import SwiftUI

// ════════════════════════════════════════════════════════════════════
// AddSonByAdminSheet — تصميم Form الموحَّد (2026-05-27)
// نفس واجهة AdminMemberDetailSheet الجديدة — Form أصلي من iOS.
// ════════════════════════════════════════════════════════════════════
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
    @State private var showOfflineAlert = false

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
            formatter.locale = Locale(identifier: "en_US_POSIX")
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
            Form {
                contextSection
                identitySection
                genderSection
                if !isDeceased {
                    phoneSection
                }
                datesSection
                if !isEditMode {
                    Section {
                        Label(
                            L10n.t(
                                "بصفتك مديراً، ستتم إضافة العضو للشجرة فوراً.",
                                "As admin, the member will be added to the tree immediately."
                            ),
                            systemImage: "info.circle.fill"
                        )
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.Color.background)
            .navigationTitle(isEditMode ? L10n.t("تعديل الابن", "Edit Child") : L10n.t("إضافة ابن", "Add Child"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: saveAction) {
                        if isSaving {
                            ProgressView().tint(DS.Color.primary)
                        } else {
                            Text(isEditMode ? L10n.t("حفظ", "Save") : L10n.t("إضافة", "Add"))
                                .font(DS.Font.callout)
                                .fontWeight(.bold)
                                .foregroundColor(DS.Color.primary)
                        }
                    }
                    .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .alert(
            L10n.t("لا يوجد اتصال بالإنترنت", "No Internet Connection"),
            isPresented: $showOfflineAlert
        ) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.t(
                "لا يمكن \(isEditMode ? "تعديل" : "إضافة") الابن بدون اتصال بالإنترنت. تأكّد من الاتصال ثم حاول مجدّداً.",
                "Cannot \(isEditMode ? "update" : "add") the child without an internet connection. Check your connection and try again."
            ))
        }
        .onAppear {
            if editingChild == nil, !lastAuthDialingCode.isEmpty {
                selectedPhoneCountry = KuwaitPhone.countryForDialingCode(lastAuthDialingCode)
            }
        }
    }

    // MARK: - Context Section (Parent info hint)
    private var contextSection: some View {
        Section {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: isEditMode ? "pencil.circle.fill" : "person.badge.plus.fill")
                    .font(DS.Font.scaled(15, weight: .semibold))
                    .foregroundColor(DS.Color.primary)
                    .frame(width: 28, height: 28)
                    .background(DS.Color.primary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(isEditMode
                         ? L10n.t("تعديل ابن", "Editing Child")
                         : L10n.t("إضافة ابن لـ:", "Adding child to:"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)

                    Text(isEditMode
                         ? (editingChild?.firstName ?? "")
                         : parent.fullName)
                        .font(DS.Font.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Identity Section
    private var identitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Label(L10n.t("الاسم الأول", "First Name"), systemImage: "person.fill")
                    .foregroundColor(DS.Color.textSecondary)
                    .font(DS.Font.caption1)
                TextField(L10n.t("اسم الابن الأول", "Child's first name"), text: $firstName)
                    .font(DS.Font.callout)
                    .onChange(of: firstName) { _ in
                        if firstName.count > 50 { firstName = String(firstName.prefix(50)) }
                    }
            }
            .padding(.vertical, 2)
        } header: {
            sectionHeader(L10n.t("الهوية", "Identity"), icon: "person.text.rectangle.fill", color: DS.Color.primary)
        }
    }

    // MARK: - Gender Section
    private var genderSection: some View {
        Section {
            Picker(L10n.t("الجنس", "Gender"), selection: $selectedGender) {
                Label(L10n.t("ذكر", "Male"), systemImage: "figure.stand").tag("male")
                Label(L10n.t("أنثى", "Female"), systemImage: "figure.stand.dress").tag("female")
            }
            .pickerStyle(.segmented)
            .padding(.vertical, DS.Spacing.xs)
        } header: {
            sectionHeader(L10n.t("الجنس", "Gender"), icon: "person.crop.circle", color: DS.Color.accent)
        }
    }

    // MARK: - Phone Section
    private var phoneSection: some View {
        Section {
            HStack(spacing: DS.Spacing.sm) {
                Menu {
                    Picker("", selection: $selectedPhoneCountry) {
                        ForEach(KuwaitPhone.supportedCountries) { country in
                            Text("\(country.flag) \(country.nameArabic) \(country.dialingCode)")
                                .tag(country)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedPhoneCountry.flag)
                        Text(selectedPhoneCountry.dialingCode)
                            .font(DS.Font.callout)
                            .fontWeight(.semibold)
                            .foregroundColor(DS.Color.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(DS.Font.scaled(10, weight: .bold))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 6)
                    .background(DS.Color.surfaceElevated)
                    .clipShape(Capsule())
                }

                TextField(L10n.t("اختياري", "Optional"), text: $phoneNumber)
                    .font(DS.Font.callout)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .multilineTextAlignment(.trailing)
                    .environment(\.layoutDirection, .leftToRight)
                    .onChange(of: phoneNumber) { newValue in
                        phoneNumber = KuwaitPhone.userTypedDigits(newValue, maxDigits: selectedPhoneCountry.maxDigits)
                    }
                    .onChange(of: selectedPhoneCountry) { newCountry in
                        phoneNumber = KuwaitPhone.userTypedDigits(phoneNumber, maxDigits: newCountry.maxDigits)
                    }

                if !phoneNumber.isEmpty {
                    Button {
                        phoneNumber = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.Font.scaled(16))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            sectionHeader(L10n.t("رقم الهاتف (اختياري)", "Phone (Optional)"), icon: "phone.fill", color: DS.Color.secondary)
        }
    }

    // MARK: - Dates Section
    private var datesSection: some View {
        Section {
            Toggle(isOn: $hasBirthDate.animation(DS.Anim.snappy)) {
                Label(L10n.t("تاريخ الميلاد متوفر", "Birth date available"), systemImage: "calendar")
                    .foregroundColor(DS.Color.textPrimary)
            }
            .tint(DS.Color.primary)

            if hasBirthDate {
                DatePicker(
                    selection: $birthDate,
                    in: ...Date(),
                    displayedComponents: .date
                ) {
                    Label(L10n.t("تاريخ الميلاد", "Birth Date"), systemImage: "calendar.badge.clock")
                        .foregroundColor(DS.Color.textPrimary)
                }
                .environment(\.locale, Locale(identifier: L10n.isArabic ? "ar" : "en_US"))
            }

            Toggle(isOn: $isDeceased.animation(DS.Anim.snappy)) {
                Label(L10n.t("إضافة كمتوفى", "Add as deceased"), systemImage: "heart.text.square.fill")
                    .foregroundColor(DS.Color.textPrimary)
            }
            .tint(DS.Color.neonPink)

            if isDeceased {
                Toggle(isOn: $hasDeathDate.animation(DS.Anim.snappy)) {
                    Label(L10n.t("تاريخ الوفاة متوفر", "Death date available"), systemImage: "calendar.badge.minus")
                        .foregroundColor(DS.Color.textPrimary)
                }
                .tint(DS.Color.neonPink)

                if hasDeathDate {
                    DatePicker(
                        selection: $deathDate,
                        in: ...Date(),
                        displayedComponents: .date
                    ) {
                        Label(L10n.t("تاريخ الوفاة", "Death Date"), systemImage: "calendar.badge.exclamationmark")
                            .foregroundColor(DS.Color.textPrimary)
                    }
                    .environment(\.locale, Locale(identifier: L10n.isArabic ? "ar" : "en_US"))
                }
            }
        } header: {
            sectionHeader(L10n.t("التواريخ والحالة", "Dates & Status"), icon: "calendar", color: DS.Color.secondary)
        }
    }

    // MARK: - Section Header Helper
    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(DS.Font.caption1)
                .fontWeight(.bold)
                .foregroundColor(DS.Color.textSecondary)
                .textCase(nil)
        }
    }

    // MARK: - Save Action (unchanged logic)
    private func saveAction() {
        guard !isSaving else { return }
        guard NetworkMonitor.shared.isConnected else {
            showOfflineAlert = true
            return
        }
        isSaving = true
        let capturedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
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

        dismiss()

        let adminName = authVM.currentUser?.firstName ?? "مدير"
        let parentName = parent.fullName

        if let child = editingChild {
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
