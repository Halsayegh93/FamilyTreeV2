import SwiftUI

// MARK: - مربّع تفاصيل الإشعار (المركز و«إشعارات الإدارة») — التصميم الغني ٢٠٢٦-١١-٠١
//
// يجمع `NotificationRichBox` بمحتوى الإشعار: الاقتباس ← الطلب (يُجلب من `request_id`) ← التغييرات ← العضو المعني
// (للإدارة) ← أقسام النوع من المركز (`extra`: تطابقات الانضمام، مسار الموافقات، رسائل الدخول) ← أزرار السياق.
// القرار على الطلب = دوال «الوارد» نفسها (`AdminRequestViewModel+NotificationBox`).

struct NotificationDetailBox: View {
    let notification: AppNotification
    /// الإدارة (`canModerate`) — العضو لا يرى اسم أحد من الإدارة ولا صورته
    let isStaff: Bool
    let sender: NotificationSenderInfo
    let kindLabel: String
    let kindIcon: String
    let time: String
    /// النص كاملاً (المركز يمرّر عرضه بالأسماء الملوّنة) — nil = بلا نص
    let quote: AnyView?
    let changes: [AppNotification.NotificationDetails.ChangeEntry]
    let subjectMember: FamilyMember?
    let subjectName: String?
    /// أقسام النوع الخاصة بالمركز
    var extra: AnyView? = nil
    let onClose: () -> Void
    /// العضو: «حسابي» (طلباتي، التصحيح، ملفي)
    let onOpenProfile: () -> Void
    /// الإدارة: الطلب في «الوارد»
    let onOpenRequest: (UUID) -> Void
    /// «فتح الخبر»
    let onOpenNews: (UUID) -> Void

    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    @State private var request: AdminRequest? = nil
    @State private var busy = false
    @State private var confirmReject = false
    @State private var rejectReason = ""
    @State private var openMember: FamilyMember? = nil
    @State private var errorText: String? = nil

    /// معرّف الطلب — طلبات الانضمام/الربط تحمل معرّف الملف لا الطلب (لها قسم التطابقات)
    private var requestId: UUID? {
        let k = notification.kind
        if k == RequestType.joinRequest.rawValue || k == NotificationKind.linkRequest.rawValue
            || k == RequestType.linkRequest.rawValue { return nil }
        return AdminNotices.requestId(of: notification)
    }

    var body: some View {
        NotificationRichBox(chips: chips, tile: tile, title: notification.title, subtitle: subtitle,
                            onClose: onClose, content: content)
            .task(id: notification.id) {
                guard let rid = requestId else { return }
                request = await adminRequestVM.fetchRequest(id: rid)
            }
            .fullScreenCover(item: $openMember) { m in
                MemberDetailsView(member: m, centered: true)
                    .background(ClearPresentationBackground())
            }
            .transaction { t in if openMember != nil { t.disablesAnimations = true } }
            .dsAlert(L10n.t("رفض الطلب؟", "Reject this request?"), isPresented: $confirmReject, icon: "xmark.circle.fill") {
                TextField(L10n.t("سبب الرفض (اختياري)", "Reason (optional)"), text: $rejectReason)
                    .dsAlertField()
                    .layoutValue(key: DSAlertIsFieldKey.self, value: true)
                Button(L10n.t("رفض", "Reject"), role: .destructive) { reject() }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.t("يصل صاحب الطلب إشعار بالرفض.", "The requester will be notified."))
            }
            .dsAlert(L10n.t("تعذّر التنفيذ", "Couldn't complete"),
                     isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button(L10n.t("حسناً", "OK")) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
    }

    // MARK: الرأس

    private var chips: [(String, NotifBoxTone)] {
        var list: [(String, NotifBoxTone)] = [(request.map { NotifBoxText.requestType($0.requestType) } ?? kindLabel, .gold)]
        if let r = request { list.append(statusChip(r)) }
        return list
    }

