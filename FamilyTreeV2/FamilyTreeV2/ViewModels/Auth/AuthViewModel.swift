import Foundation
import Supabase
import SwiftUI
import Combine

private struct PhoneLookupProfile: Decodable {
    let id: UUID
    let phoneNumber: String?
    let role: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case phoneNumber = "phone_number"
        case role
        case status
    }
}

class LanguageManager: ObservableObject {
    @AppStorage("selectedLanguage") var selectedLanguage: String = "ar" {
        didSet {
            objectWillChange.send()
        }
    }

    /// هل اختار المستخدم لغته بنفسه؟ — إن لا، يتبع لغة التطبيق الرسمية
    /// التي يحددها المالك من «إعدادات التطبيق» (طلب المالك)
    @AppStorage("languageChosenByUser") var languageChosenByUser: Bool = false

    static let shared = LanguageManager()

    init() {
        // من اختار لغته قبل إضافة «اللغة الرسمية»: القيمة محفوظة في الجهاز
        // (AppStorage لا يكتبها إلا عند اختيار المستخدم) — نعتبرها اختياره
        // حتى لا ترجع لغته للعربي بالغلط عند أول تشغيل
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "languageChosenByUser") == nil,
           defaults.object(forKey: "selectedLanguage") != nil {
            defaults.set(true, forKey: "languageChosenByUser")
        }
    }

    /// تطبيق اللغة الرسمية على من لم يختر لغته بنفسه
    func applyOfficialLanguage(_ language: String?) {
        guard !languageChosenByUser,
              let language, ["ar", "en"].contains(language),
              language != selectedLanguage else { return }
        selectedLanguage = language
    }

    /// اختيار المستخدم من «الإعدادات» — يثبّت لغته ولا تغيّرها اللغة الرسمية بعدها
    func chooseLanguage(_ language: String) {
        languageChosenByUser = true
        selectedLanguage = language
    }

    /// الرجوع للغة التطبيق الرسمية
    func followOfficialLanguage(_ official: String?) {
        languageChosenByUser = false
        applyOfficialLanguage(official)
    }

    static var isArabic: Bool {
        shared.selectedLanguage == "ar"
    }

    var locale: Locale {
        Locale(identifier: selectedLanguage)
    }

    var layoutDirection: LayoutDirection {
        selectedLanguage == "ar" ? .rightToLeft : .leftToRight
    }
}

@MainActor
class AuthViewModel: ObservableObject {

    // استخدام النسخة المركزية من Supabase
    let supabase = SupabaseConfig.client
    
    @Published var phoneNumber: String = ""
    @Published var dialingCode: String = "+965"
    
    /// حفظ آخر رقم هاتف مستخدم للتسجيل — محفوظ بأمان في Keychain
    private var lastAuthPhone: String {
        get { KeychainHelper.load(forKey: "lastAuthPhone") ?? "" }
        set {
            if newValue.isEmpty { KeychainHelper.delete(forKey: "lastAuthPhone") }
            else { KeychainHelper.save(newValue, forKey: "lastAuthPhone") }
        }
    }
    private var lastAuthDialingCode: String {
        get { KeychainHelper.load(forKey: "lastAuthDialingCode") ?? "" }
        set {
            if newValue.isEmpty { KeychainHelper.delete(forKey: "lastAuthDialingCode") }
            else { KeychainHelper.save(newValue, forKey: "lastAuthDialingCode") }
        }
    }
    @Published var otpCode: String = ""
    @Published var isOtpSent: Bool = false
    @Published var isLoading: Bool = false
    @Published var isAuthenticated: Bool = false
    private var isEndingSession = false
    private var sessionGeneration = UUID()
    @Published var currentUser: FamilyMember? = nil
    @Published var status: AuthStatus = .checking {
        didSet {
            guard status != oldValue else { return }
            if status == .checking {
                armLaunchWatchdog()
            } else {
                launchWatchdog?.cancel()
                launchCheckStalled = false
            }
        }
    }
    /// شاشة البداية علقت (بلا اتصال، أو الخادم لا يرد) — تعرض «تعذّر الاتصال» و«إعادة المحاولة»
    /// بدل الدوران بلا نهاية (فحص الثغرات ج-٦). تُصفَّر حين تخرج الحالة من `.checking`.
    @Published var launchCheckStalled: Bool = false
    private var launchWatchdog: Task<Void, Never>?
    /// إعادة فحص البروفايل المجدولة (واحدة فقط في كل لحظة)
    private var profileRecheckTask: Task<Void, Never>?
    @Published var notificationsFeatureAvailable: Bool = true
    @Published var newsApprovalFeatureAvailable: Bool = true
    @Published var contactMessageError: String?
    @Published var otpErrorMessage: String?
    /// ثوانٍ قبل السماح بطلب رمز جديد كما ذكرها خطأ الحجب (٢٠٢٦-١٠-٢٠، الانتظار يضبطه المالك) — nil = لم يُذكر
    @Published var otpRetryAfter: Int?
    @Published var otpStatusMessage: String = ""
    @Published var deleteAccountError: String?
    /// خطأ تسجيل يُعرض للمستخدم في شاشة التسجيل — يُمسح في بداية كل محاولة تسجيل.
    @Published var registrationError: String?
    @Published var bannedPhones: [BannedPhone] = []

    enum AuthStatus {
        case unauthenticated
        case checking
        case authenticatedNoProfile
        case fullyAuthenticated
        case pendingApproval
        case accountFrozen
        case deviceLimitExceeded
        case deviceRevoked
        case deviceOverLimit   // مسجّل لكن عدد أجهزته تجاوز الحد الجديد
    }
    
    static let maxDevicesPerAccount = 3

    weak var notificationVM: NotificationViewModel?
    weak var appSettingsVM: AppSettingsViewModel?
    
    // MARK: - صلاحيات الأدوار

