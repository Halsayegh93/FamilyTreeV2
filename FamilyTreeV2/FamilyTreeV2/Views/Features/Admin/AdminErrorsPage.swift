import SwiftUI
import Supabase
import Combine

// MARK: - «الأخطاء» (طلب المالك ٢٠٢٦-١١-٢٦: «أي خطأ يوصل Sentry أبيه يظهر بالتطبيق… ويروني وين الأخطاء»)
//
// للمالك وحده (قسم «التطبيق» ← «النظام»، والبحث الشامل `app.errors`). الشكل «ب» اختيار المالك: ثلاث مربّعات للمنصات
// (آيفون · أندرويد · الموقع — الضغط يصفّي) ثم «الأكثر تكراراً»، وكل خطأ يفتح «تفاصيل الخطأ» (المكان، عدد المرات، الأجهزة،
// أول وآخر مرة، الإصدار، ومسار الخطأ).
// البيانات: الدالة الطرفية `sentry-issues` بجلسة المستخدم (تتحقق أنه المالك) — مفتاح Sentry للقراءة فقط في Edge Secrets،
// لا يدخل التطبيق. بلا مفتاح: «لم يُربط بعد». لا يصل التطبيق معرّف جهاز ولا مستخدم — نص الخطأ (الأرقام مخفية) ومكانه فقط.
// حارس المكدس: الرأس والمحتوى خلف `AnyView` داخل `AdminHubPage`، والتفاصيل خلف `AdminLazyPage`.

// MARK: البيانات

enum AdminErrorPlatform: String, CaseIterable, Identifiable {
    case ios, android, web, other
    var id: String { rawValue }

    /// المربّعات الثلاث (الرابعة «أخرى» لا مربّع لها — تبقى في «الكل»)
    static let tiles: [AdminErrorPlatform] = [.ios, .android, .web]

    var title: String {
        switch self {
        case .ios:     return L10n.t("آيفون", "iPhone")
        case .android: return L10n.t("أندرويد", "Android")
        case .web:     return L10n.t("الموقع", "Website")
        case .other:   return L10n.t("أخرى", "Other")
        }
    }

    var symbol: String {
        switch self {
        case .ios:     return "apple.logo"
        case .android: return "smartphone"
        case .web:     return "globe"
        case .other:   return "questionmark.app.fill"
        }
    }

    /// تعبئة ثابتة تحت رمز أبيض (عائلة الكحلي والذهبي)
    var fill: Color {
        switch self {
        case .ios:     return DS.Color.navyFill
        case .android: return DS.Color.palmFill
        case .web:     return DS.Color.saduFill
        case .other:   return DS.Color.slateFill
        }
    }
}

struct AdminErrorIssue: Equatable, Identifiable {
    var id = ""
    var shortId = ""
    var title = ""
    /// «MemberDetailsView.swift · loadPhoto»
    var place: String?
    /// صفحة الموقع («/tree»)
    var page: String?
    var platform: AdminErrorPlatform = .other
    var count = 0
    var devices = 0
    var firstSeen: Date?
    var lastSeen: Date?
    var level = "error"
    /// كل أحداثه من نسخة تطوير/تجربة
    var testOnly = false

