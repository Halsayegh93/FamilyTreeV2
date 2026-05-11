import SwiftUI

/// شاشة طلب تعديل الشجرة — تستقبل عضو + إجراء محددين مسبقاً.
/// تدعم: إضافة ابن / تعديل اسم / تعديل رقم / تسجيل وفاة / حذف.
struct TreeEditRequestView: View {
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isDetailsFocused: Bool
    @FocusState private var isPrimaryFieldFocused: Bool

    let member: FamilyMember
    let action: TreeEditAction

    @State private var primaryText: String = ""
    @State private var notes: String = ""
    @State private var deathDate: Date = Date()
    @State private var phoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var localPhoneDigits: String = ""
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String? = nil
    @State private var showCountrySheet = false

    private var actionColor: Color {
        switch action {
        case .add: return DS.Color.success
        case .editName: return DS.Color.info
        case .editPhone: return DS.Color.primary
        case .deceased: return DS.Color.textTertiary
        case .delete: return DS.Color.error
        }
    }

    private var screenTitle: String {
        switch action {
        case .add: return L10n.t("طلب إضافة ابن", "Add Son Request")
        case .editName: return L10n.t("طلب تعديل اسم", "Edit Name Request")
        case .editPhone: return L10n.t("طلب تعديل رقم", "Edit Phone Request")
        case .deceased: return L10n.t("طلب تسجيل وفاة", "Mark Deceased Request")
        case .delete: return L10n.t("طلب حذف", "Delete Request")
        }
    }

