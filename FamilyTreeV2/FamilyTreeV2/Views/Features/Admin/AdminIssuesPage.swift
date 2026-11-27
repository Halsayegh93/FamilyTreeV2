import Combine
import SwiftUI

// MARK: - «المكرر والأخطاء» (طلب المالك ٢٠٢٦-١١-٢٧ «ابيك في قسم العائلة توريني قسم المكرر او الاخطاء»)
//
// صفّ ظاهر في جذر «العائلة» تحت «يحتاج مراجعتك» (`AdminIssuesRow`، يختفي حين لا شيء) يفتح هذه الصفحة بثلاث قوائم:
//  ١) «أسماء مكررة» — نفس الأب ونفس الاسم الأول بعد التطبيع (`AdminDuplicateNames`)، شجرة الرجال للجميع وشجرة النساء للمالك
//     والمدير (من يرى النساء في «العائلة»). المجموعة صفّ: الاسم · «أبناء فلان» · كل شخص بسطر (سنة الميلاد · «له حساب» ·
//     «متوفى») يفتح ورقة العضو (`AdminMemberSheet`) أو مربّع المرأة (`WomanDetailSheet`). «ليسا مكرّرين» محلي لكل مستخدم
//     (`AdminDuplicateDismissStore`). لا دمج ولا حذف هنا.
//  ٢) «مشكلات الشجرة» — الأنواع الخمسة بأعدادها، كلٌّ يفتح قائمتها الموجودة بأزرار إصلاحها
//     (`AdminReviewListPage(.problems, start: .problem(…))`).
//  ٣) «أرقام بدون أسماء» (المالك والمدير) — دخلوا برمز الدخول ولم يكملوا التسجيل: الرقم كاملاً · «سُجّل في …» · «الإشعارات
//     مفعّلة» · اتصال وواتساب. لا حذف (تُحذف تلقائياً بعد ٣٠ يوماً).

/// «ليسا مكرّرين» — مراجعة محلية لكل مستخدم على جهازه (UserDefaults، مثل `AdminLivingVerifiedStore`)، بلا عمود سيرفر
@MainActor
final class AdminDuplicateDismissStore: ObservableObject {
    static let shared = AdminDuplicateDismissStore()

    @Published private(set) var signatures: Set<String> = []
    private var user: String?

    private static func key(_ user: String) -> String { "admin.duplicateDismissed.\(user)" }

    func activate(user id: UUID?) {
        let u = id?.uuidString.lowercased() ?? ""
        guard u != user else { return }
        user = u
        let raw = UserDefaults.standard.string(forKey: Self.key(u)) ?? ""
        let loaded = Set(raw.split(separator: "\n").map(String.init))
        if loaded != signatures { signatures = loaded }
    }

    func dismiss(_ signature: String) {
        guard !signatures.contains(signature) else { return }
        signatures.insert(signature)
        save()
    }

    func reset() {
        guard !signatures.isEmpty else { return }
        signatures = []
        save()
    }

    private func save() {
        guard let user else { return }
        UserDefaults.standard.set(signatures.sorted().joined(separator: "\n"), forKey: Self.key(user))
    }
}

/// ما تعرضه الصفحة ويعدّه صفّها — مكان واحد للحساب
@MainActor
struct AdminIssuesData {
    var men: [AdminDuplicateNames.Group] = []
    var women: [AdminDuplicateNames.Group] = []
    /// «أرقام بدون أسماء» (المالك والمدير فقط) — الأحدث أولاً
    var nameless: [UUID] = []

    var duplicates: Int { men.count + women.count }

    /// - women: شجرة النساء (فارغة = لا تُحسب)
    /// - seesAll: المالك والمدير — شجرة النساء والأرقام
    static func make(members: [FamilyMember], women: [FamilyMember], accounts: AdminAccountsStore,
                     dismissed: Set<String>, seesAll: Bool) -> AdminIssuesData {
        var out = AdminIssuesData()
        let live = members.filter { $0.status != .deleted }
        out.men = AdminDuplicateNames.groups(live.map { .init(id: $0.id, parent: $0.fatherId, firstName: $0.firstName) },
                                             dismissed: dismissed)
        guard seesAll else { return out }
        if !women.isEmpty {
            // عقد الرجال المنسوخة في شجرة النساء (معرّفها في `profiles`) مكانها شجرة الرجال
            let profileIds = Set(members.map(\.id))
            out.women = AdminDuplicateNames.groups(women.map { .init(id: $0.id, parent: $0.fatherId, firstName: $0.firstName) },
                                                   excluding: profileIds, dismissed: dismissed)
        }
        out.nameless = AdminDuplicateNames.nameless(members.map { m in
            .init(id: m.id, name: m.fullName, pending: m.status == .pending,
                  hasLogin: hasLogin(m.id, accounts: accounts), created: created(m, accounts: accounts))
        })
        return out
    }

