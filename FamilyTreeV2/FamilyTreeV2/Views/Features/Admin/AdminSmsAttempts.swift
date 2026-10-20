import SwiftUI
import Supabase
import Combine

// MARK: - «محاولات الدخول» في صفحة «رسائل الدخول · KWT SMS» (طلب المالك ٢٠٢٦-١٠-٢٠ «منو حاول يدخل وكم مرة؟»)
//
// `sms_login_attempts(p_days 1…30)` (المالك والمدير، غيرهما 42501): سطر لكل رقم طلب رمز دخول في الفترة (الأحدث أولاً،
// أقصى ٢٠٠) — العدد اليوم/في الفترة، آخر نتيجة، هل دخل بعدها، و«مريب» (٥ أو أكثر في ساعة). الرقم كاملاً للمالك
// (`phone_e164` للنسخ والاتصال)، ومخفياً للمدير («+965 5000••34») — السيرفر يقرّر، التطبيق يعرض فقط.
// يُحفظ ٣٠ يوماً، والرمز نفسه لا يُحفظ أبداً (لا شيء هنا يوحي بأنه يُرى). العدّ بدأ ٢٠ أكتوبر ٢٠٢٦.
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
    private var fetchedAt: [Int: Date] = [:]

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
        if !force, let at = fetchedAt[period], Date().timeIntervalSince(at) < 60 { return }
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
        } catch {
            if ErrorHelper.isCancellation(error) { fetchedAt[period] = nil; return }
            if (error as? PostgrestError)?.code == "42501" { denied = true; return }
            failed.insert(period)
            Log.warning("[KWT SMS] تعذّر جلب محاولات الدخول: \(error.localizedDescription)")
        }
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
    /// الصفوف الظاهرة قبل «الكل»
    private static let collapsedCount = 8

    var body: some View {
        let result = store.current
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            AdminCardHeader(title: L10n.t("محاولات الدخول", "Sign-in attempts"),
                            badge: result?.totals.suspicious, badgeTint: DS.Color.warning) {
                if let result, !result.items.isEmpty {
                    NavigationLink { AdminLazyPage { AnyView(SmsAttemptsListPage()) } } label: {
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
            DSNoteCard(L10n.t("محاولات الدخول للمالك والمدير فقط.", "Sign-in attempts are for the owner and admins only."),
                       icon: "lock.fill", tint: DS.Color.warning)
        } else if store.isFailed && !store.isLoading {
            DSNoteCard(L10n.t("تعذّر جلب محاولات الدخول الآن — اسحب للتحديث.",
                              "Couldn't load sign-in attempts — pull to refresh."),
                       icon: "wifi.exclamationmark", tint: DS.Color.warning)
        } else {
            DSPageLoader(L10n.t("جاري جلب محاولات الدخول…", "Loading sign-in attempts…"),
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
        SmsAttemptsStat(value: totals.attempts, label: L10n.t("محاولات", "Attempts"))
    }
    private var unknown: some View {
        SmsAttemptsStat(value: totals.unknownNumbers, label: L10n.t("غير مسجّلة", "Not registered"))
    }
    private var suspicious: some View {
        SmsAttemptsStat(value: totals.suspicious, label: L10n.t("مريبة", "Suspicious"), warns: totals.suspicious > 0)
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
        DSEmptyView(L10n.t("ما في محاولات في هذه الفترة", "No attempts in this period"),
                    message: L10n.t("العدّ بدأ من 20 أكتوبر", "Counting started on 20 October"),
                    icon: "person.badge.key.fill", style: .inline)
    }
}

/// «يُحفظ 30 يوماً · رمز الدخول لا يُحفظ أبداً» (+ الإخفاء للمدير، + سقف ٢٠٠)
private struct SmsAttemptsNote: View {
    let result: SmsLoginAttempts

    var body: some View {
        var parts = [L10n.t("يُحفظ \(SmsText.days(result.retentionDays))", "Kept \(SmsText.days(result.retentionDays))"),
                     L10n.t("رمز الدخول لا يُحفظ أبداً", "The sign-in code is never stored")]
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

/// صفّ رقم: الاسم (أو «رقم غير مسجّل»)، الرقم وآخر وقت، ثم الشارات. العضو يفتح ملفه؛ للمالك نسخ/اتصال
private struct SmsAttemptRow: View {
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
            DSStatusChip(text: L10n.t("دخل", "Signed in"), icon: "checkmark", tint: DS.Color.success, size: .mini)
        } else {
            DSStatusChip(text: L10n.t("ما دخل", "Didn't sign in"), tint: DS.Color.slate, size: .mini)
        }
        if item.suspicious {
            DSStatusChip(text: L10n.t("مريب", "Suspicious"), icon: "exclamationmark.triangle.fill",
                         tint: DS.Color.warning, size: .mini)
                .accessibilityLabel(L10n.t("مريب: \(item.maxInHour) محاولات في ساعة واحدة",
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
        AdminBandHeader(backTitle: L10n.t("رسائل الدخول", "Sign-in messages"),
                        title: L10n.t("محاولات الدخول", "Sign-in attempts"),
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
