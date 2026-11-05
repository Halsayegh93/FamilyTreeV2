import SwiftUI
import PhotosUI
import UIKit

/// فحص محلي قبل الحفظ — تنبيه يقدر العضو يتجاوزه. التطابق التام يرفضه السيرفر (`child_duplicate`) فلا يُكرَّر هنا
enum AddChildChecks {
    /// أقل فرق سنوات بين ميلاد الأب وابنه قبل التنبيه — من السيرفر متى أُضيف مفتاحه (قاعدة الإعدادات من السيرفر)
    static let minFatherGapKey = "child_father_min_gap_years"
    static var minFatherGapYears: Int { AppConfigValues.shared.int(minFatherGapKey, default: 12) }

    /// نفس `child_name_key` على السيرفر: بلا مسافات وتشكيل وتطويل، والهمزات والتاء المربوطة والألف المقصورة موحّدة
    static func serverNameKey(_ name: String) -> String {
        let folded: [Character: Character] = ["أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ة": "ه", "ى": "ي"]
        let kept = name.lowercased().unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !(0x064B...0x0652).contains(scalar.value)
                && scalar.value != 0x0640
        }
        return String(String(kept).map { folded[$0] ?? $0 })
    }

    /// ابن مسجّل اسمه قريب من المكتوب (لا مطابق تماماً) — الأول فقط
    static func nearSon(name: String, among sons: [FamilyMember]) -> FamilyMember? {
        let typed = NameMatcher.tokens(name).joined(separator: " ")
        let typedKey = serverNameKey(name)
        guard !typed.isEmpty else { return nil }
        return sons.first { son in
            guard serverNameKey(son.firstName) != typedKey else { return false }
            let other = NameMatcher.tokens(son.firstName).joined(separator: " ")
            return other == typed || NameMatcher.isTypo(typed, other)
        }
    }

    /// ميلاد الابن قبل مرور الحدّ على ميلاد الأب (أو قبل ميلاده) — سنة الأب الهجرية المكتوبة كميلادية لا تُقارن
    static func isTooCloseToFather(childBirth: Date, fatherBirth raw: String?) -> Bool {
        guard let father = NameMatcher.linkBirth(raw) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard calendar.component(.year, from: father) >= DeceasedMemorial.minGregorianYear,
              let earliest = calendar.date(byAdding: .year, value: minFatherGapYears, to: father) else { return false }
        return childBirth < earliest
    }
}

