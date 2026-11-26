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
// إعادة تصميم الإدارة ٢٠٢٦-١١-٢٦ (الوحدة U18 — spec C.15، mock 11):
//   الرأس الداخلي (`AdminPage` .list): «‹ الإدارة» · «إشعارات الإدارة» · «تحديد» نصّاً في الطرف ← شرائح الفلتر بُعداً واحداً
//   تلتفّ (`DSFilterChips(style: .admin)`: الكل · يحتاج إجراء N · تغييرات الأعضاء · نشاط الفريق · النظام) ← البحث
//   (`DSSearchField(style: .admin)`) ← سطر «12 غير مقروء … قراءة الكل» ← «يحتاج إجراء الآن» ثم الأيام، كل قسم بطاقة من
//   صفوفها (مربّع النوع ٣٠، العنوان ١٥ — غير المقروء متوسط بنقطة ذهبية — والنص والوقت). زرّ البيت الواحد كحلي في طرف صفّ
//   «يحتاج إجراء الآن» («إعلان» · «مراجعة» · «راجع» · «شحن الرصيد» ← صفحة رسائل الدخول لا الرابط)، و«تمت إضافة ابن»:
//   «الملف» (ورقة العضو — بيت الحذف الوحيد، T4) و«تنبيه». السحب والضغط المطوّل «مقروء»/«حذف»، و«تحديد» ← شريط سفلي
//   «مقروء (3)» · «حذف (3)». الحالات: هيكل · «لا إشعارات» · «لا شيء في هذا الفلتر» · خطأ + «أعد المحاولة» (من
//   `AdminNoticeStore.health`). الكتابة كلها تمرّ بـ`DebugAdminProbe.dryRun` (`AdminNoticeWrites`، T0).
//   المنطق الخالص (الفلاتر، الأقسام، الحالات، سبب فشل الجلب) في `AdminNoticeLogic.swift` ويُفحص بلا محاكي.
//
// **مكان واحد لكل إشعار** (`AdminNotices.category`): ما يخصّ الإدارة لا يظهر في مركز الإشعارات العام للإدارة ولا في
// عدّاد جرسه — يبقى هناك ما يخصّ العضو نفسه (تعديل على بياناته، نتيجة طلبه، إعلانات العائلة ووفياتها، تحديث التطبيق،
// الإعجاب والتعليق، رسائل الإدارة له، ردود «مسار الموافقات» لصاحب الطلب). العضو العادي لا يتغيّر عنده شيء.

/// تصنيف إشعارات الإدارة — المصدر الواحد لمركز الإشعارات (يستبعدها) ولهذه الصفحة وعدّاد جرس «اليوم»
enum AdminNotices {
    /// `changes` = «تغييرات الأعضاء» (`member_change` من السيرفر، طلب المالك ٢٠٢٦-١١-٠١) — هنا وحدها، لا في المركز العام.
    /// النوع نفسه في `AdminNoticeLogic.swift` (منطق يُفحص بلا محاكي)
    typealias Category = AdminNoticeCategory

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
    /// «تمت إضافة ابن»: «الملف» (أو «راجع») و«تنبيه» في الصفّ، و«إرسال تنبيه» في التفاصيل — `AdminSelfChildNotice.swift`.
    /// لا «حذف» هنا (T4): بيت حذف العضو الوحيد ورقة العضو التي يفتحها «الملف»
    var selfChild: AdminNoticeSelfChild? = nil
    /// نوعه بالكلام للقارئ الصوتي (طلب · إضافة · تعديل · نظام)
    var tone: AdminNoticeTone = .system
    /// السطر الصغير: مَن فعل («أضافه أبوه فهد»، «بواسطة: فيصل»)
    var meta: String? = nil
}

/// محتوى الصفّ الجديد لـ«تغييرات الأعضاء»: المرسل («الإدارة · بواسطة: فلان» أو العضو) والتغييرات
struct AdminNoticeRich: Equatable {
    let sender: NotificationSenderInfo
    let changes: [AppNotification.NotificationDetails.ChangeEntry]
}

