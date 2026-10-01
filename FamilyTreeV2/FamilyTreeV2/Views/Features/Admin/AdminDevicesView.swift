import SwiftUI

/// الأجهزة المرتبطة بالحسابات — بتصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧):
/// بطاقة رأس بأرقام حيّة ← حقل بحث ← بطاقة لكل عضو فيها أجهزته صفوفاً `.dsRowBox()`.
/// فصل الجهاز للمالك فقط، وبتأكيد كما كان.
struct AdminDevicesView: View {
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var authVM: AuthViewModel

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    @State private var allDevices: [NotificationViewModel.LinkedDevice] = []
    @State private var searchText = ""
    @State private var deviceToRemove: NotificationViewModel.LinkedDevice?
    @State private var isRemoving = false
    /// نتيجة آخر إزالة — تظهر أسفل الشاشة (نجاح أو سبب الفشل)
    @State private var removalMessage: String?
    @State private var removalFailed = false
    @State private var isLoading = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tint = DS.Color.actionNavy

    /// تجميع الأجهزة حسب العضو — مرتبة بأحدث نشاط أولاً
    private var groupedDevices: [(member: FamilyMember?, memberId: UUID, devices: [NotificationViewModel.LinkedDevice])] {
        let grouped = Dictionary(grouping: allDevices) { $0.memberId }
        return grouped.map { (memberId, devices) in
            let member = memberVM.allMembers.first { $0.id == memberId }
            let sortedDevices = devices.sorted { $0.updatedAt > $1.updatedAt }
            return (member: member, memberId: memberId, devices: sortedDevices)
        }
        .sorted { lhs, rhs in
            // ترتيب: أحدث جهاز نشاطاً أولاً
            let lLatest = lhs.devices.first?.updatedAt ?? ""
            let rLatest = rhs.devices.first?.updatedAt ?? ""
            return lLatest > rLatest
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
    /// أعضاء بأكثر من جهاز — يهمّ مع «الحد الأقصى للأجهزة»
    private var multiDeviceMembers: Int { groupedDevices.filter { $0.devices.count > 1 }.count }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) {
                    hero

                    if isLoading {
                        SysStateCard(icon: "iphone.gen3",
                                     title: t("جارٍ تحميل الأجهزة…", "Loading devices…"),
                                     tint: tint,
                                     isLoading: true)
                            .padding(.top, DS.Spacing.sm)
                    } else if allDevices.isEmpty {
                        emptyState
                            .padding(.top, DS.Spacing.sm)
                    } else {
                        DSSearchField(text: $searchText,
                                      placeholder: t("بحث بالاسم أو الجهاز...", "Search by name or device..."),
                                      tint: tint)
                            .dsStaggerIn(1)

                        // قائمة الأجهزة — الوضع الأفقي على عمودين
                        AdaptiveLazyStack(spacing: DS.Spacing.md, landscapeMinimum: 340) {
                            if filteredGroups.isEmpty {
                                SysStateCard(icon: "magnifyingglass",
                                             title: t("لا توجد نتائج مطابقة", "No matching results"),
                                             hint: t("جرّب اسماً آخر أو نوع جهاز", "Try another name or device model"),
                                             tint: DS.Color.textTertiary)
                            }
                            ForEach(filteredGroups, id: \.memberId) { group in
                                memberDeviceCard(group)
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xxxl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay(alignment: .bottom) {
            if let removalMessage {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: removalFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .accessibilityHidden(true)
                    Text(removalMessage)
                        .font(DS.Font.plex(12, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { self.removalMessage = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -10)
                    .accessibilityLabel(t("إغلاق", "Close"))
                }
                .foregroundColor(.white)
                .padding(.leading, DS.Spacing.md)
                .padding(.trailing, DS.Spacing.xs)
                .padding(.vertical, DS.Spacing.md)
                .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(removalFailed ? DS.Color.error : DS.Color.success))
                .padding(DS.Spacing.lg)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(DS.Anim.snappy, value: removalMessage)
        .navigationTitle(t("إدارة الأجهزة", "Device Management"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .dsAlert(
            t("إزالة الجهاز", "Remove Device"),
            isPresented: .init(
                get: { deviceToRemove != nil },
                set: { if !$0 { deviceToRemove = nil } }
            )
        ) {
            Button(t("إلغاء", "Cancel"), role: .cancel) { deviceToRemove = nil }
            Button(t("إزالة", "Remove"), role: .destructive) {
                // نلتقط الجهاز فوراً — قبل أي إغلاق للمربّع يصفّر الاختيار
                let device = deviceToRemove
                if let device {
                    Task {
                        isRemoving = true
                        let success = await notificationVM.removeDeviceByAdmin(device)
                        allDevices = await notificationVM.fetchAllDevices()
                        let stillThere = allDevices.contains { $0.id == device.id }
                        removalFailed = !success || stillThere
                        removalMessage = removalFailed
                            ? t("تعذّرت إزالة الجهاز — \(notificationVM.lastDeviceError ?? "لم يُحذف من السيرفر")",
                                "Couldn't remove the device — \(notificationVM.lastDeviceError ?? "not deleted on the server")")
                            : t("تمت إزالة الجهاز", "Device removed")
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

    // MARK: - بطاقة الرأس

    private var hero: some View {
        DSPageHero(
            title: t("الأجهزة المرتبطة", "Connected devices"),
            subtitle: t("ابحث عن العضو وتابع أجهزته", "Find a member and manage their devices"),
            icon: "iphone.gen3",
            tint: tint,
            stats: [
                DSHeroStat(value: isLoading ? "—" : "\(totalMembersWithDevices)",
                           label: t("عضو", "Members"), icon: "person.2.fill"),
                DSHeroStat(value: isLoading ? "—" : "\(totalDevices)",
                           label: t("جهاز", "Devices"), icon: "iphone.gen3"),
                DSHeroStat(value: isLoading ? "—" : "\(multiDeviceMembers)",
                           label: t("بأكثر من جهاز", "Multi-device"), icon: "ipad.and.iphone")
            ]
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        SysStateCard(
            icon: "iphone.slash",
            title: t("لا توجد أجهزة مسجلة", "No registered devices"),
            hint: t("تظهر هنا أجهزة الأعضاء بعد دخولهم التطبيق", "Members' devices appear here after they sign in"),
            tint: tint
        )
    }

    // MARK: - Member Device Card

    private func memberDeviceCard(_ group: (member: FamilyMember?, memberId: UUID, devices: [NotificationViewModel.LinkedDevice])) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm + 2) {
            // رأس العضو
            HStack(spacing: DS.Spacing.sm) {
                memberAvatar(group.member)

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.member?.displayFullName ?? t("عضو غير معروف", "Unknown Member"))
                        .font(DS.Font.plex(13.5, weight: .bold))
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(1)

                    HStack(spacing: DS.Spacing.xs) {
                        if let member = group.member {
                            SysStatusChip(text: member.roleName, tint: member.roleColor)
                        }
                        SysStatusChip(
                            text: t("\(group.devices.count) جهاز",
                                    "\(group.devices.count) device\(group.devices.count == 1 ? "" : "s")"),
                            icon: "iphone.gen3",
                            tint: group.devices.count > 1 ? DS.Color.warning : DS.Color.primary
                        )
                    }
                }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            // أجهزة العضو
            VStack(spacing: 6) {
                ForEach(group.devices) { device in
                    adminDeviceRow(device)
                }
            }
        }
        .padding(DS.Spacing.md)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1))
    }

    private func memberAvatar(_ member: FamilyMember?) -> some View {
        ZStack {
            Circle().fill(tint.dsReadableGlyph.opacity(0.12))
            if let urlStr = member?.avatarUrl, let url = URL(string: urlStr) {
                CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                placeholder: { ProgressView() }
                .frame(width: 38, height: 38)
                .clipShape(Circle())
            } else if let name = member?.fullName, let first = name.first {
                Text(String(first))
                    .font(DS.Font.plex(15, weight: .bold))
                    .foregroundColor(tint.dsReadableGlyph)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(tint.dsReadableGlyph)
            }
        }
        .frame(width: 38, height: 38)
        .accessibilityHidden(true)
    }

    // MARK: - Device Row

    private func adminDeviceRow(_ device: NotificationViewModel.LinkedDevice) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: device.platform.lowercased() == "android" ? "candybarphone" : "iphone.gen3",
                        tint: tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1)
                Text(formattedDate(device.updatedAt))
                    .font(DS.Font.plex(12))
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            // فصل الأجهزة للمالك فقط (إجراء أمني — كان بلا بوابة)
            if authVM.canManageDevices {
                Button {
                    deviceToRemove = device
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 10.5, weight: .bold))
                        Text(t("إزالة", "Remove"))
                            .font(DS.Font.plex(11.5, weight: .bold))
                    }
                    .foregroundColor(DS.Color.error)
                    .padding(.horizontal, DS.Spacing.sm + 2)
                    .frame(height: 30)
                    .background(DS.Color.error.opacity(0.10), in: Capsule())
                    // مساحة ضغط ٤٤ نقطة والشكل كما هو
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .padding(.vertical, -7)
                }
                .buttonStyle(.plain)
                .disabled(isRemoving)
                .accessibilityLabel(t("إزالة \(device.displayName)", "Remove \(device.displayName)"))
            }
        }
        .dsRowBox()
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
