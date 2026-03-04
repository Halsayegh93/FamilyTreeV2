import SwiftUI

// MARK: - Family Directory View — دليل الأعضاء
struct FamilyDirectoryView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    @State private var sortOption: SortOption = .name
    @State private var filterRole: FamilyMember.UserRole? = nil
    @State private var showDeceasedOnly = false
    @State private var selectedMember: FamilyMember? = nil
    
    @State private var cachedFilteredMembers: [FamilyMember] = []
    @State private var cachedMembersByLetter: [(String, [FamilyMember])] = []
    
    enum SortOption: String, CaseIterable {
        case name, role, newest
        var label: String {
            switch self {
            case .name: return L10n.t("الاسم", "Name")
            case .role: return L10n.t("الدور", "Role")
            case .newest: return L10n.t("الأحدث", "Newest")
            }
        }
        var icon: String {
            switch self {
            case .name: return "textformat"
            case .role: return "shield.fill"
            case .newest: return "clock.fill"
            }
        }
    }
    
    private func rebuildFilteredMembers() {
        var members = authVM.allMembers.filter {
            $0.role != .pending && !$0.isHiddenFromTree
        }
        
        // فلتر البحث
        if !searchText.isEmpty {
            let folded = searchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            members = members.filter {
                $0.fullName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(folded) ||
                $0.firstName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(folded)
            }
        }
        
        // فلتر الدور
        if let role = filterRole {
            members = members.filter { $0.role == role }
        }
        
        // فلتر المتوفين
        if showDeceasedOnly {
            members = members.filter { $0.isDeceased ?? false }
        }
        
        // الترتيب
        switch sortOption {
        case .name:
            members.sort { $0.firstName < $1.firstName }
        case .role:
            members.sort { $0.role.rawValue < $1.role.rawValue }
        case .newest:
            members.sort { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
        }
        
        cachedFilteredMembers = members
        
        // تجميع حسب الحرف
        if sortOption == .name {
            let grouped = Dictionary(grouping: members) { member -> String in
                let first = member.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
                return String(first.prefix(1)).uppercased()
            }
            cachedMembersByLetter = grouped.sorted { $0.key < $1.key }
        } else {
            cachedMembersByLetter = [("", members)]
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()
                DSDecorativeBackground()
                
                VStack(spacing: 0) {
                    // شريط البحث
                    searchBar
                    
                    // الفلاتر
                    filterBar
                    
                    // عدد النتائج
                    HStack {
                        Text("\(cachedFilteredMembers.count) " + L10n.t("عضو", "members"))
                            .font(DS.Font.scaled(12, weight: .semibold))
                            .foregroundColor(DS.Color.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.xs)
                    
                    // قائمة الأعضاء
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(cachedMembersByLetter, id: \.0) { letter, members in
                                if sortOption == .name && !letter.isEmpty {
                                    Section {
                                        ForEach(members) { member in
                                            memberRow(member)
                                        }
                                    } header: {
                                        sectionHeader(letter)
                                    }
                                } else {
                                    ForEach(members) { member in
                                        memberRow(member)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, DS.Spacing.xxxl)
                    }
                }
            }
            .navigationTitle(L10n.t("دليل الأعضاء", "Member Directory"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.Font.scaled(22, weight: .medium))
                            .foregroundStyle(DS.Color.textTertiary)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .sheet(item: $selectedMember) { member in
                MemberDetailsView(member: member)
                    .presentationDetents([.medium, .large])
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear { rebuildFilteredMembers() }
        .onChange(of: searchText) { _, _ in rebuildFilteredMembers() }
        .onChange(of: sortOption) { _, _ in rebuildFilteredMembers() }
        .onChange(of: filterRole) { _, _ in rebuildFilteredMembers() }
        .onChange(of: showDeceasedOnly) { _, _ in rebuildFilteredMembers() }
        .onChange(of: authVM.allMembers.count) { _, _ in rebuildFilteredMembers() }
    }
    
    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: DS.Spacing.md - 2) {
            Image(systemName: "magnifyingglass")
                .font(DS.Font.scaled(14, weight: .semibold))
                .foregroundColor(DS.Color.primary)
            
            TextField(L10n.t("ابحث بالاسم...", "Search by name..."), text: $searchText)
                .font(DS.Font.body)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Font.scaled(16))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(Color.gray.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.sm)
    }
    
    // MARK: - Filter Bar
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                // ترتيب
                Menu {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button {
                            withAnimation { sortOption = option }
                        } label: {
                            Label(option.label, systemImage: option.icon)
                        }
                    }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(DS.Font.scaled(10, weight: .semibold))
                        Text(sortOption.label)
                            .font(DS.Font.scaled(11, weight: .semibold))
                    }
                    .foregroundColor(DS.Color.primary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.primary.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(DS.Color.primary.opacity(0.2), lineWidth: 1))
                }
                
                // فلتر الأدوار
                ForEach([FamilyMember.UserRole.admin, .supervisor, .member], id: \.self) { role in
                    let isActive = filterRole == role
                    Button {
                        withAnimation { filterRole = isActive ? nil : role }
                    } label: {
                        Text(roleName(role))
                            .font(DS.Font.scaled(11, weight: .semibold))
                            .foregroundColor(isActive ? .white : DS.Color.textSecondary)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.sm)
                            .background(Capsule().fill(isActive ? role.color : DS.Color.surface))
                            .overlay(Capsule().stroke(isActive ? role.color : Color.gray.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                
                // فلتر المتوفين
                Button {
                    withAnimation { showDeceasedOnly.toggle() }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: showDeceasedOnly ? "checkmark.circle.fill" : "circle")
                            .font(DS.Font.scaled(10))
                        Text(L10n.t("المتوفين", "Deceased"))
                            .font(DS.Font.scaled(11, weight: .semibold))
                    }
                    .foregroundColor(showDeceasedOnly ? .white : DS.Color.textSecondary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(Capsule().fill(showDeceasedOnly ? DS.Color.deceased : DS.Color.surface))
                    .overlay(Capsule().stroke(showDeceasedOnly ? DS.Color.deceased : Color.gray.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
        }
    }
    
    // MARK: - Section Header
    private func sectionHeader(_ letter: String) -> some View {
        HStack {
            Text(letter)
                .font(DS.Font.scaled(13, weight: .black))
                .foregroundColor(DS.Color.primary)
                .frame(width: 28, height: 28)
                .background(DS.Color.primary.opacity(0.1))
                .clipShape(Circle())
            
            Rectangle()
                .fill(DS.Color.primary.opacity(0.15))
                .frame(height: 1)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.background.opacity(0.95))
    }
    
    // MARK: - Member Row
    private func memberRow(_ member: FamilyMember) -> some View {
        Button {
            selectedMember = member
        } label: {
            HStack(spacing: DS.Spacing.md) {
                // صورة
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [member.roleColor, member.roleColor.opacity(0.6)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    if let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
                        CachedAsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Text(String(member.firstName.prefix(1)))
                                .font(DS.Font.scaled(18, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                    } else {
                        Text(String(member.firstName.prefix(1)))
                            .font(DS.Font.scaled(18, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    if member.isDeceased ?? false {
                        VStack {
                            Spacer()
                            HStack { Spacer()
                                Circle()
                                    .fill(DS.Color.deceased)
                                    .frame(width: 14, height: 14)
                                    .overlay(
                                        Image(systemName: "heart.slash.fill")
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                            }
                        }
                        .frame(width: 48, height: 48)
                    }
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(member.fullName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: DS.Spacing.sm) {
                        // شارة الدور
                        HStack(spacing: 3) {
                            Circle()
                                .fill(member.roleColor)
                                .frame(width: 6, height: 6)
                            Text(member.roleName)
                                .font(DS.Font.scaled(10, weight: .semibold))
                                .foregroundColor(member.roleColor)
                        }
                        
                        if let phone = member.phoneNumber, !phone.isEmpty, !(member.isPhoneHidden ?? false) {
                            Text("•")
                                .font(DS.Font.caption2)
                                .foregroundColor(DS.Color.textTertiary)
                            Text(KuwaitPhone.display(phone))
                                .font(DS.Font.scaled(10))
                                .foregroundColor(DS.Color.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                // زر اتصال
                if let phone = member.phoneNumber, !phone.isEmpty,
                   !(member.isPhoneHidden ?? false),
                   let callURL = KuwaitPhone.telURL(phone) {
                    Button {
                        UIApplication.shared.open(callURL)
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(DS.Font.scaled(13, weight: .semibold))
                            .foregroundColor(DS.Color.success)
                            .frame(width: 34, height: 34)
                            .background(DS.Color.success.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
        }
        .buttonStyle(DSScaleButtonStyle())
    }
    
    private func roleName(_ role: FamilyMember.UserRole) -> String {
        switch role {
        case .admin: return L10n.t("مدير", "Admin")
        case .supervisor: return L10n.t("مشرف", "Supervisor")
        case .member: return L10n.t("عضو", "Member")
        case .pending: return L10n.t("معلق", "Pending")
        }
    }
}
