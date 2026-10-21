import SwiftUI

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
            AdminBandHeader(title: AdminArea.app.title, subtitle: statusLine,
                            badge: canEdit ? nil : AdminPageHeader.readOnlyText, isAreaRoot: true)
        } content: {
            AnyView(AdminAppSettingsGroups(canEdit: canEdit))
        }
        // ما يُدفع من الصفوف يرجع باسم القسم
        .environment(\.adminPageTitle, AdminArea.app.title)
        .task { await appSettingsVM.fetchSettings() }
    }

    /// «الإصدار ٣٫٤ · وضع الصيانة مطفأ · آخر تعديل أمس»
    private var statusLine: String {
        let s = appSettingsVM.settings
        var parts = [L10n.t("الإصدار \(AppVersionText.short)", "Version \(AppVersionText.short)")]
        if s.updatedAt != nil {
            parts.append(s.maintenanceMode ? L10n.t("وضع الصيانة يعمل", "Maintenance on")
                                           : L10n.t("وضع الصيانة مطفأ", "Maintenance off"))
            if let when = AdminDeviceReachStore.date(s.updatedAt) {
                parts.append(L10n.t("آخر تعديل \(AppVersionText.relative(when))", "Last change \(AppVersionText.relative(when))"))
            }
        }
        return parts.joined(separator: " · ")
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
            group(L10n.t("إعدادات السيرفر", "Server settings")) {
                AnyView(NavigationLink { AdminRemoteSettingsView() } label: {
                    Label(L10n.t("القيم والنصوص من السيرفر", "Server values and text"), systemImage: "slider.horizontal.3")
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                })
            }
            group(L10n.t("القوائم", "Lists")) { AnyView(listsRows) }
            group(L10n.t("التعديلات الذاتية", "Self-edits")) { AnyView(selfEditRows) }
            if let days = appSettingsVM.settings.deathAlertDays {
                group(L10n.t("تنبيهات الإدارة", "Admin alerts")) {
                    AnyView(VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text(L10n.t("مدة تنبيه وفاة لم يُعلن عنها", "Unannounced death alert window"))
                            .dsFont(.hubRow)
                        Picker(L10n.t("المدة بالأيام", "Days"), selection: Binding(
                            get: { appSettingsVM.settings.deathAlertDays ?? days },
                            set: { value in
                                Task { await appSettingsVM.updateSetting("death_alert_days", value: value,
                                                                        updatedBy: authVM.currentUser?.id) }
                            })) {
                            ForEach(1...30, id: \.self) { value in
                                Text(L10n.t("\(value) يوم", "\(value) days")).tag(value)
                            }
                        }
                        .disabled(!canEdit || appSettingsVM.isSaving)
                        Text(L10n.t("يتحدث عند جلب الإعدادات بدون بناء جديد. مدة إتاحة إعلان الوفاة تبقى ٣٠ يومًا.",
                                    "Updates when settings refresh without a new build. Death announcements remain available for 30 days."))
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textSecondary)
                    })
                }
            }
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

    private var listsRows: some View {
        AdminRowsCardBody {
            AdminTapRow(icon: "tag.fill", tint: DS.Color.accent,
                        title: L10n.t("تصنيفات الأخبار والمكتبة", "News & library categories"),
                        subtitle: L10n.t("الاسم والأيقونة واللون، والإخفاء والترتيب", "Name, icon, colour, hide and order"),
                        tap: .page { AnyView(CategoriesManagerView()) })
            AdminTapRow(icon: "person.2.crop.square.stack.fill", tint: DS.Color.palm,
                        title: L10n.t("أسماء العوائل والفروع", "Family and branch names"),
                        subtitle: L10n.t("يختار منها العضو عائلته، وأسماء قائمة الفروع", "Members pick their family; branch list names"),
                        value: branchNamesCount > 0 ? L10n.t("\(branchNamesCount) فرع باسم", "\(branchNamesCount) named") : nil,
                        tap: .page { AnyView(AdminFamilyNamesView()) })
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
                            subtitle: L10n.t("3 تعديلات على الملف ثم بموافقة الإدارة — إيقاف الحدّ يسمح بلا عدد",
                                             "3 profile edits, then admin approval — pausing it allows unlimited edits"),
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
