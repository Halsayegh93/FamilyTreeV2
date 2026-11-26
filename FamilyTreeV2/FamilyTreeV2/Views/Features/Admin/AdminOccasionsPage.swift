import SwiftUI

// MARK: - «المناسبات والإعلانات» (إعادة التصميم ٢٠٢٦-١١-٢٦ — spec C.11، الوحدة U14، النموذج ٧)
//
// صفحة واحدة تتمرّر بعناوين صغيرة — بلا تبويبات ولا مبدّلات، وبترتيب اتجاه المالك «أ — فرح وعزاء» (٢٠٢٦-١١-٠٦):
//   الرأس: «‹ الإدارة» · العنوان قائمة الأقسام «المناسبات والإعلانات ⌄» · التاريخ · «＋ إنشاء» ذهبي واحد (بدل زرّي «إرسال
//     إشعار» و«تصميم إعلان» — spec E.15) يفتح المنشئ الواحد `AdminCreateWindow` على «ماذا تنشئ؟» بأنواع دورك وحدها
//     (`AdminCreateKind.allowed`) · سطر أرقام الرأس للمالك والمدير: «1 وفاة لم تُعلن ‹» «3 مجدولة ‹» «2 ذكرى هذا الأسبوع ‹»
//     — كلٌّ يمرّر الصفحة إلى قسمه.
//   ١ «أفراح العائلة» (من الأخبار، خلال 30 يوماً): ثلاثة ثم «عرض الكل (N)»، و«بطاقة» على كل فرح ← المصمّم على قالبه.
//   ٢ «عزاء وذكرى»: وفاة لم تُعلن (المالك والمدير) بـ«إعلان» ← `DeathAnnouncementBox`، ذكرى الراحلين خلال 30 يوماً بحبّة
//     «اليوم»/«بعد 3 أيام»، ثم «متوفون بلا تاريخ وفاة كامل 134 ‹» ← `DeathDatesCampaignPage` (`canEditMembers`).
//   ٣ «الإعلانات عند الفتح» (المالك والمدير): صفوف بـ«إيقاف» (تأكيد). الإنشاء من «＋ إنشاء» وحده (spec E.16).
//   ٤ «الإعلانات» (المالك والمدير + `occasions.published`): «مجدول» بصفوفه («تعديل» · «إلغاء الموعد»)، ثم بطاقة الأبواب:
//     «المنشور N ‹» و«تصل الإشعارات إلى N جهازاً 93٪ ‹» (المالك ← «الأجهزة ووصول الإشعارات»).
// كل أمر = صلاحية الدور × «يعدّل» القسم في جدول السيرفر (`adminCanEdit(.occasions)`): المراقب «للاطلاع» بلا أزرار
// (`AdminOccasionsLogic.Access`). الحالات لكل قسم وحده (هيكل · خطأ بإعادة المحاولة · فارغ)، وآخر الصفحة «آخر تحديث».
// الهبوط: `AdminOccasionsAnchor` — معامل `init` الصريح يغلب `AdminAreaRouter.take(.occasions, hop:)` («اليوم»).
// الكتابة (الإيقاف، إلغاء الموعد، الإرسال) تمرّ بـ`DebugAdminProbe.dryRun` (T0). حارس المكدس: الصفحة والأقسام طبقات خلف
// `AnyView`، والوجهات خلف `AdminLazyPage`، والمنشئ في نافذته المستقلّة (لا مُعدِّل عرض على «اليوم»).
// لا قراءة جديدة على السيرفر: الأعضاء، `death_announcements`، `scheduled_notifications`، الأخبار، وإشعاراتك، والأجهزة.

/// نصوص مشتركة بين الصفحة والمنشئ
enum AdminOccasionsText {
    /// «توفي ١٨ أكتوبر» / «توفيت …» — والتاريخ غير الكامل (السنة فقط، هجري، بلا تاريخ) «لا يوجد تاريخ كامل للوفاة»
    /// بدل يوم خاطئ (السنة وحدها محفوظة ١ يناير — `DeceasedMemorial.classify`)
    static func deathLine(_ m: FamilyMember) -> String {
        let verb = m.isFemale ? L10n.t("توفيت", "Died") : L10n.t("توفي", "Died")
        guard case let .exact(year, month, day) = DeceasedMemorial.classify(m.deathDate),
              let date = DeceasedMemorial.gregorian.date(from: DateComponents(year: year, month: month, day: day)) else {
            return DeathDatesCampaign.noFullDate
        }
        return "\(verb) \(shortDate(date))"
    }

    /// صفّ وفاة لم تُعلن: «تُوفي أمس» · «تُوفيت اليوم» · «تُوفي 18 نوفمبر» — وغير الكامل كما في `deathLine`
    static func deathRecent(_ m: FamilyMember) -> String {
        let verb = m.isFemale ? L10n.t("تُوفيت", "Died") : L10n.t("تُوفي", "Died")
        guard case let .exact(year, month, day) = DeceasedMemorial.classify(m.deathDate),
              let date = DeceasedMemorial.gregorian.date(from: DateComponents(year: year, month: month, day: day)) else {
            return DeathDatesCampaign.noFullDate
        }
        return "\(verb) \(relativeDay(date))"
    }

    /// «المرحوم» / «المرحومة»
    static func late(_ m: FamilyMember) -> String {
        m.isFemale ? L10n.t("المرحومة", "the late") : L10n.t("المرحوم", "the late")
    }

    static func dayTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = LanguageManager.shared.locale
        f.dateFormat = L10n.isArabic ? "EEEE d MMMM" : "EEEE d MMM"
        return f.string(from: date)
    }

    /// وصف الرأس: «الخميس، 26 نوفمبر» — أرقام لاتينية (spec A.10، النموذج ٧)
    static func headerDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar_KW@numbers=latn" : "en_US")
        f.dateFormat = L10n.isArabic ? "EEEE، d MMMM" : "EEEE, d MMMM"
        return f.string(from: date)
    }

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar_KW@numbers=latn" : "en_US")
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    /// «اليوم» · «أمس» · «2 نوفمبر»
    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return L10n.t("اليوم", "today") }
        if cal.isDateInYesterday(date) { return L10n.t("أمس", "yesterday") }
        return shortDate(date)
    }

    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar_KW@numbers=latn" : "en_US")
        f.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) ? "d MMMM" : "d MMMM yyyy"
        return f.string(from: date)
    }
}

