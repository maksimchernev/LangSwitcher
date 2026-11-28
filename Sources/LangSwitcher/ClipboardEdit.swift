import AppKit
import Carbon
import SwitcherCore

/// VS Code labels its clipboard payload as a line copy, a selection, or a multi-cursor copy.
private struct EditorCopy: Decodable {
    let version: Int
    let isFromEmptySelection: Bool
    let isBlock: Bool
    let multicursorText: [String]?

    static func read(from pasteboard: NSPasteboard) -> EditorCopy? {
        let type = NSPasteboard.PasteboardType("org.chromium.web-custom-data")
        guard let data = pasteboard.data(forType: type), data.count <= 8_000_000 else { return nil }
        var offset = 0
        // Chromium stores a Pickle header, an entry count, and aligned UTF-16 key/value pairs.
        func readCount() -> Int? {
            guard offset <= data.count - 4 else { return nil }
            let count = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
            offset += 4
            return Int(UInt32(littleEndian: count))
        }
        func readString() -> String? {
            guard let count = readCount(), count <= (data.count - offset) / 2 else { return nil }
            let size = count * 2
            let end = offset + ((size + 3) & ~3)
            guard end <= data.count else { return nil }
            defer { offset = end }
            return String(data: data[offset..<(offset + size)], encoding: .utf16LittleEndian)
        }
        guard let payloadSize = readCount(), payloadSize == data.count - 4,
              let entries = readCount(), entries <= (data.count - offset) / 8 else { return nil }
        for _ in 0..<entries {
            guard let key = readString(), let value = readString() else { return nil }
            if key == "vscode-editor-data" {
                return try? JSONDecoder().decode(Self.self, from: Data(value.utf8))
            }
        }
        return nil
    }
}

final class ClipboardEdit: PendingTextEdit {
    private static let characterLimit = 128

    private let field: TextField
    private let recent: String
    private let stillFocused: () -> Bool
    private let convert: (String, Bool) -> String?
    private let completion: (PasteEdit.Result) -> Void
    private var cancelled = false
    private var userCopyOrCut = false
    private var generatedSelection = false
    private(set) var waitingForPaste = false

    init(field: TextField, recent: String, stillFocused: @escaping () -> Bool,
         convert: @escaping (String, Bool) -> String?, completion: @escaping (PasteEdit.Result) -> Void) {
        self.field = field
        self.recent = recent
        self.stillFocused = stillFocused
        self.convert = convert
        self.completion = completion
    }

    func start() {
        waitingForPaste = true
        Task { @MainActor in
            let pasted = await run()
            waitingForPaste = false
            completion(cancelled ? .cancelled : (pasted ? .pasted : .failed))
        }
    }

    func cancel() { cancelled = true }
    func beforeUserKey(changesClipboard: Bool) {
        if changesClipboard { userCopyOrCut = true }
        if generatedSelection, stillFocused() {
            _ = post(kVK_RightArrow)
            generatedSelection = false
        }
        cancel()
    }

    private var canContinue: Bool { !cancelled && stillFocused() }

    @MainActor private func run() async -> Bool {
        guard CGPreflightPostEventAccess(), canContinue, field.canEdit,
              let initial = field.vscodePosition, initial.hasSelection || !recent.isEmpty,
              let clipboard = PasteboardTransaction(pasteboard: .general) else { return false }
        defer {
            if generatedSelection && canContinue && field.vscodePosition?.hasSelection == true {
                _ = post(kVK_RightArrow)
            }
            clipboard.restore()
        }

        guard let copied = await copy(clipboard, isLine: !initial.hasSelection),
              field.vscodePosition == initial else { return false }
        let original: String
        if initial.hasSelection {
            original = copied
        } else {
            guard let word = wordInCopiedLine(copied, column: initial.column, tabSize: field.vscodeTabSize, recent: recent) else {
                return false
            }
            original = word
        }
        guard !original.isEmpty, original.count <= Self.characterLimit,
              let replacement = convert(original, !initial.hasSelection),
              !replacement.isEmpty, replacement.count <= Self.characterLimit else { return false }

        if !initial.hasSelection {
            guard post(kVK_LeftArrow, flags: .maskShift, count: original.count) else { return false }
            generatedSelection = true
            guard let selected = await waitForPosition(selecting: true), selected.line == initial.line,
                  await copy(clipboard, isLine: false) == original,
                  field.vscodePosition == selected else { return false }
        }
        guard canContinue, field.canEdit, field.vscodePosition?.hasSelection == true,
              clipboard.stage(replacement), canContinue, clipboard.ownsTemporaryText,
              post(kVK_ANSI_V, flags: .maskCommand) else { return false }
        generatedSelection = false
        return await waitForPaste(clipboard)
    }

    @MainActor private func copy(_ clipboard: PasteboardTransaction, isLine: Bool) async -> String? {
        guard canContinue, let baseline = clipboard.copyBaseline,
              post(kVK_ANSI_C, flags: .maskCommand) else { return nil }
        let deadline = DispatchTime.now() + .milliseconds(500)
        // Cmd+C is already queued. Let its clipboard write arrive even if the edit is cancelled.
        while true {
            // A physical copy or cut owns the next clipboard change.
            if userCopyOrCut { return nil }
            if !stillFocused() { cancelled = true }
            var editorCopy: EditorCopy?
            switch clipboard.observeCopy(after: baseline, accepts: { pasteboard in
                guard let meta = EditorCopy.read(from: pasteboard) else { return false }
                editorCopy = meta
                return meta.version == 1 && (!cancelled || meta.isFromEmptySelection == isLine)
            }) {
            case .copied(let text):
                guard !cancelled, let editorCopy, editorCopy.isFromEmptySelection == isLine,
                      !editorCopy.isBlock, editorCopy.multicursorText == nil else { return nil }
                return text
            case .unexpected: return nil
            case .waiting: break
            }
            guard DispatchTime.now() < deadline else { return nil }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @MainActor private func waitForPaste(_ clipboard: PasteboardTransaction) async -> Bool {
        let deadline = DispatchTime.now() + .milliseconds(1200)
        // A queued Cmd+V may still consume the clipboard after focus or input changes.
        while clipboard.ownsTemporaryText, DispatchTime.now() < deadline {
            if !stillFocused() { cancelled = true }
            if !cancelled, field.vscodePosition?.hasSelection == false { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }

    @MainActor private func waitForPosition(selecting: Bool) async -> TextField.EditorPosition? {
        let deadline = DispatchTime.now() + .milliseconds(400)
        while canContinue {
            if let position = field.vscodePosition, position.hasSelection == selecting { return position }
            guard DispatchTime.now() < deadline else { return nil }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }

    private func post(_ key: Int, flags: CGEventFlags = [], count: Int = 1) -> Bool {
        canContinue && PasteEdit.postKey(UInt16(key), flags: flags, count: count, to: field.pid)
    }
}
