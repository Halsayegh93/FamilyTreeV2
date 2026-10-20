import SwiftUI

// MARK: - «المناسبات والإعلانات» = تقويم + منشئ واحد (الدفعة ب من «نفّذ كل المقترح»، ٢٠٢٦-١٠-٢٠)
//
// بدل ١٣ مدخلاً (كبسولتا «منشور مناسبة» و«إعلان وفاة»، بطاقة «الإعلانات» بخلاياها الأربع، «اليوم في العائلة»، صفوف
// الوفيات والإعلان وذكرى الراحلين ومنشورات المناسبات، صفحة «إشعار للأعضاء» وصفحة «رسالة تحديث التطبيق»): صفحة واحدة
// تتمرّر بعناوين صغيرة — بلا تبويبات ولا مبدّلات (طلب المالك):
//   الرأس: ‹ اليوم · العنوان قائمة الأقسام · ثلاثة أرقام (المالك والمدير) · «＋ إنشاء» ← المربّع الواحد (`AdminCreateWindow`).
//   «القادم» — بالأيام: وفيات لم يُعلن عنها («إعلان» ← المنشئ على «إعلان وفاة» جاهزاً)، الإشعارات المجدولة («إلغاء»)،
//     وذكرى الراحلين خلال ٣٠ يوماً (المراقب والمشرف: الذكرى فقط).
//   «المنشور» (المالك والمدير) — الإعلانات وإعلانات الوفاة في الأخبار، إعلانات التحديث، والإشعارات المرسلة.
//   أرقام فقط تفتح بيوتها: «تصل الإشعارات إلى N جهازاً» ← الفريق والأمان، و«N متوفى تاريخ وفاته غير مكتمل» ← العائلة.
// لا قراءة جديدة على السيرفر: الأعضاء المحمّلون، `death_announcements`، `scheduled_notifications`، الأخبار، وإشعاراتك.

/// نصوص مشتركة بين الصفحة والمنشئ
enum AdminOccasionsText {
    /// «توفي ١٨ أكتوبر» / «توفيت …» — أو «بلا تاريخ وفاة»
    static func deathLine(_ m: FamilyMember) -> String {
        let verb = m.isFemale ? L10n.t("توفيت", "Died") : L10n.t("توفي", "Died")
        guard let raw = m.deathDate?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return L10n.t("بلا تاريخ وفاة", "No death date")
        }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: String(raw.prefix(10))) else { return "\(verb) \(raw.prefix(10))" }
        return "\(verb) \(shortDate(date))"
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

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar_KW@numbers=latn" : "en_US")
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar_KW@numbers=latn" : "en_US")
        f.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) ? "d MMMM" : "d MMMM yyyy"
        return f.string(from: date)
    }
}

