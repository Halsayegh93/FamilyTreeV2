import Foundation
import Supabase

// MARK: - مربّع تفاصيل الإشعار (التصميم الغني ٢٠٢٦-١١-٠١، موافقة المالك)
//
// المربّع يقرأ طلب `admin_requests` المذكور في الإشعار (`request_id`) ليعرض «رحلة الطلب» للعضو أو تفاصيله وقراره
// للإدارة. القرار من المربّع = **نفس دوال القبول/الرفض الموجودة** لكل نوع (الشاشة وزرّ الإشعار الخارجي) — لا منطق جديد،
// ومسار الموافقات يبقى في «الوارد» (المربّع يعرض «فتح الطلب كامل» فقط حين يكون الطلب داخل المسار).

extension AdminRequestViewModel {
    /// طلب واحد بمعرّفه (أي حالة) — العضو يقرأ طلباته هو فقط (RLS: requester_id)، والإدارة بمجالها
    func fetchRequest(id: UUID) async -> AdminRequest? {
        do {
            let rows: [AdminRequest] = try await supabase
                .from("admin_requests")
                .select("*, member:members_masked!member_id(*)")
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            Log.warning("[NotifBox] تعذّر جلب الطلب \(id.uuidString.prefix(8)): \(error.localizedDescription)")
            return nil
        }
    }

    /// أنواع يقبلها/يرفضها المربّع بدوالها الموجودة (`approveFromPush` + دالة الرفض لكل نوع)
    private static let boxDecidableTypes: Set<String> = [
        RequestType.treeEdit.rawValue, RequestType.deceasedReport.rawValue, RequestType.nameChange.rawValue,
        RequestType.photoSuggestion.rawValue, RequestType.newsReport.rawValue,
    ]

    private func boxAllowed(_ request: AdminRequest) -> Bool {
        guard request.status == ApprovalStatus.pending.rawValue,
              Self.boxDecidableTypes.contains(request.requestType) else { return false }
        // داخل «مسار الموافقات» — القرار من «الوارد» بمراحله
        if approvalsWorkflowOn || request.stage != nil { return false }
        // طلبك أنت يعالجه غيرك (إلا المالك)
        if let me = authVM?.currentUser?.id, authVM?.currentUser?.role != .owner,
           request.requesterId == me || request.memberId == me { return false }
        return true
    }

    private func isContentType(_ request: AdminRequest) -> Bool {
        request.requestType == RequestType.newsReport.rawValue
    }

    /// يظهر «موافقة» في المربّع — نفس صلاحيات `approveFromPush`
    func canApproveFromBox(_ request: AdminRequest) -> Bool {
        guard boxAllowed(request) else { return false }
        return isContentType(request) ? (authVM?.canModerateContent ?? false)
                                      : (authVM?.canApproveTreeRequests ?? false)
    }

    /// يظهر «رفض» — نفس صلاحيات الرفض في «الوارد» (`canReject`)
    func canRejectFromBox(_ request: AdminRequest) -> Bool {
        guard boxAllowed(request) else { return false }
        return isContentType(request) ? (authVM?.canModerateContent ?? false)
                                      : (authVM?.canRejectRequests ?? false)
    }

    /// القبول = `approveFromPush` نفسه (يعيد فحص المسار والصلاحية ويستدعي دالة النوع)
    func approveFromBox(_ request: AdminRequest) async -> Bool {
        guard canApproveFromBox(request) else { return false }
        return await approveFromPush(requestId: request.id, requestType: request.requestType)
    }

    /// الرفض = دالة الرفض الموجودة لكل نوع
    func rejectFromBox(_ request: AdminRequest, reason: String?) async {
        guard canRejectFromBox(request) else { return }
        let r = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let why = (r?.isEmpty ?? true) ? nil : r
        switch request.requestType {
        case RequestType.treeEdit.rawValue:         await rejectTreeEditRequest(request: request, reason: why)
        case RequestType.deceasedReport.rawValue:   await rejectDeceasedRequest(request: request, reason: why)
        case RequestType.nameChange.rawValue:       await rejectNameChangeRequest(request: request, reason: why)
        case RequestType.photoSuggestion.rawValue:  await rejectPhotoSuggestion(request: request, reason: why)
        case RequestType.newsReport.rawValue:       await rejectNewsReport(request: request)
        default: break
        }
    }
}
