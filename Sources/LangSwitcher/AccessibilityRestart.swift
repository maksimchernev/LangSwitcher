import AppKit

struct AccessibilityRestart {
    private var wasTrusted: Bool
    private var offered = false

    init(initiallyTrusted: Bool) {
        wasTrusted = initiallyTrusted
    }

    mutating func observe(trusted: Bool) -> Bool {
        defer { wasTrusted = trusted }
        guard trusted, !wasTrusted, !offered else { return false }
        offered = true
        return true
    }

    static func showPrompt() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("restart.title", comment: "")
        alert.informativeText = NSLocalizedString("restart.accessibility", comment: "")
        alert.addButton(withTitle: NSLocalizedString("restart.now", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("restart.later", comment: "")).keyEquivalent = "\u{1B}"
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try scheduleRelaunch(of: Bundle.main.bundleURL, after: getpid())
            NSApp.terminate(nil)
        } catch {
            let failure = NSAlert()
            failure.messageText = NSLocalizedString("restart.failure", comment: "")
            failure.informativeText = NSLocalizedString("restart.manual", comment: "")
            failure.runModal()
        }
    }

    static func scheduleRelaunch(of bundleURL: URL, after pid: pid_t) throws {
        guard bundleURL.pathExtension.lowercased() == "app" else { throw CocoaError(.fileNoSuchFile) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for the old process to finish so the duplicate-instance check accepts the new one.
        task.arguments = [
            "-c",
            """
            remaining=50
            while kill -0 "$1" 2>/dev/null; do
                [ "$remaining" -gt 0 ] || exit 1
                remaining=$((remaining - 1))
                /bin/sleep 0.2
            done
            exec /usr/bin/open -g "$2"
            """,
            "langswitcher-restart", String(pid), bundleURL.path,
        ]
        try task.run()
    }
}
