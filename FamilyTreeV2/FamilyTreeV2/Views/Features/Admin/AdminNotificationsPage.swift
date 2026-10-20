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
    enum Category: String { case action, team, system }

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
    static let systemKinds: Set<String> = [smsBalanceLow]
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
        // ما يخصّني أنا (تعديل على بياناتي، طلب عنّي) يبقى في «الإشعارات» — كما كان
        if let me, n.subjectMemberId == me, n.createdBy != me { return nil }
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
    let title: String
    let subtitle: String
    var isUnread = false
    var notificationId: UUID? = nil
    var needsAction = false
    var button: String? = nil
    var target: AdminNoticeTarget = .none
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
                                        subtitle: lines.joined(separator: "\n"), needsAction: true))
        }
        if authVM.isAdmin {
            for m in unannounced {
                list.append(AdminNoticeItem(id: "derived.death.\(m.id.uuidString)", category: .action, date: now, pinned: true,
                                            icon: NewsTypeHelper.icon(for: "وفاة"), tint: DS.Color.slate,
                                            title: L10n.t("وفاة لم يُعلن عنها", "Death not announced"),
                                            subtitle: [m.shortFullName, m.deathDate.map { String($0.prefix(10)) }]
                                                .compactMap { $0 }.joined(separator: " · "),
                                            needsAction: true, button: L10n.t("إعلان", "Announce"), target: .occasions))
            }
        }
        if authVM.currentUser?.role == .monitor, let n = treeIssues, n > 0 {
            list.append(AdminNoticeItem(id: "derived.tree", category: .action, date: now, pinned: true,
                                        icon: "stethoscope", tint: DS.Color.warning,
                                        title: L10n.t("مشكلات الشجرة: \(n) تحتاج مراجعة", "Tree problems: \(n) to review"),
                                        subtitle: L10n.t("غير مرتبط بأب، بلا اسم، ارتباط أب غير صالح",
                                                         "Unlinked, unnamed or invalid father links"),
                                        needsAction: true, button: L10n.t("مراجعة", "Review"), target: .treeProblems))
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
        case all, action, team, system
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:    return L10n.t("الكل", "All")
            case .action: return L10n.t("يحتاج إجراء", "Needs action")
            case .team:   return L10n.t("نشاط الفريق", "Team activity")
            case .system: return L10n.t("النظام", "System")
            }
        }
        var icon: String {
            switch self {
            case .all:    return "square.grid.2x2.fill"
            case .action: return "exclamationmark.circle.fill"
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
            .dsCenterBox(item: $detail) { n in
                AnyView(detailBox(n))
            }
            .task {
                // «ظهور موحّد» (الدفعة ١٠): الصفوف تصعد بعد البطاقة الأولى مرة عند الظهور
                appeared = true
                await notificationVM.fetchNotifications(force: true)
                withAnimation(reduceMotion ? nil : DS.Anim.smooth) { hasLoaded = true }
            }
            .refreshable { await notificationVM.fetchNotifications(force: true) }
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
        for n in notificationVM.notifications {
            guard let category = AdminNotices.category(of: n, me: me) else { continue }
            list.append(Self.item(n, category: category, open: open, canTopUp: canTopUp, canSms: canSms))
        }
        return list.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.date > b.date
        }
    }

    private static func item(_ n: AppNotification, category: AdminNotices.Category, open: Set<UUID>,
                             canTopUp: Bool, canSms: Bool) -> AdminNoticeItem {
        let style = AdminNoticeRoutes.style(n, category)
        var item = AdminNoticeItem(id: n.id.uuidString, category: category, date: n.createdDate,
                                   icon: style.icon, tint: style.tint, title: n.title, subtitle: n.body,
                                   isUnread: !n.read, notificationId: n.id)
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
            if canTopUp {
                item.button = L10n.t("شحن الرصيد", "Top up")
                item.target = .sms
            }
        case .team:
            break
        }
        return item
    }

    private func matches(_ item: AdminNoticeItem, _ f: Filter) -> Bool {
        switch f {
        case .all:    return true
        case .action: return item.needsAction
        case .team:   return item.category == .team
        case .system: return item.category == .system
        }
    }

    private func visible(_ items: [AdminNoticeItem]) -> [AdminNoticeItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = q.isEmpty ? "" : ArabicTextNormalizer.normalizeForSearch(q)
        return items.filter { item in
            matches(item, filter) && (needle.isEmpty
                || ArabicTextNormalizer.normalizeForSearch(item.title).contains(needle)
                || ArabicTextNormalizer.normalizeForSearch(item.subtitle).contains(needle))
        }
    }

    /// الأيام بالترتيب: اليوم · أمس · التاريخ
    private func days(_ items: [AdminNoticeItem]) -> [(title: String, items: [AdminNoticeItem])] {
        var order: [String] = []
        var map: [String: [AdminNoticeItem]] = [:]
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar_KW@numbers=latn" : "en_US")
        f.dateFormat = "EEEE d MMMM"
        for item in items {
            let key: String
            if cal.isDateInToday(item.date) { key = L10n.t("اليوم", "Today") }
            else if cal.isDateInYesterday(item.date) { key = L10n.t("أمس", "Yesterday") }
            else { key = f.string(from: item.date) }
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(item)
        }
        return order.map { ($0, map[$0] ?? []) }
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
                               subtitle: L10n.t("الطلبات ونشاط الفريق وتنبيهات النظام — الأحدث أولاً",
                                                "Requests, team activity and system alerts — newest first"),
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
                ForEach(days(shown), id: \.title) { day in
                    AdminSectionLabel(title: day.title, trailing: "\(day.items.count)")
                        .dsCardCascade(1, appeared: appeared)
                        .adminPageRow(top: DS.Hub.stackSpacing, bottom: 0)
                    ForEach(day.items) { item in
                        row(item)
                    }
                }
            }
        }
    }

    private func row(_ item: AdminNoticeItem) -> some View {
        let picked = item.notificationId.map(selectedIds.contains) ?? false
        return AdminNoticeRow(item: item, selecting: isSelecting, picked: picked, onTap: { tap(item) })
            .dsCardCascade(1, appeared: appeared)
            .adminPageRow()
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
        detail = notificationVM.notifications.first { $0.id == id }
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

    private func detailBox(_ n: AppNotification) -> some View {
        let category = AdminNotices.category(of: n, me: authVM.currentUser?.id) ?? .system
        let style = AdminNoticeRoutes.style(n, category)
        let kind: Filter = category == .action ? .action : category == .team ? .team : .system
        let actionTitle = AdminNotices.securityKinds.contains(n.kind) ? L10n.t("تنبيه أمني", "Security alert") : L10n.t("طلب", "Request")
        return AdminNoticeDetailBox(item: n, icon: style.icon, tint: style.tint,
                                    categoryTitle: category == .action ? actionTitle : kind.title,
                                    categoryIcon: kind.icon)
            .environmentObject(memberVM)
    }
}

