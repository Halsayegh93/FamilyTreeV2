import SwiftUI
import PhotosUI
import UIKit
import Supabase

struct AddChildSheet: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss

    let member: FamilyMember

    @State private var firstName: String = ""
    @AppStorage("lastAuthDialingCode") private var lastAuthDialingCode: String = ""
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var phoneNumber: String = ""
    @State private var birthDate: Date = Date()
    @State private var selectedGender: String = "male"
    @State private var isDeceased: Bool = false
    @State private var deathDate: Date = Date()
    @State private var selectedUIImage: UIImage? = nil
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var sheetHeight: CGFloat = 520

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()


                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {
                        heroHeader
                        basicInfoCard
                            .padding(.horizontal, DS.Spacing.lg)
                        submitButton
                            .padding(.horizontal, DS.Spacing.lg)
                    }
                    .padding(.vertical, DS.Spacing.xs)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: SheetContentHeightKey.self, value: proxy.size.height)
                        }
                    )
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
        .onPreferenceChange(SheetContentHeightKey.self) { h in
            if h > 0 { sheetHeight = h + 72 }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .alert(L10n.t("تمت الإضافة", "Added Successfully"), isPresented: $showSuccessAlert) {
            Button(L10n.t("موافق", "OK")) { dismiss() }
        } message: {
            Text(L10n.t("تمت إضافة الابن بنجاح.", "Child added successfully."))
        }
        .alert(L10n.t("خطأ", "Error"), isPresented: $showErrorAlert) {
            Button(L10n.t("موافق", "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            if !lastAuthDialingCode.isEmpty {
                selectedPhoneCountry = KuwaitPhone.countryForDialingCode(lastAuthDialingCode)
            }
        }
    }

    @ViewBuilder
    private var heroHeader: some View {
        if selectedGender == "female" {
            // قاعدة التطبيق: الأنثى بلا صورة شخصية.
            FemaleAvatarView()
                .frame(width: 96, height: 96)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DS.Spacing.lg)
        } else {
            DSProfilePhotoPicker(
                selectedImage: $selectedUIImage,
                enableCrop: true,
                cropShape: .circle,
                trailing: L10n.t("اختياري", "Optional"),
                compactEmptyState: true
            )
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    private var basicInfoCard: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("المعلومات الشخصية", "Personal Info"),
                icon: "person.text.rectangle",
                iconColor: DS.Color.primary
            )

                VStack(spacing: 0) {
                    // Name field — العنوان فوق الحقل
                    DSLabeledFieldRow(icon: "person.fill", iconColor: DS.Color.primary,
                                      label: L10n.t("الاسم الأول", "First Name")) {
                        TextField(L10n.t("اسم الابن", "Child's name"), text: $firstName)
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textPrimary)
                            .onChange(of: firstName) { _ in
                                if firstName.count > 50 {
                                    firstName = String(firstName.prefix(50))
                                }
                            }
                    }

                    DSDivider()

                    // الجنس — أنثى تدخل شجرة النساء فقط؛ ذكر يدخل الشجرتين.
                    DSFormRow(icon: "person.2.fill", iconColor: DS.Color.accent,
                              label: L10n.t("الجنس", "Gender")) {
                        Picker("", selection: $selectedGender) {
                            Text(L10n.t("ذكر", "Male")).tag("male")
                            Text(L10n.t("أنثى", "Female")).tag("female")
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }

                    // Phone field — للذكر فقط (الأنثى بشجرة النساء بلا هاتف)
                    if selectedGender != "female" {
                        DSDivider()
                        DSLabeledFieldRow(icon: "phone.fill", iconColor: DS.Color.success,
                                          label: L10n.t("رقم الهاتف", "Phone Number")) {
                            DSPhoneField(
                                country: $selectedPhoneCountry,
                                digits: $phoneNumber,
                                placeholder: L10n.t("اختياري", "Optional"),
                                compact: true,
                                bordered: false
                            )
                        }
                    }

                    DSDivider()

                    // Birth date — صف موحّد
                    DSDateField(
                        label: L10n.t("تاريخ الميلاد", "Birth Date"),
                        date: $birthDate,
                        range: ...Date(),
                        labelAbove: true
                    )

                    DSDivider()

                    // Deceased toggle — صف موحّد
                    DSFormRow(icon: "leaf.fill", iconColor: DS.Color.error,
                              label: L10n.t("متوفى", "Deceased")) {
                        Toggle("", isOn: $isDeceased)
                            .labelsHidden()
                            .tint(DS.Color.error)
                    }
                    .animation(.default, value: isDeceased)

                    if isDeceased {
                        DSDivider()
                        DSDateField(
                            label: L10n.t("تاريخ الوفاة", "Death Date"),
                            date: $deathDate,
                            icon: "calendar",
                            iconColor: DS.Color.error,
                            range: ...Date()
                        )
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.xs)
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

            let birthDateString: String? = formatter.string(from: birthDate)
            let deathDateString: String? = isDeceased ? formatter.string(from: deathDate) : nil
            let cleanFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            let siblings = memberVM.allMembers.filter { $0.fatherId == member.id }.count

            do {
                // التوجيه عبر السيرفر: أنثى → النساء فقط، ذكر → الشجرتين.
                let childId = try await WomenStore.addFamilyChild(
                    parentId: member.id,
                    name: cleanFirst,
                    gender: selectedGender,
                    birthDate: birthDateString,
                    isDeceased: isDeceased,
                    deathDate: deathDateString,
                    sortOrder: siblings,
                    parentFullName: member.fullName
                )

                // الذكر فقط: رقم الهاتف (اختياري) + الصورة.
                if selectedGender != "female" {
                    let phone = KuwaitPhone.normalizedForStorage(
                        country: selectedPhoneCountry, rawLocalDigits: phoneNumber) ?? ""
                    if !phone.isEmpty {
                        try? await SupabaseConfig.client.from("profiles")
                            .update(["phone_number": AnyEncodable(phone)])
                            .eq("id", value: childId.uuidString).execute()
                    }
                    if let image = selectedUIImage {
                        await memberVM.uploadAvatar(image: image, for: childId)
                    }
                }

                await memberVM.fetchAllMembers(force: true)
                await memberVM.fetchChildren(for: member.id)
                WomenStore.cache = (try? await WomenStore.fetch()) ?? WomenStore.cache
                showSuccessAlert = true
            } catch {
                Log.error("فشل في إضافة الابن")
                errorMessage = L10n.t("فشل في إضافة الابن. حاول مرة أخرى.", "Failed to add child. Please try again.")
                showErrorAlert = true
            }
        }
    }
}