/// الحالات المشتقة («يحتاج إجراء» الآن) — يكتبها «اليوم» من حالته، ويقرؤها الجرس والصفحة.
/// وحال جلب الإشعارات (`AdminStoreHealth`، Autoplan note 2 — U18): أول جلب هيكل، والفشل «تعذّر التحميل» + «أعد المحاولة»
/// (أو القديم بـ«آخر تحديث»)، ويُسجَّل سببه. `-tmpFailStores notices` (T0) يصطنع الفشل.
@MainActor
final class AdminNoticeStore: ObservableObject {
    static let shared = AdminNoticeStore()
    @Published private(set) var derived: [AdminNoticeItem] = []
    /// «اليوم» نشر الحالات المشتقة في هذه الجلسة — قبلها لا تُعرض (لا حالة قديمة أبداً، spec C.15)
    @Published private(set) var derivedPublished = false
    /// حال جلب الإشعارات لهذه الصفحة (الشرائح وأعدادها والقائمة تقرأ منه)
    @Published private(set) var health: AdminStoreHealth = .idle

    func publish(_ items: [AdminNoticeItem]) {
        if !derivedPublished { derivedPublished = true }
        if items != derived { derived = items }
    }

    /// يلتقط أن نموذج العرض كتب القائمة أثناء الجلب — `fetchNotifications` يبتلع خطأه، فلا كتابة = فشل
    private final class DeliveryFlag { var delivered = false }

