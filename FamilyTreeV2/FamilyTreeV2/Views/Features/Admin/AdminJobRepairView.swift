import SwiftUI
import Supabase

struct AdminJobRepairView: View {
    let job: ServerHealthJob
    @State private var preview: SystemHealthRepairPreview?
    @State private var result: SystemHealthRepairResult?
    @State private var loading = false
    @State private var executing = false
    @State private var failure: String?
    @State private var confirmCleanup = false
    @State private var requestID = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                Label(L10n.t("إصلاح فعلي على السيرفر", "Repair on the server"), systemImage: "wrench.and.screwdriver.fill")
                    .font(DS.Font.footnote.weight(.semibold)).foregroundStyle(DS.Color.primary)
                SystemHealthSectionHeader(title: job.title, subtitle: job.repairPolicy)
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    step("1", L10n.t("تصحيح تعريف المهمة وجدولها وإعادة تفعيلها", "Restore the job definition, schedule and active state"))
                    if preview?.schema_repair_needed == true {
                        step("2", L10n.t("إضافة تاريخ الإنشاء المفقود، مع إبقاء الطلبات القديمة", "Add the missing creation date while retaining legacy requests"))
                    }
                    step(preview?.schema_repair_needed == true ? "3" : "2", L10n.t("تشغيل المهمة الآن وتسجيل النتيجة الفعلية", "Run the job now and record its actual result"))
                }.padding(DS.Spacing.lg).background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl))

                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(DS.Font.footnote).foregroundStyle(DS.Color.warning)
                }
                if let result {
                    resultCard(result)
                    if result.status != "succeeded" {
                        Button(L10n.t("فحص ومحاولة جديدة", "Check and try a new repair")) {
                            self.result = nil
                            requestID = UUID()
                            Task { await loadPreview() }
                        }.buttonStyle(.bordered)
                    }
                } else if let preview {
                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                        Text(L10n.t("قبل التنفيذ", "Before running")).font(DS.Font.title3)
                        Text(preview.eligible_rows.formatted()).font(DS.Font.hero).foregroundStyle(DS.Color.primary)
                        Text(preview.eligible_rows == 0
                             ? L10n.t("لا توجد سجلات للحذف. سيتم تصحيح إعداد المهمة وتجربة تشغيلها.", "There are no records to delete. The job settings will be restored and the job will run.")
                             : L10n.t("سجل ينطبق عليه شرط التنظيف وسيُحذف نهائياً عند التأكيد.", "records match the retention policy and will be permanently deleted after confirmation."))
                            .font(DS.Font.footnote).foregroundStyle(DS.Color.textSecondary)
                        if !preview.can_run {
                            Text(L10n.t("هذه العملية تتجاوز ٥٬٠٠٠ سجل وتحتاج صيانة خاصة قبل تنفيذها.", "This operation exceeds 5,000 records and requires a maintenance review before execution."))
                                .font(DS.Font.footnote).foregroundStyle(DS.Color.warning)
                        }
                    }.padding(DS.Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
                    Button {
                        if preview.eligible_rows > 0 { confirmCleanup = true }
                        else { Task { await execute(preview) } }
                    } label: {
                        HStack {
                            if executing { ProgressView().tint(DS.Color.textOnPrimary) }
                            Label(executing ? L10n.t("جاري الإصلاح…", "Repairing…") : L10n.t("إصلاح وتشغيل الآن", "Repair and run now"), systemImage: "wrench.adjustable.fill")
                        }.font(DS.Font.calloutBold).frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.sm)
                    }.buttonStyle(.borderedProminent).tint(DS.Color.primary)
                        .disabled(loading || executing || !preview.can_run)
                        .accessibilityIdentifier("health.repair.execute")
                    Button(L10n.t("إعادة فحص العدد", "Recheck affected records")) {
                        Task { await loadPreview() }
                    }.disabled(loading || executing)
                } else if loading {
                    ProgressView(L10n.t("فحص العملية قبل التنفيذ", "Checking the repair before execution"))
                        .frame(maxWidth: .infinity).padding(DS.Spacing.xxl)
                } else {
                    Button(L10n.t("إعادة الفحص", "Check again")) { Task { await loadPreview() } }
                        .buttonStyle(.borderedProminent)
                }
            }.padding(DS.Spacing.lg).padding(.bottom, DS.Spacing.xxl)
        }.background(DS.Color.background)
            .navigationTitle(L10n.t("إصلاح المهمة", "Repair job"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(executing)
            .interactiveDismissDisabled(executing)
            .task { await loadPreview() }
            .confirmationDialog(L10n.t("تأكيد الإصلاح والتنظيف", "Confirm repair and cleanup"), isPresented: $confirmCleanup, titleVisibility: .visible) {
                Button(L10n.t("إصلاح وحذف \(preview?.eligible_rows ?? 0) سجل", "Repair and delete \(preview?.eligible_rows ?? 0) records"), role: .destructive) {
                    if let preview { Task { await execute(preview) } }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            } message: {
                Text(job.repairPolicy + "\n" + L10n.t("الحذف نهائي. سيتم تصحيح المهمة وتشغيلها وتسجيل النتيجة.", "Deletion is permanent. The job will be repaired, run, and its result recorded."))
            }
    }

    private func step(_ number: String, _ title: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Text(number).font(DS.Font.calloutBold).foregroundStyle(DS.Color.primary)
            Text(title).font(DS.Font.footnote).foregroundStyle(DS.Color.textPrimary)
        }
    }
    private func resultCard(_ result: SystemHealthRepairResult) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Label(result.status == "succeeded" ? L10n.t("تم الإصلاح والتشغيل بنجاح", "Repair and execution succeeded") : L10n.t("لم يكتمل الإصلاح", "Repair did not complete"),
                  systemImage: result.status == "succeeded" ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(DS.Font.title3).foregroundStyle(result.status == "succeeded" ? DS.Color.success : DS.Color.error)
            Text(result.status == "succeeded"
                 ? L10n.t("تم تنظيف \(result.affected_rows) سجل. النتيجة محفوظة في سجل الإصلاحات.", "Cleaned \(result.affected_rows) records. The result is saved in repair history.")
                 : L10n.t("تراجعت تغييرات هذه المحاولة. السبب: ", "This attempt's changes were rolled back. Reason: ") + repairFailureTitle(result.error_code))
                .font(DS.Font.footnote).foregroundStyle(DS.Color.textSecondary)
            if let date = HealthTimestamp.date(result.completed_at) {
                Text(date.formatted(date: .abbreviated, time: .shortened)).font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
            }
        }.padding(DS.Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
            .accessibilityIdentifier("health.repair.result.\(result.status)")
    }

    @MainActor private func loadPreview() async {
        guard !loading && !executing else { return }
        loading = true
        defer { loading = false }
        do {
            let data = try await SupabaseConfig.client.rpc("system_health_repair_preview", params: ["p_job_name": job.name]).execute().data
            preview = try JSONDecoder().decode(SystemHealthRepairPreview.self, from: data)
            failure = nil
        } catch {
            if !Log.isCancellation(error) { failure = requestFailure(error) }
        }
    }
    @MainActor private func execute(_ plan: SystemHealthRepairPreview) async {
        guard !executing && !loading else { return }
        executing = true
        defer { executing = false }
        struct Params: Encodable {
            let p_job_name: String
            let p_request_id: String
            let p_expected_rows: Int
        }
        do {
            let params = Params(p_job_name: job.name, p_request_id: requestID.uuidString, p_expected_rows: plan.eligible_rows)
            let data = try await SupabaseConfig.client.rpc("repair_system_health_job", params: params).execute().data
            result = try JSONDecoder().decode(SystemHealthRepairResult.self, from: data)
            failure = nil
        } catch {
            // Keep the same request ID: a network failure after server commit
            // must not execute the repair a second time when the user retries.
            failure = requestFailure(error)
        }
    }
    private func requestFailure(_ error: Error) -> String {
        let message = (error as? PostgrestError)?.message ?? ""
        switch message {
        case "preview_changed": return L10n.t("تغيّر العدد منذ الفحص. أعد فحص العدد قبل التنفيذ.", "The count changed. Recheck affected records before running.")
        case "repair_cooldown", "job_running": return L10n.t("المهمة تعمل الآن أو نُفّذت للتو. انتظر قليلاً ثم أعد الفحص.", "This job is running or just ran. Wait briefly and check again.")
        case "not_authorized": return L10n.t("الإصلاح متاح للمالك والمدير بالحسابات الفعّالة فقط.", "Repairs require an active owner or admin account.")
        case "unsupported_repair", "job_owner_mismatch", "ambiguous_job", "scheduler_unavailable", "repair_too_large":
            return L10n.t("هذه الحالة تحتاج صيانة خاصة ولا يمكن تنفيذها من هذا الزر.", "This condition needs a maintenance review and cannot be repaired using this action.")
        default: return L10n.t("تعذر تأكيد النتيجة. أعد المحاولة؛ يحتفظ الطلب بمعرّفه لمنع تكرار التنفيذ.", "Could not confirm the result. Retry; this request keeps its ID to prevent duplicate execution.")
        }
    }
}

