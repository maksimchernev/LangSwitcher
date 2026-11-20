import AppKit
import Foundation
import SwitcherCore

func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    check(actual == expected, "expected \(expected), got \(actual)", file: file, line: line)
}
func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    check(value, "expected true", file: file, line: line)
}
func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    check(!value, "expected false", file: file, line: line)
}
func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    check(value == nil, "expected nil", file: file, line: line)
}
var failures = 0
func check(_ condition: Bool, _ message: String, file: StaticString, line: UInt) {
    if !condition {
        failures += 1
        print("FAIL \(file):\(line): \(message)")
    }
}

@main struct CoreTests {
    static func main() {
        let tests = CoreTests()
        tests.testTracksOnlyWordAfterLastSpace()
        tests.testKeepsTrailingSpacesAndStartsNextWord()
        tests.testBackspaceTracksExactlyWhatRemains()
        tests.testSourceChangeAndFocusResetDiscardOldText()
        tests.testRepeatedConversionRetainsTargetSource()
        tests.testReturnDoesNotReachIntoSentMessage()
        tests.testStandaloneModifierFiresOnce()
        tests.testCombinationAndMouseCancelModifier()
        tests.testLongInputIsBoundedWithoutKeepingPartialWord()
        tests.testActualSystemLayoutConversion()
        tests.testReplacementCannotDeleteStaleTextOrSplitUnicode()
        tests.testEditSnapshotRejectsChangedFocusRevisionSelectionAndValue()
        tests.testIdenticalEarlierWordCannotReuseTypingHistory()
        tests.testAlreadyHeldKeyOrMousePreventsModifierTap()
        tests.testMixedSelectionRoundTripIsExactAndEquivalentLayoutsAreSkipped()
        tests.testCapsLockPunctuationRetainsPhysicalStroke()
        tests.testFindsWholeWordWhenBrowserOnlyTrackedItsSuffix()
        tests.testWordRangeRejectsMiddleOfWordAndUnrelatedText()
        tests.testTypingHistoryToleratesOneEventOfCaretLag()
        tests.testPasteboardRestoresTextAndOtherRepresentations()
        tests.testPasteboardRestoresAnEmptyBoard()
        tests.testPasteboardKeepsContentsCopiedDuringTheEdit()
        tests.testPasteboardDoesNotStageOverNewerContents()
        tests.testPasteboardDeclinesFilePromises()
        tests.testNativeTextPasteReplacesWholeWordAndRestoresClipboard()
        print("25 scenarios; \(failures) failed assertions")
        if failures > 0 { exit(1) }
    }
    func testTracksOnlyWordAfterLastSpace() {
        var word = TypedWord()
        word.append("earlier ghbdtn", sourceID: "en")
        XCTAssertEqual(word.text, "ghbdtn")
        XCTAssertEqual(word.sourceID, "en")
    }

    func testKeepsTrailingSpacesAndStartsNextWord() {
        var word = TypedWord()
        word.append("ghbdtn  ", sourceID: "en")
        XCTAssertEqual(word.text, "ghbdtn  ")
        word.append("vbh", sourceID: "en")
        XCTAssertEqual(word.text, "vbh")
    }

    func testBackspaceTracksExactlyWhatRemains() {
        var word = TypedWord()
        word.append("ghbdtn ", sourceID: "en")
        word.backspace()
        XCTAssertEqual(word.text, "ghbdtn")
        word.backspace()
        XCTAssertEqual(word.text, "ghbdt")
    }

    func testSourceChangeAndFocusResetDiscardOldText() {
        var word = TypedWord()
        word.append("old", sourceID: "en")
        word.append("новое", sourceID: "ru")
        XCTAssertEqual(word.text, "новое")
        word.reset()
        XCTAssertEqual(word.text, "")
        XCTAssertNil(word.sourceID)
    }

