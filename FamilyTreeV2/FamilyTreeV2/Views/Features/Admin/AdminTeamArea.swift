import SwiftUI

// MARK: - «الفريق والأمان» — أشخاص + حالة الأمان (الدفعة ج من «نفّذ كل المقترح»، ٢٠٢٦-١٠-٢٠؛ العيّنة «أ» ٢٠٢٦-١١-٠٧)
//
// الرأس: سطر حالة واحد («كل شي سليم» أو أول ما يحتاجك ← بيته) + ثلاث حلقات صغيرة بأرقام حيّة، كل واحدة تفتح بيتها
// (رصيد الرسائل · التسجيل · وصول الإشعارات) ← بطاقة «فريق الإدارة» (عدد كل دور ← صفحة الفريق، وفيها «صلاحيات الأدوار»
// و«إضافة» للمالك) ← «الدخول والأمان»: ثلاثة مربّعات بالمنتصف — رسائل رمز الدخول · التسجيل والمنع · الاستخدام والأجهزة
// («الاستخدام والأجهزة» دمجت «الأجهزة ووصول الإشعارات» و«الاستخدام» من «المؤشرات»). المالكان كل شي؛ المدير للاطلاع
// (مقترح «أدوار الإدارة» ٢٠٢٦-١١-٠٧، الجدول من السيرفر `AdminRoleMatrix`): بطاقة الفريق ومربّع «الاستخدام» وحده — بلا
// حلقات الرأس ولا رسائل الدخول ولا التسجيل والمنع ولا الأجهزة (السيرفر يحرسها للمالك).

struct AdminTeamAreaView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var sms = SmsBalanceStore.shared
    @ObservedObject private var devices = AdminDeviceReachStore.shared
    @State private var activeNow: Int?
    @State private var usage: AppUsageStats? = AppUsageStats.cached

    var body: some View {
        let tools = AdminToolCatalog.tools(authVM: authVM, adminRequestVM: adminRequestVM)
            .filter { $0.area == .team && $0.id != "team.members" && !$0.searchOnly }
        AdminHubPage {
            AdminBandHeader(title: AdminArea.team.title, subtitle: AdminArea.team.subtitle, isAreaRoot: true) {
                EmptyView()
            } accessory: {
                if seesSecurity {
                    AnyView(AdminTeamStatusHeader(issues: issues, rings: AnyView(rings)))
                }
            }
        } content: {
            if authVM.adminSees(.teamMembers) {
                AnyView(AdminTeamCard())
            }
            if !tools.isEmpty {
                // مربّعات بالمنتصف بسطر رقمها الحيّ — التنبيه شارة «!» على أيقونة بيته
                AdminToolCards(tools: tools, hints: hints, warnings: warnings, style: .tiles(captions: true))
            }
        }
        // ما يُدفع من الرأس وبطاقة الفريق يرجع باسم القسم
        .environment(\.adminPageTitle, AdminArea.team.title)
        .task {
            guard seesSecurity else {
                // المدير (للاطلاع): رقم «الاستخدام» وحده — نفس الدوال المتاحة له على السيرفر
                guard authVM.adminSees(.teamUsage) else { return }
                async let e: Int? = AdminTodayFetch.activeNowCount()
                async let f: AppUsageStats? = AppUsageStats.fetch()
                activeNow = await e
                if let u = await f { usage = u }
                return
            }
            async let a: Void = sms.refresh()
            async let b: Void = devices.refresh()
            async let c: Void = appSettingsVM.fetchSettings()
            async let d: Void = authVM.fetchBannedPhones()
            async let e: Int? = AdminTodayFetch.activeNowCount()
            async let f: AppUsageStats? = AppUsageStats.fetch()
            _ = await (a, b, c, d)
            activeNow = await e
            if let u = await f { usage = u }
        }
    }

    /// حلقات الرأس وسطر حالته (الرصيد · التسجيل · وصول الإشعارات) — لمن يرى بيوتها الثلاثة (المالك)
    private var seesSecurity: Bool {
        authVM.adminSees(.teamSms) && authVM.adminSees(.teamRegistration) && authVM.adminSees(.teamDevices)
    }

    // MARK: ما يحتاجك — أول واحد في سطر الحالة

    private var issues: [AdminTeamIssue] {
        var list: [AdminTeamIssue] = []
        // بلا رقم — العدد بيته «الأجهزة» في «الاستخدام والأجهزة»، والنسبة حلقة «وصول الإشعارات» تحت (حذف المكرر ٢٠٢٦-١١-٠٧)
        if let invalid = devices.stats?.invalid, invalid > 0 {
            list.append(AdminTeamIssue(text: L10n.t("أجهزة تسجيلها فاشل", "Devices failed to register"),
                                       page: { AnyView(AdminPushHealthView()) }))
        }
        if sms.needsTopUp {
            list.append(AdminTeamIssue(text: L10n.t("رصيد الرسائل \(sms.level.title)", "SMS balance \(sms.level.title)"),
                                       page: { AnyView(AdminSmsView()) }))
        }
        return list
    }

    private var warnings: Set<String> {
        var w: Set<String> = []
        if sms.needsTopUp { w.insert("access.sms") }
        // التسجيلات الفاشلة: سطر الحالة فوق يقولها ويفتح بيتها — بلا «!» ثانية على المربّع
        return w
    }

    /// سطر الرقم الحيّ تحت كل مربّع
    private var hints: [String: String] {
        var h: [String: String] = [:]
        if let today = sms.overview?.today.sends {
            h["access.sms"] = L10n.t("\(today) رسالة اليوم", "\(today) today")
        }
        if appSettingsVM.settings.updatedAt != nil {
            let open = appSettingsVM.settings.allowNewRegistrations
            let banned = authVM.bannedPhones.count
            h["access.registration"] = L10n.t("\(open ? "مسموح" : "مغلق") · \(banned) ممنوعة",
                                              "\(open ? "Open" : "Closed") · \(banned) blocked")
        }
        if let now = activeNow, let active = usage?.active {
            h["access.usage"] = L10n.t("\(now) الآن · \(active) نشط", "\(now) now · \(active) active")
        }
        return h
    }

    // MARK: الحلقات الثلاث — رقم حيّ يفتح بيته

    private var rings: some View {
        let s = appSettingsVM.settings
        let ready = s.updatedAt != nil
        let reach = devices.stats
        let banned = authVM.bannedPhones.count
        let balance = sms.status?.balance
        let lowReach = (reach?.reachShare ?? 1) < 0.7
        let balanceLine: String = {
            if let days = sms.overview?.daysLeft {
                return days >= 60 ? L10n.t("يكفي تقريباً \(days / 30) شهور", "About \(days / 30) months left")
                                  : L10n.t("يكفي تقريباً \(days) يوم", "About \(days) days left")
            }
            return balance == nil ? "—" : L10n.t("الرصيد · \(sms.level.title)", "Balance · \(sms.level.title)")
        }()
        return AdminBandRingRow(columns: [
            AnyView(AdminTapWrap(tap: .page { AnyView(AdminSmsView()) }, label: AnyView(AdminBandRingColumn(
                title: L10n.t("رصيد الرسائل", "SMS balance"), line: balanceLine,
                progress: balance.map { min(1, $0 / SmsBalanceStore.gaugeReference) },
                tint: sms.level == .good ? DS.Hub.statusOk : sms.level.bandTint,
                center: .count(balance.map { Int($0.rounded(.down)) }))))),
            AnyView(AdminTapWrap(tap: .page { AnyView(AdminRegistrationBansView()) }, label: AnyView(AdminBandRingColumn(
                title: ready ? (s.allowNewRegistrations ? L10n.t("التسجيل مسموح", "Sign-up open")
                                                        : L10n.t("التسجيل مغلق", "Sign-up closed"))
                             : L10n.t("التسجيل", "Sign-up"),
                line: L10n.t("\(banned) أرقام ممنوعة", "\(banned) numbers blocked"),
                progress: ready ? 1 : nil,
                tint: ready && !s.allowNewRegistrations ? DS.Hub.kpiLate : DS.Hub.statusOk,
                symbol: ready ? (s.allowNewRegistrations ? "checkmark" : "xmark") : nil)))),
            AnyView(AdminTapWrap(tap: .page { AnyView(AdminPushHealthView()) }, label: AnyView(AdminBandRingColumn(
                title: L10n.t("وصول الإشعارات", "Notification reach"),
                line: reach.map { L10n.t("\($0.reach) من \($0.total) جهاز", "\($0.reach) of \($0.total) devices") } ?? "—",
                progress: reach.map(\.reachShare),
                tint: lowReach ? DS.Hub.kpiLate : DS.Hub.statusOk,
                center: .percent(reach.flatMap { $0.total > 0 ? $0.reachPercent : nil })))))
        ])
    }
}

