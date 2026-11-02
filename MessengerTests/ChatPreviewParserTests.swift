import Foundation
import Testing
@testable import Messenger

@Suite("ChatPreviewParser")
struct ChatPreviewParserTests {
    @Test("Parses incoming message payload and strips screen-reader prefixes and timestamps")
    func parsesValidIncomingPayload() {
        let payload: [String: Any] = [
            "title": "  Alex   Rivera ",
            "body": "Unread message: Are we still on for dinner? · 2m",
            "threadId": "",
            "href": "https://www.facebook.com/messages/t/44556677/",
            "icon": "https://scontent.xx.fbcdn.net/v/t1.30497-1/avatar.jpg"
        ]

        let parsed = ChatPreviewParser.parseNotificationPayload(payload)
        #expect(parsed != nil)
        #expect(parsed?.sender == "Alex Rivera")
        #expect(parsed?.body == "Are we still on for dinner?")
        #expect(parsed?.threadId == "44556677")
        #expect(parsed?.avatarURL?.host == "scontent.xx.fbcdn.net")
        #expect(parsed?.notificationIdentifier == "messenger-thread-44556677")
    }

    @Test("Suppresses notifications for self-authored outgoing messages")
    func suppressesSelfMessages() {
        let outgoingSamples = [
            "You: Sounds great, see you then!",
            "You sent an attachment.",
            "You reacted ❤️ to their message"
        ]

        for sample in outgoingSamples {
            let payload: [String: Any] = [
                "title": "Jordan",
                "body": sample,
                "threadId": "999"
            ]
            #expect(ChatPreviewParser.parseNotificationPayload(payload) == nil)
        }
    }

    @Test("Masks preview text when privacy mode is enabled")
    func masksPreviewWhenPrivacyEnabled() {
        let notif = IncomingChatNotification(
            threadId: "123",
            href: "https://www.facebook.com/messages/t/123/",
            sender: "Sam",
            body: "Secret surprise party at 8pm",
            avatarURL: nil
        )
        #expect(ChatPreviewParser.displayBody(for: notif, hidePreview: false) == "Secret surprise party at 8pm")
        #expect(ChatPreviewParser.displayBody(for: notif, hidePreview: true) == "New message")
    }
}
