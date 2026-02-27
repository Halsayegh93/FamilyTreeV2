import SwiftUI

struct AddSonByAdminSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    let parent: FamilyMember // الأب الذي سيتم الربط به

    @State private var firstName: String = ""
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var phoneNumber: String = ""
    @State private var hasBirthDate: Bool = false
    @State private var birthDate: Date = Date()
    @State private var isDeceased: Bool = false
    @State private var hasDeathDate: Bool = false
    @State private var deathDate: Date = Date()

    var body: some View {
        VStack(spacing: 0) {
            // شريط التحكم العلوي
            headerBar

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) {

                    // تنبيه بسيط للمدير
                    HStack {
                        Text("إضافة ابن جديد للسيد: \(parent.fullName)")
                            .font(DS.Font.caption2).bold().foregroundColor(DS.Color.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    // 1. بيانات الابن الأساسية
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        UIComponents.SectionHeader(title: "بيانات الابن", icon: "person.badge.plus.fill")

                        UIComponents.UnifiedCard {
                            // Gradient top accent line
                            Rectangle()
                                .fill(DS.Color.gradientPrimary)
                                .frame(height: 2)

                            UIComponents.UnifiedTextField(
                                label: L10n.t("الاسم", "Name"),
                                placeholder: "اسم الابن الأول",
                                text: $firstName,
                                icon: "person.fill"
                            )

                            DSDivider()

                            toggleRow(title: "تاريخ الميلاد متوفر", isOn: $hasBirthDate, icon: "calendar.badge.checkmark", color: DS.Color.primary)

                            if hasBirthDate {
                                DSDivider()
                                dateRow(title: L10n.t("تاريخ الميلاد", "Birth Date"), selection: $birthDate, icon: "calendar", color: DS.Color.primary)
                            }

                            if !isDeceased {
                                DSDivider()
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

                                    TextField("رقم الهاتف (اختياري)", text: $phoneNumber)
                                        .keyboardType(.phonePad)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(.horizontal, DS.Spacing.md)
                                .padding(.vertical, DS.Spacing.xs + 2)
                                .onChange(of: phoneNumber) { _, newValue in
                                    phoneNumber = KuwaitPhone.userTypedDigits(newValue, maxDigits: selectedPhoneCountry.maxDigits)
                                }
                                .onChange(of: selectedPhoneCountry) { _, newCountry in
                                    phoneNumber = KuwaitPhone.userTypedDigits(phoneNumber, maxDigits: newCountry.maxDigits)
                                }
                                .environment(\.layoutDirection, .leftToRight)
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.md)

                    // 2. الحالة الصحية (متوفى أو حي)
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        UIComponents.SectionHeader(title: "الحالة الصحية", icon: "heart.text.square.fill")

                        UIComponents.UnifiedCard {
                            // Gradient top accent line
                            Rectangle()
                                .fill(DS.Color.gradientPrimary)
                                .frame(height: 2)

                            toggleRow(title: "إضافة كمتوفى", isOn: $isDeceased, icon: "bolt.heart.fill", color: .gray)

                            if isDeceased {
                                DSDivider()
                                toggleRow(title: "تاريخ الوفاة متوفر", isOn: $hasDeathDate, icon: "calendar.badge.exclamationmark", color: DS.Color.error)

                                if hasDeathDate {
                                    DSDivider()
                                    dateRow(title: "تاريخ الوفاة", selection: $deathDate, icon: "calendar.badge.exclamationmark", color: DS.Color.error)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.md)

                    Text("بصفتك مديراً، ستتم إضافة العضو للشجرة فوراً.")
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .padding(.vertical, DS.Spacing.md)
            }
        }
        .background(DS.Color.background)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - المكونات الفرعية

    private var headerBar: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 40, height: 5)
                .padding(.top, DS.Spacing.md)

            HStack {
                Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                    .foregroundColor(DS.Color.error)
                    .font(DS.Font.caption1)
                Spacer()
                Text(L10n.t("إضافة ابن", "Add Child"))
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                Spacer()
                Button(action: saveAction) {
                    if authVM.isLoading { ProgressView().tint(DS.Color.primary) }
                    else {
                        Text(L10n.t("إضافة", "Add"))
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.primary)
                    }
                }
                .disabled(firstName.isEmpty || authVM.isLoading)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)

            // Gradient accent line
            Rectangle()
                .fill(DS.Color.gradientPrimary)
                .frame(height: 2)
        }
        .background(DS.Color.surface)
    }

    private func dateRow(title: String, selection: Binding<Date>, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.white)
                .font(DS.Font.scaled(14))
                .frame(width: 32, height: 32)
                .background(
                    LinearGradient(
                        colors: [DS.Color.primary, DS.Color.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(DS.Radius.sm)
            Text(title).font(DS.Font.caption1)
            Spacer()
            DatePicker("", selection: selection, in: ...Date(), displayedComponents: .date).labelsHidden()
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs + 2)
    }

    private func toggleRow(title: String, isOn: Binding<Bool>, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.white)
                .font(DS.Font.scaled(14))
                .frame(width: 32, height: 32)
                .background(
                    LinearGradient(
                        colors: [DS.Color.primary, DS.Color.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(DS.Radius.sm)
            Text(title).font(DS.Font.caption1)
            Spacer()
            Toggle("", isOn: isOn.animation())
                .labelsHidden()
                .tint(DS.Color.primary)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs + 2)
    }

    private func saveAction() {
        Task {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US")

            // إضافة مباشرة من قبل المدير
            _ = await authVM.addChild(
                firstNameOnly: firstName,
                phoneNumber: KuwaitPhone.normalizedForStorage(
                    country: selectedPhoneCountry,
                    rawLocalDigits: phoneNumber
                ) ?? "",
                birthDate: hasBirthDate ? formatter.string(from: birthDate) : nil,
                fatherId: parent.id,
                isDeceased: isDeceased,
                deathDate: (isDeceased && hasDeathDate) ? formatter.string(from: deathDate) : nil
            )
            dismiss()
        }
    }
}
