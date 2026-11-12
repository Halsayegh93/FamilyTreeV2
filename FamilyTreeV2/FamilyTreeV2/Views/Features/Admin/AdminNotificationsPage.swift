import SwiftUI
import Combine

// MARK: - «إشعارات الإدارة» — صفحة واحدة (طلب المالك ٢٠٢٦-١٠-٢٠: «صفحة وحدة «إشعارات الإدارة»»)
//
// كانت ثلاثة أماكن: بطاقة «تنبيهات» في «اليوم»، و«سجل التعديلات» في «المؤشرات»، وإشعارات الإدارة مخلوطة بإشعارات العضو
// في مركز الإشعارات. صارت صفحة واحدة يفتحها جرس «اليوم» (بعدد غير المقروء وما يحتاج إجراء)، خطّ زمني واحد بالأيام
// (اليوم · أمس · التاريخ):
//   • «يحتاج إجراء»: ما يُشتقّ من حالة حقيقية الآن (وفاة لم يُعلن عنها، مشكلات الشجرة للمراقب، خلل في إعداد قاعدة
//     البيانات — `AdminNoticeStore` يغذّيه «اليوم») + إشعارات الطلبات التي ما زالت معلّقة؛ كلٌّ بزرّ صغير لبيته الوحيد
//     (مراجعة ← الوارد على الطلب، إعلان ← المناسبات «القادم»، شحن الرصيد ← رسائل رمز الدخول)، و«محاولات دخول مريبة»
//     (`sms_suspicious` — الدفعة ١٤) بزرّ «راجع» ← «طلبات رمز الدخول».
//   • «نشاط الفريق»: سجل التعديلات نفسه (من عدّل ماذا ومتى، قبل ← بعد في مربّع التفاصيل).
//   • «النظام»: تنبيهات رصيد رسائل الدخول.
// البحث الواحد هنا (كان في «سجل التعديلات»)، والسحب: «مقروء» و«حذف» (كل عضو يحذف نسخته)، و«تحديد» للقراءة والحذف معاً.
//
// **مكان واحد لكل إشعار** (`AdminNotices.category`): ما يخصّ الإدارة لا يظهر في مركز الإشعارات العام للإدارة ولا في
// عدّاد جرسه — يبقى هناك ما يخصّ العضو نفسه (تعديل على بياناته، نتيجة طلبه، إعلانات العائلة ووفياتها، تحديث التطبيق،
// الإعجاب والتعليق، رسائل الإدارة له، ردود «مسار الموافقات» لصاحب الطلب). العضو العادي لا يتغيّر عنده شيء.

/// تصنيف إشعارات الإدارة — المصدر الواحد لمركز الإشعارات (يستبعدها) ولهذه الصفحة وعدّاد جرس «اليوم»
enum AdminNotices {
    /// `changes` = «تغييرات الأعضاء» (`member_change` من السيرفر، طلب المالك ٢٠٢٦-١١-٠١) — هنا وحدها، لا في المركز العام
    enum Category: String { case action, team, system, changes }

    /// تغييرات بيانات الأعضاء (v2: قبل ← بعد لكل حقل، والمنفّذ)
    static let memberChangeKind = "member_change"

    /// طلبات تنتظر قراراً (انضمام، شجرة، وفاة، بلاغ، محتوى بانتظار الاعتماد، رسالة عضو…)
    static let requestKinds: Set<String> = [
        "join_request",
        NotificationKind.linkRequest.rawValue,
        NotificationKind.treeEdit.rawValue,
        NotificationKind.childAdd.rawValue,
        NotificationKind.phoneChange.rawValue,
        NotificationKind.nameChange.rawValue,
        NotificationKind.deceasedReport.rawValue,
        NotificationKind.photoSuggestion.rawValue,
        NotificationKind.contentReport.rawValue,
        NotificationKind.newsReport.rawValue,
        NotificationKind.newsAdd.rawValue,
        NotificationKind.contactMessage.rawValue,
        NotificationKind.adminRequest.rawValue,
        NotificationKind.galleryPending.rawValue,
        NotificationKind.diwaniyaPending.rawValue,
        NotificationKind.projectPending.rawValue,
        NotificationKind.archivePending.rawValue,
        RequestType.familyChange.rawValue,
    ]

    /// تعديلات الأعضاء (بيانات، حذف، أدوار، انضمام) — شريحة «نشاط الفريق»
    static let memberKinds: Set<String> = [
        NotificationKind.adminEdit.rawValue,
        NotificationKind.adminEditName.rawValue,
        NotificationKind.adminEditDates.rawValue,
        NotificationKind.adminEditPhone.rawValue,
        NotificationKind.adminEditPhoneRemove.rawValue,
        NotificationKind.adminEditRole.rawValue,
        NotificationKind.adminEditFather.rawValue,
        NotificationKind.adminEditAvatar.rawValue,
        NotificationKind.adminEditAvatarRemove.rawValue,
        NotificationKind.adminEditChildAdd.rawValue,
        NotificationKind.adminEditChildRemove.rawValue,
        NotificationKind.memberDelete.rawValue,
        "member_add",
        NotificationKind.joinApproved.rawValue,
        NotificationKind.accountActivated.rawValue,
        NotificationKind.roleChange.rawValue,
    ]

    /// شجرة النساء (جدولها مستقلّ)
    static let womenKinds: Set<String> = [
        NotificationKind.womenAdd.rawValue,
        NotificationKind.womenEdit.rawValue,
        NotificationKind.womenDelete.rawValue,
    ]

