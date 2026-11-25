import SwiftUI

// MARK: - «شجرة النساء» في «العائلة» (طلب المالك ٢٠٢٦-١١-٠٨، عينة samples/admin-women)
//
// تحت أرقام العائلة مفتاح «شجرة العائلة | شجرة النساء». هنا كل ما يخص النساء وشجرتهن في مكان واحد:
// مدخل «شجرة النساء» (يفتح تبويب الشجرة عليها) ← بحث باسمها أو اسم أبوها ← شرائح: الكل · المسجّلات · المتزوجات (اسم الزوج
// تحتها) · متوفيات · فرع خارج العائلة ← القائمة. «الأحدث» بعد «الكل» (طلب المالك ٢٠٢٦-١١-١٣): المضافات أو المربوطات بحساب خلال
// ٣٠ يوماً، الأحدث أولاً. للمالك والمدير وحدهما (طلب المالك ٢٠٢٦-١١-٠٨). الضغط على امرأة يفتح مربّع تفاصيلها نفسه في شجرة النساء
// (`WomanDetailSheet`). «فرع خارج العائلة» = أبناء البنات (`DaughterSonsIndex`، يفتح ورقة حسابه) وأزواج البنات من خارج
// العائلة والنساء من خارجها (زوجات من عوائل ثانية وبنات البنات — ٢٠٢٦-١١-٢٦) (`WomenStore.outsideFamilyIds`) — لا يُعدّون
// في أي رقم للعائلة ولا يظهرن في شرائح النساء. «شجرة العائلة» بلا أي امرأة (`AdminMembersIndex`).

enum AdminWomenChip: String, CaseIterable, Identifiable {
    case all, recent, accounts, married, deceased, outside
    var id: String { rawValue }

    /// نافذة «الأحدث» بالأيام — أُضيفت عقدتها أو أُنشئ حسابها المربوط خلالها
    static let recentDays = 30

    var title: String {
        switch self {
        case .all:       return L10n.t("الكل", "All")
        // «الأحدث» (طلب المالك ٢٠٢٦-١١-١٣ «فلتر اخر الاسماء المضافة او المربوطة بالتطبيق»)
        case .recent:    return L10n.t("الأحدث", "Newest")
        // بلا «ال» كشرائح «شجرة العائلة» («مسجّلون · متوفون») — طلب المالك ٢٠٢٦-١١-١١ «الفلاتر مو مضبوطة»
        case .accounts:  return L10n.t("مسجّلات", "Registered")
        case .married:   return L10n.t("متزوجات", "Married")
        case .deceased:  return L10n.t("متوفيات", "Deceased")
        case .outside:   return L10n.t("فرع خارج العائلة", "Outside branch")
        }
    }
}

/// صفّ في القائمة: امرأة (أو زوج من خارج العائلة) من شجرة النساء، أو حساب ابن بنت
/// طلب شريحة من الصفحة — بمعرّف جديد في كل طلب، فيُطبَّق حتى لو كانت الشريحة نفسها مطلوبة قبل
/// (كان الضغط على «خارج العائلة» مرة ثانية بعد تغيير الشريحة لا يرجعها)
struct AdminWomenChipRequest: Equatable {
    let chip: AdminWomenChip
    let id = UUID()
}

struct AdminWomenEntry: Identifiable {
    enum Kind { case woman(FamilyMember), outsideHusband(FamilyMember), son(FamilyMember) }
    let kind: Kind
    let title: String
    let subtitle: String?
    let status: (text: String, tint: Color)?
    let needle: String
    /// كلمات البحث محسوبة مرة (لا مع كل حرف)
    let words: [String]

    init(kind: Kind, title: String, subtitle: String?, status: (text: String, tint: Color)?, needle: String) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.needle = needle
        self.words = NameSearch.words(needle)
    }

    var id: UUID {
        switch kind {
        case .woman(let m), .outsideHusband(let m), .son(let m): return m.id
        }
    }
}

