import SwiftUI

struct AdminAllRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @EnvironmentObject var storyVM: StoryViewModel
    @StateObject private var diwaniyaVM = DiwaniyasViewModel()
    @State private var nameEditRequest: AdminRequest? = nil
    @State private var editedName: String = ""
    @State private var phoneEditRequest: PhoneChangeRequest? = nil
    @State private var editedPhone: String = ""
    @State private var selectedDetail: RequestDetail? = nil

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
        case joinRequests, nameChange, phone, deceased, gallery
        // الشجرة — كل أنواع طلبات تعديل الشجرة + إضافة الأبناء التقليدية
        case children, treeAdd, treeEditName, treeEditPhone, treeDeceased, treeDelete
        // محتوى ونشاط
        case news, reports, photos, diwaniya, projects
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
            case .deceased: return L10n.t("وفاة", "Deceased")
            case .children: return L10n.t("أبناء", "Children")
            case .treeAdd: return L10n.t("إضافة (شجرة)", "Tree · Add")
            case .treeEditName: return L10n.t("تعديل اسم (شجرة)", "Tree · Name")
            case .treeEditPhone: return L10n.t("تعديل رقم (شجرة)", "Tree · Phone")
            case .treeDeceased: return L10n.t("وفاة (شجرة)", "Tree · Deceased")
            case .treeDelete: return L10n.t("حذف", "Delete")
            case .photos: return L10n.t("صور مقترحة", "Suggested Photos")
            case .projects: return L10n.t("مشاريع", "Projects")
            case .gallery: return L10n.t("معرض", "Gallery")
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
            case .deceased: return "bolt.heart.fill"
            case .children: return "person.badge.plus"
            case .treeAdd: return "person.crop.circle.badge.plus"
            case .treeEditName: return "pencil.line"
            case .treeEditPhone: return "phone.arrow.up.right"
            case .treeDeceased: return "heart.slash"
            case .treeDelete: return "person.badge.minus"
            case .photos: return "camera.badge.ellipsis"
            case .projects: return "briefcase.fill"
            case .gallery: return "photo.on.rectangle.angled"
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
            case .deceased: return DS.Color.error
            case .children: return DS.Color.info
            case .treeAdd: return DS.Color.success
            case .treeEditName: return DS.Color.neonPurple
            case .treeEditPhone: return DS.Color.primary
            case .treeDeceased: return DS.Color.error
            case .treeDelete: return DS.Color.error
            case .photos: return DS.Color.neonBlue
            case .projects: return DS.Color.neonPurple
            case .gallery: return DS.Color.gridDiwaniya
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
            case .joinRequests, .nameChange, .phone, .deceased, .gallery: return .members
            case .children, .treeAdd, .treeEditName, .treeEditPhone, .treeDeceased, .treeDelete: return .tree
            case .news, .reports, .photos, .diwaniya, .projects: return .content
            case .healthOrphan, .healthNoName, .healthBrokenParent, .healthHidden, .healthDupPhone: return .treeHealth
            }
        }
    }

    @State private var selectedTab: RequestTab = .all
    @State private var selectedSection: RequestSection? = nil   // nil = وضع الكل
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
            if member.isHiddenFromTree {
                memberIssues.insert(.hiddenFromTree)
            }
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
        for issue in [TreeHealthIssue.orphan, .noName, .brokenParent, .hiddenFromTree, .duplicatePhone] {
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
                // شريط التابات الأفقي (يظهر فقط إذا في طلبات)
                if totalCount > 0 {
                    tabBar
                        .padding(.top, DS.Spacing.sm)
                }

                // المحتوى
                if totalCount == 0 || itemCount(for: selectedTab) == 0 {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    tabContent
                }
            }

            // شريط العمليات الجماعية — مثبّت في الأسفل
            if isSelectMode && !selectedIds.isEmpty {
                VStack(spacing: 0) {
                    Spacer()
                    Divider()
                    HStack(spacing: DS.Spacing.md) {
                        // عداد المحددين
                        VStack(spacing: 2) {
                            Text("\(selectedIds.count)")
                                .font(DS.Font.scaled(18, weight: .black))
                                .foregroundColor(DS.Color.textPrimary)
                            Text(L10n.t("محدد", "selected"))
                                .font(DS.Font.scaled(10, weight: .medium))
                                .foregroundColor(DS.Color.textTertiary)
                        }
                        .frame(minWidth: 44)

                        Spacer()

                        // زر الرفض — يظهر فقط لمن يملك الصلاحية
                        if authVM.canRejectRequests {
                            Button {
                                showBulkRejectConfirm = true
                            } label: {
                                HStack(spacing: DS.Spacing.xs) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(DS.Font.scaled(14, weight: .semibold))
                                    Text(L10n.t("رفض", "Reject"))
                                        .font(DS.Font.calloutBold)
                                }
                                .foregroundColor(DS.Color.error)
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.sm)
                                .background(DS.Color.error.opacity(0.1))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(DS.Color.error.opacity(0.3), lineWidth: 1))
                            }
                            .disabled(adminRequestVM.isLoading)
                            .buttonStyle(DSScaleButtonStyle())
                        }

                        // زر القبول
                        Button {
                            showBulkApproveConfirm = true
                        } label: {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(DS.Font.scaled(14, weight: .semibold))
                                Text(L10n.t("قبول", "Approve"))
                                    .font(DS.Font.calloutBold)
                            }
                            .foregroundColor(DS.Color.textOnPrimary)
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.vertical, DS.Spacing.sm)
                            .background(DS.Color.gradientPrimary)
                            .clipShape(Capsule())
                        }
                        .disabled(adminRequestVM.isLoading)
                        .buttonStyle(DSScaleButtonStyle())
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(.ultraThinMaterial)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(DS.Anim.snappy, value: isSelectMode && !selectedIds.isEmpty)
        .navigationTitle(L10n.t("طلبات المراجعة", "Review Requests"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // عدّاد إجمالي
            ToolbarItem(placement: .topBarLeading) {
                if totalCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "tray.full.fill")
                            .font(DS.Font.scaled(11, weight: .bold))
                        Text("\(totalCount)")
                            .font(DS.Font.scaled(12, weight: .black))
                    }
                    .foregroundColor(DS.Color.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(DS.Color.primary.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(DS.Color.primary.opacity(0.25), lineWidth: 1))
                }
            }
            // زر التحديد المتعدّد — بارز في الأعلى يمين (لا يظهر إلا لو في طلبات قابلة)
            ToolbarItem(placement: .topBarTrailing) {
                if !isSelectMode && itemCount(for: selectedTab) > 0
                    && selectedTab.section != .treeHealth {
                    Button {
                        withAnimation(DS.Anim.snappy) {
                            isSelectMode = true
                            selectedIds.removeAll()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(DS.Font.scaled(12, weight: .bold))
                            Text(L10n.t("تحديد", "Select"))
                                .font(DS.Font.scaled(13, weight: .bold))
                        }
                        .foregroundColor(DS.Color.success)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(DS.Color.success.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(DS.Color.success.opacity(0.30), lineWidth: 1))
                    }
                }
            }
        }
        .onChange(of: selectedTab) { _ in
            withAnimation(DS.Anim.snappy) {
                isSelectMode = false
                selectedIds.removeAll()
            }
        }
        .onChange(of: memberVM.allMembers.count) { _ in
            rebuildTreeHealthCache()
        }
        .sheet(item: $openTreeHealthFilter) { filter in
            NavigationStack {
                AdminTreeHealthView(initialFilter: filter)
                    .environmentObject(memberVM)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
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
            // تحميل متوازي لجميع الطلبات — أسرع بكثير
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in await memberVM.fetchAllMembers() }
                group.addTask { @MainActor in await newsVM.fetchPendingNewsRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchNewsReportRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchPhoneChangeRequests() }
                group.addTask { @MainActor in await diwaniyaVM.fetchPendingDiwaniyas() }
                group.addTask { @MainActor in await adminRequestVM.fetchDeceasedRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchChildAddRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchPhotoSuggestionRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchNameChangeRequests() }
                group.addTask { @MainActor in await projectsVM.fetchPendingProjects() }
                group.addTask { @MainActor in await memberVM.fetchPendingGalleryPhotos() }
                group.addTask { @MainActor in await adminRequestVM.fetchTreeEditRequests(force: true) }
            }
            await fetchAllRegistrationMatches()
            recalculateCounts()

            // اختيار أول تاب فيه طلبات
            if let firstWithItems = cachedAvailableTabs.first {
                selectedTab = firstWithItems
            }
        }
        .alert(
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
        .alert(
            L10n.t("تم", "Done"),
            isPresented: $showBulkApproveResult
        ) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(bulkApproveResult ?? "")
        }
        .alert(
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
        .alert(
            L10n.t("تم", "Done"),
            isPresented: $showBulkSelectApproveResult
        ) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(bulkSelectApproveResult ?? "")
        }
        .alert(
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
        .alert(
            L10n.t("تم", "Done"),
            isPresented: $showBulkSelectRejectResult
        ) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(bulkSelectRejectResult ?? "")
        }
        .sheet(item: $selectedDetail) { detail in
            requestDetailSheet(detail)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $memberToLink) { member in
            LinkToExistingMemberSheet(pendingMember: member)
                .environmentObject(memberVM)
                .environmentObject(adminRequestVM)
        }
        .alert(
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
        .alert(
            {
                if case .failure = adminRequestVM.mergeResult {
                    return L10n.t("خطأ في الدمج", "Merge Error")
                }
                return L10n.t("تم الدمج", "Merge Complete")
            }(),
            isPresented: $showMergeSuccess
        ) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {
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
        case .treeDeceased: return treeEditCount(action: .deceased)
        case .treeDelete: return treeEditCount(action: .delete)
        case .photos: return adminRequestVM.photoSuggestionRequests.count
        case .projects: return projectsVM.pendingProjects.count
        case .gallery: return memberVM.pendingGalleryPhotos.count
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

    private func recalculateCounts() {
        cachedPendingMembers = memberVM.allMembers.filter { $0.role == .pending }
        // إعادة بناء كاش صحة الشجرة كذلك
        rebuildTreeHealthCache()
        // المجموع الكلّي = كل الأنواع ما عدا .all نفسه (لتفادي العدّ المضاعف)
        // نستثني كذلك tabs الصحة من المجموع الكلّي للطلبات (الصحة ليست "طلبات" بالمعنى الإداري)
        cachedTotalCount = RequestTab.allCases
            .filter { $0 != .all && $0.section != .treeHealth }
            .reduce(0) { $0 + itemCount(for: $1) }
        // عرض كل التابات دائماً — حتى الفارغة (المستخدم يبيها كلها مرئية)
        cachedAvailableTabs = RequestTab.allCases
    }

    /// شريط الفلاتر بنمط أرشيف العائلة — في وضع التحديد يتحوّل لشريط ملخّص التحديد.
    /// خارج وضع التحديد: صف "الكل" + الأقسام أعلى + صف فلاتر القسم الحالي تحت.
    private var tabBar: some View {
        Group {
            if isSelectMode {
                selectionSummaryBar
                    .padding(.horizontal, DS.Spacing.lg)
                    .transition(.opacity)
            } else {
                VStack(spacing: DS.Spacing.xs) {
                    sectionSelector
                    if let section = selectedSection {
                        subFilterCapsule(for: section)
                            .transition(.opacity)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        .animation(.spring(response: 0.40, dampingFraction: 0.78), value: selectedTab)
        .animation(.spring(response: 0.40, dampingFraction: 0.78), value: selectedSection)
        .animation(.spring(response: 0.35, dampingFraction: 0.80), value: isSelectMode)
        .onChange(of: totalCount) { _ in
            // إذا التاب الحالي صار فارغ، انقل لأول تاب غير فارغ (لو فيه)
            if itemCount(for: selectedTab) == 0,
               let firstNonEmpty = RequestTab.allCases.first(where: { itemCount(for: $0) > 0 }) {
                withAnimation(DS.Anim.snappy) {
                    selectedTab = firstNonEmpty
                    selectedSection = firstNonEmpty.section
                }
            }
        }
    }

    /// صف الأقسام الأعلى: "الكل" + 3 أقسام (أعضاء/شجرة/محتوى).
    private var sectionSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // "الكل" — اختصار للتاب .all
                sectionChip(
                    title: L10n.t("الكل", "All"),
                    icon: "tray.full.fill",
                    color: DS.Color.primary,
                    count: cachedTotalCount,
                    isActive: selectedTab == .all
                ) {
                    selectedTab = .all
                    selectedSection = nil
                }
                Capsule()
                    .fill(DS.Color.textTertiary.opacity(0.25))
                    .frame(width: 1, height: 22)
                    .padding(.horizontal, 2)

                ForEach(RequestSection.allCases) { section in
                    sectionChip(
                        title: section.title,
                        icon: section.icon,
                        color: section.color,
                        count: sectionCount(section),
                        isActive: selectedSection == section
                    ) {
                        selectedSection = section
                        // اختر أول tab في القسم
                        if let firstTab = RequestTab.allCases.first(where: { $0.section == section }) {
                            selectedTab = firstTab
                        }
                    }
                }
            }
            .padding(6)
            .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
            .overlay(Capsule(style: .continuous).strokeBorder(DS.Color.primary.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    /// chip القسم — أيقونة + نص دائماً (نشط ممتدّ بـ gradient، غير نشط شفّاف).
    private func sectionChip(title: String, icon: String, color: Color, count: Int, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(12, weight: .bold))
                Text(title)
                    .font(DS.Font.scaled(13, weight: isActive ? .bold : .semibold))
                    .lineLimit(1)
                if count > 0 {
                    Text("\(count)")
                        .font(DS.Font.scaled(10, weight: .black))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(
                            Capsule().fill(isActive ? Color.white.opacity(0.25) : color.opacity(0.18))
                        )
                }
            }
            .foregroundColor(isActive ? .white : color)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    isActive
                        ? AnyShapeStyle(LinearGradient(colors: [color, color.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(color.opacity(0.10))
                )
            )
            .overlay(
                Capsule().strokeBorder(isActive ? Color.clear : color.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: isActive ? color.opacity(0.30) : Color.clear, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(DSScaleButtonStyle())
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    /// مجموع طلبات القسم.
    private func sectionCount(_ section: RequestSection) -> Int {
        RequestTab.allCases
            .filter { $0.section == section }
            .reduce(0) { $0 + itemCount(for: $1) }
    }

    /// صف الفلاتر الفرعية داخل القسم — كبسولة أرشيف العائلة.
    private func subFilterCapsule(for section: RequestSection) -> some View {
        let sectionTabs = RequestTab.allCases.filter { $0.section == section }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sectionTabs) { tab in
                    if selectedTab == tab {
                        activeTabPill(tab)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    } else {
                        inactiveTabIcon(tab)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }

            }
            .padding(6)
            .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
            .overlay(Capsule(style: .continuous).strokeBorder(section.color.opacity(0.18), lineWidth: 1))
            .shadow(color: section.color.opacity(0.10), radius: 6, x: 0, y: 2)
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    /// كبسولة الفلاتر — تابات + زر التحديد مدمج آخر الصف.
    private var filterCapsule: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(availableTabs) { tab in
                    if selectedTab == tab {
                        activeTabPill(tab)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    } else {
                        inactiveTabIcon(tab)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }

                // زر التحديد المدمج — يظهر فقط لو في الـ tab الحالي طلبات
                if itemCount(for: selectedTab) > 0 {
                    Capsule()
                        .fill(DS.Color.textTertiary.opacity(0.25))
                        .frame(width: 1, height: 22)
                        .padding(.horizontal, 2)

                    Button {
                        withAnimation(DS.Anim.snappy) {
                            isSelectMode = true
                            selectedIds.removeAll()
                        }
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(DS.Font.scaled(13, weight: .bold))
                            .foregroundColor(DS.Color.success)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(DS.Color.success.opacity(0.12)))
                            .overlay(Circle().strokeBorder(DS.Color.success.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(DSScaleButtonStyle())
                    .accessibilityLabel(L10n.t("تحديد متعدّد", "Multi-select"))
                }
            }
            .padding(6)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(DS.Color.primary.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    /// شريط ملخّص التحديد — يحلّ محل الفلاتر في وضع التحديد.
    private var selectionSummaryBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button {
                withAnimation(DS.Anim.snappy) {
                    isSelectMode = false
                    selectedIds.removeAll()
                }
            } label: {
                Text(L10n.t("إلغاء", "Cancel"))
                    .font(DS.Font.scaled(13, weight: .semibold))
                    .foregroundColor(DS.Color.error)
            }
            Spacer()
            Text(L10n.t("اختيار \(selectedIds.count)", "Selected \(selectedIds.count)"))
                .font(DS.Font.scaled(13, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
            Spacer()
            // تحديد الكل في التاب الحالي
            let currentIds = currentTabIds
            let allSelected = !currentIds.isEmpty && currentIds.allSatisfy { selectedIds.contains($0) }
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
                    .font(DS.Font.scaled(13, weight: .semibold))
                    .foregroundColor(DS.Color.primary)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(
            Capsule(style: .continuous).fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule(style: .continuous).strokeBorder(DS.Color.primary.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
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
                + memberVM.pendingGalleryPhotos.map { $0.id }
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
        case .treeDeceased: return treeEdits(action: .deceased).map { $0.id }
        case .treeDelete:   return treeEdits(action: .delete).map { $0.id }
        case .photos:       return adminRequestVM.photoSuggestionRequests.map { $0.id }
        case .projects:     return projectsVM.pendingProjects.map { $0.id }
        case .gallery:      return memberVM.pendingGalleryPhotos.map { $0.id }
        // الصحة لا تدعم التحديد المتعدّد (الإجراءات تفصيلية)
        case .healthOrphan, .healthNoName, .healthBrokenParent, .healthHidden, .healthDupPhone:
            return []
        }
    }

    /// التاب النشط — pill ممتدّ بـ gradient + نص + عدّاد.
    private func activeTabPill(_ tab: RequestTab) -> some View {
        tabChipBody(tab: tab, isActive: true) {}
    }

    /// التاب غير النشط — كبسولة شفّافة بنص (مش أيقونة فقط).
    private func inactiveTabIcon(_ tab: RequestTab) -> some View {
        tabChipBody(tab: tab, isActive: false) {
            selectedTab = tab
        }
    }

    /// chip فلتر فرعي موحّد — نص + أيقونة + عدّاد دائماً.
    private func tabChipBody(tab: RequestTab, isActive: Bool, action: @escaping () -> Void) -> some View {
        let count = itemCount(for: tab)
        return Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(DS.Font.scaled(11, weight: .bold))
                Text(tab.title)
                    .font(DS.Font.scaled(12, weight: isActive ? .bold : .semibold))
                    .lineLimit(1)
                if count > 0 {
                    Text("\(count)")
                        .font(DS.Font.scaled(10, weight: .black))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(
                            Capsule().fill(isActive ? Color.white.opacity(0.25) : tab.color.opacity(0.18))
                        )
                }
            }
            .foregroundColor(isActive ? .white : tab.color)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(
                    isActive
                        ? AnyShapeStyle(LinearGradient(colors: [tab.color, tab.color.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(tab.color.opacity(0.10))
                )
            )
            .overlay(
                Capsule().strokeBorder(isActive ? Color.clear : tab.color.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: isActive ? tab.color.opacity(0.30) : Color.clear, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(tab.title)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        List {
            // زر الموافقة على الكل — أبناء فقط
            if selectedTab == .children && adminRequestVM.childAddRequests.count > 1 {
                Button {
                    showBulkApproveChildrenConfirm = true
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(DS.Font.scaled(14, weight: .semibold))
                        Text(L10n.t(
                            "الموافقة على الكل (\(adminRequestVM.childAddRequests.count))",
                            "Approve All (\(adminRequestVM.childAddRequests.count))"
                        ))
                        .font(DS.Font.calloutBold)
                    }
                    .foregroundColor(DS.Color.textOnPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(
                        LinearGradient(
                            colors: [DS.Color.success, DS.Color.success.opacity(0.8)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }
                .listRowInsets(EdgeInsets(top: DS.Spacing.xs, leading: DS.Spacing.lg, bottom: DS.Spacing.xs, trailing: DS.Spacing.lg))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .disabled(adminRequestVM.isLoading)
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
                        onReject: { Task { await adminRequestVM.rejectOrDeleteMember(memberId: member.id) } },
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
                        onReject: { Task { await newsVM.rejectNewsPost(postId: post.id) } },
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
                        onReject: { Task { await adminRequestVM.rejectNewsReport(request: request) } },
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
                        onReject: { Task { await adminRequestVM.rejectPhoneChangeRequest(request: request) } },
                        onTap: { selectedDetail = .phone(request) }
                    ) {
                        phoneRow(for: request)
                    }
                }
                .sheet(item: $phoneEditRequest) { request in
                    adminPhoneEditSheet(request: request)
                }
            case .nameChange:
                ForEach(adminRequestVM.nameChangeRequests) { request in
                    selectableRow(
                        id: request.id,
                        accentColor: RequestTab.nameChange.color,
                        onApprove: { Task { await adminRequestVM.approveNameChangeRequest(request: request) } },
                        onReject: { Task { await adminRequestVM.rejectNameChangeRequest(request: request) } },
                        onTap: { selectedDetail = .nameChange(request) }
                    ) {
                        nameChangeRow(for: request)
                    }
                }
                .sheet(item: $nameEditRequest) { request in
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
                        onReject: { Task { await diwaniyaVM.rejectDiwaniya(id: diwaniya.id) } },
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
                        onReject: { Task { await adminRequestVM.rejectDeceasedRequest(request: request) } },
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
                        onReject: { Task { await adminRequestVM.rejectChildAddRequest(request: request) } },
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
                        onReject: { Task { await adminRequestVM.rejectPhotoSuggestion(request: request) } },
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
                        onReject: { Task { await projectsVM.rejectProject(id: project.id) } },
                        onTap: { selectedDetail = .project(project) }
                    ) {
                        projectRow(for: project)
                    }
                }
            case .gallery:
                selectAllButton(ids: memberVM.pendingGalleryPhotos.map { $0.id })
                ForEach(memberVM.pendingGalleryPhotos) { photo in
                    selectableRow(
                        id: photo.id,
                        accentColor: RequestTab.gallery.color,
                        onApprove: { Task { await memberVM.approveGalleryPhoto(photoId: photo.id) } },
                        onReject: { Task { await memberVM.rejectGalleryPhoto(photoId: photo.id, photoURL: photo.photoURL) } },
                        onTap: { }
                    ) {
                        galleryPendingRow(photo: photo)
                    }
                }
            case .treeAdd:
                treeEditList(action: .add, color: RequestTab.treeAdd.color)
            case .treeEditName:
                treeEditList(action: .editName, color: RequestTab.treeEditName.color)
            case .treeEditPhone:
                treeEditList(action: .editPhone, color: RequestTab.treeEditPhone.color)
            case .treeDeceased:
                treeEditList(action: .deceased, color: RequestTab.treeDeceased.color)
            case .treeDelete:
                treeEditList(action: .delete, color: RequestTab.treeDelete.color)
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .id(selectedTab) // إعادة رسم سريعة عند تغيير التاب
        .animation(.snappy(duration: 0.2), value: selectedTab)
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

    /// بطاقة طلب موحّدة — تشمل محتوى الطلب + أزرار موافقة/رفض مرئية + إطار نظيف.
    /// - `accentColor`: لون الـ tab — يُستخدم لإطار البطاقة (إشارة بصرية للنوع)
    /// - `approveLabel`: نص زر الموافقة (افتراضي: "موافقة")
    /// - `approveIcon`: أيقونة زر الموافقة (افتراضي: checkmark)
    /// - `onApprove`/`onReject`: nil = الزر يختفي
    private func selectableRow<Content: View>(
        id: UUID,
        accentColor: Color = DS.Color.primary,
        approveLabel: String? = nil,
        approveIcon: String = "checkmark",
        approveColor: Color = DS.Color.success,
        onApprove: (() -> Void)? = nil,
        onReject: (() -> Void)? = nil,
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            // المحتوى — قابل للنقر
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
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    if isSelectMode {
                        Image(systemName: selectedIds.contains(id) ? "checkmark.circle.fill" : "circle")
                            .font(DS.Font.scaled(22, weight: .regular))
                            .foregroundColor(selectedIds.contains(id) ? DS.Color.primary : DS.Color.textTertiary)
                            .transition(.scale.combined(with: .opacity))
                            .padding(.top, 2)
                    }
                    content()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(DS.Spacing.md)
            }
            .buttonStyle(.plain)

            // شريط الإجراءات السفلي — يظهر فقط خارج وضع التحديد
            if !isSelectMode, (onApprove != nil || onReject != nil) {
                Divider().opacity(0.35).padding(.horizontal, DS.Spacing.md)
                requestActionsBar(
                    approveLabel: approveLabel,
                    approveIcon: approveIcon,
                    approveColor: approveColor,
                    onApprove: onApprove,
                    onReject: onReject
                )
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(
                    isSelectMode && selectedIds.contains(id)
                        ? DS.Color.primary.opacity(0.06)
                        : DS.Color.surface
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(
                    isSelectMode && selectedIds.contains(id)
                        ? DS.Color.primary.opacity(0.40)
                        : accentColor.opacity(0.15),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.04), radius: 5, x: 0, y: 2)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: DS.Spacing.lg, bottom: 6, trailing: DS.Spacing.lg))
    }

    /// شريط أزرار موافقة/رفض — يتكيّف حسب الصلاحيات وما هو مرسَل.
    @ViewBuilder
    private func requestActionsBar(
        approveLabel: String?,
        approveIcon: String,
        approveColor: Color,
        onApprove: (() -> Void)?,
        onReject: (() -> Void)?
    ) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            // زر الرفض — يظهر فقط لمن يملك الصلاحية
            if let onReject, authVM.canRejectRequests {
                Button(action: onReject) {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark")
                            .font(DS.Font.scaled(11, weight: .bold))
                        Text(L10n.t("رفض", "Reject"))
                            .font(DS.Font.scaled(13, weight: .bold))
                    }
                    .foregroundColor(DS.Color.error)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(DS.Color.error.opacity(0.10)))
                    .overlay(Capsule().strokeBorder(DS.Color.error.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            // زر الموافقة — قابل للتخصيص (مثل "ربط" بدل "موافقة" لطلبات الانضمام)
            if let onApprove {
                Button(action: onApprove) {
                    HStack(spacing: 5) {
                        Image(systemName: approveIcon)
                            .font(DS.Font.scaled(11, weight: .bold))
                        Text(approveLabel ?? L10n.t("موافقة", "Approve"))
                            .font(DS.Font.scaled(13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [approveColor, approveColor.opacity(0.85)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: approveColor.opacity(0.30), radius: 5, x: 0, y: 2)
                }
                .buttonStyle(.plain)
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
        case .gallery:
            for id in ids {
                await memberVM.approveGalleryPhoto(photoId: id)
                count += 1
            }
        case .treeAdd, .treeEditName, .treeEditPhone, .treeDeceased, .treeDelete:
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
        case .gallery:
            for id in ids {
                if let photo = memberVM.pendingGalleryPhotos.first(where: { $0.id == id }) {
                    await memberVM.rejectGalleryPhoto(photoId: photo.id, photoURL: photo.photoURL)
                    count += 1
                }
            }
        case .treeAdd, .treeEditName, .treeEditPhone, .treeDeceased, .treeDelete:
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

    /// قائمة عناصر صحة الشجرة لفئة معيّنة — صف بسيط بدون موافقة/رفض، تفتح AdminTreeHealthView بالنقر.
    @ViewBuilder
    private func treeHealthList(issue: TreeHealthIssue, color: Color) -> some View {
        ForEach(healthMembers(for: issue)) { member in
            selectableRow(
                id: member.id,
                accentColor: color,
                onApprove: nil,
                onReject: nil,
                onTap: { openTreeHealthFilter = issue.asAdminFilter }
            ) {
                treeHealthRow(member: member, issue: issue, color: color)
            }
        }
    }

    /// صف بسيط لعنصر صحة شجرة — اسم العضو + الـ issue badge.
    private func treeHealthRow(member: FamilyMember, issue: TreeHealthIssue, color: Color) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            iconCircle(icon: issue.asTab.icon, color: color, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.fullName.isEmpty ? L10n.t("بدون اسم", "(no name)") : member.fullName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                Text(issue.asTab.title)
                    .font(DS.Font.caption2)
                    .foregroundColor(color)
            }
            Spacer()
            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)
        }
    }

    /// القيمة الجديدة للعرض حسب نوع الإجراء.
    private func treeEditNewValue(payload: TreeEditPayload?, action: TreeEditAction) -> String? {
        guard let payload else { return nil }
        switch action {
        case .editName: return (payload.newName?.isEmpty == false) ? payload.newName : nil
        case .editPhone: return (payload.newPhone?.isEmpty == false) ? payload.newPhone : nil
        case .deceased: return (payload.deathDate?.isEmpty == false) ? payload.deathDate : nil
        case .add: return (payload.newMemberName?.isEmpty == false) ? payload.newMemberName : nil
        case .delete: return nil
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
                onReject: { Task { await adminRequestVM.rejectTreeEditRequest(request: request, reason: nil) } },
                onTap: { /* لا شيت تفاصيل خاص بطلبات الشجرة حالياً */ }
            ) {
                treeEditRow(request: request, action: action, color: color)
            }
        }
    }

    /// صف موحّد لطلبات الشجرة — يعرض الإجراء واسم العضو والقيمة الجديدة + الوقت.
    private func treeEditRow(request: AdminRequest, action: TreeEditAction, color: Color) -> some View {
        let payload = request.treeEditPayload
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: action.iconName, color: color, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(action.arabicLabel, action.englishLabel))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(request.member?.fullName ?? L10n.t("عضو", "Member"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
                Spacer()
            }

            // قيمة جديدة حسب الإجراء
            if let newDisplay = treeEditNewValue(payload: payload, action: action) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(DS.Font.scaled(10, weight: .bold))
                        .foregroundColor(DS.Color.success)
                    Text(L10n.t("القيمة الجديدة:", "New:")).font(DS.Font.caption2).foregroundColor(DS.Color.textSecondary)
                    Text(newDisplay).font(DS.Font.caption1).fontWeight(.semibold).foregroundColor(DS.Color.textPrimary)
                    Spacer()
                }
            }

            if let date = request.createdAt {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(formatRegistrationDate(date))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
    }

    /// محتوى تاب "الكل" — يصدر كل الأنواع في تسلسل (إطار البطاقة الملوّن يعطي تمييزاً بصرياً).
    @ViewBuilder
    private func allRequestsContent() -> some View {
        ForEach(pendingMembers) { member in
            selectableRow(
                id: member.id,
                accentColor: RequestTab.joinRequests.color,
                approveLabel: L10n.t("ربط", "Link"),
                approveIcon: "link.badge.plus",
                onApprove: { memberToLink = member },
                onReject: { Task { await adminRequestVM.rejectOrDeleteMember(memberId: member.id) } },
                onTap: { selectedDetail = .join(member) }
            ) {
                joinRequestRow(for: member)
            }
        }
        ForEach(newsVM.pendingNewsRequests) { post in
            selectableRow(
                id: post.id,
                accentColor: RequestTab.news.color,
                onApprove: { Task { await newsVM.approveNewsPost(postId: post.id) } },
                onReject: { Task { await newsVM.rejectNewsPost(postId: post.id) } },
                onTap: { selectedDetail = .news(post) }
            ) { newsRow(for: post) }
        }
        ForEach(adminRequestVM.newsReportRequests) { request in
            selectableRow(
                id: request.id,
                accentColor: RequestTab.reports.color,
                onApprove: { Task { await adminRequestVM.approveNewsReport(request: request) } },
                onReject: { Task { await adminRequestVM.rejectNewsReport(request: request) } },
                onTap: { selectedDetail = .report(request) }
            ) { reportRow(for: request) }
        }
        ForEach(adminRequestVM.phoneChangeRequests) { request in
            selectableRow(
                id: request.id,
                accentColor: RequestTab.phone.color,
                onApprove: { Task { await adminRequestVM.approvePhoneChangeRequest(request: request) } },
                onReject: { Task { await adminRequestVM.rejectPhoneChangeRequest(request: request) } },
                onTap: { selectedDetail = .phone(request) }
            ) { phoneRow(for: request) }
        }
        ForEach(adminRequestVM.nameChangeRequests) { request in
            selectableRow(
                id: request.id,
                accentColor: RequestTab.nameChange.color,
                onApprove: { Task { await adminRequestVM.approveNameChangeRequest(request: request) } },
                onReject: { Task { await adminRequestVM.rejectNameChangeRequest(request: request) } },
                onTap: { selectedDetail = .nameChange(request) }
            ) { nameChangeRow(for: request) }
        }
        ForEach(diwaniyaVM.pendingDiwaniyas) { diwaniya in
            selectableRow(
                id: diwaniya.id,
                accentColor: RequestTab.diwaniya.color,
                onApprove: {
                    if let adminId = authVM.currentUser?.id {
                        Task { await diwaniyaVM.approveDiwaniya(id: diwaniya.id, adminId: adminId) }
                    }
                },
                onReject: { Task { await diwaniyaVM.rejectDiwaniya(id: diwaniya.id) } },
                onTap: { selectedDetail = .diwaniya(diwaniya) }
            ) { diwaniyaRow(for: diwaniya) }
        }
        ForEach(adminRequestVM.deceasedRequests) { request in
            selectableRow(
                id: request.id,
                accentColor: RequestTab.deceased.color,
                onApprove: { Task { await adminRequestVM.approveDeceasedRequest(request: request) } },
                onReject: { Task { await adminRequestVM.rejectDeceasedRequest(request: request) } },
                onTap: { selectedDetail = .deceased(request) }
            ) { deceasedRow(for: request) }
        }
        ForEach(adminRequestVM.childAddRequests) { request in
            selectableRow(
                id: request.id,
                accentColor: RequestTab.children.color,
                approveLabel: L10n.t("تأكيد", "Confirm"),
                onApprove: { Task { await adminRequestVM.acknowledgeChildAddRequest(request: request) } },
                onReject: { Task { await adminRequestVM.rejectChildAddRequest(request: request) } },
                onTap: { selectedDetail = .child(request) }
            ) { childRow(for: request) }
        }
        ForEach(adminRequestVM.photoSuggestionRequests) { request in
            selectableRow(
                id: request.id,
                accentColor: RequestTab.photos.color,
                onApprove: { Task { await adminRequestVM.approvePhotoSuggestion(request: request) } },
                onReject: { Task { await adminRequestVM.rejectPhotoSuggestion(request: request) } },
                onTap: { selectedDetail = .photo(request) }
            ) { photoRow(for: request) }
        }
        ForEach(projectsVM.pendingProjects) { project in
            selectableRow(
                id: project.id,
                accentColor: RequestTab.projects.color,
                onApprove: {
                    if let adminId = authVM.currentUser?.id {
                        Task { await projectsVM.approveProject(id: project.id, approvedBy: adminId) }
                    }
                },
                onReject: { Task { await projectsVM.rejectProject(id: project.id) } },
                onTap: { selectedDetail = .project(project) }
            ) { projectRow(for: project) }
        }
        ForEach(memberVM.pendingGalleryPhotos) { photo in
            selectableRow(
                id: photo.id,
                accentColor: RequestTab.gallery.color,
                onApprove: { Task { await memberVM.approveGalleryPhoto(photoId: photo.id) } },
                onReject: { Task { await memberVM.rejectGalleryPhoto(photoId: photo.id, photoURL: photo.photoURL) } },
                onTap: { }
            ) { galleryPendingRow(photo: photo) }
        }
        // طلبات الشجرة (كل الإجراءات)
        treeEditList(action: .add, color: RequestTab.treeAdd.color)
        treeEditList(action: .editName, color: RequestTab.treeEditName.color)
        treeEditList(action: .editPhone, color: RequestTab.treeEditPhone.color)
        treeEditList(action: .deceased, color: RequestTab.treeDeceased.color)
        treeEditList(action: .delete, color: RequestTab.treeDelete.color)
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
            } else if memberVM.pendingGalleryPhotos.contains(where: { $0.id == id }) {
                await memberVM.approveGalleryPhoto(photoId: id); count += 1
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
            } else if let photo = memberVM.pendingGalleryPhotos.first(where: { $0.id == id }) {
                await memberVM.rejectGalleryPhoto(photoId: photo.id, photoURL: photo.photoURL); count += 1
            } else if let req = adminRequestVM.treeEditRequests.first(where: { $0.id == id }) {
                await adminRequestVM.rejectTreeEditRequest(request: req, reason: nil); count += 1
            }
        }
        return count
    }

    // MARK: - Empty State

    private var emptyState: some View {
        DSEmptyState(
            icon: "checkmark.circle.fill",
            title: L10n.t("لا توجد طلبات معلقة", "No pending requests"),
            style: .halo,
            tint: DS.Color.success
        )
    }

    // MARK: - Join Request Row

    private func joinRequestRow(for member: FamilyMember) -> some View {
        // كل المتغيرات خارج ViewBuilder لتفادي مشاكل @ViewBuilder مع let
        let matches = combinedMatches(for: member)
        let hasMatches = !matches.isEmpty
        let serverMatchCount = registrationMatches[member.id]?.count ?? 0
        let platform = member.registrationPlatform ?? "ios"
        let registrationTime = member.createdAt.map { formatRegistrationDate($0) } ?? "—"
        let uname = member.username
        let isFullName = member.fullName.split(whereSeparator: \.isWhitespace).count >= 5
        let orderedResults = orderedMatchList(for: member)
        let isExpanded = expandedMatchMembers.contains(member.id)
        let visible = isExpanded ? orderedResults : Array(orderedResults.prefix(5))

        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "person.badge.shield.checkmark", color: hasMatches ? DS.Color.success : DS.Color.warning, size: 36)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(member.fullName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)

                    // اسم المستخدم (من الموقع)
                    if let uname {
                        HStack(spacing: 3) {
                            Image(systemName: "at")
                                .font(DS.Font.scaled(9, weight: .bold))
                            Text(uname)
                                .font(DS.Font.scaled(11, weight: .bold))
                        }
                        .foregroundColor(DS.Color.primary)
                    }

                    // رقم هاتف المنضم
                    if let phone = member.phoneNumber, !phone.isEmpty {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "phone.fill")
                                .font(DS.Font.scaled(10))
                            Text(KuwaitPhone.display(phone))
                                .font(DS.Font.scaled(11, weight: .medium))
                                .monospacedDigit()
                        }
                        .foregroundColor(DS.Color.textSecondary)
                    }

                    if isFullName {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(DS.Font.scaled(10))
                                .foregroundColor(DS.Color.success)
                            Text(L10n.t("اسم خماسي مكتمل", "Full 5-part name"))
                                .font(DS.Font.scaled(10))
                                .foregroundColor(DS.Color.success)
                        }
                    }

                    // الوقت والتاريخ
                    HStack(spacing: 3) {
                        Image(systemName: "clock.fill")
                            .font(DS.Font.scaled(9))
                        Text(registrationTime)
                            .font(DS.Font.scaled(10, weight: .semibold))
                    }
                    .foregroundColor(DS.Color.textSecondary)

                    // المصدر
                    HStack(spacing: 3) {
                        Image(systemName: platform == "web" ? "globe" : "iphone")
                            .font(DS.Font.scaled(9))
                        Text(platform == "web" ? L10n.t("الموقع", "Web") : L10n.t("التطبيق", "App"))
                            .font(DS.Font.scaled(10, weight: .bold))
                    }
                    .foregroundColor(platform == "web" ? DS.Color.info : DS.Color.success)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((platform == "web" ? DS.Color.info : DS.Color.success).opacity(0.12))
                    .clipShape(Capsule())
                }

                Spacer()

                // بادج مطابقات التسجيل
                if serverMatchCount > 0 {
                    VStack(spacing: 2) {
                        Text("\(serverMatchCount)")
                            .font(DS.Font.scaled(14, weight: .black))
                            .foregroundColor(DS.Color.info)
                        Text(L10n.t("مطابقة", "match"))
                            .font(DS.Font.scaled(8, weight: .bold))
                            .foregroundColor(DS.Color.info)
                    }
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(DS.Color.info.opacity(0.1))
                    .cornerRadius(DS.Radius.md)
                }
            }

            // نتائج التطابق — لستة مرتبة من الاسم الأول للأخير
            if !orderedResults.isEmpty {
                VStack(spacing: DS.Spacing.xs) {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "person.2.fill")
                            .font(DS.Font.scaled(13, weight: .semibold))
                            .foregroundColor(DS.Color.primary)
                        Text(L10n.t(
                            "تطابق محتمل (\(orderedResults.count))",
                            "Potential matches (\(orderedResults.count))"
                        ))
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        Spacer()
                    }

                    ForEach(visible, id: \.member.id) { match in
                        joinMatchRow(match: match, pendingMember: member)
                    }

                    if orderedResults.count > 5 && !isExpanded {
                        Button {
                            withAnimation(DS.Anim.snappy) {
                                _ = expandedMatchMembers.insert(member.id)
                            }
                        } label: {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: "chevron.down")
                                    .font(DS.Font.scaled(11, weight: .bold))
                                Text(L10n.t(
                                    "عرض الكل (\(orderedResults.count))",
                                    "Show all (\(orderedResults.count))"
                                ))
                                .font(DS.Font.scaled(11, weight: .bold))
                            }
                            .foregroundColor(DS.Color.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Spacing.xs)
                        }
                        .buttonStyle(DSScaleButtonStyle())
                    }
                }
                .padding(DS.Spacing.sm)
                .background(DS.Color.primary.opacity(0.04))
                .cornerRadius(DS.Radius.md)
            } else {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "person.badge.plus")
                        .font(DS.Font.scaled(12, weight: .semibold))
                        .foregroundColor(DS.Color.textSecondary)
                    Text(L10n.t("لا يوجد تطابق — اسم جديد", "No tree matches — new name"))
                        .font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(DS.Color.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xs)
                .background(DS.Color.surface)
                .cornerRadius(DS.Radius.sm)
            }
        }
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
            // نسبة التطابق كدائرة
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.1))
                    .frame(width: 36, height: 36)
                Text("\(matchPercent)%")
                    .font(DS.Font.scaled(11, weight: .black))
                    .foregroundColor(DS.Color.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(match.member.fullName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: DS.Spacing.xs) {
                    Text(L10n.t(
                        "\(match.matchCount) من \(totalParts) أسماء متطابقة",
                        "\(match.matchCount) of \(totalParts) names match"
                    ))
                    .font(DS.Font.scaled(10, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)

                    if match.isRegistrationMatch {
                        Text(L10n.t("تسجيل", "Reg"))
                            .font(DS.Font.scaled(9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(DS.Color.primary)
                            .clipShape(Capsule())
                    }
                }

                // رقم الهاتف
                if let phone = match.member.phoneNumber, !phone.isEmpty {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "phone.fill")
                            .font(DS.Font.scaled(9))
                        Text(KuwaitPhone.display(phone))
                            .font(DS.Font.scaled(10, weight: .medium))
                            .monospacedDigit()
                    }
                    .foregroundColor(DS.Color.textTertiary)
                }
            }

            Spacer()

            Button {
                mergeTarget = (pendingMember: pendingMember, treeMember: match.member)
                showMergeConfirm = true
            } label: {
                Text(L10n.t("ربط", "Link"))
                    .font(DS.Font.scaled(12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(DS.Color.gradientPrimary)
                    .clipShape(Capsule())
            }
            .buttonStyle(DSScaleButtonStyle())
        }
        .padding(DS.Spacing.sm)
        .background(DS.Color.surface)
        .cornerRadius(DS.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.primary.opacity(0.1), lineWidth: 1)
        )
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

            // تحقق: هل الاسم الأول للعضو الموجود يطابق أي جزء من اسم المنضم؟
            guard let existingFirst = existingParts.first else { continue }
            let firstNameMatch = newParts.contains { $0.localizedCaseInsensitiveCompare(existingFirst) == .orderedSame }
            guard firstNameMatch else { continue }

            // عد كل الأجزاء المتطابقة
            var matchedParts: [String] = []
            var usedIndices: Set<Int> = []

            for newPart in newParts {
                for (idx, existingPart) in existingParts.enumerated() {
                    if !usedIndices.contains(idx) && newPart.localizedCaseInsensitiveCompare(existingPart) == .orderedSame {
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
                if newParts[i].localizedCaseInsensitiveCompare(existingParts[i]) == .orderedSame {
                    matchedParts.append(newParts[i])
                } else {
                    break
                }
            }

            // لازم الاسم الأول على الأقل يتطابق
            if !matchedParts.isEmpty {
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
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "newspaper.fill", color: newsTypeColor(post.type), size: 36)

                Text(post.author_name)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                Spacer()

                typeBadge(text: post.type, color: newsTypeColor(post.type))
            }

            contentBlock(post.content)

            if !post.mediaURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.xs) {
                        ForEach(post.mediaURLs, id: \.self) { urlStr in
                            if let url = URL(string: urlStr) {
                                CachedAsyncImage(url: url) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                                        .fill(DS.Color.surface)
                                        .overlay(ProgressView().tint(DS.Color.primary))
                                }
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                            }
                        }
                    }
                }
            }

            // التاريخ تحت
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "clock")
                    .font(DS.Font.scaled(10, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                Text(formatRegistrationDate(String(post.created_at)))
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
    }

    // MARK: - Report Row

    private func reportRow(for request: AdminRequest) -> some View {
        let postId = UUID(uuidString: request.newValue ?? "")
        let reportedPost = postId.flatMap { id in newsVM.allNews.first { $0.id == id } }

        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "exclamationmark.triangle.fill", color: DS.Color.error, size: 36)

                Text(request.member?.fullName ?? L10n.t("عضو", "Member"))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)

                Spacer()
            }

            contentBlock(request.details ?? L10n.t("بلاغ بدون تفاصيل", "Report without details"))

            if let post = reportedPost {
                Text(post.content)
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Spacing.sm)
                    .background(DS.Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            }

            // التاريخ تحت
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "clock")
                    .font(DS.Font.scaled(10, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                Text(request.createdAt.map { formatRegistrationDate($0) } ?? "—")
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
    }

    // MARK: - Phone Row

    private func phoneRow(for request: PhoneChangeRequest) -> some View {
        let currentPhone = KuwaitPhone.display(request.member?.phoneNumber)
        let newPhone = KuwaitPhone.display(request.newValue)
        let memberName = request.member?.fullName ?? "Member"

        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "phone.arrow.right", color: DS.Color.primary, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(memberName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)

                    Text(L10n.t("طلب تغيير رقم", "Phone change request"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }

                Spacer()
            }

            HStack(spacing: DS.Spacing.md) {
                VStack(spacing: 2) {
                    Text(L10n.t("الجديد", "New"))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                    Text(newPhone)
                        .font(DS.Font.caption1)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

                Image(systemName: "arrow.forward")
                    .font(DS.Font.scaled(12, weight: .semibold))
                    .foregroundColor(DS.Color.textTertiary)

                VStack(spacing: 2) {
                    Text(L10n.t("الحالي", "Current"))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                    Text(currentPhone)
                        .font(DS.Font.caption1)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            }

            // التاريخ تحت
            if let createdAt = request.createdAt {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(formatRegistrationDate(String(createdAt)))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Diwaniya Row

    private func diwaniyaRow(for diwaniya: Diwaniya) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "tent.fill", color: DS.Color.gridDiwaniya, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(diwaniya.title)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)

                    Text(diwaniya.ownerName)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }

                Spacer()
            }

            if let schedule = diwaniya.scheduleText, !schedule.isEmpty {
                detailRow(icon: "calendar", text: schedule)
            }
            if let address = diwaniya.address, !address.isEmpty {
                detailRow(icon: "mappin.and.ellipse", text: address)
            }
        }
    }

    // MARK: - Deceased Row

    private func deceasedRow(for request: AdminRequest) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "bolt.heart.fill", color: DS.Color.error, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(request.member?.fullName ?? L10n.t("عضو", "Member"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)

                    if let requester = memberVM.allMembers.first(where: { $0.id == request.requesterId }) {
                        Text(L10n.t("من: \(requester.fullName)", "By: \(requester.fullName)"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                }

                Spacer()
            }

            if let details = request.details, !details.isEmpty {
                contentBlock(details)
            }

            // التاريخ تحت
            if let createdAt = request.createdAt {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(formatRegistrationDate(String(createdAt)))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Child Row

    private func childRow(for request: AdminRequest) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "person.badge.plus", color: DS.Color.info, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(request.member?.fullName ?? L10n.t("عضو", "Member"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)

                    if let requester = memberVM.allMembers.first(where: { $0.id == request.requesterId }) {
                        Text(L10n.t("من: \(requester.fullName)", "By: \(requester.fullName)"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                }

                Spacer()
            }

            if let details = request.details, !details.isEmpty {
                contentBlock(details)
            }

            // التاريخ تحت
            if let createdAt = request.createdAt {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(formatRegistrationDate(String(createdAt)))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Photo Row

    private func photoRow(for request: AdminRequest) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "camera.badge.ellipsis", color: DS.Color.neonBlue, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(request.member?.fullName ?? L10n.t("عضو", "Member"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)

                    if let requester = memberVM.allMembers.first(where: { $0.id == request.requesterId }) {
                        Text(L10n.t("من: \(requester.fullName)", "By: \(requester.fullName)"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                }

                Spacer()
            }

            if let details = request.details, !details.isEmpty {
                contentBlock(details)
            }

            if let photoUrl = request.newValue, let url = URL(string: photoUrl) {
                CachedAsyncImage(url: url) { img in
                    img.resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                } placeholder: {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.surface)
                        .frame(height: 140)
                        .overlay(ProgressView().tint(DS.Color.primary))
                }
            }

            // التاريخ تحت
            if let createdAt = request.createdAt {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(formatRegistrationDate(String(createdAt)))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Tree Edit Row

    // MARK: - Name Change Row

    private func nameChangeRow(for request: AdminRequest) -> some View {
        let currentName = request.member?.fullName ?? L10n.t("عضو", "Member")
        let newName = request.newValue ?? "—"

        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // الصف الأول: الأيقونة + الاسم + البادج
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "rectangle.and.pencil.and.ellipsis", color: DS.Color.neonPurple, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(currentName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)

                    if let requester = memberVM.allMembers.first(where: { $0.id == request.requesterId }) {
                        Text(L10n.t("من: \(requester.fullName)", "By: \(requester.fullName)"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                }

                Spacer()
            }

            // الاسم الجديد
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "arrow.forward")
                    .font(DS.Font.scaled(10, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
                Text(L10n.t("الاسم الجديد:", "New name:"))
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)
                Text(newName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surfaceElevated)
            .cornerRadius(DS.Radius.sm)

            // التاريخ تحت
            if let createdAt = request.createdAt {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(formatRegistrationDate(String(createdAt)))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Admin Name Edit Sheet
    private func adminNameEditSheet(request: AdminRequest) -> some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.xl) {
                // الاسم الحالي
                HStack(spacing: DS.Spacing.sm) {
                    Text(L10n.t("الاسم الحالي:", "Current name:"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                    Text(request.member?.fullName ?? "—")
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Spacing.lg)

                // حقل تعديل الاسم
                DSTextField(
                    label: L10n.t("الاسم المعدّل", "Modified Name"),
                    placeholder: L10n.t("اكتب الاسم الصحيح", "Enter correct name"),
                    text: $editedName,
                    icon: "pencil",
                    iconColor: DS.Color.primary
                )
                .padding(.horizontal, DS.Spacing.lg)

                Text(L10n.t(
                    "يمكنك تعديل الاسم قبل الموافقة عليه.",
                    "You can modify the name before approving."
                ))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
                .padding(.horizontal, DS.Spacing.xxl)

                DSPrimaryButton(
                    L10n.t("موافقة بالاسم المعدّل", "Approve with Modified Name"),
                    icon: "checkmark.circle.fill"
                ) {
                    let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    Task {
                        var modifiedRequest = request
                        modifiedRequest.newValue = trimmed
                        await adminRequestVM.approveNameChangeRequest(request: modifiedRequest)
                        nameEditRequest = nil
                    }
                }
                .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, DS.Spacing.lg)

                Spacer()
            }
            .padding(.top, DS.Spacing.xl)
            .navigationTitle(L10n.t("تعديل الاسم", "Edit Name"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { nameEditRequest = nil }
                        .foregroundColor(DS.Color.primary)
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Admin Phone Edit Sheet
    private func adminPhoneEditSheet(request: PhoneChangeRequest) -> some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.xl) {
                // الرقم الحالي
                HStack(spacing: DS.Spacing.sm) {
                    Text(L10n.t("الرقم الحالي:", "Current number:"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                    Text(KuwaitPhone.display(request.member?.phoneNumber))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Spacing.lg)

                // الرقم المطلوب
                HStack(spacing: DS.Spacing.sm) {
                    Text(L10n.t("الرقم المطلوب:", "Requested number:"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                    Text(KuwaitPhone.display(request.newValue))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.success)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Spacing.lg)

                // حقل تعديل الرقم
                DSTextField(
                    label: L10n.t("الرقم المعدّل", "Modified Number"),
                    placeholder: L10n.t("اكتب الرقم الصحيح", "Enter correct number"),
                    text: $editedPhone,
                    icon: "phone",
                    iconColor: DS.Color.primary
                )
                .keyboardType(.phonePad)
                .padding(.horizontal, DS.Spacing.lg)

                Text(L10n.t(
                    "يمكنك تعديل الرقم قبل الموافقة عليه.",
                    "You can modify the number before approving."
                ))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
                .padding(.horizontal, DS.Spacing.xxl)

                DSPrimaryButton(
                    L10n.t("موافقة بالرقم المعدّل", "Approve with Modified Number"),
                    icon: "checkmark.circle.fill"
                ) {
                    let trimmed = editedPhone.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    Task {
                        var modifiedRequest = request
                        modifiedRequest.newValue = trimmed
                        await adminRequestVM.approvePhoneChangeRequest(request: modifiedRequest)
                        phoneEditRequest = nil
                    }
                }
                .disabled(editedPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, DS.Spacing.lg)

                Spacer()
            }
            .padding(.top, DS.Spacing.xl)
            .navigationTitle(L10n.t("تعديل الرقم", "Edit Number"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { phoneEditRequest = nil }
                        .foregroundColor(DS.Color.primary)
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Tree Edit Row

    // MARK: - Project Row

    // MARK: - Gallery Pending Row
    private func galleryPendingRow(photo: MemberGalleryPhoto) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "photo.on.rectangle.angled", color: DS.Color.gridDiwaniya, size: 36)

                Text(memberVM.member(byId: photo.memberId)?.fullName ?? L10n.t("عضو", "Member"))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)

                Spacer()
            }

            if let caption = photo.caption, !caption.isEmpty {
                contentBlock(caption)
            }

            // صورة مصغرة
            AsyncImage(url: URL(string: photo.photoURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                default:
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.surface)
                        .frame(height: 140)
                        .overlay(ProgressView().tint(DS.Color.primary))
                }
            }

            // التاريخ تحت
            if let date = photo.createdAt {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(formatRegistrationDate(String(date)))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Story Pending Row
    private func storyPendingRow(story: FamilyStory) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "circle.dashed", color: DS.Color.neonCyan, size: 36)

                Text(memberVM.member(byId: story.memberId)?.firstName ?? L10n.t("عضو", "Member"))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)

                Spacer()
            }

            if let caption = story.caption, !caption.isEmpty {
                contentBlock(caption)
            }

            // صورة مصغرة
            CachedAsyncPhaseImage(url: URL(string: story.imageUrl)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.surface)
                        .frame(height: 140)
                        .overlay(ProgressView().tint(DS.Color.primary))
                }
            }

            // التاريخ تحت
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "clock")
                    .font(DS.Font.scaled(10, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                Text(formatRegistrationDate(story.createdAt))
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
    }

    private func projectRow(for project: Project) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                // Logo or placeholder
                if let logoUrl = project.logoUrl, let url = URL(string: logoUrl) {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        iconCircle(icon: "briefcase.fill", color: DS.Color.neonPurple, size: 36)
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                } else {
                    iconCircle(icon: "briefcase.fill", color: DS.Color.neonPurple, size: 36)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(project.title)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)

                    Text(project.ownerName)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }

                Spacer()
            }

            if let desc = project.description, !desc.isEmpty {
                contentBlock(desc)
            }

            // التاريخ تحت
            if let date = project.createdAt {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(L10n.t("أُضيف: \(formatRegistrationDate(date))", "Added: \(formatRegistrationDate(date))"))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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

    private func typeBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(DS.Font.caption2)
            .fontWeight(.bold)
            .foregroundColor(color)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Font.scaled(12, weight: .medium))
                .foregroundColor(DS.Color.textTertiary)
                .frame(width: 18)
            Text(text)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(2)
        }
    }

    /// بلوك محتوى/تفاصيل موحد — ليبل + نص بخط أكبر
    private func contentBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(L10n.t("التفاصيل", "Details"))
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textTertiary)
            Text(text)
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Spacing.sm)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    // MARK: - Request Detail Sheet

    @ViewBuilder
    /// شيت تفاصيل الطلب — تصميم موحّد لكل الأنواع.
    private func requestDetailSheet(_ detail: RequestDetail) -> some View {
        let meta = detailMeta(for: detail)
        return NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                        // Hero — أيقونة كبيرة + نوع الطلب + الوقت
                        detailHero(icon: meta.icon, color: meta.color, title: meta.title, timestamp: meta.timestamp)

                        // محتوى مخصّص لكل نوع
                        detailContent(for: detail)

                        // مساحة سفلية لتجنّب اختفاء آخر بطاقة خلف شريط الإجراءات
                        Color.clear.frame(height: 90)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.md)
                }
                .background(DS.Color.background)

                // شريط الإجراءات السفلي الثابت
                stickyActionsBar(for: detail, accent: meta.color)
            }
            .navigationTitle(L10n.t("تفاصيل الطلب", "Request Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { selectedDetail = nil }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// metadata موحَّدة لكل نوع طلب — يُستخدم في hero + actions.
    private struct DetailMeta {
        let icon: String
        let color: Color
        let title: String
        let timestamp: String?
    }

    private func detailMeta(for detail: RequestDetail) -> DetailMeta {
        switch detail {
        case .join(let m):
            return .init(icon: "person.badge.shield.checkmark", color: DS.Color.info,
                         title: L10n.t("طلب انضمام", "Join Request"),
                         timestamp: m.createdAt.map { formatRegistrationDate($0) })
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
                         title: L10n.t("تغيير اسم", "Name Change"),
                         timestamp: r.createdAt.map { formatRegistrationDate($0) })
        case .diwaniya(let d):
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
                         timestamp: r.createdAt.map { formatRegistrationDate($0) })
        case .project(let p):
            return .init(icon: "briefcase.fill", color: DS.Color.neonPurple,
                         title: L10n.t("طلب مشروع", "Project Request"),
                         timestamp: p.createdAt.map { formatRegistrationDate($0) })
        }
    }

    /// Hero فاخر: دائرة كبيرة بـ gradient + اسم الطلب + الوقت.
    private func detailHero(icon: String, color: Color, title: String, timestamp: String?) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.75)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: color.opacity(0.35), radius: 10, x: 0, y: 5)
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }

            Text(title)
                .font(DS.Font.scaled(20, weight: .black))
                .foregroundColor(DS.Color.textPrimary)

            if let timestamp {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(DS.Font.scaled(10, weight: .bold))
                    Text(timestamp)
                        .font(DS.Font.scaled(11, weight: .semibold))
                }
                .foregroundColor(DS.Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.md)
    }

    /// المحتوى المخصّص لكل نوع — بطاقات معلومات.
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
            comparisonCard(
                oldLabel: L10n.t("الاسم الحالي", "Current Name"),
                oldValue: request.member?.fullName ?? "—",
                newLabel: L10n.t("الاسم الجديد", "New Name"),
                newValue: request.newValue ?? "—",
                icon: "person.fill"
            )

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
        }
    }

    /// بطاقة معلومة بسيطة — أيقونة دائرية + label + قيمة.
    private func infoCard(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DS.Font.scaled(11, weight: .semibold))
                    .foregroundColor(DS.Color.textSecondary)
                Text(value)
                    .font(DS.Font.scaled(15, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(color.opacity(0.12), lineWidth: 1)
        )
    }

    /// بطاقة نص طويل — label + محتوى متعدد الأسطر.
    private func longTextCard(icon: String, label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(DS.Color.textSecondary)
                Text(label)
                    .font(DS.Font.scaled(11, weight: .semibold))
                    .foregroundColor(DS.Color.textSecondary)
            }
            Text(text)
                .font(DS.Font.body)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    /// بطاقة مقارنة "قبل/بعد" — مفيدة لتغييرات الاسم/الهاتف.
    private func comparisonCard(oldLabel: String, oldValue: String,
                                 newLabel: String, newValue: String, icon: String) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                ZStack {
                    Circle().fill(DS.Color.error.opacity(0.12)).frame(width: 32, height: 32)
                    Image(systemName: icon).font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(DS.Color.error)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(oldLabel).font(DS.Font.scaled(10, weight: .semibold))
                        .foregroundColor(DS.Color.textSecondary)
                    Text(oldValue).font(DS.Font.scaled(14, weight: .semibold))
                        .foregroundColor(DS.Color.textPrimary)
                        .strikethrough(true, color: DS.Color.error.opacity(0.5))
                }
                Spacer()
            }

            HStack(spacing: 4) {
                Spacer()
                Image(systemName: "arrow.down")
                    .font(DS.Font.scaled(10, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
                Spacer()
            }

            HStack(spacing: DS.Spacing.sm) {
                ZStack {
                    Circle().fill(DS.Color.success.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: icon).font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(DS.Color.success)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(newLabel).font(DS.Font.scaled(10, weight: .semibold))
                        .foregroundColor(DS.Color.success)
                    Text(newValue).font(DS.Font.scaled(14, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                }
                Spacer()
            }
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    /// بطاقة صورة كبيرة (للصور المقترحة).
    private func photoCard(url: URL) -> some View {
        CachedAsyncImage(url: url) { img in
            img.resizable().scaledToFit()
        } placeholder: {
            RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.surface)
                .frame(height: 200)
                .overlay(ProgressView().tint(DS.Color.primary))
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    /// شريط إجراءات سفلي ثابت بـ ultraThinMaterial.
    private func stickyActionsBar(for detail: RequestDetail, accent: Color) -> some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack(spacing: DS.Spacing.sm) {
                if authVM.canRejectRequests {
                    Button {
                        rejectDetail(detail)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark").font(DS.Font.scaled(12, weight: .bold))
                            Text(L10n.t("رفض", "Reject")).font(DS.Font.scaled(14, weight: .bold))
                        }
                        .foregroundColor(DS.Color.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(DS.Color.error.opacity(0.10)))
                        .overlay(Capsule().strokeBorder(DS.Color.error.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    approveDetail(detail)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: approveIconFor(detail))
                            .font(DS.Font.scaled(12, weight: .bold))
                        Text(approveLabelFor(detail))
                            .font(DS.Font.scaled(14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [DS.Color.success, DS.Color.success.opacity(0.85)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: DS.Color.success.opacity(0.35), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(adminRequestVM.isLoading)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .background(.ultraThinMaterial)
        }
    }

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
            }
        }
    }

    private func rejectDetail(_ detail: RequestDetail) {
        Task {
            switch detail {
            case .join(let member):
                await adminRequestVM.rejectOrDeleteMember(memberId: member.id)
            case .news(let post):
                await newsVM.rejectNewsPost(postId: post.id)
            case .report(let request):
                await adminRequestVM.rejectNewsReport(request: request)
            case .phone(let request):
                await adminRequestVM.rejectPhoneChangeRequest(request: request)
            case .nameChange(let request):
                await adminRequestVM.rejectNameChangeRequest(request: request)
            case .diwaniya(let diwaniya):
                await diwaniyaVM.rejectDiwaniya(id: diwaniya.id)
            case .deceased(let request):
                await adminRequestVM.rejectDeceasedRequest(request: request)
            case .child(let request):
                await adminRequestVM.rejectChildAddRequest(request: request)
            case .photo(let request):
                await adminRequestVM.rejectPhotoSuggestion(request: request)
            case .project(let project):
                await projectsVM.rejectProject(id: project.id)
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

    @ViewBuilder
    private func detailActions(for detail: RequestDetail) -> some View {
        DSApproveRejectButtons(
            approveTitle: {
                switch detail {
                case .join: return L10n.t("ربط بالشجرة", "Link to Tree")
                default: return L10n.t("موافقة", "Approve")
                }
            }(),
            rejectTitle: L10n.t("رفض", "Reject"),
            isLoading: adminRequestVM.isLoading,
            showReject: authVM.canRejectRequests
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
                }
            }
        }
        .padding(.top, DS.Spacing.md)
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

    private func newsMediaGrid(urls: [String]) -> some View {
        DSCard(padding: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text(L10n.t("الصور", "Images"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: DS.Spacing.sm)], spacing: DS.Spacing.sm) {
                    ForEach(urls, id: \.self) { urlStr in
                        if let url = URL(string: urlStr) {
                            CachedAsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: DS.Radius.sm)
                                    .fill(DS.Color.surface)
                                    .overlay(ProgressView().tint(DS.Color.primary))
                            }
                            .frame(height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                        }
                    }
                }
            }
        }
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
