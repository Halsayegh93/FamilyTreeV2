import SwiftUI

// MARK: - «الوارد» (إعادة تصميم الإدارة ٢٠٢٦-١١-٢٦، الوحدة U8 — spec C.2، mock 2)
//
// جذر القسم صفحة واحدة تتمرّر (`List` لأجل السحب): الرأس الكحلي «‹ الإدارة» · «الوارد ⌄» · ⚙︎ «إعدادات مسار الموافقات» ·
// «تحديد»، ومجال الدور للمراقب والمشرف، وسطر الأرقام «5 بانتظار قرارك ‹ · 2 عاجل ‹ · 1 متأخر ‹» (كل رقم يضبط «الحالة»)
// ← صفوف الأبواب: «رسائل الأعضاء» (`AdminInboxView`، `inbox.messages`) و«بانتظار المراجعة» (`PostReviewQueuePage`)
// ← شريط الفلاتر (البحث + «الفلاتر»: الحالة · المجموعة · النوع · المصدر في ورقة واحدة — U5) والشرائح المفعّلة وسطر العدد
// ← سطر «تعذّر تحميل …» حين تفشل قائمة ← «هذا الطلب عولج من قبل» للطلب المطلوب ← «الموافقة على كل طلبات إضافة ابن»
// ← باب «طلبات الخصوصية» (`AdminPolicyRequestsPage`) ← الطلبات بالأيام (اليوم · أمس · التاريخ)، كل يوم بطاقة من صفوفها
// ← باب «المنجز» (`AdminInboxHandledPage`). لا مسار أقسام ولا صفوف شرائح (spec E.7/E.8).
// السحب كما كان (الطرف: «رفض» + «المزيد»، البداية: الموافقة + «حذف»)، والضغط المطوّل القائمة نفسها، و«تحديد» ← شريط سفلي
// «قبول (N)» · «رفض (N)». نفس الاستدعاءات والصلاحيات تماماً (`canApprove(_:)` / `canReject(_:)` مضروبة في «يعدّل»
// `adminCanEdit(.inbox)`، مسار الموافقات)، وكل كتابة من هنا تمرّ بـ`DebugAdminProbe.dryRun` (T0).
// التوجيه: `focusId` يفتح مربّع الطلب فوق «الوارد» (يُبحث في كل المعلّق بلا فلاتر)، `initialFilter` = «الحالة»،
// `initialSearch` في الحقل، `startsWithMessages` يدفع صفحة الرسائل لمن يملكها، والهبوط (`AdminInboxLanding`) من
// `AdminAreaRouter.take(.inbox, hop:)` — المعاملات الصريحة تغلبه.
// حارس المكدس: الجسم طبقات خلف `AnyView` (كان يفيض بـ١٢٨ ك.ب)، وكل بطاقة جديدة نوع مستقل خلف `AnyView`.
// مربّع الطلب (`requestDetailSheet` … `hardDeleteDetail`) منطقة U9 — بلا تعديل هنا.