struct AdminWomenPanel: View {
    let women: [FamilyMember]
    /// طلب شريحة من الصفحة (حلقة «خارج العائلة» ← «فرع خارج العائلة») — الشريحة نفسها حالة هنا، فتبديلها لا يعيد رسم
    /// الصفحة كلها (كان «تهنيق» عند تغيير الفلتر — بلاغ المالك ٢٠٢٦-١١-٠٨)
    var requestedChip: AdminWomenChipRequest? = nil
    /// إعادة جلب شجرة النساء بعد تعديل من مربّع التفاصيل
    let reload: () async -> Void
    /// يفتح ورقة حساب العضو (ابن البنت)
    let openMember: (_ ids: [UUID], _ start: Int) -> Void

    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @ObservedObject private var sons = DaughterSonsIndex.shared

    @State private var query = ""
    @State private var chip: AdminWomenChip = .all
    @State private var limit = 40
    /// القوائم مبنية مرة لكل تغيّر في البيانات (كانت تُبنى مع كل ضغطة وحرف — بلاغ المالك ٢٠٢٦-١١-٠٨ «القسم شوي يعلق»)
    @State private var lists: [AdminWomenChip: [AdminWomenEntry]] = [:]
    @State private var built = false
    @State private var selectedWoman: FamilyMember?

    // MARK: البيانات

    /// آخر نسخة وصلت من البيانات — إغلاقات `onChange` ترى قيمة `women` القديمة (خاصية لا حالة)، فنبني من الجديدة
    @State private var latest: [FamilyMember] = []

    private func name(_ m: FamilyMember) -> String { m.fullName.isEmpty ? m.firstName : m.fullName }