    func testRepeatedConversionRetainsTargetSource() {
        var word = TypedWord()
        word.append("ghbdtn ", sourceID: "en")
        word.replace(with: "привет ", sourceID: "ru")
        XCTAssertEqual(word.text, "привет ")
        XCTAssertEqual(word.sourceID, "ru")
        word.replace(with: "ghbdtn ", sourceID: "en")
        XCTAssertEqual(word.text, "ghbdtn ")
    }

    func testReturnDoesNotReachIntoSentMessage() {
        var word = TypedWord()
        word.append("ghbdtn\n", sourceID: "en")
        XCTAssertEqual(word.text, "")
        word.append("vbh", sourceID: "en")
        XCTAssertEqual(word.text, "vbh")
    }

    func testStandaloneModifierFiresOnce() {
        var tap = ModifierTap()
        tap.press(alone: true)
        XCTAssertTrue(tap.release())
        XCTAssertFalse(tap.release())
    }

    func testCombinationAndMouseCancelModifier() {
        var tap = ModifierTap()
        tap.press(alone: true)
        tap.cancel()
        XCTAssertFalse(tap.release())
        tap.press(alone: false)
        XCTAssertFalse(tap.release())
    }

    func testLongInputIsBoundedWithoutKeepingPartialWord() {
        var word = TypedWord()
        word.append(String(repeating: "a", count: 5000), sourceID: "en")
        XCTAssertEqual(word.text, "")
        word.append("tail", sourceID: "en")
        XCTAssertEqual(word.text, "")
        word.append(" next", sourceID: "en")
        XCTAssertEqual(word.text, "next")
    }

    func testActualSystemLayoutConversion() {
        let layouts = KeyboardLayouts()
        print("System layouts: \(layouts.enabled.map { "\($0.name) [\($0.id)]" }.joined(separator: ", "))")
        guard let en = layouts.enabled.first(where: { $0.id == "com.apple.keylayout.ABC" || $0.id == "com.apple.keylayout.US" }),
              let ru = layouts.enabled.first(where: { $0.id.lowercased().contains("russian") }) else {
            print("SKIP: English and Russian must be enabled for layout integration checks")
            return
        }
        XCTAssertEqual(en.convert("ghbdtn  ", to: ru), "привет  ")
        XCTAssertEqual(ru.convert("привет", to: en), "ghbdtn")
        XCTAssertEqual(en.convert("Ghbdtn", to: ru), "Привет")
        XCTAssertEqual(en.convert("[kt,", to: ru), "хлеб")
        XCTAssertEqual(en.convert("hello\nworld", to: ru), "руддщ\nцщкдв")
        XCTAssertEqual(layouts.conversion("привет", sourceID: en.id)?.text, "ghbdtn")
    }

    func testReplacementCannotDeleteStaleTextOrSplitUnicode() {
        XCTAssertEqual(replacementRange(in: "👋 ghbdtn next", caret: 9, expected: "ghbdtn"), NSRange(location: 3, length: 6))
        XCTAssertNil(replacementRange(in: "something else", caret: 9, expected: "ghbdtn"))
        XCTAssertNil(replacementRange(in: "ghbdtn", caret: 7, expected: "ghbdtn"))
        XCTAssertNil(replacementRange(in: "ghbdtn", caret: -1, expected: "ghbdtn"))
        XCTAssertNil(replacementRange(in: "ghbdtn", caret: 0, expected: ""))
    }

    func testEditSnapshotRejectsChangedFocusRevisionSelectionAndValue() {
        let edit = EditSnapshot(revision: 3, text: "ghbdtn", selection: NSRange(location: 6, length: 0))
        XCTAssertTrue(edit.matches(edit))
        XCTAssertFalse(edit.matches(EditSnapshot(revision: 4, text: "ghbdtn", selection: edit.selection)))
        XCTAssertFalse(edit.matches(EditSnapshot(revision: 3, text: "other", selection: edit.selection)))
        XCTAssertFalse(edit.matches(EditSnapshot(revision: 3, text: "ghbdtn", selection: NSRange(location: 0, length: 6))))
    }

