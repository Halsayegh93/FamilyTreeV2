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
    /// دخول البطاقات مرة واحدة عند ظهور الشبكة (نمط الأخبار والديوانيات)
    @State private var appeared = false

    @Environment(\.verticalSizeClass) private var vSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// الوضع الأفقي — أعمدة أكثر لاستغلال العرض
    private var isLandscape: Bool { vSizeClass == .compact }

    private var gridColumns: [GridItem] {
        if isLandscape {
            return [GridItem(.adaptive(minimum: DS.Landscape.gridCardMinWidth, maximum: .infinity), spacing: DS.Spacing.md, alignment: .top)]
        }
        // بطاقتان صغيرتان في الصف (طلب المالك ٢٠٢٦-١٠-٢٣ «مربعين يم بعض»)
        return [
            GridItem(.flexible(), spacing: DS.Spacing.md, alignment: .top),
            GridItem(.flexible(), spacing: DS.Spacing.md, alignment: .top)
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
        .onAppear { NewContentTracker.shared.markSeen(.projects) }   // «النقاط الصفراء»: فُتح القسم
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
                    .dsSectionPage(.projects)   // الصفحة تحته «تختفي» — المربّع يبقي القسم الحالي
            }
            .background(ClearPresentationBackground())
        }
        .transaction { t in
            if showingAddProject { t.disablesAnimations = true }
        }
        .dsAlert(
            L10n.t("تم إرسال المشروع", "Project Submitted"),
            isPresented: $showAddedAlert,
            moment: .sentForApproval
        ) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(L10n.t(
                "تم إرسال مشروعك للمراجعة. سيظهر بعد موافقة الإدارة.",
                "Your project has been submitted for review. It will appear after admin approval."
            ))
        }
        // تفاصيل المشروع — مربّع كبير بالمنتصف (طلب المالك ٢٠٢٦-١٠-٢٣، مثل تفاصيل العضو):
        // يتمرّر داخله، يُغلق بـ× أو بالضغط خارجه
        // المربّع صلب (أبيض/سطح الداكن) وما خلفه أغمق (طلب المالك ٢٠٢٦-١٠-٢٣)
        .dsCenterBox(item: $selectedProject, onBackgroundTap: { selectedProject = nil },
                     dim: DSCenterPanelDim.strong) { project in
            ProjectDetailView(project: project)
                .environmentObject(projectsVM)
                .environmentObject(authVM)
        }
        .fullScreenCover(item: $projectToEdit) { project in
            DSCenterPanel(onBackgroundTap: nil, hugsContent: true) {
                EditProjectView(project: project, didEdit: $didEditProject)
                    .environmentObject(projectsVM)
                    .environmentObject(authVM)
                    .dsSectionPage(.projects)
            }
            .background(ClearPresentationBackground())
        }
        .transaction { t in if projectToEdit != nil { t.disablesAnimations = true } }
        .dsAlert(L10n.t("إبلاغ عن مشروع", "Report Project"), isPresented: Binding(
            get: { projectToReport != nil },
            set: { if !$0 { projectToReport = nil } }
        )) {
            TextField(L10n.t("سبب الإبلاغ (اختياري)", "Reason (optional)"), text: $reportReason)
                .dsAlertField()
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
        // «داخل … المشاريع بعد» (طلب المالك ٢٠٢٦-١٠-٠٥): الصفحة وكل ما يُفتح منها بلون
        // المشاريع — مثل التبويبات (البيئة + AppSection.current للرسائل ومربّع التاريخ)
        .dsSectionPage(.projects)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if projectsVM.isLoading && projectsVM.projects.isEmpty && projectsVM.myPendingProjects.isEmpty {
            // التحميل الموحّد: مجسّم المشاريع يتنفّس
            DSPageLoader(section: .projects)
        } else if currentItems.isEmpty {
            emptyStateView
                .dsStaggerIn(0)   // الحالة الفارغة تصعد وتظهر (تلاشٍ فقط مع «تقليل الحركة»)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: gridColumns, spacing: DS.Spacing.md) {
                    ForEach(Array(currentItems.enumerated()), id: \.element.id) { index, project in
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
                                .padding(DS.Spacing.xsm)   // داخل زاوية الصورة
                            }
                        }
                        .contextMenu {
                            if !selectionMode {
                                projectActionsMenu(for: project)
                            }
                        }
                        // نمط الأخبار والديوانيات: البطاقات تصعد وتظهر تباعاً (أول ٧) مرة عند الظهور
                        .dsCardCascade(index, appeared: appeared)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                // البطاقات تبدأ تحت الرأس بمسافة (طلب المالك ٢٠٢٦-١٠-٢٣ — كانت ملاصقة له)، مثل المكتبة
                .padding(.top, hasToolbarRow ? DS.Spacing.xs : DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xxxxl)
                .onAppear { appeared = true }
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
            if project.approvalStatus == "approved" {
                Button {
                    Task { await projectsVM.togglePinned(id: project.id) }
                } label: {
                    Label(
                        project.isPinned
                            ? L10n.t("إلغاء التثبيت", "Unpin")
                            : L10n.t("تثبيت في الأعلى", "Pin to top"),
                        systemImage: project.isPinned ? "pin.slash.fill" : "pin.fill"
                    )
                }
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
            .dsGlyph(DS.Glyph.mdCompact, weight: .black)
            .foregroundColor(DS.Color.textSecondary)
            .frame(width: DS.Icon.discMini, height: DS.Icon.discMini)
            .background(Circle().fill(DS.Color.surface))
            .overlay(Circle().strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
            .dsSubtleShadow()
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
                // الشريحة الموحّدة بلون المعنى (بانتظار = تحذير) والعدد بعد النص
                DSChipButton(authVM.isAdmin ? L10n.t("بانتظار", "Pending") : L10n.t("طلباتي", "Mine"),
                             icon: "clock.fill", tint: DS.Color.warning, isSelected: on, count: pendingCount) {
                    // تبديل القائمة بنابض هادئ مثل فلتر الديوانيات — «تقليل الحركة»: تلاشٍ قصير
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.15)
                                               : .spring(response: 0.4, dampingFraction: 0.85)) {
                        filter = on ? .approved : .pending
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Selection UI

    private var selectionTopBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSChipButton(L10n.t("إلغاء", "Cancel"), tint: DS.Color.error) { exitSelectionMode() }
            Spacer()
            Text(L10n.t("اختيار \(selectedIDs.count)", "Selected \(selectedIDs.count)"))
                .dsFont(.rowTitleCompact)
                .foregroundColor(DS.Color.textPrimary)
            Spacer()
            DSChipButton(allSelected ? L10n.t("إلغاء الكل", "Clear all") : L10n.t("تحديد الكل", "Select all")) {
                toggleSelectAll()
            }
        }
        .padding(.horizontal, DS.Spacing.xs)
        // البطاقة الواحدة (`.dsCard`)
        .dsCard(padding: DS.Spacing.xxs)
    }

    private func selectionCheckmark(for id: UUID) -> some View {
        let isSelected = selectedIDs.contains(id)
        return Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .dsGlyph(DS.Glyph.xxl)
            .foregroundColor(isSelected ? DS.Color.textOnPrimary : DS.Color.textSecondary)
            .background(
                Circle()
                    .fill(isSelected ? AppSection.projects.ink : DS.Color.overlayText)
                    .frame(width: DS.Icon.section, height: DS.Icon.section)
            )
            .dsSubtleShadow()
            .padding(DS.Spacing.sm)
    }

    private var selectionBottomBar: some View {
        HStack(spacing: DS.Spacing.md) {
            Spacer()
            // الزرّ الواحد بدور الحذف (أحمر)
            DSButton(L10n.t("حذف", "Delete"), icon: "trash.fill", role: .destructive, fullWidth: false) {
                showBatchDeleteAlert = true
            }
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .dsGlass(Rectangle())
        .overlay(
            Rectangle().fill(DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke)).frame(height: DS.Border.width),
            alignment: .top
        )
    }

    // MARK: - Project Card — `ProjectGridCard` (نوع مستقل — حارس المكدس)

    private func projectCard(_ project: Project) -> some View {
        ProjectGridCard(project: project)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        // الصفحة الفاضية الموحّدة: مجسّم المشاريع (أو ساعة الطلبات المعلّقة) + عنوان + سطر
        DSEmptyView(filter == .pending ? L10n.t("لا توجد طلبات معلَّقة", "No pending requests")
                                       : L10n.t("لا توجد مشاريع بعد", "No projects yet"),
                    message: filter == .pending
                        ? L10n.t("سيظهر هنا أي طلب مشروع جديد", "Any new project request will appear here")
                        : L10n.t("اضغط + لإضافة مشروع جديد", "Tap + to add a new project"),
                    section: .projects,
                    icon: filter == .pending ? "clock.badge" : nil)
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

// MARK: - بطاقة المشروع في القائمة (طلب المالك ٢٠٢٦-١٠-٢٢/٢٣)
/// بطاقة صغيرة شبه مربّعة (بطاقتان في الصف): صورة المشروع تملأ أعلاها بزوايا ناعمة، وتحتها اسم المشروع
/// في الوسط فقط — بلا اسم صاحب المشروع وبلا أيقونات الحسابات (تبقى في صفحة المشروع).
struct ProjectGridCard: View {
    let project: Project

    /// صورة البطاقة الصغيرة ١٦:١٠ — أقصر من ٤:٣ السابقة (طلب المالك ٢٠٢٦-١٠-٢٣ «أصغر»)
    static let imageAspect: CGFloat = 16.0 / 10.0
    /// شعار المشروع حين لا صورة — أكبر (كان ٥٢) فيملأ أغلب ارتفاع الصورة بحاشية ضيّقة (طلب المالك ٢٠٢٦-١٠-٢٣)
    static let logoSize: CGFloat = 76

    private var isPending: Bool { project.approvalStatus == "pending" }
    private var imageRadius: CGFloat { max(DS.Card.radius - DS.Spacing.xs, DS.Radius.sm) }

    var body: some View {
        VStack(spacing: DS.Spacing.xsm) {
            Color.clear
                .aspectRatio(Self.imageAspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay { ProjectHeroImage(project: project, markSize: Self.logoSize) }
                .clipShape(RoundedRectangle(cornerRadius: imageRadius, style: .continuous))

            Text(project.title)
                .dsFont(.rowTitleCompact)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DS.Spacing.xxs)
                .padding(.bottom, DS.Spacing.xxs)
        }
        // البطاقة الواحدة (`.dsCard`) + إطار «بانتظار» فوقها
        .dsCard(padding: DS.Spacing.xs)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
                .strokeBorder(isPending ? DS.Color.warning.opacity(DS.Opacity.tintStroke) : .clear,
                              lineWidth: DS.Border.width)
        )
        .overlay(alignment: .topLeading) {
            if isPending {
                statusBadge(icon: "clock.fill", text: L10n.t("بانتظار", "Pending"), color: DS.Color.warningFill)
            } else if project.isHidden {
                statusBadge(icon: "eye.slash.fill", text: L10n.t("مخفي", "Hidden"), color: DS.Color.slateFill)
            }
        }
        // شارة التثبيت: الزاوية المقابلة (يمين) أسفل زر ••• حتى لا تتزاحم معه ولا مع شارات الحالة
        .overlay(alignment: .topTrailing) {
            if project.isPinned && !isPending {
                pinBadge
                    .padding(.top, DS.Icon.discMini + DS.Spacing.sm)
                    .padding(.trailing, DS.Spacing.sm)
            }
        }
        .opacity(isPending || project.isHidden ? DS.Opacity.dimmed : 1.0)
    }

    /// دبوس صغير ممتلئ بلون القسم — يدلّ على أن البطاقة مثبَّتة في الأعلى.
    private var pinBadge: some View {
        Image(systemName: "pin.fill")
            .dsGlyph(DS.Glyph.micro)
            .foregroundColor(DS.Color.textOnPrimary)
            .padding(DS.Spacing.xs)
            .background(Circle().fill(DS.Color.accent))
            .accessibilityLabel(L10n.t("مثبّت", "Pinned"))
    }

    private func statusBadge(icon: String, text: String, color: Color) -> some View {
        // فوق الصورة: ممتلئة بلون معناها حتى تُقرأ
        HStack(spacing: DS.Spacing.xxs) {
            Image(dsSymbol: icon).dsGlyph(DS.Glyph.micro)
            Text(text).dsFont(.micro)
        }
        .foregroundColor(DS.Color.textOnPrimary)
        .padding(.horizontal, DS.Spacing.xsm).padding(.vertical, DS.Spacing.xxs)
        .background(Capsule().fill(color))
        .padding(DS.Spacing.sm)
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
    /// بعد المربّع: «هل أنت صاحب المشروع؟» (طلب المالك ٢٠٢٦-١٠-٢٥) — «لا» = بلا اسمه على المشروع
    @State private var askOwnership = false

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    @State private var accountsBoxOpen = false
    private let tint = DS.Color.tileProjects

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
            onSubmit: { askOwnership = true },
            onCancel: { dismiss() }
        ) {
            // ── الهوية: الشعار + الاسم + الوصف ──
            DSComposerSection(title: L10n.t("هوية المشروع", "Project Identity"), icon: "sparkles", tint: tint, index: 0) {
                DSComposerLogoPicker(image: $logoImage, tint: tint)
                    .padding(.bottom, DS.Spacing.xxs)
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
                DSComposerPhotoStrip(images: $photoImages, limit: projectPhotosLimit, tint: tint)
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
        .dsAlert(L10n.t("هل أنت صاحب المشروع؟", "Are you the project owner?"),
                 isPresented: $askOwnership, icon: "person.crop.circle.badge.questionmark") {
            Button(L10n.t("نعم، أنا صاحبه", "Yes, it's mine")) { Task { await saveProject(isOwner: true) } }
            Button(L10n.t("لا", "No")) { Task { await saveProject(isOwner: false) } }
            Button(L10n.t("رجوع", "Back"), role: .cancel) {}
        } message: {
            Text(L10n.t("إذا اخترت «لا» ما يظهر اسمك على المشروع، والإدارة تحدّد صاحبه.",
                        "If you choose No, your name won't show on the project; the admins can set its owner."))
        }
    }

    /// «نعم» = اسمه صاحباً للمشروع؛ «لا» = بلا اسم (يبقى السجل باسمه للتعديل — `owner_id` شرط RLS،
    /// وتحدّد الإدارة الصاحب من «تعديل المشروع»)
    private func saveProject(isOwner: Bool) async {
        guard let currentUser = authVM.currentUser else { return }
        isSaving = true

        let ownerId = currentUser.id
        let ownerName = isOwner ? currentUser.displayFullName : ""

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
            submitterName: currentUser.displayFullName,
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
