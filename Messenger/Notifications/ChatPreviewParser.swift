import Foundation

struct IncomingChatNotification: Equatable, Sendable {
    let threadId: String
    let href: String
    let sender: String
    let body: String
    let avatarURL: URL?

    var notificationIdentifier: String {
        let sanitized = threadId
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "messenger-general" : "messenger-thread-\(sanitized)"
    }
}

enum ChatPreviewParser {
    private static let selfPrefixes: [String] = [
        "you:",
        "you sent",
        "you reacted",
        "you unsent",
        "you replied",
        "you missed",
        "you called"
    ]

    static func parseNotificationPayload(_ payload: [String: Any]) -> IncomingChatNotification? {
        guard let rawTitle = payload["title"] as? String else { return nil }
        let rawBody = (payload["body"] as? String) ?? ""
        let rawThreadId = (payload["threadId"] as? String) ?? ""
        let rawHref = (payload["href"] as? String) ?? ""
        let rawIcon = (payload["icon"] as? String) ?? ""

        let sender = cleanSender(rawTitle)
        let snippet = cleanSnippet(rawBody)

        // Filter out messages sent by the current user
        if isSelfAuthoredSnippet(snippet) {
            return nil
        }

        guard !sender.isEmpty || !snippet.isEmpty else {
            return nil
        }

        let threadId = normalizeThreadId(rawThreadId, fallbackHref: rawHref)
        let avatarURL = URL(string: rawIcon).flatMap { NavigationPolicy.isAllowedAvatarURL($0) ? $0 : nil }

        return IncomingChatNotification(
            threadId: threadId,
            href: rawHref,
            sender: sender.isEmpty ? "Messenger" : sender,
            body: snippet.isEmpty ? "Sent a message" : snippet,
            avatarURL: avatarURL
        )
    }

    static func cleanSender(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanSnippet(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip leading screen-reader unread prefix if present
        text = text.replacingOccurrences(
            of: #"^(unread message|nieprzeczytana wiadomość|ungelesene nachricht):\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Strip trailing relative timestamp separator like " · 2m" or " · Just now"
        text = text.replacingOccurrences(
            of: #"\s*·\s*(\d+\s*[smhdwy]|just now|now|\d{1,2}:\d{2}(\s*[ap]m)?)$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isSelfAuthoredSnippet(_ snippet: String) -> Bool {
        let lower = snippet.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return selfPrefixes.contains { lower.hasPrefix($0) }
    }

    static func normalizeThreadId(_ rawThreadId: String, fallbackHref: String) -> String {
        let trimmed = rawThreadId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let range = fallbackHref.range(of: #"/t/([^/?#]+)"#, options: .regularExpression) {
            let segment = String(fallbackHref[range])
            return segment.replacingOccurrences(of: "/t/", with: "")
        }
        return "default"
    }

    static func displayBody(for notification: IncomingChatNotification, hidePreview: Bool) -> String {
        hidePreview ? "New message" : notification.body
    }
}
