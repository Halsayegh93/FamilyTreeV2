// TreeViewPrototype.swift
// Self-contained prototype with 3 TreeView design variants.
// No external dependencies — runs standalone in Xcode Previews.
//
// Variants:
//   A — Bubble (current interactive style, refined)
//   B — Card Stack (horizontal cards with depth cues)
//   C — Compact List (indented list with role color rail)

import SwiftUI

// MARK: - Prototype Data Models

struct ProtoMember: Identifiable {
    let id: UUID
    let firstName: String
    let fullName: String
    let role: ProtoRole
    let isDeceased: Bool
    let birthYear: String?
    let deathYear: String?
    let fatherId: UUID?

    init(_ firstName: String, fullName: String? = nil, role: ProtoRole = .member,
         isDeceased: Bool = false, birthYear: String? = nil, deathYear: String? = nil,
         fatherId: UUID? = nil, id: UUID = UUID()) {
        self.id = id
        self.firstName = firstName
        self.fullName = fullName ?? firstName
        self.role = role
        self.isDeceased = isDeceased
        self.birthYear = birthYear
        self.deathYear = deathYear
        self.fatherId = fatherId
    }
}

enum ProtoRole {
    case admin, supervisor, member, pending

    var color: Color {
        switch self {
        case .admin:      return DS.Color.adminRole
        case .supervisor: return DS.Color.supervisorRole
        case .member:     return DS.Color.memberRole
        case .pending:    return DS.Color.pendingRole
        }
    }

    var label: String {
        switch self {
        case .admin:      return "Admin"
        case .supervisor: return "Supervisor"
        case .member:     return "Member"
        case .pending:    return "Pending"
        }
    }
}

// MARK: - Sample Data

extension ProtoMember {
    static let sampleTree: [ProtoMember] = {
        let rootId   = UUID()
        let son1Id   = UUID()
        let son2Id   = UUID()
        let son3Id   = UUID()
        let g1aId    = UUID()
        let g1bId    = UUID()
        let g2aId    = UUID()
        let g3aId    = UUID()
        let g3bId    = UUID()
        let g3cId    = UUID()
        let gg1Id    = UUID()

        return [
            ProtoMember("عبدالله", fullName: "عبدالله الرشيد",   role: .admin,      id: rootId),
            ProtoMember("محمد",    fullName: "محمد عبدالله",      role: .supervisor, fatherId: rootId,  id: son1Id),
            ProtoMember("أحمد",    fullName: "أحمد عبدالله",      role: .member,     fatherId: rootId,  id: son2Id),
            ProtoMember("علي",     fullName: "علي عبدالله",        role: .member,     isDeceased: true,
                        birthYear: "1955", deathYear: "2010",     fatherId: rootId,  id: son3Id),
            ProtoMember("فيصل",   fullName: "فيصل محمد",          role: .member,     fatherId: son1Id,  id: g1aId),
            ProtoMember("سلطان",  fullName: "سلطان محمد",         role: .member,     fatherId: son1Id,  id: g1bId),
            ProtoMember("عمر",    fullName: "عمر أحمد",           role: .pending,    fatherId: son2Id,  id: g2aId),
            ProtoMember("خالد",   fullName: "خالد علي",           role: .member,     fatherId: son3Id,  id: g3aId),
            ProtoMember("ناصر",   fullName: "ناصر علي",           role: .member,     fatherId: son3Id,  id: g3bId),
            ProtoMember("جاسم",   fullName: "جاسم علي",           role: .member,     fatherId: son3Id,  id: g3cId),
            ProtoMember("راشد",   fullName: "راشد فيصل",          role: .member,     fatherId: g1aId,   id: gg1Id),
        ]
    }()

    static func children(of id: UUID, in tree: [ProtoMember]) -> [ProtoMember] {
        tree.filter { $0.fatherId == id }
    }

    static func roots(in tree: [ProtoMember]) -> [ProtoMember] {
        let ids = Set(tree.map { $0.id })
        return tree.filter { m in
            guard let fid = m.fatherId else { return true }
            return !ids.contains(fid)
        }
    }
}

