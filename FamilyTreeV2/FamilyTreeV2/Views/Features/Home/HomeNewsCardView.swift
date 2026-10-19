import SwiftUI

// MARK: - كرت الخبر — تصميم نظيف بهرمية واضحة
// منشورات الإدارة تلبس هوية الهيدر (درع متدرّج + خيط علوي)،
// والتصويت بأشرطة نسب حيّة بدل أرقام صمّاء.
struct HomeNewsCardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.colorScheme) private var colorScheme
    /// قسم الصفحة (الأخبار) — إطار البطاقة (التحميل، اختيار التصويت) يتبعه
    @Environment(\.dsSection) private var section
    private var chromeInk: Color { DS.Color.primary.dsChrome(in: section) }

    let postId: UUID
    let authorName: String
    let authorId: UUID?
    let role: String
    let roleColor: Color
    let time: String
    let type: String
    let content: String
    let imageUrl: String?
    let imageUrls: [String]
    let pollQuestion: String?
    let pollOptions: [String]
    let pollVotes: [Int: Int]
    let selectedPollOption: Int?
    let approvalStatus: String?
    let commentCount: Int
    let likeCount: Int
    let isLiked: Bool
    let onCommentTap: () -> Void
    let onLikeTap: () -> Void
    let onVoteTap: (Int) -> Void
    let canDelete: Bool
    let canReport: Bool
    let canEdit: Bool
    let onDeleteTap: () -> Void
    let onReportTap: () -> Void
    let onEditTap: () -> Void
    let onMemberTap: (FamilyMember) -> Void
    /// تاريخ النشر — ما مضى عليه أكثر من شهرين يظهر بتاريخه أسفل البطاقة يساراً
    var postDate: Date? = nil
    /// «حظر العضو» في قائمة «…» — لغير صاحب الخبر (Guideline 1.2)
    var canBlock: Bool = false
    var onBlockTap: () -> Void = {}

    // Double-tap like animation
    @State private var showDoubleTapHeart = false

    private var authorMember: FamilyMember? {
        guard let authorId else { return nil }
        return memberVM.member(byId: authorId)
    }

    /// منشور نُشر بهوية الإدارة — الاسم المحفوظ يختلف عن اسم العضو الحقيقي
    private var isAdminIdentityPost: Bool {
        authorName == L10n.t("إدارة العائلة", "Family Admin") || authorName == "إدارة العائلة"
    }

    private var isOlderThanTwoMonths: Bool {
        guard let postDate,
              let limit = Calendar.current.date(byAdding: .month, value: -2, to: Date()) else { return false }
        return postDate < limit
    }

    private static func dateFormatter(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
    }

    private var shortDisplayName: String {
        // هوية الإدارة: نعرض الاسم المحفوظ كما هو ولا نستبدله باسم العضو
        if isAdminIdentityPost { return authorName }
        let name = authorMember?.fullName ?? authorName
        // وحدات لا كلمات (PersonName): عضو معروف ← سلسلة الشجرة، وإلا النص الحرّ
        let parts = authorMember?.nameUnits ?? PersonName.units(name)
        guard parts.count > 3, let last = parts.last else { return name }
        let first3 = parts.prefix(3).joined(separator: " ")
        if parts.dropFirst(2).first == last { return first3 }
        return "\(first3) \(last)"
    }

    private var typeColor: Color { NewsTypeHelper.color(for: type) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader

            // المحتوى — ينزل قليلاً عن الترويسة الرسمية حتى لا يلتصق بها
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(content)
                    .dsFont(.bodyCompact)
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, isAdminIdentityPost ? DS.Spacing.md : 0)
                    .padding(.bottom, DS.Spacing.xsm)
            }

            // منطقة الميديا (صور) — double-tap like
            if !imageUrls.isEmpty || imageUrl != nil {
                mediaSection
            }

            // التصويت
            if !pollOptions.isEmpty {
                pollSection
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, DS.Spacing.sm)
            }

            // شريط الإجراءات — بلا فاصل: المسافة تكفي
            actionBar
                .padding(.horizontal, DS.Spacing.md)
                .padding(.top, DS.Spacing.xxs)
                .padding(.bottom, DS.Spacing.xs)
        }
        // منشور الإدارة: لمسة ذهبية خفيفة تميّزه عن المنشورات الشخصية
        .background(isAdminIdentityPost ? DS.Color.accent.opacity(DS.Opacity.tintFillSoft) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous))
        // البطاقة الواحدة (`.dsCard`) — سطح + إطار شعري + لمسة «مجسّمات»
        // خبر الإدارة بلا إطار (طلب المالك) — الإطار الخفيف للأخبار العادية فقط
        .dsCard(padding: nil, stroked: !isAdminIdentityPost)
    }

    // MARK: - هيدر الكرت

    private func openAuthor() {
        guard !isAdminIdentityPost, let member = authorMember else { return }
        onMemberTap(member)
    }

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            // الملف الشخصي يُفتح بالضغط على الصورة أو الاسم فقط — لا على بقية الترويسة
            HStack(spacing: DS.Spacing.sm) {
                Button(action: openAuthor) { authorAvatar }
                    .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Button(action: openAuthor) {
                        // اسم صاحب الخبر على سطر واحد (طلب المالك)
                        Text(shortDisplayName)
                            .dsFont(.rowTitle)
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // سطر خفيف: النوع · الوقت — بدل الكبسولة والوقت أسفل البطاقة
                    HStack(spacing: DS.Spacing.xs) {
                        Image(dsSymbol: NewsTypeHelper.icon(for: type))
                            .dsGlyph(DS.Glyph.micro)
                        Text(NewsTypeHelper.displayName(for: type))
                            .dsFont(.caption)
                        if !isOlderThanTwoMonths {
                            Text("·")
                                .dsFont(.footnote)
                                .foregroundColor(DS.Color.textTertiary)
                            Text(time)
                                .dsFont(.footnote)
                                .foregroundColor(DS.Color.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .foregroundColor(isAdminIdentityPost ? DS.Color.accentDark : typeColor)
                    .allowsHitTesting(false)
                }
            }

            Spacer()

            if approvalStatus == "pending" {
                DSStatusChip(text: L10n.t("مراجعة", "Review"), tint: DS.Color.warning)
            }

            // قائمة «…»: تعديل/حذف للإدارة وصاحب الخبر، و«إبلاغ» و«حظر» لغير صاحبه (طلب المالك)
            if canDelete || canEdit || canReport || canBlock {
                Menu {
                    if canEdit {
                        Button(action: onEditTap) { Label(L10n.t("تعديل", "Edit"), systemImage: "pencil") }
                    }
                    if canReport {
                        Button(action: onReportTap) { Label(L10n.t("إبلاغ", "Report"), systemImage: "flag") }
                    }
                    if canBlock {
                        Button(role: .destructive, action: onBlockTap) {
                            Label(L10n.t("حظر العضو", "Block Member"), systemImage: "hand.raised.fill")
                        }
                    }
                    if canDelete {
                        Button(role: .destructive, action: onDeleteTap) { Label(L10n.t("حذف", "Delete"), systemImage: "trash") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .dsGlyph(DS.Glyph.md, weight: .semibold)
                        .foregroundColor(isAdminIdentityPost ? DS.Color.accentDark
                                                             : DS.Color.textTertiary)
                        .frame(width: DS.Icon.rowLarge, height: DS.Icon.rowLarge)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L10n.t("خيارات الخبر", "Post options"))
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.sm)
        // ترويسة رسمية بتدرّج الهيدر — كورقة رسمية للعائلة
        .background(
            Group {
                // منشور باسم الإدارة بلون مختلف — ذهبي فاتح هادئ لا فاقع (طلب المالك)
                if isAdminIdentityPost {
                    DS.Color.accent.opacity(DS.Opacity.tintFill)
                }
            }
        )
    }

    /// صورة الناشر — درع متدرّج بهوية الهيدر لمنشورات الإدارة
    @ViewBuilder
    private var authorAvatar: some View {
        if isAdminIdentityPost {
            ZStack {
                // كحلي مثل بطاقة الرئيسية — قوس الإعلان الذهبي لا يضيع فوق ذهبي
                Circle().fill(DS.Color.gradientPrimary)
                // مكبّر صوت مصمت ونبضة ذهبية واحدة كل ٨ ث (طلب المالك ٢٠٢٦-١٠-٠٥ «باعتدال»)
                FTNewsBadge(type: "إعلان", tint: DS.Color.textOnPrimary, seed: abs(authorName.hashValue % 89), style: .onColor)
            }
            .frame(width: DS.Icon.row, height: DS.Icon.row)
            .overlay(Circle().strokeBorder(DS.Color.headerBorder, lineWidth: DS.Border.width))
        } else {
            DSMemberAvatar(name: authorName,
                           avatarUrl: authorMember?.avatarUrl,
                           size: DS.Icon.discSmall,
                           roleColor: typeColor)
                .overlay(Circle().stroke(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
        }
    }

    // MARK: - الميديا

    private var mediaSection: some View {
        ZStack {
            if !imageUrls.isEmpty {
                TabView {
                    ForEach(Array(imageUrls.enumerated()), id: \.offset) { _, urlStr in
                        if let encodedStr = urlStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let url = URL(string: encodedStr) {
                            CachedAsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                            } placeholder: {
                                ZStack {
                                    DS.Color.surface
                                    DSPageLoader(size: DS.Icon.state, fillsSpace: false)
                                }
                            }
                        }
                    }
                }
                .aspectRatio(2, contentMode: .fit)
                .clipped()
                .tabViewStyle(.page(indexDisplayMode: imageUrls.count > 1 ? .automatic : .never))
            } else if let urlStr = imageUrl,
                      let encodedStr = urlStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: encodedStr) {
                CachedAsyncImage(url: url) { img in
                    img.resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .clipped()
                } placeholder: {
                    ZStack {
                        DS.Color.surface
                        DSPageLoader(size: DS.Icon.state, fillsSpace: false)
                    }
                }
                .aspectRatio(2, contentMode: .fit)
                .clipped()
            }

            // قلب الإعجاب
            if showDoubleTapHeart {
                Image(systemName: "heart.fill")
                    .dsGlyph(DS.Glyph.doubleTapHeart)
                    .foregroundStyle(DS.Color.textOnPrimary)
                    .dsCardShadow()
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke), lineWidth: DS.Card.strokeWidth)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !isLiked { onLikeTap() }
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : DS.Anim.bouncy) {
                showDoubleTapHeart = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation(DS.Anim.smooth) {
                    showDoubleTapHeart = false
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.top, DS.Spacing.xs)
    }

    // MARK: - التصويت — أشرطة نسب حيّة

    private var totalPollVotes: Int {
        pollOptions.indices.reduce(0) { $0 + (pollVotes[$1] ?? 0) }
    }

    private var pollSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            if let q = pollQuestion, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(q)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
            }

            ForEach(Array(pollOptions.enumerated()), id: \.offset) { index, option in
                pollOptionRow(index: index, option: option)
            }

            if totalPollVotes > 0 {
                Text(L10n.t("\(totalPollVotes) صوت", "\(totalPollVotes) votes"))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
    }

    private func pollOptionRow(index: Int, option: String) -> some View {
        let votes = pollVotes[index] ?? 0
        let isSelected = selectedPollOption == index
        let hasVoted = selectedPollOption != nil
        let ratio = totalPollVotes > 0 ? CGFloat(votes) / CGFloat(totalPollVotes) : 0
        let percent = totalPollVotes > 0 ? Int((ratio * 100).rounded()) : 0

        return Button(action: { onVoteTap(index) }) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Color.background)

                // شريط النسبة — يظهر بعد التصويت فلا يوحي بنتيجة قبل المشاركة
                if hasVoted {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(isSelected ? chromeInk.opacity(DS.Opacity.tintFillStrong)
                                             : DS.Color.textTertiary.opacity(DS.Opacity.cardStroke))
                            .frame(width: max(geo.size.width * ratio, ratio > 0 ? DS.Spacing.sm : 0))
                            .animation(DS.Anim.smooth, value: ratio)
                    }
                }

                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .dsGlyph(DS.Glyph.lg, weight: .semibold)
                        .foregroundColor(isSelected ? chromeInk : DS.Color.textTertiary)

                    Text(option)
                        .dsFont(isSelected ? .rowTitle : .callout)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)

                    Spacer(minLength: DS.Spacing.sm)

                    if hasVoted {
                        Text("\(percent)٪")
                            .dsFont(.badge)
                            .foregroundColor(isSelected ? chromeInk : DS.Color.textSecondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(isSelected ? chromeInk.opacity(DS.Opacity.selectedStroke)
                                       : DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke),
                            lineWidth: isSelected ? DS.Border.widthBold : DS.Border.width)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - شريط الإجراءات — أزرار شبحية خفيفة بلا كبسولات ثقيلة

    private var actionBar: some View {
        HStack(spacing: DS.Spacing.xs) {
            // Like
            Button(action: onLikeTap) {
                HStack(spacing: DS.Spacing.xs) {
                    Group {
                        if #available(iOS 17.0, *) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .symbolEffect(.bounce, value: isLiked)
                        } else {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .scaleEffect(isLiked ? 1.15 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isLiked)
                        }
                    }
                    .dsGlyph(DS.Glyph.lg, weight: .medium)
                    .foregroundColor(isLiked ? DS.Color.sadu : DS.Color.textSecondary)

                    if likeCount > 0 {
                        Text("\(likeCount)")
                            .dsFont(.chip)
                            .foregroundColor(isLiked ? DS.Color.sadu : DS.Color.textSecondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, DS.Spacing.sm)
                .frame(minWidth: DSBox.composerIcon, minHeight: DS.Icon.rowLarge)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLiked ? L10n.t("إلغاء الإعجاب", "Unlike") : L10n.t("إعجاب", "Like"))
            .accessibilityValue(likeCount > 0 ? "\(likeCount)" : "")

            // Comment
            Button(action: onCommentTap) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "bubble.right")
                        .dsGlyph(DS.Glyph.lgCompact, weight: .medium)
                        .foregroundColor(DS.Color.textSecondary)

                    if commentCount > 0 {
                        Text("\(commentCount)")
                            .dsFont(.chip)
                            .foregroundColor(DS.Color.textSecondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, DS.Spacing.sm)
                .frame(minWidth: DSBox.composerIcon, minHeight: DS.Icon.rowLarge)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("تعليقات", "Comments"))
            .accessibilityValue(commentCount > 0 ? "\(commentCount)" : "")

            Spacer()

            // أكثر من شهرين → التاريخ في الزاوية السفلية اليسرى (طلب المالك)
            if isOlderThanTwoMonths, let postDate {
                Text(Self.dateFormatter(for: postDate))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        // المحور فيزيائي (يسار→يمين) حتى يثبت التاريخ يساراً في اللغتين؛ الأزرار يميناً في العربية
        .environment(\.layoutDirection, L10n.isArabic ? .rightToLeft : .leftToRight)
    }
}
