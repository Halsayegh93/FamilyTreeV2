import SwiftUI
import PhotosUI
import UIKit

struct AddChildSheet: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss

    let member: FamilyMember

    @State private var firstName: String = ""
    @State private var familyName: String = ""
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

                DSDecorativeBackground()

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
    }

    private var heroHeader: some View {
        DSProfilePhotoPicker(
            selectedImage: $selectedUIImage
        )
        .padding(.horizontal, DS.Spacing.lg)
    }

    private var basicInfoCard: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("المعلومات الشخصية", "Personal Info"),
                icon: "person.text.rectangle"
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
                                .onChange(of: firstName) {
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
                        DSIcon("person.2.fill", color: DS.Color.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("اسم العائلة", "Family Name"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                            TextField(L10n.t("اسم العائلة", "Family name"), text: $familyName)
                                .font(DS.Font.callout)
                                .foregroundColor(DS.Color.textPrimary)
                                .onChange(of: familyName) {
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

                    // Gender picker
                    HStack(spacing: DS.Spacing.md) {
                        DSIcon(selectedGender == "female" ? "figure.stand.dress" : "person.fill", color: selectedGender == "female" ? DS.Color.neonPink : DS.Color.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("الجنس", "Gender"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                            HStack(spacing: 0) {
                                Button {
                                    withAnimation(DS.Anim.snappy) { selectedGender = "male" }
                                } label: {
                                    Text(L10n.t("ذكر", "Male"))
                                        .font(DS.Font.caption1)
                                        .fontWeight(.bold)
                                        .foregroundColor(selectedGender == "male" ? .white : DS.Color.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, DS.Spacing.sm)
                                        .background(selectedGender == "male" ? DS.Color.primary : DS.Color.surface)
                                }

                                Button {
                                    withAnimation(DS.Anim.snappy) { selectedGender = "female" }
                                } label: {
                                    Text(L10n.t("أنثى", "Female"))
                                        .font(DS.Font.caption1)
                                        .fontWeight(.bold)
                                        .foregroundColor(selectedGender == "female" ? .white : DS.Color.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, DS.Spacing.sm)
                                        .background(selectedGender == "female" ? DS.Color.neonPink : DS.Color.surface)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.sm)
                                    .stroke(DS.Color.textTertiary.opacity(0.2), lineWidth: 1)
                            )
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.xs)

                    DSDivider()

                    // Phone field
                    HStack(spacing: DS.Spacing.md) {
                        DSIcon("phone.fill", color: DS.Color.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("رقم الهاتف", "Phone Number"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                            HStack(spacing: DS.Spacing.sm) {
                                Menu {
                                    ForEach(KuwaitPhone.supportedCountries) { country in
                                        Button {
                                            selectedPhoneCountry = country
                                        } label: {
                                            Text("\(country.flag) \(country.nameArabic) \(country.dialingCode)")
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(selectedPhoneCountry.flag)
                                        Text(selectedPhoneCountry.dialingCode).font(DS.Font.caption1)
                                        Image(systemName: "chevron.down")
                                            .font(DS.Font.scaled(10, weight: .semibold))
                                    }
                                    .foregroundColor(DS.Color.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(DS.Color.surface)
                                    .cornerRadius(DS.Radius.sm)
                                }

                                TextField(L10n.t("اختياري", "Optional"), text: $phoneNumber)
                                    .keyboardType(.phonePad)
                                    .foregroundStyle(Color(UIColor.label))
                            }
                            .onChange(of: phoneNumber) { _, newValue in
                                phoneNumber = KuwaitPhone.userTypedDigits(newValue, maxDigits: selectedPhoneCountry.maxDigits)
                            }
                            .onChange(of: selectedPhoneCountry) { _, newCountry in
                                phoneNumber = KuwaitPhone.userTypedDigits(phoneNumber, maxDigits: newCountry.maxDigits)
                            }
                            .environment(\.layoutDirection, .leftToRight)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.xs)

                    DSDivider()

                    // Birth date
                    HStack(spacing: DS.Spacing.md) {
                        DSIcon("calendar", color: DS.Color.info)
                        DatePicker(L10n.t("تاريخ الميلاد", "Birth Date"), selection: $birthDate, in: ...Date(), displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: L10n.isArabic ? "ar" : "en_US"))
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
                        HStack(spacing: DS.Spacing.md) {
                            DSIcon("calendar", color: DS.Color.error)
                            DatePicker(L10n.t("تاريخ الوفاة", "Death Date"), selection: $deathDate, in: ...Date(), displayedComponents: .date)
                                .environment(\.locale, Locale(identifier: L10n.isArabic ? "ar" : "en_US"))
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
