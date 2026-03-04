import Foundation
import Supabase
import SwiftUI
import Combine
import UserNotifications

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
    private struct NewsPollVoteRecord: Decodable {
        let news_id: UUID
        let member_id: UUID
        let option_index: Int
    }

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
    @Published var otpCode: String = ""
    @Published var isOtpSent: Bool = false
    @Published var isLoading: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: FamilyMember? = nil
    @Published var allMembers: [FamilyMember] = []
    @Published var currentMemberChildren: [FamilyMember] = []
    
    // Fetch throttle timestamps
    private var lastMembersFetchDate: Date?
    private var lastNewsFetchDate: Date?
    private var lastNotificationsFetchDate: Date?
    private var lastDeceasedFetchDate: Date?
    private var lastChildAddFetchDate: Date?
    private var lastPhoneChangeFetchDate: Date?
    private var lastNewsReportFetchDate: Date?
    private var lastPendingNewsFetchDate: Date?
    @Published var status: AuthStatus = .checking // ابدأ دائماً بالفحص 👈
    @Published var deceasedRequests: [AdminRequest] = []
    @Published var childAddRequests: [AdminRequest] = []
    @Published var phoneChangeRequests: [PhoneChangeRequest] = []
    @Published var newsReportRequests: [AdminRequest] = []
    @Published var notifications: [AppNotification] = []
    @Published var allNews: [NewsPost] = [] // 👈 أضف هذا السطر هنا لحل الخطأ فوراً
    @Published var pendingNewsRequests: [NewsPost] = []
    @Published var pollVotesByPost: [UUID: [Int: Int]] = [:]
    @Published var userVoteByPost: [UUID: Int] = [:]
    @Published var activePath: [UUID] = []
    @Published var likedPosts: Set<UUID> = []
    @Published var likesCountByPost: [UUID: Int] = [:]
    @Published var commentsCountByPost: [UUID: Int] = [:]
    @Published var commentsByPost: [UUID: [NewsCommentRecord]] = [:]
    @Published var notificationsFeatureAvailable: Bool = true
    @Published var newsApprovalFeatureAvailable: Bool = true
    @Published var newsPollFeatureAvailable: Bool = true
    @Published var newsPostErrorMessage: String?
    @Published var contactMessageError: String?
    @Published var otpErrorMessage: String?
    @Published var otpStatusMessage: String = ""
    @Published var pushToken: String?
    @Published private(set) var trialStartedAt: Date?
    @Published private(set) var trialEndsAt: Date?
    
    enum AuthStatus {
        case unauthenticated
        case checking
        case authenticatedNoProfile
        case fullyAuthenticated
        case pendingApproval
        case trialExpired
    }

    private let trialDurationDays = 7
    
    var canModerate: Bool {
        currentUser?.role == .admin || currentUser?.role == .supervisor
    }

    
    var canAutoPublishNews: Bool {
        canModerate
    }
    
    var unreadNotificationsCount: Int {
        notifications.filter { !$0.read }.count
    }

    var trialDaysRemaining: Int? {
        guard let trialEndsAt else { return nil }
        let remainingSeconds = trialEndsAt.timeIntervalSinceNow
        if remainingSeconds <= 0 { return 0 }
        return Int(ceil(remainingSeconds / 86_400))
    }

    var hasActiveTrial: Bool {
        guard let trialEndsAt else { return false }
        return Date() < trialEndsAt
    }
    
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
        
        // يدعم أخطاء Postgres 42703 وأخطاء PostgREST schema cache
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

    private func resolveAuthAccess(for profile: FamilyMember) -> (status: AuthStatus, trialStart: Date?, trialEnd: Date?) {
        guard profile.role != .pending else {
            return (.pendingApproval, nil, nil)
        }

        // تم إلغاء نظام انتهاء التجربة: أي مستخدم غير معلق يُسمح له بالدخول مباشرة.
        return (.fullyAuthenticated, nil, nil)
    }
    
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
    
    func registerPushToken(_ token: String) async {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return }

        self.pushToken = cleanToken

        // لا ترسل التوكن للسيرفر إذا الإشعارات مغلقة
        let notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        guard notificationsEnabled else { return }

        guard let memberId = currentUser?.id else { return }
        do {
            let payload: [String: AnyEncodable] = [
                "member_id": AnyEncodable(memberId.uuidString),
                "token": AnyEncodable(cleanToken),
                "platform": AnyEncodable("ios")
            ]

            try await supabase
                .from("device_tokens")
                .upsert(payload, onConflict: "token")
                .execute()
        } catch {
            Log.error("خطأ حفظ Push Token: \(error.localizedDescription)")
        }
    }

    func unregisterPushToken() async {
        guard let memberId = currentUser?.id else { return }
        guard let token = pushToken, !token.isEmpty else { return }
        do {
            try await supabase
                .from("device_tokens")
                .delete()
                .eq("member_id", value: memberId.uuidString)
                .eq("token", value: token)
                .execute()
            Log.info("تم إلغاء تسجيل التوكن للإشعارات")
        } catch {
            Log.error("خطأ إلغاء تسجيل Push Token: \(error.localizedDescription)")
        }
    }
    
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
    
    /// إرسال push حقيقي لأعضاء محددين أو للجميع عبر Edge Function
    private func sendPushToMembers(title: String, body: String, kind: String = "general", targetMemberIds: [UUID]? = nil) async {
        do {
            var payload: [String: AnyEncodable] = [
                "title": AnyEncodable(title),
                "body": AnyEncodable(body),
                "kind": AnyEncodable(kind)
            ]
            if let ids = targetMemberIds, !ids.isEmpty {
                payload["member_ids"] = AnyEncodable(ids.map { $0.uuidString })
            }
            
            try await supabase.functions
                .invoke(
                    "push-notify",
                    options: FunctionInvokeOptions(body: payload)
                )
        } catch {
            Log.warning("تعذر إرسال Push للأعضاء: \(error.localizedDescription)")
        }
    }
    
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

        let maxAttempts = 2
        var lastError: Error?
        
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
                    self.otpStatusMessage = L10n.t("تم إرسال الرمز عبر SMS إلى \(finalPhone)", "Code sent via SMS to \(finalPhone)")
                    self.isLoading = false
                    return
            } catch {
                lastError = error
                let raw = "\(error) \(error.localizedDescription)".lowercased()
                let isRateLimited = raw.contains("429") || raw.contains("rate")
                
                if isRateLimited || attempt == maxAttempts {
                    break
                }
                
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
        
        self.otpStatusMessage = ""
        self.otpErrorMessage = userFacingOTPError(lastError ?? NSError(domain: "otp", code: -1))
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
            
            // بعد نجاح الرمز، نحدث بيانات المستخدم لكي يفتح التطبيق تلقائياً
            await checkUserProfile()
            
        } catch {
            Log.error("فشل التحقق: \(error.localizedDescription)")
            self.otpErrorMessage = L10n.t("الرمز غير صحيح أو منتهي. أعد طلب رمز جديد.", "Invalid or expired code. Please request a new one.")
        }
        
        self.isLoading = false

    }
    
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
        
        let candidates = [
            rawPhone.trimmingCharacters(in: .whitespacesAndNewlines),
            normalized,
            "+965\(normalized)",
            "965\(normalized)",
            "00965\(normalized)",
            "+\(normalized)"
        ]
        
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
                .limit(2000)
                .execute()
                .value
            
            let matchedRows = broad.filter { phonesMatch(stored: $0.phoneNumber, targetRaw: normalized) }
            if let profileId = pickBestProfileId(from: matchedRows) {
                return await loadProfile(by: profileId)
            }

            return nil
        } catch {
            Log.warning("فشل المطابقة الموسعة بالهاتف: \(error)")
            return nil
        }
    }
    
    private func applyAuthenticatedProfile(_ profile: FamilyMember, normalizedPhone: String?) async {
        let access = self.resolveAuthAccess(for: profile)
        self.currentUser = profile
        self.status = access.status
        self.trialStartedAt = access.trialStart
        self.trialEndsAt = access.trialEnd
        if let normalizedPhone, normalizedPhone.count == 8 {
            self.phoneNumber = normalizedPhone
        }
        Task {
            guard access.status != .trialExpired else { return }
            await self.fetchNews(force: true)
            await self.fetchNotifications()
            if self.canModerate {
                await self.fetchPendingNewsRequests()
            }
        }
    }
    
    func checkUserProfile() async {
        guard let user = try? await supabase.auth.session.user else {
            Log.info("[AUTH] No session found → unauthenticated")
            self.status = .unauthenticated
            self.trialStartedAt = nil
            self.trialEndsAt = nil
            return
        }

        let normalizedSessionPhone = user.phone ?? self.phoneNumber
        Log.info("[AUTH] Session found. UUID: \(user.id), Phone: \(normalizedSessionPhone)")

        // المحاولة 1: البحث بـ auth.uid مباشرة
        do {
            let response = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: user.id)
                .execute()

            let members = try JSONDecoder().decode([FamilyMember].self, from: response.data)

            if let profile = members.first {
                Log.info("[AUTH] Found profile by UUID: \(profile.fullName), role: \(profile.role)")
                await applyAuthenticatedProfile(profile, normalizedPhone: normalizedSessionPhone)
                if let token = pushToken { await registerPushToken(token) }
                return
            }
        } catch {
            Log.error("خطأ في جلب البروفايل بـ UUID: \(error.localizedDescription)")
        }

        // المحاولة 2: البحث بالرقم
        if let phoneProfile = await findProfileByPhone(normalizedSessionPhone) {
            Log.info("[AUTH] Found profile by phone: \(phoneProfile.fullName)")
            await applyAuthenticatedProfile(phoneProfile, normalizedPhone: normalizedSessionPhone)
            if let token = pushToken { await registerPushToken(token) }
            return
        }

        // المحاولة 3: البحث بالرقم المحلي
        let local8 = KuwaitPhone.localEightDigits(normalizedSessionPhone)
        if local8.count == 8, let directPhoneProfile = await findProfileByPhone(local8) {
            Log.info("[AUTH] Found profile by local phone: \(directPhoneProfile.fullName)")
            await applyAuthenticatedProfile(directPhoneProfile, normalizedPhone: local8)
            if let token = pushToken { await registerPushToken(token) }
            return
        }

        Log.warning("لم يتم العثور على بروفايل. Phone: \(normalizedSessionPhone), UUID: \(user.id)")
        self.status = .authenticatedNoProfile
        self.trialStartedAt = nil
        self.trialEndsAt = nil
    }
    func signOut() async {
        _ = try? await supabase.auth.signOut()
        withAnimation {
            self.status = .unauthenticated
            self.isAuthenticated = false
            self.currentUser = nil
            self.allMembers = []
            self.isOtpSent = false
            self.phoneNumber = ""
            self.trialStartedAt = nil
            self.trialEndsAt = nil
        }
    }

    // MARK: - حذف الحساب (Account Deletion — Apple Requirement)

    @Published var deleteAccountError: String?

    func deleteAccount() async -> Bool {
        self.isLoading = true

        do {
            // استدعاء Edge Function لحذف الحساب بالكامل
            try await supabase.functions.invoke(
                "delete-account",
                options: FunctionInvokeOptions(body: [:] as [String: String])
            )

            // تسجيل الخروج محلياً
            _ = try? await supabase.auth.signOut()

            self.isLoading = false
            withAnimation {
                self.status = .unauthenticated
                self.isAuthenticated = false
                self.currentUser = nil
                self.allMembers = []
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

    // MARK: - جلب البيانات (Fetch)
    
    func fetchAllMembers(force: Bool = false) async {
        // تجنب إعادة التحميل خلال 15 ثانية إلا إذا force
        if !force, let last = lastMembersFetchDate, Date().timeIntervalSince(last) < 15, !allMembers.isEmpty {
            return
        }
        
        self.activePath = [] // تصفير المسار عند كل تحميل
        
        do {
            let response = try await supabase
                .from("profiles")
                .select()
                .execute()
            
            let members = try JSONDecoder().decode([FamilyMember].self, from: response.data)
            
            self.allMembers = members
            self.lastMembersFetchDate = Date()
        } catch {
            Log.error("خطأ برمجياً في الشجرة: \(error)")
        }
    }
    
    func fetchChildren(for fatherId: UUID) async {
        do {
            let response: [FamilyMember] = try await supabase.from("profiles")
                .select()
                .eq("father_id", value: fatherId)
                .order("sort_order", ascending: true)
                .execute()
                .value
            
            self.currentMemberChildren = response
        } catch {
            Log.error("خطأ في جلب الأبناء: \(error)")
        }
    }
    
    func reorderChildren(_ children: [FamilyMember]) async {
        // تحديث محلي فوري
        currentMemberChildren = children
        
        for (index, child) in children.enumerated() {
            do {
                try await supabase
                    .from("profiles")
                    .update(["sort_order": AnyEncodable(index)])
                    .eq("id", value: child.id.uuidString)
                    .execute()
            } catch {
                Log.error("خطأ تحديث ترتيب الابن: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - إدارة الأعضاء (Member Management)
    
    // MARK: - تسجيل عضو جديد من الإدارة (بدون حساب مصادقة)
    func adminAddMember(
        fullName: String,
        firstName: String,
        birthDate: String?,
        gender: String?,
        phoneNumber: String?
    ) async -> Bool {
        self.isLoading = true
        let newId = UUID()

        let memberData: [String: AnyEncodable] = [
            "id": AnyEncodable(newId.uuidString),
            "full_name": AnyEncodable(fullName),
            "first_name": AnyEncodable(firstName),
            "birth_date": AnyEncodable(birthDate ?? Optional<String>.none),
            "phone_number": AnyEncodable(phoneNumber ?? ""),
            "role": AnyEncodable("member"),
            "status": AnyEncodable("active"),
            "is_deceased": AnyEncodable(false),
            "is_married": AnyEncodable(false),
            "is_hidden_from_tree": AnyEncodable(false),
            "sort_order": AnyEncodable(0),
            "father_id": AnyEncodable(Optional<String>.none)
        ]
        _ = memberData // silence unused warning

        do {
            try await supabase.from("profiles").insert(memberData).execute()
            await fetchAllMembers()
            self.isLoading = false
            return true
        } catch {
            Log.error("فشل إضافة عضو من الإدارة: \(error.localizedDescription)")
            self.isLoading = false
            return false
        }
    }

    // إضافة ابن جديد مع ترتيب تلقائي
    func addChild(
        firstNameOnly: String,
        phoneNumber: String,
        birthDate: String?,
        fatherId: UUID,
        isDeceased: Bool,
        deathDate: String?,
        gender: String?,
        silent: Bool = false
    ) async -> UUID? {
        self.isLoading = true
        
        // 1. دالة داخلية تضمن تحويل أي رقم عربي إلى إنجليزي يدوياً لقطع الشك باليقين ✅
        func cleanNumber(_ input: String) -> String {
            let arabicNumbers = ["٠":"0","١":"1","٢":"2","٣":"3","٤":"4","٥":"5","٦":"6","٧":"7","٨":"8","٩":"9"]
            var temp = input
            for (arabic, english) in arabicNumbers {
                temp = temp.replacingOccurrences(of: arabic, with: english)
            }
            return temp
        }
        
        // 2. تنظيف التواريخ قبل استخدامها
        let cleanedBirthDate = birthDate?.isEmpty == false ? cleanNumber(birthDate!) : nil
        let cleanedDeathDate = deathDate?.isEmpty == false ? cleanNumber(deathDate!) : nil
        
        // 3. البحث عن بيانات الأب لبناء الاسم الكامل
        let father: FamilyMember?
        if let localFather = allMembers.first(where: { $0.id == fatherId }) {
            father = localFather
        } else {
            let remoteFathers: [FamilyMember]? = try? await supabase
                .from("profiles")
                .select()
                .eq("id", value: fatherId.uuidString)
                .limit(1)
                .execute()
                .value
            father = remoteFathers?.first
        }
        
        guard let father else {
            Log.error("لم يتم العثور على بيانات الأب في القائمة أو السيرفر")
            self.isLoading = false
            return nil
        }
        
        let finalFullName = "\(firstNameOnly) \(father.fullName)".trimmingCharacters(in: .whitespaces)
        let newId = UUID()
        
        // 4. بناء المصفوفة بالقيم النظيفة (cleanedBirthDate) ✅
        let storedPhone = KuwaitPhone.normalizeForStorageFromInput(phoneNumber) ?? ""
        var newChild: [String: AnyEncodable] = [
            "id": AnyEncodable(newId.uuidString),
            "full_name": AnyEncodable(finalFullName),
            "first_name": AnyEncodable(firstNameOnly),
            "father_id": AnyEncodable(fatherId.uuidString),
            "birth_date": AnyEncodable(cleanedBirthDate ?? Optional<String>.none),
            "role": AnyEncodable("member"),
            "phone_number": AnyEncodable(storedPhone),
            "is_deceased": AnyEncodable(isDeceased),
            "is_married": AnyEncodable(false),
            "sort_order": AnyEncodable(allMembers.filter { $0.fatherId == fatherId }.count),
            "status": AnyEncodable("active")
        ]
        
        // إلحاق الجنس إذا كان محدداً
        if let gender, !gender.isEmpty {
            newChild["gender"] = AnyEncodable(gender)
        }
        
        // إلحاق تاريخ الوفاة إذا كان الشخص متوفى
        if isDeceased, let dDate = cleanedDeathDate {
            newChild["death_date"] = AnyEncodable(dDate)
        }
        
        do {
            try await supabase.from("profiles").insert(newChild).execute()
            
            // إضافة فورية للقائمة المحلية لتحديث الواجهة بدون انتظار
            let optimisticChild = FamilyMember(
                id: newId,
                firstName: firstNameOnly,
                fullName: finalFullName,
                phoneNumber: storedPhone,
                birthDate: cleanedBirthDate,
                deathDate: isDeceased ? cleanedDeathDate : nil,
                isDeceased: isDeceased,
                role: .member,
                fatherId: fatherId,
                photoURL: nil,
                isPhoneHidden: false,
                isHiddenFromTree: false,
                sortOrder: allMembers.filter { $0.fatherId == fatherId }.count,
                bio: nil,
                status: .active,
                avatarUrl: nil,
                isMarried: false,
                gender: gender,
                createdAt: nil
            )
            self.allMembers.append(optimisticChild)
            
            // تسجيل طلب إداري + إشعار فقط إذا الإضافة من حسابي (وليس من تعديل المدير)
            if !silent {
                let requester = currentUser?.id ?? fatherId
                let details = "تمت إضافة ابن جديد: \(firstNameOnly) (\(isDeceased ? "متوفى" : "حي"))."
                let requestData: [String: AnyEncodable] = [
                    "member_id": AnyEncodable(fatherId.uuidString),
                    "requester_id": AnyEncodable(requester.uuidString),
                    "request_type": AnyEncodable("child_add"),
                    "new_value": AnyEncodable(newId.uuidString),
                    "status": AnyEncodable("pending"),
                    "details": AnyEncodable(details)
                ]
                do {
                    try await supabase
                        .from("admin_requests")
                        .insert(requestData)
                        .execute()
                    
                    let requesterName = currentUser?.firstName ?? "عضو"
                    let childAddBody = "تمت إضافة ابن جديد: \(firstNameOnly)\nالأب: \(father.firstName)\nبواسطة: \(requesterName)"
                    await notifyAdminsWithPush(
                        title: "إضافة ابن جديد",
                        body: childAddBody,
                        kind: "child_add"
                    )
                } catch {
                    Log.warning("لم يتم إدراج طلب child_add في admin_requests: \(error.localizedDescription)")
                }
            }
            
            // تحديث البيانات فوراً
            await fetchAllMembers()
            await fetchChildren(for: fatherId)
            
            Log.info("تمت إضافة الابن بنجاح")
            self.isLoading = false
            return newId
        } catch {
            Log.error("خطأ إضافة الابن: \(error)")
            Log.error("تفاصيل: name=\(firstNameOnly), fatherId=\(fatherId), birthDate=\(cleanedBirthDate ?? "nil")")
        }
        self.isLoading = false
        return nil
    }
    
    // MARK: - Helper for Storage Paths
    private func getSafeMemberName(for memberId: UUID) -> String {
        return memberId.uuidString
    }
    
    // رفع صورة العضو
    func uploadAvatar(image: UIImage, for memberId: UUID) async {
        self.isLoading = true
        
        // 1. ضغط الصورة وتحويلها لبيانات
        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
            self.isLoading = false
            return
        }
        
        let safeName = getSafeMemberName(for: memberId)
        let fileName = "\(safeName).jpg"
        
        do {
            // 2. الرفع إلى السيرفر
            try await supabase.storage
                .from("avatars")
                .upload(
                    fileName,
                    data: imageData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
            
            // 3. الحصول على الرابط العام (تم تصحيح المسمى إلى getPublicURL) ✅
            // إذا استمر الخطأ، سنستخدم الطريقة اليدوية أدناه
            let publicUrl = try supabase.storage
                .from("avatars")
                .getPublicURL(path: fileName) // لاحظ أحرف URL الكبيرة
            
            let urlString = publicUrl.absoluteString
            
            // 4. تحديث رابط الصورة في جدول profiles
            try await supabase
                .from("profiles")
                .update(["avatar_url": AnyEncodable(urlString)])
                .eq("id", value: memberId.uuidString)
                .execute()
            
            // 5. تحديث البيانات محلياً فوراً
            await fetchAllMembers()
            if memberId == currentUser?.id {
                await checkUserProfile()
            }
            
            Log.info("تم رفع الصورة بنجاح: \(urlString)")
            
        } catch {
            Log.error("خطأ في الرفع أو الرابط: \(error.localizedDescription)")
            
            // طريقة بديلة (Manual Fallback) في حال فشل الحصول على الرابط من المكتبة:
            // الرابط الدائم في سوبابيس يكون بهذا الشكل:
            // https://[PROJECT_ID].supabase.co/storage/v1/object/public/avatars/[FILE_NAME]
        }
        self.isLoading = false
    }
    
    func deleteAvatar(for memberId: UUID) async {
        self.isLoading = true
        do {
            // حذف الملف من التخزين إذا كان موجوداً
            let cachedAvatarURL =
                allMembers.first(where: { $0.id == memberId })?.avatarUrl ??
                (currentUser?.id == memberId ? currentUser?.avatarUrl : nil)
            
            let safeName = getSafeMemberName(for: memberId)
            var candidatePaths: [String] = ["\(memberId.uuidString).jpg", "\(safeName).jpg"]
            if let cachedAvatarURL,
               let parsedPath = storagePath(fromPublicURL: cachedAvatarURL, bucket: "avatars"),
               !parsedPath.isEmpty,
               !candidatePaths.contains(parsedPath) {
                candidatePaths.append(parsedPath)
            }
            
            _ = try? await supabase.storage
                .from("avatars")
                .remove(paths: candidatePaths)
            
            // 1. إرسال قيمة فارغة (Optional.none) لتمثيل الـ NULL في قاعدة البيانات ✅
            let updateData: [String: AnyEncodable] = [
                "avatar_url": AnyEncodable(Optional<String>.none)
            ]
            
            try await supabase
                .from("profiles")
                .update(updateData)
                .eq("id", value: memberId.uuidString)
                .execute()
            
            // 2. تحديث البيانات محلياً
            await fetchAllMembers()
            if memberId == currentUser?.id {
                await checkUserProfile()
            }
            
            Log.info("تم حذف رابط الصورة بنجاح")
            
        } catch {
            Log.error("خطأ في حذف الصورة: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
    
    // MARK: - صورة الغلاف (Cover) منفصلة عن الصورة الشخصية (Avatar)
    
    func uploadCover(image: UIImage, for memberId: UUID) async {
        self.isLoading = true
        
        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
            self.isLoading = false
            return
        }
        
        let safeName = getSafeMemberName(for: memberId)
        let fileName = "cover_\(safeName).jpg"
        
        do {
            try await supabase.storage
                .from("avatars")
                .upload(
                    fileName,
                    data: imageData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
            
            let publicUrl = try supabase.storage
                .from("avatars")
                .getPublicURL(path: fileName)
            
            let urlString = publicUrl.absoluteString
            
            try await supabase
                .from("profiles")
                .update(["cover_url": AnyEncodable(urlString)])
                .eq("id", value: memberId.uuidString)
                .execute()
            
            await fetchAllMembers()
            if memberId == currentUser?.id {
                await checkUserProfile()
            }
            
            Log.info("تم رفع صورة الغلاف بنجاح: \(urlString)")
            
        } catch {
            Log.error("خطأ في رفع صورة الغلاف: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
    
    func deleteCover(for memberId: UUID) async {
        self.isLoading = true
        do {
            let cachedCoverURL =
                allMembers.first(where: { $0.id == memberId })?.coverUrl ??
                (currentUser?.id == memberId ? currentUser?.coverUrl : nil)
            
            let safeName = getSafeMemberName(for: memberId)
            var candidatePaths: [String] = ["cover_\(safeName).jpg"]
            if let cachedCoverURL,
               let parsedPath = storagePath(fromPublicURL: cachedCoverURL, bucket: "avatars"),
               !parsedPath.isEmpty,
               !candidatePaths.contains(parsedPath) {
                candidatePaths.append(parsedPath)
            }
            
            _ = try? await supabase.storage
                .from("avatars")
                .remove(paths: candidatePaths)
            
            let updateData: [String: AnyEncodable] = [
                "cover_url": AnyEncodable(Optional<String>.none)
            ]
            
            try await supabase
                .from("profiles")
                .update(updateData)
                .eq("id", value: memberId.uuidString)
                .execute()
            
            await fetchAllMembers()
            if memberId == currentUser?.id {
                await checkUserProfile()
            }
            
            Log.info("تم حذف صورة الغلاف بنجاح")
            
        } catch {
            Log.error("خطأ في حذف صورة الغلاف: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
    
    // MARK: - صورة المعرض في تفاصيل العضو (منفصلة عن صورة البروفايل)
    
    func uploadMemberGalleryPhoto(image: UIImage, for memberId: UUID) async -> String? {
        self.isLoading = true
        
        guard let imageData = image.jpegData(compressionQuality: 0.55) else {
            self.isLoading = false
            return nil
        }
        
        let safeName = getSafeMemberName(for: memberId)
        let filePath = "member_photos/\(safeName).jpg"
        
        do {
            try await supabase.storage
                .from("gallery")
                .upload(
                    filePath,
                    data: imageData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
            
            let publicURL = try supabase.storage
                .from("gallery")
                .getPublicURL(path: filePath)
                .absoluteString
            
            try await supabase
                .from("profiles")
                .update(["photo_url": AnyEncodable(publicURL)])
                .eq("id", value: memberId.uuidString)
                .execute()
            
            await fetchAllMembers()
            if memberId == currentUser?.id {
                await checkUserProfile()
            }
            
            self.isLoading = false
            return publicURL
        } catch {
            Log.error("خطأ رفع صورة المعرض: \(error.localizedDescription)")
            self.isLoading = false
            return nil
        }
    }
    
    func deleteMemberGalleryPhoto(for memberId: UUID) async -> Bool {
        self.isLoading = true
        let safeName = getSafeMemberName(for: memberId)
        
        let photoURL = allMembers.first(where: { $0.id == memberId })?.photoURL ?? (currentUser?.id == memberId ? currentUser?.photoURL : nil)
        var pathsToRemove: [String] = ["member_photos/\(memberId.uuidString).jpg", "member_photos/\(safeName).jpg"]
        
        if let photoURL, let parsedPath = storagePath(fromPublicURL: photoURL, bucket: "gallery"), !pathsToRemove.contains(parsedPath) {
            pathsToRemove.append(parsedPath)
        }
        
        do {
            _ = try? await supabase.storage
                .from("gallery")
                .remove(paths: pathsToRemove)
            
            try await supabase
                .from("profiles")
                .update(["photo_url": AnyEncodable(Optional<String>.none)])
                .eq("id", value: memberId.uuidString)
                .execute()
            
            await fetchAllMembers()
            if memberId == currentUser?.id {
                await checkUserProfile()
            }
            
            self.isLoading = false
            return true
        } catch {
            Log.error("خطأ حذف صورة المعرض: \(error.localizedDescription)")
            self.isLoading = false
            return false
        }
    }
    
    func fetchMemberGalleryPhotos(for memberId: UUID) async -> [MemberGalleryPhoto] {
        do {
            let photos: [MemberGalleryPhoto] = try await supabase
                .from("member_gallery_photos")
                .select()
                .eq("member_id", value: memberId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            return photos
        } catch {
            Log.error("خطأ جلب صور المعرض: \(error.localizedDescription)")
            return []
        }
    }
    
    func fetchAllGalleryPhotos() async -> [MemberGalleryPhoto] {
        do {
            let photos: [MemberGalleryPhoto] = try await supabase
                .from("member_gallery_photos")
                .select()
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            return photos
        } catch {
            Log.error("خطأ جلب كل صور المعرض: \(error.localizedDescription)")
            return []
        }
    }
    
    func uploadMemberGalleryPhotoMulti(image: UIImage, for memberId: UUID) async -> MemberGalleryPhoto? {
        self.isLoading = true
        
        guard let imageData = image.jpegData(compressionQuality: 0.6) else {
            self.isLoading = false
            return nil
        }
        
        let photoId = UUID()
        let safeName = getSafeMemberName(for: memberId)
        let filePath = "member_gallery/\(safeName)/\(photoId.uuidString).jpg"
        
        do {
            try await supabase.storage
                .from("gallery")
                .upload(
                    filePath,
                    data: imageData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
            
            let publicURL = try supabase.storage
                .from("gallery")
                .getPublicURL(path: filePath)
                .absoluteString
            
            let payload: [String: AnyEncodable] = [
                "id": AnyEncodable(photoId.uuidString),
                "member_id": AnyEncodable(memberId.uuidString),
                "photo_url": AnyEncodable(publicURL),
                "created_by": AnyEncodable(currentUser?.id.uuidString)
            ]
            
            let inserted: [MemberGalleryPhoto] = try await supabase
                .from("member_gallery_photos")
                .insert(payload)
                .select()
                .execute()
                .value
            
            let galleryMemberName = currentUser?.firstName ?? "عضو"
            let galleryBody = "قام \(galleryMemberName) بإضافة صورة جديدة في معرض الصور."
            if currentUser?.role == .member {
                await notifyAdminsWithPush(
                    title: "إضافة صورة جديدة",
                    body: galleryBody,
                    kind: "gallery_add"
                )
            } else {
                await notifyAdmins(
                    title: "إضافة صورة جديدة",
                    body: galleryBody,
                    kind: "gallery_add"
                )
            }
            
            self.isLoading = false
            return inserted.first
        } catch {
            Log.error("خطأ رفع صورة المعرض المتعدد: \(error.localizedDescription)")
            self.isLoading = false
            return nil
        }
    }
    
    func deleteMemberGalleryPhotoMulti(photoId: UUID, photoURL: String) async -> Bool {
        self.isLoading = true
        Log.info("بدء حذف صورة المعرض: id=\(photoId), url=\(photoURL)")
        
        do {
            if let path = storagePath(fromPublicURL: photoURL, bucket: "gallery") {
                Log.info("حذف من التخزين: \(path)")
                _ = try? await supabase.storage
                    .from("gallery")
                    .remove(paths: [path])
            } else {
                Log.warning("لم يتم العثور على مسار التخزين للصورة")
            }
            
            try await supabase
                .from("member_gallery_photos")
                .delete()
                .eq("id", value: photoId.uuidString)
                .execute()
            
            Log.info("تم حذف سجل الصورة من قاعدة البيانات")
            self.isLoading = false
            return true
        } catch {
            Log.error("خطأ حذف صورة المعرض المتعدد: \(error)")
            self.isLoading = false
            return false
        }
    }
    
    private func storagePath(fromPublicURL urlString: String, bucket: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let marker = "/storage/v1/object/public/\(bucket)/"
        guard let range = url.path.range(of: marker) else { return nil }
        return String(url.path[range.upperBound...])
    }
    
    // MARK: - وظائف لوحة الإدارة (Admin Actions) ✅
    
    /// تفعيل حساب عضو (تغيير status إلى active)
    func activateAccount(memberId: UUID) async {
        guard canModerate else { return }
        do {
            try await supabase
                .from("profiles")
                .update(["status": AnyEncodable("active")])
                .eq("id", value: memberId.uuidString)
                .execute()
            
            if let index = allMembers.firstIndex(where: { $0.id == memberId }) {
                allMembers[index].status = .active
                objectWillChange.send()
            }
            
            let memberName = getSafeMemberName(for: memberId)
            await notifyAdmins(
                title: "تفعيل حساب",
                body: "تم تفعيل حساب \(memberName).",
                kind: "admin"
            )
        } catch {
            Log.error("فشل تفعيل الحساب: \(error.localizedDescription)")
        }
    }
    
    /// قبول عضو جديد وتفعيل حسابه مع ربط الأب
    func approveMember(memberId: UUID, fatherId: UUID?) async {
        self.isLoading = true
        let fatherName = fatherId.flatMap { id in
            allMembers.first(where: { $0.id == id })?.fullName
        }
        do {
            let payload: [String: AnyEncodable] = [
                "role": AnyEncodable("member"),
                "status": AnyEncodable("active"),
                "father_id": AnyEncodable(fatherId?.uuidString),
                "is_hidden_from_tree": AnyEncodable(false)
            ]
            
            try await supabase
                .from("profiles")
                .update(payload)
                .eq("id", value: memberId.uuidString)
                .execute()
            
            // تحديث أي طلب ربط/انضمام معلق لهذا العضو إلى approved
            _ = try? await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("approved")])
                .eq("member_id", value: memberId.uuidString)
                .in("request_type", values: ["join_request", "link_request"])
                .eq("status", value: "pending")
                .execute()
            
            if let index = allMembers.firstIndex(where: { $0.id == memberId }) {
                allMembers[index].role = .member
                allMembers[index].status = .active
                allMembers[index].fatherId = fatherId
                allMembers[index].isHiddenFromTree = false
                objectWillChange.send()
            }

            await notifyJoinApproval(memberId: memberId, fatherName: fatherName)
            
            Log.info("تم قبول العضو بنجاح")
        } catch {
            Log.error("فشل القبول: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
    
    private func notifyJoinApproval(memberId: UUID, fatherName: String?) async {
        guard notificationsFeatureAvailable else { return }
        guard let creator = currentUser?.id else { return }
        
        let body: String
        if let fatherName, !fatherName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body = "تم قبول طلب انضمامك وربطك مع: \(fatherName)."
        } else {
            body = "تم قبول طلب انضمامك بنجاح."
        }
        
        let title = "تم اعتماد العضوية"
        
        let payload: [String: AnyEncodable] = [
            "target_member_id": AnyEncodable(memberId.uuidString),
            "title": AnyEncodable(title),
            "body": AnyEncodable(body),
            "kind": AnyEncodable("join_approved"),
            "created_by": AnyEncodable(creator.uuidString)
        ]
        
        do {
            try await supabase.from("notifications").insert(payload).execute()
            // إرسال push حقيقي للعضو
            await sendPushToMembers(title: title, body: body, kind: "join_approved", targetMemberIds: [memberId])
            // إشعار المدراء والمشرفين بانضمام عضو جديد
            let memberName = getSafeMemberName(for: memberId)
            await notifyAdmins(
                title: "انضمام عضو جديد",
                body: "تم انضمام \(memberName) للعائلة.",
                kind: "join_approved"
            )
        } catch {
            if isMissingNotificationsTableError(error) {
                notificationsFeatureAvailable = false
            } else {
                Log.error("خطأ إرسال إشعار اعتماد الانضمام: \(error.localizedDescription)")
            }
        }
    }
    /// جلب معرفات الأعضاء المتطابقين من طلب الربط
    func fetchMatchedMemberIds(for memberId: UUID) async -> [UUID] {
        do {
            struct AdminRequest: Decodable {
                let details: String?
            }
            let results: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("details")
                .eq("member_id", value: memberId.uuidString)
                .eq("request_type", value: "link_request")
                .eq("status", value: "pending")
                .limit(1)
                .execute()
                .value
            
            guard let details = results.first?.details,
                  let range = details.range(of: "matched_ids:") else {
                return []
            }
            
            let idsString = String(details[range.upperBound...])
            return idsString
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) }
        } catch {
            Log.warning("فشل جلب بيانات المطابقة: \(error.localizedDescription)")
            return []
        }
    }

    /// رفض طلب انضمام أو حذف عضو نهائياً
    func rejectOrDeleteMember(memberId: UUID) async {
        guard currentUser?.role == .admin else {
            Log.error("تم رفض حذف السجل: الصلاحية للمدير فقط")
            return
        }
        do {
            // 1) فك ارتباط الأبناء بهذا العضو قبل الحذف (تجنب قيود father_id)
            _ = try? await supabase
                .from("profiles")
                .update(["father_id": AnyEncodable(Optional<String>.none)])
                .eq("father_id", value: memberId.uuidString)
                .execute()
            
            // 2) تنظيف أي طلبات مرتبطة بهذا العضو (تجنب FK على admin_requests)
            _ = try? await supabase
                .from("admin_requests")
                .delete()
                .eq("member_id", value: memberId.uuidString)
                .execute()
            
            _ = try? await supabase
                .from("admin_requests")
                .delete()
                .eq("requester_id", value: memberId.uuidString)
                .execute()
            
            // 3) الحذف من profiles
            try await supabase
                .from("profiles")
                .delete()
                .eq("id", value: memberId.uuidString)
                .execute()
            
            // 4) التحديث المحلي الفوري لضمان اختفائه من الواجهة فوراً
            let deletedName = allMembers.first(where: { $0.id == memberId })?.firstName ?? "عضو"
            allMembers.removeAll(where: { $0.id == memberId })
            currentMemberChildren.removeAll(where: { $0.id == memberId })
            objectWillChange.send()
            
            await notifyAdmins(
                title: "حذف عضو",
                body: "تم حذف \(deletedName) من الشجرة.",
                kind: "admin"
            )
            
            Log.info("تم حذف العضو مع تنظيف المراجع المرتبطة بنجاح")
            
        } catch {
            Log.error("خطأ في الحذف: \(error.localizedDescription)")
        }
    }
    // تحديث بيانات فرد (سواء الملف الشخصي الحالي أو بيانات الأبناء) ✅
    func updateMemberData(
        memberId: UUID,
        fullName: String,
        phoneNumber: String,
        birthDate: Date,
        isMarried: Bool,
        isDeceased: Bool,
        deathDate: Date?,
        isPhoneHidden: Bool
    ) async {
        self.isLoading = true
        
        // استخراج الاسم الأول تلقائياً
        let firstName = fullName.components(separatedBy: " ").first ?? fullName
        
        // إعداد منسق التاريخ (Locale لضمان أرقام إنجليزية)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        // 2. تجهيز مصفوفة البيانات وإضافة حقل الهاتف ✅
        let normalizedPhone = KuwaitPhone.normalizeForStorageFromInput(phoneNumber) ?? ""
        var updateData: [String: AnyEncodable] = [
            "full_name": AnyEncodable(fullName),
            "first_name": AnyEncodable(firstName),
            "phone_number": AnyEncodable(normalizedPhone),
            "birth_date": AnyEncodable(formatter.string(from: birthDate)),
            "is_married": AnyEncodable(isMarried),
            "is_deceased": AnyEncodable(isDeceased),
            "is_phone_hidden": AnyEncodable(isPhoneHidden)
        ]
        
        if isDeceased, let dDate = deathDate {
            updateData["death_date"] = AnyEncodable(formatter.string(from: dDate))
        }
        
        do {
            // 3. تنفيذ التحديث في Supabase
            try await supabase
                .from("profiles")
                .update(updateData)
                .eq("id", value: memberId.uuidString)
                .execute()
            
            // 4. تحديث البيانات محلياً
            await fetchAllMembers()
            
            // إذا كان المستخدم يحدّث ملفه الشخصي "هو"
            if memberId == currentUser?.id {
                await checkUserProfile()
            }
            
            Log.info("تم تحديث بيانات: \(fullName) بنجاح")
            
        } catch {
            Log.error("خطأ في التحديث: \(error.localizedDescription)")
        }
        self.isLoading = false
    }

    /// تحديث السيرة الذاتية (bio_json)
    func updateMemberBio(memberId: UUID, bio: [FamilyMember.BioStation]) async {
        do {
            try await supabase
                .from("profiles")
                .update(["bio_json": AnyEncodable(bio)])
                .eq("id", value: memberId.uuidString)
                .execute()

            await fetchAllMembers()
            if memberId == currentUser?.id {
                await checkUserProfile()
            }
            Log.info("تم تحديث السيرة الذاتية بنجاح")
        } catch {
            Log.error("خطأ في تحديث السيرة: \(error.localizedDescription)")
        }
    }

    /// تحديث إخفاء رقم الهاتف فقط
    @discardableResult
    func updatePhoneHidden(_ isHidden: Bool) async -> Bool {
        guard let userId = currentUser?.id else { return false }
        do {
            try await supabase
                .from("profiles")
                .update(["is_phone_hidden": AnyEncodable(isHidden)])
                .eq("id", value: userId.uuidString)
                .execute()
            await fetchAllMembers()
            if let updated = allMembers.first(where: { $0.id == userId }) {
                self.currentUser = updated
            }
            return true
        } catch {
            Log.error("خطأ تحديث إخفاء الرقم: \(error.localizedDescription)")
            return false
        }
    }

    /// تحديث إخفاء تاريخ الميلاد
    @discardableResult
    func updateBirthDateHidden(_ isHidden: Bool) async -> Bool {
        guard let userId = currentUser?.id else { return false }
        do {
            try await supabase
                .from("profiles")
                .update(["is_birth_date_hidden": AnyEncodable(isHidden)])
                .eq("id", value: userId.uuidString)
                .execute()
            await fetchAllMembers()
            if let updated = allMembers.first(where: { $0.id == userId }) {
                self.currentUser = updated
            }
            return true
        } catch {
            Log.error("خطأ تحديث إخفاء تاريخ الميلاد: \(error.localizedDescription)")
            return false
        }
    }

    func updateBadgeEnabled(_ isEnabled: Bool) async {
        guard let userId = currentUser?.id else { return }
        do {
            try await supabase
                .from("profiles")
                .update(["badge_enabled": AnyEncodable(isEnabled)])
                .eq("id", value: userId.uuidString)
                .execute()
            await fetchAllMembers()
            if let updated = allMembers.first(where: { $0.id == userId }) {
                self.currentUser = updated
            }
        } catch {
            Log.error("خطأ تحديث إعداد شارة الإشعارات: \(error.localizedDescription)")
        }
    }

    // تحديث ترتيب الأبناء بالسحب والإفلات
    func moveChild(from source: IndexSet, to destination: Int) {
        currentMemberChildren.move(fromOffsets: source, toOffset: destination)
        Task {
            for (index, child) in currentMemberChildren.enumerated() {
                _ = try? await supabase
                    .from("profiles")
                    .update(["sort_order": AnyEncodable(index)])
                    .eq("id", value: child.id.uuidString)
                    .execute()
                
                if let idx = allMembers.firstIndex(where: { $0.id == child.id }) {
                    allMembers[idx].sortOrder = index
                }
            }
            objectWillChange.send()
        }
    }
    
    // MARK: - Helper Struct
    // داخل AuthViewModel.swift
    
    func registerNewUser(firstName: String, familyName: String, birthDate: Date, gender: String, fatherId: UUID? = nil) async {
        self.isLoading = true
        guard let user = try? await supabase.auth.session.user else { return }
        
        let normalizedPhone = user.phone ?? self.phoneNumber
        if let existingProfile = await findProfileByPhone(normalizedPhone) {
            await applyAuthenticatedProfile(existingProfile, normalizedPhone: normalizedPhone)
            self.isLoading = false
            return
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
                pushBody = "طلب ربط جديد من \(cleanFirstName) — لا توجد مطابقات بالشجرة."
            } else {
                pushBody = "طلب ربط جديد من \(cleanFirstName) — \(matchedMemberIds.count) مطابقة محتملة."
            }
            
            await notifyAdminsWithPush(
                title: "طلب ربط عضو جديد",
                body: pushBody,
                kind: "link_request"
            )
            
            Log.info("تم تسجيل العضو وإرسال طلب الربط بنجاح")

            if let createdProfile = await loadProfile(by: user.id) {
                await applyAuthenticatedProfile(createdProfile, normalizedPhone: KuwaitPhone.localEightDigits(normalizedPhone))
            } else {
                self.status = .pendingApproval
            }
            
        } catch {
            Log.error("خطأ في التسجيل: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
    
    /// بحث عن مطابقات الاسم في الشجرة — يُرجع قائمة بمعرفات الأعضاء المتطابقين
    private func searchForNameMatches(fullName: String, firstName: String) async -> [String] {
        do {
            // بحث بالاسم الكامل (تطابق جزئي)
            let fullNameResults: [FamilyMember] = try await supabase
                .from("profiles")
                .select()
                .ilike("full_name", pattern: "%\(fullName)%")
                .neq("status", value: "pending")
                .limit(10)
                .execute()
                .value
            
            if !fullNameResults.isEmpty {
                return fullNameResults.map { $0.id.uuidString }
            }
            
            // بحث بالاسم الأول فقط كـ fallback
            let parts = fullName.split(whereSeparator: \.isWhitespace).map(String.init)
            if parts.count >= 2 {
                let firstTwo = "\(parts[0]) \(parts[1])"
                let partialResults: [FamilyMember] = try await supabase
                    .from("profiles")
                    .select()
                    .ilike("full_name", pattern: "%\(firstTwo)%")
                    .neq("status", value: "pending")
                    .limit(10)
                    .execute()
                    .value
                return partialResults.map { $0.id.uuidString }
            }
            
            return []
        } catch {
            Log.warning("فشل البحث عن مطابقات الاسم: \(error.localizedDescription)")
            return []
        }
    }
    // MARK: - وظائف الإدارة
    func updateMemberName(memberId: UUID, fullName: String) async {
        self.isLoading = true
        let firstName = fullName.components(separatedBy: " ").first ?? fullName
        
        do {
            try await supabase
                .from("profiles")
                .update([
                    "full_name": AnyEncodable(fullName),
                    "first_name": AnyEncodable(firstName)
                ])
                .eq("id", value: memberId.uuidString)
                .execute()
                
            await fetchAllMembers()
            Log.info("تم تحديث اسم العضو بنجاح")
        } catch {
            Log.error("فشل تحديث اسم العضو: \(error.localizedDescription)")
        }
        
        self.isLoading = false
    }
    
    // هذه الدالة لتحديث رتبة العضو (مدير، مشرف، عضو)
    func updateMemberRole(memberId: UUID, newRole: FamilyMember.UserRole) async {
        guard currentUser?.role == .admin else {
            Log.error("تم رفض تحديث الرتبة: الصلاحية للمدير فقط")
            return
        }
        
        // تجاهل إذا الرتبة نفسها لم تتغير
        let currentRole = allMembers.first(where: { $0.id == memberId })?.role
        guard currentRole != newRole else {
            Log.info("الرتبة لم تتغير، تم التجاهل")
            return
        }
        
        self.isLoading = true
        
        do {
            // 1. تحديث حقل role في قاعدة البيانات
            try await supabase
                .from("profiles")
                .update(["role": AnyEncodable(newRole.rawValue)])
                .eq("id", value: memberId.uuidString)
                .execute()
            
            // 2. تحديث البيانات محلياً لكي تظهر التغييرات فوراً في الشجرة
            await fetchAllMembers()
            
            let memberName = allMembers.first(where: { $0.id == memberId })?.firstName ?? "عضو"
            let roleName = newRole == .admin ? "مدير" : (newRole == .supervisor ? "مشرف" : "عضو")
            
            // 3. إشعار المدراء بتغيير الرتبة (push + داخلي)
            await notifyAdminsWithPush(
                title: L10n.t("تغيير رتبة", "Role Changed"),
                body: L10n.t(
                    "تم تغيير رتبة \(memberName) إلى \(roleName).",
                    "\(memberName)'s role changed to \(roleName)."
                ),
                kind: "role_change"
            )
            
            // 4. إشعار العضو نفسه بتغيير رتبته
            if notificationsFeatureAvailable {
                let personalPayload: [String: AnyEncodable] = [
                    "target_member_id": AnyEncodable(memberId.uuidString),
                    "title": AnyEncodable(L10n.t("تغيير رتبتك", "Your Role Changed")),
                    "body": AnyEncodable(L10n.t(
                        "تم تغيير رتبتك إلى: \(roleName).",
                        "Your role has been changed to: \(roleName)."
                    )),
                    "kind": AnyEncodable("role_change"),
                    "created_by": AnyEncodable(currentUser?.id.uuidString)
                ]
                do {
                    try await supabase.from("notifications").insert(personalPayload).execute()
                    await sendPushToMembers(
                        title: L10n.t("تغيير رتبتك", "Your Role Changed"),
                        body: L10n.t(
                            "تم تغيير رتبتك إلى: \(roleName).",
                            "Your role has been changed to: \(roleName)."
                        ),
                        kind: "role_change",
                        targetMemberIds: [memberId]
                    )
                } catch {
                    Log.warning("تعذر إرسال إشعار تغيير الرتبة للعضو: \(error.localizedDescription)")
                }
            }
            
            Log.info("تم تحديث رتبة العضو بنجاح إلى: \(newRole.rawValue)")
            
        } catch {
            Log.error("فشل تحديث الرتبة: \(error.localizedDescription)")
        }
        
        self.isLoading = false
    }
    // دالة لتحديث ترتيب الأبناء في السيرفر
    // دالة لتحديث ترتيب الأبناء بناءً على القائمة الجديدة
    func updateChildrenOrder(for fatherId: UUID, newOrder: [FamilyMember]) async {
        self.isLoading = true
        
        // 1) تحديث الترتيب في الذاكرة مباشرة لظهور أسرع
        for (index, child) in newOrder.enumerated() {
            if let allIdx = self.allMembers.firstIndex(where: { $0.id == child.id }) {
                self.allMembers[allIdx].sortOrder = index
            }
        }
        if fatherId == self.currentUser?.id {
            self.currentMemberChildren = newOrder.enumerated().map { idx, child in
                var mutable = child
                mutable.sortOrder = idx
                return mutable
            }
        }
        self.objectWillChange.send()
        
        // 2) تحديث sort_order فعلياً في Supabase
        for (index, child) in newOrder.enumerated() {
            do {
                try await supabase
                    .from("profiles")
                    .update(["sort_order": AnyEncodable(index)])
                    .eq("id", value: child.id.uuidString)
                    .execute()
            } catch {
                Log.error("فشل تحديث ترتيب \(child.firstName) إلى \(index): \(error)")
            }
        }
        
        // 3) مزامنة نهائية مع الشجرة بعد الحفظ
        await fetchAllMembers()
        if fatherId == self.currentUser?.id {
            await fetchChildren(for: fatherId)
        }
        self.isLoading = false
    }
    func requestDeceasedStatus(memberId: UUID, deathDate: Date?) async {
        self.isLoading = true
        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dateString = deathDate != nil ? formatter.string(from: deathDate!) : "غير محدد"
            
            let requestData: [String: AnyEncodable] = [
                "member_id": AnyEncodable(memberId.uuidString),
                "requester_id": AnyEncodable(currentUser?.id.uuidString ?? ""),
                "request_type": AnyEncodable("deceased_report"),
                "status": AnyEncodable("pending"),
                "details": AnyEncodable("طلب تأكيد وفاة بتاريخ: \(dateString)")
            ]
            
            // إرسال الطلب لجدول الإدارة ✅
            try await supabase
                .from("admin_requests")
                .insert(requestData)
                .execute()
            
            let deceasedMemberName = allMembers.first(where: { $0.id == memberId })?.firstName ?? "عضو"
            let requesterDeceasedName = currentUser?.firstName ?? "عضو"
            let deceasedBody = "طلب تأكيد وفاة: \(deceasedMemberName)\nتاريخ الوفاة: \(dateString)\nبواسطة: \(requesterDeceasedName)"
            await notifyAdminsWithPush(
                title: "طلب تأكيد وفاة",
                body: deceasedBody,
                kind: "deceased_report"
            )
            
            Log.info("تم إرسال طلب تأكيد الوفاة للإدارة بنجاح")
        } catch {
            Log.error("خطأ في إرسال الطلب: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
    func fetchDeceasedRequests(force: Bool = false) async {
        if !force, let last = lastDeceasedFetchDate, Date().timeIntervalSince(last) < 20, !deceasedRequests.isEmpty { return }
        lastDeceasedFetchDate = Date()
        do {
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:profiles!member_id(*)") // حركة ذكية لجلب بيانات العضو مع الطلب ✅
                .eq("request_type", value: "deceased_report")
                .eq("status", value: "pending")
                .execute()
                .value
            
            self.deceasedRequests = requests
        } catch {
            Log.error("فشل جلب طلبات الوفاة: \(error)")
        }
    }
    
    // 3. دالة الموافقة (تحديث الشجرة + تحديث حالة الطلب)
    func approveDeceasedRequest(request: AdminRequest) async {
        self.isLoading = true
        do {
            // أ. تحديث حالة الشخص في جدول Profiles ليصبح متوفى فعلياً في الشجرة
            try await supabase
                .from("profiles")
                .update(["is_deceased": AnyEncodable(true)])
                .eq("id", value: request.memberId.uuidString)
                .execute()
            
            // ب. تحديث حالة الطلب في جدول Admin Requests إلى مقبول
            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("approved")])
                .eq("id", value: request.id.uuidString)
                .execute()
            
            // ج. تحديث البيانات محلياً
            await fetchDeceasedRequests(force: true)
            await fetchAllMembers()
            
            let memberName = allMembers.first(where: { $0.id == request.memberId })?.firstName ?? "عضو"
            await notifyAdmins(
                title: "تأكيد وفاة",
                body: "تم تأكيد وفاة \(memberName).",
                kind: "deceased_report"
            )
            
            Log.info("تم قبول الطلب وتحديث الشجرة بنجاح")
        } catch {
            Log.error("فشل في تنفيذ عملية الموافقة: \(error)")
        }
        self.isLoading = false
    }

    func rejectDeceasedRequest(request: AdminRequest) async {
        self.isLoading = true
        do {
            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("rejected")])
                .eq("id", value: request.id.uuidString)
                .execute()

            await fetchDeceasedRequests(force: true)
            Log.info("تم رفض طلب تأكيد الوفاة")
        } catch {
            Log.error("فشل في رفض طلب الوفاة: \(error)")
        }
        self.isLoading = false
    }

    // MARK: - طلبات إضافة الأبناء (Child Add Requests)

    func fetchChildAddRequests(force: Bool = false) async {
        if !force, let last = lastChildAddFetchDate, Date().timeIntervalSince(last) < 20, !childAddRequests.isEmpty { return }
        lastChildAddFetchDate = Date()
        do {
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:profiles!member_id(*)")
                .eq("request_type", value: "child_add")
                .eq("status", value: "pending")
                .execute()
                .value

            self.childAddRequests = requests
        } catch {
            Log.error("فشل جلب طلبات إضافة الأبناء: \(error)")
        }
    }

    func rejectChildAddRequest(request: AdminRequest) async {
        self.isLoading = true
        do {
            // حذف الابن المضاف من جدول profiles إذا كان موجوداً
            if let childId = request.newValue {
                try await supabase
                    .from("profiles")
                    .delete()
                    .eq("id", value: childId)
                    .execute()
            }

            // تحديث حالة الطلب إلى مرفوض
            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("rejected")])
                .eq("id", value: request.id.uuidString)
                .execute()

            await fetchChildAddRequests(force: true)
            await fetchAllMembers()

            let rejectChildDetails = request.details ?? "طلب إضافة ابن"
            let rejectByName = currentUser?.firstName ?? "مدير"
            await notifyAdminsWithPush(
                title: "رفض إضافة ابن",
                body: "\(rejectChildDetails)\nتم الرفض بواسطة: \(rejectByName)",
                kind: "child_add"
            )
            
            Log.info("تم رفض طلب إضافة الابن وحذفه من الشجرة")
        } catch {
            Log.error("فشل رفض طلب إضافة الابن: \(error)")
        }
        self.isLoading = false
    }

    func acknowledgeChildAddRequest(request: AdminRequest) async {
        self.isLoading = true
        do {
            // تحديث حالة الطلب إلى مقبول
            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("approved")])
                .eq("id", value: request.id.uuidString)
                .execute()

            await fetchChildAddRequests(force: true)

            let approveChildDetails = request.details ?? "طلب إضافة ابن"
            let approveByName = currentUser?.firstName ?? "مدير"
            await notifyAdminsWithPush(
                title: "قبول إضافة ابن",
                body: "\(approveChildDetails)\nتم القبول بواسطة: \(approveByName)",
                kind: "child_add"
            )
            
            Log.info("تم تأكيد طلب إضافة الابن بنجاح")
        } catch {
            Log.error("فشل تأكيد طلب إضافة الابن: \(error)")
        }
        self.isLoading = false
    }

    func adminAddSon(firstName: String, parent: FamilyMember?) async {
        self.isLoading = true
        
        do {
            let newId = UUID()
            
            // 1. إذا كان الأب موجوداً نركب الاسم، وإذا لم يوجد (جذر) نكتفي بالاسم الأول
            let fullCombinedName = parent.map { "\(firstName) \($0.fullName)" } ?? firstName
            
            // 2. إذا كان الأب موجوداً نأخذ معرفه، وإذا لم يوجد نرسل nil للسيرفر
            let fatherIdValue = parent?.id.uuidString
            
            let sonData: [String: AnyEncodable] = [
                "id": AnyEncodable(newId.uuidString),
                "first_name": AnyEncodable(firstName),
                "full_name": AnyEncodable(fullCombinedName),
                "father_id": AnyEncodable(fatherIdValue), // سيكون NULL في السيرفر إذا كان parent هو nil
                "role": AnyEncodable("member"),
                "is_deceased": AnyEncodable(true),
                "sort_order": AnyEncodable(0)
            ]
            
            try await supabase.from("profiles").insert(sonData).execute()
            
            // جلب البيانات فوراً لتحديث الشجرة
            await fetchAllMembers()
            
        } catch {
            Log.error("خطأ في إضافة العضو: \(error.localizedDescription)")
        }
        
        self.isLoading = false
    }
    func updateMemberPhone(memberId: UUID, newPhone: String) async {
        await updateMemberPhone(memberId: memberId, country: KuwaitPhone.defaultCountry, localPhone: newPhone)
    }

    func updateMemberPhone(memberId: UUID, country: KuwaitPhone.Country, localPhone: String) async {
        self.isLoading = true
        guard let normalizedPhone = KuwaitPhone.normalizedForStorage(country: country, rawLocalDigits: localPhone) else {
            Log.error("رقم الهاتف غير صالح للدولة المختارة.")
            self.isLoading = false
            return
        }
        do {
            // 1) تحديث الهاتف
            try await supabase
                .from("profiles")
                .update(["phone_number": AnyEncodable(normalizedPhone)])
                .eq("id", value: memberId.uuidString)
                .execute()
            
            // 2) تفعيل العضو مباشرة بعد إضافة الرقم
            let profileResponse: [FamilyMember] = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: memberId.uuidString)
                .limit(1)
                .execute()
                .value
            
            if let profile = profileResponse.first {
                var activationPayload: [String: AnyEncodable] = [
                    "status": AnyEncodable("active")
                ]
                
                if profile.role == .pending {
                    activationPayload["role"] = AnyEncodable("member")
                }
                
                try await supabase
                    .from("profiles")
                    .update(activationPayload)
                    .eq("id", value: memberId.uuidString)
                    .execute()
                
                // 3) اعتماد أي طلب انضمام معلق لنفس العضو
                _ = try? await supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable("approved")])
                    .eq("member_id", value: memberId.uuidString)
                    .eq("request_type", value: "join_request")
                    .eq("status", value: "pending")
                    .execute()
            }
            
            await fetchAllMembers() // تحديث البيانات فوراً ✅
            Log.info("تم تحديث الهاتف وتفعيل العضو للدخول المباشر")
        } catch {
            Log.error("خطأ تحديث الهاتف: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
    func updateMemberFather(memberId: UUID, fatherId: UUID?) async {
        self.isLoading = true
        do {
            // نرسل الـ UUID كـ String، وإذا كان nil نرسل NULL للسيرفر
            let updateData: [String: AnyEncodable] = [
                "father_id": AnyEncodable(fatherId?.uuidString)
            ]
            
            try await supabase
                .from("profiles")
                .update(updateData)
                .eq("id", value: memberId.uuidString)
                .execute()
            
            await fetchAllMembers() // تحديث البيانات فوراً لتظهر في الشجرة
            Log.info("تم تحديث ربط الأب بنجاح")
        } catch {
            Log.error("خطأ في ربط الأب: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
    func updateMemberHealthAndBirth(
        memberId: UUID,
        birthDate: Date?,    // أصبح اختيارياً ليدعم "Not Available"
        isDeceased: Bool,
        deathDate: Date?     // أصبح اختيارياً ليدعم "Not Available"
    ) async {
        self.isLoading = true

        // 1. تنسيق التواريخ
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        // تحويل التاريخ لنص فقط إذا كان المشرف قد أدخله، وإلا يبقى nil
        let birthDateString = birthDate != nil ? formatter.string(from: birthDate!) : nil
        let deathDateString = (isDeceased && deathDate != nil) ? formatter.string(from: deathDate!) : nil
        
        // 2. تجهيز البيانات للإرسال
        // نستخدم Optional<String>.none لإرسال NULL لقاعدة البيانات عند عدم توفر التاريخ
        var updateData: [String: AnyEncodable] = [
            "birth_date": AnyEncodable(birthDateString ?? Optional<String>.none),
            "is_deceased": AnyEncodable(isDeceased)
        ]
        
        // إضافة تاريخ الوفاة بناءً على حالة الوفاة وتوفر التاريخ
        if isDeceased {
            updateData["death_date"] = AnyEncodable(deathDateString ?? Optional<String>.none)
        } else {
            updateData["death_date"] = AnyEncodable(Optional<String>.none)
        }
        
        do {
            // 3. التحديث في قاعدة بيانات Supabase
            try await supabase
                .from("profiles")
                .update(updateData)
                .eq("id", value: memberId.uuidString)
                .execute()
            
            // 4. تحديث القائمة المحلية فوراً
            await fetchAllMembers()
            Log.info("تم تحديث البيانات بنجاح (مع دعم التواريخ المفقودة)")
            
        } catch {
            Log.error("خطأ في تحديث البيانات: \(error.localizedDescription)")
        }
        
        self.isLoading = false
    }

    @discardableResult
    func updateChildData(
        member: FamilyMember,
        firstName: String,
        phoneNumber: String,
        birthDate: String?,
        isDeceased: Bool,
        deathDate: String?,
        gender: String?
    ) async -> Bool {
        self.isLoading = true

        let safeFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalFullName = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let normalizedPhone = KuwaitPhone.normalizeForStorageFromInput(phoneNumber)
        let storedPhone = normalizedPhone ?? Optional<String>.none
        
        var payload: [String: AnyEncodable] = [
            "first_name": AnyEncodable(safeFirstName),
            "full_name": AnyEncodable(finalFullName),
            "phone_number": AnyEncodable(storedPhone),
            "birth_date": AnyEncodable(birthDate ?? Optional<String>.none),
            "is_deceased": AnyEncodable(isDeceased)
        ]

        if isDeceased {
            payload["death_date"] = AnyEncodable(deathDate ?? Optional<String>.none)
        } else {
            payload["death_date"] = AnyEncodable(Optional<String>.none)
        }

        do {
            try await supabase
                .from("profiles")
                .update(payload)
                .eq("id", value: member.id.uuidString)
                .execute()
        } catch {
            Log.error("خطأ تعديل بيانات الابن: \(error.localizedDescription)")
            self.isLoading = false
            return false
        }

        // تحديث الجنس بشكل منفصل (العمود قد لا يكون في schema cache)
        if let gender, !gender.isEmpty {
            do {
                try await supabase
                    .from("profiles")
                    .update(["gender": AnyEncodable(gender)])
                    .eq("id", value: member.id.uuidString)
                    .execute()
            } catch {
                Log.warning("عمود gender غير متوفر: \(error.localizedDescription)")
            }
        }

        await fetchAllMembers()
        if let fatherId = member.fatherId {
            await fetchChildren(for: fatherId)
        }
        
        self.isLoading = false
        return true
    }
    // دالة إرسال طلب تغيير رقم الهاتف للإدارة
    func requestPhoneNumberChange(memberId: UUID, newPhoneNumber: String) async {
        self.isLoading = true
        guard let normalizedPhone = KuwaitPhone.normalizeForStorageFromInput(newPhoneNumber) else {
            Log.error("رقم طلب التغيير غير صالح.")
            self.isLoading = false
            return
        }
        do {
            let requestData: [String: AnyEncodable] = [
                "member_id": AnyEncodable(memberId.uuidString),
                "requester_id": AnyEncodable(currentUser?.id.uuidString),
                "request_type": AnyEncodable("phone_change"),
                "new_value": AnyEncodable(normalizedPhone),
                "status": AnyEncodable("pending"),
                "details": AnyEncodable("طلب تغيير رقم الجوال")
            ]
            
            // إرسال الطلب لجدول الطلبات (مثلاً جدول admin_requests)
            try await supabase
                .from("admin_requests")
                .insert(requestData)
                .execute()
            
            let phoneRequesterName = currentUser?.firstName ?? "عضو"
            let phoneChangeBody = "طلب تغيير رقم جوال\nالعضو: \(phoneRequesterName)\nالرقم الجديد: \(KuwaitPhone.display(normalizedPhone))"
            await notifyAdminsWithPush(
                title: "طلب تغيير رقم جوال",
                body: phoneChangeBody,
                kind: "phone_change"
            )
            
            Log.info("تم إرسال طلب تغيير الرقم للإدارة: \(normalizedPhone)")
        } catch {
            Log.error("خطأ في إرسال طلب التغيير: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
    
    func fetchPhoneChangeRequests(force: Bool = false) async {
        if !force, let last = lastPhoneChangeFetchDate, Date().timeIntervalSince(last) < 20, !phoneChangeRequests.isEmpty { return }
        lastPhoneChangeFetchDate = Date()
        guard canModerate else {
            phoneChangeRequests = []
            return
        }
        
        do {
            let requests: [PhoneChangeRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:profiles!member_id(*)")
                .eq("request_type", value: "phone_change")
                .eq("status", value: "pending")
                .order("created_at", ascending: false)
                .execute()
                .value
            
            self.phoneChangeRequests = requests
        } catch {
            Log.error("خطأ جلب طلبات تغيير الرقم: \(error.localizedDescription)")
        }
    }
    
    func approvePhoneChangeRequest(request: PhoneChangeRequest) async {
        guard canModerate, let rawPhone = request.newValue, !rawPhone.isEmpty else { return }
        guard let newPhone = KuwaitPhone.normalizeForStorageFromInput(rawPhone) else { return }
        self.isLoading = true
        
        do {
            try await supabase
                .from("profiles")
                .update(["phone_number": AnyEncodable(newPhone)])
                .eq("id", value: request.memberId.uuidString)
                .execute()
            
            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("approved")])
                .eq("id", value: request.id.uuidString)
                .execute()
            
            await fetchPhoneChangeRequests(force: true)
            await fetchAllMembers()
            
            let memberName = allMembers.first(where: { $0.id == request.memberId })?.firstName ?? "عضو"
            await notifyAdmins(
                title: "اعتماد تغيير رقم",
                body: "تم اعتماد تغيير رقم جوال \(memberName).",
                kind: "phone_change"
            )
        } catch {
            Log.error("خطأ اعتماد تغيير الرقم: \(error.localizedDescription)")
        }
        
        self.isLoading = false
    }
    
    func rejectPhoneChangeRequest(request: PhoneChangeRequest) async {
        guard canModerate else { return }
        self.isLoading = true
        
        do {
            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("rejected")])
                .eq("id", value: request.id.uuidString)
                .execute()
            
            await fetchPhoneChangeRequests(force: true)
            
            let rejectPhoneMemberName = allMembers.first(where: { $0.id == request.memberId })?.firstName ?? "عضو"
            await notifyAdmins(
                title: "رفض تغيير رقم",
                body: "تم رفض طلب تغيير رقم جوال \(rejectPhoneMemberName).",
                kind: "phone_change"
            )
        } catch {
            Log.error("خطأ رفض تغيير الرقم: \(error.localizedDescription)")
        }
        
        self.isLoading = false
    }
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
    
    // 1. جلب الأخبار من السيرفر
    func fetchNews(force: Bool = false) async {
        if !force, let last = lastNewsFetchDate, Date().timeIntervalSince(last) < 10, !allNews.isEmpty { return }
        lastNewsFetchDate = Date()
        do {
            let response: [NewsPost] = try await supabase.from("news")
                .select()
                .order("created_at", ascending: false) // الأحدث أولاً
                .execute()
                .value
            
            let userId = currentUser?.id
            if canModerate {
                self.allNews = response
            } else {
                self.allNews = response.filter { post in
                    post.isApproved || post.author_id == userId
                }
            }

            let pollPostIds = allNews.filter { $0.hasPoll }.map(\.id)
            let allPostIds = allNews.map(\.id)
            async let fetchVotes: () = fetchNewsPollVotes(for: pollPostIds)
            async let fetchLikes: () = fetchNewsLikes(for: allPostIds)
            async let fetchComments: () = fetchNewsComments(for: allPostIds)
            _ = await (fetchVotes, fetchLikes, fetchComments)
        } catch {
            Log.error("خطأ جلب الأخبار: \(error)")
        }
    }

    func fetchNewsPollVotes(for postIds: [UUID]) async {
        guard newsPollFeatureAvailable else {
            pollVotesByPost = [:]
            userVoteByPost = [:]
            return
        }
        guard !postIds.isEmpty else {
            pollVotesByPost = [:]
            userVoteByPost = [:]
            return
        }

        do {
            let postIdSet = Set(postIds)
            let votes: [NewsPollVoteRecord] = try await supabase
                .from("news_poll_votes")
                .select("news_id,member_id,option_index")
                .execute()
                .value

            var aggregated: [UUID: [Int: Int]] = [:]
            var userSelection: [UUID: Int] = [:]
            let currentUserId = currentUser?.id

            for vote in votes where postIdSet.contains(vote.news_id) {
                aggregated[vote.news_id, default: [:]][vote.option_index, default: 0] += 1
                if let currentUserId, vote.member_id == currentUserId {
                    userSelection[vote.news_id] = vote.option_index
                }
            }

            pollVotesByPost = aggregated
            userVoteByPost = userSelection
            newsPollFeatureAvailable = true
        } catch {
            if isMissingNewsPollVotesTableError(error) {
                newsPollFeatureAvailable = false
                pollVotesByPost = [:]
                userVoteByPost = [:]
            } else {
                Log.error("خطأ جلب أصوات التصويت: \(error.localizedDescription)")
            }
        }
    }
    
    func fetchNewsLikes(for postIds: [UUID]) async {
        guard !postIds.isEmpty else {
            likesCountByPost = [:]
            likedPosts = []
            return
        }
        
        do {
            let postIdSet = Set(postIds)
            let likes: [NewsLikeRecord] = try await supabase
                .from("news_likes")
                .select()
                .execute()
                .value
            
            var counts: [UUID: Int] = [:]
            var userLikes: Set<UUID> = []
            let currentUserId = await authenticatedUserId()
            
            for like in likes where postIdSet.contains(like.news_id) {
                counts[like.news_id, default: 0] += 1
                if let currentUserId, like.member_id == currentUserId {
                    userLikes.insert(like.news_id)
                }
            }
            
            self.likesCountByPost = counts
            self.likedPosts = userLikes
        } catch {
            if isCancellationError(error) { return }
            Log.error("خطأ جلب الاعجابات: \(error.localizedDescription)")
        }
    }
    
    func fetchNewsComments(for postIds: [UUID]) async {
        guard !postIds.isEmpty else {
            commentsByPost = [:]
            commentsCountByPost = [:]
            return
        }
        
        do {
            let postIdSet = Set(postIds)
            let commentsData: [NewsCommentRecord] = try await supabase
                .from("news_comments")
                .select()
                .order("created_at", ascending: true)
                .execute()
                .value
            
            var aggregated: [UUID: [NewsCommentRecord]] = [:]
            var counts: [UUID: Int] = [:]
            
            for comment in commentsData where postIdSet.contains(comment.news_id) {
                aggregated[comment.news_id, default: []].append(comment)
                counts[comment.news_id, default: 0] += 1
            }
            
            self.commentsByPost = aggregated
            self.commentsCountByPost = counts
        } catch {
            if isCancellationError(error) { return }
            Log.error("خطأ جلب التعليقات: \(error.localizedDescription)")
        }
    }
    
    func toggleNewsLike(for postId: UUID) async {
        guard let memberId = await authenticatedUserId() else { return }
        
        let isCurrentlyLiked = likedPosts.contains(postId)
        
        // Optimistic update
        if isCurrentlyLiked {
            likedPosts.remove(postId)
            likesCountByPost[postId, default: 1] -= 1
        } else {
            likedPosts.insert(postId)
            likesCountByPost[postId, default: 0] += 1
        }
        
        do {
            if isCurrentlyLiked {
                try await supabase
                    .from("news_likes")
                    .delete()
                    .eq("news_id", value: postId.uuidString)
                    .eq("member_id", value: memberId.uuidString)
                    .execute()
            } else {
                let likeRecord: [String: AnyEncodable] = [
                    "news_id": AnyEncodable(postId.uuidString),
                    "member_id": AnyEncodable(memberId.uuidString)
                ]
                try await supabase
                    .from("news_likes")
                    .insert(likeRecord)
                    .execute()
            }
        } catch {
            Log.error("خطأ تحديث الاعجاب: \(error.localizedDescription)")
            // Revert on error
            if isCurrentlyLiked {
                likedPosts.insert(postId)
                likesCountByPost[postId, default: 0] += 1
            } else {
                likedPosts.remove(postId)
                likesCountByPost[postId, default: 1] -= 1
            }
        }
    }
    
    func addNewsComment(to postId: UUID, text: String) async -> Bool {
        guard let memberId = await authenticatedUserId(),
              let authorName = currentUser?.fullName else { return false }
        
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return false }
        
        do {
            let commentRecord: [String: AnyEncodable] = [
                "news_id": AnyEncodable(postId.uuidString),
                "author_id": AnyEncodable(memberId.uuidString),
                "author_name": AnyEncodable(authorName),
                "content": AnyEncodable(normalizedText)
            ]
            
            try await supabase
                .from("news_comments")
                .insert(commentRecord)
                .execute()
            
            // Refresh comments to get new data
            await fetchNewsComments(for: allNews.map(\.id))
            return true
        } catch {
            Log.error("خطأ إضافة تعليق: \(error.localizedDescription)")
            return false
        }
    }
    
    func fetchPendingNewsRequests(force: Bool = false) async {
        if !force, let last = lastPendingNewsFetchDate, Date().timeIntervalSince(last) < 20, !pendingNewsRequests.isEmpty { return }
        lastPendingNewsFetchDate = Date()
        guard canModerate else {
            pendingNewsRequests = []
            return
        }
        guard newsApprovalFeatureAvailable else {
            pendingNewsRequests = []
            return
        }
        
        do {
            let response: [NewsPost] = try await supabase.from("news")
                .select()
                .eq("approval_status", value: "pending")
                .order("created_at", ascending: false)
                .execute()
                .value
            newsApprovalFeatureAvailable = true
            self.pendingNewsRequests = response
        } catch {
            if isMissingNewsApprovalColumnError(error) {
                newsApprovalFeatureAvailable = false
                pendingNewsRequests = []
            } else {
                Log.error("خطأ جلب طلبات الأخبار: \(error)")
            }
        }
    }
    
    func fetchNotifications(force: Bool = false) async {
        if !force, let last = lastNotificationsFetchDate, Date().timeIntervalSince(last) < 15, !notifications.isEmpty { return }
        lastNotificationsFetchDate = Date()
        guard let userId = currentUser?.id else {
            notifications = []
            return
        }
        guard notificationsFeatureAvailable else {
            notifications = []
            return
        }
        
        do {
            // المدراء يشوفون الإشعارات الموجهة لهم + البث العام (notifyAdmins)
            // الأعضاء العاديون يشوفون فقط الإشعارات الموجهة لهم شخصياً
            let filter = canModerate
                ? "target_member_id.is.null,target_member_id.eq.\(userId.uuidString)"
                : "target_member_id.eq.\(userId.uuidString)"
            
            let response: [AppNotification] = try await supabase
                .from("notifications")
                .select()
                .or(filter)
                .order("created_at", ascending: false)
                .execute()
                .value
            
            let unreadCount = response.filter { !$0.read }.count
            self.notificationsFeatureAvailable = true
            self.notifications = response
            let badgeOn = currentUser?.badgeEnabled ?? true
            try? await UNUserNotificationCenter.current().setBadgeCount(badgeOn ? unreadCount : 0)
        } catch {
            if isMissingNotificationsTableError(error) {
                notificationsFeatureAvailable = false
                notifications = []
            } else {
                Log.error("خطأ جلب الإشعارات: \(error.localizedDescription)")
            }
        }
    }
    
    func deleteNotification(id: UUID) async {
        // تحديث محلي فوري
        notifications.removeAll { $0.id == id }
        let badgeOn = currentUser?.badgeEnabled ?? true
        let unread = notifications.filter { !$0.read }.count
        try? await UNUserNotificationCenter.current().setBadgeCount(badgeOn ? unread : 0)
        
        do {
            try await supabase
                .from("notifications")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            Log.error("خطأ حذف إشعار: \(error.localizedDescription)")
            await fetchNotifications(force: true)
        }
    }
    
    func deleteNotifications(ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        // تحديث محلي فوري
        notifications.removeAll { ids.contains($0.id) }
        let badgeOn = currentUser?.badgeEnabled ?? true
        let unread = notifications.filter { !$0.read }.count
        try? await UNUserNotificationCenter.current().setBadgeCount(badgeOn ? unread : 0)
        
        do {
            let idStrings = ids.map { $0.uuidString }
            try await supabase
                .from("notifications")
                .delete()
                .in("id", values: idStrings)
                .execute()
        } catch {
            Log.error("خطأ حذف إشعارات: \(error.localizedDescription)")
            await fetchNotifications(force: true)
        }
    }
    
    func markNotificationAsRead(id: UUID) async {
        // تحديث محلي فوري
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx] = notifications[idx].withRead(true)
        }
        let badgeOn = currentUser?.badgeEnabled ?? true
        let unread = notifications.filter { !$0.read }.count
        try? await UNUserNotificationCenter.current().setBadgeCount(badgeOn ? unread : 0)
        
        do {
            try await supabase
                .from("notifications")
                .update(["is_read": AnyEncodable(true)])
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            Log.error("خطأ تحديث حالة الإشعار: \(error.localizedDescription)")
            await fetchNotifications(force: true)
        }
    }
    
    func markNotificationsAsRead(ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        // تحديث محلي فوري
        for i in notifications.indices where ids.contains(notifications[i].id) {
            notifications[i] = notifications[i].withRead(true)
        }
        let badgeOn = currentUser?.badgeEnabled ?? true
        let unread = notifications.filter { !$0.read }.count
        try? await UNUserNotificationCenter.current().setBadgeCount(badgeOn ? unread : 0)
        
        do {
            let idStrings = ids.map { $0.uuidString }
            try await supabase
                .from("notifications")
                .update(["is_read": AnyEncodable(true)])
                .in("id", values: idStrings)
                .execute()
        } catch {
            Log.error("خطأ تعليم إشعارات كمقروءة: \(error.localizedDescription)")
            await fetchNotifications(force: true)
        }
    }
    
    func markAllNotificationsAsRead() async {
        guard let userId = currentUser?.id else { return }
        // تحديث محلي فوري
        for i in notifications.indices where !notifications[i].read {
            notifications[i] = notifications[i].withRead(true)
        }
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
        
        let filter = canModerate
            ? "target_member_id.is.null,target_member_id.eq.\(userId.uuidString)"
            : "target_member_id.eq.\(userId.uuidString)"
        do {
            try await supabase
                .from("notifications")
                .update(["is_read": AnyEncodable(true)])
                .or(filter)
                .eq("is_read", value: false)
                .execute()
        } catch {
            Log.error("خطأ تعليم كل الإشعارات كمقروءة: \(error.localizedDescription)")
            await fetchNotifications(force: true)
        }
    }
    
    func sendNotification(title: String, body: String, targetMemberIds: [UUID]?, sendPush: Bool = true) async {
        guard canModerate, let creator = currentUser?.id else { return }
        guard notificationsFeatureAvailable else { return }
        self.isLoading = true
        
        do {
            if let ids = targetMemberIds, !ids.isEmpty {
                for memberId in ids {
                    let payload: [String: AnyEncodable] = [
                        "target_member_id": AnyEncodable(memberId.uuidString),
                        "title": AnyEncodable(title),
                        "body": AnyEncodable(body),
                        "kind": AnyEncodable("admin"),
                        "created_by": AnyEncodable(creator.uuidString)
                    ]
                    try await supabase.from("notifications").insert(payload).execute()
                }
            } else {
                let payload: [String: AnyEncodable] = [
                    "target_member_id": AnyEncodable(Optional<String>.none),
                    "title": AnyEncodable(title),
                    "body": AnyEncodable(body),
                    "kind": AnyEncodable("admin"),
                    "created_by": AnyEncodable(creator.uuidString)
                ]
                try await supabase.from("notifications").insert(payload).execute()
            }
            
            // إرسال push حقيقي للأعضاء المستهدفين
            if sendPush {
                await sendPushToMembers(
                    title: title,
                    body: body,
                    kind: "admin",
                    targetMemberIds: targetMemberIds
                )
            }
            
            // إشعار المدراء الآخرين بإرسال إشعار إداري
            await notifyAdmins(
                title: "إشعار إداري",
                body: "تم إرسال إشعار: \(title)",
                kind: "admin"
            )
            
            await fetchNotifications(force: true)
        } catch {
            if isMissingNotificationsTableError(error) {
                notificationsFeatureAvailable = false
            } else {
                Log.error("خطأ إرسال الإشعار: \(error.localizedDescription)")
            }
        }
        
        self.isLoading = false
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
    
    func uploadNewsImage(image: UIImage, for authorId: UUID) async -> String? {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { return nil }

        let imageId = UUID()
        let safeAuthorName = getSafeMemberName(for: authorId)
        let filePath = "news/\(safeAuthorName)/\(imageId.uuidString).jpg"

        do {
            try await supabase.storage
                .from("news")
                .upload(
                    filePath,
                    data: imageData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )

            let publicURL = try supabase.storage
                .from("news")
                .getPublicURL(path: filePath)
                .absoluteString

            return publicURL
        } catch {
            Log.error("خطأ رفع صورة الخبر: \(error.localizedDescription)")
            return nil
        }
    }


    func submitNewsPollVote(postId: UUID, optionIndex: Int) async {
        guard let memberId = currentUser?.id else { return }
        guard newsPollFeatureAvailable else { return }

        do {
            let payload: [String: AnyEncodable] = [
                "news_id": AnyEncodable(postId.uuidString),
                "member_id": AnyEncodable(memberId.uuidString),
                "option_index": AnyEncodable(optionIndex)
            ]

            try await supabase
                .from("news_poll_votes")
                .upsert(payload, onConflict: "news_id,member_id")
                .execute()

            var counts = pollVotesByPost[postId] ?? [:]
            if let old = userVoteByPost[postId] {
                if old != optionIndex {
                    counts[old] = max(0, (counts[old] ?? 1) - 1)
                    counts[optionIndex] = (counts[optionIndex] ?? 0) + 1
                    userVoteByPost[postId] = optionIndex
                }
            } else {
                counts[optionIndex] = (counts[optionIndex] ?? 0) + 1
                userVoteByPost[postId] = optionIndex
            }
            pollVotesByPost[postId] = counts
        } catch {
            if isMissingNewsPollVotesTableError(error) {
                newsPollFeatureAvailable = false
            } else {
                Log.error("خطأ إرسال التصويت: \(error.localizedDescription)")
            }
        }
    }

    // 2. إضافة خبر جديد (للمدراء)
    func postNews(
        content: String,
        type: String,
        imageURLs: [String] = [],
        pollQuestion: String? = nil,
        pollOptions: [String] = []
    ) async -> Bool {
        guard let user = currentUser else {
            Log.error("لا يوجد مستخدم مسجل دخول")
            newsPostErrorMessage = "لا يوجد مستخدم مسجل دخول."
            return false
        }
        
        self.isLoading = true
        newsPostErrorMessage = nil

        let shouldAutoApprove = canAutoPublishNews
        
        // تأكد من أن المسميات هنا تطابق أعمدة الجدول في سوبابيس
        let newPost: [String: AnyEncodable] = [
            "author_id": AnyEncodable(user.id.uuidString),
            "author_name": AnyEncodable(user.fullName),
            "author_role": AnyEncodable(user.roleName),
            "role_color": AnyEncodable(user.role == .admin ? "purple" : (user.role == .supervisor ? "orange" : "blue")),
            "content": AnyEncodable(content),
            "type": AnyEncodable(type),
            "image_url": AnyEncodable(imageURLs.first),
            "image_urls": AnyEncodable(imageURLs),
            "poll_question": AnyEncodable(pollQuestion),
            "poll_options": AnyEncodable(pollOptions),
            "approval_status": AnyEncodable(shouldAutoApprove ? "approved" : "pending"),
            "approved_by": AnyEncodable(shouldAutoApprove ? user.id.uuidString : Optional<String>.none)
        ]
        
        do {
            try await supabase.from("news").insert(newPost).execute()
            if !shouldAutoApprove, currentUser?.role == .member {
                await notifyAdminsWithPush(
                    title: "خبر جديد بانتظار المراجعة",
                    body: "قام عضو بإضافة خبر جديد ويحتاج موافقة الإدارة.",
                    kind: "news_add"
                )
            }
            // إشعار المدراء والمشرفين عند نشر خبر جديد
            if shouldAutoApprove {
                await notifyAdmins(
                    title: "خبر جديد",
                    body: "تم نشر خبر جديد.",
                    kind: "news_add"
                )
            }
            Log.info(shouldAutoApprove ? "تم نشر الخبر بنجاح" : "تم إرسال الخبر للمراجعة")
            await fetchNews(force: true)
            if canModerate {
                await fetchPendingNewsRequests(force: true)
            }
            self.isLoading = false
            return true
        } catch {
            if isMissingNewsApprovalColumnError(error) ||
                isMissingNewsRichContentColumnError(error) ||
                isMissingNewsSchemaColumnError(error) {
                newsApprovalFeatureAvailable = false
                let legacyPost: [String: AnyEncodable] = [
                    "author_id": AnyEncodable(user.id.uuidString),
                    "author_name": AnyEncodable(user.fullName),
                    "author_role": AnyEncodable(user.roleName),
                    "role_color": AnyEncodable(user.role == .admin ? "purple" : (user.role == .supervisor ? "orange" : "blue")),
                    "content": AnyEncodable(content),
                    "type": AnyEncodable(type),
                    "image_url": AnyEncodable(imageURLs.first),
                    "image_urls": AnyEncodable(imageURLs)
                ]
                
                do {
                    try await supabase.from("news").insert(legacyPost).execute()
                    Log.info("تم نشر الخبر (وضع التوافق)")
                    await fetchNews(force: true)
                    self.isLoading = false
                    return true
                } catch {
                    Log.error("خطأ في نشر الخبر (وضع التوافق): \(error.localizedDescription)")
                    newsPostErrorMessage = "تعذر نشر الخبر: \(error.localizedDescription)"
                }
            } else {
                Log.error("خطأ في نشر الخبر: \(error.localizedDescription)")
                newsPostErrorMessage = "تعذر نشر الخبر: \(error.localizedDescription)"
            }
        }

        self.isLoading = false
        return false
    }

    func updateNewsPost(
        postId: UUID,
        content: String,
        type: String,
        imageURLs: [String] = [],
        pollQuestion: String? = nil,
        pollOptions: [String] = []
    ) async -> Bool {
        guard currentUser?.role != .pending else {
            newsPostErrorMessage = "غير مصرح لك بتعديل الخبر."
            return false
        }

        self.isLoading = true
        newsPostErrorMessage = nil

        let payload: [String: AnyEncodable] = [
            "content": AnyEncodable(content),
            "type": AnyEncodable(type),
            "image_url": AnyEncodable(imageURLs.first),
            "image_urls": AnyEncodable(imageURLs),
            "poll_question": AnyEncodable(pollQuestion),
            "poll_options": AnyEncodable(pollOptions)
        ]

        do {
            try await supabase
                .from("news")
                .update(payload)
                .eq("id", value: postId.uuidString)
                .execute()

            await fetchNews(force: true)
            if canModerate {
                await fetchPendingNewsRequests(force: true)
            }

            self.isLoading = false
            return true
        } catch {
            if isMissingNewsRichContentColumnError(error) ||
                isMissingNewsSchemaColumnError(error) {
                let legacyPayload: [String: AnyEncodable] = [
                    "content": AnyEncodable(content),
                    "type": AnyEncodable(type),
                    "image_url": AnyEncodable(imageURLs.first)
                ]

                do {
                    try await supabase
                        .from("news")
                        .update(legacyPayload)
                        .eq("id", value: postId.uuidString)
                        .execute()

                    await fetchNews(force: true)
                    if canModerate {
                        await fetchPendingNewsRequests(force: true)
                    }

                    self.isLoading = false
                    return true
                } catch {
                    Log.error("خطأ تعديل الخبر (وضع التوافق): \(error.localizedDescription)")
                    newsPostErrorMessage = "تعذر تعديل الخبر: \(error.localizedDescription)"
                }
            } else {
                Log.error("خطأ تعديل الخبر: \(error.localizedDescription)")
                newsPostErrorMessage = "تعذر تعديل الخبر: \(error.localizedDescription)"
            }
        }

        self.isLoading = false
        return false
    }
    
    func approveNewsPost(postId: UUID) async {
        guard canModerate, let approverId = currentUser?.id else { return }
        guard newsApprovalFeatureAvailable else { return }
        self.isLoading = true

        do {
            let payload: [String: AnyEncodable] = [
                "approval_status": AnyEncodable("approved"),
                "approved_by": AnyEncodable(approverId.uuidString),
                "approved_at": AnyEncodable(ISO8601DateFormatter().string(from: Date()))
            ]
            
            try await supabase
                .from("news")
                .update(payload)
                .eq("id", value: postId.uuidString)
                .execute()
            
            await fetchPendingNewsRequests(force: true)
            await fetchNews(force: true)
            // إشعار المدراء والمشرفين بوجود خبر جديد معتمد
            await notifyAdmins(
                title: "خبر جديد",
                body: "تم نشر خبر جديد في الأخبار.",
                kind: "news_add"
            )
        } catch {
            if isMissingNewsApprovalColumnError(error) {
                newsApprovalFeatureAvailable = false
            } else {
                Log.error("خطأ اعتماد الخبر: \(error.localizedDescription)")
            }
        }
        
        self.isLoading = false
    }

    func rejectNewsPost(postId: UUID) async {
        guard canModerate else { return }
        self.isLoading = true
        
        do {
            try await supabase
                .from("news")
                .delete()
                .eq("id", value: postId.uuidString)
                .execute()
            
            await fetchPendingNewsRequests(force: true)
            await fetchNews(force: true)
            
            await notifyAdmins(
                title: "رفض خبر",
                body: "تم رفض خبر بانتظار المراجعة.",
                kind: "news_add"
            )
        } catch {
            Log.error("خطأ رفض الخبر: \(error.localizedDescription)")
        }
        
        self.isLoading = false
    }

    func deleteNewsPost(postId: UUID) async {
        guard currentUser?.role == .admin else { return }
        self.isLoading = true
        
        do {
            try await supabase
                .from("news")
                .delete()
                .eq("id", value: postId.uuidString)
                .execute()
            
            await fetchNews(force: true)
            if canModerate {
                await fetchPendingNewsRequests(force: true)
            }
            
            await notifyAdmins(
                title: "حذف خبر",
                body: "تم حذف خبر منشور.",
                kind: "news_add"
            )
        } catch {
            Log.error("خطأ حذف الخبر: \(error.localizedDescription)")
        }
        
        self.isLoading = false
    }

    func reportNewsPost(postId: UUID, reason: String = "بلاغ على محتوى خبر") async {
        guard let userId = currentUser?.id else { return }
        guard currentUser?.role == .member else { return }
        self.isLoading = true
        
        do {
            let payload: [String: AnyEncodable] = [
                "member_id": AnyEncodable(userId.uuidString),
                "requester_id": AnyEncodable(userId.uuidString),
                "request_type": AnyEncodable("news_report"),
                "new_value": AnyEncodable(postId.uuidString),
                "status": AnyEncodable("pending"),
                "details": AnyEncodable(reason)
            ]
            
            try await supabase
                .from("admin_requests")
                .insert(payload)
                .execute()
            
            await notifyAdminsWithPush(
                title: "بلاغ جديد على خبر",
                body: "وصل بلاغ جديد ويحتاج مراجعة الإدارة.",
                kind: "news_report"
            )
            
            await sendNotification(
                title: "تم استلام البلاغ",
                body: "تم استلام بلاغك بنجاح.",
                targetMemberIds: [userId]
            )
        } catch {
            Log.error("خطأ إرسال البلاغ: \(error.localizedDescription)")
        }
        
        self.isLoading = false
    }

    func sendContactMessage(category: String, message: String, preferredContact: String?) async -> Bool {
        guard let user = currentUser else { return false }
        self.isLoading = true
        contactMessageError = nil

        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContact = preferredContact?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMessage.isEmpty else {
            contactMessageError = "الرسالة فارغة."
            self.isLoading = false
            return false
        }

        let details = """
        التصنيف: \(category)
        الرسالة: \(cleanMessage)
        وسيلة التواصل: \(cleanContact?.isEmpty == false ? cleanContact! : "غير محدد")
        """

        do {
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
            } catch {
                // fallback لقواعد بيانات لم تُحدَّث فيها new_value
                if isMissingAdminRequestNewValueColumnError(error) {
                    try await supabase
                        .from("admin_requests")
                        .insert(basePayload)
                        .execute()
                } else {
                    throw error
                }
            }

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
            } catch {
                Log.warning("تعذر إرسال إيميل التواصل: \(error.localizedDescription)")
            }

            await notifyAdminsWithPush(
                title: "رسالة تواصل جديدة",
                body: "وصلت رسالة \(category) جديدة.",
                kind: "contact_message"
            )

            self.isLoading = false
            return true
        } catch {
            Log.error("خطأ إرسال رسالة التواصل: \(error.localizedDescription)")
            contactMessageError = error.localizedDescription
            self.isLoading = false
            return false
        }
    }
    
    func fetchNewsReportRequests(force: Bool = false) async {
        if !force, let last = lastNewsReportFetchDate, Date().timeIntervalSince(last) < 20, !newsReportRequests.isEmpty { return }
        lastNewsReportFetchDate = Date()
        guard canModerate else {
            newsReportRequests = []
            return
        }
        
        do {
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:profiles!member_id(*)")
                .eq("request_type", value: "news_report")
                .eq("status", value: "pending")
                .order("created_at", ascending: false)
                .execute()
                .value
            
            self.newsReportRequests = requests
        } catch {
            Log.error("خطأ جلب بلاغات الأخبار: \(error.localizedDescription)")
        }
    }
    
    func approveNewsReport(request: AdminRequest) async {
        guard canModerate else { return }
        self.isLoading = true
        
        do {
            if let postIdRaw = request.newValue, let postId = UUID(uuidString: postIdRaw) {
                try await supabase
                    .from("news")
                    .delete()
                    .eq("id", value: postId.uuidString)
                    .execute()
            }
            
            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("approved")])
                .eq("id", value: request.id.uuidString)
                .execute()
            
            await sendNotification(
                title: "تم اعتماد البلاغ",
                body: "شكراً لك، تمت مراجعة بلاغك واتخاذ الإجراء المناسب.",
                targetMemberIds: [request.memberId]
            )
            
            await fetchNewsReportRequests(force: true)
            await fetchNews(force: true)
        } catch {
            Log.error("خطأ اعتماد بلاغ الخبر: \(error.localizedDescription)")
        }
        
        self.isLoading = false
    }

    func rejectNewsReport(request: AdminRequest) async {
        guard canModerate else { return }
        self.isLoading = true
        
        do {
            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("rejected")])
                .eq("id", value: request.id.uuidString)
                .execute()
            
            await sendNotification(
                title: "تمت مراجعة البلاغ",
                body: "تمت مراجعة البلاغ ولم يتم حذف الخبر في هذه المرة.",
                targetMemberIds: [request.memberId]
            )
            
            await fetchNewsReportRequests(force: true)
        } catch {
            Log.error("خطأ رفض بلاغ الخبر: \(error.localizedDescription)")
        }
        
        self.isLoading = false
    }
}
