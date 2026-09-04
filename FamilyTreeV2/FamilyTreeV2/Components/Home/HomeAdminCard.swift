import SwiftUI

/// بطاقة الإدارة في الرئيسية — للمشرفين فقط (canModerate).
/// نظرة سريعة: عدد الطلبات المعلّقة، الأعضاء الجدد اليوم، الأخبار بانتظار
/// الموافقة، وآخر ثلاثة أنشطة. الضغط على البطاقة يفتح تبويب الإدارة.
///
/// بنية مستقلة في ملف منفصل حتى لا تُثقل نوع واجهة الرئيسية.
struct HomeAdminCard: View {
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var adminRequestVM: AdminRequestViewModel

    let onOpenAdmin: () -> Void

    private struct ActivityItem: Identifiable {
        let id: UUID
        let icon: String
        let color: Color
        let title: String
        let subtitle: String
        let date: Date
    }

    private var pendingTotal: Int {
        adminRequestVM.deceasedRequests.count
            + adminRequestVM.childAddRequests.count
            + adminRequestVM.phoneChangeRequests.count
            + adminRequestVM.newsReportRequests.count
            + adminRequestVM.treeEditRequests.count
            + adminRequestVM.nameChangeRequests.count
            + adminRequestVM.photoSuggestionRequests.count
            + newsVM.pendingNewsRequests.count
            + memberVM.allMembers.filter { $0.role == .pending }.count
    }

    private var newMembersToday: Int {
        let cal = Calendar.current
        let today = Date()
        return memberVM.allMembers.filter { m in
            guard let d = HomeDates.parse(m.createdAt) else { return false }
            return cal.isDate(d, inSameDayAs: today)
        }.count
    }

    private var recentActivity: [ActivityItem] {
        var items: [ActivityItem] = []
        for m in memberVM.allMembers where m.role == .pending {
            if let d = HomeDates.parse(m.createdAt) {
                items.append(.init(id: m.id, icon: "person.badge.plus", color: DS.Color.success,
                                   title: L10n.t("تسجيل جديد", "New registration"),
                                   subtitle: m.fullName, date: d))
            }
        }
        for r in adminRequestVM.deceasedRequests {
            if let d = HomeDates.parse(r.createdAt) {
                items.append(.init(id: r.id, icon: "heart.slash.fill", color: DS.Color.error,
                                   title: L10n.t("طلب وفاة", "Death request"),
                                   subtitle: r.member?.fullName ?? "", date: d))
            }
        }
        for r in adminRequestVM.childAddRequests {
            if let d = HomeDates.parse(r.createdAt) {
                items.append(.init(id: r.id, icon: "person.2.fill", color: DS.Color.accent,
                                   title: L10n.t("طلب إضافة ابن", "Add child request"),
                                   subtitle: r.member?.fullName ?? "", date: d))
            }
        }
        for n in newsVM.pendingNewsRequests {
            items.append(.init(id: n.id, icon: "newspaper.fill", color: DS.Color.primary,
                               title: L10n.t("خبر بانتظار الموافقة", "News pending"),
                               subtitle: n.author_name, date: n.timestamp))
        }
        return Array(items.sorted { $0.date > $1.date }.prefix(3))
    }

    var body: some View {
        Button(action: onOpenAdmin) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                header
                stats
                if pendingTotal > 0 { warningBanner }
                if !recentActivity.isEmpty { activityList }
                cta
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Color.accent.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: DS.Color.accentDark.opacity(0.10), radius: 14, x: 0, y: 5)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Color.gradientAccent)
                    .frame(width: 40, height: 40)
                    .shadow(color: DS.Color.accent.opacity(0.35), radius: 8, x: 0, y: 4)
                Image(systemName: "shield.lefthalf.filled")
                    .font(DS.Font.scaled(17, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("لوحة الإدارة", "Admin Panel"))
                    .font(DS.Font.scaled(18, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("نظرة سريعة على الطلبات والنشاط", "Quick overview"))
                    .font(DS.Font.scaled(11, weight: .heavy))
                    .foregroundColor(DS.Color.textSecondary)
                    .tracking(0.6)
            }

            Spacer()
        }
    }

    private var stats: some View {
        HStack(spacing: DS.Spacing.sm) {
            stat(icon: "tray.full.fill", value: pendingTotal,
                 label: L10n.t("طلب", "Pending"), color: DS.Color.warning)
            stat(icon: "person.badge.plus", value: newMembersToday,
                 label: L10n.t("جديد اليوم", "New today"), color: DS.Color.success)
            stat(icon: "newspaper.fill", value: newsVM.pendingNewsRequests.count,
                 label: L10n.t("خبر", "News"), color: DS.Color.primary)
        }
    }

    private func stat(icon: String, value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(color)
                Text("\(value)")
                    .font(DS.Font.scaled(17, weight: .heavy))
                    .foregroundColor(DS.Color.textPrimary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            Text(label)
                .font(DS.Font.scaled(11, weight: .medium))
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
        }
        .padding(.vertical, DS.Spacing.sm)
        .padding(.horizontal, DS.Spacing.xs)
        .frame(maxWidth: .infinity)
        .background(DS.Color.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private var warningBanner: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DS.Font.scaled(13, weight: .bold))
                .foregroundColor(DS.Color.warning)
            Text(L10n.t("عندك \(pendingTotal) طلب ينتظر مراجعتك",
                        "\(pendingTotal) requests awaiting review"))
                .font(DS.Font.scaled(12, weight: .semibold))
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.warning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.warning.opacity(0.20), lineWidth: 1)
        )
    }

    private var activityList: some View {
        VStack(spacing: 0) {
            ForEach(Array(recentActivity.enumerated()), id: \.element.id) { index, item in
                activityRow(item)
                    .padding(.vertical, DS.Spacing.sm)
                if index < recentActivity.count - 1 {
                    Rectangle()
                        .fill(DS.Color.textTertiary.opacity(0.10))
                        .frame(height: 0.5)
                }
            }
        }
    }

    private func activityRow(_ item: ActivityItem) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            ZStack {
                Circle().fill(item.color.opacity(0.15)).frame(width: 32, height: 32)
                Image(systemName: item.icon)
                    .font(DS.Font.scaled(12, weight: .semibold))
                    .foregroundColor(item.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(DS.Font.scaled(12, weight: .semibold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(DS.Font.scaled(11, weight: .medium))
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DS.Spacing.sm)

            Text(HomeDates.relativeString(item.date))
                .font(DS.Font.scaled(11))
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1)
        }
    }

    private var cta: some View {
        HStack(spacing: DS.Spacing.xs + 2) {
            Text(L10n.t("الانتقال للوحة الإدارة", "Open Admin Dashboard"))
                .font(DS.Font.scaled(13, weight: .bold))
            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .font(DS.Font.scaled(11, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(DS.Color.gradientAccent))
        .shadow(color: DS.Color.accent.opacity(0.30), radius: 10, x: 0, y: 5)
        .padding(.top, DS.Spacing.xs)
    }

    private var cardBackground: some View {
        ZStack {
            DS.Color.surface
            Circle()
                .fill(DS.Color.accent.opacity(0.14))
                .frame(width: 220, height: 220)
                .blur(radius: 55)
                .offset(x: 130, y: -90)
            Circle()
                .fill(DS.Color.warning.opacity(0.08))
                .frame(width: 150, height: 150)
                .blur(radius: 45)
                .offset(x: -80, y: 120)
        }
    }
}