    static func decode(_ raw: Any?) -> AdminErrorIssue? {
        guard let d = raw as? [String: Any], let id = d["id"] as? String ?? SmsJSON.int(d["id"]).map(String.init) else { return nil }
        var i = AdminErrorIssue()
        i.id = id
        i.shortId = d["short_id"] as? String ?? id
        i.title = (d["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        i.place = d["where"] as? String
        i.page = d["page"] as? String
        i.platform = AdminErrorPlatform(rawValue: d["platform"] as? String ?? "") ?? .other
        i.count = SmsJSON.int(d["count"]) ?? 0
        i.devices = SmsJSON.int(d["users"]) ?? 0
        i.firstSeen = AdminErrorsText.date(d["first_seen"] as? String)
        i.lastSeen = AdminErrorsText.date(d["last_seen"] as? String)
        i.level = d["level"] as? String ?? "error"
        i.testOnly = d["test_only"] as? Bool ?? false
        return i
    }
}

struct AdminErrorsList: Equatable {
    var days = 7
    var totals: [AdminErrorPlatform: Int] = [:]
    var issues: [AdminErrorIssue] = []
    /// أقصى ما ترجعه الدالة
    static let cap = 50
}

struct AdminErrorDetail: Equatable {
    struct Frame: Equatable, Identifiable {
        var id = 0
        var file: String?
        var function: String?
        var line: Int?
    }
    var issue: AdminErrorIssue?
    var release: String?
    var environment: String?
    var os: String?
    var device: String?
    var browser: String?
    var frames: [Frame] = []
}

/// ما ترجعه `sentry-issues` أو يرميه
enum AdminErrorsReply {
    case notConfigured
    case list(AdminErrorsList)
    case detail(AdminErrorDetail)
}

struct AdminErrorsFailure: Error, Equatable {
    /// owner_only · not_found · sentry_error · network · bad_response · unauthorized
    let code: String

    var message: String {
        switch code {
        case "owner_only":   return L10n.t("صفحة الأخطاء للمالك فقط.", "The errors page is for the owner only.")
        case "unauthorized": return L10n.t("انتهت جلستك — سجّل الدخول من جديد.", "Your session ended — sign in again.")
        case "not_found":    return L10n.t("هذا الخطأ لم يعد موجوداً في Sentry.", "This error is no longer in Sentry.")
        case "sentry_error": return L10n.t("Sentry لم يرد الآن — حاول بعد قليل.", "Sentry didn't answer — try again shortly.")
        default:             return L10n.t("تعذّر جلب الأخطاء الآن — اسحب للتحديث.", "Couldn't load errors — pull to refresh.")
        }
    }
}

// MARK: المخزن

@MainActor
final class AdminErrorsStore: ObservableObject {
    static let shared = AdminErrorsStore()
    static let periods = [1, 7, 30]

    @Published private(set) var days = 7
    @Published private(set) var results: [Int: AdminErrorsList] = [:]
    @Published private(set) var loading: Set<Int> = []
    @Published private(set) var failure: AdminErrorsFailure?
    @Published private(set) var notConfigured = false
    /// المربّع المختار (nil = الكل)
    @Published var platform: AdminErrorPlatform?
    @Published private(set) var details: [String: AdminErrorDetail] = [:]
    private var fetchedAt: [Int: Date] = [:]

    var current: AdminErrorsList? { results[days] }
    var isLoading: Bool { loading.contains(days) }

    func select(_ period: Int) {
        guard period != days else { return }
        days = period
        Task { await refresh() }
    }

    /// يجلب الفترة المختارة — لا يُكرَّر خلال دقيقة إلا بالسحب أو زرّ التحديث
    func refresh(force: Bool = false) async {
        let period = days
        if !force, let at = fetchedAt[period], Date().timeIntervalSince(at) < 60 { return }
        guard !loading.contains(period) else { return }
        fetchedAt[period] = Date()
        loading.insert(period)
        defer { loading.remove(period) }
        do {
            switch try await Self.call(["action": .string("list"), "days": .integer(period)]) {
            case .notConfigured: notConfigured = true
            case .list(let list): results[period] = list; notConfigured = false
            case .detail: break
            }
            failure = nil
        } catch let e as AdminErrorsFailure {
            failure = e
        } catch {
            if ErrorHelper.isCancellation(error) { fetchedAt[period] = nil; return }
            failure = AdminErrorsFailure(code: "network")
        }
    }

    func detail(_ id: String) async throws -> AdminErrorDetail {
        switch try await Self.call(["action": .string("detail"), "id": .string(id)]) {
        case .detail(let d): details[id] = d; return d
        case .notConfigured: notConfigured = true; throw AdminErrorsFailure(code: "sentry_error")
        case .list: throw AdminErrorsFailure(code: "bad_response")
        }
    }

    private static func call(_ body: [String: AnyJSON]) async throws -> AdminErrorsReply {
        let data: Data
        do {
            data = try await SupabaseConfig.client.functions.invoke(
                "sentry-issues", options: FunctionInvokeOptions(method: .post, body: body)
            ) { data, _ in data }
        } catch let FunctionsError.httpError(code, data) {
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let err = (root?["error"] as? [String: Any])?["code"] as? String
            Log.warning("[الأخطاء] رُفض النداء: \(code) \(err ?? "")")
            throw AdminErrorsFailure(code: err ?? (code == 401 ? "unauthorized" : code == 403 ? "owner_only" : "network"))
        }
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> AdminErrorsReply {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AdminErrorsFailure(code: "bad_response")
        }
        if root["configured"] as? Bool == false { return .notConfigured }
        if let event = root["event"] as? [String: Any] {
            var d = AdminErrorDetail()
            d.issue = AdminErrorIssue.decode(root["issue"])
            d.release = event["release"] as? String
            d.environment = event["environment"] as? String
            d.os = event["os"] as? String
            d.device = event["device"] as? String
            d.browser = event["browser"] as? String
            d.frames = ((event["frames"] as? [[String: Any]]) ?? []).enumerated().map { n, f in
                AdminErrorDetail.Frame(id: n, file: f["file"] as? String, function: f["function"] as? String,
                                       line: SmsJSON.int(f["line"]))
            }
            return .detail(d)
        }
        var list = AdminErrorsList()
        list.days = SmsJSON.int(root["days"]) ?? 7
        let totals = root["totals"] as? [String: Any] ?? [:]
        for p in AdminErrorPlatform.allCases { list.totals[p] = SmsJSON.int(totals[p.rawValue]) ?? 0 }
        list.issues = ((root["issues"] as? [Any]) ?? []).compactMap(AdminErrorIssue.decode)
        return .list(list)
    }
}

// MARK: النصوص

enum AdminErrorsText {
    static let pageTitle = L10n.t("الأخطاء", "Errors")

    static func period(_ days: Int) -> String {
        switch days {
        case 1: return L10n.t("آخر 24 ساعة", "Last 24 hours")
        case 30: return L10n.t("آخر 30 يوماً", "Last 30 days")
        default: return L10n.t("آخر 7 أيام", "Last 7 days")
        }
    }

    /// «مرة واحدة» · «مرتين» · «5 مرات» · «12 مرة»
    static func times(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "once" : "\(n) times" }
        return AdminTodayText.arabicCount(n, one: "مرة", two: "مرتان", few: "مرات", many: "مرة", single: "مرة واحدة")
    }

    /// «جهاز واحد» · «جهازان» · «3 أجهزة»
    static func devices(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "1 device" : "\(n) devices" }
        return AdminTodayText.arabicCount(n, one: "جهاز", two: "جهازان", few: "أجهزة", many: "جهازاً", single: "جهاز واحد")
    }

