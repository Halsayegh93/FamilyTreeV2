import SwiftUI

/// «التحديث الإجباري» — شاشة مستقلة في إعدادات النظام (طلب المالك).
/// لكل منصة أقل رقم بناء مسموح + رابط المتجر. أي نسخة أقل تنقفل بشاشة «حدّث التطبيق».
/// التعديل للمالك فقط؛ المدير يشوفها للقراءة.
/// التصميم («أسلوب واحد» ٢٠٢٦-١٠-٠٧): الرأس الملوّن الموحّد، صفّ أرقام بالحدّين ونسختك، ثم أقسام
/// `DSComposerSection` بصفوف `.dsRowBox()`.
struct AdminForceUpdateView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    @State private var iosURLDraft = ""
    @State private var androidURLDraft = ""
    @State private var messageDraft = ""

    private var canEdit: Bool { authVM.canManageSettings }
    private var s: AppSettings { appSettingsVM.settings }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                hero

                VStack(spacing: DS.Spacing.md) {
                    explainer

                    platformSection(
                        title: L10n.t("الآيفون", "iPhone"), icon: "apple.logo",
                        key: "ios_min_build", value: s.iosMinBuild ?? 0,
                        hint: L10n.t("نسختك الحالية: \(AppBuild.current)", "Your build: \(AppBuild.current)"),
                        urlTitle: L10n.t("رابط App Store / TestFlight", "App Store / TestFlight link"),
                        urlDraft: $iosURLDraft, urlKey: "ios_update_url",
                        index: 1
                    )

                    platformSection(
                        title: L10n.t("الأندرويد", "Android"), icon: "candybarphone",
                        key: "android_min_build", value: s.androidMinBuild ?? 0,
                        hint: L10n.t("رقم البناء (versionCode) لنسخة الأندرويد", "Android versionCode"),
                        urlTitle: L10n.t("رابط Google Play / التحميل", "Google Play / download link"),
                        urlDraft: $androidURLDraft, urlKey: "android_update_url",
                        index: 2
                    )

                    legacyAndroidSection
                    messageSection

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
                    .padding(.horizontal, DS.Spacing.xxs)
                }
                .disabled(!canEdit)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xxxl)
        }
        // الرأس الملوّن الموحّد (كان شريط النظام + بطاقة رأس)
        .dsSubPageHeader(L10n.t("التحديث الإجباري", "Force Update"),
                         subtitle: canEdit
                            ? L10n.t("أقل نسخة مسموحة لكل منصة — الأقدم تنقفل", "Minimum build per platform — older ones are blocked")
                            : L10n.t("للقراءة فقط — التعديل للمالك.", "Read only — the owner edits this."))
        .onAppear {
            iosURLDraft = s.iosUpdateUrl ?? ""
            androidURLDraft = s.androidUpdateUrl ?? ""
            messageDraft = s.updateMessage ?? ""
        }
        .task { await appSettingsVM.fetchSettings() }
    }

    // MARK: - بطاقة الرأس

    private func minLabel(_ value: Int?) -> String {
        let v = value ?? 0
        return v == 0 ? L10n.t("بلا", "Off") : "\(v)"
    }

    /// العنوان والوصف في الرأس الملوّن — الأرقام هنا
    private var hero: some View {
        DSStatsRow([
                DSHeroStat(value: minLabel(s.iosMinBuild), label: L10n.t("حد الآيفون", "iPhone min"), icon: "apple.logo"),
                DSHeroStat(value: minLabel(s.androidMinBuild), label: L10n.t("حد الأندرويد", "Android min"), icon: "candybarphone"),
                DSHeroStat(value: "\(AppBuild.current)", label: L10n.t("نسختك", "Your build"), icon: "iphone.gen3")
        ], tint: DS.Color.actionNavy)
    }

    // MARK: - الأقسام

    private var explainer: some View {
        DSNoteCard(canEdit
                   ? L10n.t("أي نسخة رقمها أقل من الحد تنقفل بشاشة «حدّث التطبيق» لين يحدّث العضو. 0 = بلا إجبار.",
                            "Any build below the minimum is blocked until the member updates. 0 = off.")
                   : L10n.t("للقراءة فقط — التعديل للمالك.", "Read only — the owner edits this."),
                   icon: canEdit ? "info.circle.fill" : "eye.fill")
            .dsStaggerIn(0)
    }

    private func platformSection(title: String, icon: String, key: String, value: Int, hint: String,
                                 urlTitle: String, urlDraft: Binding<String>, urlKey: String,
                                 index: Int) -> some View {
        DSComposerSection(title: title,
                          icon: icon,
                          tint: DS.Color.actionNavy,
                          trailing: value == 0 ? L10n.t("بلا إجبار", "Off") : L10n.t("مفعّل", "On"),
                          index: index) {
            // أقل رقم بناء مسموح
            DSRow(icon: "number", tint: value == 0 ? DS.Color.textTertiary : AppSection.admin.ink,
                   title: L10n.t("أقل رقم بناء", "Minimum build"),
                   subtitle: hint) {
                HStack(spacing: DS.Spacing.sm) {
                    Text(value == 0 ? L10n.t("بلا", "Off") : "\(value)")
                        .dsFont(.title)
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
            }

            // رابط المتجر
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
    private var legacyAndroidSection: some View {
        DSComposerSection(title: L10n.t("النسخ القديمة", "Legacy versions"),
                          icon: "clock.arrow.circlepath",
                          tint: DS.Color.actionNavy,
                          index: 3) {
            DSRow(icon: "candybarphone", tint: DS.Color.warning,
                   title: L10n.t("إيقاف نسخ الأندرويد القديمة", "Block old Android versions"),
                   subtitle: L10n.t("للنسخ المثبّتة قبل هذا التحديث — ما تعرف الحد الجديد",
                                    "For copies installed before this update")) {
                Toggle("", isOn: Binding(
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
                .accessibilityLabel(L10n.t("إيقاف نسخ الأندرويد القديمة", "Block old Android versions"))
            }
        }
    }

    private var messageSection: some View {
        DSComposerSection(title: L10n.t("رسالة شاشة التحديث (اختياري)", "Update screen message (optional)"),
                          icon: "text.bubble.fill",
                          tint: DS.Color.actionNavy,
                          index: 4) {
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

    /// «حفظ» — الشريحة الواحدة ممتلئة بتعبئة القسم (مساحة ضغط ٤٤)
    private func saveButton(_ action: @escaping () -> Void) -> some View {
        DSChipButton(L10n.t("حفظ", "Save"), isSelected: true, action: action)
    }

    private func save<T: Encodable>(_ key: String, _ value: T) {
        Task { await appSettingsVM.updateSetting(key, value: value, updatedBy: authVM.currentUser?.id) }
    }
}
