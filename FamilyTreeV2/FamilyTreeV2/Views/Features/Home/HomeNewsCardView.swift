import SwiftUI

// MARK: - كرت الخبر — «قصاصة جريدة» (إعادة التصميم ٢٠٢٦-١٠-٢٤، طلب المالك «الأخبار داخل القسم يبيلها إعادة تصميم»)
// فوق: ختم النوع بلونه واسمه (مولود، زواج، وفاة، تصويت…) + «بانتظار المراجعة» + «…» ← النص ← الصور
// (ضغطة تفتحها بملء الشاشة، ضغطتان إعجاب) أو التصويت (أشرطة تنمو بلون النوع بعد التصويت) ← تحت:
// الإعجاب والتعليق، والتوقيع (صورة الكاتب · اسمه · الوقت) في الطرف الآخر — كتوقيع آخر الرسالة.
// منشورات الإدارة تبقى بلمسة ذهبية هادئة بلا إطار (طلب المالك). كل جزء بنية مستقلة (عمق نوع منخفض).
struct HomeNewsCardView: View {
    @EnvironmentObject var memberVM: MemberViewModel

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
    /// تاريخ النشر — ما مضى عليه أكثر من شهرين يظهر بتاريخه في سطر التوقيع (أسفل البطاقة يساراً)
    var postDate: Date? = nil
    /// «حظر العضو» في قائمة «…» — لغير صاحب الخبر (Guideline 1.2)
    var canBlock: Bool = false
    var onBlockTap: () -> Void = {}
    /// فتح صورة الخبر بملء الشاشة — رقم الصورة
    var onMediaTap: (Int) -> Void = { _ in }
    /// دخول الصفحة (نفس `dsCardCascade`): الختم يُطبع على البطاقة بعد وصولها، وما يُبنى بالتمرير يظهر مباشرة
    var appeared: Bool = true
    var cascadeIndex: Int = 0

    private var authorMember: FamilyMember? {
        guard let authorId else { return nil }
        return memberVM.member(byId: authorId)
    }

    /// منشور نُشر بهوية الإدارة — الاسم المحفوظ يختلف عن اسم العضو الحقيقي
    private var isAdminIdentityPost: Bool { NewsKit.isAdminIdentity(authorName) }

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

    /// اسم التوقيع بسطر واحد: الأطول أولاً، وإن ضاق السطر يقصر النسب (الثلاثي ثم الاسم والأب) بدل القصّ
    private var bylineNames: [String] {
        if isAdminIdentityPost { return [authorName] }
        let parts = authorMember?.nameUnits ?? PersonName.units(authorMember?.fullName ?? authorName)
        var names: [String] = []
        for candidate in [shortDisplayName, parts.prefix(3).joined(separator: " "), parts.prefix(2).joined(separator: " ")]
        where !candidate.isEmpty && !names.contains(candidate) {
            names.append(candidate)
        }
        return names.isEmpty ? [authorName] : names
    }

    /// الصور (المتعدّدة، وإلا الصورة الواحدة القديمة)
    private var media: [String] {
        if !imageUrls.isEmpty { return imageUrls }
        if let imageUrl, !imageUrl.isEmpty { return [imageUrl] }
        return []
    }

    private var seed: Int { Int(postId.uuid.0) }

