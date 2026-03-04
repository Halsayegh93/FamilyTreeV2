import SwiftUI

struct ContactCenterView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isMessageFocused: Bool

    @State private var selectedCategory = "اقتراح"
    @State private var message = ""

    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var appeared = false

    private let categoryItems: [(key: String, icon: String, labelAr: String, labelEn: String, color: Color)] = [
        ("اقتراح", "lightbulb.fill", "اقتراح", "Suggestion", DS.Color.warning),
        ("شكوى", "exclamationmark.bubble.fill", "شكوى", "Complaint", DS.Color.error),
        ("تحديث", "arrow.triangle.2.circlepath", "تحديث بيانات", "Update Info", DS.Color.info)
    ]

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !authVM.isLoading
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                DSDecorativeBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xl) {
                        headerCard
                        categorySection
                        messageSection
                        submitButton

                        Spacer().frame(height: DS.Spacing.xxxl)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.md)
                }
            }
            .navigationTitle(L10n.t("التواصل", "Contact"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.error)
                }
            }
            .alert(L10n.t("تم الإرسال", "Sent Successfully"), isPresented: $showSuccessAlert) {
                Button(L10n.t("حسناً", "OK")) { dismiss() }
            } message: {
                Text(L10n.t("تم إرسال رسالتك بنجاح وسيتم التواصل معك قريباً.", "Your message has been sent successfully."))
            }
            .alert(L10n.t("تعذر الإرسال", "Failed to Send"), isPresented: $showErrorAlert) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: {
                Text(authVM.contactMessageError ?? L10n.t("تعذر إرسال الرسالة حالياً. حاول مرة أخرى.", "Failed to send message. Please try again."))
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .onAppear {
                withAnimation(DS.Anim.smooth) { appeared = true }
            }
        }
    }

    // MARK: - Header Card
    private var headerCard: some View {
        DSGradientCard(gradient: DS.Color.gradientOcean) {
            VStack(spacing: DS.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Circle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 80, height: 80)
                    Image(systemName: "envelope.open.fill")
                        .font(DS.Font.scaled(28, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(spacing: DS.Spacing.xs) {
                    Text(L10n.t("مركز التواصل", "Contact Center"))
                        .font(DS.Font.title2)
                        .foregroundColor(.white)

                    Text(L10n.t("نسعد بتواصلك معنا، أرسل اقتراحك أو استفسارك", "We're happy to hear from you — send us your feedback"))
                        .font(DS.Font.footnote)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xxl)
            .padding(.horizontal, DS.Spacing.lg)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    // MARK: - Category Section
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSSectionHeader(title: L10n.t("نوع الرسالة", "Message Type"), icon: "tag.fill")

            HStack(spacing: DS.Spacing.md) {
                ForEach(categoryItems, id: \.key) { item in
                    let isSelected = selectedCategory == item.key
                    Button {
                        withAnimation(DS.Anim.snappy) {
                            selectedCategory = item.key
                        }
                    } label: {
                        VStack(spacing: DS.Spacing.sm) {
                            ZStack {
                                Circle()
                                    .fill(isSelected ? item.color : item.color.opacity(0.10))
                                    .frame(width: 44, height: 44)

                                Image(systemName: item.icon)
                                    .font(DS.Font.scaled(18, weight: .semibold))
                                    .foregroundColor(isSelected ? .white : item.color)
                            }

                            Text(L10n.t(item.labelAr, item.labelEn))
                                .font(DS.Font.caption1)
                                .fontWeight(isSelected ? .bold : .medium)
                                .foregroundColor(isSelected ? DS.Color.textPrimary : DS.Color.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.lg)
                                .fill(isSelected ? item.color.opacity(0.08) : DS.Color.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.lg)
                                .stroke(isSelected ? item.color.opacity(0.4) : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(DS.Anim.smooth.delay(0.05), value: appeared)
    }

    // MARK: - Message Section
    private var messageSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSSectionHeader(title: L10n.t("تفاصيل الرسالة", "Message Details"), icon: "text.alignright")

            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    TextEditor(text: $message)
                        .frame(minHeight: 150)
                        .focused($isMessageFocused)
                        .scrollContentBackground(.hidden)
                        .font(DS.Font.body)
                        .onChange(of: message) { _, newValue in
                            if newValue.count > 1000 {
                                message = String(newValue.prefix(1000))
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

                // Character count
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
            .shadow(color: isMessageFocused ? DS.Color.primary.opacity(0.08) : .clear, radius: 8, y: 2)
            .animation(DS.Anim.quick, value: isMessageFocused)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(DS.Anim.smooth.delay(0.1), value: appeared)
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
        .opacity(canSubmit ? 1.0 : 0.5)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(DS.Anim.smooth.delay(0.15), value: appeared)
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
                showSuccessAlert = true
            } else {
                showErrorAlert = true
            }
        }
    }
}
