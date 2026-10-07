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
            Image(dsSymbol: icon)
                .dsGlyph(DS.Glyph.md)
                .foregroundStyle(DS.Color.textOnPrimary)
                .frame(width: DSBox.alertIcon, height: DSBox.alertIcon)
                .background(
                    Circle()
                        .fill(DS.Color.overlayFill)
                )

            Text(title)
                .dsFont(.subtitle)
                .fontWeight(.semibold)
                .foregroundStyle(DS.Color.textOnPrimary)

            if let subtitle {
                Text("— \(subtitle)")
                    .font(DS.Font.caption2)
                    .foregroundStyle(DS.Color.overlayTextMuted)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(
            Capsule()
                .fill(color.opacity(DS.Opacity.mediaDim))
                .shadow(color: color.opacity(DS.Opacity.tintFillStrong), radius: DS.Spacing.sm, y: DS.Card.shadowY)
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
