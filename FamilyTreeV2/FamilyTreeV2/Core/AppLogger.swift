import Foundation
import os

enum Log {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "FamilyTreeV2",
        category: "App"
    )

    static func info(_ message: String) {
        logger.info("\(message)")
    }

    static func error(_ message: String) {
        logger.error("\(message)")
    }

    static func warning(_ message: String) {
        logger.warning("\(message)")
    }
}
