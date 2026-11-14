import SwiftUI
import Supabase

// MARK: - قطع «الاستخدام والأجهزة» (اختيار المالك ٢٠٢٦-١١-٠٧، العيّنة «أ» — samples/admin-insights-team)
//
// الصفحة نفسها `AdminPushHealthView` (AdminPushHealthView.swift — الاسم بقي لأن «اليوم» و«المناسبات» يفتحانها به). هنا:
// النداءات الحيّة (الآن · آخر 24 ساعة — نفس دوال «الاستخدام» القديمة)، حلقات الرأس، السلّم «من العائلة إلى التطبيق»
// وصفحة أسماء كل درجة (`app_usage_members` الموجودة)، بطاقتا «الحين» و«آخر 24 ساعة»، وصفحة «تفاصيل الاستخدام»
// (الاتجاه والجلسات وأكثر الشاشات — `AdminUsageInsights` كما هي). كل بطاقة نوع مستقل خلف `AnyView` (حارس المكدس).

// MARK: - النداءات الحيّة

enum AdminLiveUsage {
    /// المستخدمون الآن (آخر 5 دقائق) — `get_active_members_now`، جلسة لكل عضو + مصدر، الأحدث أولاً
    static func fetchNow() async -> [ActiveMemberRow] {
        struct Row: Decodable {
            let memberId: UUID
            let fullName: String?
            let avatarUrl: String?
            let currentScreen: String?
            let currentScreenSource: String?
            let secondsSinceActive: Int
            enum CodingKeys: String, CodingKey {
                case memberId = "member_id"
                case fullName = "full_name"
                case avatarUrl = "avatar_url"
                case currentScreen = "current_screen"
                case currentScreenSource = "current_screen_source"
                case secondsSinceActive = "seconds_since_active"
            }
        }
        do {
            let response = try await SupabaseConfig.client.rpc("get_active_members_now").execute()
            let decoded = try JSONDecoder().decode([Row].self, from: response.data)
            var seen = Set<String>()
            return decoded
                .map { ActiveMemberRow(memberId: $0.memberId, fullName: $0.fullName ?? "", avatarUrl: $0.avatarUrl,
                                       currentScreen: $0.currentScreen, source: $0.currentScreenSource,
                                       secondsSinceActive: $0.secondsSinceActive) }
                .sorted { $0.secondsSinceActive < $1.secondsSinceActive }
                .filter { seen.insert(key($0.memberId, $0.source)).inserted }
        } catch {
            Log.warning("[ActiveNow] فشل: \(error.localizedDescription)")
            return []
        }
    }

    /// آخر 24 ساعة بنوع الإجراء — `get_recent_member_actions(hours_back: 24)`، بلا جلسات «الآن»
    static func fetchActions24h(excluding now: [ActiveMemberRow]) async -> [RecentActionRow] {
        struct Row: Decodable {
            let memberId: UUID
            let fullName: String?
            let avatarUrl: String?
            let actionKind: String
            let actionLabel: String?
            let source: String?
            let minutesAgo: Int
            enum CodingKeys: String, CodingKey {
                case memberId = "member_id"
                case fullName = "full_name"
                case avatarUrl = "avatar_url"
                case actionKind = "action_kind"
                case actionLabel = "action_label"
                case source
                case minutesAgo = "minutes_ago"
            }
        }
        do {
            let payload: [String: AnyEncodable] = ["hours_back": AnyEncodable(24)]
            let response = try await SupabaseConfig.client.rpc("get_recent_member_actions", params: payload).execute()
            let decoded = try JSONDecoder().decode([Row].self, from: response.data)
            var seen = Set(now.map { key($0.memberId, $0.source) })
            return decoded
                .map { RecentActionRow(memberId: $0.memberId, fullName: $0.fullName ?? "", avatarUrl: $0.avatarUrl,
                                       actionKind: $0.actionKind, actionDetail: $0.actionLabel ?? "", source: $0.source,
                                       minutesAgo: $0.minutesAgo) }
                .sorted { $0.minutesAgo < $1.minutesAgo }
                .filter { seen.insert(key($0.memberId, $0.source)).inserted }
        } catch {
            Log.warning("[Actions24h] فشل: \(error.localizedDescription)")
            return []
        }
    }

    static func key(_ id: UUID, _ source: String?) -> String { "\(id)-\(source ?? "")" }

