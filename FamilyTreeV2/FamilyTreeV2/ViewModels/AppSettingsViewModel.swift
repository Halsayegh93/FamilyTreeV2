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
    var diwaniyasEnabled: Bool?
    var projectsEnabled: Bool?
    var albumsEnabled: Bool?
    /// إظهار «شجرة النساء» في قسم الشجرة (العمود موجود ويقرؤه الأندرويد لاختصار الرئيسية) — nil = ظاهرة
    var womenTreeEnabled: Bool?
    /// لغة التطبيق الرسمية (ar / en) — للمستخدمين الذين لم يختاروا لغتهم
    var defaultLanguage: String?
    /// التحديث الإجباري — أقل رقم بناء مسموح لكل منصة (0 = بلا إجبار) + رابط المتجر
    var iosMinBuild: Int?
    /// الطريقة القديمة — تقرأها نسخ الأندرويد المثبّتة قبل الحد لكل منصة
    var forceUpdate: Bool?
    var latestBuild: Int?
    var updateMessage: String?
    var androidMinBuild: Int?
    var iosUpdateUrl: String?
    var androidUpdateUrl: String?
    /// أسماء الفروع المخصّصة (طلب المالك ٢٠٢٦-١٠-٠٩): معرّف رأس الفرع (uuid نصّاً بحروف صغيرة) ← الاسم.
    /// تظهر في قائمة «اختر فرعاً» فقط — لا تغيّر أسماء الأعضاء في أي مكان آخر. nil/فارغ = الأسماء الافتراضية.
    var branchNames: [String: String]?
    /// «مسار الموافقات» (طلب المالك ٢٠٢٦-١٠-١٥): المختص يراجع ← المدير يعتمد ← المختص ينفّذ.
    /// nil (العمود غير موجود بعد) أو false = الطريقة القديمة كما هي
    var approvalsWorkflow: Bool?
    /// «مسار الموافقات ٢» (طلب المالك ٢٠٢٦-١٠-١٦): أنواع «المسار السريع» (تبدأ عند المدير مباشرة)
    /// والمهلة بالساعات (تذكير/تصعيد، والمستعجل) — nil = العمود غير موجود بعد (يختفي الإعداد)
    var approvalsFastTypes: [String]?
    var approvalsSlaHours: Double?
    var approvalsEscalateHours: Double?
    var approvalsUrgentSlaHours: Double?
    var approvalsUrgentEscalateHours: Double?
    /// تنبيه رصيد رسائل الدخول (KWT SMS، ٢٠٢٦-١٠-٢٠): «منخفض» تحت (٠ = مطفأ)، «عاجل» تحت (≤ المنخفض)،
    /// وكل كم ساعة يتكرر كلٌّ منهما (١–١٦٨) — يقرؤها `finish_kwtsms_send`. nil = العمود غير موجود بعد
    var smsLowThreshold: Int?
    var smsUrgentThreshold: Int?
    var smsLowRepeatHours: Int?
    var smsUrgentRepeatHours: Int?
    // حدود رسائل الدخول واسم المرسل (sms_wait_seconds…، ٢٠٢٦-١٠-٢٠) تُقرأ من `sms_admin_overview()` لا من هنا —
    // تحتاجها صفحة KWT SMS وحدها، وتكبير هذا النوع يكبّر كل نسخة منه في المكدس (حارس المكدس)
    var deathAlertDays: Int?
    var updatedAt: String?
    var updatedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case newsRequiresApproval = "news_requires_approval"
        case allowNewRegistrations = "allow_new_registrations"
        case maintenanceMode = "maintenance_mode"
        case maxDevicesPerUser = "max_devices_per_user"
        case pollsEnabled = "polls_enabled"
        case diwaniyasEnabled = "diwaniyas_enabled"
        case projectsEnabled = "projects_enabled"
        case albumsEnabled = "albums_enabled"
        case womenTreeEnabled = "women_tree_enabled"
        case defaultLanguage = "default_language"
        case iosMinBuild = "ios_min_build"
        case forceUpdate = "force_update"
        case latestBuild = "latest_build"
        case updateMessage = "update_message"
        case androidMinBuild = "android_min_build"
        case iosUpdateUrl = "ios_update_url"
        case androidUpdateUrl = "android_update_url"
        case branchNames = "branch_names"
        case approvalsWorkflow = "approvals_workflow"
        case approvalsFastTypes = "approvals_fast_types"
        case approvalsSlaHours = "approvals_sla_hours"
        case approvalsEscalateHours = "approvals_escalate_hours"
        case approvalsUrgentSlaHours = "approvals_urgent_sla_hours"
        case approvalsUrgentEscalateHours = "approvals_urgent_escalate_hours"
        case smsLowThreshold = "sms_low_threshold"
        case smsUrgentThreshold = "sms_urgent_threshold"
        case smsLowRepeatHours = "sms_low_repeat_hours"
        case smsUrgentRepeatHours = "sms_urgent_repeat_hours"
        case deathAlertDays = "death_alert_days"
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
        diwaniyasEnabled: true,
        projectsEnabled: true,
        albumsEnabled: true
    )
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isSaving = false

    /// جلب الإعدادات من السيرفر
    func fetchSettings() async {
        await RemoteSettingsModel.shared.refresh()
        do {
            let result: [AppSettings] = try await supabase
                .from("app_settings")
                .select()
                .limit(1)
                .execute()
                .value

            if let fetched = result.first {
                self.settings = fetched
                let days = fetched.deathAlertDays ?? 7
                UserDefaults.standard.set((1...30).contains(days) ? days : 7, forKey: "server.deathAlertDays")
                LanguageManager.shared.applyOfficialLanguage(fetched.defaultLanguage)
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

    // MARK: - تنبيه رصيد رسائل الدخول (KWT SMS، ٢٠٢٦-١٠-٢٠)

    /// يحفظ العتبتين والفاصلين معاً في تحديث واحد — السيرفر يشترط «عاجل ≤ منخفض» على الصف كله، فكتابة
    /// كل عمود وحده قد تُرفض في المنتصف. للمالك وحده. false = لم يُحفظ (الإعدادات تُعاد من السيرفر).
    func updateSmsAlerts(low: Int, urgent: Int, lowHours: Int, urgentHours: Int, updatedBy: UUID?) async -> Bool {
        guard canManageSettings else {
            Log.warning("[AUTH] Unauthorized updateSmsAlerts attempt — owner only")
            return false
        }
        guard low >= 0, urgent >= 0, urgent <= low, (1...168).contains(lowHours), (1...168).contains(urgentHours) else {
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            var updateData: [String: AnyEncodable] = [
                "sms_low_threshold": AnyEncodable(low),
                "sms_urgent_threshold": AnyEncodable(urgent),
                "sms_low_repeat_hours": AnyEncodable(lowHours),
                "sms_urgent_repeat_hours": AnyEncodable(urgentHours),
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
            Log.info("تم حفظ تنبيه رصيد الرسائل")
            return true
        } catch {
            Log.error("خطأ في حفظ تنبيه رصيد الرسائل: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            await fetchSettings()
            return false
        }
    }

    // MARK: - حدود رسائل الدخول (KWT SMS، ٢٠٢٦-١٠-٢٠)

    /// المدى الذي يقبله السيرفر لكل حد (قيد `check` على الأعمدة — خارجه خطأ 23514). الانتظار ٣٠–٦٠٠ ث منذ ٢٠٢٦-١٠-٢٠
    /// (كان ٦٠–٦٠٠؛ حدّ خدمة الدخول نفسها ٥ ث فقط لكل رقم)
    static let smsWaitRange = 30...600
    static let smsPerNumberHourRange = 1...20
    static let smsAllHourRange = 20...1000
    static let loginAttemptsRetentionRange = 7...90

    /// يحفظ الحدود الأربعة معاً في تحديث واحد (بلا `sms_sender` — لا يُكتب من التطبيق). للمالك وحده.
    /// المدير يمر تحديثه بلا خطأ لكن بصفر صفوف (RLS) — لذلك يُطلب الصف المحدّث ويُعدّ: لا صف = لم يُحفظ.
    /// قيمة خارج المدى يرفضها السيرفر (23514). false = لم يُحفظ. القراءة بعدها من `sms_admin_overview()`.
    func updateSmsLimits(waitSeconds: Int, perNumberHour: Int, allHour: Int, retentionDays: Int,
                         updatedBy: UUID?) async -> Bool {
        guard canManageSettings else {
            Log.warning("[AUTH] Unauthorized updateSmsLimits attempt — owner only")
            return false
        }
        guard Self.smsWaitRange.contains(waitSeconds), Self.smsPerNumberHourRange.contains(perNumberHour),
              Self.smsAllHourRange.contains(allHour), Self.loginAttemptsRetentionRange.contains(retentionDays) else {
            return false
        }
        nonisolated struct Row: Decodable { let id: UUID }
        isSaving = true
        defer { isSaving = false }
        do {
            var updateData: [String: AnyEncodable] = [
                "sms_wait_seconds": AnyEncodable(waitSeconds),
                "sms_per_number_hour": AnyEncodable(perNumberHour),
                "sms_all_hour": AnyEncodable(allHour),
                "login_attempts_retention_days": AnyEncodable(retentionDays),
                "updated_at": AnyEncodable(DateHelper.now)
            ]
            if let updatedBy {
                updateData["updated_by"] = AnyEncodable(updatedBy.uuidString)
            }
            let rows: [Row] = try await supabase
                .from("app_settings")
                .update(updateData)
                .eq("id", value: settings.id.uuidString)
                .select("id")
                .execute()
                .value
            guard !rows.isEmpty else {
                Log.warning("حدود رسائل الدخول: لم يُحدَّث أي صف (صلاحية)")
                return false
            }
            Log.info("تم حفظ حدود رسائل الدخول")
            return true
        } catch {
            Log.error("خطأ في حفظ حدود رسائل الدخول: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - أسماء الفروع (طلب المالك ٢٠٢٦-١٠-٠٩)

    /// الاسم المخصّص لفرع — المفتاح يُطابق بلا اعتبار لحالة الحروف؛ الفارغ/المسافات = لا اسم مخصّص
    func branchName(for id: UUID) -> String? {
        guard let names = settings.branchNames, !names.isEmpty else { return nil }
        let key = id.uuidString.lowercased()
        let raw = names[key] ?? names.first { $0.key.lowercased() == key }?.value
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// حفظ اسم فرع مخصّص — nil أو فارغ = حذف المفتاح (يرجع الاسم الافتراضي). للمالك وحده.
    /// تحديث متفائل: الاسم يظهر فوراً ويُعاد السابق إن فشل الحفظ.
    func updateBranchName(_ name: String?, for branchId: UUID, updatedBy: UUID?) async {
        guard canManageSettings else {
            Log.warning("[AUTH] Unauthorized updateBranchName attempt — owner only")
            return
        }
        let key = branchId.uuidString.lowercased()
        let previous = settings.branchNames
        // مفتاح واحد لكل فرع (يُزال أي مفتاح قديم بحروف كبيرة)
        var names = (previous ?? [:]).filter { $0.key.lowercased() != key }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { names[key] = trimmed }

        settings.branchNames = names
        isSaving = true
        do {
            var updateData: [String: AnyEncodable] = [
                "branch_names": AnyEncodable(names),
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
            Log.info("تم تحديث اسم الفرع")
        } catch {
            settings.branchNames = previous
            Log.error("خطأ في حفظ اسم الفرع: \(error.localizedDescription)")
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
                "diwaniyas_enabled": AnyEncodable(true),
                "projects_enabled": AnyEncodable(true),
                "albums_enabled": AnyEncodable(true),
                "women_tree_enabled": AnyEncodable(true),
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
