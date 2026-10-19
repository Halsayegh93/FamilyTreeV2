import Foundation
import Supabase

// MARK: - «مسار الموافقات ٢» (طلب المالك ٢٠٢٦-١٠-١٦ مسار الموافقات ٢)
//
// فوق المسار الأول: الأولوية («مستعجل»)، استلام الطلب وتركه (لا يتصرف فيه اثنان)، التصعيد للمدير عند
// التأخر، المسار السريع، الردود الجاهزة، وملاحظات الإدارة الداخلية. السيرفر يقرّر كل شيء
// (`advance_admin_request`: claim/release/mark_urgent/mark_normal)؛ هنا العرض والإرسال فقط.
// أعمدة/جداول غير موجودة بعد على السيرفر = الواجهة الخاصة بها تختفي والسلوك كما كان تماماً.

/// فلتر قائمة «طلبات المراجعة» والمسار شغّال: الكل · بانتظارك · مستعجل · متأخر
enum ApprovalListFilter: String, CaseIterable, Identifiable, Hashable {
    case all, waiting, urgent, late
    var id: String { rawValue }
}

extension AdminRequestViewModel {

    // MARK: الإعدادات

    /// المهلة من «إعدادات التطبيق» على اللقطة (لـ«متأخر») — nil يبقى nil
    func withApprovalSLA(_ snapshot: ApprovalSnapshot?) -> ApprovalSnapshot? {
        guard var snapshot else { return nil }
        let settings = authVM?.appSettingsVM?.settings
        snapshot.slaHours = settings?.approvalsSlaHours
        snapshot.urgentSlaHours = settings?.approvalsUrgentSlaHours
        return snapshot
    }

    /// كل لقطات الطاقم المحمّلة (للفلاتر وأعدادها)
    var allApprovalSnapshots: [ApprovalSnapshot] {
        guard approvalsWorkflowOn else { return [] }
        let rows = treeEditRequests + deceasedRequests + childAddRequests + nameChangeRequests
            + photoSuggestionRequests + newsReportRequests + joinApprovalRequests
        return rows.compactMap { withApprovalSLA($0.approvalSnapshot) }
            + phoneChangeRequests.compactMap { withApprovalSLA($0.approvalSnapshot) }
    }

    /// السيرفر فيه أعمدة «مسار ٢» (رأيناها في صف واحد على الأقل)
    var approvalsV2Seen: Bool { allApprovalSnapshots.contains { $0.hasV2 } }

    /// اللقطة الحيّة لطلب بمعرّفه (بعد استلام/أولوية يتحدّث المربّع المفتوح بلا إغلاق)
    func liveApprovalSnapshot(requestId: UUID) -> ApprovalSnapshot? {
        guard approvalsWorkflowOn else { return nil }
        let rows = treeEditRequests + deceasedRequests + childAddRequests + nameChangeRequests
            + photoSuggestionRequests + newsReportRequests + joinApprovalRequests
        if let row = rows.first(where: { $0.id == requestId }) { return withApprovalSLA(row.approvalSnapshot) }
        return withApprovalSLA(phoneChangeRequests.first(where: { $0.id == requestId })?.approvalSnapshot)
    }

    // MARK: الأدوار والاستلام

    /// يتصرف كمختص: مختص النوع، أو المالك/المدير والطلب متصعّد له لتأخره
    func canActAsApprovalSpecialist(_ snapshot: ApprovalSnapshot) -> Bool {
        isApprovalSpecialist(for: snapshot.requestType) || (isApprovalManager && snapshot.isEscalated)
    }

    /// المالك/المدير يرى إجراءات المختص لأن الطلب تصعّد له (لا لأنه مختص بالأصل) — للبانر
    func isEscalatedToMe(_ snapshot: ApprovalSnapshot) -> Bool {
        snapshot.isEscalated && isApprovalManager && !isApprovalSpecialist(for: snapshot.requestType)
            && !isOwnApprovalRequest(snapshot)
    }

    /// من استلم الطلب (إن عُرف في قائمة الأعضاء)
    func approvalHolder(_ snapshot: ApprovalSnapshot) -> FamilyMember? {
        snapshot.assignedTo.flatMap { memberVM?.member(byId: $0) }
    }

