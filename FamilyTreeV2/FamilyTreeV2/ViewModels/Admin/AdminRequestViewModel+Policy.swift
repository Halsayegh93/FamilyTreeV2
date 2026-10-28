import Foundation
import Supabase
import SwiftUI

// MARK: - سياسة الخصوصية والشروط (٢٠٢٦-١٠-٢٨): حذف الحساب بطلب، طلبات الخصوصية، موافقة ولي الأمر
//
// السيرفر هو الحَكَم: `delete-account` (بمعرّف الطلب) و`reject_account_deletion` للمالك/المدير،
// و`decide_privacy_request` للمالك/المدير/المراقب، ورفض ربط/تفعيل القاصر بلا موافقة ولي أمره.

/// تلميحات السيرفر لموافقة ولي الأمر
enum GuardianConsent {
    static let requiredHint = "guardian_consent_required"
    static let under13Hint = "under_13"
}

/// تفاصيل طلب الخصوصية (`details` نص JSON: {kind, note, prev_hidden})
nonisolated struct PrivacyRequestDetails: Decodable, Sendable {
    let kind: String?
    let note: String?

    static func parse(_ details: String?) -> PrivacyRequestDetails? {
        guard let data = details?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PrivacyRequestDetails.self, from: data)
    }

    var kindTitle: String {
        TreeDataRequestKind(rawValue: kind ?? "")?.shortTitle ?? L10n.t("طلب خصوصية", "Privacy request")
    }
}

/// تفاصيل «إضافة قريبة» (`details` نص JSON: {v, rpc, args, kind, name, requester_id, summary})
nonisolated struct RelativeAddDetails: Decodable, Sendable {
    let kind: String?
    let name: String?
    let summary: String?

    static func parse(_ details: String?) -> RelativeAddDetails? {
        guard let data = details?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RelativeAddDetails.self, from: data)
    }

    /// «إضافة زوجة: …» من السيرفر، وإلا من النوع والاسم
    var summaryText: String {
        if let s = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        let kindText: String
        switch kind {
        case "wife": kindText = L10n.t("إضافة زوجة", "Add wife")
        case "mother": kindText = L10n.t("إضافة أم", "Add mother")
        case "sister": kindText = L10n.t("إضافة أخت", "Add sister")
        default: kindText = L10n.t("إضافة قريبة", "Add relative")
        }
        guard let n = name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty else { return kindText }
        return "\(kindText): \(n)"
    }
}

/// صف يُتجاوز إن لم يُقرأ — نوع جديد أو عمود ناقص لا يُسقط القائمة كلها
private nonisolated struct LossyAdminRequest: Decodable, Sendable {
    let value: AdminRequest?
    init(from decoder: Decoder) throws { value = try? AdminRequest(from: decoder) }
}

extension AdminRequestViewModel {

    /// رفض السيرفر لربط/تفعيل قاصر: «يحتاج موافقة ولي الأمر» → مربّع طلب الموافقة، و«دون ١٣» → رسالة خطأ.
    /// true = عولج هنا (لا رسالة عامة بعده)
    func handleGuardianRefusal(_ error: Error, minorId: UUID, treeMemberId: UUID) -> Bool {
        guard let pg = error as? PostgrestError else { return false }
        switch pg.hint {
        case GuardianConsent.requiredHint:
            GuardianConsentPresenter.offer(minorId: minorId, treeMemberId: treeMemberId, message: pg.message)
            return true
        case GuardianConsent.under13Hint:
            errorMessage = AuthViewModel.serverMessage(error, fallback: L10n.t(
                "لا يمكن تفعيل حساب لمن هم دون الثالثة عشرة.",
                "Accounts can't be activated for children under 13."))
            return true
        default:
            return false
        }
    }

    /// مجال الدور: حذف الحساب للمالك/المدير، والخصوصية لهما وللمراقب
    var canHandleAccountDeletion: Bool { authVM?.isAdmin ?? false }
    var canHandlePrivacyRequests: Bool {
        (authVM?.isAdmin ?? false) || authVM?.currentUser?.role == .monitor
    }

    /// «إضافة قريبة»: مجال طلبات الشجرة (المالك/المدير/المراقب — `can_handle_admin_request`)
    var canHandleRelativeAdd: Bool { canHandlePrivacyRequests }

    /// عدد طلبات السياسة الظاهرة في «الوارد»
    var policyRequestsCount: Int { accountDeleteRequests.count + privacyRequests.count + relativeAddRequests.count }

