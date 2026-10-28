import SwiftUI
import Supabase

// MARK: - سياسة الخصوصية والشروط (طلب المالك ٢٠٢٦-١٠-٢٨)
// «بياناتي في الشجرة» (إخفاء/حذف/تصحيح)، موافقة ولي الأمر (للإدارة ولولي الأمر)،
// وطلبات الحذف والخصوصية في «الوارد». السيرفر يطبّق كل شيء؛ هنا الواجهات فقط.

extension Notification.Name {
    /// يفتح تبويب «حسابي» (إشعار `guardian_consent`) — تستقبله الرئيسية (`HomeNewsView`)
    static let openProfileTab = Notification.Name("openProfileTab")
}

// MARK: - «بياناتي في الشجرة»

enum TreeDataRequestKind: String, CaseIterable, Identifiable {
    case hide, delete, correct
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hide: return L10n.t("إخفاء بياناتي", "Hide my data")
        case .delete: return L10n.t("حذف بياناتي من الشجرة", "Delete my data from the tree")
        case .correct: return L10n.t("تصحيح بياناتي", "Correct my data")
        }
    }

    /// اسم النوع في «الوارد»
    var shortTitle: String {
        switch self {
        case .hide: return L10n.t("إخفاء", "Hide")
        case .delete: return L10n.t("حذف", "Delete")
        case .correct: return L10n.t("تصحيح", "Correct")
        }
    }

    var icon: String {
        switch self {
        case .hide: return "eye.slash.fill"
        case .delete: return "trash.fill"
        case .correct: return "pencil.line"
        }
    }

    var tint: Color {
        switch self {
        case .hide: return DS.Color.slate
        case .delete: return DS.Color.error
        case .correct: return DS.Color.palm
        }
    }

    /// الإخفاء والحذف يخفيان العضو فوراً أثناء المراجعة
    var hidesWhileReviewed: Bool { self != .correct }

    var subtitle: String {
        switch self {
        case .hide: return L10n.t("لا تظهر بياناتك للأعضاء", "Your data won't show to members")
        case .delete: return L10n.t("تُراجع الإدارة طلب حذف بياناتك", "The administration reviews your request")
        case .correct: return L10n.t("اكتب ما تريد تصحيحه", "Describe what should be corrected")
        }
    }
}

enum PrivacyRequestService {
    nonisolated struct Response: Decodable, Sendable {
        let ok: Bool?
        let hiddenNow: Bool?
        enum CodingKeys: String, CodingKey {
            case ok
            case hiddenNow = "hidden_now"
        }
    }

    /// يرسل الطلب — (نجح، الرسالة للعضو)
    @MainActor
    static func send(_ kind: TreeDataRequestKind, note: String) async -> (ok: Bool, message: String) {
        guard NetworkMonitor.shared.requireOnline() else {
            return (false, L10n.t("لا يوجد اتصال بالإنترنت.", "No internet connection."))
        }
        nonisolated struct Params: Encodable { let p_kind: String; let p_note: String? }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let r: Response = try await SupabaseConfig.client
                .rpc("request_privacy_change", params: Params(p_kind: kind.rawValue, p_note: trimmed.isEmpty ? nil : trimmed))
                .execute()
                .value
            if r.hiddenNow == true {
                return (true, L10n.t("أُرسل طلبك إلى الإدارة، وأُخفيت بياناتك عن الأعضاء أثناء مراجعته.",
                                     "Your request was sent, and your data is hidden from members while it is reviewed."))
            }
            return (true, L10n.t("أُرسل طلبك إلى الإدارة، ويصلك الرد في الإشعارات.",
                                 "Your request was sent; the reply will arrive in notifications."))
        } catch {
            Log.error("[Privacy] فشل إرسال الطلب: \(error.localizedDescription)")
            return (false, AuthViewModel.serverMessage(error, fallback: L10n.t(
                "تعذّر إرسال الطلب. حاول مرة أخرى.", "Couldn't send the request. Please try again.")))
        }
    }
}

/// مربّع الطلب: ملاحظة اختيارية + توضيح الإخفاء أثناء المراجعة
struct TreeDataRequestBox: View {
    let kind: TreeDataRequestKind
    let onSend: (String) -> Void
    let onCancel: () -> Void
    @State private var note = ""

    var body: some View {
        DSExtraBox(
            title: kind.title,
            subtitle: kind.subtitle,
            icon: kind.icon,
            tint: kind.tint,
            doneTitle: L10n.t("إرسال الطلب", "Send request"),
            onDone: { onSend(note) },
            onCancel: onCancel
        ) {
            DSComposerField(icon: "text.alignright",
                            label: L10n.t("ملاحظة", "Note"),
                            placeholder: L10n.t("اختياري", "Optional"),
                            text: $note, tint: kind.tint, multiline: true, limit: 500)
            if kind.hidesWhileReviewed {
                DSNoteCard(L10n.t("تُخفى بياناتك عن الأعضاء أثناء مراجعة طلبك",
                                  "Your data is hidden from members while your request is reviewed"),
                           icon: "eye.slash.fill", tint: DS.Color.warning)
            }
        }
    }
}

