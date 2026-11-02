import Foundation
import Observation

@MainActor
@Observable
final class AppPreferences {
    static let shared = AppPreferences()

    private enum Keys {
        static let showInMenuBar = "showInMenuBar"
        static let menuBarLeftClickTogglesWindow = "menuBarLeftClickTogglesWindow"
        static let keepRunningOnWindowClose = "keepRunningOnWindowClose"
        static let restoreLastConversationOnLaunch = "restoreLastConversationOnLaunch"
        static let lastActiveConversationURL = "lastActiveConversationURL"
        static let notificationsMuted = "notificationsMuted"
        static let hideNotificationPreviewText = "hideNotificationPreviewText"
        static let pageZoom = "pageZoom"
        static let developerExtrasEnabled = "developerExtrasEnabled"
    }

    private let defaults: UserDefaults

    var showInMenuBar: Bool {
        didSet {
            defaults.set(showInMenuBar, forKey: Keys.showInMenuBar)
            onMenuBarPreferenceChanged?()
        }
    }

    var menuBarLeftClickTogglesWindow: Bool {
        didSet {
            defaults.set(menuBarLeftClickTogglesWindow, forKey: Keys.menuBarLeftClickTogglesWindow)
            onMenuBarPreferenceChanged?()
        }
    }

    var keepRunningOnWindowClose: Bool {
        didSet {
            defaults.set(keepRunningOnWindowClose, forKey: Keys.keepRunningOnWindowClose)
        }
    }

    var restoreLastConversationOnLaunch: Bool {
        didSet {
            defaults.set(restoreLastConversationOnLaunch, forKey: Keys.restoreLastConversationOnLaunch)
        }
    }

    var lastActiveConversationURL: String? {
        didSet {
            if let lastActiveConversationURL {
                defaults.set(lastActiveConversationURL, forKey: Keys.lastActiveConversationURL)
            } else {
                defaults.removeObject(forKey: Keys.lastActiveConversationURL)
            }
        }
    }

    var notificationsMuted: Bool {
        didSet {
            defaults.set(notificationsMuted, forKey: Keys.notificationsMuted)
            onMenuBarPreferenceChanged?()
        }
    }

    var hideNotificationPreviewText: Bool {
        didSet {
            defaults.set(hideNotificationPreviewText, forKey: Keys.hideNotificationPreviewText)
        }
    }

    var pageZoom: Double {
        didSet {
            let clamped = Self.clampZoom(pageZoom)
            if pageZoom != clamped {
                pageZoom = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.pageZoom)
            onZoomChanged?(clamped)
        }
    }

    var developerExtrasEnabled: Bool {
        didSet {
            defaults.set(developerExtrasEnabled, forKey: Keys.developerExtrasEnabled)
        }
    }

    var onMenuBarPreferenceChanged: (() -> Void)?
    var onZoomChanged: ((Double) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        defaults.register(defaults: [
            Keys.showInMenuBar: true,
            Keys.menuBarLeftClickTogglesWindow: false,
            Keys.keepRunningOnWindowClose: true,
            Keys.restoreLastConversationOnLaunch: true,
            Keys.notificationsMuted: false,
            Keys.hideNotificationPreviewText: false,
            Keys.pageZoom: 1.0,
            Keys.developerExtrasEnabled: false
        ])

        self.showInMenuBar = defaults.bool(forKey: Keys.showInMenuBar)
        self.menuBarLeftClickTogglesWindow = defaults.bool(forKey: Keys.menuBarLeftClickTogglesWindow)
        self.keepRunningOnWindowClose = defaults.bool(forKey: Keys.keepRunningOnWindowClose)
        self.restoreLastConversationOnLaunch = defaults.bool(forKey: Keys.restoreLastConversationOnLaunch)
        self.lastActiveConversationURL = defaults.string(forKey: Keys.lastActiveConversationURL)
        self.notificationsMuted = defaults.bool(forKey: Keys.notificationsMuted)
        self.hideNotificationPreviewText = defaults.bool(forKey: Keys.hideNotificationPreviewText)
        let storedZoom = defaults.double(forKey: Keys.pageZoom)
        self.pageZoom = Self.clampZoom(storedZoom == 0 ? 1.0 : storedZoom)
        self.developerExtrasEnabled = defaults.bool(forKey: Keys.developerExtrasEnabled)
    }

    nonisolated static func clampZoom(_ value: Double) -> Double {
        min(max(value, 0.6), 2.5)
    }
}
