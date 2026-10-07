import SwiftUI

/// رقم بناء النسخة المثبّتة (CFBundleVersion) — يُقارن بـ app_settings.ios_min_build
enum AppBuild {
    static var current: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }
    static var versionLabel: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "\(v) (\(current))"
    }
}

/// شاشة حاجبة: النسخة قديمة ولازم تتحدّث (يتحكم فيها المالك من «إعدادات التطبيق»)
struct ForceUpdateView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @Environment(\.openURL) private var openURL

    private var updateURL: URL? {
        guard let raw = appSettingsVM.settings.iosUpdateUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    /// رسالة المالك من «التحديث الإجباري» — وإلا النص الافتراضي
    private var customMessage: String? {
        let m = appSettingsVM.settings.updateMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return m.isEmpty ? nil : m
    }

    var body: some View {
        VStack(spacing: DS.Spacing.xxl) {
            Spacer()

            // قرص الحالة المجسّم الكبير (نفس شاشات التجميد وحد الأجهزة)
            DSStateIcon("arrow.down.app.fill", tint: DS.Color.primary, size: DS.Icon.stateHero)
                .accessibilityHidden(true)

            Text(L10n.t("حدّث التطبيق", "Update the App"))
                .dsFont(.emptyTitle)
                .foregroundColor(DS.Color.textPrimary)

            Text(customMessage ?? L10n.t(
                "صدرت نسخة جديدة من التطبيق فيها تحسينات وإصلاحات مهمة. حدّث التطبيق حتى تكمل استخدامه.",
                "A new version with important improvements and fixes is available. Please update to continue."
            ))
            .dsFont(.body)
            .foregroundColor(DS.Color.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DS.Spacing.xl)

            Text(L10n.t("نسختك: \(AppBuild.versionLabel)", "Your version: \(AppBuild.versionLabel)"))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)

            Spacer()

            if let url = updateURL {
                DSPrimaryButton(L10n.t("تحديث الآن", "Update Now"), icon: "arrow.down.circle.fill") {
                    openURL(url)
                }
            }

            DSSecondaryButton(L10n.t("تحقّق مرة ثانية", "Check Again"), icon: "arrow.clockwise") {
                Task { await appSettingsVM.fetchSettings() }
            }
        }
        .padding(DS.Spacing.xxl)
        // وضع العرض: عمود قراءة متوسّط، ويتمرّر بدل أن يُقصّ النص
        .dsLandscapeReadable()
        .dsLandscapeScroll()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.background)
    }
}
