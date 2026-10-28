import Foundation
import Supabase
import SwiftUI
import Combine

/// ViewModel for managing admin requests: deceased reports, child add requests,
/// phone change requests, news reports, member approval/rejection, and account activation.
/// Extracted from AuthViewModel to reduce its size and improve separation of concerns.
@MainActor
class AdminRequestViewModel: ObservableObject {

    // MARK: - Supabase Client

    let supabase = SupabaseConfig.client

    // MARK: - Published Properties

    @Published var deceasedRequests: [AdminRequest] = []
    @Published var childAddRequests: [AdminRequest] = []
    @Published var phoneChangeRequests: [PhoneChangeRequest] = []
    @Published var newsReportRequests: [AdminRequest] = []
    @Published var treeEditRequests: [AdminRequest] = []
    @Published var nameChangeRequests: [AdminRequest] = []
    @Published var contactMessages: [AdminRequest] = []
    /// طلبات حذف الحساب المعلّقة (`account_delete`) — المالك/المدير فقط
    @Published var accountDeleteRequests: [AdminRequest] = []
    /// طلبات الخصوصية المعلّقة (`privacy_request`) — المالك/المدير/المراقب
    @Published var privacyRequests: [AdminRequest] = []
    /// «إضافة قريبة» المعلّقة (`relative_add`) — المالك/المدير/المراقب
    @Published var relativeAddRequests: [AdminRequest] = []
    /// طلبات العضو الحالي المعلّقة — يتابعها ويلغيها من «حسابي» (طلباتي).
    @Published var myPendingRequests: [AdminRequest] = []
    /// «مسار الموافقات»: صفوف طلبات الانضمام/الربط المعلّقة (مرحلتها) — تُجلب والمفتاح شغّال فقط
    @Published var joinApprovalRequests: [AdminRequest] = []
    /// «مسار الموافقات»: سجل خطوات كل طلب فُتحت تفاصيله (`admin_request_steps`)
    @Published var approvalSteps: [UUID: [AdminRequestStep]] = [:]
    /// «مسار الموافقات ٢» (طلب المالك ٢٠٢٦-١٠-١٦): الردود الجاهزة — nil في «متاح» = لم تُجلب بعد،
    /// false = الجدول غير موجود على السيرفر (تختفي الشرائح والإعداد)
    @Published var approvalTemplates: [ApprovalTemplate] = []
    @Published var approvalTemplatesAvailable: Bool? = nil
    /// ملاحظات الإدارة الداخلية لكل طلب فُتح (لا يراها العضو) — false = الجدول غير موجود (يختفي القسم)
    @Published var approvalNotes: [UUID: [AdminRequestNote]] = [:]
    @Published var approvalNotesAvailable: Bool? = nil
    /// مفتاح «مسار الموافقات» من «إعدادات التطبيق» — منشور هنا لتُعاد رسم الشاشات فور تبديله.
    /// العمود غير موجود (السيرفر لم يُرحَّل) = false = الطريقة القديمة تماماً
    @Published private(set) var approvalsWorkflowOn: Bool = false
    private var approvalsFlagSink: AnyCancellable?
    @Published var isLoading: Bool = false
    @Published var mergeResult: MergeResult? = nil
    @Published var errorMessage: String? = nil

    /// معرّفات رسائل التواصل التي قرأها هذا المشرف.
    /// مصدرها جدول `admin_message_reads` على السيرفر ليتطابق العدّاد بين الآيفون
    /// والأندرويد لنفس الحساب (طلب المالك). نسخة محلية في UserDefaults تُستخدم
    /// ريثما تصل بيانات السيرفر، ولحفظ ما عُلِّم بلا اتصال حتى تُرفع لاحقاً.
    @Published private(set) var readContactMessageIds: Set<UUID> = AdminRequestViewModel.loadReadIds()

    private static let readIdsKey = "readContactMessageIds_v1"
    /// معرّفات عُلِّمت مقروءة ولم تُرفع للسيرفر بعد (انقطاع اتصال) — تُرفع عند أول جلب ناجح
    private var unsyncedReadIds: Set<UUID> = AdminRequestViewModel.loadUnsyncedIds()
    private static let unsyncedIdsKey = "unsyncedContactReadIds_v1"

    private struct ContactMessageRead: Encodable {
        let message_id: String
        let member_id: String
    }

    private struct ContactMessageReadRow: Decodable {
        let message_id: UUID
    }

    private static func loadIds(_ key: String) -> Set<UUID> {
        guard let arr = UserDefaults.standard.array(forKey: key) as? [String] else { return [] }
        return Set(arr.compactMap(UUID.init(uuidString:)))
    }

    private static func loadReadIds() -> Set<UUID> { loadIds(readIdsKey) }
    private static func loadUnsyncedIds() -> Set<UUID> { loadIds(unsyncedIdsKey) }

    private func persistReadIds() {
        UserDefaults.standard.set(readContactMessageIds.map { $0.uuidString }, forKey: Self.readIdsKey)
        UserDefaults.standard.set(unsyncedReadIds.map { $0.uuidString }, forKey: Self.unsyncedIdsKey)
    }

    /// جلب حالة «مقروء» من السيرفر، ورفع ما تبقّى محلياً بلا مزامنة
    func fetchContactMessageReads() async {
        guard let memberId = currentUser?.id else { return }
        if !unsyncedReadIds.isEmpty { await uploadReads(Array(unsyncedReadIds), memberId: memberId) }
        do {
            let rows: [ContactMessageReadRow] = try await supabase
                .from("admin_message_reads")
                .select("message_id")
                .eq("member_id", value: memberId.uuidString)
                .execute()
                .value
            readContactMessageIds = Set(rows.map { $0.message_id }).union(unsyncedReadIds)
            persistReadIds()
        } catch {
            Log.fetchError("فشل جلب حالة قراءة الرسائل", error)
        }
    }

    /// رفع صفوف «مقروء» — ما يفشل يبقى في `unsyncedReadIds` لمحاولة لاحقة
    private func uploadReads(_ ids: [UUID], memberId: UUID) async {
        guard !ids.isEmpty else { return }
        let rows = ids.map { ContactMessageRead(message_id: $0.uuidString, member_id: memberId.uuidString) }
        do {
            try await supabase
                .from("admin_message_reads")
                .upsert(rows, onConflict: "message_id,member_id")
                .execute()
            unsyncedReadIds.subtract(ids)
            persistReadIds()
        } catch {
            unsyncedReadIds.formUnion(ids)
            persistReadIds()
            Log.error("فشل حفظ حالة قراءة الرسائل: \(error.localizedDescription)")
        }
    }

    /// تعليم رسالة كمقروءة — تظهر فوراً ثم تُحفظ على السيرفر
    func markContactMessageRead(_ id: UUID) {
        guard !readContactMessageIds.contains(id) else { return }
        readContactMessageIds.insert(id)
        unsyncedReadIds.insert(id)
        persistReadIds()
        guard let memberId = currentUser?.id else { return }
        Task { await uploadReads([id], memberId: memberId) }
    }

    /// تعليم كل الرسائل الحالية كمقروءة
    func markAllContactMessagesRead() {
        let newIds = Set(contactMessages.map { $0.id }).subtracting(readContactMessageIds)
        guard !newIds.isEmpty else { return }
        readContactMessageIds.formUnion(newIds)
        unsyncedReadIds.formUnion(newIds)
        persistReadIds()
        guard let memberId = currentUser?.id else { return }
        Task { await uploadReads(Array(newIds), memberId: memberId) }
    }

    /// عدد رسائل التواصل غير المقروءة (لم يضغط عليها المدير بعد).
    /// يُعرض كـ badge في لوحة الإدارة. يتقلّص فور الضغط على الرسالة.
    var unreadContactMessagesCount: Int {
        contactMessages.filter { !readContactMessageIds.contains($0.id) }.count
    }

    /// عدد الرسائل التي تنتظر التعامل (status == pending) — للفلاتر داخل صندوق الوارد.
    var pendingContactMessagesCount: Int {
        contactMessages.filter { $0.status == ApprovalStatus.pending.rawValue }.count
    }
    
    enum MergeResult {
        case success(String)
        case failure(String)
    }

    // MARK: - Throttle

    private let throttler = FetchThrottler()

    // MARK: - Dependencies (weak to avoid retain cycles)

    weak var authVM: AuthViewModel?
    weak var memberVM: MemberViewModel?
    weak var notificationVM: NotificationViewModel?
    weak var newsVM: NewsViewModel?

    // MARK: - Configure

    func configure(authVM: AuthViewModel, memberVM: MemberViewModel, notificationVM: NotificationViewModel, newsVM: NewsViewModel? = nil) {
        self.authVM = authVM
        self.memberVM = memberVM
        self.notificationVM = notificationVM
        self.newsVM = newsVM
        approvalsFlagSink = authVM.appSettingsVM?.$settings
            .map { $0.approvalsWorkflow == true }
            .removeDuplicates()
            .sink { [weak self] isOn in self?.approvalsWorkflowOn = isOn }
    }

    // MARK: - Private Helpers

    private var currentUser: FamilyMember? { authVM?.currentUser }
    private var canModerate: Bool { authVM?.canModerate ?? false }
    private var isAdmin: Bool { authVM?.isAdmin ?? false }
    /// قبول/رفض الطلبات: owner+admin+monitor (المشرف يقدر يقبل بس لا يرفض).
    /// نطابق `AuthViewModel.canRejectRequests` (راجع CLAUDE.md).
    private var canRejectRequests: Bool { authVM?.canRejectRequests ?? false }

    /// طلبك أنت يعالجه غيرك (إلا المالك) — السيرفر يرفضه أيضاً (فحص الثغرات)
    private func isOwnRequest(requesterId: UUID?, memberId: UUID?) -> Bool {
        guard let me = currentUser?.id, authVM?.currentUser?.role != .owner else { return false }
        if requesterId == me || memberId == me {
            errorMessage = L10n.t("طلبك يوافق عليه مسؤول آخر.", "Another admin must approve your own request.")
            return true
        }
        return false
    }

    // MARK: - «ما زال معلّقاً» قبل التطبيق (فحص الثغرات ب-٧)

    /// طلب عالجه مسؤول آخر قبلك (أو ضغطتان متتاليتان)
    private static var alreadyHandledMessage: String {
        L10n.t("عولج هذا الطلب من قبل — لم يُطبَّق شيء.",
               "This request was already handled — nothing was applied.")
    }

    // MARK: - القرار من السيرفر (decide_admin_request — أ-٣، ٢٠٢٦-١٠-٠٧)

    /// نتيجة `decide_admin_request`: السيرفر تحقّق من الصلاحية وقفل الطلب و«معلّق»، وطبّق ما كان
    /// التطبيق يكتبه، وكتب الإشعارات، وأغلق الطلب — في معاملة واحدة. يبقى للتطبيق ما لا يقدر عليه السيرفر.
    nonisolated struct DecisionResult: Decodable, Sendable {
        nonisolated struct AdminPush: Decodable, Sendable { let title: String; let body: String; let kind: String }
        nonisolated struct Death: Decodable, Sendable {
            let memberId: UUID
            let name: String
            let isFemale: Bool
            let deathDate: String?
            enum CodingKeys: String, CodingKey {
                case name
                case memberId = "member_id"
                case isFemale = "is_female"
                case deathDate = "death_date"
            }
        }
        nonisolated struct Cleanup: Decodable, Sendable { let bucket: String; let paths: [String] }
        let status: String
        let requesterNotified: Bool?
        let adminPush: AdminPush?
        let deathAnnouncement: Death?
        let storageCleanup: Cleanup?
        let newMemberId: UUID?
        enum CodingKeys: String, CodingKey {
            case status
            case requesterNotified = "requester_notified"
            case adminPush = "admin_push"
            case deathAnnouncement = "death_announcement"
            case storageCleanup = "storage_cleanup"
            case newMemberId = "new_member_id"
        }
    }

