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
    @State private var sheetHeight: CGFloat = 520

    var body: some View {
        // نفس هيكل مربّعات الإضافة وحركتها (طلب المالك)
        DSComposer(
            title: L10n.t("تعديل بيانات الابن", "Edit Child Info"),
            subtitle: L10n.t("عدّل بياناته في الشجرة", "Update the details in the tree"),
            icon: "person.crop.circle.badge.checkmark",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            actionIcon: "checkmark",
            canSubmit: !(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving),
            isBusy: isSaving,
            contentPadding: 0,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: saveChanges,
            onCancel: { dismiss() }
        ) {
            // الصورة للذكر فقط — الأنثى بلا خيار صورة
            if selectedGender != "female" { heroHeader.dsStaggerIn(0) }
            basicInfoCard
                .padding(.horizontal, DS.Spacing.lg)
                .dsStaggerIn(1)
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

    private var heroHeader: some View {
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
        .padding(.horizontal, DS.Spacing.lg)
    }

    private var basicInfoCard: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("المعلومات الشخصية", "Personal Info"),
                icon: "person.text.rectangle",
                iconColor: DS.Color.primary
            )

                VStack(spacing: 0) {
                    // Name field — العنوان فوق الحقل
                    DSLabeledFieldRow(icon: "person.fill", iconColor: DS.Color.primary,
                                      label: L10n.t("الاسم الأول", "First Name")) {
                        TextField(L10n.t("اسم الابن", "Child's name"), text: $firstName)
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textPrimary)
                            .onChange(of: firstName) { _ in
                                if firstName.count > 50 {
                                    firstName = String(firstName.prefix(50))
                                }
                            }
                    }

                    DSDivider()

                    // اختيار الجنس — ذكر/أنثى (نفس واجهة الإضافة)
                    DSFormRow(icon: "person.2.fill", iconColor: DS.Color.accent,
                              label: L10n.t("الجنس", "Gender")) {
                        HStack(spacing: DS.Spacing.xs) {
                            genderButton(title: L10n.t("ذكر", "Male"), value: "male", color: DS.Color.actionNavy)
                            genderButton(title: L10n.t("أنثى", "Female"), value: "female", color: DS.Color.neonPink)
                        }
                    }

                    // الهاتف — للذكر فقط
                    if selectedGender == "male" {
                        DSDivider()
                        DSLabeledFieldRow(icon: "phone.fill", iconColor: DS.Color.success,
                                          label: L10n.t("رقم الهاتف", "Phone Number")) {
                            DSPhoneField(
                                country: $selectedPhoneCountry,
                                digits: $phoneNumber,
                                placeholder: L10n.t("اختياري", "Optional"),
                                compact: true,
                                bordered: false
                            )
                        }
                    }

                    DSDivider()

                    // Birth date — صف موحّد (يُرسل فقط إذا كان معروفاً/حدّده المستخدم)
                    DSDateField(
                        label: L10n.t("تاريخ الميلاد", "Birth Date"),
                        date: $birthDate,
                        range: ...Date(),
                        labelAbove: true
                    )
                    .onChange(of: birthDate) { _ in birthDateProvided = true }

                    DSDivider()

                    // Deceased toggle — صف موحّد
                    DSFormRow(icon: "leaf.fill", iconColor: DS.Color.error,
                              label: L10n.t("متوفى", "Deceased")) {
                        Toggle("", isOn: $isDeceased)
                            .labelsHidden()
                            .tint(DS.Color.error)
                            // القارئ الصوتي: المفتاح بلا نص ظاهر — اسمه صراحةً
                            .accessibilityLabel(L10n.t("متوفى", "Deceased"))
                    }
                    .animation(.default, value: isDeceased)

                    if isDeceased {
                        DSDivider()
                        DSDateField(
                            label: L10n.t("تاريخ الوفاة", "Death Date"),
                            date: $deathDate,
                            icon: "calendar",
                            iconColor: DS.Color.error,
                            range: ...Date()
                        )
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.xs)

                        // الوفاة من غير الإدارة تُرسل طلباً لتأكيدها
                        if !(member.isDeceased ?? false), !authVM.canEditMembers {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(L10n.t("تُرسل للإدارة لتأكيدها قبل ظهورها في الشجرة",
                                            "Sent to the administration to confirm first"))
                                    .font(DS.Font.plex(11.5, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundColor(DS.Color.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.bottom, DS.Spacing.sm)
                        }
                    }
                }
            }
    }

    private var submitButton: some View {
        DSPrimaryButton(
            L10n.t("حفظ التعديلات", "Save Changes"),
            icon: "checkmark.circle.fill",
            isLoading: isSaving,
            action: saveChanges
        )
        .opacity(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
        .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
    }

    private func genderButton(title: String, value: String, color: Color) -> some View {
        let selected = selectedGender == value
        return Button { selectedGender = value } label: {
            Text(title)
                .font(DS.Font.caption1).fontWeight(.bold)
                .foregroundColor(selected ? .white : DS.Color.textSecondary)
                .padding(.horizontal, DS.Spacing.md)
                .frame(height: 34)
                .background(Capsule().fill(selected ? color : DS.Color.surface))
                .overlay(Capsule().strokeBorder(selected ? Color.clear : DS.Color.textTertiary.opacity(0.3), lineWidth: 1))
                // مساحة ضغط ٤٤ نقطة (حد أبل) والحبّة بنفس شكلها — الصف ارتفاعه ٥٢ فيسعها
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

            let success = await memberVM.updateChildData(
                member: updatedMember,
                firstName: cleanFirst,
                phoneNumber: KuwaitPhone.normalizedForStorage(
                    country: selectedPhoneCountry,
                    rawLocalDigits: phoneNumber
                ) ?? "",
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
