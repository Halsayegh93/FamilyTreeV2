#if DEBUG
import SwiftUI

// MARK: - معاينة التصميم بلا سيرفر (للتصوير فقط — نسخ التطوير)
//
// `-uiPreviewRequestTrail sender|fallback|handled|list|filters|filtersheet|select|buttons` عند التشغيل: مربّع تفاصيل الطلب
// بـ«المرسل» وأزرار الطلبات الجديدة، أو بلا بيانات مسجّلة (طلب قديم)، أو المربّع المعالَج للعرض فقط، أو صفوف «المنجز»، أو جذر
// «الوارد» الجديد (U8) بأبوابه وتصفيته (طقم «تصفية» الحقيقي بأرقام وهمية — F3: ثلاث شرائح، كل واحدة تُزال) وأيامه، أو الجذر
// نفسه وورقة «تصفية» مفتوحة فوقه (`filtersheet` — الاختيار المتعدّد يُطبَّق فوراً)، أو وضع «تحديد» بشريطه السفلي، أو صفوف
// الأزرار.
// أسماء وهمية — لا بيانات أعضاء حقيقية.

enum AdminTrailPreview {
    static var mode: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiPreviewRequestTrail"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

private enum PreviewData {
    static let senderId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let subjectId = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    static let adminId = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    static let monitorId = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!

    static func member(_ id: UUID, _ name: String, _ role: String, female: Bool = false, father: UUID? = nil) -> FamilyMember? {
        var json: [String: Any] = ["id": id.uuidString, "full_name": name, "role": role, "status": "active",
                                   "gender": female ? "female" : "male"]
        if let father { json["father_id"] = father.uuidString }
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder().decode(FamilyMember.self, from: data)
    }

    static let people: [UUID: FamilyMember] = {
        var map: [UUID: FamilyMember] = [:]
        map[senderId] = member(senderId, "سالم أحمد يوسف المحمدعلي", "member")
        map[subjectId] = member(subjectId, "نورة سالم أحمد يوسف المحمدعلي", "member", female: true, father: senderId)
        map[adminId] = member(adminId, "بدر خالد ناصر المحمدعلي", "admin")
        map[monitorId] = member(monitorId, "علي حسن محمد المحمدعلي", "monitor")
        return map
    }()

    static func request(status: String, recorded: Bool, type: String = "tree_edit", reply: String? = nil) -> AdminRequest? {
        var json: [String: Any] = [
            "id": UUID().uuidString, "member_id": senderId.uuidString, "requester_id": senderId.uuidString,
            "request_type": type, "status": status, "created_at": "2026-11-11T09:44:46.129Z",
            "details": #"{"v":3,"action":"add","targetMemberId":"\#(senderId.uuidString)","targetMemberName":"نورة سالم أحمد","parentMemberId":"\#(senderId.uuidString)","parentMemberName":"نورة سالم أحمد","newMemberName":"ليلى","notes":"شجرة النساء\nالاسم: ليلى"}"#,
            "new_value": "add",
        ]
        if status != "pending" {
            json["replied_at"] = "2026-11-11T10:05:12.000Z"
            json["replied_by"] = adminId.uuidString
        }
        if let reply { json["admin_reply"] = reply }
        if recorded {
            json["sent_from"] = [["icon": "tree.fill", "title": "شجرة النساء"],
                                 ["icon": "person.fill", "title": "نورة سالم أحمد"],
                                 ["icon": "plus", "title": "طلب إضافة أبناء"]]
            json["sent_via"] = ["platform": "ios", "app_version": "1.0.2", "app_build": "51", "at": "2026-11-11T09:44:46.129Z"]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder().decode(AdminRequest.self, from: data)
    }

    static func event(_ n: Int64, _ action: String, _ actor: UUID?, _ role: String, _ at: String, _ note: String? = nil) -> AdminRequestEvent? {
        var json: [String: Any] = ["id": n, "action": action, "actor_role": role, "at": at]
        if let actor { json["actor_id"] = actor.uuidString }
        if let note { json["note"] = note }
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder().decode(AdminRequestEvent.self, from: data)
    }

    static let events: [AdminRequestEvent] = [
        event(1, "sent", senderId, "member", "2026-11-11T09:44:46.129Z"),
        event(2, "claimed", monitorId, "monitor", "2026-11-11T09:52:03.000Z"),
        event(3, "recommended_approve", monitorId, "monitor", "2026-11-11T09:58:40.000Z", "الاسم مطابق لسجلّ الأسرة"),
        event(4, "approved", adminId, "admin", "2026-11-11T10:05:12.000Z"),
    ].compactMap { $0 }
}

/// جذر «الوارد» الجديد (U8، spec C.2) بأعداد وأسماء وهمية: الرأس بسطر الأرقام، صفّا الأبواب، شريط «تصفية» (الطقم الحقيقي
/// بورقته — F3) بثلاث شرائح، الأيام بصفوفها، و«المنجز» — بنفس قطع الصفحة الحقيقية (`AdminInboxBand`، `AdminInboxRow`…).
/// `selecting` = وضع «تحديد» بشريطه السفلي، و`opensSheet` = ورقة «تصفية» مفتوحة
private struct InboxRootPreview: View {
    var selecting = false
    var opensSheet = false
    @State private var search = ""
    @State private var filters = AdminInboxLogic.Filters(statuses: [.waiting], groups: [.members, .tree])
    @State private var showsFilters = false
    @State private var picked: Set<Int> = [0, 2]

