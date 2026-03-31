import SwiftUI

struct AdminDevicesView: View {
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    @State private var allDevices: [NotificationViewModel.LinkedDevice] = []
    @State private var searchText = ""
    @State private var deviceToRemove: NotificationViewModel.LinkedDevice?
    @State private var isRemoving = false
    @State private var isLoading = true

    /// تجميع الأجهزة حسب العضو
    private var groupedDevices: [(member: FamilyMember?, memberId: UUID, devices: [NotificationViewModel.LinkedDevice])] {
        let grouped = Dictionary(grouping: allDevices) { $0.memberId }
        return grouped.map { (memberId, devices) in
            let member = memberVM.allMembers.first { $0.id == memberId }
            return (member: member, memberId: memberId, devices: devices.sorted { $0.updatedAt > $1.updatedAt })
        }
        .sorted { lhs, rhs in
            // ترتيب: الأعضاء اللي لهم أسماء أول، ثم بالاسم
            let lName = lhs.member?.fullName ?? ""
            let rName = rhs.member?.fullName ?? ""
            if lName.isEmpty && !rName.isEmpty { return false }
            if !lName.isEmpty && rName.isEmpty { return true }
            return lName < rName
        }
    }

    /// البحث
    private var filteredGroups: [(member: FamilyMember?, memberId: UUID, devices: [NotificationViewModel.LinkedDevice])] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return groupedDevices
        }
        let query = searchText.lowercased()
        return groupedDevices.filter { group in
            if let name = group.member?.fullName, name.lowercased().contains(query) { return true }
            if let name = group.member?.firstName, name.lowercased().contains(query) { return true }
            if group.devices.contains(where: { ($0.displayName).lowercased().contains(query) }) { return true }
            return false
        }
    }

    /// إجمالي الأعضاء اللي عندهم أجهزة
    private var totalMembersWithDevices: Int { groupedDevices.count }
    /// إجمالي الأجهزة
    private var totalDevices: Int { allDevices.count }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if allDevices.isEmpty {
                    emptyState
                } else {
                    // Stats
                    statsBar
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)

                    // Search
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(DS.Color.textTertiary)
                        TextField(t("بحث بالاسم أو الجهاز...", "Search by name or device..."), text: $searchText)
                            .font(DS.Font.callout)
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.md)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)

                    // Device list
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: DS.Spacing.md) {
                            ForEach(filteredGroups, id: \.memberId) { group in
                                memberDeviceCard(group)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.xxxl)
                    }
                }
            }
        }
        .navigationTitle(t("إدارة الأجهزة", "Device Management"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .alert(
            t("إزالة الجهاز", "Remove Device"),
            isPresented: .init(
                get: { deviceToRemove != nil },
                set: { if !$0 { deviceToRemove = nil } }
            )
        ) {
            Button(t("إلغاء", "Cancel"), role: .cancel) { deviceToRemove = nil }
            Button(t("إزالة", "Remove"), role: .destructive) {
                if let device = deviceToRemove {
                    Task {
                        isRemoving = true
                        let success = await notificationVM.removeDeviceByAdmin(device)
                        if success {
                            allDevices.removeAll { $0.id == device.id }
                        }
                        isRemoving = false
                    }
                }
                deviceToRemove = nil
            }
        } message: {
            if let device = deviceToRemove {
                let memberName = memberVM.allMembers.first { $0.id == device.memberId }?.fullName ?? t("عضو", "Member")
                Text(t(
                    "سيتم إزالة جهاز \(device.displayName) من حساب \(memberName). سيتم تسجيل خروج هذا الجهاز تلقائياً.",
                    "Device \(device.displayName) will be removed from \(memberName)'s account. This device will be signed out automatically."
                ))
            }
        }
        .task {
            isLoading = true
            allDevices = await notificationVM.fetchAllDevices()
            isLoading = false
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: DS.Spacing.md) {
            statPill(
                icon: "person.2.fill",
                value: "\(totalMembersWithDevices)",
                label: t("عضو", "Members"),
                color: DS.Color.info
            )
            statPill(
                icon: "iphone.gen3",
                value: "\(totalDevices)",
                label: t("جهاز", "Devices"),
                color: DS.Color.neonBlue
            )
        }
    }

    private func statPill(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Font.scaled(13, weight: .bold))
                .foregroundColor(color)
            Text(value)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)
            Text(label)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity)
        .glassCard(radius: DS.Radius.md)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()
            Image(systemName: "iphone.slash")
                .font(DS.Font.scaled(48, weight: .light))
                .foregroundColor(DS.Color.textTertiary)
            Text(t("لا توجد أجهزة مسجلة", "No registered devices"))
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.textSecondary)
            Spacer()
        }
    }

    // MARK: - Member Device Card

    private func memberDeviceCard(_ group: (member: FamilyMember?, memberId: UUID, devices: [NotificationViewModel.LinkedDevice])) -> some View {
        DSCard(padding: 0) {
            // Member header
            HStack(spacing: DS.Spacing.md) {
                DSIcon("person.fill", color: DS.Color.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.member?.fullName ?? t("عضو غير معروف", "Unknown Member"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: DS.Spacing.xs) {
                        if let member = group.member {
                            DSRoleBadge(title: member.roleName, color: member.roleColor)
                        }
                        Text(t(
                            "\(group.devices.count) جهاز",
                            "\(group.devices.count) device\(group.devices.count == 1 ? "" : "s")"
                        ))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)

            DSDivider()

            // Device rows
            VStack(spacing: 0) {
                ForEach(Array(group.devices.enumerated()), id: \.element.id) { index, device in
                    if index > 0 { DSDivider() }
                    adminDeviceRow(device)
                }
            }
        }
    }

    // MARK: - Device Row

    private func adminDeviceRow(_ device: NotificationViewModel.LinkedDevice) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "iphone.gen3")
                .font(DS.Font.scaled(16, weight: .bold))
                .foregroundColor(DS.Color.neonBlue)
                .frame(width: 32, height: 32)
                .background(DS.Color.neonBlue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)

                Text(formattedDate(device.updatedAt))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
            }

            Spacer()

            Button {
                deviceToRemove = device
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "trash.fill")
                        .font(DS.Font.scaled(11, weight: .bold))
                    Text(t("إزالة", "Remove"))
                        .font(DS.Font.scaled(11, weight: .bold))
                }
                .foregroundColor(DS.Color.error)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs + 2)
                .background(DS.Color.error.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isRemoving)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - Date Formatter

    private func formattedDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            let df = DateFormatter()
            df.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: isoString) {
            let df = DateFormatter()
            df.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
        return isoString
    }
}
