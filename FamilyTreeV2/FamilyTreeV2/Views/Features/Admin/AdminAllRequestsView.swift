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
    @State private var treeEditToReject: AdminRequest? = nil
    @State private var rejectReasonText: String = ""
    @State private var showRejectReasonAlert = false

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
        case treeEdit(AdminRequest)
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
            case .treeEdit(let r): return "edit-\(r.id)"
            case .project(let p): return "proj-\(p.id)"
            }
        }
    }

    enum RequestTab: String, CaseIterable, Identifiable {
        case joinRequests, news, reports, phone, nameChange, diwaniya, deceased, children, photos, treeEdit, projects, gallery, stories

        var id: String { rawValue }

        var title: String {
            switch self {
            case .joinRequests: return L10n.t("انضمام", "Join")
            case .news: return L10n.t("أخبار", "News")
            case .reports: return L10n.t("بلاغات", "Reports")
            case .phone: return L10n.t("جوال", "Phone")
            case .nameChange: return L10n.t("أسماء", "Names")
            case .diwaniya: return L10n.t("ديوانيات", "Diwaniyas")
            case .deceased: return L10n.t("وفاة", "Deceased")
            case .children: return L10n.t("أبناء", "Children")
            case .photos: return L10n.t("صور مقترحة", "Suggested Photos")
            case .treeEdit: return L10n.t("تعديل", "Edit")
            case .projects: return L10n.t("مشاريع", "Projects")
            case .gallery: return L10n.t("معرض", "Gallery")
            case .stories: return L10n.t("قصص", "Stories")
            }
        }

        var icon: String {
            switch self {
            case .joinRequests: return "person.badge.shield.checkmark"
            case .news: return "newspaper.fill"
            case .reports: return "exclamationmark.bubble.fill"
            case .phone: return "phone.badge.checkmark"
            case .nameChange: return "rectangle.and.pencil.and.ellipsis"
            case .diwaniya: return "tent.fill"
            case .deceased: return "bolt.heart.fill"
            case .children: return "person.badge.plus"
            case .photos: return "camera.badge.ellipsis"
            case .treeEdit: return "pencil.and.list.clipboard"
            case .projects: return "briefcase.fill"
            case .gallery: return "photo.on.rectangle.angled"
            case .stories: return "circle.dashed"
            }
        }

        var color: Color {
            switch self {
            case .joinRequests: return DS.Color.info
            case .news: return DS.Color.warning
            case .reports: return DS.Color.error
            case .phone: return DS.Color.primary
            case .nameChange: return DS.Color.neonPurple
            case .diwaniya: return DS.Color.gridDiwaniya
            case .deceased: return DS.Color.error
            case .children: return DS.Color.info
            case .photos: return DS.Color.neonBlue
            case .treeEdit: return DS.Color.accent
            case .projects: return DS.Color.neonPurple
            case .gallery: return DS.Color.gridDiwaniya
            case .stories: return DS.Color.neonCyan
            }
        }
    }

    @State private var selectedTab: RequestTab = .joinRequests
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
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "hand.draw.fill")
                            .font(DS.Font.scaled(11, weight: .medium))
                        Text(selectedTab == .joinRequests
                            ? L10n.t(
                                authVM.canRejectRequests ? "اسحب لليسار للربط • اسحب لليمين للرفض" : "اسحب لليسار للربط",
                                authVM.canRejectRequests ? "Swipe left to link • Swipe right to reject" : "Swipe left to link"
                            )
                            : L10n.t(
                                authVM.canRejectRequests ? "اسحب لليسار للموافقة • اسحب لليمين للرفض" : "اسحب لليسار للموافقة",
                                authVM.canRejectRequests ? "Swipe left to approve • Swipe right to reject" : "Swipe left to approve"
                            )
                        )
                            .font(DS.Font.caption2)
                    }
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.top, DS.Spacing.xs)

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
            if itemCount(for: selectedTab) > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(DS.Anim.snappy) {
                            isSelectMode.toggle()
                            if !isSelectMode { selectedIds.removeAll() }
                        }
                    } label: {
                        Text(isSelectMode
                            ? L10n.t("إلغاء", "Cancel")
                            : L10n.t("تحديد", "Select")
                        )
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.primary)
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
                group.addTask { @MainActor in await adminRequestVM.fetchTreeEditRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchNameChangeRequests() }
                group.addTask { @MainActor in await projectsVM.fetchPendingProjects() }
                group.addTask { @MainActor in await memberVM.fetchPendingGalleryPhotos() }
                group.addTask { @MainActor in await storyVM.fetchPendingStories(force: true) }
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
        .alert(L10n.t("سبب الرفض", "Rejection Reason"), isPresented: $showRejectReasonAlert) {
            TextField(L10n.t("اختياري...", "Optional..."), text: $rejectReasonText)
            Button(L10n.t("رفض", "Reject"), role: .destructive) {
                if let req = treeEditToReject {
                    Task { await adminRequestVM.rejectTreeEditRequest(request: req, reason: rejectReasonText.isEmpty ? nil : rejectReasonText) }
                    treeEditToReject = nil
                    rejectReasonText = ""
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {
                treeEditToReject = nil
                rejectReasonText = ""
            }
        } message: {
            Text(L10n.t("أدخل سبب الرفض (اختياري)", "Enter rejection reason (optional)"))
        }
    }

    // MARK: - Item Count

    private func itemCount(for tab: RequestTab) -> Int {
        switch tab {
        case .joinRequests: return pendingMembers.count
        case .news: return newsVM.pendingNewsRequests.count
        case .reports: return adminRequestVM.newsReportRequests.count
        case .phone: return adminRequestVM.phoneChangeRequests.count
        case .nameChange: return adminRequestVM.nameChangeRequests.count
        case .diwaniya: return diwaniyaVM.pendingDiwaniyas.count
        case .deceased: return adminRequestVM.deceasedRequests.count
        case .children: return adminRequestVM.childAddRequests.count
        case .photos: return adminRequestVM.photoSuggestionRequests.count
        case .treeEdit: return adminRequestVM.treeEditRequests.count
        case .projects: return projectsVM.pendingProjects.count
        case .gallery: return memberVM.pendingGalleryPhotos.count
        case .stories: return storyVM.pendingStories.count
        }
    }

    @State private var cachedTotalCount: Int = 0
    @State private var cachedAvailableTabs: [RequestTab] = RequestTab.allCases

    private var totalCount: Int { cachedTotalCount }
    private var availableTabs: [RequestTab] { cachedAvailableTabs }

    private func recalculateCounts() {
        cachedPendingMembers = memberVM.allMembers.filter { $0.role == .pending }
        cachedTotalCount = RequestTab.allCases.reduce(0) { $0 + itemCount(for: $1) }
        cachedAvailableTabs = RequestTab.allCases.filter { itemCount(for: $0) > 0 }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(availableTabs) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
        .padding(.vertical, DS.Spacing.xs)
        .onChange(of: totalCount) { _ in
            // إذا التاب المحدد صار فارغ، انقل لأول تاب متاح
            if itemCount(for: selectedTab) == 0, let first = availableTabs.first {
                withAnimation(DS.Anim.snappy) { selectedTab = first }
            }
        }
    }

    private func tabButton(for tab: RequestTab) -> some View {
        let isSelected = selectedTab == tab
        let count = itemCount(for: tab)

        return Button {
            withAnimation(DS.Anim.snappy) { selectedTab = tab }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: tab.icon)
                    .font(DS.Font.scaled(11, weight: .semibold))

                Text(tab.title)
                    .font(DS.Font.caption1)
                    .fontWeight(.semibold)

                if count > 0 {
                    Text("\(count)")
                        .font(DS.Font.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(isSelected ? tab.color : DS.Color.textOnPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.28) : tab.color)
                        )
                }
            }
            .foregroundColor(isSelected ? DS.Color.textOnPrimary : tab.color)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                Capsule()
                    .fill(isSelected ? tab.color : tab.color.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : tab.color.opacity(0.3), lineWidth: 1)
            )
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
                    selectableRow(id: member.id) {
                        selectedDetail = .join(member)
                    } content: {
                        joinRequestRow(for: member)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !isSelectMode {
                            Button { memberToLink = member } label: {
                                Label(L10n.t("ربط", "Link"), systemImage: "link.badge.plus")
                            }.tint(DS.Color.success)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !isSelectMode && authVM.canRejectRequests {
                            Button(role: .destructive) {
                                Task { await adminRequestVM.rejectOrDeleteMember(memberId: member.id) }
                            } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
            case .news:
                selectAllButton(ids: newsVM.pendingNewsRequests.map { $0.id })
                ForEach(newsVM.pendingNewsRequests) { post in
                    selectableRow(id: post.id) {
                        selectedDetail = .news(post)
                    } content: {
                        newsRow(for: post)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !isSelectMode {
                            Button { Task { await newsVM.approveNewsPost(postId: post.id) } } label: {
                                Label(L10n.t("اعتماد", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !isSelectMode && authVM.canRejectRequests {
                            Button(role: .destructive) { Task { await newsVM.rejectNewsPost(postId: post.id) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
            case .reports:
                selectAllButton(ids: adminRequestVM.newsReportRequests.map { $0.id })
                ForEach(adminRequestVM.newsReportRequests) { request in
                    selectableRow(id: request.id) {
                        selectedDetail = .report(request)
                    } content: {
                        reportRow(for: request)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !isSelectMode {
                            Button { Task { await adminRequestVM.approveNewsReport(request: request) } } label: {
                                Label(L10n.t("اعتماد", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !isSelectMode && authVM.canRejectRequests {
                            Button(role: .destructive) { Task { await adminRequestVM.rejectNewsReport(request: request) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
            case .phone:
                selectAllButton(ids: adminRequestVM.phoneChangeRequests.map { $0.id })
                ForEach(adminRequestVM.phoneChangeRequests) { request in
                    selectableRow(id: request.id) {
                        selectedDetail = .phone(request)
                    } content: {
                        phoneRow(for: request)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !isSelectMode {
                            Button { Task { await adminRequestVM.approvePhoneChangeRequest(request: request) } } label: {
                                Label(L10n.t("اعتماد", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                            Button {
                                editedPhone = request.newValue ?? ""
                                phoneEditRequest = request
                            } label: {
                                Label(L10n.t("تعديل", "Edit"), systemImage: "pencil.circle.fill")
                            }.tint(DS.Color.primary)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !isSelectMode && authVM.canRejectRequests {
                            Button(role: .destructive) { Task { await adminRequestVM.rejectPhoneChangeRequest(request: request) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
                .sheet(item: $phoneEditRequest) { request in
                    adminPhoneEditSheet(request: request)
                }
            case .nameChange:
                selectAllButton(ids: adminRequestVM.nameChangeRequests.map { $0.id })
                ForEach(adminRequestVM.nameChangeRequests) { request in
                    selectableRow(id: request.id) {
                        selectedDetail = .nameChange(request)
                    } content: {
                        nameChangeRow(for: request)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !isSelectMode {
                            Button { Task { await adminRequestVM.approveNameChangeRequest(request: request) } } label: {
                                Label(L10n.t("موافقة", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                            Button {
                                editedName = request.newValue ?? ""
                                nameEditRequest = request
                            } label: {
                                Label(L10n.t("تعديل", "Edit"), systemImage: "pencil.circle.fill")
                            }.tint(DS.Color.primary)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !isSelectMode && authVM.canRejectRequests {
                            Button(role: .destructive) { Task { await adminRequestVM.rejectNameChangeRequest(request: request) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
                .sheet(item: $nameEditRequest) { request in
                    adminNameEditSheet(request: request)
                }
            case .diwaniya:
                selectAllButton(ids: diwaniyaVM.pendingDiwaniyas.map { $0.id })
                ForEach(diwaniyaVM.pendingDiwaniyas) { diwaniya in
                    selectableRow(id: diwaniya.id) {
                        selectedDetail = .diwaniya(diwaniya)
                    } content: {
                        diwaniyaRow(for: diwaniya)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !isSelectMode {
                            Button {
                                if let adminId = authVM.currentUser?.id {
                                    Task { await diwaniyaVM.approveDiwaniya(id: diwaniya.id, adminId: adminId) }
                                }
                            } label: {
                                Label(L10n.t("اعتماد", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !isSelectMode && authVM.canRejectRequests {
                            Button(role: .destructive) { Task { await diwaniyaVM.rejectDiwaniya(id: diwaniya.id) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
            case .deceased:
                selectAllButton(ids: adminRequestVM.deceasedRequests.map { $0.id })
                ForEach(adminRequestVM.deceasedRequests) { request in
                    selectableRow(id: request.id) {
                        selectedDetail = .deceased(request)
                    } content: {
                        deceasedRow(for: request)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !isSelectMode {
                            Button { Task { await adminRequestVM.approveDeceasedRequest(request: request) } } label: {
                                Label(L10n.t("موافقة", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !isSelectMode && authVM.canRejectRequests {
                            Button(role: .destructive) { Task { await adminRequestVM.rejectDeceasedRequest(request: request) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
            case .children:
                selectAllButton(ids: adminRequestVM.childAddRequests.map { $0.id })
                ForEach(adminRequestVM.childAddRequests) { request in
                    selectableRow(id: request.id) {
                        selectedDetail = .child(request)
                    } content: {
                        childRow(for: request)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !isSelectMode {
                            Button { Task { await adminRequestVM.acknowledgeChildAddRequest(request: request) } } label: {
                                Label(L10n.t("تأكيد", "Confirm"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !isSelectMode && authVM.canRejectRequests {
                            Button(role: .destructive) { Task { await adminRequestVM.rejectChildAddRequest(request: request) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
            case .photos:
                selectAllButton(ids: adminRequestVM.photoSuggestionRequests.map { $0.id })
                ForEach(adminRequestVM.photoSuggestionRequests) { request in
                    selectableRow(id: request.id) {
                        selectedDetail = .photo(request)
                    } content: {
                        photoRow(for: request)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !isSelectMode {
                            Button { Task { await adminRequestVM.approvePhotoSuggestion(request: request) } } label: {
                                Label(L10n.t("موافقة", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !isSelectMode && authVM.canRejectRequests {
                            Button(role: .destructive) { Task { await adminRequestVM.rejectPhotoSuggestion(request: request) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
            case .treeEdit:
                selectAllButton(ids: adminRequestVM.treeEditRequests.compactMap { req -> UUID? in
                    let action = req.treeEditPayload?.action ?? ""
                    if authVM.isAdmin { return req.id }
                    if authVM.currentUser?.role == .monitor && (action == "تعديل اسم" || action == "حذف") { return req.id }
                    if authVM.currentUser?.role == .supervisor && action == "إضافة" { return req.id }
                    return nil
                })
                ForEach(adminRequestVM.treeEditRequests) { request in
                    let action = request.treeEditPayload?.action ?? ""
                    let canApproveThis: Bool = {
                        if authVM.isAdmin { return true }
                        if authVM.currentUser?.role == .monitor { return action == "تعديل اسم" || action == "حذف" }
                        if authVM.currentUser?.role == .supervisor { return action == "إضافة" }
                        return false
                    }()
                    if canApproveThis {
                        selectableRow(id: request.id) {
                            selectedDetail = .treeEdit(request)
                        } content: {
                            treeEditRow(for: request)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !isSelectMode {
                                Button { Task { await adminRequestVM.approveTreeEditRequest(request: request) } } label: {
                                    Label(L10n.t("موافقة", "Approve"), systemImage: "checkmark.circle.fill")
                                }.tint(DS.Color.success)
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if !isSelectMode && authVM.canRejectRequests {
                                Button(role: .destructive) {
                                    treeEditToReject = request
                                    rejectReasonText = ""
                                    showRejectReasonAlert = true
                                } label: {
                                    Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                                }
                            }
                        }
                    }
                }
            case .projects:
                selectAllButton(ids: projectsVM.pendingProjects.map { $0.id })
                ForEach(projectsVM.pendingProjects) { project in
                    selectableRow(id: project.id) {
                        selectedDetail = .project(project)
                    } content: {
                        projectRow(for: project)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !isSelectMode {
                            Button {
                                if let adminId = authVM.currentUser?.id {
                                    Task { await projectsVM.approveProject(id: project.id, approvedBy: adminId) }
                                }
                            } label: {
                                Label(L10n.t("اعتماد", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !isSelectMode && authVM.canRejectRequests {
                            Button(role: .destructive) {
                                Task { await projectsVM.rejectProject(id: project.id) }
                            } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
            case .gallery:
                selectAllButton(ids: memberVM.pendingGalleryPhotos.map { $0.id })
                ForEach(memberVM.pendingGalleryPhotos) { photo in
                    selectableRow(id: photo.id) {
                        // no detail sheet for gallery
                    } content: {
                        galleryPendingRow(photo: photo)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !isSelectMode {
                            Button {
                                Task { await memberVM.approveGalleryPhoto(photoId: photo.id) }
                            } label: {
                                Label(L10n.t("موافقة", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !isSelectMode && authVM.canRejectRequests {
                            Button(role: .destructive) {
                                Task { await memberVM.rejectGalleryPhoto(photoId: photo.id, photoURL: photo.photoURL) }
                            } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
            case .stories:
                selectAllButton(ids: storyVM.pendingStories.map { $0.id })
                ForEach(storyVM.pendingStories) { story in
                    selectableRow(id: story.id) {
                        // no detail sheet for stories
                    } content: {
                        storyPendingRow(story: story)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !isSelectMode {
                            Button {
                                Task { await storyVM.approveStory(story) }
                            } label: {
                                Label(L10n.t("نشر", "Publish"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !isSelectMode && authVM.canRejectRequests {
                            Button(role: .destructive) {
                                Task { await storyVM.rejectStory(story) }
                            } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
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
        if isSelectMode && ids.count > 1 {
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

    private func selectableRow<Content: View>(
        id: UUID,
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
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
            HStack(spacing: DS.Spacing.sm) {
                if isSelectMode {
                    Image(systemName: selectedIds.contains(id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(selectedIds.contains(id) ? DS.Color.primary : DS.Color.textTertiary)
                        .transition(.scale.combined(with: .opacity))
                }
                content()
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isSelectMode && selectedIds.contains(id) ? DS.Color.primary.opacity(0.06) : Color.clear
        )
    }

    private func bulkApproveSelected() async -> Int {
        let ids = Array(selectedIds)
        var count = 0
        switch selectedTab {
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
        case .treeEdit:
            for id in ids {
                if let req = adminRequestVM.treeEditRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.approveTreeEditRequest(request: req)
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
        case .stories:
            for id in ids {
                if let story = storyVM.pendingStories.first(where: { $0.id == id }) {
                    await storyVM.approveStory(story)
                    count += 1
                }
            }
        }
        return count
    }

    private func bulkRejectSelected() async -> Int {
        let ids = Array(selectedIds)
        var count = 0
        switch selectedTab {
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
        case .treeEdit:
            for id in ids {
                if let req = adminRequestVM.treeEditRequests.first(where: { $0.id == id }) {
                    await adminRequestVM.rejectTreeEditRequest(request: req, reason: nil)
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
        case .stories:
            for id in ids {
                if let story = storyVM.pendingStories.first(where: { $0.id == id }) {
                    await storyVM.rejectStory(story)
                    count += 1
                }
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
    private func fetchAllRegistrationMatches() async {
        for member in pendingMembers {
            let ids = await adminRequestVM.fetchMatchedMemberIds(for: member.id)
            if !ids.isEmpty {
                await MainActor.run {
                    registrationMatches[member.id] = ids
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

                Image(systemName: L10n.isArabic ? "arrow.right" : "arrow.left")
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
                Image(systemName: "arrow.right")
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

    private func treeEditRow(for request: AdminRequest) -> some View {
        let actionType = request.newValue ?? L10n.t("تعديل", "Edit")
        let payload = request.treeEditPayload

        // Action-specific icon & color
        let rowIcon: String
        let rowColor: Color
        switch actionType {
        case "إضافة":
            rowIcon = "person.badge.plus"
            rowColor = DS.Color.success
        case "حذف":
            rowIcon = "person.badge.minus"
            rowColor = DS.Color.error
        default:
            rowIcon = "pencil.line"
            rowColor = DS.Color.info
        }

        // Display name: target member or new member name
        let displayName = payload?.targetMemberName ?? payload?.newMemberName ?? request.member?.fullName ?? L10n.t("عضو", "Member")

        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: rowIcon, color: rowColor, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)

                    // Show requester name
                    if let requesterName = memberVM.allMembers.first(where: { $0.id == request.requesterId })?.fullName {
                        Text(L10n.t("من: \(requesterName)", "By: \(requesterName)"))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                }

                Spacer()

                typeBadge(text: actionType, color: rowColor)
            }

            // Action-specific summary
            if let payload = payload {
                Group {
                    switch payload.action {
                    case "تعديل اسم":
                        if let newName = payload.newName, !newName.isEmpty {
                            contentBlock(L10n.t("← \(newName)", "→ \(newName)"))
                        }
                    case "إضافة":
                        if let parent = payload.parentMemberName, let child = payload.newMemberName {
                            contentBlock(L10n.t("إضافة \(child) تحت \(parent)", "Add \(child) under \(parent)"))
                        }
                    case "حذف":
                        if let reason = payload.reason, !reason.isEmpty {
                            contentBlock(reason)
                        }
                    default:
                        EmptyView()
                    }
                }
            } else if let details = request.details, !details.isEmpty {
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
    private func requestDetailSheet(_ detail: RequestDetail) -> some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    switch detail {
                    case .join(let member):
                        detailHeader(icon: "person.badge.shield.checkmark", color: DS.Color.info, title: L10n.t("طلب انضمام", "Join Request"))
                        detailField(L10n.t("الاسم الكامل", "Full Name"), member.fullName)
                        if let phone = member.phoneNumber, !phone.isEmpty {
                            detailField(L10n.t("رقم الهاتف", "Phone"), KuwaitPhone.display(phone))
                        }
                        if let date = member.createdAt {
                            detailField(L10n.t("تاريخ التسجيل", "Registered"), formatRegistrationDate(date))
                        }

                    case .news(let post):
                        detailHeader(icon: "newspaper.fill", color: DS.Color.warning, title: L10n.t("خبر بانتظار الاعتماد", "Pending News"))
                        detailField(L10n.t("الكاتب", "Author"), post.author_name)
                        detailField(L10n.t("النوع", "Type"), post.type)
                        detailField(L10n.t("التاريخ", "Date"), formatRegistrationDate(String(post.created_at)))
                        detailFullText(L10n.t("المحتوى", "Content"), post.content)
                        if !post.mediaURLs.isEmpty {
                            newsMediaGrid(urls: post.mediaURLs)
                        }

                    case .report(let request):
                        detailHeader(icon: "exclamationmark.triangle.fill", color: DS.Color.error, title: L10n.t("بلاغ", "Report"))
                        detailField(L10n.t("مقدم البلاغ", "Reporter"), request.member?.fullName ?? "—")
                        detailField(L10n.t("التاريخ", "Date"), request.createdAt.map { formatRegistrationDate($0) } ?? "—")
                        detailFullText(L10n.t("التفاصيل", "Details"), request.details ?? L10n.t("لا توجد تفاصيل", "No details"))

                    case .phone(let request):
                        detailHeader(icon: "phone.arrow.right", color: DS.Color.primary, title: L10n.t("طلب تغيير رقم", "Phone Change"))
                        detailField(L10n.t("العضو", "Member"), request.member?.fullName ?? "—")
                        detailField(L10n.t("الرقم الحالي", "Current"), KuwaitPhone.display(request.member?.phoneNumber))
                        detailField(L10n.t("الرقم الجديد", "New"), KuwaitPhone.display(request.newValue), color: DS.Color.success)
                        detailField(L10n.t("التاريخ", "Date"), request.createdAt.map { formatRegistrationDate($0) } ?? "—")

                    case .nameChange(let request):
                        detailHeader(icon: "rectangle.and.pencil.and.ellipsis", color: DS.Color.neonPurple, title: L10n.t("طلب تغيير اسم", "Name Change"))
                        detailField(L10n.t("الاسم الحالي", "Current Name"), request.member?.fullName ?? "—")
                        detailField(L10n.t("الاسم الجديد", "New Name"), request.newValue ?? "—", color: DS.Color.success)
                        detailField(L10n.t("التاريخ", "Date"), request.createdAt.map { formatRegistrationDate($0) } ?? "—")

                    case .diwaniya(let diwaniya):
                        detailHeader(icon: "tent.fill", color: DS.Color.gridDiwaniya, title: L10n.t("طلب ديوانية", "Diwaniya Request"))
                        detailField(L10n.t("الاسم", "Name"), diwaniya.title)
                        detailField(L10n.t("صاحب الديوانية", "Owner"), diwaniya.ownerName)
                        if let schedule = diwaniya.scheduleText, !schedule.isEmpty {
                            detailField(L10n.t("الموعد", "Schedule"), schedule)
                        }
                        if let address = diwaniya.address, !address.isEmpty {
                            detailField(L10n.t("العنوان", "Address"), address)
                        }

                    case .deceased(let request):
                        detailHeader(icon: "bolt.heart.fill", color: DS.Color.error, title: L10n.t("طلب تسجيل وفاة", "Deceased Request"))
                        detailField(L10n.t("العضو", "Member"), request.member?.fullName ?? "—")
                        detailFullText(L10n.t("التفاصيل", "Details"), request.details ?? L10n.t("لا توجد تفاصيل", "No details"))
                        detailField(L10n.t("التاريخ", "Date"), request.createdAt.map { formatRegistrationDate($0) } ?? "—")

                    case .child(let request):
                        detailHeader(icon: "person.badge.plus", color: DS.Color.info, title: L10n.t("طلب إضافة ابن", "Child Add Request"))
                        detailField(L10n.t("الأب", "Father"), request.member?.fullName ?? "—")
                        detailFullText(L10n.t("التفاصيل", "Details"), request.details ?? L10n.t("لا توجد تفاصيل", "No details"))
                        detailField(L10n.t("التاريخ", "Date"), request.createdAt.map { formatRegistrationDate($0) } ?? "—")

                    case .photo(let request):
                        detailHeader(icon: "camera.badge.ellipsis", color: DS.Color.neonBlue, title: L10n.t("طلب إضافة صورة", "Photo Suggestion"))
                        detailField(L10n.t("العضو", "Member"), request.member?.fullName ?? "—")
                        detailFullText(L10n.t("التفاصيل", "Details"), request.details ?? L10n.t("لا توجد تفاصيل", "No details"))
                        if let photoUrl = request.newValue, let url = URL(string: photoUrl) {
                            CachedAsyncImage(url: url) { img in
                                img.resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                            } placeholder: {
                                RoundedRectangle(cornerRadius: DS.Radius.md)
                                    .fill(DS.Color.surface)
                                    .frame(height: 200)
                                    .overlay(ProgressView().tint(DS.Color.primary))
                            }
                        }

                    case .treeEdit(let request):
                        detailHeader(icon: "pencil.and.list.clipboard", color: DS.Color.accent, title: L10n.t("طلب تعديل بالشجرة", "Tree Edit Request"))
                        if let action = request.newValue {
                            detailField(L10n.t("نوع التعديل", "Edit Type"), action)
                        }
                        // Requester info
                        if let requester = memberVM.allMembers.first(where: { $0.id == request.requesterId }) {
                            detailField(L10n.t("مقدم الطلب", "Requested By"), requester.fullName)
                        }

                        if let payload = request.treeEditPayload {
                            // Structured v2 display
                            switch payload.action {
                            case "تعديل اسم":
                                if let name = payload.targetMemberName {
                                    detailField(L10n.t("العضو المعني", "Target Member"), name)
                                }
                                if let newName = payload.newName {
                                    detailField(L10n.t("الاسم الجديد", "New Name"), newName)
                                }
                            case "حذف":
                                if let name = payload.targetMemberName {
                                    detailField(L10n.t("العضو المعني", "Target Member"), name)
                                }
                                if let reason = payload.reason {
                                    detailFullText(L10n.t("سبب الحذف", "Removal Reason"), reason)
                                }
                            case "إضافة":
                                if let parent = payload.parentMemberName {
                                    detailField(L10n.t("الأب", "Parent"), parent)
                                }
                                if let child = payload.newMemberName {
                                    detailField(L10n.t("اسم العضو الجديد", "New Member Name"), child)
                                }
                            default: EmptyView()
                            }
                            if let notes = payload.notes, !notes.isEmpty {
                                detailFullText(L10n.t("ملاحظات", "Notes"), notes)
                            }
                        } else {
                            // Fallback: old format string parsing (backward compatibility)
                            if let details = request.details {
                                let lines = details.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                                if let nameLine = lines.first(where: { $0.hasPrefix("الاسم المعني:") }) {
                                    let name = nameLine.replacingOccurrences(of: "الاسم المعني:", with: "").trimmingCharacters(in: .whitespaces)
                                    if !name.isEmpty {
                                        detailField(L10n.t("الاسم المعني", "Related Name"), name)
                                    }
                                }
                                if let detailLine = lines.first(where: { $0.hasPrefix("التفاصيل:") }) {
                                    let editDetails = detailLine.replacingOccurrences(of: "التفاصيل:", with: "").trimmingCharacters(in: .whitespaces)
                                    if !editDetails.isEmpty && editDetails != "لا توجد تفاصيل إضافية" {
                                        detailFullText(L10n.t("تفاصيل التعديل", "Edit Details"), editDetails)
                                    }
                                }
                            }
                        }
                        detailField(L10n.t("التاريخ", "Date"), request.createdAt.map { formatRegistrationDate($0) } ?? "—")

                    case .project(let project):
                        detailHeader(icon: "briefcase.fill", color: DS.Color.neonPurple, title: L10n.t("طلب مشروع", "Project Request"))
                        detailField(L10n.t("اسم المشروع", "Project Name"), project.title)
                        detailField(L10n.t("صاحب المشروع", "Owner"), project.ownerName)
                        if let desc = project.description, !desc.isEmpty {
                            detailFullText(L10n.t("الوصف", "Description"), desc)
                        }
                        if let date = project.createdAt {
                            detailField(L10n.t("التاريخ", "Date"), formatRegistrationDate(date))
                        }
                    }

                    // أزرار الموافقة والرفض
                    detailActions(for: detail)
                }
                .padding(DS.Spacing.lg)
            }
            .background(DS.Color.background)
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
                case .treeEdit(let request):
                    await adminRequestVM.approveTreeEditRequest(request: request)
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
                case .treeEdit(let request):
                    rejectReasonText = ""
                    treeEditToReject = request
                    showRejectReasonAlert = true
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
