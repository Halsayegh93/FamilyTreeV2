import SwiftUI
import UIKit
import Combine
import Supabase

// MARK: - «التطبيق» (إعادة التصميم ٢٠٢٦-١١-٢٦ — spec C.14، اختيار المالك «ب»: الحالة أولاً، الوحدة U17)
//
// للمالك وحده (`AdminAreaGate` كما هو). الرأس الكحلي: «‹ الإدارة» · «التطبيق ⌄» · «للمالك فقط. أي تغيير هنا يصل لكل
// الأعضاء.» ثم خمس بطاقات تحت عناوين صغيرة — بلا تبويبات:
//  ١) بطاقة الحالة «حالة التطبيق»: «الإصدار 1.0.1 (51)» بالذهبي الغامق + حبّة «يعمل للجميع ✓» / «متوقف للأعضاء»، وتحتها
//     «وضع الصيانة» (حبّة «مطفأ»/«مفعّل» — الضغط يسأل عند التشغيل فقط) · «إشعارات الجوال» (= «إيقاف الإشعارات»، حبّة
//     «تعمل»/«موقوفة» — يسأل عند الإيقاف فقط) · «فرض التحديث» (آخر إصدار في المتجر، «اختياري»/«إجباري» ‹ → صفحته).
//  ٢) «ما يراه الأعضاء»: لغة التطبيق (قائمة) · الديوانيات · شجرة النساء · مشاريع العائلة · الاستطلاعات.
//  ٣) «قواعد الأعضاء»: اعتماد الأخبار قبل نشرها · منع لقطة الشاشة في المكتبة (قائمة) · حدّ التعديلات الذاتية ·
//     «إعادة ضبط العدّاد» (أحمر، يسأل).
//  ٤) «القوائم»: تصنيفات الأخبار والمكتبة ‹ · أسماء العوائل والفروع ‹ · أسماء عن التطبيق ‹.
//  ٥) «النظام»: «الأخطاء» (Sentry، بعددها) ‹ · آخر تعديل للإعدادات · «استعادة الإعدادات الافتراضية» (أحمر، يسأل).
// نفس المفاتيح والنداءات (`updateSetting`، `resetToDefaults`، `set_app_config`، `ProfileEditCooldown`). كل كتابة تمرّ أولاً
// بـ`DebugAdminProbe.dryRun` (نجاح مصطنع محلي أثناء تجربة دور). الحالات (T1/T5): الحفظ = دوّارة صغيرة والباقي معطّل؛ الفشل
// يُرجع القيمة القديمة + «لم يُحفظ. أعد المحاولة»؛ قبل وصول الإعدادات الحبّات «تعذّر التحميل» أو هيكل والمفاتيح معطّلة.
// المنطق الخالص (الكلمات، ما يسأل، حال الحفظ) في AdminAppAreaLogic.swift ويُفحص بـ tests/admin-redesign/U17.
// حارس المكدس: جسم الصفحة خفيف، كل بطاقة نوع مستقل خلف `AnyView`، والوجهات خلف `AdminLazyPage` (`AdminTapWrap`).

struct AdminAppAreaPage: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @StateObject private var model = AdminAppAreaModel()

    /// المالك (`canManageSettings`) × «يعدّل» القسم في جدول السيرفر
    private var canEdit: Bool { authVM.canManageSettings && authVM.adminCanEdit(.app) }

    var body: some View {
        AdminHubPage {
            AdminBandHeader(title: AdminArea.app.title, subtitle: AdminAppLogic.pageSubtitle,
                            badge: canEdit ? nil : AdminPageHeader.readOnlyText, isAreaRoot: true)
        } content: {
            AnyView(AdminAppStatusCard(model: model, canEdit: canEdit))
            AnyView(AdminAppMembersCard(model: model, canEdit: canEdit))
            AnyView(AdminAppRulesCard(model: model, canEdit: canEdit))
            AnyView(AdminAppListsCard())
            AnyView(AdminAppSystemCard(model: model, canEdit: canEdit))
        }
        // ما يُدفع من الصفوف يرجع باسم القسم
        .environment(\.adminPageTitle, AdminArea.app.title)
        .onAppear { model.bind(settingsVM: appSettingsVM, authVM: authVM) }
        .refreshable { await model.reload(canEdit: canEdit, force: true) }
        .task {
            model.bind(settingsVM: appSettingsVM, authVM: authVM)
            await model.reload(canEdit: canEdit, force: false)
        }
        .dsAlert(model.pendingConfirm?.title ?? "",
                 isPresented: Binding(get: { model.pendingConfirm != nil },
                                      set: { if !$0 { model.pendingConfirm = nil } }),
                 presenting: model.pendingConfirm) { confirm in
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            Button(confirm.verb, role: .destructive) { model.perform(confirm) }
        } message: { confirm in
            Text(confirm.message)
        }
        .debugStackProbe("AdminAppAreaPage", limitKB: DebugStackLimit.page)
    }
}

/// نصوص الإصدار والوقت (رأس «حالة التطبيق»، وتواريخ صفحة الأخطاء)
enum AppVersionText {
    static var short: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    /// رقم البناء («51») — لا يُعرض: طلب المالك ٢٠٢٦-١٠-٣١ «الإصدار بلا رقم البناء» يغلب spec C.14
    static var build: String? { Bundle.main.infoDictionary?["CFBundleVersion"] as? String }
    /// الإصدار الرسمي فقط بلا رقم البناء (طلب المالك ٢٠٢٦-١٠-٣١)
    static var full: String { short }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func stamp(_ date: Date) -> String { DateHelper.displayDateTime(date) }
}

// MARK: - النموذج: الجلب والحفظ (مكان واحد لكل كتابة في الصفحة)

