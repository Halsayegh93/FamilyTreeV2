import Foundation
import os

enum Log {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "FamilyTreeV2",
        category: "App"
    )

    /// Routine traces are noisy during normal runs. Enable only while debugging
    /// with the `-VerboseLogs` launch argument or `VERBOSE_LOGS=1` environment value.
    private static let verboseInfoEnabled: Bool = {
#if DEBUG
        let processInfo = ProcessInfo.processInfo
        return processInfo.arguments.contains("-VerboseLogs")
            || processInfo.environment["VERBOSE_LOGS"] == "1"
#else
        return false
#endif
    }()

    static func info(_ message: String) {
        guard verboseInfoEnabled else { return }
        logger.info("\(message)")
    }

    static func error(_ message: String) {
        logger.error("\(message)")
    }

    static func warning(_ message: String) {
        logger.warning("\(message)")
    }

    /// Masks a phone number for safe logging: "+965XXXX1234" → "+965****1234"
    static func masked(_ phone: String?) -> String {
        guard let phone, phone.count > 4 else { return "***" }
        let suffix = String(phone.suffix(4))
        let prefix = String(phone.prefix(max(0, phone.count - 8)))
        let masked = String(repeating: "*", count: max(0, phone.count - prefix.count - 4))
        return "\(prefix)\(masked)\(suffix)"
    }
}
