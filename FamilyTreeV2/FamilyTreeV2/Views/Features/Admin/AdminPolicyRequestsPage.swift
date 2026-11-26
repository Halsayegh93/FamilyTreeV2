import SwiftUI

// MARK: - «طلبات الخصوصية» (إعادة تصميم الإدارة ٢٠٢٦-١١-٢٦، الوحدة U8 — spec C.2 البند ٥ وE.22)
//
// كانت بطاقات داخل قائمة «الوارد» (قائمة ثانية داخل صفحة) — صارت صفحة يفتحها صفّ «طلبات الخصوصية» في «الوارد»:
// رأس الصفحات الداخلية «‹ الوارد» · «طلبات الخصوصية» · «2 بانتظار الرد»، ثم البطاقات نفسها (`AdminPolicyRequestsSection`
// في Privacy/PrivacyRequestsViews.swift — بلا تعديل: حذف الحساب، الخصوصية، إضافة قريب وحذفه، النسب، بأزرارها ومربّعاتها
// ونداءاتها). `focusId` (إشعار بـ`request_id`) يفتح مربّع طلب القرابة كما كان.
// الحالات: الهيكل حتى يصل أول جلب، و«لا طلبات خصوصية الآن» حين تفرغ، والفشل «تعذّر التحميل» + «أعد المحاولة» (نموذج العرض
// يبتلع الخطأ — الفشل = انتهى الجلب والجهاز غير متصل).

struct AdminPolicyRequestsPage: View {
    @EnvironmentObject private var adminRequestVM: AdminRequestViewModel
    /// طلب يُفتح مربّعه بعد التحميل (من الإشعار) — يمرّره «الوارد»
    var focusId: UUID? = nil
    @State private var health: AdminStoreHealth = .idle
    @Environment(\.adminBackTitle) private var outerBack

    static var title: String { L10n.t("طلبات الخصوصية", "Privacy requests") }

    var body: some View {
        AnyView(page)
            .debugStackProbe("AdminPolicyRequestsPage", limitKB: DebugStackLimit.page)
    }

    private var count: Int { adminRequestVM.policyRequestsCount }

    private var page: some View {
        AdminPage(header: header, layout: .list, content: AnyView(rows), updatedAt: health.lastGood)
            .refreshable { await reload() }
            .task {
                // «الوارد» جلبها للتوّ — بلا جلب ثانٍ حين وصلت بياناتها
                if count > 0 { health = .loaded(at: Date()) } else { await reload() }
            }
    }

    private var header: AdminPageHeader {
        let retry: () -> Void = { Task { await reload() } }
        return AdminPageHeader(
            back: outerBack == nil ? AdminArea.inbox.title : nil,
            title: Self.title,
            subtitle: L10n.t("حذف الحساب والخصوصية وطلبات الأقارب", "Account deletion, privacy and relatives' requests"),
            items: [AdminHeaderItem(id: "awaiting", value: health.hasData || count > 0 ? count : nil,
                                    label: L10n.t("بانتظار الرد", "awaiting a reply"),
                                    health: count > 0 ? nil : health, retry: retry)])
    }

    @ViewBuilder
    private var rows: some View {
        if count > 0 {
            if health.canRetry {
                AnyView(AdminPageStateCard(.error(L10n.t("تعذّر تحديث الطلبات", "Couldn't refresh the requests"),
                                                  message: L10n.t("تعرض آخر طلبات وصلت.", "Showing the last requests received."),
                                                  retry: { Task { await reload() } }, lastGood: health.lastGood)))
                    .adminPageRow(top: DS.Spacing.xs)
            }
            // البطاقات صفوف `List` بنفسها (حشوتها وخلفيتها) — فوق أرضية الصفحة
            AnyView(AdminPolicyRequestsSection(adminRequestVM: adminRequestVM, focusId: focusId))
        } else {
            switch AdminPageKitLogic.pageState(health) {
            case .loading:
                AnyView(DSCardSkeleton(style: .request, count: 2,
                                       label: L10n.t("جارٍ تحميل الطلبات…", "Loading requests…")))
                    .adminPageRow(top: DS.Spacing.xs)
            case .failed:
                AnyView(AdminPageStateCard(.error(L10n.t("تعذّر تحميل الطلبات", "Couldn't load the requests"),
                                                  message: L10n.t("تحقّق من اتصالك ثم أعد المحاولة.",
                                                                  "Check your connection, then try again."),
                                                  retry: { Task { await reload() } })))
                    .adminPageRow(top: DS.Spacing.xs)
            case .content:
                AnyView(AdminPageStateCard(.empty(L10n.t("لا طلبات خصوصية الآن", "No privacy requests now"),
                                                  message: L10n.t("كل الطلبات عولجت.", "Every request was handled."))))
                    .adminPageRow(top: DS.Spacing.xs)
            }
        }
    }

    private func reload() async {
        health = health.beginning()
        if DebugAdminProbe.shouldFail(.inbox, hasLoaded: health.hasData) {   // `-tmpFailStores inbox`
            health = health.ending(success: false)
            return
        }
        await adminRequestVM.fetchPolicyRequests()
        health = health.ending(success: NetworkMonitor.shared.isConnected)
    }
}
