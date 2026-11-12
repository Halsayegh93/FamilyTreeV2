import SwiftUI

// MARK: - صفحة قائمة «يحتاج مراجعتك» (القرار ٣، موافقة المالك ٢٠٢٦-١١-١٢ «تمام» — عيّنة review-lists)
//
// كل قائمة من الست صفحة واحدة بنفس الشكل: رأس كحلي (العنوان والعدد · سطر الشرح · شريط التقدّم حيث له معنى) ← شرائح
// بأعدادها ← الأعضاء بأقسام ← زرّ الإصلاح في الصفّ نفسه (والاسم يفتح ورقة العضو بالسابق/التالي) ← سطر إرشاد.
// لا كتابة جديدة: كل زرّ يفتح المربّع الموجود أو يستدعي الموجود (حي ✓ المحلي، مربّع الوفاة، مربّع التاريخ، الحذف،
// الاتصال والواتساب). الأعضاء من الفهرس نفسه (`AdminMembersIndex`) والقائمة من `AdminMemberReview.rows`.

struct AdminReviewListPage: View {
    /// القائمة المعروضة — «الأحياء» و«تواريخ الوفاة» صفحة واحدة بقسمين (القرار ٦ «أ»، ٢٠٢٦-١١-١٢)
    @State private var review: AdminMemberReview
    /// «الفرع: …» المختار في «العائلة» — nil = كل العائلة
    let branchSet: Set<UUID>?

    init(review: AdminMemberReview, branchSet: Set<UUID>?) {
        _review = State(initialValue: review)
        self.branchSet = branchSet
    }

    /// «الأحياء والوفيات»: قسمان في الصفحة نفسها
    private var isLifeDeath: Bool { review == .living || review == .death }

    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    @ObservedObject private var sons = DaughterSonsIndex.shared
    @ObservedObject private var verified = AdminLivingVerifiedStore.shared
    @Environment(\.openURL) private var openURL

    @State private var index = AdminMembersIndex.empty
    @State private var filter = AdminReviewFilter.all
    @State private var query = ""
    @State private var limit = AdminMembersPage.pageSize
    @State private var sheet: AdminMemberSheetContext?
    /// «متوفى» من «هل ما زالوا أحياء؟»
    @State private var deathTarget: FamilyMember?
    /// «أدخل التاريخ» من «تاريخ وفاة غير مكتمل»
    @State private var dateTarget: FamilyMember?
    @State private var deleteTarget: FamilyMember?
    @State private var deleting = false
    @State private var deleteError: String?
    @State private var photoURL: AdminPhotoURL?

