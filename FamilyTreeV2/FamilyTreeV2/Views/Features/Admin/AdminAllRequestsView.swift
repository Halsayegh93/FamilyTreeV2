import SwiftUI

struct AdminAllRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @StateObject private var diwaniyaVM = DiwaniyasViewModel()
    @StateObject private var archiveVM = FamilyArchiveViewModel()
    @State private var nameEditRequest: AdminRequest? = nil
    @State private var editedName: String = ""
    @State private var phoneEditRequest: PhoneChangeRequest? = nil
    @State private var editedPhone: String = ""
    /// ما فُتح عليه مربّعا تعديل الاسم/الرقم — «إلغاء» يسأل فقط إذا تغيّر (توصية أبل)
    @State private var editedNameStart: String = ""
    @State private var editedPhoneStart: String = ""
    @State private var selectedDetail: RequestDetail? = nil
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

    @State private var selectedTab: RequestTab = .all
    /// شرائح «من أين وصل» (العيّنة ١٥): الكل · شجرة العائلة · شجرة النساء · الملف الشخصي · التسجيل… — في «الكل» فقط
    @State private var sourceFilter: AdminRequestSourceFilter = .all

    // MARK: «الوارد» (إعادة تصميم لوحة الإدارة — طلب المالك ٢٠٢٦-١٠-٢٠، الاتجاه «أ» + سحب «ب»؛ الدفعة ب من «نفّذ كل المقترح»)
    // طابور عمل بثلاثة مداخل: الطلبات · الرسائل (شريحتان، بلا مبدّل) · ⚙︎ إعدادات مسار الموافقات (بيتها الوحيد).
    // الرأس الكحلي بشرائح المسار (بانتظار قرارك · عاجل · متأخر · الكل)، حقل بحث واحد يخدم الشريحتين (بالاسم أو الرقم)،
    // شرائح المجموعات (الأعضاء · الشجرة · المحتوى) ثم أنواعها، وبطاقات طلبات غنية بأزرار، وآخر القائمة «المنجز اليوم».
    // «تقرير الموافقات» بيته «المؤشرات»، و«مشكلات الشجرة» شريحة في «العائلة» (الوارد = ما طلبه أحد فقط).
    // نفس الاستدعاءات والصلاحيات تماماً (`canApprove(_:)` / `canReject(_:)`، `decideOnServer`، مسار الموافقات).

    /// أقسام «الوارد» الثلاثة (التصميم المعتمد ٢٠٢٦-١١-١١): الطلبات · تمت معالجتها · الرسائل
    enum InboxSegment: Hashable { case requests, handled, messages }
    @State private var segment: InboxSegment = .requests
    /// «تمت معالجتها»: الطلبات المغلقة وسجلّ ما تم في كل طلب (`AdminRequestTrail.swift`)
    @StateObject private var handledStore = AdminHandledStore()
    /// طلب معالَج مفتوح للعرض فقط
    @State private var handledOpen: AdminRequest? = nil
    /// «المنجزة»: حذف مباشر من الإدارة (§9) — مربّع للعرض فقط
    @State private var deletionOpen: MemberDeletePlace? = nil
    /// حقل البحث الواحد — يبحث في كل طلبات المجموعة المختارة، وفي الرسائل (`AdminInboxView(sharedSearch:)`)
    @State private var searchText: String = ""
    /// طلب يُفتح مربّعه بعد التحميل («يحتاج قرارك»، المهام، الإشعار) — مرة واحدة
    private let focusId: UUID?
    @State private var focusHandled = false

    init(focusId: UUID? = nil, initialFilter: ApprovalListFilter = .all,
         startsWithMessages: Bool = false, initialSearch: String = "") {
        self.focusId = focusId
        _approvalFilter = State(initialValue: initialFilter)
        _segment = State(initialValue: startsWithMessages ? .messages : .requests)
        _searchText = State(initialValue: initialSearch)
    }
    /// «مسار الموافقات ٢» (طلب المالك ٢٠٢٦-١٠-١٦ مسار الموافقات ٢): الكل · بانتظارك · مستعجل · متأخر
    @State private var approvalFilter: ApprovalListFilter = .all
    @State private var selectedSection: RequestSection? = nil   // nil = وضع الكل
    /// التحميل الأول (قبل أول `recalculateCounts`) — بطاقة «جارٍ التحميل» بدل «لا توجد طلبات»
    @State private var isInitialLoading = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showBulkApproveChildrenConfirm = false
    @State private var bulkApproveResult: String?
    @State private var showBulkApproveResult = false

    // Multi-select (works for all tabs)
    @State private var isSelectMode = false
    /// «ظهور موحّد» (الدفعة ١٠): بطاقات الطلبات تصعد بعد البحث والشرائح مرة عند ظهورها الأول (`dsCardCascade`)
    @State private var rowsAppeared = false
    @State private var selectedIds: Set<UUID> = []
    @State private var showBulkApproveConfirm = false
    @State private var bulkSelectApproveResult: String?
    @State private var showBulkSelectApproveResult = false
    @State private var showBulkRejectConfirm = false
    @State private var bulkSelectRejectResult: String?
    @State private var showBulkSelectRejectResult = false

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

    // حارس المكدس (الدفعة ب ٢٠٢٦-١٠-٢٠): الجسم ثلاث طبقات خلف `AnyView` — الصفحة، ثم تنبيهات العمليات الجماعية،
    // ثم المربّعات والتأكيدات — فلا يُحلّ نوع سلسلة المُعدِّلات كلها دفعة واحدة (كانت تفيض مكدساً بـ١٢٨ ك.ب)
    var body: some View {
        AnyView(joinBoxLayer(AnyView(modalsLayer(AnyView(bulkAlertsLayer(AnyView(pageLayer)))))))
    }

    private var pageLayer: some View {
        VStack(spacing: 0) {
            AnyView(inboxHeader)

            if showsMessages {
                // «الرسائل» — صفحة الرسائل نفسها بلا رأسها (رأس «الوارد» فوقها) وبحث «الوارد» الواحد
                AnyView(AdminInboxView(embedded: true, sharedSearch: $searchText))
            } else if segment == .handled {
                // «تمت معالجتها» — الطلبات المغلقة بالأيام، وكلّ صفّ يفتح المربّع نفسه للعرض فقط
                AnyView(handledList)
            } else {
                // وضع التحديد: شريط ملخّص التحديد مثبّت أعلى القائمة (إلغاء · العدد · تحديد الكل)
                // — يحلّ محل الفلاتر كما كان، ويبقى ظاهراً مهما نزلت القائمة.
                if isSelectMode && totalCount > 0 {
                    selectionSummaryBar
                        .dsPageMargin()
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.xs)
                        .transition(.opacity)
                }

                // البحث ← المجموعات ← الطلبات: قائمة واحدة تتمرّر (List لأجل أزرار السحب)
                AnyView(requestsList.dsRecordsTapOrigin())   // مربّع التفاصيل يكبر من مكان الضغط
                    // شريط العمليات الجماعية — مثبّت في الأسفل، وآخر صف في القائمة يبقى فوقه
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if isSelectMode && !selectedIds.isEmpty {
                            bulkActionBar
                                .transition(reduceMotion ? .opacity
                                            : .move(edge: .bottom).combined(with: .opacity))
                        }
                    }
            }
        }
        .animation(DS.Anim.snappy, value: isSelectMode && !selectedIds.isEmpty)
        .background(DS.Hub.background.ignoresSafeArea())
        // منطقة شريط الحالة كحلية فوق الرأس الكحلي
        .adminStatusBarCover()
        // الرأس الكحلي هو شريط الصفحة (سحب الرجوع من الحافة يبقى)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: segment) { newValue in
            withAnimation(DS.Anim.snappy) {
                isSelectMode = false
                selectedIds.removeAll()
            }
            // «تمت معالجتها» يُحدَّث عند كل فتح (قرار اتُّخذ للتو في «الطلبات» يظهر فيه)
            if newValue == .handled && handledStore.loadedOnce {
                Task { await handledStore.reload() }
            }
        }
        .onChange(of: selectedSection) { _ in
            withAnimation(DS.Anim.snappy) {
                isSelectMode = false
                selectedIds.removeAll()
            }
        }
        .onChange(of: selectedTab) { _ in
            withAnimation(DS.Anim.snappy) {
                isSelectMode = false
                selectedIds.removeAll()
                // تنظيف bindings الشيتات حتى لا تبقى مفتوحة لطلبات لم تعد في القائمة
                phoneEditRequest = nil
                nameEditRequest = nil
            }
        }
        // أعداد «الوارد» تتبع القوائم لحظياً (قرار من مربّع، طلب جديد، تحديث من الإشعار)
        .onChange(of: requestsSignature) { _ in
            guard !isInitialLoading else { return }
            recalculateCounts()
        }
        // (كان على شريط التابات) إذا التاب الحالي صار فارغ، انقل لأول تاب غير فارغ (لو فيه)
        .onChange(of: totalCount) { _ in
            if itemCount(for: selectedTab) == 0,
               let firstNonEmpty = RequestTab.allCases.first(where: { itemCount(for: $0) > 0 }) {
                withAnimation(DS.Anim.snappy) {
                    selectedTab = firstNonEmpty
                    selectedSection = firstNonEmpty.section
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            // فُتح على «الرسائل» (إشعار/رابط) لدور لا يراها — يرجع لـ«الطلبات» فتظهر شريحته و«تحديد»
            if segment == .messages && !canSeeMessages { segment = .requests }
            // رسالة قديمة من إجراء خارج هذه الشاشة (قبول من الإشعار مثلاً) لا تظهر عند الفتح
            adminRequestVM.errorMessage = nil
            diwaniyaVM.notificationVM = notificationVM
            diwaniyaVM.canModerate = authVM.canModerate
            diwaniyaVM.authVM = authVM
            archiveVM.configure(authVM: authVM, notificationVM: notificationVM)
            // «مسار الموافقات»: المفتاح طازجاً قبل القوائم (مطفأ = لا شيء يتغيّر)
            await adminRequestVM.refreshApprovalsFlag()
            // تحميل متوازي لجميع الطلبات — أسرع بكثير
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in await memberVM.fetchAllMembers() }
                group.addTask { @MainActor in await newsVM.fetchPendingNewsRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchNewsReportRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchPhoneChangeRequests() }
                group.addTask { @MainActor in await diwaniyaVM.fetchPendingDiwaniyas() }
                group.addTask { @MainActor in await archiveVM.fetchItems() }
                group.addTask { @MainActor in await adminRequestVM.fetchDeceasedRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchChildAddRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchPhotoSuggestionRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchNameChangeRequests() }
                group.addTask { @MainActor in await projectsVM.fetchPendingProjects() }
                group.addTask { @MainActor in await adminRequestVM.fetchTreeEditRequests(force: true) }
                // مراحل طلبات الانضمام (المسار شغّال فقط — وإلا لا طلب)
                group.addTask { @MainActor in await adminRequestVM.fetchJoinApprovalRequests() }
                // طلبات حذف الحساب والخصوصية (سياسة الخصوصية ٢٠٢٦-١٠-٢٨)
                group.addTask { @MainActor in await adminRequestVM.fetchPolicyRequests() }
            }
            await fetchAllRegistrationMatches()
            recalculateCounts()

            // اختيار أول تاب فيه طلبات
            if let firstWithItems = cachedAvailableTabs.first {
                selectedTab = firstWithItems
            }
            // انتهى التحميل الأول — تظهر الفلاتر والطلبات بدل بطاقة التحميل
            withAnimation(.easeInOut(duration: 0.2)) { isInitialLoading = false }
            openFocusIfNeeded()
        }
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
            L10n.t("تأكيد الموافقة على الكل", "Confirm Approve All"),
            isPresented: $showBulkApproveChildrenConfirm
        ) {
            Button(L10n.t("الموافقة على الكل", "Approve All"), role: .destructive) {
                Task {
                    let total = adminRequestVM.childAddRequests.count
                    let count = await adminRequestVM.bulkApproveChildAddRequests()
                    if count > 0 { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                    bulkApproveResult = bulkResultText(done: count, total: total, approving: true)
                    showBulkApproveResult = true
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t(
                "سيتم الموافقة على جميع طلبات إضافة الأبناء المعلقة (\(adminRequestVM.childAddRequests.count) طلب)",
                "All pending child add requests (\(adminRequestVM.childAddRequests.count)) will be approved"
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
            L10n.t("تأكيد الموافقة الجماعية", "Confirm Bulk Approve"),
            isPresented: $showBulkApproveConfirm
        ) {
            Button(L10n.t("قبول الكل", "Approve All"), role: .none) {
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
            Text(L10n.t(
                "سيتم الموافقة على \(selectedIds.count) طلب.",
                "This will approve \(selectedIds.count) requests."
            ))
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
            L10n.t("تأكيد الرفض الجماعي", "Confirm Bulk Reject"),
            isPresented: $showBulkRejectConfirm
        ) {
            Button(L10n.t("رفض الكل", "Reject All"), role: .destructive) {
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
            Text(L10n.t(
                "سيتم رفض \(selectedIds.count) طلب.",
                "This will reject \(selectedIds.count) requests."
            ))
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

    /// مربّع تفاصيل الطلب، والسحب (رفض/حذف)، وربط طلب الانضمام ودمجه
    private func modalsLayer(_ content: AnyView) -> some View {
        content
        // «تمت معالجتها»: المربّع نفسه للعرض فقط (بلا أزرار قرار) + «ما تم في الطلب» و«النتيجة»
        .dsCenterBox(item: $handledOpen) { request in
            handledBox(request)
        }
        .dsCenterBox(item: $deletionOpen) { deletion in
            AnyView(AdminDeletionBox(deletion: deletion, men: memberVM.allMembers) { deletionOpen = nil })
        }
        // تفاصيل الطلب — مربّع بمنتصف الشاشة بدل الورقة السفلية (طلب المالك)
        .dsCenterBox(item: $selectedDetail) { detail in
            requestDetailSheet(detail)
                .dsAlert(L10n.t("سبب الرفض", "Rejection Reason"), isPresented: $showRejectReason) {
                    TextField(L10n.t("اكتب السبب (اختياري)", "Reason (optional)"), text: $rejectReasonText)
                        .dsAlertField()
                    Button(L10n.t("إرسال الرفض", "Send Rejection"), role: .destructive) {
                        if let d = rejectReasonDetail {
                            rejectDetail(d, reason: rejectReasonText)
                        }
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
                        if let m = forwardJoinMember { forwardJoin(m, note: forwardJoinNote) }
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
        // رفض عبر السحب (الكل) — تأكيد + سبب الرفض
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
                    rejectDetail(d, reason: trimmed.isEmpty ? nil : trimmed)
                }
                swipeRejectDetail = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { swipeRejectDetail = nil }
        } message: {
            Text(L10n.t("سيُرفَض الطلب ويبقى في السجل.", "The request will be rejected and kept in the log."))
        }
        // حذف عبر السحب (الكل) — تأكيد نهائي بالمنتصف (Alert)
        .dsAlert(
            L10n.t("حذف الطلب نهائياً؟", "Delete request permanently?"),
            isPresented: Binding(
                get: { swipeDeleteDetail != nil },
                set: { if !$0 { swipeDeleteDetail = nil } }
            )
        ) {
            Button(L10n.t("حذف نهائي", "Delete Permanently"), role: .destructive) {
                if let d = swipeDeleteDetail { hardDeleteDetail(d) }
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

    // MARK: - «الوارد»: الرأس، المبدّل، المجموعات، البحث، فتح طلب بعينه

    /// الرأس الكحلي: «‹ اليوم» + (⚙︎ إعدادات مسار الموافقات · تحديد) + «الوارد» + شرائح المسار
    private var inboxHeader: some View {
        VStack(spacing: 0) {
            AdminBandHeader(title: L10n.t("الوارد", "Inbox"),
                            subtitle: authVM.isAdmin ? nil : heroSubtitle, isAreaRoot: true) {
                // ⚙︎ بيت «إعدادات مسار الموافقات» الوحيد — ظهوره من جدول السيرفر (`inbox.approval_settings`:
                // المالك يعدّل، المدير يقرأ افتراضاً)؛ الصفحة نفسها تقفل مفاتيحها لغير المالك (`canManageSettings`)
                if authVM.adminSees(.inboxApprovalSettings) {
                    NavigationLink {
                        AdminLazyPage {
                            AnyView(AdminAppSettingsView(scope: .approvals).adminBackTitle(AdminArea.inbox.title).adminArea(.inbox))
                        }
                    } label: {
                        AdminGlassCircle(symbol: "gearshape")
                    }
                    .buttonStyle(DSScaleButtonStyle())
                    .accessibilityLabel(L10n.t("إعدادات مسار الموافقات", "Approval path settings"))
                }
                if segment == .requests && !isSelectMode && itemCount(for: selectedTab) > 0 {
                    AdminGlassButton(symbol: "checkmark.circle", label: L10n.t("تحديد", "Select")) {
                        withAnimation(DS.Anim.snappy) {
                            isSelectMode = true
                            selectedIds.removeAll()
                        }
                    }
                }
            } accessory: {
                // الأقسام الثلاثة في مسار واحد على الرأس (التصميم المعتمد ٢٠٢٦-١١-١١) — «الرسائل» لمن يراها في جدول
                // السيرفر (`inbox.messages`: المالك والمدير افتراضاً)، و«تمت معالجتها» لكل من يرى الطلبات
                if !isSelectMode {
                    AdminInboxSegmentTrack(options: segmentOptions, selection: $segment)
                        .accessibilityLabel(L10n.t("أقسام الوارد", "Inbox sections"))
                        .padding(.top, DS.Spacing.md)
                }
            }
        }
    }

    /// خيارات مسار الأقسام: الطلبات (عددها) · تمت معالجتها · الرسائل (غير المقروء أحمر)
    private var segmentOptions: [AdminInboxSegmentOption<InboxSegment>] {
        var options = [
            AdminInboxSegmentOption(id: InboxSegment.requests, title: L10n.t("الطلبات", "Requests"),
                                    count: isInitialLoading ? nil : cachedTotalCount),
            AdminInboxSegmentOption(id: InboxSegment.handled, title: L10n.t("المنجزة", "Done")),  // القرار ٤ «أ» (٢٠٢٦-١١-١٢)
        ]
        if canSeeMessages {
            options.append(AdminInboxSegmentOption(id: InboxSegment.messages, title: L10n.t("الرسائل", "Messages"),
                                                   count: adminRequestVM.pendingContactMessagesCount, alert: true))
        }
        return options
    }

    /// صفّ الفلاتر الواحد (`AdminInboxFilterRow`): «كل الطلبات» ← فلاتر المسار حين تنطبق ← المجموعات.
    /// المسار والمجموعة يجتمعان كما كانا (شريحتان مستقلّتان)، والضغط على المختارة يلغيها
    private var inboxFilterItems: [AdminInboxFilterItem] {
        let showFlow = tabSupportsApprovalFilter(selectedTab) && !isInitialLoading
        let visible = showFlow ? unfilteredTabIds.compactMap(adminRequestVM.approvalSnapshot(forRowId:)) : []
        func count(_ f: ApprovalListFilter) -> Int { adminRequestVM.approvalFilterCount(f, in: visible) }
        var items = [AdminInboxFilterItem(
            id: "all", title: L10n.t("كل الطلبات", "All requests"), count: isInitialLoading ? nil : cachedTotalCount,
            selected: approvalFilter == .all && selectedSection == nil) {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) {
                    approvalFilter = .all
                    selectedSection = nil
                    selectedTab = .all
                }
            }]
        if showFlow {
            if count(.waiting) > 0 || approvalFilter == .waiting {
                items.append(AdminInboxFilterItem(id: "waiting", title: L10n.t("بانتظار قرارك", "Awaiting you"),
                                                  count: count(.waiting), tone: .amber,
                                                  selected: approvalFilter == .waiting) { toggleApprovalFilter(.waiting) })
            }
            if adminRequestVM.approvalsV2Seen && (count(.urgent) > 0 || approvalFilter == .urgent) {
                items.append(AdminInboxFilterItem(id: "urgent", title: L10n.t("عاجل", "Urgent"), count: count(.urgent),
                                                  icon: "flame", tone: .red,
                                                  selected: approvalFilter == .urgent) { toggleApprovalFilter(.urgent) })
            }
            if count(.late) > 0 || approvalFilter == .late {
                items.append(AdminInboxFilterItem(id: "late", title: L10n.t("متأخر", "Late"), count: count(.late),
                                                  icon: "clock", tone: .red,
                                                  selected: approvalFilter == .late) { toggleApprovalFilter(.late) })
            }
        }
        for section in RequestSection.allCases where sectionCount(section) > 0 || section == selectedSection {
            items.append(AdminInboxFilterItem(id: "group-\(section.title)", title: section.title,
                                              count: sectionCount(section), icon: section.icon,
                                              selected: selectedSection == section) {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) {
                    selectedSection = selectedSection == section ? nil : section
                    selectedTab = .all
                }
            })
        }
        return items
    }

    /// شريحة مسار: اختيارها، أو إلغاؤها إن كانت المختارة
    private func toggleApprovalFilter(_ f: ApprovalListFilter) {
        setApprovalFilter(approvalFilter == f ? .all : f)
    }

    /// «الرسائل» (رسائل الأعضاء الخاصة) لمن يراها في جدول «مين يشوف وش» — السيرفر يحرسها أيضاً
    /// (`20261107210000_contact_messages_owner_admin`)
    private var canSeeMessages: Bool { authVM.adminSees(.inboxMessages) }

    /// الرسائل معروضة الحين — رابط قديم/إشعار بـ`startsWithMessages` لمن لا يراها يبقى على «الطلبات»
    private var showsMessages: Bool { segment == .messages && canSeeMessages }

    private func setApprovalFilter(_ f: ApprovalListFilter) {
        guard approvalFilter != f else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) { approvalFilter = f }
    }

    /// عدد مجموعة (الأعضاء · الشجرة · المحتوى · صحة الشجرة) في مجال الدور
    private func sectionCount(_ section: RequestSection) -> Int {
        availableTabs.filter { $0.section == section }.reduce(0) { $0 + itemCount(for: $1) }
    }

    /// أنواع المجموعة المختارة: «كل المجموعة» ثم كل نوع فيه طلبات
    private var subTypeChips: some View {
        let tabs = availableTabs.filter { $0.section == selectedSection && (itemCount(for: $0) > 0 || $0 == selectedTab) }
        var options: [DSFilterOption<RequestTab>] = [
            DSFilterOption(id: .all, title: L10n.t("كل \(selectedSection?.title ?? "")", "All \(selectedSection?.title ?? "")"))
        ]
        options += tabs.map { DSFilterOption(id: $0, title: chipTitle($0), icon: $0.icon, count: itemCount(for: $0)) }
        return DSFilterChips(options: options, selection: $selectedTab)
            .accessibilityLabel(L10n.t("أنواع الطلبات", "Request types"))
    }

    /// بصمة القوائم — تتغيّر مع أي إضافة/حذف في أي نوع
    private var requestsSignature: [Int] {
        [memberVM.allMembers.count, newsVM.pendingNewsRequests.count, adminRequestVM.newsReportRequests.count,
         adminRequestVM.phoneChangeRequests.count, adminRequestVM.nameChangeRequests.count,
         diwaniyaVM.pendingDiwaniyas.count, adminRequestVM.deceasedRequests.count,
         adminRequestVM.childAddRequests.count, adminRequestVM.photoSuggestionRequests.count,
         projectsVM.pendingProjects.count, pendingArchiveItems.count, adminRequestVM.treeEditRequests.count,
         adminRequestVM.policyRequestsCount]
    }

    /// بطاقات طلبات الحذف والخصوصية: خارج البحث والتحديد، في «الكل» أو مجموعة «الأعضاء»
    private var showsPolicyRequests: Bool {
        adminRequestVM.policyRequestsCount > 0 && !isSearching && !isSelectMode
            && (selectedSection == nil || selectedSection == .members) && selectedTab == .all
    }

    /// يبحث الآن (نصّ غير فارغ)
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// عناصر «الكل» كما تُعرض: مجموعة المختارة ثم البحث ثم شريحة المصدر (الترتيب والمجال كما في `sortedAllItems`)
    private var displayedAllItems: [AllItem] {
        let items = searchedAllItems
        guard sourceFilter != .all else { return items }
        return items.filter { sourceFilter.matches(origin(for: requestDetail(for: $0))?.kind) }
    }

    /// شرائح المصدر بأعدادها (المجموعة والبحث مطبّقان) — nil حين لا يوجد مصدران فأكثر
    private var sourceFilterOptions: [DSFilterOption<AdminRequestSourceFilter>]? {
        guard selectedTab == .all else { return nil }
        let kinds = searchedAllItems.map { origin(for: requestDetail(for: $0))?.kind }
        return AdminRequestSourceFilter.options(kinds: kinds, selected: sourceFilter)
    }

    /// عناصر «الكل» بعد المجموعة والبحث (قبل شريحة المصدر)
    private var searchedAllItems: [AllItem] {
        var items = sortedAllItems
        if let section = selectedSection {
            items = items.filter { allItemTab($0).section == section }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        // البحث الدقيق الواحد (`NameSearch`): كل كلمة بداية كلمة بالترتيب (والرقم أرقاماً فقط)
        if NameSearch.isPhoneQuery(q) {
            let digits = NameSearch.digits(q)
            return digits.count >= 3 ? items.filter { searchTexts($0).contains { NameSearch.digits($0).contains(digits) } } : []
        }
        return items.filter { NameSearch.matches(query: q, any: searchTexts($0)) }
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

    /// يفتح مربّع الطلب المطلوب بعد التحميل (من «يحتاج قرارك» أو المهام أو الإشعار) — مرة واحدة
    private func openFocusIfNeeded() {
        guard let focusId, !focusHandled else { return }
        focusHandled = true
        // طلب انضمام بمعرّف صفّه في admin_requests ← صفّه في القائمة بمعرّف العضو المعلّق
        let rowId = adminRequestVM.joinApprovalRequests.first(where: { $0.id == focusId })?.memberId ?? focusId
        guard let item = sortedAllItems.first(where: { selectableId($0) == rowId }) else { return }
        selectedDetail = requestDetail(for: item)
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

    // MARK: - Item Count

    private func itemCount(for tab: RequestTab) -> Int {
        switch tab {
        case .all: return cachedTotalCount
        case .joinRequests: return pendingMembers.count
        case .news: return newsVM.pendingNewsRequests.count
        case .reports: return adminRequestVM.newsReportRequests.count
        case .phone: return adminRequestVM.phoneChangeRequests.count
        case .nameChange: return adminRequestVM.nameChangeRequests.count
        case .diwaniya: return diwaniyaVM.pendingDiwaniyas.count
        case .deceased: return adminRequestVM.deceasedRequests.count
        case .children: return adminRequestVM.childAddRequests.count
        case .treeAdd: return treeEditCount(action: .add)
        case .treeEditName: return treeEditCount(action: .editName)
        case .treeEditPhone: return treeEditCount(action: .editPhone)
        case .treeEditBirth: return treeEditCount(action: .editBirth)
        case .treeDeceased: return treeEditCount(action: .deceased)
        case .treeAddDeathDate: return treeEditCount(action: .addDeathDate)
        case .treeAddPhoto: return treeEditCount(action: .addPhoto)
        case .treeDelete: return treeEditCount(action: .delete)
        case .treeOther: return treeEditCount(action: .other)
        case .photos: return adminRequestVM.photoSuggestionRequests.count
        case .projects: return projectsVM.pendingProjects.count
        case .archive: return pendingArchiveItems.count
        }
    }

    /// عدد طلبات الشجرة لإجراء معيّن.
    private func treeEditCount(action: TreeEditAction) -> Int {
        adminRequestVM.treeEditRequests.filter { $0.treeEditPayload?.resolvedAction == action }.count
    }

    /// طلبات الشجرة المفلترة لإجراء معيّن.
    private func treeEdits(action: TreeEditAction) -> [AdminRequest] {
        adminRequestVM.treeEditRequests.filter { $0.treeEditPayload?.resolvedAction == action }
    }

    @State private var cachedTotalCount: Int = 0
    @State private var cachedAvailableTabs: [RequestTab] = RequestTab.allCases

    private var totalCount: Int { cachedTotalCount }
    private var availableTabs: [RequestTab] { cachedAvailableTabs }

    // MARK: - صلاحية الإجراء حسب مجال الدور (تحديث الأدوار 2026-09-21)

    /// تابات المحتوى — الاعتماد فيها للإدارة، والمراجعة والبلاغات للمشرف
    private static let contentTabs: Set<RequestTab> = [.news, .projects, .archive, .diwaniya, .photos, .reports]

    /// هل يقدر المستخدم الحالي يعتمد عناصر هذا التاب؟
    private func canApprove(_ tab: RequestTab) -> Bool {
        if tab == .reports { return authVM.canModerateContent }
        if tab == .photos { return canHandlePhotos }
        return Self.contentTabs.contains(tab) ? authVM.canApproveContent : authVM.canApproveTreeRequests
    }

    /// هل يقدر يرفضها؟ (المشرف يتعامل مع البلاغات فقط)
    /// رفض طلب الانضمام = حذف ملف المتقدّم (`rejectOrDeleteMember`) — للمالك والمدير (`canDeleteMembers`) وحدهما،
    /// كان يظهر للمراقب فيفشل دائماً
    private func canReject(_ tab: RequestTab) -> Bool {
        if tab == .reports { return authVM.canModerateContent }
        if tab == .photos { return canHandlePhotos }
        if tab == .joinRequests { return authVM.canDeleteMembers }
        return Self.contentTabs.contains(tab) ? authVM.canApproveContent : authVM.canRejectRequests
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

    // MARK: - بطاقة الرأس (صفحات الإدارة الموحّدة — طلب المالك ٢٠٢٦-٠٩-٢٧)

    /// لون مجال المشاهد — نفس منطق `tabsForRole`: الإدارة كل المجالات (بلون تبويب الإدارة)،
    /// المشرف المحتوى والبلاغات (ذهبي)، والمراقب الشجرة والأعضاء (أخضر).
    private var pageTint: Color {
        if authVM.isAdmin { return AppSection.admin.fill }
        if authVM.currentUser?.role == .supervisor { return DS.Color.composerLibrary }
        return DS.Color.composerProject
    }

    private var heroSubtitle: String {
        if authVM.isAdmin {
            return L10n.t("كل ما ينتظر قرارك في مكان واحد", "Everything awaiting your decision, in one place")
        }
        if authVM.currentUser?.role == .supervisor {
            return L10n.t("مجالك: المحتوى والبلاغات", "Your scope: content & reports")
        }
        return L10n.t("مجالك: الشجرة والأعضاء", "Your scope: tree & members")
    }

    // MARK: - الفلاتر: مجموعات «الوارد» ثم أنواعها (`groupChips` / `subTypeChips`) — كانت شبكة بلاطات الأنواع

    /// داخل قسم «الشجرة» لا حاجة لتكرار «(شجرة)» في كل شريحة
    private func chipTitle(_ tab: RequestTab) -> String {
        guard tab.section == .tree else { return tab.title }
        return tab.title
            .replacingOccurrences(of: " (شجرة)", with: "")
            .replacingOccurrences(of: "Tree · ", with: "")
    }

    /// شريط ملخّص التحديد — يحلّ محل الفلاتر في وضع التحديد: «إلغاء» · العدد · «تحديد الكل».
    private var selectionSummaryBar: some View {
        // تحديد الكل في التاب الحالي
        let currentIds = currentTabIds
        let allSelected = !currentIds.isEmpty && currentIds.allSatisfy { selectedIds.contains($0) }
        return HStack(spacing: DS.Spacing.xs) {
            DSChipButton(L10n.t("إلغاء", "Cancel"), tint: DS.Color.error) {
                withAnimation(DS.Anim.snappy) {
                    isSelectMode = false
                    selectedIds.removeAll()
                }
            }

            Spacer(minLength: 0)

            DSStatusChip(text: L10n.t("اختيار \(selectedIds.count)", "Selected \(selectedIds.count)"),
                          icon: "checkmark.circle.fill",
                          tint: AppSection.admin.ink)

            Spacer(minLength: 0)

            DSChipButton(allSelected
                         ? L10n.t("إلغاء الكل", "Clear all")
                         : L10n.t("تحديد الكل", "Select all")) {
                withAnimation(DS.Anim.snappy) {
                    if allSelected {
                        currentIds.forEach { selectedIds.remove($0) }
                    } else {
                        currentIds.forEach { selectedIds.insert($0) }
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.xs)
        .background(Capsule().fill(DS.Color.surface))
        .overlay(Capsule().strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.border), lineWidth: DS.Border.width))
    }

    /// شريط العمليات الجماعية أسفل الشاشة: العدد ← «رفض» (لمن يملكه) ← «قبول» الكحلي
    private var bulkActionBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            // عداد المحددين
            VStack(spacing: 0) {
                Text("\(selectedIds.count)")
                    .dsFont(.title)
                    .foregroundColor(DS.Color.fieldLabel)
                    .monospacedDigit()
                Text(L10n.t("محدد", "selected"))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
            }
            .frame(minWidth: DS.Icon.tapTarget)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            // زر الرفض — يظهر فقط لمن يملك الصلاحية (في التبويب نفسه: صلاحية مجاله، ومنها رفض الانضمام للمالك/المدير)
            if selectedTab == .all ? authVM.canRejectRequests : canReject(selectedTab) {
                DSButton(L10n.t("رفض", "Reject"), icon: "xmark.circle.fill", role: .destructive, tint: DS.Color.reject, fullWidth: false) {
                    showBulkRejectConfirm = true
                }
                .disabled(adminRequestVM.isLoading)
            }

            // زر القبول — الزرّ الواحد بتعبئة القسم
            DSButton(L10n.t("قبول", "Approve"), icon: "checkmark.circle.fill", fullWidth: false) {
                showBulkApproveConfirm = true
            }
            .disabled(adminRequestVM.isLoading)
        }
        .dsPageMargin()
        .padding(.vertical, DS.Spacing.sm)
        .background(
            DS.Color.surface
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(DS.Color.textTertiary.opacity(DS.Opacity.border))
                        .frame(height: DS.Border.width)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// معرّفات عناصر التاب الحالي الظاهرة (للاستخدام في "تحديد الكل") — بعد فلتر «مسار ٢»
    private var currentTabIds: [UUID] {
        let ids = unfilteredTabIds
        guard isApprovalFilterActive else { return ids }
        return ids.filter { passesApprovalFilter($0, tab: selectedTab) }
    }

    /// كل معرّفات التاب الحالي (قبل الفلتر)
    private var unfilteredTabIds: [UUID] {
        switch selectedTab {
        case .all:
            // «الكل» = عناصر مجال الدور فقط، كما تُعرض (فحص الثغرات ب-٧): كان «تحديد الكل»
            // يلتقط أنواع كل المجالات فتتجاوز الموافقة الجماعية صلاحية المراقب/المشرف
            return displayedAllItems.compactMap(selectableId)
        case .joinRequests: return pendingMembers.map { $0.id }
        case .news:         return newsVM.pendingNewsRequests.map { $0.id }
        case .reports:      return adminRequestVM.newsReportRequests.map { $0.id }
        case .phone:        return adminRequestVM.phoneChangeRequests.map { $0.id }
        case .nameChange:   return adminRequestVM.nameChangeRequests.map { $0.id }
        case .diwaniya:     return diwaniyaVM.pendingDiwaniyas.map { $0.id }
        case .deceased:     return adminRequestVM.deceasedRequests.map { $0.id }
        case .children:     return adminRequestVM.childAddRequests.map { $0.id }
        case .treeAdd:      return treeEdits(action: .add).map { $0.id }
        case .treeEditName: return treeEdits(action: .editName).map { $0.id }
        case .treeEditPhone: return treeEdits(action: .editPhone).map { $0.id }
        case .treeEditBirth: return treeEdits(action: .editBirth).map { $0.id }
        case .treeDeceased: return treeEdits(action: .deceased).map { $0.id }
        case .treeAddDeathDate: return treeEdits(action: .addDeathDate).map { $0.id }
        case .treeAddPhoto: return treeEdits(action: .addPhoto).map { $0.id }
        case .treeDelete:   return treeEdits(action: .delete).map { $0.id }
        case .treeOther:    return treeEdits(action: .other).map { $0.id }
        case .photos:       return adminRequestVM.photoSuggestionRequests.map { $0.id }
        case .projects:     return projectsVM.pendingProjects.map { $0.id }
        case .archive:      return pendingArchiveItems.map { $0.id }
        }
    }

    // MARK: - القائمة

    /// بطاقة الرأس ← (تحميل) ← الفلاتر ← الطلبات أو بطاقة «لا توجد طلبات» — صفوف قائمة واحدة
    /// تتمرّر معاً. بقيت `List` لأجل أزرار السحب (موافقة / رفض / حذف).
    /// (أُزيل `.id(selectedTab)` — كان يعيد بناء القائمة كلها ومعها بطاقة الرأس وحركتها عند كل تبويب.)
    private var requestsList: some View {
        List {
            if isInitialLoading {
                // هيكل البطاقات بدل المجسّم (طلب المالك ٢٠٢٦-١١-١٧) — الطلبات تحلّ مكانه بلا قفزة
                DSCardSkeleton(style: .request, label: L10n.t("جارٍ تحميل الطلبات…", "Loading requests…"))
                    .padding(.top, DS.Spacing.sm)
                    .dsStaggerIn(1)
                    .reviewListRow()
            } else {
                // «بحث بالاسم أو الرقم» (لمسة «ب») ثم شرائح المجموعات وأنواعها (الاتجاه «أ»)
                // — وفي وضع التحديد يحلّ محلها شريط الملخّص أعلاه.
                if totalCount > 0 && !isSelectMode {
                    DSSearchField(text: $searchText, placeholder: AdminInboxView.searchPlaceholder)
                        .reviewListRow(top: DS.Spacing.md, bottom: DS.Spacing.xs)
                    AdminInboxFilterRow(items: inboxFilterItems)
                        .reviewListRow(top: 0, bottom: 0)
                    if let sources = sourceFilterOptions {
                        DSFilterChips(options: sources, selection: $sourceFilter)
                            .accessibilityLabel(L10n.t("مصدر الطلب", "Request source"))
                            .reviewListRow(top: 0, bottom: DS.Spacing.xs)
                    }
                    if selectedSection != nil {
                        subTypeChips
                            .reviewListRow(top: 0, bottom: DS.Spacing.xs)
                    }
                }

                // طلبات حذف الحساب والخصوصية — بطاقات مستقلّة في «الكل» و«الأعضاء»
                if showsPolicyRequests {
                    AdminPolicyRequestsSection(adminRequestVM: adminRequestVM, focusId: focusId)
                }

                if isSearching {
                    // البحث يعرض كل طلبات المجموعة المطابقة (أي نوع)
                    allRequestsContent()
                } else if totalCount == 0 || itemCount(for: selectedTab) == 0 {
                    if !showsPolicyRequests {
                        emptyState
                            .padding(.top, DS.Spacing.xs)
                            .dsStaggerIn(2)
                            .reviewListRow()
                    }
                } else if isApprovalFilterActive && currentTabIds.isEmpty {
                    DSEmptyView(L10n.t("لا طلبات هنا", "Nothing here"),
                                message: L10n.t("لا توجد طلبات مطابقة لهذا الفلتر حالياً.", "No request matches this filter right now."),
                                style: .card)
                        .padding(.top, DS.Spacing.xs)
                        .reviewListRow()
                } else {
                    tabRows
                }
                // «المنجز اليوم» أُزيل من آخر القائمة (٢٠٢٦-١١-١١) — مكانه قسم «تمت معالجتها» في الرأس
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .environment(\.defaultMinListRowHeight, 0)
        .animation(reduceMotion ? Animation.easeInOut(duration: 0.15) : Animation.snappy(duration: 0.2),
                   value: selectedTab)
    }

    /// صفوف التبويب المختار — نفس الاستدعاءات والصلاحيات السابقة تماماً
    @ViewBuilder
    private var tabRows: some View {
        // زر الموافقة على الكل — أبناء فقط
        if selectedTab == .children && adminRequestVM.childAddRequests.count > 1
            && !adminRequestVM.approvalsWorkflowOn {
            DSActionButton(
                title: L10n.t(
                    "الموافقة على الكل (\(adminRequestVM.childAddRequests.count))",
                    "Approve All (\(adminRequestVM.childAddRequests.count))"
                ),
                icon: "checkmark.circle.fill",
                tint: DS.Color.success,
                enabled: !adminRequestVM.isLoading
            ) {
                showBulkApproveChildrenConfirm = true
            }
            .reviewListRow(top: DS.Spacing.xs, bottom: DS.Spacing.xs)
        }

        switch selectedTab {
        case .joinRequests:
            selectAllButton(ids: pendingMembers.map { $0.id })
            ForEach(adminRequestVM.approvalOrdered(pendingMembers)) { member in
                selectableRow(
                    id: member.id,
                    accentColor: RequestTab.joinRequests.color,
                    approveLabel: joinApproveLabel(member),
                    approveIcon: "link.badge.plus",
                    approveTint: DS.Color.success, softReject: true,
                    onApprove: { joinApprove(member) },
                    onReject: { swipeRejectReason = ""; swipeRejectDetail = .join(member) },
                    onTap: { selectedDetail = .join(member) }
                ) {
                    joinRequestRow(for: member)
                }
            }
        case .news:
            selectAllButton(ids: newsVM.pendingNewsRequests.map { $0.id })
            ForEach(newsVM.pendingNewsRequests) { post in
                selectableRow(
                    id: post.id,
                    accentColor: RequestTab.news.color,
                    onApprove: { Task { await newsVM.approveNewsPost(postId: post.id) } },
                    onReject: { swipeRejectReason = ""; swipeRejectDetail = .news(post) },
                    onTap: { selectedDetail = .news(post) }
                ) {
                    newsRow(for: post)
                }
            }
        case .reports:
            selectAllButton(ids: adminRequestVM.newsReportRequests.map { $0.id })
            ForEach(adminRequestVM.approvalOrdered(adminRequestVM.newsReportRequests)) { request in
                selectableRow(
                    id: request.id,
                    accentColor: RequestTab.reports.color,
                    onApprove: { Task { await adminRequestVM.approveNewsReport(request: request) } },
                    onReject: { swipeRejectReason = ""; swipeRejectDetail = .report(request) },
                    onTap: { selectedDetail = .report(request) }
                ) {
                    reportRow(for: request)
                }
            }
        case .phone:
            ForEach(adminRequestVM.approvalOrdered(adminRequestVM.phoneChangeRequests)) { request in
                selectableRow(
                    id: request.id,
                    accentColor: RequestTab.phone.color,
                    onApprove: { Task { await adminRequestVM.approvePhoneChangeRequest(request: request) } },
                    onReject: { swipeRejectReason = ""; swipeRejectDetail = .phone(request) },
                    onTap: { selectedDetail = .phone(request) }
                ) {
                    phoneRow(for: request)
                }
            }
            .dsCenterBox(item: $phoneEditRequest) { request in
                adminPhoneEditSheet(request: request)
            }
        case .nameChange:
            ForEach(adminRequestVM.approvalOrdered(adminRequestVM.nameChangeRequests)) { request in
                selectableRow(
                    id: request.id,
                    accentColor: RequestTab.nameChange.color,
                    onApprove: { Task { await adminRequestVM.approveNameChangeRequest(request: request) } },
                    onReject: { swipeRejectReason = ""; swipeRejectDetail = .nameChange(request) },
                    onTap: { selectedDetail = .nameChange(request) }
                ) {
                    nameChangeRow(for: request)
                }
            }
            .dsCenterBox(item: $nameEditRequest) { request in
                adminNameEditSheet(request: request)
            }
        case .diwaniya:
            selectAllButton(ids: diwaniyaVM.pendingDiwaniyas.map { $0.id })
            ForEach(diwaniyaVM.pendingDiwaniyas) { diwaniya in
                selectableRow(
                    id: diwaniya.id,
                    accentColor: RequestTab.diwaniya.color,
                    onApprove: {
                        if let adminId = authVM.currentUser?.id {
                            Task { await diwaniyaVM.approveDiwaniya(id: diwaniya.id, adminId: adminId) }
                        }
                    },
                    onReject: { swipeRejectReason = ""; swipeRejectDetail = .diwaniya(diwaniya) },
                    onTap: { selectedDetail = .diwaniya(diwaniya) }
                ) {
                    diwaniyaRow(for: diwaniya)
                }
            }
        case .deceased:
            selectAllButton(ids: adminRequestVM.deceasedRequests.map { $0.id })
            ForEach(adminRequestVM.approvalOrdered(adminRequestVM.deceasedRequests)) { request in
                selectableRow(
                    id: request.id,
                    accentColor: RequestTab.deceased.color,
                    onApprove: { Task { await adminRequestVM.approveDeceasedRequest(request: request) } },
                    onReject: { swipeRejectReason = ""; swipeRejectDetail = .deceased(request) },
                    onTap: { selectedDetail = .deceased(request) }
                ) {
                    deceasedRow(for: request)
                }
            }
        case .children:
            selectAllButton(ids: adminRequestVM.childAddRequests.map { $0.id })
            ForEach(adminRequestVM.approvalOrdered(adminRequestVM.childAddRequests)) { request in
                selectableRow(
                    id: request.id,
                    accentColor: RequestTab.children.color,
                    approveLabel: L10n.t("تأكيد", "Confirm"),
                    onApprove: { Task { await adminRequestVM.acknowledgeChildAddRequest(request: request) } },
                    onReject: { swipeRejectReason = ""; swipeRejectDetail = .child(request) },
                    onTap: { selectedDetail = .child(request) }
                ) {
                    childRow(for: request)
                }
            }
        case .photos:
            selectAllButton(ids: adminRequestVM.photoSuggestionRequests.map { $0.id })
            ForEach(adminRequestVM.approvalOrdered(adminRequestVM.photoSuggestionRequests)) { request in
                selectableRow(
                    id: request.id,
                    accentColor: RequestTab.photos.color,
                    onApprove: { Task { await adminRequestVM.approvePhotoSuggestion(request: request) } },
                    onReject: { swipeRejectReason = ""; swipeRejectDetail = .photo(request) },
                    onTap: { selectedDetail = .photo(request) }
                ) {
                    photoRow(for: request)
                }
            }
        case .projects:
            selectAllButton(ids: projectsVM.pendingProjects.map { $0.id })
            ForEach(projectsVM.pendingProjects) { project in
                selectableRow(
                    id: project.id,
                    accentColor: RequestTab.projects.color,
                    onApprove: {
                        if let adminId = authVM.currentUser?.id {
                            Task { await projectsVM.approveProject(id: project.id, approvedBy: adminId) }
                        }
                    },
                    onReject: { swipeRejectReason = ""; swipeRejectDetail = .project(project) },
                    onTap: { selectedDetail = .project(project) }
                ) {
                    projectRow(for: project)
                }
            }
        case .archive:
            selectAllButton(ids: pendingArchiveItems.map { $0.id })
            ForEach(pendingArchiveItems) { item in
                selectableRow(
                    id: item.id,
                    accentColor: RequestTab.archive.color,
                    onApprove: { Task { await archiveVM.approveItem(item) } },
                    onReject: { swipeRejectReason = ""; swipeRejectDetail = .archive(item) },
                    onTap: { selectedDetail = .archive(item) }
                ) {
                    archiveRow(for: item)
                }
            }
        case .treeAdd:
            treeEditList(action: .add, color: RequestTab.treeAdd.color)
        case .treeEditName:
            treeEditList(action: .editName, color: RequestTab.treeEditName.color)
        case .treeEditPhone:
            treeEditList(action: .editPhone, color: RequestTab.treeEditPhone.color)
        case .treeEditBirth:
            treeEditList(action: .editBirth, color: RequestTab.treeEditBirth.color)
        case .treeDeceased:
            treeEditList(action: .deceased, color: RequestTab.treeDeceased.color)
        case .treeAddDeathDate:
            treeEditList(action: .addDeathDate, color: RequestTab.treeAddDeathDate.color)
        case .treeAddPhoto:
            treeEditList(action: .addPhoto, color: RequestTab.treeAddPhoto.color)
        case .treeDelete:
            treeEditList(action: .delete, color: RequestTab.treeDelete.color)
        case .treeOther:
            treeEditList(action: .other, color: RequestTab.treeOther.color)
        case .all:
            allRequestsContent()
        }
    }

    // MARK: - Select Mode Helpers

    /// «تحديد الكل» انتقل إلى `selectionSummaryBar` أعلى الشاشة — بقيت الدالّة فارغة لاستدعاءاتها
    private func selectAllButton(ids: [UUID]) -> some View {
        EmptyView()
    }

    /// صف طلب موحّد بإطار صفوف المربّعات (`.dsRowBox()`): المحتوى (أيقونة الحقل + العنوان +
    /// الوصف + شارة الحالة) ثم سهم التفاصيل — وفي وضع التحديد دائرة اختيار في أول الصف.
    /// - `accentColor`: لون نوع الطلب — صار في أيقونة الصف نفسها (بقي للاستدعاءات)
    /// - `approveLabel`: نص زر الموافقة بالسحب (افتراضي: "موافقة")
    /// - `approveIcon`: أيقونة زر الموافقة (افتراضي: checkmark)
    /// - `onApprove`/`onReject`: nil = الزر يختفي
    private func selectableRow<Content: View>(
        id: UUID,
        forTab: RequestTab? = nil,
        accentColor: Color = AppSection.admin.ink,
        approveLabel: String? = nil,
        approveIcon: String = "checkmark",
        approveColor: Color = DS.Color.successFill,
        approveTint: Color? = nil,
        softReject: Bool = false,
        onApprove: (() -> Void)? = nil,
        onReject: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isSelected = isSelectMode && selectedIds.contains(id)
        // «مسار الموافقات»: لقطة الصف — مطفأ = nil = الصف كما كان
        let flow = adminRequestVM.approvalSnapshot(forRowId: id)
        // «مسار ٢»: فلتر الكل · بانتظارك · مستعجل · متأخر — الصف لا يظهر إن لم يطابق
        let visible = passesApprovalFilter(id, tab: selectedTab, flow: flow)
        // بالمسار: الموافقة بالسحب = «تنفيذ» للمختص والطلب معتمد، والرفض من مربّع التفاصيل (بسبب يصل للعضو)
        let allowsApprove = flow.map(adminRequestVM.canExecuteApproval) ?? canApprove(forTab ?? selectedTab)
        let allowsReject = flow == nil && canReject(forTab ?? selectedTab)
        let waitingForMe = flow.map(adminRequestVM.isApprovalWaitingForMe) ?? false
        // خطّ الحالة على طرف البطاقة: متأخر/متصعّد أحمر، مستعجل كهرماني
        let stripe: Color? = flow.flatMap { f in
            (f.isLate || f.isEscalated) ? DS.Color.error : f.isUrgent ? DS.Color.warning : nil
        }
        let cardShape = RoundedRectangle(cornerRadius: DS.Hub.tileRadius, style: .continuous)
        // «لحظة نجاح» (الدفعة ١٠): الموافقة من البطاقة أو بالسحب تُظهر «تمت الموافقة» — إلا «ربط» طلب الانضمام (يفتح مربّعه)
        let tab = forTab ?? selectedTab
        let approve: (() -> Void)? = onApprove.map { work in
            guard tab != .joinRequests else { return work }
            let title = flow != nil ? L10n.t("تم التنفيذ", "Carried out")
                : tab == .children ? L10n.t("تم التأكيد", "Confirmed") : L10n.t("تمت الموافقة", "Approved")
            return { work(); AdminApprovalMoment.after(adminRequestVM, title: title) }
        }
        // المحتوى — قابل للنقر، يفتح تفاصيل الطلب (وفي وضع التحديد يحدّده)
        return Group {
            if visible {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Button {
                        if isSelectMode {
                            withAnimation(DS.Anim.snappy) {
                                if selectedIds.contains(id) { selectedIds.remove(id) }
                                else { selectedIds.insert(id) }
                            }
                        } else {
                            onTap()
                        }
                    } label: {
                        HStack(alignment: .center, spacing: DS.Spacing.sm) {
                            if isSelectMode {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .dsGlyph(DS.Glyph.xxl, weight: .regular)
                                    .foregroundColor(isSelected ? AppSection.admin.ink : DS.Color.textTertiary)
                                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                                    .accessibilityHidden(true)
                            }
                            content()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            // سهم — إشارة إن البطاقة تفتح التفاصيل (خارج وضع التحديد)
                            if !isSelectMode {
                                DSChevron()
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DSCardPressStyle())
                    .accessibilityAddTraits(isSelected ? .isSelected : [])

                    // «من أين وصل» (العيّنة ١٥): مسار الطلب + الجهاز والنسخة + نوع التنفيذ — عرض فقط، والضغط كالبطاقة
                    if let origin = rowOrigin(id) {
                        Button {
                            if isSelectMode {
                                withAnimation(DS.Anim.snappy) {
                                    if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
                                }
                            } else {
                                onTap()
                            }
                        } label: {
                            AnyView(AdminRequestCardOrigin(origin: origin))
                        }
                        .buttonStyle(DSCardPressStyle())
                    }

                    // «مسار الموافقات»: شريط المراحل الخمس + المرحلة ومن عنده + شارات الأولوية والمهلة
                    if let flow {
                        cardFlowStrip(flow, waitingForMe: waitingForMe)
                    }

                    // أزرار البطاقة — نفس إجراءات السحب تماماً (والمسار: يفتح المربّع حيث خطواته)
                    if !isSelectMode {
                        cardActions(flow: flow, waitingForMe: waitingForMe,
                                    allowsApprove: allowsApprove, allowsReject: allowsReject,
                                    approveLabel: approveLabel, approveIcon: approveIcon,
                                    approveTint: approveTint, softReject: softReject,
                                    onApprove: approve, onReject: onReject, onTap: onTap)
                    }
                }
                .padding(DS.Spacing.md)
                .dsCard(padding: nil, radius: DS.Hub.tileRadius)
                .overlay {
                    if let stripe {
                        cardShape
                            .fill(Color.clear)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(stripe).frame(width: DS.Hub.stripeWidth)
                            }
                            .clipShape(cardShape)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .overlay {
                    if isSelected {
                        cardShape
                            .fill(AppSection.admin.ink.opacity(DS.Opacity.tintFillSoft))
                            .overlay(cardShape.strokeBorder(AppSection.admin.ink.opacity(DS.Opacity.selectedStroke),
                                                            lineWidth: DS.Border.widthBold))
                            .allowsHitTesting(false)
                    }
                }
                .dsCardCascade(2, appeared: rowsAppeared)
                .onAppear {
                    guard !rowsAppeared else { return }
                    DispatchQueue.main.async { rowsAppeared = true }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: DS.Spacing.xsm, leading: DS.Spacing.lg, bottom: DS.Spacing.xsm, trailing: DS.Spacing.lg))
                .modifier(RequestSwipeActions(
                    enabled: !isSelectMode && (onApprove != nil || onReject != nil),
                    approve: allowsApprove ? approve : nil,
                    approveLabel: approveLabel ?? L10n.t("موافقة", "Approve"),
                    approveIcon: approveIcon, approveColor: approveColor,
                    reject: allowsReject ? onReject : nil,
                    delete: authVM.canDeleteMembers ? onDelete : nil,
                    more: onTap))
            }
        }
    }

    /// شريط المسار داخل البطاقة: المراحل (المنجز ذهبي) + المرحلة · من عنده، ثم شارات مستعجل/بانتظارك/متأخر
    private func cardFlowStrip(_ flow: ApprovalSnapshot, waitingForMe: Bool) -> some View {
        let holder = adminRequestVM.approvalHolderLabel(flow)
        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            HStack(spacing: DS.Spacing.sm) {
                AdminStageTrack(done: flow.stage.trackerStep + 1)
                    .frame(maxWidth: DS.Hub.ringSide / 2)
                Text([flow.stage.title, holder].compactMap { $0 }.joined(separator: " · "))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if flow.isUrgent || waitingForMe || flow.isLate || flow.isEscalated || flow.fastTrack {
                ChangedWordsFlow(spacing: DS.Spacing.xs) {
                    if flow.isUrgent {
                        DSStatusChip(text: L10n.t("عاجل", "Urgent"), icon: "flame.fill", tint: DS.Color.warning, size: .mini)
                    }
                    if waitingForMe {
                        DSStatusChip(text: L10n.t("بانتظار قرارك", "Waiting for you"), icon: "bell.badge.fill",
                                     tint: DS.Color.accent, size: .mini)
                    }
                    if flow.isEscalated {
                        DSStatusChip(text: L10n.t("تصعّد", "Escalated"), icon: "arrow.up.forward.circle.fill",
                                     tint: DS.Color.error, size: .mini)
                    } else if flow.isLate {
                        DSStatusChip(text: AdminTodayText.late(flow), icon: "clock", tint: DS.Color.error, size: .mini)
                    }
                    if flow.fastTrack {
                        DSStatusChip(text: L10n.t("مسار سريع", "Fast track"), icon: "bolt.fill", tint: DS.Color.info, size: .mini)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// أزرار البطاقة: «رفض» (لمن يملكه) · «التفاصيل» · الموافقة — وطلب في المسار ينتظرك: زرّ يفتح مربّعه
    @ViewBuilder
    private func cardActions(flow: ApprovalSnapshot?, waitingForMe: Bool, allowsApprove: Bool, allowsReject: Bool,
                             approveLabel: String?, approveIcon: String,
                             approveTint: Color? = nil, softReject: Bool = false,
                             onApprove: (() -> Void)?, onReject: (() -> Void)?,
                             onTap: @escaping () -> Void) -> some View {
        let canReject = allowsReject && onReject != nil
        let canApprove = allowsApprove && onApprove != nil
        let opensFlow = flow != nil && !canApprove && waitingForMe
        if canReject || canApprove || opensFlow {
            // أزرار الطلبات على التصميم الجديد (طلب المالك ٢٠٢٦-١١-١١) بالمقاس المدمج: الموافقة كحلية ·
            // «التفاصيل» رمادية فاتحة · «رفض» دائرة حمراء (`DSDecisionRow`) — نفس الإجراءات والصلاحيات
            DSDecisionRow(items: {
                var items: [DSDecisionItem] = []
                if opensFlow, let flow {
                    items.append(DSDecisionItem(id: "flow", title: flowActionTitle(flow), kind: .primary, action: onTap))
                } else {
                    if canApprove, let onApprove {
                        items.append(DSDecisionItem(id: "approve", title: approveLabel ?? L10n.t("موافقة", "Approve"),
                                                    kind: .primary, tint: approveTint, action: onApprove))
                    }
                    items.append(DSDecisionItem(id: "details", title: L10n.t("التفاصيل", "Details"), action: onTap))
                }
                if canReject, let onReject {
                    items.append(DSDecisionItem(id: "reject", title: L10n.t("رفض", "Reject"), icon: "xmark",
                                                kind: .destructive, tint: DS.Color.reject, soft: softReject,
                                                action: onReject))
                }
                return items
            }(), size: .compact)
        }
    }

    /// زرّ البطاقة لطلب في المسار ينتظرك — يفتح مربّعه حيث خطوة مرحلته
    private func flowActionTitle(_ flow: ApprovalSnapshot) -> String {
        switch flow.stage {
        case .review:  return L10n.t("راجع وارفع للمدير", "Review & send up")
        case .approve: return L10n.t("اعتماد", "Approve")
        case .execute: return L10n.t("تنفيذ", "Carry out")
        case .info:    return L10n.t("فتح الطلب", "Open request")
        }
    }

    /// عدد ما ستحاوله العملية الجماعية (بعد مسار الموافقات ومجال الدور) — لعرض «تم قبول N من M»
    private func bulkAttemptCount(approving: Bool) -> Int {
        let ids = approvalScopedIds(Array(selectedIds), approving: approving)
        guard selectedTab == .all else { return ids.count }
        let scope = idsInRoleScope(approving: approving)
        return ids.filter { scope.contains($0) }.count
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

    private func bulkApproveSelected() async -> Int {
        let ids = approvalScopedIds(Array(selectedIds), approving: true)
        var count = 0
        // مجال الدور (ب-٧): لا موافقة جماعية على تبويب ليس من صلاحيته
        guard selectedTab == .all || canApprove(selectedTab) else { return 0 }
        switch selectedTab {
        case .all:
            // في وضع "الكل": نمشي عبر كل القوائم بنفس الترتيب ونوافق على كل ID مطابق
            count = await bulkApproveAcrossAllTypes(ids: ids)
        case .joinRequests:
            return await adminRequestVM.bulkApproveJoinRequests(memberIds: ids)
        case .news:
            for id in ids {
                if let post = newsVM.pendingNewsRequests.first(where: { $0.id == id }) {
                    await newsVM.approveNewsPost(postId: post.id)
                    count += 1
                }
            }
        case .reports:
            for id in ids {
                if let req = adminRequestVM.newsReportRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.approveNewsReport(request: req)
                    if await adminRequestVM.awaitDecision(req.id) { count += 1 }
                }
            }
        case .phone:
            for id in ids {
                if let req = adminRequestVM.phoneChangeRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.approvePhoneChangeRequest(request: req)
                    if await adminRequestVM.awaitDecision(req.id) { count += 1 }
                }
            }
        case .nameChange:
            for id in ids {
                if let req = adminRequestVM.nameChangeRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.approveNameChangeRequest(request: req)
                    if await adminRequestVM.awaitDecision(req.id) { count += 1 }
                }
            }
        case .diwaniya:
            if let adminId = authVM.currentUser?.id {
                for id in ids {
                    if let d = diwaniyaVM.pendingDiwaniyas.first(where: { $0.id == id }) {
                        await diwaniyaVM.approveDiwaniya(id: d.id, adminId: adminId)
                        count += 1
                    }
                }
            }
        case .deceased:
            for id in ids {
                if let req = adminRequestVM.deceasedRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.approveDeceasedRequest(request: req)
                    if await adminRequestVM.awaitDecision(req.id) { count += 1 }
                }
            }
        case .children:
            for id in ids {
                if let req = adminRequestVM.childAddRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.acknowledgeChildAddRequest(request: req)
                    if await adminRequestVM.awaitDecision(req.id) { count += 1 }
                }
            }
        case .photos:
            for id in ids {
                if let req = adminRequestVM.photoSuggestionRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.approvePhotoSuggestion(request: req)
                    if await adminRequestVM.awaitDecision(req.id) { count += 1 }
                }
            }
        case .projects:
            if let adminId = authVM.currentUser?.id {
                for id in ids {
                    if let proj = projectsVM.pendingProjects.first(where: { $0.id == id }) {
                        await projectsVM.approveProject(id: proj.id, approvedBy: adminId)
                        count += 1
                    }
                }
            }
        case .archive:
            for id in ids {
                if let item = pendingArchiveItems.first(where: { $0.id == id }) {
                    await archiveVM.approveItem(item)
                    count += 1
                }
            }
        case .treeAdd, .treeEditName, .treeEditPhone, .treeEditBirth, .treeDeceased, .treeAddDeathDate, .treeAddPhoto, .treeDelete, .treeOther:
            for id in ids {
                if let req = adminRequestVM.treeEditRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.approveTreeEditRequest(request: req)
                    if await adminRequestVM.awaitDecision(req.id) { count += 1 }
                }
            }
        }
        return count
    }

    private func bulkRejectSelected() async -> Int {
        let ids = approvalScopedIds(Array(selectedIds), approving: false)
        var count = 0
        // مجال الدور (ب-٧): لا رفض جماعي على تبويب ليس من صلاحيته
        guard selectedTab == .all || canReject(selectedTab) else { return 0 }
        switch selectedTab {
        case .all:
            count = await bulkRejectAcrossAllTypes(ids: ids)
        case .joinRequests:
            for id in ids {
                if await adminRequestVM.rejectOrDeleteMember(memberId: id) { count += 1 }
            }
        case .news:
            for id in ids {
                if let post = newsVM.pendingNewsRequests.first(where: { $0.id == id }) {
                    await newsVM.rejectNewsPost(postId: post.id)
                    count += 1
                }
            }
        case .reports:
            for id in ids {
                if let req = adminRequestVM.newsReportRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.rejectNewsReport(request: req)
                    if await adminRequestVM.awaitDecision(req.id) { count += 1 }
                }
            }
        case .phone:
            for id in ids {
                if let req = adminRequestVM.phoneChangeRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.rejectPhoneChangeRequest(request: req)
                    if await adminRequestVM.awaitDecision(req.id) { count += 1 }
                }
            }
        case .nameChange:
            for id in ids {
                if let req = adminRequestVM.nameChangeRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.rejectNameChangeRequest(request: req)
                    if await adminRequestVM.awaitDecision(req.id) { count += 1 }
                }
            }
        case .diwaniya:
            for id in ids {
                if let d = diwaniyaVM.pendingDiwaniyas.first(where: { $0.id == id }) {
                    await diwaniyaVM.rejectDiwaniya(id: d.id)
                    count += 1
                }
            }
        case .deceased:
            for id in ids {
                if let req = adminRequestVM.deceasedRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.rejectDeceasedRequest(request: req)
                    if await adminRequestVM.awaitDecision(req.id) { count += 1 }
                }
            }
        case .children:
            for id in ids {
                if let req = adminRequestVM.childAddRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.rejectChildAddRequest(request: req)
                    if await adminRequestVM.awaitDecision(req.id) { count += 1 }
                }
            }
        case .photos:
            for id in ids {
                if let req = adminRequestVM.photoSuggestionRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.rejectPhotoSuggestion(request: req)
                    if await adminRequestVM.awaitDecision(req.id) { count += 1 }
                }
            }
        case .projects:
            for id in ids {
                if projectsVM.pendingProjects.contains(where: { $0.id == id }) {
                    await projectsVM.rejectProject(id: id)
                    count += 1
                }
            }
        case .archive:
            for id in ids {
                if let item = pendingArchiveItems.first(where: { $0.id == id }) {
                    await archiveVM.rejectItem(item)
                    count += 1
                }
            }
        case .treeAdd, .treeEditName, .treeEditPhone, .treeEditBirth, .treeDeceased, .treeAddDeathDate, .treeAddPhoto, .treeDelete, .treeOther:
            for id in ids {
                if let req = adminRequestVM.treeEditRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.rejectTreeEditRequest(request: req, reason: nil)
                    if await adminRequestVM.awaitDecision(req.id) { count += 1 }
                }
            }
        }
        return count
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

    // MARK: - «مسار الموافقات ٢»: الفلتر والتقرير (طلب المالك ٢٠٢٦-١٠-١٦ مسار الموافقات ٢)

    /// تابات بلا مسار (المحتوى يعتمده المدير مباشرة) — لا فلتر فيها
    private static let nonFlowTabs: Set<RequestTab> = [.news, .diwaniya, .projects, .archive]

    /// الفلتر لأنواع المسار و«الكل» فقط (لا صحة الشجرة ولا المحتوى)، والمسار شغّال
    private func tabSupportsApprovalFilter(_ tab: RequestTab) -> Bool {
        adminRequestVM.approvalsWorkflowOn && !Self.nonFlowTabs.contains(tab)
    }

    private var isApprovalFilterActive: Bool {
        approvalFilter != .all && tabSupportsApprovalFilter(selectedTab)
    }

    /// الصف يظهر مع الفلتر الحالي — ما ليس في المسار لا يطابق «بانتظارك/مستعجل/متأخر»
    private func passesApprovalFilter(_ id: UUID, tab: RequestTab, flow: ApprovalSnapshot? = nil) -> Bool {
        guard approvalFilter != .all, tabSupportsApprovalFilter(tab) else { return true }
        guard let flow = flow ?? adminRequestVM.approvalSnapshot(forRowId: id) else { return false }
        return adminRequestVM.approvalMatches(flow, filter: approvalFilter)
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

    /// قائمة طلبات الشجرة لإجراء معيّن (الموافقة/الرفض يستخدمان APIs الخاصة بالشجرة).
    @ViewBuilder
    private func treeEditList(action: TreeEditAction, color: Color) -> some View {
        ForEach(adminRequestVM.approvalOrdered(treeEdits(action: action))) { request in
            selectableRow(
                id: request.id,
                accentColor: color,
                onApprove: { Task { await adminRequestVM.approveTreeEditRequest(request: request) } },
                onReject: { swipeRejectReason = ""; swipeRejectDetail = .treeEdit(request, action) },
                onTap: { selectedDetail = .treeEdit(request, action) }
            ) {
                treeEditRow(request: request, action: action, color: color)
            }
        }
    }

    /// صف موحّد لطلبات الشجرة — الإجراء واسم العضو، ثم القيمة الجديدة والوقت.
    private func treeEditRow(request: AdminRequest, action: TreeEditAction, color: Color) -> some View {
        let payload = request.treeEditPayload
        // تعديل الاسم: الجزء الذي تغيّر فقط «الصايغ ← المحمدعلي» — الاسم الكامل مكتوب في العنوان الفرعي فوقه
        // (طلب المالك ٢٠٢٦-١١-١٧ «في تكرار بالأسماء»)
        let nameDiff = action == .editName
            ? Self.nameDiff(old: request.member?.displayFullName ?? payload?.targetMemberName, new: payload?.newName) : nil
        let newDisplay = nameDiff.map { "\($0.old) ← \($0.new)" } ?? treeEditNewValue(payload: payload, action: action)
        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            // شجرة النساء: العنوان من نوعها الحقيقي (`displayAction`) والاسم اسم المرأة المعنيّة لا السجلّ المرتبط
            let shown = payload?.displayAction ?? action
            requestRowHeader(icon: shown.iconName,
                             tint: color,
                             title: L10n.t(shown.arabicLabel, shown.englishLabel),
                             subtitle: Self.womenSubjectName(payload) ?? request.member?.displayFullName ?? L10n.t("عضو", "Member"),
                             kind: AdminRequestKind.of(request)) {
                pendingChip(Self.requestDate(request.createdAt))
            }

            // §10: «مقدّم الطلب: …» بشريحة نوعه — حين لا يكون هو المعني بالطلب (العنوان الفرعي اسم المعني)
            let requester = memberVM.member(byId: request.requesterId)
            let target = payload?.targetMemberId.flatMap(UUID.init(uuidString:)) ?? request.memberId
            if let requester, requester.id != target || action == .add {
                rowExtras {
                    requesterLine(requester)
                }
            }
            if newDisplay != nil || request.createdAt != nil {
                rowExtras {
                    // قيمة جديدة حسب الإجراء
                    if let newDisplay {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "arrow.forward.circle.fill")
                                .dsGlyph(DS.Glyph.xs)
                                .foregroundColor(DS.Color.primary)
                                .accessibilityHidden(true)
                            Text(nameDiff != nil ? L10n.t("التغيير:", "Change:") : L10n.t("القيمة الجديدة:", "New:"))
                                .dsFont(.footnote)
                                .foregroundColor(DS.Color.textTertiary)
                            Text(newDisplay)
                                .dsFieldFont(.adminRowSubtitle)
                                .foregroundColor(DS.Color.fieldLabel)
                                .lineLimit(1)
                        }
                    }
                    if let date = request.createdAt {
                        metaItem("clock", formatRegistrationDate(date))
                    }
                }
            }
        }
    }

    /// عنصر موحّد لوضع "الكل" — يجمع كل الأنواع في قائمة واحدة لترتيبها زمنياً.
    private enum AllItem: Identifiable {
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

    /// محتوى تاب "الكل" — كل الأنواع مدمجة ومرتّبة حسب الوقت (الأحدث أولاً).
    /// «الكل» مفلتر بمجال الدور — وإن لم يبقَ فيه شيء تظهر بطاقة «لا توجد طلبات» بدل فراغ.
    @ViewBuilder
    private func allRequestsContent() -> some View {
        let items = displayedAllItems
        if items.isEmpty && isSearching {
            DSEmptyView(L10n.t("لا نتائج", "No results"),
                        message: L10n.t("لا طلب يطابق «\(searchText)»", "No request matches “\(searchText)”"),
                        style: .card)
                .padding(.top, DS.Spacing.xs)
                .reviewListRow()
        } else if items.isEmpty && sourceFilter != .all {
            DSEmptyView(L10n.t("لا طلبات هنا", "Nothing here"),
                        message: L10n.t("لا توجد طلبات من هذا المصدر حالياً.", "No request from this source right now."),
                        style: .card)
                .padding(.top, DS.Spacing.xs)
                .reviewListRow()
        } else if items.isEmpty {
            emptyState
                .padding(.top, DS.Spacing.xs)
                .reviewListRow()
        } else {
            ForEach(items) { item in
                allItemRow(item)
            }
        }
    }

    @ViewBuilder
    private func allItemRow(_ item: AllItem) -> some View {
        switch item {
        case .join(let member):
            selectableRow(
                id: member.id, forTab: .joinRequests, accentColor: RequestTab.joinRequests.color,
                approveLabel: joinApproveLabel(member), approveIcon: "link.badge.plus",
                approveTint: DS.Color.success, softReject: true,
                onApprove: { joinApprove(member) },
                onReject: { swipeRejectReason = ""; swipeRejectDetail = .join(member) },
                onTap: { selectedDetail = .join(member) }
            ) { joinRequestRow(for: member) }
        case .news(let post):
            selectableRow(
                id: post.id, forTab: .news, accentColor: RequestTab.news.color,
                onApprove: { Task { await newsVM.approveNewsPost(postId: post.id) } },
                onReject: { swipeRejectReason = ""; swipeRejectDetail = .news(post) },
                onDelete: { swipeDeleteDetail = .news(post) },
                onTap: { selectedDetail = .news(post) }
            ) { newsRow(for: post) }
        case .report(let request):
            selectableRow(
                id: request.id, forTab: .reports, accentColor: RequestTab.reports.color,
                onApprove: { Task { await adminRequestVM.approveNewsReport(request: request) } },
                onReject: { swipeRejectReason = ""; swipeRejectDetail = .report(request) },
                onDelete: { swipeDeleteDetail = .report(request) },
                onTap: { selectedDetail = .report(request) }
            ) { reportRow(for: request) }
        case .phone(let request):
            selectableRow(
                id: request.id, forTab: .phone, accentColor: RequestTab.phone.color,
                onApprove: { Task { await adminRequestVM.approvePhoneChangeRequest(request: request) } },
                onReject: { swipeRejectReason = ""; swipeRejectDetail = .phone(request) },
                onDelete: { swipeDeleteDetail = .phone(request) },
                onTap: { selectedDetail = .phone(request) }
            ) { phoneRow(for: request) }
        case .nameChange(let request):
            selectableRow(
                id: request.id, forTab: .nameChange, accentColor: RequestTab.nameChange.color,
                onApprove: { Task { await adminRequestVM.approveNameChangeRequest(request: request) } },
                onReject: { swipeRejectReason = ""; swipeRejectDetail = .nameChange(request) },
                onDelete: { swipeDeleteDetail = .nameChange(request) },
                onTap: { selectedDetail = .nameChange(request) }
            ) { nameChangeRow(for: request) }
        case .diwaniya(let diwaniya):
            selectableRow(
                id: diwaniya.id, forTab: .diwaniya, accentColor: RequestTab.diwaniya.color,
                onApprove: {
                    if let adminId = authVM.currentUser?.id {
                        Task { await diwaniyaVM.approveDiwaniya(id: diwaniya.id, adminId: adminId) }
                    }
                },
                onReject: { swipeRejectReason = ""; swipeRejectDetail = .diwaniya(diwaniya) },
                onDelete: { swipeDeleteDetail = .diwaniya(diwaniya) },
                onTap: { selectedDetail = .diwaniya(diwaniya) }
            ) { diwaniyaRow(for: diwaniya) }
        case .deceased(let request):
            selectableRow(
                id: request.id, forTab: .deceased, accentColor: RequestTab.deceased.color,
                onApprove: { Task { await adminRequestVM.approveDeceasedRequest(request: request) } },
                onReject: { swipeRejectReason = ""; swipeRejectDetail = .deceased(request) },
                onDelete: { swipeDeleteDetail = .deceased(request) },
                onTap: { selectedDetail = .deceased(request) }
            ) { deceasedRow(for: request) }
        case .child(let request):
            selectableRow(
                id: request.id, forTab: .children, accentColor: RequestTab.children.color,
                approveLabel: L10n.t("تأكيد", "Confirm"),
                onApprove: { Task { await adminRequestVM.acknowledgeChildAddRequest(request: request) } },
                onReject: { swipeRejectReason = ""; swipeRejectDetail = .child(request) },
                onDelete: { swipeDeleteDetail = .child(request) },
                onTap: { selectedDetail = .child(request) }
            ) { childRow(for: request) }
        case .photo(let request):
            selectableRow(
                id: request.id, forTab: .photos, accentColor: RequestTab.photos.color,
                onApprove: { Task { await adminRequestVM.approvePhotoSuggestion(request: request) } },
                onReject: { swipeRejectReason = ""; swipeRejectDetail = .photo(request) },
                onDelete: { swipeDeleteDetail = .photo(request) },
                onTap: { selectedDetail = .photo(request) }
            ) { photoRow(for: request) }
        case .project(let project):
            selectableRow(
                id: project.id, forTab: .projects, accentColor: RequestTab.projects.color,
                onApprove: {
                    if let adminId = authVM.currentUser?.id {
                        Task { await projectsVM.approveProject(id: project.id, approvedBy: adminId) }
                    }
                },
                onReject: { swipeRejectReason = ""; swipeRejectDetail = .project(project) },
                onDelete: { swipeDeleteDetail = .project(project) },
                onTap: { selectedDetail = .project(project) }
            ) { projectRow(for: project) }
        case .archive(let item):
            selectableRow(
                id: item.id, forTab: .archive, accentColor: RequestTab.archive.color,
                onApprove: { Task { await archiveVM.approveItem(item) } },
                onReject: { swipeRejectReason = ""; swipeRejectDetail = .archive(item) },
                onDelete: { swipeDeleteDetail = .archive(item) },
                onTap: { selectedDetail = .archive(item) }
            ) { archiveRow(for: item) }
        case .treeEdit(let request, let action):
            let color = treeEditColor(action)
            selectableRow(
                id: request.id, forTab: .treeOther, accentColor: color,
                onApprove: { Task { await adminRequestVM.approveTreeEditRequest(request: request) } },
                onReject: { swipeRejectReason = ""; swipeRejectDetail = .treeEdit(request, action) },
                onDelete: { swipeDeleteDetail = .treeEdit(request, action) },
                onTap: { selectedDetail = .treeEdit(request, action) }
            ) { treeEditRow(request: request, action: action, color: color) }
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

    // MARK: - Empty State

    /// بطاقة «لا توجد طلبات» الموحّدة — للقائمة كلها أو للتبويب المختار
    private var emptyState: some View {
        DSEmptyView(L10n.t("لا توجد طلبات معلقة", "No pending requests"),
                    message: (totalCount == 0 || selectedTab == .all)
                        ? L10n.t("جميع الطلبات متابَعة، ولا يوجد ما ينتظر القرار",
                                 "All caught up — nothing is awaiting your decision")
                        : L10n.t("لا شيء في «\(selectedTab.title)» الآن",
                                 "Nothing in \(selectedTab.title) right now"),
                    tint: DS.Color.success, style: .compact)
            .padding(.vertical, DS.Spacing.xl)
    }

    // MARK: - Join Request Row

    /// مطابقة في الشجرة (`NameMatcher.linkSuggestions`): `matchCount` عمق التطابق بالترتيب (٢ = الأول + الأب)،
    /// `score` نسبته ٠…١٠٠ من `total` أجزاء اسم المتقدّم (بلا العائلة)، `fuzzy` لم يعد يُستعمل (صفر)
    typealias JoinMatch = (member: FamilyMember, matchCount: Int, matchedParts: [String], isRegistrationMatch: Bool,
                           score: Int, total: Int, fuzzy: Int)

    /// صف طلب الانضمام — أنيق ومحترم (طلب المالك ٢٠٢٦-١٠-٠١): صورة بأول حرف بحلقة لون الحالة،
    /// الاسم عنواناً، سطر حالة هادئ (مطابقة/اسم جديد · من الموقع)، عمر الطلب نصاً خفيفاً،
    /// ثم الرقم وزر واتساب دائري، وأقرب تطابق فقط. التفاصيل الكاملة داخل الطلب.
    private func joinRequestRow(for member: FamilyMember) -> some View {
        // العيّنة ١٨ (موافقة المالك ٢٠٢٦-١١-١٨): الرأس · اتصال/واتساب · «الأرجح» بنسبته وسلسلته، أو «لا مطابقة» بالأب
        // المحتمل، أو خطوات شجرة النساء — `JoinRequestCard.swift`. الأزرار (ربط · التفاصيل · ×) من `cardActions`
        let info = joinCardInfo(for: member)
        let ring = member.isFemale ? DS.Color.female : (info.pick != nil ? DS.Color.success : DS.Color.warning)
        return AnyView(JoinRequestCard(
            info: info,
            avatar: AnyView(joinPersonAvatar(member, ring: ring, size: Self.joinAvatar)),
            onSelect: { joinPicks[member.id] = $0 },
            onToggleWeak: {
                if expandedMatchMembers.contains(member.id) { expandedMatchMembers.remove(member.id) }
                else { expandedMatchMembers.insert(member.id) }
            },
            onOpenMatches: { joinMatchesFor = member }))
    }

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

    /// سطر حالة هادئ بلا شارات: «٣ مطابقات في الشجرة» أو «اسم جديد» · «من الموقع»
    private func joinStatusLine(matches: Int, fromWeb: Bool) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: matches > 0 ? "checkmark.seal.fill" : "sparkles")
                .dsGlyph(DS.Glyph.xsCompact)
                .accessibilityHidden(true)
            Text(matches > 0 ? L10n.t("\(matches) مطابقة في الشجرة", "\(matches) in the tree")
                             : L10n.t("اسم جديد", "New name"))
            if fromWeb {
                Text("·").foregroundColor(DS.Color.textTertiary)
                Image(systemName: "globe")
                    .dsGlyph(DS.Glyph.xsCompact)
                    .foregroundColor(DS.Color.info.dsReadableGlyph)
                    .accessibilityHidden(true)
                Text(L10n.t("من الموقع", "From website"))
                    .foregroundColor(DS.Color.info.dsReadableGlyph)
            }
        }
        .dsFont(.caption)
        .foregroundColor(matches > 0 ? DS.Color.success.dsReadableGlyph : DS.Color.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
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

    /// زر تواصل (واتساب/اتصال): قرص الحالة المجسّم بلون المعنى، بمساحة ضغط ٤٤ نقطة
    /// «ج»: الرقم نفسه رابط اتصال بلون التواصل — منطقة اللمس ٤٤ بلا تكبير السطر
    @ViewBuilder
    private func phoneCallLink(_ phone: String, font: DS.TextRole = .chip) -> some View {
        let shown = KuwaitPhone.display(phone)
        if let tel = KuwaitPhone.telURL(phone) {
            let pad = (DS.Icon.tapTarget - DS.Icon.row) / 2
            Button { UIApplication.shared.open(tel) } label: {
                HStack(spacing: DS.Spacing.xxs) {
                    Image(dsSymbol: "phone.fill")
                        .dsGlyph(DS.Glyph.micro, weight: .semibold)
                        .accessibilityHidden(true)
                    Text(verbatim: shown)
                        .dsFont(font)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundColor(DS.Color.sea)
                // إطار على الرقم (طلب المالك ٢٠٢٦-١١-١٣ «خلّ على الرقم إطار»)
                .padding(.horizontal, DS.Spacing.sm)
                .frame(minHeight: DS.Icon.row)
                .overlay(Capsule().strokeBorder(DS.Color.sea, lineWidth: DS.Border.widthBold))
                .padding(.vertical, pad)
                .contentShape(Rectangle())
                .padding(.vertical, -pad)
            }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityLabel(L10n.t("اتصال بـ \(shown)", "Call \(shown)"))
        } else {
            metaItem("phone.fill", shown, color: DS.Color.fieldValue)
        }
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

    /// (غير مستخدم) تجميع التطابقات حسب اسم البحث
    func groupedMatches(for member: FamilyMember) -> [(namePart: String, members: [FamilyMember])] {
        let newParts = member.fullName
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let existingMembers = memberVM.allMembers.filter { $0.role != .pending && $0.id != member.id }
        var groups: [(namePart: String, members: [FamilyMember])] = []

        for part in newParts {
            guard part.count >= 2 else { continue }
            let matched = existingMembers.filter { existing in
                let firstName = existing.fullName.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
                return firstName.localizedCaseInsensitiveCompare(part) == .orderedSame
            }
            if !matched.isEmpty {
                groups.append((namePart: part, members: Array(matched.prefix(5))))
            }
        }

        return groups
    }

    // MARK: - News Row

    private func newsRow(for post: NewsPost) -> some View {
        let tint = newsTypeColor(post.type)
        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            requestRowHeader(icon: "newspaper.fill",
                             tint: tint,
                             title: L10n.t("خبر", "News"),
                             subtitle: memberVM.displayName(id: post.author_id, stored: post.author_name, .full)) {
                pendingChip(post.timestamp)
            }

            rowExtras {
                previewText(post.content)
                // النوع + التاريخ + إشارة صور إن وُجدت
                HStack(spacing: DS.Spacing.sm) {
                    DSStatusChip(text: post.type, tint: tint)
                    metaItem("clock", formatRegistrationDate(String(post.created_at)))
                    if !post.mediaURLs.isEmpty {
                        metaItem("photo.fill", "\(post.mediaURLs.count)")
                    }
                }
            }
        }
    }

    // MARK: - Report Row

    private func reportRow(for request: AdminRequest) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            requestRowHeader(icon: "exclamationmark.triangle.fill",
                             tint: DS.Color.error,
                             title: L10n.t("بلاغ", "Report"),
                             subtitle: request.member.map { L10n.t("عن: \($0.displayFullName)", "About: \($0.displayFullName)") }) {
                pendingChip(Self.requestDate(request.createdAt))
            }

            rowExtras {
                previewText(request.details ?? L10n.t("بلاغ بدون تفاصيل", "Report without details"))
                // التاريخ تحت
                metaItem("clock", request.createdAt.map { formatRegistrationDate($0) } ?? "—")
            }
        }
    }

    // MARK: - Phone Row

    private func phoneRow(for request: PhoneChangeRequest) -> some View {
        let currentPhone = KuwaitPhone.display(request.member?.phoneNumber)
        let newPhone = KuwaitPhone.display(request.newValue)
        let memberName = request.member?.displayFullName ?? "Member"

        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            requestRowHeader(icon: "phone.arrow.right",
                             tint: AppSection.admin.ink,
                             title: L10n.t("طلب تغيير رقم", "Phone Change"),
                             subtitle: memberName, kind: .edit) {
                pendingChip(Self.requestDate(request.createdAt))
            }

            rowExtras {
                // §10: «مقدّم الطلب» حين لا يكون صاحب الرقم نفسه (سطر الاسم أعلاه)
                if let rid = request.requesterId, rid != request.memberId, let requester = memberVM.member(byId: rid) {
                    requesterLine(requester)
                }
                // سطر مقارنة مدمج: الحالي ← الجديد
                changeLine(old: currentPhone, new: newPhone)
                // التاريخ تحت
                if let createdAt = request.createdAt {
                    metaItem("clock", formatRegistrationDate(String(createdAt)))
                }
            }
        }
    }

    // MARK: - Diwaniya Row

    private func diwaniyaRow(for diwaniya: Diwaniya) -> some View {
        let schedule = diwaniya.scheduleText ?? ""
        let address = diwaniya.address ?? ""
        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            requestRowHeader(icon: "tent.fill",
                             tint: DS.Color.gridDiwaniya,
                             title: L10n.t("طلب ديوانية", "Diwaniya Request"),
                             subtitle: diwaniya.title) {
                pendingChip(nil)
            }

            if !schedule.isEmpty || !address.isEmpty {
                rowExtras {
                    if !schedule.isEmpty {
                        detailRow(icon: "calendar", text: schedule)
                    }
                    if !address.isEmpty {
                        detailRow(icon: "mappin.and.ellipse", text: address)
                    }
                }
            }
        }
    }

    // MARK: - Archive Row

    private func archiveRow(for item: ArchiveItem) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            // نوع المحتوى ظاهر قبل الموافقة (طلب المالك ٢٠٢٦-١١-٢٤): «صورة للمكتبة» / «ملف PDF للمكتبة» + الحجم
            requestRowHeader(icon: item.fileKindIcon,
                             tint: DS.Color.warning,
                             title: L10n.t("\(item.fileKindName) للمكتبة", "\(item.fileKindName) for the library"),
                             subtitle: item.title) {
                pendingChip(item.createdAt)
            }

            rowExtras {
                detailRow(icon: item.fileKindIcon, text: item.fileKindLine)
                detailRow(icon: item.categoryIcon, text: item.categoryDisplayName)
                if let year = item.year {
                    detailRow(icon: "calendar", text: "\(year)")
                }
            }
        }
    }

    // MARK: - Deceased Row

    private func deceasedRow(for request: AdminRequest) -> some View {
        let requester = memberVM.allMembers.first(where: { $0.id == request.requesterId })
        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            requestRowHeader(icon: "leaf.fill",
                             tint: DS.Color.error,
                             title: L10n.t("تسجيل وفاة", "Deceased"),
                             subtitle: L10n.t("لـ: \(request.member?.displayFullName ?? "عضو")",
                                              "For: \(request.member?.displayFullName ?? "Member")"),
                             kind: .edit) {
                pendingChip(Self.requestDate(request.createdAt))
            }

            rowExtras {
                // مقدّم الطلب هو صاحبه نفسه → لا يتكرّر (طلب المالك ٢٠٢٦-١٠-٠٧)
                if let requester, requester.id != request.memberId {
                    requesterLine(requester)
                }
                if let details = request.details, !details.isEmpty {
                    contentBlock(details)
                }
                // التاريخ تحت
                if let createdAt = request.createdAt {
                    metaItem("clock", formatRegistrationDate(String(createdAt)))
                }
            }
        }
    }

    // MARK: - Child Row

    private func childRow(for request: AdminRequest) -> some View {
        // مختصر (طلب المالك ٢٠٢٦-١١-٠٥): مَن أضاف مَن فقط — التفاصيل في مربّع الطلب
        let requester = memberVM.allMembers.first(where: { $0.id == request.requesterId })
        let father = request.member?.shortFullName ?? L10n.t("عضو", "Member")
        let child = request.newValue.flatMap(UUID.init(uuidString:)).flatMap { memberVM.member(byId: $0)?.firstName }
        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            requestRowHeader(icon: "person.badge.plus",
                             tint: DS.Color.info,
                             title: L10n.t("إضافة ابن", "Child Add"),
                             subtitle: child.map { L10n.t("\(father) أضاف ابنه \($0)", "\(father) added his son \($0)") }
                                ?? L10n.t("الأب: \(father)", "Father: \(father)"),
                             kind: .add) {
                pendingChip(Self.requestDate(request.createdAt))
            }

            // مقدّم الطلب غير الأب فقط
            if let requester, requester.id != request.memberId {
                rowExtras { requesterLine(requester) }
            }
        }
    }

    // MARK: - Photo Row

    private func photoRow(for request: AdminRequest) -> some View {
        let requester = memberVM.allMembers.first(where: { $0.id == request.requesterId })
        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            requestRowHeader(icon: "camera.badge.ellipsis",
                             tint: DS.Color.neonBlue,
                             title: L10n.t("اقتراح صورة", "Photo Suggestion"),
                             subtitle: L10n.t("لـ: \(request.member?.displayFullName ?? "عضو")",
                                              "For: \(request.member?.displayFullName ?? "Member")"),
                             kind: .edit) {
                pendingChip(Self.requestDate(request.createdAt))
            }

            rowExtras {
                // مقدّم الطلب هو صاحبه نفسه → لا يتكرّر (طلب المالك ٢٠٢٦-١٠-٠٧)
                if let requester, requester.id != request.memberId {
                    requesterLine(requester)
                }
                if let details = request.details, !details.isEmpty {
                    contentBlock(details)
                }
                HStack(spacing: DS.Spacing.sm) {
                    if let photoUrl = request.newValue, let url = URL(string: photoUrl) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable()
                                .scaledToFill()
                                .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        } placeholder: {
                            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                .fill(DS.Color.surface)
                                .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        }
                        .accessibilityHidden(true)
                    }

                    // التاريخ
                    if let createdAt = request.createdAt {
                        metaItem("clock", formatRegistrationDate(String(createdAt)))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Tree Edit Row

    // MARK: - Name Change Row

    private func nameChangeRow(for request: AdminRequest) -> some View {
        let isFamily = request.requestType == RequestType.familyChange.rawValue
        // تغيير العائلة: الاسم الكامل نفسه، والذي يتغيّر آخره فقط (طلب المالك)
        let baseName = request.member?.fullName ?? L10n.t("عضو", "Member")
        let currentName = isFamily
            ? FamilyNameCatalog.words(baseName, family: request.member?.familyName).joined(separator: " ")
            : baseName
        let newName = isFamily
            ? FamilyNameCatalog.words(baseName, family: request.newValue).joined(separator: " ")
            : (request.newValue ?? "—")
        let requester = memberVM.allMembers.first(where: { $0.id == request.requesterId })

        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            // الصف الأول: الأيقونة + نوع الطلب + الاسم الحالي + عمر الطلب
            requestRowHeader(icon: "rectangle.and.pencil.and.ellipsis",
                             tint: DS.Color.neonPurple,
                             title: isFamily ? L10n.t("تغيير العائلة", "Family Change") : L10n.t("تغيير اسم", "Name Change"),
                             subtitle: currentName, kind: .edit) {
                pendingChip(Self.requestDate(request.createdAt))
            }

            rowExtras {
                // مقدّم الطلب هو صاحبه نفسه → لا يتكرّر (طلب المالك ٢٠٢٦-١٠-٠٧)
                if let requester, requester.id != request.memberId {
                    requesterLine(requester)
                }
                // الاسم: الحالي ← الجديد (سطر مدمج)
                changeLine(old: nil, new: newName)
                // التاريخ تحت
                if let createdAt = request.createdAt {
                    metaItem("clock", formatRegistrationDate(String(createdAt)))
                }
            }
        }
    }

    // MARK: - Admin Name Edit Box
    /// تعديل الاسم قبل الموافقة — مربّع بمنتصف الشاشة بنفس تصميم المربّعات الموحّد
    /// (طلب المالك): رأس كحلي، الاسم الحالي ثم حقل الاسم المعدّل، و«موافقة» / «إلغاء» أسفله.
    private func adminNameEditSheet(request: AdminRequest) -> some View {
        DSComposer(
            title: L10n.t("تعديل الاسم", "Edit Name"),
            subtitle: L10n.t("يمكنك تعديل الاسم قبل الموافقة عليه.", "You can modify the name before approving."),
            icon: "rectangle.and.pencil.and.ellipsis",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("موافقة", "Approve"),
            actionIcon: "checkmark.circle.fill",
            canSubmit: !editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasUnsavedChanges: editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                != editedNameStart.trimmingCharacters(in: .whitespacesAndNewlines),
            onSubmit: {
                let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                Task {
                    var modifiedRequest = request
                    modifiedRequest.newValue = trimmed
                    await adminRequestVM.approveNameChangeRequest(request: modifiedRequest)
                    nameEditRequest = nil
                }
            },
            onCancel: { nameEditRequest = nil }
        ) {
            DSComposerSection(title: L10n.t("الاسم", "Name"),
                              icon: "person.fill",
                              tint: AppSection.admin.ink,
                              index: 0) {
                editBoxValueRow(icon: "person.fill",
                                label: L10n.t("الاسم الحالي", "Current Name"),
                                value: request.member?.displayFullName ?? "—",
                                tint: AppSection.admin.ink)
            }

            DSComposerSection(title: L10n.t("التعديل", "Edit"),
                              icon: "pencil",
                              tint: DS.Color.success,
                              index: 1) {
                DSComposerField(icon: "pencil",
                                label: L10n.t("الاسم المعدّل", "Modified Name"),
                                placeholder: L10n.t("اكتب الاسم الصحيح", "Enter correct name"),
                                text: $editedName,
                                tint: DS.Color.success)
            }
        }
        .onAppear { editedNameStart = editedName }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// صف قراءة فقط داخل مربّعي تعديل الاسم/الرقم — أيقونة الحقل + العنوان + القيمة
    private func editBoxValueRow(icon: String, label: String, value: String,
                                 tint: Color, valueColor: Color = DS.Color.fieldValue) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(label)
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(value)
                    .dsFieldFont(.fieldValue)
                    .foregroundColor(valueColor)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .dsRowBox()
        .accessibilityElement(children: .combine)   // «العنوان، القيمة» عنصراً واحداً
    }

    // MARK: - Admin Phone Edit Box
    /// تعديل الرقم قبل الموافقة — مربّع بمنتصف الشاشة بنفس تصميم المربّعات الموحّد
    /// (طلب المالك): الرقم الحالي والمطلوب، ثم حقل الرقم المعدّل، و«موافقة» / «إلغاء» أسفله.
    private func adminPhoneEditSheet(request: PhoneChangeRequest) -> some View {
        DSComposer(
            title: L10n.t("تعديل الرقم", "Edit Number"),
            subtitle: L10n.t("يمكنك تعديل الرقم قبل الموافقة عليه.", "You can modify the number before approving."),
            icon: "phone.badge.checkmark",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("موافقة", "Approve"),
            actionIcon: "checkmark.circle.fill",
            canSubmit: !editedPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasUnsavedChanges: editedPhone.trimmingCharacters(in: .whitespacesAndNewlines)
                != editedPhoneStart.trimmingCharacters(in: .whitespacesAndNewlines),
            onSubmit: {
                let trimmed = editedPhone.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                Task {
                    var modifiedRequest = request
                    modifiedRequest.newValue = trimmed
                    await adminRequestVM.approvePhoneChangeRequest(request: modifiedRequest)
                    phoneEditRequest = nil
                }
            },
            onCancel: { phoneEditRequest = nil }
        ) {
            DSComposerSection(title: L10n.t("رقم الهاتف", "Phone"),
                              icon: "phone.fill",
                              tint: AppSection.admin.ink,
                              index: 0) {
                editBoxValueRow(icon: "phone.fill",
                                label: L10n.t("الرقم الحالي", "Current number"),
                                value: KuwaitPhone.display(request.member?.phoneNumber),
                                tint: AppSection.admin.ink)
                editBoxValueRow(icon: "phone.arrow.right",
                                label: L10n.t("الرقم المطلوب", "Requested number"),
                                value: KuwaitPhone.display(request.newValue),
                                tint: DS.Color.success,
                                valueColor: DS.Color.success)
            }

            DSComposerSection(title: L10n.t("التعديل", "Edit"),
                              icon: "pencil",
                              tint: DS.Color.success,
                              index: 1) {
                DSComposerField(icon: "phone",
                                label: L10n.t("الرقم المعدّل", "Modified Number"),
                                placeholder: L10n.t("اكتب الرقم الصحيح", "Enter correct number"),
                                text: $editedPhone,
                                tint: DS.Color.success,
                                keyboard: .phonePad)
            }
        }
        .onAppear { editedPhoneStart = editedPhone }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Tree Edit Row

    // MARK: - Project Row

    private func projectRow(for project: Project) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                projectLogo(project)
                rowTitles(title: L10n.t("طلب مشروع", "Project Request"), subtitle: project.title)
                Spacer(minLength: 0)
                pendingChip(Self.requestDate(project.createdAt))
                    .fixedSize()
            }

            rowExtras {
                if let desc = project.description, !desc.isEmpty {
                    contentBlock(desc)
                }
                // التاريخ تحت
                if let date = project.createdAt {
                    let formatted = formatRegistrationDate(date)
                    metaItem("clock", L10n.t("أُضيف: \(formatted)", "Added: \(formatted)"))
                }
            }
        }
    }

    /// شعار المشروع بمقاس أيقونة الحقل — أو أيقونة الحقيبة إن لم يوجد
    @ViewBuilder
    private func projectLogo(_ project: Project) -> some View {
        if let logoUrl = project.logoUrl, let url = URL(string: logoUrl) {
            CachedAsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                DSFieldIcon(name: "briefcase.fill", tint: DS.Color.neonPurple)
            }
            .frame(width: DS.Icon.row, height: DS.Icon.row)
            .clipShape(RoundedRectangle(cornerRadius: DS.Icon.discRadius, style: .continuous))
            .accessibilityHidden(true)
        } else {
            DSFieldIcon(name: "briefcase.fill", tint: DS.Color.neonPurple)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Shared Components

    /// سطر معلومة بأيقونة صغيرة (الموعد، العنوان، القسم…) — Plex 12 بلون القيم
    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: DS.Spacing.xsm) {
            Image(dsSymbol: icon)
                .dsGlyph(DS.Glyph.xs, weight: .semibold)
                .foregroundColor(DS.Color.textTertiary)
                .frame(width: DS.Glyph.md)
                .accessibilityHidden(true)
            Text(text)
                .dsFieldFont(.adminRowSubtitle)
                .foregroundColor(DS.Color.fieldValue)
                .lineLimit(2)
        }
    }

    /// بلوك التفاصيل داخل الصف — عنوان صغير + النص (٣ أسطر) على بطاقة خفيفة
    private func contentBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(L10n.t("التفاصيل", "Details"))
                .dsFont(.badgeCompact)
                .foregroundColor(DS.Color.textTertiary)
            Text(text)
                .dsFieldFont(.adminRowSubtitle)
                .foregroundColor(DS.Color.fieldValue)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xsm)
        // البطاقة الواحدة (زواياها الصغيرة داخل الصف)
        .dsCard(padding: nil, radius: DS.Radius.sm)
        .accessibilityElement(children: .combine)
    }

    // MARK: - قطع صف الطلب الموحّد (نفس `DSRow` في صفحات الإدارة)

    /// رأس الصف: أيقونة الحقل بلون النوع + العنوان (Plex 13.5 عريض) + الوصف (Plex 12) + طرف
    /// (شارة الحالة عادةً).
    private func requestRowHeader<Trailing: View>(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String?,
        kind: AdminRequestKind? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: tint, side: DS.Hub.rowIcon)
                .accessibilityHidden(true)
            rowTitles(title: title, subtitle: subtitle, kind: kind)
            Spacer(minLength: 0)
            // الشارة بمقاسها — الاسم الطويل يلتفّ بدل أن تنضغط الشارة
            trailing()
                .fixedSize()
        }
    }

    private func rowTitles(title: String, subtitle: String?, kind: AdminRequestKind? = nil) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            // §10: شريحة نوع الطلب قبل العنوان في سطره
            HStack(spacing: DS.Spacing.xsm) {
                if let kind { AdminRequestKindChip(kind: kind) }
                Text(title)
                    .dsFieldFont(.adminRowTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1)
            }
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .dsFieldFont(.adminRowSubtitle)
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(2)
            }
        }
    }

    /// أسطر إضافية تحت الرأس — تبدأ تحت العنوان (بعد عمود الأيقونة + المسافة)
    private func rowExtras<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            content()
        }
        .padding(.leading, DS.Hub.rowIcon + DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// «مقدّم الطلب: …» (§10) — الشريحة على سطر العنوان
    private func requesterLine(_ requester: FamilyMember) -> some View {
        HStack(spacing: DS.Spacing.xsm) {
            AdminRequestCardLine(kind: nil, requester: requester.chainThreeName)
            ReviewVerifiedMark(requester.id)
        }
    }

    /// معاينة نصّ الطلب (سطران) — Plex 12 بلون القيم
    @ViewBuilder
    private func previewText(_ text: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            Text(trimmed)
                .dsFieldFont(.adminRowSubtitle)
                .foregroundColor(DS.Color.fieldValue)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// سطر «الحالي ← الجديد»: القديم مشطوب، والجديد عريض بلون أساسي
    private func changeLine(old: String?, new: String) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            if let old {
                Text(old)
                    .dsFieldFont(.adminRowSubtitle)
                    .foregroundColor(DS.Color.fieldValue)
                    .strikethrough(true, color: DS.Color.error.opacity(DS.Opacity.disabled))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Image(systemName: "arrow.forward")
                .dsGlyph(DS.Glyph.xs, weight: .semibold)
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)
            Text(new)
                .dsFont(.sectionTitle)
                .foregroundColor(AppSection.admin.ink)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    /// شارة «بانتظار» — بعمر الطلب إن عُرف تاريخه (اليوم، أمس، ٣ أيام…)
    private func pendingChip(_ date: Date?) -> some View {
        let text = date.map { ageText(days: daysWaiting(since: $0)) } ?? L10n.t("بانتظار", "Pending")
        return DSStatusChip(text: text, icon: "clock", tint: DS.Color.warning)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(date == nil ? text : L10n.t("بانتظار: \(text)", "Pending: \(text)"))
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

    /// مربّع تفاصيل الطلب بمنتصف الشاشة — نفس تصميم المربّعات الموحّد (طلب المالك):
    /// رأس كحلي بأيقونة نوع الطلب ووقته، الصورة (إن وُجدت)، قسم «بيانات الطلب» بصفوف،
    /// ثم شريط أزرار المربّع نفسه (طلب المالك ٢٠٢٦-١٠-٠٧ «أدمج أزرار الإجراءات مع بوكس العمل»):
    /// صفّ «تعديل الرقم / رفض / حذف نهائي» فوق صفّ «الموافقة / إغلاق» — بنفس الصلاحيات.
    /// عناصر صحة الشجرة للعرض فقط («إغلاق» وحده).
    private func requestDetailSheet(_ detail: RequestDetail) -> some View {
        let meta = detailMeta(for: detail)
        return Group {
            if let flow = approvalSnapshot(for: detail) {
                // «مسار الموافقات» شغّال: نفس البيانات داخل مربّع المسار، والأزرار بحسب الدور والمرحلة
                approvalDetailBox(detail, meta: meta, flow: flow)
            } else {
                DSComposer(
                    title: meta.title,
                    subtitle: meta.timestamp ?? L10n.t("تفاصيل الطلب", "Request Details"),
                    icon: meta.icon,
                    tint: DS.Color.actionNavy,
                    actionTitle: approveLabelFor(detail),
                    actionIcon: approveIconFor(detail),
                    showsAction: detailHasDecision(detail),
                    cancelTitle: L10n.t("إغلاق", "Close"),
                    canSubmit: !adminRequestVM.isLoading,
                    extraActions: detailExtraActions(for: detail),
                    decisionFooter: true,
                    onSubmit: { approveDetail(detail) },
                    onCancel: { selectedDetail = nil }
                ) {
                    detailBoxContent(detail, meta: meta)
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .dsCenterBox(item: $phoneEditPendingMember) { member in
            PendingMemberPhoneSheet(member: member)
                .environmentObject(adminRequestVM)
        }
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

    /// التنفيذ = مسار الموافقة القديم (`approveDetail`)، ورفض المدير = مسار الرفض القديم بالسبب.
    /// «تعديل رقم فعلي» و«حذف نهائي» باقيان كما كانا؛ «رفض» القديم يحلّ محله رفض المسار
    private func approvalDetailBox(_ detail: RequestDetail, meta: DetailMeta, flow: ApprovalSnapshot) -> some View {
        ApprovalRequestBox(
            adminRequestVM: adminRequestVM,
            memberVM: memberVM,
            snapshot: flow,
            title: meta.title,
            subtitle: meta.timestamp ?? L10n.t("تفاصيل الطلب", "Request Details"),
            icon: meta.icon,
            onExecute: { approveDetail(detail) },
            onReject: { reason in rejectDetail(detail, reason: reason) },
            onClose: { selectedDetail = nil },
            otherActions: detailExtraActions(for: detail).filter { $0.id != "reject" && $0.id != "forward" }
        ) {
            detailBoxContent(detail, meta: meta)
        }
    }

    /// كل تفصيل في «الوارد» طلب بقرار (عناصر «مشكلات الشجرة» خرجت إلى «العائلة»)
    private func detailHasDecision(_ detail: RequestDetail) -> Bool {
        true
    }

    /// محتوى المربّع: الصورة (إن وُجدت) ← «بيانات الطلب» (الإجراءات في شريط أزرار المربّع)
    @ViewBuilder
    private func detailBoxContent(_ detail: RequestDetail, meta: DetailMeta) -> some View {
        if case .join(let member) = detail {
            joinDetailContent(member)
        } else {
            genericDetailBoxContent(detail, meta: meta)
        }
    }

    /// تفاصيل طلب الانضمام — مرتّبة ومحترمة (طلب المالك ٢٠٢٦-١٠-٠١):
    /// بطاقة الشخص (صورته، اسمه، طريقة تسجيله) ← «بيانات المنضم» صفوفاً بعنوان وقيمة
    /// ← «في الشجرة» (المطابقات بزر «ربط» أو «اسم جديد») ← «الإجراءات». وقت الطلب في الرأس فقط.
    @ViewBuilder
    private func joinDetailContent(_ member: FamilyMember) -> some View {
        // الحالة ونوع التنفيذ (العيّنة ١٦) — الانضمام يُربط يدوياً دائماً
        let joinFlow = approvalSnapshot(for: RequestDetail.join(member))
        AnyView(AdminRequestStatusStrip(state: joinFlow == nil ? L10n.t("بانتظار القرار", "Awaiting a decision") : nil,
                                        sla: joinFlow.flatMap(AdminRequestStatusText.sla),
                                        execution: .manual))
        joinDetailBody(member)
        // «من أين وصل»: مسار التسجيل والجهاز والوقت
        AdminSenderSection(info: senderInfo(for: .join(member)), index: 4,
                           title: L10n.t("من أين وصل", "Where it came from"), showsSender: false)
    }

    @ViewBuilder
    private func joinDetailBody(_ member: FamilyMember) -> some View {
        // نفس ترتيب البطاقة «الأرجح أولاً»: مطابق ← قريب ← أضعف (JoinMatchPanel.swift)
        let tiersAll = joinTiers(for: member)
        let results: [JoinMatch] = tiersAll.all.map { e in
            (member: e.member, matchCount: e.depth, matchedParts: [], isRegistrationMatch: e.isServer,
             score: e.parts.isEmpty ? 0 : e.depth * 100 / e.parts.count, total: e.parts.count, fuzzy: 0)
        }
        let fromWeb = member.registrationPlatform == "web"
        let uname = member.username?.trimmingCharacters(in: .whitespaces) ?? ""
        let phone = member.phoneNumber?.trimmingCharacters(in: .whitespaces) ?? ""
        let birth = member.birthDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // ١) بطاقة الشخص
        VStack(spacing: DS.Spacing.xsm) {
            joinPersonAvatar(member, ring: results.isEmpty ? DS.Color.warning : DS.Color.success, size: DS.Icon.avatarLarge)
                .padding(.bottom, DS.Spacing.xxs)
            Text(member.fullName)
                .dsFont(.title)
                .foregroundColor(DS.Color.fieldLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: fromWeb ? "globe" : "iphone")
                    .dsGlyph(DS.Glyph.smCompact)
                    .accessibilityHidden(true)
                Text(fromWeb
                     ? (uname.isEmpty ? L10n.t("سجّل من الموقع", "Signed up on the website")
                                      : L10n.t("سجّل من الموقع · \u{2066}@\(uname)\u{2069}", "Website · @\(uname)"))
                     : L10n.t("سجّل من التطبيق برقم الجوال", "Signed up in the app by phone"))
            }
            .dsFieldFont(.adminRowSubtitle)
            .foregroundColor(fromWeb ? DS.Color.info.dsReadableGlyph : DS.Color.fieldValue)
            if member.isFemale { Self.femaleJoinTag }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xs)
        .dsStaggerIn(0)

        // ٢) بيانات المنضم — صفوف بعنوان وقيمة وفاصل رفيع
        DSComposerSection(title: L10n.t("بيانات المنضم", "Applicant"),
                          icon: "person.text.rectangle.fill",
                          tint: AppSection.admin.ink,
                          index: 1) {
            VStack(spacing: 0) {
                joinFactRow(icon: "phone.fill", tint: DS.Color.sea,
                            label: L10n.t("الهاتف", "Phone"),
                            value: phone.isEmpty ? L10n.t("غير مسجّل", "Not set") : KuwaitPhone.display(phone),
                            // «ج»: الرقم نفسه رابط اتصال، و«واتساب» رابط نصّي
                            valueAction: KuwaitPhone.telURL(phone).map { tel in { UIApplication.shared.open(tel) } }) {
                    if !phone.isEmpty, let wa = KuwaitPhone.whatsappURL(phone) {
                        whatsAppLink(wa)
                    }
                }
                Divider().padding(.leading, DS.Icon.row + DS.Spacing.sm + DS.Spacing.xs)
                joinFactRow(icon: "calendar", tint: DS.Color.neonPurple,
                            label: L10n.t("تاريخ الميلاد", "Birth date"),
                            value: birth.isEmpty ? L10n.t("غير مذكور", "Not given") : (DateHelper.displayDate(birth) ?? birth)) { EmptyView() }
                if member.isFemale {
                    Divider().padding(.leading, DS.Icon.row + DS.Spacing.sm + DS.Spacing.xs)
                    joinFactRow(icon: "figure.stand.dress", tint: DS.Color.female,
                                label: L10n.t("الجنس", "Gender"),
                                value: L10n.t("أنثى — تُربط بشجرة النساء", "Female — belongs in the women's tree")) { EmptyView() }
                }
            }
            .padding(.horizontal, DS.Spacing.smd)
            // البطاقة الواحدة (صندوق فوق بطاقة القسم)
            .dsCard(padding: nil, radius: DS.Radius.md, fill: DS.Color.background)
        }

        // ٣) «مكانه في الشجرة» (طلب المالك ٢٠٢٦-١١-١٣): المطابق الأرجح (أو الذي ضُغط صفّه) ← «يُربط بحسابه»،
        // وبلا مطابق ملاحظة وحدها. حساب المرأة يُربط من مربّع شجرة النساء (المقطع هناك)
        let placeMatch = results.first { $0.member.id == joinPlacePick[member.id] }?.member ?? results.first?.member
        if !member.isFemale {
            AnyView(TreePlaceSection(place: placeMatch.map { TreePlace.join(match: $0) }, index: 2,
                                     men: memberVM.allMembers, primary: placePrimary(for: .join(member)),
                                     emptyNote: TreePlaceText.noMatch))
        }

        // ٤) في الشجرة — المطابقات بزر «ربط»، أو اسم جديد. الأنثى: شجرة النساء (زرّ المربّع «ربط بشجرة النساء»)
        if member.isFemale {
            DSComposerSection(title: L10n.t("في شجرة النساء", "In the women's tree"),
                              icon: "figure.stand.dress",
                              tint: DS.Color.female,
                              index: 2) {
                DSNoteCard(L10n.t("تُربط بعقدتها في شجرة النساء تحت أبيها، أو تُضاف بنتاً جديدة له — من «ربط بشجرة النساء».",
                                  "She's linked to her node in the women's tree under her father, or added as his new daughter — via «Link to women's tree»."),
                           icon: "link.badge.plus", tint: DS.Color.female)
            }
        } else {
            DSComposerSection(title: L10n.t("في الشجرة", "In the tree"),
                              icon: results.isEmpty ? "sparkles" : "person.2.fill",
                              tint: results.isEmpty ? DS.Color.warning : DS.Color.success,
                              trailing: results.isEmpty ? nil : "\(results.count)",
                              index: 3) {
                if results.isEmpty {
                    // الملاحظة الموحّدة
                    DSNoteCard(L10n.t("لا يوجد اسم مطابق في الشجرة — عند «ربط بالشجرة» يُضاف عضواً جديداً.",
                                      "No matching name in the tree — linking adds them as a new member."),
                               icon: "person.badge.plus", tint: DS.Color.warning)
                } else {
                    VStack(spacing: DS.Spacing.xsm) {
                        ForEach(results, id: \.member.id) { match in
                            joinMatchRow(match: match, pendingMember: member,
                                         isPlaced: results.count > 1 && match.member.id == placeMatch?.id)
                        }
                    }
                }
            }
        }
    }

    /// صف معلومة: أيقونة + العنوان فوق القيمة (وأزرار اختيارية) — مثل بطاقات جهات الاتصال
    private func joinFactRow<Trailing: View>(icon: String, tint: Color, label: String, value: String,
                                             valueAction: (() -> Void)? = nil,
                                             @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: tint)
                .accessibilityHidden(true)
            // القيمة رابط حين يُمرَّر إجراء (رقم الهاتف = اتصال) — بلون التواصل
            let valueText = Text(value)
                .dsFieldFont(.headlineCompact)
                .foregroundColor(valueAction == nil ? DS.Color.fieldLabel : DS.Color.sea)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(label)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                if let valueAction {
                    // إطار على الرقم كرابط الاتصال في البطاقة
                    Button(action: valueAction) {
                        valueText
                            .padding(.horizontal, DS.Spacing.sm)
                            .frame(minHeight: DS.Icon.row)
                            .overlay(Capsule().strokeBorder(DS.Color.sea, lineWidth: DS.Border.widthBold))
                    }
                        .buttonStyle(DSScaleButtonStyle())
                        .accessibilityHint(L10n.t("اتصال", "Call"))
                } else {
                    valueText
                }
            }
            .accessibilityElement(children: valueAction == nil ? .combine : .contain)
            Spacer(minLength: DS.Spacing.xs)
            trailing()
        }
        .frame(minHeight: DS.Icon.tapTarget + DS.Spacing.sm)
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
        case .join: return nil   // للانضمام قسمه في `joinDetailContent` (المطابق المختار)
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

    /// أزرار المربّع الأخرى (في شريطه السفلي فوق «الموافقة / إغلاق») — بنفس الصلاحيات السابقة:
    /// تعديل/إضافة رقم فعلي (طلب انضمام + canModerate)، رفض (canRejectRequests)، حذف نهائي
    /// (canDeleteMembers، معطّل أثناء العمل). عناصر صحة الشجرة بلا إجراءات.
    private func detailExtraActions(for detail: RequestDetail) -> [DSComposerAction] {
        let decision = detailHasDecision(detail)
        var items: [DSComposerAction] = []
        // تعديل / إضافة رقم فعلي قبل الربط
        if let member = detailPhoneEditMember(detail) {
            // صفّ مستقل بعرض كامل كما كان قبل التوحيد (ن-٥ فحص ٢٠٢٦-١٠-٠٧)
            items.append(DSComposerAction(id: "phone", title: L10n.t("تعديل / إضافة رقم فعلي", "Edit / Add real number"),
                                          icon: "phone.badge.plus", role: .cancel, fullRow: true) {
                phoneEditPendingMember = member
            })
        }
        // رفض طلب الانضمام يحذف ملف المتقدّم — للمالك والمدير فقط (`canReject(.joinRequests)`)
        let isJoin: Bool = { if case .join = detail { return true } else { return false } }()
        if decision && (isJoin ? canReject(.joinRequests) : authVM.canRejectRequests) {
            // الرفض برتقالي والحذف النهائي أحمر — لونان مختلفان (طلب المالك)
            items.append(DSComposerAction(id: "reject", title: L10n.t("رفض", "Reject"),
                                          icon: "xmark", role: .destructive, tint: DS.Color.reject) {
                rejectReasonText = ""
                rejectReasonDetail = detail
                showRejectReason = true
            })
        }
        // «حوّل للمدير» (مقترح «أدوار الإدارة» البند ١١): المراقب يقبل الانضمام ولا يرفضه (الرفض = حذف الملف) —
        // بدل زرّ ناقص يحوّله للمالك/المدير بإشعار الإدارة الموجود وملاحظة. مع «مسار الموافقات» يحلّ محله «يوصي بالرفض»
        if decision, case .join(let member) = detail, !canReject(.joinRequests), authVM.canApproveTreeRequests {
            items.append(DSComposerAction(id: "forward", title: L10n.t("حوّل للمدير", "Forward to manager"),
                                          icon: "arrowshape.turn.up.left.2", role: .cancel,
                                          isEnabled: !adminRequestVM.isLoading) {
                forwardJoinNote = ""
                forwardJoinMember = member
            })
        }
        // «حذف نهائي» خارج التفاصيل (طلب المالك ٢٠٢٦-١١-١١): بسحب بطاقة الطلب في القائمة فقط (`RequestSwipeActions`)
        return items
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
                     value: request.member?.displayFullName ?? "—", color: AppSection.admin.ink)
            longTextCard(icon: "exclamationmark.bubble.fill",
                         label: L10n.t("التفاصيل", "Details"),
                         text: request.details ?? L10n.t("لا توجد تفاصيل", "No details"))

        case .phone(let request):
            // عن نفسه: «مقدّم الطلب · صاحب الشأن» أعلاه (§10 بلا تكرار)
            if request.requesterId != nil && request.requesterId != request.memberId {
                infoCard(icon: "person.fill", label: L10n.t("العضو", "Member"),
                         value: request.member?.displayFullName ?? "—", color: AppSection.admin.ink)
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
                     value: request.member?.displayFullName ?? "—", color: AppSection.admin.ink)
            longTextCard(icon: "doc.text.fill",
                         label: L10n.t("التفاصيل", "Details"),
                         text: request.details ?? L10n.t("لا توجد تفاصيل", "No details"))

        case .child(let request):
            // «الأب» = «مقدّم الطلب» غالباً (§10 بلا تكرار)
            if request.requesterId != request.memberId {
                infoCard(icon: "person.fill", label: L10n.t("الأب", "Father"),
                         value: request.member?.displayFullName ?? "—", color: AppSection.admin.ink)
            }
            longTextCard(icon: "doc.text.fill",
                         label: L10n.t("التفاصيل", "Details"),
                         text: request.details ?? L10n.t("لا توجد تفاصيل", "No details"))

        case .photo(let request):
            infoCard(icon: "person.fill", label: L10n.t("العضو", "Member"),
                     value: request.member?.displayFullName ?? "—", color: AppSection.admin.ink)
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
                         value: memberName, color: AppSection.admin.ink)
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
                         value: memberName, color: AppSection.admin.ink)
                if let death = payload?.deathDate, !death.isEmpty {
                    infoCard(icon: "calendar", label: L10n.t("تاريخ الوفاة", "Death Date"),
                             value: DateHelper.displayDate(death) ?? death, color: DS.Color.slate)
                }
            case .addDeathDate:
                infoCard(icon: "person.fill", label: memberLabel,
                         value: memberName, color: AppSection.admin.ink)
                if let death = payload?.deathDate, !death.isEmpty {
                    infoCard(icon: "calendar.badge.exclamationmark", label: L10n.t("تاريخ الوفاة", "Death Date"),
                             value: DateHelper.displayDate(death) ?? death, color: DS.Color.slate)
                }
            case .addPhoto:
                infoCard(icon: "person.fill", label: memberLabel,
                         value: memberName, color: AppSection.admin.ink)
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
                         value: memberName, color: AppSection.admin.ink)
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

    /// صف معلومة — أيقونة الحقل + العنوان الغامق + القيمة (نفس صفوف المربّعات الموحّدة).
    /// `whatsapp`: رقم هاتف ← زرّ واتساب في طرف الصف (طلب المالك ٢٠٢٦-١١-١١ «عند رقم الهاتف زر يودي للواتساب»)
    private func infoCard(icon: String, label: String, value: String, color: Color, whatsapp: String? = nil) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: icon, tint: color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(label)
                        .dsFieldFont(.label)
                        .foregroundColor(DS.Color.fieldLabel)
                    // القيمة أوضح من العنوان: بوزن أثقل ولون النص الأساسي («خلها واضحة اكثر» ٢٠٢٦-١١-٢٤)
                    Text(value)
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)   // «العنوان، القيمة» عنصراً واحداً
            Spacer(minLength: 0)
            if let url = KuwaitPhone.whatsappURL(whatsapp) {
                whatsappButton(url)
            }
        }
        // يمتدّ لارتفاع جاره حين يكونان جنب بعض (`AdminDetailPairLayout`) — المربّعان بطول واحد
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .dsRowBox()
        // حقل يصلح أن يكون جنب حقل آخر في تفاصيل الطلب — الصور والأزرار والأقسام تبقى بعرض المربّع
        .layoutValue(key: AdminDetailPairable.self, value: whatsapp == nil)
    }

    /// زرّ «واتساب» — حبّة مدمجة خضراء بنصّها (الزرّ الواحد بحجم `.compact`)، يفتح المحادثة مع الرقم
    private func whatsappButton(_ url: URL) -> some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "message.fill").dsGlyph(DSButtonSize.compact.glyph)
                Text(L10n.t("واتساب", "WhatsApp"))
            }
            .modifier(DSButtonFace(size: .compact, tint: DS.Color.success, fullWidth: false))
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(L10n.t("مراسلة عبر واتساب", "Message on WhatsApp"))
    }

    /// صف رابط قابل للنقر — يفتح URL (واتساب/موقع/سوشال) بنفس صفوف المربّعات.
    private func contactLinkCard(icon: String, label: String, value: String, color: Color, url: URL) -> some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: icon, tint: color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(label)
                        .dsFieldFont(.label)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(value)
                        .dsFieldFont(.fieldValue)
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .dsGlyph(DS.Glyph.sm)
                    .foregroundColor(color.dsReadableGlyph)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    /// يبني رابط سوشال من handle (@user) أو URL كامل.
    private func socialURL(_ raw: String, base: String) -> URL? {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return nil }
        if v.lowercased().hasPrefix("http") { return URL(string: v) }
        let handle = v.hasPrefix("@") ? String(v.dropFirst()) : v
        return URL(string: base + handle)
    }

    /// صف نص طويل — أيقونة الحقل + العنوان، ثم المحتوى متعدد الأسطر بعرض الصف.
    private func longTextCard(icon: String, label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: icon, tint: AppSection.admin.ink)
                    .accessibilityHidden(true)
                Text(label)
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                Spacer(minLength: 0)
            }
            Text(text)
                .dsFieldFont(.fieldValue)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dsRowBox()
        .accessibilityElement(children: .combine)
    }

    /// صف مقارنة «قبل/بعد» — القديم مشطوب بالأحمر ← الجديد بالأخضر (تغييرات الاسم/الهاتف).
    /// `whatsapp`: الرقم الجديد ← زرّ واتساب بجانبه (طلبات تغيير الرقم)
    private func comparisonCard(oldLabel: String, oldValue: String,
                                 newLabel: String, newValue: String, icon: String,
                                 whatsapp: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: icon, tint: DS.Color.error)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(oldLabel)
                        .dsFieldFont(.label)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(oldValue)
                        .dsFieldFont(.fieldValue)
                        .foregroundColor(DS.Color.fieldValue)
                        .strikethrough(true, color: DS.Color.error.opacity(DS.Opacity.disabled))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // سهم تحت عمود الأيقونات: من القديم إلى الجديد
            Image(systemName: "arrow.down")
                .dsGlyph(DS.Glyph.smCompact)
                .foregroundColor(DS.Color.textTertiary)
                .frame(width: DS.Icon.row)
                .accessibilityHidden(true)

            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: icon, tint: DS.Color.success)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(newLabel)
                        .dsFieldFont(.label)
                        .foregroundColor(DS.Color.success)
                    Text(newValue)
                        .dsFieldFont(.fieldValueStrong)
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let url = KuwaitPhone.whatsappURL(whatsapp) {
                    whatsappButton(url)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
        .accessibilityElement(children: .contain)   // «الحالي… الجديد…» + زرّ واتساب منفصل
    }

    /// ارتفاع مكان الصورة المقترحة قبل تحميلها، وارتفاع صورة الخبر في شبكة الصور
    private static let photoCardPlaceholder: CGFloat = 200
    private static let newsMediaTileHeight: CGFloat = 90

    /// صورة كبيرة (للصور المقترحة) بنفس إطار صفوف المربّعات.
    private func photoCard(url: URL) -> some View {
        CachedAsyncImage(url: url) { img in
            img.resizable().scaledToFit()
        } placeholder: {
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background)
                .frame(height: Self.photoCardPlaceholder)
                .overlay(DSPageLoader(size: DS.Icon.rowLarge, fillsSpace: false))
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke), lineWidth: DS.Border.width)
        )
        // صورة محتوى (المقترحة/الجديدة) — اسم واضح بدل «صورة» بلا وصف
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("الصورة", "Photo"))
        .accessibilityAddTraits(.isImage)
    }

    // الموافقة صارت زر الشريط السفلي للمربّع، والرفض والحذف النهائي في قسم «الإجراءات»
    // (detailActionsSection) — بنفس الصلاحيات وحالة التحميل السابقة.

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

