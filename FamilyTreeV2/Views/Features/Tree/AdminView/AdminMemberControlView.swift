import SwiftUI
import PhotosUI

struct AdminMemberControlView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) var dismiss

    let member: FamilyMember

    // حالات التحكم في الواجهة
    @State private var fullName: String
    @State private var isDeceased: Bool
    @State private var isMarried: Bool
    @State private var birthDate: Date
    @State private var deathDate: Date?
    @State private var showDeleteAlert = false
    @State private var localAvatarPreviewImage: UIImage? = nil
    @State private var avatarURL: String? = nil
    @State private var errorMessage = ""
    @State private var showErrorAlert = false

    init(member: FamilyMember) {
        self.member = member
        _fullName = State(initialValue: member.fullName)
        _isDeceased = State(initialValue: member.isDeceased ?? false)
        _isMarried = State(initialValue: member.isMarried ?? false)
        _avatarURL = State(initialValue: member.avatarUrl)

        // تحويل التاريخ من نص إلى Date
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let bDate = formatter.date(from: member.birthDate ?? "") ?? Date()
        _birthDate = State(initialValue: bDate)

        if let dStr = member.deathDate {
            _deathDate = State(initialValue: formatter.date(from: dStr))
        }
    }

    private var isManager: Bool {
        authVM.currentUser?.role == .admin
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()
                DSDecorativeBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {

                        // Avatar section
                        if isManager {
                            DSProfilePhotoPicker(
                                selectedImage: $localAvatarPreviewImage,
                                existingURL: avatarURL,
                                showDeleteForExisting: true,
                                onDeleteExisting: {
                                    Task {
                                        await memberVM.deleteAvatar(for: member.id)
                                        await MainActor.run {
                                            avatarURL = nil
                                            localAvatarPreviewImage = nil
                                        }
                                    }
                                }
                            )
                            .padding(.horizontal, DS.Spacing.lg)
                            .onChange(of: localAvatarPreviewImage) { _, newImage in
                                guard let newImage else { return }
                                Task {
                                    await memberVM.uploadAvatar(image: newImage, for: member.id)
                                    await MainActor.run { avatarURL = nil }
                                }
                            }
                        }

                        // Basic Information section
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            DSSectionHeader(title: L10n.t("البيانات الأساسية", "Basic Information"), icon: "person.text.rectangle")

                            DSCard {
                                VStack(spacing: 0) {
                                    HStack(spacing: DS.Spacing.md) {
                                        Image(systemName: "person.fill")
                                            .foregroundColor(DS.Color.textOnPrimary)
                                            .font(DS.Font.scaled(14))
                                            .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                                            .background(DS.Color.gradientPrimary)
                                            .cornerRadius(DS.Radius.sm)

                                        TextField(L10n.t("الاسم الكامل", "Full Name"), text: $fullName)
                                            .font(DS.Font.body)
                                            .multilineTextAlignment(.leading)
                                            .onChange(of: fullName) {
                                                if fullName.count > 100 {
                                                    fullName = String(fullName.prefix(100))
                                                }
                                            }
                                    }
                                    .padding(.horizontal, DS.Spacing.lg)
                                    .padding(.vertical, DS.Spacing.xs)

                                    DSDivider()

                                    HStack(spacing: DS.Spacing.md) {
                                        Image(systemName: "calendar")
                                            .foregroundColor(DS.Color.textOnPrimary)
                                            .font(DS.Font.scaled(14))
                                            .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                                            .background(DS.Color.gradientPrimary)
                                            .cornerRadius(DS.Radius.sm)

                                        DatePicker(L10n.t("تاريخ الميلاد", "Birth Date"), selection: $birthDate, in: ...Date(), displayedComponents: .date)
                                            .font(DS.Font.body)
                                    }
                                    .padding(.horizontal, DS.Spacing.lg)
                                    .padding(.vertical, DS.Spacing.xs)

                                    DSDivider()

                                    HStack(spacing: DS.Spacing.md) {
                                        Image(systemName: "heart.fill")
                                            .foregroundColor(DS.Color.textOnPrimary)
                                            .font(DS.Font.scaled(14))
                                            .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                                            .background(DS.Color.gradientPrimary)
                                            .cornerRadius(DS.Radius.sm)

                                        Toggle(L10n.t("متزوج", "Married"), isOn: $isMarried)
                                            .font(DS.Font.body)
                                            .tint(DS.Color.primary)
                                    }
                                    .padding(.horizontal, DS.Spacing.lg)
                                    .padding(.vertical, DS.Spacing.xs)
                                }
                            }
                            .padding(.horizontal, DS.Spacing.lg)
                        }

                        // Status section
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            DSSectionHeader(title: L10n.t("الحالة", "Status"), icon: "heart.text.square")

                            DSCard {
                                VStack(spacing: 0) {
                                    HStack(spacing: DS.Spacing.md) {
                                        Image(systemName: "cross.fill")
                                            .foregroundColor(DS.Color.textOnPrimary)
                                            .font(DS.Font.scaled(14))
                                            .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                                            .background(DS.Color.gradientPrimary)
                                            .cornerRadius(DS.Radius.sm)

                                        Toggle(L10n.t("متوفى", "Deceased"), isOn: $isDeceased)
                                            .font(DS.Font.body)
                                            .tint(DS.Color.error)
                                    }
                                    .padding(.horizontal, DS.Spacing.lg)
                                    .padding(.vertical, DS.Spacing.xs)

                                    if isDeceased {
                                        DSDivider()

                                        HStack(spacing: DS.Spacing.md) {
                                            Image(systemName: "calendar.badge.exclamationmark")
                                                .foregroundColor(DS.Color.textOnPrimary)
                                                .font(DS.Font.scaled(14))
                                                .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                                                .background(DS.Color.gradientPrimary)
                                                .cornerRadius(DS.Radius.sm)

                                            DatePicker(L10n.t("تاريخ الوفاة", "Date of Death"), selection: Binding(
                                                get: { deathDate ?? Date() },
                                                set: { deathDate = $0 }
                                            ), in: ...Date(), displayedComponents: .date)
                                            .font(DS.Font.body)
                                        }
                                        .padding(.horizontal, DS.Spacing.lg)
                                        .padding(.vertical, DS.Spacing.xs)
                                    }
                                }
                            }
                            .padding(.horizontal, DS.Spacing.lg)
                        }

                        // Save button
                        DSPrimaryButton(
                            L10n.t("حفظ التعديلات", "Save Changes"),
                            isLoading: memberVM.isLoading
                        ) {
                            Task {
                                let previousName = memberVM.member(byId: member.id)?.fullName
                                await memberVM.updateMemberData(
                                    memberId: member.id,
                                    fullName: fullName,
                                    phoneNumber: member.phoneNumber ?? "",
                                    birthDate: birthDate,
                                    isMarried: isMarried,
                                    isDeceased: isDeceased,
                                    deathDate: deathDate,
                                    isPhoneHidden: member.isPhoneHidden ?? false
                                )
                                // Check if update succeeded by verifying data changed
                                let updatedMember = memberVM.member(byId: member.id)
                                if updatedMember?.fullName == previousName && fullName != previousName {
                                    errorMessage = L10n.t("حدث خطأ أثناء حفظ التعديلات. حاول مرة أخرى.", "An error occurred while saving changes. Please try again.")
                                    showErrorAlert = true
                                    Log.error("updateMemberData failed silently for member \(member.id)")
                                } else {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(memberVM.isLoading)
                        .padding(.horizontal, DS.Spacing.lg)

                        // Delete button
                        Button(role: .destructive, action: { showDeleteAlert = true }) {
                            Text(L10n.t("حذف العضو نهائياً", "Delete Member Permanently"))
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.error)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(DS.Color.error.opacity(0.06))
                                .cornerRadius(DS.Radius.lg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                                        .stroke(DS.Color.error.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        Spacer(minLength: DS.Spacing.xxxl)
                    }
                    .padding(.top, DS.Spacing.lg)
                }
            }
            .navigationTitle(L10n.t("تعديل بيانات العضو", "Edit Member Details"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .foregroundColor(DS.Color.primary)
                }
            }
            .alert(L10n.t("تأكيد الحذف", "Confirm Deletion"), isPresented: $showDeleteAlert) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    Task {
                        await adminRequestVM.rejectOrDeleteMember(memberId: member.id)
                        // Check if deletion succeeded
                        if memberVM.allMembers.contains(where: { $0.id == member.id }) {
                            errorMessage = L10n.t("حدث خطأ أثناء حذف العضو. حاول مرة أخرى.", "An error occurred while deleting the member. Please try again.")
                            showErrorAlert = true
                            Log.error("rejectOrDeleteMember failed silently for member \(member.id)")
                        } else {
                            dismiss()
                        }
                    }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            } message: {
                Text(L10n.t("هل أنت متأكد من حذف \(member.fullName)؟ لا يمكن التراجع عن هذا الإجراء.", "Are you sure you want to delete \(member.fullName)? This action cannot be undone."))
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

}
