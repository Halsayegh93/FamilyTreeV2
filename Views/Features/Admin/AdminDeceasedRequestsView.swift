import SwiftUI

struct AdminDeceasedRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                if authVM.deceasedRequests.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: DS.Spacing.lg) {
                            ForEach(authVM.deceasedRequests) { request in
                                requestCard(request: request)
                            }
                        }
                        .padding(DS.Spacing.lg)
                    }
                }
            }
            .navigationTitle("طلبات تأكيد الوفاة")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task { await authVM.fetchDeceasedRequests() } // جلب البيانات عند الفتح
            }
        }
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
                        Text("طلب لـ: \(request.member?.fullName ?? "عضو جديد")")
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(request.details ?? "لا توجد تفاصيل إضافية")
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    Spacer()
                }

                // Action buttons — gradient approve/reject
                HStack(spacing: DS.Spacing.md) {
                    // Reject button
                    Button("رفض") { /* دالة الرفض */ }
                        .font(DS.Font.caption1)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(DS.Color.error.opacity(0.1))
                        .cornerRadius(DS.Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .stroke(DS.Color.error.opacity(0.2), lineWidth: 1)
                        )

                    // Approve button — gradient
                    Button("موافقة وتحديث الشجرة") {
                        Task {
                            await authVM.approveDeceasedRequest(request: request)
                        }
                    }
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Color.gradientPrimary)
                    .cornerRadius(DS.Radius.md)
                    .dsGlowShadow()
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
            Text("لا توجد طلبات حالياً")
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.textSecondary)
        }
    }
}
