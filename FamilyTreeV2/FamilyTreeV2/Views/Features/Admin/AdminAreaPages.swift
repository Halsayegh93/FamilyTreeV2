import SwiftUI

// MARK: - صفحات الأقسام الستة (إعادة تصميم لوحة الإدارة — طلب المالك ٢٠٢٦-١٠-٢٠، «٦ أقسام»)
//
// كل قسم = رأس كحلي («‹ اليوم»، شريط الأقسام، العنوان، الوصف) + بطاقات صفوف تفتح الصفحات الموجودة كما هي (لا منطق
// جديد). «المناسبات والإعلانات» تجمع بطاقة «المناسبات» وبطاقة «الإعلانات» المختصرة (`AdminAnnouncementsCard`)، و«الفريق
// والأمان» تجمع «الفريق» و«من يدخل وكيف».
// فهرس الأدوات `AdminToolCatalog` هو المصدر الواحد: الأقسام والبحث الشامل وجدول الانتقال (REACHABILITY.md)
// يقرؤون منه — كل ميزة لها صفّ واحد في قسم واحد، والصلاحيات كما كانت تماماً.

/// أداة في قسم: صفّ يفتح صفحة موجودة، أو إجراء (فتح شجرة النساء في تبويب الشجرة)
struct AdminTool: Identifiable {
    enum Kind {
        case page(() -> AnyView)
        case action(() -> Void)
    }

    let id: String
    let area: AdminArea
    /// عنوان البطاقة التي يقع فيها الصفّ داخل القسم
    let group: String
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    var keywords: [String] = []
    let kind: Kind
}

@MainActor
enum AdminToolCatalog {

