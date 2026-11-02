import AppKit
import WebKit

/// Hosts internal Meta `window.open` popups (voice/video calls, 2FA/security dialogs, attachment viewers)
/// while keeping `window.opener` and camera/microphone delegation intact.
@MainActor
final class PopupWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    let webView: WKWebView
    var onClose: (() -> Void)?
    private var titleObservation: NSKeyValueObservation?

    init(
        configuration: WKWebViewConfiguration,
        windowFeatures: WKWindowFeatures,
        uiDelegate: WKUIDelegate
    ) {
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView.customUserAgent = WebViewConfigurationFactory.safariUserAgent()
        self.webView.uiDelegate = uiDelegate

        let width = max(480, windowFeatures.width?.doubleValue ?? 960)
        let height = max(420, windowFeatures.height?.doubleValue ?? 700)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Messenger Call"
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.center()

        super.init(window: window)
        window.delegate = self
        webView.navigationDelegate = self

        titleObservation = webView.observe(\.title, options: [.new]) { [weak window] observedWebView, _ in
            MainActor.assumeIsolated {
                if let newTitle = observedWebView.title, !newTitle.isEmpty {
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

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if let unwrapped = NavigationPolicy.unwrapRedirect(url) {
            NSWorkspace.shared.open(unwrapped)
            decisionHandler(.cancel)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        if (scheme == "http" || scheme == "https") && !NavigationPolicy.isMetaOwnedHost(url)
            && navigationAction.navigationType == .linkActivated
        {
            NSWorkspace.shared.open(NavigationPolicy.stripTrackingParams(url))
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}
