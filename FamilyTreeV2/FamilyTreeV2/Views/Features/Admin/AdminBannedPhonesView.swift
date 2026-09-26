import SwiftUI

struct AdminBannedPhonesView: View {
    @EnvironmentObject var authVM: AuthViewModel

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    @State private var searchText = ""
    @State private var isLoading = true
    @State private var showAddSheet = false
    @State private var phoneToUnban: BannedPhone?
    @State private var isProcessing = false

    // قائمة مفلترة بالبحث
    private var filteredPhones: [BannedPhone] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return authVM.bannedPhones
        }
        let query = searchText.lowercased()
        return authVM.bannedPhones.filter {
            $0.phoneNumber.contains(query) ||
            ($0.reason?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(DS.Color.primary)
                    Spacer()
                } else if authVM.bannedPhones.isEmpty {
                    emptyState
                } else {
                    statsBar
                    searchBar
                    phonesList
                }
            }
        }
        .navigationTitle(t("الأرقام المحظورة", "Banned Numbers"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .toolbar {
            // زر الإضافة للمالك فقط — المدير يتصفّح بدون تعديل
            if authVM.canManageBannedPhones {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(DS.Font.title3)
                            .foregroundStyle(DS.Color.primary)
                    }
                }
            }
        }
        .dsCenterBox(isPresented: $showAddSheet) {
            AddBanSheet(authVM: authVM)
        }
        .dsAlert(
            t("إلغاء الحظر", "Remove Ban"),
            isPresented: Binding(
                get: { phoneToUnban != nil },
                set: { if !$0 { phoneToUnban = nil } }
            )
        ) {
            Button(t("إلغاء", "Cancel"), role: .cancel) { phoneToUnban = nil }
            Button(t("إلغاء الحظر", "Remove Ban"), role: .destructive) {
                guard let phone = phoneToUnban else { return }
                Task {
                    isProcessing = true
                    _ = await authVM.unbanPhone(phone.id)
                    isProcessing = false
                    phoneToUnban = nil
                }
            }
        } message: {
            if let phone = phoneToUnban {
                Text(t(
                    "هل تريد إلغاء حظر الرقم \(phone.phoneNumber)؟",
                    "Remove ban for \(phone.phoneNumber)?"
                ))
            }
        }
        .task {
            isLoading = true
            await authVM.fetchBannedPhones()
            isLoading = false
        }
    }

    // MARK: - Stats Bar
    private var statsBar: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon("phone.down.fill", color: DS.Color.error, size: 36, iconSize: 16)

            Text(t(
                "\(authVM.bannedPhones.count) رقم محظور",
                "\(authVM.bannedPhones.count) banned"
            ))
            .font(DS.Font.calloutBold)
            .foregroundColor(DS.Color.textPrimary)

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }

    // MARK: - Search
    private var searchBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DS.Color.textTertiary)
                .font(DS.Font.subheadline)

            TextField(t("بحث عن رقم...", "Search number..."), text: $searchText)
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.textSecondary.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.sm)
    }

    // MARK: - List
    private var phonesList: some View {
        ScrollView {
            AdaptiveLazyStack(spacing: DS.Spacing.md, landscapeMinimum: 330) {
                ForEach(filteredPhones) { banned in
                    bannedPhoneCard(banned)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xxxl)
        }
    }

    // MARK: - Card
    private func bannedPhoneCard(_ banned: BannedPhone) -> some View {
        DSCard(padding: DS.Spacing.lg) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack {
                    DSIcon("phone.down.fill", color: DS.Color.error, size: 38, iconSize: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatPhoneDisplay(banned.phoneNumber))
                            .font(DS.Font.bodyBold)
                            .foregroundColor(DS.Color.textPrimary)

                        if let reason = banned.reason, !reason.isEmpty {
                            Text(reason)
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                    }

                    Spacer()

                    // زر إلغاء الحظر — للمالك فقط (المدير يتصفّح بدون تعديل)
                    if authVM.canManageBannedPhones {
                        Button(action: {
                            phoneToUnban = banned
                        }) {
                            Text(t("إلغاء", "Unban"))
                                .font(DS.Font.caption1)
                                .fontWeight(.semibold)
                                .foregroundStyle(DS.Color.textOnPrimary)
                                .padding(.horizontal, DS.Spacing.md)
                                .padding(.vertical, DS.Spacing.xs)
                                .background(DS.Color.error)
                                .clipShape(Capsule())
                        }
                    }
                }

                // تاريخ الحظر
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "calendar")
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                    Text(formatDate(banned.createdAt))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        DSEmptyState(
            icon: "checkmark.shield.fill",
            title: t("لا توجد أرقام محظورة", "No Banned Numbers"),
            subtitle: t("يمكنك حظر أرقام هواتف من زر + في الأعلى",
                        "You can ban phone numbers using the + button above"),
            tint: DS.Color.success
        )
    }

    // MARK: - Helpers
    private func formatPhoneDisplay(_ phone: String) -> String {
        if phone.count == 8 {
            return "+965 \(phone)"
        }
        return KuwaitPhone.display(phone)
    }

    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else {
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            guard let d = fallback.date(from: isoString) else { return isoString }
            return dateDisplay(d)
        }
        return dateDisplay(date)
    }

    private func dateDisplay(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}

