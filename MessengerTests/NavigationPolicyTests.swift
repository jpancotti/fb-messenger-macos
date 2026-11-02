import Foundation
import Testing
@testable import Messenger

@Suite("NavigationPolicy")
struct NavigationPolicyTests {
    @Test("Allows Messenger conversation and home routes on facebook.com and messenger.com")
    func allowsMessengerRoutes() {
        let urls = [
            "https://www.facebook.com/messages/",
            "https://www.facebook.com/messages/t/1234567890/",
            "https://www.facebook.com/messages/e2ee/t/987654321/",
            "https://www.messenger.com/",
            "https://www.messenger.com/t/1234567890"
        ]
        for raw in urls {
            let url = URL(string: raw)!
            #expect(NavigationPolicy.decide(url, isMainFrame: true) == .allow)
        }
    }

    @Test("Redirects Facebook root News Feed landings back into /messages/")
    func redirectsFacebookHomeToMessages() {
        let rootURL = URL(string: "https://www.facebook.com/")!
        let homePhpURL = URL(string: "https://www.facebook.com/home.php")!

        #expect(NavigationPolicy.decide(rootURL, isMainFrame: true) == .redirectInApp(NavigationPolicy.homeURL))
        #expect(NavigationPolicy.decide(homePhpURL, isMainFrame: true) == .redirectInApp(NavigationPolicy.homeURL))
    }

    @Test("Allows login, 2FA checkpoint, and audio/video call routes in-app")
    func allowsAuthAndCallRoutes() {
        let urls = [
            "https://www.facebook.com/login.php?next=https%3A%2F%2Fwww.facebook.com%2Fmessages%2F",
            "https://www.facebook.com/checkpoint/1501092823525282/",
            "https://www.facebook.com/two_step_verification/two_factor/",
            "https://www.facebook.com/groupcall/ROOM:123456/"
        ]
        for raw in urls {
            let url = URL(string: raw)!
            #expect(NavigationPolicy.decide(url, isMainFrame: true) == .allow)
        }
    }

    @Test("Opens non-Messenger Facebook pages and external sites in default browser")
    func opensNonMessengerPagesExternally() {
        let reelURL = URL(string: "https://www.facebook.com/reel/1122334455/")!
        let marketplaceURL = URL(string: "https://www.facebook.com/marketplace/")!
        let externalURL = URL(string: "https://github.com/apple/swift?fbclid=IwAR12345")!

        #expect(NavigationPolicy.decide(reelURL, isMainFrame: true) == .openExternally(reelURL))
        #expect(NavigationPolicy.decide(marketplaceURL, isMainFrame: true) == .openExternally(marketplaceURL))
        #expect(
            NavigationPolicy.decide(externalURL, isMainFrame: true)
                == .openExternally(URL(string: "https://github.com/apple/swift")!)
        )
    }

    @Test("Unwraps l.facebook.com and l.messenger.com link shims and strips fbclid")
    func unwrapsLinkShims() {
        let wrapped = URL(
            string: "https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2Farticle%3Fid%3D7%26fbclid%3DIwAR999&h=AT123"
        )!
        let expected = URL(string: "https://example.com/article?id=7")!

        #expect(NavigationPolicy.decide(wrapped, isMainFrame: true, isLinkActivated: true) == .openExternally(expected))
    }

    @Test("Blocks top-level data and javascript URLs and downloads top-level blob URLs")
    func handlesSpecialSchemes() {
        let dataURL = URL(string: "data:text/html,<h1>phish</h1>")!
        let jsURL = URL(string: "javascript:alert(1)")!
        let blobURL = URL(string: "blob:https://www.facebook.com/550e8400-e29b-41d4-a716-446655440000")!

        #expect(NavigationPolicy.decide(dataURL, isMainFrame: true) == .block)
        #expect(NavigationPolicy.decide(dataURL, isMainFrame: false) == .allow)
        #expect(NavigationPolicy.decide(jsURL, isMainFrame: true) == .block)
        #expect(NavigationPolicy.decide(blobURL, isMainFrame: true) == .download)
    }

    @Test("Restores last active conversation URL only when valid and enabled")
    func validatesLaunchRestoreURL() {
        let validThread = "https://www.facebook.com/messages/e2ee/t/77889900/"
        #expect(
            NavigationPolicy.launchURL(restoreLast: true, lastConversationURL: validThread).absoluteString
                == validThread
        )
        #expect(
            NavigationPolicy.launchURL(restoreLast: false, lastConversationURL: validThread)
                == NavigationPolicy.homeURL
        )
        #expect(
            NavigationPolicy.launchURL(restoreLast: true, lastConversationURL: "https://evil.example/t/123")
                == NavigationPolicy.homeURL
        )
    }

    @Test("Restricts notification avatar downloads to HTTPS Meta CDN hosts")
    func restrictsAvatarURLs() {
        #expect(NavigationPolicy.isAllowedAvatarURL(URL(string: "https://scontent.xx.fbcdn.net/v/avatar.jpg")!))
        #expect(!NavigationPolicy.isAllowedAvatarURL(URL(string: "http://scontent.xx.fbcdn.net/v/avatar.jpg")!))
        #expect(!NavigationPolicy.isAllowedAvatarURL(URL(string: "https://attacker.example/avatar.jpg")!))
    }
}
