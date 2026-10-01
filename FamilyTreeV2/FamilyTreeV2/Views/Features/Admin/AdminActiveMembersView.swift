import SwiftUI
import Supabase
import PostgREST

// MARK: - Admin Active Members — النشاط (الآن + آخر 24 ساعة + آخر 30 يوم)
//
// تصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧): بطاقة رأس بأرقام حيّة
// (الآن · التطبيق · الموقع) ← ثلاثة أقسام صفوفها `.dsRowBox()`. التحديث كما كان:
// كل ١٥ ثانية، وبالسحب، وبزر الشريط العلوي.
struct AdminActiveMembersView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel

    @State private var nowRows: [ActiveMemberRow] = []
    @State private var recentRows: [RecentlyActiveRow] = []
    @State private var actionRows: [RecentActionRow] = []
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var refreshTimer: Timer?
    @State private var membershipCounts: MembershipCounts?
    @State private var usage: AppUsageStats? = AppUsageStats.cached
    @State private var membershipCountsFailed = false
    /// انتهى أول تحميل — قبله «—» في الأرقام بدل أصفار مضلِّلة
    @State private var didLoadOnce = false

    private struct MembershipCounts: Decodable {
        let in_system: Int
        let total_members: Int
    }

    /// لون مجال «الشجرة والأعضاء»
    private let tint = DS.Color.composerProject

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) {
                    hero

                    // الوضع الأفقي: الأقسام على عمودين
                    AdaptiveCardStack(spacing: DS.Spacing.md, landscapeMinimum: 340) {
                        nowSection
                        last24Section
                        last30Section
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xxxl)
            }
            .refreshable { await fetch() }
        }
        .navigationTitle(L10n.t("النشاط الآن", "Live Activity"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { refreshButton }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            // أبلغ إن المدير الحالي شاف "النشاط" — يبقيه ضمن النشطين
            MemberActivityTracker.report("admin", force: true)
            await fetch()
            didLoadOnce = true
            startTimer()
        }
        .onDisappear { refreshTimer?.invalidate() }
    }

    // MARK: - Refresh button (أيقونة صغيرة في الشريط العلوي — طلب المالك)
    private var refreshButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                isRefreshing = true
                MemberActivityTracker.report("admin", force: true)
                await fetch()
                isRefreshing = false
            }
        } label: {
            if isRefreshing {
                ProgressView().scaleEffect(0.8)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(DS.Font.scaled(14, weight: .bold))
            }
        }
        .disabled(isRefreshing)
        .accessibilityLabel(L10n.t("تحديث الآن", "Refresh Now"))
    }

    // MARK: - بطاقة الرأس
    /// نفس أرقام المربّعات الثلاثة السابقة (طلب المالك: أصغر وأرتب). «الأعضاء
    /// الفعّالون» موجودة أصلاً في «استخدام التطبيق» بإعدادات النظام، فلا تتكرر هنا.

    private var appCount: Int {
        nowRows.filter { $0.source == "app" }.count + recentRows.filter { $0.source == "app" }.count
    }

    private var webCount: Int {
        nowRows.filter { $0.source == "web" }.count + recentRows.filter { $0.source == "web" }.count
    }

    private func heroValue(_ n: Int) -> String { didLoadOnce ? "\(n)" : "—" }

    private var hero: some View {
        DSPageHero(
            title: L10n.t("النشاط الآن", "Live Activity"),
            subtitle: L10n.t("من يستخدم التطبيق والموقع — يتحدّث كل ١٥ ثانية",
                             "Who's on the app and the website — refreshes every 15 seconds"),
            icon: "person.2.fill",
            tint: tint,
            stats: [
                DSHeroStat(value: heroValue(nowRows.count),
                           label: L10n.t("الآن", "Now"), icon: "circle.fill"),
                DSHeroStat(value: heroValue(appCount),
                           label: L10n.t("التطبيق", "App"), icon: "iphone.gen3"),
                DSHeroStat(value: heroValue(webCount),
                           label: L10n.t("الموقع", "Web"), icon: "globe")
            ]
        )
    }

    // MARK: - الأقسام

    // ── النشطون الآن (آخر 5 دقائق) ──
    private var nowSection: some View {
        DSComposerSection(title: L10n.t("النشطون الآن", "Active Now"),
                          icon: "dot.radiowaves.left.and.right",
                          tint: DS.Color.success,
                          trailing: nowRows.isEmpty ? nil : "\(nowRows.count)",
                          index: 1) {
            if isLoading && nowRows.isEmpty {
                ProgressView()
                    .tint(tint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.xl)
            } else if nowRows.isEmpty {
                inlineEmpty(text: L10n.t("لا يوجد نشاط حالياً", "No one active right now"))
            } else {
                VStack(spacing: 6) {
                    ForEach(nowRows, id: \.sessionKey) { row in
                        activeNowRow(row)
                    }
                }
            }
        }
    }

    // ── آخر 24 ساعة (مع نوع الإجراء) ──
    private var last24Section: some View {
        DSComposerSection(title: L10n.t("آخر 24 ساعة", "Last 24 Hours"),
                          icon: "clock.arrow.circlepath",
                          tint: tint,
                          trailing: "\(actionRows.count)",
                          index: 2) {
            if actionRows.isEmpty {
                inlineEmpty(text: L10n.t("لا يوجد نشاط خلال 24 ساعة", "No activity in last 24 hours"))
            } else {
                VStack(spacing: 6) {
                    ForEach(actionRows, id: \.sessionKey) { row in
                        actionRowView(row)
                    }
                }
            }
        }
    }

    // ── آخر 30 يوم (كانت 14 — طلب المالك) ──
    private var last30Section: some View {
        DSComposerSection(title: L10n.t("نشطون آخر 30 يوم", "Last 30 Days"),
                          icon: "calendar",
                          tint: tint,
                          trailing: "\(recentRows.count)",
                          index: 3) {
            if recentRows.isEmpty {
                inlineEmpty(text: L10n.t("لا يوجد نشاط في آخر 30 يوم", "No activity in last 30 days"))
            } else {
                VStack(spacing: 6) {
                    ForEach(recentRows, id: \.sessionKey) { row in
                        recentlyActiveRow(row)
                    }
                }
            }
        }
    }

    // MARK: - الصفوف

    /// صف موحّد: الصورة (ونقطة الاتصال) + الاسم + أيقونة ووصف + طرف (الوقت)
    private func activityRow<Trailing: View>(avatarUrl: String?, online: Bool, name: String,
                                             icon: String, iconTint: Color, detail: String,
                                             @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            avatarView(avatarUrl, online: online)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(iconTint)
                        .accessibilityHidden(true)
                    Text(detail)
                        .font(DS.Font.plex(12))
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            trailing()
        }
        .frame(minHeight: 36)
        .dsRowBox()
        .accessibilityElement(children: .combine)
    }

    /// وقت نسبي صغير في طرف الصف
    private func timeText(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.plex(11.5, weight: .bold))
            .foregroundColor(DS.Color.textTertiary)
            .monospacedDigit()
            .lineLimit(1)
    }

    // MARK: - Active now row (with online dot + screen)
    private func activeNowRow(_ row: ActiveMemberRow) -> some View {
        // نقطة خضراء فقط لو نشط فعلاً خلال آخر 5 دقائق
        let trulyOnline = row.secondsSinceActive < 300
        return activityRow(avatarUrl: row.avatarUrl, online: trulyOnline, name: row.fullName,
                           icon: sourceIcon(row.source), iconTint: DS.Color.textSecondary,
                           detail: screenLabel(row.currentScreen, source: row.source)) {
            SysStatusChip(text: secondsLabel(row.secondsSinceActive), tint: DS.Color.success)
        }
    }

    // MARK: - Action row (24h)
    private func actionRowView(_ row: RecentActionRow) -> some View {
        activityRow(avatarUrl: row.avatarUrl, online: false, name: row.fullName,
                    icon: actionIcon(row.actionKind, source: row.source),
                    iconTint: actionColor(row.actionKind, source: row.source),
                    detail: actionLabel(row)) {
            timeText(minutesLabel(row.minutesAgo))
        }
    }

    // MARK: - Recently active row (no online dot)
    private func recentlyActiveRow(_ row: RecentlyActiveRow) -> some View {
        activityRow(avatarUrl: row.avatarUrl, online: false, name: row.fullName,
                    icon: sourceIcon(row.source), iconTint: DS.Color.textTertiary,
                    detail: screenLabel(row.currentScreen, source: row.source)) {
            timeText(hoursLabel(row.hoursSinceActive))
        }
    }

    private func avatarView(_ urlString: String?, online: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if let urlString, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(DS.Color.textTertiary.opacity(0.15))
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(tint)
                    )
            }

            if online {
                ActivityOnlineDot()
            }
        }
        .accessibilityHidden(true)
    }

    /// حالة فارغة داخل القسم: أيقونة بدائرة + سطر
    private func inlineEmpty(text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DS.Color.textTertiary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(DS.Color.textTertiary.opacity(0.12)))
                .accessibilityHidden(true)
            Text(text)
                .font(DS.Font.plex(12, weight: .medium))
                .foregroundColor(DS.Color.fieldValue)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.md)
        .accessibilityElement(children: .combine)
    }
    // MARK: - Action helpers
    private func actionIcon(_ kind: String, source: String? = nil) -> String {
        switch kind {
        case "screen_visit":           return sourceIcon(source)
        case "news_add":               return "square.and.pencil"
        case "news_comment":           return "text.bubble.fill"
        case "news_like":              return "heart.fill"
        case "poll_vote":              return "checkmark.square.fill"
        case "device_active":          return "iphone.gen3"
        case "web_session":            return "globe"
        default:
            if kind.hasPrefix("request_") { return "tray.fill" }
            return "bolt.fill"
        }
    }

    private func actionColor(_ kind: String, source: String? = nil) -> Color {
        switch kind {
        case "screen_visit":           return source == "web" ? DS.Color.accent : DS.Color.primary
        case "news_add":               return DS.Color.primary
        case "news_comment":           return DS.Color.info
        case "news_like":              return DS.Color.error
        case "poll_vote":              return DS.Color.warning
        case "web_session":            return DS.Color.accent
        case "device_active":          return DS.Color.primary
        default:
            if kind.hasPrefix("request_") { return DS.Color.warning }
            return DS.Color.textSecondary
        }
    }

    private func actionLabel(_ row: RecentActionRow) -> String {
        switch row.actionKind {
        case "screen_visit":
            return L10n.t("في: \(screenLabel(row.actionDetail, source: row.source))",
                          "On: \(screenLabel(row.actionDetail, source: row.source))")
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

    private func minutesLabel(_ m: Int) -> String {
        if m < 1 { return L10n.t("الآن", "now") }
        if m < 60 { return L10n.t("\(m) د", "\(m)m") }
        let h = m / 60
        return L10n.t("\(h) س", "\(h)h")
    }

    private func sourceIcon(_ source: String?) -> String {
        switch source {
        case "web": return "globe"
        case "app": return "iphone.gen3"
        default:    return "questionmark.circle"
        }
    }

    // MARK: - Labels
    private func screenLabel(_ key: String?, source: String?) -> String {
        guard let key = key, !key.isEmpty else {
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
        case "profile":   return L10n.t("حسابي", "Profile")
        case "admin":     return L10n.t("الإدارة", "Admin")
        case "news":      return L10n.t("الأخبار", "News")
        case "projects":  return L10n.t("المشاريع", "Projects")
        default:          return key
        }
    }

    private func secondsLabel(_ s: Int) -> String {
        if s < 30 { return L10n.t("الآن", "now") }
        if s < 60 { return L10n.t("ثوانٍ", "secs") }
        let m = s / 60
        return L10n.t("\(m) د", "\(m)m")
    }

    private func hoursLabel(_ h: Int) -> String {
        if h < 1 { return L10n.t("قريباً", "recent") }
        if h < 24 { return L10n.t("\(h) س", "\(h)h") }
        let d = h / 24
        return L10n.t("\(d) ي", "\(d)d")
    }

    // MARK: - Fetching
    private func fetch() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        async let now = fetchNow()
        async let recent = fetchRecent()
        async let actions = fetchActions24h()
        async let membership: Void = fetchMembershipCounts()
        let (n, r, a, _) = await (now, recent, actions, membership)
        // مفتاح فريد لكل جلسة: عضو + مصدر (app أو web)
        // هذا يسمح لنفس الشخص بجهازين (iPhone + Web) أن يظهر صفّين
        func deviceKey(_ id: UUID, _ source: String?) -> String { "\(id)-\(source ?? "")" }

        // ① "الآن" — رتّب بالأحدث أولاً، dedup per جلسة (memberId + source)
        var seenNow = Set<String>()
        nowRows = n
            .sorted { $0.secondsSinceActive < $1.secondsSinceActive }
            .filter { seenNow.insert(deviceKey($0.memberId, $0.source)).inserted }

        // ② "24 ساعة" — شيل الجلسات الموجودة في "الآن"، dedup per جلسة
        var seenActions = Set<String>()
        actionRows = a
            .filter { !seenNow.contains(deviceKey($0.memberId, $0.source)) }
            .filter { seenActions.insert(deviceKey($0.memberId, $0.source)).inserted }

        // ③ "14 يوم" — شيل الجلسات الموجودة في "الآن" أو "24 ساعة"
        let excludedDevices = seenNow.union(seenActions)
        var seenRecent = Set<String>()
        recentRows = r
            .sorted { $0.hoursSinceActive < $1.hoursSinceActive }
            .filter { !excludedDevices.contains(deviceKey($0.memberId, $0.source)) }
            .filter { seenRecent.insert(deviceKey($0.memberId, $0.source)).inserted }
    }

    private func fetchMembershipCounts() async {
        do {
            membershipCounts = try await SupabaseConfig.client.rpc("admin_membership_counts").execute().value
            usage = await AppUsageStats.fetch()
            membershipCountsFailed = false
        } catch {
            guard !Log.isCancellation(error) else { return }
            membershipCountsFailed = true
            Log.fetchError("خطأ جلب عدد الأعضاء داخل المنظومة", error)
        }
    }

    private func fetchActions24h() async -> [RecentActionRow] {
        struct Row: Decodable {
            let memberId: UUID
            let fullName: String?
            let avatarUrl: String?
            let actionKind: String
            let actionLabel: String?
            let actionAt: String?
            let source: String?
            let minutesAgo: Int
            enum CodingKeys: String, CodingKey {
                case memberId = "member_id"
                case fullName = "full_name"
                case avatarUrl = "avatar_url"
                case actionKind = "action_kind"
                case actionLabel = "action_label"
                case actionAt = "action_at"
                case source
                case minutesAgo = "minutes_ago"
            }
        }
        do {
            let payload: [String: AnyEncodable] = ["hours_back": AnyEncodable(24)]
            let response = try await SupabaseConfig.client.rpc(
                "get_recent_member_actions", params: payload
            ).execute()
            let decoded = try JSONDecoder().decode([Row].self, from: response.data)
            return decoded.map {
                RecentActionRow(
                    memberId: $0.memberId,
                    fullName: $0.fullName ?? "",
                    avatarUrl: $0.avatarUrl,
                    actionKind: $0.actionKind,
                    actionDetail: $0.actionLabel ?? "",
                    source: $0.source,
                    minutesAgo: $0.minutesAgo
                )
            }
            .sorted { $0.minutesAgo < $1.minutesAgo }
        } catch {
            Log.warning("[Actions24h] فشل: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchNow() async -> [ActiveMemberRow] {
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
            return decoded.map {
                ActiveMemberRow(
                    memberId: $0.memberId,
                    fullName: $0.fullName ?? "",
                    avatarUrl: $0.avatarUrl,
                    currentScreen: $0.currentScreen,
                    source: $0.currentScreenSource,
                    secondsSinceActive: $0.secondsSinceActive
                )
            }
        } catch {
            Log.warning("[ActiveNow] فشل: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchRecent() async -> [RecentlyActiveRow] {
        struct Row: Decodable {
            let memberId: UUID
            let fullName: String?
            let avatarUrl: String?
            let currentScreen: String?
            let currentScreenSource: String?
            let hoursSinceActive: Int
            enum CodingKeys: String, CodingKey {
                case memberId = "member_id"
                case fullName = "full_name"
                case avatarUrl = "avatar_url"
                case currentScreen = "current_screen"
                case currentScreenSource = "current_screen_source"
                case hoursSinceActive = "hours_since_active"
            }
        }
        do {
            let payload: [String: AnyEncodable] = ["days_back": AnyEncodable(30)]
            let response = try await SupabaseConfig.client.rpc(
                "get_recently_active_members", params: payload
            ).execute()
            let decoded = try JSONDecoder().decode([Row].self, from: response.data)
            // استثني النشطين الآن (آخر 5 دقائق) من قائمة 14 يوم لتجنب التكرار
            return decoded
                .filter { $0.hoursSinceActive >= 1 || ($0.hoursSinceActive == 0 && false) }
                .map {
                    RecentlyActiveRow(
                        memberId: $0.memberId,
                        fullName: $0.fullName ?? "",
                        avatarUrl: $0.avatarUrl,
                        currentScreen: $0.currentScreen,
                        source: $0.currentScreenSource,
                        hoursSinceActive: $0.hoursSinceActive
                    )
                }
        } catch {
            Log.warning("[RecentActive] فشل: \(error.localizedDescription)")
            return []
        }
    }

    private func startTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { await fetch() }
        }
    }
}

struct ActiveMemberRow {
    let memberId: UUID
    let fullName: String
    let avatarUrl: String?
    let currentScreen: String?
    let source: String?
    let secondsSinceActive: Int
}

struct RecentlyActiveRow {
    let memberId: UUID
    let fullName: String
    let avatarUrl: String?
    let currentScreen: String?
    let source: String?
    let hoursSinceActive: Int
}

struct RecentActionRow {
    let memberId: UUID
    let fullName: String
    let avatarUrl: String?
    let actionKind: String
    let actionDetail: String
    let source: String?
    let minutesAgo: Int
}

// MARK: - مفاتيح الصفوف
// نفس الشخص قد يظهر بجلستين (التطبيق + الموقع) — المفتاح عضو + مصدر (كما في الجلب)
// بدل رقم العضو وحده (كان يكرّر المعرّف في القائمة نفسها).

private extension ActiveMemberRow {
    var sessionKey: String { "\(memberId)-\(source ?? "")" }
}

private extension RecentlyActiveRow {
    var sessionKey: String { "\(memberId)-\(source ?? "")" }
}

private extension RecentActionRow {
    var sessionKey: String { "\(memberId)-\(source ?? "")" }
}

// MARK: - نقطة «متصل الآن»

/// نقطة خضراء بحلقة تتّسع بهدوء — ثابتة مع «تقليل الحركة»
private struct ActivityOnlineDot: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .stroke(DS.Color.success.opacity(pulse ? 0 : 0.55), lineWidth: 2)
                    .frame(width: pulse ? 22 : 11, height: pulse ? 22 : 11)
            }
            Circle()
                .fill(DS.Color.success)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(DS.Color.background, lineWidth: 2))
        }
        .frame(width: 11, height: 11)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}
