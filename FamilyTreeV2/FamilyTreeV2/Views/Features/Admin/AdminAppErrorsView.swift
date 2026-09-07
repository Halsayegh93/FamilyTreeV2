import SwiftUI
import Supabase

struct AdminAppErrorsView: View {
    var serverOnly = false
    @State private var operations: HealthOperations?
    @State private var dashboard: Dashboard?
    @State private var loading = false
    @State private var failure: String?
    @State private var reviewing: String?
    @State private var showReviewed = false

    private struct Dashboard: Decodable {
        let total_occurrences: Int
        let open_groups: Int
        let checked_at: Date
        let errors: [Diagnostic]
        let jobs: [Job]
        let dispatch_healthy: Bool
    }
    private struct Diagnostic: Decodable, Identifiable {
        let feature: String
        let code: String
        let app_version: String
        let occurrences: Int
        let first_seen: Date
        let last_seen: String
        let needs_review: Bool
        var id: String { feature + ":" + code + ":" + app_version }
    }
    private struct Job: Decodable, Identifiable {
        let name: String
        let status: String
        let last_run: Date?
        var id: String { name }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.xl) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text(serverOnly ? L10n.t("تشغيل الخدمات", "Service operations") : L10n.t("قائمة المتابعة", "Review queue"))
                            .font(DS.Font.title1).foregroundStyle(DS.Color.textPrimary)
                        Text(serverOnly ? L10n.t("آخر تنفيذ لكل مهمة، بوضوح", "The latest result of every job") : L10n.t("راجع المشكلة وتابع تكرارها", "Review issues and track recurrence"))
                            .font(DS.Font.footnote).foregroundStyle(DS.Color.textSecondary)
                    }
                    Spacer()
                    Button { Task { await load() } } label: {
                        Group { if loading { ProgressView() } else { Image(systemName: "arrow.clockwise") } }
                            .frame(width: DS.Icon.size, height: DS.Icon.size)
                            .background(DS.Color.surface, in: Circle())
                    }.disabled(loading).accessibilityLabel(L10n.t("تحديث", "Refresh"))
                }
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(DS.Color.warning).font(DS.Font.footnote)
                        .padding(DS.Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Color.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
                if let dashboard {
                    if serverOnly { serverContent(dashboard) }
                    else { reportsContent(dashboard) }
                    Label(dashboard.checked_at.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
                }
                if !serverOnly {
                    Text(L10n.t("آخر ١٠٠ مجموعة خلال ٧ أيام. البلاغات تصل من النسخ الداعمة عند الاتصال وتسجيل الدخول، ولا تشمل كل الأعطال أو الانهيارات.", "Latest 100 groups in 7 days. Supporting versions report while connected and signed in; coverage does not include every failure or crash."))
                        .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
                }
            }.padding(DS.Spacing.lg).padding(.bottom, DS.Spacing.xxl)
        }
        .background(DS.Color.background)
        .navigationTitle(serverOnly ? L10n.t("مهام السيرفر", "Server jobs") : L10n.t("أخطاء التطبيق", "App errors"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func reportsContent(_ dashboard: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            HStack(spacing: DS.Spacing.md) {
                metric("تحتاج مراجعة", "Needs review", value: dashboard.open_groups, color: DS.Color.warning)
                metric("بلاغات خلال ٧ أيام", "Reports in 7 days", value: dashboard.total_occurrences, color: DS.Color.primary)
            }
            Picker(L10n.t("حالة البلاغات", "Report status"), selection: $showReviewed) {
                Text(L10n.t("قيد المراجعة", "Needs review")).tag(false)
                Text(L10n.t("الكل", "All")).tag(true)
            }.pickerStyle(.segmented)
            let visible = dashboard.errors.filter { showReviewed || $0.needs_review }
            if visible.isEmpty {
                VStack(spacing: DS.Spacing.md) {
                    Image(systemName: "checkmark.shield.fill").font(DS.Font.hero).foregroundStyle(DS.Color.success)
                    Text(L10n.t("قائمة المتابعة خالية", "Your review queue is clear")).font(DS.Font.title3)
                    Text(L10n.t("أي بلاغ جديد يصل بيظهر هنا", "New reports will appear here"))
                        .font(DS.Font.footnote).foregroundStyle(DS.Color.textSecondary)
                }.frame(maxWidth: .infinity).padding(DS.Spacing.xxxl)
                    .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
            }
            ForEach(visible) { diagnostic in errorCard(diagnostic) }
            Text(L10n.t("تمت المراجعة تعني الاطلاع على البلاغ. إذا تكرر، يرجع تلقائياً لقائمة المتابعة.", "Reviewed means acknowledged. A new occurrence returns to the review queue."))
                .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
        }
    }

    private func serverContent(_ dashboard: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            Label(dashboard.dispatch_healthy ? L10n.t("موزّع الإشعارات يعمل", "Notification dispatcher is running") : L10n.t("موزّع الإشعارات يحتاج متابعة", "Notification dispatcher needs attention"), systemImage: dashboard.dispatch_healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(DS.Font.calloutBold).foregroundStyle(dashboard.dispatch_healthy ? DS.Color.success : DS.Color.warning)
                .padding(DS.Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
                .background((dashboard.dispatch_healthy ? DS.Color.success : DS.Color.warning).opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.xl))
            if let operations {
                HStack(spacing: DS.Spacing.md) {
                    metric("اتصالات فاشلة · ٢٤ س", "Failed HTTP · 24h", value: operations.http_failures, color: DS.Color.warning)
                    metric("حذف حسابات متأخر", "Delayed deletions", value: operations.pending_deletions, color: DS.Color.accent)
                }
                Text(L10n.t("محاولات تشغيل فاشلة خلال ٢٤ ساعة: \(operations.cron_failures)", "Failed job attempts in 24h: \(operations.cron_failures)"))
                    .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
            }
            Text(L10n.t("آخر نتائج التشغيل", "Latest run results")).font(DS.Font.title3)
            ForEach(dashboard.jobs) { job in
                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    Image(systemName: job.status == "succeeded" ? "checkmark.circle.fill" : job.status == "failed" ? "exclamationmark.circle.fill" : "clock.fill")
                        .font(DS.Font.title3).foregroundStyle(job.status == "succeeded" ? DS.Color.success : DS.Color.warning)
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text(jobTitle(job.name)).font(DS.Font.calloutBold).foregroundStyle(DS.Color.textPrimary)
                        if let date = job.last_run {
                            Text(date.formatted(date: .abbreviated, time: .shortened)).font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(job.status == "succeeded" ? L10n.t("نجحت", "Succeeded") : job.status == "failed" ? L10n.t("فشلت", "Failed") : L10n.t("لم تعمل بعد", "Not run yet"))
                        .font(DS.Font.caption1.weight(.semibold))
                        .foregroundStyle(job.status == "succeeded" ? DS.Color.success : DS.Color.warning)
                }.padding(DS.Spacing.lg).background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.xl).stroke(DS.Color.cardBorder, lineWidth: DS.Border.width))
            }
        }
    }

    private func metric(_ ar: String, _ en: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(value.formatted()).font(DS.Font.hero).monospacedDigit().foregroundStyle(color)
            Text(L10n.t(ar, en)).font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(DS.Spacing.lg)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.xl))
    }

    private func errorCard(_ diagnostic: Diagnostic) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Label(featureTitle(diagnostic.feature), systemImage: diagnostic.needs_review ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(DS.Font.calloutBold)
                    .foregroundStyle(diagnostic.needs_review ? DS.Color.warning : DS.Color.success)
                Spacer()
                Text(L10n.t("\(diagnostic.occurrences) بلاغ", "\(diagnostic.occurrences) reports")).font(DS.Font.caption1)
            }
            Text(codeTitle(diagnostic.code)).font(DS.Font.calloutBold)
            Text(L10n.t("الإصدار: ", "Version: ") + diagnostic.app_version).font(DS.Font.caption1)
            Text(L10n.t("آخر ظهور: ", "Last seen: ") + dateLabel(diagnostic.last_seen))
                .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
            Text(advice(diagnostic.code)).font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
            if diagnostic.needs_review {
                Button {
                    Task { await review(diagnostic) }
                } label: {
                    HStack {
                        if reviewing == diagnostic.id { ProgressView() }
                        Text(L10n.t("تمت المراجعة", "Mark reviewed"))
                    }.font(DS.Font.calloutBold)
                }.buttonStyle(.borderedProminent).tint(DS.Color.primary).disabled(reviewing != nil || loading)
            } else {
                Text(L10n.t("تمت المراجعة", "Reviewed")).font(DS.Font.caption1).foregroundStyle(DS.Color.success)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(DS.Spacing.lg)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.xl).stroke(DS.Color.cardBorder, lineWidth: DS.Border.width))
    }

    @MainActor private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let data = try await SupabaseConfig.client.rpc("app_diagnostics_dashboard").execute().data
            dashboard = try decoder().decode(Dashboard.self, from: data)
            if serverOnly { operations = try await SupabaseConfig.client.rpc("operational_health").execute().value }
            failure = nil
        } catch {
            if !Log.isCancellation(error) { failure = L10n.t("تعذر تحديث الأخطاء. البيانات المعروضة قد تكون قديمة؛ أعد المحاولة.", "Could not refresh errors. Displayed data may be stale; try again.") }
        }
    }

    @MainActor private func review(_ diagnostic: Diagnostic) async {
        guard reviewing == nil else { return }
        reviewing = diagnostic.id
        defer { reviewing = nil }
        do {
            try await SupabaseConfig.client.rpc("review_app_diagnostic", params: [
                "p_feature": diagnostic.feature, "p_code": diagnostic.code,
                "p_app_version": diagnostic.app_version, "p_seen_at": diagnostic.last_seen
            ]).execute()
            await load()
        } catch {
            failure = L10n.t("تعذر حفظ المراجعة. أعد المحاولة.", "Could not save review. Please try again.")
        }
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid server timestamp")
        }
        return decoder
    }
    private func dateLabel(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = formatter.date(from: value)
        formatter.formatOptions = [.withInternetDateTime]
        return (fractional ?? formatter.date(from: value))?.formatted(date: .abbreviated, time: .shortened) ?? value
    }
    private func featureTitle(_ feature: String) -> String {
        switch feature {
        case "news": return L10n.t("الأخبار", "News")
        case "members": return L10n.t("الأعضاء والشجرة", "Members & tree")
        case "notifications": return L10n.t("الإشعارات والأجهزة", "Notifications & devices")
        case "media": return L10n.t("الصور والملفات", "Photos & files")
        case "auth": return L10n.t("تسجيل الدخول", "Sign in")
        case "settings": return L10n.t("الإعدادات", "Settings")
        case "diwaniyas": return L10n.t("الديوانيات", "Diwaniyas")
        case "projects": return L10n.t("المشاريع", "Projects")
        case "admin": return L10n.t("الإدارة والطلبات", "Administration & requests")
        default: return L10n.t("التطبيق", "App")
        }
    }
    private func codeTitle(_ code: String) -> String {
        switch code {
        case "offline": return L10n.t("انقطاع الاتصال", "Connection lost")
        case "timeout": return L10n.t("انتهت مهلة الطلب", "Request timed out")
        case "permission_denied": return L10n.t("رفض الوصول للبيانات", "Data access denied")
        case "fetch_failed": return L10n.t("تعذر تحميل البيانات", "Data could not load")
        default: return L10n.t("تعذر إكمال العملية", "Operation could not complete")
        }
    }
    private func advice(_ code: String) -> String {
        switch code {
        case "offline", "timeout": return L10n.t("راجع الاتصال وحالة مهام السيرفر، ثم جرّب القسم المتأثر.", "Check connectivity and server jobs, then retry the affected section.")
        case "permission_denied": return L10n.t("راجع صلاحيات الحساب وسياسات الوصول للقسم المتأثر.", "Review account permissions and access policies for this section.")
        default: return L10n.t("جرّب القسم على الإصدار المذكور وتحقق من تكرار المشكلة.", "Try the section on this app version and check whether the issue repeats.")
        }
    }
    private func jobTitle(_ name: String) -> String {
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
