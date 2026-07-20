import SwiftUI
import PhotosUI
import UIKit

struct EditChildSheet: View {
    @EnvironmentObject var memberVM: MemberViewModel
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
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var sheetHeight: CGFloat = 520

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()


                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {
                        // الصورة للذكر فقط — الأنثى بلا خيار صورة
                        if selectedGender != "female" { heroHeader }
                        basicInfoCard
                            .padding(.horizontal, DS.Spacing.lg)
                        submitButton
                            .padding(.horizontal, DS.Spacing.lg)
                    }
                    .padding(.vertical, DS.Spacing.xs)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: SheetContentHeightKey.self, value: proxy.size.height)
                        }
                    )
                }
            }
            .navigationTitle(L10n.t("تعديل بيانات الابن", "Edit Child Info"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.error)
                }
            }
            .onAppear(perform: setupData)
        }
        .onPreferenceChange(SheetContentHeightKey.self) { h in
            if h > 0 { sheetHeight = h + 72 }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .alert(L10n.t("تم الحفظ", "Saved"), isPresented: $showSuccessAlert) {
            Button(L10n.t("موافق", "OK")) { dismiss() }
        } message: {
            Text(L10n.t("تم تحديث بيانات الابن بنجاح.", "Child info updated successfully."))
        }
        .alert(L10n.t("خطأ", "Error"), isPresented: $showErrorAlert) {
            Button(L10n.t("موافق", "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
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
                            genderButton(title: L10n.t("ذكر", "Male"), value: "male", color: DS.Color.primary)
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
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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

            let success = await memberVM.updateChildData(
                member: updatedMember,
                firstName: cleanFirst,
                phoneNumber: KuwaitPhone.normalizedForStorage(
                    country: selectedPhoneCountry,
                    rawLocalDigits: phoneNumber
                ) ?? "",
                birthDate: birthDateString,
                isDeceased: isDeceased,
                deathDate: deathDateString,
                gender: selectedGender
            )

            if let image = selectedUIImage {
                await memberVM.uploadAvatar(image: image, for: member.id)
            }

            isSaving = false
            if success {
                showSuccessAlert = true
            } else {
                errorMessage = L10n.t("فشل حفظ التعديلات. حاول مرة أخرى.", "Save failed. Try again.")
                showErrorAlert = true
            }
        }
    }
}
