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
//   أرقام فقط تفتح بيوتها: «تصل الإشعارات إلى N جهازاً» ← الفريق والأمان (للمالك)، و«N متوفى: لا يوجد تاريخ كامل للوفاة» ←
//   «إدارة تواريخ الوفاة».
// لا قراءة جديدة على السيرفر: الأعضاء المحمّلون، `death_announcements`، `scheduled_notifications`، الأخبار، وإشعاراتك.

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

/// الصفحة باتجاه «أ — فرح وعزاء» (اختيار المالك ٢٠٢٦-١١-٠٦، samples/occasions-and-matching): المحتوى بالمعنى —
/// «أفراح العائلة · من الأخبار» (زواج · مولود · تهنئة خلال ٣٠ يوماً، و«بطاقة» على كل فرح) ← «عزاء وذكرى» (وفاة لم يُعلن عنها
/// «إعلان»، ذكرى الراحلين خلال ٣٠ يوماً، و«N متوفى بلا تاريخ كامل» «أكمل») ← «الإعلانات» (المالك والمدير: وصول الإشعارات في
/// عنوانها، المجدول «تعديل/إلغاء»، و«المنشور» سطر بعدده يفتح القائمة كاملة). زرّان مباشران في الرأس بدل «إنشاء»:
/// «إرسال إشعار» (`canSendNotifications`) و«تصميم بطاقة» (`canModerate`) — نفس المنشئ الواحد (`AdminCreateWindow`).
/// القسم الفاضي سطر واحد هادئ. لا قراءة جديدة على السيرفر.
struct AdminOccasionsPage: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel

    /// المعلن عنهم — nil قبل الجلب أو إن تعذّر (فلا تظهر «وفاة لم يُعلن عنها» خطأً)
    @State private var announced: Set<UUID>? = nil

    var body: some View {
        let feed = AdminUpcomingFeed(members: memberVM.allMembers,
                                     scheduled: authVM.isAdmin ? notificationVM.scheduledNotifications : [],
                                     announced: authVM.isAdmin ? announced : nil)
        let loading = memberVM.allMembers.isEmpty
        AdminHubPage {
            AdminBandHeader(title: AdminArea.occasions.title, subtitle: AdminOccasionsText.dayTitle(Date()),
                            isAreaRoot: true) {
                EmptyView()
            } accessory: {
                AnyView(AdminOccasionsHeaderButtons())
            }
        } content: {
            // «أفراح العائلة» بيت «بطاقة» — لمن يصمّم البطاقات (المراقب يشوف «عزاء وذكرى» بس — الجدول من السيرفر)
            if AdminCreateKind.allowed(for: authVM).contains(.card) {
                AnyView(AdminOccasionsJoysCard())
            }
            AnyView(AdminOccasionsGriefCard(feed: feed, loading: loading))
            // «الإعلانات عند الفتح» — المالك والمدير (طلب المالك ٢٠٢٦-١١-١٢)
            if authVM.isAdmin {
                AnyView(AdminLaunchAnnouncementsCard())
            }
            if authVM.isAdmin && authVM.adminSees(.occasionsPublished) {
                AnyView(AdminOccasionsAnnouncementsCard(feed: feed, loading: loading))
            }
        }
        .task { await load() }
        .refreshable { await load(force: true) }
        .onReceive(NotificationCenter.default.publisher(for: .deathAnnouncementPublished)) { _ in
            Task { if let ids = await AdminTodayFetch.announcedDeathIds() { announced = ids } }
        }
    }

    private func load(force: Bool = false) async {
        if memberVM.allMembers.isEmpty || force { await memberVM.fetchAllMembers(force: force) }
        // «أفراح العائلة» من الأخبار المحمّلة نفسها (لكل الأدوار)
        if newsVM.allNews.isEmpty || force { await newsVM.fetchNews(force: force) }
        guard authVM.isAdmin else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in await notificationVM.fetchScheduledNotifications() }
            group.addTask { @MainActor in if let ids = await AdminTodayFetch.announcedDeathIds() { announced = ids } }
            group.addTask { @MainActor in await notificationVM.fetchNotifications(force: force) }
            // نفس مخزن «الأجهزة ووصول الإشعارات» (الفريق والأمان — للمالك فقط) — رقم واحد بتعريف واحد في المكانين
            if authVM.canViewSystemSettings {
                group.addTask { @MainActor in await AdminDeviceReachStore.shared.refresh(force: force) }
            }
        }
    }
}

