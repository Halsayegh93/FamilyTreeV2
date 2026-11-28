import SwiftUI

// MARK: - «طلبات عنه» في «إجراءات الإدارة» (كرت العضو v3، الوحدة V3)
//
// طلبات المراجعة المعلّقة عن هذا العضو (`member_id` أو `details.targetMemberId` هو، وطلبات شجرة النساء عن عقدته —
// `AdminMemberCardLogic.isAbout`) من مخازن «الوارد» نفسها (`AdminRequestViewModel`). لكل طلب: المرسل، ما يطلبه، القديم ←
// الجديد (ومصغّرتان للصورة)، والوقت. الأزرار بقاعدة واحدة (`AdminMemberCardLogic.requestActions`):
//   • «موافقة…» تعرض المعاينة ثم تؤكّد — `approveFromBox` = `approveFromPush` = دالة النوع ← `decide_admin_request`
//     (نفس صلاحيات «الوارد»: `canApproveFromBox`).
//   • «رفض» يسأل عن السبب كما في «الوارد» — `rejectFromBox` (`canRejectFromBox`).
//   • «فتح في الوارد ‹» دائماً (`MemberPendingRequestsLink`) — والطلب داخل مسار الموافقات (مرحلة) يعرضه وحده، وكذلك
//     كل نوع لا يقرّره الشريط (`AdminMemberCardLogic.boxDecidableTypes`): «تغيير الرقم» (`phoneChangeRequests`، م٢)،
//     وطلب انضمام صاحب الورقة المعلّق، و«الصلة بالعائلة»…
// بلا طلبات: «لا طلبات عنه/عنها الآن». الشريط وكل طلب لهما `.id` تقفز إليه الرقاقة وشارات «طلب» في الصفوف.
// على ورقتك لا شريط ولا شارة (م١ — `AdminMemberCardLogic.showsRequests`).

@MainActor
enum AdminMemberCardRequests {
    static let stripAnchor = "member-card-requests"

    static func anchor(_ id: UUID) -> String { "member-card-request-\(id.uuidString)" }

    /// الطلبات المعلّقة عنه من مخازن «الوارد»، الأحدث أولاً وبلا تكرار — ومعها طلبات تغيير الرقم (نموذجها
    /// `PhoneChangeRequest`) وطلب انضمامه المعلّق، «فتح في الوارد» وحده
    static func about(_ m: FamilyMember, nodeId: UUID?, vm: AdminRequestViewModel) -> [AdminRequest] {
        let pools: [[AdminRequest]] = [vm.treeEditRequests, vm.deceasedRequests, vm.nameChangeRequests,
                                       vm.photoSuggestionRequests, vm.childAddRequests, vm.lineageRequests,
                                       vm.relativeAddRequests, vm.relativeRemoveRequests,
                                       vm.phoneChangeRequests.map(asAdminRequest), joinRequest(m, vm: vm)]
        var seen = Set<UUID>()
        return pools.joined()
            .filter { $0.status == ApprovalStatus.pending.rawValue }
            .filter { r in
                let payload = r.treeEditPayload
                return AdminMemberCardLogic.isAbout(personId: m.id, nodeId: nodeId, requestMemberId: r.memberId,
                                                    targetMemberId: payload?.targetMemberId,
                                                    womenNodeId: payload?.womenNodeId)
            }
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
    }

    /// طلب تغيير الرقم بنموذج الشريط (الأعمدة نفسها في `admin_requests`)
    static func asAdminRequest(_ p: PhoneChangeRequest) -> AdminRequest {
        AdminRequest(id: p.id, memberId: p.memberId, requesterId: p.requesterId ?? p.memberId, requestType: p.requestType,
                     newValue: p.newValue, status: p.status, details: p.details, createdAt: p.createdAt, member: p.member,
                     stage: p.stage)
    }

    /// طلب انضمام صاحب الورقة المعلّق (الدور «طلب انضمام»): صفّه في «الوارد» بمرحلته إن كان المسار شغّالاً، وإلا بمعرّف
    /// العضو نفسه (`AdminAllRequestsView` يفتح صفّ العضو المعلّق بمعرّفه)
    static func joinRequest(_ m: FamilyMember, vm: AdminRequestViewModel) -> [AdminRequest] {
        guard m.role == .pending else { return [] }
        if let row = vm.joinApprovalRequests.first(where: { $0.memberId == m.id }) { return [row] }
        return [AdminRequest(id: m.id, memberId: m.id, requesterId: m.id, requestType: RequestType.joinRequest.rawValue,
                             status: ApprovalStatus.pending.rawValue, details: nil, createdAt: m.createdAt, member: m)]
    }