    private func statusChip(_ r: AdminRequest) -> (String, NotifBoxTone) {
        switch r.status {
        case ApprovalStatus.approved.rawValue: return (L10n.t("مقبول", "Approved"), .success)
        case ApprovalStatus.rejected.rawValue: return (L10n.t("مرفوض", "Rejected"), .danger)
        default:
            if isStaff, let sent = NotifBoxText.date(r.createdAt) {
                return (L10n.t("ينتظر قرارك · \(NotifBoxText.relative(sent))", "Awaiting you · \(NotifBoxText.relative(sent))"),
                        .pending)
            }
            return (L10n.t("قيد المراجعة", "Under review"), .pending)
        }
    }

    private var tile: NotifBoxTile {
        if let r = request, !isStaff {
            switch r.status {
            case ApprovalStatus.approved.rawValue: return .glyph("checkmark.circle")
            case ApprovalStatus.rejected.rawValue: return .glyph("xmark.circle")
            default: break
            }
        }
        // الإدارة: دائرة العضو المرسل/مقدّم الطلب — العضو يرى رمز النوع دائماً
        if isStaff {
            if let r = request, let m = memberVM.member(byId: r.requesterId) {
                return .member(name: m.firstName, avatarUrl: m.avatarUrl)
            }
            if sender.isMember { return .member(name: sender.name, avatarUrl: sender.avatarUrl) }
        }
        return .glyph(sender.isMember ? kindIcon : sender.glyph)
    }

    private var subtitle: String { sender.headerLine(time: time) }

    // MARK: المحتوى

    private var content: AnyView {
        AnyView(VStack(alignment: .leading, spacing: DS.Spacing.md + DS.Spacing.xxs) {
            if let quote { NotifQuoteCard(text: quote) }
            if let r = request {
                if isStaff {
                    NotifAdminRequestSection(request: r, notification: notification, busy: busy,
                                             canApprove: adminRequestVM.canApproveFromBox(r),
                                             canReject: adminRequestVM.canRejectFromBox(r),
                                             onApprove: approve, onReject: { confirmReject = true },
                                             onOpen: { onOpenRequest(r.id) })
                } else {
                    NotifMemberRequestSection(request: r, notification: notification, onOpenProfile: onOpenProfile)
                }
            }
            if !changes.isEmpty {
                NotifBoxLabel(text: L10n.t("التغييرات (\(changes.count))", "Changes (\(changes.count))"))
                NotificationChangeCards(changes: changes, isStaff: isStaff, subjectName: subjectName ?? "")
            }
            if isStaff, let name = subjectName, request == nil || subjectMember?.id != request?.requesterId {
                NotifBoxLabel(text: L10n.t("العضو المعني", "Member concerned"))
                Button { openMember = subjectMember } label: {
                    NotificationSubjectCard(name: name, avatarUrl: subjectMember?.avatarUrl,
                                            isWomenTree: notification.details?.tree == "women")
                }
                .buttonStyle(DSScaleButtonStyle())
                .disabled(subjectMember == nil)
            }
            if let extra { extra }
            footer
        })
    }

    @ViewBuilder
    private var footer: some View {
        // تغييرات: الإدارة «فتح ملف العضو»، والعضو «عرض ملفي» + ملاحظة التصحيح
        if !changes.isEmpty {
            if isStaff, let m = subjectMember {
                NotifButtonRow(items: [.init(title: L10n.t("فتح ملف العضو", "Open member profile"), kind: .primary) {
                    openMember = m
                }])
            } else if !isStaff {
                NotifButtonRow(items: [.init(title: L10n.t("عرض ملفي", "View my profile"), kind: .primary,
                                             action: onOpenProfile)])
                Text(L10n.t("لو فيه شي غلط، اطلب تصحيحه من ملفك وبتوصل للإدارة.",
                            "If something is wrong, request a correction from your profile and it will reach the administration."))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // خبر
        if let nid = notification.details?.newsId.flatMap(UUID.init(uuidString:)) {
            NotifButtonRow(items: [.init(title: L10n.t("فتح الخبر", "Open post"), kind: .secondary) { onOpenNews(nid) }])
        }
    }

    // MARK: القرار (دوال «الوارد» نفسها)

    private func approve() {
        guard let r = request, !busy else { return }
        busy = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            adminRequestVM.errorMessage = nil
            let ok = await adminRequestVM.approveFromBox(r)
            await finish(ok: ok, rid: r.id)
        }
    }

    private func reject() {
        guard let r = request, !busy else { return }
        busy = true
        let reason = rejectReason
        rejectReason = ""
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            adminRequestVM.errorMessage = nil
            await adminRequestVM.rejectFromBox(r, reason: reason)
            await finish(ok: true, rid: r.id)
        }
    }

