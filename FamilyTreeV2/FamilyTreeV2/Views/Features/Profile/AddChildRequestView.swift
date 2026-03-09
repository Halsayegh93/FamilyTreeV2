import SwiftUI
import PhotosUI
import UIKit

struct AddChildRequestView: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss

    let member: FamilyMember

    @State private var firstName: String = ""
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var phoneNumber: String = ""
    @State private var hasBirthDate: Bool = true
    @State private var birthDate: Date = Date()
    @State private var isDeceased: Bool = false
    @State private var hasDeathDate: Bool = false
    @State private var deathDate: Date = Date()
    @State private var selectedUIImage: UIImage? = nil
    @State private var showSuccessAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                DSDecorativeBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {
                        basicInfoCard
                        statusCard
                        submitButton
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.xs)
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
        .alert(L10n.t("تمت الإضافة", "Added Successfully"), isPresented: $showSuccessAlert) {
            Button(L10n.t("موافق", "OK")) { dismiss() }
        } message: {
            Text(L10n.t("تمت إضافة الابن بنجاح.", "Child added successfully."))
        }
    }

    private var basicInfoCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSSectionHeader(
                title: L10n.t("بيانات الابن", "Child Info"),
                icon: "person.text.rectangle"
            )

            DSCard(padding: 0) {
                VStack(spacing: 0) {
                    

                    HStack(spacing: DS.Spacing.md) {
                        DSIcon("person.fill", color: DS.Color.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("الاسم الأول", "First Name"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                            TextField(L10n.t("الاسم الأول", "First Name"), text: $firstName)
                                .font(DS.Font.callout)
                                .foregroundColor(DS.Color.textPrimary)
                                .onChange(of: firstName) {
                                    if firstName.count > 50 {
                                        firstName = String(firstName.prefix(50))
                                    }
                                }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.xs)

                    DSDivider()

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
                                        Text(selectedPhoneCountry.dialingCode).font(DS.Font.caption1)
                                        Image(systemName: "chevron.down")
                                            .font(DS.Font.scaled(10, weight: .semibold))
                                    }
                                    .foregroundColor(DS.Color.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(DS.Color.surface)
                                    .cornerRadius(DS.Radius.sm)
                                }

                                TextField(L10n.t("رقم الهاتف (اختياري)", "Phone (optional)"), text: $phoneNumber)
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
                    .padding(.vertical, DS.Spacing.xs)
                }
            }

            DSProfilePhotoPicker(
                selectedImage: $selectedUIImage
            )

            DSCard(padding: 0) {
                VStack(spacing: 0) {

                    HStack(spacing: DS.Spacing.md) {
                        DSIcon("calendar", color: DS.Color.info)
                        Toggle(L10n.t("تاريخ الميلاد معروف", "Birth date known"), isOn: $hasBirthDate)
                            .font(DS.Font.callout)
                            .tint(DS.Color.primary)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.xs)

                    if hasBirthDate {
                        DSDivider()
                        HStack(spacing: DS.Spacing.md) {
                            DSIcon("calendar.badge.clock", color: DS.Color.info)
                            DatePicker(L10n.t("تاريخ الميلاد", "Birth Date"), selection: $birthDate, in: ...Date(), displayedComponents: .date)
                                .environment(\.locale, Locale(identifier: "en_US"))
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.xs)
                    }
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSSectionHeader(
                title: L10n.t("الحالة", "Status"),
                icon: "heart.text.square"
            )

            DSCard(padding: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: DS.Spacing.md) {
                        DSIcon("leaf.fill", color: .gray)
                        Toggle(L10n.t("متوفى", "Deceased"), isOn: $isDeceased)
                            .font(DS.Font.callout)
                            .tint(.gray)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.xs)

                    if isDeceased {
                        DSDivider()
                        HStack(spacing: DS.Spacing.md) {
                            DSIcon("calendar.badge.clock", color: DS.Color.info)
                            Toggle(L10n.t("تاريخ الوفاة معروف", "Death date known"), isOn: $hasDeathDate)
                                .font(DS.Font.callout)
                                .tint(DS.Color.primary)
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.xs)

                        if hasDeathDate {
                            DSDivider()
                            HStack(spacing: DS.Spacing.md) {
                                DSIcon("calendar", color: DS.Color.error)
                                DatePicker(L10n.t("تاريخ الوفاة", "Death Date"), selection: $deathDate, in: ...Date(), displayedComponents: .date)
                                    .environment(\.locale, Locale(identifier: "en_US"))
                            }
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.vertical, DS.Spacing.xs)
                        }
                    }
                }
            }
        }
    }

    private var submitButton: some View {
        DSPrimaryButton(
            L10n.t("إضافة الابن", "Add Child"),
            icon: "checkmark.circle.fill",
            isLoading: memberVM.isLoading,
            action: saveChild
        )
        .opacity(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
        .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || memberVM.isLoading)
    }

    private func saveChild() {
        Task {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")

            let birthDateString: String? = hasBirthDate ? formatter.string(from: birthDate) : nil
            let deathDateString: String? = (isDeceased && hasDeathDate) ? formatter.string(from: deathDate) : nil

            let childId = await memberVM.addChild(
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

            if let childId, let image = selectedUIImage {
                await memberVM.uploadAvatar(image: image, for: childId)
            }

            if !memberVM.isLoading {
                showSuccessAlert = true
            }
        }
    }
}
