import AppKit

@MainActor
final class HubAppDelegate: NSObject, NSApplicationDelegate {
    let profile: HubAppProfile
    private let preferences = HubPreferences()

    private var mainWindowController: HubMainWindowController?
    private var statusBarController: HubStatusBarController?
    private var settingsWindowController: HubSettingsWindowController?

    init(profile: HubAppProfile) {
        self.profile = profile
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        if terminateIfAnotherInstanceIsRunning() {
            return
        }

        NSApp.mainMenu = HubMainMenu.build(profile: profile, target: self)

        let webVC = HubWebViewController(profile: profile, preferences: preferences)
        let windowController = HubMainWindowController(
            webViewController: webVC,
            profile: profile,
            preferences: preferences
        )
        self.mainWindowController = windowController

        let statusController = HubStatusBarController(profile: profile, preferences: preferences)
        statusController.isMainWindowVisibleProvider = { [weak windowController] in
            windowController?.isWindowVisibleAndActive ?? false
        }
        statusController.onToggleWindow = { [weak windowController] in
            windowController?.toggleVisibility()
        }
        statusController.onShowWindow = { [weak windowController] in
            windowController?.showAndFocus()
        }
        statusController.onSelectSection = { [weak webVC] index in
            webVC?.navigateToSection(at: index)
        }
        statusController.onPrimaryAction = { [weak webVC] in
            webVC?.triggerPrimaryAction()
        }
        statusController.onSearch = { [weak webVC] in
            webVC?.focusSearch()
        }
        statusController.onReload = { [weak webVC] in
            webVC?.reload()
        }
        statusController.onOpenSettings = { [weak self] in
            self?.openSettings(nil)
        }
        self.statusBarController = statusController

        preferences.onMenuBarPreferenceChanged = { [weak statusController] in
            statusController?.refreshVisibilityAndAppearance()
        }

        windowController.showAndFocus()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
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

    @objc func primaryAction(_ sender: Any?) {
        mainWindowController?.showAndFocus()
        mainWindowController?.webViewController.triggerPrimaryAction()
    }

    @objc func secondaryCreateAction(_ sender: Any?) {
        mainWindowController?.showAndFocus()
        mainWindowController?.webViewController.triggerSecondaryCreate()
    }

    @objc func focusSearch(_ sender: Any?) {
        mainWindowController?.showAndFocus()
        mainWindowController?.webViewController.focusSearch()
    }

    @objc func copyCleanLink(_ sender: Any?) {
        mainWindowController?.webViewController.copyCleanCurrentURL()
        mainWindowController?.flashCopiedFeedback()
    }

    @objc func openInBrowser(_ sender: Any?) {
        mainWindowController?.webViewController.openCurrentPageInBrowser()
    }

    @objc func reloadPage(_ sender: Any?) {
        mainWindowController?.webViewController.reload()
    }

    @objc func goHome(_ sender: Any?) {
        mainWindowController?.showAndFocus()
        mainWindowController?.webViewController.loadHome()
    }

    @objc func navigateBack(_ sender: Any?) {
        mainWindowController?.webViewController.goBack()
    }

    @objc func navigateForward(_ sender: Any?) {
        mainWindowController?.webViewController.goForward()
    }

    @objc func zoomIn(_ sender: Any?) {
        mainWindowController?.webViewController.zoomIn()
    }

    @objc func zoomOut(_ sender: Any?) {
        mainWindowController?.webViewController.zoomOut()
    }

    @objc func resetZoom(_ sender: Any?) {
        mainWindowController?.webViewController.resetZoom()
    }

    @objc func selectSectionMenuItem(_ sender: NSMenuItem) {
        mainWindowController?.showAndFocus()
        mainWindowController?.webViewController.navigateToSection(at: sender.tag)
    }

    @objc func openSettings(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = HubSettingsWindowController(
                appName: profile.appName,
                preferences: preferences
            )
        }
        settingsWindowController?.show()
    }

    @objc func openDedicatedLoginWindow(_ sender: Any?) {
        mainWindowController?.webViewController.openDedicatedLoginWindow()
    }

    @objc func logOut(_ sender: Any?) {
        mainWindowController?.showAndFocus()
        mainWindowController?.webViewController.logOut()
    }

    static func launch(profile: HubAppProfile) -> Never {
        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated { HubAppDelegate(profile: profile) }
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        app.setActivationPolicy(isTesting ? .accessory : .regular)
        app.delegate = delegate
        app.run()
        fatalError("NSApplication.run() should not return")
    }
}
