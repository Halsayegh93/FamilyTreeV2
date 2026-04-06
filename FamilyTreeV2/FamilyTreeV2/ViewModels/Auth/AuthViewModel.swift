import Foundation
import Supabase
import SwiftUI
import Combine

private struct OTPFallbackRequest: Encodable {
    let phone: String
    let channels: [String]
}

private struct OTPFallbackResponse: Decodable {
    let accepted: Bool?
    let message: String?
}

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

    static let shared = LanguageManager()

    init() {}

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

    enum OTPDeliveryChannel: String, CaseIterable, Identifiable {
        case sms
        case whatsapp
        case call

        var id: String { rawValue }

        var backendValue: String {
            switch self {
            case .sms: return "sms"
            case .whatsapp: return "whatsapp"
            case .call: return "call"
            }
        }
    }
    
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
    @Published var currentUser: FamilyMember? = nil
    @Published var status: AuthStatus = .checking
    @Published var notificationsFeatureAvailable: Bool = true
    @Published var newsApprovalFeatureAvailable: Bool = true
    @Published var contactMessageError: String?
    @Published var otpErrorMessage: String?
    @Published var otpStatusMessage: String = ""
    @Published var deleteAccountError: String?
    @Published var bannedPhones: [BannedPhone] = []

    enum AuthStatus {
        case unauthenticated
        case checking
        case authenticatedNoProfile
        case fullyAuthenticated
        case pendingApproval
        case accountFrozen
    }
    
    static let maxDevicesPerAccount = 3

    weak var notificationVM: NotificationViewModel?
    weak var appSettingsVM: AppSettingsViewModel?
    
    // MARK: - صلاحيات الأدوار

    /// المالك — UUID ثابت (غيّره لحساب المالك الفعلي)
    static let ownerUUID = UUID(uuidString: "9849ab4f-fc16-495e-b82d-33811d4b8d3c")

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
    var canRejectRequests: Bool {
        currentUser?.role == .owner || currentUser?.role == .admin || currentUser?.role == .monitor
    }

    /// تغيير أدوار الأعضاء (ترقية/تنزيل) — المالك فقط
    var canManageRoles: Bool { isOwner }

    /// حذف أعضاء نهائياً — مدير + مالك
    var canDeleteMembers: Bool { isAdmin }

    /// إعدادات التطبيق — المالك فقط
    var canManageSettings: Bool { isOwner }

    /// أرقام محظورة — المالك فقط
    var canManageBannedPhones: Bool { isOwner }

    /// إدارة الأجهزة — المالك فقط
    var canManageDevices: Bool { isOwner }

    /// تعديل بيانات أعضاء آخرين — مدير + مراقب + مالك (المراقب محدود)
    var canEditMembers: Bool { isAdmin || currentUser?.role == .monitor }

    /// حذف أخبار — مدير + مراقب + مالك
    var canDeleteNews: Bool { isAdmin || currentUser?.role == .monitor }

    /// إرسال إشعارات يدوية — مدير + مالك
    var canSendNotifications: Bool { isAdmin }

    /// تسجيل عضو جديد مباشرة — مدير + مشرف + مالك
    var canRegisterMembers: Bool { canModerate }

    var canAutoPublishNews: Bool {
        canModerate
    }

    // MARK: - صلاحيات المحتوى

    /// حذف تعليقات الأعضاء — مدير + مراقب + مالك
    var canDeleteComments: Bool { isAdmin || currentUser?.role == .monitor }

    /// تجميد حسابات الأعضاء — مدير + مالك
    var canFreezeMembers: Bool { isAdmin }

    /// حذف قصص الأعضاء — مدير + مراقب + مالك
    var canDeleteStories: Bool { isAdmin || currentUser?.role == .monitor }

    /// حذف ديوانيات — مدير + مالك
    var canDeleteDiwaniyas: Bool { isAdmin }

    /// حذف صور الأعضاء — مدير + مراقب + مالك
    var canDeletePhotos: Bool { isAdmin || currentUser?.role == .monitor }

    // MARK: - Schema Error Helpers
    
    private func schemaErrorDescription(_ error: Error) -> String {
        let raw = String(describing: error)
        return "\(raw) \(error.localizedDescription)".lowercased()
    }
    
    private func isMissingNotificationsTableError(_ error: Error) -> Bool {
        let desc = schemaErrorDescription(error)
        return desc.contains("public.notifications") ||
        desc.contains("could not find the table") ||
        desc.contains("relation \"notifications\" does not exist") ||
        desc.contains("42p01")
    }
    
    private func isMissingNewsApprovalColumnError(_ error: Error) -> Bool {
        let desc = schemaErrorDescription(error)
        return (desc.contains("news.approval_status") && desc.contains("does not exist")) ||
        (desc.contains("42703") && desc.contains("approval_status"))
    }

    private func isMissingNewsRichContentColumnError(_ error: Error) -> Bool {
        let desc = schemaErrorDescription(error)
        let mentionsRichColumns =
            desc.contains("image_urls") ||
            desc.contains("poll_question") ||
            desc.contains("poll_options")
        
        return (desc.contains("42703") && mentionsRichColumns) ||
        (mentionsRichColumns && (
            desc.contains("could not find") ||
            desc.contains("schema cache") ||
            desc.contains("pgrst")
        ))
    }
    
    private func isMissingNewsSchemaColumnError(_ error: Error) -> Bool {
        let desc = schemaErrorDescription(error)
        guard desc.contains("42703") else { return false }
        
        return desc.contains("approved_by") ||
        desc.contains("approved_at") ||
        desc.contains("author_id") ||
        desc.contains("author_name") ||
        desc.contains("author_role") ||
        desc.contains("role_color") ||
        desc.contains("content") ||
        desc.contains("image_url") ||
        desc.contains("type")
    }
    
    private func isMissingAdminRequestNewValueColumnError(_ error: Error) -> Bool {
        let desc = schemaErrorDescription(error)
        let mentionsNewValue = desc.contains("new_value")
        
        return (desc.contains("42703") && mentionsNewValue) ||
        (mentionsNewValue && (
            desc.contains("could not find") ||
            desc.contains("schema cache") ||
            desc.contains("pgrst")
        ))
    }

    private func isMissingNewsPollVotesTableError(_ error: Error) -> Bool {
        let desc = schemaErrorDescription(error)
        return desc.contains("news_poll_votes") &&
        (desc.contains("does not exist") || desc.contains("42p01"))
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        let desc = schemaErrorDescription(error)
        return desc.contains("cancelled") || desc.contains("canceled") || desc.contains("مُلغى")
    }

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

        guard profile.role != .pending else {
            return .pendingApproval
        }

        // العضو المجمد — يظهر له شاشة تجميد الحساب (بدون تسجيل خروج)
        if profile.status == .frozen {
            Log.info("[AUTH] العضو \(profile.fullName) حالته frozen → شاشة الحساب المجمد")
            return .accountFrozen
        }

        // العضو المعلق (status = pending) يظهر له شاشة انتظار الموافقة
        if profile.status == .pending {
            Log.info("[AUTH] العضو \(profile.fullName) حالته pending → شاشة انتظار الموافقة")
            return .pendingApproval
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
    
    init() {
        Task { await checkUserProfile() }
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
        
        if text.contains("429") || text.contains("rate") {
            return L10n.t("تم تجاوز عدد المحاولات. انتظر قليلًا ثم أعد المحاولة.", "Too many attempts. Please wait a moment and try again.")
        }
        if text.contains("network") || text.contains("timed out") {
            return L10n.t("تعذر الاتصال بالخادم. تأكد من الإنترنت ثم أعد المحاولة.", "Unable to connect to the server. Check your internet and try again.")
        }
        if text.contains("sms") || text.contains("provider") {
            return L10n.t("تعذر إرسال رمز التحقق عبر الرسائل حاليًا. حاول مجددًا بعد دقيقة.", "Unable to send verification code via SMS right now. Try again in a minute.")
        }
        
        return L10n.t("تعذر إرسال رمز التحقق حاليًا. حاول مرة أخرى.", "Unable to send verification code right now. Please try again.")
    }
    
    private func triggerOTPFallback(phone: String, channels: [OTPDeliveryChannel]) async -> (success: Bool, message: String) {
        guard let endpoint = SupabaseConfig.otpFallbackURL else {
            return (false, L10n.t("لم يتم تفعيل القناة البديلة في إعدادات التطبيق.", "Fallback channel is not enabled in app settings."))
        }
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = SupabaseConfig.otpFallbackAPIKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
        }
        
        let payload = OTPFallbackRequest(
            phone: phone,
            channels: channels.map(\.backendValue)
        )
        
        do {
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, L10n.t("فشل القناة البديلة: استجابة غير صالحة.", "Fallback channel failed: invalid response."))
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                return (false, L10n.t("فشل القناة البديلة: رمز \(httpResponse.statusCode).", "Fallback channel failed: code \(httpResponse.statusCode)."))
            }
            
            let decoded = try? JSONDecoder().decode(OTPFallbackResponse.self, from: data)
            let accepted = decoded?.accepted ?? true
            if accepted {
                return (true, decoded?.message ?? L10n.t("تم إرسال الرمز عبر قناة بديلة.", "Code sent via fallback channel."))
            } else {
                return (false, decoded?.message ?? L10n.t("تم رفض طلب القناة البديلة.", "Fallback channel request was rejected."))
            }
        } catch {
            return (false, L10n.t("فشل القناة البديلة: \(error.localizedDescription)", "Fallback channel failed: \(error.localizedDescription)"))
        }
    }
    
    // MARK: - Private Push / Notification Helpers
    
    private func sendExternalAdminPush(title: String, body: String, kind: String = "admin_request") async {
        do {
            let payload = [
                "title": title,
                "body": body,
                "kind": kind
            ]
            
            try await supabase.functions
                .invoke(
                    "push-admins",
                    options: FunctionInvokeOptions(body: payload)
                )
        } catch {
            Log.warning("تعذر إرسال Push خارجي للمدير: \(error.localizedDescription)")
        }
    }
    
    /// إرسال إشعار واحد في مركز الإشعارات (broadcast) يراه المدراء والمشرفون
    /// target_member_id = NULL يعني broadcast — الـ RLS يتكفل بإظهاره للمدراء فقط
    private func notifyAdmins(title: String, body: String, kind: String) async {
        let creatorId = currentUser?.id
        guard notificationsFeatureAvailable else { return }
        
        do {
            let payload: [String: AnyEncodable] = [
                "target_member_id": AnyEncodable(Optional<String>.none),
                "title": AnyEncodable(title),
                "body": AnyEncodable(body),
                "kind": AnyEncodable(kind),
                "created_by": AnyEncodable(creatorId?.uuidString)
            ]
            try await supabase.from("notifications").insert(payload).execute()
        } catch {
            if isMissingNotificationsTableError(error) {
                notificationsFeatureAvailable = false
            } else {
                Log.warning("تعذر إرسال إشعار للمدراء: \(error.localizedDescription)")
            }
        }
    }
    
    /// إشعار موحّد: يرسل push خارجي + إشعار داخلي في استدعاء واحد
    private func notifyAdminsWithPush(title: String, body: String, kind: String) async {
        async let push: Void = sendExternalAdminPush(title: title, body: body, kind: kind)
        async let inApp: Void = notifyAdmins(title: title, body: body, kind: kind)
        _ = await (push, inApp)
    }
    
    // MARK: - Profile Lookup Helpers
    
    private func loadProfile(by id: UUID) async -> FamilyMember? {
        do {
            let response: [FamilyMember] = try await supabase
                .from("profiles")
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
    
    private func pickBestProfileId(from rows: [PhoneLookupProfile]) -> UUID? {
        rows.max { lhs, rhs in
            func score(_ row: PhoneLookupProfile) -> Int {
                var value = 0
                if (row.status ?? "") == "active" { value += 2 }
                if (row.role ?? "") != "pending" { value += 1 }
                return value
            }
            return score(lhs) < score(rhs)
        }?.id
    }

    private func findProfileByPhone(_ rawPhone: String) async -> FamilyMember? {
        let normalized = digitsOnly(rawPhone)
        guard normalized.count >= 6 else { return nil }
        
        // استخراج الرقم المحلي (8 أرقام) للمقارنة مع التنسيق الكويتي
        let local8 = KuwaitPhone.localEightDigits(rawPhone)
        
        // بناء قائمة المرشحين مع تجنب التكرار
        var seen = Set<String>()
        var candidates: [String] = []
        func addCandidate(_ c: String) {
            let trimmed = c.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
            candidates.append(trimmed)
        }
        
        // الصيغ الأساسية
        addCandidate(rawPhone)                          // الإدخال الأصلي
        addCandidate(normalized)                        // أرقام فقط
        if local8.count == 8 {
            addCandidate(local8)                        // 8 أرقام محلية (التنسيق المخزن للكويت)
            addCandidate("+965\(local8)")               // E.164 كويتي
            addCandidate("965\(local8)")                // بدون +
            addCandidate("00965\(local8)")              // صيغة دولية
        }
        // صيغ إضافية إذا كان الرقم يبدأ بكود دولة
        if normalized != local8 {
            addCandidate("+\(normalized)")
            addCandidate("+965\(normalized)")
            addCandidate("965\(normalized)")
        }
        
        Log.info("[AUTH] findProfileByPhone: phone=\(Log.masked(rawPhone)), candidates=\(candidates.count)")
        
        // 1) محاولة مطابقة مباشرة على أكثر من صيغة شائعة
        for candidate in candidates {
            do {
                let response: [PhoneLookupProfile] = try await supabase
                    .from("profiles")
                    .select("id, phone_number, role, status")
                    .eq("phone_number", value: candidate)
                    .limit(20)
                    .execute()
                    .value
                if let profileId = pickBestProfileId(from: response),
                   let profile = await loadProfile(by: profileId) {
                    Log.info("[AUTH] تم العثور على بروفايل بالمطابقة المباشرة: \(profile.fullName) (candidate: \(candidate))")
                    return profile
                }
            } catch {
                Log.warning("فشل المطابقة المباشرة بالهاتف \(candidate): \(error)")
            }
        }
        
        // 2) محاولة أوسع: جلب الهواتف ثم تطبيعها محلياً لتفادي اختلاف التنسيقات
        do {
            let broad: [PhoneLookupProfile] = try await supabase
                .from("profiles")
                .select("id, phone_number, role, status")
                .limit(500)
                .execute()
                .value
            
            Log.info("[AUTH] بحث موسع: تم جلب \(broad.count) بروفايل")
            
            let matchedRows = broad.filter { phonesMatch(stored: $0.phoneNumber, targetRaw: normalized) }
            if let profileId = pickBestProfileId(from: matchedRows) {
                if let profile = await loadProfile(by: profileId) {
                    Log.info("[AUTH] تم العثور على بروفايل بالبحث الموسع: \(profile.fullName)")
                    return profile
                }
            }

            Log.warning("[AUTH] لم يتم العثور على أي مطابقة للهاتف: \(Log.masked(rawPhone))")
            return nil
        } catch {
            Log.warning("فشل المطابقة الموسعة بالهاتف: \(error)")
            return nil
        }
    }
    
    /// ربط بروفايل موجود بـ auth.uid الجديد — يُستخدم عندما يُعثر على بروفايل بالرقم بدلاً من UUID
    /// يتم تحديث المعرف الأساسي + جميع مراجع father_id التي تشير للمعرف القديم
    private func linkProfileToAuthUser(oldProfileId: UUID, newAuthUserId: UUID) async {
        guard oldProfileId != newAuthUserId else { return } // لا حاجة إذا كانا متطابقين
        
        let oldId = oldProfileId.uuidString.lowercased()
        let newId = newAuthUserId.uuidString.lowercased()
        
        Log.info("[AUTH] ربط البروفايل: \(oldId) → \(newId)")
        
        do {
            // 1) تحديث father_id لجميع الأبناء الذين يشيرون للمعرف القديم
            try await supabase
                .from("profiles")
                .update(["father_id": AnyEncodable(newId)])
                .eq("father_id", value: oldId)
                .execute()
            
            // 2) نسخ بيانات البروفايل القديم إلى صف جديد بالمعرف الجديد
            //    (لأن id هو primary key ولا يمكن تحديثه مباشرة)
            let oldProfiles: [FamilyMember] = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: oldId)
                .limit(1)
                .execute()
                .value
            
            guard let oldProfile = oldProfiles.first else {
                Log.warning("[AUTH] لم يُعثر على البروفايل القديم أثناء الربط")
                return
            }
            
            // بناء payload بالبيانات الموجودة
            var payload: [String: AnyEncodable] = [
                "id": AnyEncodable(newId),
                "full_name": AnyEncodable(oldProfile.fullName),
                "first_name": AnyEncodable(oldProfile.firstName),
                "phone_number": AnyEncodable(oldProfile.phoneNumber),
                "is_deceased": AnyEncodable(oldProfile.isDeceased),
                "role": AnyEncodable(oldProfile.role.rawValue),
                "status": AnyEncodable(oldProfile.status?.rawValue ?? "active"),
                "is_phone_hidden": AnyEncodable(oldProfile.isPhoneHidden),
                "is_hidden_from_tree": AnyEncodable(oldProfile.isHiddenFromTree),
                "sort_order": AnyEncodable(oldProfile.sortOrder),
                "is_married": AnyEncodable(oldProfile.isMarried)
            ]
            
            if let fatherId = oldProfile.fatherId {
                payload["father_id"] = AnyEncodable(fatherId.uuidString.lowercased())
            }
            if let birthDate = oldProfile.birthDate {
                payload["birth_date"] = AnyEncodable(birthDate)
            }
            if let deathDate = oldProfile.deathDate {
                payload["death_date"] = AnyEncodable(deathDate)
            }
            if let avatarUrl = oldProfile.avatarUrl {
                payload["avatar_url"] = AnyEncodable(avatarUrl)
            }
            if let photoURL = oldProfile.photoURL {
                payload["photo_url"] = AnyEncodable(photoURL)
            }
            if let gender = oldProfile.gender {
                payload["gender"] = AnyEncodable(gender)
            }
            if let bio = oldProfile.bio, !bio.isEmpty {
                let encoder = JSONEncoder()
                if let bioData = try? encoder.encode(bio),
                   let bioString = String(data: bioData, encoding: .utf8) {
                    payload["bio_json"] = AnyEncodable(bioString)
                }
            }
            
            // إدخال البروفايل الجديد (upsert لتجنب الخطأ إذا كان موجوداً)
            try await supabase
                .from("profiles")
                .upsert(payload)
                .execute()
            
            // 3) حذف البروفايل القديم
            try await supabase
                .from("profiles")
                .delete()
                .eq("id", value: oldId)
                .execute()
            
            // 4) تحديث device_tokens إذا كانت موجودة
            do {
                try await supabase.from("device_tokens").update(["user_id": AnyEncodable(newId)]).eq("user_id", value: oldId).execute()
            } catch { Log.warning("[AUTH] فشل تحديث device_tokens أثناء الربط: \(error.localizedDescription)") }

            // 5) تحديث admin_requests
            do {
                try await supabase.from("admin_requests").update(["member_id": AnyEncodable(newId)]).eq("member_id", value: oldId).execute()
            } catch { Log.warning("[AUTH] فشل تحديث admin_requests أثناء الربط: \(error.localizedDescription)") }

            // 6) تحديث notifications
            do {
                try await supabase.from("notifications").update(["target_member_id": AnyEncodable(newId)]).eq("target_member_id", value: oldId).execute()
            } catch { Log.warning("[AUTH] فشل تحديث notifications أثناء الربط: \(error.localizedDescription)") }

            // 7) تحديث news
            do {
                try await supabase.from("news").update(["author_id": AnyEncodable(newId)]).eq("author_id", value: oldId).execute()
            } catch { Log.warning("[AUTH] فشل تحديث news أثناء الربط: \(error.localizedDescription)") }

            // 8) تحديث member_gallery_photos
            do {
                try await supabase.from("member_gallery_photos").update(["member_id": AnyEncodable(newId)]).eq("member_id", value: oldId).execute()
            } catch { Log.warning("[AUTH] فشل تحديث member_gallery_photos أثناء الربط: \(error.localizedDescription)") }
            
            Log.info("[AUTH] ✅ تم ربط البروفايل بنجاح: \(oldProfile.fullName) → auth.uid: \(newId)")
        } catch {
            Log.error("[AUTH] ❌ فشل ربط البروفايل: \(error.localizedDescription)")
            // في حالة الفشل، نستمر بالبروفايل الأصلي — لا نوقف عملية الدخول
        }
    }
    
    private func applyAuthenticatedProfile(_ profile: FamilyMember, normalizedPhone: String?) async {
        let access = self.resolveAuthAccess(for: profile)

        // إذا العضو ما عنده رقم أو حالته معلقة → تسجيل خروج تلقائي
        if access == .unauthenticated {
            Log.info("[AUTH] العضو \(profile.fullName) غير مصرح له بالدخول → تسجيل خروج")
            await signOut()
            return
        }

        self.currentUser = profile
        self.status = access
        
        // جلب إعدادات التطبيق من السيرفر
        await appSettingsVM?.fetchSettings()
        if let normalizedPhone, normalizedPhone.count == 8 {
            self.phoneNumber = normalizedPhone
        }
        
        // تسجيل الجهاز — حتى لو pendingApproval عشان يوصله إشعار الموافقة
        if access == .fullyAuthenticated || access == .pendingApproval {
            await notificationVM?.registerDevice()
        }
    }
    
    /// بحث عن مطابقات الاسم في الشجرة — يُرجع قائمة بمعرفات الأعضاء المتطابقين
    private func searchForNameMatches(fullName: String, firstName: String) async -> [String] {
        do {
            let nameParts = fullName.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !nameParts.isEmpty else { return [] }

            var allCandidates: [UUID: Int] = [:] // UUID → عدد الأجزاء المتطابقة

            // بحث بكل جزء من الاسم — كل جزء يضيف نقطة
            for part in nameParts {
                guard part.count >= 2 else { continue }
                let results: [FamilyMember] = try await supabase
                    .from("profiles")
                    .select()
                    .ilike("full_name", pattern: "%\(part)%")
                    .neq("status", value: "pending")
                    .limit(50)
                    .execute()
                    .value

                for member in results {
                    allCandidates[member.id, default: 0] += 1
                }
            }

            // رتب حسب عدد الأجزاء المتطابقة — اللي يطابق أكثر أول
            // يعتبر تطابق إذا طابق اسمين على الأقل
            let minParts = min(2, nameParts.count)
            let matched = allCandidates
                .filter { $0.value >= minParts }
                .sorted { $0.value > $1.value }
                .prefix(10)
                .map { $0.key.uuidString }

            Log.info("[MATCH] بحث عن '\(fullName)' — لقى \(allCandidates.count) مرشح، \(matched.count) تطابق (>= \(minParts) أجزاء)")
            return Array(matched)
        } catch {
            Log.warning("فشل البحث عن مطابقات الاسم: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - OTP Send / Verify

    func sendOTP() async {
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
        self.otpStatusMessage = L10n.t("جاري إرسال رمز التحقق...", "Sending verification code...")

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

        let maxAttempts = 2

        for attempt in 1...maxAttempts {
            do {
                try await supabase.auth.signInWithOTP(
                    phone: finalPhone,
                    shouldCreateUser: true
                )
                
                    withAnimation(.spring()) {
                        self.isOtpSent = true
                    }
                    self.otpErrorMessage = nil
                    self.otpStatusMessage = L10n.t("تم إرسال الرمز عبر SMS", "Code sent via SMS")
                    self.isLoading = false
                    return
            } catch {
                let raw = "\(error) \(error.localizedDescription)".lowercased()
                let isRateLimited = raw.contains("429") || raw.contains("rate")
                
                if isRateLimited || attempt == maxAttempts {
                    break
                }

                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        // SMS فشل
        self.otpStatusMessage = ""
        self.otpErrorMessage = L10n.t(
            "تعذر إرسال رمز التحقق. حاول مرة أخرى.",
            "Unable to send verification code. Please try again."
        )

        self.isLoading = false
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
    
    // MARK: - Profile Check
    
    /// تحديث الجلسة لو منتهية — يضمن JWT صالح لاستدعاء Edge Functions
    func refreshSessionIfNeeded() async {
        do {
            let session = try await supabase.auth.session
            // لو الجلسة قاربت على الانتهاء (أقل من ساعة)
            let expiresAt = Date(timeIntervalSince1970: TimeInterval(session.expiresAt))
            if expiresAt.timeIntervalSinceNow < 3600 {
                _ = try await supabase.auth.refreshSession()
                Log.info("[AUTH] تم تحديث الجلسة بنجاح")
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
        let user: Supabase.User
        do {
            user = try await supabase.auth.session.user
        } catch {
            let errorDesc = error.localizedDescription.lowercased()
            // فقط نعتبره "لا يوجد جلسة" إذا كانت الجلسة فعلاً غير موجودة
            let isReallyNoSession = errorDesc.contains("session not found")
                || errorDesc.contains("no session")
                || errorDesc.contains("not authenticated")
                || errorDesc.contains("auth session missing")
                || errorDesc.contains("refresh_token")

            if isReallyNoSession {
                Log.info("[AUTH] No session found → unauthenticated: \(error.localizedDescription)")
                self.status = .unauthenticated
            } else {
                // خطأ شبكة أو خطأ مؤقت — لا نسجل خروج، نحتفظ بالحالة الحالية
                Log.warning("[AUTH] خطأ مؤقت في جلب الجلسة (لن نسجل خروج): \(error.localizedDescription)")
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

        // فحص الحظر — حماية مزدوجة
        if !normalizedSessionPhone.isEmpty, await isPhoneBanned(normalizedSessionPhone) {
            Log.info("[BAN] الرقم محظور بعد التحقق — تسجيل خروج: \(Log.masked(normalizedSessionPhone))")
            _ = try? await supabase.auth.signOut()
            self.status = .unauthenticated
            self.otpErrorMessage = L10n.t(
                "هذا الرقم محظور من استخدام التطبيق.",
                "This phone number is banned from using the app."
            )
            self.isOtpSent = false
            self.isLoading = false
            return
        }

        // المحاولة 1: البحث بـ auth.uid مباشرة
        let userIdString = user.id.uuidString.lowercased()
        do {
            let response: [FamilyMember] = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userIdString)
                .limit(1)
                .execute()
                .value

            if let profile = response.first {
                Log.info("[AUTH] Found profile by UUID: \(profile.fullName), role: \(profile.role), status: \(profile.status?.rawValue ?? "nil")")
                
                let existingPhone = profile.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                
                // المدير حذف الرقم من البروفايل → مباشرة لشاشة التسجيل
                if existingPhone.isEmpty {
                    Log.info("[AUTH] البروفايل بدون رقم (المدير حذفه) — توجيه مباشر للتسجيل الجديد")
                    self.status = .authenticatedNoProfile
                    return
                } else {
                    await applyAuthenticatedProfile(profile, normalizedPhone: normalizedSessionPhone)
                    return
                }
            } else {
                Log.warning("[AUTH] UUID lookup returned 0 results for: \(userIdString)")
            }
        } catch {
            Log.error("[AUTH] خطأ في جلب البروفايل بـ UUID: \(error.localizedDescription)")
        }

        // المحاولة 2: البحث بالرقم
        if let phoneProfile = await findProfileByPhone(normalizedSessionPhone) {
            Log.info("[AUTH] Found profile by phone: \(phoneProfile.fullName), profileId: \(phoneProfile.id), authUid: \(user.id)")
            // ربط البروفايل بـ auth.uid الجديد حتى يعمل تسجيل الدخول مستقبلاً بدون بحث
            await linkProfileToAuthUser(oldProfileId: phoneProfile.id, newAuthUserId: user.id)
            // إعادة تحميل البروفايل بالمعرف الجديد
            if let updatedProfile = await loadProfile(by: user.id) {
                await applyAuthenticatedProfile(updatedProfile, normalizedPhone: normalizedSessionPhone)
            } else {
                // fallback: استخدام البروفايل الأصلي
                await applyAuthenticatedProfile(phoneProfile, normalizedPhone: normalizedSessionPhone)
            }
            return
        }

        // المحاولة 3: البحث بالرقم المحلي
        let local8 = KuwaitPhone.localEightDigits(normalizedSessionPhone)
        if local8.count == 8, let directPhoneProfile = await findProfileByPhone(local8) {
            Log.info("[AUTH] Found profile by local phone: \(directPhoneProfile.fullName), profileId: \(directPhoneProfile.id), authUid: \(user.id)")
            await linkProfileToAuthUser(oldProfileId: directPhoneProfile.id, newAuthUserId: user.id)
            if let updatedProfile = await loadProfile(by: user.id) {
                await applyAuthenticatedProfile(updatedProfile, normalizedPhone: local8)
            } else {
                await applyAuthenticatedProfile(directPhoneProfile, normalizedPhone: local8)
            }
            return
        }

        // المحاولة 4: إعادة محاولة بعد تأخير قصير (لحالات التأخر في الشبكة)
        try? await Task.sleep(nanoseconds: 200_000_000)
        do {
            let retryResponse: [FamilyMember] = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userIdString)
                .limit(1)
                .execute()
                .value
            if let retryProfile = retryResponse.first {
                let retryPhone = retryProfile.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                // المدير حذف الرقم → مباشرة للتسجيل
                if retryPhone.isEmpty {
                    Log.info("[AUTH] بروفايل بدون رقم في المحاولة 4 — توجيه مباشر للتسجيل")
                    self.status = .authenticatedNoProfile
                    return
                } else {
                    Log.info("[AUTH] Found profile on retry by UUID: \(retryProfile.fullName)")
                    await applyAuthenticatedProfile(retryProfile, normalizedPhone: normalizedSessionPhone)
                    return
                }
            }
        } catch {
            Log.warning("[AUTH] Retry check failed: \(error.localizedDescription)")
        }

        Log.warning("[AUTH] ⚠️ لم يتم العثور على بروفايل بعد 4 محاولات. Phone: \(Log.masked(normalizedSessionPhone)), UUID: \(userIdString)")
        self.status = .authenticatedNoProfile
    }

    // MARK: - Banned Phones (حظر الأرقام)

    /// فحص هل الرقم محظور — يبحث بالرقم المحلي والدولي
    func isPhoneBanned(_ phone: String) async -> Bool {
        let local = KuwaitPhone.localEightDigits(phone)
        let candidates = Set([phone, local, "+965\(local)"].filter { !$0.isEmpty })

        for candidate in candidates {
            do {
                let result: [BannedPhone] = try await supabase
                    .from("banned_phones")
                    .select()
                    .eq("phone_number", value: candidate)
                    .eq("is_active", value: true)
                    .limit(1)
                    .execute()
                    .value
                if !result.isEmpty {
                    Log.info("[BAN] الرقم محظور: \(candidate)")
                    return true
                }
            } catch {
                // لو الجدول ما موجود بعد — نتجاهل الخطأ ونسمح بالدخول
                Log.warning("[BAN] خطأ في فحص الحظر: \(error.localizedDescription)")
                return false
            }
        }
        return false
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
        let local = KuwaitPhone.localEightDigits(phone)
        let normalizedPhone = local.count >= 6 ? local : phone

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
    
    func signOut() async {
        _ = try? await supabase.auth.signOut()
        withAnimation {
            self.status = .unauthenticated
            self.isAuthenticated = false
            self.currentUser = nil
            self.isOtpSent = false
            self.phoneNumber = ""
        }
        // مسح الرقم المحفوظ
        self.lastAuthPhone = ""
        self.lastAuthDialingCode = ""
        // مسح الكاش المحلي
        CacheManager.shared.clearAll()
        // إيقاف الاشتراكات الحية
        RealtimeManager.shared.unsubscribe()
    }

    // MARK: - حذف الحساب (Account Deletion — Apple Requirement)

    func deleteAccount() async -> Bool {
        self.isLoading = true
        do {
            try await supabase.functions.invoke(
                "delete-account",
                options: FunctionInvokeOptions(body: [:] as [String: String])
            )
            _ = try? await supabase.auth.signOut()
            self.isLoading = false
            withAnimation {
                self.status = .unauthenticated
                self.isAuthenticated = false
                self.currentUser = nil
                self.isOtpSent = false
                self.phoneNumber = ""
            }
            Log.info("تم حذف الحساب بنجاح")
            return true
        } catch {
            self.isLoading = false
            self.deleteAccountError = "تعذر حذف الحساب: \(error.localizedDescription)"
            Log.error("خطأ في حذف الحساب: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Registration
    
    func registerNewUser(firstName: String, familyName: String, birthDate: Date, gender: String, fatherId: UUID? = nil, avatarImage: UIImage? = nil) async {
        self.isLoading = true
        guard let user = try? await supabase.auth.session.user else { return }
        
        let normalizedPhone = user.phone ?? self.phoneNumber
        // تحقق إذا فيه profile كامل (مو فاضي من الترقر) — إذا كامل ما نكمل التسجيل
        if let existingProfile = await findProfileByPhone(normalizedPhone) {
            let name = existingProfile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                await applyAuthenticatedProfile(existingProfile, normalizedPhone: normalizedPhone)
                self.isLoading = false
                return
            }
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        
        let cleanFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFamilyName = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = "\(cleanFirstName) \(cleanFamilyName)"
        
        // بحث تلقائي عن مطابقات في الشجرة بالاسم الكامل أو أجزاء منه
        let matchedMemberIds = await searchForNameMatches(fullName: fullName, firstName: cleanFirstName)

        let profileData: [String: AnyEncodable] = [
            "id": AnyEncodable(user.id),
            "full_name": AnyEncodable(fullName),
            "first_name": AnyEncodable(cleanFirstName),
            "phone_number": AnyEncodable(user.phone ?? toE164(dialingCode: dialingCode, localDigits: phoneNumber)),
            "birth_date": AnyEncodable(formatter.string(from: birthDate)),
            "role": AnyEncodable("pending"),
            "status": AnyEncodable("pending"),
            "father_id": AnyEncodable(fatherId?.uuidString),
            "gender": AnyEncodable(gender.isEmpty ? nil : gender),
            "is_deceased": AnyEncodable(false),
            "is_married": AnyEncodable(false),
            "is_hidden_from_tree": AnyEncodable(true),
            "sort_order": AnyEncodable(0),
            "created_at": AnyEncodable(ISO8601DateFormatter().string(from: Date()))
        ]
        
        do {
            try await supabase
                .from("profiles")
                .upsert(profileData)
                .execute()
            
            // التحقق من نجاح الإنشاء
            let verifyProfile = await loadProfile(by: user.id)
            if let vp = verifyProfile {
                Log.info("[REGISTER] ✅ تم إنشاء البروفايل بنجاح: \(vp.fullName), UUID: \(user.id), role: \(vp.role)")
            } else {
                Log.error("[REGISTER] ⚠️ الـ upsert لم يُنشئ السجل! UUID: \(user.id). قد يكون RLS يمنع الإنشاء.")
            }

            // رفع الصورة الشخصية إذا اختارها المستخدم
            if let avatarImage, let imageData = ImageProcessor.process(avatarImage, for: .avatar) {
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
            
            let joinRequestData: [String: AnyEncodable] = [
                "member_id": AnyEncodable(user.id.uuidString),
                "requester_id": AnyEncodable(user.id.uuidString),
                "request_type": AnyEncodable("link_request"),
                "status": AnyEncodable("pending"),
                "details": AnyEncodable(matchInfo)
            ]
            
            _ = try? await supabase
                .from("admin_requests")
                .insert(joinRequestData)
                .execute()
            
            // إشعار المدير مع عدد المطابقات
            let pushBody: String
            if matchedMemberIds.isEmpty {
                pushBody = "\(cleanFirstName) يطلب الانضمام — لا مطابقات."
            } else {
                pushBody = "\(cleanFirstName) يطلب الانضمام — \(matchedMemberIds.count) مطابقة."
            }
            
            await notifyAdminsWithPush(
                title: "طلب انضمام جديد",
                body: pushBody,
                kind: "link_request"
            )
            
            Log.info("تم تسجيل العضو وإرسال طلب الربط بنجاح")

            // بعد نجاح الـ upsert — نضمن الانتقال لشاشة الانتظار مباشرة
            if let createdProfile = await loadProfile(by: user.id) {
                await applyAuthenticatedProfile(createdProfile, normalizedPhone: KuwaitPhone.localEightDigits(normalizedPhone))
            } else {
                // حتى لو فشل تحميل البروفايل، السجل اتسوى → ننقل لشاشة الانتظار
                self.status = .pendingApproval
            }
            
        } catch {
            Log.error("خطأ في التسجيل: \(error.localizedDescription)")
            // حتى في حالة الخطأ، نعيد محاولة فحص البروفايل بدل البقاء في شاشة التسجيل
            await checkUserProfile()
        }
        self.isLoading = false
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
        let cleanContact = preferredContact?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMessage.isEmpty else {
            Log.warning("[Contact] ⚠️ الرسالة فارغة — تم الإلغاء")
            contactMessageError = "الرسالة فارغة."
            self.isLoading = false
            return false
        }

        let details = """
        التصنيف: \(category)
        الرسالة: \(cleanMessage)
        وسيلة التواصل: \(cleanContact.flatMap { $0.isEmpty ? nil : $0 } ?? "غير محدد")
        """

        do {
            // 1. حفظ في admin_requests
            Log.info("[Contact] 1️⃣ حفظ الطلب في admin_requests...")
            let basePayload: [String: AnyEncodable] = [
                "member_id": AnyEncodable(user.id.uuidString),
                "requester_id": AnyEncodable(user.id.uuidString),
                "request_type": AnyEncodable("contact_message"),
                "status": AnyEncodable("pending"),
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
                if isMissingAdminRequestNewValueColumnError(error) {
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
                "preferred_contact": AnyEncodable(cleanContact),
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
