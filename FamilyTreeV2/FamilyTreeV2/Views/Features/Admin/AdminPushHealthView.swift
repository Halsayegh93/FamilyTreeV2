import SwiftUI
import Supabase
import Combine

// MARK: - «الاستخدام والأجهزة» — «حذف المكرر» (طلب المالك ٢٠٢٦-١١-٠٧ «يبيله القسم اعادة تطوير و حذف المكرر»)
//
// القاعدة: كل رقم مرة واحدة في بيته، والباقي روابط. الترتيب: الرأس (سطر حكم واحد بلا أرقام: «كل شي سليم» أو «أجهزة
// تسجيلها فاشل») ← «من العائلة إلى التطبيق» (السلّم = المصدر الوحيد لأعداد الأعضاء: لهم رقم ← سجّلوا ← جهازهم مسجّل ←
// استخدموا خلال 3 أسابيع ← الحين (تطبيق · موقع)؛ كل درجة تفتح أسماءها، والفرقان «ما دخلوا أبداً» و«دخلوا بدون جهاز»
// سطران بين الدرجات ← قائمتهم في «العائلة») ← «النشاط» (الحين ثم آخر 24 ساعة، بلا عدد) ← «الأجهزة» (حلقة الوصول +
// المنصّات + التسجيلات الفاشلة وقائمتها وحذفها داخلها) ← «الأجهزة حسب العضو» مطويّة ← «الإعدادات والأدوات» (عدد الأجهزة
// لكل عضو · أعضاء بأكثر من جهاز · إشعار تجريبي · «المزيد عن الاستخدام»). حُذف: حلقات الرأس الثلاث، بطاقة «يحتاج تصرّف»،
// «لـ N عضو» في عنوان الأجهزة (عدّ آخر للأعضاء بجهاز)، حلقات «النشطون» في صفحة المزيد. نفس النداءات والحذف والصلاحيات
// (الصفحة للمالك — `team.devices`؛ المدير يفتح «الاستخدام» `AdminActiveMembersView` من «الفريق والأمان»).
//
// العيّنة «أ» (٢٠٢٦-١١-٠٧) كانت: «الأجهزة ووصول الإشعارات» + «الاستخدام» صفحة واحدة. ما يلي تاريخ النسخة الأقدم:
//
// «الأجهزة ووصول الإشعارات» — صفحة واحدة (الدفعة ج من «نفّذ كل المقترح»، ٢٠٢٦-١٠-٢٠)
//
// كانت ثلاث قوائم أجهزة في ثلاثة أماكن: صفحة «الأجهزة» (أجهزة كل عضو + بحث + فصل)، و«الأجهزة المسجلة» و«بدون تسجيل
// إشعارات» داخل «وصول الإشعارات»، وفئة «دخل بلا جهاز». صارت صفحة واحدة في «الفريق والأمان» (اسم النوع بقي
// `AdminPushHealthView` لأن «اليوم» و«المناسبات والإعلانات» يفتحانها به):
// الرأس (الأجهزة المرتبطة · تصلها الإشعارات · لم تُحدَّث منذ 30 يوماً) ← «تسجيل الأجهزة للإشعارات» (النسبة وتوزيعها)
// ← «الأجهزة المرتبطة» (آيفون/أندرويد، النسخة الرسمية/نسخة الاختبار، آخر تسجيل، آخر إشعار) ← «عدد الأجهزة المسموح لكل
// عضو» (انتقل من شروط التسجيل؛ المالك يعدّل) ← «الأدوات» (إرسال إشعار تجريبي · حذف التسجيلات غير الصالحة) ← رقم
// «أعضاء مسجّلون لا تصلهم الإشعارات ↗» (شريحة العائلة) ← «الأجهزة حسب العضو» مطويّة بلا بحث — الضغط على عضو يفتح
// ورقته، وفيها أجهزته وتسجيل خروجها (بيت الأمر الوحيد، `canManageDevices`). نفس النداءات والحذف والصلاحيات.
//
// الدفعة ١٤ (طلب المالك «تم غير»): «لا تصلها الإشعارات» = التسجيلات الفاشلة فقط — تنبيه «بلا إشعارات» في «حالة النظام» يعدّها
// وحدها. ما يرفضه Apple/Google عند الإرسال (APNs 410، FCM UNREGISTERED) يحذفه `push-on-notification` فوراً، ولا يُحفظ
// سجلّ لرفض الإرسال على السيرفر — فالفاشل الباقي الذي نعرفه يقيناً هو التسجيل الفارغ أو الناقص (لا يُرسل له شيء أصلاً).
// «لم يُفتح التطبيق منذ 30 يوماً» معلومة في هذه الصفحة فقط، لا تنبيه: رمزها صالح والإشعارات تصلها.

