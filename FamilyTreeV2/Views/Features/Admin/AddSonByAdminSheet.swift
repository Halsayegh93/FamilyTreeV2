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
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var phoneNumber: String = ""
    @State private var hasBirthDate: Bool = false
    @State private var birthDate: Date = Date()
    @State private var isDeceased: Bool = false
    @State private var hasDeathDate: Bool = false
    @State private var deathDate: Date = Date()

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
                DSDecorativeBackground()

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
                    .disabled(firstName.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
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
                        .onChange(of: firstName) {
                            if firstName.count > 50 {
                                firstName = String(firstName.prefix(50))
                            }
                        }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)

                DSDivider()

                // Gender picker
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("person.2.fill", color: DS.Color.accent, size: iconSm, iconSize: iconFontSm)

                    Text(L10n.t("الجنس", "Gender"))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textPrimary)

                    Spacer()

                    Picker("", selection: $selectedGender) {
                        Text(L10n.t("ذكر", "Male")).tag("male")
                        Text(L10n.t("أنثى", "Female")).tag("female")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Phone Section
    private var phoneSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("رقم الهاتف", "Phone Number"),
                    icon: "phone.fill",
                    iconColor: DS.Color.success
                )

                HStack(spacing: DS.Spacing.sm) {
                    Menu {
                        ForEach(KuwaitPhone.supportedCountries) { country in
                            Button {
                                selectedPhoneCountry = country
                            } label: {
                                Text("\(country.flag) \(country.nameArabic) \(country.dialingCode)")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedPhoneCountry.flag)
                            Text(selectedPhoneCountry.dialingCode)
                                .font(DS.Font.caption1)
                            Image(systemName: "chevron.down")
                                .font(DS.Font.scaled(9, weight: .semibold))
                        }
                        .foregroundColor(DS.Color.textSecondary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(DS.Color.surfaceElevated.opacity(0.5))
                        .clipShape(Capsule())
                    }

                    TextField(L10n.t("رقم الهاتف (اختياري)", "Phone (optional)"), text: $phoneNumber)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.leading)
                        .font(DS.Font.callout)

                    DSIcon("phone.fill", color: DS.Color.success, size: iconSm, iconSize: iconFontSm)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
                .environment(\.layoutDirection, .leftToRight)
                .onChange(of: phoneNumber) { _, newValue in
                    phoneNumber = KuwaitPhone.userTypedDigits(newValue, maxDigits: selectedPhoneCountry.maxDigits)
                }
                .onChange(of: selectedPhoneCountry) { _, newCountry in
                    phoneNumber = KuwaitPhone.userTypedDigits(phoneNumber, maxDigits: newCountry.maxDigits)
                }
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
                    HStack(spacing: DS.Spacing.sm) {
                        DSIcon("calendar.badge.clock", color: DS.Color.info, size: iconSm, iconSize: iconFontSm)

                        DatePicker("", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "en_US"))

                        Spacer()

                        Text(L10n.t("اختر التاريخ", "Pick Date"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
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
                        HStack(spacing: DS.Spacing.sm) {
                            DSIcon("calendar.badge.exclamationmark", color: DS.Color.error, size: iconSm, iconSize: iconFontSm)

                            DatePicker("", selection: $deathDate, in: ...Date(), displayedComponents: .date)
                                .labelsHidden()
                                .environment(\.locale, Locale(identifier: "en_US"))

                            Spacer()

                            Text(L10n.t("تاريخ الوفاة", "Death Date"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
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

        if let child = editingChild {
            // Edit mode: update existing child
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
            }
        }
    }
}
