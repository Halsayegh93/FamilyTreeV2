import SwiftUI

// MARK: - «المؤشرات» — ثلاثة مداخل للقراءة (الدفعة ج من «نفّذ كل المقترح»، ٢٠٢٦-١٠-٢٠؛ الدفعة ٥)
//
// كانت ١٠ مداخل: مربّعات «نبض العائلة» الأربعة (كل واحد يكرر صفحة)، بطاقة «أفراد العائلة» (تكرر «إحصاء الأفراد» و«ملخص
// عام»)، وخمسة صفوف (الإحصائيات، النشاط الآن، سجل النشاط، تقرير الموافقات، تقارير PDF). صارت صفوفاً في بطاقة واحدة،
// كل صفّ برقمه الحي ويفتح بيته — بلا تبويبات:
//   العائلة (`AdminAnalyticsView` — بيت «إحصاء الأفراد»؛ المراقب: الأعداد فقط) · الاستخدام (`AdminActiveMembersView`) ·
//   الموافقات (`ApprovalsReportView` — بيت تقرير الموافقات الوحيد)
// «سجل التعديلات» صار «نشاط الفريق» في «إشعارات الإدارة» (جرس «اليوم»، بحثه هناك). «تقارير PDF» انتقلت إلى
// «العائلة ← زر التقارير». الصلاحيات من فهرس الأدوات (`AdminToolCatalog`).

struct AdminMetricsAreaView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @State private var activeNow: Int?
    @State private var weekly: (executed: Int, rejected: Int)?

    var body: some View {
        let tools = AdminToolCatalog.tools(authVM: authVM, adminRequestVM: adminRequestVM)
            .filter { $0.area == .metrics && !$0.searchOnly }
        AdminHubPage {
            AdminBandHeader(title: AdminArea.metrics.title, subtitle: AdminArea.metrics.subtitle, isAreaRoot: true)
        } content: {
            if tools.isEmpty {
                DSEmptyView(L10n.t("لا مؤشرات لدورك هنا", "No insights for your role here"), style: .card)
            } else {
                // مربّعات بالمنتصف بسطر رقمها الحيّ (طلب المالك ٢٠٢٦-١٠-٢٤)
                AdminToolCards(tools: tools, hints: hints, style: .tiles(captions: true))
            }
        }
        .task { await load() }
    }

    /// رقم حي واحد لكل مدخل (لا نسخة ثانية من صفحته)
    private var hints: [String: String] {
        var h: [String: String] = [:]
        let members = memberVM.allMembers.filter(\.isCountable).count
        if members > 0 { h["metrics.family"] = L10n.t("\(members.formatted()) فرد", "\(members.formatted()) members") }
        if let now = activeNow { h["metrics.usage"] = L10n.t("\(now) الآن", "\(now) now") }
        if let w = weekly { h["metrics.approvals"] = L10n.t("\(w.executed + w.rejected) هذا الأسبوع", "\(w.executed + w.rejected) this week") }
        return h
    }

    private func load() async {
        let isAdmin = authVM.isAdmin
        let flowOn = adminRequestVM.approvalsWorkflowOn
        await withTaskGroup(of: Void.self) { group in
            if memberVM.allMembers.isEmpty {
                group.addTask { @MainActor in await memberVM.fetchAllMembers() }
            }
            if isAdmin {
                group.addTask { @MainActor in activeNow = await AdminTodayFetch.activeNowCount() }
            }
            if flowOn {
                group.addTask { @MainActor in weekly = await AdminTodayFetch.weeklyDone() }
            }
        }
    }
}
