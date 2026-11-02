import AppKit

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
app.setActivationPolicy(isTesting ? .accessory : .regular)
app.delegate = delegate
app.run()
