import Foundation
import SwiftUI
import Combine
import Supabase

// MARK: - App Settings Model

struct AppSettings: Codable {
    let id: UUID
    var newsRequiresApproval: Bool
    var allowNewRegistrations: Bool
    var maintenanceMode: Bool
    var maxDevicesPerUser: Int
    var pollsEnabled: Bool?
    var storiesEnabled: Bool?
    var diwaniyasEnabled: Bool?
    var projectsEnabled: Bool?
    var albumsEnabled: Bool?
    var womenTreeEnabled: Bool?
    var latestBuild: Int?
    var updateMessage: String?
    var forceUpdate: Bool?
    var updateUrl: String?
    var updatedAt: String?
    var updatedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case newsRequiresApproval = "news_requires_approval"
        case allowNewRegistrations = "allow_new_registrations"
        case maintenanceMode = "maintenance_mode"
        case maxDevicesPerUser = "max_devices_per_user"
        case pollsEnabled = "polls_enabled"
        case storiesEnabled = "stories_enabled"
        case diwaniyasEnabled = "diwaniyas_enabled"
        case projectsEnabled = "projects_enabled"
        case albumsEnabled = "albums_enabled"
        case womenTreeEnabled = "women_tree_enabled"
        case latestBuild = "latest_build"
        case updateMessage = "update_message"
        case forceUpdate = "force_update"
        case updateUrl = "update_url"
        case updatedAt = "updated_at"
        case updatedBy = "updated_by"
    }
}

/// رقم بناء التطبيق الحالي — يُقارن بـ latest_build لإظهار بانر/شاشة التحديث.
let kAppBuild = 1

// MARK: - أقسام الرئيسية الديناميكية (server-driven)

struct HomeSection: Identifiable, Decodable, Equatable {
    let id: UUID
    var title: String
    var subtitle: String?
    var icon: String
    var color: String
    var type: String        // 'link' | 'content'
    var url: String?
    var contentText: String?
    var imageUrl: String?
    var sortOrder: Int
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, icon, color, type, url
        case contentText = "content_text"
        case imageUrl = "image_url"
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? "" ?? ""
        subtitle = try? c.decodeIfPresent(String.self, forKey: .subtitle)
        icon = (try? c.decodeIfPresent(String.self, forKey: .icon)) ?? "link" ?? "link"
        color = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? "#2B7A9F" ?? "#2B7A9F"
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "link" ?? "link"
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        contentText = try? c.decodeIfPresent(String.self, forKey: .contentText)
        imageUrl = try? c.decodeIfPresent(String.self, forKey: .imageUrl)
        sortOrder = (try? c.decodeIfPresent(Int.self, forKey: .sortOrder)) ?? 0 ?? 0
        isActive = (try? c.decodeIfPresent(Bool.self, forKey: .isActive)) ?? true ?? true
    }
}

/// مفاتيح أيقونات موحّدة بين المنصّتين.
let kHomeSectionIconKeys = ["link","info","star","calendar","location","phone",
                           "whatsapp","gift","book","heart","image","people","megaphone"]

func homeSectionSFSymbol(_ key: String) -> String {
    switch key {
    case "info": return "info.circle.fill"
    case "star": return "star.fill"
    case "calendar": return "calendar"
    case "location": return "mappin.circle.fill"
    case "phone": return "phone.fill"
    case "whatsapp": return "message.fill"
    case "gift": return "gift.fill"
    case "book": return "book.fill"
    case "heart": return "heart.fill"
    case "image": return "photo.fill"
    case "people": return "person.3.fill"
    case "megaphone": return "megaphone.fill"
    default: return "link"
    }
}

/// حظر المستخدمين (Guideline 1.2) — يخفي محتوى المحظور عن الحاظر.
enum BlocksStore {
    private struct Row: Decodable { let blocked_id: UUID }

    static func fetchBlockedIds() async -> Set<UUID> {
        guard let uid = SupabaseConfig.client.auth.currentUser?.id else { return [] }
        do {
            let rows: [Row] = try await SupabaseConfig.client.from("blocked_users")
                .select("blocked_id").eq("blocker_id", value: uid.uuidString)
                .execute().value
            return Set(rows.map(\.blocked_id))
        } catch { return [] }
    }

    static func block(_ id: UUID) async {
        guard let uid = SupabaseConfig.client.auth.currentUser?.id, uid != id else { return }
        let payload: [String: AnyEncodable] = [
            "blocker_id": AnyEncodable(uid.uuidString),
            "blocked_id": AnyEncodable(id.uuidString)
        ]
        try? await SupabaseConfig.client.from("blocked_users").upsert(payload).execute()
    }

    static func unblock(_ id: UUID) async {
        guard let uid = SupabaseConfig.client.auth.currentUser?.id else { return }
        try? await SupabaseConfig.client.from("blocked_users").delete()
            .eq("blocker_id", value: uid.uuidString)
            .eq("blocked_id", value: id.uuidString).execute()
    }

