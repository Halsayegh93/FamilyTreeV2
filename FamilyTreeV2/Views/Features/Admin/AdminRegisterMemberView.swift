import SwiftUI

struct AdminRegisterMemberView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @State private var fullName: String = ""
    @State private var selectedGender: String = "male"
    @State private var hasBirthDate: Bool = false
    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var phoneNumber: String = ""
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var showingAlert = false
    @State private var showingSuccess = false

    // Animation states
    @State private var headerScale: CGFloat = 0.8
    @State private var headerOpacity: CGFloat = 0
    @State private var cardsAppeared = false

    /// عدد أجزاء الاسم المدخل
    private var nameParts: [String] {
        fullName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            // Decorative gradient background
            DSDecorativeBackground()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xxxl) {
                        // Header with gradient icon
                        headerSection
                            .scaleEffect(headerScale)
                            .opacity(headerOpacity)

                        VStack(spacing: DS.Spacing.xl) {
                            // Full name field (5-part)
                            nameFieldSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 20)

                            // Name parts counter hint + family name
                            namePartsHint
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
        .alert(L10n.t("الاسم غير مكتمل", "Incomplete Name"), isPresented: $showingAlert) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) { }
        } message: {
            Text(L10n.t("يرجى كتابة الاسم الخماسي كاملاً (الاسم الأول، اسم الأب، اسم الجد، اسم الجد الثاني، اسم العائلة).", "Please enter your full 5-part name (first, father, grandfather, great-grandfather, family name)."))
        }
        .alert(L10n.t("تم التسجيل", "Registered"), isPresented: $showingSuccess) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) { dismiss() }
        } message: {
            Text(L10n.t("تمت إضافة العضو بنجاح.", "Member added successfully."))
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
        .padding(.top, DS.Spacing.xl)
    }

    // MARK: - Name Field Section
    private var nameFieldSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSSectionHeader(title: L10n.t("الاسم الخماسي الكامل", "Full 5-Part Name"), icon: "person.fill")
                .font(DS.Font.title3)

            DSCard {
                HStack(spacing: DS.Spacing.md) {
                    DSIcon("person.fill", color: DS.Color.primary)
                    TextField(L10n.t("الاسم الأول + الأب + الجد + الجد الثاني + العائلة", "First Father Grand-Father Great-Grand Family"), text: $fullName)
                        .font(DS.Font.body)
                        .multilineTextAlignment(L10n.isArabic ? .leading : .trailing)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
            }
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl)
                    .stroke(DS.Color.gradientPrimary, lineWidth: 1)
                    .opacity(0.3)
            )
        }
    }

    // MARK: - Name Parts Hint
    private var namePartsHint: some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                let count = nameParts.count
                let isComplete = count >= 5

                Image(systemName: isComplete ? "checkmark.circle.fill" : "info.circle.fill")
                    .font(DS.Font.scaled(14))
                    .foregroundColor(isComplete ? DS.Color.success : DS.Color.warning)

                Text(L10n.t(
                    "عدد أجزاء الاسم: \(count) من 5",
                    "Name parts: \(count) of 5"
                ))
                .font(DS.Font.caption1)
                .foregroundColor(isComplete ? DS.Color.success : DS.Color.warning)

                Spacer()

                if isComplete {
                    Text(L10n.t("مكتمل", "Complete"))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.success)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(DS.Color.success.opacity(0.1))
                        .cornerRadius(DS.Radius.sm)
                }
            }

            // عرض اسم العائلة
            if nameParts.count >= 5 {
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("house.fill", color: DS.Color.neonPurple, size: 14)
                    Text(L10n.t("اسم العائلة:", "Family Name:"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                    Text(nameParts.last ?? "")
                        .font(DS.Font.caption1)
                        .fontWeight(.semibold)
                        .foregroundColor(DS.Color.textPrimary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, DS.Spacing.sm)
    }

    // MARK: - Gender Section
    private var genderSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSSectionHeader(title: L10n.t("الجنس", "Gender"), icon: "person.2.fill")
                .font(DS.Font.title3)

            DSCard {
                HStack(spacing: DS.Spacing.md) {
                    DSIcon("person.2.fill", color: DS.Color.neonCyan)

                    Picker("", selection: $selectedGender) {
                        Text(L10n.t("ذكر", "Male")).tag("male")
                        Text(L10n.t("أنثى", "Female")).tag("female")
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
            }
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl)
                    .stroke(DS.Color.gradientAccent, lineWidth: 1)
                    .opacity(0.3)
            )
        }
    }

    // MARK: - Birth Date Section
    private var birthDateSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSSectionHeader(title: L10n.t("تاريخ الميلاد", "Birth Date"), icon: "calendar")
                .font(DS.Font.title3)

            DSCard {
                VStack(spacing: 0) {
                    HStack(spacing: DS.Spacing.md) {
                        DSIcon("calendar.badge.checkmark", color: DS.Color.primary)
                        Text(L10n.t("تاريخ الميلاد متوفر", "Birth date available"))
                            .font(DS.Font.body)
                            .foregroundColor(DS.Color.textSecondary)
                        Spacer()
                        Toggle("", isOn: $hasBirthDate.animation())
                            .labelsHidden()
                            .tint(DS.Color.primary)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)

                    if hasBirthDate {
                        DSDivider()
                        HStack(spacing: DS.Spacing.md) {
                            DSIcon("calendar", color: DS.Color.neonPurple)
                            Text(L10n.t("اختر التاريخ", "Pick Date"))
                                .font(DS.Font.body)
                                .foregroundColor(DS.Color.textSecondary)
                            Spacer()
                            DatePicker("", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                                .labelsHidden()
                                .environment(\.locale, Locale(identifier: "en_US"))
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.md)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl)
                    .stroke(DS.Color.gradientAccent, lineWidth: 1)
                    .opacity(0.3)
            )
        }
    }

    // MARK: - Phone Section
    private var phoneSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSSectionHeader(title: L10n.t("رقم الهاتف (اختياري)", "Phone Number (Optional)"), icon: "phone.fill")
                .font(DS.Font.title3)

            DSCard {
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
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
                .onChange(of: phoneNumber) { _, newValue in
                    phoneNumber = KuwaitPhone.userTypedDigits(newValue, maxDigits: selectedPhoneCountry.maxDigits)
                }
                .onChange(of: selectedPhoneCountry) { _, newCountry in
                    phoneNumber = KuwaitPhone.userTypedDigits(phoneNumber, maxDigits: newCountry.maxDigits)
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl)
                    .stroke(DS.Color.gradientPrimary, lineWidth: 1)
                    .opacity(0.3)
            )
        }
    }

    // MARK: - Submit Button
    private var submitButton: some View {
        VStack(spacing: DS.Spacing.md) {
            let isDisabled = nameParts.count < 5 || authVM.isLoading
            DSPrimaryButton(
                L10n.t("إضافة العضو", "Add Member"),
                icon: "person.badge.plus",
                isLoading: authVM.isLoading,
                useGradient: !isDisabled,
                color: isDisabled ? .gray : DS.Color.primary
            ) {
                if nameParts.count < 5 {
                    showingAlert = true
                } else {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    formatter.locale = Locale(identifier: "en_US")

                    let first = nameParts[0]
                    let full = nameParts.joined(separator: " ")
                    let birthStr = hasBirthDate ? formatter.string(from: birthDate) : nil
                    let storedPhone = KuwaitPhone.normalizedForStorage(
                        country: selectedPhoneCountry,
                        rawLocalDigits: phoneNumber
                    )

                    Task {
                        let success = await authVM.adminAddMember(
                            fullName: full,
                            firstName: first,
                            birthDate: birthStr,
                            gender: selectedGender,
                            phoneNumber: storedPhone
                        )
                        if success {
                            showingSuccess = true
                        }
                    }
                }
            }
            .disabled(isDisabled)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xxxl)
        }
    }
}
