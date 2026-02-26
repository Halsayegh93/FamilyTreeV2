import SwiftUI

struct NotificationsCenterView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                // Decorative gradient circles
                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 220, height: 220)
                    .blur(radius: 90)
                    .opacity(0.15)
                    .offset(x: 130, y: -200)

                Circle()
                    .fill(DS.Color.gradientAccent)
                    .frame(width: 180, height: 180)
                    .blur(radius: 70)
                    .opacity(0.12)
                    .offset(x: -120, y: 150)

                if authVM.notifications.isEmpty {
                    emptyState
                } else {
                    notificationsList
                }
            }
            .navigationTitle(L10n.t("الإشعارات", "Notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                }
            }
            .onAppear {
                Task { await authVM.fetchNotifications() }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            ZStack {
                // Layered gradient circles
                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 100, height: 100)
                    .opacity(0.12)

                Circle()
                    .fill(DS.Color.gradientAccent)
                    .frame(width: 72, height: 72)
                    .opacity(0.18)

                // Gradient bell icon
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(DS.Color.gradientPrimary)
            }

            Text(L10n.t("لا توجد إشعارات حالياً", "No notifications yet"))
                .font(DS.Font.title3)
                .foregroundColor(DS.Color.textSecondary)
        }
    }

    private func notificationIcon(for kind: String) -> (icon: String, gradient: LinearGradient) {
        switch kind {
        case "approval": return ("checkmark.circle.fill", DS.Color.gradientCool)
        case "news": return ("newspaper.fill", DS.Color.gradientPrimary)
        case "admin": return ("shield.fill", DS.Color.gradientAccent)
        default: return ("bell.fill", DS.Color.gradientPrimary)
        }
    }

    private func isRecent(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) < 86400 // 24 hours
    }

    // MARK: - Notifications List
    private var notificationsList: some View {
        List {
            ForEach(authVM.notifications) { item in
                let iconInfo = notificationIcon(for: item.kind)
                let recent = isRecent(item.createdDate)

                DSCard(padding: 0) {
                    HStack(spacing: DS.Spacing.md) {
                        // Gradient icon circle based on kind
                        ZStack {
                            Circle()
                                .fill(iconInfo.gradient)
                                .frame(width: 44, height: 44)
                                .overlay(Circle().stroke(DS.Color.primary.opacity(0.15), lineWidth: 1.5))

                            Image(systemName: iconInfo.icon)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)

                            // New badge for recent notifications
                            if recent {
                                Circle()
                                    .fill(DS.Color.error)
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(DS.Color.surface, lineWidth: 2))
                                    .offset(x: 14, y: -14)
                            }
                        }

                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(item.title)
                                .font(DS.Font.headline)
                                .foregroundColor(DS.Color.textPrimary)
                            Text(item.body)
                                .font(DS.Font.subheadline)
                                .foregroundColor(recent ? DS.Color.textPrimary : DS.Color.textSecondary)
                                .lineLimit(3)
                            Text(relativeTime(item.createdDate))
                                .font(DS.Font.caption2)
                                .foregroundColor(DS.Color.textSecondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                }
                .listRowInsets(EdgeInsets(top: DS.Spacing.sm, leading: DS.Spacing.lg, bottom: DS.Spacing.sm, trailing: DS.Spacing.lg))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task {
                            await authVM.deleteNotification(id: item.id)
                        }
                    } label: {
                        Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.top, DS.Spacing.sm)
    }
}
