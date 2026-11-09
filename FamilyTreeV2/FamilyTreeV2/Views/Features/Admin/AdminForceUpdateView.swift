import SwiftUI

/// «فرض التحديث» — يُفتح من «التطبيق ← التشغيل» (طلب المالك). من جديد بالمقترح المعتمد (samples/force-update،
/// ٢٠٢٦-١١-٠٧): لكل منصة (الآيفون · الأندرويد) آخر نسخة في المتجر، أقل نسخة مسموحة، ونوع التحديث للنسخ الأقدم من
/// الأخيرة (اختياري · إجباري من تاريخ · إجباري الحين) بموعده بتوقيت الكويت، و«لاحقاً» يرجع بعد كم يوم، ثم «ما الجديد
/// ونص الشاشة» و«النسخ عند الأعضاء» صفحتان. كله على السيرفر (`update_policy_admin` / `set_update_policy`).
/// قبل تطبيق الترحيل، ولغير المالك: الشكل السابق (أقل إصدار + الرابط + النسخ القديمة + الرسالة) كما كان.
struct AdminForceUpdateView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var store = AdminUpdatePolicyStore.shared

    // المسودات (الحفظ بزرّ واحد)
    @State private var ios = AdminUpdatePlatform()
    @State private var android = AdminUpdatePlatform()
    @State private var snoozeDays = 2
    @State private var baseline: AdminUpdatePolicy?
    @State private var alertText: String?
    @State private var savedMoment = false

    // الشكل السابق
    @State private var iosURLDraft = ""
    @State private var androidURLDraft = ""
    @State private var messageDraft = ""

    private var canEdit: Bool { authVM.canManageSettings }
    private var s: AppSettings { appSettingsVM.settings }
    private var isNew: Bool { canEdit && store.phase != .unavailable }

    private var dirty: Bool {
        guard let b = baseline else { return false }
        return !same(ios, b.ios) || !same(android, b.android) || snoozeDays != b.snoozeDays
    }

    private func same(_ a: AdminUpdatePlatform, _ b: AdminUpdatePlatform) -> Bool {
        a.latestBuild == b.latestBuild && a.minBuild == b.minBuild && a.mode == b.mode
            && a.latestVersion.trimmingCharacters(in: .whitespaces) == b.latestVersion
            && a.updateURL.trimmingCharacters(in: .whitespacesAndNewlines) == b.updateURL
            && (a.mode != .scheduled || a.deadline.map(AppUpdateDates.iso) == b.deadline.map(AppUpdateDates.iso))
    }

    var body: some View {
        AdminPage(header: header, lead: AnyView(explainer), content: isNew ? newCards : legacyCards)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .onAppear {
                iosURLDraft = s.iosUpdateUrl ?? ""
                androidURLDraft = s.androidUpdateUrl ?? ""
                messageDraft = s.updateMessage ?? ""
                if let p = store.policy { adopt(p) }
            }
            .task {
                await appSettingsVM.fetchSettings()
                if canEdit { await store.load() }
            }
            .onChange(of: store.policy) { p in
                if let p, !dirty { adopt(p) }
            }
            .dsAlert(L10n.t("لم يُحفظ", "Not saved"),
                     isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
                Button(L10n.t("حسناً", "OK")) {}
            } message: {
                Text(alertText ?? "")
            }
            .dsAlert(L10n.t("تم الحفظ", "Saved"), isPresented: $savedMoment, moment: .success) {
                Button(L10n.t("حسناً", "OK")) {}
            }
    }

    private func adopt(_ p: AdminUpdatePolicy) {
        ios = p.ios
        android = p.android
        snoozeDays = p.snoozeDays
        baseline = p
    }

    // MARK: - الرأس

    private func minLabel(_ value: Int?) -> String {
        let v = value ?? 0
        return v == 0 ? L10n.t("بلا", "Off") : "\(v)"
    }

    private var header: AdminPageHeader {
        if isNew {
            let ready = store.policy != nil
            return AdminPageHeader(
                title: L10n.t("فرض التحديث", "Force update"),
                subtitle: L10n.t("آخر نسخة ونوع التحديث لكل منصة", "Latest version and update type per platform"),
                glyph: "arrow.down.app.fill",
                kpis: [
                    AdminPageKPI(ready ? minLabel(ios.latestBuild) : "—", L10n.t("آخر آيفون", "Latest iPhone"), icon: "apple.logo"),
                    AdminPageKPI(ready ? minLabel(android.latestBuild) : "—", L10n.t("آخر أندرويد", "Latest Android"),
                                 icon: "candybarphone"),
                    AdminPageKPI("\(AppBuild.current)", L10n.t("نسختك", "Your build"), icon: "iphone.gen3")
                ])
        }
        let ready = s.updatedAt != nil
        return AdminPageHeader(
            title: L10n.t("فرض التحديث", "Force update"),
            subtitle: L10n.t("أدنى إصدار مسموح لكل منصة، والأقدم تُقفل", "Minimum allowed version per platform — older ones are blocked"),
            glyph: "arrow.down.app.fill",
            readOnly: !canEdit,
            kpis: [
                AdminPageKPI(ready ? minLabel(s.iosMinBuild) : "—", L10n.t("حد الآيفون", "iPhone min"), icon: "apple.logo",
                             tint: (s.iosMinBuild ?? 0) > 0 ? DS.Hub.kpiMine : DS.Color.textOnPrimary),
                AdminPageKPI(ready ? minLabel(s.androidMinBuild) : "—", L10n.t("حد الأندرويد", "Android min"),
                             icon: "candybarphone",
                             tint: (s.androidMinBuild ?? 0) > 0 ? DS.Hub.kpiMine : DS.Color.textOnPrimary),
                AdminPageKPI("\(AppBuild.current)", L10n.t("نسختك", "Your build"), icon: "iphone.gen3")
            ])
    }

    /// الشرح (يصعد فوق الرأس)
    private var explainer: some View {
        AdminSectionCard {
            if isNew {
                AdminInfoRow(icon: "info.circle.fill", tint: DS.Color.info,
                             title: L10n.t("كيف يعمل", "How it works"),
                             subtitle: L10n.t("نسخة أقدم من آخر نسخة: مربّع «يتوفر تحديث جديد» (اختياري)، أو مع عدّ تنازلي حتى الموعد ثم قفل، أو قفل فوري. أقل من أقل نسخة مسموحة = قفل دائماً.",
                                              "Older than the latest: an update box (optional), a countdown then a lock, or a lock now. Below the minimum = always locked."))
            } else {
                AdminInfoRow(icon: canEdit ? "info.circle.fill" : "eye.fill", tint: DS.Color.info,
                             title: canEdit ? L10n.t("كيف يعمل", "How it works") : AdminPageHeader.readOnlyText,
                             subtitle: L10n.t("أي نسخة رقمها أقل من الحد تُقفل بشاشة «حدّث التطبيق» حتى يحدّث العضو. 0 = بلا فرض.",
                                              "Any build below the minimum is blocked until the member updates. 0 = off."))
            }
        }
    }

    // MARK: - الشكل الجديد

    private var newCards: AnyView {
        switch store.phase {
        case .loading where store.policy == nil:
            return AnyView(AdminPageStateCard(.loading(L10n.t("جارٍ التحميل…", "Loading…"))))
        case .failed(let msg) where store.policy == nil:
            return AnyView(AdminPageStateCard(.error(L10n.t("تعذّر التحميل", "Couldn't load"), message: msg,
                                                     retry: { Task { await store.load() } })))
        default:
            break
        }
        return AnyView(VStack(spacing: DS.Hub.stackSpacing) {
            AdaptiveCardStack(spacing: DS.Hub.stackSpacing, alignment: .leading) {
                AnyView(AdminUpdatePlatformCard(
                    title: L10n.t("الآيفون", "iPhone"),
                    buildHint: L10n.t("رقم البناء في App Store — نسختك \(AppBuild.current)", "App Store build — yours is \(AppBuild.current)"),
                    urlTitle: L10n.t("رابط App Store / TestFlight", "App Store / TestFlight link"),
                    draft: $ios))
                AnyView(AdminUpdatePlatformCard(
                    title: L10n.t("الأندرويد", "Android"),
                    buildHint: L10n.t("رقم البناء (versionCode) في Google Play", "Google Play versionCode"),
                    urlTitle: L10n.t("رابط Google Play / التحميل", "Google Play / download link"),
                    draft: $android))
                AnyView(boxCard)
                AnyView(pagesCard)
                AnyView(legacyAndroidCard)
            }

            DSButton(L10n.t("حفظ", "Save"), icon: "checkmark", size: .large, isLoading: store.isSaving) { save() }
                .disabled(!dirty || store.isSaving)

            ownerNote
        })
    }

    /// المربّع عند العضو
    private var boxCard: some View {
        AdminSectionCard(title: L10n.t("مربّع التحديث", "Update box")) {
            AdminControlRow(icon: "clock.arrow.circlepath", tint: AppSection.admin.ink,
                            title: L10n.t("«لاحقاً» يعيد الإظهار بعد", "“Later” returns after"),
                            subtitle: L10n.t("يظهر مرة لكل نسخة، وفي آخر يوم قبل الموعد بلا «لاحقاً»",
                                             "Once per version; no “Later” on the last day before the deadline"),
                            control: AnyView(HStack(spacing: DS.Spacing.sm) {
                                Text(L10n.t("\(snoozeDays) يوم", "\(snoozeDays) d"))
                                    .dsFont(.statValue)
                                    .monospacedDigit()
                                    .foregroundColor(AppSection.admin.ink)
                                    .accessibilityHidden(true)
                                Stepper("", value: $snoozeDays, in: 1...30)
                                    .labelsHidden()
                                    .accessibilityLabel(L10n.t("«لاحقاً» يعيد الإظهار بعد", "“Later” returns after"))
                                    .accessibilityValue(L10n.t("\(snoozeDays) يوم", "\(snoozeDays) days"))
                            }
                            .fixedSize()))
        }
    }

    private var pagesCard: some View {
        AdminSectionCard(title: L10n.t("النصوص والأعضاء", "Texts and members")) {
            AdminRowsCardBody {
                AdminTapRow(icon: "text.badge.star", tint: AppSection.admin.ink,
                            title: L10n.t("ما الجديد ونص الشاشة", "What's new and screen text"),
                            subtitle: L10n.t("يظهر في المربّع وفي شاشة الإجبار مع معاينة", "Shown in the box and the lock screen — with preview"),
                            value: store.policy.map { "\($0.whatsNewLines.count)" },
                            tap: .page { AnyView(AdminUpdateWhatsNewView()) })
                AdminTapRow(icon: "iphone.and.arrow.forward", tint: AppSection.admin.ink,
                            title: L10n.t("النسخ عند الأعضاء", "Versions on members' devices"),
                            subtitle: L10n.t("من لا يزال على نسخة قديمة، وتذكيرهم بإشعار", "Who's still on an old version — and remind them"),
                            tap: .page { AnyView(AdminAppVersionsView()) })
            }
        }
    }

    private func save() {
        guard dirty else { return }
        var patch = AdminUpdatePolicyPatch()
        patch.ios = AdminUpdatePolicyPatch.platform(ios)
        patch.android = AdminUpdatePolicyPatch.platform(android)
        patch.snooze_days = snoozeDays
        Task {
            if let err = await store.save(patch) {
                alertText = err
            } else {
                if let p = store.policy { adopt(p) }
                await appSettingsVM.fetchSettings()
                savedMoment = true
            }
        }
    }

    // MARK: - الشكل السابق (قبل الترحيل، ولغير المالك)

    private var legacyCards: AnyView {
        AnyView(VStack(spacing: DS.Hub.stackSpacing) {
            // الوضع الأفقي: البطاقات على عمودين
            AdaptiveCardStack(spacing: DS.Hub.stackSpacing, alignment: .leading) {
                AnyView(platformCard(
                    title: L10n.t("الآيفون", "iPhone"), icon: "apple.logo",
                    key: "ios_min_build", value: s.iosMinBuild ?? 0,
                    hint: L10n.t("نسختك الحالية: \(AppBuild.current)", "Your build: \(AppBuild.current)"),
                    urlTitle: L10n.t("رابط App Store / TestFlight", "App Store / TestFlight link"),
                    urlDraft: $iosURLDraft, urlKey: "ios_update_url"
                ))
                AnyView(platformCard(
                    title: L10n.t("الأندرويد", "Android"), icon: "candybarphone",
                    key: "android_min_build", value: s.androidMinBuild ?? 0,
                    hint: L10n.t("رقم البناء (versionCode) لنسخة الأندرويد", "Android versionCode"),
                    urlTitle: L10n.t("رابط Google Play / التحميل", "Google Play / download link"),
                    urlDraft: $androidURLDraft, urlKey: "android_update_url"
                ))
                AnyView(legacyAndroidCard)
                AnyView(messageCard)
            }
            .disabled(!canEdit)

            ownerNote
        })
    }

    private func platformCard(title: String, icon: String, key: String, value: Int, hint: String,
                              urlTitle: String, urlDraft: Binding<String>, urlKey: String) -> some View {
        AdminSectionCard(title: title,
                         tag: value == 0 ? L10n.t("بلا فرض", "Off") : L10n.t("يعمل", "On")) {
            // أقل رقم بناء مسموح
            AdminControlRow(icon: "number", tint: value == 0 ? DS.Color.textTertiary : AppSection.admin.ink,
                            title: L10n.t("أقل إصدار مسموح", "Minimum allowed version"),
                            subtitle: hint,
                            control: AnyView(HStack(spacing: DS.Spacing.sm) {
                                Text(value == 0 ? L10n.t("بلا", "Off") : "\(value)")
                                    .dsFont(.statValue)
                                    .monospacedDigit()
                                    .foregroundColor(value == 0 ? DS.Color.textTertiary : AppSection.admin.ink)
                                    .frame(minWidth: DS.Icon.rowLarge)
                                    .accessibilityHidden(true)
                                Stepper("", value: Binding(
                                    get: { value },
                                    set: { save(key, max(0, $0)) }
                                ), in: 0...100_000)
                                .labelsHidden()
                                .accessibilityLabel(L10n.t("أقل إصدار مسموح — \(title)", "Minimum allowed version — \(title)"))
                                .accessibilityValue(value == 0 ? L10n.t("بلا", "Off") : "\(value)")
                            }
                            .fixedSize()))

            AdminUpdateURLField(title: urlTitle, text: urlDraft, onSave: {
                let v = urlDraft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                save(urlKey, v.isEmpty ? nil : v)
            })
        }
    }

    /// نسخ الأندرويد القديمة (قبل الحد لكل منصة) تقرأ force_update + latest_build فقط — يبقى كما هو في الشكلين
    private var legacyAndroidCard: some View {
        AdminSectionCard(title: L10n.t("النسخ القديمة", "Legacy versions")) {
            AdminControlRow(icon: "candybarphone", tint: DS.Color.warning,
                            title: L10n.t("إيقاف نسخ الأندرويد القديمة", "Block old Android versions"),
                            subtitle: L10n.t("للنسخ المثبّتة قبل الحد لكل منصة، لأنها لا تعرف الإعدادات الجديدة",
                                             "For copies installed before per-platform limits"),
                            control: AnyView(Toggle("", isOn: Binding(
                                get: { (s.forceUpdate ?? false) && (s.latestBuild ?? 0) > 1 },
                                set: { on in
                                    Task {
                                        await appSettingsVM.updateSetting("latest_build", value: on ? 2 : 0,
                                                                          updatedBy: authVM.currentUser?.id)
                                        await appSettingsVM.updateSetting("force_update", value: on,
                                                                          updatedBy: authVM.currentUser?.id)
                                    }
                                }
                            ))
                            .labelsHidden()
                            .tint(DS.Color.warning)
                            .disabled(!canEdit)
                            .accessibilityLabel(L10n.t("إيقاف نسخ الأندرويد القديمة", "Block old Android versions"))))
        }
    }

    private var messageCard: some View {
        AdminSectionCard(title: L10n.t("رسالة شاشة التحديث", "Update screen message"),
                         tag: L10n.t("اختياري", "Optional")) {
            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "text.quote", tint: DS.Color.actionNavy)
                    .accessibilityHidden(true)
                TextField(L10n.t("مثال: نسخة جديدة فيها حماية أكثر لبياناتك", "e.g. New version with better privacy"),
                          text: $messageDraft, axis: .vertical)
                    .dsFieldFont(.bodyCompact)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1...3)
                DSChipButton(L10n.t("حفظ", "Save"), isSelected: true) {
                    let v = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    save("update_message", v.isEmpty ? nil : v)
                }
            }
            .dsRowBox()
        }
    }

    /// المالك مستثنى من القفل
    private var ownerNote: some View {
        HStack(alignment: .top, spacing: DS.Spacing.xsm) {
            Image(systemName: "crown.fill")
                .dsGlyph(DS.Glyph.xs)
                .foregroundColor(DS.Color.textTertiary)
                .padding(.top, DS.Spacing.xxs)
                .accessibilityHidden(true)
            Text(L10n.t(
                "المالكان مستثنيان من القفل، حتى لا يُقفل عليهما التطبيق إذا رفعا الحد قبل تحديث أجهزتهما.",
                "Owners are exempt so you can't lock yourself out."
            ))
            .dsFont(.footnote)
            .foregroundColor(DS.Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.xs)
    }

    private func save<T: Encodable>(_ key: String, _ value: T) {
        Task { await appSettingsVM.updateSetting(key, value: value, updatedBy: authVM.currentUser?.id) }
    }
}

