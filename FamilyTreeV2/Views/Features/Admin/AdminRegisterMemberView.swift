import SwiftUI

struct AdminRegisterMemberView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @State private var fullName: String = ""
    @State private var familyName: String = ""
    @State private var selectedGender: String = "male"
    @State private var hasBirthDate: Bool = false
    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var phoneNumber: String = ""
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var showingSuccess = false
    @State private var showingError = false

    // Animation states
    @State private var headerScale: CGFloat = 0.8
    @State private var headerOpacity: CGFloat = 0
    @State private var cardsAppeared = false

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            // Decorative gradient background
            DSDecorativeBackground()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xl) {
                        // Header with gradient icon
                        headerSection
                            .scaleEffect(headerScale)
                            .opacity(headerOpacity)

                        VStack(spacing: DS.Spacing.md) {
                            // Full name field (5-part)
                            nameFieldSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 20)

                            // Family name field
                            familyNameSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 25)

                            // Gender picker
                            genderSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 28)

                            // Birth date field
                            birthDateSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 30)

                            // Phone number
                            phoneSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 33)
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // Submit button
                        submitButton
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 50)
                    }
                }
            }
        }
        .navigationTitle(L10n.t("تسجيل عضو جديد", "Register New Member"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .alert(L10n.t("تم التسجيل", "Registered"), isPresented: $showingSuccess) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) { dismiss() }
        } message: {
            Text(L10n.t("تمت إضافة العضو بنجاح.", "Member added successfully."))
        }
        .alert(L10n.t("خطأ", "Error"), isPresented: $showingError) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(authVM.errorMessage ?? L10n.t("تعذر إضافة العضو. حاول مرة أخرى.", "Failed to add member. Please try again."))
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.2)) {
                headerScale = 1.0
                headerOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.7).delay(0.5)) {
                cardsAppeared = true
            }
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.08))
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 100, height: 100)

                Image(systemName: "person.badge.plus")
                    .font(DS.Font.scaled(42, weight: .bold))
                    .foregroundColor(.white)
            }
            .dsGlowShadow()

            Text(L10n.t("تسجيل عضو جديد", "Register New Member"))
                .font(DS.Font.title1)
                .foregroundColor(DS.Color.textPrimary)

            Text(L10n.t("أدخل بيانات العضو الجديد وسيتم إضافته مباشرة للشجرة", "Enter the new member's details and they will be added to the tree directly"))
                .font(DS.Font.subheadline)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, DS.Spacing.md)
    }

    // MARK: - Name Field Section
    private var nameFieldSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(title: L10n.t("الاسم الخماسي", "Full Name (5 parts)"), icon: "person.fill")

            HStack(spacing: DS.Spacing.sm) {
                DSIcon("person.fill", color: DS.Color.primary)
                TextField(L10n.t("مثال: حسن أحمد علي محمد السالم", "e.g. John Edward James Smith Jr"), text: $fullName)
                    .font(DS.Font.body)
                    .onChange(of: fullName) {
                        if fullName.count > 100 {
                            fullName = String(fullName.prefix(100))
                        }
                    }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
        }
    }

    // MARK: - Family Name Section
    private var familyNameSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(title: L10n.t("اسم العائلة", "Family Name"), icon: "person.2.fill")

            HStack(spacing: DS.Spacing.sm) {
                DSIcon("person.2.fill", color: DS.Color.accent)
                TextField(L10n.t("مثال: آل محمد علي", "e.g. Al-Mohammad Ali"), text: $familyName)
                    .font(DS.Font.body)
                    .onChange(of: familyName) {
                        if familyName.count > 50 {
                            familyName = String(familyName.prefix(50))
                        }
                    }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
        }
    }

    // MARK: - Gender Section
    private var genderSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(title: L10n.t("الجنس", "Gender"), icon: "figure.dress.line.vertical.figure")

            HStack(spacing: DS.Spacing.sm) {
                DSIcon("figure.dress.line.vertical.figure", color: DS.Color.neonPurple)

                Text(L10n.t("الجنس", "Gender"))
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textSecondary)

                Spacer()

                Menu {
                    Button {
                        selectedGender = "male"
                    } label: {
                        Label(L10n.t("ذكر", "Male"), systemImage: selectedGender == "male" ? "checkmark" : "")
                    }
                    Button {
                        selectedGender = "female"
                    } label: {
                        Label(L10n.t("أنثى", "Female"), systemImage: selectedGender == "female" ? "checkmark" : "")
                    }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(selectedGender == "male" ? L10n.t("ذكر", "Male") : L10n.t("أنثى", "Female"))
                            .font(DS.Font.body)
                            .foregroundColor(DS.Color.textPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.sm)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
        }
    }

    // MARK: - Birth Date Section
    private var birthDateSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(title: L10n.t("تاريخ الميلاد", "Birth Date"), icon: "calendar")

            VStack(spacing: 0) {
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("calendar.badge.checkmark", color: DS.Color.primary)
                    Text(L10n.t("تاريخ الميلاد متوفر", "Birth date available"))
                        .font(DS.Font.body)
                        .foregroundColor(DS.Color.textSecondary)
                    Spacer()
                    Toggle("", isOn: $hasBirthDate)
                        .labelsHidden()
                        .tint(DS.Color.primary)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .animation(.default, value: hasBirthDate)

                if hasBirthDate {
                    DSDivider()
                    HStack(spacing: DS.Spacing.sm) {
                        DSIcon("calendar", color: DS.Color.neonPurple)
                        Text(L10n.t("اختر التاريخ", "Pick Date"))
                            .font(DS.Font.body)
                            .foregroundColor(DS.Color.textSecondary)
                        Spacer()
                        DatePicker("", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "en_US"))
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                }
            }
        }
    }

    // MARK: - Phone Section
    private var phoneSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(title: L10n.t("رقم الهاتف (اختياري)", "Phone Number (Optional)"), icon: "phone.fill")

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
                    .padding(.vertical, 8)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.sm)
                }

                TextField(L10n.t("رقم الهاتف", "Phone Number"), text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .onChange(of: phoneNumber) { _, newValue in
                phoneNumber = KuwaitPhone.userTypedDigits(newValue, maxDigits: selectedPhoneCountry.maxDigits)
            }
            .onChange(of: selectedPhoneCountry) { _, newCountry in
                phoneNumber = KuwaitPhone.userTypedDigits(phoneNumber, maxDigits: newCountry.maxDigits)
            }
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    // MARK: - Submit Button
    private var submitButton: some View {
        VStack(spacing: DS.Spacing.sm) {
            let trimmedFull = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedFamily = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
            let isDisabled = trimmedFull.isEmpty || trimmedFamily.isEmpty || authVM.isLoading
            DSPrimaryButton(
                L10n.t("إضافة العضو", "Add Member"),
                icon: "person.badge.plus",
                isLoading: authVM.isLoading,
                useGradient: !isDisabled,
                color: isDisabled ? .gray : DS.Color.primary
            ) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.locale = Locale(identifier: "en_US")

                let parts = trimmedFull.split(whereSeparator: \.isWhitespace).map(String.init)
                let first = parts.first ?? trimmedFull
                let birthStr = hasBirthDate ? formatter.string(from: birthDate) : nil
                let storedPhone = KuwaitPhone.normalizedForStorage(
                    country: selectedPhoneCountry,
                    rawLocalDigits: phoneNumber
                )

                Task {
                    let success = await authVM.adminAddMember(
                        fullName: trimmedFull,
                        firstName: first,
                        birthDate: birthStr,
                        gender: selectedGender,
                        phoneNumber: storedPhone
                    )
                    if success {
                        showingSuccess = true
                    } else {
                        showingError = true
                    }
                }
            }
            .disabled(isDisabled)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xxl)
        }
    }
}