/// جهاز مسجّل للإشعارات (`device_tokens`) — صفّ واحد لكل جهاز
struct AdminDeviceRow: Decodable, Identifiable, Equatable {
    let id: Int
    let memberId: UUID
    let token: String?
    let platform: String?
    let environment: String?
    let deviceName: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, token, platform, environment
        case memberId = "member_id"
        case deviceName = "device_name"
        case updatedAt = "updated_at"
    }

    var updatedDate: Date? { AdminDeviceReachStore.date(updatedAt) }
    /// رمز تسجيل صالح (أطول من ٢٠ حرفاً — نفس شرط `push-on-notification`؛ الأقصر لا يُرسل له شيء = تسجيل فاشل)
    var isValid: Bool { (token ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count > 20 }
    /// لم يُفتح التطبيق عليه منذ ٣٠ يوماً (أو بلا تاريخ) — معلومة فقط، الإشعارات تصله ما دام رمزه صالحاً
    var isStale: Bool {
        guard let d = updatedDate else { return true }
        return d < Date().addingTimeInterval(-30 * 86400)
    }
    var isAndroid: Bool { (platform ?? "").lowercased() == "android" }
    var isTestBuild: Bool { environment == "sandbox" }
    var displayName: String {
        if let deviceName, !deviceName.isEmpty { return deviceName }
        return isAndroid ? L10n.t("أندرويد", "Android") : L10n.t("آيفون", "iPhone")
    }
}

/// أرقام الصفحة المحسوبة من الأجهزة المحمّلة
struct AdminDeviceReachStats {
    let total: Int
    /// تسجيل صالح — تصله الإشعارات (ما رفضه Apple/Google يُحذف عند الإرسال فلا يبقى هنا)
    let reach: Int
    /// صالح لكن لم يُفتح التطبيق عليه منذ ٣٠ يوماً — معلومة فقط (ضمن `reach`)
    let stale: Int
    /// تسجيل فاشل: رمز فارغ أو ناقص — لا يصله شيء. هذا وحده رقم «بلا إشعارات» في «حالة النظام»
    let invalid: Int
    let iphone: Int
    let android: Int
    /// آيباد (اسم الجهاز) — ضمن أجهزة Apple
    let ipad: Int
    /// كم عضو داخل من كل جهاز (طلب المالك ٢٠٢٦-١١-٠٧ «كم واحد داخل من الايفون و كم من الاندرويد»)
    let iphoneMembers: Int
    let androidMembers: Int
    let ipadMembers: Int
    let official: Int
    let testBuild: Int
    let membersWithDevices: Int
    let multiDeviceMembers: Int
    let lastRegistered: Date?

    var reachShare: Double { total > 0 ? Double(reach) / Double(total) : 0 }
    var reachPercent: Int { Int((reachShare * 100).rounded(.down)) }

    init(_ rows: [AdminDeviceRow]) {
        total = rows.count
        invalid = rows.filter { !$0.isValid }.count
        stale = rows.filter { $0.isValid && $0.isStale }.count
        reach = total - invalid
        let isPad: (AdminDeviceRow) -> Bool = { r in
            !r.isAndroid && ((r.platform ?? "").lowercased() == "ipados" || (r.deviceName ?? "").lowercased().contains("ipad"))
        }
        android = rows.filter(\.isAndroid).count
        ipad = rows.filter(isPad).count
        iphone = total - android - ipad
        androidMembers = Set(rows.filter(\.isAndroid).map(\.memberId)).count
        ipadMembers = Set(rows.filter(isPad).map(\.memberId)).count
        iphoneMembers = Set(rows.filter { !$0.isAndroid && !isPad($0) }.map(\.memberId)).count
        testBuild = rows.filter(\.isTestBuild).count
        official = total - testBuild
        let perMember = Dictionary(grouping: rows, by: \.memberId)
        membersWithDevices = perMember.count
        multiDeviceMembers = perMember.values.filter { $0.count > 1 }.count
        lastRegistered = rows.compactMap(\.updatedDate).max()
    }
}

