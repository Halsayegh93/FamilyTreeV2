import SwiftUI

struct AdminNewsReportsView: View {
    @EnvironmentObject var authVM: AuthViewModel

    private var newsById: [UUID: NewsPost] {
        Dictionary(uniqueKeysWithValues: authVM.allNews.map { ($0.id, $0) })
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            if authVM.newsReportRequests.isEmpty {
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
                        Image(systemName: "checkmark.shield")
                            .font(DS.Font.scaled(26, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text(L10n.t("لا توجد بلاغات أخبار معلقة", "No pending news reports"))
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textSecondary)
                }
            } else {
                ScrollView {
                    VStack(spacing: DS.Spacing.md) {
                        ForEach(authVM.newsReportRequests) { request in
                            reportCard(for: request)
                        }
                    }
                    .padding(DS.Spacing.lg)
                }
            }
        }
        .navigationTitle(L10n.t("بلاغات الأخبار", "News Reports"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            async let reports: () = authVM.fetchNewsReportRequests()
            async let news: () = authVM.fetchNews()
            _ = await (reports, news)
        }
    }

    private func reportCard(for request: AdminRequest) -> some View {
        let postId = UUID(uuidString: request.newValue ?? "")
        let reportedPost = postId.flatMap { newsById[$0] }

        return DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {

                // Red gradient top accent
                DS.Color.gradientWarm
                    .frame(height: 4)
                    .cornerRadius(DS.Radius.full)

                // Header: badge + member info
                HStack {
                    // Gradient-tinted capsule badge
                    Text(L10n.t("بلاغ", "Report"))
                        .font(DS.Font.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.error)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 3)
                        .background(
                            LinearGradient(
                                colors: [DS.Color.error.opacity(0.15), DS.Color.error.opacity(0.08)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())

                    Spacer()

                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.member?.fullName ?? L10n.t("عضو", "Member"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(request.createdAt?.prefix(10) ?? "—")
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                }

                // Details text
                Text(request.details ?? L10n.t("بلاغ بدون تفاصيل", "Report without details"))
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Reported post preview
                if let post = reportedPost {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(L10n.t("الخبر المبلغ عنه", "Reported Post"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                        Text(post.content)
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }

                // Action buttons
                DSApproveRejectButtons(
                    approveTitle: L10n.t("اعتماد البلاغ", "Approve Report"),
                    rejectTitle: L10n.t("رفض البلاغ", "Reject Report"),
                    isLoading: authVM.isLoading,
                    approveGradient: LinearGradient(
                        colors: [DS.Color.error, DS.Color.error.opacity(0.8)],
                        startPoint: .leading, endPoint: .trailing
                    )
                ) {
                    Task { await authVM.approveNewsReport(request: request) }
                } onReject: {
                    Task { await authVM.rejectNewsReport(request: request) }
                }
            }
            .padding(DS.Spacing.lg)
        }
    }
}
