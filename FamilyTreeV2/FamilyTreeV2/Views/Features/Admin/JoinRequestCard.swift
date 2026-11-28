import SwiftUI

// MARK: - بطاقة «طلب انضمام» في «الوارد» (العيّنة ١٨ بموافقة المالك ٢٠٢٦-١١-١٨)
//
// الترتيب القديم كما هو، ومعه: «اتصال» و«واتساب» زرّين متجاورين · مربّع «الأرجح» بنسبة وحلقة وسلسلة آبائه ولماذا هو
// الأرجح · بقية المطابقات شرائح بنسبها للتبديل · «كل المطابقات (N)» يفتح مربّعاً بالقائمة كلها · حالة «لا مطابقة»
// باقتراح الأب · وللأنثى خطوات شجرة النساء. الربط والرفض والتفاصيل كما كانت (أزرار البطاقة في `AdminAllRequestsView`).
// الدرجات من `JoinMatchTiers` (فوق `NameMatcher.linkSuggestions`) — لا منطق سيرفر جديد.

// MARK: النسبة — مكان واحد

enum JoinMatchScore {
    /// نسبة التطابق المعروضة — ما يقيسه المطابِق فعلاً لا أكثر:
    ///   ١) الأسماء المتطابقة بالترتيب من أسماء المتقدّم (بلا العائلة): `depth ÷ عدد أسمائه × 100`
    ///      (السجلّ الأقصر بلا اختلاف لا يُحسب له ما لم يُكتب فيه — المجهول ليس تطابقاً)
    ///   ٢) ناقص نقطتين عن كل سنة فرق في الميلاد بعد السنة الأولى، بحدّ أقصى ٣٠ (فرق مجهول = لا خصم)
    ///   ٣) تُقرّب لأقرب عدد صحيح بين ٠ و١٠٠
    /// مثال: الرباعي متطابق ونفس السنة = 100 · الثلاثة الأولى من أربعة وبفرق ٣ سنوات = 75 − 4 = 71.
    static let birthPenaltyPerYear = 2.0
    static let birthPenaltyMax = 30.0

    static func percent(_ e: JoinMatchTiers.Entry, applicantParts: Int) -> Int {
        guard applicantParts > 0 else { return 0 }
        let matched = Double(min(e.depth, applicantParts))
        let base = matched / Double(applicantParts) * 100
        let gap = Double(max(0, (e.gapYears ?? 0) - 1))
        let penalty = min(birthPenaltyMax, gap * birthPenaltyPerYear)
        return Int(max(0, min(100, (base - penalty).rounded())))
    }
}

/// خطوات طلب الأنثى (شجرة النساء): الأب من أسمائها ← بناته ← هي
struct JoinFemaleSteps {
    let father: FamilyMember
    /// أسماء بناته في شجرة النساء (فارغة = لم تُحمَّل أو لا بنات)
    let daughters: [String]
    /// موقعها بين البنات إن وُجدت باسمها
    let herIndex: Int?
    /// لعقدتها حساب مرتبط بغيرها
    let herTaken: Bool
    let name: String
}

/// ما تحتاجه البطاقة — يبنيه `AdminAllRequestsView` من `memberVM`، وتبنيه المعاينة من بيانات وهمية
struct JoinCardInfo {
    let member: FamilyMember
    let tiers: JoinMatchTiers
    let selectedId: UUID?
    let showsWeak: Bool
    let requestAge: String?
    /// سلسلة الآباء لكل مرشّح بالأسماء الأولى: جد الأب ← الجد ← الأب ← هو
    let chains: [UUID: [String]]
    /// «الأب المحتمل» حين لا مطابقة (أسماؤه = أب المتقدّم وجده بالترتيب)
    let probableFather: FamilyMember?
    let female: JoinFemaleSteps?

    var pick: JoinMatchTiers.Entry? { tiers.entry(selectedId) }
    func percent(_ e: JoinMatchTiers.Entry) -> Int { JoinMatchScore.percent(e, applicantParts: tiers.applicantParts.count) }
    var firstName: String {
        let f = member.firstName.trimmingCharacters(in: .whitespaces)
        return f.isEmpty ? (member.nameUnits.first ?? member.fullName) : f
    }