    static func key(_ r: AdminRequest) -> AdminMemberCardLogic.RequestKey {
        let payload = r.treeEditPayload
        return .init(type: r.requestType, action: payload?.action, womenKind: payload?.women?.kind)
    }

    static func row(_ r: AdminRequest) -> AdminCardRow? {
        let k = key(r)
        return AdminMemberCardLogic.row(type: k.type, action: k.action, womenKind: k.womenKind)
    }

    /// ما يطلبه بكلمات قصيرة
    static func title(_ r: AdminRequest) -> String {
        switch r.requestType {
        case RequestType.treeEdit.rawValue:
            let payload = r.treeEditPayload
            if payload?.women?.kind == "wife" { return L10n.t("إضافة زوجة", "Add a wife") }
            if payload?.women?.kind == "mother" { return L10n.t("إضافة أم", "Add a mother") }
            switch payload?.displayAction {
            case .editName: return L10n.t("تعديل الاسم", "Edit the name")
            case .editPhone: return L10n.t("تعديل الرقم", "Edit the number")
            case .editBirth: return L10n.t("تعديل تاريخ الميلاد", "Edit the birth date")
            case .deceased: return L10n.t("تسجيل وفاة", "Report a death")
            case .addDeathDate: return L10n.t("إضافة تاريخ الوفاة", "Add the death date")
            case .addPhoto: return L10n.t("إضافة صورة", "Add a photo")
            case .add: return L10n.t("إضافة ابن أو بنت", "Add a son or daughter")
            case .delete: return L10n.t("حذف من الشجرة", "Delete from the tree")
            case .other, .none: return L10n.t("طلب آخر", "Other request")
            }
        case RequestType.photoSuggestion.rawValue: return L10n.t("اقتراح صورة جديدة له", "A new photo suggested")
        case RequestType.deceasedReport.rawValue: return L10n.t("بلاغ وفاة", "Death report")
        case RequestType.nameChange.rawValue: return L10n.t("تغيير الاسم", "Name change")
        case RequestType.familyChange.rawValue: return L10n.t("تغيير اسم العائلة", "Family name change")
        case RequestType.childAdd.rawValue: return L10n.t("إضافة ابن", "Add a son")
        case DaughterSons.requestType: return L10n.t("طلب الصلة بالعائلة", "Relation to the family request")
        case RequestType.relativeAdd.rawValue: return L10n.t("إضافة قريبة", "Add a relative")
        case RequestType.relativeRemove.rawValue: return L10n.t("حذف قريب", "Remove a relative")
        case RequestType.phoneChange.rawValue: return L10n.t("تغيير رقم الهاتف", "Phone number change")
        case RequestType.joinRequest.rawValue, RequestType.linkRequest.rawValue:
            return L10n.t("طلب انضمام قيد المراجعة", "Join request under review")
        default: return L10n.t("طلب", "Request")
        }
    }

    static func icon(_ row: AdminCardRow?) -> (String, Color) {
        switch row {
        case .photo: return ("photo", DS.Color.sadu)
        case .birth: return ("calendar", DS.Color.primary)
        case .name: return ("textformat", DS.Color.primary)
        case .death: return ("calendar.badge.clock", DS.Color.deceased)
        case .phone: return ("phone", DS.Color.sea)
        case .children, .spouses, .mother, .father, .lineage, .visibility: return ("person.2", DS.Color.palm)
        default: return ("tray", DS.Color.slate)
        }
    }

    /// مرحلة مسار الموافقات بكلمة: «عند المراجِع»…
    static func stageWord(_ raw: String?) -> String? {
        guard let raw, let stage = ApprovalStage(rawValue: raw) else { return nil }
        switch stage {
        case .review: return L10n.t("عند المراجِع", "With the reviewer")
        case .info: return L10n.t("بانتظار معلومات", "Waiting for info")
        case .approve: return L10n.t("بانتظار الاعتماد", "Awaiting approval")
        case .execute: return L10n.t("جاهز للتنفيذ", "Ready to apply")
        }
    }
}

// MARK: - الشريط

