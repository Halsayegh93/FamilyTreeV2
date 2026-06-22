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
    @State private var selectedGender: String = "male"
    @State private var isDeceased: Bool = false
    @State private var deathDate: Date = Date()
    @State private var selectedUIImage: UIImage? = nil
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var sheetHeight: CGFloat = 520
    @State private var selectedMotherId: UUID? = nil
    @State private var isHiddenFromTree: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()


                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {
                        heroHeader
                        basicInfoCard
                            .padding(.horizontal, DS.Spacing.lg)
                        motherPicker
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

    @ViewBuilder
    private var heroHeader: some View {
        if selectedGender == "female" {
            // قاعدة التطبيق: الأنثى بلا صورة شخصية.
            FemaleAvatarView()
                .frame(width: 96, height: 96)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DS.Spacing.lg)
        } else {
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

                    // Phone field — العنوان فوق الحقل، الحقل بدون إطار
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

                    DSDivider()

                    // Birth date — صف موحّد
                    DSDateField(
                        label: L10n.t("تاريخ الميلاد", "Birth Date"),
                        date: $birthDate,
                        range: ...Date(),
                        labelAbove: true
                    )

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

                    DSDivider()

                    // إظهار/إخفاء من الشجرة
                    DSFormRow(icon: isHiddenFromTree ? "eye.slash" : "eye",
                              iconColor: DS.Color.primary,
                              label: L10n.t("إظهار في الشجرة", "Show in tree")) {
                        Toggle("", isOn: Binding(
                            get: { !isHiddenFromTree },
                            set: { isHiddenFromTree = !$0 }
                        ))
                        .labelsHidden()
                        .tint(DS.Color.primary)
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

    private func setupData() {
        firstName = member.firstName
        selectedGender = member.gender ?? "male"
        selectedMotherId = member.motherId
        let detectedPhone = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
        selectedPhoneCountry = detectedPhone.country
        phoneNumber = detectedPhone.localDigits
        isDeceased = member.isDeceased ?? false
        isHiddenFromTree = member.isHiddenFromTree

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if let birth = member.birthDate, !birth.isEmpty, let parsed = formatter.date(from: birth) {
            birthDate = parsed
        }

        if let death = member.deathDate, !death.isEmpty, let parsed = formatter.date(from: death) {
            deathDate = parsed
        }
    }

    @State private var isSaving = false

    /// زوجات أبي الابن (للاختيار كأم).
    private var fatherWives: [FamilyMember] {
        guard let fid = member.fatherId else { return [] }
        return memberVM.allMembers
            .filter { $0.husbandId == fid && $0.isFemale }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// منتقي الأم — يظهر فقط لو فيه زوجات مسجّلات لأب الابن.
    @ViewBuilder
    private var motherPicker: some View {
        let wives = fatherWives
        if !wives.isEmpty {
            DSCard {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(DS.Color.accent)
                    Text(L10n.t("الأم", "Mother"))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textSecondary)
                    Spacer()
                    Picker(L10n.t("الأم", "Mother"), selection: $selectedMotherId) {
                        Text(L10n.t("بدون", "None")).tag(UUID?.none)
                        ForEach(wives) { w in
                            Text(w.firstName).tag(UUID?.some(w.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(DS.Color.primary)
                }
            }
        }
    }

    private func saveChanges() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")

            let birthDateString: String? = formatter.string(from: birthDate)
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

            // تعيين الأم (إحدى زوجات الأب) — لا يؤثّر على نجاح بقية الحفظ.
            if selectedMotherId != member.motherId {
                await memberVM.setMother(childId: member.id, motherId: selectedMotherId, silent: true)
            }

            // إظهار/إخفاء من الشجرة.
            if isHiddenFromTree != member.isHiddenFromTree {
                await memberVM.setHiddenFromTree(memberId: member.id, hidden: isHiddenFromTree)
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
