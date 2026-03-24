import SwiftUI
import Supabase

// MARK: - Admin Tree Health View
/// واجهة صحة الشجرة — تكشف الأعضاء المشكلين (يتائم، بدون أسماء، روابط مكسورة)
struct AdminTreeHealthView: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @State private var appeared = false
    @State private var searchText = ""
    @State private var selectedFilter: TreeIssueFilter = .orphan
    @State private var memberToLinkFather: FamilyMember?
    @State private var memberToEditName: FamilyMember?
    @State private var memberToToggleHidden: FamilyMember?
    @State private var showToggleHiddenConfirm = false
    @State private var memberToDelete: FamilyMember?
    @State private var showDeleteConfirm = false
    @State private var displayLimit = 20

    // MARK: - Cached data (computed once per allMembers change)
    @State private var cachedIssueMembers: [FamilyMember] = []
    @State private var cachedMemberIssues: [UUID: Set<TreeIssueFilter>] = [:]
    @State private var cachedCounts: [TreeIssueFilter: Int] = [:]

    // MARK: - Filter Enum

    enum TreeIssueFilter: String, CaseIterable {
        case orphan, noName, brokenParent, hiddenFromTree, duplicatePhone

        var label: String {
            switch self {
            case .orphan:         return L10n.t("معلّق", "Unlinked")
            case .noName:         return L10n.t("بدون اسم", "No Name")
            case .brokenParent:   return L10n.t("رابط مكسور", "Broken Link")
            case .hiddenFromTree: return L10n.t("مخفي", "Hidden")
            case .duplicatePhone: return L10n.t("رقم مكرر", "Dup Phone")
            }
        }

        var icon: String {
            switch self {
            case .orphan:         return "person.fill.xmark"
            case .noName:         return "textformat.abc.dottedunderline"
            case .brokenParent:   return "link.badge.plus"
            case .hiddenFromTree: return "eye.slash"
            case .duplicatePhone: return "phone.badge.waveform"
            }
        }

        var color: Color {
            switch self {
            case .orphan:         return DS.Color.error
            case .noName:         return DS.Color.warning
            case .brokenParent:   return DS.Color.info
            case .hiddenFromTree: return DS.Color.textTertiary
            case .duplicatePhone: return DS.Color.neonPink
            }
        }
    }

    @State private var memberToClearPhone: FamilyMember?
    @State private var showClearPhoneConfirm = false

    // MARK: - Rebuild Cache (called once when data changes)

    private func rebuildCache() {
        let allActive = memberVM.allMembers.filter { $0.role != .pending && $0.status != .frozen }
        let fatherIds = Set(allActive.compactMap(\.fatherId))
        let activeIds = Set(allActive.map(\.id))

        var issues: [UUID: Set<TreeIssueFilter>] = [:]
        var result: [FamilyMember] = []

        for member in memberVM.allMembers where member.status != .frozen {
            var memberIssues = Set<TreeIssueFilter>()

            // Orphan: بدون أب + بدون أبناء
            if member.fatherId == nil && !fatherIds.contains(member.id) && member.role != .pending {
                memberIssues.insert(.orphan)
            }

            // No name
            let name = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty || name == "بدون اسم" {
                memberIssues.insert(.noName)
            }

            // Broken parent
            if let fid = member.fatherId, !activeIds.contains(fid) {
                memberIssues.insert(.brokenParent)
            }

            // Hidden from tree
            if member.isHiddenFromTree {
                memberIssues.insert(.hiddenFromTree)
            }

            if !memberIssues.isEmpty {
                issues[member.id] = memberIssues
                result.append(member)
            }
        }

        // Duplicate phones
        let dupGroups = memberVM.duplicatePhoneGroups
        for group in dupGroups {
            for member in group {
                issues[member.id, default: []].insert(.duplicatePhone)
                if !result.contains(where: { $0.id == member.id }) {
                    result.append(member)
                }
            }
        }

        result.sort { $0.fullName < $1.fullName }

        // Compute counts
        var counts: [TreeIssueFilter: Int] = [:]
        for filter in TreeIssueFilter.allCases {
            counts[filter] = issues.values.filter { $0.contains(filter) }.count
        }

        cachedIssueMembers = result
        cachedMemberIssues = issues
        cachedCounts = counts
    }

    // MARK: - Filtered Data (lightweight — uses cache)

    private var filteredMembers: [FamilyMember] {
        var members = cachedIssueMembers.filter { cachedMemberIssues[$0.id]?.contains(selectedFilter) == true }
        if !searchText.isEmpty {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            members = members.filter {
                $0.fullName.localizedCaseInsensitiveContains(query)
                || ($0.phoneNumber ?? "").contains(query)
            }
        }
        return members
    }

    private func issueLabels(for member: FamilyMember) -> [TreeIssueFilter] {
        guard let issues = cachedMemberIssues[member.id] else { return [] }
        return TreeIssueFilter.allCases.filter { issues.contains($0) }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if cachedIssueMembers.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    filterChips
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.xs)

                    // Swipe hint
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "hand.draw")
                            .font(DS.Font.scaled(10, weight: .medium))
                        Text(L10n.t(
                            "← سحب لإجراءات سريعة →",
                            "← Swipe for quick actions →"
                        ))
                        .font(DS.Font.caption2)
                    }
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.horizontal, DS.Spacing.lg)

                    // Search
                    searchBar
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.xs)

                    if filteredMembers.isEmpty {
                        noResultsState
                    } else {
                        List {
                            let visible = Array(filteredMembers.prefix(displayLimit))
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, member in
                                let memberIssues = cachedMemberIssues[member.id] ?? []
                                memberRow(member: member, index: index)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            memberToDelete = member
                                            showDeleteConfirm = true
                                        } label: {
                                            Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                                        }
                                        if memberIssues.contains(.orphan) || memberIssues.contains(.brokenParent) {
                                            Button {
                                                memberToLinkFather = member
                                            } label: {
                                                Label(L10n.t("ربط أب", "Link Father"), systemImage: "person.line.dotted.person")
                                            }
                                            .tint(DS.Color.info)
                                        }
                                        if memberIssues.contains(.noName) {
                                            Button {
                                                memberToEditName = member
                                            } label: {
                                                Label(L10n.t("تعديل اسم", "Edit Name"), systemImage: "pencil")
                                            }
                                            .tint(DS.Color.warning)
                                        }
                                        if memberIssues.contains(.duplicatePhone) {
                                            Button {
                                                memberToClearPhone = member
                                                showClearPhoneConfirm = true
                                            } label: {
                                                Label(L10n.t("مسح الرقم", "Clear Phone"), systemImage: "phone.badge.minus")
                                            }
                                            .tint(DS.Color.neonPink)
                                        }
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        Button {
                                            memberToToggleHidden = member
                                            showToggleHiddenConfirm = true
                                        } label: {
                                            Label(
                                                member.isHiddenFromTree
                                                    ? L10n.t("إظهار", "Show")
                                                    : L10n.t("إخفاء", "Hide"),
                                                systemImage: member.isHiddenFromTree ? "eye" : "eye.slash"
                                            )
                                        }
                                        .tint(member.isHiddenFromTree ? DS.Color.success : DS.Color.textTertiary)
                                    }
                            }

                            if displayLimit < filteredMembers.count {
                                Button {
                                    displayLimit += 20
                                } label: {
                                    HStack {
                                        Spacer()
                                        Text(L10n.t(
                                            "عرض المزيد (\(filteredMembers.count - displayLimit) متبقي)",
                                            "Show more (\(filteredMembers.count - displayLimit) remaining)"
                                        ))
                                        .font(DS.Font.caption1)
                                        .foregroundColor(DS.Color.primary)
                                        Spacer()
                                    }
                                    .padding(.vertical, DS.Spacing.sm)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
        }
        .navigationTitle(L10n.t("صحة الشجرة", "Tree Health"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            L10n.t("تأكيد", "Confirm"),
            isPresented: $showToggleHiddenConfirm,
            presenting: memberToToggleHidden
        ) { member in
            Button(member.isHiddenFromTree
                   ? L10n.t("إظهار بالشجرة", "Show in Tree")
                   : L10n.t("إخفاء من الشجرة", "Hide from Tree")
            ) {
                Task { await toggleHidden(member) }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: { member in
            Text(member.isHiddenFromTree
                 ? L10n.t("إظهار \(member.fullName) بالشجرة؟", "Show \(member.fullName) in tree?")
                 : L10n.t("إخفاء \(member.fullName) من الشجرة؟", "Hide \(member.fullName) from tree?")
            )
        }
        .alert(
            L10n.t("حذف العضو نهائياً", "Delete Member Permanently"),
            isPresented: $showDeleteConfirm,
            presenting: memberToDelete
        ) { member in
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                Task { await memberVM.deleteMember(memberId: member.id) }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: { member in
            Text(L10n.t(
                "هل أنت متأكد من حذف \(member.fullName)؟ هذا الإجراء لا يمكن التراجع عنه.",
                "Are you sure you want to delete \(member.fullName)? This action cannot be undone."
            ))
        }
        .alert(
            L10n.t("مسح رقم الهاتف", "Clear Phone Number"),
            isPresented: $showClearPhoneConfirm,
            presenting: memberToClearPhone
        ) { member in
            Button(L10n.t("مسح", "Clear"), role: .destructive) {
                Task {
                    await memberVM.clearPhoneNumber(for: member.id)
                    rebuildCache()
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: { member in
            let phone = member.phoneNumber ?? ""
            Text(L10n.t(
                "مسح رقم \(KuwaitPhone.display(phone)) من \(member.fullName)؟",
                "Clear \(KuwaitPhone.display(phone)) from \(member.fullName)?"
            ))
        }
        .sheet(item: $memberToLinkFather) { member in
            LinkFatherSheet(member: member, memberVM: memberVM)
        }
        .sheet(item: $memberToEditName) { member in
            EditNameSheet(member: member, memberVM: memberVM)
        }
        .onAppear {
            withAnimation(DS.Anim.smooth.delay(0.15)) {
                appeared = true
            }
            rebuildCache()
            if (cachedCounts[selectedFilter] ?? 0) == 0 {
                if let first = TreeIssueFilter.allCases.first(where: { (cachedCounts[$0] ?? 0) > 0 }) {
                    selectedFilter = first
                }
            }
        }
        .onChange(of: memberVM.membersVersion) { _, _ in
            rebuildCache()
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Toggle Hidden

    private func toggleHidden(_ member: FamilyMember) async {
        let newValue = !member.isHiddenFromTree
        do {
            try await SupabaseConfig.client
                .from("profiles")
                .update(["is_hidden_from_tree": newValue])
                .eq("id", value: member.id.uuidString)
                .execute()
            await memberVM.fetchAllMembers(force: true)
        } catch {
            Log.error("Toggle hidden failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(TreeIssueFilter.allCases, id: \.self) { filter in
                    let filterCount = cachedCounts[filter] ?? 0
                    Button {
                        withAnimation(DS.Anim.snappy) { selectedFilter = filter; displayLimit = 20 }
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: filter.icon)
                                .font(DS.Font.scaled(11, weight: .bold))
                            Text(filter.label)
                                .font(DS.Font.scaled(13, weight: .bold))
                            if filterCount > 0 {
                                Text("\(filterCount)")
                                    .font(DS.Font.scaled(11, weight: .heavy))
                                    .foregroundColor(selectedFilter == filter ? .white : filter.color)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule().fill(selectedFilter == filter ? .white.opacity(0.25) : filter.color.opacity(0.15))
                                    )
                            }
                        }
                        .foregroundColor(selectedFilter == filter ? .white : filter.color)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(
                            Capsule().fill(selectedFilter == filter ? filter.color : DS.Color.surface)
                        )
                        .overlay(
                            Capsule().stroke(selectedFilter == filter ? .clear : filter.color.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DS.Color.textTertiary)
                .font(DS.Font.scaled(14, weight: .medium))
            TextField(L10n.t("بحث بالاسم أو الرقم...", "Search by name or phone..."), text: $searchText)
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textPrimary)
                .onChange(of: searchText) { displayLimit = 20 }
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .cornerRadius(DS.Radius.md)
    }

    // MARK: - Member Row

    private func memberRow(member: FamilyMember, index: Int) -> some View {
        HStack(spacing: DS.Spacing.md) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [selectedFilter.color.opacity(0.3), selectedFilter.color.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                let initial = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                Text(initial.isEmpty ? "?" : String(initial.prefix(1)))
                    .font(DS.Font.headline)
                    .foregroundColor(selectedFilter.color)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                // Name
                let displayName = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                Text(displayName.isEmpty ? L10n.t("بدون اسم", "No Name") : displayName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(displayName.isEmpty ? DS.Color.textTertiary : DS.Color.textPrimary)
                    .lineLimit(2)

                // Phone
                if let phone = member.phoneNumber, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(phone)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }

                // Issue tags
                let issues = issueLabels(for: member)
                if !issues.isEmpty {
                    HStack(spacing: DS.Spacing.xs) {
                        ForEach(issues, id: \.self) { tag in
                            HStack(spacing: 2) {
                                Image(systemName: tag.icon)
                                    .font(DS.Font.scaled(8, weight: .bold))
                                Text(tag.label)
                                    .font(DS.Font.scaled(9, weight: .bold))
                            }
                            .foregroundColor(tag.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(tag.color.opacity(0.10))
                            .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // Role badge
            DSRoleBadge(title: member.roleName, color: member.roleColor)
        }
        .padding(.vertical, DS.Spacing.xs)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(DS.Color.success)
            Text(L10n.t("الشجرة سليمة!", "Tree is Healthy!"))
                .font(DS.Font.title2)
                .foregroundColor(DS.Color.textPrimary)
            Text(L10n.t("ما في أعضاء مشكلين حالياً", "No problematic members found"))
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(DS.Color.textTertiary)
            Text(L10n.t("لا توجد نتائج", "No Results"))
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, DS.Spacing.xxxxl)
    }
}

// MARK: - Edit Name Sheet

struct EditNameSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @State private var fullName: String = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.xl) {
                DSSheetHeader(
                    title: L10n.t("تعديل الاسم", "Edit Name"),
                    isLoading: isSaving,
                    onCancel: { dismiss() },
                    onConfirm: { Task { await saveName() } }
                )

                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text(L10n.t("الاسم الكامل", "Full Name"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textSecondary)

                    DSTextField(
                        label: L10n.t("الاسم الكامل", "Full Name"),
                        placeholder: L10n.t("أدخل الاسم الكامل...", "Enter full name..."),
                        text: $fullName,
                        icon: "person.fill"
                    )
                }
                .padding(.horizontal, DS.Spacing.lg)

                if let phone = member.phoneNumber, !phone.isEmpty {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "phone.fill")
                            .foregroundColor(DS.Color.textTertiary)
                        Text(phone)
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                }

                Spacer()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            let name = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            fullName = (name == "بدون اسم") ? "" : name
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .presentationDetents([.medium])
    }

    private func saveName() async {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        await memberVM.updateMemberName(memberId: member.id, fullName: trimmed)
        isSaving = false
        dismiss()
    }
}