    /// كل أدوات اللوحة المتاحة لهذا الدور — بالترتيب داخل كل قسم
    static func tools(authVM: AuthViewModel, adminRequestVM: AdminRequestViewModel) -> [AdminTool] {
        var t: [AdminTool] = []
        let isAdmin = authVM.isAdmin
        let role = authVM.currentUser?.role
        func page(_ make: @escaping () -> some View) -> AdminTool.Kind { .page { AnyView(make()) } }

        // ١ الوارد
        t.append(AdminTool(id: "inbox.requests", area: .inbox, group: L10n.t("الوارد", "Inbox"),
                           title: L10n.t("الطلبات", "Requests"),
                           subtitle: L10n.t("كل ما ينتظر قراراً — بالنوع والمهلة", "Everything awaiting a decision"),
                           icon: "tray.full.fill", tint: DS.Color.primary,
                           keywords: ["طلبات", "مراجعة", "انضمام", "موافقة"],
                           kind: page { AdminAllRequestsView() }))
        t.append(AdminTool(id: "inbox.messages", area: .inbox, group: L10n.t("الوارد", "Inbox"),
                           title: L10n.t("رسائل الأعضاء", "Member messages"),
                           subtitle: L10n.t("رسائل «تواصل مع الإدارة»", "“Contact admin” messages"),
                           icon: "bubble.left.and.bubble.right.fill", tint: DS.Color.sea,
                           keywords: ["رسائل", "تواصل"],
                           kind: page { AdminAllRequestsView(startsWithMessages: true) }))
        if adminRequestVM.approvalsWorkflowOn && (isAdmin || role == .monitor) {
            t.append(AdminTool(id: "inbox.report", area: .inbox, group: L10n.t("الوارد", "Inbox"),
                               title: L10n.t("تقرير الموافقات", "Approvals report"),
                               subtitle: L10n.t("المراحل والأداء والتصعيدات", "Stages, performance, escalations"),
                               icon: "chart.bar.xaxis", tint: DS.Color.warning,
                               kind: page { ApprovalsReportView() }))
        }
        if authVM.canViewSystemSettings {
            t.append(AdminTool(id: "inbox.settings", area: .inbox, group: L10n.t("الوارد", "Inbox"),
                               title: L10n.t("إعدادات المسار", "Approval path settings"),
                               subtitle: L10n.t("مسار الموافقات، المهلة، المسار السريع، الردود الجاهزة",
                                                "Approvals path, SLA, fast track, ready replies"),
                               icon: "gearshape.fill", tint: DS.Color.slate,
                               keywords: ["مسار", "مهلة", "ردود"],
                               kind: page { AdminAppSettingsView(scope: .approvals) }))
        }

        // ٢ العائلة — صفحة القسم هي صفحة الأعضاء الواحدة (`AdminMembersPage`)؛ هذه الصفوف للبحث الشامل فقط
        // (تفتح الصفحة على شريحتها، والكلمات القديمة تجد بيتها الجديد)
        if authVM.canEditMembers {
            let members = L10n.t("الأعضاء", "Members")
            t.append(AdminTool(id: "family.members", area: .family, group: members,
                               title: L10n.t("الأعضاء", "Members"),
                               subtitle: L10n.t("بحث وشرائح، وورقة لكل عضو بكل أوامره", "Search, filters and one sheet per member"),
                               icon: "person.3.sequence.fill", tint: DS.Color.palm,
                               keywords: ["أعضاء", "سجل", "فروع", "عضو", "إدارة السجل", "بيانات العضو"],
                               kind: page { AdminMembersPage() }))
            t.append(AdminTool(id: "family.registered", area: .family, group: members,
                               title: L10n.t("الأعضاء المسجّلون", "Registered members"),
                               subtitle: L10n.t("لهم حساب في التطبيق — ومن يستخدمه ومن لا تصله الإشعارات",
                                                "With an app account — who uses it, who gets no notifications"),
                               icon: "checkmark.seal.fill", tint: DS.Color.success,
                               keywords: ["حسابات", "استخدام", "مسجّل", "موقوف", "تفعيل"],
                               kind: page { AdminMembersPage(chip: .registered) }))
            t.append(AdminTool(id: "family.gaps", area: .family, group: members,
                               title: L10n.t("بيانات ناقصة", "Missing data"),
                               subtitle: L10n.t("اكتمال البيانات واستكمالها عضواً عضواً", "Completeness, one member at a time"),
                               icon: "checklist", tint: DS.Color.warning,
                               keywords: ["نواقص", "جودة", "استكمال", "محطة"],
                               kind: page { AdminMembersPage(chip: .gaps) }))
            t.append(AdminTool(id: "family.problems", area: .family, group: members,
                               title: L10n.t("مشكلات الشجرة", "Tree problems"),
                               subtitle: L10n.t("غير مرتبط بأب، بلا اسم، ارتباط أب غير صالح، مخفي، رقم مكرر",
                                                "Unlinked, unnamed, invalid link, hidden, duplicate"),
                               icon: "stethoscope", tint: DS.Color.warning,
                               keywords: ["صحة", "سلامة", "يتيم", "مكرر"],
                               kind: page { AdminMembersPage(chip: .problems) }))
            if authVM.canRegisterMembers {
                t.append(AdminTool(id: "family.register", area: .family, group: members,
                                   title: L10n.t("تسجيل عضو جديد", "Register a new member"),
                                   subtitle: L10n.t("عضو جديد بصورته ورقمه", "A new member with photo and phone"),
                                   icon: "person.badge.plus", tint: DS.Color.palm,
                                   keywords: ["تسجيل", "إضافة"],
                                   kind: page { AdminRegisterMemberView() }))
            }
            t.append(AdminTool(id: "family.women", area: .family, group: members,
                               title: L10n.t("شجرة النساء", "Women's tree"),
                               subtitle: L10n.t("تُدار من تبويب الشجرة", "Managed from the Tree tab"),
                               icon: "person.2.fill", tint: DS.Color.female,
                               keywords: ["نساء", "بنات"],
                               kind: .action {
                                   TreeTabContainer.openWomenOnAppear = true
                                   NotificationCenter.default.post(name: .openWomenTree, object: nil)
                               }))
            // «تقارير PDF» — بيتها الواحد «⋯ ← تصدير» في صفحة الأعضاء (الدفعة ج؛ كانت صفّاً في «المؤشرات»)
            if isAdmin {
                t.append(AdminTool(id: "family.export", area: .family, group: members,
                                   title: L10n.t("تصدير قائمة الأعضاء (PDF)", "Export member list (PDF)"),
                                   subtitle: L10n.t("من «⋯» في صفحة الأعضاء — بالشريحة المختارة", "From “⋯” on the members page — with the chosen filter"),
                                   icon: "doc.text.fill", tint: DS.Color.accent,
                                   keywords: ["تقرير", "تقارير", "طباعة", "pdf"],
                                   kind: page { AdminReportsView() }))
            }
        }

        // ٣ المناسبات
        let occasions = L10n.t("المناسبات", "Occasions")
        if isAdmin {
            t.append(AdminTool(id: "occasions.deaths", area: .occasions, group: occasions,
                               title: L10n.t("الوفيات والإعلان", "Deaths & obituaries"),
                               subtitle: L10n.t("وفيات آخر 30 يوماً — أعلن بنص جاهز", "Last 30 days — announce with ready text"),
                               icon: NewsTypeHelper.icon(for: "وفاة"), tint: DS.Color.slate,
                               keywords: ["وفاة", "إعلان", "عزاء"],
                               kind: page { DeathAnnouncementsPage() }))
        }
        if authVM.canModerate {
            t.append(AdminTool(id: "occasions.memorial", area: .occasions, group: occasions,
                               title: L10n.t("ذكرى الراحلين", "Memorials"),
                               subtitle: L10n.t("الذكرى القريبة وتكميل التاريخ", "Upcoming anniversaries and dates"),
                               icon: "moon.stars.fill", tint: DS.Color.sadu,
                               keywords: ["ذكرى", "راحلين"],
                               kind: page { DeceasedMemorialView() }))
            t.append(AdminTool(id: "occasions.posts", area: .occasions, group: occasions,
                               title: L10n.t("منشورات المناسبات", "Occasion posts"),
                               subtitle: L10n.t("تهنئة، إعلان عزاء، مشاركة عزاء", "Congrats and condolences"),
                               icon: "photo.on.rectangle.angled", tint: DS.Color.accent,
                               keywords: ["منشور", "تهنئة", "مناسبة"],
                               kind: page { OccasionComposerView() }))
        }

        // ٣ب الإعلانات (داخل «المناسبات والإعلانات» — صفحتها تعرضها في بطاقة «الإعلانات» المختصرة، والبحث يقرؤها من هنا)
        if authVM.canSendNotifications {
            let send = L10n.t("إرسال للأعضاء", "Send to members")
            t.append(AdminTool(id: "ann.notify", area: .occasions, group: send,
                               title: L10n.t("إشعار للأعضاء", "Notify members"),
                               subtitle: L10n.t("للجميع أو لدولة أو لأعضاء — الآن أو بجدولة", "Everyone, a country or people — now or later"),
                               icon: "bell.badge.fill", tint: DS.Color.sea,
                               keywords: ["إشعار", "إرسال", "إعلان", "إعلانات"],
                               kind: page { AdminMessagingHubView() }))
            t.append(AdminTool(id: "ann.update", area: .occasions, group: send,
                               title: L10n.t("رسالة تحديث التطبيق", "App update message"),
                               subtitle: L10n.t("ما الجديد في «المستجدات» + إشعار", "What's new in Updates + a notification"),
                               icon: "megaphone.fill", tint: DS.Color.sea,
                               keywords: ["تحديث", "إصدار"],
                               kind: page { AdminMessagingHubView(startsWithUpdate: true) }))
            t.append(AdminTool(id: "ann.scheduled", area: .occasions, group: send,
                               title: L10n.t("المجدولة", "Scheduled"),
                               subtitle: L10n.t("الإشعارات التي تنتظر وقتها — من شريطها في «إشعار للأعضاء»",
                                                "Waiting notifications — from their bar in Notify"),
                               icon: "clock.badge.checkmark.fill", tint: DS.Color.sea,
                               keywords: ["مجدول"],
                               kind: page { AdminMessagingHubView() }))
            t.append(AdminTool(id: "ann.push", area: .occasions, group: L10n.t("هل يصلهم؟", "Does it reach them?"),
                               title: L10n.t("وصول الإشعارات", "Notification reach"),
                               subtitle: L10n.t("رموز الأجهزة، التجربة، والتنظيف", "Device tokens, test and cleanup"),
                               icon: "bell.and.waves.left.and.right.fill", tint: DS.Color.info,
                               keywords: ["رموز", "أجهزة", "تجربة"],
                               kind: page { AdminPushHealthView() }))
        }

        // ٤ المؤشرات — أربعة مداخل للقراءة (الدفعة ج من «نفّذ كل المقترح»): العائلة · الاستخدام · الموافقات · سجل التعديلات.
        // كل رقم في بيته هنا، و«اليوم» يعرض أرقاماً تفتحه فقط
        let insights = L10n.t("أرقام وسجل", "Numbers & history")
        if isAdmin || role == .monitor {
            // المراقب: الأعداد فقط (`AdminAnalyticsView` يقرأ الدور)
            t.append(AdminTool(id: "metrics.family", area: .metrics, group: insights,
                               title: L10n.t("العائلة", "The family"),
                               subtitle: isAdmin ? L10n.t("الأفراد والأحياء، المسجّلون، النمو والأعمار والأدوار",
                                                          "Members, living, registered, growth, ages and roles")
                                                 : L10n.t("أعداد الأفراد والأحياء والمسجّلين", "Members, living and registered counts"),
                               icon: "person.3.fill", tint: DS.Color.palm,
                               keywords: ["إحصائيات", "إحصاءات", "أعمار", "أفراد", "نمو", "رجال", "نساء"],
                               kind: page { AdminAnalyticsView() }))
        }
        if isAdmin {
            t.append(AdminTool(id: "metrics.usage", area: .metrics, group: insights,
                               title: L10n.t("الاستخدام", "Usage"),
                               subtitle: L10n.t("المستخدمون الآن، آخر 24 ساعة، آخر 30 يوماً — التطبيق والموقع",
                                                "Using now, last 24 hours, last 30 days — app and web"),
                               icon: "bolt.fill", tint: DS.Color.sea,
                               keywords: ["نشاط", "نشط", "الآن", "مستخدمون"],
                               kind: page { AdminActiveMembersView() }))
        }
        // تقرير الموافقات — بيته الواحد هنا (كان أيضاً في رأس «الوارد» وصفّه ومربّع «منجز هذا الأسبوع»)
        if adminRequestVM.approvalsWorkflowOn && (isAdmin || role == .monitor) {
            t.append(AdminTool(id: "metrics.approvals", area: .metrics, group: insights,
                               title: L10n.t("الموافقات", "Approvals"),
                               subtitle: L10n.t("المنجز، وقت كل مرحلة، حسب النوع، أداء الإدارة", "Done, time per stage, by type, team"),
                               icon: "chart.bar.doc.horizontal", tint: DS.Color.warning,
                               keywords: ["تقرير", "تقرير الموافقات", "منجز", "مسار"],
                               kind: page { ApprovalsReportView() }))
        }
        if isAdmin || role == .monitor {
            t.append(AdminTool(id: "metrics.activity", area: .metrics, group: insights,
                               title: L10n.t("سجل التعديلات", "Change log"),
                               subtitle: L10n.t("كل تعديل: من وماذا ومتى", "Every change: who, what, when"),
                               icon: "clock.arrow.circlepath", tint: DS.Color.primary,
                               keywords: ["سجل", "سجل النشاط", "تعديلات"],
                               kind: page { AdminActivityLogView() }))
        }

        // ٥ الفريق والأمان — أربعة مداخل: فريق الإدارة · رسائل رمز الدخول · التسجيل والمنع · الأجهزة ووصول الإشعارات
        // (صفحة القسم `AdminTeamAreaView` في `AdminTeamArea.swift`؛ «صلاحيات الأدوار» داخل فريق الإدارة)
        if isAdmin {
            t.append(AdminTool(id: "team.members", area: .team, group: L10n.t("الفريق", "Team"),
                               title: L10n.t("فريق الإدارة", "Admin team"),
                               subtitle: authVM.canManageRoles ? L10n.t("الأعضاء حسب الدور، وصلاحيات الأدوار — إضافة وتغيير",
                                                                        "Members by role and role permissions — add and change")
                                                               : L10n.t("الأعضاء حسب الدور، وصلاحيات الأدوار", "Members by role and role permissions"),
                               icon: "person.3.fill", tint: DS.Color.primary,
                               keywords: ["فريق", "مدير", "مراقب", "مشرف", "أدوار", "صلاحيات", "نطاقي", "صلاحياتي"],
                               kind: page { AdminModeratorsView() }))
        }
        if authVM.canViewSystemSettings {
            let access = L10n.t("الدخول والأمان", "Sign-in and security")
            t.append(AdminTool(id: "access.sms", area: .team, group: access,
                               title: L10n.t("رسائل رمز الدخول (KWT SMS)", "Sign-in code messages (KWT SMS)"),
                               subtitle: L10n.t("الرصيد، طلبات رمز الدخول، إعدادات الإرسال",
                                                "Balance, code requests, sending settings"),
                               icon: "ellipsis.message.fill", tint: DS.Hub.securityFill,
                               keywords: ["رسائل", "sms", "رصيد", "kwt", "محاولات", "مرسل"],
                               kind: page { AdminSmsView() }))
            t.append(AdminTool(id: "access.registration", area: .team, group: access,
                               title: L10n.t("التسجيل والمنع", "Sign-up and blocking"),
                               subtitle: L10n.t("السماح بالتسجيل · الأرقام الممنوعة من التسجيل",
                                                "Allow sign-ups · numbers blocked from signing up"),
                               icon: "person.crop.circle.badge.checkmark", tint: DS.Color.palm,
                               keywords: ["تسجيل", "شروط", "حظر", "محظور", "منع", "ممنوع"],
                               kind: page { AdminRegistrationBansView() }))
            t.append(AdminTool(id: "access.devices", area: .team, group: access,
                               title: L10n.t("الأجهزة ووصول الإشعارات", "Devices and notification reach"),
                               subtitle: L10n.t("الأجهزة المرتبطة، وصول الإشعارات، عدد الأجهزة لكل عضو",
                                                "Linked devices, notification reach, devices per member"),
                               icon: "iphone.gen3", tint: DS.Color.primary,
                               keywords: ["أجهزة", "إشعارات", "رموز", "وصول", "فصل", "تجربة"],
                               kind: page { AdminPushHealthView() }))
        }

        // ٦ التطبيق — صفحة القسم هي الإعدادات نفسها (`AdminAppAreaPage`، المفاتيح في مكانها)؛ هذه الصفوف للبحث الشامل
        // (تفتح الصفحة أو قائمتها). «كل الإعدادات في صفحة واحدة» حُذفت — الصفحة نفسها صارت كل الإعدادات
        if authVM.canViewSystemSettings {
            let settings = L10n.t("التطبيق", "App")
            t.append(AdminTool(id: "app.sections", area: .app, group: settings,
                               title: L10n.t("الأقسام الظاهرة للأعضاء", "Sections members see"),
                               subtitle: L10n.t("لغة التطبيق، الديوانيات، شجرة النساء، المشاريع، الاستطلاعات، اعتماد الأخبار",
                                                "Language, Diwaniyas, women's tree, projects, polls, news approval"),
                               icon: "switch.2", tint: DS.Color.primary,
                               keywords: ["لغة", "ميزات", "ديوانيات", "مشاريع", "استطلاعات", "أخبار", "اعتماد"],
                               kind: page { AdminAppAreaPage() }))
            t.append(AdminTool(id: "app.categories", area: .app, group: settings,
                               title: L10n.t("تصنيفات الأخبار والمكتبة", "News & library categories"),
                               subtitle: L10n.t("الاسم والأيقونة واللون، والإخفاء والترتيب", "Name, icon, colour, hide and order"),
                               icon: "tag.fill", tint: DS.Color.accent,
                               keywords: ["تصنيفات", "قوائم"],
                               kind: page { CategoriesManagerView() }))
            // «أسماء العوائل» (من «العائلة») + «أسماء الفروع» في صفحة واحدة
            t.append(AdminTool(id: "app.names", area: .app, group: settings,
                               title: L10n.t("أسماء العوائل والفروع", "Family and branch names"),
                               subtitle: L10n.t("يختار منها العضو عائلته، وأسماء قائمة الفروع", "Members pick their family; branch list names"),
                               icon: "person.2.crop.square.stack.fill", tint: DS.Color.accent,
                               keywords: ["عوائل", "عائلة", "فروع", "قوائم"],
                               kind: page { AdminFamilyNamesView() }))
            t.append(AdminTool(id: "app.selfEdits", area: .app, group: settings,
                               title: L10n.t("حدّ التعديلات الذاتية", "Self-edit limit"),
                               subtitle: L10n.t("3 تعديلات ثم بموافقة الإدارة — إيقاف الحدّ أو إعادة ضبط العدّاد",
                                                "3 edits then approval — pause or reset the counter"),
                               icon: "timer", tint: DS.Color.info,
                               keywords: ["عداد", "تعديل", "حد"],
                               kind: page { AdminAppAreaPage() }))
            t.append(AdminTool(id: "app.maintenance", area: .app, group: settings,
                               title: L10n.t("وضع الصيانة", "Maintenance mode"),
                               subtitle: L10n.t("إيقاف التطبيق مؤقتاً للأعضاء", "Pause the app for members"),
                               icon: "wrench.and.screwdriver.fill", tint: DS.Color.warning,
                               keywords: ["صيانة", "تشغيل"],
                               kind: page { AdminAppAreaPage() }))
            t.append(AdminTool(id: "app.forceUpdate", area: .app, group: settings,
                               title: L10n.t("فرض التحديث", "Force update"),
                               subtitle: L10n.t("أقل إصدار مسموح للآيفون والأندرويد", "Minimum allowed version for iPhone and Android"),
                               icon: "arrow.down.app.fill", tint: DS.Color.primary,
                               keywords: ["تحديث", "إجباري", "إصدار"],
                               kind: page { AdminForceUpdateView() }))
            t.append(AdminTool(id: "app.system", area: .app, group: settings,
                               title: L10n.t("النظام", "System"),
                               subtitle: L10n.t("الإصدار، آخر تعديل للإعدادات، استعادة الإعدادات الافتراضية",
                                                "Version, last settings change, restore defaults"),
                               icon: "info.circle.fill", tint: DS.Color.slate,
                               keywords: ["معلومات", "إعادة التعيين", "افتراضي", "استعادة"],
                               kind: page { AdminAppAreaPage() }))
        }
        return t
    }
}