    func isApprovalHeldByMe(_ snapshot: ApprovalSnapshot) -> Bool {
        guard let holder = snapshot.assignedTo, let me = authVM?.currentUser?.id else { return false }
        return holder == me
    }

    /// استلمه غيرك وهو صاحب المرحلة الحالية (المختص في المراجعة/التنفيذ، المدير في الاعتماد) — استلام
    /// قديم لمرحلة سابقة لا يقفل الطلب على أحد
    func isApprovalHeldByOther(_ snapshot: ApprovalSnapshot) -> Bool {
        guard let holder = snapshot.assignedTo, let me = authVM?.currentUser?.id, holder != me,
              snapshot.stage != .info else { return false }
        // غير معروف في القائمة = نثق بالسيرفر (مستلم)
        guard let role = memberVM?.member(byId: holder)?.role else { return true }
        let isManagerRole = role == .owner || role == .admin
        switch snapshot.stage {
        case .approve:
            return isManagerRole
        case .review, .execute:
            guard let specialist = ApprovalWorkflow.specialistRole(for: snapshot.requestType) else { return false }
            if role == specialist { return true }
            return isManagerRole && (snapshot.isEscalated || !hasActiveHolder(of: specialist))
        case .info:
            return false
        }
    }

    /// صاحب المرحلة الحالية بدوره (لا يشمل غير المختص في المراجعة مثلاً)
    private func isApprovalStageActor(_ snapshot: ApprovalSnapshot) -> Bool {
        switch snapshot.stage {
        case .review, .execute: return canActAsApprovalSpecialist(snapshot)
        case .approve: return isApprovalManager
        case .info: return false
        }
    }

    /// «استلام»: الطلب بلا مستلم (أو مستلم قديم) وأنت صاحب المرحلة
    func canClaimApproval(_ snapshot: ApprovalSnapshot) -> Bool {
        snapshot.hasV2 && !isOwnApprovalRequest(snapshot) && isApprovalStageActor(snapshot)
            && !isApprovalHeldByMe(snapshot) && !isApprovalHeldByOther(snapshot)
    }

    /// «ترك»: أنت المستلم
    func canReleaseApproval(_ snapshot: ApprovalSnapshot) -> Bool {
        snapshot.hasV2 && snapshot.stage != .info && isApprovalHeldByMe(snapshot)
    }

    /// «أخذه»: المالك يأخذ طلباً استلمه غيره — في الاعتماد دائماً، وفي المراجعة/التنفيذ إذا لم يوجد مختص
    /// مفعّل أو تصعّد الطلب (نفس قاعدة السيرفر، وإلا not_allowed)
    func canTakeOverApproval(_ snapshot: ApprovalSnapshot) -> Bool {
        guard snapshot.hasV2, authVM?.currentUser?.role == .owner, isApprovalHeldByOther(snapshot) else { return false }
        switch snapshot.stage {
        case .approve: return true
        case .review, .execute:
            guard let role = ApprovalWorkflow.specialistRole(for: snapshot.requestType) else { return false }
            return snapshot.isEscalated || !hasActiveHolder(of: role)
        case .info: return false
        }
    }

    /// ملاحظات الإدارة الداخلية لا تظهر لصاحب الطلب أو من الطلب عنه — إلا المالك (قاعدة السيرفر)
    func hidesApprovalNotes(_ snapshot: ApprovalSnapshot) -> Bool {
        guard let me = authVM?.currentUser, me.role != .owner else { return false }
        return snapshot.requesterId == me.id || snapshot.memberId == me.id
    }

    /// شارة «عندك» / «عند حسين» في صفوف الطاقم — مستلم قديم لمرحلة سابقة لا يظهر
    func approvalHolderLabel(_ snapshot: ApprovalSnapshot) -> String? {
        guard snapshot.hasV2, snapshot.stage != .info, snapshot.assignedTo != nil else { return nil }
        if isApprovalHeldByMe(snapshot) { return L10n.t("عندك", "With you") }
        guard isApprovalHeldByOther(snapshot) else { return nil }
        guard let name = approvalHolder(snapshot)?.firstName, !name.isEmpty else {
            return L10n.t("عند مسؤول آخر", "With another admin")
        }
        return L10n.t("عند \(name)", "With \(name)")
    }