    var body: some View {
        AdminPage(header: header, content: AnyView(content))
            .dsTallBox(item: $sheet) { context in
                AdminMemberSheet(ids: context.ids, start: context.start)
            }
            .modifier(AdminLivingDeathBox(member: $deathTarget))
            .dsCenterBox(item: $dateTarget) { m in
                DeceasedDateBox(member: m)
            }
            .fullScreenCover(item: $photoURL) { p in
                ProjectPhotoViewer(urls: [p.url], startIndex: 0, section: .admin)
            }
            .dsAlert(L10n.t("حذف العضو نهائياً؟", "Delete the member permanently?"),
                     isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
                Button(L10n.t("حذف نهائي", "Delete permanently"), role: .destructive) {
                    if let m = deleteTarget { delete(m) }
                    deleteTarget = nil
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { deleteTarget = nil }
            } message: {
                Text(L10n.t("سيُحذف «\(deleteTarget?.fourPartName ?? "")» من الشجرة ولا يمكن التراجع.",
                            "“\(deleteTarget?.fourPartName ?? "")” will be removed from the tree. This can't be undone."))
            }
            .dsAlert(L10n.t("تعذّر الحذف", "Couldn't delete"),
                     isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button(L10n.t("حسناً", "OK")) { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
            .task {
                verified.activate(user: authVM.currentUser?.id)
                rebuild()
                await accounts.refresh()
            }
            .onChange(of: memberVM.membersVersion) { _ in rebuild() }
            .onChange(of: accounts.accounts) { _ in rebuild() }
            .onChange(of: accounts.loaded) { _ in rebuild() }
            .onChange(of: sons.ids) { _ in rebuild() }
            .onChange(of: filter) { _ in limit = AdminMembersPage.pageSize }
            .onChange(of: query) { _ in limit = AdminMembersPage.pageSize }
    }

    private func rebuild() {
        let names = appSettingsVM
        index = AdminMembersIndex.build(members: memberVM.allMembers, accounts: accounts.accounts,
                                        accountsReady: accounts.loaded, daughterSons: sons.ids,
                                        branchName: { names.branchName(for: $0) })
    }

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

    /// الشريحة ثم البحث — والأقسام متتالية بترتيبها الثابت (السنة فقط قبل بلا تاريخ…)
    private func shownRows(_ base: [Int]) -> [Int] {
        var rows = filter == .all ? base : base.filter { filter.matches(index.entries[$0], accounts: accounts) }
        rows = rows.enumerated().sorted { a, b in
            let ga = groupRank(index.entries[a.element]), gb = groupRank(index.entries[b.element])
            return ga != gb ? ga < gb : a.offset < b.offset
        }.map(\.element)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return rows }
        if NameSearch.isPhoneQuery(q) {
            let digits = NameSearch.digits(q)
            return digits.count >= 3 ? rows.filter { index.entries[$0].digits.contains(digits) } : []
        }
        let words = NameSearch.words(q)
        rows = rows.filter { NameSearch.score(queryWords: words, candidateWords: NameSearch.words(index.entries[$0].needle)) != nil }
        return rows
    }

    // MARK: الرأس

    private var header: AdminPageHeader {
        let count = baseRows.count
        return AdminPageHeader(back: AdminArea.family.title,
                               title: isLifeDeath ? AdminMemberReview.lifeDeathTitle
                                                  : "\(review.title) · \(AdminMembersFilterBar.grouped(count))",
                               subtitle: isLifeDeath ? AdminMemberReview.lifeDeathSubtitle : review.explanation,
                               glyph: review.icon,
                               accessory: progress.map { p in AnyView(AdminReviewProgress(progress: p)) })
    }

    /// شريط التقدّم: «راجعت N من M» · «اكتمل N من M» · «اكتمال البيانات P٪» — والباقي بلا شريط
    private var progress: AdminReviewProgress.Value? {
        guard index.built else { return nil }
        switch review {
        case .living:
            let all = index.rows(.verifyLiving, .all)
            guard !all.isEmpty else { return nil }
            let done = all.filter { verified.ids.contains(index.entries[$0].id) }.count
            return .init(done: done, total: all.count,
                         leading: L10n.t("راجعت \(done)", "Reviewed \(done)"), trailing: L10n.t("من \(all.count)", "of \(all.count)"))
        case .death:
            let all = index.rows(.deceased, .all).count
            let missing = index.rows(.deceased, .deathIncomplete).count
            guard all > 0 else { return nil }
            return .init(done: all - missing, total: all,
                         leading: L10n.t("اكتمل \(all - missing)", "Complete \(all - missing)"), trailing: L10n.t("من \(all)", "of \(all)"))
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
        let base = baseRows
        let rows = shownRows(base)
        return VStack(alignment: .leading, spacing: DS.Hub.stackSpacing) {
            if !index.built {
                AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الأعضاء…", "Loading members…")))
            } else {
                if isLifeDeath { lifeDeathSwitch }
                chipsRow(filters(base))
                if review == .death || review == .gaps {
                    AdminMembersSearchField(text: $query, placeholder: L10n.t("ابحث بالاسم أو رقم الهاتف", "Search by name or phone"))
                }
                if rows.isEmpty {
                    AdminPageStateCard(query.isEmpty
                        ? .empty(L10n.t("لا شيء للمراجعة", "Nothing to review"),
                                 message: L10n.t("هذه القائمة فارغة الآن", "This list is empty right now"), tint: DS.Color.success)
                        : .empty(L10n.t("لا نتائج", "No results"), message: L10n.t("جرّب اسماً آخر أو رقماً", "Try another name or number")))
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
                DSNoteCard(review.hint, icon: "info.circle.fill", tint: DS.Color.accent)
            }
        }
    }

    /// «الأحياء · تواريخ الوفاة» بعدد كل قسم — التبديل يرجع الشريحة للكل
    private var lifeDeathSwitch: some View {
        let living = AdminMemberReview.living.rows(in: index, verified: verified.ids).count
        let death = AdminMemberReview.death.rows(in: index, verified: verified.ids).count
        return DSSegmentedSwitch(options: [
            DSSegmentOption(id: AdminMemberReview.living, title: L10n.t("الأحياء", "Living"), icon: "person.2.fill", count: living),
            DSSegmentOption(id: AdminMemberReview.death, title: L10n.t("تواريخ الوفاة", "Death dates"), icon: "calendar", count: death)
        ], selection: Binding(get: { review }, set: { v in
            guard v != review else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { review = v; filter = .all; query = ""; limit = AdminMembersPage.pageSize }
        }), size: .regular)
    }

    private func chipsRow(_ list: [(filter: AdminReviewFilter, count: Int)]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xsm) {
                ForEach(list, id: \.filter) { item in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(DS.Anim.snappy) { filter = item.filter }
                    } label: {
                        AdminMembersLightChip(title: item.filter.title, count: item.count, selected: filter == item.filter)
                    }
                    .buttonStyle(DSPressStyle())
                    .accessibilityAddTraits(filter == item.filter ? .isSelected : [])
                }
            }
            .padding(.vertical, DS.Spacing.xxs)
        }
    }

    /// الأعضاء بأقسام (أحياء: سنة الميلاد · وفاة: السنة فقط/بلا تاريخ · مشكلات: نوعها) — غيرها قسم واحد
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
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            ForEach(order, id: \.self) { key in
                let list = buckets[key] ?? []
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    if !key.isEmpty {
                        HStack {
                            Text(verbatim: key).dsFont(.sectionTitle).foregroundColor(DS.Color.textTertiary)
                            Spacer(minLength: DS.Spacing.sm)
                            Text(verbatim: AdminMembersFilterBar.grouped(totals[key] ?? list.count))
                                .dsFont(.caption).monospacedDigit().foregroundColor(DS.Color.textTertiary)
                        }
                        .padding(.horizontal, DS.Spacing.xs)
                        .accessibilityAddTraits(.isHeader)
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element) { n, i in
                            if n > 0 { AdminRowDivider() }
                            AnyView(row(i, ids: ids, position: position[i] ?? 0))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .adminCard()
                }
            }
        }
    }

    /// ترتيب الأقسام: الأحياء بقسم الميلاد، والوفاة «السنة فقط» ثم «بلا تاريخ»، والمشكلات بنوعها
    private func groupRank(_ entry: AdminMembersIndex.Entry) -> Int {
        switch review {
        case .living:   return entry.living?.group.rawValue ?? 0
        case .death:
            if case .missing = DeceasedMemorial.classify(entry.member.deathDate) { return 1 }
            return 0
        case .problems: return entry.problems.first.flatMap { AdminMemberProblem.allCases.firstIndex(of: $0) } ?? 0
        default:        return 0
        }
    }

    private func groupTitle(_ entry: AdminMembersIndex.Entry) -> String? {
        switch review {
        case .living:
            return entry.living?.group.title
        case .death:
            switch DeceasedMemorial.classify(entry.member.deathDate) {
            case .missing: return L10n.t("بلا تاريخ", "No date")
            default:       return L10n.t("السنة فقط", "Year only")
            }
        case .problems:
            return entry.problems.first?.title
        default:
            return nil
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
                                canEdit: authVM.canEditMembers, open: open,
                                deceased: { deathTarget = entry.member },
                                alive: {
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    withAnimation(DS.Anim.snappy) { verified.markAlive(entry.id) }
                                })
        case .death:
            rowWith(entry, subline: AdminReviewText.deathLine(entry.member), open: open) {
                if authVM.canEditMembers {
                    DSChipButton(L10n.t("أدخل التاريخ", "Enter date"), icon: "calendar.badge.plus",
                                 tint: DS.Color.accent, size: .small) { dateTarget = entry.member }
                }
            }
        case .gaps:
            rowWith(entry, subline: entry.gaps.filter { $0 != .deathIncomplete }.map(\.tag).joined(separator: " · "), open: open) {
                DSChipButton(L10n.t("أكمل", "Complete"), tint: DS.Color.primary, size: .small, action: open)
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
            .buttonStyle(.plain)
            trailing()
        }
    }

    @ViewBuilder
    private func problemAction(_ entry: AdminMembersIndex.Entry, open: @escaping () -> Void) -> some View {
        let problems = entry.problems
        if problems.contains(.dupPhone) {
            // «قارن»: أصحاب الرقم نفسه في ورقة واحدة بالسابق/التالي
            DSChipButton(L10n.t("قارن", "Compare"), icon: "arrow.left.arrow.right", tint: DS.Color.primary, size: .small) {
                let same = samePhone(entry)
                sheet = AdminMemberSheetContext(ids: same, start: same.firstIndex(of: entry.id) ?? 0)
            }
        } else if problems.contains(.noName) && authVM.canDeleteMembers {
            Button { deleteTarget = entry.member } label: {
                Image(systemName: "trash.fill")
                    .dsGlyph(DSButtonSize.compact.glyph)
                    .modifier(DSDeleteCircleFace(enabled: !deleting, size: .compact))
            }
            .buttonStyle(DSPressStyle())
            .disabled(deleting)
            .accessibilityLabel(L10n.t("حذف \(entry.member.fourPartName)", "Delete \(entry.member.fourPartName)"))
        } else if let first = problems.first {
            DSChipButton(first.fixTitle, icon: first.icon, tint: DS.Color.primary, size: .small, action: open)
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

    private func delete(_ m: FamilyMember) {
        deleting = true
        Task {
            let ok = await memberVM.deleteMember(memberId: m.id)
            deleting = false
            if ok {
                NotificationCenter.default.post(name: .memberDeleted, object: m.id)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                deleteError = memberVM.errorMessage
                    ?? L10n.t("تأكد من الاتصال ثم حاول مرة أخرى.", "Check your connection and try again.")
            }
        }
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

/// شريط التقدّم في الرأس الكحلي: نصّ · شريط · نصّ
struct AdminReviewProgress: View {
    struct Value {
        let done: Int
        let total: Int
        let leading: String
        let trailing: String
    }
    let progress: Value

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(verbatim: progress.leading)
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                .tint(DS.Color.accentLight)
            Text(verbatim: progress.trailing)
        }
        .dsFont(.caption)
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
