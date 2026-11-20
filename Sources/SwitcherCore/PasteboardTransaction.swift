import AppKit

public final class PasteboardTransaction {
    private static let marker = NSPasteboard.PasteboardType("local.langswitcher.temporary-paste")
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let pasteboard: NSPasteboard
    private let originalItems: [NSPasteboardItem]
    private let originalVersion: Int
    private let token = UUID().uuidString
    private var stagedVersion: Int?
    private var didWriteText = false

    public init?(pasteboard: NSPasteboard) {
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny { return nil }
        let version = pasteboard.changeCount
        guard let items = pasteboard.pasteboardItems else { return nil }

        // Items held by the pasteboard become invalid when its contents change.
        var copied: [NSPasteboardItem] = []
        var remainingBytes = 32 * 1024 * 1024
        for item in items {
            let detachedItem = NSPasteboardItem()
            guard !item.types.isEmpty else { return nil }
            for type in item.types {
                // A file promise depends on its original owner's live provider.
                let name = type.rawValue.lowercased()
                guard !name.contains("promised-file"), !name.contains("filepromise"), !name.contains("files promise"),
                      let data = item.data(forType: type), data.count <= remainingBytes,
                      detachedItem.setData(data, forType: type) else { return nil }
                remainingBytes -= data.count
            }
            copied.append(detachedItem)
        }
        guard pasteboard.changeCount == version else { return nil }
        self.pasteboard = pasteboard
        originalItems = copied
        originalVersion = version
    }

    public func stage(_ text: String) -> Bool {
        guard stagedVersion == nil, pasteboard.changeCount == originalVersion else { return false }
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string),
              item.setString(token, forType: Self.marker),
              item.setData(Data(), forType: Self.transient),
              pasteboard.changeCount == originalVersion else { return false }

        stagedVersion = pasteboard.prepareForNewContents(with: .currentHostOnly)
        guard pasteboard.changeCount == stagedVersion, pasteboard.writeObjects([item]) else {
            restore()
            return false
        }
        didWriteText = true
        stagedVersion = pasteboard.changeCount
        return ownsTemporaryText
    }

    public var ownsTemporaryText: Bool {
        guard let stagedVersion, didWriteText, pasteboard.changeCount == stagedVersion else { return false }
        return pasteboard.string(forType: Self.marker) == token && pasteboard.changeCount == stagedVersion
    }

    public func restore() {
        guard let version = stagedVersion else { return }
        defer { stagedVersion = nil }
        guard didWriteText ? ownsTemporaryText : pasteboard.changeCount == version else { return }
        // The previous owner's transfer options aren't available, so keep this write on this Mac.
        let emptyVersion = pasteboard.prepareForNewContents(with: .currentHostOnly)
        if !originalItems.isEmpty, pasteboard.changeCount == emptyVersion {
            _ = pasteboard.writeObjects(originalItems)
        }
    }

    deinit { restore() }
}
