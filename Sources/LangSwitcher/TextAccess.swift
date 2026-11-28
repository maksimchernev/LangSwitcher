import AppKit
import ApplicationServices
import Carbon
import SwitcherCore

struct TextField {
    let element: AXUIElement
    let pid: pid_t

    func same(as other: TextField) -> Bool {
        pid == other.pid && CFEqual(element, other.element)
    }

    var selection: NSRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    var selectedText: String? { attribute(kAXSelectedTextAttribute) as? String }
    var hasMultipleSelections: Bool {
        ((attribute(kAXSelectedTextRangesAttribute) as? [Any])?.count ?? 0) > 1
    }

    var isVSCodeEditor: Bool {
        guard TextAccess.isVSCode(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier),
              let classes = attribute("AXDOMClassList") as? [String] else { return false }
        return classes.contains("native-edit-context") || classes.contains("inputarea")
    }

    var canVerifySingleSelection: Bool {
        guard !hasMultipleSelections else { return false }
        guard isVSCodeEditor else { return true }
        return vscodePosition != nil
    }

    struct EditorPosition: Equatable {
        let line: Int
        let column: Int
        let hasSelection: Bool
    }

    struct ReplayCaret: Equatable {
        let line: Int?
        let column: Int
    }

    var replayCaret: ReplayCaret? {
        if isVSCodeEditor {
            guard let position = vscodePosition, !position.hasSelection,
                  vscodeStatus("status.editor.inputMode") == nil else { return nil }
            return ReplayCaret(line: position.line, column: position.column)
        }
        guard !hasMultipleSelections, let selection, selection.length == 0 else { return nil }
        return ReplayCaret(line: nil, column: selection.location)
    }

    private static let selectionLabel = try! NSRegularExpression(
        pattern: #"^\D+(\d+)\s*[,，、]\s*\D+(\d+)(\s+\([^\r\n]+\))?$"#
    )

    var vscodePosition: EditorPosition? {
        guard !hasMultipleSelections, let status = vscodeStatus("status.editor.selection") else { return nil }
        let label = status as NSString
        guard let match = Self.selectionLabel.firstMatch(in: status, range: NSRange(location: 0, length: label.length)),
              let line = Int(label.substring(with: match.range(at: 1))),
              let column = Int(label.substring(with: match.range(at: 2))),
              line > 0, column > 0 else { return nil }
        return EditorPosition(line: line, column: column, hasSelection: match.range(at: 3).location != NSNotFound)
    }

    var vscodeTabSize: Int? {
        vscodeStatus("status.editor.indentation")?.split(whereSeparator: { !$0.isASCII || !$0.isNumber }).last.flatMap { Int($0) }
    }

    var text: String? {
        if let value = attribute(kAXValueAttribute) as? String { return value }
        // Some rich text controls expose their text through a parameterized range.
        guard let length = attribute(kAXNumberOfCharactersAttribute) as? Int,
              (0...1_000_000).contains(length) else { return nil }
        var range = CFRange(location: 0, length: length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value
        )
        return status == .success ? value as? String : nil
    }

    var isSecure: Bool {
        (attribute(kAXSubroleAttribute) as? String) == kAXSecureTextFieldSubrole || IsSecureEventInputEnabled()
    }

    func snapshot(revision: Int) -> EditSnapshot? {
        guard let text, let selection else { return nil }
        return EditSnapshot(revision: revision, text: text, selection: selection)
    }

    func attribute(_ name: String) -> CFTypeRef? {
        attribute(name, of: element)
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private func vscodeStatus(_ identifier: String) -> String? {
        func statusBar(in node: AXUIElement, depth: Int) -> AXUIElement? {
            let id = attribute("AXDOMIdentifier", of: node) as? String
            if id == "workbench.parts.statusbar" { return node }
            guard depth > 0, id?.hasPrefix("workbench.parts.") != true,
                  let children = attribute(kAXChildrenAttribute, of: node) as? [AXUIElement] else { return nil }
            for child in children.reversed() {
                if let found = statusBar(in: child, depth: depth - 1) { return found }
            }
            return nil
        }

        var current = element
        var inEditor = false
        for _ in 0..<32 {
            if attribute("AXDOMIdentifier", of: current) as? String == "workbench.parts.editor" { inEditor = true }
            let classes = attribute("AXDOMClassList", of: current) as? [String]
            if classes?.contains("monaco-workbench") == true {
                guard inEditor, let bar = statusBar(in: current, depth: 8),
                      let children = attribute(kAXChildrenAttribute, of: bar) as? [AXUIElement],
                      let selection = children.first(where: {
                          attribute("AXDOMIdentifier", of: $0) as? String == identifier
                      }) else { return nil }
                return attribute(kAXDescriptionAttribute, of: selection) as? String
            }
            guard let parent = attribute(kAXParentAttribute, of: current),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            current = parent as! AXUIElement
        }
        return nil
    }

    func select(_ range: NSRange) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    var isEditableText: Bool {
        guard !isSecure, (attribute(kAXEnabledAttribute) as? Bool) != false else { return false }
        if let editability { return editability }
        let role = attribute(kAXRoleAttribute) as? String
        return [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
    }

    var canEdit: Bool {
        guard !isSecure, (attribute(kAXEnabledAttribute) as? Bool) != false else { return false }
        if let editability { return editability }
        return [kAXSelectedTextAttribute, kAXValueAttribute].contains { name in
            var writable = DarwinBoolean(false)
            let status = AXUIElementIsAttributeSettable(element, name as CFString, &writable)
            return status == .success && writable.boolValue
        }
    }

    private var editability: Bool? {
        (attribute("AXEditable") as? Bool) ?? (attribute("AXIsEditable") as? Bool)
    }
}

enum TextAccess {
    private static var preparedVSCodeProcesses: Set<NSRunningApplication> = []

    static func isVSCode(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "com.microsoft.VSCode" || bundleIdentifier == "com.microsoft.VSCodeInsiders"
    }

    static func focusedField() -> TextField? {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { return nil }

        // Spotlight can keep keyboard focus while the previous app remains frontmost.
        if let spotlight = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Spotlight").first,
           let field = focusedField(in: spotlight, requiresFocusedWindow: true),
           field.attribute(kAXIdentifierAttribute) as? String == "SpotlightSearchField",
           field.attribute(kAXFocusedAttribute) as? Bool == true {
            return field
        }

        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != getpid() else { return nil }
        return focusedField(in: front)
    }

    private static func focusedField(in application: NSRunningApplication, requiresFocusedWindow: Bool = false) -> TextField? {
        let pid = application.processIdentifier
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.12)
        if isVSCode(application.bundleIdentifier),
           preparedVSCodeProcesses.insert(application).inserted {
            preparedVSCodeProcesses = preparedVSCodeProcesses.filter { !$0.isTerminated }
            // EditContext exposes editor text in screen reader mode. Electron debounces
            // requests, so send this once when we first encounter the process.
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        var value: CFTypeRef?
        if requiresFocusedWindow {
            guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        }
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.12)
        let focused = TextField(element: element, pid: pid)
        guard !focused.isSecure else { return nil }
        if focused.isEditableText { return focused }

        // Web editors can expose a focused child rather than the editable container.
        guard let parent = focused.attribute("AXEditableAncestor"),
              CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
        let container = parent as! AXUIElement
        var containerPID: pid_t = 0
        guard AXUIElementGetPid(container, &containerPID) == .success, containerPID == pid else { return nil }
        AXUIElementSetMessagingTimeout(container, 0.12)
        let field = TextField(element: container, pid: pid)
        return field.isEditableText ? field : nil
    }
}
