import SwiftUI
import Supabase
import Combine

// MARK: - «فرض التحديث» من جديد (مقترح samples/force-update بموافقة المالك ٢٠٢٦-١١-٠٧)
//
// السيرفر يقرّر الحالة بوقته هو: `app_update_policy(p_platform, p_build)` ← none · optional · scheduled · forced
// (+ «ما الجديد» ونصوص شاشة الإجبار و«لاحقاً» بعد كم يوم). القيم في `app_config` (update_mode_ios،
// update_deadline_ios، ios_latest_build…) و`app_settings.ios_min_build`، ويغيّرها المالك من «فرض التحديث».
// • اختياري: مربّع «فيه تحديث جديد» مرة لكل نسخة، وأي إغلاق («لاحقاً» أو السحب) يرجّعه بعد update_snooze_days يوم.
// • إجباري من تاريخ: نفس المربّع بعدّ تنازلي؛ آخر ٢٤ ساعة بلا «لاحقاً» ويرجع مع كل فتح للتطبيق.
// • إجباري: `ForceUpdateView` بنصوص الإدارة. المالكان مستثنيان (السيرفر لا يعطيهما إلا «اختياري»).
// قبل تطبيق الترحيل (الدالة غير موجودة) أو قبل أول قراءة: القفل بـ`app_settings.ios_min_build` فقط — كما كان.

/// حالة نسخة هذا الجهاز كما حسبها السيرفر
nonisolated struct AppUpdatePolicy: Equatable {
    enum State: String { case none, optional, scheduled, forced }

    var state: State
    var reason: String?
    var exempt: Bool
    var canSnooze: Bool
    var latestBuild: Int
    var latestVersion: String?
    var minBuild: Int
    var deadline: Date?
    var updateURL: String?
    var snoozeDays: Int
    var whatsNew: [String]
    var forceTitle: String?
    var forceMessage: String?
    var serverNow: Date?

    /// «النسخة 1.0.1 — 50» (أو الرقم وحده)
    var versionLine: String {
        if let v = latestVersion, !v.isEmpty {
            return L10n.t("النسخة \(v) — \(latestBuild)", "Version \(v) — \(latestBuild)")
        }
        return L10n.t("النسخة \(latestBuild)", "Build \(latestBuild)")
    }
}

nonisolated extension AppUpdatePolicy: Decodable {
    private enum K: String, CodingKey {
        case state, reason, exempt, can_snooze, latest_build, latest_version, min_build, deadline, update_url,
             snooze_days, whats_new, force_title, force_message, server_now
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        state = State(rawValue: (try? c.decode(String.self, forKey: .state)) ?? "") ?? .none
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        exempt = (try? c.decodeIfPresent(Bool.self, forKey: .exempt)) ?? false
        canSnooze = (try? c.decodeIfPresent(Bool.self, forKey: .can_snooze)) ?? true
        latestBuild = (try? c.decodeIfPresent(Int.self, forKey: .latest_build)) ?? 0
        latestVersion = try? c.decodeIfPresent(String.self, forKey: .latest_version)
        minBuild = (try? c.decodeIfPresent(Int.self, forKey: .min_build)) ?? 0
        deadline = AppUpdateDates.parse(try? c.decodeIfPresent(String.self, forKey: .deadline))
        updateURL = try? c.decodeIfPresent(String.self, forKey: .update_url)
        snoozeDays = max(1, (try? c.decodeIfPresent(Int.self, forKey: .snooze_days)) ?? 2)
        whatsNew = ((try? c.decodeIfPresent([String].self, forKey: .whats_new)) ?? []).filter { !$0.isEmpty }
        forceTitle = try? c.decodeIfPresent(String.self, forKey: .force_title)
        forceMessage = try? c.decodeIfPresent(String.self, forKey: .force_message)
        serverNow = AppUpdateDates.parse(try? c.decodeIfPresent(String.self, forKey: .server_now))
    }
}

