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
    @State private var allDescendants: [UUID: Int] = [:]

    struct BranchNode: Identifiable {
        let member: FamilyMember
        let displayName: String      // اسم العرض (قد يختلف عن member.fullName للفروع الإضافية)
        let totalCount: Int          // العضو نفسه + ذرّيته
        let children: [BranchNode]   // مستوى واحد بس
        var id: UUID { member.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().scaleEffect(1.2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredNodes) { node in
                            branchRow(node, depth: 0)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, 44)
                    .scrollDismissesKeyboard(.interactively)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                }
            }
            .background(DS.Color.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                }
                // شريط البحث داخل الـ navigation bar — أعلى نقطة ممكنة
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundColor(DS.Color.textTertiary)
                        TextField(L10n.t("ابحث بالاسم...", "Search by name..."), text: $search)
                            .font(DS.Font.footnote)
                            .textFieldStyle(.plain)
                            .submitLabel(.search)
                            .frame(minWidth: 180)
                        if !search.isEmpty {
                            Button { search = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DS.Color.surface, in: Capsule())
                }
            }
        }
        .task {
            await computeTree()
        }
    }

    // البحث: لو في نص، نفتش في جميع الأعضاء (مو فقط شجرة الفروع المبنية)
    private var filteredNodes: [BranchNode] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return rootChildren }

        return allMembers
            .filter { m in
                m.fullName.localizedCaseInsensitiveContains(q)
            }
            .map { m in
                BranchNode(
                    member: m,
                    displayName: m.fullName,
                    totalCount: (allDescendants[m.id] ?? 0) + 1,
                    children: []
                )
            }
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

                // الاختيار — معكوس: الاسم على الجهة الأولى، الـ avatar على الجهة الثانية
                Button {
                    onSelect(node.member.id)
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                if node.member.isDeceased == true {
                                    Image(systemName: "leaf.fill")
                                        .font(DS.Font.scaled(9))
                                        .foregroundColor(DS.Color.textTertiary)
                                }
                                Text(node.displayName)
                                    .font(depth == 0 ? DS.Font.calloutBold : DS.Font.callout)
                                    .foregroundColor(DS.Color.textPrimary)
                                    .lineLimit(1)
                            }
                            Text(L10n.t("\(node.totalCount) عضو", "\(node.totalCount) members"))
                                .font(DS.Font.caption2)
                                .foregroundColor(DS.Color.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        DSMemberAvatar(
                            name: node.member.fullName,
                            avatarUrl: node.member.avatarUrl,
                            size: depth == 0 ? 40 : 34,
                            roleColor: DS.Color.textTertiary
                        )
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
        let result = await Task.detached(priority: .userInitiated) {
            return Self.buildTree(from: members)
        }.value

        await MainActor.run {
            self.rootChildren = result.nodes
            self.allDescendants = result.descendants
            // الجيل الأول فقط ظاهر من البداية — الأجيال الثانية وما بعدها تظهر بالضغط على السهم
            self.expanded = []
            self.isLoading = false
        }
    }

    struct TreeBuildResult {
        let nodes: [BranchNode]
        let descendants: [UUID: Int]
    }

    nonisolated static func buildTree(from members: [FamilyMember]) -> TreeBuildResult {
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

        guard let root else { return TreeBuildResult(nodes: [], descendants: [:]) }

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

        // 4) ابنِ الـ tree: مستوى 1 (أبناء) + مستوى 2 (أحفاد) + مستوى 3 (أبناء أحفاد).
        // كل الفروع تعرض المستوى الثالث تلقائياً.
        let bigBranchThreshold = 0

        func node(for member: FamilyMember, depth: Int) -> BranchNode {
            let kids: [BranchNode]
            // depth 0 = ابن مباشر لعبدالله، depth 1 = حفيد، depth 2 = ابن حفيد
            if depth == 0 {
                // دائماً نولّد أبناء (المستوى 2)
                kids = (childrenByFather[member.id] ?? [])
                    .map { node(for: $0, depth: 1) }
                    .sorted { $0.member.sortOrder < $1.member.sortOrder }
            } else if depth == 1 && (descendants[member.id] ?? 0) > bigBranchThreshold {
                // المستوى 3: تلقائياً للفروع التي ذرّيتها > الحد المُعرّف
                kids = (childrenByFather[member.id] ?? [])
                    .map { node(for: $0, depth: 2) }
                    .sorted { $0.member.sortOrder < $1.member.sortOrder }
            } else {
                kids = []
            }
            return BranchNode(
                member: member,
                displayName: member.fullName,
                totalCount: (descendants[member.id] ?? 0) + 1,
                children: kids
            )
        }

        let directChildren = childrenByFather[root.id] ?? []
        let directChildrenIds = Set(directChildren.map { $0.id })

        // ===== فروع إضافية (أحفاد) تظهر مباشرة في القائمة الرئيسية =====
        // نفس قائمة web (CustomReportClient.tsx)
        let extraTopLevelNames: [String] = [
            "محمدعلي حسن المحمدعلي",
            "علي عبدالمحسن المحمدعلي",
            "محمدحسن احمد المحمدعلي",
            "ابراهيم(العطار) المحمدعلي",
        ]

        var extraNodes: [BranchNode] = []
        var usedExtraIds: Set<UUID> = []
        for name in extraTopLevelNames {
            let candidates = members.filter { m in
                !directChildrenIds.contains(m.id) &&
                !usedExtraIds.contains(m.id) &&
                matchesExtraName(fullName: m.fullName, query: name)
            }
            guard !candidates.isEmpty else { continue }
            // اختار الاسم الأقصر — الجد الفعلي، مو الأحفاد العميقة
            let sorted = candidates.sorted { $0.fullName.count < $1.fullName.count }
            let m = sorted[0]
            let base = node(for: m, depth: 0)
            // عرض الاسم بالصيغة القصيرة بدل full_name الكامل من DB
            let overridden = BranchNode(
                member: base.member,
                displayName: name,
                totalCount: base.totalCount,
                children: base.children
            )
            extraNodes.append(overridden)
            usedExtraIds.insert(m.id)
        }

        let sortedDirect = directChildren
            .map { node(for: $0, depth: 0) }
            .sorted { $0.member.sortOrder < $1.member.sortOrder }

        return TreeBuildResult(
            nodes: sortedDirect + extraNodes,
            descendants: descendants
        )
    }

    // MARK: - مطابقة الفروع الإضافية

    /// تطبيع الحروف العربية: همزات، تاء مربوطة، ألف مقصورة، تشكيل
    nonisolated private static func normalizeArabic(_ s: String) -> String {
        var r = s
        r = r.replacingOccurrences(of: "أ", with: "ا")
        r = r.replacingOccurrences(of: "إ", with: "ا")
        r = r.replacingOccurrences(of: "آ", with: "ا")
        r = r.replacingOccurrences(of: "ى", with: "ي")
        r = r.replacingOccurrences(of: "ة", with: "ه")
        let tashkeel: Set<Character> = ["ً","ٌ","ٍ","َ","ُ","ِ","ّ","ْ","ـ"]
        r = String(r.filter { !tashkeel.contains($0) })
        return r
    }

    /// تجريد الأقواس والفواصل وتوحيد المسافات
    nonisolated private static func cleanName(_ s: String) -> String {
        var r = normalizeArabic(s)
        for ch in ["(", ")", "،", ","] {
            r = r.replacingOccurrences(of: ch, with: " ")
        }
        while r.contains("  ") {
            r = r.replacingOccurrences(of: "  ", with: " ")
        }
        return r.trimmingCharacters(in: .whitespaces)
    }

    /// إزالة كل المسافات (لمطابقة "محمدعلي" مع "محمد علي")
    nonisolated private static func compressName(_ s: String) -> String {
        return cleanName(s).replacingOccurrences(of: " ", with: "")
    }

    /// مطابقة: full_name يبدأ بأول كلمات الاستعلام (مع تجاهل المسافات داخل
    /// الأسماء المركبة) وينتهي بآخر كلمة (عادة "المحمدعلي").
    nonisolated private static func matchesExtraName(fullName: String, query: String) -> Bool {
        let tokens = cleanName(query).split(separator: " ").map(String.init)
        guard tokens.count >= 2 else { return false }
        let lastQ = tokens.last!
        let restQ = tokens.dropLast().joined(separator: " ")
        let fnC = compressName(fullName)
        let restQC = compressName(restQ)
        let lastQC = compressName(lastQ)
        guard !restQC.isEmpty, !lastQC.isEmpty else { return false }
        return fnC.hasPrefix(restQC) && fnC.hasSuffix(lastQC)
    }
}
