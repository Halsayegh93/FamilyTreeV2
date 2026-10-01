import SwiftUI

/// «التحديث الإجباري» — شاشة مستقلة في إعدادات النظام (طلب المالك).
/// لكل منصة أقل رقم بناء مسموح + رابط المتجر. أي نسخة أقل تنقفل بشاشة «حدّث التطبيق».
/// التعديل للمالك فقط؛ المدير يشوفها للقراءة.
/// التصميم: بطاقة رأس بالحدّين ونسختك، ثم أقسام `DSComposerSection` بصفوف `.dsRowBox()`.
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

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(DS.Color.textTertiary)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                        Text(L10n.t(
                            "المالك مستثنى من القفل حتى ما يقفل نفسه لو رفع الحد قبل ما يحدّث جهازه.",
                            "The owner is exempt so you can't lock yourself out."
                        ))
                        .font(DS.Font.plex(11))
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 2)
                }
                .disabled(!canEdit)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xxxl)
        }
        .background(DS.Color.background)
        .navigationTitle(L10n.t("التحديث الإجباري", "Force Update"))
        .navigationBarTitleDisplayMode(.inline)
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

    private var hero: some View {
        DSPageHero(
            title: L10n.t("التحديث الإجباري", "Force Update"),
            subtitle: canEdit
                ? L10n.t("أقل نسخة مسموحة لكل منصة — الأقدم تنقفل", "Minimum build per platform — older ones are blocked")
                : L10n.t("للقراءة فقط — التعديل للمالك.", "Read only — the owner edits this."),
            icon: "arrow.down.app.fill",
            tint: DS.Color.actionNavy,
            stats: [
                DSHeroStat(value: minLabel(s.iosMinBuild), label: L10n.t("حد الآيفون", "iPhone min"), icon: "apple.logo"),
                DSHeroStat(value: minLabel(s.androidMinBuild), label: L10n.t("حد الأندرويد", "Android min"), icon: "candybarphone"),
                DSHeroStat(value: "\(AppBuild.current)", label: L10n.t("نسختك", "Your build"), icon: "iphone.gen3")
            ]
        )
    }

    // MARK: - الأقسام

    private var explainer: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            DSFieldIcon(name: canEdit ? "info.circle.fill" : "eye.fill", tint: DS.Color.primary)
                .accessibilityHidden(true)
            Text(canEdit
                 ? L10n.t("أي نسخة رقمها أقل من الحد تنقفل بشاشة «حدّث التطبيق» لين يحدّث العضو. 0 = بلا إجبار.",
                          "Any build below the minimum is blocked until the member updates. 0 = off.")
                 : L10n.t("للقراءة فقط — التعديل للمالك.", "Read only — the owner edits this."))
                .font(DS.Font.plex(12))
                .foregroundColor(DS.Color.fieldValue)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Spacing.md)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .fill(DS.Color.primary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(DS.Color.primary.opacity(0.20), lineWidth: 1))
        .accessibilityElement(children: .combine)
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
            SysRow(icon: "number", tint: value == 0 ? DS.Color.textTertiary : DS.Color.primary,
                   title: L10n.t("أقل رقم بناء", "Minimum build"),
                   subtitle: hint) {
                HStack(spacing: DS.Spacing.sm) {
                    Text(value == 0 ? L10n.t("بلا", "Off") : "\(value)")
                        .font(DS.Font.plex(17, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(value == 0 ? DS.Color.textTertiary : DS.Color.primary)
                        .frame(minWidth: 36)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(urlTitle)
                        .font(DS.Font.plex(12, weight: .heavy))
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    TextField(urlTitle, text: urlDraft)
                        .font(DS.Font.plex(13.5))
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
            SysRow(icon: "candybarphone", tint: DS.Color.warning,
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
                    .font(DS.Font.plex(13.5))
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

    /// زر «حفظ» صغير كحلي — مساحة ضغط ٤٤ نقطة
    private func saveButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(L10n.t("حفظ", "Save"))
                .font(DS.Font.plex(13, weight: .bold))
                .foregroundColor(DSActionFill.label(enabled: canEdit))
                .padding(.horizontal, DS.Spacing.md)
                .frame(height: 32)
                .background(DSActionFill.style(enabled: canEdit), in: Capsule())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    private func save<T: Encodable>(_ key: String, _ value: T) {
        Task { await appSettingsVM.updateSetting(key, value: value, updatedBy: authVM.currentUser?.id) }
    }
}
