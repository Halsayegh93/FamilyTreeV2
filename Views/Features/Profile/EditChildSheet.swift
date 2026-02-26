import SwiftUI
import PhotosUI
import UIKit

struct EditChildSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let member: FamilyMember

    @State private var firstName: String = ""
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var phoneNumber: String = ""
    @State private var hasBirthDate: Bool = false
    @State private var birthDate: Date = Date()
    @State private var isDeceased: Bool = false
    @State private var hasDeathDate: Bool = false
    @State private var deathDate: Date = Date()
    @State private var selectedImageItem: PhotosPickerItem? = nil
    @State private var selectedUIImage: UIImage? = nil
    @State private var showSuccessAlert = false

    private var cardBackground: Color {
        colorScheme == .dark ? DS.Color.surface : .white
    }

    private var fieldBackground: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.1)
        : DS.Color.surfaceElevated
    }

    private var fieldTextColor: Color {
        colorScheme == .dark ? .white : DS.Color.textPrimary
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.lg) {
                        heroHeader
                        basicInfoCard
                        statusCard
                        submitButton
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.xxl)
                }
            }
            .navigationTitle("تعديل بيانات الابن")
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
        .alert("تم الحفظ", isPresented: $showSuccessAlert) {
            Button("موافق") { dismiss() }
        } message: {
            Text("تم تحديث بيانات الابن بنجاح.")
        }
    }

    private var heroHeader: some View {
        VStack(spacing: DS.Spacing.md) {
            PhotosPicker(selection: $selectedImageItem, matching: .images) {
                ZStack {
                    // Gradient ring with glow shadow
                    Circle()
                        .fill(DS.Color.gradientPrimary)
                        .frame(width: 112, height: 112)
                        .dsGlowShadow()

                    Circle()
                        .fill(cardBackground)
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
                        // Camera icon in gradient circle
                        ZStack {
                            Circle()
                                .fill(DS.Color.gradientPrimary)
                                .frame(width: 50, height: 50)
                            Image(systemName: "camera.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Text("تغيير الصورة الشخصية (اختياري)")
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.lg)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
        .overlay(alignment: .top) {
            // Gradient top accent line
            RoundedRectangle(cornerRadius: DS.Radius.xl)
                .fill(DS.Color.gradientPrimary)
                .frame(height: 3)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: DS.Radius.xl,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: DS.Radius.xl
                    )
                )
        }
        .dsCardShadow()
    }

    private var basicInfoCard: some View {
        VStack(spacing: DS.Spacing.md) {
            HStack {
                DSIcon("person.text.rectangle", color: DS.Color.primary, size: DS.Icon.sizeSm, iconSize: 14)
                Text("البيانات الأساسية")
                    .font(DS.Font.calloutBold)
                Spacer()
            }

            fieldRow(title: "الاسم الأول", icon: "person.fill") {
                TextField("اسم الابن", text: $firstName)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(fieldTextColor)
            }

            fieldRow(title: "رقم الهاتف", icon: "phone.fill") {
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
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(DS.Color.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(fieldBackground)
                        .cornerRadius(DS.Radius.sm)
                    }

                    TextField("اختياري", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(fieldTextColor)
                }
                .onChange(of: phoneNumber) { _, newValue in
                    phoneNumber = KuwaitPhone.userTypedDigits(newValue, maxDigits: selectedPhoneCountry.maxDigits)
                }
                .onChange(of: selectedPhoneCountry) { _, newCountry in
                    phoneNumber = KuwaitPhone.userTypedDigits(phoneNumber, maxDigits: newCountry.maxDigits)
                }
                .environment(\.layoutDirection, .leftToRight)
            }

            Toggle("تاريخ الميلاد معروف", isOn: $hasBirthDate)
                .font(DS.Font.callout)
                .tint(DS.Color.primary)

            if hasBirthDate {
                DatePicker("تاريخ الميلاد", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "en_US"))
            }
        }
        .padding(DS.Spacing.lg)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: DS.Radius.xl)
                .fill(DS.Color.gradientPrimary)
                .frame(height: 3)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: DS.Radius.xl,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: DS.Radius.xl
                    )
                )
        }
        .dsCardShadow()
    }

    private var statusCard: some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack {
                DSIcon("heart.text.square", color: DS.Color.primary, size: DS.Icon.sizeSm, iconSize: 14)
                Text("الحالة")
                    .font(DS.Font.calloutBold)
                Spacer()
            }

            Toggle("متوفى", isOn: $isDeceased.animation())
                .font(DS.Font.callout)
                .tint(DS.Color.primary)

            if isDeceased {
                Toggle("تاريخ الوفاة معروف", isOn: $hasDeathDate)
                    .font(DS.Font.callout)
                    .tint(DS.Color.primary)

                if hasDeathDate {
                    DatePicker("تاريخ الوفاة", selection: $deathDate, in: ...Date(), displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "en_US"))
                }
            }
        }
        .padding(DS.Spacing.lg)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: DS.Radius.xl)
                .fill(DS.Color.gradientPrimary)
                .frame(height: 3)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: DS.Radius.xl,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: DS.Radius.xl
                    )
                )
        }
        .dsCardShadow()
    }

    private var submitButton: some View {
        DSPrimaryButton(
            "حفظ التعديلات",
            icon: "checkmark.circle.fill",
            isLoading: authVM.isLoading,
            action: saveChanges
        )
        .opacity(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
        .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authVM.isLoading)
    }

    private func fieldRow<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Color.primary)
                Text(title)
                    .font(DS.Font.caption1)
                    .foregroundColor(fieldTextColor)
                Spacer()
            }
            content()
                .font(DS.Font.body)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.md)
                .background(fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
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
            hasBirthDate = true
            birthDate = parsed
        } else {
            hasBirthDate = false
        }

        if let death = member.deathDate, !death.isEmpty, let parsed = formatter.date(from: death) {
            hasDeathDate = true
            deathDate = parsed
        } else {
            hasDeathDate = false
        }
    }

    private func saveChanges() {
        Task {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")

            let birthDateString: String? = hasBirthDate ? formatter.string(from: birthDate) : nil
            let deathDateString: String? = (isDeceased && hasDeathDate) ? formatter.string(from: deathDate) : nil

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
