import Foundation

public struct EditSnapshot: Equatable {
    public let revision: Int
    public let text: String
    public let selection: NSRange
    public init(revision: Int, text: String, selection: NSRange) {
        self.revision = revision
        self.text = text
        self.selection = selection
    }
    public func matches(_ other: EditSnapshot) -> Bool { self == other }
}
