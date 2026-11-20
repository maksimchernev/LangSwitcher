import Foundation

public struct ConversionCycle {
    public private(set) var text: String
    public private(set) var sourceID: String
    public let strokes: [KeyboardStroke?]
    private var snapshots: [String: String]
    public init(text: String, sourceID: String, strokes: [KeyboardStroke?] = []) {
        self.text = text
        self.sourceID = sourceID
        self.strokes = strokes
        snapshots = [sourceID: text]
    }
    public mutating func advance(in layouts: [KeyboardLayout]) -> KeyboardLayout? {
        guard layouts.count >= 2, let index = layouts.firstIndex(where: { $0.id == sourceID }) else { return nil }
        let source = layouts[index]
        for offset in 1..<layouts.count {
            let target = layouts[(index + offset) % layouts.count]
            guard target.id != sourceID,
                  let result = snapshots[target.id] ?? source.convert(text, to: target, physicalStrokes: strokes),
                  result != text else { continue }
            snapshots[target.id] = result
            text = result
            sourceID = target.id
            return target
        }
        return nil
    }
}
