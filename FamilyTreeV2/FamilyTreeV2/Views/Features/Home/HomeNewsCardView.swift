import SwiftUI

// MARK: - كرت الخبر — Glass card styling
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

    private var shortDisplayName: String {
        let name = authorMember?.shortFullName ?? authorName
        let parts = name.split(separator: " ")
        guard parts.count > 4, let last = parts.last else { return name }
        let first3 = parts.prefix(3).joined(separator: " ")
        if parts[2] == last { return first3 }
        return "\(first3) \(last)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // هيدر الكرت
            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                Button {
                    if let member = authorMember {
                        onMemberTap(member)
                    }
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        ZStack {
                            if let urlStr = authorMember?.avatarUrl, let url = URL(string: urlStr) {
                                CachedAsyncImage(url: url) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [NewsTypeHelper.color(for: type), NewsTypeHelper.color(for: type).opacity(0.7)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .overlay(
                                            Text(String(authorName.first ?? "A"))
                                                .font(DS.Font.scaled(15, weight: .bold))
                                                .foregroundColor(DS.Color.textOnPrimary)
                                        )
                                }
                                .frame(width: 38, height: 38)
                                .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [NewsTypeHelper.color(for: type), NewsTypeHelper.color(for: type).opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 38, height: 38)
                                Text(String(authorName.first ?? "A"))
                                    .font(DS.Font.scaled(15, weight: .bold))
                                    .foregroundColor(DS.Color.textOnPrimary)
                            }
                        }
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(DS.Color.textTertiary.opacity(0.3), lineWidth: 1)
                        )
                        .dsGlowShadow()

                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortDisplayName)
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.textPrimary)
                                .lineLimit(1)
                            
                            HStack(spacing: 3) {
                                Image(systemName: NewsTypeHelper.icon(for: type))
                                    .font(DS.Font.scaled(9, weight: .bold))
                                Text(NewsTypeHelper.displayName(for: type))
                                    .font(DS.Font.caption2)
                                    .fontWeight(.semibold)
                            }
                                .foregroundColor(NewsTypeHelper.color(for: type))
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, 2)
                                .background(NewsTypeHelper.color(for: type).opacity(0.12))
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
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(DS.Color.warning.opacity(0.3), lineWidth: 1))
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
                            .foregroundColor(DS.Color.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(DS.Color.textTertiary.opacity(0.3), lineWidth: 0.75))
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.md)

            // المحتوى
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(content)
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textPrimary.opacity(0.95))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.md)
            }

            // منطقة الميديا (صور) — Instagram-style with double-tap like
            if !imageUrls.isEmpty || imageUrl != nil {
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
            }

            // التصويت
            if !pollOptions.isEmpty {
                pollSection
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.md)
            }

            // فاصل زجاجي
            Rectangle()
                .fill(DS.Color.textTertiary.opacity(0.2))
                .frame(height: 0.5)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)

            // شريط الإجراءات
            actionBar
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.xs)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
                    .fill(.thickMaterial)

                LinearGradient(
                    colors: [DS.Color.glassDivider(colorScheme), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [DS.Color.glassMedium(colorScheme), DS.Color.glassSubtle(colorScheme)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        )
        .dsCardShadow()
    }

    private var pollSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if let q = pollQuestion, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(q).font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
            }
            ForEach(Array(pollOptions.enumerated()), id: \.offset) { index, option in
                let isSelected = selectedPollOption == index
                Button(action: { onVoteTap(index) }) {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? DS.Color.gradientPrimary : LinearGradient(colors: [DS.Color.textSecondary], startPoint: .top, endPoint: .bottom))
                            .font(DS.Font.scaled(20))
                        Text(option).font(DS.Font.callout)
                            .foregroundColor(DS.Color.textPrimary)
                        Spacer()
                        Text("\(pollVotes[index] ?? 0)")
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(isSelected ? DS.Color.textOnPrimary : DS.Color.textSecondary)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 3)
                            .background(isSelected ? DS.Color.primary : DS.Color.glassDivider(colorScheme))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .fill(.ultraThinMaterial)
                            if isSelected {
                                DS.Color.primary.opacity(0.12)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(isSelected ? DS.Color.primary.opacity(0.4) : DS.Color.glassMedium(colorScheme), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            // Like
            Button(action: onLikeTap) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(DS.Font.scaled(15, weight: .medium))
                        .foregroundColor(isLiked ? DS.Color.error : DS.Color.textSecondary)
                        .symbolEffect(.bounce, value: isLiked)

                    if likeCount > 0 {
                        Text("\(likeCount)")
                            .font(DS.Font.caption1)
                            .fontWeight(.semibold)
                            .foregroundColor(isLiked ? DS.Color.error : DS.Color.textSecondary)
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, 7)
                .background(
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        if isLiked { DS.Color.error.opacity(0.10) }
                    }
                )
                .clipShape(Capsule())
                .overlay(Capsule().stroke(DS.Color.textTertiary.opacity(0.25), lineWidth: 0.75))
            }
            .buttonStyle(.plain)

            // Comment
            Button(action: onCommentTap) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "bubble.right")
                        .font(DS.Font.scaled(15, weight: .medium))
                        .foregroundColor(DS.Color.textSecondary)

                    if commentCount > 0 {
                        Text("\(commentCount)")
                            .font(DS.Font.caption1)
                            .fontWeight(.semibold)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(.ultraThinMaterial)
                )
                .clipShape(Capsule())
                .overlay(Capsule().stroke(DS.Color.textTertiary.opacity(0.25), lineWidth: 0.75))
            }
            .buttonStyle(.plain)

            Spacer()

            // Time
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "clock")
                    .font(DS.Font.scaled(11))
                Text(time)
                    .font(DS.Font.caption2)
            }
            .foregroundColor(DS.Color.textTertiary)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}