struct AdminOccasionsPage: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @Environment(\.dynamicTypeSize) private var typeSize

    /// المعلن عنهم — nil قبل الجلب أو إن تعذّر (فلا تظهر «وفاة لم يُعلن عنها» خطأً)
    @State private var announced: Set<UUID>? = nil

    var body: some View {
        let feed = AdminUpcomingFeed(members: memberVM.allMembers,
                                     scheduled: authVM.isAdmin ? notificationVM.scheduledNotifications : [],
                                     announced: authVM.isAdmin ? announced : nil)
        AdminHubPage {
            AdminBandHeader(title: AdminArea.occasions.title, isAreaRoot: true) {
                EmptyView()
            } accessory: {
                AnyView(headerAccessory(feed))
            }
        } content: {
            AnyView(AdminOccasionsUpcomingCard(feed: feed, loading: memberVM.allMembers.isEmpty))
            if authVM.isAdmin {
                AnyView(AdminOccasionsPublishedCard())
            }
            AnyView(AdminOccasionsNumbersCard())
        }
        .task { await load() }
        .refreshable { await load(force: true) }
        .onReceive(NotificationCenter.default.publisher(for: .deathAnnouncementPublished)) { _ in
            Task { if let ids = await AdminTodayFetch.announcedDeathIds() { announced = ids } }
        }
    }

    private func load(force: Bool = false) async {
        if memberVM.allMembers.isEmpty || force { await memberVM.fetchAllMembers(force: force) }
        guard authVM.isAdmin else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in await notificationVM.fetchScheduledNotifications() }
            group.addTask { @MainActor in if let ids = await AdminTodayFetch.announcedDeathIds() { announced = ids } }
            group.addTask { @MainActor in if newsVM.allNews.isEmpty || force { await newsVM.fetchNews(force: force) } }
            group.addTask { @MainActor in await notificationVM.fetchNotifications(force: force) }
            // نفس مخزن «الأجهزة ووصول الإشعارات» (الفريق والأمان) — رقم واحد بتعريف واحد في المكانين
            group.addTask { @MainActor in await AdminDeviceReachStore.shared.refresh(force: force) }
        }
    }

    // MARK: الرأس

    /// الأرقام الثلاثة (المالك والمدير) ثم «＋ إنشاء» — بيت كل ما يُرسل أو يُنشر
    private func headerAccessory(_ feed: AdminUpcomingFeed) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if authVM.isAdmin {
                HStack(spacing: DS.Spacing.sm) {
                    AdminKPITile(value: "\(feed.memorialWeek)", label: L10n.t("ذكرى هذا الأسبوع", "Memorials this week"),
                                 icon: "moon.stars", tint: DS.Hub.kpiMine)
                    AdminKPITile(value: announced == nil ? "—" : "\(feed.deaths.count)",
                                 label: L10n.t("وفاة لم يُعلن", "Not announced"),
                                 icon: "megaphone", tint: feed.deaths.isEmpty ? DS.Color.textOnPrimary : DS.Hub.kpiHot)
                    AdminKPITile(value: "\(notificationVM.scheduledNotifications.count)",
                                 label: L10n.t("إشعار مجدول", "Scheduled"), icon: "clock",
                                 tint: notificationVM.scheduledNotifications.isEmpty ? DS.Color.textOnPrimary : DS.Hub.kpiLate)
                }
            }
            Button {
                AdminCreateWindow.open(authVM: authVM, newsVM: newsVM, notificationVM: notificationVM, memberVM: memberVM)
            } label: {
                AdminPillLabel(title: L10n.t("إنشاء", "Create"), icon: "plus", style: .gold,
                               height: DS.Hub.pillHeightCard, fullWidth: true)
            }
            .buttonStyle(DSPressStyle())
            .accessibilityHint(authVM.canSendNotifications
                ? L10n.t("إعلان، إعلان وفاة، بطاقة تهنئة أو تعزية، إعلان تحديث التطبيق",
                         "Announcement, obituary, greeting or condolence card, app update notice")
                : L10n.t("بطاقة تهنئة أو تعزية", "Greeting or condolence card"))
        }
        .padding(.top, DS.Spacing.md)
    }
}

// MARK: - «القادم»

/// عناصر «القادم» مجمّعة بالأيام: اليوم · هذا الأسبوع · لاحقاً
struct AdminUpcomingFeed {
    enum Item: Identifiable {
        case death(FamilyMember)
        case scheduled(NotificationViewModel.ScheduledNotification, Date?)
        case memorial(DeceasedMemorialBoard.Upcoming)

        var id: String {
            switch self {
            case .death(let m):        return "death-\(m.id)"
            case .scheduled(let n, _): return "scheduled-\(n.id)"
            case .memorial(let u):     return "memorial-\(u.id)"
            }
        }
    }

