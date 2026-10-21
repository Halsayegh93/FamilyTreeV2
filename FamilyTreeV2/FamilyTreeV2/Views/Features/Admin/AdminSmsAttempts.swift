import SwiftUI
import Supabase
import Combine
import UniformTypeIdentifiers

// MARK: - «محاولات الدخول» في صفحة «رسائل الدخول · KWT SMS» (طلب المالك ٢٠٢٦-١٠-٢٠ «منو حاول يدخل وكم مرة؟»)
//
// `sms_login_attempts(p_days 1…30)` (المالك والمدير، غيرهما 42501): سطر لكل رقم طلب رمز دخول في الفترة (الأحدث أولاً،
// أقصى ٢٠٠) — العدد اليوم/في الفترة، آخر نتيجة، هل دخل بعدها، و«مريب» (٥ أو أكثر في ساعة). الرقم كاملاً للمالك
// (`phone_e164` للنسخ والاتصال)، ومخفياً للمدير («+965 5000••34») — السيرفر يقرّر، التطبيق يعرض فقط.
// يُحفظ ٣٠ يوماً. العدّ بدأ ٢٠ أكتوبر ٢٠٢٦.
// «اعرض الرمز» للمالك وحده (طلب المالك ٢٠٢٦-١٠-٢١ «اذا في خطا ممكن اعطيه لصاحب الرقم»، 20261021080000):
// `owner_login_codes` = الأرقام التي لها رمز صالح الآن (بلا الرمز) + آخر عرض، و`owner_reveal_login_code` يرجع الرمز
// ويُسجَّل كل نداء. الرمز يعيش ٥ دقائق في السيرفر ويبطل بالدخول؛ المدير يأخذ 42501 فلا يظهر له شيء.
// حارس المكدس: البطاقة نوع مستقل خلف `AnyView` في `AdminSmsView`، والصفحة الكاملة خلف `AdminLazyPage`.

/// ما ترجعه `sms_login_attempts(p_days)` — فكّ متسامح كالنظرة
struct SmsLoginAttempts: Equatable {
    struct Totals: Equatable {
        var phones = 0, attempts = 0, unknownNumbers = 0, suspicious = 0
    }

    struct Item: Equatable, Identifiable {
        /// ترتيبه في الرد (المخفي قد يتكرر بين رقمين)
        var id = 0
        /// كما يرجع: كامل للمالك، مخفي للمدير
        var phone = ""
        /// للمالك فقط (نسخ/اتصال)
        var phoneE164: String?
        var profileId: UUID?
        var name: String?
        var isMember = false
        var memberStatus: String?
        var attemptsToday = 0, attemptsInWindow = 0
        var sent = 0, blocked = 0, failed = 0, unknown = 0, test = 0
        var firstAt: Date?
        var lastAt: Date?
        /// sent · blocked · failed · unknown · test
        var lastOutcome = "unknown"
        var loggedIn = false
        var lastSignInAt: Date?
        var maxInHour = 0
        var suspicious = false
    }

    var days = 7
    var masked = true
    var retentionDays = 30
    var generatedAt: Date?
    var totals = Totals()
    var items: [Item] = []

    /// أقصى ما يرجعه السيرفر من الأرقام
    static let itemCap = 200