/// الأجهزة المسجّلة للإشعارات — مخزن واحد تقرؤه صفحة الأجهزة ورأس «الفريق والأمان» (المالك والمدير)
@MainActor
final class AdminDeviceReachStore: ObservableObject {
    static let shared = AdminDeviceReachStore()

    /// nil = لم يُحمَّل بعد
    @Published private(set) var rows: [AdminDeviceRow]?
    @Published private(set) var lastNotification: Date?
    @Published private(set) var failed = false
    @Published private(set) var isLoading = false
    @Published private(set) var loadedAt: Date?

    var stats: AdminDeviceReachStats? { rows.map(AdminDeviceReachStats.init) }
    /// التسجيلات الفاشلة (لا تصلها الإشعارات) — قائمتها في الصفحة مع «حذف التسجيلات غير الصالحة»
    var failingRows: [AdminDeviceRow] { (rows ?? []).filter { !$0.isValid } }

    /// جلب الأجهزة وآخر إشعار — مرة كل دقيقة على الأكثر ما لم يُطلب
    func refresh(force: Bool = false) async {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 60 { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            #if DEBUG
            try DebugAdminProbe.failIfAsked(.devices, hasLoaded: rows != nil)   // `-tmpFailStores devices`
            #endif
            let fetched: [AdminDeviceRow] = try await SupabaseConfig.client
                .from("device_tokens")
                .select("id, member_id, token, platform, environment, device_name, updated_at")
                .order("updated_at", ascending: false)
                .execute()
                .value
            struct NotificationRow: Decodable { let created_at: String? }
            let last: [NotificationRow] = (try? await SupabaseConfig.client
                .from("notifications")
                .select("created_at")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value) ?? []
            rows = fetched
            lastNotification = Self.date(last.first?.created_at)
            failed = false
            loadedAt = Date()
        } catch {
            guard !ErrorHelper.isCancellation(error) else { return }
            #if DEBUG
            // الفشل المصطنع لا يمرّ بـ`Log.error` (يبلّغ السيرفر)
            if DebugAdminProbe.isInjected(error) { failed = true; return }
            #endif
            Log.error("[Devices] فشل جلب الأجهزة: \(error.localizedDescription)")
            failed = true
        }
    }

    /// للتصوير/المعاينة فقط
    func apply(_ rows: [AdminDeviceRow], lastNotification: Date?) {
        self.rows = rows
        self.lastNotification = lastNotification
        failed = false
        loadedAt = Date()
    }

    nonisolated static func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }
}


