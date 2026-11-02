import AppKit

@MainActor
final class HubStatusBarController: NSObject, NSMenuDelegate {
    private let profile: HubAppProfile
    private let preferences: HubPreferences
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()

    var isMainWindowVisibleProvider: (() -> Bool)?
    var onToggleWindow: (() -> Void)?
    var onShowWindow: (() -> Void)?
    var onSelectSection: ((Int) -> Void)?
    var onPrimaryAction: (() -> Void)?
    var onSearch: (() -> Void)?
    var onReload: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init(profile: HubAppProfile, preferences: HubPreferences) {
        self.profile = profile
        self.preferences = preferences
        super.init()
        statusMenu.delegate = self
        refreshVisibilityAndAppearance()
    }

    func refreshVisibilityAndAppearance() {
        if preferences.showInMenuBar {
            if statusItem == nil {
                statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            }
            configureInteractionMode()
            updateButtonAppearance()
        } else if let existing = statusItem {
            NSStatusBar.system.removeStatusItem(existing)
            statusItem = nil
        }
    }

    private func configureInteractionMode() {
        guard let statusItem, let button = statusItem.button else { return }

        if preferences.menuBarLeftClickTogglesWindow {
            statusItem.menu = nil
            button.target = self
            button.action = #selector(handleStatusBarButtonClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        } else {
            button.target = nil
            button.action = nil
            rebuildMenu()
            statusItem.menu = statusMenu
        }
    }

    private func updateButtonAppearance() {
        guard let button = statusItem?.button else { return }
        let symbolName = preferences.notificationsMuted ? "bell.slash.fill" : profile.menuBarSymbol
        let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: profile.appName)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        button.image = image
        button.toolTip = profile.appName
    }

    @objc private func handleStatusBarButtonClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            onToggleWindow?()
            return
        }
        let isRightClick = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        if isRightClick, let statusItem {
            rebuildMenu()
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            onToggleWindow?()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        statusMenu.removeAllItems()

        let isVisible = isMainWindowVisibleProvider?() ?? false
        let toggleItem = NSMenuItem(
            title: isVisible ? "Hide \(profile.appName)" : "Show \(profile.appName)",
            action: #selector(toggleWindowAction),
            keyEquivalent: ""
        )
        toggleItem.target = self
        statusMenu.addItem(toggleItem)

        statusMenu.addItem(.separator())

        for (index, section) in profile.sections.enumerated() {
            let item = NSMenuItem(
                title: section.menuTitle,
                action: #selector(selectSectionAction(_:)),
                keyEquivalent: section.shortcutKey
            )
            item.tag = index
            item.target = self
            statusMenu.addItem(item)
        }

        statusMenu.addItem(.separator())

        let primaryItem = NSMenuItem(
            title: profile.primaryActionTitle,
            action: #selector(primaryAction),
            keyEquivalent: "n"
        )
        primaryItem.target = self
        statusMenu.addItem(primaryItem)

        let searchItem = NSMenuItem(
            title: profile.searchMenuTitle,
            action: #selector(searchAction),
            keyEquivalent: "f"
        )
        searchItem.target = self
        statusMenu.addItem(searchItem)

        statusMenu.addItem(.separator())

        let muteItem = NSMenuItem(
            title: "Mute Notifications",
            action: #selector(toggleMuteAction),
            keyEquivalent: ""
        )
        muteItem.target = self
        muteItem.state = preferences.notificationsMuted ? .on : .off
        statusMenu.addItem(muteItem)

        let reloadItem = NSMenuItem(
            title: "Reload",
            action: #selector(reloadAction),
            keyEquivalent: "r"
        )
        reloadItem.target = self
        statusMenu.addItem(reloadItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settingsItem.target = self
        statusMenu.addItem(settingsItem)

        statusMenu.addItem(.separator())
        statusMenu.addItem(
            withTitle: "Quit \(profile.appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
    }

    @objc private func toggleWindowAction() {
        onToggleWindow?()
    }

    @objc private func selectSectionAction(_ sender: NSMenuItem) {
        onShowWindow?()
        onSelectSection?(sender.tag)
    }

    @objc private func primaryAction() {
        onShowWindow?()
        onPrimaryAction?()
    }

    @objc private func searchAction() {
        onShowWindow?()
        onSearch?()
    }

    @objc private func toggleMuteAction() {
        preferences.notificationsMuted.toggle()
        updateButtonAppearance()
    }

    @objc private func reloadAction() {
        onReload?()
    }

    @objc private func openSettingsAction() {
        onOpenSettings?()
    }
}