    /// «مستعجل»: المدير أو مختص النوع (السيرفر يقرّر نفس القاعدة)
    func canSetApprovalPriority(_ snapshot: ApprovalSnapshot) -> Bool {
        snapshot.hasV2 && !isOwnApprovalRequest(snapshot)
            && (isApprovalManager || isApprovalSpecialist(for: snapshot.requestType))
    }

    /// قرارات المرحلة مقفلة عليك: استلمه غيرك (المالك يأخذه أولاً بشريحة «أخذه») — إلا إذا تصعّد للمدير
    /// لتأخره، فالمالك/المدير يتصرف بدل المختص المستلم
    func isApprovalDecisionLocked(_ snapshot: ApprovalSnapshot) -> Bool {
        isApprovalHeldByOther(snapshot) && !(snapshot.isEscalated && isApprovalManager)
    }

    // MARK: الفلاتر

    func approvalMatches(_ snapshot: ApprovalSnapshot, filter: ApprovalListFilter) -> Bool {
        switch filter {
        case .all: return true
        case .waiting: return isApprovalWaitingForMe(snapshot)
        case .urgent: return snapshot.isUrgent
        case .late: return snapshot.isLate || snapshot.isEscalated
        }
    }

    /// عدد كل فلتر في نطاق ما يراه الدور (`visible`: لقطات الصفوف الظاهرة)
    func approvalFilterCount(_ filter: ApprovalListFilter, in visible: [ApprovalSnapshot]) -> Int {
        visible.filter { approvalMatches($0, filter: filter) }.count
    }

    // MARK: الردود الجاهزة

    /// جدول غير موجود (السيرفر لم يُرحَّل) — رسائل PostgREST/Postgres المعروفة
    private func isMissingRelation(_ error: Error, _ name: String) -> Bool {
        let raw = ErrorHelper.description(error)
        guard raw.contains(name) || raw.contains("pgrst205") || raw.contains("pgrst202") else { return false }
        return raw.contains("pgrst205") || raw.contains("pgrst202") || raw.contains("could not find")
            || raw.contains("does not exist") || raw.contains("42p01") || raw.contains("schema cache")
    }

    /// الردود الجاهزة لنوع (بالترتيب)
    func approvalTemplates(of kinds: [ApprovalTemplateKind]) -> [ApprovalTemplate] {
        approvalTemplates.filter { t in t.templateKind.map(kinds.contains) ?? false }
            .sorted { a, b in
                let ia = kinds.firstIndex(of: a.templateKind ?? .note) ?? 0
                let ib = kinds.firstIndex(of: b.templateKind ?? .note) ?? 0
                return ia != ib ? ia < ib : (a.sort ?? 0) < (b.sort ?? 0)
            }
    }

    func fetchApprovalTemplates(force: Bool = false) async {
        if !force, approvalTemplatesAvailable != nil { return }
        do {
            let rows: [ApprovalTemplate] = try await supabase
                .from("approval_templates")
                .select("id, kind, body, sort")
                .order("sort", ascending: true)
                .execute()
                .value
            approvalTemplates = rows
            approvalTemplatesAvailable = true
        } catch {
            if isMissingRelation(error, "approval_templates") {
                approvalTemplates = []
                approvalTemplatesAvailable = false
            } else {
                Log.warning("[Approvals] تعذّر جلب الردود الجاهزة: \(error.localizedDescription)")
            }
        }
    }