    enum Bucket: Int, CaseIterable, Identifiable {
        case today, week, later
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .today: return L10n.t("اليوم · \(AdminOccasionsText.dayTitle(Date()))", "Today · \(AdminOccasionsText.dayTitle(Date()))")
            case .week:  return L10n.t("هذا الأسبوع", "This week")
            case .later: return L10n.t("لاحقاً", "Later")
            }
        }

        static func of(days: Int) -> Bucket {
            days <= 0 ? .today : (days < DeceasedMemorial.weekDays ? .week : .later)
        }
    }

    /// الوفيات الحديثة التي لم يُعلن عنها (المالك والمدير — فارغة قبل معرفة المعلن عنهم)
    let deaths: [FamilyMember]
    struct DayGroup: Identifiable {
        let bucket: Bucket
        let items: [Item]
        var id: Int { bucket.rawValue }
    }

    let groups: [DayGroup]
    /// ذكرى خلال ٧ أيام (رقم الرأس)
    let memorialWeek: Int

    init(members: [FamilyMember], scheduled: [NotificationViewModel.ScheduledNotification], announced: Set<UUID>?) {
        let board = DeceasedMemorialBoard(members)
        memorialWeek = board.withinWeek
        if let announced {
            deaths = members
                .filter { $0.isDeceased == true && $0.role != .pending && DeathRecency.isRecent($0.deathDate)
                    && !announced.contains($0.id) }
                .sorted { ($0.deathDate ?? "") > ($1.deathDate ?? "") }
        } else {
            deaths = []
        }
        var map: [Bucket: [(Double, Item)]] = [:]
        for m in deaths { map[.today, default: []].append((-1, .death(m))) }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for n in scheduled {
            let date = n.scheduledDate
            let days = date.map { cal.dateComponents([.day], from: today, to: cal.startOfDay(for: $0)).day ?? 0 } ?? 0
            map[Bucket.of(days: days), default: []].append((date?.timeIntervalSince1970 ?? 0, .scheduled(n, date)))
        }
        for u in board.upcoming {
            let when = cal.date(byAdding: .day, value: u.anniversary.daysUntil, to: today) ?? today
            map[Bucket.of(days: u.anniversary.daysUntil), default: []].append((when.timeIntervalSince1970 + 1, .memorial(u)))
        }
        groups = Bucket.allCases.compactMap { b in
            guard let list = map[b], !list.isEmpty else { return nil }
            return DayGroup(bucket: b, items: list.sorted { $0.0 < $1.0 }.map(\.1))
        }
    }

    var isEmpty: Bool { groups.isEmpty }
}

