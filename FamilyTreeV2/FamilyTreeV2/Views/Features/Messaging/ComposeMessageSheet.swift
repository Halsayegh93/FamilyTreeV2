import SwiftUI
import PhotosUI
import Supabase

/// شيت أنيقة لإنشاء رسالة جديدة للإدارة.
/// تستبدل ContactCenterView القديمة بـ flow أبسط: اختر تصنيف → اكتب موضوع + رسالة → إرسال.
struct ComposeMessageSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: FocusedField?

    enum FocusedField { case subject, message }

    @State private var category: String = "استفسار"
    @State private var subject: String = ""
    @State private var message: String = ""
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var attachedImage: UIImage? = nil
    @State private var isSending: Bool = false
    @State private var showErrorAlert: Bool = false

    /// callback لتحديث القائمة الأم بعد الإرسال
    var onSent: (() -> Void)? = nil

    private let categories: [(key: String, icon: String, labelAr: String, labelEn: String, color: Color)] = [
        ("استفسار", "questionmark.circle.fill", "استفسار", "Inquiry", DS.Color.info),
        ("اقتراح", "lightbulb.fill", "اقتراح", "Suggestion", DS.Color.warning),
        ("شكوى", "exclamationmark.triangle.fill", "شكوى", "Complaint", DS.Color.error),
        ("مشكلة تقنية", "wrench.and.screwdriver.fill", "تقني", "Technical", DS.Color.neonPurple),
        ("أخرى", "ellipsis.circle.fill", "أخرى", "Other", DS.Color.accent)
    ]

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    categorySection
                    subjectField
                    messageField
                    attachmentSection
                    senderRow
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xxxl)
            }
            .background(DS.Color.background.ignoresSafeArea())
            .navigationTitle(L10n.t("رسالة جديدة", "New Message"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .foregroundColor(DS.Color.error)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending {
                            ProgressView().progressViewStyle(.circular).tint(DS.Color.primary)
                        } else {
                            Text(L10n.t("إرسال", "Send"))
                                .fontWeight(.bold)
                        }
                    }
                    .disabled(!canSend)
                    .foregroundColor(canSend ? DS.Color.primary : DS.Color.textTertiary)
                }
            }
            .alert(L10n.t("تعذر الإرسال", "Failed to Send"), isPresented: $showErrorAlert) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: {
                Text(authVM.contactMessageError ?? L10n.t("تعذر الإرسال. حاول مرة أخرى.", "Send failed."))
            }
            .onChange(of: selectedPhoto) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        withAnimation(DS.Anim.snappy) { attachedImage = image }
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionLabel(L10n.t("التصنيف", "Category"), icon: "tag.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xs) {
                    ForEach(categories, id: \.key) { item in
                        let isSelected = category == item.key
                        Button {
                            withAnimation(DS.Anim.snappy) { category = item.key }
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: item.icon)
                                    .font(DS.Font.scaled(12, weight: .semibold))
                                Text(L10n.t(item.labelAr, item.labelEn))
                                    .font(DS.Font.caption1)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(isSelected ? .white : item.color)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.sm)
                            .background(
                                Capsule()
                                    .fill(isSelected ? item.color : item.color.opacity(0.1))
                            )
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

    private var subjectField: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionLabel(L10n.t("الموضوع (اختياري)", "Subject (optional)"), icon: "text.alignleft")
            TextField(L10n.t("ملخّص رسالتك…", "Brief summary…"), text: $subject)
                .font(DS.Font.body)
                .padding(DS.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .fill(DS.Color.surfaceElevated)
                )
                .focused($focused, equals: .subject)
                .onChange(of: subject) { v in
                    if v.count > 100 { subject = String(v.prefix(100)) }
                }
        }
    }

    private var messageField: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionLabel(L10n.t("الرسالة", "Message"), icon: "square.and.pencil")
            ZStack(alignment: .topLeading) {
                TextEditor(text: $message)
                    .focused($focused, equals: .message)
                    .frame(minHeight: 180)
                    .padding(DS.Spacing.sm)
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.lg)
                            .fill(DS.Color.surfaceElevated)
                    )
                    .font(DS.Font.body)
                    .onChange(of: message) { v in
                        if v.count > 1000 { message = String(v.prefix(1000)) }
                    }

                if message.isEmpty {
                    Text(L10n.t("اكتب رسالتك هنا…", "Write your message here…"))
                        .font(DS.Font.body)
                        .foregroundColor(DS.Color.textTertiary)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.top, DS.Spacing.md)
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Spacer()
                Text("\(message.count)/1000")
                    .font(DS.Font.caption2)
                    .foregroundColor(message.count >= 900 ? DS.Color.error : DS.Color.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var attachmentSection: some View {
        if let img = attachedImage {
            HStack(spacing: DS.Spacing.md) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("صورة مرفقة", "Image attached"))
                        .font(DS.Font.calloutBold)
                    Text(L10n.t("سترسل مع الرسالة", "Will be sent"))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textSecondary)
                }
                Spacer()
                Button {
                    withAnimation { attachedImage = nil; selectedPhoto = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Font.scaled(20))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            .padding(DS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .fill(DS.Color.surfaceElevated)
            )
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
                .padding(DS.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .fill(DS.Color.primary.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var senderRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "person.fill")
                .font(DS.Font.caption2)
            Text(L10n.t("ترسل باسم:", "Sending as:"))
                .font(DS.Font.caption2)
            Text(authVM.currentUser?.fullName ?? "—")
                .font(DS.Font.caption1)
                .fontWeight(.semibold)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
            Spacer()
            Image(systemName: "lock.fill")
                .font(DS.Font.caption2)
        }
        .foregroundColor(DS.Color.textTertiary)
        .padding(.top, DS.Spacing.xs)
    }

    private func sectionLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(DS.Font.caption1)
            Text(text)
                .font(DS.Font.calloutBold)
            Spacer()
        }
        .foregroundColor(DS.Color.textSecondary)
    }

    // MARK: - Send

    private func send() async {
        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMessage.isEmpty else { return }

        var fullMessage = cleanMessage
        if !cleanSubject.isEmpty {
            fullMessage = "الموضوع: \(cleanSubject)\n\n\(cleanMessage)"
        }

        isSending = true
        defer { isSending = false }

        // رفع الصورة لو موجودة
        var imageNote = ""
        if let image = attachedImage,
           let data = ImageProcessor.process(image, for: .contact) {
            let path = "contact-attachments/\(UUID().uuidString).jpg"
            do {
                try await SupabaseConfig.client.storage
                    .from("avatars")
                    .upload(path, data: data, options: .init(contentType: "image/jpeg"))
                let url = try SupabaseConfig.client.storage
                    .from("avatars")
                    .getPublicURL(path: path)
                imageNote = "\n\nصورة مرفقة: \(url.absoluteString)"
            } catch {
                Log.warning("[Compose] ⚠️ فشل رفع الصورة: \(error.localizedDescription)")
            }
        }

        let sent = await authVM.sendContactMessage(
            category: category,
            message: fullMessage + imageNote,
            preferredContact: authVM.currentUser?.phoneNumber
        )

        if sent {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSent?()
            await authVM.fetchMyContactMessages(force: true)
            dismiss()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            showErrorAlert = true
        }
    }
}
