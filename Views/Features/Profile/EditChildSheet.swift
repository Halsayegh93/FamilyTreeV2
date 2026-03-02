import SwiftUI
import PhotosUI
import UIKit

struct EditChildSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    let member: FamilyMember

    @State private var firstName: String = ""
    @State private var familyName: String = ""
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var phoneNumber: String = ""
    @State private var birthDate: Date = Date()
    @State private var isDeceased: Bool = false
    @State private var deathDate: Date = Date()
    @State private var selectedImageItem: PhotosPickerItem? = nil
    @State private var selectedUIImage: UIImage? = nil
    @State private var showSuccessAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                DSDecorativeBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xxl) {
                        heroHeader
                        basicInfoCard
                        submitButton
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.xxl)
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
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onChange(of: selectedImageItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run { selectedUIImage = image }
                }
            }
        }
        .alert(L10n.t("تم الحفظ", "Saved"), isPresented: $showSuccessAlert) {
            Button(L10n.t("موافق", "OK")) { dismiss() }
        } message: {
            Text(L10n.t("تم تحديث بيانات الابن بنجاح.", "Child info updated successfully."))
        }
    }

    private var heroHeader: some View {
        DSCard(padding: 0) {
            VStack(spacing: DS.Spacing.md) {
                PhotosPicker(selection: $selectedImageItem, matching: .images) {
                    ZStack {
                        Circle()
                            .fill(DS.Color.gradientPrimary)
                            .frame(width: 112, height: 112)
                            .dsGlowShadow()

                        Circle()
                            .fill(DS.Color.surface)
                            .frame(width: 102, height: 102)

                        if let image = selectedUIImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 96, height: 96)
                                .clipShape(Circle())
                        } else if let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                        } else {
                            ZStack {
                                Circle()
                                    .fill(DS.Color.gradientPrimary)
                                    .frame(width: 50, height: 50)
                                Image(systemName: "camera.fill")
                                    .font(DS.Font.scaled(20, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Text(L10n.t("تغيير الصورة الشخصية (اختياري)", "Change Photo (optional)"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.lg)
        }
    }

    private var basicInfoCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSSectionHeader(
                title: L10n.t("البيانات الأساسية", "Basic Info"),
                icon: "person.text.rectangle"
            )

            DSCard(padding: 0) {
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
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)

                    DSDivider()

                    // Family name field
                    HStack(spacing: DS.Spacing.md) {
                        DSIcon("person.2.fill", color: DS.Color.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("اسم العائلة (اختياري)", "Family Name (optional)"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                            TextField(L10n.t("اسم العائلة", "Family name"), text: $familyName)
                                .font(DS.Font.callout)
                                .foregroundColor(DS.Color.textPrimary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)

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
                                        Text(selectedPhoneCountry.dialingCode).font(DS.Font.callout)
                                        Image(systemName: "chevron.down")
                                            .font(DS.Font.scaled(10, weight: .semibold))
                                    }
                                    .foregroundColor(DS.Color.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(DS.Color.surfaceElevated)
                                    .cornerRadius(DS.Radius.sm)
                                }

                                TextField(L10n.t("اختياري", "Optional"), text: $phoneNumber)
                                    .keyboardType(.phonePad)
                                    .foregroundColor(DS.Color.textPrimary)
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
                    .padding(.vertical, DS.Spacing.md)

                    DSDivider()

                    // Birth date
                    HStack(spacing: DS.Spacing.md) {
                        DSIcon("calendar", color: DS.Color.info)
                        DatePicker(L10n.t("تاريخ الميلاد", "Birth Date"), selection: $birthDate, in: ...Date(), displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "en_US"))
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)

                    DSDivider()

                    // Deceased toggle
                    HStack(spacing: DS.Spacing.md) {
                        DSIcon("leaf.fill", color: DS.Color.error)
                        Toggle(L10n.t("متوفى", "Deceased"), isOn: $isDeceased.animation())
                            .font(DS.Font.callout)
                            .tint(DS.Color.error)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)

                    if isDeceased {
                        DSDivider()
                        HStack(spacing: DS.Spacing.md) {
                            DSIcon("calendar", color: DS.Color.error)
                            DatePicker(L10n.t("تاريخ الوفاة", "Death Date"), selection: $deathDate, in: ...Date(), displayedComponents: .date)
                                .environment(\.locale, Locale(identifier: "en_US"))
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.sm)
                    }
                }
            }
        }
    }

    private var submitButton: some View {
        DSPrimaryButton(
            L10n.t("حفظ التعديلات", "Save Changes"),
            icon: "checkmark.circle.fill",
            isLoading: authVM.isLoading,
            action: saveChanges
        )
        .opacity(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
        .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authVM.isLoading)
    }

    private func setupData() {
        firstName = member.firstName
        let detectedPhone = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
        selectedPhoneCountry = detectedPhone.country
        phoneNumber = detectedPhone.localDigits
        isDeceased = member.isDeceased ?? false

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

    private func saveChanges() {
        Task {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")

            let birthDateString: String? = formatter.string(from: birthDate)
            let deathDateString: String? = isDeceased ? formatter.string(from: deathDate) : nil

            await authVM.updateChildData(
                member: member,
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                phoneNumber: KuwaitPhone.normalizedForStorage(
                    country: selectedPhoneCountry,
                    rawLocalDigits: phoneNumber
                ) ?? "",
                birthDate: birthDateString,
                isDeceased: isDeceased,
                deathDate: deathDateString
            )

            if let image = selectedUIImage {
                await authVM.uploadAvatar(image: image, for: member.id)
            }

            if !authVM.isLoading {
                showSuccessAlert = true
            }
        }
    }
}
