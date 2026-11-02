import AppKit
import AVFoundation
import Network
import WebKit

/// Weak proxy so `WKUserContentController` does not strongly retain the view controller.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
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
final class MessengerViewController: NSViewController {
    private let preferences: AppPreferences
    private let badgeController: BadgeController
    private let notificationManager: NotificationManager

    private(set) var webView: MessengerWebView!
    private var popupControllers: [ObjectIdentifier: PopupWindowController] = [:]
    private var loginWindowController: LoginWindowController?

    private var networkMonitor: NWPathMonitor?
    private var wasNetworkSatisfied = true
    private var lastWakeReloadDate = Date.distantPast

    init(
        preferences: AppPreferences,
        badgeController: BadgeController,
        notificationManager: NotificationManager
    ) {
        self.preferences = preferences
        self.badgeController = badgeController
        self.notificationManager = notificationManager
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1180, height: 780))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupRecoveryMonitors()

        preferences.onZoomChanged = { [weak self] newZoom in
            self?.webView?.pageZoom = CGFloat(newZoom)
        }

        loadInitialPage()
    }

    deinit {
        networkMonitor?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupWebView() {
        let proxy = WeakScriptMessageHandler(target: self)
        let config = WebViewConfigurationFactory.makeConfiguration(
            preferences: preferences,
            scriptMessageHandler: proxy
        )

        webView = MessengerWebView(frame: view.bounds, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = WebViewConfigurationFactory.safariUserAgent()
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

    private func setupRecoveryMonitors() {
        // Reload after Mac wakes from sleep so realtime WebSockets reconnect cleanly
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // Reload when network connectivity returns after going offline
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
        let queuePrefix = Bundle.main.bundleIdentifier ?? "com.fbmac.Messenger"
        monitor.start(queue: DispatchQueue(label: "\(queuePrefix).NetworkMonitor"))
        self.networkMonitor = monitor
    }

    @objc private func handleSystemDidWake() {
        let now = Date()
        guard now.timeIntervalSince(lastWakeReloadDate) > 10 else { return }
        lastWakeReloadDate = now
        webView.reload()
    }

    // MARK: - Navigation & Actions

    func loadInitialPage() {
        let target = NavigationPolicy.launchURL(
            restoreLast: preferences.restoreLastConversationOnLaunch,
            lastConversationURL: preferences.lastActiveConversationURL
        )
        webView.load(URLRequest(url: target))
    }

    func loadHome() {
        webView.load(URLRequest(url: NavigationPolicy.homeURL))
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

    func triggerNewMessage() {
        evaluateBridgeCall("window.__MESSENGER_BRIDGE?.newMessage();")
    }

    func focusSearch() {
        evaluateBridgeCall("window.__MESSENGER_BRIDGE?.focusSearch();")
    }

    func selectConversation(at oneBasedIndex: Int) {
        guard (1...9).contains(oneBasedIndex) else { return }
        evaluateBridgeCall("window.__MESSENGER_BRIDGE?.openChat(\(oneBasedIndex));")
    }

    func openConversation(threadId: String, href: String) {
        let target = !href.isEmpty ? href : threadId
        let escaped = target
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        evaluateBridgeCall("window.__MESSENGER_BRIDGE?.openThread(\"\(escaped)\");")
    }

    func zoomIn() {
        preferences.pageZoom = AppPreferences.clampZoom(preferences.pageZoom + 0.1)
    }

    func zoomOut() {
        preferences.pageZoom = AppPreferences.clampZoom(preferences.pageZoom - 0.1)
    }

    func resetZoom() {
        preferences.pageZoom = 1.0
    }

    func openDedicatedLoginWindow() {
        if let existing = loginWindowController {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = LoginWindowController { [weak self] in
            self?.loginWindowController = nil
            self?.loadHome()
        }
        loginWindowController = controller
        controller.showWindow(nil)
    }

    func logOut() {
        let alert = NSAlert()
        alert.messageText = "Log Out of Messenger?"
        alert.informativeText = "This clears your Messenger and Facebook session cookies in this app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Log Out")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        preferences.lastActiveConversationURL = nil
        badgeController.update(count: 0)

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

    private func evaluateBridgeCall(_ script: String) {
        webView.evaluateJavaScript(script, in: nil, in: .defaultClient, completionHandler: nil)
    }
}

// MARK: - WKScriptMessageHandler

extension MessengerViewController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == WebViewConfigurationFactory.bridgeHandlerName,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String
        else {
            return
        }

        switch type {
        case "badge":
            if let count = body["count"] as? Int {
                badgeController.update(count: count)
            }

        case "notification":
            if let parsed = ChatPreviewParser.parseNotificationPayload(body) {
                notificationManager.post(parsed)
            }

        case "activeConversation":
            if let urlString = body["url"] as? String,
               let url = URL(string: urlString),
               NavigationPolicy.isConversationURL(url)
            {
                preferences.lastActiveConversationURL = url.absoluteString
            }

        default:
            break
        }
    }
}

// MARK: - WKNavigationDelegate

extension MessengerViewController: WKNavigationDelegate {
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

        switch NavigationPolicy.decide(url, isMainFrame: isMainFrame, isLinkActivated: isLinkActivated) {
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url, NavigationPolicy.isConversationURL(url) {
            preferences.lastActiveConversationURL = url.absoluteString
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Automatically recover if macOS terminates the WebContent process under memory pressure
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

extension MessengerViewController: WKUIDelegate {
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

            switch NavigationPolicy.decide(url, isMainFrame: true, isLinkActivated: true) {
            case .openExternally(let target):
                NSWorkspace.shared.open(target)
                return nil
            case .block:
                return nil
            case .download:
                webView.load(navigationAction.request)
                return nil
            case .allow, .redirectInApp:
                break
            }
        }

        // Open internal Meta popups (audio/video calls, 2FA/OAuth dialogs) in a dedicated native window
        // sharing the provided WKWebViewConfiguration so `window.opener` and WebRTC sessions stay intact.
        let popup = PopupWindowController(
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
        guard host.hasSuffix("facebook.com") || host == "facebook.com"
            || host.hasSuffix("messenger.com") || host == "messenger.com"
        else {
            decisionHandler(.deny)
            return
        }

        let requiredMediaTypes: [AVMediaType]
        switch type {
        case .camera:
            requiredMediaTypes = [.video]
        case .microphone:
            requiredMediaTypes = [.audio]
        case .cameraAndMicrophone:
            requiredMediaTypes = [.video, .audio]
        @unknown default:
            requiredMediaTypes = []
        }

        Task { @MainActor in
            let granted = await Self.requestAVPermissions(for: requiredMediaTypes)
            if granted {
                decisionHandler(.grant)
            } else {
                decisionHandler(.deny)
                Self.presentMediaPermissionAlert(for: type)
            }
        }
    }

    private static func requestAVPermissions(for mediaTypes: [AVMediaType]) async -> Bool {
        for mediaType in mediaTypes {
            switch AVCaptureDevice.authorizationStatus(for: mediaType) {
            case .authorized:
                continue
            case .notDetermined:
                let allowed = await AVCaptureDevice.requestAccess(for: mediaType)
                if !allowed { return false }
            case .denied, .restricted:
                return false
            @unknown default:
                return false
            }
        }
        return true
    }

    private static func presentMediaPermissionAlert(for type: WKMediaCaptureType) {
        let label: String
        let paneAnchor: String
        switch type {
        case .camera:
            label = "Camera"
            paneAnchor = "Privacy_Camera"
        case .microphone:
            label = "Microphone"
            paneAnchor = "Privacy_Microphone"
        case .cameraAndMicrophone:
            label = "Camera and Microphone"
            paneAnchor = "Privacy_Camera"
        @unknown default:
            label = "Media Device"
            paneAnchor = "Privacy"
        }

        let alert = NSAlert()
        alert.messageText = "\(label) Access Required"
        alert.informativeText = "Enable \(label.lowercased()) access for Messenger in System Settings → Privacy & Security to make voice or video calls."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(paneAnchor)")
        {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - WKDownloadDelegate

extension MessengerViewController: WKDownloadDelegate {
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