// MARK: - بطاقة منصة

/// آخر نسخة · أقل نسخة · اسم النسخة · نوع التحديث (+ الموعد) · رابط المتجر — كلها مسودة تُحفظ بـ«حفظ» الصفحة
private struct AdminUpdatePlatformCard: View {
    let title: String
    let buildHint: String
    let urlTitle: String
    @Binding var draft: AdminUpdatePlatform

    private var latest: Int { draft.latestBuild }

    var body: some View {
        AdminSectionCard(title: title, tag: tag) {
            AdminRowsCardBody {
                AdminControlRow(icon: "shippingbox.fill", tint: AppSection.admin.ink,
                                title: L10n.t("آخر نسخة في المتجر", "Latest in the store"),
                                subtitle: buildHint,
                                control: AnyView(AdminNumberField(value: $draft.latestBuild,
                                                                  label: L10n.t("آخر نسخة — \(title)", "Latest — \(title)"))))
                AdminControlRow(icon: "number", tint: draft.minBuild == 0 ? DS.Color.textTertiary : AppSection.admin.ink,
                                title: L10n.t("أقل نسخة مسموحة", "Minimum allowed"),
                                subtitle: L10n.t("أقل منها = إجباري دائماً · 0 = بلا", "Below it = always locked · 0 = off"),
                                control: AnyView(AdminNumberField(value: $draft.minBuild,
                                                                  label: L10n.t("أقل نسخة — \(title)", "Minimum — \(title)"))))
                AdminControlRow(icon: "tag.fill", tint: AppSection.admin.ink,
                                title: L10n.t("اسم النسخة", "Version name"),
                                subtitle: L10n.t("يظهر في المربّع، مثل 1.0.1", "Shown in the box — e.g. 1.0.1"),
                                control: AnyView(AdminShortField(text: $draft.latestVersion, placeholder: "1.0.1",
                                                                 label: L10n.t("اسم النسخة — \(title)", "Version name — \(title)"))))
            }

            if latest > 0 {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text(L10n.t("نوع التحديث للنسخ الأقدم من \(latest)", "Update type for builds older than \(latest)"))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                    DSSegmentedSwitch(options: AdminUpdatePlatform.Mode.allCases.map {
                        DSSegmentOption(id: $0, title: $0.title, icon: $0.icon)
                    }, selection: modeBinding, size: .regular)
                    modeDetail
                }
                .padding(.top, DS.Spacing.xs)
            } else {
                Text(L10n.t("يرجى إدخال رقم آخر نسخة ليظهر للأعضاء مربّع التحديث.",
                            "Enter the latest build to show members the update box."))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
            }

            AdminUpdateURLField(title: urlTitle, text: $draft.updateURL, onSave: nil)
        }
    }

    private var tag: String {
        guard latest > 0 else { return L10n.t("بلا مربّع", "No box") }
        return draft.mode.title
    }

    /// «إجباري من تاريخ» بلا موعد = بعد أسبوع الساعة ١٢ ص بتوقيت الكويت (يتغيّر من «الموعد»)
    private var modeBinding: Binding<AdminUpdatePlatform.Mode> {
        Binding(get: { draft.mode }, set: { mode in
            draft.mode = mode
            if mode == .scheduled, draft.deadline == nil {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = AppUpdateDates.kuwait
                let start = cal.startOfDay(for: Date())
                draft.deadline = cal.date(byAdding: .day, value: 7, to: start)
            }
        })
    }

    @ViewBuilder private var modeDetail: some View {
        switch draft.mode {
        case .optional:
            AdminUpdateNote(icon: "sparkles", text: L10n.t("مربّع «يتوفر تحديث جديد» مرة لكل نسخة، و«لاحقاً» يعيد إظهاره بعد الأيام المحددة.",
                                                         "An update box once per version; “Later” brings it back after the set days."))
        case .scheduled:
            AdminControlRow(icon: "calendar", tint: AppSection.admin.ink,
                            title: L10n.t("الموعد", "Deadline"),
                            subtitle: draft.deadline.map { AppUpdateDates.dayTimeLine($0) + L10n.t(" · بتوقيت الكويت", " · Kuwait time") },
                            control: AnyView(DatePicker("", selection: Binding(
                                get: { draft.deadline ?? Date() },
                                set: { draft.deadline = $0 }), displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .environment(\.timeZone, AppUpdateDates.kuwait)
                                .accessibilityLabel(L10n.t("الموعد", "Deadline"))))
            if let d = draft.deadline, d <= Date() {
                AdminUpdateNote(icon: "exclamationmark.triangle.fill",
                                text: L10n.t("انقضى الموعد، وتُقفل النسخ الأقدم مباشرة بعد الحفظ.",
                                             "The deadline has passed — older builds lock right after saving."),
                                tint: DS.Color.warning)
            }
        case .forced:
            AdminUpdateNote(icon: "lock.fill", text: L10n.t("كل نسخة أقدم من \(latest) تُقفل الآن بشاشة «حدّث التطبيق».",
                                                          "Every build older than \(latest) locks now."),
                            tint: DS.Color.warning)
        }
    }
}

