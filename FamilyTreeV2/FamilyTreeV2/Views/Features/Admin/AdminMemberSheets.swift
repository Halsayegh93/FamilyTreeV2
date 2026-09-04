import SwiftUI

// شيتان مشتركان كانا داخل AdminPendingRequestsView (المحذوفة) وتستخدمهما شاشات أخرى.

struct LinkToExistingMemberSheet: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) var dismiss
    @FocusState private var searchFocused: Bool

    let pendingMember: FamilyMember

    @State private var searchText = ""
    @State private var selectedMember: FamilyMember? = nil
    @State private var showConfirm = false

    private var candidates: [FamilyMember] {
        let all = memberVM.allMembers.filter {
            $0.role != .pending &&
            $0.id != pendingMember.id &&
            $0.isDeceased == false
        }
        if searchText.isEmpty { return all }
        return all.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // بطاقة العضو المعلق
                    VStack(spacing: DS.Spacing.xs) {
                        HStack(spacing: DS.Spacing.md) {
                            ZStack {
                                Circle()
                                    .fill(DS.Color.warning.opacity(0.15))
                                    .frame(width: 46, height: 46)
                                Text(pendingMember.fullName.prefix(1))
                                    .font(DS.Font.scaled(20, weight: .bold))
                                    .foregroundColor(DS.Color.warning)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t("سيتم ربط حساب:", "Linking account:"))
                                    .font(DS.Font.caption2)
                                    .foregroundColor(DS.Color.textTertiary)
                                Text(pendingMember.fullName)
                                    .font(DS.Font.calloutBold)
                                    .foregroundColor(DS.Color.textPrimary)
                            }
                            Spacer()
                        }

                        if let selected = selectedMember {
                            HStack(spacing: DS.Spacing.sm) {
                                Image(systemName: "arrow.down")
                                    .font(DS.Font.scaled(12, weight: .bold))
                                    .foregroundColor(DS.Color.success)
                                Text(L10n.t("سيُربط بـ", "Will link to"))
                                    .font(DS.Font.caption1)
                                    .foregroundColor(DS.Color.textSecondary)
                                Text(selected.fullName)
                                    .font(DS.Font.calloutBold)
                                    .foregroundColor(DS.Color.success)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    withAnimation(DS.Anim.snappy) { selectedMember = nil }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(DS.Color.textTertiary)
                                }
                            }
                            .padding(DS.Spacing.sm)
                            .background(DS.Color.success.opacity(0.08))
                            .cornerRadius(DS.Radius.md)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(DS.Spacing.lg)
                    .background(DS.Color.surface)

                    // حقل البحث
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(searchFocused ? DS.Color.primary : DS.Color.textTertiary)
                        TextField(L10n.t("ابحث عن عضو...", "Search member..."), text: $searchText)
                            .focused($searchFocused)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                        }
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.lg)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .stroke(searchFocused ? DS.Color.primary : DS.Color.inactiveBorder, lineWidth: searchFocused ? 2 : 1))
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)

                    // القائمة
                    List {
                        ForEach(candidates) { member in
                            let isSelected = selectedMember?.id == member.id
                            Button {
                                withAnimation(DS.Anim.snappy) {
                                    selectedMember = isSelected ? nil : member
                                }
                            } label: {
                                HStack(spacing: DS.Spacing.md) {
                                    ZStack {
                                        Circle()
                                            .fill(isSelected ? DS.Color.success.opacity(0.15) : DS.Color.primary.opacity(0.08))
                                            .frame(width: 38, height: 38)
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(DS.Font.scaled(14, weight: .bold))
                                                .foregroundColor(DS.Color.success)
                                        } else {
                                            Text(member.fullName.prefix(1))
                                                .font(DS.Font.scaled(16, weight: .bold))
                                                .foregroundColor(DS.Color.primary)
                                        }
                                    }
                                    Text(member.fullName)
                                        .font(DS.Font.callout)
                                        .foregroundColor(DS.Color.textPrimary)
                                        .lineLimit(2)
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(DS.Color.gradientPrimary)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .padding(.vertical, DS.Spacing.xs)
                            }
                            .buttonStyle(DSScaleButtonStyle())
                            .listRowBackground(
                                isSelected ? DS.Color.success.opacity(0.05) : Color.clear
                            )
                            .listRowSeparator(isSelected ? .hidden : .visible)
                        }
                    }
                    .listStyle(.plain)

                    // زر الربط
                    DSPrimaryButton(
                        L10n.t("ربط بهذا العضو", "Link to This Member"),
                        icon: "link.badge.plus",
                        isLoading: adminRequestVM.isLoading
                    ) {
                        showConfirm = true
                    }
                    .disabled(selectedMember == nil || adminRequestVM.isLoading)
                    .opacity(selectedMember == nil ? 0.5 : 1.0)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Color.surface)
                }
            }
            .navigationTitle(L10n.t("ربط بعضو موجود", "Link to Existing Member"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.Font.scaled(20))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
            }
            .animation(DS.Anim.snappy, value: selectedMember?.id)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .alert(
            L10n.t("تأكيد الربط", "Confirm Link"),
            isPresented: $showConfirm
        ) {
            Button(L10n.t("ربط", "Link"), role: .none) {
                guard let target = selectedMember else { return }
                Task {
                    await adminRequestVM.mergeMemberIntoTreeMember(
                        newMemberId: pendingMember.id,
                        existingTreeMemberId: target.id
                    )
                    dismiss()
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            if let target = selectedMember {
                Text(L10n.t(
                    "سيُربط حساب \(pendingMember.firstName) بسجل \(target.fullName) الموجود بالشجرة.\nسيحتفظ بموقعه وأبنائه وبياناته.",
                    "Account \(pendingMember.firstName) will be linked to \(target.fullName)'s existing tree record. Position, children and data will be preserved."
                ))
            }
        }
    }
}

