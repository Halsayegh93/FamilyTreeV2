import SwiftUI

struct AdminPhoneRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            if adminRequestVM.phoneChangeRequests.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: DS.Spacing.md) {
                        ForEach(adminRequestVM.phoneChangeRequests) { request in
                            phoneRequestCard(request: request)
                        }
                    }
                    .padding(DS.Spacing.lg)
                }
            }
        }
        .navigationTitle(L10n.t("طلبات تغيير الجوال", "Phone Change Requests"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await adminRequestVM.fetchPhoneChangeRequests() }
    }

    private func phoneRequestCard(request: PhoneChangeRequest) -> some View {
        let currentPhone = KuwaitPhone.display(request.member?.phoneNumber)
        let newPhone = KuwaitPhone.display(request.newValue)
        let memberName = request.member?.fullName ?? "Member"

        return DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {

                // Gradient accent bar
                DS.Color.gradientPrimary
                    .frame(height: 4)
                    .cornerRadius(DS.Radius.full)

                // Header: icon + name + date
                HStack(spacing: DS.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [DS.Color.primary.opacity(0.2), DS.Color.primary.opacity(0.08)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        Image(systemName: "phone.arrow.right")
                            .foregroundColor(DS.Color.primary)
                            .font(DS.Font.scaled(18, weight: .semibold))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(memberName)
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Text((request.createdAt ?? "").prefix(10))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textSecondary)
                    }

                    Spacer()
                }

                DSDivider()

                // Phone comparison boxes
                HStack(spacing: DS.Spacing.xl) {
                    // New phone — DS.Color.success styled
                    VStack(alignment: .center, spacing: DS.Spacing.xs) {
                        Text(L10n.t("الرقم الجديد", "New Number"))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.success)
                        Text(newPhone)
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.success)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DS.Spacing.md)
                    .background(DS.Color.success.opacity(0.08))
                    .cornerRadius(DS.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.success.opacity(0.2), lineWidth: 1)
                    )

                    // Arrow
                    Image(systemName: "arrow.left")
                        .foregroundColor(DS.Color.primary)
                        .font(DS.Font.scaled(14, weight: .semibold))

                    // Current phone
                    VStack(alignment: .center, spacing: DS.Spacing.xs) {
                        Text(L10n.t("الرقم الحالي", "Current Number"))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textSecondary)
                        Text(currentPhone)
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surfaceElevated)
                    .cornerRadius(DS.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.textTertiary.opacity(0.2), lineWidth: 1)
                    )
                }

                // Action buttons
                DSApproveRejectButtons(
                    approveTitle: L10n.t("اعتماد الرقم", "Approve Number"),
                    rejectTitle: L10n.t("رفض", "Reject"),
                    isLoading: adminRequestVM.isLoading
                ) {
                    Task { await adminRequestVM.approvePhoneChangeRequest(request: request) }
                } onReject: {
                    Task { await adminRequestVM.rejectPhoneChangeRequest(request: request) }
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
            Text(L10n.t("لا توجد طلبات معلقة", "No pending requests"))
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.textSecondary)
        }
    }
}