    /// زرّ البطاقة الرئيسي: «ربط بـ «يوسف»» · «ربط بـ «نورة» في شجرة النساء» · «اختر من الشجرة»
    var approveLabel: String {
        if member.isFemale {
            if let f = female, f.herIndex != nil, !f.herTaken {
                // «في شجرة النساء» في شارة الرأس وخطوات المربّع — الزرّ بعرض نصف البطاقة فلا يتّسع لها
                return L10n.t("ربط بـ «\(f.name)»", "Link to «\(f.name)»")
            }
            return L10n.t("ربط بشجرة النساء", "Link in the women's tree")
        }
        guard let p = pick else { return L10n.t("اختر من الشجرة", "Pick from the tree") }
        let n = p.member.nameUnits.first ?? p.member.firstName
        return L10n.t("ربط بـ «\(n)»", "Link to «\(n)»")
    }

    /// «مواليد 2009 · 17 سنة»
    static func birthText(_ m: FamilyMember) -> String? {
        guard let y = JoinMatchTiers.year(m.birthDate) else { return nil }
        if let d = DateHelper.parse(String((m.birthDate ?? "").prefix(10))),
           let age = Calendar(identifier: .gregorian).dateComponents([.year], from: d, to: Date()).year, age >= 0 {
            return L10n.t("مواليد \(y) · \(age) سنة", "Born \(y) · \(age) yrs")
        }
        return L10n.t("مواليد \(y)", "Born \(y)")
    }

    /// المنصّة التي سجّل منها
    var platform: (text: String, icon: String)? {
        switch member.registrationPlatform {
        case "web": return (L10n.t("من الموقع", "From website"), "globe")
        case "ios": return (L10n.t("آيفون", "iPhone"), "iphone")
        case "android": return (L10n.t("أندرويد", "Android"), "candybarphone")
        default: return nil
        }
    }

    /// القارئ الصوتي: الاسم · الأرجح · النسبة
    var spoken: String {
        var parts = [L10n.t("طلب انضمام", "Join request"), member.displayFullName]
        if member.isFemale {
            parts.append(L10n.t("أنثى، تُربط بشجرة النساء", "Female, linked in the women's tree"))
        } else if let p = pick {
            parts.append(L10n.t("الأرجح: \(p.member.chainThreeName)، \(percent(p)) بالمئة",
                                "Best match: \(p.member.chainThreeName), \(percent(p)) percent"))
        } else {
            parts.append(L10n.t("لا مطابقة في الشجرة", "No match in the tree"))
        }
        if let age = requestAge { parts.append(age) }
        return parts.joined(separator: "، ")
    }
}

// MARK: - البطاقة

