import SwiftUI
import Supabase
import Combine

// MARK: - «تفاصيل الرقم» (المالك فقط، ٢٠٢٦-١٠-٢٢ «كم أخذت الرسالة لين وصلت؟»)
//
// `owner_sms_login_details(p_phone, p_days, p_before)` (المالك، غيره 42501): كل طلب رمز دخول لرقم واحد، الأحدث أولاً،
// ٥٠ في الصفحة (`next_before` للمزيد). لكل طلب مُرسَل: «انرسل بعد X ث من الطلب» (`recorded_at − details.requested_at`)
// وحالة التسليم من `details.queue_status` (يملؤها السيرفر تلقائياً بعد ١–٣٠ دقيقة من الإرسال، ووقت الفحص `queue_checked_at`).
// «فك القفل» (المالك، بعد التأكيد): `kwtsms-admin` `{action:"unlock", phone}` ← `{ok, was_locked, cleared_requests}`.
// رمز كل رسالة (المالك ٢٠٢٦-١٠-٢٣): `owner_number_login_codes(p_phone, p_days)` ← `{codes:[{code, sent_at, status valid|expired}]}`
// (كل نداء يُسجَّل «عرضت الرمز»)، ويُطابَق كل طلب مُرسَل بأقرب رمز خلال دقيقتين. بعد «فك القفل»:
// `owner_clear_number_messages(p_phone)` يمسح طلبات الرقم ورموزه. قبل ترحيل 20261023180000 يفشل الاثنان بصمت.
// المدير لا يصل هنا أصلاً (صفوفه مخفية بلا `phone_e164`) — لا نداء جديد له.
// حارس المكدس: الصفحة خلف `AdminLazyPage { AnyView(…) }`، والرأس والمحتوى خلف `AnyView`.

/// ما ترجعه `owner_sms_login_details` — فكّ متسامح
struct SmsNumberDetails: Equatable {
    struct Request: Equatable, Identifiable {
        var id: Int64 = 0
        var recordedAt: Date?
        /// sent · blocked · failed · unknown · test
        var outcome = "unknown"
        var alerted = false
        var requestedAt: Date?
        var retryAfterSeconds: Int?
        var errorCode: String?
        var testMode = false
        /// حالة KWT بعد الإرسال («Delivered»، «ERR029»…) — nil قبل الفحص
        var queueStatus: String?
        var queueCheckedAt: Date?
    }

    var phoneE164 = ""
    var days = 7
    var memberId: UUID?
    var memberName: String?
    var memberStatus: String?
    var lastSignInAt: Date?
    /// أرقام `summary` كما هي (sent/blocked/…)
    var summary: [String: Int] = [:]
    var activeCodeExpiresAt: Date?
    var total = 0
    var items: [Request] = []
    var nextBefore: Int64?
    var codeViewCount = 0

