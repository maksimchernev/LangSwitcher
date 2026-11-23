import AppKit

enum InstallationPrompt {
    static func showIfNeeded() {
        guard let applications = destination(for: Bundle.main.bundleURL) else { return }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("installation.title", comment: "")
        alert.informativeText = NSLocalizedString("installation.instructions", comment: "")
        alert.addButton(withTitle: NSLocalizedString("installation.openApplications", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("installation.later", comment: "")).keyEquivalent = "\u{1B}"

        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(applications)
        }
    }

    static func destination(for bundleURL: URL) -> URL? {
        guard bundleURL.pathExtension.lowercased() == "app" else { return nil }

        let fileManager = FileManager.default
        let domains: FileManager.SearchPathDomainMask = [.localDomainMask, .userDomainMask, .systemDomainMask]
        let installed = fileManager.urls(for: .applicationDirectory, in: domains).contains { directory in
            var relationship = FileManager.URLRelationship.other
            do {
                try fileManager.getRelationship(&relationship, ofDirectoryAt: directory, toItemAt: bundleURL)
                return relationship == .contains
            } catch {
                return false
            }
        }
        guard !installed else { return nil }
        return fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first
    }
}
