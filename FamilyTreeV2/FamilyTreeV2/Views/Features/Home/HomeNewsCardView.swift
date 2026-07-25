import SwiftUI

// MARK: - كرت الخبر — تصميم نظيف بهرمية واضحة
// منشورات الإدارة تلبس هوية الهيدر (درع متدرّج + خيط علوي)،
// والتصويت بأشرطة نسب حيّة بدل أرقام صمّاء.
struct HomeNewsCardView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.colorScheme) private var colorScheme

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

    private var shortDisplayName: String {
        // هوية الإدارة: نعرض الاسم المحفوظ كما هو ولا نستبدله باسم العضو
        if isAdminIdentityPost { return authorName }
        let name = authorMember?.fullName ?? authorName
        let parts = name.split(separator: " ")
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
                    .font(DS.Font.scaled(14))
                    .foregroundColor(DS.Color.textPrimary.opacity(0.95))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, isAdminIdentityPost ? DS.Spacing.md : 0)
                    .padding(.bottom, DS.Spacing.sm)
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
                .padding(.top, 2)
                .padding(.bottom, 4)
        }
        // منشور الإدارة: خلفية مزرقّة تميّزه عن المنشورات الشخصية البيضاء
        .background(
            ZStack {
                DS.Color.surface
                if isAdminIdentityPost { DS.Color.primary.opacity(0.07) }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(isAdminIdentityPost ? DS.Color.primary.opacity(0.45)
                                            : DS.Color.textTertiary.opacity(0.15),
                        lineWidth: isAdminIdentityPost ? 1.4 : 0.75)
        )
        .dsCardShadow()
    }

    // MARK: - هيدر الكرت

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            Button {
                guard !isAdminIdentityPost, let member = authorMember else { return }
                onMemberTap(member)
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    authorAvatar

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(shortDisplayName)
                                .font(DS.Font.scaled(14, weight: .bold))
                                .foregroundColor(isAdminIdentityPost ? .white : DS.Color.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            if isAdminIdentityPost {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(DS.Font.scaled(12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }

                        HStack(spacing: 3) {
                            Image(systemName: NewsTypeHelper.icon(for: type))
                                .font(DS.Font.scaled(8, weight: .bold))
                            Text(NewsTypeHelper.displayName(for: type))
                                .font(DS.Font.scaled(9, weight: .semibold))
                        }
                        .foregroundColor(isAdminIdentityPost ? .white : typeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(isAdminIdentityPost ? SwiftUI.Color.white.opacity(0.22)
                                                        : typeColor.opacity(0.10))
                        .clipShape(Capsule())
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if approvalStatus == "pending" {
                Text(L10n.t("مراجعة", "Review"))
                    .font(DS.Font.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.warning)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(DS.Color.warning.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(DS.Color.warning.opacity(0.30), lineWidth: 1))
            }

            if canDelete || canReport || canEdit {
                Menu {
                    if canEdit {
                        Button(action: onEditTap) { Label(L10n.t("تعديل", "Edit"), systemImage: "pencil") }
                    }
                    if canDelete {
                        Button(role: .destructive, action: onDeleteTap) { Label(L10n.t("حذف", "Delete"), systemImage: "trash") }
                    }
                    if canReport {
                        Button(action: onReportTap) { Label(L10n.t("إبلاغ", "Report"), systemImage: "exclamationmark.bubble") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(DS.Font.scaled(14, weight: .semibold))
                        .foregroundColor(isAdminIdentityPost ? SwiftUI.Color.white.opacity(0.9)
                                                             : DS.Color.textTertiary)
                        .frame(width: 44, height: 44)   // هدف لمس ≥44pt
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.top, isAdminIdentityPost ? DS.Spacing.sm + 2 : DS.Spacing.md)
        .padding(.bottom, isAdminIdentityPost ? DS.Spacing.sm + 2 : DS.Spacing.sm)
        // ترويسة رسمية بتدرّج الهيدر — كورقة رسمية للعائلة
        .background(
            Group {
                if isAdminIdentityPost {
                    ZStack {
                        DS.Color.gradientPrimary
                        DS.Color.headerVeil
                    }
                }
            }
        )
    }

    /// صورة الناشر — درع متدرّج بهوية الهيدر لمنشورات الإدارة
    @ViewBuilder
    private var authorAvatar: some View {
        if isAdminIdentityPost {
            ZStack {
                Circle()
                    .fill(SwiftUI.Color.white.opacity(0.22))
                Image(systemName: "megaphone.fill")
                    .font(DS.Font.scaled(15, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 36, height: 36)
            .overlay(Circle().strokeBorder(SwiftUI.Color.white.opacity(0.35), lineWidth: 1))
        } else {
            DSMemberAvatar(name: authorName,
                           avatarUrl: authorMember?.avatarUrl,
                           size: 32,
                           roleColor: typeColor)
                .overlay(Circle().stroke(DS.Color.textTertiary.opacity(0.30), lineWidth: 1))
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
                                    ProgressView().tint(DS.Color.primary)
                                }
                            }
                        }
                    }
                }
                .aspectRatio(4/5, contentMode: .fit)
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
                        ProgressView().tint(DS.Color.primary)
                    }
                }
                .aspectRatio(4/5, contentMode: .fit)
                .clipped()
            }

            // قلب الإعجاب
            if showDoubleTapHeart {
                Image(systemName: "heart.fill")
                    .font(DS.Font.scaled(60, weight: .bold))
                    .foregroundStyle(DS.Color.textOnPrimary)
                    .dsCardShadow()
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.textTertiary.opacity(0.12), lineWidth: 0.75)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !isLiked { onLikeTap() }
            withAnimation(DS.Anim.bouncy) {
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
        VStack(alignment: .leading, spacing: 6) {
            if let q = pollQuestion, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(q)
                    .font(DS.Font.scaled(13.5, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
            }

            ForEach(Array(pollOptions.enumerated()), id: \.offset) { index, option in
                pollOptionRow(index: index, option: option)
            }

            if totalPollVotes > 0 {
                Text(L10n.t("\(totalPollVotes) صوت", "\(totalPollVotes) votes"))
                    .font(DS.Font.scaled(9.5))
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.top, 1)
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
                            .fill(isSelected ? DS.Color.primary.opacity(0.18)
                                             : DS.Color.textTertiary.opacity(0.10))
                            .frame(width: max(geo.size.width * ratio, ratio > 0 ? 8 : 0))
                            .animation(DS.Anim.smooth, value: ratio)
                    }
                }

                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(DS.Font.scaled(16, weight: .semibold))
                        .foregroundColor(isSelected ? DS.Color.primary : DS.Color.textTertiary)

                    Text(option)
                        .font(DS.Font.scaled(13, weight: isSelected ? .bold : .regular))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)

                    Spacer(minLength: DS.Spacing.sm)

                    if hasVoted {
                        Text("\(percent)٪")
                            .font(DS.Font.scaled(11, weight: .bold))
                            .foregroundColor(isSelected ? DS.Color.primary : DS.Color.textSecondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm + 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(isSelected ? DS.Color.primary.opacity(0.40)
                                       : DS.Color.textTertiary.opacity(0.15),
                            lineWidth: isSelected ? 1.3 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// الوقت أسفل البطاقة — طلب المالك (كان في الهيدر)
    private var timeStamp: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
                .font(DS.Font.scaled(10))
            Text(time)
                .font(DS.Font.caption2)
        }
        .foregroundColor(DS.Color.textTertiary)
    }

    // MARK: - شريط الإجراءات — أزرار شبحية خفيفة بلا كبسولات ثقيلة

    private var actionBar: some View {
        HStack(spacing: DS.Spacing.xs) {
            // Like
            Button(action: onLikeTap) {
                HStack(spacing: 5) {
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
                    .font(DS.Font.scaled(16, weight: .medium))
                    .foregroundColor(isLiked ? DS.Color.error : DS.Color.textSecondary)

                    if likeCount > 0 {
                        Text("\(likeCount)")
                            .font(DS.Font.scaled(12, weight: .semibold))
                            .foregroundColor(isLiked ? DS.Color.error : DS.Color.textSecondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, DS.Spacing.sm)
                .frame(minWidth: 40, minHeight: 44)   // هدف لمس ≥44pt
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLiked ? L10n.t("إلغاء الإعجاب", "Unlike") : L10n.t("إعجاب", "Like"))
            .accessibilityValue(likeCount > 0 ? "\(likeCount)" : "")

            // Comment
            Button(action: onCommentTap) {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.right")
                        .font(DS.Font.scaled(15, weight: .medium))
                        .foregroundColor(DS.Color.textSecondary)

                    if commentCount > 0 {
                        Text("\(commentCount)")
                            .font(DS.Font.scaled(12, weight: .semibold))
                            .foregroundColor(DS.Color.textSecondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, DS.Spacing.sm)
                .frame(minWidth: 40, minHeight: 44)   // هدف لمس ≥44pt
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("تعليقات", "Comments"))
            .accessibilityValue(commentCount > 0 ? "\(commentCount)" : "")

            Spacer()

            // الوقت في نهاية الشريط السفلي
            timeStamp
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}