    /// نفس الجلب (`fetchNotifications(force: true)`) بحاله: الإلغاء (أُغلقت الصفحة) ليس فشلاً، والفشل يُسجَّل بسببه —
    /// `Log.error` لما يستحق البلاغ، و`Log.warning` للانقطاع والفشل المصطنع
    func load(using vm: NotificationViewModel) async {
        let before = health
        health = health.beginning()
        var injected = false
        do {
            try DebugAdminProbe.failIfAsked(.notices, hasLoaded: before.hasData)   // `-tmpFailStores notices`
        } catch {
            injected = true
        }
        var delivered = false
        if !injected {
            let flag = DeliveryFlag()
            let watch = vm.$notifications.dropFirst().sink { _ in flag.delivered = true }
            await vm.fetchNotifications(force: true)
            watch.cancel()
            delivered = flag.delivered
            if Task.isCancelled && !delivered {
                health = before
                return
            }
        }
        if let failure = AdminNoticeLogic.loadFailure(injected: injected,
                                                      featureAvailable: vm.notificationsFeatureAvailable,
                                                      delivered: delivered,
                                                      online: NetworkMonitor.shared.isConnected) {
            let line = "[AdminNoticeStore] load failed: \(failure.cause)"
            if failure.isExpected { Log.warning(line) } else { Log.error(line) }
            health = health.ending(success: false)
        } else {
            health = health.ending(success: true)
        }
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
    /// الصفحة التي يفتحها الزرّ — بقسمها في قائمة العنوان، وخلف حارس القسم (spec B.6: الدور الذي لا يرى القسم يرى رأسه
    /// و«ليس ضمن صلاحياتك» بلا بيانات). «شحن الرصيد» يفتح صفحة رسائل الدخول (بيت «شحن» — E.20)، لا الرابط
    static func page(_ target: AdminNoticeTarget) -> AnyView {
        let back = L10n.t("إشعارات الإدارة", "Admin notifications")
        switch target {
        case .none:
            return AnyView(EmptyView())
        case .inbox(let id):
            return AnyView(AdminAreaGate(area: .inbox) { AnyView(AdminAllRequestsView(focusId: id)) }.adminArea(.inbox))
        case .messages:
            return AnyView(AdminAreaGate(area: .inbox) { AnyView(AdminAllRequestsView(startsWithMessages: true)) }
                .adminArea(.inbox))
        case .occasions:
            return AnyView(AdminAreaGate(area: .occasions) { AnyView(AdminOccasionsPage()) }
                .adminArea(.occasions).adminBackTitle(back))
        case .sms:
            return AnyView(AdminAreaGate(area: .team) { AnyView(AdminSmsView(backTitle: back)) }.adminArea(.team))
        case .smsAttempts:
            return AnyView(AdminAreaGate(area: .team) { AnyView(SmsAttemptsListPage()) }
                .adminBackTitle(back).adminArea(.team))
        case .treeProblems:
            return AnyView(AdminAreaGate(area: .family) { AnyView(AdminMembersPage(chip: .problems)) }
                .adminArea(.family))
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

// MARK: - الكتابة

/// كل كتابة من «إشعارات الإدارة» ومربّعاتها — نفس نداءات نموذج العرض، وتمرّ بـ`DebugAdminProbe.dryRun` (T0): أثناء تجربة
/// دور تُسجَّل «DRY-RUN» ويُصطنع نجاحها محلياً بلا سيرفر
@MainActor
enum AdminNoticeWrites {
    /// «مقروء» (صفّ، تحديد، «قراءة الكل»، فتح الإشعار أو ملف الابن)
    static func markRead(_ ids: Set<UUID>, _ vm: NotificationViewModel) async {
        guard !ids.isEmpty else { return }
        if DebugAdminProbe.dryRun("admin notices mark read \(ids.count)") {
            for i in vm.notifications.indices where ids.contains(vm.notifications[i].id) {
                vm.notifications[i] = vm.notifications[i].withRead(true)
            }
            return
        }
        if ids.count == 1, let id = ids.first {
            await vm.markNotificationAsRead(id: id)
        } else {
            await vm.markNotificationsAsRead(ids: ids)
        }
    }

    /// «حذف» — كل عضو يحذف نسخته
    static func delete(_ ids: Set<UUID>, _ vm: NotificationViewModel) async {
        guard !ids.isEmpty else { return }
        if DebugAdminProbe.dryRun("admin notices delete \(ids.count)") {
            withAnimation(DS.Anim.quick) { vm.notifications.removeAll { ids.contains($0.id) } }
            return
        }
        if ids.count == 1, let id = ids.first {
            await vm.deleteNotification(id: id)
        } else {
            await vm.deleteNotifications(ids: ids)
        }
    }

    /// «تنبيه» لأب الابن المضاف أو لمن غيّر البيانات: إشعار «تنبيه من الإدارة» (`sendNotification`، `kind: admin`)
    static func sendAlert(title: String, body: String, to member: UUID, _ vm: NotificationViewModel) async -> Bool {
        if DebugAdminProbe.dryRun("admin notice alert to \(member)") { return true }
        return await vm.sendNotification(title: title, body: body, targetMemberIds: [member], kind: "admin")
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

    /// الفلاتر الخمسة (`AdminNoticeLogic.Filter`)
    typealias Filter = AdminNoticeLogic.Filter
    private typealias Logic = AdminNoticeLogic

    @State private var filter: Filter = .all
    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selectedIds: Set<UUID> = []
    @State private var showDeleteConfirm = false
    @State private var detail: AppNotification?
    /// «ظهور موحّد»: الأقسام تصعد مرة عند الظهور الأول (لا عند التحديث)
    @State private var appeared = false
    @State private var selfChildFlow = AdminSelfChildFlow()

    static var title: String { L10n.t("إشعارات الإدارة", "Admin notifications") }

    /// ما يُرسم، محسوباً مرة لكل رسم
    private struct Model {
        let all: [AdminNoticeItem]
        /// في اليد إشعارات تُعرض (من جلب ناجح أو سابق)
        let ready: Bool
        let counts: [Filter: Int]
        /// بعد الفلتر والبحث
        let visible: [AdminNoticeItem]
        /// أقسام `visible`: «يحتاج إجراء الآن» ثم الأيام
        let sections: [AdminNoticeLogic.Section]
        let unreadIds: Set<UUID>
        let searching: Bool

        /// صفوف لها إشعار (تُحدَّد وتُقرأ وتُحذف)
        var noticeIds: Set<UUID> { Set(all.compactMap(\.notificationId)) }
    }

    // حارس المكدس: الصفحة ثم المربّعات طبقات خلف `AnyView`، والقياس (`-tmpStackDepth`) على الجذر (≤ ٦٠٠ ك.ب)
    var body: some View {
        AnyView(layered)
            .debugStackProbe("AdminNotificationsPage", limitKB: DebugStackLimit.page)
    }

    private var layered: AnyView {
        let model = makeModel()
        return AnyView(dialogs(AnyView(page(model))))
    }

    private func page(_ m: Model) -> some View {
        AdminPage(header: header(m), lead: lead(m), layout: .list, content: AnyView(rows(m)),
                  updatedAt: m.ready ? store.health.lastGood : nil)
            .refreshable { await store.load(using: notificationVM) }
            // شريط التحديد السفلي — مثبّت، وآخر صفّ يبقى فوقه
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelecting {
                    AnyView(selectionBar(m))
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .task {
                appeared = true
                await store.load(using: notificationVM)
            }
    }

    /// تأكيد الحذف الجماعي، ومربّع التفاصيل، ومربّعات صفّ الابن
    private func dialogs(_ content: AnyView) -> some View {
        content
            .dsAlert(Logic.deleteQuestion(selectedIds.count), isPresented: $showDeleteConfirm, icon: "trash.fill") {
                Button(L10n.t("حذف", "Delete"), role: .destructive) { deleteSelected() }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.t("تُحذف من إشعاراتك أنت فقط. لا يمكن التراجع.",
                            "They're removed from your notifications only. This can't be undone."))
            }
            // تفاصيل الإشعار المربّع الغني بمنتصف الشاشة — نفسه في مركز الإشعارات (طلب المالك ٢٠٢٦-١١-٠١)
            .dsCenterBox(item: $detail, onBackgroundTap: { detail = nil }) { n in
                AnyView(detailBox(n))
            }
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
        // «إضافة قريبة» و«طلب حذف من الشجرة» (§9): يحتاج إجراء ما دام معلّقاً، و«مراجعة» تفتح مربّعه في «الوارد»
        ids.formUnion(vm.relativeAddRequests.map(\.id))
        ids.formUnion(vm.relativeRemoveRequests.map(\.id))
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
        // الحالات المشتقة بعد أن نشرها «اليوم» في هذه الجلسة فقط — لا حالة قديمة (spec C.15)
        var list = Logic.keepsDerived(published: store.derivedPublished) ? store.derived : []
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
        return list
    }

    private func makeModel() -> Model {
        let all = allItems
        let ready = Logic.ready(health: store.health, hasNotices: all.contains { $0.notificationId != nil })
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        // البحث الدقيق الواحد (`NameSearch`): كل كلمة بداية كلمة بالترتيب
        let visible = all.filter { item in
            Logic.matches(Self.fact(item), filter)
                && (q.isEmpty || NameSearch.matches(query: q, any: [item.title, item.subtitle, item.meta ?? ""]))
        }
        return Model(all: all, ready: ready, counts: Logic.counts(all.map { Self.fact($0) }), visible: visible,
                     sections: Logic.sections(visible.map { Self.fact($0) }),
                     unreadIds: Set(all.filter(\.isUnread).compactMap(\.notificationId)),
                     searching: !q.isEmpty)
    }

    private static func fact(_ item: AdminNoticeItem) -> AdminNoticeLogic.Fact {
        AdminNoticeLogic.Fact(category: item.category, needsAction: item.needsAction, pinned: item.pinned,
                              unread: item.isUnread, date: item.date)
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
            canAlert: authVM.canSendNotifications && n.createdBy != nil)
        if review && !n.read { item.needsAction = true }
    }

    /// باقي «تغييرات الأعضاء»: «إرسال تنبيه» في التفاصيل لمن غيّر البيانات إذا فيه خطأ (ليس لتعديلاتي أنا)
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
                await AdminNoticeWrites.markRead([notice.notificationId], notificationVM)
            }
        case .alert:
            guard notice.canAlert else { return }
            selfChildFlow.alert = notice
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
            // «شحن الرصيد» ← صفحة رسائل رمز الدخول (بيت «شحن»)، لا رابط الشحن مباشرة (spec E.20)
            if canTopUp, n.kind == AdminNotices.smsBalanceLow {
                item.button = L10n.t("شحن الرصيد", "Top up")
                item.target = .sms
            }
        case .team, .changes:
            break
        }
        return item
    }

    // MARK: الرأس

    /// «‹ الإدارة» · «إشعارات الإدارة» · «تحديد» نصّاً في الطرف (spec C.15، mock 11) — «قراءة الكل» فوق القائمة
    private func header(_ m: Model) -> AdminPageHeader {
        var actions: [AdminPageAction] = []
        if isSelecting || (m.ready && !m.noticeIds.isEmpty) {
            actions.append(AdminPageAction(symbol: "checkmark.circle",
                                           label: isSelecting ? L10n.t("إلغاء", "Cancel") : L10n.t("تحديد", "Select"),
                                           tap: .action { toggleSelect() },
                                           textOnly: true))
        }
        return AdminPageHeader(back: Logic.backTitle(opener), title: Self.title, actions: actions)
    }

    // MARK: فوق القائمة

    /// الشرائح (تلتفّ) ← البحث ← «12 غير مقروء … قراءة الكل». مع التحميل تمسك مكانها (بلا أعداد)، ولا تظهر فوق «لا
    /// إشعارات» ولا فوق خطأ بلا بيانات
    private func lead(_ m: Model) -> AnyView? {
        guard Logic.showsFilters(ready: m.ready, health: store.health, total: m.all.count) else { return nil }
        let options = Filter.allCases.map { f in
            DSFilterOption(id: f, title: f.title, count: Logic.chipCount(f, counts: m.counts, ready: m.ready))
        }
        let unread = m.unreadIds
        let showsCaption = m.ready && !unread.isEmpty && !isSelecting
        return AnyView(VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSFilterChips(options: options, selection: $filter, style: .admin)
            DSSearchField(text: $searchText, placeholder: L10n.t("ابحث في الإشعارات", "Search notifications"),
                          style: .admin)
            if showsCaption {
                AdminNoticeCaption(unread: unread.count) { markRead(unread) }
            }
        })
    }

