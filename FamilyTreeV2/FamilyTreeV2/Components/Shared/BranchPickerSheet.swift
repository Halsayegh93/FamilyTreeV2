import SwiftUI

/// مربّع اختيار فرع — شجري متوسّع، بمنتصف الشاشة بتصميم المربّعات الموحّد
/// (رأس ملوّن + بحث + الفروع صفوفاً + «إلغاء»): الضغط على الاسم يختار الفرع،
/// والسهم يعرض أبناءه تحته. يُفتح بـ `.dsCenterBox(isPresented:)`.
/// المستوى الأول: أبناء عبدالله المباشرين (يخفي عبدالله نفسه)
/// كل ابن يتوسّع ليبين أحفاده (مستوى ثاني)
struct BranchPickerSheet: View {
    let allMembers: [FamilyMember]
    /// الفرع المختار حالياً — عليه علامة ✓ (اختياري؛ الاستدعاء بدونه يبقى كما هو)
    var selectedId: UUID? = nil
    let onSelect: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var rootChildren: [BranchNode] = []
    @State private var expanded: Set<UUID> = []
    @State private var isLoading = true
    @State private var allDescendants: [UUID: Int] = [:]

    /// نتائج البحث (من كل الأعضاء — قد تكون آلافاً) فوق هذا العدد تُبنى كسولةً؛
    /// دونه صفوف عادية حتى يُقاس ارتفاع المربّع بدقّة (الكسولة تُبلِّغ ارتفاعاً ناقصاً للقصيرة)
    private static let lazyListThreshold = 40

    struct BranchNode: Identifiable {
        let member: FamilyMember
        let displayName: String      // اسم العرض (قد يختلف عن member.fullName للفروع الإضافية)
        let totalCount: Int          // العضو نفسه + ذرّيته
        let children: [BranchNode]   // مستوى واحد بس
        var id: UUID { member.id }
    }

    var body: some View {
        let nodes = filteredNodes
        let searching = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // الاختيار بالضغط على الاسم (المُستدعي يغلق المربّع كالسابق) — لا زر إجراء، «إلغاء» وحده
        return DSComposer(
            title: L10n.t("البحث بالفرع", "Search by branch"),
            subtitle: L10n.t("اختر فرعاً لحصر النتائج عليه", "Pick a branch to narrow the results"),
            icon: "tree.fill",
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            cancelTitle: L10n.t("إلغاء", "Cancel"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { dismiss() }
        ) {
            searchField
                .dsStaggerIn(0)

            DSComposerSection(
                title: searching ? L10n.t("نتائج البحث", "Search results")
                                 : L10n.t("فروع العائلة", "Family branches"),
                icon: searching ? "person.2.fill" : "tree.fill",
                tint: DS.Color.primary,
                trailing: isLoading ? nil : "\(nodes.count)",
                index: 1
            ) {
                branchList(nodes, searching: searching)
            }
        }
        .task {
            await computeTree()
        }
    }

    // MARK: - أجزاء المربّع

    /// البحث — حقل المربّعات بأيقونة العدسة، مع ✕ للمسح كالسابق
    private var searchField: some View {
        DSComposerField(icon: "magnifyingglass",
                        label: L10n.t("بحث", "Search"),
                        placeholder: L10n.t("ابحث بالاسم...", "Search by name..."),
                        text: $search)
            .submitLabel(.search)
            .overlay(alignment: .trailing) { clearSearchButton }
    }

    @ViewBuilder
    private var clearSearchButton: some View {
        if !search.isEmpty {
            Button { search = "" } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(DS.Color.textTertiary)
                    // مساحة ضغط ٤٤ نقطة (حد أبل) — مركز الأيقونة في مكانه (كان ٣٦ + هامش ٤)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("مسح البحث", "Clear search"))
        }
    }

    /// القائمة: تحميل ← لا نتائج ← الفروع (شجرة تتوسّع) أو نتائج البحث
    @ViewBuilder
    private func branchList(_ nodes: [BranchNode], searching: Bool) -> some View {
        if isLoading {
            ProgressView()
                .tint(DS.Color.primary)
                .scaleEffect(1.2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.xl)
        } else if nodes.isEmpty {
            Text(L10n.t("لا توجد نتائج", "No results"))
                .font(DS.Font.plex(13, weight: .semibold))
                .foregroundColor(DS.Color.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.md)
        } else if searching && nodes.count > Self.lazyListThreshold {
            // كسولة — البحث يشمل كل الأعضاء: تُبنى الصفوف الظاهرة فقط
            LazyVStack(spacing: DS.Spacing.sm) {
                ForEach(nodes) { node in
                    branchRow(node, depth: 0)
                }
            }
        } else {
            // صفوف عادية لا كسولة — تُقاس كاملةً فيأخذ المربّع ارتفاعها الصحيح
            VStack(spacing: DS.Spacing.sm) {
                ForEach(nodes) { node in
                    branchTree(node, depth: 0)
                }
            }
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

    /// الفرع + أبناؤه تحته عند التوسيع (مُزاحون بخط جانبي خفيف) — AnyView لأنها متداخلة
    private func branchTree(_ node: BranchNode, depth: Int) -> AnyView {
        let showsChildren = expanded.contains(node.id) && !node.children.isEmpty
        return AnyView(
            VStack(spacing: DS.Spacing.sm) {
                branchRow(node, depth: depth)
                if showsChildren {
                    childrenStack(node, depth: depth)
                }
            }
        )
    }

    /// أبناء الفرع — مُزاحون لجهة البداية مع خط يربطهم بالأب
    private func childrenStack(_ node: BranchNode, depth: Int) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(node.children) { child in
                branchTree(child, depth: depth + 1)
            }
        }
        .padding(.leading, DS.Spacing.lg)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(DS.Color.primary.opacity(0.2))
                .frame(width: 2)
                .padding(.leading, 6)
        }
        .transition(.opacity)
    }