    /// إضافة رد جاهز (المالك/المدير — السيرفر يرفض غيرهما). يرجّع رسالة عند الفشل
    func addApprovalTemplate(kind: ApprovalTemplateKind, body: String) async -> String? {
        guard NetworkMonitor.shared.requireOnline() else {
            return L10n.t("لا يوجد اتصال بالإنترنت.", "No internet connection.")
        }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return L10n.t("اكتب نص الرد أولاً.", "Write the reply first.") }
        nonisolated struct Row: Encodable { let kind: String; let body: String; let sort: Int }
        let nextSort = (approvalTemplates.filter { $0.kind == kind.rawValue }.compactMap(\.sort).max() ?? 0) + 1
        do {
            try await supabase
                .from("approval_templates")
                .insert(Row(kind: kind.rawValue, body: text, sort: nextSort))
                .execute()
            await fetchApprovalTemplates(force: true)
            return nil
        } catch {
            Log.error("[Approvals] فشل حفظ الرد الجاهز: \(error)")
            return L10n.t("تعذّر حفظ الرد — حاول مرة أخرى.", "Couldn't save the reply — try again.")
        }
    }

    func deleteApprovalTemplate(_ template: ApprovalTemplate) async -> String? {
        guard NetworkMonitor.shared.requireOnline() else {
            return L10n.t("لا يوجد اتصال بالإنترنت.", "No internet connection.")
        }
        let previous = approvalTemplates
        approvalTemplates.removeAll { $0.id == template.id }
        do {
            try await supabase
                .from("approval_templates")
                .delete()
                .eq("id", value: template.id.uuidString)
                .execute()
            return nil
        } catch {
            approvalTemplates = previous
            Log.error("[Approvals] فشل حذف الرد الجاهز: \(error)")
            return L10n.t("تعذّر الحذف — حاول مرة أخرى.", "Couldn't delete — try again.")
        }
    }

    // MARK: ملاحظات الإدارة الداخلية (لا يراها العضو)

    func fetchApprovalNotes(for requestId: UUID) async {
        guard approvalNotesAvailable != false else { return }
        do {
            let rows: [AdminRequestNote] = try await supabase
                .from("admin_request_notes")
                .select("id, request_id, author_id, body, created_at")
                .eq("request_id", value: requestId.uuidString)
                .order("created_at", ascending: true)
                .execute()
                .value
            approvalNotes[requestId] = rows
            approvalNotesAvailable = true
        } catch {
            if isMissingRelation(error, "admin_request_notes") {
                approvalNotesAvailable = false
            } else {
                Log.warning("[Approvals] تعذّر جلب ملاحظات الإدارة: \(error.localizedDescription)")
                if approvalNotes[requestId] == nil { approvalNotes[requestId] = [] }
            }
        }
    }

    /// ملاحظة داخلية جديدة — الكاتب أنت (السيرفر يتحقّق). يرجّع رسالة عند الفشل
    func addApprovalNote(requestId: UUID, body: String) async -> String? {
        guard NetworkMonitor.shared.requireOnline() else {
            return L10n.t("لا يوجد اتصال بالإنترنت.", "No internet connection.")
        }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let me = authVM?.currentUser?.id else { return nil }
        nonisolated struct Row: Encodable { let request_id: String; let author_id: String; let body: String }
        do {
            try await supabase
                .from("admin_request_notes")
                .insert(Row(request_id: requestId.uuidString, author_id: me.uuidString, body: text))
                .execute()
            await fetchApprovalNotes(for: requestId)
            return nil
        } catch {
            Log.error("[Approvals] فشل حفظ ملاحظة الإدارة: \(error)")
            return L10n.t("تعذّر إرسال الملاحظة — حاول مرة أخرى.", "Couldn't send the note — try again.")
        }
    }

    func deleteApprovalNote(_ note: AdminRequestNote) async -> String? {
        guard NetworkMonitor.shared.requireOnline() else {
            return L10n.t("لا يوجد اتصال بالإنترنت.", "No internet connection.")
        }
        let previous = approvalNotes[note.requestId]
        approvalNotes[note.requestId]?.removeAll { $0.id == note.id }
        do {
            try await supabase
                .from("admin_request_notes")
                .delete()
                .eq("id", value: note.id.uuidString)
                .execute()
            return nil
        } catch {
            approvalNotes[note.requestId] = previous
            Log.error("[Approvals] فشل حذف ملاحظة الإدارة: \(error)")
            return L10n.t("تعذّر الحذف — حاول مرة أخرى.", "Couldn't delete — try again.")
        }
    }
}
