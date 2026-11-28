import SwiftUI

// MARK: - صفحة قائمة «يحتاج مراجعتك» (القرار ٣، موافقة المالك ٢٠٢٦-١١-١٢؛ إعادة التصميم U12 ٢٠٢٦-١١-٢٦ — spec C.8)
//
// كل قائمة صفحة بنفس الشكل، تُفتح من صفحة «يحتاج مراجعتك» (`AdminReviewHubPage`): رأس كحلي (العنوان · الشرح · سطر الأرقام
// بعدد القائمة كاملة = رقم الصفّ الذي فتحها (T2) · شريط التقدّم حيث له معنى) ← حقل البحث («بيانات ناقصة») ← شرائح بُعد واحد
// تلتفّ (`DSFilterChips(style: .admin)` — لا مفتاح ولا تبويب) ← الأعضاء بأقسام ← زرّ الإصلاح في الصفّ نفسه (والاسم يفتح ورقة
// العضو بالسابق/التالي) ← سطر إرشاد.
// لا كتابة جديدة: كل زرّ يفتح المربّع الموجود أو يستدعي الموجود (حي ✓ المحلي، مربّع الوفاة، الاتصال والواتساب).
// لا حذف هنا (T4، F1): «بلا اسم» زرّه «الملف» يفتح ورقة العضو — بيت «حذف العضو نهائياً» الوحيد (قسم «الحساب»).
// الأعضاء من الفهرس نفسه (`AdminMembersIndex`) والقائمة من `AdminMemberReview.rows`.
// «تاريخ وفاة غير مكتمل» (`.death`) لم تعد هنا: بيتها الواحد `DeathDatesCampaignPage` (spec E.19) — `AdminReviewListPage(.death)`
// يفتحها هي (رابط «اليوم» وغيره يبقى يعمل). مفتاح «الأحياء · تواريخ الوفاة» حُذف (لا مفاتيح — قاعدة المالك ٣).
// تجربة الأدوار (`-tmpAdminRole`): «حي ✓» و«متوفى» تمرّ بـ`DebugAdminProbe.dryRun` (T0).

struct AdminReviewListPage: View {
    /// القائمة المعروضة
    let review: AdminMemberReview
    /// «الفرع: …» المختار في «العائلة» — nil = كل العائلة
    let branchSet: Set<UUID>?

    /// - start: الشريحة المختارة عند الفتح («المكرر والأخطاء» يفتح «مشكلات في الشجرة» على نوع المشكلة)
    init(review: AdminMemberReview, branchSet: Set<UUID>?, start: AdminReviewFilter = .all) {
        self.review = review
        self.branchSet = branchSet
        _filter = State(initialValue: start)
    }

    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    @ObservedObject private var sons = DaughterSonsIndex.shared
    @ObservedObject private var verified = AdminLivingVerifiedStore.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index = AdminMembersIndex.empty
    @State private var filter: AdminReviewFilter
    @State private var query = ""
    @State private var limit = AdminMembersPage.pageSize
    @State private var sheet: AdminMemberSheetContext?
    /// «متوفى» من «هل ما زالوا أحياء؟»
    @State private var deathTarget: FamilyMember?
    @State private var photoURL: AdminPhotoURL?

    // حارس المكدس: الصفحة والمربّعات طبقات خلف `AnyView`
    var body: some View {
        if review == .death {
            // بيت واحد لاستكمال تواريخ الوفاة (spec E.19)
            AnyView(DeathDatesCampaignPage())
        } else {
            AnyView(page)
                .debugStackProbe("AdminReviewListPage")
        }
    }

    private var page: some View {
        AdminPage(header: header, content: AnyView(content))
            .dsTallBox(item: $sheet) { context in
                AdminMemberSheet(ids: context.ids, start: context.start)
            }
            .modifier(AdminLivingDeathBox(member: $deathTarget))
            .fullScreenCover(item: $photoURL) { p in
                ProjectPhotoViewer(urls: [p.url], startIndex: 0, section: .admin)
            }
            .refreshable { await reload(force: true) }
            .task { await reload(force: false) }
            .onChange(of: memberVM.membersVersion) { _ in rebuild() }
            .onChange(of: accounts.accounts) { _ in rebuild() }
            .onChange(of: accounts.loaded) { _ in rebuild() }
            .onChange(of: sons.ids) { _ in rebuild() }
            .onChange(of: filter) { _ in limit = AdminMembersPage.pageSize }
            .onChange(of: query) { _ in limit = AdminMembersPage.pageSize }
    }

