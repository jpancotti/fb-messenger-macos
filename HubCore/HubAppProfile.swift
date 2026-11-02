import Foundation

enum HubAppKind: String, Sendable {
    case marketplace
    case groups
}

struct HubSection: Equatable, Sendable {
    let id: String
    let title: String
    let menuTitle: String
    let symbolName: String
    let url: URL
    let shortcutKey: String
    let matchPrefixes: [String]
}

struct HubAppProfile: Sendable {
    let kind: HubAppKind
    let appName: String
    let menuBarSymbol: String
    let homeURL: URL
    let primaryActionTitle: String
    let primaryActionToolbarLabel: String
    let primaryActionSymbol: String
    let primaryActionFallbackURL: URL
    let secondaryCreateTitle: String?
    let secondaryCreateURL: URL?
    let searchMenuTitle: String
    let sections: [HubSection]

    func activeSectionIndex(for url: URL?) -> Int? {
        guard let url, let host = url.host?.lowercased(),
              host == "facebook.com" || host.hasSuffix(".facebook.com")
        else {
            return nil
        }
        let path = url.path.lowercased()

        // Match more specific prefixes before generic root section prefixes
        var bestIndex: Int?
        var bestLength = -1

        for (idx, section) in sections.enumerated() {
            for prefix in section.matchPrefixes {
                let normalized = prefix.lowercased()
                if path == normalized || path == normalized + "/" || path.hasPrefix(normalized + "/") {
                    if normalized.count > bestLength {
                        bestLength = normalized.count
                        bestIndex = idx
                    }
                }
            }
        }
        return bestIndex
    }

    static let marketplace = HubAppProfile(
        kind: .marketplace,
        appName: "Marketplace",
        menuBarSymbol: "storefront.fill",
        homeURL: URL(string: "https://www.facebook.com/marketplace/")!,
        primaryActionTitle: "Create New Listing…",
        primaryActionToolbarLabel: "Sell",
        primaryActionSymbol: "plus.circle.fill",
        primaryActionFallbackURL: URL(string: "https://www.facebook.com/marketplace/create/item/")!,
        secondaryCreateTitle: nil,
        secondaryCreateURL: nil,
        searchMenuTitle: "Search Marketplace…",
        sections: [
            HubSection(
                id: "browse",
                title: "Browse",
                menuTitle: "Browse Marketplace",
                symbolName: "storefront",
                url: URL(string: "https://www.facebook.com/marketplace/")!,
                shortcutKey: "1",
                matchPrefixes: ["/marketplace", "/marketplace/category", "/marketplace/search", "/marketplace/item"]
            ),
            HubSection(
                id: "buying",
                title: "Buying",
                menuTitle: "Buying",
                symbolName: "bag",
                url: URL(string: "https://www.facebook.com/marketplace/you/buying/")!,
                shortcutKey: "2",
                matchPrefixes: ["/marketplace/you/buying"]
            ),
            HubSection(
                id: "selling",
                title: "Selling",
                menuTitle: "Selling Dashboard",
                symbolName: "tag",
                url: URL(string: "https://www.facebook.com/marketplace/you/selling/")!,
                shortcutKey: "3",
                matchPrefixes: ["/marketplace/you/selling", "/marketplace/you/dashboard"]
            ),
            HubSection(
                id: "saved",
                title: "Saved",
                menuTitle: "Saved Listings",
                symbolName: "bookmark",
                url: URL(string: "https://www.facebook.com/marketplace/you/saved/")!,
                shortcutKey: "4",
                matchPrefixes: ["/marketplace/you/saved"]
            ),
            HubSection(
                id: "inbox",
                title: "Inbox",
                menuTitle: "Marketplace Inbox",
                symbolName: "tray",
                url: URL(string: "https://www.facebook.com/marketplace/inbox/")!,
                shortcutKey: "5",
                matchPrefixes: ["/marketplace/inbox", "/marketplace/notifications"]
            )
        ]
    )

    static let groups = HubAppProfile(
        kind: .groups,
        appName: "Groups",
        menuBarSymbol: "person.3.fill",
        homeURL: URL(string: "https://www.facebook.com/groups/feed/")!,
        primaryActionTitle: "New Post in Group",
        primaryActionToolbarLabel: "New Post",
        primaryActionSymbol: "square.and.pencil",
        primaryActionFallbackURL: URL(string: "https://www.facebook.com/groups/feed/")!,
        secondaryCreateTitle: "Create New Group…",
        secondaryCreateURL: URL(string: "https://www.facebook.com/groups/create/")!,
        searchMenuTitle: "Search Groups…",
        sections: [
            HubSection(
                id: "feed",
                title: "Feed",
                menuTitle: "Your Groups Feed",
                symbolName: "rectangle.stack",
                url: URL(string: "https://www.facebook.com/groups/feed/")!,
                shortcutKey: "1",
                matchPrefixes: ["/groups/feed"]
            ),
            HubSection(
                id: "joins",
                title: "Your Groups",
                menuTitle: "Your Groups",
                symbolName: "person.3",
                url: URL(string: "https://www.facebook.com/groups/joins/")!,
                shortcutKey: "2",
                matchPrefixes: ["/groups/joins"]
            ),
            HubSection(
                id: "discover",
                title: "Discover",
                menuTitle: "Discover Groups",
                symbolName: "safari",
                url: URL(string: "https://www.facebook.com/groups/discover/")!,
                shortcutKey: "3",
                matchPrefixes: ["/groups/discover"]
            )
        ]
    )
}
