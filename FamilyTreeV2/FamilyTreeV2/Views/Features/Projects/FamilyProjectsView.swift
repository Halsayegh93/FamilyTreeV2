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

    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — أعمدة أكثر لاستغلال العرض
    private var isLandscape: Bool { vSizeClass == .compact }

    private var gridColumns: [GridItem] {
        if isLandscape {
            return [GridItem(.adaptive(minimum: 200, maximum: .infinity), spacing: DS.Spacing.md, alignment: .top)]
        }
        return [
            GridItem(.flexible(), spacing: DS.Spacing.md),
            GridItem(.flexible(), spacing: DS.Spacing.md)
        ]
    }

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
                } else if hasToolbarRow {
                    // التصنيفات أُزيلت (طلب المالك) — يبقى فقط زر الطلبات المعلّقة إن وُجدت؛
                    // زر التحديد انتقل لهيدر الصفحة
                    toolbarRow
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
                    DSFloatingButton(icon: "plus", color: DS.Color.primary) {
                        showingAddProject = true
                    }
                    .accessibilityLabel(L10n.t("إضافة مشروع", "Add Project"))
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
        // زر التحديد في هيدر الصفحة — للإدارة فقط
        .onReceive(NotificationCenter.default.publisher(for: .subPageStartSelection)) { note in
            guard authVM.isAdmin, (note.userInfo?["page"] as? String) == "projects" else { return }
            withAnimation(DS.Anim.snappy) {
                filter = .approved
                selectionMode = true
                selectedIDs = []
            }
        }
        .task {
            await projectsVM.fetchProjects()
            if let userId = authVM.currentUser?.id {
                await projectsVM.fetchMyPendingProjects(ownerId: userId)
            }
            if authVM.isAdmin {
                await projectsVM.fetchPendingProjects()
            }
        }
        // الإضافة مربّع بمنتصف الشاشة لا ورقة سفلية (طلب المالك)
        .fullScreenCover(isPresented: $showingAddProject) {
            DSCenterPanel(onBackgroundTap: nil, hugsContent: true) {
                AddProjectView(showAddedAlert: $showAddedAlert)
                    .environmentObject(projectsVM)
                    .environmentObject(authVM)
                    .environmentObject(memberVM)
            }
            .background(ClearPresentationBackground())
        }
        .transaction { t in
            if showingAddProject { t.disablesAnimations = true }
        }
        .dsAlert(
            L10n.t("تم إرسال المشروع", "Project Submitted"),
            isPresented: $showAddedAlert
        ) {
            Button(L10n.t("حسناً", "OK")) {}
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
        .fullScreenCover(item: $projectToEdit) { project in
            DSCenterPanel(onBackgroundTap: nil, hugsContent: true) {
                EditProjectView(project: project, didEdit: $didEditProject)
                    .environmentObject(projectsVM)
                    .environmentObject(authVM)
            }
            .background(ClearPresentationBackground())
        }
        .transaction { t in if projectToEdit != nil { t.disablesAnimations = true } }
        .dsAlert(L10n.t("إبلاغ عن مشروع", "Report Project"), isPresented: Binding(
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
        .dsAlert(L10n.t("تم الإبلاغ", "Reported"), isPresented: $reportSent) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(L10n.t("شكراً لك، وصل بلاغك للإدارة وستتم مراجعته خلال ٢٤ ساعة.", "Thank you — your report reached the admins and will be reviewed within 24 hours."))
        }
        .dsAlert(L10n.t("حذف المشروع", "Delete project"),
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
        .dsAlert(L10n.t("حذف المشاريع المختارة", "Delete selected"),
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
                        .overlay(alignment: .topTrailing) {
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
            // الموافقة/الرفض من زر النقاط مباشرة — للإدارة فقط (طلب المالك)
            if project.approvalStatus == "pending" {
                Button {
                    Task {
                        if let approverId = authVM.currentUser?.id {
                            await projectsVM.approveProject(id: project.id, approvedBy: approverId)
                        }
                    }
                } label: {
                    Label(L10n.t("موافقة", "Approve"), systemImage: "checkmark.circle.fill")
                }
                Button {
                    Task { await projectsVM.rejectProject(id: project.id) }
                } label: {
                    Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                }
                Divider()
            }
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
            .foregroundColor(DS.Color.textSecondary)
            .frame(width: 26, height: 26)
            .background(Circle().fill(DS.Color.surface))
            .overlay(Circle().strokeBorder(DS.Color.textTertiary.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
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

    private var pendingCount: Int {
        authVM.isAdmin ? projectsVM.pendingProjects.count : projectsVM.myPendingProjects.count
    }

    private var hasToolbarRow: Bool { pendingCount > 0 || filter == .pending }

    private var toolbarRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            if pendingCount > 0 || filter == .pending {
                let on = filter == .pending
                Button {
                    withAnimation(DS.Anim.snappy) { filter = on ? .approved : .pending }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "clock.fill")
                            .font(DS.Font.scaled(12, weight: .bold))
                        Text(authVM.isAdmin ? L10n.t("بانتظار", "Pending") : L10n.t("طلباتي", "Mine"))
                            .font(DS.Font.scaled(12, weight: .bold))
                        Text("\(pendingCount)")
                            .font(DS.Font.scaled(11, weight: .heavy))
                    }
                    .foregroundColor(on ? .white : DS.Color.warning)
                    .padding(.horizontal, DS.Spacing.md)
                    .frame(height: 34)
                    .background(Capsule().fill(on ? DS.Color.warning : DS.Color.warning.opacity(0.12)))
                }
                .buttonStyle(DSScaleButtonStyle())
            }

            Spacer(minLength: 0)
        }
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
        .dsGlass(Rectangle())
        .overlay(
            Rectangle().fill(DS.Color.textTertiary.opacity(0.15)).frame(height: 0.5),
            alignment: .top
        )
    }

    // MARK: - Project Card — بطاقة بغلاف مقوّس وشعار بارز (نفس روح صفحة المشروع)

    private func projectCard(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // غلاف صغير بخلفية قسم المشاريع — بحافة مقوّسة
            ProjectSectionBackdrop(symbolSize: 16)
            .frame(height: cardCoverHeight)
            .frame(maxWidth: .infinity)
            .clipShape(ProjectCoverArc(depth: 18))

            VStack(alignment: .leading, spacing: 3) {
                Text(project.title)
                    .font(DS.Font.plex(13, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(DS.Font.scaled(10, weight: .bold))
                    Text(project.ownerName)
                        .font(DS.Font.plex(11, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundColor(DS.Color.textSecondary)

                if project.hasSocialLinks {
                    socialIndicators(project: project)
                        .padding(.top, 3)
                }
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.top, cardLogoSize / 2 + 2)
            .padding(.bottom, DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(alignment: .top) { cardLogo(project).offset(y: cardCoverHeight - cardLogoSize / 2 + 2) }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(project.approvalStatus == "pending"
                        ? DS.Color.warning.opacity(0.30)
                        : DS.Color.primary.opacity(0.08),
                        lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            if project.approvalStatus == "pending" {
                statusBadge(icon: "clock.fill", text: L10n.t("بانتظار", "Pending"), color: DS.Color.warning)
            } else if project.isHidden {
                statusBadge(icon: "eye.slash.fill", text: L10n.t("مخفي", "Hidden"), color: DS.Color.textTertiary)
            }
        }
        .opacity(project.approvalStatus == "pending" || project.isHidden ? 0.85 : 1.0)
        .dsSubtleShadow()
    }

    private var cardCoverHeight: CGFloat { 74 }
    private var cardLogoSize: CGFloat { 52 }

    /// شعار المشروع على حافة الغلاف — مربّع بزوايا ناعمة بإطار بلون البطاقة
    private func cardLogo(_ project: Project) -> some View {
        Group {
            if let logoUrl = project.logoUrl, let url = URL(string: logoUrl) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: { DS.Color.mutedBackground }
            } else {
                ZStack {
                    DS.Color.primary.opacity(0.12)
                    Image(systemName: "briefcase.fill")
                        .font(DS.Font.scaled(18, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                }
            }
        }
        .frame(width: cardLogoSize, height: cardLogoSize)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.surface, lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.15), radius: 5, x: 0, y: 2)
    }

    private func statusBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(DS.Font.scaled(10, weight: .bold))
            Text(text).font(DS.Font.scaled(10, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(color))
        .padding(DS.Spacing.xs)
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
            .font(DS.Font.scaled(11, weight: .bold))
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
    /// صور المشروع الجديدة (تُرفع عند الإضافة)
    @State private var photoImages: [UIImage] = []
    @State private var noExistingPhotos: [String] = []
    @State private var isSaving = false
    @State private var selectedOwnerId: UUID?
    @State private var showMemberPicker = false
    @State private var memberSearchText = ""
    // طي/فتح قسم روابط التواصل (محتوى كبير) لإبقاء الشيت مضغوطاً.
    @State private var contactsOpen = true

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    @State private var accountsBoxOpen = false
    private let tint = DS.Color.composerProject

    private var filledAccounts: Int {
        [phoneNumber, whatsappNumber, instagramUrl, twitterUrl, websiteUrl, locationUrl]
            .filter(ProjectContactTiles.isFilled).count
    }

    /// ما أدخله المستخدم ولم يُرسل (نص، شعار، صور، حسابات) — «إلغاء» يسأل قبل التجاهل
    /// (توصية أبل). «+965 » المبدئي في واتساب لا يُعدّ حساباً.
    private var hasUnsavedChanges: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || logoImage != nil
            || !photoImages.isEmpty
            || filledAccounts > 0
    }

    var body: some View {
        DSComposer(
            title: L10n.t("مشروع جديد", "New Project"),
            subtitle: L10n.t("عرّف العائلة بمشروعك", "Introduce your project to the family"),
            icon: "briefcase.fill",
            tint: tint,
            actionTitle: authVM.isAdmin ? L10n.t("إضافة المشروع", "Add Project") : L10n.t("إرسال للمراجعة", "Submit"),
            actionIcon: "sparkles",
            canSubmit: canSubmit,
            isBusy: isSaving,
            note: authVM.isAdmin ? nil : L10n.t("يظهر لك فوراً، وللجميع بعد موافقة الإدارة", "Visible to you now, to everyone after approval"),
            isBehindExtra: accountsBoxOpen,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: { Task { await saveProject() } },
            onCancel: { dismiss() }
        ) {
            // ── الهوية: الشعار + الاسم + الوصف ──
            DSComposerSection(title: L10n.t("هوية المشروع", "Project Identity"), icon: "sparkles", tint: tint, index: 0) {
                DSComposerLogoPicker(image: $logoImage, tint: tint, size: 88)
                    .padding(.bottom, 2)
                DSComposerField(icon: "textformat", label: L10n.t("اسم المشروع *", "Project name *"),
                                placeholder: L10n.t("مثال: مخبز البيت", "e.g. Home Bakery"),
                                text: $title, tint: tint, limit: 60)
                DSComposerField(icon: "text.alignright", label: L10n.t("وصف مختصر", "Short description"),
                                placeholder: L10n.t("سطر يعرّف بالمشروع وما يقدّمه", "One line about what it offers"),
                                text: $description, tint: tint, multiline: true, limit: 160)
            }

            // ── الصور ──
            DSComposerSection(title: L10n.t("صور المشروع", "Project Photos"), icon: "photo.on.rectangle.angled",
                              tint: tint, trailing: "\(photoImages.count)/\(projectPhotosLimit)", index: 1) {
                DSComposerPhotoStrip(images: $photoImages, limit: projectPhotosLimit, tint: tint, size: 80)
            }

            // ── حسابات التواصل ──
            DSComposerSection(title: L10n.t("حسابات التواصل", "Contact Accounts"), icon: "link", tint: tint,
                              trailing: filledAccounts == 0 ? L10n.t("اختياري", "Optional") : "\(filledAccounts)",
                              index: 2) {
                ProjectAccountsEditor(phone: $phoneNumber, whatsapp: $whatsappNumber,
                                      instagram: $instagramUrl, twitter: $twitterUrl,
                                      website: $websiteUrl, location: $locationUrl,
                                      tint: tint,
                                      onExtraChange: { accountsBoxOpen = $0 })
            }
        }
        .dsTallBox(isPresented: $showMemberPicker) { memberPickerSheet }   // قائمة أعضاء طويلة (توصية أبل)
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

    // MARK: - Hero photo (شعار المشروع — مطابق صورة إضافة ابن)

    private var heroHeader: some View {
        DSProfilePhotoPicker(
            selectedImage: $logoImage,
            enableCrop: true,
            cropShape: .circle,
            trailing: L10n.t("شعار (اختياري)", "Logo (Optional)"),
            compactEmptyState: true,
            useOverlayActionsOnly: true,
            avatarSize: 54
        )
    }

    // MARK: - Card: Basics

    private var basicsCard: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("معلومات المشروع", "Project Info"),
                icon: "briefcase.fill",
                iconColor: DS.Color.primary
            )

            VStack(spacing: 0) {
                DSLabeledFieldRow(icon: "textformat", iconColor: DS.Color.primary,
                                  label: L10n.t("اسم المشروع *", "Project Name *")) {
                    TextField(L10n.t("اسم المشروع", "Project name"), text: $title)
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textPrimary)
                }

                DSDivider()

                DSLabeledFieldRow(icon: "text.alignleft", iconColor: DS.Color.accent,
                                  label: L10n.t("وصف مختصر", "Short Description")) {
                    TextField(L10n.t("اختياري", "Optional"), text: $description, axis: .vertical)
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1...2)
                }
            }
        }
    }

    // MARK: - Card: Owner

    private var ownerCard: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("صاحب المشروع", "Project Owner"),
                icon: "person.crop.circle.badge.checkmark",
                iconColor: DS.Color.primary
            )

            DSLabeledFieldRow(icon: "person.fill", iconColor: DS.Color.primary,
                              label: L10n.t("العضو", "Member")) {
                Button { showMemberPicker = true } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        if let ownerId = selectedOwnerId,
                           let member = memberVM.member(byId: ownerId) {
                            Text(member.displayFullName)
                                .font(DS.Font.callout)
                                .foregroundColor(DS.Color.textPrimary)
                                .lineLimit(1)
                        } else {
                            Text((authVM.currentUser?.displayFullName ?? "") + L10n.t(" (أنت)", " (You)"))
                                .font(DS.Font.callout)
                                .foregroundColor(DS.Color.textPrimary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Card: Contact Links

    private var contactLinksCard: some View {
        let filled = [phoneNumber, whatsappNumber, instagramUrl, twitterUrl, websiteUrl, locationUrl]
            .filter(ProjectContactTiles.isFilled).count
        return DSCard(padding: 0) {
            // رأس قابل للطي.
            Button {
                withAnimation(DS.Anim.quick) { contactsOpen.toggle() }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "link")
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(DS.Color.success)
                    Text(L10n.t("حسابات التواصل", "Contact Accounts"))
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                    Spacer()
                    Text(filled > 0 ? "\(filled)" : L10n.t("اختياري", "Optional"))
                        .font(DS.Font.scaled(11, weight: .semibold))
                        .foregroundColor(filled > 0 ? DS.Color.success : DS.Color.textTertiary)
                    Image(systemName: contactsOpen ? "chevron.up" : "chevron.down")
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                }
                .padding(DS.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if contactsOpen {
                // مربّعات — كل حساب يفتح مربّعاً بالمنتصف (طلب المالك)
                ProjectContactTiles(phone: $phoneNumber, whatsapp: $whatsappNumber,
                                    instagram: $instagramUrl, twitter: $twitterUrl,
                                    website: $websiteUrl, location: $locationUrl)
                    .padding([.horizontal, .bottom], DS.Spacing.md)
            }
        }
    }

    /// حقل رابط مدمج (أيقونة + إدخال) لشبكة العمودين — يقلّص الارتفاع.
    private func compactLink(icon: String, color: Color, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(DS.Font.scaled(13, weight: .semibold))
                .foregroundColor(color)
            TextField(placeholder, text: text)
                .font(DS.Font.scaled(13))
                .foregroundColor(DS.Color.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.textTertiary.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Member Picker Sheet

    /// اختيار صاحب المشروع — مربّع بمنتصف الشاشة بتصميم المربّعات الموحّد: بحث ثم
    /// الأعضاء صفوفاً والمختار بعلامة ✓. الضغط على عضو يختاره ويغلق المربّع (كالسابق)،
    /// و«إعادة تعيين» (كانت بجهة التأكيد في الشريط العلوي) صارت زر الإجراء أسفل المربّع.
    private var memberPickerSheet: some View {
        let list = filteredMembers
        let projectTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return DSComposer(
            title: L10n.t("اختيار صاحب المشروع", "Select Project Owner"),
            subtitle: projectTitle.isEmpty ? L10n.t("مشروع جديد", "New Project") : projectTitle,
            icon: "person.crop.circle.badge.checkmark",
            tint: tint,
            actionTitle: L10n.t("إعادة تعيين", "Reset"),
            actionIcon: "arrow.counterclockwise",
            cancelTitle: L10n.t("إلغاء", "Cancel"),
            canSubmit: true,
            onSubmit: {
                selectedOwnerId = nil
                showMemberPicker = false
                memberSearchText = ""
            },
            onCancel: {
                showMemberPicker = false
                memberSearchText = ""
            }
        ) {
            DSComposerField(icon: "magnifyingglass",
                            label: L10n.t("بحث", "Search"),
                            placeholder: L10n.t("بحث عن عضو...", "Search member..."),
                            text: $memberSearchText,
                            tint: tint)
                .dsStaggerIn(0)

            DSComposerSection(title: L10n.t("الأعضاء", "Members"), icon: "person.2.fill",
                              tint: tint, index: 1) {
                if list.isEmpty {
                    Text(L10n.t("لا توجد نتائج", "No results"))
                        .font(DS.Font.plex(13, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                } else {
                    memberPickerRows(list)
                }
            }
        }
    }

    /// صفوف الأعضاء — كسولة للقوائم الطويلة (نتائج البحث قد تكون آلافاً)، وعادية
    /// للقصيرة حتى يُقاس ارتفاع المربّع كاملاً (الكسولة تُبلِّغ ارتفاعاً ناقصاً للقصيرة)
    @ViewBuilder
    private func memberPickerRows(_ list: [FamilyMember]) -> some View {
        if list.count > 40 {
            LazyVStack(spacing: DS.Spacing.sm) {
                ForEach(list) { member in memberPickerRow(member) }
            }
        } else {
            VStack(spacing: DS.Spacing.sm) {
                ForEach(list) { member in memberPickerRow(member) }
            }
        }
    }

    /// صف عضو: الصورة + الاسم، والمختار بعلامة ✓ وإطار بلون القسم
    private func memberPickerRow(_ member: FamilyMember) -> some View {
        let isSelected = selectedOwnerId == member.id
        return Button {
            selectedOwnerId = member.id
            showMemberPicker = false
            memberSearchText = ""
        } label: {
            HStack(spacing: DS.Spacing.sm) {
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

                Text(member.displayFullName)
                    .font(DS.Font.plex(14.5, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? DS.Color.fieldLabel : DS.Color.fieldValue)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Spacer(minLength: 0)

                if isSelected {
                    // الاختيار يُقرأ من سمة «مُختار» على الصف
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(tint)
                        .accessibilityHidden(true)
                }
            }
            .dsRowBox()
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(tint.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        .accessibilityHidden(true)   // زخرفة — الاسم يُقرأ
    }

    private var filteredMembers: [FamilyMember] {
        let active = memberVM.allMembers.filter { $0.status == .active && $0.isDeceased != true }
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

        // المنشئ هو صاحب المشروع (تعيين صاحب آخر صار في تعديل المشروع للإدارة).
        let ownerId = currentUser.id
        let ownerName = currentUser.fullName

        // Upload logo if selected
        var uploadedLogoUrl: String? = nil
        if let logoImage {
            let projectId = UUID()
            if let data = ImageProcessor.process(logoImage, for: .projectLogo) {
                uploadedLogoUrl = await projectsVM.uploadLogo(imageData: data, projectId: projectId)
            }
        }

        // رفع صور المعرض
        var photoUrls: [String] = []
        for img in photoImages {
            if let data = ImageProcessor.process(img, for: .projectLogo),
               let url = await projectsVM.uploadProjectPhoto(imageData: data) {
                photoUrls.append(url)
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
            locationUrl: locationUrl.isEmpty ? nil : locationUrl,
            imageUrls: photoUrls
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
