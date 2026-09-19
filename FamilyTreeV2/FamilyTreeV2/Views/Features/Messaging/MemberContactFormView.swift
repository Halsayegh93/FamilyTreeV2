import SwiftUI

/// تواصل مع الإدارة — نموذج بسيط (لا دردشة، لا تاريخ)، بتصميم مرتّب (طلب المالك):
/// ترحيب يوضّح القسم ← بطاقات التصنيف بوصف قصير ← بطاقة الرسالة (عنوان + نص) ←
/// بريد الرد (اختياري) ← زر إرسال بلون التصنيف ← شاشة تأكيد.
struct MemberContactFormView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — نوزّع النموذج على عمودين
    private var isLandscape: Bool { vSizeClass == .compact }

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

    private let maxLength = 1000

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            if didSend {
                successState
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                formState
                    .transition(.opacity)
            }
        }
        .animation(DS.Anim.smooth, value: didSend)
    }

    // MARK: - حالة الإدخال
    private var formState: some View {
        ScrollView(showsIndicators: false) {
            Group {
                if isLandscape {
                    // الوضع الأفقي: عمودان — (الترحيب + التصنيف) و(الرسالة + الإرسال)
                    HStack(alignment: .top, spacing: DS.Spacing.lg) {
                        VStack(alignment: .leading, spacing: DS.Spacing.md) {
                            categorySection
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                            messageSection
                            replySection
                            if let err = errorText { errorBanner(err) }
                            sendButton
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    // تصميم متوسّط (طلب المالك): تصنيف بسطر واحد · الرسالة · البريد · إرسال
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        categorySection
                        messageSection
                        replySection
                        if let err = errorText { errorBanner(err) }
                        sendButton
                        Spacer(minLength: DS.Spacing.xl)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xxxxl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - التصنيف — صف واحد مختصر

    private var categorySection: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(ContactCategory.allCases, id: \.self) { cat in
                categoryChip(cat)
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
                    .font(DS.Font.scaled(17, weight: .semibold))
                Text(cat.title)
                    .font(DS.Font.plex(13, weight: selected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(selected ? .white : cat.color)
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(selected ? cat.color : cat.color.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(selected ? .clear : cat.color.opacity(0.20), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - الرسالة — بطاقة واحدة: عنوان ثم نص

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            VStack(spacing: 0) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "text.cursor")
                        .font(DS.Font.scaled(13, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                    // العنوان بمحاذاة ثابتة: يمين في العربية، يسار في الإنجليزية (طلب المالك)
                    TextField(L10n.t("عنوان الرسالة (اختياري)", "Subject (optional)"), text: $subject)
                        .font(DS.Font.plex(15, weight: .semibold))
                        .environment(\.layoutDirection, .leftToRight)
                        .multilineTextAlignment(L10n.isArabic ? .trailing : .leading)
                }
                .padding(.horizontal, DS.Spacing.md)
                .frame(height: 48)

                Rectangle()
                    .fill(DS.Color.cardBorder)
                    .frame(height: 0.75)
                    .padding(.horizontal, DS.Spacing.md)

                ZStack(alignment: .topLeading) {
                    if message.isEmpty {
                        Text(L10n.t("اكتب رسالتك هنا…", "Write your message here…"))
                            .font(DS.Font.plex(14, weight: .regular))
                            .foregroundColor(DS.Color.textTertiary)
                            .padding(.horizontal, DS.Spacing.md + 4)
                            .padding(.vertical, DS.Spacing.md + 6)
                    }
                    TextEditor(text: $message)
                        .focused($messageFocused)
                        .font(DS.Font.plex(15, weight: .regular))
                        .scrollContentBackground(.hidden)
                        .padding(DS.Spacing.sm)
                        .frame(minHeight: 180, maxHeight: 260)
                }

                HStack {
                    Spacer()
                    Text("\(message.count)/\(maxLength)")
                        .font(DS.Font.plex(11, weight: .medium))
                        .foregroundColor(message.count > maxLength ? DS.Color.error : DS.Color.textTertiary)
                        .environment(\.layoutDirection, .leftToRight)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.sm)
            }
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(DS.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(messageFocused ? selectedCategory.color.opacity(0.45) : DS.Color.cardBorder,
                                  lineWidth: messageFocused ? 1.5 : 0.75)
            )
            .animation(DS.Anim.quick, value: messageFocused)
        }
    }

    // MARK: - بريد الرد — اختياري

    private var replySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "at")
                    .font(DS.Font.scaled(14, weight: .semibold))
                    .foregroundColor(emailIsValid ? DS.Color.success : DS.Color.textTertiary)
                    .frame(width: 20)
                TextField(L10n.t("بريدك للرد (اختياري)", "Your email for a reply (optional)"), text: $preferredContact)
                    .font(DS.Font.plex(14, weight: .regular))
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
                    .multilineTextAlignment(L10n.isArabic ? .trailing : .leading)
                if emailIsValid {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DS.Font.scaled(14, weight: .bold))
                        .foregroundColor(DS.Color.success)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(DS.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(emailIsValid ? DS.Color.success.opacity(0.35) : DS.Color.cardBorder, lineWidth: 0.75)
            )
            .animation(DS.Anim.quick, value: emailIsValid)

        }
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
            Text(text)
                .font(DS.Font.plex(12, weight: .regular))
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.error.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    // MARK: - زر الإرسال — بلون التصنيف المختار
    private var sendButton: some View {
        Button {
            Task { await send() }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                if isSending {
                    ProgressView().tint(.white).scaleEffect(0.9)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(DS.Font.scaled(14, weight: .bold))
                }
                Text(isSending ? L10n.t("جارٍ الإرسال…", "Sending…") : L10n.t("إرسال", "Send"))
                    .font(DS.Font.plex(15, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(canSend ? selectedCategory.color : DS.Color.textTertiary.opacity(0.4))
            )
            .shadow(color: canSend ? selectedCategory.color.opacity(0.25) : .clear, radius: 10, x: 0, y: 4)
            .animation(DS.Anim.quick, value: selectedCategory)
        }
        .disabled(!canSend || isSending)
        .buttonStyle(DSScaleButtonStyle())
    }

    private var canSend: Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxLength
    }

    // MARK: - حالة النجاح
    @State private var sentCategory: ContactCategory = .inquiry

    private var successState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(DS.Color.success.opacity(0.10))
                    .frame(width: isLandscape ? 96 : 140, height: isLandscape ? 96 : 140)
                Circle()
                    .fill(DS.Color.success.opacity(0.16))
                    .frame(width: isLandscape ? 70 : 104, height: isLandscape ? 70 : 104)
                Image(systemName: "checkmark")
                    .font(.system(size: isLandscape ? 30 : 44, weight: .bold))
                    .foregroundColor(DS.Color.success)
            }

            VStack(spacing: DS.Spacing.sm) {
                Text(L10n.t("وصلت رسالتك", "Message received"))
                    .font(DS.Font.plex(22, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                HStack(spacing: 5) {
                    Image(systemName: sentCategory.icon)
                        .font(DS.Font.scaled(11, weight: .bold))
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
                    .padding(.horizontal, DS.Spacing.xl)
            }

            Spacer()

            Button {
                resetForm()
            } label: {
                Text(L10n.t("إرسال رسالة أخرى", "Send another"))
                    .font(DS.Font.plex(15, weight: .bold))
                    .foregroundColor(DS.Color.primary)
                    .frame(maxWidth: 280)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            .fill(DS.Color.primary.opacity(0.10))
                    )
            }
            .buttonStyle(DSScaleButtonStyle())
            .padding(.bottom, isLandscape ? DS.Spacing.md : DS.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity)
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
