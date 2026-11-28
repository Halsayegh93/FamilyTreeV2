#if DEBUG
import SwiftUI

// MARK: - معاينة مربّع الطلب والسحب ووضع «تحديد» و«بانتظار المراجعة» بلا سيرفر (للتصوير فقط — نسخ التطوير)
//
// `-uiPreviewInbox box|box-full|swipe|select|review` — القطع الحقيقية (`AdminRequestPanel`، `AdminRequestPanelSummary`،
// `RequestSwipeActions`، `AdminInboxSelectionBar`، `PostReviewCard`) ببيانات وهمية. التفاصيل الكاملة هنا بقطع المربّع نفسها
// (`AdminRequestBoxShowcase`) لأن المربّع الحقيقي يحتاج بيانات السيرفر.

enum AdminRequestPanelPreview {
    static let modes: Set<String> = ["box", "box-full", "swipe", "select", "review"]
}

struct AdminRequestPanelPreviewScreen: View {
    let mode: String
    @State private var expanded: Bool
    @State private var showsBox = true

    init(mode: String) {
        self.mode = mode
        _expanded = State(initialValue: mode == "box-full")
    }

    private static let summary = AdminRequestSummaryModel(
        name: "سالم أحمد يوسف المحمدعلي", about: "عن نفسه",
        changes: [AdminRequestChange(label: "الحالة الاجتماعية", current: "أعزب", requested: "متزوج")],
        stateWord: "بانتظار قرارك", stateTone: .mine)

    var body: some View {
        switch mode {
        case "swipe": swipeList
        case "select": selectScreen
        case "review": reviewScreen
        default:
            ZStack {
                AdminInboxTilesPreviewScreen(mode: "requests")
                if showsBox { panel }
            }
        }
    }