    func fetchPolicyRequests() async {
        var types: [String] = []
        if canHandleAccountDeletion { types.append(RequestType.accountDelete.rawValue) }
        if canHandlePrivacyRequests { types.append(RequestType.privacyRequest.rawValue) }
        if canHandleRelativeAdd { types.append(RequestType.relativeAdd.rawValue) }
        guard !types.isEmpty else {
            accountDeleteRequests = []
            privacyRequests = []
            relativeAddRequests = []
            return
        }
        do {
            let rows: [LossyAdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:members_masked!member_id(*)")
                .in("request_type", values: types)
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .order("created_at", ascending: true)
                .execute()
                .value
            let all = rows.compactMap(\.value)
            accountDeleteRequests = all.filter { $0.requestType == RequestType.accountDelete.rawValue }
            privacyRequests = all.filter { $0.requestType == RequestType.privacyRequest.rawValue }
            relativeAddRequests = all.filter { $0.requestType == RequestType.relativeAdd.rawValue }
        } catch {
            Log.fetchError("فشل جلب طلبات الحذف والخصوصية", error)
        }
    }

    // MARK: حذف الحساب

    /// تنفيذ الحذف النهائي عبر `delete-account` — true = نجح وأُزيل الصف
    func approveAccountDeletion(_ request: AdminRequest) async -> Bool {
        guard canHandleAccountDeletion, NetworkMonitor.shared.requireOnline() else { return false }
        isLoading = true
        defer { isLoading = false }
        nonisolated struct Response: Decodable { let ok: Bool? }
        do {
            let response: Response = try await supabase.functions.invoke(
                "delete-account",
                options: FunctionInvokeOptions(body: ["request_id": request.id.uuidString])
            )
            guard response.ok == true else { throw NSError(domain: "AccountDeletion", code: 1) }
            accountDeleteRequests.removeAll { $0.id == request.id }
            Task { await memberVM?.fetchAllMembers(force: true) }
            return true
        } catch let FunctionsError.httpError(code, data) {
            Log.error("[AccountDeletion] رفض السيرفر (\(code))")
            errorMessage = Self.functionMessage(data) ?? Self.deletionFailedMessage
            return false
        } catch {
            Log.error("[AccountDeletion] فشل الحذف: \(error.localizedDescription)")
            errorMessage = Self.deletionFailedMessage
            return false
        }
    }

    func rejectAccountDeletion(_ request: AdminRequest, reason: String?) async -> Bool {
        guard canHandleAccountDeletion, NetworkMonitor.shared.requireOnline() else { return false }
        nonisolated struct Params: Encodable { let p_request_id: String; let p_reason: String? }
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await supabase.rpc("reject_account_deletion",
                                       params: Params(p_request_id: request.id.uuidString, p_reason: Self.clean(reason)))
                .execute()
            accountDeleteRequests.removeAll { $0.id == request.id }
            return true
        } catch {
            Log.error("[AccountDeletion] فشل الرفض: \(error.localizedDescription)")
            errorMessage = AuthViewModel.serverMessage(error, fallback: L10n.t(
                "تعذّر رفض الطلب. حاول مرة أخرى.", "Couldn't reject the request. Please try again."))
            return false
        }
    }

    // MARK: «إضافة قريبة»

    /// قبول/رفض «إضافة قريبة» عبر `decide_admin_request` (القبول يُنشئ العقدة ويرجع `new_member_id`)
    func decideRelativeAdd(_ request: AdminRequest, approve: Bool, reason: String?) async -> Bool {
        guard canHandleRelativeAdd, NetworkMonitor.shared.requireOnline() else { return false }
        isLoading = true
        defer { isLoading = false }
        // الخطأ (ومنه `requester_gone`) في `errorMessage` من `decideOnServer`
        guard await decideOnServer(request.id, approve: approve, reason: reason) != nil else { return false }
        relativeAddRequests.removeAll { $0.id == request.id }
        if approve { _ = try? await WomenStore.fetch() }
        return true
    }

    // MARK: طلبات الخصوصية

    func decidePrivacyRequest(_ request: AdminRequest, approve: Bool, reason: String?) async -> Bool {
        guard canHandlePrivacyRequests, NetworkMonitor.shared.requireOnline() else { return false }
        nonisolated struct Params: Encodable { let p_request_id: String; let p_approve: Bool; let p_reason: String? }
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await supabase.rpc("decide_privacy_request",
                                       params: Params(p_request_id: request.id.uuidString, p_approve: approve,
                                                      p_reason: Self.clean(reason)))
                .execute()
            privacyRequests.removeAll { $0.id == request.id }
            Task { await memberVM?.fetchAllMembers(force: true) }
            return true
        } catch {
            Log.error("[Privacy] فشل القرار: \(error.localizedDescription)")
            errorMessage = AuthViewModel.serverMessage(error, fallback: L10n.t(
                "تعذّر تنفيذ القرار. حاول مرة أخرى.", "Couldn't apply the decision. Please try again."))
            return false
        }
    }

    // MARK: مساعدات

    private static var deletionFailedMessage: String {
        L10n.t("لم يكتمل حذف الحساب. حاول مرة أخرى.", "The account deletion didn't complete. Please try again.")
    }

    private static func clean(_ text: String?) -> String? {
        let t = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    /// رسالة الدالة الطرفية ({error} أو {message}) إن كانت عربية
    static func functionMessage(_ data: Data) -> String? {
        nonisolated struct Body: Decodable { let error: String?; let message: String? }
        guard L10n.isArabic, let body = try? JSONDecoder().decode(Body.self, from: data),
              let text = body.message ?? body.error,
              text.range(of: "\\p{Arabic}", options: .regularExpression) != nil else { return nil }
        return text
    }
}
