import Foundation
import SwiftUI
import Combine
import Supabase

enum ConfigValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), array([ConfigValue]), object([String: ConfigValue]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([ConfigValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: ConfigValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    var text: String? { if case .string(let v) = self { return v }; return nil }
    var number: Double? { if case .number(let v) = self { return v }; return nil }
    var strings: [String]? {
        guard case .array(let v) = self, v.allSatisfy({ $0.text != nil }) else { return nil }
        return v.compactMap(\.text)
    }
    var editorText: String {
        if let text { return text }
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Only public values persist across launches; member values are kept in memory and replaced on every session change.
final class RemoteSettingsCache: @unchecked Sendable {
    static let shared = RemoteSettingsCache()
    private let lock = NSLock()
    private var values: [String: ConfigValue] = [:]
    private let publicKeys: Set<String> = ["site_url", "privacy_url", "privacy_url_en", "terms_url", "terms_url_en", "support_email"]
    private init() {
        if let data = UserDefaults.standard.data(forKey: "remote.publicSettings"),
           let v = try? JSONDecoder().decode([String: ConfigValue].self, from: data) { values = v }
    }
    func value(_ key: String) -> ConfigValue? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func replace(_ incoming: [String: ConfigValue]) {
        lock.lock(); values = incoming; lock.unlock()
        let pub = incoming.filter { publicKeys.contains($0.key) }
        if let data = try? JSONEncoder().encode(pub) { UserDefaults.standard.set(data, forKey: "remote.publicSettings") }
    }
    func clearMemberValues() {
        lock.lock(); values = values.filter { publicKeys.contains($0.key) }; lock.unlock()
    }
}

enum RemoteSettings {
    // Preserve the app's existing translations until the owner customizes a notification.
    private static let notificationDefaults: [String: String] = [
        "notify_join_approved_title": "تم قبول طلبك",
        "notify_join_approved_body": "وافقت الإدارة على انضمامك — مرحباً في عائلة المحمدعلي",
        "notify_news_like_title": "إعجاب جديد",
        "notify_news_like_body": "{name} أعجب بمنشورك",
        "notify_news_like_admin_body": "الإدارة أعجبت بمنشورك",
        "notify_news_comment_title": "تعليق جديد",
        "notify_news_comment_body": "{name} علّق على منشورك",
        "notify_news_comment_admin_body": "الإدارة علّقت على منشورك"
    ]
    static func text(_ key: String, _ fallback: String) -> String {
        guard let value = RemoteSettingsCache.shared.value(key)?.text else { return fallback }
        return notificationDefaults[key] == value ? fallback : value
    }
    static func int(_ key: String, _ fallback: Int, range: ClosedRange<Int>) -> Int {
        guard let n = RemoteSettingsCache.shared.value(key)?.number, n.isFinite,
              n.rounded() == n, n >= Double(range.lowerBound), n <= Double(range.upperBound) else { return fallback }
        return Int(n)
    }
    static func strings(_ key: String, _ fallback: [String]) -> [String] {
        guard let v = RemoteSettingsCache.shared.value(key)?.strings, !v.isEmpty else { return fallback }; return v
    }
    static func template(_ key: String, fallback: String, name: String) -> String {
        text(key, fallback).replacingOccurrences(of: "{name}", with: name)
    }
    static var morning: Int { int("greeting_morning_start_hour", 4, range: 0...11) }
    static var afternoon: Int { int("greeting_afternoon_start_hour", 12, range: 12...16) }
    static var evening: Int { int("greeting_evening_start_hour", 17, range: 17...23) }
}

struct RemoteConfigMeta: Decodable {
    let kind: String
    let label_ar: String
    let help_ar: String?
    let category: String
    let sort: Int
    let min: Double?
    let max: Double?
    let max_length: Int?
    let is_default: Bool
    let updated_at: String?
    let updated_by_name: String?
}
struct RemoteConfigCategory: Decodable, Identifiable {
    let key: String
    let label_ar: String
    let sort: Int
    var id: String { key }
}
struct RemoteConfigPayload: Decodable {
    let values: [String: ConfigValue]
    let scope: String
    let can_edit: Bool?
    let meta: [String: RemoteConfigMeta]?
    let categories: [RemoteConfigCategory]?
}

@MainActor
final class RemoteSettingsModel: ObservableObject {
    static let shared = RemoteSettingsModel()
    @Published private(set) var payload: RemoteConfigPayload?
    @Published private(set) var loading = false
    @Published private(set) var saving = false
    @Published var error: String?
    private var epoch = 0
    private var sessionID: UUID?

    func clearSession() {
        epoch += 1
        sessionID = nil
        payload = nil
        loading = false
        error = nil
        RemoteSettingsCache.shared.clearMemberValues()
    }

    func refresh(publicOnly: Bool = false) async {
        let userID = publicOnly ? nil : SupabaseConfig.client.auth.currentSession?.user.id
        if userID != sessionID {
            epoch += 1; sessionID = userID; payload = nil
            RemoteSettingsCache.shared.clearMemberValues()
        }
        epoch += 1
        let requestEpoch = epoch
        loading = true
        defer { if requestEpoch == epoch { loading = false } }
        do {
            let result: RemoteConfigPayload = try await SupabaseConfig.client
                .rpc(userID == nil ? "app_config_public" : "app_config").execute().value
            guard epoch == requestEpoch, publicOnly || SupabaseConfig.client.auth.currentSession?.user.id == userID else { return }
            RemoteSettingsCache.shared.replace(result.values)
            payload = result
            error = nil
        } catch {
            guard epoch == requestEpoch else { return }
            self.error = L10n.t("تعذّر تحميل إعدادات السيرفر. حاول مرة ثانية.", "Couldn't load server settings. Please retry.")
            Log.fetchError("Remote settings", error)
        }
    }

    func save(key: String, value: ConfigValue) async -> Bool {
        guard payload?.can_edit == true, !saving else { return false }
        saving = true
        defer { saving = false }
        do {
            let args: [String: ConfigValue] = ["p_key": .string(key), "p_value": value]
            _ = try await SupabaseConfig.client.rpc("set_app_config", params: args).execute()
            await refresh()
            return true
        } catch {
            self.error = (error as? PostgrestError)?.message ?? L10n.t("تعذّر حفظ الإعداد.", "Couldn't save this setting.")
            return false
        }
    }
}
