import SwiftUI

struct AdminPhoneRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            if authVM.phoneChangeRequests.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: DS.Spacing.lg) {
                        ForEach(authVM.phoneChangeRequests) { request in
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
        .task { await authVM.fetchPhoneChangeRequests() }
    }

    private func phoneRequestCard(request: PhoneChangeRequest) -> some View {
        let currentPhone = KuwaitPhone.display(request.member?.phoneNumber)
        let newPhone = KuwaitPhone.display(request.newValue)
        let memberName = request.member?.fullName ?? "Member"

        return DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {

                // Gradient accent bar at top
                DS.Color.gradientPrimary
                    .frame(height: 4)
                    .cornerRadius(DS.Radius.full)

                // Header: date + name
                HStack {
                    Text((request.createdAt ?? "").prefix(10))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textSecondary)
                    Spacer()
                    Text(memberName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
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

                    // Arrow — DS.Color.primary
                    Image(systemName: "arrow.left")
                        .foregroundColor(DS.Color.primary)
                        .font(DS.Font.scaled(14, weight: .semibold))

                    // Current phone — DS.Color.textSecondary styled
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
                    isLoading: authVM.isLoading
                ) {
                    Task { await authVM.approvePhoneChangeRequest(request: request) }
                } onReject: {
                    Task { await authVM.rejectPhoneChangeRequest(request: request) }
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
