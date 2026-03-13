import SwiftUI

struct AdminBannedPhonesView: View {
    @EnvironmentObject var authVM: AuthViewModel

    private var isArabic: Bool { LanguageManager.shared.selectedLanguage == "ar" }
    private func t(_ ar: String, _ en: String) -> String { isArabic ? ar : en }

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
            DSDecorativeBackground()

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
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(DS.Font.title3)
                        .foregroundStyle(DS.Color.primary)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddBanSheet(authVM: authVM)
        }
        .alert(
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
                .foregroundStyle(Color(UIColor.label))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.sm)
    }

    // MARK: - List
    private var phonesList: some View {
        ScrollView {
            LazyVStack(spacing: DS.Spacing.md) {
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

                    Button(action: {
                        phoneToUnban = banned
                    }) {
                        Text(t("إلغاء", "Unban"))
                            .font(DS.Font.caption1)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(DS.Color.error)
                            .clipShape(Capsule())
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
        VStack(spacing: DS.Spacing.xl) {
            Spacer()
            DSIcon("checkmark.shield.fill", color: DS.Color.success, size: 70, iconSize: 30)
            Text(t("لا توجد أرقام محظورة", "No Banned Numbers"))
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.textPrimary)
            Text(t(
                "يمكنك حظر أرقام هواتف من زر + في الأعلى",
                "You can ban phone numbers using the + button above"
            ))
            .font(DS.Font.subheadline)
            .foregroundColor(DS.Color.textSecondary)
            .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(DS.Spacing.xxl)
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
        df.locale = Locale(identifier: isArabic ? "ar" : "en")
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}

// MARK: - Add Ban Sheet

struct AddBanSheet: View {
    @ObservedObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    private var isArabic: Bool { LanguageManager.shared.selectedLanguage == "ar" }
    private func t(_ ar: String, _ en: String) -> String { isArabic ? ar : en }

    @State private var phoneNumber = ""
    @State private var reason = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var cleanPhone: String {
        KuwaitPhone.normalizeDigits(phoneNumber).filter(\.isNumber)
    }

    private var isValid: Bool {
        cleanPhone.count >= 6
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: DS.Spacing.xxl) {
                    // أيقونة
                    DSIcon("phone.down.fill", color: DS.Color.error, size: DS.Icon.size, iconSize: 22)
                        .padding(.top, DS.Spacing.xxl)

                    Text(t("حظر رقم هاتف", "Ban Phone Number"))
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textPrimary)

                    VStack(spacing: DS.Spacing.lg) {
                        // حقل الرقم
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(t("رقم الهاتف", "Phone Number"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)

                            TextField(t("مثال: 99123456", "e.g. 99123456"), text: $phoneNumber)
                                .keyboardType(.numberPad)
                                .font(DS.Font.scaled(18, weight: .bold))
                                .foregroundStyle(Color(UIColor.label))
                                .multilineTextAlignment(.leading)
                                .padding(DS.Spacing.md)
                                .background(DS.Color.surface)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                )
                                .environment(\.layoutDirection, .leftToRight)
                        }

                        // سبب الحظر
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(t("السبب (اختياري)", "Reason (optional)"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)

                            TextField(t("سبب الحظر...", "Ban reason..."), text: $reason)
                                .font(DS.Font.subheadline)
                                .foregroundStyle(Color(UIColor.label))
                                .padding(DS.Spacing.md)
                                .background(DS.Color.surface)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    // رسالة خطأ
                    if let error = errorMessage {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(DS.Color.error)
                            Text(error)
                                .font(DS.Font.footnote)
                                .foregroundColor(DS.Color.error)
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                    }

                    // زر الحظر
                    DSPrimaryButton(
                        t("حظر الرقم", "Ban Number"),
                        icon: "phone.down.fill",
                        isLoading: isLoading,
                        useGradient: isValid,
                        color: isValid ? DS.Color.error : .gray
                    ) {
                        Task { await banAction() }
                    }
                    .disabled(!isValid || isLoading)
                    .padding(.horizontal, DS.Spacing.lg)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(t("إلغاء", "Cancel")) { dismiss() }
                        .foregroundStyle(DS.Color.primary)
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
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
