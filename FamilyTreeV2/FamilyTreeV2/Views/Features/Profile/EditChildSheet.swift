import SwiftUI
import PhotosUI
import UIKit

struct EditChildSheet: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) private var dismiss
    let member: FamilyMember

    @State private var firstName: String = ""
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var phoneNumber: String = ""
    @State private var birthDate: Date = Date()
    /// هل للابن تاريخ ميلاد فعلي (أو حدّده المستخدم الآن)؟ — لا نكتب «اليوم» المفبرك.
    @State private var birthDateProvided: Bool = false
    @State private var selectedGender: String = "male"
    @State private var isDeceased: Bool = false
    @State private var deathDate: Date = Date()
    @State private var selectedUIImage: UIImage? = nil
    @State private var showSuccessAlert = false
    /// وفاة الابن أُرسلت طلباً للإدارة (بدل تسجيلها مباشرة) — تتغيّر رسالة الحفظ
    @State private var deathRequestSent = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        // نفس هيكل مربّعات الإضافة وحركتها (طلب المالك)
        DSComposer(
            title: L10n.t("تعديل بيانات الابن", "Edit Child Info"),
            // الاسم الثلاثي للابن بدل الجملة العامة — ليعرف المستخدم بيانات من يعدّل (طلب المالك ٢٠٢٦-١٠-٠٧)
            subtitle: member.fullName.isEmpty ? L10n.t("عدّل بياناته في الشجرة", "Update the details in the tree")
                                              : member.fullName.nameThreeParts,
            icon: "person.crop.circle.badge.checkmark",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            actionIcon: "checkmark",
            canSubmit: !(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving),
            isBusy: isSaving,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: saveChanges,
            onCancel: { dismiss() }
        ) {
            // الصورة للذكر فقط — الأنثى بلا خيار صورة
            if selectedGender != "female" { photoSection }
            basicInfoSection
        }
        .onAppear(perform: setupData)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .dsAlert(L10n.t("تم الحفظ", "Saved"), isPresented: $showSuccessAlert) {
            Button(L10n.t("موافق", "OK")) { dismiss() }
        } message: {
            Text(deathRequestSent
                 ? L10n.t("تم حفظ التعديلات، وأُرسل طلب تسجيل الوفاة للإدارة لتأكيده.",
                          "Changes saved. The death was sent to the administration to confirm.")
                 : L10n.t("تم تحديث بيانات الابن بنجاح.", "Child info updated successfully."))
        }
        .dsAlert(L10n.t("خطأ", "Error"), isPresented: $showErrorAlert) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - تغييرات لم تُحفظ (توصية أبل)

    /// الحقول كما تُحفظ — تُقارن بما فُتح عليه المربّع
    private struct Draft: Equatable {
        var name: String
        var gender: String
        /// الدولة تُحسب مع الرقم فقط (رقم فارغ = لا رقم)
        var phone: String
        var birth: String?
        var isDeceased: Bool
        var death: String?
    }

    /// القيم التي فُتح عليها المربّع — تُلتقط مرة في setupData
    @State private var startDraft: Draft? = nil

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
            birth: birthDateProvided ? Self.dayFormatter.string(from: birthDate) : nil,
            isDeceased: isDeceased,
            death: isDeceased ? Self.dayFormatter.string(from: deathDate) : nil
        )
    }

    /// صورة جديدة أو أي حقل يختلف عمّا فُتح عليه — «إلغاء» يسأل قبل التجاهل
    private var hasUnsavedChanges: Bool {
        guard let startDraft else { return false }
        return selectedUIImage != nil || currentDraft != startDraft
    }

    /// الصورة — قسم مثل أقسام مربّعات الإضافة (للذكر فقط)
    private var photoSection: some View {
        DSComposerSection(title: L10n.t("الصورة الشخصية", "Profile Photo"), icon: "camera.fill",
                          tint: DS.Color.primary, index: 0) {
            DSProfilePhotoPicker(
                selectedImage: $selectedUIImage,
                existingURL: member.avatarUrl,
                enableCrop: true,
                cropShape: .circle,
                trailing: nil,
                showDeleteForExisting: member.avatarUrl != nil,
                onDeleteExisting: {
                    Task {
                        await memberVM.deleteAvatar(for: member.id)
                    }
                },
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

            // اختيار الجنس — ذكر/أنثى (نفس واجهة الإضافة)
            DSGenderPicker(selection: $selectedGender)

            // الهاتف — للذكر فقط
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

            // تاريخ الميلاد (يُرسل فقط إذا كان معروفاً/حدّده المستخدم)
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

                // الوفاة من غير الإدارة تُرسل طلباً لتأكيدها
                if !(member.isDeceased ?? false), !authVM.canEditMembers {
                    DSNoteCard(L10n.t("تُرسل للإدارة لتأكيدها قبل ظهورها في الشجرة",
                                      "Sent to the administration to confirm first"))
                }
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

    private func setupData() {
        firstName = member.firstName
        selectedGender = member.gender ?? "male"
        let detectedPhone = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
        selectedPhoneCountry = detectedPhone.country
        phoneNumber = detectedPhone.localDigits
        isDeceased = member.isDeceased ?? false

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if let birth = member.birthDate, !birth.isEmpty, let parsed = formatter.date(from: birth) {
            birthDate = parsed
            birthDateProvided = true
        }

        if let death = member.deathDate, !death.isEmpty, let parsed = formatter.date(from: death) {
            deathDate = parsed
        }

        // نقطة البداية لمقارنة «تغييرات لم تُحفظ» — مرة واحدة فقط (لا يُعاد عند رجوع العرض)
        if startDraft == nil { startDraft = currentDraft }
    }

    @State private var isSaving = false

    private func saveChanges() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")

            // اختياري: نُرسل nil (غير معروف) إن لم يُحدَّد تاريخ ميلاد — بدل «اليوم» الخاطئ.
            let birthDateString: String? = birthDateProvided ? formatter.string(from: birthDate) : nil
            let deathDateString: String? = isDeceased ? formatter.string(from: deathDate) : nil

            let cleanFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)

            // بناء الاسم الكامل الجديد — نستبدل الاسم الأول فقط ونحافظ على باقي السلسلة
            let originalParts = member.fullName.split(whereSeparator: \.isWhitespace).map(String.init)
            let finalFullName: String = originalParts.count > 1
                ? ([cleanFirst] + originalParts.dropFirst()).joined(separator: " ")
                : cleanFirst

            var updatedMember = member
            updatedMember.fullName = finalFullName
            updatedMember.firstName = cleanFirst

            // وفاة الابن يسجّلها الأب (من غير الإدارة) = طلب للإدارة (طلب المالك):
            // بقية التعديلات تُحفظ مباشرة، والوفاة تنتظر القبول ثم يطلع «إعلان وفاة» للإدارة
            let wasDeceased = member.isDeceased ?? false
            let newlyDeceased = isDeceased && !wasDeceased
            let deathNeedsApproval = newlyDeceased && !authVM.canEditMembers

            // الرقم يُرسل فقط إذا تغيّر فعلاً (فحص الثغرات ب-٢): رقم الابن المخفي يصل هنا
            // فارغاً، فكان كل حفظ يمسحه وينقفل الدخول على الابن. لا يُكتب فوقه فراغ أبداً.
            var phoneToSend: String? = nil
            if selectedGender == "male" {
                let entered = KuwaitPhone.normalizedForStorage(country: selectedPhoneCountry,
                                                               rawLocalDigits: phoneNumber)
                // رقم مكتوب لكنه غير صالح — لا نحوّله إلى «حذف الرقم» بصمت
                if !phoneNumber.isEmpty && entered == nil {
                    isSaving = false
                    errorMessage = L10n.t("رقم الهاتف غير صحيح. تحقّق من الرقم ورمز الدولة.",
                                          "Invalid phone number. Check the number and country code.")
                    showErrorAlert = true
                    return
                }
                let start = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
                let original = KuwaitPhone.normalizedForStorage(country: start.country,
                                                                rawLocalDigits: start.localDigits) ?? ""
                if (entered ?? "") != original { phoneToSend = entered ?? "" }
            }

            let success = await memberVM.updateChildData(
                member: updatedMember,
                firstName: cleanFirst,
                phoneNumber: phoneToSend,
                birthDate: birthDateString,
                isDeceased: deathNeedsApproval ? wasDeceased : isDeceased,
                deathDate: deathNeedsApproval ? member.deathDate : deathDateString,
                gender: selectedGender
            )

            var requestFailed = false
            if success, deathNeedsApproval {
                let sent = await adminRequestVM.submitTreeEditRequest(payload: TreeEditPayload.make(
                    action: .deceased,
                    targetMemberId: member.id.uuidString,
                    targetMemberName: finalFullName,
                    deathDate: deathDateString
                ))
                requestFailed = !sent
            }

            if let image = selectedUIImage {
                await memberVM.uploadAvatar(image: image, for: member.id)
            }

            isSaving = false
            if success, requestFailed {
                errorMessage = L10n.t("حُفظت التعديلات، لكن تعذّر إرسال طلب الوفاة للإدارة. حاول مرة ثانية.",
                                      "Changes saved, but the death request couldn't be sent. Try again.")
                showErrorAlert = true
            } else if success {
                deathRequestSent = deathNeedsApproval
                showSuccessAlert = true
                // الإدارة سجّلت الوفاة مباشرة → مربّع «إعلان وفاة»
                if newlyDeceased, !deathNeedsApproval {
                    let target = DeathAnnouncementTarget(id: member.id, name: finalFullName,
                                                         isFemale: selectedGender == "female",
                                                         deathDate: deathDateString)
                    let canAnnounce = authVM.canApproveTreeRequests
                    Task { await DeathAnnouncementPresenter.offer(target, canAnnounce: canAnnounce) }
                }
            } else {
                errorMessage = L10n.t("فشل حفظ التعديلات. حاول مرة أخرى.", "Save failed. Try again.")
                showErrorAlert = true
            }
        }
    }
}