// MARK: - الرأس: زرّان مباشران

/// «إرسال إشعار» و«تصميم بطاقة» جنباً إلى جنب (فوق بعض من أحجام إمكانية الوصول) — كلٌّ بصلاحيته
struct AdminOccasionsHeaderButtons: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DS.Spacing.sm))
            : AnyLayout(HStackLayout(spacing: DS.Spacing.sm))
        let allowed = AdminCreateKind.allowed(for: authVM)
        layout {
            if allowed.contains(.announcement) && authVM.adminAccess(.occasionsAnnounce).canEdit { button(.announcement) }
            if allowed.contains(.card) { button(.card) }
        }
        .padding(.top, DS.Spacing.md)
    }

    private func button(_ kind: AdminCreateKind) -> some View {
        Button {
            // كل زر يفتح نوعه وحده — «إرسال إشعار» بلا «تصميم إعلان» والعكس (المالك ٢٠٢٦-١١-٠٨)
            AdminCreateWindow.open(kind, chooser: false,
                                   authVM: authVM, newsVM: newsVM, notificationVM: notificationVM, memberVM: memberVM)
        } label: {
            AdminPillLabel(title: kind.title, icon: kind == .announcement ? "speaker.wave.2" : "photo",
                           style: .gold, height: DS.Hub.pillHeightCard, fullWidth: true)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityHint(kind.note)
    }
}

// MARK: - قطع مشتركة

/// عنوان قسم صغير بطرف اختياري قابل للضغط («عرض الكل (4)»)
struct AdminOccasionsSectionTitle: View {
    let title: String
    var actionTitle: String? = nil
    var onAction: () -> Void = {}

    var body: some View {
        HStack {
            // خط عناوين الأقسام الموحّد ولونها (`DSBox.sectionTitleFont` / `fieldLabel`)
            Text(title)
                .font(DSBox.sectionTitleFont)
                .foregroundColor(DS.Color.fieldLabel)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Spacing.sm)
            if let actionTitle {
                Button(action: onAction) {
                    Text(actionTitle)
                        .dsFont(.chip)
                        .foregroundColor(DS.Color.primary)
                        .dsTapArea(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                }
                .buttonStyle(DSPressStyle())
            }
        }
        .padding(.horizontal, DS.Spacing.xs)
        .padding(.top, DS.Spacing.xs)
    }
}

/// سطر هادئ واحد لقسم فارغ (بدل بطاقة فارغة)
struct AdminOccasionsQuietLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .dsGlyph(DS.Glyph.sm)
                .accessibilityHidden(true)
            Text(text)
                .dsFont(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(DS.Color.textTertiary)
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard(padding: nil)
    }
}

// MARK: - «أفراح العائلة · من الأخبار»

