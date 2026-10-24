import SwiftUI

/// بطاقة «الأخبار والمناسبات» في الرئيسية — ملمومة (طلب المالك ٢٠٢٦-١٠-٢٤ «ملموم أكثر شوي وأصغر شوي»):
/// رأس بسطر واحد (المجسّم، العنوان، «عرض كل الأخبار» مع العدد)، ثم آخر مناسبة بلون نوعها،
/// ثم صفّان بسطر واحد لكلٍّ منهما: ختم النوع بلونه + النص + (النوع · الوقت · التفاعل).
///
/// مهم: هذه بنية `View` مستقلة في ملف خاص بها، وليست دالة داخل `HomeNewsView`
/// تُرجع `some View`. عند بنائها سابقاً كجزء من جسم الرئيسية تضخّم عمق نوع
/// الواجهة حتى انهار التطبيق عند الإقلاع بطفح مكدس أثناء بناء بيانات أنواع
/// Swift (EXC_BAD_ACCESS في منطقة حارس المكدس، بتكرار
/// swift::SubstGenericParametersFromMetadata::buildDescriptorPath).
/// البنية المستقلة تجعل النوع عند الأب مجرّد `HomeNewsPreviewCard` — والرأس والصفوف بنى مستقلة كذلك.
struct HomeNewsPreviewCard: View {
    @EnvironmentObject private var newsVM: NewsViewModel
    /// أخبار من حظرهم المستخدم لا تظهر في المعاينة (Guideline 1.2)
    @ObservedObject private var blockedStore = BlockedMembersStore.shared
    /// نقطة «جديد» بجانب العنوان إذا فيه خبر لم يُفتح
    @ObservedObject private var newDots = NewContentTracker.shared

    /// يُستدعى عند الضغط على الرأس لفتح صفحة الأخبار
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
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // الرأس كله زرّ واحد يفتح صفحة الأخبار
            Button(action: onTap) {
                HomeNewsBoxHeader(hasNew: newDots.hasNew(.news),
                                  total: newsVM.allNews.isEmpty ? nil : max(newsVM.totalNewsCount, newsVM.allNews.count))
                    .contentShape(Rectangle())
            }
            .buttonStyle(DSPressStyle())
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // البطاقة الواحدة (`.dsCard`) — بحشوة أضيق من قبل (كانت ١٦)
        .dsCard(padding: DS.Spacing.md)
    }

    // MARK: - المحتوى

    @ViewBuilder
    private var content: some View {
        if (newsVM.isLoadingNews || newsVM.isLoading) && newsVM.allNews.isEmpty {
            // التحميل الموحّد: مجسّم الأخبار يتنفّس
            DSPageLoader(section: .news, fillsSpace: false)
                .padding(.vertical, DS.Spacing.sm)
        } else if visibleNews.isEmpty {
            // الحالة الفارغة الموحّدة (مجسّم الأخبار + عنوان) داخل البطاقة
            DSEmptyView(L10n.t("لا توجد أخبار بعد", "No news yet"), section: .news, style: .inline)
        } else {
            VStack(spacing: 0) {
                // آخر مناسبة (زواج/مولود/وفاة) أولاً — هي ما يهم العائلة أكثر
                if let occasion = latestOccasion {
                    Button { open(occasion) } label: { HomeOccasionRow(news: occasion) }
                        .buttonStyle(DSPressStyle())
                        .padding(.bottom, DS.Spacing.xxs)
                }
                ForEach(Array(previewPosts.enumerated()), id: \.element.id) { idx, news in
                    if idx > 0 {
                        // فاصل شعري بين الصفوف يبدأ بعد صورة الكاتب
                        Rectangle()
                            .fill(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke))
                            .frame(height: DS.Border.width)
                            .padding(.leading, NewsKit.sealRow + DS.Spacing.sm)
                    }
                    Button { open(news) } label: {
                        HomeNewsPreviewRow(
                            news: news,
                            member: news.author_id.flatMap { memberVM.member(byId: $0) },
                            likes: newsVM.likesCountByPost[news.id] ?? 0,
                            comments: newsVM.commentsCountByPost[news.id] ?? 0,
                            votes: (newsVM.pollVotesByPost[news.id] ?? [:]).values.reduce(0, +)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DSPressStyle())
                }
            }
        }
    }

    /// أحدث مناسبة خلال آخر ٣٠ يوماً — إن وُجدت
    private var latestOccasion: NewsPost? {
        visibleNews.first {
            NewsKit.occasionTypes.contains($0.type)
                && HomeDates.isWithinLastDays($0.timestamp, days: NewsKit.occasionDays)
        }
    }

    /// أحدث الأخبار للمعاينة، بلا تكرار المناسبة المعروضة أعلاه
    private var previewPosts: [NewsPost] {
        let excluded = latestOccasion?.id
        return Array(visibleNews.filter { $0.id != excluded }
            .prefix(NewsKit.homePreviewCount - (latestOccasion == nil ? 0 : 1)))
    }
}

