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
        case updatedAt = "updated_at"
        case updatedBy = "updated_by"
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
                Log.error("خطأ في جلب إعدادات التطبيق: \(error.localizedDescription)")
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
