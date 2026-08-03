import SwiftUI

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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showRegisterMember = true } label: {
                    Image(systemName: "person.badge.plus")
                        .font(DS.Font.scaled(15, weight: .semibold))
                }
                .accessibilityLabel(L10n.t("تسجيل عضو جديد", "Register new member"))
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showBannedPhones = true } label: {
                    Image(systemName: "phone.down.fill")
                        .font(DS.Font.scaled(14, weight: .semibold))
                }
                .accessibilityLabel(L10n.t("الأرقام المحظورة", "Banned numbers"))
            }
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
        }
        .onChange(of: memberVM.allMembers.count) { _ in
            stats = computeStats()
        }
        .navigationDestination(isPresented: $showBannedPhones) {
            AdminBannedPhonesView().environmentObject(authVM)
        }
    }

    // MARK: - نظرة عامة

    private var overviewTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                DSSectionHeader(title: L10n.t("الحسابات", "Accounts"))

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.md), count: 2),
                    spacing: DS.Spacing.md
                ) {
                    statCard(
                        value: stats.total,
                        title: L10n.t("إجمالي الأفراد", "Total members"),
                        icon: "person.3.fill",
                        color: DS.Color.primary
                    ) { selectedTab = .directory }

                    statCard(
                        value: stats.active,
                        title: L10n.t("حسابات مفعّلة", "Active accounts"),
                        icon: "checkmark.seal.fill",
                        color: DS.Color.success
                    ) { selectedTab = .directory }

                    statCard(
                        value: stats.pending,
                        title: L10n.t("بانتظار التفعيل", "Pending activation"),
                        icon: "clock.badge.questionmark",
                        color: DS.Color.primary
                    ) {
                        issueFocus = .all
                        selectedTab = .accounts
                    }

                    if stats.frozen > 0 {
                        statCard(
                            value: stats.frozen,
                            title: L10n.t("مجمّدة", "Frozen"),
                            icon: "snowflake",
                            color: DS.Color.error
                        ) {
                            issueFocus = .all
                            selectedTab = .accounts
                        }
                    }
                }

                // ملاحظة: «الملفات الناقصة» و«النشاط» و«الأجهزة» لا تتكرّر هنا —
                // الناقصة هي نفسها فلاتر تاب «الحسابات»، والنشاط والأجهزة تحت «صحة النظام».
                DSSectionHeader(title: L10n.t("جودة البيانات", "Data quality"))

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 2),
                    spacing: DS.Spacing.sm
                ) {
                    statCard(
                        value: stats.noBirthDate,
                        title: L10n.t("بلا تاريخ ميلاد", "No birth date"),
                        icon: "calendar.badge.exclamationmark",
                        color: DS.Color.accent
                    ) {
                        issueFocus = .noBirthDate
                        selectedTab = .accounts
                    }

                    statCard(
                        value: stats.noGender,
                        title: L10n.t("بلا جنس محدّد", "No gender"),
                        icon: "person.fill.questionmark",
                        color: DS.Color.neonPurple
                    ) {
                        issueFocus = .noGender
                        selectedTab = .accounts
                    }

                    statCard(
                        value: stats.accountNoPhoto,
                        title: L10n.t("صاحب حساب بلا صورة", "Account without photo"),
                        icon: "person.crop.circle.badge.questionmark",
                        color: DS.Color.secondary
                    ) {
                        issueFocus = .noPhoto
                        selectedTab = .accounts
                    }

                    statCard(
                        value: stats.deceasedNoDeathDate,
                        title: L10n.t("متوفّى بلا تاريخ وفاة", "Deceased, no death date"),
                        icon: "leaf.fill",
                        color: DS.Color.textSecondary
                    ) {
                        issueFocus = .deceasedNoDeathDate
                        selectedTab = .accounts
                    }
                }
            }
            .padding(DS.Spacing.lg)
        }
    }

    private struct MemberStats {
        var total = 0, active = 0, pending = 0, frozen = 0
        var noBirthDate = 0, noFather = 0
        var noGender = 0, deceasedNoDeathDate = 0
        /// أصحاب الحسابات (لهم رقم) بلا صورة — المقياس الوحيد ذو المعنى للصور
        var accountNoPhoto = 0
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
            case .none:    break
            }
            // جودة البيانات تُحتسب على الأحياء فقط
            guard m.isDeceased != true else { continue }
            if (m.birthDate ?? "").trimmingCharacters(in: .whitespaces).isEmpty { s.noBirthDate += 1 }
            if m.fatherId == nil { s.noFather += 1 }
            if (m.gender ?? "").trimmingCharacters(in: .whitespaces).isEmpty { s.noGender += 1 }
            // الصورة تُحتسب على أصحاب الحسابات فقط — بقية أفراد الشجرة ليسوا مستخدمين
            let hasAccount = !(m.phoneNumber ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            if hasAccount, (m.avatarUrl ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
               m.avatarUnavailable != true {
                s.accountNoPhoto += 1
            }
        }
        // المتوفّون بلا تاريخ وفاة — يُحتسبون خارج شرط الأحياء أعلاه
        for m in memberVM.allMembers where m.isDeceased == true {
            if (m.deathDate ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
               m.deathDateUnknown != true {
                s.deceasedNoDeathDate += 1
            }
        }
        return s
    }

    /// «الأرقام المحظورة» — زر في الشريط بدل تاب فرعي
    @State private var showBannedPhones = false

    private func statCard(
        value: Int,
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.md) {
                ZStack {
                    Circle().fill(color.opacity(0.14))
                    Image(systemName: icon)
                        .font(DS.Font.scaled(14, weight: .semibold))
                        .foregroundColor(color)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 0) {
                    Text("\(value)")
                        .font(DS.Font.plex(20, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(title)
                        .font(DS.Font.scaled(11, weight: .medium))
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - الحسابات

    private var accountsTab: some View {
        AdminActivateAccountsView(focus: $issueFocus)
            .environmentObject(authVM)
            .environmentObject(memberVM)
            .environmentObject(adminRequestVM)
    }

    // MARK: - Tab Bar — حاوية واحدة بمؤشّر منزلق (بدل ٤ كبسولات منفصلة)

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .padding(3)
        .background(DS.Color.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(DS.Color.textTertiary.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func tabButton(for tab: Tab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(DS.Anim.snappy) { selectedTab = tab }
        } label: {
            Image(systemName: tab.icon)
                .font(DS.Font.scaled(15, weight: .semibold))
                .accessibilityLabel(tab.title)
            .foregroundColor(isSelected ? DS.Color.textOnPrimary : DS.Color.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(isSelected ? tab.color : Color.clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(DSScaleButtonStyle())
    }
}
