import AppKit
import Foundation

@MainActor
final class BadgeController {
    private(set) var unreadCount: Int = 0
    var onCountChanged: ((Int) -> Void)?

    func update(count: Int) {
        let sanitized = max(0, count)
        let label = Self.badgeLabel(for: sanitized)
        if NSApp?.dockTile.badgeLabel != label {
            NSApp?.dockTile.badgeLabel = label
            NSApp?.dockTile.display()
        }
        guard sanitized != unreadCount else { return }
        unreadCount = sanitized
        onCountChanged?(sanitized)
    }

    nonisolated static func badgeLabel(for count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }
}