nonisolated private struct AdminAppConfigParams: Encodable, Sendable {
    let p_key: String
    let p_value: String
}

@MainActor
final class AdminAppAreaModel: ObservableObject {
    /// `app_settings` (`fetchSettings` لا يُبلغ الفشل — وصلت = `updatedAt`، كـ«الفريق والأمان»)
    @Published private(set) var settingsHealth: AdminStoreHealth = .idle
    /// `app_config` (منع لقطة الشاشة)
    @Published private(set) var configHealth: AdminStoreHealth = .idle
    @Published private(set) var save = AdminAppSaveState()
    /// تأكيد ينتظر «نعم» (spec A.14)
    @Published var pendingConfirm: AdminAppLogic.Confirm?
    /// «حدّ التعديلات الذاتية» على هذا الجهاز (`ProfileEditCooldown` — محلي كما كان)
    @Published private(set) var cooldownDisabled = ProfileEditCooldown.shared.isDisabled
    /// قيم `app_config` حُفظت من هنا (أو اصطُنعت في تجربة دور) — تغلب الذاكرة حتى يعيد الجلب نفس القيمة
    @Published private(set) var configOverride: [String: String] = [:]
    /// آخر قيمة طُلبت لكل إعداد — «أعد المحاولة» يعيدها
    private var lastAttempt: [AdminAppSetting: AdminAppValue] = [:]

    private weak var settingsVM: AppSettingsViewModel?
    private weak var authVM: AuthViewModel?

    func bind(settingsVM: AppSettingsViewModel, authVM: AuthViewModel) {
        self.settingsVM = settingsVM
        self.authVM = authVM
    }

    // MARK: الجلب — كل مخزن وحده (فشل واحد لا يوقف الباقي)

    func reload(canEdit: Bool, force: Bool) async {
        let viewsErrors = authVM?.canViewSystemSettings ?? false
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in await self.loadSettings() }
            group.addTask { @MainActor in await self.loadConfig() }
            // «فرض التحديث» الجديد للمالك فقط (`update_policy_admin`) — كصفحته
            if canEdit { group.addTask { @MainActor in await AdminUpdatePolicyStore.shared.load() } }
            // عدد «الأخطاء» (Sentry) — لا يتكرر خلال دقيقة إلا بالسحب
            if viewsErrors { group.addTask { @MainActor in await AdminErrorsStore.shared.refresh(force: force) } }
        }
    }

    func loadSettings() async {
        guard let vm = settingsVM else { return }
        settingsHealth = AdminAppLogic.seeded(settingsHealth, hasData: vm.settings.updatedAt != nil).beginning()
        await vm.fetchSettings()
        settingsHealth = settingsHealth.ending(success: vm.settings.updatedAt != nil && NetworkMonitor.shared.isConnected)
    }

    /// حبّة الرأس «تعذّر التحميل ↻»
    func retrySettings() {
        Task { await loadSettings() }
    }

    func loadConfig() async {
        let config = AppConfigValues.shared
        configHealth = AdminAppLogic.seeded(configHealth, hasData: !config.values.isEmpty).beginning()
        await config.refresh(force: true)
        configHealth = configHealth.ending(success: !config.values.isEmpty && NetworkMonitor.shared.isConnected)
    }

    /// قيمة «منع لقطة الشاشة في المكتبة» الظاهرة
    func shield(_ config: AppConfigValues) -> String {
        let key = AdminAppSetting.libraryShield.serverKey ?? ""
        return configOverride[key] ?? config.string(key) ?? AdminAppLogic.shieldFallback
    }

    // MARK: الطلب ← (تأكيد) ← الحفظ

    /// ضغطة على مفتاح أو حبّة أو قائمة أو صفّ أحمر: ما يسأل ينتظر «نعم»، والباقي يُحفظ فوراً
    func request(_ setting: AdminAppSetting, to value: AdminAppValue?) {
        guard !save.isBusy else { return }
        if let ask = AdminAppLogic.confirm(for: setting, to: value) {
            pendingConfirm = ask
            return
        }
        Task { await write(setting, value) }
    }

    /// «نعم» في مربّع التأكيد
    func perform(_ confirm: AdminAppLogic.Confirm) {
        pendingConfirm = nil
        let change = confirm.change
        Task { await write(change.setting, change.value) }
    }

    /// «لم يُحفظ. أعد المحاولة» — نفس الطلب (وما يسأل يسأل من جديد)
    func retry(_ setting: AdminAppSetting) {
        if setting.store == .command {
            request(setting, to: nil)
        } else if let value = lastAttempt[setting] {
            request(setting, to: value)
        }
    }

    private func write(_ setting: AdminAppSetting, _ value: AdminAppValue?) async {
        guard save.begin(setting) else { return }
        if let value { lastAttempt[setting] = value }
        let ok: Bool
        switch setting.store {
        case .settings: ok = await writeSettings(setting, value)
        case .config:   ok = await writeConfig(setting, value)
        case .local:    ok = writeLocal(value)
        case .command:  ok = await runCommand(setting)
        }
        save.finish(setting, success: ok)
        if !ok {
            UIAccessibility.post(notification: .announcement,
                                 argument: AdminAppLogic.failedAnnouncement(setting.rowTitle))
        }
    }

    /// صفّ `app_settings`: القيمة تظهر فوراً، والفشل (خطأ، أو تحديث بلا صفوف فرجعت القيمة القديمة) يعيد القديمة
    private func writeSettings(_ setting: AdminAppSetting, _ value: AdminAppValue?) async -> Bool {
        guard let vm = settingsVM, let key = setting.serverKey, let value,
              let old = vm.settings.adminAppValue(setting) else { return false }
        if DebugAdminProbe.dryRun("app_settings \(key)=\(value.logText)") {
            vm.settings.setAdminAppValue(value, for: setting)
            return true
        }
        vm.settings.setAdminAppValue(value, for: setting)
        vm.errorMessage = nil
        let by = authVM?.currentUser?.id
        switch value {
        case .flag(let on):   await vm.updateSetting(key, value: on, updatedBy: by)
        case .text(let text): await vm.updateSetting(key, value: text, updatedBy: by)
        }
        let ok = AdminAppLogic.saveSucceeded(desired: value, after: vm.settings.adminAppValue(setting) ?? old,
                                             errored: vm.errorMessage != nil)
        if !ok { vm.settings.setAdminAppValue(old, for: setting) }
        return ok
    }

    /// `app_config` عبر `set_app_config` (المالك) — نفس الكتابة السابقة
    private func writeConfig(_ setting: AdminAppSetting, _ value: AdminAppValue?) async -> Bool {
        guard let key = setting.serverKey, let text = value?.text else { return false }
        let previous = configOverride[key]
        configOverride[key] = text
        if DebugAdminProbe.dryRun("set_app_config \(key)=\(text)") { return true }
        do {
            _ = try await SupabaseConfig.client.rpc("set_app_config",
                                                    params: AdminAppConfigParams(p_key: key, p_value: text)).execute()
            await AppConfigValues.shared.refresh(force: true)
            return true
        } catch {
            configOverride[key] = previous
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[CONFIG] تعذّر حفظ \(key): \(error.localizedDescription)")
            }
            return false
        }
    }

    /// «حدّ التعديلات الذاتية» (محلي كما كان)
    private func writeLocal(_ value: AdminAppValue?) -> Bool {
        guard let limitOn = value?.flag else { return false }
        if DebugAdminProbe.dryRun("ProfileEditCooldown isDisabled=\(!limitOn)") {
            cooldownDisabled = !limitOn
            return true
        }
        ProfileEditCooldown.shared.isDisabled = !limitOn
        cooldownDisabled = ProfileEditCooldown.shared.isDisabled
        return cooldownDisabled == !limitOn
    }

    /// الأمران الأحمران بعد «نعم»
    private func runCommand(_ setting: AdminAppSetting) async -> Bool {
        switch setting {
        case .resetCounter:
            if !DebugAdminProbe.dryRun("ProfileEditCooldown resetAllCooldowns") {
                ProfileEditCooldown.shared.resetAllCooldowns()
            }
            DSMomentToast.show(L10n.t("صُفّر العدّاد", "Counter reset"), moment: .success)
            return true
        case .restoreDefaults:
            guard let vm = settingsVM else { return false }
            if DebugAdminProbe.dryRun("app_settings resetToDefaults") {
                vm.settings.adminAppRestoreDefaults()
            } else {
                vm.errorMessage = nil
                await vm.resetToDefaults(updatedBy: authVM?.currentUser?.id)
                guard vm.errorMessage == nil else { return false }
            }
            DSMomentToast.show(L10n.t("استُعيدت الإعدادات الافتراضية", "Default settings restored"), moment: .success)
            return true
        default:
            return false
        }
    }
}