struct AdminAllRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @StateObject private var diwaniyaVM = DiwaniyasViewModel()
    @StateObject private var archiveVM = FamilyArchiveViewModel()
    @State private var selectedDetail: RequestDetail? = nil
    /// الطلب المطلوب (`focusId`) ليس بين المعلّق: «عولج من قبل» حين وصلت كل القوائم، و«تعذّر التحميل» حين فشلت قائمة
    @State private var focusMissing: FocusMissing? = nil
    // إدخال سبب الرفض — يُرسل كرسالة لمقدّم الطلب
    @State private var showRejectReason = false
    @State private var rejectReasonText: String = ""
    @State private var rejectReasonDetail: RequestDetail? = nil
    // «حوّل للمدير» — المراقب على طلب انضمام (الرفض = حذف الملف للمالك/المدير وحدهما)، بملاحظة اختيارية
    @State private var forwardJoinMember: FamilyMember? = nil
    @State private var forwardJoinNote: String = ""
    @State private var forwardJoinDone = false
    // حذف نهائي لأي طلب — للمالك/المدير فقط
    // تعديل/إضافة رقم فعلي لعضو معلّق (طلب انضمام)
    @State private var phoneEditPendingMember: FamilyMember? = nil
    // سحب (الكل): رفض مع سبب — وحذف مع تأكيد
    @State private var swipeRejectDetail: RequestDetail? = nil
    @State private var swipeRejectReason: String = ""
    @State private var swipeDeleteDetail: RequestDetail? = nil
    /// «مكانه في الشجرة» لطلب الانضمام: المطابق المعروض (العضو المعلّق ← المطابق) — الضغط على صفّ مطابق يبدّله
    @State private var joinPlacePick: [UUID: UUID] = [:]

    /// نوع الطلب المحدد لعرض التفاصيل
    enum RequestDetail: Identifiable {
        case join(FamilyMember)
        case news(NewsPost)
        case report(AdminRequest)
        case phone(PhoneChangeRequest)
        case nameChange(AdminRequest)
        case diwaniya(Diwaniya)
        case deceased(AdminRequest)
        case child(AdminRequest)
        case photo(AdminRequest)
        case project(Project)
        case archive(ArchiveItem)
        /// طلب تعديل على الشجرة (إضافة/تعديل اسم/تعديل رقم/وفاة/حذف).
        case treeEdit(AdminRequest, TreeEditAction)

        var id: String {
            switch self {
            case .join(let m): return "join-\(m.id)"
            case .news(let n): return "news-\(n.id)"
            case .report(let r): return "report-\(r.id)"
            case .phone(let p): return "phone-\(p.id)"
            case .nameChange(let r): return "name-\(r.id)"
            case .diwaniya(let d): return "diw-\(d.id)"
            case .deceased(let r): return "dec-\(r.id)"
            case .child(let r): return "child-\(r.id)"
            case .photo(let r): return "photo-\(r.id)"
            case .project(let p): return "proj-\(p.id)"
            case .archive(let a): return "arch-\(a.id)"
            case .treeEdit(let r, _): return "tree-\(r.id)"
            }
        }
    }

    /// أقسام رئيسية للطلبات — تجميع منطقي للفلاتر.
    enum RequestSection: String, CaseIterable, Identifiable {
        case members      // أعضاء — انضمام/اسم/جوال/وفاة/معرض
        case tree         // الشجرة — أبناء/إضافة شجرة/حذف شجرة
        case content      // محتوى ونشاط — أخبار/بلاغات/صور/ديوانيات/مشاريع

        var id: String { rawValue }

        var title: String {
            switch self {
            case .members:     return L10n.t("أعضاء", "Members")
            case .tree:        return L10n.t("الشجرة", "Tree")
            case .content:     return L10n.t("محتوى ونشاط", "Content")
            }
        }

        var icon: String {
            switch self {
            case .members:    return "person.2.fill"
            case .tree:       return "tree.fill"
            case .content:    return "doc.fill"
            }
        }

        var color: Color {
            switch self {
            case .members:    return DS.Color.info
            case .tree:       return DS.Color.palm
            case .content:    return DS.Color.accent
            }
        }
    }

    enum RequestTab: String, CaseIterable, Identifiable {
        case all
        // أعضاء
        case joinRequests, nameChange, phone, deceased
        // الشجرة — كل أنواع طلبات تعديل الشجرة + إضافة الأبناء التقليدية
        case children, treeAdd, treeEditName, treeEditPhone, treeEditBirth, treeDeceased, treeAddDeathDate, treeAddPhoto, treeDelete, treeOther
        // محتوى ونشاط
        case news, reports, photos, diwaniya, projects, archive

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return L10n.t("الكل", "All")
            case .joinRequests: return L10n.t("طلبات الانضمام", "Join requests")
            case .news: return L10n.t("أخبار", "News")
            case .reports: return L10n.t("بلاغات", "Reports")
            case .phone: return L10n.t("جوال", "Phone")
            case .nameChange: return L10n.t("أسماء", "Names")
            case .diwaniya: return L10n.t("ديوانيات", "Diwaniyas")
            case .archive: return L10n.t("أرشيف", "Archive")
            case .deceased: return L10n.t("وفاة", "Deceased")
            case .children: return L10n.t("أبناء", "Children")
            case .treeAdd: return L10n.t("إضافة (شجرة)", "Tree · Add")
            case .treeEditName: return L10n.t("تعديل اسم (شجرة)", "Tree · Name")
            case .treeEditPhone: return L10n.t("تعديل رقم (شجرة)", "Tree · Phone")
            case .treeEditBirth: return L10n.t("تعديل ميلاد (شجرة)", "Tree · Birth")
            case .treeDeceased: return L10n.t("وفاة (شجرة)", "Tree · Deceased")
            case .treeAddDeathDate: return L10n.t("تاريخ وفاة (شجرة)", "Tree · Death Date")
            case .treeAddPhoto: return L10n.t("صورة (شجرة)", "Tree · Photo")
            case .treeDelete: return L10n.t("حذف", "Delete")
            case .treeOther: return L10n.t("طلب آخر (شجرة)", "Tree · Other")
            case .photos: return L10n.t("صور مقترحة", "Suggested Photos")
            case .projects: return L10n.t("مشاريع", "Projects")
            }
        }

        var icon: String {
            switch self {
            case .all: return "tray.full.fill"
            case .joinRequests: return "person.badge.shield.checkmark"
            case .news: return "newspaper.fill"
            case .reports: return "exclamationmark.bubble.fill"
            case .phone: return "phone.badge.checkmark"
            case .nameChange: return "rectangle.and.pencil.and.ellipsis"
            case .diwaniya: return "tent.fill"
            case .archive: return "archivebox.fill"
            case .deceased: return "leaf.fill"
            case .children: return "person.badge.plus"
            case .treeAdd: return "person.crop.circle.badge.plus"
            case .treeEditName: return "pencil.line"
            case .treeEditPhone: return "phone.arrow.up.right"
            case .treeEditBirth: return "calendar"
            case .treeDeceased: return "leaf.fill"
            case .treeAddDeathDate: return "calendar.badge.exclamationmark"
            case .treeAddPhoto: return "photo.badge.plus"
            case .treeDelete: return "person.badge.minus"
            case .treeOther: return "square.and.pencil"
            case .photos: return "camera.badge.ellipsis"
            case .projects: return "briefcase.fill"
            }
        }

        var color: Color {
            switch self {
            case .all: return AppSection.admin.ink
            case .joinRequests: return DS.Color.info
            case .news: return DS.Color.accent
            case .reports: return DS.Color.error
            case .phone: return AppSection.admin.ink
            case .nameChange: return DS.Color.palm
            case .diwaniya: return DS.Color.gridDiwaniya
            case .archive: return DS.Color.sadu
            case .deceased: return DS.Color.slate
            case .children: return DS.Color.info
            case .treeAdd: return DS.Color.palm
            case .treeEditName: return DS.Color.palm
            case .treeEditPhone: return AppSection.admin.ink
            case .treeEditBirth: return DS.Color.palm
            case .treeDeceased: return DS.Color.slate
            case .treeAddDeathDate: return DS.Color.slate
            case .treeAddPhoto: return AppSection.admin.ink
            case .treeDelete: return DS.Color.error
            case .treeOther: return DS.Color.accent
            case .photos: return DS.Color.sadu
            case .projects: return DS.Color.accent
            }
        }

        /// القسم الذي ينتمي إليه — nil لـ .all (ليس له قسم).
        var section: RequestSection? {
            switch self {
            case .all: return nil
            case .joinRequests, .nameChange, .phone, .deceased: return .members
            case .children, .treeAdd, .treeEditName, .treeEditPhone, .treeEditBirth, .treeDeceased, .treeAddDeathDate, .treeAddPhoto, .treeDelete, .treeOther: return .tree
            case .news, .reports, .photos, .diwaniya, .projects, .archive: return .content
            }
        }
    }

    // MARK: - «الوارد»: الحالة

    /// فلاتر الورقة (spec A.13): الحالة · المجموعة · النوع · المصدر — بقيم عقد الهبوط (`AdminInboxLogic.Filters`)
    @State private var filters = AdminInboxLogic.Filters()
    @State private var showsFilters = false
    /// مخزن «المنجز» الواحد: رقم صفّه آخر القائمة، وصفحته، و«من أين وصل» في مربّع الطلب
    @StateObject private var handledStore = AdminHandledStore()
    /// حقل البحث الواحد
    @State private var searchText: String = ""
    /// طلب يُفتح مربّعه بعد التحميل (الإشعار، «اليوم»، «إشعارات الإدارة») — مرة واحدة
    private let focusId: UUID?
    @State private var focusHandled = false
    /// «الحالة» الممرّرة صراحةً — تغلب الهبوط
    private let explicitStatus: Bool
    private let explicitSearch: Bool
    private let startsWithMessages: Bool

    init(focusId: UUID? = nil, initialFilter: ApprovalListFilter = .all,
         startsWithMessages: Bool = false, initialSearch: String = "") {
        self.focusId = focusId
        self.startsWithMessages = startsWithMessages
        explicitStatus = initialFilter != .all
        explicitSearch = !initialSearch.isEmpty
        _filters = State(initialValue: AdminInboxLogic.Filters(
            status: AdminInboxLogic.Status(rawValue: initialFilter.rawValue) ?? .all))
        _searchText = State(initialValue: initialSearch)
    }

    /// حال كل قائمة (عقد U2 `AdminStoreHealth`) — نموذج العرض يبتلع الخطأ، فالفشل = انتهى الجلب والجهاز غير متصل
    /// (أو `-tmpFailStores inbox`)
    @State private var storeHealth: [AdminInboxLogic.Store: AdminStoreHealth] = [:]
    /// أول ظهور: الهبوط والطلب المطلوب والرسائل والجلب مرة واحدة (الرجوع من صفحة باب لا يعيدها)
    @State private var didStart = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dsLandscape) private var landscape
    /// عدّاد الانتقال (`.area(.inbox, hop)`) — مفتاح الهبوط
    @Environment(\.adminAreaHop) private var areaHop
    @Environment(\.adminBackTitle) private var outerBack
    @Environment(\.dismiss) private var dismiss
    @State private var showBulkApproveChildrenConfirm = false
    @State private var bulkApproveResult: String?
    @State private var showBulkApproveResult = false

    // التحديد المتعدّد
    @State private var isSelectMode = false
    /// «ظهور موحّد»: الصفوف تصعد مرة عند ظهورها الأول (`dsCardCascade`)
    @State private var rowsAppeared = false
    @State private var selectedIds: Set<UUID> = []
    @State private var showBulkApproveConfirm = false
    @State private var bulkSelectApproveResult: String?
    @State private var showBulkSelectApproveResult = false
    @State private var showBulkRejectConfirm = false
    @State private var bulkSelectRejectResult: String?
    @State private var showBulkSelectRejectResult = false

    /// الصفحة المدفوعة من باب (الرسائل · المنجز · الخصوصية · ⚙︎) — وجهة واحدة على مستوى الصفحة (لا `NavigationLink`
    /// داخل خلية `List`)
    @State private var door: Door? = nil
    @State private var doorOpen = false
    @State private var showsPostReview = false
    @ObservedObject private var postReview = PostReviewStore.shared

    // Join request states
    @State private var memberToLink: FamilyMember? = nil
    /// مربّع «المطابقات المحتملة» لطلب انضمام (العيّنة ١٨)
    @State private var joinMatchesFor: FamilyMember? = nil
    @State private var mergeTarget: (pendingMember: FamilyMember, treeMember: FamilyMember)? = nil
    @State private var showMergeConfirm = false
    @State private var showMergeSuccess = false
    @State private var mergeSuccessMessage = ""
    /// مطابقات التسجيل من السيرفر (matched_ids من admin_requests)
    @State private var registrationMatches: [UUID: [UUID]] = [:]
    /// الأعضاء اللي المدير فتح كل المتطابقين حقهم
    @State private var expandedMatchMembers: Set<UUID> = []
    /// «الأرجح أولاً»: السجلّ المختار لكل طلب انضمام (بلا اختيار = الأرجح) ودرجاته المحفوظة
    @State private var joinPicks: [UUID: UUID] = [:]
    @State private var joinTierCache = JoinTierCache()

    @State private var cachedPendingMembers: [FamilyMember] = []
    private var pendingMembers: [FamilyMember] { cachedPendingMembers }

    /// عناصر الأرشيف المعلّقة (بانتظار اعتماد الإدارة).
    private var pendingArchiveItems: [ArchiveItem] {
        archiveVM.items.filter { $0.approvalStatus == .pending }
    }

    private enum Door: Equatable {
        case messages, handled, settings
        case policy(UUID?)
    }

    private enum FocusMissing { case handled, failed }

    // حارس المكدس (الدفعة ب ٢٠٢٦-١٠-٢٠): الجسم طبقات خلف `AnyView` — الصفحة، ثم تنبيهات العمليات الجماعية، ثم المربّعات
    // والتأكيدات — فلا يُحلّ نوع سلسلة المُعدِّلات كلها دفعة واحدة (كانت تفيض مكدساً بـ١٢٨ ك.ب)
    var body: some View {
        AnyView(joinBoxLayer(AnyView(modalsLayer(AnyView(bulkAlertsLayer(AnyView(pageLayer)))))))
            .debugStackProbe("AdminAllRequestsView", limitKB: DebugStackLimit.page)
    }

    /// الصفحة: القائمة وشريط التحديد والأرضية (طبقة)، ثم الوجهة والورقتان والمراقبات
    private var pageLayer: some View {
        let model = makeModel()
        return AnyView(pageChrome(AnyView(list(model)), model))
            .navigationDestination(isPresented: $doorOpen) { doorPage }
            .adminFilterSheet(isPresented: $showsFilters, set: model.filterSet, selection: $filters)
            .dsTallBox(isPresented: $showsPostReview) {
                PostReviewQueuePage(onClose: { showsPostReview = false })
            }
            .onChange(of: filters) { _ in clearSelection() }
            // أعداد «الوارد» تتبع القوائم لحظياً (قرار من مربّع، طلب جديد، تحديث من الإشعار)
            .onChange(of: requestsSignature) { _ in
                guard didStart else { return }
                recalculateCounts()
            }
            // موافقة أو رفض هنا يغيّر العدد ← «بانتظار المراجعة» و«المنجز» يتحدّثان
            .onChange(of: totalCount) { _ in
                Task {
                    await PostReviewStore.shared.refresh()
                    if handledStore.loadedOnce { await handledStore.reload() }
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .task { await start() }
    }

    private func pageChrome(_ list: AnyView, _ model: InboxModel) -> some View {
        list
            // شريط التحديد — مثبّت في الأسفل، وآخر صفّ يبقى فوقه
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelectMode {
                    AnyView(selectionBar(model))
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(DS.Anim.snappy, value: isSelectMode)
            .adminHideTopEdgeEffect()
            // السحب للأسفل فوق الرأس يكشف كحلياً لا أبيض (نفس صفحات الأقسام)
            .background(alignment: .top) {
                AdminBandBackground().frame(height: AdminHubMetrics.pullReveal).ignoresSafeArea(edges: .top)
            }
            .background(DS.Hub.background.ignoresSafeArea())
            // منطقة شريط الحالة كحلية فوق الرأس الكحلي، والرأس شريط الصفحة (سحب الرجوع من الحافة يبقى)
            .adminStatusBarCover()
            .toolbar(.hidden, for: .navigationBar)
    }

    /// تأكيدات العمليات الجماعية ونتائجها، وأخطاء الموافقة/الرفض
    /// مربّع «المطابقات المحتملة» (العيّنة ١٨): الضغط على مرشّح يختاره ويُغلق، و«اختر من الشجرة» المنتقي الموجود
    private func joinBoxLayer(_ content: AnyView) -> some View {
        content.dsCenterBox(item: $joinMatchesFor) { member in
            AnyView(JoinMatchesBox(info: joinCardInfo(for: member),
                                   onPick: { id in joinPicks[member.id] = id; joinMatchesFor = nil },
                                   onPickFromTree: {
                                       joinMatchesFor = nil
                                       // بعد إغلاق المربّع — مربّع واحد في المرة
                                       DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.boxHandoff) { memberToLink = member }
                                   },
                                   onClose: { joinMatchesFor = nil }))
        }
    }

    private func bulkAlertsLayer(_ content: AnyView) -> some View {
        content
        .dsAlert(
            L10n.t("الموافقة على الكل؟", "Approve all?"),
            isPresented: $showBulkApproveChildrenConfirm
        ) {
            Button(L10n.t("وافق على الكل", "Approve all")) {
                Task {
                    let total = adminRequestVM.childAddRequests.count
                    let count: Int
                    if DebugAdminProbe.dryRun("inbox approve all child additions (\(total))") {
                        count = total
                    } else {
                        count = await adminRequestVM.bulkApproveChildAddRequests()
                    }
                    if count > 0 { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                    bulkApproveResult = bulkResultText(done: count, total: total, approving: true)
                    showBulkApproveResult = true
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t(
                "تُقبل كل طلبات إضافة الأبناء المعلّقة (\(adminRequestVM.childAddRequests.count) طلب).",
                "All pending child add requests (\(adminRequestVM.childAddRequests.count)) will be approved."
            ))
        }
        .dsAlert(
            L10n.t("تم", "Done"),
            isPresented: $showBulkApproveResult,
            moment: .approved
        ) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(bulkApproveResult ?? "")
        }
        .dsAlert(
            AdminInboxText.bulkApproveQuestion(selectedIds.count),
            isPresented: $showBulkApproveConfirm
        ) {
            Button(L10n.t("قبول", "Approve")) {
                Task {
                    let total = bulkAttemptCount(approving: true)
                    let count = await bulkApproveSelected()
                    await MainActor.run {
                        if count > 0 { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                        bulkSelectApproveResult = bulkResultText(done: count, total: total, approving: true)
                        showBulkSelectApproveResult = true
                        isSelectMode = false
                        selectedIds.removeAll()
                        recalculateCounts()
                    }
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("يُقبل ما يخصّ صلاحيتك منها، والباقي يبقى معلّقاً.",
                        "The ones within your role are approved; the rest stay pending."))
        }
        .dsAlert(
            L10n.t("تم", "Done"),
            isPresented: $showBulkSelectApproveResult,
            moment: .approved
        ) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(bulkSelectApproveResult ?? "")
        }
        .dsAlert(
            AdminInboxText.bulkRejectQuestion(selectedIds.count),
            isPresented: $showBulkRejectConfirm
        ) {
            Button(L10n.t("رفض", "Reject"), role: .destructive) {
                Task {
                    let total = bulkAttemptCount(approving: false)
                    let count = await bulkRejectSelected()
                    await MainActor.run {
                        bulkSelectRejectResult = bulkResultText(done: count, total: total, approving: false)
                        showBulkSelectRejectResult = true
                        isSelectMode = false
                        selectedIds.removeAll()
                        recalculateCounts()
                    }
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("يُرفض ما يخصّ صلاحيتك منها ويبقى في السجل.",
                        "The ones within your role are rejected and kept in the log."))
        }
        .dsAlert(
            L10n.t("تم", "Done"),
            isPresented: $showBulkSelectRejectResult
        ) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(bulkSelectRejectResult ?? "")
        }
        // أخطاء الموافقة/الرفض ظاهرة (كانت تُسجَّل فقط): طلب عالجه غيرك، لا صلاحية، فشل التنفيذ
        .dsAlert(
            L10n.t("تنبيه", "Notice"),
            isPresented: Binding(
                get: { adminRequestVM.errorMessage != nil },
                set: { if !$0 { adminRequestVM.errorMessage = nil } }
            )
        ) {
            Button(L10n.t("حسناً", "OK")) { adminRequestVM.errorMessage = nil }
        } message: {
            Text(adminRequestVM.errorMessage ?? "")
        }
        // خطأ اعتماد/رفض مشروع (الحذف كان تفاؤلياً وتعود البطاقة)
        .dsAlert(
            L10n.t("تنبيه", "Notice"),
            isPresented: Binding(
                get: { projectsVM.decisionError != nil },
                set: { if !$0 { projectsVM.decisionError = nil } }
            )
        ) {
            Button(L10n.t("حسناً", "OK")) { projectsVM.decisionError = nil }
        } message: {
            Text(projectsVM.decisionError ?? "")
        }
    }

    /// مربّع تفاصيل الطلب، والسحب (رفض/حذف)، وربط طلب الانضمام ودمجه — كل كتابة تمرّ بـ`DebugAdminProbe.dryRun`
    private func modalsLayer(_ content: AnyView) -> some View {
        content
        // مربّع الطلب (U9، spec A.15/C.3): ورقة طويلة بمقبض ومكدسها — الانتقال للطلب التالي داخلها لا يُغلقها
        .dsTallBox(item: $selectedDetail) { detail in
            requestDetailSheet(detail)
                .dsAlert(L10n.t("سبب الرفض", "Rejection Reason"), isPresented: $showRejectReason) {
                    TextField(L10n.t("اكتب السبب (اختياري)", "Reason (optional)"), text: $rejectReasonText)
                        .dsAlertField()
                    Button(L10n.t("إرسال الرفض", "Send Rejection"), role: .destructive) {
                        if let d = rejectReasonDetail { reject(d, reason: rejectReasonText) }
                        rejectReasonDetail = nil
                    }
                    Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { rejectReasonDetail = nil }
                } message: {
                    Text(L10n.t("سيصل السبب كرسالة إلى مقدّم الطلب.",
                                "The reason will be sent as a message to the requester."))
                }
                .dsAlert(L10n.t("حوّل للمدير", "Forward to manager"),
                         isPresented: Binding(get: { forwardJoinMember != nil },
                                              set: { if !$0 { forwardJoinMember = nil } })) {
                    TextField(L10n.t("ملاحظة للمدير (اختياري)", "Note for the manager (optional)"), text: $forwardJoinNote)
                        .dsAlertField()
                    Button(L10n.t("تحويل", "Forward")) {
                        if let m = forwardJoinMember {
                            if DebugAdminProbe.dryRun("inbox forward join \(m.id) to manager") {
                                forwardJoinDone = true
                            } else {
                                forwardJoin(m, note: forwardJoinNote)
                            }
                        }
                        forwardJoinMember = nil
                    }
                    Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { forwardJoinMember = nil }
                } message: {
                    Text(L10n.t("رفض طلب الانضمام للمالك والمدير — يصلهم إشعار بالطلب وملاحظتك ليقرّروا.",
                                "Rejecting a join request is for the owner and admin — they get a notice with your note to decide."))
                }
        }
        .dsAlert(L10n.t("حُوّل للمدير", "Forwarded to the manager"), isPresented: $forwardJoinDone,
                 moment: .success) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(L10n.t("وصل المالك والمدير إشعار بالطلب، والطلب باقٍ في «الوارد» حتى يقرّرا.",
                        "The owner and admin were notified; the request stays in the inbox until they decide."))
        }
        // رفض عبر السحب أو الضغط المطوّل — سبب الرفض ثم التأكيد
        .dsAlert(
            L10n.t("سبب الرفض", "Rejection Reason"),
            isPresented: Binding(
                get: { swipeRejectDetail != nil },
                set: { if !$0 { swipeRejectDetail = nil } }
            )
        ) {
            TextField(L10n.t("اكتب السبب (اختياري)", "Reason (optional)"), text: $swipeRejectReason)
                .dsAlertField()
            Button(L10n.t("تأكيد الرفض", "Confirm Reject"), role: .destructive) {
                if let d = swipeRejectDetail {
                    let trimmed = swipeRejectReason.trimmingCharacters(in: .whitespacesAndNewlines)
                    reject(d, reason: trimmed.isEmpty ? nil : trimmed)
                }
                swipeRejectDetail = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { swipeRejectDetail = nil }
        } message: {
            Text(L10n.t("سيُرفَض الطلب ويبقى في السجل.", "The request will be rejected and kept in the log."))
        }
        // حذف عبر السحب أو الضغط المطوّل — تأكيد نهائي بالمنتصف
        .dsAlert(
            L10n.t("حذف الطلب نهائياً؟", "Delete request permanently?"),
            isPresented: Binding(
                get: { swipeDeleteDetail != nil },
                set: { if !$0 { swipeDeleteDetail = nil } }
            )
        ) {
            Button(L10n.t("حذف نهائي", "Delete Permanently"), role: .destructive) {
                if let d = swipeDeleteDetail {
                    if !DebugAdminProbe.dryRun("inbox delete request \(d.id)") { hardDeleteDetail(d) }
                }
                swipeDeleteDetail = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { swipeDeleteDetail = nil }
        } message: {
            Text(L10n.t(
                "سيُحذف الطلب نهائياً من قاعدة البيانات ولا يمكن التراجع.",
                "This request will be permanently removed and cannot be undone."
            ))
        }
        .dsTallBox(item: $memberToLink) { member in   // قائمة أعضاء طويلة (توصية أبل)
            // طلب الأنثى: المربّع نفسه يفتح «ربط بشجرة النساء» (دخول النساء ٢٠٢٦-١٠-٢٤)
            LinkToExistingMemberSheet(pendingMember: member,
                                      suggested: orderedMatchList(for: member).map(\.member),
                                      onWomanLinked: { recalculateCounts() })
                .environmentObject(memberVM)
                .environmentObject(adminRequestVM)
        }
        .dsAlert(
            L10n.t("تأكيد الدمج", "Confirm Merge"),
            isPresented: $showMergeConfirm
        ) {
            Button(L10n.t("دمج", "Merge"), role: .destructive) {
                if let target = mergeTarget {
                    if DebugAdminProbe.dryRun("inbox merge \(target.pendingMember.id) into \(target.treeMember.id)") {
                        mergeSuccessMessage = L10n.t("تجربة: لم يُرسل شيء للسيرفر.", "Dry run: nothing was sent.")
                        showMergeSuccess = true
                        mergeTarget = nil
                        return
                    }
                    Task {
                        await adminRequestVM.mergeMemberIntoTreeMember(
                            newMemberId: target.pendingMember.id,
                            existingTreeMemberId: target.treeMember.id
                        )
                        await MainActor.run {
                            if let result = adminRequestVM.mergeResult {
                                switch result {
                                case .success(let msg):
                                    mergeSuccessMessage = msg
                                case .failure(let msg):
                                    mergeSuccessMessage = msg
                                }
                                showMergeSuccess = true
                            }
                            mergeTarget = nil
                        }
                    }
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {
                mergeTarget = nil
            }
        } message: {
            if let target = mergeTarget {
                Text(L10n.t(
                    "سيتم ربط حساب \(target.pendingMember.fullName) بسجل \(target.treeMember.fullName) الموجود بالشجرة.",
                    "This will link \(target.pendingMember.fullName)'s account to \(target.treeMember.fullName)'s tree record."
                ))
            }
        }
        .dsAlert(
            {
                if case .failure = adminRequestVM.mergeResult {
                    return L10n.t("خطأ في الدمج", "Merge Error")
                }
                return L10n.t("تم الدمج", "Merge Complete")
            }(),
            isPresented: $showMergeSuccess,
            moment: { if case .success = adminRequestVM.mergeResult { return .success }; return nil }()
        ) {
            Button(L10n.t("حسناً", "OK")) {
                adminRequestVM.mergeResult = nil
            }
        } message: {
            Text(mergeSuccessMessage)
        }
    }

    /// رفض من السحب أو من مربّع الطلب (بسبب) — نفس `rejectDetail`، وتجربة الدور لا ترسل شيئاً
    private func reject(_ detail: RequestDetail, reason: String?) {
        if DebugAdminProbe.dryRun("inbox reject \(detail.id)") { return }
        rejectDetail(detail, reason: reason)
    }

    // MARK: - النموذج: يُحسب مرة لكل رسم

    /// طلب واحد بما يحتاجه الرسم والفلتر
    fileprivate struct Entry: Identifiable {
        let item: AllItem
        let fact: AdminInboxLogic.Fact
        let date: Date
        let flow: ApprovalSnapshot?
        var id: String { item.id }
    }

    fileprivate struct InboxModel {
        /// كل طلبات المجال (بلا بحث ولا فلاتر)
        let entries: [Entry]
        /// بعد البحث والفلاتر — بالأيام
        let days: [DSDayGroup<Entry>]
        let visible: [Entry]
        let filterSet: AdminFilterSet<AdminInboxLogic.Filters>
        let header: AdminInboxLogic.HeaderCounts
        let phase: AdminInboxLogic.Phase

        /// وصلت أرقام تُعرض (لا هيكل ولا فشل كلي)
        var ready: Bool { phase != .loading && phase != .failed }
    }

    private func makeModel() -> InboxModel {
        typealias L = AdminInboxLogic
        let workflowOn = adminRequestVM.approvalsWorkflowOn
        let entries = sortedAllItems.map(entry)
        let searched = searchedEntries(entries)
        let current = filters
        let visible = searched.filter { L.matches($0.fact, current, workflowOn: workflowOn) }
        let phase = L.phase(storeHealth, relevant: relevantStores)
        let ready = phase != .loading && phase != .failed
        return InboxModel(entries: entries,
                          days: dayGroups(visible),
                          visible: visible,
                          filterSet: filterSet(facts: searched.map(\.fact), ready: ready, workflowOn: workflowOn),
                          header: L.headerCounts(entries.map(\.fact), workflowOn: workflowOn),
                          phase: phase)
    }

    private func entry(_ item: AllItem) -> Entry {
        let flow = approvalSnapshot(for: item)
        let source = origin(for: requestDetail(for: item)).flatMap { AdminInboxLogic.Source(rawValue: $0.kind.rawValue) }
        let fact = AdminInboxLogic.Fact(kind: filterKind(item), source: source, inFlow: flow != nil,
                                        waiting: flow.map(adminRequestVM.isApprovalWaitingForMe) ?? false,
                                        urgent: flow?.isUrgent ?? false,
                                        late: flow.map { $0.isLate || $0.isEscalated } ?? false)
        return Entry(item: item, fact: fact, date: allItemDate(item), flow: flow)
    }

    /// نوع الفلتر: طلب الشجرة بإجرائه (`allItemTab` يجمعها في «طلب آخر» لأجل الصلاحية فقط)
    private func filterKind(_ item: AllItem) -> AdminInboxLogic.Kind {
        if case .treeEdit(_, let action) = item { return Self.treeKind(action) }
        return AdminInboxLogic.Kind(rawValue: allItemTab(item).rawValue) ?? .treeOther
    }

    private static func treeKind(_ action: TreeEditAction) -> AdminInboxLogic.Kind {
        switch action {
        case .add:          return .treeAdd
        case .editName:     return .treeEditName
        case .editPhone:    return .treeEditPhone
        case .editBirth:    return .treeEditBirth
        case .deceased:     return .treeDeceased
        case .addDeathDate: return .treeAddDeathDate
        case .addPhoto:     return .treeAddPhoto
        case .delete:       return .treeDelete
        case .other:        return .treeOther
        }
    }

    /// الأيام (الأحدث أولاً)، وداخل اليوم: العاجل ثم ما ينتظرك ثم الأحدث. ما بلا تاريخ (الديوانيات) آخراً
    private func dayGroups(_ entries: [Entry]) -> [DSDayGroup<Entry>] {
        let calendar = Calendar.current
        let rank: (Entry) -> Int = { $0.fact.urgent ? 0 : ($0.fact.waiting ? 1 : 2) }
        let dated = entries.filter { $0.date != .distantPast }.sorted { a, b in
            let da = calendar.startOfDay(for: a.date), db = calendar.startOfDay(for: b.date)
            if da != db { return da > db }
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            return a.date > b.date
        }
        var groups = DSDayBuckets.group(dated) { $0.date }
        let undated = entries.filter { $0.date == .distantPast }
        if !undated.isEmpty {
            groups.append(DSDayGroup(day: .distantPast, title: L10n.t("بلا تاريخ", "No date"), items: undated))
        }
        return groups
    }

    /// القوائم التي تخصّ هذا الدور (حالها يقرّر الهيكل والفشل)
    private var relevantStores: [AdminInboxLogic.Store] {
        let kinds = Set(tabsForRole(RequestTab.allCases).compactMap { AdminInboxLogic.Kind(rawValue: $0.rawValue) })
        return AdminInboxLogic.Store.allCases.filter { $0.isRelevant(to: kinds) }
    }

    /// القوائم الفاشلة الآن — «أعد المحاولة» يعيدها وحدها
    private var failedStores: Set<AdminInboxLogic.Store> {
        Set(relevantStores.filter { storeHealth[$0]?.canRetry == true })
    }

    // MARK: - ورقة الفلاتر (spec A.13 + C.2): الحالة · المجموعة · النوع (بعد المجموعة) · المصدر (الموجود فقط)

    private func filterSet(facts: [AdminInboxLogic.Fact], ready: Bool,
                           workflowOn: Bool) -> AdminFilterSet<AdminInboxLogic.Filters> {
        typealias L = AdminInboxLogic
        let count: (L.Filters) -> Int? = { ready ? L.count(facts, $0, workflowOn: workflowOn) : nil }
        let roleKinds = Set(tabsForRole(RequestTab.allCases).compactMap { L.Kind(rawValue: $0.rawValue) })
        let roleGroups = L.Group.allCases.filter { g in roleKinds.contains { $0.group == g } }
        let presentSources = L.Source.allCases.filter { s in facts.contains { $0.source == s } }
        return AdminFilterSet(reset: L.Filters(), noun: AdminInboxText.requestsNoun, normalize: L.normalize,
                              resultCount: count) { s in
            var groups: [AdminFilterGroup<L.Filters>] = []
            // الحالة: «عاجل» و«متأخر» من مسار الموافقات — مطفأ = لا تظهران (إلا المختارة من رابط)
            var statuses: [L.Status] = workflowOn ? L.Status.allCases : [.all, .waiting]
            if !statuses.contains(s.status) { statuses.append(s.status) }
            groups.append(.choices("status", title: L10n.t("الحالة", "Status"), value: \.status, all: .all,
                                   options: statuses.map { status in
                                       var next = s
                                       next.status = status
                                       return AdminFilterOption(status, Self.statusTitle(status), count: count(next))
                                   }))
            // المجموعة — حين يرى الدور أكثر من مجموعة
            if roleGroups.count > 1 || s.group != nil {
                let all = L.Filters(status: s.status, source: s.source)
                let options = [AdminFilterOption<L.Group?>(nil, L10n.t("الكل", "All"), count: count(all))]
                    + roleGroups.map { g in
                        AdminFilterOption<L.Group?>(g, Self.groupTitle(g),
                                                    count: count(L.Filters(status: s.status, group: g, source: s.source)))
                    }
                groups.append(.choices("group", title: L10n.t("المجموعة", "Group"), value: \.group, all: nil,
                                       options: options))
            }
            // النوع — بعد اختيار مجموعة: «كل المجموعة» ثم ما فيه طلبات (والمختار)
            if let g = s.group {
                let base = L.Filters(status: s.status, group: g, source: s.source)
                let kinds = L.Kind.allCases.filter { k in
                    k.group == g && roleKinds.contains(k)
                        && ((count(L.Filters(status: s.status, kind: k, source: s.source)) ?? 1) > 0 || s.kind == k)
                }
                let options = [AdminFilterOption<L.Kind?>(nil, L10n.t("كل \(Self.groupTitle(g))", "All \(Self.groupTitle(g))"),
                                                          count: count(base))]
                    + kinds.map { k in
                        AdminFilterOption<L.Kind?>(k, Self.kindTitle(k),
                                                   count: count(L.Filters(status: s.status, kind: k, source: s.source)))
                    }
                groups.append(.choices("kind", title: L10n.t("النوع", "Type"), value: \.kind, all: nil, options: options))
            }
            // المصدر — المصادر الموجودة فقط (اثنان فأكثر، أو المختار)
            var sources = presentSources
            if let chosen = s.source, !sources.contains(chosen) { sources.append(chosen) }
            if sources.count >= 2 || s.source != nil {
                var all = s
                all.source = nil
                let options = [AdminFilterOption<L.Source?>(nil, L10n.t("الكل", "All"), count: count(all))]
                    + sources.map { src in
                        var next = s
                        next.source = src
                        return AdminFilterOption<L.Source?>(src, Self.sourceTitle(src), count: count(next))
                    }
                groups.append(.choices("source", title: L10n.t("المصدر", "Source"), value: \.source, all: nil,
                                       options: options))
            }
            return groups
        }
    }

    private static func statusTitle(_ s: AdminInboxLogic.Status) -> String {
        switch s {
        case .all:     return L10n.t("كل الطلبات", "All requests")
        case .waiting: return L10n.t("بانتظار قرارك", "Awaiting you")
        case .urgent:  return L10n.t("عاجل", "Urgent")
        case .late:    return L10n.t("متأخر", "Late")
        }
    }

    private static func groupTitle(_ g: AdminInboxLogic.Group) -> String {
        RequestSection(rawValue: g.rawValue)?.title ?? g.rawValue
    }

    private static func kindTitle(_ k: AdminInboxLogic.Kind) -> String {
        guard let tab = RequestTab(rawValue: k.rawValue) else { return k.rawValue }
        guard tab.section == .tree else { return tab.title }
        // داخل «الشجرة» لا حاجة لتكرار «(شجرة)»
        return tab.title.replacingOccurrences(of: " (شجرة)", with: "").replacingOccurrences(of: "Tree · ", with: "")
    }

    private static func sourceTitle(_ s: AdminInboxLogic.Source) -> String {
        AdminRequestSourceKind(rawValue: s.rawValue)?.title ?? s.rawValue
    }

    // MARK: - البحث

    /// يبحث الآن (نصّ غير فارغ)
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// البحث الدقيق الواحد (`NameSearch`): كل كلمة بداية كلمة بالترتيب (والرقم أرقاماً فقط)
    private func searchedEntries(_ entries: [Entry]) -> [Entry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        if NameSearch.isPhoneQuery(q) {
            let digits = NameSearch.digits(q)
            guard digits.count >= 3 else { return [] }
            return entries.filter { searchTexts($0.item).contains { NameSearch.digits($0).contains(digits) } }
        }
        return entries.filter { NameSearch.matches(query: q, any: searchTexts($0.item)) }
    }

    /// نصوص البحث لكل طلب: الاسم، مقدّم الطلب، الرقم، القيمة الجديدة، العنوان
    private func searchTexts(_ item: AllItem) -> [String] {
        func person(_ m: FamilyMember?) -> [String] { [m?.fullName, m?.phoneNumber].compactMap { $0 } }
        func request(_ r: AdminRequest) -> [String] {
            person(r.member) + person(memberVM.member(byId: r.requesterId)) + [r.newValue, r.details].compactMap { $0 }
        }
        switch item {
        case .join(let m): return person(m)
        case .news(let p): return [p.author_name, p.content]
        case .report(let r), .nameChange(let r), .deceased(let r), .child(let r), .photo(let r): return request(r)
        case .treeEdit(let r, _): return request(r)
        case .phone(let r):
            return person(r.member) + [r.newValue].compactMap { $0 } + person(r.requesterId.flatMap(memberVM.member(byId:)))
        case .diwaniya(let d): return [d.title]
        case .project(let p): return [p.title]
        case .archive(let a): return [a.title]
        }
    }

    // MARK: - البداية والجلب

    /// أول ظهور: الهبوط ← الرسائل لمن طلبها ← الجلب ← الطلب المطلوب ← «المنجز» بعده (بلا انتظار)
    private func start() async {
        guard !didStart else { return }
        didStart = true
        applyLanding()
        // فُتح على «الرسائل» (إشعار/بحث/رابط): صفحتها فوق «الوارد» — لمن يراها في جدول السيرفر وحده
        if startsWithMessages && canSeeMessages {
            DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.boxHandoff) { open(.messages) }
        }
        // رسالة قديمة من إجراء خارج هذه الشاشة (قبول من الإشعار مثلاً) لا تظهر عند الفتح
        adminRequestVM.errorMessage = nil
        diwaniyaVM.notificationVM = notificationVM
        diwaniyaVM.canModerate = authVM.canModerate
        diwaniyaVM.authVM = authVM
        archiveVM.configure(authVM: authVM, notificationVM: notificationVM)
        await reload()
        // «المنجز» بعد الطلبات — رقم صفّه، وصفحته تفتح على ما وصل
        if !handledStore.loadedOnce && !handledStore.isLoading {
            handledStore.includesDeletions = authVM.canModerateTree
            await handledStore.reload()
        }
    }

    /// الهبوط (`AdminInboxLanding` بعدّاد الانتقال) مرة واحدة — مقصوصاً على أنواع الدور؛ المعاملات الصريحة تغلبه
    private func applyLanding() {
        guard let landing = AdminAreaRouter.take(.inbox, hop: areaHop) else { return }
        let allowed = Set(tabsForRole(RequestTab.allCases).map(\.rawValue))
        var next = AdminInboxLogic.Filters(landing: landing.clamped(toKinds: allowed))
        if explicitStatus { next.status = filters.status }
        filters = next
    }

    /// الجلب المتوازي لكل القوائم (أو الفاشلة وحدها) — المفتاح طازجاً قبلها. حال كل قائمة بعد انتهائها
    private func reload(_ only: Set<AdminInboxLogic.Store>? = nil) async {
        typealias S = AdminInboxLogic.Store
        let targets = only ?? Set(S.allCases)
        for s in targets { storeHealth[s] = (storeHealth[s] ?? .idle).beginning() }
        // «مسار الموافقات»: المفتاح طازجاً قبل القوائم (مطفأ = لا شيء يتغيّر)
        await adminRequestVM.refreshApprovalsFlag()
        // `-tmpFailStores inbox`: جانب المحتوى يفشل بلا جلب (`@ثوانٍ` بعد أول تحميل ناجح)
        let contentHasData = S.allCases.contains { $0.isContent && storeHealth[$0]?.hasData == true }
        let injected = DebugAdminProbe.shouldFail(.inbox, hasLoaded: contentHasData)
        let run = targets.filter { !(injected && $0.isContent) }
        await withTaskGroup(of: Void.self) { group in
            for s in run {
                group.addTask { @MainActor in await fetch(s) }
            }
            if only == nil {
                if canSeeMessages {
                    group.addTask { @MainActor in await adminRequestVM.fetchContactMessages() }
                }
                group.addTask { @MainActor in await PostReviewStore.shared.refresh() }
            }
        }
        let online = NetworkMonitor.shared.isConnected
        for s in targets {
            storeHealth[s] = (storeHealth[s] ?? .loading).ending(success: online && !(injected && s.isContent))
        }
        if run.contains(.joins) { await fetchAllRegistrationMatches() }
        recalculateCounts()
        openFocusIfNeeded()
    }

    /// جلب قائمة واحدة — نفس نداءات نماذج العرض
    private func fetch(_ store: AdminInboxLogic.Store) async {
        switch store {
        case .joins:
            await memberVM.fetchAllMembers()
            // مراحل طلبات الانضمام (المسار شغّال فقط — وإلا لا طلب)
            await adminRequestVM.fetchJoinApprovalRequests()
        case .names:     await adminRequestVM.fetchNameChangeRequests()
        case .phones:    await adminRequestVM.fetchPhoneChangeRequests()
        case .deceased:  await adminRequestVM.fetchDeceasedRequests()
        case .children:  await adminRequestVM.fetchChildAddRequests()
        case .treeEdits: await adminRequestVM.fetchTreeEditRequests(force: true)
        case .news:      await newsVM.fetchPendingNewsRequests()
        case .reports:   await adminRequestVM.fetchNewsReportRequests()
        case .photos:    await adminRequestVM.fetchPhotoSuggestionRequests()
        case .diwaniyas: await diwaniyaVM.fetchPendingDiwaniyas()
        case .projects:  await projectsVM.fetchPendingProjects()
        case .archive:   await archiveVM.fetchItems()
        // طلبات حذف الحساب والخصوصية (سياسة الخصوصية ٢٠٢٦-١٠-٢٨)
        case .policy:    await adminRequestVM.fetchPolicyRequests()
        }
    }

    /// يفتح الطلب المطلوب مرة واحدة: يُبحث في كل المعلّق بلا فلاتر — مربّعه فوق «الوارد»، أو صفحة الخصوصية عليه.
    /// لم يوجد: «عولج من قبل» فقط حين وصلت كل القوائم، وإلا «تعذّر التحميل» (قد يكون في القائمة التي فشلت)
    private func openFocusIfNeeded() {
        guard let focusId, !focusHandled else { return }
        // طلب انضمام بمعرّف صفّه في admin_requests ← صفّه في القائمة بمعرّف العضو المعلّق
        let rowId = adminRequestVM.joinApprovalRequests.first(where: { $0.id == focusId })?.memberId ?? focusId
        let item = sortedAllItems.first(where: { selectableId($0) == rowId })
        switch AdminInboxLogic.focusOutcome(inPending: item != nil, inPolicy: policyRequestIds.contains(focusId),
                                            health: storeHealth, relevant: relevantStores) {
        case .open:
            focusHandled = true
            focusMissing = nil
            if let item { selectedDetail = requestDetail(for: item) }
        case .policy:
            focusHandled = true
            focusMissing = nil
            open(.policy(focusId))
        case .wait:
            break
        case .handledBefore:
            focusHandled = true
            focusMissing = .handled
        case .failed:
            focusMissing = .failed
        }
    }

    /// معرّفات طلبات الخصوصية والقرابة (صفحتها مستقلة)
    private var policyRequestIds: Set<UUID> {
        Set((adminRequestVM.accountDeleteRequests + adminRequestVM.privacyRequests + adminRequestVM.relativeAddRequests
             + adminRequestVM.relativeRemoveRequests + adminRequestVM.lineageRequests).map(\.id))
    }

    /// «الرسائل» (رسائل الأعضاء الخاصة) لمن يراها في جدول «مين يشوف وش» — السيرفر يحرسها أيضاً
    /// (`20261107210000_contact_messages_owner_admin`)
    private var canSeeMessages: Bool { authVM.adminSees(.inboxMessages) }

    /// بصمة القوائم — تتغيّر مع أي إضافة/حذف في أي نوع
    private var requestsSignature: [Int] {
        [memberVM.allMembers.count, newsVM.pendingNewsRequests.count, adminRequestVM.newsReportRequests.count,
         adminRequestVM.phoneChangeRequests.count, adminRequestVM.nameChangeRequests.count,
         diwaniyaVM.pendingDiwaniyas.count, adminRequestVM.deceasedRequests.count,
         adminRequestVM.childAddRequests.count, adminRequestVM.photoSuggestionRequests.count,
         projectsVM.pendingProjects.count, pendingArchiveItems.count, adminRequestVM.treeEditRequests.count,
         adminRequestVM.policyRequestsCount]
    }

    private func requestDetail(for item: AllItem) -> RequestDetail {
        switch item {
        case .join(let m): return .join(m)
        case .news(let p): return .news(p)
        case .report(let r): return .report(r)
        case .phone(let r): return .phone(r)
        case .nameChange(let r): return .nameChange(r)
        case .diwaniya(let d): return .diwaniya(d)
        case .deceased(let r): return .deceased(r)
        case .child(let r): return .child(r)
        case .photo(let r): return .photo(r)
        case .project(let p): return .project(p)
        case .archive(let a): return .archive(a)
        case .treeEdit(let r, let action): return .treeEdit(r, action)
        }
    }

    @State private var cachedTotalCount: Int = 0
    @State private var cachedAvailableTabs: [RequestTab] = RequestTab.allCases

    private var totalCount: Int { cachedTotalCount }
    private var availableTabs: [RequestTab] { cachedAvailableTabs }

    // MARK: - صلاحية الإجراء حسب مجال الدور (تحديث الأدوار 2026-09-21) × «يعدّل» في جدول السيرفر (Autoplan note 13)

    /// تابات المحتوى — الاعتماد فيها للإدارة، والمراجعة والبلاغات للمشرف
    private static let contentTabs: Set<RequestTab> = [.news, .projects, .archive, .diwaniya, .photos, .reports]

    /// هل يقدر المستخدم الحالي يعتمد عناصر هذا التاب؟ — والقسم «يعدّل» له في الجدول (القسم «للاطلاع» بلا أزرار)
    private func canApprove(_ tab: RequestTab) -> Bool {
        guard authVM.adminCanEdit(.inbox) else { return false }
        if tab == .reports { return authVM.canModerateContent }
        if tab == .photos { return canHandlePhotos }
        return Self.contentTabs.contains(tab) ? authVM.canApproveContent : authVM.canApproveTreeRequests
    }

    /// هل يقدر يرفضها؟ (المشرف يتعامل مع البلاغات فقط)
    /// رفض طلب الانضمام = حذف ملف المتقدّم (`rejectOrDeleteMember`) — للمالك والمدير (`canDeleteMembers`) وحدهما،
    /// كان يظهر للمراقب فيفشل دائماً
    private func canReject(_ tab: RequestTab) -> Bool {
        guard authVM.adminCanEdit(.inbox) else { return false }
        if tab == .reports { return authVM.canModerateContent }
        if tab == .photos { return canHandlePhotos }
        if tab == .joinRequests { return authVM.canDeleteMembers }
        return Self.contentTabs.contains(tab) ? authVM.canApproveContent : authVM.canRejectRequests
    }

    /// حذف الطلب نهائياً (السحب) — المالك والمدير، والقسم «يعدّل»
    private var canHardDelete: Bool {
        authVM.canDeleteMembers && authVM.adminCanEdit(.inbox)
    }
    /// «صور مقترحة» (بيانات عضو — مجال الشجرة، مقترح «أدوار الإدارة» البند ٥): يعالجها من يعدّلها في جدول السيرفر
    /// (`inbox.photos`) ويملك طلبات الشجرة — المالك والمدير والمراقب دائماً (لا حسب مفتاح المسار)، والمشرف لا
    /// (السيرفر يرفضها له أصلاً: `can_handle_admin_request`)
    private var canHandlePhotos: Bool {
        authVM.adminAccess(.inboxPhotos).canEdit && authVM.canModerateTree
    }

    /// التابات التي يراها هذا الدور — كل دور يشوف مجاله فقط، و«صور مقترحة» من جدول السيرفر (`inbox.photos`)
    private func tabsForRole(_ tabs: [RequestTab]) -> [RequestTab] {
        let photos = Self.reviewIncludesPhotos(for: authVM)
        if authVM.isAdmin { return tabs.filter { $0 != .photos || photos } }
        if authVM.currentUser?.role == .supervisor {
            return tabs.filter { $0 == .all || (Self.contentTabs.contains($0) && ($0 != .photos || photos)) }
        }
        // المراقب: الشجرة والأعضاء + «صور مقترحة» دائماً (افتراض الجدول)
        return tabs.filter {
            $0 == .all || !Self.contentTabs.contains($0) || ($0 == .photos && photos)
        }
    }

    private func recalculateCounts() {
        cachedPendingMembers = memberVM.allMembers.filter { $0.role == .pending }
        // المجموع الكلّي عبر مصدر واحد للحقيقة — يطابق بادج «طلبات المراجعة» في لوحة الإدارة
        cachedTotalCount = Self.reviewRequestsTotal(
            memberVM: memberVM, newsVM: newsVM, adminRequestVM: adminRequestVM,
            diwaniyaVM: diwaniyaVM, projectsVM: projectsVM,
            pendingArchiveCount: pendingArchiveItems.count,
            scope: Self.reviewScope(for: authVM),
            includePhotos: Self.reviewIncludesPhotos(for: authVM)
        )
        // عرض كل التابات دائماً — حتى الفارغة (المستخدم يبيها كلها مرئية).
        // «مشكلات الشجرة» خرجت من «الوارد» (الدفعة ب ٢٠٢٦-١٠-٢٠): بيتها «العائلة» ← شريحة «مشكلات الشجرة» —
        // الوارد = ما طلبه أحد فقط
        cachedAvailableTabs = tabsForRole(RequestTab.allCases)
    }

    /// مصدر واحد للحقيقة لعدد «طلبات المراجعة» — يستخدمه «الكل» داخل الطلبات وبادج لوحة الإدارة
    /// حتى يتطابق الرقمان دائماً. يطابق مجموع عدّادات كل التابات (joinRequests…صحة الشجرة).
    /// مجال العدّاد حسب الدور — نفس `tabsForRole`: الإدارة كل شيء، المشرف المحتوى والبلاغات،
    /// والمراقب الشجرة والأعضاء (مع صحة الشجرة) — حتى يطابق الرقم ما يراه في القائمة.
    enum ReviewScope { case all, content, tree }

    @MainActor
    static func reviewScope(for authVM: AuthViewModel) -> ReviewScope {
        if authVM.isAdmin { return .all }
        if authVM.currentUser?.role == .supervisor { return .content }
        return .tree
    }

    /// «صور مقترحة» ضمن «الوارد» لهذا الدور — خانة `inbox.photos` في جدول السيرفر (المالك والمدير والمراقب افتراضاً)
    @MainActor
    static func reviewIncludesPhotos(for authVM: AuthViewModel) -> Bool {
        authVM.adminSees(.inboxPhotos)
    }

    @MainActor
    static func reviewRequestsTotal(
        memberVM: MemberViewModel,
        newsVM: NewsViewModel,
        adminRequestVM: AdminRequestViewModel,
        diwaniyaVM: DiwaniyasViewModel,
        projectsVM: ProjectsViewModel,
        pendingArchiveCount: Int = 0,
        scope: ReviewScope = .all,
        includePhotos: Bool = true
    ) -> Int {
        let members = memberVM.allMembers
        let pending = members.filter { $0.role == .pending }.count

        // المحتوى والبلاغات = تبويبات `contentTabs` بلا «صور مقترحة»، والباقي الشجرة والأعضاء.
        // «صور مقترحة» تُضاف لمن يراها في جدول السيرفر (`includePhotos`) أياً كان مجاله — نفس `tabsForRole`
        let content = newsVM.pendingNewsRequests.count
            + adminRequestVM.newsReportRequests.count
            + diwaniyaVM.pendingDiwaniyas.count
            + projectsVM.pendingProjects.count
            + pendingArchiveCount
        let photos = includePhotos ? adminRequestVM.photoSuggestionRequests.count : 0
        let tree = pending
            + adminRequestVM.phoneChangeRequests.count
            + adminRequestVM.nameChangeRequests.count
            + adminRequestVM.deceasedRequests.count
            + adminRequestVM.childAddRequests.count
            + adminRequestVM.treeEditRequests.count
            + adminRequestVM.policyRequestsCount
        switch scope {
        case .all:     return content + tree + photos
        case .content: return content + photos
        case .tree:    return tree + photos
        }
    }

    /// سطر المجال تحت العنوان للمراقب والمشرف (spec C.2)
    private var scopeLine: String? {
        if authVM.isAdmin { return nil }
        if authVM.currentUser?.role == .supervisor {
            return L10n.t("مجالك: المحتوى والبلاغات", "Your scope: content & reports")
        }
        return L10n.t("مجالك: طلبات الشجرة والأعضاء", "Your scope: tree & member requests")
    }

    // MARK: - الرأس والأبواب

    /// «تحديد» لمن يعدّل وحين توجد طلبات
    private func canSelect(_ m: InboxModel) -> Bool {
        authVM.adminCanEdit(.inbox) && !m.entries.isEmpty
    }

    private func band(_ m: InboxModel) -> some View {
        let dismiss = dismiss
        return AdminInboxBand(backTitle: outerBack ?? AdminArea.homeTitle, onBack: { dismiss() },
                              subtitle: scopeLine,
                              readOnly: !authVM.adminCanEdit(.inbox),
                              items: headerItems(m)) {
            // ⚙︎ بيت «إعدادات مسار الموافقات» الوحيد — ظهوره من جدول السيرفر (`inbox.approval_settings`: المالك يعدّل،
            // المدير يقرأ افتراضاً)؛ الصفحة نفسها تقفل مفاتيحها لغير المالك (`canManageSettings`)
            if authVM.adminSees(.inboxApprovalSettings) {
                AdminGlassButton(symbol: "gearshape", label: L10n.t("إعدادات مسار الموافقات", "Approval path settings")) {
                    open(.settings)
                }
            }
            if canSelect(m) || isSelectMode {
                AdminHeaderTextButton(title: isSelectMode ? L10n.t("إلغاء", "Cancel") : L10n.t("تحديد", "Select")) {
                    toggleSelectMode()
                }
            }
        }
    }

    /// «5 بانتظار قرارك ‹ · 2 عاجل ‹ · 1 متأخر ‹» — من كل طلبات المجال، وكل رقم يضبط «الحالة» وحدها (T2)
    private func headerItems(_ m: InboxModel) -> [AdminHeaderItem] {
        typealias L = AdminInboxLogic
        let health: AdminStoreHealth?
        switch m.phase {
        case .failed:               health = .failed(lastGood: nil)
        case .stale(let since, _):  health = .failed(lastGood: since)
        default:                    health = nil
        }
        let retry: () -> Void = { Task { await reload(failedStores.isEmpty ? nil : failedStores) } }
        func item(_ status: L.Status, _ n: Int, _ label: String, _ spoken: String) -> AdminHeaderItem {
            AdminHeaderItem(id: status.rawValue, value: m.ready ? n : nil, label: label, health: health,
                            tap: .action { land(status) }, retry: retry, spoken: spoken)
        }
        return [
            item(.waiting, m.header.waiting, L10n.t("بانتظار قرارك", "awaiting you"),
                 L10n.t("\(m.header.waiting) بانتظار قرارك، يعرضها", "\(m.header.waiting) awaiting you, shows them")),
            item(.urgent, m.header.urgent, L10n.t("عاجل", "urgent"),
                 L10n.t("\(m.header.urgent) عاجل، يعرضها", "\(m.header.urgent) urgent, shows them")),
            item(.late, m.header.late, L10n.t("متأخر", "late"),
                 L10n.t("\(m.header.late) متأخر، يعرضها", "\(m.header.late) late, shows them")),
        ]
    }

    /// رقم الرأس يفتح قائمته: «الحالة» وحدها وبلا بحث — فأول رقم تحت الشريط = الرقم المضغوط
    private func land(_ status: AdminInboxLogic.Status) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? nil : DS.Anim.snappy) {
            filters = AdminInboxLogic.Filters(status: status)
            searchText = ""
        }
    }

    private func open(_ d: Door) {
        door = d
        doorOpen = true
    }

    /// الصفحة المدفوعة — خلف `AdminLazyPage { AnyView(...) }` (حارس المكدس)، بقسمها واسم ما فُتحت منه
    private var doorPage: AnyView {
        let back = AdminArea.inbox.title
        switch door {
        case .messages?:
            return AnyView(AdminLazyPage { AnyView(AdminInboxView().adminBackTitle(back).adminArea(.inbox)) })
        case .handled?:
            let store = handledStore
            let box: (AdminRequest, @escaping () -> Void) -> AnyView = { request, close in
                AnyView(handledBox(request, onClose: close))
            }
            return AnyView(AdminLazyPage {
                AnyView(AdminInboxHandledPage(store: store, box: box).adminBackTitle(back).adminArea(.inbox))
            })
        case .policy(let id)?:
            return AnyView(AdminLazyPage {
                AnyView(AdminPolicyRequestsPage(focusId: id).adminBackTitle(back).adminArea(.inbox))
            })
        case .settings?:
            return AnyView(AdminLazyPage {
                AnyView(AdminAppSettingsView(scope: .approvals).adminBackTitle(back).adminArea(.inbox))
            })
        case nil:
            return AnyView(EmptyView())
        }
    }

    /// «رسائل الأعضاء» و«بانتظار المراجعة» — بطاقة صفوف بلا عنوان أعلى القائمة
    @ViewBuilder
    private var doorCard: some View {
        let mine = postReviewCount
        if canSeeMessages || mine > 0 {
            AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                if canSeeMessages {
                    AdminInboxDoorRow(icon: "bubble.left.and.bubble.right.fill", tint: DS.Color.sea,
                                      title: AdminInboxView.title,
                                      subtitle: AdminInboxText.messagesLine(unread: adminRequestVM.unreadContactMessagesCount,
                                                                            awaiting: adminRequestVM.pendingContactMessagesCount)) {
                        open(.messages)
                    }
                }
                if mine > 0 {
                    AdminInboxDoorRow(icon: "checkmark.shield.fill", tint: DS.Color.accent,
                                      title: L10n.t("بانتظار المراجعة", "Awaiting review"),
                                      subtitle: AdminInboxText.postReviewLine(mine)) {
                        showsPostReview = true
                    }
                }
            }
        }
    }

    /// ما ينتظر مراجعتك بعد الموافقة (مراجعة بعد الموافقة، ٢٠٢٦-١١-٢٥) — من يراجع ماذا: `PostReviewStore.canReview`
    private var postReviewCount: Int {
        postReview.pending.filter { PostReviewStore.canReview($0, me: authVM.currentUser, members: memberVM.allMembers) }.count
    }

    // MARK: - القائمة

    /// صفوف `List` واحدة تتمرّر: الرأس ← الأبواب ← الفلاتر ← الأسطر ← الطلبات بالأيام ← «المنجز»
    private func list(_ m: InboxModel) -> some View {
        List {
            AnyView(band(m))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if !isSelectMode && (canSeeMessages || postReviewCount > 0) {
                AnyView(doorCard)
                    .adminPageRow(top: DS.Spacing.lg, bottom: 0)
            }
            if showsFilterBar(m) {
                AnyView(AdminFilterPanel(set: m.filterSet, selection: $filters, search: $searchText,
                                         note: L10n.t("الأحدث أولاً", "Newest first"),
                                         openFilters: { showsFilters = true }))
                    .adminPageRow(top: DS.Hub.stackSpacing, bottom: 0)
            }
            AnyView(notices(m))
            if let n = approveAllChildrenCount {
                AnyView(DSButton(AdminInboxText.approveAllChildren(n), icon: "checkmark.circle", role: .cancel) {
                    showBulkApproveChildrenConfirm = true
                }
                .disabled(adminRequestVM.isLoading))
                .adminPageRow(top: DS.Spacing.sm, bottom: 0)
            }
            if adminRequestVM.policyRequestsCount > 0 && !isSelectMode && !isSearching {
                AnyView(AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                    AdminInboxDoorRow(icon: "lock.shield.fill", tint: DS.Color.primary,
                                      title: AdminPolicyRequestsPage.title,
                                      subtitle: AdminInboxText.policyLine(adminRequestVM.policyRequestsCount)) {
                        open(.policy(nil))
                    }
                })
                .adminPageRow(top: DS.Spacing.sm, bottom: 0)
            }
            AnyView(requestRows(m))
            if !isSelectMode {
                AnyView(AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                    AdminInboxDoorRow(icon: "checkmark.circle.fill", tint: DS.Color.palm,
                                      title: AdminInboxHandledPage.title,
                                      subtitle: L10n.t("آخر 30 يوماً، للاطلاع", "Last 30 days, view only"),
                                      value: AdminInboxHandledPage.doorValue(store: handledStore, authVM: authVM,
                                                                             memberVM: memberVM),
                                      hint: L10n.t("يفتح الطلبات المعالجة", "Opens the handled requests")) {
                        open(.handled)
                    }
                })
                .adminPageRow(top: DS.Hub.sectionGap, bottom: 0)
            }
            // آخر صفّ لا يختفي تحت شريط التبويبات
            DS.Hub.background
                .frame(height: landscape ? DS.Landscape.tabBarClearance + DS.Spacing.lg : DS.Spacing.xxxl)
                .listRowInsets(EdgeInsets())
                .listRowBackground(DS.Hub.background)
                .listRowSeparator(.hidden)
                .accessibilityHidden(true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .environment(\.defaultMinListRowHeight, 0)
        .refreshable { await reload() }
        // أفقياً: الصفوف بعرض الشاشة كي يصل الكحلي للحافتين (المحتوى نفسه في عمود القراءة)
        .ignoresSafeArea(.container, edges: landscape ? .horizontal : [])
        // مربّع التفاصيل يكبر من مكان الضغط
        .dsRecordsTapOrigin()
    }

    /// الشريط مع التحميل (يمسك المكان) ومع وجود طلبات أو فلتر/بحث مفعّل — لا شريط فوق خطأ ولا فوق «لا طلبات»
    private func showsFilterBar(_ m: InboxModel) -> Bool {
        guard !isSelectMode else { return false }
        switch m.phase {
        case .failed:  return false
        case .loading: return true
        default:       return !m.entries.isEmpty || !filters.isEmpty || isSearching
        }
    }

    /// «الموافقة على كل طلبات إضافة ابن (N)» — المسار مطفأ، ولمن يوافق، وحين تُعرض طلبات الإضافة
    private var approveAllChildrenCount: Int? {
        let n = adminRequestVM.childAddRequests.count
        guard n > 1, !adminRequestVM.approvalsWorkflowOn, !isSelectMode, !isSearching, canApprove(.children),
              filters.status == .all || filters.status == .waiting,
              filters.group == nil || filters.group == .tree,
              filters.kind == nil || filters.kind == .children,
              filters.source == nil else { return nil }
        return n
    }

    /// فوق الطلبات: فشل قائمة (جزئي/قديم) ثم الطلب المطلوب. «تعذّر التحميل» للطلب المطلوب لا يأتي إلا مع قائمة فشلت، فيُقال
    /// في بطاقتها نفسها (لا بطاقتان)؛ «عولج من قبل» هادئة وحدها حين وصلت كل القوائم
    @ViewBuilder
    private func notices(_ m: InboxModel) -> some View {
        let retry = { Task { await reload(failedStores.isEmpty ? nil : failedStores) } }
        switch m.phase {
        case .partial(let stores):
            AnyView(AdminPageStateCard(.error(AdminInboxText.failedLine(stores),
                                              message: L10n.t("ما وصل ظاهر تحته.", "What arrived is shown below.") + focusFailedNote,
                                              retry: { _ = retry() })))
                .adminPageRow(top: DS.Spacing.sm, bottom: 0)
        case .stale(let since, _):
            AnyView(AdminPageStateCard(.error(L10n.t("تعذّر تحديث الطلبات", "Couldn't refresh the requests"),
                                              message: L10n.t("تعرض آخر طلبات وصلت.", "Showing the last requests received.")
                                                + focusFailedNote,
                                              retry: { _ = retry() }, lastGood: since)))
                .adminPageRow(top: DS.Spacing.sm, bottom: 0)
        default:
            EmptyView()
        }
        if focusMissing == .handled {
            // هادئة — فقط وكل القوائم وصلت: الطلب فعلاً ليس معلّقاً
            AnyView(AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                AdminInboxDoorRow(icon: "checkmark.circle", tint: DS.Color.palm,
                                  title: L10n.t("هذا الطلب عولج من قبل", "This request was already handled"),
                                  subtitle: L10n.t("افتح المنجز لترى ما تم فيه", "Open what's done to see what happened"),
                                  hint: L10n.t("يفتح المنجز", "Opens what's done")) {
                    open(.handled)
                }
            })
            .adminPageRow(top: DS.Spacing.sm, bottom: 0)
        }
    }

    /// الطلب المطلوب لم يوجد وقائمة فشلت: قد يكون فيها — سطر في بطاقة الفشل نفسها (لا «عولج من قبل» أبداً)
    private var focusFailedNote: String {
        focusMissing == .failed
            ? L10n.t(" والطلب الذي فتحته قد يكون فيها.", " The request you opened may be in it.") : ""
    }

    /// الطلبات: هيكل · خطأ · «لا طلبات الآن» · «لا طلبات بهذه الفلاتر» · الأيام
    @ViewBuilder
    private func requestRows(_ m: InboxModel) -> some View {
        switch m.phase {
        case .loading:
            AnyView(DSCardSkeleton(style: .notice, count: 4, label: L10n.t("جارٍ تحميل الطلبات…", "Loading requests…")))
                .adminPageRow(top: DS.Hub.stackSpacing, bottom: 0)
        case .failed:
            AnyView(AdminPageStateCard(.error(L10n.t("تعذّر تحميل الطلبات", "Couldn't load the requests"),
                                              message: L10n.t("تحقّق من اتصالك ثم أعد المحاولة.",
                                                              "Check your connection, then try again.") + focusFailedNote,
                                              retry: { Task { await reload(failedStores.isEmpty ? nil : failedStores) } })))
                .adminPageRow(top: DS.Hub.stackSpacing, bottom: 0)
        default:
            if m.entries.isEmpty {
                // «كل الطلبات عولجت» فقط حين وصلت كل القوائم (الجزئي يقول «فيما وصل»)
                let complete = m.phase == .loaded
                AnyView(AdminPageStateCard(.empty(L10n.t("لا طلبات الآن", "No requests now"),
                                                  message: complete ? L10n.t("كل الطلبات عولجت.", "Every request was handled.")
                                                                    : L10n.t("لا طلبات فيما وصل.", "None in what arrived."),
                                                  tint: DS.Color.success)))
                    .adminPageRow(top: DS.Hub.stackSpacing, bottom: 0)
            } else if m.visible.isEmpty {
                AnyView(filteredEmpty)
                    .adminPageRow(top: DS.Hub.stackSpacing, bottom: 0)
            } else {
                ForEach(m.days) { day in
                    DSDayHeader(title: day.title, count: day.items.count)
                        .dsCardCascade(1, appeared: rowsAppeared)
                        .adminPageRow(top: DS.Hub.stackSpacing, bottom: DSNoticeMetrics.headerGap)
                    ForEach(Array(day.items.enumerated()), id: \.element.id) { index, e in
                        cell(e, position: DSGroupPosition(index: index, count: day.items.count))
                    }
                }
            }
        }
    }

    /// فلاتر بلا نتيجة: «لا طلبات بهذه الفلاتر» + «مسح الفلاتر»؛ بحث بلا نتيجة: «لا نتائج» + «مسح البحث»
    private var filteredEmpty: some View {
        Group {
            if !filters.isEmpty {
                AdminFilterEmptyCard(title: L10n.t("لا طلبات بهذه الفلاتر", "No requests with these filters")) {
                    withAnimation(reduceMotion ? nil : DS.Anim.snappy) { filters = AdminInboxLogic.Filters() }
                }
            } else {
                AdminPageStateCard(.empty(L10n.t("لا نتائج", "No results"),
                                          message: L10n.t("لا طلب يطابق «\(searchText)»", "No request matches “\(searchText)”"),
                                          actionTitle: L10n.t("مسح البحث", "Clear search"),
                                          action: { searchText = "" }))
            }
        }
    }

    // MARK: - الصفّ وإجراءاته

    /// إجراءات الصفّ — السحب والضغط المطوّل والقارئ الصوتي نفسها (spec A.15)
    private struct RowAction: Identifiable {
        enum Kind { case approve, details, reject, delete }
        let kind: Kind
        let title: String
        let icon: String
        let run: () -> Void
        var id: Kind { kind }
    }

    private func actions(for e: Entry) -> [RowAction] {
        let tab = allItemTab(e.item)
        // بالمسار: الموافقة بالسحب = «تنفيذ» للمختص والطلب معتمد، والرفض من مربّع التفاصيل (بسبب يصل للعضو)
        let allowsApprove = e.flow.map { adminRequestVM.canExecuteApproval($0) && authVM.adminCanEdit(.inbox) }
            ?? canApprove(tab)
        let allowsReject = e.flow == nil && canReject(tab)
        var list: [RowAction] = []
        if allowsApprove {
            let label: String
            let icon: String
            switch e.item {
            case .join(let m): label = joinApproveLabel(m); icon = "link.badge.plus"
            case .child:       label = L10n.t("تأكيد", "Confirm"); icon = "checkmark"
            default:           label = L10n.t("موافقة", "Approve"); icon = "checkmark"
            }
            list.append(RowAction(kind: .approve, title: label, icon: icon) { approve(e) })
        }
        list.append(RowAction(kind: .details, title: L10n.t("التفاصيل", "Details"), icon: "ellipsis") { openDetail(e) })
        if allowsReject {
            list.append(RowAction(kind: .reject, title: L10n.t("رفض", "Reject"), icon: "xmark") {
                swipeRejectReason = ""
                swipeRejectDetail = requestDetail(for: e.item)
            })
        }
        // حذف الطلب نهائياً — لا لطلب الانضمام (رفضه هو حذف الملف)
        if canHardDelete, !isJoin(e.item) {
            list.append(RowAction(kind: .delete, title: L10n.t("حذف", "Delete"), icon: "trash.fill") {
                swipeDeleteDetail = requestDetail(for: e.item)
            })
        }
        return list
    }

    private func isJoin(_ item: AllItem) -> Bool {
        if case .join = item { return true }
        return false
    }

    /// الخلية: الضغط يفتح المربّع (أو يحدّد في وضع التحديد)، السحب الموافقة/الحذف من البداية و«رفض»/«المزيد» من الطرف،
    /// والضغط المطوّل القائمة نفسها
    private func cell(_ e: Entry, position: DSGroupPosition) -> some View {
        let list = isSelectMode ? [] : actions(for: e)
        let picked = selectableId(e.item).map(selectedIds.contains) ?? false
        let model = rowModel(e)
        func action(_ kind: RowAction.Kind) -> (() -> Void)? { list.first { $0.kind == kind }?.run }
        return Button {
            tap(e)
        } label: {
            AnyView(AdminInboxRow(model: model, position: position, selecting: isSelectMode, picked: picked))
        }
        .buttonStyle(DSNoticePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelectMode && picked ? .isSelected : [])
        .accessibilityHint(isSelectMode ? L10n.t("يحدّده", "Selects it") : L10n.t("يفتح الطلب", "Opens the request"))
        .accessibilityActions {
            ForEach(list.filter { $0.kind != .details }) { a in
                Button(a.title) { a.run() }
            }
        }
        .modifier(RequestSwipeActions(
            enabled: !isSelectMode && !list.isEmpty,
            approve: action(.approve),
            approveLabel: list.first { $0.kind == .approve }?.title ?? L10n.t("موافقة", "Approve"),
            approveIcon: list.first { $0.kind == .approve }?.icon ?? "checkmark",
            approveColor: DS.Color.successFill,
            reject: action(.reject),
            delete: action(.delete),
            more: { openDetail(e) }))
        .modifier(RequestRowMenu(actions: list.map { a in
            RequestRowMenu.Item(id: "\(a.kind)", title: a.title, icon: a.icon, destructive: a.kind == .delete || a.kind == .reject,
                                run: a.run)
        }))
        .dsCardCascade(2, appeared: rowsAppeared)
        .onAppear {
            guard !rowsAppeared else { return }
            DispatchQueue.main.async { rowsAppeared = true }
        }
        .adminPageRow(top: 0, bottom: 0)
    }

    private func tap(_ e: Entry) {
        if isSelectMode {
            guard let id = selectableId(e.item) else { return }
            withAnimation(DS.Anim.quick) {
                if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
            }
            return
        }
        openDetail(e)
    }

    private func openDetail(_ e: Entry) {
        selectedDetail = requestDetail(for: e.item)
    }

    /// الموافقة من الصفّ — نفس نداءات نماذج العرض، و«لحظة النجاح» (إلا «ربط» الانضمام: يفتح تأكيد الدمج أو المنتقي)
    private func approve(_ e: Entry) {
        if case .join(let member) = e.item {
            joinApprove(member)
            return
        }
        let tab = allItemTab(e.item)
        let title = e.flow != nil ? L10n.t("تم التنفيذ", "Carried out")
            : tab == .children ? L10n.t("تم التأكيد", "Confirmed") : L10n.t("تمت الموافقة", "Approved")
        if DebugAdminProbe.dryRun("inbox approve \(tab.rawValue) \(e.id)") {
            AdminApprovalMoment.after(adminRequestVM, title: title)
            return
        }
        guard let work = approveWork(e.item) else { return }
        Task { await work() }
        AdminApprovalMoment.after(adminRequestVM, title: title)
    }

    private func approveWork(_ item: AllItem) -> (() async -> Void)? {
        switch item {
        case .join:
            return nil
        case .news(let post):
            return { await newsVM.approveNewsPost(postId: post.id) }
        case .report(let request):
            return { await adminRequestVM.approveNewsReport(request: request) }
        case .phone(let request):
            return { await adminRequestVM.approvePhoneChangeRequest(request: request) }
        case .nameChange(let request):
            return { await adminRequestVM.approveNameChangeRequest(request: request) }
        case .diwaniya(let diwaniya):
            guard let adminId = authVM.currentUser?.id else { return nil }
            return { await diwaniyaVM.approveDiwaniya(id: diwaniya.id, adminId: adminId) }
        case .deceased(let request):
            return { await adminRequestVM.approveDeceasedRequest(request: request) }
        case .child(let request):
            return { await adminRequestVM.acknowledgeChildAddRequest(request: request) }
        case .photo(let request):
            return { await adminRequestVM.approvePhotoSuggestion(request: request) }
        case .project(let project):
            guard let adminId = authVM.currentUser?.id else { return nil }
            return { await projectsVM.approveProject(id: project.id, approvedBy: adminId) }
        case .archive(let item):
            return { await archiveVM.approveItem(item) }
        case .treeEdit(let request, _):
            return { await adminRequestVM.approveTreeEditRequest(request: request) }
        }
    }

    // MARK: - ما يرسمه الصفّ (spec C.2 البند ٦)

    private func rowModel(_ e: Entry) -> AdminInboxRowModel {
        let person = rowPerson(e.item)
        let look = rowLook(e.item)
        let (pills, word, tone) = rowState(e)
        return AdminInboxRowModel(
            name: person.member?.fourPartName ?? person.fallback,
            avatarName: person.member?.firstName ?? person.fallback,
            avatarURL: person.member?.avatarUrl,
            avatarTint: person.member?.roleColor ?? DS.Color.brand,
            typeIcon: look.icon,
            typeFill: look.fill,
            time: AdminInboxClock.text(e.date),
            ask: rowAsk(e.item),
            pills: pills,
            stateWord: word,
            stateTone: tone,
            isNew: InboxSeenStore.shared.isNew(requestDetail(for: e.item).id, created: e.date))
    }

    /// من أرسل: المتقدّم نفسه في الانضمام، وإلا مقدّم الطلب (أو صاحب المحتوى)
    private func rowPerson(_ item: AllItem) -> (member: FamilyMember?, fallback: String) {
        let unknown = L10n.t("عضو", "Member")
        func requester(_ r: AdminRequest) -> FamilyMember? {
            memberVM.member(byId: r.requesterId) ?? (r.requesterId == r.memberId ? r.member : nil)
        }
        switch item {
        case .join(let m): return (m, unknown)
        case .news(let p):
            return (p.author_id.flatMap { memberVM.member(byId: $0) }, p.author_name.isEmpty ? unknown : p.author_name)
        case .report(let r), .nameChange(let r), .deceased(let r), .child(let r), .photo(let r), .treeEdit(let r, _):
            return (requester(r), r.member?.fourPartName ?? unknown)
        case .phone(let r):
            return (r.requesterId.flatMap(memberVM.member(byId:)) ?? r.member, r.member?.fourPartName ?? unknown)
        case .diwaniya(let d): return (memberVM.member(byId: d.ownerId), d.ownerName.isEmpty ? unknown : d.ownerName)
        case .project(let p): return (memberVM.member(byId: p.ownerId), p.ownerName.isEmpty ? unknown : p.ownerName)
        case .archive(let a): return (memberVM.member(byId: a.uploadedBy), unknown)
        }
    }

    /// رمز النوع على ركن الصورة وتعبئته (عائلة الكحلي والذهبي بمعنى النوع)
    private func rowLook(_ item: AllItem) -> (icon: String, fill: Color) {
        switch item {
        case .join(let m):   return ("person.fill", m.isFemale ? DS.Color.femaleFill : DS.Color.primaryFill)
        case .news:          return ("newspaper.fill", DS.Color.goldFill)
        case .report:        return ("flag.fill", DS.Color.errorFill)
        case .phone:         return ("phone.fill", DS.Color.seaFill)
        case .nameChange:    return ("character.cursor.ibeam", DS.Color.palmFill)
        case .diwaniya:      return ("tent.fill", DS.Color.palmFill)
        case .deceased:      return ("leaf.fill", DS.Color.deceasedFill)
        case .child:         return ("person.badge.plus", DS.Color.palmFill)
        case .photo:         return ("photo.fill", DS.Color.saduFill)
        case .project:       return ("briefcase.fill", DS.Color.goldFill)
        case .archive:       return ("archivebox.fill", DS.Color.saduFill)
        case .treeEdit(let r, let action):
            let shown = r.treeEditPayload?.displayAction ?? action
            switch shown {
            case .editPhone:              return (shown.iconName, DS.Color.seaFill)
            case .deceased, .addDeathDate: return (shown.iconName, DS.Color.deceasedFill)
            case .addPhoto:               return (shown.iconName, DS.Color.saduFill)
            case .delete:                 return (shown.iconName, DS.Color.errorFill)
            case .other:                  return (shown.iconName, DS.Color.goldFill)
            default:                      return (shown.iconName, DS.Color.palmFill)
            }
        }
    }

    /// ما يطلبه بجملة قصيرة: «يطلب إضافة ابن: محمد» · «يبلّغ عن وفاة: جاسم محمد عبدالله»
    private func rowAsk(_ item: AllItem) -> String {
        func short(_ m: FamilyMember?) -> String { m?.chainThreeName ?? L10n.t("عضو", "a member") }
        func snippet(_ text: String?) -> String? {
            let line = (text ?? "").split(whereSeparator: \.isNewline).first.map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !line.isEmpty else { return nil }
            return line.count > 60 ? String(line.prefix(60)) + "…" : line
        }
        switch item {
        case .join(let m):
            let base = L10n.t("طلب انضمام", "Join request")
            if m.isFemale { return base + L10n.t(" · أنثى · تُربط بشجرة النساء", " · Female · goes in the women's tree") }
            return base + (joinTiers(for: m).suggested != nil
                           ? L10n.t(" · له تطابق في الشجرة", " · matches the tree")
                           : L10n.t(" · اسم جديد", " · new name"))
        case .news(let p):
            return snippet(p.content).map { L10n.t("خبر للنشر: \($0)", "Post to publish: \($0)") }
                ?? L10n.t("خبر للنشر", "Post to publish")
        case .report(let r):
            return snippet(r.details).map { L10n.t("بلاغ عن منشور: \($0)", "Post report: \($0)") }
                ?? L10n.t("بلاغ عن منشور لـ \(short(r.member))", "Report on \(short(r.member))'s post")
        case .phone(let r):
            let selfRequest = r.requesterId == nil || r.requesterId == r.memberId
            if selfRequest {
                return r.member?.isFemale == true ? L10n.t("تطلب تغيير رقمها", "Asks to change her number")
                                                  : L10n.t("يطلب تغيير رقمه", "Asks to change his number")
            }
            return L10n.t("يطلب تغيير رقم \(short(r.member))", "Asks to change \(short(r.member))'s number")
        case .nameChange(let r):
            let isFamily = r.requestType == RequestType.familyChange.rawValue
            let value = (r.newValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let what = isFamily ? L10n.t("تغيير العائلة", "Family change") : L10n.t("تغيير الاسم", "Name change")
            let whom = r.requesterId == r.memberId ? "" : L10n.t(" لـ \(short(r.member))", " for \(short(r.member))")
            return value.isEmpty ? what + whom : what + whom + L10n.t(" إلى: \(value)", " to: \(value)")
        case .diwaniya(let d):
            return L10n.t("ديوانية جديدة: \(d.title)", "New diwaniya: \(d.title)")
        case .deceased(let r):
            return L10n.t("يبلّغ عن وفاة: \(short(r.member))", "Reports a death: \(short(r.member))")
        case .child(let r):
            let child = r.newValue.flatMap(UUID.init(uuidString:)).flatMap { memberVM.member(byId: $0)?.firstName }
            let forOther = r.requesterId != r.memberId
            let head = forOther ? L10n.t("يطلب إضافة ابن لـ \(short(r.member))", "Adds a son to \(short(r.member))")
                                : L10n.t("يطلب إضافة ابن", "Adds a son")
            return child.map { "\(head): \($0)" } ?? head
        case .photo(let r):
            return L10n.t("يقترح صورة لـ \(short(r.member))", "Suggests a photo for \(short(r.member))")
        case .project(let p):
            return L10n.t("مشروع جديد: \(p.title)", "New project: \(p.title)")
        case .archive(let a):
            return L10n.t("\(a.fileKindName) للمكتبة: \(a.title)", "\(a.fileKindName) for the library: \(a.title)")
        case .treeEdit(let r, let action):
            let payload = r.treeEditPayload
            let shown = payload?.displayAction ?? action
            let label = Self.profileReasonTitle(payload?.reason) ?? L10n.t(shown.arabicLabel, shown.englishLabel)
            let subject = Self.womenSubjectName(payload) ?? r.member?.chainThreeName ?? payload?.targetMemberName
            let diff = action == .editName
                ? Self.nameDiff(old: r.member?.displayFullName ?? payload?.targetMemberName, new: payload?.newName) : nil
            let change = diff.map { "\($0.old) ← \($0.new)" } ?? treeEditNewValue(payload: payload, action: action)
            var text = label
            if let subject, !subject.isEmpty, action != .add { text += ": \(subject)" }
            if let change, !change.isEmpty { text += action == .add ? ": \(change)" : " · \(change)" }
            return text
        }
    }

    /// سطر الحالة: «عاجل»/«متأخر» حبّتان، ثم «بانتظار قرارك» (ذهبي) أو أين الطلب في المسار (رمادي) أو «للاطلاع»
    private func rowState(_ e: Entry) -> ([AdminInboxRowModel.Pill], String?, AdminInboxRowModel.StateTone) {
        var pills: [AdminInboxRowModel.Pill] = []
        if let flow = e.flow {
            if flow.isUrgent { pills.append(.init(title: L10n.t("عاجل", "Urgent"), tone: .error)) }
            if flow.isEscalated {
                pills.append(.init(title: L10n.t("تصعّد", "Escalated"), tone: .error))
            } else if flow.isLate {
                pills.append(.init(title: L10n.t("متأخر", "Late"), tone: .warn))
            }
            if e.fact.waiting { return (pills, L10n.t("بانتظار قرارك", "Awaiting you"), .mine) }
            let word = adminRequestVM.approvalHolderLabel(flow) ?? Self.stageWord(flow.stage)
            return (pills, word, .neutral)
        }
        let tab = allItemTab(e.item)
        if canApprove(tab) || canReject(tab) { return (pills, L10n.t("بانتظار قرارك", "Awaiting you"), .mine) }
        return (pills, L10n.t("للاطلاع", "View only"), .neutral)
    }

    private static func stageWord(_ stage: ApprovalStage) -> String {
        switch stage {
        case .review:  return L10n.t("عند المختص", "With the specialist")
        case .info:    return L10n.t("بانتظار معلومات العضو", "Waiting for the member")
        case .approve: return L10n.t("عند المدير للاعتماد", "With the manager")
        case .execute: return L10n.t("معتمد · للتنفيذ", "Approved · to carry out")
        }
    }

    // MARK: - التحديد

    private func toggleSelectMode() {
        withAnimation(DS.Anim.snappy) {
            isSelectMode.toggle()
            selectedIds.removeAll()
        }
    }

    private func clearSelection() {
        guard isSelectMode || !selectedIds.isEmpty else { return }
        withAnimation(DS.Anim.snappy) {
            isSelectMode = false
            selectedIds.removeAll()
        }
    }

    /// «رفض (N)» لمن يملك الرفض على شيء من المحدّد (والقسم «يعدّل»)
    private var canBulkReject: Bool {
        guard authVM.adminCanEdit(.inbox) else { return false }
        if selectedIds.isEmpty { return authVM.canRejectRequests || authVM.canModerateContent }
        return !idsInRoleScope(approving: false).isDisjoint(with: selectedIds)
    }

    private func selectionBar(_ m: InboxModel) -> some View {
        let shown = Set(m.visible.compactMap { selectableId($0.item) })
        let allPicked = !shown.isEmpty && shown.isSubset(of: selectedIds)
        return AdminInboxSelectionBar(
            count: selectedIds.count, allPicked: allPicked, canPickAll: !shown.isEmpty,
            canReject: canBulkReject, busy: adminRequestVM.isLoading,
            onToggleAll: {
                withAnimation(DS.Anim.quick) {
                    if allPicked { selectedIds.subtract(shown) } else { selectedIds.formUnion(shown) }
                }
            },
            onApprove: { showBulkApproveConfirm = true },
            onReject: { showBulkRejectConfirm = true })
    }

    /// عدد ما ستحاوله العملية الجماعية (بعد مسار الموافقات ومجال الدور) — لعرض «تم قبول N من M»
    private func bulkAttemptCount(approving: Bool) -> Int {
        let scope = idsInRoleScope(approving: approving)
        return approvalScopedIds(Array(selectedIds), approving: approving).filter { scope.contains($0) }.count
    }

    /// نتيجة العملية الجماعية بالعدد الحقيقي — ما فشل أو رفضه حارس لا يُحسب، ويُذكر آخر سبب
    private func bulkResultText(done: Int, total: Int, approving: Bool) -> String {
        // رسائل الطلبات المفردة تُجمع هنا بدل مربّع «تنبيه» فوق مربّع النتيجة
        let reason = adminRequestVM.errorMessage
        adminRequestVM.errorMessage = nil
        if done >= total {
            return approving ? L10n.t("تم قبول \(done) طلب بنجاح", "Successfully approved \(done) requests")
                             : L10n.t("تم رفض \(done) طلب", "Rejected \(done) requests")
        }
        let summary = approving
            ? L10n.t("تم قبول \(done) من \(total) — الباقي لم يُقبل وبقي معلّقاً",
                     "Approved \(done) of \(total) — the rest weren't approved and stay pending")
            : L10n.t("تم رفض \(done) من \(total) — الباقي لم يُرفض وبقي معلّقاً",
                     "Rejected \(done) of \(total) — the rest weren't rejected and stay pending")
        guard let reason, !reason.isEmpty else { return summary }
        return summary + "\n" + reason
    }

    /// الموافقة الجماعية — تعبر كل الأنواع بمجال الدور (فحص الثغرات ب-٧)؛ تجربة الدور لا ترسل شيئاً
    private func bulkApproveSelected() async -> Int {
        let ids = approvalScopedIds(Array(selectedIds), approving: true)
        if DebugAdminProbe.dryRun("inbox bulk approve \(ids.count)") { return bulkAttemptCount(approving: true) }
        return await bulkApproveAcrossAllTypes(ids: ids)
    }

    private func bulkRejectSelected() async -> Int {
        let ids = approvalScopedIds(Array(selectedIds), approving: false)
        if DebugAdminProbe.dryRun("inbox bulk reject \(ids.count)") { return bulkAttemptCount(approving: false) }
        return await bulkRejectAcrossAllTypes(ids: ids)
    }

    /// «مسار الموافقات» في العمليات الجماعية: طلب في المسار يُقبل فقط إذا كان معتمداً وأنت مختصه (تنفيذ)،
    /// ويُرفض فقط من المدير — والباقي (المحتوى، أو المسار مطفأ) كما كان
    private func approvalScopedIds(_ ids: [UUID], approving: Bool) -> [UUID] {
        guard adminRequestVM.approvalsWorkflowOn else { return ids }
        return ids.filter { id in
            guard let flow = adminRequestVM.approvalSnapshot(forRowId: id) else { return true }
            return approving ? adminRequestVM.canExecuteApproval(flow) : adminRequestVM.canRejectApproval(flow)
        }
    }

    /// الأجزاء المختلفة بين اسمين (يُسقط المشترك من البداية والنهاية): «محمد اسامه … الصايغ» و«محمد اسامه … المحمدعلي»
    /// ← («الصايغ»، «المحمدعلي»). nil إن لم يُعرف الاسم القديم أو لم يختلف شيء.
    static func nameDiff(old: String?, new: String?) -> (old: String, new: String)? {
        let a = (old ?? "").split(separator: " ").map(String.init)
        let b = (new ?? "").split(separator: " ").map(String.init)
        guard !a.isEmpty, !b.isEmpty, a != b else { return nil }
        var head = 0
        while head < a.count, head < b.count, a[head] == b[head] { head += 1 }
        var tail = 0
        while tail < a.count - head, tail < b.count - head, a[a.count - 1 - tail] == b[b.count - 1 - tail] { tail += 1 }
        let oldPart = a[head..<(a.count - tail)].joined(separator: " ")
        let newPart = b[head..<(b.count - tail)].joined(separator: " ")
        return (oldPart.isEmpty ? "—" : oldPart, newPart.isEmpty ? "—" : newPart)
    }

    /// اسم المرأة المعنيّة في طلب شجرة النساء المنظّم (من ذاكرة شجرة النساء) — nil لغيره
    static func womenSubjectName(_ payload: TreeEditPayload?) -> String? {
        guard let id = payload?.womenNodeId,
              let w = WomenStore.cache.first(where: { $0.id == id }) else { return nil }
        let n = w.displayFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? nil : n
    }

    /// القيمة الجديدة للعرض حسب نوع الإجراء.
    private func treeEditNewValue(payload: TreeEditPayload?, action: TreeEditAction) -> String? {
        guard let payload else { return nil }
        switch action {
        case .editName: return (payload.newName?.isEmpty == false) ? payload.newName : nil
        case .editPhone: return (payload.newPhone?.isEmpty == false) ? payload.newPhone : nil
        case .editBirth:
            let date = payload.newBirthDate ?? payload.newName
            return (date?.isEmpty == false) ? date : nil
        case .deceased: return (payload.deathDate?.isEmpty == false) ? payload.deathDate : nil
        case .addDeathDate: return (payload.deathDate?.isEmpty == false) ? payload.deathDate : nil
        case .addPhoto: return L10n.t("صورة مرفقة", "Attached photo")
        case .add: return (payload.newMemberName?.isEmpty == false) ? payload.newMemberName : nil
        case .delete: return nil
        case .other: return (payload.notes?.isEmpty == false) ? payload.notes : nil
        }
    }

    /// عنصر موحّد لوضع "الكل" — يجمع كل الأنواع في قائمة واحدة لترتيبها زمنياً.
    fileprivate enum AllItem: Identifiable {
        case join(FamilyMember)
        case news(NewsPost)
        case report(AdminRequest)
        case phone(PhoneChangeRequest)
        case nameChange(AdminRequest)
        case diwaniya(Diwaniya)
        case deceased(AdminRequest)
        case child(AdminRequest)
        case photo(AdminRequest)
        case project(Project)
        case archive(ArchiveItem)
        case treeEdit(AdminRequest, TreeEditAction)

        var id: String {
            switch self {
            case .join(let m): return "join-\(m.id)"
            case .news(let p): return "news-\(p.id)"
            case .report(let r): return "report-\(r.id)"
            case .phone(let r): return "phone-\(r.id)"
            case .nameChange(let r): return "name-\(r.id)"
            case .diwaniya(let d): return "diw-\(d.id)"
            case .deceased(let r): return "dec-\(r.id)"
            case .child(let r): return "child-\(r.id)"
            case .photo(let r): return "photo-\(r.id)"
            case .project(let p): return "proj-\(p.id)"
            case .archive(let a): return "arch-\(a.id)"
            case .treeEdit(let r, _): return "tree-\(r.id)"
            }
        }
    }

    private func parseISODate(_ s: String?) -> Date {
        guard let s else { return .distantPast }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        return iso.date(from: s) ?? iso2.date(from: s) ?? .distantPast
    }

    private func allItemDate(_ item: AllItem) -> Date {
        switch item {
        case .join(let m): return parseISODate(m.createdAt)
        case .news(let p): return p.timestamp
        case .report(let r), .nameChange(let r), .deceased(let r),
             .child(let r), .photo(let r): return parseISODate(r.createdAt)
        case .treeEdit(let r, _): return parseISODate(r.createdAt)
        case .phone(let r): return parseISODate(r.createdAt)
        case .diwaniya: return .distantPast
        case .project(let p): return parseISODate(p.createdAt)
        case .archive(let a): return a.createdAt
        }
    }

    /// كل عناصر وضع "الكل" مرتّبة زمنياً (الأحدث أولاً).
    private var sortedAllItems: [AllItem] {
        var items: [AllItem] = []
        items += pendingMembers.map { .join($0) }
        items += newsVM.pendingNewsRequests.map { .news($0) }
        items += adminRequestVM.newsReportRequests.map { .report($0) }
        items += adminRequestVM.phoneChangeRequests.map { .phone($0) }
        items += adminRequestVM.nameChangeRequests.map { .nameChange($0) }
        items += diwaniyaVM.pendingDiwaniyas.map { .diwaniya($0) }
        items += adminRequestVM.deceasedRequests.map { .deceased($0) }
        items += adminRequestVM.childAddRequests.map { .child($0) }
        items += adminRequestVM.photoSuggestionRequests.map { .photo($0) }
        items += projectsVM.pendingProjects.map { .project($0) }
        items += pendingArchiveItems.map { .archive($0) }
        items += adminRequestVM.treeEditRequests.map {
            AllItem.treeEdit($0, $0.treeEditPayload?.resolvedAction ?? .add)
        }
        // «الكل» يعرض لكل دور عناصر مجاله فقط — مثل التابات (فحص الثغرات)
        let visible = Set(tabsForRole(RequestTab.allCases))
        let sorted = items
            .filter { visible.contains(allItemTab($0)) }
            .sorted { allItemDate($0) > allItemDate($1) }
        // «مسار الموافقات ٢»: المستعجل أولاً ثم ما ينتظرك («بانتظارك») — الأقدم أولاً في كلٍّ منهما —
        // ثم الباقي بترتيبه. مطفأ = كما كان
        guard adminRequestVM.approvalsWorkflowOn else { return sorted }
        return adminRequestVM.approvalPrioritized(sorted) { approvalSnapshot(for: $0) }
    }

    /// لقطة المسار لعنصر في «الكل» — المحتوى بلا مسار
    private func approvalSnapshot(for item: AllItem) -> ApprovalSnapshot? {
        return selectableId(item).flatMap(adminRequestVM.approvalSnapshot(forRowId:))
    }

    /// تاب كل عنصر في «الكل» — لتحديد صلاحية الموافقة/الرفض عليه
    private func allItemTab(_ item: AllItem) -> RequestTab {
        switch item {
        case .join: return .joinRequests
        case .news: return .news
        case .report: return .reports
        case .phone: return .phone
        case .nameChange: return .nameChange
        case .diwaniya: return .diwaniya
        case .deceased: return .deceased
        case .child: return .children
        case .photo: return .photos
        case .project: return .projects
        case .archive: return .archive
        case .treeEdit: return .treeOther
        }
    }

    private func treeEditColor(_ action: TreeEditAction) -> Color {
        switch action {
        case .add: return RequestTab.treeAdd.color
        case .editName: return RequestTab.treeEditName.color
        case .editPhone: return RequestTab.treeEditPhone.color
        case .editBirth: return DS.Color.palm
        case .deceased: return RequestTab.treeDeceased.color
        case .addDeathDate: return DS.Color.textTertiary
        case .addPhoto: return AppSection.admin.ink
        case .delete: return RequestTab.treeDelete.color
        case .other: return DS.Color.accent
        }
    }

    /// معرّف العنصر للتحديد المتعدّد
    private func selectableId(_ item: AllItem) -> UUID? {
        switch item {
        case .join(let m): return m.id
        case .news(let p): return p.id
        case .report(let r), .nameChange(let r), .deceased(let r),
             .child(let r), .photo(let r): return r.id
        case .treeEdit(let r, _): return r.id
        case .phone(let r): return r.id
        case .diwaniya(let d): return d.id
        case .project(let p): return p.id
        case .archive(let a): return a.id
        }
    }

    /// المعرّفات التي يملك هذا الدور الإجراء عليها في «الكل» — نفس `canApprove`/`canReject`
    /// لكل نوع (مطابق `can_handle_admin_request` في السيرفر: المراقب الشجرة والأعضاء،
    /// المشرف البلاغات، المالك/المدير الكل)
    private func idsInRoleScope(approving: Bool) -> Set<UUID> {
        Set(sortedAllItems
            .filter { approving ? canApprove(allItemTab($0)) : canReject(allItemTab($0)) }
            .compactMap(selectableId))
    }

    /// موافقة دفعية تعبر كل الأنواع (لوضع "الكل").
    private func bulkApproveAcrossAllTypes(ids: [UUID]) async -> Int {
        var count = 0
        // ما خرج عن مجال الدور لا يُقبل ولو حُدّد (فحص الثغرات ب-٧)
        let idSet = idsInRoleScope(approving: true)
        // طلبات النساء لا تُقبل جماعياً — تُربط واحدة واحدة بشجرة النساء (تُحسب «لم تُقبل»)
        var skippedWomen = 0

        for id in ids where idSet.contains(id) {
            if let joiner = pendingMembers.first(where: { $0.id == id }) {
                if joiner.isFemale { skippedWomen += 1; continue }
                count += await adminRequestVM.bulkApproveJoinRequests(memberIds: [id])
            } else if let post = newsVM.pendingNewsRequests.first(where: { $0.id == id }) {
                await newsVM.approveNewsPost(postId: post.id); count += 1
            } else if let req = adminRequestVM.newsReportRequests.first(where: { $0.id == id }) {
                await adminRequestVM.approveNewsReport(request: req)
                if await adminRequestVM.awaitDecision(req.id) { count += 1 }
            } else if let req = adminRequestVM.phoneChangeRequests.first(where: { $0.id == id }) {
                await adminRequestVM.approvePhoneChangeRequest(request: req)
                if await adminRequestVM.awaitDecision(req.id) { count += 1 }
            } else if let req = adminRequestVM.nameChangeRequests.first(where: { $0.id == id }) {
                await adminRequestVM.approveNameChangeRequest(request: req)
                if await adminRequestVM.awaitDecision(req.id) { count += 1 }
            } else if let d = diwaniyaVM.pendingDiwaniyas.first(where: { $0.id == id }),
                      let adminId = authVM.currentUser?.id {
                await diwaniyaVM.approveDiwaniya(id: d.id, adminId: adminId); count += 1
            } else if let req = adminRequestVM.deceasedRequests.first(where: { $0.id == id }) {
                await adminRequestVM.approveDeceasedRequest(request: req)
                if await adminRequestVM.awaitDecision(req.id) { count += 1 }
            } else if let req = adminRequestVM.childAddRequests.first(where: { $0.id == id }) {
                await adminRequestVM.acknowledgeChildAddRequest(request: req)
                if await adminRequestVM.awaitDecision(req.id) { count += 1 }
            } else if let req = adminRequestVM.photoSuggestionRequests.first(where: { $0.id == id }) {
                await adminRequestVM.approvePhotoSuggestion(request: req)
                if await adminRequestVM.awaitDecision(req.id) { count += 1 }
            } else if let proj = projectsVM.pendingProjects.first(where: { $0.id == id }),
                      let adminId = authVM.currentUser?.id {
                await projectsVM.approveProject(id: proj.id, approvedBy: adminId); count += 1
            } else if let item = pendingArchiveItems.first(where: { $0.id == id }) {
                await archiveVM.approveItem(item); count += 1
            } else if let req = adminRequestVM.treeEditRequests.first(where: { $0.id == id }) {
                await adminRequestVM.approveTreeEditRequest(request: req)
                if await adminRequestVM.awaitDecision(req.id) { count += 1 }
            }
        }
        if skippedWomen > 0 {
            adminRequestVM.errorMessage = AdminRequestViewModel.womenOneByOneMessage
        }
        return count
    }

    /// رفض دفعي يعبر كل الأنواع (لوضع "الكل").
    private func bulkRejectAcrossAllTypes(ids: [UUID]) async -> Int {
        var count = 0
        // ما خرج عن مجال الدور لا يُرفض ولو حُدّد (فحص الثغرات ب-٧)
        let idSet = idsInRoleScope(approving: false)

        for id in ids where idSet.contains(id) {
            if pendingMembers.contains(where: { $0.id == id }) {
                if await adminRequestVM.rejectOrDeleteMember(memberId: id) { count += 1 }
            } else if let post = newsVM.pendingNewsRequests.first(where: { $0.id == id }) {
                await newsVM.rejectNewsPost(postId: post.id); count += 1
            } else if let req = adminRequestVM.newsReportRequests.first(where: { $0.id == id }) {
                await adminRequestVM.rejectNewsReport(request: req)
                if await adminRequestVM.awaitDecision(req.id) { count += 1 }
            } else if let req = adminRequestVM.phoneChangeRequests.first(where: { $0.id == id }) {
                await adminRequestVM.rejectPhoneChangeRequest(request: req)
                if await adminRequestVM.awaitDecision(req.id) { count += 1 }
            } else if let req = adminRequestVM.nameChangeRequests.first(where: { $0.id == id }) {
                await adminRequestVM.rejectNameChangeRequest(request: req)
                if await adminRequestVM.awaitDecision(req.id) { count += 1 }
            } else if let d = diwaniyaVM.pendingDiwaniyas.first(where: { $0.id == id }) {
                await diwaniyaVM.rejectDiwaniya(id: d.id); count += 1
            } else if let req = adminRequestVM.deceasedRequests.first(where: { $0.id == id }) {
                await adminRequestVM.rejectDeceasedRequest(request: req)
                if await adminRequestVM.awaitDecision(req.id) { count += 1 }
            } else if let req = adminRequestVM.childAddRequests.first(where: { $0.id == id }) {
                await adminRequestVM.rejectChildAddRequest(request: req)
                if await adminRequestVM.awaitDecision(req.id) { count += 1 }
            } else if let req = adminRequestVM.photoSuggestionRequests.first(where: { $0.id == id }) {
                await adminRequestVM.rejectPhotoSuggestion(request: req)
                if await adminRequestVM.awaitDecision(req.id) { count += 1 }
            } else if projectsVM.pendingProjects.contains(where: { $0.id == id }) {
                await projectsVM.rejectProject(id: id); count += 1
            } else if let item = pendingArchiveItems.first(where: { $0.id == id }) {
                await archiveVM.rejectItem(item); count += 1
            } else if let req = adminRequestVM.treeEditRequests.first(where: { $0.id == id }) {
                await adminRequestVM.rejectTreeEditRequest(request: req, reason: nil)
                if await adminRequestVM.awaitDecision(req.id) { count += 1 }
            }
        }
        return count
    }

    // MARK: - Join Request Row

    /// مطابقة في الشجرة (`NameMatcher.linkSuggestions`): `matchCount` عمق التطابق بالترتيب (٢ = الأول + الأب)،
    /// `score` نسبته ٠…١٠٠ من `total` أجزاء اسم المتقدّم (بلا العائلة)، `fuzzy` لم يعد يُستعمل (صفر)
    typealias JoinMatch = (member: FamilyMember, matchCount: Int, matchedParts: [String], isRegistrationMatch: Bool,
                           score: Int, total: Int, fuzzy: Int)

    /// كل ما تعرضه بطاقة الانضمام ومربّع مطابقاتها — من الشجرة المحمّلة فقط (بلا نداء سيرفر)
    func joinCardInfo(for member: FamilyMember) -> JoinCardInfo {
        let tiers = joinTiers(for: member)
        var chains: [UUID: [String]] = [:]
        for e in tiers.all { chains[e.id] = ancestorChain(e.member) }
        let needsFather = member.isFemale || tiers.strongCount == 0
        let father = needsFather ? probableFather(for: member) : nil
        return JoinCardInfo(
            member: member, tiers: tiers, selectedId: joinPickId(member, tiers),
            showsWeak: expandedMatchMembers.contains(member.id),
            requestAge: Self.requestDate(member.createdAt).map { ageText(days: daysWaiting(since: $0)) },
            chains: chains,
            probableFather: member.isFemale ? nil : father,
            female: member.isFemale ? father.map { femaleSteps(for: member, father: $0) } : nil)
    }

    /// «عبدالله › حسن › خالد › يوسف»: جد الأب ← الجد ← الأب ← هو (الأسماء الأولى، من روابط الآباء)
    private func ancestorChain(_ m: FamilyMember) -> [String] {
        var names = [m.nameUnits.first ?? m.firstName]
        var current = m
        for _ in 0..<3 {
            guard let fid = current.fatherId, let f = memberVM.member(byId: fid) else { break }
            names.append(f.nameUnits.first ?? f.firstName)
            current = f
        }
        return names.reversed()
    }

    /// «الأب المحتمل»: رجل في الشجرة أسماؤه بالترتيب = أب المتقدّم ثم جده (اثنان على الأقل، بلا اختلاف قبل أن
    /// ينتهي أحدهما) — الأعمق تطابقاً. نفس مفاتيح `NameMatcher` في المطابقة
    private func probableFather(for member: FamilyMember) -> FamilyMember? {
        let key = "\(memberVM.allMembers.count)-\(member.fullName)"
        return joinTierCache.father(for: member.id, key: key) {
            let noise = NameMatcher.linkNoise(member.familyName)
            let target = Array(NameMatcher.linkChain(member.nameUnits, noise: noise).dropFirst())
            guard target.count >= 2 else { return nil }
            var best: (depth: Int, member: FamilyMember)? = nil
            for m in memberVM.allMembers where !m.isFemale && m.role != .pending && m.id != member.id && m.hasName {
                let chain = NameMatcher.linkChain(m.nameUnits,
                                                  noise: m.familyName.map { noise.union([NameMatcher.linkKey($0)]) } ?? noise)
                let n = min(target.count, chain.count)
                guard n >= 2, Array(chain.prefix(n)) == Array(target.prefix(n)) else { continue }
                if best == nil || n > best!.depth { best = (n, m) }
            }
            return best?.member
        }
    }

    /// خطوات الأنثى: بنات الأب في شجرة النساء (`WomenStore.cache`) وهل هي بينهن باسمها الأول
    private func femaleSteps(for member: FamilyMember, father: FamilyMember) -> JoinFemaleSteps {
        let daughters = WomenStore.cache.filter { $0.isFemale && $0.fatherId == father.id }
        let mine = NameMatcher.linkKey(member.nameUnits.first ?? member.firstName)
        let index = daughters.firstIndex { NameMatcher.linkKey($0.nameUnits.first ?? $0.firstName) == mine }
        let taken = index.map { i in
            WomenStore.linkedUserByWoman[daughters[i].id].map { $0 != member.id } ?? false
        } ?? false
        return JoinFemaleSteps(father: father, daughters: daughters.map { $0.nameUnits.first ?? $0.firstName },
                               herIndex: index, herTaken: taken, name: member.nameUnits.first ?? member.firstName)
    }

    // MARK: «الأرجح أولاً» (اختيار المالك ٢٠٢٦-١١-٠٦ — JoinMatchPanel.swift)

    /// درجات المطابقة: نفس المرشّحين والاستبعاد في `orderedMatchList`، بلا حدّ العشرين (العدد الكامل للدرجات)
    func joinTiers(for member: FamilyMember) -> JoinMatchTiers {
        guard !member.isFemale else { return .empty }
        let accounts = AdminAccountsStore.shared
        let serverIds = registrationMatches[member.id] ?? []
        let cfg = AppConfigValues.shared
        let minDepth = cfg.int("join_match_min_depth", default: 3)
        let bestOnly = cfg.int("join_match_best_only", default: 1) != 0
        let key = "\(memberVM.allMembers.count)-\(serverIds.count)-\(accounts.accounts.count)-\(member.fullName)-\(member.birthDate ?? "")-\(minDepth)-\(bestOnly)"
        return joinTierCache.tiers(for: member.id, key: key) {
            let existing = memberVM.allMembers.filter { m in
                m.role != .pending && m.id != member.id && m.hasName && !m.isFemale &&
                (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                m.isDeceased != true && accounts.info(m.id) == nil
            }
            let list = NameMatcher.linkSuggestions(for: member, among: existing, serverIds: Set(serverIds), limit: 500,
                                                     minDepth: minDepth, bestOnly: bestOnly)
            return JoinMatchTiers.build(for: member, suggestions: list)
        }
    }

    /// المختار — أو الأرجح (مطابق ثم قريب) إن لم يختر المراجع
    private func joinPickId(_ member: FamilyMember, _ tiers: JoinMatchTiers) -> UUID? {
        if let id = joinPicks[member.id], tiers.entry(id) != nil { return id }
        return tiers.suggested?.id
    }

    /// زرّ البطاقة والسحب: «ربط» بالمختار (تأكيد الدمج نفسه) — وبلا مختار «اختر من الشجرة» (المنتقي نفسه)
    private func joinApprove(_ member: FamilyMember) {
        let tiers = joinTiers(for: member)
        if let pick = tiers.entry(joinPickId(member, tiers)) {
            mergeTarget = (pendingMember: member, treeMember: pick.member)
            showMergeConfirm = true
        } else {
            memberToLink = member
        }
    }

    private func joinApproveLabel(_ member: FamilyMember) -> String {
        joinCardInfo(for: member).approveLabel
    }

    /// صورة المنضم في صفّه (= مساحة الضغط) وفي بطاقة تفاصيله
    private static let joinAvatar: CGFloat = DS.Icon.tapTarget

    /// «أنثى · تُربط بشجرة النساء» (الدفعة ١٢) — والربط «ربط بشجرة النساء» (`LinkWomanAccountSheet`، ٢٠٢٦-١٠-٢٤)
    static var femaleJoinTag: some View {
        HStack(spacing: DS.Spacing.xs) {
            DSStatusChip(text: L10n.t("أنثى", "Female"), icon: "figure.stand.dress", tint: DS.Color.female, size: .mini)
            Text(L10n.t("تُربط بشجرة النساء", "Belongs in the women's tree"))
                .dsFont(.caption)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    /// صورة المنضم (أو أول حرف من اسمه) بحلقة رفيعة بلون الحالة: أخضر له مطابقة، كهرماني اسم جديد
    private func joinPersonAvatar(_ member: FamilyMember, ring: Color, size: CGFloat) -> some View {
        let initial = member.firstName.trimmingCharacters(in: .whitespaces).first
            ?? member.fullName.trimmingCharacters(in: .whitespaces).first ?? "؟"
        let ringColor = ring.dsReadableGlyph
        return ZStack {
            Circle().fill(AppSection.admin.ink.opacity(DS.Opacity.tintFillSoft))
            if let raw = member.avatarUrl, !raw.isEmpty, let url = URL(string: raw) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .clipShape(Circle())
            } else {
                Text(String(initial))
                    .font(DS.Font.plex(size * 0.4, weight: .bold))
                    .foregroundColor(AppSection.admin.ink)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(ringColor, lineWidth: size > Self.joinAvatar ? DS.Border.widthBold * 2 : DS.Border.widthBold))
        .accessibilityHidden(true)
    }

    /// «ج»: «واتساب» رابط نصّي بلون التواصل (البترولي) — بدل الدائرة المجسّمة بلا كلمة
    private func whatsAppLink(_ url: URL) -> some View {
        let pad = (DS.Icon.tapTarget - DS.Icon.row) / 2
        return Button { UIApplication.shared.open(url) } label: {
            HStack(spacing: DS.Spacing.xxs) {
                Image(systemName: "message.fill")
                    .dsGlyph(DS.Glyph.micro, weight: .semibold)
                    .accessibilityHidden(true)
                Text(L10n.t("واتساب", "WhatsApp"))
                    .dsFont(.chip)
                    .lineLimit(1)
            }
            .foregroundColor(DS.Color.sea)
            .padding(.vertical, pad)
            .contentShape(Rectangle())
            .padding(.vertical, -pad)
        }
        .buttonStyle(DSScaleButtonStyle())
        .fixedSize()
        .accessibilityLabel(L10n.t("مراسلة على واتساب", "Message on WhatsApp"))
    }

    // MARK: - تنسيق تاريخ التسجيل مع الوقت
    private func formatRegistrationDate(_ isoString: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        guard let date = iso.date(from: isoString) ?? iso2.date(from: isoString) else {
            return String(isoString.prefix(16)).replacingOccurrences(of: "T", with: " ")
        }
        return DateHelper.displayDateTime(date)
    }

    private func joinMatchRow(match: JoinMatch, pendingMember: FamilyMember, isPlaced: Bool = false) -> some View {
        // عمق التطابق بالترتيب (الأول ثم الأب ثم الجد…) من أجزاء اسم المتقدّم — بلا اسم العائلة والروابط
        let totalParts = max(match.total, 1)
        let birth = match.member.birthDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return HStack(spacing: DS.Spacing.sm) {
            // كم جزءاً تطابق — الحلقة الصغيرة الموحّدة (الدفعة ١٠) بالعدد في وسطها
            DSRingGauge(progress: min(1, Double(match.matchCount) / Double(totalParts)), tint: AppSection.admin.ink,
                        size: DS.Ring.small, center: .count(match.matchCount), ink: AppSection.admin.ink)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(match.member.displayFullName)
                    .dsFieldFont(.adminRowTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DS.Spacing.xs) {
                    // السبب: «الاسم الأول + الأب + الجد»
                    Text(NameMatcher.linkReason(depth: match.matchCount))
                    .dsFieldFont(.footnote)
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(2)   // السبب كاملاً ولو بخط كبير
                    .minimumScaleFactor(0.85)

                    if match.isRegistrationMatch {
                        DSStatusChip(text: L10n.t("تسجيل", "Reg"), tint: AppSection.admin.ink)
                    }
                }

                // تاريخ الميلاد — يُقارن بتاريخ المنضم (الأقرب أولاً بين المتساويين)
                if !birth.isEmpty {
                    metaItem("calendar", birth)
                }
            }
            .accessibilityElement(children: .combine)
            // جسم الصفّ (لا شريحة «ربط») يعرض هذا المطابق في «مكانه في الشجرة»
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(DS.Anim.snappy) { joinPlacePick[pendingMember.id] = match.member.id }
            }
            .accessibilityAddTraits(isPlaced ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(L10n.t("يعرض مكانه في الشجرة", "Shows its place in the tree"))

            Spacer(minLength: 0)

            // «ربط» — الشريحة الموحّدة ممتلئة بتعبئة القسم
            DSChipButton(L10n.t("ربط", "Link"), isSelected: true) {
                mergeTarget = (pendingMember: pendingMember, treeMember: match.member)
                showMergeConfirm = true
            }
            .accessibilityLabel(L10n.t("ربط بـ \(match.member.displayFullName)",
                                       "Link to \(match.member.displayFullName)"))
        }
        // البطاقة الواحدة — المطابق المعروض في «مكانه في الشجرة» بإطار ذهبي
        .dsCard(padding: DS.Spacing.sm)
        .overlay(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
            .strokeBorder(DS.Color.accentLight.opacity(isPlaced ? 1 : 0), lineWidth: DS.Border.widthBold))
    }

    // MARK: - Registration Matches

    /// جلب مطابقات التسجيل من السيرفر لكل الأعضاء المعلقين
    /// - snapshot من admin_requests.details (وقت التسجيل، قد يكون قديم)
    /// - + RPC search_members_by_name الحي (v2: exact word + 75% + top-4 parts)
    /// ثم نُدمج النتائج (set) عشان نضمن أحدث وأدق match.
    private func fetchAllRegistrationMatches() async {
        for member in pendingMembers {
            async let stored = adminRequestVM.fetchMatchedMemberIds(for: member.id)
            async let live = adminRequestVM.searchMembersByNameRPC(member.fullName, excluding: member.id)
            let (storedIds, liveIds) = await (stored, live)

            // دمج بدون تكرار، السيرفر الحي أولاً (أدق)، ثم باقي snapshot
            var seen = Set<UUID>()
            var combined: [UUID] = []
            for id in liveIds where seen.insert(id).inserted {
                combined.append(id)
            }
            for id in storedIds where seen.insert(id).inserted {
                combined.append(id)
            }

            if !combined.isEmpty {
                await MainActor.run {
                    registrationMatches[member.id] = combined
                }
            }
        }
    }

    // MARK: - Name Matching

    /// تطبيع اسم عربي: إزالة التشكيل والتطويل + توحيد الألف/الهمزة/التاء المربوطة/الألف المقصورة.
    /// يسمح بمطابقة الأسماء المكتوبة بإملاء مختلف (أحمد/احمد، فاطمه/فاطمة، يحيى/يحيي).
    static func normalizeArabicName(_ s: String) -> String {
        var t = s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "ar"))
        let map: [Character: Character] = [
            "أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا",
            "ة": "ه", "ى": "ي", "ئ": "ي", "ؤ": "و"
        ]
        t = String(t.map { map[$0] ?? $0 })
        t = t.replacingOccurrences(of: "ـ", with: "") // تطويل
        return t.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// مسافة تعديل (Levenshtein) — للسماح بفرق حرف واحد بين اسمين.
    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }

    /// هل الاسمان متطابقان أو متشابهان (فرق حرف واحد بعد التطبيع)؟
    static func namesSimilar(_ a: String, _ b: String) -> Bool {
        let na = normalizeArabicName(a)
        let nb = normalizeArabicName(b)
        if na.isEmpty || nb.isEmpty { return false }
        if na == nb { return true }
        // فرق حرف واحد فقط — وللأسماء بطول 3 أحرف فأكثر لتفادي التطابق الزائد
        guard min(na.count, nb.count) >= 3, abs(na.count - nb.count) <= 1 else { return false }
        return editDistance(Array(na), Array(nb)) <= 1
    }

    /// لستة مرتّبة صارمة (طلب المالك ٢٠٢٦-١٠-٢٤ «تطلع اسماء ماله شغل بالربط») — `NameMatcher.linkSuggestions`:
    /// الاسم الأول ثم الأب ثم الجد بالترتيب (الاسم المركّب وحدة)، والعائلة في آخر الاسم ضجيج لا دليل، ولا يُقترح إلا
    /// من طابق الأول والأب على الأقل — ومطابقات السيرفر (`search_members_by_name` + لقطة التسجيل) بنفس الشرط.
    /// لا يُقترح من له حساب أو متوفى. الترتيب بعمق التطابق ثم قرب تاريخ الميلاد.
    func orderedMatchList(for member: FamilyMember) -> [JoinMatch] {
        // الأنثى تُربط بشجرة النساء — لا مطابقات (ولا «ربط») من شجرة الرجال
        guard !member.isFemale else { return [] }
        let accounts = AdminAccountsStore.shared
        // سجلات الشجرة فقط: رجال أحياء لهم اسم، مو pending، وبلا حساب (بلا هاتف، وليس في قائمة الحسابات إن حُمّلت)
        let existingMembers = memberVM.allMembers.filter { m in
            m.role != .pending && m.id != member.id && m.hasName && !m.isFemale &&
            (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            m.isDeceased != true && accounts.info(m.id) == nil
        }
        let serverIds = Set(registrationMatches[member.id] ?? [])
        let cfg = AppConfigValues.shared
        return NameMatcher.linkSuggestions(for: member, among: existingMembers, serverIds: serverIds,
                                           minDepth: cfg.int("join_match_min_depth", default: 3),
                                           bestOnly: cfg.int("join_match_best_only", default: 1) != 0).map { s in
            (member: s.member, matchCount: s.depth, matchedParts: [], isRegistrationMatch: s.isServer,
             score: s.total > 0 ? s.depth * 100 / s.total : 0, total: s.total, fuzzy: 0)
        }
    }

    /// معلومة صغيرة: أيقونة + نص (Plex 11) — التاريخ، الهاتف، مقدّم الطلب…
    private func metaItem(_ icon: String, _ text: String, color: Color = DS.Color.textTertiary) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            Image(dsSymbol: icon)
                .dsGlyph(DS.Glyph.micro, weight: .semibold)
                .accessibilityHidden(true)
            Text(text)
                .dsFont(.caption)
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundColor(color)
    }

    /// أيام الانتظار بالتقويم (اليوم = ٠)
    private func daysWaiting(since date: Date) -> Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: Date())).day ?? 0
        return max(0, days)
    }

    /// عمر مختصر يصلح للشارة ولبطاقة الرأس
    private func ageText(days: Int) -> String {
        switch days {
        case ..<1:    return L10n.t("اليوم", "Today")
        case 1:       return L10n.t("أمس", "1 day")
        case 2:       return L10n.t("يومان", "2 days")
        case 3...10:  return L10n.t("\(days) أيام", "\(days) days")
        default:      return L10n.t("\(days) يوماً", "\(days) days")
        }
    }

    /// تاريخ الطلب من نصّ ISO — بمحلّلين ثابتين (الصفوف والأرقام تُرسم كثيراً)
    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func requestDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return isoWithFraction.date(from: raw) ?? isoPlain.date(from: raw)
    }

    // MARK: - Request Detail Box

    /// «24 سنة · غير متزوجة» / «متوفاة · متزوجة» — المختارة كما في شجرة النساء الآن
    static func womanFacts(_ w: FamilyMember) -> String {
        var parts: [String] = []
        if w.isDeceased == true { parts.append(L10n.t("متوفاة", "Deceased")) }
        if let age = WifeCandidateRules.age(w) { parts.append(L10n.t("\(age) سنة", "\(age) years")) }
        else { parts.append(L10n.t("بلا تاريخ ميلاد", "No birth date")) }
        parts.append(WifeCandidateRules.isMarried(w) ? L10n.t("متزوجة", "Married") : L10n.t("غير متزوجة", "Not married"))
        return parts.joined(separator: " · ")
    }

    /// أسباب «طلب آخر» الداخلية التي يرسلها تعديل الملف الشخصي (EditProfileView) ← عنوان عربي مفهوم.
    /// كانت تظهر للإدارة كما هي («profile_marital») تحت «السبب» وبعنوان «طلب آخر».
    static func profileReasonTitle(_ reason: String?) -> String? {
        guard let reason, reason.hasPrefix("profile_") else { return nil }
        switch reason {
        case "profile_marital": return L10n.t("تغيير الحالة الاجتماعية", "Marital Status Change")
        case "profile_bio": return L10n.t("تعديل السيرة الذاتية", "Bio Update")
        case "profile_phone_hidden": return L10n.t("إظهار أو إخفاء الرقم", "Phone Visibility")
        default: return L10n.t("تعديل الملف الشخصي", "Profile Update")
        }
    }

    // MARK: مربّع الطلب (إعادة تصميم الإدارة ٢٠٢٦-١١-٢٦، الوحدة U9 — spec C.3، mock 3، T3)
    //
    // ورقة طويلة بمكدسها (`NavigationStack`): «إغلاق» · النوع · «⋯» (إدارة الطلب) ← صاحب الطلب ← المراحل الأربع ←
    // «التفاصيل» ← … ← «السجل» مطويّاً ← الشريط السفلي (زرّان + «المزيد»). كل قرار نفس نداء نموذج العرض السابق، وكل
    // كتابة تمرّ بـ`DebugAdminProbe.dryRun` (T0).
    // بعد قرار نجح فعلاً: من القائمة ينتقل للطلب التالي المعلّق بالمعرّف (الشريط معطّل حتى يُحمَّل ولـ٠٫٨ ث على الأقل،
    // والقارئ الصوتي يقول «الطلب التالي: …»، والأخير ينتهي بـ«كل الطلبات عولجت»)، ومن الإشعار (`focusId`) يُغلق.
    // الخطأ: يبقى برسالة السيرفر (`decide_admin_request` hint) — بعد إعادة جلب الطلب (المهلة: ربما نُفّذ)، وإن عالجه غيرك:
    // «عالجه فلان» ثم ينتقل. الأشخاص (المرسل، مقدّم الطلب) يُدفعون داخل مكدس المربّع خلف `AdminLazyPage{AnyView}`.

    /// ما يُدفع داخل مكدس المربّع
    enum BoxRoute: Hashable {
        case person(UUID)
        case place
        case note(AdminBoxNoteSpec.Purpose)
    }

    /// حال المربّع
    enum BoxPhase: Equatable {
        case idle
        /// قرار يُرسل — معرّف زرّه (دوّارته)
        case busy(String)
        /// الانتقال للتالي: الشريط معطّل حتى يُحمَّل التالي ولـ٠٫٨ ث على الأقل
        case advancing
        /// عالجه غيرك — سطره ثم الانتقال
        case handledElsewhere
        /// لا شيء باقٍ: «كل الطلبات عولجت»
        case finished(String)
    }

    /// قرار بمسار الموافقة/الرفض القديم (نفس نداءات نموذج العرض)
    enum BoxDecision {
        case approve, execute, executeNow
        case reject(String?)
    }

    /// قرارات الشريط بترتيب أهميتها + ما لا يكون زرّاً أبداً + سطر بلا أزرار
    private struct BoxActions {
        var decisions: [AdminBoxAction] = []
        var extras: [AdminBoxAction] = []
        var quiet: String? = nil
    }

    /// الطلب المعروض بعد الانتقال (nil = الذي فُتح به المربّع) — المربّع نفسه لا يُغلق ويُفتح عند الانتقال
    @State private var boxShown: RequestDetail? = nil
    /// فُتح من الإشعار/«اليوم» (`focusId`) — يُغلق بعد القرار بدل الانتقال
    @State private var boxFromFocus = false
    @State private var boxFocusUsed = false
    @State private var boxPhase: BoxPhase = .idle
    @State private var boxNotice: AdminBoxNotice? = nil
    /// آخر خطأ من نموذج العرض أثناء القرار (يُلتقط هنا فلا يظهر فوقه تنبيه ثانٍ)
    @State private var boxLastError: String? = nil
    @State private var boxPath: [BoxRoute] = []
    @State private var boxNoteText = ""
    @State private var boxAskFields: Set<ApprovalInfoField> = []
    @State private var boxConfirmDelete = false
    /// «ربط» من «يطابق في الشجرة» — الانضمام المنتظر نتيجة دمجه، وترتيب القائمة وقتها
    @State private var boxMergeMember: UUID? = nil
    @State private var boxMergeOrder: [String] = []

    /// يُقدَّم من `modalsLayer` — المربّع ورقة طويلة بمكدسها، ومربّع تعديل الرقم فوقه
    private func requestDetailSheet(_ detail: RequestDetail) -> some View {
        AnyView(requestBox(detail))
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .dsCenterBox(item: $phoneEditPendingMember) { member in
                PendingMemberPhoneSheet(member: member)
                    .environmentObject(adminRequestVM)
            }
    }

    private func requestBox(_ presented: RequestDetail) -> some View {
        let detail = boxCurrent(presented)
        let flow = liveFlow(detail)
        return NavigationStack(path: $boxPath) {
            AnyView(boxRoot(detail, flow: flow))
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: BoxRoute.self) { route in
                    // حارس المكدس: كل صفحة تُدفع داخل المربّع نوع مستقل خلف `AnyView`
                    AdminLazyPage { AnyView(boxPage(route, detail: detail)) }
                }
        }
        .tint(AppSection.admin.ink)
        .background(DS.Hub.background.ignoresSafeArea())
        .environment(\.adminRequestBoxRows, true)
        .interactiveDismissDisabled(boxIsBusy)
        .onAppear { boxOpened(presented) }
        .onChange(of: adminRequestVM.errorMessage) { boxCaptureError($0) }
        .onReceive(adminRequestVM.$mergeResult) { boxMergeFinished($0) }
        .dsAlert(AdminRequestBoxText.deleteQuestion, isPresented: $boxConfirmDelete) {
            Button(AdminRequestBoxText.deleteVerb, role: .destructive) { boxDelete(detail) }
            Button(AdminRequestBoxText.cancel, role: .cancel) {}
        } message: {
            Text(AdminRequestBoxText.deleteLine)
        }
        .debugStackProbe("AdminRequestBox", limitKB: DebugStackLimit.page)
    }

    /// الجذر: صفّ التنقّل ثم المحتوى يتمرّر، والشريط السفلي في المنطقة الآمنة
    private func boxRoot(_ detail: RequestDetail, flow: ApprovalSnapshot?) -> some View {
        let meta = detailMeta(for: detail)
        let finished: String? = { if case .finished(let title) = boxPhase { return title } else { return nil } }()
        return VStack(spacing: 0) {
            AdminRequestBoxNavRow(title: finished == nil ? meta.title : AdminArea.inbox.title,
                                  menu: finished == nil ? boxMenu(detail, flow: flow) : [],
                                  closeEnabled: !boxIsBusy,
                                  onClose: closeBox)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Hub.stackSpacing) {
                        if let finished {
                            AdminRequestBoxEndState(title: finished)
                        } else {
                            AnyView(boxContent(detail, meta: meta, flow: flow))
                        }
                    }
                    .id(finished == nil ? detail.id : "finished")
                    .transition(.opacity)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Hub.pageBottom)
                }
                .scrollDismissesKeyboard(.interactively)
                // الانتقال للتالي يبدأ من أعلاه
                .onChange(of: detail.id) { id in proxy.scrollTo(id, anchor: .top) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { AnyView(boxBar(detail, flow: flow)) }
        .background(DS.Hub.background.ignoresSafeArea())
    }

    /// المحتوى بالترتيب (spec C.3): صاحب الطلب ← المراحل ← التفاصيل ← (يطابق في الشجرة) ← البيانات المطلوبة ← فحص تلقائي
    /// ← مكانه في الشجرة ← ملاحظات الإدارة ← المرسل ← من أين وصل ← طلبات مرتبطة ← السجل. كل بطاقة نوع خلف `AnyView`
    private func boxContent(_ detail: RequestDetail, meta: DetailMeta, flow: ApprovalSnapshot?) -> some View {
        let women = WomenStore.cache
        let exec = execution(for: detail)
        let log = boxLog(detail, flow: flow)
        return VStack(alignment: .leading, spacing: DS.Hub.sectionGap) {
            VStack(alignment: .leading, spacing: DS.Hub.stackSpacing) {
                AnyView(boxTitleBlock(detail, meta: meta, flow: flow))
                AnyView(boxStageCard(flow, mine: canApprove(detailTab(detail)) || canReject(detailTab(detail))))
            }
            if case .join(let member) = detail {
                AnyView(boxJoinSections(member))
            } else {
                AnyView(boxDetailsSection(detail))
            }
            AnyView(AdminRequestChangesCard(changes: AdminRequestInsights.changes(detail, men: memberVM.allMembers, women: women)))
            AnyView(AdminRequestChecksCard(checks: AdminRequestInsights.checks(detail, execution: exec,
                                                                               men: memberVM.allMembers, women: women)))
            // للانضمام صفّه تحت «يطابق في الشجرة»
            if !isJoinDetail(detail), treePlace(for: detail) != nil {
                AnyView(boxPlaceRow)
            }
            AnyView(boxNotesSection(detail, flow: flow))
            AnyView(boxContext(detail))
            if let log {
                AnyView(AdminRequestLogCard(steps: log.steps, loading: log.loading))
            }
        }
    }

    // MARK: سطر صاحب الطلب والمراحل

    private func boxTitleBlock(_ detail: RequestDetail, meta: DetailMeta, flow: ApprovalSnapshot?) -> some View {
        let sender = senderId(for: detail).flatMap { memberVM.member(byId: $0) }
        let created = detailCreated(detail)
        let when = created == .distantPast ? nil : DateHelper.relativeTime(from: created)
        let source = origin(for: detail).map { L10n.t("من ", "from ") + $0.kind.title }
        return AdminRequestTitleBlock(name: boxRequesterName(detail, sender: sender, meta: meta),
                                      line: [when, source].compactMap { $0 }.joined(separator: " · "),
                                      avatarURL: sender?.avatarUrl ?? meta.imageUrl,
                                      urgent: flow?.isUrgent == true)
    }

    /// اسم صاحب الطلب كما يُقرأ: الأسماء الثلاثة الأولى، والمنضم باسمه الكامل، والمحتوى باسم صاحبه
    private func boxRequesterName(_ detail: RequestDetail, sender: FamilyMember?, meta: DetailMeta) -> String {
        switch detail {
        case .join(let m): return m.fullName
        case .news(let p): return memberVM.displayName(id: p.author_id, stored: p.author_name, .full)
        case .diwaniya(let d): return d.ownerName.isEmpty ? meta.title : d.ownerName
        case .project(let p) where sender == nil: return p.ownerName.isEmpty ? meta.title : p.ownerName
        default:
            guard let sender else { return meta.title }
            let short = sender.chainThreeName
            return short.isEmpty ? sender.fullName : short
        }
    }

    /// المراحل الأربع وسطرها («أوصى المراقب بالقبول · عندك · قبل 3 ساعات · متبقٍّ 21 ساعة») — بلا مسار «بانتظار قرارك»
    private func boxStageCard(_ flow: ApprovalSnapshot?, mine: Bool) -> some View {
        guard let flow else {
            // «بانتظار قرارك» لمن يقرّر فيه، و«بانتظار القرار» لمن يطّلع فقط
            return AdminRequestStageCard(step: nil, note: mine ? AdminRequestBoxText.waiting
                                                               : L10n.t("بانتظار القرار", "Awaiting a decision"))
        }
        var parts: [String] = []
        if let approves = flow.recommendsApproval, flow.stage != .review {
            let who = ApprovalWorkflow.specialistRole(for: flow.requestType).map(AdminRequestViewModel.approvalRoleTitle)
                ?? L10n.t("المختص", "the specialist")
            parts.append(approves ? L10n.t("أوصى \(who) بالقبول", "\(who) recommended approval")
                                  : L10n.t("أوصى \(who) بالرفض", "\(who) recommended rejection"))
        }
        if adminRequestVM.isEscalatedToMe(flow) {
            parts.append(L10n.t("صُعّد إليك لتأخره", "Escalated to you for being late"))
        } else if adminRequestVM.isApprovalWaitingForMe(flow) {
            parts.append(L10n.t("عندك", "With you"))
        } else {
            parts.append(L10n.t("عند \(boxHolderTitle(flow))", "With \(boxHolderTitle(flow))"))
        }
        if let since = flow.stageSince ?? flow.createdAt { parts.append(DateHelper.relativeTime(from: since)) }
        if flow.fastTrack { parts.append(L10n.t("مسار سريع", "Fast track")) }
        let sla = AdminRequestStatusText.sla(flow)
        if let sla { parts.append(sla.text) }
        return AdminRequestStageCard(step: AdminRequestBoxLogic.trackStep(stage: flow.stage.rawValue),
                                     note: parts.joined(separator: " · "),
                                     late: sla?.late == true || flow.isEscalated)
    }

    /// «الطلب الحين عند …» — باسم المستلم إن وُجد (نفس `ApprovalRequestBox`)
    private func boxHolderTitle(_ flow: ApprovalSnapshot) -> String {
        if adminRequestVM.isApprovalHeldByOther(flow), let holder = adminRequestVM.approvalHolder(flow) {
            return "\(holder.firstName) (\(AdminRequestViewModel.approvalRoleTitle(holder.role)))"
        }
        return adminRequestVM.approvalHolderTitle(flow)
    }

    // MARK: «التفاصيل»

    /// الصفوف الثلاثة (§10) ثم صفوف النوع — في بطاقة واحدة بفواصل تبدأ من النص (spec A.5/A.6)
    private func boxDetailsSection(_ detail: RequestDetail) -> some View {
        AdminBoxSection(title: AdminRequestBoxText.details) {
            AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                if let facts = requestFacts(for: detail) {
                    AdminRequestFactList(facts: facts, onOpenPerson: { boxPush(.person($0)) })
                }
                detailContent(for: detail)
            }
        }
    }

    /// صفّ «مكانه في الشجرة» ‹ — يدفع صفحته (المعاينة وزرّ «افتح بالشجرة الكاملة») داخل المربّع
    private var boxPlaceRow: some View {
        AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
            Button { boxPush(.place) } label: {
                AdminListRow(icon: "point.3.connected.trianglepath.dotted", tint: DS.Color.palm,
                             title: TreePlaceText.sectionTitle)
            }
            .buttonStyle(AdminRowPressStyle())
        }
    }

    /// «ملاحظات الإدارة» (لا يراها العضو): ملاحظات المسار (التوصية، سؤال العضو وردّه، ملاحظة المدير) ثم الداخلية بحقلها
    @ViewBuilder
    private func boxNotesSection(_ detail: RequestDetail, flow: ApprovalSnapshot?) -> some View {
        let row = adminRow(for: detail)
        let notesId: UUID? = flow?.requestId ?? row?.id
        let hidden = flow.map { adminRequestVM.hidesApprovalNotes($0) } ?? boxIsOwnRow(row)
        let flowNotes = flow.map { ApprovalFlowNotesCard.hasContent($0) } ?? false
        let ownNotes = notesId != nil && !hidden && adminRequestVM.approvalNotesAvailable == true
        if flowNotes || ownNotes {
            AdminBoxSection(title: L10n.t("ملاحظات الإدارة", "Admin notes"),
                            trailing: L10n.t("لا يراها العضو", "Hidden from the member")) {
                VStack(alignment: .leading, spacing: DS.Hub.cardGap) {
                    if let flow, flowNotes { ApprovalFlowNotesCard(flow: flow) }
                    if ownNotes, let notesId {
                        ApprovalInternalNotes(adminRequestVM: adminRequestVM, memberVM: memberVM, requestId: notesId, card: true)
                    }
                }
            }
        }
    }

    /// طلبك أنت (أو عنك) — ملاحظات الإدارة لا تظهر لك (إلا المالك)، كما في `contextPanel`
    private func boxIsOwnRow(_ row: (id: UUID, requester: UUID?, member: UUID)?) -> Bool {
        guard let me = authVM.currentUser, let row else { return false }
        return me.role != .owner && (row.requester == me.id || row.member == me.id)
    }

    /// «المرسل» بأعداد طلباته ← «من أين وصل» ← «طلبات مرتبطة» — الأقسام نفسها بشكل المربّع الجديد
    private func boxContext(_ detail: RequestDetail) -> some View {
        let row = adminRow(for: detail)
        let sender = senderId(for: detail).flatMap { memberVM.member(byId: $0) }
        let record = requestRecord(for: detail)
        let isWomen: Bool = {
            if record?.from?.steps.first == .womenTree { return true }
            if case .treeEdit(let r, _) = detail {
                return r.treeEditPayload?.women != nil || WomenTreeRequestLines(r.treeEditPayload?.notes ?? "") != nil
            }
            return false
        }()
        let subject = isWomen ? nil : record?.subject.flatMap { memberVM.member(byId: $0) }
        let relation = sender.flatMap { s in subject.flatMap { AdminTrailText.relation(sender: s, subject: $0) } }
        let context = AdminRequestContext(requestId: row?.id, sender: sender, relation: relation, memberId: row?.member,
                                          senderInfo: senderInfo(for: detail), log: nil,
                                          viewerCanModerate: authVM.canModerate, viewerId: authVM.currentUser?.id)
        return AdminRequestContextPanel(context: context, card: true, onOpenPerson: { boxPush(.person($0)) }) {
            EmptyView()
        }
    }

    /// «السجل»: خطوات المسار (من قام بها ومتى) أو سجلّ السيرفر — nil للمحتوى والانضمام بلا صفّ طلب
    private func boxLog(_ detail: RequestDetail, flow: ApprovalSnapshot?) -> (steps: [DSPathStep], loading: Bool)? {
        if let flow {
            guard let log = adminRequestVM.approvalSteps[flow.requestId] else { return ([], true) }
            var steps: [DSPathStep] = log.map { step in
                let subject = step.subjectId.flatMap { memberVM.member(byId: $0)?.firstName }
                var lines = [ApprovalWorkflow.date(step.createdAt).map { DateHelper.displayDateTime($0) } ?? AdminTrailText.notRecorded]
                if let note = step.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { lines.append(note) }
                return DSPathStep(icon: boxStepIcon(step.action), title: boxActor(step) + " " + step.actionTitle(subject: subject),
                                  lines: lines, tint: boxStepTint(step.action))
            }
            steps.append(DSPathStep(icon: "hourglass", title: L10n.t("الآن: ", "Now: ") + flow.stage.title,
                                    lines: [flow.stageSince.map { DateHelper.relativeTime(from: $0) } ?? ""].filter { !$0.isEmpty },
                                    tint: DS.Color.accent))
            return (steps, false)
        }
        guard let row = adminRow(for: detail) else { return nil }
        let events = handledStore.events[row.id]
        return (AdminRequestLog.steps(events: events, requesterId: row.requester, createdAt: requestRecord(for: detail)?.created,
                                      lookup: { memberVM.member(byId: $0) }), false)
    }

    /// «الاسم (الدور)» لمن قام بالخطوة — نفس `ApprovalRequestBox`
    private func boxActor(_ step: AdminRequestStep) -> String {
        let role = step.actorRole.flatMap(FamilyMember.UserRole.init(rawValue:))
        let roleTitle = role.map(AdminRequestViewModel.approvalRoleTitle)
        guard step.actorId != nil else { return roleTitle ?? L10n.t("النظام", "System") }
        guard let name = step.actorId.flatMap({ memberVM.member(byId: $0)?.firstName }) else {
            return roleTitle ?? L10n.t("—", "—")
        }
        guard let roleTitle, role != .member, role != .pending else { return name }
        return "\(name) (\(roleTitle))"
    }

    private func boxStepIcon(_ action: String) -> String {
        switch action {
        case "rejected", "recommend_reject": return "xmark.circle.fill"
        case "approve", "executed", "recommend_approve": return "checkmark.circle.fill"
        case "request_info", "provide_info": return "questionmark.bubble.fill"
        case "escalated", "reminded": return "exclamationmark.circle.fill"
        case "submitted": return "paperplane.fill"
        default: return "circle.fill"
        }
    }

    private func boxStepTint(_ action: String) -> Color? {
        switch action {
        case "rejected", "recommend_reject", "escalated": return DS.Color.error
        case "approve", "executed", "recommend_approve": return DS.Color.success
        case "request_info", "reminded": return DS.Color.warning
        default: return nil
        }
    }

    // MARK: الصفحات المدفوعة داخل المربّع

    private func boxPage(_ route: BoxRoute, detail: RequestDetail) -> some View {
        switch route {
        case .person(let id):
            // ورقة العضو داخل مكدس المربّع (لا ورقة فوق ورقة) — عضو واحد = بلا شريط «السابق · التالي»
            return AnyView(AdminMemberSheet(ids: [id], start: 0)
                .toolbar(.hidden, for: .navigationBar)
                .background(DS.Hub.background.ignoresSafeArea()))
        case .place:
            return AnyView(AdminBoxPage(title: TreePlaceText.sectionTitle, onBack: boxPop) {
                boxPlaceSection(detail)
            })
        case .note(let purpose):
            return AnyView(AdminBoxNotePage(spec: AdminBoxNoteSpec(purpose: purpose), adminRequestVM: adminRequestVM,
                                            text: $boxNoteText, fields: $boxAskFields, onBack: boxPop) {
                boxPop()
                boxConfirmNote(purpose, detail: detail)
            })
        }
    }

    /// «مكانه في الشجرة»: المطابق المختار للانضمام، وإلا مكان الطلب — وزرّ القرار المباشر في المعاينة
    @ViewBuilder
    private func boxPlaceSection(_ detail: RequestDetail) -> some View {
        if case .join(let member) = detail {
            let results = joinTiers(for: member).all
            let match = results.first { $0.member.id == joinPlacePick[member.id] }?.member ?? results.first?.member
            TreePlaceSection(place: match.map { TreePlace.join(match: $0) }, index: 0, men: memberVM.allMembers,
                             primary: boxPlacePrimary(detail), emptyNote: TreePlaceText.noMatch)
        } else if let place = treePlace(for: detail) {
            TreePlaceSection(place: place, index: 0, men: memberVM.allMembers, primary: boxPlacePrimary(detail))
        }
    }

    /// زرّ المعاينة: القرار المباشر وحده (الموافقة بلا مسار، أو «تنفيذ» للمختص) — يرجع للطلب ثم يمرّ بالقرار نفسه
    private func boxPlacePrimary(_ detail: RequestDetail) -> TreePlacePrimary? {
        guard authVM.adminCanEdit(.inbox) else { return nil }
        if let flow = liveFlow(detail) {
            guard ApprovalDecisionRoles(adminRequestVM, snapshot: flow).primary == .execute else { return nil }
            return TreePlacePrimary(title: L10n.t("تنفيذ", "Carry out"), icon: "checkmark.circle.fill") {
                boxPath = []
                boxApprove(detail, execute: true)
            }
        }
        guard canApprove(detailTab(detail)) else { return nil }
        return TreePlacePrimary(title: approveLabelFor(detail), icon: approveIconFor(detail)) {
            boxPath = []
            boxApprove(detail, execute: false)
        }
    }

    private func boxPush(_ route: BoxRoute) {
        guard boxPhase == .idle || boxPhase == .advancing else { return }
        boxPath.append(route)
    }

    private func boxPop() {
        if !boxPath.isEmpty { boxPath.removeLast() }
    }

    // MARK: الشريط السفلي و«⋯»

    private func boxBar(_ detail: RequestDetail, flow: ApprovalSnapshot?) -> some View {
        if case .finished = boxPhase {
            return AdminRequestDecisionBar(buttons: [
                AdminBoxAction(id: "back", title: AdminRequestBoxText.backToInbox, style: .primary) { closeBox() },
            ])
        }
        let acts = boxActions(detail, flow: flow)
        let split = AdminRequestBoxLogic.barSplit(decisions: acts.decisions.count, extras: acts.extras.count)
        let busyId: String? = { if case .busy(let id) = boxPhase { return id } else { return nil } }()
        return AdminRequestDecisionBar(buttons: Array(acts.decisions.prefix(split.buttons)),
                                       more: Array(acts.decisions.dropFirst(split.buttons)) + acts.extras,
                                       busyId: busyId,
                                       locked: boxPhase != .idle,
                                       notice: boxNotice,
                                       quietLine: acts.quiet)
    }

    /// القرارات بحسب الدور والمرحلة (spec C.3 البند ٨) — بنفس الصلاحيات (`canApprove`/`canReject` × «يعدّل»، قواعد المسار)
    private func boxActions(_ detail: RequestDetail, flow: ApprovalSnapshot?) -> BoxActions {
        var out = BoxActions()
        guard authVM.adminCanEdit(.inbox) else {
            out.quiet = AdminRequestBoxText.readOnly
            return out
        }
        if let flow {
            let roles = ApprovalDecisionRoles(adminRequestVM, snapshot: flow)
            switch roles.primary {
            case .recommend:
                // المختص: «أوصي بالقبول» · «أوصي بالرفض» (ملاحظته في صفحتها)
                out.decisions.append(AdminBoxAction(id: "recommendApprove", title: L10n.t("أوصي بالقبول", "Recommend approval"),
                                                    style: .primary) { boxOpenNote(.recommendApprove) })
                out.decisions.append(AdminBoxAction(id: "recommendReject", title: L10n.t("أوصي بالرفض", "Recommend rejection"),
                                                    style: .plain) { boxOpenNote(.recommendReject) })
            case .approve:
                // المدير: «اعتماد» يرجّعه للمختص لينفّذه
                out.decisions.append(AdminBoxAction(id: "approve", title: L10n.t("اعتماد", "Approve"), style: .primary) {
                    boxAdvance(detail, .approve, note: nil, id: "approve")
                })
            case .execute:
                out.decisions.append(AdminBoxAction(id: "execute", title: L10n.t("تنفيذ", "Carry out"), style: .primary) {
                    boxApprove(detail, execute: true)
                })
            case nil:
                break
            }
            if roles.canReject {
                out.decisions.append(AdminBoxAction(id: "reject", title: L10n.t("رفض", "Reject"), style: .reject) {
                    boxOpenNote(.rejectFlow)
                })
            }
            if roles.primary == .approve {
                out.extras.append(AdminBoxAction(id: "executeNow", title: L10n.t("اعتماد وتنفيذ الحين", "Approve and carry out now"),
                                                 icon: "bolt.fill") { boxApprove(detail, execute: true) })
                out.extras.append(AdminBoxAction(id: "approveNote", title: L10n.t("اعتماد بملاحظة للمختص", "Approve with a note"),
                                                 icon: "text.bubble") { boxOpenNote(.approveNote) })
            }
            if roles.canReturn {
                out.extras.append(AdminBoxAction(id: "return", title: L10n.t("إرجاع للمختص", "Return to the specialist"),
                                                 icon: "arrow.uturn.backward") { boxOpenNote(.returnBack) })
            }
            if roles.canAsk {
                out.extras.append(AdminBoxAction(id: "ask", title: L10n.t("اطلب معلومات", "Ask for info"),
                                                 icon: "questionmark.bubble") { boxOpenNote(.ask) })
            }
            if out.decisions.isEmpty && out.extras.isEmpty {
                out.quiet = roles.isOwn
                    ? L10n.t("هذا طلبك — يعالجه مسؤول آخر.", "This is your request — another admin handles it.")
                    : L10n.t("الطلب حالياً لدى \(boxHolderTitle(roles.flow)).", "The request is now with \(boxHolderTitle(roles.flow)).")
            }
            return out
        }
        let tab = detailTab(detail)
        if canApprove(tab) {
            out.decisions.append(AdminBoxAction(id: "approve", title: approveLabelFor(detail), style: .primary) {
                boxApprove(detail, execute: false)
            })
        }
        // رفض الانضمام = حذف ملف المتقدّم — للمالك والمدير (`canReject(.joinRequests)`)
        if canReject(tab) {
            out.decisions.append(AdminBoxAction(id: "reject", title: L10n.t("رفض", "Reject"), style: .reject) {
                boxOpenNote(.reject)
            })
        }
        // «حوّل للمدير»: المراقب يقبل الانضمام ولا يرفضه — إشعار الإدارة الموجود بملاحظته (التنبيه في `modalsLayer`)
        if case .join(let member) = detail, !canReject(.joinRequests), authVM.canApproveTreeRequests {
            out.extras.append(AdminBoxAction(id: "forward", title: L10n.t("حوّل للمدير", "Forward to manager"),
                                             icon: "arrowshape.turn.up.left.2") {
                forwardJoinNote = ""
                forwardJoinMember = member
            })
        }
        if out.decisions.isEmpty && out.extras.isEmpty { out.quiet = AdminRequestBoxText.readOnly }
        return out
    }

    /// «⋯» = إدارة الطلب وحدها (spec C.3 البند ١): عاجل · استلم/اترك/خذه («مسار ٢») · حذف الطلب (المالك/المدير، يسأل)
    private func boxMenu(_ detail: RequestDetail, flow: ApprovalSnapshot?) -> [AdminBoxMenuItem] {
        guard authVM.adminCanEdit(.inbox) else { return [] }
        let enabled = boxPhase == .idle
        var items: [AdminBoxMenuItem] = []
        if let f = flow, f.hasV2 {
            if adminRequestVM.canSetApprovalPriority(f) {
                items.append(AdminBoxMenuItem(id: "urgent",
                                              title: f.isUrgent ? L10n.t("ليس عاجلاً", "Not urgent") : L10n.t("اجعله عاجلاً", "Make it urgent"),
                                              icon: f.isUrgent ? "flame" : "flame.fill", isEnabled: enabled) {
                    boxHousekeeping(f, f.isUrgent ? .markNormal : .markUrgent)
                })
            }
            if adminRequestVM.canClaimApproval(f) {
                items.append(AdminBoxMenuItem(id: "claim", title: L10n.t("استلم الطلب", "Take the request"),
                                              icon: "hand.raised.fill", isEnabled: enabled) { boxHousekeeping(f, .claim) })
            }
            if adminRequestVM.canReleaseApproval(f) {
                items.append(AdminBoxMenuItem(id: "release", title: L10n.t("اترك الطلب", "Release the request"),
                                              icon: "hand.raised.slash", isEnabled: enabled) { boxHousekeeping(f, .release) })
            }
            if adminRequestVM.isApprovalHeldByOther(f), adminRequestVM.canTakeOverApproval(f) {
                let name = adminRequestVM.approvalHolder(f)?.firstName ?? L10n.t("مسؤول آخر", "another admin")
                items.append(AdminBoxMenuItem(id: "take", title: L10n.t("خذه من \(name)", "Take it over from \(name)"),
                                              icon: "arrow.down.circle.fill", isEnabled: enabled) { boxHousekeeping(f, .claim) })
            }
        }
        // حذف الطلب نهائياً — لا لطلب الانضمام (رفضه هو حذف الملف)
        if canHardDelete {
            if case .join = detail {} else {
                items.append(AdminBoxMenuItem(id: "delete", title: L10n.t("حذف الطلب", "Delete the request"), icon: "trash",
                                              destructive: true, isEnabled: enabled) { boxConfirmDelete = true })
            }
        }
        return items
    }

    // MARK: - «مسار الموافقات» في مربّع التفاصيل (طلب المالك ٢٠٢٦-١٠-١٥)

    /// معرّف صفّ التفاصيل للمسار — طلبات `admin_requests` فقط (للانضمام: العضو المعلّق)
    private func approvalSnapshot(for detail: RequestDetail) -> ApprovalSnapshot? {
        switch detail {
        case .join(let m): return adminRequestVM.approvalSnapshot(forRowId: m.id)
        case .report(let r), .nameChange(let r), .deceased(let r), .child(let r), .photo(let r):
            return adminRequestVM.approvalSnapshot(forRowId: r.id)
        case .treeEdit(let r, _): return adminRequestVM.approvalSnapshot(forRowId: r.id)
        case .phone(let r): return adminRequestVM.approvalSnapshot(forRowId: r.id)
        case .news, .diwaniya, .project, .archive: return nil
        }
    }

    /// كل تفصيل في «الوارد» طلب بقرار (عناصر «مشكلات الشجرة» خرجت إلى «العائلة»)
    private func detailHasDecision(_ detail: RequestDetail) -> Bool {
        true
    }

    /// تاب الطلب المفتوح — لسطر «الوارد ‹ القسم ‹ النوع»
    private func detailTab(_ detail: RequestDetail) -> RequestTab {
        switch detail {
        case .join: return .joinRequests
        case .news: return .news
        case .report: return .reports
        case .phone: return .phone
        case .nameChange: return .nameChange
        case .diwaniya: return .diwaniya
        case .deceased: return .deceased
        case .child: return .children
        case .photo: return .photos
        case .project: return .projects
        case .archive: return .archive
        case .treeEdit: return .treeOther
        }
    }

    /// وقت وصول الطلب المفتوح (لـ«جديد»)
    private func detailCreated(_ detail: RequestDetail) -> Date {
        guard let item = sortedAllItems.first(where: { requestDetail(for: $0).id == detail.id }) else { return .distantPast }
        return allItemDate(item)
    }

    private func isJoinDetail(_ detail: RequestDetail) -> Bool {
        if case .join = detail { return true }
        return false
    }

    /// طلب الانضمام في المربّع الجديد (spec C.3 البند ٥): «التفاصيل» (الهاتف بقلمه، الميلاد، التسجيل) ← «يطابق في الشجرة»
    /// صفوفاً بـ«ربط» (تأكيد الدمج نفسه) ← «مكانه في الشجرة» ‹. الأنثى: «في شجرة النساء» (زرّ القرار «ربط بشجرة النساء»)
    private func boxJoinSections(_ member: FamilyMember) -> some View {
        let tiers = joinTiers(for: member)
        let results = tiers.all
        let placeId = results.first { $0.member.id == joinPlacePick[member.id] }?.member.id ?? results.first?.member.id
        let fromWeb = member.registrationPlatform == "web"
        let uname = member.username?.trimmingCharacters(in: .whitespaces) ?? ""
        let phone = member.phoneNumber?.trimmingCharacters(in: .whitespaces) ?? ""
        let birth = member.birthDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let editPhone: (() -> Void)? = detailPhoneEditMember(.join(member)).map { m in { phoneEditPendingMember = m } }
        // «ربط» = قبول الانضمام بمطابقه — لمن يقبل طلبات الشجرة والقسم «يعدّل»
        let canLink = canApprove(.joinRequests)
        return VStack(alignment: .leading, spacing: DS.Hub.sectionGap) {
            AdminBoxSection(title: AdminRequestBoxText.details) {
                AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                    AdminDetailInfoRow(icon: "phone.fill", label: L10n.t("الهاتف", "Phone"),
                                       value: phone.isEmpty ? L10n.t("غير مسجّل", "Not set") : KuwaitPhone.display(phone),
                                       color: DS.Color.sea, whatsapp: phone.isEmpty ? nil : phone,
                                       edit: editPhone, tel: KuwaitPhone.telURL(phone))
                    AdminDetailInfoRow(icon: "calendar", label: L10n.t("تاريخ الميلاد", "Birth date"),
                                       value: birth.isEmpty ? L10n.t("غير مذكور", "Not given") : (DateHelper.displayDate(birth) ?? birth),
                                       color: DS.Color.primary)
                    if member.isFemale {
                        AdminDetailInfoRow(icon: "figure.stand.dress", label: L10n.t("الجنس", "Gender"),
                                           value: L10n.t("أنثى — تُربط بشجرة النساء", "Female — belongs in the women's tree"),
                                           color: DS.Color.female)
                    }
                    AdminDetailInfoRow(icon: fromWeb ? "globe" : "iphone", label: L10n.t("التسجيل", "Signed up"),
                                       value: fromWeb
                                           ? (uname.isEmpty ? L10n.t("من الموقع", "Website")
                                                            : L10n.t("من الموقع · \u{2066}@\(uname)\u{2069}", "Website · @\(uname)"))
                                           : L10n.t("من التطبيق برقم الجوال", "App, with phone number"),
                                       color: DS.Color.info)
                }
            }
            if member.isFemale {
                AdminBoxSection(title: L10n.t("في شجرة النساء", "In the women's tree")) {
                    DSNoteCard(L10n.t("تُربط بعقدتها في شجرة النساء تحت أبيها، أو تُضاف بنتاً جديدة له — من «ربط بشجرة النساء».",
                                      "She's linked to her node in the women's tree under her father, or added as his new daughter — via «Link to women's tree»."),
                               icon: "link.badge.plus", tint: DS.Color.female)
                }
            } else {
                AdminBoxSection(title: L10n.t("يطابق في الشجرة", "Matches in the tree"),
                                trailing: results.isEmpty ? nil : "\(results.count)") {
                    VStack(alignment: .leading, spacing: DS.Hub.cardGap) {
                        if results.isEmpty {
                            DSNoteCard(L10n.t("لا يوجد اسم مطابق في الشجرة — عند «ربط بالشجرة» يُضاف عضواً جديداً.",
                                              "No matching name in the tree — linking adds them as a new member."),
                                       icon: "person.badge.plus", tint: DS.Color.warning)
                        } else {
                            AdminRowsCard {
                                ForEach(results) { e in
                                    JoinBoxMatchRow(name: e.member.displayFullName,
                                                    reason: NameMatcher.linkReason(depth: e.depth),
                                                    birth: tiers.birthLine(e),
                                                    depth: e.depth, total: max(e.parts.count, 1),
                                                    isRegistration: e.isServer,
                                                    isPlaced: results.count > 1 && e.member.id == placeId,
                                                    onShowPlace: {
                                                        withAnimation(DS.Anim.snappy) { joinPlacePick[member.id] = e.member.id }
                                                        boxPush(.place)
                                                    },
                                                    onLink: canLink ? { boxLink(member, to: e.member) } : nil)
                                }
                            }
                        }
                        AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                            Button { boxPush(.place) } label: {
                                AdminListRow(icon: "point.3.connected.trianglepath.dotted", tint: DS.Color.palm,
                                             title: TreePlaceText.sectionTitle)
                            }
                            .buttonStyle(AdminRowPressStyle())
                        }
                    }
                }
            }
        }
    }

    /// «ربط» من صفّ مطابق: تأكيد الدمج نفسه (`modalsLayer`)، والمربّع ينتظر نتيجته لينتقل
    private func boxLink(_ member: FamilyMember, to match: FamilyMember) {
        guard boxPhase == .idle, authVM.adminCanEdit(.inbox), canApprove(.joinRequests) else { return }
        boxMergeMember = member.id
        boxMergeOrder = boxOrder()
        mergeTarget = (pendingMember: member, treeMember: match)
        showMergeConfirm = true
    }

    @ViewBuilder
    private func genericDetailBoxContent(_ detail: RequestDetail, meta: DetailMeta, handled: AdminRequest? = nil) -> some View {
        if let imageUrl = meta.imageUrl, let url = URL(string: imageUrl) {
            detailHeroImage(url: url, color: meta.color)
                .dsStaggerIn(0)
        }

        // التفاصيل المطوّرة (العيّنة ١٦) — للطلب المعلّق فقط: الحالة والمهلة والتنفيذ، «البيانات المطلوبة»، «فحص تلقائي»
        if handled == nil {
            decisionAids(for: detail, index: 1)
        }

        DSComposerSection(title: detailInfoTitle(detail),
                          icon: detailInfoIcon(detail),
                          tint: AppSection.admin.ink,
                          index: 1) {
            // §10: «نوع الطلب» · «القرابة» · «مقدّم الطلب» أولاً — لكل طلب يخصّ شخصاً
            if let facts = requestFacts(for: detail) {
                AdminRequestFactRows(facts: facts)
            }
            // الحقول القصيرة جنب بعض، والطويلة بعرض المربّع («اذا كان النص صغير خلهم جنب بعض» ٢٠٢٦-١١-٢٤)
            AdminDetailPairLayout(spacing: DS.Spacing.sm) {
                detailContent(for: detail)
            }
        }

        // «مكانه في الشجرة» (طلب المالك ٢٠٢٦-١١-١٣) — للطلبات التي تخصّ شخصاً في الشجرة فقط: قبل التنفيذ، وفي
        // المعالَج (§8) بنتيجته (تمّ / «رُفض») بلا زرّ إجراء في المعاينة
        let place = handled.map { handledPlace($0) } ?? treePlace(for: detail)
        if let place {
            AnyView(TreePlaceSection(place: place, index: 2, men: memberVM.allMembers,
                                     primary: handled == nil ? placePrimary(for: detail) : nil))
        }

        // «المرسل»: مسار الإرسال خطواتٍ مرقّمة، ومن أرسله، والجهاز والوقت (طلب المالك ٢٠٢٦-١١-١١، التصميم المعتمد).
        // المعلّق (العيّنة ١٦): «المرسل» بأعداد طلباته ← «من أين وصل» ← «سجل الطلب» ← الملاحظات ← «طلبات مرتبطة»
        if handled == nil {
            contextPanel(for: detail, index: place == nil ? 3 : 4)
        } else {
            AdminSenderSection(info: senderInfo(for: detail), index: place == nil ? 2 : 3)
        }
    }

    /// الصفوف الثلاثة (§10) — طلبات الأشخاص فقط (لا الأخبار والمحتوى والبلاغات والرسائل)
    private func requestFacts(for detail: RequestDetail) -> AdminRequestFacts? {
        let lookup: (UUID) -> FamilyMember? = { memberVM.member(byId: $0) }
        switch detail {
        case .nameChange(let r), .deceased(let r), .child(let r), .photo(let r), .treeEdit(let r, _):
            return AdminRequestFacts.of(r, member: lookup)
        case .phone(let p):
            return AdminRequestFacts.edit(requesterId: p.requesterId ?? p.memberId, subjectId: p.memberId, member: lookup)
        case .report(let r):
            return AdminRequestFacts.of(r, member: lookup)
        case .join, .news, .diwaniya, .project, .archive:
            return nil
        }
    }

    /// مكان الطلب المعالَج (§8): المقبول بصيغة ما تمّ، والمرفوض «رُفض» — غيرهما (مسحوب…) بلا قسم
    private func handledPlace(_ r: AdminRequest) -> TreePlace? {
        guard r.status == ApprovalStatus.approved.rawValue || r.status == ApprovalStatus.rejected.rawValue else { return nil }
        return TreePlace.fromRequest(r, data: TreePlaceData(men: memberVM.allMembers, women: WomenStore.cache))
    }

    /// مكان الطلب في الشجرة (`TreePlace`) — المحتوى (أخبار، ديوانيات، مشاريع، أرشيف، بلاغات، رسائل) بلا قسم
    private func treePlace(for detail: RequestDetail) -> TreePlace? {
        let label = detailMeta(for: detail).title
        let data = TreePlaceData(men: memberVM.allMembers, women: WomenStore.cache)
        switch detail {
        case .join: return nil   // للانضمام صفّه تحت «يطابق في الشجرة» في المربّع (`boxJoinSections`)
        case .child(let r): return TreePlace.childAdd(r, kindLabel: label)
        case .treeEdit(let r, let action): return TreePlace.treeEdit(r, action: action, kindLabel: label, data: data)
        case .nameChange(let r): return TreePlace.nameChange(r, kindLabel: label)
        case .deceased(let r): return TreePlace.deceasedReport(r, kindLabel: label)
        case .photo(let r): return TreePlace.photoSuggestion(r, kindLabel: label)
        case .phone: return nil   // تغيير الرقم لا يخصّ الشجرة (طلب المالك ٢٠٢٦-١١-١٧)
        case .news, .report, .diwaniya, .project, .archive: return nil
        }
    }

    /// زرّ المربّع الرئيسي في المعاينة: نفس العنوان والمعالج. مع «مسار الموافقات» = «تنفيذ» للمختص في مرحلة التنفيذ
    /// وحدها (غيرها يحتاج ملاحظة أو مبدّلاً داخل المربّع) — وإلا «العودة إلى الطلب» وحده
    private func placePrimary(for detail: RequestDetail) -> TreePlacePrimary? {
        if let flow = approvalSnapshot(for: detail) {
            let live = adminRequestVM.liveApprovalSnapshot(requestId: flow.requestId) ?? flow
            guard live.stage == .execute, !adminRequestVM.isOwnApprovalRequest(live),
                  !adminRequestVM.isApprovalDecisionLocked(live), adminRequestVM.canActAsApprovalSpecialist(live)
            else { return nil }
            return TreePlacePrimary(title: L10n.t("تنفيذ", "Carry out"), icon: "checkmark.circle.fill") { approveDetail(detail) }
        }
        guard detailHasDecision(detail) else { return nil }
        return TreePlacePrimary(title: approveLabelFor(detail), icon: approveIconFor(detail)) { approveDetail(detail) }
    }

    /// صفّ `admin_requests` وراء التفصيل (المسار والجهاز والوقت) — المحتوى (أخبار، ديوانيات…) بلا صفّ
    private func requestRecord(for detail: RequestDetail) -> (from: RequestSource?, via: RequestSentVia?, created: String?, subject: UUID?)? {
        switch detail {
        case .report(let r), .nameChange(let r), .deceased(let r), .child(let r), .photo(let r):
            return (r.sentFrom, r.sentVia, r.createdAt, r.memberId)
        case .treeEdit(let r, _):
            let target = r.treeEditPayload?.targetMemberId.flatMap(UUID.init(uuidString:)) ?? r.memberId
            return (r.sentFrom, r.sentVia, r.createdAt, target)
        case .phone(let r): return (r.sentFrom, r.sentVia, r.createdAt, r.memberId)
        case .join(let m):
            let row = adminRequestVM.joinApprovalRequests.first { $0.memberId == m.id || $0.requesterId == m.id }
                ?? handledStore.items.first { $0.memberId == m.id && ($0.requestType == RequestType.linkRequest.rawValue
                                                                     || $0.requestType == RequestType.joinRequest.rawValue) }
            return (row?.sentFrom, row?.sentVia, row?.createdAt ?? m.createdAt, m.id)
        case .news(let p): return (nil, nil, p.created_at, nil)
        case .diwaniya, .project, .archive: return nil
        }
    }

    // MARK: «من أين وصل» والتنفيذ (العيّنتان ١٥ و١٦)

    /// مسار الطلب والجهاز ونوع التنفيذ — المسار المسجّل وإلا المستنتج
    private func origin(for detail: RequestDetail) -> AdminRequestOrigin? {
        let record = requestRecord(for: detail)
        let steps = AdminTrailText.pathSteps(recorded: record?.from, inferred: requestSource(for: detail))
        guard !steps.isEmpty || record?.via != nil else { return nil }
        return AdminRequestOrigin(steps: steps, via: record?.via, execution: execution(for: detail))
    }

    /// هل يُنفَّذ الطلب عند قبوله — القاعدة الواحدة `AdminRequestExecution`
    private func execution(for detail: RequestDetail) -> AdminRequestExecution? {
        switch detail {
        case .join: return .manual
        case .phone(let r): return AdminRequestExecution.of(type: r.requestType, payload: nil)
        case .report(let r), .nameChange(let r), .deceased(let r), .child(let r), .photo(let r), .treeEdit(let r, _):
            return AdminRequestExecution.of(r)
        case .news, .diwaniya, .project, .archive: return nil
        }
    }

    /// تفصيل صفّ البطاقة من معرّفه (للانضمام: العضو المعلّق)
    private func rowDetail(_ id: UUID) -> RequestDetail? {
        if let r = adminRequestVM.treeEditRequests.first(where: { $0.id == id }) {
            return .treeEdit(r, r.treeEditPayload?.resolvedAction ?? .add)
        }
        if let r = adminRequestVM.nameChangeRequests.first(where: { $0.id == id }) { return .nameChange(r) }
        if let r = adminRequestVM.deceasedRequests.first(where: { $0.id == id }) { return .deceased(r) }
        if let r = adminRequestVM.childAddRequests.first(where: { $0.id == id }) { return .child(r) }
        if let r = adminRequestVM.photoSuggestionRequests.first(where: { $0.id == id }) { return .photo(r) }
        if let r = adminRequestVM.newsReportRequests.first(where: { $0.id == id }) { return .report(r) }
        if let r = adminRequestVM.phoneChangeRequests.first(where: { $0.id == id }) { return .phone(r) }
        if let m = pendingMembers.first(where: { $0.id == id }) { return .join(m) }
        return nil
    }

    /// «من أين وصل» لبطاقة — طلبات `admin_requests` والانضمام فقط (المحتوى بلا شريط)
    private func rowOrigin(_ id: UUID) -> AdminRequestOrigin? {
        rowDetail(id).flatMap(origin(for:))
    }

    /// صفّ `admin_requests` وراء التفصيل — للأعداد والطلبات المرتبطة والملاحظات
    private func adminRow(for detail: RequestDetail) -> (id: UUID, requester: UUID?, member: UUID)? {
        switch detail {
        case .report(let r), .nameChange(let r), .deceased(let r), .child(let r), .photo(let r): return (r.id, r.requesterId, r.memberId)
        case .treeEdit(let r, _):
            let target = r.treeEditPayload?.targetMemberId.flatMap(UUID.init(uuidString:)) ?? r.memberId
            return (r.id, r.requesterId, target)
        case .phone(let r): return (r.id, r.requesterId ?? r.memberId, r.memberId)
        case .join, .news, .diwaniya, .project, .archive: return nil
        }
    }

    /// الأقسام العلوية في التفاصيل: الحالة/المهلة/التنفيذ ← «البيانات المطلوبة» ← «فحص تلقائي»
    private func decisionAids(for detail: RequestDetail, index: Int) -> some View {
        let exec = execution(for: detail)
        let flow = approvalSnapshot(for: detail).map { adminRequestVM.liveApprovalSnapshot(requestId: $0.requestId) ?? $0 }
        let women = WomenStore.cache
        return AnyView(AdminRequestDecisionAids(
            state: flow == nil ? L10n.t("بانتظار القرار", "Awaiting a decision") : nil,
            sla: flow.flatMap(AdminRequestStatusText.sla),
            execution: exec,
            changes: AdminRequestInsights.changes(detail, men: memberVM.allMembers, women: women),
            checks: AdminRequestInsights.checks(detail, execution: exec, men: memberVM.allMembers, women: women),
            index: index))
    }

    /// الأقسام السفلية: «المرسل» بأعداد طلباته ← «من أين وصل» ← «سجل الطلب» ← «ملاحظات الإدارة» ← «طلبات مرتبطة».
    /// مع «مسار الموافقات» السجلّ والملاحظات في مربّع المسار نفسه فلا تتكرّر هنا
    private func contextPanel(for detail: RequestDetail, index: Int) -> some View {
        let row = adminRow(for: detail)
        let inFlow = approvalSnapshot(for: detail) != nil
        let sender = senderId(for: detail).flatMap { memberVM.member(byId: $0) }
        let record = requestRecord(for: detail)
        let isWomen: Bool = {
            if record?.from?.steps.first == .womenTree { return true }
            if case .treeEdit(let r, _) = detail {
                return r.treeEditPayload?.women != nil || WomenTreeRequestLines(r.treeEditPayload?.notes ?? "") != nil
            }
            return false
        }()
        let subject = isWomen ? nil : record?.subject.flatMap { memberVM.member(byId: $0) }
        let relation = sender.flatMap { s in subject.flatMap { AdminTrailText.relation(sender: s, subject: $0) } }
        let log: [DSPathStep]? = (inFlow || row == nil) ? nil : AdminRequestLog.steps(
            events: row.flatMap { handledStore.events[$0.id] }, requesterId: row?.requester,
            createdAt: record?.created, lookup: { memberVM.member(byId: $0) })
        let me = authVM.currentUser
        let ownRequest = me.map { $0.role != .owner && (row?.requester == $0.id || row?.member == $0.id) } ?? false
        let context = AdminRequestContext(requestId: row?.id, sender: sender, relation: relation, memberId: row?.member,
                                          senderInfo: senderInfo(for: detail), log: log,
                                          viewerCanModerate: authVM.canModerate, viewerId: me?.id)
        return AnyView(AdminRequestContextPanel(context: context, index: index) {
            // خارج المسار: ملاحظات الإدارة نفسها (`admin_request_notes`) — لا تظهر لصاحب الطلب أو المعني به (إلا المالك)
            if !inFlow, let id = row?.id, !ownRequest {
                ApprovalInternalNotes(adminRequestVM: adminRequestVM, memberVM: memberVM, requestId: id)
            }
        }
        .task(id: row?.id) {
            guard !inFlow, let id = row?.id else { return }
            if !ownRequest { await adminRequestVM.fetchApprovalNotes(for: id) }
            if handledStore.events[id] == nil { await handledStore.loadEvents(for: id) }
        })
    }

    /// «المرسل»: الخطوات (المسجّلة وإلا المستنتجة)، «الاسم الرباعي · الدور · الصلة»، الجهاز، الوقت
    private func senderInfo(for detail: RequestDetail) -> AdminSenderInfo {
        let record = requestRecord(for: detail)
        let steps = AdminTrailText.pathSteps(recorded: record?.from, inferred: requestSource(for: detail))
        var sender: String? = nil
        var senderMemberId: UUID? = nil
        if let id = senderId(for: detail), let member = memberVM.member(byId: id) {
            senderMemberId = member.id
            // صلته بالمعني — لا تُحسب لطلبات شجرة النساء (مرساتها ملفّ رجل لا المرأة نفسها)
            let women = (record?.from?.steps.first == .womenTree)
                || { if case .treeEdit(let r, _) = detail { return WomenTreeRequestLines(r.treeEditPayload?.notes ?? "") != nil }; return false }()
            let subject = women ? nil : record?.subject.flatMap { memberVM.member(byId: $0) }
            sender = [member.fourPartName, AdminTrailText.roleName(member.role), AdminTrailText.relation(sender: member, subject: subject)]
                .compactMap { $0 }.joined(separator: " · ")
        }
        let via = record?.via
        let time = DateHelper.displayDateTime(via?.at) ?? DateHelper.displayDateTime(record?.created) ?? AdminTrailText.notRecorded
        // طلب زوجة أو أم من شجرة النساء: الاسم المختار كاملاً في «المرسل» (طلب المالك ٢٠٢٦-١١-١٢)
        var chosen: WomenTreeRequestLines? = nil
        if case .treeEdit(let r, _) = detail, let lines = WomenTreeRequestLines(r.treeEditPayload?.notes ?? ""),
           lines.relation != nil {
            chosen = lines
        }
        return AdminSenderInfo(steps: steps, sender: sender, device: AdminTrailText.device(via),
                               deviceRecorded: via != nil, time: time,
                               chosenLabel: chosen?.chosenLabel, chosenName: chosen?.fullName,
                               senderId: senderMemberId)
    }

    /// معرّف مرسل الطلب
    private func senderId(for detail: RequestDetail) -> UUID? {
        switch detail {
        case .join(let m): return m.id
        case .news(let p): return p.ownerId
        case .report(let r), .nameChange(let r), .deceased(let r), .child(let r), .photo(let r):
            return r.requesterId
        case .treeEdit(let r, _): return r.requesterId
        case .phone(let r): return r.requesterId ?? r.memberId
        case .diwaniya(let d): return d.ownerId
        case .project(let p): return p.ownerId
        case .archive(let a): return a.uploadedBy
        }
    }

    /// من أين أُرسل الطلب — من نوعه وحمولته (يعمل للطلبات القديمة أيضاً، بلا تغيير في السيرفر)
    private func requestSource(for detail: RequestDetail) -> String {
        let arrow = L10n.t(" ← ", " → ")
        switch detail {
        case .join(let m):
            return m.registrationPlatform == "web" ? L10n.t("الموقع", "Website") + arrow + L10n.t("التسجيل", "Sign-up")
                                                   : L10n.t("التطبيق", "App") + arrow + L10n.t("التسجيل", "Sign-up")
        case .news: return L10n.t("الرئيسية", "Home") + arrow + L10n.t("خبر جديد", "New post")
        case .diwaniya: return L10n.t("الديوانيات", "Diwaniyas") + arrow + L10n.t("إضافة ديوانية", "Add diwaniya")
        case .project: return L10n.t("مشاريع العائلة", "Family projects") + arrow + L10n.t("إضافة مشروع", "Add project")
        case .archive: return L10n.t("مكتبة العائلة", "Family library") + arrow + L10n.t("رفع ملف", "Upload")
        case .phone: return L10n.t("الملف الشخصي", "Profile") + arrow + L10n.t("تغيير الرقم", "Change phone")
        case .nameChange: return L10n.t("الملف الشخصي", "Profile") + arrow + L10n.t("تعديل البيانات", "Edit details")
        case .child: return L10n.t("الملف الشخصي", "Profile") + arrow + L10n.t("الأسرة", "Family") + arrow + L10n.t("إضافة الأبناء", "Add children")
        case .deceased: return L10n.t("الشجرة", "Tree") + arrow + L10n.t("تفاصيل العضو", "Member details") + arrow + L10n.t("تسجيل وفاة", "Report death")
        case .photo: return L10n.t("الشجرة", "Tree") + arrow + L10n.t("تفاصيل العضو", "Member details") + arrow + L10n.t("اقتراح صورة", "Suggest photo")
        case .report(let r):
            switch r.requestType {
            case "news_report", "content_report":
                return L10n.t("الرئيسية", "Home") + arrow + L10n.t("بلاغ عن منشور", "Report a post")
            case RequestType.relativeAdd.rawValue:
                // «إضافة قريبة» من «الأسرة» (حسابي) أو «عائلتي» — بصلة القرابة
                let what = RelativeAddDetails.parse(r.details)?.requestTitle ?? L10n.t("طلب إضافة قريبة", "Add relative")
                return L10n.t("الملف الشخصي", "Profile") + arrow + L10n.t("الأسرة", "Family") + arrow + what
            case RequestType.accountDelete.rawValue:
                return L10n.t("الإعدادات", "Settings") + arrow + L10n.t("حذف الحساب", "Delete account")
            case RequestType.privacyRequest.rawValue:
                return L10n.t("الإعدادات", "Settings") + arrow + L10n.t("الخصوصية", "Privacy")
            default:
                return L10n.t("التواصل", "Contact") + arrow + L10n.t("رسالة للإدارة", "Message to admins")
            }
        case .treeEdit(let r, let action):
            let p = r.treeEditPayload
            if let notes = p?.notes, let women = WomenTreeRequestLines(notes) {
                // شجرة النساء: تفاصيل المرأة نفسها ← «طلب إضافة»
                let whom = women.forWhom.map { L10n.t("تفاصيل ", "Details of ") + $0 } ?? L10n.t("تفاصيل العضو", "Member details")
                // نوعه الحقيقي (تعديل اسم، حذف…) لا «إضافة» دائماً (٢٠٢٦-١١-١٨)
                let shown = p?.displayAction ?? action
                let what = shown == .add ? L10n.t("طلب إضافة", "Add request")
                    : L10n.t("طلب ", "") + L10n.t(shown.arabicLabel, shown.englishLabel)
                return L10n.t("شجرة النساء", "Women's tree") + arrow + whom + arrow + what
            }
            if let reason = p?.reason, reason.hasPrefix("profile_") {
                return L10n.t("الملف الشخصي", "Profile") + arrow + L10n.t("تعديل البيانات", "Edit details")
            }
            let whom = (p?.targetMemberName).map { L10n.t("تفاصيل ", "Details of ") + $0 } ?? L10n.t("تفاصيل العضو", "Member details")
            let what = action == .add ? L10n.t("طلب إضافة", "Add request") : L10n.t("طلب تعديل", "Edit request")
            return L10n.t("الشجرة", "Tree") + arrow + whom + arrow + what
        }
    }

    private func detailInfoTitle(_ detail: RequestDetail) -> String {
        return L10n.t("بيانات الطلب", "Request Info")
    }

    private func detailInfoIcon(_ detail: RequestDetail) -> String {
        return "doc.text.fill"
    }

    /// صورة الطلب (العضو، المشروع، الصورة المقترحة…) دائرية بمنتصف المربّع تحت الرأس
    private func detailHeroImage(url: URL, color: Color) -> some View {
        CachedAsyncImage(url: url) { img in
            img.resizable().scaledToFill()
        } placeholder: {
            Circle().fill(color.opacity(DS.Opacity.tintFill))
        }
        .frame(width: DS.Icon.photoPickerCompact, height: DS.Icon.photoPickerCompact)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(color.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.widthBold))
        .dsSubtleShadow()
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xs)
        .accessibilityHidden(true)   // صورة زخرفية فوق البيانات — الصورة المقترحة لها صفّها
    }

    /// العضو المعلّق الذي يُعدَّل رقمه — لطلبات الانضمام فقط ولمن يملك canModerate
    private func detailPhoneEditMember(_ detail: RequestDetail) -> FamilyMember? {
        guard authVM.canModerate, case .join(let member) = detail else { return nil }
        return member
    }

    /// metadata موحَّدة لكل نوع طلب — يُستخدم في hero + actions.
    private struct DetailMeta {
        let icon: String
        let color: Color
        let title: String
        let timestamp: String?
        /// صورة دائرية تظهر في الـ hero بدل الأيقونة (مثل صورة المشروع في صفحة المشاريع)
        var imageUrl: String? = nil
    }

    private func detailMeta(for detail: RequestDetail) -> DetailMeta {
        switch detail {
        case .join(let m):
            return .init(icon: "person.badge.shield.checkmark", color: DS.Color.info,
                         title: L10n.t("طلب انضمام", "Join Request"),
                         timestamp: m.createdAt.map { formatRegistrationDate($0) },
                         imageUrl: m.avatarUrl)
        case .news(let p):
            return .init(icon: "newspaper.fill", color: DS.Color.accent,
                         title: L10n.t("خبر بانتظار الاعتماد", "Pending News"),
                         timestamp: formatRegistrationDate(String(p.created_at)))
        case .report(let r):
            return .init(icon: "exclamationmark.triangle.fill", color: DS.Color.error,
                         title: L10n.t("بلاغ", "Report"),
                         timestamp: r.createdAt.map { formatRegistrationDate($0) })
        case .phone(let r):
            return .init(icon: "phone.arrow.right", color: AppSection.admin.ink,
                         title: L10n.t("تغيير رقم هاتف", "Phone Change"),
                         timestamp: r.createdAt.map { formatRegistrationDate($0) })
        case .nameChange(let r):
            return .init(icon: "rectangle.and.pencil.and.ellipsis", color: DS.Color.palm,
                         title: r.requestType == RequestType.familyChange.rawValue
                            ? L10n.t("تغيير العائلة", "Family Change") : L10n.t("تغيير اسم", "Name Change"),
                         timestamp: r.createdAt.map { formatRegistrationDate($0) })
        case .diwaniya:
            return .init(icon: "tent.fill", color: DS.Color.gridDiwaniya,
                         title: L10n.t("طلب ديوانية", "Diwaniya Request"),
                         timestamp: nil)
        case .deceased(let r):
            return .init(icon: "leaf.fill", color: DS.Color.slate,
                         title: L10n.t("تسجيل وفاة", "Deceased"),
                         timestamp: r.createdAt.map { formatRegistrationDate($0) })
        case .child(let r):
            return .init(icon: "person.badge.plus", color: DS.Color.info,
                         title: L10n.t("إضافة ابن", "Child Add"),
                         timestamp: r.createdAt.map { formatRegistrationDate($0) })
        case .photo(let r):
            return .init(icon: "camera.badge.ellipsis", color: DS.Color.neonBlue,
                         title: L10n.t("اقتراح صورة", "Photo Suggestion"),
                         timestamp: r.createdAt.map { formatRegistrationDate($0) },
                         imageUrl: r.newValue)
        case .project(let p):
            return .init(icon: "briefcase.fill", color: DS.Color.accent,
                         title: L10n.t("طلب مشروع", "Project Request"),
                         timestamp: p.createdAt.map { formatRegistrationDate($0) },
                         imageUrl: p.logoUrl)
        case .archive(let a):
            return .init(icon: a.categoryIcon, color: DS.Color.sadu,
                         title: L10n.t("عنصر أرشيف", "Archive Item"),
                         timestamp: nil,
                         imageUrl: a.thumbnailUrl)
        case .treeEdit(let request, let action):
            let shown = request.treeEditPayload?.displayAction ?? action
            return .init(icon: shown.iconName, color: treeEditColor(action),
                         // «طلب آخر» من تعديل الملف الشخصي يحمل عنوانه الحقيقي (تغيير الحالة الاجتماعية…)
                         title: Self.profileReasonTitle(request.treeEditPayload?.reason)
                             ?? L10n.t(shown.arabicLabel, shown.englishLabel),
                         timestamp: request.createdAt.map { formatRegistrationDate($0) },
                         imageUrl: request.member?.avatarUrl)
        }
    }

    /// المحتوى المخصّص لكل نوع — صفوف داخل قسم «بيانات الطلب».
    @ViewBuilder
    private func detailContent(for detail: RequestDetail) -> some View {
        switch detail {
        case .join(let member):
            infoCard(icon: "person.fill", label: L10n.t("الاسم الكامل", "Full Name"),
                     value: member.fullName, color: AppSection.admin.ink)
            if let phone = member.phoneNumber, !phone.isEmpty {
                infoCard(icon: "phone.fill", label: L10n.t("رقم الهاتف", "Phone"),
                         value: KuwaitPhone.display(phone), color: DS.Color.sea, whatsapp: phone)
            }
            if let birth = member.birthDate?.trimmingCharacters(in: .whitespacesAndNewlines), !birth.isEmpty {
                infoCard(icon: "calendar", label: L10n.t("تاريخ الميلاد", "Birth Date"),
                         value: DateHelper.displayDate(birth) ?? birth, color: DS.Color.palm)
            }
            if member.isFemale {
                infoCard(icon: "figure.stand.dress", label: L10n.t("الجنس", "Gender"),
                         value: L10n.t("أنثى — تُربط بشجرة النساء", "Female — belongs in the women's tree"),
                         color: DS.Color.female)
            }
            // طريقة التسجيل في سطر واحد: الموقع باسم دخول وكلمة مرور، والتطبيق برقم الجوال
            if member.registrationPlatform == "web" {
                let uname = member.username?.trimmingCharacters(in: .whitespaces) ?? ""
                infoCard(icon: "globe", label: L10n.t("التسجيل", "Signed up"),
                         value: uname.isEmpty
                            ? L10n.t("من الموقع", "Website")
                            : L10n.t("من الموقع · اسم الدخول: \(uname)", "Website · username: \(uname)"),
                         color: DS.Color.info)
            } else {
                infoCard(icon: "iphone", label: L10n.t("التسجيل", "Signed up"),
                         value: L10n.t("من التطبيق برقم الجوال", "App, with phone number"),
                         color: DS.Color.info)
            }
            if let created = member.createdAt {
                infoCard(icon: "clock.fill", label: L10n.t("وقت الطلب", "Requested"),
                         value: formatRegistrationDate(created), color: DS.Color.warning)
            }
            // «تعديل / إضافة رقم فعلي» انتقل إلى قسم «الإجراءات» (detailActionsSection)

        case .news(let post):
            infoCard(icon: "person.fill", label: L10n.t("الكاتب", "Author"),
                     value: memberVM.displayName(id: post.author_id, stored: post.author_name, .full),
                     color: AppSection.admin.ink)
            infoCard(icon: "tag.fill", label: L10n.t("النوع", "Type"),
                     value: post.type, color: newsTypeColor(post.type))
            longTextCard(icon: "text.alignleft",
                         label: L10n.t("المحتوى", "Content"),
                         text: post.content)
            if !post.mediaURLs.isEmpty {
                newsMediaGrid(urls: post.mediaURLs)
            }

        case .report(let request):
            infoCard(icon: "person.fill", label: L10n.t("مقدم البلاغ", "Reporter"),
                     value: request.member?.displayFullName ?? "—", color: AppSection.admin.ink, person: request.memberId)
            longTextCard(icon: "exclamationmark.bubble.fill",
                         label: L10n.t("التفاصيل", "Details"),
                         text: request.details ?? L10n.t("لا توجد تفاصيل", "No details"))

        case .phone(let request):
            // عن نفسه: «مقدّم الطلب · صاحب الشأن» أعلاه (§10 بلا تكرار)
            if request.requesterId != nil && request.requesterId != request.memberId {
                infoCard(icon: "person.fill", label: L10n.t("العضو", "Member"),
                         value: request.member?.displayFullName ?? "—", color: AppSection.admin.ink, person: request.memberId)
            }
            comparisonCard(
                oldLabel: L10n.t("الرقم الحالي", "Current"),
                oldValue: KuwaitPhone.display(request.member?.phoneNumber),
                newLabel: L10n.t("الرقم الجديد", "New"),
                newValue: KuwaitPhone.display(request.newValue),
                icon: "phone.fill",
                whatsapp: request.newValue
            )

        case .nameChange(let request):
            if request.requestType == RequestType.familyChange.rawValue {
                // تغيير العائلة: الاسم الكامل قبل/بعد — يتغيّر الاسم الأخير فقط
                let base = request.member?.fullName ?? "—"
                comparisonCard(
                    oldLabel: L10n.t("الاسم الحالي", "Current Name"),
                    oldValue: FamilyNameCatalog.words(base, family: request.member?.familyName).joined(separator: " "),
                    newLabel: L10n.t("بعد تغيير العائلة", "After family change"),
                    newValue: FamilyNameCatalog.words(base, family: request.newValue).joined(separator: " "),
                    icon: "person.2.fill"
                )
            } else {
                comparisonCard(
                    oldLabel: L10n.t("الاسم الحالي", "Current Name"),
                    oldValue: request.member?.fullName ?? "—",
                    newLabel: L10n.t("الاسم الجديد", "New Name"),
                    newValue: request.newValue ?? "—",
                    icon: "person.fill"
                )
            }

        case .diwaniya(let diwaniya):
            infoCard(icon: "tent.fill", label: L10n.t("اسم الديوانية", "Name"),
                     value: diwaniya.title, color: DS.Color.gridDiwaniya)
            infoCard(icon: "person.fill", label: L10n.t("صاحب الديوانية", "Owner"),
                     value: diwaniya.ownerName, color: AppSection.admin.ink)
            if let schedule = diwaniya.scheduleText, !schedule.isEmpty {
                infoCard(icon: "calendar", label: L10n.t("الموعد", "Schedule"),
                         value: schedule, color: DS.Color.info)
            }
            if let address = diwaniya.address, !address.isEmpty {
                infoCard(icon: "mappin.and.ellipse", label: L10n.t("العنوان", "Address"),
                         value: address, color: DS.Color.palm)
            }

        case .deceased(let request):
            infoCard(icon: "person.fill", label: L10n.t("العضو", "Member"),
                     value: request.member?.displayFullName ?? "—", color: AppSection.admin.ink, person: request.memberId)
            longTextCard(icon: "doc.text.fill",
                         label: L10n.t("التفاصيل", "Details"),
                         text: request.details ?? L10n.t("لا توجد تفاصيل", "No details"))

        case .child(let request):
            // «الأب» = «مقدّم الطلب» غالباً (§10 بلا تكرار)
            if request.requesterId != request.memberId {
                infoCard(icon: "person.fill", label: L10n.t("الأب", "Father"),
                         value: request.member?.displayFullName ?? "—", color: AppSection.admin.ink, person: request.memberId)
            }
            longTextCard(icon: "doc.text.fill",
                         label: L10n.t("التفاصيل", "Details"),
                         text: request.details ?? L10n.t("لا توجد تفاصيل", "No details"))

        case .photo(let request):
            infoCard(icon: "person.fill", label: L10n.t("العضو", "Member"),
                     value: request.member?.displayFullName ?? "—", color: AppSection.admin.ink, person: request.memberId)
            if !(request.details ?? "").isEmpty {
                longTextCard(icon: "text.bubble.fill",
                             label: L10n.t("ملاحظات", "Notes"),
                             text: request.details ?? "")
            }
            if let photoUrl = request.newValue, let url = URL(string: photoUrl) {
                photoCard(url: url)
            }

        case .project(let project):
            infoCard(icon: "briefcase.fill", label: L10n.t("اسم المشروع", "Project"),
                     value: project.title, color: DS.Color.accent)
            infoCard(icon: "person.fill", label: L10n.t("صاحب المشروع", "Owner"),
                     // صاحب فارغ = المُرسل ليس صاحبه — لا يُستبدل باسم المُرسل من معرّفه
                     value: project.ownerName.trimmingCharacters(in: .whitespaces).isEmpty
                         ? L10n.t("المُرسل ليس صاحبه — لم يُحدَّد", "Not the sender — not set")
                         : memberVM.displayName(id: project.ownerId, stored: project.ownerName, .full),
                     color: AppSection.admin.ink)
            if let desc = project.description, !desc.isEmpty {
                longTextCard(icon: "doc.text.fill",
                             label: L10n.t("الوصف", "Description"),
                             text: desc)
            }
            // روابط التواصل
            if let wa = project.whatsappNumber, !wa.isEmpty, let url = KuwaitPhone.whatsappURL(wa) {
                contactLinkCard(icon: "message.fill", label: L10n.t("واتساب", "WhatsApp"),
                                value: KuwaitPhone.display(wa), color: DS.Color.sea, url: url)
            }
            if let phone = project.phoneNumber, !phone.isEmpty, let url = KuwaitPhone.telURL(phone) {
                contactLinkCard(icon: "phone.fill", label: L10n.t("هاتف", "Phone"),
                                value: KuwaitPhone.display(phone), color: AppSection.admin.ink, url: url)
            }
            if let web = project.websiteUrl, !web.isEmpty,
               let url = URL(string: web.lowercased().hasPrefix("http") ? web : "https://\(web)") {
                contactLinkCard(icon: "globe", label: L10n.t("الموقع", "Website"),
                                value: web, color: DS.Color.info, url: url)
            }
            if let ig = project.instagramUrl, !ig.isEmpty, let url = socialURL(ig, base: "https://instagram.com/") {
                contactLinkCard(icon: "camera.fill", label: L10n.t("إنستغرام", "Instagram"),
                                value: ig, color: DS.Color.neonPink, url: url)
            }
            if let tw = project.twitterUrl, !tw.isEmpty, let url = socialURL(tw, base: "https://twitter.com/") {
                contactLinkCard(icon: "bird.fill", label: "X / Twitter",
                                value: tw, color: DS.Color.neonBlue, url: url)
            }
            if let sc = project.snapchatUrl, !sc.isEmpty, let url = socialURL(sc, base: "https://snapchat.com/add/") {
                contactLinkCard(icon: "camera.viewfinder", label: L10n.t("سناب شات", "Snapchat"),
                                value: sc, color: DS.Color.accent, url: url)
            }
            if let loc = project.locationUrl, !loc.isEmpty,
               let url = URL(string: loc.lowercased().hasPrefix("http") ? loc : "https://\(loc)") {
                contactLinkCard(icon: "mappin.and.ellipse", label: L10n.t("الموقع الجغرافي", "Location"),
                                value: L10n.t("فتح الخريطة", "Open map"), color: DS.Color.palm, url: url)
            }

        case .archive(let item):
            // نوع المحتوى ومعاينته قبل الموافقة (طلب المالك ٢٠٢٦-١١-٢٤ «ما يبين شنو نوع المحتوى قبل الموافقة»)
            AdminArchivePreviewCard(item: item)
            infoCard(icon: "textformat", label: L10n.t("العنوان", "Title"),
                     value: item.title, color: DS.Color.sadu)
            infoCard(icon: item.fileKindIcon, label: L10n.t("نوع المحتوى", "Content type"),
                     value: item.fileKindLine, color: DS.Color.sadu)
            infoCard(icon: item.categoryIcon, label: L10n.t("القسم", "Category"),
                     value: item.categoryDisplayName,
                     color: DS.Color.info)
            if let year = item.year {
                infoCard(icon: "calendar", label: L10n.t("السنة", "Year"),
                         value: "\(year)", color: AppSection.admin.ink)
            }
            if let desc = item.description, !desc.isEmpty {
                longTextCard(icon: "doc.text.fill",
                             label: L10n.t("الوصف", "Description"),
                             text: desc)
            }

        case .treeEdit(let request, let action):
            let payload = request.treeEditPayload
            let memberName = memberVM.treeEditTargetName(payload)
                ?? request.member?.displayFullName
                ?? L10n.t("عضو", "Member")
            // مقدّم الطلب هو العضو نفسه (مقارنة كمعرّفات — الآيفون يرسل حروفاً كبيرة) → يظهر مرة
            // واحدة بعنوان «صاحب الطلب» بدل «العضو» + «مقدّم التعديل» (طلب المالك ٢٠٢٦-١٠-٠٧)
            let targetId = payload?.targetMemberId.flatMap { UUID(uuidString: $0) } ?? request.memberId
            let selfRequest = targetId == request.requesterId
            let memberLabel = selfRequest ? L10n.t("صاحب الطلب", "Requester") : L10n.t("العضو", "Member")
            let showsMemberRow = action != .editName && action != .add
            switch action {
            case .editName:
                comparisonCard(
                    oldLabel: L10n.t("الاسم الحالي", "Current Name"),
                    oldValue: request.member?.fullName ?? memberName,
                    newLabel: L10n.t("الاسم الجديد", "New Name"),
                    newValue: payload?.newName ?? "—",
                    icon: "person.fill"
                )
            case .editPhone:
                infoCard(icon: "person.fill", label: memberLabel,
                         value: memberName, color: AppSection.admin.ink, person: targetId)
                comparisonCard(
                    oldLabel: L10n.t("الرقم الحالي", "Current"),
                    oldValue: KuwaitPhone.display(request.member?.phoneNumber),
                    newLabel: L10n.t("الرقم الجديد", "New"),
                    newValue: KuwaitPhone.display(payload?.newPhone),
                    icon: "phone.fill",
                    whatsapp: payload?.newPhone
                )
            case .deceased:
                infoCard(icon: "person.fill", label: memberLabel,
                         value: memberName, color: AppSection.admin.ink, person: targetId)
                if let death = payload?.deathDate, !death.isEmpty {
                    infoCard(icon: "calendar", label: L10n.t("تاريخ الوفاة", "Death Date"),
                             value: DateHelper.displayDate(death) ?? death, color: DS.Color.slate)
                }
            case .addDeathDate:
                infoCard(icon: "person.fill", label: memberLabel,
                         value: memberName, color: AppSection.admin.ink, person: targetId)
                if let death = payload?.deathDate, !death.isEmpty {
                    infoCard(icon: "calendar.badge.exclamationmark", label: L10n.t("تاريخ الوفاة", "Death Date"),
                             value: DateHelper.displayDate(death) ?? death, color: DS.Color.slate)
                }
            case .addPhoto:
                infoCard(icon: "person.fill", label: memberLabel,
                         value: memberName, color: AppSection.admin.ink, person: targetId)
                if let photoStr = payload?.newPhotoUrl, let url = URL(string: photoStr) {
                    photoCard(url: url)
                }
            case .add:
                // طلب من شجرة النساء: الطلب معلّق على أقرب سجلّ في الشجرة العامة (غالباً مقدّم الطلب)، فاسمه ليس
                // الاسم الجديد ولا الأب — الاسم ولمن من سطري «الاسم:» و«لـ:» في الملاحظات (كان يعرض «الاسم الجديد:
                // فيصل… · الأب: فيصل…» فقُبل طلبا ليلى وريم بلا إضافة، ٢٠٢٦-١١-١١)
                if let women = payload?.notes.flatMap(WomenTreeRequestLines.init) {
                    // التفاصيل كاملة (طلب المالك ٢٠٢٦-١١-١٢ «ابى في الوارد تفاصيل كاملة»): نوع الطلب · المختارة بنسبها ·
                    // عمرها وحالتها من شجرة النساء · أبوها · لمن · ما تفعله الإدارة
                    if let kind = women.kindText {
                        infoCard(icon: "list.bullet.rectangle", label: L10n.t("نوع الطلب", "Request type"),
                                 value: kind, color: AppSection.admin.ink)
                    }
                    infoCard(icon: "person.fill", label: women.chosenLabel,
                             value: women.fullName, color: DS.Color.female)
                    if let w = women.woman(in: WomenStore.cache) {
                        infoCard(icon: "info.circle.fill", label: L10n.t("عنها في الشجرة", "In the tree"),
                                 value: Self.womanFacts(w), color: DS.Color.female)
                    }
                    if let father = women.father {
                        infoCard(icon: "person.fill", label: L10n.t("أبوها", "Her father"),
                                 value: father, color: DS.Color.male)
                    }
                    if let forWhom = women.forWhom {
                        infoCard(icon: "person.2.fill",
                                 label: women.relation == .wife ? L10n.t("زوجةً لـ", "Wife of")
                                     : women.relation == .mother ? L10n.t("أمّاً لـ", "Mother of")
                                     : L10n.t("لـ (شجرة النساء)", "For (women's tree)"),
                                 value: forWhom, color: AppSection.admin.ink)
                    }
                    if let manual = women.manual {
                        DSNoteCard(L10n.t("المطلوب من الإدارة: ", "For the admins: ") + manual,
                                   icon: "hand.point.up.left.fill", tint: DS.Color.info)
                    }
                } else {
                    infoCard(icon: "person.fill", label: L10n.t("الاسم الجديد", "New Name"),
                             value: payload?.newMemberName ?? memberName, color: DS.Color.palm)
                    if let parent = payload?.parentMemberName, !parent.isEmpty {
                        infoCard(icon: "person.2.fill", label: L10n.t("الأب", "Father"),
                                 value: parent, color: AppSection.admin.ink)
                    }
                }
            case .delete:
                infoCard(icon: "person.fill", label: memberLabel,
                         value: memberName, color: DS.Color.error)
            case .editBirth:
                infoCard(icon: "person.fill", label: memberLabel,
                         value: memberName, color: AppSection.admin.ink, person: targetId)
                if let newDate = (payload?.newBirthDate ?? payload?.newName), !newDate.isEmpty {
                    infoCard(icon: "calendar", label: L10n.t("تاريخ الميلاد الجديد", "New Birth Date"),
                             value: newDate, color: DS.Color.palm)
                }
            case .other:
                infoCard(icon: "person.fill", label: memberLabel,
                         value: memberName, color: DS.Color.accent)
            }
            if !(selfRequest && showsMemberRow),
               let requester = memberVM.allMembers.first(where: { $0.id == request.requesterId }) {
                infoCard(icon: "person.crop.circle.badge.checkmark",
                         label: selfRequest ? L10n.t("صاحب الطلب", "Requester") : L10n.t("مقدّم التعديل", "Requested by"),
                         value: requester.displayFullName, color: DS.Color.info)
            }
            // سبب داخلي من تعديل الملف الشخصي (profile_marital…) لا يُعرض كما هو — عنوانه في رأس المربّع
            if let reason = payload?.reason, !reason.isEmpty, Self.profileReasonTitle(reason) == nil {
                longTextCard(icon: "text.bubble.fill",
                             label: L10n.t("السبب", "Reason"), text: reason)
            }
            if let raw = payload?.notes, !raw.isEmpty {
                // طلب شجرة النساء: ما عُرض بطاقاتٍ أعلاه لا يتكرّر هنا
                let notes = WomenTreeRequestLines(raw) != nil ? WomenTreeRequestLines.rest(raw) : raw
                // سطر «⚠︎ تنبيه للإدارة» يُعرض بطاقة تحذير بارزة أعلى الملاحظات (طلب المالك ٢٠٢٦-١١-١١:
                // أبناء امرأة بلا زوج مسجّل — تُضاف الإدارة الزوج أولاً)
                let split = notes.adminNoticeSplit
                ForEach(split.notices, id: \.self) { notice in
                    DSNoteCard(notice, icon: "exclamationmark.triangle.fill", tint: DS.Color.warning)
                }
                if !split.rest.isEmpty {
                    longTextCard(icon: "note.text",
                                 label: L10n.t("ملاحظات", "Notes"), text: split.rest)
                }
            }

        }
    }

    /// صف معلومة — في مربّع الطلب الجديد صفّ spec A.6 داخل بطاقة «التفاصيل»، وفي المربّع المعالَج الشكل السابق
    /// (`AdminDetailInfoRow` يقرأ `adminRequestBoxRows`). `whatsapp`: رقم هاتف ← «واتساب» في طرف الصف
    /// `person`: صفّ شخص (الأب، العضو) ‹ — يدفع ورقته داخل مكدس المربّع (في المعالَج بلا سهم)
    private func infoCard(icon: String, label: String, value: String, color: Color, whatsapp: String? = nil,
                          person: UUID? = nil) -> some View {
        let open: (() -> Void)? = person.flatMap { memberVM.member(byId: $0) }.map { m in { boxPush(.person(m.id)) } }
        return AdminDetailInfoRow(icon: icon, label: label, value: value, color: color, whatsapp: whatsapp, open: open)
            // حقل يصلح أن يكون جنب حقل آخر في المعالَج — الصور والأزرار والأقسام تبقى بعرض المربّع
            .layoutValue(key: AdminDetailPairable.self, value: whatsapp == nil)
    }

    /// صف رابط قابل للنقر — يفتح URL (واتساب/موقع/سوشال)
    private func contactLinkCard(icon: String, label: String, value: String, color: Color, url: URL) -> some View {
        AdminDetailLinkRow(icon: icon, label: label, value: value, color: color, url: url)
    }

    /// يبني رابط سوشال من handle (@user) أو URL كامل.
    private func socialURL(_ raw: String, base: String) -> URL? {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return nil }
        if v.lowercased().hasPrefix("http") { return URL(string: v) }
        let handle = v.hasPrefix("@") ? String(v.dropFirst()) : v
        return URL(string: base + handle)
    }

    /// صف نص طويل — العنوان ثم المحتوى متعدد الأسطر بعرض الصف
    private func longTextCard(icon: String, label: String, text: String) -> some View {
        AdminDetailLongTextRow(icon: icon, label: label, text: text)
    }

    /// صف مقارنة «قبل/بعد» — القديم مشطوب ← الجديد (تغييرات الاسم/الهاتف). `whatsapp`: الرقم الجديد ← «واتساب»
    private func comparisonCard(oldLabel: String, oldValue: String,
                                newLabel: String, newValue: String, icon: String,
                                whatsapp: String? = nil) -> some View {
        AdminDetailComparisonRow(oldLabel: oldLabel, oldValue: oldValue, newLabel: newLabel, newValue: newValue,
                                 icon: icon, whatsapp: whatsapp)
    }

    /// ارتفاع صورة الخبر في شبكة الصور
    private static let newsMediaTileHeight: CGFloat = 90

    /// صورة كبيرة (للصور المقترحة) بعرض الصف
    private func photoCard(url: URL) -> some View {
        AdminDetailPhotoRow(url: url)
    }

    // MARK: القرار في المربّع (U9): نفس النداءات، ثم الانتقال بعد نجاح مؤكَّد

    private var boxIsBusy: Bool {
        if case .busy = boxPhase { return true }
        return false
    }

    /// الطلب المعروض الآن بأحدث بياناته من القوائم (الانتقال يبدّله دون إغلاق المربّع)
    private func boxCurrent(_ presented: RequestDetail) -> RequestDetail {
        let shown = boxShown ?? presented
        return boxDetail(id: shown.id) ?? shown
    }

    private func boxDetail(id: String) -> RequestDetail? {
        for item in sortedAllItems {
            let d = requestDetail(for: item)
            if d.id == id { return d }
        }
        return nil
    }

    /// لقطة المسار الحيّة (بعد الاستلام أو تغيير الأولوية)
    private func liveFlow(_ detail: RequestDetail) -> ApprovalSnapshot? {
        approvalSnapshot(for: detail).map { adminRequestVM.liveApprovalSnapshot(requestId: $0.requestId) ?? $0 }
    }

    /// ترتيب القائمة كما تظهر الآن (الفلاتر والبحث والأيام) — معرّفات التفاصيل
    private func boxOrder() -> [String] {
        makeModel().days.flatMap(\.items).map { requestDetail(for: $0.item).id }
    }

    /// معرّف صفّ الطلب في القائمة (للانضمام: العضو المعلّق)
    private func boxRowId(_ detail: RequestDetail) -> UUID {
        switch detail {
        case .join(let m): return m.id
        case .news(let p): return p.id
        case .report(let r), .nameChange(let r), .deceased(let r), .child(let r), .photo(let r): return r.id
        case .treeEdit(let r, _): return r.id
        case .phone(let r): return r.id
        case .diwaniya(let d): return d.id
        case .project(let p): return p.id
        case .archive(let a): return a.id
        }
    }

    /// صفّ `admin_requests` وراء الطلب (لمعرفة من عالجه) — للانضمام صفّه في المسار إن وُجد
    private func boxAdminRequestId(_ detail: RequestDetail) -> UUID? {
        switch detail {
        case .join(let m): return adminRequestVM.joinApprovalRequests.first { $0.memberId == m.id }?.id
        case .report(let r), .nameChange(let r), .deceased(let r), .child(let r), .photo(let r): return r.id
        case .treeEdit(let r, _): return r.id
        case .phone(let r): return r.id
        case .news, .diwaniya, .project, .archive: return nil
        }
    }

    /// فُتح على الطلب المطلوب (`focusId` من الإشعار أو «اليوم»)؟ — مرة واحدة لكل فتح من هناك
    private func isFocusDetail(_ detail: RequestDetail) -> Bool {
        guard let focusId else { return false }
        let rowId = adminRequestVM.joinApprovalRequests.first(where: { $0.id == focusId })?.memberId ?? focusId
        return boxRowId(detail) == rowId
    }

    /// فتح المربّع: حال جديد، ومن أين فُتح، وجلب ما يُحمَّل للطلب (قراءة فقط)
    private func boxOpened(_ detail: RequestDetail) {
        boxShown = nil
        boxPhase = .idle
        boxNotice = nil
        boxLastError = nil
        boxPath = []
        boxNoteText = ""
        boxAskFields = []
        boxMergeMember = nil
        boxFromFocus = !boxFocusUsed && focusHandled && isFocusDetail(detail)
        if boxFromFocus { boxFocusUsed = true }
        Task { await boxLoad(detail) }
    }

    /// ما يحمّله الطلب عند ظهوره: خطوات المسار وملاحظاته والردود الجاهزة، أو ملاحظات الإدارة وسجلّ السيرفر
    private func boxLoad(_ detail: RequestDetail) async {
        InboxSeenStore.shared.markSeen(detail.id)
        if let flow = approvalSnapshot(for: detail) {
            await adminRequestVM.fetchApprovalSteps(for: flow.requestId)
            if !adminRequestVM.hidesApprovalNotes(flow) { await adminRequestVM.fetchApprovalNotes(for: flow.requestId) }
            await adminRequestVM.fetchApprovalTemplates()
        } else if let row = adminRow(for: detail) {
            if !boxIsOwnRow(row) { await adminRequestVM.fetchApprovalNotes(for: row.id) }
            if handledStore.events[row.id] == nil { await handledStore.loadEvents(for: row.id) }
        }
    }

    /// «إغلاق» — لا يُغلق وقرار يُرسل (مصيره غير معروف بعد)
    private func closeBox() {
        guard !boxIsBusy else { return }
        selectedDetail = nil
    }

    /// خطأ نموذج العرض أثناء فتح المربّع: يظهر سطراً فوق الشريط (لا تنبيه فوق المربّع)
    private func boxCaptureError(_ message: String?) {
        guard let message, selectedDetail != nil else { return }
        adminRequestVM.errorMessage = nil
        boxLastError = message
        if boxPhase == .idle {
            boxNotice = AdminBoxNotice(kind: .error, text: AdminRequestBoxLogic.failureLine(message, arabic: L10n.isArabic))
        }
    }

    /// سطر «الرد يتأخر…» بعد مهلة — الشريط يبقى معطّلاً حتى يصل الجواب ويُعاد جلب الطلب
    private func boxSlowTimer() -> Task<Void, Never> {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(AdminRequestBoxLogic.slowAfter * 1_000_000_000))
            guard !Task.isCancelled, boxIsBusy else { return }
            boxNotice = AdminBoxNotice(kind: .slow, text: AdminRequestBoxText.slow)
        }
    }

    private func boxOpenNote(_ purpose: AdminBoxNoteSpec.Purpose) {
        guard boxPhase == .idle else { return }
        boxNoteText = ""
        boxAskFields = []
        boxNotice = nil
        boxPath.append(.note(purpose))
    }

    /// تأكيد صفحة الملاحظة — كل غرض بنداء المسار نفسه (`advanceApproval`) أو مسار الرفض القديم
    private func boxConfirmNote(_ purpose: AdminBoxNoteSpec.Purpose, detail: RequestDetail) {
        let note = boxNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch purpose {
        case .recommendApprove: boxAdvance(detail, .recommendApprove, note: note, id: "recommendApprove")
        case .recommendReject: boxAdvance(detail, .recommendReject, note: note, id: "recommendReject")
        case .ask:
            boxAdvance(detail, .requestInfo, note: note, fields: ApprovalInfoField.askable.filter(boxAskFields.contains), id: "ask")
        case .approveNote: boxAdvance(detail, .approve, note: note, id: "approve")
        case .returnBack: boxAdvance(detail, .returnToSpecialist, note: note, id: "return")
        case .reject, .rejectFlow: boxDecide(detail, .reject(note.isEmpty ? nil : note), id: "reject")
        }
    }

    /// «الموافقة» بلا مسار / «تنفيذ» بالمسار — الانضمام: «ربط بالشجرة» يفتح المنتقي فوق «الوارد» بعد إغلاق المربّع
    private func boxApprove(_ detail: RequestDetail, execute: Bool) {
        if case .join(let member) = detail {
            guard boxPhase == .idle else { return }
            selectedDetail = nil
            // ورقة واحدة في المرة: المنتقي بعد نزول المربّع
            DispatchQueue.main.asyncAfter(deadline: .now() + AdminRequestBoxMetrics.sheetHandoff) { memberToLink = member }
            return
        }
        boxDecide(detail, execute ? .execute : .approve, id: execute ? "execute" : "approve")
    }

    /// خطوة المسار (`advance_admin_request`): توصية، سؤال العضو، اعتماد، إرجاع
    private func boxAdvance(_ detail: RequestDetail, _ action: ApprovalAction, note: String?,
                            fields: [ApprovalInfoField] = [], id: String) {
        guard boxPhase == .idle, let flow = liveFlow(detail) else { return }
        let order = boxOrder()
        let done: (toast: String?, spoken: String?) = {
            switch action {
            case .approve: return (L10n.t("تم الاعتماد", "Approved"), nil)
            case .recommendApprove, .recommendReject: return (nil, L10n.t("رُفع للمدير", "Sent to the manager"))
            case .requestInfo: return (nil, L10n.t("أُرسل للعضو", "Sent to the member"))
            case .returnToSpecialist: return (nil, L10n.t("أُرجع للمختص", "Returned to the specialist"))
            default: return (nil, nil)
            }
        }()
        boxNotice = nil
        boxLastError = nil
        if DebugAdminProbe.dryRun("inbox box \(action.rawValue) \(flow.requestId)") {
            boxFinish(detail, order: order, toast: done.toast, spoken: done.spoken)
            return
        }
        boxPhase = .busy(id)
        let slow = boxSlowTimer()
        Task {
            let error = await adminRequestVM.advanceApproval(flow, action: action, note: note, fields: fields)
            slow.cancel()
            if let error {
                await boxResolveFailure(detail, message: error, order: order)
            } else {
                boxFinish(detail, order: order, toast: done.toast, spoken: done.spoken)
            }
        }
    }

    /// قرار بمسار الموافقة/الرفض القديم — النجاح مؤكَّد من السيرفر (`awaitDecision`)، والمحتوى بعد إعادة جلبه
    private func boxDecide(_ detail: RequestDetail, _ decision: BoxDecision, id: String) {
        guard boxPhase == .idle else { return }
        let order = boxOrder()
        let done: (toast: String?, spoken: String?) = {
            switch decision {
            case .reject: return (nil, L10n.t("رُفض الطلب", "The request was rejected"))
            case .execute, .executeNow: return (L10n.t("تم التنفيذ", "Carried out"), nil)
            case .approve:
                if case .child = detail { return (L10n.t("تم التأكيد", "Confirmed"), nil) }
                return (L10n.t("تمت الموافقة", "Approved"), nil)
            }
        }()
        boxNotice = nil
        boxLastError = nil
        if DebugAdminProbe.dryRun("inbox box \(id) \(detail.id)") {
            boxFinish(detail, order: order, toast: done.toast, spoken: done.spoken)
            return
        }
        boxPhase = .busy(id)
        let slow = boxSlowTimer()
        Task {
            let ok: Bool
            if case .reject(let reason) = decision {
                ok = await boxRejectCall(detail, reason: reason)
            } else {
                ok = await boxApproveCall(detail)
            }
            slow.cancel()
            if ok {
                boxFinish(detail, order: order, toast: done.toast, spoken: done.spoken)
            } else {
                let message = boxLastError ?? adminRequestVM.errorMessage
                adminRequestVM.errorMessage = nil
                await boxResolveFailure(detail, message: message, order: order)
            }
        }
    }

    /// الموافقة: نفس نداءات `approveDetail` — `true` = طبّقها السيرفر فعلاً
    private func boxApproveCall(_ detail: RequestDetail) async -> Bool {
        switch detail {
        case .join:
            return false
        case .report(let r):
            await adminRequestVM.approveNewsReport(request: r)
            return await adminRequestVM.awaitDecision(r.id)
        case .phone(let r):
            await adminRequestVM.approvePhoneChangeRequest(request: r)
            return await adminRequestVM.awaitDecision(r.id)
        case .nameChange(let r):
            await adminRequestVM.approveNameChangeRequest(request: r)
            return await adminRequestVM.awaitDecision(r.id)
        case .deceased(let r):
            await adminRequestVM.approveDeceasedRequest(request: r)
            return await adminRequestVM.awaitDecision(r.id)
        case .child(let r):
            await adminRequestVM.acknowledgeChildAddRequest(request: r)
            return await adminRequestVM.awaitDecision(r.id)
        case .photo(let r):
            await adminRequestVM.approvePhotoSuggestion(request: r)
            return await adminRequestVM.awaitDecision(r.id)
        case .treeEdit(let r, _):
            await adminRequestVM.approveTreeEditRequest(request: r)
            return await adminRequestVM.awaitDecision(r.id)
        case .news(let post):
            await newsVM.approveNewsPost(postId: post.id)
            return await boxContentGone(detail)
        case .diwaniya(let diwaniya):
            guard let adminId = authVM.currentUser?.id else { return false }
            await diwaniyaVM.approveDiwaniya(id: diwaniya.id, adminId: adminId)
            return await boxContentGone(detail)
        case .project(let project):
            guard let adminId = authVM.currentUser?.id else { return false }
            await projectsVM.approveProject(id: project.id, approvedBy: adminId)
            return await boxContentGone(detail)
        case .archive(let item):
            await archiveVM.approveItem(item)
            return !boxStillPending(detail)
        }
    }

    /// الرفض: نفس نداءات `rejectDetail` (السبب يصل لصاحب الطلب) — `true` = طبّقه السيرفر فعلاً
    private func boxRejectCall(_ detail: RequestDetail, reason: String?) async -> Bool {
        switch detail {
        case .join(let member):
            return await adminRequestVM.rejectOrDeleteMember(memberId: member.id)
        case .report(let r):
            await adminRequestVM.rejectNewsReport(request: r)
            return await adminRequestVM.awaitDecision(r.id)
        case .phone(let r):
            await adminRequestVM.rejectPhoneChangeRequest(request: r, reason: reason)
            return await adminRequestVM.awaitDecision(r.id)
        case .nameChange(let r):
            await adminRequestVM.rejectNameChangeRequest(request: r, reason: reason)
            return await adminRequestVM.awaitDecision(r.id)
        case .deceased(let r):
            await adminRequestVM.rejectDeceasedRequest(request: r, reason: reason)
            return await adminRequestVM.awaitDecision(r.id)
        case .child(let r):
            await adminRequestVM.rejectChildAddRequest(request: r, reason: reason)
            return await adminRequestVM.awaitDecision(r.id)
        case .photo(let r):
            await adminRequestVM.rejectPhotoSuggestion(request: r, reason: reason)
            return await adminRequestVM.awaitDecision(r.id)
        case .treeEdit(let r, _):
            await adminRequestVM.rejectTreeEditRequest(request: r, reason: reason)
            return await adminRequestVM.awaitDecision(r.id)
        case .news(let post):
            await newsVM.rejectNewsPost(postId: post.id)
            return await boxContentGone(detail)
        case .diwaniya(let diwaniya):
            await diwaniyaVM.rejectDiwaniya(id: diwaniya.id)
            return await boxContentGone(detail)
        case .project(let project):
            await projectsVM.rejectProject(id: project.id)
            return await boxContentGone(detail)
        case .archive(let item):
            await archiveVM.rejectItem(item)
            return !boxStillPending(detail)
        }
    }

    /// المحتوى (أخبار، ديوانيات، مشاريع): نماذجها تُخفي العنصر فوراً ثم تكتب — النجاح = لم يعد معلّقاً بعد إعادة جلبه
    private func boxContentGone(_ detail: RequestDetail) async -> Bool {
        for wait in [AdminRequestBoxMetrics.contentSettle, AdminRequestBoxMetrics.contentRecheck] {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            await boxRefetch(detail)
            if !boxStillPending(detail) { return true }
        }
        return false
    }

    /// إعادة جلب قائمة الطلب وحدها (قراءة) — قبل أن تعود الأزرار بعد خطأ أو مهلة
    private func boxRefetch(_ detail: RequestDetail) async {
        switch detail {
        case .join:
            await memberVM.fetchAllMembers(force: true)
            await adminRequestVM.fetchJoinApprovalRequests()
        case .news: await newsVM.fetchPendingNewsRequests(force: true)
        case .report: await adminRequestVM.fetchNewsReportRequests(force: true)
        case .phone: await adminRequestVM.fetchPhoneChangeRequests(force: true)
        case .nameChange: await adminRequestVM.fetchNameChangeRequests(force: true)
        case .diwaniya: await diwaniyaVM.fetchPendingDiwaniyas()
        case .deceased: await adminRequestVM.fetchDeceasedRequests(force: true)
        case .child: await adminRequestVM.fetchChildAddRequests(force: true)
        case .photo: await adminRequestVM.fetchPhotoSuggestionRequests(force: true)
        case .project: await projectsVM.fetchPendingProjects()
        case .archive: await archiveVM.fetchItems()
        case .treeEdit: await adminRequestVM.fetchTreeEditRequests(force: true)
        }
    }

    /// ما زال معلّقاً في قائمته الآن؟
    private func boxStillPending(_ detail: RequestDetail) -> Bool {
        switch detail {
        case .join(let m): return memberVM.member(byId: m.id)?.role == .pending
        case .news(let p): return newsVM.pendingNewsRequests.contains { $0.id == p.id }
        case .report(let r): return adminRequestVM.newsReportRequests.contains { $0.id == r.id }
        case .phone(let r): return adminRequestVM.phoneChangeRequests.contains { $0.id == r.id }
        case .nameChange(let r): return adminRequestVM.nameChangeRequests.contains { $0.id == r.id }
        case .diwaniya(let d): return diwaniyaVM.pendingDiwaniyas.contains { $0.id == d.id }
        case .deceased(let r): return adminRequestVM.deceasedRequests.contains { $0.id == r.id }
        case .child(let r): return adminRequestVM.childAddRequests.contains { $0.id == r.id }
        case .photo(let r): return adminRequestVM.photoSuggestionRequests.contains { $0.id == r.id }
        case .project(let p): return projectsVM.pendingProjects.contains { $0.id == p.id }
        case .archive(let a): return pendingArchiveItems.contains { $0.id == a.id }
        case .treeEdit(let r, _): return adminRequestVM.treeEditRequests.contains { $0.id == r.id }
        }
    }

    /// القرار لم يُؤكَّد: يُعاد جلب الطلب أولاً (المهلة/الانقطاع — ربما نُفّذ)، ثم: باقٍ ← الرسالة والأزرار تعود؛ عالجه
    /// غيرك ← «عالجه فلان» ثم الانتقال؛ عالجته أنت فعلاً ← نجاح
    private func boxResolveFailure(_ detail: RequestDetail, message: String?, order: [String]) async {
        // بلا سبب معروف (مهلة، انقطاع): ربما أكمل السيرفر القرار بعد انقطاع الجواب — نمهله قليلاً ثم نجلب الطلب كما هو.
        // السبب المعروف (`not_allowed`، `phone_in_use`…) يُجلب فوراً: لم يُطبَّق شيء
        let generic = AdminRequestViewModel.decisionErrorMessage(URLError(.timedOut))
        if message == nil || message == generic {
            try? await Task.sleep(nanoseconds: UInt64(AdminRequestBoxMetrics.contentSettle * 1_000_000_000))
        }
        await boxRefetch(detail)
        let pending = boxStillPending(detail)
        var handlerName: String? = nil
        var decision: String? = nil
        var handlerIsMe = false
        if !pending, let id = boxAdminRequestId(detail) {
            await handledStore.reload()
            if let r = handledStore.items.first(where: { $0.id == id }) {
                await handledStore.loadEvents(for: id)
                let events = handledStore.events[id]
                let handler = AdminTrailText.handlerId(r, events: events)
                handlerIsMe = handler != nil && handler == authVM.currentUser?.id
                handlerName = AdminTrailText.person(handler, lookup: { memberVM.member(byId: $0) })
                decision = AdminTrailText.decision(r, events: events).title
            }
        }
        switch AdminRequestBoxLogic.outcome(succeeded: false, stillPending: pending, handlerIsMe: handlerIsMe) {
        case .failed:
            let text = AdminRequestBoxLogic.failureLine(message ?? "", arabic: L10n.isArabic)
            boxPhase = .idle
            boxNotice = AdminBoxNotice(kind: .error, text: text)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            UIAccessibility.post(notification: .announcement, argument: text)
        case .success:
            boxFinish(detail, order: order, toast: nil, spoken: nil)
        case .handledElsewhere:
            let text = AdminRequestBoxText.handledBy(handlerName, decision: decision)
            boxPhase = .handledElsewhere
            boxNotice = AdminBoxNotice(kind: .info, text: text)
            UIAccessibility.post(notification: .announcement, argument: text)
            try? await Task.sleep(nanoseconds: UInt64(AdminRequestBoxLogic.handledNotice * 1_000_000_000))
            boxFinish(detail, order: order, toast: nil, spoken: nil)
        }
    }

    /// بعد نجاح مؤكَّد: اللحظة، ثم من الإشعار يُغلق، ومن القائمة ينتقل للتالي المعلّق بالمعرّف أو ينتهي
    private func boxFinish(_ detail: RequestDetail, order: [String], toast: String?, spoken: String?) {
        if let toast {
            DSMomentToast.show(toast, moment: .approved)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if let spoken { UIAccessibility.post(notification: .announcement, argument: spoken) }
        }
        boxLastError = nil
        boxPath = []
        boxNoteText = ""
        boxAskFields = []
        if boxFromFocus {
            boxPhase = .idle
            boxNotice = nil
            selectedDetail = nil
            return
        }
        let pending = Set(boxOrder())
        guard let nextId = AdminRequestBoxLogic.next(after: detail.id, order: order, pending: pending),
              let next = boxDetail(id: nextId) else {
            let others = makeModel().entries.contains { requestDetail(for: $0.item).id != detail.id }
            let title = AdminRequestBoxLogic.endTitle(othersOutsideFilter: others, arabic: L10n.isArabic)
            boxNotice = nil
            withAnimation(reduceMotion ? nil : DS.Anim.snappy) { boxPhase = .finished(title) }
            DispatchQueue.main.asyncAfter(deadline: .now() + AdminRequestBoxLogic.minimumLock) {
                UIAccessibility.post(notification: .announcement, argument: title)
            }
            return
        }
        boxMove(to: next)
    }

    /// الانتقال للتالي: الشريط معطّل حتى يُحمَّل ولـ٠٫٨ ث على الأقل، ثم «الطلب التالي: …» للقارئ الصوتي
    private func boxMove(to next: RequestDetail) {
        boxNotice = nil
        boxPhase = .advancing
        withAnimation(reduceMotion ? nil : DS.Anim.snappy) { boxShown = next }
        let meta = detailMeta(for: next)
        let name = boxRequesterName(next, sender: senderId(for: next).flatMap { memberVM.member(byId: $0) }, meta: meta)
        Task {
            let started = Date()
            await boxLoad(next)
            let left = AdminRequestBoxLogic.minimumLock - Date().timeIntervalSince(started)
            if left > 0 { try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000)) }
            guard boxShown?.id == next.id, boxPhase == .advancing else { return }
            boxPhase = .idle
            UIAccessibility.post(notification: .announcement, argument: AdminRequestBoxText.nextRequest(name))
        }
    }

    /// «ربط» من المربّع انتهى: نجح ← كقرار مؤكَّد (ينتقل/يُغلق)، فشل ← رسالته في تنبيه الدمج نفسه
    private func boxMergeFinished(_ result: AdminRequestViewModel.MergeResult?) {
        guard let id = boxMergeMember, let result else { return }
        boxMergeMember = nil
        guard case .success = result, let shown = selectedDetail.map({ boxCurrent($0) }), case .join(let m) = shown,
              m.id == id else { return }
        boxFinish(shown, order: boxMergeOrder, toast: nil, spoken: L10n.t("تم الربط", "Linked"))
    }

    /// استلام/ترك/أولوية — خطوة إدارية، المربّع يبقى على الطلب
    private func boxHousekeeping(_ flow: ApprovalSnapshot, _ action: ApprovalAction) {
        guard boxPhase == .idle else { return }
        boxNotice = nil
        if DebugAdminProbe.dryRun("inbox box \(action.rawValue) \(flow.requestId)") {
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }
        boxPhase = .busy("menu")
        Task {
            let error = await adminRequestVM.advanceApproval(flow, action: action, note: nil)
            boxPhase = .idle
            if let error {
                boxNotice = AdminBoxNotice(kind: .error, text: AdminRequestBoxLogic.failureLine(error, arabic: L10n.isArabic))
            } else {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    /// «حذف الطلب» من «⋯» بعد التأكيد — نفس `hardDeleteDetail` (يُغلق المربّع بعده)
    private func boxDelete(_ detail: RequestDetail) {
        guard boxPhase == .idle else { return }
        if DebugAdminProbe.dryRun("inbox box delete \(detail.id)") {
            selectedDetail = nil
            return
        }
        boxPhase = .busy("delete")
        hardDeleteDetail(detail)
    }

    // MARK: المسارات السابقة (السحب والقائمة — نفس النداءات)

    private func approveLabelFor(_ detail: RequestDetail) -> String {
        switch detail {
        case .join(let m):
            return m.isFemale ? L10n.t("ربط بشجرة النساء", "Link to Women's Tree") : L10n.t("ربط بالشجرة", "Link to Tree")
        case .child:   return L10n.t("تأكيد", "Confirm")
        default:
            // «قبول وتنفيذ» حين ينفّذه السيرفر عند القبول (العيّنة ١٦) — والإجراء نفسه بلا تغيير
            return execution(for: detail) == .auto ? L10n.t("قبول وتنفيذ", "Approve & apply") : L10n.t("موافقة", "Approve")
        }
    }

    private func approveIconFor(_ detail: RequestDetail) -> String {
        switch detail {
        case .join: return "link.badge.plus"
        default:    return "checkmark"
        }
    }

    private func approveDetail(_ detail: RequestDetail) {
        if DebugAdminProbe.dryRun("inbox approve \(detail.id)") { return }
        // «لحظة نجاح» (الدفعة ١٠) بعد أن تنتهي الموافقة — إلا «ربط» طلب الانضمام (يفتح مربّع الربط)
        let title: String?
        switch detail {
        case .join:  title = nil
        case .child: title = L10n.t("تم التأكيد", "Confirmed")
        default:
            title = selectedFlowIsExecute(detail) ? L10n.t("تم التنفيذ", "Carried out") : L10n.t("تمت الموافقة", "Approved")
        }
        Task {
            switch detail {
            case .join(let member):
                await MainActor.run {
                    memberToLink = member
                    selectedDetail = nil
                }
            case .news(let post):
                await newsVM.approveNewsPost(postId: post.id)
                await MainActor.run { selectedDetail = nil }
            case .report(let request):
                await adminRequestVM.approveNewsReport(request: request)
                await MainActor.run { selectedDetail = nil }
            case .phone(let request):
                await adminRequestVM.approvePhoneChangeRequest(request: request)
                await MainActor.run { selectedDetail = nil }
            case .nameChange(let request):
                await adminRequestVM.approveNameChangeRequest(request: request)
                await MainActor.run { selectedDetail = nil }
            case .diwaniya(let diwaniya):
                if let adminId = authVM.currentUser?.id {
                    await diwaniyaVM.approveDiwaniya(id: diwaniya.id, adminId: adminId)
                }
                await MainActor.run { selectedDetail = nil }
            case .deceased(let request):
                await adminRequestVM.approveDeceasedRequest(request: request)
                await MainActor.run { selectedDetail = nil }
            case .child(let request):
                await adminRequestVM.acknowledgeChildAddRequest(request: request)
                await MainActor.run { selectedDetail = nil }
            case .photo(let request):
                await adminRequestVM.approvePhotoSuggestion(request: request)
                await MainActor.run { selectedDetail = nil }
            case .project(let project):
                if let adminId = authVM.currentUser?.id {
                    await projectsVM.approveProject(id: project.id, approvedBy: adminId)
                }
                await MainActor.run { selectedDetail = nil }
            case .archive(let item):
                await archiveVM.approveItem(item)
                await MainActor.run { selectedDetail = nil }
            case .treeEdit(let request, _):
                await adminRequestVM.approveTreeEditRequest(request: request)
                await MainActor.run { selectedDetail = nil }
            }
            if let title {
                await MainActor.run { AdminApprovalMoment.after(adminRequestVM, title: title) }
            }
        }
    }

    /// الطلب في مرحلة «التنفيذ» من مسار الموافقات (الموافقة عندها = التنفيذ)
    private func selectedFlowIsExecute(_ detail: RequestDetail) -> Bool {
        guard let id = UUID(uuidString: String(detail.id.split(separator: "-", maxSplits: 1).last ?? "")) else { return false }
        return adminRequestVM.approvalSnapshot(forRowId: id)?.stage == .execute
    }

    /// «حوّل للمدير» — إشعار الإدارة الموجود (`notifyAdminsWithPush`) بمعرّف العضو المعلّق، فزرّه «مراجعة» في
    /// «إشعارات الإدارة» يفتح طلبه في «الوارد» ما دام معلّقاً. لا تغيير على الطلب نفسه
    private func forwardJoin(_ member: FamilyMember, note: String) {
        Task {
            if await adminRequestVM.forwardJoinToManager(member: member, note: note) {
                selectedDetail = nil
                forwardJoinDone = true
            }
        }
    }

    private func rejectDetail(_ detail: RequestDetail, reason: String? = nil) {
        Task {
            // سبب الرفض (مُهذّب) يُمرَّر لإشعار صاحب الطلب في كل الأنواع.
            let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            let r: String? = (trimmedReason?.isEmpty == false) ? trimmedReason : nil
            switch detail {
            case .join(let member):
                await adminRequestVM.rejectOrDeleteMember(memberId: member.id)
            case .news(let post):
                await newsVM.rejectNewsPost(postId: post.id)
            case .report(let request):
                await adminRequestVM.rejectNewsReport(request: request)
            case .phone(let request):
                await adminRequestVM.rejectPhoneChangeRequest(request: request, reason: r)
            case .nameChange(let request):
                await adminRequestVM.rejectNameChangeRequest(request: request, reason: r)
            case .diwaniya(let diwaniya):
                await diwaniyaVM.rejectDiwaniya(id: diwaniya.id)
            case .deceased(let request):
                await adminRequestVM.rejectDeceasedRequest(request: request, reason: r)
            case .child(let request):
                await adminRequestVM.rejectChildAddRequest(request: request, reason: r)
            case .photo(let request):
                await adminRequestVM.rejectPhotoSuggestion(request: request, reason: r)
            case .project(let project):
                await projectsVM.rejectProject(id: project.id)
            case .archive(let item):
                await archiveVM.rejectItem(item)
            case .treeEdit(let request, _):
                await adminRequestVM.rejectTreeEditRequest(request: request, reason: r)
            }
            await MainActor.run { selectedDetail = nil }
        }
    }

    /// حذف نهائي لأي طلب — يمسح العنصر كلياً من قاعدة البيانات (مختلف عن «رفض»).
    private func hardDeleteDetail(_ detail: RequestDetail) {
        Task {
            switch detail {
            case .join(let member):
                await adminRequestVM.rejectOrDeleteMember(memberId: member.id)
            case .news(let post):
                await newsVM.deleteNewsPost(postId: post.id)
            case .report(let request):
                await adminRequestVM.deleteAdminRequestRow(requestId: request.id)
            case .phone(let request):
                await adminRequestVM.deleteAdminRequestRow(requestId: request.id)
            case .nameChange(let request):
                await adminRequestVM.deleteAdminRequestRow(requestId: request.id)
            case .diwaniya(let diwaniya):
                await diwaniyaVM.deleteDiwaniya(id: diwaniya.id)
            case .deceased(let request):
                await adminRequestVM.deleteAdminRequestRow(requestId: request.id)
            case .child(let request):
                await adminRequestVM.deleteAdminRequestRow(requestId: request.id)
            case .photo(let request):
                await adminRequestVM.deleteAdminRequestRow(requestId: request.id)
            case .project(let project):
                await projectsVM.deleteProject(id: project.id)
            case .archive(let item):
                await archiveVM.deleteItem(item)
            case .treeEdit(let request, _):
                await adminRequestVM.deleteAdminRequestRow(requestId: request.id)
            }
            await MainActor.run { selectedDetail = nil }
        }
    }

    // (المساعدات القديمة detailHeader / detailActions / detailField / detailFullText حُذفت — بلا مرجع)

    /// صور الخبر داخل «بيانات الطلب» — صفوف عادية لا LazyVGrid (الشبكة الكسولة
    /// تُبلِّغ ارتفاعاً ناقصاً داخل المربّع فيُقصّ آخر صف)
    private func newsMediaGrid(urls: [String]) -> some View {
        let items = urls.compactMap { URL(string: $0) }
        let columns = 3
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "photo.on.rectangle", tint: DS.Color.accent)
                    .accessibilityHidden(true)
                Text(L10n.t("الصور", "Images"))
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                Spacer(minLength: 0)
            }
            VStack(spacing: DS.Spacing.sm) {
                ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { start in
                    let end = min(start + columns, items.count)
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(start..<end, id: \.self) { index in
                            newsMediaTile(items[index])
                        }
                        ForEach(0..<(columns - (end - start)), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
            }
        }
        .dsRowBox()
    }

    private func newsMediaTile(_ url: URL) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: Self.newsMediaTileHeight)
            .overlay(
                CachedAsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(DS.Color.surface)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.t("صورة الخبر", "News image"))
            .accessibilityAddTraits(.isImage)
    }

    private func newsTypeColor(_ type: String) -> Color {
        switch type {
        case "وفاة": return DS.Color.newsDeath
        case "زواج": return DS.Color.newsWedding
        case "مولود": return DS.Color.newsBirth
        case "تصويت": return DS.Color.newsVote
        case "إعلان": return DS.Color.newsAnnouncement
        case "تهنئة": return DS.Color.newsCongrats
        case "تذكير": return DS.Color.newsReminder
        case "دعوة": return DS.Color.newsInvitation
        default: return AppSection.admin.ink
        }
    }
}

