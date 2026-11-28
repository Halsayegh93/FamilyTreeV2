#if DEBUG
import SwiftUI

// MARK: - معاينة مربّعات «الوارد» بلا سيرفر (للتصوير فقط — نسخ التطوير)
//
// `-uiPreviewInbox requests|done|done-week|messages` عند التشغيل: رأس «الوارد» الحقيقي (`AdminInboxBand` + `AdminInboxTileRow` +
// `AdminMembersFilterBar`) والمربّع المختار، وتحته الشرائح وسطر العدد (`AdminInboxFilterStatus`) وصفوف `AdminInboxRow` بأسماء
// وهمية. المربّعات تُضغط فتتبدّل القائمة بحركة الصفحة نفسها. صفوف «الرسائل» هنا بشكل صفّ الطلب (صفّ الرسالة الحقيقي يحتاج
// بيانات السيرفر).

enum AdminInboxTilesPreview {
    static var mode: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiPreviewInbox"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

struct AdminInboxTilesPreviewScreen: View {
    @State private var tile: AdminInboxTile
    @State private var search = ""
    @State private var filters = AdminInboxLogic.Filters()
    @State private var done = AdminInboxDoneLogic.Filters()
    @State private var messageFilters = AdminInboxMessageLogic.Filters()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(mode: String) {
        // `done-week` = «المنجزة» وفترة «هذا الأسبوع» مختارة (شريحتها بـ✕ تحت الرأس)
        let base = mode.replacingOccurrences(of: "-week", with: "")
        _tile = State(initialValue: AdminInboxTile(rawValue: base) ?? .requests)
        if mode.hasSuffix("-week") { _done = State(initialValue: AdminInboxDoneLogic.Filters(range: .week)) }
    }

    private static let facts: [AdminInboxLogic.Fact] = {
        let kinds: [AdminInboxLogic.Kind] = [.joinRequests, .treeAdd, .joinRequests, .phone, .joinRequests]
        return kinds.enumerated().map { i, kind in
            AdminInboxLogic.Fact(kind: kind, source: .profile, inFlow: false, waiting: i == 1, urgent: false, late: false)
        }
    }()

    private static let requestSet = AdminAllRequestsView.inboxFilterSet(facts: facts, ready: true, workflowOn: false,
                                                                        roleKinds: Set(AdminInboxLogic.Kind.allCases))

    private static let doneSet: AdminFilterSet<AdminInboxDoneLogic.Filters> = {
        typealias D = AdminInboxDoneLogic
        let counts: [D.Range: Int] = [.today: 3, .week: 11]
        return AdminFilterSet(noun: AdminInboxText.requestsNoun, resultCount: { counts[$0.range] }) { _ in
            [.single("range", title: "الفترة", value: \.range, neutral: D.Range.today,
                     options: D.Range.allCases.map { AdminFilterOption($0, $0.title, count: counts[$0]) })]
        }
    }()

    private static let messageSet: AdminFilterSet<AdminInboxMessageLogic.Filters> = {
        typealias L = AdminInboxMessageLogic
        return AdminFilterSet(noun: L.noun, resultCount: { $0.isEmpty ? 4 : 2 }) { _ in
            [.choices("status", title: "الحالة", values: \.statuses,
                      options: [AdminFilterOption(L.Status.unread, L.Status.unread.title, count: 2),
                                AdminFilterOption(L.Status.awaiting, L.Status.awaiting.title, count: 3)])]
        }
    }()

    private static func row(_ name: String, _ icon: String, _ fill: Color, _ time: String, _ ask: String,
                            pills: [AdminInboxRowModel.Pill] = [], word: String? = nil, mine: Bool = false)
        -> AdminInboxRowModel {
        AdminInboxRowModel(name: name, avatarName: name, avatarURL: nil, typeIcon: icon, typeFill: fill, time: time,
                           ask: ask, pills: pills, stateWord: word, stateTone: mine ? .mine : .neutral)
    }