/// تواريخ السيرفر (ISO بكسور ثوانٍ أو بدونها، Z أو +00:00) — وعرض الموعد بتوقيت الكويت
nonisolated enum AppUpdateDates {
    static let kuwait = TimeZone(identifier: "Asia/Kuwait") ?? .current

    static func parse(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)
    }

    /// للسيرفر: وقت عالمي بلا كسور
    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// «الخميس 20 نوفمبر»
    static func dayLine(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        f.timeZone = kuwait
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f.string(from: date)
    }

    /// «الخميس 20 نوفمبر · 12:00 ص»
    static func dayTimeLine(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        f.timeZone = kuwait
        f.setLocalizedDateFormatFromTemplate("hmma")
        return "\(dayLine(date)) · \(f.string(from: date))"
    }
}

/// المربّع المعروض (نسخة واحدة)
struct AppUpdateSheetItem: Identifiable, Equatable {
    let policy: AppUpdatePolicy
    var id: Int { policy.latestBuild }
}

@MainActor
final class AppUpdateStore: ObservableObject {
    static let shared = AppUpdateStore()

    /// nil = لم تُقرأ بعد أو الدالة غير موجودة على السيرفر (الطريقة السابقة)
    @Published private(set) var policy: AppUpdatePolicy?
    @Published var sheet: AppUpdateSheetItem?

    /// وقت السيرفر − وقت الجهاز (العدّ والموعد بوقت السيرفر لا بساعة الجوال)
    private var clockOffset: TimeInterval = 0
    private var lastFetch: Date?
    private var isLoading = false
    /// آخر يوم (بلا «لاحقاً»): يظهر مرة لكل فتح للتطبيق
    private var shownThisLaunch: Set<Int> = []
    /// النسخة التي عُرض مربّعها الآن
    private var presented: AppUpdatePolicy?

    private static let minInterval: TimeInterval = 60
    private static func snoozeKey(_ build: Int) -> String { "appUpdate.snoozedUntil.\(build)" }

    var serverNow: Date { Date().addingTimeInterval(clockOffset) }

    static var platform: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipados" : "ios" }

    func refresh(force: Bool = false) async {
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < Self.minInterval { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let p: AppUpdatePolicy = try await SupabaseConfig.client
                .rpc("app_update_policy", params: AppUpdateParams(p_platform: Self.platform, p_build: AppBuild.current))
                .execute().value
            if let now = p.serverNow { clockOffset = now.timeIntervalSince(Date()) }
            policy = p
            lastFetch = Date()
        } catch {
            if ErrorHelper.isCancellation(error) { return }
            let pg = error as? PostgrestError
            if pg?.code == "PGRST202" || ErrorHelper.description(error).localizedCaseInsensitiveContains("could not find the function") {
                // الترحيل لم يُطبَّق — الطريقة السابقة (الحد الأدنى من app_settings)
                policy = nil
                lastFetch = Date()
            } else {
                // انقطاع: تبقى آخر قراءة كما هي
                Log.warning("[UPDATE] تعذّر جلب حالة التحديث: \(error.localizedDescription)")
            }
        }
    }

    /// شاشة «حدّث التطبيق» الحاجبة. `minBuildSetting` = `app_settings.ios_min_build` (يعمل قبل الترحيل وبعده).
    func isForced(minBuildSetting: Int, isOwner: Bool) -> Bool {
        if isOwner { return false }
        if AppBuild.current < minBuildSetting { return true }
        guard let p = policy, !p.exempt else { return false }
        if p.state == .forced { return true }
        // الموعد مرّ والتطبيق مفتوح من قبله
        if p.state == .scheduled, let d = p.deadline, serverNow >= d { return true }
        return false
    }

    /// يعرض المربّع إن لزم (بعد كل قراءة)
    func evaluateSheet(blocked: Bool) {
        guard !blocked, let p = policy, p.state == .optional || p.state == .scheduled, p.latestBuild > AppBuild.current else {
            if sheet != nil { sheet = nil }
            return
        }
        if sheet?.policy.latestBuild == p.latestBuild {
            if sheet?.policy != p { presented = p; sheet = AppUpdateSheetItem(policy: p) }   // نصوص أحدث لنفس النسخة
            return
        }
        let snoozable = p.canSnooze || p.exempt
        if snoozable {
            if let until = UserDefaults.standard.object(forKey: Self.snoozeKey(p.latestBuild)) as? Date, Date() < until { return }
        } else if shownThisLaunch.contains(p.latestBuild) {
            return
        }
        shownThisLaunch.insert(p.latestBuild)
        presented = p
        sheet = AppUpdateSheetItem(policy: p)
    }