/// سحب بطاقة الطلب («الوارد» — لمسة «ب» مثل البريد): من الطرف «رفض» (لمن يملكه) + «المزيد» (التفاصيل)،
/// ومن البداية الموافقة + «حذف نهائي» (للمالك/المدير) — نفس الاستدعاءات والصلاحيات السابقة
private struct RequestSwipeActions: ViewModifier {
    let enabled: Bool
    let approve: (() -> Void)?
    let approveLabel: String
    let approveIcon: String
    let approveColor: Color
    let reject: (() -> Void)?
    let delete: (() -> Void)?
    let more: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if let reject {
                        Button(action: reject) {
                            Label(L10n.t("رفض", "Reject"), systemImage: "xmark")
                        }
                        .tint(DS.Color.reject)
                    }
                    Button(action: more) {
                        Label(L10n.t("المزيد", "More"), systemImage: "ellipsis")
                    }
                    .tint(DS.Color.slateFill)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if let approve {
                        Button(action: approve) {
                            Label(approveLabel, systemImage: approveIcon)
                        }
                        .tint(approveColor)
                    }
                    if let delete {
                        Button(role: .destructive, action: delete) {
                            Label(L10n.t("حذف", "Delete"), systemImage: "trash.fill")
                        }
                        .tint(DS.Color.error)
                    }
                }
        } else {
            content
        }
    }
}

