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
        case .hide: return L10n.t("إخفاء البيانات", "Hide my data")
        case .delete: return L10n.t("حذف البيانات من الشجرة", "Delete my data from the tree")
        case .correct: return L10n.t("تصحيح البيانات", "Correct my data")
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
                // قسم بعنوانه الموحّد (طلب المالك ٢٠٢٦-١١-١٠ «التصاميم مو موحدة»)
                DSComposerSection(title: L10n.t("موافقة ولي الأمر", "Guardian consent"), icon: "person.2.fill",
                                  tint: DS.Color.primary, trailing: "\(requests.count)", index: 0) {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(requests) { request in
                            row(request)
                        }
                        if let errorText {
                            DSNoteCard(errorText, icon: "exclamationmark.circle.fill", tint: DS.Color.error)
                        }
                    }
                }
                .dsPageMargin()
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
            Button(L10n.t("رفض", "Reject"), role: .destructive) {
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
            // تذييل المربّعات الموحّد: «موافقة» بتعبئة القسم، و«رفض» سطراً أحمر هادئاً تحته (بتأكيده كما كان)
            VStack(spacing: DS.Spacing.xs) {
                DSButton(L10n.t("موافقة", "Approve"), icon: "checkmark", isLoading: busyId == request.id) {
                    decide(request, approve: true)
                }
                Button { rejectTarget = request } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "xmark").dsGlyph(DS.Glyph.sm)
                        Text(L10n.t("رفض", "Reject")).dsFont(.chip)
                    }
                    .foregroundColor(DS.Color.error)
                    .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel(L10n.t("رفض", "Reject"))
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

/// بطاقات مستقلّة فوق طلبات «الوارد» — للمالك/المدير (الحذف) والمالك/المدير/المراقب (الخصوصية)،
/// و«إضافة قريبة» و«طلب حذف من الشجرة» (§9، المالك والمدير) بمربّع تفاصيلها
struct AdminPolicyRequestsSection: View {
    @ObservedObject var adminRequestVM: AdminRequestViewModel
    /// طلب يُفتح مربّعه بعد التحميل (من الإشعار) — مرة واحدة
    var focusId: UUID? = nil

    @State private var confirmDelete: AdminRequest?
    @State private var rejectTarget: AdminRequest?
    @State private var rejectReason = ""
    @State private var busyId: UUID?
    /// مربّع «إضافة قريبة» / «طلب حذف من الشجرة»
    @State private var openRelative: AdminRequest?
    @State private var focusHandled = false