    private var canSubmit: Bool {
        guard !adminRequestVM.isLoading else { return false }
        switch action {
        case .add, .editName:
            return !primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .editPhone:
            return KuwaitPhone.normalizedForStorage(country: phoneCountry, rawLocalDigits: localPhoneDigits) != nil
        case .deceased:
            return true
        case .delete:
            return !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xxl) {
                        memberCard
                        primaryFieldSection
                        notesSection
                        submitButton
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xxxxl)
                }
            }
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.error)
                }
            }
            .alert(L10n.t("تم الإرسال", "Request Sent"), isPresented: $showSuccessAlert) {
                Button(L10n.t("حسناً", "OK")) { dismiss() }
            } message: {
                Text(L10n.t(
                    "تم إرسال طلبك للإدارة وسيتم مراجعته قريباً.",
                    "Your request has been sent to admin for review."
                ))
            }
            .alert(L10n.t("تعذر الإرسال", "Failed to Send"), isPresented: $showErrorAlert) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? L10n.t(
                    "تعذر إرسال الطلب. حاول مرة أخرى.",
                    "Failed to send request. Please try again."
                ))
            }
            .sheet(isPresented: $showCountrySheet) {
                countryPickerSheet
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .onAppear { prefillFromMember() }
        }
    }

    // MARK: - Member Card

    private var memberCard: some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(actionColor.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: action.iconName)
                    .font(DS.Font.scaled(20, weight: .semibold))
                    .foregroundColor(actionColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(action.arabicLabel, action.englishLabel))
                    .font(DS.Font.caption1)
                    .fontWeight(.semibold)
                    .foregroundColor(actionColor)
                Text(member.fullName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(actionColor.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Primary Field

    @ViewBuilder
    private var primaryFieldSection: some View {
        switch action {
        case .add:
            textInputSection(
                label: L10n.t("اسم الابن الجديد", "New Son Name"),
                placeholder: L10n.t("اكتب اسم الابن...", "Enter son's name..."),
                icon: "person.badge.plus",
                text: $primaryText
            )
        case .editName:
            textInputSection(
                label: L10n.t("الاسم الجديد", "New Name"),
                placeholder: L10n.t("اكتب الاسم الجديد...", "Enter new name..."),
                icon: "pencil",
                text: $primaryText
            )
        case .editPhone:
            phoneInputSection
        case .deceased:
            deceasedDateSection
        case .delete:
            EmptyView()
        }
    }

    private func textInputSection(label: String, placeholder: String, icon: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(label)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)

            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(14, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                    .frame(width: 24)

                TextField(placeholder, text: text)
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .focused($isPrimaryFieldFocused)

                if !text.wrappedValue.isEmpty {
                    Button { text.wrappedValue = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.Font.scaled(14, weight: .medium))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.md)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(
                        isPrimaryFieldFocused ? DS.Color.primary.opacity(0.4) : DS.Color.textTertiary.opacity(0.15),
                        lineWidth: isPrimaryFieldFocused ? 1.5 : 1
                    )
            )
        }
    }

    private var phoneInputSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(L10n.t("الرقم الجديد", "New Phone Number"))
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)

            HStack(spacing: DS.Spacing.sm) {
                Button { showCountrySheet = true } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(phoneCountry.flag)
                            .font(DS.Font.scaled(16))
                        Text(phoneCountry.dialingCode)
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(DS.Font.scaled(10, weight: .semibold))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(DSScaleButtonStyle())

                TextField(L10n.t("رقم الهاتف", "Phone number"), text: $localPhoneDigits)
                    .keyboardType(.numberPad)
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .focused($isPrimaryFieldFocused)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.lg)
                            .stroke(
                                isPrimaryFieldFocused ? DS.Color.primary.opacity(0.4) : DS.Color.textTertiary.opacity(0.15),
                                lineWidth: isPrimaryFieldFocused ? 1.5 : 1
                            )
                    )
            }
        }
    }

    private var countryPickerSheet: some View {
        NavigationStack {
            List(KuwaitPhone.supportedCountries) { country in
                Button {
                    phoneCountry = country
                    showCountrySheet = false
                } label: {
                    HStack(spacing: DS.Spacing.md) {
                        Text(country.flag).font(DS.Font.scaled(20))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t(country.nameArabic, country.isoCode))
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.textPrimary)
                            Text(country.dialingCode)
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textTertiary)
                        }
                        Spacer()
                        if phoneCountry == country {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(DS.Color.primary)
                        }
                    }
                }
            }
            .navigationTitle(L10n.t("اختر الدولة", "Select Country"))
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }

    private var deceasedDateSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(L10n.t("تاريخ الوفاة", "Date of Death"))
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)

            DatePicker(
                L10n.t("تاريخ الوفاة", "Date of Death"),
                selection: $deathDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
            )
        }
    }

    // MARK: - Notes / Reason Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(notesLabel)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes)
                    .frame(minHeight: action == .delete ? 100 : 80)
                    .focused($isDetailsFocused)
                    .scrollContentBackground(.hidden)
                    .font(DS.Font.body)

                if notes.isEmpty {
                    Text(notesPlaceholder)
                        .font(DS.Font.body)
                        .foregroundColor(DS.Color.textTertiary)
                        .padding(.top, DS.Spacing.sm)
                        .padding(.leading, DS.Spacing.xs)
                        .allowsHitTesting(false)
                }
            }
            .padding(DS.Spacing.md)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(
                        isDetailsFocused ? DS.Color.primary.opacity(0.4) : DS.Color.textTertiary.opacity(0.15),
                        lineWidth: isDetailsFocused ? 1.5 : 1
                    )
            )
        }
    }

    private var notesLabel: String {
        action == .delete
            ? L10n.t("سبب الحذف (مطلوب)", "Removal Reason (required)")
            : L10n.t("ملاحظات إضافية (اختياري)", "Additional Notes (optional)")
    }

    private var notesPlaceholder: String {
        action == .delete
            ? L10n.t("اكتب سبب طلب الحذف...", "Write the removal reason...")
            : L10n.t("أي ملاحظات إضافية...", "Any additional notes...")
    }

    // MARK: - Submit

    private var submitButton: some View {
        DSPrimaryButton(
            L10n.t("إرسال الطلب", "Submit Request"),
            icon: "paperplane.fill",
            isLoading: adminRequestVM.isLoading,
            useGradient: canSubmit,
            color: canSubmit ? actionColor : .gray
        ) {
            submit()
        }
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1.0 : DS.Opacity.disabled)
    }

    // MARK: - Helpers

    private func prefillFromMember() {
        switch action {
        case .editName:
            primaryText = member.fullName
        case .editPhone:
            if let phone = member.phoneNumber, !phone.isEmpty {
                let detected = KuwaitPhone.detectCountryAndLocal(phone)
                phoneCountry = detected.country
                localPhoneDigits = detected.localDigits
            }
        default:
            break
        }
    }

    private func submit() {
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: TreeEditPayload

        switch action {
        case .add:
            payload = TreeEditPayload.make(
                action: .add,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                parentMemberId: member.id.uuidString,
                parentMemberName: member.fullName,
                newMemberName: primaryText.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: cleanNotes.isEmpty ? nil : cleanNotes
            )

        case .editName:
            payload = TreeEditPayload.make(
                action: .editName,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                newName: primaryText.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: cleanNotes.isEmpty ? nil : cleanNotes
            )

        case .editPhone:
            guard let normalized = KuwaitPhone.normalizedForStorage(country: phoneCountry, rawLocalDigits: localPhoneDigits) else {
                errorMessage = L10n.t("رقم الهاتف غير صالح", "Invalid phone number")
                showErrorAlert = true
                return
            }
            payload = TreeEditPayload.make(
                action: .editPhone,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                newPhone: normalized,
                notes: cleanNotes.isEmpty ? nil : cleanNotes
            )

        case .deceased:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            payload = TreeEditPayload.make(
                action: .deceased,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                deathDate: formatter.string(from: deathDate),
                notes: cleanNotes.isEmpty ? nil : cleanNotes
            )

        case .delete:
            payload = TreeEditPayload.make(
                action: .delete,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                reason: cleanNotes
            )
        }

        Task {
            let sent = await adminRequestVM.submitTreeEditRequest(payload: payload)
            if sent {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showSuccessAlert = true
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                showErrorAlert = true
            }
        }
    }
}
