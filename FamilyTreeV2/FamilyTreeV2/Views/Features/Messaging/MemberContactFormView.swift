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
        .sheet(isPresented: $showAbout) {
            AboutFamilySheet()
        }
    }

    @State private var showAbout = false

    // MARK: - حالة الإدخال
    private var formState: some View {
        ScrollView(showsIndicators: false) {
            Group {
                if isLandscape {
                    // الوضع الأفقي: عمودان — يمين (تعريف + تصنيف) ويسار (الرسالة + الإرسال)
                    HStack(alignment: .top, spacing: DS.Spacing.lg) {
                        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
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
                    VStack(alignment: .leading, spacing: DS.Spacing.md) {

                        categoryPicker

                        messageField

                        contactField

                        if let err = errorText {
                            errorBanner(err)
                        }

                        sendButton
                            .padding(.top, DS.Spacing.xs)

                        // «من نحن» انتقل لشاشته الخاصة — غرض واحد لكل شاشة
                        aboutLinkRow

                        Spacer(minLength: DS.Spacing.xxl)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xxxxl)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return b.map { "\(v) (\($0))" } ?? v
    }

    // MARK: - بطاقة «عمل هذا التطبيق» — بدل صف «عن التطبيق»
    private var aboutLinkRow: some View {
        VStack(spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.xs) {
                Rectangle()
                    .fill(DS.Color.textTertiary.opacity(0.18))
                    .frame(height: 1)
                Text(L10n.t("عمل هذا التطبيق", "Made by"))
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize()
                Rectangle()
                    .fill(DS.Color.textTertiary.opacity(0.18))
                    .frame(height: 1)
            }

            HStack(spacing: DS.Spacing.md) {
                ZStack {
                    Circle().fill(DS.Color.gradientPrimary)
                    Image(systemName: "hammer.fill")
                        .font(DS.Font.scaled(16, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("حسن الصايغ", "Hasan Al-Sayegh"))
                        .font(DS.Font.plex(15, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                    Text(L10n.t("فكرة وتصميم وبرمجة", "Idea, design & code"))
                        .font(DS.Font.scaled(12))
                        .foregroundColor(DS.Color.textSecondary)
                }

                Spacer(minLength: 0)

                // تفاصيل التطبيق تبقى متاحة بضغطة
                Button { showAbout = true } label: {
                    Image(systemName: "info.circle.fill")
                        .font(DS.Font.scaled(20, weight: .medium))
                        .foregroundColor(DS.Color.primary)
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("عن التطبيق", "About the app"))
            }
            .padding(DS.Spacing.md)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1)
            )

            Text(L10n.t("الإصدار \(appVersion)", "Version \(appVersion)"))
                .font(DS.Font.scaled(11))
                .foregroundColor(DS.Color.textTertiary)
        }
        .padding(.top, DS.Spacing.lg)
    }


    /// عنوان قسم قديم — باقٍ لحقل الإيميل فقط
    private func legacyContactLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(DS.Font.scaled(12, weight: .bold))
                .foregroundColor(DS.Color.primary.opacity(0.75))
            Text(title)
                .font(DS.Font.caption1)
                .fontWeight(.bold)
                .foregroundColor(DS.Color.textSecondary)
        }
    }

    // MARK: - اختيار التصنيف
    /// التصنيف — كبسولة فلاتر عائمة، نفس شريط الأخبار والأرشيف والشجرة
    private var categoryPicker: some View {
        HStack {
            Spacer(minLength: 0)

            HStack(spacing: 6) {
                ForEach(ContactCategory.allCases, id: \.self) { cat in
                    categoryChip(cat)
                }
            }
            .padding(6)
            .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(DS.Color.primary.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
            .animation(.spring(response: 0.40, dampingFraction: 0.78), value: selectedCategory)

            Spacer(minLength: 0)
        }
    }

    /// المختار كبسولة ملوّنة بنص، وغيره أيقونة دائرية (نفس نمط الفلاتر)
    private func categoryChip(_ cat: ContactCategory) -> some View {
        let selected = selectedCategory == cat
        return Button {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.78)) { selectedCategory = cat }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            // كل التصنيفات تظهر بنصّها — المختار كبسولة ملوّنة والباقي خفيف
            HStack(spacing: 5) {
                Image(systemName: cat.icon)
                    .font(DS.Font.scaled(11, weight: .bold))
                Text(cat.title)
                    .font(DS.Font.scaled(12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(selected ? .white : cat.color)
            .padding(.horizontal, DS.Spacing.sm + 2)
            .padding(.vertical, 8)
            .background(
                Group {
                    if selected {
                        Capsule().fill(
                            LinearGradient(
                                colors: [cat.color, cat.color.opacity(0.85)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                    } else {
                        Capsule().fill(cat.color.opacity(0.12))
                    }
                }
            )
            .overlay(
                Capsule().strokeBorder(
                    selected ? .clear : cat.color.opacity(0.20), lineWidth: 1
                )
            )
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - حقل الرسالة
    /// مربّع مبسّط: عنوان الرسالة ثم نصّها — بلا ترويسة قسم
    private var messageField: some View {
        VStack(spacing: DS.Spacing.sm) {
            // العنوان — سطر واحد، اختياري والتلميح داخل المربّع
            HStack(spacing: DS.Spacing.sm) {
                TextField(L10n.t("عنوان الرسالة", "Subject"), text: $subject)
                    .font(DS.Font.body)
                if subject.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(L10n.t("اختياري", "Optional"))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm + 4)
                .background(DS.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .strokeBorder(DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
                )

            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text(L10n.t("اكتب رسالتك هنا… (مطلوب)", "Type your message here… (required)"))
                        .font(DS.Font.scaled(14))
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

                // العدّاد داخل الحقل — لا يسرق سطراً فوقه
                Text("\(message.count)/\(maxLength)")
                    .font(DS.Font.scaled(12))
                    .foregroundColor(message.count > maxLength ? DS.Color.error : DS.Color.textTertiary)
                    .padding(.horizontal, DS.Spacing.sm + 2)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: L10n.isArabic ? .bottomLeading : .bottomTrailing)
                    .allowsHitTesting(false)
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

    // MARK: - الإيميل للرد — اختياري، بلا ملاحظات
    private var contactField: some View {
        DSCard(padding: 0) {
            contactSectionHeader
            contactFieldBody
        }
    }

    private var contactSectionHeader: some View {
        DSSectionHeader(
            title: L10n.t("البريد الإلكتروني", "Email"),
            icon: "envelope.fill",
            iconColor: DS.Color.primary
        )
    }

    private var contactFieldBody: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                TextField(L10n.t("name@example.com", "name@example.com"), text: $preferredContact)
                    .font(DS.Font.subheadline)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
                    .multilineTextAlignment(L10n.isArabic ? .trailing : .leading)
                if emailIsValid {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.success)
                        .transition(.scale.combined(with: .opacity))
                } else if preferredContact.isEmpty {
                    // التلميح داخل الحقل — يختفي أول ما يبدأ بالكتابة
                    Text(L10n.t("اختياري", "Optional"))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm + 2)
            .background(DS.Color.background)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(emailIsValid ? DS.Color.primary.opacity(0.30)
                                               : DS.Color.textTertiary.opacity(0.15),
                                  lineWidth: 1)
            )
            .animation(DS.Anim.quick, value: emailIsValid)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.md)
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
            withAnimation(DS.Anim.smooth) { didSend = true }
        } else {
            errorText = authVM.contactMessageError ?? L10n.t("تعذر إرسال الرسالة. حاول مرة ثانية.", "Failed to send. Please try again.")
        }
    }

    private func resetForm() {
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
