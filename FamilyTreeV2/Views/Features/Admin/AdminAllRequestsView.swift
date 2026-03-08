import SwiftUI

struct AdminAllRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @StateObject private var diwaniyaVM = DiwaniyasViewModel()

    enum RequestTab: String, CaseIterable, Identifiable {
        case news, reports, phone, diwaniya, deceased, children, photos

        var id: String { rawValue }

        var title: String {
            switch self {
            case .news: return L10n.t("أخبار", "News")
            case .reports: return L10n.t("بلاغات", "Reports")
            case .phone: return L10n.t("جوال", "Phone")
            case .diwaniya: return L10n.t("ديوانيات", "Diwaniyas")
            case .deceased: return L10n.t("وفاة", "Deceased")
            case .children: return L10n.t("أبناء", "Children")
            case .photos: return L10n.t("صور", "Photos")
            }
        }

        var icon: String {
            switch self {
            case .news: return "newspaper.fill"
            case .reports: return "exclamationmark.bubble.fill"
            case .phone: return "phone.badge.checkmark"
            case .diwaniya: return "tent.fill"
            case .deceased: return "bolt.heart.fill"
            case .children: return "person.badge.plus"
            case .photos: return "camera.badge.ellipsis"
            }
        }

        var color: Color {
            switch self {
            case .news: return DS.Color.warning
            case .reports: return DS.Color.error
            case .phone: return DS.Color.primary
            case .diwaniya: return DS.Color.gridDiwaniya
            case .deceased: return DS.Color.error
            case .children: return DS.Color.info
            case .photos: return DS.Color.neonBlue
            }
        }
    }

    @State private var selectedTab: RequestTab = .news

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
                    tabContent
                }
            }
        }
        .navigationTitle(L10n.t("طلبات المراجعة", "Review Requests"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            await newsVM.fetchPendingNewsRequests()
            await adminRequestVM.fetchNewsReportRequests()
            await adminRequestVM.fetchPhoneChangeRequests()
            await diwaniyaVM.fetchPendingDiwaniyas()
            await adminRequestVM.fetchDeceasedRequests()
            await adminRequestVM.fetchChildAddRequests()
            await adminRequestVM.fetchPhotoSuggestionRequests()

            // اختيار أول تاب فيه طلبات
            if let firstWithItems = RequestTab.allCases.first(where: { itemCount(for: $0) > 0 }) {
                selectedTab = firstWithItems
            }
        }
    }

    // MARK: - Item Count

    private func itemCount(for tab: RequestTab) -> Int {
        switch tab {
        case .news: return newsVM.pendingNewsRequests.count
        case .reports: return adminRequestVM.newsReportRequests.count
        case .phone: return adminRequestVM.phoneChangeRequests.count
        case .diwaniya: return diwaniyaVM.pendingDiwaniyas.count
        case .deceased: return adminRequestVM.deceasedRequests.count
        case .children: return adminRequestVM.childAddRequests.count
        case .photos: return adminRequestVM.photoSuggestionRequests.count
        }
    }

    private var totalCount: Int {
        RequestTab.allCases.reduce(0) { $0 + itemCount(for: $1) }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(RequestTab.allCases) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.xs)
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
                    .font(DS.Font.scaled(12, weight: .semibold))

                Text(tab.title)
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)

                if count > 0 {
                    Text("\(count)")
                        .font(DS.Font.caption2)
                        .fontWeight(.black)
                        .foregroundColor(isSelected ? tab.color : .white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(isSelected ? DS.Color.surface : tab.color.opacity(0.8))
                        .clipShape(Circle())
                }
            }
            .foregroundColor(isSelected ? .white : DS.Color.textSecondary)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                Capsule()
                    .fill(isSelected ? tab.color : DS.Color.surface)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : DS.Color.textTertiary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: DS.Spacing.md) {
                switch selectedTab {
                case .news:
                    ForEach(newsVM.pendingNewsRequests) { post in
                        newsCard(for: post)
                    }
                case .reports:
                    ForEach(adminRequestVM.newsReportRequests) { request in
                        reportCard(for: request)
                    }
                case .phone:
                    ForEach(adminRequestVM.phoneChangeRequests) { request in
                        phoneCard(for: request)
                    }
                case .diwaniya:
                    ForEach(diwaniyaVM.pendingDiwaniyas) { diwaniya in
                        diwaniyaCard(for: diwaniya)
                    }
                case .deceased:
                    ForEach(adminRequestVM.deceasedRequests) { request in
                        deceasedCard(for: request)
                    }
                case .children:
                    ForEach(adminRequestVM.childAddRequests) { request in
                        childCard(for: request)
                    }
                case .photos:
                    ForEach(adminRequestVM.photoSuggestionRequests) { request in
                        photoCard(for: request)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)
            .padding(.bottom, DS.Spacing.xxxl)
        }
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

    // MARK: - News Card

    private func newsCard(for post: NewsPost) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                accentBar(color: DS.Color.warning)

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
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !post.mediaURLs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Spacing.sm) {
                            ForEach(post.mediaURLs, id: \.self) { urlStr in
                                if let url = URL(string: urlStr) {
                                    CachedAsyncImage(url: url) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: DS.Radius.md)
                                            .fill(DS.Color.surface)
                                            .overlay(ProgressView().tint(DS.Color.primary))
                                    }
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                                }
                            }
                        }
                    }
                }

                DSApproveRejectButtons(
                    approveTitle: L10n.t("اعتماد النشر", "Approve"),
                    rejectTitle: L10n.t("رفض", "Reject"),
                    isLoading: newsVM.isLoading,
                    approveGradient: LinearGradient(
                        colors: [DS.Color.success, DS.Color.success.opacity(0.8)],
                        startPoint: .leading, endPoint: .trailing
                    )
                ) {
                    Task { await newsVM.approveNewsPost(postId: post.id) }
                } onReject: {
                    Task { await newsVM.rejectNewsPost(postId: post.id) }
                }
            }
            .padding(DS.Spacing.lg)
        }
    }

    // MARK: - Report Card

    private func reportCard(for request: AdminRequest) -> some View {
        let postId = UUID(uuidString: request.newValue ?? "")
        let reportedPost = postId.flatMap { id in newsVM.allNews.first { $0.id == id } }

        return DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                accentBar(color: DS.Color.error)

                HStack(spacing: DS.Spacing.md) {
                    iconCircle(icon: "exclamationmark.triangle.fill", color: DS.Color.error)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.member?.fullName ?? L10n.t("عضو", "Member"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(request.createdAt?.prefix(10) ?? "—")
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textSecondary)
                    }

                    Spacer()

                    typeBadge(text: L10n.t("بلاغ", "Report"), color: DS.Color.error)
                }

                Text(request.details ?? L10n.t("بلاغ بدون تفاصيل", "Report without details"))
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let post = reportedPost {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(L10n.t("الخبر المبلغ عنه", "Reported Post"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                        Text(post.content)
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }

                DSApproveRejectButtons(
                    approveTitle: L10n.t("اعتماد البلاغ", "Approve Report"),
                    rejectTitle: L10n.t("رفض البلاغ", "Reject Report"),
                    isLoading: adminRequestVM.isLoading,
                    approveGradient: LinearGradient(
                        colors: [DS.Color.error, DS.Color.error.opacity(0.8)],
                        startPoint: .leading, endPoint: .trailing
                    )
                ) {
                    Task { await adminRequestVM.approveNewsReport(request: request) }
                } onReject: {
                    Task { await adminRequestVM.rejectNewsReport(request: request) }
                }
            }
            .padding(DS.Spacing.lg)
        }
    }

    // MARK: - Phone Card

    private func phoneCard(for request: PhoneChangeRequest) -> some View {
        let currentPhone = KuwaitPhone.display(request.member?.phoneNumber)
        let newPhone = KuwaitPhone.display(request.newValue)
        let memberName = request.member?.fullName ?? "Member"

        return DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                accentBar(color: DS.Color.primary)

                HStack(spacing: DS.Spacing.md) {
                    iconCircle(icon: "phone.arrow.right", color: DS.Color.primary)

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

                DSDivider()

                HStack(spacing: DS.Spacing.xl) {
                    VStack(alignment: .center, spacing: DS.Spacing.xs) {
                        Text(L10n.t("الرقم الجديد", "New Number"))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.success)
                        Text(newPhone)
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.success)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DS.Spacing.md)
                    .background(DS.Color.success.opacity(0.08))
                    .cornerRadius(DS.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.success.opacity(0.2), lineWidth: 1)
                    )

                    Image(systemName: "arrow.left")
                        .foregroundColor(DS.Color.primary)
                        .font(DS.Font.scaled(14, weight: .semibold))

                    VStack(alignment: .center, spacing: DS.Spacing.xs) {
                        Text(L10n.t("الرقم الحالي", "Current Number"))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textSecondary)
                        Text(currentPhone)
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surfaceElevated)
                    .cornerRadius(DS.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.textTertiary.opacity(0.2), lineWidth: 1)
                    )
                }

                DSApproveRejectButtons(
                    approveTitle: L10n.t("اعتماد الرقم", "Approve Number"),
                    rejectTitle: L10n.t("رفض", "Reject"),
                    isLoading: adminRequestVM.isLoading
                ) {
                    Task { await adminRequestVM.approvePhoneChangeRequest(request: request) }
                } onReject: {
                    Task { await adminRequestVM.rejectPhoneChangeRequest(request: request) }
                }
            }
            .padding(DS.Spacing.lg)
        }
    }

    // MARK: - Diwaniya Card

    private func diwaniyaCard(for diwaniya: Diwaniya) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                accentBar(color: DS.Color.gridDiwaniya)

                HStack(spacing: DS.Spacing.sm) {
                    Circle()
                        .fill(DS.Color.gridDiwaniya.opacity(0.15))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "tent.fill")
                                .font(DS.Font.scaled(16, weight: .semibold))
                                .foregroundColor(DS.Color.gridDiwaniya)
                        )

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

                    typeBadge(text: L10n.t("معلق", "Pending"), color: DS.Color.warning)
                }

                VStack(spacing: DS.Spacing.sm) {
                    if let schedule = diwaniya.scheduleText, !schedule.isEmpty {
                        detailRow(icon: "calendar", text: schedule)
                    }
                    if let phone = diwaniya.contactPhone, !phone.isEmpty {
                        detailRow(icon: "phone.fill", text: phone)
                    }
                    if let address = diwaniya.address, !address.isEmpty {
                        detailRow(icon: "mappin.and.ellipse", text: address)
                    }
                }

                DSApproveRejectButtons(
                    approveTitle: L10n.t("اعتماد", "Approve"),
                    rejectTitle: L10n.t("رفض", "Reject"),
                    isLoading: diwaniyaVM.isLoading,
                    approveGradient: LinearGradient(
                        colors: [DS.Color.success, DS.Color.success.opacity(0.8)],
                        startPoint: .leading, endPoint: .trailing
                    )
                ) {
                    if let adminId = authVM.currentUser?.id {
                        Task { await diwaniyaVM.approveDiwaniya(id: diwaniya.id, adminId: adminId) }
                    }
                } onReject: {
                    Task { await diwaniyaVM.rejectDiwaniya(id: diwaniya.id) }
                }
            }
            .padding(DS.Spacing.lg)
        }
    }

    // MARK: - Deceased Card

    private func deceasedCard(for request: AdminRequest) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                accentBar(color: DS.Color.error)

                HStack(spacing: DS.Spacing.md) {
                    iconCircle(icon: "bolt.heart.fill", color: DS.Color.error)

                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(L10n.t("طلب لـ: \(request.member?.fullName ?? "عضو جديد")", "Request for: \(request.member?.fullName ?? "New Member")"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(request.details ?? L10n.t("لا توجد تفاصيل إضافية", "No additional details"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    Spacer()
                }

                DSApproveRejectButtons(
                    approveTitle: L10n.t("موافقة وتحديث الشجرة", "Approve & Update Tree"),
                    rejectTitle: L10n.t("رفض", "Reject"),
                    isLoading: adminRequestVM.isLoading
                ) {
                    Task { await adminRequestVM.approveDeceasedRequest(request: request) }
                } onReject: {
                    Task { await adminRequestVM.rejectDeceasedRequest(request: request) }
                }
            }
            .padding(DS.Spacing.lg)
        }
    }

    // MARK: - Child Card

    private func childCard(for request: AdminRequest) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                accentBar(color: DS.Color.info)

                HStack(spacing: DS.Spacing.md) {
                    iconCircle(icon: "person.badge.plus", color: DS.Color.info)

                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(L10n.t("طلب من: \(request.member?.fullName ?? "عضو")", "Request from: \(request.member?.fullName ?? "Member")"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(request.details ?? L10n.t("لا توجد تفاصيل إضافية", "No additional details"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                        if let createdAt = request.createdAt {
                            Text(createdAt.prefix(10))
                                .font(DS.Font.caption2)
                                .foregroundColor(DS.Color.textSecondary.opacity(0.7))
                        }
                    }
                    Spacer()
                }

                DSApproveRejectButtons(
                    approveTitle: L10n.t("تأكيد الإضافة", "Confirm Addition"),
                    rejectTitle: L10n.t("رفض وحذف", "Reject & Delete"),
                    isLoading: adminRequestVM.isLoading
                ) {
                    Task { await adminRequestVM.acknowledgeChildAddRequest(request: request) }
                } onReject: {
                    Task { await adminRequestVM.rejectChildAddRequest(request: request) }
                }
            }
            .padding(DS.Spacing.lg)
        }
    }

    // MARK: - Photo Card

    private func photoCard(for request: AdminRequest) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                accentBar(color: DS.Color.neonBlue)

                HStack(spacing: DS.Spacing.md) {
                    iconCircle(icon: "camera.badge.ellipsis", color: DS.Color.primary)

                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(L10n.t(
                            "اقتراح صورة لـ: \(request.member?.fullName ?? "عضو")",
                            "Photo suggestion for: \(request.member?.fullName ?? "Member")"
                        ))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(request.details ?? L10n.t("لا توجد تفاصيل", "No details"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    Spacer()
                }

                if let photoUrl = request.newValue, let url = URL(string: photoUrl) {
                    CachedAsyncImage(url: url) { img in
                        img.resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    } placeholder: {
                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            .fill(DS.Color.surface)
                            .frame(height: 200)
                            .overlay(ProgressView().tint(DS.Color.primary))
                    }
                }

                DSApproveRejectButtons(
                    approveTitle: L10n.t("موافقة وتحديث الصورة", "Approve & Update Photo"),
                    rejectTitle: L10n.t("رفض", "Reject"),
                    isLoading: adminRequestVM.isLoading
                ) {
                    Task { await adminRequestVM.approvePhotoSuggestion(request: request) }
                } onReject: {
                    Task { await adminRequestVM.rejectPhotoSuggestion(request: request) }
                }
            }
            .padding(DS.Spacing.lg)
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

    private func iconCircle(icon: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.2), color.opacity(0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
            Image(systemName: icon)
                .foregroundColor(color)
                .font(DS.Font.scaled(18, weight: .semibold))
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
