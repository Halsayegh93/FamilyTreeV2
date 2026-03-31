import SwiftUI

struct AdminStoriesView: View {
    @EnvironmentObject var storyVM: StoryViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            if storyVM.pendingStories.isEmpty {
                VStack(spacing: DS.Spacing.lg) {
                    Image(systemName: "checkmark.circle")
                        .font(DS.Font.scaled(48, weight: .regular))
                        .foregroundColor(DS.Color.success.opacity(0.5))
                    Text(L10n.t("لا توجد قصص معلقة", "No pending stories"))
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textSecondary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Spacing.md) {
                        ForEach(storyVM.pendingStories) { story in
                            pendingStoryCard(story)
                        }
                    }
                    .padding(DS.Spacing.lg)
                }
            }
        }
        .navigationTitle(L10n.t("قصص معلقة", "Pending Stories"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await storyVM.fetchPendingStories(force: true) }
        .refreshable { await storyVM.fetchPendingStories(force: true) }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Pending Story Card

    private func pendingStoryCard(_ story: FamilyStory) -> some View {
        let member = memberVM.member(byId: story.memberId)

        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Header: avatar + name + time
            HStack(spacing: DS.Spacing.md) {
                // Avatar
                Group {
                    if let avatarUrl = member?.avatarUrl, let url = URL(string: avatarUrl) {
                        CachedAsyncPhaseImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                memberInitialCircle(member, size: 40)
                            }
                        }
                    } else {
                        memberInitialCircle(member, size: 40)
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(member?.firstName ?? L10n.t("عضو", "Member"))
                        .font(DS.Font.scaled(14, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)

                    Text(relativeTime(story.createdDate))
                        .font(DS.Font.scaled(11, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                }

                Spacer()

                // بادج معلق
                Text(L10n.t("معلّق", "Pending"))
                    .font(DS.Font.scaled(10, weight: .bold))
                    .foregroundColor(DS.Color.warning)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(DS.Color.warning.opacity(0.1))
                    .clipShape(Capsule())
            }

            // الصورة
            CachedAsyncPhaseImage(url: URL(string: story.imageUrl)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .fill(DS.Color.surface)
                        .frame(height: 250)
                        .overlay(ProgressView().tint(DS.Color.primary))
                }
            }

            // Caption
            if let caption = story.caption, !caption.isEmpty {
                Text(caption)
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textPrimary)
            }

            // أزرار الموافقة/الرفض
            DSApproveRejectButtons(
                approveTitle: L10n.t("نشر", "Publish"),
                rejectTitle: L10n.t("رفض", "Reject"),
                onApprove: { Task { await storyVM.approveStory(story) } },
                onReject: { Task { await storyVM.rejectStory(story) } }
            )
        }
        .padding(DS.Spacing.lg)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(DS.Color.textTertiary.opacity(0.1), lineWidth: 1)
        )
        .dsCardShadow()
    }

    // MARK: - Helpers

    private func memberInitialCircle(_ member: FamilyMember?, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(DS.Color.primary.opacity(0.15))
            Text(String((member?.firstName ?? "?").prefix(1)))
                .font(DS.Font.scaled(size * 0.4, weight: .bold))
                .foregroundColor(DS.Color.primary)
        }
        .frame(width: size, height: size)
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private func relativeTime(_ date: Date) -> String {
        Self.relativeDateFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}