/// الضغط المطوّل على صفّ الطلب: نفس إجراءات السحب (spec A.15 — للسحب بديل بالضغط) — لا شيء في وضع التحديد
private struct RequestRowMenu: ViewModifier {
    struct Item: Identifiable {
        let id: String
        let title: String
        let icon: String
        let destructive: Bool
        let run: () -> Void
    }

    let actions: [Item]

    @ViewBuilder
    func body(content: Content) -> some View {
        if actions.isEmpty {
            content
        } else {
            content.contextMenu {
                ForEach(actions) { item in
                    Button(role: item.destructive ? .destructive : nil, action: item.run) {
                        Label(item.title, systemImage: item.icon)
                    }
                }
            }
        }
    }
}

// MARK: - تنبيه إداري داخل ملاحظات الطلب

extension String {
    /// أسطر تبدأ بـ«⚠︎» = تنبيهات للإدارة تُعرض بارزة، والباقي ملاحظات عادية
    var adminNoticeSplit: (notices: [String], rest: String) {
        var notices: [String] = []
        var rest: [String] = []
        for line in components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("⚠︎") || trimmed.hasPrefix("⚠") {
                let body = trimmed.drop { $0 == "⚠" || $0 == "\u{FE0E}" || $0 == "\u{FE0F}" || $0 == " " }
                notices.append(String(body))
            } else {
                rest.append(line)
            }
        }
        return (notices, rest.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}


/// سطور طلب «شجرة النساء» في الملاحظات: «الاسم: …» و«لـ: …» (يكتبها `WomanDetailSheet.requestPayload`)
struct WomenTreeRequestLines {
    /// الاسم كما في الطلب
    let name: String
    let forWhom: String?
    /// «أبوها: …» / «أبوها في الشجرة: …» — طلبات الزوجة والأم من العائلة
    let father: String?
    /// زوجة أو أم (من سطر العنوان «شجرة النساء — طلب ربط زوجة» …) — nil = غيرهما
    let relation: Relation?
    /// عنوان الطلب بعد «شجرة النساء — » («طلب ربط زوجة» …)
    let kindTitle: String?
    /// «التنفيذ يدوي: …» — ما تفعله الإدارة
    let manual: String?

