import Combine
import SwiftUI
import Supabase

// MARK: - «المرسل» و«ما تم في الطلب» و«تمت معالجتها» (طلب المالك ٢٠٢٦-١١-١١)
//
// «المرسل»: مسار الإرسال خطوات مرقّمة (`sent_from`، وإلا المسار المستنتج من نوع الطلب)، «أرسله» (الاسم الرباعي ·
// الدور الحقيقي · صلته بالمعني إن كانت واضحة)، و«الجهاز» و«الوقت» خليتين متجاورتين (`sent_via`، وإلا «غير مسجّل»).
// «ما تم في الطلب»: سجلّ السيرفر `admin_request_events` (20261111150000) — كل تغيير ومن فعله ومتى وملاحظته؛
// الطلبات قبل الترحيل: ما تسمح به أعمدتها (أُرسل · قُبل/رُفض بمن ردّ إن سُجّل) وإلا «غير مسجّل».
// «النتيجة»: ما تغيّر فعلاً كما يُستنتج من نوع الطلب وحمولته فقط — لا اختراع.
// «تمت معالجتها»: الطلبات المغلقة في آخر ٣٠ يوماً (الأحدث أولاً، «عرض المزيد») — صفّ بقرار وبواسطة ووقت، ويفتح
// المربّع نفسه للعرض فقط.

// MARK: سجلّ الحدث

nonisolated struct AdminRequestEvent: Decodable, Identifiable, Hashable, Sendable {
    let id: Int64
    let requestId: UUID?
    let requestType: String?
    let subjectId: UUID?
    let action: String
    let actorId: UUID?
    let actorRole: String?
    let note: String?
    let at: String?

    enum CodingKeys: String, CodingKey {
        case id, action, note, at
        case requestId = "request_id"
        case requestType = "request_type"
        case subjectId = "subject_id"
        case actorId = "actor_id"
        case actorRole = "actor_role"
    }

    /// أحداث القرار (تحدّد من عالج الطلب ومتى)
    static let decisionActions: Set<String> = ["approved", "executed", "replied", "rejected"]
}

/// صف يُتجاوز إن لم يُقرأ (طالب محذوف، نوع جديد) — لا يُسقط الصفحة كلها
private nonisolated struct LossyHandledRequest: Decodable, Sendable {
    let value: AdminRequest?
    init(from decoder: Decoder) throws { value = try? AdminRequest(from: decoder) }
}

// MARK: - مخزن «تمت معالجتها» والسجلّ

@MainActor
final class AdminHandledStore: ObservableObject {
    @Published private(set) var items: [AdminRequest] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadedOnce = false
    @Published private(set) var hasMore = false
    @Published private(set) var failed = false
    /// سجلّ كل طلب فُتح (بمعرّفه)
    @Published private(set) var events: [UUID: [AdminRequestEvent]] = [:]
    /// nil = لم يُعرف، false = السيرفر قبل 20261111150000 (بلا سجلّ)
    @Published private(set) var eventsAvailable: Bool? = nil
    /// اسم عقدة شجرة النساء المربوطة بحساب المنضمة (معرّف الحساب ← الاسم) — لـ«رُبطت بـ» (طلب المالك ٢٠٢٦-١١-١١)
    @Published private(set) var womenLinks: [UUID: String] = [:]
    /// حذف الإدارة المباشر (بلا طلب) في ما تعرضه القائمة — يُدمج في الأيام (§9، المالك والمدير والمراقب)
    @Published private(set) var deletions: [MemberDeletePlace] = []
    /// يضبطها العرض: من يقرأ سجلّ الأماكن (`member_delete_places`) — المالك والمدير والمراقب
    var includesDeletions = false

    static let pageSize = 40
    static let windowDays = 30
    private let supabase = SupabaseConfig.client

    /// بداية النافذة (آخر ٣٠ يوماً)
    private var since: String {
        let date = Calendar.current.date(byAdding: .day, value: -Self.windowDays, to: Date()) ?? Date()
        return ISO8601DateFormatter().string(from: date)
    }

    func reload() async {
        await load(reset: true)
    }

