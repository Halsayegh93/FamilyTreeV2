import SwiftUI

/// التعليقات — مربّع بمنتصف الشاشة بنفس تصميم المربّعات (طلب المالك): رأس كحلي بعدد
/// التعليقات، التعليقات بطاقات تتمرّر عند الطول، وشريط سفلي ثابت فيه حقل الكتابة
/// و«إرسال» و«إغلاق» (يسار). يبلّغ `DSCenterPanel(hugsContent:)` بارتفاعه.
struct NewsCommentsSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    let news: NewsPost
    @State private var commentInput = ""
    @State private var isLoadingComments = false
    @State private var isSendingComment = false
    @State private var reportCommentId: UUID? = nil
    @State private var reportCommentLabel = ""
    @State private var reportReason = ""
    @State private var reportSent = false
    /// حظر كاتب التعليق (Guideline 1.2) — تعليقات المحظورين لا تظهر للحاظر
    @State private var blockTarget: BlockTarget? = nil
    @ObservedObject private var blockedStore = BlockedMembersStore.shared
    /// تعليق فيه ألفاظ مسيئة — لا يُرسل
    @State private var showObjectionableAlert = false
    /// «تجاهل التغييرات؟» عند «إغلاق» وفي الحقل تعليق لم يُرسل (توصية أبل)
    @State private var confirmDiscard = false
    @Environment(\.dismiss) private var dismiss

    /// ارتفاعات الرأس والقائمة والشريط — تُبلَّغ للمربّع بعد قياس الرأس والشريط معاً
    @State private var headerH: CGFloat = 0
    @State private var contentH: CGFloat = 0
    @State private var footerH: CGFloat = 0
    @FocusState private var inputFocused: Bool
    /// دخول التعليقات (نمط الأخبار والديوانيات) — مرة حين تظهر القائمة
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// تعليقات الأخبار بلون قسم الأخبار (طلب المالك ٢٠٢٦-١٠-٠٥ «وحتى الاخبار»)
    private let tint = AppSection.news.fill

    /// تعليقات الخبر بلا تعليقات من حظرهم المستخدم
    private var postComments: [NewsCommentRecord] {
        (newsVM.commentsByPost[news.id] ?? []).filter {
            !blockedStore.isBlocked(id: $0.author_id, name: $0.author_name)
        }
    }

    /// سطر الرأس: عدد التعليقات (أو التحميل / لا يوجد)
    private var countText: String {
        let n = postComments.count
        if n > 0 { return L10n.t("\(n) تعليق", n == 1 ? "1 comment" : "\(n) comments") }
        return isLoadingComments ? L10n.t("جاري تحميل التعليقات...", "Loading comments...")
                                 : L10n.t("لا توجد تعليقات بعد", "No comments yet")
    }

    private var canSend: Bool {
        !isSendingComment && !commentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// تعليق مكتوب لم يُرسل — الإغلاق يسأل أولاً، والمربّع الطويل لا يُسحب (توصية أبل).
    /// أثناء الإرسال لا يُسأل: التعليق في طريقه للحفظ.
    private var hasUnsentDraft: Bool {
        !isSendingComment && !commentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            DSComposerHeader(title: L10n.t("التعليقات", "Comments"),
                             subtitle: countText,
                             icon: "bubble.left.and.bubble.right.fill",
                             tint: tint)
                // «إغلاق» أعلى الرأس يساراً (قاعدة التطبيق) — بدل الزر المكرّر بجانب الحقل (طلب المالك)
                .overlay(alignment: .topTrailing) { closeButton }
                .readHeight($headerH)

            ScrollView(showsIndicators: false) {
                commentsContent
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.sm)
                    .readHeight($contentH)
            }
            .scrollDismissesKeyboard(.interactively)

            inputBar.readHeight($footerH)
        }
        .background(DS.Color.background)
        // يُبلَّغ الارتفاع بعد قياس الرأس والشريط معاً (نفس DSComposer) — وإلا يلتقط
        // المربّع قياساً ناقصاً فيُقصّ آخر المحتوى
        .preference(key: SheetContentHeightKey.self,
                    value: headerH > 0 && footerH > 0 ? headerH + contentH + footerH : 0)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        // مربّع طويل من الأسفل: لا يُسحب وفي الحقل تعليق لم يُرسل
        .interactiveDismissDisabled(hasUnsentDraft)
        .dsAlert(L10n.t("تجاهل التعديلات؟", "Discard changes?"), isPresented: $confirmDiscard) {
            Button(L10n.t("متابعة التعديل", "Keep editing"), role: .cancel) {}
            Button(L10n.t("تجاهل", "Discard"), role: .destructive) { dismiss() }
        } message: {
            // الصياغة الرسمية (اختيار المالك ٢٠٢٦-١٠-٠٧)
            Text(L10n.t("لديك تعديلات غير محفوظة. هل تريد تجاهلها والخروج؟",
                        "You have unsaved changes. Discard them and leave?"))
        }
        .task {
            isLoadingComments = true
            await newsVM.fetchNewsComments(for: [news.id])
            isLoadingComments = false
        }
        .dsAlert(L10n.t("إبلاغ عن تعليق", "Report Comment"), isPresented: Binding(
            get: { reportCommentId != nil },
            set: { if !$0 { reportCommentId = nil } }
        )) {
            TextField(L10n.t("سبب الإبلاغ (اختياري)", "Reason (optional)"), text: $reportReason)
                .dsAlertField()
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
        .dsAlert(L10n.t("تم الإبلاغ", "Reported"), isPresented: $reportSent) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(L10n.t("شكراً لك، وصل بلاغك للإدارة وستتم مراجعته خلال ٢٤ ساعة.",
                        "Thank you — your report reached the admins and will be reviewed within 24 hours."))
        }
        // حظر كاتب التعليق — نفس رسائل «إبلاغ» (بلاغ تلقائي للإدارة)
        .dsBlockMemberFlow(target: $blockTarget)
        .dsAlert(L10n.t("تعليق غير لائق", "Inappropriate comment"), isPresented: $showObjectionableAlert) {
            Button(L10n.t("تعديل التعليق", "Edit comment"), role: .cancel) {}
        } message: {
            // نص السيرفر (`blocked_words_message_general`) إن وُجد — نفسه لكل الحفظ
            Text(ObjectionableText.message)
        }
        // زر الإرسال والرسائل بلون قسم الأخبار ما دامت الورقة ظاهرة
        .dsSectionPage(.news)
    }

    // MARK: - المحتوى: تحميل / تعليقات / لا يوجد

    @ViewBuilder
    private var commentsContent: some View {
        if isLoadingComments {
            // التحميل الموحّد: مجسّم الأخبار يتنفّس + نص قصير
            DSPageLoader(L10n.t("جاري تحميل التعليقات...", "Loading comments..."), section: .news, fillsSpace: false)
                .padding(.vertical, DS.Spacing.xxl)
        } else if !postComments.isEmpty {
            VStack(spacing: DS.Spacing.sm) {
                ForEach(Array(postComments.enumerated()), id: \.element.id) { idx, comment in
                    commentCard(comment)
                        // نمط الأخبار والديوانيات: تصعد وتظهر تباعاً (أول ٧، والباقي مع السابع)
                        .dsCardCascade(idx, appeared: appeared)
                        // تعليق جديد بعد الفتح (أو حذف) — صعود خفيف مع تلاشٍ، و«تقليل الحركة»: تلاشٍ فقط
                        .transition(reduceMotion
                                    ? .opacity
                                    : .asymmetric(insertion: .opacity.combined(with: .offset(y: DSMotion.rise)),
                                                  removal: .opacity))
                }
            }
            .animation(reduceMotion ? DSMotion.fade : DS.Anim.smooth, value: postComments.map(\.id))
            // مرة لكل ظهور للقائمة (بعد التحميل) — وتعود للبداية إن اختفت ثم ظهرت
            .onAppear { appeared = true }
            .onDisappear { appeared = false }
        } else {
            // الحالة الفارغة الموحّدة (مجسّم + عنوان)
            DSEmptyView(L10n.t("لا توجد تعليقات بعد", "No comments yet"), section: .news,
                        icon: "bubble.left.and.bubble.right.fill", compact: true)
        }
    }

    /// بطاقة تعليق — نفس بطاقات أقسام المربّعات: رأس (أيقونة + الاسم + الوقت + قائمة) ثم النص
    private func commentCard(_ comment: NewsCommentRecord) -> some View {
        // قائمة ظاهرة: إبلاغ / حظر / حذف
        // التعليق يُحفظ بمعرّف الدخول (قد يختلف عن معرّف الملف للعضو المربوط) — نقارن بالاثنين
        let isMine = AccountIdentity.isMine(comment.author_id, currentUser: authVM.currentUser)
        let canDeleteThis = authVM.canDeleteComments || isMine
        let canReportThis = !isMine
        // حظر الكاتب — لغير تعليقاتي (لا يحظر المستخدم نفسه أبداً)
        let canBlockThis = !isMine && comment.author_id != nil
        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            HStack(spacing: DS.Spacing.xsm) {
                // قرص «مجسّمات» الموحّد
                DSStateIcon("person.fill", tint: AppSection.news.ink, size: DS.Icon.section)
                    .accessibilityHidden(true)
                Text(memberVM.displayName(id: comment.author_id, stored: comment.author_name, .four))
                    .dsFieldFont(.sectionTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(relativeTimeFromISO(comment.created_at))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)

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
                        if canBlockThis, let authorId = comment.author_id {
                            Button(role: .destructive) {
                                blockTarget = BlockTarget(id: authorId, name: comment.author_name)
                            } label: {
                                Label(L10n.t("حظر العضو", "Block Member"), systemImage: "hand.raised.fill")
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
                            .dsGlyph(DS.Glyph.mdCompact)
                            .foregroundColor(DS.Color.textSecondary)
                            .frame(width: DSBox.alertIcon, height: DS.Spacing.xxl)
                            // ← مساحة ضغط ٤٤×٤٤ بلا تغيير في التخطيط: حوله هامش
                            // البطاقة ونصوص لا تُضغط فقط
                            .tapArea(horizontal: (DS.Icon.tapTarget - DSBox.alertIcon) / 2,
                                     vertical: (DS.Icon.tapTarget - DS.Spacing.xxl) / 2)
                    }
                    .accessibilityLabel(L10n.t("خيارات التعليق", "Comment options"))
                }
            }

            Text(comment.content)
                .dsReadingFont()
                .foregroundColor(DS.Color.fieldValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        // البطاقة الواحدة (`.dsCard`)
        .dsCard(padding: DS.Spacing.md)
    }

    // MARK: - زر الإغلاق أعلى الرأس

    private var closeButton: some View {
        // زر الإغلاق الموحّد فوق الرأس الملوّن (DSNavButtons)
        DSCloseButton(context: .onColor) {
            if hasUnsentDraft { confirmDiscard = true } else { dismiss() }
        }
        .padding(.top, DS.Spacing.lg)
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - الشريط السفلي: حقل الإدخال + إرسال (كحلي)

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
            TextField(L10n.t("اكتب تعليقك...", "Write a comment..."), text: $commentInput, axis: .vertical)
                .lineLimit(1...3)
                .dsFieldFont(.fieldValue)
                .foregroundColor(DS.Color.textPrimary)
                .focused($inputFocused)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .frame(minHeight: DSBox.buttonHeight)
                .background(DSBox.buttonShape.fill(DS.Color.surface))
                .overlay(DSBox.buttonShape
                    .strokeBorder(inputFocused ? AppSection.news.ink.opacity(DS.Opacity.selectedStroke)
                                               : DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke),
                                  lineWidth: inputFocused ? DS.Border.widthBold : DS.Border.width))
                .animation(.easeInOut(duration: 0.2), value: inputFocused)

            Button(action: {
                guard !isSendingComment else { return }
                // تصفية الألفاظ المسيئة قبل النشر (Guideline 1.2) — التعليقات تُنشر بلا مراجعة
                if ObjectionableContentFilter.containsObjectionable(commentInput) {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    showObjectionableAlert = true
                    return
                }
                isSendingComment = true
                Task {
                    let success = await newsVM.addNewsComment(to: news.id, text: commentInput)
                    isSendingComment = false
                    if success {
                        await MainActor.run { commentInput = "" }
                    } else if newsVM.lastCommentRejectedAsObjectionable {
                        // فلتر السيرفر (قائمته في app_config) — نفس تنبيه فلتر الجهاز
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        showObjectionableAlert = true
                    }
                }
            }) {
                ZStack {
                    if isSendingComment {
                        ProgressView().tint(DS.Color.textOnPrimary).scaleEffect(0.85)   // دوّارة صغيرة داخل الزرّ
                    } else {
                        Image(systemName: "paperplane.fill")
                            .dsGlyph(DSButtonSize.regular.glyph)
                            .foregroundColor(DSActionFill.label(enabled: canSend || isSendingComment))
                    }
                }
                // زرّ مربّع بمقاس الزرّ الواحد وزواياه
                .frame(width: DSBox.buttonHeight, height: DSBox.buttonHeight)
                .background(DSActionFill.style(enabled: canSend || isSendingComment), in: DSBox.buttonShape)
            }
            .disabled(isSendingComment || commentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(L10n.t("إرسال", "Send"))
        }
        .buttonStyle(DSScaleButtonStyle())
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.md)
        .background(
            DS.Color.background
                .overlay(alignment: .top) {
                    Rectangle().fill(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke)).frame(height: DS.Border.width)
                }
        )
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

// MARK: - مساحة ضغط أكبر (توصية أبل: ٤٤ نقطة)

private extension View {
    /// يكبّر منطقة اللمس حول عنصر صغير بلا تغيير في شكله ولا في التخطيط: الحشوة تُضاف
    /// لمنطقة اللمس ثم تُسترد من التخطيط. القيم محسوبة لكل عنصر حتى لا تتداخل مع جيرانه.
    func tapArea(horizontal: CGFloat = 0, vertical: CGFloat = 0) -> some View {
        self
            .padding(.horizontal, horizontal).padding(.vertical, vertical)
            .contentShape(Rectangle())
            .padding(.horizontal, -horizontal).padding(.vertical, -vertical)
    }
}