    private var rows: [AdminInboxRowModel] {
        switch tile {
        case .requests:
            return [
                Self.row("سالم أحمد يوسف المحمدعلي", "person.text.rectangle", DS.Color.primaryFill, "11:14 ص",
                         "طلب آخر · تغيير الحالة الاجتماعية", word: "بانتظار قرارك", mine: true),
                Self.row("نورة خالد ناصر", "person.fill", DS.Color.femaleFill, "10:05 ص",
                         "طلب انضمام · من خارج العائلة", word: "للاطلاع"),
                Self.row("بدر علي حسن المحمدعلي", "person.badge.plus", DS.Color.palmFill, "9:12 ص",
                         "طلب انضمام · من العائلة", word: "للاطلاع"),
            ]
        case .done:
            return [
                Self.row("علي حسن محمد المحمدعلي", "phone.fill", DS.Color.seaFill, "10:40 ص", "تغيير الرقم",
                         pills: [.init(title: "قُبل", tone: .ok)], word: "بواسطة بدر"),
                Self.row("سالم أحمد يوسف المحمدعلي", "person.badge.plus", DS.Color.palmFill, "9:02 ص",
                         "إضافة ابن — ليلى", pills: [.init(title: "قُبل", tone: .ok)], word: "بواسطة بدر"),
                Self.row("خالد ناصر بدر", "person.fill", DS.Color.primaryFill, "8:15 ص", "طلب انضمام",
                         pills: [.init(title: "رُفض", tone: .error)], word: "بواسطة علي"),
            ]
        case .messages:
            return [
                Self.row("محمد عبدالله جاسم المحمدعلي", "questionmark.bubble.fill", DS.Color.seaFill, "12:30 م",
                         "استفسار — متى موعد الغبقة السنوية؟", word: "بانتظار الرد", mine: true),
                Self.row("فاطمة سالم أحمد", "lightbulb.fill", DS.Color.goldFill, "8:50 ص",
                         "اقتراح — إضافة صور قديمة للمكتبة", word: "بانتظار الرد", mine: true),
            ]
        }
    }

    private var band: some View {
        let accessory: AnyView
        switch tile {
        case .requests:
            accessory = AnyView(AdminMembersFilterBar(query: $search, activeCount: Self.requestSet.activeCount(filters)) {})
        case .done:
            accessory = AnyView(AdminMembersFilterBar(query: $search, activeCount: Self.doneSet.activeCount(done)) {})
        case .messages:
            accessory = AnyView(AdminMembersFilterBar(query: $search,
                                                      activeCount: Self.messageSet.activeCount(messageFilters)) {})
        }
        return AdminInboxBand(backTitle: "الإدارة", onBack: {}, items: [
            AdminHeaderItem(id: "review", value: 2, label: "بانتظار المراجعة", tap: .action {}, emphasis: true),
            AdminHeaderItem(id: "waiting", value: 1, label: "بانتظار قرارك", tap: .action {}),
            AdminHeaderItem(id: "urgent", value: 0, label: "عاجل", tap: .action {}),
            AdminHeaderItem(id: "late", value: 0, label: "متأخر", tap: .action {}),
        ], tiles: AnyView(AdminInboxTileRow(items: [
            AdminInboxTileItem(tile: .requests, value: 5),
            AdminInboxTileItem(tile: .done, value: 3),
            AdminInboxTileItem(tile: .messages, value: 2),
        ], selected: tile, onSelect: { next in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: DSMotion.tabFade)) { tile = next }
        })), accessory: accessory) {
            if tile != .done { AdminInboxCircleButton(symbol: "checkmark.circle", label: "تحديد") {} }
            AdminInboxCircleButton(symbol: "gearshape", label: "إعدادات مسار الموافقات") {}
        }
    }

    @ViewBuilder private var status: some View {
        switch tile {
        case .requests:
            AdminInboxFilterStatus(set: Self.requestSet, selection: $filters, note: "الأحدث أولاً")
        case .done:
            AdminInboxFilterStatus(set: Self.doneSet, selection: $done)
        case .messages:
            AdminInboxFilterStatus(set: Self.messageSet, selection: $messageFilters, note: "الأحدث أولاً")
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                band
                VStack(alignment: .leading, spacing: DS.Hub.stackSpacing) {
                    status
                    VStack(alignment: .leading, spacing: DSNoticeMetrics.headerGap) {
                        DSDayHeader(title: "اليوم", count: rows.count)
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, model in
                                AdminInboxRow(model: model, position: DSGroupPosition(index: index, count: rows.count))
                            }
                        }
                    }
                }
                .id(tile)
                .transition(.opacity)
                .dsPageMargin()
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Hub.pageBottom)
            }
        }
        .background(DS.Hub.background.ignoresSafeArea())
        .adminStatusBarCover()
    }
}
#endif
