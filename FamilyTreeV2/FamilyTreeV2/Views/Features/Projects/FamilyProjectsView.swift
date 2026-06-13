import SwiftUI

struct FamilyProjectsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel

    @State private var showingAddProject = false
    @State private var selectedProject: Project?
    @State private var showAddedAlert = false

    // Filter
    @State private var filter: ProjectsFilter = .approved

    // Selection (admin only)
    @State private var selectionMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showBatchDeleteAlert = false
    @State private var projectToDelete: Project? = nil
    @State private var projectToEdit: Project? = nil
    @State private var didEditProject = false
    @State private var projectToReport: Project? = nil
    @State private var reportReason = ""
    @State private var reportSent = false

    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: DS.Spacing.md),
        GridItem(.flexible(), spacing: DS.Spacing.md)
    ]

    enum ProjectsFilter: Hashable {
        case approved
        case pending
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // شريط التحديد العلوي يحلّ محل صف الفلاتر في وضع التحديد
                if selectionMode {
                    selectionTopBar
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.xs)
                } else {
                    filterCapsule
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.xs)
                }

                contentArea
            }

            // FAB رفع — للجميع، يختفي في وضع التحديد
            if !selectionMode {
                HStack {
                    Spacer()
                    DSFloatingButton(label: L10n.t("إضافة مشروع", "Add Project"), color: DS.Color.secondary) {
                        showingAddProject = true
                    }
                    .padding(.trailing, DS.Spacing.xl)
                    .padding(.bottom, DS.Spacing.lg)
                }
            }

            // شريط الإجراءات السفلي للتحديد
            if selectionMode {
                selectionBottomBar
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(DS.Anim.snappy, value: selectionMode)
        .task {
            await projectsVM.fetchProjects()
            if let userId = authVM.currentUser?.id {
                await projectsVM.fetchMyPendingProjects(ownerId: userId)
            }
            if authVM.isAdmin {
                await projectsVM.fetchPendingProjects()
            }
        }
        .sheet(isPresented: $showingAddProject) {
            AddProjectView(showAddedAlert: $showAddedAlert)
                .environmentObject(projectsVM)
                .environmentObject(authVM)
                .environmentObject(memberVM)
        }
        .alert(
            L10n.t("تم إرسال المشروع", "Project Submitted"),
            isPresented: $showAddedAlert
        ) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.t(
                "تم إرسال مشروعك للمراجعة. سيظهر بعد موافقة الإدارة.",
                "Your project has been submitted for review. It will appear after admin approval."
            ))
        }
        .sheet(item: $selectedProject) { project in
            ProjectDetailView(project: project)
                .environmentObject(projectsVM)
                .environmentObject(authVM)
        }
        .sheet(item: $projectToEdit) { project in
            NavigationStack {
                EditProjectView(project: project, didEdit: $didEditProject)
                    .environmentObject(projectsVM)
                    .environmentObject(authVM)
            }
        }
        .alert(L10n.t("إبلاغ عن مشروع", "Report Project"), isPresented: Binding(
            get: { projectToReport != nil },
            set: { if !$0 { projectToReport = nil } }
        )) {
            TextField(L10n.t("سبب الإبلاغ (اختياري)", "Reason (optional)"), text: $reportReason)
            Button(L10n.t("إبلاغ", "Report"), role: .destructive) {
                let target = projectToReport
                let reason = reportReason
                projectToReport = nil
                reportReason = ""
                if let target {
                    Task {
                        let ok = await notificationVM.reportContent(
                            contentKind: L10n.t("مشروع", "project"),
                            contentLabel: target.title,
                            contentId: target.id,
                            reason: reason
                        )
                        if ok { await MainActor.run { reportSent = true } }
                    }
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { projectToReport = nil; reportReason = "" }
        } message: {
            Text(L10n.t("اكتب سبب الإبلاغ، وسيتم إرساله للإدارة لمراجعة هذا المشروع.",
                       "Enter a reason; it will be sent to the admins to review this project."))
        }
        .alert(L10n.t("تم الإبلاغ", "Reported"), isPresented: $reportSent) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.t("شكراً لك، وصل بلاغك للإدارة.", "Thank you, your report reached the admins."))
        }
        .alert(L10n.t("حذف المشروع", "Delete project"),
               isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } })) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                if let p = projectToDelete {
                    Task { await projectsVM.deleteProject(id: p.id) }
                }
                projectToDelete = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { projectToDelete = nil }
        } message: {
            Text(L10n.t("حذف هذا المشروع نهائياً؟",
                       "Permanently delete this project?"))
        }
        .alert(L10n.t("حذف المشاريع المختارة", "Delete selected"),
               isPresented: $showBatchDeleteAlert) {
            Button(L10n.t("حذف \(selectedIDs.count)", "Delete \(selectedIDs.count)"),
                   role: .destructive) {
                let ids = selectedIDs
                Task {
                    for id in ids {
                        await projectsVM.deleteProject(id: id)
                    }
                    await MainActor.run { exitSelectionMode() }
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("حذف \(selectedIDs.count) مشروع نهائياً؟",
                       "Permanently delete \(selectedIDs.count) projects?"))
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if projectsVM.isLoading && projectsVM.projects.isEmpty && projectsVM.myPendingProjects.isEmpty {
            Spacer()
            ProgressView().tint(DS.Color.primary)
            Spacer()
        } else if currentItems.isEmpty {
            Spacer()
            emptyStateView
            Spacer()
        } else {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: gridColumns, spacing: DS.Spacing.md) {
                    ForEach(currentItems) { project in
                        Button {
                            if selectionMode {
                                toggleSelection(project.id)
                            } else {
                                selectedProject = project
                            }
                        } label: {
                            projectCard(project)
                                .overlay(alignment: .topLeading) {
                                    if selectionMode {
                                        selectionCheckmark(for: project.id)
                                    }
                                }
                        }
                        .buttonStyle(DSScaleButtonStyle())
                        // زر قائمة ظاهر — كـ overlay على الزر نفسه. الإدارة: تحكّم
                        // كامل، غيرهم: إبلاغ فقط (لغير مشاريعهم).
                        .overlay(alignment: .topLeading) {
                            if !selectionMode && projectMenuHasActions(for: project) {
                                Menu {
                                    projectActionsMenu(for: project)
                                } label: {
                                    cardMenuBadge
                                }
                                .padding(6)
                            }
                        }
                        .contextMenu {
                            if !selectionMode {
                                projectActionsMenu(for: project)
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxxxl)
            }
            .refreshable { await refreshAll() }
        }
    }

    /// هل توجد إجراءات للمستخدم الحالي على هذا المشروع؟
    private func projectMenuHasActions(for project: Project) -> Bool {
        if authVM.isAdmin { return true }
        return project.ownerId != authVM.currentUser?.id
    }

    /// محتوى قائمة إجراءات المشروع — للإدارة تحكّم كامل، لغيرهم إبلاغ فقط.
    @ViewBuilder
    private func projectActionsMenu(for project: Project) -> some View {
        if authVM.isAdmin {
            Button {
                projectToEdit = project
            } label: {
                Label(L10n.t("تعديل", "Edit"), systemImage: "pencil")
            }
            Button {
                Task { await projectsVM.toggleHidden(id: project.id) }
            } label: {
                Label(
                    project.isHidden
                        ? L10n.t("إظهار للجميع", "Show to all")
                        : L10n.t("إخفاء من الأعضاء", "Hide from members"),
                    systemImage: project.isHidden ? "eye.fill" : "eye.slash.fill"
                )
            }
            Button(role: .destructive) {
                projectToDelete = project
            } label: {
                Label(L10n.t("حذف", "Delete"), systemImage: "trash")
            }
            // إبلاغ متاح للإدارة أيضاً (لغير مشاريعهم)
            if project.ownerId != authVM.currentUser?.id {
                Divider()
                Button {
                    projectToReport = project
                } label: {
                    Label(L10n.t("إبلاغ", "Report"), systemImage: "exclamationmark.bubble")
                }
            }
        } else if project.ownerId != authVM.currentUser?.id {
            // الأعضاء العاديون: إبلاغ فقط (لغير مشاريعهم) — سياسة Apple
            Button {
                projectToReport = project
            } label: {
                Label(L10n.t("إبلاغ", "Report"), systemImage: "exclamationmark.bubble")
            }
        }
    }

    /// شارة زر القائمة الظاهر (•••) — دائرة زجاجية صغيرة.
    private var cardMenuBadge: some View {
        Image(systemName: "ellipsis")
            .font(DS.Font.scaled(13, weight: .black))
            .foregroundColor(.white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.black.opacity(0.35)))
            .background(Circle().fill(.ultraThinMaterial))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
    }

    private var currentItems: [Project] {
        switch filter {
        case .approved:
            return projectsVM.projects
        case .pending:
            return authVM.isAdmin
                ? projectsVM.pendingProjects
                : projectsVM.myPendingProjects
        }
    }

    private func refreshAll() async {
        await projectsVM.fetchProjects()
        if let userId = authVM.currentUser?.id {
            await projectsVM.fetchMyPendingProjects(ownerId: userId)
        }
        if authVM.isAdmin {
            await projectsVM.fetchPendingProjects()
        }
    }

    // MARK: - Filter Capsule (مع زر التحديد المدمج)

    private var filterCapsule: some View {
        let pendingCount = authVM.isAdmin
            ? projectsVM.pendingProjects.count
            : projectsVM.myPendingProjects.count

        return HStack(spacing: 6) {
            if filter == .approved {
                activeFilterPill(
                    title: L10n.t("الكل", "All"),
                    icon: "briefcase.fill",
                    count: projectsVM.projects.count,
                    color: DS.Color.primary
                )
            } else {
                inactiveFilterIcon(icon: "briefcase.fill",
                                   count: projectsVM.projects.count,
                                   color: DS.Color.primary) {
                    filter = .approved
                }
            }

            // فلتر بانتظار — يظهر فقط لو فيه طلبات
            if pendingCount > 0 {
                if filter == .pending {
                    activeFilterPill(
                        title: authVM.isAdmin
                            ? L10n.t("بانتظار", "Pending")
                            : L10n.t("طلباتي", "Mine"),
                        icon: "clock.fill",
                        count: pendingCount,
                        color: DS.Color.warning
                    )
                } else {
                    inactiveFilterIcon(icon: "clock.fill",
                                       count: pendingCount,
                                       color: DS.Color.warning) {
                        filter = .pending
                    }
                }
            }

            Spacer(minLength: 0)

            // زر التحديد مدمج — للإدارة فقط
            if authVM.isAdmin && filter == .approved {
                Capsule()
                    .fill(DS.Color.textTertiary.opacity(0.25))
                    .frame(width: 1, height: 22)
                    .padding(.horizontal, 2)

                Button {
                    withAnimation(DS.Anim.snappy) {
                        selectionMode = true
                        selectedIDs = []
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
        .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
        .overlay(Capsule(style: .continuous).strokeBorder(DS.Color.primary.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .animation(.spring(response: 0.40, dampingFraction: 0.78), value: filter)
    }

    private func activeFilterPill(title: String, icon: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(DS.Font.scaled(12, weight: .bold)).foregroundColor(.white)
            Text(title).font(DS.Font.scaled(13, weight: .bold)).foregroundColor(.white)
            if count > 0 {
                Text("\(count)")
                    .font(DS.Font.scaled(10, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.25)))
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, 8)
        .background(Capsule().fill(LinearGradient(colors: [color, color.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .shadow(color: color.opacity(0.35), radius: 8, x: 0, y: 3)
    }

    private func inactiveFilterIcon(icon: String, count: Int, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(color.opacity(0.12)))
                    .overlay(Circle().strokeBorder(color.opacity(0.20), lineWidth: 1))
                if count > 0 {
                    Text("\(count)")
                        .font(DS.Font.scaled(9, weight: .black))
                        .foregroundColor(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(color))
                        .overlay(Capsule().strokeBorder(Color.white, lineWidth: 1.5))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Selection UI

    private var selectionTopBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button { exitSelectionMode() } label: {
                Text(L10n.t("إلغاء", "Cancel"))
                    .font(DS.Font.scaled(13, weight: .semibold))
                    .foregroundColor(DS.Color.error)
            }
            Spacer()
            Text(L10n.t("اختيار \(selectedIDs.count)", "Selected \(selectedIDs.count)"))
                .font(DS.Font.scaled(13, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
            Spacer()
            Button {
                toggleSelectAll()
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
        .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Color.primary.opacity(0.18), lineWidth: 1))
    }

    private func selectionCheckmark(for id: UUID) -> some View {
        let isSelected = selectedIDs.contains(id)
        return Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(isSelected ? .white : DS.Color.textPrimary.opacity(0.7))
            .background(
                Circle()
                    .fill(isSelected ? DS.Color.primary : Color.white.opacity(0.85))
                    .frame(width: 22, height: 22)
            )
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            .padding(10)
    }

    private var selectionBottomBar: some View {
        HStack(spacing: DS.Spacing.md) {
            Spacer()
            Button {
                showBatchDeleteAlert = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "trash.fill").font(DS.Font.scaled(12, weight: .bold))
                    Text(L10n.t("حذف", "Delete")).font(DS.Font.scaled(13, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, 9)
                .background(Capsule().fill(DS.Color.error))
            }
            .buttonStyle(DSScaleButtonStyle())
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle().fill(DS.Color.textTertiary.opacity(0.15)).frame(height: 0.5),
            alignment: .top
        )
    }

    // MARK: - Project Card (التصميم الجديد)

    private func projectCard(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            // معاينة بصرية — صورة شعار أو placeholder مع gradient
            ZStack {
                if let logoUrl = project.logoUrl, let url = URL(string: logoUrl) {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView().tint(DS.Color.primary)
                    }
                } else {
                    projectPlaceholderCover
                }
            }
            .frame(width: 96, height: 96)
            .clipped()
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(DS.Color.primary.opacity(0.12), lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, DS.Spacing.xs)

            // العنوان والمالك
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title)
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(DS.Font.scaled(8, weight: .bold))
                    Text(project.ownerName)
                        .font(DS.Font.scaled(10, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundColor(DS.Color.textSecondary)
            }

            // مؤشّر روابط التواصل (لو فيه)
            if project.hasSocialLinks {
                socialIndicators(project: project)
                    .padding(.top, 2)
            }
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(DS.Color.surface))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(project.approvalStatus == "pending"
                        ? DS.Color.warning.opacity(0.30)
                        : DS.Color.primary.opacity(0.08),
                        lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if project.approvalStatus == "pending" {
                HStack(spacing: 3) {
                    Image(systemName: "clock.fill").font(DS.Font.scaled(9, weight: .bold))
                    Text(L10n.t("بانتظار", "Pending")).font(DS.Font.scaled(9, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(DS.Color.warning))
                .padding(DS.Spacing.sm)
            } else if project.isHidden {
                HStack(spacing: 3) {
                    Image(systemName: "eye.slash.fill").font(DS.Font.scaled(9, weight: .bold))
                    Text(L10n.t("مخفي", "Hidden")).font(DS.Font.scaled(9, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(DS.Color.textTertiary))
                .padding(DS.Spacing.sm)
            }
        }
        .opacity(project.approvalStatus == "pending" || project.isHidden ? 0.85 : 1.0)
        .dsSubtleShadow()
    }

    /// أيقونات المنصات اللي عنده روابط فيها — مؤشّر بصري سريع.
    private func socialIndicators(project: Project) -> some View {
        HStack(spacing: 4) {
            if project.phoneNumber?.isEmpty == false    { socialDot(icon: "phone.fill", color: DS.Color.success) }
            if project.whatsappNumber?.isEmpty == false { socialDot(icon: "message.fill", color: Color(hex: "#25D366")) }
            if project.instagramUrl?.isEmpty == false   { socialDot(icon: "camera.fill", color: Color(hex: "#E1306C")) }
            if project.twitterUrl?.isEmpty == false     { socialDot(icon: "xmark", color: Color(hex: "#000000")) }
            if project.websiteUrl?.isEmpty == false     { socialDot(icon: "globe", color: DS.Color.info) }
            if project.locationUrl?.isEmpty == false    { socialDot(icon: "mappin.and.ellipse", color: Color(hex: "#EA4335")) }
        }
    }

    private func socialDot(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(DS.Font.scaled(8, weight: .bold))
            .foregroundColor(color)
            .frame(width: 16, height: 16)
            .background(Circle().fill(color.opacity(0.15)))
    }

    private var projectPlaceholderCover: some View {
        ZStack {
            LinearGradient(
                colors: [DS.Color.primary.opacity(0.30), DS.Color.accent.opacity(0.30)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "briefcase.fill")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(.white.opacity(0.85))
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: filter == .pending ? "clock.badge" : "briefcase")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(DS.Color.textTertiary)
            Text(filter == .pending
                 ? L10n.t("لا توجد طلبات معلَّقة", "No pending requests")
                 : L10n.t("لا توجد مشاريع بعد", "No projects yet"))
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.textPrimary)
            Text(filter == .pending
                 ? L10n.t("سيظهر هنا أي طلب مشروع جديد",
                          "Any new project request will appear here")
                 : L10n.t("اضغط + لإضافة مشروع جديد",
                          "Tap + to add a new project"))
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Selection Helpers

    private var allSelected: Bool {
        guard !currentItems.isEmpty else { return false }
        return currentItems.allSatisfy { selectedIDs.contains($0.id) }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func toggleSelectAll() {
        if allSelected {
            for p in currentItems { selectedIDs.remove(p.id) }
        } else {
            for p in currentItems { selectedIDs.insert(p.id) }
        }
    }

    private func exitSelectionMode() {
        withAnimation(DS.Anim.snappy) {
            selectionMode = false
            selectedIDs = []
        }
    }
}

// MARK: - Add Project View
struct AddProjectView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss
    @Binding var showAddedAlert: Bool

    @State private var title = ""
    @State private var description = ""
    @State private var websiteUrl = ""
    @State private var instagramUrl = ""
    @State private var twitterUrl = ""
    @State private var whatsappNumber = "+965 "
    @State private var phoneNumber = ""
    @State private var locationUrl = ""
    @State private var logoImage: UIImage? = nil
    @State private var isSaving = false
    @State private var selectedOwnerId: UUID?
    @State private var showMemberPicker = false
    @State private var memberSearchText = ""

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {

                        // ── إرشاد للأعضاء العاديين ──
                        if !authVM.isAdmin {
                            approvalHintCard
                        }

                        // ── البطاقة 1: الأساسيات (شعار + اسم + وصف) ──
                        basicsCard

                        // ── البطاقة 2: صاحب المشروع (للإدارة فقط) ──
                        if authVM.canModerate {
                            ownerCard
                                .sheet(isPresented: $showMemberPicker) { memberPickerSheet }
                        }

                        // ── البطاقة 3: روابط التواصل (اختيارية، مجموعة) ──
                        contactLinksCard

                        // ── زر الإضافة ──
                        DSPrimaryButton(
                            L10n.t("إرسال المشروع", "Submit Project"),
                            isLoading: isSaving
                        ) {
                            Task { await saveProject() }
                        }
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.5)
                        .padding(.top, DS.Spacing.sm)
                    }
                    .padding(DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xxxl)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                }
            }
            .navigationTitle(L10n.t("مشروع جديد", "New Project"))
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }

    // MARK: - Hint card (للأعضاء العاديين)

    private var approvalHintCard: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: "info.circle.fill")
                .font(DS.Font.scaled(14, weight: .bold))
                .foregroundColor(DS.Color.info)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("بانتظار موافقة الإدارة",
                           "Pending admin approval"))
                    .font(DS.Font.scaled(12, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("مشروعك يظهر لك بعد الإرسال، ويظهر للجميع بعد المراجعة.",
                           "Your project will be visible to you, and to everyone once admin approves."))
                    .font(DS.Font.scaled(11, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
                    .lineSpacing(2)
            }
            Spacer()
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.info.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.info.opacity(0.20), lineWidth: 1)
        )
    }

    // MARK: - Card: Basics

    private var basicsCard: some View {
        VStack(spacing: DS.Spacing.md) {
            // Logo (مدمج بداية البطاقة)
            DSProfilePhotoPicker(
                selectedImage: $logoImage,
                enableCrop: true,
                cropShape: .circle,
                title: L10n.t("شعار المشروع", "Project Logo"),
                trailing: L10n.t("اختياري", "Optional"),
                compactEmptyState: true
            )

            Divider().opacity(0.4)

            // الاسم — مطلوب
            DSTextField(
                label: L10n.t("اسم المشروع", "Project Name"),
                placeholder: L10n.t("اكتب اسم المشروع هنا", "Enter project name"),
                text: $title,
                icon: "briefcase.fill",
                required: true
            )

            // الوصف — اختياري
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "text.alignleft")
                        .font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(DS.Color.textSecondary)
                    Text(L10n.t("وصف مختصر", "Short Description"))
                        .font(DS.Font.scaled(12, weight: .semibold))
                        .foregroundColor(DS.Color.textSecondary)
                    Spacer()
                    Text(L10n.t("اختياري", "Optional"))
                        .font(DS.Font.scaled(10, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                }
                TextEditor(text: $description)
                    .font(DS.Font.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 70)
                    .padding(DS.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(DS.Color.background)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .strokeBorder(DS.Color.textTertiary.opacity(0.20), lineWidth: 1)
                    )
            }
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(DS.Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Card: Owner

    private var ownerCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(DS.Color.primary)
                Text(L10n.t("صاحب المشروع", "Project Owner"))
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Spacer()
            }

            Button { showMemberPicker = true } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "person.fill")
                        .font(DS.Font.body)
                        .foregroundColor(DS.Color.primary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(DS.Color.primary.opacity(0.10)))

                    if let ownerId = selectedOwnerId,
                       let member = memberVM.member(byId: ownerId) {
                        Text(member.fullName)
                            .font(DS.Font.body)
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(1)
                    } else {
                        HStack(spacing: 4) {
                            Text(authVM.currentUser?.fullName ?? "")
                                .font(DS.Font.body)
                                .foregroundColor(DS.Color.textPrimary)
                                .lineLimit(1)
                            Text(L10n.t("(أنت)", "(You)"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textTertiary)
                        }
                    }

                    Spacer()

                    Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                }
                .padding(DS.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(DS.Color.textTertiary.opacity(0.20), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(DS.Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Card: Contact Links

    private var contactLinksCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(DS.Color.success)
                Text(L10n.t("روابط التواصل", "Contact Links"))
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Spacer()
                Text(L10n.t("اختياري", "Optional"))
                    .font(DS.Font.scaled(10, weight: .semibold))
                    .foregroundColor(DS.Color.textTertiary)
            }

            Text(L10n.t("أضف الروابط التي تريد عرضها للزوار",
                       "Add links to share with visitors"))
                .font(DS.Font.scaled(11, weight: .medium))
                .foregroundColor(DS.Color.textSecondary)

            VStack(spacing: DS.Spacing.xs) {
                socialRow(platform: .phone, placeholder: "+965...", text: $phoneNumber)
                socialRow(platform: .whatsapp, placeholder: "+965...", text: $whatsappNumber)
                socialRow(platform: .instagram, placeholder: "@username", text: $instagramUrl)
                socialRow(platform: .twitter, placeholder: "@username", text: $twitterUrl)
                socialRow(platform: .website, placeholder: "https://...", text: $websiteUrl)
                socialRow(platform: .location, placeholder: L10n.t("رابط الموقع (Maps)", "Maps URL"), text: $locationUrl)
            }
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(DS.Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    /// صف رابط تواصل مدمج وأنيق — أيقونة + label + textfield في سطر واحد.
    private func socialRow(platform: SocialPlatform, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            platform.iconView(size: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(platform.label)
                    .font(DS.Font.scaled(10, weight: .semibold))
                    .foregroundColor(DS.Color.textSecondary)
                TextField(placeholder, text: text)
                    .font(DS.Font.callout)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Font.scaled(13))
                        .foregroundColor(DS.Color.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.textTertiary.opacity(0.18), lineWidth: 1)
        )
    }

    private func socialTextField(platform: SocialPlatform, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: DS.Spacing.md) {
            platform.iconView(size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(platform.label)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                TextField(placeholder, text: text)
                    .font(DS.Font.body)
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Member Picker Sheet

    private var memberPickerSheet: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(DS.Color.textTertiary)
                        TextField(L10n.t("بحث عن عضو...", "Search member..."), text: $memberSearchText)
                            .font(DS.Font.body)
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)

                    List {
                        ForEach(filteredMembers) { member in
                            Button {
                                selectedOwnerId = member.id
                                showMemberPicker = false
                                memberSearchText = ""
                            } label: {
                                HStack(spacing: DS.Spacing.md) {
                                    // Avatar
                                    if let avatarUrl = member.avatarUrl, let url = URL(string: avatarUrl) {
                                        CachedAsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 40, height: 40)
                                                .clipShape(Circle())
                                        } placeholder: {
                                            memberPlaceholderAvatar
                                        }
                                    } else {
                                        memberPlaceholderAvatar
                                    }

                                    Text(member.fullName)
                                        .font(DS.Font.body)
                                        .foregroundColor(DS.Color.textPrimary)

                                    Spacer()

                                    if selectedOwnerId == member.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(DS.Color.primary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(L10n.t("اختيار صاحب المشروع", "Select Project Owner"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("إلغاء", "Cancel")) {
                        showMemberPicker = false
                        memberSearchText = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("إعادة تعيين", "Reset")) {
                        selectedOwnerId = nil
                        showMemberPicker = false
                        memberSearchText = ""
                    }
                    .foregroundColor(DS.Color.textSecondary)
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }

    private var memberPlaceholderAvatar: some View {
        ZStack {
            Circle()
                .fill(DS.Color.primary.opacity(0.10))
                .frame(width: 40, height: 40)
            Image(systemName: "person.fill")
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.primary)
        }
    }

    private var filteredMembers: [FamilyMember] {
        let active = memberVM.allMembers.filter { $0.status == .active }
        let query = memberSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return Array(active.prefix(20))
        }
        return active.filter {
            $0.fullName.lowercased().contains(query)
        }
    }

    private func saveProject() async {
        guard let currentUser = authVM.currentUser else { return }
        isSaving = true

        // owner_id لازم يكون المستخدم الحالي (RLS: owner_id = auth.uid())
        // لو اختار عضو ثاني نحفظ اسمه بس الـ owner_id يبقى المستخدم الحالي
        let ownerId = currentUser.id
        let ownerName: String

        if let selectedId = selectedOwnerId,
           let selectedMember = memberVM.member(byId: selectedId) {
            ownerName = selectedMember.fullName
        } else {
            ownerName = currentUser.fullName
        }

        // Upload logo if selected
        var uploadedLogoUrl: String? = nil
        if let logoImage {
            let projectId = UUID()
            if let data = ImageProcessor.process(logoImage, for: .projectLogo) {
                uploadedLogoUrl = await projectsVM.uploadLogo(imageData: data, projectId: projectId)
            }
        }

        let success = await projectsVM.addProject(
            ownerId: ownerId,
            ownerName: ownerName,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.isEmpty ? nil : description,
            logoUrl: uploadedLogoUrl,
            websiteUrl: websiteUrl.isEmpty ? nil : websiteUrl,
            instagramUrl: instagramUrl.isEmpty ? nil : instagramUrl,
            twitterUrl: twitterUrl.isEmpty ? nil : twitterUrl,
            snapchatUrl: nil,
            whatsappNumber: {
                let t = whatsappNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                return (t.isEmpty || t == "+965") ? nil : whatsappNumber
            }(),
            phoneNumber: phoneNumber.isEmpty ? nil : phoneNumber,
            locationUrl: locationUrl.isEmpty ? nil : locationUrl
        )

        if success {
            if let userId = authVM.currentUser?.id {
                await projectsVM.fetchMyPendingProjects(ownerId: userId)
            }
            isSaving = false
            showAddedAlert = true
            dismiss()
        } else {
            isSaving = false
        }
    }
}
