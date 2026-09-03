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
                ForEach(Array(newsVM.allNews.prefix(3))) { news in
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
                Circle().fill(DS.Color.gradientPrimary)
                Image(systemName: "megaphone.fill")
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 32, height: 32)
            .overlay(Circle().strokeBorder(DS.Color.headerBorder, lineWidth: 1))
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
