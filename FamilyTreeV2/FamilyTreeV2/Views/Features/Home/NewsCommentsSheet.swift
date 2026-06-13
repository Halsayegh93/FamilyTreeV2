import SwiftUI

struct NewsCommentsSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    let news: NewsPost
    @State private var commentInput = ""
    @State private var isLoadingComments = false
    @State private var isSendingComment = false
    @State private var reportCommentId: UUID? = nil
    @State private var reportCommentLabel = ""
    @State private var reportReason = ""
    @State private var reportSent = false
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
                    List {
                        ForEach(postComments) { comment in
                            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(comment.author_name).font(DS.Font.caption1).fontWeight(.bold)
                                    Text(comment.content).font(DS.Font.callout)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(relativeTimeFromISO(comment.created_at))
                                        .font(DS.Font.caption2)
                                        .foregroundColor(DS.Color.textSecondary)

                                    // قائمة ظاهرة: إبلاغ / حذف
                                    let canDeleteThis = authVM.canDeleteComments || comment.author_id == authVM.currentUser?.id
                                    let canReportThis = comment.author_id != authVM.currentUser?.id
                                    if canDeleteThis || canReportThis {
                                        Menu {
                                            if canReportThis {
                                                Button {
                                                    reportCommentId = comment.id
                                                    reportCommentLabel = comment.author_name
                                                } label: {
                                                    Label(L10n.t("إبلاغ", "Report"), systemImage: "exclamationmark.bubble")
                                                }
                                            }
                                            if canDeleteThis {
                                                Button(role: .destructive) {
                                                    Task { _ = await newsVM.deleteComment(commentId: comment.id, postId: news.id) }
                                                } label: {
                                                    Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                                                }
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis")
                                                .font(DS.Font.scaled(13, weight: .bold))
                                                .foregroundColor(DS.Color.textSecondary)
                                                .frame(width: 28, height: 24)
                                                .contentShape(Rectangle())
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, DS.Spacing.xs)
                            .listRowBackground(DS.Color.surface)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if authVM.canDeleteComments || comment.author_id == authVM.currentUser?.id {
                                    Button(role: .destructive) {
                                        Task {
                                            _ = await newsVM.deleteComment(commentId: comment.id, postId: news.id)
                                        }
                                    } label: {
                                        Label(L10n.t("حذف", "Delete"), systemImage: "trash.fill")
                                    }
                                }
                                // إبلاغ — لكل تعليق ليس للمستخدم نفسه (سياسة Apple)
                                if comment.author_id != authVM.currentUser?.id {
                                    Button {
                                        reportCommentId = comment.id
                                        reportCommentLabel = comment.author_name
                                    } label: {
                                        Label(L10n.t("إبلاغ", "Report"), systemImage: "exclamationmark.bubble")
                                    }
                                    .tint(DS.Color.warning)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                } else {
                    VStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(DS.Font.scaled(40))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا توجد تعليقات بعد", "No comments yet"))
                            .font(DS.Font.title3)
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
                        guard !isSendingComment else { return }
                        isSendingComment = true
                        Task {
                            let success = await newsVM.addNewsComment(to: news.id, text: commentInput)
                            isSendingComment = false
                            if success {
                                await MainActor.run { commentInput = "" }
                            }
                        }
                    }) {
                        if isSendingComment {
                            ProgressView()
                                .tint(DS.Color.textOnPrimary)
                                .frame(width: 42, height: 42)
                                .background(DS.Color.gradientPrimary)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(DS.Font.scaled(15, weight: .bold))
                                .foregroundColor(DS.Color.textOnPrimary)
                                .frame(width: 42, height: 42)
                                .background(DS.Color.gradientPrimary)
                                .clipShape(Circle())
                        }
                    }
                    .disabled(isSendingComment || commentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            .alert(L10n.t("إبلاغ عن تعليق", "Report Comment"), isPresented: Binding(
                get: { reportCommentId != nil },
                set: { if !$0 { reportCommentId = nil } }
            )) {
                TextField(L10n.t("سبب الإبلاغ (اختياري)", "Reason (optional)"), text: $reportReason)
                Button(L10n.t("إبلاغ", "Report"), role: .destructive) {
                    let id = reportCommentId
                    let label = reportCommentLabel
                    let reason = reportReason
                    reportCommentId = nil
                    reportReason = ""
                    Task {
                        let ok = await notificationVM.reportContent(
                            contentKind: L10n.t("تعليق", "comment"),
                            contentLabel: label,
                            contentId: id,
                            reason: reason
                        )
                        if ok { await MainActor.run { reportSent = true } }
                    }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { reportCommentId = nil; reportReason = "" }
            } message: {
                Text(L10n.t("اكتب سبب الإبلاغ، وسيتم إرساله للإدارة لمراجعة هذا التعليق.",
                           "Enter a reason; it will be sent to the admins to review this comment."))
            }
            .alert(L10n.t("تم الإبلاغ", "Reported"), isPresented: $reportSent) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: {
                Text(L10n.t("شكراً لك، وصل بلاغك للإدارة.", "Thank you, your report reached the admins."))
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
