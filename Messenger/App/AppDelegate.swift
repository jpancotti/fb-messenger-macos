import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = AppPreferences.shared
    private let badgeController = BadgeController()
    private lazy var notificationManager = NotificationManager(preferences: preferences)

    private var mainWindowController: MainWindowController?
    private var statusBarController: StatusBarController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        if terminateIfAnotherInstanceIsRunning() {
            return
        }

        NSApp.mainMenu = MainMenu.build(target: self)

        let messengerVC = MessengerViewController(
            preferences: preferences,
            badgeController: badgeController,
            notificationManager: notificationManager
        )
        let windowController = MainWindowController(
            messengerViewController: messengerVC,
            preferences: preferences
        )
        self.mainWindowController = windowController

        let statusController = StatusBarController(preferences: preferences)
        statusController.isMainWindowVisibleProvider = { [weak windowController] in
            windowController?.isWindowVisibleAndActive ?? false
        }
        statusController.onToggleWindow = { [weak windowController] in
            windowController?.toggleVisibility()
        }
        statusController.onShowWindow = { [weak windowController] in
            windowController?.showAndFocus()
        }
        statusController.onNewMessage = { [weak messengerVC] in
            messengerVC?.triggerNewMessage()
        }
        statusController.onSearchChats = { [weak messengerVC] in
            messengerVC?.focusSearch()
        }
        statusController.onReload = { [weak messengerVC] in
            messengerVC?.reload()
        }
        statusController.onOpenSettings = { [weak self] in
            self?.openSettings(nil)
        }
        self.statusBarController = statusController

        badgeController.onCountChanged = { [weak statusController] count in
            statusController?.updateUnreadCount(count)
        }

        preferences.onMenuBarPreferenceChanged = { [weak statusController] in
            statusController?.refreshVisibilityAndAppearance()
        }

        notificationManager.onSelectConversation = { [weak self] threadId, href in
            self?.mainWindowController?.showAndFocus()
            self?.mainWindowController?.messengerViewController.openConversation(
                threadId: threadId,
                href: href
            )
        }
        notificationManager.setup()

        windowController.showAndFocus()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Always bring the main window back on Dock click (even after orderOut on ⌘W)
        mainWindowController?.showAndFocus()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func terminateIfAnotherInstanceIsRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }

        guard let existing = others.first else { return false }
        existing.activate()
        NSApp.terminate(nil)
        return true
    }

    // MARK: - Menu Actions

    @objc func showMainWindow(_ sender: Any?) {
        mainWindowController?.showAndFocus()
    }

    @objc func newMessage(_ sender: Any?) {
        mainWindowController?.showAndFocus()
        mainWindowController?.messengerViewController.triggerNewMessage()
    }

    @objc func focusSearch(_ sender: Any?) {
        mainWindowController?.showAndFocus()
        mainWindowController?.messengerViewController.focusSearch()
    }

    @objc func reloadPage(_ sender: Any?) {
        mainWindowController?.messengerViewController.reload()
    }

    @objc func goHome(_ sender: Any?) {
        mainWindowController?.showAndFocus()
        mainWindowController?.messengerViewController.loadHome()
    }

    @objc func navigateBack(_ sender: Any?) {
        mainWindowController?.messengerViewController.goBack()
    }

    @objc func navigateForward(_ sender: Any?) {
        mainWindowController?.messengerViewController.goForward()
    }

    @objc func zoomIn(_ sender: Any?) {
        mainWindowController?.messengerViewController.zoomIn()
    }

    @objc func zoomOut(_ sender: Any?) {
        mainWindowController?.messengerViewController.zoomOut()
    }

    @objc func resetZoom(_ sender: Any?) {
        mainWindowController?.messengerViewController.resetZoom()
    }

    @objc func selectConversationMenuItem(_ sender: NSMenuItem) {
        mainWindowController?.showAndFocus()
        mainWindowController?.messengerViewController.selectConversation(at: sender.tag)
    }

    @objc func toggleMuteNotifications(_ sender: Any?) {
        preferences.notificationsMuted.toggle()
    }

    @objc func openSettings(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(preferences: preferences)
        }
        settingsWindowController?.show()
    }

    @objc func openDedicatedLoginWindow(_ sender: Any?) {
        mainWindowController?.messengerViewController.openDedicatedLoginWindow()
    }

    @objc func logOut(_ sender: Any?) {
        mainWindowController?.showAndFocus()
        mainWindowController?.messengerViewController.logOut()
    }
}