/// أخبار الزواج والمواليد والتهاني المنشورة خلال ٣٠ يوماً — الأحدث أولاً، اثنان ثم «عرض الكل (N)»؛ «بطاقة» تفتح المصمّم
/// على قالبها (زواج ← عقد قران، مولود ← قدوم مولود)
struct AdminOccasionsJoysCard: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @State private var showsAll = false

    static let joyTypes: [String] = ["زواج", "مولود", "تهنئة"]
    private static let windowDays = 30
    private static let collapsed = 2

    private var joys: [NewsPost] {
        let since = Date().addingTimeInterval(-Double(Self.windowDays) * 86_400)
        return newsVM.allNews
            .filter { Self.joyTypes.contains($0.type) && $0.timestamp >= since
                && ($0.approval_status == nil || $0.approval_status == "approved") }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        let all = joys
        let visible = showsAll ? all : Array(all.prefix(Self.collapsed))
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminOccasionsSectionTitle(
                title: L10n.t("أفراح العائلة · من الأخبار", "Family joys · from News"),
                actionTitle: all.count > Self.collapsed
                    ? (showsAll ? L10n.t("أقل", "Less") : L10n.t("عرض الكل (\(all.count))", "Show all (\(all.count))"))
                    : nil,
                onAction: { withAnimation(DS.Anim.snappy) { showsAll.toggle() } })
            if all.isEmpty {
                AdminOccasionsQuietLine(icon: "heart",
                                        text: L10n.t("لا أفراح في الأخبار خلال ٣٠ يوماً", "No joyful news in the last 30 days"))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, post in
                        if index > 0 { AdminRowDivider() }
                        row(post)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .adminCard()
            }
        }
    }

    private func row(_ post: NewsPost) -> some View {
        let firstLine = post.content.split(separator: "\n").first.map(String.init) ?? post.content
        return AdminListRow(icon: NewsTypeHelper.icon(for: post.type), tint: NewsTypeHelper.color(for: post.type),
                            title: firstLine.trimmingCharacters(in: .whitespaces),
                            subtitle: "\(post.type) · \(AdminOccasionsText.shortDate(post.timestamp))",
                            showsChevron: false) {
            AdminPillButton(title: L10n.t("إعلان", "Design"), icon: "photo", style: .soft) { card(post) }
        }
        .accessibilityAction(named: L10n.t("تصميم إعلان", "Design an announcement")) { card(post) }
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

// MARK: - «عزاء وذكرى»

/// وفيات لم يُعلن عنها («إعلان» — المالك والمدير)، ثم ذكرى الراحلين خلال ٣٠ يوماً (ثلاث ثم «عرض الكل»)، ثم
/// «N متوفى بلا تاريخ كامل» «أكمل» ← «إدارة تواريخ الوفاة» (`canEditMembers`)
struct AdminOccasionsGriefCard: View {
    let feed: AdminUpcomingFeed
    let loading: Bool

    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @State private var showsAll = false

    private static let collapsed = 3

    var body: some View {
        let memorials = DeceasedMemorialBoard(memberVM.allMembers).upcoming
        let visible = showsAll ? memorials : Array(memorials.prefix(Self.collapsed))
        let incomplete = authVM.canEditMembers ? DeathDatesCampaign.stats(memberVM.allMembers).incomplete : 0
        let isEmpty = feed.deaths.isEmpty && memorials.isEmpty && incomplete == 0
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminOccasionsSectionTitle(
                title: L10n.t("عزاء وذكرى", "Condolences & memorials"),
                actionTitle: memorials.count > Self.collapsed
                    ? (showsAll ? L10n.t("أقل", "Less") : L10n.t("عرض الكل (\(memorials.count))", "Show all (\(memorials.count))"))
                    : nil,
                onAction: { withAnimation(DS.Anim.snappy) { showsAll.toggle() } })
            if loading {
                AdminPageStateCard(.loading(L10n.t("جارٍ التحميل…", "Loading…")))
            } else if isEmpty {
                AdminOccasionsQuietLine(icon: "leaf",
                                        text: L10n.t("لا ذكرى خلال ٣٠ يوماً", "No memorial in the next 30 days"))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(feed.deaths.enumerated()), id: \.element.id) { index, m in
                        if index > 0 { AdminRowDivider() }
                        deathRow(m)
                    }
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, u in
                        if index > 0 || !feed.deaths.isEmpty { AdminRowDivider() }
                        memorialRow(u)
                    }
                    if incomplete > 0 {
                        if !feed.deaths.isEmpty || !visible.isEmpty { AdminRowDivider() }
                        datesRow(incomplete)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .adminCard()
            }
        }
    }

    private func deathRow(_ m: FamilyMember) -> some View {
        AdminListRow(icon: NewsTypeHelper.icon(for: "وفاة"), tint: DS.Color.error,
                     title: L10n.t("وفاة لم يُعلن عنها", "Death not announced"),
                     subtitle: "\(AdminOccasionsText.late(m)) \(m.shortFullName) · \(AdminOccasionsText.deathLine(m))",
                     showsChevron: false) {
            AdminPillButton(title: L10n.t("إعلان", "Announce"), style: .navy) { announce(m) }
        }
        .accessibilityAction(named: L10n.t("إعلان", "Announce")) { announce(m) }
    }

    private func memorialRow(_ u: DeceasedMemorialBoard.Upcoming) -> some View {
        AdminListRow(icon: "leaf.fill", tint: DS.Color.sadu,
                     title: L10n.t("ذكرى \(AdminOccasionsText.late(u.member)) \(u.member.fullName)",
                                   "\(u.member.fullName)'s anniversary"),
                     subtitle: DeceasedMemorial.anniversaryLine(u.anniversary, arabic: L10n.isArabic),
                     showsChevron: false) {
            AdminValueChip(text: DeceasedMemorial.whenLabel(u.anniversary.daysUntil, arabic: L10n.isArabic),
                           tint: u.anniversary.daysUntil <= 1 ? DS.Color.accent : DS.Color.primary)
        }
    }

    /// «128 متوفى بلا تاريخ كامل» — بيت الاستكمال «إدارة تواريخ الوفاة»
    private func datesRow(_ incomplete: Int) -> some View {
        NavigationLink {
            AdminLazyPage {
                AnyView(DeathDatesCampaignPage().adminBackTitle(AdminArea.occasions.title).adminArea(.family))
            }
        } label: {
            AdminListRow(icon: "calendar.badge.exclamationmark", tint: DS.Color.warning,
                         title: L10n.t("\(incomplete) متوفى بلا تاريخ كامل", "\(incomplete) deceased without a full date"),
                         subtitle: L10n.t("لا تظهر ذكراهم حتى يكتمل التاريخ", "Their memorial shows once the date is complete"),
                         showsChevron: false) {
                AdminPillLabel(title: L10n.t("أكمل", "Complete"), style: .soft)
            }
        }
        .buttonStyle(.plain)
    }

    /// مربّع «إعلان وفاة» مباشرة والمتوفى جاهز (كصفحة المتوفى والأندرويد) — شريط «إنشاء» لا يضمّ «إعلان وفاة»
    /// فكان يفتح «إرسال إشعار» بدله
    private func announce(_ m: FamilyMember) {
        DeathAnnouncementPresenter.open(DeathAnnouncementTarget(id: m.id, name: m.fullName, isFemale: m.isFemale,
                                                                deathDate: m.deathDate))
    }
}

