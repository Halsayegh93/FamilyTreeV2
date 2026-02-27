import SwiftUI

struct ContactCenterView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory = "اقتراح"
    @State private var message = ""
    @State private var preferredContact = ""
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false

    private let categories = ["اقتراح", "شكوى", "تحديث"]

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !authVM.isLoading
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                // Decorative gradient circles
                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 240, height: 240)
                    .blur(radius: 100)
                    .opacity(0.14)
                    .offset(x: -140, y: -220)

                Circle()
                    .fill(DS.Color.gradientAccent)
                    .frame(width: 180, height: 180)
                    .blur(radius: 80)
                    .opacity(0.10)
                    .offset(x: 140, y: 200)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xl) {
                        headerCard
                        categorySection
                        messageSection
                        contactSection
                        submitButton
                    }
                    .padding(DS.Spacing.lg)
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
        }
    }

    // MARK: - Header Card
    private var headerCard: some View {
        DSGradientCard(gradient: DS.Color.gradientPrimary) {
            HStack(spacing: DS.Spacing.md) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text(L10n.t("مركز التواصل", "Contact Center"))
                        .font(DS.Font.title2)
                        .foregroundColor(.white)
                    Text(L10n.t("أرسل اقتراحك أو شكواك أو طلب التحديث بسهولة.", "Send your suggestion, complaint, or update request easily."))
                        .font(DS.Font.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    Circle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 50, height: 50)
                    Image(systemName: "envelope.open.fill")
                        .font(DS.Font.scaled(22, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(DS.Spacing.xl)
        }
    }

    // MARK: - Category Section
    private var categorySection: some View {
        DSCard(padding: 0) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "tag.fill")
                        .font(DS.Font.scaled(12, weight: .semibold))
                        .foregroundStyle(DS.Color.gradientAccent)
                    Text(L10n.t("نوع الطلب", "Request Type"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Picker(L10n.t("نوع الطلب", "Request Type"), selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .tint(DS.Color.primary)
            }
            .padding(DS.Spacing.lg)
        }
    }

    // MARK: - Message Section
    private var messageSection: some View {
        DSCard(padding: 0) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "text.alignright")
                        .font(DS.Font.scaled(12, weight: .semibold))
                        .foregroundStyle(DS.Color.gradientAccent)
                    Text(L10n.t("تفاصيل الرسالة", "Message Details"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $message)
                    .frame(minHeight: 140)
                    .padding(DS.Spacing.sm)
                    .background(DS.Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                    .overlay(alignment: .topTrailing) {
                        if message.isEmpty {
                            Text(L10n.t("اكتب رسالتك هنا...", "Write your message here..."))
                                .font(DS.Font.body)
                                .foregroundColor(DS.Color.textTertiary)
                                .padding(.top, DS.Spacing.lg)
                                .padding(.trailing, DS.Spacing.lg)
                        }
                    }
            }
            .padding(DS.Spacing.lg)
        }
    }

    // MARK: - Contact Section
    private var contactSection: some View {
        DSCard(padding: 0) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "phone.fill")
                        .font(DS.Font.scaled(12, weight: .semibold))
                        .foregroundStyle(DS.Color.gradientAccent)
                    Text(L10n.t("وسيلة التواصل (اختياري)", "Contact Method (optional)"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TextField(L10n.t("رقم هاتف أو بريد إلكتروني", "Phone or email"), text: $preferredContact)
                    .font(DS.Font.body)
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.primary.opacity(0.15), lineWidth: 1)
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(DS.Spacing.lg)
        }
    }

    // MARK: - Submit Button
    private var submitButton: some View {
        DSPrimaryButton(L10n.t("إرسال", "Send"), icon: "paperplane.fill", isLoading: authVM.isLoading, useGradient: canSubmit, color: canSubmit ? DS.Color.primary : .gray) {
            submit()
        }
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1.0 : 0.6)
    }

    // MARK: - Submit Logic
    private func submit() {
        Task {
            let sent = await authVM.sendContactMessage(
                category: selectedCategory,
                message: message,
                preferredContact: preferredContact
            )
            if sent {
                showSuccessAlert = true
            } else {
                showErrorAlert = true
            }
        }
    }
}