/// رأس مربّع الأخبار بسطر واحد: المجسّم + العنوان + نقطة «جديد» … «عرض كل الأخبار» بعدده.
/// إن ضاق السطر (جوال صغير أو خط كبير) يقصر الرابط إلى «الكل» ثم إلى العدد والسهم.
struct HomeNewsBoxHeader: View {
    let hasNew: Bool
    /// الإجمالي من السيرفر — لا عدد المحمَّل فقط (طلب المالك)؛ nil قبل وصول الأخبار
    let total: Int?

    private enum LinkStyle { case full, short, countOnly }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(.full)
            row(.short)
            row(.countOnly)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.t("الأخبار والمناسبات", "News & Events"))
        .accessibilityValue(total.map { L10n.t("\($0) منشور", "\($0) posts") } ?? "")
        .accessibilityHint(L10n.t("يفتح كل الأخبار", "Opens all news"))
    }

    private func row(_ style: LinkStyle) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            // مجسّم الصحيفة — نفس رسم بطاقة الأخبار، مصغّراً
            FT5STrial.newsCardArt(tint: AppSection.HomeTile.news.ink)
                .map {
                    AnyView($0.scaleEffect(NewsKit.homeArtScale)
                        .frame(width: NewsKit.homeArtWidth, height: NewsKit.homeArtHeight))
                }

            HStack(spacing: DS.Spacing.xsm) {
                Text(L10n.t("الأخبار والمناسبات", "News & Events"))
                    .dsFont(.title)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                if hasNew { DSNewDot(size: NewsKit.homeNewDot) }
            }
            .animation(DS.Anim.snappy, value: hasNew)

            Spacer(minLength: DS.Spacing.sm)

            link(style)
        }
    }

    /// «عرض كل الأخبار ٢٤ ‹» بلون القسم — صغير ومدمج في الرأس بدل الزرّ العريض
    private func link(_ style: LinkStyle) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            switch style {
            case .full: Text(L10n.t("عرض كل الأخبار", "Show all news")).fixedSize()
            case .short: Text(L10n.t("الكل", "All")).fixedSize()
            case .countOnly: EmptyView()
            }
            if let total {
                Text("\(total)")
                    .dsFont(.micro)
                    .monospacedDigit()
                    .padding(.horizontal, DS.Spacing.xsm)
                    .padding(.vertical, DS.Spacing.xxs)
                    .background(Capsule().fill(AppSection.news.ink.opacity(DS.Opacity.tintFill)))
                    .fixedSize()
            }
            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .dsGlyph(DS.Glyph.sm)
        }
        .dsFont(.chipCompact)
        .foregroundColor(AppSection.news.ink)
    }
}

/// صف معاينة خبر واحد بسطر — صورة الكاتب + النص + (النوع · الوقت · التفاعل) + صورة مصغّرة.
/// (طلب المالك ٢٠٢٦-١٠-٢٥: صورة الكاتب لا ختم النوع؛ النوع يبقى بلونه في السطر الصغير)
/// بنية مستقلة لإبقاء عمق النوع منخفضاً.
struct HomeNewsPreviewRow: View {
    let news: NewsPost
    /// الكاتب من الشجرة — لصورته ولون دوره (nil لمنشور الإدارة أو كاتب غير محمَّل)
    let member: FamilyMember?
    let likes: Int
    let comments: Int
    /// مجموع أصوات التصويت (إن كان الخبر تصويتاً)
    var votes: Int = 0

    private var thumbURL: URL? {
        news.mediaURLs.first.flatMap { URL(string: $0) }
    }

    /// النص، وإن خلا الخبر من النص: سؤال التصويت أو «صورة»
    private var previewText: String {
        let text = news.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        if let q = news.poll_question?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty { return q }
        return news.mediaURLs.isEmpty ? NewsTypeHelper.displayName(for: news.type) : L10n.t("صورة", "Photo")
    }

