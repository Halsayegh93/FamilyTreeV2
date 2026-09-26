import SwiftUI

/// إعدادات النظام — بتصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧):
/// بطاقة رأس بأرقام حيّة ← «استخدام التطبيق» (شريط توزيع + كل فئة تفتح أعضاءها) ←
/// «الإدارة» (بلاطات مضغوطة بثلاثة أعمدة — طلب المالك). ضُمّ إليها ما كان مبعثراً في
/// اللوحة: فريق الإدارة · إرسال الإشعارات · تحديثات التطبيق — فصارت اللوحة للعمل
/// اليومي وهذه لضبط النظام.
struct AdminSecuritySettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    /// أرقام «استخدام التطبيق» — الأحياء فقط
    @State private var usageStats: AppUsageStats? = AppUsageStats.cached
    @Environment(\.verticalSizeClass) private var vSizeClass

    /// عدد فريق الإدارة — شارة على مربّع الفريق، كما كانت في اللوحة.
    private var moderatorCount: Int {
        memberVM.allMembers.filter {
            ($0.role == .owner || $0.role == .admin || $0.role == .monitor || $0.role == .supervisor)
                && $0.isDeceased != true && $0.status != .frozen
        }.count
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    hero

                    // صفحة واحدة (طلب المالك): استخدام التطبيق أولاً، ثم «الإدارة»
                    // (الإعدادات، الفريق، الأجهزة، … النشاط، الإشعارات).
                    usageSection

                    managementSection
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xxxl)
            }
        }
        .navigationTitle(L10n.t("إعدادات النظام", "System Settings"))
        .task { usageStats = await AppUsageStats.fetch() }
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - بطاقة الرأس

    private var hero: some View {
        DSPageHero(
            title: L10n.t("إعدادات النظام", "System Settings"),
            subtitle: authVM.canManageSettings
                ? L10n.t("الإدارة وصحة النظام والاستخدام", "Management, health & usage")
                : L10n.t("تتصفّح للقراءة — التعديل للمالك", "Read-only — the owner edits"),
            icon: "lock.shield.fill",
            tint: DS.Color.actionNavy,
            stats: [
                DSHeroStat(value: totalUsers.map { "\($0)" } ?? "—",
                           label: L10n.t("إجمالي المستخدمين", "Total users"), icon: "person.2.fill"),
                DSHeroStat(value: usageStats.map { "\($0.active)" } ?? "—",
                           label: L10n.t("فعّال", "Active"), icon: "checkmark.seal.fill"),
                DSHeroStat(value: "\(moderatorCount)",
                           label: L10n.t("فريق الإدارة", "Admin team"), icon: "person.3.fill")
            ]
        )
    }

    // MARK: - استخدام التطبيق (طلب المالك)
    // العضو الفعّال = رقم جوال + جهاز دخل التطبيق. الأحياء فقط.

    /// إجمالي المستخدمين = كل من سجّل دخول للتطبيق (فعّال + خامل + دخل بلا جهاز)
    private var totalUsers: Int? {
        guard let u = usageStats else { return nil }
        return u.active + u.idle + u.loginNoDevice
    }

    private var usageSection: some View {
        DSComposerSection(title: L10n.t("استخدام التطبيق", "App usage"),
                          icon: "chart.bar.fill",
                          tint: DS.Color.composerProject,
                          trailing: totalUsers.map { L10n.t("إجمالي المستخدمين \($0.formatted())",
                                                             "Total users \($0.formatted())") },
                          index: 0) {
            // لمحة التوزيع — كل فئة بلونها وبنسبتها
            if let u = usageStats {
                SysDistributionBar(segments: AppUsageCategory.allCases.map {
                    SysDistributionBar.Segment(id: $0.rawValue, value: u.value(for: $0), tint: $0.color)
                })
            }

            Text(L10n.t("الأحياء · فعّال = دخل خلال ٢١ يوم", "Alive · active = last 21 days"))
                .font(DS.Font.plex(11, weight: .medium))
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // الصف الأول: من دخل التطبيق (فعّال، خامل، بلا جهاز) — الثاني: من لم يدخل
            HStack(spacing: DS.Spacing.sm) {
                usageLink(.active)
                usageLink(.idle)
                usageLink(.loginNoDevice)
            }
            HStack(spacing: DS.Spacing.sm) {
                usageLink(.neverLogged)
                usageLink(.noPhone)
            }
        }
    }

    private func usageLink(_ category: AppUsageCategory) -> some View {
        NavigationLink {
            AppUsageMembersView(category: category)
        } label: {
            usageTile(category)
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel("\(category.title): \(usageValue(category).map { "\($0)" } ?? "—")")
    }

    private func usageTile(_ category: AppUsageCategory) -> some View {
        VStack(spacing: 3) {
            Image(systemName: category.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(category.color)
                .frame(width: 26, height: 26)
                .background(Circle().fill(category.color.opacity(0.13)))
                .accessibilityHidden(true)
            Text(usageValue(category).map { "\($0)" } ?? "—")
                .font(DS.Font.plex(16, weight: .bold))
                .foregroundColor(DS.Color.fieldLabel)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(category.title)
                .font(DS.Font.plex(10.5, weight: .semibold))
                .foregroundColor(DS.Color.fieldValue)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.sm)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(category.color.opacity(0.28), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private func usageValue(_ category: AppUsageCategory) -> Int? {
        usageStats?.value(for: category)
    }

    // MARK: - الإدارة — مربّعات مضغوطة بثلاثة أعمدة (طلب المالك)

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm, alignment: .top),
              count: vSizeClass == .compact ? 4 : 3)
    }

    private var managementSection: some View {
        DSComposerSection(title: L10n.t("الإدارة", "Management"),
                          icon: "gearshape.2.fill",
                          tint: DS.Color.actionNavy,
                          trailing: authVM.canManageSettings ? nil : L10n.t("للقراءة", "Read-only"),
                          index: 1) {
            LazyVGrid(columns: gridColumns, spacing: DS.Spacing.sm) {
                AdminTile(
                    title: L10n.t("إعدادات التطبيق", "App Settings"),
                    subtitle: L10n.t("اللغة · التسجيل · الميزات", "Language · Sign-up · Features"),
                    icon: "gearshape.fill",
                    color: DS.Color.actionNavy, compact: true
                ) {
                    AdminAppSettingsView()
                        .environmentObject(authVM)
                        .environmentObject(memberVM)
                        .environmentObject(appSettingsVM)
                        .environmentObject(notificationVM)
                }

                // الترتيب (طلب المالك): الإعدادات، الفريق، الأجهزة — ثم الباقي
                if authVM.canModerate {
                    AdminTile(
                        title: L10n.t("فريق الإدارة", "Admin Team"),
                        subtitle: L10n.t("الأدوار والصلاحيات", "Roles & permissions"),
                        icon: "person.3.fill",
                        color: DS.Color.actionNavy,
                        badge: moderatorCount, compact: true
                    ) {
                        AdminModeratorsView()
                            .environmentObject(authVM)
                            .environmentObject(memberVM)
                    }
                }

                if authVM.isAdmin {
                    // «النشاط الآن» جنب «فريق الإدارة» (طلب المالك)
                    AdminTile(
                        title: L10n.t("النشاط الآن", "Live Activity"),
                        subtitle: L10n.t("الدخول والحضور وآخر نشاط", "Sign-ins & recent activity"),
                        icon: "person.2.fill",
                        color: DS.Color.composerProject, compact: true
                    ) {
                        AdminActiveMembersView()
                            .environmentObject(authVM)
                            .environmentObject(memberVM)
                            .environmentObject(notificationVM)
                    }

                    AdminTile(
                        title: L10n.t("الأجهزة", "Devices"),
                        subtitle: L10n.t("المرتبطة بالحسابات", "Linked to accounts"),
                        icon: "iphone.gen3",
                        color: DS.Color.actionNavy, compact: true
                    ) {
                        AdminDevicesView()
                            .environmentObject(authVM)
                            .environmentObject(notificationVM)
                            .environmentObject(memberVM)
                    }

                    AdminTile(
                        title: L10n.t("التحديث الإجباري", "Force Update"),
                        subtitle: L10n.t("إيقاف النسخ القديمة", "Block old versions"),
                        icon: "arrow.down.app.fill",
                        color: DS.Color.actionNavy, compact: true
                    ) {
                        AdminForceUpdateView()
                            .environmentObject(authVM)
                            .environmentObject(appSettingsVM)
                    }

                    // «إرسال إشعارات» + «تحديثات التطبيق» صفحة واحدة
                    AdminTile(
                        title: L10n.t("الإشعارات والتحديثات", "Notifications & Updates"),
                        subtitle: L10n.t("إشعار للأعضاء أو تحديث", "Notify members or announce"),
                        icon: "bell.badge.fill",
                        color: DS.Color.composerDiwaniya, compact: true
                    ) {
                        AdminMessagingHubView()
                            .environmentObject(authVM)
                            .environmentObject(memberVM)
                            .environmentObject(notificationVM)
                    }

                    // انتقلت من «إدارة الأعضاء» — إعداد أمان (التعديل للمالك)
                    AdminTile(
                        title: L10n.t("الأرقام المحظورة", "Banned Numbers"),
                        subtitle: L10n.t("منع التسجيل برقم", "Block sign-up by number"),
                        icon: "phone.down.fill",
                        color: DS.Color.error, compact: true
                    ) {
                        AdminBannedPhonesView()
                            .environmentObject(authVM)
                    }

                    AdminTile(
                        title: L10n.t("حالة الإشعارات", "Push Status"),
                        subtitle: L10n.t("جاهزية الإرسال واختبار الوصول", "Delivery readiness & testing"),
                        icon: "bell.and.waves.left.and.right.fill",
                        color: DS.Color.composerDiwaniya, compact: true
                    ) {
                        AdminPushHealthView()
                            .environmentObject(authVM)
                            .environmentObject(memberVM)
                            .environmentObject(notificationVM)
                    }
                }
            }
        }
    }
}
