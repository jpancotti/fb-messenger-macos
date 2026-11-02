import AppKit

@MainActor
enum MainMenu {
    static func build(target: AppDelegate) -> NSMenu {
        let mainMenu = NSMenu()

        // 1. Messenger (Application Menu)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(
            withTitle: "About Messenger",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(AppDelegate.openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = target
        appMenu.addItem(settingsItem)

        appMenu.addItem(.separator())

        let signInItem = NSMenuItem(
            title: "Sign In Window…",
            action: #selector(AppDelegate.openDedicatedLoginWindow(_:)),
            keyEquivalent: ""
        )
        signInItem.target = target
        appMenu.addItem(signInItem)

        let logOutItem = NSMenuItem(
            title: "Log Out…",
            action: #selector(AppDelegate.logOut(_:)),
            keyEquivalent: ""
        )
        logOutItem.target = target
        appMenu.addItem(logOutItem)

        appMenu.addItem(.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)

        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide Messenger",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)

        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Messenger",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")

        let newMsgItem = NSMenuItem(
            title: "New Message",
            action: #selector(AppDelegate.newMessage(_:)),
            keyEquivalent: "n"
        )
        newMsgItem.target = target
        fileMenu.addItem(newMsgItem)

        let searchItem = NSMenuItem(
            title: "Search Chats…",
            action: #selector(AppDelegate.focusSearch(_:)),
            keyEquivalent: "f"
        )
        searchItem.target = target
        fileMenu.addItem(searchItem)

        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )

        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // 3. Edit Menu (essential so ⌘C, ⌘V, ⌘X, ⌘A, ⌘Z route properly into WKWebView text inputs)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pastePlain = NSMenuItem(
            title: "Paste and Match Style",
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "V"
        )
        pastePlain.keyEquivalentModifierMask = [.command, .option, .shift]
        editMenu.addItem(pastePlain)
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 4. View Menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")

        let reloadItem = NSMenuItem(
            title: "Reload Messenger",
            action: #selector(AppDelegate.reloadPage(_:)),
            keyEquivalent: "r"
        )
        reloadItem.target = target
        viewMenu.addItem(reloadItem)

        let goHomeItem = NSMenuItem(
            title: "Go to Messenger Home",
            action: #selector(AppDelegate.goHome(_:)),
            keyEquivalent: "R"
        )
        goHomeItem.keyEquivalentModifierMask = [.command, .shift]
        goHomeItem.target = target
        viewMenu.addItem(goHomeItem)

        viewMenu.addItem(.separator())

        let backItem = NSMenuItem(
            title: "Back",
            action: #selector(AppDelegate.navigateBack(_:)),
            keyEquivalent: "["
        )
        backItem.target = target
        viewMenu.addItem(backItem)

        let forwardItem = NSMenuItem(
            title: "Forward",
            action: #selector(AppDelegate.navigateForward(_:)),
            keyEquivalent: "]"
        )
        forwardItem.target = target
        viewMenu.addItem(forwardItem)

        viewMenu.addItem(.separator())

        let actualSizeItem = NSMenuItem(
            title: "Actual Size",
            action: #selector(AppDelegate.resetZoom(_:)),
            keyEquivalent: "0"
        )
        actualSizeItem.target = target
        viewMenu.addItem(actualSizeItem)

        let zoomInItem = NSMenuItem(
            title: "Zoom In",
            action: #selector(AppDelegate.zoomIn(_:)),
            keyEquivalent: "+"
        )
        zoomInItem.target = target
        viewMenu.addItem(zoomInItem)

        let zoomInAlt = NSMenuItem(
            title: "Zoom In",
            action: #selector(AppDelegate.zoomIn(_:)),
            keyEquivalent: "="
        )
        zoomInAlt.isAlternate = true
        zoomInAlt.target = target
        viewMenu.addItem(zoomInAlt)

        let zoomOutItem = NSMenuItem(
            title: "Zoom Out",
            action: #selector(AppDelegate.zoomOut(_:)),
            keyEquivalent: "-"
        )
        zoomOutItem.target = target
        viewMenu.addItem(zoomOutItem)

        viewMenu.addItem(.separator())

        let fullScreenItem = NSMenuItem(
            title: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fullScreenItem)

        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // 5. Conversations Menu (⌘1 – ⌘9 quick jump)
        let convMenuItem = NSMenuItem()
        let convMenu = NSMenu(title: "Conversations")
        for index in 1...9 {
            let item = NSMenuItem(
                title: "Select Conversation \(index)",
                action: #selector(AppDelegate.selectConversationMenuItem(_:)),
                keyEquivalent: "\(index)"
            )
            item.tag = index
            item.target = target
            convMenu.addItem(item)
        }
        convMenu.addItem(.separator())
        let muteItem = NSMenuItem(
            title: "Toggle Mute Notifications",
            action: #selector(AppDelegate.toggleMuteNotifications(_:)),
            keyEquivalent: "M"
        )
        muteItem.keyEquivalentModifierMask = [.command, .shift]
        muteItem.target = target
        convMenu.addItem(muteItem)

        convMenuItem.submenu = convMenu
        mainMenu.addItem(convMenuItem)

        // 6. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")

        let showMainItem = NSMenuItem(
            title: "Show Messenger Window",
            action: #selector(AppDelegate.showMainWindow(_:)),
            keyEquivalent: "1"
        )
        showMainItem.keyEquivalentModifierMask = [.command, .option]
        showMainItem.target = target
        windowMenu.addItem(showMainItem)

        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )

        NSApp.windowsMenu = windowMenu
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // 7. Help Menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        NSApp.helpMenu = helpMenu
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        return mainMenu
    }
}
