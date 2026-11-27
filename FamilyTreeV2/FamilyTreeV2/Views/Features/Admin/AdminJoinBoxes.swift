import SwiftUI
import Supabase

// MARK: - مربّعات «طلب انضمام» و«استكمال التسجيل» في «الوارد» (المالك ٢٠٢٦-١١-٢٧، الوحدة R2 — admin-boxes.png)
//
// مربّع صغير في المنتصف (`dsCenterBox`) يتبدّل محتواه خطوة خطوة — نفس شكل مربّعات التسجيل (`SignupStepDots`):
//  البيانات ← «الربط» (اقتراحات بشرائح القيم) ← «تأكيد الربط»، و«عضو جديد» / «بنت جديدة» ← اختيار الوالد ← التأكيد.
// «من خارج العائلة» ← «اعتماد» وحده. «استكمال التسجيل» ← البيانات والاقتراحات ← «ربط بالوالدة» ← التأكيد.
// النداءات هي الموجودة نفسها بصلاحياتها: `mergeMemberIntoTreeMember` (merge_member_into_tree) · `approveMember` (الأب) ·
// `linkWomanAccount` (link_woman_account — «بنت جديدة» عقدتها بمعرّف ملفها منذ 20261127170000) · `DaughterSons.approveJoin`
// (approve_join_as_daughter_son) · `decideLineage(…, motherId:)` (decide_lineage_request). الخطوات والشرائح: `AdminJoinBoxRules`.

/// ما يفتحه المربّع
enum AdminJoinBoxSubject: Identifiable {
    case join(FamilyMember, outside: Bool)
    case completion(AdminRequest)

    var id: String {
        switch self {
        case .join(let m, _): return "join-\(m.id)"
        case .completion(let r): return "completion-\(r.id)"
        }
    }
}

struct AdminJoinBox: View {
    typealias Rules = AdminJoinBoxRules
    typealias T = AdminJoinBoxRules.Ar

    let subject: AdminJoinBoxSubject
    /// الرجل: الأقرب لاسمه من شجرة العائلة (مطابقة الاسم الموجودة في «الوارد»)
    var suggestedMen: [FamilyMember] = []
    /// الأرجح من مطابقة الاسم — مختار مسبقاً (المراجع يؤكّد أو يبدّل)
    var preselected: UUID? = nil
    var requestAge: String? = nil
    /// يقرّر فيه (ربط/اعتماد) — `canApprove(.joinRequests)` في «الوارد»
    var canDecide: Bool = true
    /// «رفض مع سبب» — nil = لا يملك الرفض
    var onReject: ((String?) -> Void)? = nil
    /// «كل التفاصيل» (مربّع الطلب الطويل: الاتصال، التحويل للمدير، السجل)
    var onDetails: (() -> Void)? = nil
    var onDone: () -> Void
    let onClose: () -> Void
    /// الخطوة الأولى (معاينة التصوير) — البيانات افتراضياً
    var initialStep: Rules.Step = .applicant

    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var adminRequestVM: AdminRequestViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: Rules.Step = .applicant
    /// الخطوة التي فُتح منها التأكيد (للرجوع)
    @State private var confirmFrom: Rules.Step = .link
    @State private var picked: UUID? = nil
    @State private var fatherPick: FamilyMember? = nil
    @State private var fatherSearch = ""
    @State private var busy = false
    @State private var errorText: String? = nil
    @State private var askReason = false
    @State private var reason = ""
    /// «طلب استكمال البيانات»: الحقول المحدّدة والملاحظة
    @State private var missing: Set<Rules.MissingField> = []
    @State private var askNote = ""

    // التحميل
    @State private var loaded = false
    @State private var women: [FamilyMember] = []
    @State private var womanRequest: AdminRequestViewModel.WomanJoinRequestInfo? = nil
    @State private var mothers: [LineageMotherSuggestion] = []

    // MARK: المشتقات

    private var member: FamilyMember? {
        switch subject {
        case .join(let m, _): return m
        case .completion(let r): return r.member ?? memberVM.member(byId: r.memberId)
        }
    }

    private var kind: Rules.Kind {
        switch subject {
        case .join(_, let outside): return Rules.kind(isOutside: outside, isCompletion: false)
        case .completion: return .completion
        }
    }

