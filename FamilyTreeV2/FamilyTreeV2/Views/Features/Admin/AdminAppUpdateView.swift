import SwiftUI
import Supabase

/// تحديثات التطبيق ورسائل النظام — تُنشر لكل الأعضاء وتظهر في تبويب
/// «المستجدات» بمركز الإشعارات (طلب المالك).
/// الفرق عن «إرسال إشعارات»: هذه إعلانات عامة عن التطبيق نفسه (إصدار جديد،
/// ميزة، صيانة)، لا رسائل موجّهة لأعضاء بعينهم.
struct AdminAppUpdateView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var kind: UpdateKind = .feature
    @State private var version = ""
    @State private var summary = ""
    @State private var isSending = false
    @State private var didSend = false
    @State private var errorText: String?
    @FocusState private var summaryFocused: Bool

    private let maxLength = 500

    // MARK: - نوع الرسالة

    enum UpdateKind: String, CaseIterable, Identifiable {
        case feature, fix, maintenance, notice
        var id: String { rawValue }

        var title: String {
            switch self {
            case .feature:     return L10n.t("ميزة جديدة", "New feature")
            case .fix:         return L10n.t("إصلاح", "Fix")
            case .maintenance: return L10n.t("صيانة", "Maintenance")
            case .notice:      return L10n.t("تنويه", "Notice")
            }
        }
        var icon: String {
            switch self {
            case .feature:     return "sparkles"
            case .fix:         return "wrench.and.screwdriver.fill"
            case .maintenance: return "gearshape.2.fill"
            case .notice:      return "info.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .feature:     return DS.Color.success
            case .fix:         return DS.Color.info
            case .maintenance: return DS.Color.warning
            case .notice:      return DS.Color.primary
            }
        }
        /// عنوان الإشعار كما يصل العضو
        var headline: String {
            switch self {
            case .feature:     return L10n.t("ميزة جديدة في التطبيق", "New in the app")
            case .fix:         return L10n.t("تحسينات وإصلاحات", "Improvements & fixes")
            case .maintenance: return L10n.t("صيانة مجدولة", "Scheduled maintenance")
            case .notice:      return L10n.t("تنويه من الإدارة", "Notice from admin")
            }
        }
    }

    private var canSend: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && !didSend
    }

    /// العنوان النهائي: «ميزة جديدة في التطبيق · 2.1»
    private var finalTitle: String {
        let v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? kind.headline : "\(kind.headline) · \(v)"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    introCard
                    kindPicker
                    versionField
                    summaryField
                    previewCard

                    if let errorText {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(DS.Color.error)
                            Text(errorText)
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .padding(DS.Spacing.sm)
                        .background(DS.Color.error.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                    }

                    DSPrimaryButton(
                        didSend ? L10n.t("تم النشر", "Published")
                                : L10n.t("نشر للجميع", "Publish to everyone"),
                        icon: didSend ? "checkmark.circle.fill" : "megaphone.fill",
                        isLoading: isSending
                    ) {
                        Task { await publish() }
                    }
                    .disabled(!canSend)
                }
                .padding(DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxxxl)
            }
        }
        .navigationTitle(L10n.t("تحديثات التطبيق", "App Updates"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - الأقسام

    private var introCard: some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "megaphone.fill")
                    .font(DS.Font.scaled(17, weight: .semibold))
                    .foregroundColor(DS.Color.primary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("رسالة نظام لكل الأعضاء", "System message to everyone"))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("تظهر في تبويب «المستجدات» ويصل معها إشعار.",
                            "Appears in the Updates tab with a push notification."))
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

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionLabel(L10n.t("النوع", "Type"), icon: "square.grid.2x2.fill")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                ForEach(UpdateKind.allCases) { k in
                    let selected = kind == k
                    Button {
                        withAnimation(DS.Anim.quick) { kind = k }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: k.icon)
                                .font(DS.Font.scaled(11, weight: .bold))
                                .foregroundColor(selected ? .white : k.color)
                                .frame(width: 22, height: 22)
                                .background(selected ? k.color : k.color.opacity(0.12))
                                .clipShape(Circle())
                            Text(k.title)
                                .font(DS.Font.scaled(11, weight: selected ? .bold : .semibold))
                                .foregroundColor(selected ? k.color : DS.Color.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(selected ? k.color.opacity(0.08) : DS.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .strokeBorder(selected ? k.color.opacity(0.40) : DS.Color.textTertiary.opacity(0.12),
                                              lineWidth: selected ? 1.3 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var versionField: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionLabel(L10n.t("رقم الإصدار (اختياري)", "Version (optional)"), icon: "number")
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "app.badge.fill")
                    .font(DS.Font.scaled(13, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                TextField(L10n.t("مثال: 2.1", "e.g. 2.1"), text: $version)
                    .font(DS.Font.callout)
                    .keyboardType(.decimalPad)
                    .environment(\.layoutDirection, .leftToRight)
                    .multilineTextAlignment(L10n.isArabic ? .trailing : .leading)
            }
            .padding(DS.Spacing.md)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
    }

    private var summaryField: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                sectionLabel(L10n.t("ما الجديد", "What's new"), icon: "text.alignright")
                Spacer()
                Text("\(summary.count)/\(maxLength)")
                    .font(DS.Font.caption2)
                    .foregroundColor(summary.count > maxLength ? DS.Color.error : DS.Color.textTertiary)
            }
            ZStack(alignment: .topLeading) {
                if summary.isEmpty {
                    Text(L10n.t("اكتب ما تغيّر في التطبيق…", "Describe what changed…"))
                        .font(DS.Font.body)
                        .foregroundColor(DS.Color.textTertiary)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.md + 4)
                }
                TextEditor(text: $summary)
                    .focused($summaryFocused)
                    .font(DS.Font.body)
                    .scrollContentBackground(.hidden)
                    .padding(DS.Spacing.sm)
                    .frame(minHeight: 130, maxHeight: 200)
                    .onChange(of: summary) { _ in
                        if summary.count > maxLength { summary = String(summary.prefix(maxLength)) }
                    }
            }
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
    }

    /// معاينة الشكل كما يصل العضو
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionLabel(L10n.t("المعاينة", "Preview"), icon: "eye.fill")
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                Image(systemName: kind.icon)
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(kind.color)
                    .frame(width: 32, height: 32)
                    .background(kind.color.opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(finalTitle)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(summary.isEmpty ? L10n.t("نص التحديث…", "Update text…") : summary)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Spacing.md)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .strokeBorder(DS.Color.mutedBackground, lineWidth: 1)
            )
        }
    }

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

    // MARK: - النشر

    @MainActor
    private func publish() async {
        errorText = nil
        summaryFocused = false
        isSending = true
        defer { isSending = false }

        // صف واحد بلا هدف: القاعدة تُفرّخ نسخة لكل عضو ويخرج الدفع مرة واحدة
        let ok = await notificationVM.sendNotification(
            title: finalTitle,
            body: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            targetMemberIds: nil,
            kind: "app_update"
        )
        if ok {
            didSend = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } else {
            errorText = L10n.t("تعذّر النشر. حاول مرة أخرى.", "Could not publish. Try again.")
        }
    }
}