    /// «آخرها قبل ساعة»
    static func last(_ date: Date?) -> String? {
        SmsAttemptsText.relative(date).map { L10n.t("آخرها \($0)", "Last \($0)") }
    }

    /// تاريخ Sentry («2026-11-26T00:07:07.462000Z» — الكسور قد تكون ٦ خانات)
    static func date(_ iso: String?) -> Date? {
        guard var s = iso, !s.isEmpty else { return nil }
        if let dot = s.firstIndex(of: "."), let end = s[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            s.removeSubrange(dot..<end)
        }
        return parser.date(from: s)
    }

    private static let parser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// «الملف · الدالة» أو صفحة الموقع — معزولاً بترتيبه داخل السطر العربي
    static func place(_ issue: AdminErrorIssue) -> String? {
        if let p = issue.place { return SmsAttemptsText.isolatedLTR(p) }
        if let page = issue.page { return L10n.t("الصفحة \(SmsAttemptsText.isolatedLTR(page))", "Page \(page)") }
        return nil
    }
}

// MARK: الصفحة

struct AdminErrorsPage: View {
    @ObservedObject private var store = AdminErrorsStore.shared
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        AdminHubPage {
            AnyView(AdminErrorsHeader(store: store))
        } content: {
            if authVM.canViewSystemSettings {
                AnyView(AdminErrorsContent(store: store))
            } else {
                AnyView(DSNoteCard(AdminErrorsFailure(code: "owner_only").message, icon: "lock.fill", tint: DS.Color.warning)
                    .adminCard())
            }
        }
        .refreshable { await store.refresh(force: true) }
        .task { if authVM.canViewSystemSettings { await store.refresh() } }
    }
}

private struct AdminErrorsHeader: View {
    @ObservedObject var store: AdminErrorsStore

    var body: some View {
        AdminBandHeader(backTitle: AdminArea.app.title,
                        title: AdminErrorsText.pageTitle,
                        subtitle: L10n.t("ما يصل Sentry من الآيفون والأندرويد والموقع · \(AdminErrorsText.period(store.days))",
                                         "What reaches Sentry from iPhone, Android and web · \(AdminErrorsText.period(store.days))")) {
            AdminGlassButton(symbol: "arrow.clockwise", label: L10n.t("تحديث", "Refresh")) {
                Task { await store.refresh(force: true) }
            }
        } accessory: {
            EmptyView()
        }
    }
}

