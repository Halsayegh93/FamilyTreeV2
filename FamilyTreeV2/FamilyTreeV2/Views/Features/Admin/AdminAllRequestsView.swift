import SwiftUI

struct AdminAllRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @StateObject private var diwaniyaVM = DiwaniyasViewModel()

    enum RequestTab: String, CaseIterable, Identifiable {
        case joinRequests, news, reports, phone, diwaniya, deceased, children, photos, treeEdit

        var id: String { rawValue }

        var title: String {
            switch self {
            case .joinRequests: return L10n.t("انضمام", "Join")
            case .news: return L10n.t("أخبار", "News")
            case .reports: return L10n.t("بلاغات", "Reports")
            case .phone: return L10n.t("جوال", "Phone")
            case .diwaniya: return L10n.t("ديوانيات", "Diwaniyas")
            case .deceased: return L10n.t("وفاة", "Deceased")
            case .children: return L10n.t("أبناء", "Children")
            case .photos: return L10n.t("صور", "Photos")
            case .treeEdit: return L10n.t("تعديل", "Edit")
            }
        }

        var icon: String {
            switch self {
            case .joinRequests: return "person.badge.shield.checkmark"
            case .news: return "newspaper.fill"
            case .reports: return "exclamationmark.bubble.fill"
            case .phone: return "phone.badge.checkmark"
            case .diwaniya: return "tent.fill"
            case .deceased: return "bolt.heart.fill"
            case .children: return "person.badge.plus"
            case .photos: return "camera.badge.ellipsis"
            case .treeEdit: return "pencil.and.list.clipboard"
            }
        }

        var color: Color {
            switch self {
            case .joinRequests: return DS.Color.info
            case .news: return DS.Color.warning
            case .reports: return DS.Color.error
            case .phone: return DS.Color.primary
            case .diwaniya: return DS.Color.gridDiwaniya
            case .deceased: return DS.Color.error
            case .children: return DS.Color.info
            case .photos: return DS.Color.neonBlue
            case .treeEdit: return DS.Color.accent
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

    private var pendingMembers: [FamilyMember] {
        memberVM.allMembers.filter { $0.role == .pending }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            VStack(spacing: 0) {
                // شريط التابات الأفقي
                tabBar
                    .padding(.top, DS.Spacing.sm)

                // المحتوى
                if itemCount(for: selectedTab) == 0 {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "hand.draw.fill")
                            .font(DS.Font.scaled(11, weight: .medium))
                        Text(selectedTab == .joinRequests
                            ? L10n.t("اسحب لليسار للربط • اسحب لليمين للرفض", "Swipe left to link • Swipe right to reject")
                            : L10n.t("اسحب لليسار للموافقة • اسحب لليمين للرفض", "Swipe left to approve • Swipe right to reject")
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
            await memberVM.fetchAllMembers()
            await newsVM.fetchPendingNewsRequests()
            await adminRequestVM.fetchNewsReportRequests()
            await adminRequestVM.fetchPhoneChangeRequests()
            await diwaniyaVM.fetchPendingDiwaniyas()
            await adminRequestVM.fetchDeceasedRequests()
            await adminRequestVM.fetchChildAddRequests()
            await adminRequestVM.fetchPhotoSuggestionRequests()
            await adminRequestVM.fetchTreeEditRequests()
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
    }

    // MARK: - Item Count

    private func itemCount(for tab: RequestTab) -> Int {
        switch tab {
        case .joinRequests: return pendingMembers.count
        case .news: return newsVM.pendingNewsRequests.count
        case .reports: return adminRequestVM.newsReportRequests.count
        case .phone: return adminRequestVM.phoneChangeRequests.count
        case .diwaniya: return diwaniyaVM.pendingDiwaniyas.count
        case .deceased: return adminRequestVM.deceasedRequests.count
        case .children: return adminRequestVM.childAddRequests.count
        case .photos: return adminRequestVM.photoSuggestionRequests.count
        case .treeEdit: return adminRequestVM.treeEditRequests.count
        }
    }

    private var totalCount: Int {
        RequestTab.allCases.reduce(0) { $0 + itemCount(for: $1) }
    }

    // MARK: - Tab Bar

    private var topRowTabs: [RequestTab] {
        [.joinRequests, .news, .reports, .phone, .diwaniya]
    }

    private var bottomRowTabs: [RequestTab] {
        [.deceased, .children, .photos, .treeEdit]
    }

    private var tabBar: some View {
        VStack(spacing: DS.Spacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(topRowTabs) { tab in
                        tabButton(for: tab)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(bottomRowTabs) { tab in
                        tabButton(for: tab)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
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
                        .foregroundColor(isSelected ? tab.color : .white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(isSelected ? DS.Color.surface : tab.color.opacity(0.6))
                        .clipShape(Circle())
                }
            }
            .foregroundColor(isSelected ? .white : DS.Color.textTertiary)
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
                    .foregroundColor(.white)
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
                    joinRequestRow(for: member)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                Task {
                                    // مطابقات السيرفر المخزنة + المطابقات المحلية
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
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await adminRequestVM.rejectOrDeleteMember(memberId: member.id) }
                            } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                }
            case .news:
                ForEach(newsVM.pendingNewsRequests) { post in
                    newsRow(for: post)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { Task { await newsVM.approveNewsPost(postId: post.id) } } label: {
                                Label(L10n.t("اعتماد", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(role: .destructive) { Task { await newsVM.rejectNewsPost(postId: post.id) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                }
            case .reports:
                ForEach(adminRequestVM.newsReportRequests) { request in
                    reportRow(for: request)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { Task { await adminRequestVM.approveNewsReport(request: request) } } label: {
                                Label(L10n.t("اعتماد", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(role: .destructive) { Task { await adminRequestVM.rejectNewsReport(request: request) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                }
            case .phone:
                ForEach(adminRequestVM.phoneChangeRequests) { request in
                    phoneRow(for: request)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { Task { await adminRequestVM.approvePhoneChangeRequest(request: request) } } label: {
                                Label(L10n.t("اعتماد", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(role: .destructive) { Task { await adminRequestVM.rejectPhoneChangeRequest(request: request) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                }
            case .diwaniya:
                ForEach(diwaniyaVM.pendingDiwaniyas) { diwaniya in
                    diwaniyaRow(for: diwaniya)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                if let adminId = authVM.currentUser?.id {
                                    Task { await diwaniyaVM.approveDiwaniya(id: diwaniya.id, adminId: adminId) }
                                }
                            } label: {
                                Label(L10n.t("اعتماد", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(role: .destructive) { Task { await diwaniyaVM.rejectDiwaniya(id: diwaniya.id) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                }
            case .deceased:
                ForEach(adminRequestVM.deceasedRequests) { request in
                    deceasedRow(for: request)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { Task { await adminRequestVM.approveDeceasedRequest(request: request) } } label: {
                                Label(L10n.t("موافقة", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(role: .destructive) { Task { await adminRequestVM.rejectDeceasedRequest(request: request) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                }
            case .children:
                ForEach(adminRequestVM.childAddRequests) { request in
                    childRow(for: request)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { Task { await adminRequestVM.acknowledgeChildAddRequest(request: request) } } label: {
                                Label(L10n.t("تأكيد", "Confirm"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(role: .destructive) { Task { await adminRequestVM.rejectChildAddRequest(request: request) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                }
            case .photos:
                ForEach(adminRequestVM.photoSuggestionRequests) { request in
                    photoRow(for: request)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { Task { await adminRequestVM.approvePhotoSuggestion(request: request) } } label: {
                                Label(L10n.t("موافقة", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(role: .destructive) { Task { await adminRequestVM.rejectPhotoSuggestion(request: request) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                }
            case .treeEdit:
                ForEach(adminRequestVM.treeEditRequests) { request in
                    treeEditRow(for: request)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { Task { await adminRequestVM.approveTreeEditRequest(request: request) } } label: {
                                Label(L10n.t("موافقة", "Approve"), systemImage: "checkmark.circle.fill")
                            }.tint(DS.Color.success)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(role: .destructive) { Task { await adminRequestVM.rejectTreeEditRequest(request: request) } } label: {
                                Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
                                .foregroundColor(DS.Color.success)
                            Text(L10n.t("اسم خماسي مكتمل", "Full 5-part name"))
                                .font(DS.Font.scaled(10))
                                .foregroundColor(DS.Color.success)
                        }
                    }

                    Text(L10n.t("سجل في: \(member.createdAt?.prefix(10) ?? "—")", "Registered: \(member.createdAt?.prefix(10) ?? "—")"))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textSecondary)
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

            // نتائج التطابق
            if hasMatches {
                VStack(spacing: DS.Spacing.sm) {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "person.2.fill")
                            .font(DS.Font.scaled(13, weight: .semibold))
                            .foregroundColor(DS.Color.info)
                        Text(L10n.t(
                            "تطابق محتمل مع \(matches.count) عضو",
                            "Potential match with \(matches.count) member(s)"
                        ))
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.info)
                        Spacer()
                    }

                    ForEach(matches.prefix(3), id: \.member.id) { match in
                        joinMatchRow(match: match, pendingMember: member)
                    }
                }
                .padding(DS.Spacing.sm)
                .background(DS.Color.info.opacity(0.04))
                .cornerRadius(DS.Radius.md)
            } else {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DS.Font.scaled(12, weight: .semibold))
                        .foregroundColor(DS.Color.success)
                    Text(L10n.t("لا يوجد تطابق — اسم جديد", "No tree matches — new name"))
                        .font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(DS.Color.success)
                    Spacer()
                }
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xs)
                .background(DS.Color.success.opacity(0.06))
                .cornerRadius(DS.Radius.sm)
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
                            .foregroundColor(.white)
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
                .padding(.vertical, 4)
                .background(DS.Color.gradientPrimary)
                .clipShape(Capsule())
            }
            .buttonStyle(DSScaleButtonStyle())
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

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author_name)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                    Text(post.created_at.prefix(10))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }

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
        }
    }

    // MARK: - Report Row

    private func reportRow(for request: AdminRequest) -> some View {
        let postId = UUID(uuidString: request.newValue ?? "")
        let reportedPost = postId.flatMap { id in newsVM.allNews.first { $0.id == id } }

        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "exclamationmark.triangle.fill", color: DS.Color.error, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(request.member?.fullName ?? L10n.t("عضو", "Member"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(request.createdAt?.prefix(10) ?? "—")
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textSecondary)
                }

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
                    Text((request.createdAt ?? "").prefix(10))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textSecondary)
                }

                Spacer()
            }

            HStack(spacing: DS.Spacing.md) {
                VStack(spacing: 2) {
                    Text(L10n.t("الجديد", "New"))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.success)
                    Text(newPhone)
                        .font(DS.Font.caption1)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.success)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.success.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

                Image(systemName: "arrow.left")
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
                        .font(DS.Font.caption2)
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

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(request.member?.fullName ?? L10n.t("عضو", "Member"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(request.details ?? L10n.t("لا توجد تفاصيل", "No details"))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }

    // MARK: - Child Row

    private func childRow(for request: AdminRequest) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "person.badge.plus", color: DS.Color.info, size: 36)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(request.member?.fullName ?? L10n.t("عضو", "Member"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(request.details ?? L10n.t("لا توجد تفاصيل", "No details"))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                    if let createdAt = request.createdAt {
                        Text(createdAt.prefix(10))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Photo Row

    private func photoRow(for request: AdminRequest) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "camera.badge.ellipsis", color: DS.Color.neonBlue, size: 36)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(request.member?.fullName ?? L10n.t("عضو", "Member"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(request.details ?? L10n.t("لا توجد تفاصيل", "No details"))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
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
        }
    }

    // MARK: - Tree Edit Row

    private func treeEditRow(for request: AdminRequest) -> some View {
        let actionType = request.newValue ?? L10n.t("تعديل", "Edit")

        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                iconCircle(icon: "pencil.and.list.clipboard", color: DS.Color.accent, size: 36)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(request.member?.fullName ?? L10n.t("عضو", "Member"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                    if let createdAt = request.createdAt {
                        Text(createdAt.prefix(10))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                }

                Spacer()

                typeBadge(text: actionType, color: DS.Color.accent)
            }

            if let details = request.details, !details.isEmpty {
                Text(details)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
