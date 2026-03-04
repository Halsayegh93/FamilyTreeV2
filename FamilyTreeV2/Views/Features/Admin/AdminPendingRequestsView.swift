import SwiftUI

struct AdminPendingRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var selectedMemberForLinking: FamilyMember?
    @State private var matchedIdsForSelected: [UUID] = []

    // تصفية الأعضاء الذين حالتهم "Pending"
    var pendingMembers: [FamilyMember] {
        authVM.allMembers.filter { $0.role == .pending }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            if pendingMembers.isEmpty {
                VStack(spacing: DS.Spacing.xl) {
                    ZStack {
                        Circle()
                            .fill(DS.Color.gridTree.opacity(0.08))
                            .frame(width: 140, height: 140)
                        Circle()
                            .fill(DS.Color.gridTree.opacity(0.12))
                            .frame(width: 100, height: 100)
                        Circle()
                            .fill(DS.Color.gradientPrimary)
                            .frame(width: 66, height: 66)
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .font(DS.Font.scaled(28, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text(L10n.t("لا توجد طلبات معلقة حالياً", "No pending requests"))
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textSecondary)
                }
            } else {
                List {
                    ForEach(pendingMembers) { member in
                        pendingMemberCard(member: member)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(L10n.t("طلبات الربط", "Link Requests"))
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .sheet(item: $selectedMemberForLinking) { member in
            FatherLinkApprovalSheet(member: member, suggestedMatchIds: matchedIdsForSelected)
                .environmentObject(authVM)
        }
        .task { await authVM.fetchAllMembers() }
    }

    func pendingMemberCard(member: FamilyMember) -> some View {
        DSCard {
            VStack(spacing: DS.Spacing.lg) {

                // Accent bar
                LinearGradient(
                    colors: [DS.Color.warning, DS.Color.warning.opacity(0.6)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 4)
                .cornerRadius(DS.Radius.full)

                HStack(spacing: DS.Spacing.lg) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [DS.Color.warning.opacity(0.3), DS.Color.warning.opacity(0.1)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 50, height: 50)

                        Text(member.fullName.prefix(1))
                            .font(DS.Font.headline)
                            .foregroundColor(DS.Color.warning)
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(member.fullName)
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)

                        // عرض الاسم الخماسي بشكل واضح
                        let parts = member.fullName.split(whereSeparator: \.isWhitespace)
                        if parts.count >= 5 {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(DS.Font.scaled(10))
                                    .foregroundColor(DS.Color.success)
                                Text(L10n.t("اسم خماسي مكتمل", "Full 5-part name"))
                                    .font(DS.Font.scaled(10))
                                    .foregroundColor(DS.Color.success)
                            }
                        }

                        Text(L10n.t("سجل في: \(member.createdAt?.prefix(10) ?? "—")", "Registered: \(member.createdAt?.prefix(10) ?? "—")"))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textSecondary)
                    }

                    Spacer()
                }

                DSApproveRejectButtons(
                    approveTitle: L10n.t("ربط بالشجرة", "Link to Tree"),
                    rejectTitle: L10n.t("رفض", "Reject"),
                    isLoading: authVM.isLoading
                ) {
                    Task {
                        let ids = await authVM.fetchMatchedMemberIds(for: member.id)
                        await MainActor.run {
                            matchedIdsForSelected = ids
                            selectedMemberForLinking = member
                        }
                    }
                } onReject: {
                    Task {
                        await authVM.rejectOrDeleteMember(memberId: member.id)
                    }
                }
            }
            .padding(DS.Spacing.lg)
        }
    }
}

