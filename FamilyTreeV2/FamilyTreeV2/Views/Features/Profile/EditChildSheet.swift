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
    /// تاريخ الوفاة معروف/حدّده المستخدم — بدونه لا يُرسل «اليوم» كتاريخ وفاة
    @State private var deathDateProvided: Bool = false
    @State private var selectedUIImage: UIImage? = nil
    @State private var showSuccessAlert = false
    /// وفاة الابن أُرسلت طلباً للإدارة (بدل تسجيلها مباشرة) — تتغيّر رسالة الحفظ
    @State private var deathRequestSent = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    /// حذف الابن من «عائلتي» — لكل عضو يعدّل ابنه هو (طلب المالك ٢٠٢٦-١٠-١٦ «حط زر حذف للكل»)
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    var body: some View {
        // نفس هيكل مربّعات الإضافة وحركتها (طلب المالك)
        DSComposer(
            title: L10n.t("تعديل بيانات الابن", "Edit Child Info"),
            // الاسم الثلاثي للابن بدل الجملة العامة — ليعرف المستخدم بيانات من يعدّل (طلب المالك ٢٠٢٦-١٠-٠٧)
            subtitle: member.fullName.isEmpty ? L10n.t("عدّل بياناته في الشجرة", "Update the details in the tree")
                                              : member.shortFullName,   // بالعائلة المختارة
            icon: "person.crop.circle.badge.checkmark",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            actionIcon: "checkmark",
            canSubmit: !(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving),
            isBusy: isSaving,
            hasUnsavedChanges: hasUnsavedChanges,
            extraActions: deleteActions,
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
        .dsAlert(L10n.t("حذف الابن؟", "Delete this son?"), isPresented: $showDeleteConfirm) {
            Button(L10n.t("حذف نهائي", "Delete permanently"), role: .destructive) { deleteChild() }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("يُحذف «\(member.firstName)» من الشجرة ومن عائلتك، ويُلغى طلب إضافته إن كان معلّقاً. لا يمكن التراجع.",
                        "«\(member.firstName)» is removed from the tree and your family, and a pending add request is cancelled. This can't be undone."))
        }
    }

    // MARK: - حذف الابن (لكل أب — طلب المالك ٢٠٢٦-١٠-١٦ «حط زر حذف للكل»)

    /// ابنه هو (أبوه = المستخدم) — يحذفه أي عضو مفعّل عبر remove_self_child (أبناؤه فقط، بلا حساب دخول،
    /// والمتوفى للمالك والمدير — السيرفر يرفض غير ذلك برسالة عربية)
    private var isOwnSon: Bool {
        guard let me = authVM.currentUser?.id else { return false }
        return member.fatherId == me
    }

    /// زرّ الحذف بأسفل المربّع — لكل من يعدّل ابنه هو، وللمالك والمدير كما كان
    private var deleteActions: [DSComposerAction] {
        guard isOwnSon || authVM.canDeleteMembers else { return [] }
        return [DSComposerAction(id: "delete-child", title: L10n.t("حذف الابن", "Delete son"), icon: "trash",
                                 role: .destructive, isEnabled: !isDeleting && !isSaving, fullRow: true) {
            showDeleteConfirm = true
        }]
    }

    private func deleteChild() {
        isDeleting = true
        Task {
            let ok: Bool
            if isOwnSon {
                switch await memberVM.removeSelfChild(id: member.id) {
                case .deleted:
                    ok = true
                case .serverMissing where authVM.canDeleteMembers:
                    // الدالة لم تُرفع للسيرفر بعد — المالك والمدير بالمسار المباشر القديم
                    ok = await deleteDirectly()
                case .serverMissing, .failed:
                    ok = false
                }
            } else {
                ok = await deleteDirectly()
            }
            if ok {
                await adminRequestVM.fetchMyPendingRequests(force: true)
                isDeleting = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } else {
                isDeleting = false
                errorMessage = memberVM.errorMessage ?? L10n.t("تعذّر حذف الابن.", "Couldn't delete the son.")
                showErrorAlert = true
            }
        }
    }

    /// المسار المباشر (المالك والمدير): حذف السجل، ثم طلب «إضافة ابن» المعلّق عنه، وتحديث العائلة
    /// (السيرفر يحذف نسخته في شجرة النساء)
    private func deleteDirectly() async -> Bool {
        guard await memberVM.deleteMember(memberId: member.id) else { return false }
        await adminRequestVM.deleteChildAddRequests(childId: member.id)
        if let uid = authVM.currentUser?.id {
            await memberVM.fetchChildren(for: uid)   // يُنعش شجرة النساء معه (fetchWomenFamily)
        }
        return true
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

    private var currentDraft: Draft {
        Draft(
            name: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            gender: selectedGender,
            phone: phoneNumber.isEmpty ? "" : "\(selectedPhoneCountry.id)|\(phoneNumber)",
            birth: birthDateProvided ? DateHelper.format(birthDate) : nil,
            isDeceased: isDeceased,
            death: isDeceased && deathDateProvided ? DateHelper.format(deathDate) : nil
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

            // الجنس — تغييره ينقل الابن بين الشجرة العامة وشجرة النساء (`move_child_gender`)،
            // فهو لمن يعدّل الشجرة فقط (`canEditMembers`، مثل أندرويد)؛ لغيرهم للقراءة
            if authVM.canEditMembers {
                DSGenderPicker(selection: $selectedGender)
            } else {
                DSGenderReadOnlyRow(gender: originalGender)
            }

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
                        value: deathDateProvided ? DSDateText.display(deathDate) : L10n.t("بدون تاريخ", "No date")) {
                    dsPresentDatePicker(title: L10n.t("تاريخ الوفاة", "Death Date"),
                                        initial: deathDateProvided ? deathDate : nil, allowClear: false) { picked in
                        guard let picked else { return }
                        deathDate = picked
                        deathDateProvided = true
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

    /// الجنس كما فُتح عليه المربّع (بلا قيمة = ذكر)
    private var originalGender: String {
        (member.gender ?? "male").lowercased() == "female" ? "female" : "male"
    }

    private func setupData() {
        firstName = member.firstName
        selectedGender = originalGender
        let detectedPhone = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
        selectedPhoneCountry = detectedPhone.country
        phoneNumber = detectedPhone.localDigits
        isDeceased = member.isDeceased ?? false

        // DateHelper: ميلادي بأرقام لاتينية أياً كان تقويم الجهاز
        if let parsed = DateHelper.parse(member.birthDate) {
            birthDate = parsed
            birthDateProvided = true
        }

        if let parsed = DateHelper.parse(member.deathDate) {
            deathDate = parsed
            deathDateProvided = true
        }

        // نقطة البداية لمقارنة «تغييرات لم تُحفظ» — مرة واحدة فقط (لا يُعاد عند رجوع العرض)
        if startDraft == nil { startDraft = currentDraft }
    }

    @State private var isSaving = false

    private func saveChanges() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            // اختياري: نُرسل nil (غير معروف) إن لم يُحدَّد تاريخ ميلاد/وفاة — بدل «اليوم» الخاطئ.
            let birthDateString: String? = birthDateProvided ? DateHelper.format(birthDate) : nil
            let deathDateString: String? = isDeceased && deathDateProvided ? DateHelper.format(deathDate) : nil

            let cleanFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)

            // بناء الاسم الكامل الجديد — نستبدل الاسم الأول القديم كاملاً (ولو مركّباً مثل «زين العابدين»)
            // ونحافظ على باقي السلسلة (القاعدة ١ في PersonName)
            let finalFullName = PersonName.replacingFirstName(
                in: member.fullName, old: member.firstName, new: cleanFirst,
                fatherFullName: member.fatherId.flatMap { memberVM.member(byId: $0)?.fullName })

            // تغيير الجنس (نقل بين الشجرتين) لمن يعدّل الشجرة فقط؛ لغيرهم يبقى الجنس الأصلي
            // (مثل أندرويد — كان الآيفون يكتب عمود gender مباشرة فيبقى الابن في الجدول الخطأ)
            let canEditGender = authVM.canEditMembers
            let wasFemale = originalGender == "female"
            let nowFemale = canEditGender ? (selectedGender == "female") : wasFemale
            let genderChanged = canEditGender && nowFemale != wasFemale

            // وفاة الابن يسجّلها الأب (من غير الإدارة) = طلب للإدارة (طلب المالك):
            // بقية التعديلات تُحفظ مباشرة، والوفاة تنتظر القبول ثم يطلع «إعلان وفاة» للإدارة
            let wasDeceased = member.isDeceased ?? false
            let newlyDeceased = isDeceased && !wasDeceased
            let deathNeedsApproval = newlyDeceased && !authVM.canEditMembers

            // الرقم يُرسل فقط إذا تغيّر فعلاً (فحص الثغرات ب-٢): رقم الابن المخفي يصل هنا
            // فارغاً، فكان كل حفظ يمسحه وينقفل الدخول على الابن. لا يُكتب فوقه فراغ أبداً.
            var phoneToSend: String? = nil
            if !nowFemale {
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

            // تغيير الجنس: ننقل السجل بين الشجرتين أولاً عبر السيرفر (يحفظ الروابط)، ثم تُحفظ
            // بقية الحقول على السجل بعد النقل — نفس ترتيب أندرويد
            var targetId = member.id
            if genderChanged {
                guard let movedId = await memberVM.moveChildGender(childId: member.id,
                                                                   toGender: nowFemale ? "female" : "male") else {
                    isSaving = false
                    errorMessage = memberVM.errorMessage
                        ?? L10n.t("فشل حفظ التعديلات. حاول مرة أخرى.", "Save failed. Try again.")
                    showErrorAlert = true
                    return
                }
                targetId = movedId
            }

            let success: Bool
            if genderChanged && nowFemale {
                // صار في شجرة النساء — لا هاتف ولا صورة للأنثى
                success = await memberVM.updateWomanMember(
                    id: targetId,
                    firstName: cleanFirst,
                    birthDate: birthDateProvided ? birthDate : nil,
                    isDeceased: isDeceased,
                    deathDate: isDeceased && deathDateProvided ? deathDate : nil,
                    gender: "female",
                    fullName: finalFullName
                )
                // يخرج من «الأبناء» في الشجرة العامة
                if let fatherId = member.fatherId { await memberVM.fetchChildren(for: fatherId) }
            } else {
                success = await memberVM.updateChildRow(
                    id: targetId,
                    fatherId: member.fatherId,
                    fullName: finalFullName,
                    firstName: cleanFirst,
                    phoneNumber: phoneToSend,
                    birthDate: birthDateString,
                    isDeceased: deathNeedsApproval ? wasDeceased : isDeceased,
                    deathDate: deathNeedsApproval ? member.deathDate : deathDateString,
                    // الجنس لا يُكتب مباشرة أبداً — تغييره عبر النقل أعلاه فقط
                    gender: nil
                )
            }

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

            // الصورة للذكر فقط (الأنثى بلا صورة)
            if !nowFemale, let image = selectedUIImage {
                await memberVM.uploadAvatar(image: image, for: targetId)
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
                    let target = DeathAnnouncementTarget(id: targetId, name: finalFullName,
                                                         isFemale: nowFemale,
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