    /// الأسطر التي تُعرض بطاقاتٍ (لا تتكرّر في «ملاحظات»)
    private static let shownPrefixes = ["شجرة النساء", "Women's tree", "الاسم:", "Name:", "لـ:", "For:",
                                        "أبوها في الشجرة:", "أبوها:", "Her father in the tree:", "Her father:",
                                        "التنفيذ يدوي:", "Manual:"]

    /// الملاحظات بلا الأسطر المعروضة بطاقاتٍ — «ملاحظات: …» تبقى نصّها فقط
    static func rest(_ notes: String) -> String {
        notes.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in !line.isEmpty && !shownPrefixes.contains(where: { line.hasPrefix($0) }) }
            .map { line in
                for p in ["ملاحظات:", "Notes:"] where line.hasPrefix(p) {
                    return line.dropFirst(p.count).trimmingCharacters(in: .whitespaces)
                }
                return line
            }
            .joined(separator: "\n")
    }

    /// شرح نوع الطلب بلغة واضحة
    var kindText: String? {
        guard let kindTitle else { return nil }
        let what = relation == .mother ? L10n.t("أمّاً", "as mother") : L10n.t("زوجةً", "as wife")
        if relation != nil && kindTitle.contains("ربط") {
            return L10n.t("بنت موجودة في الشجرة تُربط ", "An existing daughter, linked ") + what
        }
        if relation != nil && kindTitle.contains("من العائلة") {
            return L10n.t("بنت جديدة تُضاف تحت أبيها ثم تُربط ", "A new daughter added under her father, then linked ") + what
        }
        return kindTitle
    }

