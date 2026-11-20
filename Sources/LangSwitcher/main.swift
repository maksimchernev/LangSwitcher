import AppKit
import ApplicationServices
import SwitcherCore

if CommandLine.arguments.contains("--diagnose") {
    let layouts = KeyboardLayouts()
    print("LangSwitcher \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
    print("Accessibility: \(AXIsProcessTrusted() ? "granted" : "not granted")")
    print("Current input source: \(layouts.currentID ?? "unavailable")")
    for layout in layouts.enabled { print("Layout: \(layout.name) [\(layout.id)]") }
    if let result = layouts.conversion("ghbdtn", sourceID: "com.apple.keylayout.ABC") {
        print("Conversion: ghbdtn → \(result.text) [\(result.target.name)]")
    }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