    static func acceptTerms() async {
        guard let uid = SupabaseConfig.client.auth.currentUser?.id else { return }
        let iso = ISO8601DateFormatter()
        let payload: [String: AnyEncodable] = ["terms_accepted_at": AnyEncodable(iso.string(from: Date()))]
        try? await SupabaseConfig.client.from("profiles").update(payload).eq("id", value: uid.uuidString).execute()
    }
}

/// طبقة بيانات أقسام الرئيسية — قراءة/كتابة (الكتابة للإدارة عبر RLS).
enum HomeSectionsStore {
    static func fetchActive() async throws -> [HomeSection] {
        try await SupabaseConfig.client.from("home_sections")
            .select().eq("is_active", value: true)
            .order("sort_order", ascending: true).execute().value
    }
    static func fetchAll() async throws -> [HomeSection] {
        try await SupabaseConfig.client.from("home_sections")
            .select().order("sort_order", ascending: true).execute().value
    }
    static func upsert(_ payload: [String: AnyEncodable], id: UUID?) async throws {
        if let id {
            try await SupabaseConfig.client.from("home_sections").update(payload).eq("id", value: id.uuidString).execute()
        } else {
            try await SupabaseConfig.client.from("home_sections").insert(payload).execute()
        }
    }
    static func delete(id: UUID) async throws {
        try await SupabaseConfig.client.from("home_sections").delete().eq("id", value: id.uuidString).execute()
    }
}

// MARK: - App Settings ViewModel

@MainActor
class AppSettingsViewModel: ObservableObject {
    private let supabase = SupabaseConfig.client
    weak var authVM: AuthViewModel?
    private var canModerate: Bool { authVM?.canModerate ?? false }
    private var canManageSettings: Bool { authVM?.canManageSettings ?? false }

    @Published var settings = AppSettings(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        newsRequiresApproval: true,
        allowNewRegistrations: true,
        maintenanceMode: false,
        maxDevicesPerUser: 3,
        pollsEnabled: true,
        storiesEnabled: true,
        diwaniyasEnabled: true,
        projectsEnabled: true,
        albumsEnabled: true
    )
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isSaving = false

    /// جلب الإعدادات من السيرفر
    func fetchSettings() async {
        do {
            let result: [AppSettings] = try await supabase
                .from("app_settings")
                .select()
                .limit(1)
                .execute()
                .value

            if let fetched = result.first {
                self.settings = fetched
            }
        } catch {
            // إذا الجدول مو موجود، نستخدم القيم الافتراضية
            if isSchemaError(error) {
                Log.warning("جدول app_settings غير موجود — نستخدم القيم الافتراضية")
            } else {
                Log.fetchError("خطأ في جلب إعدادات التطبيق", error)
            }
        }
    }

    /// تحديث إعداد واحد في السيرفر
    func updateSetting<T: Encodable>(_ key: String, value: T, updatedBy: UUID?) async {
        guard canManageSettings else {
            Log.warning("[AUTH] Unauthorized updateSetting attempt — owner only")
            return
        }
        isSaving = true
        do {
            var updateData: [String: AnyEncodable] = [
                key: AnyEncodable(value),
                "updated_at": AnyEncodable(DateHelper.now)
            ]
            if let updatedBy {
                updateData["updated_by"] = AnyEncodable(updatedBy.uuidString)
            }

            try await supabase
                .from("app_settings")
                .update(updateData)
                .eq("id", value: settings.id.uuidString)
                .execute()

            await fetchSettings()
            Log.info("تم تحديث الإعداد: \(key)")
        } catch {
            Log.error("خطأ في تحديث الإعداد \(key): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    /// إعادة تعيين جميع الإعدادات للقيم الافتراضية
    func resetToDefaults(updatedBy: UUID?) async {
        guard canManageSettings else {
            Log.warning("[AUTH] Unauthorized resetToDefaults attempt — owner only")
            return
        }
        isSaving = true
        do {
            let updateData: [String: AnyEncodable] = [
                "news_requires_approval": AnyEncodable(true),
                "allow_new_registrations": AnyEncodable(true),
                "maintenance_mode": AnyEncodable(false),
                "max_devices_per_user": AnyEncodable(3),
                "polls_enabled": AnyEncodable(true),
                "stories_enabled": AnyEncodable(true),
                "diwaniyas_enabled": AnyEncodable(true),
                "projects_enabled": AnyEncodable(true),
                "albums_enabled": AnyEncodable(true),
                "updated_at": AnyEncodable(DateHelper.now),
                "updated_by": AnyEncodable(updatedBy?.uuidString)
            ]

            try await supabase
                .from("app_settings")
                .update(updateData)
                .eq("id", value: settings.id.uuidString)
                .execute()

            await fetchSettings()
            Log.info("تم إعادة تعيين الإعدادات")
        } catch {
            Log.error("خطأ في إعادة التعيين: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func isSchemaError(_ error: Error) -> Bool {
        let desc = error.localizedDescription.lowercased()
        return desc.contains("relation") && desc.contains("does not exist")
            || desc.contains("42p01")
    }
}