    private var isAdminIdentity: Bool {
        news.author_name == L10n.t("إدارة العائلة", "Family Admin")
            || news.author_name == "إدارة العائلة"
    }

    private var roleColor: Color {
        switch news.role_color {
        case "purple": return DS.Color.adminRole
        case "orange": return DS.Color.supervisorRole
        case "green":  return DS.Color.monitorRole
        default:       return DS.Color.brand   // دور العضو: كحلي ثابت (معنى)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            avatar

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(previewText)
                    .dsFont(.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HomeNewsMetaLine(news: news, likes: likes, comments: comments, votes: votes)
            }

            if let thumbURL {
                CachedAsyncImage(url: thumbURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    DS.Color.mutedBackground
                }
                .frame(width: NewsKit.homeThumb, height: NewsKit.homeThumb)
                .clipShape(RoundedRectangle(cornerRadius: DS.Icon.discRadiusSmall, style: .continuous))
            }
        }
        .padding(.vertical, DS.Spacing.xsm)
    }

    /// صورة الكاتب بحلقة لون دوره — ومنشور الإدارة قرص كحلي بمكبّر الصوت
    @ViewBuilder
    private var avatar: some View {
        if isAdminIdentity {
            ZStack {
                Circle().fill(DS.Color.gradientPrimary)
                FTNewsBadge(type: "إعلان", tint: DS.Color.textOnPrimary, seed: Int(news.id.uuid.0), style: .onColor)
            }
            .frame(width: NewsKit.sealRow, height: NewsKit.sealRow)
            .overlay(Circle().strokeBorder(DS.Color.headerBorder, lineWidth: DS.Border.width))
        } else {
            DSMemberAvatar(
                name: news.author_name,
                avatarUrl: member?.avatarUrl,
                size: NewsKit.sealRow,
                roleColor: roleColor
            )
        }
    }
}

/// سطر صغير تحت نص الخبر: النوع بلونه · الوقت · «مراجعة» · الأصوات/الإعجاب/التعليقات
struct HomeNewsMetaLine: View {
    let news: NewsPost
    let likes: Int
    let comments: Int
    let votes: Int

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(NewsTypeHelper.displayName(for: news.type))
                .dsFont(.newsKicker)
                .foregroundColor(NewsTypeHelper.color(for: news.type))
                .lineLimit(1)
                .fixedSize()
            Text("·")
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
            Text(NewsKit.timeText(news.timestamp))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1)

            // بانتظار موافقة الإدارة
            if news.approval_status == "pending" {
                Image(systemName: "hourglass")
                    .dsGlyph(DS.Glyph.xs)
                    .foregroundColor(DS.Color.warning)
                    .accessibilityLabel(L10n.t("بانتظار المراجعة", "Pending review"))
            }
            if news.hasPoll { NewsCountMark(icon: "chart.bar.fill", value: votes) }
            if likes > 0 { NewsCountMark(icon: "heart.fill", value: likes) }
            if comments > 0 { NewsCountMark(icon: "bubble.left.fill", value: comments) }
        }
    }
}

/// صف «آخر مناسبة» أعلى بطاقة الأخبار — ختم النوع + (النوع · الوقت) + النص على أرضية بلون النوع الخفيف.
struct HomeOccasionRow: View {
    let news: NewsPost
    /// هالة الاحتفال الذهبية تحيّي كل مناسبة جديدة مرة واحدة (يُحفظ عند الاختفاء حتى لا تقفز الحركة)
    @AppStorage("ftCelebratedOccasion") private var celebratedId = ""

    private var color: Color { NewsTypeHelper.color(for: news.type) }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            NewsTypeSeal(type: news.type, size: NewsKit.sealOccasion,
                         celebrate: celebratedId != news.id.uuidString)
                .onDisappear { celebratedId = news.id.uuidString }

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(NewsTypeHelper.displayName(for: news.type))
                        .dsFont(.newsKicker)
                        .foregroundColor(color)
                        .fixedSize()
                    Text("·")
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                    Text(NewsKit.timeText(news.timestamp))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)
                }
                Text(news.content)
                    .dsFont(.calloutMedium)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
                .fill(color.opacity(DS.Opacity.tintFillSoft))
        )
    }
}
