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
    // إضافة رقم + تفعيل لعضو من «صحة الشجرة»
    @State private var healthPhoneMember: FamilyMember? = nil
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
        /// عنصر صحة الشجرة — للعرض فقط (بدون موافقة/رفض)، يعرض معلومات العضو + واتساب.
        case healthMember(FamilyMember, TreeHealthIssue)

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
            case .healthMember(let m, _): return "health-\(m.id)"
            }
        }
    }

    /// أقسام رئيسية للطلبات — تجميع منطقي للفلاتر.
    enum RequestSection: String, CaseIterable, Identifiable {
        case members      // أعضاء — انضمام/اسم/جوال/وفاة/معرض
        case tree         // الشجرة — أبناء/إضافة شجرة/حذف شجرة
        case content      // محتوى ونشاط — أخبار/بلاغات/صور/ديوانيات/مشاريع
        case treeHealth   // صحة الشجرة — يتائم/بدون اسم/روابط مكسورة/مخفي/رقم مكرر

        var id: String { rawValue }

        var title: String {
            switch self {
            case .members:     return L10n.t("أعضاء", "Members")
            case .tree:        return L10n.t("الشجرة", "Tree")
            case .content:     return L10n.t("محتوى ونشاط", "Content")
            case .treeHealth:  return L10n.t("صحة الشجرة", "Tree Health")
            }
        }

        var icon: String {
            switch self {
            case .members:    return "person.2.fill"
            case .tree:       return "tree.fill"
            case .content:    return "doc.fill"
            case .treeHealth: return "heart.text.square.fill"
            }
        }

        var color: Color {
            switch self {
            case .members:    return DS.Color.info
            case .tree:       return DS.Color.success
            case .content:    return DS.Color.warning
            case .treeHealth: return DS.Color.error
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
        // صحة الشجرة (audit issues)
        case healthOrphan, healthNoName, healthBrokenParent, healthHidden, healthDupPhone

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return L10n.t("الكل", "All")
            case .joinRequests: return L10n.t("انضمام", "Join")
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
            case .healthOrphan: return L10n.t("معلّق", "Unlinked")
            case .healthNoName: return L10n.t("بدون اسم", "No Name")
            case .healthBrokenParent: return L10n.t("رابط مكسور", "Broken Link")
            case .healthHidden: return L10n.t("مخفي", "Hidden")
            case .healthDupPhone: return L10n.t("رقم مكرر", "Dup Phone")
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
            case .healthOrphan: return "person.fill.xmark"
            case .healthNoName: return "textformat.abc.dottedunderline"
            case .healthBrokenParent: return "link.badge.plus"
            case .healthHidden: return "eye.slash"
            case .healthDupPhone: return "phone.badge.waveform"
            }
        }

        var color: Color {
            switch self {
            case .all: return DS.Color.primary
            case .joinRequests: return DS.Color.info
            case .news: return DS.Color.warning
            case .reports: return DS.Color.error
            case .phone: return DS.Color.primary
            case .nameChange: return DS.Color.neonPurple
            case .diwaniya: return DS.Color.gridDiwaniya
            case .archive: return DS.Color.warning
            case .deceased: return DS.Color.error
            case .children: return DS.Color.info
            case .treeAdd: return DS.Color.success
            case .treeEditName: return DS.Color.neonPurple
            case .treeEditPhone: return DS.Color.primary
            case .treeEditBirth: return DS.Color.warning
            case .treeDeceased: return DS.Color.error
            case .treeAddDeathDate: return DS.Color.error
            case .treeAddPhoto: return DS.Color.primary
            case .treeDelete: return DS.Color.error
            case .treeOther: return DS.Color.accent
            case .photos: return DS.Color.neonBlue
            case .projects: return DS.Color.neonPurple
            case .healthOrphan: return DS.Color.error
            case .healthNoName: return DS.Color.warning
            case .healthBrokenParent: return DS.Color.info
            case .healthHidden: return DS.Color.textTertiary
            case .healthDupPhone: return DS.Color.neonPink
            }
        }

        /// القسم الذي ينتمي إليه — nil لـ .all (ليس له قسم).
        var section: RequestSection? {
            switch self {
            case .all: return nil
            case .joinRequests, .nameChange, .phone, .deceased: return .members
            case .children, .treeAdd, .treeEditName, .treeEditPhone, .treeEditBirth, .treeDeceased, .treeAddDeathDate, .treeAddPhoto, .treeDelete, .treeOther: return .tree
            case .news, .reports, .photos, .diwaniya, .projects, .archive: return .content
            case .healthOrphan, .healthNoName, .healthBrokenParent, .healthHidden, .healthDupPhone: return .treeHealth
            }
        }
    }

    @State private var selectedTab: RequestTab = .all
    @State private var selectedSection: RequestSection? = nil   // nil = وضع الكل
    /// التحميل الأول (قبل أول `recalculateCounts`) — بطاقة «جارٍ التحميل» بدل «لا توجد طلبات»
    @State private var isInitialLoading = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showBulkApproveChildrenConfirm = false
    @State private var bulkApproveResult: String?
    @State private var showBulkApproveResult = false

    // Multi-select (works for all tabs)
    @State private var isSelectMode = false
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

    // MARK: - Tree Health Caches
    @State private var cachedHealthIssueMembers: [FamilyMember] = []
    @State private var cachedHealthMemberIssues: [UUID: Set<TreeHealthIssue>] = [:]
    @State private var cachedHealthCounts: [TreeHealthIssue: Int] = [:]
    @State private var openTreeHealthFilter: AdminTreeHealthView.TreeIssueFilter? = nil

    enum TreeHealthIssue: String, Hashable {
        case orphan, noName, brokenParent, hiddenFromTree, duplicatePhone

        var asTab: RequestTab {
            switch self {
            case .orphan:         return .healthOrphan
            case .noName:         return .healthNoName
            case .brokenParent:   return .healthBrokenParent
            case .hiddenFromTree: return .healthHidden
            case .duplicatePhone: return .healthDupPhone
            }
        }

        var asAdminFilter: AdminTreeHealthView.TreeIssueFilter {
            switch self {
            case .orphan:         return .orphan
            case .noName:         return .noName
            case .brokenParent:   return .brokenParent
            case .hiddenFromTree: return .hiddenFromTree
            case .duplicatePhone: return .duplicatePhone
            }
        }

        static func from(tab: RequestTab) -> TreeHealthIssue? {
            switch tab {
            case .healthOrphan:        return .orphan
            case .healthNoName:        return .noName
            case .healthBrokenParent:  return .brokenParent
            case .healthHidden:        return .hiddenFromTree
            case .healthDupPhone:      return .duplicatePhone
            default: return nil
            }
        }
    }

    private func rebuildTreeHealthCache() {
        let allActive = memberVM.allMembers.filter { $0.role != .pending && $0.status != .frozen }
        let fatherIds = Set(allActive.compactMap(\.fatherId))
        let activeIds = Set(allActive.map(\.id))

        var issues: [UUID: Set<TreeHealthIssue>] = [:]
        var result: [FamilyMember] = []

        for member in memberVM.allMembers where member.status != .frozen {
            var memberIssues = Set<TreeHealthIssue>()
            if member.fatherId == nil && !fatherIds.contains(member.id) && member.role != .pending {
                memberIssues.insert(.orphan)
            }
            let name = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty || name == "بدون اسم" {
                memberIssues.insert(.noName)
            }
            if let fid = member.fatherId, !activeIds.contains(fid) {
                memberIssues.insert(.brokenParent)
            }
            // ملاحظة: «مخفي» (hiddenFromTree) أُزيل من فحص صحة الشجرة بطلب المستخدم — لا يُعتبر مشكلة.
            if !memberIssues.isEmpty {
                issues[member.id] = memberIssues
                result.append(member)
            }
        }
        for group in memberVM.duplicatePhoneGroups {
            for member in group {
                issues[member.id, default: []].insert(.duplicatePhone)
                if !result.contains(where: { $0.id == member.id }) {
                    result.append(member)
                }
            }
        }
        result.sort { $0.fullName < $1.fullName }

        var counts: [TreeHealthIssue: Int] = [:]
        for issue in [TreeHealthIssue.orphan, .noName, .brokenParent, .duplicatePhone] {
            counts[issue] = issues.values.filter { $0.contains(issue) }.count
        }

        cachedHealthIssueMembers = result
        cachedHealthMemberIssues = issues
        cachedHealthCounts = counts
    }

    private func healthMembers(for issue: TreeHealthIssue) -> [FamilyMember] {
        cachedHealthIssueMembers.filter { cachedHealthMemberIssues[$0.id]?.contains(issue) == true }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // وضع التحديد: شريط ملخّص التحديد مثبّت أعلى القائمة (إلغاء · العدد · تحديد الكل)
                // — يحلّ محل الفلاتر كما كان، ويبقى ظاهراً مهما نزلت القائمة.
                if isSelectMode && totalCount > 0 {
                    selectionSummaryBar
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.xs)
                        .transition(.opacity)
                }

                // بطاقة الرأس ← الفلاتر ← الطلبات: قائمة واحدة تتمرّر (List لأجل أزرار السحب)
                requestsList
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
        .navigationTitle(L10n.t("طلبات المراجعة", "Review Requests"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // زر التحديد المتعدّد — أيقونة فقط بدون خلفية
            ToolbarItem(placement: .topBarTrailing) {
                if !isSelectMode && itemCount(for: selectedTab) > 0
                    && selectedTab.section != .treeHealth {
                    Button {
                        withAnimation(DS.Anim.snappy) {
                            isSelectMode = true
                            selectedIds.removeAll()
                        }
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(DS.Font.scaled(16, weight: .semibold))
                            .foregroundColor(DS.Color.success)
                    }
                    .accessibilityLabel(L10n.t("تحديد", "Select"))
                }
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
        .onChange(of: memberVM.allMembers.count) { _ in
            rebuildTreeHealthCache()
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
        .sheet(item: $openTreeHealthFilter) { filter in
            NavigationStack {
                AdminTreeHealthView(initialFilter: filter)
                    .environmentObject(memberVM)
                    .toolbar {
                        ToolbarItem(placement: DSToolbar.cancelPlacement) {
                            Button(L10n.t("إغلاق", "Close")) { openTreeHealthFilter = nil }
                                .foregroundColor(DS.Color.primary)
                        }
                    }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            diwaniyaVM.notificationVM = notificationVM
            diwaniyaVM.canModerate = authVM.canModerate
            diwaniyaVM.authVM = authVM
            archiveVM.configure(authVM: authVM, notificationVM: notificationVM)
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
            }
            await fetchAllRegistrationMatches()
            recalculateCounts()

            // اختيار أول تاب فيه طلبات
            if let firstWithItems = cachedAvailableTabs.first {
                selectedTab = firstWithItems
            }
            // انتهى التحميل الأول — تظهر الفلاتر والطلبات بدل بطاقة التحميل
            withAnimation(.easeInOut(duration: 0.2)) { isInitialLoading = false }
        }
        .dsAlert(
            L10n.t("تأكيد الموافقة على الكل", "Confirm Approve All"),
            isPresented: $showBulkApproveChildrenConfirm
        ) {
            Button(L10n.t("الموافقة على الكل", "Approve All"), role: .destructive) {
                Task {
                    let count = await adminRequestVM.bulkApproveChildAddRequests()
                    bulkApproveResult = L10n.t(
                        "تم قبول \(count) طلب بنجاح",
                        "Successfully approved \(count) requests"
                    )
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
            isPresented: $showBulkApproveResult
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
                    let count = await bulkApproveSelected()
                    await MainActor.run {
                        bulkSelectApproveResult = L10n.t("تم قبول \(count) طلب بنجاح", "Successfully approved \(count) requests")
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
            isPresented: $showBulkSelectApproveResult
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
                    let count = await bulkRejectSelected()
                    await MainActor.run {
                        bulkSelectRejectResult = L10n.t("تم رفض \(count) طلب", "Rejected \(count) requests")
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
        .dsCenterBox(item: $healthPhoneMember) { member in
            PendingMemberPhoneSheet(member: member, activateOnSave: true)
                .environmentObject(adminRequestVM)
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
            LinkToExistingMemberSheet(pendingMember: member,
                                      suggested: orderedMatchList(for: member).map(\.member))
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
            isPresented: $showMergeSuccess
        ) {
            Button(L10n.t("حسناً", "OK")) {
                adminRequestVM.mergeResult = nil
            }
        } message: {
            Text(mergeSuccessMessage)
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
        case .healthOrphan: return cachedHealthCounts[.orphan] ?? 0
        case .healthNoName: return cachedHealthCounts[.noName] ?? 0
        case .healthBrokenParent: return cachedHealthCounts[.brokenParent] ?? 0
        case .healthHidden: return cachedHealthCounts[.hiddenFromTree] ?? 0
        case .healthDupPhone: return cachedHealthCounts[.duplicatePhone] ?? 0
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

    /// تابات مخفية من «طلبات المراجعة» لأنها مغطّاة بأقسام أخرى:
    /// «معلّق» (بدون أب) موجود في «إدارة الأعضاء ← أعضاء غير مكتملين ← بدون أب».
    /// «مخفي» (healthHidden) أُزيل بطلب المستخدم — لا يُعتبر مشكلة صحة شجرة.
    private static let hiddenTabs: Set<RequestTab> = [.healthHidden]

    // MARK: - صلاحية الإجراء حسب مجال الدور (تحديث الأدوار 2026-09-21)

    /// تابات المحتوى — الاعتماد فيها للإدارة، والمراجعة والبلاغات للمشرف
    private static let contentTabs: Set<RequestTab> = [.news, .projects, .archive, .diwaniya, .photos, .reports]

    /// هل يقدر المستخدم الحالي يعتمد عناصر هذا التاب؟
    private func canApprove(_ tab: RequestTab) -> Bool {
        if tab == .reports { return authVM.canModerateContent }
        return Self.contentTabs.contains(tab) ? authVM.canApproveContent : authVM.canApproveTreeRequests
    }

    /// هل يقدر يرفضها؟ (المشرف يتعامل مع البلاغات فقط)
    private func canReject(_ tab: RequestTab) -> Bool {
        if tab == .reports { return authVM.canModerateContent }
        return Self.contentTabs.contains(tab) ? authVM.canApproveContent : authVM.canRejectRequests
    }

    /// التابات التي يراها هذا الدور — كل دور يشوف مجاله فقط
    private func tabsForRole(_ tabs: [RequestTab]) -> [RequestTab] {
        if authVM.isAdmin { return tabs }
        if authVM.currentUser?.role == .supervisor {
            return tabs.filter { $0 == .all || Self.contentTabs.contains($0) }
        }
        // المراقب: الشجرة والأعضاء
        return tabs.filter { $0 == .all || !Self.contentTabs.contains($0) }
    }

    private func recalculateCounts() {
        cachedPendingMembers = memberVM.allMembers.filter { $0.role == .pending }
        // إعادة بناء كاش صحة الشجرة كذلك (لعدّادات التابات والقوائم)
        rebuildTreeHealthCache()
        // المجموع الكلّي عبر مصدر واحد للحقيقة — يطابق بادج «طلبات المراجعة» في لوحة الإدارة
        cachedTotalCount = Self.reviewRequestsTotal(
            memberVM: memberVM, newsVM: newsVM, adminRequestVM: adminRequestVM,
            diwaniyaVM: diwaniyaVM, projectsVM: projectsVM,
            pendingArchiveCount: pendingArchiveItems.count,
            scope: Self.reviewScope(for: authVM)
        )
        // عرض كل التابات دائماً — حتى الفارغة (المستخدم يبيها كلها مرئية)
        // ما عدا التابات المخفية (مغطّاة بأقسام أخرى).
        cachedAvailableTabs = tabsForRole(RequestTab.allCases.filter { !Self.hiddenTabs.contains($0) })
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

        // صحة الشجرة — نفس منطق rebuildTreeHealthCache (بدون «مخفي»)
        let allActive = members.filter { $0.role != .pending && $0.status != .frozen }
        let fatherIds = Set(allActive.compactMap(\.fatherId))
        let activeIds = Set(allActive.map(\.id))
        var issues: [UUID: Set<TreeHealthIssue>] = [:]
        for member in members where member.status != .frozen {
            var s = Set<TreeHealthIssue>()
            if member.fatherId == nil && !fatherIds.contains(member.id) && member.role != .pending {
                s.insert(.orphan)
            }
            let name = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty || name == "بدون اسم" { s.insert(.noName) }
            if let fid = member.fatherId, !activeIds.contains(fid) { s.insert(.brokenParent) }
            if !s.isEmpty { issues[member.id] = s }
        }
        for group in memberVM.duplicatePhoneGroups {
            for member in group { issues[member.id, default: []].insert(.duplicatePhone) }
        }
        var healthTotal = 0
        for issue in [TreeHealthIssue.orphan, .noName, .brokenParent, .duplicatePhone] {
            healthTotal += issues.values.filter { $0.contains(issue) }.count
        }

        // المحتوى والبلاغات = تبويبات `contentTabs`، والباقي الشجرة والأعضاء
        let content = newsVM.pendingNewsRequests.count
            + adminRequestVM.newsReportRequests.count
            + diwaniyaVM.pendingDiwaniyas.count
            + adminRequestVM.photoSuggestionRequests.count
            + projectsVM.pendingProjects.count
            + pendingArchiveCount
        let tree = pending
            + adminRequestVM.phoneChangeRequests.count
            + adminRequestVM.nameChangeRequests.count
            + adminRequestVM.deceasedRequests.count
            + adminRequestVM.childAddRequests.count
            + adminRequestVM.treeEditRequests.count
            + healthTotal
        switch scope {
        case .all:     return content + tree
        case .content: return content
        case .tree:    return tree
        }
    }

    // MARK: - بطاقة الرأس (صفحات الإدارة الموحّدة — طلب المالك ٢٠٢٦-٠٩-٢٧)

    /// لون مجال المشاهد — نفس منطق `tabsForRole`: الإدارة كل المجالات (كحلي)،
    /// المشرف المحتوى والبلاغات (ذهبي)، والمراقب الشجرة والأعضاء (أخضر).
    private var pageTint: Color {
        if authVM.isAdmin { return DS.Color.actionNavy }
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

    private var heroSection: some View {
        DSPageHero(
            title: L10n.t("طلبات المراجعة", "Review Requests"),
            subtitle: heroSubtitle,
            icon: "tray.full.fill",
            tint: pageTint,
            stats: heroStats
        )
    }

    /// ٣ أرقام حيّة من البيانات المحمّلة أصلاً (بلا طلبات جديدة للسيرفر): المجموع (نفس
    /// عدّاد «الكل» وبادج لوحة الإدارة)، ما وصل اليوم، وعمر أقدم طلب ينتظر — «—» أثناء التحميل.
    private var heroStats: [DSHeroStat] {
        var total = "—", today = "—", oldest = "—"
        if !isInitialLoading {
            let dates = visibleRequestDates
            total = "\(cachedTotalCount)"
            today = "\(dates.filter { Calendar.current.isDateInToday($0) }.count)"
            if let first = dates.min() { oldest = ageText(days: daysWaiting(since: first)) }
        }
        return [
            DSHeroStat(value: total, label: L10n.t("بانتظار المراجعة", "Awaiting review"), icon: "tray.full.fill"),
            DSHeroStat(value: today, label: L10n.t("جديد اليوم", "New today"), icon: "sparkles"),
            DSHeroStat(value: oldest, label: L10n.t("أقدم طلب", "Oldest request"), icon: "hourglass")
        ]
    }

    /// تواريخ الطلبات التي يراها هذا الدور (نفس فلترة قائمة «الكل») — بلا صحة الشجرة
    /// (ليست طلبات) ولا الديوانيات (بلا تاريخ).
    private var visibleRequestDates: [Date] {
        let visible = Set(tabsForRole(RequestTab.allCases))
        var dates: [Date] = []
        func add(_ tab: RequestTab, _ items: [Date?]) {
            guard visible.contains(tab) else { return }
            dates.append(contentsOf: items.compactMap { $0 })
        }
        add(.joinRequests, pendingMembers.map { Self.requestDate($0.createdAt) })
        add(.news, newsVM.pendingNewsRequests.map { Optional($0.timestamp) })
        add(.reports, adminRequestVM.newsReportRequests.map { Self.requestDate($0.createdAt) })
        add(.phone, adminRequestVM.phoneChangeRequests.map { Self.requestDate($0.createdAt) })
        add(.nameChange, adminRequestVM.nameChangeRequests.map { Self.requestDate($0.createdAt) })
        add(.deceased, adminRequestVM.deceasedRequests.map { Self.requestDate($0.createdAt) })
        add(.children, adminRequestVM.childAddRequests.map { Self.requestDate($0.createdAt) })
        add(.photos, adminRequestVM.photoSuggestionRequests.map { Self.requestDate($0.createdAt) })
        add(.projects, projectsVM.pendingProjects.map { Self.requestDate($0.createdAt) })
        add(.archive, pendingArchiveItems.map { Optional($0.createdAt) })
        // طلبات الشجرة تتبع في «الكل» تبويب «طلب آخر» (allItemTab)
        add(.treeOther, adminRequestVM.treeEditRequests.map { Self.requestDate($0.createdAt) })
        return dates
    }

    // MARK: - الفلاتر (مستويان: الأقسام ← تبويبات القسم)

    /// الأقسام الظاهرة لهذا الدور — كل دور يشوف تبويبات مجاله فقط (`availableTabs` = `tabsForRole`)
    private var visibleSections: [RequestSection] {
        RequestSection.allCases.filter { section in availableTabs.contains { $0.section == section } }
    }

    private func countOrNil(_ n: Int) -> Int? { n > 0 ? n : nil }

    /// عدّادات شرائح القسم بلون مجاله: المحتوى ذهبي، والشجرة والأعضاء أخضر
    private func sectionTint(_ section: RequestSection) -> Color {
        section == .content ? DS.Color.composerLibrary : DS.Color.composerProject
    }

    /// اختيار القسم — نفس سلوك الشرائح السابقة: «الكل» يرجع للكل، والقسم يفتح أول تبويب فيه
    private var sectionSelection: Binding<RequestSection?> {
        Binding(
            get: { selectedTab == .all ? nil : selectedSection },
            set: { section in
                if let section {
                    selectedSection = section
                    if let firstTab = RequestTab.allCases.first(where: { $0.section == section && !Self.hiddenTabs.contains($0) }) {
                        selectedTab = firstTab
                    }
                } else {
                    selectedTab = .all
                    selectedSection = nil
                }
            }
        )
    }

    // MARK: - شبكة أنواع الطلبات (بلاطات ديناميكية)

    /// الأنواع التي تظهر: «الكل» ثم كل نوع في مجال الدور عليه طلبات (بترتيب الأقسام)،
    /// ويبقى المختار ظاهراً ولو صار فارغاً حتى لا يختفي من تحت إصبع المستخدم.
    private var tileTabs: [RequestTab] {
        let withItems = availableTabs.filter { $0 != .all && (itemCount(for: $0) > 0 || $0 == selectedTab) }
        return [.all] + withItems
    }

    private var typeTiles: some View {
        let tabs = tileTabs
        let columns = 5
        let rows = stride(from: 0, to: tabs.count, by: columns).map { Array(tabs[$0..<min($0 + columns, tabs.count)]) }
        return VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r], id: \.self) { tab in
                        typeTile(tab)
                    }
                    // أكمل الصف الأخير بفراغات حتى تبقى البلاطات بنفس العرض
                    ForEach(0..<(columns - rows[r].count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.82),
                   value: tabs)
    }

    /// بلاطة نوع: أيقونة ملوّنة كبيرة وعليها العدد، وتحتها الاسم — المختارة ممتلئة بلونها
    private func typeTile(_ tab: RequestTab) -> some View {
        let selected = selectedTab == tab
        let count = tab == .all ? cachedTotalCount : itemCount(for: tab)
        let tint = (tab == .all ? pageTint : tab.color).dsReadableGlyph
        let title = tab == .all ? L10n.t("الكل", "All") : chipTitle(tab)
        return Button {
            guard !selected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.82)) {
                selectedTab = tab
                selectedSection = tab.section
            }
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(selected ? .white : tint)
                        .frame(width: 38, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected
                                      ? AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.78)],
                                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                      : AnyShapeStyle(tint.opacity(0.14)))
                        )
                        .shadow(color: selected && !reduceMotion ? tint.opacity(0.4) : .clear, radius: 6, x: 0, y: 3)
                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(DS.Font.plex(9.5, weight: .heavy))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 17, minHeight: 16)
                            .background(Capsule().fill(selected ? Color.black.opacity(0.35) : DS.Color.error))
                            .overlay(Capsule().strokeBorder(DS.Color.surface, lineWidth: 1.5))
                            .offset(x: 6, y: -5)
                            .contentTransition(.numericText())
                    }
                }
                .scaleEffect(selected && !reduceMotion ? 1.05 : 1)
                .accessibilityHidden(true)

                Text(title)
                    .font(DS.Font.plex(10, weight: .bold))
                    .foregroundColor(selected ? tint : DS.Color.fieldLabel)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .frame(height: 25, alignment: .top)
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(selected ? tint.opacity(0.10) : DS.Color.surface))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(selected ? tint.opacity(0.6) : DS.Color.textTertiary.opacity(0.12),
                              lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
        .transition(.scale(scale: 0.8).combined(with: .opacity))
        .accessibilityLabel(count > 0 ? "\(title)، \(count)" : title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// المستوى الأول: «الكل» + أقسام مجال الدور — بطاقات بأيقونات ملوّنة كبيرة وتحتها الاسم
    /// والعدد، والمختارة مظلّلة بلونها (اختيار المالك ٢٠٢٦-٠٩-٢٧)
    private var sectionChips: some View {
        var cards: [(id: RequestSection?, title: String, icon: String, color: Color, count: Int)] = [
            (nil, L10n.t("الكل", "All"), RequestTab.all.icon, DS.Color.primary, cachedTotalCount)
        ]
        cards += visibleSections.map { section in
            (section, section.title, section.icon, section.color, sectionCount(section))
        }
        let selected = sectionSelection.wrappedValue
        return HStack(spacing: 6) {
            ForEach(cards, id: \.title) { card in
                sectionCard(title: card.title, icon: card.icon, color: card.color,
                            count: card.count, isSelected: card.id == selected) {
                    guard card.id != selected else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.15)
                                               : .spring(response: 0.4, dampingFraction: 0.82)) {
                        sectionSelection.wrappedValue = card.id
                    }
                }
            }
        }
    }

    /// بطاقة قسم: أيقونة ملوّنة كبيرة، تحتها الاسم ثم العدد — المختارة ممتلئة الأيقونة ومظلّلة بلونها
    private func sectionCard(title: String, icon: String, color: Color, count: Int,
                             isSelected: Bool, action: @escaping () -> Void) -> some View {
        let tint = color.dsReadableGlyph
        return Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(isSelected ? .white : tint)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.8)],
                                                                         startPoint: .topLeading,
                                                                         endPoint: .bottomTrailing))
                                         : AnyShapeStyle(tint.opacity(0.14))))
                    .shadow(color: isSelected && !reduceMotion ? tint.opacity(0.35) : .clear, radius: 5, x: 0, y: 3)
                    .scaleEffect(isSelected && !reduceMotion ? 1.06 : 1)
                    .accessibilityHidden(true)
                Text(title)
                    .font(DS.Font.plex(11.5, weight: .bold))
                    .foregroundColor(isSelected ? tint : DS.Color.fieldLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(count > 0 ? "\(count)" : "—")
                    .font(DS.Font.plex(11, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(count > 0 ? (isSelected ? .white : tint) : DS.Color.textTertiary)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 22, minHeight: 17)
                    .background(Capsule().fill(count > 0 ? (isSelected ? tint : tint.opacity(0.14)) : Color.clear))
            }
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? tint.opacity(0.10) : DS.Color.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? tint.opacity(0.55) : DS.Color.textTertiary.opacity(0.12),
                              lineWidth: isSelected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(count > 0 ? "\(title)، \(count)" : title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// المستوى الثاني: كل تبويبات القسم المختار في مجال الدور — حتى الفارغة (طلب المستخدم)
    private func tabChips(for section: RequestSection) -> some View {
        let tabs = availableTabs.filter { $0.section == section }
        return DSFilterChips(
            options: tabs.map { tab in
                DSFilterOption(id: tab, title: chipTitle(tab), icon: tab.icon,
                               count: countOrNil(itemCount(for: tab)))
            },
            selection: $selectedTab,
            tint: section.color.dsReadableGlyph
        )
    }

    /// داخل قسم «الشجرة» لا حاجة لتكرار «(شجرة)» في كل شريحة
    private func chipTitle(_ tab: RequestTab) -> String {
        guard tab.section == .tree else { return tab.title }
        return tab.title
            .replacingOccurrences(of: " (شجرة)", with: "")
            .replacingOccurrences(of: "Tree · ", with: "")
    }

    /// مجموع طلبات القسم.
    private func sectionCount(_ section: RequestSection) -> Int {
        RequestTab.allCases
            .filter { $0.section == section && !Self.hiddenTabs.contains($0) }
            .reduce(0) { $0 + itemCount(for: $1) }
    }

    /// شريط ملخّص التحديد — يحلّ محل الفلاتر في وضع التحديد: «إلغاء» · العدد · «تحديد الكل».
    private var selectionSummaryBar: some View {
        // تحديد الكل في التاب الحالي
        let currentIds = currentTabIds
        let allSelected = !currentIds.isEmpty && currentIds.allSatisfy { selectedIds.contains($0) }
        return HStack(spacing: DS.Spacing.xs) {
            Button {
                withAnimation(DS.Anim.snappy) {
                    isSelectMode = false
                    selectedIds.removeAll()
                }
            } label: {
                Text(L10n.t("إلغاء", "Cancel"))
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(DS.Color.error)
                    .padding(.horizontal, DS.Spacing.md)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            SysStatusChip(text: L10n.t("اختيار \(selectedIds.count)", "Selected \(selectedIds.count)"),
                          icon: "checkmark.circle.fill",
                          tint: DS.Color.primary)

            Spacer(minLength: 0)

            Button {
                withAnimation(DS.Anim.snappy) {
                    if allSelected {
                        currentIds.forEach { selectedIds.remove($0) }
                    } else {
                        currentIds.forEach { selectedIds.insert($0) }
                    }
                }
            } label: {
                Text(allSelected
                     ? L10n.t("إلغاء الكل", "Clear all")
                     : L10n.t("تحديد الكل", "Select all"))
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(DS.Color.primary)
                    .padding(.horizontal, DS.Spacing.md)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 3)
        .background(Capsule().fill(DS.Color.surface))
        .overlay(Capsule().strokeBorder(DS.Color.textTertiary.opacity(0.12), lineWidth: 1))
    }

    /// شريط العمليات الجماعية أسفل الشاشة: العدد ← «رفض» (لمن يملكه) ← «قبول» الكحلي
    private var bulkActionBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            // عداد المحددين
            VStack(spacing: 0) {
                Text("\(selectedIds.count)")
                    .font(DS.Font.plex(18, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .monospacedDigit()
                Text(L10n.t("محدد", "selected"))
                    .font(DS.Font.plex(11, weight: .semibold))
                    .foregroundColor(DS.Color.textTertiary)
            }
            .frame(minWidth: 44)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            // زر الرفض — يظهر فقط لمن يملك الصلاحية
            if authVM.canRejectRequests {
                Button {
                    showBulkRejectConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(L10n.t("رفض", "Reject"))
                            .font(DS.Font.plex(14, weight: .bold))
                    }
                    .foregroundColor(DS.Color.error)
                    .padding(.horizontal, DS.Spacing.lg)
                    .frame(minHeight: 44)
                    .background(DS.Color.error.opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(DS.Color.error.opacity(0.28), lineWidth: 1))
                    .contentShape(Capsule())
                }
                .disabled(adminRequestVM.isLoading)
                .buttonStyle(DSScaleButtonStyle())
            }

            // زر القبول
            Button {
                showBulkApproveConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(L10n.t("قبول", "Approve"))
                        .font(DS.Font.plex(14, weight: .bold))
                }
                .foregroundColor(DSActionFill.label(enabled: !adminRequestVM.isLoading))
                .padding(.horizontal, DS.Spacing.lg)
                .frame(minHeight: 44)
                .background(DSActionFill.style(enabled: !adminRequestVM.isLoading), in: Capsule())
                .contentShape(Capsule())
            }
            .disabled(adminRequestVM.isLoading)
            .buttonStyle(DSScaleButtonStyle())
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(
            DS.Color.surface
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(DS.Color.textTertiary.opacity(0.12))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// معرّفات عناصر التاب الحالي (للاستخدام في "تحديد الكل").
    private var currentTabIds: [UUID] {
        switch selectedTab {
        case .all:
            return pendingMembers.map { $0.id }
                + newsVM.pendingNewsRequests.map { $0.id }
                + adminRequestVM.newsReportRequests.map { $0.id }
                + adminRequestVM.phoneChangeRequests.map { $0.id }
                + adminRequestVM.nameChangeRequests.map { $0.id }
                + diwaniyaVM.pendingDiwaniyas.map { $0.id }
                + adminRequestVM.deceasedRequests.map { $0.id }
                + adminRequestVM.childAddRequests.map { $0.id }
                + adminRequestVM.treeEditRequests.map { $0.id }
                + adminRequestVM.photoSuggestionRequests.map { $0.id }
                + projectsVM.pendingProjects.map { $0.id }
                + pendingArchiveItems.map { $0.id }
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
        // الصحة لا تدعم التحديد المتعدّد (الإجراءات تفصيلية)
        case .healthOrphan, .healthNoName, .healthBrokenParent, .healthHidden, .healthDupPhone:
            return []
        }
    }

    // MARK: - القائمة

    /// بطاقة الرأس ← (تحميل) ← الفلاتر ← الطلبات أو بطاقة «لا توجد طلبات» — صفوف قائمة واحدة
    /// تتمرّر معاً. بقيت `List` لأجل أزرار السحب (موافقة / رفض / حذف).
    /// (أُزيل `.id(selectedTab)` — كان يعيد بناء القائمة كلها ومعها بطاقة الرأس وحركتها عند كل تبويب.)
    private var requestsList: some View {
        List {
            heroSection
                .reviewListRow(top: DS.Spacing.sm, bottom: DS.Spacing.sm)

            if isInitialLoading {
                SysStateCard(icon: "tray.full.fill",
                             title: L10n.t("جارٍ تحميل الطلبات…", "Loading requests…"),
                             tint: pageTint,
                             isLoading: true)
                    .padding(.top, DS.Spacing.xs)
                    .dsStaggerIn(1)
                    .reviewListRow()
            } else {
                // شبكة أنواع الطلبات (فكرة جديدة — طلب المالك): بلاطة لكل نوع فيه طلبات فقط،
                // بأيقونة ملوّنة كبيرة واسمه وعدده — ضغطة واحدة تفتح النوع (بدل قسم ثم نوع).
                // وفي وضع التحديد يحلّ محلها شريط الملخّص أعلاه.
                if totalCount > 0 && !isSelectMode {
                    typeTiles
                        .dsStaggerIn(1)
                        .reviewListRow(top: 0, bottom: DS.Spacing.xs)
                }

                if totalCount == 0 || itemCount(for: selectedTab) == 0 {
                    emptyState
                        .padding(.top, DS.Spacing.xs)
                        .dsStaggerIn(2)
                        .reviewListRow()
                } else {
                    tabRows
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .animation(reduceMotion ? Animation.easeInOut(duration: 0.15) : Animation.snappy(duration: 0.2),
                   value: selectedTab)
    }

    /// صفوف التبويب المختار — نفس الاستدعاءات والصلاحيات السابقة تماماً
    @ViewBuilder
    private var tabRows: some View {
        // زر الموافقة على الكل — أبناء فقط
        if selectedTab == .children && adminRequestVM.childAddRequests.count > 1 {
            SysActionButton(
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
            ForEach(pendingMembers) { member in
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
            ForEach(adminRequestVM.newsReportRequests) { request in
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
            ForEach(adminRequestVM.phoneChangeRequests) { request in
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
            ForEach(adminRequestVM.nameChangeRequests) { request in
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
            ForEach(adminRequestVM.deceasedRequests) { request in
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
            ForEach(adminRequestVM.childAddRequests) { request in
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
            ForEach(adminRequestVM.photoSuggestionRequests) { request in
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
        case .healthOrphan:
            treeHealthList(issue: .orphan, color: RequestTab.healthOrphan.color)
        case .healthNoName:
            treeHealthList(issue: .noName, color: RequestTab.healthNoName.color)
        case .healthBrokenParent:
            treeHealthList(issue: .brokenParent, color: RequestTab.healthBrokenParent.color)
        case .healthHidden:
            treeHealthList(issue: .hiddenFromTree, color: RequestTab.healthHidden.color)
        case .healthDupPhone:
            treeHealthList(issue: .duplicatePhone, color: RequestTab.healthDupPhone.color)
        case .all:
            allRequestsContent()
        }
    }

    // MARK: - Select Mode Helpers

    @ViewBuilder
    private func selectAllButton(ids: [UUID]) -> some View {
        // "تحديد الكل" انتقل إلى selectionSummaryBar أعلى الشاشة — هذا أصبح no-op
        // (احتفظنا بالاستدعاءات لتجنّب تعديل 12 موقعاً في tabContent)
        if false {
            let allSelected = ids.allSatisfy { selectedIds.contains($0) }
            Button {
                withAnimation(DS.Anim.snappy) {
                    if allSelected {
                        ids.forEach { selectedIds.remove($0) }
                    } else {
                        ids.forEach { selectedIds.insert($0) }
                    }
                }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: allSelected ? "checkmark.circle.fill" : "circle.dotted")
                        .font(DS.Font.scaled(15, weight: .semibold))
                    Text(allSelected
                        ? L10n.t("إلغاء تحديد الكل", "Deselect All")
                        : L10n.t("تحديد الكل (\(ids.count))", "Select All (\(ids.count))")
                    )
                    .font(DS.Font.callout)
                }
                .foregroundColor(DS.Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.xs)
            }
            .buttonStyle(DSScaleButtonStyle())
            .listRowBackground(DS.Color.primary.opacity(0.05))
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: DS.Spacing.xs, leading: DS.Spacing.lg, bottom: DS.Spacing.xs, trailing: DS.Spacing.lg))
        }
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
        accentColor: Color = DS.Color.primary,
        approveLabel: String? = nil,
        approveIcon: String = "checkmark",
        approveColor: Color = DS.Color.success,
        onApprove: (() -> Void)? = nil,
        onReject: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isSelected = isSelectMode && selectedIds.contains(id)
        // المحتوى — قابل للنقر، يفتح تفاصيل الطلب (وفي وضع التحديد يحدّده)
        return Button {
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
                        .font(DS.Font.scaled(22, weight: .regular))
                        .foregroundColor(isSelected ? DS.Color.primary : DS.Color.textTertiary)
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                // سهم — إشارة إن الصف يفتح التفاصيل (خارج وضع التحديد)
                if !isSelectMode {
                    SysChevron()
                }
            }
            .dsRowBox()
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.primary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .strokeBorder(DS.Color.primary.opacity(0.55), lineWidth: 1.5)
                        )
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: DS.Spacing.lg, bottom: 4, trailing: DS.Spacing.lg))
        // الموافقة/الرفض عبر السحب — خارج وضع التحديد فقط
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isSelectMode, canApprove(forTab ?? selectedTab), let onApprove {
                Button(action: onApprove) {
                    Label(approveLabel ?? L10n.t("موافقة", "Approve"), systemImage: approveIcon)
                }
                .tint(approveColor)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !isSelectMode, let onReject, canReject(forTab ?? selectedTab) {
                Button(action: onReject) {
                    Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                }
                .tint(DS.Color.warning)
            }
            // حذف نهائي — جنب الرفض (للمالك/المدير)
            if !isSelectMode, let onDelete, authVM.canDeleteMembers {
                Button(role: .destructive, action: onDelete) {
                    Label(L10n.t("حذف", "Delete"), systemImage: "trash.fill")
                }
                .tint(DS.Color.error)
            }
        }
    }

    private func bulkApproveSelected() async -> Int {
        let ids = Array(selectedIds)
        var count = 0
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
                    count += 1
                }
            }
        case .phone:
            for id in ids {
                if let req = adminRequestVM.phoneChangeRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.approvePhoneChangeRequest(request: req)
                    count += 1
                }
            }
        case .nameChange:
            for id in ids {
                if let req = adminRequestVM.nameChangeRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.approveNameChangeRequest(request: req)
                    count += 1
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
                    count += 1
                }
            }
        case .children:
            for id in ids {
                if let req = adminRequestVM.childAddRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.acknowledgeChildAddRequest(request: req)
                    count += 1
                }
            }
        case .photos:
            for id in ids {
                if let req = adminRequestVM.photoSuggestionRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.approvePhotoSuggestion(request: req)
                    count += 1
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
                    count += 1
                }
            }
        case .healthOrphan, .healthNoName, .healthBrokenParent, .healthHidden, .healthDupPhone:
            break // التحديد المتعدّد غير مدعوم للصحة — الإجراءات تفصيلية لكل عضو
        }
        return count
    }

    private func bulkRejectSelected() async -> Int {
        let ids = Array(selectedIds)
        var count = 0
        switch selectedTab {
        case .all:
            count = await bulkRejectAcrossAllTypes(ids: ids)
        case .joinRequests:
            for id in ids {
                await adminRequestVM.rejectOrDeleteMember(memberId: id)
                count += 1
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
                    count += 1
                }
            }
        case .phone:
            for id in ids {
                if let req = adminRequestVM.phoneChangeRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.rejectPhoneChangeRequest(request: req)
                    count += 1
                }
            }
        case .nameChange:
            for id in ids {
                if let req = adminRequestVM.nameChangeRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.rejectNameChangeRequest(request: req)
                    count += 1
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
                    count += 1
                }
            }
        case .children:
            for id in ids {
                if let req = adminRequestVM.childAddRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.rejectChildAddRequest(request: req)
                    count += 1
                }
            }
        case .photos:
            for id in ids {
                if let req = adminRequestVM.photoSuggestionRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.rejectPhotoSuggestion(request: req)
                    count += 1
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
                    count += 1
                }
            }
        case .healthOrphan, .healthNoName, .healthBrokenParent, .healthHidden, .healthDupPhone:
            break // الصحة لا تدعم الرفض الدفعي
        }
        return count
    }

    /// قائمة عناصر صحة الشجرة لفئة معيّنة — صف بسيط بدون موافقة/رفض، تفتح شيت تفاصيل العضو بالنقر.
    @ViewBuilder
    private func treeHealthList(issue: TreeHealthIssue, color: Color) -> some View {
        ForEach(healthMembers(for: issue)) { member in
            selectableRow(
                id: member.id,
                accentColor: color,
                onApprove: nil,
                onReject: nil,
                onTap: { selectedDetail = .healthMember(member, issue) }
            ) {
                treeHealthRow(member: member, issue: issue, color: color)
            }
            // أزرار سحب: تفعيل + إضافة رقم (يمين) — حذف (يسار)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if authVM.canModerate {
                    // ربط/دمج العضو المعلّق بعضو موجود بالشجرة (يربط ويفعّل حسابه).
                    Button {
                        memberToLink = member
                    } label: {
                        Label(L10n.t("ربط", "Link"), systemImage: "link.badge.plus")
                    }
                    .tint(DS.Color.info)

                    Button {
                        healthPhoneMember = member
                    } label: {
                        Label(L10n.t("رقم", "Number"), systemImage: "phone.badge.plus")
                    }
                    .tint(DS.Color.primary)

                    Button {
                        Task { await adminRequestVM.activateAccount(memberId: member.id) }
                    } label: {
                        Label(L10n.t("تفعيل", "Activate"), systemImage: "checkmark.circle.fill")
                    }
                    .tint(DS.Color.success)
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if authVM.canDeleteMembers {
                    Button(role: .destructive) {
                        Task { await adminRequestVM.rejectOrDeleteMember(memberId: member.id) }
                    } label: {
                        Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                    }
                }
            }
        }
    }

    /// صف عنصر صحة الشجرة — اسم العضو + شارة المشكلة بلونها + وقت إضافته.
    private func treeHealthRow(member: FamilyMember, issue: TreeHealthIssue, color: Color) -> some View {
        let added: String? = member.createdAt.map { raw in
            let formatted = formatRegistrationDate(raw)
            return L10n.t("أُضيف: \(formatted)", "Added: \(formatted)")
        }
        return requestRowHeader(
            icon: issue.asTab.icon,
            tint: color,
            title: member.fullName.isEmpty ? L10n.t("بدون اسم", "(no name)") : member.displayFullName,
            subtitle: added
        ) {
            SysStatusChip(text: issue.asTab.title, tint: color)
        }
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
        ForEach(treeEdits(action: action)) { request in
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
        return VStack(alignment: .leading, spacing: 6) {
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
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.forward.circle.fill")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundColor(DS.Color.success)
                                .accessibilityHidden(true)
                            Text(L10n.t("القيمة الجديدة:", "New:"))
                                .font(DS.Font.plex(11))
                                .foregroundColor(DS.Color.textTertiary)
                            Text(newDisplay)
                                .font(DS.Font.plex(12, weight: .bold))
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
        case health(FamilyMember, TreeHealthIssue)

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
            case .health(let m, let i): return "health-\(i)-\(m.id)"
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
        case .health(let m, _): return parseISODate(m.createdAt)
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
        for issue in [TreeHealthIssue.orphan, .noName, .brokenParent, .duplicatePhone] {
            items += healthMembers(for: issue).map { .health($0, issue) }
        }
        // «الكل» يعرض لكل دور عناصر مجاله فقط — مثل التابات (فحص الثغرات)
        let visible = Set(tabsForRole(RequestTab.allCases))
        return items
            .filter { visible.contains(allItemTab($0)) }
            .sorted { allItemDate($0) > allItemDate($1) }
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
        case .health(_, let issue): return issue.asTab
        }
    }

    private func treeEditColor(_ action: TreeEditAction) -> Color {
        switch action {
        case .add: return RequestTab.treeAdd.color
        case .editName: return RequestTab.treeEditName.color
        case .editPhone: return RequestTab.treeEditPhone.color
        case .editBirth: return DS.Color.warning
        case .deceased: return RequestTab.treeDeceased.color
        case .addDeathDate: return DS.Color.textTertiary
        case .addPhoto: return DS.Color.primary
        case .delete: return RequestTab.treeDelete.color
        case .other: return DS.Color.accent
        }
    }

    /// محتوى تاب "الكل" — كل الأنواع مدمجة ومرتّبة حسب الوقت (الأحدث أولاً).
    /// «الكل» مفلتر بمجال الدور — وإن لم يبقَ فيه شيء تظهر بطاقة «لا توجد طلبات» بدل فراغ.
    @ViewBuilder
    private func allRequestsContent() -> some View {
        let items = sortedAllItems
        if items.isEmpty {
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
        case .health(let member, let issue):
            selectableRow(
                id: member.id, forTab: issue.asTab, accentColor: issue.asTab.color,
                onApprove: nil, onReject: nil,
                onTap: { selectedDetail = .healthMember(member, issue) }
            ) { treeHealthRow(member: member, issue: issue, color: issue.asTab.color) }
            // أزرار سحب: تفعيل + إضافة رقم (يمين) — حذف (يسار)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if authVM.canModerate {
                    // ربط/دمج العضو المعلّق بعضو موجود بالشجرة (يربط ويفعّل حسابه).
                    Button {
                        memberToLink = member
                    } label: {
                        Label(L10n.t("ربط", "Link"), systemImage: "link.badge.plus")
                    }
                    .tint(DS.Color.info)

                    Button {
                        healthPhoneMember = member
                    } label: {
                        Label(L10n.t("رقم", "Number"), systemImage: "phone.badge.plus")
                    }
                    .tint(DS.Color.primary)

                    Button {
                        Task { await adminRequestVM.activateAccount(memberId: member.id) }
                    } label: {
                        Label(L10n.t("تفعيل", "Activate"), systemImage: "checkmark.circle.fill")
                    }
                    .tint(DS.Color.success)
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if authVM.canDeleteMembers {
                    Button(role: .destructive) {
                        Task { await adminRequestVM.rejectOrDeleteMember(memberId: member.id) }
                    } label: {
                        Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                    }
                }
            }
        }
    }

    /// موافقة دفعية تعبر كل الأنواع (لوضع "الكل").
    private func bulkApproveAcrossAllTypes(ids: [UUID]) async -> Int {
        var count = 0
        let idSet = Set(ids)

        for id in ids {
            if pendingMembers.contains(where: { $0.id == id }) {
                _ = await adminRequestVM.bulkApproveJoinRequests(memberIds: [id])
                count += 1
            } else if let post = newsVM.pendingNewsRequests.first(where: { $0.id == id }) {
                await newsVM.approveNewsPost(postId: post.id); count += 1
            } else if let req = adminRequestVM.newsReportRequests.first(where: { $0.id == id }) {
                await adminRequestVM.approveNewsReport(request: req); count += 1
            } else if let req = adminRequestVM.phoneChangeRequests.first(where: { $0.id == id }) {
                await adminRequestVM.approvePhoneChangeRequest(request: req); count += 1
            } else if let req = adminRequestVM.nameChangeRequests.first(where: { $0.id == id }) {
                await adminRequestVM.approveNameChangeRequest(request: req); count += 1
            } else if let d = diwaniyaVM.pendingDiwaniyas.first(where: { $0.id == id }),
                      let adminId = authVM.currentUser?.id {
                await diwaniyaVM.approveDiwaniya(id: d.id, adminId: adminId); count += 1
            } else if let req = adminRequestVM.deceasedRequests.first(where: { $0.id == id }) {
                await adminRequestVM.approveDeceasedRequest(request: req); count += 1
            } else if let req = adminRequestVM.childAddRequests.first(where: { $0.id == id }) {
                await adminRequestVM.acknowledgeChildAddRequest(request: req); count += 1
            } else if let req = adminRequestVM.photoSuggestionRequests.first(where: { $0.id == id }) {
                await adminRequestVM.approvePhotoSuggestion(request: req); count += 1
            } else if let proj = projectsVM.pendingProjects.first(where: { $0.id == id }),
                      let adminId = authVM.currentUser?.id {
                await projectsVM.approveProject(id: proj.id, approvedBy: adminId); count += 1
            } else if let item = pendingArchiveItems.first(where: { $0.id == id }) {
                await archiveVM.approveItem(item); count += 1
            } else if let req = adminRequestVM.treeEditRequests.first(where: { $0.id == id }) {
                await adminRequestVM.approveTreeEditRequest(request: req); count += 1
            }
        }
        _ = idSet // silence unused
        return count
    }

    /// رفض دفعي يعبر كل الأنواع (لوضع "الكل").
    private func bulkRejectAcrossAllTypes(ids: [UUID]) async -> Int {
        var count = 0

        for id in ids {
            if pendingMembers.contains(where: { $0.id == id }) {
                await adminRequestVM.rejectOrDeleteMember(memberId: id); count += 1
            } else if let post = newsVM.pendingNewsRequests.first(where: { $0.id == id }) {
                await newsVM.rejectNewsPost(postId: post.id); count += 1
            } else if let req = adminRequestVM.newsReportRequests.first(where: { $0.id == id }) {
                await adminRequestVM.rejectNewsReport(request: req); count += 1
            } else if let req = adminRequestVM.phoneChangeRequests.first(where: { $0.id == id }) {
                await adminRequestVM.rejectPhoneChangeRequest(request: req); count += 1
            } else if let req = adminRequestVM.nameChangeRequests.first(where: { $0.id == id }) {
                await adminRequestVM.rejectNameChangeRequest(request: req); count += 1
            } else if let d = diwaniyaVM.pendingDiwaniyas.first(where: { $0.id == id }) {
                await diwaniyaVM.rejectDiwaniya(id: d.id); count += 1
            } else if let req = adminRequestVM.deceasedRequests.first(where: { $0.id == id }) {
                await adminRequestVM.rejectDeceasedRequest(request: req); count += 1
            } else if let req = adminRequestVM.childAddRequests.first(where: { $0.id == id }) {
                await adminRequestVM.rejectChildAddRequest(request: req); count += 1
            } else if let req = adminRequestVM.photoSuggestionRequests.first(where: { $0.id == id }) {
                await adminRequestVM.rejectPhotoSuggestion(request: req); count += 1
            } else if projectsVM.pendingProjects.contains(where: { $0.id == id }) {
                await projectsVM.rejectProject(id: id); count += 1
            } else if let item = pendingArchiveItems.first(where: { $0.id == id }) {
                await archiveVM.rejectItem(item); count += 1
            } else if let req = adminRequestVM.treeEditRequests.first(where: { $0.id == id }) {
                await adminRequestVM.rejectTreeEditRequest(request: req, reason: nil); count += 1
            }
        }
        return count
    }

    // MARK: - Empty State

    /// بطاقة «لا توجد طلبات» الموحّدة — للقائمة كلها أو للتبويب المختار
    private var emptyState: some View {
        SysStateCard(
            icon: "checkmark.circle.fill",
            title: L10n.t("لا توجد طلبات معلقة", "No pending requests"),
            hint: (totalCount == 0 || selectedTab == .all)
                ? L10n.t("كل الطلبات متابَعة — ما فيه شي ينتظر قرارك",
                         "All caught up — nothing is awaiting your decision")
                : L10n.t("لا شيء في «\(selectedTab.title)» الآن",
                         "Nothing in \(selectedTab.title) right now"),
            tint: DS.Color.success
        )
    }

    // MARK: - Join Request Row

    private typealias JoinMatch = (member: FamilyMember, matchCount: Int, matchedParts: [String], isRegistrationMatch: Bool)

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
                joinPersonAvatar(member, ring: hasMatches ? DS.Color.success : DS.Color.warning, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(member.displayFullName)
                        .font(DS.Font.plex(14.5, weight: .bold))
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    joinStatusLine(matches: results.count, fromWeb: fromWeb)
                }

                Spacer(minLength: DS.Spacing.xs)

                if let age {
                    Text(age)
                        .font(DS.Font.plex(11, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize()
                }
            }

            if let phone {
                HStack(spacing: DS.Spacing.sm) {
                    metaItem("phone.fill", KuwaitPhone.display(phone), color: DS.Color.fieldValue)
                    Spacer(minLength: 0)
                    if let wa = KuwaitPhone.whatsappURL(phone) {
                        roundContactButton(icon: "message.fill", tint: DS.Color.success,
                                           label: L10n.t("واتساب", "WhatsApp")) {
                            UIApplication.shared.open(wa)
                        }
                    }
                }
                .padding(.leading, 56)   // تحت الاسم (الصورة ٤٤ + المسافة)
            }

            if hasMatches {
                joinBestMatches(for: member, results: results)
            }
        }
    }

    /// سطر حالة هادئ بلا شارات: «٣ مطابقات في الشجرة» أو «اسم جديد» · «من الموقع»
    private func joinStatusLine(matches: Int, fromWeb: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: matches > 0 ? "checkmark.seal.fill" : "sparkles")
                .font(.system(size: 10, weight: .bold))
                .accessibilityHidden(true)
            Text(matches > 0 ? L10n.t("\(matches) مطابقة في الشجرة", "\(matches) in the tree")
                             : L10n.t("اسم جديد", "New name"))
            if fromWeb {
                Text("·").foregroundColor(DS.Color.textTertiary)
                Image(systemName: "globe")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(DS.Color.info.dsReadableGlyph)
                    .accessibilityHidden(true)
                Text(L10n.t("من الموقع", "From website"))
                    .foregroundColor(DS.Color.info.dsReadableGlyph)
            }
        }
        .font(DS.Font.plex(11.5, weight: .semibold))
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
            Circle().fill(DS.Color.actionNavy.dsReadableGlyph.opacity(0.08))
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
                    .foregroundColor(DS.Color.actionNavy.dsReadableGlyph)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(ringColor, lineWidth: size > 60 ? 3 : 2))
        .accessibilityHidden(true)
    }

    /// زر تواصل دائري صغير (واتساب/اتصال) بمساحة ضغط ٤٤ نقطة
    private func roundContactButton(icon: String, tint: Color, label: String,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(tint.dsReadableGlyph)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.dsReadableGlyph.opacity(0.12)))
                .padding(5)
                .contentShape(Rectangle())
                .padding(-5)
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(label)
    }

    /// أقرب تطابق فقط — والباقي بزر «عرض كل المطابقات»
    @ViewBuilder
    private func joinBestMatches(for member: FamilyMember, results: [JoinMatch]) -> some View {
        let isExpanded = expandedMatchMembers.contains(member.id)
        let visible = isExpanded ? results : Array(results.prefix(1))
        VStack(spacing: 6) {
            ForEach(visible, id: \.member.id) { match in
                joinMatchRow(match: match, pendingMember: member)
            }
            if results.count > 1 && !isExpanded {
                Button {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) {
                        _ = expandedMatchMembers.insert(member.id)
                    }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(L10n.t("عرض كل المطابقات (\(results.count))",
                                    "Show all matches (\(results.count))"))
                            .font(DS.Font.plex(11.5, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .accessibilityHidden(true)
                    }
                    .foregroundColor(DS.Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DSScaleButtonStyle())
            }
        }
        .padding(.leading, 56)   // تحت الاسم (الصورة ٤٤ + المسافة)
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

    private func joinMatchRow(match: (member: FamilyMember, matchCount: Int, matchedParts: [String], isRegistrationMatch: Bool), pendingMember: FamilyMember) -> some View {
        let totalParts = max(
            pendingMember.fullName.split(whereSeparator: \.isWhitespace).count,
            match.member.fullName.split(whereSeparator: \.isWhitespace).count
        )
        let hasNameMatch = match.matchCount >= 2
        let matchPercent = hasNameMatch ? Int(Double(match.matchCount) / Double(max(totalParts, 1)) * 100) : 0

        return HStack(spacing: DS.Spacing.sm) {
            // نسبة التطابق كحلقة صغيرة
            SysRing(progress: Double(matchPercent) / 100, tint: DS.Color.primary, lineWidth: 3, size: 36) {
                Text(L10n.t("\(matchPercent)٪", "\(matchPercent)%"))
                    .font(DS.Font.plex(10, weight: .bold))
                    .foregroundColor(DS.Color.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(match.member.displayFullName)
                    .font(DS.Font.plex(13, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1)

                HStack(spacing: DS.Spacing.xs) {
                    Text(L10n.t(
                        "\(match.matchCount) من \(totalParts) أسماء متطابقة",
                        "\(match.matchCount) of \(totalParts) names match"
                    ))
                    .font(DS.Font.plex(11))
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                    if match.isRegistrationMatch {
                        SysStatusChip(text: L10n.t("تسجيل", "Reg"), tint: DS.Color.primary)
                    }
                }

                // رقم الهاتف
                if let phone = match.member.phoneNumber, !phone.isEmpty {
                    metaItem("phone.fill", KuwaitPhone.display(phone))
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            Button {
                mergeTarget = (pendingMember: pendingMember, treeMember: match.member)
                showMergeConfirm = true
            } label: {
                Text(L10n.t("ربط", "Link"))
                    .font(DS.Font.plex(12.5, weight: .bold))
                    .foregroundColor(DSActionFill.label())
                    .padding(.horizontal, DS.Spacing.md)
                    .frame(height: 32)
                    .background(DSActionFill.style(), in: Capsule())
                    // مساحة ضغط ٤٤ نقطة والشكل كما هو
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .padding(.vertical, -6)
            }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityLabel(L10n.t("ربط بـ \(match.member.displayFullName)",
                                       "Link to \(match.member.displayFullName)"))
        }
        .padding(DS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(DS.Color.textTertiary.opacity(0.12), lineWidth: 1))
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

    /// المطابقات المدمجة: مطابقات التسجيل (من السيرفر) + المطابقات المحلية بالاسم
    private func combinedMatches(for member: FamilyMember) -> [(member: FamilyMember, matchCount: Int, matchedParts: [String], isRegistrationMatch: Bool)] {
        let localMatches = findNameMatches(for: member)
        let serverIds = registrationMatches[member.id] ?? []

        // جمع الأعضاء المتطابقين من السيرفر اللي مو موجودين بالمطابقة المحلية
        let localMatchIds = Set(localMatches.map(\.member.id))
        let serverOnlyMembers = serverIds
            .filter { !localMatchIds.contains($0) }
            .compactMap { id in memberVM.allMembers.first(where: { $0.id == id }) }

        var combined: [(member: FamilyMember, matchCount: Int, matchedParts: [String], isRegistrationMatch: Bool)] = []

        // مطابقات السيرفر أولاً (الأهم)
        for serverMember in serverOnlyMembers {
            combined.append((member: serverMember, matchCount: 0, matchedParts: [], isRegistrationMatch: true))
        }

        // ثم المطابقات المحلية اللي أيضاً من السيرفر
        for match in localMatches {
            let isAlsoServer = serverIds.contains(match.member.id)
            combined.append((member: match.member, matchCount: match.matchCount, matchedParts: match.matchedParts, isRegistrationMatch: isAlsoServer))
        }

        return combined
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

    private func findNameMatches(for member: FamilyMember) -> [(member: FamilyMember, matchCount: Int, matchedParts: [String])] {
        let newParts = member.fullName
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !newParts.isEmpty else { return [] }

        let existingMembers = memberVM.allMembers.filter { $0.role != .pending && $0.id != member.id }

        var matches: [(member: FamilyMember, matchCount: Int, matchedParts: [String])] = []

        for existing in existingMembers {
            let existingParts = existing.fullName
                .split(whereSeparator: \.isWhitespace)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            // تحقق: هل الاسم الأول للعضو الموجود يطابق/يشابه أي جزء من اسم المنضم؟
            guard let existingFirst = existingParts.first else { continue }
            let firstNameMatch = newParts.contains { Self.namesSimilar($0, existingFirst) }
            guard firstNameMatch else { continue }

            // عد كل الأجزاء المتطابقة
            var matchedParts: [String] = []
            var usedIndices: Set<Int> = []

            for newPart in newParts {
                for (idx, existingPart) in existingParts.enumerated() {
                    if !usedIndices.contains(idx) && Self.namesSimilar(newPart, existingPart) {
                        matchedParts.append(newPart)
                        usedIndices.insert(idx)
                        break
                    }
                }
            }

            if matchedParts.count >= 1 {
                matches.append((member: existing, matchCount: matchedParts.count, matchedParts: matchedParts))
            }
        }

        return matches.sorted { $0.matchCount > $1.matchCount }
    }

    /// لستة مرتبة: الأكثر تطابقاً أول — يبحث بالاسم الأول ثم الأول+الثاني ثم الأول+الثاني+الثالث...
    func orderedMatchList(for member: FamilyMember) -> [(member: FamilyMember, matchCount: Int, matchedParts: [String], isRegistrationMatch: Bool)] {
        let newParts = member.fullName
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !newParts.isEmpty else { return [] }

        // لازم تطابق أول 3 أسماء بالترتيب (أو كل الأسماء لو المنضم أقل من 3).
        // مثال: «علي طارق علي حسين» → يُعرض فقط من يطابق «علي طارق علي»،
        // ويُستبعد «علي طارق موسى» و«علي جعفر موسى».
        let requiredPrefix = min(3, newParts.count)

        // فقط الأعضاء: بدون هاتف + أحياء + مو pending
        let existingMembers = memberVM.allMembers.filter { m in
            m.role != .pending && m.id != member.id &&
            (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            m.isDeceased != true
        }
        let serverIds = Set(registrationMatches[member.id] ?? [])

        // لكل عضو موجود — كم اسم يطابق بالترتيب من البداية
        var results: [(member: FamilyMember, matchCount: Int, matchedParts: [String], isRegistrationMatch: Bool)] = []

        for existing in existingMembers {
            let existingParts = existing.fullName
                .split(whereSeparator: \.isWhitespace)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            // عد الأسماء المتطابقة بالترتيب من البداية
            var matchedParts: [String] = []
            let minCount = min(newParts.count, existingParts.count)
            for i in 0..<minCount {
                // تطابق أو تشابه (فرق حرف واحد) — يعرض الأسماء المشابهة لو فيه اختلاف بسيط بالإملاء
                if Self.namesSimilar(newParts[i], existingParts[i]) {
                    matchedParts.append(newParts[i])
                } else {
                    break
                }
            }

            // لازم تطابق أول 3 أسماء بالترتيب (أو كل الأسماء لو أقل من 3)
            if matchedParts.count >= requiredPrefix {
                results.append((
                    member: existing,
                    matchCount: matchedParts.count,
                    matchedParts: matchedParts,
                    isRegistrationMatch: serverIds.contains(existing.id)
                ))
            }
        }

        // رتب: الأكثر تطابقاً أول
        return results.sorted { $0.matchCount > $1.matchCount }.prefix(20).map { $0 }
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
        return VStack(alignment: .leading, spacing: 6) {
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
                    SysStatusChip(text: post.type, tint: tint)
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
        VStack(alignment: .leading, spacing: 6) {
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

        return VStack(alignment: .leading, spacing: 6) {
            requestRowHeader(icon: "phone.arrow.right",
                             tint: DS.Color.primary,
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
        return VStack(alignment: .leading, spacing: 6) {
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
        VStack(alignment: .leading, spacing: 6) {
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
        return VStack(alignment: .leading, spacing: 6) {
            requestRowHeader(icon: "bolt.heart.fill",
                             tint: DS.Color.error,
                             title: L10n.t("تسجيل وفاة", "Deceased"),
                             subtitle: L10n.t("لـ: \(request.member?.displayFullName ?? "عضو")",
                                              "For: \(request.member?.fullName ?? "Member")")) {
                pendingChip(Self.requestDate(request.createdAt))
            }

            rowExtras {
                if let requester {
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
        return VStack(alignment: .leading, spacing: 6) {
            requestRowHeader(icon: "person.badge.plus",
                             tint: DS.Color.info,
                             title: L10n.t("إضافة ابن", "Child Add"),
                             subtitle: L10n.t("الأب: \(request.member?.displayFullName ?? "عضو")",
                                              "Father: \(request.member?.fullName ?? "Member")")) {
                pendingChip(Self.requestDate(request.createdAt))
            }

            rowExtras {
                if let requester {
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
        return VStack(alignment: .leading, spacing: 6) {
            requestRowHeader(icon: "camera.badge.ellipsis",
                             tint: DS.Color.neonBlue,
                             title: L10n.t("اقتراح صورة", "Photo Suggestion"),
                             subtitle: L10n.t("لـ: \(request.member?.displayFullName ?? "عضو")",
                                              "For: \(request.member?.fullName ?? "Member")")) {
                pendingChip(Self.requestDate(request.createdAt))
            }

            rowExtras {
                if let requester {
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
                                .frame(width: 44, height: 44)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        } placeholder: {
                            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                .fill(DS.Color.surface)
                                .frame(width: 44, height: 44)
                                .overlay(ProgressView().tint(DS.Color.primary))
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

        return VStack(alignment: .leading, spacing: 6) {
            // الصف الأول: الأيقونة + نوع الطلب + الاسم الحالي + عمر الطلب
            requestRowHeader(icon: "rectangle.and.pencil.and.ellipsis",
                             tint: DS.Color.neonPurple,
                             title: isFamily ? L10n.t("تغيير العائلة", "Family Change") : L10n.t("تغيير اسم", "Name Change"),
                             subtitle: currentName) {
                pendingChip(Self.requestDate(request.createdAt))
            }

            rowExtras {
                if let requester {
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
                              tint: DS.Color.primary,
                              index: 0) {
                editBoxValueRow(icon: "person.fill",
                                label: L10n.t("الاسم الحالي", "Current Name"),
                                value: request.member?.displayFullName ?? "—",
                                tint: DS.Color.primary)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DS.Font.plex(12, weight: .heavy))
                    .foregroundColor(DS.Color.fieldLabel)
                Text(value)
                    .font(DS.Font.plex(14.5))
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
                              tint: DS.Color.primary,
                              index: 0) {
                editBoxValueRow(icon: "phone.fill",
                                label: L10n.t("الرقم الحالي", "Current number"),
                                value: KuwaitPhone.display(request.member?.phoneNumber),
                                tint: DS.Color.primary)
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
        VStack(alignment: .leading, spacing: 6) {
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
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
        } else {
            DSFieldIcon(name: "briefcase.fill", tint: DS.Color.neonPurple)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Shared Components

    private func accentBar(color: Color) -> some View {
        LinearGradient(
            colors: [color, color.opacity(0.7)],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 4)
        .cornerRadius(DS.Radius.full)
    }

    private func iconCircle(icon: String, color: Color, size: CGFloat = 44) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.2), color.opacity(0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            Image(systemName: icon)
                .foregroundColor(color)
                .font(DS.Font.scaled(size * 0.4, weight: .semibold))
        }
    }

    private func memberAvatar(urlStr: String?, name: String) -> some View {
        DSMemberAvatar(name: name, avatarUrl: urlStr, size: 40, roleColor: DS.Color.primary)
    }

    /// سطر معلومة بأيقونة صغيرة (الموعد، العنوان، القسم…) — Plex 12 بلون القيم
    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(DS.Color.textTertiary)
                .frame(width: 14)
                .accessibilityHidden(true)
            Text(text)
                .font(DS.Font.plex(12))
                .foregroundColor(DS.Color.fieldValue)
                .lineLimit(2)
        }
    }

    /// بلوك التفاصيل داخل الصف — عنوان صغير + النص (٣ أسطر) على بطاقة خفيفة
    private func contentBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.t("التفاصيل", "Details"))
                .font(DS.Font.plex(10.5, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)
            Text(text)
                .font(DS.Font.plex(12.5))
                .foregroundColor(DS.Color.fieldValue)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - قطع صف الطلب الموحّد (نفس `SysRow` في صفحات الإدارة)

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
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.Font.plex(13.5, weight: .bold))
                .foregroundColor(DS.Color.fieldLabel)
                .lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(DS.Font.plex(12))
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(2)
            }
        }
    }

    /// أسطر إضافية تحت الرأس — تبدأ تحت العنوان (بعد عمود الأيقونة ٣٢ + ٨)
    private func rowExtras<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            content()
        }
        .padding(.leading, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// معلومة صغيرة: أيقونة + نص (Plex 11) — التاريخ، الهاتف، مقدّم الطلب…
    private func metaItem(_ icon: String, _ text: String, color: Color = DS.Color.textTertiary) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(DS.Font.plex(11))
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
                .font(DS.Font.plex(12))
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
                    .font(DS.Font.plex(12))
                    .foregroundColor(DS.Color.fieldValue)
                    .strikethrough(true, color: DS.Color.error.opacity(0.5))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Image(systemName: "arrow.forward")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)
            Text(new)
                .font(DS.Font.plex(12.5, weight: .bold))
                .foregroundColor(DS.Color.primary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    /// زر واتساب صغير داخل الصف — كبسولة خضراء خفيفة ومساحة ضغط ٤٤ نقطة
    private func whatsAppButton(_ url: URL) -> some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "message.fill")
                    .font(.system(size: 10.5, weight: .bold))
                Text(L10n.t("واتساب", "WhatsApp"))
                    .font(DS.Font.plex(11.5, weight: .bold))
            }
            .foregroundColor(DS.Color.success)
            .padding(.horizontal, DS.Spacing.sm + 2)
            .frame(height: 28)
            .background(DS.Color.success.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(DS.Color.success.opacity(0.25), lineWidth: 1))
            // مساحة ضغط ٤٤ نقطة والشكل كما هو
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .padding(.vertical, -8)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    /// شارة «بانتظار» — بعمر الطلب إن عُرف تاريخه (اليوم، أمس، ٣ أيام…)
    private func pendingChip(_ date: Date?) -> some View {
        let text = date.map { ageText(days: daysWaiting(since: $0)) } ?? L10n.t("بانتظار", "Pending")
        return SysStatusChip(text: text, icon: "clock", tint: DS.Color.warning)
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

    /// مربّع تفاصيل الطلب بمنتصف الشاشة — نفس تصميم المربّعات الموحّد (طلب المالك):
    /// رأس كحلي بأيقونة نوع الطلب ووقته، الصورة (إن وُجدت)، قسم «بيانات الطلب» بصفوف،
    /// ثم قسم «الإجراءات» (تعديل الرقم، رفض، حذف نهائي). الشريط السفلي: الموافقة كحلي
    /// يمين و«إغلاق» يسار — عناصر صحة الشجرة للعرض فقط («إغلاق» وحده).
    private func requestDetailSheet(_ detail: RequestDetail) -> some View {
        let meta = detailMeta(for: detail)
        return DSComposer(
            title: meta.title,
            subtitle: meta.timestamp ?? L10n.t("تفاصيل الطلب", "Request Details"),
            icon: meta.icon,
            tint: DS.Color.actionNavy,
            actionTitle: approveLabelFor(detail),
            actionIcon: approveIconFor(detail),
            showsAction: detailHasDecision(detail),
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: !adminRequestVM.isLoading,
            onSubmit: { approveDetail(detail) },
            onCancel: { selectedDetail = nil }
        ) {
            detailBoxContent(detail, meta: meta)
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

    /// عناصر صحة الشجرة للعرض فقط — لا موافقة ولا رفض ولا حذف (كما كانت)
    private func detailHasDecision(_ detail: RequestDetail) -> Bool {
        if case .healthMember = detail { return false }
        return true
    }

    /// محتوى المربّع: الصورة (إن وُجدت) ← «بيانات الطلب» ← «الإجراءات»
    @ViewBuilder
    private func detailBoxContent(_ detail: RequestDetail, meta: DetailMeta) -> some View {
        if case .join(let member) = detail {
            joinDetailContent(member)
            detailActionsSection(for: detail)
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
        VStack(spacing: 6) {
            joinPersonAvatar(member, ring: results.isEmpty ? DS.Color.warning : DS.Color.success, size: 74)
                .padding(.bottom, 2)
            Text(member.fullName)
                .font(DS.Font.plex(17, weight: .bold))
                .foregroundColor(DS.Color.fieldLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                Image(systemName: fromWeb ? "globe" : "iphone")
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
                Text(fromWeb
                     ? (uname.isEmpty ? L10n.t("سجّل من الموقع", "Signed up on the website")
                                      : L10n.t("سجّل من الموقع · \u{2066}@\(uname)\u{2069}", "Website · @\(uname)"))
                     : L10n.t("سجّل من التطبيق برقم الجوال", "Signed up in the app by phone"))
            }
            .font(DS.Font.plex(12, weight: .semibold))
            .foregroundColor(fromWeb ? DS.Color.info.dsReadableGlyph : DS.Color.fieldValue)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xs)
        .dsStaggerIn(0)

        // ٢) بيانات المنضم — صفوف بعنوان وقيمة وفاصل رفيع
        DSComposerSection(title: L10n.t("بيانات المنضم", "Applicant"),
                          icon: "person.text.rectangle.fill",
                          tint: DS.Color.primary,
                          index: 1) {
            VStack(spacing: 0) {
                joinFactRow(icon: "phone.fill", tint: DS.Color.success,
                            label: L10n.t("الهاتف", "Phone"),
                            value: phone.isEmpty ? L10n.t("غير مسجّل", "Not set") : KuwaitPhone.display(phone)) {
                    if !phone.isEmpty {
                        HStack(spacing: 6) {
                            if let wa = KuwaitPhone.whatsappURL(phone) {
                                roundContactButton(icon: "message.fill", tint: DS.Color.success,
                                                   label: L10n.t("واتساب", "WhatsApp")) {
                                    UIApplication.shared.open(wa)
                                }
                            }
                            if let tel = KuwaitPhone.telURL(phone) {
                                roundContactButton(icon: "phone.fill", tint: DS.Color.primary,
                                                   label: L10n.t("اتصال", "Call")) {
                                    UIApplication.shared.open(tel)
                                }
                            }
                        }
                    }
                }
                Divider().padding(.leading, 44)
                joinFactRow(icon: "calendar", tint: DS.Color.neonPurple,
                            label: L10n.t("تاريخ الميلاد", "Birth date"),
                            value: birth.isEmpty ? L10n.t("غير مذكور", "Not given") : birth) { EmptyView() }
            }
            .padding(.horizontal, DS.Spacing.sm + 2)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.background))
        }

        // ٣) في الشجرة — المطابقات بزر «ربط»، أو اسم جديد
        DSComposerSection(title: L10n.t("في الشجرة", "In the tree"),
                          icon: results.isEmpty ? "sparkles" : "person.2.fill",
                          tint: results.isEmpty ? DS.Color.warning : DS.Color.success,
                          trailing: results.isEmpty ? nil : "\(results.count)",
                          index: 2) {
            if results.isEmpty {
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    DSFieldIcon(name: "person.badge.plus", tint: DS.Color.warning)
                    Text(L10n.t("لا يوجد اسم مطابق في الشجرة — عند «ربط بالشجرة» يُضاف عضواً جديداً.",
                                "No matching name in the tree — linking adds them as a new member."))
                        .font(DS.Font.plex(12.5, weight: .medium))
                        .foregroundColor(DS.Color.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .dsRowBox()
            } else {
                VStack(spacing: 6) {
                    ForEach(results, id: \.member.id) { match in
                        joinMatchRow(match: match, pendingMember: member)
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
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(DS.Font.plex(11, weight: .semibold))
                    .foregroundColor(DS.Color.textTertiary)
                Text(value)
                    .font(DS.Font.plex(14.5, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: DS.Spacing.xs)
            trailing()
        }
        .frame(minHeight: 54)
    }

    @ViewBuilder
    private func genericDetailBoxContent(_ detail: RequestDetail, meta: DetailMeta) -> some View {
        if let imageUrl = meta.imageUrl, let url = URL(string: imageUrl) {
            detailHeroImage(url: url, color: meta.color)
                .dsStaggerIn(0)
        }

        DSComposerSection(title: detailInfoTitle(detail),
                          icon: detailInfoIcon(detail),
                          tint: DS.Color.primary,
                          index: 1) {
            detailContent(for: detail)
        }

        detailActionsSection(for: detail)
    }

    private func detailInfoTitle(_ detail: RequestDetail) -> String {
        if case .healthMember = detail { return L10n.t("بيانات العضو", "Member Info") }
        return L10n.t("بيانات الطلب", "Request Info")
    }

    private func detailInfoIcon(_ detail: RequestDetail) -> String {
        if case .healthMember = detail { return "person.text.rectangle.fill" }
        return "doc.text.fill"
    }

    /// صورة الطلب (العضو، المشروع، الصورة المقترحة…) دائرية بمنتصف المربّع تحت الرأس
    private func detailHeroImage(url: URL, color: Color) -> some View {
        CachedAsyncImage(url: url) { img in
            img.resizable().scaledToFill()
        } placeholder: {
            Circle().fill(color.opacity(0.12))
                .overlay(ProgressView().tint(color))
        }
        .frame(width: 88, height: 88)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(color.opacity(0.25), lineWidth: 1.5))
        .shadow(color: color.opacity(0.22), radius: 10, x: 0, y: 5)
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xs)
        .accessibilityHidden(true)   // صورة زخرفية فوق البيانات — الصورة المقترحة لها صفّها
    }

    /// قسم «الإجراءات» — كل ما عدا الموافقة (التي في الشريط السفلي)، بنفس الصلاحيات السابقة:
    /// تعديل/إضافة رقم فعلي (طلب انضمام + canModerate)، رفض (canRejectRequests)،
    /// حذف نهائي (canDeleteMembers). عناصر صحة الشجرة بلا إجراءات.
    @ViewBuilder
    private func detailActionsSection(for detail: RequestDetail) -> some View {
        let phoneMember = detailPhoneEditMember(detail)
        let decision = detailHasDecision(detail)
        let showReject = decision && authVM.canRejectRequests
        let showDelete = decision && authVM.canDeleteMembers
        if phoneMember != nil || showReject || showDelete {
            DSComposerSection(title: L10n.t("الإجراءات", "Actions"),
                              icon: "hand.tap.fill",
                              tint: DS.Color.primary,
                              index: 2) {
                // تعديل / إضافة رقم فعلي قبل الربط
                if let member = phoneMember {
                    detailActionButton(
                        title: L10n.t("تعديل / إضافة رقم فعلي", "Edit / Add real number"),
                        icon: "phone.badge.plus",
                        color: DS.Color.primary
                    ) {
                        phoneEditPendingMember = member
                    }
                }

                if showReject || showDelete {
                    HStack(spacing: DS.Spacing.sm) {
                        if showReject {
                            detailActionButton(
                                title: L10n.t("رفض", "Reject"),
                                icon: "xmark",
                                color: DS.Color.warning
                            ) {
                                rejectReasonText = ""
                                rejectReasonDetail = detail
                                showRejectReason = true
                            }
                        }
                        // حذف نهائي — يمسح الطلب كلياً (للمالك/المدير فقط)
                        if showDelete {
                            detailActionButton(
                                title: L10n.t("حذف نهائي", "Delete Permanently"),
                                icon: "trash",
                                color: DS.Color.error
                            ) {
                                deleteConfirmDetail = detail
                            }
                            .disabled(adminRequestVM.isLoading)
                        }
                    }
                }
            }
        }
    }

    /// العضو المعلّق الذي يُعدَّل رقمه — لطلبات الانضمام فقط ولمن يملك canModerate
    private func detailPhoneEditMember(_ detail: RequestDetail) -> FamilyMember? {
        guard authVM.canModerate, case .join(let member) = detail else { return nil }
        return member
    }

    /// زر إجراء واضح داخل قسم «الإجراءات» — نص وأيقونة بلون الإجراء على خلفية خفيفة منه
    private func detailActionButton(title: String, icon: String, color: Color,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs + 2) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(DS.Font.plex(14, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(color.opacity(0.12)))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(color.opacity(0.25), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
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
            return .init(icon: "newspaper.fill", color: DS.Color.warning,
                         title: L10n.t("خبر بانتظار الاعتماد", "Pending News"),
                         timestamp: formatRegistrationDate(String(p.created_at)))
        case .report(let r):
            return .init(icon: "exclamationmark.triangle.fill", color: DS.Color.error,
                         title: L10n.t("بلاغ", "Report"),
                         timestamp: r.createdAt.map { formatRegistrationDate($0) })
        case .phone(let r):
            return .init(icon: "phone.arrow.right", color: DS.Color.primary,
                         title: L10n.t("تغيير رقم هاتف", "Phone Change"),
                         timestamp: r.createdAt.map { formatRegistrationDate($0) })
        case .nameChange(let r):
            return .init(icon: "rectangle.and.pencil.and.ellipsis", color: DS.Color.neonPurple,
                         title: r.requestType == RequestType.familyChange.rawValue
                            ? L10n.t("تغيير العائلة", "Family Change") : L10n.t("تغيير اسم", "Name Change"),
                         timestamp: r.createdAt.map { formatRegistrationDate($0) })
        case .diwaniya:
            return .init(icon: "tent.fill", color: DS.Color.gridDiwaniya,
                         title: L10n.t("طلب ديوانية", "Diwaniya Request"),
                         timestamp: nil)
        case .deceased(let r):
            return .init(icon: "bolt.heart.fill", color: DS.Color.error,
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
            return .init(icon: "briefcase.fill", color: DS.Color.neonPurple,
                         title: L10n.t("طلب مشروع", "Project Request"),
                         timestamp: p.createdAt.map { formatRegistrationDate($0) },
                         imageUrl: p.logoUrl)
        case .archive(let a):
            return .init(icon: a.categoryIcon, color: DS.Color.warning,
                         title: L10n.t("عنصر أرشيف", "Archive Item"),
                         timestamp: nil,
                         imageUrl: a.thumbnailUrl)
        case .treeEdit(let request, let action):
            return .init(icon: action.iconName, color: treeEditColor(action),
                         title: L10n.t(action.arabicLabel, action.englishLabel),
                         timestamp: request.createdAt.map { formatRegistrationDate($0) },
                         imageUrl: request.member?.avatarUrl)
        case .healthMember(let member, let issue):
            let name = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            return .init(icon: issue.asTab.icon, color: issue.asTab.color,
                         title: name.isEmpty ? L10n.t("بدون اسم", "(no name)") : name,
                         timestamp: nil,
                         imageUrl: member.avatarUrl)
        }
    }

    /// المحتوى المخصّص لكل نوع — صفوف داخل قسم «بيانات الطلب».
    @ViewBuilder
    private func detailContent(for detail: RequestDetail) -> some View {
        switch detail {
        case .join(let member):
            infoCard(icon: "person.fill", label: L10n.t("الاسم الكامل", "Full Name"),
                     value: member.fullName, color: DS.Color.primary)
            if let phone = member.phoneNumber, !phone.isEmpty {
                infoCard(icon: "phone.fill", label: L10n.t("رقم الهاتف", "Phone"),
                         value: KuwaitPhone.display(phone), color: DS.Color.success)
            }
            if let birth = member.birthDate?.trimmingCharacters(in: .whitespacesAndNewlines), !birth.isEmpty {
                infoCard(icon: "calendar", label: L10n.t("تاريخ الميلاد", "Birth Date"),
                         value: birth, color: DS.Color.neonPurple)
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
                     value: post.author_name, color: DS.Color.primary)
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
                     value: request.member?.fullName ?? "—", color: DS.Color.primary)
            longTextCard(icon: "exclamationmark.bubble.fill",
                         label: L10n.t("التفاصيل", "Details"),
                         text: request.details ?? L10n.t("لا توجد تفاصيل", "No details"))

        case .phone(let request):
            infoCard(icon: "person.fill", label: L10n.t("العضو", "Member"),
                     value: request.member?.fullName ?? "—", color: DS.Color.primary)
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
                     value: diwaniya.ownerName, color: DS.Color.primary)
            if let schedule = diwaniya.scheduleText, !schedule.isEmpty {
                infoCard(icon: "calendar", label: L10n.t("الموعد", "Schedule"),
                         value: schedule, color: DS.Color.info)
            }
            if let address = diwaniya.address, !address.isEmpty {
                infoCard(icon: "mappin.and.ellipse", label: L10n.t("العنوان", "Address"),
                         value: address, color: DS.Color.error)
            }

        case .deceased(let request):
            infoCard(icon: "person.fill", label: L10n.t("العضو", "Member"),
                     value: request.member?.fullName ?? "—", color: DS.Color.primary)
            longTextCard(icon: "doc.text.fill",
                         label: L10n.t("التفاصيل", "Details"),
                         text: request.details ?? L10n.t("لا توجد تفاصيل", "No details"))

        case .child(let request):
            infoCard(icon: "person.fill", label: L10n.t("الأب", "Father"),
                     value: request.member?.fullName ?? "—", color: DS.Color.primary)
            longTextCard(icon: "doc.text.fill",
                         label: L10n.t("التفاصيل", "Details"),
                         text: request.details ?? L10n.t("لا توجد تفاصيل", "No details"))

        case .photo(let request):
            infoCard(icon: "person.fill", label: L10n.t("العضو", "Member"),
                     value: request.member?.fullName ?? "—", color: DS.Color.primary)
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
                     value: project.title, color: DS.Color.neonPurple)
            infoCard(icon: "person.fill", label: L10n.t("صاحب المشروع", "Owner"),
                     value: project.ownerName, color: DS.Color.primary)
            if let desc = project.description, !desc.isEmpty {
                longTextCard(icon: "doc.text.fill",
                             label: L10n.t("الوصف", "Description"),
                             text: desc)
            }
            // روابط التواصل
            if let wa = project.whatsappNumber, !wa.isEmpty, let url = KuwaitPhone.whatsappURL(wa) {
                contactLinkCard(icon: "message.fill", label: L10n.t("واتساب", "WhatsApp"),
                                value: KuwaitPhone.display(wa), color: DS.Color.success, url: url)
            }
            if let phone = project.phoneNumber, !phone.isEmpty, let url = KuwaitPhone.telURL(phone) {
                contactLinkCard(icon: "phone.fill", label: L10n.t("هاتف", "Phone"),
                                value: KuwaitPhone.display(phone), color: DS.Color.primary, url: url)
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
                                value: sc, color: DS.Color.warning, url: url)
            }
            if let loc = project.locationUrl, !loc.isEmpty,
               let url = URL(string: loc.lowercased().hasPrefix("http") ? loc : "https://\(loc)") {
                contactLinkCard(icon: "mappin.and.ellipse", label: L10n.t("الموقع الجغرافي", "Location"),
                                value: L10n.t("فتح الخريطة", "Open map"), color: DS.Color.error, url: url)
            }

        case .archive(let item):
            infoCard(icon: "textformat", label: L10n.t("العنوان", "Title"),
                     value: item.title, color: DS.Color.warning)
            infoCard(icon: item.categoryIcon, label: L10n.t("القسم", "Category"),
                     value: item.categoryDisplayName,
                     color: DS.Color.info)
            if let year = item.year {
                infoCard(icon: "calendar", label: L10n.t("السنة", "Year"),
                         value: "\(year)", color: DS.Color.primary)
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
                infoCard(icon: "person.fill", label: L10n.t("العضو", "Member"),
                         value: memberName, color: DS.Color.primary)
                comparisonCard(
                    oldLabel: L10n.t("الرقم الحالي", "Current"),
                    oldValue: KuwaitPhone.display(request.member?.phoneNumber),
                    newLabel: L10n.t("الرقم الجديد", "New"),
                    newValue: KuwaitPhone.display(payload?.newPhone),
                    icon: "phone.fill"
                )
            case .deceased:
                infoCard(icon: "person.fill", label: L10n.t("العضو", "Member"),
                         value: memberName, color: DS.Color.primary)
                if let death = payload?.deathDate, !death.isEmpty {
                    infoCard(icon: "calendar", label: L10n.t("تاريخ الوفاة", "Death Date"),
                             value: death, color: DS.Color.error)
                }
            case .addDeathDate:
                infoCard(icon: "person.fill", label: L10n.t("العضو", "Member"),
                         value: memberName, color: DS.Color.primary)
                if let death = payload?.deathDate, !death.isEmpty {
                    infoCard(icon: "calendar.badge.exclamationmark", label: L10n.t("تاريخ الوفاة", "Death Date"),
                             value: death, color: DS.Color.error)
                }
            case .addPhoto:
                infoCard(icon: "person.fill", label: L10n.t("العضو", "Member"),
                         value: memberName, color: DS.Color.primary)
                if let photoStr = payload?.newPhotoUrl, let url = URL(string: photoStr) {
                    photoCard(url: url)
                }
            case .add:
                infoCard(icon: "person.fill", label: L10n.t("الاسم الجديد", "New Name"),
                         value: payload?.newMemberName ?? memberName, color: DS.Color.success)
                if let parent = payload?.parentMemberName, !parent.isEmpty {
                    infoCard(icon: "person.2.fill", label: L10n.t("الأب", "Father"),
                             value: parent, color: DS.Color.primary)
                }
            case .delete:
                infoCard(icon: "person.fill", label: L10n.t("العضو", "Member"),
                         value: memberName, color: DS.Color.error)
            case .editBirth:
                infoCard(icon: "person.fill", label: L10n.t("العضو", "Member"),
                         value: memberName, color: DS.Color.primary)
                if let newDate = (payload?.newBirthDate ?? payload?.newName), !newDate.isEmpty {
                    infoCard(icon: "birthday.cake", label: L10n.t("تاريخ الميلاد الجديد", "New Birth Date"),
                             value: newDate, color: DS.Color.warning)
                }
            case .other:
                infoCard(icon: "person.fill", label: L10n.t("العضو", "Member"),
                         value: memberName, color: DS.Color.accent)
            }
            if let requester = memberVM.allMembers.first(where: { $0.id == request.requesterId }) {
                infoCard(icon: "person.crop.circle.badge.checkmark",
                         label: L10n.t("مقدّم التعديل", "Requested by"),
                         value: requester.fullName, color: DS.Color.info)
            }
            if let reason = payload?.reason, !reason.isEmpty {
                longTextCard(icon: "text.bubble.fill",
                             label: L10n.t("السبب", "Reason"), text: reason)
            }
            if let notes = payload?.notes, !notes.isEmpty {
                longTextCard(icon: "note.text",
                             label: L10n.t("ملاحظات", "Notes"), text: notes)
            }

        case .healthMember(let member, let issue):
            // نوع المشكلة
            infoCard(icon: issue.asTab.icon,
                     label: L10n.t("نوع المشكلة", "Issue Type"),
                     value: issue.asTab.title,
                     color: issue.asTab.color)
            // اسم العضو
            let displayName = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            infoCard(icon: "person.fill",
                     label: L10n.t("الاسم", "Name"),
                     value: displayName.isEmpty ? L10n.t("بدون اسم", "(no name)") : displayName,
                     color: DS.Color.primary)
            // رقم الهاتف + واتساب
            if let phone = member.phoneNumber, !phone.isEmpty {
                infoCard(icon: "phone.fill",
                         label: L10n.t("رقم الهاتف", "Phone"),
                         value: KuwaitPhone.display(phone),
                         color: DS.Color.success)
                if let wa = KuwaitPhone.whatsappURL(phone) {
                    contactLinkCard(icon: "message.fill",
                                    label: L10n.t("تواصل واتساب", "WhatsApp"),
                                    value: KuwaitPhone.display(phone),
                                    color: DS.Color.success, url: wa)
                }
            } else {
                infoCard(icon: "phone.slash", label: L10n.t("رقم الهاتف", "Phone"),
                         value: L10n.t("لا يوجد", "None"), color: DS.Color.textTertiary)
            }
        }
    }

    /// صف معلومة — أيقونة الحقل + العنوان الغامق + القيمة (نفس صفوف المربّعات الموحّدة).
    private func infoCard(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DS.Font.plex(12, weight: .heavy))
                    .foregroundColor(DS.Color.fieldLabel)
                Text(value)
                    .font(DS.Font.plex(14.5))
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(DS.Font.plex(12, weight: .heavy))
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(value)
                        .font(DS.Font.plex(14.5))
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color.opacity(0.7))
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
                DSFieldIcon(name: icon, tint: DS.Color.primary)
                    .accessibilityHidden(true)
                Text(label)
                    .font(DS.Font.plex(12, weight: .heavy))
                    .foregroundColor(DS.Color.fieldLabel)
                Spacer(minLength: 0)
            }
            Text(text)
                .font(DS.Font.plex(14.5))
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(oldLabel)
                        .font(DS.Font.plex(12, weight: .heavy))
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(oldValue)
                        .font(DS.Font.plex(14.5))
                        .foregroundColor(DS.Color.fieldValue)
                        .strikethrough(true, color: DS.Color.error.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // سهم تحت عمود الأيقونات: من القديم إلى الجديد
            Image(systemName: "arrow.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)
                .frame(width: 32)
                .accessibilityHidden(true)

            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: icon, tint: DS.Color.success)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(newLabel)
                        .font(DS.Font.plex(12, weight: .heavy))
                        .foregroundColor(DS.Color.success)
                    Text(newValue)
                        .font(DS.Font.plex(14.5, weight: .bold))
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

    /// صورة كبيرة (للصور المقترحة) بنفس إطار صفوف المربّعات.
    private func photoCard(url: URL) -> some View {
        CachedAsyncImage(url: url) { img in
            img.resizable().scaledToFit()
        } placeholder: {
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background)
                .frame(height: 200)
                .overlay(ProgressView().tint(DS.Color.primary))
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
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
        case .join:    return L10n.t("ربط بالشجرة", "Link to Tree")
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
            case .healthMember:
                await MainActor.run { selectedDetail = nil }
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
            case .healthMember:
                break // لا إجراء رفض لعناصر الصحة
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
            case .healthMember:
                break // عناصر الصحة ليست طلبات — لا حذف
            }
            await MainActor.run { selectedDetail = nil }
        }
    }

    // legacy helpers — لم تعد ضرورية لكن نتركها للتوافق مع أي استدعاءات أخرى
    private func detailHeader(icon: String, color: Color, title: String, iconSize: CGFloat = 40) -> some View {
        HStack(spacing: DS.Spacing.md) {
            iconCircle(icon: icon, color: color, size: iconSize)
            Text(title)
                .font(DS.Font.title3)
                .fontWeight(.bold)
                .foregroundColor(DS.Color.textPrimary)
            Spacer()
        }
        .padding(.bottom, DS.Spacing.sm)
    }

    /// مجال الطلب المعروض في التفاصيل — لإخفاء الأزرار عمّن لا يملك اعتماده
    private func detailIsContent(_ detail: RequestDetail) -> Bool {
        switch detail {
        case .news, .project, .archive, .diwaniya, .photo, .report: return true
        default: return false
        }
    }

    private func canApproveDetail(_ detail: RequestDetail) -> Bool {
        if case .report = detail { return authVM.canModerateContent }
        return detailIsContent(detail) ? authVM.canApproveContent : authVM.canApproveTreeRequests
    }

    @ViewBuilder
    private func detailActions(for detail: RequestDetail) -> some View {
        if canApproveDetail(detail) {
        DSApproveRejectButtons(
            approveTitle: {
                switch detail {
                case .join: return L10n.t("ربط بالشجرة", "Link to Tree")
                default: return L10n.t("موافقة", "Approve")
                }
            }(),
            rejectTitle: L10n.t("رفض", "Reject"),
            isLoading: adminRequestVM.isLoading,
            showReject: canApproveDetail(detail) && (detailIsContent(detail) || authVM.canRejectRequests),
            useCapsule: true
        ) {
            // موافقة
            Task {
                switch detail {
                case .join(let member):
                    await MainActor.run {
                        memberToLink = member
                        selectedDetail = nil
                    }
                case .news(let post):
                    await newsVM.approveNewsPost(postId: post.id)
                    selectedDetail = nil
                case .report(let request):
                    await adminRequestVM.approveNewsReport(request: request)
                    selectedDetail = nil
                case .phone(let request):
                    await adminRequestVM.approvePhoneChangeRequest(request: request)
                    selectedDetail = nil
                case .nameChange(let request):
                    await adminRequestVM.approveNameChangeRequest(request: request)
                    selectedDetail = nil
                case .diwaniya(let diwaniya):
                    if let adminId = authVM.currentUser?.id {
                        await diwaniyaVM.approveDiwaniya(id: diwaniya.id, adminId: adminId)
                    }
                    selectedDetail = nil
                case .deceased(let request):
                    await adminRequestVM.approveDeceasedRequest(request: request)
                    selectedDetail = nil
                case .child(let request):
                    await adminRequestVM.acknowledgeChildAddRequest(request: request)
                    selectedDetail = nil
                case .photo(let request):
                    await adminRequestVM.approvePhotoSuggestion(request: request)
                    selectedDetail = nil
                case .project(let project):
                    if let adminId = authVM.currentUser?.id {
                        await projectsVM.approveProject(id: project.id, approvedBy: adminId)
                    }
                    selectedDetail = nil
                case .archive(let item):
                    await archiveVM.approveItem(item)
                    selectedDetail = nil
                case .treeEdit(let request, _):
                    await adminRequestVM.approveTreeEditRequest(request: request)
                    selectedDetail = nil
                case .healthMember:
                    selectedDetail = nil
                }
            }
        } onReject: {
            // رفض
            Task {
                switch detail {
                case .join(let member):
                    await adminRequestVM.rejectOrDeleteMember(memberId: member.id)
                    selectedDetail = nil
                case .news(let post):
                    await newsVM.rejectNewsPost(postId: post.id)
                    selectedDetail = nil
                case .report(let request):
                    await adminRequestVM.rejectNewsReport(request: request)
                    selectedDetail = nil
                case .phone(let request):
                    await adminRequestVM.rejectPhoneChangeRequest(request: request)
                    selectedDetail = nil
                case .nameChange(let request):
                    await adminRequestVM.rejectNameChangeRequest(request: request)
                    selectedDetail = nil
                case .diwaniya(let diwaniya):
                    await diwaniyaVM.rejectDiwaniya(id: diwaniya.id)
                    selectedDetail = nil
                case .deceased(let request):
                    await adminRequestVM.rejectDeceasedRequest(request: request)
                    selectedDetail = nil
                case .child(let request):
                    await adminRequestVM.rejectChildAddRequest(request: request)
                    selectedDetail = nil
                case .photo(let request):
                    await adminRequestVM.rejectPhotoSuggestion(request: request)
                    selectedDetail = nil
                case .project(let project):
                    await projectsVM.rejectProject(id: project.id)
                    selectedDetail = nil
                case .archive(let item):
                    await archiveVM.rejectItem(item)
                    selectedDetail = nil
                case .treeEdit(let request, _):
                    await adminRequestVM.rejectTreeEditRequest(request: request, reason: nil)
                    selectedDetail = nil
                case .healthMember:
                    selectedDetail = nil
                }
            }
        }
        .padding(.top, DS.Spacing.md)
        }
    }

    private func detailField(_ label: String, _ value: String, color: Color = DS.Color.textPrimary) -> some View {
        DSCard(padding: DS.Spacing.md) {
            HStack {
                Text(label)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                Spacer()
                Text(value)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(color)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func detailFullText(_ label: String, _ text: String) -> some View {
        DSCard(padding: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text(label)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                Text(text)
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

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
                    .font(DS.Font.plex(12, weight: .heavy))
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
            .frame(height: 90)
            .overlay(
                CachedAsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(DS.Color.surface)
                        .overlay(ProgressView().tint(DS.Color.primary))
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
        default: return DS.Color.primary
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