    static func decode(_ data: Data) throws -> SmsLoginAttempts {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        var r = SmsLoginAttempts()
        r.days = SmsJSON.int(root["days"]) ?? 7
        r.masked = root["masked"] as? Bool ?? true
        r.retentionDays = SmsJSON.int(root["retention_days"]) ?? 30
        r.generatedAt = ApprovalWorkflow.date(root["generated_at"] as? String)
        if let t = root["totals"] as? [String: Any] {
            r.totals = Totals(phones: SmsJSON.int(t["phones"]) ?? 0, attempts: SmsJSON.int(t["attempts"]) ?? 0,
                              unknownNumbers: SmsJSON.int(t["unknown_numbers"]) ?? 0,
                              suspicious: SmsJSON.int(t["suspicious"]) ?? 0)
        }
        r.items = (root["items"] as? [[String: Any]] ?? []).enumerated().map { i, x in
            Item(id: i,
                 phone: x["phone"] as? String ?? "—",
                 phoneE164: (x["phone_e164"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                 profileId: (x["profile_id"] as? String).flatMap(UUID.init(uuidString:)),
                 name: (x["name"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 },
                 isMember: x["is_member"] as? Bool ?? false,
                 memberStatus: x["member_status"] as? String,
                 attemptsToday: SmsJSON.int(x["attempts_today"]) ?? 0,
                 attemptsInWindow: SmsJSON.int(x["attempts_in_window"]) ?? 0,
                 sent: SmsJSON.int(x["sent"]) ?? 0, blocked: SmsJSON.int(x["blocked"]) ?? 0,
                 failed: SmsJSON.int(x["failed"]) ?? 0, unknown: SmsJSON.int(x["unknown"]) ?? 0,
                 test: SmsJSON.int(x["test"]) ?? 0,
                 firstAt: ApprovalWorkflow.date(x["first_at"] as? String),
                 lastAt: ApprovalWorkflow.date(x["last_at"] as? String),
                 lastOutcome: x["last_outcome"] as? String ?? "unknown",
                 loggedIn: x["logged_in"] as? Bool ?? false,
                 lastSignInAt: ApprovalWorkflow.date(x["last_sign_in_at"] as? String),
                 maxInHour: SmsJSON.int(x["max_in_hour"]) ?? 0,
                 suspicious: x["suspicious"] as? Bool ?? false)
        }
        return r
    }
}

/// ما ترجعه `owner_login_codes(p_days)` — للمالك فقط
struct OwnerLoginCodes: Equatable {
    struct Seen: Equatable {
        var lastAt: Date?
        var count = 0
    }

    /// `phone_e164` ← وقت انتهاء الرمز الصالح
    var expiries: [String: Date] = [:]
    /// `phone_e164` ← آخر «اعرض الرمز» وعدده في الفترة
    var views: [String: Seen] = [:]

    static func decode(_ data: Data) throws -> OwnerLoginCodes {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        var r = OwnerLoginCodes()
        for x in root["codes"] as? [[String: Any]] ?? [] {
            if let phone = x["phone_e164"] as? String, let at = ApprovalWorkflow.date(x["expires_at"] as? String) {
                r.expiries[phone] = at
            }
        }
        for x in root["views"] as? [[String: Any]] ?? [] {
            if let phone = x["phone_e164"] as? String {
                r.views[phone] = Seen(lastAt: ApprovalWorkflow.date(x["last_viewed_at"] as? String),
                                      count: SmsJSON.int(x["count"]) ?? 0)
            }
        }
        return r
    }
}

/// ما ترجعه `owner_reveal_login_code(p_phone)`
struct OwnerCodeReveal: Equatable {
    /// shown · used · expired · none
    var status = "none"
    var code: String?
    var expiresAt: Date?

    static func decode(_ data: Data) throws -> OwnerCodeReveal {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        return OwnerCodeReveal(status: root["status"] as? String ?? "none",
                               code: (root["code"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                               expiresAt: ApprovalWorkflow.date(root["expires_at"] as? String))
    }
}

// MARK: - المخزن

/// المحاولات لكل فترة (اليوم / ٧ / ٣٠) — مشترك بين البطاقة والصفحة الكاملة
@MainActor
final class SmsLoginAttemptsStore: ObservableObject {
    static let shared = SmsLoginAttemptsStore()
    /// فترات المبدّل بالأيام
    static let periods = [1, 7, 30]

    /// الفترة المختارة
    @Published private(set) var days = 7
    @Published var results: [Int: SmsLoginAttempts] = [:]
    @Published private(set) var loading: Set<Int> = []
    @Published private(set) var failed: Set<Int> = []
    @Published private(set) var denied = false
    /// للمالك فقط — يبقى فاضياً للمدير
    @Published var ownerCodes = OwnerLoginCodes()
    private var fetchedAt: [Int: Date] = [:]
    private var ownerCodesAt: Date?

    var current: SmsLoginAttempts? { results[days] }
    var isLoading: Bool { loading.contains(days) }
    var isFailed: Bool { failed.contains(days) }

    func select(_ period: Int) {
        guard period != days else { return }
        days = period
        Task { await refresh() }
    }

    /// يجلب الفترة المختارة — لا يُكرَّر خلال دقيقة إلا بالسحب للتحديث
    func refresh(force: Bool = false) async {
        let period = days
        if !force, let at = fetchedAt[period], Date().timeIntervalSince(at) < 60 {
            await refreshOwnerCodes()
            return
        }
        guard !loading.contains(period) else { return }
        fetchedAt[period] = Date()
        loading.insert(period)
        defer { loading.remove(period) }
        do {
            let data = try await SupabaseConfig.client
                .rpc("sms_login_attempts", params: ["p_days": period])
                .execute().data
            results[period] = try SmsLoginAttempts.decode(data)
            failed.remove(period)
            denied = false
            await refreshOwnerCodes(force: force)
        } catch {
            if ErrorHelper.isCancellation(error) { fetchedAt[period] = nil; return }
            if (error as? PostgrestError)?.code == "42501" { denied = true; return }
            failed.insert(period)
            Log.warning("[KWT SMS] تعذّر جلب محاولات الدخول: \(error.localizedDescription)")
        }
    }

    /// الأرقام التي لها رمز صالح + آخر عرض — للمالك فقط (الرد غير المخفي)، ولا يتكرر خلال ١٠ ثوانٍ
    func refreshOwnerCodes(force: Bool = false) async {
        guard current?.masked == false else { return }
        if !force, let at = ownerCodesAt, Date().timeIntervalSince(at) < 10 { return }
        ownerCodesAt = Date()
        do {
            let data = try await SupabaseConfig.client
                .rpc("owner_login_codes", params: ["p_days": days])
                .execute().data
            ownerCodes = try OwnerLoginCodes.decode(data)
        } catch {
            if ErrorHelper.isCancellation(error) { ownerCodesAt = nil; return }
            Log.warning("[KWT SMS] تعذّر جلب رموز الدخول الصالحة: \(error.localizedDescription)")
        }
    }

    /// «اعرض الرمز» — يُسجَّل في السيرفر مع كل نداء، ثم يُحدَّث سطر «عرضت الرمز»
    func reveal(_ phoneE164: String) async throws -> OwnerCodeReveal {
        let data = try await SupabaseConfig.client
            .rpc("owner_reveal_login_code", params: ["p_phone": phoneE164])
            .execute().data
        let reply = try OwnerCodeReveal.decode(data)
        await refreshOwnerCodes(force: true)
        return reply
    }
}

// MARK: - النصوص

enum SmsAttemptsText {
    static func period(_ days: Int) -> String {
        switch days {
        case 1: return L10n.t("اليوم", "Today")
        case 7: return L10n.t("7 أيام", "7 days")
        default: return L10n.t("\(days) يوماً", "\(days) days")
        }
    }

    /// آخر نتيجة بكلام مفهوم
    static func outcome(_ raw: String) -> (title: String, icon: String, tint: Color) {
        switch raw {
        case "sent":    return (L10n.t("انرسل", "Sent"), "paperplane.fill", DS.Color.success)
        case "blocked": return (L10n.t("انرفض لكثرة الطلب", "Refused: too many requests"), "hand.raised.fill", DS.Color.warning)
        case "failed":  return (L10n.t("فشل", "Failed"), "xmark.circle.fill", DS.Color.error)
        case "test":    return (L10n.t("تجريبي", "Test"), "flask.fill", DS.Color.info)
        default:        return (L10n.t("غير معروف", "Unknown"), "questionmark.circle.fill", DS.Color.slate)
        }
    }

    /// «قبل 5 دقائق» — أرقام لاتينية كبقية اللوحة
    static func relative(_ date: Date?) -> String? {
        guard let date else { return nil }
        relativeFormatter.locale = Locale(identifier: L10n.isArabic ? "ar@numbers=latn" : "en")
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// يعزل الرقم اللاتيني داخل سطر عربي (يبقى «+965 …» بترتيبه)
    static func isolatedLTR(_ text: String) -> String { "\u{2066}\(text)\u{2069}" }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}

// MARK: - البطاقة

/// «محاولات الدخول»: مبدّل الفترة، المجاميع، أول ٨ أرقام و«الكل»، وسطر الحفظ
struct SmsAttemptsCard: View {
    @ObservedObject private var store = SmsLoginAttemptsStore.shared
    /// قسم صفحة الرسائل — يُمرَّر لصفحة «الكل»
    @Environment(\.adminArea) private var area
    /// الصفوف الظاهرة قبل «الكل»
    private static let collapsedCount = 8

    var body: some View {
        let result = store.current
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            AdminCardHeader(title: L10n.t("طلبات رمز الدخول", "Sign-in code requests"),
                            badge: result?.totals.suspicious, badgeTint: DS.Color.warning) {
                if let result, !result.items.isEmpty {
                    NavigationLink { AdminLazyPage { AnyView(SmsAttemptsListPage().adminArea(area)) } } label: {
                        AdminCardLinkLabel(title: L10n.t("الكل (\(result.items.count))", "All (\(result.items.count))"))
                    }
                    .buttonStyle(.plain)
                }
            }
            SmsAttemptsPeriodSwitch(store: store)
            if let result {
                SmsAttemptsTotalsView(totals: result.totals)
                if result.items.isEmpty {
                    SmsAttemptsEmpty()
                } else {
                    SmsAttemptsRows(items: Array(result.items.prefix(Self.collapsedCount)), days: result.days)
                }
                SmsAttemptsNote(result: result)
            } else {
                SmsAttemptsStatus(store: store)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
        .task { await store.refresh() }
    }
}

/// اليوم / ٧ أيام / ٣٠ يوماً
private struct SmsAttemptsPeriodSwitch: View {
    @ObservedObject var store: SmsLoginAttemptsStore

    var body: some View {
        DSSegmentedSwitch(options: [
            DSSegmentOption(id: 1, title: SmsAttemptsText.period(1), icon: "sun.max.fill"),
            DSSegmentOption(id: 7, title: SmsAttemptsText.period(7), icon: "calendar"),
            DSSegmentOption(id: 30, title: SmsAttemptsText.period(30), icon: "calendar.badge.clock")
        ], selection: Binding(get: { store.days }, set: { store.select($0) }), size: .regular)
    }
}

/// بلا بيانات للفترة بعد: جارٍ الجلب، أو تعذّر، أو غير مسموح
private struct SmsAttemptsStatus: View {
    @ObservedObject var store: SmsLoginAttemptsStore

    var body: some View {
        if store.denied {
            DSNoteCard(L10n.t("طلبات رمز الدخول للمالك والمدير فقط.", "Sign-in code requests are for the owner and admins only."),
                       icon: "lock.fill", tint: DS.Color.warning)
        } else if store.isFailed && !store.isLoading {
            DSNoteCard(L10n.t("تعذّر جلب طلبات رمز الدخول الآن — اسحب للتحديث.",
                              "Couldn't load sign-in attempts — pull to refresh."),
                       icon: "wifi.exclamationmark", tint: DS.Color.warning)
        } else {
            DSPageLoader(L10n.t("جاري جلب طلبات رمز الدخول…", "Loading sign-in code requests…"),
                         size: DS.Icon.loaderArtInline, fillsSpace: false)
        }
    }
}

/// أرقام · محاولات · غير مسجّلة · مريبة — صفّ واحد، ومربّعان بمربّعين مع الخط الكبير
private struct SmsAttemptsTotalsView: View {
    let totals: SmsLoginAttempts.Totals
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize >= .xxLarge {
                VStack(spacing: DS.Spacing.sm) {
                    HStack(alignment: .top, spacing: DS.Spacing.sm) { phones; attempts }
                    HStack(alignment: .top, spacing: DS.Spacing.sm) { unknown; suspicious }
                }
            } else {
                HStack(alignment: .top, spacing: DS.Spacing.sm) { phones; attempts; unknown; suspicious }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var phones: some View {
        SmsAttemptsStat(value: totals.phones, label: L10n.t("أرقام", "Numbers"))
    }
    private var attempts: some View {
        SmsAttemptsStat(value: totals.attempts, label: L10n.t("طلبات", "Requests"))
    }
    private var unknown: some View {
        SmsAttemptsStat(value: totals.unknownNumbers, label: L10n.t("غير مسجّلة", "Not registered"))
    }
    private var suspicious: some View {
        SmsAttemptsStat(value: totals.suspicious, label: L10n.t("مشبوهة", "Suspicious"), warns: totals.suspicious > 0)
    }
}

private struct SmsAttemptsStat: View {
    let value: Int
    let label: String
    /// «مريبة» بلون التحذير متى زادت على صفر
    var warns = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(verbatim: "\(value)")
                .dsFont(.statValue)
                .monospacedDigit()
                .foregroundColor(warns ? DS.Color.warning.dsReadableGlyph : DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Hub.kpiPadding)
        .background(RoundedRectangle(cornerRadius: DS.Hub.kpiRadius, style: .continuous).fill(DS.Color.cardBackgroundSoft))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// «ما في محاولات في هذه الفترة — العدّ بدأ من 20 أكتوبر»
private struct SmsAttemptsEmpty: View {
    var body: some View {
        DSEmptyView(L10n.t("لا طلبات في هذه الفترة", "No requests in this period"),
                    message: L10n.t("العدّ بدأ من 20 أكتوبر", "Counting started on 20 October"),
                    icon: "person.badge.key.fill", style: .inline)
    }
}

/// «يُحفظ 30 يوماً · رمز الدخول لا يُحفظ أبداً» (+ الإخفاء للمدير، + سقف ٢٠٠)
private struct SmsAttemptsNote: View {
    let result: SmsLoginAttempts

    var body: some View {
        var parts = [L10n.t("يُحفظ \(SmsText.days(result.retentionDays))", "Kept \(SmsText.days(result.retentionDays))"),
                     result.masked
                        ? L10n.t("رمز الدخول لا يظهر للمدراء", "Sign-in codes aren't shown to admins")
                        : L10n.t("رمز الدخول يظهر لك وحدك خلال صلاحيته (5 دقائق)",
                                 "Sign-in codes show for you only while valid (5 minutes)")]
        if result.masked {
            parts.append(L10n.t("الأرقام مخفية جزئياً — كاملة للمالك", "Numbers partly hidden — full for the owner"))
        }
        if result.items.count >= SmsLoginAttempts.itemCap {
            parts.append(L10n.t("يظهر أحدث \(SmsLoginAttempts.itemCap) رقم", "Latest \(SmsLoginAttempts.itemCap) numbers shown"))
        }
        return Text(verbatim: parts.joined(separator: " · "))
            .dsFont(.footnote)
            .foregroundColor(DS.Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - الصفوف

/// الصفوف مفصولة بخط رفيع
private struct SmsAttemptsRows: View {
    let items: [SmsLoginAttempts.Item]
    let days: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                SmsAttemptRow(item: item, days: days)
                if item.id != items.last?.id { AdminRowDivider() }
            }
        }
    }
}

/// صفّ رقم + سطر «اعرض الرمز» للمالك تحته (خارج رابط الصف حتى لا تبتلع الضغطةَ)
private struct SmsAttemptRow: View {
    let item: SmsLoginAttempts.Item
    let days: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SmsAttemptRowMain(item: item, days: days)
            if let e164 = item.phoneE164 {
                SmsOwnerCodeLine(phoneE164: e164, name: item.name.map(PersonName.threeParts) ?? item.phone)
            }
        }
    }
}

/// صفّ رقم: الاسم (أو «رقم غير مسجّل»)، الرقم وآخر وقت، ثم الشارات. العضو يفتح ملفه؛ للمالك نسخ/اتصال
private struct SmsAttemptRowMain: View {
    let item: SmsLoginAttempts.Item
    let days: Int
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        let member = item.profileId.flatMap { memberVM.member(byId: $0) }
        Group {
            if let member {
                NavigationLink { AdminLazyPage { AnyView(AdminMemberDetailSheet(member: member)) } } label: {
                    content(name: member.shortFullName, navigates: true)
                }
                .buttonStyle(.plain)
            } else if item.phoneE164 != nil {
                // رقم بلا ملف: الضغط نفسه يفتح «نسخ الرقم / اتصال» (المالك)
                Menu { phoneActions } label: { content(name: displayName, navigates: false) }
                    .buttonStyle(.plain)
            } else {
                content(name: displayName, navigates: false)
            }
        }
        .modifier(SmsPhoneContextMenu(enabled: item.phoneE164 != nil && member != nil) { phoneActions })
    }

    /// الاسم من الرد (ثلاثي) — أو «رقم غير مسجّل»
    private var displayName: String {
        item.name.map(PersonName.threeParts) ?? L10n.t("رقم غير مسجّل", "Unregistered number")
    }

    private func content(name: String, navigates: Bool) -> some View {
        let registered = item.profileId != nil || item.name != nil
        return HStack(alignment: .top, spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: registered ? "person.fill" : "person.fill.questionmark",
                            tint: item.suspicious ? DS.Color.warning : registered ? DS.Color.palm : DS.Color.slate)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(name)
                    .dsFont(.hubRow)
                    .foregroundColor(registered ? DS.Color.textPrimary : DS.Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .dsNameLines()
                Text(verbatim: phoneLine)
                    .dsFont(.footnote)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                OccasionFlowLayout(spacing: DS.Spacing.xs) { chips }
            }
            Spacer(minLength: 0)
            if navigates { DSChevron().padding(.top, DS.Spacing.sm) }
        }
        .padding(.vertical, DS.Spacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// «+965 50001234 · قبل 5 دقائق» — الرقم معزول بترتيبه داخل السطر العربي
    private var phoneLine: String {
        var parts = [SmsAttemptsText.isolatedLTR(item.phone)]
        if let when = SmsAttemptsText.relative(item.lastAt) { parts.append(when) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var chips: some View {
        if days > 1 && item.attemptsToday > 0 {
            DSStatusChip(text: L10n.t("اليوم: \(item.attemptsToday)", "Today: \(item.attemptsToday)"),
                         icon: "clock.fill", tint: DS.Color.primary, size: .mini)
        }
        DSStatusChip(text: "\(SmsAttemptsText.period(days)): \(days == 1 ? item.attemptsToday : item.attemptsInWindow)",
                     icon: "calendar", tint: DS.Color.primary, size: .mini)
        if item.loggedIn {
            // «دخل ✓» — العلامة رمز النظام (حرف ✓ في خط Plex يظهر كـ V)
            DSStatusChip(text: L10n.t("ناجحة", "Signed in"), icon: "checkmark", tint: DS.Color.success, size: .mini)
        } else {
            DSStatusChip(text: L10n.t("لم يسجّل الدخول", "Didn't sign in"), tint: DS.Color.slate, size: .mini)
        }
        if item.suspicious {
            DSStatusChip(text: L10n.t("مشبوهة", "Suspicious"), icon: "exclamationmark.triangle.fill",
                         tint: DS.Color.warning, size: .mini)
                .accessibilityLabel(L10n.t("مشبوهة: \(item.maxInHour) طلبات في ساعة واحدة",
                                           "Suspicious: \(item.maxInHour) attempts in one hour"))
        }
        let outcome = SmsAttemptsText.outcome(item.lastOutcome)
        DSStatusChip(text: outcome.title, icon: outcome.icon, tint: outcome.tint, size: .mini)
    }

    @ViewBuilder private var phoneActions: some View {
        if let e164 = item.phoneE164 {
            Button {
                UIPasteboard.general.string = e164
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Label(L10n.t("نسخ الرقم", "Copy number"), systemImage: "doc.on.doc")
            }
            if let url = KuwaitPhone.telURL(e164) {
                Button { openURL(url) } label: {
                    Label(L10n.t("اتصال", "Call"), systemImage: "phone.fill")
                }
            }
        }
    }
}

// MARK: - «اعرض الرمز» (المالك)

/// للمالك: زر «اعرض الرمز» ما دام للرقم رمز صالح، وسطر «عرضت الرمز» بعد أي عرض — لا شيء غير ذلك
private struct SmsOwnerCodeLine: View {
    let phoneE164: String
    let name: String
    @ObservedObject private var store = SmsLoginAttemptsStore.shared
    @State private var target: SmsRevealTarget?

    var body: some View {
        let expiry = store.ownerCodes.expiries[phoneE164]
        let seen = store.ownerCodes.views[phoneE164]
        if expiry != nil || seen != nil {
            HStack(spacing: DS.Spacing.sm) {
                if expiry != nil {
                    DSChipButton(L10n.t("اعرض الرمز", "Show code"), icon: "key.fill", size: .small) {
                        target = SmsRevealTarget(id: phoneE164, name: name)
                    }
                }
                if let seen, let when = SmsAttemptsText.relative(seen.lastAt) {
                    Text(verbatim: seen.count > 1
                         ? L10n.t("عرضت الرمز \(when) · \(seen.count) مرات", "You viewed the code \(when) · \(seen.count) times")
                         : L10n.t("عرضت الرمز \(when)", "You viewed the code \(when)"))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, DS.Spacing.sm + 2)
            .padding(.leading, DS.Icon.row + DS.Spacing.md)
            .dsCenterBox(item: $target) { target in
                AnyView(SmsRevealCodeBox(target: target))
            }
        }
    }
}

struct SmsRevealTarget: Identifiable {
    /// `phone_e164`
    let id: String
    let name: String
}

/// الرمز كبيراً + الوقت الباقي + «نسخ الرمز» — العرض نفسه يُسجَّل في السيرفر
struct SmsRevealCodeBox: View {
    let target: SmsRevealTarget
    @Environment(\.dismiss) private var dismiss
    @State private var reply: OwnerCodeReveal?
    @State private var failed = false
    @State private var copied = false

    var body: some View {
        DSComposer(title: L10n.t("رمز الدخول", "Sign-in code"),
                   subtitle: "\(target.name) · \(SmsAttemptsText.isolatedLTR("+965 " + target.id.dropFirst(4)))",
                   icon: "key.fill", tint: DS.Color.actionNavy,
                   actionTitle: "", showsAction: false, cancelTitle: L10n.t("إغلاق", "Close"),
                   canSubmit: false, onSubmit: {}, onCancel: { dismiss() }) {
            if let reply, reply.status == "shown", let code = reply.code, let expiresAt = reply.expiresAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    codeSection(code: code, expiresAt: expiresAt, now: context.date)
                }
                DSNoteCard(L10n.t("أعطه لصاحب الرقم فقط إذا هو اللي تواصل معك. كل عرض ينكتب في السجل.",
                                  "Give it only to the number's owner if they contacted you. Every view is logged."),
                           icon: "hand.raised.fill", tint: DS.Color.warning)
            } else if let reply {
                DSNoteCard(statusText(reply.status), icon: "clock.badge.xmark", tint: DS.Color.slate)
            } else if failed {
                DSNoteCard(L10n.t("تعذّر جلب الرمز الآن — حاول مرة ثانية.", "Couldn't load the code — try again."),
                           icon: "wifi.exclamationmark", tint: DS.Color.warning)
            } else {
                DSPageLoader(L10n.t("جاري جلب الرمز…", "Loading the code…"), size: DS.Icon.loaderArtInline, fillsSpace: false)
            }
        }
        .task { if reply == nil { await load() } }
    }

    init(target: SmsRevealTarget, reply: OwnerCodeReveal? = nil) {
        self.target = target
        _reply = State(initialValue: reply)
    }

    private func codeSection(code: String, expiresAt: Date, now: Date) -> some View {
        let left = max(0, Int(expiresAt.timeIntervalSince(now).rounded(.up)))
        return DSComposerSection(title: L10n.t("الرمز", "Code"), icon: "key.fill", index: 0) {
            if left > 0 {
                Text(verbatim: code)
                    .dsFont(.codeDigit)
                    .monospacedDigit()
                    .tracking(DS.Spacing.sm)
                    .foregroundColor(DS.Color.textPrimary)
                    .environment(\.layoutDirection, .leftToRight)
                    .frame(maxWidth: .infinity)
                    .textSelection(.enabled)
                    .accessibilityLabel(code.map(String.init).joined(separator: " "))
                Text(L10n.t("ينتهي بعد \(left / 60):\(String(format: "%02d", left % 60))",
                            "Expires in \(left / 60):\(String(format: "%02d", left % 60))"))
                    .dsFont(.footnote)
                    .monospacedDigit()
                    .foregroundColor(left <= 60 ? DS.Color.warning.dsReadableGlyph : DS.Color.textSecondary)
                    .frame(maxWidth: .infinity)
                DSButton(copied ? L10n.t("تم النسخ", "Copied") : L10n.t("نسخ الرمز", "Copy code"),
                         icon: copied ? "checkmark" : "doc.on.doc") {
                    copy(code, until: expiresAt)
                }
            } else {
                DSNoteCard(statusText("expired"), icon: "clock.badge.xmark", tint: DS.Color.slate)
            }
        }
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case "used": return L10n.t("صاحب الرقم دخل بهذا الرمز — ما عاد يصلح.", "The number's owner already signed in — the code no longer works.")
        case "expired": return L10n.t("انتهت صلاحية الرمز (5 دقائق). خلّه يطلب رمزاً جديداً.", "The code expired (5 minutes). Ask them to request a new one.")
        default: return L10n.t("ما في رمز صالح لهذا الرقم الآن.", "There's no valid code for this number right now.")
        }
    }

    /// للجهاز فقط (لا ينتقل لأجهزة آبل الأخرى) ويُمسح من الحافظة عند انتهاء الرمز
    private func copy(_ code: String, until expiresAt: Date) {
        UIPasteboard.general.setItems([[UTType.plainText.identifier: code]],
                                      options: [.localOnly: true, .expirationDate: expiresAt])
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        copied = true
    }

    private func load() async {
        do {
            reply = try await SmsLoginAttemptsStore.shared.reveal(target.id)
        } catch {
            guard !ErrorHelper.isCancellation(error) else { return }
            failed = true
            Log.warning("[KWT SMS] تعذّر عرض رمز الدخول: \(error.localizedDescription)")
        }
    }
}

/// ضغطة مطوّلة «نسخ الرقم / اتصال» على صفّ العضو (المالك) — بلا قائمة فارغة لغيره
private struct SmsPhoneContextMenu<Actions: View>: ViewModifier {
    let enabled: Bool
    @ViewBuilder var actions: () -> Actions

    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu { actions() }
        } else {
            content
        }
    }
}

// MARK: - الصفحة الكاملة

/// كل الأرقام في الفترة مع بحث بالاسم أو الرقم
struct SmsAttemptsListPage: View {
    @ObservedObject private var store = SmsLoginAttemptsStore.shared
    @State private var query = ""

    var body: some View {
        AdminHubPage {
            AnyView(SmsAttemptsListHeader(query: $query, store: store))
        } content: {
            AnyView(SmsAttemptsListContent(store: store, query: query))
        }
        .refreshable { await store.refresh(force: true) }
        .task { await store.refresh() }
    }
}

private struct SmsAttemptsListHeader: View {
    @Binding var query: String
    @ObservedObject var store: SmsLoginAttemptsStore

    var body: some View {
        AdminBandHeader(backTitle: L10n.t("رسائل رمز الدخول", "Sign-in code messages"),
                        title: L10n.t("طلبات رمز الدخول", "Sign-in code requests"),
                        subtitle: L10n.t("من طلب رمز دخول، وكم مرة", "Who asked for a sign-in code, and how often")) {
            AdminGlassButton(symbol: "arrow.clockwise", label: L10n.t("تحديث", "Refresh")) {
                Task { await store.refresh(force: true) }
            }
        } accessory: {
            DSSearchField(text: $query, placeholder: L10n.t("بحث بالاسم أو الرقم", "Name or number"))
                .padding(.top, DS.Spacing.md)
        }
    }
}

private struct SmsAttemptsListContent: View {
    @ObservedObject var store: SmsLoginAttemptsStore
    let query: String
    @EnvironmentObject var memberVM: MemberViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SmsAttemptsPeriodSwitch(store: store)
            if let result = store.current {
                SmsAttemptsTotalsView(totals: result.totals)
                let rows = filtered(result.items)
                if result.items.isEmpty {
                    SmsAttemptsEmpty()
                } else if rows.isEmpty {
                    DSEmptyView(L10n.t("لا نتائج", "No results"), message: L10n.t("جرّب اسماً أو رقماً آخر", "Try another name or number"),
                                icon: "magnifyingglass", style: .inline)
                } else {
                    SmsAttemptsRows(items: rows, days: result.days)
                }
                SmsAttemptsNote(result: result)
            } else {
                SmsAttemptsStatus(store: store)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    /// بالاسم (من الرد أو من الشجرة) أو بخانات الرقم الظاهرة
    private func filtered(_ items: [SmsLoginAttempts.Item]) -> [SmsLoginAttempts.Item] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        let needle = ArabicTextNormalizer.normalizeForSearch(q)
        let digits = KuwaitPhone.normalizeDigits(q).filter(\.isNumber)
        return items.filter { item in
            let names = [item.name, item.profileId.flatMap { memberVM.member(byId: $0)?.fullName }].compactMap { $0 }
            if !needle.isEmpty, names.contains(where: { ArabicTextNormalizer.normalizeForSearch($0).contains(needle) }) {
                return true
            }
            guard !digits.isEmpty else { return false }
            return [item.phone, item.phoneE164 ?? ""].contains { $0.filter(\.isNumber).contains(digits) }
        }
    }
}
