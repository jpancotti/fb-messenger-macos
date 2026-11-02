import AppKit

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private static let frameAutosaveName = "MessengerMainWindowFrame"
    private static let toolbarIdentifier = NSToolbar.Identifier("MessengerUnifiedToolbar")

    let messengerViewController: MessengerViewController
    private let preferences: AppPreferences

    init(
        messengerViewController: MessengerViewController,
        preferences: AppPreferences
    ) {
        self.messengerViewController = messengerViewController
        self.preferences = preferences

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )

        window.title = "Messenger"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 560)
        window.backgroundColor = .windowBackgroundColor
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentViewController = messengerViewController

        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.setContentSize(NSSize(width: 1180, height: 780))
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)

        super.init(window: window)
        window.delegate = self
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

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if preferences.keepRunningOnWindowClose {
            sender.orderOut(nil)
            return false
        }
        return true
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        window?.toolbar = nil
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.showsBaselineSeparator = false
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }
}