    // MARK: النصوص

    static func sourceIcon(_ source: String?) -> String {
        switch source {
        case "web": return "globe"
        case "app": return "iphone.gen3"
        default:    return "questionmark.circle"
        }
    }

    static func sourceName(_ source: String?) -> String {
        source == "web" ? L10n.t("الموقع", "Web") : L10n.t("التطبيق", "App")
    }

    static func screenLabel(_ key: String?, source: String?) -> String {
        guard let key, !key.isEmpty else {
            switch source {
            case "web": return L10n.t("على الموقع", "On Web")
            case "app": return L10n.t("في التطبيق", "In App")
            default:    return L10n.t("نشط", "Active")
            }
        }
        switch key {
        case "home":      return L10n.t("الرئيسية", "Home")
        case "tree":      return L10n.t("الشجرة", "Tree")
        case "diwaniyas": return L10n.t("الديوانيات", "Diwaniyas")
        case "profile":   return L10n.t("الملف الشخصي", "Profile")
        case "admin":     return L10n.t("الإدارة", "Admin")
        case "news":      return L10n.t("الأخبار", "News")
        case "projects":  return L10n.t("المشاريع", "Projects")
        default:          return key
        }
    }

    static func actionLabel(_ row: RecentActionRow) -> String {
        switch row.actionKind {
        case "screen_visit":
            return L10n.t("في \(screenLabel(row.actionDetail, source: row.source))",
                          "On \(screenLabel(row.actionDetail, source: row.source))")
        case "news_add":      return L10n.t("نشر: \(row.actionDetail)", "Posted: \(row.actionDetail)")
        case "news_comment":  return L10n.t("علّق: \(row.actionDetail)", "Commented: \(row.actionDetail)")
        case "news_like":     return L10n.t("أعجب بمنشور", "Liked a post")
        case "poll_vote":     return L10n.t("صوّت في استطلاع", "Voted in poll")
        case "device_active": return L10n.t("فتح التطبيق", "Opened the app")
        case "web_session":   return L10n.t("دخل الموقع", "Entered the site")
        default:
            if row.actionKind.hasPrefix("request_") {
                return L10n.t("طلب: \(row.actionDetail)", "Request: \(row.actionDetail)")
            }
            return row.actionDetail
        }
    }

    static func minutesLabel(_ m: Int) -> String {
        if m < 1 { return L10n.t("الآن", "now") }
        if m < 60 { return L10n.t("\(m) د", "\(m)m") }
        return L10n.t("\(m / 60) س", "\(m / 60)h")
    }

