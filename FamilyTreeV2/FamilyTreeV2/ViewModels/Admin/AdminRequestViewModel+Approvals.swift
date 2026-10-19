import Foundation
import Supabase

// MARK: - «مسار الموافقات» (طلب المالك ٢٠٢٦-١٠-١٥)
//
// المختص يراجع ويرفع للمدير بتوصية (أو يطلب معلومات من العضو) ← المدير يعتمد فيرجع للمختص، أو يرفض،
// أو يرجّعه بملاحظة ← المختص ينفّذ بمسار الموافقة القديم نفسه. السيرفر (`advance_admin_request`) يقرّر
// الصلاحية والمرحلة ويكتب السجل والإشعارات؛ التطبيق يعرض ويرسل الإجراء فقط.
// المفتاح مطفأ أو السيرفر لم يُرحَّل بعد → كل الدوال هنا لا تغيّر شيئاً (اللقطات nil).

extension AdminRequestViewModel {

    // MARK: المفتاح

    /// قراءة مفتاح المسار وحده (عمود واحد) — لا يُعيد نشر كل الإعدادات إلا إذا تغيّر فعلاً
    func refreshApprovalsFlag() async {
        nonisolated struct FlagRow: Decodable { let approvals_workflow: Bool? }
        guard let settingsVM = authVM?.appSettingsVM else { return }
        do {
            let rows: [FlagRow] = try await supabase
                .from("app_settings")
                .select("approvals_workflow")
                .limit(1)
                .execute()
                .value
            let isOn = rows.first?.approvals_workflow == true
            if (settingsVM.settings.approvalsWorkflow == true) != isOn {
                settingsVM.settings.approvalsWorkflow = isOn
            }
        } catch {
            // العمود غير موجود بعد = المسار مطفأ؛ انقطاع الشبكة لا يغيّر الحالة
            if ErrorHelper.isMissingColumn(error, column: "approvals_workflow"), settingsVM.settings.approvalsWorkflow != nil {
                settingsVM.settings.approvalsWorkflow = nil
            }
        }
    }

    // MARK: الأدوار

    /// مدير المسار: المالك أو المدير (يعتمد، يرفض في أي مرحلة، يرجّع للمختص)
    var isApprovalManager: Bool { authVM?.isAdmin == true }

    /// مختص النوع: المشرف للبلاغات، والمراقب لغيرها. وإن لم يحمل الدور أحد مفعّل يقوم المالك/المدير
    /// بخطوات المختص (السيرفر يقرّر نفس القاعدة — هنا لإظهار الأزرار فقط)
    func isApprovalSpecialist(for requestType: String) -> Bool {
        guard let role = ApprovalWorkflow.specialistRole(for: requestType),
              let me = authVM?.currentUser else { return false }
        if me.role == role { return true }
        guard isApprovalManager else { return false }
        return !hasActiveHolder(of: role)
    }

    /// هل يحمل الدور عضو مفعّل حيّ؟
    func hasActiveHolder(of role: FamilyMember.UserRole) -> Bool {
        memberVM?.allMembers.contains { $0.role == role && $0.status == .active && $0.isDeceased != true } ?? false
    }

    // MARK: اللقطات

    /// لقطة طلب — nil والمفتاح مطفأ أو الطلب مغلق أو خارج المسار
    func approvalSnapshot(for request: AdminRequest) -> ApprovalSnapshot? {
        approvalsWorkflowOn ? withApprovalSLA(request.approvalSnapshot) : nil
    }

    func approvalSnapshot(for request: PhoneChangeRequest) -> ApprovalSnapshot? {
        approvalsWorkflowOn ? withApprovalSLA(request.approvalSnapshot) : nil
    }

    /// لقطة طلب العضو نفسه («طلباتي»، مربّع الرد) — تظهر إذا كان المفتاح شغّالاً **أو** صفّ الطلب نفسه يحمل
    /// مرحلة من السيرفر (السيرفر لا يضع المرحلة إلا والمسار شغّال). بلاغ المالك ٢٠٢٦-١٠-١٥: طلبه في «معلومات»
    /// ظهر بلا شريط المسار لأن المفتاح المحلي كان ما زال false — فلا يعتمد جانب العضو على المفتاح وحده.
    /// شاشات الطاقم تبقى على `approvalSnapshot(for:)` (المفتاح فقط).
    func memberApprovalSnapshot(for request: AdminRequest) -> ApprovalSnapshot? {
        guard approvalsWorkflowOn || request.stage != nil else { return nil }
        return withApprovalSLA(request.approvalSnapshot)
    }

