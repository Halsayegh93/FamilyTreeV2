import SwiftUI

struct NewsCommentsSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    let news: NewsPost
    @State private var commentInput = ""
    @State private var isLoadingComments = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                if isLoadingComments {
                    VStack(spacing: DS.Spacing.md) {
                        ProgressView()
                        Text(L10n.t("جاري تحميل التعليقات...", "Loading comments..."))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let postComments = newsVM.commentsByPost[news.id], !postComments.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: DS.Spacing.sm) {
                            ForEach(postComments) { comment in
                                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(comment.author_name).font(DS.Font.caption1).fontWeight(.bold)
                                        Text(comment.content).font(DS.Font.callout)
                                    }
                                    Spacer()
                                    Text(relativeTimeFromISO(comment.created_at))
                                    .font(DS.Font.caption2)
                                    .foregroundColor(DS.Color.textSecondary)
                                }
                                .padding(DS.Spacing.md)
                                .glassBackground(radius: DS.Radius.md)
                            }
                        }
                        .padding(DS.Spacing.lg)
                    }
                } else {
                    VStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(DS.Font.scaled(44))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا توجد تعليقات بعد", "No comments yet"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                            .padding(.top, DS.Spacing.sm)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // حقل الإدخال
                HStack(spacing: DS.Spacing.sm) {
                    TextField(L10n.t("اكتب تعليقك...", "Write a comment..."), text: $commentInput, axis: .vertical)
                        .lineLimit(1...3)
                        .font(DS.Font.callout)
                        .padding(DS.Spacing.md)
                        .glassBackground(radius: DS.Radius.md)

                    Button(action: {
                        Task {
                            let success = await newsVM.addNewsComment(to: news.id, text: commentInput)
                            if success {
                                await MainActor.run { commentInput = "" }
                            }
                        }
                    }) {
                        Image(systemName: "paperplane.fill")
                            .font(DS.Font.scaled(15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(DS.Color.gradientPrimary)
                            .clipShape(Circle())
                    }
                    .disabled(commentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(DS.Spacing.lg)
            }
            .background(DS.Color.background)
            .navigationTitle(L10n.t("التعليقات", "Comments"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                }
            }
            .task {
                isLoadingComments = true
                await newsVM.fetchNewsComments(for: [news.id])
                isLoadingComments = false
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Helpers
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func relativeTimeFromISO(_ dateString: String) -> String {
        Self.relativeFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        let date = Self.isoFormatter.date(from: dateString) ?? Date()
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
