import SwiftUI

struct RegistrationView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var fullName: String = ""
    @State private var familyName: String = ""
    @StateObject private var familyNamesVM = FamilyNamesViewModel()
    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var selectedGender: String = "male"
    @State private var selectedImage: UIImage? = nil

    // Animation states
    @State private var headerScale: CGFloat = 0.8
    @State private var headerOpacity: CGFloat = 0
    @State private var cardsAppeared = false
    @State private var hasAttemptedSubmit = false
    @State private var showConfirmSubmit = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DS.Color.primary.opacity(0.06), DS.Color.background],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                topBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xl) {
                        // الصورة الشخصية — في الأعلى مثل حسابي
                        photoSection
                            .scaleEffect(headerScale)
                            .opacity(headerOpacity)

                        // العنوان
                        VStack(spacing: DS.Spacing.sm) {
                            Text(L10n.t("عائلة المحمدعلي", "Al-Mohammadali Family"))
                                .font(DS.Font.title1)
                                .fontWeight(.black)
                                .foregroundColor(DS.Color.textPrimary)

                            Text(L10n.t("أكمل بياناتك للانضمام", "Complete profile to join"))
                                .font(DS.Font.callout)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                        .opacity(headerOpacity)

                        // الحقول
                        VStack(spacing: DS.Spacing.md) {
                            nameFieldSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 20)

                            familyNameSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 25)

                            birthDateSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 30)

                            // TODO: gender — re-enable when needed
                            // genderSection
                            //     .opacity(cardsAppeared ? 1 : 0)
                            //     .offset(y: cardsAppeared ? 0 : 35)
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // زر الإرسال
                        submitButton
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 40)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .alert(
            L10n.t("تعذّر التسجيل", "Registration Failed"),
            isPresented: Binding(
                get: { authVM.registrationError != nil },
                set: { if !$0 { authVM.registrationError = nil } }
            )
        ) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) { authVM.registrationError = nil }
        } message: {
            Text(authVM.registrationError ?? "")
        }
        .task { await familyNamesVM.fetch() }
        .onAppear {
            Log.info("[REGISTRATION] RegistrationView ظهرت — البروفايل غير موجود. phone=\(Log.masked(authVM.phoneNumber))")
            withAnimation(DS.Anim.elastic.delay(0.2)) {
                headerScale = 1.0
                headerOpacity = 1.0
            }
            withAnimation(DS.Anim.smooth.delay(0.5)) {
                cardsAppeared = true
            }
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            // كان مكتوبًا «رجوع» لكنه يسجّل الخروج فعليًا — تسمية صادقة بدل الطرد الصامت
            Button(action: { Task { await authVM.signOut() } }) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(DS.Font.scaled(13, weight: .bold))
                    Text(L10n.t("تسجيل الخروج", "Sign out"))
                }
                .font(DS.Font.subheadline)
                .foregroundColor(DS.Color.textSecondary)
            }
            Spacer()
        }
        .padding(DS.Spacing.lg)
        .background(DS.Color.surface.opacity(0.95))
        .dsSubtleShadow()
    }

    // MARK: - Photo Section — كاميرا على الصورة مباشرة
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
                "Will be used as your photo in the family tree"
            ))
            .font(DS.Font.caption1)
            .foregroundColor(DS.Color.textTertiary)
        }
        .padding(.top, DS.Spacing.xl)
    }

    // MARK: - Name Field — الاسم الرباعي
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

    // MARK: - Family Name
    /// اختيار العائلة — بنفس هيئة حقل «الاسم الرباعي» حرفياً (أيقونة + عنوان
    /// + قيمة) فتبدو كل الحقول قطعة واحدة.
    private var familyNameSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Menu {
                ForEach(familyNamesVM.activeNames, id: \.self) { option in
                    Button {
                        familyName = option
                    } label: {
                        if familyName == option {
                            Label(option, systemImage: "checkmark")
                        } else {
                            Text(option)
                        }
                    }
                }
            } label: {
                HStack(spacing: DS.Spacing.md) {
                    DSIcon("person.2.fill", color: DS.Color.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 2) {
                            Text(L10n.t("العائلة", "Family"))
                                .foregroundColor(DS.Color.textSecondary)
                            Text("*").foregroundColor(DS.Color.error)
                        }
                        .font(DS.Font.caption1)

                        Text(familyName.isEmpty
                             ? L10n.t("اختر عائلتك", "Choose your family")
                             : familyName)
                            .font(DS.Font.body)
                            .foregroundColor(familyName.isEmpty
                                             ? DS.Color.textTertiary
                                             : DS.Color.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if familyNamesVM.isLoading {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(DS.Font.scaled(12, weight: .semibold))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(SwiftUI.Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hasAttemptedSubmit && familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError(L10n.t("اختيار العائلة مطلوب", "Choosing a family is required"))
            }
        }
    }

    // MARK: - Birth Date
    private var birthDateSection: some View {
        DSDateField(
            label: L10n.t("تاريخ الميلاد", "Birth Date"),
            date: $birthDate,
            range: ...Date(),
            // نفس مقاسات نصوص حقلي الاسم والعائلة
            labelFont: DS.Font.caption1,
            valueFont: DS.Font.body
        )
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        // نفس هيئة حقل «الاسم الرباعي» — مادة زجاجية وحدّ أبيض خفيف
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(SwiftUI.Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Gender
    private var genderSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.md) {
                DSIcon("figure.dress.line.vertical.figure", color: DS.Color.info)

                Text(L10n.t("الجنس", "Gender"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)

                Spacer()

                Picker("", selection: $selectedGender) {
                    Text(L10n.t("ذكر", "Male")).tag("male")
                    Text(L10n.t("أنثى", "Female")).tag("female")
                }
                .pickerStyle(.menu)
                .tint(DS.Color.primary)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.inactiveBorder, lineWidth: 1)
            )

            // ملاحظة الربط
            Text(L10n.t(
                "سيتم إضافة اسم العائلة (المحمدعلي) تلقائياً كاسم أخير",
                "The family name (Al-Mohammad Ali) will be added automatically as last name"
            ))
            .font(DS.Font.caption1)
            .foregroundColor(DS.Color.textTertiary)
            .padding(.leading, DS.Spacing.sm)
        }
    }

    // MARK: - Submit Button
    private var submitButton: some View {
        VStack(spacing: DS.Spacing.sm) {
            let trimmedFull = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedFamily = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
            // Validation أقوى: طول 2-50 + على الأقل حرفان أبجديان (يرفض "12" أو "...")
            let fullLetterCount = trimmedFull.filter { $0.isLetter }.count
            let familyLetterCount = trimmedFamily.filter { $0.isLetter }.count
            let isValid = trimmedFull.count >= 2 && trimmedFull.count <= 50 && fullLetterCount >= 2
                       && trimmedFamily.count >= 2 && trimmedFamily.count <= 50 && familyLetterCount >= 2
            let isDisabled = !isValid || authVM.isLoading

            DSPrimaryButton(
                L10n.t("إرسال طلب الانضمام", "Submit Join Request"),
                icon: "paperplane.fill",
                isLoading: authVM.isLoading,
                useGradient: !isDisabled,
                color: isDisabled ? DS.Color.inactive : DS.Color.primary
            ) {
                withAnimation(DS.Anim.snappy) { hasAttemptedSubmit = true }
                guard isValid else { return }
                showConfirmSubmit = true
            }
            .disabled(authVM.isLoading)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xxl)
            .confirmationDialog(
                L10n.t("تأكيد إرسال الطلب", "Confirm Submission"),
                isPresented: $showConfirmSubmit,
                titleVisibility: .visible
            ) {
                Button(L10n.t("إرسال", "Submit")) {
                    Task {
                        await authVM.registerNewUser(
                            firstName: trimmedFull,
                            familyName: trimmedFamily,
                            birthDate: birthDate,
                            gender: selectedGender,
                            avatarImage: selectedImage
                        )
                    }
                }
                Button(L10n.t("مراجعة البيانات", "Review"), role: .cancel) {}
            } message: {
                Text(L10n.t(
                    "اسمك: \(trimmedFull) \(trimmedFamily)\nسيُرسل طلبك للإدارة وتنتظر الموافقة.",
                    "Name: \(trimmedFull) \(trimmedFamily)\nYour request will be sent to admins for approval."
                ))
            }
        }
    }

    // MARK: - Validation Error
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
