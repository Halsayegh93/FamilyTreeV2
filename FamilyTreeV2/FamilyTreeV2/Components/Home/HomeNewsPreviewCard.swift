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
    /// أخبار من حظرهم المستخدم لا تظهر في المعاينة (Guideline 1.2)
    @ObservedObject private var blockedStore = BlockedMembersStore.shared
    /// نقطة «جديد» بجانب العنوان إذا فيه خبر لم يُفتح
    @ObservedObject private var newDots = NewContentTracker.shared

    /// يُستدعى عند الضغط على البطاقة لفتح صفحة الأخبار
    let onTap: () -> Void
    /// يفتح صفحة الأخبار على خبر بعينه (الضغط على صف الخبر) — بدونه يفتح الصفحة نفسها
    var onOpenNews: ((UUID) -> Void)? = nil

    private func open(_ news: NewsPost) {
        if let onOpenNews { onOpenNews(news.id) } else { onTap() }
    }

    /// الأخبار بلا منشورات المحظورين (منشور الإدارة بلا كاتب لا يُخفى)
    private var visibleNews: [NewsPost] {
        guard !blockedStore.entries.isEmpty else { return newsVM.allNews }
        return newsVM.allNews.filter { news in
            guard let authorId = news.author_id else { return true }
            return !blockedStore.isBlocked(id: authorId, name: news.author_name)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Button(action: onTap) { header.contentShape(Rectangle()) }
                .buttonStyle(.plain)
            content
            if visibleNews.count > 3 {
                // الزرّ الموحّد (ثانوي) — السهم بعد النص
                Button(action: onTap) { showAllButton }
                    .buttonStyle(.ds(.cancel))
                    .padding(.top, DS.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // البطاقة الواحدة (`.dsCard`) — نفس بطاقة الترحيب وبطاقات الأقسام
        .dsCard(padding: DS.Spacing.lg)
    }

    // MARK: - الهيدر

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            // لون قسم «الأخبار» في الرئيسية — من عائلة اللوحة (AppSection.HomeTile.news)
            // رسم بطاقة الأخبار للاتجاه المختار، وإلا الشارة الحالية
            FT5STrial.newsCardArt(tint: AppSection.HomeTile.news.ink)
                                .map { AnyView($0.frame(width: DS.Icon.sizeLg, height: DS.Icon.tapTarget)) }

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xsm) {
                    Text(L10n.t("الأخبار والمناسبات", "News & Events"))
                        .dsFont(.title)
                        .foregroundColor(DS.Color.textPrimary)
                    if newDots.hasNew(.news) { DSNewDot(size: 9) }
                }
                .animation(DS.Anim.snappy, value: newDots.hasNew(.news))
                if !newsVM.allNews.isEmpty {
                    // الإجمالي من السيرفر — لا عدد المحمَّل فقط
                    Text("\(max(newsVM.totalNewsCount, newsVM.allNews.count)) " + L10n.t("منشور", "posts"))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }

            Spacer()

            if todayCount > 0 { todayBadge }
        }
    }

    /// عدد الأخبار المنشورة اليوم
    private var todayCount: Int {
        visibleNews.filter { Calendar.current.isDateInToday($0.timestamp) }.count
    }

    private var todayBadge: some View {
        DSStatusChip(text: L10n.t("جديد اليوم", "New today"), tint: DS.Color.error)
    }

    // MARK: - المحتوى

    @ViewBuilder
    private var content: some View {
        if newsVM.isLoading && newsVM.allNews.isEmpty {
            // التحميل الموحّد: مجسّم الأخبار يتنفّس
            DSPageLoader(section: .news, fillsSpace: false)
                .padding(.vertical, DS.Spacing.sm)
        } else if visibleNews.isEmpty {
            // الحالة الفارغة الموحّدة (مجسّم الأخبار + عنوان) داخل البطاقة
            DSEmptyView(L10n.t("لا توجد أخبار بعد", "No news yet"), section: .news, style: .inline)
        } else {
            VStack(spacing: DS.Spacing.sm) {
                // آخر مناسبة (زواج/مولود/وفاة) أولاً — هي ما يهم العائلة أكثر
                if let occasion = latestOccasion {
                    Button { open(occasion) } label: { HomeOccasionRow(news: occasion) }
                        .buttonStyle(DSScaleButtonStyle())
                }
                ForEach(Array(previewPosts.enumerated()), id: \.element.id) { idx, news in
                    if idx > 0 {
                        // فاصل رفيع بين الأخبار — أنعم من تكديسها بلا فواصل
                        Rectangle()
                            .fill(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke))
                            .frame(height: DS.Border.width)
                            .padding(.leading, DS.Icon.row + DS.Spacing.sm)
                    }
                    Button { open(news) } label: {
                        HomeNewsPreviewRow(
                            news: news,
                            member: news.author_id.flatMap { memberVM.member(byId: $0) },
                            likes: newsVM.likesCountByPost[news.id] ?? 0,
                            comments: newsVM.commentsCountByPost[news.id] ?? 0
                        )
                        .padding(.vertical, DS.Spacing.xxs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
            }
        }
    }

    private static let occasionTypes: Set<String> = ["زواج", "مولود", "وفاة"]

    /// أحدث مناسبة خلال آخر 30 يوماً — إن وُجدت
    private var latestOccasion: NewsPost? {
        visibleNews.first {
            Self.occasionTypes.contains($0.type)
                && HomeDates.isWithinLastDays($0.timestamp, days: 30)
        }
    }

    /// أحدث الأخبار للمعاينة، بلا تكرار المناسبة المعروضة أعلاه
    private var previewPosts: [NewsPost] {
        let excluded = latestOccasion?.id
        return Array(visibleNews.filter { $0.id != excluded }.prefix(latestOccasion == nil ? 3 : 2))
    }

    private var showAllButton: some View {
        HStack(spacing: DSBox.buttonSpacing) {
            Text(L10n.t("عرض كل الأخبار", "Show all news"))
            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .dsGlyph(DSButtonSize.regular.glyph)
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
        case "green":  return DS.Color.monitorRole
        default:       return DS.Color.brand   // دور العضو: كحلي ثابت (معنى)
        }
    }

    private var thumbURL: URL? {
        news.mediaURLs.first.flatMap { URL(string: $0) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            avatar

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(news.content)
                    .dsFont(.callout)
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
                .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                .clipShape(RoundedRectangle(cornerRadius: DS.Icon.discRadiusSmall, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if isAdminIdentity {
            ZStack {
                Circle().fill(DS.Color.gradientPrimary)
                // مكبّر صوت مصمت ونبضة ذهبية واحدة كل ٨ ث (طلب المالك ٢٠٢٦-١٠-٠٥ «باعتدال»)
                FTNewsBadge(type: "إعلان", tint: DS.Color.textOnPrimary, seed: Int(news.id.uuid.0), style: .onColor)
            }
            .frame(width: DS.Icon.row, height: DS.Icon.row)
            .overlay(Circle().strokeBorder(DS.Color.headerBorder, lineWidth: DS.Border.width))
        } else {
            DSMemberAvatar(
                name: news.author_name,
                avatarUrl: member?.avatarUrl,
                size: DS.Icon.row,
                roleColor: roleColor
            )
        }
    }

    private var metaRow: some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(displayName)
                .dsFont(isAdminIdentity ? .badge : .footnote)
                .foregroundColor(isAdminIdentity ? DS.Color.primary : DS.Color.textSecondary)
                .lineLimit(1)
            Text("•")
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
            Text(Self.relativeTime(news.timestamp))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1)

            if news.hasPoll { metaChip(icon: "chart.bar.fill", value: nil) }
            if likes > 0 { metaChip(icon: "heart.fill", value: likes) }
            if comments > 0 { metaChip(icon: "bubble.left.fill", value: comments) }
        }
    }

    private func metaChip(icon: String, value: Int?) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            Image(dsSymbol: icon)
                .dsGlyph(DS.Glyph.xs)
            if let value {
                Text("\(value)")
                    .dsFont(.badge)
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
    /// هالة الاحتفال الذهبية تحيّي كل مناسبة جديدة مرة واحدة (يُحفظ عند الاختفاء حتى لا تقفز الحركة)
    @AppStorage("ftCelebratedOccasion") private var celebratedId = ""

    private var color: Color { NewsTypeHelper.color(for: news.type) }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            ZStack {
                Circle().fill(color.opacity(DS.Opacity.tintFillStrong))
                // شارة متحرّكة للنوع (مهد يتأرجح، خاتمان يلتحمان، ألعاب نارية فوق الأبراج…) — «وفاة» هلال ثابت
                if FTNewsBadges.hasArt(for: news.type, currentIcon: NewsTypeHelper.icon(for: news.type)) {
                    FTNewsBadge(type: news.type, tint: color, seed: 0,
                                celebrate: celebratedId != news.id.uuidString)
                } else {
                    Image(dsSymbol: NewsTypeHelper.icon(for: news.type))
                        .dsGlyph(DS.Glyph.md)
                        .foregroundColor(color)
                }
            }
            .frame(width: DS.Icon.rowLarge, height: DS.Icon.rowLarge)
            .onDisappear { celebratedId = news.id.uuidString }

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xsm) {
                    DSStatusChip(text: news.type, tint: color, size: .mini)
                    Text(HomeDates.relativeString(news.timestamp))
                        .dsFont(.micro)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)
                }
                Text(news.content)
                    .dsFont(.rowTitleCompact)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(DS.Card.padding)
        .background(
            RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
                .fill(color.opacity(DS.Opacity.tintFillSoft))
        )
    }
}