// MARK: - الربط بالنماذج

extension AppSettings {
    /// قيمة إعداد من صفّ `app_settings` كما تظهر (nil يعني الافتراضي: الأقسام ظاهرة، الإشعارات تعمل، العربية)
    func adminAppValue(_ setting: AdminAppSetting) -> AdminAppValue? {
        switch setting {
        case .maintenance:  return .flag(maintenanceMode)
        case .pushPaused:   return .flag(notificationsPaused == true)
        case .language:     return .text(defaultLanguage ?? "ar")
        case .diwaniyas:    return .flag(diwaniyasEnabled ?? true)
        case .womenTree:    return .flag(womenTreeEnabled ?? true)
        case .projects:     return .flag(projectsEnabled ?? true)
        case .polls:        return .flag(pollsEnabled ?? true)
        case .newsApproval: return .flag(newsRequiresApproval)
        case .libraryShield, .selfEditLimit, .resetCounter, .restoreDefaults: return nil
        }
    }

    mutating func setAdminAppValue(_ value: AdminAppValue, for setting: AdminAppSetting) {
        switch (setting, value) {
        case (.maintenance, .flag(let b)):  maintenanceMode = b
        case (.pushPaused, .flag(let b)):   notificationsPaused = b
        case (.language, .text(let t)):     defaultLanguage = t
        case (.diwaniyas, .flag(let b)):    diwaniyasEnabled = b
        case (.womenTree, .flag(let b)):    womenTreeEnabled = b
        case (.projects, .flag(let b)):     projectsEnabled = b
        case (.polls, .flag(let b)):        pollsEnabled = b
        case (.newsApproval, .flag(let b)): newsRequiresApproval = b
        default: break
        }
    }

    /// تجربة دور: نفس قيم `resetToDefaults` محلياً بلا كتابة
    mutating func adminAppRestoreDefaults() {
        newsRequiresApproval = true
        allowNewRegistrations = true
        maintenanceMode = false
        notificationsPaused = false
        maxDevicesPerUser = 3
        pollsEnabled = true
        diwaniyasEnabled = true
        projectsEnabled = true
        albumsEnabled = true
        womenTreeEnabled = true
    }
}