    /// المحتوى: اعتماد ورفض ونشر وحذف (أخبار، صور، ديوانيات، مشاريع، المكتبة)
    static let contentKinds: Set<String> = [
        NotificationKind.newsPublished.rawValue,
        "news_deleted",
        NotificationKind.galleryApproved.rawValue,
        NotificationKind.galleryRejected.rawValue,
        NotificationKind.diwaniyaApproved.rawValue,
        NotificationKind.diwaniyaRejected.rawValue,
        NotificationKind.projectApproved.rawValue,
        NotificationKind.projectRejected.rawValue,
        NotificationKind.archiveApproved.rawValue,
        NotificationKind.archiveRejected.rawValue,
    ]

    static let teamKinds: Set<String> = memberKinds.union(womenKinds).union(contentKinds)

    /// «رصيد رسائل الدخول منخفض» (`kwtsms_low_balance_alert`) و«محاولات دخول مريبة» (`log_login_attempt`) — للمالك والمدير
    static let smsBalanceLow = "sms_balance_low"
    static let smsSuspicious = "sms_suspicious"
    /// أنواع KWT SMS — نقر إشعارها يفتح صفحتها في لوحة الإدارة
    static let smsKinds: Set<String> = [smsBalanceLow, smsSuspicious]

    /// تنبيهات النظام (رصيد رسائل رمز الدخول)
    static let systemKinds: Set<String> = [smsBalanceLow, "review_account_activity"]
    private static let decidedPrefixes = ["تم قبول", "تم رفض"]
    /// تنبيهات أمنية تحتاج مراجعة («يحتاج إجراء» بزرّ «راجع»)
    static let securityKinds: Set<String> = [smsSuspicious]

    /// «مسار الموافقات» يرسل لصاحب الطلب بهذه العناوين (`approvals_v2`) — تخصّه هو فتبقى في مركز الإشعارات
    private static let requesterTitles = [
        "الإدارة تحتاج معلومات إضافية", "تمت الموافقة على طلبك", "تم تنفيذ طلبك", "تذكير: الإدارة تنتظر ردّك",
    ]

    /// تصنيف الإشعار للإدارة — nil = ليس إداريّاً (مكانه مركز الإشعارات). يُسأل للإدارة فقط (`canModerate`)
    static func category(of n: AppNotification, me: UUID?) -> Category? {
        // تنبيهات KWT SMS إدارية دائماً (تصل المالك والمدير فقط) — قبل قاعدة «ما يخصّني»
        if securityKinds.contains(n.kind) { return .action }
        if systemKinds.contains(n.kind) { return .system }
        // «تغييرات الأعضاء» إدارية دائماً — قبل قاعدة «ما يخصّني» (العضو يصله `my_profile_change` في «إشعاراتي»)
        if n.kind == memberChangeKind { return .changes }
        // ما يخصّني أنا (تعديل على بياناتي، طلب عنّي) يبقى في «الإشعارات» — كما كان
        if let me, n.subjectMemberId == me, n.createdBy != me { return nil }
        // نتيجة طلب انتهى («تم قبول…») بنوع الطلب نفسه: سجلّ لا مهمّة — كانت تطلع «يحتاج إجراء» بزرّ «مراجعة»
        if requestKinds.contains(n.kind), decidedPrefixes.contains(where: { n.title.hasPrefix($0) }) { return .team }
        if requestKinds.contains(n.kind) { return .action }
        if teamKinds.contains(n.kind) { return .team }
        if n.kind == NotificationKind.admin.rawValue, n.details?.type == "approval_workflow",
           !requesterTitles.contains(where: { n.title.hasPrefix($0) }) {
            return .action
        }
        return nil
    }

    /// معرّف الطلب الذي يخصّه الإشعار (عمود الطلب، أو تفاصيل «مسار الموافقات»)
    static func requestId(of n: AppNotification) -> UUID? {
        n.requestId ?? n.details?.workflowRequestId.flatMap(UUID.init(uuidString:))
    }
}

// MARK: - العنصر

/// أين يفتح زرّ العنصر — بيت واحد لكل أمر
enum AdminNoticeTarget: Equatable {
    case none
    case inbox(UUID?)
    case messages
    case occasions
    case sms
    /// «طلبات رمز الدخول» كاملة (محاولات دخول مريبة)
    case smsAttempts
    case treeProblems
}

/// صفّ في «إشعارات الإدارة»: إشعار (له معرّف للقراءة والحذف والتفاصيل) أو حالة مشتقة («يحتاج إجراء» الآن)
struct AdminNoticeItem: Identifiable, Equatable {
    let id: String
    let category: AdminNotices.Category
    let date: Date
    /// حالة مشتقة الآن (لا إشعار) — أول «اليوم»
    var pinned = false
    let icon: String
    let tint: Color
    var title: String
    var subtitle: String
    var isUnread = false
    var notificationId: UUID? = nil
    var needsAction = false
    var button: String? = nil
    var target: AdminNoticeTarget = .none
    /// الصفّ الجديد (المرسل + «قبل ← بعد») — «تغييرات الأعضاء»
    var rich: AdminNoticeRich? = nil
    /// «تمت إضافة ابن»: «راجع» في البطاقة، و«الملف» · «فيه خطأ؟» · «حذف» في التفاصيل — `AdminSelfChildNotice.swift`
    var selfChild: AdminNoticeSelfChild? = nil
    /// لون نقطته على الخطّ الزمني (طلب · إضافة · تعديل · نظام)
    var tone: AdminNoticeTone = .system
    /// السطر الصغير: مَن فعل («أضافه أبوه فهد»، «بواسطة: فيصل»)
    var meta: String? = nil
}

