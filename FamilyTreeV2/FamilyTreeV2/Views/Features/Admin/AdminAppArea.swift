import SwiftUI
import Supabase

// MARK: - «التطبيق» = الإعدادات نفسها، مجمّعة بمفاتيحها في مكانها (الدفعة ج من «نفّذ كل المقترح»، ٢٠٢٦-١٠-٢٠)
//
// كانت ٩ صفوف تفتح ٩ صفحات إعداد + «كل الإعدادات في صفحة واحدة» (تكررها كلها). صارت صفحة القسم هي الإعدادات (مثل
// «الإعدادات» في الآيفون) بخمس مجموعات تحت عناوين صغيرة — بلا تبويبات:
//   ١ الأقسام الظاهرة للأعضاء: لغة التطبيق (قائمة في مكانها) · الديوانيات · شجرة النساء · مشاريع العائلة · الاستطلاعات ·
//     اعتماد الأخبار قبل نشرها
//   ٢ القوائم: تصنيفات الأخبار والمكتبة › · أسماء العوائل والفروع ›
//   ٣ التعديلات الذاتية: حدّ التعديلات الذاتية + «إعادة ضبط العدّاد»
//   ٤ التشغيل: وضع الصيانة · فرض التحديث ›
//   ٥ النظام (تذييل): الإصدار، آخر تعديل للإعدادات، «استعادة الإعدادات الافتراضية» بالأحمر
// نفس المفاتيح والنداءات (`updateSetting`، `resetToDefaults`، `ProfileEditCooldown`) — المالك يعدّل، والمدير يقرأ بشارة
// «للاطلاع فقط — التعديل للمالك» والمفاتيح معطّلة. «شروط التسجيل» في «الفريق والأمان ← التسجيل والمنع»، و«إعدادات مسار
// الموافقات» في ⚙︎ «الوارد» (بيت كلٍّ منهما الوحيد).

struct AdminAppAreaPage: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    private var canEdit: Bool { authVM.canManageSettings }

    var body: some View {
        AdminHubPage {
            AdminBandHeader(title: AdminArea.app.title,
                            badge: canEdit ? nil : AdminPageHeader.readOnlyText, isAreaRoot: true)
        } content: {
            AnyView(AdminAppSettingsGroups(canEdit: canEdit))
        }
        // ما يُدفع من الصفوف يرجع باسم القسم
        .environment(\.adminPageTitle, AdminArea.app.title)
        .task { await appSettingsVM.fetchSettings() }
    }
}

/// نصوص الإصدار والوقت (مشتركة بين الرأس والتذييل)
enum AppVersionText {
    static var short: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    static var full: String { short + " (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))" }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func stamp(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}

/// المجموعات الخمس — نوع مستقل خلف `AnyView` (حارس المكدس)، وكل مجموعة بطاقة صفوف تحت عنوان صغير
private struct AdminAppSettingsGroups: View {
    let canEdit: Bool
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @State private var cooldownDisabled = ProfileEditCooldown.shared.isDisabled
    @State private var showReset = false
    @State private var showResetCooldown = false

    var body: some View {
        VStack(spacing: DS.Hub.stackSpacing) {
            group(L10n.t("الأقسام الظاهرة للأعضاء", "Sections members see")) { AnyView(sectionsRows) }
            // القوائم: مربّعان بالمنتصف (طلب المالك ٢٠٢٦-١٠-٢٤ «الايقونات بالمنتصف مع المسميات») — المفاتيح تبقى صفوفاً
            tilesGroup(L10n.t("القوائم", "Lists")) { AnyView(listsTiles) }
            group(L10n.t("التعديلات الذاتية", "Self-edits")) { AnyView(selfEditRows) }
            group(L10n.t("التشغيل", "Operations")) { AnyView(operationRows) }
            group(L10n.t("النظام", "System")) { AnyView(systemRows) }
        }
        .dsAlert(L10n.t("استعادة الإعدادات الافتراضية", "Restore default settings"), isPresented: $showReset) {
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            Button(L10n.t("استعادة", "Restore"), role: .destructive) {
                Task { await appSettingsVM.resetToDefaults(updatedBy: authVM.currentUser?.id) }
            }
        } message: {
            Text(L10n.t("ترجع كل الإعدادات للقيم الافتراضية.", "Every setting returns to its default value."))
        }
        .dsAlert(L10n.t("إعادة ضبط العدّاد", "Reset the counter"), isPresented: $showResetCooldown) {
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            Button(L10n.t("إعادة الضبط", "Reset"), role: .destructive) {
                ProfileEditCooldown.shared.resetAllCooldowns()
            }
        } message: {
            Text(L10n.t("تُصفَّر فترات الانتظار، ويقدر العضو يعدّل ملفه فوراً.",
                        "Waiting periods are cleared and members can edit their profile right away."))
        }
    }