/// شيء يحتاج المالك في القسم — نصّه وبيته
struct AdminTeamIssue {
    let text: String
    let page: () -> AnyView
}

/// سطر الحالة الواحد فوق الحلقات: «كل شي سليم» أو «شي واحد يحتاجك: …» + «شوف» يفتح بيته
struct AdminTeamStatusHeader: View {
    let issues: [AdminTeamIssue]
    let rings: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if let first = issues.first {
                AdminTapWrap(tap: .page(first.page), label: AnyView(line(text: lead + first.text, ok: false)))
            } else {
                line(text: L10n.t("كل شيء سليم", "All good"), ok: true)
            }
            rings
        }
        .padding(.top, DS.Spacing.md)
    }

    private var lead: String {
        issues.count == 1 ? L10n.t("أمر واحد يحتاج المتابعة: ", "One thing needs you: ")
                          : L10n.t("\(issues.count) أشياء تحتاجك: ", "\(issues.count) things need you: ")
    }

    private func line(text: String, ok: Bool) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Circle().fill(ok ? DS.Hub.statusOk : DS.Hub.kpiLate)
                .frame(width: DS.Hub.statusDot, height: DS.Hub.statusDot)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .dsFont(.hubLabel)
                .monospacedDigit()
                .foregroundColor(DS.Color.textOnPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Spacing.xs)
            if !ok {
                Text(L10n.t("عرض", "View"))
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.accentLight)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Hub.kpiRadius, style: .continuous).fill(DS.Hub.glass))
        .overlay(RoundedRectangle(cornerRadius: DS.Hub.kpiRadius, style: .continuous)
            .strokeBorder(DS.Hub.glassLine, lineWidth: DS.Border.width))
        .accessibilityElement(children: .combine)
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .adminCard()),
            accessibilityLabel: nil)
    }
}