    func loadMore() async {
        await load(reset: false)
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; loadedOnce = true }
        let from = reset ? 0 : items.count
        do {
            let rows: [LossyHandledRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:members_masked!member_id(*)")
                .neq("status", value: ApprovalStatus.pending.rawValue)
                // المعالجة في النافذة؛ القديم بلا وقت ردّ بوقت إرساله
                .or("replied_at.gte.\(since),and(replied_at.is.null,created_at.gte.\(since))")
                .order("replied_at", ascending: false, nullsFirst: false)
                .order("created_at", ascending: false)
                .range(from: from, to: from + Self.pageSize - 1)
                .execute()
                .value
            let page = rows.compactMap(\.value)
            items = reset ? page : items + page.filter { p in !items.contains { $0.id == p.id } }
            hasMore = rows.count == Self.pageSize
            failed = false
            await loadWomenLinks(for: page)
            await loadDeletions()
        } catch {
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[Handled] تعذّر جلب الطلبات المعالجة: \(error.localizedDescription)")
                failed = true
            }
        }
    }

    /// المحذوفون مباشرة منذ أقدم يوم تعرضه القائمة (آخر ٣٠ يوماً، أو أقدم ما حُمِّل إن بقي المزيد)
    private func loadDeletions() async {
        guard includesDeletions else { deletions = []; return }
        let window = Calendar.current.date(byAdding: .day, value: -Self.windowDays, to: Date()) ?? Date()
        var since = window
        if hasMore, let oldest = items.compactMap({ DateHelper.parse($0.repliedAt ?? $0.createdAt) }).min() {
            since = max(window, Calendar.current.startOfDay(for: oldest))
        }
        do {
            deletions = try await TreePlaceDeletedLookup.recent(since: since).filter(\.isStaffDirect)
        } catch {
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[Handled] تعذّر جلب الحذف المباشر: \(error.localizedDescription)")
            }
        }
    }

    private struct WomenLinkRow: Decodable {
        let fullName: String?
        let firstName: String?
        let linkedUserId: UUID
        enum CodingKeys: String, CodingKey {
            case fullName = "full_name", firstName = "first_name", linkedUserId = "linked_user_id"
        }
    }

    /// طلبات الانضمام المقبولة: عقدة شجرة النساء المربوطة بحساب صاحبة الطلب (`link_woman_account`)
    private func loadWomenLinks(for page: [AdminRequest]) async {
        let ids = Set(page.filter(AdminTrailText.isApprovedJoin).map(\.memberId)).subtracting(womenLinks.keys)
        guard !ids.isEmpty else { return }
        do {
            let rows: [WomenLinkRow] = try await supabase
                .from("women_members")
                .select("full_name, first_name, linked_user_id")
                .in("linked_user_id", values: ids.map(\.uuidString))
                .execute()
                .value
            for r in rows {
                let name = [r.fullName, r.firstName].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }
                if let name { womenLinks[r.linkedUserId] = name }
            }
        } catch {
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[Handled] تعذّر جلب ربط شجرة النساء: \(error.localizedDescription)")
            }
        }
    }

    /// سجلّ طلب واحد (الأقدم أولاً) — بلا جدول على السيرفر = قائمة فارغة و`eventsAvailable = false`
    func loadEvents(for requestId: UUID) async {
        guard eventsAvailable != false else { events[requestId] = []; return }
        do {
            let rows: [AdminRequestEvent] = try await supabase
                .from("admin_request_events")
                .select()
                .eq("request_id", value: requestId.uuidString)
                .order("at", ascending: true)
                .order("id", ascending: true)
                .execute()
                .value
            events[requestId] = rows
            eventsAvailable = true
        } catch {
            let raw = ErrorHelper.description(error)
            if ErrorHelper.isMissingTable(error, table: "admin_request_events") || raw.contains("schema cache") || raw.contains("pgrst205") {
                eventsAvailable = false
            } else {
                Log.warning("[Handled] تعذّر جلب سجلّ الطلب: \(error.localizedDescription)")
            }
            events[requestId] = []
        }
    }

    #if DEBUG
    /// معاينة التصميم (`-uiPreviewRequestTrail`) — بيانات وهمية بلا سيرفر
    func seedPreview(items: [AdminRequest], events: [UUID: [AdminRequestEvent]]) {
        self.items = items
        self.events = events
        eventsAvailable = true
        loadedOnce = true
    }
    #endif
}

// MARK: - النصوص المشتركة

enum AdminTrailText {
    /// الدور الحقيقي للإدارة (المالك يظهر «المالك» هنا — الإدارة ترى الأدوار كما هي)
    static func roleName(_ role: FamilyMember.UserRole?) -> String? {
        switch role {
        case .owner: return L10n.t("المالك", "Owner")
        case .admin: return L10n.t("مدير", "Admin")
        case .monitor: return L10n.t("مراقب", "Monitor")
        case .supervisor: return L10n.t("مشرف", "Supervisor")
        case .member: return L10n.t("عضو", "Member")
        case .pending: return L10n.t("معلّق", "Pending")
        case nil: return nil
        }
    }

    static func roleName(raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw == "server" { return L10n.t("السيرفر", "Server") }
        if raw == "frozen" { return L10n.t("موقوف", "Suspended") }
        return roleName(FamilyMember.UserRole(rawValue: raw))
    }