    /// لقطة صفّ في «طلبات المراجعة» بمعرّفه — للانضمام: معرّف العضو المعلّق (صفّه بنفس `member_id`)
    func approvalSnapshot(forRowId id: UUID) -> ApprovalSnapshot? {
        guard approvalsWorkflowOn else { return nil }
        let lists = [treeEditRequests, deceasedRequests, childAddRequests, nameChangeRequests,
                     photoSuggestionRequests, newsReportRequests]
        for list in lists {
            if let request = list.first(where: { $0.id == id }) { return withApprovalSLA(request.approvalSnapshot) }
        }
        if let phone = phoneChangeRequests.first(where: { $0.id == id }) { return withApprovalSLA(phone.approvalSnapshot) }
        return withApprovalSLA(joinApprovalRequests.first(where: { $0.memberId == id })?.approvalSnapshot)
    }

    /// طلبك أنت يعالجه غيرك (إلا المالك) — السيرفر يرفضه أيضاً (own_request)
    func isOwnApprovalRequest(_ snapshot: ApprovalSnapshot) -> Bool {
        guard let me = authVM?.currentUser, me.role != .owner else { return false }
        return snapshot.requesterId == me.id
    }

    /// الطلب ينتظر المستخدم الحالي («بانتظارك»): المختص في المراجعة والتنفيذ (والمدير إذا تصعّد)، والمدير
    /// في الاعتماد — وما استلمه غيرك ليس بانتظارك («مسار ٢»)
    func isApprovalWaitingForMe(_ snapshot: ApprovalSnapshot) -> Bool {
        guard !isOwnApprovalRequest(snapshot), !isApprovalDecisionLocked(snapshot) else { return false }
        switch snapshot.stage {
        case .review, .execute: return canActAsApprovalSpecialist(snapshot)
        case .approve: return isApprovalManager
        case .info: return false
        }
    }

    /// يقدر ينفّذ الآن (مسار الموافقة القديم): المختص (أو المدير والطلب متصعّد) والطلب معتمد
    func canExecuteApproval(_ snapshot: ApprovalSnapshot) -> Bool {
        snapshot.stage == .execute && canActAsApprovalSpecialist(snapshot) && !isOwnApprovalRequest(snapshot)
            && !isApprovalDecisionLocked(snapshot)
    }

    /// يقدر يرفض نهائياً (مسار الرفض القديم): المدير في أي مرحلة
    func canRejectApproval(_ snapshot: ApprovalSnapshot) -> Bool {
        isApprovalManager && !isOwnApprovalRequest(snapshot)
    }

    /// المرتّب: المستعجل أولاً ثم ما ينتظرك (الأقدم أولاً في كلٍّ منهما — «مسار ٢»)، والباقي بترتيبه —
    /// المفتاح مطفأ = القائمة كما هي
    func approvalOrdered<T: Identifiable>(_ items: [T]) -> [T] where T.ID == UUID {
        guard approvalsWorkflowOn else { return items }
        return approvalPrioritized(items) { approvalSnapshot(forRowId: $0.id) }
    }

    /// ترتيب «مسار ٢» لأي قائمة بلقطاتها: مستعجل ← بانتظارك ← الباقي بترتيبه
    func approvalPrioritized<T>(_ items: [T], snapshot: (T) -> ApprovalSnapshot?) -> [T] {
        var urgent: [(T, Date)] = [], waiting: [(T, Date)] = [], rest: [T] = []
        for item in items {
            guard let flow = snapshot(item) else { rest.append(item); continue }
            let since = flow.createdAt ?? .distantFuture
            if flow.isUrgent { urgent.append((item, since)) }
            else if isApprovalWaitingForMe(flow) { waiting.append((item, since)) }
            else { rest.append(item) }
        }
        guard !urgent.isEmpty || !waiting.isEmpty else { return items }
        // داخل المستعجل: ما ينتظرك قبل غيره، ثم الأقدم
        let urgentSorted = urgent.sorted { a, b in
            let wa = snapshot(a.0).map(isApprovalWaitingForMe) ?? false
            let wb = snapshot(b.0).map(isApprovalWaitingForMe) ?? false
            return wa != wb ? wa : a.1 < b.1
        }
        return urgentSorted.map(\.0) + waiting.sorted { $0.1 < $1.1 }.map(\.0) + rest
    }