    /// ٢٠ طلباً وهمياً بأنواع ومصادر ومراحل مختلفة — للأعداد في الشرائح والورقة فقط
    private static let facts: [AdminInboxLogic.Fact] = {
        typealias F = AdminInboxLogic.Fact
        let kinds: [AdminInboxLogic.Kind] = [.joinRequests, .children, .treeAdd, .phone, .deceased, .news, .treeEditName,
                                             .photos, .children, .nameChange, .reports, .treeAddPhoto, .joinRequests,
                                             .children, .diwaniya, .treeDeceased, .phone, .treeAdd, .archive, .children]
        let sources: [AdminInboxLogic.Source] = [.registration, .profile, .familyTree, .profile, .familyTree, .content]
        return kinds.enumerated().map { i, kind in
            F(kind: kind, source: sources[i % sources.count], inFlow: true, waiting: i % 3 != 1, urgent: i % 7 == 0,
              late: i % 5 == 4)
        }
    }()

    private static let set = AdminAllRequestsView.inboxFilterSet(facts: facts, ready: true, workflowOn: true,
                                                                 roleKinds: Set(AdminInboxLogic.Kind.allCases))

    private struct Day: Identifiable {
        let title: String
        let rows: [AdminInboxRowModel]
        var id: String { title }
    }

    private static func row(_ name: String, _ icon: String, _ fill: Color, _ time: String, _ ask: String,
                            pills: [AdminInboxRowModel.Pill] = [], word: String, mine: Bool, new: Bool = false)
        -> AdminInboxRowModel {
        AdminInboxRowModel(name: name, avatarName: name, avatarURL: nil, typeIcon: icon, typeFill: fill, time: time,
                           ask: ask, pills: pills, stateWord: word, stateTone: mine ? .mine : .neutral, isNew: new)
    }