// MARK: - الصفحة

struct AdminOccasionsPage: View {
    /// قسم يُفتح عليه — يغلب هبوط «اليوم» المخزَّن (`AdminAreaRouter.take(.occasions, hop:)`)
    private let anchor: AdminOccasionsAnchor?

    init(anchor: AdminOccasionsAnchor? = nil) {
        self.anchor = anchor
    }

    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @Environment(\.adminAreaHop) private var hop
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// المعلن عنهم — nil قبل الجلب أو إن تعذّر (فلا تظهر «وفاة لم تُعلن» خطأً)
    @State private var announced: Set<UUID>? = nil
    @State private var announcedHealth: AdminStoreHealth = .idle
    /// الإشعارات المجدولة — الجلب لا يبلّغ عن فشله (`NotificationViewModel`)، فالحال تحميل ثم وصول
    @State private var scheduledHealth: AdminStoreHealth = .idle
    @State private var newsHealth: AdminStoreHealth = .idle
    /// جلب الأعضاء من هذه الصفحة (`AdminTodayLogic.membersFetchEnded`): علامة الفشل في نموذج الأعضاء تبقى من جلب سابق
    /// حتى ينجح جلب، فلا تُقرأ وحدها أثناء «أعد المحاولة» (F2، كما في «اليوم» F1)
    @State private var membersFetch: AdminStoreHealth = .idle
    /// وصلت إشعاراتك (عدد «المنشور» قبلها «—»)
    @State private var publishedReady = false
    /// ما يُحسب من الأعضاء مرة لكل تغيّر (لا مع كل رسم)
    @State private var feed = AdminUpcomingFeed.empty
    @State private var updatedAt: Date?
    @State private var started = false
    /// الهبوط ينتظر وصول الأرقام، ثم تُمرَّر الصفحة إليه
    @State private var pendingTarget: AdminOccasionsSection?
    @State private var scrollTarget: AdminOccasionsSection?
    /// كل سحب للتحديث يعيد جلب «الإعلانات عند الفتح» أيضاً
    @State private var refreshToken = 0

    private typealias Logic = AdminOccasionsLogic

    // MARK: الظهور

    private var access: Logic.Access {
        let kinds = AdminCreateKind.allowed(for: authVM)
        return .make(isAdmin: authVM.isAdmin, canSendNotifications: authVM.canSendNotifications,
                     cardKind: kinds.contains(.card),
                     announceKind: kinds.contains(.announcement) && authVM.adminCanEdit(.occasionsAnnounce),
                     seesPublished: authVM.adminSees(.occasionsPublished), areaEdit: authVM.adminCanEdit(.occasions),
                     canEditMembers: authVM.canEditMembers, familyEdit: authVM.adminCanEdit(.family),
                     ownerSystem: authVM.canViewSystemSettings)
    }

    /// أنواع «＋ إنشاء»: أنواع المنشئ لدورك (`AdminCreateKind.allowed`)، و«إرسال إشعار» بخانة `occasions.announce` كما كان
    private var creatorKinds: [AdminCreateKind] {
        AdminCreateKind.allowed(for: authVM).filter { $0 != .announcement || authVM.adminCanEdit(.occasionsAnnounce) }
    }

    /// الأعضاء: وصلوا = كلمة؛ وإلا حال جلب هذه الصفحة — هيكل أثناء التحميل، و«تعذّر التحميل» بعد أن ينتهي بفشل فقط (F2)
    private var membersHealth: AdminStoreHealth {
        AdminTodayLogic.membersHealth(hasMembers: !memberVM.allMembers.isEmpty, loadedAt: updatedAt, fetch: membersFetch)
    }

    // MARK: الصفحة

    // حارس المكدس: الصفحة طبقة خلف `AnyView`
    var body: some View {
        AnyView(page)
            .debugStackProbe("AdminOccasionsPage")
    }

    private var page: some View {
        let access = self.access
        let shown = Logic.sections(access)
        return ScrollViewReader { proxy in
            AdminHubPage {
                header(access)
            } content: {
                ForEach(shown, id: \.self) { section in
                    sectionView(section, access: access).id(section)
                }
                if let updatedAt {
                    AdminOccasionsFooter(date: updatedAt)
                }
            }
            .onChange(of: scrollTarget) { target in
                guard let target else { return }
                scrollTarget = nil
                if reduceMotion {
                    proxy.scrollTo(target, anchor: .top)
                } else {
                    withAnimation(DS.Anim.smooth) { proxy.scrollTo(target, anchor: .top) }
                }
            }
        }
        .task {
            if !started {
                started = true
                // الهبوط مرة واحدة — الصريح يغلب المخزَّن، والقسم المخفي لدورك يُتجاهل
                pendingTarget = Logic.scrollTarget(explicit: anchor, stored: AdminAreaRouter.take(.occasions, hop: hop),
                                                   shown: shown)
                rebuild()
            }
            // كل ظهور يجدّد المجدول والمعلن عنهم وإشعاراتك (كما كانت الصفحة) — الأعضاء والأخبار حين تفرغ فقط
            await load()
            if let target = pendingTarget {
                pendingTarget = nil
                scrollTarget = target
            }
        }
        .refreshable {
            refreshToken += 1
            await load(force: true)
        }
        .onChange(of: memberVM.membersVersion) { _ in rebuild() }
        .onChange(of: announced) { _ in rebuild() }
        .onReceive(NotificationCenter.default.publisher(for: .deathAnnouncementPublished)) { _ in
            Task { await reloadAnnounced() }
        }
    }

    // MARK: الرأس

    private func header(_ access: Logic.Access) -> some View {
        AdminBandHeader(title: AdminArea.occasions.title, subtitle: AdminOccasionsText.headerDate(Date()),
                        badge: access.readOnly ? AdminPageHeader.readOnlyText : nil,
                        isAreaRoot: true, items: headerItems(access)) {
            if access.create && !creatorKinds.isEmpty {
                AdminPillButton(title: L10n.t("إنشاء", "Create"), icon: "plus", style: .gold, action: openCreator)
                    .accessibilityHint(creatorKinds.map(\.title).joined(separator: L10n.t("، ", ", ")))
            }
        }
    }

