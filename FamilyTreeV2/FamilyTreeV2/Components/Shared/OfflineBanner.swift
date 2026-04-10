import SwiftUI

// MARK: - OfflineBanner
// بانر يظهر عند فقدان الاتصال — يختفي بعد 3 ثوانٍ ويرجع عند تغيير الشاشة
// + بانر أخضر عند رجوع الاتصال

struct OfflineBanner: View {
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @State private var showBanner = false
    @State private var showReconnected = false
    @State private var wasDisconnected = false
    @State private var hideTask: Task<Void, Never>?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        // بانر انقطاع الاتصال
        if !networkMonitor.isConnected && showBanner {
            bannerView(
                icon: "wifi.slash",
                title: L10n.t("لا يوجد اتصال", "No Connection"),
                subtitle: L10n.t("تقدر تتصفح البيانات المحفوظة مؤقتاً", "You can browse cached data offline"),
                color: DS.Color.error
            )
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height < 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height < -30 {
                            withAnimation(DS.Anim.snappy) { showBanner = false }
                            hideTask?.cancel()
                        }
                        withAnimation(DS.Anim.snappy) { dragOffset = 0 }
                    }
            )
        }

        // بانر رجوع الاتصال
        if showReconnected {
            bannerView(
                icon: "wifi",
                title: L10n.t("رجع الاتصال", "Back Online"),
                subtitle: L10n.t("جاري تحديث البيانات", "Updating data..."),
                color: DS.Color.success
            )
        }

        EmptyView()
            .onAppear {
                if !networkMonitor.isConnected {
                    wasDisconnected = true
                    triggerBanner()
                }
            }
            .onChange(of: networkMonitor.isConnected) { connected in
                if !connected {
                    wasDisconnected = true
                    showReconnected = false
                    triggerBanner()
                } else {
                    withAnimation(DS.Anim.snappy) { showBanner = false }
                    hideTask?.cancel()

                    // رسالة رجوع الاتصال — مرة وحدة فقط
                    if wasDisconnected {
                        wasDisconnected = false
                        withAnimation(DS.Anim.smooth) { showReconnected = true }
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            withAnimation(DS.Anim.snappy) { showReconnected = false }
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TabChanged"))) { _ in
                if !networkMonitor.isConnected {
                    triggerBanner()
                }
            }
    }

    // MARK: - Banner View

    private func bannerView(icon: String, title: String, subtitle: String?, color: Color) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(.white.opacity(0.2))
                )

            Text(title)
                .font(DS.Font.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            if let subtitle {
                Text("— \(subtitle)")
                    .font(DS.Font.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(
            Capsule()
                .fill(color.opacity(0.88))
                .shadow(color: color.opacity(0.2), radius: 8, y: 3)
        )
        .padding(.horizontal, DS.Spacing.xl)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Helpers

    private func triggerBanner() {
        hideTask?.cancel()
        withAnimation(DS.Anim.smooth) { showBanner = true }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(DS.Anim.snappy) { showBanner = false }
        }
    }
}