private struct AdminErrorsContent: View {
    @ObservedObject var store: AdminErrorsStore

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // الفترة: شرائح فلتر تلتفّ (spec A.9 — لا مبدّل في الإدارة)
            DSFilterChips(options: [
                DSFilterOption(id: 1, title: L10n.t("اليوم", "Today")),
                DSFilterOption(id: 7, title: L10n.t("7 أيام", "7 days")),
                DSFilterOption(id: 30, title: L10n.t("30 يوماً", "30 days"))
            ], selection: Binding(get: { store.days }, set: { store.select($0) }), style: .admin)

            if store.notConfigured {
                DSNoteCard(L10n.t("لم يُربط Sentry بهذه الصفحة بعد — يلزمه مفتاح قراءة على السيرفر.",
                                  "Sentry isn't connected to this page yet — it needs a read key on the server."),
                           icon: "link.badge.plus", tint: DS.Color.info)
            } else if let list = store.current {
                AdminErrorsPlatformTiles(list: list, selection: $store.platform)
                AdminErrorsList_(list: list, platform: store.platform)
                AdminErrorsNote(list: list)
            } else if let failure = store.failure, !store.isLoading {
                DSNoteCard(failure.message, icon: "wifi.exclamationmark", tint: DS.Color.warning)
            } else {
                DSPageLoader(L10n.t("جاري جلب الأخطاء…", "Loading errors…"), size: DS.Icon.loaderArtInline, fillsSpace: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }
}

/// آيفون · أندرويد · الموقع — عدد الأخطاء المختلفة في الفترة، والضغط يصفّي القائمة (الضغط ثانيةً يرجع «الكل»)
private struct AdminErrorsPlatformTiles: View {
    let list: AdminErrorsList
    @Binding var selection: AdminErrorPlatform?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm, alignment: .top),
                            count: typeSize.isAccessibilitySize ? 1 : AdminErrorPlatform.tiles.count)
        LazyVGrid(columns: columns, spacing: DS.Spacing.sm) {
            ForEach(AdminErrorPlatform.tiles) { p in
                AdminErrorsPlatformTile(platform: p, count: list.totals[p] ?? 0, selected: selection == p) {
                    withAnimation(DS.Anim.snappy) { selection = selection == p ? nil : p }
                }
            }
        }
    }
}

private struct AdminErrorsPlatformTile: View {
    let platform: AdminErrorPlatform
    let count: Int
    let selected: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(spacing: DS.Spacing.xs) {
                AdminIconSquare(symbol: platform.symbol, tint: platform.fill, filled: true)
                Text(verbatim: "\(count)")
                    .dsFont(.statValue)
                    .monospacedDigit()
                    .foregroundColor(count > 0 ? DS.Color.textPrimary : DS.Color.textTertiary)
                Text(platform.title)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .background(RoundedRectangle(cornerRadius: DS.Hub.kpiRadius, style: .continuous)
                .fill(selected ? platform.fill.opacity(DS.Opacity.tintFill) : DS.Color.cardBackgroundSoft))
            .overlay(RoundedRectangle(cornerRadius: DS.Hub.kpiRadius, style: .continuous)
                .stroke(selected ? platform.fill.opacity(DS.Opacity.selectedStroke) : Color.clear, lineWidth: DS.Border.width))
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("\(platform.title): \(count) خطأ", "\(platform.title): \(count) errors"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(L10n.t("يعرض أخطاء هذه المنصة فقط", "Shows this platform's errors only"))
    }
}

/// «الأكثر تكراراً» (أو «آيفون — الأكثر تكراراً») ثم الصفوف
private struct AdminErrorsList_: View {
    let list: AdminErrorsList
    let platform: AdminErrorPlatform?

    var body: some View {
        let rows = platform.map { p in list.issues.filter { $0.platform == p } } ?? list.issues
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: platform.map { L10n.t("\($0.title) — الأكثر تكراراً", "\($0.title) — most frequent") }
                              ?? L10n.t("الأكثر تكراراً", "Most frequent"))
            if rows.isEmpty {
                DSEmptyView(platform == nil ? L10n.t("ما في أخطاء في هذه الفترة", "No errors in this period")
                                            : L10n.t("ما في أخطاء من \(platform!.title) في هذه الفترة",
                                                     "No \(platform!.title) errors in this period"),
                            icon: "checkmark.seal.fill", style: .inline)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { issue in
                        AdminErrorRow(issue: issue)
                        if issue.id != rows.last?.id { AdminRowDivider() }
                    }
                }
            }
        }
    }
}

