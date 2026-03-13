import SwiftUI

struct RegistrationView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var fullName: String = ""
    @State private var familyName: String = ""
    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var selectedGender: String = "male"
    @State private var selectedImage: UIImage? = nil

    // Animation states
    @State private var headerScale: CGFloat = 0.8
    @State private var headerOpacity: CGFloat = 0
    @State private var cardsAppeared = false
    @State private var hasAttemptedSubmit = false

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

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
                        VStack(spacing: DS.Spacing.xs) {
                            Text(L10n.t("إنشاء ملف تعريف", "Create Profile"))
                                .font(DS.Font.title1)
                                .foregroundColor(DS.Color.textPrimary)

                            Text(L10n.t("أكمل بياناتك للانضمام إلى العائلة", "Complete your info to join the family"))
                                .font(DS.Font.subheadline)
                                .foregroundColor(DS.Color.textSecondary)
                                .multilineTextAlignment(.center)
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

                            genderSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 35)
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
        .onAppear {
            Log.info("[REGISTRATION] RegistrationView ظهرت — البروفايل غير موجود. phone=\(authVM.phoneNumber), lastAuthPhone=\(UserDefaults.standard.string(forKey: "lastAuthPhone") ?? "empty")")
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
            Button(action: { Task { await authVM.signOut() } }) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: L10n.isArabic ? "chevron.right" : "chevron.left")
                        .font(DS.Font.scaled(13, weight: .bold))
                    Text(L10n.t("رجوع", "Back"))
                }
                .font(DS.Font.subheadline)
                .foregroundColor(DS.Color.primary)
            }
            Spacer()
        }
        .padding(DS.Spacing.lg)
        .background(DS.Color.surface.opacity(0.95))
        .dsSubtleShadow()
    }

    // MARK: - Photo Section — كاميرا على الصورة مباشرة
    private var photoSection: some View {
        DSProfilePhotoPicker(
            selectedImage: $selectedImage,
            enableCrop: true,
            cropShape: .circle,
            title: L10n.t("الصورة الشخصية", "Profile Photo"),
            trailing: L10n.t("اختياري", "Optional"),
            compactEmptyState: true
        )
        .padding(.top, DS.Spacing.xl)
    }

    // MARK: - Name Field — الاسم الرباعي
    private var nameFieldSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DSTextField(
                label: L10n.t("الاسم الرباعي", "Full Name (4 parts)"),
                placeholder: L10n.t("اسمك الرباعي", "Your full name"),
                text: $fullName,
                icon: "person.fill",
                iconColor: DS.Color.primary
            )
            .onChange(of: fullName) {
                if fullName.count > 100 {
                    fullName = String(fullName.prefix(100))
                }
            }

            // توضيح الاسم بالعربي
            Text(L10n.t(
                "مثال: محمد عبدالله علي أحمد",
                "Example: Mohammad Abdullah Ali Ahmad"
            ))
            .font(DS.Font.caption1)
            .foregroundColor(DS.Color.textTertiary)
            .padding(.leading, DS.Spacing.sm)

            if hasAttemptedSubmit && fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError(L10n.t("الاسم مطلوب", "Name is required"))
            }
        }
    }

    // MARK: - Family Name
    private var familyNameSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DSTextField(
                label: L10n.t("اسم العائلة", "Family Name"),
                placeholder: L10n.t("مثال: آل محمد علي", "e.g. Al-Mohammad Ali"),
                text: $familyName,
                icon: "person.2.fill",
                iconColor: DS.Color.accent
            )
            .onChange(of: familyName) {
                if familyName.count > 50 {
                    familyName = String(familyName.prefix(50))
                }
            }

            if hasAttemptedSubmit && familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError(L10n.t("اسم العائلة مطلوب", "Family name is required"))
            }
        }
    }

    // MARK: - Birth Date
    private var birthDateSection: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon("calendar", color: DS.Color.neonPurple)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("تاريخ الميلاد", "Birth Date"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)

                Text(L10n.t("اختر التاريخ", "Pick Date"))
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textSecondary)
            }

            Spacer()

            DatePicker("", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: L10n.isArabic ? "ar" : "en_US"))
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Gender
    private var genderSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.md) {
                DSIcon("figure.dress.line.vertical.figure", color: DS.Color.neonPurple)

                Text(L10n.t("الجنس", "Gender"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)

                Spacer()
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)

            HStack(spacing: DS.Spacing.sm) {
                genderButton(
                    title: L10n.t("ذكر", "Male"),
                    icon: "figure.stand",
                    value: "male",
                    gradient: DS.Color.gradientPrimary,
                    shadowColor: DS.Color.primary
                )

                genderButton(
                    title: L10n.t("أنثى", "Female"),
                    icon: "figure.stand.dress",
                    value: "female",
                    gradient: DS.Color.gradientAccent,
                    shadowColor: DS.Color.accent
                )
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.md)
        }
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    private func genderButton(title: String, icon: String, value: String, gradient: LinearGradient, shadowColor: Color) -> some View {
        Button {
            withAnimation(DS.Anim.snappy) { selectedGender = value }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(16, weight: .bold))
                Text(title)
                    .font(DS.Font.calloutBold)
            }
            .foregroundColor(selectedGender == value ? .white : DS.Color.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                Group {
                    if selectedGender == value {
                        AnyView(gradient)
                    } else {
                        AnyView(DS.Color.surface)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(
                        selectedGender == value ? Color.clear : Color.gray.opacity(0.15),
                        lineWidth: 1
                    )
            )
            .shadow(color: selectedGender == value ? shadowColor.opacity(0.2) : .clear, radius: 8, x: 0, y: 3)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Submit Button
    private var submitButton: some View {
        VStack(spacing: DS.Spacing.sm) {
            let trimmedFull = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedFamily = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
            let isDisabled = trimmedFull.isEmpty || trimmedFamily.isEmpty || authVM.isLoading

            DSPrimaryButton(
                L10n.t("إرسال طلب الانضمام", "Submit Join Request"),
                icon: "paperplane.fill",
                isLoading: authVM.isLoading,
                useGradient: !isDisabled,
                color: isDisabled ? .gray : DS.Color.primary
            ) {
                withAnimation(DS.Anim.snappy) {
                    hasAttemptedSubmit = true
                }

                guard !trimmedFull.isEmpty, !trimmedFamily.isEmpty else { return }

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
            .disabled(authVM.isLoading)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xxl)
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