// MARK: - موافقة ولي الأمر: جانب الإدارة (مربّع «اطلب موافقة ولي الأمر»)

/// يعرض المربّع في نافذة فوق كل شيء — الربط/التفعيل يحدث من أوراق ومربّعات مختلفة
@MainActor
enum GuardianConsentPresenter {
    private static var window: UIWindow?
    private static weak var previousKey: UIWindow?

    static func offer(minorId: UUID, treeMemberId: UUID, message: String) {
        guard window == nil else { return }
        // بعد أن تُغلق الورقة/التأكيد الذي بدأ منه الربط
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard window == nil else { return }
            present(minorId: minorId, treeMemberId: treeMemberId, message: message)
        }
    }

    private static func present(minorId: UUID, treeMemberId: UUID, message: String) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        previousKey = scene.windows.first(where: \.isKeyWindow)
        let root = DSCenterPanel(onBackgroundTap: nil, hugsContent: true) {
            GuardianConsentPromptBox(minorId: minorId, treeMemberId: treeMemberId,
                                     message: message, onClose: { close() })
        }
        .environment(\.locale, LanguageManager.shared.locale)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .dsSection(AppSection.current)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert
        w.backgroundColor = .clear
        w.overrideUserInterfaceStyle = DSPopupPresenter.appInterfaceStyle(in: scene)
        w.rootViewController = host
        w.makeKeyAndVisible()
        window = w
    }

    static func close() {
        guard let w = window else { return }
        window = nil
        UIView.animate(withDuration: 0.2, animations: { w.alpha = 0 }, completion: { _ in
            w.isHidden = true
            w.rootViewController = nil
            previousKey?.makeKey()
        })
    }
}

struct GuardianConsentPromptBox: View {
    let minorId: UUID
    let treeMemberId: UUID
    let message: String
    let onClose: () -> Void

    @State private var isBusy = false
    @State private var sent = false
    @State private var errorText: String?

    private var tint: Color { DS.Color.actionNavy }