/// صفّ خطأ: أيقونة المنصة · النص · المكان · «آخرها قبل ساعة» ثم الشارات (العدد، الأجهزة، «تجربة»)
private struct AdminErrorRow: View {
    let issue: AdminErrorIssue
    @Environment(\.adminArea) private var area

    var body: some View {
        NavigationLink {
            AdminLazyPage {
                AnyView(AdminErrorDetailPage(issue: issue)
                    .adminArea(area).adminBackTitle(AdminErrorsText.pageTitle))
            }
        } label: {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                AdminIconSquare(symbol: issue.platform.symbol, tint: issue.platform.fill, filled: true)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(verbatim: issue.title)
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    if let place = AdminErrorsText.place(issue) {
                        Text(verbatim: place)
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textSecondary)
                            .lineLimit(2)
                    }
                    if let last = AdminErrorsText.last(issue.lastSeen) {
                        Text(verbatim: last)
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    OccasionFlowLayout(spacing: DS.Spacing.xs) { chips }
                }
                Spacer(minLength: 0)
                DSChevron().padding(.top, DS.Spacing.sm)
            }
            .padding(.vertical, DS.Spacing.smd)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var chips: some View {
        DSStatusChip(text: AdminErrorsText.times(issue.count), icon: "arrow.triangle.2.circlepath",
                     tint: DS.Color.error, size: .mini)
        if issue.devices > 0 {
            DSStatusChip(text: AdminErrorsText.devices(issue.devices), icon: "iphone", tint: DS.Color.primary, size: .mini)
        }
        if issue.testOnly {
            DSStatusChip(text: L10n.t("نسخة تجربة", "Test build"), icon: "hammer.fill", tint: DS.Color.slate, size: .mini)
        }
    }
}

/// «يتحدّث من Sentry مباشرة · الأرقام الطويلة مخفية» (+ سقف ٥٠)
private struct AdminErrorsNote: View {
    let list: AdminErrorsList