// MARK: - شيت تعديل / إضافة رقم فعلي لعضو معلّق
struct PendingMemberPhoneSheet: View {
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    let member: FamilyMember
    /// عند true يفعّل العضو بعد حفظ الرقم (يُستخدم في «صحة الشجرة»)
    var activateOnSave: Bool = false

    @State private var selectedCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var localDigits: String = ""
    @State private var errorBanner: String? = nil

    private var canSave: Bool {
        !localDigits.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !adminRequestVM.isLoading
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    // العضو
                    HStack(spacing: DS.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(DS.Color.warning.opacity(0.15))
                                .frame(width: 46, height: 46)
                            Text(member.fullName.prefix(1))
                                .font(DS.Font.scaled(20, weight: .bold))
                                .foregroundColor(DS.Color.warning)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.fullName)
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.textPrimary)
                            Text(L10n.t("الرقم الحالي: ", "Current: ") + KuwaitPhone.display(member.phoneNumber))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.lg)

                    // الدولة + الرقم المحلي
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("الرقم الفعلي الجديد", "New real number"))
                            .font(DS.Font.scaled(12, weight: .semibold))
                            .foregroundColor(DS.Color.textSecondary)

                        DSPhoneField(
                            country: $selectedCountry,
                            digits: $localDigits,
                            placeholder: String(repeating: "X", count: selectedCountry.maxDigits)
                        )
                    }

                    Text(activateOnSave
                         ? L10n.t(
                            "سيُضاف الرقم ويُفعّل الحساب مباشرة بعد الحفظ.",
                            "The number will be added and the account activated right after saving.")
                         : L10n.t(
                            "يُحدَّث رقم العضو فقط — يبقى الطلب معلّقاً لتربطه بالشجرة أو ترفضه لاحقاً.",
                            "Only updates the member's number — the request stays pending so you can link or reject it later."))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)

                    if let errorBanner {
                        Text(errorBanner)
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.error)
                    }

                    Spacer()
                }
                .padding(DS.Spacing.lg)
            }
            .navigationTitle(L10n.t("رقم العضو", "Member Number"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .disabled(adminRequestVM.isLoading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("حفظ", "Save")) { save() }
                        .fontWeight(.bold)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                let detected = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
                selectedCountry = detected.country
                localDigits = detected.localDigits
                focused = true
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func save() {
        errorBanner = nil
        Task {
            let ok = await adminRequestVM.updatePendingMemberPhone(
                memberId: member.id,
                country: selectedCountry,
                localDigits: localDigits,
                activate: activateOnSave
            )
            if ok {
                dismiss()
            } else {
                errorBanner = adminRequestVM.errorMessage
                adminRequestVM.errorMessage = nil
            }
        }
    }
}