    var body: some View {
        DSComposer(
            title: L10n.t("موافقة ولي الأمر", "Guardian consent"),
            subtitle: L10n.t("حساب قاصر", "A minor's account"),
            icon: sent ? "checkmark" : "person.2.fill",
            tint: tint,
            actionTitle: L10n.t("اطلب موافقة ولي الأمر", "Ask the guardian"),
            actionIcon: "paperplane.fill",
            showsAction: !sent,
            cancelTitle: sent ? L10n.t("إغلاق", "Close") : L10n.t("إلغاء", "Cancel"),
            canSubmit: !isBusy,
            isBusy: isBusy,
            onSubmit: send,
            onCancel: onClose
        ) {
            DSComposerSection(title: sent ? L10n.t("تم", "Done") : L10n.t("السبب", "Reason"),
                              icon: sent ? "checkmark" : "info.circle.fill", tint: tint, index: 0) {
                Text(sent ? L10n.t("أُرسل طلب الموافقة لولي الأمر", "The consent request was sent to the guardian")
                          : message)
                    .dsFont(.bodyCompact)
                    .foregroundColor(DS.Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let errorText {
                DSNoteCard(errorText, icon: "exclamationmark.circle.fill", tint: DS.Color.error)
                    .transition(.opacity)
            }
        }
    }

    private func send() {
        guard !isBusy, NetworkMonitor.shared.requireOnline() else { return }
        nonisolated struct Params: Encodable { let p_minor: String; let p_tree_member: String }
        nonisolated struct Response: Decodable { let ok: Bool? }
        isBusy = true
        errorText = nil
        Task {
            do {
                let r: Response = try await SupabaseConfig.client
                    .rpc("request_guardian_consent",
                         params: Params(p_minor: minorId.uuidString, p_tree_member: treeMemberId.uuidString))
                    .execute()
                    .value
                isBusy = false
                guard r.ok != false else { throw NSError(domain: "GuardianConsent", code: 1) }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(DSMotion.fade) { sent = true }
            } catch {
                Log.error("[GuardianConsent] فشل الطلب: \(error.localizedDescription)")
                isBusy = false
                withAnimation(DSMotion.fade) {
                    errorText = AuthViewModel.serverMessage(error, fallback: L10n.t(
                        "تعذّر إرسال طلب الموافقة. حاول مرة أخرى.", "Couldn't send the consent request. Please try again."))
                }
            }
        }
    }
}

// MARK: - موافقة ولي الأمر: جانب ولي الأمر («حسابي»)

nonisolated struct GuardianRequest: Decodable, Identifiable, Sendable {
    let id: UUID
    let minorName: String?
    let createdAt: String?
    let scope: String?
    enum CodingKeys: String, CodingKey {
        case id, scope
        case minorName = "minor_name"
        case createdAt = "created_at"
    }
}

/// بطاقة أعلى «حسابي» — تظهر فقط إن وُجد طلب
struct GuardianRequestsCard: View {
    @State private var requests: [GuardianRequest] = []
    @State private var busyId: UUID?
    @State private var rejectTarget: GuardianRequest?
    @State private var errorText: String?

    var body: some View {
        // VStack لا Group: يبقى موجوداً وهو فارغ فيعمل `.task`
        VStack(spacing: 0) {
            if !requests.isEmpty {
                DSFormCard(L10n.t("موافقة ولي الأمر", "Guardian consent"), icon: "person.2.fill",
                           color: DS.Color.info) {
                    Text("\(requests.count)")
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                } content: {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(requests) { request in
                            row(request)
                        }
                        if let errorText {
                            DSNoteCard(errorText, icon: "exclamationmark.circle.fill", tint: DS.Color.error)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
            }
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .openProfileTab)) { _ in
            Task { await load() }
        }
        .dsAlert(L10n.t("رفض الطلب؟", "Reject the request?"),
                 isPresented: Binding(get: { rejectTarget != nil }, set: { if !$0 { rejectTarget = nil } })) {
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { rejectTarget = nil }
            Button(L10n.t("أرفض", "Reject"), role: .destructive) {
                if let r = rejectTarget { decide(r, approve: false) }
                rejectTarget = nil
            }
        } message: {
            Text(L10n.t("لن يُفعَّل حساب \(rejectTarget?.minorName ?? "") في التطبيق.",
                        "\(rejectTarget?.minorName ?? "")'s account won't be activated."))
        }
    }

    private func row(_ request: GuardianRequest) -> some View {
        let name = request.minorName ?? L10n.t("أحد أبنائك", "One of your children")
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(L10n.t("\(name) يطلب إنشاء حساب في التطبيق", "\(name) is asking to create an account in the app"))
                .dsFont(.rowTitle)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Spacing.sm) {
                DSButton(L10n.t("أوافق", "Approve"), icon: "checkmark", tint: DS.Color.success,
                         isLoading: busyId == request.id) {
                    decide(request, approve: true)
                }
                DSButton(L10n.t("أرفض", "Reject"), icon: "xmark", role: .destructive, tint: DS.Color.reject) {
                    rejectTarget = request
                }
            }
            .disabled(busyId != nil)
        }
        .dsRowBox()
    }

    private func load() async {
        do {
            let rows: [GuardianRequest]? = try await SupabaseConfig.client
                .rpc("my_guardian_requests").execute().value
            withAnimation(DSMotion.fade) { requests = rows ?? [] }
        } catch {
            Log.warning("[GuardianConsent] تعذّر جلب الطلبات: \(error.localizedDescription)")
        }
    }

    private func decide(_ request: GuardianRequest, approve: Bool) {
        guard busyId == nil, NetworkMonitor.shared.requireOnline() else { return }
        nonisolated struct Params: Encodable { let p_consent_id: String; let p_approve: Bool }
        busyId = request.id
        errorText = nil
        Task {
            do {
                _ = try await SupabaseConfig.client
                    .rpc("decide_guardian_consent", params: Params(p_consent_id: request.id.uuidString, p_approve: approve))
                    .execute()
                if approve { DSMomentToast.show(L10n.t("تمت الموافقة", "Approved"), section: .profile) }
            } catch {
                Log.error("[GuardianConsent] فشل القرار: \(error.localizedDescription)")
                errorText = AuthViewModel.serverMessage(error, fallback: L10n.t(
                    "تعذّر حفظ قرارك. حاول مرة أخرى.", "Couldn't save your decision. Please try again."))
            }
            busyId = nil
            await load()
        }
    }
}

// MARK: - «الوارد»: طلبات حذف الحساب والخصوصية

/// بطاقات مستقلّة فوق طلبات «الوارد» — للمالك/المدير (الحذف) والمالك/المدير/المراقب (الخصوصية)
struct AdminPolicyRequestsSection: View {
    @ObservedObject var adminRequestVM: AdminRequestViewModel

    @State private var confirmDelete: AdminRequest?
    @State private var rejectTarget: AdminRequest?
    @State private var rejectReason = ""
    @State private var busyId: UUID?

