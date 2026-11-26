import Foundation
#if !ADMIN_LOGIC_TEST
import SwiftUI
import Supabase
#endif

// MARK: - «رسائل الأعضاء» (إعادة تصميم الإدارة ٢٠٢٦-١١-٢٦، الوحدة U10 — spec C.4)
//
// صفحة مستقلة تُدفع من صفّ «رسائل الأعضاء» في «الوارد» (لم تعد شريحة داخله): رأس الصفحات الداخلية (`AdminPage`) —
// «‹ الوارد» · «رسائل الأعضاء» · «تحديد» نصّاً في الطرف · سطر الأرقام «7 غير مقروءة ‹» «2 بانتظار الرد ‹» (كل رقم يضبط
// فلتر «الحالة» فيكون أول رقم تحت الشريط هو نفسه) ← شريط الفلاتر (البحث + «الفلاتر»: «الحالة» و«النوع» في الورقة،
// الشرائح المفعّلة تحته) ← «● 7 رسائل جديدة … تحديد الكل كمقروء» ← الأيام (اليوم · أمس · التاريخ)، كل يوم بطاقة من
// صفوفها (`DSNoticeKit`). السحب: «مقروء» و«تمّت المعالجة» من البداية، «حذف» من الطرف (يسأل أولاً)؛ والضغط المطوّل
// القائمة نفسها؛ و«تحديد» ← شريط سفلي «تحديد الكل · N محدّدة · حذف».
// المربّع: المرسل · الرسالة · «الرد على العضو» (واتساب / اتصال / بريد) · «تمّت المعالجة» · «إغلاق» · حذف (يسأل أولاً).
//
// الصلاحية: `inbox.messages` في جدول السيرفر (المالك والمدير). غيرهما يصل الصفحة (رابط قديم) فيرى الرأس وبطاقة «ليست ضمن
// صلاحياتك» بلا جلب. «يعدّل» (`adminCanEdit`) شرط الحذف و«تمّت المعالجة» و«تحديد»؛ «مقروء» حال شخصية لكل مشرف.
// الحالات (spec A.12/T5): هيكل صفوف · «لا رسائل» · «لا رسائل بهذه الفلاتر» + «مسح الفلاتر» · خطأ + «أعد المحاولة» (والرسائل
// القديمة تبقى بـ«آخر تحديث»). الكتابة كلها تمرّ بـ`DebugAdminProbe.dryRun` (T0) — بنجاح مصطنع أثناء تجربة دور.
//
// الجزء الأول منطق خالص (Foundation) يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u10-logic FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminInboxView.swift tests/admin-redesign/U10/main.swift && /tmp/u10-logic

// MARK: - المنطق الخالص

nonisolated enum AdminInboxMessageLogic {
    /// «الكل» في مجموعة «النوع»
    static let allKinds = "*"

    /// مجموعة «الحالة» في ورقة الفلاتر — اختيار واحد. «تمّت المعالجة» باقية من فلتر الصفحة القديم (لا يضيع عرض المعالَج)
    enum Status: String, CaseIterable, Hashable {
        case all, unread, awaiting, today, handled

        var title: String {
            switch self {
            case .all:      return L10n.t("الكل", "All")
            case .unread:   return L10n.t("غير مقروءة", "Unread")
            case .awaiting: return L10n.t("بانتظار الرد", "Awaiting reply")
            case .today:    return L10n.t("جديد اليوم", "New today")
            case .handled:  return L10n.t("تمّت المعالجة", "Handled")
            }
        }
    }

    /// حالة فلاتر الصفحة — «مسح الفلاتر» يرجع إلى `Filters()`
    struct Filters: Equatable {
        var status: Status = .all
        var kind: String = AdminInboxMessageLogic.allKinds
    }

    /// ما يحتاجه الفلتر من الرسالة (يُحسب مرة لكل رسم)
    struct Fact: Equatable {
        var unread: Bool
        /// بانتظار الرد (`status == pending`)
        var pending: Bool
        /// تمّت المعالجة (`status == approved`)
        var handled: Bool
        var today: Bool
        /// اسم النوع المعروض («استفسار»…) — `ContactCategoryInfo.title`
        var kind: String
    }

    static func matches(_ fact: Fact, status: Status) -> Bool {
        switch status {
        case .all:      return true
        case .unread:   return fact.unread
        case .awaiting: return fact.pending
        case .today:    return fact.today
        case .handled:  return fact.handled
        }
    }

    static func matches(_ fact: Fact, _ filters: Filters) -> Bool {
        matches(fact, status: filters.status) && (filters.kind == allKinds || fact.kind == filters.kind)
    }

    static func count(_ facts: [Fact], _ filters: Filters) -> Int {
        facts.reduce(0) { $0 + (matches($1, filters) ? 1 : 0) }
    }

    /// صفوف «النوع» في الورقة: الأربعة الثابتة دائماً (الصفر رمادي ويبقى قابلاً للاختيار — spec A.13)، ثم أي نوع آخر
    /// موجود في الرسائل («اعتراض»، نوع قديم) — الأكثر أولاً، والتعادل بترتيب الظهور
    static func kindOrder(fixed: [String], facts: [Fact]) -> [String] {
        var counts: [String: Int] = [:]
        var seen: [String] = []
        for fact in facts where !fixed.contains(fact.kind) {
            if counts[fact.kind] == nil { seen.append(fact.kind) }
            counts[fact.kind, default: 0] += 1
        }
        let extras = seen.enumerated()
            .sorted { lhs, rhs in
                let a = counts[lhs.element] ?? 0, b = counts[rhs.element] ?? 0
                return a != b ? a > b : lhs.offset < rhs.offset
            }
            .map(\.element)
        return fixed + extras
    }

    /// المعدود بعد الرقم («12 رسالة»): ١ رسالة، ٢ رسالتان، ٣–١٠ رسائل، ١١–٩٩ رسالة، وغيرها مفرد
    static func noun(_ n: Int) -> String {
        L10n.t(arabicNoun(n, one: "رسالة", two: "رسالتان", few: "رسائل", many: "رسالة"), n == 1 ? "message" : "messages")
    }

    static func arabicNoun(_ n: Int, one: String, two: String, few: String, many: String) -> String {
        if n == 1 { return one }
        if n == 2 { return two }
        switch n % 100 {
        case 3...10:  return few
        case 11...99: return many
        default:      return one
        }
    }

    /// «● 7 رسائل جديدة» — المفرد والمثنى بلا رقم كما كان («رسالة جديدة»، «رسالتان جديدتان»)
    static func newPhrase(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "1 new message" : "\(n) new messages" }
        if n == 1 { return "رسالة جديدة" }
        if n == 2 { return "رسالتان جديدتان" }
        switch n % 100 {
        case 3...10: return "\(n) رسائل جديدة"
        default:     return "\(n) رسالة جديدة"
        }
    }

    /// سؤال الحذف الجماعي (spec A.14: السؤال بالفعل)
    static func deleteQuestion(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "Delete 1 message?" : "Delete \(n) messages?" }
        if n == 1 { return "حذف الرسالة؟" }
        if n == 2 { return "حذف الرسالتين؟" }
        return "حذف \(n) \(arabicNoun(n, one: "رسالة", two: "رسالتان", few: "رسائل", many: "رسالة"))؟"
    }
}

#if !ADMIN_LOGIC_TEST

// MARK: - الصفحة

struct AdminInboxView: View {
    private typealias Logic = AdminInboxMessageLogic

    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var authVM: AuthViewModel