// MARK: - Variant Picker Shell

enum TreeVariant: String, CaseIterable {
    case bubble  = "A — Bubble"
    case card    = "B — Card Stack"
    case list    = "C — Compact List"
}

struct TreeViewPrototype: View {
    @State private var variant: TreeVariant = .bubble
    @State private var selectedMember: ProtoMember? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Variant Picker
                Picker("Variant", selection: $variant) {
                    ForEach(TreeVariant.allCases, id: \.self) { v in
                        Text(v.rawValue).tag(v)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemGroupedBackground))

                Divider()

                // Active Variant
                Group {
                    switch variant {
                    case .bubble:
                        VariantA_Bubble(members: ProtoMember.sampleTree, onSelect: { selectedMember = $0 })
                    case .card:
                        VariantB_CardStack(members: ProtoMember.sampleTree, onSelect: { selectedMember = $0 })
                    case .list:
                        VariantC_CompactList(members: ProtoMember.sampleTree, onSelect: { selectedMember = $0 })
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: variant)
            }
            .navigationTitle("شجرة العائلة")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .sheet(item: $selectedMember) { member in
            ProtoMemberDetailSheet(member: member)
                .presentationDetents([.medium])
        }
    }
}

// MARK: - Variant A: Bubble (Refined interactive style)

struct VariantA_Bubble: View {
    let members: [ProtoMember]
    let onSelect: (ProtoMember) -> Void

    @State private var expandedIds: Set<UUID> = []
    @State private var scale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Engraved grid background
                VariantA_Background()
                    .ignoresSafeArea()

                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    ZStack {
                        ForEach(ProtoMember.roots(in: members)) { root in
                            VariantA_Branch(
                                member: root,
                                members: members,
                                expandedIds: $expandedIds,
                                level: 0,
                                onSelect: onSelect
                            )
                        }
                    }
                    .scaleEffect(scale)
                    .padding(80)
                    .frame(minWidth: geometry.size.width,
                           minHeight: geometry.size.height)
                }

                // Zoom controls
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VariantA_ZoomControls(scale: $scale)
                            .padding(.trailing, 20)
                            .padding(.bottom, 30)
                    }
                }
            }
        }
    }
}

struct VariantA_Background: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            Canvas { ctx, size in
                let step: CGFloat = 34
                var lines = Path()
                var x: CGFloat = 0
                while x <= size.width { lines.move(to: .init(x: x, y: 0)); lines.addLine(to: .init(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y <= size.height { lines.move(to: .init(x: 0, y: y)); lines.addLine(to: .init(x: size.width, y: y)); y += step }
                ctx.stroke(lines, with: .color(.primary.opacity(colorScheme == .dark ? 0.04 : 0.05)), lineWidth: 0.5)
            }
        }
    }
}

struct VariantA_Branch: View {
    let member: ProtoMember
    let members: [ProtoMember]
    @Binding var expandedIds: Set<UUID>
    let level: Int
    let onSelect: (ProtoMember) -> Void

    private var children: [ProtoMember] { ProtoMember.children(of: member.id, in: members) }
    private var isExpanded: Bool { expandedIds.contains(member.id) }