    /// المختارة نفسها في شجرة النساء (اسمها الأول + أبوها) — لعمرها وحالتها
    func woman(in people: [FamilyMember]) -> FamilyMember? {
        guard relation != nil, let father, let first = name.split(separator: " ").first else { return nil }
        let byId = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return people.first { w in
            guard w.isFemale, String(w.firstName.split(separator: " ").first ?? "") == first,
                  let f = w.fatherId.flatMap({ byId[$0] }) else { return false }
            return (f.fullName.isEmpty ? f.firstName : f.displayFullName) == father
        }
    }

    enum Relation { case wife, mother }

    init?(_ notes: String) {
        let lines = notes.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let head = lines.first(where: { $0.hasPrefix("شجرة النساء") || $0.hasPrefix("Women's tree") }) else { return nil }
        func value(_ prefixes: [String]) -> String? {
            for line in lines {
                for p in prefixes where line.hasPrefix(p) {
                    let v = line.dropFirst(p.count).trimmingCharacters(in: .whitespaces)
                    if !v.isEmpty { return v }
                }
            }
            return nil
        }
        guard let name = value(["الاسم:", "Name:"]) else { return nil }
        self.name = name
        self.forWhom = value(["لـ:", "For:"])
        self.father = value(["أبوها في الشجرة:", "أبوها:", "Her father in the tree:", "Her father:"])
        if head.contains("زوجة") || head.lowercased().contains("wife") { relation = .wife }
        else if head.contains(" أم") || head.lowercased().contains("mother") { relation = .mother }
        else { relation = nil }
        let dash = head.components(separatedBy: "— ")
        kindTitle = dash.count > 1 ? dash.dropFirst().joined(separator: "— ").trimmingCharacters(in: .whitespaces) : nil
        manual = value(["التنفيذ يدوي:", "Manual:"])
    }

