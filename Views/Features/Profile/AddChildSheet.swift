import SwiftUI
import PhotosUI
import UIKit

struct AddChildSheet: View {
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
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

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
        .onChange(of: selectedImageItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run { selectedUIImage = image }
                }
            }
        }
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

                Text(L10n.t("الصورة الشخصية (اختياري)", "Profile Photo (optional)"))
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
                                    .background(DS.Color.surface)
                                    .cornerRadius(DS.Radius.sm)
                                }

                                TextField(L10n.t("اختياري", "Optional"), text: $phoneNumber)
                                    .keyboardType(.phonePad)
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
            L10n.t("إضافة الابن", "Add Child"),
            icon: "checkmark.circle.fill",
            isLoading: authVM.isLoading,
            action: saveChild
        )
        .opacity(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
        .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authVM.isLoading)
    }

    private func saveChild() {
        Task {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")

            let birthDateString: String? = formatter.string(from: birthDate)
            let deathDateString: String? = isDeceased ? formatter.string(from: deathDate) : nil

            let childId = await authVM.addChild(
                firstNameOnly: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                phoneNumber: KuwaitPhone.normalizedForStorage(
                    country: selectedPhoneCountry,
                    rawLocalDigits: phoneNumber
                ) ?? "",
                birthDate: birthDateString,
                fatherId: member.id,
                isDeceased: isDeceased,
                deathDate: deathDateString,
                gender: nil
            )

            guard let childId else {
                Log.error("فشل في إضافة الابن")
                errorMessage = L10n.t("فشل في إضافة الابن. حاول مرة أخرى.", "Failed to add child. Please try again.")
                showErrorAlert = true
                return
            }

            if let image = selectedUIImage {
                await authVM.uploadAvatar(image: image, for: childId)
            }

            await authVM.fetchChildren(for: member.id)
            showSuccessAlert = true
        }
    }
}
