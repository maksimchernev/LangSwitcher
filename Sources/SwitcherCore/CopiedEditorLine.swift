import Foundation

/// Maps VS Code's one-based status bar column back into a copied model line.
public func wordInCopiedLine(_ copied: String, column: Int, tabSize: Int?, recent: String) -> String? {
    guard column > 0, copied.utf16.count <= 1_000_000 else { return nil }
    var line = copied
    if line.last?.isNewline == true { line.removeLast() }
    guard !line.contains(where: \.isNewline) else { return nil }
    var displayed = 1
    var offset = 0
    for scalar in line.unicodeScalars {
        if displayed >= column { break }
        if scalar == "\t" {
            guard let tabSize, (1...256).contains(tabSize) else { return nil }
            displayed += tabSize - (displayed - 1) % tabSize
        } else {
            displayed += 1
        }
        offset += scalar.value > 0xFFFF ? 2 : 1
    }
    guard displayed == column,
          let range = lastWordRange(in: line, caret: offset, matchingRecent: recent),
          let indices = Range(range, in: line) else { return nil }
    return String(line[indices])
}