struct JoinRequestCard: View {
    let info: JoinCardInfo
    let avatar: AnyView
    let onSelect: (UUID) -> Void
    let onToggleWeak: () -> Void
    let onOpenMatches: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// «من خارج العائلة» (R1)
    @ObservedObject private var outsideJoins = OutsideJoinStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            header
            contacts
            if info.member.isFemale {
                if let f = info.female { femaleSteps(f) }
            } else if let pick = info.pick {
                bestBox(pick)
            } else {
                noMatchNote
            }
        }
    }

    // MARK: الرأس

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            avatar
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(info.member.displayFullName)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                NotifFlow(spacing: DS.Spacing.xs) {
                    if outsideJoins.contains(info.member.id) {
                        OutsideJoinTag(member: info.member)
                    }
                    if info.member.isFemale {
                        DSStatusChip(text: L10n.t("أنثى · شجرة النساء", "Female · women's tree"),
                                     icon: "figure.stand.dress", tint: DS.Color.female, size: .mini)
                    } else {
                        AdminRequestKindChip(kind: .join)
                    }
                    if let b = JoinCardInfo.birthText(info.member) {
                        DSStatusChip(text: b, icon: "birthday.cake.fill", tint: DS.Color.slate, size: .mini)
                    }
                    if let p = info.platform {
                        DSStatusChip(text: p.text, icon: p.icon,
                                     tint: info.member.registrationPlatform == "web" ? DS.Color.info : DS.Color.slate,
                                     size: .mini)
                    }
                }
            }
            Spacer(minLength: DS.Spacing.xs)
            if let age = info.requestAge {
                Text(age)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(info.spoken)
    }

    // MARK: اتصال · واتساب

    @ViewBuilder
    private var contacts: some View {
        if let raw = info.member.phoneNumber, !raw.isEmpty {
            let shown = KuwaitPhone.display(raw)
            HStack(spacing: DS.Spacing.sm) {
                if let tel = KuwaitPhone.telURL(raw) {
                    contactPill(icon: "phone.fill", text: shown, tint: DS.Color.sea, digits: true,
                                spoken: L10n.t("اتصال بـ \(shown)", "Call \(shown)")) { UIApplication.shared.open(tel) }
                }
                if let wa = KuwaitPhone.whatsappURL(raw) {
                    contactPill(icon: "message.fill", text: L10n.t("واتساب", "WhatsApp"), tint: DS.Color.palm,
                                digits: false, spoken: L10n.t("واتساب", "WhatsApp")) { UIApplication.shared.open(wa) }
                }
            }
        }
    }

    private func contactPill(icon: String, text: String, tint: Color, digits: Bool, spoken: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Image(dsSymbol: icon)
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .accessibilityHidden(true)
                Text(verbatim: text)
                    .dsFont(.chip)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .environment(\.layoutDirection, digits ? .leftToRight : LanguageManager.shared.layoutDirection)
            }
            .foregroundColor(tint.dsReadableGlyph)
            .frame(maxWidth: .infinity, minHeight: DSBox.buttonHeightCompact)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(tint.opacity(DS.Opacity.tintFill)))
            .padding(.vertical, DSButtonSize.compact.hitInset)
            .contentShape(Rectangle())
            .padding(.vertical, -DSButtonSize.compact.hitInset)
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(spoken)
    }

    // MARK: ١) الأرجح — مربّع مختصر (ملاحظة المالك ٢٠٢٦-١١-١٨ «بسّطه»): حلقة صغيرة بالنسبة + الاسم، سطر السلسلة،
    // سطر الأسباب، و«كل المطابقات (N)» نصّاً في طرفه — بقية المرشّحين في المربّع

    private func bestBox(_ e: JoinMatchTiers.Entry) -> some View {
        let pct = info.percent(e)
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        let chain = info.chains[e.id] ?? []
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                DSRingValue(progress: Double(pct) / 100, tint: DS.Color.success,
                            text: L10n.t("\(pct)٪", "\(pct)%"))
                Text(e.member.chainThreeName)
                    .dsFont(.rowTitle)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            if chain.count > 1 {
                Text(verbatim: chain.dropLast().joined(separator: L10n.isArabic ? " ‹ " : " › "))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                reasonsText(e)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DS.Spacing.xs)
                if info.tiers.total > 1 { allMatchesButton }
            }
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(DS.Color.success.opacity(DS.Opacity.tintFillFaint)))
        .overlay(shape.strokeBorder(DS.Color.success.opacity(DS.Opacity.fieldStroke), lineWidth: DS.Border.width))
        .accessibilityElement(children: .contain)
    }

    /// «✓ الاسم الرباعي · ✓ نفس سنة الميلاد» — بلا «بلا رقم ولا حساب» (صحيح دائماً في هذه القائمة)
    private func reasonsText(_ e: JoinMatchTiers.Entry) -> Text {
        var out = Text(verbatim: "")
        let reasons = JoinMatchWhy.reasons(e, tiers: info.tiers, short: true)
        for (i, r) in reasons.enumerated() {
            if i > 0 { out = out + Text(verbatim: " · ").foregroundColor(DS.Color.textTertiary) }
            out = out + Text(Image(systemName: r.ok ? "checkmark" : "exclamationmark"))
                .font(DS.Font.icon(DS.Glyph.micro, weight: .bold))
                .foregroundColor((r.ok ? DS.Color.success : DS.Color.warning).dsReadableGlyph)
                + Text(verbatim: " " + r.text).foregroundColor(DS.Color.textSecondary)
        }
        return out.font(DS.Font.role(.caption))
    }

    /// «كل المطابقات (N)» — رابط نصّي يفتح مربّع المطابقات المحتملة (مساحة لمس ٤٤)
    private var allMatchesButton: some View {
        Button(action: onOpenMatches) {
            Text(L10n.t("كل المطابقات (\(info.tiers.total))", "All matches (\(info.tiers.total))"))
                .dsFont(.chip)
                .monospacedDigit()
                .foregroundColor(AppSection.admin.ink)
                .underline()
                .fixedSize()
                .frame(minHeight: DS.Icon.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: ٢) لا مطابقة

    private var noMatchNote: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Group {
                if let f = info.probableFather {
                    Text(L10n.t("لا مطابقة في الشجرة. ", "No match in the tree. "))
                        .font(DS.Font.role(.sectionTitle))
                    + Text(L10n.t("أقرب اسم: «\(f.chainThreeName)» (الأب المحتمل) — أضِفه ابناً له أو اختر مكانه من الشجرة.",
                                  "Closest name: «\(f.chainThreeName)» (likely father) — add him as a son or pick his place in the tree."))
                        .font(DS.Font.role(.footnote))
                } else {
                    Text(L10n.t("لا مطابقة في الشجرة. ", "No match in the tree. "))
                        .font(DS.Font.role(.sectionTitle))
                    + Text(L10n.t("اختر مكانه من الشجرة.", "Pick his place in the tree."))
                        .font(DS.Font.role(.footnote))
                }
            }
            .foregroundColor(DS.Color.warning.dsReadableGlyph)
            .fixedSize(horizontal: false, vertical: true)
            if !info.tiers.weak.isEmpty { allMatchesButton }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(DS.Color.warning.opacity(DS.Opacity.tintFillSoft)))
        .overlay(shape.strokeBorder(DS.Color.warning.opacity(DS.Opacity.tintStroke),
                                    style: StrokeStyle(lineWidth: DS.Border.width, dash: [DS.Spacing.xs, DS.Spacing.xs])))
    }

    // MARK: ٣) الأنثى

    private func femaleSteps(_ f: JoinFemaleSteps) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            stepRow(1) {
                HStack(spacing: DS.Spacing.xs) {
                    (Text(L10n.t("الأب: ", "Father: ")).font(DS.Font.role(.footnote)).foregroundColor(DS.Color.textSecondary)
                     + Text(f.father.chainThreeName).font(DS.Font.role(.sectionTitle)).foregroundColor(DS.Color.textPrimary))
                        .lineLimit(2)
                    Spacer(minLength: DS.Spacing.xs)
                    DSStatusChip(text: L10n.t("في الشجرة", "In the tree"), tint: DS.Color.palm, size: .mini)
                }
            }
            if !f.daughters.isEmpty {
                stepRow(2) {
                    daughtersText(f)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                stepRow(3) {
                    Text(f.herIndex == nil
                         ? L10n.t("لم تُوجد في بناته — تُضاف تحته", "Not among his daughters — she'll be added under him")
                         : f.herTaken
                            ? L10n.t("لـ«\(f.name)» حساب مرتبط — راجع التفاصيل", "«\(f.name)» already has an account — check the details")
                            : L10n.t("«\(f.name)» بلا حساب — تُربط بها", "«\(f.name)» has no account — linked to her"))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(DS.Color.female.opacity(DS.Opacity.tintFillSoft)))
        .overlay(shape.strokeBorder(DS.Color.female.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
        .accessibilityElement(children: .combine)
    }

    private func daughtersText(_ f: JoinFemaleSteps) -> Text {
        var out = Text(L10n.t("بناته: ", "His daughters: ")).font(DS.Font.role(.footnote)).foregroundColor(DS.Color.textSecondary)
        for (i, n) in f.daughters.enumerated() {
            if i > 0 { out = out + Text(verbatim: " · ").font(DS.Font.role(.footnote)).foregroundColor(DS.Color.textTertiary) }
            out = out + (i == f.herIndex
                ? Text(verbatim: n).font(DS.Font.role(.sectionTitle)).foregroundColor(DS.Color.female.dsReadableGlyph)
                : Text(verbatim: n).font(DS.Font.role(.footnote)).foregroundColor(DS.Color.textSecondary))
        }
        return out
    }

    private func stepRow<C: View>(_ n: Int, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            Text(verbatim: L10n.isArabic ? ["١", "٢", "٣"][n - 1] : "\(n)")
                .dsFont(.badge)
                .foregroundColor(DS.Color.textOnPrimary)
                .frame(width: DS.Glyph.xxl, height: DS.Glyph.xxl)
                .background(Circle().fill(DS.Color.female.dsSolidFill))
                .accessibilityHidden(true)
            content()
        }
    }
}

// MARK: - لماذا هو الأرجح (من بيانات المطابِق الحقيقية)

enum JoinMatchWhy {
    struct Reason { let text: String; let ok: Bool }

    /// `short`: نصوص البطاقة المختصرة («الاسم الرباعي») وبلا «بلا رقم ولا حساب»
    static func reasons(_ e: JoinMatchTiers.Entry, tiers: JoinMatchTiers, short: Bool = false) -> [Reason] {
        var out: [Reason] = []
        let n = tiers.applicantParts.count
        if e.depth >= n {
            let word: String
            switch n {
            case 2: word = L10n.t("الاسم الثنائي", "Two-part name")
            case 3: word = L10n.t("الاسم الثلاثي", "Three-part name")
            case 4: word = L10n.t("الاسم الرباعي", "Four-part name")
            default: word = L10n.t("الأسماء الـ\(n)", "All \(n) names")
            }
            out.append(Reason(text: short ? word : word + L10n.t(" متطابق", " match"), ok: true))
        } else if e.endsClean {
            out.append(Reason(text: L10n.t("السجلّ ينتهي عند \(JoinMatchTiers.position(e.depth - 1))",
                                           "Record ends at \(JoinMatchTiers.position(e.depth - 1))"), ok: true))
        } else {
            out.append(Reason(text: L10n.t("يختلف عند \(JoinMatchTiers.position(e.depth))",
                                           "Differs at \(JoinMatchTiers.position(e.depth))"), ok: false))
        }
        if let gap = e.gapYears {
            out.append(gap == 0
                ? Reason(text: L10n.t("نفس سنة الميلاد", "Same birth year"), ok: true)
                : Reason(text: L10n.t("بفرق \(gap) سنة", "\(gap) years apart"), ok: gap < 5))
        } else {
            out.append(Reason(text: L10n.t("بلا تاريخ ميلاد للمقارنة", "No birth date to compare"), ok: false))
        }
        // مرشّحو `joinTiers` بلا رقم ولا حساب دخول أصلاً (شرط القائمة)
        if !short { out.append(Reason(text: L10n.t("بلا رقم ولا حساب", "No number, no account"), ok: true)) }
        return out
    }
}

// MARK: - مربّع «المطابقات المحتملة»

struct JoinMatchesBox: View {
    let info: JoinCardInfo
    let onPick: (UUID) -> Void
    let onPickFromTree: () -> Void
    let onClose: () -> Void

    var body: some View {
        DSComposer(
            title: L10n.t("المطابقات المحتملة · \(info.firstName)", "Possible matches · \(info.firstName)"),
            subtitle: L10n.t("\(info.tiers.total) مرشّحاً — اضغط أحدهم لاختياره", "\(info.tiers.total) candidates — tap one to pick it"),
            icon: "point.3.connected.trianglepath.dotted",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("اختر من الشجرة", "Pick from the tree"),
            actionIcon: "tree.fill",
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: true,
            onSubmit: onPickFromTree,
            onCancel: onClose
        ) {
            group(L10n.t("مطابق", "Exact"), icon: "checkmark.seal.fill", tint: DS.Color.success, info.tiers.exact, index: 1)
            group(L10n.t("قريب", "Close"), icon: "circle.lefthalf.filled", tint: DS.Color.info, info.tiers.near,
                  index: info.tiers.exact.isEmpty ? 1 : 2)
            group(L10n.t("ضعيف", "Weak"), icon: "circle.dashed", tint: DS.Color.slate, info.tiers.weak,
                  index: (info.tiers.exact.isEmpty ? 0 : 1) + (info.tiers.near.isEmpty ? 0 : 1) + 1)
        }
    }

    @ViewBuilder
    private func group(_ title: String, icon: String, tint: Color, _ entries: [JoinMatchTiers.Entry], index: Int) -> some View {
        if !entries.isEmpty {
            DSComposerSection(title: title, icon: icon, tint: tint, trailing: "\(entries.count)", index: index) {
                VStack(spacing: DS.Spacing.sm) {
                    // الأعلى نسبة أولاً داخل كل مجموعة (٢٠٢٦-١١-١٨)
                    ForEach(entries.sorted { info.percent($0) > info.percent($1) }) { e in row(e) }
                }
            }
        }
    }

    private func row(_ e: JoinMatchTiers.Entry) -> some View {
        let on = info.selectedId == e.id
        let pct = info.percent(e)
        let tint = pct >= 85 ? DS.Color.success : pct >= 60 ? DS.Color.info : DS.Color.slate
        return Button { onPick(e.id) } label: {
            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                DSRingGauge(progress: Double(pct) / 100, tint: tint, size: DS.Ring.small, center: .percent(pct))
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(e.member.chainThreeName)
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let chain = info.chains[e.id], chain.count > 1 {
                        Text(verbatim: chain.joined(separator: L10n.isArabic ? " ‹ " : " › "))
                            .dsFont(.caption)
                            .foregroundColor(DS.Color.textSecondary)
                            .lineLimit(1)
                    }
                    Text(verbatim: info.tiers.birthLine(e) + L10n.t(" · بلا حساب", " · no account"))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DS.Spacing.xs)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .dsGlyph(DS.Glyph.xl, weight: .regular)
                    .foregroundColor(on ? DS.Color.success.dsReadableGlyph : DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(DS.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(on ? DS.Color.success.opacity(DS.Opacity.tintFillSoft) : DS.Color.surface))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(on ? DS.Color.success.opacity(DS.Opacity.tintStroke) : DS.Color.cardBorder,
                              lineWidth: DS.Border.width))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.t("\(e.member.chainThreeName)، \(pct) بالمئة، \(info.tiers.birthLine(e))",
                                   "\(e.member.chainThreeName), \(pct) percent, \(info.tiers.birthLine(e))"))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
