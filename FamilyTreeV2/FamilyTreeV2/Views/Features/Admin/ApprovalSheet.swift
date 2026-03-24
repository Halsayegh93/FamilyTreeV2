import SwiftUI

struct ApprovalSheet: View {
    let member: FamilyMember
    var onComplete: () -> Void
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @FocusState private var isSearchFocused: Bool

    @State private var searchText = ""
    @State private var selectedFather: FamilyMember? = nil
    @State private var isLoading = false

    /// بحث محلي في الأعضاء المحملين بدل الاستعلام من السيرفر كل مرة
    private var searchResults: [FamilyMember] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.count >= 2 else { return [] }
        return memberVM.allMembers
            .filter { $0.status == .active && $0.id != member.id }
            .filter { $0.fullName.lowercased().contains(query) }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.xl) {
                // عرض بيانات الشخص المطلوب ربطه
                VStack(spacing: DS.Spacing.md) {
                    // Header icon — gradient circle with person.badge.plus
                    ZStack {
                        Circle()
                            .fill(DS.Color.gradientPrimary)
                            .frame(width: 66, height: 66)
                        Image(systemName: "person.badge.plus")
                            .font(DS.Font.scaled(28, weight: .semibold))
                            .foregroundColor(DS.Color.textOnPrimary)
                    }
                    .dsGlowShadow()

                    Text(L10n.t("ربط بالشجرة", "Link to Tree"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)

                    Text(member.fullName)
                        .font(DS.Font.title3)
                        .foregroundColor(DS.Color.textPrimary)
                }
                .padding(DS.Spacing.lg)
                .frame(maxWidth: .infinity)
                .background(DS.Color.surface)
                .cornerRadius(DS.Radius.xl)
                .dsCardShadow()

                // خانة البحث عن الأب
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    Text(L10n.t("ابحث عن اسم الأب في العائلة:", "Search for the father's name:"))
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textPrimary)

                    // DS styled search field with focus border
                    HStack(spacing: DS.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(DS.Color.gradientPrimary)
                                .frame(width: 32, height: 32)
                            Image(systemName: "magnifyingglass")
                                .font(DS.Font.scaled(12, weight: .semibold))
                                .foregroundColor(DS.Color.textOnPrimary)
                        }

                        TextField(L10n.t("اكتب الاسم الخماسي للأب...", "Type the father's full name..."), text: $searchText)
                            .multilineTextAlignment(.leading)
                            .font(DS.Font.body)
                            .focused($isSearchFocused)
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(isSearchFocused ? DS.Color.primary : DS.Color.inactiveBorder, lineWidth: isSearchFocused ? 2 : 1)
                    )
                    .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
                }

                // نتائج البحث — gradient checkmarks, DS.Font
                List(searchResults) { father in
                    HStack(spacing: DS.Spacing.md) {
                        if selectedFather?.id == father.id {
                            Image(systemName: "checkmark.circle.fill")
                                .font(DS.Font.scaled(20))
                                .foregroundStyle(DS.Color.gradientPrimary)
                        } else {
                            Image(systemName: "circle")
                                .font(DS.Font.scaled(20))
                                .foregroundColor(DS.Color.textTertiary)
                        }

                        Spacer()

                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(father.fullName)
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.textPrimary)
                            Text(L10n.t("رقم الهاتف: \(KuwaitPhone.display(father.phoneNumber))", "Phone: \(KuwaitPhone.display(father.phoneNumber))"))
                                .font(DS.Font.caption2)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedFather = father
                    }
                    .accessibilityLabel(L10n.t("اختيار \(father.fullName) كأب", "Select \(father.fullName) as father"))
                }
                .listStyle(.plain)

                // زر التأكيد النهائي — DSPrimaryButton gradient
                DSPrimaryButton(
                    L10n.t("تأكيد الانضمام والربط بالأب", "Confirm & Link to Father"),
                    icon: "checkmark.circle.fill",
                    isLoading: isLoading
                ) {
                    approveAndLink()
                }
                .disabled(selectedFather == nil || isLoading)
                .opacity((selectedFather == nil || isLoading) ? 0.6 : 1.0)
                .padding(.horizontal, DS.Spacing.xs)
            }
            .padding(DS.Spacing.lg)
            .navigationTitle(L10n.t("إجراءات الموافقة", "Approval Actions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.error)
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// تفعيل العضو وربطه بالأب عبر AdminRequestViewModel
    private func approveAndLink() {
        guard authVM.canModerate else {
            Log.warning("[AUTH] Unauthorized approveAndLink attempt")
            return
        }
        guard let fatherId = selectedFather?.id else { return }
        isLoading = true

        Task {
            await adminRequestVM.approveMember(memberId: member.id, fatherId: fatherId)
            await MainActor.run {
                isLoading = false
                onComplete()
                dismiss()
            }
        }
    }
}