    var body: some View {
        Group {
            ForEach(adminRequestVM.accountDeleteRequests) { request in
                card(request, isDeletion: true)
            }
            ForEach(adminRequestVM.privacyRequests) { request in
                card(request, isDeletion: false)
            }
            ForEach(adminRequestVM.relativeAddRequests) { request in
                card(request, isDeletion: false)
            }
            // «طلب حذف من الشجرة» (§9)
            ForEach(adminRequestVM.relativeRemoveRequests) { request in
                card(request, isDeletion: false)
            }
            // «طلب النسب» — صفّا الأم والأب وموافقة/رفض (أبناء البنات من خارج العائلة)
            ForEach(adminRequestVM.lineageRequests) { request in
                AdminLineageRequestCard(request: request, adminRequestVM: adminRequestVM)
            }
        }
        .onAppear(perform: openFocusIfNeeded)
        .onChange(of: relativeIds) { _ in openFocusIfNeeded() }
        .dsCenterBox(item: $openRelative) { request in
            AnyView(AdminRelativeRequestBox(
                request: request, adminRequestVM: adminRequestVM, isBusy: busyId == request.id,
                onApprove: { openRelative = nil; approve(request) },
                onReject: { reason in openRelative = nil; reject(request, reason: reason) },
                onClose: { openRelative = nil }))
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

    private var relativeIds: [UUID] {
        (adminRequestVM.relativeAddRequests + adminRequestVM.relativeRemoveRequests).map(\.id)
    }

    private func openFocusIfNeeded() {
        guard let focusId, !focusHandled else { return }
        guard let r = (adminRequestVM.relativeRemoveRequests + adminRequestVM.relativeAddRequests)
            .first(where: { $0.id == focusId }) else { return }
        focusHandled = true
        openRelative = r
    }

    private func name(_ r: AdminRequest?) -> String {
        r?.member?.fullName ?? L10n.t("العضو", "the member")
    }

    private static func isRelative(_ r: AdminRequest) -> Bool {
        r.requestType == RequestType.relativeAdd.rawValue || r.requestType == RequestType.relativeRemove.rawValue
    }

    private static func isRemoval(_ r: AdminRequest) -> Bool {
        r.requestType == RequestType.relativeRemove.rawValue
    }

    /// عنوان البطاقة (§10): «طلب إضافة زوجة» · «طلب حذف ابن» … لا «إضافة قريبة» وحدها
    static func title(_ request: AdminRequest) -> String {
        switch request.requestType {
        case RequestType.accountDelete.rawValue: return L10n.t("طلب حذف حساب", "Account deletion request")
        case RequestType.relativeAdd.rawValue:
            return RelativeAddDetails.parse(request.details)?.requestTitle ?? AdminRequestFactText.relativeAddGeneric
        case RequestType.relativeRemove.rawValue:
            return RelativeRemoveDetails.parse(request.details)?.requestTitle ?? RelativeRemoveDetails.genericTitle
        default:
            let kind = PrivacyRequestDetails.parse(request.details)?.kindTitle ?? ""
            return L10n.t("طلب خصوصية: \(kind)", "Privacy request: \(kind)")
        }
    }

    private func card(_ request: AdminRequest, isDeletion: Bool) -> some View {
        let isRelative = Self.isRelative(request)
        let isRemoval = Self.isRemoval(request)
        let details = isDeletion || isRelative ? nil : PrivacyRequestDetails.parse(request.details)
        let tint = isDeletion || isRemoval ? DS.Color.error : DS.Color.palm
        let title = Self.title(request)
        // «إضافة قريبة»/«حذف»: ملخّص السيرفر («حذف ابن: …») مكان الملاحظة
        let note = isRemoval ? RelativeRemoveDetails.parse(request.details)?.summary
                 : isRelative ? RelativeAddDetails.parse(request.details)?.summaryText
                 : details?.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lookup: (UUID) -> FamilyMember? = { adminRequestVM.memberVM?.member(byId: $0) }
        let facts = AdminRequestFacts.of(request, member: lookup)
        let approveTitle = isRemoval ? L10n.t("موافقة على الحذف", "Approve removal")
                         : isDeletion ? L10n.t("تنفيذ الحذف", "Delete account") : L10n.t("موافقة", "Approve")
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: isDeletion ? "person.crop.circle.badge.xmark"
                                : isRemoval ? "person.badge.minus"
                                : isRelative ? "person.badge.plus" : "lock.shield.fill",
                            tint: tint)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    // §10: شريحة النوع قبل العنوان، ثم «مقدّم الطلب: …»
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xsm) {
                        if let kind = facts?.kind { AdminRequestKindChip(kind: kind) }
                        Text(title)
                            .dsFont(.rowTitle)
                            .foregroundColor(DS.Color.textPrimary)
                    }
                    AdminRequestCardLine(kind: nil, requester: facts?.requesterShort ?? name(request))
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
            // «مكانه في الشجرة» (طلب المالك ٢٠٢٦-١١-١٣) — زرّ المعاينة الرئيسي = زرّ البطاقة نفسه
            if let place = treePlace(request, title: title) {
                AnyView(TreePlaceSection(place: place, men: adminRequestVM.memberVM?.allMembers ?? [],
                                         primary: TreePlacePrimary(
                                            title: approveTitle,
                                            icon: isDeletion || isRemoval ? "trash" : "checkmark") {
                                                if isDeletion { confirmDelete = request } else { approve(request) }
                                            })
                    .environment(\.dsFlatComposerSections, true))
            }
            HStack(spacing: DS.Spacing.sm) {
                DSButton(approveTitle,
                         icon: isDeletion || isRemoval ? "trash" : "checkmark",
                         role: isDeletion || isRemoval ? .destructive : nil,
                         tint: isDeletion || isRemoval ? nil : DS.Color.success,
                         isLoading: busyId == request.id) {
                    if isDeletion { confirmDelete = request } else { approve(request) }
                }
                DSButton(L10n.t("رفض", "Reject"), icon: "xmark", role: .cancel) {
                    rejectReason = ""
                    rejectTarget = request
                }
            }
            .disabled(busyId != nil)
            // «إضافة قريبة» و«حذف»: التفاصيل كاملة في مربّع (بيانات الطلب، المكان، المرسل)
            if isRelative {
                DSChipButton(L10n.t("تفاصيل الطلب", "Request details"), icon: "doc.text.magnifyingglass",
                             tint: DS.Color.primary, size: .small) {
                    openRelative = request
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(DS.Spacing.md)
        .dsCard(padding: nil, radius: DS.Hub.tileRadius)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: DS.Spacing.xsm, leading: DS.Spacing.lg, bottom: DS.Spacing.xsm, trailing: DS.Spacing.lg))
    }