    /// قديم: داخل «الوارد» شريحةً بلا رأس — U8 يدفع الصفحة بدلها، وU21 يحذفه
    private let embedded: Bool
    /// قديم: بحث «الوارد» الواحد للطلبات والرسائل — nil = بحث الصفحة
    private let sharedSearch: Binding<String>?

    init() {
        embedded = false
        sharedSearch = nil
    }

    @available(*, deprecated, message: "push AdminInboxView() as its own page; U8 drops this call, U21 removes")
    init(embedded: Bool, sharedSearch: Binding<String>? = nil) {
        self.embedded = embedded
        self.sharedSearch = sharedSearch
    }

    /// تلميح حقل البحث الواحد في «الوارد» (الطلبات والرسائل) — يقرؤه «الوارد» أيضاً
    static let searchPlaceholder = L10n.t("بحث في الطلبات والرسائل بالاسم أو الرقم", "Search requests and messages by name or number")

    static var title: String { L10n.t("رسائل الأعضاء", "Members' messages") }

    @State private var ownSearch = ""
    @State private var filters = AdminInboxMessageLogic.Filters()
    @State private var showsFilters = false
    /// حال جلب الرسائل (عقد U2): هيكل ← الكلمة، والفشل بعد تحميل ناجح يُبقي الرسائل بـ«آخر تحديث»
    @State private var health: AdminStoreHealth = .idle
    @State private var selectedMessage: AdminRequest?
    @State private var isSelectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    /// رسالة طُلب حذفها (سحب، ضغط مطوّل، أو من مربّعها) — تأكيد قبل الحذف
    @State private var messageToDelete: AdminRequest?
    /// «ظهور موحّد»: الأيام تصعد مرة عند الظهور الأول (لا عند التحديث)
    @State private var appeared = false
    /// DRY-RUN (T0): «مقروء» مصطنع محلياً — لا يُرسل للسيرفر
    @State private var dryReadIds: Set<UUID> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.adminBackTitle) private var outerBack

    private var searchBinding: Binding<String> { sharedSearch ?? $ownSearch }
    private var trimmedSearch: String { searchBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: الصلاحية

    /// الصفحة لمن يرى «الرسائل» في جدول السيرفر (المالك والمدير)
    private var canSee: Bool { authVM.adminSees(.inboxMessages) }
    /// الحذف و«تمّت المعالجة» و«تحديد»: «يعدّل» في الجدول للخانة وللقسم (Autoplan note 7)
    private var canEdit: Bool { canSee && authVM.adminCanEdit(.inboxMessages) && authVM.adminCanEdit(.inbox) }

    // MARK: Body

    // حارس المكدس: الصفحة ثم التأكيدات والمربّع طبقات خلف `AnyView`
    var body: some View {
        if embedded {
            AnyView(layered)
        } else {
            AnyView(layered)
                .debugStackProbe("AdminInboxView", limitKB: DebugStackLimit.page)
        }
    }

    private var layered: AnyView {
        guard canSee else { return embedded ? AnyView(lockedCard) : AnyView(lockedPage) }
        let model = makeModel()
        let page = embedded ? AnyView(embeddedList(model)) : AnyView(pageView(model))
        return AnyView(dialogsLayer(page))
    }

    private func pageView(_ m: Model) -> some View {
        AdminPage(header: header(m), lead: lead(m), layout: .list, content: AnyView(rows(m)),
                  updatedAt: health.lastGood)
            .refreshable { await reload(force: true) }
            // شريط التحديد السفلي — مثبّت، وآخر رسالة تبقى فوقه
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelectMode {
                    selectionBar(m)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .adminFilterSheet(isPresented: $showsFilters, set: m.set, selection: $filters)
    }

    /// تأكيدا الحذف، والتحميل الأول، ومربّع تفاصيل الرسالة
    private func dialogsLayer(_ content: AnyView) -> some View {
        let pendingName = messageToDelete?.member?.displayFullName
        return content
            .dsAlert(Logic.deleteQuestion(selectedIDs.count), isPresented: $showDeleteConfirm, icon: "trash.fill") {
                Button(L10n.t("احذف", "Delete"), role: .destructive) {
                    Task { await deleteSelected() }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.t("تُحذف الرسائل المحدّدة من الوارد. لا يمكن التراجع.",
                            "The selected messages are removed from the inbox. This can't be undone."))
            }
            .dsAlert(Logic.deleteQuestion(1), isPresented: Binding(
                get: { messageToDelete != nil },
                set: { if !$0 { messageToDelete = nil } }
            ), icon: "trash.fill") {
                Button(L10n.t("احذف الرسالة", "Delete message"), role: .destructive) {
                    if let msg = messageToDelete {
                        Task { await delete([msg.id]) }
                    }
                    messageToDelete = nil
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { messageToDelete = nil }
            } message: {
                if let pendingName, !pendingName.isEmpty {
                    Text(L10n.t("تُحذف رسالة \(pendingName). لا يمكن التراجع.",
                                "\(pendingName)'s message is removed. This can't be undone."))
                } else {
                    Text(L10n.t("لا يمكن التراجع.", "This can't be undone."))
                }
            }
            .task {
                appeared = true
                await reload(force: false)
            }
            .dsCenterBox(item: $selectedMessage) { msg in
                MessageDetailSheet(message: msg,
                                   canEdit: canEdit,
                                   markRead: { markRead(msg.id) },
                                   markHandled: { await markHandled(msg) },
                                   onDelete: {
                                       selectedMessage = nil
                                       messageToDelete = msg
                                   },
                                   onDismiss: { selectedMessage = nil })
            }
    }

    // MARK: البيانات

    private struct Entry: Identifiable {
        let msg: AdminRequest
        let info: ContactCategoryInfo
        let fact: AdminInboxMessageLogic.Fact
        let date: Date?
        var id: UUID { msg.id }
    }

    /// كل ما يرسمه الرسم الواحد — يُحسب مرة
    private struct Model {
        /// كل الرسائل، الأحدث أولاً
        let all: [Entry]
        /// بعد البحث وقبل الفلاتر (منها أعداد الورقة)
        let searched: [Entry]
        /// بعد الفلاتر — القائمة
        let visible: [Entry]
        let set: AdminFilterSet<AdminInboxMessageLogic.Filters>
        /// وصلت رسائل (هذا الجلب أو قبله) — قبلها «—» لا أصفار
        let ready: Bool
        let unread: Int
        let awaiting: Int
    }

    private func makeModel() -> Model {
        let read = adminRequestVM.readContactMessageIds.union(dryReadIds)
        let calendar = Calendar.current
        let all = adminRequestVM.contactMessages
            .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            .map { msg -> Entry in
                let info = ContactCategoryInfo.from(raw: ContactParser.category(of: msg))
                let date = ContactParser.date(msg.createdAt)
                let fact = Logic.Fact(unread: !read.contains(msg.id),
                                      pending: msg.status == ApprovalStatus.pending.rawValue,
                                      handled: msg.status == ApprovalStatus.approved.rawValue,
                                      today: date.map { calendar.isDateInToday($0) } ?? false,
                                      kind: info.title)
                return Entry(msg: msg, info: info, fact: fact, date: date)
            }
        let searched = Self.search(all, trimmedSearch)
        let ready = health.hasData || !all.isEmpty
        let current = filters
        return Model(all: all,
                     searched: searched,
                     visible: searched.filter { Logic.matches($0.fact, current) },
                     set: Self.filterSet(facts: searched.map(\.fact), ready: ready),
                     ready: ready,
                     unread: all.reduce(0) { $0 + ($1.fact.unread ? 1 : 0) },
                     awaiting: all.reduce(0) { $0 + ($1.fact.pending ? 1 : 0) })
    }

    /// نفس مطابقة بحث الطلبات (`NameSearch`): كل كلمة بداية كلمة بالترتيب في الاسم أو النص، أو الرقم (أرقاماً فقط)
    private static func search(_ entries: [Entry], _ query: String) -> [Entry] {
        guard !query.isEmpty else { return entries }
        if NameSearch.isPhoneQuery(query) {
            return entries.filter { NameSearch.phoneMatches(query: query, phone: $0.msg.member?.phoneNumber) }
        }
        return entries.filter { entry in
            NameSearch.matches(query: query, any: [entry.msg.member?.fullName ?? "", ContactParser.message(from: entry.msg)])
        }
    }

    /// ورقة «الفلاتر»: «الحالة» و«النوع» بأعدادهما لأي حالة (بعد البحث)، و«النتيجة الآن» = القائمة نفسها
    private static func filterSet(facts: [AdminInboxMessageLogic.Fact],
                                  ready: Bool) -> AdminFilterSet<AdminInboxMessageLogic.Filters> {
        typealias L = AdminInboxMessageLogic
        let fixed = ["استفسار", "اقتراح", "شكوى", "أخرى"].map { ContactCategoryInfo.from(raw: $0).title }
        let kinds = L.kindOrder(fixed: fixed, facts: facts)
        let count: (L.Filters) -> Int? = { ready ? L.count(facts, $0) : nil }
        return AdminFilterSet(reset: L.Filters(), noun: L.noun, resultCount: count) { s in
            let statuses = L.Status.allCases.map { status -> AdminFilterOption<L.Status> in
                AdminFilterOption(status, status.title, count: count(L.Filters(status: status, kind: s.kind)))
            }
            let kindOptions = [AdminFilterOption(L.allKinds, L10n.t("الكل", "All"),
                                                 count: count(L.Filters(status: s.status, kind: L.allKinds)))]
                + kinds.map { kind in
                    AdminFilterOption(kind, kind, count: count(L.Filters(status: s.status, kind: kind)))
                }
            let groups: [AdminFilterGroup<L.Filters>] = [
                .choices("status", title: L10n.t("الحالة", "Status"), value: \.status, all: .all, options: statuses),
                .choices("kind", title: L10n.t("النوع", "Type"), value: \.kind, all: L.allKinds, options: kindOptions),
            ]
            return groups
        }
    }

    // MARK: الرأس

    private var backTitle: String? { outerBack == nil ? L10n.t("الوارد", "Inbox") : nil }

    /// «‹ الوارد» · «رسائل الأعضاء» · «تحديد» · سطر الأرقام «7 غير مقروءة ‹» «2 بانتظار الرد ‹»
    private func header(_ m: Model) -> AdminPageHeader {
        var actions: [AdminPageAction] = []
        if canEdit && !m.all.isEmpty {
            actions.append(AdminPageAction(symbol: "checkmark.circle",
                                           label: isSelectMode ? L10n.t("إلغاء", "Cancel") : L10n.t("تحديد", "Select"),
                                           tap: .action { toggleSelectMode() },
                                           textOnly: true))
        }
        // الأرقام من الرسائل الموجودة ولو فشل التحديث (بـ«آخر تحديث»)؛ «—» وإعادة المحاولة فقط حين لا رسالة في اليد
        let itemHealth: AdminStoreHealth?
        if adminRequestVM.contactMessages.isEmpty {
            itemHealth = health
        } else if case .failed(let lastGood?) = health {
            itemHealth = .failed(lastGood: lastGood)
        } else {
            itemHealth = nil
        }
        let retry: () -> Void = { Task { await reload(force: true) } }
        let items = [
            AdminHeaderItem(id: "unread", value: m.ready ? m.unread : nil, label: L10n.t("غير مقروءة", "unread"),
                            health: itemHealth, tap: .action { land(.unread) }, retry: retry),
            AdminHeaderItem(id: "awaiting", value: m.ready ? m.awaiting : nil,
                            label: L10n.t("بانتظار الرد", "awaiting reply"),
                            health: itemHealth, tap: .action { land(.awaiting) }, retry: retry),
        ]
        return AdminPageHeader(back: backTitle, title: Self.title, readOnly: !canEdit, items: items, actions: actions)
    }

    /// رقم الرأس يفتح قائمته: «الحالة» وحدها وبلا بحث — فأول رقم تحت الشريط = الرقم المضغوط (T2)
    private func land(_ status: AdminInboxMessageLogic.Status) {
        withAnimation(reduceMotion ? nil : DS.Anim.snappy) {
            filters = Logic.Filters(status: status)
            searchBinding.wrappedValue = ""
        }
    }

    // MARK: فوق القائمة

    /// شريط الفلاتر (والملخّص حين يُفلتر) ← «● 7 رسائل جديدة … تحديد الكل كمقروء»
    private func lead(_ m: Model) -> AnyView? {
        let bar = showsFilterBar(m)
        let unreadLine = m.ready && m.unread > 0 && !isSelectMode
        guard bar || unreadLine else { return nil }
        return AnyView(VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            if bar {
                AdminFilterPanel(set: m.set, selection: $filters, search: searchBinding,
                                 placeholder: sharedSearch == nil ? AdminFilterText.searchPlaceholder : Self.searchPlaceholder,
                                 note: L10n.t("الأحدث أولاً", "Newest first"),
                                 showsCaption: filters != Logic.Filters() || !trimmedSearch.isEmpty,
                                 openFilters: { showsFilters = true })
            }
            if unreadLine {
                unreadRow(m.unread)
            }
        })
    }

    /// الشريط مع التحميل (يمسك المكان) ومع وجود رسائل — لا شريط فوق «لا رسائل» ولا فوق خطأ بلا رسائل
    private func showsFilterBar(_ m: Model) -> Bool {
        if m.ready { return !m.all.isEmpty }
        return !health.canRetry
    }

    /// «● 7 رسائل جديدة» في البداية و«تحديد الكل كمقروء» (نصّ كحلي، لمس ٤٤) في الطرف — تحتها إن ضاق السطر
    private func unreadRow(_ unread: Int) -> some View {
        let label = HStack(spacing: DS.Spacing.sm) {
            DSGoldDot(size: DSNoticeMetrics.unreadDot)
            Text(verbatim: Logic.newPhrase(unread))
                .dsFont(.subtitle)
                .monospacedDigit()
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        let button = Button(action: markAllRead) {
            Text(L10n.t("تحديد الكل كمقروء", "Mark all read"))
                .dsFont(.button)
                .foregroundColor(AppSection.admin.ink)
                .multilineTextAlignment(.leading)
                .frame(minHeight: DS.Icon.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.sm) {
                label
                Spacer(minLength: DS.Spacing.sm)
                button.fixedSize()
            }
            VStack(alignment: .leading, spacing: 0) {
                label.frame(minHeight: DS.Icon.tapTarget)
                button
            }
        }
        .frame(minHeight: DS.Icon.tapTarget)
    }

    // MARK: القائمة

    /// صفوف `List`: الحالة (هيكل/فارغ/خطأ) أو الأيام — كل يوم عنوانه ثم صفوفه، وكل صفّ جزء من بطاقة يومه
    @ViewBuilder
    private func rows(_ m: Model) -> some View {
        if !m.ready {
            if health.canRetry {
                AnyView(AdminPageStateCard(.error(L10n.t("تعذّر تحميل الرسائل", "Couldn't load messages"),
                                                  message: L10n.t("تحقّق من اتصالك ثم أعد المحاولة.",
                                                                  "Check your connection, then try again."),
                                                  retry: { Task { await reload(force: true) } })))
                    .adminPageRow(top: DS.Spacing.xs)
            } else {
                AnyView(DSCardSkeleton(style: .notice, count: 5,
                                       label: L10n.t("جارٍ تحميل الرسائل…", "Loading messages…")))
                    .adminPageRow(top: DS.Hub.stackSpacing)
            }
        } else if m.all.isEmpty {
            AnyView(AdminPageStateCard(.empty(L10n.t("لا رسائل", "No messages"),
                                              message: L10n.t("عندما يكتب عضو للإدارة تظهر رسالته هنا.",
                                                              "When a member writes to the admins, it shows here."))))
                .adminPageRow(top: DS.Spacing.xs)
        } else {
            if health.canRetry {
                // التحديث فشل والرسائل القديمة باقية تحته
                AnyView(AdminPageStateCard(.error(L10n.t("تعذّر تحديث الرسائل", "Couldn't refresh messages"),
                                                  message: L10n.t("تعرض آخر رسائل وصلت.", "Showing the last messages received."),
                                                  retry: { Task { await reload(force: true) } },
                                                  lastGood: health.lastGood)))
                    .adminPageRow(top: DS.Spacing.xs)
            }
            if m.visible.isEmpty {
                AnyView(filteredEmpty)
                    .adminPageRow(top: DS.Spacing.xs)
            } else {
                ForEach(DSDayBuckets.group(m.visible) { $0.date ?? .distantPast }) { day in
                    DSDayHeader(title: day.title, count: day.items.count)
                        .dsCardCascade(1, appeared: appeared)
                        .adminPageRow(top: DS.Hub.stackSpacing, bottom: DSNoticeMetrics.headerGap)
                    ForEach(Array(day.items.enumerated()), id: \.element.id) { index, entry in
                        messageCell(entry, position: DSGroupPosition(index: index, count: day.items.count))
                    }
                }
            }
        }
    }

    /// فلاتر بلا نتيجة: «لا رسائل بهذه الفلاتر» + «مسح الفلاتر»؛ بحث بلا نتيجة: «لا نتائج» + «مسح البحث»
    private var filteredEmpty: some View {
        Group {
            if filters != Logic.Filters() {
                AdminFilterEmptyCard(title: L10n.t("لا رسائل بهذه الفلاتر", "No messages with these filters")) {
                    withAnimation(reduceMotion ? nil : DS.Anim.snappy) { filters = Logic.Filters() }
                }
            } else {
                AdminPageStateCard(.empty(L10n.t("لا نتائج", "No results"),
                                          message: L10n.t("جرّب كلمة أخرى", "Try another word"),
                                          actionTitle: L10n.t("مسح البحث", "Clear search"),
                                          action: { searchBinding.wrappedValue = "" }))
            }
        }
    }

    // MARK: الصفّ

    /// إجراءات الرسالة — السحب والضغط المطوّل والقارئ الصوتي نفسها (spec A.15)
    private enum RowAction: Hashable {
        case read, handled, delete

        var title: String {
            switch self {
            case .read:    return L10n.t("مقروء", "Read")
            case .handled: return L10n.t("تمّت المعالجة", "Handled")
            case .delete:  return L10n.t("حذف", "Delete")
            }
        }
        var icon: String {
            switch self {
            case .read:    return "envelope.open.fill"
            case .handled: return "checkmark.circle.fill"
            case .delete:  return "trash.fill"
            }
        }
    }

    private func actions(for entry: Entry) -> [RowAction] {
        var list: [RowAction] = []
        if entry.fact.unread { list.append(.read) }
        if entry.fact.pending && canEdit { list.append(.handled) }
        if canEdit { list.append(.delete) }
        return list
    }

    private func perform(_ action: RowAction, _ entry: Entry) {
        switch action {
        case .read:    withAnimation(DS.Anim.quick) { markRead(entry.id) }
        case .handled: Task { await markHandled(entry.msg) }
        case .delete:  messageToDelete = entry.msg
        }
    }

    /// الخلية: الضغط يفتح المربّع (أو يحدّد في وضع التحديد)، السحب «مقروء»/«تمّت المعالجة» من البداية و«حذف» من الطرف
    /// (يسأل أولاً فلا يُسحب للآخر)، والضغط المطوّل القائمة نفسها
    private func messageCell(_ entry: Entry, position: DSGroupPosition) -> some View {
        let picked = selectedIDs.contains(entry.id)
        let list = isSelectMode ? [] : actions(for: entry)
        let whatsapp = Self.replyPhone(entry.msg).flatMap { KuwaitPhone.whatsappURL($0) }
        return AnyView(messageRow(entry, picked: picked, position: position))
            .contentShape(Rectangle())
            .onTapGesture { tap(entry) }
            .accessibilityElement(children: .combine)
            .accessibilityValue(entry.fact.unread ? L10n.t("جديدة", "New") : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isSelectMode && picked ? .isSelected : [])
            .accessibilityActions {
                ForEach(list, id: \.self) { action in
                    Button(action.title) { perform(action, entry) }
                }
                if let whatsapp, !isSelectMode {
                    Button(L10n.t("مراسلة عبر واتساب", "Message on WhatsApp")) { UIApplication.shared.open(whatsapp) }
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if list.contains(.delete) {
                    Button { perform(.delete, entry) } label: {
                        Label(RowAction.delete.title, systemImage: RowAction.delete.icon)
                    }
                    .tint(DS.Color.errorFill)
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if list.contains(.read) {
                    Button { perform(.read, entry) } label: {
                        Label(RowAction.read.title, systemImage: RowAction.read.icon)
                    }
                    .tint(DS.Color.primaryFill)
                }
                if list.contains(.handled) {
                    Button { perform(.handled, entry) } label: {
                        Label(RowAction.handled.title, systemImage: RowAction.handled.icon)
                    }
                    .tint(DS.Color.successFill)
                }
            }
            .contextMenu {
                ForEach(list, id: \.self) { action in
                    Button(role: action == .delete ? .destructive : nil) {
                        perform(action, entry)
                    } label: {
                        Label(action.title, systemImage: action.icon)
                    }
                }
            }
            .dsCardCascade(1, appeared: appeared)
            .adminPageRow(top: 0, bottom: 0)
    }

    private func tap(_ entry: Entry) {
        if isSelectMode {
            withAnimation(DS.Anim.quick) {
                if selectedIDs.contains(entry.id) { selectedIDs.remove(entry.id) } else { selectedIDs.insert(entry.id) }
            }
            return
        }
        markRead(entry.id)
        selectedMessage = entry.msg
    }

    /// صفّ مختصر (`DSNoticeRow`): صورة المرسل وعلى ركنها أيقونة النوع ·
    /// الاسم (سطران) وفي طرفه الوقت ونقطة «جديد» · المقتطف سطران · النوع بلونه («تمّت المعالجة» إن عولجت) ثم رقم
    /// الرد وزرّ «واتساب» (طلب المالك ٢٠٢٦-١١-١١ «حط رقمه وزر رسالة للواتساب»)
    private func messageRow(_ entry: Entry, picked: Bool, position: DSGroupPosition) -> some View {
        let preview = ContactParser.message(from: entry.msg)
        return DSNoticeRow(title: entry.msg.member?.displayFullName ?? L10n.t("عضو", "Member"),
                           time: entry.date.map { Self.relativeShort($0) } ?? "",
                           unread: entry.fact.unread, tint: AppSection.admin.ink) {
            HStack(spacing: DSNoticeMetrics.selectGap) {
                if isSelectMode {
                    DSNoticeSelectCircle(picked: picked, tint: AppSection.admin.ink)
                }
                avatar(for: entry.msg.member, kind: entry.info)
            }
        } detail: {
            if !preview.isEmpty {
                DSNoticeText(text: preview, unread: entry.fact.unread, lines: 2, role: .subtitle)
            }
            metaLine(entry)
        }
        .dsGroupedRow(position, radius: DS.Hub.cardRadius,
                      dividerInset: DSNoticeMetrics.dividerInset(icon: DS.Icon.avatarRow, selecting: isSelectMode),
                      highlight: isSelectMode && picked ? AppSection.admin.ink.opacity(DS.Opacity.tintFill) : nil)
    }

    /// النوع (+ «تمّت المعالجة») ثم الرقم وزرّ «واتساب» في السطر نفسه — تحته إن ضاق (الخط الأكبر)
    @ViewBuilder
    private func metaLine(_ entry: Entry) -> some View {
        let tags = HStack(spacing: DS.Spacing.sm) {
            kindLabel(entry.info)
            if entry.fact.handled { handledLabel }
        }
        if !isSelectMode, let phone = Self.replyPhone(entry.msg), let whatsapp = KuwaitPhone.whatsappURL(phone) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Spacing.sm) {
                    tags
                    Spacer(minLength: DS.Spacing.xs)
                    phoneText(phone)
                    whatsappChip(whatsapp)
                }
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    tags
                    HStack(spacing: DS.Spacing.sm) {
                        phoneText(phone)
                        whatsappChip(whatsapp)
                    }
                }
            }
        } else {
            tags
        }
    }

    private func phoneText(_ phone: String) -> some View {
        Text(verbatim: "\u{2066}" + KuwaitPhone.display(phone) + "\u{2069}")
            .dsFont(.subtitle)
            .monospacedDigit()
            .foregroundColor(DS.Color.textSecondary)
            .lineLimit(1)
    }

    private func whatsappChip(_ url: URL) -> some View {
        DSChipButton(L10n.t("واتساب", "WhatsApp"), icon: "message.fill", tint: DS.Color.success, size: .small) {
            UIApplication.shared.open(url)
        }
        .fixedSize()
        .accessibilityLabel(L10n.t("مراسلة عبر واتساب", "Message on WhatsApp"))
    }

    /// رقم الرد: ما كتبه العضو للتواصل (إن لم يكن بريداً) وإلا رقمه المسجّل — نفس «الرد على العضو» في التفاصيل
    static func replyPhone(_ msg: AdminRequest) -> String? {
        let preferred = ContactParser.preferredContact(from: msg)
        if let preferred, !preferred.contains("@"), !preferred.trimmingCharacters(in: .whitespaces).isEmpty { return preferred }
        let phone = msg.member?.phoneNumber?.trimmingCharacters(in: .whitespaces) ?? ""
        return phone.isEmpty ? nil : phone
    }

    /// نوع الرسالة بلونه تحت المقتطف (أيقونة صغيرة + الاسم، ١٣)
    private func kindLabel(_ info: ContactCategoryInfo) -> some View {
        Label {
            Text(info.title).dsFont(.chip).lineLimit(1)
        } icon: {
            Image(dsSymbol: info.icon).dsGlyph(DS.Glyph.xs)
        }
        .labelStyle(DSNoticeMetaLabelStyle())
        .foregroundColor(info.color.dsReadableGlyph)
    }

    /// «✓ تمّت المعالجة» — كلمة لا لون وحده (القائمة تجمع المعالَج وغيره حين «الحالة» = الكل)
    private var handledLabel: some View {
        Label {
            Text(Logic.Status.handled.title).dsFont(.chip).lineLimit(1)
        } icon: {
            Image(systemName: "checkmark").dsGlyph(DS.Glyph.xs, weight: .semibold)
        }
        .labelStyle(DSNoticeMetaLabelStyle())
        .foregroundColor(DS.Color.success)
    }

    /// صورة المرسل — وعلى ركنها أيقونة نوع الرسالة بتعبئته (رمز أبيض بحلقة بلون السطح)
    private func avatar(for member: FamilyMember?, kind info: ContactCategoryInfo) -> some View {
        DSMemberAvatar(
            name: member?.firstName ?? "?",
            avatarUrl: member?.avatarUrl,
            size: DS.Icon.avatarRow,
            roleColor: member?.roleColor ?? DS.Color.primary
        )
        .overlay(alignment: .bottomTrailing) {
            Image(dsSymbol: info.icon)
                .dsGlyph(DSNoticeMetrics.kindBadgeGlyph, weight: .bold)
                .foregroundColor(DS.Color.textOnPrimary)
                .frame(width: DSNoticeMetrics.kindBadge, height: DSNoticeMetrics.kindBadge)
                .background(Circle().fill(Self.kindFill(info)))
                .overlay(Circle().strokeBorder(DS.Color.surface, lineWidth: DS.Border.widthBold))
                .offset(x: L10n.isArabic ? -DS.Spacing.xs : DS.Spacing.xs, y: DS.Spacing.xs)
        }
        .accessibilityHidden(true)
    }

    /// تعبئة ثابتة تحت الرمز الأبيض لكل نوع (لا تفتح في الداكن)
    private static func kindFill(_ info: ContactCategoryInfo) -> Color {
        if info.color == DS.Color.sadu { return DS.Color.saduFill }
        if info.color == DS.Color.palm { return DS.Color.palmFill }
        if info.color == DS.Color.accent { return DS.Color.goldFill }
        if info.color == DS.Color.sea { return DS.Color.seaFill }
        if info.color == DS.Color.textSecondary { return DS.Color.slateFill }
        return DS.Color.primaryFill
    }

    /// «الآن» · «5 د» · «3 س» · «2 ي» · «23 أكتوبر» (أرقام لاتينية كبقية اللوحة)
    private static func relativeShort(_ d: Date) -> String {
        let secs = Int(Date().timeIntervalSince(d))
        if secs < 60 { return L10n.t("الآن", "Now") }
        if secs < 3600 { return L10n.t("\(secs / 60) د", "\(secs / 60)m") }
        if secs < 86400 { return L10n.t("\(secs / 3600) س", "\(secs / 3600)h") }
        if secs < 604800 { return L10n.t("\(secs / 86400) ي", "\(secs / 86400)d") }
        return (L10n.isArabic ? shortDateAr : shortDateEn).string(from: d)
    }

    private static let shortDateAr: DateFormatter = shortDate("ar_KW@numbers=latn")
    private static let shortDateEn: DateFormatter = shortDate("en_US")

    private static func shortDate(_ locale: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f
    }

    // MARK: التحديد

    private func toggleSelectMode() {
        withAnimation(DS.Anim.quick) {
            isSelectMode.toggle()
            if !isSelectMode { selectedIDs.removeAll() }
        }
    }

    /// شريط وضع التحديد: «تحديد الكل» · العدد · «حذف» (يسأل قبل الحذف) — أبيض بخطّ رفيع فوقه
    private func selectionBar(_ m: Model) -> some View {
        let shown = Set(m.visible.map(\.id))
        let allPicked = !shown.isEmpty && shown.isSubset(of: selectedIDs)
        return HStack(spacing: DS.Spacing.md) {
            Button {
                withAnimation(DS.Anim.quick) {
                    if allPicked { selectedIDs.subtract(shown) } else { selectedIDs.formUnion(shown) }
                }
            } label: {
                Text(allPicked ? L10n.t("إلغاء تحديد الكل", "Deselect all") : L10n.t("تحديد الكل", "Select all"))
                    .dsFont(.button)
                    .foregroundColor(AppSection.admin.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(minHeight: DS.Icon.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DSPressStyle())
            .disabled(shown.isEmpty)

            Text(verbatim: L10n.t("\(selectedIDs.count) محدّدة", "\(selectedIDs.count) selected"))
                .dsFont(.subtitle)
                .monospacedDigit()
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            // الزرّ الواحد بالأحمر (دوّارته داخله أثناء الحذف)
            DSButton(L10n.t("حذف", "Delete"), icon: "trash.fill", role: .destructive,
                     isLoading: isDeleting, fullWidth: false) {
                showDeleteConfirm = true
            }
            .disabled(selectedIDs.isEmpty || isDeleting)
        }
        .dsPageMargin()
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Hub.background.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { AdminRowDivider() }
    }

    private func deleteSelected() async {
        isDeleting = true
        await delete(Array(selectedIDs))
        selectedIDs.removeAll()
        isDeleting = false
        withAnimation(DS.Anim.quick) { isSelectMode = false }
    }

    // MARK: الجلب والكتابة (نفس نداءات نموذج العرض، وكلها تمرّ بـDRY-RUN في تجربة الأدوار — T0)

    /// نفس الجلب (`fetchContactMessages`). نموذج العرض يبتلع الخطأ، فالفشل = انتهى الجلب والجهاز غير متصل
    /// (أو `-tmpFailStores inbox`)
    private func reload(force: Bool) async {
        health = health.beginning()
        if DebugAdminProbe.shouldFail(.inbox, hasLoaded: health.hasData) {
            withAnimation(reduceMotion ? nil : DS.Anim.smooth) { health = health.ending(success: false) }
            return
        }
        await adminRequestVM.fetchContactMessages(force: force)
        let online = NetworkMonitor.shared.isConnected
        withAnimation(reduceMotion ? nil : DS.Anim.smooth) { health = health.ending(success: online) }
    }

    private func markRead(_ id: UUID) {
        guard !adminRequestVM.readContactMessageIds.contains(id), !dryReadIds.contains(id) else { return }
        if DebugAdminProbe.dryRun("contact message mark read \(id)") {
            dryReadIds.insert(id)
            return
        }
        adminRequestVM.markContactMessageRead(id)
    }

    private func markAllRead() {
        if DebugAdminProbe.dryRun("contact messages mark all read") {
            withAnimation(DS.Anim.quick) { dryReadIds.formUnion(adminRequestVM.contactMessages.map(\.id)) }
            return
        }
        withAnimation(DS.Anim.quick) { adminRequestVM.markAllContactMessagesRead() }
    }

    private func markHandled(_ msg: AdminRequest) async {
        markRead(msg.id)
        if DebugAdminProbe.dryRun("contact message mark handled \(msg.id)") {
            if let i = adminRequestVM.contactMessages.firstIndex(where: { $0.id == msg.id }) {
                adminRequestVM.contactMessages[i].status = ApprovalStatus.approved.rawValue
            }
            return
        }
        await adminRequestVM.markContactMessageHandled(msg)
    }

    private func delete(_ ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        if DebugAdminProbe.dryRun("contact messages delete \(ids.count)") {
            withAnimation(DS.Anim.quick) { adminRequestVM.contactMessages.removeAll { ids.contains($0.id) } }
            return
        }
        await adminRequestVM.deleteContactMessages(ids: ids)
    }

    // MARK: من لا يملك الرسائل

    private var lockedCard: some View {
        AdminPageStateCard(.readOnly(L10n.t("هذه الصفحة ليست ضمن صلاحياتك", "This page isn't part of your role"),
                                     message: L10n.t("رسائل الأعضاء يقرؤها المالك والمدير.",
                                                     "Members' messages are read by the owner and admins.")))
    }

    /// الرأس وبطاقة «ليست ضمن صلاحياتك» — بلا جلب ولا أرقام
    private var lockedPage: some View {
        AdminPage(header: AdminPageHeader(back: backTitle, title: Self.title), content: AnyView(lockedCard))
    }

    // MARK: قديم — داخل «الوارد» (U8 يحذف النداء، وU21 يحذف المسار)

    /// نفس الصفوف والشريط بلا رأس (رأس «الوارد» فوقها) وبحث «الوارد» الواحد، و«تحديد» شريحة فوق الشريط
    private func embeddedList(_ m: Model) -> some View {
        List {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                if canEdit && !m.all.isEmpty {
                    HStack {
                        Spacer(minLength: 0)
                        DSChipButton(isSelectMode ? L10n.t("إلغاء", "Cancel") : L10n.t("تحديد", "Select"),
                                     icon: isSelectMode ? "xmark.circle" : "checkmark.circle",
                                     isSelected: isSelectMode, size: .small, action: toggleSelectMode)
                            .fixedSize()
                    }
                }
                lead(m)
            }
            .adminPageRow(top: DS.Spacing.sm)

            rows(m)

            DS.Hub.background
                .frame(height: DS.Spacing.xxxl)
                .listRowInsets(EdgeInsets())
                .listRowBackground(DS.Hub.background)
                .listRowSeparator(.hidden)
                .accessibilityHidden(true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .environment(\.defaultMinListRowHeight, 0)
        .background(DS.Hub.background)
        .refreshable { await reload(force: true) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelectMode {
                selectionBar(m)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .adminFilterSheet(isPresented: $showsFilters, set: m.set, selection: $filters)
    }
}

// MARK: - Message Detail Sheet

/// تفاصيل الرسالة — المربّع الموحّد: المرسل، الرسالة، الرد على العضو (واتساب · اتصال · بريد)، ثم «تمّت المعالجة»
/// (للرسالة المعلّقة) · «إغلاق» · حذف (يسأل في الصفحة قبل الحذف). الكتابة كلها من الصفحة (نفس نداءاتها وDRY-RUN)
private struct MessageDetailSheet: View {
    let message: AdminRequest
    /// الحذف و«تمّت المعالجة» لمن «يعدّل» الرسائل
    let canEdit: Bool
    let markRead: () -> Void
    let markHandled: () async -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @State private var isMarking = false
    /// مربّع كتابة الرد الرسمي (يُرسل من بريد العائلة)
    @State private var showEmailComposer = false

    private var isPending: Bool { message.status == ApprovalStatus.pending.rawValue }

    var body: some View {
        DSComposer(
            title: L10n.t("تفاصيل الرسالة", "Message Detail"),
            subtitle: message.member?.displayFullName ?? L10n.t("عضو", "Member"),
            icon: "envelope.open.fill",
            tint: DS.Color.actionNavy,
            actionTitle: isMarking ? L10n.t("جارٍ…", "Working…") : L10n.t("تمّت المعالجة", "Mark as Handled"),
            actionIcon: "checkmark.circle.fill",
            showsAction: isPending && canEdit,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: true,
            isBusy: isMarking,
            isBehindExtra: showEmailComposer,
            // «تمّت المعالجة» · «إغلاق» · حذف (دائرة حمراء) في صفّ واحد — قرار المالك ٢٠٢٦-١١-١١
            extraActions: canEdit ? [DSComposerAction(id: "delete", title: L10n.t("حذف الرسالة", "Delete message"),
                                                      icon: "trash.fill", role: .destructive, action: onDelete)] : [],
            extraInline: canEdit,
            onSubmit: { Task { await markHandledAndClose() } },
            onCancel: onDismiss
        ) {
            senderSection
            messageSection
            replySection
        }
        .onAppear {
            // defensive: تأكد أن الرسالة معلّمة كمقروءة حتى لو فُتحت من مسار آخر
            markRead()
        }
        .dsCenterBox(isPresented: $showEmailComposer) {
            OfficialReplySheet(
                to: ContactParser.preferredContact(from: message) ?? "",
                memberName: message.member?.displayFullName ?? "",
                category: ContactParser.category(of: message),
                originalMessage: ContactParser.message(from: message)
            )
        }
    }

    // MARK: المرسل — الصورة · الاسم والهاتف · التصنيف في الطرف المقابل

    private var senderSection: some View {
        let info = ContactCategoryInfo.from(raw: ContactParser.category(of: message))
        let phone = message.member?.phoneNumber ?? ""
        return DSComposerSection(title: L10n.t("المرسل", "Sender"),
                                 icon: "person.fill",
                                 tint: AppSection.admin.ink,
                                 index: 0) {
            HStack(spacing: DS.Spacing.sm) {
                DSMemberAvatar(
                    name: message.member?.firstName ?? "?",
                    avatarUrl: message.member?.avatarUrl,
                    size: DS.Icon.avatar,
                    roleColor: message.member?.roleColor ?? DS.Color.primary
                )
                .accessibilityHidden(true)   // الصورة زخرفة — الاسم يُقرأ بعدها

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(message.member?.displayFullName ?? L10n.t("عضو", "Member"))
                        .dsFont(.adminRowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !phone.isEmpty {
                        Text(verbatim: "\u{2066}" + KuwaitPhone.display(phone) + "\u{2069}")
                            .dsFieldFont(.subtitle)
                            .monospacedDigit()
                            .foregroundColor(DS.Color.fieldValue)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: DS.Spacing.xxs) {
                    // التصنيف يُقرأ من النص تحته — قرص الحالة المجسّم بلون التصنيف كما هو
                    DSStateIcon(info.icon, tint: info.color, size: DS.Icon.row, mapsChrome: false)
                    Text(info.title)
                        .dsFont(.chip)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
            .dsRowBox()
            .accessibilityElement(children: .combine)   // المرسل ورقمه وتصنيف الرسالة معاً
        }
    }

    // MARK: نص الرسالة (+ حالة التعامل)

    private var messageSection: some View {
        DSComposerSection(title: L10n.t("الرسالة", "Message"),
                          icon: "text.bubble.fill",
                          tint: DS.Color.info,
                          index: 1) {
            Text(ContactParser.message(from: message))
                .dsFont(.body)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .dsRowBox()

            if !isPending {
                HStack(spacing: DS.Spacing.sm) {
                    DSFieldIcon(name: "checkmark.seal.fill", tint: DS.Color.success)
                        .accessibilityHidden(true)
                    Text(L10n.t("تمّت معالجة هذه الرسالة", "This message was handled"))
                        .dsFont(.adminRowTitle)
                        .foregroundColor(DS.Color.success)
                    Spacer(minLength: 0)
                }
                .dsRowBox()
            }
        }
    }

    // MARK: الرد على العضو — الوسيلة التي طلبها العضو أوّلاً، ثم رقمه المسجّل

    @ViewBuilder
    private var replySection: some View {
        let phone = message.member?.phoneNumber ?? ""
        let preferred = ContactParser.preferredContact(from: message)
        let isEmail = (preferred ?? "").contains("@")
        let replyPhone = isEmail ? phone : (preferred ?? phone)

        if isEmail || !replyPhone.isEmpty {
            DSComposerSection(title: L10n.t("الرد على العضو", "Reply to member"),
                              icon: "arrowshape.turn.up.left.fill",
                              tint: DS.Color.success,
                              index: 2) {
                // وسيلة التواصل التي كتبها العضو — تُعرض وتُنسخ بالضغط
                if let preferred {
                    preferredContactRow(preferred, isEmail: isEmail)
                }

                HStack(spacing: DS.Spacing.sm) {
                    if !replyPhone.isEmpty {
                        replyButton(
                            title: L10n.t("واتساب", "WhatsApp"),
                            icon: "message.fill",
                            // أخضر واتساب الثابت (#25D366) كان باهتاً جداً على خلفيته في الوضع الفاتح
                            // (~1.8:1) — لون أخضر من ألوان التطبيق يُقرأ في الوضعين
                            color: DS.Color.secondary
                        ) { openURL("https://wa.me/\(sanitize(replyPhone))") }
                        replyButton(
                            title: L10n.t("اتصال", "Call"),
                            icon: "phone.fill",
                            color: DS.Color.success
                        ) { openURL("tel:\(sanitize(replyPhone))") }
                    }
                    if isEmail {
                        replyButton(
                            title: L10n.t("بريد", "Email"),
                            icon: "envelope.fill",
                            color: DS.Color.info
                        ) { showEmailComposer = true }
                    }
                }
            }
        }
    }

    private func preferredContactRow(_ preferred: String, isEmail: Bool) -> some View {
        Button {
            UIPasteboard.general.string = preferred
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: isEmail ? "envelope.fill" : "phone.fill", tint: DS.Color.info)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(L10n.t("وسيلة التواصل", "Preferred contact"))
                        .dsFieldFont(.label)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(preferred)
                        .dsFieldFont(.fieldValue)
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
                Image(systemName: "doc.on.doc")
                    .dsGlyph(DS.Glyph.mdCompact, weight: .semibold)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        // رمز النسخ للعين فقط — القارئ الصوتي يعرف أن الضغط ينسخ
        .accessibilityHint(L10n.t("ينسخ وسيلة التواصل", "Copies the contact"))
    }

    /// الزرّ الواحد (٤٤) بلون الوسيلة صلباً (واتساب، اتصال، بريد)
    private func replyButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        DSButton(title, icon: icon, tint: color, action: action)
    }

    private func sanitize(_ phone: String) -> String {
        phone.filter { $0.isNumber || $0 == "+" }
    }

    private func openURL(_ str: String) {
        guard let url = URL(string: str) else { return }
        UIApplication.shared.open(url)
    }

    @MainActor
    private func markHandledAndClose() async {
        isMarking = true
        await markHandled()
        isMarking = false
        onDismiss()
    }
}

// MARK: - Helpers

enum ContactParser {
    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// تحويل ISO string لـ Date (يدعم بكسر ثواني أو بدونها).
    static func date(_ str: String?) -> Date? {
        guard let s = str, !s.isEmpty else { return nil }
        return isoFull.date(from: s) ?? isoBasic.date(from: s)
    }

    /// التصنيف: من new_value مباشرة، fallback لتحليل details.
    static func category(of msg: AdminRequest) -> String {
        if let nv = msg.newValue?.trimmingCharacters(in: .whitespacesAndNewlines), !nv.isEmpty {
            return nv
        }
        guard let details = msg.details else { return "—" }
        for line in details.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("التصنيف:") {
                return String(trimmed.dropFirst("التصنيف:".count)).trimmingCharacters(in: .whitespaces)
            }
            if trimmed.lowercased().hasPrefix("category:") {
                return String(trimmed.dropFirst("category:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return "—"
    }

    /// وسيلة التواصل التي كتبها العضو للرد (إيميل أو رقم) — إن وُجدت.
    static func preferredContact(from msg: AdminRequest) -> String? {
        guard let details = msg.details else { return nil }
        for line in details.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("وسيلة التواصل:") {
                let v = String(t.dropFirst("وسيلة التواصل:".count)).trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
            if t.lowercased().hasPrefix("preferred contact:") {
                let v = String(t.dropFirst("preferred contact:".count)).trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
        }
        return nil
    }

    /// نص الرسالة: من سطر "الرسالة:" أو "Message:" — fallback للنص الكامل.
    static func message(from msg: AdminRequest) -> String {
        guard let details = msg.details else { return "" }
        let lines = details.components(separatedBy: .newlines)
        var capturing = false
        var collected: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("الرسالة:") {
                capturing = true
                let rest = String(trimmed.dropFirst("الرسالة:".count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { collected.append(rest) }
                continue
            }
            if trimmed.lowercased().hasPrefix("message:") {
                capturing = true
                let rest = String(trimmed.dropFirst("message:".count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { collected.append(rest) }
                continue
            }
            if trimmed.hasPrefix("التصنيف:") || trimmed.lowercased().hasPrefix("category:") {
                continue
            }
            if trimmed.hasPrefix("وسيلة التواصل:") || trimmed.lowercased().hasPrefix("preferred contact:") {
                capturing = false
                continue
            }
            if capturing && !trimmed.isEmpty { collected.append(trimmed) }
        }
        if collected.isEmpty {
            return details
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("التصنيف:") }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
        }
        return collected.joined(separator: "\n")
    }
}

/// عرض موحّد للتصنيف (لون/أيقونة/ترجمة) بناءً على نص خام من قاعدة البيانات.
struct ContactCategoryInfo {
    let title: String
    let icon: String
    let color: Color

    static func from(raw: String) -> ContactCategoryInfo {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        switch trimmed {
        case "شكوى", "complaint", "Complaint":
            return .init(title: L10n.t("شكوى", "Complaint"), icon: "exclamationmark.bubble.fill", color: DS.Color.sadu)
        case "اقتراح", "suggestion", "Suggestion":
            return .init(title: L10n.t("اقتراح", "Suggestion"), icon: "lightbulb.fill", color: DS.Color.palm)
        case "استفسار", "inquiry", "Inquiry":
            return .init(title: L10n.t("استفسار", "Inquiry"), icon: "questionmark.bubble.fill", color: AppSection.admin.ink)
        case "اعتراض", "appeal", "Appeal":
            return .init(title: L10n.t("اعتراض", "Appeal"), icon: "hand.raised.fill", color: DS.Color.sea)
        case "أخرى", "other", "Other":
            return .init(title: L10n.t("أخرى", "Other"), icon: "ellipsis.message.fill", color: DS.Color.accent)
        default:
            return .init(title: trimmed.isEmpty ? "—" : trimmed, icon: "envelope.fill", color: DS.Color.textSecondary)
        }
    }
}


// MARK: - شيت الرد الرسمي (يُرسل من بريد العائلة عبر الخادم)

/// «الرد بالبريد» — مربّع كتابة بنفس التصميم الموحّد (طلب المالك): المستلم ثم نص الرد،
/// و«إرسال الرد» / «إغلاق» أسفل المربّع
private struct OfficialReplySheet: View {
    let to: String
    let memberName: String
    let category: String
    let originalMessage: String

    @Environment(\.dismiss) private var dismiss
    @State private var replyText = ""
    @State private var isSending = false
    @State private var errorText: String?
    @State private var didSend = false

    private var canSend: Bool {
        !(isSending || didSend || replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        DSComposer(
            title: L10n.t("الرد بالبريد", "Email reply"),
            subtitle: memberName.isEmpty ? L10n.t("العضو", "Member") : memberName,
            icon: "envelope.badge.fill",
            tint: DS.Color.actionNavy,
            actionTitle: didSend ? L10n.t("تم الإرسال", "Sent") : L10n.t("إرسال الرد", "Send reply"),
            actionIcon: didSend ? "checkmark.circle.fill" : "paperplane.fill",
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: canSend,
            isBusy: isSending,
            // ردّ مكتوب لم يُرسل → «إغلاق» يسأل قبل التجاهل (توصية أبل)؛ بعد الإرسال لا سؤال
            hasUnsavedChanges: !didSend && !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onSubmit: { Task { await send() } },
            onCancel: { dismiss() }
        ) {
            recipientSection
            replySection
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: المستلم

    private var recipientSection: some View {
        DSComposerSection(title: L10n.t("المستلم", "Recipient"),
                          icon: "person.fill",
                          tint: DS.Color.info,
                          index: 0) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "envelope.badge.fill", tint: DS.Color.info)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(memberName.isEmpty ? L10n.t("العضو", "Member") : memberName)
                        .dsFont(.adminRowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                    Text(to)
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: نص الرد

    private var replySection: some View {
        DSComposerSection(title: L10n.t("الرد على العضو", "Reply to member"),
                          icon: "arrowshape.turn.up.left.fill",
                          tint: AppSection.admin.ink,
                          index: 1) {
            ReplyComposerField(label: L10n.t("نص الرد", "Reply"),
                               placeholder: L10n.t("اكتب ردّك هنا…", "Write your reply…"),
                               text: $replyText)

            if let errorText {
                DSNoteCard(errorText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
    }

    @MainActor
    private func send() async {
        errorText = nil
        isSending = true
        defer { isSending = false }
        do {
            struct Payload: Encodable {
                let to: String, reply: String, member_name: String
                let original_message: String, category: String
            }
            _ = try await SupabaseConfig.client.functions.invoke(
                "admin-reply-email",
                options: .init(body: Payload(
                    to: to,
                    reply: replyText.trimmingCharacters(in: .whitespacesAndNewlines),
                    member_name: memberName,
                    original_message: originalMessage,
                    category: category
                ))
            )
            didSend = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } catch {
            Log.error("[AdminReply] فشل إرسال الرد: \(error.localizedDescription)")
            errorText = L10n.t("تعذّر إرسال الرد. حاول مرة أخرى.", "Could not send the reply. Try again.")
        }
    }
}

/// حقل نص الرد — بنفس شكل `DSComposerField` لكنه أطول (يبدأ بستة أسطر)،
/// فالرد البريدي يحتاج مساحة كتابة مثل محرّر النص السابق
private struct ReplyComposerField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var tint: Color = AppSection.admin.ink
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            // رمز الحقل الموحّد (`DSFieldIcon`) كبقية حقول المربّعات
            DSFieldIcon(name: "square.and.pencil", tint: tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(label)
                    .dsFieldFont(.label)
                    .foregroundColor(focused ? tint : DS.Color.fieldLabel)
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(6...12)
                    .dsFieldFont(.fieldValue)
                    .foregroundColor(DS.Color.textPrimary)
                    .focused($focused)
            }
        }
        .dsRowBox()
        .dsFocusFieldBox(focused: focused, tint: tint)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}


#endif
