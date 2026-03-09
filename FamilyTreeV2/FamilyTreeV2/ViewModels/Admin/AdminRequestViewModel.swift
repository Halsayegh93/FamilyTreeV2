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
    @Published var isLoading: Bool = false
    @Published var mergeResult: MergeResult? = nil
    
    enum MergeResult {
        case success(String)
        case failure(String)
    }

    // MARK: - Throttle Dates

    private var lastDeceasedFetchDate: Date?
    private var lastChildAddFetchDate: Date?
    private var lastPhoneChangeFetchDate: Date?
    private var lastNewsReportFetchDate: Date?
    private var lastTreeEditFetchDate: Date?

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

    /// حذف العنصر محلياً مع أنيميشن ثم تحديث من السيرفر بعد تأخير
    private func removeLocallyThenRefresh<T: Identifiable>(
        from array: inout [T],
        id: T.ID,
        refresh: @escaping () async -> Void
    ) {
        withAnimation(DS.Anim.snappy) {
            array.removeAll { $0.id as AnyHashable == id as AnyHashable }
        }
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refresh()
        }
    }

    private func schemaErrorDescription(_ error: Error) -> String {
        let raw = String(describing: error)
        return "\(raw) \(error.localizedDescription)".lowercased()
    }

    private func isMissingAdminRequestNewValueColumnError(_ error: Error) -> Bool {
        let desc = schemaErrorDescription(error)
        let mentionsNewValue = desc.contains("new_value")

        return (desc.contains("42703") && mentionsNewValue) ||
        (mentionsNewValue && (
            desc.contains("could not find") ||
            desc.contains("schema cache") ||
            desc.contains("pgrst")
        ))
    }

    /// Helper to get a safe member name for logging (uses member ID string)
    private func getSafeMemberName(for memberId: UUID) -> String {
        return memberId.uuidString
    }

    /// Lookup a member by ID from authVM's member cache
    private func memberById(_ id: UUID) -> FamilyMember? {
        return memberVM?.member(byId: id)
    }

    // MARK: - Tree Edit Requests

    /// إرسال طلب تعديل الشجرة (إضافة / تعديل اسم / حذف)
    func submitTreeEditRequest(actionType: String, memberName: String, details: String) async -> Bool {
        guard let user = currentUser else { return false }
        self.isLoading = true
        defer { self.isLoading = false }

        let cleanDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMemberName = memberName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMemberName.isEmpty else { return false }

        let fullDetails = """
        نوع التعديل: \(actionType)
        الاسم المعني: \(cleanMemberName)
        التفاصيل: \(cleanDetails.isEmpty ? "لا توجد تفاصيل إضافية" : cleanDetails)
        بواسطة: \(user.fullName)
        """

        do {
            let basePayload: [String: AnyEncodable] = [
                "member_id": AnyEncodable(user.id.uuidString),
                "requester_id": AnyEncodable(user.id.uuidString),
                "request_type": AnyEncodable("tree_edit"),
                "status": AnyEncodable("pending"),
                "details": AnyEncodable(fullDetails)
            ]

            do {
                var payload = basePayload
                payload["new_value"] = AnyEncodable(actionType)
                try await supabase.from("admin_requests").insert(payload).execute()
            } catch {
                if isMissingAdminRequestNewValueColumnError(error) {
                    try await supabase.from("admin_requests").insert(basePayload).execute()
                } else {
                    throw error
                }
            }

            let requesterName = user.firstName
            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("طلب تعديل الشجرة", "Tree Edit Request"),
                body: L10n.t(
                    "طلب \(actionType) من \(requesterName): \(cleanMemberName)",
                    "\(actionType) request from \(requesterName): \(cleanMemberName)"
                ),
                kind: "tree_edit"
            )

            Log.info("[TreeEdit] تم إرسال طلب تعديل الشجرة: \(actionType) — \(cleanMemberName)")
            return true
        } catch {
            Log.error("[TreeEdit] خطأ في إرسال طلب تعديل الشجرة: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Fetch / Approve / Reject Tree Edit Requests

    func fetchTreeEditRequests(force: Bool = false) async {
        if !force, let last = lastTreeEditFetchDate, Date().timeIntervalSince(last) < 20, !treeEditRequests.isEmpty { return }
        lastTreeEditFetchDate = Date()
        do {
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:profiles!member_id(*)")
                .eq("request_type", value: "tree_edit")
                .eq("status", value: "pending")
                .order("created_at", ascending: false)
                .execute()
                .value

            self.treeEditRequests = requests
        } catch {
            Log.error("فشل جلب طلبات تعديل الشجرة: \(error)")
        }
    }

    func approveTreeEditRequest(request: AdminRequest) async {
        do {
            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("approved")])
                .eq("id", value: request.id.uuidString)
                .execute()

            removeLocallyThenRefresh(from: &treeEditRequests, id: request.id) { [weak self] in
                await self?.fetchTreeEditRequests(force: true)
            }

            await notificationVM?.sendNotification(
                title: L10n.t("تم تنفيذ طلبك", "Request Completed"),
                body: L10n.t("تم قبول طلب تعديل الشجرة", "Your tree edit request was approved"),
                targetMemberIds: [request.requesterId]
            )

            Log.info("[TreeEdit] تم قبول طلب تعديل الشجرة")
        } catch {
            Log.error("[TreeEdit] فشل قبول طلب تعديل الشجرة: \(error)")
        }
    }

    func rejectTreeEditRequest(request: AdminRequest) async {
        do {
            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("rejected")])
                .eq("id", value: request.id.uuidString)
                .execute()

            removeLocallyThenRefresh(from: &treeEditRequests, id: request.id) { [weak self] in
                await self?.fetchTreeEditRequests(force: true)
            }
            Log.info("[TreeEdit] تم رفض طلب تعديل الشجرة")
        } catch {
            Log.error("[TreeEdit] فشل رفض طلب تعديل الشجرة: \(error)")
        }
    }

    // MARK: - Deceased Status Requests

    func requestDeceasedStatus(memberId: UUID, deathDate: Date?) async {
        self.isLoading = true
        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dateString = deathDate != nil ? formatter.string(from: deathDate!) : "غير محدد"

            let requestData: [String: AnyEncodable] = [
                "member_id": AnyEncodable(memberId.uuidString),
                "requester_id": AnyEncodable(currentUser?.id.uuidString ?? ""),
                "request_type": AnyEncodable("deceased_report"),
                "status": AnyEncodable("pending"),
                "details": AnyEncodable("طلب تأكيد وفاة بتاريخ: \(dateString)")
            ]

            try await supabase
                .from("admin_requests")
                .insert(requestData)
                .execute()

            let deceasedMemberName = memberById(memberId)?.firstName ?? "عضو"
            let requesterDeceasedName = currentUser?.firstName ?? "عضو"
            let deceasedBody = "طلب تأكيد وفاة: \(deceasedMemberName)\nتاريخ الوفاة: \(dateString)\nبواسطة: \(requesterDeceasedName)"
            await notificationVM?.notifyAdminsWithPush(
                title: "طلب تأكيد وفاة",
                body: deceasedBody,
                kind: "deceased_report"
            )

            Log.info("تم إرسال طلب تأكيد الوفاة للإدارة بنجاح")
        } catch {
            Log.error("خطأ في إرسال الطلب: \(error.localizedDescription)")
        }
        self.isLoading = false
    }

    func fetchDeceasedRequests(force: Bool = false) async {
        if !force, let last = lastDeceasedFetchDate, Date().timeIntervalSince(last) < 20, !deceasedRequests.isEmpty { return }
        lastDeceasedFetchDate = Date()
        do {
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:profiles!member_id(*)")
                .eq("request_type", value: "deceased_report")
                .eq("status", value: "pending")
                .execute()
                .value

            self.deceasedRequests = requests
        } catch {
            Log.error("فشل جلب طلبات الوفاة: \(error)")
        }
    }

    func approveDeceasedRequest(request: AdminRequest) async {
        do {
            try await supabase
                .from("profiles")
                .update(["is_deceased": AnyEncodable(true)])
                .eq("id", value: request.memberId.uuidString)
                .execute()

            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("approved")])
                .eq("id", value: request.id.uuidString)
                .execute()

            removeLocallyThenRefresh(from: &deceasedRequests, id: request.id) { [weak self] in
                await self?.fetchDeceasedRequests(force: true)
                await self?.memberVM?.fetchAllMembers(force: true)
            }

            await notificationVM?.sendNotification(
                title: L10n.t("تم تنفيذ طلبك", "Request Completed"),
                body: L10n.t("تم تأكيد حالة الوفاة", "Deceased status has been confirmed"),
                targetMemberIds: [request.requesterId]
            )

            Log.info("تم قبول الطلب وتحديث الشجرة بنجاح")
        } catch {
            Log.error("فشل في تنفيذ عملية الموافقة: \(error)")
        }
    }

    func rejectDeceasedRequest(request: AdminRequest) async {
        do {
            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("rejected")])
                .eq("id", value: request.id.uuidString)
                .execute()

            removeLocallyThenRefresh(from: &deceasedRequests, id: request.id) { [weak self] in
                await self?.fetchDeceasedRequests(force: true)
            }
            Log.info("تم رفض طلب تأكيد الوفاة")
        } catch {
            Log.error("فشل في رفض طلب الوفاة: \(error)")
        }
    }

    // MARK: - Child Add Requests

    func fetchChildAddRequests(force: Bool = false) async {
        if !force, let last = lastChildAddFetchDate, Date().timeIntervalSince(last) < 20, !childAddRequests.isEmpty { return }
        lastChildAddFetchDate = Date()
        do {
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:profiles!member_id(*)")
                .eq("request_type", value: "child_add")
                .eq("status", value: "pending")
                .execute()
                .value

            self.childAddRequests = requests
        } catch {
            Log.error("فشل جلب طلبات إضافة الأبناء: \(error)")
        }
    }

    func rejectChildAddRequest(request: AdminRequest) async {
        do {
            if let childId = request.newValue {
                try await supabase
                    .from("profiles")
                    .delete()
                    .eq("id", value: childId)
                    .execute()
            }

            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("rejected")])
                .eq("id", value: request.id.uuidString)
                .execute()

            removeLocallyThenRefresh(from: &childAddRequests, id: request.id) { [weak self] in
                await self?.fetchChildAddRequests(force: true)
                await self?.memberVM?.fetchAllMembers(force: true)
            }

            Log.info("تم رفض طلب إضافة الابن وحذفه من الشجرة")
        } catch {
            Log.error("فشل رفض طلب إضافة الابن: \(error)")
        }
    }

    func acknowledgeChildAddRequest(request: AdminRequest) async {
        do {
            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("approved")])
                .eq("id", value: request.id.uuidString)
                .execute()

            removeLocallyThenRefresh(from: &childAddRequests, id: request.id) { [weak self] in
                await self?.fetchChildAddRequests(force: true)
            }

            await notificationVM?.sendNotification(
                title: L10n.t("تم تنفيذ طلبك", "Request Completed"),
                body: L10n.t("تم قبول طلب إضافة الابن", "Your child add request was approved"),
                targetMemberIds: [request.requesterId]
            )

            Log.info("تم تأكيد طلب إضافة الابن بنجاح")
        } catch {
            Log.error("فشل تأكيد طلب إضافة الابن: \(error)")
        }
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
                    .update(["status": AnyEncodable("approved")])
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
                    .update(["status": AnyEncodable("approved")])
                    .eq("member_id", value: memberId.uuidString)
                    .eq("request_type", value: "join_request")
                    .eq("status", value: "pending")
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
                "request_type": AnyEncodable("phone_change"),
                "new_value": AnyEncodable(normalizedPhone),
                "status": AnyEncodable("pending"),
                "details": AnyEncodable("طلب تغيير رقم الجوال")
            ]

            try await supabase
                .from("admin_requests")
                .insert(requestData)
                .execute()

            let phoneRequesterName = currentUser?.firstName ?? "عضو"
            let phoneChangeBody = "طلب تغيير رقم جوال\nالعضو: \(phoneRequesterName)\nالرقم الجديد: \(KuwaitPhone.display(normalizedPhone))"
            await notificationVM?.notifyAdminsWithPush(
                title: "طلب تغيير رقم جوال",
                body: phoneChangeBody,
                kind: "phone_change"
            )

            Log.info("تم إرسال طلب تغيير الرقم للإدارة: \(normalizedPhone)")
        } catch {
            Log.error("خطأ في إرسال طلب التغيير: \(error.localizedDescription)")
        }
        self.isLoading = false
    }

    func fetchPhoneChangeRequests(force: Bool = false) async {
        if !force, let last = lastPhoneChangeFetchDate, Date().timeIntervalSince(last) < 20, !phoneChangeRequests.isEmpty { return }
        lastPhoneChangeFetchDate = Date()
        guard canModerate else {
            phoneChangeRequests = []
            return
        }

        do {
            let requests: [PhoneChangeRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:profiles!member_id(*)")
                .eq("request_type", value: "phone_change")
                .eq("status", value: "pending")
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

        do {
            try await supabase
                .from("profiles")
                .update(["phone_number": AnyEncodable(newPhone)])
                .eq("id", value: request.memberId.uuidString)
                .execute()

            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("approved")])
                .eq("id", value: request.id.uuidString)
                .execute()

            removeLocallyThenRefresh(from: &phoneChangeRequests, id: request.id) { [weak self] in
                await self?.fetchPhoneChangeRequests(force: true)
                await self?.memberVM?.fetchAllMembers(force: true)
            }

            if let requesterId = request.requesterId {
                await notificationVM?.sendNotification(
                    title: L10n.t("تم تنفيذ طلبك", "Request Completed"),
                    body: L10n.t("تم اعتماد تغيير رقم الجوال", "Your phone change request was approved"),
                    targetMemberIds: [requesterId]
                )
            }
        } catch {
            Log.error("خطأ اعتماد تغيير الرقم: \(error.localizedDescription)")
        }
    }

    func rejectPhoneChangeRequest(request: PhoneChangeRequest) async {
        guard canModerate else { return }

        do {
            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("rejected")])
                .eq("id", value: request.id.uuidString)
                .execute()

            removeLocallyThenRefresh(from: &phoneChangeRequests, id: request.id) { [weak self] in
                await self?.fetchPhoneChangeRequests(force: true)
            }
        } catch {
            Log.error("خطأ رفض تغيير الرقم: \(error.localizedDescription)")
        }
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
            await notificationVM?.notifyAdmins(
                title: "تفعيل حساب",
                body: "تم تفعيل حساب \(memberName).",
                kind: "admin"
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
                .update(["status": AnyEncodable("approved")])
                .eq("member_id", value: memberId.uuidString)
                .in("request_type", values: ["join_request", "link_request"])
                .eq("status", value: "pending")
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
        Log.info("[MERGE] ==============================")
        Log.info("[MERGE] بدء الدمج:")
        Log.info("[MERGE]   العضو الجديد (يبقى): \(newMemberId)")
        Log.info("[MERGE]   عضو الشجرة (يُحذف): \(existingTreeMemberId)")
        Log.info("[MERGE] ==============================")
        self.isLoading = true
        do {
            // 0) التحقق من وجود سجل العضو الجديد أولاً
            let newMemberResponse = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: newMemberId.uuidString)
                .limit(1)
                .execute()
            let newMembers = try JSONDecoder().decode([FamilyMember].self, from: newMemberResponse.data)
            guard let newMember = newMembers.first else {
                Log.error("[MERGE] ❌ سجل العضو الجديد غير موجود! UUID: \(newMemberId)")
                self.mergeResult = .failure(L10n.t(
                    "سجل العضو الجديد غير موجود في قاعدة البيانات.",
                    "New member record not found in database."
                ))
                self.isLoading = false
                return
            }
            Log.info("[MERGE] سجل العضو الجديد موجود: \(newMember.fullName), role=\(newMember.role), phone=\(newMember.phoneNumber ?? "nil")")
            
            // 1) Load the existing tree record to get tree data
            let treeResponse = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: existingTreeMemberId.uuidString)
                .limit(1)
                .execute()
            
            let treeMembers = try JSONDecoder().decode([FamilyMember].self, from: treeResponse.data)
            guard let treeMember = treeMembers.first else {
                Log.error("[MERGE] ❌ سجل الشجرة غير موجود! UUID: \(existingTreeMemberId)")
                self.mergeResult = .failure(L10n.t(
                    "سجل عضو الشجرة غير موجود في قاعدة البيانات.",
                    "Tree member record not found in database."
                ))
                self.isLoading = false
                return
            }
            
            // 2) Update the new registration record with tree data from old record
            var updatePayload: [String: AnyEncodable] = [
                "role": AnyEncodable("member"),
                "status": AnyEncodable("active"),
                "is_hidden_from_tree": AnyEncodable(false),
                "full_name": AnyEncodable(treeMember.fullName),
                "first_name": AnyEncodable(treeMember.firstName),
                "father_id": AnyEncodable(treeMember.fatherId?.uuidString),
                "sort_order": AnyEncodable(treeMember.sortOrder),
                "is_deceased": AnyEncodable(treeMember.isDeceased ?? false),
                "is_married": AnyEncodable(treeMember.isMarried ?? false)
            ]
            
            // Transfer avatar/cover/photo from tree record if exists
            if let avatarUrl = treeMember.avatarUrl, !avatarUrl.isEmpty {
                updatePayload["avatar_url"] = AnyEncodable(avatarUrl)
            }
            if let coverUrl = treeMember.coverUrl, !coverUrl.isEmpty {
                updatePayload["cover_url"] = AnyEncodable(coverUrl)
            }
            if let photoURL = treeMember.photoURL, !photoURL.isEmpty {
                updatePayload["photo_url"] = AnyEncodable(photoURL)
            }
            
            // Transfer bio if exists
            if let bio = treeMember.bio, !bio.isEmpty {
                updatePayload["bio"] = AnyEncodable(bio)
            }
            
            // Transfer death date if exists
            if let deathDate = treeMember.deathDate, !deathDate.isEmpty {
                updatePayload["death_date"] = AnyEncodable(deathDate)
            }
            
            try await supabase
                .from("profiles")
                .update(updatePayload)
                .eq("id", value: newMemberId.uuidString)
                .execute()
            Log.info("[MERGE] تم إرسال تحديث السجل الجديد")
            
            // التحقق من نجاح التحديث فعلياً (RLS قد يمنع التحديث بصمت)
            let verifyResponse = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: newMemberId.uuidString)
                .limit(1)
                .execute()
            let verifyMembers = try JSONDecoder().decode([FamilyMember].self, from: verifyResponse.data)
            if let verified = verifyMembers.first {
                if verified.role == .member && verified.status == .active {
                    Log.info("[MERGE] ✅ التحقق ناجح: role=\(verified.role), status=\(verified.status ?? .active), name=\(verified.fullName)")
                } else {
                    Log.error("[MERGE] ⚠️ التحديث لم يُطبق! role=\(verified.role), status=\(verified.status ?? .pending). قد يكون RLS يمنع التحديث.")
                    self.mergeResult = .failure(L10n.t(
                        "فشل تحديث حالة العضو. تحقق من صلاحيات قاعدة البيانات (RLS).",
                        "Failed to update member status. Check database permissions (RLS)."
                    ))
                    self.isLoading = false
                    return
                }
            }
            
            // 3) Re-link children: change their father_id from old to new
            _ = try? await supabase
                .from("profiles")
                .update(["father_id": AnyEncodable(newMemberId.uuidString)])
                .eq("father_id", value: existingTreeMemberId.uuidString)
                .execute()
            
            // 4) Transfer gallery photos from old to new
            _ = try? await supabase
                .from("member_gallery_photos")
                .update(["member_id": AnyEncodable(newMemberId.uuidString)])
                .eq("member_id", value: existingTreeMemberId.uuidString)
                .execute()
            
            // 5) Transfer notifications from old to new
            _ = try? await supabase
                .from("notifications")
                .update(["target_member_id": AnyEncodable(newMemberId.uuidString)])
                .eq("target_member_id", value: existingTreeMemberId.uuidString)
                .execute()
            
            // 6) Approve pending admin requests for new member
            _ = try? await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("approved")])
                .eq("member_id", value: newMemberId.uuidString)
                .in("request_type", values: ["join_request", "link_request"])
                .eq("status", value: "pending")
                .execute()
            
            // 7) Clean up admin_requests referencing old record
            _ = try? await supabase
                .from("admin_requests")
                .delete()
                .eq("member_id", value: existingTreeMemberId.uuidString)
                .execute()
            _ = try? await supabase
                .from("admin_requests")
                .delete()
                .eq("requester_id", value: existingTreeMemberId.uuidString)
                .execute()
            
            // 8) Transfer device tokens from old to new
            _ = try? await supabase
                .from("device_tokens")
                .update(["member_id": AnyEncodable(newMemberId.uuidString)])
                .eq("member_id", value: existingTreeMemberId.uuidString)
                .execute()
            
            // 9) Delete the old tree record (مع حماية ضد حذف السجل الخطأ)
            guard existingTreeMemberId != newMemberId else {
                Log.error("[MERGE] ❌ محاولة حذف نفس السجل المراد الاحتفاظ به! تم الإيقاف.")
                self.mergeResult = .failure(L10n.t(
                    "خطأ: لا يمكن دمج العضو مع نفسه.",
                    "Error: Cannot merge a member with itself."
                ))
                self.isLoading = false
                return
            }
            do {
                Log.info("[MERGE] حذف السجل القديم: \(existingTreeMemberId) (العضو المحفوظ: \(newMemberId))")
                try await supabase
                    .from("profiles")
                    .delete()
                    .eq("id", value: existingTreeMemberId.uuidString)
                    .execute()
                Log.info("[MERGE] ✅ تم حذف السجل القديم بنجاح")
            } catch {
                Log.error("[MERGE] فشل حذف السجل القديم: \(error.localizedDescription)")
                // حتى لو فشل الحذف، السجل الجديد اتحدث بنجاح
            }
            
            // 10) التحقق النهائي: السجل الجديد لا يزال موجوداً بعد الحذف
            let finalCheck = try? await supabase
                .from("profiles")
                .select("id, role, status, full_name")
                .eq("id", value: newMemberId.uuidString)
                .limit(1)
                .execute()
            if let checkData = finalCheck?.data,
               let checkMembers = try? JSONDecoder().decode([FamilyMember].self, from: checkData),
               let final = checkMembers.first {
                Log.info("[MERGE] ✅ التحقق النهائي: السجل موجود — \(final.fullName), role=\(final.role), status=\(final.status?.rawValue ?? "nil")")
            } else {
                Log.error("[MERGE] ❌ التحقق النهائي: السجل الجديد اختفى بعد الحذف! UUID: \(newMemberId)")
            }
            
            // 11) Refresh local data
            await memberVM?.fetchAllMembers()
            
            // 11) Notify the member
            await notifyJoinApproval(memberId: newMemberId, fatherName: treeMember.fatherId.flatMap { id in memberById(id)?.fullName })
            
            Log.info("[MERGE] تم دمج العضو بنجاح: \(treeMember.fullName) → auth UUID: \(newMemberId)")
            self.mergeResult = .success(L10n.t(
                "تم دمج \(treeMember.fullName) بنجاح وتفعيل حسابه.",
                "Successfully merged \(treeMember.fullName) and activated their account."
            ))
        } catch {
            Log.error("[MERGE] فشل دمج العضو: \(error.localizedDescription)")
            self.mergeResult = .failure(L10n.t(
                "حدث خطأ أثناء الدمج: \(error.localizedDescription)",
                "Error during merge: \(error.localizedDescription)"
            ))
        }
        self.isLoading = false
    }

    private func notifyJoinApproval(memberId: UUID, fatherName: String?) async {
        guard let creator = currentUser?.id else { return }

        let body: String
        if let fatherName, !fatherName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body = "تم قبول طلب انضمامك وربطك مع: \(fatherName)."
        } else {
            body = "تم قبول طلب انضمامك بنجاح."
        }

        let title = "تم اعتماد العضوية"

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
            // Notify admins and supervisors about the new member
            let memberName = getSafeMemberName(for: memberId)
            await notificationVM?.notifyAdmins(
                title: "انضمام عضو جديد",
                body: "تم انضمام \(memberName) للعائلة.",
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
                .eq("request_type", value: "link_request")
                .eq("status", value: "pending")
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
        guard currentUser?.role == .admin else {
            Log.error("تم رفض حذف السجل: الصلاحية للمدير فقط")
            return
        }
        do {
            // 1) Unlink children from this member before deletion (avoid father_id FK constraints)
            _ = try? await supabase
                .from("profiles")
                .update(["father_id": AnyEncodable(Optional<String>.none)])
                .eq("father_id", value: memberId.uuidString)
                .execute()

            // 2) Clean up any requests associated with this member (avoid FK on admin_requests)
            _ = try? await supabase
                .from("admin_requests")
                .delete()
                .eq("member_id", value: memberId.uuidString)
                .execute()

            _ = try? await supabase
                .from("admin_requests")
                .delete()
                .eq("requester_id", value: memberId.uuidString)
                .execute()

            // 3) Delete from profiles
            try await supabase
                .from("profiles")
                .delete()
                .eq("id", value: memberId.uuidString)
                .execute()

            // 4) Immediate local update to hide from UI
            let deletedName = memberById(memberId)?.firstName ?? "عضو"
            memberVM?.allMembers.removeAll(where: { $0.id == memberId })
            memberVM?.currentMemberChildren.removeAll(where: { $0.id == memberId })
            memberVM?.objectWillChange.send()

            await notificationVM?.notifyAdmins(
                title: "حذف عضو",
                body: "تم حذف \(deletedName) من الشجرة.",
                kind: "admin"
            )

            Log.info("تم حذف العضو مع تنظيف المراجع المرتبطة بنجاح")

        } catch {
            Log.error("خطأ في الحذف: \(error.localizedDescription)")
        }
    }

    // MARK: - News Report Requests

    func fetchNewsReportRequests(force: Bool = false) async {
        if !force, let last = lastNewsReportFetchDate, Date().timeIntervalSince(last) < 20, !newsReportRequests.isEmpty { return }
        lastNewsReportFetchDate = Date()
        guard canModerate else {
            newsReportRequests = []
            return
        }

        do {
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:profiles!member_id(*)")
                .eq("request_type", value: "news_report")
                .eq("status", value: "pending")
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

        do {
            if let postIdRaw = request.newValue, let postId = UUID(uuidString: postIdRaw) {
                try await supabase
                    .from("news")
                    .delete()
                    .eq("id", value: postId.uuidString)
                    .execute()
            }

            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("approved")])
                .eq("id", value: request.id.uuidString)
                .execute()

            removeLocallyThenRefresh(from: &newsReportRequests, id: request.id) { [weak self] in
                await self?.fetchNewsReportRequests(force: true)
                await self?.newsVM?.fetchNews(force: true)
            }

            await notificationVM?.sendNotification(
                title: L10n.t("تم تنفيذ طلبك", "Request Completed"),
                body: L10n.t("تمت مراجعة بلاغك واتخاذ الإجراء المناسب", "Your report was reviewed and action was taken"),
                targetMemberIds: [request.requesterId]
            )
        } catch {
            Log.error("خطأ اعتماد بلاغ الخبر: \(error.localizedDescription)")
        }
    }

    func rejectNewsReport(request: AdminRequest) async {
        guard canModerate else { return }

        do {
            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("rejected")])
                .eq("id", value: request.id.uuidString)
                .execute()

            removeLocallyThenRefresh(from: &newsReportRequests, id: request.id) { [weak self] in
                await self?.fetchNewsReportRequests(force: true)
            }
        } catch {
            Log.error("خطأ رفض بلاغ الخبر: \(error.localizedDescription)")
        }
    }

    // MARK: - Photo Suggestion Requests

    @Published var photoSuggestionRequests: [AdminRequest] = []
    private var lastPhotoSuggestionFetchDate: Date?

    /// إرسال اقتراح صورة لعضو — يرفع الصورة كملف مؤقت ويسجل طلب إداري
    func submitPhotoSuggestion(image: UIImage, for memberId: UUID) async -> Bool {
        guard let user = currentUser else { return false }
        self.isLoading = true
        defer { self.isLoading = false }

        guard let imageData = image.jpegData(compressionQuality: 0.5) else { return false }

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
            let requesterName = user.firstName

            let basePayload: [String: AnyEncodable] = [
                "member_id": AnyEncodable(memberId.uuidString),
                "requester_id": AnyEncodable(user.id.uuidString),
                "request_type": AnyEncodable("photo_suggestion"),
                "status": AnyEncodable("pending"),
                "details": AnyEncodable("اقتراح صورة لـ \(memberName) بواسطة \(requesterName)")
            ]

            // محاولة إرسال مع new_value
            do {
                var payload = basePayload
                payload["new_value"] = AnyEncodable(urlString)
                try await supabase.from("admin_requests").insert(payload).execute()
            } catch {
                if isMissingAdminRequestNewValueColumnError(error) {
                    try await supabase.from("admin_requests").insert(basePayload).execute()
                } else {
                    throw error
                }
            }

            // 3. إشعار المدراء
            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("اقتراح صورة", "Photo Suggestion"),
                body: L10n.t(
                    "اقترح \(requesterName) صورة لـ \(memberName)",
                    "\(requesterName) suggested a photo for \(memberName)"
                ),
                kind: "photo_suggestion"
            )

            Log.info("[PhotoSuggestion] تم إرسال اقتراح صورة لـ \(memberName)")
            return true
        } catch {
            Log.error("[PhotoSuggestion] خطأ في إرسال اقتراح الصورة: \(error.localizedDescription)")
            return false
        }
    }

    func fetchPhotoSuggestionRequests(force: Bool = false) async {
        if !force, let last = lastPhotoSuggestionFetchDate, Date().timeIntervalSince(last) < 20, !photoSuggestionRequests.isEmpty { return }
        lastPhotoSuggestionFetchDate = Date()

        do {
            let requests: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:profiles!member_id(*)")
                .eq("request_type", value: "photo_suggestion")
                .eq("status", value: "pending")
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

        do {
            let timestamp = Int(Date().timeIntervalSince1970)
            let urlWithCache = photoUrl.contains("?") ? "\(photoUrl)&v=\(timestamp)" : "\(photoUrl)?v=\(timestamp)"

            try await supabase
                .from("profiles")
                .update(["avatar_url": AnyEncodable(urlWithCache)])
                .eq("id", value: request.memberId.uuidString)
                .execute()

            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("approved")])
                .eq("id", value: request.id.uuidString)
                .execute()

            removeLocallyThenRefresh(from: &photoSuggestionRequests, id: request.id) { [weak self] in
                await self?.fetchPhotoSuggestionRequests(force: true)
                await self?.memberVM?.fetchAllMembers(force: true)
            }

            await notificationVM?.sendNotification(
                title: L10n.t("تم تنفيذ طلبك", "Request Completed"),
                body: L10n.t("تم قبول الصورة المقترحة", "Your photo suggestion was approved"),
                targetMemberIds: [request.requesterId]
            )

            Log.info("[PhotoSuggestion] تم قبول اقتراح الصورة وتحديث الملف الشخصي")
        } catch {
            Log.error("[PhotoSuggestion] خطأ قبول اقتراح الصورة: \(error.localizedDescription)")
        }
    }

    /// رفض اقتراح صورة — حذف الصورة من التخزين
    func rejectPhotoSuggestion(request: AdminRequest) async {
        guard canModerate else { return }

        do {
            if let photoUrl = request.newValue,
               let url = URL(string: photoUrl),
               let range = url.path.range(of: "/storage/v1/object/public/avatars/") {
                let storagePath = String(url.path[range.upperBound...])
                _ = try? await supabase.storage
                    .from("avatars")
                    .remove(paths: [storagePath])
            }

            try await supabase
                .from("admin_requests")
                .update(["status": AnyEncodable("rejected")])
                .eq("id", value: request.id.uuidString)
                .execute()

            removeLocallyThenRefresh(from: &photoSuggestionRequests, id: request.id) { [weak self] in
                await self?.fetchPhotoSuggestionRequests(force: true)
            }

            Log.info("[PhotoSuggestion] تم رفض اقتراح الصورة")
        } catch {
            Log.error("[PhotoSuggestion] خطأ رفض اقتراح الصورة: \(error.localizedDescription)")
        }
    }
}
