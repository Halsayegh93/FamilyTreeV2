import Foundation
import Supabase

struct SupabaseConfig {
    private enum InfoKeys {
        static let url = "SUPABASE_URL"
        static let anonKey = "SUPABASE_ANON_KEY"
        static let otpFallbackURL = "OTP_FALLBACK_URL"
        static let otpFallbackAPIKey = "OTP_FALLBACK_API_KEY"
    }

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

        guard let parsedURL = URL(string: finalValue) else {
            // Graceful fallback instead of crashing in production
            assertionFailure("Invalid Supabase URL value: \(finalValue)")
            return URL(string: "https://placeholder.supabase.co")!
        }

        return parsedURL
    }()

    static let key: String = {
        readInfoValue(InfoKeys.anonKey) ?? Defaults.anonKey
    }()
    
    // Optional endpoint for alternate OTP delivery (e.g. WhatsApp/Voice).
    static let otpFallbackURL: URL? = {
        if let value = readInfoValue(InfoKeys.otpFallbackURL) {
            return URL(string: value)
        }
        return URL(string: "functions/v1/otp-fallback", relativeTo: url)?.absoluteURL
    }()
    
    static let otpFallbackAPIKey: String? = {
        readInfoValue(InfoKeys.otpFallbackAPIKey)
    }()
    
    static let client = SupabaseClient(
        supabaseURL: url,
        supabaseKey: key,
        options: SupabaseClientOptions(
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
    )
}
