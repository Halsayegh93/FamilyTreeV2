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
}

/// شريط «المستجدات» — الرابط بين الرئيسية وبقية الأقسام.
///
/// شرائح صغيرة، كل شريحة رقم + وجهة: الأخبار الجديدة تفتح صفحة الأخبار،
/// الأعضاء الجدد يفتحون الشجرة، الإشعارات تفتح مركز الإشعارات،
/// والطلبات المعلّقة (للمشرفين) تفتح لوحة الإدارة.
/// لا تظهر شريحة رقمها صفر، ويختفي الشريط كله إن لم يكن فيه شيء.
struct HomeUpdatesStrip: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @EnvironmentObject private var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel
    /// الديوانيات ليست كائن بيئة عاماً — نجلبها هنا (بكاش داخلي في الـ ViewModel)
    @StateObject private var diwaniyasVM = DiwaniyasViewModel()

    let onNews: () -> Void
    let onTree: () -> Void
    let onNotifications: () -> Void
    let onAdmin: () -> Void
    let onDiwaniyas: () -> Void

    /// نافذة «الجديد» بالأيام
    private let window = 7

    private var newPostsCount: Int {
        newsVM.allNews.filter { HomeDates.isWithinLastDays($0.timestamp, days: window) }.count
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

    /// معرّف اليوم بترقيم التطبيق: 0=السبت … 6=الجمعة
    private var todayIndex: Int { Calendar.current.component(.weekday, from: Date()) % 7 }

    private var openDiwaniyas: [Diwaniya] {
        diwaniyasVM.diwaniyas.filter { $0.approvalStatus == "approved" && $0.isClosed != true }
    }

    /// ديوانيات تنعقد اليوم
    private var diwaniyasTodayCount: Int {
        guard diwaniyasEnabled else { return 0 }
        return openDiwaniyas.filter { ($0.scheduleDays ?? []).contains(todayIndex) }.count
    }

    /// ديوانيات لها أيام انعقاد هذا الأسبوع (حين لا يوجد شيء اليوم)
    private var diwaniyasThisWeekCount: Int {
        guard diwaniyasEnabled else { return 0 }
        return openDiwaniyas.filter { !($0.scheduleDays ?? []).isEmpty }.count
    }

    private var hasAnything: Bool {
        newPostsCount + newMembersCount + unreadCount + pendingCount
            + diwaniyasTodayCount + diwaniyasThisWeekCount > 0
    }

    var body: some View {
        // VStack موجود دائماً حتى يعمل .task ولو كان الشريط فارغاً
        VStack(spacing: 0) {
        if hasAnything {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.sm) {
                    if pendingCount > 0 {
                        HomeUpdateChip(
                            icon: "tray.full.fill",
                            count: pendingCount,
                            label: L10n.t("بانتظارك", "Awaiting you"),
                            color: DS.Color.warning,
                            action: onAdmin
                        )
                    }
                    if newPostsCount > 0 {
                        HomeUpdateChip(
                            icon: "newspaper.fill",
                            count: newPostsCount,
                            label: L10n.t("أخبار جديدة", "New posts"),
                            color: DS.Color.primary,
                            action: onNews
                        )
                    }
                    if newMembersCount > 0 {
                        HomeUpdateChip(
                            icon: "person.badge.plus",
                            count: newMembersCount,
                            label: L10n.t("أعضاء جدد", "New members"),
                            color: DS.Color.secondary,
                            action: onTree
                        )
                    }
                    if unreadCount > 0 {
                        HomeUpdateChip(
                            icon: "bell.badge.fill",
                            count: unreadCount,
                            label: L10n.t("إشعارات", "Notifications"),
                            color: DS.Color.accent,
                            action: onNotifications
                        )
                    }
                    if diwaniyasTodayCount > 0 {
                        HomeUpdateChip(
                            icon: "map.fill",
                            count: diwaniyasTodayCount,
                            label: L10n.t("ديوانية اليوم", "Diwaniya today"),
                            color: DS.Color.tileDiwaniya,
                            action: onDiwaniyas
                        )
                    } else if diwaniyasThisWeekCount > 0 {
                        HomeUpdateChip(
                            icon: "map.fill",
                            count: diwaniyasThisWeekCount,
                            label: L10n.t("ديوانيات هذا الأسبوع", "Diwaniyas this week"),
                            color: DS.Color.tileDiwaniya,
                            action: onDiwaniyas
                        )
                    }
                }
                .padding(.horizontal, DS.Spacing.xs)
            }
        }
        }
        .task {
            if diwaniyasEnabled, diwaniyasVM.diwaniyas.isEmpty {
                await diwaniyasVM.fetchDiwaniyas()
            }
        }
    }
}

/// شريحة واحدة في شريط المستجدات
struct HomeUpdateChip: View {
    let icon: String
    let count: Int
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: DS.Spacing.sm) {
                ZStack {
                    Circle().fill(color.opacity(0.16))
                    Image(systemName: icon)
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(color)
                }
                .frame(width: 28, height: 28)

                Text("\(count)")
                    .font(DS.Font.scaled(16, weight: .heavy))
                    .foregroundColor(DS.Color.textPrimary)
                    .contentTransition(.numericText())

                Text(label)
                    .font(DS.Font.scaled(12, weight: .semibold))
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
            }
            .padding(.leading, 6)
            .padding(.trailing, DS.Spacing.md)
            .padding(.vertical, 6)
            .background(Capsule().fill(DS.Color.surface))
            .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 1))
            .shadow(color: color.opacity(0.12), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel("\(count) \(label)")
    }
}