    var body: some View {
        var parts = [L10n.t("من Sentry مباشرة", "Live from Sentry"),
                     L10n.t("الأرقام الطويلة في نص الخطأ مخفية", "Long numbers in error text are hidden")]
        if list.issues.count >= AdminErrorsList.cap {
            parts.append(L10n.t("يظهر أكثر \(AdminErrorsList.cap) خطأ تكراراً", "Top \(AdminErrorsList.cap) errors shown"))
        }
        return Text(verbatim: parts.joined(separator: " · "))
            .dsFont(.footnote)
            .foregroundColor(DS.Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: تفاصيل الخطأ

struct AdminErrorDetailPage: View {
    let issue: AdminErrorIssue
    @ObservedObject private var store = AdminErrorsStore.shared
    @State private var failure: AdminErrorsFailure?
    @State private var loading = false

    var body: some View {
        AdminHubPage {
            AnyView(AdminBandHeader(backTitle: AdminErrorsText.pageTitle,
                                    title: issue.platform.title,
                                    subtitle: L10n.t("تفاصيل الخطأ · \(issue.shortId)", "Error details · \(issue.shortId)")) {
                AdminGlassButton(symbol: "arrow.clockwise", label: L10n.t("تحديث", "Refresh")) { Task { await load() } }
            } accessory: { EmptyView() })
        } content: {
            AnyView(AdminErrorDetailContent(issue: store.details[issue.id]?.issue ?? issue,
                                            detail: store.details[issue.id],
                                            loading: loading, failure: failure))
        }
        .refreshable { await load() }
        .task { if store.details[issue.id] == nil { await load() } }
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            _ = try await store.detail(issue.id)
            failure = nil
        } catch let e as AdminErrorsFailure {
            failure = e
        } catch {
            if !ErrorHelper.isCancellation(error) { failure = AdminErrorsFailure(code: "network") }
        }
    }
}

private struct AdminErrorDetailContent: View {
    let issue: AdminErrorIssue
    let detail: AdminErrorDetail?
    let loading: Bool
    let failure: AdminErrorsFailure?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(verbatim: issue.title)
                .dsFont(.headline)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            AdminRowsCardBody {
                if let place = AdminErrorsText.place(issue) {
                    AdminInfoRow(icon: "mappin.and.ellipse", tint: issue.platform.fill, title: L10n.t("المكان", "Where"),
                                 subtitle: place)
                }
                AdminInfoRow(icon: "arrow.triangle.2.circlepath", tint: DS.Color.error, title: L10n.t("تكرر", "Happened"),
                             trailing: AnyView(AdminValueChip(text: AdminErrorsText.times(issue.count), tint: DS.Color.error)))
                AdminInfoRow(icon: "iphone", tint: DS.Color.primary, title: L10n.t("الأجهزة", "Devices"),
                             trailing: AnyView(AdminValueChip(text: AdminErrorsText.devices(issue.devices), tint: DS.Color.primary)))
                if let first = issue.firstSeen {
                    AdminInfoRow(icon: "clock.arrow.circlepath", tint: DS.Color.primary, title: L10n.t("أول مرة", "First seen"),
                                 subtitle: AppVersionText.stamp(first))
                }
                if let last = issue.lastSeen {
                    AdminInfoRow(icon: "clock.fill", tint: DS.Color.primary, title: L10n.t("آخر مرة", "Last seen"),
                                 subtitle: AppVersionText.stamp(last))
                }
                if let detail {
                    if let release = detail.release {
                        AdminInfoRow(icon: "app.badge.fill", tint: DS.Color.primary, title: L10n.t("الإصدار", "Version"),
                                     subtitle: SmsAttemptsText.isolatedLTR(release))
                    }
                    if let system = [detail.device, detail.os, detail.browser].compactMap({ $0 }).joined(separator: " · ").nilIfEmpty {
                        AdminInfoRow(icon: "cpu", tint: DS.Color.primary, title: L10n.t("الجهاز والنظام", "Device and system"),
                                     subtitle: SmsAttemptsText.isolatedLTR(system))
                    }
                    AdminInfoRow(icon: "shippingbox.fill", tint: DS.Color.primary, title: L10n.t("النسخة", "Build"),
                                 subtitle: AdminErrorDetailContent.environment(detail.environment))
                }
            }

            if let detail {
                AdminErrorFrames(frames: detail.frames, platform: issue.platform)
            } else if let failure, !loading {
                DSNoteCard(failure.message, icon: "wifi.exclamationmark", tint: DS.Color.warning)
            } else {
                DSPageLoader(L10n.t("جاري جلب التفاصيل…", "Loading details…"), size: DS.Icon.loaderArtInline, fillsSpace: false)
            }

            if let url = URL(string: "https://almohaliapp.sentry.io/issues/\(issue.id)/") {
                DSButton(L10n.t("افتح في Sentry", "Open in Sentry"), icon: "safari.fill") { openURL(url) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    static func environment(_ env: String?) -> String {
        switch (env ?? "").lowercased() {
        case "production": return L10n.t("النسخة الرسمية", "Official release")
        case "development", "dev": return L10n.t("نسخة تجربة (من جهاز المطوّر)", "Test build (developer device)")
        case "preview": return L10n.t("نسخة معاينة", "Preview build")
        case "": return L10n.t("غير معروفة", "Unknown")
        default: return SmsAttemptsText.isolatedLTR(env ?? "")
        }
    }
}

/// «مسار الخطأ»: أسطر التطبيق، الأحدث أولاً — الملف:السطر ثم الدالة
private struct AdminErrorFrames: View {
    let frames: [AdminErrorDetail.Frame]
    let platform: AdminErrorPlatform

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: L10n.t("مسار الخطأ", "Where it happened in the code"))
            if frames.isEmpty {
                Text(platform == .ios
                     ? L10n.t("المسار غير متاح بعد — يظهر بعد رفع ملفات الرموز (dSYM) من نسخ TestFlight.",
                              "Not available yet — appears once symbol files (dSYM) are uploaded from TestFlight builds.")
                     : L10n.t("المسار غير متاح لهذا الخطأ.", "No code path for this error."))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ForEach(frames) { f in
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text(verbatim: [f.file, f.line.map(String.init)].compactMap { $0 }.joined(separator: ":"))
                                .dsFont(.footnote)
                                .foregroundColor(DS.Color.textPrimary)
                            if let fn = f.function {
                                Text(verbatim: fn)
                                    .dsFont(.caption)
                                    .foregroundColor(DS.Color.textTertiary)
                                    .lineLimit(2)
                            }
                        }
                        .environment(\.layoutDirection, .leftToRight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Spacing.sm)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .fill(DS.Color.cardBackgroundSoft))
                    }
                }
                .textSelection(.enabled)
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