    /// الاسم المختار كاملاً (طلب المالك ٢٠٢٦-١١-١٢): بنت الشجرة اسمها غالباً الأول وحده («فاطمة») —
    /// يُكمَل باسم أبيها الكامل «فاطمة علي حسين … المحمدعلي». الاسم الأطول من نسب أبيها يبقى كما هو.
    var fullName: String {
        guard let father, !father.isEmpty else { return name }
        let words = name.split(separator: " ")
        guard let first = words.first, words.count <= father.split(separator: " ").count else { return name }
        return "\(first) \(father)"
    }

    /// عنوان الاسم في الطلب: «الزوجة المختارة» / «الأم المختارة» / «الاسم الجديد»
    var chosenLabel: String {
        switch relation {
        case .wife: return L10n.t("الزوجة المختارة", "Chosen wife")
        case .mother: return L10n.t("الأم المختارة", "Chosen mother")
        case nil: return L10n.t("الاسم الجديد", "New Name")
        }
    }
}


// MARK: - «المنجز»: مربّع الطلب المعالَج (طلب المالك ٢٠٢٦-١١-١١ «قسم واضح ودقيق: شنو كل طلب صار فيه ومن سواه من الإدارة»)
// القائمة صارت صفحة (`AdminInboxHandledPage`)؛ المربّع يُبنى هنا لأنه نفس محتوى مربّع «الطلبات» (منطقة U9)