/// «القادم»: عنوان صغير ثم بطاقة لكل يوم/فترة — الصفوف بأزرارها في مكانها
struct AdminOccasionsUpcomingCard: View {
    let feed: AdminUpcomingFeed
    let loading: Bool

    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @State private var cancelTarget: NotificationViewModel.ScheduledNotification? = nil
    @State private var cancellingId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: L10n.t("القادم", "Upcoming"),
                              trailing: authVM.isAdmin ? nil : L10n.t("ذكرى الراحلين", "Memorials"))
            if loading {
                AdminPageStateCard(.loading(L10n.t("جارٍ التحميل…", "Loading…")))
            } else if feed.isEmpty {
                AdminPageStateCard(.empty(L10n.t("لا شيء قادم", "Nothing upcoming"),
                                          message: authVM.isAdmin
                                            ? L10n.t("لا ذكرى ولا إشعار مجدول خلال ٣٠ يوماً", "No memorial or scheduled push in 30 days")
                                            : L10n.t("لا ذكرى خلال ٣٠ يوماً", "No memorial in the next 30 days")))
            } else {
                ForEach(feed.groups) { group in
                    AnyView(groupCard(group.bucket, group.items))
                }
            }
        }
        .dsAlert(L10n.t("إلغاء الإشعار المجدول؟", "Cancel the scheduled push?"), isPresented: Binding(
            get: { cancelTarget != nil },
            set: { if !$0 { cancelTarget = nil } }
        ), icon: "clock.badge.xmark") {
            Button(L10n.t("إلغاء الإشعار", "Cancel push"), role: .destructive) {
                guard let n = cancelTarget else { return }
                cancelTarget = nil
                Task {
                    cancellingId = n.id
                    await notificationVM.cancelScheduledNotification(n.id)
                    cancellingId = nil
                }
            }
            Button(L10n.t("تراجع", "Keep it"), role: .cancel) { cancelTarget = nil }
        } message: {
            Text(L10n.t("«\(cancelTarget?.title ?? "")» لن يُرسل.", "“\(cancelTarget?.title ?? "")” won't be sent."))
        }
    }

    private func groupCard(_ bucket: AdminUpcomingFeed.Bucket, _ items: [AdminUpcomingFeed.Item]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(bucket.title)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .padding(.bottom, DS.Spacing.xxs)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { AdminRowDivider() }
                AnyView(row(item))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    @ViewBuilder
    private func row(_ item: AdminUpcomingFeed.Item) -> some View {
        switch item {
        case .death(let m):
            AdminListRow(icon: NewsTypeHelper.icon(for: "وفاة"), tint: DS.Color.error,
                         title: L10n.t("وفاة لم يُعلن عنها", "Death not announced"),
                         subtitle: "\(AdminOccasionsText.late(m)) \(m.shortFullName) · \(AdminOccasionsText.deathLine(m))",
                         showsChevron: false) {
                AdminPillButton(title: L10n.t("إعلان", "Announce"), style: .navy) { announce(m) }
            }
            .accessibilityAction(named: L10n.t("إعلان", "Announce")) { announce(m) }
        case .scheduled(let n, let date):
            AdminListRow(icon: "bell.badge.fill", tint: DS.Color.sea,
                         title: scheduledTitle(date), subtitle: scheduledSubtitle(n), showsChevron: false) {
                if cancellingId == n.id {
                    ProgressView()
                } else {
                    AdminPillButton(title: L10n.t("إلغاء", "Cancel"), style: .soft) { cancelTarget = n }
                }
            }
            .accessibilityAction(named: L10n.t("إلغاء الإشعار المجدول", "Cancel the scheduled push")) { cancelTarget = n }
        case .memorial(let u):
            AdminListRow(icon: "moon.stars.fill", tint: DS.Color.sadu,
                         title: L10n.t("ذكرى \(AdminOccasionsText.late(u.member)) \(u.member.fullName)",
                                       "\(u.member.fullName)'s anniversary"),
                         subtitle: DeceasedMemorial.anniversaryLine(u.anniversary, arabic: L10n.isArabic),
                         showsChevron: false) {
                AdminValueChip(text: DeceasedMemorial.whenLabel(u.anniversary.daysUntil, arabic: L10n.isArabic),
                               tint: u.anniversary.daysUntil <= 1 ? DS.Color.accent : DS.Color.primary)
            }
        }
    }

    /// المنشئ الواحد على «إعلان وفاة» والمتوفى جاهز
    private func announce(_ m: FamilyMember) {
        AdminCreateWindow.open(.death, death: DeathAnnouncementTarget(id: m.id, name: m.fullName, isFemale: m.isFemale,
                                                                      deathDate: m.deathDate),
                               authVM: authVM, newsVM: newsVM, notificationVM: notificationVM, memberVM: memberVM)
    }

    private func scheduledTitle(_ date: Date?) -> String {
        guard let date else { return L10n.t("إشعار مجدول", "Scheduled push") }
        if Calendar.current.isDateInToday(date) {
            return L10n.t("إشعار مجدول · \(AdminOccasionsText.time(date))", "Scheduled push · \(AdminOccasionsText.time(date))")
        }
        let when = "\(AdminOccasionsText.dayTitle(date)) · \(AdminOccasionsText.time(date))"
        return L10n.t("إشعار مجدول · \(when)", "Scheduled push · \(when)")
    }

    private func scheduledSubtitle(_ n: NotificationViewModel.ScheduledNotification) -> String {
        let to = n.isBroadcast ? L10n.t("للجميع", "Everyone") : L10n.t("لـ \(n.targetCount) عضو", "\(n.targetCount) members")
        return "\(n.title) · \(to)"
    }
}

// MARK: - «المنشور»

/// ما نُشر للأعضاء: الإعلانات وإعلانات الوفاة (الأخبار)، إعلانات التحديث والإشعارات المرسلة (إشعاراتك) — الأحدث أولاً
struct AdminOccasionsPublishedCard: View {
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @State private var limit = Self.pageSize

    private static let pageSize = 6

    struct Item: Identifiable {
        let id: String
        let kind: AdminCreateKind?
        let kindTitle: String
        let icon: String
        let tint: Color
        let title: String
        let date: Date
    }

    private var items: [Item] {
        var list: [Item] = []
        for post in newsVM.allNews where post.type == "إعلان" || post.type == "وفاة" {
            let death = post.type == "وفاة"
            let firstLine = post.content.split(separator: "\n").first.map(String.init) ?? post.content
            list.append(Item(id: "news-\(post.id)", kind: death ? .death : .announcement,
                             kindTitle: death ? L10n.t("إعلان وفاة", "Obituary") : L10n.t("إعلان في الأخبار", "Announcement in News"),
                             icon: death ? AdminCreateKind.death.icon : AdminCreateKind.announcement.icon,
                             tint: death ? DS.Color.slate : DS.Color.sea, title: firstLine, date: post.timestamp))
        }
        for n in notificationVM.notifications where n.kind == "app_update" || n.kind == "admin_broadcast" {
            let update = n.kind == "app_update"
            list.append(Item(id: "notif-\(n.id)", kind: update ? .appUpdate : .announcement,
                             kindTitle: update ? L10n.t("إعلان تحديث التطبيق", "App update notice") : L10n.t("إشعار للأعضاء", "Push to members"),
                             icon: update ? AdminCreateKind.appUpdate.icon : "bell.fill",
                             tint: update ? DS.Color.accent : DS.Color.info, title: n.title, date: n.createdDate))
        }
        return list.sorted { $0.date > $1.date }
    }