    // MARK: الجلب

    /// صفوف طلبات الانضمام/الربط المعلّقة (مرحلة كل عضو معلّق) — والمفتاح شغّال فقط
    func fetchJoinApprovalRequests() async {
        guard approvalsWorkflowOn, authVM?.canModerate == true else {
            if !joinApprovalRequests.isEmpty { joinApprovalRequests = [] }
            return
        }
        do {
            let rows: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*")
                .in("request_type", values: [RequestType.joinRequest.rawValue, RequestType.linkRequest.rawValue])
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .order("created_at", ascending: false)
                .execute()
                .value
            joinApprovalRequests = rows
        } catch {
            Log.warning("[Approvals] تعذّر جلب مراحل طلبات الانضمام: \(error.localizedDescription)")
        }
    }

    /// سجل خطوات طلب — الجدول غير موجود بعد أو لا صلاحية = سجل فارغ بهدوء
    func fetchApprovalSteps(for requestId: UUID) async {
        do {
            let rows: [AdminRequestStep] = try await supabase
                .from("admin_request_steps")
                .select()
                .eq("request_id", value: requestId.uuidString)
                .order("created_at", ascending: true)
                .execute()
                .value
            approvalSteps[requestId] = rows
        } catch {
            Log.warning("[Approvals] تعذّر جلب سجل الطلب: \(error.localizedDescription)")
            if approvalSteps[requestId] == nil { approvalSteps[requestId] = [] }
        }
    }

    // MARK: الإجراء

    /// خطوة في المسار (`advance_admin_request`). يرجّع nil عند النجاح أو رسالة عربية واضحة عند الفشل
    /// (تُعرض داخل المربّع نفسه). بعد النجاح تُحدَّث قائمة النوع وسجلّه.
    /// - fields: «طلب معلومات» منظّم — الحقول التي اختارها المختص (الملاحظة تصير اختيارية)
    /// - values: ردّ العضو على الحقول (السيرفر يفحصها ويكتب الملخّص المقروء في السجل)
    func advanceApproval(_ snapshot: ApprovalSnapshot, action: ApprovalAction, note: String?,
                         fields: [ApprovalInfoField] = [], values: [String: String]? = nil) async -> String? {
        guard NetworkMonitor.shared.requireOnline() else {
            return L10n.t("لا يوجد اتصال بالإنترنت.", "No internet connection.")
        }
        // المعاملات الجديدة تُرسل فقط عند استعمالها — الاستدعاء العادي بالأسماء الثلاثة كما كان
        nonisolated struct Params: Encodable {
            let p_request_id: String
            let p_action: String
            let p_note: String?
            let p_fields: [String]?
            let p_values: [String: String]?
        }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let asked = fields.filter { $0 != .text }
        let structured = (action == .requestInfo && !asked.isEmpty) || (action == .provideInfo && values != nil)
        if action.requiresNote && trimmed.isEmpty && !structured {
            return L10n.t("اكتب الملاحظة أولاً.", "Write the note first.")
        }
        do {
            try await supabase
                .rpc("advance_admin_request", params: Params(
                    p_request_id: snapshot.requestId.uuidString,
                    p_action: action.rawValue,
                    p_note: trimmed.isEmpty ? nil : trimmed,
                    p_fields: action == .requestInfo && !fields.isEmpty ? fields.map(\.rawValue) : nil,
                    p_values: action == .provideInfo ? values : nil))
                .execute()
            Log.info("[Approvals] \(action.rawValue) — \(snapshot.requestId)")
        } catch {
            Log.error("[Approvals] \(action.rawValue) فشل: \(error)")
            return Self.approvalErrorMessage(error, action: action)
        }
        // طلبك أنت (المالك يراجع طلبه) أو ردّك كعضو → «طلباتي» تتحدّث أيضاً فلا تبقى بمرحلتها القديمة
        let isMine = snapshot.requesterId != nil && snapshot.requesterId == authVM?.currentUser?.id
        if action.isHousekeeping {
            // الأولوية تظهر للعضو أيضاً («مستعجل») — «طلباتي» تتحدّث إن كان طلبك
            await refreshApprovalList(for: snapshot.requestType)
            if isMine && (action == .markUrgent || action == .markNormal) { await fetchMyPendingRequests(force: true) }
        } else if action == .provideInfo {
            await fetchMyPendingRequests(force: true)
        } else {
            await refreshApprovalList(for: snapshot.requestType)
            if isMine { await fetchMyPendingRequests(force: true) }
        }
        await fetchApprovalSteps(for: snapshot.requestId)
        return nil
    }

