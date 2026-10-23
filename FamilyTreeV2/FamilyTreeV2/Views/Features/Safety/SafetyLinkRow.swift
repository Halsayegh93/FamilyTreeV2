import SwiftUI
import UIKit

// MARK: - صف رابط (يُستعمل في «عن التطبيق» و«الخصوصية والشروط»)

/// صف رابط بنفس صفوف المربّعات: أيقونة الحقل + عنوان + وصف + سهم
struct SafetyLinkRow: View {
    let icon: String
    var tint: Color = DS.Color.primary
    let title: String
    var subtitle: String? = nil
    /// رابط خارج التطبيق (المتصفح / البريد) — سهم مائل بدل سهم التنقّل
    var external: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: icon, tint: tint)
                    .accessibilityHidden(true)   // زخرفة
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title)
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    if let subtitle {
                        Text(subtitle)
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: DS.Spacing.xs)
                if external {
                    Image(systemName: "arrow.up.forward.square")
                        .dsGlyph(DS.Glyph.sm)
                        .foregroundColor(DS.Color.textTertiary)
                        .accessibilityHidden(true)
                } else {
                    DSChevron()
                }
            }
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityHint(external ? L10n.t("يفتح خارج التطبيق", "Opens outside the app") : "")
    }
}
