import Foundation

public func replacementRange(in text: String, caret: Int, expected: String) -> NSRange? {
    let length = expected.utf16.count
    guard length > 0, caret >= length, caret <= text.utf16.count else { return nil }
    let range = NSRange(location: caret - length, length: length)
    guard let stringRange = Range(range, in: text), String(text[stringRange]) == expected else { return nil }
    return range
}