    /// الملف الشخصي يُفتح بالضغط على الصورة أو الاسم فقط — لا لمنشور الإدارة
    private var bylineTap: (() -> Void)? {
        guard !isAdminIdentityPost, let member = authorMember else { return nil }
        return { onMemberTap(member) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            NewsCardKicker(
                type: type,
                isPending: approvalStatus == "pending",
                seed: seed,
                stamped: appeared,
                stampIndex: cascadeIndex,
                menuTint: isAdminIdentityPost ? DS.Color.accentDark : DS.Color.textTertiary,
                actions: NewsCardActions(canEdit: canEdit, canReport: canReport, canBlock: canBlock, canDelete: canDelete,
                                         onEdit: onEditTap, onReport: onReportTap, onBlock: onBlockTap, onDelete: onDeleteTap)
            )

            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(content)
                    .dsFont(.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(NewsKit.bodyLineSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !media.isEmpty {
                NewsCardMedia(urls: media, isLiked: isLiked, onLike: onLikeTap, onOpen: onMediaTap)
            }

            if !pollOptions.isEmpty {
                NewsCardPoll(question: pollQuestion, options: pollOptions, votes: pollVotes,
                             selected: selectedPollOption, tint: typeColor, onVote: onVoteTap)
            }

            NewsCardFooter(
                likeCount: likeCount, isLiked: isLiked, commentCount: commentCount,
                onLike: onLikeTap, onComment: onCommentTap,
                byline: NewsBylineView(
                    names: bylineNames,
                    avatarUrl: authorMember?.avatarUrl,
                    isAdmin: isAdminIdentityPost,
                    roleColor: roleColor,
                    time: postDate.map { NewsKit.timeText($0) } ?? time,
                    seed: seed,
                    onTap: bylineTap
                )
            )
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.top, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.xs)
        // حافّة رفيعة بلون النوع عند بداية البطاقة — تُعرف المناسبة من طرفها وأنت تمرّر
        .overlay(alignment: .leading) {
            Capsule()
                .fill(typeColor)
                .frame(width: NewsKit.spineWidth)
                .padding(.vertical, DS.Card.radius)
                .accessibilityHidden(true)
        }
        // منشور الإدارة: لمسة ذهبية خفيفة تميّزه عن المنشورات الشخصية
        .background(isAdminIdentityPost ? DS.Color.accent.opacity(DS.Opacity.tintFillSoft) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous))
        // البطاقة الواحدة (`.dsCard`) — خبر الإدارة بلا إطار (طلب المالك)، الإطار الخفيف للأخبار العادية فقط
        .dsCard(padding: nil, stroked: !isAdminIdentityPost)
    }
}

// MARK: - رأس البطاقة: ختم النوع + اسمه + المراجعة + «…»

/// إجراءات قائمة «…»: تعديل/حذف للإدارة وصاحب الخبر، و«إبلاغ» و«حظر» لغير صاحبه (طلب المالك)
struct NewsCardActions {
    var canEdit = false
    var canReport = false
    var canBlock = false
    var canDelete = false
    var onEdit: () -> Void = {}
    var onReport: () -> Void = {}
    var onBlock: () -> Void = {}
    var onDelete: () -> Void = {}

    var hasAny: Bool { canEdit || canReport || canBlock || canDelete }
}

struct NewsCardKicker: View {
    let type: String
    let isPending: Bool
    let seed: Int
    /// الختم مطبوع (بعد دخول البطاقة) — قبله صغير مائل
    let stamped: Bool
    let stampIndex: Int
    let menuTint: Color
    let actions: NewsCardActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let settled = stamped || reduceMotion
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            // «ختم» النوع يُطبع بنابض بعد وصول البطاقة (أول ٧ بطاقات تباعاً) — «تقليل الحركة»: ساكن
            NewsTypeSeal(type: type, size: NewsKit.sealCard, seed: seed)
                .scaleEffect(settled ? 1 : NewsKit.stampFromScale)
                .rotationEffect(.degrees(settled ? 0 : NewsKit.stampFromAngle))
                .animation(reduceMotion ? nil
                           : DSMotion.iconPop.delay(NewsKit.stampDelay + Double(min(max(stampIndex, 0), 6)) * NewsKit.stampStep),
                           value: stamped)
            Text(NewsTypeHelper.displayName(for: type))
                .dsFont(.newsKicker)
                .foregroundColor(NewsTypeHelper.color(for: type))
                .lineLimit(1)

