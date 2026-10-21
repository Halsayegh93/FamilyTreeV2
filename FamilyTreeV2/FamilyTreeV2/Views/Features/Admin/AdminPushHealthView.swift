import SwiftUI
import Supabase
import Combine

// MARK: - «الأجهزة ووصول الإشعارات» — صفحة واحدة (الدفعة ج من «نفّذ كل المقترح»، ٢٠٢٦-١٠-٢٠)
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
        android = rows.filter(\.isAndroid).count
        iphone = total - android
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
    @State private var isSendingTest = false
    @State private var isCleaningUp = false
    @State private var toolResult: (text: String, success: Bool)?
    @State private var listOpen = false
    @State private var sheet: AdminMemberSheetContext?

    var body: some View {
        AdminPage(header: header, lead: AnyView(leadCard), content: AnyView(cards))
            .refreshable { await store.refresh(force: true) }
            .dsTallBox(item: $sheet) { context in
                AdminMemberSheet(ids: context.ids, start: context.start)
            }
            .task {
                async let devices: Void = store.refresh()
                async let settings: Void = appSettingsVM.fetchSettings()
                if let u = await AppUsageStats.fetch() { usage = u }
                _ = await (devices, settings)
            }
    }

    // MARK: - الرأس

    private var header: AdminPageHeader {
        let s = store.stats
        return AdminPageHeader(
            title: L10n.t("الأجهزة ووصول الإشعارات", "Devices and notification reach"),
            subtitle: L10n.t("الأجهزة المرتبطة بالحسابات، وهل تصلها الإشعارات", "Devices linked to accounts, and whether notifications reach them"),
            glyph: "iphone.gen3",
            kpis: [
                AdminPageKPI(s.map { "\($0.total)" } ?? "—", L10n.t("الأجهزة المرتبطة", "Linked devices"), icon: "iphone"),
                AdminPageKPI(s.map { "\($0.reach)" } ?? "—", L10n.t("تصلها الإشعارات", "Reached"),
                             icon: "bell.badge.fill", tint: DS.Hub.kpiMine),
                AdminPageKPI(s.map { "\($0.invalid)" } ?? "—", L10n.t("لا تصلها الإشعارات", "Not reached"),
                             icon: "bell.slash.fill",
                             tint: (s?.invalid ?? 0) > 0 ? DS.Hub.kpiLate : DS.Color.textOnPrimary)
            ])
    }

    // MARK: - البطاقات

    private var leadCard: AnyView {
        if let s = store.stats { return AnyView(registrationCard(s)) }
        if store.failed {
            return AnyView(AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأجهزة", "Couldn't load devices"),
                                                     message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى",
                                                                     "Check your connection and try again"),
                                                     retry: { Task { await store.refresh(force: true) } })))
        }
        return AnyView(AdminPageStateCard(.loading(L10n.t("جارٍ فحص الأجهزة…", "Checking devices…"))))
    }

    private var cards: AnyView {
        // الأدوات متاحة حتى قبل اكتمال الفحص
        guard let s = store.stats else {
            return AnyView(VStack(spacing: DS.Hub.stackSpacing) {
                AnyView(toolsCard(nil))
                AnyView(limitCard(nil))
            })
        }
        let failing = store.failingRows
        return AnyView(AdaptiveCardStack(spacing: DS.Hub.stackSpacing, alignment: .leading) {
            if !failing.isEmpty { AnyView(failingCard(failing)) }
            AnyView(devicesCard(s))
            AnyView(limitCard(s))
            AnyView(toolsCard(s))
            AnyView(membersCard)
            AnyView(perMemberCard)
            AnyView(footnote)
        })
    }

    /// «تسجيل الأجهزة للإشعارات»: الحلقة الموحّدة (الدفعة ١٠) — تصلها · لا تصلها (تسجيل فاشل) بألوان المعنى والنسبة في وسطها،
    /// ثم الصفّان بأعدادهما، و«لم يُفتح التطبيق منذ 30 يوماً» معلومة محايدة (الدفعة ١٤ — ليست تنبيهاً)
    private func registrationCard(_ s: AdminDeviceReachStats) -> some View {
        let parts = DSGaugePart.counts([("reach", s.reach, DS.Color.success), ("invalid", s.invalid, DS.Color.error)])
        let line = L10n.t("\(s.reach) من \(s.total) جهازاً — تسجيل صالح تصله الإشعارات",
                          "\(s.reach) of \(s.total) devices — a valid registration that notifications reach")
        return AdminSectionCard(title: L10n.t("تسجيل الأجهزة للإشعارات", "Device registration for notifications")) {
            DSGaugeRow(gauge: DSRingGauge(parts: parts, size: DS.Ring.medium, track: DS.Ring.emptyTrack,
                                          center: .percent(s.total > 0 ? s.reachPercent : nil),
                                          caption: L10n.t("تصلها", "Reached")),
                       title: L10n.t("تصلها الإشعارات", "Notifications reach them"), subtitle: line,
                       spoken: L10n.t("تصل الإشعارات إلى \(s.reachPercent)٪ من الأجهزة، \(line)",
                                      "Notifications reach \(s.reachPercent)% of devices, \(line)"))
            AdminRowsCardBody {
                AdminInfoRow(icon: "bell.badge.fill", tint: DS.Color.success,
                             title: L10n.t("تصلها الإشعارات", "Notifications reach them"),
                             trailing: AnyView(AdminRowValue(text: "\(s.reach)")))
                AdminInfoRow(icon: "bell.slash.fill", tint: DS.Color.error,
                             title: L10n.t("لا تصلها الإشعارات", "Not reached"),
                             subtitle: L10n.t("تسجيل فاشل: رمز فارغ أو ناقص", "Failed registration: empty or truncated token"),
                             trailing: AnyView(AdminRowValue(text: "\(s.invalid)", tint: s.invalid > 0 ? DS.Color.error.dsReadableGlyph : DS.Color.textPrimary)))
                AdminInfoRow(icon: "info.circle.fill", tint: DS.Color.info,
                             title: L10n.t("لم يُفتح التطبيق منذ 30 يوماً", "App not opened in 30 days"),
                             subtitle: L10n.t("للعلم فقط — الإشعارات تصلها ما دام تسجيلها صالحاً",
                                              "For information only — notifications still reach them while the registration is valid"),
                             trailing: AnyView(AdminRowValue(text: "\(s.stale)")))
            }
        }
    }

    /// «أجهزة لا تصلها الإشعارات» (تظهر حين يوجد تسجيل فاشل فقط): جهاز لكل صفّ — العضو يفتح ورقته — ثم «حذف التسجيلات
    /// غير الصالحة» (بيت الحذف حين توجد؛ وإلا يبقى في «الأدوات»)
    private func failingCard(_ rows: [AdminDeviceRow]) -> some View {
        let ids = groups.compactMap { $0.member?.id }
        return AdminSectionCard(title: L10n.t("أجهزة لا تصلها الإشعارات", "Devices not reached"),
                                badge: rows.count, badgeTint: DS.Color.error) {
            AdminRowsCardBody {
                ForEach(rows) { row in
                    AnyView(failingRow(row, ids: ids))
                }
            }
            cleanupButton(count: rows.count)
            Text(L10n.t("تسجيل فارغ أو ناقص لا يُرسل له شيء — يعود صالحاً حين يفتح صاحبه التطبيق. ما ترفضه Apple أو Google عند الإرسال يُحذف تلقائياً.",
                        "An empty or truncated registration gets nothing — it becomes valid again when its owner opens the app. Tokens Apple or Google reject at send time are removed automatically."))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func failingRow(_ row: AdminDeviceRow, ids: [UUID]) -> some View {
        let member = memberVM.member(byId: row.memberId)
        let name = member?.displayFullName ?? L10n.t("عضو غير معروف", "Unknown member")
        let face = HStack(spacing: DS.Spacing.sm) {
            DSMemberAvatar(name: name, avatarUrl: member?.avatarUrl, size: DS.Icon.row, roleColor: AppSection.admin.ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(name)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .dsNameLines()
                Text(verbatim: "\(row.displayName) · \(relative(row.updatedDate))")
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Spacing.xs)
            DSStatusChip(text: L10n.t("تسجيل فاشل", "Failed"), tint: DS.Color.error, size: .mini)
            if member != nil { DSChevron() }
        }
        .padding(.vertical, DS.Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)

        return Group {
            if let member, let start = ids.firstIndex(of: member.id) {
                Button { sheet = AdminMemberSheetContext(ids: ids, start: start) } label: { face }
                    .buttonStyle(.plain)
            } else {
                face
            }
        }
    }

    /// «حذف التسجيلات غير الصالحة» — زرّ واحد في الصفحة: في بطاقة الفاشلة حين توجد، وإلا في «الأدوات»
    private func cleanupButton(count: Int) -> some View {
        DSActionButton(title: count > 0
                            ? L10n.t("حذف التسجيلات غير الصالحة (\(count))", "Delete invalid registrations (\(count))")
                            : L10n.t("حذف التسجيلات غير الصالحة", "Delete invalid registrations"),
                       icon: "trash.fill", tint: DS.Color.warning, isBusy: isCleaningUp) {
            Task { await runCleanup() }
        }
    }

    /// «الأجهزة المرتبطة»: المنصة والنسخة وآخر نشاط
    private func devicesCard(_ s: AdminDeviceReachStats) -> some View {
        AdminSectionCard(title: L10n.t("الأجهزة المرتبطة", "Linked devices"),
                         tag: L10n.t("\(s.membersWithDevices) عضو", "\(s.membersWithDevices) members"), spacing: 0) {
            AdminRowsCardBody {
                AdminInfoRow(icon: "iphone", tint: DS.Color.primary, title: L10n.t("آيفون", "iPhone"),
                             trailing: AnyView(AdminRowValue(text: "\(s.iphone)")))
                AdminInfoRow(icon: "candybarphone", tint: DS.Color.palm, title: L10n.t("أندرويد", "Android"),
                             trailing: AnyView(AdminRowValue(text: "\(s.android)")))
                AdminInfoRow(icon: "checkmark.shield.fill", tint: DS.Color.success, title: L10n.t("النسخة الرسمية", "Official build"),
                             trailing: AnyView(AdminRowValue(text: "\(s.official)")))
                AdminInfoRow(icon: "hammer.fill", tint: DS.Color.warning, title: L10n.t("نسخة الاختبار", "Test build"),
                             trailing: AnyView(AdminRowValue(text: "\(s.testBuild)")))
                AdminInfoRow(icon: "arrow.up.circle.fill", tint: DS.Color.success, title: L10n.t("آخر تسجيل جهاز", "Last device registered"),
                             trailing: AnyView(AdminValueChip(text: relative(s.lastRegistered), tint: DS.Color.primary)))
                AdminInfoRow(icon: "paperplane.fill", tint: DS.Color.sea, title: L10n.t("آخر إشعار مُرسل", "Last notification sent"),
                             trailing: AnyView(AdminValueChip(text: relative(store.lastNotification), tint: DS.Color.primary)))
            }
        }
    }

    /// «عدد الأجهزة المسموح لكل عضو» (كان في «قواعد التسجيل») — المالك يعدّل، والمدير يقرأ
    private func limitCard(_ s: AdminDeviceReachStats?) -> some View {
        let canEdit = authVM.canManageSettings
        let max = appSettingsVM.settings.maxDevicesPerUser
        return AdminSectionCard(spacing: 0) {
            AdminRowsCardBody {
                AdminControlRow(icon: "iphone.gen3.badge.play", tint: DS.Color.info,
                                title: L10n.t("عدد الأجهزة المسموح لكل عضو", "Devices allowed per member"),
                                subtitle: canEdit ? L10n.t("الجهاز الزائد يُطلب منه تسجيل خروج جهاز آخر",
                                                           "An extra device is asked to sign another one out")
                                                  : AdminPageHeader.readOnlyText,
                                control: AnyView(limitControl(max, canEdit: canEdit)))
                if let s, s.multiDeviceMembers > 0 {
                    AdminInfoRow(icon: "ipad.and.iphone", tint: DS.Color.primary,
                                 title: L10n.t("أعضاء بأكثر من جهاز", "Members with more than one device"),
                                 trailing: AnyView(AdminRowValue(text: "\(s.multiDeviceMembers)")))
                }
            }
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

    /// «الأدوات»: إرسال إشعار تجريبي لجهازك، وحذف التسجيلات غير الصالحة (المالك والمدير — كما كانا)
    private func toolsCard(_ s: AdminDeviceReachStats?) -> some View {
        AdminSectionCard(title: L10n.t("الأدوات", "Tools")) {
            DSActionButton(title: L10n.t("إرسال إشعار تجريبي", "Send a test notification"), icon: "paperplane.fill",
                           isBusy: isSendingTest) {
                Task { await sendTestPush() }
            }
            // حين توجد تسجيلات فاشلة يكون الحذف في بطاقتها (فوق) — زرّ واحد في الصفحة
            let cleansHere = (s?.invalid ?? 0) == 0
            if cleansHere { cleanupButton(count: 0) }
            Text(cleansHere
                 ? L10n.t("الإشعار التجريبي يصل جهازك أنت. الحذف للتسجيلات الفارغة أو الناقصة فقط — أجهزة من لم يفتح التطبيق منذ مدة تبقى حتى تصلهم الإشعارات.",
                          "The test reaches your own device. Deleting removes empty or truncated registrations only — idle members' devices stay so they still get notifications.")
                 : L10n.t("الإشعار التجريبي يصل جهازك أنت.", "The test reaches your own device."))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let toolResult {
                DSNoteCard(toolResult.text, icon: toolResult.success ? "checkmark.circle.fill" : "xmark.octagon.fill",
                           tint: toolResult.success ? DS.Color.success : DS.Color.error)
                    .transition(.opacity)
            }
        }
    }

    /// رقم فقط ↗ شريحة «مسجّلون ← لا تصله الإشعارات» في «العائلة» (بيت القائمة)
    private var membersCard: some View {
        let n = usage?.loginNoDevice
        return AdminSectionCard(spacing: 0) {
            AdminTapRow(icon: "person.crop.circle.badge.exclamationmark", tint: DS.Color.warning,
                        title: L10n.t("أعضاء مسجّلون لا تصلهم الإشعارات", "Registered members not reached"),
                        subtitle: L10n.t("دخلوا التطبيق بلا جهاز مسجّل للإشعارات", "Signed in without a device registered for notifications"),
                        value: n.map { "\($0)" }, valueTint: (n ?? 0) > 0 ? DS.Color.warning : DS.Color.textTertiary,
                        tap: .page { AnyView(AdminMembersPage(chip: .registered, sub: .noPush).adminArea(.family)) })
        }
    }

    // MARK: - الأجهزة حسب العضو (مطويّة، بلا بحث)

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
        let latest = relative(group.devices.first?.updatedDate)
        let face = HStack(spacing: DS.Spacing.sm) {
            DSMemberAvatar(name: name, avatarUrl: group.member?.avatarUrl, size: DS.Icon.row, roleColor: AppSection.admin.ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(name)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .dsNameLines()
                Text(verbatim: "\(names) · \(latest)")
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
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

    private var footnote: some View {
        Text(L10n.t("أجهزة عضو بعينه وتسجيل خروجها: من ورقة العضو ← الحساب.",
                    "A member's devices and signing them out: from the member sheet → Account."))
            .dsFont(.footnote)
            .foregroundColor(DS.Color.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.xs)
    }

    private func relative(_ date: Date?) -> String {
        guard let date else { return L10n.t("لا يوجد", "None") }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - الإشعار التجريبي (نفس الإدراج السابق — المشغّل على `notifications` يوصّله: APNs + FCM)

    private func sendTestPush() async {
        guard !isSendingTest else { return }
        guard let memberId = authVM.currentUser?.id else {
            toolResult = (L10n.t("لا يوجد مستخدم حالي", "No current user"), false)
            return
        }
        isSendingTest = true
        toolResult = nil
        defer { isSendingTest = false }
        do {
            let payload: [String: AnyEncodable] = [
                "target_member_id": AnyEncodable(memberId.uuidString),
                "title": AnyEncodable(L10n.t("إشعار تجريبي ✓", "Test notification ✓")),
                "body": AnyEncodable(L10n.t("إذا وصلك هذا الإشعار، المنظومة تعمل بشكل كامل.",
                                            "If you received this, the system is fully working.")),
                "kind": AnyEncodable("test"),
                "created_by": AnyEncodable(memberId.uuidString)
            ]
            try await SupabaseConfig.client.from("notifications").insert(payload).execute()
            withAnimation { toolResult = (L10n.t("تم الإرسال — تحقّق من جهازك خلال ثوانٍ", "Sent — check your device in a few seconds"), true) }
        } catch {
            Log.error("[Devices] فشل إرسال الإشعار التجريبي: \(error.localizedDescription)")
            withAnimation { toolResult = (L10n.t("تعذّر الإرسال: \(error.localizedDescription)", "Couldn't send: \(error.localizedDescription)"), false) }
        }
        await store.refresh(force: true)
    }

    // MARK: - حذف التسجيلات غير الصالحة (فارغة أو ناقصة — نفس شرط `isValid`؛ بصلاحية المالك/المدير على device_tokens، كما كان)

    private func runCleanup() async {
        guard !isCleaningUp else { return }
        isCleaningUp = true
        toolResult = nil
        defer { isCleaningUp = false }
        struct Row: Decodable { let id: Int; let token: String? }
        do {
            let rows: [Row] = try await SupabaseConfig.client.from("device_tokens").select("id, token").execute().value
            let invalidIds = rows
                .filter { ($0.token ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count <= 20 }
                .map(\.id)
            if !invalidIds.isEmpty {
                try await SupabaseConfig.client.from("device_tokens").delete().in("id", values: invalidIds).execute()
            }
            withAnimation {
                toolResult = invalidIds.isEmpty
                    ? (L10n.t("لا توجد تسجيلات غير صالحة ✓ (\(rows.count) جهاز سليم)", "No invalid registrations ✓ (\(rows.count) devices OK)"), true)
                    : (L10n.t("حُذف \(invalidIds.count) تسجيل غير صالح ✓ — قبل: \(rows.count) · بعد: \(rows.count - invalidIds.count)",
                              "Deleted \(invalidIds.count) invalid registrations ✓ — before: \(rows.count) · after: \(rows.count - invalidIds.count)"), true)
            }
            Log.info("[Devices] cleanup: removed \(invalidIds.count) broken tokens of \(rows.count)")
            await store.refresh(force: true)
        } catch {
            Log.error("[Devices] cleanup failed: \(error.localizedDescription)")
            withAnimation { toolResult = (L10n.t("فشل الحذف: \(error.localizedDescription)", "Delete failed: \(error.localizedDescription)"), false) }
        }
    }
}
