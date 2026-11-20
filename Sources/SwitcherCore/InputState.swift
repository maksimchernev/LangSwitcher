import Foundation

public struct TypedWord {
    public private(set) var text = ""
    public private(set) var sourceID: String?
    public private(set) var expectedCaret: Int?
    public private(set) var strokes: [KeyboardStroke?] = []
    private var discardedLongWord = false
    private var caretBeforeLastInput: Int?
    public init() {}
    public mutating func append(_ characters: String, sourceID: String, at caret: Int? = nil, stroke: KeyboardStroke? = nil) {
        if self.sourceID != sourceID { reset() }
        var insertionCaret = caret
        if let caret, let expectedCaret, caret != expectedCaret {
            // The editor can expose the caret from just before the preceding keystroke.
            // Conversion still requires the predicted caret and actual text to agree.
            if caret == caretBeforeLastInput { insertionCaret = expectedCaret }
            else { reset() }
        }
        for character in characters {
            if character == "\n" || character == "\r" || character == "\t" {
                reset()
                continue
            }
            if character.isWhitespace {
                if discardedLongWord { reset() }
                if !text.isEmpty { text.append(character); strokes.append(stroke) }
            } else {
                guard !discardedLongWord else { continue }
                if text.last?.isWhitespace == true { text = ""; strokes = [] }
                text.append(character)
                strokes.append(stroke)
                self.sourceID = sourceID
            }
            if text.count > 2048 {
                text = ""
                strokes = []
                discardedLongWord = true
            }
        }
        if let insertionCaret, !text.isEmpty, insertionCaret <= Int.max - characters.utf16.count {
            caretBeforeLastInput = insertionCaret
            expectedCaret = insertionCaret + characters.utf16.count
        }
    }
    public mutating func backspace(at caret: Int? = nil) {
        if let caret, let expectedCaret, caret != expectedCaret { reset(); return }
        guard !text.isEmpty else { return }
        let removed = text.removeLast()
        if !strokes.isEmpty { strokes.removeLast() }
        if let expectedCaret { self.expectedCaret = expectedCaret - removed.utf16.count }
        caretBeforeLastInput = nil
        if text.isEmpty { sourceID = nil }
    }
    public mutating func reset() {
        text = ""
        strokes = []
        sourceID = nil
        expectedCaret = nil
        caretBeforeLastInput = nil
        discardedLongWord = false
    }
    public mutating func replace(with text: String, sourceID: String, caret: Int? = nil, strokes: [KeyboardStroke?] = []) {
        reset()
        guard text.count <= 2048 else { return }
        self.text = text
        self.sourceID = sourceID
        expectedCaret = caret
        self.strokes = strokes.count == text.count ? strokes : Array(repeating: nil, count: text.count)
    }
}

public struct ModifierTap {
    private var armed = false
    public init() {}
    public mutating func press(alone: Bool, otherKeysDown: Bool = false, mouseDown: Bool = false) {
        armed = alone && !otherKeysDown && !mouseDown
    }
    public mutating func cancel() { armed = false }
    public mutating func release() -> Bool {
        defer { armed = false }
        return armed
    }
}
