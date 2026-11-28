import Foundation

public struct ReplayWord {
    public let text: String
    public let strokes: [KeyboardStroke]

    public init?(word: TypedWord, source: KeyboardLayout, target: KeyboardLayout) {
        let original = word.text
        let strokes = word.strokes.compactMap { $0 }
        guard (1...64).contains(original.count), strokes.count == original.count,
              word.sourceID == source.id, source.id != target.id,
              original.allSatisfy({ $0.unicodeScalars.count == 1 && ($0.isLetter || $0 == " ") }),
              original.contains(where: \.isLetter),
              source.replayText(for: strokes) == original,
              let replacement = target.replayText(for: strokes), replacement != original,
              replacement.unicodeScalars.count == original.unicodeScalars.count,
              replacement.allSatisfy({ $0.isLetter || $0 == " " }) else { return nil }
        text = replacement
        self.strokes = strokes
    }
}