    static func secondsLabel(_ s: Int) -> String {
        if s < 60 { return L10n.t("الآن", "now") }
        return L10n.t("\(s / 60) د", "\(s / 60)m")
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return L10n.t("لا يوجد", "None") }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - حلقة في الرأس الكحلي (الحلقة الصغيرة بعددها، الاسم أبيض، سطر ذهبي)

struct AdminBandRingColumn: View {
    let title: String
    let line: String
    let progress: Double?
    let tint: Color
    var center: DSGaugeCenter = .none
    /// رمز في وسط الحلقة بدل الرقم («✓» التسجيل مسموح)
    var symbol: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let ring = DSRingGauge(progress: progress, tint: tint, size: DS.Ring.small, track: DS.Ring.bandTrack,
                               center: center, ink: DS.Color.textOnPrimary)
            .overlay {
                if let symbol {
                    Image(systemName: symbol)
                        .dsGlyph(DS.Glyph.lg, weight: .bold)
                        .foregroundColor(DS.Color.textOnPrimary)
                }
            }
        Group {
            if typeSize.isAccessibilitySize {
                AnyView(HStack(spacing: DS.Spacing.md) {
                    ring
                    VStack(alignment: .leading, spacing: 0) { titleText; lineText }
                    Spacer(minLength: 0)
                })
            } else {
                AnyView(VStack(spacing: DS.Spacing.xs) {
                    ring
                    titleText.multilineTextAlignment(.center)
                    lineText.multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var titleText: some View {
        Text(title)
            .dsFont(.hubRow)
            .foregroundColor(DS.Color.textOnPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var lineText: some View {
        Text(verbatim: line)
            .dsFont(.caption)
            .monospacedDigit()
            .foregroundColor(DS.Color.accentLight)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var spoken: String {
        let value = center.number.map { DSGaugeText.value($0, percent: center.isPercent) }
        return [title, value, line].compactMap { $0 }.joined(separator: L10n.t("، ", ", "))
    }
}

/// صفّ الحلقات في الرأس (عمودي من أحجام إمكانية الوصول) بفواصل رفيعة
struct AdminBandRingRow: View {
    let columns: [AnyView]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(columns.indices, id: \.self) { columns[$0] }
            }
        } else {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                ForEach(columns.indices, id: \.self) { i in
                    if i > 0 {
                        Rectangle().fill(DS.Hub.ringStroke).frame(width: DS.Border.width / 2)
                            .accessibilityHidden(true)
                    }
                    columns[i]
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - السلّم «من العائلة إلى التطبيق»

/// درجة في السلّم — كل درجة تفتح أسماءها
enum AdminUsageStep: String, CaseIterable, Identifiable {
    case hasPhone, registered, device, active, now

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hasPhone:   return L10n.t("لهم رقم جوال", "Have a phone number")
        case .registered: return L10n.t("سجّلوا في التطبيق", "Signed in to the app")
        case .device:     return L10n.t("جهازهم مسجّل", "Device registered")
        case .active:     return L10n.t("استخدموا خلال 3 أسابيع", "Used it in 3 weeks")
        case .now:        return L10n.t("يستخدمونه الآن", "Using it now")
        }
    }

    /// فئات `app_usage_members` التي تكوّن الدرجة («الحين» من القائمة الحيّة)
    var categories: [AppUsageCategory] {
        switch self {
        case .hasPhone:   return [.active, .idle, .loginNoDevice, .neverLogged]
        case .registered: return [.active, .idle, .loginNoDevice]
        case .device:     return [.active, .idle]
        case .active:     return [.active]
        case .now:        return []
        }
    }

    func count(_ u: AppUsageStats?, now: Int?) -> Int? {
        if self == .now { return now }
        guard let u else { return nil }
        return categories.reduce(0) { $0 + u.value(for: $1) }
    }
}

struct AdminUsageFunnelCard: View {
    let usage: AppUsageStats?
    let now: [ActiveMemberRow]
    let nowLoaded: Bool

    private var living: Int? {
        usage.map { $0.active + $0.idle + $0.loginNoDevice + $0.neverLogged + $0.noPhone }
    }

    var body: some View {
        let top = AdminUsageStep.hasPhone.count(usage, now: nil) ?? 0
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: L10n.t("من العائلة إلى التطبيق", "From the family to the app"),
                              trailing: living.map { L10n.t("من \($0.formatted()) حي", "of \($0.formatted()) living") })
            card(top: top)
        }
    }

    private func card(top: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            ForEach(Array(AdminUsageStep.allCases.enumerated()), id: \.element.id) { index, step in
                AnyView(stepRow(step, index: index, top: top))
                // الفرق بين الدرجتين = من وقف عندها — بيته الوحيد في الصفحة (كان أيضاً في «يحتاج تصرّف»)
                if step == .hasPhone, let never = usage?.neverLogged, never > 0 {
                    AnyView(gapRow(text: L10n.t("\(never) ما دخلوا أبداً — ممكن تذكّرهم برسالة",
                                                "\(never) never signed in — you could remind them"),
                                   page: { AnyView(AdminMembersPage(chip: .treeOnly, sub: .notSignedIn).adminArea(.family)) }))
                }
                if step == .registered, let noDevice = usage?.loginNoDevice, noDevice > 0 {
                    AnyView(gapRow(text: L10n.t("\(noDevice) دخلوا بدون جهاز — ما سمحوا بالإشعارات",
                                                "\(noDevice) signed in without a device — notifications not allowed"),
                                   page: { AnyView(AdminMembersPage(chip: .registered, sub: .noPush).adminArea(.family)) }))
                }
            }
            Text(L10n.t("اضغط أي درجة لعرض الأسماء", "Tap any step to see the names"))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Spacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    /// سطر صغير بين درجتين: من وقف هنا + «عرض» ← قائمتهم في «العائلة»
    private func gapRow(text: String, page: @escaping () -> AnyView) -> some View {
        AdminTapWrap(tap: .page(page), feel: .plain, label: AnyView(
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "arrow.turn.down.left")
                    .dsGlyph(DS.Glyph.xs)
                    .foregroundColor(DS.Color.textTertiary)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityHidden(true)
                Text(verbatim: text)
                    .dsFont(.footnote)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DS.Spacing.xs)
                Text(L10n.t("عرض", "View"))
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.primary)
            }
            .padding(.leading, DS.Spacing.md)
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())))
    }

