import SwiftUI
import PhotosUI
import UIKit

struct AddChildSheet: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss

    let member: FamilyMember

    @State private var firstName: String = ""
    @State private var familyName: String = ""
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
                }
            }
            .navigationTitle(L10n.t("إضافة ابن", "Add Child"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.error)
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .alert(L10n.t("تمت الإضافة", "Added Successfully"), isPresented: $showSuccessAlert) {
            Button(L10n.t("موافق", "OK")) { dismiss() }
        } message: {
            Text(L10n.t("تمت إضافة الابن بنجاح.", "Child added successfully."))
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
                    // Name field
                    HStack(spacing: DS.Spacing.md) {
                        DSIcon("person.fill", color: DS.Color.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("الاسم الأول", "First Name"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                            TextField(L10n.t("اسم الابن", "Child's name"), text: $firstName)
                                .font(DS.Font.callout)
                                .foregroundColor(DS.Color.textPrimary)
                                .onChange(of: firstName) { _ in
                                    if firstName.count > 50 {
                                        firstName = String(firstName.prefix(50))
                                    }
                                }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.xs)

                    DSDivider()

                    // Family name field
                    HStack(spacing: DS.Spacing.md) {
                        DSIcon("person.2.fill", color: DS.Color.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("اسم العائلة", "Family Name"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                            TextField(L10n.t("اسم العائلة", "Family name"), text: $familyName)
                                .font(DS.Font.callout)
                                .foregroundColor(DS.Color.textPrimary)
                                .onChange(of: familyName) { _ in
                                    if familyName.count > 50 {
                                        familyName = String(familyName.prefix(50))
                                    }
                                }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.xs)

                    DSDivider()

                    // TODO: gender — re-enable when needed

                    // Phone field — بدون رمز الدولة
                    HStack(spacing: DS.Spacing.md) {
                        DSIcon("phone.fill", color: DS.Color.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("رقم الهاتف", "Phone Number"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                            PhoneNumberTextField(
                                text: $phoneNumber,
                                placeholder: L10n.t("اختياري", "Optional"),
                                font: .systemFont(ofSize: 15),
                                keyboardType: .phonePad,
                                maxLength: selectedPhoneCountry.maxDigits
                            )
                            .frame(height: 30)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.xs)

                    DSDivider()

                    // Birth date
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        HStack(spacing: DS.Spacing.md) {
                            DSIcon("calendar", color: DS.Color.accent)
                            Text(L10n.t("تاريخ الميلاد", "Birth Date"))
                                .font(DS.Font.callout)
                                .foregroundColor(DS.Color.textPrimary)
                        }
                        StableWheelDatePicker(selection: $birthDate, in: ...Date())
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.xs)

                    DSDivider()

                    // Deceased toggle
                    HStack(spacing: DS.Spacing.md) {
                        DSIcon("leaf.fill", color: DS.Color.error)
                        Toggle(L10n.t("متوفى", "Deceased"), isOn: $isDeceased)
                            .font(DS.Font.callout)
                            .tint(DS.Color.error)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.xs)
                    .animation(.default, value: isDeceased)

                    if isDeceased {
                        DSDivider()
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            HStack(spacing: DS.Spacing.md) {
                                DSIcon("calendar", color: DS.Color.error)
                                Text(L10n.t("تاريخ الوفاة", "Death Date"))
                                    .font(DS.Font.callout)
                                    .foregroundColor(DS.Color.textPrimary)
                            }
                            StableWheelDatePicker(selection: $deathDate, in: ...Date())
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.xs)
                    }
                }
            }
    }

    private var submitButton: some View {
        DSPrimaryButton(
            L10n.t("إضافة الابن", "Add Child"),
            icon: "checkmark.circle.fill",
            isLoading: memberVM.isLoading,
            action: saveChild
        )
        .opacity(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
        .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || memberVM.isLoading)
    }

    private func saveChild() {
        Task {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")

            let birthDateString: String? = formatter.string(from: birthDate)
            let deathDateString: String? = isDeceased ? formatter.string(from: deathDate) : nil

            let childId = await memberVM.addChild(
                firstNameOnly: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                phoneNumber: KuwaitPhone.normalizedForStorage(
                    country: selectedPhoneCountry,
                    rawLocalDigits: phoneNumber
                ) ?? "",
                birthDate: birthDateString,
                fatherId: member.id,
                isDeceased: isDeceased,
                deathDate: deathDateString,
                gender: selectedGender
            )

            guard let childId else {
                Log.error("فشل في إضافة الابن")
                errorMessage = L10n.t("فشل في إضافة الابن. حاول مرة أخرى.", "Failed to add child. Please try again.")
                showErrorAlert = true
                return
            }

            if let image = selectedUIImage {
                await memberVM.uploadAvatar(image: image, for: childId)
            }

            await memberVM.fetchChildren(for: member.id)
            showSuccessAlert = true
        }
    }
}
