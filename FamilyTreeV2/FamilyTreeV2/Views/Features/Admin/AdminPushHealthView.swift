import SwiftUI
import Supabase

// MARK: - Admin Push Health — فحص حالة الإشعارات

struct AdminPushHealthView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel

    @State private var stats: PushHealthStats?
    @State private var tokenOwners: [TokenOwnerEntry] = []
    @State private var missingMembers: [FamilyMember] = []
    @State private var isLoading = true
    @State private var isSendingTest = false
    @State private var testResultMessage: String?
    @State private var testResultIsSuccess = false
    @State private var lastRefresh: Date?
    @State private var tokenOwnersExpanded = false
    @State private var missingMembersExpanded = false
    @State private var isCleaningUp = false
    @State private var cleanupResultMessage: String?
    @State private var cleanupResultIsSuccess = false

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.xxl) {
                    overviewSection
                        .padding(.top, DS.Spacing.md)

                    tokenHealthSection

                    tokenOwnersSection

                    environmentBreakdownSection

                    lastActivitySection

                    testPushSection

                    cleanupSection

                    Spacer(minLength: DS.Spacing.xxxl)
                }
            }
            .refreshable { await loadStats() }

            if isLoading && stats == nil {
                ProgressView()
                    .tint(DS.Color.primary)
            }
        }
        .navigationTitle(L10n.t("فحص الإشعارات", "Push Health"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await loadStats() }
    }

    // MARK: - Overview
    private var overviewSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("نظرة عامة", "Overview"),
                icon: "chart.bar.fill",
                iconColor: DS.Color.primary
            )

            HStack(spacing: DS.Spacing.md) {
                miniStat(
                    value: "\(stats?.totalDevices ?? 0)",
                    label: L10n.t("أجهزة", "Devices"),
                    icon: "iphone",
                    color: DS.Color.primary
                )

                miniStat(
                    value: "\(stats?.validTokens ?? 0)",
                    label: L10n.t("رمز صالح", "Valid"),
                    icon: "checkmark.seal.fill",
                    color: DS.Color.success
                )

                miniStat(
                    value: "\(stats?.invalidTokens ?? 0)",
                    label: L10n.t("رمز غير صالح", "Invalid"),
                    icon: "xmark.seal.fill",
                    color: stats?.invalidTokens == 0 ? DS.Color.textTertiary : DS.Color.error
                )
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Environment Breakdown
    private var environmentBreakdownSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("التوزيع حسب البيئة", "Environment Breakdown"),
                icon: "arrow.triangle.branch",
                iconColor: DS.Color.accent
            )

            VStack(spacing: 0) {
                infoRow(
                    icon: "hammer.fill",
                    iconColor: DS.Color.warning,
                    label: L10n.t("Sandbox (تطوير)", "Sandbox (Debug)"),
                    value: "\(stats?.sandboxCount ?? 0)"
                )

                DSDivider()

                infoRow(
                    icon: "checkmark.shield.fill",
                    iconColor: DS.Color.success,
                    label: L10n.t("Production (إنتاج)", "Production (Release)"),
                    value: "\(stats?.productionCount ?? 0)"
                )
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Token Health
    private var tokenHealthSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("صحة رموز التسجيل", "Token Health"),
                icon: "heart.text.square.fill",
                iconColor: DS.Color.error
            )

            VStack(spacing: 0) {
                infoRow(
                    icon: "doc.text.fill",
                    iconColor: DS.Color.info,
                    label: L10n.t("رموز تسجيل فارغة", "Empty Tokens"),
                    value: "\(stats?.emptyTokens ?? 0)",
                    valueColor: (stats?.emptyTokens ?? 0) > 0 ? DS.Color.warning : DS.Color.textPrimary
                )

                DSDivider()

                infoRow(
                    icon: "clock.badge.exclamationmark.fill",
                    iconColor: DS.Color.warning,
                    label: L10n.t("رموز قديمة (أكثر من 30 يوم)", "Stale (>30 days)"),
                    value: "\(stats?.staleTokens ?? 0)",
                    valueColor: (stats?.staleTokens ?? 0) > 0 ? DS.Color.warning : DS.Color.textPrimary
                )

                DSDivider()

                let rate = stats?.healthPercentage ?? 0
                let rateColor: Color = rate >= 90 ? DS.Color.success : (rate >= 70 ? DS.Color.warning : DS.Color.error)
                infoRow(
                    icon: "percent",
                    iconColor: rateColor,
                    label: L10n.t("معدل الصحة", "Health Rate"),
                    value: "\(rate)%",
                    valueColor: rateColor
                )
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Last Activity
    private var lastActivitySection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("النشاط الأخير", "Recent Activity"),
                icon: "clock.fill",
                iconColor: DS.Color.secondary
            )

            VStack(spacing: 0) {
                infoRow(
                    icon: "arrow.up.circle.fill",
                    iconColor: DS.Color.success,
                    label: L10n.t("آخر تسجيل جهاز", "Last device registered"),
                    value: formatRelative(stats?.lastDeviceRegisteredAt)
                )

                DSDivider()

                infoRow(
                    icon: "bell.badge.fill",
                    iconColor: DS.Color.primary,
                    label: L10n.t("آخر إشعار مرسل", "Last notification sent"),
                    value: formatRelative(stats?.lastNotificationSentAt)
                )

                if let refresh = lastRefresh {
                    DSDivider()
                    infoRow(
                        icon: "arrow.clockwise",
                        iconColor: DS.Color.textTertiary,
                        label: L10n.t("آخر فحص", "Last refreshed"),
                        value: formatRelative(refresh)
                    )
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Test Push
    private var testPushSection: some View {
        VStack(spacing: DS.Spacing.sm) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("اختبار الإرسال", "Test Delivery"),
                    icon: "paperplane.fill",
                    iconColor: DS.Color.neonBlue
                )

                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text(L10n.t(
                        "اختبر استلام إشعار على جهازك الحالي. النتيجة تظهر فوراً.",
                        "Test push delivery to your current device. Result shows instantly."
                    ))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                    .padding(.horizontal, DS.Spacing.lg)

                    Button {
                        Task { await sendTestPush() }
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            if isSendingTest {
                                ProgressView().tint(DS.Color.textOnPrimary)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(DS.Font.scaled(14, weight: .bold))
                            }
                            Text(L10n.t("أرسل إشعار تجريبي", "Send Test Push"))
                                .font(DS.Font.calloutBold)
                        }
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(DS.Color.gradientPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    }
                    .disabled(isSendingTest)
                    .buttonStyle(DSScaleButtonStyle())
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.md)

                    if let msg = testResultMessage {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: testResultIsSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .font(DS.Font.scaled(14, weight: .bold))
                            Text(msg)
                                .font(DS.Font.caption1)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(testResultIsSuccess ? DS.Color.success : DS.Color.error)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.sm)
                        .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    // MARK: - Manual Cleanup
    private var cleanupSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("تنظيف رموز التسجيل", "Cleanup Tokens"),
                icon: "trash.fill",
                iconColor: DS.Color.warning
            )

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text(L10n.t(
                    "يحذف التوكنات الفاضية وغير الصالحة والأجهزة اللي ما تحدثت منذ 60 يوم. شغّله وقت الحاجة.",
                    "Removes empty, invalid, and stale (60+ days) tokens. Run when needed."
                ))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Spacing.lg)

                Button {
                    Task { await runCleanup() }
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        if isCleaningUp {
                            ProgressView().tint(DS.Color.textOnPrimary)
                        } else {
                            Image(systemName: "trash.fill")
                                .font(DS.Font.scaled(14, weight: .bold))
                        }
                        Text(L10n.t("تنظيف الآن", "Clean Now"))
                            .font(DS.Font.calloutBold)
                    }
                    .foregroundColor(DS.Color.textOnPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Color.warning)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                }
                .disabled(isCleaningUp)
                .buttonStyle(DSScaleButtonStyle())
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.md)

                if let msg = cleanupResultMessage {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: cleanupResultIsSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .font(DS.Font.scaled(14, weight: .bold))
                        Text(msg)
                            .font(DS.Font.caption1)
                            .fontWeight(.medium)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundColor(cleanupResultIsSuccess ? DS.Color.success : DS.Color.error)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.sm)
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Token Owners (+ Missing Members as collapsible subsections)
    private var tokenOwnersSection: some View {
        DSCard(padding: 0) {
            // ـــــــــــــــــــــــــــــــ
            // أصحاب التوكنات — Collapsible
            // ـــــــــــــــــــــــــــــــ
            Button {
                withAnimation(DS.Anim.snappy) { tokenOwnersExpanded.toggle() }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("person.2.badge.gearshape", color: DS.Color.primary, size: 30, iconSize: 13)

                    Text(L10n.t("الأجهزة المسجلة", "Token Owners"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)

                    Spacer()

                    Text("\(tokenOwners.count)")
                        .font(DS.Font.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.primary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(DS.Color.primary.opacity(0.12))
                        .clipShape(Capsule())

                    Image(systemName: "chevron.down")
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.textTertiary)
                        .rotationEffect(.degrees(tokenOwnersExpanded ? 180 : 0))
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSBoldButtonStyle())

            if tokenOwnersExpanded {
                DSDivider()

                if tokenOwners.isEmpty {
                    VStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .font(DS.Font.scaled(24))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا يوجد أجهزة مسجلة", "No registered devices"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DS.Spacing.xl)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(tokenOwners.enumerated()), id: \.element.id) { idx, owner in
                            tokenOwnerRow(owner: owner)
                            if idx < tokenOwners.count - 1 {
                                DSDivider()
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }

            DSDivider()

            // ـــــــــــــــــــــــــــــــ
            // بدون تسجيل إشعارات — Collapsible
            // ـــــــــــــــــــــــــــــــ
            Button {
                withAnimation(DS.Anim.snappy) { missingMembersExpanded.toggle() }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("bell.slash.fill", color: DS.Color.warning, size: 30, iconSize: 13)

                    Text(L10n.t("بدون تسجيل إشعارات", "No Push Registration"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)

                    Spacer()

                    Text("\(missingMembers.count)")
                        .font(DS.Font.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(missingMembers.isEmpty ? DS.Color.success : DS.Color.warning)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 2)
                        .background((missingMembers.isEmpty ? DS.Color.success : DS.Color.warning).opacity(0.12))
                        .clipShape(Capsule())

                    Image(systemName: "chevron.down")
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.textTertiary)
                        .rotationEffect(.degrees(missingMembersExpanded ? 180 : 0))
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSBoldButtonStyle())

            if missingMembersExpanded {
                DSDivider()

                if missingMembers.isEmpty {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(DS.Font.scaled(14, weight: .bold))
                            .foregroundColor(DS.Color.success)
                        Text(L10n.t("جميع الأعضاء النشطين مسجلون ✓", "All active members registered ✓"))
                            .font(DS.Font.caption1)
                            .fontWeight(.medium)
                            .foregroundColor(DS.Color.success)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.md)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(missingMembers.enumerated()), id: \.element.id) { idx, member in
                            missingMemberRow(member: member)
                            if idx < missingMembers.count - 1 {
                                DSDivider()
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func tokenOwnerRow(owner: TokenOwnerEntry) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            // Avatar
            ZStack {
                Circle()
                    .fill(DS.Color.surface)
                    .frame(width: 34, height: 34)

                if let urlStr = owner.avatarUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { ProgressView() }
                    .frame(width: 30, height: 30).clipShape(Circle())
                } else {
                    Text(String(owner.fullName.prefix(1)))
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(owner.fullName)
                    .font(DS.Font.callout)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: DS.Spacing.xs) {
                    Text(owner.deviceName)
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)

                    Text("·")
                        .foregroundColor(DS.Color.textTertiary)

                    Text(formatRelative(owner.updatedAt))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }

            Spacer()

            // Environment pill
            HStack(spacing: 3) {
                Image(systemName: owner.environment == "sandbox" ? "hammer.fill" : "checkmark.shield.fill")
                    .font(DS.Font.scaled(9, weight: .bold))
                Text(owner.environment == "sandbox" ? L10n.t("تطوير", "Sandbox") : L10n.t("إنتاج", "Prod"))
                    .font(DS.Font.caption2)
                    .fontWeight(.bold)
            }
            .foregroundColor(owner.environment == "sandbox" ? DS.Color.warning : DS.Color.success)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 3)
            .background((owner.environment == "sandbox" ? DS.Color.warning : DS.Color.success).opacity(0.12))
            .clipShape(Capsule())

            // Validity dot
            Circle()
                .fill(owner.isValid ? DS.Color.success : DS.Color.error)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
    }

    private func missingMemberRow(member: FamilyMember) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DS.Color.warning.opacity(0.1))
                    .frame(width: 34, height: 34)

                if let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { ProgressView() }
                    .frame(width: 30, height: 30).clipShape(Circle())
                } else {
                    Text(String(member.fullName.prefix(1)))
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(DS.Color.warning)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(member.fullName)
                    .font(DS.Font.callout)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: DS.Spacing.xs) {
                    Text(member.roleName)
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textSecondary)

                    if let phone = member.phoneNumber, !phone.isEmpty {
                        Text("·")
                            .foregroundColor(DS.Color.textTertiary)
                        Text(KuwaitPhone.display(phone))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textTertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Image(systemName: "bell.slash")
                .font(DS.Font.scaled(12, weight: .bold))
                .foregroundColor(DS.Color.warning)
                .frame(width: 24, height: 24)
                .background(DS.Color.warning.opacity(0.12))
                .clipShape(Circle())
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - UI helpers

    private func miniStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(DS.Font.scaled(18, weight: .bold))
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12))
                .clipShape(Circle())

            Text(value)
                .font(DS.Font.title3)
                .fontWeight(.black)
                .foregroundColor(DS.Color.textPrimary)

            Text(label)
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func infoRow(
        icon: String,
        iconColor: Color,
        label: String,
        value: String,
        valueColor: Color = DS.Color.textPrimary
    ) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: iconColor)

            Text(label)
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)

            Spacer()

            Text(value)
                .font(DS.Font.calloutBold)
                .foregroundColor(valueColor)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }

    private func formatRelative(_ date: Date?) -> String {
        guard let date else { return L10n.t("لا يوجد", "None") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Data loading

    private func loadStats() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let rows: [DeviceTokenRow] = try await SupabaseConfig.client
                .from("device_tokens")
                .select("member_id, token, platform, environment, device_name, updated_at")
                .order("updated_at", ascending: false)
                .execute()
                .value

            let notifs: [NotificationTimestampRow] = try await SupabaseConfig.client
                .from("notifications")
                .select("created_at")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            stats = PushHealthStats(rows: rows, lastNotification: notifs.first?.createdAt)

            // بناء قائمة أصحاب التوكنات مع أسمائهم من MemberViewModel
            tokenOwners = rows.compactMap { row in
                guard let memberUUID = UUID(uuidString: row.memberId) else { return nil }
                let member = memberVM.member(byId: memberUUID)
                let tokenLen = (row.token ?? "").count
                return TokenOwnerEntry(
                    id: "\(row.memberId)-\(row.deviceName ?? "unknown")",
                    memberId: memberUUID,
                    fullName: member?.fullName ?? L10n.t("عضو غير معروف", "Unknown member"),
                    avatarUrl: member?.avatarUrl,
                    deviceName: row.deviceName ?? L10n.t("جهاز غير معروف", "Unknown device"),
                    environment: row.environment ?? "production",
                    isValid: tokenLen > 20,
                    updatedAt: row.updatedDate
                )
            }

            // بناء قائمة الأعضاء النشطين اللي ما عندهم توكن
            let registeredMemberIds = Set(rows.compactMap { UUID(uuidString: $0.memberId) })
            missingMembers = memberVM.allMembers
                .filter { member in
                    // نشط = عنده رقم هاتف + status != pending + role != pending
                    let hasPhone = !(member.phoneNumber ?? "").isEmpty
                    let isActive = member.status != .pending && member.role != .pending
                    let notRegistered = !registeredMemberIds.contains(member.id)
                    return hasPhone && isActive && notRegistered
                }
                .sorted { $0.fullName < $1.fullName }

            lastRefresh = Date()
        } catch {
            Log.error("[PushHealth] فشل جلب الإحصائيات: \(error.localizedDescription)")
        }
    }

    // MARK: - Test push

    private func sendTestPush() async {
        guard !isSendingTest else { return }
        guard let memberId = authVM.currentUser?.id else {
            testResultMessage = L10n.t("لا يوجد مستخدم حالي", "No current user")
            testResultIsSuccess = false
            return
        }

        isSendingTest = true
        testResultMessage = nil
        defer { isSendingTest = false }

        // نستخدم نفس المسار اللي يستخدمه التطبيق — sendPushToMembers
        await notificationVM.sendPushToMembers(
            title: L10n.t("اختبار إشعار ✓", "Test Notification ✓"),
            body: L10n.t(
                "إذا وصلك هذا الإشعار، المنظومة تعمل بشكل كامل.",
                "If you received this, the system is fully working."
            ),
            kind: "test",
            targetMemberIds: [memberId]
        )

        withAnimation {
            testResultMessage = L10n.t(
                "تم الإرسال — تحقق من جهازك خلال ثوانٍ",
                "Sent — check your device within a few seconds"
            )
            testResultIsSuccess = true
        }

        // إعادة تحميل الإحصائيات بعد الاختبار
        await loadStats()
    }

    // MARK: - Manual cleanup

    private func runCleanup() async {
        guard !isCleaningUp else { return }

        isCleaningUp = true
        cleanupResultMessage = nil
        defer { isCleaningUp = false }

        struct CleanupResponse: Decodable {
            let ok: Bool
            let before: Int?
            let after: Int?
            let deleted: DeletedCounts?
            struct DeletedCounts: Decodable {
                let invalidTokens: Int?
                let stale: Int?
                let total: Int?
            }
        }

        do {
            let response: CleanupResponse = try await SupabaseConfig.client.functions
                .invoke("cleanup-tokens", options: FunctionInvokeOptions(body: [String: String]()))

            let deleted = response.deleted?.total ?? 0
            let before = response.before ?? 0
            let after = response.after ?? 0

            withAnimation {
                cleanupResultMessage = L10n.t(
                    "تم التنظيف ✓ حُذف \(deleted) رمز تسجيل. قبل: \(before) → بعد: \(after)",
                    "Cleanup done ✓ Deleted \(deleted) tokens. Before: \(before) → After: \(after)"
                )
                cleanupResultIsSuccess = true
            }
            Log.info("[PushHealth] cleanup: deleted=\(deleted), before=\(before), after=\(after)")

            // إعادة تحميل الإحصائيات عشان الأرقام تتحدّث
            await loadStats()
        } catch {
            Log.error("[PushHealth] cleanup failed: \(error.localizedDescription)")
            withAnimation {
                cleanupResultMessage = L10n.t(
                    "فشل التنظيف: \(error.localizedDescription)",
                    "Cleanup failed: \(error.localizedDescription)"
                )
                cleanupResultIsSuccess = false
            }
        }
    }
}