struct AdminMemberRequestsStrip: View {
    let member: FamilyMember
    let requests: [AdminRequest]
    let byId: (UUID) -> FamilyMember?
    let openInbox: (AdminRequest) -> Void
    @EnvironmentObject private var adminRequestVM: AdminRequestViewModel
    @State private var approveTarget: AdminRequest?
    @State private var rejectTarget: AdminRequest?
    @State private var reason = ""
    @State private var working: UUID?
    @State private var failure: String?

    private var title: String {
        AdminMemberCardLogic.requestsTitle(count: requests.count, female: member.isFemale, arabic: L10n.isArabic)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(verbatim: title)
                .dsFont(.sectionTitle)
                .foregroundColor(DS.Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if requests.isEmpty {
                Text(verbatim: AdminMemberCardLogic.noRequests(female: member.isFemale, arabic: L10n.isArabic))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
            } else {
                ForEach(Array(requests.enumerated()), id: \.element.id) { index, r in
                    if index > 0 { AdminRowDivider() }
                    item(r).id(AdminMemberCardRequests.anchor(r.id))
                }
                Text(L10n.t("«موافقة» تعرض المعاينة قبل التنفيذ، والقرار هنا هو نداء «الوارد» نفسه. الطلب في مرحلة مراجعة، وتغيير الرقم والانضمام والصلة بالعائلة، تُفتح في «الوارد» فقط.",
                            "«Approve» previews before applying; the decision here is the inbox's own call. A request in a review stage, a phone change, a join or a relation request opens in the inbox only."))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Hub.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.cardBackgroundSoft)
        .id(AdminMemberCardRequests.stripAnchor)
        .modifier(AdminMemberRequestAlerts(approveTarget: $approveTarget, rejectTarget: $rejectTarget, reason: $reason,
                                           failure: $failure, preview: { change($0) },
                                           approve: approve, reject: reject))
    }

    // MARK: الطلب

    private func item(_ r: AdminRequest) -> some View {
        let row = AdminMemberCardRequests.row(r)
        let (icon, tint) = AdminMemberCardRequests.icon(row)
        let sender = byId(r.requesterId).flatMap { AdminMemberSheetLogic.firstName($0.firstName, full: $0.fullName) }
            ?? L10n.t("عضو", "A member")
        let when = DateHelper.relativeTime(from: r.createdAt)
        let actions = AdminMemberCardLogic.requestActions(type: r.requestType, stage: r.stage,
                                                          workflowOn: adminRequestVM.approvalsWorkflowOn,
                                                          canApprove: adminRequestVM.canApproveFromBox(r),
                                                          canReject: adminRequestVM.canRejectFromBox(r))
        return HStack(alignment: .top, spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: icon, tint: tint, filled: true)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(AdminMemberCardRequests.title(r))
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DS.Spacing.sm) {
                    Text(verbatim: [L10n.t("المرسل: \(sender)", "From: \(sender)"), when].filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let stage = AdminMemberCardRequests.stageWord(r.stage) {
                        AdminMemberTagPill(tag: AdminMemberTag(text: stage, tone: .family))
                    }
                }
                changeView(r, row: row)
                buttons(r, actions: actions)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.xs)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func changeView(_ r: AdminRequest, row: AdminCardRow?) -> some View {
        if row == .photo, let proposed = proposedPhoto(r) {
            HStack(spacing: DS.Spacing.sm) {
                photo(currentPhoto)
                Image(systemName: L10n.isArabic ? "arrow.left" : "arrow.right")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(DS.Color.textTertiary)
                photo(proposed)
                Text(L10n.t("الحالية ← المقترحة", "Current → proposed"))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(L10n.t("الصورة الحالية والصورة المقترحة", "Current and proposed photo")))
        } else if let text = change(r) {
            Text(verbatim: text)
                .dsFont(.body)
                .monospacedDigit()
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var currentPhoto: String? {
        [member.avatarUrl, member.photoURL].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }

    private func proposedPhoto(_ r: AdminRequest) -> String? {
        if r.requestType == RequestType.photoSuggestion.rawValue { return r.newValue }
        return r.treeEditPayload?.newPhotoUrl
    }

    private func photo(_ url: String?) -> some View {
        Group {
            if let url, let u = URL(string: url) {
                CachedAsyncImage(url: u) { image in image.resizable().scaledToFill() } placeholder: {
                    DS.Color.cardBackground
                }
            } else {
                Image(systemName: "person.fill")
                    .dsGlyph(DS.Glyph.xl)
                    .foregroundColor(DS.Color.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.Color.cardBackground)
            }
        }
        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    /// «27/12/1963 ← 27/12/1962» — القديم ثم الجديد، أو الجديد وحده
    private func change(_ r: AdminRequest) -> String? {
        let arrow = L10n.isArabic ? " ← " : " → "
        let payload = r.treeEditPayload
        func pair(_ old: String?, _ new: String?) -> String? {
            guard let new = new?.trimmingCharacters(in: .whitespacesAndNewlines), !new.isEmpty else { return nil }
            return AdminMemberCardLogic.value(old, arabic: L10n.isArabic) + arrow + new
        }
        switch r.requestType {
        case RequestType.treeEdit.rawValue:
            if let w = payload?.women {
                switch w.kind {
                case "edit_birth": return pair(AdminMemberSheetFacts.dayText(member.birthDate), AdminMemberSheetFacts.dayText(w.birth))
                case "edit_name": return pair(member.firstName, w.name)
                default: return w.name
                }
            }
            switch payload?.displayAction {
            case .editBirth: return pair(AdminMemberSheetFacts.dayText(member.birthDate), AdminMemberSheetFacts.dayText(payload?.newBirthDate))
            case .editName: return pair(member.fullName, payload?.newName)
            case .deceased, .addDeathDate:
                return AdminMemberSheetFacts.dayText(payload?.deathDate) ?? L10n.t("متوفى", "Deceased")
            case .add: return payload?.newMemberName
            case .editPhone: return L10n.t("رقم جديد", "A new number")
            default: return payload?.reason ?? payload?.notes
            }
        case RequestType.nameChange.rawValue, RequestType.familyChange.rawValue:
            return pair(member.fullName, r.newValue)
        case RequestType.phoneChange.rawValue:
            return L10n.t("رقم جديد — يُراجَع في «الوارد»", "A new number — reviewed in the inbox")
        default:
            return nil
        }
    }

    // MARK: الأزرار

    private func buttons(_ r: AdminRequest, actions: [AdminMemberCardLogic.RequestAction]) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            if working == r.id {
                ProgressView().scaleEffect(DS.Spinner.chipScale)
                    .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
            } else {
                ForEach(actions, id: \.self) { action in
                    switch action {
                    case .approve:
                        AdminPillButton(title: L10n.t("موافقة…", "Approve…"), style: .navy) { approveTarget = r }
                            .fixedSize()
                            .accessibilityHint(Text(L10n.t("يعرض المعاينة قبل التنفيذ", "Shows a preview first")))
                    case .reject:
                        AdminPillButton(title: L10n.t("رفض", "Reject"), style: .reject) { reason = ""; rejectTarget = r }
                            .fixedSize()
                            .accessibilityHint(Text(L10n.t("يسأل عن السبب", "Asks for a reason")))
                    case .openInbox:
                        Button { openInbox(r) } label: {
                            HStack(spacing: DS.Spacing.xxs) {
                                Text(L10n.t("فتح في الوارد", "Open in inbox")).dsFont(.chip)
                                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                                    .dsGlyph(DS.Glyph.xs, weight: .semibold)
                            }
                            .foregroundColor(DS.Color.accent)
                            .frame(minHeight: DS.Icon.tapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(DSPressStyle())
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: القرار — نداء «الوارد» نفسه

    private func approve(_ r: AdminRequest) {
        if DebugAdminProbe.dryRun("member card approveFromBox \(r.id)") {
            DSMomentToast.show(L10n.t("تمت الموافقة", "Approved"), moment: .approved)
            return
        }
        working = r.id
        adminRequestVM.errorMessage = nil
        Task { @MainActor in
            let ok = await adminRequestVM.approveFromBox(r)
            working = nil
            guard ok else {
                failure = adminRequestVM.errorMessage
                    ?? L10n.t("تعذّرت الموافقة من هنا — افتحه في «الوارد».", "Couldn't approve here — open it in the inbox.")
                adminRequestVM.errorMessage = nil
                return
            }
            AdminApprovalMoment.after(adminRequestVM)
            // الموافقة متفائلة: خطأ السيرفر يصل بعدها
            try? await Task.sleep(nanoseconds: UInt64((DS.MomentToast.settle + 0.1) * 1_000_000_000))
            if let message = adminRequestVM.errorMessage {
                failure = message
                adminRequestVM.errorMessage = nil
            }
        }
    }

    private func reject(_ r: AdminRequest, _ why: String) {
        if DebugAdminProbe.dryRun("member card rejectFromBox \(r.id)") { return }
        working = r.id
        adminRequestVM.errorMessage = nil
        Task { @MainActor in
            let ok = await adminRequestVM.rejectFromBox(r, reason: why)
            working = nil
            if !ok {
                failure = adminRequestVM.errorMessage
                    ?? L10n.t("تعذّر الرفض — افتحه في «الوارد».", "Couldn't reject — open it in the inbox.")
                adminRequestVM.errorMessage = nil
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

/// المعاينة قبل الموافقة، وسبب الرفض، والخطأ — في نوعها المستقل (حارس المكدس)
private struct AdminMemberRequestAlerts: ViewModifier {
    @Binding var approveTarget: AdminRequest?
    @Binding var rejectTarget: AdminRequest?
    @Binding var reason: String
    @Binding var failure: String?
    let preview: (AdminRequest) -> String?
    let approve: (AdminRequest) -> Void
    let reject: (AdminRequest, String) -> Void

    func body(content: Content) -> some View {
        content
            .dsAlert(L10n.t("الموافقة على «\(approveTarget.map(AdminMemberCardRequests.title) ?? "")»؟",
                            "Approve «\(approveTarget.map(AdminMemberCardRequests.title) ?? "")»?"),
                     isPresented: Binding(get: { approveTarget != nil }, set: { if !$0 { approveTarget = nil } }),
                     presenting: approveTarget) { r in
                Button(L10n.t("وافق", "Approve")) { approveTarget = nil; approve(r) }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { approveTarget = nil }
            } message: { r in
                Text([preview(r), L10n.t("يُنفَّذ الآن ويصل صاحب الطلب إشعار.", "Applied now; the requester is notified.")]
                    .compactMap { $0 }.joined(separator: "\n"))
            }
            .dsAlert(L10n.t("رفض الطلب؟", "Reject the request?"),
                     isPresented: Binding(get: { rejectTarget != nil }, set: { if !$0 { rejectTarget = nil } }),
                     presenting: rejectTarget) { r in
                TextField(L10n.t("سبب الرفض (اختياري)", "Reason (optional)"), text: $reason)
                    .dsAlertField()
                Button(L10n.t("ارفض", "Reject"), role: .destructive) { rejectTarget = nil; reject(r, reason) }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { rejectTarget = nil }
            } message: { _ in
                Text(L10n.t("يصل صاحب الطلب إشعار بالرفض وسببه.", "The requester is notified with the reason."))
            }
            .dsAlert(L10n.t("تعذّر التنفيذ", "Couldn't complete"),
                     isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button(L10n.t("حسناً", "OK")) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
    }
}

// MARK: - رقاقة القفز تحت الرأس

/// «طلبان عنه ‹» — رابط قفز فقط إلى الشريط في «إجراءات الإدارة»
struct AdminMemberRequestsChip: View {
    let count: Int
    /// «طلبان عنها» على ورقة المرأة
    var female: Bool = false
    let jump: () -> Void

    var body: some View {
        if let text = AdminMemberCardLogic.requestsChip(count: count, female: female, arabic: L10n.isArabic) {
            Button(action: jump) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "tray")
                        .dsGlyph(DS.Glyph.md, weight: .semibold)
                        .foregroundColor(DS.Color.accent)
                    Text(verbatim: text)
                        .dsFont(.chip)
                        .foregroundColor(DS.Color.textPrimary)
                    HStack(spacing: DS.Spacing.xs) {
                        Text(L10n.t("انتقل", "Go")).dsFont(.sectionTitle)
                        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                            .dsGlyph(DS.Glyph.xs, weight: .semibold)
                    }
                    .foregroundColor(DS.Color.accent)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xsm)
                .frame(minHeight: DS.Icon.tapTarget)
                .background(RoundedRectangle(cornerRadius: DS.Hub.memberMissingRadius, style: .continuous)
                    .fill(DS.Color.accentLight.opacity(DS.Opacity.tintFill)))
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: text))
            .accessibilityHint(Text(L10n.t("يقفز إلى الطلبات في إجراءات الإدارة", "Jumps to the requests in admin actions")))
            .accessibilityAddTraits(.isButton)
        }
    }
}