struct FatherLinkApprovalSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @FocusState private var isSearchFocused: Bool

    let member: FamilyMember
    let suggestedMatchIds: [UUID]
    @State private var searchText = ""
    @State private var selectedFatherId: UUID?

    /// المرشحون: المطابقات المقترحة أولاً ثم الباقي
    private var fatherCandidates: [FamilyMember] {
        let candidates = authVM.allMembers.filter { $0.role != .pending && $0.id != member.id }

        if searchText.isEmpty {
            // المطابقات المقترحة أولاً
            let suggested = candidates.filter { suggestedMatchIds.contains($0.id) }
            let others = candidates.filter { !suggestedMatchIds.contains($0.id) }
            return suggested + others.prefix(20)
        }
        return candidates.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.md) {

                // Header icon
                ZStack {
                    Circle()
                        .fill(DS.Color.gradientPrimary)
                        .frame(width: 56, height: 56)
                    Image(systemName: "link.badge.plus")
                        .font(DS.Font.scaled(22, weight: .semibold))
                        .foregroundColor(.white)
                }
                .dsGlowShadow()
                .padding(.top, DS.Spacing.sm)

                // عرض اسم العضو الجديد بوضوح
                VStack(spacing: DS.Spacing.xs) {
                    Text(L10n.t("ربط العضو بالأب قبل التفعيل", "Link member to father before activation"))
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textPrimary)

                    Text(member.fullName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(DS.Color.primary.opacity(0.08))
                        .cornerRadius(DS.Radius.md)
                }

                // شريط معلومات المطابقات
                if !suggestedMatchIds.isEmpty {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(DS.Font.scaled(14))
                            .foregroundColor(DS.Color.success)
                        Text(L10n.t(
                            "وُجدت \(suggestedMatchIds.count) مطابقة محتملة بالاسم",
                            "\(suggestedMatchIds.count) potential name match(es) found"
                        ))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.success)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.success.opacity(0.08))
                    .cornerRadius(DS.Radius.md)
                } else {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "info.circle.fill")
                            .font(DS.Font.scaled(14))
                            .foregroundColor(DS.Color.warning)
                        Text(L10n.t("لا توجد مطابقات — اختر الأب يدوياً", "No matches — select father manually"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.warning)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.warning.opacity(0.08))
                    .cornerRadius(DS.Radius.md)
                }

                // حقل البحث
                HStack(spacing: DS.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(DS.Color.gradientPrimary)
                            .frame(width: 32, height: 32)
                        Image(systemName: "magnifyingglass")
                            .font(DS.Font.scaled(12, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    TextField(L10n.t("ابحث عن الأب...", "Search for father..."), text: $searchText)
                        .multilineTextAlignment(.leading)
                        .font(DS.Font.body)
                        .focused($isSearchFocused)
                }
                .padding(DS.Spacing.md)
                .background(DS.Color.surface)
                .cornerRadius(DS.Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(isSearchFocused ? DS.Color.primary : Color.gray.opacity(0.12), lineWidth: isSearchFocused ? 2 : 1)
                )
                .animation(.easeInOut(duration: 0.2), value: isSearchFocused)

                List(fatherCandidates) { father in
                    Button {
                        selectedFatherId = father.id
                    } label: {
                        HStack(spacing: DS.Spacing.md) {
                            if selectedFatherId == father.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(DS.Font.scaled(20))
                                    .foregroundStyle(DS.Color.gradientPrimary)
                            } else {
                                Image(systemName: "circle")
                                    .font(DS.Font.scaled(20))
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(father.fullName)
                                    .font(DS.Font.callout)
                                    .foregroundColor(DS.Color.textPrimary)
                                // علامة المطابقة المقترحة
                                if suggestedMatchIds.contains(father.id) {
                                    Text(L10n.t("مطابقة محتملة", "Potential match"))
                                        .font(DS.Font.scaled(10, weight: .semibold))
                                        .foregroundColor(DS.Color.success)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(DS.Color.success.opacity(0.12))
                                        .cornerRadius(DS.Radius.sm)
                                }
                            }
                        }
                    }
                    .listRowBackground(
                        suggestedMatchIds.contains(father.id)
                            ? DS.Color.success.opacity(0.04)
                            : Color.clear
                    )
                }
                .listStyle(.plain)

                if selectedFatherId == nil {
                    Text(L10n.t("اختر الأب أولاً قبل تفعيل العضوية.", "Select father first before activating membership."))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                DSPrimaryButton(
                    L10n.t("تفعيل العضوية والربط", "Activate & Link"),
                    icon: "checkmark.circle.fill",
                    isLoading: authVM.isLoading
                ) {
                    Task {
                        await authVM.approveMember(memberId: member.id, fatherId: selectedFatherId)
                        dismiss()
                    }
                }
                .disabled(selectedFatherId == nil || authVM.isLoading)
                .opacity((selectedFatherId == nil || authVM.isLoading) ? 0.6 : 1.0)
            }
            .padding(DS.Spacing.lg)
            .navigationTitle(L10n.t("اعتماد طلب الربط", "Approve Link Request"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.error)
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}