    private func reload(force: Bool) async {
        verified.activate(user: authVM.currentUser?.id)
        if memberVM.allMembers.isEmpty || force { await memberVM.fetchAllMembers(force: force) }
        rebuild()
        await accounts.refresh(force: force)
    }

    private func rebuild() {
        let names = appSettingsVM
        index = AdminMembersIndex.build(members: memberVM.allMembers, accounts: accounts.accounts,
                                        accountsReady: accounts.loaded, daughterSons: sons.ids,
                                        branchName: { names.branchName(for: $0) })
    }

    /// أزرار الإصلاح والتسجيل: صلاحية الدور مضروبة بـ«يعدّل» في جدول السيرفر (Autoplan note 7)
    private var canEdit: Bool { authVM.canEditMembers && authVM.adminCanEdit(.family) }
    private var canDelete: Bool { authVM.canDeleteMembers && authVM.adminCanEdit(.family) }

    /// القائمة جاهزة: الفهرس مبني، وقوائم الحسابات وصلت لقائمتي «الحسابات» (قبلها فارغة كذباً — spec A.12)
    private var ready: Bool { index.built && (!review.isUsage || index.accountsReady) }

    // MARK: الأعضاء

    /// القائمة كاملة داخل الفرع، بترتيبها: الأكثر نقصاً أولاً في «بيانات ناقصة»، والأطول غياباً أولاً في «لم يدخلوا»
    private var baseRows: [Int] {
        var rows = review.rows(in: index, verified: verified.ids)
        if let set = branchSet { rows = rows.filter { set.contains(index.entries[$0].id) } }
        switch review {
        case .gaps:
            let n = { (i: Int) in index.entries[i].gaps.filter { $0 != .deathIncomplete }.count }
            rows = rows.enumerated().sorted { n($0.element) != n($1.element) ? n($0.element) > n($1.element) : $0.offset < $1.offset }
                .map(\.element)
        case .inactive:
            let seen = { (i: Int) in accounts.info(index.entries[i].id)?.lastSeen ?? .distantPast }
            rows.sort { seen($0) < seen($1) }
        default: break
        }
        return rows
    }

    /// الشرائح بأعدادها — «الكل» ثم ما فيه أعضاء فقط
    private func filters(_ base: [Int]) -> [(filter: AdminReviewFilter, count: Int)] {
        let options = AdminReviewFilter.options(for: review)
        let entries = base.map { index.entries[$0] }
        return options.compactMap { f in
            let n = f == .all ? entries.count : entries.filter { f.matches($0, accounts: accounts) }.count
            return f == .all || n > 0 ? (f, n) : nil
        }
    }

