import SwiftUI

struct AdminNewsRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            if authVM.pendingNewsRequests.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    DSSectionHeader(
                        title: L10n.t("طلبات معلقة", "Pending Requests"),
                        icon: "newspaper.fill",
                        trailing: "\(authVM.pendingNewsRequests.count)"
                    )
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)

                    LazyVStack(spacing: DS.Spacing.md) {
                        ForEach(authVM.pendingNewsRequests) { post in
                            card(for: post)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xxxl)
                }
            }
        }
        .navigationTitle(L10n.t("طلبات نشر الأخبار", "News Publish Requests"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await authVM.fetchPendingNewsRequests() }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(DS.Color.success.opacity(0.08))
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(DS.Color.success.opacity(0.12))
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 60, height: 60)
                Image(systemName: "checkmark.circle.fill")
                    .font(DS.Font.scaled(26, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(L10n.t("لا توجد طلبات نشر معلقة", "No pending publish requests"))
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.textSecondary)
        }
    }

    // MARK: - Card
    private func card(for post: NewsPost) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {

                // Accent bar
                LinearGradient(
                    colors: [DS.Color.warning, DS.Color.warning.opacity(0.7)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 4)
                .cornerRadius(DS.Radius.full)

                // Header: author + type
                HStack(spacing: DS.Spacing.sm) {
                    // صورة الكاتب
                    let member = authVM.member(byId: post.author_id)
                    if let urlStr = member?.avatarUrl, let url = URL(string: urlStr) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Circle()
                                .fill(DS.Color.primary.opacity(0.15))
                                .overlay(
                                    Text(String(post.author_name.first ?? "A"))
                                        .font(DS.Font.scaled(14, weight: .bold))
                                        .foregroundColor(DS.Color.primary)
                                )
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(DS.Color.primary.opacity(0.15))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(String(post.author_name.first ?? "A"))
                                    .font(DS.Font.scaled(14, weight: .bold))
                                    .foregroundColor(DS.Color.primary)
                            )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.author_name)
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(1)
                        Text(post.created_at.prefix(10))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textTertiary)
                    }

                    Spacer()

                    // نوع الخبر
                    Text(post.type)
                        .font(DS.Font.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(colorForType(post.type))
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 3)
                        .background(colorForType(post.type).opacity(0.12))
                        .clipShape(Capsule())
                }

                // المحتوى
                Text(post.content)
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // الصور
                if !post.mediaURLs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Spacing.sm) {
                            ForEach(post.mediaURLs, id: \.self) { urlStr in
                                if let url = URL(string: urlStr) {
                                    CachedAsyncImage(url: url) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: DS.Radius.md)
                                            .fill(DS.Color.surface)
                                            .overlay(ProgressView().tint(DS.Color.primary))
                                    }
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                                }
                            }
                        }
                    }
                }

                // أزرار الموافقة/الرفض
                DSApproveRejectButtons(
                    approveTitle: L10n.t("اعتماد النشر", "Approve"),
                    rejectTitle: L10n.t("رفض", "Reject"),
                    isLoading: authVM.isLoading,
                    approveGradient: LinearGradient(
                        colors: [DS.Color.success, DS.Color.success.opacity(0.8)],
                        startPoint: .leading, endPoint: .trailing
                    )
                ) {
                    Task { await authVM.approveNewsPost(postId: post.id) }
                } onReject: {
                    Task { await authVM.rejectNewsPost(postId: post.id) }
                }
            }
            .padding(DS.Spacing.lg)
        }
    }

    private func colorForType(_ type: String) -> Color {
        switch type {
        case "وفاة": return DS.Color.newsDeath
        case "زواج": return DS.Color.newsWedding
        case "مولود": return DS.Color.newsBirth
        case "تصويت": return DS.Color.newsVote
        case "إعلان": return DS.Color.newsAnnouncement
        case "تهنئة": return DS.Color.newsCongrats
        case "تذكير": return DS.Color.newsReminder
        case "دعوة": return DS.Color.newsInvitation
        default: return DS.Color.primary
        }
    }
}
