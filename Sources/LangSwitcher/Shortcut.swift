import AppKit
import Carbon
import IOKit.hidsystem

enum Shortcut: String, CaseIterable {
    case leftOption, rightOption, leftControl, rightControl

    var title: String { NSLocalizedString("shortcut.\(rawValue)", comment: "") }

    var keyCode: Int64 {
        switch self {
        case .leftOption: return Int64(kVK_Option)
        case .rightOption: return Int64(kVK_RightOption)
        case .leftControl: return Int64(kVK_Control)
        case .rightControl: return Int64(kVK_RightControl)
        }
    }

    var modifier: CGEventFlags {
        switch self {
        case .leftOption, .rightOption: return .maskAlternate
        case .leftControl, .rightControl: return .maskControl
        }
    }

    private var sideMask: UInt64 {
        switch self {
        case .leftOption: return UInt64(NX_DEVICELALTKEYMASK)
        case .rightOption: return UInt64(NX_DEVICERALTKEYMASK)
        case .leftControl: return UInt64(NX_DEVICELCTLKEYMASK)
        case .rightControl: return UInt64(NX_DEVICERCTLKEYMASK)
        }
    }

    private var familyMask: UInt64 {
        switch self {
        case .leftOption, .rightOption:
            return UInt64(NX_DEVICELALTKEYMASK | NX_DEVICERALTKEYMASK)
        case .leftControl, .rightControl:
            return UInt64(NX_DEVICELCTLKEYMASK | NX_DEVICERCTLKEYMASK)
        }
    }

    func isPressed(with flags: CGEventFlags) -> Bool {
        // A release on one side can leave the shared modifier flag set by the other side.
        let sides = flags.rawValue & familyMask
        return flags.contains(modifier) && (sides == 0 || (sides & sideMask) != 0)
    }

    func isOtherSideDown(with flags: CGEventFlags) -> Bool {
        (flags.rawValue & familyMask & ~sideMask) != 0
    }

    static func restore(saved: [String]?, legacy: String?) -> Set<Shortcut> {
        let selected = Set((saved ?? []).compactMap(Shortcut.init(rawValue:)))
        if !selected.isEmpty { return selected }
        return [legacy.flatMap(Shortcut.init(rawValue:)) ?? .leftOption]
    }
}
