import Foundation
import Observation

@MainActor
@Observable
final class HubPreferences {
    private enum Keys {
        static let showInMenuBar = "showInMenuBar"
        static let menuBarLeftClickTogglesWindow = "menuBarLeftClickTogglesWindow"
        static let keepRunningOnWindowClose = "keepRunningOnWindowClose"
        static let restoreLastPageOnLaunch = "restoreLastPageOnLaunch"
        static let lastVisitedURL = "lastVisitedURL"
        static let notificationsMuted = "notificationsMuted"
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

    var restoreLastPageOnLaunch: Bool {
        didSet {
            defaults.set(restoreLastPageOnLaunch, forKey: Keys.restoreLastPageOnLaunch)
        }
    }

    var lastVisitedURL: String? {
        didSet {
            if let lastVisitedURL {
                defaults.set(lastVisitedURL, forKey: Keys.lastVisitedURL)
            } else {
                defaults.removeObject(forKey: Keys.lastVisitedURL)
            }
        }
    }

    var notificationsMuted: Bool {
        didSet {
            defaults.set(notificationsMuted, forKey: Keys.notificationsMuted)
            onMenuBarPreferenceChanged?()
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
            Keys.restoreLastPageOnLaunch: true,
            Keys.notificationsMuted: false,
            Keys.pageZoom: 1.0,
            Keys.developerExtrasEnabled: false
        ])

        self.showInMenuBar = defaults.bool(forKey: Keys.showInMenuBar)
        self.menuBarLeftClickTogglesWindow = defaults.bool(forKey: Keys.menuBarLeftClickTogglesWindow)
        self.keepRunningOnWindowClose = defaults.bool(forKey: Keys.keepRunningOnWindowClose)
        self.restoreLastPageOnLaunch = defaults.bool(forKey: Keys.restoreLastPageOnLaunch)
        self.lastVisitedURL = defaults.string(forKey: Keys.lastVisitedURL)
        self.notificationsMuted = defaults.bool(forKey: Keys.notificationsMuted)
        let storedZoom = defaults.double(forKey: Keys.pageZoom)
        self.pageZoom = Self.clampZoom(storedZoom == 0 ? 1.0 : storedZoom)
        self.developerExtrasEnabled = defaults.bool(forKey: Keys.developerExtrasEnabled)
    }

    nonisolated static func clampZoom(_ value: Double) -> Double {
        min(max(value, 0.6), 2.5)
    }
}
