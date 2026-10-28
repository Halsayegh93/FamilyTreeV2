import SwiftUI
import PhotosUI
import UIKit

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

    private func saveChild() {
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
                    errorMessage = L10n.t("فشل في إضافة الابن. حاول مرة أخرى.", "Failed to add child. Please try again.")
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
