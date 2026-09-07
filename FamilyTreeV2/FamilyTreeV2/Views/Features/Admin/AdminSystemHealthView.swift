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

struct HealthOperations: Decodable {
    let cron_failures: Int
    let http_failures: Int
    let pending_deletions: Int
}
struct HealthDiagnostics: Decodable {
    struct Job: Decodable {
        let name: String
        let status: String
    }
    let open_groups: Int
    let total_occurrences: Int
    let dispatch_healthy: Bool
    let jobs: [Job]
}
struct HealthMembership: Decodable {
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
        diagnostics.open_groups > 0 || failedJobs > 0 || !diagnostics.dispatch_healthy
            || operations.http_failures > 0 || operations.pending_deletions > 0
    }
}

enum SystemHealthDestination: String, Hashable {
    case errors, allErrors, activity, devices, push, server, successfulJobs, failedJobs, operations
    static let sections: [Self] = [.errors, .server, .activity, .devices, .push]

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
        case .server, .successfulJobs, .failedJobs, .operations: return L10n.t("نتائج التشغيل وآخر تنفيذ", "Run results & latest execution")
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
struct SystemHealthOverviewContent: View {
    let snapshot: SystemHealthSnapshot?
    let loading: Bool
    let failure: String?
    let updatedAt: Date?
    let refresh: () async -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.md), count: typeSize.isAccessibilitySize ? 1 : 2)
    }
    private var statusColor: Color {
        guard snapshot != nil, failure == nil else { return DS.Color.textSecondary }
        return snapshot?.needsAttention == true ? DS.Color.warning : DS.Color.success
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                hero
                if let failure {
                    Label(failure, systemImage: "wifi.exclamationmark")
                        .font(DS.Font.footnote).foregroundStyle(DS.Color.warning)
                        .padding(DS.Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Color.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    sectionTitle("أقسام المتابعة", "Explore", subtitle: L10n.t("التفاصيل والإجراءات", "Details & actions"))
                    VStack(spacing: 0) {
                        ForEach(SystemHealthDestination.sections, id: \.self) { destination in
                            NavigationLink(destination: destination.screen) { destinationRow(destination) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("health.section.\(destination.rawValue)")
                            if destination != SystemHealthDestination.sections.last {
                                Divider().padding(.leading, DS.Icon.size + DS.Spacing.xxl)
                            }
                        }
                    }.background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.xl).stroke(DS.Color.cardBorder, lineWidth: DS.Border.width))
                }
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    sectionTitle("ملخص سريع", "At a glance", subtitle: L10n.t("أرقام من النظام مباشرة", "Directly from the system"))
                    LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                        metric(title: L10n.t("داخل المنظومة", "In the system"), value: snapshot.map { $0.membership.in_system.formatted() }, detail: snapshot.map { L10n.t("من \($0.membership.total_members.formatted()) عضو معتمد", "of \($0.membership.total_members.formatted()) approved members") } ?? L10n.t("سجّلوا الدخول فعلياً", "Have actually signed in"), icon: "person.badge.shield.checkmark.fill", color: DS.Color.secondary, destination: .activity)
                        metric(title: L10n.t("تحتاج مراجعة", "Needs review"), value: snapshot.map { $0.diagnostics.open_groups.formatted() }, detail: L10n.t("مجموعات أخطاء · ٧ أيام", "Error groups · 7 days"), icon: "exclamationmark.bubble.fill", color: DS.Color.warning, destination: .errors)
                        metric(title: L10n.t("بلاغات التطبيق", "App reports"), value: snapshot.map { $0.diagnostics.total_occurrences.formatted() }, detail: L10n.t("آخر ٧ أيام", "Last 7 days"), icon: "waveform.path", color: DS.Color.primary, destination: .allErrors)
                        metric(title: L10n.t("مهام ناجحة", "Successful jobs"), value: snapshot.map { "\($0.successfulJobs) / \($0.diagnostics.jobs.count)" }, detail: L10n.t("حسب آخر تشغيل مكتمل", "Latest completed run"), icon: "checkmark.seal.fill", color: DS.Color.accent, destination: .successfulJobs)
                    }
                }
                if let snapshot { attention(snapshot) }
                Label(L10n.t("يتحدث الملخص عند فتح الصفحة أو الرجوع للتطبيق أو السحب للتحديث", "Updated when you open this page, return to the app, or pull to refresh"), systemImage: "arrow.down.circle")
                    .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
                    .frame(maxWidth: .infinity)
            }.padding(DS.Spacing.lg).padding(.bottom, DS.Spacing.xxl)
        }
        .background(DS.Color.background)
        .refreshable { await refresh() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            HStack {
                Label(L10n.t("مركز المتابعة", "SYSTEM OVERVIEW"), systemImage: "waveform.path.ecg")
                    .font(DS.Font.caption1.weight(.bold)).foregroundStyle(DS.Color.primary)
                Spacer()
                Button { Task { await refresh() } } label: {
                    Group {
                        if loading { ProgressView() }
                        else { Image(systemName: "arrow.clockwise").font(DS.Font.calloutBold) }
                    }.frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                        .background(DS.Color.surface, in: Circle())
                }.disabled(loading).accessibilityLabel(L10n.t("تحديث صحة النظام", "Refresh system health"))
            }
            HStack(alignment: .center, spacing: DS.Spacing.md) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text(L10n.t("نظرة على نظام العائلة", "Your family system"))
                        .font(DS.Font.title1).foregroundStyle(DS.Color.textPrimary)
                    Label(statusTitle, systemImage: snapshot == nil || failure != nil ? "clock" : snapshot?.needsAttention == true ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(DS.Font.footnote.weight(.semibold)).foregroundStyle(statusColor)
                }
                Spacer(minLength: 0)
                Image(systemName: "shield.lefthalf.filled")
                    .font(DS.Font.scaled(38, weight: .medium)).foregroundStyle(DS.Color.primary.opacity(0.8))
                    .accessibilityHidden(true)
            }
            HStack(spacing: DS.Spacing.xs) {
                Circle().fill(DS.Color.textSecondary).frame(width: 5, height: 5)
                Text(updatedAt.map { L10n.t("آخر تحديث ", "Updated ") + $0.formatted(date: .omitted, time: .shortened) } ?? L10n.t("بانتظار تحميل المؤشرات", "Waiting for system data"))
                    .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
            }
        }.padding(DS.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [DS.Color.primary.opacity(0.10), DS.Color.accent.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: DS.Radius.xxl))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.xxl).stroke(DS.Color.primary.opacity(0.12), lineWidth: DS.Border.width))
    }
    private var statusTitle: String {
        if failure != nil { return L10n.t("حالة البيانات تحتاج تحديث", "Data needs refreshing") }
        guard let snapshot else { return L10n.t("جاري قراءة حالة النظام", "Checking system status") }
        return snapshot.needsAttention ? L10n.t("توجد مؤشرات تحتاج متابعة", "Some indicators need attention") : L10n.t("لا توجد تنبيهات في المؤشرات الحالية", "No alerts in the current indicators")
    }
    private func sectionTitle(_ ar: String, _ en: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(L10n.t(ar, en)).font(DS.Font.title3).foregroundStyle(DS.Color.textPrimary)
            Text(subtitle).font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
        }
    }
    private func metric(title: String, value: String?, detail: String, icon: String, color: Color, destination: SystemHealthDestination) -> some View {
        NavigationLink(destination: destination.screen) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    Image(systemName: icon).font(DS.Font.calloutBold).foregroundStyle(color)
                    Spacer()
                    Image(systemName: "chevron.forward").font(DS.Font.caption2).foregroundStyle(DS.Color.textTertiary)
                }
                Text(value ?? "—").font(DS.Font.hero).monospacedDigit().foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.65)
                Text(title).font(DS.Font.calloutBold).foregroundStyle(DS.Color.textPrimary)
                Text(detail).font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(DS.Spacing.lg)
                .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.xl).stroke(DS.Color.cardBorder, lineWidth: DS.Border.width))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityIdentifier("health.metric.\(destination.rawValue)")
    }
    @ViewBuilder private func attention(_ data: SystemHealthSnapshot) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            sectionTitle("قائمة المتابعة", "Attention list", subtitle: L10n.t("ابدأ بما يحتاج إجراء", "Start with what needs action"))
            VStack(spacing: 0) {
                if data.diagnostics.open_groups > 0 {
                    attentionRow(title: L10n.t("\(data.diagnostics.open_groups) مجموعات أخطاء تحتاج مراجعة", "\(data.diagnostics.open_groups) error groups need review"), detail: L10n.t("راجع البلاغات وآخر ظهور لها", "Review reports and their latest occurrence"), destination: .errors)
                }
                if data.failedJobs > 0 || !data.diagnostics.dispatch_healthy {
                    attentionRow(title: L10n.t("راجع تشغيل مهام السيرفر", "Review server job execution"), detail: L10n.t("\(data.failedJobs) مهام آخر تشغيل لها فشل", "\(data.failedJobs) jobs last completed with a failure"), destination: data.failedJobs > 0 ? .failedJobs : .server)
                }
                if data.operations.http_failures > 0 || data.operations.pending_deletions > 0 {
                    attentionRow(title: L10n.t("عمليات تحتاج متابعة", "Operations need attention"), detail: L10n.t("\(data.operations.http_failures) اتصالات فاشلة خلال ٢٤ ساعة · \(data.operations.pending_deletions) حذف متأخر", "\(data.operations.http_failures) failed HTTP calls in 24h · \(data.operations.pending_deletions) delayed deletions"), destination: .operations)
                }
                if !data.needsAttention {
                    Label(L10n.t("لا توجد تنبيهات مسجلة حالياً", "No alerts currently recorded"), systemImage: "checkmark.circle.fill")
                        .font(DS.Font.callout).foregroundStyle(DS.Color.success).padding(DS.Spacing.lg)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
        }
    }
    private func attentionRow(title: String, detail: String, destination: SystemHealthDestination) -> some View {
        NavigationLink(destination: destination.screen) {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(DS.Color.warning)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(title).font(DS.Font.calloutBold).foregroundStyle(DS.Color.textPrimary)
                    Text(detail).font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward").font(DS.Font.caption1).foregroundStyle(DS.Color.textTertiary)
            }.padding(DS.Spacing.lg).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func destinationRow(_ destination: SystemHealthDestination) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: destination.icon).font(DS.Font.headline).foregroundStyle(destination.color)
                .frame(width: DS.Icon.size, height: DS.Icon.size)
                .background(destination.color.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.Radius.md))
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(destination.title).font(DS.Font.calloutBold).foregroundStyle(DS.Color.textPrimary)
                Text(destination.subtitle).font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(DS.Font.caption1).foregroundStyle(DS.Color.textTertiary)
        }.padding(DS.Spacing.lg).contentShape(Rectangle())
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