    var body: some View {
        let all = items
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: L10n.t("المنشور", "Published"), trailing: all.isEmpty ? nil : "\(all.count)")
            if all.isEmpty {
                AdminPageStateCard(.empty(L10n.t("لم يُنشر شيء بعد", "Nothing published yet"),
                                          message: L10n.t("يظهر هنا ما يُنشر من «إنشاء»", "What you publish from Create appears here")))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(all.prefix(limit).enumerated()), id: \.element.id) { index, item in
                        if index > 0 { AdminRowDivider() }
                        AdminListRow(icon: item.icon, tint: item.tint, title: item.title,
                                     subtitle: "\(item.kindTitle) · \(AdminOccasionsText.shortDate(item.date))",
                                     showsChevron: false)
                    }
                    if all.count > limit {
                        AdminPillButton(title: L10n.t("عرض المزيد (\(all.count - limit))", "Show more (\(all.count - limit))"),
                                        icon: "chevron.down", style: .soft, height: DS.Hub.pillHeightCard) {
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

// MARK: - أرقام فقط تفتح بيوتها

/// «تصل الإشعارات إلى N جهازاً · P٪» ← الفريق والأمان ← «الأجهزة ووصول الإشعارات»، و«N متوفى تاريخ وفاته غير مكتمل» ← العائلة ←
/// متوفون ← غير مكتمل. لا أوامر هنا — البيت هناك
struct AdminOccasionsNumbersCard: View {
    /// «تصلها الإشعارات» = رمز صالح ومحدَّث خلال ٣٠ يوماً — نفس رقم «الأجهزة ووصول الإشعارات» ورأس «الفريق والأمان»
    @ObservedObject private var devices = AdminDeviceReachStore.shared
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel

    private var incomplete: Int { memberVM.allMembers.filter { $0.role != .pending && AdminMemberFacts.deathIncomplete($0) }.count }

    var body: some View {
        let showsReach = authVM.canSendNotifications
        let reach = devices.stats.flatMap { $0.total > 0 ? $0 : nil }
        let showsDates = authVM.canEditMembers && incomplete > 0
        if showsReach || showsDates {
            VStack(alignment: .leading, spacing: 0) {
                if showsReach {
                    NavigationLink {
                        AdminLazyPage { AnyView(AdminPushHealthView().adminBackTitle(AdminArea.occasions.title).adminArea(.team)) }
                    } label: {
                        AdminListRow(icon: "bell.and.waves.left.and.right.fill", tint: DS.Color.info,
                                     title: reach.map { L10n.t("تصل الإشعارات إلى \($0.reach) جهازاً", "Notifications reach \($0.reach) devices") }
                                        ?? L10n.t("وصول الإشعارات", "Notification reach"),
                                     subtitle: AdminArea.team.title) {
                            if let reach {
                                AdminValueChip(text: L10n.t("\(reach.reachPercent)٪", "\(reach.reachPercent)%"),
                                               tint: reach.reachPercent >= 90 ? DS.Color.success
                                                   : (reach.reachPercent >= 70 ? DS.Color.warning : DS.Color.error))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if showsReach && showsDates { AdminRowDivider() }
                if showsDates {
                    NavigationLink {
                        AdminLazyPage {
                            AnyView(AdminMembersPage(chip: .deceased, sub: .deathIncomplete)
                                .adminBackTitle(AdminArea.occasions.title).adminArea(.family))
                        }
                    } label: {
                        AdminListRow(icon: "calendar.badge.exclamationmark", tint: DS.Color.warning,
                                     title: L10n.t("\(incomplete) متوفى تاريخ وفاته غير مكتمل", "\(incomplete) deceased with an incomplete date"),
                                     subtitle: L10n.t("لا تظهر ذكراهم — الاستكمال في «العائلة»", "No memorial shows — complete them in Family"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .adminCard()
        }
    }
}
