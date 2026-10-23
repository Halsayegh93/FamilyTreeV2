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
    /// يعيد رسم الصفحة لمّا تصل التصنيفات المحدّثة (أسماء «التصنيفات» في الإدارة بدل الافتراضية)
    @ObservedObject private var categoryStore = CategoryStore.shared

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
    /// دخول البطاقات مرة واحدة عند ظهور الشبكة (نمط الأخبار والديوانيات)
    @State private var appeared = false

    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — أعمدة أكثر لاستغلال العرض
    private var isLandscape: Bool { vSizeClass == .compact }

    /// ضلع بطاقة المكتبة — محسوب من عرض الشاشة وعدد الأعمدة والهوامش،
    /// حتى تبقى البطاقة مربّعة فعلاً ولا تتمدّد خارج القسم (طلب المالك).
    private var cardSide: CGFloat {
        let width = UIScreen.main.bounds.width
        let columns: CGFloat = isLandscape ? max(2, floor((width - DS.Spacing.lg * 2) / DS.Landscape.gridCardMinWidth)) : 2
        let gaps = DS.Spacing.sm * (columns - 1)
        let side = (width - DS.Spacing.lg * 2 - gaps) / columns
        return max(130, side)
    }

    private var gridColumns: [GridItem] {
        if isLandscape {
            return [GridItem(.adaptive(minimum: DS.Landscape.gridCardMinWidth, maximum: .infinity), spacing: DS.Spacing.sm, alignment: .top)]
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
                    // التحميل الموحّد: مجسّم المكتبة يتنفّس
                    DSPageLoader(section: .library)
                } else if archiveVM.items(in: selectedCategory).isEmpty {
                    emptyState
                        .dsStaggerIn(0)   // الحالة الفارغة تصعد وتظهر (تلاشٍ فقط مع «تقليل الحركة»)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: gridColumns, spacing: DS.Spacing.sm) {
                            ForEach(Array(archiveVM.items(in: selectedCategory).enumerated()),
                                    id: \.element.id) { index, item in
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
                                .overlay(alignment: Alignment(horizontal: .trailing, vertical: .archiveCardTop)) {
                                    if !selectionMode && menuHasActions(for: item) {
                                        Menu {
                                            archiveActionsMenu(for: item)
                                        } label: {
                                            cardMenuBadge
                                        }
                                        .padding(DS.Spacing.sm)   // داخل زاوية المعاينة
                                    }
                                }
                                .contextMenu {
                                    if !selectionMode {
                                        archiveActionsMenu(for: item)
                                    }
                                }
                                // نمط الأخبار والديوانيات: البطاقات تصعد وتظهر تباعاً (أول ٧) مرة عند الظهور
                                .dsCardCascade(index, appeared: appeared)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.md)
                        .padding(.bottom, DS.Spacing.xxxxl)
                        .onAppear { appeared = true }
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
        .onAppear { NewContentTracker.shared.markSeen(.library) }   // «النقاط الصفراء»: فُتح القسم
        .task {
            archiveVM.configure(authVM: authVM, notificationVM: notificationVM)
            // التصنيفات بأحدث أسمائها (قد تكون تغيّرت من جهاز آخر) — بالتوازي مع العناصر
            async let categories: Void = categoryStore.fetch()
            await archiveVM.fetchItems()
            await categories
        }
        .onReceive(NotificationCenter.default.publisher(for: .subPageStartSelection)) { note in
            guard authVM.isAdmin, (note.userInfo?["page"] as? String) == "archive" else { return }
            withAnimation(DS.Anim.snappy) {
                selectionMode = true
                selectedIDs = []
            }
        }
        // «إضافة إلى المكتبة» مربّع بمنتصف الشاشة (طلب المالك)
        .fullScreenCover(isPresented: $showingUpload) {
            DSCenterPanel(onBackgroundTap: nil, hugsContent: true) {
                ArchiveUploadSheet(archiveVM: archiveVM, defaultCategory: selectedCategory ?? .documents)
                    .dsSectionPage(.library)   // الصفحة تحته «تختفي» — المربّع يبقي القسم الحالي
            }
            .background(ClearPresentationBackground())
        }
        .transaction { t in
            if showingUpload { t.disablesAnimations = true }
        }
        // تفاصيل العنصر — مربّع كبير بالمنتصف (طلب المالك ٢٠٢٦-١٠-٢٣، مثل تفاصيل العضو):
        // يُغلق بـ× أو بالضغط خارجه
        .dsCenterBox(item: $selectedItem, onBackgroundTap: { selectedItem = nil }) { item in
            ArchiveItemViewer(item: item, uploaderName: uploaderName(for: item))
        }
        .fullScreenCover(item: $itemToEdit) { item in
            DSCenterPanel(onBackgroundTap: nil, hugsContent: true) {
                ArchiveEditSheet(archiveVM: archiveVM, item: item)
                    .dsSectionPage(.library)
            }
            .background(ClearPresentationBackground())
        }
        .transaction { t in if itemToEdit != nil { t.disablesAnimations = true } }
        .dsAlert(L10n.t("إبلاغ عن عنصر", "Report Item"), isPresented: Binding(
            get: { itemToReport != nil },
            set: { if !$0 { itemToReport = nil } }
        )) {
            TextField(L10n.t("سبب الإبلاغ (اختياري)", "Reason (optional)"), text: $reportReason)
                .dsAlertField()
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
            Text(L10n.t("شكراً لك، وصل بلاغك للإدارة وستتم مراجعته خلال ٢٤ ساعة.", "Thank you — your report reached the admins and will be reviewed within 24 hours."))
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
        .dsAlert(L10n.t("حذف من المكتبة", "Delete from library"),
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
            Text(L10n.t("حذف هذا العنصر نهائياً من المكتبة؟",
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
            Text(L10n.t("حذف \(selectedIDs.count) عنصر نهائياً من المكتبة؟",
                       "Permanently delete \(selectedIDs.count) items from the archive?"))
        }
        // «داخل المكتبة نفس الالوان» (طلب المالك ٢٠٢٦-١٠-٠٥): الصفحة وكل ما يُفتح منها بلون
        // المكتبة — مثل التبويبات (البيئة + AppSection.current للرسائل ومربّع التاريخ)
        .dsSectionPage(.library)
    }

    // MARK: - Selection Mode UI

    private var selectionTopBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSChipButton(L10n.t("إلغاء", "Cancel"), tint: DS.Color.error) { exitSelectionMode() }
            Spacer()
            Text(L10n.t("اختيار \(selectedIDs.count)", "Selected \(selectedIDs.count)"))
                .dsFont(.rowTitleCompact)
                .foregroundColor(DS.Color.textPrimary)
            Spacer()
            DSChipButton(allInCategorySelected ? L10n.t("إلغاء الكل", "Clear all")
                                               : L10n.t("تحديد الكل", "Select all")) {
                toggleSelectAllInCategory()
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
                    .fill(isSelected ? AppSection.library.ink : DS.Color.overlayText)
                    .frame(width: DS.Icon.section, height: DS.Icon.section)
            )
            .dsSubtleShadow()
            .padding(DS.Spacing.sm)
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
                           color: DS.Color.slateFill) {
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
                           color: DS.Color.navyFill) {
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
                       color: DS.Color.errorFill) {
                showBatchDeleteAlert = true
            }
            .disabled(isEmpty)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .dsGlass(Rectangle())
        .overlay(
            Rectangle()
                .fill(DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke))
                .frame(height: DS.Border.width),
            alignment: .top
        )
    }

    /// زرّ شريط التحديد — الزرّ الواحد بلون معناه (الحذف أحمر)
    private func actionPill(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        DSButton(label, icon: icon, role: color == DS.Color.error ? .destructive : nil,
                 tint: color == DS.Color.error ? nil : color, fullWidth: false, action: action)
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

    // MARK: - Archive Card

    /// أيقونة PDF احتياطية (لو ما توفّر ملف لتوليد المصغّرة).
    private var pdfIconPlaceholder: some View { ArchivePDFPlaceholder() }

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
            .dsGlyph(DS.Glyph.mdCompact, weight: .black)
            .foregroundColor(DS.Color.textSecondary)
            .frame(width: DS.Icon.discMini, height: DS.Icon.discMini)
            .background(Circle().fill(DS.Color.surface))
            .overlay(Circle().strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
            .dsSubtleShadow()
    }

    // MARK: - بطاقة المكتبة (طلب المالك ٢٠٢٦-١٠-٢٢/٢٣ — مربّعة صغيرة بنمط بطاقة المشاريع)
    //
    // التصنيف «لسان» ملف بلون المكتبة فوق حافة البطاقة، ومعاينة الوثيقة كبيرة بزوايا ناعمة (ختم السنة
    // البارز وشارة PDF عليها)، وتحتها العنوان في الوسط — بلا اسم من أضافها (يظهر داخل صفحة العنصر فقط).
    private func archiveCard(_ item: ArchiveItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            categoryTab(for: item)
            archiveCardBody(item)
                // زرّ القائمة يحاذي أعلى البطاقة نفسها لا أعلى اللسان
                .alignmentGuide(.archiveCardTop) { $0[.top] }
        }
    }

    /// لسان التصنيف — شكل لسان ملف بزاويتين علويّتين مدوّرتين، ملتصق بحافة البطاقة العليا (طلب المالك ٢٠٢٦-١٠-٢٣)
    private func categoryTab(for item: ArchiveItem) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            // رمز التصنيف قد يكون القبر المخصّص — `dsSymbol` يرسمه
            Image(dsSymbol: item.categoryIcon)
                .dsGlyph(DS.Glyph.micro)
            Text(item.categoryDisplayName)
                .dsFont(.micro)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundColor(DS.Color.textOnPrimary)
        .padding(.horizontal, DS.Spacing.sm)
        .frame(minHeight: DS.Icon.section)   // يطول مع «حجم النص» بدل قصّ الاسم
        .background(
            UnevenCorners(radius: DS.Radius.sm, topLeading: true, topTrailing: true,
                          bottomLeading: false, bottomTrailing: false)
                .fill(AppSection.library.fill)
        )
        .frame(maxWidth: (cardSide - DS.Spacing.md * 2), alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.leading, DS.Spacing.md)
        .accessibilityElement(children: .combine)
    }

    private func archiveCardBody(_ item: ArchiveItem) -> some View {
        let accent = item.categoryColor
        let inner = cardSide - DS.Spacing.sm * 2
        let imageRadius = max(DS.Card.radius - DS.Spacing.sm, DS.Radius.sm)

        return VStack(spacing: DS.Spacing.sm) {
            // الوثيقة + ختم السنة
            preview(for: item, accent: accent)
                .frame(width: inner, height: inner * 0.75)   // أكبر ما يمكن مع بقاء البطاقة مربّعة
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: imageRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: imageRadius, style: .continuous)
                        .strokeBorder(AppSection.library.ink.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width)
                )
                .overlay(alignment: .bottomTrailing) { yearStamp(for: item, accent: accent) }
                .overlay(alignment: .bottomLeading) { fileKindBadge(for: item) }
                .overlay(alignment: .topLeading) {
                    statusStack(for: item)
                        .padding(DS.Spacing.xs)
                }

            Text(item.title)
                .dsFont(.rowTitleCompact)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.Spacing.xxs)
            .padding(.bottom, DS.Spacing.xxs)
        }
        // شبه مربّعة صغيرة — بطاقتان في الصف (طلب المالك ٢٠٢٦-١٠-٢٣)؛ تطول فقط مع «حجم النص»
        .frame(width: inner)
        // البطاقة الواحدة (`.dsCard`) + إطار الحالة (بانتظار/مرفوض/مخفي) فوقها
        .dsCard(padding: DS.Spacing.sm)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
                .strokeBorder(borderColor(for: item), lineWidth: DS.Border.width)
        )
        .opacity(item.approvalStatus == .rejected ? DS.Opacity.disabled
                 : (item.isHidden || item.approvalStatus == .pending ? DS.Opacity.dimmed : 1.0))
    }

    /// ختم السنة — مائل قليلاً بحدود متقطّعة مثل أختام الأرشيف
    @ViewBuilder
    private func yearStamp(for item: ArchiveItem, accent: Color) -> some View {
        if let year = item.year {
            ArchiveYearStamp(year: year, accent: accent, filled: true, prominent: true)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.xsm)
        }
    }

    /// نوع الملف على حافة الوثيقة
    @ViewBuilder
    private func fileKindBadge(for item: ArchiveItem) -> some View {
        if item.isPDF {
            ArchivePDFBadge()
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.xsm)
        }
    }

    /// معاينة العنصر: صورة، أول صفحة PDF، أو ورقة بأيقونة التصنيف
    @ViewBuilder
    private func preview(for item: ArchiveItem, accent: Color) -> some View {
        ZStack {
            accent.opacity(DS.Opacity.tintFill)

            if item.isImage, let url = URL(string: item.fileUrl) {
                // scaledToFill داخل إطار ثابت — كل الوثائق بنفس المساحة
                // مهما اختلفت أبعاد الصورة (طلب المالك)
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    DSPageLoader(section: .library, size: DS.Icon.state, fillsSpace: false)
                }
            } else if item.isPDF {
                if let thumb = item.thumbnailUrl, let turl = URL(string: thumb) {
                    CachedAsyncImage(url: turl) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        DSPageLoader(section: .library, size: DS.Icon.state, fillsSpace: false)
                    }
                } else if let furl = URL(string: item.fileUrl) {
                    PDFThumbnailView(url: furl)
                } else {
                    pdfIconPlaceholder
                }
            } else {
                // رمز التصنيف قد يكون القبر المخصّص (ن-١ فحص ٢٠٢٦-١٠-٠٧)
                Image(dsSymbol: item.categoryIcon)
                    .dsGlyph(DS.Icon.sizeSm, weight: .light)
                    .foregroundColor(accent)
            }
        }
    }

    /// شارة الحالة (الأولوية: بانتظار > مرفوض > مخفي)
    @ViewBuilder
    private func statusStack(for item: ArchiveItem) -> some View {
        if item.approvalStatus == .pending {
            statusBadge(icon: "clock.fill", label: L10n.t("بانتظار", "Pending"), color: DS.Color.warningFill)
        } else if item.approvalStatus == .rejected {
            statusBadge(icon: "xmark.circle.fill", label: L10n.t("مرفوض", "Rejected"), color: DS.Color.errorFill)
        } else if item.isHidden {
            statusBadge(icon: "eye.slash.fill", label: L10n.t("مخفي", "Hidden"), color: DS.Color.slateFill)
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
        case .rejected: return DS.Color.error.opacity(DS.Opacity.tintStroke)
        case .pending:  return DS.Color.warning.opacity(DS.Opacity.tintStroke)
        case .approved: return item.isHidden ? DS.Color.textTertiary.opacity(DS.Opacity.tintStroke) : .clear
        }
    }

    /// شارة حالة موحّدة (capsule صغيرة بأيقونة + نص).
    private func statusBadge(icon: String, label: String, color: Color) -> some View {
        // فوق الصورة: ممتلئة بلون معناها حتى تُقرأ
        HStack(spacing: DS.Spacing.xxs) {
            Image(dsSymbol: icon).dsGlyph(DS.Glyph.xs)
            Text(label).dsFont(.badge)
        }
        .foregroundColor(DS.Color.textOnPrimary)
        .padding(.horizontal, DS.Spacing.xsm)
        .padding(.vertical, DS.Spacing.xxs)
        .background(Capsule().fill(color))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        // الصفحة الفاضية الموحّدة: مجسّم المكتبة + عنوان + سطر (أي مستخدم يضيف — للأعضاء بعد الموافقة)
        DSEmptyView(L10n.t("لا توجد عناصر في هذا القسم بعد", "No items in this section yet"),
                    message: authVM.isAdmin
                        ? L10n.t("اضغط + لإضافة عنصر", "Tap + to add an item")
                        : L10n.t("اضغط + لإضافة عنصر (سيُعرض بعد موافقة الإدارة)",
                                 "Tap + to add (visible after admin approval)"),
                    section: .library)
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

    /// ملف مختار أو نص مكتوب لم يُرفع — «إلغاء» يسأل قبل التجاهل (توصية أبل).
    /// «القسم» اختيار فقط فلا يُحتسب.
    private var hasUnsavedChanges: Bool {
        pickedFileData != nil
            || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !yearText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let tint = DS.Color.tileLibrary
    @State private var floatIcons = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pickedImage: UIImage? {
        guard pickedMimeType.hasPrefix("image/"), let pickedFileData else { return nil }
        return UIImage(data: pickedFileData)
    }

    var body: some View {
        DSComposer(
            title: L10n.t("إضافة إلى المكتبة", "Add to Library"),
            subtitle: L10n.t("وثيقة أو صورة من تاريخ العائلة", "A document or photo from family history"),
            icon: "books.vertical.fill",
            tint: tint,
            actionTitle: L10n.t("إضافة إلى المكتبة", "Add to Library"),
            actionIcon: "tray.and.arrow.down.fill",
            canSubmit: canSubmit,
            isBusy: archiveVM.isUploading,
            progress: archiveVM.isUploading ? archiveVM.uploadProgress : nil,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: { submit() },
            onCancel: { dismiss() }
        ) {
            // ── الملف ──
            DSComposerSection(title: L10n.t("الملف", "File"), icon: "doc.on.doc.fill", tint: tint,
                              trailing: pickedFileData == nil ? L10n.t("صورة أو PDF", "Photo or PDF") : nil,
                              index: 0) {
                if pickedFileData != nil {
                    pickedPreview
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
                } else {
                    HStack(spacing: DS.Spacing.sm) {
                        sourceCard(icon: "photo.fill", title: L10n.t("صورة", "Photo"),
                                   subtitle: L10n.t("من ألبوم الصور", "From your photos"),
                                   delay: 0) { showPhotoPicker = true }
                        sourceCard(icon: "doc.richtext.fill", title: L10n.t("ملف PDF", "PDF file"),
                                   subtitle: L10n.t("من الملفات", "From Files"),
                                   delay: 0.5) { showFileImporter = true }
                    }
                    .transition(.opacity)
                }
            }

            // ── تفاصيل العنصر ──
            DSComposerSection(title: L10n.t("تفاصيل العنصر", "Item Details"), icon: "tray.full.fill",
                              tint: tint, index: 1) {
                DSComposerField(icon: "textformat", label: L10n.t("العنوان *", "Title *"),
                                placeholder: L10n.t("مثلاً: شجرة العائلة 1965", "e.g. Family Tree 1965"),
                                text: $title, tint: tint, limit: 80)
                DSComposerField(icon: "calendar", label: L10n.t("السنة", "Year"),
                                placeholder: "1965", text: $yearText, tint: tint,
                                limit: 4, keyboard: .numberPad, ltr: true)
                DSComposerField(icon: "text.alignright", label: L10n.t("الوصف", "Description"),
                                placeholder: L10n.t("ملاحظات أو قصة العنصر", "Notes or the story behind it"),
                                text: $description, tint: tint, multiline: true, limit: 300)
            }

            // ── القسم ──
            DSComposerSection(title: L10n.t("القسم", "Section"), icon: "folder.fill", tint: tint, index: 2) {
                ArchiveCategoryChips(key: $categoryKey, tint: tint)
            }

            if let errorBanner {
                DSNoteCard(errorBanner, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: pickedFileData != nil)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { newItem in handlePhotoPick(newItem) }
        .onAppear {
            guard !reduceMotion else { return }   // أيقونات ثابتة مع «تقليل الحركة»
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { floatIcons = true }
        }
    }

    /// بطاقة مصدر كبيرة — الأيقونة تطفو بهدوء
    private func sourceCard(icon: String, title: String, subtitle: String, delay: Double,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: DS.Spacing.xsm) {
                // قرص «مجسّمات» الموحّد
                DSStateIcon(icon, tint: tint, size: DSBox.photoTile)
                    .accessibilityHidden(true)   // زخرفة — العنوان والوصف يُقرآن
                Text(title)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                Text(subtitle)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            // خانة «إضافة» المتقطّعة الموحّدة (نفس `DSAddChipLabel`)
            .background(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous).fill(DS.Color.background))
            .overlay(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
                .strokeBorder(tint.opacity(DSAddChipLabel.strokeOpacity), style: DSAddChipLabel.dash))
            .trialCardSkin(radius: DS.Card.radius)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    /// معاينة الملف المختار: الصورة نفسها، أو بطاقة PDF
    private var pickedPreview: some View {
        let size = ByteCountFormatter().string(fromByteCount: Int64(pickedFileData?.count ?? 0))
        return VStack(spacing: 0) {
            if let img = pickedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, DS.Color.shadowOverlay], startPoint: .top, endPoint: .bottom)
                            .frame(height: DS.Icon.sizeLg)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Label(size, systemImage: "photo")
                            .dsFont(.caption)
                            .foregroundColor(DS.Color.textOnPrimary)
                            .padding(DS.Spacing.sm)
                    }
            } else {
                HStack(spacing: DS.Spacing.md) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: "doc.richtext.fill")
                            .dsGlyph(DS.Icon.row, weight: .regular)
                            .foregroundColor(tint.dsReadableGlyph)
                            .accessibilityHidden(true)
                        ArchivePDFBadge()
                            .offset(x: DS.Spacing.xsm, y: DS.Spacing.xs)
                    }
                    .frame(width: DS.Icon.state, height: DS.Icon.sizeLg)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(pickedFileName.isEmpty ? L10n.t("ملف مختار", "Selected file") : pickedFileName)
                            .dsFont(.rowTitle)
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(2)
                        Text(size)
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(DS.Spacing.md)
            }
            // «تغيير» و«إزالة» بالشريحة الموحّدة (مساحة ضغط ٤٤)
            HStack(spacing: DS.Spacing.sm) {
                DSChipButton(L10n.t("تغيير", "Change"), icon: "arrow.triangle.2.circlepath", tint: tint) {
                    if pickedMimeType == "application/pdf" { showFileImporter = true } else { showPhotoPicker = true }
                }
                Spacer(minLength: 0)
                DSChipButton(L10n.t("إزالة", "Remove"), icon: "trash", tint: DS.Color.error) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        pickedFileData = nil
                        pickedFileName = ""
                        pickedMimeType = ""
                        photoItem = nil
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(DS.Color.background)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
            .strokeBorder(tint.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
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
        _initial = State(initialValue: Fields(title: item.title, description: item.description ?? "",
                                              year: item.year.map(String.init) ?? "",
                                              categoryKey: item.effectiveCategoryKey))
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    // MARK: - تغييرات لم تُحفظ (توصية أبل)

    private struct Fields: Equatable {
        var title: String
        var description: String
        var year: String
        var categoryKey: String

        /// بلا فراغات الأطراف — فراغ زائد وحده لا يُعدّ تعديلاً
        var normalized: Fields {
            Fields(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                   description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                   year: year.trimmingCharacters(in: .whitespacesAndNewlines),
                   categoryKey: categoryKey)
        }
    }

    /// القيم التي فُتح بها المربّع — تُلتقط مرة واحدة
    @State private var initial: Fields

    /// أي حقل يختلف عمّا فُتح به المربّع — «إلغاء» يسأل قبل التجاهل
    private var hasUnsavedChanges: Bool {
        Fields(title: title, description: description, year: yearText, categoryKey: categoryKey).normalized
            != initial.normalized
    }

    private let tint = DS.Color.tileLibrary

    var body: some View {
        // نفس مربّع «إضافة إلى المكتبة» (طلب المالك): تصميم موحّد للإضافة والتعديل
        DSComposer(
            title: L10n.t("تعديل العنصر", "Edit Item"),
            subtitle: item.title,
            icon: "books.vertical.fill",
            tint: tint,
            actionTitle: L10n.t("حفظ", "Save"),
            actionIcon: "checkmark",
            canSubmit: canSave,
            isBusy: isSaving,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: { save() },
            onCancel: { dismiss() }
        ) {
            DSComposerSection(title: L10n.t("تفاصيل العنصر", "Item Details"), icon: "tray.full.fill",
                              tint: tint, index: 0) {
                DSComposerField(icon: "textformat", label: L10n.t("العنوان *", "Title *"),
                                placeholder: L10n.t("عنوان العنصر", "Item title"),
                                text: $title, tint: tint, limit: 80)
                DSComposerField(icon: "calendar", label: L10n.t("السنة", "Year"),
                                placeholder: "1965", text: $yearText, tint: tint,
                                limit: 4, keyboard: .numberPad, ltr: true)
                DSComposerField(icon: "text.alignright", label: L10n.t("الوصف", "Description"),
                                placeholder: L10n.t("ملاحظات أو قصة العنصر", "Notes or the story behind it"),
                                text: $description, tint: tint, multiline: true, limit: 300)
            }
            DSComposerSection(title: L10n.t("القسم", "Section"), icon: "folder.fill", tint: tint, index: 1) {
                ArchiveCategoryChips(key: $categoryKey, tint: tint)
            }
            if let errorBanner {
                DSNoteCard(errorBanner, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
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
    /// الصورة مكبّرة بملء الشاشة (طلب المالك ٢٠٢٦-١٠-٢٣ «اضغط الصورة تكبر»)
    @State private var showFullImage = false
    /// ارتفاع الرأس — المربّع بالمنتصف على قدر محتواه (`dsPanelContentHeight`)
    @State private var headerH: CGFloat = 0
    @Environment(\.verticalSizeClass) private var vSizeClass
    /// ارتفاع المعاينة — أصغر (طلب المالك ٢٠٢٦-١٠-٢٣: ٢٣٠ ← ١٧٠، والأفقي ١٥٠ ← ١١٠)
    private var previewHeight: CGFloat { vSizeClass == .compact ? 110 : 170 }

    private var accent: Color { item.categoryColor }

    // MARK: - صفحة العنصر — «ورقة أرشيف» + بطاقة فهرسة
    //
    // الوثيقة تُعرض مثبّتة على ورقة بيضاء بظل خفيف، وتحتها بطاقة فهرسة
    // فيها التصنيف وختم السنة والعنوان والوصف ومن أضافها (طلب المالك).
    var body: some View {
        VStack(spacing: 0) {
            // الرأس الموحّد (`DSSubPageHeader`) بلون المكتبة: × للإغلاق، وزرّ الحفظ/المشاركة في الطرف
            DSSubPageHeader(title: item.title, subtitle: item.categoryDisplayName, section: .library,
                            nav: .close, onBack: { dismiss() }) {
                DSHeaderButton(symbol: downloading ? "hourglass" : "square.and.arrow.down",
                               label: L10n.t("حفظ أو مشاركة", "Save or share")) {
                    Task { await downloadAndShare() }
                }
                .disabled(downloading)
            }
            .readHeight($headerH)

            // داخل المربّع بالمنتصف: معاينة بارتفاع معتدل ثم بطاقة الفهرسة — يتمرّر إن طال (نص كبير/أفقي)
            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) {
                    documentSheet
                        .frame(maxWidth: .infinity)
                        .frame(height: previewHeight)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.md)

                    indexCard
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.md)
                }
                .dsPanelContentHeight(extra: headerH)
            }
            .frame(maxHeight: .infinity)
            .background(
                LinearGradient(colors: [accent.opacity(DS.Opacity.tintFill), DS.Color.background],
                               startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
            )
        }
        .fullScreenCover(isPresented: $showFullImage) {
            ProjectPhotoViewer(urls: [item.fileUrl], startIndex: 0, section: .library)
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .dsSectionPage(.library)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// الوثيقة مثبّتة على ورقة بظل — الضغط على الصورة يفتحها مكبّرة بملء الشاشة (وفيها القرصة والضغطتان)
    private var documentSheet: some View {
        Group {
            if item.isPDF, let url = URL(string: item.fileUrl) {
                ArchivePDFView(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            } else if item.isImage, let url = URL(string: item.fileUrl) {
                Button { showFullImage = true } label: {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        DSPageLoader(section: .library)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DSScaleButtonStyle())
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                .accessibilityLabel(L10n.t("تكبير الصورة", "Enlarge image"))
            } else {
                // الحالة الموحّدة: مجسّم + عنوان + زرّ الحفظ
                DSEmptyView(L10n.t("لا يمكن عرض هذا الملف داخل التطبيق", "This file can't be previewed in the app"),
                            section: .library, icon: "doc.questionmark",
                            actionTitle: L10n.t("حفظ الملف", "Save file"), actionIcon: "square.and.arrow.down",
                            compact: true) {
                    Task { await downloadAndShare() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // الورقة = البطاقة الواحدة (`.dsCard`)
        .dsCard()
    }

    /// بطاقة فهرسة: تصنيف + ختم سنة + عنوان + وصف + من أضافها ومتى
    private var indexCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSStatusChip(text: item.categoryDisplayName, icon: item.categoryIcon, tint: accent)

                if item.isPDF || !item.formattedSize.isEmpty {
                    Text([item.isPDF ? "PDF" : nil, item.formattedSize.isEmpty ? nil : item.formattedSize]
                            .compactMap { $0 }.joined(separator: " · "))
                        .dsFont(.micro)
                        .foregroundColor(DS.Color.textTertiary)
                }

                Spacer(minLength: 0)

                if let year = item.year {
                    ArchiveYearStamp(year: year, accent: accent)
                }
            }

            Text(item.title)
                .dsFont(.title)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // تاريخ الإضافة تحت العنوان مباشرة (طلب المالك ٢٠٢٦-١٠-٢٣) — نفس عرض التواريخ في التطبيق
            let added = DSDateText.display(item.createdAt)
            Text(L10n.t("أُضيف: \(added)", "Added: \(added)"))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let desc = item.description, !desc.isEmpty {
                Text(desc)
                    .dsFont(.callout)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // من أضاف العنصر — هنا فقط لا على البطاقة (طلب المالك ٢٠٢٦-١٠-٢٢)؛ التاريخ صار تحت العنوان
            if let uploaderName, !uploaderName.isEmpty {
                Rectangle()
                    .fill(accent.opacity(DS.Opacity.tintStroke))
                    .frame(height: DS.Border.width)

                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "person.fill")
                        .dsGlyph(DS.Glyph.micro)
                    Text(L10n.t("أضافه: \(uploaderName)", "Added by: \(uploaderName)"))
                        .dsFont(.caption)
                        .lineLimit(1)
                }
                .foregroundColor(DS.Color.textTertiary)
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        // شريط لون التصنيف على الحافة — داخل حدود البطاقة الواحدة
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: DS.Spacing.xs)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous))
        .dsCard(padding: nil)
    }

    /// تحميل الملف لمجلد مؤقت ثم فتح share sheet للحفظ في Files / مشاركة.
    private func downloadAndShare() async {
        guard let url = URL(string: item.fileUrl) else { return }
        downloading = true
        defer { downloading = false }
        do {
            // الصور الخاصة: رابط موقَّع إن أمكن (وإلا الأصلي)
            let fetchURL = await StorageURLResolver.shared.displayURL(for: url)
            let (tempURL, _) = try await URLSession.shared.download(from: fetchURL)
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
            // الصور الخاصة: رابط موقَّع إن أمكن (وإلا الأصلي)
            let fetchURL = await StorageURLResolver.shared.displayURL(for: url)
            if let data = try? Data(contentsOf: fetchURL),
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
                ArchivePDFPlaceholder()
            } else {
                DSPageLoader(section: .library, size: DS.Icon.state, fillsSpace: false)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        if let cached = PDFThumbCache.shared.object(forKey: url as NSURL) {
            image = cached
            return
        }
        // الصور الخاصة: رابط موقَّع إن أمكن (وإلا الأصلي) — المصغّرة تبقى مخزّنة بالرابط المحفوظ
        let fetchURL = await StorageURLResolver.shared.displayURL(for: url)
        let rendered = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let data = try? Data(contentsOf: fetchURL),
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


/// أقسام المكتبة — الفلاتر الموحّدة (`DSFilterChips`) — مشتركة بين الإضافة والتعديل
struct ArchiveCategoryChips: View {
    @Binding var key: String
    var tint: Color = DS.Color.tileLibrary

    var body: some View {
        DSFilterChips(options: ArchiveItem.selectableCategoryKeys.map {
                          DSFilterOption(id: $0, title: ArchiveItem.categoryName($0), icon: ArchiveItem.categoryIcon($0))
                      },
                      selection: $key, tint: tint)
    }
}

// MARK: - قطع «الملف الأرشيفي» المشتركة (البطاقة، صفحة العنصر، مربّع الإضافة)

/// ختم السنة — مائل قليلاً بحدود متقطّعة مثل أختام الأرشيف
/// أعلى بطاقة المكتبة نفسها (تحت لسان التصنيف) — يحاذي زرّ القائمة بها
extension VerticalAlignment {
    private enum ArchiveCardTop: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.top] }
    }
    static let archiveCardTop = VerticalAlignment(ArchiveCardTop.self)
}

struct ArchiveYearStamp: View {
    let year: Int
    let accent: Color
    /// على الصورة: بسطح يفصله عنها
    var filled: Bool = false
    /// على بطاقة المكتبة: رقم أكبر وأثقل يُقرأ من بعيد (طلب المالك ٢٠٢٦-١٠-٢٣)
    var prominent: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Icon.discRadiusSmall / 2, style: .continuous)
        Text(verbatim: String(year))
            .dsFont(prominent ? .statValue : .badge)
            .foregroundColor(accent)
            .padding(.horizontal, prominent ? DS.Spacing.sm : DS.Spacing.xsm)
            .padding(.vertical, DS.Spacing.xxs)
            .background(shape.fill(filled ? DS.Color.surface : .clear))
            .overlay(shape.strokeBorder(accent.opacity(DS.Opacity.selectedStroke), style: DSAddChipLabel.dash))
            .rotationEffect(.degrees(-7))
    }
}

/// شارة «PDF» الحمراء الصغيرة
struct ArchivePDFBadge: View {
    var body: some View {
        Text("PDF")
            .dsFont(.micro)
            .foregroundColor(DS.Color.textOnPrimary)
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, DS.Spacing.xxs / 2)
            .background(Capsule().fill(DS.Color.errorFill))
    }
}

/// أيقونة PDF احتياطية (لو ما توفّرت مصغّرة)
struct ArchivePDFPlaceholder: View {
    var body: some View {
        VStack(spacing: DS.Spacing.xsm) {
            Image(systemName: "doc.text.fill")
                .dsGlyph(DS.Icon.rowLarge, weight: .light)
                .foregroundColor(AppSection.library.ink)
            Text("PDF")
                .dsFont(.badge)
                .foregroundColor(AppSection.library.ink)
                .padding(.horizontal, DS.Spacing.xsm)
                .padding(.vertical, DS.Spacing.xxs / 2)
                .background(Capsule().fill(AppSection.library.ink.opacity(DS.Opacity.tintFill)))
        }
    }
}