    static func decode(_ data: Data) throws -> SmsNumberDetails {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        var r = SmsNumberDetails()
        r.phoneE164 = root["phone_e164"] as? String ?? ""
        r.days = SmsJSON.int(root["days"]) ?? 7
        if let m = root["member"] as? [String: Any] {
            r.memberId = (m["id"] as? String).flatMap(UUID.init(uuidString:))
            r.memberName = (m["name"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            r.memberStatus = m["status"] as? String
        }
        r.lastSignInAt = ApprovalWorkflow.date(root["last_sign_in_at"] as? String)
        for (key, value) in root["summary"] as? [String: Any] ?? [:] {
            if let n = SmsJSON.int(value) { r.summary[key] = n }
        }
        r.activeCodeExpiresAt = ApprovalWorkflow.date((root["active_code"] as? [String: Any])?["expires_at"] as? String)
        r.items = (root["items"] as? [[String: Any]] ?? []).map { decodeRequest($0) }
        r.total = SmsJSON.int(root["total"]) ?? r.items.count
        r.nextBefore = SmsJSON.double(root["next_before"]).map { Int64($0) }
        r.codeViewCount = SmsJSON.int(root["code_view_count"]) ?? 0
        return r
    }

    private static func decodeRequest(_ x: [String: Any]) -> Request {
        let d = x["details"] as? [String: Any] ?? [:]
        return Request(id: SmsJSON.double(x["id"]).map { Int64($0) } ?? 0,
                       recordedAt: ApprovalWorkflow.date(x["recorded_at"] as? String),
                       outcome: x["outcome"] as? String ?? "unknown",
                       alerted: x["alerted"] as? Bool ?? false,
                       requestedAt: ApprovalWorkflow.date(d["requested_at"] as? String),
                       retryAfterSeconds: SmsJSON.int(d["retry_after_seconds"]),
                       errorCode: (d["error_code"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                       testMode: d["test_mode"] as? Bool ?? false,
                       queueStatus: (d["queue_status"] as? String)
                           .map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 },
                       queueCheckedAt: ApprovalWorkflow.date(d["queue_checked_at"] as? String))
    }
}

/// رمز دخول أُرسل للرقم — من `owner_number_login_codes`
struct SmsLoginCode: Equatable {
    var code: String
    var sentAt: Date
    /// آخر رمز للرقم، لم ينتهِ، ولم يدخل صاحبه بعده
    var valid: Bool

    static func decode(_ data: Data) -> [SmsLoginCode] {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (root?["codes"] as? [[String: Any]] ?? []).compactMap { x in
            guard let code = x["code"] as? String, let sent = ApprovalWorkflow.date(x["sent_at"] as? String) else { return nil }
            return SmsLoginCode(code: code, sentAt: sent, valid: x["status"] as? String == "valid")
        }
    }

    /// رمز الطلب المُرسَل: أقرب رمز حُفظ خلال دقيقتين من تسجيل الطلب
    static func match(_ item: SmsNumberDetails.Request, in codes: [SmsLoginCode]) -> SmsLoginCode? {
        guard item.outcome == "sent", let at = item.recordedAt else { return nil }
        return codes
            .filter { abs($0.sentAt.timeIntervalSince(at)) <= 120 }
            .min { abs($0.sentAt.timeIntervalSince(at)) < abs($1.sentAt.timeIntervalSince(at)) }
    }
}

/// حالة التسليم من `queue_status`
enum SmsDelivery: Equatable {
    /// وصلت — بالدقائق حتى الفحص (حدّ أعلى)
    case delivered(minutes: Int?)
    /// ما وصلت — بالحالة الخام
    case notDelivered(String)
    /// لم يُفحص بعد أو حالة وسيطة
    case pending

    static func of(_ request: SmsNumberDetails.Request) -> SmsDelivery {
        guard let raw = request.queueStatus else { return .pending }
        let s = raw.lowercased()
        let failed = ["undeliver", "fail", "reject", "expire"].contains { s.contains($0) } || s.hasPrefix("err")
        if failed { return .notDelivered(raw) }
        guard s.contains("delivered") else { return .pending }
        guard let sent = request.recordedAt, let checked = request.queueCheckedAt else { return .delivered(minutes: nil) }
        let seconds = checked.timeIntervalSince(sent)
        guard seconds >= 0 else { return .delivered(minutes: nil) }
        return .delivered(minutes: max(1, Int((seconds / 60).rounded(.up))))
    }

    /// ثواني ما بين الطلب والإرسال — فقط إن كانا موجودين وبين ٠ و٦٠٠ ث
    static func sendDelay(_ request: SmsNumberDetails.Request) -> Double? {
        guard let sent = request.recordedAt, let asked = request.requestedAt else { return nil }
        let s = sent.timeIntervalSince(asked)
        return (0...600).contains(s) ? s : nil
    }
}

// MARK: - النصوص

enum SmsDetailsText {
    static let pageTitle = L10n.t("تفاصيل الرقم", "Number details")

    /// «اليوم 11:41:18» · «أمس 11:41:18» · «18 أكتوبر 11:41:18» — بتوقيت الكويت وأرقام لاتينية
    static func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SmsJSON.kuwait
        let locale = Locale(identifier: L10n.isArabic ? "ar@numbers=latn" : "en")
        clock.locale = locale
        clock.timeZone = SmsJSON.kuwait
        clock.setLocalizedDateFormatFromTemplate("jjmmss")
        let t = clock.string(from: date)
        if cal.isDateInToday(date) { return L10n.t("اليوم \(t)", "Today \(t)") }
        if cal.isDateInYesterday(date) { return L10n.t("أمس \(t)", "Yesterday \(t)") }
        day.locale = locale
        day.timeZone = SmsJSON.kuwait
        day.setLocalizedDateFormatFromTemplate("dMMM")
        return "\(day.string(from: date)) \(t)"
    }

    /// «انرسل بعد 1.3 ث من الطلب»
    static func sendDelay(_ seconds: Double) -> String {
        let n = String(format: "%.1f", seconds)
        return L10n.t("انرسل بعد \(n) ث من الطلب", "Sent \(n) s after the request")
    }

    /// «وصلت · خلال ~3 د» (علامة ✓ رمز النظام بجانبها — حرف ✓ في Plex يظهر كـ V)
    static func delivered(_ minutes: Int?) -> String {
        guard let minutes else { return L10n.t("وصلت", "Delivered") }
        if minutes <= 1 { return L10n.t("وصلت · خلال دقيقة", "Delivered · within a minute") }
        return L10n.t("وصلت · خلال ~\(minutes) د", "Delivered · within ~\(minutes) min")
    }

    static let notDelivered = L10n.t("ما وصلت", "Not delivered")
    static let pending = L10n.t("قيد التحقق…", "Checking…")

    /// «انرفض — انتظر 42 ث» · «انرفض — حاول بعد ساعة» (حد الساعة/اليوم، طلب المالك ٢٠٢٦-١٠-٢٣)
    static func blocked(_ retryAfter: Int?) -> String? {
        guard let retryAfter, retryAfter > 0 else { return nil }
        if retryAfter >= OTPWaitText.hourThreshold { return L10n.t("انرفض — حاول بعد ساعة", "Refused — try in an hour") }
        return L10n.t("انرفض — انتظر \(retryAfter) ث", "Refused — wait \(retryAfter) s")
    }

    /// عناوين أرقام `summary` المعروفة بترتيب العرض
    static let summaryKeys: [(key: String, title: String)] = [
        ("sent", L10n.t("انرسل", "Sent")),
        ("blocked", L10n.t("انرفض", "Refused")),
        ("failed", L10n.t("فشل", "Failed")),
        ("test", L10n.t("تجريبي", "Test")),
        ("unknown", L10n.t("غير معروف", "Unknown"))
    ]

    private static let clock = DateFormatter()
    private static let day = DateFormatter()
}

// MARK: - المخزن (لكل صفحة)

@MainActor
final class SmsNumberDetailsStore: ObservableObject {
    let phoneE164: String
    let days: Int
    @Published private(set) var result: SmsNumberDetails?
    @Published private(set) var loading = false
    @Published private(set) var loadingMore = false
    @Published private(set) var failed = false
    @Published private(set) var denied = false
    /// «فك القفل» (المالك): يعمل الآن · تأكيد قبل النداء · نتيجته أو خطأه
    @Published private(set) var unlocking = false
    @Published var confirmUnlock = false
    @Published var unlockNotice: SmsNotice?
    /// رموز الرقم في الفترة (المالك) — فارغة إن تعذّر الجلب
    @Published private(set) var codes: [SmsLoginCode] = []

    init(phoneE164: String, days: Int) {
        self.phoneE164 = phoneE164
        self.days = days
    }

    private struct Params: Encodable {
        let p_phone: String
        let p_days: Int
        let p_before: Int64?
    }

    private func fetch(before: Int64?) async throws -> SmsNumberDetails {
        let data = try await SupabaseConfig.client
            .rpc("owner_sms_login_details", params: Params(p_phone: phoneE164, p_days: days, p_before: before))
            .execute().data
        return try SmsNumberDetails.decode(data)
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            result = try await fetch(before: nil)
            failed = false
            denied = false
            await fetchCodes()
        } catch {
            handle(error)
        }
    }

    /// «المزيد» — الصفحة التالية بـ `next_before`
    func loadMore() async {
        guard let current = result, let before = current.nextBefore, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await fetch(before: before)
            var merged = current
            let seen = Set(current.items.map(\.id))
            merged.items += page.items.filter { !seen.contains($0.id) }
            merged.nextBefore = page.nextBefore
            result = merged
        } catch {
            handle(error)
        }
    }

