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

    // MARK: - تغييرات لم تُحفظ (توصية أبل)

    /// الحقول كما تُحفظ — تُقارن بما فُتح عليه المربّع (فارغ للإضافة، بيانات الابن للتعديل)
    private struct Draft: Equatable {
        var name: String = ""
        var gender: String = "male"
        /// الدولة تُحسب مع الرقم فقط (رقم فارغ = لا رقم) — رمز الدولة المعبّأ تلقائياً ليس تغييراً
        var phone: String = ""
        var birth: String? = nil
        var isDeceased: Bool = false
        var death: String? = nil
    }

    private let startDraft: Draft

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var currentDraft: Draft {
        Draft(
            name: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            gender: selectedGender,
            phone: phoneNumber.isEmpty ? "" : "\(selectedPhoneCountry.id)|\(phoneNumber)",
            birth: hasBirthDate ? Self.dayFormatter.string(from: birthDate) : nil,
            isDeceased: isDeceased,
            death: (isDeceased && hasDeathDate) ? Self.dayFormatter.string(from: deathDate) : nil
        )
    }

    /// أي حقل يختلف عمّا فُتح عليه المربّع — «إلغاء» يسأل قبل التجاهل
    private var hasUnsavedChanges: Bool { currentDraft != startDraft }

    /// نقطة البداية: فارغة للإضافة، وبيانات الابن (بنفس قراءة init) للتعديل
    private static func makeStartDraft(_ child: FamilyMember?) -> Draft {
        guard let child else { return Draft() }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        func day(_ raw: String?) -> String? {
            guard let raw, !raw.isEmpty, let date = parser.date(from: raw) else { return nil }
            return dayFormatter.string(from: date)
        }
        let phone = KuwaitPhone.detectCountryAndLocal(child.phoneNumber)
        let deceased = child.isDeceased ?? false
        return Draft(
            name: child.firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            gender: child.gender ?? "male",
            phone: phone.localDigits.isEmpty ? "" : "\(phone.country.id)|\(phone.localDigits)",
            birth: day(child.birthDate),
            isDeceased: deceased,
            death: deceased ? day(child.deathDate) : nil
        )
    }

    init(parent: FamilyMember, editingChild: FamilyMember? = nil) {
        self.parent = parent
        self.editingChild = editingChild
        self.startDraft = Self.makeStartDraft(editingChild)

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
        // نفس هيكل مربّعات الإضافة وحركتها (طلب المالك)
        DSComposer(
            title: isEditMode ? L10n.t("تعديل الابن", "Edit Child") : L10n.t("إضافة ابن", "Add Child"),
            subtitle: isEditMode ? L10n.t("عدّل بياناته في الشجرة", "Update the child's details")
                                 : L10n.t("يُضاف للشجرة فوراً", "Added to the tree right away"),
            icon: isEditMode ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus",
            tint: DS.Color.actionNavy,
            actionTitle: isEditMode ? L10n.t("حفظ", "Save") : L10n.t("إضافة", "Add"),
            actionIcon: isEditMode ? "checkmark" : "plus",
            canSubmit: !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            isBusy: isSaving,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: saveAction,
            onCancel: { dismiss() }
        ) {
            contextSection.dsStaggerIn(0)
            basicsCard.dsStaggerIn(1)
            datesCard.dsStaggerIn(2)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .dsAlert(
            L10n.t("لا يوجد اتصال بالإنترنت", "No Internet Connection"),
            isPresented: $showOfflineAlert
        ) {
            Button(L10n.t("حسناً", "OK")) {}
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

    // MARK: - لمن الابن
    private var contextSection: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: isEditMode ? "pencil" : "person.badge.plus")
                .font(DS.Font.plex(13, weight: .bold))
                .foregroundColor(DS.Color.primary)
                .frame(width: 32, height: 32)
                .background(DS.Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)   // زخرفة — النص بجانبها يكفي

            VStack(alignment: .leading, spacing: 2) {
                Text(isEditMode
                     ? L10n.t("تعديل ابن", "Editing Child")
                     : L10n.t("إضافة ابن لـ", "Adding child to"))
                    .font(DS.Font.plex(11.5, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                Text(isEditMode ? (editingChild?.firstName ?? "") : parent.fullName)
                    .font(DS.Font.plex(14.5, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
    }

    // MARK: - البيانات الأساسية: الاسم، الجنس، الرقم
    private var basicsCard: some View {
        DSFormCard(L10n.t("البيانات الأساسية", "Basic Info"),
                   icon: "person.text.rectangle.fill", color: DS.Color.primary) {
            DSFieldBox(L10n.t("الاسم الأول", "First Name")) {
                TextField(L10n.t("اسم الابن الأول", "Child's first name"), text: $firstName)
                    .onChange(of: firstName) { _ in
                        if firstName.count > 50 { firstName = String(firstName.prefix(50)) }
                    }
            }

            DSGenderPicker(selection: $selectedGender)

            if !isDeceased {
                DSFieldBox(L10n.t("رقم الهاتف (اختياري)", "Phone (optional)")) {
                    DSPhoneField(
                        country: $selectedPhoneCountry,
                        digits: $phoneNumber,
                        placeholder: L10n.t("اختياري", "Optional"),
                        compact: true,
                        bordered: false
                    )
                }
            }
        }
    }

    // MARK: - التواريخ والحالة (طلب المالك)
    private var datesCard: some View {
        DSFormCard(L10n.t("التواريخ والحالة", "Dates & Status"),
                   icon: "calendar", color: DS.Color.warning) {
            DSLifeDatesBox(hasBirthDate: $hasBirthDate, birthDate: $birthDate,
                           isDeceased: $isDeceased,
                           hasDeathDate: $hasDeathDate, deathDate: $deathDate,
                           deceasedTitle: isEditMode ? L10n.t("متوفّى", "Deceased")
                                                     : L10n.t("يُسجَّل متوفّى", "Record as deceased"))
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