extension AdminAllRequestsView {
    /// التفصيل المقابل لصفّ معالَج — نفس محتوى مربّع «الطلبات»
    private func handledDetail(for r: AdminRequest) -> RequestDetail? {
        switch r.requestType {
        case RequestType.joinRequest.rawValue, RequestType.linkRequest.rawValue:
            return (r.member ?? memberVM.member(byId: r.memberId)).map { .join($0) }
        case RequestType.nameChange.rawValue, RequestType.familyChange.rawValue: return .nameChange(r)
        case RequestType.deceasedReport.rawValue: return .deceased(r)
        case RequestType.childAdd.rawValue: return .child(r)
        case RequestType.photoSuggestion.rawValue: return .photo(r)
        case RequestType.treeEdit.rawValue: return .treeEdit(r, r.treeEditPayload?.resolvedAction ?? .other)
        case RequestType.newsReport.rawValue, RequestType.contentReport.rawValue, "contact_message": return .report(r)
        case RequestType.phoneChange.rawValue:
            guard let data = try? JSONEncoder().encode(r),
                  let phone = try? JSONDecoder().decode(PhoneChangeRequest.self, from: data) else { return nil }
            return .phone(phone)
        default: return nil
        }
    }

    /// المربّع للعرض فقط: «بيانات الطلب» ← «المرسل» ← «ما تم في الطلب» ← «النتيجة»، و«إغلاق» وحده
    func handledBox(_ request: AdminRequest, onClose: @escaping () -> Void) -> some View {
        let events = handledStore.events[request.id]
        let decision = AdminTrailText.decision(request, events: events)
        let when = DateHelper.displayDateTime(AdminTrailText.handledAt(request, events: events))
        let detail = handledDetail(for: request)
        return DSComposer(
            title: AdminTrailText.typeTitle(request),
            subtitle: decision.title + (when.map { " · " + $0 } ?? ""),
            icon: AdminTrailText.typeIcon(request),
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: onClose
        ) {
            if let detail {
                genericDetailBoxContent(detail, meta: detailMeta(for: detail), handled: request)
            } else {
                handledFallbackInfo(request)
                // «مكانه في الشجرة» (§8) — إضافة قريبة، النسب، الخصوصية، حذف الحساب
                if let place = handledPlace(request) {
                    AnyView(TreePlaceSection(place: place, index: 2, men: memberVM.allMembers))
                }
                AdminSenderSection(info: senderInfo(for: .report(request)), index: 2)
            }
            AdminHandlingSections(request: request, events: events, lookup: { memberVM.member(byId: $0) }, startIndex: 3,
                                  link: joinLink(request))
        }
        .task(id: request.id) { await handledStore.loadEvents(for: request.id) }
    }

    /// «رُبط بـ: …» — مكان الحساب في شجرة العائلة، أو عقدة شجرة النساء المربوطة به
    private func joinLink(_ request: AdminRequest) -> String? {
        AdminTrailText.joinLink(request, member: memberVM.member(byId: request.memberId) ?? request.member,
                                womenName: handledStore.womenLinks[request.memberId])
    }

    /// «بيانات الطلب» للأنواع بلا مربّع خاص (حذف الحساب، الخصوصية، إضافة قريبة، النسب…)
    @ViewBuilder
    private func handledFallbackInfo(_ request: AdminRequest) -> some View {
        DSComposerSection(title: L10n.t("بيانات الطلب", "Request Info"), icon: "doc.text.fill",
                          tint: AppSection.admin.ink, index: 1) {
            // §10: «نوع الطلب» · «القرابة» · «مقدّم الطلب» أولاً، بلا تكرار «النوع»/«لمن»/«صلة القرابة»
            let facts = AdminRequestFacts.of(request, member: { memberVM.member(byId: $0) })
            if let facts { AdminRequestFactRows(facts: facts) }
            let relativeName: String? = {
                switch request.requestType {
                case RequestType.relativeAdd.rawValue:
                    let n = RelativeAddDetails.parse(request.details)?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return n.isEmpty ? "—" : n
                case RequestType.relativeRemove.rawValue:
                    return RelativeRemoveDetails.parse(request.details)?.trimmedName ?? "—"
                default:
                    return nil
                }
            }()
            if let relativeName {
                DSTileGrid([.wide(DSFieldTileFace(label: L10n.t("الاسم", "Name"), value: relativeName, glyph: .none))])
            } else if facts == nil || request.requesterId != request.memberId {
                DSTileGrid([
                    .wide(DSFieldTileFace(label: L10n.t("المعني بالطلب", "About"),
                                          value: request.member?.fourPartName ?? memberVM.member(byId: request.memberId)?.fourPartName ?? "—",
                                          glyph: .none)),
                ])
            }
            if let details = request.details?.trimmingCharacters(in: .whitespacesAndNewlines), !details.isEmpty,
               !details.hasPrefix("{") {
                Text(details)
                    .dsFieldFont(.fieldValue)
                    .foregroundColor(DS.Color.tileValue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dsRowBox()
            }
        }
    }
}

// MARK: - معاينة عنصر المكتبة قبل الموافقة

/// معاينة عنصر المكتبة في تفاصيل «الوارد» (طلب المالك ٢٠٢٦-١١-٢٤ «وصلني بالمكتبة بس ما يبين شنو نوع المحتوى قبل
/// الموافقة»): الصورة نفسها أو الصفحة الأولى من الـPDF إن وُجدت مصغّرتها، وزرّ «عرض المحتوى» يفتحه بالعارض نفسه
/// في المكتبة (`ProjectPhotoViewer` للصورة، `ArchivePDFReader` للـPDF). الإدارة لا تُحجب عنها لقطة الشاشة
private struct AdminArchivePreviewCard: View {
    let item: ArchiveItem
    @State private var showImage = false
    @State private var showReader = false

    private var previewURL: URL? {
        if item.isImage { return URL(string: item.fileUrl) }
        return item.thumbnailUrl.flatMap { URL(string: $0) }
    }

    private var canOpen: Bool { (item.isImage || item.isPDF) && URL(string: item.fileUrl) != nil }

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            if let u = previewURL {
                CachedAsyncImage(url: u) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.cardBackgroundSoft)
                        .frame(height: 140)
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { open() }
                .accessibilityLabel(L10n.t("معاينة \(item.fileKindName)", "Preview of \(item.fileKindName)"))
                .accessibilityAddTraits(.isButton)
            } else {
                // بلا معاينة (PDF بلا مصغّرة): رمز النوع كبيراً مع اسمه
                VStack(spacing: DS.Spacing.xs) {
                    Image(systemName: item.fileKindIcon)
                        .dsGlyph(DS.Glyph.xxl)
                        .foregroundColor(DS.Color.sadu)
                    Text(verbatim: item.fileKindLine)
                        .dsFont(.label)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 96)
                .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Color.cardBackgroundSoft))
                .accessibilityElement(children: .combine)
            }
            if canOpen {
                DSButton(item.isPDF ? L10n.t("فتح الملف", "Open file") : L10n.t("عرض الصورة", "View image"),
                         icon: item.isPDF ? "doc.text.magnifyingglass" : "photo",
                         tint: DS.Color.sadu) { open() }
            }
        }
        .fullScreenCover(isPresented: $showImage) {
            ProjectPhotoViewer(urls: [item.fileUrl], startIndex: 0, section: .library, shielded: false)
        }
        .fullScreenCover(isPresented: $showReader) {
            if let url = URL(string: item.fileUrl) {
                ArchivePDFReader(url: url, title: item.title, shielded: false)
            }
        }
    }

    private func open() {
        if item.isImage { showImage = true } else if item.isPDF { showReader = true }
    }
}

// MARK: - الحقول القصيرة جنب بعض

/// حقل معلومة (`infoCard` بلا زرّ واتساب) — وحده يدخل الأزواج؛ غيره بعرض المربّع دائماً
nonisolated private struct AdminDetailPairable: LayoutValueKey {
    static let defaultValue = false
}

/// تفاصيل الطلب في «الوارد» (طلب المالك ٢٠٢٦-١١-٢٤ «اذا كان النص صغير خلهم جنب بعض»): كل حقلين متتاليين
/// قصيرين — عرضه الطبيعي يكفيه نصف السطر — في صفّ واحد بعرضين متساويين وطول واحد، والطويل (الاسم الكامل، الرقم
/// مع واتساب، الوصف، الصور) بعرض المربّع. يكبر الخط (أحجام إمكانية الوصول) ← تقلّ الأزواج تلقائياً
private struct AdminDetailPairLayout: Layout {
    var spacing: CGFloat

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[Int]] {
        let half = (width - spacing) / 2
        func short(_ i: Int) -> Bool {
            subviews[i][AdminDetailPairable.self] && subviews[i].sizeThatFits(.unspecified).width <= half
        }
        var out: [[Int]] = []
        var i = 0
        while i < subviews.count {
            if i + 1 < subviews.count, short(i), short(i + 1) {
                out.append([i, i + 1]); i += 2
            } else {
                out.append([i]); i += 1
            }
        }
        return out
    }

    private func rowHeight(_ row: [Int], _ subviews: Subviews, width: CGFloat) -> CGFloat {
        let w = row.count == 2 ? (width - spacing) / 2 : width
        return row.map { subviews[$0].sizeThatFits(ProposedViewSize(width: w, height: nil)).height }.max() ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let rs = rows(subviews, width: width)
        let heights = rs.map { rowHeight($0, subviews, width: width) }
        let total = heights.reduce(0, +) + spacing * CGFloat(max(0, rs.count - 1))
        return CGSize(width: width, height: total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            let w = row.count == 2 ? (bounds.width - spacing) / 2 : bounds.width
            let h = rowHeight(row, subviews, width: bounds.width)
            for (k, idx) in row.enumerated() {
                subviews[idx].place(at: CGPoint(x: bounds.minX + CGFloat(k) * (w + spacing), y: y),
                                    anchor: .topLeading, proposal: ProposedViewSize(width: w, height: h))
            }
            y += h + spacing
        }
    }
}
