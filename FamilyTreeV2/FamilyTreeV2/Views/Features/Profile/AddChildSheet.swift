import SwiftUI
import PhotosUI
import UIKit

struct AddChildSheet: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss

    let member: FamilyMember

    @State private var firstName: String = ""
    @AppStorage("lastAuthDialingCode") private var lastAuthDialingCode: String = ""
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

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()


                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {
                        heroHeader
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
            .navigationTitle(L10n.t("إضافة فرد", "Add Member"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.error)
                }
            }
        }
        .onPreferenceChange(SheetContentHeightKey.self) { h in
            if h > 0 { sheetHeight = h + 72 }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .alert(L10n.t("تمت الإضافة", "Added Successfully"), isPresented: $showSuccessAlert) {
            Button(L10n.t("موافق", "OK")) { dismiss() }
        } message: {
            Text(L10n.t("تمت الإضافة بنجاح.", "Added successfully."))
        }
        .alert(L10n.t("خطأ", "Error"), isPresented: $showErrorAlert) {
            Button(L10n.t("موافق", "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            if !lastAuthDialingCode.isEmpty {
                selectedPhoneCountry = KuwaitPhone.countryForDialingCode(lastAuthDialingCode)
            }
        }
    }

    private var heroHeader: some View {
        DSProfilePhotoPicker(
            selectedImage: $selectedUIImage,
            enableCrop: true,
            cropShape: .circle,
            trailing: L10n.t("اختياري", "Optional"),
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

                    // اختيار الجنس — أنثى تُضاف لشجرة النساء، ذكر للشجرة العامة
                    DSFormRow(icon: "person.2.fill", iconColor: DS.Color.accent,
                              label: L10n.t("الجنس", "Gender")) {
                        HStack(spacing: DS.Spacing.xs) {
                            genderButton(title: L10n.t("ابن", "Son"), value: "male", color: DS.Color.primary)
                            genderButton(title: L10n.t("ابنة", "Daughter"), value: "female", color: DS.Color.neonPink)
                        }
                    }

                    // الهاتف — للابن (الذكر) فقط
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
                }
            }
    }

    private var submitButton: some View {
        DSPrimaryButton(
            L10n.t("إضافة", "Add"),
            icon: "checkmark.circle.fill",
            isLoading: memberVM.isLoading,
            action: saveChild
        )
        .opacity(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
        .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || memberVM.isLoading)
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

    private func saveChild() {
        Task {
            let name = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            let birthDateString: String? = formatter.string(from: birthDate)
            let deathDateString: String? = isDeceased ? formatter.string(from: deathDate) : nil

            if selectedGender == "female" {
                // أنثى → شجرة النساء عبر RPC add_family_child
                let newId = await memberVM.addFamilyChild(
                    parentId: member.id,
                    name: name,
                    gender: "female",
                    birthDate: birthDate,
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
                if let image = selectedUIImage {
                    await memberVM.uploadAvatar(image: image, for: childId)
                }
            }

            await memberVM.fetchChildren(for: member.id)
            showSuccessAlert = true
        }
    }
}