    private struct CodesParams: Encodable {
        let p_phone: String
        let p_days: Int
    }

    /// رموز الرقم — أفضل جهد: أي خطأ يترك الصفوف بلا رمز
    private func fetchCodes() async {
        do {
            let data = try await SupabaseConfig.client
                .rpc("owner_number_login_codes", params: CodesParams(p_phone: phoneE164, p_days: days))
                .execute().data
            codes = SmsLoginCode.decode(data)
        } catch {
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[KWT SMS] تعذّر جلب رموز الرقم: \(error.localizedDescription)")
            }
        }
    }

    private struct PhoneParams: Encodable { let p_phone: String }

    /// مسح طلبات الرقم ورموزه بعد «فك القفل» — true إن نجح
    private func clearMessages() async -> Bool {
        do {
            _ = try await SupabaseConfig.client
                .rpc("owner_clear_number_messages", params: PhoneParams(p_phone: phoneE164))
                .execute()
            codes = []
            return true
        } catch {
            Log.warning("[KWT SMS] تعذّر مسح رسائل الرقم: \(error.localizedDescription)")
            return false
        }
    }

    /// رد `kwtsms-admin` `unlock`: `{ok, was_locked, cleared_requests}`
    nonisolated struct UnlockReply: Decodable {
        let wasLocked: Bool?
        let clearedRequests: Int?
        enum CodingKeys: String, CodingKey { case wasLocked = "was_locked"; case clearedRequests = "cleared_requests" }
    }

    /// «فك القفل» (المالك فقط، بعد التأكيد): يفك قفل الرقم ويمسح طلباته الأخيرة ثم تُعاد الصفحة
    func unlock() {
        guard !unlocking else { return }
        unlocking = true
        Task {
            defer { unlocking = false }
            do {
                let reply = try await SmsBalanceStore.shared.call("unlock", phone: phoneE164, as: UnlockReply.self)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                // فك القفل يصفّر الحدود دائماً (باليوم وبالساعة ورمز الدقيقتين — 20261023140000)، و`was_locked`
                // يخص قفل «الطلبات المتكررة» وحده؛ فالرسالة واحدة (المالك ٢٠٢٦-١٠-٢٣: «ليش يطلع ما كان مقفول»)
                // ومع التصفير تُمسح رسائله القديمة (المالك ٢٠٢٦-١٠-٢٣: «مع التصفير احذف الرسائل القديمة»)
                _ = reply
                let cleared = await clearMessages()
                unlockNotice = SmsNotice(title: L10n.t("انفك القفل", "Unlocked"),
                                         message: cleared
                                            ? L10n.t("تصفّرت حدوده وانمسحت رسائله القديمة — يقدر يطلب رمز الحين",
                                                     "Limits reset and old messages cleared — they can request a code now")
                                            : L10n.t("تصفّرت حدوده — يقدر يطلب رمز الحين",
                                                     "Its limits were reset — they can request a code now"))
                await refresh()
            } catch {
                guard !ErrorHelper.isCancellation(error) else { return }
                let e = error as? SmsAdminError ?? SmsAdminError(code: "network")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                unlockNotice = SmsNotice(title: e.title,
                                         message: e.code == "owner_only"
                                            ? L10n.t("فك القفل للمالك فقط.", "Only the owner can unlock a number.")
                                            : e.message)
            }
        }
    }

    private func handle(_ error: Error) {
        if ErrorHelper.isCancellation(error) { return }
        if (error as? PostgrestError)?.code == "42501" { denied = true; return }
        failed = true
        Log.warning("[KWT SMS] تعذّر جلب تفاصيل الرقم: \(error.localizedDescription)")
    }
}