// MARK: - Add Ban Sheet

struct AddBanSheet: View {
    @ObservedObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    @State private var phoneNumber = ""
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var reason = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// الرقم المحلي (أرقام فقط) كما أُدخل.
    private var localDigits: String {
        KuwaitPhone.normalizeDigits(phoneNumber).filter(\.isNumber)
    }

    /// الرقم النهائي بصيغة E.164 (كود الدولة + المحلي) للحظر.
    private var cleanPhone: String {
        KuwaitPhone.normalizedForStorage(country: selectedPhoneCountry, rawLocalDigits: phoneNumber)
            ?? "\(selectedPhoneCountry.dialingCode)\(localDigits)"
    }

    private var isValid: Bool {
        localDigits.count >= 6
    }

    /// أي إدخال (رقم، سبب، أو دولة غير الافتراضية) → «إلغاء» يسأل قبل التجاهل (توصية أبل)
    private var hasInput: Bool {
        !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedPhoneCountry != KuwaitPhone.defaultCountry
    }

    var body: some View {
        // نفس هيكل مربّعات الإضافة (طلب المالك): رأس أحمر للحظر، قسم البيانات،
        // و«حظر الرقم» كحلي يمين / «إلغاء» رمادي يسار
        DSComposer(
            title: t("حظر رقم هاتف", "Ban Phone Number"),
            subtitle: t("يُمنع الرقم من استخدام التطبيق", "The number is blocked from using the app"),
            icon: "phone.down.fill",
            tint: DS.Color.error,
            actionTitle: t("حظر الرقم", "Ban Number"),
            actionIcon: "phone.down.fill",
            canSubmit: isValid,
            isBusy: isLoading,
            hasUnsavedChanges: hasInput,
            onSubmit: { Task { await banAction() } },
            onCancel: { dismiss() }
        ) {
            DSComposerSection(title: t("بيانات الحظر", "Ban details"), icon: "phone.down.fill",
                              tint: DS.Color.error, index: 0) {
                // حقل الرقم
                phoneRow

                // سبب الحظر
                DSComposerField(icon: "text.bubble.fill",
                                label: t("السبب (اختياري)", "Reason (optional)"),
                                placeholder: t("سبب الحظر...", "Ban reason..."),
                                text: $reason,
                                tint: DS.Color.error)
            }

            // رسالة خطأ
            if let error = errorMessage {
                errorRow(error)
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// صف الرقم بنفس شكل حقول المربّعات: أيقونة + العنوان فوق + حقل الهاتف الموحّد
    private var phoneRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "phone.fill", tint: DS.Color.error)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(t("رقم الهاتف", "Phone Number"))
                    .font(DS.Font.plex(12, weight: .heavy))
                    .foregroundColor(DS.Color.fieldLabel)
                DSPhoneField(
                    country: $selectedPhoneCountry,
                    digits: $phoneNumber,
                    placeholder: t("مثال: 99123456", "e.g. 99123456"),
                    compact: true,
                    bordered: false
                )
            }
        }
        .dsRowBox()
    }

    private func errorRow(_ error: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(error)
                .font(DS.Font.plex(12.5, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(DS.Color.error)
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.error.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private func banAction() async {
        errorMessage = nil
        isLoading = true

        let success = await authVM.banPhone(
            cleanPhone,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reason.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if success {
            dismiss()
        } else {
            errorMessage = t(
                "فشل حظر الرقم. قد يكون محظوراً بالفعل.",
                "Failed to ban number. It may already be banned."
            )
        }
        isLoading = false
    }
}
