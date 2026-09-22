import SwiftUI

// «صحة النظام» لم تعد قسماً مستقلاً (طلب المالك): «النشاط الآن» و«الإشعارات»
// صارا مربّعين في «إعدادات النظام ← الإدارة»، و«مهام السيرفر» أُزيلت من التطبيق.
// (المهام المجدولة على السيرفر نفسها تعمل كما هي.)

/// عنوان موحّد أعلى صفحات المتابعة (النشاط، الإشعارات، الأجهزة)
struct SystemHealthSectionHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title).font(DS.Font.title1).foregroundStyle(DS.Color.textPrimary)
            Text(subtitle).font(DS.Font.footnote).foregroundStyle(DS.Color.textSecondary)
        }
    }
}
