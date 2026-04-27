import SwiftUI

/// شيت اختيار فرع — شجري متوسّع
/// المستوى الأول: أبناء عبدالله المباشرين (يخفي عبدالله نفسه)
/// كل ابن يتوسّع ليبين أحفاده (مستوى ثاني)
struct BranchPickerSheet: View {
    let allMembers: [FamilyMember]
    let onSelect: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var rootChildren: [BranchNode] = []
    @State private var expanded: Set<UUID> = []
    @State private var isLoading = true

    struct BranchNode: Identifiable {
        let member: FamilyMember
        let totalCount: Int          // العضو نفسه + ذرّيته
        let children: [BranchNode]   // مستوى واحد بس
        var id: UUID { member.id }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DS.Color.textTertiary)
                    TextField(L10n.t("ابحث بالاسم...", "Search by name..."), text: $search)
                        .font(DS.Font.callout)
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(DS.Color.textTertiary)
                        }
                    }
                }
                .padding(DS.Spacing.md)
                .background(DS.Color.surface)
                .cornerRadius(DS.Radius.lg)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)

                if isLoading {
                    Spacer()
                    ProgressView().scaleEffect(1.2)
                    Spacer()
                } else {
                    List {
                        ForEach(filteredNodes) { node in
                            branchRow(node, depth: 0)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(DS.Color.background)
            .navigationTitle(L10n.t("اختر فرعاً", "Pick a branch"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                }
            }
        }
        .task {
            await computeTree()
        }
    }

    // البحث: لو في نص بحث، نسطّح كل المستويات ونفلتر
    private var filteredNodes: [BranchNode] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return rootChildren }

        var matches: [BranchNode] = []
        func walk(_ node: BranchNode) {
            if node.member.fullName.localizedCaseInsensitiveContains(q) {
                matches.append(BranchNode(
                    member: node.member,
                    totalCount: node.totalCount,
                    children: []
                ))
            }
            for child in node.children {
                walk(child)
            }
        }
        for parent in rootChildren {
            walk(parent)
        }
        return matches
    }

    private func branchRow(_ node: BranchNode, depth: Int) -> AnyView {
        AnyView(branchRowContent(node, depth: depth))
    }

    @ViewBuilder
    private func branchRowContent(_ node: BranchNode, depth: Int) -> some View {
        let isExpanded = expanded.contains(node.id)
        let canExpand = !node.children.isEmpty

        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                // زر التوسعة
                if canExpand {
                    Button {
                        withAnimation(DS.Anim.snappy) {
                            if isExpanded { expanded.remove(node.id) }
                            else { expanded.insert(node.id) }
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.left")
                            .font(DS.Font.scaled(11, weight: .bold))
                            .foregroundColor(DS.Color.textSecondary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(DS.Color.surface))
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 22)
                }

                // الاختيار
                Button {
                    onSelect(node.member.id)
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        DSMemberAvatar(
                            name: node.member.fullName,
                            avatarUrl: node.member.avatarUrl,
                            size: depth == 0 ? 40 : 34,
                            roleColor: node.member.roleColor
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(node.member.fullName)
                                    .font(depth == 0 ? DS.Font.calloutBold : DS.Font.callout)
                                    .foregroundColor(DS.Color.textPrimary)
                                    .lineLimit(1)
                                if node.member.isDeceased == true {
                                    Image(systemName: "leaf.fill")
                                        .font(DS.Font.scaled(9))
                                        .foregroundColor(DS.Color.textTertiary)
                                }
                            }
                            Text(L10n.t("\(node.totalCount) عضو", "\(node.totalCount) members"))
                                .font(DS.Font.caption2)
                                .foregroundColor(DS.Color.textTertiary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, CGFloat(depth) * 24)
            .padding(.vertical, 4)

            // أبناء هذا الفرع
            if isExpanded {
                ForEach(node.children) { child in
                    branchRow(child, depth: depth + 1)
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func computeTree() async {
        let members = allMembers
        let computed = await Task.detached(priority: .userInitiated) {
            return Self.buildTree(from: members)
        }.value

        await MainActor.run {
            self.rootChildren = computed
            self.isLoading = false
        }
    }

    nonisolated static func buildTree(from members: [FamilyMember]) -> [BranchNode] {
        // 1) خريطة الأبناء حسب الأب
        var childrenByFather: [UUID: [FamilyMember]] = [:]
        for m in members {
            if let f = m.fatherId {
                childrenByFather[f, default: []].append(m)
            }
        }

        // 2) لقّ الجذر — عبدالله المحمدعلي
        let root: FamilyMember? = members.first { m in
            m.fatherId == nil &&
            m.fullName.contains("عبدالله") && m.fullName.contains("المحمدعلي")
        } ?? members.first { m in
            m.fullName.trimmingCharacters(in: .whitespaces) == "عبدالله المحمدعلي"
        } ?? members.first { $0.fatherId == nil }

        guard let root else { return [] }

        // 3) احسب ذرّيات كل عضو بـ memoization (post-order)
        var descendants: [UUID: Int] = [:]
        var visited: Set<UUID> = []
        var order: [UUID] = []
        var stack: [(UUID, Bool)] = []

        for m in members {
            if visited.contains(m.id) { continue }
            stack.append((m.id, false))
            while let (cur, processed) = stack.popLast() {
                if processed { order.append(cur); continue }
                if visited.contains(cur) { continue }
                visited.insert(cur)
                stack.append((cur, true))
                for c in childrenByFather[cur] ?? [] {
                    if !visited.contains(c.id) {
                        stack.append((c.id, false))
                    }
                }
            }
        }
        for id in order {
            var count = 0
            for c in childrenByFather[id] ?? [] {
                count += 1 + (descendants[c.id] ?? 0)
            }
            descendants[id] = count
        }

        // 4) ابنِ الـ tree: مستوى 1 (أبناء) + مستوى 2 (أحفاد) + مستوى 3 لـ حسين علي وحسين ابراهيم(العطار) فقط
        func shouldExpandThirdLevel(_ name: String) -> Bool {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return (trimmed.hasPrefix("حسين علي") || trimmed.hasPrefix("حسين ابراهيم"))
                && trimmed.contains("المحمدعلي")
        }

        func node(for member: FamilyMember, depth: Int) -> BranchNode {
            let kids: [BranchNode]
            // depth 0 = ابن مباشر لعبدالله، depth 1 = حفيد، depth 2 = ابن حفيد
            if depth == 0 {
                // دائماً نولّد أبناء (المستوى 2)
                kids = (childrenByFather[member.id] ?? [])
                    .map { node(for: $0, depth: 1) }
                    .sorted { $0.member.sortOrder < $1.member.sortOrder }
            } else if depth == 1 && shouldExpandThirdLevel(member.fullName) {
                // المستوى 3: فقط لحسين علي وحسين ابراهيم(العطار)
                kids = (childrenByFather[member.id] ?? [])
                    .map { node(for: $0, depth: 2) }
                    .sorted { $0.member.sortOrder < $1.member.sortOrder }
            } else {
                kids = []
            }
            return BranchNode(
                member: member,
                totalCount: (descendants[member.id] ?? 0) + 1,
                children: kids
            )
        }

        let directChildren = childrenByFather[root.id] ?? []
        return directChildren
            .map { node(for: $0, depth: 0) }
            .sorted { $0.member.sortOrder < $1.member.sortOrder }
    }
}
