import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers

/// شاشة أرشيف العائلة — وثائق وكتب وصور قديمة. الكل يقدر يتصفّح ويُحمّل،
/// الرفع/الحذف للمدراء فقط (owner + admin).
struct FamilyArchiveView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @StateObject private var archiveVM = FamilyArchiveViewModel()

    /// nil = الكل
    @State private var selectedCategory: ArchiveItem.Category? = nil
    @State private var showingUpload = false
    @State private var selectedItem: ArchiveItem? = nil
    @State private var itemToDelete: ArchiveItem? = nil
    @State private var itemToEdit: ArchiveItem? = nil

    // وضع التحديد المتعدّد (للمدراء فقط)
    @State private var selectionMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showBatchDeleteAlert = false

    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: DS.Spacing.sm),
        GridItem(.flexible(), spacing: DS.Spacing.sm)
    ]

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

                // صف الفلاتر (مع زر التحديد مدمج للإدارة)
                categoryPicker
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xs)

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
                                .contextMenu {
                                    if authVM.isAdmin && !selectionMode {
                                        // إجراءات الموافقة — فقط للعناصر المعلَّقة
                                        if item.approvalStatus == .pending {
                                            Button {
                                                Task { await archiveVM.approveItem(item) }
                                            } label: {
                                                Label(L10n.t("موافقة", "Approve"),
                                                      systemImage: "checkmark.circle.fill")
                                            }
                                            Button {
                                                Task { await archiveVM.rejectItem(item) }
                                            } label: {
                                                Label(L10n.t("رفض", "Reject"),
                                                      systemImage: "xmark.circle.fill")
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
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.xxxxl)
                    }
                    .refreshable { await archiveVM.fetchItems() }
                }
            }

            // زر رفع — متاح للجميع، يختفي فقط في وضع التحديد
            if !selectionMode {
                HStack {
                    Spacer()
                    DSFloatingButton(icon: "plus") {
                        showingUpload = true
                    }
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
            archiveVM.configure(authVM: authVM)
            await archiveVM.fetchItems()
        }
        .sheet(isPresented: $showingUpload) {
            ArchiveUploadSheet(archiveVM: archiveVM, defaultCategory: selectedCategory ?? .documents)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedItem) { item in
            ArchiveItemViewer(item: item)
        }
        .sheet(item: $itemToEdit) { item in
            ArchiveEditSheet(archiveVM: archiveVM, item: item)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert(L10n.t("حذف من الأرشيف", "Delete from archive"),
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
        .alert(L10n.t("حذف العناصر المختارة", "Delete selected items"),
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
        .background(.ultraThinMaterial)
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

    /// كل الخيارات بترتيب ثابت: الكل ثم 4 أقسام.
    private var allFilterOptions: [ArchiveItem.Category?] {
        [nil, .documents, .books, .oldPhotos, .other]
    }

    private var categoryPicker: some View {
        HStack(spacing: 6) {
            ForEach(allFilterOptions, id: \.self) { option in
                if selectedCategory == option {
                    activeFilterPill(option)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else {
                    inactiveFilterIcon(option)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }

            // زر التحديد مدمج داخل الكبسولة — للإدارة فقط، يختفي في وضع التحديد
            if authVM.isAdmin && !selectionMode {
                Capsule()
                    .fill(DS.Color.textTertiary.opacity(0.25))
                    .frame(width: 1, height: 22)
                    .padding(.horizontal, 2)
                    .transition(.opacity)

                inlineSelectButton
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
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
        .animation(.spring(response: 0.40, dampingFraction: 0.78), value: selectedCategory)
        .animation(.spring(response: 0.40, dampingFraction: 0.78), value: selectionMode)
    }

    /// زر تحديد مدمج — أيقونة فقط ليتناغم مع الفلاتر inactive.
    private var inlineSelectButton: some View {
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

    /// الفلتر النشط — pill ممتدّ بلون فئته + اسم + عدّاد.
    private func activeFilterPill(_ option: ArchiveItem.Category?) -> some View {
        let color = accentColor(for: option)
        let count = archiveVM.count(in: option)
        return HStack(spacing: 6) {
            Image(systemName: icon(for: option))
                .font(DS.Font.scaled(12, weight: .bold))
                .foregroundColor(.white)
            Text(title(for: option))
                .font(DS.Font.scaled(13, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
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
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [color, color.opacity(0.85)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
        )
        .shadow(color: color.opacity(0.35), radius: 8, x: 0, y: 3)
    }

    /// الفلتر غير النشط — أيقونة دائرية فقط بلون الفئة.
    private func inactiveFilterIcon(_ option: ArchiveItem.Category?) -> some View {
        let color = accentColor(for: option)
        let count = archiveVM.count(in: option)
        return Button {
            selectedCategory = option
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon(for: option))
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(color.opacity(0.12)))
                    .overlay(Circle().strokeBorder(color.opacity(0.20), lineWidth: 1))

                // عدّاد صغير غير مزعج — يظهر فقط لو > 0
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
        .accessibilityLabel(title(for: option))
    }

    // MARK: - Archive Card

    /// أيقونة PDF احتياطية (لو ما توفّر ملف لتوليد المصغّرة).
    private var pdfIconPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(DS.Color.primary.opacity(0.85))
            Text("PDF")
                .font(DS.Font.scaled(10, weight: .black))
                .foregroundColor(DS.Color.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(DS.Color.primary.opacity(0.15)))
        }
    }

    private func archiveCard(_ item: ArchiveItem) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            // معاينة بصرية أو أيقونة
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.primary.opacity(0.08))

                    if item.isImage, let url = URL(string: item.fileUrl) {
                        CachedAsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ProgressView().tint(DS.Color.primary)
                        }
                    } else if item.isPDF {
                        // معاينة أول صفحة من الـPDF — مصغّرة جاهزة أو نُولّدها
                        if let thumb = item.thumbnailUrl, let turl = URL(string: thumb) {
                            CachedAsyncImage(url: turl) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                ProgressView().tint(DS.Color.primary)
                            }
                        } else if let furl = URL(string: item.fileUrl) {
                            PDFThumbnailView(url: furl)
                        } else {
                            pdfIconPlaceholder
                        }
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: item.category.iconName)
                                .font(.system(size: 36, weight: .light))
                                .foregroundColor(DS.Color.primary.opacity(0.85))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if item.isPDF {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.text.fill")
                                .font(DS.Font.scaled(8, weight: .bold))
                            Text("PDF")
                                .font(DS.Font.scaled(9, weight: .black))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DS.Color.error.opacity(0.9)))
                        .padding(6)
                    }
                }

                // شارة الحالة (الأولوية: pending > rejected > hidden)
                VStack(alignment: .trailing, spacing: 4) {
                    if item.approvalStatus == .pending {
                        statusBadge(
                            icon: "clock.fill",
                            label: L10n.t("بانتظار", "Pending"),
                            color: DS.Color.warning
                        )
                    } else if item.approvalStatus == .rejected {
                        statusBadge(
                            icon: "xmark.circle.fill",
                            label: L10n.t("مرفوض", "Rejected"),
                            color: DS.Color.error
                        )
                    } else if item.isHidden {
                        statusBadge(
                            icon: "eye.slash.fill",
                            label: L10n.t("مخفي", "Hidden"),
                            color: DS.Color.textTertiary
                        )
                    }
                }
                .padding(6)
            }

            // عنوان + حجم
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let year = item.year {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(DS.Font.scaled(9, weight: .bold))
                        Text(String(year))
                            .font(DS.Font.scaled(10, weight: .bold))
                    }
                    .foregroundColor(item.category.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(item.category.accentColor.opacity(0.12)))
                }

                if !item.formattedSize.isEmpty {
                    Text(item.formattedSize)
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 226, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(borderColor(for: item), lineWidth: 1)
        )
        .opacity(item.approvalStatus == .rejected ? 0.55 : (item.isHidden || item.approvalStatus == .pending ? 0.75 : 1.0))
        .dsSubtleShadow()
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
            Image(systemName: icon).font(DS.Font.scaled(9, weight: .bold))
            Text(label).font(DS.Font.scaled(9, weight: .bold))
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
    @State private var category: ArchiveItem.Category
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
        self._category = State(initialValue: defaultCategory)
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        pickedFileData != nil &&
        !archiveVM.isUploading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {

                    // اختيار الملف
                    fileSelectionSection

                    // العنوان
                    fieldGroup(label: L10n.t("العنوان", "Title"), required: true) {
                        DSTextField(
                            label: "",
                            placeholder: L10n.t("مثلاً: شجرة العائلة 1965", "e.g. Family Tree 1965"),
                            text: $title,
                            icon: "textformat"
                        )
                    }

                    // الوصف
                    fieldGroup(label: L10n.t("الوصف (اختياري)", "Description (optional)")) {
                        DSTextField(
                            label: "",
                            placeholder: L10n.t("ملاحظات أو سياق", "Notes or context"),
                            text: $description,
                            icon: "text.alignleft"
                        )
                    }

                    // السنة (اختياري)
                    fieldGroup(label: L10n.t("السنة (اختياري)", "Year (optional)")) {
                        DSTextField(
                            label: "",
                            placeholder: L10n.t("مثلاً: 1965", "e.g. 1965"),
                            text: $yearText,
                            icon: "calendar"
                        )
                        .keyboardType(.numberPad)
                    }

                    // القسم
                    fieldGroup(label: L10n.t("القسم", "Category")) {
                        categorySegmented
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .disabled(archiveVM.isUploading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("رفع", "Upload")) { submit() }
                        .fontWeight(.bold)
                        .disabled(!canSubmit)
                }
            }
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

    // MARK: - Category Segmented

    private var categorySegmented: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ArchiveItem.Category.allCases) { cat in
                    Button {
                        category = cat
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: cat.iconName)
                                .font(DS.Font.scaled(11, weight: .bold))
                            Text(L10n.t(cat.displayName, cat.displayNameEn))
                                .font(DS.Font.scaled(12, weight: category == cat ? .bold : .medium))
                        }
                        .foregroundColor(category == cat ? .white : DS.Color.primary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(category == cat ? DS.Color.primary : DS.Color.primary.opacity(0.10)))
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private func fieldGroup<C: View>(label: String, required: Bool = false, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(DS.Font.scaled(12, weight: .semibold))
                    .foregroundColor(DS.Color.textSecondary)
                if required {
                    Text("*")
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.error)
                }
            }
            content()
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
                category: category,
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
    @State private var category: ArchiveItem.Category
    @State private var isSaving = false
    @State private var errorBanner: String? = nil

    init(archiveVM: FamilyArchiveViewModel, item: ArchiveItem) {
        self.archiveVM = archiveVM
        self.item = item
        _title = State(initialValue: item.title)
        _description = State(initialValue: item.description ?? "")
        _yearText = State(initialValue: item.year.map(String.init) ?? "")
        _category = State(initialValue: item.category)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    DSTextField(label: L10n.t("العنوان", "Title"), placeholder: "", text: $title, icon: "textformat")
                    DSTextField(label: L10n.t("الوصف (اختياري)", "Description (optional)"), placeholder: "", text: $description, icon: "text.alignleft")
                    DSTextField(label: L10n.t("السنة (اختياري)", "Year (optional)"), placeholder: L10n.t("مثلاً: 1965", "e.g. 1965"), text: $yearText, icon: "calendar")
                        .keyboardType(.numberPad)

                    Text(L10n.t("القسم", "Category"))
                        .font(DS.Font.scaled(12, weight: .semibold))
                        .foregroundColor(DS.Color.textSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Spacing.sm) {
                            ForEach(ArchiveItem.Category.allCases) { cat in
                                Button { category = cat } label: {
                                    Text(L10n.isArabic ? cat.displayName : cat.displayNameEn)
                                        .font(DS.Font.scaled(12, weight: category == cat ? .bold : .medium))
                                        .foregroundColor(category == cat ? .white : DS.Color.primary)
                                        .padding(.horizontal, DS.Spacing.md)
                                        .padding(.vertical, DS.Spacing.sm)
                                        .background(Capsule().fill(category == cat ? DS.Color.primary : DS.Color.primary.opacity(0.10)))
                                }
                                .buttonStyle(.plain)
                            }
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
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("حفظ", "Save")) { save() }
                        .fontWeight(.bold)
                        .disabled(!canSave)
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
                category: category,
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
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false
    @State private var shareURL: URL? = nil
    @State private var downloading = false

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                if item.isPDF, let url = URL(string: item.fileUrl) {
                    ArchivePDFView(url: url)
                        .ignoresSafeArea(edges: .bottom)
                } else if item.isImage, let url = URL(string: item.fileUrl) {
                    // عرض طبيعي: scaledToFit مع كامل المساحة، بدون scroll/zoom زائد
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } placeholder: {
                        ProgressView().tint(DS.Color.primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(DS.Spacing.md)
                } else {
                    VStack(spacing: DS.Spacing.md) {
                        Image(systemName: "doc.questionmark")
                            .font(.system(size: 56))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا يمكن عرض هذا الملف داخل التطبيق",
                                   "This file can't be previewed in the app"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await downloadAndShare() }
                    } label: {
                        if downloading {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                    .disabled(downloading)
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
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                VStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(DS.Color.primary.opacity(0.85))
                    Text("PDF")
                        .font(DS.Font.scaled(10, weight: .black))
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
