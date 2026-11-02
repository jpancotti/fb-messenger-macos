import AppKit
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let preferences: AppPreferences
    var onSelectConversation: ((String, String) -> Void)?
    private var isAuthorized = false

    /// Running inside a valid `.app` bundle is required for `UNUserNotificationCenter.current()`.
    private var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    init(preferences: AppPreferences) {
        self.preferences = preferences
        super.init()
    }

    func setup() {
        guard canUseUserNotifications else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let openAction = UNNotificationAction(
            identifier: "OPEN_CHAT",
            title: "Open Conversation",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "MESSENGER_MESSAGE",
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.isAuthorized = granted
            }
        }
    }

    func post(_ notification: IncomingChatNotification) {
        guard canUseUserNotifications, !preferences.notificationsMuted else { return }

        let title = notification.sender
        let body = ChatPreviewParser.displayBody(
            for: notification,
            hidePreview: preferences.hideNotificationPreviewText
        )
        let identifier = notification.notificationIdentifier
        let threadId = notification.threadId
        let href = notification.href
        let avatarURL = preferences.hideNotificationPreviewText ? nil : notification.avatarURL

        Task {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.threadIdentifier = threadId
            content.categoryIdentifier = "MESSENGER_MESSAGE"
            content.userInfo = [
                "threadId": threadId,
                "href": href
            ]

            if let avatarURL, let attachment = await Self.downloadAvatarAttachment(from: avatarURL) {
                content.attachments = [attachment]
            }

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private static func downloadAvatarAttachment(from url: URL) async -> UNNotificationAttachment? {
        guard NavigationPolicy.isAllowedAvatarURL(url) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 4.0)
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  !data.isEmpty,
                  data.count <= 2_000_000
            else {
                return nil
            }

            let ext: String
            switch http.mimeType?.lowercased() {
            case "image/png":
                ext = "png"
            case "image/webp":
                ext = "webp"
            default:
                ext = "jpg"
            }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("msgr-avatar-\(UUID().uuidString).\(ext)")
            try data.write(to: tempURL, options: .atomic)
            return try UNNotificationAttachment(identifier: "avatar", url: tempURL)
        } catch {
            return nil
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let threadId = (userInfo["threadId"] as? String) ?? ""
        let href = (userInfo["href"] as? String) ?? ""

        Task { @MainActor [weak self] in
            self?.onSelectConversation?(threadId, href)
        }
        completionHandler()
    }
}
