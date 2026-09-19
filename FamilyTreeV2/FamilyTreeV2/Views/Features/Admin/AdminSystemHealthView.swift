import SwiftUI
import Supabase

struct AdminSystemHealthView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: SystemHealthSnapshot?
    @State private var loading = false
    @State private var failure: String?
    @State private var updatedAt: Date?

    var body: some View {
        Group {
            if authVM.isAdmin {
                SystemHealthOverviewContent(snapshot: snapshot, loading: loading, failure: failure, updatedAt: updatedAt) {
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
    static let sections: [Self] = [.server, .activity, .devices, .push]

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
        case .activity: return L10n.t("نشاط الأعضاء", "Member activity")
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
            VStack(spacing: 0) {
                ForEach(SystemHealthDestination.sections, id: \.self) { destination in
                    NavigationLink(destination: destination.screen) { sectionRow(destination) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("health.section.\(destination.rawValue)")
                    if destination != SystemHealthDestination.sections.last {
                        Divider().padding(.leading, 36 + DS.Spacing.md * 2)
                    }
                }
            }
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.xl).stroke(DS.Color.cardBorder, lineWidth: DS.Border.width))
        }
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
            return ("\(data.membership.in_system.formatted())/\(data.membership.total_members.formatted())", DS.Color.textSecondary)
        case .push:
            return data.diagnostics.dispatch_healthy
                ? (L10n.t("يعمل", "OK"), DS.Color.success)
                : (L10n.t("متوقف", "Down"), DS.Color.warning)
        case .devices:
            return nil
        }
    }

    private func sectionRow(_ destination: SystemHealthDestination) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: destination.icon)
                .font(DS.Font.scaled(15, weight: .semibold))
                .foregroundStyle(destination.color)
                .frame(width: 36, height: 36)
                .background(destination.color.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.md))
            Text(destination.title)
                .font(DS.Font.calloutBold).foregroundStyle(DS.Color.textPrimary)
            Spacer(minLength: 0)
            if let (value, color) = summary(for: destination) {
                Text(value)
                    .font(DS.Font.calloutBold).monospacedDigit()
                    .foregroundStyle(color)
            }
            Image(systemName: "chevron.forward").font(DS.Font.caption1).foregroundStyle(DS.Color.textTertiary)
        }
        .padding(DS.Spacing.md)
        .contentShape(Rectangle())
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
