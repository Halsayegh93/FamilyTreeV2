import SwiftUI
import Supabase
import Combine

// MARK: - «فرض التحديث» في الإدارة — القراءة والحفظ (المالك)
//
// `update_policy_admin()` ← كل الإعدادات للمنصتين، و`set_update_policy(p)` حفظ جزئي يفحصه السيرفر (الأدنى ≤ الأخيرة،
// «إجباري من تاريخ» يحتاج موعداً، الرابط https…) ويرجع الإعدادات بعد الحفظ. `app_build_overview(p_days)` ← «النسخ
// عند الأعضاء». قبل تطبيق الترحيل `phase = .unavailable` والصفحة ترجع لشكلها السابق (الحد الأدنى والرابط).

/// إعدادات منصة واحدة
nonisolated struct AdminUpdatePlatform: Equatable, Decodable {
    var latestBuild: Int
    var latestVersion: String
    var minBuild: Int
    var mode: Mode
    var deadline: Date?
    var updateURL: String

    enum Mode: String, CaseIterable, Identifiable {
        case optional, scheduled, forced
        var id: String { rawValue }
        var title: String {
            switch self {
            case .optional: return L10n.t("اختياري", "Optional")
            case .scheduled: return L10n.t("إجباري من تاريخ", "Required from date")
            case .forced: return L10n.t("إجباري فوراً", "Required now")
            }
        }
        var icon: String {
            switch self {
            case .optional: return "sparkles"
            case .scheduled: return "calendar"
            case .forced: return "lock.fill"
            }
        }
    }

    private enum K: String, CodingKey { case latest_build, latest_version, min_build, mode, deadline, update_url }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        latestBuild = (try? c.decodeIfPresent(Int.self, forKey: .latest_build)) ?? 0
        latestVersion = (try? c.decodeIfPresent(String.self, forKey: .latest_version)) ?? ""
        minBuild = (try? c.decodeIfPresent(Int.self, forKey: .min_build)) ?? 0
        mode = Mode(rawValue: (try? c.decodeIfPresent(String.self, forKey: .mode)) ?? "") ?? .optional
        deadline = AppUpdateDates.parse(try? c.decodeIfPresent(String.self, forKey: .deadline))
        updateURL = (try? c.decodeIfPresent(String.self, forKey: .update_url)) ?? ""
    }

    init(latestBuild: Int = 0, latestVersion: String = "", minBuild: Int = 0, mode: Mode = .optional,
         deadline: Date? = nil, updateURL: String = "") {
        self.latestBuild = latestBuild
        self.latestVersion = latestVersion
        self.minBuild = minBuild
        self.mode = mode
        self.deadline = deadline
        self.updateURL = updateURL
    }
}