    private func stepRow(_ step: AdminUsageStep, index: Int, top: Int) -> some View {
        let value = step.count(usage, now: nowLoaded ? now.count : nil)
        let share = value.map { top > 0 ? Double($0) / Double(top) : 0 }
        // الدرجات تغمق كلما نزلت — نفس اللون (أخضر العائلة)
        let tint = DS.Color.palm.opacity(0.45 + 0.55 * Double(index) / Double(AdminUsageStep.allCases.count - 1))
        // «الحين» وحدها: التطبيق والموقع (كان سطر حلقة الرأس)
        let app = now.filter { $0.source != "web" }.count
        let split: String? = step == .now && nowLoaded && !now.isEmpty
            ? L10n.t("\(app) تطبيق · \(now.count - app) موقع", "\(app) app · \(now.count - app) web") : nil
        let face = HStack(spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text(step.title)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if let split {
                    Text(verbatim: split)
                        .dsFont(.caption)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DSMeterBar(progress: share, tint: tint, track: DS.Ring.emptyTrack)
                .frame(maxWidth: .infinity)
            Text(verbatim: value.map { "\($0)" } ?? "—")
                .dsFont(.statValue)
                .monospacedDigit()
                .foregroundColor(DS.Color.textPrimary)
                .frame(minWidth: DS.Icon.section, alignment: .trailing)
        }
        .frame(minHeight: DS.Icon.tapTarget)
        .contentShape(Rectangle())
        let rows = now
        return AdminTapWrap(tap: .page { AnyView(AdminUsageStepPage(step: step, nowRows: rows)) }, feel: .plain,
                            label: AnyView(face),
                            accessibilityLabel: [step.title, value.map { "\($0)" } ?? "—", split].compactMap { $0 }
                                .joined(separator: L10n.t("، ", ", ")))
    }
}

// MARK: - صفحة أسماء الدرجة

struct AdminUsageStepPage: View {
    let step: AdminUsageStep
    var nowRows: [ActiveMemberRow] = []
    @EnvironmentObject var memberVM: MemberViewModel

    private struct Entry: Identifiable {
        let id: String
        let memberId: UUID
        let name: String
        let detail: String
        let when: String
    }

    @State private var entries: [Entry]?
    @State private var failed = false
    @State private var sheet: AdminMemberSheetContext?

    var body: some View {
        AdminPage(header: AdminPageHeader(title: step.title,
                                          subtitle: entries.map { L10n.t("\($0.count) عضو", "\($0.count) members") },
                                          glyph: "person.3.sequence.fill"),
                  content: AnyView(list))
            .dsTallBox(item: $sheet) { context in
                AdminMemberSheet(ids: context.ids, start: context.start)
            }
            .task { await load() }
            .refreshable { await load() }
    }