// MARK: - الصفّ

/// صفّ بطاقة: مربّع النوع (ونقطة «جديد») · العنوان · السطر · الوقت — وزرّ البيت الواحد لما يحتاج إجراء
struct AdminNoticeRow: View {
    let item: AdminNoticeItem
    let selecting: Bool
    let picked: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            if selecting && item.notificationId != nil {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .dsGlyph(DS.Glyph.xl, weight: .regular)
                    .foregroundColor(picked ? AppSection.admin.ink : DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            AdminIconSquare(symbol: item.icon, tint: item.tint)
                .overlay(alignment: .topTrailing) {
                    if item.isUnread {
                        Circle()
                            .fill(DS.Hub.bellDot)
                            .frame(width: DS.Icon.legendDot, height: DS.Icon.legendDot)
                            .overlay(Circle().strokeBorder(DS.Color.surface, lineWidth: DS.Border.widthBold))
                            .offset(x: L10n.isArabic ? -DS.Spacing.xxs : DS.Spacing.xxs, y: -DS.Spacing.xxs)
                    }
                }
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: item.title)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.subtitle.isEmpty {
                    Text(verbatim: item.subtitle)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(item.pinned ? 3 : 1)
                }
                if !item.pinned {
                    Text(verbatim: Self.relative(item.date))
                        .dsFont(.caption)
                        .foregroundColor(item.isUnread ? AppSection.admin.ink : DS.Color.textTertiary)
                }
            }
            Spacer(minLength: 0)
            if let button = item.button, !selecting {
                AdminTapWrap(tap: .page { AdminNoticeRoutes.page(item.target) },
                             label: AnyView(AdminPillLabel(title: button, style: item.pinned ? .navy : .soft)
                                .dsTapArea(width: DS.Icon.tapTarget, height: DS.Hub.pillHeight)),
                             accessibilityLabel: "\(button): \(item.title)")
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Hub.cardPadding)
        .padding(.vertical, DS.Spacing.md)
        .adminCard(padding: nil)
        .overlay {
            if selecting && picked {
                RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous)
                    .strokeBorder(AppSection.admin.ink.opacity(DS.Opacity.selectedStroke), lineWidth: DS.Border.widthBold)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        // بزرّ: يبقى الزرّ عنصراً مستقلاً للقارئ الصوتي
        .accessibilityElement(children: item.button == nil || selecting ? .combine : .contain)
        .accessibilityValue(item.isUnread ? L10n.t("جديد", "New") : "")
        .accessibilityAddTraits(item.notificationId != nil ? .isButton : [])
        .accessibilityAddTraits(selecting && picked ? .isSelected : [])
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private static func relative(_ date: Date) -> String {
        formatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - مربّع التفاصيل (كان «تفاصيل الحركة» في سجل التعديلات)

/// تفاصيل إشعار واحد: ما تغيّر (قبل ← بعد)، النص، ومعلومات السجل (التصنيف، الوقت، تخصّ، نفّذها).
/// مربّع عرض بنفس تصميم المربّعات: رأس بلون النوع، أقسام تدخل تباعاً، و«إغلاق» أسفل المربّع.
struct AdminNoticeDetailBox: View {
    let item: AppNotification
    let icon: String
    let tint: Color
    let categoryTitle: String
    let categoryIcon: String

    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss

    private var subject: FamilyMember? { item.subjectMemberId.flatMap(memberVM.member(byId:)) }
    private var actor: FamilyMember? { item.createdBy.flatMap(memberVM.member(byId:)) }

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return f
    }()
    private var fullDate: String {
        Self.fullFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return Self.fullFormatter.string(from: item.createdDate)
    }

    private var changes: [AppNotification.NotificationDetails.ChangeEntry] { item.details?.changes ?? [] }

    /// لون الرأس — درجة داكنة من لون النوع حتى يُقرأ النص الأبيض
    private var headerTint: Color {
        if tint == DS.Color.error { return DS.Color.error }
        if tint == DS.Color.slate || tint == DS.Color.textSecondary { return DS.Color.textSecondary }
        if tint == DS.Color.success || tint == DS.Color.palm { return DS.Color.composerProject }
        if tint == DS.Color.warning || tint == DS.Color.accent { return DS.Color.composerLibrary }
        return DS.Color.actionNavy
    }

    private var bodyIndex: Int { changes.isEmpty ? 0 : 1 }
    private var infoIndex: Int { bodyIndex + (item.body.isEmpty ? 0 : 1) }

    var body: some View {
        DSComposer(
            title: item.title,
            subtitle: categoryTitle,
            icon: icon,
            tint: headerTint,
            actionTitle: "",
            showsAction: false,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { dismiss() }
        ) {
            if !changes.isEmpty { changesSection }
            if !item.body.isEmpty { bodySection }
            infoSection
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private var changesSection: some View {
        DSComposerSection(title: L10n.t("ما تغيّر", "What changed"), icon: "arrow.left.arrow.right",
                          tint: DS.Color.accent, trailing: "\(changes.count)", index: 0) {
            VStack(spacing: DS.Spacing.sm) {
                ForEach(changes) { ch in AdminNoticeChangeLine(change: ch) }
            }
        }
    }

    private var bodySection: some View {
        DSComposerSection(title: L10n.t("التفاصيل", "Details"), icon: "text.alignright",
                          tint: AppSection.admin.ink, index: bodyIndex) {
            Text(item.body)
                .dsFieldFont(.body)
                .foregroundColor(DS.Color.fieldValue)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsRowBox()
        }
    }

    private var infoSection: some View {
        DSComposerSection(title: L10n.t("معلومات السجل", "Record info"), icon: "info.circle.fill",
                          tint: DS.Color.textSecondary, index: infoIndex) {
            VStack(spacing: DS.Spacing.sm) {
                infoRow(icon: categoryIcon, tint: tint, L10n.t("التصنيف", "Category"), categoryTitle)
                infoRow(icon: "calendar.badge.clock", tint: DS.Color.warning, L10n.t("الوقت", "Time"), fullDate)
                if let subject {
                    infoRow(icon: "person.fill", tint: AppSection.admin.ink, L10n.t("تخصّ", "About"), subject.shortFullName)
                }
                if let actor {
                    infoRow(icon: "person.fill.checkmark", tint: DS.Color.success, L10n.t("نفّذها", "By"), actor.shortFullName)
                }
            }
        }
    }

    private func infoRow(icon: String, tint: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(label)
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(value)
                    .dsFieldFont(.body)
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .dsRowBox()
        .accessibilityElement(children: .combine)
    }
}

/// سطر «ما تغيّر»: اسم الحقل + القيمة قبل ← بعد (والصور مصغّرات)
private struct AdminNoticeChangeLine: View {
    let change: AppNotification.NotificationDetails.ChangeEntry

    private var isPhoto: Bool {
        change.field == "avatar_url" || change.field == "cover_url" || change.field == "photo_url"
    }

    private func display(_ v: String?) -> String {
        let t = (v ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? L10n.t("بلا", "None") : t
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            DSFieldIcon(name: isPhoto ? "photo.fill" : "pencil", tint: DS.Color.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(AppNotification.NotificationDetails.localizedFieldName(change.field))
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                if isPhoto {
                    HStack(spacing: DS.Spacing.md) {
                        photoThumb(change.before, label: L10n.t("قبل", "Before"), faded: true)
                        arrow
                        photoThumb(change.after, label: L10n.t("بعد", "After"), faded: false)
                        Spacer(minLength: 0)
                    }
                } else {
                    HStack(spacing: DS.Spacing.xsm) {
                        Text(display(change.before))
                            .dsFont(.callout)
                            .foregroundColor(DS.Color.textTertiary)
                            .strikethrough(true, color: DS.Color.textTertiary.opacity(DS.Opacity.selectedStroke))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        arrow
                        Text(display(change.after))
                            .dsFont(.rowTitleCompact)
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.t("قبل: \(display(change.before))، بعد: \(display(change.after))",
                                               "Before: \(display(change.before)), after: \(display(change.after))"))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
    }

    private var arrow: some View {
        Image(systemName: L10n.isArabic ? "arrow.left" : "arrow.right")
            .dsGlyph(DS.Glyph.xs)
            .foregroundColor(DS.Color.textTertiary)
            .accessibilityHidden(true)
    }

    private func photoThumb(_ urlString: String?, label: String, faded: Bool) -> some View {
        let trimmed = (urlString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(spacing: DS.Spacing.xxs) {
            Group {
                if let url = URL(string: trimmed), !trimmed.isEmpty {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(DS.Color.surface)
                    }
                } else {
                    ZStack {
                        Rectangle().fill(DS.Color.surface)
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .dsGlyph(DS.Glyph.md, weight: .regular)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
            }
            .frame(width: DSBox.photoTile, height: DSBox.photoTile)
            .clipShape(RoundedRectangle(cornerRadius: DS.Icon.discRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Icon.discRadius, style: .continuous)
                    .strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke), lineWidth: DS.Border.width)
            )
            .opacity(faded ? DS.Opacity.disabled : 1)
            .accessibilityHidden(true)
            Text(label)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
        }
    }
}