/// كل الإعدادات كما يرجعها السيرفر
nonisolated struct AdminUpdatePolicy: Equatable, Decodable {
    var ios: AdminUpdatePlatform
    var android: AdminUpdatePlatform
    var snoozeDays: Int
    var whatsNew: String
    var forceTitle: String
    var forceMessage: String
    var reminderTitle: String
    var reminderBody: String
    var legacyForce: Bool

    private enum K: String, CodingKey {
        case ios, android, snooze_days, whats_new, force_title, force_message, reminder_title, reminder_body, legacy_android
    }
    private struct Legacy: Decodable { let force_update: Bool? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        ios = (try? c.decode(AdminUpdatePlatform.self, forKey: .ios)) ?? AdminUpdatePlatform()
        android = (try? c.decode(AdminUpdatePlatform.self, forKey: .android)) ?? AdminUpdatePlatform()
        snoozeDays = (try? c.decodeIfPresent(Int.self, forKey: .snooze_days)) ?? 2
        whatsNew = (try? c.decodeIfPresent(String.self, forKey: .whats_new)) ?? ""
        forceTitle = (try? c.decodeIfPresent(String.self, forKey: .force_title)) ?? ""
        forceMessage = (try? c.decodeIfPresent(String.self, forKey: .force_message)) ?? ""
        reminderTitle = (try? c.decodeIfPresent(String.self, forKey: .reminder_title)) ?? ""
        reminderBody = (try? c.decodeIfPresent(String.self, forKey: .reminder_body)) ?? ""
        legacyForce = (try? c.decodeIfPresent(Legacy.self, forKey: .legacy_android))?.force_update ?? false
    }

    /// أسطر «ما الجديد» كما يراها العضو
    var whatsNewLines: [String] {
        whatsNew.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// ما يُرسل للحفظ — الغائب لا يتغيّر
nonisolated struct AdminUpdatePolicyPatch: Encodable, Sendable {
    struct Platform: Encodable, Sendable {
        var latest_build: Int?
        var latest_version: String?
        var min_build: Int?
        var mode: String?
        /// "" = مسح الموعد
        var deadline: String?
        var update_url: String?
    }
    var ios: Platform?
    var android: Platform?
    var snooze_days: Int?
    var whats_new: String?
    var force_title: String?
    var force_message: String?
    var reminder_title: String?
    var reminder_body: String?

    static func platform(_ p: AdminUpdatePlatform) -> Platform {
        Platform(latest_build: p.latestBuild,
                 latest_version: p.latestVersion.trimmingCharacters(in: .whitespaces),
                 min_build: p.minBuild,
                 mode: p.mode.rawValue,
                 deadline: p.deadline.map(AppUpdateDates.iso) ?? "",
                 update_url: p.updateURL.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

nonisolated private struct AdminUpdatePatchParams: Encodable, Sendable { let p: AdminUpdatePolicyPatch }

@MainActor
final class AdminUpdatePolicyStore: ObservableObject {
    enum Phase: Equatable { case loading, loaded, unavailable, failed(String) }

    static let shared = AdminUpdatePolicyStore()

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var policy: AdminUpdatePolicy?
    @Published private(set) var isSaving = false

    func load() async {
        if policy == nil { phase = .loading }
        do {
            let p: AdminUpdatePolicy = try await SupabaseConfig.client.rpc("update_policy_admin").execute().value
            policy = p
            phase = .loaded
        } catch {
            if ErrorHelper.isCancellation(error) { return }
            if Self.isMissing(error) { phase = .unavailable; return }
            Log.warning("[UPDATE] تعذّر جلب إعدادات فرض التحديث: \(error.localizedDescription)")
            if policy == nil { phase = .failed(Self.message(error)) }
        }
    }

    /// nil = حُفظ، وإلا رسالة الخطأ
    func save(_ patch: AdminUpdatePolicyPatch) async -> String? {
        guard !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let p: AdminUpdatePolicy = try await SupabaseConfig.client
                .rpc("set_update_policy", params: AdminUpdatePatchParams(p: patch)).execute().value
            policy = p
            phase = .loaded
            // حالة هذا الجهاز تتبع فوراً
            Task { await AppUpdateStore.shared.refresh(force: true) }
            return nil
        } catch {
            if ErrorHelper.isCancellation(error) { return nil }
            Log.warning("[UPDATE] تعذّر حفظ فرض التحديث: \(error.localizedDescription)")
            return Self.message(error)
        }
    }

    static func isMissing(_ error: Error) -> Bool {
        let pg = error as? PostgrestError
        return pg?.code == "PGRST202" || ErrorHelper.description(error).localizedCaseInsensitiveContains("could not find the function")
    }

    static func message(_ error: Error) -> String {
        guard let pg = error as? PostgrestError else {
            return L10n.t("تعذّر الاتصال، يرجى التحقق من الإنترنت والمحاولة مرة أخرى.", "Couldn't connect — check the internet and retry.")
        }
        if pg.code == "42501" || pg.hint == "not_allowed" {
            return L10n.t("«فرض التحديث» للمالك فقط.", "Force update is for the owner only.")
        }
        if pg.code == "22023" || pg.code == "23514", !pg.message.isEmpty { return pg.message }
        return L10n.t("تعذّر الحفظ، يرجى المحاولة مرة أخرى.", "Couldn't save — try again.")
    }
}

// MARK: - «النسخ عند الأعضاء»

nonisolated struct AdminBuildOverview: Decodable, Equatable {
    struct Platform: Decodable, Equatable {
        struct Build: Decodable, Equatable { let build: Int; let count: Int }
        let latest_build: Int
        let total: Int
        let on_latest: Int
        let older: Int
        let unknown: Int
        let builds: [Build]
    }
    struct Device: Decodable, Equatable, Identifiable {
        let member_id: UUID
        let name: String
        let platform: String
        let build: Int?
        let version: String?
        let device_name: String?
        let last_seen: String?
        var id: String { "\(member_id.uuidString)|\(platform)|\(build ?? -1)|\(device_name ?? "")|\(last_seen ?? "")" }
        var lastSeen: Date? { AppUpdateDates.parse(last_seen) }
    }
    let ios: Platform
    let android: Platform
    let days: Int
    let devices: [Device]
}