    /// عنوان نوع الطلب بالعربية الرسمية
    static func typeTitle(_ request: AdminRequest) -> String {
        switch request.requestType {
        case RequestType.joinRequest.rawValue, RequestType.linkRequest.rawValue: return L10n.t("طلب انضمام", "Join request")
        case RequestType.treeEdit.rawValue:
            let p = request.treeEditPayload
            if let reason = AdminAllRequestsView.profileReasonTitle(p?.reason) { return reason }
            if let a = p?.resolvedAction, a != .other {
                return L10n.t("طلب ", "") + (L10n.isArabic ? a.arabicLabel : a.englishLabel)
            }
            return L10n.t("طلب تعديل", "Edit request")
        case RequestType.newsReport.rawValue: return L10n.t("بلاغ عن منشور", "Post report")
        case RequestType.contentReport.rawValue: return L10n.t("بلاغ عن محتوى", "Content report")
        case RequestType.phoneChange.rawValue: return L10n.t("طلب تغيير الرقم", "Phone change")
        case RequestType.nameChange.rawValue: return L10n.t("طلب تغيير الاسم", "Name change")
        case RequestType.familyChange.rawValue: return L10n.t("طلب تغيير العائلة", "Family change")
        case RequestType.childAdd.rawValue: return L10n.t("طلب إضافة ابن", "Add child")
        case RequestType.deceasedReport.rawValue: return L10n.t("طلب تسجيل وفاة", "Death report")
        case RequestType.photoSuggestion.rawValue: return L10n.t("اقتراح صورة", "Photo suggestion")
        case RequestType.accountDelete.rawValue: return L10n.t("طلب حذف الحساب", "Account deletion")
        case RequestType.privacyRequest.rawValue: return L10n.t("طلب خصوصية", "Privacy request")
        case RequestType.relativeAdd.rawValue:
            // صلة القرابة في العنوان (طلب المالك ٢٠٢٦-١١-١٢ «طلب إضافة قريبة… حدد من»)
            return RelativeAddDetails.parse(request.details)?.requestTitle ?? AdminRequestFactText.relativeAddGeneric
        case RequestType.relativeRemove.rawValue:
            // «طلب حذف ابن/بنت/زوجة» (§10)
            return RelativeRemoveDetails.parse(request.details)?.requestTitle ?? RelativeRemoveDetails.genericTitle
        case "lineage_request": return L10n.t("طلب نسب", "Lineage request")
        case "contact_message": return L10n.t("رسالة للإدارة", "Message to admins")
        default: return L10n.t("طلب", "Request")
        }
    }

    static func typeIcon(_ request: AdminRequest) -> String {
        switch request.requestType {
        case RequestType.joinRequest.rawValue, RequestType.linkRequest.rawValue: return "person.badge.shield.checkmark"
        case RequestType.treeEdit.rawValue: return request.treeEditPayload?.resolvedAction?.iconName ?? "square.and.pencil"
        case RequestType.newsReport.rawValue, RequestType.contentReport.rawValue: return "flag.fill"
        case RequestType.phoneChange.rawValue: return "phone.fill"
        case RequestType.nameChange.rawValue, RequestType.familyChange.rawValue: return "character.cursor.ibeam"
        case RequestType.childAdd.rawValue: return "person.badge.plus"
        case RequestType.deceasedReport.rawValue: return "leaf.fill"
        case RequestType.photoSuggestion.rawValue: return "photo.badge.plus"
        case "contact_message": return "envelope.fill"
        case RequestType.relativeAdd.rawValue: return "person.badge.plus"
        case RequestType.relativeRemove.rawValue: return "person.badge.minus"
        default: return "doc.text.fill"
        }
    }

    // MARK: الحدث

    static func actionTitle(_ action: String) -> String {
        switch action {
        case "sent": return L10n.t("أُرسل الطلب", "Request sent")
        case "approved": return L10n.t("قُبل الطلب", "Approved")
        case "executed": return L10n.t("نُفّذ الطلب", "Executed")
        case "replied": return L10n.t("رُدّ على الطلب", "Replied")
        case "rejected": return L10n.t("رُفض الطلب", "Rejected")
        case "reopened": return L10n.t("أُعيد فتح الطلب", "Reopened")
        case "recommended_approve": return L10n.t("أوصى المختص بالقبول", "Recommended approval")
        case "recommended_reject": return L10n.t("أوصى المختص بالرفض", "Recommended rejection")
        case "manager_approved": return L10n.t("اعتمده المدير", "Approved by manager")
        case "info_requested": return L10n.t("طُلبت معلومات إضافية", "More information requested")
        case "info_replied": return L10n.t("أرسل صاحب الطلب المعلومات", "Information provided")
        case "returned": return L10n.t("أُعيد للمراجعة", "Returned for review")
        case "claimed": return L10n.t("استُلم الطلب", "Claimed")
        case "released": return L10n.t("تُرك الطلب", "Released")
        case "escalated": return L10n.t("صُعِّد الطلب لتأخّره", "Escalated")
        case "moved": return L10n.t("نُقل الطلب إلى ملف آخر", "Moved to another record")
        case "deleted": return L10n.t("حُذف الطلب", "Deleted")
        case "withdrawn": return L10n.t("سحب صاحب الطلب طلبه", "Withdrawn")
        case "member_activated": return L10n.t("فُعِّل حساب العضو", "Account activated")
        default:
            if action.hasPrefix("stage:") { return L10n.t("تغيّرت مرحلة الطلب", "Stage changed") }
            return L10n.t("تغيّرت حالة الطلب", "Status changed")
        }
    }