    func testIdenticalEarlierWordCannotReuseTypingHistory() {
        var word = TypedWord()
        word.append("ghbdtn", sourceID: "en", at: 20)
        XCTAssertEqual(word.expectedCaret, 26)
        // A programmatic caret move to an older identical word starts fresh.
        word.append("x", sourceID: "en", at: 6)
        XCTAssertEqual(word.text, "x")
        XCTAssertEqual(word.expectedCaret, 7)
        word.reset()
        XCTAssertNil(word.expectedCaret)
    }

    func testAlreadyHeldKeyOrMousePreventsModifierTap() {
        var tap = ModifierTap()
        tap.press(alone: true, otherKeysDown: true)
        XCTAssertFalse(tap.release())
        tap.press(alone: true, mouseDown: true)
        XCTAssertFalse(tap.release())
    }

    func testMixedSelectionRoundTripIsExactAndEquivalentLayoutsAreSkipped() {
        let layouts = KeyboardLayouts()
        guard let en = layouts.enabled.first(where: { $0.id == "com.apple.keylayout.ABC" }),
              let ru = layouts.enabled.first(where: { $0.id.lowercased().contains("russian") }) else { return }
        var cycle = ConversionCycle(text: "aя", sourceID: en.id)
        XCTAssertEqual(cycle.advance(in: [en, ru])?.id, ru.id)
        XCTAssertEqual(cycle.text, "фя")
        XCTAssertEqual(cycle.advance(in: [en, ru])?.id, en.id)
        XCTAssertEqual(cycle.text, "aя")
        var equivalent = ConversionCycle(text: "ghbdtn", sourceID: en.id)
        XCTAssertEqual(equivalent.advance(in: [en, en, ru])?.id, ru.id)
        XCTAssertEqual(equivalent.text, "привет")
    }

    func testCapsLockPunctuationRetainsPhysicalStroke() {
        let layouts = KeyboardLayouts()
        guard let en = layouts.enabled.first(where: { $0.id == "com.apple.keylayout.ABC" }),
              let ru = layouts.enabled.first(where: { $0.id.lowercased().contains("russian") }) else { return }
        var word = TypedWord()
        word.append("[", sourceID: en.id, at: 0, stroke: KeyboardStroke(key: 33, capsLock: true))
        XCTAssertEqual(en.convert(word.text, to: ru, physicalStrokes: word.strokes), "Х")
    }

    func testFindsWholeWordWhenBrowserOnlyTrackedItsSuffix() {
        let text = "тест привет "
        let range = lastWordRange(in: text, caret: 12, matchingRecent: "ривет ")
        XCTAssertEqual(range, NSRange(location: 5, length: 7))
        if let range, let swiftRange = Range(range, in: text) {
            XCTAssertEqual(text.replacingCharacters(in: swiftRange, with: "ghbdtn "), "тест ghbdtn ")
        }
        XCTAssertEqual(lastWordRange(in: "👋 [kt,  more", caret: 9, matchingRecent: "kt,  "),
                       NSRange(location: 3, length: 6))
    }

    func testWordRangeRejectsMiddleOfWordAndUnrelatedText() {
        XCTAssertNil(lastWordRange(in: "приветствие", caret: 6, matchingRecent: "ривет"))
        XCTAssertNil(lastWordRange(in: "тест привет ", caret: 12, matchingRecent: "руддщ "))
        XCTAssertNil(lastWordRange(in: "привет\n ", caret: 8, matchingRecent: " "))
        XCTAssertNil(lastWordRange(in: "привет ", caret: 7, matchingRecent: ""))
    }

    func testTypingHistoryToleratesOneEventOfCaretLag() {
        var word = TypedWord()
        word.append("п", sourceID: "ru", at: 0)
        for (caret, character) in "ривет ".enumerated() {
            word.append(String(character), sourceID: "ru", at: caret)
        }
        XCTAssertEqual(word.text, "привет ")
        XCTAssertEqual(word.expectedCaret, 7)
        XCTAssertEqual(lastWordRange(in: "привет ", caret: 7, matchingRecent: word.text),
                       NSRange(location: 0, length: 7))
    }