    private func buildLists(_ women: [FamilyMember]) -> [AdminWomenChip: [AdminWomenEntry]] {
        let map = Dictionary(women.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let linked = WomenStore.linkedUserByWoman
        let outside = WomenStore.outsideFamilyIds
        var out: [AdminWomenChip: [AdminWomenEntry]] = [:]
        // «الأحدث»: تاريخ إضافة العقدة أو إنشاء حسابها المربوط (الأحدث منهما) خلال النافذة — يُرتَّب بعد الحلقة
        let cutoff = Calendar.current.date(byAdding: .day, value: -AdminWomenChip.recentDays, to: Date()) ?? .distantPast
        var recent: [(date: Date, entry: AdminWomenEntry)] = []
        let females = AdminGrouping.alphabetical(women.filter { $0.isFemale && !name($0).trimmingCharacters(in: .whitespaces).isEmpty })
        // النساء من خارج العائلة (`is_outside_family`، طلب المالك ٢٠٢٦-١١-٢٦): زوجات من عوائل ثانية وبنات البنات —
        // في «فرع خارج العائلة» وحده، لا في شرائح النساء (مثل حلقة «النساء» التي لا تعدّهن)
        var outsideWomen: [AdminWomenEntry] = []
        for w in females {
            if outside.contains(w.id) {
                let sub: String? = {
                    if let hid = w.husbandId, let h = map[hid] ?? memberVM.member(byId: hid) {
                        return L10n.t("زوجة: \(name(h))", "Wife of \(name(h))")
                    }
                    if let mom = w.motherId.flatMap({ map[$0] }) {
                        return L10n.t("بنت بنت · أمّها: \(name(mom))", "Daughter's daughter · mother: \(name(mom))")
                    }
                    return nil
                }()
                let status: (String, Color)? = w.isDeceased == true
                    ? (L10n.t("متوفاة", "Deceased"), DS.Color.textTertiary)
                    : (linked[w.id] != nil ? (L10n.t("مسجّلة", "Registered"), DS.Color.success) : nil)
                outsideWomen.append(AdminWomenEntry(kind: .woman(w), title: name(w), subtitle: sub, status: status,
                                                    needle: ArabicTextNormalizer.normalizeForSearch(name(w))))
                continue
            }
            let husband = w.husbandId.flatMap { map[$0] }
            let sub: String? = {
                // تحت اسمها (طلب المالك ٢٠٢٦-١١-٠٨): اسم الزوج · «متزوجة: غير مسجّل الزوج» · «غير متزوجة» — بلا «بنت فلان»
                if let husband {
                    let tag = outside.contains(husband.id) ? L10n.t(" (من خارج العائلة)", " (outside the family)") : ""
                    return L10n.t("الزوج: \(name(husband))\(tag)", "Husband: \(name(husband))\(tag)")
                }
                if w.isMarried == true { return L10n.t("متزوجة: غير مسجّل الزوج", "Married: husband not recorded") }
                return L10n.t("غير متزوجة", "Not married")
            }()
            let status: (String, Color)? = w.isDeceased == true
                ? (L10n.t("متوفاة", "Deceased"), DS.Color.textTertiary)
                : (linked[w.id] != nil ? (L10n.t("مسجّلة", "Registered"), DS.Color.success) : nil)
            let e = AdminWomenEntry(kind: .woman(w), title: name(w), subtitle: sub, status: status,
                                    needle: ArabicTextNormalizer.normalizeForSearch(name(w)))
            out[.all, default: []].append(e)
            if linked[w.id] != nil { out[.accounts, default: []].append(e) }
            if w.isDeceased == true { out[.deceased, default: []].append(e) }
            // «المتزوجات» (طلب المالك ٢٠٢٦-١١-٠٨): اسم الزوج تحتها، أو «الزوج غير مسجّل»
            if w.husbandId != nil || w.isMarried == true { out[.married, default: []].append(e) }
            let added = ApprovalWorkflow.date(w.createdAt)
            let linkedAt = linked[w.id].flatMap { memberVM.member(byId: $0) }.flatMap { ApprovalWorkflow.date($0.createdAt) }
            let byLink = linkedAt.map { l in added.map { l > $0 } ?? true } ?? false
            if let latest = byLink ? linkedAt : added, latest >= cutoff {
                let day = AdminOccasionsText.shortDate(latest)
                let line = byLink ? L10n.t("رُبطت بحساب \(day)", "Linked to an account \(day)")
                                  : L10n.t("أُضيفت \(day)", "Added \(day)")
                recent.append((latest, AdminWomenEntry(kind: .woman(w), title: e.title, subtitle: line, status: status,
                                                        needle: e.needle)))
            }
        }
        out[.recent] = recent.sorted { $0.date > $1.date }.map(\.entry)
        // فرع خارج العائلة: أبناء البنات (حساباتهم) ثم أزواج البنات من خارج العائلة
        var outsideRows: [AdminWomenEntry] = []
        // حساب مراجعة أبل ليس فرداً في «فرع خارج العائلة»
        let review = AppConfigValues.shared.reviewAccountIds
        let sonMembers = AdminGrouping.alphabetical(memberVM.allMembers.filter { sons.contains($0.id) && !review.contains($0.id) })
        for s in sonMembers {
            let node = WomenStore.womanByLinkedUser[s.id].flatMap { map[$0] }
            let mother = node?.motherId.flatMap { map[$0] }
            let sub = mother.map { L10n.t("أمّه: \(name($0)) · ابن بنت", "Mother: \(name($0)) · daughter's son") }
                ?? L10n.t("ابن بنت · لم يكمل حسابه", "Daughter's son · account not completed")
            let status: (String, Color) = node == nil
                ? (L10n.t("أكمل حسابه؟", "Not completed"), DS.Color.warning)
                : (L10n.t("في الشجرة", "In the tree"), DS.Color.success)
            outsideRows.append(AdminWomenEntry(kind: .son(s), title: s.fullName, subtitle: sub, status: status,
                                               needle: ArabicTextNormalizer.normalizeForSearch(s.fullName)))
        }
        for h in AdminGrouping.alphabetical(women.filter { outside.contains($0.id) && !$0.isFemale }) {
            let wife = women.first { $0.husbandId == h.id }
            outsideRows.append(AdminWomenEntry(kind: .outsideHusband(h), title: name(h),
                                               subtitle: wife.map { L10n.t("زوج: \(name($0))", "Husband of \(name($0))") },
                                               status: h.isDeceased == true ? (L10n.t("متوفى", "Deceased"), DS.Color.textTertiary) : nil,
                                               needle: ArabicTextNormalizer.normalizeForSearch(name(h))))
        }
        out[.outside] = outsideRows + outsideWomen
        return out
    }

    private func rows(_ all: [AdminWomenChip: [AdminWomenEntry]]) -> [AdminWomenEntry] {
        let base = all[chip] ?? []
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        let words = NameSearch.words(q)
        var hits: [(order: Int, score: Int, entry: AdminWomenEntry)] = []
        for (n, e) in base.enumerated() {
            if let score = NameSearch.score(queryWords: words, candidateWords: e.words) {
                hits.append((order: n, score: score, entry: e))
            }
        }
        hits.sort { $0.score != $1.score ? $0.score < $1.score : $0.order < $1.order }
        return hits.map(\.entry)
    }

    // MARK: الواجهة

    var body: some View {
        let all = lists
        let shown = built ? rows(all) : []
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            treeEntry
            AdminMembersSearchField(text: $query, placeholder: L10n.t("ابحث باسمها أو اسم أبيها", "Search by her or her father's name"))
            chips(all)
            HStack {
                Spacer(minLength: 0)
                Text(verbatim: countText(shown.count))
                    .dsFont(.caption)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
            }
            // مساحة القائمة لا تقصر فجأة عند تغيير الشريحة — كانت الصفحة تقفز للأعلى وتتبدّل حالة القسم (بلاغ المالك ٢٠٢٦-١١-٠٨)
            VStack(spacing: 0) {
                if women.isEmpty || !built {
                    AdminPageStateCard(.loading(L10n.t("جارٍ تحميل شجرة النساء…", "Loading the women's tree…")))
                } else if shown.isEmpty {
                    AdminPageStateCard(.empty(query.isEmpty ? emptyTitle : L10n.t("لا نتائج", "No results"),
                                              message: query.isEmpty ? nil : L10n.t("جرّب اسماً آخر", "Try another name")))
                } else {
                    list(shown)
                }
            }
            .frame(minHeight: DS.Hub.filterListMinHeight, alignment: .top)
        }
        .onAppear {
            if let requestedChip { chip = requestedChip.chip }
            rebuild()
        }
        .onChange(of: requestedChip) { r in if let r { chip = r.chip; query = ""; limit = 40 } }
        // أي تبدّل في بيانات النساء (تعديل بنفس العدد: وفاة، زوج، حالة) — لا العدد وحده
        .onChange(of: women) { rebuild($0) }
        .onChange(of: sons.ids) { _ in rebuild() }
        .onChange(of: memberVM.membersVersion) { _ in rebuild() }
        .onChange(of: chip) { _ in limit = 40 }
        .onChange(of: query) { _ in limit = 40 }
        .fullScreenCover(item: $selectedWoman) { w in
            WomanDetailSheet(
                woman: w,
                allWomen: women,
                me: authVM.currentUser,
                canEdit: authVM.canEditMembers,
                canDelete: authVM.canDeleteMembers,
                canAnnounceDeath: authVM.isAdmin,
                canModerate: authVM.canModerate,
                onChanged: { await reload(); rebuild() },
                onOpenMember: { id in
                    selectedWoman = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { selectedWoman = women.first { $0.id == id } }
                }
            )
            .background(ClearPresentationBackground())
        }
        .transaction { t in if selectedWoman != nil { t.disablesAnimations = true } }
    }