    private func group(_ title: String, rows: () -> AnyView) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: title)
            VStack(alignment: .leading, spacing: 0) {
                rows()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .adminCard()
        }
    }

    // MARK: ١ الأقسام الظاهرة للأعضاء

    private var sectionsRows: some View {
        let s = appSettingsVM.settings
        return AdminRowsCardBody {
            AdminControlRow(icon: "character.bubble.fill", tint: DS.Color.primary,
                            title: L10n.t("لغة التطبيق", "App language"),
                            subtitle: L10n.t("لكل الأعضاء — من يختار لغته من «الإعدادات» تبقى لغته",
                                             "For everyone — anyone who picks a language in Settings keeps theirs"),
                            control: AnyView(languageControl))
            toggle("diwaniyas_enabled", icon: AppSection.diwaniyas.symbol, tint: AppSection.admin.ink,
                   title: L10n.t("الديوانيات", "Diwaniyas"),
                   subtitle: L10n.t("قسم الديوانيات للأعضاء", "The Diwaniyas section for members"),
                   isOn: s.diwaniyasEnabled ?? true)
            toggle("women_tree_enabled", icon: "person.2.fill", tint: DS.Color.female,
                   title: L10n.t("شجرة النساء", "Women's tree"),
                   subtitle: L10n.t("داخل قسم الشجرة", "Inside the Tree section"),
                   isOn: s.womenTreeEnabled ?? true)
            toggle("projects_enabled", icon: "briefcase.fill", tint: DS.Color.accent,
                   title: L10n.t("مشاريع العائلة", "Family projects"),
                   subtitle: L10n.t("في الرئيسية", "On Home"),
                   isOn: s.projectsEnabled ?? true)
            toggle("polls_enabled", icon: "chart.bar.fill", tint: DS.Color.info,
                   title: L10n.t("الاستطلاعات", "Polls"),
                   subtitle: L10n.t("استطلاع داخل الخبر", "A poll inside a news post"),
                   isOn: s.pollsEnabled ?? true)
            toggle("news_requires_approval", icon: "checkmark.shield.fill", tint: DS.Color.accent,
                   title: L10n.t("اعتماد الأخبار قبل نشرها", "Approve news before publishing"),
                   subtitle: L10n.t("أخبار الأعضاء تنتظر اعتماد الإدارة", "Members' posts wait for approval"),
                   isOn: s.newsRequiresApproval)
            AdminControlRow(icon: "eye.slash.fill", tint: AppSection.library.ink,
                            title: L10n.t("منع لقطة الشاشة في المكتبة", "Block screenshots in the library"),
                            subtitle: L10n.t("ملفات المكتبة تظهر فارغة في لقطة الشاشة وتسجيلها",
                                             "Library files show blank in screenshots and recordings"),
                            control: AnyView(LibraryPolicyControl(key: "library_screen_protection", fallback: "members",
                                                                  options: LibraryPolicyControl.shieldOptions, canEdit: canEdit)))
        }
    }

    /// قائمة أصلية في مكانها (العربية / English) — للمدير نصّ فقط
    @ViewBuilder
    private var languageControl: some View {
        let current = appSettingsVM.settings.defaultLanguage ?? "ar"
        let label = current == "ar" ? "العربية" : "English"
        if canEdit {
            Menu {
                Picker(selection: Binding(get: { current }, set: { value in
                    guard value != current else { return }
                    Task { await appSettingsVM.updateSetting("default_language", value: value, updatedBy: authVM.currentUser?.id) }
                })) {
                    Text(verbatim: "العربية").tag("ar")
                    Text(verbatim: "English").tag("en")
                } label: { EmptyView() }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: DS.Spacing.xxs) {
                    Text(verbatim: label).dsFont(.chip)
                    Image(systemName: "chevron.up.chevron.down").dsGlyph(DS.Glyph.xs, weight: .semibold)
                }
                .foregroundColor(DS.Color.accent)
                .frame(minHeight: DS.Icon.tapTarget)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.t("لغة التطبيق: \(label)", "App language: \(label)"))
        } else {
            AdminValueChip(text: label, tint: DS.Color.primary)
        }
    }

    // MARK: ٢ القوائم

    /// مجموعة مربّعات: العنوان الصغير ثم الشبكة (بلا بطاقة صفوف — كل مربّع بطاقته)
    private func tilesGroup(_ title: String, tiles: () -> AnyView) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: title)
            tiles()
        }
    }

    /// تصنيفات الأخبار والمكتبة · أسماء العوائل والفروع (وعدد الفروع المسمّاة تحت الاسم) — نفس الصفحتين ونفس الدفع.
    /// سطر الرقم محجوز في المربّعين معاً حين يوجد (طول واحد)، ولا فراغ له حين لا يوجد
    private var listsTiles: some View {
        let named = branchNamesCount > 0
        return AdminTileGrid(count: 2) {
            AdminTapWrap(tap: .page { AnyView(CategoriesManagerView()) }, feel: .tile, label: AnyView(
                AdminHubTile(icon: "tag.fill", fill: DS.Color.goldFill,
                             title: L10n.t("تصنيفات الأخبار والمكتبة", "News & library categories"),
                             reservesCaption: named, index: 0,
                             hint: L10n.t("الاسم والأيقونة واللون، والإخفاء والترتيب", "Name, icon, colour, hide and order"))))
            AdminTapWrap(tap: .page { AnyView(AdminFamilyNamesView()) }, feel: .tile, label: AnyView(
                AdminHubTile(icon: "person.2.crop.square.stack.fill", fill: DS.Color.palmFill,
                             title: L10n.t("أسماء العوائل والفروع", "Family and branch names"),
                             caption: named ? L10n.t("\(branchNamesCount) فرع باسم", "\(branchNamesCount) named") : nil,
                             reservesCaption: named, index: 1,
                             hint: L10n.t("يختار منها العضو عائلته، وأسماء قائمة الفروع", "Members pick their family; branch list names"))))
        }
    }

    private var branchNamesCount: Int {
        (appSettingsVM.settings.branchNames ?? [:]).values
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    // MARK: ٣ التعديلات الذاتية (العدّاد محلّي كما كان — `ProfileEditCooldown`)

    private var selfEditRows: some View {
        AdminRowsCardBody {
            AdminControlRow(icon: "timer", tint: DS.Color.info,
                            title: L10n.t("حدّ التعديلات الذاتية", "Self-edit limit"),
                            subtitle: L10n.t("3 تعديلات ثم بموافقة الإدارة", "3 edits, then admin approval"),
                            control: AnyView(
                                Toggle("", isOn: Binding(get: { !cooldownDisabled }, set: { on in
                                    cooldownDisabled = !on
                                    ProfileEditCooldown.shared.isDisabled = !on
                                }))
                                .labelsHidden()
                                .tint(AppSection.admin.ink)
                                .accessibilityLabel(L10n.t("حدّ التعديلات الذاتية", "Self-edit limit"))
                                .disabled(!canEdit)))
            AdminTapRow(icon: "arrow.counterclockwise.circle.fill", tint: DS.Color.warning,
                        title: L10n.t("إعادة ضبط العدّاد", "Reset the counter"),
                        subtitle: L10n.t("تصفير فترات الانتظار", "Clear the waiting periods"),
                        tap: canEdit ? .action { showResetCooldown = true } : .none)
        }
    }

    // MARK: ٤ التشغيل

    private var operationRows: some View {
        let s = appSettingsVM.settings
        return AdminRowsCardBody {
            toggle("maintenance_mode", icon: "wrench.and.screwdriver.fill", tint: DS.Color.error,
                   title: L10n.t("وضع الصيانة", "Maintenance mode"),
                   subtitle: L10n.t("يوقف التطبيق مؤقتاً للأعضاء — الإدارة تدخل", "Pauses the app for members — admins still get in"),
                   isOn: s.maintenanceMode)
            AdminTapRow(icon: "arrow.down.app.fill", tint: DS.Color.primary,
                        title: L10n.t("فرض التحديث", "Force update"),
                        subtitle: forceUpdateLine(s),
                        tap: .page { AnyView(AdminForceUpdateView()) })
        }
    }

    private func forceUpdateLine(_ s: AppSettings) -> String {
        func v(_ n: Int?) -> String { (n ?? 0) == 0 ? L10n.t("بلا", "off") : "\(n ?? 0)" }
        return L10n.t("أقل إصدار مسموح: آيفون \(v(s.iosMinBuild)) · أندرويد \(v(s.androidMinBuild))",
                      "Minimum allowed: iPhone \(v(s.iosMinBuild)) · Android \(v(s.androidMinBuild))")
    }

    // MARK: ٥ النظام

    private var systemRows: some View {
        let updated = AdminDeviceReachStore.date(appSettingsVM.settings.updatedAt)
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminRowsCardBody {
                AdminInfoRow(icon: "app.badge.fill", tint: DS.Color.primary, title: L10n.t("الإصدار", "Version"),
                             trailing: AnyView(AdminValueChip(text: AppVersionText.full, tint: DS.Color.primary)))
                AdminInfoRow(icon: "clock.fill", tint: DS.Color.primary, title: L10n.t("آخر تعديل للإعدادات", "Last settings change"),
                             trailing: AnyView(AdminValueChip(text: updated.map { AppVersionText.stamp($0) } ?? L10n.t("غير محدد", "N/A"),
                                                              tint: DS.Color.primary)))
            }
            DSButton(L10n.t("استعادة الإعدادات الافتراضية", "Restore default settings"), icon: "arrow.counterclockwise",
                     role: .destructive) { showReset = true }
                .disabled(!canEdit)
                .padding(.bottom, DS.Spacing.xs)
        }
    }

    // MARK: مفتاح في مكانه

    /// نفس الحفظ السابق (`updateSetting`) — المفتاح يتبع قيمة السيرفر بعد الحفظ
    private func toggle(_ key: String, icon: String, tint: Color, title: String, subtitle: String, isOn: Bool) -> some View {
        AdminControlRow(icon: icon, tint: tint, title: title, subtitle: subtitle, control: AnyView(
            Toggle("", isOn: Binding(get: { isOn }, set: { value in
                Task { await appSettingsVM.updateSetting(key, value: value, updatedBy: authVM.currentUser?.id) }
            }))
            .labelsHidden()
            .tint(AppSection.admin.ink)
            .accessibilityLabel(title)
            .disabled(!canEdit)))
    }
}