    private var panel: some View {
        AdminRequestPanel(expanded: $expanded, title: "تغيير الحالة الاجتماعية", subtitle: "طلب آخر · اليوم 11:14 ص",
                          icon: "pencil", onClose: { showsBox = false }) {
            AdminRequestPanelSummary(model: Self.summary, decisions: [
                AdminBoxAction(id: "approve", title: "موافقة", style: .primary) {},
                AdminBoxAction(id: "reject", title: "رفض", style: .reject) {},
            ], onExpand: { withAnimation(DSMotion.expand) { expanded = true } })
        } full: {
            VStack(spacing: 0) {
                AdminRequestBoxNavRow(title: "", menu: [
                    AdminBoxMenuItem(id: "urgent", title: "اجعله عاجلاً", icon: "flame") {},
                    AdminBoxMenuItem(id: "delete", title: "حذف الطلب", icon: "trash", destructive: true) {},
                ], closeTitle: AdminRequestPanelText.hideFull) {
                    withAnimation(DSMotion.expand) { expanded = false }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Hub.stackSpacing) {
                        AdminRequestTitleBlock(name: "سالم أحمد يوسف المحمدعلي", line: "قبل ساعتين · من ملفه")
                        AdminRequestStageCard(step: 2, note: "أوصى المراقب بالقبول · عندك منذ 3 ساعات")
                        AdminRequestChangesCard(changes: Self.summary.changes)
                        AdminBoxSection(title: "ملاحظات الإدارة", trailing: "لا يراها العضو") {
                            AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                                AdminDetailInfoRow(icon: "text.bubble", label: "بدر", value: "عقد الزواج مرفق في الطلب السابق",
                                                   color: DS.Color.primary)
                            }
                        }
                        AdminBoxSection(title: "بيانات العضو") {
                            AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                                AdminDetailInfoRow(icon: "person.fill", label: "الاسم", value: "سالم أحمد يوسف",
                                                   color: DS.Color.palm, open: {})
                                AdminDetailInfoRow(icon: "calendar", label: "الميلاد", value: "14/03/1994", color: DS.Color.primary)
                                AdminDetailInfoRow(icon: "tray.full", label: "الطلبات السابقة", value: "2", color: DS.Color.primary, open: {})
                            }
                        }
                        AdminRequestLogCard(steps: [DSPathStep(icon: "paperplane.fill", title: "أُرسل", lines: ["بواسطة: سالم"]),
                                                    DSPathStep(icon: "hand.thumbsup.fill", title: "أوصى المراقب بالقبول",
                                                               lines: ["بواسطة: حسن"])])
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AdminRequestDecisionBar(
                    buttons: [AdminBoxAction(id: "approve", title: "اعتماد", style: .primary) {},
                              AdminBoxAction(id: "reject", title: "رفض", style: .reject) {}],
                    more: [AdminBoxAction(id: "now", title: "اعتماد وتنفيذ الحين", icon: "bolt") {}])
            }
            .environment(\.adminRequestBoxRows, true)
            .background(DS.Hub.background)
        }
    }

    // MARK: السحب — `List` حقيقية بـ`RequestSwipeActions` (اسحب على المحاكي)

    private static func row(_ name: String, _ icon: String, _ fill: Color, _ ask: String, word: String, mine: Bool = false)
        -> AdminInboxRowModel {
        AdminInboxRowModel(name: name, avatarName: name, avatarURL: nil, typeIcon: icon, typeFill: fill, time: "11:14 ص",
                           ask: ask, stateWord: word, stateTone: mine ? .mine : .neutral)
    }

    private var rows: [AdminInboxRowModel] {
        [Self.row("سالم أحمد يوسف المحمدعلي", "person.text.rectangle", DS.Color.primaryFill,
                  "طلب آخر · تغيير الحالة الاجتماعية", word: "بانتظار قرارك", mine: true),
         Self.row("نورة خالد ناصر", "person.fill", DS.Color.femaleFill, "طلب انضمام · من خارج العائلة", word: "بانتظار قرارك", mine: true),
         Self.row("بدر علي حسن المحمدعلي", "person.badge.plus", DS.Color.palmFill, "يطلب إضافة ابن: محمد", word: "بانتظار قرارك", mine: true)]
    }

    private var swipeList: some View {
        List {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, model in
                AdminInboxRow(model: model, position: DSGroupPosition(index: i, count: rows.count))
                    .modifier(RequestSwipeActions(enabled: true, approve: {}, approveLabel: "موافقة", approveIcon: "checkmark",
                                                  approveColor: DS.Color.successFill, reject: {}, delete: {}))
                    .adminPageRow(top: 0, bottom: 0)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.top, DS.Spacing.xxl)
        .background(DS.Hub.background.ignoresSafeArea())
    }

    // MARK: وضع «تحديد»

    private var selectScreen: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    AdminInboxBand(backTitle: "الإدارة", onBack: {}, items: [
                        AdminHeaderItem(id: "review", value: 2, label: "بانتظار المراجعة", tap: .action {}, emphasis: true),
                        AdminHeaderItem(id: "waiting", value: 1, label: "بانتظار قرارك", tap: .action {}),
                        AdminHeaderItem(id: "urgent", value: 0, label: "عاجل", tap: .action {}),
                        AdminHeaderItem(id: "late", value: 0, label: "متأخر", tap: .action {}),
                    ], selectingTitle: AdminInboxText.selectingTitle(2)) {
                        AdminHeaderTextButton(title: "تم") {}
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, model in
                            AdminInboxRow(model: model, position: DSGroupPosition(index: i, count: rows.count),
                                          selecting: true, picked: i < 2)
                        }
                    }
                    .dsPageMargin()
                    .padding(.top, DS.Spacing.md)
                }
            }
            AdminInboxSelectionBar(count: 2, allPicked: false, canPickAll: true, canReject: true, busy: false,
                                   onToggleAll: {}, onApprove: {}, onReject: {})
        }
        .background(DS.Hub.background.ignoresSafeArea())
        .adminStatusBarCover()
    }

    // MARK: «بانتظار المراجعة» — بطاقات الصفحة الحقيقية

    private static func request(_ type: String, _ value: String?) -> AdminRequest {
        AdminRequest(id: UUID(), memberId: UUID(), requesterId: UUID(), requestType: type, newValue: value,
                     status: "approved", details: nil, createdAt: nil, member: nil, adminReply: nil,
                     repliedAt: nil, repliedBy: nil, approvedAt: "2026-11-28T08:20:00Z")
    }

    private var reviewScreen: some View {
        let one = Self.request(RequestType.nameChange.rawValue, "متزوج")
        let two = Self.request(RequestType.childAdd.rawValue, nil)
        return DSComposer(title: "بانتظار المراجعة", subtitle: "طلبات قُبلت — راجع ما تم فيها", icon: "checkmark.shield.fill",
                          tint: DS.Color.actionNavy, actionTitle: "", showsAction: false, cancelTitle: "إغلاق",
                          canSubmit: false, onSubmit: {}, onCancel: {}) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                AdminSectionLabel(title: "بانتظار المراجعة · 2")
                PostReviewCard(request: one, summary: Self.summary, busy: false, onOK: {}, onFlag: {}, onFull: {})
                PostReviewCard(request: two, summary: AdminRequestSummaryModel(
                    name: "علي حسن الصايغ", about: "عن ابنه",
                    changes: [AdminRequestChange(label: "الاسم", current: nil, requested: "محمد علي حسن الصايغ"),
                              AdminRequestChange(label: "الميلاد", current: nil, requested: "2026")]),
                    busy: false, onOK: {}, onFlag: {}, onFull: {})
            }
        }
        .background(DS.Hub.background.ignoresSafeArea())
    }
}
#endif
