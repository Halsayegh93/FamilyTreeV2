import SwiftUI

/// «التحديث الإجباري» — شاشة مستقلة في إعدادات النظام (طلب المالك).
/// لكل منصة أقل رقم بناء مسموح + رابط المتجر. أي نسخة أقل تنقفل بشاشة «حدّث التطبيق».
/// التعديل للمالك فقط؛ المدير يشوفها للقراءة.
/// التصميم بشكل «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠، `AdminPageKit`): رأس كحلي بالحدّين ونسختك (وشارة «للقراءة» لغير
/// المالك) ← بطاقة الشرح تصعد فوقه ← بطاقة لكل منصة (أقل رقم بناء بعدّاده، ورابط المتجر بحقله و«حفظ») ← النسخ القديمة ←
/// رسالة شاشة التحديث. نفس الحفظ والتعطيل لغير المالك تماماً.
struct AdminForceUpdateView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    @State private var iosURLDraft = ""
    @State private var androidURLDraft = ""
    @State private var messageDraft = ""

    private var canEdit: Bool { authVM.canManageSettings }
    private var s: AppSettings { appSettingsVM.settings }

    var body: some View {
        AdminPage(header: header, lead: AnyView(explainer), content: cards)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .onAppear {
                iosURLDraft = s.iosUpdateUrl ?? ""
                androidURLDraft = s.androidUpdateUrl ?? ""
                messageDraft = s.updateMessage ?? ""
            }
            .task { await appSettingsVM.fetchSettings() }
    }

    // MARK: - الرأس

    private func minLabel(_ value: Int?) -> String {
        let v = value ?? 0
        return v == 0 ? L10n.t("بلا", "Off") : "\(v)"
    }

    /// الحدّان ونسختك — «—» قبل وصول الإعدادات من السيرفر (القيم الافتراضية بلا تاريخ تحديث)
    private var header: AdminPageHeader {
        let ready = s.updatedAt != nil
        return AdminPageHeader(
            title: L10n.t("التحديث الإجباري", "Force Update"),
            subtitle: L10n.t("أقل نسخة مسموحة لكل منصة — الأقدم تنقفل", "Minimum build per platform — older ones are blocked"),
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

    // MARK: - البطاقات

    /// الشرح (يصعد فوق الرأس) — القاعدة نفسها، ولغير المالك سطر «للقراءة» كما كان
    private var explainer: some View {
        AdminSectionCard {
            AdminInfoRow(icon: canEdit ? "info.circle.fill" : "eye.fill", tint: DS.Color.info,
                         title: canEdit ? L10n.t("كيف يعمل", "How it works")
                                        : L10n.t("للقراءة فقط — التعديل للمالك.", "Read only — the owner edits this."),
                         subtitle: L10n.t("أي نسخة رقمها أقل من الحد تنقفل بشاشة «حدّث التطبيق» لين يحدّث العضو. 0 = بلا إجبار.",
                                          "Any build below the minimum is blocked until the member updates. 0 = off."))
        }
    }

    private var cards: AnyView {
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
                         tag: value == 0 ? L10n.t("بلا إجبار", "Off") : L10n.t("مفعّل", "On")) {
            // أقل رقم بناء مسموح
            AdminControlRow(icon: "number", tint: value == 0 ? DS.Color.textTertiary : AppSection.admin.ink,
                            title: L10n.t("أقل رقم بناء", "Minimum build"),
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
                                .accessibilityLabel(L10n.t("أقل رقم بناء — \(title)", "Minimum build — \(title)"))
                                .accessibilityValue(value == 0 ? L10n.t("بلا", "Off") : "\(value)")
                            }
                            .fixedSize()))

            // رابط المتجر — حقل كتابة (صندوق الحقل الموحّد) و«حفظ»
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "link", tint: DS.Color.actionNavy)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(urlTitle)
                        .dsFieldFont(.label)
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    TextField(urlTitle, text: urlDraft)
                        .dsFieldFont(.bodyCompact)
                        .foregroundColor(DS.Color.textPrimary)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                }
                saveButton {
                    let v = urlDraft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    save(urlKey, v.isEmpty ? nil : v)
                }
            }
            .dsRowBox()
        }
    }

    /// نسخ الأندرويد القديمة (قبل هذا التحديث) تقرأ force_update + latest_build فقط
    private var legacyAndroidCard: some View {
        AdminSectionCard(title: L10n.t("النسخ القديمة", "Legacy versions")) {
            AdminControlRow(icon: "candybarphone", tint: DS.Color.warning,
                            title: L10n.t("إيقاف نسخ الأندرويد القديمة", "Block old Android versions"),
                            subtitle: L10n.t("للنسخ المثبّتة قبل هذا التحديث — ما تعرف الحد الجديد",
                                             "For copies installed before this update"),
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
                saveButton {
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
                "المالك مستثنى من القفل حتى ما يقفل نفسه لو رفع الحد قبل ما يحدّث جهازه.",
                "The owner is exempt so you can't lock yourself out."
            ))
            .dsFont(.footnote)
            .foregroundColor(DS.Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.xs)
    }

    /// «حفظ» — الشريحة الواحدة ممتلئة بتعبئة القسم (مساحة ضغط ٤٤)
    private func saveButton(_ action: @escaping () -> Void) -> some View {
        DSChipButton(L10n.t("حفظ", "Save"), isSelected: true, action: action)
    }

    private func save<T: Encodable>(_ key: String, _ value: T) {
        Task { await appSettingsVM.updateSetting(key, value: value, updatedBy: authVM.currentUser?.id) }
    }
}