    /// سطر الأرقام (المالك والمدير): كل رقم يمرّر الصفحة إلى قسمه — الصفر باهت ولا يفتح شيئاً (`AdminHeaderItemLook`)
    private func headerItems(_ access: Logic.Access) -> [AdminHeaderItem] {
        guard access.headerLine else { return [] }
        let f = feed
        let deathsHealth = AdminStoreHealth.combined([membersHealth, announcedHealth])
        var items: [AdminHeaderItem] = [
            AdminHeaderItem(id: "deaths", value: f.deaths.count, label: L10n.t("وفاة لم تُعلن", "unannounced deaths"),
                            health: deathsHealth, tap: .action({ jump(.grief) }),
                            retry: { Task { await reloadAnnounced() } },
                            spoken: L10n.t("\(f.deaths.count) وفاة لم تُعلن، ينقلك إلى عزاء وذكرى",
                                           "\(f.deaths.count) unannounced deaths, moves to condolences"))
        ]
        if access.announcements {
            let n = notificationVM.scheduledNotifications.count
            items.append(AdminHeaderItem(id: "scheduled", value: n, label: L10n.t("مجدولة", "scheduled"),
                                         health: scheduledHealth, tap: .action({ jump(.announcements) }),
                                         spoken: L10n.t("\(n) إشعارات مجدولة، ينقلك إلى الإعلانات",
                                                        "\(n) scheduled pushes, moves to announcements")))
        }
        items.append(AdminHeaderItem(id: "memorials", value: f.memorialWeek,
                                     label: L10n.t("ذكرى هذا الأسبوع", "memorials this week"),
                                     health: membersHealth, tap: .action({ jump(.grief) }),
                                     retry: { Task { await reloadMembers() } },
                                     spoken: L10n.t("\(f.memorialWeek) ذكرى هذا الأسبوع، ينقلك إلى عزاء وذكرى",
                                                    "\(f.memorialWeek) memorials this week, moves to condolences")))
        return items
    }

    private func jump(_ section: AdminOccasionsSection) {
        scrollTarget = section
    }

    /// «＋ إنشاء» — المنشئ الواحد في نافذته المستقلّة على «ماذا تنشئ؟» بأنواع دورك
    private func openCreator() {
        let kinds = creatorKinds
        guard let first = kinds.first else { return }
        AdminCreateWindow.open(first, chooser: true, kinds: kinds,
                               authVM: authVM, newsVM: newsVM, notificationVM: notificationVM, memberVM: memberVM)
    }

    // MARK: الأقسام — كلٌّ طبقة خلف `AnyView`

    private func sectionView(_ section: AdminOccasionsSection, access: Logic.Access) -> AnyView {
        switch section {
        case .joys:
            return AnyView(AdminOccasionsJoysCard(health: newsHealth, canCard: access.card,
                                                  retry: { Task { await reloadNews() } }))
        case .grief:
            return AnyView(AdminOccasionsGriefCard(feed: feed, membersHealth: membersHealth,
                                                   announcedHealth: announcedHealth, access: access,
                                                   retryMembers: { Task { await reloadMembers() } },
                                                   retryAnnounced: { Task { await reloadAnnounced() } }))
        case .launch:
            return AnyView(AdminLaunchAnnouncementsCard(canStop: access.stopLaunch, canCreate: access.create,
                                                        refreshToken: refreshToken))
        case .announcements:
            return AnyView(AdminOccasionsAnnouncementsCard(scheduledHealth: scheduledHealth, canEdit: access.editScheduled,
                                                           showsReach: access.reach, publishedReady: publishedReady,
                                                           retryScheduled: { Task { await reloadScheduled() } }))
        }
    }

    // MARK: الجلب

    private func rebuild() {
        feed = AdminUpcomingFeed(members: memberVM.allMembers, announced: authVM.isAdmin ? announced : nil,
                                 countsIncomplete: authVM.canEditMembers)
    }

    private func load(force: Bool = false) async {
        if memberVM.allMembers.isEmpty || force { await fetchMembers(force: force) }
        // «أفراح العائلة» من الأخبار المحمّلة نفسها (لكل الأدوار)
        if newsVM.allNews.isEmpty || force {
            await reloadNews(force: force)
        } else if newsHealth == .idle {
            newsHealth = .loaded(at: Date())
        }
        if authVM.isAdmin {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in await reloadScheduled() }
                group.addTask { @MainActor in await reloadAnnounced() }
                group.addTask { @MainActor in
                    await notificationVM.fetchNotifications(force: force)
                    publishedReady = true
                }
                // نفس مخزن «الأجهزة ووصول الإشعارات» (الفريق والأمان — للمالك فقط) — رقم واحد بتعريف واحد في المكانين
                if authVM.canViewSystemSettings {
                    group.addTask { @MainActor in await AdminDeviceReachStore.shared.refresh(force: force) }
                }
            }
        }
        updatedAt = Date()
        rebuild()
    }

    private func reloadMembers() async {
        await fetchMembers(force: true)
        rebuild()
    }

    /// جلب الأعضاء بحاله: أثناءه هيكل، وبعده وصلوا أو فشل حقيقي — الملغى (غادر الصفحة) هيكل يُعاد في الظهور التالي
    private func fetchMembers(force: Bool) async {
        membersFetch = membersFetch.beginning()
        await memberVM.fetchAllMembers(force: force)
        membersFetch = AdminTodayLogic.membersFetchEnded(hasMembers: !memberVM.allMembers.isEmpty,
                                                         loadFailed: memberVM.membersLoadFailed && !Task.isCancelled)
    }

    private func reloadNews(force: Bool = true) async {
        newsHealth = newsHealth.beginning()
        await newsVM.fetchNews(force: force)
        newsHealth = newsHealth.ending(success: newsVM.newsLoadError == nil)
    }

    private func reloadAnnounced() async {
        guard authVM.isAdmin else { return }
        announcedHealth = announcedHealth.beginning()
        let ids = await AdminTodayFetch.announcedDeathIds()
        if let ids { announced = ids }
        announcedHealth = announcedHealth.ending(success: ids != nil)
    }

    private func reloadScheduled() async {
        guard authVM.isAdmin else { return }
        scheduledHealth = scheduledHealth.beginning()
        await notificationVM.fetchScheduledNotifications()
        scheduledHealth = scheduledHealth.ending(success: true)
    }
}