struct AddChildSheet: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    let member: FamilyMember

    @State private var firstName: String = ""
    @AppStorage("lastAuthDialingCode") private var lastAuthDialingCode: String = ""
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var phoneNumber: String = ""
    @State private var birthDate: Date = Date()
    /// هل حدّد المستخدم تاريخ ميلاد فعلاً؟ — نتجنّب كتابة «اليوم» المفبرك لمن لم يُحدَّد له.
    @State private var birthDateProvided: Bool = false
    @State private var selectedGender: String = "male"
    @State private var isDeceased: Bool = false
    @State private var deathDate: Date = Date()
    @State private var selectedUIImage: UIImage? = nil
    @State private var showSuccessAlert = false
    /// ابن أضافه عضو (غير الإدارة) — يُحفظ معلّقاً ويُرسل للإدارة للموافقة (ج-١)
    @State private var sentForApproval = false
    /// حُفظ الابن لكن طلبه لم يصل للإدارة — رسالة صادقة بدل «تمت الإضافة»
    @State private var approvalRequestWarning: String? = nil
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    /// تنبيهات الفحص المحلي — الحفظ بعد «متابعة»
    @State private var localWarnings: [String] = []
    @State private var showLocalWarnings = false

    var body: some View {
        // نفس هيكل مربّعات الإضافة وحركتها (طلب المالك)
        DSComposer(
            title: L10n.t("إضافة فرد", "Add Member"),
            subtitle: L10n.t("ابن أو بنت لعائلتك", "A son or daughter to your family"),
            icon: "person.crop.circle.badge.plus",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("إضافة", "Add"),
            actionIcon: "plus",
            canSubmit: !(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || memberVM.isLoading || isSubmitting),
            isBusy: memberVM.isLoading || isSubmitting,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: saveChild,
            onCancel: { dismiss() }
        ) {
            // الصورة للذكر فقط — الأنثى بلا خيار صورة
            if selectedGender != "female" { photoSection }
            basicInfoSection
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .dsAlert(successTitle, isPresented: $showSuccessAlert,
                 moment: approvalRequestWarning != nil ? nil : (sentForApproval ? .sentForApproval : .newMember)) {
            Button(L10n.t("موافق", "OK")) { dismiss() }
        } message: {
            Text(successMessage)
        }
        .dsAlert(L10n.t("خطأ", "Error"), isPresented: $showErrorAlert) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(errorMessage)
        }
        .dsAlert(L10n.t("تأكد قبل الحفظ", "Check before saving"), isPresented: $showLocalWarnings, icon: "exclamationmark.triangle.fill") {
            Button(L10n.t("متابعة", "Continue")) { performSave() }
            Button(L10n.t("تعديل", "Edit"), role: .cancel) {}
        } message: {
            Text(localWarnings.joined(separator: "\n\n"))
        }
        .onAppear {
            if !lastAuthDialingCode.isEmpty {
                selectedPhoneCountry = KuwaitPhone.countryForDialingCode(lastAuthDialingCode)
            }
        }
    }

    /// رسالة الحفظ صادقة (ج-١): ابن العضو ينتظر موافقة الإدارة، لا «تمت الإضافة»
    private var successTitle: String {
        if approvalRequestWarning != nil { return L10n.t("تنبيه", "Notice") }
        return sentForApproval ? L10n.t("أُرسل للموافقة", "Sent for Approval")
                               : L10n.t("تمت الإضافة", "Added Successfully")
    }

    private var successMessage: String {
        if let approvalRequestWarning { return approvalRequestWarning }
        return sentForApproval
            ? L10n.t("أُضيف ابنك وأُرسل للإدارة للموافقة.",
                     "Your son was added and sent to the administration for approval.")
            : L10n.t("تمت الإضافة بنجاح.", "Added successfully.")
    }

    /// أي إدخال (اسم، رقم، صورة، تاريخ، جنس، وفاة) — «إلغاء» يسأل قبل تجاهله (توصية أبل).
    /// المربّع يبدأ فارغاً؛ رمز الدولة المُعبّأ تلقائياً لا يُحسب وحده.
    private var hasUnsavedChanges: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !phoneNumber.isEmpty
            || selectedUIImage != nil
            || birthDateProvided
            || selectedGender != "male"
            || isDeceased
    }

    /// الصورة — قسم مثل أقسام مربّعات الإضافة (للذكر فقط)
    private var photoSection: some View {
        DSComposerSection(title: L10n.t("الصورة الشخصية", "Profile Photo"), icon: "camera.fill",
                          tint: DS.Color.primary, trailing: L10n.t("اختياري", "Optional"), index: 0) {
            DSProfilePhotoPicker(
                selectedImage: $selectedUIImage,
                enableCrop: true,
                cropShape: .circle,
                trailing: nil,   // «اختياري» في عنوان القسم
                compactEmptyState: true
            )
            .frame(maxWidth: .infinity)
        }
    }

    /// البيانات — نفس أقسام وحقول مربّعات الإضافة («أسلوب واحد»): الاسم، الجنس، الهاتف، التواريخ
    private var basicInfoSection: some View {
        DSComposerSection(title: L10n.t("المعلومات الشخصية", "Personal Info"),
                          icon: "person.text.rectangle", tint: DS.Color.primary, index: 1) {
            DSComposerField(icon: "person.fill", label: L10n.t("الاسم الأول", "First Name"),
                            placeholder: L10n.t("اسم الابن", "Child's name"),
                            text: $firstName, tint: DS.Color.primary, limit: 50)

            // اختيار الجنس — أنثى تُضاف لشجرة النساء، ذكر للشجرة العامة
            DSGenderPicker(selection: $selectedGender)

            // الهاتف — للابن (الذكر) فقط
            if selectedGender == "male" {
                DSFieldBox(L10n.t("رقم الهاتف", "Phone Number")) {
                    DSPhoneField(
                        country: $selectedPhoneCountry,
                        digits: $phoneNumber,
                        placeholder: L10n.t("اختياري", "Optional"),
                        compact: true,
                        bordered: false
                    )
                }
            }

            // تاريخ الميلاد (اختياري: يُرسل فقط إذا حدّده المستخدم)
            dateRow(icon: "gift.fill", tint: DS.Color.warning,
                    title: L10n.t("تاريخ الميلاد", "Birth Date"),
                    value: birthDateProvided ? DSDateText.display(birthDate) : L10n.t("بدون تاريخ", "No date")) {
                dsPresentDatePicker(title: L10n.t("تاريخ الميلاد", "Birth Date"),
                                    initial: birthDateProvided ? birthDate : nil, allowClear: false) { picked in
                    guard let picked else { return }
                    birthDate = picked
                    birthDateProvided = true
                }
            }

            // متوفى — صفّ بإطار حقول المربّعات
            DSRow(icon: "leaf.fill", tint: DS.Color.error, title: L10n.t("متوفى", "Deceased")) {
                Toggle("", isOn: $isDeceased.animation(DS.Anim.snappy))
                    .labelsHidden()
                    .tint(DS.Color.error)
                    // القارئ الصوتي: المفتاح بلا نص ظاهر — اسمه صراحةً
                    .accessibilityLabel(L10n.t("متوفى", "Deceased"))
            }

            if isDeceased {
                dateRow(icon: "calendar", tint: DS.Color.error,
                        title: L10n.t("تاريخ الوفاة", "Death Date"),
                        value: DSDateText.display(deathDate)) {
                    dsPresentDatePicker(title: L10n.t("تاريخ الوفاة", "Death Date"),
                                        initial: deathDate, allowClear: false) { picked in
                        if let picked { deathDate = picked }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// صفّ تاريخ يفتح مربّع التاريخ الموحّد بالمنتصف
    private func dateRow(icon: String, tint: Color, title: String, value: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DSRow(icon: icon, tint: tint, title: title, subtitle: value) {
                DSStateIcon("pencil", tint: DS.Color.primary, size: DSBox.fieldIcon)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.t("يفتح اختيار التاريخ", "Opens the date picker"))
    }

    /// حارس محلي يمنع الإضافة المكرّرة — isLoading في الـ VM يتأخر لحظة
    /// بعد الضغط، فكانت النقرات السريعة تنشئ أكثر من سجل.
    @State private var isSubmitting = false

    /// الفحص المحلي: اسم قريب من ابن مسجّل، أو ميلاد قريب جداً من ميلاد الأب — والعضو يقدر يكمل
    private var currentWarnings: [String] {
        var list: [String] = []
        let name = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedGender != "female" {
            let sons = memberVM.allMembers.filter { $0.fatherId == member.id && !$0.isFemale }
            if let son = AddChildChecks.nearSon(name: name, among: sons) {
                list.append(L10n.t("«\(name)» قريب من اسم ابنك «\(son.firstName)». هل هو شخص ثاني؟",
                                   "«\(name)» is close to your son's name «\(son.firstName)». Is this a different person?"))
            }
        }
        if birthDateProvided, AddChildChecks.isTooCloseToFather(childBirth: birthDate, fatherBirth: member.birthDate) {
            list.append(L10n.t("ميلاد الابن قريب جداً من ميلاد الأب.", "The birth date is very close to the father's."))
        }
        return list
    }

    private func saveChild() {
        guard !isSubmitting else { return }
        let warnings = currentWarnings
        if warnings.isEmpty {
            performSave()
        } else {
            localWarnings = warnings
            showLocalWarnings = true
        }
    }

    private func performSave() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            let name = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            // تاريخ الميلاد اختياري: لا نكتبه إن لم يحدّده المستخدم (بدل «اليوم» الخاطئ).
            let birthDateString: String? = birthDateProvided ? formatter.string(from: birthDate) : nil
            let deathDateString: String? = isDeceased ? formatter.string(from: deathDate) : nil

            if selectedGender == "female" {
                // أنثى → شجرة النساء عبر RPC add_family_child
                let newId = await memberVM.addFamilyChild(
                    parentId: member.id,
                    name: name,
                    gender: "female",
                    birthDate: birthDateProvided ? birthDate : nil,
                    isDeceased: isDeceased,
                    deathDate: isDeceased ? deathDate : nil,
                    parentFullName: member.fullName
                )
                guard newId != nil else {
                    errorMessage = memberVM.errorMessage ?? L10n.t("فشل في الإضافة.", "Failed to add.")
                    showErrorAlert = true
                    return
                }
            } else {
                // ذكر → الشجرة العامة (profiles) مع هاتف/صورة، وينعكس تلقائياً لشجرة النساء
                memberVM.errorMessage = nil   // لا تظهر رسالة قديمة إن رجع بلا محاولة (بلا اتصال)
                let childId = await memberVM.addChild(
                    firstNameOnly: name,
                    phoneNumber: KuwaitPhone.normalizedForStorage(
                        country: selectedPhoneCountry,
                        rawLocalDigits: phoneNumber
                    ) ?? "",
                    birthDate: birthDateString,
                    fatherId: member.id,
                    isDeceased: isDeceased,
                    deathDate: deathDateString,
                    gender: "male"
                )
                guard let childId else {
                    errorMessage = memberVM.errorMessage
                        ?? L10n.t("فشل في إضافة الابن. حاول مرة أخرى.", "Failed to add child. Please try again.")
                    showErrorAlert = true
                    return
                }
                // غير الإدارة: الابن «معلّق» وطلبه عند الإدارة (ج-١) — أو حُفظ وطلبه لم يصل
                sentForApproval = !authVM.canModerate && !memberVM.lastChildAddWasDirect
                approvalRequestWarning = memberVM.errorMessage
                if let image = selectedUIImage {
                    await memberVM.uploadAvatar(image: image, for: childId)
                }
            }

            await memberVM.fetchChildren(for: member.id)
            showSuccessAlert = true
        }
    }
}
