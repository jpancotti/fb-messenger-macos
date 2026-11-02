import Foundation
import WebKit

@MainActor
enum WebViewConfigurationFactory {
    static let bridgeHandlerName = "messengerBridge"

    static func makeConfiguration(
        preferences: AppPreferences,
        scriptMessageHandler: WKScriptMessageHandler
    ) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        if preferences.developerExtrasEnabled {
            configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        }

        let contentController = WKUserContentController()
        contentController.add(
            scriptMessageHandler,
            contentWorld: .defaultClient,
            name: bridgeHandlerName
        )

        // 1. Preload script (.page world at documentStart): SharedWorker fix, audio polish, Notification shim, route attribute
        if let preloadSource = loadBundledResource(name: "preload", ext: "js") {
            contentController.addUserScript(
                WKUserScript(
                    source: preloadSource,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true,
                    in: .page
                )
            )
        }

        // 2. Scoped Messenger CSS (.page world at documentStart)
        if let cssSource = loadBundledResource(name: "messenger", ext: "css") {
            let escapedCSS = cssSource
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            let cssInjector = """
            (function() {
                const inject = () => {
                    if (document.getElementById('__msgr_native_css')) return;
                    const style = document.createElement('style');
                    style.id = '__msgr_native_css';
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

        // 3. Isolated bridge script (.defaultClient world at documentEnd)
        if let bridgeSource = loadBundledResource(name: "bridge", ext: "js") {
            contentController.addUserScript(
                WKUserScript(
                    source: bridgeSource,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true,
                    in: .defaultClient
                )
            )
        }

        configuration.userContentController = contentController
        return configuration
    }

    static func safariUserAgent() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let safariMajor = max(18, v.majorVersion)
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safariMajor).0 Safari/605.1.15"
    }

    private static func loadBundledResource(name: String, ext: String) -> String? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Scripts")
        {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return nil
    }
}
