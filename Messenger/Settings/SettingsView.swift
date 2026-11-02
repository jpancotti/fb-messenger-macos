import SwiftUI

struct SettingsView: View {
    @Bindable var preferences: AppPreferences

    var body: some View {
        Form {
            Section("Window & Menu Bar") {
                Toggle("Show Messenger icon in menu bar", isOn: $preferences.showInMenuBar)

                if preferences.showInMenuBar {
                    Picker("Menu bar click action", selection: $preferences.menuBarLeftClickTogglesWindow) {
                        Text("Open quick menu").tag(false)
                        Text("Toggle window (right-click for menu)").tag(true)
                    }
                }

                Toggle("Keep running in background when closing window (⌘W)", isOn: $preferences.keepRunningOnWindowClose)

                Toggle("Reopen last active conversation on launch", isOn: $preferences.restoreLastConversationOnLaunch)
            }

            Section("Notifications & Privacy") {
                Toggle("Mute all Messenger notifications", isOn: $preferences.notificationsMuted)
                Toggle("Hide message preview text in notification banners", isOn: $preferences.hideNotificationPreviewText)
            }

            Section("Appearance & Developer") {
                HStack {
                    Text("Text & UI Zoom")
                    Spacer()
                    Text("\(Int((preferences.pageZoom * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("−") {
                        preferences.pageZoom = AppPreferences.clampZoom(preferences.pageZoom - 0.1)
                    }
                    Button("Reset") {
                        preferences.pageZoom = 1.0
                    }
                    Button("+") {
                        preferences.pageZoom = AppPreferences.clampZoom(preferences.pageZoom + 0.1)
                    }
                }

                Toggle("Enable WebKit Web Inspector (requires relaunch)", isOn: $preferences.developerExtrasEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 390)
    }
}
