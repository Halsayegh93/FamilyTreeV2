import SwiftUI

/// أدوات مشتركة لبطاقات الرئيسية: تحليل التواريخ والوقت النسبي.
enum HomeDates {
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    static func parse(_ iso: String?) -> Date? {
        guard let s = iso, !s.isEmpty else { return nil }
        return isoFrac.date(from: s) ?? isoPlain.date(from: s)
    }

    static func relativeString(_ date: Date) -> String {
        relative.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return relative.localizedString(for: date, relativeTo: Date())
    }

    static func isWithinLastDays(_ date: Date, days: Int) -> Bool {
        guard let limit = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return false }
        return date >= limit
    }

    /// معرّف اليوم بترقيم التطبيق: 0=السبت … 6=الجمعة
    static var todayIndex: Int { Calendar.current.component(.weekday, from: Date()) % 7 }
}

/// بطاقة «المستجدات» — الرابط بين الرئيسية وبقية الأقسام.
///
/// بطاقة واحدة بأعمدة متساوية بدل كبسولات عائمة. كل عمود: أيقونة مربّعة
/// بتدرّج، رقم، ووجهة. النقطة الحمراء فقط على ما يحتاج انتباهاً.
/// لا يظهر عمود رقمه صفر، وتختفي البطاقة كلها إن لم يكن فيها شيء.
struct HomeUpdatesStrip: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @EnvironmentObject private var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel

    /// الديوانيات تُمرَّر من الرئيسية (تُجلب هناك مرة واحدة)
    let diwaniyas: [Diwaniya]

    let onNews: () -> Void
    let onTree: () -> Void
    let onNotifications: () -> Void
    let onAdmin: () -> Void
    let onDiwaniyas: () -> Void

    /// نافذة «الجديد» بالأيام
    private let window = 7

    private struct Item: Identifiable {
        let id: String
        let icon: String
        let count: Int
        let label: String
        let colors: [Color]
        let attention: Bool
        let action: () -> Void
    }

    // MARK: - الأرقام

    private var newPostsCount: Int {
        newsVM.allNews.filter { HomeDates.isWithinLastDays($0.timestamp, days: window) }.count
    }
    private var postsTodayCount: Int {
        newsVM.allNews.filter { Calendar.current.isDateInToday($0.timestamp) }.count
    }
    private var newMembersCount: Int {
        memberVM.allMembers.filter { m in
            guard m.role != .pending, let d = HomeDates.parse(m.createdAt) else { return false }
            return HomeDates.isWithinLastDays(d, days: window)
        }.count
    }
    private var unreadCount: Int { notificationVM.unreadNotificationsCount }
    private var pendingCount: Int {
        guard authVM.canModerate else { return 0 }
        return adminRequestVM.deceasedRequests.count
            + adminRequestVM.childAddRequests.count
            + adminRequestVM.phoneChangeRequests.count
            + adminRequestVM.newsReportRequests.count
            + adminRequestVM.treeEditRequests.count
            + adminRequestVM.nameChangeRequests.count
            + adminRequestVM.photoSuggestionRequests.count
            + newsVM.pendingNewsRequests.count
            + memberVM.allMembers.filter { $0.role == .pending }.count
    }
    private var diwaniyasEnabled: Bool { appSettingsVM.settings.diwaniyasEnabled ?? true }
    private var openDiwaniyas: [Diwaniya] {
        diwaniyas.filter { $0.approvalStatus == "approved" && $0.isClosed != true }
    }
    private var diwaniyasTodayCount: Int {
        guard diwaniyasEnabled else { return 0 }
        return openDiwaniyas.filter { ($0.scheduleDays ?? []).contains(HomeDates.todayIndex) }.count
    }
    private var diwaniyasThisWeekCount: Int {
        guard diwaniyasEnabled else { return 0 }
        return openDiwaniyas.filter { !($0.scheduleDays ?? []).isEmpty }.count
    }

    private var items: [Item] {
        var out: [Item] = []
        if pendingCount > 0 {
            out.append(.init(id: "pending", icon: "tray.full.fill", count: pendingCount,
                             label: L10n.t("بانتظارك", "Awaiting you"),
                             colors: [DS.Color.warning.opacity(0.85), DS.Color.warning],
                             attention: true, action: onAdmin))
        }
        if newPostsCount > 0 {
            out.append(.init(id: "news", icon: "newspaper.fill", count: newPostsCount,
                             label: L10n.t("أخبار", "Posts"),
                             colors: [DS.Color.primaryLight, DS.Color.primaryDark],
                             attention: postsTodayCount > 0, action: onNews))
        }
        if newMembersCount > 0 {
            out.append(.init(id: "members", icon: "person.badge.plus", count: newMembersCount,
                             label: L10n.t("أعضاء جدد", "New members"),
                             colors: [DS.Color.secondaryLight, DS.Color.tileTreeDeep],
                             attention: false, action: onTree))
        }
        if unreadCount > 0 {
            out.append(.init(id: "notifications", icon: "bell.fill", count: unreadCount,
                             label: L10n.t("إشعارات", "Notifications"),
                             colors: [DS.Color.accentLight, DS.Color.accentDark],
                             attention: true, action: onNotifications))
        }
        if diwaniyasTodayCount > 0 {
            out.append(.init(id: "diwaniya", icon: "map.fill", count: diwaniyasTodayCount,
                             label: L10n.t("ديوانية اليوم", "Diwaniya today"),
                             colors: [DS.Color.tileContact, DS.Color.tileContactDeep],
                             attention: true, action: onDiwaniyas))
        } else if diwaniyasThisWeekCount > 0 {
            out.append(.init(id: "diwaniya", icon: "map.fill", count: diwaniyasThisWeekCount,
                             label: L10n.t("ديوانيات الأسبوع", "This week"),
                             colors: [DS.Color.tileContact, DS.Color.tileContactDeep],
                             attention: false, action: onDiwaniyas))
        }
        return out
    }

    // MARK: - العرض

    var body: some View {
        let items = items
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.t("المستجدات", "What's new"))
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                    Spacer()
                    Text(L10n.t("آخر ٧ أيام", "Last 7 days"))
                        .font(DS.Font.scaled(10.5, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                }
                .padding(.horizontal, DS.Spacing.xs + 2)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.xs),
                                   count: items.count <= 4 ? items.count : 3),
                    spacing: DS.Spacing.xs
                ) {
                    ForEach(items) { item in
                        HomeUpdateColumn(
                            icon: item.icon, count: item.count, label: item.label,
                            colors: item.colors, attention: item.attention, action: item.action
                        )
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.sm + 2)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.sm + 2)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: DS.Color.primaryDark.opacity(0.10), radius: 14, x: 0, y: 6)
        }
    }
}

/// عمود واحد في بطاقة المستجدات
struct HomeUpdateColumn: View {
    let icon: String
    let count: Int
    let label: String
    let colors: [Color]
    let attention: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 40, height: 40)
                            .shadow(color: (colors.last ?? DS.Color.primary).opacity(0.35), radius: 7, x: 0, y: 4)
                        Image(systemName: icon)
                            .font(DS.Font.scaled(16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    if attention {
                        Circle()
                            .fill(DS.Color.error)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(DS.Color.surface, lineWidth: 2))
                            .offset(x: 4, y: -4)
                    }
                }

                Text("\(count)")
                    .font(DS.Font.scaled(20, weight: .heavy))
                    .foregroundColor(DS.Color.textPrimary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(label)
                    .font(DS.Font.scaled(10.5, weight: .semibold))
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.sm)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel("\(count) \(label)")
    }
}