    /// السجلّ بلا اسم و«معلّق» يُنشأ عند الدخول برمز الدخول — وبعد وصول قوائم الحسابات يُشترط وجوده فيها
    static func hasLogin(_ id: UUID, accounts: AdminAccountsStore) -> Bool {
        guard accounts.loaded else { return true }
        return accounts.info(id) != nil || accounts.outsideSeen[id] != nil
    }

    static func created(_ m: FamilyMember, accounts: AdminAccountsStore) -> Date? {
        accounts.info(m.id)?.created ?? m.createdAt.flatMap(DateParsing.iso)
    }
}

// MARK: - صفّ «العائلة»

/// «المكرر والأخطاء» تحت بطاقة «يحتاج مراجعتك» بشكلها نفسه (`AdminMembersReviewRow`): مربّع الرمز · العنوان · السطر ·
/// حبّة العدد · السهم
struct AdminIssuesRow: View {
    let count: Int
    let line: String
    @Environment(\.dynamicTypeSize) private var typeSize

    static var title: String { L10n.t("المكرر والأخطاء", "Duplicates & errors") }

    var body: some View {
        NavigationLink {
            AdminLazyPage {
                AnyView(AdminIssuesPage().adminBackTitle(AdminArea.family.title).adminArea(.family))
            }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "person.2.badge.gearshape")
                    .dsGlyph(DS.Glyph.lg, weight: .medium)
                    .foregroundColor(DS.Color.error)
                    .frame(width: DS.Icon.rowLarge, height: DS.Icon.rowLarge)
                    .background(RoundedRectangle(cornerRadius: DS.Hub.tileIconRadius, style: .continuous)
                        .fill(DS.Color.error.opacity(DS.Opacity.tintFill)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(Self.title)
                        .dsFont(.hubSection)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(verbatim: line)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if typeSize.isAccessibilitySize {
                        pill.padding(.top, DS.Spacing.xs)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !typeSize.isAccessibilitySize { pill }
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Hub.cardPadding)
            .padding(.vertical, DS.Spacing.smd)
            .frame(maxWidth: .infinity, minHeight: DS.Hub.familyReviewMinHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(AdminMembersFramePressStyle(radius: DS.Hub.familyReviewRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(Self.title): \(AdminNumberText.grouped(count))، \(line)"))
        .accessibilityHint(L10n.t("يفتح الأسماء المكررة ومشكلات الشجرة", "Opens duplicates and tree problems"))
        .accessibilityAddTraits(.isButton)
    }

    private var pill: some View {
        Text(verbatim: AdminNumberText.grouped(count))
            .dsFont(.badge)
            .monospacedDigit()
            .foregroundColor(DS.Color.error)
            .lineLimit(1)
            .padding(.horizontal, DS.Spacing.smd)
            .frame(minHeight: DS.Hub.familyReviewPill)
            .background(Capsule().fill(DS.Color.error.opacity(DS.Opacity.tintFill)))
            .fixedSize()
    }

    /// «أسماء مكررة · مشكلات الشجرة · أرقام بدون أسماء» — ما فيه أحد فقط
    static func line(duplicates: Int, problems: Int, nameless: Int) -> String {
        var parts: [String] = []
        if duplicates > 0 { parts.append(L10n.t("أسماء مكررة \(duplicates)", "Duplicate names \(duplicates)")) }
        if problems > 0 { parts.append(L10n.t("مشكلات الشجرة \(problems)", "Tree problems \(problems)")) }
        if nameless > 0 { parts.append(L10n.t("أرقام بدون أسماء \(nameless)", "Numbers without names \(nameless)")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - الصفحة

struct AdminIssuesPage: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    @ObservedObject private var sons = DaughterSonsIndex.shared
    @ObservedObject private var dismissed = AdminDuplicateDismissStore.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index = AdminMembersIndex.empty
    @State private var data = AdminIssuesData()
    @State private var women: [FamilyMember] = WomenStore.cache
    @State private var sheet: AdminMemberSheetContext?
    @State private var selectedWoman: FamilyMember?

    init() {}

    // حارس المكدس: الصفحة والمربّعات طبقات خلف `AnyView`
    var body: some View {
        AnyView(page)
            .debugStackProbe("AdminIssuesPage")
    }

    private var page: some View {
        AdminPage(header: header, content: AnyView(content))
            .adminArea(.family)
            .dsTallBox(item: $sheet) { context in
                AdminMemberSheet(ids: context.ids, start: context.start)
            }
            .modifier(AdminWomanDetailCover(woman: $selectedWoman, women: women, me: authVM.currentUser,
                                            canEdit: authVM.canEditMembers && authVM.adminCanEdit(.family),
                                            canDelete: authVM.canDeleteMembers && authVM.adminCanEdit(.family),
                                            canAnnounceDeath: authVM.isAdmin, canModerate: authVM.canModerate,
                                            onChanged: { await loadWomen(force: true) }))
            .refreshable { await reload(force: true) }
            .task { await reload(force: false) }
            .onChange(of: memberVM.membersVersion) { _ in rebuild() }
            .onChange(of: accounts.accounts) { _ in rebuild() }
            .onChange(of: accounts.loaded) { _ in rebuild() }
            .onChange(of: sons.ids) { _ in rebuild() }
            .onChange(of: dismissed.signatures) { _ in rebuild() }
    }

    private var seesAll: Bool { authVM.isAdmin }
    private var canEdit: Bool { authVM.canEditMembers && authVM.adminCanEdit(.family) }

    private var header: AdminPageHeader {
        AdminPageHeader(title: AdminIssuesRow.title,
                        subtitle: L10n.t("أسماء مكررة تحت الأب نفسه، ومشكلات في الشجرة، وأرقام لم تكمل التسجيل",
                                         "Same name under one father, tree problems, and numbers that didn't finish signing up"),
                        readOnly: !authVM.adminCanEdit(.family))
    }

    private func reload(force: Bool) async {
        dismissed.activate(user: authVM.currentUser?.id)
        if memberVM.allMembers.isEmpty || force { await memberVM.fetchAllMembers(force: force) }
        rebuild()
        await sons.refresh()
        await accounts.refresh(force: force)
        if seesAll { await loadWomen(force: force) }
        rebuild()
    }

    private func loadWomen(force: Bool) async {
        if !force, !women.isEmpty { return }
        do {
            women = try await WomenStore.fetch()
            rebuild()
        } catch {
            if !Log.isCancellation(error) { Log.fetchError("[AdminIssuesPage] women tree load failed", error) }
        }
    }

    private func rebuild() {
        let names = appSettingsVM
        index = AdminMembersIndex.build(members: memberVM.allMembers, accounts: accounts.accounts,
                                        accountsReady: accounts.loaded, daughterSons: sons.ids,
                                        branchName: { names.branchName(for: $0) })
        data = AdminIssuesData.make(members: memberVM.allMembers, women: women, accounts: accounts,
                                    dismissed: dismissed.signatures, seesAll: seesAll)
    }

    // MARK: المحتوى

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Hub.sectionGap) {
            if memberVM.membersLoadFailed && memberVM.allMembers.isEmpty {
                AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                                          message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                          retry: { Task { await reload(force: true) } }))
            } else if !index.built {
                AdminPageStateCard(.loading(L10n.t("جارٍ تحميل القوائم…", "Loading the lists…"), rows: 5))
            } else {
                AnyView(duplicatesSection)
                AnyView(problemsSection)
                if seesAll { AnyView(namelessSection) }
            }
        }
    }

    // MARK: ١) أسماء مكررة

    private var duplicatesSection: some View {
        let groups = data.men.map { ($0, false) } + data.women.map { ($0, true) }
        return VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: L10n.t("أسماء مكررة", "Duplicate names"),
                              trailing: groups.isEmpty ? nil : AdminNumberText.grouped(groups.count))
            if groups.isEmpty {
                emptyLine(L10n.t("لا أسماء مكررة تحت أب واحد", "No repeated names under one father"))
            } else {
                ForEach(groups, id: \.0.id) { group, inWomen in
                    AnyView(groupCard(group, inWomen: inWomen))
                }
            }
            footnote(L10n.t("«ليسا مكرّرين» يخفي المجموعة عندك أنت فقط، وتعود إن أُضيف شخص ثالث بالاسم نفسه.",
                            "«Not duplicates» hides the group on your device only; it returns if a third person with the name is added."))
            if !dismissed.signatures.isEmpty {
                Button {
                    dismissed.reset()
                } label: {
                    Text(L10n.t("إعادة إظهار ما أخفيته", "Show hidden groups again"))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.primary)
                        .frame(minHeight: DS.Icon.tapTarget)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func groupCard(_ group: AdminDuplicateNames.Group, inWomen: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(verbatim: group.name)
                        .dsFont(.hubSection)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(verbatim: fatherLine(group.parent, inWomen: inWomen))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if inWomen {
                    AdminMemberTagPill(tag: AdminMemberTag(text: L10n.t("شجرة النساء", "Women's tree"), tone: .daughterSon))
                }
            }
            .padding(.bottom, DS.Spacing.sm)
            ForEach(Array(group.ids.enumerated()), id: \.element) { n, id in
                AdminRowDivider(inset: 0)
                AnyView(personRow(id, number: n + 1, in: group, inWomen: inWomen))
            }
            AdminRowDivider(inset: 0)
            HStack {
                Spacer(minLength: 0)
                AdminPillButton(title: L10n.t("ليسا مكرّرين", "Not duplicates"), icon: "checkmark", style: .soft,
                                height: DS.Hub.pillHeightCard) {
                    withAnimation(reduceMotion ? nil : DS.Anim.snappy) { dismissed.dismiss(group.signature) }
                }
                .accessibilityHint(L10n.t("يخفي هذه المجموعة عندك أنت فقط", "Hides this group on your device only"))
            }
            .padding(.top, DS.Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private func personRow(_ id: UUID, number: Int, in group: AdminDuplicateNames.Group, inWomen: Bool) -> some View {
        let person = inWomen ? women.first { $0.id == id } : memberVM.member(byId: id)
        let tags = person.map { chips($0, inWomen: inWomen) } ?? []
        return Button {
            open(id, in: group, inWomen: inWomen)
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Text(verbatim: AdminNumberText.grouped(number))
                    .dsFont(.badge)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textSecondary)
                    .frame(width: DS.Icon.row, height: DS.Icon.row)
                    .background(Circle().fill(DS.Color.textTertiary.opacity(DS.Opacity.tintFill)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(verbatim: person?.fullName.isEmpty == false ? person!.fullName : group.name)
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                        .dsNameLines()
                    if tags.isEmpty {
                        Text(L10n.t("بلا تاريخ ميلاد ولا حساب", "No birth date and no account"))
                            .dsFont(.subtitle)
                            .foregroundColor(DS.Color.textTertiary)
                    } else {
                        DSChipFlow(spacing: DS.Spacing.xs, lineSpacing: DS.Spacing.xs) {
                            ForEach(tags, id: \.text) { AdminMemberTagPill(tag: $0) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                DSChevron()
            }
            .padding(.vertical, DS.Spacing.smd)
            .frame(minHeight: DS.Hub.rowMinHeightTwoLines)
            .contentShape(Rectangle())
        }
        .buttonStyle(AdminRowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.t("يفتح بيانات العضو", "Opens the member details"))
    }

    /// سنة الميلاد · «له حساب» · «متوفى» — ما يفرّق بين الاثنين
    private func chips(_ m: FamilyMember, inWomen: Bool) -> [AdminMemberTag] {
        var out: [AdminMemberTag] = []
        if let raw = m.birthDate, raw.count >= 4, let year = Int(raw.prefix(4)), year > 1000 {
            out.append(AdminMemberTag(text: L10n.t("مواليد \(year)", "Born \(year)")))
        }
        let account = inWomen ? WomenStore.linkedUserByWoman[m.id] != nil
                              : (accounts.info(m.id) != nil || m.status == .frozen)
        if account { out.append(AdminMemberTag(text: L10n.t("له حساب", "Has an account"), tone: .family)) }
        if m.isDeceased == true { out.append(AdminMemberTag(text: L10n.t("متوفى", "Deceased"))) }
        return out
    }

    /// «أبناء فلان» — الأب من الشجرة نفسها (شجرة النساء: عقدتها أو ملفه)
    private func fatherLine(_ parent: UUID, inWomen: Bool) -> String {
        let father = (inWomen ? women.first { $0.id == parent } : nil) ?? memberVM.member(byId: parent)
        guard let father else { return L10n.t("الأب غير معروف", "Unknown father") }
        let name = father.shortFullName.isEmpty ? father.fullName : father.shortFullName
        return L10n.t("أبناء \(name)", "Children of \(name)")
    }

    private func open(_ id: UUID, in group: AdminDuplicateNames.Group, inWomen: Bool) {
        if inWomen {
            selectedWoman = women.first { $0.id == id }
        } else {
            sheet = AdminMemberSheetContext(ids: group.ids, start: group.ids.firstIndex(of: id) ?? 0)
        }
    }

    // MARK: ٢) مشكلات الشجرة

    private var problemsSection: some View {
        let counts = AdminMemberProblem.allCases.map { p in (p, index.rows(.problems, AdminMemberSub(rawValue: p.rawValue) ?? .all).count) }
        let busy = counts.filter { $0.1 > 0 }
        let total = index.rows(.problems, .all).count
        return VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: L10n.t("مشكلات الشجرة", "Tree problems"),
                              trailing: total > 0 ? AdminNumberText.grouped(total) : nil)
            if busy.isEmpty {
                emptyLine(L10n.t("لا مشكلات في الشجرة", "No tree problems"))
            } else {
                AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                    ForEach(busy, id: \.0) { problem, n in
                        let face = AdminListRow(icon: problem.icon, tint: DS.Color.error, title: problem.title,
                                                subtitle: problem.fixTitle) {
                            AdminRowValue(text: AdminNumberText.grouped(n))
                        }
                        AdminTapWrap(tap: .page {
                                        AnyView(AdminReviewListPage(review: .problems, branchSet: nil, start: .problem(problem)))
                                     },
                                     feel: .row, label: AnyView(face),
                                     accessibilityLabel: "\(problem.title): \(AdminNumberText.grouped(n))")
                    }
                }
            }
        }
    }

    // MARK: ٣) أرقام بدون أسماء

    private var namelessSection: some View {
        let rows = data.nameless.compactMap { memberVM.member(byId: $0) }
        return VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: L10n.t("أرقام بدون أسماء", "Numbers without names"),
                              trailing: rows.isEmpty ? nil : AdminNumberText.grouped(rows.count))
            if rows.isEmpty {
                emptyLine(L10n.t("لا أرقام بدون أسماء", "No numbers without names"))
            } else {
                AdminRowsCard(dividerInset: 0) {
                    ForEach(rows) { m in
                        AnyView(namelessRow(m))
                    }
                }
            }
            footnote(L10n.t("دخلوا برمز الدخول ولم يكملوا نموذج التسجيل. تُحذف تلقائياً بعد 30 يوماً إن لم يُستكمل التسجيل.",
                            "They entered the login code but never filled the sign-up form. Removed automatically after 30 days if not completed."))
        }
    }

    private func namelessRow(_ m: FamilyMember) -> some View {
        let line = AdminDuplicateNames.registeredLine(AdminIssuesData.created(m, accounts: accounts))
        let usage = accounts.info(m.id)?.usage
        let push = usage == .active || usage == .idle
        return HStack(spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(verbatim: KuwaitPhone.display(m.phoneNumber))
                    .dsFont(.hubRow)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textPrimary)
                    .environment(\.layoutDirection, .leftToRight)
                    .textSelection(.enabled)
                HStack(spacing: DS.Spacing.sm) {
                    if let line {
                        Text(verbatim: line)
                            .dsFont(.subtitle)
                            .monospacedDigit()
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    if push {
                        AdminMemberTagPill(tag: AdminMemberTag(text: L10n.t("الإشعارات مفعّلة", "Notifications on"), tone: .family))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DS.Spacing.xs) {
                if let tel = KuwaitPhone.telURL(m.phoneNumber) {
                    AdminReviewCircleButton(symbol: "phone.fill", tint: DS.Color.sea,
                                            label: L10n.t("اتصال", "Call")) { openURL(tel) }
                }
                if let wa = KuwaitPhone.whatsappURL(m.phoneNumber) {
                    AdminReviewCircleButton(symbol: "message.fill", tint: DS.Color.success,
                                            label: L10n.t("واتساب", "WhatsApp")) { openURL(wa) }
                }
            }
        }
        .padding(.vertical, DS.Spacing.smd)
        .frame(minHeight: DS.Hub.rowMinHeightTwoLines)
    }

    // MARK: قطع صغيرة

    private func emptyLine(_ text: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .dsGlyph(DS.Glyph.md, weight: .medium)
                .foregroundColor(DS.Color.success)
                .accessibilityHidden(true)
            Text(text)
                .dsFont(.body)
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: DS.Hub.rowMinHeight, alignment: .leading)
        .adminCard()
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .dsFont(.subtitle)
            .foregroundColor(DS.Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.Spacing.xxs)
    }
}
