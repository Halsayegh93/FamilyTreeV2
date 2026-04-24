import SwiftUI
import PhotosUI
import Supabase

struct ContactCenterView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    enum Field { case subject, message }

    @State private var selectedCategory = "استفسار"
    @State private var subject = ""
    @State private var message = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var attachedImage: UIImage?
    @State private var showSuccessState = false
    @State private var showErrorAlert = false
    @State private var showCharacterLimitWarning = false
    @State private var appeared = false

    private let categoryItems: [(key: String, icon: String, labelAr: String, labelEn: String, color: Color)] = [
        ("استفسار", "questionmark.circle.fill", "استفسار", "Inquiry", DS.Color.info),
        ("اقتراح", "lightbulb.fill", "اقتراح", "Suggestion", DS.Color.warning),
        ("شكوى", "exclamationmark.triangle.fill", "شكوى", "Complaint", DS.Color.error),
        ("مشكلة تقنية", "wrench.and.screwdriver.fill", "مشكلة تقنية", "Technical Issue", DS.Color.neonPurple),
        ("أخرى", "ellipsis.circle.fill", "أخرى", "Other", DS.Color.accent)
    ]

    private var selectedCategoryColor: Color {
        categoryItems.first { $0.key == selectedCategory }?.color ?? DS.Color.primary
    }

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !authVM.isLoading
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            if showSuccessState {
                successView
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xl) {
                        headerSection
                            .opacity(appeared ? 1 : 0)
                            .scaleEffect(appeared ? 1 : 0.9)

                        categorySection
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)

                        combinedMessageCard
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 25)

                        senderInfoCard
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 32)

                        submitButton
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 35)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.xxxxl)
                    .onAppear {
                        guard !appeared else { return }
                        withAnimation(DS.Anim.smooth.delay(0.1)) { appeared = true }
                    }
                }
            }
        }
        .alert(L10n.t("تعذر الإرسال", "Failed to Send"), isPresented: $showErrorAlert) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(authVM.contactMessageError ?? L10n.t("تعذر الإرسال. حاول مرة أخرى.", "Send failed. Try again."))
        }
        .alert(L10n.t("الحد الأقصى", "Character Limit"), isPresented: $showCharacterLimitWarning) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.t("تم الوصول إلى الحد الأقصى للرسالة (1000 حرف).", "Message limit reached (1000 chars)"))
        }
        .onChange(of: selectedPhoto) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    withAnimation(DS.Anim.snappy) {
                        attachedImage = image
                    }
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: "envelope.open.fill")
                    .font(DS.Font.scaled(30, weight: .bold))
                    .foregroundColor(DS.Color.primary)
            }

            Text(L10n.t("تواصل معنا", "Contact Us"))
                .font(DS.Font.title3)
                .fontWeight(.black)
                .foregroundColor(DS.Color.textPrimary)

            Text(L10n.t("نسعد بتواصلك ونحرص على الرد بأسرع وقت", "We'll respond as soon as possible"))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xl)
        }
        .padding(.vertical, DS.Spacing.sm)
    }

    // MARK: - Sender Info Card (Auto-filled)
    private var senderInfoCard: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("بيانات المرسل", "Sender Info"),
                icon: "person.text.rectangle.fill",
                iconColor: DS.Color.primary
            )

            // الاسم
            HStack(spacing: DS.Spacing.md) {
                DSIcon("person.fill", color: DS.Color.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("الاسم", "Name"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                    Text(authVM.currentUser?.fullName ?? "—")
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                }
                Spacer()
                Image(systemName: "lock.fill")
                    .font(DS.Font.scaled(12, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)

            DSDivider()

            // رقم الهاتف
            HStack(spacing: DS.Spacing.md) {
                DSIcon("phone.fill", color: DS.Color.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("رقم الهاتف", "Phone"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                    Text(authVM.currentUser?.phoneNumber.flatMap { $0.isEmpty ? nil : KuwaitPhone.display($0) } ?? "—")
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                }
                Spacer()
                Image(systemName: "lock.fill")
                    .font(DS.Font.scaled(12, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
        }
    }

    // MARK: - Category Section
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(L10n.t("نوع الرسالة", "Message Type"))
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)
                .padding(.leading, DS.Spacing.xs)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(categoryItems, id: \.key) { item in
                        let isSelected = selectedCategory == item.key
                        Button {
                            withAnimation(DS.Anim.snappy) {
                                selectedCategory = item.key
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: item.icon)
                                    .font(DS.Font.scaled(13, weight: .semibold))
                                Text(L10n.t(item.labelAr, item.labelEn))
                                    .font(DS.Font.caption1)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(isSelected ? DS.Color.textOnPrimary : item.color)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.sm)
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
    }

    // MARK: - Combined Message Card (موضوع + رسالة + مرفق)
    private var combinedMessageCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("رسالتك", "Your Message"))
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)
                .padding(.leading, DS.Spacing.xs)
                .padding(.bottom, DS.Spacing.sm)

            VStack(spacing: 0) {
                // الموضوع
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "text.alignleft")
                        .font(DS.Font.scaled(14, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(width: 24)

                    TextField(
                        L10n.t("الموضوع (اختياري)...", "Subject (optional)..."),
                        text: $subject
                    )
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .focused($focusedField, equals: .subject)
                    .onChange(of: subject) { newValue in
                        if newValue.count > 100 { subject = String(newValue.prefix(100)) }
                    }

                    if !subject.isEmpty {
                        Button { subject = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(DS.Font.scaled(14))
                                .foregroundColor(DS.Color.textTertiary)
                        }
                        .accessibilityLabel(L10n.t("مسح", "Clear"))
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.md)

                Divider().padding(.horizontal, DS.Spacing.md)

                // الرسالة
                ZStack(alignment: .topTrailing) {
                    TextEditor(text: $message)
                        .frame(minHeight: 140)
                        .focused($focusedField, equals: .message)
                        .scrollContentBackground(.hidden)
                        .font(DS.Font.body)
                        .onChange(of: message) { newValue in
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
                .padding(.horizontal, DS.Spacing.md)
                .padding(.top, DS.Spacing.sm)

                HStack {
                    Spacer()
                    Text("\(message.count)/1000")
                        .font(DS.Font.caption2)
                        .foregroundColor(message.count >= 900 ? DS.Color.error : DS.Color.textTertiary)
                }
                .padding(.horizontal, DS.Spacing.md)

                Divider().padding(.horizontal, DS.Spacing.md)

                // المرفق
                if let image = attachedImage {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 120)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.sm)

                        Button {
                            withAnimation(DS.Anim.snappy) {
                                attachedImage = nil
                                selectedPhoto = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(DS.Font.scaled(20, weight: .bold))
                                .foregroundColor(.white)
                                .dsCardShadow()
                        }
                        .padding(DS.Spacing.lg)
                        .accessibilityLabel(L10n.t("إزالة الصورة", "Remove image"))
                    }
                } else {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "photo.badge.plus")
                                .font(DS.Font.scaled(15, weight: .semibold))
                            Text(L10n.t("إرفاق صورة", "Attach Image"))
                                .font(DS.Font.caption1)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(DS.Color.primary)
                        .padding(.vertical, DS.Spacing.md)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
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

    // MARK: - Success View
    private var successView: some View {
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
                Text(L10n.t("تم إرسال رسالتك وسيتم التواصل معك قريباً.", "Message sent. We'll reply soon."))
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xxxl)
            }

            Spacer()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Submit Logic
    private func submit() {
        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        // Build combined message with subject
        var fullMessage = cleanMessage
        if !cleanSubject.isEmpty {
            fullMessage = "الموضوع: \(cleanSubject)\n\n\(cleanMessage)"
        }

        Task {
            // Upload image if attached
            var imageNote = ""
            if let image = attachedImage,
               let data = ImageProcessor.process(image, for: .contact) {
                let path = "contact-attachments/\(UUID().uuidString).jpg"
                do {
                    try await SupabaseConfig.client.storage
                        .from("avatars")
                        .upload(path, data: data, options: .init(contentType: "image/jpeg"))
                    let publicUrl = try SupabaseConfig.client.storage
                        .from("avatars")
                        .getPublicURL(path: path)
                    imageNote = "\n\nصورة مرفقة: \(publicUrl.absoluteString)"
                } catch {
                    Log.warning("[Contact] ⚠️ فشل رفع الصورة: \(error.localizedDescription)")
                }
            }

            let sent = await authVM.sendContactMessage(
                category: selectedCategory,
                message: fullMessage + imageNote,
                preferredContact: authVM.currentUser?.phoneNumber
            )
            if sent {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(DS.Anim.smooth) {
                    showSuccessState = true
                }
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                showErrorAlert = true
            }
        }
    }
}
