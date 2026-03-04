import SwiftUI
import PhotosUI

struct AdminMemberControlView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    let member: FamilyMember

    // حالات التحكم في الواجهة
    @State private var fullName: String
    @State private var isDeceased: Bool
    @State private var isMarried: Bool
    @State private var birthDate: Date
    @State private var deathDate: Date?
    @State private var showDeleteAlert = false
    @State private var showAvatarPicker = false
    @State private var selectedAvatarItem: PhotosPickerItem? = nil
    @State private var localAvatarPreviewImage: UIImage? = nil
    @State private var showDeleteAvatarAlert = false
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

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xl) {

                        // Avatar section
                        if isManager {
                            DSCard {
                                VStack(spacing: DS.Spacing.lg) {
                                    HStack {
                                        Spacer()
                                        ZStack {
                                            if let localAvatarPreviewImage {
                                                Image(uiImage: localAvatarPreviewImage)
                                                    .resizable()
                                                    .scaledToFill()
                                            } else if let avatar = avatarURL, let url = URL(string: avatar) {
                                                AsyncImage(url: url) { img in
                                                    img.resizable().scaledToFill()
                                                } placeholder: {
                                                    ProgressView().tint(DS.Color.primary)
                                                }
                                            } else {
                                                Circle()
                                                    .fill(
                                                        LinearGradient(
                                                            colors: [DS.Color.primary.opacity(0.15), DS.Color.accent.opacity(0.08)],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                                    .overlay(
                                                        Image(systemName: "person.fill")
                                                            .font(DS.Font.scaled(28, weight: .bold))
                                                            .foregroundColor(DS.Color.primary)
                                                    )
                                            }
                                        }
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(DS.Color.gradientPrimary, lineWidth: 3)
                                        )
                                        .dsGlowShadow()
                                        Spacer()
                                    }

                                    Button {
                                        showAvatarPicker = true
                                    } label: {
                                        HStack(spacing: DS.Spacing.sm) {
                                            Image(systemName: "camera.fill")
                                                .foregroundColor(.white)
                                                .font(DS.Font.scaled(12))
                                                .frame(width: 28, height: 28)
                                                .background(DS.Color.gradientPrimary)
                                                .clipShape(Circle())
                                            Text(L10n.t("تغيير صورة البروفايل", "Change Profile Photo"))
                                                .font(DS.Font.calloutBold)
                                                .foregroundColor(DS.Color.primary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, DS.Spacing.sm)
                                    }

                                    if avatarURL != nil || localAvatarPreviewImage != nil {
                                        Button(role: .destructive) {
                                            showDeleteAvatarAlert = true
                                        } label: {
                                            Label(L10n.t("حذف صورة البروفايل", "Delete Profile Photo"), systemImage: "trash")
                                                .font(DS.Font.calloutBold)
                                                .foregroundColor(DS.Color.error)
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                }
                                .padding(DS.Spacing.lg)
                            }
                            .padding(.horizontal, DS.Spacing.lg)
                        }

                        // Basic Information section
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            DSSectionHeader(title: L10n.t("البيانات الأساسية", "Basic Information"), icon: "person.text.rectangle")

                            DSCard {
                                VStack(spacing: 0) {
                                    HStack(spacing: DS.Spacing.md) {
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.white)
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
                                    .padding(.vertical, DS.Spacing.md)

                                    DSDivider()

                                    HStack(spacing: DS.Spacing.md) {
                                        Image(systemName: "calendar")
                                            .foregroundColor(.white)
                                            .font(DS.Font.scaled(14))
                                            .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                                            .background(DS.Color.gradientPrimary)
                                            .cornerRadius(DS.Radius.sm)

                                        DatePicker(L10n.t("تاريخ الميلاد", "Birth Date"), selection: $birthDate, in: ...Date(), displayedComponents: .date)
                                            .font(DS.Font.body)
                                    }
                                    .padding(.horizontal, DS.Spacing.lg)
                                    .padding(.vertical, DS.Spacing.md)

                                    DSDivider()

                                    HStack(spacing: DS.Spacing.md) {
                                        Image(systemName: "heart.fill")
                                            .foregroundColor(.white)
                                            .font(DS.Font.scaled(14))
                                            .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                                            .background(DS.Color.gradientPrimary)
                                            .cornerRadius(DS.Radius.sm)

                                        Toggle(L10n.t("متزوج", "Married"), isOn: $isMarried)
                                            .font(DS.Font.body)
                                            .tint(DS.Color.primary)
                                    }
                                    .padding(.horizontal, DS.Spacing.lg)
                                    .padding(.vertical, DS.Spacing.md)
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
                                            .foregroundColor(.white)
                                            .font(DS.Font.scaled(14))
                                            .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                                            .background(DS.Color.gradientPrimary)
                                            .cornerRadius(DS.Radius.sm)

                                        Toggle(L10n.t("متوفى", "Deceased"), isOn: $isDeceased)
                                            .font(DS.Font.body)
                                            .tint(DS.Color.error)
                                    }
                                    .padding(.horizontal, DS.Spacing.lg)
                                    .padding(.vertical, DS.Spacing.md)

                                    if isDeceased {
                                        DSDivider()

                                        HStack(spacing: DS.Spacing.md) {
                                            Image(systemName: "calendar.badge.exclamationmark")
                                                .foregroundColor(.white)
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
                                        .padding(.vertical, DS.Spacing.md)
                                    }
                                }
                            }
                            .padding(.horizontal, DS.Spacing.lg)
                        }

                        // Save button
                        DSPrimaryButton(
                            L10n.t("حفظ التعديلات", "Save Changes"),
                            isLoading: authVM.isLoading
                        ) {
                            Task {
                                let previousName = authVM.allMembers.first(where: { $0.id == member.id })?.fullName
                                await authVM.updateMemberData(
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
                                let updatedMember = authVM.allMembers.first(where: { $0.id == member.id })
                                if updatedMember?.fullName == previousName && fullName != previousName {
                                    errorMessage = L10n.t("حدث خطأ أثناء حفظ التعديلات. حاول مرة أخرى.", "An error occurred while saving changes. Please try again.")
                                    showErrorAlert = true
                                    Log.error("updateMemberData failed silently for member \(member.id)")
                                } else {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(authVM.isLoading)
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
                        await authVM.rejectOrDeleteMember(memberId: member.id)
                        // Check if deletion succeeded
                        if authVM.allMembers.contains(where: { $0.id == member.id }) {
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
            .photosPicker(isPresented: $showAvatarPicker, selection: $selectedAvatarItem, matching: .images)
            .onChange(of: selectedAvatarItem) { _, newItem in
                handleAvatarImageChange(newItem)
            }
            .alert(L10n.t("حذف صورة البروفايل", "Delete Profile Photo"), isPresented: $showDeleteAvatarAlert) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    Task {
                        await authVM.deleteAvatar(for: member.id)
                        await MainActor.run {
                            self.avatarURL = nil
                            self.localAvatarPreviewImage = nil
                        }
                    }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            } message: {
                Text(L10n.t("هل تريد حذف صورة البروفايل لهذا العضو؟", "Do you want to delete this member's profile photo?"))
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func handleAvatarImageChange(_ item: PhotosPickerItem?) {
        Task {
            guard let data = try? await item?.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else { return }
            await MainActor.run {
                self.localAvatarPreviewImage = uiImage
            }
            await authVM.uploadAvatar(image: uiImage, for: member.id)
            await MainActor.run {
                self.avatarURL = nil
            }
        }
    }
}