    // MARK: القائمة

    /// صفوف `List`: الحالة (هيكل/خطأ/فارغ) أو الأقسام — كل قسم عنوانه ثم صفوفه، وكل صفّ جزء من بطاقة قسمه
    @ViewBuilder
    private func rows(_ m: Model) -> some View {
        let state = Logic.body(ready: m.ready, health: store.health, total: m.all.count, shown: m.visible.count,
                               searching: m.searching)
        if Logic.showsRefreshError(ready: m.ready, health: store.health, total: m.all.count) {
            // التحديث فشل والإشعارات القديمة باقية تحته
            AnyView(AdminPageStateCard(.error(L10n.t("تعذّر تحديث الإشعارات", "Couldn't refresh notifications"),
                                              message: L10n.t("تعرض آخر إشعارات وصلت.", "Showing the last notifications received."),
                                              retry: reload, lastGood: store.health.lastGood)))
                .adminPageRow(top: DS.Spacing.xs)
        }
        switch state {
        case .skeleton:
            AnyView(DSCardSkeleton(style: .notice, count: 5,
                                   label: L10n.t("جارٍ تحميل الإشعارات…", "Loading notifications…")))
                .adminPageRow(top: DS.Hub.stackSpacing)
        case .failed:
            AnyView(AdminPageStateCard(.error(L10n.t("تعذّر تحميل الإشعارات", "Couldn't load notifications"),
                                              message: L10n.t("تحقّق من اتصالك ثم أعد المحاولة.",
                                                              "Check your connection, then try again."),
                                              retry: reload)))
                .adminPageRow(top: DS.Spacing.xs)
        case .empty:
            AnyView(AdminPageStateCard(.empty(L10n.t("لا إشعارات", "No notifications"),
                                              message: L10n.t("ستصلك هنا تنبيهات الطلبات والنظام.",
                                                              "Request and system alerts will arrive here."))))
                .adminPageRow(top: DS.Spacing.xs)
        case .filteredEmpty(let searching):
            AnyView(filteredEmpty(searching: searching))
                .adminPageRow(top: DS.Spacing.xs)
        case .list:
            ForEach(m.sections, id: \.id) { section in
                let items = section.indices.map { m.visible[$0] }
                DSDayHeader(title: sectionTitle(section), count: items.count)
                    .dsCardCascade(1, appeared: appeared)
                    .adminPageRow(top: DS.Hub.stackSpacing, bottom: DSNoticeMetrics.headerGap)
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    cell(item, position: DSGroupPosition(index: index, count: items.count), now: section.kind == .now)
                }
            }
        }
    }

    private func sectionTitle(_ section: AdminNoticeLogic.Section) -> String {
        switch section.kind {
        case .now:          return L10n.t("يحتاج إجراء الآن", "Needs action now")
        case .day(let day): return DSDayBuckets.title(for: day)
        }
    }

    /// بحث بلا نتيجة: «لا نتائج» + «مسح البحث»؛ فلتر بلا نتيجة: «لا شيء في هذا الفلتر» + «عرض الكل»
    private func filteredEmpty(searching: Bool) -> some View {
        Group {
            if searching {
                AdminPageStateCard(.empty(L10n.t("لا نتائج", "No results"),
                                          message: L10n.t("جرّب كلمة أخرى", "Try another word"),
                                          actionTitle: L10n.t("مسح البحث", "Clear search"),
                                          action: { searchText = "" }))
            } else {
                AdminPageStateCard(.empty(L10n.t("لا شيء في هذا الفلتر", "Nothing in this filter"),
                                          message: L10n.t("«\(filter.title)» فارغ الآن.", "«\(filter.title)» is empty now."),
                                          actionTitle: L10n.t("عرض الكل", "Show all"),
                                          action: { withAnimation(reduceMotion ? nil : DS.Anim.snappy) { filter = .all } }))
            }
        }
    }

    // MARK: الصفّ

    private func rowActions(_ item: AdminNoticeItem) -> [AdminNoticeRowAction] {
        guard item.notificationId != nil else { return [] }
        return item.isUnread ? [.read, .delete] : [.delete]
    }

    private func perform(_ action: AdminNoticeRowAction, _ item: AdminNoticeItem) {
        guard let id = item.notificationId else { return }
        switch action {
        case .read:   markRead([id])
        case .delete: Task { await AdminNoticeWrites.delete([id], notificationVM) }
        }
    }

    /// الخلية: الضغط يفتح التفاصيل ويعلّم الإشعار مقروءاً (أو يحدّد في وضع التحديد)، السحب «مقروء» من البداية و«حذف» من
    /// الطرف، والضغط المطوّل القائمة نفسها (spec A.15)
    private func cell(_ item: AdminNoticeItem, position: DSGroupPosition, now: Bool) -> some View {
        let picked = item.notificationId.map(selectedIds.contains) ?? false
        let actions = isSelecting ? [] : rowActions(item)
        return AnyView(AdminNoticeListRow(item: item, position: position, now: now, selecting: isSelecting,
                                          picked: picked, actions: actions,
                                          onTap: { tap(item) },
                                          perform: { perform($0, item) },
                                          onSelfChild: handleSelfChild))
            .contentShape(Rectangle())
            .onTapGesture { tap(item) }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if actions.contains(.delete) {
                    Button(role: .destructive) { perform(.delete, item) } label: {
                        Label(AdminNoticeRowAction.delete.title, systemImage: AdminNoticeRowAction.delete.icon)
                    }
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if actions.contains(.read) {
                    Button { perform(.read, item) } label: {
                        Label(AdminNoticeRowAction.read.title, systemImage: AdminNoticeRowAction.read.icon)
                    }
                    .tint(DS.Color.primaryFill)
                }
            }
            .contextMenu {
                ForEach(actions) { action in
                    Button(role: action == .delete ? .destructive : nil) { perform(action, item) } label: {
                        Label(action.title, systemImage: action.icon)
                    }
                }
            }
            .dsCardCascade(1, appeared: appeared)
            .adminPageRow(top: 0, bottom: 0)
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
        if item.isUnread { markRead([id]) }
    }

    // MARK: التحديد

    private func toggleSelect() {
        withAnimation(DS.Anim.quick) {
            isSelecting.toggle()
            if !isSelecting { selectedIds.removeAll() }
        }
    }

    /// شريط وضع التحديد (spec C.15): «تحديد الكل» · «مقروء (3)» · «حذف (3)» (يسأل قبل الحذف) — أبيض بخطّ رفيع فوقه،
    /// والزرّان تحت «تحديد الكل» إن ضاق السطر (الخط الكبير)
    private func selectionBar(_ m: Model) -> some View {
        let shown = Set(m.visible.compactMap(\.notificationId))
        let allPicked = !shown.isEmpty && shown.isSubset(of: selectedIds)
        let picked = selectedIds.intersection(m.noticeIds)
        let selectAll = Button {
            withAnimation(DS.Anim.quick) {
                if allPicked { selectedIds.subtract(shown) } else { selectedIds.formUnion(shown) }
            }
        } label: {
            Text(allPicked ? L10n.t("إلغاء تحديد الكل", "Deselect all") : L10n.t("تحديد الكل", "Select all"))
                .dsFont(.button)
                .foregroundColor(AppSection.admin.ink)
                .lineLimit(1)
                .frame(minHeight: DS.Icon.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .disabled(shown.isEmpty)
        let read = DSButton(Logic.countedVerb(L10n.t("مقروء", "Read"), picked.count), icon: "envelope.open.fill",
                            fullWidth: false) { markSelectedRead(picked) }
            .disabled(picked.isEmpty)
        let delete = DSButton(Logic.countedVerb(L10n.t("حذف", "Delete"), picked.count), icon: "trash.fill",
                              role: .destructive, fullWidth: false) { showDeleteConfirm = true }
            .disabled(picked.isEmpty)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.md) {
                selectAll.fixedSize()
                Spacer(minLength: 0)
                read.fixedSize()
                delete.fixedSize()
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                selectAll
                HStack(spacing: DS.Spacing.md) {
                    read
                    delete
                }
            }
        }
        .dsPageMargin()
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Hub.background.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { AdminRowDivider() }
    }

    private func markSelectedRead(_ ids: Set<UUID>) {
        withAnimation(DS.Anim.quick) { selectedIds.removeAll(); isSelecting = false }
        markRead(ids)
    }

    private func deleteSelected() {
        let ids = selectedIds.intersection(Set(notificationVM.notifications.map(\.id)))
        withAnimation(DS.Anim.quick) { selectedIds.removeAll(); isSelecting = false }
        Task { await AdminNoticeWrites.delete(ids, notificationVM) }
    }

    private func markRead(_ ids: Set<UUID>) {
        Task { await AdminNoticeWrites.markRead(ids, notificationVM) }
    }

    private func reload() {
        Task { await store.load(using: notificationVM) }
    }

    // MARK: التفاصيل

    /// المرسل — المصدر الواحد مع مركز الإشعارات (الصفوف القديمة: اسم المنفّذ أو «الإدارة»)
    private func sender(_ n: AppNotification, style: (icon: String, tint: Color)) -> NotificationSenderInfo {
        let legacy = n.createdBy.flatMap { memberVM.member(byId: $0) }?.shortFullName ?? L10n.t("الإدارة", "Admin")
        return NotificationSenderInfo.resolve(n, isStaff: true, kindIcon: style.icon, legacyName: legacy,
                                              member: { memberVM.member(byId: $0) })
    }

    private func categoryTitle(_ n: AppNotification, _ category: AdminNotices.Category) -> String {
        switch category {
        case .action:
            return AdminNotices.securityKinds.contains(n.kind) ? L10n.t("تنبيه أمني", "Security alert")
                                                               : L10n.t("طلب", "Request")
        case .changes: return Filter.changes.title
        case .team:    return Filter.team.title
        case .system:  return Filter.system.title
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
                notification: n, categoryTitle: cat, icon: style.icon, notice: notice,
                onClose: { detail = nil },
                onOpenProfile: { id in
                    detail = nil
                    afterBox { selfChildFlow.sheet = AdminMemberSheetContext(ids: [id], start: 0) }
                })
                .environmentObject(memberVM)
                .environmentObject(notificationVM)
                // «طلب تغيير الصورة» تحت بطاقة الصورة يقرأ الصلاحية
                .environmentObject(authVM))
        }
        return AnyView(requestDetailBox(n, style: style, cat: cat))
    }

    /// بعد إغلاق المربّع — لا تتداخل حركتاهما
    private func afterBox(_ run: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.boxHandoff, execute: run)
    }

    private func requestDetailBox(_ n: AppNotification, style: (icon: String, tint: Color), cat: String) -> some View {
        let subject = NotificationDetailParts.subjectMember(n, member: { memberVM.member(byId: $0) })
        let body = n.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return NotificationDetailBox(
            notification: n,
            isStaff: true,
            sender: sender(n, style: style),
            kindLabel: cat,
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
                afterBox {
                    NotificationCenter.default.post(name: .openAdminReviewForKind, object: nil,
                                                    userInfo: ["kind": n.kind, "request_id": rid.uuidString])
                }
            },
            onOpenNews: { nid in
                detail = nil
                afterBox {
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

/// «قبل 5 دقائق» (قسم «يحتاج إجراء الآن» والمربّعات) و«9:05 ص» (صفوف الأيام — اليوم في عنوان قسمه). أرقام لاتينية
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

    private static var clockFormatter: (arabic: Bool, formatter: DateFormatter)?

    static func clock(_ date: Date) -> String {
        let arabic = L10n.isArabic
        if clockFormatter?.arabic != arabic {
            let f = DateFormatter()
            f.locale = Locale(identifier: arabic ? "ar_KW@numbers=latn" : "en_US")
            f.setLocalizedDateFormatFromTemplate("jmm")
            clockFormatter = (arabic, f)
        }
        return clockFormatter?.formatter.string(from: date) ?? ""
    }
}