    private let days: [Day] = [
        Day(title: "اليوم", rows: [
            row("سالم أحمد يوسف المحمدعلي", "leaf.fill", DS.Color.deceasedFill, "8:40 ص",
                "يبلّغ عن وفاة: علي حسن محمد", pills: [.init(title: "عاجل", tone: .error)], word: "عند المختص",
                mine: false, new: true),
            row("بدر خالد ناصر المحمدعلي", "person.badge.plus", DS.Color.palmFill, "9:12 ص",
                "يطلب إضافة ابن: ليلى", word: "بانتظار قرارك", mine: true),
            row("نورة سالم أحمد يوسف", "person.fill", DS.Color.femaleFill, "10:05 ص",
                "طلب انضمام · أنثى · تُربط بشجرة النساء", word: "عند المختص", mine: false),
        ]),
        Day(title: "أمس", rows: [
            row("علي حسن محمد المحمدعلي", "phone.fill", DS.Color.seaFill, "7:15 م", "يطلب تغيير رقمه",
                pills: [.init(title: "متأخر", tone: .warn)], word: "بانتظار قرارك", mine: true),
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                AdminInboxBand(backTitle: "الإدارة", onBack: {}, items: [
                    AdminHeaderItem(id: "waiting", value: 5, label: "بانتظار قرارك", tap: .action {}),
                    AdminHeaderItem(id: "urgent", value: 2, label: "عاجل", tap: .action {}),
                    AdminHeaderItem(id: "late", value: 1, label: "متأخر", tap: .action {}),
                ]) {
                    AdminGlassCircle(symbol: "gearshape")
                    AdminHeaderTextButton(title: selecting ? "إلغاء" : "تحديد") {}
                }
                VStack(alignment: .leading, spacing: DS.Hub.stackSpacing) {
                    if !selecting {
                        AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                            AdminInboxDoorRow(icon: "bubble.left.and.bubble.right.fill", tint: DS.Color.sea,
                                              title: AdminInboxView.title,
                                              subtitle: AdminInboxText.messagesLine(unread: 7, awaiting: 2)) {}
                            AdminInboxDoorRow(icon: "checkmark.shield.fill", tint: DS.Color.accent,
                                              title: "بانتظار المراجعة", subtitle: AdminInboxText.postReviewLine(3)) {}
                        }
                        AdminFilterPanel(set: Self.set, selection: $filters, search: $search,
                                         note: L10n.t("الأحدث أولاً", "Newest first"),
                                         openFilters: { showsFilters = true })
                    }
                    ForEach(days) { day in
                        VStack(alignment: .leading, spacing: DSNoticeMetrics.headerGap) {
                            DSDayHeader(title: day.title, count: day.rows.count)
                            VStack(spacing: 0) {
                                ForEach(Array(day.rows.enumerated()), id: \.offset) { index, model in
                                    let id = (day.title == "اليوم" ? 0 : 10) + index
                                    AdminInboxRow(model: model, position: DSGroupPosition(index: index, count: day.rows.count),
                                                  selecting: selecting, picked: picked.contains(id))
                                        .onTapGesture {
                                            guard selecting else { return }
                                            if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
                                        }
                                }
                            }
                        }
                    }
                    if !selecting {
                        AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                            AdminInboxDoorRow(icon: "checkmark.circle.fill", tint: DS.Color.palm,
                                              title: AdminInboxHandledPage.title, subtitle: "آخر 30 يوماً، للاطلاع",
                                              value: "48") {}
                        }
                        .padding(.top, DS.Hub.sectionGap - DS.Hub.stackSpacing)
                    }
                }
                .dsPageMargin()
                .padding(.top, DS.Spacing.lg)
                .padding(.bottom, DS.Hub.pageBottom)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting {
                AdminInboxSelectionBar(count: picked.count, allPicked: picked.count == 4, canPickAll: true,
                                       canReject: true, busy: false, onToggleAll: {}, onApprove: {}, onReject: {})
            }
        }
        .background(DS.Hub.background.ignoresSafeArea())
        .adminFilterSheet(isPresented: $showsFilters, set: Self.set, selection: $filters)
        .task {
            guard opensSheet, !showsFilters else { return }
            try? await Task.sleep(nanoseconds: 400_000_000)
            showsFilters = true
        }
    }
}

struct AdminTrailPreviewScreen: View {
    let mode: String
    @State private var open = true