    /// قبول/رفض طلب مراجعة على السيرفر. بعد النجاح يكمل التطبيق ما بقي له فقط:
    /// الدفع الخارجي للإدارة (`push-admins` كما كان)، حذف ملف اقتراح الصورة (Storage API)،
    /// ومربّع «إعلان وفاة». الفشل = لا شيء طُبّق والطلب على حاله، مع رسالة واضحة.
    /// - silent: القبول الجماعي لإضافة الأبناء بلا إشعارات (كما كان).
    @discardableResult
    func decideOnServer(_ requestId: UUID, approve: Bool, reason: String? = nil, silent: Bool = false) async -> DecisionResult? {
        nonisolated struct Overrides: Encodable { let silent: Bool }
        nonisolated struct Params: Encodable {
            let p_request_id: String
            let p_decision: String
            let p_reason: String?
            let p_overrides: Overrides?
        }
        let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let result: DecisionResult = try await supabase
                .rpc("decide_admin_request", params: Params(
                    p_request_id: requestId.uuidString,
                    p_decision: approve ? "approve" : "reject",
                    p_reason: (trimmedReason?.isEmpty ?? true) ? nil : trimmedReason,
                    p_overrides: silent ? Overrides(silent: true) : nil))
                .execute()
                .value
            decisionOutcomes[requestId] = true
            if let push = result.adminPush {
                await notificationVM?.pushAdminsExternally(title: push.title, body: push.body, kind: push.kind)
            }
            if let cleanup = result.storageCleanup, !cleanup.paths.isEmpty {
                _ = try? await supabase.storage.from(cleanup.bucket).remove(paths: cleanup.paths)
            }
            if let death = result.deathAnnouncement {
                let target = DeathAnnouncementTarget(id: death.memberId, name: death.name,
                                                     isFemale: death.isFemale, deathDate: death.deathDate)
                let canAnnounce = authVM?.isAdmin == true   // للمالك والمدير (السيرفر 20261007130000)
                Task { await DeathAnnouncementPresenter.offer(target, canAnnounce: canAnnounce) }
            }
            if result.requesterNotified == true {
                await notificationVM?.fetchNotifications(force: true)
            }
            return result
        } catch {
            Log.error("[Decide] \(approve ? "قبول" : "رفض") \(requestId) فشل: \(error)")
            decisionOutcomes[requestId] = false
            errorMessage = Self.decisionErrorMessage(error)
            return nil
        }
    }

    /// رسائل عربية واضحة لأخطاء `decide_admin_request` (الـ hint = اسم الخطأ)
    static func decisionErrorMessage(_ error: Error) -> String {
        let pg = error as? PostgrestError
        return decisionMessage(forKey: pg?.hint ?? pg?.message ?? "", serverMessage: pg?.message)
    }

    private static func decisionMessage(forKey key: String, serverMessage: String? = nil) -> String {
        switch key {
        case "already_handled", "request_not_found":
            return alreadyHandledMessage
        case "own_request":
            return L10n.t("طلبك يوافق عليه مسؤول آخر.", "Another admin must approve your own request.")
        case "not_allowed":
            return L10n.t("هذا الطلب خارج مجال دورك — لم يُطبَّق شيء.",
                          "This request is outside your role — nothing was applied.")
        case "phone_in_use":
            return L10n.t("الرقم مستخدم من عضو آخر — لم يُطبَّق شيء.",
                          "The number belongs to another member — nothing was applied.")
        case "bad_payload":
            return L10n.t("بيانات الطلب غير صالحة فلم يُطبَّق شيء. ارفض الطلب واطلب من العضو إرساله من جديد.",
                          "The request data is invalid, so nothing was applied. Reject it and ask the member to resend.")
        case "not_authenticated":
            return L10n.t("انتهت الجلسة — سجّل الدخول من جديد.", "Your session expired — please sign in again.")
        case "unsupported_type", "bad_decision":
            return L10n.t("هذا النوع من الطلبات لا يُعالج من هنا.", "This request type can't be handled here.")
        case "family_links_protected":
            return serverMessage ?? L10n.t("لا يمكن الحذف: مرتبط بأفراد في العائلة.", "Can't delete: linked to family members.")
        case "requester_gone":
            return L10n.t("صاحب الطلب لم يعد موجوداً — ارفض الطلب.", "The requester no longer exists — reject the request.")
        // «مسار الموافقات» (advance_admin_request، والموافقة المباشرة والمفتاح شغّال)
        case "approval_needs_manager":
            return L10n.t("الطلب يحتاج اعتماد المدير قبل التنفيذ", "The request needs the manager's approval before it's carried out")
        case "workflow_off":
            return L10n.t("مسار الموافقات مطفأ الحين — حدّث الصفحة.", "The approvals path is off now — refresh the page.")
        case "wrong_stage":
            return L10n.t("الطلب انتقل لمرحلة ثانية — حدّث الصفحة وشوف وين وصل.",
                          "The request has moved to another stage — refresh to see where it is.")
        case "note_required":
            return L10n.t("اكتب الملاحظة أولاً.", "Write the note first.")
        case "bad_action":
            return L10n.t("إجراء غير معروف — حدّث التطبيق وحاول مرة أخرى.", "Unknown action — update the app and try again.")
        default:
            return L10n.t("تعذّر تنفيذ القرار — لم يُطبَّق شيء. حاول مرة أخرى.",
                          "Couldn't complete the decision — nothing was applied. Please try again.")
        }
    }

    /// حذف العنصر محلياً فوراً مع أنيميشن ثم تحديث من السيرفر بعد تأخير
    private func removeLocallyThenRefresh<T: Identifiable>(
        from array: inout [T],
        id: T.ID,
        refresh: @escaping () async -> Void
    ) {
        withAnimation(.snappy(duration: 0.25)) {
            array.removeAll { $0.id as AnyHashable == id as AnyHashable }
        }
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refresh()
        }
    }

    /// نتيجة آخر قرار على السيرفر لكل طلب (`decideOnServer`) — تقرؤها العمليات الجماعية لعدّ الناجح فعلاً
    private var decisionOutcomes: [UUID: Bool] = [:]
    /// عمل الخلفية لكل طلب أُزيل تفاؤلياً — العمليات الجماعية تنتظره قبل قراءة النتيجة
    private var pendingDecisionWork: [AnyHashable: Task<Void, Never>] = [:]

    /// حذف فوري ثم تنفيذ API + تحديث بالخلفية (optimistic)
    private func optimisticRemove<T: Identifiable>(
        from array: inout [T],
        id: T.ID,
        apiWork: @escaping () async -> Void,
        refresh: @escaping () async -> Void
    ) {
        withAnimation(.snappy(duration: 0.25)) {
            array.removeAll { $0.id as AnyHashable == id as AnyHashable }
        }
        let key = id as AnyHashable
        let work = Task { await apiWork() }
        pendingDecisionWork[key] = work
        Task { [weak self] in
            await work.value
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refresh()
            self?.pendingDecisionWork.removeValue(forKey: key)
        }
    }

    /// للعمليات الجماعية: بعد استدعاء قبول/رفض طلب، انتظر تنفيذه على السيرفر وأرجع هل نجح فعلاً.
    /// طلب رفضه حارس محلي (صلاحية، طلبك أنت…) لا عمل له ولا نتيجة → false
    func awaitDecision(_ requestId: UUID) async -> Bool {
        if let work = pendingDecisionWork.removeValue(forKey: requestId as AnyHashable) {
            await work.value
        }
        return decisionOutcomes.removeValue(forKey: requestId) ?? false
    }

    // Schema error helpers delegated to ErrorHelper

    /// Helper to get a member name by ID — fallback to UUID if not found
    private func getSafeMemberName(for memberId: UUID) -> String {
        return memberById(memberId)?.displayFullName ?? memberId.uuidString
    }

    /// Lookup a member by ID from authVM's member cache
    private func memberById(_ id: UUID) -> FamilyMember? {
        return memberVM?.member(byId: id)
    }

    // MARK: - Tree Edit Requests

    /// إرسال طلب تعديل الشجرة (إضافة / تعديل اسم / حذف) — v2 structured payload
    /// رفع صورة مقترحة لطلب «إضافة صورة» — تُخزَّن باسم
    /// photo_suggestion_<callerUid>_<uuid>.jpg في bucket الأفاتار (عام). الاسم
    /// يطابق سياسة RLS (`photo_suggestion_<auth.uid>_%`) فيُسمح لأي عضو مسجّل
    /// برفعه؛ ولا يُطبَّق على الملف إلا بعد موافقة الإدارة.
    /// تُعيد الرابط العام لتضمينه في حمولة الطلب، أو nil عند الفشل.
    func uploadPhotoSuggestion(_ image: UIImage) async -> String? {
        guard let imageData = ImageProcessor.process(image, for: .avatar) else { return nil }
        guard let uid = currentUser?.id.uuidString.lowercased() else {
            Log.error("[TreeEdit] Photo suggestion: no current user")
            return nil
        }
        let fileName = "photo_suggestion_\(uid)_\(UUID().uuidString.lowercased()).jpg"
        do {
            try await supabase.storage
                .from("avatars")
                .upload(fileName, data: imageData, options: FileOptions(contentType: "image/jpeg", upsert: true))
            let publicUrl = try supabase.storage
                .from("avatars")
                .getPublicURL(path: fileName)
            return publicUrl.absoluteString
        } catch {
            Log.error("[TreeEdit] Photo suggestion upload failed: \(error)")
            return nil
        }
    }

    func submitTreeEditRequest(payload: TreeEditPayload) async -> Bool {
        guard NetworkMonitor.shared.requireOnline() else { return false }
        guard let user = currentUser else { return false }
        self.isLoading = true
        defer { self.isLoading = false }

        do {
            let jsonData = try JSONEncoder().encode(payload)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""

            // member_id: دايماً يكون العضو المعني — للإضافة = الطالب نفسه (لأن الابن مو موجود بعد)
            let targetId: String
            if let tid = payload.targetMemberId, !tid.isEmpty {
                targetId = tid
            } else {
                targetId = user.id.uuidString
            }

            let requestId = UUID()
            let basePayload: [String: AnyEncodable] = [
                "id": AnyEncodable(requestId.uuidString),
                "member_id": AnyEncodable(targetId),
                "requester_id": AnyEncodable(user.id.uuidString),
                "request_type": AnyEncodable(RequestType.treeEdit.rawValue),
                "status": AnyEncodable(ApprovalStatus.pending.rawValue),
                "details": AnyEncodable(jsonString)
            ]

            do {
                var dbPayload = basePayload
                dbPayload["new_value"] = AnyEncodable(payload.action)
                try await supabase.from("admin_requests").insert(dbPayload).execute()
            } catch {
                if ErrorHelper.isMissingColumn(error, column: "new_value") {
                    try await supabase.from("admin_requests").insert(basePayload).execute()
                } else {
                    throw error
                }
            }

            let memberName = payload.targetMemberName ?? payload.newMemberName ?? ""
            let actionLabelAr = payload.resolvedAction?.arabicLabel ?? payload.action
            let actionLabelEn = payload.resolvedAction?.englishLabel ?? payload.action
            let requesterFirstName = user.firstName
            let bodyAr: String = memberName.isEmpty
                ? "\(requesterFirstName) قدّم طلب \(actionLabelAr)"
                : "\(requesterFirstName) قدّم طلب \(actionLabelAr) لـ «\(memberName)»"
            let bodyEn: String = memberName.isEmpty
                ? "\(requesterFirstName) submitted a \(actionLabelEn) request"
                : "\(requesterFirstName) submitted a \(actionLabelEn) request for «\(memberName)»"
            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("طلب تعديل شجرة العائلة", "Family Tree Edit Request"),
                body: L10n.t(bodyAr, bodyEn),
                kind: NotificationKind.treeEdit.rawValue,
                requestId: requestId,
                requestType: RequestType.treeEdit.rawValue
            )

            Log.info("[TreeEdit] Submitted: \(payload.action) — \(memberName)")
            return true
        } catch {
            Log.error("[TreeEdit] Submit failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - My Requests (member-scoped tracking)

    /// أنواع الطلبات التي يتابعها العضو في «طلباتي» (طلبات تغيير بيانات تحتاج موافقة).
    /// نستبعد البلاغات ورسائل التواصل وطلبات الانضمام (ليست تغييرات يتابعها العضو).
    private static let myTrackedRequestTypes: [String] = [
        RequestType.treeEdit.rawValue,
        RequestType.nameChange.rawValue,
        RequestType.phoneChange.rawValue,
        RequestType.deceasedReport.rawValue,
        RequestType.childAdd.rawValue
    ]

    /// ما يُضاف لـ«طلباتي» والمسار شغّال: باقي أنواع المسار التي يرسلها عضو مفعّل
    private static let myApprovalExtraTypes: [String] = [
        RequestType.familyChange.rawValue,
        RequestType.photoSuggestion.rawValue,
        RequestType.newsReport.rawValue,
        RequestType.contentReport.rawValue
    ]

    /// جلب طلبات العضو الحالي المعلّقة — يقرأ صفوفه فقط (RLS: requester_id = auth.uid()).
    func fetchMyPendingRequests(force: Bool = false) async {
        guard let uid = currentUser?.id else {
            myPendingRequests = []
            return
        }
        guard throttler.canFetch(key: "myRequests", interval: 20, force: force) || myPendingRequests.isEmpty else { return }
        throttler.didFetch(key: "myRequests")
        // مفتاح «مسار الموافقات» قد يتبدّل أثناء الجلسة — يُقرأ طازجاً مع «طلباتي» (عمود واحد)
        await refreshApprovalsFlag()
        do {
            // «مسار الموافقات»: كل طلب في المسار قد يسأل عنه المختص — فيُتابَع هنا ليُرَد عليه. الأنواع الإضافية
            // تُجلب دائماً وتبقى إذا كان المفتاح شغّالاً أو الصف نفسه يحمل مرحلة من السيرفر (لا يعتمد على المفتاح
            // المحلي وحده — بلاغ المالك ٢٠٢٦-١٠-١٥)؛ مطفأ وبلا مرحلة = «طلباتي» كما كانت
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:members_masked!member_id(*)")
                .eq("requester_id", value: uid.uuidString)
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .in("request_type", values: Self.myTrackedRequestTypes + Self.myApprovalExtraTypes)
                .order("created_at", ascending: false)
                .execute()
                .value
            let workflowOn = approvalsWorkflowOn
            self.myPendingRequests = requests.filter {
                Self.myTrackedRequestTypes.contains($0.requestType) || workflowOn || $0.stage != nil
            }
        } catch {
            Log.fetchError("فشل جلب طلباتي المعلّقة", error)
        }
    }

    /// طلبات «إضافة ابن» المعلّقة عن ابن حُذف — تُحذف معه حتى لا يبقى طلب يشير لسجل غير موجود (المالك والمدير)
    func deleteChildAddRequests(childId: UUID) async {
        do {
            try await supabase
                .from("admin_requests")
                .delete()
                .eq("request_type", value: RequestType.childAdd.rawValue)
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .in("new_value", values: [childId.uuidString, childId.uuidString.lowercased()])
                .execute()
        } catch {
            Log.error("[ChildAdd] تعذّر حذف طلب الإضافة بعد حذف الابن: \(error.localizedDescription)")
        }
    }

    /// سحب/إلغاء طلب معلّق للعضو نفسه — حذف الصف من admin_requests.
    /// RLS يسمح للعضو بحذف صفوفه فقط (requester_id = auth.uid()).
    func cancelMyRequest(_ request: AdminRequest) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard let uid = currentUser?.id, request.requesterId == uid else {
            Log.warning("[MyRequests] محاولة إلغاء طلب لا يخص المستخدم — تم التجاهل")
            return
        }
        errorMessage = nil
        // إزالة فورية محلياً ثم الحذف — يُرجَع الصف مكانه إن لم يُحذف شيء
        let originalIndex = myPendingRequests.firstIndex(where: { $0.id == request.id })
        withAnimation(.snappy(duration: 0.25)) {
            myPendingRequests.removeAll { $0.id == request.id }
        }
        nonisolated struct DeletedRow: Decodable { let id: UUID }
        do {
            // المعلّق فقط، ونطلب الصفوف المحذوفة: صفر صفوف (عُولج الطلب أو منعته السياسة) لا يعطي خطأ
            // فكان الطلب «يرجع» بعد اختفائه بلا تفسير
            let deleted: [DeletedRow] = try await supabase
                .from("admin_requests")
                .delete()
                .eq("id", value: request.id.uuidString)
                .eq("requester_id", value: uid.uuidString)
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .select("id")
                .execute()
                .value
            guard !deleted.isEmpty else {
                Log.warning("[MyRequests] لم يُحذف الطلب (0 صفوف): \(request.id)")
                withAnimation(.snappy(duration: 0.25)) {
                    if !myPendingRequests.contains(where: { $0.id == request.id }) {
                        myPendingRequests.insert(request, at: min(originalIndex ?? 0, myPendingRequests.count))
                    }
                }
                errorMessage = L10n.t("تعذّر سحب الطلب — ربما تمت معالجته",
                                      "Couldn't withdraw the request — it may have been handled already")
                await fetchMyPendingRequests(force: true)
                return
            }
            Log.info("[MyRequests] تم إلغاء الطلب: \(request.id)")
            // سحب «إضافة ابن» = إلغاء الإضافة: الابن المضاف يُحذف معه — لكل عضو عبر remove_self_child
            // (أبناؤه هو فقط، بلا حساب دخول)؛ قبل رفع الدالة للسيرفر: المالك والمدير بالحذف المباشر.
            // فشل الحذف لا يُعرض (الطلب نفسه سُحب) — يُسجَّل فقط
            if request.requestType == RequestType.childAdd.rawValue,
               let raw = request.newValue, let childId = UUID(uuidString: raw), let memberVM {
                switch await memberVM.removeSelfChild(id: childId) {
                case .deleted:
                    break   // removeSelfChild يُنعش الأبناء وعائلة شجرة النساء
                case .serverMissing where authVM?.canDeleteMembers == true:
                    if await memberVM.deleteMember(memberId: childId) {
                        await memberVM.fetchChildren(for: uid)   // يُنعش شجرة النساء معه
                    } else {
                        Log.warning("[MyRequests] تعذّر حذف الابن بعد سحب طلب إضافته: \(memberVM.errorMessage ?? "")")
                    }
                case .serverMissing, .failed:
                    Log.warning("[MyRequests] لم يُحذف الابن بعد سحب طلب إضافته: \(memberVM.errorMessage ?? "")")
                }
                memberVM.errorMessage = nil
            }
        } catch {
            Log.error("[MyRequests] فشل إلغاء الطلب: \(error.localizedDescription)")
            // فشل الحذف → الصف يرجع مكانه، ورسالة، ثم إعادة التحميل لاستعادة الحالة الصحيحة
            withAnimation(.snappy(duration: 0.25)) {
                if !myPendingRequests.contains(where: { $0.id == request.id }) {
                    myPendingRequests.insert(request, at: min(originalIndex ?? 0, myPendingRequests.count))
                }
            }
            errorMessage = L10n.t("تعذّر سحب الطلب — ربما تمت معالجته",
                                  "Couldn't withdraw the request — it may have been handled already")
            await fetchMyPendingRequests(force: true)
        }
    }

    // MARK: - Fetch / Mark Contact Messages

    /// رسائل التواصل من شاشة "التواصل" — للإدارة فقط.
    /// تجلب كل الـ admin_requests بنوع contact_message — سواء pending أو approved (مُعالَجة).
    func fetchContactMessages(force: Bool = false) async {
        guard throttler.canFetch(key: "contactMessages", interval: 20, force: force) || contactMessages.isEmpty else { return }
        throttler.didFetch(key: "contactMessages")
        do {
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:members_masked!member_id(*)")
                .eq("request_type", value: "contact_message")
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            self.contactMessages = requests
            await fetchContactMessageReads()
        } catch {
            Log.fetchError("فشل جلب رسائل التواصل", error)
        }
    }

    /// تعليم رسالة كمُعالَجة — يحول status من pending إلى approved.
    func markContactMessageHandled(_ request: AdminRequest) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        do {
            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable(ApprovalStatus.approved.rawValue)])
                .eq("id", value: request.id.uuidString)
                .execute()
            if let idx = contactMessages.firstIndex(where: { $0.id == request.id }) {
                contactMessages[idx].status = ApprovalStatus.approved.rawValue
            }
            Log.info("[Contact] تم تعليم الرسالة كمُعالَجة: \(request.id)")
        } catch {
            Log.error("فشل تعليم الرسالة: \(error.localizedDescription)")
        }
    }

    /// حذف رسائل تواصل (واحدة أو أكثر) من admin_requests.
    func deleteContactMessages(ids: [UUID]) async {
        guard NetworkMonitor.shared.requireOnline(), !ids.isEmpty else { return }
        do {
            try await supabase
                .from("admin_requests")
                .delete()
                .in("id", values: ids.map { $0.uuidString })
                .execute()
            contactMessages.removeAll { ids.contains($0.id) }
            Log.info("[Contact] تم حذف \(ids.count) رسالة")
        } catch {
            Log.error("فشل حذف الرسائل: \(error.localizedDescription)")
        }
    }

    /// إرسال رد إداري على رسالة تواصل.
    /// يحفظ الرد في DB + إشعار داخلي + push + إيميل (إذا للعضو إيميل).
    // MARK: - Fetch / Approve / Reject Tree Edit Requests

    func fetchTreeEditRequests(force: Bool = false) async {
        guard throttler.canFetch(key: "treeEdit", interval: 20, force: force) || treeEditRequests.isEmpty else { return }
        throttler.didFetch(key: "treeEdit")
        do {
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:members_masked!member_id(*)")
                .eq("request_type", value: RequestType.treeEdit.rawValue)
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .order("created_at", ascending: false)
                .execute()
                .value

            self.treeEditRequests = requests
        } catch {
            Log.fetchError("فشل جلب طلبات تعديل الشجرة", error)
        }
    }

    func approveTreeEditRequest(request: AdminRequest) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard canModerate else { Log.warning("قبول طلب التعديل مرفوض: لا صلاحية"); return }
        // طلبك أنت يعالجه غيرك (إلا المالك) — السيرفر يرفضه أيضاً (own_request)
        guard !isOwnRequest(requesterId: request.requesterId, memberId: request.memberId) else { return }
        let payload = request.treeEditPayload

        optimisticRemove(from: &treeEditRequests, id: request.id, apiWork: { [weak self] in
            guard let self else { return }
            // السيرفر يطبّق التعديل بحسب الإجراء ويغلق الطلب ويكتب الإشعارات في معاملة واحدة
            // (decide_admin_request — كانت «إضافة» تُحجز ثم تُرجع، وباقي الأنواع تُكتب ثم تُغلق)
            guard await self.decideOnServer(request.id, approve: true) != nil else { return }
            Log.info("[TreeEdit] Approved: \(payload?.action ?? request.newValue ?? "")")
        }, refresh: { [weak self] in
            await self?.fetchTreeEditRequests(force: true)
            await self?.memberVM?.fetchAllMembers(force: true)
            // إزالة الابن من currentMemberChildren فوراً عند الحذف لينعكس في «حسابي» و«تعديل المدير»
            if payload?.action == "حذف",
               let targetIdString = payload?.targetMemberId,
               let targetUUID = UUID(uuidString: targetIdString) {
                await MainActor.run {
                    self?.memberVM?.currentMemberChildren.removeAll { $0.id == targetUUID }
                }
            }
        })
    }

    /// زر «قبول» في إشعار الجوال: موافقة كاملة تطبّق التعديل كما في «طلبات المراجعة».
    /// كان يغيّر حالة الطلب إلى «مقبول» فقط فلا يُطبَّق شيء — مثل طلب وفاة يُقبل ويبقى
    /// صاحبه «حياً» في الشجرة. الأنواع التي تحتاج مراجعة بالشاشة (تغيير الهاتف، إضافة ابن…)
    /// تبقى معلّقة لتُعتمد من «طلبات المراجعة» بدل قبول لا يطبّق شيئاً.
    func approveFromPush(requestId: UUID, requestType: String) async -> Bool {
        guard NetworkMonitor.shared.requireOnline() else { return false }
        let tree = authVM?.canApproveTreeRequests == true
        let content = authVM?.canModerateContent == true
        do {
            let rows: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:members_masked!member_id(*)")
                .eq("id", value: requestId.uuidString)
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .limit(1)
                .execute()
                .value
            guard let request = rows.first else { return false }
            // «مسار الموافقات»: قبول الإشعار = تنفيذ، فقط للمختص والطلب معتمد — وإلا يبقى للمسار في الشاشة
            if let flow = approvalSnapshot(for: request), !canExecuteApproval(flow) {
                Log.info("[PushApprove] الطلب في مسار الموافقات (\(flow.stage.rawValue)) — يبقى للمراجعة من الشاشة")
                return false
            }
            switch request.requestType {
            case RequestType.treeEdit.rawValue where tree:
                await approveTreeEditRequest(request: request)
            case RequestType.deceasedReport.rawValue where tree:
                await approveDeceasedRequest(request: request)
            case RequestType.nameChange.rawValue where tree:
                await approveNameChangeRequest(request: request)
            case RequestType.photoSuggestion.rawValue where tree:
                await approvePhotoSuggestion(request: request)
            case RequestType.newsReport.rawValue where content:
                await approveNewsReport(request: request)
            default:
                Log.info("[PushApprove] يبقى معلّقاً للمراجعة من الشاشة: \(request.requestType)")
                return false
            }
            return true
        } catch {
            Log.error("[PushApprove] فشل جلب الطلب: \(error.localizedDescription)")
            return false
        }
    }

    /// تسجيل تعديل أدمن مباشر في admin_requests كسجل audit (status='approved' فوراً).
    /// لا يطلق إشعارات للمستخدمين — فقط للسجل.
    func logAdminDirectEdit(payload: TreeEditPayload) async {
        guard let user = currentUser else { return }
        do {
            var directPayload = payload
            if directPayload.isAdminDirectEdit != true {
                directPayload = TreeEditPayload(
                    v: payload.v,
                    action: payload.action,
                    targetMemberId: payload.targetMemberId,
                    targetMemberName: payload.targetMemberName,
                    newName: payload.newName,
                    newPhone: payload.newPhone,
                    newBirthDate: payload.newBirthDate,
                    deathDate: payload.deathDate,
                    newPhotoUrl: payload.newPhotoUrl,
                    parentMemberId: payload.parentMemberId,
                    parentMemberName: payload.parentMemberName,
                    newMemberName: payload.newMemberName,
                    reason: payload.reason,
                    notes: payload.notes,
                    isAdminDirectEdit: true
                )
            }

            let jsonData = try JSONEncoder().encode(directPayload)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""

            let targetId: String = directPayload.targetMemberId
                ?? directPayload.parentMemberId
                ?? user.id.uuidString

            let logEntry: [String: AnyEncodable] = [
                "id": AnyEncodable(UUID().uuidString),
                "member_id": AnyEncodable(targetId),
                "requester_id": AnyEncodable(user.id.uuidString),
                "request_type": AnyEncodable(RequestType.treeEdit.rawValue),
                "status": AnyEncodable(ApprovalStatus.approved.rawValue),
                "new_value": AnyEncodable(directPayload.action),
                "details": AnyEncodable(jsonString)
            ]

            do {
                try await supabase.from("admin_requests").insert(logEntry).execute()
            } catch {
                if ErrorHelper.isMissingColumn(error, column: "new_value") {
                    var fallback = logEntry
                    fallback.removeValue(forKey: "new_value")
                    try await supabase.from("admin_requests").insert(fallback).execute()
                } else {
                    throw error
                }
            }

            Log.info("[AdminAudit] Direct edit logged: \(directPayload.action)")
        } catch {
            Log.error("[AdminAudit] Failed to log direct edit: \(error.localizedDescription)")
        }
    }

    func rejectTreeEditRequest(request: AdminRequest, reason: String? = nil) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard authVM?.canRejectRequests == true else { Log.warning("رفض الطلب مرفوض: الصلاحية للإدارة فقط"); return }
        let actionAr = request.treeEditPayload?.resolvedAction?.arabicLabel ?? "التعديل"

        optimisticRemove(from: &treeEditRequests, id: request.id, apiWork: { [weak self] in
            guard let self else { return }
            // السيرفر يغلق الطلب «مرفوضاً» ويُشعر صاحبه والإدارة (decide_admin_request)
            guard await self.decideOnServer(request.id, approve: false, reason: reason) != nil else { return }
            Log.info("[TreeEdit] Rejected: \(actionAr)")
        }, refresh: { [weak self] in
            await self?.fetchTreeEditRequests(force: true)
        })
    }

    // MARK: - Deceased Status Requests

    func requestDeceasedStatus(memberId: UUID, deathDate: Date?) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        self.isLoading = true
        do {
            let dateString = deathDate.map { DateHelper.format($0) } ?? "غير محدد"

            let deceasedRequestId = UUID()
            let requestData: [String: AnyEncodable] = [
                "id": AnyEncodable(deceasedRequestId.uuidString),
                "member_id": AnyEncodable(memberId.uuidString),
                "requester_id": AnyEncodable(currentUser?.id.uuidString ?? ""),
                "request_type": AnyEncodable(RequestType.deceasedReport.rawValue),
                "status": AnyEncodable(ApprovalStatus.pending.rawValue),
                "details": AnyEncodable("طلب تأكيد وفاة بتاريخ: \(dateString)")
            ]

            try await supabase
                .from("admin_requests")
                .insert(requestData)
                .execute()

            let deceasedMemberName = memberById(memberId)?.firstName ?? "عضو"
            let requesterDeceasedName = currentUser?.firstName ?? "عضو"
            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("طلب تأكيد وفاة", "Deceased Status Request"),
                body: L10n.t(
                    "\(requesterDeceasedName) يطلب تأكيد وفاة \(deceasedMemberName)",
                    "\(requesterDeceasedName) requests deceased confirmation for \(deceasedMemberName)"
                ),
                kind: RequestType.deceasedReport.rawValue,
                requestId: deceasedRequestId,
                requestType: RequestType.deceasedReport.rawValue
            )

            Log.info("تم إرسال طلب تأكيد الوفاة للإدارة بنجاح")
        } catch {
            Log.error("خطأ في إرسال الطلب: \(error.localizedDescription)")
        }
        self.isLoading = false
    }

    func fetchDeceasedRequests(force: Bool = false) async {
        guard throttler.canFetch(key: "deceased", interval: 20, force: force) || deceasedRequests.isEmpty else { return }
        throttler.didFetch(key: "deceased")
        do {
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:members_masked!member_id(*)")
                .eq("request_type", value: RequestType.deceasedReport.rawValue)
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .execute()
                .value

            self.deceasedRequests = requests
        } catch {
            Log.fetchError("فشل جلب طلبات الوفاة", error)
        }
    }

    func approveDeceasedRequest(request: AdminRequest) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard canModerate else { Log.warning("قبول طلب الوفاة مرفوض: لا صلاحية"); return }
        // طلبك أنت يعالجه غيرك (إلا المالك) — السيرفر يرفضه أيضاً (own_request)
        guard !isOwnRequest(requesterId: request.requesterId, memberId: request.memberId) else { return }
        optimisticRemove(from: &deceasedRequests, id: request.id, apiWork: { [weak self] in
            guard let self else { return }
            // السيرفر يسجّل الوفاة ويغلق ويُشعر؛ وفاة جديدة → مربّع «إعلان وفاة» (decideOnServer)
            guard await self.decideOnServer(request.id, approve: true) != nil else { return }
            Log.info("تم قبول الطلب وتحديث الشجرة بنجاح")
        }, refresh: { [weak self] in
            await self?.fetchDeceasedRequests(force: true)
            await self?.memberVM?.fetchAllMembers(force: true)
        })
    }

    func rejectDeceasedRequest(request: AdminRequest, reason: String? = nil) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        // المراقب يقدر يرفض حسب CLAUDE.md (المشرف فقط ممنوع من الرفض)
        guard canRejectRequests else { Log.warning("رفض الطلب مرفوض: لا صلاحية"); return }
        optimisticRemove(from: &deceasedRequests, id: request.id, apiWork: { [weak self] in
            guard let self else { return }
            guard await self.decideOnServer(request.id, approve: false, reason: reason) != nil else { return }
            Log.info("تم رفض طلب تأكيد الوفاة")
        }, refresh: { [weak self] in
            await self?.fetchDeceasedRequests(force: true)
        })
    }

    // MARK: - Child Add Requests

    func fetchChildAddRequests(force: Bool = false) async {
        guard throttler.canFetch(key: "childAdd", interval: 20, force: force) || childAddRequests.isEmpty else { return }
        throttler.didFetch(key: "childAdd")
        do {
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:members_masked!member_id(*)")
                .eq("request_type", value: RequestType.childAdd.rawValue)
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .execute()
                .value

            self.childAddRequests = requests
        } catch {
            Log.fetchError("فشل جلب طلبات إضافة الأبناء", error)
        }
    }

    func rejectChildAddRequest(request: AdminRequest, reason: String? = nil) async {
        // المراقب يقدر يرفض حسب CLAUDE.md (المشرف فقط ممنوع من الرفض)
        guard canRejectRequests else { Log.warning("رفض الطلب مرفوض: لا صلاحية"); return }
        // طلبك أنت يعالجه غيرك (إلا المالك) — السيرفر يرفضه أيضاً (own_request)
        guard !isOwnRequest(requesterId: request.requesterId, memberId: request.memberId) else { return }
        optimisticRemove(from: &childAddRequests, id: request.id, apiWork: { [weak self] in
            guard let self else { return }
            // السيرفر يحذف ملف الابن (للمالك والمدير كما كان) ويغلق ويُشعر — حماية روابط العائلة كما هي
            guard await self.decideOnServer(request.id, approve: false, reason: reason) != nil else { return }
            Log.info("تم رفض طلب إضافة الابن")
        }, refresh: { [weak self] in
            await self?.fetchChildAddRequests(force: true)
            await self?.memberVM?.fetchAllMembers(force: true)
        })
    }

    func acknowledgeChildAddRequest(request: AdminRequest) async {
        // قبول طلبات الشجرة لمجالها: المالك/المدير/المراقب (السيرفر يفرضه أيضاً)
        guard authVM?.canApproveTreeRequests == true else { Log.warning("قبول طلب إضافة الابن مرفوض: لا صلاحية"); return }
        // طلبك أنت يعالجه غيرك (إلا المالك) — السيرفر يرفضه أيضاً (own_request)
        guard !isOwnRequest(requesterId: request.requesterId, memberId: request.memberId) else { return }
        optimisticRemove(from: &childAddRequests, id: request.id, apiWork: { [weak self] in
            guard let self else { return }
            // ابن أضافه عضو يُحفظ «معلّقاً» — السيرفر يفعّله ويغلق ويُشعر (المجمّد لا يُفك)
            guard await self.decideOnServer(request.id, approve: true) != nil else { return }
            Log.info("تم تأكيد طلب إضافة الابن بنجاح")
        }, refresh: { [weak self] in
            await self?.fetchChildAddRequests(force: true)
            await self?.memberVM?.fetchAllMembers(force: true)
        })
    }

    /// الموافقة على جميع طلبات إضافة الأبناء المعلقة دفعة واحدة — بلا إشعارات (كما كان)
    func bulkApproveChildAddRequests() async -> Int {
        guard authVM?.canApproveTreeRequests == true else { return 0 }
        self.isLoading = true
        let pending = childAddRequests
        var successCount = 0

        for request in pending {
            // كل طلب يُقرَّر على السيرفر وحده (معلّق؟ مجال الدور؟ ليس طلبك؟) — الفاشل يبقى معلّقاً
            if await decideOnServer(request.id, approve: true, silent: true) != nil { successCount += 1 }
        }

        await fetchChildAddRequests(force: true)
        await memberVM?.fetchAllMembers(force: true)

        Log.info("تم قبول \(successCount)/\(pending.count) طلب إضافة أبناء")
        self.isLoading = false
        return successCount
    }

    /// قبول جماعي لطلبات الانضمام — كل طلب بمسار التفعيل الواحد (`activateAccount`): لا تفعيل بلا أب،
    /// إغلاق طلب الانضمام، وإشعار العضو والإدارة. كان يكتب role/status مباشرة على الكل بلا حارس الأب
    /// ولا إغلاق ولا إشعار. يرجّع عدد ما تفعّل فعلاً؛ الناقص (بلا أب، رفضه السيرفر) يبقى معلّقاً
    func bulkApproveJoinRequests(memberIds: [UUID]) async -> Int {
        guard !memberIds.isEmpty else { return 0 }
        isLoading = true
        var approved = 0
        // دخول النساء (٢٠٢٦-١٠-٢٤): طلب الأنثى لا يُقبل جماعياً — يُربط بعقدتها في شجرة النساء واحدة واحدة
        var skippedWomen = 0
        for id in memberIds {
            if memberById(id)?.isFemale == true { skippedWomen += 1; continue }
            if await activateAccount(memberId: id, approvingJoin: true) { approved += 1 }
        }
        if skippedWomen > 0 {
            errorMessage = Self.womenOneByOneMessage
        }
        // آخر سبب (مثل «غير مربوط بالشجرة») يبقى في errorMessage — شاشة الطلبات تضمّه لملخّص «N من M»
        Log.info("تم قبول \(approved)/\(memberIds.count) طلب انضمام جماعياً")
        isLoading = false
        return approved
    }

    // MARK: - Admin Add Son

    func adminAddSon(firstName: String, parent: FamilyMember?) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        self.isLoading = true

        do {
            let newId = UUID()

            // Build full name from parent if available, otherwise use first name alone
            let fullCombinedName = parent.map { "\(firstName) \($0.fullName)" } ?? firstName

            // Father ID from parent, or nil for root
            let fatherIdValue = parent?.id.uuidString

            let sonData: [String: AnyEncodable] = [
                "id": AnyEncodable(newId.uuidString),
                "first_name": AnyEncodable(firstName),
                "full_name": AnyEncodable(fullCombinedName),
                "father_id": AnyEncodable(fatherIdValue),
                "role": AnyEncodable("member"),
                "is_deceased": AnyEncodable(true),
                "sort_order": AnyEncodable(0)
            ]

            try await supabase.from("profiles").insert(sonData).execute()

            // Refresh members immediately
            await memberVM?.fetchAllMembers(force: true)

            // إشعار للمدراء بإضافة الابن
            let parentFullName = parent?.fullName ?? ""
            let notifBody = L10n.t(
                "تم إضافة الابن: «\(firstName)» لـ: «\(parentFullName)»",
                "Son added: «\(firstName)» to: «\(parentFullName)»"
            )
            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("تعديل الشجرة", "Tree Update"),
                body: notifBody,
                kind: NotificationKind.treeEdit.rawValue
            )

        } catch {
            Log.error("خطأ في إضافة العضو: \(error.localizedDescription)")
        }

        self.isLoading = false
    }

    // MARK: - Update Member Phone

    func updateMemberPhone(memberId: UUID, newPhone: String) async {
        await updateMemberPhone(memberId: memberId, country: KuwaitPhone.defaultCountry, localPhone: newPhone)
    }

    /// تعديل/إضافة رقم جوال فعلي لعضو معلّق — إدخال حر يدعم الأرقام الدولية عبر الكشف التلقائي.
    /// - `activate`: عند true يفعّل الحساب أيضاً (status=active + role=member للمعلّق + اعتماد طلب الانضمام).
    /// يرجع true عند النجاح.
    @discardableResult
    func updatePendingMemberPhone(memberId: UUID, rawInput: String, activate: Bool = false) async -> Bool {
        guard let normalizedPhone = KuwaitPhone.normalizeForStorageFromInput(rawInput) else {
            self.errorMessage = L10n.t("رقم الجوال غير صالح.", "Invalid phone number.")
            return false
        }
        return await applyMemberPhone(memberId: memberId, normalizedPhone: normalizedPhone, activate: activate)
    }

    /// تعديل/إضافة رقم جوال فعلي لعضو معلّق — باختيار الدولة + الرقم المحلي.
    @discardableResult
    func updatePendingMemberPhone(memberId: UUID, country: KuwaitPhone.Country, localDigits: String, activate: Bool = false) async -> Bool {
        guard let normalizedPhone = KuwaitPhone.normalizedForStorage(country: country, rawLocalDigits: localDigits) else {
            self.errorMessage = L10n.t(
                "رقم غير صالح لـ \(country.nameArabic).",
                "Invalid number for \(country.nameArabic)."
            )
            return false
        }
        return await applyMemberPhone(memberId: memberId, normalizedPhone: normalizedPhone, activate: activate)
    }

    /// النواة المشتركة: تحقق صلاحية + منع تكرار + حفظ على السيرفر + تفعيل اختياري.
    @discardableResult
    private func applyMemberPhone(memberId: UUID, normalizedPhone: String, activate: Bool) async -> Bool {
        guard NetworkMonitor.shared.requireOnline() else { return false }
        guard canModerate else {
            self.errorMessage = L10n.t("ليس لديك صلاحية لتعديل الأرقام.", "You don't have permission to edit numbers.")
            return false
        }
        // منع تكرار الرقم
        if let memberVM = memberVM {
            let check = memberVM.isPhoneDuplicate(normalizedPhone, excludingMemberId: memberId)
            if check.isDuplicate {
                self.errorMessage = L10n.t(
                    "الرقم مستخدم من عضو آخر: \(check.existingMember?.fullName ?? "")",
                    "Number already used by: \(check.existingMember?.fullName ?? "")"
                )
                return false
            }
        }
        self.isLoading = true
        defer { self.isLoading = false }
        do {
            try await supabase
                .from("profiles")
                .update(["phone_number": AnyEncodable(normalizedPhone)])
                .eq("id", value: memberId.uuidString)
                .execute()

            if activate {
                // تفعيل العضو: status=active + role=member للمعلّق + اعتماد طلب الانضمام —
                // من «معلّق» فقط (فحص الثغرات ب-٣): المجمّد لا يُفك تجميده بتعديل رقمه
                let profiles: [FamilyMember] = (try? await supabase
                    .from("members_masked") // الهاتف المخفي يُفرَّغ من السيرفر
                    .select()
                    .eq("id", value: memberId.uuidString)
                    .limit(1)
                    .execute()
                    .value) ?? []

                if let profile = profiles.first, profile.status == .pending || profile.status == nil {
                    var payload: [String: AnyEncodable] = ["status": AnyEncodable("active")]
                    if profile.role == .pending {
                        payload["role"] = AnyEncodable("member")
                    }
                    try await supabase
                        .from("profiles")
                        .update(payload)
                        .eq("id", value: memberId.uuidString)
                        .or("status.is.null,status.eq.pending")
                        .execute()

                    _ = try? await supabase
                        .from("admin_requests")
                        .update(["status": AnyEncodable(ApprovalStatus.approved.rawValue)])
                        .eq("member_id", value: memberId.uuidString)
                        .eq("request_type", value: RequestType.joinRequest.rawValue)
                        .eq("status", value: ApprovalStatus.pending.rawValue)
                        .execute()
                }
            }

            await memberVM?.fetchAllMembers(force: true)
            Log.info(activate ? "تم تحديث الرقم وتفعيل العضو" : "تم تحديث رقم العضو المعلّق")
            return true
        } catch {
            Log.error("خطأ تحديث رقم العضو المعلّق: \(error.localizedDescription)")
            await MainActor.run {
                self.errorMessage = L10n.t(
                    "فشل تحديث الرقم: \(error.localizedDescription)",
                    "Failed to update number: \(error.localizedDescription)"
                )
            }
            return false
        }
    }

    func updateMemberPhone(memberId: UUID, country: KuwaitPhone.Country, localPhone: String) async {
        self.isLoading = true
        guard let normalizedPhone = KuwaitPhone.normalizedForStorage(country: country, rawLocalDigits: localPhone) else {
            Log.error("رقم الهاتف غير صالح للدولة المختارة.")
            self.isLoading = false
            return
        }
        // التحقق من تكرار الرقم
        if let memberVM = memberVM {
            let check = memberVM.isPhoneDuplicate(normalizedPhone, excludingMemberId: memberId)
            if check.isDuplicate {
                Log.warning("رقم الهاتف مستخدم من عضو آخر: \(check.existingMember?.fullName ?? "")")
                self.isLoading = false
                return
            }
        }
        do {
            // 1) Update phone
            try await supabase
                .from("profiles")
                .update(["phone_number": AnyEncodable(normalizedPhone)])
                .eq("id", value: memberId.uuidString)
                .execute()

            // 2) Activate member after adding the number — from «pending» only (ب-٣):
            //    a frozen member is never unfrozen as a side effect of a phone edit
            let profileResponse: [FamilyMember] = try await supabase
                .from("members_masked") // الهاتف المخفي يُفرَّغ من السيرفر
                .select()
                .eq("id", value: memberId.uuidString)
                .limit(1)
                .execute()
                .value

            if let profile = profileResponse.first, profile.status == .pending || profile.status == nil {
                var activationPayload: [String: AnyEncodable] = [
                    "status": AnyEncodable("active")
                ]

                if profile.role == .pending {
                    activationPayload["role"] = AnyEncodable("member")
                }

                try await supabase
                    .from("profiles")
                    .update(activationPayload)
                    .eq("id", value: memberId.uuidString)
                    .or("status.is.null,status.eq.pending")
                    .execute()

                // 3) Approve any pending join request for the same member
                _ = try? await supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.approved.rawValue)])
                    .eq("member_id", value: memberId.uuidString)
                    .eq("request_type", value: RequestType.joinRequest.rawValue)
                    .eq("status", value: ApprovalStatus.pending.rawValue)
                    .execute()
            }

            await memberVM?.fetchAllMembers(force: true)
            Log.info("تم تحديث الهاتف وتفعيل العضو للدخول المباشر")
        } catch {
            Log.error("خطأ تحديث الهاتف: \(error.localizedDescription)")
        }
        self.isLoading = false
    }

    // MARK: - Phone Change Requests

    /// يرجع نجاح إرسال الطلب — كان يُسجَّل الخطأ فقط فتقول الشاشة «أُرسل»
    @discardableResult
    func requestPhoneNumberChange(memberId: UUID, newPhoneNumber: String) async -> Bool {
        self.isLoading = true
        guard let normalizedPhone = KuwaitPhone.normalizeForStorageFromInput(newPhoneNumber) else {
            Log.error("رقم طلب التغيير غير صالح.")
            self.isLoading = false
            return false
        }
        do {
            let phoneRequestId = UUID()
            let requestData: [String: AnyEncodable] = [
                "id": AnyEncodable(phoneRequestId.uuidString),
                "member_id": AnyEncodable(memberId.uuidString),
                "requester_id": AnyEncodable(currentUser?.id.uuidString),
                "request_type": AnyEncodable(RequestType.phoneChange.rawValue),
                "new_value": AnyEncodable(normalizedPhone),
                "status": AnyEncodable(ApprovalStatus.pending.rawValue),
                "details": AnyEncodable("طلب تغيير رقم الجوال")
            ]

            try await supabase
                .from("admin_requests")
                .insert(requestData)
                .execute()

            let phoneRequesterName = currentUser?.firstName ?? "عضو"
            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("طلب تغيير رقم الهاتف", "Phone Change Request"),
                body: L10n.t(
                    "\(phoneRequesterName) يطلب تغيير رقم هاتفه",
                    "\(phoneRequesterName) requests a phone number change"
                ),
                kind: RequestType.phoneChange.rawValue,
                requestId: phoneRequestId,
                requestType: RequestType.phoneChange.rawValue
            )

            Log.info("تم إرسال طلب تغيير الرقم للإدارة: \(Log.masked(normalizedPhone))")
        } catch {
            Log.error("خطأ في إرسال طلب التغيير: \(error.localizedDescription)")
            self.isLoading = false
            return false
        }
        self.isLoading = false
        return true
    }

    // MARK: - Family Change Requests (العائلة بطلب فقط — طلب المالك)

    @discardableResult
    func requestFamilyChange(memberId: UUID, newFamily: String) async -> Bool {
        let requestId = UUID()
        do {
            let requestData: [String: AnyEncodable] = [
                "id": AnyEncodable(requestId.uuidString),
                "member_id": AnyEncodable(memberId.uuidString),
                "requester_id": AnyEncodable(currentUser?.id.uuidString),
                "request_type": AnyEncodable(RequestType.familyChange.rawValue),
                "new_value": AnyEncodable(newFamily),
                "status": AnyEncodable(ApprovalStatus.pending.rawValue),
                "details": AnyEncodable("طلب تغيير العائلة إلى: \(newFamily)")
            ]
            try await supabase.from("admin_requests").insert(requestData).execute()

            let requesterFullName = currentUser?.displayFullName ?? "عضو"
            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("طلب تغيير العائلة", "Family Change Request"),
                body: L10n.t("طلب تغيير عائلة: \(requesterFullName) إلى \(newFamily)",
                             "Family change request: \(requesterFullName) to \(newFamily)"),
                kind: RequestType.familyChange.rawValue,
                requestId: requestId,
                requestType: RequestType.familyChange.rawValue
            )
            return true
        } catch {
            Log.error("خطأ في إرسال طلب تغيير العائلة: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Name Change Requests

    /// يرجع نجاح إرسال الطلب — كان يُسجَّل الخطأ فقط فتقول الشاشة «أُرسل»
    @discardableResult
    func requestNameChange(memberId: UUID, newName: String) async -> Bool {
        self.isLoading = true
        do {
            let nameRequestId = UUID()
            let requestData: [String: AnyEncodable] = [
                "id": AnyEncodable(nameRequestId.uuidString),
                "member_id": AnyEncodable(memberId.uuidString),
                "requester_id": AnyEncodable(currentUser?.id.uuidString),
                "request_type": AnyEncodable(RequestType.nameChange.rawValue),
                "new_value": AnyEncodable(newName),
                "status": AnyEncodable(ApprovalStatus.pending.rawValue),
                "details": AnyEncodable("طلب تغيير الاسم إلى: \(newName)")
            ]

            try await supabase
                .from("admin_requests")
                .insert(requestData)
                .execute()

            let requesterFullName = currentUser?.fullName ?? "عضو"
            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("طلب تغيير الاسم", "Name Change Request"),
                body: L10n.t(
                    "طلب تغيير اسم: \(requesterFullName) إلى \(newName)",
                    "Name change request: \(requesterFullName) to \(newName)"
                ),
                kind: RequestType.nameChange.rawValue,
                requestId: nameRequestId,
                requestType: RequestType.nameChange.rawValue
            )

            Log.info("تم إرسال طلب تغيير الاسم للإدارة: \(newName)")
        } catch {
            Log.error("خطأ في إرسال طلب تغيير الاسم: \(error.localizedDescription)")
            self.isLoading = false
            return false
        }
        self.isLoading = false
        return true
    }

    // MARK: - Fetch / Approve / Reject Name Change Requests

    func fetchNameChangeRequests(force: Bool = false) async {
        guard throttler.canFetch(key: "nameChange", interval: 20, force: force) || nameChangeRequests.isEmpty else { return }
        throttler.didFetch(key: "nameChange")
        guard canModerate else {
            nameChangeRequests = []
            return
        }

        do {
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:members_masked!member_id(*)")
                // «أسماء» تشمل طلبات تغيير العائلة
                .in("request_type", values: [RequestType.nameChange.rawValue, RequestType.familyChange.rawValue])
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .order("created_at", ascending: false)
                .execute()
                .value

            self.nameChangeRequests = requests
        } catch {
            Log.fetchError("فشل جلب طلبات تغيير الاسم", error)
        }
    }

    func approveNameChangeRequest(request: AdminRequest) async {
        guard canModerate else { Log.warning("قبول طلب الاسم مرفوض: لا صلاحية"); return }
        guard !isOwnRequest(requesterId: request.requesterId, memberId: request.memberId) else { return }
        guard let newName = request.newValue, !newName.isEmpty else {
            Log.error("[NameChange] الاسم الجديد غير موجود في الطلب")
            return
        }

        if request.requestType == RequestType.familyChange.rawValue {
            await approveFamilyChange(request: request, newFamily: newName)
            return
        }

        optimisticRemove(from: &nameChangeRequests, id: request.id, apiWork: { [weak self] in
            guard let self else { return }
            // السيرفر يغيّر الاسم ويغلق ويُشعر في معاملة واحدة (decide_admin_request)
            guard await self.decideOnServer(request.id, approve: true) != nil else { return }
            Log.info("[NameChange] تم قبول طلب تغيير الاسم → \(newName)")
        }, refresh: { [weak self] in
            await self?.fetchNameChangeRequests(force: true)
            await self?.memberVM?.fetchAllMembers(force: true)
        })
    }

    /// اعتماد «تغيير العائلة»: يُطبَّق على العضو وأبنائه (set_family_name_cascade داخل decide_admin_request)
    private func approveFamilyChange(request: AdminRequest, newFamily: String) async {
        optimisticRemove(from: &nameChangeRequests, id: request.id, apiWork: { [weak self] in
            guard let self else { return }
            guard await self.decideOnServer(request.id, approve: true) != nil else { return }
            Log.info("[FamilyChange] تم قبول طلب تغيير العائلة → \(newFamily)")
        }, refresh: { [weak self] in
            await self?.fetchNameChangeRequests(force: true)
            await self?.memberVM?.fetchAllMembers(force: true)
        })
    }

    func rejectNameChangeRequest(request: AdminRequest, reason: String? = nil) async {
        // كان isAdmin (يستبعد المراقب). حسب CLAUDE.md المراقب يقدر يرفض.
        guard canRejectRequests else { Log.warning("رفض الطلب مرفوض: لا صلاحية"); return }
        optimisticRemove(from: &nameChangeRequests, id: request.id, apiWork: { [weak self] in
            guard let self else { return }
            guard await self.decideOnServer(request.id, approve: false, reason: reason) != nil else { return }
            Log.info("[NameChange] تم رفض الطلب")
        }, refresh: { [weak self] in
            await self?.fetchNameChangeRequests(force: true)
        })
    }

    func fetchPhoneChangeRequests(force: Bool = false) async {
        guard throttler.canFetch(key: "phoneChange", interval: 20, force: force) || phoneChangeRequests.isEmpty else { return }
        throttler.didFetch(key: "phoneChange")
        guard canModerate else {
            phoneChangeRequests = []
            return
        }

        do {
            let requests: [PhoneChangeRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:members_masked!member_id(*)")
                .eq("request_type", value: RequestType.phoneChange.rawValue)
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .order("created_at", ascending: false)
                .execute()
                .value

            self.phoneChangeRequests = requests
        } catch {
            Log.fetchError("خطأ جلب طلبات تغيير الرقم", error)
        }
    }

    func approvePhoneChangeRequest(request: PhoneChangeRequest) async {
        guard canModerate, let rawPhone = request.newValue, !rawPhone.isEmpty else { return }
        guard !isOwnRequest(requesterId: request.requesterId, memberId: request.memberId) else { return }
        guard let newPhone = KuwaitPhone.normalizeForStorageFromInput(rawPhone) else { return }
        // التحقق من تكرار الرقم قبل الموافقة (السيرفر يفحص أيضاً — phone_in_use — ويشمل الأرقام المخفية)
        if let memberVM = memberVM {
            let check = memberVM.isPhoneDuplicate(newPhone, excludingMemberId: request.memberId)
            if check.isDuplicate {
                Log.warning("رفض تغيير الرقم: مستخدم من \(check.existingMember?.fullName ?? "")")
                errorMessage = Self.decisionMessage(forKey: "phone_in_use")
                return
            }
        }

        optimisticRemove(from: &phoneChangeRequests, id: request.id, apiWork: { [weak self] in
            guard let self else { return }
            // السيرفر يحفظ الرقم موحّداً ويغلق ويُشعر في معاملة واحدة (decide_admin_request)
            guard await self.decideOnServer(request.id, approve: true) != nil else { return }
            Log.info("[PhoneChange] تم قبول طلب تغيير الرقم")
        }, refresh: { [weak self] in
            await self?.fetchPhoneChangeRequests(force: true)
            await self?.memberVM?.fetchAllMembers(force: true)
        })
    }

    func rejectPhoneChangeRequest(request: PhoneChangeRequest, reason: String? = nil) async {
        // كان isAdmin (يستبعد المراقب). حسب CLAUDE.md المراقب يقدر يرفض.
        guard canRejectRequests else { Log.warning("رفض الطلب مرفوض: لا صلاحية"); return }

        optimisticRemove(from: &phoneChangeRequests, id: request.id, apiWork: { [weak self] in
            guard let self else { return }
            guard await self.decideOnServer(request.id, approve: false, reason: reason) != nil else { return }
            Log.info("[PhoneChange] تم رفض طلب تغيير الرقم")
        }, refresh: { [weak self] in
            await self?.fetchPhoneChangeRequests(force: true)
        })
    }

    // MARK: - Account Activation & Member Approval

    /// «تسجيل في التطبيق» / قبول طلب انضمام — المسار الواحد للتفعيل: لا تفعيل بلا أب، يغلق طلب الانضمام
    /// المعلّق، ويُشعر العضو والإدارة. يرجّع true فقط إذا تفعّل الصف فعلاً على السيرفر.
    /// - approvingJoin: قبول طلب انضمام (القبول الجماعي) — من «معلّق» فقط، يصير «عضواً» ويظهر في الشجرة،
    ///   وإشعاره «تم اعتماد انضمامك» بدل «تم تفعيل حسابك»
    @discardableResult
    func activateAccount(memberId: UUID, approvingJoin: Bool = false) async -> Bool {
        guard canModerate else { return false }
        // طلب انضمام أنثى: مكانها شجرة النساء — «ربط بشجرة النساء» (`linkWomanAccount`) لا التفعيل
        if let m = memberById(memberId), m.isFemale, approvingJoin || m.role == .pending {
            errorMessage = Self.womenOneByOneMessage
            return false
        }
        // لا تفعيل لحساب خارج الشجرة (بلا أب): يصير معلّقاً بالهواء — لا يظهر في الشجرة ولا يعمل له «موقعي»
        // (حدث مع «عبدالله اياد» ٢٠٢٦-١٠-٠٥). الربط بسجله أو إضافته تحت أبيه أولاً.
        var fatherId = memberVM?.allMembers.first(where: { $0.id == memberId })?.fatherId
        if fatherId == nil {
            struct FatherRow: Decodable { let father_id: UUID? }
            if let row: FatherRow = try? await supabase.from("profiles").select("father_id")
                .eq("id", value: memberId.uuidString).single().execute().value {
                fatherId = row.father_id
            }
        }
        guard fatherId != nil else {
            errorMessage = L10n.t("هذا الحساب غير مربوط بالشجرة. اربطه بسجله الصحيح من «ربط بالشجرة»، أو أضِفه تحت أبيه أولاً.",
                                  "This account isn't linked to the tree. Link it to its record with «Link to tree», or add it under its father first.")
            return false
        }
        nonisolated struct UpdatedRow: Decodable { let id: UUID }
        // «معلّق» يصير «عضواً» (كما في تفعيل الرقم) — لا يُمسّ دور أحد الإدارة
        let localRole = memberById(memberId)?.role
        let promotesRole = localRole == .pending || (approvingJoin && localRole == nil)
        do {
            var payload: [String: AnyEncodable] = ["status": AnyEncodable("active")]
            if promotesRole { payload["role"] = AnyEncodable("member") }
            if approvingJoin { payload["is_hidden_from_tree"] = AnyEncodable(false) }
            // نطلب الصف المحدَّث: صفر صفوف = رفضه حارس السيرفر بلا خطأ — لا يُحسب تفعيلاً
            let updated: [UpdatedRow]
            if approvingJoin {
                // المجمّد لا يُفك تجميده بقبول جماعي
                updated = try await supabase
                    .from("profiles")
                    .update(payload)
                    .eq("id", value: memberId.uuidString)
                    .or("status.is.null,status.neq.frozen")
                    .select("id")
                    .execute()
                    .value
            } else {
                updated = try await supabase
                    .from("profiles")
                    .update(payload)
                    .eq("id", value: memberId.uuidString)
                    .select("id")
                    .execute()
                    .value
            }
            guard !updated.isEmpty else {
                Log.warning("لم يتفعّل الحساب (0 صفوف): \(memberId)")
                errorMessage = L10n.t("تعذّر تفعيل الحساب — ربما عولج من قبل أو ليس لديك صلاحية.",
                                      "Couldn't activate the account — it may have been handled already, or you lack permission.")
                return false
            }

            // طلب الانضمام/الربط المعلّق يُغلق مع التفعيل
            _ = try? await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable(ApprovalStatus.approved.rawValue)])
                .eq("member_id", value: memberId.uuidString)
                .in("request_type", values: [RequestType.joinRequest.rawValue, RequestType.linkRequest.rawValue])
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .execute()

            // Update local data through memberVM
            if let index = memberVM?.allMembers.firstIndex(where: { $0.id == memberId }) {
                memberVM?.allMembers[index].status = .active
                if promotesRole { memberVM?.allMembers[index].role = .member }
                if approvingJoin { memberVM?.allMembers[index].isHiddenFromTree = false }
                memberVM?.objectWillChange.send()
            }

            if approvingJoin {
                // نفس إشعار قبول الانضمام (العضو + الإدارة)
                await notifyJoinApproval(memberId: memberId, fatherName: fatherId.flatMap { memberById($0)?.fullName })
                return true
            }

            let memberName = getSafeMemberName(for: memberId)

            // إشعار المستخدم بالتفعيل
            let userTitle = L10n.t("مرحباً بك في العائلة", "Welcome to the Family")
            let userBody = L10n.t("تم تفعيل حسابك بنجاح — يمكنك الآن استخدام التطبيق", "Your account is now active — you can start using the app")
            if let creator = currentUser?.id {
                let payload: [String: AnyEncodable] = [
                    "target_member_id": AnyEncodable(memberId.uuidString),
                    "title": AnyEncodable(userTitle),
                    "body": AnyEncodable(userBody),
                    "kind": AnyEncodable("account_activated"),
                    "created_by": AnyEncodable(creator.uuidString)
                ]
                _ = try? await supabase.from("notifications").insert(payload).execute()
            }
            await notificationVM?.sendPushToMembers(
                title: userTitle,
                body: userBody,
                kind: "account_activated",
                targetMemberIds: [memberId]
            )

            // إشعار المدراء
            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("تفعيل حساب", "Account Activated"),
                body: L10n.t(
                    "تم تفعيل حساب \(memberName)",
                    "\(memberName)'s account was activated"
                ),
                kind: "account_activated",
                subjectMemberId: memberId
            )
            return true
        } catch {
            Log.error("فشل تفعيل الحساب: \(error.localizedDescription)")
            if handleGuardianRefusal(error, minorId: memberId, treeMemberId: memberId) { return false }
            errorMessage = L10n.t("تعذّر تفعيل الحساب. حاول مرة أخرى.", "Couldn't activate the account. Try again.")
            return false
        }
    }

    /// Approve a new member and activate their account with father linkage
    func approveMember(memberId: UUID, fatherId: UUID?) async {
        guard canModerate else { Log.warning("قبول العضو مرفوض: لا صلاحية"); return }
        // الأنثى لا تُكتب تحت أب في شجرة الرجال — «ربط بشجرة النساء»
        if memberById(memberId)?.isFemale == true {
            errorMessage = Self.womenOneByOneMessage
            return
        }
        self.isLoading = true
        let fatherName = fatherId.flatMap { id in
            memberById(id)?.fullName
        }
        do {
            let payload: [String: AnyEncodable] = [
                "role": AnyEncodable("member"),
                "status": AnyEncodable("active"),
                "father_id": AnyEncodable(fatherId?.uuidString),
                "is_hidden_from_tree": AnyEncodable(false)
            ]

            try await supabase
                .from("profiles")
                .update(payload)
                .eq("id", value: memberId.uuidString)
                .execute()

            // Approve any pending join/link requests for this member
            _ = try? await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable(ApprovalStatus.approved.rawValue)])
                .eq("member_id", value: memberId.uuidString)
                .in("request_type", values: [RequestType.joinRequest.rawValue, RequestType.linkRequest.rawValue])
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .execute()

            // Update local data
            if let index = memberVM?.allMembers.firstIndex(where: { $0.id == memberId }) {
                memberVM?.allMembers[index].role = .member
                memberVM?.allMembers[index].status = .active
                memberVM?.allMembers[index].fatherId = fatherId
                memberVM?.allMembers[index].isHiddenFromTree = false
                memberVM?.objectWillChange.send()
            }

            await notifyJoinApproval(memberId: memberId, fatherName: fatherName)

            Log.info("تم قبول العضو بنجاح")
        } catch {
            Log.error("فشل القبول: \(error.localizedDescription)")
            if !handleGuardianRefusal(error, minorId: memberId, treeMemberId: memberId) {
                errorMessage = L10n.t("تعذّر قبول العضو. حاول مرة أخرى.", "Couldn't approve the member. Try again.")
            }
        }
        self.isLoading = false
    }

    /// Merge a newly registered member into an existing tree member.
    /// Copies the tree position data (father, children, bio, photos) from the old tree record
    /// to the new registration record (which has the correct auth UUID), then deletes the old record.
    func mergeMemberIntoTreeMember(newMemberId: UUID, existingTreeMemberId: UUID) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard canModerate else {
            Log.error("[MERGE] مرفوض: الصلاحية للمدير فقط")
            self.mergeResult = .failure(L10n.t("ليس لديك صلاحية لإجراء الدمج.", "You don't have permission to merge."))
            return
        }
        guard newMemberId != existingTreeMemberId else {
            self.mergeResult = .failure(L10n.t("لا يمكن دمج العضو مع نفسه.", "Cannot merge a member with itself."))
            return
        }
        // «ربط بالشجرة» لملفات الرجال فقط — حساب الأنثى يُربط بعقدتها في شجرة النساء
        if memberById(newMemberId)?.isFemale == true {
            self.mergeResult = .failure(Self.womenOneByOneMessage)
            return
        }

        Log.info("[MERGE] بدء الدمج: \(newMemberId) ← \(existingTreeMemberId)")
        self.isLoading = true

        do {
            // استدعاء الـ atomic function على السيرفر — كل العمليات في transaction واحدة
            struct MergeParams: Encodable {
                let p_new_member_id: String
                let p_tree_member_id: String
            }
            nonisolated struct MergeResponse: Decodable {
                let success: Bool
                let message: String
                let mergedName: String?
                /// `guardian_consent_required` / `under_13` للقاصر (الشروط ٢٠٢٦-١٠-٢٨)
                let hint: String?
                enum CodingKeys: String, CodingKey {
                    case success, message, hint
                    case mergedName = "merged_name"
                }
            }

            let response: MergeResponse = try await supabase
                .rpc("merge_member_into_tree", params: MergeParams(
                    p_new_member_id: newMemberId.uuidString,
                    p_tree_member_id: existingTreeMemberId.uuidString
                ))
                .execute()
                .value

            if response.success {
                let name = response.mergedName ?? ""
                Log.info("[MERGE] ✅ نجح الدمج: \(name)")

                // إشعار العضو بالقبول
                await notifyJoinApproval(memberId: newMemberId, fatherName: nil)

                // تحديث البيانات المحلية
                await memberVM?.fetchAllMembers(force: true)

                self.mergeResult = .success(L10n.t(
                    "تم ربط \(name) بنجاح وتفعيل حسابه.",
                    "Successfully linked \(name) and activated their account."
                ))
            } else if response.hint == GuardianConsent.requiredHint {
                // قاصر ١٣–١٧: لا ربط قبل موافقة ولي الأمر — مربّع «اطلب موافقة ولي الأمر»
                Log.info("[MERGE] يحتاج موافقة ولي الأمر")
                self.mergeResult = nil
                GuardianConsentPresenter.offer(minorId: newMemberId, treeMemberId: existingTreeMemberId,
                                               message: response.message)
            } else {
                Log.error("[MERGE] ❌ فشل: \(response.message)")
                self.mergeResult = .failure(response.message)
            }
        } catch {
            Log.error("[MERGE] ❌ خطأ: \(error.localizedDescription)")
            self.mergeResult = .failure(L10n.t(
                "حدث خطأ أثناء الدمج: \(error.localizedDescription)",
                "Merge error: \(error.localizedDescription)"
            ))
        }

        self.isLoading = false
    }

    // MARK: - دخول النساء (طلب المالك ٢٠٢٦-١٠-٢٤): ربط طلب انضمام أنثى بعقدتها في شجرة النساء

    /// طلب الأنثى لا يمرّ بالتفعيل أو «ربط بالشجرة» أو القبول الجماعي
    static var womenOneByOneMessage: String {
        L10n.t("النساء يُربطن واحدة واحدة من «ربط بشجرة النساء».",
               "Women are linked one at a time with «Link to women's tree».")
    }

    /// طلب الانضمام/الربط المعلّق + الأب الذي اختارته في التسجيل (`|father_id:…|father_name:…` في `details`)
    struct WomanJoinRequestInfo {
        let requestId: UUID
        let fatherId: UUID?
        let fatherName: String?
    }

    /// يقرأ أحدث طلب انضمام/ربط معلّق للعضو — nil = لا طلب أو تعذّرت القراءة
    func fetchWomanJoinRequest(for memberId: UUID) async -> WomanJoinRequestInfo? {
        nonisolated struct Row: Decodable { let id: UUID; let details: String? }
        do {
            let rows: [Row] = try await supabase
                .from("admin_requests")
                .select("id, details")
                .eq("member_id", value: memberId.uuidString)
                .in("request_type", values: [RequestType.linkRequest.rawValue, RequestType.joinRequest.rawValue])
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return nil }
            let fields = Self.joinDetailFields(row.details)
            let name = fields["father_name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return WomanJoinRequestInfo(requestId: row.id,
                                        fatherId: fields["father_id"].flatMap { UUID(uuidString: $0) },
                                        fatherName: (name?.isEmpty == false) ? name : nil)
        } catch {
            Log.warning("[WomenLink] تعذّرت قراءة طلب الانضمام: \(error.localizedDescription)")
            return nil
        }
    }

    /// حقول `details` بصيغة «نص|مفتاح:قيمة|مفتاح:قيمة» (التسجيل)
    static func joinDetailFields(_ details: String?) -> [String: String] {
        var out: [String: String] = [:]
        for part in (details ?? "").split(separator: "|") {
            guard let colon = part.firstIndex(of: ":") else { continue }
            let key = part[..<colon].trimmingCharacters(in: .whitespaces)
            let value = part[part.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { out[key] = value }
        }
        return out
    }

    /// `link_woman_account`: بعقدة موجودة (`womanId`) أو بنت جديدة باسم `name` تحت `fatherId`.
    /// السيرفر يفعّل الحساب ويغلق الطلب ويُدرج «مرحباً بك في العائلة». يرجّع nil عند النجاح أو رسالة الخطأ.
    func linkWomanAccount(requestId: UUID, memberId: UUID, womanId: UUID?, fatherId: UUID?, name: String?) async -> String? {
        guard NetworkMonitor.shared.requireOnline() else {
            return L10n.t("لا يوجد اتصال بالإنترنت.", "No internet connection.")
        }
        guard authVM?.canApproveTreeRequests == true else {
            return Self.womanLinkMessage("not_allowed")
        }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        // المفاتيح الأربعة دائماً — الفارغ null
        let params: [String: AnyEncodable] = [
            "p_request_id": AnyEncodable(requestId.uuidString),
            "p_woman_id": AnyEncodable(womanId?.uuidString),
            "p_father_id": AnyEncodable(womanId == nil ? fatherId?.uuidString : Optional<String>.none),
            "p_name": AnyEncodable(womanId == nil ? trimmedName : Optional<String>.none)
        ]
        isLoading = true
        defer { isLoading = false }
        do {
            try await supabase.rpc("link_woman_account", params: params).execute()
            Log.info("[WomenLink] ✅ رُبط حساب \(memberId.uuidString.prefix(8)) بشجرة النساء")
            // الطلب يختفي فوراً من «الوارد» (طلبات الانضمام = الدور «معلّق»)
            if let index = memberVM?.allMembers.firstIndex(where: { $0.id == memberId }) {
                memberVM?.allMembers[index].role = .member
                memberVM?.allMembers[index].status = .active
                memberVM?.allMembers[index].isHiddenFromTree = true
                memberVM?.objectWillChange.send()
            }
            await memberVM?.fetchAllMembers(force: true)
            _ = try? await WomenStore.fetch()
            NotificationCenter.default.post(name: .womenMembersChanged, object: nil)
            return nil
        } catch {
            let hint = (error as? PostgrestError)?.hint ?? ""
            Log.error("[WomenLink] ❌ فشل الربط (\(hint)): \(error.localizedDescription)")
            return Self.womanLinkMessage(hint)
        }
    }

    /// رسائل `link_woman_account` بالـ hint
    static func womanLinkMessage(_ hint: String) -> String {
        switch hint {
        case "not_allowed":
            return L10n.t("ربط النساء للمالك والمدير والمراقب.", "Linking women is for the owner, admins and monitors.")
        case "request_not_found", "already_handled":
            return alreadyHandledMessage
        case "not_female":
            return L10n.t("صاحب الطلب ليس مسجّلاً كأنثى.", "The applicant isn't registered as female.")
        case "has_father":
            return L10n.t("الحساب مربوط بشجرة الرجال (له أب أو أبناء) — صحّحه أولاً.",
                          "The account is tied to the men's tree (has a father or children) — fix it first.")
        case "node_taken":
            return L10n.t("هذا الاسم مربوط بحساب آخر.", "This name is linked to another account.")
        case "not_female_node":
            return L10n.t("هذا الاسم ليس أنثى في شجرة النساء.", "This name isn't a female in the women's tree.")
        case "no_father":
            return L10n.t("الأب غير موجود في الشجرة — اختر الأب.", "The father isn't in the tree — choose the father.")
        case "name_required":
            return L10n.t("اكتب اسمها.", "Type her name.")
        default:
            return L10n.t("تعذّر الربط. حاول مرة أخرى.", "Couldn't link. Try again.")
        }
    }

    private func notifyJoinApproval(memberId: UUID, fatherName: String?) async {
        guard let creator = currentUser?.id else { return }

        let body: String
        if let fatherName, !fatherName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body = L10n.t(
                "تم اعتماد انضمامك وربطك بالشجرة مع: \(fatherName)",
                "Your membership was approved and linked to: \(fatherName)"
            )
        } else {
            body = L10n.t(
                "تم اعتماد انضمامك للعائلة بنجاح",
                "Your family membership was approved successfully"
            )
        }

        let title = L10n.t("مرحباً بك في العائلة", "Welcome to the Family")

        let payload: [String: AnyEncodable] = [
            "target_member_id": AnyEncodable(memberId.uuidString),
            "title": AnyEncodable(title),
            "body": AnyEncodable(body),
            "kind": AnyEncodable("join_approved"),
            "created_by": AnyEncodable(creator.uuidString)
        ]

        do {
            try await supabase.from("notifications").insert(payload).execute()
            // Send real push to the member
            await notificationVM?.sendPushToMembers(title: title, body: body, kind: "join_approved", targetMemberIds: [memberId])
            // Notify admins and supervisors about the new member (خارجي + داخلي)
            let memberName = getSafeMemberName(for: memberId)
            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("انضمام عضو جديد", "New Member Joined"),
                body: L10n.t(
                    "\(memberName) انضم لشجرة العائلة",
                    "\(memberName) joined the family tree"
                ),
                kind: "join_approved",
                subjectMemberId: memberId
            )
        } catch {
            Log.error("خطأ إرسال إشعار اعتماد الانضمام: \(error.localizedDescription)")
        }
    }

    /// Real-time match via server RPC `search_members_by_name` (v2: exact word + 75% threshold + top-4 parts).
    /// أذكى من `fetchMatchedMemberIds` لأن الأخير يقرأ snapshot وقت التسجيل،
    /// بينما هذا يستدعي السيرفر مباشرة بأحدث logic. يُستخدم في شاشات الإدارة لإحضار
    /// مطابقات حقيقية ودقيقة عند فتح طلب الانضمام/الربط.
    /// - Parameters:
    ///   - fullName: الاسم الكامل لمتقدم الطلب
    ///   - excludeId: معرّف العضو نفسه (اختياري) — يُستبعد من النتائج
    /// - Returns: قائمة UUIDs للأعضاء المتطابقين، مرتّبة حسب match_score من السيرفر
    func searchMembersByNameRPC(_ fullName: String, excluding excludeId: UUID? = nil) async -> [UUID] {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        struct MatchRow: Decodable {
            let memberId: UUID
            let fullName: String
            let matchScore: Int64
            enum CodingKeys: String, CodingKey {
                case memberId = "member_id"
                case fullName = "full_name"
                case matchScore = "match_score"
            }
        }

        do {
            let results: [MatchRow] = try await supabase
                .rpc("search_members_by_name", params: ["p_query": AnyEncodable(trimmed)])
                .execute()
                .value
            let ids = results.compactMap { row -> UUID? in
                row.memberId == excludeId ? nil : row.memberId
            }
            Log.info("[AdminMatch] RPC رجّع \(ids.count) مطابقة لـ '\(trimmed)'")
            return ids
        } catch {
            Log.warning("[AdminMatch] فشل استدعاء search_members_by_name: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetch matched member IDs from a link request
    func fetchMatchedMemberIds(for memberId: UUID) async -> [UUID] {
        do {
            struct LinkAdminRequest: Decodable {
                let details: String?
            }
            let results: [LinkAdminRequest] = try await supabase
                .from("admin_requests")
                .select("details")
                .eq("member_id", value: memberId.uuidString)
                .eq("request_type", value: RequestType.linkRequest.rawValue)
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .limit(1)
                .execute()
                .value

            guard let details = results.first?.details,
                  let range = details.range(of: "matched_ids:") else {
                return []
            }

            let idsString = String(details[range.upperBound...])
            return idsString
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) }
        } catch {
            Log.warning("فشل جلب بيانات المطابقة: \(error.localizedDescription)")
            return []
        }
    }

    /// رفض طلب انضمام أو حذف عضو نهائياً — ينتظر الحذف ويرجّع true إذا حُذف فعلاً.
    /// إشعار «لم تتم الموافقة على طلب انضمامك» لطلب انضمام معلّق فقط (لا لعضو حقيقي يُحذف)
    @discardableResult
    func rejectOrDeleteMember(memberId: UUID) async -> Bool {
        guard NetworkMonitor.shared.requireOnline() else { return false }
        guard authVM?.canDeleteMembers == true else {
            Log.error("تم رفض حذف السجل: الصلاحية للمالك فقط")
            self.errorMessage = L10n.t("ليس لديك صلاحية لرفض الطلبات.", "You don't have permission to reject requests.")
            return false
        }
        // لا يُحذف المالك ولا سجلك أنت (السيرفر يرفضهما أيضاً — فحص الثغرات)
        if memberId == currentUser?.id || memberById(memberId)?.role == .owner {
            self.errorMessage = L10n.t("لا يمكن حذف هذا السجل.", "This record can't be deleted.")
            return false
        }

        let target = memberById(memberId)
        let deletedName = target?.fourPartName ?? "عضو"
        // طلب انضمام معلّق (دوره «معلّق» — نفس قائمة طلبات الانضمام) — وحده يُبلَّغ بالرفض.
        // لا يُعتمد status: أعضاء الشجرة بلا دخول حالتهم التاريخية «معلّق»
        let isPendingJoin = target?.role == .pending

        // إشعار الرفض يُدرج قبل الحذف: صف الإشعار وأجهزة المتقدّم تُحذف مع ملفه (CASCADE)، فلا يصله شيء
        // بعده. الإدراج يُطلق الدفع فوراً — لطلب انضمام معلّق فقط، ويُسحب الصف إن فشل الحذف
        var rejectNotifId: UUID? = nil
        if isPendingJoin, let creator = currentUser?.id {
            let notifId = UUID()
            let rejectNotif: [String: AnyEncodable] = [
                "id": AnyEncodable(notifId.uuidString),
                "target_member_id": AnyEncodable(memberId.uuidString),
                "title": AnyEncodable(L10n.t("طلب الانضمام", "Join Request")),
                "body": AnyEncodable(L10n.t(
                    "لم تتم الموافقة على طلب انضمامك — تواصل مع إدارة العائلة",
                    "Your join request was not approved — please contact the family administration"
                )),
                "kind": AnyEncodable("request_rejected"),
                "created_by": AnyEncodable(creator.uuidString)
            ]
            if (try? await supabase.from("notifications").insert(rejectNotif).execute()) != nil {
                rejectNotifId = notifId
            }
        }

        // حذف فوري محلياً — يُستعاد من السيرفر إن فشل
        withAnimation(.snappy(duration: 0.25)) {
            memberVM?.allMembers.removeAll(where: { $0.id == memberId })
            memberVM?.currentMemberChildren.removeAll(where: { $0.id == memberId })
            memberVM?.membersVersion += 1
            memberVM?.objectWillChange.send()
        }

        nonisolated struct DeletedRow: Decodable { let id: UUID }
        do {
            // الحذف أولاً — السيرفر يحذف طلبات العضو وإشعاراته تلقائياً (ON DELETE)، ويرفض حذف من له
            // أبناء/زوجة مرتبطون (حماية روابط العائلة). نطلب الصف المحذوف: صفر صفوف = لم يُحذف
            let deleted: [DeletedRow] = try await supabase
                .from("profiles")
                .delete()
                .eq("id", value: memberId.uuidString)
                .select("id")
                .execute()
                .value
            guard !deleted.isEmpty else {
                Log.warning("لم يُحذف العضو (0 صفوف): \(memberId)")
                await undoRejectNotification(rejectNotifId)
                await memberVM?.fetchAllMembers(force: true)
                errorMessage = L10n.t("تعذّر حذف العضو — ربما حُذف من قبل أو ليس لديك صلاحية.",
                                      "Couldn't delete the member — it may already be gone, or you lack permission.")
                return false
            }

            _ = try? await supabase
                .from("admin_requests")
                .delete()
                .eq("requester_id", value: memberId.uuidString)
                .execute()

            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("حذف عضو", "Member Removed"),
                body: L10n.t(
                    "تم حذف عضو من شجرة العائلة\n\(deletedName)",
                    "Removed from the family tree\n\(deletedName)"
                ),
                kind: "member_delete"
            )
            Log.info("تم حذف العضو مع تنظيف المراجع المرتبطة بنجاح")
            return true
        } catch {
            Log.error("خطأ في الحذف: \(error.localizedDescription)")
            await undoRejectNotification(rejectNotifId)
            await memberVM?.fetchAllMembers(force: true)
            if let pgError = error as? PostgrestError, pgError.hint == "family_links_protected" {
                errorMessage = pgError.message
            } else {
                errorMessage = L10n.t(
                    "فشل حذف العضو: \(error.localizedDescription)",
                    "Failed to delete member: \(error.localizedDescription)"
                )
            }
            return false
        }
    }

    /// فشل حذف المتقدّم: صف إشعار الرفض الذي أُدرج قبله يُسحب (الدفع نفسه خرج لحظة الإدراج)
    private func undoRejectNotification(_ id: UUID?) async {
        guard let id else { return }
        _ = try? await supabase.from("notifications").delete().eq("id", value: id.uuidString).execute()
    }

    /// حذف نهائي لصف طلب من جدول admin_requests — يمسح الطلب كلياً من قاعدة البيانات
    /// (مختلف عن «رفض» الذي يغيّر الحالة فقط). للمالك/المدير فقط.
    func deleteAdminRequestRow(requestId: UUID) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard authVM?.canDeleteMembers == true else {
            Log.error("تم رفض حذف الطلب: الصلاحية للمالك/المدير فقط")
            self.errorMessage = L10n.t("ليس لديك صلاحية لحذف الطلبات نهائياً.", "You don't have permission to permanently delete requests.")
            return
        }

        // إزالة فورية محلياً من كل القوائم — ثم API بالخلفية
        withAnimation(.snappy(duration: 0.25)) {
            deceasedRequests.removeAll { $0.id == requestId }
            childAddRequests.removeAll { $0.id == requestId }
            newsReportRequests.removeAll { $0.id == requestId }
            treeEditRequests.removeAll { $0.id == requestId }
            nameChangeRequests.removeAll { $0.id == requestId }
            photoSuggestionRequests.removeAll { $0.id == requestId }
            phoneChangeRequests.removeAll { $0.id == requestId }
        }

        do {
            try await supabase
                .from("admin_requests")
                .delete()
                .eq("id", value: requestId.uuidString)
                .execute()
            Log.info("تم حذف الطلب نهائياً من admin_requests")
        } catch {
            Log.error("خطأ في حذف الطلب: \(error.localizedDescription)")
            await MainActor.run {
                self.errorMessage = L10n.t(
                    "فشل حذف الطلب: \(error.localizedDescription)",
                    "Failed to delete request: \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - News Report Requests

    func fetchNewsReportRequests(force: Bool = false) async {
        guard throttler.canFetch(key: "newsReport", interval: 20, force: force) || newsReportRequests.isEmpty else { return }
        throttler.didFetch(key: "newsReport")
        guard canModerate else {
            newsReportRequests = []
            return
        }

        do {
            // تبويب «البلاغات» يجمع بلاغات الأخبار + بلاغات المحتوى العام (Apple UGC):
            // التعليقات/الأرشيف/المشاريع/الديوانيات/تفاصيل العضو تُدرَج بـ content_report.
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:members_masked!member_id(*)")
                .in("request_type", values: [
                    RequestType.newsReport.rawValue,
                    RequestType.contentReport.rawValue
                ])
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .order("created_at", ascending: false)
                .execute()
                .value

            self.newsReportRequests = requests
        } catch {
            Log.fetchError("خطأ جلب البلاغات", error)
        }
    }

    func approveNewsReport(request: AdminRequest) async {
        // قبول البلاغ يحذف الخبر — مجال المحتوى فقط (لا المراقب)
        guard authVM?.canModerateContent == true else { Log.warning("قبول البلاغ مرفوض: لا صلاحية"); return }

        optimisticRemove(from: &newsReportRequests, id: request.id, apiWork: { [weak self] in
            guard let self else { return }
            // السيرفر يحذف الخبر (بلاغ خبر فقط) ويغلق ويُشعر المبلّغ (decide_admin_request)
            guard await self.decideOnServer(request.id, approve: true) != nil else { return }
        }, refresh: { [weak self] in
            await self?.fetchNewsReportRequests(force: true)
            await self?.newsVM?.fetchNews(force: true)
        })
    }

    func rejectNewsReport(request: AdminRequest) async {
        // البلاغات مجال المحتوى: المالك/المدير/المشرف (كانت canRejectRequests = مجال الشجرة، معكوسة)
        guard authVM?.canModerateContent == true else { Log.warning("رفض البلاغ مرفوض: لا صلاحية"); return }

        optimisticRemove(from: &newsReportRequests, id: request.id, apiWork: { [weak self] in
            guard let self else { return }
            await self.decideOnServer(request.id, approve: false)
        }, refresh: { [weak self] in
            await self?.fetchNewsReportRequests(force: true)
        })
    }

    // MARK: - Photo Suggestion Requests

    @Published var photoSuggestionRequests: [AdminRequest] = []

    /// إرسال اقتراح صورة لعضو — يرفع الصورة كملف مؤقت ويسجل طلب إداري
    func submitPhotoSuggestion(image: UIImage, for memberId: UUID) async -> Bool {
        guard let user = currentUser else { return false }
        self.isLoading = true
        defer { self.isLoading = false }

        guard let imageData = ImageProcessor.process(image, for: .avatar) else { return false }

        let fileName = "photo_suggestion_\(memberId.uuidString)_\(Int(Date().timeIntervalSince1970)).jpg"

        do {
            // 1. رفع الصورة المقترحة إلى التخزين
            try await supabase.storage
                .from("avatars")
                .upload(
                    fileName,
                    data: imageData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )

            let publicUrl = try supabase.storage
                .from("avatars")
                .getPublicURL(path: fileName)

            let urlString = publicUrl.absoluteString

            // 2. إنشاء طلب إداري
            let memberName = memberById(memberId)?.displayFullName ?? "عضو"
            let photoRequestId = UUID()

            let basePayload: [String: AnyEncodable] = [
                "id": AnyEncodable(photoRequestId.uuidString),
                "member_id": AnyEncodable(memberId.uuidString),
                "requester_id": AnyEncodable(user.id.uuidString),
                "request_type": AnyEncodable(RequestType.photoSuggestion.rawValue),
                "status": AnyEncodable(ApprovalStatus.pending.rawValue),
                "details": AnyEncodable("اقتراح صورة لـ \(memberName)")
            ]

            // محاولة إرسال مع new_value
            do {
                var payload = basePayload
                payload["new_value"] = AnyEncodable(urlString)
                try await supabase.from("admin_requests").insert(payload).execute()
            } catch {
                if ErrorHelper.isMissingColumn(error, column: "new_value") {
                    try await supabase.from("admin_requests").insert(basePayload).execute()
                } else {
                    throw error
                }
            }

            // 3. إشعار المدراء
            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("اقتراح صورة جديدة", "New Photo Suggestion"),
                body: L10n.t(
                    "اقتراح صورة جديدة لـ: \(memberName) تحتاج موافقتكم",
                    "New photo suggestion for: \(memberName) — needs approval"
                ),
                kind: RequestType.photoSuggestion.rawValue,
                requestId: photoRequestId,
                requestType: RequestType.photoSuggestion.rawValue
            )

            Log.info("[PhotoSuggestion] تم إرسال اقتراح صورة لـ \(memberName)")
            return true
        } catch {
            Log.error("[PhotoSuggestion] خطأ في إرسال اقتراح الصورة: \(error.localizedDescription)")
            return false
        }
    }

    func fetchPhotoSuggestionRequests(force: Bool = false) async {
        guard throttler.canFetch(key: "photoSuggestion", interval: 20, force: force) || photoSuggestionRequests.isEmpty else { return }
        throttler.didFetch(key: "photoSuggestion")

        do {
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:members_masked!member_id(*)")
                .eq("request_type", value: RequestType.photoSuggestion.rawValue)
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .order("created_at", ascending: false)
                .execute()
                .value

            self.photoSuggestionRequests = requests
        } catch {
            Log.fetchError("خطأ جلب اقتراحات الصور", error)
        }
    }

    /// الموافقة على اقتراح صورة — تحديث صورة العضو
    func approvePhotoSuggestion(request: AdminRequest) async {
        guard canModerate else { return }
        // طلبك أنت يعالجه غيرك (إلا المالك) — السيرفر يرفضه أيضاً (own_request)
        guard !isOwnRequest(requesterId: request.requesterId, memberId: request.memberId) else { return }
        guard let photoUrl = request.newValue, !photoUrl.isEmpty else {
            Log.error("[PhotoSuggestion] لا يوجد رابط صورة في الطلب")
            return
        }

        optimisticRemove(from: &photoSuggestionRequests, id: request.id, apiWork: { [weak self] in
            guard let self else { return }
            // السيرفر يضع الصورة (+ ?v=<وقت>) ويغلق ويُشعر (decide_admin_request)
            guard await self.decideOnServer(request.id, approve: true) != nil else { return }
            Log.info("[PhotoSuggestion] تم قبول اقتراح الصورة وتحديث الملف الشخصي")
        }, refresh: { [weak self] in
            await self?.fetchPhotoSuggestionRequests(force: true)
            await self?.memberVM?.fetchAllMembers(force: true)
        })
    }

    /// رفض اقتراح صورة — السيرفر يغلق ويُشعر، والتطبيق يحذف ملف الاقتراح (storage_cleanup)
    func rejectPhotoSuggestion(request: AdminRequest, reason: String? = nil) async {
        // المراقب يقدر يرفض حسب CLAUDE.md (المشرف فقط ممنوع من الرفض)
        guard canRejectRequests else { Log.warning("رفض الطلب مرفوض: لا صلاحية"); return }

        optimisticRemove(from: &photoSuggestionRequests, id: request.id, apiWork: { [weak self] in
            guard let self else { return }
            guard await self.decideOnServer(request.id, approve: false, reason: reason) != nil else { return }
            Log.info("[PhotoSuggestion] تم رفض اقتراح الصورة")
        }, refresh: { [weak self] in
            await self?.fetchPhotoSuggestionRequests(force: true)
        })
    }
}
