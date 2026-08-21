import Foundation

public struct TemperSwiftError: LocalizedError, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String { self.message }
    public var description: String { self.message }
}
