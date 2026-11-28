import SwiftUI

// MARK: - «الوارد» ← طلب انضمام ← المطابقة في الشجرة: «أ — الأرجح أولاً» (اختيار المالك ٢٠٢٦-١١-٠٦)
//
// samples/occasions-and-matching — كانت تظهر ~٢٠ اسماً لأن «الاسم الأول + الأب» يكفي، فيضيع المطابق الحقيقي بينها.
// القاعدة (ترتيب على الجهاز فقط، فوق `NameMatcher.linkSuggestions` بلا تغيير على السيرفر):
// ١) المقارنة بالترتيب بعد حذف اسم العائلة: الأول ← الأب ← الجد ← جد الأب.
// ٢) «مطابق»: كل أسماء المتقدّم بالترتيب — يظهر أولاً ومحدّداً جاهزاً.
// ٣) «قريب»: السجلّ ينتهي قبلها بلا اختلاف، ثم من يطابق حتى الجد — ٣ كحدّ أقصى.
// ٤) «أضعف»: الأول والأب فقط — مخفيّ خلف «N أسماء أضعف»، ولا يظهر وحده إلا إذا ما في غيره.
// ٥) داخل الدرجة: الأقرب في سنة الميلاد، ومن يفرق ١٥ سنة فأكثر ينزل للأضعف.
// زرّ «ربط» واحد أسفل البطاقة يقول بمن («يُربط بـ …») — وبلا مطابق كامل أو قريب «اختر من الشجرة».

struct JoinMatchTiers {
    enum PartState { case match, differ, missing }

    struct Entry: Identifiable {
        let member: FamilyMember
        let depth: Int
        /// حالة كل اسم من أسماء المتقدّم أمام هذا السجلّ (للنقاط)
        let parts: [PartState]
        /// السجلّ ينتهي قبل أسماء المتقدّم بلا اختلاف
        let endsClean: Bool
        let gapYears: Int?
        let birthYear: String?
        let isServer: Bool
        var id: UUID { member.id }
    }

    /// أسماء المتقدّم كما كتبها (بلا العائلة) — شرائح «محمد ✓ علي ✓…»
    let applicantParts: [String]
    let applicantYear: String?
    let exact: [Entry]
    let near: [Entry]
    let weak: [Entry]

    static let empty = JoinMatchTiers(applicantParts: [], applicantYear: nil, exact: [], near: [], weak: [])
    static let nearLimit = 3
    static let farBirthYears = 15

    var total: Int { exact.count + near.count + weak.count }
    var strongCount: Int { exact.count + near.count }
    /// الأرجح — محدّد جاهزاً
    var suggested: Entry? { exact.first ?? near.first }
    var all: [Entry] { exact + near + weak }
    func entry(_ id: UUID?) -> Entry? { id.flatMap { id in all.first { $0.id == id } } }

    /// سنة الميلاد المعروفة («2026» الوهمي في الشجرة = مجهول)
    static func year(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count >= 4, !raw.hasPrefix("2026") else { return nil }
        let y = String(raw.prefix(4))
        return Int(y) == nil ? nil : y
    }