    /// الشريحة ثم البحث — والأقسام متتالية بترتيبها الثابت
    private func shownRows(_ base: [Int]) -> [Int] {
        var rows = filter == .all ? base : base.filter { filter.matches(index.entries[$0], accounts: accounts) }
        rows = rows.enumerated().sorted { a, b in
            let ga = groupRank(index.entries[a.element]), gb = groupRank(index.entries[b.element])
            return ga != gb ? ga < gb : a.offset < b.offset
        }.map(\.element)
        let q = trimmedQuery
        guard !q.isEmpty else { return rows }
        if NameSearch.isPhoneQuery(q) {
            let digits = NameSearch.digits(q)
            return digits.count >= 3 ? rows.filter { index.entries[$0].digits.contains(digits) } : []
        }
        let words = NameSearch.words(q)
        rows = rows.filter { NameSearch.score(queryWords: words, candidateWords: NameSearch.words(index.entries[$0].needle)) != nil }
        return rows
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: الرأس

    /// «‹ يحتاج مراجعتك» · العنوان · الشرح · «41 عضواً» (رقم الصفّ الذي فتحها، بلا سهم) · شريط التقدّم
    private var header: AdminPageHeader {
        let count: Int? = ready ? baseRows.count : nil
        // العنوان = اسم الصفّ الذي فتحها في «يحتاج مراجعتك» (اسم واحد لكل قائمة)
        let title = AdminReviewHubLogic.List(rawValue: review.rawValue)?.title ?? review.title
        return AdminPageHeader(title: title,
                               subtitle: review.explanation,
                               readOnly: !authVM.adminCanEdit(.family),
                               items: [AdminHeaderItem(id: "count", value: count, label: Self.membersNoun(count))],
                               accessory: progress.map { p in AnyView(AdminReviewProgress(progress: p)) })
    }

    /// «عضو» · «عضوان» · «أعضاء» · «عضواً»
    static func membersNoun(_ n: Int?) -> String {
        guard let n else { return L10n.t("عضو", "members") }
        return L10n.t(AdminFilterText.noun(n, one: "عضو", two: "عضوان", few: "أعضاء", many: "عضواً"),
                      n == 1 ? "member" : "members")
    }

    /// شريط التقدّم: «راجعت N من M» · «اكتمال البيانات P٪» — والباقي بلا شريط
    private var progress: AdminReviewProgress.Value? {
        guard index.built else { return nil }
        switch review {
        case .living:
            let all = index.rows(.verifyLiving, .all)
            guard !all.isEmpty else { return nil }
            let done = all.filter { verified.ids.contains(index.entries[$0].id) }.count
            return .init(done: done, total: all.count,
                         leading: L10n.t("راجعت \(done)", "Reviewed \(done)"), trailing: L10n.t("من \(all.count)", "of \(all.count)"))
        case .gaps:
            let living: Int = index.entries.reduce(0) { $0 + ($1.member.isDeceased == true ? 0 : 1) }
            guard living > 0 else { return nil }
            let missing: Int = index.rows(.gaps, .all).count
            let done: Int = max(0, living - missing)
            let pct: Int = Int((Double(done) / Double(living) * 100).rounded())
            let leading: String = L10n.t("مكتمل \(pct)٪", "\(pct)% complete")
            let trailing: String = L10n.t("اكتمال البيانات", "Data completeness")
            return AdminReviewProgress.Value(done: done, total: living, leading: leading, trailing: trailing)
        default:
            return nil
        }
    }

    // MARK: المحتوى

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Hub.stackSpacing) {
            if memberVM.membersLoadFailed && memberVM.allMembers.isEmpty {
                AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                                          message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                          retry: { Task { await reload(force: true) } }))
            } else if !ready {
                AdminPageStateCard(.loading(L10n.t("جارٍ تحميل القائمة…", "Loading the list…"), rows: 5))
            } else {
                AnyView(loaded)
            }
        }
    }

    private var loaded: some View {
        let base = baseRows
        let rows = shownRows(base)
        let options = filters(base)
        return VStack(alignment: .leading, spacing: DS.Hub.stackSpacing) {
            if review == .gaps {
                DSSearchField(text: $query, placeholder: AdminFilterText.searchPlaceholder, style: .admin)
            }
            // بُعد واحد = صفّ شرائح يلتفّ (spec A.9 الاستعمال ١) — لا ورقة فلاتر لخيار واحد
            if options.count > 1 {
                DSFilterChips(options: options.map { DSFilterOption(id: $0.filter, title: $0.filter.title, count: $0.count) },
                              selection: $filter, style: .admin)
            }
            if rows.isEmpty {
                emptyCard(listIsEmpty: base.isEmpty)
            } else {
                AnyView(groups(rows))
                if rows.count > limit {
                    AdminPillButton(title: L10n.t("عرض المزيد (\(rows.count - limit))", "Show more (\(rows.count - limit))"),
                                    icon: "chevron.down", style: .soft, height: DS.Hub.pillHeightCard) {
                        limit += AdminMembersPage.pageSize
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            hint
        }
    }

    /// فارغة: بالبحث «لا أحد بهذا الاسم أو الرقم» + «مسح البحث»؛ بالشريحة «لا نتائج بهذه التصفية» + «عرض الكل» (شريحة «الكل»)؛
    /// والقائمة نفسها فارغة «لا شيء للمراجعة» (spec A.12)
    @ViewBuilder
    private func emptyCard(listIsEmpty: Bool) -> some View {
        if !trimmedQuery.isEmpty {
            AdminPageStateCard(.empty(L10n.t("لا أحد بهذا الاسم أو الرقم", "Nobody with this name or number"),
                                      actionTitle: L10n.t("مسح البحث", "Clear search"),
                                      action: { query = "" }))
        } else if filter != .all && !listIsEmpty {
            AdminFilterEmptyCard(showAll: { withAnimation(reduceMotion ? nil : DS.Anim.snappy) { filter = .all } })
        } else {
            AdminPageStateCard(.empty(L10n.t("لا شيء للمراجعة", "Nothing to review"),
                                      message: L10n.t("هذه القائمة فارغة الآن", "This list is empty right now"),
                                      tint: DS.Color.success))
        }
    }

    /// سطر الإرشاد آخر الصفحة — ١٣ رمادي بلا بطاقة
    private var hint: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xsm) {
            Image(systemName: "info.circle")
                .dsGlyph(DS.Glyph.sm, weight: .medium)
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)
            Text(review.hint)
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Spacing.xxs)
        .padding(.top, DS.Spacing.xs)
    }

    /// الأعضاء بأقسام (أحياء: سنة الميلاد · مشكلات: نوعها) — غيرها قسم واحد. عنوان القسم ١٥ والعدد ١٣ في طرفه (spec A.4)
    private func groups(_ rows: [Int]) -> some View {
        let visible = Array(rows.prefix(limit))
        let ids = rows.map { index.entries[$0].id }
        var order: [String] = []
        var buckets: [String: [Int]] = [:]
        for i in visible {
            let key = groupTitle(index.entries[i]) ?? ""
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(i)
        }
        // عدد القسم كاملاً (لا المعروض منه فقط)
        var totals: [String: Int] = [:]
        for i in rows { totals[groupTitle(index.entries[i]) ?? "", default: 0] += 1 }
        let position = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1, $0) })
        return VStack(alignment: .leading, spacing: DS.Hub.sectionGap) {
            ForEach(order, id: \.self) { key in
                let list = buckets[key] ?? []
                VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
                    if !key.isEmpty {
                        AdminSectionLabel(title: key, trailing: DSNumber.grouped(totals[key] ?? list.count))
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element) { n, i in
                            if n > 0 { AdminRowDivider(inset: DS.Icon.avatar + DS.Spacing.md) }
                            AnyView(row(i, ids: ids, position: position[i] ?? 0))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .adminCard()
                }
            }
        }
    }

    /// ترتيب الأقسام: الأحياء بقسم الميلاد، والمشكلات بنوعها
    private func groupRank(_ entry: AdminMembersIndex.Entry) -> Int {
        switch review {
        case .living:   return entry.living?.group.rawValue ?? 0
        case .problems: return entry.problems.first.flatMap { AdminMemberProblem.allCases.firstIndex(of: $0) } ?? 0
        default:        return 0
        }
    }

    private func groupTitle(_ entry: AdminMembersIndex.Entry) -> String? {
        switch review {
        case .living:   return entry.living?.group.title
        case .problems: return entry.problems.first?.title
        default:        return nil
        }
    }

    // MARK: الصفّ

    @ViewBuilder
    private func row(_ i: Int, ids: [UUID], position: Int) -> some View {
        let entry = index.entries[i]
        let open = { sheet = AdminMemberSheetContext(ids: ids, start: position) }
        switch review {
        case .living:
            AdminLivingCheckRow(entry: entry, reason: AdminReviewText.livingLine(entry),
                                canEdit: canEdit, open: open,
                                deceased: { markDeceased(entry.member) },
                                alive: { markAlive(entry.id) })
        case .death:
            // لا تُرسم: `.death` تفتح `DeathDatesCampaignPage` (أعلى)
            rowWith(entry, subline: AdminReviewText.deathLine(entry.member), open: open) { EmptyView() }
        case .gaps:
            rowWith(entry, subline: entry.gaps.filter { $0 != .deathIncomplete }.map(\.tag).joined(separator: " · "), open: open) {
                if canEdit {
                    AdminPillButton(title: L10n.t("أكمل", "Complete"), style: .soft, height: DS.Hub.pillHeightCard, action: open)
                        .fixedSize()
                }
            }
        case .problems:
            rowWith(entry, subline: entry.problems.map(\.title).joined(separator: " · "), open: open) {
                problemAction(entry, open: open)
            }
        case .notOpened, .inactive:
            rowWith(entry, subline: usageLine(entry), warns: false, open: open) {
                contactButtons(entry.member, invite: review == .notOpened)
            }
        }
    }

    /// الصفّ الموحّد: الصورة والاسم وسطر السبب (يفتح الورقة) + الإجراء في الطرف
    private func rowWith<Trailing: View>(_ entry: AdminMembersIndex.Entry, subline: String, warns: Bool = true,
                                         open: @escaping () -> Void,
                                         @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Button(action: open) {
                AdminMemberListRow(entry: entry, subline: subline, warns: warns,
                                   onPhotoTap: { photoURL = AdminPhotoURL(url: $0) }, showsStatus: false)
            }
            .buttonStyle(AdminRowPressStyle())
            trailing()
        }
    }

    @ViewBuilder
    private func problemAction(_ entry: AdminMembersIndex.Entry, open: @escaping () -> Void) -> some View {
        let problems = entry.problems
        if problems.contains(.dupPhone) {
            // «قارن»: أصحاب الرقم نفسه في ورقة واحدة بالسابق/التالي (عرض — يبقى للاطلاع أيضاً)
            AdminPillButton(title: L10n.t("قارن", "Compare"), icon: "arrow.left.arrow.right", style: .soft,
                            height: DS.Hub.pillHeightCard) {
                let same = samePhone(entry)
                sheet = AdminMemberSheetContext(ids: same, start: same.firstIndex(of: entry.id) ?? 0)
            }
            .fixedSize()
        } else if problems.contains(.noName) && canDelete {
            // T4: بيت حذف العضو الوحيد ورقة العضو («الحساب» ← «حذف العضو نهائياً») — «الملف» يفتحها (كان سلّة حذف هنا)
            let profile = L10n.t("الملف", "Profile")
            AdminPillButton(title: profile, icon: "person.crop.circle", style: .soft, height: DS.Hub.pillHeightCard,
                            action: open)
                .fixedSize()
                .accessibilityLabel(Text(verbatim: "\(profile): \(entry.member.fourPartName)"))
        } else if let first = problems.first, canEdit {
            AdminPillButton(title: first.fixTitle, icon: first.icon, style: .soft, height: DS.Hub.pillHeightCard, action: open)
                .fixedSize()
        }
    }

    /// أعضاء يشتركون في رقم هذا العضو (آخر ٨ أرقام)
    private func samePhone(_ entry: AdminMembersIndex.Entry) -> [UUID] {
        let key = String(NameSearch.digits(entry.member.phoneNumber ?? "").suffix(8))
        guard key.count == 8 else { return [entry.id] }
        let same = index.entries.filter { String(NameSearch.digits($0.member.phoneNumber ?? "").suffix(8)) == key }.map(\.id)
        return same.isEmpty ? [entry.id] : same
    }

    /// «آخر دخول قبل 34 يوماً» / «لم يسجّل الدخول»
    private func usageLine(_ entry: AdminMembersIndex.Entry) -> String {
        guard review == .inactive else { return AdminMemberSub.notSignedIn.title }
        guard let seen = accounts.info(entry.id)?.lastSeen else { return AdminMemberSub.inactive.title }
        let days = max(0, Calendar.current.dateComponents([.day], from: seen, to: Date()).day ?? 0)
        return L10n.t("آخر دخول قبل \(days) يوماً", "Last seen \(days) days ago")
    }

    /// اتصال + واتساب (برسالة الدعوة للتطبيق لمن لم يفتحه بعد)
    @ViewBuilder
    private func contactButtons(_ m: FamilyMember, invite: Bool) -> some View {
        if let phone = m.phoneNumber, !phone.isEmpty {
            HStack(spacing: DS.Spacing.xs) {
                if let tel = KuwaitPhone.telURL(phone) {
                    AdminReviewCircleButton(symbol: "phone.fill", tint: DS.Color.sea,
                                            label: L10n.t("اتصال", "Call")) { openURL(tel) }
                }
                if let wa = whatsappURL(phone, invite: invite) {
                    AdminReviewCircleButton(symbol: "message.fill", tint: DS.Color.success,
                                            label: L10n.t("واتساب", "WhatsApp")) { openURL(wa) }
                }
            }
        }
    }

    private func whatsappURL(_ phone: String, invite: Bool) -> URL? {
        guard let base = KuwaitPhone.whatsappURL(phone) else { return nil }
        guard invite else { return base }
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "text", value: AdminReviewText.inviteMessage(appSettingsVM.settings))]
        return parts?.url ?? base
    }

    // MARK: الكتابة (كلها تمرّ بـ`DebugAdminProbe.dryRun` — نجاح مصطنع أثناء تجربة دور)

    /// «حي ✓» — مراجعة محلية لهذا المستخدم على جهازه
    private func markAlive(_ id: UUID) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if DebugAdminProbe.dryRun("living-check alive \(id)") { return }
        withAnimation(reduceMotion ? nil : DS.Anim.snappy) { verified.markAlive(id) }
    }

    /// «متوفى» — مربّع تسجيل الوفاة الموجود (`AdminLivingDeathBox`)؛ أثناء تجربة دور لا يُفتح (الحفظ داخله)
    private func markDeceased(_ m: FamilyMember) {
        if DebugAdminProbe.dryRun("death box (mark deceased) \(m.id)") { return }
        deathTarget = m
    }
}