extension AdminAppSetting {
    /// اسم الصفّ (للقارئ الصوتي حين يفشل الحفظ)
    var rowTitle: String {
        switch self {
        case .maintenance:     return L10n.t("وضع الصيانة", "Maintenance mode")
        case .pushPaused:      return L10n.t("إشعارات الجوال", "Phone notifications")
        case .language:        return L10n.t("لغة التطبيق", "App language")
        case .diwaniyas:       return L10n.t("الديوانيات", "Diwaniyas")
        case .womenTree:       return L10n.t("شجرة النساء", "Women's tree")
        case .projects:        return L10n.t("مشاريع العائلة", "Family projects")
        case .polls:           return L10n.t("الاستطلاعات", "Polls")
        case .newsApproval:    return L10n.t("اعتماد الأخبار قبل نشرها", "Approve news before publishing")
        case .libraryShield:   return L10n.t("منع لقطة الشاشة في المكتبة", "Block screenshots in the library")
        case .selfEditLimit:   return L10n.t("حدّ التعديلات الذاتية", "Self-edit limit")
        case .resetCounter:    return L10n.t("إعادة ضبط العدّاد", "Reset the counter")
        case .restoreDefaults: return L10n.t("استعادة الإعدادات الافتراضية", "Restore default settings")
        }
    }
}

extension AdminAppLogic.Tone {
    var pill: AdminPillTone {
        switch self {
        case .ok:    return .ok
        case .off:   return .off
        case .warn:  return .warn
        case .error: return .error
        }
    }
}

// MARK: - ١) بطاقة الحالة «حالة التطبيق»

/// رأسها الإصدار بالذهبي الغامق وحبّة الحال، وتحتها الصيانة والإشعارات (حبّة تغيّر حين تُضغط) و«فرض التحديث» (يفتح صفحته)
struct AdminAppStatusCard: View {
    @ObservedObject var model: AdminAppAreaModel
    let canEdit: Bool
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var policy = AdminUpdatePolicyStore.shared

    var body: some View {
        let s = appSettingsVM.settings
        let health = model.settingsHealth
        let head = AdminAppLogic.statusWord(maintenanceOn: s.maintenanceMode)
        let paused = s.notificationsPaused == true
        AdminSectionCard(title: L10n.t("حالة التطبيق", "App status"), spacing: 0,
                         status: AdminStatePill(health: health, title: head.text, tone: head.tone.pill, icon: head.icon,
                                                retry: { model.retrySettings() }),
                         subtitle: AdminAppLogic.versionLine(short: AppVersionText.short, build: nil)) {
            AdminRowsCardBody {
                AdminAppActingRow(model: model, setting: .maintenance, icon: "wrench.and.screwdriver.fill",
                                  tint: DS.Color.slateFill, title: AdminAppSetting.maintenance.rowTitle,
                                  subtitle: L10n.t("يوقف التطبيق للأعضاء فقط", "Stops the app for members only"),
                                  current: s.maintenanceMode, word: AdminAppLogic.maintenanceWord(on: s.maintenanceMode),
                                  hint: AdminAppLogic.maintenanceHint(on: s.maintenanceMode),
                                  health: health, canEdit: canEdit)
                AdminAppActingRow(model: model, setting: .pushPaused, icon: "bell.fill",
                                  tint: DS.Color.slateFill, title: AdminAppSetting.pushPaused.rowTitle,
                                  subtitle: AdminAppLogic.pushLine(paused: paused),
                                  current: paused, word: AdminAppLogic.pushWord(paused: paused),
                                  hint: AdminAppLogic.pushHint(paused: paused),
                                  health: health, canEdit: canEdit)
                forceUpdateRow(s)
            }
        }
    }

    /// «فرض التحديث»: آخر إصدار في المتجر + «اختياري»/«إجباري» ‹ → `AdminForceUpdateView` (بيت الأمر الوحيد)
    private func forceUpdateRow(_ s: AppSettings) -> some View {
        let f = forceFacts(s)
        let pill = AdminStatePill(health: f.health, title: f.word.text, tone: f.word.tone.pill, icon: f.word.icon)
        return AdminTapWrap(tap: .page { AnyView(AdminForceUpdateView()) }, feel: .row, label: AnyView(
            AdminListRow(icon: "arrow.down.app.fill", tint: DS.Color.navyFill,
                         title: L10n.t("فرض التحديث", "Force update"), subtitle: f.line) { pill.fixedSize() }
        ))
    }

    /// من إعدادات «فرض التحديث» الجديدة (المالك)، وقبل ترحيلها (أو لغير المالك) من `app_settings` كما كانت الصفحة
    private func forceFacts(_ s: AppSettings) -> (word: AdminAppLogic.Word, line: String, health: AdminStoreHealth) {
        let iosMin = s.iosMinBuild ?? 0
        let androidMin = s.androidMinBuild ?? 0
        let legacyAndroid = (s.forceUpdate ?? false) && (s.latestBuild ?? 0) > 1
        let legacy = (word: AdminAppLogic.forceUpdateWord(required: AdminAppLogic.legacyForceRequired(
                        iosMin: iosMin, androidMin: androidMin, legacyAndroid: legacyAndroid)),
                      line: model.settingsHealth.hasData ? AdminAppLogic.legacyLine(iosMin: iosMin, androidMin: androidMin)
                                                         : AdminStoreHealthText.placeholder,
                      health: model.settingsHealth)
        guard canEdit else { return legacy }
        if let p = policy.policy {
            let required = AdminAppLogic.forceUpdateRequired(modes: [p.ios.mode.rawValue, p.android.mode.rawValue])
            return (word: AdminAppLogic.forceUpdateWord(required: required),
                    line: AdminAppLogic.storeLine(ios: p.ios.latestBuild, android: p.android.latestBuild),
                    health: AdminStoreHealth.loaded(at: .distantPast))
        }
        switch policy.phase {
        case .unavailable, .loaded:
            return legacy
        case .loading:
            return (word: legacy.word, line: AdminStoreHealthText.placeholder, health: AdminStoreHealth.loading)
        case .failed:
            return (word: legacy.word,
                    line: L10n.t("تعذّر جلب إعدادات التحديث", "Couldn't load the update settings"),
                    health: AdminStoreHealth.failed(lastGood: nil))
        }
    }
}

