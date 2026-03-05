import SwiftUI

struct AdminDeceasedRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            if adminRequestVM.deceasedRequests.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: DS.Spacing.md) {
                        ForEach(adminRequestVM.deceasedRequests) { request in
                            requestCard(request: request)
                        }
                    }
                    .padding(DS.Spacing.lg)
                }
            }
        }
        .navigationTitle(L10n.t("طلبات تأكيد الوفاة", "Deceased Confirmation Requests"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await adminRequestVM.fetchDeceasedRequests() }
    }

    private func requestCard(request: AdminRequest) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {

                // Red gradient accent bar
                LinearGradient(
                    colors: [DS.Color.error, DS.Color.error.opacity(0.7)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 4)
                .cornerRadius(DS.Radius.full)

                HStack(spacing: DS.Spacing.md) {
                    // Gradient circle with heart icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [DS.Color.error.opacity(0.2), DS.Color.error.opacity(0.08)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        Image(systemName: "bolt.heart.fill")
                            .foregroundColor(DS.Color.error)
                            .font(DS.Font.scaled(18, weight: .semibold))
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        // عرض اسم الشخص من البيانات القادمة من السيرفر
                        Text(L10n.t("طلب لـ: \(request.member?.fullName ?? "عضو جديد")", "Request for: \(request.member?.fullName ?? "New Member")"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(request.details ?? L10n.t("لا توجد تفاصيل إضافية", "No additional details"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    Spacer()
                }

                // Action buttons
                DSApproveRejectButtons(
                    approveTitle: L10n.t("موافقة وتحديث الشجرة", "Approve & Update Tree"),
                    rejectTitle: L10n.t("رفض", "Reject"),
                    isLoading: adminRequestVM.isLoading
                ) {
                    Task { await adminRequestVM.approveDeceasedRequest(request: request) }
                } onReject: {
                    Task { await adminRequestVM.rejectDeceasedRequest(request: request) }
                }
            }
            .padding(DS.Spacing.lg)
        }
    }

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
                Image(systemName: "checkmark.circle.fill")
                    .font(DS.Font.scaled(26, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(L10n.t("لا توجد طلبات حالياً", "No requests at the moment"))
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.textSecondary)
        }
    }
}
