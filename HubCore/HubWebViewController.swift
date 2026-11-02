import AppKit
import AVFoundation
import Network
@preconcurrency import UserNotifications
import WebKit

private final class WeakHubScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

@MainActor
final class HubWebViewController: NSViewController, UNUserNotificationCenterDelegate {
    static let bridgeHandlerName = "hubBridge"

    let profile: HubAppProfile
    let preferences: HubPreferences

    private(set) var webView: WKWebView!
    private var popupControllers: [ObjectIdentifier: HubPopupWindowController] = [:]
    private var loginWindowController: HubLoginWindowController?

    private var urlObservation: NSKeyValueObservation?
    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?

    private var networkMonitor: NWPathMonitor?
    private var wasNetworkSatisfied = true
    private var lastWakeReloadDate = Date.distantPast

    var onNavigationStateChanged: ((URL?, Bool, Bool) -> Void)?
    var onActivateMainWindowRequested: (() -> Void)?

    private var canUseNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    init(profile: HubAppProfile, preferences: HubPreferences) {
        self.profile = profile
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1260, height: 840))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupObservations()
        setupRecoveryMonitors()
        setupNotifications()

        preferences.onZoomChanged = { [weak self] newZoom in
            self?.webView?.pageZoom = CGFloat(newZoom)
        }

        loadInitialPage()
    }

    deinit {
        networkMonitor?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    static func safariUserAgent() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let safariMajor = max(18, v.majorVersion)
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safariMajor).0 Safari/605.1.15"
    }

    // MARK: - Setup

    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        if preferences.developerExtrasEnabled {
            configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        }

        let contentController = WKUserContentController()
        contentController.add(
            WeakHubScriptMessageHandler(target: self),
            contentWorld: .defaultClient,
            name: Self.bridgeHandlerName
        )

        if let preloadJS = Self.loadBundledScript(name: "hub_preload", ext: "js") {
            contentController.addUserScript(
                WKUserScript(
                    source: preloadJS,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true,
                    in: .page
                )
            )
        }

        if let cssSource = Self.loadBundledScript(name: "hub", ext: "css") {
            let escapedCSS = cssSource
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            let cssInjector = """
            (function() {
                const inject = () => {
                    if (document.getElementById('__hub_native_css')) return;
                    const style = document.createElement('style');
                    style.id = '__hub_native_css';
                    style.textContent = `\(escapedCSS)`;
                    (document.head || document.documentElement).appendChild(style);
                };
                inject();
                document.addEventListener('DOMContentLoaded', inject, { once: true });
            })();
            """
            contentController.addUserScript(
                WKUserScript(
                    source: cssInjector,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true,
                    in: .page
                )
            )
        }

        if let bridgeJS = Self.loadBundledScript(name: "hub_bridge", ext: "js") {
            contentController.addUserScript(
                WKUserScript(
                    source: bridgeJS,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true,
                    in: .defaultClient
                )
            )
        }

        configuration.userContentController = contentController

        webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = Self.safariUserAgent()
        webView.pageZoom = CGFloat(preferences.pageZoom)

        if preferences.developerExtrasEnabled, webView.responds(to: Selector(("setInspectable:"))) {
            webView.isInspectable = true
        }

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupObservations() {
        let notifyChange: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            if let currentURL = self.webView.url,
               HubNavigationPolicy.isInScopeFacebookURL(currentURL, for: self.profile.kind)
            {
                self.preferences.lastVisitedURL = CleanLinkFormatter.cleanURL(currentURL).absoluteString
            }
            self.onNavigationStateChanged?(
                self.webView.url,
                self.webView.canGoBack,
                self.webView.canGoForward
            )
        }

        urlObservation = webView.observe(\.url, options: [.new]) { _, _ in
            MainActor.assumeIsolated { notifyChange() }
        }
        canGoBackObservation = webView.observe(\.canGoBack, options: [.new]) { _, _ in
            MainActor.assumeIsolated { notifyChange() }
        }
        canGoForwardObservation = webView.observe(\.canGoForward, options: [.new]) { _, _ in
            MainActor.assumeIsolated { notifyChange() }
        }
    }

    private func setupRecoveryMonitors() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let isSatisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.wasNetworkSatisfied && isSatisfied {
                    self.webView.reload()
                }
                self.wasNetworkSatisfied = isSatisfied
            }
        }
        let queuePrefix = Bundle.main.bundleIdentifier ?? "com.fbmac.\(profile.appName)"
        monitor.start(queue: DispatchQueue(label: "\(queuePrefix).NetworkMonitor"))
        self.networkMonitor = monitor
    }

    private func setupNotifications() {
        guard canUseNotifications else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    @objc private func handleSystemDidWake() {
        let now = Date()
        guard now.timeIntervalSince(lastWakeReloadDate) > 10 else { return }
        lastWakeReloadDate = now
        webView.reload()
    }

    private static func loadBundledScript(name: String, ext: String) -> String? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources")
        {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return nil
    }

    // MARK: - Actions

    func loadInitialPage() {
        let target = HubNavigationPolicy.launchURL(
            for: profile.kind,
            restoreLast: preferences.restoreLastPageOnLaunch,
            lastVisitedURL: preferences.lastVisitedURL
        )
        webView.load(URLRequest(url: target))
    }

    func loadHome() {
        webView.load(URLRequest(url: profile.homeURL))
    }

    func navigateToSection(at index: Int) {
        guard profile.sections.indices.contains(index) else { return }
        let target = profile.sections[index].url.absoluteString
        let escaped = target
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        evaluateBridge("window.__HUB_BRIDGE?.navigateSection(\"\(escaped)\");")
    }

    func triggerPrimaryAction() {
        let mode = profile.kind.rawValue
        let fallback = profile.primaryActionFallbackURL.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        evaluateBridge("window.__HUB_BRIDGE?.triggerPrimaryAction(\"\(mode)\", \"\(fallback)\");")
    }

    func triggerSecondaryCreate() {
        guard let url = profile.secondaryCreateURL else { return }
        webView.load(URLRequest(url: url))
    }

    func focusSearch() {
        evaluateBridge("window.__HUB_BRIDGE?.focusSearch();")
    }

    func reload() {
        if webView.url == nil {
            loadInitialPage()
        } else {
            webView.reload()
        }
    }

    func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }

    @discardableResult
    func copyCleanCurrentURL() -> URL? {
        let rawURL = webView.url ?? profile.homeURL
        let cleaned = CleanLinkFormatter.cleanURL(rawURL)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(cleaned.absoluteString, forType: .string)
        return cleaned
    }

    func openCurrentPageInBrowser() {
        let rawURL = webView.url ?? profile.homeURL
        NSWorkspace.shared.open(CleanLinkFormatter.cleanURL(rawURL))
    }

    func zoomIn() {
        preferences.pageZoom = HubPreferences.clampZoom(preferences.pageZoom + 0.1)
    }

    func zoomOut() {
        preferences.pageZoom = HubPreferences.clampZoom(preferences.pageZoom - 0.1)
    }

    func resetZoom() {
        preferences.pageZoom = 1.0
    }

    func openDedicatedLoginWindow() {
        if let existing = loginWindowController {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = HubLoginWindowController(profile: profile) { [weak self] in
            self?.loginWindowController = nil
            self?.loadHome()
        }
        loginWindowController = controller
        controller.showWindow(nil)
    }

    func logOut() {
        let alert = NSAlert()
        alert.messageText = "Log Out of \(profile.appName)?"
        alert.informativeText = "This clears your Facebook session cookies in \(profile.appName)."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Log Out")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        preferences.lastVisitedURL = nil
        let store = WKWebsiteDataStore.default()
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: allTypes) { [weak self] records in
            let metaRecords = records.filter { record in
                record.displayName.contains("facebook") || record.displayName.contains("messenger")
            }
            store.removeData(ofTypes: allTypes, for: metaRecords) {
                Task { @MainActor [weak self] in
                    self?.loadHome()
                }
            }
        }
    }

    private func evaluateBridge(_ script: String) {
        webView.evaluateJavaScript(script, in: nil, in: .defaultClient, completionHandler: nil)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let targetURLString = response.notification.request.content.userInfo["url"] as? String
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onActivateMainWindowRequested?()
            if let targetURLString,
               let url = URL(string: targetURLString),
               HubNavigationPolicy.isInScopeFacebookURL(url, for: self.profile.kind)
            {
                self.webView.load(URLRequest(url: url))
            }
        }
        completionHandler()
    }
}

