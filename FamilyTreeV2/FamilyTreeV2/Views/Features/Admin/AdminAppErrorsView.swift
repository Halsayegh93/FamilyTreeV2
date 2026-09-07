import SwiftUI
import Supabase

struct AdminAppErrorsView: View {
    @State private var dashboard: Dashboard?
    @State private var loading = false
    @State private var failure: String?
    @State private var reviewing: String?
    @State private var showReviewed = false

    init(showAll: Bool = false) {
        _showReviewed = State(initialValue: showAll)
    }

    private struct Dashboard: Decodable {
        let total_occurrences: Int
        let open_groups: Int
        let checked_at: String
        let errors: [Diagnostic]
    }
    private struct Diagnostic: Decodable, Identifiable {
        let feature: String
        let code: String
        let app_version: String
        let occurrences: Int
        let last_seen: String
        let needs_review: Bool
        var id: String { feature + ":" + code + ":" + app_version }
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.xl) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text(showReviewed ? L10n.t("بلاغات التطبيق", "App reports") : L10n.t("قائمة المتابعة", "Review queue"))
                            .font(DS.Font.title1).foregroundStyle(DS.Color.textPrimary)
                        Text(L10n.t("راجع المشكلة وتابع تكرارها", "Review issues and track recurrence"))
                            .font(DS.Font.footnote).foregroundStyle(DS.Color.textSecondary)
                    }
                    Spacer()
                    Button { Task { await load() } } label: {
                        Group { if loading { ProgressView() } else { Image(systemName: "arrow.clockwise") } }
                            .frame(width: DS.Icon.size, height: DS.Icon.size)
                            .background(DS.Color.surface, in: Circle())
                    }.disabled(loading).accessibilityLabel(L10n.t("تحديث", "Refresh"))
                }
                NavigationLink(destination: AdminServerHealthView()) {
                    Label(L10n.t("فتح أدوات الإصلاح", "Open repair tools"), systemImage: "wrench.and.screwdriver.fill")
                        .font(DS.Font.calloutBold).frame(maxWidth: .infinity).padding(DS.Spacing.md)
                        .foregroundStyle(DS.Color.primary)
                        .background(DS.Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.lg))
                }.buttonStyle(.plain)
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(DS.Color.warning).font(DS.Font.footnote)
                        .padding(DS.Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Color.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
                if let dashboard {
                    reportsContent(dashboard)
                    Label(dateLabel(dashboard.checked_at), systemImage: "clock")
                        .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
                }
                Group {
                    Text(L10n.t("آخر ١٠٠ مجموعة خلال ٧ أيام. البلاغات تصل من النسخ الداعمة عند الاتصال وتسجيل الدخول، ولا تشمل كل الأعطال أو الانهيارات.", "Latest 100 groups in 7 days. Supporting versions report while connected and signed in; coverage does not include every failure or crash."))
                        .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
                }
            }.padding(DS.Spacing.lg).padding(.bottom, DS.Spacing.xxl)
        }
        .background(DS.Color.background)
        .navigationTitle(L10n.t("أخطاء التطبيق", "App errors"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func reportsContent(_ dashboard: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            HStack(spacing: DS.Spacing.md) {
                Button { showReviewed = false } label: {
                    metric("تحتاج مراجعة", "Needs review", value: dashboard.open_groups, color: DS.Color.warning)
                }.buttonStyle(.plain).accessibilityIdentifier("health.reports.needsReview")
                Button { showReviewed = true } label: {
                    metric("بلاغات خلال ٧ أيام", "Reports in 7 days", value: dashboard.total_occurrences, color: DS.Color.primary)
                }.buttonStyle(.plain).accessibilityIdentifier("health.reports.all")
            }
            Picker(L10n.t("حالة البلاغات", "Report status"), selection: $showReviewed) {
                Text(L10n.t("قيد المراجعة", "Needs review")).tag(false)
                Text(L10n.t("الكل", "All")).tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("health.reports.filter")
            let visible = dashboard.errors.filter { showReviewed || $0.needs_review }
            if visible.isEmpty {
                VStack(spacing: DS.Spacing.md) {
                    Image(systemName: "checkmark.shield.fill").font(DS.Font.hero).foregroundStyle(DS.Color.success)
                    Text(showReviewed ? L10n.t("لا توجد بلاغات خلال ٧ أيام", "No reports in the last 7 days") : L10n.t("قائمة المتابعة خالية", "Your review queue is clear")).font(DS.Font.title3)
                    Text(L10n.t("أي بلاغ جديد يصل بيظهر هنا", "New reports will appear here"))
                        .font(DS.Font.footnote).foregroundStyle(DS.Color.textSecondary)
                }.frame(maxWidth: .infinity).padding(DS.Spacing.xxxl)
                    .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
            }
            ForEach(visible) { diagnostic in errorCard(diagnostic) }
            Text(L10n.t("تمت المراجعة تسجّل الاطلاع فقط. الإصلاح يتم من أدوات الإصلاح للحالات المدعومة؛ وإذا تكرر البلاغ يرجع لقائمة المتابعة.", "Reviewed records acknowledgment. Use repair tools for supported conditions; a recurrence returns to the review queue."))
                .font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
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
            dashboard = try JSONDecoder().decode(Dashboard.self, from: data)
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

    private func dateLabel(_ value: String) -> String {
        HealthTimestamp.date(value)?.formatted(date: .abbreviated, time: .shortened)
            ?? L10n.t("التاريخ غير متاح", "Date unavailable")
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
}
