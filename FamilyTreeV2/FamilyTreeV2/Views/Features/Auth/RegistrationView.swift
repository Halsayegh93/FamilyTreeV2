import SwiftUI

struct RegistrationView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var fullName: String = ""
    @State private var familyName: String = ""
    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var selectedGender: String = "male"

    // Animation states
    @State private var headerScale: CGFloat = 0.8
    @State private var headerOpacity: CGFloat = 0
    @State private var cardsAppeared = false
    @State private var hasAttemptedSubmit = false

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            // Decorative gradient background
            decorativeBackground

            VStack(spacing: 0) {
                // Top bar
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

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xl) {
                        // Header with gradient icon
                        headerSection
                            .scaleEffect(headerScale)
                            .opacity(headerOpacity)

                        VStack(spacing: DS.Spacing.md) {
                            // Full name field
                            nameFieldSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 20)

                            // Family name field
                            familyNameSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 25)

                            // Birth date field
                            birthDateSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 30)

                            // Gender selection
                            genderSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 35)
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // Submit button
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

    // MARK: - Decorative Background
    private var decorativeBackground: some View {
        DSDecorativeBackground()
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(DS.Color.primary.opacity(0.08))
                    .frame(width: 120, height: 120)

                // Gradient circle
                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 100, height: 100)

                Image(systemName: "person.badge.plus")
                    .font(DS.Font.scaled(42, weight: .bold))
                    .foregroundColor(DS.Color.textOnPrimary)
            }
            .dsGlowShadow()

            Text(L10n.t("إنشاء ملف تعريف", "Create Profile"))
                .font(DS.Font.title1)
                .foregroundColor(DS.Color.textPrimary)

            Text(L10n.t("يرجى إكمال بياناتك للانضمام إلى العائلة", "Complete your info to join the family"))
                .font(DS.Font.subheadline)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, DS.Spacing.md)
    }

    // MARK: - Name Field Section
    private var nameFieldSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DSTextField(
                label: L10n.t("الاسم الخماسي", "Full Name (5 parts)"),
                placeholder: L10n.t("مثال: حسن أحمد علي محمد السالم", "e.g. John Edward James Smith Jr"),
                text: $fullName,
                icon: "person.fill",
                iconColor: DS.Color.primary
            )
            .onChange(of: fullName) {
                if fullName.count > 100 {
                    fullName = String(fullName.prefix(100))
                }
            }

            if hasAttemptedSubmit && fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(DS.Font.caption2)
                    Text(L10n.t("الاسم مطلوب", "Name is required"))
                        .font(DS.Font.caption1)
                }
                .foregroundColor(DS.Color.error)
                .padding(.leading, DS.Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Family Name Section
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
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(DS.Font.caption2)
                    Text(L10n.t("اسم العائلة مطلوب", "Family name is required"))
                        .font(DS.Font.caption1)
                }
                .foregroundColor(DS.Color.error)
                .padding(.leading, DS.Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Birth Date Section
    private var birthDateSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
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
    }

    // MARK: - Gender Section
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
                // ذكر
                Button {
                    withAnimation(DS.Anim.snappy) { selectedGender = "male" }
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "figure.stand")
                            .font(DS.Font.scaled(16, weight: .bold))
                        Text(L10n.t("ذكر", "Male"))
                            .font(DS.Font.calloutBold)
                    }
                    .foregroundColor(selectedGender == "male" ? .white : DS.Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        Group {
                            if selectedGender == "male" {
                                AnyView(DS.Color.gradientPrimary)
                            } else {
                                AnyView(DS.Color.surface)
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(
                                selectedGender == "male" ? Color.clear : Color.gray.opacity(0.15),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: selectedGender == "male" ? DS.Color.primary.opacity(0.2) : .clear, radius: 8, x: 0, y: 3)
                }
                .buttonStyle(DSScaleButtonStyle())

                // أنثى
                Button {
                    withAnimation(DS.Anim.snappy) { selectedGender = "female" }
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "figure.stand.dress")
                            .font(DS.Font.scaled(16, weight: .bold))
                        Text(L10n.t("أنثى", "Female"))
                            .font(DS.Font.calloutBold)
                    }
                    .foregroundColor(selectedGender == "female" ? .white : DS.Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        Group {
                            if selectedGender == "female" {
                                AnyView(DS.Color.gradientAccent)
                            } else {
                                AnyView(DS.Color.surface)
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(
                                selectedGender == "female" ? Color.clear : Color.gray.opacity(0.15),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: selectedGender == "female" ? DS.Color.accent.opacity(0.2) : .clear, radius: 8, x: 0, y: 3)
                }
                .buttonStyle(DSScaleButtonStyle())
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
                        gender: selectedGender
                    )
                }
            }
            .disabled(authVM.isLoading)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xxl)
        }
    }
}