    func testPasteboardRestoresTextAndOtherRepresentations() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let textAndURL = NSPasteboardItem()
        textAndURL.setString("макс", forType: .string)
        textAndURL.setString("https://example.com", forType: .URL)
        let secondItem = NSPasteboardItem()
        let dataType = NSPasteboard.PasteboardType("com.example.binary")
        secondItem.setData(Data([3, 1, 4]), forType: dataType)
        XCTAssertTrue(board.writeObjects([textAndURL, secondItem]))

        let edit = PasteboardTransaction(pasteboard: board)
        XCTAssertEqual(edit?.stage("ghbdtn "), true)
        XCTAssertEqual(board.string(forType: .string), "ghbdtn ")
        edit?.restore()

        XCTAssertEqual(board.string(forType: .string), "макс")
        XCTAssertEqual(board.string(forType: .URL), "https://example.com")
        XCTAssertEqual(board.pasteboardItems?.count, 2)
        XCTAssertEqual(board.pasteboardItems?.last?.data(forType: dataType), Data([3, 1, 4]))
    }

    func testPasteboardRestoresAnEmptyBoard() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let edit = PasteboardTransaction(pasteboard: board)
        XCTAssertEqual(edit?.stage("ghbdtn "), true)
        XCTAssertEqual(edit?.ownsTemporaryText, true)
        edit?.restore()
        XCTAssertTrue(board.pasteboardItems?.isEmpty ?? true)
        XCTAssertNil(board.string(forType: .string))
    }

    func testPasteboardKeepsContentsCopiedDuringTheEdit() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("макс", forType: .string)
        let edit = PasteboardTransaction(pasteboard: board)
        XCTAssertEqual(edit?.stage("ghbdtn "), true)
        board.clearContents()
        board.setString("новое", forType: .string)
        XCTAssertEqual(edit?.ownsTemporaryText, false)
        edit?.restore()
        XCTAssertEqual(board.string(forType: .string), "новое")
    }

    func testPasteboardDoesNotStageOverNewerContents() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("макс", forType: .string)
        let edit = PasteboardTransaction(pasteboard: board)
        board.clearContents()
        board.setString("новое", forType: .string)
        XCTAssertEqual(edit?.stage("ghbdtn "), false)
        XCTAssertEqual(board.string(forType: .string), "новое")
    }

    func testPasteboardDeclinesFilePromises() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let promise = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")
        board.setString("file:///example-file", forType: promise)
        XCTAssertNil(PasteboardTransaction(pasteboard: board))
        XCTAssertEqual(board.string(forType: promise), "file:///example-file")
    }

    func testNativeTextPasteReplacesWholeWordAndRestoresClipboard() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        XCTAssertTrue(board.setString("макс", forType: .string))
        let editor = NSTextView(frame: .zero)
        editor.string = "тест привет "
        let layouts = KeyboardLayouts().enabled
        guard let ru = layouts.first(where: { $0.id == "com.apple.keylayout.Russian" }),
              let en = layouts.first(where: { $0.id == "com.apple.keylayout.ABC" || $0.id == "com.apple.keylayout.US" })
        else {
            print("SKIP: ABC and Russian must be enabled for the native paste check")
            return
        }
        guard let range = lastWordRange(in: editor.string, caret: 12, matchingRecent: "ривет "),
              let swiftRange = Range(range, in: editor.string),
              let correction = ru.convert(String(editor.string[swiftRange]), to: en)
        else {
            check(false, "expected a complete word and layout conversion", file: #filePath, line: #line)
            return
        }
        editor.setSelectedRange(range)
        let edit = PasteboardTransaction(pasteboard: board)
        XCTAssertEqual(edit?.stage(correction), true)
        XCTAssertTrue(editor.readSelection(from: board, type: .string))
        edit?.restore()
        XCTAssertEqual(editor.string, "тест ghbdtn ")
        XCTAssertEqual(board.string(forType: .string), "макс")
    }
}