/// «آخر تحديث 9:41» آخر الصفحة — ١٣ رمادي في الوسط (spec A.2)
private struct AdminOccasionsFooter: View {
    let date: Date

    var body: some View {
        Text(AdminStoreHealthText.updated(date))
            .dsFont(.subtitle)
            .foregroundColor(DS.Color.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - قطع مشتركة

/// قسم: العنوان (spec A.4) ثم بطاقته على بُعد ٨ — والبطاقتان في قسم واحد على بُعد ١٢
struct AdminOccasionsSectionStack<Content: View>: View {
    let title: String
    var note: String? = nil
    var link: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: title, trailing: note, link: link)
            VStack(alignment: .leading, spacing: DS.Hub.cardGap) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// رابط «عرض الكل (N)» / «أقل» في طرف عنوان القسم — ١٥ كحلي، لمسه ٤٤ (spec A.4)
struct AdminOccasionsToggleLink: View {
    let total: Int
    @Binding var expanded: Bool

    var body: some View {
        Button {
            withAnimation(DS.Anim.snappy) { expanded.toggle() }
        } label: {
            AdminCardLinkLabel(title: expanded ? L10n.t("أقل", "Less")
                                               : L10n.t("عرض الكل (\(total))", "Show all (\(total))"),
                               showsChevron: false)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityAddTraits(.isButton)
    }
}

/// صفّ في بطاقات الصفحة (spec A.6): البادئ (صورة العضو أو مربّع الأيقونة، أو لا شيء) · العنوان ١٥ / الوصف ١٣ رمادي
/// سطران · الطرف (حبّة، قيمة، سهم). ٤٤ لسطر و٥٦ لسطرين. من أحجام إمكانية الوصول الطرف تحت النص فلا يُضغط النص
struct AdminOccasionsRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let twoLines = subtitle.map { !$0.isEmpty } ?? false
        let stacked = typeSize.isAccessibilitySize
        HStack(alignment: stacked ? .top : .center, spacing: DS.Spacing.md) {
            leading()
            if stacked {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    text
                    trailing()
                }
                Spacer(minLength: 0)
            } else {
                text
                Spacer(minLength: DS.Spacing.xs)
                trailing()
            }
        }
        .padding(.vertical, DS.Spacing.xsm)
        .frame(minHeight: twoLines ? DS.Hub.rowMinHeightTwoLines : DS.Hub.rowMinHeight)
        .contentShape(Rectangle())
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(title)
                .dsFont(.body)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// قسم فارغ: بطاقة بسطر واحد هادئ (ما الفارغ — وأول إجراء إن وُجد)
struct AdminOccasionsQuietLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: icon, tint: DS.Color.textTertiary, filled: false, glyph: DS.Glyph.md)
            Text(text)
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: DS.Hub.rowMinHeight, alignment: .leading)
        .adminCard()
        .accessibilityElement(children: .combine)
    }
}

/// صفّ «تعذّر …» داخل بطاقة قسم يعرض بقية بياناته (كل مخزن يفشل وحده — spec C.11): مربّع خفيف + السطر + «أعد المحاولة»
struct AdminOccasionsRetryRow: View {
    let text: String
    let retry: () -> Void

    var body: some View {
        AdminOccasionsRow(title: text) {
            AdminIconSquare(symbol: "exclamationmark.triangle.fill", tint: DS.Color.error, filled: false)
        } trailing: {
            AdminPillButton(title: AdminStoreHealthText.retry, icon: "arrow.clockwise", style: .soft, action: retry)
        }
    }
}

// MARK: - ١ «أفراح العائلة»

/// أخبار الزواج والمواليد والتهاني المنشورة خلال ٣٠ يوماً — الأحدث أولاً، ثلاثة ثم «عرض الكل (N)»؛ «بطاقة» تفتح المصمّم
/// على قالبها (زواج ← عقد قران، مولود ← قدوم مولود)
struct AdminOccasionsJoysCard: View {
    let health: AdminStoreHealth
    /// «بطاقة» (تصميم البطاقات × «يعدّل» القسم)
    let canCard: Bool
    let retry: () -> Void

    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @State private var showsAll = false

    static let joyTypes: [String] = ["زواج", "مولود", "تهنئة"]
    private static let windowDays = 30

