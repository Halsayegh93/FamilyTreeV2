import SwiftUI

struct AdminRegisterMemberView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss

    @State private var fullName: String = ""
    @State private var familyName: String = ""
    @State private var selectedGender: String = "male"
    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var selectedImage: UIImage? = nil
    @State private var phoneNumber: String = ""
    @State private var hasAttemptedSubmit = false
    @AppStorage("lastAuthDialingCode") private var lastAuthDialingCode: String = ""
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var showingSuccess = false
    @State private var showingError = false

    // Animation states
    @State private var headerScale: CGFloat = 0.8
    @State private var headerOpacity: CGFloat = 0
    @State private var cardsAppeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DS.Color.primary.opacity(0.06), DS.Color.background],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xl) {
                        // الصورة الشخصية — في الأعلى مثل فورم التسجيل
                        photoSection
                            .scaleEffect(headerScale)
                            .opacity(headerOpacity)

                        // العنوان — نفس فورم التسجيل
                        VStack(spacing: DS.Spacing.sm) {
                            Text(L10n.t("عائلة المحمدعلي", "Al-Mohammadali Family"))
                                .font(DS.Font.title1)
                                .fontWeight(.black)
                                .foregroundColor(DS.Color.textPrimary)

                            Text(L10n.t("أدخل بيانات العضو الجديد", "Enter the new member's details"))
                                .font(DS.Font.callout)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                        .opacity(headerOpacity)

                        VStack(spacing: DS.Spacing.md) {
                            // الاسم الرباعي
                            nameFieldSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 20)

                            // اسم العائلة
                            familyNameSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 25)

                            // تاريخ الميلاد
                            birthDateSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 30)

                            // رقم الهاتف (خاص بالإدارة — اختياري)
                            phoneSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 33)
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // زر الإرسال
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
            Text(L10n.t("تعذر الإضافة. حاول مرة أخرى.", "Add failed. Try again."))
        }
        .onAppear {
            if !lastAuthDialingCode.isEmpty {
                selectedPhoneCountry = KuwaitPhone.countryForDialingCode(lastAuthDialingCode)
            }
            withAnimation(DS.Anim.elastic.delay(0.2)) {
                headerScale = 1.0
                headerOpacity = 1.0
            }
            withAnimation(DS.Anim.smooth.delay(0.5)) {
                cardsAppeared = true
            }
        }
    }

    // MARK: - Photo Section — كاميرا على الصورة مباشرة (نفس فورم التسجيل)
    private var photoSection: some View {
        VStack(spacing: DS.Spacing.xs) {
            DSProfilePhotoPicker(
                selectedImage: $selectedImage,
                enableCrop: true,
                cropShape: .circle,
                title: L10n.t("الصورة الشخصية", "Profile Photo"),
                trailing: L10n.t("اختياري", "Optional"),
                compactEmptyState: true
            )

            Text(L10n.t(
                "سوف تُستخدم كصورة في شجرة العائلة",
                "Will be used as the member's photo in the family tree"
            ))
            .font(DS.Font.caption1)
            .foregroundColor(DS.Color.textTertiary)
        }
        .padding(.top, DS.Spacing.xl)
    }

    // MARK: - Name Field Section — الاسم الرباعي (نفس فورم التسجيل)
    private var nameFieldSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DSTextField(
                label: L10n.t("الاسم الرباعي", "Full Name (4 parts)"),
                placeholder: L10n.t("محمد عبدالله علي أحمد", "Mohammad Abdullah Ali Ahmad"),
                text: $fullName,
                icon: "person.fill",
                iconColor: DS.Color.primary,
                required: true,
                hint: L10n.t("(باللغة العربية)", "(in Arabic)")
            )
            .onChange(of: fullName) { _ in
                if fullName.count > 100 {
                    fullName = String(fullName.prefix(100))
                }
            }

            if hasAttemptedSubmit && fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError(L10n.t("الاسم مطلوب", "Name is required"))
            }
        }
    }

    // MARK: - Family Name Section — نفس فورم التسجيل
    private var familyNameSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DSTextField(
                label: L10n.t("اسم العائلة", "Family Name"),
                placeholder: L10n.t("مثال: آل محمد علي", "e.g. Al-Mohammad Ali"),
                text: $familyName,
                icon: "person.2.fill",
                iconColor: DS.Color.accent,
                required: true
            )
            .onChange(of: familyName) { _ in
                if familyName.count > 50 {
                    familyName = String(familyName.prefix(50))
                }
            }

            if hasAttemptedSubmit && familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError(L10n.t("اسم العائلة مطلوب", "Family name is required"))
            }
        }
    }

    // MARK: - Birth Date Section — نفس فورم التسجيل
    private var birthDateSection: some View {
        DSDateField(
            label: L10n.t("تاريخ الميلاد", "Birth Date"),
            date: $birthDate,
            range: ...Date()
        )
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.inactiveBorder, lineWidth: 1)
        )
    }

    // MARK: - Phone Section — حقل موحّد مع كود الدولة على الجهة المقابلة
    private var phoneSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.md) {
                DSIcon("phone.fill", color: DS.Color.success)
                Text(L10n.t("رقم الهاتف (اختياري)", "Phone Number (Optional)"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                Spacer()
            }
            DSPhoneField(
                country: $selectedPhoneCountry,
                digits: $phoneNumber,
                placeholder: L10n.t("رقم الهاتف", "Phone Number")
            )
        }
    }

    // MARK: - Submit Button
    private var submitButton: some View {
        VStack(spacing: DS.Spacing.sm) {
            let trimmedFull = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedFamily = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
            // نفس Validation فورم التسجيل: 2-50 حرف + على الأقل حرفان أبجديان
            let fullLetterCount = trimmedFull.filter { $0.isLetter }.count
            let familyLetterCount = trimmedFamily.filter { $0.isLetter }.count
            let isValid = trimmedFull.count >= 2 && trimmedFull.count <= 50 && fullLetterCount >= 2
                       && trimmedFamily.count >= 2 && trimmedFamily.count <= 50 && familyLetterCount >= 2
            let isDisabled = !isValid || memberVM.isLoading
            DSPrimaryButton(
                L10n.t("إضافة العضو", "Add Member"),
                icon: "person.badge.plus",
                isLoading: memberVM.isLoading,
                useGradient: !isDisabled,
                color: isDisabled ? DS.Color.inactive : DS.Color.primary
            ) {
                withAnimation(DS.Anim.snappy) { hasAttemptedSubmit = true }
                guard isValid else { return }

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.locale = Locale(identifier: "en_US")

                let parts = trimmedFull.split(whereSeparator: \.isWhitespace).map(String.init)
                let first = parts.first ?? trimmedFull
                let birthStr = formatter.string(from: birthDate)
                let storedPhone = KuwaitPhone.normalizedForStorage(
                    country: selectedPhoneCountry,
                    rawLocalDigits: phoneNumber
                )

                Task {
                    let success = await memberVM.adminAddMember(
                        fullName: trimmedFull,
                        firstName: first,
                        birthDate: birthStr,
                        gender: selectedGender,
                        phoneNumber: storedPhone,
                        avatarImage: selectedImage
                    )
                    if success {
                        showingSuccess = true
                    } else {
                        showingError = true
                    }
                }
            }
            .disabled(memberVM.isLoading)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xxl)
        }
    }

    // MARK: - Validation Error — نفس فورم التسجيل
    private func validationError(_ text: String) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(DS.Font.caption2)
            Text(text)
                .font(DS.Font.caption1)
        }
        .foregroundColor(DS.Color.error)
        .padding(.leading, DS.Spacing.sm)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

}
