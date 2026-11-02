import AppKit
import WebKit

/// Optional clean Sign-In window (Messenger → Sign In Window…) sharing `WKWebsiteDataStore.default()`
/// that allows unrestricted Facebook auth/2FA/passkey redirects and automatically closes upon authentication.
@MainActor
final class LoginWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private let webView: WKWebView
    private var onComplete: (() -> Void)?
    private var didComplete = false

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.customUserAgent = WebViewConfigurationFactory.safariUserAgent()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign In to Messenger"
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.center()

        super.init(window: window)
        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self

        if let loginURL = URL(string: "https://www.facebook.com/login.php?next=https%3A%2F%2Fwww.facebook.com%2Fmessages%2F") {
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
        if navigationAction.navigationType == .linkActivated && !NavigationPolicy.isMetaOwnedHost(url) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, NavigationPolicy.isMetaOwnedHost(url) else { return }
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
