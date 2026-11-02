import AppKit

@MainActor
final class HubMainWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private enum ToolbarItemID {
        static let backForward = NSToolbarItem.Identifier("HubBackForward")
        static let sections = NSToolbarItem.Identifier("HubSections")
        static let primaryAction = NSToolbarItem.Identifier("HubPrimaryAction")
        static let search = NSToolbarItem.Identifier("HubSearch")
        static let copyLink = NSToolbarItem.Identifier("HubCopyLink")
        static let openBrowser = NSToolbarItem.Identifier("HubOpenBrowser")
        static let reload = NSToolbarItem.Identifier("HubReload")
    }

    let webViewController: HubWebViewController
    private let profile: HubAppProfile
    private let preferences: HubPreferences

    private var backForwardControl: NSSegmentedControl?
    private var sectionsControl: NSSegmentedControl?
    private var copyLinkButton: NSButton?

    init(webViewController: HubWebViewController, profile: HubAppProfile, preferences: HubPreferences) {
        self.webViewController = webViewController
        self.profile = profile
        self.preferences = preferences

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1260, height: 840),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable
            ],
            backing: .buffered,
            defer: false
        )

        window.title = profile.appName
        window.titleVisibility = .hidden
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 680, height: 560)
        window.backgroundColor = .windowBackgroundColor
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentViewController = webViewController

        let autosaveName = "\(profile.appName)MainWindowFrame"
        if !window.setFrameUsingName(autosaveName) {
            window.setContentSize(NSSize(width: 1260, height: 840))
            window.center()
        }
        window.setFrameAutosaveName(autosaveName)

        super.init(window: window)
        window.delegate = self

        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("\(profile.appName)Toolbar"))
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact

        webViewController.onNavigationStateChanged = { [weak self] url, canGoBack, canGoForward in
            self?.syncToolbarState(url: url, canGoBack: canGoBack, canGoForward: canGoForward)
        }
        webViewController.onActivateMainWindowRequested = { [weak self] in
            self?.showAndFocus()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var isWindowVisibleAndActive: Bool {
        guard let window else { return false }
        return window.isVisible && !window.isMiniaturized && NSApp.isActive && window.isKeyWindow
    }

    func showAndFocus() {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hideToBackground() {
        window?.orderOut(nil)
    }

    func toggleVisibility() {
        if isWindowVisibleAndActive {
            hideToBackground()
        } else {
            showAndFocus()
        }
    }

    func flashCopiedFeedback() {
        guard let button = copyLinkButton else { return }
        button.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        Task { @MainActor [weak button] in
            try? await Task.sleep(for: .milliseconds(1200))
            button?.image = NSImage(systemSymbolName: "link", accessibilityDescription: "Copy Clean Link")
        }
    }

    private func syncToolbarState(url: URL?, canGoBack: Bool, canGoForward: Bool) {
        backForwardControl?.setEnabled(canGoBack, forSegment: 0)
        backForwardControl?.setEnabled(canGoForward, forSegment: 1)

        if let activeIndex = profile.activeSectionIndex(for: url) {
            sectionsControl?.selectedSegment = activeIndex
        } else {
            sectionsControl?.selectedSegment = -1
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if preferences.keepRunningOnWindowClose {
            sender.orderOut(nil)
            return false
        }
        return true
    }

    // MARK: - NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItemID.backForward,
            .flexibleSpace,
            ToolbarItemID.sections,
            .flexibleSpace,
            ToolbarItemID.primaryAction,
            ToolbarItemID.search,
            ToolbarItemID.copyLink,
            ToolbarItemID.openBrowser,
            ToolbarItemID.reload
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarItemID.backForward:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let backImg = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")!
            let fwdImg = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")!
            let control = NSSegmentedControl(
                images: [backImg, fwdImg],
                trackingMode: .momentary,
                target: self,
                action: #selector(handleBackForward(_:))
            )
            control.segmentStyle = .separated
            control.setEnabled(false, forSegment: 0)
            control.setEnabled(false, forSegment: 1)
            self.backForwardControl = control
            item.view = control
            item.label = "Back/Forward"
            item.toolTip = "Navigate Back or Forward (⌘[ / ⌘])"
            return item

        case ToolbarItemID.sections:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let labels = profile.sections.map(\.title)
            let control = NSSegmentedControl(
                labels: labels,
                trackingMode: .selectOne,
                target: self,
                action: #selector(handleSectionSegment(_:))
            )
            for (idx, section) in profile.sections.enumerated() {
                if let img = NSImage(systemSymbolName: section.symbolName, accessibilityDescription: section.title) {
                    control.setImage(img, forSegment: idx)
                    control.setImageScaling(.scaleProportionallyDown, forSegment: idx)
                }
            }
            control.selectedSegment = 0
            self.sectionsControl = control
            item.view = control
            item.label = "Sections"
            return item

        case ToolbarItemID.primaryAction:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let button = NSButton(
                title: profile.primaryActionToolbarLabel,
                image: NSImage(
                    systemSymbolName: profile.primaryActionSymbol,
                    accessibilityDescription: profile.primaryActionTitle
                )!,
                target: self,
                action: #selector(handlePrimaryAction)
            )
            button.bezelStyle = .toolbar
            button.imagePosition = .imageLeading
            item.view = button
            item.label = profile.primaryActionToolbarLabel
            item.toolTip = "\(profile.primaryActionTitle) (⌘N)"
            return item

        case ToolbarItemID.search:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let button = NSButton(
                image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")!,
                target: self,
                action: #selector(handleSearch)
            )
            button.bezelStyle = .toolbar
            item.view = button
            item.label = "Search"
            item.toolTip = "\(profile.searchMenuTitle) (⌘F)"
            return item

        case ToolbarItemID.copyLink:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let button = NSButton(
                image: NSImage(systemSymbolName: "link", accessibilityDescription: "Copy Clean Link")!,
                target: self,
                action: #selector(handleCopyLink)
            )
            button.bezelStyle = .toolbar
            self.copyLinkButton = button
            item.view = button
            item.label = "Copy Link"
            item.toolTip = "Copy Clean Tracking-Free Link (⇧⌘C)"
            return item

        case ToolbarItemID.openBrowser:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let button = NSButton(
                image: NSImage(systemSymbolName: "safari", accessibilityDescription: "Open in Browser")!,
                target: self,
                action: #selector(handleOpenBrowser)
            )
            button.bezelStyle = .toolbar
            item.view = button
            item.label = "Open in Browser"
            item.toolTip = "Open Current Page in Default Browser (⇧⌘O)"
            return item

        case ToolbarItemID.reload:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let button = NSButton(
                image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")!,
                target: self,
                action: #selector(handleReload)
            )
            button.bezelStyle = .toolbar
            item.view = button
            item.label = "Reload"
            item.toolTip = "Reload Page (⌘R)"
            return item

        default:
            return nil
        }
    }

    @objc private func handleBackForward(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            webViewController.goBack()
        } else if sender.selectedSegment == 1 {
            webViewController.goForward()
        }
    }

    @objc private func handleSectionSegment(_ sender: NSSegmentedControl) {
        guard sender.selectedSegment >= 0 else { return }
        webViewController.navigateToSection(at: sender.selectedSegment)
    }

    @objc private func handlePrimaryAction() {
        webViewController.triggerPrimaryAction()
    }

    @objc private func handleSearch() {
        webViewController.focusSearch()
    }

    @objc private func handleCopyLink() {
        webViewController.copyCleanCurrentURL()
        flashCopiedFeedback()
    }

    @objc private func handleOpenBrowser() {
        webViewController.openCurrentPageInBrowser()
    }

    @objc private func handleReload() {
        webViewController.reload()
    }
}
