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

    private var selectedCategoryItem: (key: String, icon: String, labelAr: String, labelEn: String, color: Color)? {
        categoryItems.first { $0.key == selectedCategory }
    }

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !authVM.isLoading
    }

    private var latestReply: AdminRequest? {
        authVM.myContactMessages.first { !($0.adminReply?.isEmpty ?? true) }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            if showSuccessState {
                successView
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xl) {
                        greetingRow
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 16)

                        VStack(alignment: .leading, spacing: DS.Spacing.md) {
                            sectionTitle(L10n.t("نوع الرسالة", "Message Type"), icon: "tag.fill")
                            categoryGrid
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)

                        composeCard
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 24)

                        senderFooter
                            .opacity(appeared ? 1 : 0)

                        submitButton
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 28)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.xxxxl)
                    .onAppear {
                        guard !appeared else { return }
                        withAnimation(DS.Anim.smooth.delay(0.05)) { appeared = true }
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
                    withAnimation(DS.Anim.snappy) { attachedImage = image }
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Greeting Row (with corner Admin Replies button)

    private var greetingRow: some View {
        let firstName = authVM.currentUser?.firstName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let greeting: String = {
            if firstName.isEmpty {
                return L10n.t("مرحباً 👋", "Hi 👋")
            }
            return L10n.t("مرحباً، \(firstName) 👋", "Hi, \(firstName) 👋")
        }()

        return HStack(alignment: .center, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(greeting)
                    .font(DS.Font.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("كيف نقدر نخدمك اليوم؟", "How can we help you today?"))
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textSecondary)
            }
            Spacer(minLength: DS.Spacing.sm)
            inboxCornerButton
        }
        .task {
            await authVM.fetchMyContactMessages()
        }
    }

    // MARK: - Corner Inbox Button (small with badge)

    private var inboxCornerButton: some View {
        let count = authVM.unreadAdminRepliesCount
        let hasUnread = count > 0

        return NavigationLink {
            MyContactRepliesView()
        } label: {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(DS.Color.gradientPrimary)
                        .frame(width: 44, height: 44)
                        .shadow(color: DS.Color.primary.opacity(0.3), radius: 6, y: 3)
                    Image(systemName: hasUnread ? "envelope.badge.fill" : "envelope.open.fill")
                        .font(DS.Font.scaled(17, weight: .semibold))
                        .foregroundColor(.white)
                        .symbolRenderingMode(.hierarchical)
                }
                // Badge — top-right corner, overlapping
                if hasUnread {
                    Text("\(count)")
                        .font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .padding(.horizontal, 4)
                        .background(
                            Capsule()
                                .fill(DS.Color.error)
                                .overlay(Capsule().stroke(DS.Color.background, lineWidth: 2))
                        )
                        .offset(x: 4, y: -4)
                }
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(
            hasUnread
            ? L10n.t("ردود الإدارة، \(count) جديد", "Admin replies, \(count) new")
            : L10n.t("ردود الإدارة", "Admin replies")
        )
    }

    // MARK: - Section Title Helper

    private func sectionTitle(_ text: String, icon: String) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
            Text(text)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)
            Spacer()
        }
    }

    // MARK: - Category Grid (compact 3 columns)

    private var categoryGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: DS.Spacing.xs),
            GridItem(.flexible(), spacing: DS.Spacing.xs),
            GridItem(.flexible(), spacing: DS.Spacing.xs),
        ]
        return LazyVGrid(columns: columns, spacing: DS.Spacing.xs) {
            ForEach(categoryItems, id: \.key) { item in
                let isSelected = selectedCategory == item.key
                Button {
                    withAnimation(DS.Anim.snappy) { selectedCategory = item.key }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(isSelected ? item.color : item.color.opacity(0.12))
                                .frame(width: 28, height: 28)
                            Image(systemName: item.icon)
                                .font(DS.Font.scaled(13, weight: .semibold))
                                .foregroundColor(isSelected ? .white : item.color)
                        }
                        Text(L10n.t(item.labelAr, item.labelEn))
                            .font(DS.Font.caption2)
                            .fontWeight(isSelected ? .bold : .semibold)
                            .foregroundColor(isSelected ? DS.Color.textPrimary : DS.Color.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .fill(isSelected ? item.color.opacity(0.08) : DS.Color.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(isSelected ? item.color : DS.Color.surface, lineWidth: isSelected ? 1.5 : 0.5)
                    )
                }
                .buttonStyle(DSScaleButtonStyle())
            }
        }
    }

    // MARK: - Compose Card

    private var composeCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            sectionTitle(L10n.t("رسالتك", "Your Message"), icon: "square.and.pencil")

            VStack(spacing: 0) {
                // Subject
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "text.alignleft")
                        .font(DS.Font.scaled(14, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(width: 22)

                    TextField(
                        L10n.t("الموضوع (اختياري)", "Subject (optional)"),
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
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.md)

                Divider().padding(.horizontal, DS.Spacing.md)

                // Message body
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $message)
                        .frame(minHeight: 150)
                        .focused($focusedField, equals: .message)
                        .scrollContentBackground(.hidden)
                        .font(DS.Font.body)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.top, DS.Spacing.xs)
                        .onChange(of: message) { newValue in
                            if newValue.count > 1000 {
                                message = String(newValue.prefix(1000))
                                showCharacterLimitWarning = true
                            }
                        }

                    if message.isEmpty {
                        Text(L10n.t("اكتب رسالتك هنا…", "Write your message here…"))
                            .font(DS.Font.body)
                            .foregroundColor(DS.Color.textTertiary)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.top, DS.Spacing.md - 2)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, DS.Spacing.sm)

                // Counter
                HStack {
                    Spacer()
                    Text("\(message.count)/1000")
                        .font(DS.Font.caption2)
                        .foregroundColor(message.count >= 900 ? DS.Color.error : DS.Color.textTertiary)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.top, DS.Spacing.xs)
                .padding(.bottom, DS.Spacing.sm)

                Divider().padding(.horizontal, DS.Spacing.md)

                // Attachment row
                attachmentRow
            }
            .background(DS.Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(DS.Color.surface, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var attachmentRow: some View {
        if let image = attachedImage {
            HStack(spacing: DS.Spacing.md) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("صورة مرفقة", "Image attached"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(L10n.t("سيتم إرسالها مع الرسالة", "Will be sent with your message"))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textSecondary)
                }

                Spacer()

                Button {
                    withAnimation(DS.Anim.snappy) {
                        attachedImage = nil
                        selectedPhoto = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Font.scaled(22))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
        } else {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "paperclip")
                        .font(DS.Font.scaled(14, weight: .semibold))
                    Text(L10n.t("إرفاق صورة (اختياري)", "Attach image (optional)"))
                        .font(DS.Font.callout)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .foregroundColor(DS.Color.primary)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.md)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sender Footer (compact)

    private var senderFooter: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "person.fill")
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
            Text(L10n.t("ترسل باسم:", "Sending as:"))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
            Text(authVM.currentUser?.fullName ?? "—")
                .font(DS.Font.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
            if let phone = authVM.currentUser?.phoneNumber, !phone.isEmpty {
                Text("·")
                    .foregroundColor(DS.Color.textTertiary)
                Text(KuwaitPhone.display(phone))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "lock.fill")
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textTertiary)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .fill(DS.Color.surface.opacity(0.5))
        )
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
                    .frame(width: 130, height: 130)
                Circle()
                    .fill(DS.Color.success.opacity(0.18))
                    .frame(width: 96, height: 96)
                Image(systemName: "checkmark.circle.fill")
                    .font(DS.Font.scaled(48, weight: .bold))
                    .foregroundColor(DS.Color.success)
            }

            VStack(spacing: DS.Spacing.sm) {
                Text(L10n.t("تم الإرسال بنجاح", "Sent Successfully"))
                    .font(DS.Font.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("تم إرسال رسالتك. الإدارة بترد عليك من شاشة \"ردود الإدارة\" أو على إيميلك.",
                            "Your message was sent. The admin will reply via \"Admin Replies\" or email."))
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xxxl)
            }

            Spacer()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Helpers

    private func timeAgo(_ iso: String?) -> String {
        guard let iso = iso else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = f.date(from: iso)
        if date == nil {
            f.formatOptions = [.withInternetDateTime]
            date = f.date(from: iso)
        }
        guard let d = date else { return "" }
        let secs = Int(Date().timeIntervalSince(d))
        if secs < 60 { return L10n.t("الآن", "Now") }
        if secs < 3600 { return L10n.t("منذ \(secs/60) د", "\(secs/60)m") }
        if secs < 86400 { return L10n.t("منذ \(secs/3600) س", "\(secs/3600)h") }
        return L10n.t("منذ \(secs/86400) يوم", "\(secs/86400)d")
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
