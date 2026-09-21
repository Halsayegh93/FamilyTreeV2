import SwiftUI

/// «التحديث الإجباري» — شاشة مستقلة في إعدادات النظام (طلب المالك).
/// لكل منصة أقل رقم بناء مسموح + رابط المتجر. أي نسخة أقل تنقفل بشاشة «حدّث التطبيق».
/// التعديل للمالك فقط؛ المدير يشوفها للقراءة.
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
                explainer

                platformCard(
                    title: L10n.t("الآيفون", "iPhone"), icon: "apple.logo",
                    key: "ios_min_build", value: s.iosMinBuild ?? 0,
                    hint: L10n.t("نسختك الحالية: \(AppBuild.current)", "Your build: \(AppBuild.current)"),
                    urlTitle: L10n.t("رابط App Store / TestFlight", "App Store / TestFlight link"),
                    urlDraft: $iosURLDraft, urlKey: "ios_update_url"
                )

                platformCard(
                    title: L10n.t("الأندرويد", "Android"), icon: "candybarphone",
                    key: "android_min_build", value: s.androidMinBuild ?? 0,
                    hint: L10n.t("رقم البناء (versionCode) لنسخة الأندرويد", "Android versionCode"),
                    urlTitle: L10n.t("رابط Google Play / التحميل", "Google Play / download link"),
                    urlDraft: $androidURLDraft, urlKey: "android_update_url"
                )

                legacyAndroidCard
                messageCard

                Text(L10n.t(
                    "المالك مستثنى من القفل حتى ما يقفل نفسه لو رفع الحد قبل ما يحدّث جهازه.",
                    "The owner is exempt so you can't lock yourself out."
                ))
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Spacing.lg)
            }
            .padding(.vertical, DS.Spacing.lg)
            .disabled(!canEdit)
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

    private var explainer: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(DS.Color.info)
            Text(canEdit
                 ? L10n.t("أي نسخة رقمها أقل من الحد تنقفل بشاشة «حدّث التطبيق» لين يحدّث العضو. 0 = بلا إجبار.",
                          "Any build below the minimum is blocked until the member updates. 0 = off.")
                 : L10n.t("للقراءة فقط — التعديل للمالك.", "Read only — the owner edits this."))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.info.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func platformCard(title: String, icon: String, key: String, value: Int, hint: String,
                              urlTitle: String, urlDraft: Binding<String>, urlKey: String) -> some View {
        DSCard(padding: DS.Spacing.lg) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(spacing: DS.Spacing.md) {
                    Image(systemName: icon)
                        .font(DS.Font.scaled(18, weight: .semibold))
                        .foregroundColor(DS.Color.primary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(DS.Font.calloutBold).foregroundColor(DS.Color.textPrimary)
                        Text(hint).font(DS.Font.caption2).foregroundColor(DS.Color.textTertiary)
                    }
                    Spacer()
                    Text(value == 0 ? L10n.t("بلا", "Off") : "\(value)")
                        .font(DS.Font.plex(18, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(value == 0 ? DS.Color.textTertiary : DS.Color.primary)
                        .frame(minWidth: 40)
                    Stepper("", value: Binding(
                        get: { value },
                        set: { save(key, max(0, $0)) }
                    ), in: 0...100_000)
                    .labelsHidden()
                }

                HStack(spacing: DS.Spacing.sm) {
                    TextField(urlTitle, text: urlDraft)
                        .font(DS.Font.caption1)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                        .padding(DS.Spacing.sm)
                        .background(DS.Color.mutedBackground, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                    Button(L10n.t("حفظ", "Save")) {
                        let v = urlDraft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        save(urlKey, v.isEmpty ? nil : v)
                    }
                    .font(DS.Font.calloutBold)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    /// نسخ الأندرويد القديمة (قبل هذا التحديث) تقرأ force_update + latest_build فقط
    private var legacyAndroidCard: some View {
        DSCard(padding: DS.Spacing.lg) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Toggle(isOn: Binding(
                    get: { (s.forceUpdate ?? false) && (s.latestBuild ?? 0) > 1 },
                    set: { on in
                        Task {
                            await appSettingsVM.updateSetting("latest_build", value: on ? 2 : 0,
                                                              updatedBy: authVM.currentUser?.id)
                            await appSettingsVM.updateSetting("force_update", value: on,
                                                              updatedBy: authVM.currentUser?.id)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("إيقاف نسخ الأندرويد القديمة", "Block old Android versions"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(L10n.t("للنسخ المثبّتة قبل هذا التحديث — ما تعرف الحد الجديد",
                                    "For copies installed before this update"))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
                .tint(DS.Color.warning)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private var messageCard: some View {
        DSCard(padding: DS.Spacing.lg) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text(L10n.t("رسالة شاشة التحديث (اختياري)", "Update screen message (optional)"))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                HStack(spacing: DS.Spacing.sm) {
                    TextField(L10n.t("مثال: نسخة جديدة فيها حماية أكثر لبياناتك", "e.g. New version with better privacy"),
                              text: $messageDraft, axis: .vertical)
                        .font(DS.Font.caption1)
                        .lineLimit(1...3)
                        .padding(DS.Spacing.sm)
                        .background(DS.Color.mutedBackground, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                    Button(L10n.t("حفظ", "Save")) {
                        let v = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        save("update_message", v.isEmpty ? nil : v)
                    }
                    .font(DS.Font.calloutBold)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func save<T: Encodable>(_ key: String, _ value: T) {
        Task { await appSettingsVM.updateSetting(key, value: value, updatedBy: authVM.currentUser?.id) }
    }
}