    var body: some View {
        VStack(spacing: 0) {
            // Node
            VariantA_Node(member: member, isExpanded: isExpanded,
                          hasChildren: !children.isEmpty,
                          onTap: { onSelect(member) },
                          onToggle: {
                              withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                  if isExpanded { expandedIds.remove(member.id) }
                                  else { expandedIds.insert(member.id) }
                              }
                          })

            // Connector + children
            if isExpanded && !children.isEmpty {
                VStack(spacing: 8) {
                    Rectangle()
                        .fill(DS.Color.primary.opacity(0.35))
                        .frame(width: 1.5, height: 16)

                    // Chunk children into rows of 3
                    let chunks = stride(from: 0, to: children.count, by: 3).map {
                        Array(children[$0..<min($0 + 3, children.count)])
                    }
                    ForEach(0..<chunks.count, id: \.self) { ri in
                        HStack(alignment: .top, spacing: 28) {
                            ForEach(chunks[ri]) { child in
                                VariantA_Branch(member: child, members: members,
                                                expandedIds: $expandedIds,
                                                level: level + 1,
                                                onSelect: onSelect)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct VariantA_Node: View {
    let member: ProtoMember
    let isExpanded: Bool
    let hasChildren: Bool
    let onTap: () -> Void
    let onToggle: () -> Void

    private let size: CGFloat = 72

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                ZStack {
                    Circle()
                        .fill(member.isDeceased ? Color.gray.opacity(0.75) : member.role.color.opacity(0.9))
                        .frame(width: size, height: size)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)

                    Image(systemName: "person.fill")
                        .resizable().scaledToFit()
                        .frame(width: 28)
                        .foregroundColor(.white.opacity(0.65))

                    // Deceased overlay
                    if member.isDeceased {
                        VStack {
                            Spacer()
                            Text(lifeSpan)
                                .font(DS.Font.scaled(8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(DS.Color.deceased.opacity(0.85))
                                .clipShape(Capsule())
                                .padding(.bottom, 4)
                        }
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                    }
                }
            }
            .buttonStyle(.plain)

            Button(action: onToggle) {
                VStack(spacing: 4) {
                    Text(member.firstName)
                        .font(DS.Font.scaled(11, weight: .bold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .frame(minWidth: 72)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.08), radius: 2)

                    if hasChildren {
                        ZStack {
                            Circle()
                                .fill(DS.Color.primary)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
                                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(DS.Font.scaled(11, weight: .black))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
        }
        .fixedSize()
    }

    private var lifeSpan: String {
        guard let b = member.birthYear, let d = member.deathYear else { return "متوفى" }
        return "\(b)–\(d)"
    }
}

struct VariantA_ZoomControls: View {
    @Binding var scale: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation { scale = min(scale + 0.25, 2.5) } } label: {
                Image(systemName: "plus").frame(width: 44, height: 42)
            }
            Divider().frame(width: 24)
            Button { scale = 1.0 } label: {
                Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 42)
            }
            Divider().frame(width: 24)
            Button { withAnimation { scale = max(scale - 0.25, 0.4) } } label: {
                Image(systemName: "minus").frame(width: 44, height: 42)
            }
        }
        .font(DS.Font.scaled(15, weight: .bold))
        .foregroundColor(.primary)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }
}

// MARK: - Variant B: Card Stack (depth cues, horizontal cards)

struct VariantB_CardStack: View {
    let members: [ProtoMember]
    let onSelect: (ProtoMember) -> Void

    @State private var expandedIds: Set<UUID> = []

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(ProtoMember.roots(in: members)) { root in
                    VariantB_CardBranch(member: root, members: members,
                                        expandedIds: $expandedIds,
                                        depth: 0, onSelect: onSelect)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

struct VariantB_CardBranch: View {
    let member: ProtoMember
    let members: [ProtoMember]
    @Binding var expandedIds: Set<UUID>
    let depth: Int
    let onSelect: (ProtoMember) -> Void

    private var children: [ProtoMember] { ProtoMember.children(of: member.id, in: members) }
    private var isExpanded: Bool { expandedIds.contains(member.id) }

    var body: some View {
        VStack(spacing: 0) {
            // The card row
            HStack(spacing: 0) {
                // Depth rail
                if depth > 0 {
                    HStack(spacing: 6) {
                        ForEach(0..<depth, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(width: 16)
                        }
                    }
                }

                // Card
                Button(action: { onSelect(member) }) {
                    HStack(spacing: 12) {
                        // Avatar circle
                        ZStack {
                            Circle()
                                .fill(member.isDeceased ? Color.gray.opacity(0.7) : member.role.color.opacity(0.15))
                                .frame(width: 46, height: 46)
                            Circle()
                                .stroke(member.isDeceased ? Color.gray.opacity(0.4) : member.role.color.opacity(0.5), lineWidth: 1.5)
                                .frame(width: 46, height: 46)
                            Text(String(member.firstName.prefix(1)))
                                .font(DS.Font.scaled(18, weight: .bold))
                                .foregroundColor(member.isDeceased ? .gray : member.role.color)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(member.fullName)
                                .font(DS.Font.scaled(14, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                Text(member.role.label)
                                    .font(DS.Font.scaled(11, weight: .medium))
                                    .foregroundColor(member.role.color)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(member.role.color.opacity(0.1))
                                    .clipShape(Capsule())

                                if member.isDeceased {
                                    Text(lifeSpan)
                                        .font(DS.Font.scaled(11, weight: .medium))
                                        .foregroundColor(DS.Color.deceased.opacity(0.8))
                                }
                            }
                        }

                        Spacer()

                        if !children.isEmpty {
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    if isExpanded { expandedIds.remove(member.id) }
                                    else { expandedIds.insert(member.id) }
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text("\(children.count)")
                                        .font(DS.Font.scaled(12, weight: .bold))
                                        .foregroundColor(.secondary)
                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .font(DS.Font.scaled(12, weight: .bold))
                                        .foregroundColor(DS.Color.primary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(DS.Color.primary.opacity(0.08))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: depth == 0 ? 16 : 12))
                    .shadow(color: .black.opacity(depth == 0 ? 0.06 : 0.03),
                            radius: depth == 0 ? 6 : 3, y: depth == 0 ? 2 : 1)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, depth == 0 ? 12 : 6)

            // Children
            if isExpanded && !children.isEmpty {
                VStack(spacing: 0) {
                    ForEach(children) { child in
                        VariantB_CardBranch(member: child, members: members,
                                            expandedIds: $expandedIds,
                                            depth: depth + 1, onSelect: onSelect)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
        }
    }

    private var lifeSpan: String {
        guard let b = member.birthYear, let d = member.deathYear else { return "متوفى" }
        return "\(b)–\(d)"
    }
}

// MARK: - Variant C: Compact List (indented list with role color rail)

struct VariantC_CompactList: View {
    let members: [ProtoMember]
    let onSelect: (ProtoMember) -> Void

    @State private var expandedIds: Set<UUID> = []

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(ProtoMember.roots(in: members)) { root in
                    VariantC_Row(member: root, members: members,
                                 expandedIds: $expandedIds,
                                 depth: 0, onSelect: onSelect)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

struct VariantC_Row: View {
    let member: ProtoMember
    let members: [ProtoMember]
    @Binding var expandedIds: Set<UUID>
    let depth: Int
    let onSelect: (ProtoMember) -> Void

    private var children: [ProtoMember] { ProtoMember.children(of: member.id, in: members) }
    private var isExpanded: Bool { expandedIds.contains(member.id) }
    private let indent: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { onSelect(member) }) {
                HStack(spacing: 0) {
                    // Indentation with color rail
                    if depth > 0 {
                        ZStack(alignment: .leading) {
                            Color.clear.frame(width: CGFloat(depth) * indent)
                            Rectangle()
                                .fill(member.role.color.opacity(0.35))
                                .frame(width: 2)
                                .padding(.leading, CGFloat(depth) * indent - 1)
                        }
                    }

                    HStack(spacing: 10) {
                        // Role dot
                        Circle()
                            .fill(member.isDeceased ? Color.gray.opacity(0.7) : member.role.color)
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(member.fullName)
                                .font(DS.Font.scaled(13, weight: depth == 0 ? .bold : .semibold))
                                .foregroundColor(member.isDeceased ? .secondary : .primary)
                                .strikethrough(member.isDeceased, color: .secondary)

                            if member.isDeceased, let b = member.birthYear, let d = member.deathYear {
                                Text("\(b)–\(d)")
                                    .font(DS.Font.scaled(10, weight: .medium))
                                    .foregroundColor(DS.Color.deceased.opacity(0.7))
                            }
                        }

                        Spacer()

                        if !children.isEmpty {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if isExpanded { expandedIds.remove(member.id) }
                                    else { expandedIds.insert(member.id) }
                                }
                            }) {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.left")
                                    .font(DS.Font.scaled(11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.trailing, 14)
                    .padding(.leading, depth == 0 ? 16 : 8)
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
            }
            .buttonStyle(.plain)

            // Separator
            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(height: 0.5)
                .padding(.leading, depth == 0 ? 16 : CGFloat(depth) * indent + 8)

            // Children
            if isExpanded && !children.isEmpty {
                ForEach(children) { child in
                    VariantC_Row(member: child, members: members,
                                 expandedIds: $expandedIds,
                                 depth: depth + 1, onSelect: onSelect)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
        }
    }
}

// MARK: - Shared Member Detail Sheet

struct ProtoMemberDetailSheet: View {
    let member: ProtoMember
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 16)

            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(member.isDeceased ? Color.gray.opacity(0.2) : member.role.color.opacity(0.12))
                        .frame(width: 88, height: 88)
                    Circle()
                        .stroke(member.isDeceased ? Color.gray.opacity(0.4) : member.role.color.opacity(0.4), lineWidth: 2)
                        .frame(width: 88, height: 88)
                    Text(String(member.firstName.prefix(1)))
                        .font(DS.Font.scaled(36, weight: .bold))
                        .foregroundColor(member.isDeceased ? .gray : member.role.color)
                }

                VStack(spacing: 4) {
                    Text(member.fullName)
                        .font(DS.Font.scaled(20, weight: .bold))
                    Text(member.role.label)
                        .font(DS.Font.scaled(13, weight: .medium))
                        .foregroundColor(member.role.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(member.role.color.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding(.bottom, 20)

            Divider()

            // Info rows
            VStack(spacing: 0) {
                if member.isDeceased {
                    DetailInfoRow(icon: "heart.slash.fill", label: "الوفاة",
                                  value: member.deathYear ?? "—", color: DS.Color.deceased)
                    Divider().padding(.leading, 52)
                }
                if let b = member.birthYear {
                    DetailInfoRow(icon: "calendar", label: "الميلاد", value: b, color: DS.Color.primary)
                }
                DetailInfoRow(icon: "person.2.fill", label: "الدور",
                              value: member.role.label, color: member.role.color)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Spacer()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .environment(\.layoutDirection, .rightToLeft)
    }
}

struct DetailInfoRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(color.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(DS.Font.scaled(15))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(DS.Font.scaled(11, weight: .medium))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(DS.Font.scaled(14, weight: .semibold))
                    .foregroundColor(.primary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Previews

#Preview("Prototype — All Variants") {
    TreeViewPrototype()
}

#Preview("A — Bubble") {
    NavigationStack {
        VariantA_Bubble(members: ProtoMember.sampleTree, onSelect: { _ in })
            .navigationTitle("شجرة العائلة")
            .navigationBarTitleDisplayMode(.inline)
    }
    .environment(\.layoutDirection, .rightToLeft)
}

#Preview("B — Card Stack") {
    NavigationStack {
        VariantB_CardStack(members: ProtoMember.sampleTree, onSelect: { _ in })
            .navigationTitle("شجرة العائلة")
            .navigationBarTitleDisplayMode(.inline)
    }
    .environment(\.layoutDirection, .rightToLeft)
}

#Preview("C — Compact List") {
    NavigationStack {
        VariantC_CompactList(members: ProtoMember.sampleTree, onSelect: { _ in })
            .navigationTitle("شجرة العائلة")
            .navigationBarTitleDisplayMode(.inline)
    }
    .environment(\.layoutDirection, .rightToLeft)
}

#Preview("Member Detail Sheet") {
    ProtoMemberDetailSheet(member: ProtoMember.sampleTree[0])
}
