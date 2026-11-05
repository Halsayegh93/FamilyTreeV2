import SwiftUI
import UIKit

/// أيقونات التطبيق البديلة (طلب المالك ٢٠٢٦-١٠-٣١): الأساسية تتبع وضع الجوال (فاتح: كحلي على كريمي، داكن: كريمي على كحلي، زجاجي/ملوّن: شعار أبيض)، والبقية ألوان الهوية.
/// `iconName` = اسم مجموعة الأيقونة في Assets (`nil` للأساسية)، والمعاينة من `IconPreview-<key>`.
struct AppIconChoice: Identifiable, Equatable {
    let id: String
    let iconName: String?
    let titleAr: String
    let titleEn: String

    var title: String { L10n.t(titleAr, titleEn) }
    var preview: String { "IconPreview-\(id)" }

    static let all: [AppIconChoice] = [
        AppIconChoice(id: "Main", iconName: nil, titleAr: "الأساسية", titleEn: "Classic"),
        AppIconChoice(id: "NavyGold", iconName: "AppIcon-NavyGold", titleAr: "كحلي وذهبي", titleEn: "Navy & gold"),
        AppIconChoice(id: "Black", iconName: "AppIcon-Black", titleAr: "أسود", titleEn: "Black")
    ]

    /// الأيقونة المختارة على الجهاز الآن
    @MainActor static var current: AppIconChoice {
        let name = UIApplication.shared.alternateIconName
        return all.first { $0.iconName == name } ?? all[0]
    }
}

/// مربّع «أيقونة التطبيق» في الإعدادات — يغيّر أيقونة الشاشة الرئيسية على هذا الجهاز
struct AppIconSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var langManager = LanguageManager.shared
    @State private var selected: AppIconChoice = AppIconChoice.current
    @State private var failed = false

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.md), count: 3)

    var body: some View {
        DSComposer(
            title: t("أيقونة التطبيق", "App Icon"),
            subtitle: t("شكل التطبيق على شاشة جوالك", "How the app looks on your home screen"),
            icon: "apps.iphone",
            tint: DS.Color.primary,
            actionTitle: "",
            showsAction: false,
            cancelTitle: t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { dismiss() }
        ) {
            DSComposerSection(title: t("الأيقونات", "Icons"), icon: "square.grid.2x2.fill",
                              tint: DS.Color.primary, index: 0) {
                VStack(spacing: DS.Spacing.md) {
                    LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                        ForEach(AppIconChoice.all) { choice in
                            iconTile(choice)
                        }
                    }
                    Text(failed
                         ? t("تعذّر تغيير الأيقونة، حاول مرة ثانية.", "Couldn't change the icon. Try again.")
                         : t("تتغير الأيقونة على هذا الجهاز فقط.", "The icon changes on this device only."))
                        .dsFont(.footnote)
                        .foregroundColor(failed ? DS.Color.error : DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .environment(\.layoutDirection, langManager.layoutDirection)
    }

    private func iconTile(_ choice: AppIconChoice) -> some View {
        let isOn = choice == selected
        return Button {
            apply(choice)
        } label: {
            VStack(spacing: DS.Spacing.xs) {
                Image(choice.preview)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .stroke(isOn ? DS.Color.accent : DS.Color.cardBorder,
                                lineWidth: isOn ? DS.Border.width * 3 : DS.Border.width))
                    .overlay(alignment: .topTrailing) {
                        if isOn {
                            Image(systemName: "checkmark.circle.fill")
                                .dsGlyph(DS.Glyph.md)
                                .foregroundStyle(DS.Color.textOnPrimary, DS.Color.accent)
                                .padding(DS.Spacing.xs)
                        }
                    }
                Text(choice.title)
                    .dsFont(.micro)
                    .foregroundColor(isOn ? DS.Color.textPrimary : DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func apply(_ choice: AppIconChoice) {
        guard choice != selected, UIApplication.shared.supportsAlternateIcons else { return }
        let previous = selected
        selected = choice
        failed = false
        UIApplication.shared.setAlternateIconName(choice.iconName) { error in
            guard let error else { return }
            Log.warning("[ICON] تعذّر تغيير الأيقونة: \(error.localizedDescription)")
            Task { @MainActor in
                selected = previous
                failed = true
            }
        }
    }
}
