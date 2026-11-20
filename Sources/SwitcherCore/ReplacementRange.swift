import Foundation

public func replacementRange(in text: String, caret: Int, expected: String) -> NSRange? {
    let length = expected.utf16.count
    guard length > 0, caret >= length, caret <= text.utf16.count else { return nil }
    let range = NSRange(location: caret - length, length: length)
    guard let stringRange = Range(range, in: text), String(text[stringRange]) == expected else { return nil }
    return range
}

public func lastWordRange(in text: String, caret: Int, matchingRecent recent: String) -> NSRange? {
    guard recent.contains(where: { !$0.isWhitespace }),
          let suffix = replacementRange(in: text, caret: caret, expected: recent),
          let suffixRange = Range(suffix, in: text) else { return nil }

    let cursor = suffixRange.upperBound
    var wordEnd = cursor
    while wordEnd > text.startIndex {
        let previous = text.index(before: wordEnd)
        guard text[previous].isWhitespace, !text[previous].isNewline else { break }
        wordEnd = previous
    }
    if wordEnd == cursor, cursor < text.endIndex, !text[cursor].isWhitespace { return nil }

    var start = wordEnd
    while start > text.startIndex {
        let previous = text.index(before: start)
        guard !text[previous].isWhitespace else { break }
        start = previous
    }
    let range = start..<cursor
    guard start < wordEnd, text[range].count <= 2048, text[range].hasSuffix(recent) else { return nil }
    return NSRange(range, in: text)
}