// MARK: - ٢) «ما يراه الأعضاء»

struct AdminAppMembersCard: View {
    @ObservedObject var model: AdminAppAreaModel
    let canEdit: Bool
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    var body: some View {
        let s = appSettingsVM.settings
        let health = model.settingsHealth
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: L10n.t("ما يراه الأعضاء", "What members see"))
            AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                AdminAppMenuRow(model: model, setting: .language, icon: "globe", tint: DS.Color.navyFill,
                                subtitle: L10n.t("لكل الأعضاء، ومن اختار لغته تبقى له",
                                                 "For everyone; anyone who picked a language keeps it"),
                                options: AdminAppLogic.languages, current: s.defaultLanguage ?? "ar",
                                health: health, canEdit: canEdit)
                AdminAppToggleRow(model: model, setting: .diwaniyas, icon: AppSection.diwaniyas.symbol,
                                  tint: DS.Color.navyFill, subtitle: L10n.t("قسم الديوانيات", "The Diwaniyas section"),
                                  isOn: s.diwaniyasEnabled ?? true, health: health, canEdit: canEdit)
                AdminAppToggleRow(model: model, setting: .womenTree, icon: "tree.fill", tint: DS.Color.palmFill,
                                  subtitle: L10n.t("داخل قسم الشجرة", "Inside the Tree section"),
                                  isOn: s.womenTreeEnabled ?? true, health: health, canEdit: canEdit)
                AdminAppToggleRow(model: model, setting: .projects, icon: "briefcase.fill", tint: DS.Color.goldFill,
                                  subtitle: L10n.t("في الرئيسية", "On Home"),
                                  isOn: s.projectsEnabled ?? true, health: health, canEdit: canEdit)
                AdminAppToggleRow(model: model, setting: .polls, icon: "chart.bar.fill", tint: DS.Color.seaFill,
                                  subtitle: L10n.t("استطلاع داخل الخبر", "A poll inside a news post"),
                                  isOn: s.pollsEnabled ?? true, health: health, canEdit: canEdit)
            }
        }
    }
}

// MARK: - ٣) «قواعد الأعضاء»

struct AdminAppRulesCard: View {
    @ObservedObject var model: AdminAppAreaModel
    let canEdit: Bool
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var config = AppConfigValues.shared

    var body: some View {
        let s = appSettingsVM.settings
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: L10n.t("قواعد الأعضاء", "Member rules"))
            AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                AdminAppToggleRow(model: model, setting: .newsApproval, icon: "checkmark.shield.fill",
                                  tint: DS.Color.navyFill,
                                  subtitle: L10n.t("أخبار الأعضاء تنتظر اعتماد الإدارة", "Members' posts wait for approval"),
                                  isOn: s.newsRequiresApproval, health: model.settingsHealth, canEdit: canEdit)
                // `app_config.library_screen_protection` — الحفظ والمشاركة لكل عنصر من قائمته في المكتبة
                AdminAppMenuRow(model: model, setting: .libraryShield, icon: "eye.slash.fill", tint: DS.Color.slateFill,
                                subtitle: L10n.t("الملفات تظهر فارغة في اللقطة", "Files show blank in screenshots"),
                                options: AdminAppLogic.shieldOptions, current: model.shield(config),
                                health: model.configHealth, canEdit: canEdit)
                // العدّاد على الجهاز (`ProfileEditCooldown`) — قيمته حاضرة دائماً
                AdminAppToggleRow(model: model, setting: .selfEditLimit, icon: "timer", tint: DS.Color.slateFill,
                                  subtitle: L10n.t("3 تعديلات ثم بموافقة الإدارة", "3 edits, then admin approval"),
                                  isOn: !model.cooldownDisabled, health: .loaded(at: .distantPast), canEdit: canEdit)
                if canEdit {
                    AdminAppCommandRow(model: model, setting: .resetCounter, icon: "arrow.counterclockwise",
                                       subtitle: L10n.t("تصفير فترات الانتظار", "Clear the waiting periods"))
                }
                // «تنبيه الصورة» + تذكير طلب الصورة (P1، ٢٠٢٦-١١-٢٦) — `app_config` عبر `set_app_config` (المالك)
                AdminPhotoReminderRow(kind: .popupDays, health: model.configHealth, canEdit: canEdit)
                AdminPhotoReminderRow(kind: .remindDays, health: model.configHealth, canEdit: canEdit)
                AdminPhotoReminderRow(kind: .maxReminders, health: model.configHealth, canEdit: canEdit)
            }
        }
    }
}

// MARK: - «تنبيه الصورة» وتذكير طلب الصورة (P1)

/// صفّ رقم بـ«−/+» يكتب مفتاح `app_config` (int) بـ`set_app_config` — للمالك. القيمة تظهر فوراً، والفشل يُرجع القديمة
/// + «لم يُحفظ. أعد المحاولة»؛ مفتاح غائب على السيرفر (قبل الترحيل) = «يحتاج تحديث السيرفر» بلا أزرار.
private struct AdminPhotoReminderRow: View {
    enum Kind {
        /// «تنبيه الصورة»: «كمّل ملفك بصورة» يرجع بعد (`photo_reminder_days`)
        case popupDays
        /// «التذكير كل 3 أيام» (`photo_request_remind_days`)
        case remindDays
        /// «حتى 3 تذكيرات» (`photo_request_max_reminders`)
        case maxReminders

        var key: String {
            switch self {
            case .popupDays:    return "photo_reminder_days"
            case .remindDays:   return PhotoNudgeLogic.remindDaysKey
            case .maxReminders: return PhotoNudgeLogic.maxRemindersKey
            }
        }

