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
    @Published var isLoading: Bool = false
    @Published var mergeResult: MergeResult? = nil
    @Published var errorMessage: String? = nil

    /// معرّفات رسائل التواصل التي قرأها المدير (محفوظة محلياً في UserDefaults).
    /// تُستخدم لتحديد العدّاد "غير المقروء" المعروض في لوحة الإدارة.
    @Published private(set) var readContactMessageIds: Set<UUID> = AdminRequestViewModel.loadReadIds()

    private static let readIdsKey = "readContactMessageIds_v1"

    private static func loadReadIds() -> Set<UUID> {
        guard let arr = UserDefaults.standard.array(forKey: readIdsKey) as? [String] else { return [] }
        return Set(arr.compactMap(UUID.init(uuidString:)))
    }

    private func persistReadIds() {
        let arr = readContactMessageIds.map { $0.uuidString }
        UserDefaults.standard.set(arr, forKey: Self.readIdsKey)
    }

    /// تعليم رسالة كمقروءة محلياً. يرفع تحديث للـ UI تلقائياً.
    func markContactMessageRead(_ id: UUID) {
        guard !readContactMessageIds.contains(id) else { return }
        readContactMessageIds.insert(id)
        persistReadIds()
    }

    /// تعليم كل الرسائل الحالية كمقروءة.
    func markAllContactMessagesRead() {
        let allIds = Set(contactMessages.map { $0.id })
        guard !allIds.isSubset(of: readContactMessageIds) else { return }
        readContactMessageIds.formUnion(allIds)
        persistReadIds()
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
    }

    // MARK: - Private Helpers

    private var currentUser: FamilyMember? { authVM?.currentUser }
    private var canModerate: Bool { authVM?.canModerate ?? false }
    private var isAdmin: Bool { authVM?.isAdmin ?? false }
    /// قبول/رفض الطلبات: owner+admin+monitor (المشرف يقدر يقبل بس لا يرفض).
    /// نطابق `AuthViewModel.canRejectRequests` (راجع CLAUDE.md).
    private var canRejectRequests: Bool { authVM?.canRejectRequests ?? false }

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
        Task {
            await apiWork()
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refresh()
        }
    }

    // Schema error helpers delegated to ErrorHelper

    /// Helper to get a member name by ID — fallback to UUID if not found
    private func getSafeMemberName(for memberId: UUID) -> String {
        return memberById(memberId)?.fullName ?? memberId.uuidString
    }

    /// إشعار للإدارة في "المستجدات" بإجراء تمّ (موافقة/رفض)
    /// in-app + push — يصل لكل canModerate (broadcast بدون target)
    private func broadcastCompletedAction(titleAr: String, titleEn: String, bodyAr: String, bodyEn: String, kind: NotificationKind) async {
        await notificationVM?.notifyAdminsWithPush(
            title: L10n.t(titleAr, titleEn),
            body: L10n.t(bodyAr, bodyEn),
            kind: kind.rawValue
        )
    }

    /// Lookup a member by ID from authVM's member cache
    private func memberById(_ id: UUID) -> FamilyMember? {
        return memberVM?.member(byId: id)
    }

    // MARK: - Tree Edit Requests

    /// إرسال طلب تعديل الشجرة (إضافة / تعديل اسم / حذف) — v2 structured payload
    /// رفع صورة مقترحة لطلب «إضافة صورة» — تُخزَّن تحت suggestions/<uuid>.jpg في
    /// bucket الأفاتار (عام) ولا تُطبَّق على الملف إلا بعد موافقة الإدارة.
    /// تُعيد الرابط العام لتضمينه في حمولة الطلب، أو nil عند الفشل.
    func uploadPhotoSuggestion(_ image: UIImage) async -> String? {
        guard let imageData = ImageProcessor.process(image, for: .avatar) else { return nil }
        let fileName = "suggestions/\(UUID().uuidString.lowercased()).jpg"
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

    // MARK: - Fetch / Mark Contact Messages

    /// رسائل التواصل من شاشة "التواصل" — للإدارة فقط.
    /// تجلب كل الـ admin_requests بنوع contact_message — سواء pending أو approved (مُعالَجة).
    func fetchContactMessages(force: Bool = false) async {
        guard throttler.canFetch(key: "contactMessages", interval: 20, force: force) || contactMessages.isEmpty else { return }
        throttler.didFetch(key: "contactMessages")
        do {
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:profiles!member_id(*)")
                .eq("request_type", value: "contact_message")
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            self.contactMessages = requests
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
                .select("*, member:profiles!member_id(*)")
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
        let payload = request.treeEditPayload

        optimisticRemove(from: &treeEditRequests, id: request.id, apiWork: { [weak self] in
            guard let self = self else { return }
            do {
                let resolvedAction = payload?.resolvedAction
                var notifBody = L10n.t("تم قبول طلب تعديل الشجرة", "Your tree edit request was approved")

                if let payload = payload, let action = resolvedAction {
                    let memberName = payload.targetMemberName ?? request.member?.fullName ?? ""
                    switch action {
                    case .editName:
                        if let targetId = payload.targetMemberId,
                           let newName = payload.newName?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !newName.isEmpty {
                            let nameParts = newName.split(whereSeparator: \.isWhitespace).map(String.init)
                            let newFirstName = nameParts.first ?? newName
                            try await self.supabase
                                .from("profiles")
                                .update([
                                    "full_name": AnyEncodable(newName),
                                    "first_name": AnyEncodable(newFirstName)
                                ])
                                .eq("id", value: targetId)
                                .execute()
                            notifBody = L10n.t(
                                "تم تغيير الاسم إلى: «\(newName)»",
                                "Name changed to: «\(newName)»"
                            )
                            Log.info("[TreeEdit] Name updated: \(newName)")
                        }

                    case .editPhone:
                        if let targetId = payload.targetMemberId,
                           let newPhone = payload.newPhone, !newPhone.isEmpty {
                            try await self.supabase
                                .from("profiles")
                                .update(["phone_number": AnyEncodable(newPhone)])
                                .eq("id", value: targetId)
                                .execute()
                            let target = memberName.isEmpty ? "" : " لـ «\(memberName)»"
                            let targetEn = memberName.isEmpty ? "" : " for «\(memberName)»"
                            notifBody = L10n.t(
                                "تم تحديث رقم الهاتف\(target)",
                                "Phone number updated\(targetEn)"
                            )
                            Log.info("[TreeEdit] Phone updated for: \(memberName)")
                        }

                    case .deceased:
                        if let targetId = payload.targetMemberId {
                            var update: [String: AnyEncodable] = ["is_deceased": AnyEncodable(true)]
                            if let dateStr = payload.deathDate, !dateStr.isEmpty {
                                update["death_date"] = AnyEncodable(dateStr)
                            }
                            try await self.supabase
                                .from("profiles")
                                .update(update)
                                .eq("id", value: targetId)
                                .execute()
                            let target = memberName.isEmpty ? "" : " لـ «\(memberName)»"
                            let targetEn = memberName.isEmpty ? "" : " for «\(memberName)»"
                            notifBody = L10n.t(
                                "تم تأكيد حالة الوفاة\(target)",
                                "Deceased status confirmed\(targetEn)"
                            )
                            Log.info("[TreeEdit] Deceased marked: \(memberName)")
                        }

                    case .delete:
                        if let targetId = payload.targetMemberId {
                            try await self.supabase
                                .from("profiles")
                                .update(["is_hidden_from_tree": AnyEncodable(true)])
                                .eq("id", value: targetId)
                                .execute()
                            let target = memberName.isEmpty ? "" : " «\(memberName)»"
                            let targetEn = memberName.isEmpty ? "" : " «\(memberName)»"
                            notifBody = L10n.t(
                                "تم قبول طلب حذف\(target) من الشجرة",
                                "Removal request approved\(targetEn)"
                            )
                            Log.info("[TreeEdit] Member hidden from tree: \(memberName)")
                        }

                    case .add:
                        if let parentId = payload.parentMemberId,
                           let newMemberName = payload.newMemberName?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !newMemberName.isEmpty {
                            let newId = UUID()
                            let nameParts = newMemberName.split(whereSeparator: \.isWhitespace).map(String.init)
                            let firstName = nameParts.first ?? newMemberName

                            let parentMember = self.memberVM?.member(byId: UUID(uuidString: parentId) ?? UUID())
                            let combinedFullName = parentMember.map { "\(firstName) \($0.fullName)" } ?? newMemberName

                            let sonData: [String: AnyEncodable] = [
                                "id": AnyEncodable(newId.uuidString),
                                "first_name": AnyEncodable(firstName),
                                "full_name": AnyEncodable(combinedFullName),
                                "father_id": AnyEncodable(parentId),
                                "role": AnyEncodable("member"),
                                "status": AnyEncodable("active"),
                                "is_phone_hidden": AnyEncodable(true),
                                "sort_order": AnyEncodable(0)
                            ]
                            try await self.supabase.from("profiles").insert(sonData).execute()

                            let parentName = payload.parentMemberName ?? parentMember?.fullName ?? ""
                            notifBody = L10n.t(
                                "تم إضافة «\(firstName)» تحت «\(parentName)»",
                                "«\(firstName)» added under «\(parentName)»"
                            )
                            Log.info("[TreeEdit] Member added: \(combinedFullName)")
                        }

                    case .editBirth:
                        // تاريخ الميلاد الجديد في newBirthDate (مع دعم newName للطلبات القديمة).
                        if let targetId = payload.targetMemberId,
                           let newDate = (payload.newBirthDate ?? payload.newName)?
                               .trimmingCharacters(in: .whitespacesAndNewlines),
                           !newDate.isEmpty {
                            try await self.supabase
                                .from("profiles")
                                .update(["birth_date": AnyEncodable(newDate)])
                                .eq("id", value: targetId)
                                .execute()
                            notifBody = L10n.t(
                                "تم تحديث تاريخ الميلاد إلى: «\(newDate)»",
                                "Birth date updated to: «\(newDate)»"
                            )
                            Log.info("[TreeEdit] Birth date updated: \(newDate)")
                        }

                    case .addDeathDate:
                        // إضافة تاريخ وفاة لمتوفى — يضبط is_deceased + death_date.
                        if let targetId = payload.targetMemberId,
                           let dateStr = payload.deathDate?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !dateStr.isEmpty {
                            try await self.supabase
                                .from("profiles")
                                .update([
                                    "is_deceased": AnyEncodable(true),
                                    "death_date": AnyEncodable(dateStr)
                                ])
                                .eq("id", value: targetId)
                                .execute()
                            let target = memberName.isEmpty ? "" : " لـ «\(memberName)»"
                            let targetEn = memberName.isEmpty ? "" : " for «\(memberName)»"
                            notifBody = L10n.t(
                                "تم إضافة تاريخ الوفاة\(target)",
                                "Death date added\(targetEn)"
                            )
                            Log.info("[TreeEdit] Death date added: \(dateStr)")
                        }

                    case .addPhoto:
                        // اعتماد صورة مقترحة — تُضبط avatar_url على رابط الصورة المرفوعة.
                        if let targetId = payload.targetMemberId,
                           let url = payload.newPhotoUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !url.isEmpty {
                            try await self.supabase
                                .from("profiles")
                                .update(["avatar_url": AnyEncodable(url)])
                                .eq("id", value: targetId)
                                .execute()
                            let target = memberName.isEmpty ? "" : " لـ «\(memberName)»"
                            let targetEn = memberName.isEmpty ? "" : " for «\(memberName)»"
                            notifBody = L10n.t(
                                "تم اعتماد الصورة\(target)",
                                "Photo approved\(targetEn)"
                            )
                            Log.info("[TreeEdit] Photo approved for: \(memberName)")
                        }

                    case .other:
                        // طلب حر — لا تعديل تلقائي؛ القبول يُعلِم العضو فقط.
                        let target = memberName.isEmpty ? "" : " «\(memberName)»"
                        let targetEn = memberName.isEmpty ? "" : " «\(memberName)»"
                        notifBody = L10n.t(
                            "تم قبول طلبك\(target)",
                            "Your request\(targetEn) was approved"
                        )
                        Log.info("[TreeEdit] Other request approved: \(memberName)")
                    }
                } else if let legacyAction = payload?.action {
                    // Backwards compat for v2 strings without resolved action
                    Log.info("[TreeEdit] Legacy/unmapped action: \(legacyAction)")
                }

                try await self.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.approved.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()

                await self.notificationVM?.sendNotification(
                    title: L10n.t("تم قبول طلبك", "Your Request Was Approved"),
                    body: notifBody,
                    targetMemberIds: [request.requesterId]
                )

                // إشعار للإدارة في "المستجدات"
                let memberName = payload?.targetMemberName ?? request.member?.fullName ?? ""
                let actionAr = payload?.resolvedAction?.arabicLabel ?? "تعديل"
                let actionEn = payload?.resolvedAction?.englishLabel ?? "edit"
                await self.broadcastCompletedAction(
                    titleAr: "تم قبول \(actionAr)",
                    titleEn: "\(actionEn) Approved",
                    bodyAr: memberName.isEmpty ? "تم قبول طلب \(actionAr)" : "تم قبول طلب \(actionAr) لـ «\(memberName)»",
                    bodyEn: memberName.isEmpty ? "\(actionEn) request approved" : "\(actionEn) request for «\(memberName)» approved",
                    kind: .treeEdit
                )

                Log.info("[TreeEdit] Approved: \(payload?.action ?? request.newValue ?? "")")
            } catch {
                Log.error("[TreeEdit] Approve failed: \(error)")
            }
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

    /// لاحقة «السبب: …» تُضاف لنص إشعار الرفض إذا كتب المدير سبباً.
    static func rejectReasonSuffix(_ reason: String?, arabic: Bool) -> String {
        guard let r = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty else { return "" }
        return arabic ? "\nالسبب: \(r)" : "\nReason: \(r)"
    }

    func rejectTreeEditRequest(request: AdminRequest, reason: String? = nil) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard authVM?.canRejectRequests == true else { Log.warning("رفض الطلب مرفوض: الصلاحية للإدارة فقط"); return }
        let payload = request.treeEditPayload
        let actionAr = payload?.resolvedAction?.arabicLabel ?? L10n.t("التعديل", "edit")
        let actionEn = payload?.resolvedAction?.englishLabel ?? "edit"
        let memberName = payload?.targetMemberName ?? request.member?.fullName ?? ""

        optimisticRemove(from: &treeEditRequests, id: request.id, apiWork: { [weak self] in
            do {
                try await self?.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.rejected.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()

                let reasonText = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let bodyAr: String
                let bodyEn: String
                if memberName.isEmpty {
                    bodyAr = reasonText.isEmpty
                        ? "تم رفض طلب \(actionAr)"
                        : "تم رفض طلب \(actionAr)\nالسبب: \(reasonText)"
                    bodyEn = reasonText.isEmpty
                        ? "Your \(actionEn) request was rejected"
                        : "Your \(actionEn) request was rejected\nReason: \(reasonText)"
                } else {
                    bodyAr = reasonText.isEmpty
                        ? "تم رفض طلب \(actionAr)\n«\(memberName)»"
                        : "تم رفض طلب \(actionAr)\n«\(memberName)»\nالسبب: \(reasonText)"
                    bodyEn = reasonText.isEmpty
                        ? "Your \(actionEn) request was rejected\n«\(memberName)»"
                        : "Your \(actionEn) request was rejected\n«\(memberName)»\nReason: \(reasonText)"
                }

                await self?.notificationVM?.sendNotification(
                    title: L10n.t("لم يتم قبول طلبك", "Your Request Was Declined"),
                    body: L10n.t(bodyAr, bodyEn),
                    targetMemberIds: [request.requesterId],
                    kind: "request_rejected"
                )

                // إشعار للإدارة في "المستجدات"
                await self?.broadcastCompletedAction(
                    titleAr: "تم رفض \(actionAr)",
                    titleEn: "\(actionEn) Rejected",
                    bodyAr: memberName.isEmpty ? "تم رفض طلب \(actionAr)" : "تم رفض طلب \(actionAr) لـ «\(memberName)»",
                    bodyEn: memberName.isEmpty ? "\(actionEn) request rejected" : "\(actionEn) request for «\(memberName)» rejected",
                    kind: .treeEdit
                )

                Log.info("[TreeEdit] Rejected: \(actionAr) — \(memberName)")
            } catch {
                Log.error("[TreeEdit] Reject failed: \(error)")
            }
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
                .select("*, member:profiles!member_id(*)")
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
        let memberName = request.member?.fullName ?? ""
        optimisticRemove(from: &deceasedRequests, id: request.id, apiWork: { [weak self] in
            do {
                try await self?.supabase
                    .from("profiles")
                    .update(["is_deceased": AnyEncodable(true)])
                    .eq("id", value: request.memberId.uuidString)
                    .execute()

                try await self?.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.approved.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()

                await self?.notificationVM?.sendNotification(
                    title: L10n.t("تم قبول طلبك", "Your Request Was Approved"),
                    body: L10n.t("تم تأكيد حالة الوفاة وتحديث الشجرة", "Deceased status confirmed and tree updated"),
                    targetMemberIds: [request.requesterId]
                )

                await self?.broadcastCompletedAction(
                    titleAr: "تم قبول طلب وفاة",
                    titleEn: "Deceased Status Approved",
                    bodyAr: memberName.isEmpty ? "تم تأكيد حالة وفاة" : "تم تأكيد وفاة «\(memberName)»",
                    bodyEn: memberName.isEmpty ? "Deceased status confirmed" : "Deceased status confirmed for «\(memberName)»",
                    kind: .deceasedReport
                )
                Log.info("تم قبول الطلب وتحديث الشجرة بنجاح")
            } catch {
                Log.error("فشل في تنفيذ عملية الموافقة: \(error)")
            }
        }, refresh: { [weak self] in
            await self?.fetchDeceasedRequests(force: true)
            await self?.memberVM?.fetchAllMembers(force: true)
        })
    }

    func rejectDeceasedRequest(request: AdminRequest, reason: String? = nil) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        // المراقب يقدر يرفض حسب CLAUDE.md (المشرف فقط ممنوع من الرفض)
        guard canRejectRequests else { Log.warning("رفض الطلب مرفوض: لا صلاحية"); return }
        let memberName = request.member?.fullName ?? ""
        optimisticRemove(from: &deceasedRequests, id: request.id, apiWork: { [weak self] in
            do {
                try await self?.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.rejected.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()

                await self?.broadcastCompletedAction(
                    titleAr: "تم رفض طلب وفاة",
                    titleEn: "Deceased Request Rejected",
                    bodyAr: (memberName.isEmpty ? "تم رفض طلب تأكيد وفاة" : "تم رفض طلب تأكيد وفاة «\(memberName)»") + Self.rejectReasonSuffix(reason, arabic: true),
                    bodyEn: (memberName.isEmpty ? "Deceased request rejected" : "Deceased request for «\(memberName)» rejected") + Self.rejectReasonSuffix(reason, arabic: false),
                    kind: .deceasedReport
                )
                Log.info("تم رفض طلب تأكيد الوفاة")
            } catch {
                Log.error("فشل في رفض طلب الوفاة: \(error)")
            }
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
                .select("*, member:profiles!member_id(*)")
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
        let childName = request.member?.firstName ?? ""
        optimisticRemove(from: &childAddRequests, id: request.id, apiWork: { [weak self] in
            do {
                if let childId = request.newValue {
                    try await self?.supabase
                        .from("profiles")
                        .delete()
                        .eq("id", value: childId)
                        .execute()
                }

                try await self?.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.rejected.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()

                await self?.broadcastCompletedAction(
                    titleAr: "تم رفض طلب إضافة ابن",
                    titleEn: "Child Add Rejected",
                    bodyAr: (childName.isEmpty ? "تم رفض طلب إضافة ابن" : "تم رفض طلب إضافة «\(childName)»") + Self.rejectReasonSuffix(reason, arabic: true),
                    bodyEn: (childName.isEmpty ? "Child add request rejected" : "Add request for «\(childName)» rejected") + Self.rejectReasonSuffix(reason, arabic: false),
                    kind: .childAdd
                )
                Log.info("تم رفض طلب إضافة الابن وحذفه من الشجرة")
            } catch {
                Log.error("فشل رفض طلب إضافة الابن: \(error)")
            }
        }, refresh: { [weak self] in
            await self?.fetchChildAddRequests(force: true)
            await self?.memberVM?.fetchAllMembers(force: true)
        })
    }

    func acknowledgeChildAddRequest(request: AdminRequest) async {
        optimisticRemove(from: &childAddRequests, id: request.id, apiWork: { [weak self] in
            do {
                try await self?.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.approved.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()

                // جلب اسم الابن والأب من البيانات
                let childFirstName = request.member?.firstName ?? ""
                let parentName: String = {
                    if let fatherId = request.member?.fatherId,
                       let parent = self?.memberVM?.member(byId: fatherId) {
                        return parent.fullName
                    }
                    return ""
                }()

                let childNotifBody = L10n.t(
                    "تم إضافة الابن: «\(childFirstName)» لـ: «\(parentName)»",
                    "Son added: «\(childFirstName)» to: «\(parentName)»"
                )

                await self?.notificationVM?.sendNotification(
                    title: L10n.t("تم قبول طلبك", "Your Request Was Approved"),
                    body: childNotifBody,
                    targetMemberIds: [request.requesterId]
                )

                await self?.broadcastCompletedAction(
                    titleAr: "تم قبول طلب إضافة ابن",
                    titleEn: "Child Add Approved",
                    bodyAr: "تم إضافة «\(childFirstName)» لـ «\(parentName)»",
                    bodyEn: "«\(childFirstName)» added to «\(parentName)»",
                    kind: .childAdd
                )
                Log.info("تم تأكيد طلب إضافة الابن بنجاح")
            } catch {
                Log.error("فشل تأكيد طلب إضافة الابن: \(error)")
            }
        }, refresh: { [weak self] in
            await self?.fetchChildAddRequests(force: true)
        })
    }

    /// الموافقة على جميع طلبات إضافة الأبناء المعلقة دفعة واحدة
    func bulkApproveChildAddRequests() async -> Int {
        self.isLoading = true
        let pending = childAddRequests
        var successCount = 0

        for request in pending {
            do {
                try await supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.approved.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()
                successCount += 1
            } catch {
                Log.error("فشل قبول طلب إضافة ابن \(request.id): \(error.localizedDescription)")
            }
        }

        await fetchChildAddRequests(force: true)

        Log.info("تم قبول \(successCount)/\(pending.count) طلب إضافة أبناء")
        self.isLoading = false
        return successCount
    }

    func bulkApproveJoinRequests(memberIds: [UUID]) async -> Int {
        guard !memberIds.isEmpty else { return 0 }
        isLoading = true
        var approved = 0
        do {
            let payload: [String: AnyEncodable] = [
                "role": AnyEncodable("member"),
                "status": AnyEncodable("active"),
                "is_hidden_from_tree": AnyEncodable(false)
            ]
            try await supabase
                .from("profiles")
                .update(payload)
                .in("id", values: memberIds.map { $0.uuidString })
                .execute()

            for id in memberIds {
                if let index = memberVM?.allMembers.firstIndex(where: { $0.id == id }) {
                    memberVM?.allMembers[index].role = .member
                    memberVM?.allMembers[index].status = .active
                    memberVM?.allMembers[index].isHiddenFromTree = false
                    approved += 1
                }
            }
            memberVM?.objectWillChange.send()
            Log.info("تم قبول \(approved) عضو جماعياً")
        } catch {
            self.errorMessage = L10n.t("فشل القبول الجماعي", "Bulk approve failed")
            Log.error("فشل القبول الجماعي: \(error.localizedDescription)")
        }
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
                // تفعيل العضو: status=active + role=member للمعلّق + اعتماد طلب الانضمام
                let profiles: [FamilyMember] = (try? await supabase
                    .from("profiles")
                    .select()
                    .eq("id", value: memberId.uuidString)
                    .limit(1)
                    .execute()
                    .value) ?? []

                var payload: [String: AnyEncodable] = ["status": AnyEncodable("active")]
                if profiles.first?.role == .pending {
                    payload["role"] = AnyEncodable("member")
                }
                try await supabase
                    .from("profiles")
                    .update(payload)
                    .eq("id", value: memberId.uuidString)
                    .execute()

                _ = try? await supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.approved.rawValue)])
                    .eq("member_id", value: memberId.uuidString)
                    .eq("request_type", value: RequestType.joinRequest.rawValue)
                    .eq("status", value: ApprovalStatus.pending.rawValue)
                    .execute()
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

            // 2) Activate member directly after adding the number
            let profileResponse: [FamilyMember] = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: memberId.uuidString)
                .limit(1)
                .execute()
                .value

            if let profile = profileResponse.first {
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

    func requestPhoneNumberChange(memberId: UUID, newPhoneNumber: String) async {
        self.isLoading = true
        guard let normalizedPhone = KuwaitPhone.normalizeForStorageFromInput(newPhoneNumber) else {
            Log.error("رقم طلب التغيير غير صالح.")
            self.isLoading = false
            return
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
        }
        self.isLoading = false
    }

    // MARK: - Name Change Requests

    func requestNameChange(memberId: UUID, newName: String) async {
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
        }
        self.isLoading = false
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
                .select("*, member:profiles!member_id(*)")
                .eq("request_type", value: RequestType.nameChange.rawValue)
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
        guard let newName = request.newValue, !newName.isEmpty else {
            Log.error("[NameChange] الاسم الجديد غير موجود في الطلب")
            return
        }

        optimisticRemove(from: &nameChangeRequests, id: request.id, apiWork: { [weak self] in
            do {
                let nameParts = newName.split(whereSeparator: \.isWhitespace).map(String.init)
                let newFirstName = nameParts.first ?? newName

                try await self?.supabase
                    .from("profiles")
                    .update([
                        "full_name": AnyEncodable(newName),
                        "first_name": AnyEncodable(newFirstName)
                    ])
                    .eq("id", value: request.memberId.uuidString)
                    .execute()

                try await self?.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.approved.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()

                await self?.notificationVM?.sendNotification(
                    title: L10n.t("تم تغيير اسمك", "Your Name Was Changed"),
                    body: L10n.t("تم اعتماد اسمك الجديد: \(newName)", "Your new name has been approved: \(newName)"),
                    targetMemberIds: [request.requesterId]
                )

                let oldName = request.member?.fullName ?? ""
                await self?.broadcastCompletedAction(
                    titleAr: "تم قبول تغيير اسم",
                    titleEn: "Name Change Approved",
                    bodyAr: oldName.isEmpty
                        ? "وافقت الإدارة — تم اعتماد الاسم الجديد: «\(newName)»"
                        : "وافقت الإدارة — تغيّر الاسم من «\(oldName)» إلى «\(newName)»",
                    bodyEn: oldName.isEmpty
                        ? "Approved by administration — New name: «\(newName)»"
                        : "Approved by administration — Name changed from «\(oldName)» to «\(newName)»",
                    kind: .nameChange
                )
                Log.info("[NameChange] تم قبول طلب تغيير الاسم → \(newName)")
            } catch {
                Log.error("[NameChange] فشل قبول طلب تغيير الاسم: \(error)")
            }
        }, refresh: { [weak self] in
            await self?.fetchNameChangeRequests(force: true)
            await self?.memberVM?.fetchAllMembers(force: true)
        })
    }

    func rejectNameChangeRequest(request: AdminRequest, reason: String? = nil) async {
        // كان isAdmin (يستبعد المراقب). حسب CLAUDE.md المراقب يقدر يرفض.
        guard canRejectRequests else { Log.warning("رفض الطلب مرفوض: لا صلاحية"); return }
        optimisticRemove(from: &nameChangeRequests, id: request.id, apiWork: { [weak self] in
            do {
                try await self?.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.rejected.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()

                await self?.notificationVM?.sendNotification(
                    title: L10n.t("لم يتم قبول طلبك", "Your Request Was Declined"),
                    body: L10n.t(
                        "طلب تغيير الاسم لم تتم الموافقة عليه" + Self.rejectReasonSuffix(reason, arabic: true),
                        "Your name change request was not approved" + Self.rejectReasonSuffix(reason, arabic: false)
                    ),
                    targetMemberIds: [request.requesterId],
                    kind: "request_rejected"
                )

                let memberName = request.member?.fullName ?? ""
                await self?.broadcastCompletedAction(
                    titleAr: "تم رفض تغيير اسم",
                    titleEn: "Name Change Rejected",
                    bodyAr: memberName.isEmpty ? "تم رفض طلب تغيير الاسم" : "تم رفض طلب تغيير اسم «\(memberName)»",
                    bodyEn: memberName.isEmpty ? "Name change rejected" : "Name change for «\(memberName)» rejected",
                    kind: .nameChange
                )
                Log.info("[NameChange] تم رفض طلب تغيير الاسم")
            } catch {
                Log.error("[NameChange] فشل رفض طلب تغيير الاسم: \(error)")
            }
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
                .select("*, member:profiles!member_id(*)")
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
        guard let newPhone = KuwaitPhone.normalizeForStorageFromInput(rawPhone) else { return }
        // التحقق من تكرار الرقم قبل الموافقة
        if let memberVM = memberVM {
            let check = memberVM.isPhoneDuplicate(newPhone, excludingMemberId: request.memberId)
            if check.isDuplicate {
                Log.warning("رفض تغيير الرقم: مستخدم من \(check.existingMember?.fullName ?? "")")
                return
            }
        }

        optimisticRemove(from: &phoneChangeRequests, id: request.id, apiWork: { [weak self] in
            do {
                try await self?.supabase
                    .from("profiles")
                    .update(["phone_number": AnyEncodable(newPhone)])
                    .eq("id", value: request.memberId.uuidString)
                    .execute()

                try await self?.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.approved.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()

                if let requesterId = request.requesterId {
                    await self?.notificationVM?.sendNotification(
                        title: L10n.t("تم تغيير رقم هاتفك", "Phone Number Updated"),
                        body: L10n.t("رقم هاتفك الجديد تم اعتماده بنجاح", "Your new phone number has been approved"),
                        targetMemberIds: [requesterId]
                    )
                }

                let memberName = request.member?.fullName ?? ""
                await self?.broadcastCompletedAction(
                    titleAr: "تم قبول تغيير رقم",
                    titleEn: "Phone Change Approved",
                    bodyAr: memberName.isEmpty ? "تم قبول طلب تغيير رقم" : "تم تغيير رقم «\(memberName)»",
                    bodyEn: memberName.isEmpty ? "Phone change approved" : "Phone for «\(memberName)» updated",
                    kind: .phoneChange
                )
            } catch {
                Log.error("خطأ اعتماد تغيير الرقم: \(error.localizedDescription)")
            }
        }, refresh: { [weak self] in
            await self?.fetchPhoneChangeRequests(force: true)
            await self?.memberVM?.fetchAllMembers(force: true)
        })
    }

    func rejectPhoneChangeRequest(request: PhoneChangeRequest, reason: String? = nil) async {
        // كان isAdmin (يستبعد المراقب). حسب CLAUDE.md المراقب يقدر يرفض.
        guard canRejectRequests else { Log.warning("رفض الطلب مرفوض: لا صلاحية"); return }

        optimisticRemove(from: &phoneChangeRequests, id: request.id, apiWork: { [weak self] in
            do {
                try await self?.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.rejected.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()

                if let requesterId = request.requesterId {
                    await self?.notificationVM?.sendNotification(
                        title: L10n.t("لم يتم قبول طلبك", "Your Request Was Declined"),
                        body: L10n.t(
                            "طلب تغيير رقم الهاتف لم تتم الموافقة عليه" + Self.rejectReasonSuffix(reason, arabic: true),
                            "Your phone change request was not approved" + Self.rejectReasonSuffix(reason, arabic: false)
                        ),
                        targetMemberIds: [requesterId],
                        kind: "request_rejected"
                    )
                }

                let memberName = request.member?.fullName ?? ""
                await self?.broadcastCompletedAction(
                    titleAr: "تم رفض تغيير رقم",
                    titleEn: "Phone Change Rejected",
                    bodyAr: memberName.isEmpty ? "تم رفض طلب تغيير رقم" : "تم رفض تغيير رقم «\(memberName)»",
                    bodyEn: memberName.isEmpty ? "Phone change rejected" : "Phone change for «\(memberName)» rejected",
                    kind: .phoneChange
                )
                Log.info("[PhoneChange] تم رفض طلب تغيير الرقم")
            } catch {
                Log.error("خطأ رفض تغيير الرقم: \(error.localizedDescription)")
            }
        }, refresh: { [weak self] in
            await self?.fetchPhoneChangeRequests(force: true)
        })
    }

    // MARK: - Account Activation & Member Approval

    func activateAccount(memberId: UUID) async {
        guard canModerate else { return }
        do {
            try await supabase
                .from("profiles")
                .update(["status": AnyEncodable("active")])
                .eq("id", value: memberId.uuidString)
                .execute()

            // Update local data through memberVM
            if let index = memberVM?.allMembers.firstIndex(where: { $0.id == memberId }) {
                memberVM?.allMembers[index].status = .active
                memberVM?.objectWillChange.send()
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
                kind: "account_activated"
            )
        } catch {
            Log.error("فشل تفعيل الحساب: \(error.localizedDescription)")
        }
    }

    /// Approve a new member and activate their account with father linkage
    func approveMember(memberId: UUID, fatherId: UUID?) async {
        guard canModerate else { Log.warning("قبول العضو مرفوض: لا صلاحية"); return }
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

        Log.info("[MERGE] بدء الدمج: \(newMemberId) ← \(existingTreeMemberId)")
        self.isLoading = true

        do {
            // استدعاء الـ atomic function على السيرفر — كل العمليات في transaction واحدة
            struct MergeParams: Encodable {
                let p_new_member_id: String
                let p_tree_member_id: String
            }
            struct MergeResponse: Decodable {
                let success: Bool
                let message: String
                let mergedName: String?
                enum CodingKeys: String, CodingKey {
                    case success, message
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
                kind: "join_approved"
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

    /// Reject a join request or permanently delete a member
    func rejectOrDeleteMember(memberId: UUID) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard authVM?.canDeleteMembers == true else {
            Log.error("تم رفض حذف السجل: الصلاحية للمالك فقط")
            self.errorMessage = L10n.t("ليس لديك صلاحية لرفض الطلبات.", "You don't have permission to reject requests.")
            return
        }

        // حذف فوري محلياً — ثم API بالخلفية
        let deletedName = memberById(memberId)?.fourPartName ?? "عضو"
        withAnimation(.snappy(duration: 0.25)) {
            memberVM?.allMembers.removeAll(where: { $0.id == memberId })
            memberVM?.currentMemberChildren.removeAll(where: { $0.id == memberId })
            memberVM?.membersVersion += 1
            memberVM?.objectWillChange.send()
        }

        Task { [weak self] in
            do {
                _ = try? await self?.supabase
                    .from("profiles")
                    .update(["father_id": AnyEncodable(Optional<String>.none)])
                    .eq("father_id", value: memberId.uuidString)
                    .execute()

                _ = try? await self?.supabase
                    .from("admin_requests")
                    .delete()
                    .eq("member_id", value: memberId.uuidString)
                    .execute()

                _ = try? await self?.supabase
                    .from("admin_requests")
                    .delete()
                    .eq("requester_id", value: memberId.uuidString)
                    .execute()

                try await self?.supabase
                    .from("profiles")
                    .delete()
                    .eq("id", value: memberId.uuidString)
                    .execute()

                await self?.notificationVM?.notifyAdminsWithPush(
                    title: L10n.t("حذف عضو", "Member Removed"),
                    body: L10n.t(
                        "تم حذف عضو من شجرة العائلة\n\(deletedName)",
                        "Removed from the family tree\n\(deletedName)"
                    ),
                    kind: "member_delete"
                )
                Log.info("تم حذف العضو مع تنظيف المراجع المرتبطة بنجاح")
            } catch {
                Log.error("خطأ في الحذف: \(error.localizedDescription)")
                await MainActor.run {
                    self?.errorMessage = L10n.t(
                        "فشل حذف العضو: \(error.localizedDescription)",
                        "Failed to delete member: \(error.localizedDescription)"
                    )
                }
            }
        }
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
                .select("*, member:profiles!member_id(*)")
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
        guard canModerate else { return }

        optimisticRemove(from: &newsReportRequests, id: request.id, apiWork: { [weak self] in
            do {
                if let postIdRaw = request.newValue, let postId = UUID(uuidString: postIdRaw) {
                    try await self?.supabase
                        .from("news")
                        .delete()
                        .eq("id", value: postId.uuidString)
                        .execute()
                }

                try await self?.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.approved.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()

                await self?.notificationVM?.sendNotification(
                    title: L10n.t("تمت مراجعة بلاغك", "Your Report Was Reviewed"),
                    body: L10n.t("بلاغك تم مراجعته واتخاذ الإجراء المناسب", "Your report was reviewed and appropriate action was taken"),
                    targetMemberIds: [request.requesterId]
                )
            } catch {
                Log.error("خطأ اعتماد بلاغ الخبر: \(error.localizedDescription)")
            }
        }, refresh: { [weak self] in
            await self?.fetchNewsReportRequests(force: true)
            await self?.newsVM?.fetchNews(force: true)
        })
    }

    func rejectNewsReport(request: AdminRequest) async {
        // المراقب يقدر يرفض حسب CLAUDE.md (المشرف فقط ممنوع من الرفض)
        guard canRejectRequests else { Log.warning("رفض الطلب مرفوض: لا صلاحية"); return }

        optimisticRemove(from: &newsReportRequests, id: request.id, apiWork: { [weak self] in
            do {
                try await self?.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.rejected.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()
            } catch {
                Log.error("خطأ رفض بلاغ الخبر: \(error.localizedDescription)")
            }
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
            let memberName = memberById(memberId)?.fullName ?? "عضو"
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
                .select("*, member:profiles!member_id(*)")
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
        guard let photoUrl = request.newValue, !photoUrl.isEmpty else {
            Log.error("[PhotoSuggestion] لا يوجد رابط صورة في الطلب")
            return
        }

        optimisticRemove(from: &photoSuggestionRequests, id: request.id, apiWork: { [weak self] in
            do {
                let timestamp = Int(Date().timeIntervalSince1970)
                let urlWithCache = photoUrl.contains("?") ? "\(photoUrl)&v=\(timestamp)" : "\(photoUrl)?v=\(timestamp)"

                try await self?.supabase
                    .from("profiles")
                    .update(["avatar_url": AnyEncodable(urlWithCache)])
                    .eq("id", value: request.memberId.uuidString)
                    .execute()

                try await self?.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.approved.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()

                await self?.notificationVM?.sendNotification(
                    title: L10n.t("تم قبول اقتراحك", "Your Suggestion Was Approved"),
                    body: L10n.t("الصورة المقترحة تم قبولها وتحديثها", "Your photo suggestion was approved and applied"),
                    targetMemberIds: [request.requesterId]
                )
                Log.info("[PhotoSuggestion] تم قبول اقتراح الصورة وتحديث الملف الشخصي")
            } catch {
                Log.error("[PhotoSuggestion] خطأ قبول اقتراح الصورة: \(error.localizedDescription)")
            }
        }, refresh: { [weak self] in
            await self?.fetchPhotoSuggestionRequests(force: true)
            await self?.memberVM?.fetchAllMembers(force: true)
        })
    }

    /// رفض اقتراح صورة — حذف الصورة من التخزين
    func rejectPhotoSuggestion(request: AdminRequest, reason: String? = nil) async {
        // المراقب يقدر يرفض حسب CLAUDE.md (المشرف فقط ممنوع من الرفض)
        guard canRejectRequests else { Log.warning("رفض الطلب مرفوض: لا صلاحية"); return }

        optimisticRemove(from: &photoSuggestionRequests, id: request.id, apiWork: { [weak self] in
            do {
                if let photoUrl = request.newValue,
                   let url = URL(string: photoUrl),
                   let range = url.path.range(of: "/storage/v1/object/public/avatars/") {
                    let storagePath = String(url.path[range.upperBound...])
                    _ = try? await self?.supabase.storage
                        .from("avatars")
                        .remove(paths: [storagePath])
                }

                try await self?.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.rejected.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()

                await self?.notificationVM?.sendNotification(
                    title: L10n.t("لم يتم قبول طلبك", "Your Request Was Declined"),
                    body: L10n.t(
                        "اقتراح الصورة لم تتم الموافقة عليه" + Self.rejectReasonSuffix(reason, arabic: true),
                        "Your photo suggestion was not approved" + Self.rejectReasonSuffix(reason, arabic: false)
                    ),
                    targetMemberIds: [request.requesterId],
                    kind: "request_rejected"
                )
                Log.info("[PhotoSuggestion] تم رفض اقتراح الصورة")
            } catch {
                Log.error("[PhotoSuggestion] خطأ رفض اقتراح الصورة: \(error.localizedDescription)")
            }
        }, refresh: { [weak self] in
            await self?.fetchPhotoSuggestionRequests(force: true)
        })
    }
}
