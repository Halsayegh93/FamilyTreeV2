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
    @Environment(\.colorScheme) private var colorScheme
    /// «تقليل الحركة» (توصية أبل): تلاشٍ بدل التكبير
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                          tint: selectedCategory.color,
                          index: 0) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(ContactCategory.allCases, id: \.self) { cat in
                    categoryChip(cat)
                }
            }
        }
    }

    private func categoryChip(_ cat: ContactCategory) -> some View {
        let selected = selectedCategory == cat
        return Button {
            withAnimation(DS.Anim.quick) { selectedCategory = cat }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: cat.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(selected ? .white : cat.color)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(selected ? Color.white.opacity(0.2) : cat.color.opacity(0.13)))
                    .accessibilityHidden(true)
                Text(cat.title)
                    .dsFieldFont(12, weight: .bold)
                    .foregroundColor(selected ? .white : DS.Color.fieldLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient(colors: [cat.color, cat.color.opacity(0.8)],
                                                         startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(DS.Color.background))
                    // الداكن: ألوان التصنيفات فاتحة فيه والنص أبيض — طبقة تعتيم تحفظ وضوحه
                    // (نفس معالجة رأس المربّع DSComposerHeader)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(Color.black.opacity(selected && colorScheme == .dark ? 0.3 : 0)))
            }
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(selected ? Color.clear : DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: selected ? cat.color.opacity(0.3) : .clear, radius: 6, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - الرسالة — عنوان ثم نص

    private var messageSection: some View {
        DSComposerSection(title: L10n.t("الرسالة", "Message"),
                          icon: "text.bubble.fill",
                          tint: selectedCategory.color,
                          index: 1) {
            DSComposerField(icon: "text.cursor",
                            label: L10n.t("العنوان", "Subject"),
                            placeholder: L10n.t("عنوان الرسالة (اختياري)", "Subject (optional)"),
                            text: $subject,
                            tint: selectedCategory.color)
            messageEditor
        }
    }

    /// نص الرسالة — نفس شكل حقول المربّعات، مع عدّاد ثابت (يحمرّ فوق الحد)
    private var messageEditor: some View {
        let tint = selectedCategory.color
        return HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: "text.alignright")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(messageFocused ? .white : tint)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(messageFocused ? tint : tint.opacity(0.12)))
                .onTapGesture { messageFocused = true }
                .accessibilityHidden(true)   // أيقونة الحقل — زخرفة

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(L10n.t("نص الرسالة *", "Message *"))
                        .dsFieldFont(12, weight: .heavy)
                        .foregroundColor(messageFocused ? tint : DS.Color.fieldLabel)
                    Spacer(minLength: 0)
                    Text("\(message.count)/\(maxLength)")
                        .font(DS.Font.plex(10, weight: .semibold))
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
                            .font(DS.Font.plex(14.5))
                            .foregroundColor(DS.Color.textTertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $message)
                        .focused($messageFocused)
                        .dsFieldFont(14.5)
                        .foregroundColor(DS.Color.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 130, maxHeight: 220)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.sm + 2)
        .padding(.vertical, DS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(messageFocused ? tint.opacity(0.65) : DS.Color.textTertiary.opacity(0.15),
                          lineWidth: messageFocused ? 1.5 : 1))
        .animation(.easeInOut(duration: 0.2), value: messageFocused)
    }

    // MARK: - بريد الرد — اختياري

    private var replySection: some View {
        DSComposerSection(title: L10n.t("بريد الرد", "Reply Email"),
                          icon: "at",
                          tint: emailIsValid ? DS.Color.success : selectedCategory.color,
                          trailing: L10n.t("اختياري", "Optional"),
                          index: 2) {
            replyField
        }
    }

    /// حقل البريد — نفس شكل حقول المربّعات، ويتلوّن بالأخضر مع علامة ✓ حين يبدو صالحاً
    private var replyField: some View {
        let tint = emailIsValid ? DS.Color.success : selectedCategory.color
        return HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "at")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(replyFocused ? .white : tint)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(replyFocused ? tint : tint.opacity(0.12)))
                .accessibilityHidden(true)   // أيقونة الحقل — زخرفة

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("البريد الإلكتروني", "Email"))
                    .dsFieldFont(12, weight: .heavy)
                    .foregroundColor(replyFocused ? tint : DS.Color.fieldLabel)
                TextField(L10n.t("بريدك للرد (اختياري)", "Your email for a reply (optional)"), text: $preferredContact)
                    .dsFieldFont(14.5)
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
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(DS.Color.success)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    .accessibilityLabel(L10n.t("البريد يبدو صحيحاً", "Email looks valid"))
            }
        }
        .padding(.horizontal, DS.Spacing.sm + 2)
        .padding(.vertical, DS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(replyFocused ? tint.opacity(0.65)
                                       : (emailIsValid ? DS.Color.success.opacity(0.35) : DS.Color.textTertiary.opacity(0.15)),
                          lineWidth: replyFocused ? 1.5 : 1))
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
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(DS.Color.error)
                .accessibilityHidden(true)
            Text(text)
                .font(DS.Font.plex(12, weight: .regular))
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.error.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private var canSend: Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxLength
    }

    // MARK: - حالة النجاح — داخل المربّع، و«إرسال رسالة أخرى» / «إغلاق» في الشريط السفلي
    @State private var sentCategory: ContactCategory = .inquiry

    private var successState: some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DS.Color.success.opacity(0.10))
                    .frame(width: 104, height: 104)
                Circle()
                    .fill(DS.Color.success.opacity(0.16))
                    .frame(width: 76, height: 76)
                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(DS.Color.success)
            }
            .accessibilityHidden(true)   // زخرفة — «وصلت رسالتك» تُقرأ

            VStack(spacing: DS.Spacing.sm) {
                Text(L10n.t("وصلت رسالتك", "Message received"))
                    .font(DS.Font.plex(20, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                HStack(spacing: 5) {
                    Image(systemName: sentCategory.icon)
                        .font(.system(size: 11, weight: .bold))
                        .accessibilityHidden(true)
                    Text(sentCategory.title)
                        .font(DS.Font.plex(12, weight: .bold))
                }
                .foregroundColor(sentCategory.color)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, 5)
                .background(Capsule().fill(sentCategory.color.opacity(0.12)))

                Text(L10n.t("شكراً لتواصلك. سترد عليك الإدارة بأقرب وقت.",
                            "Thank you. The admins will reply soon."))
                    .font(DS.Font.plex(14, weight: .regular))
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xl)
        .padding(.horizontal, DS.Spacing.md)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1))
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
        case .complaint: return DS.Color.error
        case .suggestion: return DS.Color.success
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
