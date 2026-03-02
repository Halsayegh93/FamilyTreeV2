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
                    // عدد الطلبات
                    HStack(spacing: DS.Spacing.md) {
                        Image(systemName: "newspaper.fill")
                            .font(DS.Font.scaled(16, weight: .semibold))
                            .foregroundColor(DS.Color.primary)

                        Text(L10n.t("طلبات معلقة", "Pending Requests"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)

                        Spacer()

                        Text("\(authVM.pendingNewsRequests.count)")
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.primary)
                            .frame(minWidth: 26, minHeight: 26)
                            .background(DS.Color.primary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                            .fill(DS.Color.surfaceElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                                    .stroke(DS.Color.textTertiary.opacity(0.25), lineWidth: 0.75)
                            )
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, DS.Spacing.sm)

                    LazyVStack(spacing: DS.Spacing.md) {
                        ForEach(authVM.pendingNewsRequests) { post in
                            card(for: post)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xxxl)
                }
            }
        }
        .navigationTitle(L10n.t("طلبات نشر الأخبار", "News Publish Requests"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear {
            Task { await authVM.fetchPendingNewsRequests() }
        }
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
                Image(systemName: "checkmark.seal.fill")
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
        VStack(alignment: .leading, spacing: DS.Spacing.md) {

            // Header: author + type
            HStack(spacing: DS.Spacing.sm) {
                // صورة الكاتب
                let member = authVM.allMembers.first(where: { $0.id == post.author_id })
                if let urlStr = member?.avatarUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { img in
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
                                AsyncImage(url: url) { img in
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
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
                .fill(.thickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
                        .stroke(DS.Color.textTertiary.opacity(0.2), lineWidth: 0.75)
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private func colorForType(_ type: String) -> Color {
        switch type {
        case "وفاة": return DS.Color.newsDeath
        case "زواج": return DS.Color.newsWedding
        case "مولود": return DS.Color.newsBirth
        case "تصويت": return DS.Color.newsVote
        default: return DS.Color.primary
        }
    }
}