// MARK: - التوجيه

/// صفحة القسم — «الوارد» صفحة الطلبات نفسها، والباقي بطاقات أدواته. كل ما يُفتح منها يتبع القسم (`adminArea`)
struct AdminAreaView: View {
    let area: AdminArea

    var body: some View {
        page.adminArea(area)
    }

    private var page: AnyView {
        switch area {
        case .inbox:     return AnyView(AdminAllRequestsView())
        case .family:    return AnyView(AdminMembersPage())
        case .metrics:   return AnyView(AdminMetricsAreaView())
        case .team:      return AnyView(AdminTeamAreaView())
        case .app:       return AnyView(AdminAppAreaPage())
        case .occasions: return AnyView(AdminToolsAreaView(area: .occasions))
        }
    }
}

/// بطاقات أدوات القسم مجمّعة بعنوان كل مجموعة
struct AdminToolCards: View {
    let tools: [AdminTool]
    var hints: [String: String] = [:]
    /// تلميحات تحذير (بلون التحذير)
    var warnings: Set<String> = []

    private var groups: [(title: String, tools: [AdminTool])] {
        var order: [String] = []
        var map: [String: [AdminTool]] = [:]
        for tool in tools {
            if map[tool.group] == nil { order.append(tool.group) }
            map[tool.group, default: []].append(tool)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        ForEach(groups, id: \.title) { group in
            VStack(alignment: .leading, spacing: 0) {
                AdminCardHeader(title: group.title)
                ForEach(Array(group.tools.enumerated()), id: \.element.id) { index, tool in
                    if index > 0 { AdminRowDivider() }
                    AdminToolRow(tool: tool, hint: hints[tool.id], warn: warnings.contains(tool.id))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .adminCard()
        }
    }
}

/// صفّ أداة واحد — يفتح صفحتها (أو ينفّذ إجراءها)
struct AdminToolRow: View {
    let tool: AdminTool
    var hint: String? = nil
    var warn: Bool = false

    var body: some View {
        switch tool.kind {
        case .page(let make):
            // اسم القسم على زر «رجوع» الصفحة الداخلية (AdminPageKit)، وقسمها في شريط الأقسام (من البحث أيضاً)
            NavigationLink { AdminLazyPage(make: make).adminBackTitle(tool.area.title).adminArea(tool.area) } label: { label }
                .buttonStyle(.plain)
        case .action(let run):
            Button(action: run) { label }
                .buttonStyle(.plain)
        }
    }

    private var label: some View {
        AdminListRow(icon: tool.icon, tint: tool.tint, title: tool.title, subtitle: tool.subtitle) {
            if let hint {
                Text(hint)
                    .dsFont(.caption)
                    .monospacedDigit()
                    .foregroundColor(warn ? DS.Color.warning : DS.Color.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// قسم بلا بطاقات خاصة: الرأس + بطاقات أدواته
struct AdminToolsAreaView: View {
    let area: AdminArea
    var readOnlyBadge: Bool = false
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @ObservedObject private var sms = SmsBalanceStore.shared

    var body: some View {
        // صفوف «الإعلانات» تُعرض في بطاقتها المختصرة (أعلى القسم) لا كبطاقات أدوات
        let tools = AdminToolCatalog.tools(authVM: authVM, adminRequestVM: adminRequestVM)
            .filter { $0.area == area && !AdminAnnouncementsCard.toolIds.contains($0.id) }
        let announces = area == .occasions && authVM.canSendNotifications
        AdminHubPage {
            AdminBandHeader(title: area.title, subtitle: area.subtitle,
                            badge: readOnlyBadge && !authVM.canManageSettings
                                ? L10n.t("للقراءة — يعدّلها المالك", "Read-only — the owner edits") : nil,
                            isAreaRoot: true)
        } content: {
            AdminAreaTop(area: area)
            if tools.isEmpty && !announces {
                DSEmptyView(L10n.t("لا أدوات لدورك هنا", "No tools for your role here"), style: .card)
            } else if !tools.isEmpty {
                AdminToolCards(tools: tools, hints: hints, warnings: warnings)
            }
        }
        .task {
            if area == .team && authVM.canViewSystemSettings { await sms.refresh() }
            if announces { await notificationVM.fetchScheduledNotifications() }
            if area == .occasions && memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
        }
    }

    private var hints: [String: String] {
        var h: [String: String] = [:]
        if let balance = sms.status?.balance {
            h["access.sms"] = L10n.t("\(SmsBalanceText.points(balance)) نقطة", "\(SmsBalanceText.points(balance)) pts")
        }
        if !authVM.bannedPhones.isEmpty { h["access.banned"] = "\(authVM.bannedPhones.count)" }
        let scheduled = notificationVM.scheduledNotifications.count
        if scheduled > 0 { h["ann.scheduled"] = "\(scheduled)" }
        if area == .occasions {
            let memorial = DeceasedMemorialBoard(memberVM.allMembers)
            if memorial.withinWeek > 0 {
                h["occasions.memorial"] = L10n.t("\(memorial.withinWeek) هالأسبوع", "\(memorial.withinWeek) this week")
            }
            let recent = memberVM.allMembers.filter {
                $0.isDeceased == true && $0.role != .pending && DeathRecency.isRecent($0.deathDate)
            }.count
            if recent > 0 { h["occasions.deaths"] = L10n.t("\(recent) حديثة", "\(recent) recent") }
        }
        if area == .team {
            let staff = memberVM.allMembers.filter {
                [.owner, .admin, .monitor, .supervisor].contains($0.role) && $0.isDeceased != true && $0.status != .frozen
            }.count
            h["team.members"] = "\(staff)"
        }
        return h
    }

    private var warnings: Set<String> {
        return sms.needsTopUp ? ["access.sms"] : []
    }
}

// MARK: - أعلى الأقسام: ما انتقل من «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠ «الأقسام فوق + قائمة وحدة»)
//
// «اليوم» صار: الرأس ← أعداد الأعضاء ← الأقسام ← تنبيهات ← «يحتاج قرارك». فما كان تحتها انتقل لأعلى قسمه بلا
// ضياع: كل إجراء سريع أعلى قسمه، «اليوم في العائلة» أعلى «المناسبات»، و«نبض العائلة» أعلى «المؤشرات».
// الصلاحيات كما كانت على «اليوم» حرفياً.

/// ما يسبق بطاقات الأدوات في الأقسام العامة: الإجراءات السريعة، ثم في «المناسبات والإعلانات» بطاقة «الإعلانات»
/// المختصرة (لمن يرسل للأعضاء) و«اليوم في العائلة»
struct AdminAreaTop: View {
    let area: AdminArea
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        AdminAreaQuickActions(area: area)
        if area == .occasions {
            if authVM.canSendNotifications {
                AnyView(AdminAnnouncementsCard())
            }
            AdminFamilyTodayCard()
        }
    }
}

/// الإجراءات السريعة لقسم: أزرار كبسولة بعرض الصفحة — منشور مناسبة وإعلان وفاة ← المناسبات والإعلانات («إعلان جديد»
/// في بطاقة «الإعلانات» تحتها). «العائلة» بلا كبسولات: «تسجيل عضو جديد» زرّ رأسها، والبحث حقلها الواحد
struct AdminAreaQuickActions: View {
    let area: AdminArea
    @EnvironmentObject var authVM: AuthViewModel

    private struct Action: Identifiable {
        let id: String
        let icon: String
        let title: String
        let page: () -> AnyView
    }

    private var actions: [Action] {
        var list: [Action] = []
        switch area {
        case .occasions:
            list.append(Action(id: "occasion", icon: "photo.on.rectangle", title: L10n.t("منشور مناسبة", "Occasion post")) {
                AnyView(OccasionComposerView())
            })
            if authVM.isAdmin {
                list.append(Action(id: "death", icon: NewsTypeHelper.icon(for: "وفاة"),
                                   title: L10n.t("إعلان وفاة", "Obituary")) {
                    AnyView(DeathAnnouncementsPage())
                })
            }
        default:
            break
        }
        return list
    }

    var body: some View {
        let list = actions
        if !list.isEmpty {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(list) { action in
                    NavigationLink { AdminLazyPage(make: action.page).adminArea(area) } label: {
                        AdminPillLabel(title: action.title, icon: action.icon, style: .navy,
                                       height: DS.Hub.pillHeightCard, fullWidth: true)
                    }
                    .buttonStyle(DSPressStyle())
                    .accessibilityLabel(action.title)
                }
            }
        }
    }
}

/// «اليوم في العائلة» (كانت في «اليوم»): الذكرى القريبة، ووفيات آخر ٣٠ يوماً ومن أُضيف هذا الأسبوع (المالك والمدير
/// والمراقب). لا تُرسم بلا صفوف
struct AdminFamilyTodayCard: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel

    private var rows: [AdminFamilyTodayRow] {
        let all = memberVM.allMembers
        guard !all.isEmpty else { return [] }
        var rows: [AdminFamilyTodayRow] = []
        if let next = DeceasedMemorialBoard(all).upcoming.first {
            rows.append(AdminFamilyTodayRow(
                id: "memorial", icon: "moon.stars.fill", tint: DS.Color.sadu,
                title: L10n.t("ذكرى \(next.member.shortFullName)", "\(next.member.shortFullName)'s anniversary"),
                value: DeceasedMemorial.whenLabel(next.anniversary.daysUntil, arabic: L10n.isArabic),
                target: .memorial))
        }
        guard authVM.isAdmin || authVM.currentUser?.role == .monitor else { return rows }
        let deaths = all.filter { $0.isDeceased == true && $0.role != .pending && DeathRecency.isRecent($0.deathDate) }.count
        if deaths > 0 {
            rows.append(AdminFamilyTodayRow(
                id: "deaths", icon: NewsTypeHelper.icon(for: "وفاة"), tint: DS.Color.slate,
                title: L10n.t("وفيات آخر 30 يوماً", "Deaths in the last 30 days"),
                value: "\(deaths)", target: authVM.isAdmin ? .deaths : .memorial))
        }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let joined = all.filter { m in
            m.isDeceased != true && m.isCountable && (ApprovalWorkflow.date(m.createdAt).map { $0 >= weekAgo } ?? false)
        }.count
        if joined > 0 {
            rows.append(AdminFamilyTodayRow(
                id: "joined", icon: "person.crop.circle.badge.plus", tint: DS.Color.palm,
                title: L10n.t("قُيّدوا هذا الأسبوع", "Added this week"),
                value: "\(joined)", target: .directory))
        }
        return rows
    }

    var body: some View {
        let rows = self.rows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                AdminCardHeader(title: L10n.t("اليوم في العائلة", "Today in the family"))
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { AdminRowDivider() }
                    NavigationLink { AdminLazyPage { Self.page(row.target) }.adminArea(.occasions) } label: {
                        AdminListRow(icon: row.icon, tint: row.tint, title: row.title) {
                            Text(verbatim: row.value)
                                .dsFont(.chip)
                                .monospacedDigit()
                                .foregroundColor(DS.Color.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .adminCard()
        }
    }

    private static func page(_ target: AdminFamilyTodayRow.Target) -> AnyView {
        switch target {
        case .memorial:  return AnyView(DeceasedMemorialView())
        case .deaths:    return AnyView(DeathAnnouncementsPage())
        case .directory: return AnyView(AdminMembersPage(sub: .newThisWeek).adminArea(.family).adminBackTitle(AdminArea.occasions.title))
        }
    }
}

// MARK: - «صلاحياتي» (سطر «اليوم» للمراقب والمشرف)

/// «صلاحياتي» (كان «نطاقي») — ما يقدر عليه دورك وما لا يقدر (البطاقة تصعد فوق الرأس). تُفتح من سطر «صلاحياتي» في
/// «اليوم» للمراقب والمشرف (بيته الوحيد؛ للمالك والمدير «دورك» مميّز في فريق الإدارة ← صلاحيات الأدوار)
struct AdminMyScopeView: View {
    let guide: RoleGuide
    @Environment(\.adminBackTitle) private var opener

    var body: some View {
        AdminPage(header: AdminPageHeader(back: opener ?? L10n.t("اليوم", "Today"),
                                          title: L10n.t("صلاحياتي · \(guide.title)", "My permissions · \(guide.title)"),
                                          subtitle: guide.mandate,
                                          glyph: guide.icon),
                  lead: AnyView(AdminRoleGuideCard(guide: guide, showsTitle: false)),
                  content: AnyView(EmptyView()))
    }
}

struct AdminRoleGuideCard: View {
    let guide: RoleGuide
    var showsTitle: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if showsTitle {
                HStack(spacing: DS.Spacing.md) {
                    AdminIconSquare(symbol: guide.icon, tint: guide.color)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(guide.title)
                            .dsFont(.headline)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(guide.mandate)
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                AdminRowDivider()
            }
            ForEach(guide.can, id: \.self) { line($0, allowed: true) }
            ForEach(guide.cannot, id: \.self) { line($0, allowed: false) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private func line(_ text: String, allowed: Bool) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .dsGlyph(DS.Glyph.md)
                .foregroundColor(allowed ? DS.Color.success : DS.Color.textTertiary)
                .padding(.top, DS.Spacing.xxs)
                .accessibilityHidden(true)
            Text(text)
                .dsFont(.subtitle)
                .foregroundColor(allowed ? DS.Color.textPrimary : DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(allowed ? text : L10n.t("غير مسموح: \(text)", "Can't: \(text)"))
    }
}

// MARK: - البحث الشامل

/// بحث في اللوحة: الأدوات والإعدادات بأسمائها، والأعضاء بالاسم أو الرقم، والطلبات (يفتح «الوارد» بالبحث)
struct AdminSearchView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @State private var query = ""
    /// ورقة العضو (نفس ورقة «العائلة») على نتائج البحث
    @State private var sheet: AdminMemberSheetContext?

    private var q: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var tools: [AdminTool] {
        guard !q.isEmpty else { return [] }
        let needle = ArabicTextNormalizer.normalizeForSearch(q)
        return AdminToolCatalog.tools(authVM: authVM, adminRequestVM: adminRequestVM).filter { tool in
            ([tool.title, tool.subtitle, tool.area.title] + tool.keywords)
                .contains { ArabicTextNormalizer.normalizeForSearch($0).contains(needle) }
        }
    }

    private var members: [FamilyMember] {
        guard authVM.canEditMembers, q.count >= 2 else { return [] }
        let needle = ArabicTextNormalizer.normalizeForSearch(q)
        let digits = q.filter(\.isNumber)
        return Array(memberVM.allMembers.filter { m in
            ArabicTextNormalizer.normalizeForSearch(m.fullName).contains(needle)
                || (digits.count >= 3 && (m.phoneNumber ?? "").contains(digits))
        }.prefix(20))
    }

    var body: some View {
        AdminHubPage {
            AdminBandHeader(title: L10n.t("بحث", "Search"),
                            subtitle: L10n.t("عضو، طلب، أو إعداد", "A member, a request or a setting")) {
                EmptyView()
            } accessory: {
                DSSearchField(text: $query, placeholder: L10n.t("بحث بالاسم أو الرقم أو الأداة", "Name, number or tool"))
                    .padding(.top, DS.Spacing.md)
            }
        } content: {
            if q.isEmpty {
                DSNoteCard(L10n.t("اكتب اسم عضو أو رقمه، أو اسم أداة مثل «الأجهزة» أو «وضع الصيانة».",
                                  "Type a member's name or number, or a tool like “Devices” or “Maintenance mode”."),
                           icon: "magnifyingglass")
            } else {
                if adminRequestVM.approvalsWorkflowOn || authVM.canModerate {
                    VStack(alignment: .leading, spacing: 0) {
                        NavigationLink { AdminLazyPage { AnyView(AdminAllRequestsView(initialSearch: q).adminArea(.inbox)) } } label: {
                            AdminListRow(icon: "tray.full.fill", tint: DS.Color.primary,
                                         title: L10n.t("ابحث في الوارد عن «\(q)»", "Search the inbox for “\(q)”"))
                        }
                        .buttonStyle(.plain)
                    }
                    .adminCard()
                }
                if !tools.isEmpty {
                    AdminToolCards(tools: tools.map {
                        AdminTool(id: $0.id, area: $0.area, group: L10n.t("الأدوات", "Tools"), title: $0.title,
                                  subtitle: "\($0.area.title) · \($0.subtitle)", icon: $0.icon, tint: $0.tint,
                                  keywords: $0.keywords, kind: $0.kind)
                    })
                }
                if !members.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        AdminCardHeader(title: L10n.t("الأعضاء", "Members"), badge: members.count, badgeTint: DS.Color.palm)
                        let ids = members.map(\.id)
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, m in
                            if index > 0 { AdminRowDivider() }
                            Button { sheet = AdminMemberSheetContext(ids: ids, start: index) } label: {
                                AdminListRow(icon: m.isDeceased == true ? "person.fill.xmark" : "person.fill",
                                             tint: DS.Color.palm, title: m.displayFullName,
                                             subtitle: m.phoneNumber.map { KuwaitPhone.display($0) })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .adminCard()
                }
                if tools.isEmpty && members.isEmpty {
                    DSEmptyView(L10n.t("لا نتائج", "No results"),
                                message: L10n.t("جرّب كلمة أخرى", "Try another word"), style: .card)
                }
            }
        }
        .dsTallBox(item: $sheet) { context in
            AdminMemberSheet(ids: context.ids, start: context.start)
        }
    }
}

extension Notification.Name {
    /// يفتح تبويب الشجرة على «شجرة النساء» (من «العائلة» في لوحة الإدارة)
    static let openWomenTree = Notification.Name("openWomenTree")
}
