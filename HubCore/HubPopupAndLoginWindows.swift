import AppKit
import WebKit

/// Hosts internal Meta `window.open` popups (OAuth, photo/attachment viewers, buyer/seller call dialogs).
@MainActor
final class HubPopupWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    let webView: WKWebView
    private let appKind: HubAppKind
    var onClose: (() -> Void)?
    private var titleObservation: NSKeyValueObservation?

    init(
        appName: String,
        appKind: HubAppKind,
        configuration: WKWebViewConfiguration,
        windowFeatures: WKWindowFeatures,
        uiDelegate: WKUIDelegate
    ) {
        self.appKind = appKind
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView.customUserAgent = HubWebViewController.safariUserAgent()
        self.webView.uiDelegate = uiDelegate

        let width = max(500, windowFeatures.width?.doubleValue ?? 960)
        let height = max(440, windowFeatures.height?.doubleValue ?? 720)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = appName
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.center()

        super.init(window: window)
        window.delegate = self
        webView.navigationDelegate = self

        titleObservation = webView.observe(\.title, options: [.new]) { [weak window] observed, _ in
            MainActor.assumeIsolated {
                if let newTitle = observed.title, !newTitle.isEmpty {
                    window?.title = newTitle
                }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func windowWillClose(_ notification: Notification) {
        titleObservation?.invalidate()
        titleObservation = nil
        webView.stopLoading()
        onClose?()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if let unwrapped = HubNavigationPolicy.unwrapRedirect(url) {
            NSWorkspace.shared.open(unwrapped)
            decisionHandler(.cancel)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        if (scheme == "http" || scheme == "https")
            && !HubNavigationPolicy.isMetaOwnedHost(url)
            && navigationAction.navigationType == .linkActivated
        {
            NSWorkspace.shared.open(CleanLinkFormatter.cleanURL(url))
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}

/// Optional clean Sign-In window sharing `WKWebsiteDataStore.default()`.
@MainActor
final class HubLoginWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private let webView: WKWebView
    private var onComplete: (() -> Void)?
    private var didComplete = false

    init(profile: HubAppProfile, onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.customUserAgent = HubWebViewController.safariUserAgent()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign In to \(profile.appName)"
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.center()

        super.init(window: window)
        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self

        let encodedNext = profile.homeURL.absoluteString
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let loginURL = URL(string: "https://www.facebook.com/login.php?next=\(encodedNext)") {
            webView.load(URLRequest(url: loginURL))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func windowWillClose(_ notification: Notification) {
        webView.stopLoading()
        if !didComplete {
            didComplete = true
            onComplete?()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if navigationAction.navigationType == .linkActivated && !HubNavigationPolicy.isMetaOwnedHost(url) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, HubNavigationPolicy.isMetaOwnedHost(url) else { return }
        let path = url.path.lowercased()

        let inProgressPrefixes = [
            "/login", "/checkpoint", "/two_step_verification", "/authn",
            "/recover", "/cookie", "/privacy/consent", "/dialog", "/auth"
        ]
        if inProgressPrefixes.contains(where: { path.hasPrefix($0) }) {
            return
        }

        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            let hasSession = cookies.contains { cookie in
                cookie.domain.contains("facebook.com") && cookie.name == "c_user"
            }
            guard hasSession else { return }
            Task { @MainActor [weak self] in
                guard let self, !self.didComplete else { return }
                self.didComplete = true
                self.close()
                self.onComplete?()
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
