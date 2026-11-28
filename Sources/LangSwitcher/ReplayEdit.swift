import AppKit
import Carbon
import SwitcherCore

final class ReplayEdit: PendingTextEdit {
    private let field: TextField
    private let word: ReplayWord
    private let layouts: KeyboardLayouts
    private let original: KeyboardLayout
    private let target: KeyboardLayout
    private let stillValid: () -> Bool
    private let completion: (Bool) -> Void
    private var cancelled = false
    private(set) var waitingForPaste = false

    init(field: TextField, word: ReplayWord, layouts: KeyboardLayouts,
         original: KeyboardLayout, target: KeyboardLayout,
         stillValid: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
        self.field = field
        self.word = word
        self.layouts = layouts
        self.original = original
        self.target = target
        self.stillValid = stillValid
        self.completion = completion
    }

    func start() {
        waitingForPaste = true
        Task { @MainActor in
            let sent = await replay()
            waitingForPaste = false
            completion(sent)
        }
    }

    func cancel() { cancelled = true }
    func beforeUserKey(changesClipboard: Bool) { cancel() }

    @MainActor private func replay() async -> Bool {
        guard !cancelled, stillValid(), layouts.currentID == original.id, layouts.select(target) else { return false }
        var sent = false
        defer {
            if !sent, layouts.currentID == target.id { _ = layouts.select(original) }
        }
        let deadline = DispatchTime.now() + .milliseconds(350)
        while !cancelled, layouts.currentID != target.id {
            guard DispatchTime.now() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
        guard !cancelled, let events = prepareEvents(), stillValid(), layouts.currentID == target.id else { return false }
        for event in events { event.postToPid(field.pid) }
        sent = true
        return true
    }

    private func prepareEvents() -> [CGEvent]? {
        guard let source = CGEventSource(stateID: .privateState) else { return nil }
        var events: [CGEvent] = []
        func appendKey(_ key: UInt16, flags: CGEventFlags) -> Bool {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return false }
                event.flags = flags
                event.setIntegerValueField(.eventSourceUserData, value: PasteEdit.eventMarker)
                events.append(event)
            }
            return true
        }
        for _ in word.strokes {
            guard appendKey(UInt16(kVK_Delete), flags: []) else { return nil }
        }
        for stroke in word.strokes {
            var flags: CGEventFlags = []
            if stroke.modifiers & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
            if stroke.modifiers & UInt32(alphaLock) != 0 { flags.insert(.maskAlphaShift) }
            guard appendKey(stroke.key, flags: flags) else { return nil }
        }
        return events
    }
}
