import SwiftUI

// MARK: - إدارة الأعضاء — بتصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧)
//
// شريط أقسام بعرض الصفحة (نظرة · الحسابات · السجل · العوائل) — المختار كحلي مثل
// الفلاتر — وتحته محتوى القسم، ولكل قسم بطاقة رأسه وأرقامه الحيّة.
// «نظرة»: بطاقة رأس ← «الحسابات» (لمحة توزيع + صفوف تفتح قوائمها) ←
// «جودة البيانات» (حلقة اكتمال + صف لكل نقص يفتح محطة الحسابات على تصنيفه).
// الوجهات والصلاحيات كما كانت تماماً (تسجيل عضو جديد للمالك والمدير فقط).

struct AdminMembersManagementView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel

    enum Tab: Int, CaseIterable {
        // ملاحظة: تاب صحة الشجرة (treeHealth) نُقل إلى "طلبات المراجعة" → قسم "صحة الشجرة"
        case overview, accounts, directory, families

        var title: String {
            switch self {
            case .overview:   return L10n.t("نظرة", "Overview")
            case .accounts:   return L10n.t("الحسابات", "Accounts")
            case .directory:  return L10n.t("السجل", "Registry")
            case .families:   return L10n.t("العوائل", "Families")
            }
        }

        var icon: String {
            switch self {
            case .overview:   return "square.grid.2x2.fill"
            case .accounts:   return "person.crop.circle.badge.exclamationmark"
            case .directory:  return "person.3.sequence.fill"
            case .families:   return "person.2.crop.square.stack.fill"
            }
        }

        var color: Color {
            switch self {
            case .overview:   return DS.Color.secondary
            case .accounts:   return DS.Color.primary
            case .directory:  return DS.Color.primary
            case .families:   return DS.Color.accent
            }
        }
    }

    @State private var selectedTab: Tab = .overview
    @State private var showRegisterMember = false
    /// التصنيف الذي تفتح عليه المحطة عند الضغط على بطاقة جودة بيانات
    @State private var issueFocus: AdminActivateAccountsView.IssueFocus = .all
    /// أُحصيت الأرقام مرة على الأقل — قبلها «—» بدل أصفار مضلِّلة
    @State private var statsReady = false
    @Namespace private var tabNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// لون مجال «الشجرة والأعضاء»
    private let tint = DS.Color.composerProject

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                tabBar
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xs)

                switch selectedTab {
                case .overview:
                    overviewTab

                case .accounts:
                    accountsTab

                case .directory:
                    AdminMembersDirectoryView()
                        .environmentObject(authVM)
                        .environmentObject(memberVM)

                case .families:
                    AdminFamilyNamesView()
                        .environmentObject(authVM)
                }
            }
        }
        .navigationTitle(L10n.t("إدارة الأعضاء", "Members Management"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // تسجيل عضو جديد — نُقل من اللوحة الرئيسية إلى حيث ينتمي
            // للمالك والمدير فقط (canRegisterMembers) — كان يظهر للمراقب
            if authVM.canRegisterMembers {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showRegisterMember = true } label: {
                        Image(systemName: "person.badge.plus")
                            .font(DS.Font.scaled(15, weight: .semibold))
                    }
                    .accessibilityLabel(L10n.t("تسجيل عضو جديد", "Register new member"))
                }
            }
            // «الأرقام المحظورة» انتقلت إلى «إعدادات النظام ← الأمان والوصول»
        }
        .navigationDestination(isPresented: $showRegisterMember) {
            AdminRegisterMemberView()
                .environmentObject(authVM)
                .environmentObject(memberVM)
                .environmentObject(adminRequestVM)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
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

    // MARK: - نظرة عامة

    private var overviewTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                overviewHero

                accountsSection

                // ملاحظة: «الملفات الناقصة» و«النشاط» و«الأجهزة» لا تتكرّر هنا —
                // الناقصة هي نفسها محطة «الحسابات»، والنشاط والأجهزة في «إعدادات النظام».
                dataQualitySection

                // نفس زر الشريط العلوي — ظاهر هنا لأنه أكثر إجراء يُطلب من هذه الصفحة
                if authVM.canRegisterMembers {
                    SysActionButton(title: L10n.t("تسجيل عضو جديد", "Register new member"),
                                    icon: "person.badge.plus") {
                        showRegisterMember = true
                    }
                    .padding(.top, DS.Spacing.xs)
                    .dsStaggerIn(3)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)
            .padding(.bottom, DS.Spacing.xxxl)
        }
    }

    private func heroValue(_ n: Int) -> String { statsReady ? "\(n)" : "—" }

    private var overviewHero: some View {
        DSPageHero(
            title: L10n.t("إدارة الأعضاء", "Members Management"),
            subtitle: L10n.t("الحسابات والسجل والعوائل", "Accounts, registry, families"),
            icon: "person.2.badge.gearshape",
            tint: tint,
            stats: [
                DSHeroStat(value: heroValue(stats.total),
                           label: L10n.t("الأفراد", "Members"), icon: "person.3.fill"),
                DSHeroStat(value: heroValue(stats.active),
                           label: L10n.t("مفعّلة", "Active"), icon: "checkmark.seal.fill"),
                DSHeroStat(value: heroValue(stats.pending),
                           label: L10n.t("بانتظار التفعيل", "Pending"), icon: "clock.badge.questionmark")
            ]
        )
    }

    // MARK: - الحسابات

    private var accountsSection: some View {
        DSComposerSection(title: L10n.t("الحسابات", "Accounts"),
                          icon: "person.crop.circle.badge.checkmark",
                          tint: tint,
                          trailing: statsReady ? L10n.t("\(stats.total) فرد", "\(stats.total) members") : nil,
                          index: 1) {
            if statsReady && stats.active + stats.pending + stats.frozen > 0 {
                accountsGlance
            }

            overviewRow(icon: "person.3.fill", tint: tint,
                        title: L10n.t("إجمالي الأفراد", "Total members"),
                        subtitle: L10n.t("تصفّح السجل بالفروع", "Browse the registry by branch"),
                        value: stats.total, valueTint: tint) {
                selectedTab = .directory
            }

            overviewRow(icon: "checkmark.seal.fill", tint: DS.Color.success,
                        title: L10n.t("حسابات مفعّلة", "Active accounts"),
                        subtitle: L10n.t("يدخلون التطبيق برقمهم", "Sign in with their number"),
                        value: stats.active, valueTint: DS.Color.success) {
                selectedTab = .directory
            }

            overviewRow(icon: "clock.badge.questionmark", tint: DS.Color.warning,
                        title: L10n.t("بانتظار التفعيل", "Pending activation"),
                        subtitle: L10n.t("أكمل بياناتهم من محطة الحسابات", "Complete them in the accounts station"),
                        value: stats.pending, valueTint: DS.Color.warning) {
                issueFocus = .all
                selectedTab = .accounts
            }

            if stats.frozen > 0 {
                overviewRow(icon: "snowflake", tint: DS.Color.error,
                            title: L10n.t("مجمّدة", "Frozen"),
                            subtitle: L10n.t("لا يستطيعون دخول التطبيق", "Can't access the app"),
                            value: stats.frozen, valueTint: DS.Color.error) {
                    issueFocus = .all
                    selectedTab = .accounts
                }
            }
        }
    }

    /// لمحة سريعة: شريط بنسب المفعّل / المنتظر / المجمّد + النسب مكتوبة تحته
    private var accountsGlance: some View {
        let sum = max(1, stats.active + stats.pending + stats.frozen)
        func pct(_ v: Int) -> Int { Int((Double(v) / Double(sum) * 100).rounded()) }
        return VStack(alignment: .leading, spacing: 7) {
            SysDistributionBar(segments: [
                .init(id: "active", value: stats.active, tint: DS.Color.success),
                .init(id: "pending", value: stats.pending, tint: DS.Color.warning),
                .init(id: "frozen", value: stats.frozen, tint: DS.Color.error)
            ])
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
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ title: String, _ percent: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(L10n.t("\(title) \(percent)٪", "\(title) \(percent)%"))
                .font(DS.Font.plex(10.5, weight: .semibold))
                .foregroundColor(DS.Color.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// صف قابل للضغط: أيقونة + عنوان + وصف + العدد + سهم
    private func overviewRow(icon: String, tint: Color, title: String, subtitle: String,
                             value: Int, valueTint: Color,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SysRow(icon: icon, tint: tint, title: title, subtitle: subtitle) {
                SysStatusChip(text: heroValue(value), tint: valueTint)
                SysChevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - جودة البيانات

    private var qualityGaps: Int {
        stats.noBirthDate + stats.noGender + stats.accountNoPhoto + stats.deceasedNoDeathDate
    }

    private var dataQualitySection: some View {
        DSComposerSection(title: L10n.t("جودة البيانات", "Data quality"),
                          icon: "checklist",
                          tint: tint,
                          trailing: !statsReady ? nil
                            : (qualityGaps == 0 ? L10n.t("مكتملة", "Complete")
                                                : L10n.t("\(qualityGaps) نقص", "\(qualityGaps) gaps")),
                          index: 2) {
            completenessRow

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

            qualityRow(icon: "leaf.fill", tint: DS.Color.textSecondary,
                       title: L10n.t("متوفّى بلا تاريخ وفاة", "Deceased, no death date"),
                       subtitle: L10n.t("من المتوفّين", "Deceased members"),
                       value: stats.deceasedNoDeathDate, focus: .deceasedNoDeathDate)
        }
    }

    /// نسبة الحقول المكتملة: الميلاد والجنس للأحياء، والصورة لأصحاب الحسابات،
    /// وتاريخ الوفاة للمتوفّين — نفس الأعداد المعروضة في الصفوف أدناه.
    private var completeness: Double {
        let checks = stats.living * 2 + stats.livingAccounts + stats.deceased
        guard checks > 0 else { return 1 }
        return max(0, min(1, 1 - Double(qualityGaps) / Double(checks)))
    }

    private var completenessRow: some View {
        let pct = Int((completeness * 100).rounded())
        let ringTint = completeness >= 0.9 ? DS.Color.success
            : (completeness >= 0.6 ? DS.Color.warning : DS.Color.error)
        return HStack(spacing: DS.Spacing.md) {
            SysRing(progress: statsReady ? completeness : 0, tint: ringTint, lineWidth: 6, size: 56) {
                Text(statsReady ? L10n.t("\(pct)٪", "\(pct)%") : "—")
                    .dsFieldFont(13, weight: .bold)
                    .foregroundColor(DS.Color.fieldLabel)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("اكتمال البيانات", "Data completeness"))
                    .dsFieldFont(13.5, weight: .bold)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(L10n.t("الميلاد والجنس وصور الحسابات وتواريخ الوفاة",
                            "Birth dates, gender, account photos and death dates"))
                    .dsFieldFont(12)
                    .foregroundColor(DS.Color.fieldValue)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .dsRowBox()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statsReady
                            ? L10n.t("اكتمال البيانات \(pct)٪", "Data completeness \(pct)%")
                            : L10n.t("اكتمال البيانات", "Data completeness"))
    }

    /// صف نقص: يفتح محطة «الحسابات» على تصنيفه — «مكتمل» أخضر إذا لا شيء ناقص
    private func qualityRow(icon: String, tint: Color, title: String, subtitle: String,
                            value: Int, focus: AdminActivateAccountsView.IssueFocus) -> some View {
        Button {
            issueFocus = focus
            selectedTab = .accounts
        } label: {
            SysRow(icon: icon, tint: tint, title: title, subtitle: subtitle) {
                if !statsReady {
                    SysStatusChip(text: "—", tint: DS.Color.textTertiary)
                } else if value == 0 {
                    SysStatusChip(text: L10n.t("مكتمل", "Complete"), icon: "checkmark", tint: DS.Color.success)
                } else {
                    SysStatusChip(text: "\(value)", tint: DS.Color.warning)
                }
                SysChevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
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

    @State private var stats = MemberStats()

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

    // MARK: - الحسابات

    private var accountsTab: some View {
        AdminActivateAccountsView(focus: $issueFocus)
            .environmentObject(authVM)
            .environmentObject(memberVM)
            .environmentObject(adminRequestVM)
    }

    // MARK: - شريط الأقسام — حاوية واحدة، والمختار كحلي ينزلق بين الأقسام

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .padding(3)
        .background(Capsule().fill(DS.Color.surface))
        .overlay(Capsule().strokeBorder(DS.Color.textTertiary.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func tabButton(for tab: Tab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            guard !isSelected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) { selectedTab = tab }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .bold))
                    .accessibilityHidden(true)
                Text(tab.title)
                    .font(DS.Font.plex(12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(isSelected ? .white : DS.Color.textSecondary)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if isSelected {
                    Capsule()
                        .fill(DSActionFill.style())
                        .matchedGeometryEffect(id: "membersTab", in: tabNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