    private func lookup(_ id: UUID) -> FamilyMember? { PreviewData.people[id] }

    private func senderInfo(recorded: Bool) -> AdminSenderInfo {
        let sender = PreviewData.people[PreviewData.senderId]!
        let subject = PreviewData.people[PreviewData.subjectId]
        let request = PreviewData.request(status: "pending", recorded: recorded)
        let steps = AdminTrailText.pathSteps(recorded: request?.sentFrom,
                                             inferred: "الشجرة ← تفاصيل نورة سالم أحمد ← طلب إضافة")
        return AdminSenderInfo(
            steps: steps,
            sender: [sender.fourPartName, AdminTrailText.roleName(sender.role),
                     recorded ? AdminTrailText.relation(sender: sender, subject: subject) : nil]
                .compactMap { $0 }.joined(separator: " · "),
            device: AdminTrailText.device(request?.sentVia),
            deviceRecorded: request?.sentVia != nil,
            time: DateHelper.displayDateTime(request?.sentVia?.at ?? request?.createdAt) ?? AdminTrailText.notRecorded)
    }

    private var infoSection: some View {
        DSComposerSection(title: L10n.t("بيانات الطلب", "Request Info"), icon: "doc.text.fill",
                          tint: AppSection.admin.ink, index: 1) {
            DSTileGrid([
                .wide(DSFieldTileFace(label: "الابن أو البنت", value: "ليلى", glyph: .none)),
                .half(DSFieldTileFace(label: "الجنس", value: "أنثى", glyph: .none)),
                .half(DSFieldTileFace(label: "الأم", value: "نورة سالم أحمد", glyph: .none)),
            ])
        }
    }

