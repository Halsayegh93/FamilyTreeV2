import SwiftUI

struct AdminNewsRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            if authVM.pendingNewsRequests.isEmpty {
                // Empty state with gradient circles
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
                    Text("لا توجد طلبات نشر معلقة")
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textSecondary)
                }
            } else {
                ScrollView {
                    VStack(spacing: DS.Spacing.md) {
                        ForEach(authVM.pendingNewsRequests) { post in
                            card(for: post)
                        }
                    }
                    .padding(DS.Spacing.lg)
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

    private func card(for post: NewsPost) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {

                // Blue gradient top accent
                DS.Color.gradientPrimary
                    .frame(height: 4)
                    .cornerRadius(DS.Radius.full)

                // Header: type badge + author info
                HStack {
                    // Gradient capsule type badge
                    Text(post.type)
                        .font(DS.Font.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.primary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 3)
                        .background(
                            LinearGradient(
                                colors: [DS.Color.primary.opacity(0.15), DS.Color.gridTree.opacity(0.1)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())

                    Spacer()

                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.author_name)
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(post.created_at.prefix(10))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                }

                // Content
                Text(post.content)
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Action buttons
                HStack(spacing: DS.Spacing.md) {
                    // Reject button — DS.Color.error tint
                    Button("رفض") {
                        Task { await authVM.rejectNewsPost(postId: post.id) }
                    }
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.error)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Color.error.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.error.opacity(0.2), lineWidth: 1)
                    )

                    // Approve button — DS.Color.success gradient
                    Button {
                        Task { await authVM.approveNewsPost(postId: post.id) }
                    } label: {
                        if authVM.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("اعتماد النشر")
                                .fontWeight(.bold)
                        }
                    }
                    .font(DS.Font.caption1)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.md)
                    .background(
                        LinearGradient(
                            colors: [DS.Color.success, DS.Color.success.opacity(0.8)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }
            }
            .padding(DS.Spacing.lg)
        }
    }
}