    private var list: AnyView {
        guard let entries else {
            if failed {
                return AnyView(AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأسماء", "Couldn't load the names"),
                                                         message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى",
                                                                         "Check your connection and try again"),
                                                         retry: { Task { await load() } })))
            }
            return AnyView(AdminPageStateCard(.loading(L10n.t("جارٍ التحميل…", "Loading…"))))
        }
        if entries.isEmpty {
            return AnyView(DSEmptyView(L10n.t("لا أحد متصل الآن", "No one here right now"), style: .card))
        }
        let ids = entries.map(\.memberId)
        return AnyView(AdminSectionCard(spacing: 0) {
            AdminLazyRows(items: entries) { entry in
                AnyView(row(entry, ids: ids))
            }
        })
    }

    private func row(_ e: Entry, ids: [UUID]) -> some View {
        let member = memberVM.member(byId: e.memberId)
        return Button {
            if let start = ids.firstIndex(of: e.memberId) { sheet = AdminMemberSheetContext(ids: ids, start: start) }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSMemberAvatar(name: e.name, avatarUrl: member?.avatarUrl, size: DS.Icon.row, roleColor: AppSection.admin.ink)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(e.name)
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                        .dsNameLines()
                    Text(e.detail)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Spacing.xs)
                if !e.when.isEmpty {
                    Text(verbatim: e.when)
                        .dsFont(.badge)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)
                }
                if member != nil { DSChevron() }
            }
            .padding(.vertical, DS.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(member == nil)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
        if step == .now {
            let rows = nowRows.isEmpty ? await AdminLiveUsage.fetchNow() : nowRows
            entries = rows.map { r in
                Entry(id: AdminLiveUsage.key(r.memberId, r.source), memberId: r.memberId,
                      name: memberVM.displayName(id: r.memberId, stored: r.fullName, .four),
                      detail: "\(AdminLiveUsage.screenLabel(r.currentScreen, source: r.source)) · \(AdminLiveUsage.sourceName(r.source))",
                      when: AdminLiveUsage.secondsLabel(r.secondsSinceActive))
            }
            return
        }
        // نفس دالة قوائم الحسابات (`app_usage_members`) — فئة لكل نداء، معاً
        let cats = step.categories
        let lists: [(AppUsageCategory, [AppUsageMember]?)] = await withTaskGroup(of: (AppUsageCategory, [AppUsageMember]?).self) { group in
            for c in cats {
                group.addTask {
                    let rows: [AppUsageMember]? = try? await SupabaseConfig.client
                        .rpc("app_usage_members", params: ["p_category": c.rawValue])
                        .execute()
                        .value
                    return (c, rows)
                }
            }
            var out: [(AppUsageCategory, [AppUsageMember]?)] = []
            for await item in group { out.append(item) }
            return out
        }
        guard lists.allSatisfy({ $0.1 != nil }) else { failed = true; return }
        failed = false
        var all: [(AppUsageCategory, AppUsageMember)] = []
        for (c, rows) in lists {
            for r in rows ?? [] where !AdminMemberFacts.isBlank(r.fullName)
                && r.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) != "بدون اسم" {
                all.append((c, r))
            }
        }
        all.sort { ($0.1.lastSeen ?? .distantPast) > ($1.1.lastSeen ?? .distantPast) }
        entries = all.map { c, r in
            Entry(id: r.memberId.uuidString, memberId: r.memberId,
                  name: memberVM.displayName(id: r.memberId, stored: r.fullName ?? "", .four),
                  detail: c.title,
                  when: r.lastSeen.map { AdminLiveUsage.relative($0) } ?? "")
        }
    }
}

// MARK: - «النشاط» (الحين + آخر 24 ساعة) وسطر حكم الرأس

/// صفّ نشاط: الصورة (ونقطة «متصل») · الاسم · أين · مصدره · الوقت شارة
struct AdminLiveRow: View {
    let memberId: UUID
    let name: String
    let avatarUrl: String?
    let detail: String
    let source: String?
    let time: String
    var online = false

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSMemberAvatar(name: name, avatarUrl: avatarUrl, size: DS.Icon.row, roleColor: AppSection.admin.ink)
                .overlay(alignment: .bottomTrailing) {
                    if online {
                        Circle().fill(DS.Color.success)
                            .frame(width: DS.Icon.onlineDot, height: DS.Icon.onlineDot)
                            .overlay(Circle().stroke(DS.Color.cardBackground, lineWidth: DS.Border.widthBold))
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(name)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Spacing.xs)
            Image(systemName: AdminLiveUsage.sourceIcon(source))
                .dsGlyph(DS.Glyph.sm)
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityLabel(AdminLiveUsage.sourceName(source))
            DSStatusChip(text: time, tint: online ? DS.Color.success : DS.Color.primary, size: .mini)
        }
        .padding(.vertical, DS.Spacing.sm)
        .accessibilityElement(children: .combine)
    }
}

