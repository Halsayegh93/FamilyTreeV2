import SwiftUI

// MARK: - OfflineBanner
// بانر يظهر عند فقدان الاتصال بالإنترنت

struct OfflineBanner: View {
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @State private var isVisible = false

    var body: some View {
        if !networkMonitor.isConnected {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 14, weight: .semibold))

                Text(L10n.t("لا يوجد اتصال بالإنترنت", "No Internet Connection"))
                    .font(DS.Font.caption1)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                Capsule()
                    .fill(DS.Color.warning.gradient)
            )
            .shadow(color: DS.Color.warning.opacity(0.3), radius: 8, y: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear { withAnimation(DS.Anim.snappy) { isVisible = true } }
        }
    }
}