    /// بعد القرار: يُعاد جلب الطلب فتظهر حالته الجديدة (أو رسالة الخطأ من الدالة)
    private func finish(ok: Bool, rid: UUID) async {
        // القرار يُطبَّق بتفاؤل ثم على السيرفر — مهلة قصيرة قبل إعادة القراءة
        try? await Task.sleep(nanoseconds: 900_000_000)
        request = await adminRequestVM.fetchRequest(id: rid) ?? request
        busy = false
        if let msg = adminRequestVM.errorMessage {
            errorText = msg
            adminRequestVM.errorMessage = nil
        } else if !ok {
            errorText = L10n.t("هذا الطلب يُكمل من «الوارد».", "Finish this request from the inbox.")
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

// MARK: - العضو: رحلة الطلب

struct NotifMemberRequestSection: View {
    let request: AdminRequest
    let notification: AppNotification
    let onOpenProfile: () -> Void

    private var sent: Date? { NotifBoxText.date(request.createdAt) }
    private var decided: Date? { NotifBoxText.date(request.repliedAt) ?? NotifBoxText.date(request.approvedAt) }

    private var steps: [NotifJourneyStep] {
        var list = [NotifJourneyStep(title: L10n.t("أرسلت الطلب", "You sent the request"),
                                     subtitle: sent.map(NotifBoxText.long) ?? "", tone: .neutral)]
        switch request.status {
        case ApprovalStatus.approved.rawValue, ApprovalStatus.rejected.rawValue:
            let took: String = {
                guard let s = sent, let d = decided, d > s else { return "" }
                return NotifBoxText.within(d.timeIntervalSince(s))
            }()
            list.append(NotifJourneyStep(title: L10n.t("راجعته الإدارة", "Reviewed by the administration"),
                                         subtitle: took, tone: .neutral))
            let approved = request.status == ApprovalStatus.approved.rawValue
            list.append(NotifJourneyStep(title: approved ? L10n.t("مقبول", "Approved") : L10n.t("مرفوض", "Rejected"),
                                         subtitle: NotifBoxText.long(decided ?? notification.createdDate),
                                         tone: approved ? .success : .danger))
        default:
            list.append(NotifJourneyStep(title: L10n.t("قيد المراجعة", "Under review"), subtitle: "", tone: .pending))
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md + DS.Spacing.xxs) {
            NotifJourneyView(steps: steps)
            if let reply = request.adminReply?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty {
                NotifReplyCard(text: reply)
            }
            NotifInfoGrid(cells: [
                NotifInfoCell(label: L10n.t("نوع الطلب", "Request type"), value: NotifBoxText.requestType(request.requestType)),
                NotifInfoCell(label: L10n.t("وصلك", "Received"), value: NotifBoxText.short(notification.createdDate)),
            ])
            buttons
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch request.status {
        case ApprovalStatus.rejected.rawValue:
            // «طلب جديد بالتصحيح» و«طلباتي» — كلاهما في «حسابي» (لا مدخل مباشر لكل نوع طلب)
            NotifButtonRow(items: [
                .init(title: L10n.t("طلب جديد بالتصحيح", "New corrected request"), kind: .primary, action: onOpenProfile),
                .init(title: L10n.t("طلباتي", "My requests"), kind: .secondary, action: onOpenProfile),
            ])
        case ApprovalStatus.approved.rawValue:
            NotifButtonRow(items: [.init(title: L10n.t("عرض ملفي", "View my profile"), kind: .primary, action: onOpenProfile)])
        default:
            NotifButtonRow(items: [.init(title: L10n.t("طلباتي", "My requests"), kind: .secondary, action: onOpenProfile)])
        }
    }
}

// MARK: - الإدارة: تفاصيل الطلب والقرار

struct NotifAdminRequestSection: View {
    let request: AdminRequest
    let notification: AppNotification
    let busy: Bool
    let canApprove: Bool
    let canReject: Bool
    let onApprove: () -> Void
    let onReject: () -> Void
    let onOpen: () -> Void

    @EnvironmentObject var memberVM: MemberViewModel

    private var requester: FamilyMember? { memberVM.member(byId: request.requesterId) }
    private var pending: Bool { request.status == ApprovalStatus.pending.rawValue }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if let m = requester { requesterRow(m) }
            let cells = NotifRequestCells.cells(for: request, memberVM: memberVM)
            if !cells.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    NotifBoxLabel(text: L10n.t("تفاصيل الطلب", "Request details"))
                    NotifInfoGrid(cells: cells)
                }
                .padding(DS.Spacing.md)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Color.cardBorder, lineWidth: DS.Border.width))
            }
            if let line = NotifRequestCells.context(for: request, memberVM: memberVM) {
                NotifContextLine(icon: "plus", text: line)
            }
            let tags = self.tags
            if !tags.isEmpty {
                NotifFlow { ForEach(Array(tags.enumerated()), id: \.offset) { _, t in NotifTagChip(text: t.0, tone: t.1) } }
            }
            if let sent = NotifBoxText.date(request.createdAt) {
                NotifMetaLine(text: L10n.t("أُرسل \(NotifBoxText.long(sent))", "Sent \(NotifBoxText.long(sent))"))
            }
            decision
        }
    }

    private func requesterRow(_ m: FamilyMember) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSMemberAvatar(name: m.firstName, avatarUrl: m.avatarUrl, size: DS.Icon.row, roleColor: m.roleColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: m.shortFullName)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                Text(L10n.t("مقدّم الطلب", "Requester"))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textSecondary)
            }
            Spacer(minLength: 0)
            DSStatusChip(text: m.roleName, tint: m.roleColor, size: .mini)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
        .accessibilityElement(children: .combine)
    }

    private var tags: [(String, NotifBoxTone)] {
        var list: [(String, NotifBoxTone)] = []
        if let stage = request.stage, pending { list.append((NotifBoxText.stage(stage), .neutral)) }
        if let a = request.assignedTo, pending, let m = memberVM.member(byId: a) {
            list.append((L10n.t("مسند إلى: \(m.firstName)", "Assigned to: \(m.firstName)"), .neutral))
        }
        if let p = request.priority, pending {
            list.append(p == "urgent" ? (L10n.t("عاجل", "Urgent"), .danger) : (L10n.t("أولوية عادية", "Normal priority"), .pending))
        }
        if request.fastTrack == true, pending { list.append((L10n.t("اعتماد مباشر", "Fast track"), .gold)) }
        return list
    }

    private var decision: AnyView {
        if pending && (canApprove || canReject) {
            var items: [NotifButtonRow.Item] = []
            if canApprove { items.append(.init(title: L10n.t("موافقة", "Approve"), kind: .approve, disabled: busy, action: onApprove)) }
            if canReject { items.append(.init(title: L10n.t("رفض", "Reject"), kind: .reject, disabled: busy, action: onReject)) }
            items.append(.init(title: L10n.t("رد / سؤال", "Reply / ask"), kind: .secondary, disabled: busy, action: onOpen))
            return AnyView(VStack(spacing: 0) {
                NotifButtonRow(items: items)
                NotifTextLink(title: L10n.t("فتح الطلب كامل", "Open full request"), action: onOpen)
            })
        } else {
            return AnyView(NotifButtonRow(items: [.init(title: L10n.t("فتح الطلب كامل", "Open full request"),
                                                         kind: pending ? .primary : .secondary, action: onOpen)]))
        }
    }
}

