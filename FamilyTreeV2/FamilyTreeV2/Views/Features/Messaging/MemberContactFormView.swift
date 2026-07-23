import SwiftUI

/// نموذج تواصل بسيط — لا دردشة، لا تاريخ.
/// العضو يختار تصنيف + يكتب رسالة + يرسل → شاشة تأكيد.
struct MemberContactFormView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — نوزّع النموذج على عمودين
    private var isLandscape: Bool { vSizeClass == .compact }

    @State private var selectedCategory: ContactCategory = .inquiry
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
                    // الوضع الأفقي: عمودان — يمين (تعريف + تصنيف) ويسار (الرسالة + الإرسال)
                    HStack(alignment: .top, spacing: DS.Spacing.lg) {
                        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                            introCard
                            categoryPicker
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                            messageField
                            contactField
                            if let err = errorText {
                                errorBanner(err)
                            }
                            sendButton
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        introCard

                        categoryPicker

                        messageField

                        contactField

                        if let err = errorText {
                            errorBanner(err)
                        }

                        sendButton
                            .padding(.top, DS.Spacing.xs)

                        Spacer(minLength: DS.Spacing.xxl)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xxxxl)
        }
    }

    // MARK: - شرح مختصر
    private var introCard: some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "envelope.fill")
                    .font(DS.Font.scaled(17, weight: .semibold))
                    .foregroundColor(DS.Color.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("تواصل مع الإدارة", "Contact Admin"))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("اختر التصنيف واكتب رسالتك — يصلك الرد بأقرب وقت.",
                            "Pick a category and write your message — you'll get a reply soon."))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .strokeBorder(DS.Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    /// عنوان قسم موحّد — أيقونة صغيرة + نص عريض
    private func sectionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(DS.Font.scaled(10, weight: .bold))
                .foregroundColor(DS.Color.primary.opacity(0.75))
            Text(title)
                .font(DS.Font.caption1)
                .fontWeight(.bold)
                .foregroundColor(DS.Color.textSecondary)
        }
    }

    // MARK: - اختيار التصنيف
    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionLabel(L10n.t("التصنيف", "Category"), icon: "square.grid.2x2.fill")

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2),
                spacing: 6
            ) {
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
        } label: {
            HStack(spacing: 5) {
                Image(systemName: cat.icon)
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(selected ? .white : cat.color)
                    .frame(width: 22, height: 22)
                    .background(selected ? cat.color : cat.color.opacity(0.12))
                    .clipShape(Circle())

                Text(cat.title)
                    .font(DS.Font.scaled(11, weight: selected ? .bold : .semibold))
                    .foregroundColor(selected ? cat.color : DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(selected ? cat.color.opacity(0.08) : DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(selected ? cat.color.opacity(0.40) : DS.Color.textTertiary.opacity(0.12),
                                  lineWidth: selected ? 1.3 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - حقل الرسالة
    private var messageField: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                sectionLabel(L10n.t("الرسالة", "Message"), icon: "text.alignright")
                Spacer()
                Text("\(message.count)/\(maxLength)")
                    .font(DS.Font.caption2)
                    .foregroundColor(message.count > maxLength ? DS.Color.error : DS.Color.textTertiary)
            }

            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text(L10n.t("اكتب رسالتك هنا…", "Type your message here…"))
                        .font(DS.Font.body)
                        .foregroundColor(DS.Color.textTertiary)
                        .padding(.horizontal, DS.Spacing.md + 4)
                        .padding(.vertical, DS.Spacing.md + 8)
                }
                TextEditor(text: $message)
                    .focused($messageFocused)
                    .font(DS.Font.body)
                    .scrollContentBackground(.hidden)
                    .padding(DS.Spacing.sm)
                    .frame(minHeight: 130, maxHeight: 200)
            }
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(
                        messageFocused ? DS.Color.primary.opacity(0.35) : DS.Color.textTertiary.opacity(0.15),
                        lineWidth: messageFocused ? 1.5 : 1
                    )
            )

        }
    }

    // MARK: - وسيلة التواصل للرد (قسم مستقل)
    private var contactField: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionLabel(L10n.t("وسيلة التواصل للرد", "Reply contact"), icon: "at")

            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: preferredContact.contains("@") ? "envelope.fill" : "phone.fill")
                    .font(DS.Font.scaled(13, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                TextField(L10n.t("إيميلك أو رقم هاتفك (اختياري)", "Your email or phone (optional)"),
                          text: $preferredContact)
                    .font(DS.Font.callout)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
                    .multilineTextAlignment(L10n.isArabic ? .trailing : .leading)
            }
            .padding(DS.Spacing.md)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
            )

            Text(L10n.t("اتركه فارغاً لنرد على رقمك المسجّل.",
                        "Leave empty to be reached on your registered number."))
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textTertiary)
        }
    }

    // MARK: - بانر خطأ
    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(DS.Color.error)
            Text(text)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.sm)
        .background(DS.Color.error.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    // MARK: - زر الإرسال
    private var sendButton: some View {
        Button {
            Task { await send() }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                if isSending {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(DS.Font.scaled(14, weight: .bold))
                }
                Text(isSending ? L10n.t("جارٍ الإرسال…", "Sending…") : L10n.t("إرسال", "Send"))
                    .font(DS.Font.calloutBold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md + 4)
            .background(canSend ? DS.Color.gradientPrimary : LinearGradient(colors: [DS.Color.textTertiary.opacity(0.4)], startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
        .disabled(!canSend || isSending)
        .buttonStyle(DSScaleButtonStyle())
    }

    private var canSend: Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxLength
    }

    // MARK: - حالة النجاح
    private var successState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(DS.Color.success.opacity(0.15))
                    .frame(width: isLandscape ? 76 : 120, height: isLandscape ? 76 : 120)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: isLandscape ? 50 : 80, weight: .bold))
                    .foregroundColor(DS.Color.success)
            }

            VStack(spacing: DS.Spacing.sm) {
                Text(L10n.t("تم استلام رسالتك", "Message Received"))
                    .font(DS.Font.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t(
                    "شكراً لتواصلك. راح ترد عليك الإدارة بأقرب وقت.",
                    "Thank you. Admin will reach out shortly."
                ))
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.lg)
            }

            Spacer()

            Button {
                resetForm()
            } label: {
                Text(L10n.t("إرسال رسالة جديدة", "Send Another"))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.primary)
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Color.primary.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(DS.Color.primary.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(DSScaleButtonStyle())
            .padding(.bottom, isLandscape ? DS.Spacing.md : DS.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    @MainActor
    private func send() async {
        errorText = nil
        messageFocused = false
        isSending = true
        let ok = await authVM.sendContactMessage(
            category: selectedCategory.serverValue,
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            preferredContact: preferredContact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : preferredContact.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        isSending = false
        if ok {
            withAnimation(DS.Anim.smooth) { didSend = true }
        } else {
            errorText = authVM.contactMessageError ?? L10n.t("تعذر إرسال الرسالة. حاول مرة ثانية.", "Failed to send. Please try again.")
        }
    }

    private func resetForm() {
        message = ""
        selectedCategory = .inquiry
        errorText = nil
        withAnimation(DS.Anim.smooth) { didSend = false }
    }
}

// MARK: - التصنيفات الأربعة

enum ContactCategory: CaseIterable {
    case complaint, suggestion, inquiry, other

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
