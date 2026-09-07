import SwiftUI
import Supabase

struct AdminServerHealthView: View {
    @State private var dashboard: ServerHealthDashboard?
    @State private var operations: HealthOperations?
    @State private var loading = false
    @State private var failure: String?
    @State private var filter: ServerHealthFilter
    private let operationsFirst: Bool

    init(initialFilter: ServerHealthFilter = .all, operationsFirst: Bool = false) {
        self.operationsFirst = operationsFirst
        _filter = State(initialValue: initialFilter)
    }

    var body: some View {
        ServerHealthContent(dashboard: dashboard, operations: operations, loading: loading,
                            failure: failure, filter: $filter, operationsFirst: operationsFirst, refresh: load)
            .navigationTitle(L10n.t("مهام السيرفر", "Server jobs"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
    }

    @MainActor private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            async let jobsData = SupabaseConfig.client.rpc("app_diagnostics_dashboard").execute().data
            async let health: HealthOperations = SupabaseConfig.client.rpc("operational_health").execute().value
            let (data, currentHealth) = try await (jobsData, health)
            let currentJobs = try JSONDecoder().decode(ServerHealthDashboard.self, from: data)
            dashboard = currentJobs
            operations = currentHealth
            failure = nil
        } catch {
            if !Log.isCancellation(error) {
                failure = L10n.t("تعذر تحديث مهام السيرفر. أعد المحاولة؛ النتائج السابقة قد تكون قديمة.", "Could not refresh server jobs. Try again; previous results may be stale.")
            }
        }
    }
}

struct ServerHealthContent: View {
    let dashboard: ServerHealthDashboard?
    let operations: HealthOperations?
    let loading: Bool
    let failure: String?
    @Binding var filter: ServerHealthFilter
    var operationsFirst = false
    let refresh: () async -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                HStack(alignment: .top) {
                    SystemHealthSectionHeader(title: L10n.t("تشغيل الخدمات", "Service operations"),
                                              subtitle: L10n.t("المهام المجدولة وآخر نتيجة مكتملة لكل مهمة", "Scheduled jobs and their latest completed results"))
                    Spacer(minLength: DS.Spacing.sm)
                    Button { Task { await refresh() } } label: {
                        Group {
                            if loading { ProgressView() }
                            else { Image(systemName: "arrow.clockwise") }
                        }.frame(width: DS.Icon.size, height: DS.Icon.size)
                            .background(DS.Color.surface, in: Circle())
                    }.disabled(loading).accessibilityLabel(L10n.t("تحديث مهام السيرفر", "Refresh server jobs"))
                }
                if let failure {
                    Label(failure, systemImage: "wifi.exclamationmark")
                        .font(DS.Font.footnote).foregroundStyle(DS.Color.warning)
                }
                if let dashboard {
                    if operationsFirst, let operations { operationsSummary(operations) }
                    dispatcher(dashboard)
                    jobs(dashboard)
                    if !operationsFirst, let operations { operationsSummary(operations) }
                    if let checked = HealthTimestamp.date(dashboard.checked_at) {
                        Label(L10n.t("آخر تحديث: ", "Updated: ") + checked.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                            .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
                    }
                } else if loading {
                    ProgressView(L10n.t("جاري تحميل المهام", "Loading jobs"))
                        .frame(maxWidth: .infinity).padding(DS.Spacing.xxl)
                } else if failure != nil {
                    Button(L10n.t("إعادة المحاولة", "Try again")) { Task { await refresh() } }
                        .buttonStyle(.borderedProminent)
                }
            }.padding(DS.Spacing.lg).padding(.bottom, DS.Spacing.xxl)
        }.background(DS.Color.background)
            .refreshable { await refresh() }
            .accessibilityIdentifier("health.server.screen")
    }

    private func dispatcher(_ data: ServerHealthDashboard) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Label(data.dispatch_healthy ? L10n.t("موزّع الإشعارات يعمل", "Notification dispatcher is running") : L10n.t("موزّع الإشعارات يحتاج متابعة", "Notification dispatcher needs attention"),
                  systemImage: data.dispatch_healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(DS.Font.calloutBold)
            Text(L10n.t("المؤشر يتحقق من نجاح تشغيل الموزّع خلال آخر ٥ دقائق، ولا يثبت وصول كل إشعار للجهاز.", "Checks for a successful dispatcher run in the last 5 minutes; it does not confirm every notification reached a device."))
                .font(DS.Font.caption1)
        }.foregroundStyle(data.dispatch_healthy ? DS.Color.success : DS.Color.warning)
            .frame(maxWidth: .infinity, alignment: .leading).padding(DS.Spacing.lg)
            .background((data.dispatch_healthy ? DS.Color.success : DS.Color.warning).opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.xl))
    }

    private func jobs(_ data: ServerHealthDashboard) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Text(L10n.t("المهام المجدولة", "Scheduled jobs")).font(DS.Font.title3)
                Spacer()
                Text(data.jobs.count.formatted()).font(DS.Font.calloutBold).foregroundStyle(DS.Color.textSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(ServerHealthFilter.allCases, id: \.self) { option in
                        Button { filter = option } label: {
                            Text(option.title + " · " + data.jobs.filter { option.includes($0) }.count.formatted())
                                .font(DS.Font.footnote.weight(.semibold))
                                .padding(.horizontal, DS.Spacing.md).padding(.vertical, DS.Spacing.sm)
                                .foregroundStyle(filter == option ? DS.Color.textOnPrimary : DS.Color.textPrimary)
                                .background(filter == option ? DS.Color.primary : DS.Color.surface, in: Capsule())
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("health.server.filter.\(option.rawValue)")
                            .accessibilityAddTraits(filter == option ? [.isSelected] : [])
                    }
                }
            }
            let visible = data.jobs(matching: filter)
            if visible.isEmpty {
                Label(data.jobs.isEmpty ? L10n.t("لا توجد مهام مجدولة مفعّلة", "No active scheduled jobs") : L10n.t("لا توجد مهام بهذه الحالة", "No jobs with this status"), systemImage: "tray")
                    .font(DS.Font.footnote).foregroundStyle(DS.Color.textSecondary)
                    .frame(maxWidth: .infinity).padding(DS.Spacing.xxl)
                    .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
            }
            ForEach(visible) { job in jobCard(job) }
            Text(L10n.t("الحالة تخص آخر تشغيل مكتمل، وقد يكون بتاريخ سابق. «بلا نتيجة» تعني عدم وجود تشغيل مكتمل في السجل المتاح. اضغط المهمة للتفاصيل.", "Status reflects the latest completed run, which may be older. No result means no completed run in the available history. Tap a job for details."))
                .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
        }
    }

    private func jobCard(_ job: ServerHealthJob) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text(job.name).font(DS.Font.caption1).textSelection(.enabled)
                    .environment(\.layoutDirection, .leftToRight)
                Text(job.status == "failed" ? L10n.t("آخر تشغيل مسجّل فشل. راجع إعداد المهمة وسجل التنفيذ؛ تبقى هذه النتيجة إلى أن يكتمل تشغيل جديد.", "The last recorded run failed. Check the job configuration and execution logs; this result remains until a new run completes.") : job.status == "succeeded" ? L10n.t("اكتمل آخر تشغيل بنجاح حسب سجل السيرفر.", "The latest run completed successfully according to the server log.") : L10n.t("لا توجد نتيجة مكتملة حالياً. قد تكون المهمة جديدة أو انتهت مدة الاحتفاظ بالسجل.", "No completed result is available. The job may be new or its history may have expired."))
                    .font(DS.Font.footnote)
            }.foregroundStyle(DS.Color.textSecondary).padding(.top, DS.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                Image(systemName: job.status == "succeeded" ? "checkmark.circle.fill" : job.status == "failed" ? "exclamationmark.circle.fill" : "clock.fill")
                    .foregroundStyle(job.color).font(DS.Font.title3)
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text(job.title).font(DS.Font.calloutBold).foregroundStyle(DS.Color.textPrimary)
                    Text(job.statusTitle).font(DS.Font.caption1.weight(.semibold)).foregroundStyle(job.color)
                    if let date = HealthTimestamp.date(job.last_run) {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.contentShape(Rectangle())
        }.padding(DS.Spacing.lg)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
            .accessibilityIdentifier("health.server.job.\(job.name)")
    }

    private func operationsSummary(_ data: HealthOperations) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(L10n.t("مؤشرات التشغيل", "Operational indicators")).font(DS.Font.title3)
            operationRow(L10n.t("محاولات مهام فاشلة · ٢٤ ساعة", "Failed job attempts · 24h"), count: data.cron_failures)
            operationRow(L10n.t("اتصالات سيرفر فاشلة · ٢٤ ساعة", "Failed server HTTP calls · 24h"), count: data.http_failures)
            operationRow(L10n.t("حذف حسابات متأخر أكثر من ١٥ دقيقة", "Account deletions delayed over 15 minutes"), count: data.pending_deletions)
        }.padding(DS.Spacing.lg).background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
    }
    private func operationRow(_ title: String, count: Int) -> some View {
        HStack(alignment: .top) {
            Text(title).font(DS.Font.footnote).foregroundStyle(DS.Color.textSecondary)
            Spacer()
            Text(count.formatted()).font(DS.Font.calloutBold).foregroundStyle(count > 0 ? DS.Color.warning : DS.Color.success)
        }
    }
}

