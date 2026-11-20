import AppKit
import ApplicationServices
import Carbon

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
    var text: String? { attribute(kAXValueAttribute) as? String }

    var isSecure: Bool {
        (attribute(kAXSubroleAttribute) as? String) == kAXSecureTextFieldSubrole || IsSecureEventInputEnabled()
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

    func setSelectedText(_ text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    func replace(_ range: NSRange, expected: String, with replacement: String, in snapshot: String,
                 stillValid: () -> Bool) -> Bool {
        guard stillValid(), text == snapshot, !isSecure,
              let stringRange = Range(range, in: snapshot), String(snapshot[stringRange]) == expected,
              let oldSelection = selection else { return false }
        var writable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &writable) == .success,
              writable.boolValue, select(range) else { return false }
        guard stillValid(), text == snapshot, selectedText == expected else {
            if stillValid() { _ = select(oldSelection) }
            return false
        }
        guard setSelectedText(replacement) else {
            if stillValid() { _ = select(oldSelection) }
            return false
        }
        let expectedValue = snapshot.replacingCharacters(in: stringRange, with: replacement)
        guard text == expectedValue else { return false }
        _ = select(NSRange(location: range.location + replacement.utf16.count, length: 0))
        return true
    }
}

enum TextAccess {
    static func focusedField() -> TextField? {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != getpid() else { return nil }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.12)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.12)
        let field = TextField(element: element, pid: front.processIdentifier)
        guard !field.isSecure else { return nil }
        let role = field.attribute(kAXRoleAttribute) as? String
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else { return nil }
        if let enabled = field.attribute(kAXEnabledAttribute) as? Bool, !enabled { return nil }
        if let editable = field.attribute("AXEditable") as? Bool, !editable { return nil }
        return field
    }

}