    /// `suggestions` مرتّبة من `NameMatcher.linkSuggestions` (العمق ثم قرب الميلاد)
    static func build(for applicant: FamilyMember, suggestions: [NameMatcher.LinkSuggestion]) -> JoinMatchTiers {
        guard !suggestions.isEmpty else { return .empty }
        let noise = NameMatcher.linkNoise(applicant.familyName)
        let chainA = NameMatcher.linkChain(applicant.nameUnits, noise: noise)
        let shown = applicant.nameUnits.filter { !NameMatcher.linkKey($0).isEmpty }
        let parts = Array(shown.prefix(chainA.count))
        var exact: [Entry] = [], near: [(Int, Entry)] = [], weak: [Entry] = []
        for (index, s) in suggestions.enumerated() {
            let m = s.member
            let chainB = NameMatcher.linkChain(m.nameUnits,
                                               noise: m.familyName.map { noise.union([NameMatcher.linkKey($0)]) } ?? noise)
            let exhausted = s.depth >= chainB.count
            let states: [PartState] = chainA.indices.map { i in
                if i < s.depth { return .match }
                if exhausted || i >= chainB.count { return .missing }
                return chainA[i] == chainB[i] ? .match : .differ
            }
            let endsClean = s.depth < chainA.count && exhausted
            let gap = s.birthGapDays.map { $0 / 365 }
            let far = (gap ?? 0) >= farBirthYears
            let e = Entry(member: m, depth: s.depth, parts: states, endsClean: endsClean, gapYears: gap,
                          birthYear: year(m.birthDate), isServer: s.isServer)
            if far { weak.append(e) }
            else if s.depth >= chainA.count { exact.append(e) }
            else if endsClean || s.depth >= 3 { near.append((index, e)) }
            else { weak.append(e) }
        }
        // «قريب»: المنتهي بلا اختلاف أولاً، ثم الأعمق — والترتيب الأصلي (قرب الميلاد) داخلها
        near.sort { a, b in
            if a.1.endsClean != b.1.endsClean { return a.1.endsClean }
            if a.1.depth != b.1.depth { return a.1.depth > b.1.depth }
            return a.0 < b.0
        }
        let nearShown = near.prefix(nearLimit).map(\.1)
        let overflow = near.dropFirst(nearLimit).map(\.1)
        return JoinMatchTiers(applicantParts: parts, applicantYear: year(applicant.birthDate),
                              exact: exact, near: Array(nearShown), weak: overflow + weak)
    }

    /// «الاسم الأول» · «الأب» · «الجد» · «جد الأب» · «الجد الـ4»
    static func position(_ i: Int) -> String {
        switch i {
        case 0: return L10n.t("الاسم الأول", "the first name")
        case 1: return L10n.t("الأب", "the father")
        case 2: return L10n.t("الجد", "the grandfather")
        case 3: return L10n.t("جد الأب", "the great-grandfather")
        default: return L10n.t("الجد الـ\(i - 1)", "ancestor \(i - 1)")
        }
    }

    /// سطر الميلاد: «مواليد 1994 · نفس سنة المتقدّم» / «· بفرق 3 سنوات» / «بلا تاريخ ميلاد»
    func birthLine(_ e: Entry) -> String {
        guard let y = e.birthYear else { return L10n.t("بلا تاريخ ميلاد", "No birth date") }
        let base = L10n.t("مواليد \(y)", "Born \(y)")
        guard let a = applicantYear, let ai = Int(a), let bi = Int(y) else { return base }
        let gap = abs(ai - bi)
        if gap == 0 { return base + L10n.t(" · نفس سنة المتقدّم", " · same year as the applicant") }
        return base + L10n.t(" · بفرق \(gap) سنة", " · \(gap) years apart")
    }

    /// السبب: «السجلّ ينتهي عند الجد · بلا اختلاف» أو «يختلف جد الأب · مواليد 1996»
    func reason(_ e: Entry) -> String {
        let head = e.endsClean
            ? L10n.t("السجلّ ينتهي عند \(Self.position(e.depth - 1)) · بلا اختلاف",
                     "Record ends at \(Self.position(e.depth - 1)) · no difference")
            : L10n.t("يختلف \(Self.position(e.depth))", "Differs at \(Self.position(e.depth))")
        if let y = e.birthYear { return head + L10n.t(" · مواليد \(y)", " · born \(y)") }
        return head + L10n.t(" · بلا تاريخ ميلاد", " · no birth date")
    }
}

// MARK: - اللوحة داخل بطاقة طلب الانضمام

