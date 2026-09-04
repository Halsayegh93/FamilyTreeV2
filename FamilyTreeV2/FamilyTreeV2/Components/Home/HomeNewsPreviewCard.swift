import SwiftUI

/// بطاقة «آخر الأخبار» في الرئيسية — معاينة حيّة بصورة الكاتب والتفاعلات.
///
/// مهم: هذه بنية `View` مستقلة في ملف خاص بها، وليست دالة داخل `HomeNewsView`
/// تُرجع `some View`. عند بنائها سابقاً كجزء من جسم الرئيسية تضخّم عمق نوع
/// الواجهة حتى انهار التطبيق عند الإقلاع بطفح مكدس أثناء بناء بيانات أنواع
/// Swift (EXC_BAD_ACCESS في منطقة حارس المكدس، بتكرار
/// swift::SubstGenericParametersFromMetadata::buildDescriptorPath).
/// البنية المستقلة تجعل النوع عند الأب مجرّد `HomeNewsPreviewCard`.
struct HomeNewsPreviewCard: View {
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var memberVM: MemberViewModel

    /// يُستدعى عند الضغط على البطاقة لفتح صفحة الأخبار
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                header
                content
                if newsVM.allNews.count > 3 { showAllButton }
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            // بلا هذا تلتقط زخارف الخلفية المزاحة نقرات فوق حدود البطاقة
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Color.primary.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: DS.Color.primaryDark.opacity(0.12), radius: 16, x: 0, y: 6)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - الهيدر

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 40, height: 40)
                    .shadow(color: DS.Color.primary.opacity(0.35), radius: 8, x: 0, y: 4)
                Image(systemName: "newspaper.fill")
                    .font(DS.Font.scaled(17, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("الأخبار والمناسبات", "News & Events"))
                    .font(DS.Font.scaled(18, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                if !newsVM.allNews.isEmpty {
                    Text("\(newsVM.allNews.count) " + L10n.t("منشور", "POSTS"))
                        .font(DS.Font.scaled(11, weight: .heavy))
                        .foregroundColor(DS.Color.textSecondary)
                        .tracking(0.6)
                }
            }

            Spacer()

            if todayCount > 0 { todayBadge }
        }
    }

    /// عدد الأخبار المنشورة اليوم
    private var todayCount: Int {
        newsVM.allNews.filter { Calendar.current.isDateInToday($0.timestamp) }.count
    }

    private var todayBadge: some View {
        Text(L10n.t("جديد اليوم", "New today"))
            .font(DS.Font.scaled(10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 4)
            .background(Capsule().fill(DS.Color.error))
    }

    // MARK: - المحتوى

    @ViewBuilder
    private var content: some View {
        if newsVM.isLoading && newsVM.allNews.isEmpty {
            VStack(spacing: DS.Spacing.sm) {
                ForEach(0..<2, id: \.self) { _ in
                    DSSkeletonRow(avatarSize: 40)
                }
            }
            .padding(.vertical, DS.Spacing.sm)
        } else if newsVM.allNews.isEmpty {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "newspaper")
                    .font(DS.Font.scaled(18))
                    .foregroundColor(DS.Color.textTertiary)
                Text(L10n.t("لا توجد أخبار بعد", "No news yet"))
                    .font(DS.Font.scaled(13, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
                Spacer()
            }
            .padding(.vertical, DS.Spacing.md)
        } else {
            VStack(spacing: DS.Spacing.md) {
                // مناسبات الأسبوع (زواج/مولود/وفاة) أولاً — هي ما يهم العائلة أكثر
                if !weekOccasions.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs + 2) {
                        Text(L10n.t("مناسبات هذا الأسبوع", "This week's occasions"))
                            .font(DS.Font.scaled(11, weight: .heavy))
                            .foregroundColor(DS.Color.textSecondary)
                            .tracking(0.4)
                        ForEach(weekOccasions) { occasion in
                            HomeOccasionRow(news: occasion)
                        }
                    }
                }
                ForEach(previewPosts) { news in
                    HomeNewsPreviewRow(
                        news: news,
                        member: news.author_id.flatMap { memberVM.member(byId: $0) },
                        likes: newsVM.likesCountByPost[news.id] ?? 0,
                        comments: newsVM.commentsCountByPost[news.id] ?? 0
                    )
                }
            }
        }
    }

    private static let occasionTypes: Set<String> = ["زواج", "مولود", "وفاة"]

    /// مناسبات آخر ٧ أيام (حتى ٣)، وإن لم توجد فأحدث مناسبة خلال ٣٠ يوماً
    private var weekOccasions: [NewsPost] {
        let all = newsVM.allNews.filter { Self.occasionTypes.contains($0.type) }
        let week = all.filter { HomeDates.isWithinLastDays($0.timestamp, days: 7) }
        if !week.isEmpty { return Array(week.prefix(3)) }
        if let latest = all.first(where: { HomeDates.isWithinLastDays($0.timestamp, days: 30) }) {
            return [latest]
        }
        return []
    }

    /// أحدث الأخبار للمعاينة، بلا تكرار المناسبات المعروضة أعلاه
    private var previewPosts: [NewsPost] {
        let excluded = Set(weekOccasions.map { $0.id })
        let count = weekOccasions.isEmpty ? 3 : 2
        return Array(newsVM.allNews.filter { !excluded.contains($0.id) }.prefix(count))
    }

    private var showAllButton: some View {
        HStack(spacing: DS.Spacing.xs + 2) {
            Text(L10n.t("عرض كل الأخبار", "Show all news"))
                .font(DS.Font.scaled(13, weight: .bold))
            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .font(DS.Font.scaled(11, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(DS.Color.gradientPrimary))
        .shadow(color: DS.Color.primary.opacity(0.30), radius: 10, x: 0, y: 5)
        .padding(.top, DS.Spacing.xs)
    }

    private var cardBackground: some View {
        ZStack {
            DS.Color.surface
            Circle()
                .fill(DS.Color.primary.opacity(0.16))
                .frame(width: 220, height: 220)
                .blur(radius: 55)
                .offset(x: 130, y: -90)
            Circle()
                .fill(DS.Color.secondary.opacity(0.12))
                .frame(width: 160, height: 160)
                .blur(radius: 45)
                .offset(x: -80, y: 120)
            Circle()
                .fill(DS.Color.accent.opacity(0.12))
                .frame(width: 130, height: 130)
                .blur(radius: 38)
                .offset(x: -100, y: -70)
        }
    }
}

/// صف معاينة خبر واحد — بنية مستقلة أيضاً لإبقاء عمق النوع منخفضاً.
struct HomeNewsPreviewRow: View {
    let news: NewsPost
    let member: FamilyMember?
    let likes: Int
    let comments: Int

    private var isAdminIdentity: Bool {
        news.author_name == L10n.t("إدارة العائلة", "Family Admin")
            || news.author_name == "إدارة العائلة"
    }

    private var displayName: String {
        isAdminIdentity ? news.author_name : (member?.fourPartName ?? news.author_name)
    }

    private var roleColor: Color {
        switch news.role_color {
        case "purple": return DS.Color.adminRole
        case "orange": return DS.Color.supervisorRole
        case "green":  return DS.Color.success
        default:       return DS.Color.primary
        }
    }

    private var thumbURL: URL? {
        news.mediaURLs.first.flatMap { URL(string: $0) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            avatar

            VStack(alignment: .leading, spacing: 3) {
                Text(news.content)
                    .font(DS.Font.scaled(13, weight: .medium))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                metaRow
            }

            Spacer(minLength: 0)

            if let thumbURL {
                CachedAsyncImage(url: thumbURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    DS.Color.mutedBackground
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if isAdminIdentity {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.sm + 2, style: .continuous)
                    .fill(LinearGradient(colors: [DS.Color.accentDark, DS.Color.primary],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "checkmark.shield.fill")
                    .font(DS.Font.scaled(14, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 32, height: 32)
        } else {
            DSMemberAvatar(
                name: news.author_name,
                avatarUrl: member?.avatarUrl,
                size: 32,
                roleColor: roleColor
            )
        }
    }

    private var metaRow: some View {
        HStack(spacing: 4) {
            Text(displayName)
                .font(DS.Font.scaled(11, weight: isAdminIdentity ? .bold : .medium))
                .foregroundColor(isAdminIdentity ? DS.Color.primary : DS.Color.textSecondary)
                .lineLimit(1)
            Text("•")
                .font(DS.Font.scaled(11))
                .foregroundColor(DS.Color.textTertiary)
            Text(Self.relativeTime(news.timestamp))
                .font(DS.Font.scaled(11))
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1)

            if news.hasPoll { metaChip(icon: "chart.bar.fill", value: nil) }
            if likes > 0 { metaChip(icon: "heart.fill", value: likes) }
            if comments > 0 { metaChip(icon: "bubble.left.fill", value: comments) }
        }
    }

    private func metaChip(icon: String, value: Int?) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(DS.Font.scaled(11, weight: .bold))
            if let value {
                Text("\(value)")
                    .font(DS.Font.scaled(11, weight: .bold))
            }
        }
        .foregroundColor(DS.Color.textTertiary)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static func relativeTime(_ date: Date) -> String {
        relativeFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

/// صف «آخر مناسبة» أعلى بطاقة الأخبار — نوع المناسبة بلونه وأيقونته + النص.
struct HomeOccasionRow: View {
    let news: NewsPost

    private var color: Color { NewsTypeHelper.color(for: news.type) }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            ZStack {
                Circle().fill(color.opacity(0.16))
                Image(systemName: NewsTypeHelper.icon(for: news.type))
                    .font(DS.Font.scaled(14, weight: .bold))
                    .foregroundColor(color)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(news.type)
                        .font(DS.Font.scaled(10, weight: .heavy))
                        .foregroundColor(color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.12)))
                    Text(HomeDates.relativeString(news.timestamp))
                        .font(DS.Font.scaled(10))
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)
                }
                Text(news.content)
                    .font(DS.Font.scaled(13, weight: .semibold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(color.opacity(0.18), lineWidth: 1)
        )
    }
}