func repairFailureTitle(_ code: String?) -> String {
    switch code {
    case "42703", "42P01": return L10n.t("بنية البيانات تحتاج تحديثاً إضافياً", "The database structure needs an additional update")
    case "42501": return L10n.t("صلاحيات تنفيذ المهمة تحتاج مراجعة", "Job execution permissions need review")
    case "55P03", "40P01": return L10n.t("البيانات مشغولة بعملية أخرى؛ جرّب لاحقاً", "Another operation is using this data; try later")
    case "23503": return L10n.t("توجد سجلات مرتبطة تحتاج معالجة", "Related records need attention")
    default: return L10n.t("خطأ في التنفيذ يحتاج فحصاً فنياً", "An execution error needs technical investigation")
    }
}

extension ServerHealthJob {
    var repairPolicy: String {
        switch name {
        case "cleanup-old-join-requests": return L10n.t("تنظيف الطلبات المقبولة والمرفوضة الأقدم من ٦٠ يوماً. الطلبات المعلّقة محفوظة.", "Clean approved and rejected requests older than 60 days. Pending requests are retained.")
        case "cleanup-old-web-sessions": return L10n.t("تنظيف جلسات الويب التي لم تنشط منذ أكثر من ٣٠ يوماً.", "Clean web sessions inactive for more than 30 days.")
        case "cleanup-delivery-attempts": return L10n.t("تنظيف سجل محاولات الإرسال الأقدم من ٨ أيام.", "Clean delivery-attempt records older than 8 days.")
        case "cleanup-app-diagnostics": return L10n.t("تنظيف تقارير الأخطاء ومراجعاتها الأقدم من ٣٠ يوماً.", "Clean diagnostic reports and reviews older than 30 days.")
        default: return L10n.t("هذه المهمة تحتاج معالجة خاصة.", "This job needs a maintenance review.")
        }
    }
}
