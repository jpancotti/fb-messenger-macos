import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let preferences: AppPreferences
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private var unreadCount: Int = 0

    var isMainWindowVisibleProvider: (() -> Bool)?
    var onToggleWindow: (() -> Void)?
    var onShowWindow: (() -> Void)?
    var onNewMessage: (() -> Void)?
    var onSearchChats: (() -> Void)?
    var onReload: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init(preferences: AppPreferences) {
        self.preferences = preferences
        super.init()
        statusMenu.delegate = self
        refreshVisibilityAndAppearance()
    }

    func updateUnreadCount(_ count: Int) {
        unreadCount = max(0, count)
        updateButtonAppearance()
    }

    func refreshVisibilityAndAppearance() {
        if preferences.showInMenuBar {
            if statusItem == nil {
                statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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

        let symbolName: String
        if preferences.notificationsMuted {
            symbolName = "bell.slash.fill"
        } else if unreadCount > 0 {
            symbolName = "message.badge.filled.fill"
        } else {
            symbolName = "message.fill"
        }

        let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Messenger")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true

        button.image = image
        button.imagePosition = .imageLeading
        if let label = BadgeController.badgeLabel(for: unreadCount) {
            button.title = " \(label)"
        } else {
            button.title = ""
        }
        button.toolTip = unreadCount > 0
            ? "Messenger (\(unreadCount) unread)"
            : "Messenger"
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
            buttonPerformPopUp(statusItem: statusItem)
        } else {
            onToggleWindow?()
        }
    }

    private func buttonPerformPopUp(statusItem: NSStatusItem) {
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        statusMenu.removeAllItems()

        let isVisible = isMainWindowVisibleProvider?() ?? false
        let toggleTitle = isVisible ? "Hide Messenger" : "Show Messenger"
        let toggleItem = NSMenuItem(
            title: toggleTitle,
            action: #selector(toggleWindowAction),
            keyEquivalent: ""
        )
        toggleItem.target = self
        statusMenu.addItem(toggleItem)

        let unreadSummaryTitle = unreadCount == 0
            ? "No Unread Messages"
            : (unreadCount == 1 ? "1 Unread Conversation" : "\(unreadCount) Unread Conversations")
        let summaryItem = NSMenuItem(title: unreadSummaryTitle, action: nil, keyEquivalent: "")
        summaryItem.isEnabled = false
        statusMenu.addItem(summaryItem)

        statusMenu.addItem(.separator())

        let newMsgItem = NSMenuItem(
            title: "New Message",
            action: #selector(newMessageAction),
            keyEquivalent: "n"
        )
        newMsgItem.target = self
        statusMenu.addItem(newMsgItem)

        let searchItem = NSMenuItem(
            title: "Search Chats",
            action: #selector(searchChatsAction),
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
            title: "Reload Connection",
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

        let quitItem = NSMenuItem(
            title: "Quit Messenger",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusMenu.addItem(quitItem)
    }

    @objc private func toggleWindowAction() {
        onToggleWindow?()
    }

    @objc private func newMessageAction() {
        onShowWindow?()
        onNewMessage?()
    }

    @objc private func searchChatsAction() {
        onShowWindow?()
        onSearchChats?()
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