    static func actionIcon(_ action: String) -> String {
        switch action {
        case "sent": return "paperplane.fill"
        case "approved", "manager_approved": return "checkmark.circle.fill"
        case "executed": return "checkmark.seal.fill"
        case "replied": return "arrowshape.turn.up.left.fill"
        case "rejected", "recommended_reject": return "xmark.circle.fill"
        case "recommended_approve": return "hand.thumbsup.fill"
        case "info_requested", "info_replied": return "questionmark.bubble.fill"
        case "returned", "reopened": return "arrow.uturn.backward"
        case "claimed", "released": return "person.crop.circle.badge.checkmark"
        case "escalated": return "exclamationmark.triangle.fill"
        case "deleted", "withdrawn": return "trash.fill"
        case "member_activated": return "person.crop.circle.fill.badge.checkmark"
        case "moved": return "arrow.left.arrow.right"
        default: return "circle.fill"
        }
    }

    static func actionTint(_ action: String) -> Color? {
        switch action {
        case "approved", "manager_approved", "member_activated", "recommended_approve": return DS.Color.success
        case "rejected", "recommended_reject", "deleted", "withdrawn": return DS.Color.error
        case "escalated": return DS.Color.warning
        default: return nil
        }
    }

    // MARK: القرار

    enum Decision {
        case approved, rejected, executed, replied, other

        var title: String {
            switch self {
            case .approved: return L10n.t("قُبل", "Approved")
            case .rejected: return L10n.t("رُفض", "Rejected")
            case .executed: return L10n.t("نُفّذ", "Executed")
            case .replied: return L10n.t("رُدّ", "Replied")
            case .other: return L10n.t("عولج", "Handled")
            }
        }

        var tint: Color {
            switch self {
            case .approved: return DS.Color.success
            case .rejected: return DS.Color.error
            case .executed: return DS.Color.brand
            case .replied, .other: return DS.Color.slate
            }
        }

        var icon: String {
            switch self {
            case .approved: return "checkmark"
            case .rejected: return "xmark"
            case .executed: return "checkmark.seal"
            case .replied: return "arrowshape.turn.up.left"
            case .other: return "circle"
            }
        }
    }

    static func decision(_ request: AdminRequest, events: [AdminRequestEvent]?) -> Decision {
        switch request.status {
        case ApprovalStatus.rejected.rawValue: return .rejected
        case ApprovalStatus.approved.rawValue:
            if request.requestType == "contact_message" { return .replied }
            if events?.contains(where: { $0.action == "executed" }) == true || request.approvedBy != nil { return .executed }
            return .approved
        default: return .other
        }
    }

    /// حدث القرار الأخير في السجلّ
    static func decisionEvent(_ events: [AdminRequestEvent]?) -> AdminRequestEvent? {
        events?.last { AdminRequestEvent.decisionActions.contains($0.action) }
    }

    /// من عالج الطلب: replied_by (يملؤه السيرفر من الترحيل)، وإلا حدث القرار، وإلا اعتماد المسار
    static func handlerId(_ request: AdminRequest, events: [AdminRequestEvent]?) -> UUID? {
        request.repliedBy ?? decisionEvent(events)?.actorId ?? request.approvedBy
    }

    /// وقت المعالجة
    static func handledAt(_ request: AdminRequest, events: [AdminRequestEvent]?) -> String? {
        request.repliedAt ?? decisionEvent(events)?.at
    }

    /// «الاسم الرباعي · الدور» — أو «غير مسجّل»
    static func person(_ id: UUID?, fallbackRole: String? = nil, lookup: (UUID) -> FamilyMember?) -> String? {
        guard let id else { return nil }
        let member = lookup(id)
        let name = member?.fourPartName ?? L10n.t("عضو غير موجود في القائمة", "Unlisted member")
        let role = roleName(member?.role) ?? roleName(raw: fallbackRole)
        return [name, role].compactMap { $0 }.joined(separator: " · ")
    }

    static let notRecorded = L10n.t("غير مسجّل", "Not recorded")

    // MARK: «المرسل»

