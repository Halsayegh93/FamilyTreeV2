import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers

/// شاشة أرشيف العائلة — وثائق وكتب وصور قديمة. الكل يقدر يتصفّح ويُحمّل،
/// الرفع/الحذف للمدراء فقط (owner + admin).
struct FamilyArchiveView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @StateObject private var archiveVM = FamilyArchiveViewModel()

    /// nil = الكل
    @State private var selectedCategory: ArchiveItem.Category? = nil
    @State private var showingUpload = false
    @State private var selectedItem: ArchiveItem? = nil
    @State private var itemToDelete: ArchiveItem? = nil
    @State private var itemToEdit: ArchiveItem? = nil
    @State private var itemToReport: ArchiveItem? = nil
    @State private var itemToApprove: ArchiveItem? = nil
    @State private var itemToReject: ArchiveItem? = nil
    @State private var reportReason = ""
    @State private var reportSent = false

    // وضع التحديد المتعدّد (للمدراء فقط)
    @State private var selectionMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showBatchDeleteAlert = false

    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — أعمدة أكثر لاستغلال العرض
    private var isLandscape: Bool { vSizeClass == .compact }

    /// ضلع بطاقة المكتبة — محسوب من عرض الشاشة وعدد الأعمدة والهوامش،
    /// حتى تبقى البطاقة مربّعة فعلاً ولا تتمدّد خارج القسم (طلب المالك).
    private var cardSide: CGFloat {
        let width = UIScreen.main.bounds.width
        let columns: CGFloat = isLandscape ? max(2, floor((width - DS.Spacing.lg * 2) / 210)) : 2
        let gaps = DS.Spacing.sm * (columns - 1)
        let side = (width - DS.Spacing.lg * 2 - gaps) / columns
        return max(130, side)
    }

    private var gridColumns: [GridItem] {
        if isLandscape {
            return [GridItem(.adaptive(minimum: 190, maximum: .infinity), spacing: DS.Spacing.sm, alignment: .top)]
        }
        return [
            GridItem(.flexible(), spacing: DS.Spacing.sm),
            GridItem(.flexible(), spacing: DS.Spacing.sm)
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // شريط التحديد العلوي يحلّ محل صف الفئات في وضع التحديد
                if selectionMode {
                    selectionTopBar
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.xs)
                        .transition(.opacity)
                }

                // التصنيفات أُزيلت، وزر التحديد انتقل لهيدر الصفحة (للإدارة فقط)

                if archiveVM.isLoading && archiveVM.items.isEmpty {
                    Spacer()
                    ProgressView().tint(DS.Color.primary)
                    Spacer()
                } else if archiveVM.items(in: selectedCategory).isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: gridColumns, spacing: DS.Spacing.sm) {
                            ForEach(archiveVM.items(in: selectedCategory)) { item in
                                Button {
                                    if selectionMode {
                                        toggleSelection(item.id)
                                    } else {
                                        selectedItem = item
                                    }
                                } label: {
                                    archiveCard(item)
                                        .overlay(alignment: .topLeading) {
                                            if selectionMode {
                                                selectionCheckmark(for: item.id)
                                            }
                                        }
                                }
                                .buttonStyle(DSScaleButtonStyle())
                                // زر قائمة ظاهر — كـ overlay على الزر نفسه حتى ما
                                // يتعارض ضغطه مع ضغط البطاقة. الإدارة: تحكّم كامل،
                                // غيرهم: إبلاغ فقط (لغير عناصرهم).
                                .overlay(alignment: .topTrailing) {
                                    if !selectionMode && menuHasActions(for: item) {
                                        Menu {
                                            archiveActionsMenu(for: item)
                                        } label: {
                                            cardMenuBadge
                                        }
                                        .padding(.trailing, 4)
                                        .padding(.top, 2)
                                    }
                                }
                                .contextMenu {
                                    if !selectionMode {
                                        archiveActionsMenu(for: item)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.md)
                        .padding(.bottom, DS.Spacing.xxxxl)
                    }
                    .refreshable { await archiveVM.fetchItems() }
                }
            }

            // زر رفع — متاح للجميع، يختفي فقط في وضع التحديد
            if !selectionMode {
                HStack {
                    Spacer()
                    DSFloatingButton(icon: "plus", color: DS.Color.primary) {
                        showingUpload = true
                    }
                    .accessibilityLabel(L10n.t("إضافة", "Add"))
                    .padding(.trailing, DS.Spacing.xl)
                    .padding(.bottom, DS.Spacing.lg)
                }
            }

            // شريط الإجراءات السفلي في وضع التحديد
            if selectionMode {
                selectionBottomBar
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(DS.Anim.snappy, value: selectionMode)
        .task {
            archiveVM.configure(authVM: authVM, notificationVM: notificationVM)
            await archiveVM.fetchItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: .subPageStartSelection)) { note in
            guard authVM.isAdmin, (note.userInfo?["page"] as? String) == "archive" else { return }
            withAnimation(DS.Anim.snappy) {
                selectionMode = true
                selectedIDs = []
            }
        }
        .sheet(isPresented: $showingUpload) {
            ArchiveUploadSheet(archiveVM: archiveVM, defaultCategory: selectedCategory ?? .documents)
                .presentationDetents([.fraction(0.62)])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedItem) { item in
            ArchiveItemViewer(item: item, uploaderName: uploaderName(for: item))
        }
        .sheet(item: $itemToEdit) { item in
            ArchiveEditSheet(archiveVM: archiveVM, item: item)
                .presentationDetents([.fraction(0.62)])
                .presentationDragIndicator(.visible)
        }
        .dsAlert(L10n.t("إبلاغ عن عنصر", "Report Item"), isPresented: Binding(
            get: { itemToReport != nil },
            set: { if !$0 { itemToReport = nil } }
        )) {
            TextField(L10n.t("سبب الإبلاغ (اختياري)", "Reason (optional)"), text: $reportReason)
            Button(L10n.t("إبلاغ", "Report"), role: .destructive) {
                let target = itemToReport
                let reason = reportReason
                itemToReport = nil
                reportReason = ""
                if let target {
                    Task {
                        let ok = await notificationVM.reportContent(
                            contentKind: L10n.t("عنصر أرشيف", "archive item"),
                            contentLabel: target.title,
                            contentId: target.id,
                            reason: reason
                        )
                        if ok { await MainActor.run { reportSent = true } }
                    }
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { itemToReport = nil; reportReason = "" }
        } message: {
            Text(L10n.t("اكتب سبب الإبلاغ، وسيتم إرساله للإدارة لمراجعة هذا العنصر.",
                       "Enter a reason; it will be sent to the admins to review this item."))
        }
        .dsAlert(L10n.t("تم الإبلاغ", "Reported"), isPresented: $reportSent) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(L10n.t("شكراً لك، وصل بلاغك للإدارة.", "Thank you, your report reached the admins."))
        }
        .dsAlert(L10n.t("تأكيد الموافقة", "Confirm Approval"), isPresented: Binding(
            get: { itemToApprove != nil },
            set: { if !$0 { itemToApprove = nil } }
        )) {
            Button(L10n.t("موافقة", "Approve")) {
                if let target = itemToApprove { Task { await archiveVM.approveItem(target) } }
                itemToApprove = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { itemToApprove = nil }
        } message: {
            Text(L10n.t("هل تريد الموافقة على هذا العنصر؟ سيظهر لجميع الأعضاء.",
                       "Approve this item? It will be visible to all members."))
        }
        .dsAlert(L10n.t("تأكيد الرفض", "Confirm Rejection"), isPresented: Binding(
            get: { itemToReject != nil },
            set: { if !$0 { itemToReject = nil } }
        )) {
            Button(L10n.t("رفض", "Reject"), role: .destructive) {
                if let target = itemToReject { Task { await archiveVM.rejectItem(target) } }
                itemToReject = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { itemToReject = nil }
        } message: {
            Text(L10n.t("هل تريد رفض هذا العنصر؟", "Reject this item?"))
        }
        .dsAlert(L10n.t("حذف من الأرشيف", "Delete from archive"),
               isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
               )) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                if let item = itemToDelete {
                    Task { await archiveVM.deleteItem(item) }
                }
                itemToDelete = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { itemToDelete = nil }
        } message: {
            Text(L10n.t("حذف هذا العنصر نهائياً من الأرشيف؟",
                       "Permanently delete this item from the archive?"))
        }
        .dsAlert(L10n.t("حذف العناصر المختارة", "Delete selected items"),
               isPresented: $showBatchDeleteAlert) {
            Button(L10n.t("حذف \(selectedIDs.count)", "Delete \(selectedIDs.count)"),
                   role: .destructive) {
                let ids = selectedIDs
                Task {
                    await archiveVM.deleteItems(ids: ids)
                    await MainActor.run { exitSelectionMode() }
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("حذف \(selectedIDs.count) عنصر نهائياً من الأرشيف؟",
                       "Permanently delete \(selectedIDs.count) items from the archive?"))
        }
    }

    // MARK: - Selection Mode UI

    private var selectionTopBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button {
                exitSelectionMode()
            } label: {
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
                toggleSelectAllInCategory()
            } label: {
                Text(allInCategorySelected ? L10n.t("إلغاء الكل", "Clear all")
                                           : L10n.t("تحديد الكل", "Select all"))
                    .font(DS.Font.scaled(13, weight: .semibold))
                    .foregroundColor(DS.Color.primary)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.primary.opacity(0.18), lineWidth: 1)
        )
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
        let selected = archiveVM.items.filter { selectedIDs.contains($0.id) }
        let anyVisible = selected.contains { !$0.isHidden }
        let anyHidden = selected.contains { $0.isHidden }
        let isEmpty = selectedIDs.isEmpty

        return HStack(spacing: DS.Spacing.md) {
            // إخفاء (يظهر فقط إذا فيه عنصر مرئي ضمن التحديد)
            if anyVisible {
                actionPill(icon: "eye.slash.fill",
                           label: L10n.t("إخفاء", "Hide"),
                           color: DS.Color.warning) {
                    let ids = selectedIDs
                    Task {
                        await archiveVM.setHidden(ids: ids, hidden: true)
                        await MainActor.run { exitSelectionMode() }
                    }
                }
                .disabled(isEmpty)
            }

            // إظهار (يظهر فقط إذا فيه مخفي ضمن التحديد)
            if anyHidden {
                actionPill(icon: "eye.fill",
                           label: L10n.t("إظهار", "Show"),
                           color: DS.Color.success) {
                    let ids = selectedIDs
                    Task {
                        await archiveVM.setHidden(ids: ids, hidden: false)
                        await MainActor.run { exitSelectionMode() }
                    }
                }
                .disabled(isEmpty)
            }

            Spacer()

            // حذف
            actionPill(icon: "trash.fill",
                       label: L10n.t("حذف", "Delete"),
                       color: DS.Color.error) {
                showBatchDeleteAlert = true
            }
            .disabled(isEmpty)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .dsGlass(Rectangle())
        .overlay(
            Rectangle()
                .fill(DS.Color.textTertiary.opacity(0.15))
                .frame(height: 0.5),
            alignment: .top
        )
    }

    private func actionPill(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(12, weight: .bold))
                Text(label)
                    .font(DS.Font.scaled(13, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, 9)
            .background(Capsule().fill(color))
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Selection Helpers

    private var allInCategorySelected: Bool {
        let inCat = archiveVM.items(in: selectedCategory)
        guard !inCat.isEmpty else { return false }
        return inCat.allSatisfy { selectedIDs.contains($0.id) }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func toggleSelectAllInCategory() {
        let inCat = archiveVM.items(in: selectedCategory).map(\.id)
        if allInCategorySelected {
            for id in inCat { selectedIDs.remove(id) }
        } else {
            for id in inCat { selectedIDs.insert(id) }
        }
    }

    private func exitSelectionMode() {
        withAnimation(DS.Anim.snappy) {
            selectionMode = false
            selectedIDs = []
        }
    }

    // MARK: - Category Picker

    // MARK: - Premium Filter Bar
    // التصميم: حاوية ultraThinMaterial. الفلتر النشط = pill ممتدّ بلون فئته + اسم + عدّاد.
    // البقية = أيقونات دائرية بلون باهت. النقر على أيقونة يبدّل النشط بـ matched geometry.

    private var allCategoryAccent: Color { DS.Color.primary }
    private var allCategoryIcon: String { "square.grid.2x2.fill" }

    private func accentColor(for category: ArchiveItem.Category?) -> Color {
        category?.accentColor ?? allCategoryAccent
    }

    private func icon(for category: ArchiveItem.Category?) -> String {
        category?.iconName ?? allCategoryIcon
    }

    private func title(for category: ArchiveItem.Category?) -> String {
        if let c = category {
            return L10n.t(c.displayName, c.displayNameEn)
        }
        return L10n.t("الكل", "All")
    }

    // MARK: - Archive Card

    /// أيقونة PDF احتياطية (لو ما توفّر ملف لتوليد المصغّرة).
    private var pdfIconPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(DS.Color.primary.opacity(0.85))
            Text("PDF")
                .font(DS.Font.scaled(11, weight: .black))
                .foregroundColor(DS.Color.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(DS.Color.primary.opacity(0.15)))
        }
    }

    /// هل توجد إجراءات للمستخدم الحالي على هذا العنصر؟ (لإظهار/إخفاء زر القائمة)
    private func menuHasActions(for item: ArchiveItem) -> Bool {
        if authVM.isAdmin { return true }
        // غير الإدارة: إبلاغ متاح فقط لعناصر غيرهم
        return item.uploadedBy != authVM.currentUser?.id
    }

    /// محتوى قائمة إجراءات عنصر الأرشيف — للإدارة تحكّم كامل، لغيرهم إبلاغ فقط.
    @ViewBuilder
    private func archiveActionsMenu(for item: ArchiveItem) -> some View {
        if authVM.isAdmin {
            // إجراءات الموافقة — فقط للعناصر المعلَّقة (مع تأكيد)
            if item.approvalStatus == .pending {
                Button {
                    itemToApprove = item
                } label: {
                    Label(L10n.t("موافقة", "Approve"), systemImage: "checkmark.circle.fill")
                }
                Button {
                    itemToReject = item
                } label: {
                    Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                }
                Divider()
            }
            // إجراءات الإخفاء — فقط للموافق عليها
            if item.approvalStatus == .approved {
                Button {
                    Task { await archiveVM.toggleHidden(item) }
                } label: {
                    Label(
                        item.isHidden
                            ? L10n.t("إظهار للجميع", "Show to all")
                            : L10n.t("إخفاء من الأعضاء", "Hide from members"),
                        systemImage: item.isHidden ? "eye.fill" : "eye.slash.fill"
                    )
                }
            }
            Button {
                itemToEdit = item
            } label: {
                Label(L10n.t("تعديل", "Edit"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                itemToDelete = item
            } label: {
                Label(L10n.t("حذف", "Delete"), systemImage: "trash")
            }
            // إبلاغ متاح للإدارة أيضاً (لغير عناصرهم)
            if item.uploadedBy != authVM.currentUser?.id {
                Divider()
                Button {
                    itemToReport = item
                } label: {
                    Label(L10n.t("إبلاغ", "Report"), systemImage: "exclamationmark.bubble")
                }
            }
        } else if item.uploadedBy != authVM.currentUser?.id {
            // الأعضاء العاديون: إبلاغ فقط (لغير عناصرهم) — سياسة Apple
            Button {
                itemToReport = item
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

    // MARK: - بطاقة المكتبة — «ملف أرشيفي»
    //
    // الفكرة: كل عنصر ملف في أرشيف: لسان تصنيف ملوّن في الأعلى، الوثيقة
    // مثبّتة داخل إطار ورقي، وختم السنة مائل على حافتها، وتحتها العنوان
    // ومن أضافها — مربّع بأبعاد القسم (طلب المالك).
    private func archiveCard(_ item: ArchiveItem) -> some View {
        let accent = item.categoryColor

        return VStack(alignment: .leading, spacing: 0) {
            // لسان الملف
            HStack(spacing: 4) {
                Image(systemName: item.categoryIcon)
                    .font(DS.Font.scaled(9, weight: .bold))
                Text(item.categoryDisplayName)
                    .font(DS.Font.plex(10, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, DS.Spacing.sm)
            .frame(height: 22)
            .background(
                UnevenCorners(radius: DS.Radius.sm, bottomLeading: true, bottomTrailing: true)
                    .fill(accent)
            )
            .padding(.leading, DS.Spacing.sm)

            // الوثيقة داخل إطار ورقي + ختم السنة
            preview(for: item, accent: accent)
                .frame(width: cardSide - DS.Spacing.sm * 2, height: cardSide * 0.44)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .strokeBorder(accent.opacity(0.22), lineWidth: 1)
                )
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.top, DS.Spacing.xs)
                .overlay(alignment: .bottomTrailing) { yearStamp(for: item, accent: accent) }
                .overlay(alignment: .bottomLeading) { fileKindBadge(for: item) }
                .overlay(alignment: .topLeading) {
                    statusStack(for: item)
                        .padding(.horizontal, DS.Spacing.sm + 4)
                        .padding(.top, DS.Spacing.sm)
                }

            // خط فاصل رفيع ثم العنوان
            Rectangle()
                .fill(accent.opacity(0.25))
                .frame(height: 1)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.top, DS.Spacing.sm)

            Text(item.title)
                .font(DS.Font.plex(12.5, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.top, 5)

            Spacer(minLength: 0)

            uploaderStrip(for: item, accent: accent)
        }
        .frame(width: cardSide, height: cardSide, alignment: .top)
        .background(
            // ورقة: تدرّج خفيف بلون التصنيف من الأعلى
            LinearGradient(
                colors: [accent.opacity(0.07), DS.Color.surface],
                startPoint: .top, endPoint: .center
            )
            .background(DS.Color.surface)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(borderColor(for: item), lineWidth: 1)
        )
        .opacity(item.approvalStatus == .rejected ? 0.55 : (item.isHidden || item.approvalStatus == .pending ? 0.75 : 1.0))
        .dsSubtleShadow()
    }

    /// شريط المُضيف أسفل البطاقة — صورة العضو + الاسم المختصر، والتاريخ على الطرف الثاني
    private func uploaderStrip(for item: ArchiveItem, accent: Color) -> some View {
        let member = memberVM.member(byId: item.uploadedBy)
        return HStack(spacing: 5) {
            // صورة العضو — حرف أول إن لم تكن له صورة
            Group {
                if let avatar = member?.avatarUrl, let url = URL(string: avatar) {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        accent.opacity(0.25)
                    }
                } else {
                    ZStack {
                        accent.opacity(0.22)
                        Image(systemName: "person.fill")
                            .font(DS.Font.scaled(8, weight: .bold))
                            .foregroundColor(accent)
                    }
                }
            }
            .frame(width: 18, height: 18)
            .clipShape(Circle())

            Text(member?.displayName ?? uploaderName(for: item) ?? L10n.t("غير معروف", "Unknown"))
                .font(DS.Font.plex(10, weight: .semibold))
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(accent.opacity(0.10))
    }

    /// ختم السنة — مائل قليلاً بحدود متقطّعة مثل أختام الأرشيف
    @ViewBuilder
    private func yearStamp(for item: ArchiveItem, accent: Color) -> some View {
        if let year = item.year {
            Text(String(year))
                .font(DS.Font.plex(11, weight: .bold))
                .foregroundColor(accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(DS.Color.surface.opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(accent.opacity(0.75),
                                      style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                )
                .rotationEffect(.degrees(-7))
                .padding(.horizontal, DS.Spacing.sm + 4)
                .padding(.bottom, 6)
        }
    }

    /// نوع الملف على حافة الوثيقة
    @ViewBuilder
    private func fileKindBadge(for item: ArchiveItem) -> some View {
        if item.isPDF {
            Text("PDF")
                .font(DS.Font.plex(9, weight: .black))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(DS.Color.error.opacity(0.92)))
                .padding(.horizontal, DS.Spacing.sm + 4)
                .padding(.bottom, 6)
        }
    }

    /// معاينة العنصر: صورة، أول صفحة PDF، أو ورقة بأيقونة التصنيف
    @ViewBuilder
    private func preview(for item: ArchiveItem, accent: Color) -> some View {
        ZStack {
            accent.opacity(0.10)

            if item.isImage, let url = URL(string: item.fileUrl) {
                // scaledToFill داخل إطار ثابت — كل الوثائق بنفس المساحة
                // مهما اختلفت أبعاد الصورة (طلب المالك)
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView().tint(accent)
                }
            } else if item.isPDF {
                if let thumb = item.thumbnailUrl, let turl = URL(string: thumb) {
                    CachedAsyncImage(url: turl) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView().tint(accent)
                    }
                } else if let furl = URL(string: item.fileUrl) {
                    PDFThumbnailView(url: furl)
                } else {
                    pdfIconPlaceholder
                }
            } else {
                Image(systemName: item.categoryIcon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(accent.opacity(0.8))
            }
        }
    }

    /// شارة الحالة (الأولوية: بانتظار > مرفوض > مخفي)
    @ViewBuilder
    private func statusStack(for item: ArchiveItem) -> some View {
        if item.approvalStatus == .pending {
            statusBadge(icon: "clock.fill", label: L10n.t("بانتظار", "Pending"), color: DS.Color.warning)
        } else if item.approvalStatus == .rejected {
            statusBadge(icon: "xmark.circle.fill", label: L10n.t("مرفوض", "Rejected"), color: DS.Color.error)
        } else if item.isHidden {
            statusBadge(icon: "eye.slash.fill", label: L10n.t("مخفي", "Hidden"), color: DS.Color.textTertiary)
        }
    }

    /// اسم العضو الذي أضاف العنصر (من uploadedBy) — nil لو غير معروف.
    /// اسم من أضاف العنصر — خماسي في التفاصيل: الأول والثاني والثالث والرابع
    /// والعائلة (طلب المالك)
    private func uploaderName(for item: ArchiveItem) -> String? {
        guard let member = memberVM.member(byId: item.uploadedBy) else { return nil }
        let name = member.fivePartName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? member.firstName : name
    }

    private func borderColor(for item: ArchiveItem) -> Color {
        switch item.approvalStatus {
        case .rejected: return DS.Color.error.opacity(0.35)
        case .pending:  return DS.Color.warning.opacity(0.35)
        case .approved: return item.isHidden ? DS.Color.textTertiary.opacity(0.30)
                                             : DS.Color.primary.opacity(0.08)
        }
    }

    /// شارة حالة موحّدة (capsule صغيرة بأيقونة + نص).
    private func statusBadge(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(DS.Font.scaled(11, weight: .bold))
            Text(label).font(DS.Font.scaled(11, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(color))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: selectedCategory?.iconName ?? "archivebox")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(DS.Color.textTertiary)
            Text(L10n.t("لا توجد عناصر في هذا القسم بعد",
                       "No items in this section yet"))
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
            // أي مستخدم يقدر يضيف — مع تنبيه للأعضاء بحاجة الموافقة
            Text(authVM.isAdmin
                 ? L10n.t("اضغط + لإضافة عنصر", "Tap + to add an item")
                 : L10n.t("اضغط + لإضافة عنصر (سيُعرض بعد موافقة الإدارة)",
                          "Tap + to add (visible after admin approval)"))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Upload Sheet

/// شيت رفع عنصر للأرشيف — PDF أو صورة.
struct ArchiveUploadSheet: View {
    @ObservedObject var archiveVM: FamilyArchiveViewModel
    let defaultCategory: ArchiveItem.Category
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var yearText = ""
    @State private var categoryKey: String
    @State private var pickedFileData: Data? = nil
    @State private var pickedFileName: String = ""
    @State private var pickedMimeType: String = ""
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var errorBanner: String? = nil

    init(archiveVM: FamilyArchiveViewModel, defaultCategory: ArchiveItem.Category) {
        self.archiveVM = archiveVM
        self.defaultCategory = defaultCategory
        // التصنيف الافتراضي إن كان ظاهراً، وإلا أول تصنيف ظاهر
        let keys = ArchiveItem.selectableCategoryKeys
        self._categoryKey = State(initialValue: keys.contains(defaultCategory.rawValue)
                                  ? defaultCategory.rawValue : (keys.first ?? defaultCategory.rawValue))
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        pickedFileData != nil &&
        !archiveVM.isUploading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {

                    // اختيار الملف — الـ"hero" بالأعلى
                    fileSelectionSection

                    // بطاقة موحّدة بنمط إضافة ابن
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: L10n.t("تفاصيل العنصر", "Item Details"),
                            icon: "tray.full.fill",
                            iconColor: DS.Color.primary
                        )

                        VStack(spacing: 0) {
                            DSLabeledFieldRow(icon: "textformat", iconColor: DS.Color.primary,
                                              label: L10n.t("العنوان *", "Title *")) {
                                TextField(L10n.t("مثلاً: شجرة العائلة 1965", "e.g. Family Tree 1965"), text: $title)
                                    .font(DS.Font.callout)
                                    .foregroundColor(DS.Color.textPrimary)
                            }

                            DSDivider()

                            DSLabeledFieldRow(icon: "calendar", iconColor: DS.Color.success,
                                              label: L10n.t("السنة", "Year")) {
                                TextField("1965", text: $yearText)
                                    .keyboardType(.numberPad)
                                    .font(DS.Font.callout)
                                    .foregroundColor(DS.Color.textPrimary)
                            }

                            DSDivider()

                            DSLabeledFieldRow(icon: "text.alignleft", iconColor: DS.Color.accent,
                                              label: L10n.t("الوصف", "Description")) {
                                TextField(L10n.t("ملاحظات أو سياق", "Notes or context"), text: $description, axis: .vertical)
                                    .font(DS.Font.callout)
                                    .foregroundColor(DS.Color.textPrimary)
                                    .lineLimit(2...4)
                            }

                            DSDivider()

                            DSLabeledFieldRow(icon: "folder.fill", iconColor: DS.Color.warning,
                                              label: L10n.t("القسم", "Category")) {
                                categoryMenu
                            }
                        }
                    }

                    if archiveVM.isUploading {
                        VStack(spacing: DS.Spacing.xs) {
                            ProgressView(value: archiveVM.uploadProgress)
                                .progressViewStyle(.linear)
                                .tint(DS.Color.primary)
                            Text(L10n.t("جاري الرفع...", "Uploading..."))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                        .padding(.top, DS.Spacing.sm)
                    }

                    if let errorBanner {
                        Text(errorBanner)
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.error)
                            .padding(.top, DS.Spacing.xs)
                    }


                    Spacer(minLength: DS.Spacing.xxxl)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
            }
            .background(DS.Color.background.ignoresSafeArea())
            .navigationTitle(L10n.t("إضافة للأرشيف", "Add to Archive"))
            .navigationBarTitleDisplayMode(.inline)
            // الإضافة أعلى يمين، والإغلاق يسار (طلب المالك)
            .dsSheetToolbar(
                confirm: L10n.t("إضافة", "Add"),
                isLoading: archiveVM.isUploading,
                disabled: !canSubmit,
                onConfirm: { submit() },
                onCancel: { dismiss() }
            )
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType.pdf],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $photoItem,
                matching: .images
            )
            .onChange(of: photoItem) { newItem in
                handlePhotoPick(newItem)
            }
        }
        .presentationDetents([.fraction(0.62)])
        .presentationDragIndicator(.visible)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - File Selection Section

    private var fileSelectionSection: some View {
        VStack(spacing: DS.Spacing.sm) {
            if pickedFileData != nil {
                // عرض الملف المختار
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: pickedMimeType == "application/pdf" ? "doc.text.fill" : "photo.fill")
                        .font(DS.Font.scaled(20, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pickedFileName.isEmpty ? L10n.t("ملف مختار", "Selected file") : pickedFileName)
                            .font(DS.Font.callout)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(ByteCountFormatter().string(fromByteCount: Int64(pickedFileData?.count ?? 0)))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    Spacer()
                    Button {
                        pickedFileData = nil
                        pickedFileName = ""
                        pickedMimeType = ""
                        photoItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(DS.Color.error)
                    }
                }
                .padding(DS.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .fill(DS.Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .strokeBorder(DS.Color.primary.opacity(0.20), lineWidth: 1)
                )
            } else {
                // أزرار اختيار النوع
                HStack(spacing: DS.Spacing.sm) {
                    pickButton(
                        icon: "doc.text.fill",
                        title: L10n.t("ملف PDF", "PDF File")
                    ) { showFileImporter = true }

                    pickButton(
                        icon: "photo.fill",
                        title: L10n.t("صورة", "Photo")
                    ) { showPhotoPicker = true }
                }
            }
        }
    }

    private func pickButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(22, weight: .bold))
                    .foregroundColor(DS.Color.primary)
                Text(title)
                    .font(DS.Font.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.textPrimary)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(DS.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(DS.Color.primary.opacity(0.20), lineWidth: 1.5)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Category Menu + Boxed Field

    /// صندوق إدخال موحّد الارتفاع — لمحاذاة الحقول في صف عمودين.
    @ViewBuilder
    private func boxedField<C: View>(@ViewBuilder content: () -> C) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.sm)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Color.textTertiary.opacity(0.18), lineWidth: 1)
            )
    }

    /// منيو اختيار القسم — يظهر كحقل أنيق بدل شريط الكبسولات.
    private var categoryMenu: some View {
        Menu {
            ForEach(ArchiveItem.selectableCategoryKeys, id: \.self) { key in
                Button {
                    categoryKey = key
                } label: {
                    Label(ArchiveItem.categoryName(key), systemImage: ArchiveItem.categoryIcon(key))
                }
            }
        } label: {
            boxedField {
                HStack(spacing: 6) {
                    Image(systemName: ArchiveItem.categoryIcon(categoryKey))
                        .font(DS.Font.scaled(12, weight: .semibold))
                        .foregroundColor(DS.Color.primary)
                    Text(ArchiveItem.categoryName(categoryKey))
                        .font(DS.Font.scaled(14))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Actions

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            // الوصول الآمن للملف
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            pickedFileData = data
            pickedFileName = url.lastPathComponent
            pickedMimeType = "application/pdf"
            if title.isEmpty {
                title = url.deletingPathExtension().lastPathComponent
            }
        } catch {
            errorBanner = L10n.t("تعذّر قراءة الملف.", "Failed to read file.")
        }
    }

    private func handlePhotoPick(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { return }
                await MainActor.run {
                    pickedFileData = data
                    // نخمّن النوع — PhotosPicker يعطي JPEG/HEIC غالباً
                    let utType = item.supportedContentTypes.first
                    if utType?.conforms(to: .png) == true {
                        pickedMimeType = "image/png"
                        pickedFileName = "image.png"
                    } else if utType?.conforms(to: .heic) == true {
                        pickedMimeType = "image/heic"
                        pickedFileName = "image.heic"
                    } else {
                        pickedMimeType = "image/jpeg"
                        pickedFileName = "image.jpg"
                    }
                }
            } catch {
                await MainActor.run {
                    errorBanner = L10n.t("تعذّر تحميل الصورة.", "Failed to load image.")
                }
            }
        }
    }

    private func submit() {
        guard let data = pickedFileData else { return }
        Task {
            let item = await archiveVM.uploadItem(
                title: title,
                description: description,
                categoryKey: categoryKey,
                year: Int(yearText.trimmingCharacters(in: .whitespacesAndNewlines)),
                fileData: data,
                fileName: pickedFileName,
                mimeType: pickedMimeType
            )
            if item != nil {
                dismiss()
            } else if let err = archiveVM.errorMessage {
                errorBanner = err
            }
        }
    }
}