    /// رسائل أخطاء المسار: رسالة السيرفر العربية حين تسمّي الناقص (ردّ العضو على الحقول)، والدالة القديمة
    /// على السيرفر (لم يُرحَّل بعد) تُشرح بدل خطأ تقني — وإلا رسائل القرار المعتادة
    static func approvalErrorMessage(_ error: Error, action: ApprovalAction? = nil) -> String {
        let pg = error as? PostgrestError
        let server = pg?.message.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let arabicServer = L10n.isArabic && !server.isEmpty
            && server.range(of: "\\p{Arabic}", options: .regularExpression) != nil
        if pg?.hint == "note_required", arabicServer {
            return server
        }
        // «مسار ٢»: الطلب عند مسؤول آخر — رسالة السيرفر تسمّي من استلمه
        if pg?.hint == "claimed_by_other" {
            return arabicServer ? server : L10n.t("الطلب عند مسؤول آخر — حدّث الصفحة.",
                                                  "Another admin holds this request — refresh the page.")
        }
        // الاستلام والأولوية على سيرفر لم يُرحَّل بعد (إجراء غير معروف أو دالة قديمة)
        if action?.isHousekeeping == true,
           pg?.hint == "bad_action" || pg?.code == "PGRST202" || server.contains("Could not find the function") {
            return L10n.t("هذه الميزة تحتاج تحديث السيرفر.", "This needs a server update.")
        }
        if pg?.code == "PGRST202" || server.contains("Could not find the function") {
            return L10n.t("اختيار الناقص يحتاج تحديث السيرفر — اكتب المطلوب كملاحظة.",
                          "Choosing missing items needs a server update — write it as a note.")
        }
        return decisionErrorMessage(error)
    }

    /// إعادة جلب قائمة النوع بعد خطوة (المرحلة تغيّرت)
    func refreshApprovalList(for requestType: String) async {
        switch requestType {
        case RequestType.treeEdit.rawValue: await fetchTreeEditRequests(force: true)
        case RequestType.deceasedReport.rawValue: await fetchDeceasedRequests(force: true)
        case RequestType.childAdd.rawValue: await fetchChildAddRequests(force: true)
        case RequestType.nameChange.rawValue, RequestType.familyChange.rawValue: await fetchNameChangeRequests(force: true)
        case RequestType.phoneChange.rawValue: await fetchPhoneChangeRequests(force: true)
        case RequestType.photoSuggestion.rawValue: await fetchPhotoSuggestionRequests(force: true)
        case RequestType.newsReport.rawValue, RequestType.contentReport.rawValue: await fetchNewsReportRequests(force: true)
        case RequestType.joinRequest.rawValue, RequestType.linkRequest.rawValue: await fetchJoinApprovalRequests()
        default: break
        }
    }

    // MARK: نصوص

    /// من بيده الطلب الآن — «الطلب الحين عند …»
    func approvalHolderTitle(_ snapshot: ApprovalSnapshot) -> String {
        switch snapshot.stage {
        case .approve:
            return L10n.t("المدير", "the manager")
        case .info:
            let name = snapshot.requesterId.flatMap { memberVM?.member(byId: $0)?.firstName }
            return name.map { L10n.t("العضو (\($0))", "the member (\($0))") } ?? L10n.t("العضو", "the member")
        case .review, .execute:
            return ApprovalWorkflow.specialistRole(for: snapshot.requestType).map(Self.approvalRoleTitle)
                ?? L10n.t("المختص", "the specialist")
        }
    }

    /// اسم الدور في المسار (المالك يظهر «المدير» كما في بقية التطبيق)
    static func approvalRoleTitle(_ role: FamilyMember.UserRole) -> String {
        switch role {
        case .owner, .admin: return L10n.t("المدير", "the manager")
        case .monitor: return L10n.t("المراقب", "the monitor")
        case .supervisor: return L10n.t("المشرف", "the supervisor")
        case .member, .pending: return L10n.t("العضو", "the member")
        }
    }
}
