import SwiftUI
import Supabase

struct AdminSystemHealthView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: SystemHealthSnapshot?
    @State private var loading = false
    @State private var failure: String?
    @State private var updatedAt: Date?
    /// نشاط الأعضاء بتعريف المالك: فعّال (رقم + جهاز + ٢١ يوم) وخامل
    @State private var usage: AppUsageStats? = AppUsageStats.cached

    var body: some View {
        Group {
            if authVM.isAdmin {
                SystemHealthOverviewContent(snapshot: snapshot, loading: loading, failure: failure, updatedAt: updatedAt, usage: usage) {
                    await refresh()
                }
                .task { await refresh() }
                .onChange(of: scenePhase) { phase in
                    if phase == .active { Task { await refresh() } }
                }
            } else {
                Text(L10n.t("هذه الصفحة مخصصة للمالك والمدير", "This page is available to owners and admins"))
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .navigationTitle(L10n.t("صحة النظام", "System Health"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    @MainActor private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        // مستقل عن باقي الملخص — فشله لا يُسقط الصفحة
        usage = await AppUsageStats.fetch()
        do {
            async let operations: HealthOperations = SupabaseConfig.client.rpc("operational_health").execute().value
            async let diagnostics: HealthDiagnostics = SupabaseConfig.client.rpc("app_diagnostics_dashboard").execute().value
            async let membership: HealthMembership = SupabaseConfig.client.rpc("admin_membership_counts").execute().value
            let (o, d, m) = try await (operations, diagnostics, membership)
            snapshot = SystemHealthSnapshot(operations: o, diagnostics: d, membership: m)
            updatedAt = Date()
            failure = nil
        } catch {
            if !Log.isCancellation(error) {
                failure = L10n.t("تعذر تحديث الملخص. اسحب لإعادة المحاولة؛ البيانات السابقة قد تكون قديمة.", "Could not refresh the overview. Pull to retry; previous data may be stale.")
            }
        }
    }
}

nonisolated struct HealthOperations: Decodable {
    let cron_failures: Int
    let http_failures: Int
    let pending_deletions: Int
}
nonisolated struct HealthDiagnostics: Decodable {
    nonisolated struct Job: Decodable {
        let name: String
        let status: String
        var active: Bool? = nil
        var configuration_needs_repair: Bool? = nil
    }
    let open_groups: Int
    let total_occurrences: Int
    let dispatch_healthy: Bool
    let jobs: [Job]
}
nonisolated struct HealthMembership: Decodable {
    let in_system: Int
    let total_members: Int
}
struct SystemHealthSnapshot {
    let operations: HealthOperations
    let diagnostics: HealthDiagnostics
    let membership: HealthMembership
    var failedJobs: Int { diagnostics.jobs.filter { $0.status == "failed" }.count }
    var successfulJobs: Int { diagnostics.jobs.filter { $0.status == "succeeded" }.count }
    var needsAttention: Bool {
        failedJobs > 0 || !diagnostics.dispatch_healthy
            || operations.http_failures > 0 || operations.pending_deletions > 0
            || diagnostics.jobs.contains { $0.active == false || $0.configuration_needs_repair == true }
    }
}

enum SystemHealthDestination: String, Hashable {
    case errors, allErrors, activity, devices, push, server, successfulJobs, failedJobs, operations
    // «أخطاء التطبيق» أُزيلت من صحة النظام (طلب المالك)
    // «الأجهزة» انتقلت إلى «إعدادات النظام» (طلب المالك)
    static let sections: [Self] = [.activity, .push, .server]

    @ViewBuilder var screen: some View {
        switch self {
        case .errors: AdminAppErrorsView(showAll: false)
        case .allErrors: AdminAppErrorsView(showAll: true)
        case .activity: AdminActiveMembersView()
        case .devices: AdminDevicesView()
        case .push: AdminPushHealthView()
        case .server: AdminServerHealthView()
        case .operations: AdminServerHealthView(operationsFirst: true)
        case .successfulJobs: AdminServerHealthView(initialFilter: .succeeded)
        case .failedJobs: AdminServerHealthView(initialFilter: .failed)
        }
    }
    var title: String {
        switch self {
        case .errors, .allErrors: return L10n.t("أخطاء التطبيق", "App errors")
        case .activity: return L10n.t("النشاط الآن", "Live activity")
        case .devices: return L10n.t("الأجهزة", "Devices")
        case .push: return L10n.t("الإشعارات", "Notifications")
        case .server, .successfulJobs, .failedJobs, .operations: return L10n.t("مهام السيرفر", "Server jobs")
        }
    }
    var subtitle: String {
        switch self {
        case .errors, .allErrors: return L10n.t("البلاغات ومتابعة تكرارها", "Reports & recurring issues")
        case .activity: return L10n.t("الدخول والحضور وآخر نشاط", "Sign-ins & recent activity")
        case .devices: return L10n.t("الأجهزة المرتبطة بالحسابات", "Devices linked to accounts")
        case .push: return L10n.t("جاهزية الإرسال واختبار الوصول", "Delivery readiness & testing")
        case .server, .successfulJobs, .failedJobs, .operations: return L10n.t("إصلاح المهام وتشغيلها ومتابعة النتائج", "Repair jobs, run them & track results")
        }
    }
    var icon: String {
        switch self {
        case .errors, .allErrors: return "exclamationmark.bubble.fill"
        case .activity: return "person.2.fill"
        case .devices: return "iphone.gen3"
        case .push: return "bell.badge.fill"
        case .server, .successfulJobs, .failedJobs, .operations: return "server.rack"
        }
    }
    var color: Color {
        switch self {
        case .errors, .allErrors: return DS.Color.warning
        case .activity: return DS.Color.secondary
        case .devices: return DS.Color.primary
        case .push: return DS.Color.accent
        case .server, .successfulJobs, .failedJobs, .operations: return DS.Color.info
        }
    }
}

/// Presentation-only overview, shared by the live screen and Xcode previews.
/// تصميم مبسّط (طلب المالك): بطاقة حالة واحدة ← ما يحتاج إجراء (إن وُجد) ← قائمة
/// الأقسام برقم واحد لكل قسم. بلا شبكة مؤشرات ولا عناوين فرعية.
struct SystemHealthOverviewContent: View {
    let snapshot: SystemHealthSnapshot?
    let loading: Bool
    let failure: String?
    let updatedAt: Date?
    var usage: AppUsageStats? = nil
    let refresh: () async -> Void

    private var statusColor: Color {
        guard snapshot != nil, failure == nil else { return DS.Color.textSecondary }
        return snapshot?.needsAttention == true ? DS.Color.warning : DS.Color.success
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                statusCard
                if let failure {
                    Label(failure, systemImage: "wifi.exclamationmark")
                        .font(DS.Font.footnote).foregroundStyle(DS.Color.warning)
                        .padding(DS.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Color.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
                if let snapshot, snapshot.needsAttention { attention(snapshot) }
                sectionsList
            }
            .padding(DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xxl)
        }
        .background(DS.Color.background)
        .refreshable { await refresh() }
    }

    // MARK: - بطاقة الحالة

    private var statusIcon: String {
        if snapshot == nil || failure != nil { return "clock.fill" }
        return snapshot?.needsAttention == true ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
    }

    private var statusTitle: String {
        if failure != nil { return L10n.t("تعذّر التحديث", "Couldn't refresh") }
        guard let snapshot else { return L10n.t("جاري الفحص…", "Checking…") }
        return snapshot.needsAttention ? L10n.t("يحتاج متابعة", "Needs attention") : L10n.t("النظام سليم", "All systems OK")
    }

    private var statusCard: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: statusIcon)
                .font(DS.Font.scaled(22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(statusColor, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(DS.Font.title3).foregroundStyle(DS.Color.textPrimary)
                Text(updatedAt.map { L10n.t("آخر تحديث ", "Updated ") + $0.formatted(date: .omitted, time: .shortened) } ?? " ")
                    .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
            }
            Spacer(minLength: 0)
            Button { Task { await refresh() } } label: {
                Group {
                    if loading { ProgressView() }
                    else { Image(systemName: "arrow.clockwise").font(DS.Font.calloutBold).foregroundStyle(DS.Color.primary) }
                }
                .frame(width: 38, height: 38)
                .background(DS.Color.primary.opacity(0.10), in: Circle())
            }
            .disabled(loading)
            .accessibilityLabel(L10n.t("تحديث صحة النظام", "Refresh system health"))
        }
        .padding(DS.Spacing.lg)
        .background(statusColor.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous).stroke(statusColor.opacity(0.22), lineWidth: 1))
        .animation(DS.Anim.smooth, value: snapshot?.needsAttention)
    }

    // MARK: - يحتاج إجراء

    @ViewBuilder private func attention(_ data: SystemHealthSnapshot) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(L10n.t("يحتاج إجراء", "Needs action"))
                .font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary)
            VStack(spacing: 0) {
                if data.failedJobs > 0 || !data.diagnostics.dispatch_healthy {
                    attentionRow(L10n.t("\(data.failedJobs) مهام سيرفر فشلت", "\(data.failedJobs) server jobs failed"), destination: data.failedJobs > 0 ? .failedJobs : .server)
                }
                if data.diagnostics.jobs.contains(where: { $0.active == false || $0.configuration_needs_repair == true }) {
                    attentionRow(L10n.t("مهام تحتاج إصلاح", "Jobs need repair"), destination: .server)
                }
                if data.operations.http_failures > 0 || data.operations.pending_deletions > 0 {
                    attentionRow(L10n.t("عمليات متأخرة أو فاشلة", "Delayed or failed operations"), destination: .operations)
                }
            }
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.xl).stroke(DS.Color.warning.opacity(0.25), lineWidth: DS.Border.width))
        }
    }

    private func attentionRow(_ title: String, destination: SystemHealthDestination) -> some View {
        NavigationLink(destination: destination.screen) {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(DS.Color.warning)
                Text(title).font(DS.Font.calloutBold).foregroundStyle(DS.Color.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward").font(DS.Font.caption1).foregroundStyle(DS.Color.textTertiary)
            }
            .padding(DS.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - الأقسام — رقم واحد لكل قسم

    private var sectionsList: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(L10n.t("الأقسام", "Sections"))
                .font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 3),
                      spacing: DS.Spacing.sm) {
                ForEach(SystemHealthDestination.sections, id: \.self) { destination in
                    NavigationLink(destination: destination.screen) { sectionTile(destination) }
                        .buttonStyle(DSScaleButtonStyle())
                        .accessibilityIdentifier("health.section.\(destination.rawValue)")
                }
            }
        }
    }

    /// مربّع قسم: أيقونة، القيمة المختصرة بخط كبير، والعنوان
    private func sectionTile(_ destination: SystemHealthDestination) -> some View {
        let value = summary(for: destination)
        return VStack(spacing: 6) {
            Image(systemName: destination.icon)
                .font(DS.Font.scaled(15, weight: .semibold))
                .foregroundStyle(destination.color)
                .frame(width: 34, height: 34)
                .background(destination.color.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.md))
            Text(value?.0 ?? "—")
                .font(DS.Font.plex(17, weight: .bold)).monospacedDigit()
                .foregroundStyle(value?.1 ?? DS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(destination.title)
                .font(DS.Font.plex(11, weight: .semibold))
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .stroke(destination.color.opacity(0.18), lineWidth: 1))
    }

    /// القيمة المختصرة لكل قسم ولونها (برتقالي إن كانت تستدعي انتباهاً)
    private func summary(for destination: SystemHealthDestination) -> (String, Color)? {
        guard let data = snapshot else { return nil }
        switch destination {
        case .errors, .allErrors:
            let n = data.diagnostics.open_groups
            return (n.formatted(), n > 0 ? DS.Color.warning : DS.Color.textSecondary)
        case .server, .successfulJobs, .failedJobs, .operations:
            return ("\(data.successfulJobs)/\(data.diagnostics.jobs.count)",
                    data.failedJobs > 0 ? DS.Color.warning : DS.Color.textSecondary)
        case .activity:
            // الفعّالون بالأرقام في «استخدام التطبيق» — هنا مدخل للحضور اللحظي فقط
            return (L10n.t("عرض", "Open"), DS.Color.secondary)
        case .push:
            return data.diagnostics.dispatch_healthy
                ? (L10n.t("يعمل", "OK"), DS.Color.success)
                : (L10n.t("متوقف", "Down"), DS.Color.warning)
        case .devices:
            return nil
        }
    }

}