// MARK: - الصفحة

struct SmsNumberDetailsPage: View {
    let fallbackName: String?
    @StateObject private var store: SmsNumberDetailsStore

    init(phoneE164: String, days: Int, name: String?) {
        fallbackName = name
        _store = StateObject(wrappedValue: SmsNumberDetailsStore(phoneE164: phoneE164, days: days))
    }

    var body: some View {
        AdminHubPage {
            AnyView(SmsNumberDetailsHeader(store: store, fallbackName: fallbackName))
        } content: {
            AnyView(SmsNumberDetailsContent(store: store))
        }
        .refreshable { await store.refresh() }
        .task { if store.result == nil { await store.refresh() } }
        .modifier(SmsUnlockAlerts(store: store))
    }
}

/// تأكيد «فك القفل» ثم نتيجته
private struct SmsUnlockAlerts: ViewModifier {
    @ObservedObject var store: SmsNumberDetailsStore

    func body(content: Content) -> some View {
        content
            .dsAlert(L10n.t("فك قفل هذا الرقم؟", "Unlock this number?"),
                     isPresented: $store.confirmUnlock, icon: "lock.open.fill") {
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
                Button(L10n.t("فك القفل", "Unlock")) { store.unlock() }
            } message: {
                Text(L10n.t("يقدر صاحب الرقم يطلب رمز دخول فوراً، وتنمسح طلباته الأخيرة من عدّاد القفل.",
                            "The number's owner can request a sign-in code right away, and its recent requests are cleared from the lock counter."))
            }
            .dsAlert(store.unlockNotice?.title ?? "", isPresented: Binding(
                get: { store.unlockNotice != nil },
                set: { if !$0 { store.unlockNotice = nil } }
            ), presenting: store.unlockNotice) { _ in
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: { notice in
                Text(notice.message)
            }
    }
}

private struct SmsNumberDetailsHeader: View {
    @ObservedObject var store: SmsNumberDetailsStore
    let fallbackName: String?

