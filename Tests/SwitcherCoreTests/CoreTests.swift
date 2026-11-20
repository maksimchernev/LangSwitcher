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
        print("16 scenarios; \(failures) failed assertions")
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
}
