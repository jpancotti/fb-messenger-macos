import AppKit
import SwiftUI

struct HubSettingsView: View {
    let appName: String
    @Bindable var preferences: HubPreferences

    var body: some View {
        Form {
            Section("Window & Menu Bar") {
                Toggle("Show \(appName) icon in menu bar", isOn: $preferences.showInMenuBar)

                if preferences.showInMenuBar {
                    Picker("Menu bar click action", selection: $preferences.menuBarLeftClickTogglesWindow) {
                        Text("Open quick menu").tag(false)
                        Text("Toggle window (right-click for menu)").tag(true)
                    }
                }

                Toggle("Keep running in background when closing window (⌘W)", isOn: $preferences.keepRunningOnWindowClose)

                Toggle("Reopen last visited \(appName) page on launch", isOn: $preferences.restoreLastPageOnLaunch)
            }

            Section("Notifications") {
                Toggle("Mute all \(appName) notifications", isOn: $preferences.notificationsMuted)
            }

            Section("Appearance & Developer") {
                HStack {
                    Text("Text & UI Zoom")
                    Spacer()
                    Text("\(Int((preferences.pageZoom * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("−") {
                        preferences.pageZoom = HubPreferences.clampZoom(preferences.pageZoom - 0.1)
                    }
                    Button("Reset") {
                        preferences.pageZoom = 1.0
                    }
                    Button("+") {
                        preferences.pageZoom = HubPreferences.clampZoom(preferences.pageZoom + 0.1)
                    }
                }

                Toggle("Enable WebKit Web Inspector (requires relaunch)", isOn: $preferences.developerExtrasEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 370)
    }
}

@MainActor
final class HubSettingsWindowController: NSWindowController {
    init(appName: String, preferences: HubPreferences) {
        let hosting = NSHostingController(
            rootView: HubSettingsView(appName: appName, preferences: preferences)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "\(appName) Settings"
        window.styleMask = [.titled, .closable]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