    /// مكان الطلب: «إضافة قريبة»/«حذف» بنوعها، والحذف والخصوصية تعريف بالعضو
    private func treePlace(_ request: AdminRequest, title: String) -> TreePlace? {
        let data = TreePlaceData(men: adminRequestVM.memberVM?.allMembers ?? [], women: WomenStore.cache)
        switch request.requestType {
        case RequestType.relativeAdd.rawValue: return TreePlace.relativeAdd(request, kindLabel: title)
        case RequestType.relativeRemove.rawValue: return TreePlace.relativeRemove(request, kindLabel: title, data: data)
        default: return TreePlace.subject(memberId: request.memberId, kindLabel: title, data: data)
        }
    }

    private func approve(_ request: AdminRequest) {
        guard busyId == nil else { return }
        busyId = request.id
        Task {
            let ok: Bool
            switch request.requestType {
            case RequestType.accountDelete.rawValue: ok = await adminRequestVM.approveAccountDeletion(request)
            case RequestType.relativeAdd.rawValue: ok = await adminRequestVM.decideRelativeAdd(request, approve: true, reason: nil)
            case RequestType.relativeRemove.rawValue:
                ok = await adminRequestVM.decideRelativeRemove(request, approve: true, reason: nil)
            default: ok = await adminRequestVM.decidePrivacyRequest(request, approve: true, reason: nil)
            }
            busyId = nil
            if ok {
                DSMomentToast.show(request.requestType == RequestType.accountDelete.rawValue
                                   || request.requestType == RequestType.relativeRemove.rawValue
                                   ? L10n.t("تم التنفيذ", "Carried out") : L10n.t("تمت الموافقة", "Approved"))
            }
        }
    }

    private func reject(_ request: AdminRequest, reason: String) {
        guard busyId == nil else { return }
        busyId = request.id
        Task {
            switch request.requestType {
            case RequestType.accountDelete.rawValue:
                _ = await adminRequestVM.rejectAccountDeletion(request, reason: reason)
            case RequestType.relativeAdd.rawValue:
                _ = await adminRequestVM.decideRelativeAdd(request, approve: false, reason: reason)
            case RequestType.relativeRemove.rawValue:
                _ = await adminRequestVM.decideRelativeRemove(request, approve: false, reason: reason)
            default:
                _ = await adminRequestVM.decidePrivacyRequest(request, approve: false, reason: reason)
            }
            busyId = nil
        }
    }
}

// MARK: - مربّع «إضافة قريبة» / «طلب حذف من الشجرة» (§9/§10)

/// بيانات الطلب (نوع الطلب · القرابة · مقدّم الطلب · الاسم) ← «مكانه في الشجرة» ← «المرسل»، والقرار بأزراره
struct AdminRelativeRequestBox: View {
    let request: AdminRequest
    @ObservedObject var adminRequestVM: AdminRequestViewModel
    let isBusy: Bool
    let onApprove: () -> Void
    let onReject: (String) -> Void
    let onClose: () -> Void

    @State private var askReason = false
    @State private var reason = ""

    private var isRemoval: Bool { request.requestType == RequestType.relativeRemove.rawValue }

    private var nameValue: String? {
        if isRemoval { return RelativeRemoveDetails.parse(request.details)?.trimmedName }
        let n = RelativeAddDetails.parse(request.details)?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? nil : n
    }