    private var joys: [NewsPost] {
        let since = Date().addingTimeInterval(-Double(Self.windowDays) * 86_400)
        return newsVM.allNews
            .filter { Self.joyTypes.contains($0.type) && $0.timestamp >= since
                && ($0.approval_status == nil || $0.approval_status == "approved") }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        let all = joys
        let count = AdminOccasionsLogic.visibleCount(total: all.count, limit: AdminOccasionsLogic.collapsedRows,
                                                     expanded: showsAll)
        let visible = Array(all.prefix(count))
        AdminOccasionsSectionStack(
            title: L10n.t("أفراح العائلة", "Family joys"),
            note: L10n.t("من الأخبار", "From News"),
            link: AdminOccasionsLogic.needsToggle(total: all.count, limit: AdminOccasionsLogic.collapsedRows)
                ? AnyView(AdminOccasionsToggleLink(total: all.count, expanded: $showsAll)) : nil
        ) {
            if all.isEmpty {
                switch health.look {
                case .skeleton:
                    AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الأخبار…", "Loading news…"), rows: 2))
                case .unknown:
                    AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأخبار", "Couldn't load news"),
                                              message: L10n.t("الأفراح تأتي من الأخبار", "Joys come from News"),
                                              retry: retry))
                default:
                    AdminOccasionsQuietLine(icon: "heart",
                                            text: L10n.t("لا أفراح في الأخبار خلال 30 يوماً",
                                                         "No joyful news in the last 30 days"))
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, post in
                        if index > 0 { AdminRowDivider(inset: AdminRowDivider.iconInset) }
                        row(post)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .adminCard()
            }
        }
    }

    private func row(_ post: NewsPost) -> some View {
        let firstLine = (post.content.split(separator: "\n").first.map(String.init) ?? post.content)
            .trimmingCharacters(in: .whitespaces)
        let subtitle = "\(post.type) · \(AdminOccasionsText.relativeDay(post.timestamp))"
        return AdminOccasionsRow(title: firstLine, subtitle: subtitle) {
            AdminIconSquare(symbol: NewsTypeHelper.icon(for: post.type), tint: NewsTypeHelper.color(for: post.type),
                            filled: false, glyph: DS.Glyph.md)
        } trailing: {
            if canCard {
                AdminPillButton(title: L10n.t("بطاقة", "Card"), style: .soft) { card(post) }
                    .accessibilityLabel(L10n.t("تصميم بطاقة", "Design a card"))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func card(_ post: NewsPost) {
        let template: String? = switch post.type {
        case "زواج": "wedding"
        case "مولود": "newborn"
        default: nil
        }
        // فرح بإعلان معروف (زواج ← عقد قران، مولود ← قدوم مولود) يفتح المصمّم عليه مباشرة؛ غيره يختار الإعلان أولاً
        AdminCreateWindow.open(.card, cardTemplate: template, chooser: false,
                               authVM: authVM, newsVM: newsVM, notificationVM: notificationVM, memberVM: memberVM)
    }
}

// MARK: - ٢ «عزاء وذكرى»

/// وفيات لم يُعلن عنها («إعلان» — المالك والمدير)، ثم ذكرى الراحلين خلال ٣٠ يوماً (ثلاث ثم «عرض الكل»)، ثم
/// «متوفون بلا تاريخ وفاة كامل N ‹» ← «تواريخ الوفاة» (`canEditMembers`)
struct AdminOccasionsGriefCard: View {
    let feed: AdminUpcomingFeed
    let membersHealth: AdminStoreHealth
    let announcedHealth: AdminStoreHealth
    let access: AdminOccasionsLogic.Access
    let retryMembers: () -> Void
    let retryAnnounced: () -> Void

    @State private var showsAll = false

    /// صفوف البطاقة بترتيبها
    private enum Row: Identifiable {
        case death(FamilyMember)
        case announceFailed
        case memorial(DeceasedMemorialBoard.Upcoming)
        case dates(Int)

        var id: String {
            switch self {
            case .death(let m):    return "death-\(m.id)"
            case .announceFailed:  return "announce-failed"
            case .memorial(let u): return "memorial-\(u.id)"
            case .dates:           return "dates"
            }
        }

        /// بداية الفاصل فوق الصفّ = بداية نصّه
        var dividerInset: CGFloat {
            switch self {
            case .death:          return DS.Icon.avatarRow + DS.Spacing.md
            case .announceFailed, .dates: return AdminRowDivider.iconInset
            case .memorial:       return 0
            }
        }
    }

    private func rows() -> [Row] {
        var list: [Row] = []
        if access.deaths {
            if announcedHealth.look == .unknown { list.append(.announceFailed) }
            list += feed.deaths.map { Row.death($0) }
        }
        let count = AdminOccasionsLogic.visibleCount(total: feed.memorials.count, limit: AdminOccasionsLogic.collapsedRows,
                                                     expanded: showsAll)
        list += feed.memorials.prefix(count).map { Row.memorial($0) }
        if access.datesRow && feed.incomplete > 0 { list.append(.dates(feed.incomplete)) }
        return list
    }

    var body: some View {
        let total = feed.memorials.count
        AdminOccasionsSectionStack(
            title: L10n.t("عزاء وذكرى", "Condolences & memorials"),
            link: AdminOccasionsLogic.needsToggle(total: total, limit: AdminOccasionsLogic.collapsedRows)
                ? AnyView(AdminOccasionsToggleLink(total: total, expanded: $showsAll)) : nil
        ) {
            switch membersHealth.look {
            case .skeleton:
                AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الذكرى…", "Loading memorials…"), rows: 3))
            case .unknown:
                AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                                          message: L10n.t("الذكرى والوفيات تُحسب منهم", "Memorials and deaths come from them"),
                                          retry: retryMembers))
            default:
                content
            }
        }
    }

    @ViewBuilder private var content: some View {
        let list = rows()
        if list.isEmpty {
            AdminOccasionsQuietLine(icon: "leaf", text: L10n.t("لا ذكرى خلال 30 يوماً", "No memorial in the next 30 days"))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { AdminRowDivider(inset: row.dividerInset) }
                    view(row)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .adminCard()
        }
    }

    private func view(_ row: Row) -> AnyView {
        switch row {
        case .death(let m):
            return AnyView(deathRow(m))
        case .announceFailed:
            return AnyView(AdminOccasionsRetryRow(text: L10n.t("تعذّر معرفة الوفيات غير المعلنة",
                                                               "Couldn't check unannounced deaths"),
                                                  retry: retryAnnounced))
        case .memorial(let u):
            return AnyView(memorialRow(u))
        case .dates(let n):
            return AnyView(AdminOccasionsDatesRow(count: n, opens: access.datesOpens))
        }
    }

    private func deathRow(_ m: FamilyMember) -> some View {
        AdminOccasionsRow(title: m.shortFullName, subtitle: AdminOccasionsText.deathRecent(m)) {
            DSMemberAvatar(name: m.fullName, avatarUrl: m.avatarUrl, size: DS.Icon.avatarRow, roleColor: DS.Color.deceased)
                .grayscale(1)
                .accessibilityHidden(true)
        } trailing: {
            if access.announceDeath {
                AdminPillButton(title: L10n.t("إعلان", "Announce"), style: .navy) { announce(m) }
                    .accessibilityLabel(L10n.t("إعلان وفاة \(m.shortFullName)", "Announce \(m.shortFullName)'s death"))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("وفاة لم تُعلن", "Death not announced"))
    }

    private func memorialRow(_ u: DeceasedMemorialBoard.Upcoming) -> some View {
        let when = DeceasedMemorial.whenLabel(u.anniversary.daysUntil, arabic: L10n.isArabic)
        return AdminOccasionsRow(title: u.member.shortFullName,
                                 subtitle: DeceasedMemorial.anniversaryLine(u.anniversary, arabic: L10n.isArabic)) {
            EmptyView()
        } trailing: {
            AdminStatePill(title: when, tone: .off)
        }
        .accessibilityElement(children: .combine)
    }

    /// مربّع «إعلان وفاة» مباشرة والمتوفى جاهز (كصفحة المتوفى) — نافذته المستقلّة
    private func announce(_ m: FamilyMember) {
        DeathAnnouncementPresenter.open(DeathAnnouncementTarget(id: m.id, name: m.fullName, isFemale: m.isFemale,
                                                                deathDate: m.deathDate))
    }
}

/// «متوفون بلا تاريخ وفاة كامل 134 ‹» — بيت الاستكمال «تواريخ الوفاة» (تحت «العائلة»)؛ بلا سهم لمن لا يعدّل الأعضاء
private struct AdminOccasionsDatesRow: View {
    let count: Int
    let opens: Bool

    var body: some View {
        if opens {
            NavigationLink {
                AdminLazyPage {
                    AnyView(DeathDatesCampaignPage().adminBackTitle(AdminArea.occasions.title).adminArea(.family))
                }
            } label: {
                face
            }
            .buttonStyle(AdminRowPressStyle())
            .accessibilityHint(L10n.t("يفتح تواريخ الوفاة", "Opens death dates"))
        } else {
            face
        }
    }

    private var face: some View {
        AdminListRow(icon: "calendar.badge.exclamationmark", tint: DS.Color.warning,
                     title: L10n.t("متوفون بلا تاريخ وفاة كامل", "Deceased without a full death date"),
                     showsChevron: opens) {
            AdminRowValue(text: AdminNumberText.grouped(count))
        }
    }
}

// MARK: - ٤ «الإعلانات» (المالك والمدير)

/// «مجدول» بصفوفه («تعديل» · «إلغاء الموعد») أو سطر هادئ، ثم بطاقة الأبواب: «المنشور N ‹» ووصول الإشعارات (للمالك)
struct AdminOccasionsAnnouncementsCard: View {
    let scheduledHealth: AdminStoreHealth
    /// «تعديل» · «إلغاء الموعد» (المالك والمدير × «يعدّل» القسم)
    let canEdit: Bool
    let showsReach: Bool
    let publishedReady: Bool
    let retryScheduled: () -> Void

    @ObservedObject private var devices = AdminDeviceReachStore.shared
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @State private var cancelTarget: NotificationViewModel.ScheduledNotification? = nil
    @State private var cancellingId: UUID? = nil
    @State private var cancelFailed = false

    var body: some View {
        AdminOccasionsSectionStack(title: L10n.t("الإعلانات", "Announcements")) {
            scheduledCard
            doorsCard
        }
        .dsAlert(L10n.t("إلغاء الموعد؟", "Cancel the schedule?"), isPresented: Binding(
            get: { cancelTarget != nil },
            set: { if !$0 { cancelTarget = nil } }
        ), icon: "clock.badge.xmark") {
            Button(L10n.t("إلغاء الموعد", "Cancel the schedule"), role: .destructive) {
                guard let n = cancelTarget else { return }
                cancelTarget = nil
                cancel(n)
            }
            Button(L10n.t("تراجع", "Keep it"), role: .cancel) { cancelTarget = nil }
        } message: {
            Text(L10n.t("«\(cancelTarget.map(Self.previewText) ?? "")» لن يُرسل.", "“\(cancelTarget.map(Self.previewText) ?? "")” won't be sent."))
        }
        .dsAlert(L10n.t("تعذّر الإلغاء", "Couldn't cancel"), isPresented: $cancelFailed) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.t("حاول مرة أخرى.", "Try again."))
        }
    }

    /// أول النص (للتأكيد)
    nonisolated static func previewText(_ n: NotificationViewModel.ScheduledNotification) -> String {
        let text = n.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = text.isEmpty ? n.title : text
        return line.count > 40 ? String(line.prefix(40)) + "…" : line
    }

    // MARK: «مجدول»

    @ViewBuilder private var scheduledCard: some View {
        let list = notificationVM.scheduledNotifications
            .sorted { ($0.scheduledDate ?? .distantPast) < ($1.scheduledDate ?? .distantPast) }
        if list.isEmpty && scheduledHealth.look == .skeleton {
            AdminPageStateCard(.loading(L10n.t("جارٍ تحميل المجدول…", "Loading scheduled pushes…"), rows: 2))
        } else if list.isEmpty && scheduledHealth.look == .unknown {
            AdminPageStateCard(.error(L10n.t("تعذّر تحميل المجدول", "Couldn't load scheduled pushes"), retry: retryScheduled))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                groupLine(count: list.count)
                if list.isEmpty {
                    Text(L10n.t("لا إشعارات مجدولة", "No scheduled pushes"))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: DS.Hub.rowMinHeight, alignment: .leading)
                }
                ForEach(list) { item in
                    AdminRowDivider()
                    AdminScheduledPushRow(item: item, date: item.scheduledDate,
                                          audience: AdminAnnounceKit.audienceLabel(ids: item.targetMemberIds,
                                                                                   members: memberVM.allMembers),
                                          canEdit: canEdit, isBusy: cancellingId == item.id,
                                          onEdit: { edit(item) }, onCancel: { cancelTarget = item })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .adminCard()
        }
    }

    /// «مجدول · 3» — عنوان مجموعة داخل البطاقة (spec A.5: سطر لا صندوق)
    private func groupLine(count: Int) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(L10n.t("مجدول", "Scheduled"))
                .dsFont(.sectionTitle)
                .foregroundColor(DS.Color.textSecondary)
            if count > 0 {
                // النقطة والعدد نصّان منفصلان — نصّ واحد «· 3» يقلب النقطة بعد العدد في العربية
                Text(verbatim: "·")
                    .dsFont(.sectionTitle)
                    .foregroundColor(DS.Color.textTertiary)
                Text(verbatim: "\(count)")
                    .dsFont(.sectionTitle)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: DS.Icon.tapTarget)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: الأبواب

    private var doorsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            publishedRow
            if showsReach {
                AdminRowDivider()
                reachRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    /// «المنشور N ‹» ← القائمة كاملة
    private var publishedRow: some View {
        let count = AdminOccasionsPublishedCard.items(news: newsVM.allNews, notifications: notificationVM.notifications).count
        return NavigationLink {
            AdminLazyPage { AnyView(AdminOccasionsPublishedPage().adminBackTitle(AdminArea.occasions.title).adminArea(.occasions)) }
        } label: {
            AdminOccasionsRow(title: L10n.t("المنشور", "Published")) {
                EmptyView()
            } trailing: {
                AdminRowValue(text: publishedReady ? AdminNumberText.grouped(count) : AdminStoreHealthText.placeholder)
                DSChevron()
            }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(AdminRowPressStyle())
    }

    /// «تصل الإشعارات إلى 412 جهازاً» «93٪ ‹» — نفس مخزن «الأجهزة ووصول الإشعارات» (رقم واحد بتعريف واحد)
    @ViewBuilder private var reachRow: some View {
        let stats = devices.stats.flatMap { $0.total > 0 ? $0 : nil }
        if devices.rows == nil && devices.failed {
            AdminOccasionsRow(title: L10n.t("وصول الإشعارات", "Notification reach")) {
                EmptyView()
            } trailing: {
                AdminStatePill(health: .failed(lastGood: nil), title: "", tone: .off,
                               retry: { Task { await devices.refresh(force: true) } })
            }
        } else {
            NavigationLink {
                AdminLazyPage { AnyView(AdminPushHealthView().adminBackTitle(AdminArea.occasions.title).adminArea(.team)) }
            } label: {
                AdminOccasionsRow(title: stats.map { L10n.t("تصل الإشعارات إلى \(AdminNumberText.grouped($0.reach)) جهازاً",
                                                            "Notifications reach \(AdminNumberText.grouped($0.reach)) devices") }
                                    ?? L10n.t("وصول الإشعارات", "Notification reach"),
                                  subtitle: stats.map { L10n.t("من \(AdminNumberText.grouped($0.total)) جهازاً مسجّلاً",
                                                               "of \(AdminNumberText.grouped($0.total)) registered devices") }) {
                    EmptyView()
                } trailing: {
                    AdminRowValue(text: stats.map { L10n.t("\($0.reachPercent)٪", "\($0.reachPercent)%") }
                                    ?? AdminStoreHealthText.placeholder)
                    DSChevron()
                }
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(AdminRowPressStyle())
            .accessibilityHint(L10n.t("الأجهزة ووصول الإشعارات", "Devices & notification reach"))
        }
    }

    // MARK: الأوامر

    /// «تعديل» = المنشئ نفسه بمسودّة الإشعار المجدول (النص، المستلمون، الموعد) — الحفظ يعدّل الصف نفسه
    private func edit(_ n: NotificationViewModel.ScheduledNotification) {
        AdminCreateWindow.open(.announcement, announce: AdminAnnounceDraft(editing: n, members: memberVM.allMembers),
                               authVM: authVM, newsVM: newsVM, notificationVM: notificationVM, memberVM: memberVM)
    }

    /// «إلغاء الموعد» بعد التأكيد — أثناء تجربة دور لا كتابة (`DebugAdminProbe.dryRun`) ويُصطنع النجاح محلياً
    private func cancel(_ n: NotificationViewModel.ScheduledNotification) {
        if DebugAdminProbe.dryRun("cancel scheduled notification \(n.id)") {
            withAnimation(DS.Anim.quick) { notificationVM.scheduledNotifications.removeAll { $0.id == n.id } }
            return
        }
        Task {
            cancellingId = n.id
            let ok = await notificationVM.cancelScheduledNotification(n.id)
            cancellingId = nil
            if !ok { cancelFailed = true }
        }
    }
}

/// «المنشور» كاملاً (من سطر «الإعلانات»)
struct AdminOccasionsPublishedPage: View {
    var body: some View {
        AdminPage(header: AdminPageHeader(title: L10n.t("المنشور", "Published"),
                                          subtitle: L10n.t("الإعلانات وإعلانات الوفاة والتحديث والإشعارات المرسلة",
                                                           "Announcements, obituaries, updates and pushes sent"),
                                          glyph: "bell.fill"),
                  content: AnyView(AdminOccasionsPublishedCard(showsTitle: false)))
    }
}

// MARK: - ما يُحسب من الأعضاء

/// الوفيات التي لم يُعلن عنها، والذكرى خلال ٣٠ يوماً، وعدد المتوفين بلا تاريخ كامل — يُحسب مرة لكل تغيّر في الأعضاء
/// أو المعلن عنهم (لا مع كل رسم)
struct AdminUpcomingFeed {
    /// الوفيات الحديثة التي لم يُعلن عنها (المالك والمدير — فارغة قبل معرفة المعلن عنهم)
    let deaths: [FamilyMember]
    /// ذكراهم خلال ٣٠ يوماً — الأقرب أولاً
    let memorials: [DeceasedMemorialBoard.Upcoming]
    /// ذكرى خلال ٧ أيام (رقم الرأس)
    let memorialWeek: Int
    /// متوفون بلا تاريخ وفاة كامل (`DeathDatesCampaign.stats` — لمن يعدّل الأعضاء، وإلا ٠)
    let incomplete: Int

    static let empty = AdminUpcomingFeed(deaths: [], memorials: [], memorialWeek: 0, incomplete: 0)

    private init(deaths: [FamilyMember], memorials: [DeceasedMemorialBoard.Upcoming], memorialWeek: Int, incomplete: Int) {
        self.deaths = deaths
        self.memorials = memorials
        self.memorialWeek = memorialWeek
        self.incomplete = incomplete
    }

    init(members: [FamilyMember], announced: Set<UUID>?, countsIncomplete: Bool) {
        let board = DeceasedMemorialBoard(members)
        memorials = board.upcoming
        memorialWeek = board.withinWeek
        incomplete = countsIncomplete ? DeathDatesCampaign.stats(members).incomplete : 0
        if let announced {
            deaths = members
                .filter { $0.isDeceased == true && $0.role != .pending && DeathRecency.isRecent($0.deathDate, within: DeathRecency.alertDays)
                    && !announced.contains($0.id) }
                .sorted { ($0.deathDate ?? "") > ($1.deathDate ?? "") }
        } else {
            deaths = []
        }
    }
}

/// إشعار مجدول (spec C.11، النموذج ٧): الوقت «9:00 ص» ١٥ شبه عريض واليوم ١٣ رمادي تحته في عمود الطرف، النص ١٥ سطرين،
/// لمن ١٣ رمادي، ثم «تعديل» و«إلغاء الموعد» حبّتان بفراغ ١٢ (لمس ٤٤ بلا تداخل). من أحجام إمكانية الوصول الوقت فوق النص
struct AdminScheduledPushRow: View {
    let item: NotificationViewModel.ScheduledNotification
    let date: Date?
    /// «الكل» · «الكويت (210)» · «32 عضو»
    let audience: String
    /// الحبّتان لمن يعدّل (المالك والمدير × «يعدّل» القسم)
    var canEdit: Bool = true
    let isBusy: Bool
    let onEdit: () -> Void
    let onCancel: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// عمود الوقت (يصطفّ النص في كل الصفوف) — رسم الصفّ وحده
    private static let timeColumn: CGFloat = 64

    /// النص الذي كتبه المرسل — وعنوانه إن لم يكن الافتراضي
    private var text: String {
        let body = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? item.title : body
    }
    private var customTitle: String? {
        let t = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == AdminAnnounceKit.defaultTitle || t == text ? nil : t
    }

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.sm))
                             : AnyLayout(HStackLayout(alignment: .top, spacing: DS.Spacing.md))
        layout {
            timeBlock
                .frame(minWidth: stacked ? nil : Self.timeColumn, alignment: .leading)
            details
            if !stacked { Spacer(minLength: 0) }
        }
        .padding(.vertical, DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // عنصر واحد بجملته (لا ينفّذ شيئاً بالضغط المزدوج)، والحبّتان إجراءان مسمّيان لمن يعدّل
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .modifier(AdminScheduledActions(enabled: canEdit && !isBusy, onEdit: onEdit, onCancel: onCancel))
    }

    /// «9:00 ص» ثم «غداً»
    private var timeBlock: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(verbatim: date.map { AdminOccasionsText.time($0) } ?? AdminStoreHealthText.placeholder)
                .dsFont(.hubValue)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let date {
                Text(AdminAnnounceKit.dayWord(date))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            if let customTitle {
                Text(customTitle)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
            }
            Text(text)
                .dsFont(.body)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(audience)
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1)
            if canEdit {
                Group {
                    if isBusy {
                        AdminStatePill(title: L10n.t("جارٍ الإلغاء", "Cancelling"), tone: .off, isBusy: true)
                    } else {
                        AdminPillRow {
                            AdminPillButton(title: L10n.t("تعديل", "Edit"), style: .soft, action: onEdit)
                            AdminPillButton(title: L10n.t("إلغاء الموعد", "Cancel the schedule"), style: .reject,
                                            action: onCancel)
                                .accessibilityHint(L10n.t("يسأل قبل الإلغاء", "Asks before cancelling"))
                        }
                    }
                }
                .padding(.top, DS.Spacing.xs)
            }
        }
    }

    private var spoken: String {
        let when = date.map { AdminAnnounceKit.when($0) } ?? ""
        return L10n.t("إشعار مجدول \(when): \(text). المستلمون: \(audience)", "Scheduled push \(when): \(text). To: \(audience)")
    }
}

