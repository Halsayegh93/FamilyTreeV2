import SwiftUI

// MARK: - «المناسبات والإعلانات» = تقويم + منشئ واحد (الدفعة ب من «نفّذ كل المقترح»، ٢٠٢٦-١٠-٢٠)
//
// بدل ١٣ مدخلاً (كبسولتا «منشور مناسبة» و«إعلان وفاة»، بطاقة «الإعلانات» بخلاياها الأربع، «اليوم في العائلة»، صفوف
// الوفيات والإعلان وذكرى الراحلين ومنشورات المناسبات، صفحة «إشعار للأعضاء» وصفحة «رسالة تحديث التطبيق»): صفحة واحدة
// تتمرّر بعناوين صغيرة — بلا تبويبات ولا مبدّلات (طلب المالك):
//   الرأس: ‹ اليوم · العنوان قائمة الأقسام · ثلاثة أرقام (المالك والمدير) · «＋ إنشاء» ← المربّع الواحد (`AdminCreateWindow`).
//   «الإشعارات المجدولة» (المالك والمدير؛ تبسيط ٢٠٢٦-١٠-٢٢): قائمة مسطّحة بالموعد — الوقت · النص · لمن، و«تعديل» يفتح المنشئ
//     نفسه بمسودّته و«إلغاء» بتأكيد؛ بلا تجميع بالأيام، وبلا مجدول: «ما في إشعارات مجدولة».
//   «القادم» — بالأيام (اليوم · بكرة · هذا الأسبوع · لاحقاً): وفيات لم يُعلن عنها («إعلان» ← المنشئ على «إعلان وفاة»
//     جاهزاً) وذكرى الراحلين خلال ٣٠ يوماً (المراقب والمشرف: الذكرى فقط).
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

    /// ذكرى الأسبوع (المالك والمدير) ثم «＋ إنشاء» — بيت كل ما يُرسل أو يُنشر. «وفاة لم يُعلن» و«المجدول» في قسم «القادم»
    private func headerAccessory(_ feed: AdminUpcomingFeed) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if authVM.isAdmin {
                HStack(spacing: DS.Spacing.sm) {
                    AdminKPITile(value: "\(feed.memorialWeek)", label: L10n.t("ذكرى هذا الأسبوع", "Memorials this week"),
                                 icon: "moon.stars", tint: DS.Hub.kpiMine)
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

/// عناصر «القادم» مجمّعة بالأيام: اليوم · هذا الأسبوع · لاحقاً — والإشعارات المجدولة قائمة مسطّحة بالموعد
struct AdminUpcomingFeed {
    enum Item: Identifiable {
        case death(FamilyMember)
        case memorial(DeceasedMemorialBoard.Upcoming)

        var id: String {
            switch self {
            case .death(let m):        return "death-\(m.id)"
            case .memorial(let u):     return "memorial-\(u.id)"
            }
        }
    }

    struct Scheduled: Identifiable {
        let item: NotificationViewModel.ScheduledNotification
        let date: Date?
        var id: UUID { item.id }
    }

    enum Bucket: Int, CaseIterable, Identifiable {
        case today, tomorrow, week, later
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .today:
                return L10n.t("اليوم · \(AdminOccasionsText.dayTitle(Date()))", "Today · \(AdminOccasionsText.dayTitle(Date()))")
            case .tomorrow:
                let day = AdminOccasionsText.dayTitle(Date().addingTimeInterval(86400))
                return L10n.t("بكرة · \(day)", "Tomorrow · \(day)")
            case .week:  return L10n.t("هذا الأسبوع", "This week")
            case .later: return L10n.t("لاحقاً", "Later")
            }
        }

        static func of(days: Int) -> Bucket {
            switch days {
            case ...0: return .today
            case 1:    return .tomorrow
            case 2..<DeceasedMemorial.weekDays: return .week
            default:   return .later
            }
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
    /// الإشعارات المجدولة بالموعد (الأقرب أولاً) — بلا تجميع
    let scheduled: [Scheduled]

    init(members: [FamilyMember], scheduled: [NotificationViewModel.ScheduledNotification], announced: Set<UUID>?) {
        let board = DeceasedMemorialBoard(members)
        memorialWeek = board.withinWeek
        self.scheduled = scheduled
            .map { Scheduled(item: $0, date: $0.scheduledDate) }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        if let announced {
            deaths = members
                .filter { $0.isDeceased == true && $0.role != .pending && DeathRecency.isRecent($0.deathDate, within: DeathRecency.alertDays)
                    && !announced.contains($0.id) }
                .sorted { ($0.deathDate ?? "") > ($1.deathDate ?? "") }
        } else {
            deaths = []
        }
        var map: [Bucket: [(Double, Item)]] = [:]
        for m in deaths { map[.today, default: []].append((-1, .death(m))) }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
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
    @State private var cancelFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if authVM.isAdmin && !loading {
                AnyView(scheduledSection)
            }
            AdminSectionLabel(title: L10n.t("القادم", "Upcoming"),
                              trailing: authVM.isAdmin ? nil : L10n.t("ذكرى الراحلين", "Memorials"))
            if loading {
                AdminPageStateCard(.loading(L10n.t("جارٍ التحميل…", "Loading…")))
            } else if feed.isEmpty {
                AdminPageStateCard(.empty(L10n.t("لا شيء قادم", "Nothing upcoming"),
                                          message: L10n.t("لا ذكرى خلال ٣٠ يوماً", "No memorial in the next 30 days")))
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
                    let ok = await notificationVM.cancelScheduledNotification(n.id)
                    cancellingId = nil
                    if !ok { cancelFailed = true }
                }
            }
            Button(L10n.t("تراجع", "Keep it"), role: .cancel) { cancelTarget = nil }
        } message: {
            Text(L10n.t("«\(cancelTarget.map(Self.previewText) ?? "")» ما راح يوصل.", "“\(cancelTarget.map(Self.previewText) ?? "")” won't be sent."))
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

    /// «الإشعارات المجدولة»: قائمة مسطّحة بالموعد (الوقت · النص · لمن) — أو سطر هادئ واحد بلا مجدول
    private var scheduledSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: L10n.t("الإشعارات المجدولة", "Scheduled pushes"),
                              trailing: feed.scheduled.isEmpty ? nil : "\(feed.scheduled.count)")
            Group {
                if feed.scheduled.isEmpty {
                    AdminListRow(icon: "bell.slash", tint: DS.Color.textTertiary,
                                 title: L10n.t("ما في إشعارات مجدولة", "No scheduled pushes"),
                                 subtitle: L10n.t("«إنشاء» ← إعلان ← جدولة", "Create → Announcement → Schedule"),
                                 showsChevron: false)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(feed.scheduled.enumerated()), id: \.element.id) { index, s in
                            if index > 0 { AdminRowDivider() }
                            AdminScheduledPushRow(item: s.item, date: s.date, showsDay: true,
                                                  audience: AdminAnnounceKit.audienceLabel(ids: s.item.targetMemberIds,
                                                                                           members: memberVM.allMembers),
                                                  isBusy: cancellingId == s.item.id,
                                                  onEdit: { edit(s.item) }, onCancel: { cancelTarget = s.item })
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .adminCard()
        }
        .padding(.bottom, DS.Spacing.sm)
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

    /// «تعديل» = المنشئ نفسه بمسودّة الإشعار المجدول (النص، المستلمون، الموعد) — الحفظ يعدّل الصف نفسه
    private func edit(_ n: NotificationViewModel.ScheduledNotification) {
        AdminCreateWindow.open(.announcement, announce: AdminAnnounceDraft(editing: n, members: memberVM.allMembers),
                               authVM: authVM, newsVM: newsVM, notificationVM: notificationVM, memberVM: memberVM)
    }
}

/// إشعار مجدول في «الإشعارات المجدولة»: الوقت كبيراً في الطرف واليوم فوقه («اليوم» · «بكرة» · «الخميس»)، النص سطرين،
/// لمن، ثم «تعديل» و«إلغاء» صغيران — ومن أحجام إمكانية الوصول الوقت فوق النص
struct AdminScheduledPushRow: View {
    let item: NotificationViewModel.ScheduledNotification
    let date: Date?
    let showsDay: Bool
    /// «الكل» · «الكويت (210)» · «32 عضو»
    let audience: String
    let isBusy: Bool
    let onEdit: () -> Void
    let onCancel: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private static let timeColumn: CGFloat = 76

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
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    timeBlock(alignment: .leading)
                    details
                }
            } else {
                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    timeBlock(alignment: .center)
                        .frame(width: Self.timeColumn)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(RoundedRectangle(cornerRadius: DS.Hub.iconSquareRadius, style: .continuous)
                            .fill(DS.Color.sea.dsReadableGlyph.opacity(DS.Opacity.tintFill)))
                    details
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, DS.Spacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
        .accessibilityAction(named: L10n.t("تعديل", "Edit"), onEdit)
        .accessibilityAction(named: L10n.t("إلغاء الإشعار المجدول", "Cancel the scheduled push"), onCancel)
    }

    /// «9:00» كبيرة و«ص» صغيرة بجانبها، واليوم فوقها حين لا يقوله عنوان المجموعة
    private func timeBlock(alignment: HorizontalAlignment) -> some View {
        let parts = Self.timeParts(date)
        let ink = DS.Color.sea.dsReadableGlyph
        return VStack(alignment: alignment, spacing: 0) {
            if showsDay, let date {
                Text(AdminAnnounceKit.dayWord(date))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Text(verbatim: parts.clock)
                    .dsFont(.hubPulse)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !parts.period.isEmpty {
                    Text(verbatim: parts.period)
                        .dsFont(.hubButton)
                }
            }
            .foregroundColor(ink)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            if let customTitle {
                Text(customTitle)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
            }
            Text(text)
                .dsFont(.hubRow)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Spacing.xxs) {
                Image(systemName: item.isBroadcast ? "person.3.fill" : "person.2.fill")
                    .dsGlyph(DS.Glyph.xs, weight: .semibold)
                Text(verbatim: L10n.isArabic ? "← \(audience)" : "→ \(audience)")
                    .dsFont(.footnote)
                    .lineLimit(1)
            }
            .foregroundColor(DS.Color.textTertiary)
            HStack(spacing: DS.Spacing.sm) {
                if isBusy {
                    ProgressView()
                } else {
                    AdminPillButton(title: L10n.t("تعديل", "Edit"), icon: "pencil", style: .soft, action: onEdit)
                    AdminPillButton(title: L10n.t("إلغاء", "Cancel"), icon: "xmark", style: .reject, action: onCancel)
                }
            }
            .padding(.top, DS.Spacing.xxs)
        }
    }

    /// «9:00» و«ص» (أو «AM»)
    static func timeParts(_ date: Date?) -> (clock: String, period: String) {
        guard let date else { return ("—", "") }
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar_KW@numbers=latn" : "en_US")
        f.dateFormat = "h:mm"
        let clock = f.string(from: date)
        f.dateFormat = "a"
        return (clock, f.string(from: date))
    }

    private var spoken: String {
        let when = date.map { AdminAnnounceKit.when($0) } ?? ""
        return L10n.t("إشعار مجدول \(when): \(text). المستلمون: \(audience)", "Scheduled push \(when): \(text). To: \(audience)")
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
    /// «تصلها الإشعارات» = تسجيل صالح (الفاشل وحده لا تصله — الدفعة ١٤) — نفس رقم «الأجهزة ووصول الإشعارات» ورأس «الفريق والأمان»
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
                                // الحلقة المصغّرة الموحّدة (الدفعة ١٠) بلون الحال كما كان
                                DSRingValue(progress: reach.reachShare,
                                            tint: reach.reachPercent >= 90 ? DS.Color.success
                                                : (reach.reachPercent >= 70 ? DS.Color.warning : DS.Color.error),
                                            text: DSGaugeText.percent(reach.reachPercent))
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