    var body: some View {
        Group {
            ForEach(adminRequestVM.accountDeleteRequests) { request in
                card(request, isDeletion: true)
            }
            ForEach(adminRequestVM.privacyRequests) { request in
                card(request, isDeletion: false)
            }
        }
        .dsAlert(L10n.t("حذف نهائي للحساب؟", "Delete the account permanently?"),
                 isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { confirmDelete = nil }
            Button(L10n.t("حذف نهائي", "Delete Permanently"), role: .destructive) {
                if let r = confirmDelete { approve(r) }
                confirmDelete = nil
            }
        } message: {
            Text(L10n.t("يُحذف رقم \(name(confirmDelete)) وبريده وصورته ومنشوراته وتعليقاته وحساب دخوله، ويبقى اسمه وموقعه في الشجرة. لا يمكن التراجع.",
                        "\(name(confirmDelete))'s number, email, photo, posts, comments and login are deleted; the name and place in the tree remain. This can't be undone."))
        }
        .dsAlert(L10n.t("سبب الرفض", "Rejection Reason"),
                 isPresented: Binding(get: { rejectTarget != nil }, set: { if !$0 { rejectTarget = nil } })) {
            TextField(L10n.t("اكتب السبب (اختياري)", "Reason (optional)"), text: $rejectReason)
                .dsAlertField()
            Button(L10n.t("إرسال الرفض", "Send Rejection"), role: .destructive) {
                if let r = rejectTarget { reject(r, reason: rejectReason) }
                rejectTarget = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { rejectTarget = nil }
        } message: {
            Text(L10n.t("سيصل السبب كرسالة إلى مقدّم الطلب.", "The reason will be sent as a message to the requester."))
        }
    }

    private func name(_ r: AdminRequest?) -> String {
        r?.member?.fullName ?? L10n.t("العضو", "the member")
    }

    private func card(_ request: AdminRequest, isDeletion: Bool) -> some View {
        let details = isDeletion ? nil : PrivacyRequestDetails.parse(request.details)
        let tint = isDeletion ? DS.Color.error : DS.Color.palm
        let title = isDeletion ? L10n.t("طلب حذف حساب", "Account deletion request")
                               : L10n.t("طلب خصوصية: \(details?.kindTitle ?? "")", "Privacy request: \(details?.kindTitle ?? "")")
        let note = details?.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: isDeletion ? "person.crop.circle.badge.xmark" : "lock.shield.fill", tint: tint)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title)
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(name(request))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                        .dsNameLines()
                }
                Spacer(minLength: 0)
                if let created = request.createdAt {
                    Text(DateHelper.relativeTime(from: created))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            if let note, !note.isEmpty {
                Text(note)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isDeletion {
                Text(L10n.t("يُنفَّذ خلال سبعة أيام من الطلب.", "To be carried out within seven days of the request."))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
            }
            HStack(spacing: DS.Spacing.sm) {
                DSButton(isDeletion ? L10n.t("تنفيذ الحذف", "Delete account") : L10n.t("موافقة", "Approve"),
                         icon: isDeletion ? "trash" : "checkmark",
                         role: isDeletion ? .destructive : nil,
                         tint: isDeletion ? nil : DS.Color.success,
                         isLoading: busyId == request.id) {
                    if isDeletion { confirmDelete = request } else { approve(request) }
                }
                DSButton(L10n.t("رفض", "Reject"), icon: "xmark", role: .cancel) {
                    rejectReason = ""
                    rejectTarget = request
                }
            }
            .disabled(busyId != nil)
        }
        .padding(DS.Spacing.md)
        .dsCard(padding: nil, radius: DS.Hub.tileRadius)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: DS.Spacing.xsm, leading: DS.Spacing.lg, bottom: DS.Spacing.xsm, trailing: DS.Spacing.lg))
    }

    private func approve(_ request: AdminRequest) {
        guard busyId == nil else { return }
        busyId = request.id
        Task {
            let ok = request.requestType == RequestType.accountDelete.rawValue
                ? await adminRequestVM.approveAccountDeletion(request)
                : await adminRequestVM.decidePrivacyRequest(request, approve: true, reason: nil)
            busyId = nil
            if ok {
                DSMomentToast.show(request.requestType == RequestType.accountDelete.rawValue
                                   ? L10n.t("تم التنفيذ", "Carried out") : L10n.t("تمت الموافقة", "Approved"))
            }
        }
    }

    private func reject(_ request: AdminRequest, reason: String) {
        guard busyId == nil else { return }
        busyId = request.id
        Task {
            if request.requestType == RequestType.accountDelete.rawValue {
                _ = await adminRequestVM.rejectAccountDeletion(request, reason: reason)
            } else {
                _ = await adminRequestVM.decidePrivacyRequest(request, approve: false, reason: reason)
            }
            busyId = nil
        }
    }
}