/// إجراءات القارئ الصوتي على صفّ المجدول (نفس الحبّتين) — لمن يعدّل فقط
private struct AdminScheduledActions: ViewModifier {
    let enabled: Bool
    let onEdit: () -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .accessibilityAction(named: L10n.t("تعديل", "Edit"), onEdit)
                .accessibilityAction(named: L10n.t("إلغاء الموعد", "Cancel the schedule"), onCancel)
        } else {
            content
        }
    }
}

// MARK: - «المنشور»

/// ما نُشر للأعضاء: الإعلانات وإعلانات الوفاة (الأخبار)، إعلانات التحديث والإشعارات المرسلة (إشعاراتك) — الأحدث أولاً
struct AdminOccasionsPublishedCard: View {
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    /// false = داخل صفحة «المنشور» (العنوان في رأسها)
    var showsTitle: Bool = true
    @State private var limit = Self.pageSize

    private static let pageSize = 20

    struct Item: Identifiable {
        let id: String
        let kind: AdminCreateKind?
        let kindTitle: String
        let icon: String
        let tint: Color
        let title: String
        let date: Date
    }

    /// كل المنشور — الأحدث أولاً (يقرؤه سطر «المنشور» في «الإعلانات» أيضاً)
    static func items(news: [NewsPost], notifications: [AppNotification]) -> [Item] {
        var list: [Item] = []
        for post in news where post.type == "إعلان" || post.type == "وفاة" {
            let death = post.type == "وفاة"
            let firstLine = post.content.split(separator: "\n").first.map(String.init) ?? post.content
            list.append(Item(id: "news-\(post.id)", kind: death ? .death : .announcement,
                             kindTitle: death ? L10n.t("إعلان وفاة", "Obituary") : L10n.t("إعلان في الأخبار", "Announcement in News"),
                             icon: death ? AdminCreateKind.death.icon : AdminCreateKind.announcement.icon,
                             tint: death ? DS.Color.slate : DS.Color.sea, title: firstLine, date: post.timestamp))
        }
        for n in notifications where n.kind == "app_update" || n.kind == "admin_broadcast" {
            let update = n.kind == "app_update"
            list.append(Item(id: "notif-\(n.id)", kind: update ? .appUpdate : .announcement,
                             kindTitle: update ? L10n.t("إعلان تحديث التطبيق", "App update notice") : L10n.t("إشعار للأعضاء", "Push to members"),
                             icon: update ? AdminCreateKind.appUpdate.icon : "bell.fill",
                             tint: update ? DS.Color.accent : DS.Color.info, title: n.title, date: n.createdDate))
        }
        return list.sorted { $0.date > $1.date }
    }