    var body: some View {
        ZStack {
            DS.Hub.background.ignoresSafeArea()
            if mode == "filters" {
                InboxRootPreview()
            } else if mode == "filtersheet" {
                InboxRootPreview(opensSheet: true)
            } else if mode == "select" {
                InboxRootPreview(selecting: true)
            } else if mode == "buttons" {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        DSBoxSectionTitle(title: "بطاقة طلب في «الوارد» (مدمج)", icon: "tray.full")
                        DSDecisionRow(items: [
                            DSDecisionItem(id: "a", title: "موافقة", kind: .primary) {},
                            DSDecisionItem(id: "d", title: "التفاصيل") {},
                            DSDecisionItem(id: "r", title: "رفض", icon: "xmark", kind: .destructive, tint: DS.Color.reject) {},
                        ])
                        DSBoxSectionTitle(title: "طلب في المسار ينتظرك", icon: "point.topleft.down.to.point.bottomright.curvepath")
                        DSDecisionRow(items: [
                            DSDecisionItem(id: "f", title: "اعتماد الطلب", kind: .primary) {},
                            DSDecisionItem(id: "r", title: "رفض", icon: "xmark", kind: .destructive, tint: DS.Color.reject) {},
                        ])
                        DSBoxSectionTitle(title: "طلب تعديل الشجرة", icon: "tree")
                        DSDecisionRow(items: [
                            DSDecisionItem(id: "a", title: "موافقة", icon: "checkmark.circle.fill", kind: .primary) {},
                            DSDecisionItem(id: "r", title: "رفض", icon: "xmark", kind: .destructive, tint: DS.Color.reject) {},
                        ])
                        DSBoxSectionTitle(title: "إشعار مجدول (المناسبات)", icon: "calendar")
                        DSDecisionRow(items: [
                            DSDecisionItem(id: "e", title: "تعديل", icon: "pencil") {},
                            DSDecisionItem(id: "c", title: "إلغاء الموعد", icon: "xmark", kind: .destructive, tint: DS.Color.reject) {},
                        ])
                        DSBoxSectionTitle(title: "مربّع مسار الموافقات (عادي)", icon: "checkmark.seal")
                        DSDecisionRow(items: [
                            DSDecisionItem(id: "ask", title: "اسأل العضو عن ناقص", icon: "questionmark.bubble.fill") {},
                            DSDecisionItem(id: "ret", title: "إرجاع للمختص", icon: "arrow.uturn.backward") {},
                        ], size: .regular)
                        DSDecisionRow(items: [
                            DSDecisionItem(id: "p", title: "اعتماد", kind: .primary) {},
                            DSDecisionItem(id: "r", title: "رفض", kind: .reject) {},
                            DSDecisionItem(id: "c", title: "إغلاق", icon: "xmark", kind: .dismiss) {},
                        ], size: .regular)
                    }
                    .dsPageMargin()
                    .padding(.top, DS.Page.top)
                }
            } else if mode == "list" {
                // «المنجز» (U8، spec C.5): صفوف الصفحة الحقيقية من طلبات وهمية
                ScrollView {
                    VStack(alignment: .leading, spacing: DSNoticeMetrics.headerGap) {
                        DSDayHeader(title: L10n.t("اليوم", "Today"), count: 3)
                        VStack(spacing: 0) {
                            ForEach(["approved", "rejected", "approved"].indices, id: \.self) { i in
                                if let r = PreviewData.request(status: ["approved", "rejected", "approved"][i], recorded: i != 2,
                                                               type: i == 2 ? "contact_message" : "tree_edit",
                                                               reply: i == 1 ? "الاسم غير مطابق" : nil) {
                                    let events = i == 0 ? PreviewData.events : nil
                                    AdminInboxRow(model: AdminInboxHandledPage.rowModel(
                                                    .request(r), events: events,
                                                    date: DateHelper.parse(AdminTrailText.handledAt(r, events: events)) ?? Date(),
                                                    lookup: lookup),
                                                  position: DSGroupPosition(index: i, count: 3))
                                }
                            }
                        }
                    }
                    .dsPageMargin()
                    .padding(.top, DS.Page.top)
                }
            }
        }
        .dsCenterBox(isPresented: Binding(get: { open && !["list", "buttons", "filters", "filtersheet", "select"].contains(mode) },
                                          set: { open = $0 })) {
            box
        }
    }

    @ViewBuilder private var box: some View {
        switch mode {
        case "handled":
            let r = PreviewData.request(status: "approved", recorded: true)!
            DSComposer(title: AdminTrailText.typeTitle(r),
                       subtitle: AdminTrailText.Decision.approved.title + " · " + (DateHelper.displayDateTime(r.repliedAt) ?? ""),
                       icon: AdminTrailText.typeIcon(r), tint: DS.Color.actionNavy, actionTitle: "", showsAction: false,
                       cancelTitle: L10n.t("إغلاق", "Close"), canSubmit: false, onSubmit: {}, onCancel: {}) {
                infoSection
                AdminSenderSection(info: senderInfo(recorded: true), index: 2)
                AdminHandlingSections(request: r, events: PreviewData.events, lookup: lookup, startIndex: 3)
            }
        default:
            let recorded = mode != "fallback"
            DSComposer(title: "طلب إضافة", subtitle: recorded ? "شجرة النساء" : "الشجرة",
                       icon: "person.badge.plus", tint: DS.Color.actionNavy,
                       actionTitle: L10n.t("قبول", "Approve"), cancelTitle: L10n.t("إغلاق", "Close"), canSubmit: true,
                       extraActions: [
                           DSComposerAction(id: "phone", title: L10n.t("تعديل / إضافة رقم فعلي", "Edit / Add real number"),
                                            icon: "phone.badge.plus", role: .cancel, fullRow: true) {},
                           DSComposerAction(id: "reject", title: L10n.t("رفض", "Reject"), icon: "xmark",
                                            role: .destructive, tint: DS.Color.reject) {},
                       ],
                       decisionFooter: true, onSubmit: {}, onCancel: {}) {
                infoSection
                AdminSenderSection(info: senderInfo(recorded: recorded), index: 2)
            }
        }
    }
}
#endif