struct AdminPushHealthView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var store = AdminDeviceReachStore.shared

    @State private var usage: AppUsageStats? = AppUsageStats.cached
    @State private var nowRows: [ActiveMemberRow] = []
    @State private var actionRows: [RecentActionRow] = []
    @State private var liveLoaded = false
    @State private var isRefreshing = false
    @State private var refreshTimer: Timer?
    @State private var isSendingTest = false
    @State private var isCleaningUp = false
    @State private var testResult: (text: String, success: Bool)?
    @State private var cleanupResult: (text: String, success: Bool)?
    @State private var failingOpen = false
    @State private var listOpen = false
    @State private var sheet: AdminMemberSheetContext?

    var body: some View {
        AdminPage(header: header, content: AnyView(cards))
            .refreshable { await reload(force: true) }
            .dsTallBox(item: $sheet) { context in
                AdminMemberSheet(ids: context.ids, start: context.start)
            }
            .task {
                // المدير الحالي يبقى ضمن النشطين (كما في «الاستخدام»)
                MemberActivityTracker.report("admin", force: true)
                await reload(force: false)
                startTimer()
            }
            .onDisappear { refreshTimer?.invalidate() }
    }

    // MARK: - التحميل (نفس النداءات: الأجهزة، الإعدادات، أرقام الاستخدام، الآن وآخر 24 ساعة — كل 15 ثانية للحيّ)

    private func reload(force: Bool) async {
        async let devices: Void = store.refresh(force: force)
        async let settings: Void = appSettingsVM.fetchSettings()
        async let live: Void = refreshLive()
        if let u = await AppUsageStats.fetch() { usage = u }
        _ = await (devices, settings, live)
    }

    private func refreshLive() async {
        let now = await AdminLiveUsage.fetchNow()
        let day = await AdminLiveUsage.fetchActions24h(excluding: now)
        nowRows = now
        actionRows = day
        liveLoaded = true
    }

    private func startTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { await refreshLive() }
        }
    }

    private func refreshNow() {
        guard !isRefreshing else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            isRefreshing = true
            MemberActivityTracker.report("admin", force: true)
            await reload(force: true)
            isRefreshing = false
        }
    }

    // MARK: - الرأس: سطر حكم واحد (بلا أرقام — كل رقم له بيت تحت)

    private var header: AdminPageHeader {
        AdminPageHeader(
            title: L10n.t("الاستخدام والأجهزة", "Usage and devices"),
            subtitle: L10n.t("من يستخدم التطبيق، وهل تصله الإشعارات", "Who uses the app, and do notifications reach them"),
            glyph: "iphone.gen3",
            actions: [AdminPageAction(symbol: isRefreshing ? "hourglass" : "arrow.clockwise",
                                      label: L10n.t("تحديث الآن", "Refresh now"), tap: .action { refreshNow() })],
            accessory: AnyView(statusLine))
    }

    private var statusLine: some View {
        let s = store.stats
        let ok: Bool? = s.map { $0.invalid == 0 }
        let text: String = {
            guard let ok else {
                return store.failed ? L10n.t("تعذّر فحص الأجهزة", "Couldn't check devices") : L10n.t("جارٍ الفحص…", "Checking…")
            }
            return ok ? L10n.t("كل شيء سليم، والإشعارات تصل إلى جميع الأجهزة", "All good — notifications reach every device")
                      : L10n.t("في أجهزة تسجيلها فاشل — تحت في «الأجهزة»", "Some devices failed to register — see Devices below")
        }()
        return AdminUsageStatusLine(ok: ok, text: text)
    }

    // MARK: - البطاقات (كل واحدة نوعها خلف `AnyView`)

    private var cards: some View {
        VStack(spacing: DS.Hub.stackSpacing) {
            AnyView(AdminUsageFunnelCard(usage: usage, now: nowRows, nowLoaded: liveLoaded))
            AnyView(AdminLiveActivityCard(now: nowRows, day: actionRows, loaded: liveLoaded))
            AnyView(devicesSection)
            if store.stats != nil { AnyView(perMemberCard) }
            AnyView(settingsSection)
        }
    }

    // MARK: الأجهزة — حلقة الوصول + المنصّات + التسجيلات الفاشلة (قائمتها وحذفها هنا وحدها)

    @ViewBuilder private var devicesSection: some View {
        let s = store.stats
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: L10n.t("الأجهزة", "Devices"),
                              trailing: s.map { L10n.t("\($0.total) جهاز", "\($0.total) devices") })
            if let s {
                let failing = store.failingRows
                AnyView(AdminDevicesRingCard(
                    stats: s, lastNotification: store.lastNotification,
                    failingOpen: $failingOpen, isDeleting: isCleaningUp,
                    onDelete: { Task { await runCleanup() } },
                    failingList: AnyView(VStack(spacing: 0) {
                        ForEach(failing) { row in AnyView(failingDeviceRow(row)) }
                    }),
                    result: cleanupResult))
            } else if store.failed {
                AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأجهزة", "Couldn't load devices"),
                                          message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                          retry: { Task { await store.refresh(force: true) } }))
            } else {
                AdminPageStateCard(.loading(L10n.t("جارٍ فحص الأجهزة…", "Checking devices…")))
            }
        }
    }

    private func failingDeviceRow(_ row: AdminDeviceRow) -> some View {
        let member = memberVM.member(byId: row.memberId)
        let ids = groups.compactMap { $0.member?.id }
        let name = member?.displayFullName ?? L10n.t("عضو غير معروف", "Unknown member")
        let face = HStack(spacing: DS.Spacing.sm) {
            DSMemberAvatar(name: name, avatarUrl: member?.avatarUrl, size: DS.Icon.row, roleColor: AppSection.admin.ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(name).dsFont(.hubRow).foregroundColor(DS.Color.textPrimary).dsNameLines()
                Text(verbatim: "\(row.displayName) · \(AdminLiveUsage.relative(row.updatedDate))")
                    .dsFont(.footnote).foregroundColor(DS.Color.textTertiary).lineLimit(1)
            }
            Spacer(minLength: DS.Spacing.xs)
            if member != nil { DSChevron() }
        }
        .padding(.vertical, DS.Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        return Group {
            if let member, let start = ids.firstIndex(of: member.id) {
                Button { sheet = AdminMemberSheetContext(ids: ids, start: start) } label: { face }.buttonStyle(.plain)
            } else {
                face
            }
        }
    }

    // MARK: الإعدادات والأدوات (آخر الصفحة)

    private var settingsSection: some View {
        let s = store.stats
        let canEdit = authVM.canManageSettings
        let max = appSettingsVM.settings.maxDevicesPerUser
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: L10n.t("الإعدادات والأدوات", "Settings and tools"))
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                AdminRowsCardBody {
                    AdminControlRow(icon: "iphone.gen3.badge.play", tint: DS.Color.info,
                                    title: L10n.t("الأجهزة المسموحة لكل عضو", "Devices allowed per member"),
                                    subtitle: canEdit ? L10n.t("يُطلب من صاحب الجهاز الزائد تسجيل الخروج من جهاز آخر",
                                                               "An extra device is asked to sign another one out")
                                                      : AdminPageHeader.readOnlyText,
                                    control: AnyView(limitControl(max, canEdit: canEdit)))
                    if let s, s.multiDeviceMembers > 0 {
                        AdminInfoRow(icon: "ipad.and.iphone", tint: DS.Color.primary,
                                     title: L10n.t("أعضاء بأكثر من جهاز", "Members with more than one device"),
                                     trailing: AnyView(AdminRowValue(text: "\(s.multiDeviceMembers)")))
                    }
                    AdminTapRow(icon: "paperplane.fill", tint: DS.Color.sea,
                                title: L10n.t("إرسال إشعار تجريبي", "Send a test notification"),
                                subtitle: L10n.t("يُرسل إلى جهازك فقط", "Reaches your own device only"),
                                value: isSendingTest ? L10n.t("جارٍ…", "Sending…") : nil,
                                tap: .action { Task { await sendTestPush() } })
                    AdminTapRow(icon: "chart.xyaxis.line", tint: DS.Color.accent,
                                title: L10n.t("المزيد عن الاستخدام", "More about usage"),
                                subtitle: L10n.t("الاتجاه، الجلسات، أكثر الشاشات والأعضاء", "Trend, sessions, top screens and members"),
                                tap: .page { AnyView(AdminUsageDetailsPage()) })
                }
                if let testResult {
                    DSNoteCard(testResult.text, icon: testResult.success ? "checkmark.circle.fill" : "xmark.octagon.fill",
                               tint: testResult.success ? DS.Color.success : DS.Color.error)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .adminCard()
        }
    }

    @ViewBuilder
    private func limitControl(_ value: Int, canEdit: Bool) -> some View {
        if canEdit {
            HStack(spacing: DS.Spacing.sm) {
                Text("\(value)")
                    .dsFont(.statValue)
                    .monospacedDigit()
                    .foregroundColor(AppSection.admin.ink)
                    .frame(minWidth: DS.Icon.section)
                    .accessibilityHidden(true)
                Stepper("\(value)", value: Binding(
                    get: { appSettingsVM.settings.maxDevicesPerUser },
                    set: { newValue in
                        appSettingsVM.settings.maxDevicesPerUser = newValue
                        #if DEBUG
                        if DebugAdminProbe.dryRun("app_settings max_devices_per_user=\(newValue)") { return }
                        #endif
                        Task { await appSettingsVM.updateSetting("max_devices_per_user", value: newValue,
                                                                 updatedBy: authVM.currentUser?.id) }
                    }), in: 1...10)
                .labelsHidden()
                .accessibilityLabel(L10n.t("عدد الأجهزة المسموح لكل عضو", "Devices allowed per member"))
                .accessibilityValue("\(value)")
            }
            .fixedSize()
        } else {
            AdminRowValue(text: "\(value)")
        }
    }

    // MARK: - الأجهزة حسب العضو (مطويّة، بلا بحث) — الضغط يفتح ورقة العضو (أجهزته وتسجيل خروجها)

    private struct MemberDevices: Identifiable {
        let id: UUID
        let member: FamilyMember?
        let devices: [AdminDeviceRow]
    }

    private var groups: [MemberDevices] {
        let rows = store.rows ?? []
        let grouped = Dictionary(grouping: rows, by: \.memberId)
        return grouped.map { id, devices in
            MemberDevices(id: id, member: memberVM.member(byId: id),
                          devices: devices.sorted { ($0.updatedDate ?? .distantPast) > ($1.updatedDate ?? .distantPast) })
        }
        .sorted { ($0.devices.first?.updatedDate ?? .distantPast) > ($1.devices.first?.updatedDate ?? .distantPast) }
    }

    private var perMemberCard: some View {
        let list = groups
        let ids = list.compactMap { $0.member?.id }
        return AdminSectionCard(title: L10n.t("الأجهزة حسب العضو", "Devices by member"),
                                badge: list.count, badgeTint: DS.Color.primary, spacing: 0,
                                isOpen: $listOpen,
                                summary: L10n.t("اضغط عضواً لفتح ورقته — أجهزته وتسجيل خروجها في «الحساب»",
                                                "Tap a member to open their sheet — devices and sign-out are under Account")) {
            AdminLazyRows(items: list) { group in
                AnyView(memberRow(group, ids: ids))
            }
        }
    }

    private func memberRow(_ group: MemberDevices, ids: [UUID]) -> some View {
        let name = group.member?.displayFullName ?? L10n.t("عضو غير معروف", "Unknown member")
        let names = group.devices.map(\.displayName).joined(separator: "، ")
        let latest = AdminLiveUsage.relative(group.devices.first?.updatedDate)
        let face = HStack(spacing: DS.Spacing.sm) {
            DSMemberAvatar(name: name, avatarUrl: group.member?.avatarUrl, size: DS.Icon.row, roleColor: AppSection.admin.ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(name).dsFont(.hubRow).foregroundColor(DS.Color.textPrimary).dsNameLines()
                Text(verbatim: "\(names) · \(latest)")
                    .dsFont(.footnote).foregroundColor(DS.Color.textTertiary).lineLimit(1)
            }
            Spacer(minLength: DS.Spacing.xs)
            if group.devices.contains(where: \.isTestBuild) {
                DSStatusChip(text: L10n.t("اختبار", "Test"), icon: "hammer.fill", tint: DS.Color.warning, size: .mini)
            }
            if group.devices.contains(where: { !$0.isValid }) {
                DSStatusChip(text: L10n.t("تسجيل فاشل", "Failed"), tint: DS.Color.error, size: .mini)
            }
            AdminValueChip(text: "\(group.devices.count)", icon: "iphone", tint: group.devices.count > 1 ? DS.Color.warning : DS.Color.primary)
            if group.member != nil { DSChevron() }
        }
        .padding(.vertical, DS.Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)

        return Group {
            if let member = group.member, let start = ids.firstIndex(of: member.id) {
                Button { sheet = AdminMemberSheetContext(ids: ids, start: start) } label: { face }
                    .buttonStyle(.plain)
            } else {
                face
            }
        }
    }

    // MARK: - الإشعار التجريبي (نفس الإدراج السابق — المشغّل على `notifications` يوصّله: APNs + FCM)

    private func sendTestPush() async {
        guard !isSendingTest else { return }
        guard let memberId = authVM.currentUser?.id else {
            testResult = (L10n.t("لا يوجد مستخدم حالي", "No current user"), false)
            return
        }
        isSendingTest = true
        testResult = nil
        defer { isSendingTest = false }
        #if DEBUG
        if DebugAdminProbe.dryRun("notifications.insert kind=test (test push)") {
            withAnimation { testResult = (L10n.t("تم الإرسال — تحقّق من جهازك خلال ثوانٍ", "Sent — check your device in a few seconds"), true) }
            return
        }
        #endif
        do {
            let payload: [String: AnyEncodable] = [
                "target_member_id": AnyEncodable(memberId.uuidString),
                "title": AnyEncodable(L10n.t("إشعار تجريبي ✓", "Test notification ✓")),
                "body": AnyEncodable(L10n.t("عند وصول هذا الإشعار، فالمنظومة تعمل بشكل كامل.",
                                            "If you received this, the system is fully working.")),
                "kind": AnyEncodable("test"),
                "created_by": AnyEncodable(memberId.uuidString)
            ]
            try await SupabaseConfig.client.from("notifications").insert(payload).execute()
            withAnimation { testResult = (L10n.t("تم الإرسال — تحقّق من جهازك خلال ثوانٍ", "Sent — check your device in a few seconds"), true) }
        } catch {
            Log.error("[Devices] فشل إرسال الإشعار التجريبي: \(error.localizedDescription)")
            withAnimation { testResult = (L10n.t("تعذّر الإرسال: \(error.localizedDescription)", "Couldn't send: \(error.localizedDescription)"), false) }
        }
        await store.refresh(force: true)
    }

    // MARK: - حذف التسجيلات غير الصالحة (فارغة أو ناقصة — نفس شرط `isValid`؛ بصلاحية المالك على device_tokens، كما كان)

    private func runCleanup() async {
        guard !isCleaningUp else { return }
        isCleaningUp = true
        cleanupResult = nil
        defer { isCleaningUp = false }
        struct Row: Decodable { let id: Int; let token: String? }
        do {
            let rows: [Row] = try await SupabaseConfig.client.from("device_tokens").select("id, token").execute().value
            let invalidIds = rows
                .filter { ($0.token ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count <= 20 }
                .map(\.id)
            #if DEBUG
            let dryRun = !invalidIds.isEmpty && DebugAdminProbe.dryRun("device_tokens.delete \(invalidIds.count) invalid registrations")
            #else
            let dryRun = false
            #endif
            if !invalidIds.isEmpty, !dryRun {
                try await SupabaseConfig.client.from("device_tokens").delete().in("id", values: invalidIds).execute()
            }
            withAnimation {
                cleanupResult = invalidIds.isEmpty
                    ? (L10n.t("لا توجد تسجيلات غير صالحة ✓ (\(rows.count) جهاز سليم)", "No invalid registrations ✓ (\(rows.count) devices OK)"), true)
                    : (L10n.t("حُذف \(invalidIds.count) تسجيل غير صالح ✓ — قبل: \(rows.count) · بعد: \(rows.count - invalidIds.count)",
                              "Deleted \(invalidIds.count) invalid registrations ✓ — before: \(rows.count) · after: \(rows.count - invalidIds.count)"), true)
            }
            Log.info("[Devices] cleanup: removed \(invalidIds.count) broken tokens of \(rows.count)")
            await store.refresh(force: true)
        } catch {
            Log.error("[Devices] cleanup failed: \(error.localizedDescription)")
            withAnimation { cleanupResult = (L10n.t("فشل الحذف: \(error.localizedDescription)", "Delete failed: \(error.localizedDescription)"), false) }
        }
    }
}

