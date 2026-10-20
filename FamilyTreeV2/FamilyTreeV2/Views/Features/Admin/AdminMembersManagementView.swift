import SwiftUI

// MARK: - صفحات «العائلة» — بشكل «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠: «كل الصفحات بنفس شكل «اليوم»»)
//
// كل تبويب قديم صار صفحته (تُفتح من صفّها في قسم «العائلة»، و«رجوع» يعود للقسم): «جودة البيانات» (نظرة) هنا،
// «الحسابات والاستخدام» = محطة التفعيل (`AdminActivateAccountsView`)، «سجل الأعضاء» (`AdminMembersDirectoryView`)،
// «أسماء العوائل» (`AdminFamilyNamesView`). ما كان يقلب التبويب صار يدفع الصفحة نفسها (المحطة على تصنيفها).
// الوجهات والصلاحيات كما كانت تماماً (تسجيل عضو جديد للمالك والمدير فقط).

struct AdminMembersManagementView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel

    enum Tab: Int, CaseIterable {
        // ملاحظة: تاب صحة الشجرة (treeHealth) نُقل إلى قسم «العائلة» → «صحة الشجرة»
        case overview, accounts, directory, families

        var title: String {
            switch self {
            case .overview:   return L10n.t("جودة البيانات", "Data quality")
            case .accounts:   return L10n.t("الحسابات والاستخدام", "Accounts & usage")
            case .directory:  return L10n.t("سجل الأعضاء", "Member registry")
            case .families:   return L10n.t("أسماء العوائل", "Family names")
            }
        }

        var icon: String {
            switch self {
            case .overview:   return "checklist"
            case .accounts:   return "person.crop.circle.badge.checkmark"
            case .directory:  return "person.3.sequence.fill"
            case .families:   return "person.2.crop.square.stack.fill"
            }
        }

        /// وصف رأس الصفحة
        var subtitle: String {
            switch self {
            case .overview:   return L10n.t("الحسابات ونواقص البيانات — كل صفّ يفتح ما خلفه",
                                            "Accounts and data gaps — every row opens what's behind it")
            case .accounts:   return L10n.t("عضو واحد في كل مرة — أكمل نواقصه ثم اسحب للتالي",
                                            "One member at a time — fill the gaps, then swipe to the next")
            case .directory:  return L10n.t("تصفّح الفروع، أو ابحث بالاسم أو الرقم",
                                            "Browse branches, or search by name or phone")
            case .families:   return L10n.t("يختار العضو عائلته منها، وتظهر بآخر اسمه في التطبيق.",
                                            "Members pick from this list; it appears at the end of their name.")
            }
        }
    }

    private let tab: Tab
    /// التصنيف الذي تفتح عليه المحطة (من صفوف «جودة البيانات»)
    @State private var issueFocus: AdminActivateAccountsView.IssueFocus

    /// يُفتح على صفحة بعينها من صفّها في قسم «العائلة» — الافتراضي «جودة البيانات»
    init(initialTab: Tab = .overview, focus: AdminActivateAccountsView.IssueFocus = .all) {
        self.tab = initialTab
        _issueFocus = State(initialValue: focus)
    }

    /// أُحصيت الأرقام مرة على الأقل — قبلها «—» بدل أصفار مضلِّلة
    @State private var statsReady = false
    @State private var stats = MemberStats()

    var body: some View {
        page
            .task {
                if memberVM.allMembers.isEmpty {
                    await memberVM.fetchAllMembers()
                }
                stats = computeStats()
                statsReady = true
            }
            .onChange(of: memberVM.allMembers.count) { _ in
                stats = computeStats()
            }
    }

    private var page: AnyView {
        switch tab {
        case .overview:
            return AnyView(qualityPage)
        case .accounts:
            return AnyView(AdminActivateAccountsView(focus: $issueFocus))
        case .directory:
            return AnyView(AdminMembersDirectoryView())
        case .families:
            return AnyView(AdminFamilyNamesView())
        }
    }

    // MARK: - جودة البيانات (نظرة)

    private var qualityPage: some View {
        AdminPage(header: qualityHeader,
                  lead: AnyView(accountsCard),
                  content: AnyView(qualityContent))
    }

    private func heroValue(_ n: Int) -> String { AdminPageKPI.count(n, ready: statsReady) }

    /// صفحة تُدفع من هنا
    private static func membersPage(_ tab: Tab, focus: AdminActivateAccountsView.IssueFocus = .all) -> AdminPageTap {
        .page { AnyView(AdminMembersManagementView(initialTab: tab, focus: focus)) }
    }

    private var registerTap: AdminPageTap { .page { AnyView(AdminRegisterMemberView()) } }

    private var qualityHeader: AdminPageHeader {
        var actions: [AdminPageAction] = []
        // تسجيل عضو جديد — للمالك والمدير فقط (canRegisterMembers)
        if authVM.canRegisterMembers {
            actions.append(AdminPageAction(symbol: "person.badge.plus",
                                           label: L10n.t("تسجيل عضو جديد", "Register new member"),
                                           tap: registerTap))
        }
        return AdminPageHeader(
            title: Tab.overview.title,
            subtitle: Tab.overview.subtitle,
            glyph: Tab.overview.icon,
            kpis: [
                AdminPageKPI(heroValue(stats.total), L10n.t("الأفراد", "Members"), icon: "person.3",
                             tap: Self.membersPage(.directory)),
                AdminPageKPI(heroValue(stats.active), L10n.t("مفعّلة", "Active"), icon: "checkmark.seal",
                             tint: DS.Hub.kpiMine),
                AdminPageKPI(heroValue(stats.pending), L10n.t("بانتظار", "Pending"), icon: "clock",
                             tint: DS.Hub.kpiLate, tap: Self.membersPage(.accounts)),
                AdminPageKPI(heroValue(qualityGaps), L10n.t("نواقص", "Gaps"), icon: "exclamationmark.circle",
                             tint: DS.Hub.kpiHot)
            ],
            actions: actions)
    }

    // MARK: - الحسابات

    /// «الحسابات»: لمحة التوزيع + صفوف تفتح السجل أو المحطة
    private var accountsCard: some View {
        AdminSectionCard(title: L10n.t("الحسابات", "Accounts"),
                         tag: statsReady ? L10n.t("\(stats.total) فرد", "\(stats.total) members") : nil) {
            if statsReady && stats.active + stats.pending + stats.frozen > 0 {
                accountsGlance
            }
            AdminRowsCardBody {
                AdminTapRow(icon: "person.3.fill", tint: DS.Color.palm,
                            title: L10n.t("إجمالي الأفراد", "Total members"),
                            subtitle: L10n.t("تصفّح السجل بالفروع", "Browse the registry by branch"),
                            value: heroValue(stats.total), valueTint: DS.Color.palm,
                            tap: Self.membersPage(.directory))
                AdminTapRow(icon: "checkmark.seal.fill", tint: DS.Color.success,
                            title: L10n.t("حسابات مفعّلة", "Active accounts"),
                            subtitle: L10n.t("يدخلون التطبيق برقمهم", "Sign in with their number"),
                            value: heroValue(stats.active), valueTint: DS.Color.success,
                            tap: Self.membersPage(.directory))
                AdminTapRow(icon: "clock.badge.questionmark", tint: DS.Color.warning,
                            title: L10n.t("بانتظار التفعيل", "Pending activation"),
                            subtitle: L10n.t("أكمل بياناتهم من محطة الحسابات", "Complete them in the accounts station"),
                            value: heroValue(stats.pending), valueTint: DS.Color.warning,
                            tap: Self.membersPage(.accounts))
                if stats.frozen > 0 {
                    AdminTapRow(icon: "snowflake", tint: DS.Color.error,
                                title: L10n.t("مجمّدة", "Frozen"),
                                subtitle: L10n.t("لا يستطيعون دخول التطبيق", "Can't access the app"),
                                value: heroValue(stats.frozen), valueTint: DS.Color.error,
                                tap: Self.membersPage(.accounts))
                }
            }
        }
    }

    /// لمحة سريعة: شريط بنسب المفعّل / المنتظر / المجمّد + النسب مكتوبة تحته
    private var accountsGlance: some View {
        let sum = max(1, stats.active + stats.pending + stats.frozen)
        func pct(_ v: Int) -> Int { Int((Double(v) / Double(sum) * 100).rounded()) }
        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            DSDistributionBar(segments: [
                .init(id: "active", value: stats.active, tint: DS.Color.success),
                .init(id: "pending", value: stats.pending, tint: DS.Color.warning),
                .init(id: "frozen", value: stats.frozen, tint: DS.Color.error)
            ], height: DS.Hub.meterHeight)
            HStack(spacing: DS.Spacing.md) {
                if stats.active > 0 {
                    legendItem(L10n.t("مفعّلة", "Active"), pct(stats.active), DS.Color.success)
                }
                if stats.pending > 0 {
                    legendItem(L10n.t("بانتظار التفعيل", "Pending"), pct(stats.pending), DS.Color.warning)
                }
                if stats.frozen > 0 {
                    legendItem(L10n.t("مجمّدة", "Frozen"), pct(stats.frozen), DS.Color.error)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.bottom, DS.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ title: String, _ percent: Int, _ color: Color) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Circle().fill(color).frame(width: DS.Icon.legendDotCompact, height: DS.Icon.legendDotCompact)
                .accessibilityHidden(true)
            Text(L10n.t("\(title) \(percent)٪", "\(title) \(percent)%"))
                .dsFont(.caption)
                .foregroundColor(DS.Color.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - جودة البيانات

    private var qualityGaps: Int {
        stats.noBirthDate + stats.noGender + stats.accountNoPhoto + stats.deceasedNoDeathDate
    }

    private var qualityContent: some View {
        VStack(spacing: DS.Hub.stackSpacing) {
            AnyView(dataQualityCard)
            // أكثر إجراء يُطلب من هنا — نفس زرّ الرأس
            if authVM.canRegisterMembers {
                AdminTapWrap(tap: registerTap, label: AnyView(registerButtonFace))
            }
        }
    }

    private var registerButtonFace: some View {
        HStack(spacing: DSBox.buttonSpacing) {
            Image(systemName: "person.badge.plus").dsGlyph(DSButtonSize.regular.glyph)
            Text(L10n.t("تسجيل عضو جديد", "Register new member"))
        }
        .modifier(DSButtonFace())
    }

    private var dataQualityCard: some View {
        AdminSectionCard(title: L10n.t("نواقص البيانات", "Data gaps"),
                         badge: statsReady ? qualityGaps : nil,
                         tag: statsReady && qualityGaps == 0 ? L10n.t("مكتملة", "Complete") : nil) {
            AdminScoreRow(progress: statsReady ? completeness : nil,
                          title: L10n.t("اكتمال البيانات", "Data completeness"),
                          subtitle: L10n.t("الميلاد والجنس وصور الحسابات وتواريخ الوفاة",
                                           "Birth dates, gender, account photos and death dates"))
                .padding(.bottom, DS.Spacing.xs)
            AdminRowsCardBody {
                qualityRow(icon: "calendar.badge.exclamationmark", tint: DS.Color.accent,
                           title: L10n.t("بلا تاريخ ميلاد", "No birth date"),
                           subtitle: L10n.t("من الأحياء", "Living members"),
                           value: stats.noBirthDate, focus: .noBirthDate)
                qualityRow(icon: "person.fill.questionmark", tint: DS.Color.neonPurple,
                           title: L10n.t("بلا جنس محدّد", "No gender"),
                           subtitle: L10n.t("من الأحياء", "Living members"),
                           value: stats.noGender, focus: .noGender)
                qualityRow(icon: "person.crop.circle.badge.questionmark", tint: DS.Color.secondary,
                           title: L10n.t("صاحب حساب بلا صورة", "Account without photo"),
                           subtitle: L10n.t("أصحاب الحسابات فقط", "Account holders only"),
                           value: stats.accountNoPhoto, focus: .noPhoto)
                qualityRow(icon: "leaf.fill", tint: DS.Color.slate,
                           title: L10n.t("متوفّى بلا تاريخ وفاة", "Deceased, no death date"),
                           subtitle: L10n.t("من المتوفّين", "Deceased members"),
                           value: stats.deceasedNoDeathDate, focus: .deceasedNoDeathDate)
            }
        }
    }

    /// نسبة الحقول المكتملة: الميلاد والجنس للأحياء، والصورة لأصحاب الحسابات،
    /// وتاريخ الوفاة للمتوفّين — نفس الأعداد المعروضة في الصفوف أدناه.
    private var completeness: Double {
        let checks = stats.living * 2 + stats.livingAccounts + stats.deceased
        guard checks > 0 else { return 1 }
        return max(0, min(1, 1 - Double(qualityGaps) / Double(checks)))
    }

    /// صف نقص: يفتح محطة «الحسابات» على تصنيفه — «مكتمل» أخضر إذا لا شيء ناقص
    private func qualityRow(icon: String, tint: Color, title: String, subtitle: String,
                            value: Int, focus: AdminActivateAccountsView.IssueFocus) -> some View {
        let done = statsReady && value == 0
        return AdminTapRow(icon: icon, tint: tint, title: title, subtitle: subtitle,
                           value: !statsReady ? "—" : (done ? L10n.t("مكتمل", "Complete") : "\(value)"),
                           valueIcon: done ? "checkmark" : nil,
                           valueTint: !statsReady ? DS.Color.textTertiary : (done ? DS.Color.success : DS.Color.warning),
                           tap: Self.membersPage(.accounts, focus: focus))
    }

    // MARK: - الأرقام

    private struct MemberStats {
        var total = 0, active = 0, pending = 0, frozen = 0
        var noBirthDate = 0, noFather = 0
        var noGender = 0, deceasedNoDeathDate = 0
        /// أصحاب الحسابات (لهم رقم) بلا صورة — المقياس الوحيد ذو المعنى للصور
        var accountNoPhoto = 0
        /// مقامات «اكتمال البيانات»: الأحياء، أصحاب الحسابات منهم، المتوفّون
        var living = 0, livingAccounts = 0, deceased = 0
    }

    private func computeStats() -> MemberStats {
        var s = MemberStats()
        s.total = memberVM.allMembers.count
        for m in memberVM.allMembers {
            switch m.status {
            case .active:  s.active += 1
            case .pending: s.pending += 1
            case .frozen:  s.frozen += 1
            case .deleted, .none:    break
            }
            // جودة البيانات تُحتسب على الأحياء فقط
            guard m.isDeceased != true else { continue }
            s.living += 1
            if (m.birthDate ?? "").trimmingCharacters(in: .whitespaces).isEmpty { s.noBirthDate += 1 }
            if m.fatherId == nil { s.noFather += 1 }
            if (m.gender ?? "").trimmingCharacters(in: .whitespaces).isEmpty { s.noGender += 1 }
            // الصورة تُحتسب على أصحاب الحسابات فقط — بقية أفراد الشجرة ليسوا مستخدمين
            let hasAccount = !(m.phoneNumber ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            if hasAccount { s.livingAccounts += 1 }
            if hasAccount, (m.avatarUrl ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
               m.avatarUnavailable != true {
                s.accountNoPhoto += 1
            }
        }
        // المتوفّون بلا تاريخ وفاة — يُحتسبون خارج شرط الأحياء أعلاه
        for m in memberVM.allMembers where m.isDeceased == true {
            s.deceased += 1
            if (m.deathDate ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
               m.deathDateUnknown != true {
                s.deceasedNoDeathDate += 1
            }
        }
        return s
    }
}