    /// أُغلق المربّع (بأي طريقة)
    func sheetDismissed() {
        guard let p = presented else { return }
        presented = nil
        if p.canSnooze || p.exempt { snooze(p) }
    }

    /// «لاحقاً» أو إغلاق المربّع — يرجع بعد أيام السيرفر (آخر يوم: مع فتح التطبيق التالي)
    private func snooze(_ p: AppUpdatePolicy) {
        let until = Date().addingTimeInterval(TimeInterval(max(1, p.snoozeDays)) * 86_400)
        UserDefaults.standard.set(until, forKey: Self.snoozeKey(p.latestBuild))
    }

    /// رابط المتجر: من السيرفر، وإلا من إعدادات التطبيق
    func storeURL(fallback: String?) -> URL? {
        for raw in [policy?.updateURL, fallback] {
            if let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, let url = URL(string: s) { return url }
        }
        return nil
    }

    // MARK: - الجهاز يبلّغ نسخته («النسخ عند الأعضاء»)

    /// بعد تسجيل الجهاز — خارج upsert التسجيل حتى لا يكسره قبل الترحيل (الفشل صامت)
    static func reportBuild(deviceId: String) async {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        do {
            _ = try await SupabaseConfig.client
                .rpc("report_app_build", params: AppBuildReport(p_device_id: deviceId, p_build: AppBuild.current, p_version: version))
                .execute()
        } catch {
            if ErrorHelper.isCancellation(error) { return }
            Log.info("[UPDATE] لم يُسجَّل رقم النسخة (الترحيل غير مطبّق؟): \(error.localizedDescription)")
        }
    }
}

nonisolated private struct AppUpdateParams: Encodable, Sendable {
    let p_platform: String
    let p_build: Int
}

nonisolated private struct AppBuildReport: Encodable, Sendable {
    let p_device_id: String
    let p_build: Int
    let p_version: String
}

// MARK: - البوابة فوق التطبيق

private struct AppUpdateGateModifier: ViewModifier {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var store = AppUpdateStore.shared
    @Environment(\.scenePhase) private var scenePhase

    private var isOwner: Bool { authVM.currentUser?.role == .owner }

    func body(content: Content) -> some View {
        content
            .task { await refresh(force: true) }
            .onChange(of: scenePhase) { phase in
                if phase == .active { Task { await refresh(force: false) } }
            }
            // أي إغلاق («لاحقاً» أو السحب) = يرجع بعد أيام السيرفر؛ آخر يوم: مع فتح التطبيق التالي
            .dsHalfBox(item: $store.sheet, onDismiss: { store.sheetDismissed() }) { item in
                AnyView(AppUpdateSheet(policy: item.policy,
                                       serverNow: store.serverNow,
                                       storeURL: store.storeURL(fallback: appSettingsVM.settings.iosUpdateUrl),
                                       onLater: { store.sheet = nil }))
            }
    }

    private func refresh(force: Bool) async {
        await store.refresh(force: force)
        store.evaluateSheet(blocked: store.isForced(minBuildSetting: appSettingsVM.settings.iosMinBuild ?? 0, isOwner: isOwner))
    }
}

extension View {
    /// مربّع «فيه تحديث جديد» / «حدّث قبل…» حسب حالة السيرفر
    func appUpdateGate() -> some View { modifier(AppUpdateGateModifier()) }
}

// MARK: - المربّع

/// «فيه تحديث جديد» (اختياري) أو «حدّث قبل الخميس 20 نوفمبر» بعدّ تنازلي (من تاريخ). «لاحقاً» تختفي آخر يوم.
struct AppUpdateSheet: View {
    let policy: AppUpdatePolicy
    let serverNow: Date
    let storeURL: URL?
    let onLater: () -> Void
    @Environment(\.openURL) private var openURL