/// «النشاط»: الحين أولاً (نقطة «متصل») ثم آخر 24 ساعة — بطاقة واحدة بلا عدد (العدد في درجة «الحين» بالسلّم)
struct AdminLiveActivityCard: View {
    let now: [ActiveMemberRow]
    let day: [RecentActionRow]
    let loaded: Bool
    @State private var showsAll = false
    @EnvironmentObject var memberVM: MemberViewModel
    private static let preview = 6

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: L10n.t("النشاط", "Activity"),
                              trailing: L10n.t("الآن وآخر 24 ساعة · يُحدَّث كل 15 ثانية",
                                               "Now and last 24 hours · refreshes every 15 seconds"))
            card
        }
    }

    private var card: some View {
        let total = now.count + day.count
        let nowShown = showsAll ? now : Array(now.prefix(Self.preview))
        let dayShown = showsAll ? day : Array(day.prefix(max(0, Self.preview - nowShown.count)))
        return AdminSectionCard(spacing: 0) {
            if !loaded {
                DSPageLoader(fillsSpace: false).frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.md)
            } else if total == 0 {
                DSEmptyView(L10n.t("لا استخدام خلال 24 ساعة", "No use in the last 24 hours"), style: .inline)
            } else {
                AdminRowsCardBody {
                    ForEach(nowShown, id: \.sessionKeyLive) { r in
                        AdminLiveRow(memberId: r.memberId,
                                     name: memberVM.displayName(id: r.memberId, stored: r.fullName, .four),
                                     avatarUrl: r.avatarUrl,
                                     detail: "\(AdminLiveUsage.screenLabel(r.currentScreen, source: r.source)) · \(AdminLiveUsage.sourceName(r.source))",
                                     source: r.source,
                                     time: AdminLiveUsage.secondsLabel(r.secondsSinceActive),
                                     online: r.secondsSinceActive < 300)
                    }
                    ForEach(dayShown, id: \.sessionKeyLive) { r in
                        AdminLiveRow(memberId: r.memberId,
                                     name: memberVM.displayName(id: r.memberId, stored: r.fullName, .four),
                                     avatarUrl: r.avatarUrl, detail: AdminLiveUsage.actionLabel(r), source: r.source,
                                     time: AdminLiveUsage.minutesLabel(r.minutesAgo))
                    }
                    if total > Self.preview {
                        Button {
                            withAnimation(DSMotion.expand) { showsAll.toggle() }
                        } label: {
                            HStack(spacing: DS.Spacing.xs) {
                                Text(showsAll ? L10n.t("عرض أقل", "Show less")
                                              : L10n.t("عرض الكل (\(total))", "Show all (\(total))"))
                                    .dsFont(.chip)
                                Image(systemName: showsAll ? "chevron.up" : (L10n.isArabic ? "chevron.left" : "chevron.right"))
                                    .dsGlyph(DS.Glyph.xs, weight: .semibold)
                            }
                            .foregroundColor(DS.Color.primary)
                            .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// سطر الحكم الواحد في الرأس الكحلي — بلا أرقام (كل رقم له بيت واحد تحت)
struct AdminUsageStatusLine: View {
    /// nil = جارٍ الفحص
    let ok: Bool?
    let text: String

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Circle().fill(ok == false ? DS.Hub.kpiLate : (ok == true ? DS.Hub.statusOk : DS.Hub.ringStroke))
                .frame(width: DS.Hub.statusDot, height: DS.Hub.statusDot)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .dsFont(.hubLabel)
                .foregroundColor(DS.Color.textOnPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Hub.kpiRadius, style: .continuous).fill(DS.Hub.glass))
        .overlay(RoundedRectangle(cornerRadius: DS.Hub.kpiRadius, style: .continuous)
            .strokeBorder(DS.Hub.glassLine, lineWidth: DS.Border.width))
        .padding(.top, DS.Spacing.md)
        .accessibilityElement(children: .combine)
    }
}

extension ActiveMemberRow {
    var sessionKeyLive: String { AdminLiveUsage.key(memberId, source) }
}

extension RecentActionRow {
    var sessionKeyLive: String { AdminLiveUsage.key(memberId, source) }
}

// MARK: - «المزيد عن الاستخدام» — الاتجاه والجلسات وأكثر الشاشات والأعضاء (بطاقات «الاستخدام» بلا حلقات النشطين)

struct AdminUsageDetailsPage: View {
    var body: some View {
        // بلا حلقات «النشطون» (اليوم · 7 · 30 يوماً) — النشطون بيتهم السلّم في الصفحة السابقة
        AdminPage(header: AdminPageHeader(title: L10n.t("المزيد عن الاستخدام", "More about usage"),
                                          subtitle: L10n.t("الاتجاه، الجلسات، أكثر الشاشات والأعضاء",
                                                           "Trend, sessions, top screens and members"),
                                          glyph: "chart.xyaxis.line"),
                  content: AnyView(AdminUsageInsights(showsActiveRings: false)))
            .refreshable { await AdminUsageStore.shared.refresh(force: true) }
    }
}