struct SystemHealthSectionHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title).font(DS.Font.title1).foregroundStyle(DS.Color.textPrimary)
            Text(subtitle).font(DS.Font.footnote).foregroundStyle(DS.Color.textSecondary)
        }
    }
}


// MARK: - صحة النظام مضمّنة في «إعدادات النظام» (طلب المالك: صفحات أقل)
//
// بدل صفحة «صحة النظام» ثم صفحات داخلها: سطر حالة + ما يحتاج إجراء + ثلاثة
// مربّعات تفتح مباشرة (النشاط الآن، الإشعارات، مهام السيرفر).

struct SystemHealthInlineSection: View {
    @State private var snapshot: SystemHealthSnapshot?
    @State private var loading = false
    @State private var failed = false

    private var statusColor: Color {
        guard let snapshot, !failed else { return DS.Color.textSecondary }
        return snapshot.needsAttention ? DS.Color.warning : DS.Color.success
    }

    private var statusText: String {
        if failed { return L10n.t("تعذّر الفحص", "Couldn't check") }
        guard let snapshot else { return L10n.t("جاري الفحص…", "Checking…") }
        return snapshot.needsAttention ? L10n.t("يحتاج متابعة", "Needs attention") : L10n.t("النظام سليم", "All systems OK")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "waveform.path.ecg")
                    .font(DS.Font.scaled(12, weight: .bold))
                    .foregroundColor(DS.Color.info)
                Text(L10n.t("صحة النظام", "System Health"))
                    .font(DS.Font.plex(14, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Spacer(minLength: 0)
                // الحالة كشارة صغيرة + تحديث
                HStack(spacing: 4) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText)
                        .font(DS.Font.plex(10.5, weight: .bold))
                        .foregroundColor(statusColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(statusColor.opacity(0.12)))
                Button { Task { await refresh() } } label: {
                    Group {
                        if loading { ProgressView().scaleEffect(0.7) }
                        else { Image(systemName: "arrow.clockwise").font(DS.Font.scaled(11, weight: .bold)) }
                    }
                    .foregroundColor(DS.Color.primary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(DS.Color.primary.opacity(0.10)))
                }
                .disabled(loading)
            }

