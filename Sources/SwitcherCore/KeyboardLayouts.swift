import Foundation
import Carbon

public struct KeyboardStroke: Hashable {
    public let key: UInt16
    public let modifiers: UInt32
    public init(key: UInt16, shift: Bool = false, capsLock: Bool = false) {
        self.key = key
        self.modifiers = (shift ? UInt32(shiftKey) : 0) | (capsLock ? UInt32(alphaLock) : 0)
    }
    init(key: UInt16, modifiers: UInt32) { self.key = key; self.modifiers = modifiers }
}

public struct KeyboardLayout {
    public let id: String
    public let name: String
    let source: TISInputSource
    private let characters: [KeyboardStroke: String]
    private let strokes: [Character: KeyboardStroke]

    init?(_ source: TISInputSource) {
        guard let id = Self.string(source, kTISPropertyInputSourceID),
              let name = Self.string(source, kTISPropertyLocalizedName),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = unsafeBitCast(raw, to: CFData.self) as Data
        var forward: [KeyboardStroke: String] = [:]
        var reverse: [Character: KeyboardStroke] = [:]
        data.withUnsafeBytes { bytes in
            guard let pointer = bytes.baseAddress else { return }
            let layout = pointer.assumingMemoryBound(to: UCKeyboardLayout.self)
            for modifiers in [UInt32(0), UInt32(shiftKey), UInt32(alphaLock), UInt32(shiftKey | alphaLock)] {
                for key in UInt16(0)..<UInt16(128) {
                    var dead: UInt32 = 0
                    var length = 0
                    var output = [UniChar](repeating: 0, count: 16)
                    let status = UCKeyTranslate(layout, key, UInt16(kUCKeyActionDown),
                        modifiers >> 8, UInt32(LMGetKbdType()),
                        OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead,
                        output.count, &length, &output)
                    guard status == noErr, length > 0 else { continue }
                    let text = String(utf16CodeUnits: output, count: length)
                    guard text.count == 1, let character = text.first,
                          !character.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
                    else { continue }
                    let stroke = KeyboardStroke(key: key, modifiers: modifiers)
                    forward[stroke] = text
                    if reverse[character] == nil { reverse[character] = stroke }
                }
            }
        }
        guard !forward.isEmpty else { return nil }
        self.id = id
        self.name = name
        self.source = source
        characters = forward
        strokes = reverse
    }

    public func convert(_ text: String, to target: KeyboardLayout, physicalStrokes: [KeyboardStroke?] = []) -> String? {
        let usePhysical = physicalStrokes.count == text.count
        let result = text.enumerated().map { index, character -> String in
            guard !character.isWhitespace,
                  let stroke = (usePhysical ? physicalStrokes[index] : nil) ?? strokes[character],
                  let translated = target.characters[stroke] else { return String(character) }
            return translated
        }.joined()
        return result == text ? nil : result
    }

    func letterScore(_ text: String) -> Int {
        text.reduce(0) { $0 + ($1.isLetter && strokes[$1] != nil ? 1 : 0) }
    }

    static func string(_ source: TISInputSource, _ property: CFString) -> String? {
        guard let value = TISGetInputSourceProperty(source, property) else { return nil }
        return unsafeBitCast(value, to: CFString.self) as String
    }
}

public final class KeyboardLayouts {
    public private(set) var enabled: [KeyboardLayout] = []
    public init() { refresh() }

    public func refresh() {
        let filter = [kTISPropertyInputSourceType!: kTISTypeKeyboardLayout!,
                      kTISPropertyInputSourceIsEnabled: kCFBooleanTrue!] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false).takeRetainedValue() as! [TISInputSource]
        enabled = sources.compactMap(KeyboardLayout.init)
    }

    public var currentID: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return KeyboardLayout.string(source, kTISPropertyInputSourceID)
    }

    public func conversion(_ text: String, sourceID: String?) -> (text: String, target: KeyboardLayout)? {
        guard let source = inferredSource(for: text, preferredID: sourceID) else { return nil }
        var cycle = ConversionCycle(text: text, sourceID: source.id)
        guard let target = cycle.advance(in: enabled) else { return nil }
        return (cycle.text, target)
    }

    public func inferredSource(for text: String, preferredID: String?) -> KeyboardLayout? {
        guard enabled.count >= 2 else { return nil }
        let preferred = enabled.firstIndex { $0.id == preferredID } ?? 0
        var index = preferred
        var score = enabled[preferred].letterScore(text)
        for candidate in enabled.indices {
            let candidateScore = enabled[candidate].letterScore(text)
            if candidateScore > score { index = candidate; score = candidateScore }
        }
        return enabled[index]
    }

    @discardableResult public func select(_ layout: KeyboardLayout) -> Bool {
        TISSelectInputSource(layout.source) == noErr
    }
}
