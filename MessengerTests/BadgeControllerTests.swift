import Foundation
import Testing
@testable import Messenger

@Suite("BadgeController & AppPreferences")
struct BadgeControllerTests {
    @Test("Formats Dock and menu bar unread badge labels cleanly")
    func formatsBadgeLabels() {
        #expect(BadgeController.badgeLabel(for: -1) == nil)
        #expect(BadgeController.badgeLabel(for: 0) == nil)
        #expect(BadgeController.badgeLabel(for: 1) == "1")
        #expect(BadgeController.badgeLabel(for: 42) == "42")
        #expect(BadgeController.badgeLabel(for: 99) == "99")
        #expect(BadgeController.badgeLabel(for: 100) == "99+")
    }

    @Test("Clamps zoom level to safe bounds")
    @MainActor
    func clampsZoomBounds() {
        #expect(AppPreferences.clampZoom(0.2) == 0.6)
        #expect(AppPreferences.clampZoom(1.25) == 1.25)
        #expect(AppPreferences.clampZoom(5.0) == 2.5)
    }
}