// MARK: - الشرائح

enum AdminReviewFilter: Hashable {
    case all
    case livingGroup(AdminLivingCheck.Group)
    case deathYearOnly, deathMissing
    case gap(AdminMemberGap)
    case problem(AdminMemberProblem)
    case inKuwait, abroad
    case awayShort, awayLong

    static func options(for review: AdminMemberReview) -> [AdminReviewFilter] {
        switch review {
        case .living:    return [.all] + AdminLivingCheck.Group.allCases.map { .livingGroup($0) }
        case .death:     return [.all, .deathYearOnly, .deathMissing]
        case .gaps:      return [.all, .gap(.noBirth), .gap(.noGender), .gap(.noPhoto)]
        case .problems:  return [.all] + AdminMemberProblem.allCases.map { .problem($0) }
        case .notOpened: return [.all, .inKuwait, .abroad]
        case .inactive:  return [.all, .awayShort, .awayLong]
        }
    }

    var title: String {
        switch self {
        case .all:                 return L10n.t("الكل", "All")
        case .livingGroup(let g):  return g.title
        case .deathYearOnly:       return L10n.t("السنة فقط", "Year only")
        case .deathMissing:        return L10n.t("بلا تاريخ", "No date")
        case .gap(let g):
            switch g {
            case .noBirth:  return L10n.t("الميلاد", "Birth")
            case .noGender: return L10n.t("الجنس", "Gender")
            case .noPhoto:  return L10n.t("الصورة", "Photo")
            case .deathIncomplete: return g.tag
            }
        case .problem(let p):      return p.title
        case .inKuwait:            return L10n.t("داخل الكويت", "In Kuwait")
        case .abroad:              return L10n.t("خارج الكويت", "Abroad")
        case .awayShort:           return L10n.t("21 إلى 60 يوماً", "21–60 days")
        case .awayLong:            return L10n.t("أكثر من 60 يوماً", "Over 60 days")
        }
    }

