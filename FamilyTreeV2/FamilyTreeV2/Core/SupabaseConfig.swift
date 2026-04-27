import Foundation
import Supabase
import os

/// مسجل مخصص يمرر فقط التحذيرات والأخطاء ويتجاهل الرسائل الكثيرة
private struct QuietSupabaseLogger: SupabaseLogger {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "FamilyTreeV2",
        category: "Supabase"
    )

    func log(message: SupabaseLogMessage) {
        switch message.level {
        case .warning:
            logger.warning("\(message.description)")
        case .error:
            logger.error("\(message.description)")
        default:
            break // تجاهل verbose و debug
        }
    }
}

struct SupabaseConfig {
    private enum InfoKeys {
        static let url = "SUPABASE_URL"
        static let anonKey = "SUPABASE_ANON_KEY"
    }

    // NOTE: Supabase anon key مقصود أن يكون علنياً في client bundle — الحماية الفعلية
    // تتم عبر Row Level Security (RLS) على الجداول في الـ backend، وليس بإخفاء المفتاح.
    // راجع: https://supabase.com/docs/guides/auth/row-level-security
    // للـ best practice: انقل القيم إلى xcconfig غير محفوظ في git وأضف `SUPABASE_URL` /
    // `SUPABASE_ANON_KEY` كـ INFOPLIST_KEY_* في Build Settings — الكود يقرأهم من Info.plist تلقائياً.
    private enum Defaults {
        static let url = "https://poxyxsgvzwmnmewytsiw.supabase.co"
        static let anonKey = "sb_publishable_o4VLYXBvBhvmvAv0n_z68g_JAMIb6v1"
    }

    private static func readInfoValue(_ key: String) -> String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static let url: URL = {
        let finalValue = readInfoValue(InfoKeys.url) ?? Defaults.url

        if let parsedURL = URL(string: finalValue) {
            return parsedURL
        }

        // Fallback لا يصل إليه عملياً (URL strings الصالحة أعلاه)، لكن يحافظ على type safety بدون force unwrap
        assertionFailure("Invalid Supabase URL value: \(finalValue)")
        return URL(string: Defaults.url) ?? URL(fileURLWithPath: "/dev/null")
    }()

    static let key: String = {
        readInfoValue(InfoKeys.anonKey) ?? Defaults.anonKey
    }()
    
    /// Central Supabase client.
    /// Keep client access on the MainActor to avoid structural concurrency warnings
    /// from the underlying SDK during startup / realtime wiring.
    @MainActor
    static let client = SupabaseClient(
        supabaseURL: url,
        supabaseKey: key,
        options: SupabaseClientOptions(
            auth: .init(emitLocalSessionAsInitialSession: true),
            global: .init(logger: QuietSupabaseLogger())
        )
    )
}
