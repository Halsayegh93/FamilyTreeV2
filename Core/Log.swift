import Foundation

enum LegacyLog {
    static func info(_ message: String) {
        print("[INFO] \(message)")
    }

    static func warning(_ message: String) {
        print("[WARN] \(message)")
    }

    static func error(_ message: String) {
        print("[ERROR] \(message)")
    }
}