        var range: ClosedRange<Int> {
            switch self {
            case .popupDays:    return 0...365
            case .remindDays:   return PhotoNudgeLogic.remindDaysRange
            case .maxReminders: return PhotoNudgeLogic.maxRemindersRange
            }
        }

        var ladder: [Int]? { self == .popupDays ? [0, 7, 14, 30, 60, 90, 180, 365] : nil }
        var unit: ApprovalHoursStepper.Unit { self == .maxReminders ? .count : .days }
        var icon: String {
            switch self {
            case .popupDays:    return "person.crop.circle.badge.plus"
            case .remindDays:   return "bell.badge.fill"
            case .maxReminders: return "number"
            }
        }

        var title: String {
            switch self {
            case .popupDays:    return L10n.t("تنبيه الصورة", "Photo prompt")
            case .remindDays:   return L10n.t("تذكير طلب الصورة", "Photo request reminder")
            case .maxReminders: return L10n.t("حدّ التذكيرات", "Reminder limit")
            }
        }

        func subtitle(_ v: Int) -> String {
            switch self {
            case .popupDays:
                return v == 0 ? L10n.t("«كمّل ملفك بصورة» مطفأ", "«Add a photo» prompt off")
                              : L10n.t("«كمّل ملفك بصورة» يرجع بعد \(v) يوم", "«Add a photo» returns after \(v) days")
            case .remindDays:
                switch v {
                case 0:  return L10n.t("بلا تذكير", "No reminders")
                case 1:  return L10n.t("التذكير كل يوم", "Remind every day")
                case 2:  return L10n.t("التذكير كل يومين", "Remind every 2 days")
                default: return L10n.t("التذكير كل \(v) أيام", "Remind every \(v) days")
                }
            case .maxReminders:
                switch v {
                case 0:  return L10n.t("بلا تذكير", "No reminders")
                case 1:  return L10n.t("تذكير واحد", "1 reminder")
                case 2:  return L10n.t("حتى تذكيرين", "Up to 2 reminders")
                default: return L10n.t("حتى \(v) تذكيرات", "Up to \(v) reminders")
                }
            }
        }
    }

    let kind: Kind
    let health: AdminStoreHealth
    let canEdit: Bool
    @ObservedObject private var config = AppConfigValues.shared
    /// قيمة حُفظت للتو (تغلب الذاكرة حتى يعيد الجلب)
    @State private var pending: Int?
    @State private var saving = false
    @State private var failed: Int?
    @State private var missing = false

    private nonisolated struct Params: Encodable, Sendable {
        let p_key: String
        let p_value: Int
    }

    /// المفتاح على السيرفر (بعد الترحيل) — قبل وصول القيم لا يُحكم بغيابه
    private var exists: Bool { config.values[kind.key] != nil }
    private var value: Int { pending ?? config.int(kind.key, default: 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AdminControlRow(icon: kind.icon, tint: DS.Color.sadu, title: kind.title, subtitle: subtitleText,
                            control: control)
            if let failed {
                AdminAppFailLine(busy: saving) { write(failed) }
            }
        }
    }

    private var subtitleText: String {
        guard AdminAppLogic.showsValue(health) else { return AdminStoreHealthText.placeholder }
        guard exists && !missing else {
            return L10n.t("يحتاج تحديث السيرفر", "Needs a server update")
        }
        return kind.subtitle(value)
    }

    private var control: AnyView {
        guard AdminAppLogic.showsValue(health), exists, !missing else { return AnyView(EmptyView()) }
        let enabled = AdminAppLogic.controlEnabled(health: health, canEdit: canEdit, busy: saving)
        return AnyView(HStack(spacing: DS.Spacing.sm) {
            if saving { AdminAppSpinner() }
            ApprovalHoursStepper(value: value, range: kind.range, step: 1, label: kind.title,
                                 onChange: { write($0) }, unit: kind.unit, ladder: kind.ladder,
                                 zeroText: L10n.t("مطفأ", "Off"))
                .disabled(!enabled)
        })
    }

    private func write(_ v: Int) {
        guard canEdit, !saving else { return }
        let old = pending
        pending = v
        failed = nil
        if DebugAdminProbe.dryRun("set_app_config \(kind.key)=\(v)") { return }
        saving = true
        Task {
            do {
                _ = try await SupabaseConfig.client.rpc("set_app_config", params: Params(p_key: kind.key, p_value: v)).execute()
                await AppConfigValues.shared.refresh(force: true)
                if config.int(kind.key, default: -1) == v { pending = nil }
            } catch {
                pending = old
                if (error as? PostgrestError)?.hint == "unknown_key" {
                    missing = true
                } else if !ErrorHelper.isCancellation(error) {
                    failed = v
                    UIAccessibility.post(notification: .announcement, argument: AdminAppLogic.failedAnnouncement(kind.title))
                    Log.warning("[CONFIG] تعذّر حفظ \(kind.key): \(error.localizedDescription)")
                }
            }
            saving = false
        }
    }
}

// MARK: - ٤) «القوائم»

