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
    // حذف نهائي لأي طلب — للمالك/المدير فقط
    @State private var deleteConfirmDetail: RequestDetail? = nil
    // تعديل/إضافة رقم فعلي لعضو معلّق (طلب انضمام)
    @State private var phoneEditPendingMember: FamilyMember? = nil
    // سحب (الكل): رفض مع سبب — وحذف مع تأكيد
    @State private var swipeRejectDetail: RequestDetail? = nil
    @State private var swipeRejectReason: String = ""
    @State private var swipeDeleteDetail: RequestDetail? = nil

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
            case .deceased: return "bolt.heart.fill"
            case .children: return "person.badge.plus"
            case .treeAdd: return "person.crop.circle.badge.plus"
            case .treeEditName: return "pencil.line"
            case .treeEditPhone: return "phone.arrow.up.right"
            case .treeEditBirth: return "birthday.cake"
            case .treeDeceased: return "heart.slash"
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

    // MARK: «الوارد» (إعادة تصميم لوحة الإدارة — طلب المالك ٢٠٢٦-١٠-٢٠، الاتجاه «أ» + سحب «ب»؛ الدفعة ب من «نفّذ كل المقترح»)
    // طابور عمل بثلاثة مداخل: الطلبات · الرسائل (شريحتان، بلا مبدّل) · ⚙︎ إعدادات مسار الموافقات (بيتها الوحيد).
    // الرأس الكحلي بشرائح المسار (بانتظار قرارك · عاجل · متأخر · الكل)، حقل بحث واحد يخدم الشريحتين (بالاسم أو الرقم)،
    // شرائح المجموعات (الأعضاء · الشجرة · المحتوى) ثم أنواعها، وبطاقات طلبات غنية بأزرار، وآخر القائمة «المنجز اليوم».
    // «تقرير الموافقات» بيته «المؤشرات»، و«مشكلات الشجرة» شريحة في «العائلة» (الوارد = ما طلبه أحد فقط).
    // نفس الاستدعاءات والصلاحيات تماماً (`canApprove(_:)` / `canReject(_:)`، `decideOnServer`، مسار الموافقات).

    /// قسما «الوارد»
    enum InboxSegment: Hashable { case requests, messages }
    @State private var segment: InboxSegment = .requests
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
    @State private var mergeTarget: (pendingMember: FamilyMember, treeMember: FamilyMember)? = nil
    @State private var showMergeConfirm = false
    @State private var showMergeSuccess = false
    @State private var mergeSuccessMessage = ""
    /// مطابقات التسجيل من السيرفر (matched_ids من admin_requests)
    @State private var registrationMatches: [UUID: [UUID]] = [:]
    /// الأعضاء اللي المدير فتح كل المتطابقين حقهم
    @State private var expandedMatchMembers: Set<UUID> = []

    @State private var cachedPendingMembers: [FamilyMember] = []
    private var pendingMembers: [FamilyMember] { cachedPendingMembers }

    /// عناصر الأرشيف المعلّقة (بانتظار اعتماد الإدارة).
    private var pendingArchiveItems: [ArchiveItem] {
        archiveVM.items.filter { $0.approvalStatus == .pending }
    }

    // حارس المكدس (الدفعة ب ٢٠٢٦-١٠-٢٠): الجسم ثلاث طبقات خلف `AnyView` — الصفحة، ثم تنبيهات العمليات الجماعية،
    // ثم المربّعات والتأكيدات — فلا يُحلّ نوع سلسلة المُعدِّلات كلها دفعة واحدة (كانت تفيض مكدساً بـ١٢٨ ك.ب)
    var body: some View {
        AnyView(modalsLayer(AnyView(bulkAlertsLayer(AnyView(pageLayer)))))
    }

    private var pageLayer: some View {
        VStack(spacing: 0) {
            AnyView(inboxHeader)

            if segment == .messages {
                // «الرسائل» — صفحة الرسائل نفسها بلا رأسها (رأس «الوارد» فوقها) وبحث «الوارد» الواحد
                AnyView(AdminInboxView(embedded: true, sharedSearch: $searchText))
            } else {
                // وضع التحديد: شريط ملخّص التحديد مثبّت أعلى القائمة (إلغاء · العدد · تحديد الكل)
                // — يحلّ محل الفلاتر كما كان، ويبقى ظاهراً مهما نزلت القائمة.
                if isSelectMode && totalCount > 0 {
                    selectionSummaryBar
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.xs)
                        .transition(.opacity)
                }

                // البحث ← المجموعات ← الطلبات: قائمة واحدة تتمرّر (List لأجل أزرار السحب)
                AnyView(requestsList)
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
        .onChange(of: segment) { _ in
            withAnimation(DS.Anim.snappy) {
                isSelectMode = false
                selectedIds.removeAll()
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
    }

    /// مربّع تفاصيل الطلب، والسحب (رفض/حذف)، وربط طلب الانضمام ودمجه
    private func modalsLayer(_ content: AnyView) -> some View {
        content
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
                // ⚙︎ بيت «إعدادات مسار الموافقات» الوحيد (المالك يعدّل، المدير يقرأ)
                if authVM.canViewSystemSettings {
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
                if segment == .requests && !isSelectMode {
                    headerFilterChips
                        .padding(.top, DS.Spacing.md)
                }
            }

            // «الطلبات · الرسائل» شريحتا فلتر (لا مبدّل — طلب المالك «مابي تويب علوي»)
            DSFilterChips(options: [
                DSFilterOption(id: InboxSegment.requests, title: L10n.t("الطلبات", "Requests"),
                               icon: "tray.full.fill", count: isInitialLoading ? nil : cachedTotalCount),
                DSFilterOption(id: InboxSegment.messages, title: L10n.t("الرسائل", "Messages"),
                               icon: "bubble.left.and.bubble.right.fill",
                               count: adminRequestVM.pendingContactMessagesCount)
            ], selection: $segment)
            .accessibilityLabel(L10n.t("الطلبات أو الرسائل", "Requests or messages"))
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)
        }
    }

    /// شرائح المسار فوق الرأس: بانتظارك · مستعجل · متأخر · الكل (المختارة ذهبية) — بأعداد التبويب الحالي
    private var headerFilterChips: some View {
        let showFlow = tabSupportsApprovalFilter(selectedTab) && !isInitialLoading
        let visible = showFlow ? unfilteredTabIds.compactMap(adminRequestVM.approvalSnapshot(forRowId:)) : []
        func count(_ f: ApprovalListFilter) -> Int { adminRequestVM.approvalFilterCount(f, in: visible) }
        let allCount = selectedTab == .all ? displayedAllItems.count : itemCount(for: selectedTab)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xsm + 1) {
                if showFlow {
                    // شريحة صفرية تختفي (إلا المختارة حتى لا تضيع)
                    if count(.waiting) > 0 || approvalFilter == .waiting {
                        AdminBandFilterChip(title: L10n.t("بانتظار قرارك", "Awaiting you"), count: count(.waiting),
                                            selected: approvalFilter == .waiting) { setApprovalFilter(.waiting) }
                    }
                    if adminRequestVM.approvalsV2Seen && (count(.urgent) > 0 || approvalFilter == .urgent) {
                        AdminBandFilterChip(title: L10n.t("عاجل", "Urgent"), count: count(.urgent), icon: "flame",
                                            iconTint: DS.Hub.kpiHot, selected: approvalFilter == .urgent) {
                            setApprovalFilter(.urgent)
                        }
                    }
                    if count(.late) > 0 || approvalFilter == .late {
                        AdminBandFilterChip(title: L10n.t("متأخر", "Late"), count: count(.late), icon: "clock",
                                            iconTint: DS.Hub.kpiLate, selected: approvalFilter == .late) {
                            setApprovalFilter(.late)
                        }
                    }
                }
                AdminBandFilterChip(title: L10n.t("الكل", "All"), count: isInitialLoading ? nil : allCount,
                                    selected: approvalFilter == .all || !showFlow) { setApprovalFilter(.all) }
            }
            .padding(.vertical, DS.Spacing.xxs)
        }
        .accessibilityLabel(L10n.t("فلتر الطلبات", "Request filter"))
    }

    private func setApprovalFilter(_ f: ApprovalListFilter) {
        guard approvalFilter != f else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) { approvalFilter = f }
    }

    /// عدد مجموعة (الأعضاء · الشجرة · المحتوى · صحة الشجرة) في مجال الدور
    private func sectionCount(_ section: RequestSection) -> Int {
        availableTabs.filter { $0.section == section }.reduce(0) { $0 + itemCount(for: $1) }
    }

    /// شرائح المجموعات (الاتجاه «أ»): الكل ثم كل مجموعة فيها طلبات
    private var groupChips: some View {
        let sections = RequestSection.allCases.filter { sectionCount($0) > 0 || $0 == selectedSection }
        var options: [DSFilterOption<RequestSection?>] = [DSFilterOption(id: nil, title: L10n.t("الكل", "All"))]
        options += sections.map { DSFilterOption(id: $0, title: $0.title, icon: $0.icon, count: sectionCount($0)) }
        let binding = Binding<RequestSection?>(
            get: { selectedSection },
            set: { newValue in
                selectedSection = newValue
                selectedTab = .all
            })
        return DSFilterChips(options: options, selection: binding)
            .accessibilityLabel(L10n.t("مجموعات الطلبات", "Request groups"))
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
         projectsVM.pendingProjects.count, pendingArchiveItems.count, adminRequestVM.treeEditRequests.count]
    }

    /// يبحث الآن (نصّ غير فارغ)
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// عناصر «الكل» كما تُعرض: مجموعة المختارة ثم البحث (الترتيب والمجال كما في `sortedAllItems`)
    private var displayedAllItems: [AllItem] {
        var items = sortedAllItems
        if let section = selectedSection {
            items = items.filter { allItemTab($0).section == section }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        let needle = ArabicTextNormalizer.normalizeForSearch(q)
        let digits = String(q.filter(\.isNumber))
        return items.filter { item in
            let texts = searchTexts(item)
            if texts.contains(where: { ArabicTextNormalizer.normalizeForSearch($0).contains(needle) }) { return true }
            return digits.count >= 3 && texts.contains { $0.filter(\.isNumber).contains(digits) }
        }
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
        return Self.contentTabs.contains(tab) ? authVM.canApproveContent : authVM.canApproveTreeRequests
    }

    /// هل يقدر يرفضها؟ (المشرف يتعامل مع البلاغات فقط)
    /// رفض طلب الانضمام = حذف ملف المتقدّم (`rejectOrDeleteMember`) — للمالك والمدير (`canDeleteMembers`) وحدهما،
    /// كان يظهر للمراقب فيفشل دائماً
    private func canReject(_ tab: RequestTab) -> Bool {
        if tab == .reports { return authVM.canModerateContent }
        if tab == .joinRequests { return authVM.canDeleteMembers }
        return Self.contentTabs.contains(tab) ? authVM.canApproveContent : authVM.canRejectRequests
    }

    /// التابات التي يراها هذا الدور — كل دور يشوف مجاله فقط
    private func tabsForRole(_ tabs: [RequestTab]) -> [RequestTab] {
        if authVM.isAdmin { return tabs }
        if authVM.currentUser?.role == .supervisor {
            return tabs.filter { $0 == .all || Self.contentTabs.contains($0) }
        }
        // المراقب: الشجرة والأعضاء — و«صور مقترحة» والمسار شغّال (مختصّها المراقب)
        return tabs.filter {
            $0 == .all || !Self.contentTabs.contains($0) || ($0 == .photos && adminRequestVM.approvalsWorkflowOn)
        }
    }

    private func recalculateCounts() {
        cachedPendingMembers = memberVM.allMembers.filter { $0.role == .pending }
        // المجموع الكلّي عبر مصدر واحد للحقيقة — يطابق بادج «طلبات المراجعة» في لوحة الإدارة
        cachedTotalCount = Self.reviewRequestsTotal(
            memberVM: memberVM, newsVM: newsVM, adminRequestVM: adminRequestVM,
            diwaniyaVM: diwaniyaVM, projectsVM: projectsVM,
            pendingArchiveCount: pendingArchiveItems.count,
            scope: Self.reviewScope(for: authVM)
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

    @MainActor
    static func reviewRequestsTotal(
        memberVM: MemberViewModel,
        newsVM: NewsViewModel,
        adminRequestVM: AdminRequestViewModel,
        diwaniyaVM: DiwaniyasViewModel,
        projectsVM: ProjectsViewModel,
        pendingArchiveCount: Int = 0,
        scope: ReviewScope = .all
    ) -> Int {
        let members = memberVM.allMembers
        let pending = members.filter { $0.role == .pending }.count

        // المحتوى والبلاغات = تبويبات `contentTabs`، والباقي الشجرة والأعضاء
        let content = newsVM.pendingNewsRequests.count
            + adminRequestVM.newsReportRequests.count
            + diwaniyaVM.pendingDiwaniyas.count
            + adminRequestVM.photoSuggestionRequests.count
            + projectsVM.pendingProjects.count
            + pendingArchiveCount
        // «مسار الموافقات»: مختص الصور المقترحة المراقب — فتُحسب في مجال الشجرة أيضاً
        let photosInTree = adminRequestVM.approvalsWorkflowOn ? adminRequestVM.photoSuggestionRequests.count : 0
        let tree = pending
            + adminRequestVM.phoneChangeRequests.count
            + adminRequestVM.nameChangeRequests.count
            + adminRequestVM.deceasedRequests.count
            + adminRequestVM.childAddRequests.count
            + adminRequestVM.treeEditRequests.count
            + photosInTree
        switch scope {
        case .all:     return content + tree - photosInTree
        case .content: return content
        case .tree:    return tree
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
        .padding(.horizontal, DS.Spacing.lg)
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
                DSPageLoader(L10n.t("جارٍ تحميل الطلبات…", "Loading requests…"), fillsSpace: false)
                    .padding(.top, DS.Spacing.xl)
                    .dsStaggerIn(1)
                    .reviewListRow()
            } else {
                // «بحث بالاسم أو الرقم» (لمسة «ب») ثم شرائح المجموعات وأنواعها (الاتجاه «أ»)
                // — وفي وضع التحديد يحلّ محلها شريط الملخّص أعلاه.
                if totalCount > 0 && !isSelectMode {
                    DSSearchField(text: $searchText, placeholder: AdminInboxView.searchPlaceholder)
                        .reviewListRow(top: DS.Spacing.md, bottom: DS.Spacing.xs)
                    groupChips
                        .reviewListRow(top: 0, bottom: 0)
                    if selectedSection != nil {
                        subTypeChips
                            .reviewListRow(top: 0, bottom: DS.Spacing.xs)
                    }
                }

                if isSearching {
                    // البحث يعرض كل طلبات المجموعة المطابقة (أي نوع)
                    allRequestsContent()
                } else if totalCount == 0 || itemCount(for: selectedTab) == 0 {
                    emptyState
                        .padding(.top, DS.Spacing.xs)
                        .dsStaggerIn(2)
                        .reviewListRow()
                } else if isApprovalFilterActive && currentTabIds.isEmpty {
                    DSEmptyView(L10n.t("لا طلبات هنا", "Nothing here"),
                                message: L10n.t("لا طلب يطابق هذا الفلتر الحين.", "No request matches this filter right now."),
                                style: .card)
                        .padding(.top, DS.Spacing.xs)
                        .reviewListRow()
                } else {
                    tabRows
                }
                // «المنجز اليوم (N) ›» — آخر القائمة (كان «عرض المنجز» في صفحة «عرض الكل» المحذوفة)
                if !isSearching && !isSelectMode {
                    AdminInboxDoneToday()
                        .reviewListRow(top: DS.Spacing.sm, bottom: DS.Spacing.lg)
                }
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
                    approveLabel: L10n.t("ربط", "Link"),
                    approveIcon: "link.badge.plus",
                    onApprove: { memberToLink = member },
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
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])

                    // «مسار الموافقات»: شريط المراحل الخمس + المرحلة ومن عنده + شارات الأولوية والمهلة
                    if let flow {
                        cardFlowStrip(flow, waitingForMe: waitingForMe)
                    }

                    // أزرار البطاقة — نفس إجراءات السحب تماماً (والمسار: يفتح المربّع حيث خطواته)
                    if !isSelectMode {
                        cardActions(flow: flow, waitingForMe: waitingForMe,
                                    allowsApprove: allowsApprove, allowsReject: allowsReject,
                                    approveLabel: approveLabel, approveIcon: approveIcon,
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
                             onApprove: (() -> Void)?, onReject: (() -> Void)?,
                             onTap: @escaping () -> Void) -> some View {
        let canReject = allowsReject && onReject != nil
        let canApprove = allowsApprove && onApprove != nil
        let opensFlow = flow != nil && !canApprove && waitingForMe
        if canReject || canApprove || opensFlow {
            HStack(spacing: DS.Spacing.xsm + 1) {
                if canReject, let onReject {
                    AdminPillButton(title: L10n.t("رفض", "Reject"), style: .reject,
                                    height: DS.Hub.pillHeightCard, fullWidth: true, action: onReject)
                }
                if opensFlow, let flow {
                    AdminPillButton(title: flowActionTitle(flow), style: .navy,
                                    height: DS.Hub.pillHeightCard, fullWidth: true, action: onTap)
                } else {
                    AdminPillButton(title: L10n.t("التفاصيل", "Details"), style: .soft,
                                    height: DS.Hub.pillHeightCard, fullWidth: true, action: onTap)
                    if canApprove, let onApprove {
                        AdminPillButton(title: approveLabel ?? L10n.t("موافقة", "Approve"), style: .navy,
                                        height: DS.Hub.pillHeightCard, fullWidth: true, action: onApprove)
                    }
                }
            }
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
        let newDisplay = treeEditNewValue(payload: payload, action: action)
        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            requestRowHeader(icon: action.iconName,
                             tint: color,
                             title: L10n.t(action.arabicLabel, action.englishLabel),
                             subtitle: request.member?.displayFullName ?? L10n.t("عضو", "Member")) {
                pendingChip(Self.requestDate(request.createdAt))
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
                            Text(L10n.t("القيمة الجديدة:", "New:"))
                                .dsFont(.footnote)
                                .foregroundColor(DS.Color.textTertiary)
                            Text(newDisplay)
                                .dsFieldFont(.chip)
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
                approveLabel: L10n.t("ربط", "Link"), approveIcon: "link.badge.plus",
                onApprove: { memberToLink = member },
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
                        ? L10n.t("كل الطلبات متابَعة — ما فيه شي ينتظر قرارك",
                                 "All caught up — nothing is awaiting your decision")
                        : L10n.t("لا شيء في «\(selectedTab.title)» الآن",
                                 "Nothing in \(selectedTab.title) right now"),
                    tint: DS.Color.success, style: .compact)
            .padding(.vertical, DS.Spacing.xl)
    }

    // MARK: - Join Request Row

    /// مطابقة في الشجرة (`NameMatcher`): `score` النسبة ٠…١٠٠، `total` أجزاء اسم المتقدّم، `fuzzy` منها بفرق حرف
    typealias JoinMatch = (member: FamilyMember, matchCount: Int, matchedParts: [String], isRegistrationMatch: Bool,
                           score: Int, total: Int, fuzzy: Int)

    /// صف طلب الانضمام — أنيق ومحترم (طلب المالك ٢٠٢٦-١٠-٠١): صورة بأول حرف بحلقة لون الحالة،
    /// الاسم عنواناً، سطر حالة هادئ (مطابقة/اسم جديد · من الموقع)، عمر الطلب نصاً خفيفاً،
    /// ثم الرقم وزر واتساب دائري، وأقرب تطابق فقط. التفاصيل الكاملة داخل الطلب.
    private func joinRequestRow(for member: FamilyMember) -> some View {
        // كل المتغيرات خارج ViewBuilder لتفادي مشاكل @ViewBuilder مع let
        let phone: String? = {
            guard let p = member.phoneNumber, !p.isEmpty else { return nil }
            return p
        }()
        let results = orderedMatchList(for: member)
        let hasMatches = !results.isEmpty
        let fromWeb = member.registrationPlatform == "web"
        let age = Self.requestDate(member.createdAt).map { ageText(days: daysWaiting(since: $0)) }

        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .center, spacing: DS.Spacing.md) {
                joinPersonAvatar(member, ring: hasMatches ? DS.Color.success : DS.Color.warning, size: Self.joinAvatar)

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(member.displayFullName)
                        .dsFieldFont(.headlineCompact)
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    // الأنثى لا تُطابق بشجرة الرجال — سطرها «تُربط بشجرة النساء»
                    if !member.isFemale { joinStatusLine(matches: results.count, fromWeb: fromWeb) }
                    if member.isFemale { Self.femaleJoinTag }
                }

                Spacer(minLength: DS.Spacing.xs)

                if let age {
                    Text(age)
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize()
                }
            }

            if let phone {
                HStack(spacing: DS.Spacing.sm) {
                    metaItem("phone.fill", KuwaitPhone.display(phone), color: DS.Color.fieldValue)
                    Spacer(minLength: 0)
                    if let wa = KuwaitPhone.whatsappURL(phone) {
                        roundContactButton(icon: "message.fill", tint: DS.Color.sea,
                                           label: L10n.t("واتساب", "WhatsApp")) {
                            UIApplication.shared.open(wa)
                        }
                    }
                }
                .padding(.leading, Self.joinAvatar + DS.Spacing.md)   // تحت الاسم (الصورة + المسافة)
            }

            if hasMatches {
                joinBestMatches(for: member, results: results)
            }
        }
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
    private func roundContactButton(icon: String, tint: Color, label: String,
                                    action: @escaping () -> Void) -> some View {
        let pad = (DS.Icon.tapTarget - DS.Icon.rowCompact) / 2
        return Button(action: action) {
            DSStateIcon(icon, tint: tint.dsReadableGlyph, size: DS.Icon.rowCompact, mapsChrome: false)
                .padding(pad)
                .contentShape(Rectangle())
                .padding(-pad)
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(label)
    }

    /// أقرب تطابق فقط — والباقي بزر «عرض كل المطابقات»
    @ViewBuilder
    private func joinBestMatches(for member: FamilyMember, results: [JoinMatch]) -> some View {
        let isExpanded = expandedMatchMembers.contains(member.id)
        let visible = isExpanded ? results : Array(results.prefix(1))
        VStack(spacing: DS.Spacing.xsm) {
            ForEach(visible, id: \.member.id) { match in
                joinMatchRow(match: match, pendingMember: member)
            }
            if results.count > 1 && !isExpanded {
                // الشريحة الموحّدة في وسط السطر
                DSChipButton(L10n.t("عرض كل المطابقات (\(results.count))",
                                    "Show all matches (\(results.count))"),
                             icon: "chevron.down", tint: AppSection.admin.ink) {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) {
                        _ = expandedMatchMembers.insert(member.id)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.leading, Self.joinAvatar + DS.Spacing.md)   // تحت الاسم (الصورة + المسافة)
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateFormat = "d MMM yyyy · h:mm a"
        return formatter.string(from: date)
    }

    private func joinMatchRow(match: JoinMatch, pendingMember: FamilyMember) -> some View {
        // النتيجة الموزونة من `NameMatcher` (الأول أثقل ثم الأب ثم الجد…) — بلا اسم العائلة والروابط
        let totalParts = max(match.total, 1)
        let matchPercent = min(100, max(0, match.score))

        return HStack(spacing: DS.Spacing.sm) {
            // نسبة التطابق — الحلقة الصغيرة الموحّدة (الدفعة ١٠)
            DSRingGauge(progress: Double(matchPercent) / 100, tint: AppSection.admin.ink, size: DS.Ring.small,
                        center: .percent(matchPercent), ink: AppSection.admin.ink)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(match.member.displayFullName)
                    .dsFieldFont(.rowTitleCompact)
                    .foregroundColor(DS.Color.fieldLabel)
                    .dsNameLines()

                HStack(spacing: DS.Spacing.xs) {
                    Text(match.fuzzy > 0
                         ? L10n.t("\(match.matchCount) من \(totalParts) أسماء متطابقة · \(match.fuzzy) بفرق حرف",
                                  "\(match.matchCount) of \(totalParts) names match · \(match.fuzzy) one letter off")
                         : L10n.t("\(match.matchCount) من \(totalParts) أسماء متطابقة",
                                  "\(match.matchCount) of \(totalParts) names match"))
                    .dsFieldFont(.footnote)
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                    if match.isRegistrationMatch {
                        DSStatusChip(text: L10n.t("تسجيل", "Reg"), tint: AppSection.admin.ink)
                    }
                }

                // رقم الهاتف
                if let phone = match.member.phoneNumber, !phone.isEmpty {
                    metaItem("phone.fill", KuwaitPhone.display(phone))
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            // «ربط» — الشريحة الموحّدة ممتلئة بتعبئة القسم
            DSChipButton(L10n.t("ربط", "Link"), isSelected: true) {
                mergeTarget = (pendingMember: pendingMember, treeMember: match.member)
                showMergeConfirm = true
            }
            .accessibilityLabel(L10n.t("ربط بـ \(match.member.displayFullName)",
                                       "Link to \(match.member.displayFullName)"))
        }
        // البطاقة الواحدة
        .dsCard(padding: DS.Spacing.sm)
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

    /// لستة مرتبة بالأقرب (طلب المالك ٢٠٢٦-١٠-٢٤ «تقريب الاسم اكثر نظم الالية») — `NameMatcher`:
    /// تطبيع عربي، «عبد الله» = «عبدالله»، بلا اسم العائلة والروابط، مقارنة بالترتيب بوزن أعلى للأول ثم الأب ثم الجد،
    /// وفرق حرف واحد مقبول. يُعرض من تطابقت أول ٣ أجزاء من اسمه بالترتيب (أو كلها إن كانت أقل)، ومطابقات السيرفر
    /// (`search_members_by_name` + لقطة التسجيل) تُدمج بلا تكرار متى تطابق الاسم الأول — ثم الكل بالنتيجة.
    func orderedMatchList(for member: FamilyMember) -> [JoinMatch] {
        // الأنثى تُربط بشجرة النساء — لا مطابقات (ولا «ربط») من شجرة الرجال
        guard !member.isFemale else { return [] }
        let families = NameMatcher.familyKeys()
        let applicant = NameMatcher.chain(member.fullName, families: families)
        guard !applicant.isEmpty else { return [] }

        // فقط سجلات الشجرة: بدون هاتف + أحياء + لها اسم + مو pending
        let existingMembers = memberVM.allMembers.filter { m in
            m.role != .pending && m.id != member.id && m.hasName &&
            (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            m.isDeceased != true
        }
        let serverIds = Set(registrationMatches[member.id] ?? [])

        var scored: [(member: FamilyMember, result: NameMatcher.Result, isServer: Bool)] = []
        for existing in existingMembers {
            let isServer = serverIds.contains(existing.id)
            let result = NameMatcher.compare(applicant, NameMatcher.chain(existing.fullName, families: families))
            // المحلي: أول ٣ أجزاء بالترتيب · السيرفر: يكفي الاسم الأول (السيرفر وجده بمنطقه)
            guard result.isStrong || (isServer && result.prefix >= 1) else { continue }
            scored.append((member: existing, result: result, isServer: isServer))
        }

        scored.sort { a, b in
            if a.result.score != b.result.score || a.result.prefix != b.result.prefix {
                return NameMatcher.ranksBefore(a.result, b.result)
            }
            if a.isServer != b.isServer { return a.isServer }
            return a.member.fullName.localizedStandardCompare(b.member.fullName) == .orderedAscending
        }

        return scored.prefix(20).map { item in
            (member: item.member, matchCount: item.result.matched.count, matchedParts: item.result.matched,
             isRegistrationMatch: item.isServer, score: item.result.percent, total: item.result.total,
             fuzzy: item.result.fuzzy)
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
                             subtitle: post.author_name) {
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
                             subtitle: request.member.map { L10n.t("عن: \($0.fullName)", "About: \($0.fullName)") }) {
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
        let memberName = request.member?.fullName ?? "Member"

        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            requestRowHeader(icon: "phone.arrow.right",
                             tint: AppSection.admin.ink,
                             title: L10n.t("طلب تغيير رقم", "Phone Change"),
                             subtitle: memberName) {
                pendingChip(Self.requestDate(request.createdAt))
            }

            rowExtras {
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
            requestRowHeader(icon: item.categoryIcon,
                             tint: DS.Color.warning,
                             title: L10n.t("عنصر أرشيف", "Archive Item"),
                             subtitle: item.title) {
                pendingChip(item.createdAt)
            }

            rowExtras {
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
            requestRowHeader(icon: "bolt.heart.fill",
                             tint: DS.Color.error,
                             title: L10n.t("تسجيل وفاة", "Deceased"),
                             subtitle: L10n.t("لـ: \(request.member?.displayFullName ?? "عضو")",
                                              "For: \(request.member?.fullName ?? "Member")")) {
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
        let requester = memberVM.allMembers.first(where: { $0.id == request.requesterId })
        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            requestRowHeader(icon: "person.badge.plus",
                             tint: DS.Color.info,
                             title: L10n.t("إضافة ابن", "Child Add"),
                             subtitle: L10n.t("الأب: \(request.member?.displayFullName ?? "عضو")",
                                              "Father: \(request.member?.fullName ?? "Member")")) {
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

    // MARK: - Photo Row

    private func photoRow(for request: AdminRequest) -> some View {
        let requester = memberVM.allMembers.first(where: { $0.id == request.requesterId })
        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            requestRowHeader(icon: "camera.badge.ellipsis",
                             tint: DS.Color.neonBlue,
                             title: L10n.t("اقتراح صورة", "Photo Suggestion"),
                             subtitle: L10n.t("لـ: \(request.member?.displayFullName ?? "عضو")",
                                              "For: \(request.member?.fullName ?? "Member")")) {
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
                             subtitle: currentName) {
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
                    .dsFieldFont(.body)
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
                .dsFieldFont(.subtitle)
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
                .dsFieldFont(.calloutCompact)
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
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: tint)
                .accessibilityHidden(true)
            rowTitles(title: title, subtitle: subtitle)
            Spacer(minLength: 0)
            // الشارة بمقاسها — الاسم الطويل يلتفّ بدل أن تنضغط الشارة
            trailing()
                .fixedSize()
        }
    }

    private func rowTitles(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(title)
                .dsFieldFont(.rowTitle)
                .foregroundColor(DS.Color.fieldLabel)
                .lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .dsFieldFont(.subtitle)
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
        .padding(.leading, DS.Icon.row + DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// معلومة صغيرة: أيقونة + نص (Plex 11) — التاريخ، الهاتف، مقدّم الطلب…
    private func metaItem(_ icon: String, _ text: String, color: Color = DS.Color.textTertiary) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            Image(dsSymbol: icon)
                .dsGlyph(DS.Glyph.micro, weight: .semibold)
                .accessibilityHidden(true)
            Text(text)
                .dsFont(.footnote)
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundColor(color)
    }

    /// «من: …» — مقدّم الطلب
    private func requesterLine(_ requester: FamilyMember) -> some View {
        metaItem("person.fill", L10n.t("من: \(requester.displayFullName)", "By: \(requester.displayFullName)"))
    }

    /// معاينة نصّ الطلب (سطران) — Plex 12 بلون القيم
    @ViewBuilder
    private func previewText(_ text: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            Text(trimmed)
                .dsFieldFont(.subtitle)
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
                    .dsFieldFont(.subtitle)
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
                    onSubmit: { approveDetail(detail) },
                    onCancel: { selectedDetail = nil }
                ) {
                    detailBoxContent(detail, meta: meta)
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .dsAlert(
            L10n.t("حذف الطلب نهائياً؟", "Delete request permanently?"),
            isPresented: Binding(
                get: { deleteConfirmDetail != nil },
                set: { if !$0 { deleteConfirmDetail = nil } }
            )
        ) {
            Button(L10n.t("حذف نهائي", "Delete Permanently"), role: .destructive) {
                if let d = deleteConfirmDetail {
                    hardDeleteDetail(d)
                }
                deleteConfirmDetail = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { deleteConfirmDetail = nil }
        } message: {
            Text(L10n.t(
                "سيُحذف هذا الطلب نهائياً من قاعدة البيانات ولا يمكن التراجع.",
                "This request will be permanently removed and cannot be undone."
            ))
        }
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
            otherActions: detailExtraActions(for: detail).filter { $0.id != "reject" }
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
        let results = orderedMatchList(for: member)
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
            .dsFieldFont(.chip)
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
                            value: phone.isEmpty ? L10n.t("غير مسجّل", "Not set") : KuwaitPhone.display(phone)) {
                    if !phone.isEmpty {
                        HStack(spacing: DS.Spacing.xsm) {
                            if let wa = KuwaitPhone.whatsappURL(phone) {
                                roundContactButton(icon: "message.fill", tint: DS.Color.sea,
                                                   label: L10n.t("واتساب", "WhatsApp")) {
                                    UIApplication.shared.open(wa)
                                }
                            }
                            if let tel = KuwaitPhone.telURL(phone) {
                                roundContactButton(icon: "phone.fill", tint: AppSection.admin.ink,
                                                   label: L10n.t("اتصال", "Call")) {
                                    UIApplication.shared.open(tel)
                                }
                            }
                        }
                    }
                }
                Divider().padding(.leading, DS.Icon.row + DS.Spacing.sm + DS.Spacing.xs)
                joinFactRow(icon: "calendar", tint: DS.Color.neonPurple,
                            label: L10n.t("تاريخ الميلاد", "Birth date"),
                            value: birth.isEmpty ? L10n.t("غير مذكور", "Not given") : birth) { EmptyView() }
                if member.isFemale {
                    Divider().padding(.leading, DS.Icon.row + DS.Spacing.sm + DS.Spacing.xs)
                    joinFactRow(icon: "figure.stand.dress", tint: DS.Color.female,
                                label: L10n.t("الجنس", "Gender"),
                                value: L10n.t("أنثى — تُربط بشجرة النساء", "Female — belongs in the women's tree")) { EmptyView() }
                }
            }
            .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xxs)
            // البطاقة الواحدة (صندوق فوق بطاقة القسم)
            .dsCard(padding: nil, radius: DS.Radius.md, fill: DS.Color.background)
        }

        // ٣) في الشجرة — المطابقات بزر «ربط»، أو اسم جديد. الأنثى: شجرة النساء (زرّ المربّع «ربط بشجرة النساء»)
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
                              index: 2) {
                if results.isEmpty {
                    // الملاحظة الموحّدة
                    DSNoteCard(L10n.t("لا يوجد اسم مطابق في الشجرة — عند «ربط بالشجرة» يُضاف عضواً جديداً.",
                                      "No matching name in the tree — linking adds them as a new member."),
                               icon: "person.badge.plus", tint: DS.Color.warning)
                } else {
                    VStack(spacing: DS.Spacing.xsm) {
                        ForEach(results, id: \.member.id) { match in
                            joinMatchRow(match: match, pendingMember: member)
                        }
                    }
                }
            }
        }
    }

    /// صف معلومة: أيقونة + العنوان فوق القيمة (وأزرار اختيارية) — مثل بطاقات جهات الاتصال
    private func joinFactRow<Trailing: View>(icon: String, tint: Color, label: String, value: String,
                                             @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(label)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                Text(value)
                    .dsFieldFont(.headlineCompact)
                    .foregroundColor(DS.Color.fieldLabel)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: DS.Spacing.xs)
            trailing()
        }
        .frame(minHeight: DS.Icon.tapTarget + DS.Spacing.sm)
    }

    @ViewBuilder
    private func genericDetailBoxContent(_ detail: RequestDetail, meta: DetailMeta) -> some View {
        if let imageUrl = meta.imageUrl, let url = URL(string: imageUrl) {
            detailHeroImage(url: url, color: meta.color)
                .dsStaggerIn(0)
        }

        DSComposerSection(title: detailInfoTitle(detail),
                          icon: detailInfoIcon(detail),
                          tint: AppSection.admin.ink,
                          index: 1) {
            detailContent(for: detail)
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
        // حذف نهائي — يمسح الطلب كلياً (للمالك/المدير فقط)
        if decision && authVM.canDeleteMembers {
            items.append(DSComposerAction(id: "delete", title: L10n.t("حذف نهائي", "Delete Permanently"),
                                          icon: "trash", role: .destructive,
                                          isEnabled: !adminRequestVM.isLoading) {
                deleteConfirmDetail = detail
            })
        }
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
            return .init(icon: "bolt.heart.fill", color: DS.Color.slate,
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
            return .init(icon: action.iconName, color: treeEditColor(action),
                         // «طلب آخر» من تعديل الملف الشخصي يحمل عنوانه الحقيقي (تغيير الحالة الاجتماعية…)
                         title: Self.profileReasonTitle(request.treeEditPayload?.reason)
                             ?? L10n.t(action.arabicLabel, action.englishLabel),
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
                         value: KuwaitPhone.display(phone), color: DS.Color.sea)
            }
            if let birth = member.birthDate?.trimmingCharacters(in: .whitespacesAndNewlines), !birth.isEmpty {
                infoCard(icon: "calendar", label: L10n.t("تاريخ الميلاد", "Birth Date"),
                         value: birth, color: DS.Color.palm)
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
                     value: post.author_name, color: AppSection.admin.ink)
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
                     value: request.member?.fullName ?? "—", color: AppSection.admin.ink)
            longTextCard(icon: "exclamationmark.bubble.fill",
                         label: L10n.t("التفاصيل", "Details"),
                         text: request.details ?? L10n.t("لا توجد تفاصيل", "No details"))

        case .phone(let request):
            infoCard(icon: "person.fill", label: L10n.t("العضو", "Member"),
                     value: request.member?.fullName ?? "—", color: AppSection.admin.ink)
            comparisonCard(
                oldLabel: L10n.t("الرقم الحالي", "Current"),
                oldValue: KuwaitPhone.display(request.member?.phoneNumber),
                newLabel: L10n.t("الرقم الجديد", "New"),
                newValue: KuwaitPhone.display(request.newValue),
                icon: "phone.fill"
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
                     value: request.member?.fullName ?? "—", color: AppSection.admin.ink)
            longTextCard(icon: "doc.text.fill",
                         label: L10n.t("التفاصيل", "Details"),
                         text: request.details ?? L10n.t("لا توجد تفاصيل", "No details"))

        case .child(let request):
            infoCard(icon: "person.fill", label: L10n.t("الأب", "Father"),
                     value: request.member?.fullName ?? "—", color: AppSection.admin.ink)
            longTextCard(icon: "doc.text.fill",
                         label: L10n.t("التفاصيل", "Details"),
                         text: request.details ?? L10n.t("لا توجد تفاصيل", "No details"))

        case .photo(let request):
            infoCard(icon: "person.fill", label: L10n.t("العضو", "Member"),
                     value: request.member?.fullName ?? "—", color: AppSection.admin.ink)
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
                     value: project.ownerName, color: AppSection.admin.ink)
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
            infoCard(icon: "textformat", label: L10n.t("العنوان", "Title"),
                     value: item.title, color: DS.Color.sadu)
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
            let memberName = payload?.targetMemberName
                ?? request.member?.fullName
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
                    icon: "phone.fill"
                )
            case .deceased:
                infoCard(icon: "person.fill", label: memberLabel,
                         value: memberName, color: AppSection.admin.ink)
                if let death = payload?.deathDate, !death.isEmpty {
                    infoCard(icon: "calendar", label: L10n.t("تاريخ الوفاة", "Death Date"),
                             value: death, color: DS.Color.slate)
                }
            case .addDeathDate:
                infoCard(icon: "person.fill", label: memberLabel,
                         value: memberName, color: AppSection.admin.ink)
                if let death = payload?.deathDate, !death.isEmpty {
                    infoCard(icon: "calendar.badge.exclamationmark", label: L10n.t("تاريخ الوفاة", "Death Date"),
                             value: death, color: DS.Color.slate)
                }
            case .addPhoto:
                infoCard(icon: "person.fill", label: memberLabel,
                         value: memberName, color: AppSection.admin.ink)
                if let photoStr = payload?.newPhotoUrl, let url = URL(string: photoStr) {
                    photoCard(url: url)
                }
            case .add:
                infoCard(icon: "person.fill", label: L10n.t("الاسم الجديد", "New Name"),
                         value: payload?.newMemberName ?? memberName, color: DS.Color.palm)
                if let parent = payload?.parentMemberName, !parent.isEmpty {
                    infoCard(icon: "person.2.fill", label: L10n.t("الأب", "Father"),
                             value: parent, color: AppSection.admin.ink)
                }
            case .delete:
                infoCard(icon: "person.fill", label: memberLabel,
                         value: memberName, color: DS.Color.error)
            case .editBirth:
                infoCard(icon: "person.fill", label: memberLabel,
                         value: memberName, color: AppSection.admin.ink)
                if let newDate = (payload?.newBirthDate ?? payload?.newName), !newDate.isEmpty {
                    infoCard(icon: "birthday.cake", label: L10n.t("تاريخ الميلاد الجديد", "New Birth Date"),
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
                         value: requester.fullName, color: DS.Color.info)
            }
            // سبب داخلي من تعديل الملف الشخصي (profile_marital…) لا يُعرض كما هو — عنوانه في رأس المربّع
            if let reason = payload?.reason, !reason.isEmpty, Self.profileReasonTitle(reason) == nil {
                longTextCard(icon: "text.bubble.fill",
                             label: L10n.t("السبب", "Reason"), text: reason)
            }
            if let notes = payload?.notes, !notes.isEmpty {
                longTextCard(icon: "note.text",
                             label: L10n.t("ملاحظات", "Notes"), text: notes)
            }

        }
    }

    /// صف معلومة — أيقونة الحقل + العنوان الغامق + القيمة (نفس صفوف المربّعات الموحّدة).
    private func infoCard(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(label)
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(value)
                    .dsFieldFont(.body)
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .dsRowBox()
        .accessibilityElement(children: .combine)   // «العنوان، القيمة» عنصراً واحداً
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
                        .dsFieldFont(.body)
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
                .dsFieldFont(.body)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dsRowBox()
        .accessibilityElement(children: .combine)
    }

    /// صف مقارنة «قبل/بعد» — القديم مشطوب بالأحمر ← الجديد بالأخضر (تغييرات الاسم/الهاتف).
    private func comparisonCard(oldLabel: String, oldValue: String,
                                 newLabel: String, newValue: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: icon, tint: DS.Color.error)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(oldLabel)
                        .dsFieldFont(.label)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(oldValue)
                        .dsFieldFont(.body)
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
                        .dsFieldFont(.headline)
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
        .accessibilityElement(children: .combine)   // «الحالي… الجديد…» عنصراً واحداً
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
        default:       return L10n.t("موافقة", "Approve")
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
