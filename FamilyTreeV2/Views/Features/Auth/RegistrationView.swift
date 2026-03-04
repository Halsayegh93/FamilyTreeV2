import SwiftUI

struct RegistrationView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var fullName: String = ""
    @State private var familyName: String = ""
    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var searchText = ""
    @State private var selectedFatherId: UUID?
    @State private var selectedGender: String = "male"

    // Animation states
    @State private var headerScale: CGFloat = 0.8
    @State private var headerOpacity: CGFloat = 0
    @State private var cardsAppeared = false

    private var fatherCandidates: [FamilyMember] {
        let base = authVM.allMembers.filter { $0.role != .pending }
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return base.prefix(20).map { $0 }
        }
        return base.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText) ||
            $0.firstName.localizedCaseInsensitiveContains(searchText)
        }.prefix(20).map { $0 }
    }

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
                            Image(systemName: "chevron.right")
                                .font(DS.Font.scaled(13, weight: .bold))
                            Text(L10n.t("رجوع", "Back"))
                        }
                        .font(DS.Font.subheadline)
                        .foregroundColor(DS.Color.primary)
                    }
                    Spacer()
                }
                .padding(DS.Spacing.lg)
                .background(.ultraThinMaterial)

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

                            // Father selection
                            fatherSelectionSection
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 40)
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
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await authVM.fetchAllMembers() }
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

    // MARK: - Decorative Background
    private var decorativeBackground: some View {
        ZStack {
            // Top gradient
            LinearGradient(
                colors: [
                    DS.Color.primary.opacity(0.12),
                    DS.Color.primary.opacity(0.04),
                    .clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            // Decorative circles
            Circle()
                .fill(DS.Color.primary.opacity(0.06))
                .frame(width: 300, height: 300)
                .offset(x: -120, y: -300)

            Circle()
                .fill(DS.Color.neonPurple.opacity(0.05))
                .frame(width: 200, height: 200)
                .offset(x: 150, y: -200)

            Circle()
                .fill(DS.Color.primary.opacity(0.04))
                .frame(width: 150, height: 150)
                .offset(x: 160, y: 400)

            Circle()
                .fill(DS.Color.accentLight.opacity(0.04))
                .frame(width: 120, height: 120)
                .offset(x: -140, y: 350)
        }
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
                    .foregroundColor(.white)
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
            DSSectionHeader(title: L10n.t("الاسم الخماسي", "Full Name (5 parts)"), icon: "person.fill")

            DSCard {
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
    }

    // MARK: - Family Name Section
    private var familyNameSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DSSectionHeader(title: L10n.t("اسم العائلة", "Family Name"), icon: "person.2.fill")

            DSCard {
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
    }

    // MARK: - Birth Date Section
    private var birthDateSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DSSectionHeader(title: L10n.t("تاريخ الميلاد", "Birth Date"), icon: "calendar")

            DSCard {
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

    // MARK: - Gender Section
    private var genderSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DSSectionHeader(title: L10n.t("الجنس", "Gender"), icon: "figure.dress.line.vertical.figure")

            DSCard {
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
    }

    // MARK: - Father Selection Section
    private var fatherSelectionSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DSSectionHeader(title: L10n.t("اختيار الأب من الشجرة", "Select Father from Tree"), icon: "person.2.fill")

            DSCard {
                // Search field
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("magnifyingglass", color: DS.Color.primary)
                    TextField(L10n.t("ابحث عن اسم الأب...", "Search father's name..."), text: $searchText)
                        .font(DS.Font.body)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)

                if let fatherId = selectedFatherId,
                   let father = authVM.allMembers.first(where: { $0.id == fatherId }) {
                    DSDivider()
                    HStack {
                        // Gradient checkmark badge
                        ZStack {
                            Circle()
                                .fill(DS.Color.gradientPrimary)
                                .frame(width: 24, height: 24)
                            Image(systemName: "checkmark")
                                .font(DS.Font.scaled(11, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text(L10n.t("الأب المختار: \(father.fullName)", "Selected: \(father.fullName)"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                        Spacer()
                        Button(L10n.t("إزالة", "Remove")) { selectedFatherId = nil }
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.error)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)
                }

                if !fatherCandidates.isEmpty {
                    DSDivider()
                    VStack(spacing: 0) {
                        ForEach(fatherCandidates) { candidate in
                            Button {
                                selectedFatherId = candidate.id
                                searchText = candidate.fullName
                            } label: {
                                HStack(spacing: DS.Spacing.md) {
                                    // Gradient avatar circle with first letter
                                    ZStack {
                                        Circle()
                                            .fill(
                                                selectedFatherId == candidate.id
                                                    ? DS.Color.gradientPrimary
                                                    : LinearGradient(
                                                        colors: [DS.Color.primary.opacity(0.15), DS.Color.neonPurple.opacity(0.15)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                            )
                                            .frame(width: 36, height: 36)

                                        Text(String(candidate.fullName.prefix(1)))
                                            .font(DS.Font.scaled(14, weight: .bold))
                                            .foregroundColor(selectedFatherId == candidate.id ? .white : DS.Color.primary)
                                    }

                                    Text(candidate.fullName)
                                        .font(DS.Font.callout)
                                        .foregroundColor(DS.Color.textPrimary)
                                        .lineLimit(1)

                                    Spacer()

                                    if selectedFatherId == candidate.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(DS.Color.success)
                                            .font(DS.Font.scaled(18))
                                    }
                                }
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.md)
                                .background(
                                    selectedFatherId == candidate.id
                                        ? DS.Color.primary.opacity(0.05)
                                        : Color.clear
                                )
                            }
                            if candidate.id != fatherCandidates.last?.id {
                                DSDivider()
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
        }
    }

    // MARK: - Submit Button
    private var submitButton: some View {
        VStack(spacing: DS.Spacing.sm) {
            let isDisabled = fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authVM.isLoading
            DSPrimaryButton(
                L10n.t("إرسال طلب الانضمام", "Submit Join Request"),
                icon: "paperplane.fill",
                isLoading: authVM.isLoading,
                useGradient: !isDisabled,
                color: isDisabled ? .gray : DS.Color.primary
            ) {
                let trimmedFull = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedFamily = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    await authVM.registerNewUser(
                        firstName: trimmedFull,
                        familyName: trimmedFamily,
                        birthDate: birthDate,
                        gender: selectedGender,
                        fatherId: selectedFatherId
                    )
                }
            }
            .disabled(isDisabled)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xxl)
        }
    }
}