struct AdminAppListsCard: View {
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    var body: some View {
        let branches = AdminAppLogic.branchesValue(branchNamesCount)
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: L10n.t("القوائم", "Lists"))
            AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                AdminTapRow(icon: "tag.fill", tint: DS.Color.goldFill,
                            title: L10n.t("تصنيفات الأخبار والمكتبة", "News & library categories"),
                            subtitle: L10n.t("الاسم والأيقونة واللون والترتيب", "Name, icon, colour and order"),
                            tap: .page { AnyView(CategoriesManagerView()) })
                AdminTapWrap(tap: .page { AnyView(AdminFamilyNamesView()) }, feel: .row, label: AnyView(
                    AdminListRow(icon: "person.2.crop.square.stack.fill", tint: DS.Color.palmFill,
                                 title: L10n.t("أسماء العوائل والفروع", "Family and branch names"),
                                 subtitle: branches == nil
                                    ? L10n.t("يختار منها العضو عائلته، وأسماء قائمة الفروع",
                                             "Members pick their family; branch list names")
                                    : nil) {
                        if let branches {
                            Text(verbatim: branches)
                                .dsFont(.body)
                                .monospacedDigit()
                                .foregroundColor(DS.Color.textSecondary)
                                .lineLimit(1)
                        }
                    }
                ))
                // أسماء مربّع «عن التطبيق» (طلب المالك ٢٠٢٦-١١-١٤)
                AdminTapRow(icon: "info.circle.fill", tint: DS.Color.navyFill,
                            title: L10n.t("أسماء عن التطبيق", "About box names"),
                            subtitle: L10n.t("الأسماء في مربع «عن التطبيق»", "Names in the About box"),
                            tap: .page { AnyView(AdminAboutCreditsView()) })
            }
        }
    }

    private var branchNamesCount: Int {
        (appSettingsVM.settings.branchNames ?? [:]).values
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
}

// MARK: - ٥) «النظام»

struct AdminAppSystemCard: View {
    @ObservedObject var model: AdminAppAreaModel
    let canEdit: Bool
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var errors = AdminErrorsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: L10n.t("النظام", "System"))
            AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                // «الأخطاء» (طلب المالك ٢٠٢٦-١١-٢٦): ما يصل Sentry من الآيفون والأندرويد والموقع — `AdminErrorsPage.swift`
                AdminTapWrap(tap: .page { AnyView(AdminErrorsPage()) }, feel: .row, label: AnyView(
                    AdminListRow(icon: "exclamationmark.triangle.fill", tint: DS.Color.slateFill,
                                 title: AdminErrorsText.pageTitle,
                                 subtitle: L10n.t("من الآيفون والأندرويد والموقع", "From iPhone, Android and the website")) {
                        errorsValue
                    }
                ))
                AdminInfoRow(icon: "clock.fill", tint: DS.Color.slateFill,
                             title: L10n.t("آخر تعديل للإعدادات", "Last settings change"),
                             trailing: AnyView(Text(verbatim: lastChange)
                                .dsFont(.body)
                                .monospacedDigit()
                                .foregroundColor(DS.Color.textSecondary)
                                .lineLimit(1)))
                if canEdit {
                    AdminAppCommandRow(model: model, setting: .restoreDefaults, icon: "arrow.counterclockwise",
                                       subtitle: L10n.t("المفاتيح في هذه الصفحة ترجع لأولها", "The switches here go back to their defaults"))
                }
            }
        }
    }

    /// عدد الأخطاء المختلفة في فترة الصفحة (Sentry) — «—» أثناء أول جلب، ولا شيء حين لم يُربط أو فشل (الصفحة تقول السبب)
    @ViewBuilder
    private var errorsValue: some View {
        if !errors.notConfigured, let list = errors.current {
            let count = AdminAppLogic.errorsValue(totals: Array(list.totals.values))
            AdminRowValue(text: count)
                .accessibilityLabel(Text(verbatim: "\(count) · \(AdminErrorsText.period(list.days))"))
        } else if errors.isLoading {
            Text(verbatim: AdminStoreHealthText.placeholder)
                .dsFont(.body)
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityLabel(AdminStoreHealthText.loading)
        }
    }

    private var lastChange: String {
        guard model.settingsHealth.hasData,
              let date = AdminDeviceReachStore.date(appSettingsVM.settings.updatedAt) else {
            return AdminStoreHealthText.placeholder
        }
        return AdminAppLogic.dayMonth(date)
    }
}

// MARK: - الصفوف

/// صفّ بحبّة تغيّر حين يُضغط (الصيانة، إشعارات الجوال — «ب» المالك): الصفّ كله زرّ واحد (لمس ≥ ٥٦)، سمة الزرّ وتلميح
/// «يسأل قبل التغيير» حين يسأل، دوّارة صغيرة داخل الحبّة أثناء الحفظ. لغير من يعدّل: الحبّة كلمة فقط
private struct AdminAppActingRow: View {
    @ObservedObject var model: AdminAppAreaModel
    let setting: AdminAppSetting
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    /// القيمة الآن (الضغط يكتب عكسها)
    let current: Bool
    let word: AdminAppLogic.Word
    let hint: String
    let health: AdminStoreHealth
    let canEdit: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if canEdit {
                Button { model.request(setting, to: .flag(!current)) } label: { face }
                    .buttonStyle(AdminRowPressStyle())
                    .disabled(!AdminAppLogic.controlEnabled(health: health, canEdit: canEdit, busy: model.save.isBusy))
                    .accessibilityHint(hint)
            } else {
                face
            }
            if model.save.hasFailed(setting) {
                AdminAppFailLine(busy: model.save.isBusy) { model.retry(setting) }
            }
        }
    }

    private var face: some View {
        AdminListRow(icon: icon, tint: tint, title: title, subtitle: subtitle, showsChevron: false) {
            pill.fixedSize()
        }
    }

    private var pill: AdminStatePill {
        model.save.isSaving(setting)
            ? AdminStatePill(title: word.text, tone: word.tone.pill, icon: word.icon, isBusy: true)
            : AdminStatePill(health: health, title: word.text, tone: word.tone.pill, icon: word.icon)
    }
}