/// محتوى الصفّ الجديد لـ«تغييرات الأعضاء»: المرسل («الإدارة · بواسطة: فلان» أو العضو) والتغييرات
struct AdminNoticeRich: Equatable {
    let sender: NotificationSenderInfo
    let changes: [AppNotification.NotificationDetails.ChangeEntry]
}

/// الحالات المشتقة («يحتاج إجراء» الآن) — يكتبها «اليوم» من حالته، ويقرؤها الجرس والصفحة
@MainActor
final class AdminNoticeStore: ObservableObject {
    static let shared = AdminNoticeStore()
    @Published private(set) var derived: [AdminNoticeItem] = []

    func publish(_ items: [AdminNoticeItem]) {
        if items != derived { derived = items }
    }

    /// وفاة لم يُعلن عنها (المالك والمدير) · مشكلات الشجرة (المراقب) · خلل في إعداد قاعدة البيانات (للكل)
    static func derive(authVM: AuthViewModel, unannounced: [FamilyMember], treeIssues: Int?) -> [AdminNoticeItem] {
        var list: [AdminNoticeItem] = []
        let now = Date()
        if !authVM.notificationsFeatureAvailable || !authVM.newsApprovalFeatureAvailable {
            var lines: [String] = []
            if !authVM.notificationsFeatureAvailable {
                lines.append(L10n.t("جدول الإشعارات غير موجود — الإشعارات معطلة", "Notifications table missing"))
            }
            if !authVM.newsApprovalFeatureAvailable {
                lines.append(L10n.t("عمود اعتماد الأخبار غير موجود — اعتماد الأخبار معطّل", "News approval column missing"))
            }
            list.append(AdminNoticeItem(id: "derived.schema", category: .action, date: now, pinned: true,
                                        icon: "exclamationmark.triangle.fill", tint: DS.Color.error,
                                        title: L10n.t("خلل في إعداد قاعدة البيانات", "Database setup problem"),
                                        subtitle: lines.joined(separator: "\n"), needsAction: true, tone: .system))
        }
        if authVM.isAdmin {
            for m in unannounced {
                list.append(AdminNoticeItem(id: "derived.death.\(m.id.uuidString)", category: .action, date: now, pinned: true,
                                            icon: NewsTypeHelper.icon(for: "وفاة"), tint: DS.Color.slate,
                                            title: L10n.t("وفاة لم يُعلن عنها", "Death not announced"),
                                            subtitle: [m.shortFullName, m.deathDate.flatMap { DateHelper.displayDate($0) }]
                                                .compactMap { $0 }.joined(separator: " · "),
                                            needsAction: true, button: L10n.t("إعلان", "Announce"), target: .occasions,
                                            tone: .request))
            }
        }
        if authVM.currentUser?.role == .monitor, let n = treeIssues, n > 0 {
            list.append(AdminNoticeItem(id: "derived.tree", category: .action, date: now, pinned: true,
                                        icon: "stethoscope", tint: DS.Color.warning,
                                        title: L10n.t("مشكلات الشجرة: \(n) تحتاج مراجعة", "Tree problems: \(n) to review"),
                                        subtitle: L10n.t("غير مرتبط بأب، بلا اسم، ارتباط أب غير صالح",
                                                         "Unlinked, unnamed or invalid father links"),
                                        needsAction: true, button: L10n.t("مراجعة", "Review"), target: .treeProblems,
                                        tone: .request))
        }
        return list
    }
}

// MARK: - بيوت الأزرار

enum AdminNoticeRoutes {
    /// الصفحة التي يفتحها الزرّ — بقسمها في قائمة العنوان
    static func page(_ target: AdminNoticeTarget) -> AnyView {
        let back = L10n.t("إشعارات الإدارة", "Admin notifications")
        switch target {
        case .none:            return AnyView(EmptyView())
        case .inbox(let id):   return AnyView(AdminAllRequestsView(focusId: id).adminArea(.inbox))
        case .messages:        return AnyView(AdminAllRequestsView(startsWithMessages: true).adminArea(.inbox))
        case .occasions:       return AnyView(AdminOccasionsPage().adminArea(.occasions).adminBackTitle(back))
        case .sms:             return AnyView(AdminSmsView(backTitle: back).adminArea(.team))
        case .smsAttempts:     return AnyView(SmsAttemptsListPage().adminBackTitle(back).adminArea(.team))
        case .treeProblems:    return AnyView(AdminMembersPage(chip: .problems).adminArea(.family))
        }
    }

