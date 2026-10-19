import SwiftUI

/// تواصل مع الإدارة — نموذج بسيط (لا دردشة، لا تاريخ) في مربّع بمنتصف الشاشة بنفس
/// تصميم مربّعات الإضافة (طلب المالك): رأس كحلي ← نوع الرسالة ← الرسالة (عنوان + نص) ←
/// بريد الرد (اختياري) ← «إرسال» كحلي يمين و«إلغاء» يسار ← تأكيد داخل المربّع نفسه.
struct MemberContactFormView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: ContactCategory = .inquiry
    /// عنوان الرسالة — يُضاف كأول سطر في المتن
    @State private var subject: String = ""
    @State private var message: String = ""
    /// إيميل أو رقم يرد عليه المدير (اختياري)
    @State private var preferredContact: String = ""
    @State private var isSending = false
    @State private var didSend = false
    @State private var errorText: String? = nil
    @FocusState private var messageFocused: Bool
    @FocusState private var replyFocused: Bool
    /// «تقليل الحركة» (توصية أبل): تلاشٍ بدل التكبير
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// قسم الواجهة التي فتحت المربّع — nil خارج التبويبات (الانتظار، التجميد)
    @Environment(\.dsSection) private var openerSection

    /// «تواصل بعد» (طلب المالك ٢٠٢٦-١٠-٠٥): المربّع بلون التواصل من أي تبويب = لون الإدارة
    /// (رسائل الإدارة، نفس مربّعه في الرئيسية `tileContact`). خارج التبويبات يبقى كحلي العلامة.
    private var contactSection: AppSection? { openerSection == nil ? nil : .admin }

    /// لون نوع الرسالة: «استفسار» (الكحلي) يتبع لون التواصل، والباقي ألوان معانٍ ثابتة
    private func categoryTint(_ cat: ContactCategory) -> Color {
        cat.color.dsChrome(in: contactSection)
    }

    private let maxLength = 1000

    /// رسالة مكتوبة لم تُرسل — «إلغاء» يسأل قبل التجاهل (توصية أبل). بعد الإرسال
    /// («إغلاق») لا يُسأل. «نوع الرسالة» اختيار فقط فلا يُحتسب.
    private var hasUnsavedChanges: Bool {
        guard !didSend else { return false }
        return [subject, message, preferredContact]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        DSComposer(
            title: L10n.t("تواصل مع الإدارة", "Contact Admin"),
            subtitle: L10n.t("اكتب رسالتك ويصلك الرد بأقرب وقت", "Write your message — you'll get a reply soon"),
            icon: "envelope.fill",
            tint: DS.Color.tileContact,
            actionTitle: submitTitle,
            actionIcon: didSend ? "square.and.pencil" : "paperplane.fill",
            cancelTitle: didSend ? L10n.t("إغلاق", "Close") : L10n.t("إلغاء", "Cancel"),
            canSubmit: didSend || canSend,
            isBusy: isSending,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: submitTapped,
            onCancel: { dismiss() }
        ) {
            if didSend {
                successState
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
            } else {
                categorySection
                messageSection
                replySection
                if let err = errorText { errorBanner(err) }
            }
        }
        .animation(DS.Anim.smooth, value: didSend)
        // زر الإرسال والرسائل ومربّعات النافذة المستقلّة بلون التواصل ما دام المربّع ظاهراً
        .dsSectionPage(contactSection)
    }

    /// زر الإجراء: «إرسال» ← «جارٍ الإرسال…» ← بعد الإرسال «إرسال رسالة أخرى»
    private var submitTitle: String {
        if didSend { return L10n.t("إرسال رسالة أخرى", "Send another") }
        return isSending ? L10n.t("جارٍ الإرسال…", "Sending…") : L10n.t("إرسال", "Send")
    }

    private func submitTapped() {
        if didSend {
            resetForm()
        } else {
            Task { await send() }
        }
    }

    // MARK: - التصنيف — صف واحد مختصر

    private var categorySection: some View {
        DSComposerSection(title: L10n.t("نوع الرسالة", "Message Type"),
                          icon: "square.grid.2x2.fill",
                          tint: categoryTint(selectedCategory),
                          index: 0) {
            // مربّعات الاختيار الموحّدة (`DSOptionTiles`) — كل نوع بلون معناه
            DSOptionTiles(ContactCategory.allCases.map {
                              DSOptionTile($0, title: $0.title, icon: $0.icon, tint: categoryTint($0))
                          },
                          selection: $selectedCategory, columns: ContactCategory.allCases.count)
        }
    }

    // MARK: - الرسالة — عنوان ثم نص

    private var messageSection: some View {
        DSComposerSection(title: L10n.t("الرسالة", "Message"),
                          icon: "text.bubble.fill",
                          tint: categoryTint(selectedCategory),
                          index: 1) {
            DSComposerField(icon: "text.cursor",
                            label: L10n.t("العنوان", "Subject"),
                            placeholder: L10n.t("عنوان الرسالة (اختياري)", "Subject (optional)"),
                            text: $subject,
                            tint: categoryTint(selectedCategory))
            messageEditor
        }
    }

    /// نص الرسالة — نفس شكل حقول المربّعات، مع عدّاد ثابت (يحمرّ فوق الحد)
    private var messageEditor: some View {
        let tint = categoryTint(selectedCategory)
        return HStack(alignment: .top, spacing: DS.Spacing.sm) {
            // قرص الحقل الموحّد («مجسّمات»)
            DSFieldIcon(name: "text.alignright", tint: tint)
                .onTapGesture { messageFocused = true }
                .accessibilityHidden(true)   // أيقونة الحقل — زخرفة

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack {
                    Text(L10n.t("نص الرسالة *", "Message *"))
                        .dsFieldFont(.label)
                        .foregroundColor(messageFocused ? tint : DS.Color.fieldLabel)
                    Spacer(minLength: 0)
                    Text("\(message.count)/\(maxLength)")
                        .dsFont(.micro)
                        .foregroundColor(message.count > maxLength ? DS.Color.error : DS.Color.textTertiary)
                        .monospacedDigit()
                        .environment(\.layoutDirection, .leftToRight)
                }
                // الضغط على العنوان يفتح الكتابة — بلا إيماءة فوق المحرّر نفسه (تعطّل وضع المؤشّر)
                .contentShape(Rectangle())
                .onTapGesture { messageFocused = true }

                ZStack(alignment: .topLeading) {
                    if message.isEmpty {
                        Text(L10n.t("اكتب رسالتك هنا…", "Write your message here…"))
                            .dsFieldFont(.body)
                            .foregroundColor(DS.Color.textTertiary)
                            .padding(.top, DS.Spacing.sm)
                            .padding(.leading, DS.Spacing.xs)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $message)
                        .focused($messageFocused)
                        .dsFieldFont(.body)
                        .foregroundColor(DS.Color.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: DS.Icon.emptyArt, maxHeight: DS.Icon.emptyArt * 1.7)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous).fill(DS.Color.background))
        .overlay(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
            .strokeBorder(messageFocused ? tint.opacity(DS.Opacity.selectedStroke) : DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke),
                          lineWidth: messageFocused ? DS.Border.widthBold : DS.Border.width))
        .animation(.easeInOut(duration: 0.2), value: messageFocused)
    }

    // MARK: - بريد الرد — اختياري

    private var replySection: some View {
        DSComposerSection(title: L10n.t("بريد الرد", "Reply Email"),
                          icon: "at",
                          tint: emailIsValid ? DS.Color.success : categoryTint(selectedCategory),
                          trailing: L10n.t("اختياري", "Optional"),
                          index: 2) {
            replyField
        }
    }

    /// حقل البريد — نفس شكل حقول المربّعات، ويتلوّن بالأخضر مع علامة ✓ حين يبدو صالحاً
    private var replyField: some View {
        let tint = emailIsValid ? DS.Color.success : categoryTint(selectedCategory)
        return HStack(spacing: DS.Spacing.sm) {
            // قرص الحقل الموحّد («مجسّمات»)
            DSFieldIcon(name: "at", tint: tint)
                .accessibilityHidden(true)   // أيقونة الحقل — زخرفة

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(L10n.t("البريد الإلكتروني", "Email"))
                    .dsFieldFont(.label)
                    .foregroundColor(replyFocused ? tint : DS.Color.fieldLabel)
                TextField(L10n.t("بريدك للرد (اختياري)", "Your email for a reply (optional)"), text: $preferredContact)
                    .dsFieldFont(.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
                    .multilineTextAlignment(L10n.isArabic ? .trailing : .leading)
                    .focused($replyFocused)
            }

            if emailIsValid {
                Image(systemName: "checkmark.circle.fill")
                    .dsGlyph(DS.Glyph.lgCompact)
                    .foregroundColor(DS.Color.success)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    .accessibilityLabel(L10n.t("البريد يبدو صحيحاً", "Email looks valid"))
            }
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous).fill(DS.Color.background))
        .overlay(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
            .strokeBorder(replyFocused ? tint.opacity(DS.Opacity.selectedStroke)
                                       : (emailIsValid ? DS.Color.success.opacity(DS.Opacity.tintStroke)
                                                       : DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke)),
                          lineWidth: replyFocused ? DS.Border.widthBold : DS.Border.width))
        .contentShape(Rectangle())
        .onTapGesture { replyFocused = true }
        .animation(.easeInOut(duration: 0.2), value: replyFocused)
        .animation(DS.Anim.quick, value: emailIsValid)
    }

    /// بريد يبدو صالحاً — لمجرّد التأكيد البصري، الحقل يبقى اختيارياً
    private var emailIsValid: Bool {
        let t = preferredContact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.contains("@"), let at = t.firstIndex(of: "@") else { return false }
        let domain = t[t.index(after: at)...]
        return !t[t.startIndex..<at].isEmpty && domain.contains(".") && !domain.hasSuffix(".")
    }

    // MARK: - بانر خطأ
    private func errorBanner(_ text: String) -> some View {
        // الملاحظة الملوّنة الموحّدة بلون الخطأ
        DSNoteCard(text, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
    }

    private var canSend: Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxLength
    }

    // MARK: - حالة النجاح — داخل المربّع، و«إرسال رسالة أخرى» / «إغلاق» في الشريط السفلي
    @State private var sentCategory: ContactCategory = .inquiry

    private var successState: some View {
        VStack(spacing: DS.Spacing.md) {
            // قرص «مجسّمات» الموحّد بلون النجاح
            DSStateIcon("checkmark", tint: DS.Color.success, size: DS.Icon.loaderArt - DS.Spacing.xl, mapsChrome: false)
                .accessibilityHidden(true)   // زخرفة — «وصلت رسالتك» تُقرأ

            VStack(spacing: DS.Spacing.sm) {
                Text(L10n.t("وصلت رسالتك", "Message received"))
                    .dsFont(.emptyTitle)
                    .foregroundColor(DS.Color.textPrimary)
                DSStatusChip(text: sentCategory.title, icon: sentCategory.icon, tint: sentCategory.color)

                Text(L10n.t("شكراً لتواصلك. سترد عليك الإدارة بأقرب وقت.",
                            "Thank you. The admins will reply soon."))
                    .dsFont(.body)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xl)
        .padding(.horizontal, DS.Spacing.md)
        // البطاقة الواحدة (`.dsCard`)
        .dsCard(padding: nil)
    }

    // MARK: - Actions

    /// العنوان يُضاف كأول سطر في المتن
    private var combinedMessage: String {
        let t = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? b : t + "\n" + b
    }

    @MainActor
    private func send() async {
        errorText = nil
        messageFocused = false
        isSending = true
        let ok = await authVM.sendContactMessage(
            category: selectedCategory.serverValue,
            message: combinedMessage,
            preferredContact: preferredContact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : preferredContact.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        isSending = false
        if ok {
            sentCategory = selectedCategory
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(DS.Anim.smooth) { didSend = true }
        } else {
            errorText = authVM.contactMessageError ?? L10n.t("تعذر إرسال الرسالة. حاول مرة ثانية.", "Failed to send. Please try again.")
        }
    }

    private func resetForm() {
        subject = ""
        message = ""
        preferredContact = ""
        selectedCategory = .inquiry
        errorText = nil
        withAnimation(DS.Anim.smooth) { didSend = false }
    }
}

// MARK: - التصنيفات الأربعة

enum ContactCategory: CaseIterable {
    case inquiry, complaint, suggestion, other

    var title: String {
        switch self {
        case .complaint: return L10n.t("شكوى", "Complaint")
        case .suggestion: return L10n.t("اقتراح", "Suggestion")
        case .inquiry: return L10n.t("استفسار", "Inquiry")
        case .other: return L10n.t("أخرى", "Other")
        }
    }

    var icon: String {
        switch self {
        case .complaint: return "exclamationmark.bubble.fill"
        case .suggestion: return "lightbulb.fill"
        case .inquiry: return "questionmark.bubble.fill"
        case .other: return "ellipsis.message.fill"
        }
    }

    var color: Color {
        switch self {
        case .complaint: return DS.Color.sadu
        case .suggestion: return DS.Color.palm
        case .inquiry: return DS.Color.primary
        case .other: return DS.Color.accent
        }
    }

    /// القيمة المخزنة في قاعدة البيانات (ثابتة بالعربي للتوافق مع الخلفية).
    var serverValue: String {
        switch self {
        case .complaint: return "شكوى"
        case .suggestion: return "اقتراح"
        case .inquiry: return "استفسار"
        case .other: return "أخرى"
        }
    }
}
