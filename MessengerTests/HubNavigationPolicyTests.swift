import Foundation
import Testing

@Suite("HubNavigationPolicy & CleanLinkFormatter (Marketplace & Groups)")
struct HubNavigationPolicyTests {
    @Test("Marketplace allows listings, selling dashboard, photos, and buyer/seller chats")
    func allowsMarketplaceRoutes() {
        let urls = [
            "https://www.facebook.com/marketplace/",
            "https://www.facebook.com/marketplace/item/918273645/",
            "https://www.facebook.com/marketplace/you/selling/",
            "https://www.facebook.com/marketplace/create/item/",
            "https://www.facebook.com/photo/?fbid=12345",
            "https://www.facebook.com/messages/t/88776655/"
        ]

        for raw in urls {
            let url = URL(string: raw)!
            #expect(HubNavigationPolicy.decide(url, for: .marketplace, isMainFrame: true) == .allow)
        }
    }

    @Test("Groups allows group feeds, discussions, files, events, lightboxes, and cross-posted items")
    func allowsGroupsRoutes() {
        let urls = [
            "https://www.facebook.com/groups/feed/",
            "https://www.facebook.com/groups/joins/",
            "https://www.facebook.com/groups/discover/",
            "https://www.facebook.com/groups/swiftdevelopers/posts/11223344/",
            "https://www.facebook.com/groups/swiftdevelopers/files/",
            "https://www.facebook.com/events/99887766/",
            "https://www.facebook.com/photo/?fbid=554433",
            "https://www.facebook.com/marketplace/item/123456/"
        ]

        for raw in urls {
            let url = URL(string: raw)!
            #expect(HubNavigationPolicy.decide(url, for: .groups, isMainFrame: true) == .allow)
        }
    }

    @Test("Redirects Facebook News Feed root back into Marketplace or Groups Home")
    func blocksNewsFeedEscape() {
        let rootURL = URL(string: "https://www.facebook.com/")!
        let homePhp = URL(string: "https://www.facebook.com/home.php")!

        #expect(
            HubNavigationPolicy.decide(rootURL, for: .marketplace, isMainFrame: true)
                == .redirectInApp(HubAppProfile.marketplace.homeURL)
        )
        #expect(
            HubNavigationPolicy.decide(homePhp, for: .groups, isMainFrame: true)
                == .redirectInApp(HubAppProfile.groups.homeURL)
        )
    }

    @Test("Opens Reels, Watch, and external links outside Marketplace and Groups")
    func opensDistractionsAndExternalSitesInBrowser() {
        let reelURL = URL(string: "https://www.facebook.com/reel/123456789/")!
        let watchURL = URL(string: "https://www.facebook.com/watch/")!

        #expect(HubNavigationPolicy.decide(reelURL, for: .marketplace, isMainFrame: true) == .openExternally(reelURL))
        #expect(HubNavigationPolicy.decide(watchURL, for: .groups, isMainFrame: true) == .openExternally(watchURL))
    }

    @Test("Strips bloated referral and tracking parameters from Marketplace item and Group post URLs")
    func cleansMarketplaceAndGroupLinks() {
        let bloatedItem = URL(
            string: "https://www.facebook.com/marketplace/item/918273645/?ref=search&referral_code=null&referral_story_type=post&tracking=browse_serp%3Aabc&__cft__[0]=AZX&__tn__=-UK-R"
        )!
        #expect(
            CleanLinkFormatter.cleanURL(bloatedItem).absoluteString
                == "https://www.facebook.com/marketplace/item/918273645/"
        )

        let bloatedGroupPost = URL(
            string: "https://www.facebook.com/groups/swiftdevs/posts/445566/?__cft__[0]=AZ123&__tn__=%2CO%2CP-R&fbclid=IwAR999"
        )!
        #expect(
            CleanLinkFormatter.cleanURL(bloatedGroupPost).absoluteString
                == "https://www.facebook.com/groups/swiftdevs/posts/445566/"
        )
    }

    @Test("Matches active toolbar section indices accurately")
    func matchesActiveToolbarSections() {
        #expect(
            HubAppProfile.marketplace.activeSectionIndex(
                for: URL(string: "https://www.facebook.com/marketplace/you/selling/")
            ) == 2
        )
        #expect(
            HubAppProfile.marketplace.activeSectionIndex(
                for: URL(string: "https://www.facebook.com/marketplace/you/saved/")
            ) == 3
        )
        #expect(
            HubAppProfile.groups.activeSectionIndex(
                for: URL(string: "https://www.facebook.com/groups/discover/")
            ) == 2
        )
        // Inside a specific group discussion, none of Feed / Your Groups / Discover is falsely selected
        #expect(
            HubAppProfile.groups.activeSectionIndex(
                for: URL(string: "https://www.facebook.com/groups/swiftdevelopers/")
            ) == nil
        )
    }
}