    @MainActor
    func matches(_ entry: AdminMembersIndex.Entry, accounts: AdminAccountsStore) -> Bool {
        switch self {
        case .all: return true
        case .livingGroup(let g): return entry.living?.group == g
        case .deathYearOnly:
            if case .missing = DeceasedMemorial.classify(entry.member.deathDate) { return false }
            return true
        case .deathMissing:
            if case .missing = DeceasedMemorial.classify(entry.member.deathDate) { return true }
            return false
        case .gap(let g): return entry.gaps.contains(g)
        case .problem(let p): return entry.problems.contains(p)
        case .inKuwait, .abroad:
            let d = NameSearch.digits(entry.member.phoneNumber ?? "")
            let kuwait = d.count == 8 || d.hasPrefix("965") || d.hasPrefix("00965")
            return self == .inKuwait ? kuwait : !kuwait
        case .awayShort, .awayLong:
            guard let seen = accounts.info(entry.id)?.lastSeen else { return self == .awayLong }
            let days = Calendar.current.dateComponents([.day], from: seen, to: Date()).day ?? 0
            return self == .awayShort ? days <= 60 : days > 60
        }
    }
}

// MARK: - النصوص

enum AdminReviewText {
    /// «مواليد 1908 · 118 سنة» أو «بلا تاريخ ميلاد»
    static func livingLine(_ entry: AdminMembersIndex.Entry) -> String {
        guard let y = entry.living?.birthYear else { return L10n.t("بلا تاريخ ميلاد", "No birth date") }
        let age = Calendar.current.component(.year, from: Date()) - y
        return L10n.t("مواليد \(y) · \(age) سنة", "Born \(y) · \(age) years")
    }

