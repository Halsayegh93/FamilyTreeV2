import SwiftUI

struct AdminDiwaniyaRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var diwaniyaVM = DiwaniyasViewModel()

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            if diwaniyaVM.pendingDiwaniyas.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    // عدد الطلبات
                    HStack(spacing: DS.Spacing.md) {
                        Image(systemName: "tent.fill")
                            .font(DS.Font.scaled(16, weight: .semibold))
                            .foregroundColor(DS.Color.gridDiwaniya)

                        Text(L10n.t("طلبات معلقة", "Pending Requests"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)

                        Spacer()

                        Text("\(diwaniyaVM.pendingDiwaniyas.count)")
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.gridDiwaniya)
                            .frame(minWidth: 26, minHeight: 26)
                            .background(DS.Color.gridDiwaniya.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                            .fill(DS.Color.surfaceElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                                    .stroke(DS.Color.textTertiary.opacity(0.25), lineWidth: 0.75)
                            )
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, DS.Spacing.sm)

                    LazyVStack(spacing: DS.Spacing.md) {
                        ForEach(diwaniyaVM.pendingDiwaniyas) { diwaniya in
                            card(for: diwaniya)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xxxl)
                }
            }
        }
        .navigationTitle(L10n.t("طلبات الديوانيات", "Diwaniya Requests"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await diwaniyaVM.fetchPendingDiwaniyas() }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(DS.Color.success.opacity(0.08))
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(DS.Color.success.opacity(0.12))
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 60, height: 60)
                Image(systemName: "checkmark.seal.fill")
                    .font(DS.Font.scaled(26, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(L10n.t("لا توجد طلبات ديوانيات معلقة", "No pending diwaniya requests"))
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.textSecondary)
        }
    }

    // MARK: - Card
    private func card(for diwaniya: Diwaniya) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {

            // Header
            HStack(spacing: DS.Spacing.sm) {
                // أيقونة الديوانية
                Circle()
                    .fill(DS.Color.gridDiwaniya.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "tent.fill")
                            .font(DS.Font.scaled(16, weight: .semibold))
                            .foregroundColor(DS.Color.gridDiwaniya)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(diwaniya.title)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                    Text(diwaniya.ownerName)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }

                Spacer()

                Text(L10n.t("معلق", "Pending"))
                    .font(DS.Font.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.warning)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(DS.Color.warning.opacity(0.12))
                    .clipShape(Capsule())
            }

            // التفاصيل
            VStack(spacing: DS.Spacing.sm) {
                if let schedule = diwaniya.scheduleText, !schedule.isEmpty {
                    detailRow(icon: "calendar", text: schedule)
                }
                if let phone = diwaniya.contactPhone, !phone.isEmpty {
                    detailRow(icon: "phone.fill", text: phone)
                }
                if let address = diwaniya.address, !address.isEmpty {
                    detailRow(icon: "mappin.and.ellipse", text: address)
                }
                if let maps = diwaniya.mapsUrl, !maps.isEmpty {
                    detailRow(icon: "map.fill", text: L10n.t("رابط الموقع متوفر", "Map link available"))
                }
            }

            // أزرار الموافقة/الرفض
            DSApproveRejectButtons(
                approveTitle: L10n.t("اعتماد", "Approve"),
                rejectTitle: L10n.t("رفض", "Reject"),
                isLoading: diwaniyaVM.isLoading,
                approveGradient: LinearGradient(
                    colors: [DS.Color.success, DS.Color.success.opacity(0.8)],
                    startPoint: .leading, endPoint: .trailing
                )
            ) {
                if let adminId = authVM.currentUser?.id {
                    Task { await diwaniyaVM.approveDiwaniya(id: diwaniya.id, adminId: adminId) }
                }
            } onReject: {
                Task { await diwaniyaVM.rejectDiwaniya(id: diwaniya.id) }
            }
        }
        .padding(DS.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
                .fill(.thickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
                        .stroke(DS.Color.textTertiary.opacity(0.2), lineWidth: 0.75)
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Font.scaled(12, weight: .medium))
                .foregroundColor(DS.Color.textTertiary)
                .frame(width: 18)
            Text(text)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(2)
        }
    }
}
