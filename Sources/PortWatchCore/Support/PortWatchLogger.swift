import Foundation
import os

public protocol PortWatchLogging: Sendable {
    func info(_ message: String)
    func error(_ message: String)
}

public struct PortWatchLogger: PortWatchLogging {
    private let logger: Logger

    public init(subsystem: String = "PortWatch", category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