    var body: some View {
        AdminBandHeader(backTitle: L10n.t("طلبات رمز الدخول", "Sign-in code requests"),
                        title: name,
                        subtitle: subtitle) {
            AdminGlassButton(symbol: "arrow.clockwise", label: L10n.t("تحديث", "Refresh")) {
                Task { await store.refresh() }
            }
        } accessory: {
            EmptyView()
        }
    }

    private var name: String {
        if let n = store.result?.memberName ?? fallbackName { return PersonName.threeParts(n) }
        return L10n.t("رقم غير مسجّل", "Unregistered number")
    }

    /// «تفاصيل الرقم» + الرقم كاملاً + الفترة
    private var subtitle: String {
        let phone = SmsAttemptsText.isolatedLTR("+965 " + store.phoneE164.dropFirst(4))
        return "\(SmsDetailsText.pageTitle) · \(phone) · \(SmsAttemptsText.period(store.days))"
    }
}

private struct SmsNumberDetailsContent: View {
    @ObservedObject var store: SmsNumberDetailsStore

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if let result = store.result {
                SmsNumberSummary(result: result)
                SmsUnlockButton(store: store)
                AdminCardHeader(title: L10n.t("الطلبات", "Requests"), badge: nil, badgeTint: DS.Color.primary) {
                    Text(verbatim: "\(result.items.count)/\(result.total)")
                        .dsFont(.caption)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textTertiary)
                }
                if result.items.isEmpty {
                    DSEmptyView(L10n.t("لا طلبات في هذه الفترة", "No requests in this period"),
                                icon: "person.badge.key.fill", style: .inline)
                } else {
                    SmsNumberRequestRows(items: result.items, codes: store.codes)
                }
                if result.nextBefore != nil {
                    Button { Task { await store.loadMore() } } label: {
                        AdminPillLabel(title: store.loadingMore ? L10n.t("جاري الجلب…", "Loading…") : L10n.t("المزيد", "More"),
                                       icon: "chevron.down", style: .soft, height: DS.Hub.pillHeightCard, fullWidth: true)
                    }
                    .buttonStyle(DSPressStyle())
                    .disabled(store.loadingMore)
                }
                if store.failed {
                    DSNoteCard(L10n.t("تعذّر الجلب الآن — اسحب للتحديث.", "Couldn't load — pull to refresh."),
                               icon: "wifi.exclamationmark", tint: DS.Color.warning)
                }
                Text(L10n.t("حالة التسليم يفحصها السيرفر تلقائياً بعد 1–30 دقيقة من الإرسال، والمدة تقريبية (حتى وقت الفحص).",
                            "Delivery is checked by the server 1–30 minutes after sending; the time is approximate (up to the check)."))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if store.denied {
                DSNoteCard(L10n.t("تفاصيل الرقم للمالك فقط.", "Number details are for the owner only."),
                           icon: "lock.fill", tint: DS.Color.warning)
            } else if store.failed && !store.loading {
                DSNoteCard(L10n.t("تعذّر جلب تفاصيل الرقم الآن — اسحب للتحديث.", "Couldn't load number details — pull to refresh."),
                           icon: "wifi.exclamationmark", tint: DS.Color.warning)
            } else {
                DSPageLoader(L10n.t("جاري جلب تفاصيل الرقم…", "Loading number details…"),
                             size: DS.Icon.loaderArtInline, fillsSpace: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }
}

/// «فك القفل» — المالك فقط (الصفحة أصلاً للمالك)
private struct SmsUnlockButton: View {
    @ObservedObject var store: SmsNumberDetailsStore
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        if authVM.isOwner {
            Button { store.confirmUnlock = true } label: {
                AdminPillLabel(title: store.unlocking ? L10n.t("جاري فك القفل…", "Unlocking…") : L10n.t("فك القفل", "Unlock"),
                               icon: "lock.open", style: .soft, height: DS.Hub.pillHeightCard, fullWidth: true)
            }
            .buttonStyle(DSPressStyle())
            .disabled(store.unlocking)
            .accessibilityHint(L10n.t("يسمح للرقم يطلب رمز دخول فوراً", "Lets this number request a sign-in code right away"))
        }
    }
}

/// عدد الطلبات ونتائجها + آخر دخول + ملف العضو (إن كان في الشجرة)
private struct SmsNumberSummary: View {
    let result: SmsNumberDetails
    @EnvironmentObject var memberVM: MemberViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            OccasionFlowLayout(spacing: DS.Spacing.xs) {
                DSStatusChip(text: L10n.t("طلبات: \(result.total)", "Requests: \(result.total)"),
                             icon: "calendar", tint: DS.Color.primary)
                ForEach(SmsDetailsText.summaryKeys, id: \.key) { entry in
                    if let n = result.summary[entry.key], n > 0 {
                        let tint = SmsAttemptsText.outcome(entry.key).tint
                        DSStatusChip(text: "\(entry.title): \(n)", tint: tint)
                    }
                }
                if result.codeViewCount > 0 {
                    DSStatusChip(text: L10n.t("عرضت الرمز: \(result.codeViewCount)", "Code views: \(result.codeViewCount)"),
                                 icon: "key.fill", tint: DS.Color.slate)
                }
            }
            Text(verbatim: signInLine)
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let member = result.memberId.flatMap({ memberVM.member(byId: $0) }) {
                NavigationLink { AdminLazyPage { AnyView(AdminMemberDetailSheet(member: member)) } } label: {
                    AdminPillLabel(title: L10n.t("ملف العضو", "Member profile"), icon: "person.fill",
                                   style: .soft, height: DS.Hub.pillHeightCard, fullWidth: true)
                }
                .buttonStyle(DSPressStyle())
            }
        }
    }

    private var signInLine: String {
        guard let at = result.lastSignInAt else { return L10n.t("لم يسجّل الدخول بعد", "Hasn't signed in yet") }
        return L10n.t("آخر دخول: \(SmsDetailsText.time(at))", "Last sign-in: \(SmsDetailsText.time(at))")
    }
}