/// صفّ مفتاح: قبل وصول قيمته هيكل معطّل (لا قيمة افتراضية مضلِّلة)، أثناء الحفظ دوّارة صغيرة بجانبه والباقي معطّل،
/// والفشل يعيده ويترك سطر «لم يُحفظ». لغير من يعدّل كلمة «مفعّل»/«مطفأ» (spec A.12)
private struct AdminAppToggleRow: View {
    @ObservedObject var model: AdminAppAreaModel
    let setting: AdminAppSetting
    let icon: String
    let tint: Color
    var subtitle: String? = nil
    let isOn: Bool
    let health: AdminStoreHealth
    let canEdit: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AdminControlRow(icon: icon, tint: tint, title: setting.rowTitle, subtitle: subtitle, control: control)
            if model.save.hasFailed(setting) {
                AdminAppFailLine(busy: model.save.isBusy) { model.retry(setting) }
            }
        }
    }

    private var control: AnyView {
        guard canEdit else {
            let word = AdminAppLogic.onOffWord(isOn)
            return AnyView(AdminStatePill(health: health, title: word.text, tone: word.tone.pill).fixedSize())
        }
        let title = setting.rowTitle
        let enabled = AdminAppLogic.controlEnabled(health: health, canEdit: canEdit, busy: model.save.isBusy)
        return AnyView(HStack(spacing: DS.Spacing.sm) {
            if model.save.isSaving(setting) { AdminAppSpinner() }
            Toggle(title, isOn: Binding(get: { isOn }, set: { model.request(setting, to: .flag($0)) }))
                .labelsHidden()
                .tint(DS.Color.toggleOn)
                .redacted(reason: AdminAppLogic.showsValue(health) ? [] : .placeholder)
                .disabled(!enabled)
                .accessibilityLabel(title)
        })
    }
}

/// صفّ اختيار بقائمة أصلية في الطرف («العربية ⌄»، «على الجميع ⌄») — القيمة الحالية بعلامة ✓ داخل القائمة
private struct AdminAppMenuRow: View {
    @ObservedObject var model: AdminAppAreaModel
    let setting: AdminAppSetting
    let icon: String
    let tint: Color
    var subtitle: String? = nil
    let options: [(value: String, title: String)]
    let current: String
    let health: AdminStoreHealth
    let canEdit: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AdminControlRow(icon: icon, tint: tint, title: setting.rowTitle, subtitle: subtitle, control: control)
            if model.save.hasFailed(setting) {
                AdminAppFailLine(busy: model.save.isBusy) { model.retry(setting) }
            }
        }
    }

    private var currentTitle: String {
        options.first { $0.value == current }?.title ?? current
    }

    private var control: AnyView {
        guard AdminAppLogic.showsValue(health) else {
            // قبل وصول القيمة: «—» (والفشل يقوله رأس بطاقة الحالة أو هذا الصفّ للقارئ الصوتي)
            return AnyView(Text(verbatim: AdminStoreHealthText.placeholder)
                .dsFont(.body)
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityLabel(health.canRetry ? AdminStoreHealthText.failed : AdminStoreHealthText.loading))
        }
        guard canEdit else {
            return AnyView(Text(verbatim: currentTitle)
                .dsFont(.body)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1))
        }
        let title = setting.rowTitle
        let enabled = AdminAppLogic.controlEnabled(health: health, canEdit: canEdit, busy: model.save.isBusy)
        return AnyView(Menu {
            Picker(selection: Binding(get: { current }, set: { value in
                guard value != current else { return }
                model.request(setting, to: .text(value))
            })) {
                ForEach(options.indices, id: \.self) { i in
                    Text(verbatim: options[i].title).tag(options[i].value)
                }
            } label: {
                EmptyView()
            }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                if model.save.isSaving(setting) { AdminAppSpinner() }
                Text(verbatim: currentTitle)
                    .dsFont(.body)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Image(systemName: "chevron.down")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityLabel(Text(verbatim: "\(title)، \(currentTitle)"))
        .accessibilityHint(L10n.t("يفتح الخيارات", "Opens the choices")))
    }
}

/// صفّ أحمر (إعادة ضبط العدّاد، استعادة الإعدادات الافتراضية): آخر بطاقته، يسأل أولاً، ودوّارة صغيرة أثناء التنفيذ
private struct AdminAppCommandRow: View {
    @ObservedObject var model: AdminAppAreaModel
    let setting: AdminAppSetting
    let icon: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.request(setting, to: nil) } label: {
                AdminListRow(icon: icon, title: setting.rowTitle, subtitle: subtitle, showsChevron: false,
                             destructive: true) {
                    if model.save.isSaving(setting) { AdminAppSpinner() }
                }
            }
            .buttonStyle(AdminRowPressStyle())
            .disabled(model.save.isBusy)
            .accessibilityHint(L10n.t("يسأل قبل التنفيذ", "Asks first"))
            if model.save.hasFailed(setting) {
                AdminAppFailLine(busy: model.save.isBusy) { model.retry(setting) }
            }
        }
    }
}

/// «لم يُحفظ. أعد المحاولة» تحت الصفّ — ١٣ أحمر، لمسه ٤٤، والضغط يعيد الطلب نفسه
private struct AdminAppFailLine: View {
    let busy: Bool
    let retry: () -> Void

    var body: some View {
        Button(action: retry) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "exclamationmark.circle.fill")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .accessibilityHidden(true)
                Text(AdminAppLogic.failedLine)
                    .dsFont(.subtitle)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundColor(DS.Color.error)
            .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .disabled(busy)
        .padding(.leading, AdminRowDivider.iconInset)
        .accessibilityHint(L10n.t("يعيد الحفظ", "Saves again"))
    }
}

/// دوّارة الحفظ الصغيرة داخل الصفّ (لا دوّارة صفحة)
private struct AdminAppSpinner: View {
    var body: some View {
        ProgressView()
            .scaleEffect(DS.Spinner.chipScale)
            .tint(DS.Color.textTertiary)
            .accessibilityLabel(AdminAppLogic.savingLabel)
    }
}
