import SwiftUI
import Supabase

// MARK: - Admin Push Health — فحص حالة الإشعارات
//
// التصميم الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧): بطاقة رأس بأرقام حيّة ← «صحة رموز التسجيل»
// بحلقة نسبة ← التوزيع حسب البيئة بشريط ← النشاط الأخير ← الأجهزة المسجلة / بدون تسجيل
// (قسمان قابلان للطي) ← اختبار الإرسال ← التنظيف. البيانات والإجراءات كما هي.
// بشكل «اليوم» (٢٠٢٦-١٠-٢٠، `AdminPageKit`): الأرقام في الرأس الكحلي («بدون تسجيل» يفتح قائمتهم)،
// والأقسام بطاقات بيضاء صفوفها مفصولة بخط.

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

    private let tint = DS.Color.composerDiwaniya

    var body: some View {
        // بشكل «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠، `AdminPageKit`): رأس كحلي بالأرقام ← «صحة رموز التسجيل»
        // تصعد فوقه ← البطاقات (عمودان أفقياً) — الاختبار والتنظيف متاحان حتى قبل اكتمال الفحص
        AdminPage(header: header, lead: AnyView(leadCard), content: AnyView(cards))
            .refreshable { await loadStats() }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .task { await loadStats() }
    }

    // MARK: - الرأس الكحلي

    /// معدل الصحة في حلقة أول بطاقة — لا يتكرّر هنا
    private var header: AdminPageHeader {
        AdminPageHeader(
            title: L10n.t("وصول الإشعارات", "Notification reach"),
            subtitle: L10n.t("حالة الأجهزة والإرسال في نظرة واضحة", "A clear view of devices and delivery"),
            glyph: "bell.and.waves.left.and.right.fill",
            kpis: [
                AdminPageKPI(stats.map { "\($0.totalDevices)" } ?? "—", L10n.t("أجهزة", "Devices"), icon: "iphone"),
                AdminPageKPI(stats.map { "\($0.validTokens)" } ?? "—", L10n.t("رمز صالح", "Valid"),
                             icon: "checkmark.seal.fill", tint: DS.Hub.kpiMine),
                AdminPageKPI(stats == nil ? "—" : "\(missingMembers.count)", L10n.t("بدون تسجيل", "Unregistered"),
                             icon: "bell.slash.fill",
                             tint: missingMembers.isEmpty ? DS.Color.textOnPrimary : DS.Hub.kpiLate,
                             tap: stats == nil ? .none : .action { openMissing() })
            ])
    }

    /// رقم «بدون تسجيل» يفتح قائمتهم
    private func openMissing() {
        withAnimation(DSMotion.expand) { missingMembersExpanded = true }
    }

    /// أول بطاقة: صحة الرموز — أو الفحص الجاري، أو تعذّر التحميل
    private var leadCard: AnyView {
        if let stats { return AnyView(tokenHealthSection(stats)) }
        if isLoading {
            return AnyView(AdminPageStateCard(.loading(L10n.t("جارٍ فحص الإشعارات…", "Checking notifications…"))))
        }
        return AnyView(AdminPageStateCard(.error(L10n.t("تعذّر تحميل البيانات", "Couldn't load data"),
                                                 message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى",
                                                                 "Check your connection and try again"),
                                                 retry: { Task { await loadStats() } })))
    }

    private var cards: AnyView {
        if let stats {
            // الوضع الأفقي: الأقسام على عمودين
            return AnyView(AdaptiveCardStack(spacing: DS.Hub.stackSpacing, alignment: .leading) {
                AnyView(environmentBreakdownSection(stats))
                AnyView(lastActivitySection)
                AnyView(tokenOwnersSection)
                AnyView(missingMembersSection)
                AnyView(testPushSection)
                AnyView(cleanupSection)
            })
        }
        // الإجراءات متاحة دائماً — حتى قبل اكتمال الفحص
        return AnyView(AdaptiveCardStack(spacing: DS.Hub.stackSpacing, alignment: .leading) {
            AnyView(testPushSection)
            AnyView(cleanupSection)
        })
    }

    // MARK: - صحة رموز التسجيل (النظرة العامة + الصحة)

    private func rateColor(_ rate: Int) -> Color {
        rate >= 90 ? DS.Color.success : (rate >= 70 ? DS.Color.warning : DS.Color.error)
    }

    private func tokenHealthSection(_ stats: PushHealthStats) -> some View {
        let rate = stats.healthPercentage
        let color = rateColor(rate)
        return AdminSectionCard(title: L10n.t("صحة رموز التسجيل", "Token Health"),
                                tag: L10n.t("نظرة عامة", "Overview")) {
            HStack(spacing: DS.Spacing.md) {
                DSRing(progress: Double(rate) / 100, tint: color.dsReadableGlyph, lineWidth: DS.Spacing.sm,
                       size: DS.Icon.ring) {
                    VStack(spacing: 0) {
                        Text("\(rate)%")
                            .dsFont(.statValue)
                            .foregroundColor(DS.Color.textPrimary)
                            .monospacedDigit()
                        Text(L10n.t("معدل الصحة", "Health Rate"))
                            .dsFont(.microCompact)
                            .foregroundColor(DS.Color.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, DS.Spacing.xsm)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(L10n.t("معدل الصحة", "Health Rate")): \(rate)%")

                VStack(spacing: DS.Spacing.xsm) {
                    healthLine(icon: "iphone", tint: AppSection.admin.ink,
                               label: L10n.t("أجهزة", "Devices"), value: stats.totalDevices)
                    healthLine(icon: "checkmark.seal.fill", tint: DS.Color.success,
                               label: L10n.t("رمز صالح", "Valid"), value: stats.validTokens)
                    healthLine(icon: "xmark.seal.fill",
                               tint: stats.invalidTokens == 0 ? DS.Color.textTertiary : DS.Color.error,
                               label: L10n.t("رمز غير صالح", "Invalid"), value: stats.invalidTokens)
                }
            }
            .padding(.bottom, DS.Spacing.xs)

            AdminRowsCardBody {
                AdminInfoRow(icon: "doc.text.fill", tint: DS.Color.info,
                             title: L10n.t("رموز تسجيل فارغة", "Empty Tokens"),
                             trailing: AnyView(countValue(stats.emptyTokens, warnWhenPositive: true)))
                AdminInfoRow(icon: "clock.badge.exclamationmark.fill", tint: DS.Color.warning,
                             title: L10n.t("رموز قديمة (أكثر من 30 يوم)", "Stale (>30 days)"),
                             trailing: AnyView(countValue(stats.staleTokens, warnWhenPositive: true)))
            }
        }
    }

    private func healthLine(icon: String, tint: Color, label: String, value: Int) -> some View {
        HStack(spacing: DS.Spacing.xsm) {
            Image(dsSymbol: icon)
                .dsGlyph(DS.Glyph.xs)
                .foregroundColor(tint)
                .frame(width: DS.Icon.inline)
                .accessibilityHidden(true)
            Text(label)
                .dsFont(.chip)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: DS.Spacing.xs)
            Text("\(value)")
                .dsFont(.headline)
                .foregroundColor(DS.Color.textPrimary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func countValue(_ value: Int, warnWhenPositive: Bool) -> some View {
        AdminRowValue(text: "\(value)",
                      tint: warnWhenPositive && value > 0 ? DS.Color.warning.dsReadableGlyph : DS.Color.textPrimary)
    }

    // MARK: - التوزيع حسب البيئة

    private func environmentBreakdownSection(_ stats: PushHealthStats) -> some View {
        AdminSectionCard(title: L10n.t("التوزيع حسب البيئة", "Environment Breakdown")) {
            DSDistributionBar(segments: [
                .init(id: "production", value: stats.productionCount, tint: DS.Color.success),
                .init(id: "sandbox", value: stats.sandboxCount, tint: DS.Color.warning)
            ])

            AdminRowsCardBody {
                AdminInfoRow(icon: "checkmark.shield.fill", tint: DS.Color.success,
                             title: L10n.t("Production (إنتاج)", "Production (Release)"),
                             trailing: AnyView(countValue(stats.productionCount, warnWhenPositive: false)))
                AdminInfoRow(icon: "hammer.fill", tint: DS.Color.warning,
                             title: L10n.t("Sandbox (تطوير)", "Sandbox (Debug)"),
                             trailing: AnyView(countValue(stats.sandboxCount, warnWhenPositive: false)))
            }
        }
    }

    // MARK: - Last Activity

    private var lastActivitySection: some View {
        AdminSectionCard(title: L10n.t("النشاط الأخير", "Recent Activity"), spacing: 0) {
            AdminRowsCardBody {
                AdminInfoRow(icon: "arrow.up.circle.fill", tint: DS.Color.success,
                             title: L10n.t("آخر تسجيل جهاز", "Last device registered"),
                             trailing: AnyView(relativeValue(stats?.lastDeviceRegisteredAt)))
                AdminInfoRow(icon: "bell.badge.fill", tint: AppSection.admin.ink,
                             title: L10n.t("آخر إشعار مرسل", "Last notification sent"),
                             trailing: AnyView(relativeValue(stats?.lastNotificationSentAt)))
                if let refresh = lastRefresh {
                    AdminInfoRow(icon: "arrow.clockwise", tint: DS.Color.textTertiary,
                                 title: L10n.t("آخر فحص", "Last refreshed"),
                                 trailing: AnyView(relativeValue(refresh)))
                }
            }
        }
    }

    private func relativeValue(_ date: Date?) -> some View {
        AdminValueChip(text: formatRelative(date), tint: DS.Color.primary)
    }

    // MARK: - الأجهزة المسجلة (قابل للطي)

    private var tokenOwnersSection: some View {
        AdminSectionCard(title: L10n.t("الأجهزة المسجلة", "Token Owners"),
                         badge: tokenOwners.count, badgeTint: DS.Color.primary, spacing: 0,
                         isOpen: $tokenOwnersExpanded) {
            if tokenOwners.isEmpty {
                AdminInfoRow(icon: "person.crop.circle.badge.xmark", tint: DS.Color.textTertiary,
                             title: L10n.t("لا يوجد أجهزة مسجلة", "No registered devices"))
            } else {
                AdminLazyRows(items: tokenOwners) { AnyView(tokenOwnerRow(owner: $0)) }
            }
        }
    }

    // MARK: - بدون تسجيل إشعارات (قابل للطي)

    private var missingMembersSection: some View {
        AdminSectionCard(title: L10n.t("بدون تسجيل إشعارات", "No Push Registration"),
                         badge: missingMembers.count, spacing: 0,
                         isOpen: $missingMembersExpanded) {
            if missingMembers.isEmpty {
                AdminInfoRow(icon: "checkmark.seal.fill", tint: DS.Color.success,
                             title: L10n.t("جميع الأعضاء النشطين مسجلون ✓", "All active members registered ✓"))
            } else {
                AdminLazyRows(items: missingMembers) { AnyView(missingMemberRow(member: $0)) }
            }
        }
    }

    /// صورة العضو الموحّدة (`DSMemberAvatar`) — كانت دائرة يدوية بدوّارة أثناء التحميل
    private func avatar(url: String?, initial: String, tint: Color) -> some View {
        DSMemberAvatar(name: initial, avatarUrl: url, size: DS.Icon.row, roleColor: tint)
            .accessibilityHidden(true)
    }

    private func tokenOwnerRow(owner: TokenOwnerEntry) -> some View {
        let sandbox = owner.environment == "sandbox"
        return HStack(spacing: DS.Spacing.sm) {
            avatar(url: owner.avatarUrl, initial: String(owner.fullName.prefix(1)), tint: AppSection.admin.ink)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(owner.fullName)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .dsNameLines()
                Text("\(owner.deviceName) · \(formatRelative(owner.updatedAt))")
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: DS.Spacing.xs)

            // البيئة
            DSStatusChip(text: sandbox ? L10n.t("تطوير", "Sandbox") : L10n.t("إنتاج", "Prod"),
                          icon: sandbox ? "hammer.fill" : "checkmark.shield.fill",
                          tint: sandbox ? DS.Color.warning : DS.Color.success)

            // صلاحية الرمز
            Circle()
                .fill(owner.isValid ? DS.Color.success : DS.Color.error)
                .frame(width: DS.Icon.legendDot, height: DS.Icon.legendDot)
                .accessibilityHidden(true)
        }
        .padding(.vertical, DS.Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityValue(owner.isValid ? L10n.t("رمز صالح", "Valid") : L10n.t("رمز غير صالح", "Invalid"))
    }

    private func missingMemberRow(member: FamilyMember) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            avatar(url: member.avatarUrl, initial: String(member.fullName.prefix(1)), tint: DS.Color.warning)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(member.displayFullName)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: DS.Spacing.xs) {
                    Text(member.roleName)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                    if let phone = member.phoneNumber, !phone.isEmpty {
                        Text("·")
                            .foregroundColor(DS.Color.textTertiary)
                        Text(KuwaitPhone.display(phone))
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textTertiary)
                            .lineLimit(1)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
            }

            Spacer(minLength: DS.Spacing.xs)

            DSStateIcon("bell.slash.fill", tint: DS.Color.warning, size: DS.Icon.section)
        }
        .padding(.vertical, DS.Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Test Push

    private var testPushSection: some View {
        AdminSectionCard(title: L10n.t("اختبار الإرسال", "Test Delivery")) {
            Text(L10n.t(
                "اختبر استلام إشعار على جهازك الحالي. النتيجة تظهر فوراً.",
                "Test push delivery to your current device. Result shows instantly."
            ))
            .dsFont(.footnote)
            .foregroundColor(DS.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            DSActionButton(title: L10n.t("أرسل إشعار تجريبي", "Send Test Push"),
                            icon: "paperplane.fill",
                            isBusy: isSendingTest) {
                Task { await sendTestPush() }
            }

            if let msg = testResultMessage {
                resultRow(msg, success: testResultIsSuccess)
            }
        }
    }

    // MARK: - Manual Cleanup

    private var cleanupSection: some View {
        AdminSectionCard(title: L10n.t("تنظيف رموز التسجيل", "Cleanup Tokens")) {
            Text(L10n.t(
                "يحذف رموز التسجيل التالفة فقط (الفاضية أو الناقصة). أجهزة الأعضاء الخاملين تبقى حتى تصلهم الإشعارات.",
                "Removes broken (empty or truncated) tokens only. Idle members' devices are kept so they still get notifications."
            ))
            .dsFont(.footnote)
            .foregroundColor(DS.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            DSActionButton(title: L10n.t("تنظيف الآن", "Clean Now"),
                            icon: "trash.fill",
                            tint: DS.Color.warning,
                            isBusy: isCleaningUp) {
                Task { await runCleanup() }
            }

            if let msg = cleanupResultMessage {
                resultRow(msg, success: cleanupResultIsSuccess)
            }
        }
    }

    private func resultRow(_ message: String, success: Bool) -> some View {
        DSNoteCard(message, icon: success ? "checkmark.circle.fill" : "xmark.octagon.fill",
                   tint: success ? DS.Color.success : DS.Color.error)
            .transition(.opacity)
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

        // إدراج إشعار اختبار — الـ trigger على جدول notifications يوصّل الـ push
        // (نفس مسار التوصيل الموحّد للتطبيق والويب والأندرويد: APNs + FCM).
        do {
            let payload: [String: AnyEncodable] = [
                "target_member_id": AnyEncodable(memberId.uuidString),
                "title": AnyEncodable(L10n.t("اختبار إشعار ✓", "Test Notification ✓")),
                "body": AnyEncodable(L10n.t(
                    "إذا وصلك هذا الإشعار، المنظومة تعمل بشكل كامل.",
                    "If you received this, the system is fully working."
                )),
                "kind": AnyEncodable("test"),
                "created_by": AnyEncodable(memberId.uuidString)
            ]
            try await SupabaseConfig.client.from("notifications").insert(payload).execute()
        } catch {
            Log.error("[PushHealth] فشل إرسال إشعار الاختبار: \(error.localizedDescription)")
        }

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

    /// تنظيف الرموز التالفة فقط (فاضية أو أقصر من ٢٠ حرفاً).
    /// كانت تستدعي وظيفة cleanup-tokens على السيرفر، لكنها صارت للنظام فقط
    /// فكان الزر يفشل دائماً. وكانت تحذف أيضاً أجهزة من لم يفتح التطبيق ٦٠ يوماً —
    /// وهم الخاملون الذين نحتاج جهازهم لنوصل لهم إشعاراً (طلب المالك).
    /// الحذف هنا مباشر بصلاحية المالك/المدير على device_tokens.
    private func runCleanup() async {
        guard !isCleaningUp else { return }

        isCleaningUp = true
        cleanupResultMessage = nil
        defer { isCleaningUp = false }

        struct Row: Decodable { let id: Int; let token: String? }

        do {
            let rows: [Row] = try await SupabaseConfig.client
                .from("device_tokens")
                .select("id, token")
                .execute()
                .value
            let invalidIds = rows
                .filter { ($0.token ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count < 20 }
                .map(\.id)

            if !invalidIds.isEmpty {
                try await SupabaseConfig.client
                    .from("device_tokens")
                    .delete()
                    .in("id", values: invalidIds)
                    .execute()
            }

            withAnimation {
                cleanupResultMessage = invalidIds.isEmpty
                    ? L10n.t("لا توجد رموز تالفة ✓ (\(rows.count) جهاز سليم)",
                             "No broken tokens ✓ (\(rows.count) devices OK)")
                    : L10n.t("تم التنظيف ✓ حُذف \(invalidIds.count) رمز تالف. قبل: \(rows.count) → بعد: \(rows.count - invalidIds.count)",
                             "Cleanup done ✓ Removed \(invalidIds.count) broken tokens. Before: \(rows.count) → After: \(rows.count - invalidIds.count)")
                cleanupResultIsSuccess = true
            }
            Log.info("[PushHealth] cleanup: removed \(invalidIds.count) broken tokens of \(rows.count)")
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
