import SwiftUI
import Supabase
import PostgREST

// MARK: - Admin Active Members — النشاط (الآن + آخر 14 يوم)
struct AdminActiveMembersView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel

    @State private var nowRows: [ActiveMemberRow] = []
    @State private var recentRows: [RecentlyActiveRow] = []
    @State private var actionRows: [RecentActionRow] = []
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var refreshTimer: Timer?

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.lg) {

                    // ── إحصائية ──
                    statsCard
                        .padding(.top, DS.Spacing.md)

                    // ── زر تحديث الآن ──
                    refreshButton
                        .padding(.horizontal, DS.Spacing.lg)

                    // ── النشطون الآن (آخر 5 دقائق) ──
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: L10n.t("النشطون الآن", "Active Now"),
                            icon: "circle.fill",
                            iconColor: DS.Color.success
                        )

                        if isLoading && nowRows.isEmpty {
                            ProgressView()
                                .padding(.vertical, DS.Spacing.xxxl)
                                .frame(maxWidth: .infinity)
                        } else if nowRows.isEmpty {
                            inlineEmpty(
                                text: L10n.t("لا يوجد نشاط حالياً", "No one active right now")
                            )
                        } else {
                            ForEach(Array(nowRows.enumerated()), id: \.element.memberId) { idx, row in
                                activeNowRow(row)
                                if idx < nowRows.count - 1 {
                                    rowDivider
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    // ── آخر 24 ساعة (مع نوع الإجراء) ──
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: L10n.t("آخر 24 ساعة", "Last 24 Hours"),
                            icon: "clock.arrow.circlepath",
                            trailing: "\(actionRows.count)",
                            iconColor: DS.Color.warning
                        )

                        if actionRows.isEmpty {
                            inlineEmpty(
                                text: L10n.t("لا يوجد نشاط خلال 24 ساعة", "No activity in last 24 hours")
                            )
                        } else {
                            ForEach(Array(actionRows.enumerated()), id: \.element.memberId) { idx, row in
                                actionRowView(row)
                                if idx < actionRows.count - 1 {
                                    rowDivider
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    // ── آخر 14 يوم ──
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: L10n.t("نشطون آخر 14 يوم", "Last 14 Days"),
                            icon: "calendar",
                            trailing: "\(recentRows.count)",
                            iconColor: DS.Color.info
                        )

                        if recentRows.isEmpty {
                            inlineEmpty(
                                text: L10n.t("لا يوجد نشاط في آخر 14 يوم", "No activity in last 14 days")
                            )
                        } else {
                            ForEach(Array(recentRows.enumerated()), id: \.element.memberId) { idx, row in
                                recentlyActiveRow(row)
                                if idx < recentRows.count - 1 {
                                    rowDivider
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    Spacer(minLength: DS.Spacing.xxxl)
                }
            }
            .refreshable { await fetch() }
        }
        .navigationTitle(L10n.t("النشاط", "Activity"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            // أبلغ إن المدير الحالي شاف "النشاط" — يبقيه ضمن النشطين
            MemberActivityTracker.report("admin", force: true)
            await fetch()
            startTimer()
        }
        .onDisappear { refreshTimer?.invalidate() }
    }

    // MARK: - Refresh button
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
            HStack(spacing: 8) {
                if isRefreshing {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(DS.Font.scaled(14, weight: .bold))
                }
                Text(L10n.t("تحديث الآن", "Refresh Now"))
                    .font(DS.Font.scaled(14, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(DS.Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
        .disabled(isRefreshing)
    }

    // MARK: - Action row (24h)
    private func actionRowView(_ row: RecentActionRow) -> some View {
        HStack(spacing: DS.Spacing.md) {
            avatarView(row.avatarUrl, online: false)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.fullName)
                    .font(DS.Font.scaled(14, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: actionIcon(row.actionKind, source: row.source))
                        .font(DS.Font.scaled(10, weight: .semibold))
                        .foregroundColor(actionColor(row.actionKind, source: row.source))
                    Text(actionLabel(row))
                        .font(DS.Font.scaled(11, weight: .semibold))
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(minutesLabel(row.minutesAgo))
                .font(DS.Font.scaled(10, weight: .semibold))
                .foregroundColor(DS.Color.textTertiary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }

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

    // MARK: - Stats card
    private var statsCard: some View {
        HStack(spacing: DS.Spacing.sm) {
            statBox(
                icon: "circle.fill",
                title: L10n.t("الآن", "Now"),
                value: "\(nowRows.count)",
                color: DS.Color.success
            )
            statBox(
                icon: "iphone.gen3",
                title: L10n.t("التطبيق", "App"),
                value: "\(nowRows.filter { $0.source == "app" }.count + recentRows.filter { $0.source == "app" }.count)",
                color: DS.Color.primary
            )
            statBox(
                icon: "globe",
                title: L10n.t("الموقع", "Web"),
                value: "\(nowRows.filter { $0.source == "web" }.count + recentRows.filter { $0.source == "web" }.count)",
                color: DS.Color.accent
            )
            statBox(
                icon: "clock.arrow.circlepath",
                title: L10n.t("14 يوم", "14d"),
                value: "\(recentRows.count)",
                color: DS.Color.info
            )
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func statBox(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(color)
            Text(value)
                .font(DS.Font.scaled(20, weight: .heavy))
                .foregroundColor(DS.Color.textPrimary)
            Text(title)
                .font(DS.Font.scaled(10, weight: .semibold))
                .foregroundColor(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.md)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    // MARK: - Active now row (with online dot + screen)
    private func activeNowRow(_ row: ActiveMemberRow) -> some View {
        // نقطة خضراء فقط لو نشط فعلاً خلال آخر 5 دقائق
        let trulyOnline = row.secondsSinceActive < 300
        return HStack(spacing: DS.Spacing.md) {
            avatarView(row.avatarUrl, online: trulyOnline)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.fullName)
                    .font(DS.Font.scaled(14, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: sourceIcon(row.source))
                        .font(DS.Font.scaled(10, weight: .semibold))
                    Text(screenLabel(row.currentScreen, source: row.source))
                        .font(DS.Font.scaled(11, weight: .semibold))
                }
                .foregroundColor(DS.Color.textSecondary)
            }

            Spacer()

            Text(secondsLabel(row.secondsSinceActive))
                .font(DS.Font.scaled(10, weight: .heavy))
                .foregroundColor(DS.Color.success)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }

    // MARK: - Recently active row (no online dot)
    private func recentlyActiveRow(_ row: RecentlyActiveRow) -> some View {
        HStack(spacing: DS.Spacing.md) {
            avatarView(row.avatarUrl, online: false)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.fullName)
                    .font(DS.Font.scaled(14, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: sourceIcon(row.source))
                        .font(DS.Font.scaled(10, weight: .semibold))
                    Text(screenLabel(row.currentScreen, source: row.source))
                        .font(DS.Font.scaled(11, weight: .regular))
                }
                .foregroundColor(DS.Color.textTertiary)
            }

            Spacer()

            Text(hoursLabel(row.hoursSinceActive))
                .font(DS.Font.scaled(10, weight: .semibold))
                .foregroundColor(DS.Color.textTertiary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }

    private func sourceIcon(_ source: String?) -> String {
        switch source {
        case "web": return "globe"
        case "app": return "iphone.gen3"
        default:    return "questionmark.circle"
        }
    }

    private func avatarView(_ urlString: String?, online: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(DS.Color.textTertiary.opacity(0.15))
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(DS.Color.primary.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(DS.Font.scaled(16))
                            .foregroundColor(DS.Color.primary)
                    )
            }

            if online {
                Circle()
                    .fill(DS.Color.success)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(DS.Color.surface, lineWidth: 2))
            }
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(DS.Color.textTertiary.opacity(0.10))
            .frame(height: 0.5)
            .padding(.leading, DS.Spacing.lg + 56)
    }

    private func inlineEmpty(text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "moon.zzz.fill")
                .font(DS.Font.scaled(20))
                .foregroundColor(DS.Color.textTertiary)
            Text(text)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.lg)
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
        isLoading = true
        defer { isLoading = false }

        async let now = fetchNow()
        async let recent = fetchRecent()
        async let actions = fetchActions24h()
        let (n, r, a) = await (now, recent, actions)
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
            let payload: [String: AnyEncodable] = ["days_back": AnyEncodable(14)]
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