struct JoinMatchPanel: View {
    let tiers: JoinMatchTiers
    let selectedId: UUID?
    let showsWeak: Bool
    let onSelect: (UUID) -> Void
    let onToggleWeak: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            header
            ForEach(tiers.exact) { e in exactCard(e) }
            if !tiers.near.isEmpty {
                HStack {
                    Text(L10n.t("قريب", "Close"))
                        .dsFont(.sectionTitle)
                        .foregroundColor(DS.Color.textTertiary)
                    Spacer(minLength: 0)
                    Text(verbatim: "\(tiers.near.count)")
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                }
                .accessibilityElement(children: .combine)
                ForEach(tiers.near) { e in compactRow(e) }
            }
            if !tiers.weak.isEmpty { weakToggle }
            if showsWeak { ForEach(tiers.weak) { e in compactRow(e) } }
            if let pick = tiers.entry(selectedId) { linkLine(pick) }
        }
    }

    // MARK: الأجزاء

    private var header: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .dsGlyph(DS.Glyph.xs)
                .accessibilityHidden(true)
            Text(L10n.t("في الشجرة", "In the tree"))
                .dsFont(.sectionTitle)
            Spacer(minLength: 0)
            Text(verbatim: L10n.t("\(tiers.strongCount) من \(tiers.total)", "\(tiers.strongCount) of \(tiers.total)"))
                .dsFont(.caption)
                .monospacedDigit()
        }
        .foregroundColor(DS.Color.textTertiary)
        .accessibilityElement(children: .combine)
    }

    private func radio(_ on: Bool) -> some View {
        Image(systemName: on ? "largecircle.fill.circle" : "circle")
            .dsGlyph(DS.Glyph.xl, weight: .regular)
            .foregroundColor(on ? AppSection.admin.ink : DS.Color.textTertiary)
            .accessibilityHidden(true)
    }

    /// «مطابق»: البطاقة المحدّدة — الاسم، شرائح الأسماء المتطابقة ✓، الميلاد، وشارة «مطابق»
    private func exactCard(_ e: JoinMatchTiers.Entry) -> some View {
        let on = selectedId == e.id
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        return Button { onSelect(e.id) } label: {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                radio(on)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(e.member.displayFullName)
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    FlowChips(parts: tiers.applicantParts)
                    HStack(spacing: DS.Spacing.sm) {
                        Text(tiers.birthLine(e))
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        DSStatusChip(text: L10n.t("مطابق", "Exact"), tint: DS.Color.success, size: .mini)
                    }
                }
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(DS.Color.surface))
            .overlay(shape.strokeBorder(on ? AppSection.admin.ink : DS.Color.cardBorder,
                                        lineWidth: on ? DS.Border.widthBold : DS.Border.width))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    /// «قريب»/«أضعف»: اختيار · الاسم · السبب · النقاط
    private func compactRow(_ e: JoinMatchTiers.Entry) -> some View {
        let on = selectedId == e.id
        return Button { onSelect(e.id) } label: {
            HStack(spacing: DS.Spacing.sm) {
                radio(on)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(e.member.displayFullName)
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tiers.reason(e))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DS.Spacing.xs)
                PartDots(states: e.parts)
            }
            .padding(.vertical, DS.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    /// «16 أسماء أضعف — الأول والأب فقط ⌄» — أو وحده بلا غيره: «لا مطابق كامل · 4 أسماء تطابق الأول والأب فقط»
    private var weakToggle: some View {
        let n = tiers.weak.count
        let alone = tiers.strongCount == 0
        let text = alone
            ? L10n.t("لا مطابق كامل · \(n) أسماء تطابق الأول والأب فقط", "No full match · \(n) match first name and father only")
            : L10n.t("\(n) أسماء أضعف — الأول والأب فقط", "\(n) weaker — first name and father only")
        return Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) { onToggleWeak() }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                if alone { PartDots(states: [.match, .match, .differ]) }
                Text(text)
                    .dsFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: showsWeak ? "chevron.up" : "chevron.down")
                    .dsGlyph(DS.Glyph.xs, weight: .semibold)
                    .accessibilityHidden(true)
            }
            .foregroundColor(DS.Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: alone ? .leading : .center)
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// «🔗 يُربط بـ محمد علي حسن صالح عبدالله»
    private func linkLine(_ e: JoinMatchTiers.Entry) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "link")
                .dsGlyph(DS.Glyph.xs, weight: .semibold)
                .foregroundColor(DS.Color.success.dsReadableGlyph)
                .accessibilityHidden(true)
            Text(L10n.t("يُربط بـ ", "Links to "))
                .font(DS.Font.role(.footnote))
                .foregroundColor(DS.Color.textSecondary)
            + Text(e.member.displayFullName)
                .font(DS.Font.role(.sectionTitle))
                .foregroundColor(DS.Color.textPrimary)
        }
        .lineLimit(2)
        .padding(.top, DS.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Color.cardBorder).frame(height: DS.Border.width)
        }
    }
}

/// شرائح أسماء المتقدّم المتطابقة «محمد ✓»
private struct FlowChips: View {
    let parts: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.xs) { chips }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) { chips }
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
            DSStatusChip(text: p, icon: "checkmark", tint: DS.Color.success, size: .mini)
        }
    }
}