    private var scheduled: Bool { policy.state == .scheduled && policy.deadline != nil && !policy.exempt }
    private var showsLater: Bool { policy.canSnooze || policy.exempt }

    var body: some View {
        // هيكل المربّعات الموحّد (طلب المالك ٢٠٢٦-١١-١١): الرأس الكحلي، ثم «التحديث الآن» و«لاحقاً» الخفيف —
        // «لاحقاً» تختفي حين لا تأجيل (آخر يوم) كما كانت
        DSComposer(
            title: title,
            subtitle: subtitle,
            icon: scheduled ? "calendar" : "sparkles",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("التحديث الآن", "Update now"),
            actionIcon: "arrow.down.circle",
            cancelTitle: L10n.t("لاحقاً", "Later"),
            showsCancel: showsLater,
            canSubmit: storeURL != nil,
            onSubmit: { if let storeURL { openURL(storeURL) } },
            onCancel: onLater
        ) {
            VStack(spacing: DS.Spacing.lg) {
                if scheduled, let d = policy.deadline {
                    AppUpdateCountdown(deadline: d, now: serverNow)
                }
                if !policy.whatsNew.isEmpty {
                    AppUpdateWhatsNewList(lines: policy.whatsNew, showsLabel: !scheduled, onBand: false)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var title: String {
        if scheduled, let d = policy.deadline {
            return L10n.t("حدّث قبل \(AppUpdateDates.dayLine(d))", "Update before \(AppUpdateDates.dayLine(d))")
        }
        return L10n.t("يتوفر تحديث جديد", "A new update is available")
    }

    private var subtitle: String {
        scheduled ? L10n.t("بعدها لا يعمل التطبيق إلا بالنسخة الجديدة", "After that, the app opens only on the new version")
                  : policy.versionLine
    }

}

/// مربّع الأيقونة في أعلى المربّع والشاشة
struct AppUpdateIconTile: View {
    let symbol: String
    var onBand: Bool = false

    var body: some View {
        Image(systemName: symbol)
            .font(DS.Font.icon(onBand ? 30 : 24, weight: .semibold))
            .foregroundColor(onBand ? DS.Color.accentLight : DS.Color.accent)
            .frame(width: onBand ? DS.Icon.sizeLg + DS.Spacing.md : DS.Icon.size + DS.Spacing.sm,
                   height: onBand ? DS.Icon.sizeLg + DS.Spacing.md : DS.Icon.size + DS.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(onBand ? DS.Color.textOnPrimary.opacity(0.1) : DS.Color.cardBackgroundSoft))
            .accessibilityHidden(true)
    }
}

/// «٥ أيام · ١٤ ساعة»
struct AppUpdateCountdown: View {
    let deadline: Date
    let now: Date

    var body: some View {
        let total = max(0, Int(deadline.timeIntervalSince(now)))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        HStack(spacing: DS.Spacing.sm) {
            cell(days, L10n.t("أيام", "days"))
            cell(hours, L10n.t("ساعة", "hours"))
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("باقي \(days) أيام و\(hours) ساعة", "\(days) days and \(hours) hours left"))
    }

    private func cell(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text("\(n)")
                .dsFont(.statValue)
                .monospacedDigit()
                .foregroundColor(DS.Color.textPrimary)
            Text(label)
                .dsFont(.caption)
                .foregroundColor(DS.Color.accent)
        }
        .frame(minWidth: 52)
        .padding(.vertical, DS.Spacing.xsm)
        .padding(.horizontal, DS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.cardBackgroundSoft))
    }
}

/// «ما الجديد» — نقاط، بلون الأرضية الفاتحة أو فوق الكحلي
struct AppUpdateWhatsNewList: View {
    let lines: [String]
    var showsLabel: Bool = true
    var onBand: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            if showsLabel {
                Text(L10n.t("ما الجديد", "What's new"))
                    .dsFont(.caption)
                    .foregroundColor(onBand ? DS.Color.accentLight : DS.Color.accent)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                    Text(verbatim: "•")
                        .dsFont(.body)
                        .accessibilityHidden(true)
                    Text(line)
                        .dsFont(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundColor(onBand ? DS.Color.textOnPrimary : DS.Color.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