    /// المالك — يُقرأ من Info.plist (`OWNER_UUID`) مع fallback للقيمة الافتراضية.
    /// لنقله إلى build config: أضف `INFOPLIST_KEY_OWNER_UUID = <uuid>` في pbxproj أو xcconfig.
    static let ownerUUID: UUID? = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "OWNER_UUID") as? String,
           let uuid = UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return uuid
        }
        // Default fallback (dev/legacy)
        return UUID(uuidString: "9849ab4f-fc16-495e-b82d-33811d4b8d3c")
    }()

    /// هل المستخدم الحالي مالك التطبيق
    var isOwner: Bool {
        currentUser?.role == .owner
    }

    /// هل المستخدم مدير أو مالك
    var isAdmin: Bool {
        currentUser?.role == .owner || currentUser?.role == .admin
    }

    /// هل يقدر يدخل لوحة الإدارة (مالك أو مدير أو مراقب أو مشرف)
    var canModerate: Bool {
        currentUser?.role == .owner || currentUser?.role == .admin || currentUser?.role == .monitor || currentUser?.role == .supervisor
    }

    /// هل يقدر يرفض الطلبات (مالك أو مدير أو مراقب) — المشرف يقدر يوافق بس ما يرفض
    // MARK: - الصلاحيات حسب مجال الدور (تحديث 2026-09-21)
    //
    // كل دور له مجال واضح بدل درجات متداخلة:
    // • المراقب  → الشجرة والأعضاء
    // • المشرف   → المحتوى والبلاغات (المراجعة والإخفاء والحذف — لا الاعتماد)
    // • الاعتماد النهائي للمحتوى (أخبار/مكتبة/مشاريع/ديوانيات) للإدارة فقط

    /// مجال الشجرة والأعضاء — الإدارة + المراقب
    var canModerateTree: Bool { isAdmin || currentUser?.role == .monitor }

    /// مجال المحتوى والبلاغات — الإدارة + المشرف
    var canModerateContent: Bool { isAdmin || currentUser?.role == .supervisor }

    /// اعتماد المحتوى (أخبار، مكتبة، مشاريع، ديوانيات) — الإدارة فقط
    var canApproveContent: Bool { isAdmin }

    /// قبول طلبات الشجرة والأعضاء (انضمام، وفاة، إضافة ابن، رقم/اسم، تعديلات الشجرة)
    var canApproveTreeRequests: Bool { canModerateTree }

    /// رفض الطلبات — نفس من يقبلها في مجاله
    var canRejectRequests: Bool { canModerateTree }

    var canManageRoles: Bool { isOwner }

    /// حذف أعضاء نهائياً — مدير + مالك
    var canDeleteMembers: Bool { isAdmin }

    /// إعدادات التطبيق — المالك فقط
    var canManageSettings: Bool { isOwner }

    /// رؤية شاشة "إعدادات النظام" (قراءة فقط للمدير، تعديل للمالك)
    var canViewSystemSettings: Bool { isAdmin }

    /// أرقام محظورة — المالك فقط
    var canManageBannedPhones: Bool { isOwner }

    /// إدارة الأجهزة — المالك فقط
    var canManageDevices: Bool { isOwner }

    /// تعديل بيانات أعضاء آخرين — مجال الشجرة
    var canEditMembers: Bool { canModerateTree }

    /// حذف أخبار — مجال المحتوى
    var canDeleteNews: Bool { canModerateContent }

    /// إرسال إشعارات يدوية — مدير + مالك
    var canSendNotifications: Bool { isAdmin }

    /// تسجيل عضو جديد مباشرة — مدير + مالك
    var canRegisterMembers: Bool { isAdmin }

    /// نشر أخبار فريق الإدارة بلا مراجعة
    var canAutoPublishNews: Bool { canModerate }

    /// حذف تعليقات — مجال المحتوى
    var canDeleteComments: Bool { canModerateContent }

    /// تجميد حسابات الأعضاء — مدير + مالك
    var canFreezeMembers: Bool { isAdmin }

    /// حذف ديوانيات — مدير + مالك
    var canDeleteDiwaniyas: Bool { isAdmin }

    /// حذف صور الأعضاء — مجال المحتوى
    var canDeletePhotos: Bool { canModerateContent }

    // MARK: - Schema Error Helpers (delegated to ErrorHelper)

    private func parseServerDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }

        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
        if let date = withoutFraction.date(from: raw) { return date }

        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone(secondsFromGMT: 0)
        fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fallback.date(from: raw)
    }

    private func resolveAuthAccess(for profile: FamilyMember) -> AuthStatus {
        // البروفايل بدون اسم = الترقر أنشأ السجل تلقائياً ولم يكمل المستخدم التسجيل بعد
        let name = profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            Log.info("[AUTH] البروفايل بدون اسم (أنشأه الترقر تلقائياً) → شاشة إنشاء الملف التعريفي")
            return .authenticatedNoProfile
        }

        // المجمد — يظهر له شاشة تجميد الحساب (نفحص قبل role لأن الأولوية للتجميد)
        if profile.status == .frozen || profile.status == .deleted {
            Log.info("[AUTH] العضو \(profile.fullName) حالته frozen → شاشة الحساب المجمد")
            return .accountFrozen
        }

        // شاشة الانتظار = المستخدم أكمل نموذج التسجيل فعلاً (role=pending).
        // ملاحظة مهمة: لا نعتمد على status=pending وحده لأن الـ default في قاعدة البيانات
        // لأي عضو جديد هو 'pending' — بمعنى أعضاء الشجرة المضافون بواسطة الإدارة
        // (role='member', status='pending') سيتم إعادة توجيههم لفورم التسجيل بشكل صحيح.
        guard profile.role != .pending else {
            Log.info("[AUTH] العضو \(profile.fullName) role=pending → شاشة انتظار الموافقة")
            return .pendingApproval
        }

        // عضو الشجرة بـ role='member' وstatus='pending' = مضاف بالإدارة ولم يُسجّل بعد
        // نوجّهه لفورم التسجيل حتى يرسل طلب الانضمام بشكل صحيح
        if profile.status == .pending {
            Log.info("[AUTH] العضو \(profile.fullName) role=member+status=pending → شاشة التسجيل (عضو شجرة غير مسجّل)")
            return .authenticatedNoProfile
        }

        // العضو بدون رقم — المدير حذف رقمه → يسجّل من جديد
        let phone = profile.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if phone.isEmpty {
            Log.info("[AUTH] العضو \(profile.fullName) بدون رقم هاتف (المدير حذفه) → شاشة التسجيل")
            return .authenticatedNoProfile
        }

        return .fullyAuthenticated
    }
    
    // MARK: - Init

    /// Task الحالي لـ checkUserProfile — نحتفظ به لنلغي الـ calls المتزامنة المكررة
    private var activeProfileCheckTask: Task<Void, Never>?

    init() {
        activeProfileCheckTask = Task { [weak self] in
            await self?.checkUserProfile()
        }
        armLaunchWatchdog()
    }

    /// مهلة شاشة البداية (ج-٦): إن بقيت الحالة «جاري التحقق» ١٢ ثانية (طلب معلّق بلا رد، أو
    /// بلا اتصال) تظهر رسالة «تعذّر الاتصال» مع «إعادة المحاولة» — والتحقق يستمر بالخلفية.
    private func armLaunchWatchdog() {
        launchWatchdog?.cancel()
        launchWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled, let self, self.status == .checking else { return }
            self.launchCheckStalled = true
        }
    }

    /// «إعادة المحاولة» من شاشة البداية العالقة
    /// يلغي الفحص الجاري (قد يكون عالقاً على طلب بلا رد) ويبدأ واحداً جديداً — كانت الضغطة تضيف فحصاً
    /// موازياً فوق العالق بدل أن تحلّ محلّه
    func retryLaunchCheck() async {
        launchCheckStalled = false
        armLaunchWatchdog()
        profileRecheckTask?.cancel()
        activeProfileCheckTask?.cancel()
        let task = Task { [weak self] in await self?.checkUserProfile() }
        activeProfileCheckTask = task
        await task.value
    }

    /// بلا اتصال ولا نسخة محفوظة للعضو: «تعذّر الاتصال» على شاشة البداية ومحاولة تلقائية كل
    /// لحظات حتى يعود الاتصال (ج-٦) — كانت الحالة تبقى «جاري التحقق» فتدور الشاشة بلا نهاية.
    private func showLaunchConnectionProblem(generation: UUID) {
        guard status == .checking else { return }
        launchCheckStalled = true
        scheduleProfileRecheck(generation: generation)
    }

    deinit {
        activeProfileCheckTask?.cancel()
    }
    
    // MARK: - نظام المصادقة (Auth)
    
    private func normalizeDialingCode(_ raw: String) -> String {
        let digits = KuwaitPhone.normalizeDigits(raw).filter(\.isNumber)
        let prefix = String(digits.prefix(4))
        return prefix.isEmpty ? "+965" : "+\(prefix)"
    }
    
    private func normalizePhoneDigits(_ raw: String) -> String {
        String(KuwaitPhone.normalizeDigits(raw).filter(\.isNumber).prefix(15))
    }
    
    private func toE164(dialingCode: String, localDigits: String) -> String? {
        let code = normalizeDialingCode(dialingCode)
        let local = normalizePhoneDigits(localDigits)
        guard local.count >= 6 else { return nil }
        return "\(code)\(local)"
    }
    
    private func digitsOnly(_ raw: String) -> String {
        KuwaitPhone.normalizeDigits(raw).filter(\.isNumber)
    }

    private func authenticatedUserId() async -> UUID? {
        if let sessionUser = try? await supabase.auth.session.user {
            return sessionUser.id
        }
        return currentUser?.id
    }
    
    private func phonesMatch(stored: String?, targetRaw: String) -> Bool {
        let target = digitsOnly(targetRaw)
        let storedDigits = digitsOnly(stored ?? "")
        guard !storedDigits.isEmpty, !target.isEmpty else { return false }
        
        if storedDigits == target { return true }
        if storedDigits.count == 8, target.hasSuffix(storedDigits) { return true }
        if target.count == 8, storedDigits.hasSuffix(target) { return true }
        return false
    }
    
    private func userFacingOTPError(_ error: Error) -> String {
        let text = "\(error) \(error.localizedDescription)".lowercased()
        
        if let wait = OTPWaitText.message(from: text, arabic: L10n.isArabic) { return wait }
        if text.contains("429") || text.contains("rate") {
            return L10n.t("تم تجاوز عدد المحاولات. انتظر دقيقة ثم أعد المحاولة.", "Too many attempts. Please wait a minute and try again.")
        }
        if text.contains("network") || text.contains("timed out") {
            return L10n.t("تعذر الاتصال بالخادم. تأكد من الإنترنت ثم أعد المحاولة.", "Unable to connect to the server. Check your internet and try again.")
        }
        if text.contains("sms") || text.contains("provider") {
            return L10n.t("تعذر إرسال رمز التحقق عبر الرسائل حاليًا. حاول مجددًا بعد دقيقة.", "Unable to send verification code via SMS right now. Try again in a minute.")
        }
        
        return L10n.t("تعذر إرسال رمز التحقق حاليًا. حاول مرة أخرى.", "Unable to send verification code right now. Please try again.")
    }
    
    // MARK: - Private Push / Notification Helpers
    
    private func sendExternalAdminPush(
        title: String,
        body: String,
        kind: String = NotificationKind.adminRequest.rawValue,
        requestId: UUID? = nil,
        requestType: String? = nil
    ) async {
        do {
            var payload: [String: AnyEncodable] = [
                "title": AnyEncodable(title),
                "body": AnyEncodable(body),
                "kind": AnyEncodable(kind)
            ]
            if let rid = requestId   { payload["request_id"]   = AnyEncodable(rid.uuidString) }
            if let rt  = requestType { payload["request_type"] = AnyEncodable(rt) }
            try await supabase.functions
                .invoke("push-admins", options: FunctionInvokeOptions(body: payload))
        } catch {
            Log.warning("تعذر إرسال Push خارجي للمدير: \(error.localizedDescription)")
        }
    }
    
    /// إرسال إشعار واحد في مركز الإشعارات (broadcast) يراه المدراء والمشرفون
    private func notifyAdmins(title: String, body: String, kind: String, requestId: UUID? = nil, requestType: String? = nil) async {
        let creatorId = currentUser?.id
        guard notificationsFeatureAvailable else { return }

        do {
            var payload: [String: AnyEncodable] = [
                "target_member_id": AnyEncodable(Optional<String>.none),
                "title": AnyEncodable(title),
                "body": AnyEncodable(body),
                "kind": AnyEncodable(kind),
                "created_by": AnyEncodable(creatorId?.uuidString)
            ]
            if let rid = requestId   { payload["request_id"]   = AnyEncodable(rid.uuidString) }
            if let rt  = requestType { payload["request_type"] = AnyEncodable(rt) }
            try await supabase.from("notifications").insert(payload).execute()
        } catch {
            if ErrorHelper.isMissingTable(error, table: "notifications") {
                notificationsFeatureAvailable = false
            } else if !ErrorHelper.isMissingColumn(error, column: "request_id") {
                Log.warning("تعذر إرسال إشعار للمدراء: \(error.localizedDescription)")
            } else {
                let fallback: [String: AnyEncodable] = [
                    "target_member_id": AnyEncodable(Optional<String>.none),
                    "title": AnyEncodable(title),
                    "body": AnyEncodable(body),
                    "kind": AnyEncodable(kind),
                    "created_by": AnyEncodable(creatorId?.uuidString)
                ]
                _ = try? await supabase.from("notifications").insert(fallback).execute()
            }
        }
    }

    /// إشعار موحّد: يرسل push خارجي + إشعار داخلي في استدعاء واحد
    private func notifyAdminsWithPush(title: String, body: String, kind: String, requestId: UUID? = nil, requestType: String? = nil) async {
        async let push: Void = sendExternalAdminPush(title: title, body: body, kind: kind, requestId: requestId, requestType: requestType)
        async let inApp: Void = notifyAdmins(title: title, body: body, kind: kind, requestId: requestId, requestType: requestType)
        _ = await (push, inApp)
    }

    /// إرسال إشعار إيميل عبر event-notify edge function — للأحداث الإدارية وتغيير الحالة
    /// لا يرمي خطأ — مجرد warning في اللوق إذا فشل (لا نُفشل العملية الأصلية بسبب إيميل)
    func sendEventEmail(payload: [String: AnyEncodable]) async {
        do {
            try await supabase.functions.invoke(
                "event-notify",
                options: FunctionInvokeOptions(body: payload)
            )
            Log.info("[EventEmail] ✅ event-notify اكتمل")
        } catch {
            Log.warning("[EventEmail] ⚠️ فشل event-notify: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Profile Lookup Helpers
    
    private func loadProfile(by id: UUID) async -> FamilyMember? {
        do {
            let response: [FamilyMember] = try await supabase
                .from("members_masked") // الهاتف المخفي يُفرَّغ من السيرفر
                .select()
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value

            return response.first
        } catch {
            Log.warning("فشل جلب البروفايل عبر المعرّف \(id): \(error)")
            return nil
        }
    }
    
    /// رقم ملف العضو نفسه من السيرفر (`get_member_phone`: يرجع رقمك ولو مخفياً، بهوية `current_profile_id()`)
    private func ownPhoneFromServer(_ id: UUID) async -> String? {
        let phone: String? = try? await supabase
            .rpc("get_member_phone", params: ["p_id": id.uuidString])
            .execute()
            .value
        let trimmed = phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// معرّف ملف هذا الحساب كما يراه السيرفر: `current_profile_id()` = app_metadata.profile_id
    /// وإلا auth.uid() — مصدر الهوية الوحيد بعد إزالة الربط القديم على الجهاز (فحص الثغرات ب-٦).
    private func serverProfileId() async -> UUID? {
        do {
            let id: UUID? = try await supabase.rpc("current_profile_id").execute().value
            return id
        } catch {
            Log.warning("[AUTH] تعذّر قراءة current_profile_id: \(error.localizedDescription)")
            return nil
        }
    }

    /// ملفات الشجرة التي تحمل رقم هذا الحساب (السيرفر يطابق آخر ٨ أرقام، ولغير المفعّل برقم حسابه
    /// فقط) — للقراءة فقط: تُضاف لمطابقات طلب الربط لتربطها الإدارة، ولا يُنقل منها شيء على الجهاز.
    private func phoneMatchedProfileIds(_ rawPhone: String, excluding ownId: UUID) async -> [UUID] {
        let digits = digitsOnly(rawPhone)
        guard digits.count >= 8 else { return [] }
        do {
            let rows: [PhoneLookupProfile] = try await supabase
                .rpc("find_profiles_by_phone", params: ["p_phone": digits])
                .execute()
                .value
            return rows.map(\.id).filter { $0 != ownId }
        } catch {
            Log.warning("[AUTH] تعذّر البحث بالرقم لمطابقات الطلب: \(error.localizedDescription)")
            return []
        }
    }

    /// ملف حقيقي (عضو شجرة، لا تسجيل معلّق) أرسل صاحبه طلب الانضمام/الربط وينتظر الإدارة —
    /// يرى شاشة الانتظار بدل فورم التسجيل من جديد (التسجيل لم يعد يكتب فوق ملفه — ب-٤).
    private func hasPendingJoinRequest(for profile: FamilyMember) async -> Bool {
        let name = profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, profile.role != .pending else { return false }
        var requesters = [profile.id.uuidString]
        if let authId = supabase.auth.currentUser?.id, authId != profile.id {
            requesters.append(authId.uuidString)
        }
        struct RequestRow: Decodable { let id: UUID }
        let rows: [RequestRow] = (try? await supabase
            .from("admin_requests")
            .select("id")
            .in("requester_id", values: requesters)
            .in("request_type", values: [RequestType.linkRequest.rawValue, RequestType.joinRequest.rawValue])
            .eq("status", value: ApprovalStatus.pending.rawValue)
            .limit(1)
            .execute()
            .value) ?? []
        return !rows.isEmpty
    }

    /// ملف بلا رقم (الإدارة حذفته): فورم التسجيل — أو شاشة الانتظار إن أرسل طلبه للإدارة (ب-٤)
    private func routeProfileWithoutPhone(_ profile: FamilyMember, normalizedPhone: String, generation: UUID) async {
        let waiting = await hasPendingJoinRequest(for: profile)
        guard generation == sessionGeneration, !isEndingSession, !Task.isCancelled else { return }
        if waiting {
            await applyAuthenticatedProfile(profile, normalizedPhone: normalizedPhone)
        } else {
            self.status = .authenticatedNoProfile
        }
    }

    /// نتيجة طلب الربط: `created` = أُنشئ الآن (تُبلَّغ الإدارة)، `existing` = معلّق أصلاً
    private enum LinkRequestOutcome { case created, existing }

    /// طلب ربط واحد معلّق فقط لكل حساب (ب-٤: كان كل إرسال للنموذج — ومنه «تعديل البيانات» —
    /// يضيف صفاً جديداً). الطلب عن الملف نفسه: `member_id = requester_id` كما يشترط حارس السيرفر.
    /// - Returns: `nil` = فشل (لا طلب).
    private func ensurePendingLinkRequest(profileId: UUID, details: String) async -> LinkRequestOutcome? {
        struct RequestRow: Decodable { let id: UUID }
        do {
            let existing: [RequestRow] = try await supabase
                .from("admin_requests")
                .select("id")
                .eq("requester_id", value: profileId.uuidString)
                .in("request_type", values: [RequestType.linkRequest.rawValue, RequestType.joinRequest.rawValue])
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .limit(1)
                .execute()
                .value
            if !existing.isEmpty {
                Log.info("[REGISTER] طلب ربط معلّق موجود — لا يُكرَّر")
                return .existing
            }
            let joinRequestData: [String: AnyEncodable] = [
                "member_id": AnyEncodable(profileId.uuidString),
                "requester_id": AnyEncodable(profileId.uuidString),
                "request_type": AnyEncodable(RequestType.linkRequest.rawValue),
                "status": AnyEncodable(ApprovalStatus.pending.rawValue),
                "details": AnyEncodable(details)
            ]
            try await supabase
                .from("admin_requests")
                .insert(joinRequestData)
                .execute()
            Log.info("[REGISTER] ✅ تم إنشاء طلب الانضمام في admin_requests")
            return .created
        } catch {
            Log.error("[REGISTER] ❌ فشل إنشاء طلب الانضمام: \(error.localizedDescription) — memberId=\(profileId.uuidString.prefix(8))")
            return nil
        }
    }
    
    private func applyAuthenticatedProfile(_ profile: FamilyMember, normalizedPhone: String?) async {
        guard !isEndingSession, !Task.isCancelled, let authUser = supabase.auth.currentUser else { return }
        let generation = sessionGeneration
        var profile = profile
        // حساب مربوط بملف شجرة بمعرّف آخر (app_metadata.profile_id) ورقمه مخفي: `members_masked` يقارن بـ auth.uid
        // فيصل رقمه فارغاً، فكان يُرسَل لشاشة التسجيل كأن الإدارة حذفت رقمه. الرقم من السيرفر بهويته الصحيحة.
        if profile.id != authUser.id, profile.role != .owner,
           (profile.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let phone = await ownPhoneFromServer(profile.id) {
            guard generation == sessionGeneration, !isEndingSession, !Task.isCancelled else { return }
            profile.phoneNumber = phone
        }
        CacheManager.shared.beginAccount(authUser.id)
        var access = self.resolveAuthAccess(for: profile)

        // إذا العضو ما عنده رقم أو حالته معلقة → تسجيل خروج تلقائي
        if access == .unauthenticated {
            Log.info("[AUTH] العضو \(profile.fullName) غير مصرح له بالدخول → تسجيل خروج")
            await signOut()
            return
        }

        // عضو شجرة أرسل طلبه وينتظر الإدارة → شاشة الانتظار لا فورم التسجيل مرة أخرى (ب-٤)
        if access == .authenticatedNoProfile, await hasPendingJoinRequest(for: profile) {
            guard generation == sessionGeneration, !isEndingSession, !Task.isCancelled,
                  authUser.id == supabase.auth.currentUser?.id else { return }
            access = .pendingApproval
        }

        self.currentUser = profile
        self.status = access

        // ينشر الجلسة لامتداد المشاركة فور معرفة العضو (لا ينتظر تجديد الجلسة)
        if let session = try? await supabase.auth.session {
            publishSessionToShareExtension(session)
        }

        // جلب إعدادات التطبيق من السيرفر
        await appSettingsVM?.fetchSettings()
        // تصنيفات الأخبار والمكتبة كما ضبطتها الإدارة — كانت لا تُحمَّل إلا بفتح شاشة «التصنيفات»،
        // فتظهر الأسماء الافتراضية القديمة لبقية المستخدمين (بلاغ المالك ٢٠٢٦-١٠-٠٧). بلا انتظار.
        Task { await CategoryStore.shared.fetch() }
        guard generation == sessionGeneration, !isEndingSession,
              authUser.id == supabase.auth.currentUser?.id, !Task.isCancelled else { return }
        if let normalizedPhone, normalizedPhone.count == 8 {
            self.phoneNumber = normalizedPhone
        }

        // تسجيل الجهاز يتم في AppState عند تغيير status لـ fullyAuthenticated
        // pendingApproval يحتاج تسجيل هنا عشان يوصله إشعار الموافقة
        if access == .pendingApproval {
            await notificationVM?.registerDevice()
        }

        // تحديث last_active_at — يضمن ظهور العضو "نشط" في لوحة الإدارة
        _ = try? await supabase.rpc("touch_last_active").execute()
    }
    
    /// بحث عن مطابقات الاسم في الشجرة — يُرجع قائمة بمعرفات الأعضاء المتطابقين
    /// يستخدم دالة security definer لتجاوز RLS (مستخدمو pending لا يرون الأعضاء)
    private func searchForNameMatches(fullName: String, firstName: String) async -> [String] {
        struct NameMatchRow: Decodable {
            let memberId: UUID
            let fullName: String
            let matchScore: Int
            enum CodingKeys: String, CodingKey {
                case memberId = "member_id"
                case fullName = "full_name"
                case matchScore = "match_score"
            }
        }

        do {
            let results: [NameMatchRow] = try await supabase
                .rpc("search_members_by_name", params: ["p_query": AnyEncodable(fullName)])
                .execute()
                .value

            let matched = results.map { $0.memberId.uuidString }
            Log.info("[MATCH] بحث عن '\(fullName)' — \(matched.count) تطابق")
            return matched
        } catch {
            Log.warning("[MATCH] فشل البحث عن مطابقات الاسم: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - OTP Send / Verify

    /// Feature flag — اقلب لـ true بعد إعداد WhatsApp Business Account في Twilio Verify.
    /// إعداده يتطلب: Messaging Service + WhatsApp Sender معتمد من Meta.
    static let whatsappOTPEnabled = false

    /// قناة إرسال رمز التحقق — تُمرَّر إلى Twilio Verify عبر Supabase Auth.
    enum OTPChannel {
        case sms
        case whatsapp

        var supabaseChannel: MessagingChannel {
            switch self {
            case .sms: return .sms
            case .whatsapp: return .whatsapp
            }
        }

        var arabicLabel: String {
            switch self {
            case .sms: return "SMS"
            case .whatsapp: return "واتساب"
            }
        }

        var englishLabel: String {
            switch self {
            case .sms: return "SMS"
            case .whatsapp: return "WhatsApp"
            }
        }
    }

    /// طلب رمز جارٍ — ضغطتان سريعتان على «متابعة» أو «إعادة» ترسلان طلباً واحداً (طلب المالك ٢٠٢٦-١٠-٢٣)؛
    /// السيرفر يحمي أيضاً: رمز واحد لكل دقيقتين (`sms_one_code_seconds`)
    private var otpRequestInFlight = false

    // MARK: - رمز بانتظار الكتابة (المالك ٢٠٢٦-١٠-٢٤: «يذهب الى المسجات و يرجع الى التطبيق يعيد التطبيق من البداية»)
    // آخر رمز أُرسل يُحفظ على الجهاز ٥ دقائق (صلاحية الرمز)، فلو أغلق النظام التطبيق وهو في «الرسائل» يرجع لخانة الرمز.

    static let pendingOTPKey = "pendingOTP.v1"
    static let pendingOTPLifetime: TimeInterval = 300

    /// تعديل الرقم، الدخول، الخروج — لا رجوع لخانة الرمز بعدها. (`clearLocalSession` لا يلغيه: فحص الجلسة عند
    /// الإقلاع بلا حساب يمرّ به، وكان يمسح الرمز المحفوظ قبل ما تظهر شاشة الدخول)
    func cancelPendingOTP() {
        UserDefaults.standard.removeObject(forKey: Self.pendingOTPKey)
    }

    private func savePendingOTP() {
        UserDefaults.standard.set(["phone": phoneNumber, "dial": dialingCode, "at": Date().timeIntervalSince1970],
                                  forKey: Self.pendingOTPKey)
    }

    /// يرجع لخانة الرمز إن أُرسل رمز خلال آخر ٥ دقائق — الثواني المنقضية منذ الإرسال، أو nil
    @discardableResult
    func restorePendingOTPIfAny() -> TimeInterval? {
        guard status == .unauthenticated,
              let saved = UserDefaults.standard.dictionary(forKey: Self.pendingOTPKey),
              let phone = saved["phone"] as? String, let dial = saved["dial"] as? String,
              let at = saved["at"] as? TimeInterval else { return nil }
        let elapsed = Date().timeIntervalSince1970 - at
        guard elapsed >= 0, elapsed < Self.pendingOTPLifetime, !phone.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.pendingOTPKey)
            return nil
        }
        // الشاشة قد تُبنى من جديد والرمز ما زال ظاهراً — نرجع الوقت المنقضي فقط حتى تكمل العدّادات
        if !isOtpSent {
            phoneNumber = phone
            dialingCode = dial
            isOtpSent = true
        }
        Log.info("[OTP] رجوع لخانة الرمز بعد \(Int(elapsed)) ث")
        return elapsed
    }

    func sendOTP(channel: OTPChannel = .sms) async {
        guard !otpRequestInFlight else { return }
        otpRequestInFlight = true
        defer { otpRequestInFlight = false }
        otpRetryAfter = nil
        let cleanPhone = normalizePhoneDigits(phoneNumber)
        let cleanDialingCode = normalizeDialingCode(dialingCode)
        guard cleanPhone.count >= 6 else {
            self.otpErrorMessage = L10n.t("رقم الهاتف غير صالح.", "Invalid phone number.")
            self.otpStatusMessage = ""
            return
        }

        guard let finalPhone = toE164(dialingCode: cleanDialingCode, localDigits: cleanPhone) else {
            self.otpErrorMessage = L10n.t("تعذر تكوين رقم دولي صالح.", "Unable to form a valid international number.")
            self.otpStatusMessage = ""
            return
        }

        self.phoneNumber = cleanPhone
        self.dialingCode = cleanDialingCode
        self.isLoading = true
        self.otpErrorMessage = nil
        let channelAr = channel.arabicLabel
        let channelEn = channel.englishLabel
        self.otpStatusMessage = L10n.t(
            "جاري إرسال رمز التحقق عبر \(channelAr)...",
            "Sending verification code via \(channelEn)..."
        )

        // فحص الحظر قبل إرسال OTP
        if await isPhoneBanned(finalPhone) {
            self.otpErrorMessage = L10n.t(
                "هذا الرقم محظور من استخدام التطبيق.",
                "This phone number is banned from using the app."
            )
            self.otpStatusMessage = ""
            self.isLoading = false
            return
        }

        // محاولة واحدة فقط — تجنب استهلاك attempts من Twilio Verify
        do {
            Log.info("[OTP] إرسال OTP عبر \(channelEn) لـ \(Log.masked(finalPhone))")
            try await supabase.auth.signInWithOTP(
                phone: finalPhone,
                channel: channel.supabaseChannel,
                shouldCreateUser: true
            )

            Log.info("[OTP] ✅ تم إرسال OTP بنجاح عبر \(channelEn)")
            withAnimation(.spring()) {
                self.isOtpSent = true
            }
            savePendingOTP()
            self.otpErrorMessage = nil
            self.otpStatusMessage = L10n.t(
                "تم إرسال الرمز عبر \(channelAr)",
                "Code sent via \(channelEn)"
            )
            self.isLoading = false
            return
        } catch {
            Log.error("[OTP] ❌ فشل: \(error)")
            self.otpStatusMessage = ""
            self.otpRetryAfter = OTPWaitText.seconds(in: "\(error) \(error.localizedDescription)")
            self.otpErrorMessage = friendlyOTPErrorMessage(error: error, channel: channel)
            self.isLoading = false
        }
    }

    /// تحويل أخطاء Twilio/Supabase إلى رسالة عربية واضحة للمستخدم.
    private func friendlyOTPErrorMessage(error: Error, channel: OTPChannel) -> String {
        let raw = "\(error) \(error.localizedDescription)".lowercased()
        let suggestWhatsApp = channel == .sms && AuthViewModel.whatsappOTPEnabled

        // Twilio error 60410: phone temporarily blocked due to fraud
        if raw.contains("60410") || raw.contains("temporarily blocked") || raw.contains("fraudulent") {
            if suggestWhatsApp {
                return L10n.t(
                    "هذا الرقم محظور مؤقتاً من SMS بسبب محاولات متكررة. جرّب الإرسال عبر واتساب.",
                    "This number is temporarily blocked from SMS due to repeated attempts. Try WhatsApp instead."
                )
            }
            return L10n.t(
                "هذا الرقم محظور مؤقتاً بسبب محاولات متكررة. حاول بعد ساعة.",
                "This number is temporarily blocked due to repeated attempts. Try again in an hour."
            )
        }

        // Twilio error 60203: max send attempts (5 in 10 minutes)
        if raw.contains("60203") || raw.contains("max send attempts") {
            if suggestWhatsApp {
                return L10n.t(
                    "تجاوزت عدد محاولات SMS. انتظر 10 دقائق أو جرّب الإرسال عبر واتساب.",
                    "SMS attempts exceeded. Wait 10 min or try WhatsApp."
                )
            }
            return L10n.t(
                "تجاوزت عدد المحاولات. انتظر 10 دقائق ثم حاول.",
                "Attempts exceeded. Wait 10 minutes and try again."
            )
        }

        // «انتظر N ثانية» — الحجب يذكر الثواني (دالة KWT SMS أو Supabase نفسه)، قبل الفرع العام (٢٠٢٦-١٠-٢٠)
        if let wait = OTPWaitText.message(from: raw, arabic: L10n.isArabic) {
            return wait
        }

        // Rate limited (Supabase or Twilio)
        if raw.contains("429") || raw.contains("rate") || raw.contains("too many") {
            return L10n.t(
                // رمز واحد لكل رقم كل دقيقة (Supabase + دالة KWT SMS — ٢٠٢٦-١٠-١٩)
                "كثرة الطلبات. انتظر دقيقة وأعد المحاولة.",
                "Too many requests. Wait a minute and try again."
            )
        }

        // Invalid phone number
        if raw.contains("60200") || raw.contains("invalid parameter") || raw.contains("invalid phone") {
            return L10n.t(
                "رقم الهاتف غير صحيح. تحقق من الرقم ورمز الدولة.",
                "Invalid phone number. Check the number and country code."
            )
        }

        // WhatsApp not enrolled in Verify Service
        if raw.contains("whatsapp") && (raw.contains("not enabled") || raw.contains("not configured")) {
            return L10n.t(
                "خدمة واتساب غير متاحة حالياً. استخدم SMS.",
                "WhatsApp is not available now. Use SMS instead."
            )
        }

        // Generic fallback
        let channelAr = channel.arabicLabel
        let channelEn = channel.englishLabel
        if suggestWhatsApp {
            return L10n.t(
                "تعذر إرسال الرمز عبر \(channelAr). جرّب الإرسال عبر واتساب أو حاول لاحقاً.",
                "Unable to send via \(channelEn). Try WhatsApp or try later."
            )
        }
        return L10n.t(
            "تعذر إرسال الرمز عبر \(channelAr). حاول لاحقاً.",
            "Unable to send via \(channelEn). Try again later."
        )
    }
    
    func verifyOTP() async {
        let cleanCode = otpCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanCode.count == 6 else {
            self.otpErrorMessage = L10n.t("رمز التحقق يجب أن يكون 6 أرقام.", "Verification code must be 6 digits.")
            return
        }
        
        let cleanPhone = normalizePhoneDigits(phoneNumber)
        let cleanDialingCode = normalizeDialingCode(dialingCode)
        guard cleanPhone.count >= 6,
              let finalPhone = toE164(dialingCode: cleanDialingCode, localDigits: cleanPhone) else {
            self.otpErrorMessage = L10n.t("رقم الهاتف غير صالح.", "Invalid phone number.")
            return
        }

        self.isLoading = true
        self.otpErrorMessage = nil

        do {
            // التحقق من الرمز عن طريق سوبابيس
            try await supabase.auth.verifyOTP(
                phone: finalPhone,
                token: cleanCode,
                type: .sms
            )
            
            Log.info("تم التحقق من الرمز بنجاح!")
            AppAnalytics.trackLogin()
            
            // حفظ الرقم محلياً — يبقى بعد إعادة فتح التطبيق
            self.lastAuthPhone = cleanPhone
            self.lastAuthDialingCode = cleanDialingCode
            
            // بعد نجاح الرمز، نحدث بيانات المستخدم لكي يفتح التطبيق تلقائياً
            await checkUserProfile()
            
        } catch {
            Log.error("فشل التحقق: \(error.localizedDescription)")
            self.otpErrorMessage = L10n.t("الرمز غير صحيح أو منتهي. أعد طلب رمز جديد.", "Invalid or expired code. Please request a new one.")
        }
        
        self.isLoading = false

    }
    
    // MARK: - جسر امتداد المشاركة

    /// ينشر رمز الجلسة لحاوية App Group ليرفع امتداد المشاركة باسم العضو.
    /// يُستدعى عند كل تحقق أو تجديد للجلسة.
    func publishSessionToShareExtension(_ session: Session) {
        guard !isEndingSession, status == .fullyAuthenticated,
              session.user.id == supabase.auth.currentUser?.id, currentUser != nil else {
            SharedSessionStore.clear()
            return
        }
        SharedSessionStore.save(
            accessToken: session.accessToken,
            expiresAt: TimeInterval(session.expiresAt),
            memberId: currentUser?.id,
            memberName: currentUser?.fullName,
            isAdmin: isAdmin
        )
    }

    // MARK: - Profile Check
    
    /// تحديث الجلسة لو منتهية — يضمن JWT صالح لاستدعاء Edge Functions
    func refreshSessionIfNeeded() async {
        do {
            let session = try await supabase.auth.session
            // لو الجلسة قاربت على الانتهاء (أقل من ساعة)
            let expiresAt = Date(timeIntervalSince1970: TimeInterval(session.expiresAt))
            if expiresAt.timeIntervalSinceNow < 3600 {
                let refreshed = try await supabase.auth.refreshSession()
                publishSessionToShareExtension(refreshed)
                Log.info("[AUTH] تم تحديث الجلسة بنجاح")
            } else {
                publishSessionToShareExtension(session)
            }
        } catch {
            Log.warning("[AUTH] تعذر تحديث الجلسة: \(error.localizedDescription)")
            // محاولة refresh حتى لو فشل الأول
            do {
                _ = try await supabase.auth.refreshSession()
                Log.info("[AUTH] تم تحديث الجلسة (إعادة محاولة)")
            } catch {
                Log.error("[AUTH] فشل تحديث الجلسة نهائياً: \(error.localizedDescription)")
            }
        }
    }

    func checkUserProfile() async {
        guard !isEndingSession, !Task.isCancelled else { return }
        let generation = sessionGeneration
        // بدون نت + المستخدم مسجل — نحتفظ بالحالة الحالية ولا نتشيك
        if !NetworkMonitor.shared.isConnected && currentUser != nil {
            Log.info("[AUTH] بدون اتصال — نحتفظ بالحالة الحالية")
            return
        }

        // فتح التطبيق: العضو المفعّل محفوظ على الجهاز → يدخل فوراً والتحقق يكمل بالخلفية — لا انتظار على شاشة
        // البداية لتجديد الجلسة وثلاثة طلبات للخادم (طلب المالك ٢٠٢٦-١٠-٢٤ «لا يعلق عند الدخول»). إن تغيّر شيء
        // (جُمّد، حُذف رقمه، انتهت الجلسة) ينقله التحقق للشاشة الصحيحة، والسيرفر يحمي البيانات بنفسه.
        if status == .checking, currentUser == nil {
            restoreActiveMemberFromCache()
        }

        let user: Supabase.User
        do {
            user = try await supabase.auth.session.user
            guard generation == sessionGeneration, !isEndingSession, !Task.isCancelled else { return }
            cancelPendingOTP()
            CacheManager.shared.beginAccount(user.id)
        } catch {
            guard generation == sessionGeneration, !isEndingSession, !Task.isCancelled else { return }
            let errorDesc = error.localizedDescription.lowercased()
            // فقط نعتبره "لا يوجد جلسة" إذا كانت الجلسة فعلاً غير موجودة
            // جلسة ميتة على السيرفر (رمز تجديد ملغى/مستعمل) = لا جلسة → شاشة الدخول، لا انتظار بلا نهاية (ج-٦)
            let authCode = (error as? AuthError)?.errorCode
            let isReallyNoSession = errorDesc.contains("session not found")
                || errorDesc.contains("no session")
                || errorDesc.contains("not authenticated")
                || errorDesc.contains("auth session missing")
                || errorDesc.contains("refresh_token")
                || authCode == ErrorCode.sessionNotFound || authCode == ErrorCode.sessionExpired
                || authCode == ErrorCode.refreshTokenNotFound || authCode == ErrorCode.refreshTokenAlreadyUsed

            if isReallyNoSession {
                // ما زال على شاشة الدخول (مثلاً رجع من «الرسائل» ليكتب الرمز): لا شيء يُمسح — المسح كان يرجّعه
                // لخانة الرقم ويفرّغها (المالك ٢٠٢٦-١٠-٢٤)
                if status == .unauthenticated && currentUser == nil { return }
                Log.info("[AUTH] No session found → unauthenticated: \(error.localizedDescription)")
                clearLocalSession()
            } else if currentUser == nil {
                // خطأ شبكة أو خطأ مؤقت — لا نسجل خروج. cold start بلا نت والجلسة منتهية: تجديدها
                // يحتاج الشبكة فيفشل — فنقرأ الجلسة المحفوظة على الجهاز (بلا شبكة) ونستعيد العضو
                // من كاش حسابه (ج-٦: كان الكاش لا يُقرأ هنا قبل فتح حسابه فتدور شاشة البداية بلا نهاية)
                if let storedUser = supabase.auth.currentUser {
                    CacheManager.shared.beginAccount(storedUser.id)
                    if let cached = CacheManager.shared.load([FamilyMember].self, for: .members),
                       let profile = cached.first(where: { $0.id == storedUser.id }) {
                        Log.info("[AUTH] استعادة المستخدم من الكاش (بدون نت): \(profile.fullName)")
                        self.currentUser = profile
                        self.isAuthenticated = true
                        self.status = self.resolveAuthAccess(for: profile)
                        return
                    }
                }
                Log.warning("[AUTH] خطأ مؤقت في جلب الجلسة بلا كاش: \(error.localizedDescription)")
                showLaunchConnectionProblem(generation: generation)
            } else {
                Log.warning("[AUTH] خطأ مؤقت في جلب الجلسة (لن نسجل خروج): \(error.localizedDescription)")
            }
            return
        }

        // بدون نت بعد قراءة الجلسة — نستعيد من الكاش بدل جلب من السيرفر (بعد التأكد أن الخادم لا يرد فعلاً:
        // مراقب الشبكة قد يخطئ فيبقى الفحص متوقفاً والإنترنت شغّال)
        if !NetworkMonitor.shared.isConnected, !(await NetworkMonitor.shared.confirmReachable()) {
            guard generation == sessionGeneration, !isEndingSession, !Task.isCancelled else { return }
            if let cached = CacheManager.shared.load([FamilyMember].self, for: .members),
               let profile = cached.first(where: { $0.id == user.id }) {
                Log.info("[AUTH] استعادة المستخدم من الكاش (cold start بدون نت): \(profile.fullName)")
                self.currentUser = profile
                self.isAuthenticated = true
                let access = self.resolveAuthAccess(for: profile)
                self.status = access
            } else {
                Log.info("[AUTH] بدون اتصال — تخطي جلب البروفايل من السيرفر")
                // بلا كاش: لا دوران بلا نهاية (ج-٦)
                showLaunchConnectionProblem(generation: generation)
            }
            return
        }

        // استخدام الرقم المحفوظ محلياً كـ fallback إذا user.phone فارغ
        let rawPhone = user.phone ?? self.phoneNumber
        let normalizedSessionPhone: String
        if !rawPhone.isEmpty {
            normalizedSessionPhone = rawPhone
        } else if !lastAuthPhone.isEmpty {
            // استخدام الرقم المحفوظ من آخر تسجيل OTP
            let code = lastAuthDialingCode.isEmpty ? "+965" : lastAuthDialingCode
            normalizedSessionPhone = toE164(dialingCode: code, localDigits: lastAuthPhone) ?? lastAuthPhone
        } else {
            normalizedSessionPhone = ""
        }
        Log.info("[AUTH] Session found. UUID: \(user.id), Phone: \(Log.masked(normalizedSessionPhone))")
        /// خطأ شبكة/مؤقت أثناء البحث — ليس دليلاً على عدم وجود الحساب
        var lookupFailed = false

        // فحص الحظر — حماية مزدوجة
        if !normalizedSessionPhone.isEmpty, await isPhoneBanned(normalizedSessionPhone) {
            Log.info("[BAN] الرقم محظور بعد التحقق — تسجيل خروج: \(Log.masked(normalizedSessionPhone))")
            guard generation == sessionGeneration, !isEndingSession, !Task.isCancelled, user.id == supabase.auth.currentUser?.id else { return }
            await signOut()
            self.otpErrorMessage = L10n.t(
                "هذا الرقم محظور من استخدام التطبيق.",
                "This phone number is banned from using the app."
            )
            self.isOtpSent = false
            self.isLoading = false
            return
        }

        // بدون نت — لا نحاول جلب البروفايل من السيرفر
        if !NetworkMonitor.shared.isConnected, !(await NetworkMonitor.shared.confirmReachable()) {
            guard generation == sessionGeneration, !isEndingSession, !Task.isCancelled else { return }
            Log.info("[AUTH] بدون اتصال — تخطي جلب البروفايل من السيرفر")
            showLaunchConnectionProblem(generation: generation)   // لا دوران بلا نهاية (ج-٦)
            return
        }

        // المحاولة 1: البحث بـ auth.uid مباشرة
        let userIdString = user.id.uuidString.lowercased()
        do {
            let response: [FamilyMember] = try await supabase
                .from("members_masked") // الهاتف المخفي يُفرَّغ من السيرفر
                .select()
                .eq("id", value: userIdString)
                .limit(1)
                .execute()
                .value

            guard generation == sessionGeneration, !isEndingSession, !Task.isCancelled, user.id == supabase.auth.currentUser?.id else { return }
            if let profile = response.first {
                Log.info("[AUTH] Found profile by UUID: \(profile.fullName), role: \(profile.role), status: \(profile.status?.rawValue ?? "nil")")
                
                let existingPhone = profile.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                
                // المدير حذف الرقم من البروفايل → مباشرة لشاشة التسجيل (أو الانتظار إن أرسل طلبه — ب-٤)
                if existingPhone.isEmpty && profile.status != .frozen && profile.status != .deleted
                    && profile.role != .owner {
                    Log.info("[AUTH] البروفايل بدون رقم (المدير حذفه) — توجيه مباشر للتسجيل الجديد")
                    await routeProfileWithoutPhone(profile, normalizedPhone: normalizedSessionPhone, generation: generation)
                    return
                } else {
                    await applyAuthenticatedProfile(profile, normalizedPhone: normalizedSessionPhone)
                    return
                }
            } else {
                Log.warning("[AUTH] UUID lookup returned 0 results for: \(userIdString)")
            }
        } catch {
            guard generation == sessionGeneration, !isEndingSession, !Task.isCancelled else { return }
            Log.error("[AUTH] خطأ في جلب البروفايل بـ UUID: \(error.localizedDescription)")
            lookupFailed = true
        }

        // المحاولة 2: الملف المربوط بهذا الحساب على السيرفر (`current_profile_id()` —
        // app_metadata.profile_id). لا ربط على الجهاز بعد اليوم (فحص الثغرات ب-٦): البحث بالرقم ثم
        // نسخ الملف لمعرّف الدخول وحذف القديم كان يفصل الزوجات والبنات ويقص النسب. أول دخول لعضو
        // الشجرة يتبنّاه السيرفر نفسه (`adopt_tree_profile` عند إنشاء حساب الدخول) فيُوجد بالمعرّف أعلاه،
        // ومن لا ملف له يكمل التسجيل وتربطه الإدارة بـ «ربط بالشجرة» (دالة سيرفر بحراسها).
        if let linkedId = await serverProfileId(), linkedId != user.id,
           let linkedProfile = await loadProfile(by: linkedId) {
            guard generation == sessionGeneration, !isEndingSession, !Task.isCancelled, user.id == supabase.auth.currentUser?.id else { return }
            Log.info("[AUTH] Found profile linked on the server: \(linkedProfile.fullName)")
            await applyAuthenticatedProfile(linkedProfile, normalizedPhone: normalizedSessionPhone)
            return
        }

        // المحاولة 4: إعادة محاولة بعد تأخير قصير (لحالات التأخر في الشبكة)
        try? await Task.sleep(nanoseconds: 200_000_000)
        do {
            let retryResponse: [FamilyMember] = try await supabase
                .from("members_masked") // الهاتف المخفي يُفرَّغ من السيرفر
                .select()
                .eq("id", value: userIdString)
                .limit(1)
                .execute()
                .value
            guard generation == sessionGeneration, !isEndingSession, !Task.isCancelled, user.id == supabase.auth.currentUser?.id else { return }
            if let retryProfile = retryResponse.first {
                let retryPhone = retryProfile.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                // المدير حذف الرقم → مباشرة للتسجيل (أو الانتظار إن أرسل طلبه — ب-٤)
                if retryPhone.isEmpty && retryProfile.status != .frozen && retryProfile.status != .deleted
                    && retryProfile.role != .owner {
                    Log.info("[AUTH] بروفايل بدون رقم في المحاولة 4 — توجيه مباشر للتسجيل")
                    await routeProfileWithoutPhone(retryProfile, normalizedPhone: normalizedSessionPhone, generation: generation)
                    return
                } else {
                    Log.info("[AUTH] Found profile on retry by UUID: \(retryProfile.fullName)")
                    await applyAuthenticatedProfile(retryProfile, normalizedPhone: normalizedSessionPhone)
                    return
                }
            }
        } catch {
            guard generation == sessionGeneration, !isEndingSession, !Task.isCancelled else { return }
            Log.warning("[AUTH] Retry check failed: \(error.localizedDescription)")
            lookupFailed = true
        }

        guard generation == sessionGeneration, !isEndingSession, !Task.isCancelled, user.id == supabase.auth.currentUser?.id else { return }

        // تعثّر الاتصال ≠ «لا يوجد حساب» (شكوى المالك ٢٠٢٦-٠٩-٢٨): كان أي خطأ مؤقت لحظة
        // الرجوع للتطبيق يفتح شاشة التسجيل ويمسح الكاش — كأن الحساب انحذف وبياناته راحت.
        if lookupFailed {
            if currentUser != nil {
                Log.warning("[AUTH] تعذّر التحقق من البروفايل (خطأ مؤقت) — نُبقي الحالة الحالية")
                return
            }
            if let cached = CacheManager.shared.load([FamilyMember].self, for: .members),
               let profile = cached.first(where: { $0.id == user.id }) {
                Log.info("[AUTH] خطأ مؤقت — استعادة المستخدم من الكاش: \(profile.fullName)")
                self.currentUser = profile
                self.isAuthenticated = true
                self.status = self.resolveAuthAccess(for: profile)
                return
            }
            // لا كاش: شاشة البداية مع إعادة المحاولة بعد لحظات — لا شاشة تسجيل خاطئة
            Log.warning("[AUTH] خطأ مؤقت بلا كاش — إعادة المحاولة بعد ٣ ثوانٍ")
            self.status = .checking
            scheduleProfileRecheck(generation: generation)
            return
        }

        Log.warning("[AUTH] ⚠️ لم يتم العثور على بروفايل بعد 4 محاولات. Phone: \(Log.masked(normalizedSessionPhone)), UUID: \(userIdString)")
        self.status = .authenticatedNoProfile
    }

    /// العضو المفعّل من كاش حسابه (جلسة محفوظة على الجهاز، بلا شبكة) — للدخول الفوري عند فتح التطبيق.
    /// غير المفعّل (معلّق، مجمّد، بلا رقم…) ينتظر التحقق من الخادم كما كان.
    private func restoreActiveMemberFromCache() {
        guard let storedUser = supabase.auth.currentUser else { return }
        CacheManager.shared.beginAccount(storedUser.id)
        guard let cached = CacheManager.shared.load([FamilyMember].self, for: .members),
              let profile = cached.first(where: { $0.id == storedUser.id }),
              resolveAuthAccess(for: profile) == .fullyAuthenticated else { return }
        Log.info("[AUTH] دخول فوري من الكاش — التحقق يكمل بالخلفية")
        currentUser = profile
        isAuthenticated = true
        status = .fullyAuthenticated
    }

    /// إعادة فحص البروفايل بعد خطأ مؤقت (بلا كاش) — ما دامت الجلسة نفسها على شاشة البداية
    private func scheduleProfileRecheck(generation: UUID) {
        profileRecheckTask?.cancel()   // محاولة مجدولة واحدة فقط (لا سلاسل متوازية مع «إعادة المحاولة»)
        profileRecheckTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self, generation == self.sessionGeneration, !self.isEndingSession,
                  self.status == .checking else { return }
            await self.checkUserProfile()
        }
    }

    // MARK: - Banned Phones (حظر الأرقام)

    /// فحص هل الرقم محظور — بنفس مطابقة السيرفر (`KuwaitPhone.banKey`: الرقم كاملاً برمز دولته)
    func isPhoneBanned(_ phone: String) async -> Bool {
        do {
            let banned = try await activeBans(matching: phone)
            if !banned.isEmpty { Log.info("[BAN] الرقم محظور: \(Log.masked(phone))") }
            return !banned.isEmpty
        } catch {
            // لو الجدول ما موجود بعد — نتجاهل الخطأ ونسمح بالدخول (السيرفر يفرض الحظر بنفسه)
            Log.warning("[BAN] خطأ في فحص الحظر: \(error.localizedDescription)")
            return false
        }
    }

    /// الحظر الفعّال لرقم — لزرّ «حظر الرقم / إلغاء الحظر» في «إدارة السجل»
    func activeBan(for phone: String) async -> BannedPhone? {
        do {
            return try await activeBans(matching: phone).first
        } catch {
            Log.warning("[BAN] خطأ في فحص حظر الرقم: \(error.localizedDescription)")
            return nil
        }
    }

    /// الأرقام المحظورة الفعّالة المطابقة لرقم — قائمة الحظر صغيرة فتُقارن هنا بمفتاح السيرفر نفسه
    /// (المحلي والدولي والأجنبي بأي صيغة حُفظ)
    private func activeBans(matching phone: String) async throws -> [BannedPhone] {
        let key = KuwaitPhone.banKey(phone)
        guard key.count >= 8 else { return [] }
        let active: [BannedPhone] = try await supabase
            .from("banned_phones")
            .select()
            .eq("is_active", value: true)
            .execute()
            .value
        return active.filter { KuwaitPhone.banKey($0.phoneNumber) == key }
    }

    /// جلب جميع الأرقام المحظورة
    func fetchBannedPhones() async {
        do {
            let result: [BannedPhone] = try await supabase
                .from("banned_phones")
                .select()
                .eq("is_active", value: true)
                .order("created_at", ascending: false)
                .execute()
                .value
            self.bannedPhones = result
        } catch {
            Log.error("[BAN] خطأ في جلب الأرقام المحظورة: \(error.localizedDescription)")
        }
    }

    /// حظر رقم هاتف
    func banPhone(_ phone: String, reason: String?) async -> Bool {
        guard let adminId = currentUser?.id else { return false }
        // الكويتي يُحفظ محلياً (٨ أرقام) كما كان، والأجنبي كاملاً برمز دولته — ليطابقه السيرفر
        // (كان يُحفظ أول ٨ أرقام من الأجنبي فلا يُجمَّد صاحبه ولا يُمنع تسجيله)
        let key = KuwaitPhone.banKey(phone)
        guard key.count >= 8 else { return false }
        let normalizedPhone = key.count == 11 && key.hasPrefix("965") ? String(key.dropFirst(3)) : "+" + key

        do {
            try await supabase
                .from("banned_phones")
                .insert([
                    "phone_number": normalizedPhone,
                    "reason": reason ?? "",
                    "banned_by": adminId.uuidString
                ])
                .execute()
            Log.info("[BAN] تم حظر الرقم: \(Log.masked(normalizedPhone))")
            await fetchBannedPhones()
            return true
        } catch {
            Log.error("[BAN] خطأ في حظر الرقم: \(error.localizedDescription)")
            return false
        }
    }

    /// إلغاء حظر رقم
    func unbanPhone(_ bannedPhoneId: UUID) async -> Bool {
        do {
            try await supabase
                .from("banned_phones")
                .update(["is_active": false])
                .eq("id", value: bannedPhoneId.uuidString)
                .execute()
            Log.info("[BAN] تم إلغاء حظر الرقم: \(bannedPhoneId)")
            await fetchBannedPhones()
            return true
        } catch {
            Log.error("[BAN] خطأ في إلغاء الحظر: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Sign Out
    
    private func clearLocalSession() {
        sessionGeneration = UUID()
        activeProfileCheckTask?.cancel()
        CacheManager.shared.clearAll()
        SharedSessionStore.clear()
        RealtimeManager.shared.unsubscribe()
        lastAuthPhone = ""
        lastAuthDialingCode = ""
        bannedPhones = []
        otpCode = ""
        withAnimation {
            status = .unauthenticated
            isAuthenticated = false
            currentUser = nil
            isOtpSent = false
            phoneNumber = ""
        }
    }

    func signOut() async {
        guard !isEndingSession else { return }
        isEndingSession = true
        defer { isEndingSession = false }
        await notificationVM?.unregisterPushToken()
        cancelPendingOTP()
        clearLocalSession()
        // هذا الجهاز فقط — الافتراضي .global كان يُخرج العضو من كل أجهزته
        // (الأندرويد والآيباد…) عند خروج واحد أو إزالة جهاز واحد من الإدارة.
        _ = try? await supabase.auth.signOut(scope: .local)
        StorageURLResolver.shared.reset()
        // Also invalidate saves queued by any work that finished during signOut.
        CacheManager.shared.clearAll()
        SharedSessionStore.clear()
    }

    func deleteAccount() async -> Bool {
        guard !isOwner else {
            deleteAccountError = L10n.t("حساب مالك التطبيق محمي. يلزم نقل الملكية قبل حذفه.",
                                       "The owner account is protected. Transfer ownership before deleting it.")
            return false
        }
        guard !isEndingSession else { return false }
        isLoading = true
        deleteAccountError = nil
        defer { isLoading = false }
        do {
            nonisolated struct DeletionResponse: Decodable { let ok: Bool }
            let response: DeletionResponse = try await supabase.functions.invoke(
                "delete-account", options: FunctionInvokeOptions(body: [:] as [String: String])
            )
            guard response.ok else { throw NSError(domain: "AccountDeletion", code: 1) }
            await signOut()
            return true
        } catch {
            deleteAccountError = L10n.t("لم يكتمل حذف الحساب. حاول مرة أخرى لإكمال التنظيف.",
                                       "Account deletion is incomplete. Please retry to finish cleanup.")
            Log.error("Account deletion did not complete")
            return false
        }
    }

    // MARK: - Registration
    
    func registerNewUser(firstName: String, familyName: String, birthDate: Date?, gender: String, fatherId: UUID? = nil, avatarImage: UIImage? = nil) async {
        self.isLoading = true
        self.registrationError = nil
        guard let user = try? await supabase.auth.session.user else {
            self.registrationError = L10n.t(
                "تعذّر إكمال التسجيل. تأكد من اتصالك بالإنترنت وحاول مرة أخرى.",
                "Registration couldn't be completed. Check your internet connection and try again."
            )
            self.isLoading = false
            return
        }
        
        let normalizedPhone = user.phone ?? self.phoneNumber

        // ب-٤: التسجيل لا يكتب فوق ملف موجود أبداً — كان الـ upsert يصفّر دور عضو الشجرة وحالته
        // ويخفيه ويقص نسبه (father_id = nil) ويكرّر طلبات الربط. ملف هذا الحساب (معرّفه = auth.uid،
        // أو المربوط على السيرفر عبر current_profile_id) يُقرأ بقراءة لا تبتلع الخطأ: «تعذّرت القراءة»
        // لا تعني «لا يوجد ملف».
        let ownRows: [FamilyMember]
        do {
            ownRows = try await supabase
                .from("members_masked") // الهاتف المخفي يُفرَّغ من السيرفر
                .select()
                .eq("id", value: user.id.uuidString.lowercased())
                .limit(1)
                .execute()
                .value
        } catch {
            Log.error("[REGISTER] تعذّرت قراءة ملف الحساب: \(error.localizedDescription)")
            self.registrationError = L10n.t(
                "تعذّر إكمال التسجيل. تأكد من اتصالك بالإنترنت وحاول مرة أخرى.",
                "Registration couldn't be completed. Check your internet connection and try again."
            )
            self.isLoading = false
            return
        }
        var ownProfile = ownRows.first
        if ownProfile == nil, let linkedId = await serverProfileId(), linkedId != user.id {
            ownProfile = await loadProfile(by: linkedId)
        }
        let cleanFamilyName = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        // الاسم الأخير = العائلة المختارة: لو كتب العضو عائلة في آخر اسمه
        // (نفس المختارة أو غيرها من القائمة) تُحذف ثم تُضاف المختارة — بلا تكرار
        let cleanFirstName = FamilyNameCatalog.stripTrailingFamily(firstName, chosen: cleanFamilyName)
        let fullName = cleanFamilyName.isEmpty ? cleanFirstName : "\(cleanFirstName) \(cleanFamilyName)"

        // عضو حقيقي في الشجرة (تبنّاه السيرفر عند الدخول، أو حذفت الإدارة رقمه) → يُستخدم كما هو
        if let existing = ownProfile,
           !existing.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           existing.role != .pending {
            await registerExistingProfile(existing, normalizedPhone: normalizedPhone, typedName: fullName)
            self.isLoading = false
            return
        }
        // ما بقي يُكتب: لا ملف، أو سجل مبدئي بلا اسم (أنشأه السيرفر عند الدخول)، أو تسجيله المعلّق
        // هو («تعديل البيانات» من شاشة الانتظار)
        let hasOwnRow = ownRows.first != nil
        
        // بحث تلقائي عن مطابقات في الشجرة بالاسم الكامل أو أجزاء منه — وقبلها ملف شجرة يحمل
        // رقمه ولم يتبنّه السيرفر: مطابقة تربطها الإدارة («ربط بالشجرة»)، لا نقل على الجهاز (ب-٦)
        let nameMatchedIds = await searchForNameMatches(fullName: fullName, firstName: cleanFirstName)
        let phoneMatchedIds = await phoneMatchedProfileIds(normalizedPhone, excluding: user.id).map(\.uuidString)
        let matchedMemberIds = phoneMatchedIds + nameMatchedIds.filter { !phoneMatchedIds.contains($0) }

        var profileData: [String: AnyEncodable] = [
            "id": AnyEncodable(user.id),
            "full_name": AnyEncodable(fullName),
            "family_name": AnyEncodable(cleanFamilyName),
            "first_name": AnyEncodable(cleanFirstName),
            "phone_number": AnyEncodable(user.phone ?? toE164(dialingCode: dialingCode, localDigits: phoneNumber)),
            "role": AnyEncodable("pending"),
            "status": AnyEncodable("pending"),
            "gender": AnyEncodable(gender.isEmpty ? nil : gender),
            "is_deceased": AnyEncodable(false),
            "is_married": AnyEncodable(false),
            "is_hidden_from_tree": AnyEncodable(true),
            "sort_order": AnyEncodable(0),
            "created_at": AnyEncodable(DateHelper.now)
        ]
        // الأب يُكتب فقط إن اختير — لا تفريغ لأب موجود
        if let fatherId { profileData["father_id"] = AnyEncodable(fatherId.uuidString) }
        // تاريخ الميلاد فقط إن اختاره فعلاً — لا يُحفظ تاريخ «قبل ٢٠ سنة» الافتراضي (٢٠٢٦-١٠-٠٥)
        if let birthDate { profileData["birth_date"] = AnyEncodable(DateHelper.format(birthDate)) }
        
        do {
            // لا «تحرير الرقم» من عضو آخر قبل الحفظ (كان free_phone_for_reregistration يفرّغه ولو كان
            // ملفاً مربوطاً بحساب): حارس السيرفر عند الحفظ يحرّره من ملف شجرة لم يدخل صاحبه فقط،
            // ويرفض (phone_in_use) إن كان لأحد الإدارة أو لملف له حساب دخول.
            if hasOwnRow {
                // سجل مبدئي أو تسجيله المعلّق — التحديث مشروط بـ «معلّق» فلا يمسّ ملفاً مفعّلاً
                var updateData = profileData
                updateData.removeValue(forKey: "id")
                try await supabase
                    .from("profiles")
                    .update(updateData)
                    .eq("id", value: user.id.uuidString)
                    .eq("status", value: "pending")
                    .execute()
            } else {
                try await supabase
                    .from("profiles")
                    .insert(profileData)
                    .execute()
            }

            // التحقق من نجاح الإنشاء
            let verifyProfile = await loadProfile(by: user.id)
            let profileVerified = (verifyProfile?.role == .pending)
            if let vp = verifyProfile {
                Log.info("[REGISTER] ✅ تم إنشاء البروفايل بنجاح: \(vp.fullName), UUID: \(user.id), role: \(vp.role)")
            } else {
                Log.error("[REGISTER] ⚠️ الحفظ لم يُنشئ السجل! UUID: \(user.id). قد يكون RLS يمنع الإنشاء.")
            }

            // رفع الصورة الشخصية إذا اختارها المستخدم
            if profileVerified, let avatarImage, let imageData = ImageProcessor.process(avatarImage, for: .avatar) {
                let fileName = "\(user.id.uuidString.lowercased()).jpg"
                do {
                    try await supabase.storage
                        .from("avatars")
                        .upload(fileName, data: imageData, options: FileOptions(contentType: "image/jpeg", upsert: true))

                    let publicUrl = try supabase.storage
                        .from("avatars")
                        .getPublicURL(path: fileName)

                    let timestamp = Int(Date().timeIntervalSince1970)
                    let urlString = "\(publicUrl.absoluteString)?v=\(timestamp)"

                    try await supabase
                        .from("profiles")
                        .update(["avatar_url": AnyEncodable(urlString)])
                        .eq("id", value: user.id.uuidString)
                        .execute()

                    Log.info("[REGISTER] ✅ تم رفع الصورة الشخصية: \(fileName)")
                } catch {
                    Log.warning("[REGISTER] ⚠️ فشل رفع الصورة: \(error.localizedDescription)")
                }
            }
            
            // بناء تفاصيل الطلب مع المطابقات المحتملة
            let matchInfo: String
            if matchedMemberIds.isEmpty {
                matchInfo = "طلب انضمام جديد — لا توجد مطابقات بالاسم في الشجرة"
            } else {
                matchInfo = "طلب ربط — وُجدت \(matchedMemberIds.count) مطابقة محتملة|matched_ids:\(matchedMemberIds.joined(separator: ","))"
            }
            
            // طلب ربط واحد فقط — «تعديل البيانات» لا يكرّره
            var requestOutcome: LinkRequestOutcome? = nil
            if profileVerified {
                requestOutcome = await ensurePendingLinkRequest(profileId: user.id, details: matchInfo)
            }

            // فشل إنشاء البروفايل (RLS) أو طلب الانضمام → لا نُجبر شاشة الانتظار: المستخدم
            // سينتظر موافقة لا يمكن أن تصل. نعرض خطأً ونُبقيه في شاشة التسجيل ليعيد المحاولة.
            guard profileVerified, let requestOutcome else {
                Log.error("[REGISTER] ⛔️ تسجيل غير مكتمل — profileVerified=\(profileVerified), joinRequest=\(requestOutcome != nil)")
                self.registrationError = L10n.t(
                    "تعذّر إكمال طلب الانضمام. تأكد من اتصالك بالإنترنت وحاول مرة أخرى.",
                    "Couldn't complete your join request. Check your internet connection and try again."
                )
                self.isLoading = false
                return
            }

            // الإدارة تُبلَّغ مرة واحدة — عند إنشاء الطلب فقط
            if requestOutcome == .created {
                // الإشعار الداخلي والدفع يصدران من طلب الانضمام المحفوظ في قاعدة البيانات.
                // لا نرسل نسخة ثانية من التطبيق.

                // إيميل للإدارة بطلب الانضمام الجديد
                await sendEventEmail(payload: [
                    "type": AnyEncodable("join_request"),
                    "member_name": AnyEncodable(fullName),
                    "member_phone": AnyEncodable(user.phone ?? toE164(dialingCode: dialingCode, localDigits: phoneNumber))
                ])
            }

            Log.info("تم تسجيل العضو وإرسال طلب الربط بنجاح")
            AppAnalytics.trackRegister()

            // بعد نجاح الحفظ — نضمن الانتقال لشاشة الانتظار مباشرة
            if let createdProfile = await loadProfile(by: user.id) {
                await applyAuthenticatedProfile(createdProfile, normalizedPhone: KuwaitPhone.localEightDigits(normalizedPhone))
            } else {
                // حتى لو فشل تحميل البروفايل، السجل اتسوى → ننقل لشاشة الانتظار
                self.status = .pendingApproval
            }
            
        } catch {
            Log.error("خطأ في التسجيل: \(error.localizedDescription)")
            // فشل التسجيل (شبكة/خادم) → أظهر خطأً للمستخدم بدل الطرد الصامت،
            // ثم أعد فحص البروفايل (يُبقيه في شاشة التسجيل إن لم يُنشأ السجل).
            let raw = "\(error) \(error.localizedDescription)".lowercased()
            self.registrationError = raw.contains("phone_in_use")
                ? L10n.t("هذا الرقم مسجّل لعضو آخر. تواصل مع إدارة العائلة.",
                         "This number is registered to another member. Please contact the family administration.")
                : L10n.t("تعذّر إكمال التسجيل. تأكد من اتصالك بالإنترنت وحاول مرة أخرى.",
                         "Registration couldn't be completed. Check your internet connection and try again.")
            await checkUserProfile()
        }
        self.isLoading = false
    }

    /// التسجيل وجد ملفاً حقيقياً لهذا الحساب (عضو شجرة تبنّاه السيرفر، أو عضو حذفت الإدارة رقمه):
    /// لا يُكتب فوقه شيء (ب-٤) — لا إخفاء ولا قص نسب ولا تصفير. المفعّل/المجمّد كما يقرّره ملفه،
    /// والباقي طلب ربط واحد للإدارة ثم شاشة الانتظار.
    private func registerExistingProfile(_ existing: FamilyMember, normalizedPhone: String, typedName: String) async {
        guard resolveAuthAccess(for: existing) == .authenticatedNoProfile else {
            Log.info("[REGISTER] ملف قائم لهذا الحساب — يُستخدم كما هو: \(existing.fullName)")
            await applyAuthenticatedProfile(existing, normalizedPhone: normalizedPhone)
            return
        }
        // ما كتبه في النموذج يصل للإدارة للمراجعة فقط — لا يُكتب على ملفه
        let typed = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = "طلب انضمام — العضو موجود في الشجرة: \(existing.fullName) — لا يحتاج ربطاً، الموافقة تفعّله"
            + (typed.isEmpty || typed == existing.fullName ? "" : " (كتب في التسجيل: \(typed))")
        guard let outcome = await ensurePendingLinkRequest(profileId: existing.id, details: details) else {
            self.registrationError = L10n.t(
                "تعذّر إكمال طلب الانضمام. تأكد من اتصالك بالإنترنت وحاول مرة أخرى.",
                "Couldn't complete your join request. Check your internet connection and try again."
            )
            return
        }
        if outcome == .created {
            // نفس مسار التسجيل الجديد: قاعدة البيانات تنشئ إشعار الطلب مرة واحدة.
            await sendEventEmail(payload: [
                "type": AnyEncodable("join_request"),
                "member_name": AnyEncodable(existing.fullName),
                "member_phone": AnyEncodable(normalizedPhone)
            ])
        }
        Log.info("[REGISTER] ملف شجرة قائم — بلا كتابة فوقه، والطلب عند الإدارة: \(existing.fullName)")
        AppAnalytics.trackRegister()
        // يصل لشاشة الانتظار: الطلب المعلّق يحوّل «التسجيل» إلى «الانتظار» (applyAuthenticatedProfile)
        await applyAuthenticatedProfile(existing, normalizedPhone: KuwaitPhone.localEightDigits(normalizedPhone))
    }

    // MARK: - Contact

    func sendContactMessage(category: String, message: String, preferredContact: String?) async -> Bool {
        guard let user = currentUser else {
            Log.error("[Contact] ❌ لا يوجد مستخدم حالي — تم إلغاء الإرسال")
            return false
        }
        Log.info("[Contact] 📨 بدء إرسال رسالة تواصل — التصنيف: \(category), المرسل: \(user.fullName)")
        self.isLoading = true
        contactMessageError = nil

        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMessage.isEmpty else {
            Log.warning("[Contact] ⚠️ الرسالة فارغة — تم الإلغاء")
            contactMessageError = "الرسالة فارغة."
            self.isLoading = false
            return false
        }

        var details = """
        التصنيف: \(category)
        الرسالة: \(cleanMessage)
        """
        // وسيلة تواصل اختيارية يرد عليها المدير (إيميل أو رقم) — طلب المالك
        if let pc = preferredContact?.trimmingCharacters(in: .whitespacesAndNewlines), !pc.isEmpty {
            details += "\nوسيلة التواصل: \(pc)"
        }

        do {
            // 1. حفظ في admin_requests
            Log.info("[Contact] 1️⃣ حفظ الطلب في admin_requests...")
            let basePayload: [String: AnyEncodable] = [
                "member_id": AnyEncodable(user.id.uuidString),
                "requester_id": AnyEncodable(user.id.uuidString),
                "request_type": AnyEncodable("contact_message"),
                "status": AnyEncodable(ApprovalStatus.pending.rawValue),
                "details": AnyEncodable(details)
            ]
            
            do {
                var payload = basePayload
                payload["new_value"] = AnyEncodable(category)
                
                try await supabase
                    .from("admin_requests")
                    .insert(payload)
                    .execute()
                Log.info("[Contact] ✅ تم الحفظ في admin_requests بنجاح")
            } catch {
                if ErrorHelper.isMissingColumn(error, column: "new_value") {
                    Log.warning("[Contact] ⚠️ عمود new_value غير موجود — إعادة المحاولة بدونه")
                    try await supabase
                        .from("admin_requests")
                        .insert(basePayload)
                        .execute()
                    Log.info("[Contact] ✅ تم الحفظ في admin_requests (بدون new_value)")
                } else {
                    throw error
                }
            }

            // 2. إرسال الإيميل عبر contact-email
            Log.info("[Contact] 2️⃣ استدعاء contact-email edge function...")
            let emailPayload: [String: AnyEncodable] = [
                "category": AnyEncodable(category),
                "message": AnyEncodable(cleanMessage),
                "sender_name": AnyEncodable(user.fullName),
                "sender_phone": AnyEncodable(user.phoneNumber)
            ]

            do {
                try await supabase.functions.invoke(
                    "contact-email",
                    options: FunctionInvokeOptions(body: emailPayload)
                )
                Log.info("[Contact] ✅ contact-email اكتمل بنجاح (لم يرمِ خطأ)")
            } catch {
                Log.warning("[Contact] ⚠️ فشل contact-email: \(error.localizedDescription)")
                Log.warning("[Contact] ⚠️ تفاصيل الخطأ: \(error)")
            }

            // 3. إشعار المشرفين
            Log.info("[Contact] 3️⃣ إرسال إشعار للمشرفين...")
            await notifyAdminsWithPush(
                title: "رسالة تواصل",
                body: "رسالة \(category) جديدة.",
                kind: "contact_message"
            )
            Log.info("[Contact] ✅ تم إرسال إشعار المشرفين")

            Log.info("[Contact] ✅ اكتمل إرسال رسالة التواصل بنجاح")
            self.isLoading = false
            return true
        } catch {
            Log.error("[Contact] ❌ خطأ إرسال رسالة التواصل: \(error.localizedDescription)")
            Log.error("[Contact] ❌ تفاصيل: \(error)")
            contactMessageError = error.localizedDescription
            self.isLoading = false
            return false
        }
    }
    
    // MARK: - Weekly Digest
    
    /// تشغيل الملخص الأسبوعي يدوياً (للمدير)
    func triggerWeeklyDigest() async -> (success: Bool, message: String) {
        do {
            let response: Data = try await supabase.functions.invoke(
                "weekly-digest",
                options: FunctionInvokeOptions(method: .post)
            ) { data, _ in data }

            if let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
               let ok = json["ok"] as? Bool, ok {
                let notified = json["notified"] as? Int ?? 0
                return (true, L10n.t("تم إرسال الملخص الأسبوعي لـ \(notified) عضو", "Weekly digest sent to \(notified) members"))
            }
            return (false, L10n.t("فشل إرسال الملخص", "Failed to send digest"))
        } catch {
            Log.error("Weekly digest error: \(error.localizedDescription)")
            return (false, error.localizedDescription)
        }
    }
    
    // MARK: - Utility
    
    // دالة مساعدة لجلب حجم الذاكرة المستهلكة حالياً (بالميجابايت)
    func getMemoryUsage() -> Double {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(taskInfo.resident_size) / 1024 / 1024 // تحويل من بايت إلى ميجابايت
        } else {
            return 0
        }
    }
}