// MARK: - صفوف الطلبات

private struct SmsNumberRequestRows: View {
    let items: [SmsNumberDetails.Request]
    let codes: [SmsLoginCode]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                SmsNumberRequestRow(item: item, code: SmsLoginCode.match(item, in: codes))
                if item.id != items.last?.id { AdminRowDivider() }
            }
        }
    }
}

/// صفّ طلب: الوقت + النتيجة، ثم للمُرسَل «انرسل بعد…» وسطر التسليم، وللمرفوض «انتظر N ث»
private struct SmsNumberRequestRow: View {
    let item: SmsNumberDetails.Request
    /// رمز هذه الرسالة وحالته (المالك)
    let code: SmsLoginCode?

    var body: some View {
        let outcome = SmsAttemptsText.outcome(item.outcome)
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                Text(verbatim: SmsDetailsText.time(item.recordedAt))
                    .dsFont(.hubRow)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textPrimary)
                Spacer(minLength: DS.Spacing.sm)
                DSStatusChip(text: outcome.title, icon: outcome.icon, tint: outcome.tint, size: .mini)
            }
            if item.outcome == "sent" {
                if let delay = SmsDelivery.sendDelay(item) {
                    SmsDetailLine(text: SmsDetailsText.sendDelay(delay), icon: "timer", tint: DS.Color.textSecondary)
                }
                SmsDeliveryLine(item: item)
                if let code {
                    SmsDetailLine(text: code.valid
                                    ? L10n.t("الرمز \(code.code) · صالح", "Code \(code.code) · valid")
                                    : L10n.t("الرمز \(code.code) · منتهي", "Code \(code.code) · expired"),
                                  icon: "key.fill",
                                  tint: code.valid ? DS.Color.success : DS.Color.textSecondary)
                }
            } else if item.outcome == "blocked", let text = SmsDetailsText.blocked(item.retryAfterSeconds) {
                SmsDetailLine(text: text, icon: "hourglass", tint: DS.Color.warning.dsReadableGlyph)
            } else if item.outcome == "failed", let code = item.errorCode {
                SmsDetailLine(text: SmsText.errorLine(code), icon: "exclamationmark.triangle.fill",
                              tint: DS.Color.error)
            }
        }
        .padding(.vertical, DS.Spacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// سطر صغير برمز
private struct SmsDetailLine: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
            Image(dsSymbol: icon)
                .dsGlyph(DS.Glyph.sm)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .dsFont(.footnote)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(tint)
    }
}

/// وصلت ✓ · ما وصلت (مع الحالة) · قيد التحقق…
private struct SmsDeliveryLine: View {
    let item: SmsNumberDetails.Request

    var body: some View {
        switch SmsDelivery.of(item) {
        case .delivered(let minutes):
            SmsDetailLine(text: SmsDetailsText.delivered(minutes), icon: "checkmark.circle.fill",
                          tint: DS.Color.success.dsReadableGlyph)
        case .notDelivered(let raw):
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                SmsDetailLine(text: SmsDetailsText.notDelivered, icon: "xmark.circle.fill", tint: DS.Color.error)
                Text(verbatim: "\(SmsText.isolate(raw)) · \(SmsText.deliveryStatus(raw))")
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .pending:
            SmsDetailLine(text: pendingText, icon: "clock", tint: DS.Color.textTertiary)
        }
    }

    /// حالة وسيطة معروفة («Sent») تُذكر بجانب «قيد التحقق…»
    private var pendingText: String {
        guard let raw = item.queueStatus else { return SmsDetailsText.pending }
        return "\(SmsDetailsText.pending) · \(SmsText.isolate(raw))"
    }
}
