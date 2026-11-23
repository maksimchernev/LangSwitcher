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
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
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
    static func focusedField() -> TextField? {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { return nil }

        // Spotlight can keep keyboard focus while the previous app remains frontmost.
        if let spotlight = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Spotlight").first,
           let field = focusedField(in: spotlight.processIdentifier, requiresFocusedWindow: true),
           field.attribute(kAXIdentifierAttribute) as? String == "SpotlightSearchField",
           field.attribute(kAXFocusedAttribute) as? Bool == true {
            return field
        }

        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != getpid() else { return nil }
        return focusedField(in: front.processIdentifier)
    }

    private static func focusedField(in pid: pid_t, requiresFocusedWindow: Bool = false) -> TextField? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.12)
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
