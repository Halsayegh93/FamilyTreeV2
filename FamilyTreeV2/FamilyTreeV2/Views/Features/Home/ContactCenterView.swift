import SwiftUI

struct ContactCenterView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isMessageFocused: Bool

    @State private var selectedCategory = "اقتراح"
    @State private var message = ""

    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var showCharacterLimitWarning = false
    @State private var messageSent = false

    private let categoryItems: [(key: String, icon: String, labelAr: String, labelEn: String, color: Color)] = [
        ("اقتراح", "lightbulb.fill", "اقتراح", "Suggestion", DS.Color.warning),
        ("شكوى", "exclamationmark.bubble.fill", "شكوى", "Complaint", DS.Color.error),
        ("تحديث", "arrow.triangle.2.circlepath", "تحديث بيانات", "Update Info", DS.Color.info)
    ]

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !authVM.isLoading
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            if messageSent {
                // Success state
                VStack(spacing: DS.Spacing.xl) {
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .fill(DS.Color.success.opacity(0.1))
                            .frame(width: 120, height: 120)
                        Circle()
                            .fill(DS.Color.success.opacity(0.18))
                            .frame(width: 88, height: 88)
                        Image(systemName: "checkmark.circle.fill")
                            .font(DS.Font.scaled(44, weight: .bold))
                            .foregroundColor(DS.Color.success)
                    }
                    
                    VStack(spacing: DS.Spacing.sm) {
                        Text(L10n.t("تم الإرسال بنجاح", "Sent Successfully"))
                            .font(DS.Font.title3)
                            .fontWeight(.black)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(L10n.t("تم إرسال رسالتك وسيتم التواصل معك قريباً.", "Your message has been sent. We'll get back to you soon."))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DS.Spacing.xxxl)
                    }
                    
                    Spacer()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xxl) {
                        categorySection
                        messageSection
                        submitButton
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xxxxl)
                }
            }
        }
        .alert(L10n.t("تعذر الإرسال", "Failed to Send"), isPresented: $showErrorAlert) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(authVM.contactMessageError ?? L10n.t("تعذر إرسال الرسالة حالياً. حاول مرة أخرى.", "Failed to send message. Please try again."))
        }
        .alert(L10n.t("الحد الأقصى", "Character Limit"), isPresented: $showCharacterLimitWarning) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.t("تم الوصول إلى الحد الأقصى للرسالة (1000 حرف).", "You've reached the maximum message length (1000 characters)."))
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Category Section
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(L10n.t("نوع الرسالة", "Message Type"))
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)

            HStack(spacing: DS.Spacing.sm) {
                ForEach(categoryItems, id: \.key) { item in
                    let isSelected = selectedCategory == item.key
                    Button {
                        withAnimation(DS.Anim.snappy) {
                            selectedCategory = item.key
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: item.icon)
                                .font(DS.Font.scaled(14, weight: .semibold))
                            Text(L10n.t(item.labelAr, item.labelEn))
                                .font(DS.Font.caption1)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(isSelected ? DS.Color.textOnPrimary : item.color)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? item.color : item.color.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? Color.clear : item.color.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
            }
        }
    }

    // MARK: - Message Section
    private var messageSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(L10n.t("رسالتك", "Your Message"))
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)

            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    TextEditor(text: $message)
                        .frame(minHeight: 160)
                        .focused($isMessageFocused)
                        .scrollContentBackground(.hidden)
                        .font(DS.Font.body)
                        .onChange(of: message) { _, newValue in
                            if newValue.count > 1000 {
                                message = String(newValue.prefix(1000))
                                showCharacterLimitWarning = true
                            }
                        }

                    if message.isEmpty {
                        Text(L10n.t("اكتب رسالتك هنا...", "Write your message here..."))
                            .font(DS.Font.body)
                            .foregroundColor(DS.Color.textTertiary)
                            .padding(.top, DS.Spacing.sm)
                            .padding(.trailing, DS.Spacing.xs)
                            .allowsHitTesting(false)
                    }
                }
                .padding(DS.Spacing.md)

                HStack {
                    Spacer()
                    Text("\(message.count)/1000")
                        .font(DS.Font.caption2)
                        .foregroundColor(message.count >= 1000 ? DS.Color.error : DS.Color.textTertiary)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.sm)
            }
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(isMessageFocused ? DS.Color.primary.opacity(0.4) : DS.Color.textTertiary.opacity(0.15), lineWidth: isMessageFocused ? 1.5 : 1)
            )
        }
    }

    // MARK: - Submit Button
    private var submitButton: some View {
        DSPrimaryButton(
            L10n.t("إرسال الرسالة", "Send Message"),
            icon: "paperplane.fill",
            isLoading: authVM.isLoading,
            useGradient: canSubmit,
            color: canSubmit ? DS.Color.primary : .gray
        ) {
            submit()
        }
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1.0 : DS.Opacity.disabled)
    }

    // MARK: - Submit Logic
    private func submit() {
        Task {
            let sent = await authVM.sendContactMessage(
                category: selectedCategory,
                message: message,
                preferredContact: ""
            )
            if sent {
                withAnimation(DS.Anim.smooth) {
                    messageSent = true
                }
            } else {
                showErrorAlert = true
            }
        }
    }
}