/// نقطة لكل اسم من أسماء المتقدّم: ممتلئة تطابق · حمراء تختلف · مفرّغة ناقصة في السجلّ
private struct PartDots: View {
    let states: [JoinMatchTiers.PartState]

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, s in
                switch s {
                case .match:   Circle().fill(AppSection.admin.ink)
                case .differ:  Circle().fill(DS.Color.error)
                case .missing: Circle().strokeBorder(DS.Color.textTertiary, lineWidth: DS.Border.width)
                }
            }
            .frame(width: DS.Glyph.micro, height: DS.Glyph.micro)
        }
        .accessibilityHidden(true)
    }
}

/// درجات كل طلب محفوظة ما دام الأعضاء ومطابقات السيرفر والحسابات كما هي — الصفّ وزرّه وسحبه يقرؤونها معاً بلا إعادة حساب
final class JoinTierCache {
    private var store: [UUID: (key: String, tiers: JoinMatchTiers)] = [:]

    func tiers(for id: UUID, key: String, build: () -> JoinMatchTiers) -> JoinMatchTiers {
        if let hit = store[id], hit.key == key { return hit.tiers }
        let t = build()
        store[id] = (key, t)
        return t
    }

    /// «الأب المحتمل» لطلب بلا مطابقة (العيّنة ١٨) — بحث في كل الأعضاء، فيُحفظ بالمفتاح نفسه
    private var fathers: [UUID: (key: String, father: FamilyMember?)] = [:]

    func father(for id: UUID, key: String, build: () -> FamilyMember?) -> FamilyMember? {
        if let hit = fathers[id], hit.key == key { return hit.father }
        let f = build()
        fathers[id] = (key, f)
        return f
    }
}

// MARK: - صفّ مطابق داخل مربّع الطلب الجديد (U9، spec C.3 البند ٥)

/// «يطابق في الشجرة»: حلقة صغيرة بعمق التطابق · الاسم ١٥ متوسط · السبب والميلاد ١٣ رمادي · «ربط» (حبّة كحلية ٣٤ ولمسها ٤٤).
/// جسم الصفّ يعرض هذا المطابق في «مكانه في الشجرة»، و«ربط» = تأكيد الدمج نفسه
struct JoinBoxMatchRow: View {
    let name: String
    let reason: String
    var birth: String? = nil
    /// كم جزءاً تطابق بالترتيب، من كم
    let depth: Int
    let total: Int
    var isRegistration: Bool = false
    /// المطابق المعروض في «مكانه في الشجرة»
    var isPlaced: Bool = false
    let onShowPlace: () -> Void
    /// nil = لا «ربط» لهذا الدور (المعاينة وحدها)
    let onLink: (() -> Void)?

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Button(action: onShowPlace) {
                HStack(spacing: DS.Spacing.md) {
                    DSRingGauge(progress: min(1, Double(depth) / Double(max(total, 1))), tint: AppSection.admin.ink,
                                size: DS.Ring.small, center: .count(depth), ink: AppSection.admin.ink)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        HStack(spacing: DS.Spacing.xs) {
                            if isPlaced {
                                Image(systemName: "mappin.circle.fill")
                                    .dsGlyph(DS.Glyph.md)
                                    .foregroundColor(DS.Color.accent)
                                    .accessibilityHidden(true)
                            }
                            Text(name)
                                .dsFont(.rowTitle)
                                .foregroundColor(DS.Color.textPrimary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(line)
                            .dsFont(.subtitle)
                            .foregroundColor(DS.Color.textTertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(AdminRowPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isPlaced ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(L10n.t("يعرض مكانه في الشجرة", "Shows its place in the tree"))
            if let onLink {
                AdminPillButton(title: L10n.t("ربط", "Link"), style: .navy, action: onLink)
                    .accessibilityLabel(L10n.t("ربط بـ \(name)", "Link to \(name)"))
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: DS.Hub.rowMinHeightTwoLines, alignment: .leading)
    }

    /// «الاسم الأول + الأب + الجد · مواليد 1990 · تسجيل»
    private var line: String {
        var parts = [reason]
        if let birth, !birth.isEmpty { parts.append(birth) }
        if isRegistration { parts.append(L10n.t("تسجيل", "Registration")) }
        return parts.joined(separator: " · ")
    }
}