/// منع لقطة الشاشة في المكتبة من التطبيق (طلب المالك ٢٠٢٦-١٠-٢٩ «لقطة الشاشة على الكل»):
/// `app_config.library_screen_protection` — قائمة أصلية، والحفظ عبر `set_app_config` (المالك).
/// الحفظ والمشاركة لكل عنصر من قائمته في المكتبة (`family_archive.allow_share`)
private struct LibraryPolicyControl: View {
    let key: String
    let fallback: String
    let options: [(value: String, title: String)]
    let canEdit: Bool
    @ObservedObject private var config = AppConfigValues.shared
    @State private var saving = false
    @State private var error: String?

    static let shieldOptions: [(value: String, title: String)] = [
        ("all", L10n.t("على الجميع", "Everyone")),
        ("members", L10n.t("على الأعضاء فقط", "Members only")),
        ("off", L10n.t("مطفأ", "Off"))
    ]

    private struct Params: Encodable {
        let p_key: String
        let p_value: String
    }

    private var current: String { config.string(key) ?? fallback }
    private var label: String { options.first { $0.value == current }?.title ?? current }

    var body: some View {
        Group {
            if canEdit {
                Menu {
                    Picker(selection: Binding(get: { current }, set: { value in
                        guard value != current else { return }
                        Task { await save(value) }
                    })) {
                        ForEach(options, id: \.value) { Text(verbatim: $0.title).tag($0.value) }
                    } label: { EmptyView() }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: DS.Spacing.xxs) {
                        if saving { ProgressView().controlSize(.mini) }
                        Text(verbatim: label).dsFont(.chip)
                        Image(systemName: "chevron.up.chevron.down").dsGlyph(DS.Glyph.xs, weight: .semibold)
                    }
                    .foregroundColor(DS.Color.accent)
                    .frame(minHeight: DS.Icon.tapTarget)
                    .contentShape(Rectangle())
                }
                .disabled(saving)
                .accessibilityLabel(Text(verbatim: label))
            } else {
                AdminValueChip(text: label, tint: DS.Color.primary)
            }
        }
        .task { await config.refresh(force: true) }
        .dsAlert(L10n.t("تعذّر الحفظ", "Couldn't save"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func save(_ value: String) async {
        saving = true
        defer { saving = false }
        do {
            _ = try await SupabaseConfig.client.rpc("set_app_config", params: Params(p_key: key, p_value: value)).execute()
            await config.refresh(force: true)
        } catch {
            if ErrorHelper.isCancellation(error) { return }
            Log.warning("[CONFIG] تعذّر حفظ \(key): \(error.localizedDescription)")
            self.error = L10n.t("تأكد من الاتصال وجرّب مرة ثانية.", "Check the connection and try again.")
        }
    }
}