// MARK: - Archive Edit Sheet

/// تعديل البيانات الوصفية لعنصر أرشيف (عنوان/وصف/سنة/قسم) — بدون تغيير الملف.
struct ArchiveEditSheet: View {
    @ObservedObject var archiveVM: FamilyArchiveViewModel
    let item: ArchiveItem
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var description: String
    @State private var yearText: String
    @State private var categoryKey: String
    @State private var isSaving = false
    @State private var errorBanner: String? = nil

    init(archiveVM: FamilyArchiveViewModel, item: ArchiveItem) {
        self.archiveVM = archiveVM
        self.item = item
        _title = State(initialValue: item.title)
        _description = State(initialValue: item.description ?? "")
        _yearText = State(initialValue: item.year.map(String.init) ?? "")
        _categoryKey = State(initialValue: item.effectiveCategoryKey)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    DSTextField(label: L10n.t("العنوان", "Title"), placeholder: "", text: $title, icon: "textformat")
                    DSTextField(label: L10n.t("الوصف (اختياري)", "Description (optional)"), placeholder: "", text: $description, icon: "text.alignleft")

                    // السنة + القسم — عمودان متحاذيان
                    HStack(alignment: .top, spacing: DS.Spacing.md) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.t("السنة", "Year"))
                                .font(DS.Font.scaled(12, weight: .semibold))
                                .foregroundColor(DS.Color.textSecondary)
                            editBoxedField {
                                TextField("1965", text: $yearText)
                                    .keyboardType(.numberPad)
                                    .font(DS.Font.scaled(14))
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.t("القسم", "Category"))
                                .font(DS.Font.scaled(12, weight: .semibold))
                                .foregroundColor(DS.Color.textSecondary)
                            editCategoryMenu
                        }
                    }

                    if let errorBanner {
                        Text(errorBanner).font(DS.Font.caption1).foregroundColor(DS.Color.error)
                    }
                    Spacer(minLength: DS.Spacing.xxxl)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
            }
            .background(DS.Color.background.ignoresSafeArea())
            .navigationTitle(L10n.t("تعديل العنصر", "Edit Item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: DSToolbar.cancelPlacement) {
                    DSToolbarCancelButton { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: DSToolbar.confirmPlacement) {
                    Button(L10n.t("حفظ", "Save")) { save() }
                        .fontWeight(.bold)
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.fraction(0.62)])
        .presentationDragIndicator(.visible)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// صندوق إدخال موحّد الارتفاع — لمحاذاة الحقول في صف عمودين.
    @ViewBuilder
    private func editBoxedField<C: View>(@ViewBuilder content: () -> C) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.sm)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Color.textTertiary.opacity(0.18), lineWidth: 1)
            )
    }

    /// منيو اختيار القسم — يظهر كحقل أنيق بدل شريط الكبسولات.
    private var editCategoryMenu: some View {
        Menu {
            ForEach(ArchiveItem.selectableCategoryKeys, id: \.self) { key in
                Button {
                    categoryKey = key
                } label: {
                    Label(ArchiveItem.categoryName(key), systemImage: ArchiveItem.categoryIcon(key))
                }
            }
        } label: {
            editBoxedField {
                HStack(spacing: 6) {
                    Image(systemName: ArchiveItem.categoryIcon(categoryKey))
                        .font(DS.Font.scaled(12, weight: .semibold))
                        .foregroundColor(DS.Color.primary)
                    Text(ArchiveItem.categoryName(categoryKey))
                        .font(DS.Font.scaled(14))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
    }

    private func save() {
        Task {
            isSaving = true
            let ok = await archiveVM.updateItem(
                item,
                title: title,
                description: description,
                categoryKey: categoryKey,
                year: Int(yearText.trimmingCharacters(in: .whitespacesAndNewlines))
            )
            isSaving = false
            if ok { dismiss() } else { errorBanner = archiveVM.errorMessage }
        }
    }
}

// MARK: - Archive Item Viewer

/// عارض عناصر الأرشيف — PDFKit لـ PDFs، CachedAsyncImage للصور.
/// زر مشاركة/تنزيل يفتح UIActivityViewController.
struct ArchiveItemViewer: View {
    let item: ArchiveItem
    var uploaderName: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false
    @State private var shareURL: URL? = nil
    @State private var downloading = false
    /// تكبير الصورة بضغطتين
    @State private var zoomed = false

    private var accent: Color { item.categoryColor }

    // MARK: - صفحة العنصر — «ورقة أرشيف» + بطاقة فهرسة
    //
    // الوثيقة تُعرض مثبّتة على ورقة بيضاء بظل خفيف، وتحتها بطاقة فهرسة
    // فيها التصنيف وختم السنة والعنوان والوصف ومن أضافها (طلب المالك).
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [accent.opacity(0.10), DS.Color.background],
                    startPoint: .top, endPoint: .center
                )
                .ignoresSafeArea()

                VStack(spacing: DS.Spacing.md) {
                    documentSheet
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.md)

                    indexCard
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.md)
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: DSToolbar.cancelPlacement) {
                    DSToolbarCancelButton(title: L10n.t("إغلاق", "Close")) { dismiss() }
                }
                ToolbarItem(placement: DSToolbar.confirmPlacement) {
                    Button {
                        Task { await downloadAndShare() }
                    } label: {
                        if downloading {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.primary)
                        }
                    }
                    .disabled(downloading)
                    .accessibilityLabel(L10n.t("حفظ أو مشاركة", "Save or share"))
                }
            }
            .sheet(isPresented: $showShare) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// الوثيقة مثبّتة على ورقة بظل — الصور تتكبّر بضغطتين
    private var documentSheet: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .fill(DS.Color.surface)
                .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6)

            Group {
                if item.isPDF, let url = URL(string: item.fileUrl) {
                    ArchivePDFView(url: url)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                } else if item.isImage, let url = URL(string: item.fileUrl) {
                    // تكبير بالقرصة أو بضغطتين + تحريك بالسحب (طلب المالك)
                    ZoomableImage(onZoomChange: { zoomed = $0 }) {
                        CachedAsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            ProgressView().tint(accent)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                } else {
                    VStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "doc.questionmark")
                            .font(.system(size: 48))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا يمكن عرض هذا الملف داخل التطبيق",
                                   "This file can't be previewed in the app"))
                            .font(DS.Font.plex(13, weight: .medium))
                            .foregroundColor(DS.Color.textSecondary)
                            .multilineTextAlignment(.center)
                        Button {
                            Task { await downloadAndShare() }
                        } label: {
                            Text(L10n.t("حفظ الملف", "Save file"))
                                .font(DS.Font.calloutBold)
                                .foregroundColor(.white)
                                .padding(.horizontal, DS.Spacing.lg)
                                .frame(height: 40)
                                .background(Capsule().fill(accent))
                        }
                    }
                    .padding(DS.Spacing.lg)
                }
            }
            .padding(DS.Spacing.sm)
        }
    }

    /// بطاقة فهرسة: تصنيف + ختم سنة + عنوان + وصف + من أضافها ومتى
    private var indexCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                HStack(spacing: 4) {
                    Image(systemName: item.categoryIcon)
                        .font(DS.Font.scaled(10, weight: .bold))
                    Text(item.categoryDisplayName)
                        .font(DS.Font.plex(11, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, 4)
                .background(Capsule().fill(accent))

                if item.isPDF || !item.formattedSize.isEmpty {
                    Text([item.isPDF ? "PDF" : nil, item.formattedSize.isEmpty ? nil : item.formattedSize]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(DS.Font.plex(10, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                }

                Spacer(minLength: 0)

                if let year = item.year {
                    Text(String(year))
                        .font(DS.Font.plex(12, weight: .bold))
                        .foregroundColor(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(accent.opacity(0.75),
                                              style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                        )
                        .rotationEffect(.degrees(-7))
                }
            }

            Text(item.title)
                .font(DS.Font.plex(17, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let desc = item.description, !desc.isEmpty {
                Text(desc)
                    .font(DS.Font.plex(13, weight: .regular))
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Rectangle()
                .fill(accent.opacity(0.22))
                .frame(height: 1)

            HStack(spacing: DS.Spacing.sm) {
                if let uploaderName, !uploaderName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(DS.Font.scaled(10, weight: .bold))
                        Text(uploaderName)
                            .font(DS.Font.plex(11, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(DS.Font.plex(11, weight: .medium))
            }
            .foregroundColor(DS.Color.textTertiary)
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(LinearGradient(colors: [accent, accent.opacity(0.6)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .dsSubtleShadow()
    }

    /// تحميل الملف لمجلد مؤقت ثم فتح share sheet للحفظ في Files / مشاركة.
    private func downloadAndShare() async {
        guard let url = URL(string: item.fileUrl) else { return }
        downloading = true
        defer { downloading = false }
        do {
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            // إعادة تسمية الملف ليحمل اسمه الأصلي
            let suggestedName = item.fileName ?? (item.title + (item.isPDF ? ".pdf" : ".jpg"))
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedName)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)
            shareURL = dest
            showShare = true
        } catch {
            Log.error("[Archive] خطأ تنزيل: \(error.localizedDescription)")
        }
    }
}

// MARK: - PDF View (UIViewRepresentable)

/// عارض PDF بسيط مبني على PDFKit، يحمّل من URL.
private struct ArchivePDFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        // تكبير أوسع داخل التفاصيل (طلب المالك)
        view.maxScaleFactor = 6
        view.minScaleFactor = 0.5
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemBackground

        Task.detached {
            if let data = try? Data(contentsOf: url),
               let doc = PDFDocument(data: data) {
                await MainActor.run {
                    view.document = doc
                }
            }
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - PDF First-Page Thumbnail

/// كاش للمصغّرات المولّدة من ملفات PDF (مفتاح = رابط الملف).
private final class PDFThumbCache {
    static let shared = NSCache<NSURL, UIImage>()
}

/// يولّد ويعرض أول صفحة من ملف PDF كمصغّرة (مع كاش)، ويرجع لأيقونة عند الفشل.
private struct PDFThumbnailView: View {
    let url: URL
    @State private var image: UIImage? = nil
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Color.clear.overlay(
                    Image(uiImage: image).resizable().scaledToFill()
                )
                .clipped()
            } else if failed {
                VStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(DS.Color.primary.opacity(0.85))
                    Text("PDF")
                        .font(DS.Font.scaled(11, weight: .black))
                        .foregroundColor(DS.Color.primary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(DS.Color.primary.opacity(0.15)))
                }
            } else {
                ProgressView().tint(DS.Color.primary)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        if let cached = PDFThumbCache.shared.object(forKey: url as NSURL) {
            image = cached
            return
        }
        let rendered = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url),
                  let doc = PDFDocument(data: data),
                  let page = doc.page(at: 0) else { return nil }
            let box = page.bounds(for: .mediaBox)
            guard box.width > 0, box.height > 0 else { return nil }
            let target: CGFloat = 500
            let scale = target / max(box.width, box.height)
            let size = CGSize(width: box.width * scale, height: box.height * scale)
            return page.thumbnail(of: size, for: .mediaBox)
        }.value

        if let rendered {
            PDFThumbCache.shared.setObject(rendered, forKey: url as NSURL)
            image = rendered
        } else {
            failed = true
        }
    }
}


/// مستطيل بزوايا مختارة — يُستخدم للسان الملف في بطاقة المكتبة (iOS 16 يدعم الرسم اليدوي)
struct UnevenCorners: Shape {
    var radius: CGFloat = 8
    var topLeading = false
    var topTrailing = false
    var bottomLeading = true
    var bottomTrailing = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, min(rect.width, rect.height) / 2)
        path.move(to: CGPoint(x: rect.minX + (topLeading ? r : 0), y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - (topTrailing ? r : 0), y: rect.minY))
        if topTrailing {
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                        startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - (bottomTrailing ? r : 0)))
        if bottomTrailing {
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                        startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX + (bottomLeading ? r : 0), y: rect.maxY))
        if bottomLeading {
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                        startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + (topLeading ? r : 0)))
        if topLeading {
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                        startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        return path
    }
}