private extension ServerHealthFilter {
    var title: String {
        switch self {
        case .all: return L10n.t("الكل", "All")
        case .failed: return L10n.t("فشلت", "Failed")
        case .succeeded: return L10n.t("نجحت", "Succeeded")
        case .notRun: return L10n.t("بلا نتيجة", "No result")
        }
    }
}
private extension ServerHealthJob {
    var color: Color { status == "succeeded" ? DS.Color.success : status == "failed" ? DS.Color.error : DS.Color.textSecondary }
    var statusTitle: String {
        status == "succeeded" ? L10n.t("نجحت", "Succeeded") : status == "failed" ? L10n.t("فشلت", "Failed") : L10n.t("بلا نتيجة مكتملة", "No completed result")
    }
    var title: String {
        switch name {
        case "cleanup-old-web-sessions": return L10n.t("تنظيف جلسات الويب القديمة", "Clean old web sessions")
        case "cleanup-old-join-requests": return L10n.t("تنظيف طلبات الانضمام القديمة", "Clean old join requests")
        case "cleanup-old-read-notifications": return L10n.t("تنظيف الإشعارات المقروءة", "Clean read notifications")
        case "cleanup-old-user-timeline": return L10n.t("تنظيف سجل النشاط القديم", "Clean old activity")
        case "cleanup-inactive-device-tokens": return L10n.t("تنظيف تسجيلات الأجهزة غير النشطة", "Clean inactive device registrations")
        case "dispatch-scheduled-notifications": return L10n.t("توزيع الإشعارات المجدولة", "Dispatch scheduled notifications")
        case "cleanup-delivery-attempts": return L10n.t("تنظيف سجل محاولات الإرسال", "Clean delivery attempts")
        case "cleanup-app-diagnostics": return L10n.t("تنظيف تقارير الأخطاء القديمة", "Clean old error reports")
        default: return name
        }
    }
}
