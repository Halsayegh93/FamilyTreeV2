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

/// شاشة حاجبة: النسخة قديمة ولازم تتحدّث — بعد موعد «إجباري من تاريخ»، أو «إجباري الحين»، أو تحت أقل نسخة مسموحة.
/// العنوان والرسالة و«ما الجديد» من السيرفر (`app_update_policy` ← «فرض التحديث» في الإدارة)، وإلا رسالة
/// `app_settings.update_message` ثم النص الافتراضي (قبل الترحيل). شكل المقترح المعتمد: كحلي، مربّع أيقونة ذهبي،
/// «ما الجديد» في بطاقة، و«افتح المتجر» ذهبي. المالكان لا يصلون هنا.
struct ForceUpdateView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var store = AppUpdateStore.shared
    @Environment(\.openURL) private var openURL
    @State private var checking = false

    private var policy: AppUpdatePolicy? { store.policy }

    private var updateURL: URL? { store.storeURL(fallback: appSettingsVM.settings.iosUpdateUrl) }

    private func clean(_ s: String?) -> String? {
        let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    private var title: String {
        clean(policy?.forceTitle) ?? L10n.t("حدّث التطبيق", "Update the App")
    }

    private var message: String {
        clean(policy?.forceMessage) ?? clean(appSettingsVM.settings.updateMessage) ?? L10n.t(
            "نسختك قديمة. حدّث من المتجر عشان تكمل استخدام تطبيق عائلة المحمدعلي.",
            "Your version is out of date. Update from the store to keep using the app.")
    }

    var body: some View {
        ForceUpdateContent(
            title: title, message: message, lines: policy?.whatsNew ?? [],
            onOpenStore: updateURL.map { url in { openURL(url) } },
            checking: checking,
            onCheck: {
                guard !checking else { return }
                checking = true
                Task {
                    await appSettingsVM.fetchSettings()
                    await store.refresh(force: true)
                    checking = false
                }
            })
        .task { await store.refresh(force: false) }
    }
}

/// وجه شاشة الإجبار — تستعمله الشاشة نفسها ومعاينة «ما الجديد» في الإدارة
struct ForceUpdateContent: View {
    let title: String
    let message: String
    let lines: [String]
    /// nil = بلا رابط متجر (الزرّ يختفي)
    let onOpenStore: (() -> Void)?
    var checking: Bool = false
    /// nil = بلا «تحقّق مرة ثانية» (المعاينة)
    var onCheck: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xl) {
                Spacer(minLength: DS.Spacing.xxl)

                AppUpdateIconTile(symbol: "iphone", onBand: true)

                VStack(spacing: DS.Spacing.sm) {
                    Text(title)
                        .dsFont(.emptyTitle)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .dsFont(.body)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                if !lines.isEmpty {
                    AppUpdateWhatsNewList(lines: lines, onBand: true)
                        .padding(DS.Spacing.lg)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            .fill(DS.Color.textOnPrimary.opacity(0.08)))
                }

                VStack(spacing: DS.Spacing.sm) {
                    if let onOpenStore {
                        DSButton(L10n.t("افتح المتجر", "Open the Store"), icon: "arrow.down.circle.fill", size: .large,
                                 tint: DS.Color.goldFill, action: onOpenStore)
                    }
                    if let onCheck {
                        Button(action: onCheck) {
                            Text(checking ? L10n.t("جاري التحقق…", "Checking…") : L10n.t("تحقّق مرة ثانية", "Check Again"))
                                .dsFont(.callout)
                                .foregroundColor(DS.Color.accentLight)
                                .frame(minHeight: DS.Icon.tapTarget)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(L10n.t("نسختك: \(AppBuild.versionLabel)", "Your version: \(AppBuild.versionLabel)"))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.accentLight)
                }
                .padding(.top, DS.Spacing.sm)

                Spacer(minLength: DS.Spacing.xxl)
            }
            .padding(.horizontal, DS.Spacing.xxl)
            .frame(maxWidth: .infinity)
            // وضع العرض: عمود قراءة متوسّط
            .dsLandscapeReadable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.gradientBand.ignoresSafeArea())
        .dsLightStatusBar()
    }
}