// MARK: - صف القائمة الشفاف (نمط صفحات الإدارة)

private extension View {
    /// صف بلا خلفية ولا فاصل، بهوامش الصفحة — المحتوى نفسه يرسم صندوقه
    func reviewListRow(top: CGFloat = 4, bottom: CGFloat = 4) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: DS.Spacing.lg, bottom: bottom, trailing: DS.Spacing.lg))
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


// MARK: - «تمت معالجتها» (طلب المالك ٢٠٢٦-١١-١١ «قسم واضح ودقيق: شنو كل طلب صار فيه ومن سواه من الإدارة»)

extension AdminAllRequestsView {
    /// «عرض المزيد» للطلبات المعالجة — تحت القائمة، أو تحت «لا نتائج» حين يُخفي الفلتر كل المحمَّل
    var handledMoreButton: some View {
        Button {
            Task { await handledStore.loadMore() }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                if handledStore.isLoading { ProgressView() }
                Text(L10n.t("عرض المزيد", "Show more"))
            }
            .modifier(DSButtonFace(role: .cancel))
        }
        .buttonStyle(DSPressStyle())
        .disabled(handledStore.isLoading)
        .reviewListRow(top: DS.Spacing.sm, bottom: DS.Spacing.lg)
    }

    /// الطلبات المغلقة (آخر ٣٠ يوماً) بالأيام، الأحدث أولاً، وبحث «الوارد» الواحد — بنفس قواعد ظهور «الطلبات»
    var handledList: some View {
        let visible = visibleHandledEntries
        return List {
            DSSearchField(text: $searchText, placeholder: AdminInboxView.searchPlaceholder)
                .reviewListRow(top: DS.Spacing.md, bottom: DS.Spacing.xs)
            if !handledStore.loadedOnce {
                DSPageLoader(L10n.t("جارٍ تحميل ما تمت معالجته…", "Loading handled requests…"), fillsSpace: false)
                    .padding(.top, DS.Spacing.xl)
                    .reviewListRow()
            } else if visible.isEmpty {
                // ما في المحمَّل شي يطابق — والباقي لم يُحمَّل بعد: لا نقول «لا طلبات»، ونُبقي «عرض المزيد»
                DSEmptyView(handledStore.failed ? L10n.t("تعذّر التحميل", "Couldn't load")
                                : handledStore.hasMore ? L10n.t("لا نتائج فيما حُمِّل", "No matches in what's loaded")
                                : L10n.t("لا طلبات معالجة", "Nothing handled yet"),
                            message: handledStore.failed
                                ? L10n.t("تحقّق من الاتصال ثم اسحب للتحديث.", "Check your connection, then pull to refresh.")
                                : handledStore.hasMore
                                ? L10n.t("اعرض المزيد لتبحث في الطلبات الأقدم.", "Show more to search older requests.")
                                : L10n.t("الطلبات التي قُبلت أو رُفضت في آخر ٣٠ يوماً تظهر هنا.",
                                         "Requests approved or rejected in the last 30 days appear here."),
                            style: .card)
                    .reviewListRow(top: DS.Spacing.xs)
                if handledStore.hasMore && !handledStore.failed { handledMoreButton }
            } else {
                ForEach(DSDayBuckets.group(visible, date: handledEntryDate)) { group in
                    DSDayHeader(title: group.title, count: group.items.count)
                        .reviewListRow(top: DS.Spacing.sm, bottom: DS.Spacing.xxs)
                    ForEach(group.items) { entry in
                        switch entry {
                        case .request(let request):
                            AdminHandledRow(request: request, events: handledStore.events[request.id],
                                            lookup: { memberVM.member(byId: $0) }) {
                                handledOpen = request
                            }
                            .reviewListRow(top: DS.Spacing.xxs, bottom: DS.Spacing.xxs)
                        case .deletion(let deletion):
                            // حذف الإدارة المباشر (§9) — للعرض فقط
                            AdminDeletionRow(deletion: deletion) { deletionOpen = deletion }
                                .reviewListRow(top: DS.Spacing.xxs, bottom: DS.Spacing.xxs)
                        }
                    }
                }
                if handledStore.hasMore {
                    handledMoreButton
                } else {
                    Text(L10n.t("آخر ٣٠ يوماً", "Last 30 days"))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .reviewListRow(top: DS.Spacing.sm, bottom: DS.Spacing.lg)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .environment(\.defaultMinListRowHeight, 0)
        .refreshable { await handledStore.reload() }
        .task {
            handledStore.includesDeletions = authVM.canModerateTree
            if !handledStore.loadedOnce { await handledStore.reload() }
        }
    }

    /// الطلبات المعالجة + حذف الإدارة المباشر في الأيام نفسها، الأحدث أولاً (§9)
    private var visibleHandledEntries: [AdminHandledEntry] {
        var entries = visibleHandled.map(AdminHandledEntry.request)
        if authVM.canModerateTree {
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let deletions = handledStore.deletions.filter { d in
                q.isEmpty || NameSearch.matches(query: q, any: [d.displayFullName, d.deletedByName ?? "",
                                                                 AdminDeletionText.title])
            }
            entries += deletions.map(AdminHandledEntry.deletion)
        }
        return entries.sorted { handledEntryDate($0) > handledEntryDate($1) }
    }

    private func handledEntryDate(_ entry: AdminHandledEntry) -> Date {
        switch entry {
        case .request(let r): return handledDate(r)
        case .deletion(let d): return d.deletedDate ?? .distantPast
        }
    }

    /// وقت التجميع: وقت المعالجة، والقديم بلا وقت ردّ بوقت إرساله
    private func handledDate(_ request: AdminRequest) -> Date {
        DateHelper.parse(AdminTrailText.handledAt(request, events: handledStore.events[request.id]))
            ?? DateHelper.parse(request.createdAt) ?? .distantPast
    }

    /// ما يراه هذا الدور — نفس مجالات «الطلبات» (`tabsForRole` / `canSeeMessages` / الصور المقترحة)
    private var visibleHandled: [AdminRequest] {
        let items = handledStore.items.filter(handledVisible)
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter { r in
            let texts = [r.member?.fullName, memberVM.member(byId: r.requesterId)?.fullName, r.newValue, r.details,
                         AdminTrailText.typeTitle(r), r.treeEditPayload?.targetMemberName, r.treeEditPayload?.newMemberName]
                .compactMap { $0 }
            return NameSearch.matches(query: q, any: texts)
        }
    }

    private func handledVisible(_ r: AdminRequest) -> Bool {
        switch r.requestType {
        case "contact_message": return canSeeMessages
        case RequestType.newsReport.rawValue, RequestType.contentReport.rawValue: return authVM.canModerateContent
        case RequestType.photoSuggestion.rawValue: return canHandlePhotos
        case RequestType.accountDelete.rawValue, RequestType.privacyRequest.rawValue,
             RequestType.relativeRemove.rawValue: return authVM.isAdmin
        default: return authVM.canModerateTree
        }
    }

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
    func handledBox(_ request: AdminRequest) -> some View {
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
            onCancel: { handledOpen = nil }
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