    /// `fresh`: القيمة الجديدة من `onChange(of: women)`؛ غيرها يبني من آخر ما وصل
    private func rebuild(_ fresh: [FamilyMember]? = nil) {
        if let fresh { latest = fresh }
        let source = latest.isEmpty ? women : latest
        guard !source.isEmpty else { return }
        lists = buildLists(source)
        built = true
    }

    /// مدخل الشجرة نفسها — يفتح تبويب الشجرة على «شجرة النساء» (كحلقة «النساء»)
    private var treeEntry: some View {
        Button {
            TreeTabContainer.openWomenOnAppear = true
            NotificationCenter.default.post(name: .openWomenTree, object: nil)
        } label: {
            AdminListRow(icon: "figure.stand.dress", tint: DS.Color.female,
                         title: L10n.t("شجرة النساء", "Women's tree"),
                         subtitle: L10n.t("افتح الشجرة · رتّب الزوجات · أضف أم أو زوجة", "Open the tree · order wives · add a mother or wife"))
        }
        .buttonStyle(.plain)
        .adminCard()
        .accessibilityHint(L10n.t("يفتح شجرة النساء", "Opens the women's tree"))
    }

    private func chips(_ all: [AdminWomenChip: [AdminWomenEntry]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xsm) {
                ForEach(AdminWomenChip.allCases.filter { $0 != .outside || !(all[.outside] ?? []).isEmpty }) { c in
                    Button {
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) { chip = c; limit = 40 }
                    } label: {
                        AdminMembersLightChip(title: c.title, count: c == .all ? nil : (all[c] ?? []).count, selected: c == chip)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(c == chip ? .isSelected : [])
                }
            }
            .padding(.horizontal, DS.Border.width)
        }
    }

    /// الحالة الفاضية بلا بحث — «الأحدث» تقول ما الذي تبحث عنه
    private var emptyTitle: String {
        chip == .recent
            ? L10n.t("لا أسماء مضافة أو مربوطة خلال \(AdminWomenChip.recentDays) يوماً",
                     "No names added or linked in the last \(AdminWomenChip.recentDays) days")
            : L10n.t("لا أحد هنا الآن", "Nobody here right now")
    }

    private func countText(_ n: Int) -> String {
        let number = AdminMembersFilterBar.grouped(n)
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { return L10n.t("\(number) نتيجة", "\(number) results") }
        switch chip {
        case .outside: return L10n.t("\(number) · لا يُعدّون في أرقام العائلة", "\(number) · not counted in family numbers")
        case .recent: return L10n.t("\(number) · الأحدث أولاً", "\(number) · newest first")
        default: return L10n.t("\(number) · أبجدياً", "\(number) · A–Z")
        }
    }

    private func list(_ shown: [AdminWomenEntry]) -> some View {
        let visible = Array(shown.prefix(limit))
        let sonIds = shown.compactMap { e -> UUID? in if case .son(let m) = e.kind { return m.id } else { return nil } }
        return VStack(alignment: .leading, spacing: 0) {
            LazyVStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { pos, e in
                    if pos > 0 { AdminRowDivider() }
                    Button { open(e, sonIds: sonIds) } label: { AdminWomenRow(entry: e) }
                        .buttonStyle(.plain)
                }
            }
            if shown.count > limit {
                AdminPillButton(title: L10n.t("عرض المزيد (\(shown.count - limit))", "Show more (\(shown.count - limit))"),
                                icon: "chevron.down", style: .soft, height: DS.Hub.pillHeightCard) {
                    limit += 40
                }
                .padding(.top, DS.Spacing.sm)
            }
        }
        .adminCard()
    }

    private func open(_ e: AdminWomenEntry, sonIds: [UUID]) {
        switch e.kind {
        case .woman(let m), .outsideHusband(let m): selectedWoman = m
        case .son(let m): openMember(sonIds, sonIds.firstIndex(of: m.id) ?? 0)
        }
    }
}