    private var female: Bool { member?.isFemale == true }
    private var source: Rules.Source { Rules.source(kind, female: female) }

    private var lineage: OutsideLineageDetails? {
        if case .completion(let r) = subject { return OutsideLineageDetails.parse(r.details) }
        return nil
    }

    private var applicantName: String {
        member?.fullName ?? L10n.t("العضو", "the member")
    }

    private var applicantFirst: String {
        let f = (member?.firstName ?? "").trimmingCharacters(in: .whitespaces)
        return f.isEmpty ? (applicantName.split(separator: " ").first.map(String.init) ?? applicantName) : f
    }

    // MARK: الجسم

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                if let dot = Rules.dotIndex(kind, step: step) {
                    SignupStepDots(count: Rules.steps(kind).count, current: dot)
                }
                content
                if let errorText {
                    DSNoteCard(errorText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                }
                buttons
            }
            .padding(DS.Spacing.lg)
            .id(step == .confirm ? "confirm" : "\(step)")
            .transition(.opacity)
            .dsPanelContentHeight(extra: 0)
        }
        .background(DS.Color.surface)
        .animation(reduceMotion ? nil : DSMotion.fade, value: step)
        .interactiveDismissDisabled(busy)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await load() }
        .dsAlert(L10n.t("سبب الرفض", "Rejection Reason"), isPresented: $askReason) {
            TextField(L10n.t("اكتب السبب (اختياري)", "Reason (optional)"), text: $reason)
                .dsAlertField()
            Button(L10n.t("إرسال الرفض", "Send Rejection"), role: .destructive) {
                let r = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                onReject?(r.isEmpty ? nil : r)
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("سيصل السبب كرسالة إلى مقدّم الطلب.", "The reason will be sent as a message to the requester."))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .applicant:
            title(kind == .completion ? L10n.t(T.completionTitle, "Complete registration") : L10n.t(T.joinTitle, "Join request"))
            applicantBlock
            if kind == .completion { suggestionsBlock }
            if kind == .outsideJoin {
                Text(L10n.t(T.outsideNote, "After approval the app asks: «Is the mother from the family?»."))
                    .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .link:
            title(L10n.t(T.linkTitle, "Link"))
            if female { applicantHeader(compact: true) }
            suggestionsBlock
        case .newMember:
            title(Rules.title(.newMember, female: female))
            newMemberBlock
        case .confirm:
            title(L10n.t(T.confirmTitle, "Confirm link"))
            confirmBlock
        case .askMissing:
            title(L10n.t(T.askMissing, "Request missing details"))
            applicantHeader(compact: true)
            askBlock
        }
    }

    // MARK: «طلب استكمال البيانات»

    @ViewBuilder
    private var askBlock: some View {
        Text(L10n.t(T.askPrompt, "Tick the missing details:"))
            .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
        VStack(spacing: 0) {
            ForEach(Array(Rules.askFields(kind).enumerated()), id: \.element) { i, f in
                if i > 0 { Divider() }
                askRow(f)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(DS.Color.cardBorder, lineWidth: DS.Border.width))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        DSComposerField(icon: "text.bubble", label: L10n.t(T.askNote, "Note to the member (optional)"),
                        placeholder: L10n.t("مثال: يُرجى كتابة الاسم الرباعي كاملاً", "e.g. Please write the full four-part name"),
                        text: $askNote, limit: Rules.askNoteLimit)
        if missing.isEmpty {
            Text(L10n.t(T.mustTickOne, "Tick at least one item."))
                .dsFont(.footnote).foregroundColor(DS.Color.textTertiary)
        } else {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(L10n.t(T.askPreview, "Notification text:")).dsFont(.footnote).foregroundColor(DS.Color.textTertiary)
                Text(verbatim: Rules.askMessage(missing, note: askNote))
                    .dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.t(T.askConfirmLine, "The member gets this notification, and the request stays pending until they send the details."))
                    .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.cardBackgroundSoft))
        }
    }

    /// صفّ تحديد: مربّع ✓ + الاسم الرسمي — المحدّد بعلامة وإطار، لا باللون وحده
    private func askRow(_ f: Rules.MissingField) -> some View {
        let on = missing.contains(f)
        return Button {
            if on { missing.remove(f) } else { missing.insert(f) }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .dsGlyph(DS.Glyph.xl)
                    .foregroundColor(on ? DS.Color.primary : DS.Color.textTertiary)
                    .accessibilityHidden(true)
                Text(Rules.fieldLabel(f)).dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.md)
            .frame(minHeight: DS.Icon.tapTarget)
            .background(on ? DS.Color.cardBackgroundSoft : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Rules.fieldLabel(f))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .dsFont(.headline)
            .foregroundColor(DS.Color.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: ١) بيانات صاحب الطلب

    private var originTag: (text: String, fill: Color) {
        switch kind {
        case .familyJoin: return (L10n.t(T.fromFamily, "From the family"), DS.Color.primaryFill)
        case .outsideJoin: return (L10n.t(T.fromOutside, "From outside the family"), DS.Color.palmFill)
        case .completion: return (L10n.t(T.completionTag, "Complete registration"), DS.Color.goldFill)
        }
    }

    private func applicantHeader(compact: Bool) -> some View {
        let tag = originTag
        let sub = applicantSubline
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(tag.text)
                .dsFont(.badge)
                .foregroundColor(DS.Color.textOnPrimary)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xxs)
                .background(Capsule().fill(tag.fill))
            HStack(spacing: DS.Spacing.md) {
                DSMemberAvatar(name: applicantName, avatarUrl: member?.avatarUrl,
                               size: compact ? DS.Icon.rowLarge : DS.Icon.avatar,
                               roleColor: female ? DS.Color.female : DS.Color.brand)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(verbatim: applicantName)
                        .dsFont(.rowTitle).fontWeight(.semibold)
                        .foregroundColor(DS.Color.textPrimary)
                        .dsNameLines()
                    if !sub.isEmpty {
                        Text(verbatim: sub)
                            .dsFont(.caption).foregroundColor(DS.Color.textTertiary)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// «ذكر · مواليد 1999 · 26 سنة · قبل ساعتين» — «استكمال التسجيل»: «الأم من العائلة»
    private var applicantSubline: String {
        if kind == .completion { return L10n.t("الأم من العائلة", "Mother from the family") }
        guard let m = member else { return "" }
        var parts = [m.isFemale ? L10n.t(T.female, "Female") : L10n.t(T.male, "Male")]
        if let b = JoinCardInfo.birthText(m) { parts.append(b) }
        if let requestAge { parts.append(requestAge) }
        return parts.joined(separator: " · ")
    }

    private var applicantBlock: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            applicantHeader(compact: false)
            VStack(spacing: 0) {
                ForEach(Array(dataRows.enumerated()), id: \.offset) { i, row in
                    if i > 0 { Divider() }
                    dataRow(row.label, row.value)
                }
            }
        }
    }

    private var dataRows: [(label: String, value: String)] {
        if kind == .completion {
            let d = lineage
            return [(L10n.t(T.motherTyped, "Mother's name as typed"),
                     SignupOriginRules.tidy((d?.motherTypedName ?? "") + " " + (d?.motherFamily ?? ""))),
                    (L10n.t(T.father, "Father"), d?.fatherName ?? "")]
        }
        guard let m = member else { return [] }
        var rows: [(String, String)] = [(kind == .outsideJoin ? L10n.t(T.threeName, "Three-part name")
                                                             : L10n.t(T.fullName, "Four-part name"), m.fullName)]
        if kind == .outsideJoin {
            rows.append((L10n.t(T.family, "Family"), (m.familyName ?? "").trimmingCharacters(in: .whitespaces)))
        }
        if let d = DateHelper.parse(String((m.birthDate ?? "").prefix(10))) {
            rows.append((L10n.t(T.birth, "Birth date"), d.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())))
        }
        return rows
    }

    private func dataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.md) {
            Text(label).dsFont(.footnote).foregroundColor(DS.Color.textTertiary)
            Spacer(minLength: DS.Spacing.sm)
            Text(verbatim: value.isEmpty ? "—" : value)
                .dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: DS.Icon.tapTarget)
        .accessibilityElement(children: .combine)
    }

    // MARK: ٢) الاقتراحات

    /// الاقتراح: الاسم الكامل (كلماته المطابقة للطلب خضراء) + شريحة الميلاد (والزوج للمرأة حين يفرّق)
    private struct Suggestion: Identifiable {
        let id: UUID
        let fullName: String
        let words: [Rules.NameWord]
        let chips: [Rules.Chip]

        init(_ c: Rules.Candidate, among: [Rules.Candidate], expect: Rules.Expect, women: Bool) {
            id = c.id
            fullName = Rules.spokenName(c)
            words = Rules.nameWords(c, expect: expect)
            chips = Rules.chips(c, among: among, expect: expect, women: women)
        }

        /// القارئ الصوتي: الاسم الكامل ثم الشرائح
        var spoken: String { ([fullName] + chips.map(Rules.spoken)).joined(separator: "، ") }
    }

    private var suggestionsTitle: String {
        switch source {
        case .familyTree: return L10n.t(T.familySuggestions, "Suggestions from the family tree")
        case .womenDaughters, .motherSuggestions: return L10n.t(T.womenSuggestions, "Suggestions from the women's tree")
        case .none: return ""
        }
    }

    private var expect: Rules.Expect {
        if kind == .completion {
            let d = lineage
            return Rules.Expect(typedName: d?.motherTypedName ?? "", birthYear: nil, expectedHusband: d?.fatherName)
        }
        return Rules.Expect(typedName: applicantName, birthYear: Rules.birthYear(member?.birthDate), expectedHusband: nil)
    }

    private var candidates: [Rules.Candidate] {
        switch source {
        case .familyTree:
            return suggestedMen.map { Rules.candidate(id: $0.id, fullName: $0.fullName, birthDate: $0.birthDate, husband: nil) }
        case .womenDaughters:
            return womenSuggestions.map { w in
                let husband = w.husbandId.flatMap { id in memberVM.member(byId: id)?.chainThreeName
                    ?? women.first { $0.id == id }?.fullName }
                return Rules.candidate(id: w.id, fullName: w.fullName, birthDate: w.birthDate,
                                       husband: husband.map { MotherPickRules.shortName($0) })
            }
        case .motherSuggestions:
            return mothers.map { s in
                Rules.candidate(id: s.id, fullName: s.fullName, birthDate: nil,
                                husband: s.husbandName.map { MotherPickRules.shortName($0) })
            }
        case .none:
            return []
        }
    }

    private var suggestions: [Suggestion] {
        let all = candidates
        return all.map { Suggestion($0, among: all, expect: expect, women: source != .familyTree) }
    }

    /// بنات الأب (من طلبها إن اختارته) ثم الأقرب لاسمها في شجرة النساء — بلا المربوطة بحساب آخر
    private var womenSuggestions: [FamilyMember] {
        guard let m = member else { return [] }
        let families = NameMatcher.familyKeys()
        let applicant = NameMatcher.chain(m.fullName, families: families)
        let free = women.filter { w in
            w.isFemale && (WomenStore.linkedUserByWoman[w.id].map { $0 == m.id } ?? true)
        }
        var out: [FamilyMember] = []
        if let fid = womanRequest?.fatherId {
            let firstKey = Rules.words(m.firstName.isEmpty ? m.fullName : m.firstName).first
            out = free.filter { $0.fatherId == fid && Rules.words($0.firstName.isEmpty ? $0.fullName : $0.firstName).first == firstKey }
        }
        let skip = Set(out.map(\.id))
        let scored: [(FamilyMember, NameMatcher.Result)] = free.compactMap { w in
            guard !skip.contains(w.id), !applicant.isEmpty else { return nil }
            let r = NameMatcher.compare(applicant, NameMatcher.chain(w.fullName, families: families))
            return r.isStrong ? (w, r) : nil
        }
        out += scored.sorted { NameMatcher.ranksBefore($0.1, $1.1) }.prefix(8).map(\.0)
        return out
    }

    @ViewBuilder
    private var suggestionsBlock: some View {
        Text(suggestionsTitle).dsFont(.footnote).foregroundColor(DS.Color.textTertiary)
        let list = suggestions
        if !loaded && source != .familyTree {
            DSPageLoader(L10n.t("جارٍ البحث", "Searching"), fillsSpace: false)
        } else if list.isEmpty {
            Text(L10n.t(T.noSuggestions, "No suggestions for this name."))
                .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                    // المقترحات تصعد تباعاً مرة عند ظهور الخطوة — «تقليل الحركة»: تلاشٍ
                    VStack(spacing: 0) {
                        if i > 0 { Divider() }
                        suggestionRow(s, selected: picked == s.id) { picked = picked == s.id ? nil : s.id }
                    }
                    .dsStaggerIn(i)
                }
            }
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.surface))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.cardBorder, lineWidth: DS.Border.width))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            if let warn = motherWarning {
                DSNoteCard(warn, icon: "exclamationmark.triangle.fill", tint: DS.Color.warning)
            }
        }
    }

    /// «استكمال التسجيل»: الوالدة المختارة لها زوج غير الوالد (نفس تنبيه البطاقة السابقة)
    private var motherWarning: String? {
        guard kind == .completion, let s = mothers.first(where: { $0.id == picked }), s.husbandId != nil, !s.husbandMatches
        else { return nil }
        return s.husbandInFamily
            ? L10n.t("زوجها من العائلة — يُربط صاحب الطلب تحت والده في الشجرة، لا هنا.",
                     "Her husband is from the family — link the requester under his father in the tree instead.")
            : L10n.t("لها زوج مسجّل باسم آخر «\(s.husbandName ?? "")» — صحّح الشجرة أولاً أو ارفض الطلب.",
                     "She has a different recorded husband «\(s.husbandName ?? "")» — fix the tree first or reject.")
    }

    private func suggestionRow(_ s: Suggestion, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.md) {
                DSMemberAvatar(name: s.fullName, avatarUrl: nil, size: DS.Icon.row,
                               roleColor: source == .familyTree ? DS.Color.brand : DS.Color.female)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    AdminFullNameText(words: s.words)
                    if !s.chips.isEmpty { AdminValueChips(chips: s.chips) }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .dsGlyph(DS.Glyph.xl)
                    .foregroundColor(selected ? DS.Color.primary : DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .frame(minHeight: DS.Icon.tapTarget)
            .background(selected ? DS.Color.cardBackgroundSoft : Color.clear)
            // المختار: علامة ✓ وإطار — لا باللون وحده
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(selected ? DS.Color.primary : Color.clear, lineWidth: DS.Border.widthBold))
            // الاختيار: ✓ والإطار يتبدّلان بتباطؤ سريع لا قفزة
            .animation(reduceMotion ? DSMotion.fade : DSMotion.tap, value: selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.spoken)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: ٣) عضو جديد / بنت جديدة — اختيار الوالد

    private var fatherCandidates: [FamilyMember] {
        guard let m = member else { return [] }
        let men = memberVM.allMembers.filter { !$0.isFemale && $0.role != .pending && $0.hasName && $0.id != m.id }
        let q = fatherSearch.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { return Array(NameSearch.filter(men, query: q) { $0.fullName }.prefix(20)) }
        let families = NameMatcher.familyKeys()
        let chain = Array(NameMatcher.chain(m.fullName, families: families).dropFirst())
        guard !chain.isEmpty else { return [] }
        return men.compactMap { x -> (FamilyMember, NameMatcher.Result)? in
            let r = NameMatcher.compare(chain, NameMatcher.chain(x.fullName, families: families))
            return r.isStrong ? (x, r) : nil
        }
        .sorted { NameMatcher.ranksBefore($0.1, $1.1) }
        .prefix(6).map(\.0)
    }

    @ViewBuilder
    private var newMemberBlock: some View {
        Text(L10n.t(T.pickFather, "Pick the father from the family tree"))
            .dsFont(.footnote).foregroundColor(DS.Color.textTertiary)
        DSSearchField(text: $fatherSearch, placeholder: L10n.t("اسم الوالد", "Father's name"))
        let list = fatherCandidates
        // الوالد يقابل الاسم المكتوب بعد الاسم الأول: والده = جد صاحب الطلب
        let fatherExpect = Rules.Expect(typedName: applicantName.split(separator: " ").dropFirst().joined(separator: " "),
                                        birthYear: nil, expectedHusband: nil)
        let built = list.map { Rules.candidate(id: $0.id, fullName: $0.fullName, birthDate: $0.birthDate, husband: nil) }
        if built.isEmpty {
            Text(L10n.t(T.noSuggestions, "No suggestions for this name."))
                .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(built.enumerated()), id: \.element.id) { i, c in
                    // المقترحات تصعد تباعاً مرة (نتيجة البحث الجديدة فقط تدخل) — «تقليل الحركة»: تلاشٍ
                    VStack(spacing: 0) {
                        if i > 0 { Divider() }
                        suggestionRow(Suggestion(c, among: built, expect: fatherExpect, women: false),
                                      selected: fatherPick?.id == c.id) {
                            fatherPick = fatherPick?.id == c.id ? nil : list.first { $0.id == c.id }
                        }
                    }
                    .dsStaggerIn(i)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.cardBorder, lineWidth: DS.Border.width))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        if let f = fatherPick {
            Text(female
                 ? L10n.t("تُضاف «\(applicantFirst)» بنتاً لـ«\(f.firstName)» في شجرة النساء، ويُربط حسابها بها.",
                          "«\(applicantFirst)» is added as \(f.firstName)'s daughter in the women's tree and her account is linked to her.")
                 : L10n.t("يُقيَّد «\(applicantFirst)» ابناً لـ«\(f.firstName)» في الشجرة ويُفعَّل حسابه.",
                          "«\(applicantFirst)» is recorded as \(f.firstName)'s son and his account is activated."))
                .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: ٤) التأكيد

    private var targetLine: String {
        if confirmFrom == .newMember, let f = fatherPick {
            return female ? L10n.t("بنت جديدة لـ«\(f.chainThreeName)»", "New daughter of «\(f.chainThreeName)»")
                          : L10n.t("ابن «\(f.chainThreeName)»", "Son of «\(f.chainThreeName)»")
        }
        switch source {
        case .familyTree:
            return suggestedMen.first { $0.id == picked }?.fullName ?? ""
        case .womenDaughters:
            return women.first { $0.id == picked }?.fullName ?? ""
        case .motherSuggestions:
            return mothers.first { $0.id == picked }.map { L10n.t("الوالدة: ", "Mother: ") + $0.fullName } ?? ""
        case .none:
            return ""
        }
    }

    private var confirmBlock: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            if !targetLine.isEmpty {
                Text(verbatim: "«\(applicantName)» ← \(targetLine)")
                    .dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L10n.t(T.confirmLine, "The account will be linked to the tree record — this can't be undone from the app."))
                .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.cardBackgroundSoft))
    }

    // MARK: الأزرار

    private func enabled(_ action: Rules.Action) -> Bool {
        guard canDecide, !busy else { return false }
        switch action {
        case .link, .linkMother: return picked != nil && motherWarning == nil
        case .addAndLink: return fatherPick != nil && (!female || womanRequest != nil)
        case .confirm: return true
        case .toLink, .newMember: return true
        case .approveOutside: return true
        case .askMissing: return true
        case .sendAsk: return Rules.canSendAsk(missing, note: askNote)
        }
    }

    /// لماذا الزرّ الرئيسي معطّل — سطر رسمي تحته بدل زرّ صامت
    private func disabledReason(_ action: Rules.Action) -> String? {
        guard canDecide, !busy, !enabled(action) else { return nil }
        switch action {
        case .link, .linkMother:
            return motherWarning == nil ? L10n.t(T.pickSuggestion, "Pick one of the suggestions.") : nil
        case .addAndLink:
            return fatherPick == nil ? L10n.t(T.pickFatherFirst, "Pick the father.") : nil
        default:
            return nil
        }
    }

    @ViewBuilder
    private var buttons: some View {
        let primary = Rules.primary(kind, step: step)
        VStack(spacing: DS.Spacing.sm) {
            if let why = disabledReason(primary) {
                Text(why).dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if step == .confirm || step == .newMember || step == .askMissing {
                HStack(spacing: DS.Spacing.sm) {
                    DSButton(L10n.t(step == .confirm ? T.cancel : T.back, step == .confirm ? "Cancel" : "Back"),
                             role: .cancel) {
                        errorText = nil
                        step = step == .confirm ? confirmFrom : (step == .askMissing ? .applicant : .link)
                    }
                    .disabled(busy)
                    DSButton(Rules.title(primary, female: female), isLoading: busy) { run(primary) }
                        .disabled(!enabled(primary))
                }
            } else if canDecide {
                DSButton(Rules.title(primary, female: female), isLoading: busy) { run(primary) }
                    .disabled(!enabled(primary))
                if let second = Rules.secondary(kind, step: step) {
                    DSButton(Rules.title(second, female: female), role: .cancel) { run(second) }
                        .disabled(busy)
                }
            }
            if step != .confirm && step != .newMember && step != .askMissing {
                footerLinks
            }
        }
    }

    private var footerLinks: some View {
        HStack(spacing: DS.Spacing.lg) {
            if let onDetails, step == .applicant {
                textLink(L10n.t(T.details, "All details"), tint: AppSection.admin.ink, action: onDetails)
            }
            if onReject != nil {
                textLink(L10n.t(T.rejectWithReason, "Reject with reason"), tint: DS.Color.error) {
                    reason = ""
                    askReason = true
                }
            }
            if step == .link || (step == .applicant && !canDecide) {
                textLink(L10n.t("إغلاق", "Close"), tint: DS.Color.textSecondary, action: onClose)
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(busy)
    }

    private func textLink(_ text: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).dsFont(.chip).foregroundColor(tint)
                .frame(minHeight: DS.Icon.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: التنفيذ

    private func run(_ action: Rules.Action) {
        errorText = nil
        if let next = Rules.next(after: action) {
            if next == .confirm { confirmFrom = step }
            if next == .link || next == .newMember { picked = next == .link ? picked : picked }
            step = next
            return
        }
        switch action {
        case .approveOutside: execute(.approveOutside)
        case .sendAsk: execute(.sendAsk)
        case .confirm: execute(confirmFrom == .newMember ? .addAndLink : (kind == .completion ? .linkMother : .link))
        default: break
        }
    }

    private func execute(_ what: Rules.Action) {
        guard canDecide, !busy, let m = member else { return }
        if DebugAdminProbe.dryRun("join box \(what) \(subject.id)") {
            errorText = L10n.t("تجربة: لم يُرسل شيء للسيرفر.", "Dry run: nothing was sent.")
            return
        }
        busy = true
        Task {
            let failure = await call(what, member: m)
            busy = false
            if let failure {
                errorText = failure
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                DSMomentToast.show(what == .approveOutside ? L10n.t("تم الاعتماد", "Approved")
                                   : what == .sendAsk ? L10n.t(T.askSent, "Request for missing details sent")
                                   : L10n.t("تم الربط", "Linked"))
                onDone()
            }
        }
    }

    /// نداءات السيرفر الموجودة — nil = نجح
    private func call(_ what: Rules.Action, member m: FamilyMember) async -> String? {
        switch what {
        case .sendAsk:
            let requestId: UUID?
            if case .completion(let r) = subject {
                requestId = r.id
            } else {
                requestId = await adminRequestVM.fetchWomanJoinRequest(for: m.id)?.requestId
            }
            guard let requestId else {
                return L10n.t("لا يوجد طلب معلّق لهذا الحساب — ربما عولج من قبل.",
                              "No pending request for this account — it may have been handled already.")
            }
            do {
                try await CompletionAsk.ask(requestId: requestId, fields: missing, note: askNote)
                return nil
            } catch {
                return CompletionAsk.message(error)
            }
        case .approveOutside:
            do {
                try await DaughterSons.approveJoin(memberId: m.id)
                await DaughterSonsIndex.shared.refresh(force: true)
                await OutsideJoinStore.shared.refresh(force: true)
                await memberVM.fetchAllMembers(force: true)
                return nil
            } catch {
                return DaughterSons.message(error)
            }
        case .linkMother:
            guard case .completion(let r) = subject else { return nil }
            let ok = await adminRequestVM.decideLineage(r, approve: true, reason: nil, motherId: picked)
            return ok ? nil : takeError()
        case .link where female, .addAndLink where female:
            guard let info = womanRequest else {
                return L10n.t("لا يوجد طلب انضمام معلّق لهذا الحساب — ربما عولج من قبل.",
                              "No pending join request for this account — it may have been handled already.")
            }
            let newDaughter = what == .addAndLink
            return await adminRequestVM.linkWomanAccount(requestId: info.requestId, memberId: m.id,
                                                         womanId: newDaughter ? nil : picked,
                                                         fatherId: newDaughter ? fatherPick?.id : nil,
                                                         name: newDaughter ? applicantFirst : nil)
        case .link:
            guard let target = picked else { return nil }
            await adminRequestVM.mergeMemberIntoTreeMember(newMemberId: m.id, existingTreeMemberId: target)
            let result = adminRequestVM.mergeResult
            adminRequestVM.mergeResult = nil
            switch result {
            case .success?: return nil
            case .failure(let msg)?: return msg
            case nil:
                // قاصر: مربّع «اطلب موافقة ولي الأمر» يظهر — يُغلق هذا المربّع
                onClose()
                return takeError() ?? ""
            }
        case .addAndLink:
            await adminRequestVM.approveMember(memberId: m.id, fatherId: fatherPick?.id)
            if let e = takeError() { return e }
            return memberVM.member(byId: m.id)?.role == .pending
                ? L10n.t("تعذّر قبول العضو. حاول مرة أخرى.", "Couldn't approve the member. Try again.") : nil
        default:
            return nil
        }
    }

    /// خطأ نموذج العرض يظهر هنا داخل المربّع (لا تنبيه ثانٍ تحته)
    private func takeError() -> String? {
        let e = adminRequestVM.errorMessage
        adminRequestVM.errorMessage = nil
        return e
    }

    // MARK: التحميل

    private func load() async {
        guard !loaded else { return }
        if initialStep != .applicant { step = initialStep }
        if picked == nil, let preselected, suggestedMen.contains(where: { $0.id == preselected }) { picked = preselected }
        switch source {
        case .womenDaughters:
            if let m = member { womanRequest = await adminRequestVM.fetchWomanJoinRequest(for: m.id) }
            women = (try? await WomenStore.fetch()) ?? WomenStore.cache
        case .motherSuggestions:
            if case .completion(let r) = subject {
                do {
                    mothers = try await SupabaseConfig.client
                        .rpc("lineage_mother_suggestions", params: ["p_request_id": r.id.uuidString]).execute().value
                    let matching = mothers.filter(\.husbandMatches)
                    if picked == nil, matching.count == 1 { picked = matching[0].id }
                } catch {
                    if !ErrorHelper.isCancellation(error) {
                        Log.warning("[JoinBox] lineage_mother_suggestions: \(error.localizedDescription)")
                    }
                }
            }
        case .familyTree, .none:
            women = WomenStore.cache
        }
        loaded = true
    }
}

// MARK: - الاسم الكامل: كلماته المطابقة للطلب خضراء

/// الاسم الكامل واضحاً (سطران إن لزم)، والكلمة المطابقة لجزء اسم الطلب خضراء وأعرض قليلاً؛ القارئ الصوتي يقرأ الاسم كاملاً
struct AdminFullNameText: View {
    let words: [AdminJoinBoxRules.NameWord]

    var body: some View {
        words.enumerated().reduce(Text(verbatim: "")) { acc, item in
            let (i, w) = item
            let piece = Text(verbatim: (i > 0 ? " " : "") + w.text)
                .foregroundColor(w.matches ? DS.Color.success : DS.Color.textPrimary)
                .fontWeight(w.matches ? .semibold : .regular)
            return acc + piece
        }
        .dsFont(.rowTitle)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(words.map(\.text).joined(separator: " "))
    }
}

// MARK: - الشرائح: الميلاد و«الزوج: …»

/// «خالد · سعود · 1999 (· الزوج)» — كل قيمة شريحة صغيرة؛ المطابقة لبيانات الطلب خضراء بعلامة ✓، بلا تسميات رمادية،
/// والقارئ الصوتي يقرأ التسمية مع القيمة («الوالد خالد، مطابق»)
struct AdminValueChips: View {
    let chips: [AdminJoinBoxRules.Chip]

    var body: some View {
        DSChipFlow(spacing: DS.Spacing.xs) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, c in
                HStack(spacing: DS.Spacing.xxs) {
                    if c.matches {
                        Image(systemName: "checkmark")
                            .dsGlyph(DS.Glyph.micro, weight: .bold)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: AdminJoinBoxRules.chipText(c))
                        .dsFont(.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .foregroundColor(c.matches ? DS.Color.success : DS.Color.textSecondary)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xxs)
                .background(Capsule().fill(c.matches ? DS.Color.success.opacity(DS.Opacity.tintFill)
                                                     : DS.Color.cardBackgroundSoft))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(AdminJoinBoxRules.spoken(c))
            }
        }
    }
}