    /// صلته بالمعني بالطلب حين تكون واضحة من الشجرة: نفسه · أبوه/أبوها · ابنه/ابنته · أخوه/أخوها (وإلا بلا)
    static func relation(sender: FamilyMember, subject: FamilyMember?) -> String? {
        guard let subject else { return nil }
        let female = subject.isFemale
        if sender.id == subject.id { return female ? L10n.t("نفسها", "Herself") : L10n.t("نفسه", "Himself") }
        if subject.fatherId == sender.id { return female ? L10n.t("أبوها", "Her father") : L10n.t("أبوه", "His father") }
        if sender.fatherId == subject.id { return sender.isFemale ? L10n.t("ابنته", "His daughter") : L10n.t("ابنه", "His son") }
        if let f = sender.fatherId, f == subject.fatherId {
            if sender.isFemale { return female ? L10n.t("أختها", "Her sister") : L10n.t("أخته", "His sister") }
            return female ? L10n.t("أخوها", "Her brother") : L10n.t("أخوه", "His brother")
        }
        return nil
    }

    /// المسار المسجّل، وإلا المستنتج («الشجرة ← تفاصيل … ← طلب تعديل») خطواتٍ بالرموز المعروفة
    static func pathSteps(recorded: RequestSource?, inferred: String) -> [DSPathStep] {
        if let recorded, !recorded.isEmpty {
            return recorded.steps.map { DSPathStep(icon: $0.icon, title: $0.title) }
        }
        let parts = inferred
            .components(separatedBy: " ← ")
            .flatMap { $0.components(separatedBy: " → ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.map { DSPathStep(icon: inferredIcon($0), title: $0) }
    }

    private static func inferredIcon(_ title: String) -> String {
        switch title {
        case L10n.t("الشجرة", "Tree"), L10n.t("شجرة النساء", "Women's tree"): return "tree.fill"
        case L10n.t("الملف الشخصي", "Profile"): return "person.crop.circle"
        case L10n.t("الأسرة", "Family"): return RequestSourceStep.profileFamily.icon
        case L10n.t("الرئيسية", "Home"): return "house.fill"
        case L10n.t("التواصل", "Contact"): return "envelope.fill"
        case L10n.t("التسجيل", "Sign-up"): return "person.badge.plus"
        case L10n.t("الموقع", "Website"): return "globe"
        case L10n.t("التطبيق", "App"): return "iphone"
        case L10n.t("الديوانيات", "Diwaniyas"): return "cup.and.saucer.fill"
        case L10n.t("مشاريع العائلة", "Family projects"): return "briefcase.fill"
        case L10n.t("مكتبة العائلة", "Family library"): return "books.vertical.fill"
        default:
            if title.hasPrefix(L10n.t("تفاصيل", "Details")) { return "person.fill" }
            if title.contains(L10n.t("إضافة", "Add")) { return "plus" }
            if title.contains(L10n.t("بلاغ", "Report")) { return "flag.fill" }
            if title.contains(L10n.t("وفاة", "death")) { return "leaf.fill" }
            if title.contains(L10n.t("صورة", "photo")) { return "photo.badge.plus" }
            return "pencil"
        }
    }

    /// «الجهاز»: «آيفون 1.0.2 (51)» — أو «غير مسجّل»
    static func device(_ via: RequestSentVia?) -> String {
        via.map(\.deviceLine) ?? notRecorded
    }

    // MARK: «رُبط بـ» — طلبات الانضمام المقبولة (طلب المالك ٢٠٢٦-١١-١١ «وضّح تم ربطها بمن»)

    static func isApprovedJoin(_ request: AdminRequest) -> Bool {
        request.status == ApprovalStatus.approved.rawValue
            && (request.requestType == RequestType.joinRequest.rawValue || request.requestType == RequestType.linkRequest.rawValue)
    }

    /// شجرة النساء: العقدة المربوطة بالحساب؛ شجرة العائلة: مكان الحساب في الشجرة بعد الربط (الدمج يُبقي الحساب مكان العضو)
    static func joinLink(_ request: AdminRequest, member: FamilyMember?, womenName: String?) -> String? {
        guard isApprovedJoin(request) else { return nil }
        // الشجرة أولاً — الاسم الطويل يُقصّ من آخره فلا تضيع الشجرة
        if let womenName, !womenName.isEmpty {
            return L10n.t("رُبطت في شجرة النساء بـ: ", "Linked in the women's tree to: ") + womenName
        }
        if let member, member.fatherId != nil {
            return (member.isFemale ? L10n.t("رُبطت في شجرة العائلة بـ: ", "Linked in the family tree to: ")
                                    : L10n.t("رُبط في شجرة العائلة بـ: ", "Linked in the family tree to: "))
                + member.fourPartName
        }
        return nil
    }

    // MARK: «النتيجة» — مما في الطلب فقط

    static func result(_ request: AdminRequest) -> [String] {
        let reply = request.adminReply?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch request.status {
        case ApprovalStatus.rejected.rawValue:
            return [L10n.t("لم يُنفَّذ شيء — رُفض الطلب.", "Nothing changed — the request was rejected.")]
                + (reply.isEmpty ? [] : [L10n.t("السبب: ", "Reason: ") + reply])
        case ApprovalStatus.approved.rawValue:
            break
        default:
            return [L10n.t("الحالة: ", "Status: ") + (request.status)]
        }
        let value = request.newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var lines: [String] = []
        switch request.requestType {
        case "contact_message":
            lines.append(L10n.t("رُدّ على الرسالة.", "The message was answered."))
        case RequestType.joinRequest.rawValue, RequestType.linkRequest.rawValue:
            lines.append(L10n.t("قُبل الانضمام وفُعِّل الحساب.", "Join approved and the account activated."))
        case RequestType.nameChange.rawValue where !value.isEmpty:
            lines.append(L10n.t("تغيّر الاسم إلى: ", "Name changed to: ") + value)
        case RequestType.familyChange.rawValue where !value.isEmpty:
            lines.append(L10n.t("تغيّرت العائلة إلى: ", "Family changed to: ") + value)
        case RequestType.phoneChange.rawValue where !value.isEmpty:
            lines.append(L10n.t("تغيّر الرقم إلى: ", "Phone changed to: ") + "\u{2066}" + KuwaitPhone.display(value) + "\u{2069}")
        case RequestType.deceasedReport.rawValue:
            lines.append(L10n.t("سُجّلت الوفاة.", "The death was recorded."))
            if let d = request.details, !d.isEmpty { lines.append(d) }
        case RequestType.childAdd.rawValue:
            lines.append(L10n.t("اعتُمدت إضافة الابن.", "The child was approved."))
            if let d = request.details, !d.isEmpty { lines.append(d) }
        case RequestType.photoSuggestion.rawValue:
            lines.append(L10n.t("اعتُمدت الصورة المقترحة.", "The suggested photo was approved."))
        case RequestType.newsReport.rawValue:
            lines.append(L10n.t("قُبل البلاغ وحُذف المنشور.", "Report accepted and the post removed."))
        case RequestType.contentReport.rawValue:
            lines.append(L10n.t("قُبل البلاغ.", "Report accepted."))
        case RequestType.relativeAdd.rawValue:
            lines.append(L10n.t("نُفّذ: ", "Done: ") + (relativeSummary(request) ?? AdminRequestFactText.relativeAddGeneric))
        case RequestType.relativeRemove.rawValue:
            lines.append(L10n.t("نُفّذ: ", "Done: ") + (relativeSummary(request) ?? AdminRequestFactText.relativeRemoveGeneric))
        case RequestType.treeEdit.rawValue:
            lines.append(contentsOf: treeEditResult(request))
        default:
            lines.append(L10n.t("قُبل الطلب.", "The request was approved."))
        }
        if !reply.isEmpty { lines.append(L10n.t("رد الإدارة: ", "Reply: ") + reply) }
        return lines
    }

    private static func relativeSummary(_ request: AdminRequest) -> String? {
        guard let data = request.details?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["summary"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func treeEditResult(_ request: AdminRequest) -> [String] {
        guard let p = request.treeEditPayload, let action = p.resolvedAction else {
            return [L10n.t("قُبل الطلب.", "The request was approved.")]
        }
        let target = p.targetMemberName ?? p.parentMemberName ?? ""
        switch action {
        case .add:
            if let name = p.newMemberName, !name.isEmpty {
                return [L10n.t("أُضيف: ", "Added: ") + name + (target.isEmpty ? "" : L10n.t(" — تحت ", " — under ") + target)]
            }
            // طلبات شجرة النساء والإضافات اليدوية: الإدارة تنفّذها بنفسها حسب الملاحظات
            return [L10n.t("قُبل — التنفيذ يدوي كما في ملاحظات الطلب.", "Approved — carried out manually per the request notes.")]
        case .editName:
            return [L10n.t("تغيّر الاسم إلى: ", "Name changed to: ") + (p.newName ?? "—")]
        case .editPhone:
            return [L10n.t("تغيّر الرقم إلى: ", "Phone changed to: ") + "\u{2066}" + KuwaitPhone.display(p.newPhone ?? "") + "\u{2069}"]
        case .editBirth:
            return [L10n.t("تغيّر تاريخ الميلاد إلى: ", "Birth date changed to: ") + (DateHelper.displayDate(p.newBirthDate ?? "") ?? (p.newBirthDate ?? "—"))]
        case .deceased:
            let date = p.deathDate.flatMap { DateHelper.displayDate($0) }
            return [L10n.t("سُجّلت الوفاة", "Death recorded") + (date.map { L10n.t(" بتاريخ ", " on ") + $0 } ?? "") + "."]
        case .addDeathDate:
            return [L10n.t("أُضيف تاريخ الوفاة: ", "Death date added: ") + (p.deathDate.flatMap { DateHelper.displayDate($0) } ?? "—")]
        case .addPhoto:
            return [L10n.t("اعتُمدت الصورة المقترحة.", "The suggested photo was approved.")]
        case .delete:
            return [L10n.t("حُذف من الشجرة: ", "Removed from the tree: ") + (target.isEmpty ? "—" : target)]
        case .other:
            return [AdminAllRequestsView.profileReasonTitle(p.reason).map { L10n.t("قُبل: ", "Approved: ") + $0 }
                    ?? L10n.t("قُبل الطلب.", "The request was approved.")]
        }
    }
}

// MARK: - «المرسل»

struct AdminSenderInfo {
    let steps: [DSPathStep]
    /// «الاسم الرباعي · الدور · الصلة» — nil = غير معروف
    let sender: String?
    let device: String
    let deviceRecorded: Bool
    let time: String
    /// طلب زوجة/أم من شجرة النساء: «الزوجة المختارة» + اسمها كاملاً — nil = لا سطر
    var chosenLabel: String? = nil
    var chosenName: String? = nil
    /// المرسل في الشجرة — «أرسله» يفتح ورقته (طلب المالك ٢٠٢٦-١١-١٢)
    var senderId: UUID? = nil
}

struct AdminSenderSection: View {
    let info: AdminSenderInfo
    var index: Int = 2
    /// ورقة المرسل («أرسله» ←)
    @State private var openSender: AdminMemberSheetContext?

    var body: some View {
        DSComposerSection(title: L10n.t("المرسل", "Sender"),
                          icon: "paperplane.fill",
                          tint: AppSection.admin.ink,
                          index: index) {
            if !info.steps.isEmpty {
                DSPathSteps(steps: info.steps)
                    .accessibilityLabel(L10n.t("من أين أُرسل", "Sent from"))
            }
            if let chosenName = info.chosenName, let chosenLabel = info.chosenLabel {
                DSTileGrid([.wide(DSFieldTileFace(label: chosenLabel, value: chosenName, glyph: .none))])
            }
            DSTileGrid([
                .wide(senderTile),
                .half(DSFieldTileFace(label: L10n.t("الجهاز", "Device"), value: info.device,
                                      isPlaceholder: !info.deviceRecorded, glyph: .none)),
                .half(DSFieldTileFace(label: L10n.t("الوقت", "Time"), value: info.time, glyph: .none)),
            ])
        }
        .dsTallBox(item: $openSender) { context in
            AdminMemberSheet(ids: context.ids, start: context.start)
        }
    }

    /// «أرسله»: الاسم الرباعي · الدور · الصلة — والضغط يفتح تفاصيل العضو حين يُعرف
    @ViewBuilder
    private var senderTile: some View {
        let face = DSFieldTileFace(label: L10n.t("أرسله", "Sent by"),
                                   value: info.sender ?? L10n.t("غير معروف", "Unknown"),
                                   isPlaceholder: info.sender == nil,
                                   glyph: info.senderId == nil ? .none : .open)
        if let id = info.senderId {
            Button { openSender = AdminMemberSheetContext(ids: [id], start: 0) } label: { face }
                .buttonStyle(DSPressStyle())
                .accessibilityHint(L10n.t("يفتح تفاصيل العضو", "Opens the member's details"))
        } else {
            face
        }
    }
}

// MARK: - «ما تم في الطلب» و«النتيجة» (العرض فقط)

struct AdminHandlingSections: View {
    let request: AdminRequest
    /// nil = يُحمَّل
    let events: [AdminRequestEvent]?
    let lookup: (UUID) -> FamilyMember?
    var startIndex: Int = 3
    /// «رُبط بـ: …» لطلب الانضمام المقبول — أول سطر في «النتيجة»
    var link: String? = nil

    var body: some View {
        DSComposerSection(title: L10n.t("ما تم في الطلب", "What happened"),
                          icon: "list.number",
                          tint: AppSection.admin.ink,
                          index: startIndex) {
            if events == nil {
                HStack(spacing: DS.Spacing.sm) {
                    ProgressView()
                    Text(L10n.t("جارٍ تحميل سجلّ الطلب…", "Loading the request log…"))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                DSPathSteps(steps: timeline)
            }
        }
        DSComposerSection(title: L10n.t("النتيجة", "Outcome"),
                          icon: "checkmark.seal",
                          tint: AppSection.admin.ink,
                          index: startIndex + 1) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(Array(AdminTrailText.result(request).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .dsFieldFont(.fieldValue)
                        .foregroundColor(DS.Color.tileValue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let link {
                    Label(link, systemImage: "link")
                        .dsFieldFont(.fieldValueStrong)
                        .foregroundColor(DS.Color.tileValue)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsRowBox()
        }
    }

    private func by(_ id: UUID?, role: String?) -> String {
        if id == nil, role == "server" { return L10n.t("بواسطة: السيرفر", "By: server") }
        return L10n.t("بواسطة: ", "By: ")
            + (AdminTrailText.person(id, fallbackRole: role, lookup: lookup) ?? AdminTrailText.notRecorded)
    }

    private func when(_ raw: String?) -> String {
        DateHelper.displayDateTime(raw) ?? AdminTrailText.notRecorded
    }

    /// السجلّ إن وُجد، وإلا ما تسمح به أعمدة الطلب القديم
    private var timeline: [DSPathStep] {
        if let events, !events.isEmpty {
            return events.map { e in
                var lines = [by(e.actorId, role: e.actorRole), when(e.at)]
                if let note = e.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    lines.append(note)
                }
                return DSPathStep(icon: AdminTrailText.actionIcon(e.action), title: AdminTrailText.actionTitle(e.action),
                                  lines: lines, tint: AdminTrailText.actionTint(e.action))
            }
        }
        var steps = [DSPathStep(icon: AdminTrailText.actionIcon("sent"), title: AdminTrailText.actionTitle("sent"),
                                lines: [by(request.requesterId, role: nil), when(request.createdAt)])]
        let decision = AdminTrailText.decision(request, events: nil)
        let action: String = {
            switch decision {
            case .approved: return "approved"
            case .rejected: return "rejected"
            case .executed: return "executed"
            case .replied: return "replied"
            case .other: return "status:\(request.status)"
            }
        }()
        var lines = [by(AdminTrailText.handlerId(request, events: nil), role: nil),
                     DateHelper.displayDateTime(request.repliedAt) ?? (L10n.t("الوقت: ", "Time: ") + AdminTrailText.notRecorded)]
        if let reply = request.adminReply?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty { lines.append(reply) }
        steps.append(DSPathStep(icon: AdminTrailText.actionIcon(action), title: AdminTrailText.actionTitle(action),
                                lines: lines, tint: AdminTrailText.actionTint(action)))
        return steps
    }
}

// MARK: - صفّ «تمت معالجتها»

struct AdminHandledRow: View {
    let request: AdminRequest
    let events: [AdminRequestEvent]?
    let lookup: (UUID) -> FamilyMember?
    let onTap: () -> Void

    /// المعني بالطلب: طلب شجرة النساء باسمه من الملاحظات، والإضافة بالاسم الجديد، وإلا العضو المستهدف
    private var subject: String? {
        let p = request.treeEditPayload
        if let women = p?.notes.flatMap(WomenTreeRequestLines.init) { return women.fullName }
        if p?.resolvedAction == .add, let name = p?.newMemberName, !name.isEmpty { return name }
        if let name = p?.targetMemberName, !name.isEmpty { return name }
        return request.member?.fourPartName ?? lookup(request.memberId)?.fourPartName
    }

    var body: some View {
        let decision = AdminTrailText.decision(request, events: events)
        let handler = AdminTrailText.person(AdminTrailText.handlerId(request, events: events), lookup: lookup)
        let time = DateHelper.displayDateTime(AdminTrailText.handledAt(request, events: events))
        // §10: شريحة النوع قبل العنوان، و«مقدّم الطلب» فوق «بواسطة» (إلا إن كان الطلب عن نفسه — اسمه في العنوان)
        let facts = AdminRequestFacts.of(request, member: lookup)
        let selfRequest = facts.map { $0.requester != $0.requesterShort } ?? true
        Button(action: onTap) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                DSFieldIcon(name: AdminTrailText.typeIcon(request), tint: decision.tint)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xsm) {
                        if let kind = facts?.kind { AdminRequestKindChip(kind: kind) }
                        Text(AdminTrailText.typeTitle(request) + (subject.map { " — " + $0 } ?? ""))
                            .dsFont(.adminRowTitle)
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if let facts, !selfRequest, facts.requesterShort != "—" {
                        Text(AdminRequestFactText.requesterLine(facts.requesterShort))
                            .dsFont(.adminRowSubtitle)
                            .foregroundColor(DS.Color.textSecondary)
                            .lineLimit(1)
                    }
                    Text(L10n.t("بواسطة: ", "By: ") + (handler ?? AdminTrailText.notRecorded))
                        .dsFont(.adminRowSubtitle)
                        .foregroundColor(handler == nil ? DS.Color.textTertiary : DS.Color.textSecondary)
                        .lineLimit(2)
                    Text(time ?? L10n.t("وقت المعالجة غير مسجّل", "Handling time not recorded"))
                        .dsFont(.adminRowSubtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .monospacedDigit()
                }
                Spacer(minLength: DS.Spacing.xs)
                decisionBadge(decision)
            }
            .padding(DS.Card.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous).fill(DS.Color.fieldFill))
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.t("يعرض ما تم في الطلب", "Shows what happened"))
    }

    private func decisionBadge(_ decision: AdminTrailText.Decision) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            Image(systemName: decision.icon).dsGlyph(DS.Glyph.xs, weight: .bold)
            Text(decision.title).dsFont(.badge)
        }
        .foregroundColor(decision.tint.dsReadableGlyph)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xxs)
        .background(Capsule().fill(decision.tint.opacity(DS.Opacity.tintFill)))
    }
}
