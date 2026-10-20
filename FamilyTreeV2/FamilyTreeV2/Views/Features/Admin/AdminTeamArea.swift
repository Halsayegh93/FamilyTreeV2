import SwiftUI

// MARK: - «الفريق والأمان» — أشخاص + حالة الأمان (الدفعة ج من «نفّذ كل المقترح»، ٢٠٢٦-١٠-٢٠)
//
// كانت ٧ صفوف (فريق الإدارة بالأدوار، ما يقدر عليه كل دور، نطاقي، رسائل الدخول، الأجهزة، الأرقام المحظورة، قواعد
// التسجيل). صارت ٤ مداخل بلا تكرار:
//   الرأس: ثلاث إشارات حالة، كل واحدة رقم↗ لبيتها تحت (رصيد رسائل الدخول · التسجيل · وصول الإشعارات)
//   «فريق الإدارة»: بطاقة بعدد كل دور ← صفحة الفريق (وفيها «صلاحيات الأدوار» ودورك مميّز، و«إضافة» للمالك)
//   «الدخول والأمان»: رسائل رمز الدخول (KWT SMS) · التسجيل والمنع · الأجهزة ووصول الإشعارات
// «نطاقي» حُذف للمالك والمدير (سطر «صلاحياتي» في «اليوم» للمراقب والمشرف هو بيته). الصلاحيات كما كانت: الفريق
// `isAdmin`، والباقي `canViewSystemSettings`.

struct AdminTeamAreaView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var sms = SmsBalanceStore.shared
    @ObservedObject private var devices = AdminDeviceReachStore.shared

    var body: some View {
        let tools = AdminToolCatalog.tools(authVM: authVM, adminRequestVM: adminRequestVM)
            .filter { $0.area == .team && $0.id != "team.members" }
        AdminHubPage {
            AdminBandHeader(title: AdminArea.team.title, subtitle: AdminArea.team.subtitle, isAreaRoot: true) {
                EmptyView()
            } accessory: {
                if authVM.canViewSystemSettings {
                    AnyView(statusTiles)
                }
            }
        } content: {
            if authVM.isAdmin {
                AnyView(AdminTeamCard())
            }
            if !tools.isEmpty {
                AdminToolCards(tools: tools, hints: [:], warnings: sms.needsTopUp ? ["access.sms"] : [])
            }
        }
        // ما يُدفع من الإشارات وبطاقة الفريق يرجع باسم القسم
        .environment(\.adminPageTitle, AdminArea.team.title)
        .task {
            guard authVM.canViewSystemSettings else { return }
            async let a: Void = sms.refresh()
            async let b: Void = devices.refresh()
            async let c: Void = appSettingsVM.fetchSettings()
            async let d: Void = authVM.fetchBannedPhones()
            _ = await (a, b, c, d)
        }
    }

    // MARK: إشارات الحالة — رقم↗ لبيته

    private var statusTiles: some View {
        let s = appSettingsVM.settings
        let ready = s.updatedAt != nil
        let reach = devices.stats
        let banned = authVM.bannedPhones.count
        return HStack(spacing: DS.Spacing.sm) {
            AdminTapWrap(tap: .page { AnyView(AdminSmsView().adminArea(.team)) },
                         label: AnyView(AdminKPITile(
                            value: sms.status?.balance.map { L10n.t("\(SmsBalanceText.points($0)) نقطة", "\(SmsBalanceText.points($0)) pts") } ?? "—",
                            label: sms.status == nil ? L10n.t("رصيد الرسائل", "SMS balance")
                                                     : L10n.t("الرصيد · \(sms.level.title)", "Balance · \(sms.level.title)"),
                            icon: "ellipsis.message", tint: sms.level == .good ? DS.Color.textOnPrimary : sms.level.bandTint)))
            AdminTapWrap(tap: .page { AnyView(AdminRegistrationBansView()) },
                         label: AnyView(AdminKPITile(
                            value: ready ? (s.allowNewRegistrations ? L10n.t("مسموح", "Open") : L10n.t("مغلق", "Closed")) : "—",
                            label: banned > 0 ? L10n.t("التسجيل · \(banned) ممنوعة", "Sign-up · \(banned) blocked")
                                              : L10n.t("التسجيل", "Sign-up"),
                            icon: "person.badge.plus",
                            tint: ready && !s.allowNewRegistrations ? DS.Hub.kpiLate : DS.Hub.kpiMine)))
            AdminTapWrap(tap: .page { AnyView(AdminPushHealthView()) },
                         label: AnyView(AdminKPITile(
                            value: reach.map { L10n.t("\($0.reachPercent)٪", "\($0.reachPercent)%") } ?? "—",
                            label: L10n.t("وصول الإشعارات", "Notification reach"),
                            icon: "bell.badge",
                            tint: (reach?.reachShare ?? 1) < 0.7 ? DS.Hub.kpiLate : DS.Color.textOnPrimary)))
        }
        .padding(.top, DS.Spacing.lg)
    }
}

/// «فريق الإدارة»: عدد كل دور (المالك · المدراء · المراقبون · المشرفون) — البطاقة كلها تفتح صفحة الفريق (بيته)
struct AdminTeamCard: View {
    @EnvironmentObject var memberVM: MemberViewModel

    private struct Cell: Identifiable {
        let id: String
        let label: String
        let count: Int
        let tint: Color
    }

    private var cells: [Cell] {
        let staff = memberVM.allMembers.filter { $0.isDeceased != true }
        func n(_ role: FamilyMember.UserRole) -> Int { staff.filter { $0.role == role }.count }
        func tint(_ role: FamilyMember.UserRole) -> Color { RoleGuide.forRole(role)?.color ?? role.color }
        return [
            Cell(id: "owner", label: L10n.t("المالك", "Owner"), count: n(.owner), tint: tint(.owner)),
            Cell(id: "admin", label: L10n.t("المدراء", "Admins"), count: n(.admin), tint: tint(.admin)),
            Cell(id: "monitor", label: L10n.t("المراقبون", "Monitors"), count: n(.monitor), tint: tint(.monitor)),
            Cell(id: "supervisor", label: L10n.t("المشرفون", "Supervisors"), count: n(.supervisor), tint: tint(.supervisor))
        ]
    }

    var body: some View {
        let loaded = !memberVM.allMembers.isEmpty
        AdminTapWrap(tap: .page { AnyView(AdminModeratorsView()) }, feel: .plain, label: AnyView(
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                AdminCardHeader(title: L10n.t("فريق الإدارة", "Admin team")) {
                    AdminCardLinkLabel(title: L10n.t("عرض الفريق", "View the team"))
                }
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(cells) { cell in
                        VStack(spacing: DS.Spacing.xxs) {
                            Text(verbatim: loaded ? "\(cell.count)" : "—")
                                .dsFont(.statValue)
                                .monospacedDigit()
                                .foregroundColor(cell.tint.dsReadableGlyph)
                            Text(cell.label)
                                .dsFont(.caption)
                                .foregroundColor(DS.Color.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(DS.Color.cardBackgroundSoft))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(cell.label): \(loaded ? "\(cell.count)" : "—")")
                    }
                }
                Text(L10n.t("وفيها صلاحيات الأدوار — المسموح وغير المسموح لكل دور", "With role permissions — what each role is and isn’t allowed"))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .adminCard()),
            accessibilityLabel: nil)
    }
}