    var body: some View {
        let all = Self.items(news: newsVM.allNews, notifications: notificationVM.notifications)
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            if showsTitle {
                AdminSectionLabel(title: L10n.t("المنشور", "Published"),
                                  trailing: all.isEmpty ? nil : AdminNumberText.grouped(all.count))
            }
            if all.isEmpty {
                AdminPageStateCard(.empty(L10n.t("لم يُنشر شيء بعد", "Nothing published yet"),
                                          message: L10n.t("يظهر هنا ما يُنشر من «＋ إنشاء»", "What you publish from Create appears here")))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(all.prefix(limit).enumerated()), id: \.element.id) { index, item in
                        if index > 0 { AdminRowDivider(inset: AdminRowDivider.iconInset) }
                        AdminListRow(icon: item.icon, tint: item.tint, title: item.title,
                                     subtitle: "\(item.kindTitle) · \(AdminOccasionsText.shortDate(item.date))",
                                     showsChevron: false)
                    }
                    if all.count > limit {
                        AdminPillButton(title: L10n.t("عرض المزيد (\(all.count - limit))", "Show more (\(all.count - limit))"),
                                        icon: "chevron.down", style: .soft) {
                            withAnimation(DS.Anim.snappy) { limit += Self.pageSize }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, DS.Spacing.sm)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .adminCard()
            }
        }
    }
}