            if isPending {
                DSStatusChip(text: L10n.t("بانتظار المراجعة", "Pending review"), icon: "hourglass",
                             tint: DS.Color.warning, size: .mini)
            }

            Spacer(minLength: DS.Spacing.sm)

            if actions.hasAny {
                NewsCardMenu(actions: actions, tint: menuTint)
            }
        }
        // ارتفاع ثابت للرأس — بقائمة أو بلا قائمة
        .frame(minHeight: DS.Icon.rowLarge)
    }
}

struct NewsCardMenu: View {
    let actions: NewsCardActions
    let tint: Color

    var body: some View {
        Menu {
            if actions.canEdit {
                Button(action: actions.onEdit) { Label(L10n.t("تعديل", "Edit"), systemImage: "pencil") }
            }
            if actions.canReport {
                Button(action: actions.onReport) { Label(L10n.t("إبلاغ", "Report"), systemImage: "flag") }
            }
            if actions.canBlock {
                Button(role: .destructive, action: actions.onBlock) {
                    Label(L10n.t("حظر العضو", "Block Member"), systemImage: "hand.raised.fill")
                }
            }
            if actions.canDelete {
                Button(role: .destructive, action: actions.onDelete) { Label(L10n.t("حذف", "Delete"), systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .dsGlyph(DS.Glyph.md, weight: .semibold)
                .foregroundColor(tint)
                .frame(width: DS.Icon.rowLarge, height: DS.Icon.rowLarge)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(L10n.t("خيارات الخبر", "Post options"))
    }
}

// MARK: - الصور: ضغطة تفتحها بملء الشاشة، ضغطتان إعجاب، وعدّاد «٢ من ٣»

struct NewsCardMedia: View {
    let urls: [String]
    let isLiked: Bool
    let onLike: () -> Void
    let onOpen: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var showHeart = false

    private func url(_ raw: String) -> URL? {
        raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap { URL(string: $0) }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        ZStack {
            if urls.count == 1 {
                photo(0)
            } else {
                TabView(selection: $page) {
                    ForEach(urls.indices, id: \.self) { idx in
                        photo(idx).tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            // قلب الإعجاب
            if showHeart {
                Image(systemName: "heart.fill")
                    .dsGlyph(DS.Glyph.doubleTapHeart)
                    .foregroundStyle(DS.Color.textOnPrimary)
                    .dsCardShadow()
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
        }
        .aspectRatio(NewsKit.mediaAspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .overlay(shape.stroke(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke), lineWidth: DS.Card.strokeWidth))
        .overlay(alignment: .topTrailing) {
            if urls.count > 1 { counter }
        }
        .contentShape(shape)
        .onTapGesture(count: 2) { likeBurst() }
        .onTapGesture { onOpen(page) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(urls.count > 1 ? L10n.t("\(urls.count) صور", "\(urls.count) photos") : L10n.t("صورة", "Photo"))
        .accessibilityHint(L10n.t("اضغط للتكبير، وضغطتين للإعجاب", "Tap to enlarge, double-tap to like"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen(page) }
    }

    private func photo(_ idx: Int) -> some View {
        CachedAsyncImage(url: url(urls[idx])) { img in
            img.resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } placeholder: {
            ZStack {
                DS.Color.surface
                DSPageLoader(size: DS.Icon.state, fillsSpace: false)
            }
        }
    }

    /// «٢ من ٣» في زاوية الصورة — نفس عدّاد العارض بملء الشاشة
    private var counter: some View {
        Text(verbatim: L10n.t("\(page + 1) من \(urls.count)", "\(page + 1) of \(urls.count)"))
            .dsFont(.micro)
            .monospacedDigit()
            .foregroundColor(DS.Color.overlayTextFull)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs)
            .background(Capsule().fill(DS.Color.shadowHeavy))
            .padding(DS.Spacing.sm)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func likeBurst() {
        if !isLiked { onLike() }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : DS.Anim.bouncy) {
            showHeart = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            withAnimation(DS.Anim.smooth) {
                showHeart = false
            }
        }
    }
}

// MARK: - التصويت: لوحة بلون النوع الخفيف، والأشرطة تنمو بعد التصويت

struct NewsCardPoll: View {
    let question: String?
    let options: [String]
    let votes: [Int: Int]
    let selected: Int?
    let tint: Color
    let onVote: (Int) -> Void

    private var total: Int {
        options.indices.reduce(0) { $0 + (votes[$1] ?? 0) }
    }

    private var questionText: String {
        let q = question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return q.isEmpty ? L10n.t("تصويت", "Poll") : q
    }

    var body: some View {
        let total = total
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xsm) {
                Image(dsSymbol: "chart.bar.fill")
                    .dsGlyph(DS.Glyph.sm)
                    .foregroundColor(tint)
                    .accessibilityHidden(true)
                Text(questionText)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DS.Spacing.sm)
                if total > 0 {
                    Text(L10n.t("\(total) صوت", "\(total) votes"))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize()
                }
            }

            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                NewsPollOptionRow(text: option, votes: votes[index] ?? 0, total: total,
                                  isSelected: selected == index, hasVoted: selected != nil, tint: tint) {
                    onVote(index)
                }
            }

            // النتيجة تظهر بعد المشاركة فلا يوحي الشريط بنتيجة قبلها
            if selected == nil {
                Text(L10n.t("صوّت لتظهر النتيجة", "Vote to see the results"))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(tint.opacity(DS.Opacity.tintFillSoft))
        )
    }
}

struct NewsPollOptionRow: View {
    let text: String
    let votes: Int
    let total: Int
    let isSelected: Bool
    let hasVoted: Bool
    let tint: Color
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// الشريط ينمو من الصفر مرة عند الظهور — و«تقليل الحركة»: يظهر بطوله مباشرة
    @State private var grown = false

    private var ratio: CGFloat { total > 0 ? CGFloat(votes) / CGFloat(total) : 0 }
    private var percent: Int { Int((ratio * 100).rounded()) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
        let shown = hasVoted && grown ? ratio : 0
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .dsGlyph(DS.Glyph.lg, weight: .semibold)
                    .foregroundColor(isSelected ? tint : DS.Color.textTertiary)

                Text(text)
                    .dsFont(isSelected ? .rowTitle : .callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: DS.Spacing.sm)

                if hasVoted {
                    Text("\(percent)٪")
                        .dsFont(.badge)
                        .foregroundColor(isSelected ? tint : DS.Color.textSecondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .frame(minHeight: NewsKit.pollRowMinHeight)
            // شريط النسبة من بداية السطر — يظهر بعد التصويت فقط
            .background(alignment: .leading) {
                GeometryReader { geo in
                    shape
                        .fill(isSelected ? tint.opacity(DS.Opacity.tintFillStrong)
                                         : DS.Color.textTertiary.opacity(DS.Opacity.tintFill))
                        .frame(width: geo.size.width * shown)
                }
            }
            .background(DS.Color.surface)
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(isSelected ? tint.opacity(DS.Opacity.selectedStroke)
                                              : DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke),
                                   lineWidth: isSelected ? DS.Border.widthBold : DS.Border.width)
            )
            .contentShape(shape)
        }
        .buttonStyle(DSPressStyle())
        .animation(reduceMotion ? nil : DS.Anim.smooth, value: shown)
        .onAppear {
            guard !grown else { return }
            if reduceMotion {
                grown = true
            } else {
                withAnimation(DS.Anim.smooth.delay(NewsKit.pollGrowDelay)) { grown = true }
            }
        }
        .accessibilityLabel(text)
        .accessibilityValue(hasVoted ? "\(percent)٪" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - أسفل البطاقة: الإعجاب والتعليق … والتوقيع

struct NewsCardFooter: View {
    let likeCount: Int
    let isLiked: Bool
    let commentCount: Int
    let onLike: () -> Void
    let onComment: () -> Void
    let byline: NewsBylineView

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            NewsLikeButton(count: likeCount, isLiked: isLiked, action: onLike)
            NewsCommentButton(count: commentCount, action: onComment)
            Spacer(minLength: DS.Spacing.sm)
            byline
        }
    }
}

struct NewsLikeButton: View {
    let count: Int
    let isLiked: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Group {
                    if reduceMotion {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                    } else if #available(iOS 17.0, *) {
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

                if count > 0 {
                    // العدد يتدحرج للرقم الجديد — و«تقليل الحركة»: يتبدّل بلا حركة
                    Text("\(count)")
                        .dsFont(.chip)
                        .foregroundColor(isLiked ? DS.Color.sadu : DS.Color.textSecondary)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }
            }
            .padding(.horizontal, DS.Spacing.sm)
            .frame(minWidth: DSBox.composerIcon, minHeight: DS.Icon.rowLarge)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .animation(reduceMotion ? nil : DS.Anim.snappy, value: count)
        .accessibilityLabel(isLiked ? L10n.t("إلغاء الإعجاب", "Unlike") : L10n.t("إعجاب", "Like"))
        .accessibilityValue(count > 0 ? "\(count)" : "")
    }
}

struct NewsCommentButton: View {
    let count: Int
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "bubble.right")
                    .dsGlyph(DS.Glyph.lgCompact, weight: .medium)
                    .foregroundColor(DS.Color.textSecondary)

                if count > 0 {
                    Text("\(count)")
                        .dsFont(.chip)
                        .foregroundColor(DS.Color.textSecondary)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }
            }
            .padding(.horizontal, DS.Spacing.sm)
            .frame(minWidth: DSBox.composerIcon, minHeight: DS.Icon.rowLarge)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .animation(reduceMotion ? nil : DS.Anim.snappy, value: count)
        .accessibilityLabel(L10n.t("تعليقات", "Comments"))
        .accessibilityValue(count > 0 ? "\(count)" : "")
    }
}

/// سطر التوقيع: صورة الكاتب (أو ختم الإدارة) · اسمه · الوقت — يفتح ملفه بالضغط على الصورة أو الاسم
struct NewsBylineView: View {
    /// صيغ الاسم من الأطول للأقصر — يُختار أطول ما يسعه السطر
    let names: [String]
    let avatarUrl: String?
    let isAdmin: Bool
    let roleColor: Color
    let time: String
    let seed: Int
    let onTap: (() -> Void)?

    private func name(_ i: Int) -> String { names.indices.contains(i) ? names[i] : (names.last ?? "") }

    var body: some View {
        if let onTap {
            Button(action: onTap) { fitted.contentShape(Rectangle()) }
                .buttonStyle(DSPressStyle())
                .accessibilityHint(L10n.t("يفتح ملف الكاتب", "Opens the author's profile"))
        } else {
            fitted
        }
    }

    private var fitted: some View {
        ViewThatFits(in: .horizontal) {
            label(name(0))
            label(name(1))
            label(name(2))
        }
    }

    private func label(_ name: String) -> some View {
        HStack(spacing: DS.Spacing.xsm) {
            if isAdmin {
                NewsAdminSeal(size: NewsKit.bylineAvatar, seed: seed)
            } else {
                DSMemberAvatar(name: name, avatarUrl: avatarUrl, size: NewsKit.bylineAvatar, roleColor: roleColor)
                    .overlay(Circle().stroke(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
            }
            // اسم صاحب الخبر على سطر واحد (طلب المالك)
            Text(name)
                .dsFont(.newsByline)
                .foregroundColor(isAdmin ? DS.Color.accent : DS.Color.textSecondary)
                .lineLimit(1)
            Text("·")
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
            Text(time)
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minHeight: DS.Icon.rowLarge)
        .accessibilityElement(children: .combine)
    }
}