// MARK: - WKScriptMessageHandler

extension HubWebViewController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.bridgeHandlerName,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String
        else {
            return
        }

        if type == "notification", canUseNotifications, !preferences.notificationsMuted {
            let title = ((body["title"] as? String) ?? profile.appName)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let text = ((body["body"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tag = (body["tag"] as? String) ?? UUID().uuidString
            let url = (body["url"] as? String) ?? profile.homeURL.absoluteString

            guard !title.isEmpty || !text.isEmpty else { return }

            let content = UNMutableNotificationContent()
            content.title = title.isEmpty ? profile.appName : title
            content.body = text
            content.sound = .default
            content.userInfo = ["url": url]

            let request = UNNotificationRequest(identifier: "hub-\(tag)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}

// MARK: - WKNavigationDelegate

extension HubWebViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        let isLinkActivated = navigationAction.navigationType == .linkActivated

        switch HubNavigationPolicy.decide(
            url,
            for: profile.kind,
            isMainFrame: isMainFrame,
            isLinkActivated: isLinkActivated
        ) {
        case .allow:
            decisionHandler(.allow)
        case .redirectInApp(let targetURL):
            decisionHandler(.cancel)
            webView.load(URLRequest(url: targetURL))
        case .download:
            decisionHandler(.download)
        case .openExternally(let externalURL):
            NSWorkspace.shared.open(externalURL)
            decisionHandler(.cancel)
        case .block:
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
}

// MARK: - WKUIDelegate

extension HubWebViewController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if url.scheme?.lowercased() == "blob" {
                webView.load(navigationAction.request)
                return nil
            }

            switch HubNavigationPolicy.decide(
                url,
                for: profile.kind,
                isMainFrame: true,
                isLinkActivated: true
            ) {
            case .openExternally(let target):
                NSWorkspace.shared.open(target)
                return nil
            case .block:
                return nil
            case .download:
                webView.load(navigationAction.request)
                return nil
            case .redirectInApp(let target):
                webView.load(URLRequest(url: target))
                return nil
            case .allow:
                // Regular in-scope target="_blank" links (e.g. clicking a Marketplace listing card or Group permalink)
                // should open smoothly in the main window rather than spawning a second window unless JS requested popup dimensions.
                let isExplicitPopup = windowFeatures.width != nil || windowFeatures.height != nil
                if !isExplicitPopup {
                    webView.load(URLRequest(url: url))
                    return nil
                }
            }
        }

        let popup = HubPopupWindowController(
            appName: profile.appName,
            appKind: profile.kind,
            configuration: configuration,
            windowFeatures: windowFeatures,
            uiDelegate: self
        )
        let id = ObjectIdentifier(popup)
        popup.onClose = { [weak self] in
            self?.popupControllers.removeValue(forKey: id)
        }
        popupControllers[id] = popup
        popup.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        return popup.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let match = popupControllers.values.first(where: { $0.webView === webView }) {
            match.close()
        }
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true

        if let hostWindow = webView.window {
            panel.beginSheetModal(for: hostWindow) { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        } else {
            completionHandler(panel.runModal() == .OK ? panel.urls : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        let host = origin.host.lowercased()
        guard host == "facebook.com" || host.hasSuffix(".facebook.com")
            || host == "messenger.com" || host.hasSuffix(".messenger.com")
        else {
            decisionHandler(.deny)
            return
        }

        let mediaTypes: [AVMediaType]
        switch type {
        case .camera:
            mediaTypes = [.video]
        case .microphone:
            mediaTypes = [.audio]
        case .cameraAndMicrophone:
            mediaTypes = [.video, .audio]
        @unknown default:
            mediaTypes = []
        }

        Task { @MainActor in
            for mediaType in mediaTypes {
                switch AVCaptureDevice.authorizationStatus(for: mediaType) {
                case .authorized:
                    continue
                case .notDetermined:
                    if !(await AVCaptureDevice.requestAccess(for: mediaType)) {
                        decisionHandler(.deny)
                        return
                    }
                default:
                    decisionHandler(.deny)
                    return
                }
            }
            decisionHandler(.grant)
        }
    }
}

// MARK: - WKDownloadDelegate

extension HubWebViewController: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true

        if let hostWindow = view.window {
            panel.beginSheetModal(for: hostWindow) { result in
                completionHandler(result == .OK ? panel.url : nil)
            }
        } else {
            completionHandler(panel.runModal() == .OK ? panel.url : nil)
        }
    }
}