    /// شكل الصفّ حسب النوع (مربّع الأيقونة ولونه)
    static func style(_ n: AppNotification, _ category: AdminNotices.Category) -> (icon: String, tint: Color) {
        let kind = n.kind
        switch category {
        case .changes:
            return ("person.text.rectangle", DS.Color.accent)
        case .system:
            return ("ellipsis.message.fill", DS.Color.warning)
        case .action:
            switch kind {
            case AdminNotices.smsSuspicious:                   return ("exclamationmark.shield.fill", DS.Color.error)
            case "join_request", NotificationKind.linkRequest.rawValue, NotificationKind.childAdd.rawValue:
                return ("person.badge.plus", DS.Color.info)
            case NotificationKind.treeEdit.rawValue:           return ("pencil.circle.fill", DS.Color.palm)
            case NotificationKind.deceasedReport.rawValue:     return (NewsTypeHelper.icon(for: "وفاة"), DS.Color.slate)
            case NotificationKind.phoneChange.rawValue:        return ("phone.fill", DS.Color.palm)
            case NotificationKind.nameChange.rawValue, RequestType.familyChange.rawValue:
                return ("character.cursor.ibeam", DS.Color.info)
            case NotificationKind.photoSuggestion.rawValue, NotificationKind.galleryPending.rawValue:
                return ("photo.fill", DS.Color.sadu)
            case NotificationKind.newsReport.rawValue, NotificationKind.contentReport.rawValue:
                return ("exclamationmark.bubble.fill", DS.Color.error)
            case NotificationKind.newsAdd.rawValue:            return ("newspaper.fill", DS.Color.accent)
            case NotificationKind.diwaniyaPending.rawValue:    return ("tent.fill", DS.Color.palm)
            case NotificationKind.projectPending.rawValue:     return ("briefcase.fill", DS.Color.accent)
            case NotificationKind.archivePending.rawValue:     return ("books.vertical.fill", DS.Color.sadu)
            case NotificationKind.contactMessage.rawValue:     return ("bubble.left.fill", DS.Color.sea)
            default:                                           return ("tray.fill", DS.Color.primary)
            }
        case .team:
            if AdminNotices.womenKinds.contains(kind) {
                return (kind == NotificationKind.womenDelete.rawValue ? "trash.fill" : "figure.dress.line.vertical.figure",
                        kind == NotificationKind.womenDelete.rawValue ? DS.Color.error : DS.Color.female)
            }
            if AdminNotices.memberKinds.contains(kind) {
                switch kind {
                case NotificationKind.memberDelete.rawValue:
                    return ("person.crop.circle.badge.minus", DS.Color.error)
                case NotificationKind.roleChange.rawValue, NotificationKind.adminEditRole.rawValue:
                    return ("shield.lefthalf.filled", DS.Color.accent)
                case NotificationKind.joinApproved.rawValue, NotificationKind.accountActivated.rawValue:
                    return ("person.crop.circle.badge.checkmark", DS.Color.success)
                case NotificationKind.adminEditAvatar.rawValue, NotificationKind.adminEditAvatarRemove.rawValue:
                    return ("photo.circle.fill", DS.Color.info)
                default:
                    return ("pencil.circle.fill", DS.Color.palm)
                }
            }
            if kind.contains("news") { return ("newspaper.fill", DS.Color.info) }
            if kind.contains("gallery") { return ("photo.stack.fill", DS.Color.info) }
            if kind.contains("diwaniya") { return (AppSection.diwaniyas.symbol, AppSection.admin.ink) }
            if kind.contains("project") { return ("briefcase.fill", DS.Color.accent) }
            return ("doc.fill", DS.Color.info)
        }
    }
}

// MARK: - الصفحة

