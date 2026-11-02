import Foundation

enum HubNavigationPolicy {
    enum Decision: Equatable, Sendable {
        case allow
        case redirectInApp(URL)
        case download
        case openExternally(URL)
        case block
    }

    private static let metaInfraDomains: [String] = [
        "fbcdn.net",
        "fbsbx.com",
        "facebook.net",
        "accountkit.com",
        "cdninstagram.com"
    ]

    private static let commonAuthExactPaths: Set<String> = [
        "/login",
        "/login.php",
        "/checkpoint",
        "/recover",
        "/logout.php",
        "/photo",
        "/photo.php",
        "/commerce"
    ]

    private static let commonAuthAndUtilityPrefixes: [String] = [
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
        "/flx/",
        "/photo/",
        "/commerce/",
        "/messages",
        "/groupcall",
        "/rtc"
    ]

    static func decide(
        _ url: URL,
        for kind: HubAppKind,
        isMainFrame: Bool,
        isLinkActivated: Bool = false
    ) -> Decision {
        let homeURL = kind == .marketplace ? HubAppProfile.marketplace.homeURL : HubAppProfile.groups.homeURL
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

        if let unwrapped = unwrapRedirect(url) {
            if isInScopeFacebookURL(unwrapped, for: kind) {
                return .redirectInApp(unwrapped)
            }
            return .openExternally(unwrapped)
        }

        if !isMainFrame {
            if isLinkActivated && !isMetaOwnedHost(url) {
                return .openExternally(CleanLinkFormatter.cleanURL(url))
            }
            return .allow
        }

        guard let host = url.host?.lowercased() else {
            return .block
        }

        if metaInfraDomains.contains(where: { matchesDomain(host, domain: $0) }) {
            return .allow
        }

        if matchesDomain(host, domain: "messenger.com") {
            return .allow
        }

        if matchesDomain(host, domain: "facebook.com") {
            let path = url.path.lowercased()

            // Never let Facebook dump the user onto the algorithmic News Feed
            if path.isEmpty || path == "/" || path == "/home.php" || path == "/index.php" {
                return .redirectInApp(homeURL)
            }

            if isAllowedFacebookPath(path, for: kind) {
                return .allow
            }

            return .openExternally(CleanLinkFormatter.cleanURL(url))
        }

        return .openExternally(CleanLinkFormatter.cleanURL(url))
    }

    static func isAllowedFacebookPath(_ lowercasePath: String, for kind: HubAppKind) -> Bool {
        if commonAuthExactPaths.contains(lowercasePath) {
            return true
        }
        if commonAuthAndUtilityPrefixes.contains(where: { lowercasePath.hasPrefix($0) }) {
            return true
        }

        switch kind {
        case .marketplace:
            return lowercasePath == "/marketplace" || lowercasePath.hasPrefix("/marketplace/")

        case .groups:
            return lowercasePath == "/groups"
                || lowercasePath.hasPrefix("/groups/")
                || lowercasePath == "/events"
                || lowercasePath.hasPrefix("/events/")
                || lowercasePath == "/videos"
                || lowercasePath.hasPrefix("/videos/")
                || lowercasePath == "/download"
                || lowercasePath.hasPrefix("/download/")
                || lowercasePath.hasPrefix("/marketplace/item/")
        }
    }

    static func isInScopeFacebookURL(_ url: URL, for kind: HubAppKind) -> Bool {
        guard let host = url.host?.lowercased(),
              url.scheme?.lowercased() == "https",
              matchesDomain(host, domain: "facebook.com")
        else {
            return false
        }
        let path = url.path.lowercased()
        switch kind {
        case .marketplace:
            return path == "/marketplace" || path.hasPrefix("/marketplace/")
        case .groups:
            return path == "/groups" || path.hasPrefix("/groups/")
        }
    }

    static func launchURL(for kind: HubAppKind, restoreLast: Bool, lastVisitedURL: String?) -> URL {
        let defaultHome = kind == .marketplace ? HubAppProfile.marketplace.homeURL : HubAppProfile.groups.homeURL
        guard restoreLast,
              let raw = lastVisitedURL,
              let candidate = URL(string: raw),
              isInScopeFacebookURL(candidate, for: kind)
        else {
            return defaultHome
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
        return CleanLinkFormatter.cleanURL(targetURL)
    }

    private static func matchesDomain(_ host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}

enum CleanLinkFormatter {
    private static let strippedQueryKeys: Set<String> = [
        "fbclid",
        "mibextid",
        "ref",
        "referral_code",
        "referral_story_type",
        "tracking",
        "__tn__",
        "__cft__[0]",
        "idorvanity",
        "hoisted_section_header_type",
        "acontext",
        "paipv"
    ]

    /// Strips tracking noise from Marketplace item URLs, Group post permalinks, and external links.
    static func cleanURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        // Canonicalize `/marketplace/item/<id>/...` completely by dropping all referral query clutter
        if let host = components.host?.lowercased(),
           (host == "facebook.com" || host.hasSuffix(".facebook.com")),
           components.path.lowercased().hasPrefix("/marketplace/item/")
        {
            components.queryItems = nil
            components.fragment = nil
            return components.url ?? url
        }

        guard let items = components.queryItems, !items.isEmpty else {
            return url
        }

        let filtered = items.filter { item in
            let lower = item.name.lowercased()
            if strippedQueryKeys.contains(lower) {
                return false
            }
            if lower.hasPrefix("__cft__") {
                return false
            }
            return true
        }

        if filtered.count == items.count {
            return url
        }
        components.queryItems = filtered.isEmpty ? nil : filtered
        return components.url ?? url
    }
}
