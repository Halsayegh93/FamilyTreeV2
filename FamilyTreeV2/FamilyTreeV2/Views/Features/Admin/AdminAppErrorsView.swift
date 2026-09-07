import SwiftUI
import Supabase

struct AdminAppErrorsView: View {
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
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack {
                    Label(L10n.t("متابعة أخطاء التطبيق", "App error tracking"), systemImage: "exclamationmark.bubble.fill")
                        .font(DS.Font.calloutBold)
                    Spacer()
                    if loading { ProgressView() }
                    else {
                        Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel(L10n.t("تحديث الأخطاء", "Refresh errors"))
                    }
                }
                if let failure {
                    Text(failure).foregroundStyle(DS.Color.error).font(DS.Font.caption1)
                }
                if let dashboard {
                    HStack(spacing: DS.Spacing.md) {
                        metric("تحتاج مراجعة", "Needs review", value: dashboard.open_groups, color: DS.Color.warning)
                        metric("بلاغات خلال ٧ أيام", "Reports in 7 days", value: dashboard.total_occurrences, color: DS.Color.info)
                    }
                    Text(L10n.t("آخر تحديث: ", "Updated: ") + dashboard.checked_at.formatted(date: .abbreviated, time: .shortened))
                        .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
                    Toggle(L10n.t("إظهار الأخطاء التي تمت مراجعتها", "Include reviewed errors"), isOn: $showReviewed)
                        .font(DS.Font.caption1).tint(DS.Color.primary)
                    let visible = dashboard.errors.filter { showReviewed || $0.needs_review }
                    if visible.isEmpty {
                        VStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "checkmark.shield.fill").font(DS.Font.title2).foregroundStyle(DS.Color.success)
                            Text(L10n.t("ما فيه أخطاء مسجلة تحتاج مراجعة", "No recorded errors need review"))
                                .font(DS.Font.calloutBold)
                        }.frame(maxWidth: .infinity).padding(DS.Spacing.lg)
                    }
                    ForEach(visible) { diagnostic in errorCard(diagnostic) }
                    Text(L10n.t("آخر ١٠٠ مجموعة أخطاء خلال ٧ أيام. تمت المراجعة تعني الاطلاع على البلاغ؛ تكراره يعيده لقائمة المتابعة.", "Latest 100 error groups in 7 days. Reviewed means acknowledged; a new occurrence reopens the group."))
                        .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
                    Divider()
                    Label(L10n.t("مهام السيرفر", "Server jobs"), systemImage: "server.rack")
                        .font(DS.Font.calloutBold)
                    Label(dashboard.dispatch_healthy
                          ? L10n.t("موزّع الإشعارات يعمل", "Notification dispatcher is running")
                          : L10n.t("موزّع الإشعارات يحتاج متابعة", "Notification dispatcher needs attention"),
                          systemImage: dashboard.dispatch_healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(DS.Font.caption1)
                        .foregroundStyle(dashboard.dispatch_healthy ? DS.Color.success : DS.Color.warning)
                    ForEach(dashboard.jobs) { job in
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            HStack(alignment: .top) {
                                Text(jobTitle(job.name)).font(DS.Font.caption1)
                                Spacer()
                                Text(job.status == "succeeded" ? L10n.t("نجحت", "Succeeded") : job.status == "failed" ? L10n.t("فشلت", "Failed") : L10n.t("بانتظار أول تشغيل", "Awaiting first run"))
                                    .font(DS.Font.caption1)
                                    .foregroundStyle(job.status == "succeeded" ? DS.Color.success : DS.Color.warning)
                            }
                            if let date = job.last_run {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
                            }
                        }.padding(DS.Spacing.md).background(DS.Color.textTertiary.opacity(0.07), in: RoundedRectangle(cornerRadius: DS.Radius.md))
                    }
                } else if !loading && failure == nil {
                    Text(L10n.t("اسحب للتحديث", "Pull to refresh")).foregroundStyle(DS.Color.textSecondary)
                }
                Text(L10n.t("تصل بلاغات مختصرة من النسخ الداعمة عند توفر الاتصال وتسجيل الدخول. لا تشمل هذه القائمة كل الأعطال أو الانهيارات، ولا تحتوي بيانات الرسائل أو أرقام الهواتف.", "Supporting app versions send brief reports when signed in and connected. This list does not cover every failure or crash and contains no message content or phone numbers."))
                    .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
            }.padding(DS.Spacing.lg)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func metric(_ ar: String, _ en: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(value.formatted()).font(DS.Font.title2).foregroundStyle(color)
            Text(L10n.t(ar, en)).font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(DS.Spacing.md)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.md))
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
                }.disabled(reviewing != nil || loading)
            } else {
                Text(L10n.t("تمت المراجعة", "Reviewed")).font(DS.Font.caption1).foregroundStyle(DS.Color.success)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(DS.Spacing.md)
            .background(DS.Color.textTertiary.opacity(0.07), in: RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    @MainActor private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let data = try await SupabaseConfig.client.rpc("app_diagnostics_dashboard").execute().data
            dashboard = try decoder().decode(Dashboard.self, from: data)
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