// MARK: - «الإعلانات» (المالك والمدير)

/// العنوان ووصول الإشعارات في طرفه (للمالك ← «الأجهزة ووصول الإشعارات») ← بطاقة: «مجدول N» وصفوفه («تعديل» · «إلغاء»)
/// أو سطر هادئ، ثم «المنشور» سطر واحد بعدده يفتح القائمة كاملة
struct AdminOccasionsAnnouncementsCard: View {
    let feed: AdminUpcomingFeed
    let loading: Bool

    @ObservedObject private var devices = AdminDeviceReachStore.shared
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @State private var cancelTarget: NotificationViewModel.ScheduledNotification? = nil
    @State private var cancellingId: UUID? = nil
    @State private var cancelFailed = false

    var body: some View {
        let published = AdminOccasionsPublishedCard.items(news: newsVM.allNews, notifications: notificationVM.notifications)
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            title
            VStack(alignment: .leading, spacing: 0) {
                if !loading {
                    scheduledBlock
                    AdminRowDivider()
                }
                publishedRow(published)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .adminCard()
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

    /// «الإعلانات» ووصول الإشعارات في الطرف (للمالك — بيته «الفريق والأمان»)
    private var title: some View {
        let reach = devices.stats.flatMap { $0.total > 0 ? $0 : nil }
        return HStack {
            Text(L10n.t("الإعلانات", "Announcements"))
                .dsFont(.sectionTitle)
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Spacing.sm)
            if authVM.canViewSystemSettings, let reach {
                NavigationLink {
                    AdminLazyPage { AnyView(AdminPushHealthView().adminBackTitle(AdminArea.occasions.title).adminArea(.team)) }
                } label: {
                    HStack(spacing: DS.Spacing.xsm) {
                        DSRingGauge(progress: reach.reachShare,
                                    tint: reach.reachPercent >= 90 ? DS.Color.success
                                        : (reach.reachPercent >= 70 ? DS.Color.warning : DS.Color.error),
                                    size: DS.Ring.mini)
                        Text(verbatim: L10n.t("تصل \(reach.reach) جهازاً · \(reach.reachPercent)٪",
                                              "Reaches \(reach.reach) devices · \(reach.reachPercent)%"))
                            .dsFont(.chip)
                            .monospacedDigit()
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .dsTapArea(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                }
                .buttonStyle(DSPressStyle())
                .accessibilityHint(L10n.t("الأجهزة ووصول الإشعارات", "Devices & notification reach"))
            }
        }
        .padding(.horizontal, DS.Spacing.xs)
        .padding(.top, DS.Spacing.xs)
    }

    /// «مجدول N» ثم الصفوف — أو سطر هادئ
    @ViewBuilder
    private var scheduledBlock: some View {
        if feed.scheduled.isEmpty {
            AdminListRow(icon: "bell.slash", tint: DS.Color.textTertiary,
                         title: L10n.t("لا توجد إشعارات مجدولة", "No scheduled pushes"),
                         subtitle: L10n.t("«إرسال إشعار» ← متى؟ ← اختر وقت", "Send a push → When? → Pick a time"),
                         showsChevron: false)
        } else {
            HStack {
                Text(L10n.t("مجدول", "Scheduled"))
                    .dsFont(.label)
                    .foregroundColor(DS.Color.textSecondary)
                Spacer(minLength: 0)
                Text(verbatim: "\(feed.scheduled.count)")
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
            }
            .padding(.top, DS.Spacing.xs)
            .accessibilityElement(children: .combine)
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

    /// «المنشور · 14 هذا الشهر · آخره أمس» ← القائمة كاملة
    private func publishedRow(_ items: [AdminOccasionsPublishedCard.Item]) -> some View {
        let cal = Calendar.current
        let thisMonth = items.filter { cal.isDate($0.date, equalTo: Date(), toGranularity: .month) }.count
        let subtitle: String = {
            guard let last = items.first else { return L10n.t("لم يُنشر شيء بعد", "Nothing published yet") }
            return L10n.t("\(thisMonth) هذا الشهر · آخره \(AdminOccasionsText.relativeDay(last.date))",
                          "\(thisMonth) this month · last \(AdminOccasionsText.relativeDay(last.date))")
        }()
        return NavigationLink {
            AdminLazyPage { AnyView(AdminOccasionsPublishedPage().adminBackTitle(AdminArea.occasions.title).adminArea(.occasions)) }
        } label: {
            AdminListRow(icon: "bell.fill", tint: DS.Color.info,
                         title: L10n.t("المنشور", "Published"), subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    /// «تعديل» = المنشئ نفسه بمسودّة الإشعار المجدول (النص، المستلمون، الموعد) — الحفظ يعدّل الصف نفسه
    private func edit(_ n: NotificationViewModel.ScheduledNotification) {
        AdminCreateWindow.open(.announcement, announce: AdminAnnounceDraft(editing: n, members: memberVM.allMembers),
                               authVM: authVM, newsVM: newsVM, notificationVM: notificationVM, memberVM: memberVM)
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
                return L10n.t("غداً · \(day)", "Tomorrow · \(day)")
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
        .padding(.vertical, DS.Spacing.smd)
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
                    // نفس صفّ القرار المدمج (٢٠٢٦-١١-١١): «تعديل» حبّة رمادية، و«إلغاء» الموعد دائرة حمراء
                    DSDecisionRow(items: [
                        DSDecisionItem(id: "edit", title: L10n.t("تعديل", "Edit"), icon: "pencil", action: onEdit),
                        DSDecisionItem(id: "cancel", title: L10n.t("إلغاء الموعد", "Cancel the schedule"), icon: "xmark",
                                       kind: .destructive, tint: DS.Color.reject, action: onCancel)
                    ], size: .compact)
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
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if showsTitle {
                AdminSectionLabel(title: L10n.t("المنشور", "Published"), trailing: all.isEmpty ? nil : "\(all.count)")
            }
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