/// سطر توضيح صغير بأيقونة
private struct AdminUpdateNote: View {
    let icon: String
    let text: String
    var tint: Color = DS.Color.info

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.xsm) {
            Image(systemName: icon)
                .dsGlyph(DS.Glyph.xs)
                .foregroundColor(tint.dsReadableGlyph)
                .padding(.top, DS.Spacing.xxs)
                .accessibilityHidden(true)
            Text(text)
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// حقل رقم البناء (أرقام فقط) — يكتب في المسودة مع كل حرف (لا ينتظر «تم»)
struct AdminNumberField: View {
    @Binding var value: Int
    let label: String

    var body: some View {
        TextField("0", text: Binding(
            get: { value == 0 ? "" : "\(value)" },
            set: { raw in
                let digits = String(raw.filter(\.isASCIIDigitOrArabic).prefix(9)).asciiDigits
                value = Int(digits) ?? 0
            }))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .dsFont(.statValue)
            .monospacedDigit()
            .foregroundColor(DS.Color.textPrimary)
            .frame(width: DS.Icon.sizeLg + DS.Spacing.xl)
            .padding(.vertical, DS.Spacing.xsm)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.fieldFill))
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityLabel(label)
    }
}

/// حقل نص قصير (اسم النسخة)
private struct AdminShortField: View {
    @Binding var text: String
    let placeholder: String
    let label: String

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .dsFieldFont(.bodyCompact)
            .foregroundColor(DS.Color.textPrimary)
            .frame(width: DS.Icon.sizeLg + DS.Spacing.xl)
            .padding(.vertical, DS.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.fieldFill))
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityLabel(label)
    }
}

/// رابط المتجر — حقل الكتابة الموحّد، و«حفظ» في الشكل السابق فقط
private struct AdminUpdateURLField: View {
    let title: String
    @Binding var text: String
    let onSave: (() -> Void)?

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "link", tint: DS.Color.actionNavy)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                TextField(title, text: $text)
                    .dsFieldFont(.bodyCompact)
                    .foregroundColor(DS.Color.textPrimary)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
            }
            if let onSave {
                DSChipButton(L10n.t("حفظ", "Save"), isSelected: true, action: onSave)
            }
        }
        .dsRowBox()
    }
}

private extension Character {
    var isASCIIDigitOrArabic: Bool { ("0"..."9").contains(self) || ("٠"..."٩").contains(self) }
}

private extension String {
    /// الأرقام العربية الهندية ← لاتينية
    var asciiDigits: String {
        String(map { c -> Character in
            if let v = "٠١٢٣٤٥٦٧٨٩".firstIndex(of: c) {
                return Character("\("٠١٢٣٤٥٦٧٨٩".distance(from: "٠١٢٣٤٥٦٧٨٩".startIndex, to: v))")
            }
            return c
        })
    }
}
