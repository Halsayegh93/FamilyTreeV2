import SwiftUI

struct AdminChildAddRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()
                DSDecorativeBackground()

                if authVM.childAddRequests.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: DS.Spacing.lg) {
                            ForEach(authVM.childAddRequests) { request in
                                requestCard(request: request)
                            }
                        }
                        .padding(DS.Spacing.lg)
                    }
                }
            }
            .navigationTitle(L10n.t("طلبات إضافة الأبناء", "Child Add Requests"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await authVM.fetchChildAddRequests() }
        }
    }

    private func requestCard(request: AdminRequest) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {

                // Teal gradient accent bar
                LinearGradient(
                    colors: [DS.Color.info, DS.Color.info.opacity(0.7)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 4)
                .cornerRadius(DS.Radius.full)

                HStack(spacing: DS.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [DS.Color.info.opacity(0.2), DS.Color.info.opacity(0.08)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        Image(systemName: "person.badge.plus")
                            .foregroundColor(DS.Color.info)
                            .font(DS.Font.scaled(18, weight: .semibold))
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(L10n.t("طلب من: \(request.member?.fullName ?? "عضو")", "Request from: \(request.member?.fullName ?? "Member")"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)

                        // عرض اسم الابن المضاف من تفاصيل الطلب
                        Text(request.details ?? L10n.t("لا توجد تفاصيل إضافية", "No additional details"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)

                        if let createdAt = request.createdAt {
                            Text(createdAt.prefix(10))
                                .font(DS.Font.caption2)
                                .foregroundColor(DS.Color.textSecondary.opacity(0.7))
                        }
                    }
                    Spacer()
                }

                // Action buttons
                DSApproveRejectButtons(
                    approveTitle: L10n.t("تأكيد الإضافة", "Confirm Addition"),
                    rejectTitle: L10n.t("رفض وحذف", "Reject & Delete"),
                    isLoading: authVM.isLoading
                ) {
                    Task { await authVM.acknowledgeChildAddRequest(request: request) }
                } onReject: {
                    Task { await authVM.rejectChildAddRequest(request: request) }
                }
            }
            .padding(DS.Spacing.lg)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(DS.Color.gridTree.opacity(0.08))
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(DS.Color.gridTree.opacity(0.12))
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 60, height: 60)
                Image(systemName: "tray")
                    .font(DS.Font.scaled(26, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(L10n.t("لا توجد طلبات إضافة أبناء حالياً", "No child add requests"))
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.textSecondary)
        }
    }
}
