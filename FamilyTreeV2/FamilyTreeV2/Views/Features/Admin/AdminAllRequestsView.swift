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
            case .photos: return L10n.t("صور", "Photos")
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

    // Join request states
    @State private var selectedMemberForLinking: FamilyMember?
    @State private var matchedIdsForSelected: [UUID] = []
    @State private var mergeTarget: (pendingMember: FamilyMember, treeMember: FamilyMember)? = nil
    @State private var showMergeConfirm = false
    @State private var showMergeSuccess = false
    @State private var mergeSuccessMessage = ""
    /// مطابقات التسجيل من السيرفر (matched_ids من admin_requests)
    @State private var registrationMatches: [UUID: [UUID]] = [:]
    /// الأعضاء اللي المدير فتح كل المتطابقين حقهم
    @State private var expandedMatchMembers: Set<UUID> = []

    private var pendingMembers: [FamilyMember] {
        memberVM.allMembers.filter { $0.role == .pending }
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
        }
        .navigationTitle(L10n.t("طلبات المراجعة", "Review Requests"))
        .navigationBarTitleDisplayMode(.inline)
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

            // اختيار أول تاب فيه طلبات
            if let firstWithItems = RequestTab.allCases.first(where: { itemCount(for: $0) > 0 }) {
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
        .sheet(item: $selectedDetail) { detail in
            requestDetailSheet(detail)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedMemberForLinking) { member in
            FatherLinkApprovalSheet(member: member, suggestedMatchIds: matchedIdsForSelected)
                .environmentObject(authVM)
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

    private var totalCount: Int {
        RequestTab.allCases.reduce(0) { $0 + itemCount(for: $1) }
    }

    // MARK: - Tab Bar

    private var availableTabs: [RequestTab] {
        RequestTab.allCases.filter { itemCount(for: $0) > 0 }
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
        .onChange(of: totalCount) { _, _ in
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
                    .font(DS.Font.scaled(11, weight: .medium))

                Text(tab.title)
                    .font(DS.Font.caption1)
                    .fontWeight(.semibold)

                if count > 0 {
                    Text("\(count)")
                        .font(DS.Font.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(isSelected ? tab.color : DS.Color.textOnPrimary)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(isSelected ? DS.Color.surface : tab.color.opacity(0.6))
                        .clipShape(Circle())
                }
            }
            .foregroundColor(isSelected ? DS.Color.textOnPrimary : DS.Color.textTertiary)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                Capsule()
                    .fill(isSelected ? tab.color.opacity(0.85) : DS.Color.surface.opacity(0.6))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : DS.Color.textTertiary.opacity(0.12), lineWidth: 0.5)
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
                ForEach(pendingMembers) { member in
                    Button { selectedDetail = .join(member) } label: {
                        joinRequestRow(for: member)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            Task {
                                let serverIds = registrationMatches[member.id] ?? []
                                let localIds = findNameMatches(for: member).map(\.member.id)
                                let combined = Array(Set(serverIds + localIds))
                                await MainActor.run {
                                    matchedIdsForSelected = combined
                                    selectedMemberForLinking = member
                                }
                            }
                        } label: {
                            Label(L10n.t("ربط", "Link"), systemImage: "link.badge.plus")
                        }.tint(DS.Color.success)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if authVM.canRejectRequests {
                            Button(role: .destructive) {
                                Task { await adminRequestVM.rejectOrDeleteMember(memberId: member.id) }
                            } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
            case .news:
                ForEach(newsVM.pendingNewsRequests) { post in
                    Button { selectedDetail = .news(post) } label: {
                        newsRow(for: post)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button { Task { await newsVM.approveNewsPost(postId: post.id) } } label: {
                            Label(L10n.t("اعتماد", "Approve"), systemImage: "checkmark.circle.fill")
                        }.tint(DS.Color.success)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if authVM.canRejectRequests {
                            Button(role: .destructive) { Task { await newsVM.rejectNewsPost(postId: post.id) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
            case .reports:
                ForEach(adminRequestVM.newsReportRequests) { request in
                    Button { selectedDetail = .report(request) } label: {
                        reportRow(for: request)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button { Task { await adminRequestVM.approveNewsReport(request: request) } } label: {
                            Label(L10n.t("اعتماد", "Approve"), systemImage: "checkmark.circle.fill")
                        }.tint(DS.Color.success)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if authVM.canRejectRequests {
                            Button(role: .destructive) { Task { await adminRequestVM.rejectNewsReport(request: request) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
            case .phone:
                ForEach(adminRequestVM.phoneChangeRequests) { request in
                    Button { selectedDetail = .phone(request) } label: {
                        phoneRow(for: request)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
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
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if authVM.canRejectRequests {
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
                ForEach(adminRequestVM.nameChangeRequests) { request in
                    Button { selectedDetail = .nameChange(request) } label: {
                        nameChangeRow(for: request)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
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
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if authVM.canRejectRequests {
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
                ForEach(diwaniyaVM.pendingDiwaniyas) { diwaniya in
                    Button { selectedDetail = .diwaniya(diwaniya) } label: {
                        diwaniyaRow(for: diwaniya)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            if let adminId = authVM.currentUser?.id {
                                Task { await diwaniyaVM.approveDiwaniya(id: diwaniya.id, adminId: adminId) }
                            }
                        } label: {
                            Label(L10n.t("اعتماد", "Approve"), systemImage: "checkmark.circle.fill")
                        }.tint(DS.Color.success)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if authVM.canRejectRequests {
                            Button(role: .destructive) { Task { await diwaniyaVM.rejectDiwaniya(id: diwaniya.id) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
            case .deceased:
                ForEach(adminRequestVM.deceasedRequests) { request in
                    Button { selectedDetail = .deceased(request) } label: {
                        deceasedRow(for: request)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button { Task { await adminRequestVM.approveDeceasedRequest(request: request) } } label: {
                            Label(L10n.t("موافقة", "Approve"), systemImage: "checkmark.circle.fill")
                        }.tint(DS.Color.success)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if authVM.canRejectRequests {
                            Button(role: .destructive) { Task { await adminRequestVM.rejectDeceasedRequest(request: request) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
            case .children:
                ForEach(adminRequestVM.childAddRequests) { request in
                    Button { selectedDetail = .child(request) } label: {
                        childRow(for: request)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button { Task { await adminRequestVM.acknowledgeChildAddRequest(request: request) } } label: {
                            Label(L10n.t("تأكيد", "Confirm"), systemImage: "checkmark.circle.fill")
                        }.tint(DS.Color.success)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if authVM.canRejectRequests {
                            Button(role: .destructive) { Task { await adminRequestVM.rejectChildAddRequest(request: request) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
            case .photos:
                ForEach(adminRequestVM.photoSuggestionRequests) { request in
                    Button { selectedDetail = .photo(request) } label: {
                        photoRow(for: request)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button { Task { await adminRequestVM.approvePhotoSuggestion(request: request) } } label: {
                            Label(L10n.t("موافقة", "Approve"), systemImage: "checkmark.circle.fill")
                        }.tint(DS.Color.success)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if authVM.canRejectRequests {
                            Button(role: .destructive) { Task { await adminRequestVM.rejectPhotoSuggestion(request: request) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
            case .treeEdit:
                ForEach(adminRequestVM.treeEditRequests) { request in
                    let action = request.treeEditPayload?.action ?? ""
                    // المراقب: تعديل اسم + حذف — المشرف: إضافة فقط — المدير: الكل
                    let canApproveThis: Bool = {
                        if authVM.isAdmin { return true }
                        if authVM.currentUser?.role == .monitor {
                            return action == "تعديل اسم" || action == "حذف"
                        }
                        if authVM.currentUser?.role == .supervisor {
                            return action == "إضافة"
                        }
                        return false
                    }()

                    if canApproveThis {
                        Button { selectedDetail = .treeEdit(request) } label: {
                            treeEditRow(for: request)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button { Task { await adminRequestVM.approveTreeEditRequest(request: request) } } label: {
                                Label(L10n.t("موافقة", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if authVM.canRejectRequests {
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
                ForEach(projectsVM.pendingProjects) { project in
                    Button { selectedDetail = .project(project) } label: {
                        projectRow(for: project)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            if let adminId = authVM.currentUser?.id {
                                Task { await projectsVM.approveProject(id: project.id, approvedBy: adminId) }
                            }
                        } label: {
                            Label(L10n.t("اعتماد", "Approve"), systemImage: "checkmark.circle.fill")
                        }.tint(DS.Color.success)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if authVM.canRejectRequests {
                            Button(role: .destructive) {
                                Task { await projectsVM.rejectProject(id: project.id) }
                            } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                }
            case .gallery:
                ForEach(memberVM.pendingGalleryPhotos) { photo in
                    galleryPendingRow(photo: photo)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                Task { await memberVM.approveGalleryPhoto(photoId: photo.id) }
                            } label: {
                                Label(L10n.t("موافقة", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if authVM.canRejectRequests {
                                Button(role: .destructive) {
                                    Task { await memberVM.rejectGalleryPhoto(photoId: photo.id, photoURL: photo.photoURL) }
                                } label: {
                                    Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                                }
                            }
                        }
                }
            case .stories:
                ForEach(storyVM.pendingStories) { story in
                    storyPendingRow(story: story)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                Task { await storyVM.approveStory(story) }
                            } label: {
                                Label(L10n.t("نشر", "Publish"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if authVM.canRejectRequests {
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(DS.Color.success.opacity(0.08))
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(DS.Color.success.opacity(0.12))
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 60, height: 60)
                Image(systemName: "checkmark.circle.fill")
                    .font(DS.Font.scaled(26, weight: .semibold))
                    .foregroundColor(DS.Color.textOnPrimary)
            }
            Text(L10n.t("لا توجد طلبات معلقة", "No pending requests"))
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.textSecondary)
        }
    }

    // MARK: - Join Request Row

    private func joinRequestRow(for member: FamilyMember) -> some View {
        let matches = combinedMatches(for: member)
        let hasMatches = !matches.isEmpty
        let serverMatchCount = registrationMatches[member.id]?.count ?? 0

        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "person.badge.shield.checkmark", color: hasMatches ? DS.Color.success : DS.Color.warning, size: 36)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(member.fullName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)

                    let parts = member.fullName.split(whereSeparator: \.isWhitespace)
                    if parts.count >= 5 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(DS.Font.scaled(10))
                                .foregroundColor(DS.Color.textPrimary)
                            Text(L10n.t("اسم خماسي مكتمل", "Full 5-part name"))
                                .font(DS.Font.scaled(10))
                                .foregroundColor(DS.Color.textPrimary)
                        }
                    }
                }

                Spacer()

                // بادج مطابقات التسجيل
                if serverMatchCount > 0 {
                    VStack(spacing: 2) {
                        Text("\(serverMatchCount)")
                            .font(DS.Font.scaled(14, weight: .black))
                            .foregroundColor(DS.Color.textSecondary)
                        Text(L10n.t("مطابقة", "match"))
                            .font(DS.Font.scaled(8, weight: .bold))
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(DS.Color.info.opacity(0.1))
                    .cornerRadius(DS.Radius.md)
                }
            }

            // نتائج التطابق
            if hasMatches {
                VStack(spacing: DS.Spacing.sm) {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "person.2.fill")
                            .font(DS.Font.scaled(13, weight: .semibold))
                            .foregroundColor(DS.Color.textSecondary)
                        Text(L10n.t(
                            "تطابق محتمل مع \(matches.count) عضو",
                            "Potential match with \(matches.count) member(s)"
                        ))
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.textSecondary)
                        Spacer()
                    }

                    let isExpanded = expandedMatchMembers.contains(member.id)
                    let visible = isExpanded ? matches : Array(matches.prefix(3))

                    ForEach(visible, id: \.member.id) { match in
                        joinMatchRow(match: match, pendingMember: member)
                    }

                    if matches.count > 3 && !isExpanded {
                        Button {
                            withAnimation(DS.Anim.snappy) {
                                _ = expandedMatchMembers.insert(member.id)
                            }
                        } label: {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: "ellipsis.circle.fill")
                                    .font(DS.Font.scaled(12, weight: .semibold))
                                Text(L10n.t(
                                    "عرض الكل (\(matches.count))",
                                    "Show all (\(matches.count))"
                                ))
                                .font(DS.Font.scaled(11, weight: .bold))
                            }
                            .foregroundColor(DS.Color.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Spacing.xs)
                        }
                        .buttonStyle(DSScaleButtonStyle())
                        .accessibilityLabel(L10n.t("عرض كل التطابقات", "Show all matches"))
                    }
                }
                .padding(DS.Spacing.sm)
                .background(DS.Color.info.opacity(0.04))
                .cornerRadius(DS.Radius.md)
            } else {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DS.Font.scaled(12, weight: .semibold))
                        .foregroundColor(DS.Color.textPrimary)
                    Text(L10n.t("لا يوجد تطابق — اسم جديد", "No tree matches — new name"))
                        .font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xs)
                .background(DS.Color.success.opacity(0.06))
                .cornerRadius(DS.Radius.sm)
            }

            // التاريخ تحت
            if let createdAt = member.createdAt {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(L10n.t("سجل في: \(createdAt.prefix(10))", "Registered: \(createdAt.prefix(10))"))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
    }

    private func joinMatchRow(match: (member: FamilyMember, matchCount: Int, matchedParts: [String], isRegistrationMatch: Bool), pendingMember: FamilyMember) -> some View {
        let totalParts = max(
            pendingMember.fullName.split(whereSeparator: \.isWhitespace).count,
            match.member.fullName.split(whereSeparator: \.isWhitespace).count
        )
        let hasNameMatch = match.matchCount >= 3
        let matchRatio = hasNameMatch ? Double(match.matchCount) / Double(max(totalParts, 1)) : 0
        let strengthColor: Color = match.isRegistrationMatch ? DS.Color.info : (matchRatio >= 0.8 ? DS.Color.success : matchRatio >= 0.6 ? DS.Color.info : DS.Color.warning)

        return HStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(strengthColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: match.isRegistrationMatch ? "link.circle.fill" : (matchRatio >= 0.8 ? "checkmark.circle.fill" : "person.fill.questionmark"))
                    .font(DS.Font.scaled(12, weight: .semibold))
                    .foregroundColor(strengthColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(match.member.fullName)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: DS.Spacing.xs) {
                    if match.isRegistrationMatch {
                        Text(L10n.t("مطابقة تسجيل", "Registration match"))
                            .font(DS.Font.scaled(9, weight: .bold))
                            .foregroundColor(DS.Color.textOnPrimary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(DS.Color.info)
                            .clipShape(Capsule())
                    }
                    if hasNameMatch {
                        Text(L10n.t(
                            "\(match.matchCount)/\(totalParts) متطابق",
                            "\(match.matchCount)/\(totalParts) match"
                        ))
                        .font(DS.Font.scaled(10, weight: .semibold))
                        .foregroundColor(strengthColor)
                    }
                }
            }

            Spacer()

            Button {
                mergeTarget = (pendingMember: pendingMember, treeMember: match.member)
                showMergeConfirm = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.merge")
                        .font(DS.Font.scaled(10, weight: .bold))
                    Text(L10n.t("دمج", "Merge"))
                        .font(DS.Font.scaled(10, weight: .bold))
                }
                .foregroundColor(DS.Color.textOnPrimary)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xs)
                .background(DS.Color.gradientPrimary)
                .clipShape(Capsule())
            }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityLabel(L10n.t("دمج مع \(match.member.fullName)", "Merge with \(match.member.fullName)"))
        }
        .padding(DS.Spacing.xs)
        .background(strengthColor.opacity(0.04))
        .cornerRadius(DS.Radius.sm)
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

        guard newParts.count >= 3 else { return [] }

        let existingMembers = memberVM.allMembers.filter { $0.role != .pending && $0.id != member.id }

        var matches: [(member: FamilyMember, matchCount: Int, matchedParts: [String])] = []

        for existing in existingMembers {
            let existingParts = existing.fullName
                .split(whereSeparator: \.isWhitespace)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

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

            if matchedParts.count >= 3 {
                matches.append((member: existing, matchCount: matchedParts.count, matchedParts: matchedParts))
            }
        }

        return matches.sorted { $0.matchCount > $1.matchCount }
    }

    // MARK: - News Row

    private func newsRow(for post: NewsPost) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                let member = post.author_id.flatMap { memberVM.member(byId: $0) }
                memberAvatar(urlStr: member?.avatarUrl, name: post.author_name)

                Text(post.author_name)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                Spacer()

                typeBadge(text: post.type, color: newsTypeColor(post.type))
            }

            Text(post.content)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textPrimary)
                .lineSpacing(3)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

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
                Text(post.created_at.prefix(10))
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

            Text(request.details ?? L10n.t("بلاغ بدون تفاصيل", "Report without details"))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

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
                Text(request.createdAt?.prefix(10) ?? "—")
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

                Text(memberName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)

                Spacer()
            }

            HStack(spacing: DS.Spacing.md) {
                VStack(spacing: 2) {
                    Text(L10n.t("الجديد", "New"))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(newPhone)
                        .font(DS.Font.caption1)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.success.opacity(0.06))
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
                    Text(createdAt.prefix(10))
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

                Text(diwaniya.title)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                Spacer()
            }

            if let schedule = diwaniya.scheduleText, !schedule.isEmpty {
                detailRow(icon: "calendar", text: schedule)
            }
            if let address = diwaniya.address, !address.isEmpty {
                detailRow(icon: "mappin.and.ellipse", text: address)
            }

            // صاحب الديوانية تحت
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "person.fill")
                    .font(DS.Font.scaled(10, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                Text(diwaniya.ownerName)
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
    }

    // MARK: - Deceased Row

    private func deceasedRow(for request: AdminRequest) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "bolt.heart.fill", color: DS.Color.error, size: 36)

                Text(request.member?.fullName ?? L10n.t("عضو", "Member"))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)

                Spacer()
            }

            if let details = request.details, !details.isEmpty {
                Text(details)
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
            }

            // التاريخ تحت
            if let createdAt = request.createdAt {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(createdAt.prefix(10))
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

                Text(request.member?.fullName ?? L10n.t("عضو", "Member"))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)

                Spacer()
            }

            if let details = request.details, !details.isEmpty {
                Text(details)
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
            }

            // التاريخ تحت
            if let createdAt = request.createdAt {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(createdAt.prefix(10))
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

                Text(request.member?.fullName ?? L10n.t("عضو", "Member"))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)

                Spacer()
            }

            if let details = request.details, !details.isEmpty {
                Text(details)
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
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
                    Text(createdAt.prefix(10))
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

        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // الصف الأول: الأيقونة + الاسم + البادج
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "rectangle.and.pencil.and.ellipsis", color: DS.Color.neonPurple, size: 30)

                Text(currentName)
                    .font(DS.Font.subheadline)
                    .foregroundColor(DS.Color.textPrimary)

                Spacer()

                typeBadge(text: L10n.t("تغيير اسم", "Name Change"), color: DS.Color.neonPurple)
            }

            // الاسم الجديد
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "arrow.right")
                    .font(DS.Font.scaled(10, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("الاسم الجديد:", "New name:"))
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textSecondary)
                Text(newName)
                    .font(DS.Font.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.textPrimary)
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.success.opacity(0.06))
            .cornerRadius(DS.Radius.sm)

            // التاريخ تحت
            if let createdAt = request.createdAt {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(createdAt.prefix(10))
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
                        .foregroundColor(DS.Color.textPrimary)
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

        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
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
                            Text(L10n.t("← \(newName)", "→ \(newName)"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                    case "إضافة":
                        if let parent = payload.parentMemberName, let child = payload.newMemberName {
                            Text(L10n.t("إضافة \(child) تحت \(parent)", "Add \(child) under \(parent)"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textPrimary)
                        }
                    case "حذف":
                        if let reason = payload.reason, !reason.isEmpty {
                            Text(reason)
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                                .lineLimit(1)
                        }
                    default:
                        EmptyView()
                    }
                }
            } else if let details = request.details, !details.isEmpty {
                // Fallback for old format
                Text(details)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // التاريخ تحت
            if let createdAt = request.createdAt {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(createdAt.prefix(10))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Project Row

    // MARK: - Gallery Pending Row
    private func galleryPendingRow(photo: MemberGalleryPhoto) -> some View {
        HStack(spacing: DS.Spacing.md) {
            AsyncImage(url: URL(string: photo.photoURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipped()
                        .cornerRadius(DS.Radius.sm)
                default:
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .fill(DS.Color.surface)
                        .frame(width: 60, height: 60)
                        .overlay(Image(systemName: "photo").foregroundColor(DS.Color.textTertiary))
                }
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                if let member = memberVM.member(byId: photo.memberId) {
                    Text(member.fullName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                }
                if let caption = photo.caption, !caption.isEmpty {
                    Text(caption)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                }
                if let date = photo.createdAt {
                    Text(String(date.prefix(10)))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }

            Spacer()

            DSPulseBadge(count: 1)
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - Story Pending Row
    private func storyPendingRow(story: FamilyStory) -> some View {
        HStack(spacing: DS.Spacing.md) {
            CachedAsyncPhaseImage(url: URL(string: story.imageUrl)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipped()
                        .cornerRadius(DS.Radius.sm)
                } else {
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .fill(DS.Color.surface)
                        .frame(width: 60, height: 60)
                        .overlay(Image(systemName: "circle.dashed").foregroundColor(DS.Color.textTertiary))
                }
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                if let member = memberVM.member(byId: story.memberId) {
                    Text(member.firstName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                }
                if let caption = story.caption, !caption.isEmpty {
                    Text(caption)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                }
                Text(String(story.createdAt.prefix(10)))
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)
            }

            Spacer()

            DSPulseBadge(count: 1)
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private func projectRow(for project: Project) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                // Logo or placeholder
                if let logoUrl = project.logoUrl, let url = URL(string: logoUrl) {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        iconCircle(icon: "briefcase.fill", color: DS.Color.neonPurple, size: 40)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    iconCircle(icon: "briefcase.fill", color: DS.Color.neonPurple, size: 40)
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
                Text(desc)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(3)
            }

            // التاريخ تحت
            if let date = project.createdAt?.prefix(10) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(L10n.t("أُضيف: \(date)", "Added: \(date)"))
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
        Group {
            if let urlStr, let url = URL(string: urlStr) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    avatarPlaceholder(name: name)
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                avatarPlaceholder(name: name)
            }
        }
    }

    private func avatarPlaceholder(name: String) -> some View {
        Circle()
            .fill(DS.Color.primary.opacity(0.15))
            .frame(width: 40, height: 40)
            .overlay(
                Text(String(name.first ?? "A"))
                    .font(DS.Font.scaled(14, weight: .bold))
                    .foregroundColor(DS.Color.primary)
            )
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
                            detailField(L10n.t("تاريخ التسجيل", "Registered"), String(date.prefix(10)))
                        }

                    case .news(let post):
                        detailHeader(icon: "newspaper.fill", color: DS.Color.warning, title: L10n.t("خبر بانتظار الاعتماد", "Pending News"))
                        detailField(L10n.t("الكاتب", "Author"), post.author_name)
                        detailField(L10n.t("النوع", "Type"), post.type)
                        detailField(L10n.t("التاريخ", "Date"), String(post.created_at.prefix(10)))
                        detailFullText(L10n.t("المحتوى", "Content"), post.content)
                        if !post.mediaURLs.isEmpty {
                            newsMediaGrid(urls: post.mediaURLs)
                        }

                    case .report(let request):
                        detailHeader(icon: "exclamationmark.triangle.fill", color: DS.Color.error, title: L10n.t("بلاغ", "Report"))
                        detailField(L10n.t("مقدم البلاغ", "Reporter"), request.member?.fullName ?? "—")
                        detailField(L10n.t("التاريخ", "Date"), String((request.createdAt ?? "—").prefix(10)))
                        detailFullText(L10n.t("التفاصيل", "Details"), request.details ?? L10n.t("لا توجد تفاصيل", "No details"))

                    case .phone(let request):
                        detailHeader(icon: "phone.arrow.right", color: DS.Color.primary, title: L10n.t("طلب تغيير رقم", "Phone Change"))
                        detailField(L10n.t("العضو", "Member"), request.member?.fullName ?? "—")
                        detailField(L10n.t("الرقم الحالي", "Current"), KuwaitPhone.display(request.member?.phoneNumber))
                        detailField(L10n.t("الرقم الجديد", "New"), KuwaitPhone.display(request.newValue), color: DS.Color.success)
                        detailField(L10n.t("التاريخ", "Date"), String((request.createdAt ?? "—").prefix(10)))

                    case .nameChange(let request):
                        detailHeader(icon: "rectangle.and.pencil.and.ellipsis", color: DS.Color.neonPurple, title: L10n.t("طلب تغيير اسم", "Name Change"), iconSize: 38)
                        detailField(L10n.t("الاسم الحالي", "Current Name"), request.member?.fullName ?? "—")
                        detailField(L10n.t("الاسم الجديد", "New Name"), request.newValue ?? "—", color: DS.Color.success)
                        detailField(L10n.t("التاريخ", "Date"), String((request.createdAt ?? "—").prefix(10)))

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
                        detailField(L10n.t("التاريخ", "Date"), String((request.createdAt ?? "—").prefix(10)))

                    case .child(let request):
                        detailHeader(icon: "person.badge.plus", color: DS.Color.info, title: L10n.t("طلب إضافة ابن", "Child Add Request"))
                        detailField(L10n.t("الأب", "Father"), request.member?.fullName ?? "—")
                        detailFullText(L10n.t("التفاصيل", "Details"), request.details ?? L10n.t("لا توجد تفاصيل", "No details"))
                        detailField(L10n.t("التاريخ", "Date"), String((request.createdAt ?? "—").prefix(10)))

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
                        detailField(L10n.t("التاريخ", "Date"), String((request.createdAt ?? "—").prefix(10)))

                    case .project(let project):
                        detailHeader(icon: "briefcase.fill", color: DS.Color.neonPurple, title: L10n.t("طلب مشروع", "Project Request"))
                        detailField(L10n.t("اسم المشروع", "Project Name"), project.title)
                        detailField(L10n.t("صاحب المشروع", "Owner"), project.ownerName)
                        if let desc = project.description, !desc.isEmpty {
                            detailFullText(L10n.t("الوصف", "Description"), desc)
                        }
                        if let date = project.createdAt {
                            detailField(L10n.t("التاريخ", "Date"), String(date.prefix(10)))
                        }
                    }
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

    private func detailHeader(icon: String, color: Color, title: String, iconSize: CGFloat = 48) -> some View {
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
