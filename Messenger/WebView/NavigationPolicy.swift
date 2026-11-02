import Foundation

enum NavigationPolicy {
    enum Decision: Equatable, Sendable {
        case allow
        case redirectInApp(URL)
        case download
        case openExternally(URL)
        case block
    }

    static let homeURL = URL(string: "https://www.facebook.com/messages/")!

    private static let metaInfraDomains: [String] = [
        "fbcdn.net",
        "fbsbx.com",
        "facebook.net",
        "accountkit.com",
        "cdninstagram.com"
    ]

    private static let allowedFacebookExactPaths: Set<String> = [
        "/messages",
        "/login",
        "/login.php",
        "/checkpoint",
        "/recover",
        "/logout.php"
    ]

    private static let allowedFacebookPathPrefixes: [String] = [
        "/messages/",
        "/t/",
        "/e2ee/",
        "/groupcall",
        "/rtc",
        "/call",
        "/messenger_media",
        "/login/",
        "/checkpoint/",
        "/two_step_verification",
        "/authn",
        "/auth/",
        "/recover/",
        "/cookie/",
        "/privacy/consent",
        "/consent/",
        "/dialog/",
        "/v2.",
        "/v1",
        "/security/",
        "/logout",
        "/ajax/",
        "/intern/",
        "/flx/"
    ]

    static func decide(
        _ url: URL,
        isMainFrame: Bool,
        isLinkActivated: Bool = false
    ) -> Decision {
        let scheme = url.scheme?.lowercased()

        switch scheme {
        case "blob":
            return isMainFrame ? .download : .allow
        case "about":
            let raw = url.absoluteString.lowercased()
            if !isMainFrame || raw == "about:blank" || raw == "about:srcdoc" {
                return .allow
            }
            return .block
        case "data":
            return isMainFrame ? .block : .allow
        case "javascript":
            return .block
        case "http", "https":
            break
        case nil:
            return .allow
        default:
            return isLinkActivated ? .openExternally(url) : .block
        }

        // Unwrap l.facebook.com / lm.facebook.com / l.messenger.com tracking shims first
        if let unwrapped = unwrapRedirect(url) {
            if isConversationURL(unwrapped) {
                return .redirectInApp(unwrapped)
            }
            return .openExternally(unwrapped)
        }

        // Allow embedded subframes (2FA CAPTCHAs, media players, workers) unless the user explicitly clicked an external link
        if !isMainFrame {
            if isLinkActivated && !isMetaOwnedHost(url) {
                return .openExternally(stripTrackingParams(url))
            }
            return .allow
        }

        guard let host = url.host?.lowercased() else {
            return .block
        }

        if matchesDomain(host, domain: "messenger.com") {
            return .allow
        }

        if metaInfraDomains.contains(where: { matchesDomain(host, domain: $0) }) {
            return .allow
        }

        if matchesDomain(host, domain: "facebook.com") {
            let path = url.path.lowercased()
            if path.isEmpty || path == "/" || path == "/home.php" || path == "/index.php" {
                return .redirectInApp(homeURL)
            }
            if isAllowedFacebookInAppPath(path) {
                return .allow
            }
            return .openExternally(stripTrackingParams(url))
        }

        return .openExternally(stripTrackingParams(url))
    }

    static func isAllowedFacebookInAppPath(_ lowercasePath: String) -> Bool {
        if allowedFacebookExactPaths.contains(lowercasePath) {
            return true
        }
        return allowedFacebookPathPrefixes.contains { lowercasePath.hasPrefix($0) }
    }

    static func isConversationURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              url.scheme?.lowercased() == "https"
        else {
            return false
        }
        let path = url.path.lowercased()
        if matchesDomain(host, domain: "facebook.com") {
            return path.hasPrefix("/messages/t/") || path.hasPrefix("/messages/e2ee/t/")
        }
        if matchesDomain(host, domain: "messenger.com") {
            return path.hasPrefix("/t/") || path.hasPrefix("/e2ee/t/")
        }
        return false
    }

    static func launchURL(restoreLast: Bool, lastConversationURL: String?) -> URL {
        guard restoreLast,
              let raw = lastConversationURL,
              let candidate = URL(string: raw),
              isConversationURL(candidate)
        else {
            return homeURL
        }
        return candidate
    }

    static func isMetaOwnedHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if matchesDomain(host, domain: "facebook.com") || matchesDomain(host, domain: "messenger.com") {
            return true
        }
        return metaInfraDomains.contains { matchesDomain(host, domain: $0) }
    }

    static func isAllowedAvatarURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && isMetaOwnedHost(url)
    }

    static func unwrapRedirect(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              (host == "l.facebook.com" || host == "lm.facebook.com" || host == "l.messenger.com"),
              url.path == "/l.php",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawTarget = components.queryItems?.first(where: { $0.name == "u" })?.value,
              let targetURL = URL(string: rawTarget),
              let targetScheme = targetURL.scheme?.lowercased(),
              targetScheme == "http" || targetScheme == "https"
        else {
            return nil
        }
        return stripTrackingParams(targetURL)
    }

    static func stripTrackingParams(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              !items.isEmpty
        else {
            return url
        }
        let filtered = items.filter { item in
            let name = item.name.lowercased()
            return name != "fbclid" && name != "__cft__[0]" && name != "__tn__"
        }
        if filtered.count == items.count {
            return url
        }
        components.queryItems = filtered.isEmpty ? nil : filtered
        return components.url ?? url
    }

    private static func matchesDomain(_ host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}