/// بطاقة «الأجهزة»: حلقة واحدة بأجزائها الثلاثة والنسبة في وسطها والمفتاح بجانبها — «ما توصلها (تسجيل فاشل)» يفتح
/// أجهزتها وزرّ حذفها هنا (بيت التسجيلات الفاشلة الوحيد) — ثم المنصّات وسطر النسخ وآخر إشعار
struct AdminDevicesRingCard: View {
    let stats: AdminDeviceReachStats
    let lastNotification: Date?
    @Binding var failingOpen: Bool
    let isDeleting: Bool
    let onDelete: () -> Void
    let failingList: AnyView
    let result: (text: String, success: Bool)?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let s = stats
        let fresh = max(0, s.reach - s.stale)
        let staleTint = DS.Color.success.opacity(0.45)
        let parts = DSGaugePart.counts([("fresh", fresh, DS.Color.success), ("stale", s.stale, staleTint),
                                        ("invalid", s.invalid, DS.Color.error)])
        let ring = DSRingGauge(parts: parts, size: DS.Ring.medium, track: DS.Ring.emptyTrack,
                               center: .percent(s.total > 0 ? s.reachPercent : nil), caption: L10n.t("توصلها", "Reached"),
                               spoken: L10n.t("تصل الإشعارات إلى \(s.reachPercent)٪ من الأجهزة", "Notifications reach \(s.reachPercent)% of devices"))
        let legend = VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            legendRow(DS.Color.success, L10n.t("توصلها الإشعارات", "Notifications reach them"), fresh)
            legendRow(staleTint, L10n.t("تصلها، لكن لم تُفتح منذ 30 يوماً", "Reached, but not opened in 30 days"), s.stale)
            if s.invalid > 0 {
                Button {
                    withAnimation(DSMotion.expand) { failingOpen.toggle() }
                } label: {
                    legendRow(DS.Color.error, L10n.t("لا تصلها (تسجيل فاشل)", "Not reached (failed registration)"), s.invalid,
                              chevron: failingOpen ? "chevron.up" : "chevron.down")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(failingOpen ? L10n.t("يخفي الأجهزة", "Hides the devices") : L10n.t("يعرض الأجهزة وزرّ الحذف", "Shows the devices and the delete button"))
            } else {
                legendRow(DS.Color.error, L10n.t("لا تصلها (تسجيل فاشل)", "Not reached (failed registration)"), 0)
            }
        }
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if typeSize.isAccessibilitySize {
                AnyView(VStack(alignment: .leading, spacing: DS.Spacing.sm) { ring; legend })
            } else {
                AnyView(HStack(spacing: DS.Spacing.md) { ring; legend })
            }
            if failingOpen && s.invalid > 0 {
                AnyView(failingBlock(count: s.invalid))
            }
            if let result {
                DSNoteCard(result.text, icon: result.success ? "checkmark.circle.fill" : "xmark.octagon.fill",
                           tint: result.success ? DS.Color.success : DS.Color.error)
                    .transition(.opacity)
            }
            HStack(spacing: DS.Spacing.sm) {
                platform("iphone", L10n.t("آيفون", "iPhone"), s.iphoneMembers, s.iphone)
                platform("candybarphone", L10n.t("أندرويد", "Android"), s.androidMembers, s.android)
                if s.ipad > 0 { platform("ipad", L10n.t("آيباد", "iPad"), s.ipadMembers, s.ipad) }
            }
            Text(verbatim: L10n.t("النسخة الرسمية \(s.official) · نسخة الاختبار \(s.testBuild) · آخر تسجيل \(AdminLiveUsage.relative(s.lastRegistered)) · آخر إشعار \(AdminLiveUsage.relative(lastNotification))",
                                  "Official \(s.official) · Test \(s.testBuild) · last registered \(AdminLiveUsage.relative(s.lastRegistered)) · last notification \(AdminLiveUsage.relative(lastNotification))"))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    /// الأجهزة الفاشلة (الضغط يفتح ورقة صاحبها) + الحذف — نفس الحذف السابق
    private func failingBlock(count: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(L10n.t("لا يصلها شيء، وتعود عند فتح صاحبها التطبيق", "Nothing reaches them — they recover when the owner opens the app"))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            failingList
            DSButton(L10n.t("حذف التسجيلات الفاشلة (\(count))", "Delete failed registrations (\(count))"),
                     icon: "trash.fill", role: .destructive, isLoading: isDeleting) { onDelete() }
                .disabled(isDeleting)
        }
        .padding(DS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.cardBackgroundSoft))
    }

    private func legendRow(_ tint: Color, _ title: String, _ value: Int, chevron: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xsm) {
            Circle().fill(tint).frame(width: DS.Hub.statusDot, height: DS.Hub.statusDot)
                .accessibilityHidden(true)
            Text(title)
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Spacing.xs)
            Text(verbatim: "\(value)")
                .dsFont(.hubRow)
                .monospacedDigit()
                .foregroundColor(DS.Color.textPrimary)
            if let chevron {
                Image(systemName: chevron)
                    .dsGlyph(DS.Glyph.xs, weight: .semibold)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: chevron == nil ? nil : DS.Icon.tapTarget)
        .accessibilityElement(children: .combine)
    }

    /// المنصّة: عدد الأعضاء الداخلين منها كبيراً، وعدد الأجهزة تحته
    private func platform(_ icon: String, _ title: String, _ members: Int, _ devices: Int) -> some View {
        VStack(spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon).dsGlyph(DS.Glyph.sm).foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
            }
            Text(verbatim: L10n.t("\(members) عضو", "\(members) members"))
                .dsFont(.rowTitle)
                .monospacedDigit()
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(verbatim: L10n.t("\(devices) جهاز", "\(devices) devices"))
                .dsFont(.micro)
                .monospacedDigit()
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: DS.Icon.section)
        .padding(.vertical, DS.Spacing.xs)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.cardBackgroundSoft))
        .accessibilityElement(children: .combine)
    }
}
