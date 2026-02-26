import SwiftUI

struct AdminDiwaniyaRequestsView: View {
    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: DS.Spacing.lg) {
                Image(systemName: "tent.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(DS.Color.gridDiwaniya)

                Text(L10n.t("طلبات الديوانيات", "Diwaniya Requests"))
                    .font(DS.Font.title3)
                    .foregroundColor(DS.Color.textPrimary)

                Text(L10n.t("سيتم عرض طلبات الديوانيات هنا عند توفر مصدر البيانات.", "Diwaniya review requests will appear here when the data source is available."))
                    .font(DS.Font.subheadline)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xl)
            }
            .padding(DS.Spacing.xxl)
            .glassCard(radius: DS.Radius.xl)
            .padding(.horizontal, DS.Spacing.lg)
        }
        .navigationTitle(L10n.t("طلبات الديوانيات", "Diwaniya Requests"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}
