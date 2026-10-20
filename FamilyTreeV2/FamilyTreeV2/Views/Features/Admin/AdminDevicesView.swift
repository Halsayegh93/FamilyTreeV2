import SwiftUI

/// الأجهزة المرتبطة بالحسابات — بشكل «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠، `AdminPageKit`):
/// رأس كحلي بأرقام حيّة (وشارة «للقراءة» لغير المالك) ← البحث يصعد فوقه ← بطاقة بيضاء لكل عضو فيها أجهزته
/// صفوفاً مفصولة بخط. فصل الجهاز للمالك فقط، وبتأكيد كما كان.
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
        AdminPage(header: header, lead: leadCard, content: deviceCards)
            .overlay(alignment: .bottom) {
                if let removalMessage {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: removalFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .accessibilityHidden(true)
                        Text(removalMessage)
                            .dsFont(.chip)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button { self.removalMessage = nil } label: {
                            Image(systemName: "xmark")
                                .dsGlyph(DS.Glyph.xs)
                                .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, -DS.Spacing.sm)
                        .accessibilityLabel(t("إغلاق", "Close"))
                    }
                    .foregroundColor(DS.Color.textOnPrimary)
                    .padding(.leading, DS.Spacing.md)
                    .padding(.trailing, DS.Spacing.xs)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DSBox.sectionShape.fill(removalFailed ? DS.Color.error : DS.Color.success))
                    .padding(DS.Spacing.lg)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(DS.Anim.snappy, value: removalMessage)
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

    // MARK: - الرأس الكحلي

    /// ٣ أرقام حيّة من الأجهزة المحمّلة أصلاً — «—» قبل اكتمال التحميل. الفصل للمالك وحده (شارة «للقراءة» لغيره)
    private var header: AdminPageHeader {
        AdminPageHeader(
            title: t("الأجهزة", "Devices"),
            subtitle: t("ابحث عن العضو وتابع أجهزته", "Find a member and manage their devices"),
            glyph: "iphone.gen3",
            readOnly: !authVM.canManageDevices,
            kpis: [
                AdminPageKPI(isLoading ? "—" : "\(totalMembersWithDevices)", t("عضو", "Members"), icon: "person.2.fill"),
                AdminPageKPI(isLoading ? "—" : "\(totalDevices)", t("جهاز", "Devices"), icon: "iphone.gen3",
                             tint: DS.Hub.kpiMine),
                AdminPageKPI(isLoading ? "—" : "\(multiDeviceMembers)", t("بأكثر من جهاز", "Multi-device"),
                             icon: "ipad.and.iphone",
                             tint: !isLoading && multiDeviceMembers > 0 ? DS.Hub.kpiLate : DS.Color.textOnPrimary)
            ])
    }

    // MARK: - المحتوى

    /// أول بطاقة (تصعد فوق الرأس): التحميل، أو «لا توجد أجهزة»، أو البحث
    private var leadCard: AnyView {
        if isLoading {
            return AnyView(AdminPageStateCard(.loading(t("جارٍ تحميل الأجهزة…", "Loading devices…"))))
        }
        if allDevices.isEmpty {
            return AnyView(AdminPageStateCard(.empty(t("لا توجد أجهزة مسجلة", "No registered devices"),
                                                     message: t("تظهر هنا أجهزة الأعضاء بعد دخولهم التطبيق",
                                                                "Members' devices appear here after they sign in"))))
        }
        return AnyView(DSSearchField(text: $searchText,
                                     placeholder: t("بحث بالاسم أو الجهاز...", "Search by name or device..."),
                                     tint: tint)
            .adminCard(padding: DS.Spacing.md))
    }

    /// بطاقة لكل عضو بأجهزته — الوضع الأفقي على عمودين
    private var deviceCards: AnyView {
        guard !isLoading, !allDevices.isEmpty else { return AnyView(EmptyView()) }
        let groups = filteredGroups
        if groups.isEmpty {
            return AnyView(AdminPageStateCard(.empty(t("لا توجد نتائج مطابقة", "No matching results"),
                                                     message: t("جرّب اسماً آخر أو نوع جهاز", "Try another name or device model"))))
        }
        return AnyView(VStack(spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: t("أجهزة الأعضاء", "Members' devices"),
                              trailing: t("\(groups.count) عضو", "\(groups.count) members"))
            AdaptiveLazyStack(spacing: DS.Hub.stackSpacing) {
                ForEach(groups, id: \.memberId) { group in
                    memberDeviceCard(group)
                }
            }
        })
    }

    // MARK: - Member Device Card

    /// بطاقة بيضاء: العضو (صورته، اسمه، دوره، عدد أجهزته) ثم أجهزته صفوفاً مفصولة بخط
    private func memberDeviceCard(_ group: (member: FamilyMember?, memberId: UUID, devices: [NotificationViewModel.LinkedDevice])) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // رأس العضو
            HStack(spacing: DS.Spacing.md) {
                memberAvatar(group.member)

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(group.member?.displayFullName ?? t("عضو غير معروف", "Unknown Member"))
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                        .dsNameLines()

                    HStack(spacing: DS.Spacing.xs) {
                        if let member = group.member {
                            DSStatusChip(text: member.roleName, tint: member.roleColor)
                        }
                        DSStatusChip(
                            text: t("\(group.devices.count) جهاز",
                                    "\(group.devices.count) device\(group.devices.count == 1 ? "" : "s")"),
                            icon: "iphone.gen3",
                            tint: group.devices.count > 1 ? DS.Color.warning : AppSection.admin.ink
                        )
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.bottom, DS.Spacing.sm)
            .accessibilityElement(children: .combine)

            // أجهزة العضو
            ForEach(group.devices) { device in
                AdminRowDivider()
                adminDeviceRow(device)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private func memberAvatar(_ member: FamilyMember?) -> some View {
        DSMemberAvatar(name: member?.fullName ?? t("عضو", "Member"), avatarUrl: member?.avatarUrl,
                       size: DS.Icon.avatar, roleColor: tint)
            .accessibilityHidden(true)
    }

    // MARK: - Device Row

    private func adminDeviceRow(_ device: NotificationViewModel.LinkedDevice) -> some View {
        HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: device.platform.lowercased() == "android" ? "candybarphone" : "iphone.gen3",
                            tint: DS.Color.primary)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(device.displayName)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                Text(formattedDate(device.updatedAt))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            // فصل الأجهزة للمالك فقط (إجراء أمني — كان بلا بوابة)
            if authVM.canManageDevices {
                // الشريحة الواحدة بالأحمر (مساحة ضغط ٤٤)
                DSChipButton(t("إزالة", "Remove"), icon: "trash.fill", tint: DS.Color.error) {
                    deviceToRemove = device
                }
                .disabled(isRemoving)
                .accessibilityLabel(t("إزالة \(device.displayName)", "Remove \(device.displayName)"))
            }
        }
        .padding(.vertical, DS.Spacing.sm + 2)
        .frame(minHeight: DS.Icon.tapTarget)
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