/// الصورة · الاسم كاملاً · سطر الزوج/الأب · الحالة كلمة خفيفة
struct AdminWomenRow: View {
    let entry: AdminWomenEntry

    private var member: FamilyMember {
        switch entry.kind { case .woman(let m), .outsideHusband(let m), .son(let m): return m }
    }

    private var tint: Color {
        switch entry.kind {
        case .woman: return member.isDeceased == true ? DS.Color.deceased : DS.Color.female
        case .outsideHusband, .son: return DS.Color.slate
        }
    }

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Group {
                if member.isDeceased == true {
                    DSMemberAvatar(name: entry.title, avatarUrl: member.avatarUrl, size: DS.Icon.avatar, roleColor: tint)
                        .grayscale(1)
                } else {
                    DSMemberAvatar(name: entry.title, avatarUrl: member.avatarUrl, size: DS.Icon.avatar, roleColor: tint)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                // الاسم كاملاً بحجمه — سطران إن طال (طلب المالك ٢٠٢٦-١١-٠٨ «ليش الاسم صغر»)
                Text(entry.title)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = entry.subtitle {
                    Text(verbatim: sub)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Spacing.xs)
            if let s = entry.status {
                Text(verbatim: s.text)
                    .dsFont(.caption)
                    .foregroundColor(s.tint.dsReadableGlyph)
                    .fixedSize()
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