    var body: some View {
        let title = AdminPolicyRequestsSection.title(request)
        let approveTitle = isRemoval ? L10n.t("موافقة على الحذف", "Approve removal") : L10n.t("موافقة", "Approve")
        let men = adminRequestVM.memberVM?.allMembers ?? []
        let data = TreePlaceData(men: men, women: WomenStore.cache)
        let place = isRemoval ? TreePlace.relativeRemove(request, kindLabel: title, data: data)
                              : TreePlace.relativeAdd(request, kindLabel: title)
        return DSComposer(
            title: title,
            subtitle: DateHelper.displayDateTime(request.createdAt) ?? L10n.t("تفاصيل الطلب", "Request Details"),
            icon: isRemoval ? "person.badge.minus" : "person.badge.plus",
            tint: DS.Color.actionNavy,
            // أزرار الطلبات الموحّدة: الإضافة «موافقة» كحلي + «رفض»؛ والحذف «موافقة على الحذف» أحمر (هدّام) و«رفض» فوقه
            actionTitle: approveTitle,
            actionIcon: "checkmark",
            showsAction: !isRemoval,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: !isBusy,
            extraActions: isRemoval ? [
                DSComposerAction(id: "reject", title: L10n.t("رفض", "Reject"), icon: "xmark", isEnabled: !isBusy) {
                    reason = ""
                    askReason = true
                },
                DSComposerAction(id: "approve", title: approveTitle, icon: "trash", role: .destructive,
                                 tint: DS.Color.error, isEnabled: !isBusy, action: onApprove),
            ] : [
                DSComposerAction(id: "reject", title: L10n.t("رفض", "Reject"), icon: "xmark",
                                 role: .destructive, tint: DS.Color.reject, isEnabled: !isBusy) {
                    reason = ""
                    askReason = true
                },
            ],
            decisionFooter: true,
            onSubmit: onApprove,
            onCancel: onClose
        ) {
            DSComposerSection(title: L10n.t("بيانات الطلب", "Request Info"), icon: "doc.text.fill",
                              tint: AppSection.admin.ink, index: 1) {
                if let facts = AdminRequestFacts.of(request, member: { adminRequestVM.memberVM?.member(byId: $0) }) {
                    AdminRequestFactRows(facts: facts)
                }
                if let nameValue {
                    DSTileGrid([.wide(DSFieldTileFace(label: L10n.t("الاسم", "Name"), value: nameValue, glyph: .none))])
                }
            }
            if let place {
                AnyView(TreePlaceSection(place: place, index: 2, men: men,
                                         primary: TreePlacePrimary(title: approveTitle,
                                                                   icon: isRemoval ? "trash" : "checkmark",
                                                                   action: onApprove)))
            }
            AdminSenderSection(info: senderInfo, index: place == nil ? 2 : 3)
        }
        .dsAlert(L10n.t("سبب الرفض", "Rejection Reason"), isPresented: $askReason) {
            TextField(L10n.t("اكتب السبب (اختياري)", "Reason (optional)"), text: $reason)
                .dsAlertField()
            Button(L10n.t("إرسال الرفض", "Send Rejection"), role: .destructive) { onReject(reason) }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("سيصل السبب كرسالة إلى مقدّم الطلب.", "The reason will be sent as a message to the requester."))
        }
    }

    /// «المرسل»: المسار («الملف الشخصي ← الأسرة ← …»)، ومن أرسله، والجهاز والوقت
    private var senderInfo: AdminSenderInfo {
        let arrow = L10n.t(" ← ", " → ")
        let what = AdminPolicyRequestsSection.title(request)
        let inferred = L10n.t("الملف الشخصي", "Profile") + arrow + L10n.t("الأسرة", "Family") + arrow + what
        let sender = adminRequestVM.memberVM?.member(byId: request.requesterId)
        let line = sender.map { m in
            [m.fourPartName, AdminTrailText.roleName(m.role)].compactMap { $0 }.joined(separator: " · ")
        }
        let via = request.sentVia
        return AdminSenderInfo(
            steps: AdminTrailText.pathSteps(recorded: request.sentFrom, inferred: inferred),
            sender: line, device: AdminTrailText.device(via), deviceRecorded: via != nil,
            time: DateHelper.displayDateTime(via?.at) ?? DateHelper.displayDateTime(request.createdAt) ?? AdminTrailText.notRecorded,
            senderId: sender?.id)
    }
}