// MARK: - Models

private struct DeviceTokenRow: Decodable {
    let memberId: String
    let token: String?
    let platform: String?
    let environment: String?
    let deviceName: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case memberId = "member_id"
        case token
        case platform
        case environment
        case deviceName = "device_name"
        case updatedAt = "updated_at"
    }

    var updatedDate: Date? {
        guard let updatedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: updatedAt) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: updatedAt)
    }
}

struct TokenOwnerEntry: Identifiable {
    let id: String
    let memberId: UUID
    let fullName: String
    let avatarUrl: String?
    let deviceName: String
    let environment: String
    let isValid: Bool
    let updatedAt: Date?
}

private struct NotificationTimestampRow: Decodable {
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
    }
}

private struct PushHealthStats {
    let totalDevices: Int
    let validTokens: Int
    let invalidTokens: Int
    let emptyTokens: Int
    let staleTokens: Int
    let sandboxCount: Int
    let productionCount: Int
    let lastDeviceRegisteredAt: Date?
    let lastNotificationSentAt: Date?

    var healthPercentage: Int {
        guard totalDevices > 0 else { return 0 }
        return Int((Double(validTokens) / Double(totalDevices)) * 100.0)
    }

    init(rows: [DeviceTokenRow], lastNotification: String?) {
        self.totalDevices = rows.count
        self.emptyTokens = rows.filter { ($0.token ?? "").isEmpty }.count

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        self.staleTokens = rows.filter {
            guard let d = $0.updatedDate else { return true }
            return d < thirtyDaysAgo
        }.count

        self.validTokens = rows.filter { row in
            guard let t = row.token else { return false }
            return t.count > 20
        }.count
        self.invalidTokens = totalDevices - validTokens

        self.sandboxCount = rows.filter { $0.environment == "sandbox" }.count
        self.productionCount = rows.filter { $0.environment == "production" || $0.environment == nil }.count

        self.lastDeviceRegisteredAt = rows.compactMap(\.updatedDate).max()

        if let last = lastNotification {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = formatter.date(from: last) {
                self.lastNotificationSentAt = d
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                self.lastNotificationSentAt = formatter.date(from: last)
            }
        } else {
            self.lastNotificationSentAt = nil
        }
    }
}
