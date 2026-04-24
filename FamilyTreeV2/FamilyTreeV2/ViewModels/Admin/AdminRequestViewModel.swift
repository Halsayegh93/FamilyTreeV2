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
    @Published var isLoading: Bool = false
    @Published var mergeResult: MergeResult? = nil
    @Published var errorMessage: String? = nil
    
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

    /// Lookup a member by ID from authVM's member cache
    private func memberById(_ id: UUID) -> FamilyMember? {
        return memberVM?.member(byId: id)
    }

    // MARK: - Tree Edit Requests

    /// إرسال طلب تعديل الشجرة (إضافة / تعديل اسم / حذف) — v2 structured payload
    func submitTreeEditRequest(payload: TreeEditPayload) async -> Bool {
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

            let basePayload: [String: AnyEncodable] = [
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
            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("طلب تعديل شجرة العائلة", "Family Tree Edit Request"),
                body: L10n.t(
                    "طلب تعديل: \(payload.action) — \(memberName)",
                    "Edit request: \(payload.action) — \(memberName)"
                ),
                kind: NotificationKind.treeEdit.rawValue
            )

            Log.info("[TreeEdit] Submitted: \(payload.action) — \(memberName)")
            return true
        } catch {
            Log.error("[TreeEdit] Submit failed: \(error.localizedDescription)")
            return false
        }
    }

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
            Log.error("فشل جلب طلبات تعديل الشجرة: \(error)")
        }
    }

    func approveTreeEditRequest(request: AdminRequest) async {
        let payload = request.treeEditPayload

        optimisticRemove(from: &treeEditRequests, id: request.id, apiWork: { [weak self] in
            do {
                // 1. Perform actual tree edit based on action type
                if let payload = payload {
                    switch payload.action {
                    case "تعديل اسم":
                        if let targetId = payload.targetMemberId,
                           let newName = payload.newName, !newName.isEmpty {
                            let nameParts = newName.split(whereSeparator: \.isWhitespace).map(String.init)
                            let newFirstName = nameParts.first ?? newName
                            try await self?.supabase
                                .from("profiles")
                                .update([
                                    "full_name": AnyEncodable(newName),
                                    "first_name": AnyEncodable(newFirstName)
                                ])
                                .eq("id", value: targetId)
                                .execute()
                            Log.info("[TreeEdit] Name updated: \(newName)")
                        }

                    case "حذف":
                        if let targetId = payload.targetMemberId {
                            try await self?.supabase
                                .from("profiles")
                                .update(["is_hidden_from_tree": AnyEncodable(true)])
                                .eq("id", value: targetId)
                                .execute()
                            Log.info("[TreeEdit] Member hidden from tree: \(targetId)")
                        }

                    case "إضافة":
                        // Admin needs to add manually — context provided in notification
                        Log.info("[TreeEdit] Add request approved — admin should add manually")

                    default:
                        break
                    }
                }

                // 2. Mark request as approved
                try await self?.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.approved.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()

                // 3. Notify requester with action-specific message
                let actionDesc = payload?.action ?? request.newValue ?? ""
                let notifBody: String
                switch payload?.action {
                case "تعديل اسم":
                    let newName = payload?.newName ?? ""
                    notifBody = L10n.t(
                        "تم تغيير الاسم إلى: \(newName)",
                        "Name changed to: \(newName)"
                    )
                case "حذف":
                    notifBody = L10n.t(
                        "تم قبول طلب الحذف من الشجرة",
                        "Your removal request was approved"
                    )
                case "إضافة":
                    let childName = payload?.newMemberName ?? ""
                    let parentName = payload?.parentMemberName ?? ""
                    notifBody = L10n.t(
                        "تم إضافة الابن: «\(childName)» لـ: «\(parentName)»",
                        "Son added: «\(childName)» to: «\(parentName)»"
                    )
                default:
                    notifBody = L10n.t("تم قبول طلب تعديل الشجرة", "Your tree edit request was approved")
                }

                await self?.notificationVM?.sendNotification(
                    title: L10n.t("تم قبول طلبك", "Your Request Was Approved"),
                    body: notifBody,
                    targetMemberIds: [request.requesterId]
                )
                Log.info("[TreeEdit] Approved: \(actionDesc)")
            } catch {
                Log.error("[TreeEdit] Approve failed: \(error)")
            }
        }, refresh: { [weak self] in
            await self?.fetchTreeEditRequests(force: true)
            await self?.memberVM?.fetchAllMembers(force: true)
        })
    }

    func rejectTreeEditRequest(request: AdminRequest, reason: String? = nil) async {
        guard isAdmin else { Log.warning("رفض الطلب مرفوض: الصلاحية للمدير فقط"); return }
        optimisticRemove(from: &treeEditRequests, id: request.id, apiWork: { [weak self] in
            do {
                try await self?.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.rejected.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()

                // Notify requester about rejection
                let actionDesc = request.newValue ?? ""
                let reasonText = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let bodyAr = reasonText.isEmpty
                    ? "تم رفض طلب \(actionDesc) في الشجرة"
                    : "تم رفض طلب \(actionDesc) في الشجرة: \(reasonText)"
                let bodyEn = reasonText.isEmpty
                    ? "Your \(actionDesc) tree edit request was rejected"
                    : "Your \(actionDesc) tree edit request was rejected: \(reasonText)"

                await self?.notificationVM?.sendNotification(
                    title: L10n.t("لم يتم قبول طلبك", "Your Request Was Declined"),
                    body: L10n.t(bodyAr, bodyEn),
                    targetMemberIds: [request.requesterId]
                )
                Log.info("[TreeEdit] Rejected: \(actionDesc)")
            } catch {
                Log.error("[TreeEdit] Reject failed: \(error)")
            }
        }, refresh: { [weak self] in
            await self?.fetchTreeEditRequests(force: true)
        })
    }

    // MARK: - Deceased Status Requests

    func requestDeceasedStatus(memberId: UUID, deathDate: Date?) async {
        self.isLoading = true
        do {
            let dateString = deathDate.map { DateHelper.format($0) } ?? "غير محدد"

            let requestData: [String: AnyEncodable] = [
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
                kind: RequestType.deceasedReport.rawValue
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
            Log.error("فشل جلب طلبات الوفاة: \(error)")
        }
    }

    func approveDeceasedRequest(request: AdminRequest) async {
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
                Log.info("تم قبول الطلب وتحديث الشجرة بنجاح")
            } catch {
                Log.error("فشل في تنفيذ عملية الموافقة: \(error)")
            }
        }, refresh: { [weak self] in
            await self?.fetchDeceasedRequests(force: true)
            await self?.memberVM?.fetchAllMembers(force: true)
        })
    }

    func rejectDeceasedRequest(request: AdminRequest) async {
        guard isAdmin else { Log.warning("رفض الطلب مرفوض: الصلاحية للمدير فقط"); return }
        optimisticRemove(from: &deceasedRequests, id: request.id, apiWork: { [weak self] in
            do {
                try await self?.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.rejected.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()
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
            Log.error("فشل جلب طلبات إضافة الأبناء: \(error)")
        }
    }

    func rejectChildAddRequest(request: AdminRequest) async {
        guard isAdmin else { Log.warning("رفض الطلب مرفوض: الصلاحية للمدير فقط"); return }
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

    // MARK: - Admin Add Son

    func adminAddSon(firstName: String, parent: FamilyMember?) async {
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
            let requestData: [String: AnyEncodable] = [
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
                kind: RequestType.phoneChange.rawValue
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
            let requestData: [String: AnyEncodable] = [
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
                kind: RequestType.nameChange.rawValue
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
            Log.error("فشل جلب طلبات تغيير الاسم: \(error)")
        }
    }

    func approveNameChangeRequest(request: AdminRequest) async {
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
                Log.info("[NameChange] تم قبول طلب تغيير الاسم → \(newName)")
            } catch {
                Log.error("[NameChange] فشل قبول طلب تغيير الاسم: \(error)")
            }
        }, refresh: { [weak self] in
            await self?.fetchNameChangeRequests(force: true)
            await self?.memberVM?.fetchAllMembers(force: true)
        })
    }

    func rejectNameChangeRequest(request: AdminRequest) async {
        guard isAdmin else { Log.warning("رفض الطلب مرفوض: الصلاحية للمدير فقط"); return }
        optimisticRemove(from: &nameChangeRequests, id: request.id, apiWork: { [weak self] in
            do {
                try await self?.supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.rejected.rawValue)])
                    .eq("id", value: request.id.uuidString)
                    .execute()

                await self?.notificationVM?.sendNotification(
                    title: L10n.t("لم يتم قبول طلبك", "Your Request Was Declined"),
                    body: L10n.t("طلب تغيير الاسم لم تتم الموافقة عليه", "Your name change request was not approved"),
                    targetMemberIds: [request.requesterId]
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
            Log.error("خطأ جلب طلبات تغيير الرقم: \(error.localizedDescription)")
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
            } catch {
                Log.error("خطأ اعتماد تغيير الرقم: \(error.localizedDescription)")
            }
        }, refresh: { [weak self] in
            await self?.fetchPhoneChangeRequests(force: true)
            await self?.memberVM?.fetchAllMembers(force: true)
        })
    }

    func rejectPhoneChangeRequest(request: PhoneChangeRequest) async {
        guard isAdmin else { Log.warning("رفض الطلب مرفوض: الصلاحية للمدير فقط"); return }

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
                        body: L10n.t("طلب تغيير رقم الهاتف لم تتم الموافقة عليه", "Your phone change request was not approved"),
                        targetMemberIds: [requesterId]
                    )
                }
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
        guard authVM?.canDeleteMembers == true else {
            Log.error("تم رفض حذف السجل: الصلاحية للمالك فقط")
            self.errorMessage = L10n.t("ليس لديك صلاحية لرفض الطلبات.", "You don't have permission to reject requests.")
            return
        }

        // حذف فوري محلياً — ثم API بالخلفية
        let deletedName = memberById(memberId)?.firstName ?? "عضو"
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
                        "تم حذف \(deletedName) من شجرة العائلة",
                        "\(deletedName) was removed from the family tree"
                    ),
                    kind: "admin"
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

    // MARK: - News Report Requests

    func fetchNewsReportRequests(force: Bool = false) async {
        guard throttler.canFetch(key: "newsReport", interval: 20, force: force) || newsReportRequests.isEmpty else { return }
        throttler.didFetch(key: "newsReport")
        guard canModerate else {
            newsReportRequests = []
            return
        }

        do {
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:profiles!member_id(*)")
                .eq("request_type", value: RequestType.newsReport.rawValue)
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .order("created_at", ascending: false)
                .execute()
                .value

            self.newsReportRequests = requests
        } catch {
            Log.error("خطأ جلب بلاغات الأخبار: \(error.localizedDescription)")
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
        guard isAdmin else { Log.warning("رفض الطلب مرفوض: الصلاحية للمدير فقط"); return }

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

            let basePayload: [String: AnyEncodable] = [
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
                kind: RequestType.photoSuggestion.rawValue
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
            Log.error("خطأ جلب اقتراحات الصور: \(error.localizedDescription)")
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
    func rejectPhotoSuggestion(request: AdminRequest) async {
        guard isAdmin else { Log.warning("رفض الطلب مرفوض: الصلاحية للمدير فقط"); return }

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
                Log.info("[PhotoSuggestion] تم رفض اقتراح الصورة")
            } catch {
                Log.error("[PhotoSuggestion] خطأ رفض اقتراح الصورة: \(error.localizedDescription)")
            }
        }, refresh: { [weak self] in
            await self?.fetchPhotoSuggestionRequests(force: true)
        })
    }
}