    /// صف فرع: الصورة + الاسم (🍃 للمتوفى، ✓ للمختار حالياً) ثم سهم التوسعة إن كان له أبناء.
    /// الضغط على الصف يختار الفرع، والسهم يعرض أبناءه — نفس السابق.
    private func branchRow(_ node: BranchNode, depth: Int) -> some View {
        let isSelected = node.id == selectedId
        let isTop = depth == 0
        let canExpand = !node.children.isEmpty
        return Button {
            onSelect(node.member.id)
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSMemberAvatar(
                    name: node.member.fullName,
                    avatarUrl: node.member.avatarUrl,
                    size: isTop ? 36 : 32,
                    roleColor: DS.Color.primary
                )
                if node.member.isDeceased == true {
                    Image(systemName: "leaf.fill")
                        .font(DS.Font.scaled(11))
                        .foregroundColor(DS.Color.textTertiary)
                }
                Text(node.displayName)
                    .font(DS.Font.plex(isTop ? 14.5 : 14, weight: (isTop || isSelected) ? .bold : .regular))
                    .foregroundColor((isTop || isSelected) ? DS.Color.fieldLabel : DS.Color.fieldValue)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(DS.Color.primary)
                }
                if canExpand {
                    // مكان سهم التوسعة — الزر نفسه فوق الصف (ضغطته لا تختار الفرع)
                    Color.clear.frame(width: Self.expandButtonSize, height: Self.expandButtonSize)
                }
            }
            .branchRowBox(selected: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // القارئ الصوتي: اسم الفرع (+ «متوفى») بلا حرف الصورة البديلة ولا أسماء الرموز
        .accessibilityLabel(node.displayName
                            + (node.member.isDeceased == true ? L10n.t("، متوفى", ", deceased") : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay(alignment: .trailing) {
            if canExpand {
                expandButton(for: node)
                    // الدائرة في مكانها السابق (هامش الصف ١٠ + نصف ٣٠) ومنطقة الضغط ٤٤ حولها
                    .padding(.trailing, DS.Spacing.sm + 2 - (Self.expandHitSize - Self.expandButtonSize) / 2)
            }
        }
    }

    private static let expandButtonSize: CGFloat = 30
    /// منطقة ضغط سهم التوسعة — ٤٤ نقطة (حد أبل)، والدائرة ٣٠ كما هي
    private static let expandHitSize: CGFloat = 44

    /// سهم التوسعة — مغلق يشير لجهة القراءة (يسار بالعربي)، ومفتوح للأسفل
    private func expandButton(for node: BranchNode) -> some View {
        let isExpanded = expanded.contains(node.id)
        return Button {
            withAnimation(DS.Anim.snappy) {
                if isExpanded { expanded.remove(node.id) }
                else { expanded.insert(node.id) }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(DS.Color.primary)
                // الاتجاه يُعكس تلقائياً بالعربي — زاوية واحدة تشير لجهة القراءة باللغتين
                .rotationEffect(.degrees(isExpanded ? 0 : -90))
                .frame(width: Self.expandButtonSize, height: Self.expandButtonSize)
                .background(Circle().fill(DS.Color.primary.opacity(isExpanded ? 0.18 : 0.10)))
                // مساحة ضغط ٤٤ نقطة (حد أبل) حول الدائرة — الصف ٤٨+ فيسعها
                .frame(width: Self.expandHitSize, height: Self.expandHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? L10n.t("إخفاء الأبناء", "Hide sons")
                                       : L10n.t("عرض الأبناء", "Show sons"))
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

private extension View {
    /// صف الفرع: صندوق صفوف المربّعات + إطار بلون التطبيق للفرع المختار حالياً
    func branchRowBox(selected: Bool) -> some View {
        dsRowBox()
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Color.primary.opacity(selected ? 0.6 : 0), lineWidth: 1.5)
            )
    }
}