struct AdminNotificationsPage: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @ObservedObject private var store = AdminNoticeStore.shared
    @ObservedObject private var sms = SmsBalanceStore.shared
    @Environment(\.adminBackTitle) private var opener
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Filter: String, CaseIterable, Identifiable {
        case all, action, changes, team, system
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:    return L10n.t("الكل", "All")
            case .action: return L10n.t("يحتاج إجراء", "Needs action")
            case .changes: return L10n.t("تغييرات الأعضاء", "Member changes")
            case .team:   return L10n.t("نشاط الفريق", "Team activity")
            case .system: return L10n.t("النظام", "System")
            }
        }
        var icon: String {
            switch self {
            case .all:    return "square.grid.2x2.fill"
            case .action: return "exclamationmark.circle.fill"
            case .changes: return "pencil.line"
            case .team:   return "person.2.fill"
            case .system: return "gearshape.fill"
            }
        }
    }

    @State private var filter: Filter = .all
    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selectedIds: Set<UUID> = []
    @State private var showDeleteConfirm = false
    @State private var detail: AppNotification?
    @State private var hasLoaded = false
    @State private var appeared = false
    @State private var selfChildFlow = AdminSelfChildFlow()

    static var title: String { L10n.t("إشعارات الإدارة", "Admin notifications") }

    var body: some View {
        let items = allItems
        return AdminPage(header: header(items), lead: AnyView(leadCard(items)), layout: .list,
                         content: AnyView(rows(items)))
            .dsAlert(L10n.t("حذف \(selectedIds.count) من الإشعارات؟", "Delete \(selectedIds.count) notifications?"),
                     isPresented: $showDeleteConfirm, icon: "trash.fill") {
                Button(L10n.t("حذف", "Delete"), role: .destructive) { deleteSelected() }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            }
            // تفاصيل الإشعار المربّع الغني بمنتصف الشاشة — نفسه في مركز الإشعارات (طلب المالك ٢٠٢٦-١١-٠١)
            .dsCenterBox(item: $detail, onBackgroundTap: { detail = nil }) { n in
                AnyView(detailBox(n))
            }
            .task {
                // «ظهور موحّد» (الدفعة ١٠): الصفوف تصعد بعد البطاقة الأولى مرة عند الظهور
                appeared = true
                await notificationVM.fetchNotifications(force: true)
                withAnimation(reduceMotion ? nil : DS.Anim.smooth) { hasLoaded = true }
            }
            .refreshable { await notificationVM.fetchNotifications(force: true) }
            .modifier(AdminSelfChildFlowModifier(flow: $selfChildFlow, missingChildren: missingSelfChildren))
    }

    // MARK: البيانات

    /// الطلبات التي ما زالت معلّقة (الإشعار يحتاج إجراء ما دام طلبه هنا)
    private var openRequestIds: Set<UUID> {
        var ids = Set<UUID>()
        let vm = adminRequestVM
        for list in [vm.deceasedRequests, vm.childAddRequests, vm.newsReportRequests, vm.photoSuggestionRequests,
                     vm.nameChangeRequests, vm.treeEditRequests, vm.joinApprovalRequests] {
            ids.formUnion(list.map(\.id))
        }
        ids.formUnion(vm.phoneChangeRequests.map(\.id))
        ids.formUnion(vm.contactMessages.filter { $0.status == ApprovalStatus.pending.rawValue }.map(\.id))
        ids.formUnion(newsVM.pendingNewsRequests.map(\.id))
        ids.formUnion(projectsVM.pendingProjects.map(\.id))
        for m in memberVM.allMembers where m.role == .pending { ids.insert(m.id) }
        return ids
    }

    private var allItems: [AdminNoticeItem] {
        let me = authVM.currentUser?.id
        let open = openRequestIds
        let canSms = authVM.canViewSystemSettings
        let canTopUp = canSms && sms.needsTopUp
        var list = store.derived
        // «الرسائل» رسائل خاصة — إشعارها لمن يراها في جدول السيرفر فقط (`inbox.messages`)
        let seesMessages = authVM.adminSees(.inboxMessages)
        for n in notificationVM.notifications {
            if !seesMessages && n.kind == NotificationKind.contactMessage.rawValue { continue }
            guard let category = AdminNotices.category(of: n, me: me) else { continue }
            var item = Self.item(n, category: category, open: open, canTopUp: canTopUp, canSms: canSms)
            if category == .changes {
                let isSelfChild = n.details?.selfChild == true
                // إضافة الابن: نصّ الإشعار (مَن أضاف مَن) بدل «قبل ← بعد»
                item.rich = AdminNoticeRich(sender: sender(n, style: AdminNoticeRoutes.style(n, category)),
                                            changes: isSelfChild ? [] : (n.details?.changes ?? []))
                if isSelfChild { applySelfChild(n, to: &item) } else { applyChangeAlert(n, to: &item) }
                // بلا تكرار (اختيار المالك ٢٠٢٦-١١-٠٦): العنوان نوع الحدث، والسطر الشخص، والصغير مَن فعل
                if n.details?.action != nil || isSelfChild {
                    item.title = AdminNoticeText.eventTitle(n)
                    let person = AdminNoticeText.subjectName(n, member: { memberVM.member(byId: $0) })
                    // مكان التغيير (شجرة النساء/العائلة) دائماً، ولو غاب الاسم
                    var parts = person.isEmpty ? [] : [person]
                    if !person.isEmpty, isSelfChild,
                       let year = AdminNoticeText.birthYear(n, member: { memberVM.member(byId: $0) }) {
                        parts.append(L10n.t("مواليد \(year)", "Born \(year)"))
                    }
                    if let tree = AdminNoticeText.treeLabel(n) { parts.append(tree) }
                    if !parts.isEmpty { item.subtitle = parts.joined(separator: " · ") }
                    item.meta = AdminNoticeText.actorLine(n, member: { memberVM.member(byId: $0) })
                }
            }
            list.append(item)
        }
        return list.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.date > b.date
        }
    }

    /// أدوات صفّ «تمت إضافة ابن». بعد حذف الابن يفرّغ السيرفر `subject_member_id` فيبقى الصفّ سجلّاً بلا أزرار.
    /// «راجعه» يحتاج إجراء ما دام غير مقروء (مثل «محاولات دخول مريبة»): السيرفر لا يحفظ حالة مراجعة
    private func applySelfChild(_ n: AppNotification, to item: inout AdminNoticeItem) {
        guard let childId = n.subjectMemberId else { return }
        let child = memberVM.member(byId: childId)
        let father = n.createdBy.flatMap { memberVM.member(byId: $0) }
        let review = n.details?.review == true
        let childFullName = child?.chainThreeName ?? PersonName.firstThree(n.details?.subject?.name ?? "")
        item.selfChild = AdminNoticeSelfChild(
            childId: childId,
            fatherId: n.createdBy,
            notificationId: n.id,
            childFirstName: child?.firstName ?? childFullName.split(separator: " ").first.map(String.init) ?? "",
            childFullName: childFullName,
            fatherName: father?.chainThreeName ?? (n.details?.actor?.name ?? n.details?.sender?.name).map(PersonName.firstThree) ?? "",
            review: review,
            canAlert: authVM.canSendNotifications && n.createdBy != nil,
            canDelete: authVM.canDeleteMembers && child?.role != .owner && childId != authVM.currentUser?.id)
        if review && !n.read { item.needsAction = true }
    }

    /// باقي «تغييرات الأعضاء»: زرّ «تنبيه» لمن غيّر البيانات إذا فيه خطأ (ليس لتعديلاتي أنا)
    private func applyChangeAlert(_ n: AppNotification, to item: inout AdminNoticeItem) {
        guard authVM.canSendNotifications, let actor = n.createdBy, actor != authVM.currentUser?.id else { return }
        let name = PersonName.firstThree(n.details?.subject?.name ?? "")
        item.selfChild = AdminNoticeSelfChild(
            childId: n.subjectMemberId ?? n.id,
            fatherId: actor,
            notificationId: n.id,
            childFirstName: n.subjectMemberId.flatMap { memberVM.member(byId: $0)?.firstName } ?? name,
            childFullName: name,
            fatherName: memberVM.member(byId: actor)?.chainThreeName
                ?? (n.details?.actor?.name ?? n.details?.sender?.name).map(PersonName.firstThree) ?? "",
            review: false,
            canAlert: true,
            canDelete: false,
            isGeneral: true)
    }

    /// أبناء أُضيفوا بعد آخر تحميل للأعضاء — يُجلبون ليعمل الملف والاسم وسنة الميلاد
    private var missingSelfChildren: [UUID] {
        notificationVM.notifications.compactMap { n in
            guard n.details?.selfChild == true, let id = n.subjectMemberId, memberVM.member(byId: id) == nil else { return nil }
            return id
        }
    }

    /// زرّ في صفّ «تمت إضافة ابن» — كل زرّ بصلاحيته، والصفّ لا يعرض ما لا يملكه الدور
    private func handleSelfChild(_ action: AdminSelfChildAction, _ notice: AdminNoticeSelfChild) {
        switch action {
        case .openProfile:
            Task {
                if memberVM.member(byId: notice.childId) == nil { await memberVM.fetchSingleMember(id: notice.childId) }
                selfChildFlow.sheet = AdminMemberSheetContext(ids: [notice.childId], start: 0)
                await notificationVM.markNotificationAsRead(id: notice.notificationId)
            }
        case .alert:
            guard notice.canAlert else { return }
            selfChildFlow.alert = notice
        case .delete:
            guard notice.canDelete else { return }
            selfChildFlow.deleting = notice
        }
    }

    private static func item(_ n: AppNotification, category: AdminNotices.Category, open: Set<UUID>,
                             canTopUp: Bool, canSms: Bool) -> AdminNoticeItem {
        let style = AdminNoticeRoutes.style(n, category)
        var item = AdminNoticeItem(id: n.id.uuidString, category: category, date: n.createdDate,
                                   icon: style.icon, tint: style.tint, title: AdminNoticeText.shortenQuotedNames(n.title),
                                   subtitle: AdminNoticeText.shortenQuotedNames(n.body),
                                   isUnread: !n.read, notificationId: n.id)
        item.tone = AdminNoticeTone.of(n, category)
        switch category {
        case .action where n.kind == AdminNotices.smsSuspicious:
            // محاولات دخول مريبة: تحتاج إجراء ما دامت غير مقروءة، و«راجع» يبقى ← «طلبات رمز الدخول»
            item.needsAction = !n.read
            if canSms {
                item.button = L10n.t("راجع", "Review")
                item.target = .smsAttempts
            }
        case .action:
            // معرّف الطلب معروف: يحتاج إجراء ما دام معلّقاً؛ وإلا ما دام غير مقروء
            let rid = AdminNotices.requestId(of: n)
            item.needsAction = rid.map(open.contains) ?? !n.read
            if item.needsAction {
                item.button = L10n.t("مراجعة", "Review")
                item.target = n.kind == NotificationKind.contactMessage.rawValue
                    ? .messages : .inbox(rid.flatMap { open.contains($0) ? $0 : nil })
            }
        case .system:
            if canTopUp, n.kind == AdminNotices.smsBalanceLow {
                item.button = L10n.t("شحن الرصيد", "Top up")
                item.target = .sms
            }
        case .team, .changes:
            break
        }
        return item
    }

    private func matches(_ item: AdminNoticeItem, _ f: Filter) -> Bool {
        switch f {
        case .all:    return true
        case .action: return item.needsAction
        case .changes: return item.category == .changes
        case .team:   return item.category == .team
        case .system: return item.category == .system
        }
    }

    private func visible(_ items: [AdminNoticeItem]) -> [AdminNoticeItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        // البحث الدقيق الواحد (`NameSearch`): كل كلمة بداية كلمة بالترتيب

        return items.filter { item in
            matches(item, filter) && (q.isEmpty || NameSearch.matches(query: q, any: [item.title, item.subtitle, item.meta ?? ""]))
        }
    }

    /// قسم في الخطّ الزمني: «يحتاج إجراء الآن» (الحالات المشتقة — ليست أحداثاً بوقت) ثم الأيام: اليوم · أمس · التاريخ
    private struct NoticeSection: Identifiable {
        let id: String
        let title: String
        let items: [AdminNoticeItem]
    }

    /// ترتيب الصفحة (طلب المالك ٢٠٢٦-١٠-٢٤ «ابي ارتبها»): ما يحتاج إجراء الآن أولاً بقسمه، ثم كل يوم بطاقة واحدة
    private func sections(_ items: [AdminNoticeItem]) -> [NoticeSection] {
        let pinned = items.filter(\.pinned)
        var list: [NoticeSection] = []
        if !pinned.isEmpty {
            list.append(NoticeSection(id: "now", title: L10n.t("يحتاج إجراء الآن", "Needs action now"), items: pinned))
        }
        for day in DSDayBuckets.group(items.filter { !$0.pinned }, date: \.date) {
            list.append(NoticeSection(id: "day.\(day.day.timeIntervalSince1970)", title: day.title, items: day.items))
        }
        return list
    }

    // MARK: الرأس

    private func header(_ items: [AdminNoticeItem]) -> AdminPageHeader {
        let unread = items.filter(\.isUnread).compactMap(\.notificationId)
        let hasRows = items.contains { $0.notificationId != nil }
        var actions: [AdminPageAction] = []
        if !isSelecting && !unread.isEmpty {
            actions.append(AdminPageAction(symbol: "envelope.open", label: L10n.t("قراءة الكل", "Mark all read"),
                                           tap: .action {
                                               Task { await notificationVM.markNotificationsAsRead(ids: Set(unread)) }
                                           }))
        }
        if isSelecting || hasRows {
            actions.append(AdminPageAction(symbol: isSelecting ? "checkmark.circle.fill" : "checkmark.circle",
                                           label: isSelecting ? L10n.t("إلغاء التحديد", "Cancel selection")
                                                              : L10n.t("تحديد", "Select"),
                                           dot: isSelecting,
                                           tap: .action {
                                               withAnimation(DS.Anim.quick) {
                                                   isSelecting.toggle()
                                                   if !isSelecting { selectedIds.removeAll() }
                                               }
                                           }))
        }
        var counts: [Filter: Int] = [:]
        for item in items {
            for f in Filter.allCases where matches(item, f) { counts[f, default: 0] += 1 }
        }
        let chips = Filter.allCases.map { f in
            // بلا رموز: الشرائح الأربع في سطر واحد
            AdminPageChip(id: f.rawValue, title: f.title, count: (counts[f] ?? 0) > 0 ? counts[f] : nil,
                          selected: filter == f) {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) { filter = f }
            }
        }
        return AdminPageHeader(back: opener ?? L10n.t("اليوم", "Today"), title: Self.title,
                               glyph: "bell.badge", actions: actions, chips: chips)
    }

    // MARK: المحتوى

    private func leadCard(_ items: [AdminNoticeItem]) -> AnyView {
        if !hasLoaded && items.isEmpty {
            return AnyView(AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الإشعارات…", "Loading notifications…"))))
        }
        if items.isEmpty {
            return AnyView(AdminPageStateCard(.empty(L10n.t("لا توجد إشعارات للإدارة", "No admin notifications"),
                                                     message: L10n.t("الطلبات الجديدة وتعديلات الفريق تظهر هنا",
                                                                     "New requests and team changes show up here"))))
        }
        return AnyView(DSSearchField(text: $searchText,
                                     placeholder: L10n.t("ابحث في الإشعارات والتعديلات…", "Search notifications and changes…"))
            .adminCard(padding: DS.Spacing.md))
    }

    @ViewBuilder
    private func rows(_ all: [AdminNoticeItem]) -> some View {
        if !all.isEmpty {
            let shown = visible(all)
            if isSelecting {
                AnyView(selectionBar(shown))
                    .adminPageRow(top: DS.Hub.stackSpacing, bottom: DS.Spacing.xxs)
            }
            if shown.isEmpty {
                AnyView(noResults)
                    .adminPageRow(top: DS.Hub.stackSpacing)
            } else {
                // خطّ زمني (اختيار المالك ٢٠٢٦-١١-٠٦ «ب»): كل قسم عنوانه بحلقة على الخطّ، ثم كل إشعار بطاقته بنقطة نوعه —
                // الخطّ متّصل من أول عنوان حتى آخر بطاقة؛ السحب لكل بطاقة
                let list = sections(shown)
                let lastId = list.last?.items.last?.id
                ForEach(Array(list.enumerated()), id: \.element.id) { index, section in
                    AdminTimelineHeader(title: section.title, count: section.items.count, isFirst: index == 0)
                        .dsCardCascade(1, appeared: appeared)
                        .adminPageRow(top: 0, bottom: 0)
                    ForEach(section.items) { item in
                        row(item, isLast: item.id == lastId)
                    }
                }
            }
        }
    }

    private func row(_ item: AdminNoticeItem, isLast: Bool) -> some View {
        let picked = item.notificationId.map(selectedIds.contains) ?? false
        return AdminNoticeTimelineRow(item: item, selecting: isSelecting, picked: picked, isLast: isLast,
                                      onTap: { tap(item) }, onSelfChild: handleSelfChild)
            .dsCardCascade(1, appeared: appeared)
            .adminPageRow(top: 0, bottom: 0)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if let id = item.notificationId {
                    Button(role: .destructive) {
                        Task { await notificationVM.deleteNotification(id: id) }
                    } label: {
                        Label(L10n.t("حذف", "Delete"), systemImage: "trash.fill")
                    }
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let id = item.notificationId, item.isUnread {
                    Button {
                        Task { await notificationVM.markNotificationAsRead(id: id) }
                    } label: {
                        Label(L10n.t("مقروء", "Read"), systemImage: "envelope.open")
                    }
                    .tint(DS.Color.primaryFill)
                }
            }
    }

    /// الضغط: في التحديد يختار، وإلا يفتح التفاصيل ويعلّم الإشعار مقروءاً
    private func tap(_ item: AdminNoticeItem) {
        guard let id = item.notificationId else { return }
        if isSelecting {
            withAnimation(DS.Anim.quick) {
                if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
            }
            return
        }
        let n = notificationVM.notifications.first { $0.id == id }
        detail = n
        if item.isUnread { Task { await notificationVM.markNotificationAsRead(id: id) } }
    }

    private var noResults: some View {
        let searching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return DSEmptyView(searching ? L10n.t("لا توجد نتائج", "No results") : L10n.t("لا شيء هنا الآن", "Nothing here now"),
                           message: searching ? L10n.t("جرّب كلمة أخرى", "Try another word")
                                              : L10n.t("لا شيء في «\(filter.title)»", "Nothing in \(filter.title)"),
                           actionTitle: filter == .all ? nil : L10n.t("عرض الكل", "Show all"),
                           actionIcon: Filter.all.icon, style: .compact,
                           action: filter == .all ? nil : { withAnimation(DS.Anim.snappy) { filter = .all } })
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity)
            .adminCard()
    }

    /// شريط التحديد: تحديد الكل · العدد · مقروء · حذف
    private func selectionBar(_ shown: [AdminNoticeItem]) -> some View {
        let all = Set(shown.compactMap(\.notificationId))
        return HStack(spacing: DS.Spacing.sm) {
            DSChipButton(L10n.t("تحديد الكل", "Select all"), icon: "checkmark.circle.fill") {
                withAnimation(DS.Anim.quick) { selectedIds = selectedIds == all ? [] : all }
            }
            Text(L10n.t("\(selectedIds.count) محدّد", "\(selectedIds.count) selected"))
                .dsFieldFont(.chip)
                .foregroundColor(DS.Color.fieldValue)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            DSChipButton(L10n.t("مقروء", "Read"), icon: "envelope.open.fill") {
                let ids = selectedIds
                withAnimation(DS.Anim.quick) { selectedIds.removeAll(); isSelecting = false }
                Task { await notificationVM.markNotificationsAsRead(ids: ids) }
            }
            .disabled(selectedIds.isEmpty)
            .opacity(selectedIds.isEmpty ? DS.Opacity.disabled : 1)
            DSChipButton(L10n.t("حذف", "Delete"), icon: "trash.fill", tint: DS.Color.error) {
                showDeleteConfirm = true
            }
            .disabled(selectedIds.isEmpty)
            .opacity(selectedIds.isEmpty ? DS.Opacity.disabled : 1)
        }
        .adminCard(padding: DS.Spacing.md)
    }

    private func deleteSelected() {
        let ids = selectedIds
        withAnimation(DS.Anim.quick) { selectedIds.removeAll(); isSelecting = false }
        Task { await notificationVM.deleteNotifications(ids: ids) }
    }

    /// المرسل — المصدر الواحد مع مركز الإشعارات (الصفوف القديمة: اسم المنفّذ أو «الإدارة»)
    private func sender(_ n: AppNotification, style: (icon: String, tint: Color)) -> NotificationSenderInfo {
        let legacy = n.createdBy.flatMap { memberVM.member(byId: $0) }?.shortFullName ?? L10n.t("الإدارة", "Admin")
        return NotificationSenderInfo.resolve(n, isStaff: true, kindIcon: style.icon, legacyName: legacy,
                                              member: { memberVM.member(byId: $0) })
    }

    private func categoryTitle(_ n: AppNotification, _ category: AdminNotices.Category) -> (title: String, icon: String) {
        switch category {
        case .action:
            return (AdminNotices.securityKinds.contains(n.kind) ? L10n.t("تنبيه أمني", "Security alert")
                                                                : L10n.t("طلب", "Request"),
                    Filter.action.icon)
        case .changes: return (Filter.changes.title, Filter.changes.icon)
        case .team:    return (Filter.team.title, Filter.team.icon)
        case .system:  return (Filter.system.title, Filter.system.icon)
        }
    }

    private func detailBox(_ n: AppNotification) -> AnyView {
        let category = AdminNotices.category(of: n, me: authVM.currentUser?.id) ?? .system
        let style = AdminNoticeRoutes.style(n, category)
        let cat = categoryTitle(n, category)
        // تغييرات الأعضاء ونشاط الفريق: المربّع «بلا تكرار» و«فيه خطأ؟» داخله (اختيار المالك ٢٠٢٦-١١-٠٦)؛ الطلبات والنظام
        // يبقون في مربّع الإشعار بقرارهم
        if category == .changes || category == .team {
            let notice = allItems.first { $0.notificationId == n.id }?.selfChild
            return AnyView(AdminNoticeDetailBox(
                notification: n, categoryTitle: cat.title, icon: style.icon, notice: notice,
                onClose: { detail = nil },
                onOpenProfile: { id in
                    detail = nil
                    afterBox { selfChildFlow.sheet = AdminMemberSheetContext(ids: [id], start: 0) }
                },
                onDelete: { notice in
                    detail = nil
                    afterBox { selfChildFlow.deleting = notice }
                })
                .environmentObject(memberVM)
                .environmentObject(notificationVM)
                // «طلب تغيير الصورة» تحت بطاقة الصورة يقرأ الصلاحية
                .environmentObject(authVM))
        }
        return AnyView(requestDetailBox(n, category: category, style: style, cat: cat))
    }

    /// بعد إغلاق المربّع — لا تتداخل حركتاهما
    private func afterBox(_ run: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.boxHandoff, execute: run)
    }

    private func requestDetailBox(_ n: AppNotification, category: AdminNotices.Category,
                                  style: (icon: String, tint: Color), cat: (title: String, icon: String)) -> some View {
        let subject = NotificationDetailParts.subjectMember(n, member: { memberVM.member(byId: $0) })
        let body = n.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return NotificationDetailBox(
            notification: n,
            isStaff: true,
            sender: sender(n, style: style),
            kindLabel: cat.title,
            kindIcon: style.icon,
            time: AdminNoticeRow.relative(n.createdDate),
            quote: body.isEmpty ? nil : AnyView(Text(body).dsFont(.body).foregroundColor(DS.Color.textPrimary)),
            changes: n.details?.changes ?? [],
            subjectMember: subject,
            subjectName: n.details?.subject?.name ?? subject?.shortFullName,
            onClose: { detail = nil },
            onOpenProfile: { detail = nil },
            onOpenRequest: { rid in
                detail = nil
                // «الوارد» على الطلب نفسه — نفس مسار نقر الإشعار في «اليوم»
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    NotificationCenter.default.post(name: .openAdminReviewForKind, object: nil,
                                                    userInfo: ["kind": n.kind, "request_id": rid.uuidString])
                }
            },
            onOpenNews: { nid in
                detail = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    NotificationCenter.default.post(name: .openNewsPost, object: nil, userInfo: ["id": nid])
                }
            }
        )
        .environmentObject(authVM)
        .environmentObject(memberVM)
        .environmentObject(adminRequestVM)
    }
}

// MARK: - الوقت

/// «قبل 5 دقائق» — الصفّ نفسه `AdminNoticeTimelineRow` (AdminNoticeTimeline.swift)
enum AdminNoticeRow {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static func relative(_ date: Date) -> String {
        formatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
