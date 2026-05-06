import SwiftUI

struct AddSonByAdminSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss

    let parent: FamilyMember
    let editingChild: FamilyMember?

    private var isEditMode: Bool { editingChild != nil }

    @State private var firstName: String = ""
    @State private var selectedGender: String = "male"
    @AppStorage("lastAuthDialingCode") private var lastAuthDialingCode: String = ""
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var phoneNumber: String = ""
    @State private var hasBirthDate: Bool = false
    @State private var birthDate: Date = Date()
    @State private var isDeceased: Bool = false
    @State private var hasDeathDate: Bool = false
    @State private var deathDate: Date = Date()
    @State private var isSaving = false

    init(parent: FamilyMember, editingChild: FamilyMember? = nil) {
        self.parent = parent
        self.editingChild = editingChild

        if let child = editingChild {
            self._firstName = State(initialValue: child.firstName)
            self._selectedGender = State(initialValue: child.gender ?? "male")

            let detectedPhone = KuwaitPhone.detectCountryAndLocal(child.phoneNumber)
            self._selectedPhoneCountry = State(initialValue: detectedPhone.country)
            self._phoneNumber = State(initialValue: detectedPhone.localDigits)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let bStr = child.birthDate, !bStr.isEmpty, let date = formatter.date(from: bStr) {
                self._hasBirthDate = State(initialValue: true)
                self._birthDate = State(initialValue: date)
            }

            let deceased = child.isDeceased ?? false
            self._isDeceased = State(initialValue: deceased)
            if deceased, let dStr = child.deathDate, !dStr.isEmpty, let date = formatter.date(from: dStr) {
                self._hasDeathDate = State(initialValue: true)
                self._deathDate = State(initialValue: date)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.sm) {

                        // Parent info hint
                        HStack {
                            Text(isEditMode
                                 ? L10n.t("تعديل بيانات: \(editingChild?.firstName ?? "")", "Editing: \(editingChild?.firstName ?? "")")
                                 : L10n.t("إضافة ابن جديد للسيد: \(parent.fullName)", "Adding new child for: \(parent.fullName)"))
                                .font(DS.Font.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(DS.Color.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)

                        // Basic info section
                        basicInfoSection

                        // Phone section
                        if !isDeceased {
                            phoneSection
                        }

                        // Dates & status section
                        datesSection

                        // Admin note
                        if !isEditMode {
                            Text(L10n.t("بصفتك مديراً، ستتم إضافة العضو للشجرة فوراً.", "As admin, the member will be added to the tree immediately."))
                                .font(DS.Font.caption2)
                                .foregroundColor(DS.Color.textSecondary)
                                .padding(.horizontal, DS.Spacing.lg)
                        }
                    }
                    .padding(.bottom, DS.Spacing.xxxl)
                }
            }
            .navigationTitle(isEditMode ? L10n.t("تعديل الابن", "Edit Child") : L10n.t("إضافة ابن", "Add Child"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: saveAction) {
                        Text(isEditMode ? L10n.t("حفظ", "Save") : L10n.t("إضافة", "Add"))
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.primary)
                    }
                    .disabled(firstName.isEmpty || isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear {
            // في وضع الإضافة: استخدم رمز الدولة من تسجيل الدخول
            if editingChild == nil, !lastAuthDialingCode.isEmpty {
                selectedPhoneCountry = KuwaitPhone.countryForDialingCode(lastAuthDialingCode)
            }
        }
    }

    // MARK: - Helpers
    private let iconSm: CGFloat = 30
    private let iconFontSm: CGFloat = 13

    // MARK: - Basic Info Section
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("بيانات الابن", "Child Info"),
                    icon: "person.badge.plus.fill",
                    iconColor: DS.Color.primary
                )

                // Name field
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("person.fill", color: DS.Color.primary, size: iconSm, iconSize: iconFontSm)

                    TextField(L10n.t("اسم الابن الأول", "Child's first name"), text: $firstName)
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .onChange(of: firstName) { _ in
                            if firstName.count > 50 {
                                firstName = String(firstName.prefix(50))
                            }
                        }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)

                DSDivider()

                // TODO: gender — re-enable when needed
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Phone Section — بدون رمز الدولة
    private var phoneSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("رقم الهاتف (اختياري)", "Phone Number (Optional)"),
                    icon: "phone.fill",
                    iconColor: DS.Color.success
                )

                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("phone.fill", color: DS.Color.success, size: iconSm, iconSize: iconFontSm)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("رقم الهاتف", "Phone Number"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                        PhoneNumberTextField(
                            text: $phoneNumber,
                            placeholder: L10n.t("اختياري", "Optional"),
                            font: .systemFont(ofSize: 15),
                            keyboardType: .phonePad,
                            maxLength: selectedPhoneCountry.maxDigits
                        )
                        .frame(height: 30)
                    }
                    Spacer()
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Dates & Status Section
    private var datesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("التواريخ والحالة", "Dates & Status"),
                    icon: "calendar",
                    iconColor: DS.Color.warning
                )

                // Birth date toggle
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("calendar", color: DS.Color.primary, size: iconSm, iconSize: iconFontSm)

                    Text(L10n.t("تاريخ الميلاد متوفر", "Birth date available"))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textPrimary)

                    Spacer()

                    Toggle("", isOn: $hasBirthDate)
                        .labelsHidden()
                        .tint(DS.Color.primary)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
                .animation(.default, value: hasBirthDate)

                if hasBirthDate {
                    DSDivider()
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        HStack(spacing: DS.Spacing.sm) {
                            DSIcon("calendar.badge.clock", color: DS.Color.info, size: iconSm, iconSize: iconFontSm)
                            Text(L10n.t("تاريخ الميلاد", "Birth Date"))
                                .font(DS.Font.callout)
                                .foregroundColor(DS.Color.textPrimary)
                            Spacer()
                        }
                        StableWheelDatePicker(selection: $birthDate, in: ...Date())
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                }

                DSDivider()

                // Deceased toggle
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("heart.text.square.fill", color: DS.Color.error, size: iconSm, iconSize: iconFontSm)

                    Text(L10n.t("إضافة كمتوفى", "Add as deceased"))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textPrimary)

                    Spacer()

                    Toggle("", isOn: $isDeceased)
                        .labelsHidden()
                        .tint(DS.Color.error)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
                .animation(.default, value: isDeceased)

                if isDeceased {
                    DSDivider()

                    HStack(spacing: DS.Spacing.sm) {
                        DSIcon("calendar.badge.minus", color: DS.Color.error, size: iconSm, iconSize: iconFontSm)

                        Text(L10n.t("تاريخ الوفاة متوفر", "Death date available"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textPrimary)

                        Spacer()

                        Toggle("", isOn: $hasDeathDate)
                            .labelsHidden()
                            .tint(DS.Color.error)
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                    .animation(.default, value: hasDeathDate)

                    if hasDeathDate {
                        DSDivider()
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            HStack(spacing: DS.Spacing.sm) {
                                DSIcon("calendar.badge.exclamationmark", color: DS.Color.error, size: iconSm, iconSize: iconFontSm)
                                Text(L10n.t("تاريخ الوفاة", "Death Date"))
                                    .font(DS.Font.callout)
                                    .foregroundColor(DS.Color.textPrimary)
                                Spacer()
                            }
                            StableWheelDatePicker(selection: $deathDate, in: ...Date())
                        }
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs)
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Save Action
    private func saveAction() {
        guard !isSaving else { return }
        isSaving = true
        // Capture values before dismiss
        let capturedFirstName = firstName
        let capturedPhone = KuwaitPhone.normalizedForStorage(
            country: selectedPhoneCountry,
            rawLocalDigits: phoneNumber
        ) ?? ""
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US")
        let capturedBirthDate = hasBirthDate ? formatter.string(from: birthDate) : nil
        let capturedIsDeceased = isDeceased
        let capturedDeathDate = (isDeceased && hasDeathDate) ? formatter.string(from: deathDate) : nil
        let capturedGender = selectedGender
        let vm = memberVM

        // Dismiss immediately for snappy UX
        dismiss()

        let adminName = authVM.currentUser?.firstName ?? "مدير"
        let parentName = parent.fullName

        if let child = editingChild {
            // Edit mode: detect what actually changed
            let origPhone = KuwaitPhone.normalizedForStorage(
                country: KuwaitPhone.detectCountryAndLocal(child.phoneNumber).country,
                rawLocalDigits: KuwaitPhone.detectCountryAndLocal(child.phoneNumber).localDigits
            ) ?? ""
            let nameChanged = capturedFirstName != child.firstName
            let phoneChanged = capturedPhone != origPhone
            let birthChanged = capturedBirthDate != child.birthDate
            let deceasedChanged = capturedIsDeceased != (child.isDeceased ?? false)
            let deathChanged = capturedDeathDate != child.deathDate
            let genderChanged = capturedGender != (child.gender ?? "male")

            let somethingChanged = nameChanged || phoneChanged || birthChanged || deceasedChanged || deathChanged || genderChanged

            guard somethingChanged else { return }

            Task {
                await vm.updateChildData(
                    member: child,
                    firstName: capturedFirstName,
                    phoneNumber: capturedPhone,
                    birthDate: capturedBirthDate,
                    isDeceased: capturedIsDeceased,
                    deathDate: capturedDeathDate,
                    gender: capturedGender
                )

                // بناء قائمة الحقول المتغيرة فقط
                var changedFields: [String] = []
                if nameChanged { changedFields.append(L10n.t("الاسم", "Name")) }
                if phoneChanged { changedFields.append(L10n.t("الهاتف", "Phone")) }
                if birthChanged { changedFields.append(L10n.t("تاريخ الميلاد", "Birth date")) }
                if deceasedChanged || deathChanged { changedFields.append(L10n.t("حالة الوفاة", "Deceased status")) }
                if genderChanged { changedFields.append(L10n.t("الجنس", "Gender")) }

                let fieldsList = changedFields.joined(separator: "، ")
                await vm.notificationVM?.notifyAdminsWithPush(
                    title: L10n.t("تعديل بيانات ابن", "Child Data Updated"),
                    body: L10n.t(
                        "تم تعديل بيانات: \(capturedFirstName) ابن \(parentName)",
                        "Updated: \(capturedFirstName) son of \(parentName)"
                    ),
                    kind: "admin_edit"
                )
                Log.info("[Admin] \(adminName) عدّل بيانات الابن \(capturedFirstName): \(fieldsList)")
            }
        } else {
            // Add mode: create new child
            let capturedParentId = parent.id
            Task {
                _ = await vm.addChild(
                    firstNameOnly: capturedFirstName,
                    phoneNumber: capturedPhone,
                    birthDate: capturedBirthDate,
                    fatherId: capturedParentId,
                    isDeceased: capturedIsDeceased,
                    deathDate: capturedDeathDate,
                    gender: capturedGender,
                    silent: true
                )
                // إشعار: أي مدير أضاف الابن
                await vm.notificationVM?.notifyAdminsWithPush(
                    title: L10n.t("إضافة ابن جديد", "New Child Added"),
                    body: L10n.t(
                        "تم إضافة ابن: \(capturedFirstName) لـ: \(parentName)",
                        "Child added: \(capturedFirstName) to: \(parentName)"
                    ),
                    kind: "admin_edit_child_add"
                )
                Log.info("[Admin] \(adminName) أضاف الابن \(capturedFirstName) لـ \(parentName)")
            }
        }
    }
}
