import SwiftUI

/// إعدادات النظام — مربّعات بنفس لغة لوحة الإدارة (AdminTile) بدل صفوف داخل
/// بطاقات. ضُمّ إليها ما كان مبعثراً في اللوحة: فريق الإدارة · إرسال الإشعارات
/// · تحديثات التطبيق — فصارت اللوحة للعمل اليومي وهذه لضبط النظام.
struct AdminSecuritySettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    /// أرقام «استخدام التطبيق» — الأحياء فقط
    @State private var usageStats: AppUsageStats? = AppUsageStats.cached

    /// عدد فريق الإدارة — شارة على مربّع الفريق، كما كانت في اللوحة.
    private var moderatorCount: Int {
        memberVM.allMembers.filter {
            $0.role == .owner || $0.role == .admin || $0.role == .monitor || $0.role == .supervisor
        }.count
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {

                    // صفحة واحدة بقسم واحد (طلب المالك): «الإدارة» — استخدام التطبيق
                    // أولاً، ثم المربّعات (الإعدادات، الفريق، الأجهزة، … النشاط، الإشعارات).
                    sectionHeader(icon: "gearshape.2.fill", color: DS.Color.primary,
                                  title: L10n.t("الإدارة", "Management"), note: nil)
                        .padding(.horizontal, DS.Spacing.lg)

                    // استخدام التطبيق — كل مربّع يفتح أعضاء فئته
                    usageGrid
                        .padding(.horizontal, DS.Spacing.lg)

                    // خط فاصل بين الاستخدام والمربّعات (طلب المالك)
                    Rectangle()
                        .fill(DS.Color.textTertiary.opacity(0.18))
                        .frame(height: 1)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.sm)

                    LazyVGrid(columns: gridColumns, spacing: DS.Spacing.md) {
                        AdminTile(
                            title: L10n.t("إعدادات التطبيق", "App Settings"),
                            subtitle: L10n.t("اللغة · التسجيل · الميزات", "Language · Sign-up · Features"),
                            icon: "gearshape.fill",
                            color: DS.Color.primary, compact: true
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
                                color: DS.Color.neonPurple,
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
                                color: DS.Color.success, compact: true
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
                                color: DS.Color.info, compact: true
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
                                color: DS.Color.warning, compact: true
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
                                color: DS.Color.secondary, compact: true
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
                                color: DS.Color.accent, compact: true
                            ) {
                                AdminPushHealthView()
                                    .environmentObject(authVM)
                                    .environmentObject(memberVM)
                                    .environmentObject(notificationVM)
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    Spacer(minLength: DS.Spacing.xxxl)
                }
                .padding(.top, DS.Spacing.md)
            }
        }
        .navigationTitle(L10n.t("إعدادات النظام", "System Settings"))
        .task { usageStats = await AppUsageStats.fetch() }
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 3)
    }


    // MARK: - استخدام التطبيق (طلب المالك)
    // العضو الفعّال = رقم جوال + جهاز دخل التطبيق. الأحياء فقط.

    /// عنوان قسم موحّد — أيقونة + عنوان + ملاحظة صغيرة على الطرف
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.md), count: 3)
    }

    private func sectionHeader(icon: String, color: Color, title: String, note: String?) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(DS.Font.scaled(12, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(DS.Font.plex(14, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
            Spacer(minLength: 0)
            if let note {
                Text(note)
                    .font(DS.Font.plex(10, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
    }

    /// استخدام التطبيق: صفّ علوي أبرز (فعّال · خامل) ثم صفّ ثلاثي للبقية
    /// إجمالي المستخدمين = كل من سجّل دخول للتطبيق (فعّال + خامل + دخل بلا جهاز)
    private var totalUsers: Int? {
        guard let u = usageStats else { return nil }
        return u.active + u.idle + u.loginNoDevice
    }

    private var usageGrid: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // العنوان + إجمالي المستخدمين (كل من دخل التطبيق: فعّال + خامل + بلا جهاز)
            HStack(spacing: DS.Spacing.xs) {
                Text(L10n.t("استخدام التطبيق", "App usage"))
                    .font(DS.Font.plex(12, weight: .bold))
                    .foregroundColor(DS.Color.textSecondary)
                Text(L10n.t("· الأحياء · فعّال = دخل خلال ٢١ يوم", "· alive · active = last 21 days"))
                    .font(DS.Font.plex(10, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if let total = totalUsers {
                    HStack(spacing: 4) {
                        Text(L10n.t("إجمالي المستخدمين", "Total users"))
                            .font(DS.Font.plex(10.5, weight: .semibold))
                        Text(total.formatted())
                            .font(DS.Font.plex(13, weight: .bold))
                            .monospacedDigit()
                    }
                    .foregroundColor(DS.Color.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(DS.Color.primary.opacity(0.10)))
                }
            }

            // الصف الأول: من دخل التطبيق (فعّال، خامل، بلا جهاز) — الثاني: من لم يدخل
            HStack(spacing: DS.Spacing.sm) {
                usageLink(.active, large: false)
                usageLink(.idle, large: false)
                usageLink(.loginNoDevice, large: false)
            }
            HStack(spacing: DS.Spacing.sm) {
                usageLink(.neverLogged, large: false)
                usageLink(.noPhone, large: false)
            }
        }
    }

    private func usageLink(_ category: AppUsageCategory, large: Bool) -> some View {
        NavigationLink {
            AppUsageMembersView(category: category)
        } label: {
            usageTile(category, large: large)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    private func usageTile(_ category: AppUsageCategory, large: Bool) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            if large {
                ZStack {
                    Circle().fill(category.color.opacity(0.16)).frame(width: 34, height: 34)
                    Image(systemName: category.icon)
                        .font(DS.Font.scaled(14, weight: .bold))
                        .foregroundColor(category.color)
                }
            }
            VStack(alignment: large ? .leading : .center, spacing: 2) {
                if !large {
                    Image(systemName: category.icon)
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(category.color)
                }
                Text(usageValue(category).map { "\($0)" } ?? "—")
                    .font(DS.Font.plex(large ? 20 : 16, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(category.title)
                    .font(DS.Font.plex(10.5, weight: .semibold))
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if large { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: large ? 68 : 76)
        .padding(.horizontal, DS.Spacing.sm)
        .background(category.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(category.color.opacity(0.22), lineWidth: 1)
        )
    }

    private func usageValue(_ category: AppUsageCategory) -> Int? {
        usageStats?.value(for: category)
    }

}
