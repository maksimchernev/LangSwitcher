import AppKit
import Carbon
import SwitcherCore

/// Selects a verified range, pastes into its app, and restores the clipboard when the edit finishes.
final class PasteEdit {
    static let eventMarker: Int64 = 0x4C53575041535445
    enum Result { case pasted, failed, cancelled }

    private let field: TextField
    private let snapshot: EditSnapshot
    private let range: NSRange
    private let original: String
    private let replacement: String
    private let expectedValue: String
    private let stillFocused: () -> Bool
    private let completion: (Result) -> Void
    private var clipboard: PasteboardTransaction?
    private var finished = false
    private var cancelled = false
    private(set) var waitingForPaste = false

    init?(field: TextField, snapshot: EditSnapshot, range: NSRange, replacement: String,
          stillFocused: @escaping () -> Bool, completion: @escaping (Result) -> Void) {
        guard range.length > 0, let stringRange = Range(range, in: snapshot.text) else { return nil }
        self.field = field
        self.snapshot = snapshot
        self.range = range
        original = String(snapshot.text[stringRange])
        self.replacement = replacement
        expectedValue = snapshot.text.replacingCharacters(in: stringRange, with: replacement)
        self.stillFocused = stillFocused
        self.completion = completion
    }

    func start() {
        guard CGPreflightPostEventAccess(), stillFocused(), field.canEdit, !field.hasMultipleSelections, targetIsUnchanged,
              let clipboard = PasteboardTransaction(pasteboard: .general),
              stillFocused(), targetIsUnchanged
        else { finish(.failed); return }
        self.clipboard = clipboard

        if snapshot.selection != range, !field.select(range) {
            // When the app won't set an AX range, select backward from the verified caret.
            guard snapshot.selection == NSRange(location: NSMaxRange(range), length: 0),
                  original.count <= 128, stillFocused(),
                  field.selection == snapshot.selection, field.text == snapshot.text,
                  postKey(UInt16(kVK_LeftArrow), flags: .maskShift, count: original.count)
            else { finish(.failed); return }
        }
        waitForSelection(until: .now() + .milliseconds(350))
    }

    func cancel() {
        cancelled = true
        // A posted paste is already queued in the target. Let it finish before restoring.
        if !waitingForPaste { finish(.cancelled) }
    }

    func beforeUserKey() {
        if waitingForPaste, !cancelled, stillFocused(), field.text == expectedValue {
            finish(.pasted)
        } else {
            cancel()
        }
    }

    private var targetIsUnchanged: Bool {
        guard let current = field.snapshot(revision: snapshot.revision) else { return false }
        return snapshot.matches(current)
    }

    private func waitForSelection(until deadline: DispatchTime) {
        guard !finished else { return }
        guard stillFocused(), field.text == snapshot.text else { finish(.failed); return }
        guard targetIsSelected else {
            guard DispatchTime.now() < deadline else { finish(.failed); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) { [weak self] in
                self?.waitForSelection(until: deadline)
            }
            return
        }
        guard let clipboard, clipboard.stage(replacement), stillFocused(), field.canEdit,
              field.text == snapshot.text, targetIsSelected, clipboard.ownsTemporaryText,
              postKey(UInt16(kVK_ANSI_V), flags: .maskCommand)
        else { finish(.failed); return }
        waitingForPaste = true
        waitForPaste(until: .now() + .milliseconds(1200))
    }

    private var targetIsSelected: Bool {
        guard field.selection == range, !field.hasMultipleSelections else { return false }
        return field.selectedText.map { $0 == original } ?? true
    }

    private func waitForPaste(until deadline: DispatchTime) {
        guard !finished else { return }
        if !cancelled, !stillFocused() { cancelled = true }
        if !field.isSecure, field.text == expectedValue {
            finish(cancelled ? .cancelled : .pasted)
        } else if DispatchTime.now() >= deadline || clipboard?.ownsTemporaryText != true {
            finish(cancelled ? .cancelled : .failed)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) { [weak self] in
                self?.waitForPaste(until: deadline)
            }
        }
    }

    private func finish(_ result: Result) {
        guard !finished else { return }
        finished = true
        clipboard?.restore()
        clipboard = nil
        if (result == .failed || !waitingForPaste), range != snapshot.selection, stillFocused(),
           field.text == snapshot.text, field.selection == range {
            _ = field.select(snapshot.selection)
        }
        completion(result)
    }

    private func postKey(_ key: CGKeyCode, flags: CGEventFlags, count: Int = 1) -> Bool {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return false }
        for event in [down, up] {
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
        }
        for _ in 0..<count {
            down.postToPid(field.pid)
            up.postToPid(field.pid)
        }
        return true
    }
}