    /// «توفي 1985» أو «لا يوجد تاريخ للوفاة»
    static func deathLine(_ m: FamilyMember) -> String {
        switch DeceasedMemorial.classify(m.deathDate) {
        case .yearOnly(let y), .hijriLike(let y): return L10n.t("الوفاة: السنة فقط \(y)", "Death: year only \(y)")
        case .exact: return AdminMemberGap.deathIncomplete.title
        case .missing: return L10n.t("لا يوجد تاريخ للوفاة", "No date of death")
        }
    }

    /// رسالة دعوة التطبيق — نصّها من السيرفر (`app_config.app_invite_message`) إن وُجد، والرابطان من «فرض التحديث»
    @MainActor
    static func inviteMessage(_ s: AppSettings) -> String {
        var lines = [AppConfigValues.shared.string("app_invite_message")
                     ?? "السلام عليكم، هذا تطبيق عائلة المحمدعلي — حمّله وسجّل دخولك برقم جوالك:"]
        if let ios = s.iosUpdateUrl, !ios.isEmpty { lines.append("آيفون: \(ios)") }
        if let android = s.androidUpdateUrl, !android.isEmpty { lines.append("أندرويد: \(android)") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - أجزاء

/// شريط التقدّم في الرأس الكحلي (spec A.11 «مقياس»): نصّ · شريط ٨ بطرفين مدوّرين على مسار الكحلي · نصّ — ١٣ ذهبي
struct AdminReviewProgress: View {
    struct Value {
        let done: Int
        let total: Int
        let leading: String
        let trailing: String
    }
    let progress: Value

    var body: some View {
        let share = Double(progress.done) / Double(max(progress.total, 1))
        HStack(spacing: DS.Spacing.sm) {
            Text(verbatim: progress.leading)
                .fixedSize()
            DSMeterBar(parts: [DSGaugePart("done", share: share, tint: DS.Color.accentLight)], track: DS.Ring.bandTrack)
                .accessibilityHidden(true)
            Text(verbatim: progress.trailing)
                .fixedSize()
        }
        .dsFont(.subtitle)
        .monospacedDigit()
        .foregroundColor(DS.Color.accentLight)
        .accessibilityElement(children: .combine)
    }
}

/// زرّ دائري صغير (اتصال، واتساب) بلمس ٤٤
struct AdminReviewCircleButton: View {
    let symbol: String
    let tint: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .dsGlyph(DS.Glyph.md, weight: .semibold)
                .foregroundColor(tint.dsReadableGlyph)
                .frame(width: DS.Icon.row, height: DS.Icon.row)
                .background(Circle().fill(tint.opacity(DS.Opacity.tintFill)))
                .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(label)
    }
}
