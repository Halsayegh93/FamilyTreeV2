import SwiftUI

struct AdminPendingRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var selectedMemberForLinking: FamilyMember?

    // تصفية الأعضاء الذين حالتهم "Pending"
    var pendingMembers: [FamilyMember] {
        authVM.allMembers.filter { $0.role == .pending }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            if pendingMembers.isEmpty {
                // Empty state with gradient circles
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
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text("لا توجد طلبات معلقة حالياً")
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
        .navigationTitle(L10n.t("طلبات الانضمام", "Join Requests"))
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .sheet(item: $selectedMemberForLinking) { member in
            FatherLinkApprovalSheet(member: member)
                .environmentObject(authVM)
        }
        .onAppear {
            Task { await authVM.fetchAllMembers() }
        }
    }

    // بطاقة الطلب بتصميم مودرن
    func pendingMemberCard(member: FamilyMember) -> some View {
        DSCard {
            VStack(spacing: DS.Spacing.lg) {

                // Orange/warning gradient accent bar
                LinearGradient(
                    colors: [DS.Color.warning, DS.Color.warning.opacity(0.6)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 4)
                .cornerRadius(DS.Radius.full)

                HStack(spacing: DS.Spacing.lg) {
                    // Avatar — gradient-filled circle
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
                        Text("سجل في: \(member.createdAt?.prefix(10) ?? "تاريخ غير معروف")")
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textSecondary)
                    }

                    Spacer()
                }

                // داخل ForEach في ملف AdminPendingRequestsView.swift

                HStack(spacing: DS.Spacing.lg) {
                    // زر الرفض — DS.Color.error border
                    Button(action: {
                        Task {
                            await authVM.rejectOrDeleteMember(memberId: member.id)
                        }
                    }) {
                        Text("رفض")
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.error)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Spacing.md)
                            .background(DS.Color.error.opacity(0.08))
                            .cornerRadius(DS.Radius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.md)
                                    .stroke(DS.Color.error.opacity(0.3), lineWidth: 1.5)
                            )
                    }

                    // زر القبول — DSPrimaryButton gradient
                    Button(action: {
                        selectedMemberForLinking = member
                    }) {
                        ZStack {
                            if authVM.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("قبول العضوية")
                                    .font(DS.Font.calloutBold)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(DS.Color.gradientPrimary)
                        .cornerRadius(DS.Radius.md)
                        .dsGlowShadow()
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
    @State private var searchText = ""
    @State private var selectedFatherId: UUID?

    private var fatherCandidates: [FamilyMember] {
        let candidates = authVM.allMembers.filter { $0.role != .pending && $0.id != member.id }
        if searchText.isEmpty {
            return candidates.prefix(20).map { $0 }
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
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                }
                .dsGlowShadow()
                .padding(.top, DS.Spacing.sm)

                Text("ربط العضو بالأب قبل التفعيل")
                    .font(DS.Font.headline)
                    .foregroundColor(DS.Color.textPrimary)

                // DS styled search
                HStack(spacing: DS.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(DS.Color.gradientPrimary)
                            .frame(width: 32, height: 32)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    TextField("ابحث عن الأب...", text: $searchText)
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
                                    .font(.system(size: 20))
                                    .foregroundStyle(DS.Color.gradientPrimary)
                            } else {
                                Image(systemName: "circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                            Spacer()
                            Text(father.fullName)
                                .font(DS.Font.callout)
                                .foregroundColor(DS.Color.textPrimary)
                        }
                    }
                }
                .listStyle(.plain)

                if selectedFatherId == nil {
                    Text("اختر الأب أولاً قبل تفعيل العضوية.")
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // DSPrimaryButton gradient
                DSPrimaryButton(
                    "تفعيل العضوية",
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
            .navigationTitle("اعتماد الطلب")
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