// MARK: - قيم الطلب

enum NotifRequestCells {
    private static func clean(_ s: String?) -> String? {
        let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    /// النص الحرّ في `details` (لا JSON)
    private static func freeText(_ s: String?) -> String? {
        guard let t = clean(s), !t.hasPrefix("{"), !t.hasPrefix("[") else { return nil }
        return t
    }

    static func cells(for r: AdminRequest, memberVM: MemberViewModel) -> [NotifInfoCell] {
        var list: [NotifInfoCell] = []
        func add(_ label: String, _ value: String?, _ highlighted: Bool = false) {
            if let v = clean(value) { list.append(NotifInfoCell(label: label, value: v, highlighted: highlighted)) }
        }
        let memberName = r.member?.shortFullName ?? memberVM.member(byId: r.memberId)?.shortFullName
        switch r.requestType {
        case RequestType.treeEdit.rawValue:
            if let p = r.treeEditPayload {
                add(L10n.t("الإجراء", "Action"), p.resolvedAction.map { L10n.t($0.arabicLabel, $0.englishLabel) } ?? p.action)
                add(L10n.t("العضو", "Member"), p.targetMemberName)
                add(L10n.t("تحت", "Under"), p.parentMemberName)
                add(L10n.t("الاسم", "Name"), p.newMemberName, true)
                add(L10n.t("الاسم الجديد", "New name"), p.newName, true)
                add(L10n.t("الرقم الجديد", "New phone"), p.newPhone, true)
                add(L10n.t("الميلاد", "Birth date"), p.newBirthDate, true)
                add(L10n.t("تاريخ الوفاة", "Death date"), p.deathDate, true)
                add(L10n.t("السبب", "Reason"), p.reason)
                add(L10n.t("ملاحظات", "Notes"), p.notes)
            } else {
                add(L10n.t("الطلب", "Request"), r.newValue, true)
                add(L10n.t("التفاصيل", "Details"), freeText(r.details))
            }
        case RequestType.childAdd.rawValue:
            let child = r.newValue.flatMap(UUID.init(uuidString:)).flatMap { memberVM.member(byId: $0) }
            add(L10n.t("الاسم", "Name"), child?.firstName, true)
            add(L10n.t("الميلاد", "Birth date"), child?.birthDate.map { String($0.prefix(10)) })
            let father = child?.fatherId.flatMap { memberVM.member(byId: $0) } ?? memberVM.member(byId: r.requesterId)
            add(L10n.t("الأب", "Father"), father?.shortFullName)
        case RequestType.nameChange.rawValue:
            add(L10n.t("الاسم الحالي", "Current name"), r.member?.fullName ?? memberName)
            add(L10n.t("الاسم الجديد", "New name"), r.newValue, true)
        case RequestType.familyChange.rawValue:
            add(L10n.t("العضو", "Member"), memberName)
            add(L10n.t("العائلة الجديدة", "New family"), r.newValue, true)
        case RequestType.phoneChange.rawValue:
            add(L10n.t("العضو", "Member"), memberName)
            add(L10n.t("الرقم الجديد", "New phone"), r.newValue, true)
        case RequestType.deceasedReport.rawValue:
            add(L10n.t("العضو", "Member"), memberName)
            add(L10n.t("تاريخ الوفاة", "Death date"), r.newValue, true)
            add(L10n.t("التفاصيل", "Details"), freeText(r.details))
        case RequestType.newsReport.rawValue, RequestType.contentReport.rawValue:
            add(L10n.t("السبب", "Reason"), freeText(r.details))
        case RequestType.photoSuggestion.rawValue:
            add(L10n.t("العضو", "Member"), memberName)
            add(L10n.t("التفاصيل", "Details"), freeText(r.details))
        default:
            add(L10n.t("العضو", "Member"), memberName)
            add(L10n.t("القيمة المطلوبة", "Requested value"),
                r.newValue.flatMap { UUID(uuidString: $0) == nil ? $0 : nil }, true)
            add(L10n.t("التفاصيل", "Details"), freeText(r.details))
        }
        return list
    }

    /// سطر السياق — «إضافة ابن»: ترتيبه بين أبناء أبيه في الشجرة
    static func context(for r: AdminRequest, memberVM: MemberViewModel) -> String? {
        guard r.requestType == RequestType.childAdd.rawValue,
              let childId = r.newValue.flatMap(UUID.init(uuidString:)),
              let child = memberVM.member(byId: childId),
              let fatherId = child.fatherId,
              let father = memberVM.member(byId: fatherId) else { return nil }
        let n = memberVM.allMembers.filter { $0.fatherId == fatherId }.count
        guard n > 0 else { return nil }
        return L10n.t("بيصير الابن رقم \(n) لـ\(father.firstName) في الشجرة",
                      "Will be child #\(n) of \(father.firstName) in the tree")
    }
}
