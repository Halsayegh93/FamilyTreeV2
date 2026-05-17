import SwiftUI

struct AdminContactMessageDetailSheet: View {
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) private var dismiss

    let message: AdminRequest
    @State private var isProcessing = false

    var parsed: ContactMessageParser.Parsed {
        ContactMessageParser.parse(message)
    }

    var senderName: String {
        message.member?.fullName ?? L10n.t("عضو", "Member")
    }

    var senderPhone: String? {
        message.member?.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var senderEmail: String? {
        let e = message.member?.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (e?.isEmpty ?? true) ? nil : e
    }

    var isHandled: Bool {
        message.status != ApprovalStatus.pending.rawValue
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    senderCard
                    if let cat = parsed.category, !cat.isEmpty {
                        categoryBadge(cat)
                    }
                    messageCard
                    if let pref = parsed.preferredContact, !pref.isEmpty {
                        preferredContactRow(pref)
                    }
                    quickActions
                    Spacer(minLength: DS.Spacing.lg)
                    handledToggleButton
                }
                .padding(DS.Spacing.lg)
            }
            .background(DS.Color.background.ignoresSafeArea())
            .navigationTitle(L10n.t("تفاصيل الرسالة", "Message Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                }
            }
        }
    }

    private var senderCard: some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.15))
                    .frame(width: 56, height: 56)
                Text(String(senderName.prefix(1)))
                    .font(DS.Font.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(senderName)
                    .font(DS.Font.bodyBold)
                    .foregroundColor(DS.Color.textPrimary)
                Text(dateFormatted(message.createdAt))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)
            }
            Spacer()
            if isHandled {
                Label(L10n.t("مُعالَجة", "Handled"), systemImage: "checkmark.seal.fill")
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.success)
            }
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(DS.Color.surfaceElevated)
        )
    }

    private func categoryBadge(_ category: String) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "tag.fill")
                .font(DS.Font.caption1)
            Text(category)
                .font(DS.Font.callout)
                .fontWeight(.semibold)
        }
        .foregroundColor(DS.Color.info)
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(
            Capsule()
                .fill(DS.Color.info.opacity(0.12))
        )
    }

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "text.bubble.fill")
                    .font(DS.Font.caption1)
                Text(L10n.t("الرسالة", "Message"))
                    .font(DS.Font.calloutBold)
            }
            .foregroundColor(DS.Color.textSecondary)

            Text(parsed.message ?? message.details ?? "")
                .font(DS.Font.body)
                .foregroundColor(DS.Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(DS.Color.surfaceElevated)
        )
    }

    private func preferredContactRow(_ pref: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "star.fill")
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.warning)
            Text(L10n.t("وسيلة التواصل المفضّلة:", "Preferred contact:"))
                .font(DS.Font.subheadline)
                .foregroundColor(DS.Color.textSecondary)
            Text(pref)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.md)
    }

    private var quickActions: some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "bolt.fill")
                    .font(DS.Font.caption1)
                Text(L10n.t("إجراءات سريعة", "Quick Actions"))
                    .font(DS.Font.calloutBold)
                Spacer()
            }
            .foregroundColor(DS.Color.textSecondary)
            .padding(.bottom, DS.Spacing.xs)

            if let phone = senderPhone, !phone.isEmpty {
                actionButton(
                    icon: "phone.fill",
                    label: L10n.t("اتصال", "Call"),
                    color: DS.Color.success,
                    url: URL(string: "tel:\(phone)")
                )
                actionButton(
                    icon: "message.fill",
                    label: L10n.t("واتساب", "WhatsApp"),
                    color: Color(hex: "#25D366"),
                    url: whatsappURL(phone: phone)
                )
            }
            if let email = senderEmail {
                actionButton(
                    icon: "envelope.fill",
                    label: L10n.t("إيميل", "Email"),
                    color: DS.Color.info,
                    url: URL(string: "mailto:\(email)")
                )
            }
            if senderPhone == nil && senderEmail == nil {
                Text(L10n.t("لا توجد وسائل تواصل متاحة لهذا العضو", "No contact methods available for this member"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.vertical, DS.Spacing.sm)
            }
        }
    }

    private func actionButton(icon: String, label: String, color: Color, url: URL?) -> some View {
        Button {
            if let url = url { UIApplication.shared.open(url) }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: icon)
                    .font(DS.Font.callout)
                    .foregroundColor(color)
                    .frame(width: 32)
                Text(label)
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textPrimary)
                Spacer()
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)
            }
            .padding(DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(DS.Color.surfaceElevated)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
        .disabled(url == nil)
        .opacity(url == nil ? 0.5 : 1)
    }

    private var handledToggleButton: some View {
        Button {
            Task {
                isProcessing = true
                if isHandled {
                    await adminRequestVM.markContactMessageUnhandled(message)
                } else {
                    await adminRequestVM.markContactMessageHandled(message)
                }
                isProcessing = false
                dismiss()
            }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                if isProcessing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Image(systemName: isHandled ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                        .font(DS.Font.callout)
                }
                Text(isHandled
                     ? L10n.t("إعادة لقيد المعالجة", "Mark as Unhandled")
                     : L10n.t("تعليم كمُعالَجة", "Mark as Handled"))
                    .font(DS.Font.calloutBold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .fill(isHandled ? DS.Color.warning : DS.Color.success)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
        .disabled(isProcessing)
    }

    // MARK: - Helpers

    private func dateFormatted(_ iso: String?) -> String {
        guard let iso = iso else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = f.date(from: iso)
        if date == nil {
            f.formatOptions = [.withInternetDateTime]
            date = f.date(from: iso)
        }
        guard let d = date else { return "" }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        df.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en")
        return df.string(from: d)
    }

    private func whatsappURL(phone: String) -> URL? {
        // إزالة كل ما عدا الأرقام والـ +
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        let clean = digits.hasPrefix("+") ? String(digits.dropFirst()) : digits
        return URL(string: "https://wa.me/\(clean)")
    }
}