            if let snapshot, snapshot.needsAttention {
                VStack(spacing: 0) {
                    if snapshot.failedJobs > 0 || !snapshot.diagnostics.dispatch_healthy {
                        attentionRow(L10n.t("\(snapshot.failedJobs) مهام سيرفر فشلت", "\(snapshot.failedJobs) server jobs failed"),
                                     destination: snapshot.failedJobs > 0 ? .failedJobs : .server)
                    }
                    if snapshot.diagnostics.jobs.contains(where: { $0.active == false || $0.configuration_needs_repair == true }) {
                        attentionRow(L10n.t("مهام تحتاج إصلاح", "Jobs need repair"), destination: .server)
                    }
                    if snapshot.operations.http_failures > 0 || snapshot.operations.pending_deletions > 0 {
                        attentionRow(L10n.t("عمليات متأخرة أو فاشلة", "Delayed or failed operations"), destination: .operations)
                    }
                }
                .background(DS.Color.warning.opacity(0.07), in: RoundedRectangle(cornerRadius: DS.Radius.lg))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 3),
                      spacing: DS.Spacing.sm) {
                ForEach(SystemHealthDestination.sections, id: \.self) { destination in
                    NavigationLink(destination: destination.screen) { tile(destination) }
                        .buttonStyle(DSScaleButtonStyle())
                }
            }
        }
        .task { await refresh() }
    }

    private func tile(_ destination: SystemHealthDestination) -> some View {
        let value = summary(destination)
        return VStack(spacing: 4) {
            Image(systemName: destination.icon)
                .font(DS.Font.scaled(14, weight: .semibold))
                .foregroundStyle(destination.color)
            Text(value.0)
                .font(DS.Font.plex(15, weight: .bold)).monospacedDigit()
                .foregroundStyle(value.1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(destination.title)
                .font(DS.Font.plex(10.5, weight: .semibold))
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 84)
        .background(destination.color.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(destination.color.opacity(0.22), lineWidth: 1))
    }

    private func summary(_ destination: SystemHealthDestination) -> (String, Color) {
        switch destination {
        case .activity:
            return (L10n.t("عرض", "Open"), DS.Color.secondary)
        case .push:
            guard let snapshot else { return ("—", DS.Color.textSecondary) }
            return snapshot.diagnostics.dispatch_healthy
                ? (L10n.t("يعمل", "OK"), DS.Color.success)
                : (L10n.t("متوقف", "Down"), DS.Color.warning)
        default:
            guard let snapshot else { return ("—", DS.Color.textSecondary) }
            return ("\(snapshot.successfulJobs)/\(snapshot.diagnostics.jobs.count)",
                    snapshot.failedJobs > 0 ? DS.Color.warning : DS.Color.textPrimary)
        }
    }

    private func attentionRow(_ title: String, destination: SystemHealthDestination) -> some View {
        NavigationLink(destination: destination.screen) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(DS.Color.warning)
                Text(title).font(DS.Font.plex(12, weight: .bold)).foregroundStyle(DS.Color.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .font(DS.Font.scaled(10, weight: .bold)).foregroundStyle(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @MainActor private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            async let operations: HealthOperations = SupabaseConfig.client.rpc("operational_health").execute().value
            async let diagnostics: HealthDiagnostics = SupabaseConfig.client.rpc("app_diagnostics_dashboard").execute().value
            async let membership: HealthMembership = SupabaseConfig.client.rpc("admin_membership_counts").execute().value
            let (o, d, m) = try await (operations, diagnostics, membership)
            snapshot = SystemHealthSnapshot(operations: o, diagnostics: d, membership: m)
            failed = false
        } catch {
            if !Log.isCancellation(error) { failed = true }
        }
    }
}
