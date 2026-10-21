import SwiftUI

// MARK: - إدارة التصنيفات — في «إعدادات التطبيق» (طلب المالك)
//
// لكل قسم فيه تصنيفات (الأخبار، مكتبة العائلة): تعديل الاسم والأيقونة واللون،
// إخفاء/إظهار (بدون حذف — المحتوى القديم يبقى بتصنيفه)، ترتيب، وإضافة للأخبار.
//
// بشكل «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠، `AdminPageKit`): رأس كحلي بأرقامه الحيّة وشريحتي القسمين بعددهما وزرّ «إضافة»
// للمالك (وشارة «للقراءة» لغيره) ← بطاقة التوضيح تصعد فوقه ← عنوان القسم ← كل تصنيف بطاقة بيضاء داخل `List`
// (`AdminPage(layout: .list)` — بقيت لأجل السحب لإعادة الترتيب والسحب للتحديث). التعديل والإضافة والحذف والترتيب
// للمالك فقط (`canManageSettings`) وبنفس المربّعات والتأكيدات كما كانت تماماً.

struct CategoriesManagerView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var store = CategoryStore.shared
    @State private var section: CategorySection = .news
    @State private var editing: ContentCategory?
    @State private var showAdd = false
    /// التصنيف المطلوب حذفه من القائمة — ينتظر التأكيد
    @State private var pendingDelete: ContentCategory?
    @State private var deleteError: String?
    /// اكتمل أول جلب — قبله «—» في الأرقام وبطاقة تحميل (إن لم تكن التصنيفات محمّلة أصلاً)
    @State private var hasLoaded = false
    /// جلب جارٍ (الفتح أو السحب للتحديث أو «إعادة المحاولة»)
    @State private var isFetching = false
    /// آخر جلب انتهى والجهاز غير متصل — لبطاقة «تعذّر التحميل» بدل قائمة فارغة مضلِّلة
    @State private var lastFetchOffline = false
    /// دخول صفوف التصنيفات (نمط الأخبار والديوانيات) — مرة واحدة، بعد عنوان القسم
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// لون قسم «التصنيفات» في إعدادات التطبيق (مجال المحتوى) — رأس الصفحة يطابق ما ضُغط
    private let pageTint = DS.Color.composerLibrary

    private var canEdit: Bool { authVM.canManageSettings }

    var body: some View {
        let items = store.list(section, activeOnly: false)

        return AdminPage(header: header, lead: leadCard, layout: .list, content: AnyView(listRows(items)))
            .environment(\.editMode, editModeBinding)
            .task { await loadCategories() }
            .refreshable { await loadCategories() }
            // تعديل/إضافة تصنيف — مربّع بمنتصف الشاشة بدل الورقة السفلية
            .dsCenterBox(item: $editing) { category in
                CategoryEditSheet(category: category, isNew: false, section: section)
            }
            .dsCenterBox(isPresented: $showAdd) {
                CategoryEditSheet(category: nil, isNew: true, section: section)
            }
            .dsAlert(L10n.t("حذف التصنيف", "Delete Category"),
                     isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { pendingDelete = nil }
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    let target = pendingDelete
                    pendingDelete = nil
                    if let target {
                        Task { if !(await store.delete(target)) { deleteError = store.errorMessage } }
                    }
                }
            } message: {
                Text(L10n.t("«\(pendingDelete?.nameAr ?? "")» ينحذف نهائياً من التصنيفات.",
                            "«\(pendingDelete?.nameAr ?? "")» will be permanently deleted."))
            }
            .dsAlert(L10n.t("تعذّر الحذف", "Couldn't delete"),
                     isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button(L10n.t("حسناً", "OK")) { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// عنوان القسم المختار ← التصنيفات (بطاقة لكل تصنيف، تُسحب لإعادة الترتيب)
    @ViewBuilder
    private func listRows(_ items: [ContentCategory]) -> some View {
        if !isInitialLoading && !loadFailed {
            sectionTitle(count: items.count)
                // العنوان يظهر مع الصفوف (بعد التحميل) — فتبدأ الصفوف بعده
                .onAppear(perform: startRowsCascade)
                .adminPageRow(top: DS.Hub.stackSpacing, bottom: 0)

            if items.isEmpty {
                emptySection
                    .padding(.vertical, DS.Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .adminCard()
                    .adminPageRow(top: DS.Spacing.xs)
            } else {
                categoriesRows(items)
            }
        }
    }

    private var editModeBinding: Binding<EditMode> {
        Binding.constant(canEdit ? EditMode.active : EditMode.inactive)
    }

    // MARK: - التحميل

    /// نفس الجلب السابق تماماً (`fetch` ثم `fetchCounts`) — ويحفظ اكتماله وهل انتهى بلا اتصال
    private func loadCategories() async {
        isFetching = true
        await store.fetch()
        await store.fetchCounts()
        lastFetchOffline = !NetworkMonitor.shared.isConnected
        isFetching = false
        hasLoaded = true
    }

    /// أول تحميل (أو «إعادة المحاولة») ولا تصنيفات محمّلة بعد
    private var isInitialLoading: Bool {
        store.categories.isEmpty && (isFetching || !hasLoaded)
    }

    /// الجلب انتهى بلا تصنيفات والجهاز غير متصل
    private var loadFailed: Bool {
        store.categories.isEmpty && hasLoaded && !isFetching && lastFetchOffline
    }

    // MARK: - الرأس الكحلي

    /// ٣ أرقام حيّة من التصنيفات المحمّلة أصلاً (بلا طلبات جديدة للسيرفر): كلها، الظاهرة، والمخفية —
    /// وشريحتا القسمين بعدد تصنيفات كل منهما (كانتا فلاتر تحت الرأس). «—» قبل اكتمال أول تحميل.
    /// «إضافة تصنيف» للمالك في الأقسام التي تقبل الإضافة (كان زرّاً أسفل القائمة).
    private var header: AdminPageHeader {
        let all = CategorySection.allCases.flatMap { store.list($0, activeOnly: false) }
        let visible = all.filter(\.isActive).count
        let pending = isInitialLoading || loadFailed
        return AdminPageHeader(
            title: L10n.t("التصنيفات", "Categories"),
            subtitle: L10n.t("الاسم والأيقونة واللون، والإخفاء والترتيب", "Name, icon, colour, hide and order"),
            glyph: "tag.fill",
            readOnly: !canEdit,
            kpis: [
                AdminPageKPI(pending ? "—" : "\(all.count)", L10n.t("الكل", "All"), icon: "tag.fill"),
                AdminPageKPI(pending ? "—" : "\(visible)", L10n.t("ظاهر", "Visible"), icon: "eye.fill",
                             tint: DS.Hub.kpiMine),
                AdminPageKPI(pending ? "—" : "\(all.count - visible)", L10n.t("مخفي", "Hidden"), icon: "eye.slash.fill")
            ],
            actions: canEdit && section.allowsAdding && !pending
                ? [AdminPageAction(symbol: "plus", label: L10n.t("إضافة تصنيف", "Add category"),
                                   tap: .action { showAdd = true })]
                : [],
            chips: pending ? [] : CategorySection.allCases.map { item in
                let n = store.list(item, activeOnly: false).count
                return AdminPageChip(id: item.rawValue, title: item.title, count: n > 0 ? n : nil,
                                     icon: sectionIcon(item), selected: section == item) { section = item }
            })
    }

    /// أول بطاقة (تصعد فوق الرأس): التحميل، أو تعذّره، أو التوضيح
    private var leadCard: AnyView {
        if isInitialLoading {
            return AnyView(AdminPageStateCard(.loading(L10n.t("جارٍ تحميل التصنيفات…", "Loading categories…"))))
        }
        if loadFailed {
            return AnyView(AdminPageStateCard(.error(L10n.t("تعذّر تحميل التصنيفات", "Couldn't load categories"),
                                                     message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى",
                                                                     "Check your connection and try again"),
                                                     retry: { Task { await loadCategories() } })))
        }
        return AnyView(hintRow.adminCard())
    }

    // MARK: - القسم (الأخبار / مكتبة العائلة)

    private func sectionIcon(_ item: CategorySection) -> String {
        switch item {
        case .news:    return "newspaper.fill"
        case .archive: return "books.vertical.fill"
        }
    }

    /// نفس نص التوضيح السابق — بطاقة تصعد فوق الرأس
    private var hintRow: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: canEdit ? "info.circle.fill" : "lock.fill",
                            tint: canEdit ? pageTint : DS.Color.textTertiary)
            Text(footerText)
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var footerText: String {
        var text = L10n.t("اضغط على التصنيف لتعديل اسمه وأيقونته ولونه أو إخفائه. التصنيف المخفي يختفي من الاختيارات، والمحتوى القديم يبقى بتصنيفه.",
                          "Tap a category to edit its name, icon and colour, or hide it. Hidden categories disappear from choices; existing content keeps its category.")
        if section == .archive {
            text += "\n" + L10n.t("التصنيف الجديد في المكتبة يظهر لمن لم يحدّث التطبيق تحت «أخرى».",
                                  "New library categories show as «Other» for members who haven't updated.")
        }
        if !canEdit {
            text += "\n" + L10n.t("التعديل متاح للمالك فقط.", "Only the owner can edit.")
        }
        return text
    }

    /// عنوان القسم المختار — للمالك «اسحب لإعادة الترتيب» (كما كان)، ولغيره عدد التصنيفات
    private func sectionTitle(count: Int) -> some View {
        AdminSectionLabel(title: L10n.t("تصنيفات \(section.title)", "\(section.title) categories"),
                          trailing: canEdit
                            ? L10n.t("اسحب لإعادة الترتيب", "Drag to reorder")
                            : L10n.t("\(count) تصنيف", count == 1 ? "1 category" : "\(count) categories"))
    }

    // MARK: - التصنيفات

    private func categoriesRows(_ items: [ContentCategory]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, category in
            Button {
                if canEdit { editing = category }
            } label: {
                row(category)
            }
            .buttonStyle(.plain)
            .accessibilityHint(canEdit ? L10n.t("يفتح تعديل التصنيف", "Opens category editing") : "")
            .moveDisabled(!canEdit)
            // نمط الأخبار والديوانيات: أول ٧ تصعد تباعاً، وما يُبنى بالتمرير يظهر مباشرة
            .dsCardCascade(index, appeared: appeared)
            .adminPageRow()
        }
        .onMove { source, destination in
            if canEdit { move(from: source, to: destination) }
        }
    }

    /// الصفوف تدخل بعد أقسام الصفحة فوقها (الفلاتر والتوضيح ← العنوان = ٢) — من حيث كانت تبدأ (٣)،
    /// فيبقى التسلسل: الرأس ← الأقسام ← الصفوف. مرة واحدة؛ «تقليل الحركة»: تلاشٍ فوري بلا انتظار.
    private func startRowsCascade() {
        guard !appeared else { return }
        guard !reduceMotion else { appeared = true; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.staggerDelay(3, base: DSMotion.sectionsOnPage)) {
            appeared = true
        }
    }

    /// لا تصنيفات في القسم المختار
    private var emptySection: some View {
        DSEmptyView(L10n.t("لا توجد تصنيفات", "No categories"),
                    message: canEdit && section.allowsAdding
                        ? L10n.t("أضف تصنيفاً من زر + في الأعلى", "Add one with the + button above")
                        : nil,
                    style: .compact)
    }

    /// بطاقة تصنيف: أيقونة التصنيف بلونه + الاسم (وعدد عناصره جنبه) + الاسم الإنجليزي،
    /// وشارة «مخفي» وزر الحذف (للتصنيف الفارغ غير الأساسي) في الطرف
    private func row(_ category: ContentCategory) -> some View {
        let count = store.itemCount(category)
        return HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: category.symbol,
                            tint: category.isActive ? category.color : DS.Color.textTertiary)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xsm) {
                    Text(category.nameAr)
                        .dsFont(.hubRow)
                        .foregroundColor(category.isActive ? DS.Color.textPrimary : DS.Color.textTertiary)
                        .lineLimit(1)
                    // عدد العناصر — رقم فقط جنب الاسم (طلب المالك)
                    AdminValueChip(text: "\(count)", tint: count > 0 ? category.color : DS.Color.textTertiary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.t("\(count) عنصر", count == 1 ? "1 item" : "\(count) items"))
                }
                Text(category.nameEn)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            if !category.isActive {
                DSStatusChip(text: L10n.t("مخفي", "Hidden"), icon: "eye.slash.fill", tint: DS.Color.textTertiary)
            }
            // حذف من برّا — للتصنيف الفارغ غير الأساسي فقط
            if canEdit && count == 0 && !store.isProtected(category) {
                Button {
                    pendingDelete = category
                } label: {
                    Image(systemName: "trash")
                        .dsGlyph(DS.Glyph.mdCompact)
                        .foregroundColor(DS.Color.error)
                        .frame(width: DS.Icon.discSmall, height: DS.Icon.discSmall)
                        .background(Circle().fill(DS.Color.error.opacity(DS.Opacity.tintFill)))
                        // مساحة ضغط ٤٤ نقطة والشكل كما هو
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                        .padding(.vertical, -DS.Spacing.xsm)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("حذف التصنيف", "Delete category"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Hub.cardPadding)
        .padding(.vertical, DS.Spacing.md)
        .adminCard(padding: nil)
        .contentShape(Rectangle())
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = store.list(section, activeOnly: false).map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        let current = section
        Task { await store.reorder(current, ids: ids) }
    }
}

/// مربّع تعديل/إضافة تصنيف — الاسم بالعربي والإنجليزي، الأيقونة، اللون، الظهور.
/// نفس هيكل مربّعات الإضافة (طلب المالك): رأس كحلي يحمل أيقونة التصنيف، أقسام،
/// و«إضافة/حفظ» كحلي يمين / «إلغاء» رمادي يسار.
struct CategoryEditSheet: View {
    let category: ContentCategory?
    let isNew: Bool
    let section: CategorySection

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = CategoryStore.shared
    @State private var nameAr: String
    @State private var nameEn: String
    @State private var iconKey: String
    @State private var colorKey: String
    @State private var isActive: Bool
    @State private var saving = false
    @State private var errorText: String?
    @State private var confirmDelete = false
    /// ما فُتح عليه المربّع — «إلغاء» يسأل فقط إذا تغيّر شيء (توصية أبل)
    private let startAr: String
    private let startEn: String
    private let startIcon: String
    private let startColor: String
    private let startActive: Bool

    init(category: ContentCategory?, isNew: Bool, section: CategorySection) {
        self.category = category
        self.isNew = isNew
        self.section = section
        // تعبئة بيانات التصنيف من البداية (كانت في onAppear) — حتى لا تومض أيقونة
        // الرأس من الافتراضية إلى أيقونة التصنيف
        let ar = category?.nameAr ?? ""
        let en = category?.nameEn ?? ""
        let icon = category?.iconKey ?? "star.fill"
        let color = category?.colorKey ?? "navy"
        let active = category?.isActive ?? true
        _nameAr = State(initialValue: ar)
        _nameEn = State(initialValue: en)
        _iconKey = State(initialValue: icon)
        _colorKey = State(initialValue: color)
        _isActive = State(initialValue: active)
        startAr = ar
        startEn = en
        startIcon = icon
        startColor = color
        startActive = active
    }

    private var accent: Color { CategoryPalette.color(colorKey) }

    /// اسم أو أيقونة أو لون أو ظهور مختلف عمّا فُتح عليه المربّع
    private var hasChanges: Bool {
        nameAr != startAr || nameEn != startEn || iconKey != startIcon
            || colorKey != startColor || isActive != startActive
    }

    var body: some View {
        DSComposer(
            title: isNew ? L10n.t("تصنيف جديد", "New Category") : L10n.t("تعديل التصنيف", "Edit Category"),
            subtitle: L10n.t("تصنيفات \(section.title)", "\(section.title) categories"),
            icon: iconKey,
            tint: DS.Color.actionNavy,
            actionTitle: isNew ? L10n.t("إضافة", "Add") : L10n.t("حفظ", "Save"),
            actionIcon: isNew ? "plus" : "checkmark",
            canSubmit: !nameAr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            isBusy: saving,
            hasUnsavedChanges: hasChanges,
            onSubmit: { Task { await save() } },
            onCancel: { dismiss() }
        ) {
            preview.dsStaggerIn(0)
            namesSection
            iconSection
            colorSection

            if !isNew {
                visibilitySection
            }

            if let category, !isNew, !store.isProtected(category) {
                deleteCard(category)
                    .dsStaggerIn(5)
            }

            if let errorText {
                DSNoteCard(errorText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: الأقسام

    /// معاينة شارة التصنيف كما ستظهر
    private var preview: some View {
        HStack(spacing: DS.Spacing.xs) {
            // ن-١ فحص ٢٠٢٦-١٠-٠٧: رمز «وفاة» (القبر) من الأصول — `systemName` كان يظهره فارغاً
            Image(dsSymbol: CategoryPalette.symbol(iconKey)).dsGlyph(DS.Glyph.sm)
                .accessibilityHidden(true)
            Text(nameAr.isEmpty ? L10n.t("اسم التصنيف", "Category name") : nameAr)
                .dsFont(.rowTitleCompact)
        }
        .foregroundColor(DS.Color.textOnPrimary)
        .padding(.horizontal, DS.Spacing.md)
        .frame(minHeight: DS.Icon.row)   // يطول مع «حجم النص» بدل قصّ الاسم
        .background(Capsule().fill(accent))
        .opacity(isActive ? 1 : DS.Opacity.disabled)
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xs)
    }

    private var namesSection: some View {
        DSComposerSection(title: L10n.t("الاسم", "Name"), icon: "tag.fill",
                          tint: AppSection.admin.ink, index: 1) {
            DSComposerField(icon: "textformat",
                            label: L10n.t("الاسم بالعربي", "Arabic name"),
                            placeholder: L10n.t("اسم التصنيف", "Category name"),
                            text: $nameAr)
            DSComposerField(icon: "globe",
                            label: L10n.t("الاسم بالإنجليزي", "English name"),
                            placeholder: L10n.t("اختياري", "Optional"),
                            text: $nameEn,
                            ltr: true,
                            ltrKeepsAutocorrect: true)
        }
    }

    private var iconSection: some View {
        DSComposerSection(title: L10n.t("الأيقونة", "Icon"), icon: "square.grid.2x2.fill",
                          tint: DS.Color.info, index: 2) {
            // صفوف عادية لا LazyVGrid — الشبكة الكسولة تُبلِّغ ارتفاعاً ناقصاً فيُقصّ آخر صف
            // (المسافة ٦ + نقطة ضغط زائدة فوق وتحت كل زر = نفس الفراغ الظاهر ٨ كما كان)
            gridRows(CategoryPalette.icons, columns: 5, spacing: DS.Spacing.xsm) { icon in
                Button { iconKey = icon } label: {
                    // رمز القبر المخصّص يُرسم من الأصول (ن-١ فحص ٢٠٢٦-١٠-٠٧)
                    Image(dsSymbol: CategoryPalette.symbol(icon))
                        .dsGlyph(DS.Glyph.lg)
                        .foregroundColor(iconKey == icon ? DS.Color.textOnPrimary : accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: DS.Icon.tapTarget - DS.Spacing.xxs)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(iconKey == icon ? accent : accent.opacity(DS.Opacity.tintFill)))
                        // مساحة ضغط ٤٤ (توصية أبل) — الزر الظاهر ٤٢ كما هو
                        .frame(height: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // زر أيقونة بلا نص — اسمها للقارئ الصوتي، والمختارة «محدّدة»
                .accessibilityLabel(CategoryEditA11yNames.icon(icon))
                .accessibilityAddTraits(iconKey == icon ? .isSelected : [])
            }
        }
    }

    private var colorSection: some View {
        DSComposerSection(title: L10n.t("اللون", "Colour"), icon: "paintpalette.fill",
                          tint: DS.Color.accent, index: 3) {
            // كل لون بخانة ٤٤ نقطة ارتفاعاً وبعرض خانته كاملاً (بلا فراغ بين الخانات) —
            // الدوائر بنفس حجمها وتقريباً بنفس مواضعها، والحشوة السالبة تبقي ارتفاع الشبكة
            gridRows(CategoryPalette.colorKeys, columns: 7, spacing: 0, hSpacing: 0) { key in
                Button { colorKey = key } label: {
                    Circle()
                        .fill(CategoryPalette.color(key))
                        .frame(width: DS.Icon.row, height: DS.Icon.row)
                        .overlay(Circle().strokeBorder(DS.Color.textOnPrimary,
                                                       lineWidth: colorKey == key ? DS.Border.widthBold * 2 : 0))
                        .overlay(Circle().strokeBorder(CategoryPalette.color(key),
                                                       lineWidth: colorKey == key ? DS.Border.widthBold : 0)
                            .padding(-DS.Spacing.xxs))
                        // مساحة ضغط ٤٤ (توصية أبل)
                        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // زر لون بلا نص — اسم اللون للقارئ الصوتي، والمختار «محدّد»
                .accessibilityLabel(CategoryEditA11yNames.color(key))
                .accessibilityAddTraits(colorKey == key ? .isSelected : [])
            }
            .padding(.vertical, -DS.Spacing.xsm)
        }
    }

    private var visibilitySection: some View {
        DSComposerSection(title: L10n.t("الظهور", "Visibility"), icon: "eye.fill",
                          tint: DS.Color.success, index: 4) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: isActive ? "eye.fill" : "eye.slash.fill",
                            tint: isActive ? DS.Color.success : DS.Color.textTertiary)
                    .accessibilityHidden(true)
                Toggle(isOn: $isActive) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(L10n.t("ظاهر للأعضاء", "Visible to members"))
                            .dsFieldFont(.rowTitle)
                            .foregroundColor(DS.Color.fieldLabel)
                        Text(L10n.t("الإخفاء يشيله من الاختيارات، والمحتوى القديم يبقى بتصنيفه",
                                    "Hiding removes it from choices; existing content keeps it"))
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(AppSection.admin.ink)
            }
            .dsRowBox()
        }
    }

    /// شبكة غير كسولة: صفوف من `columns` عناصر، والصف الناقص يُكمَّل بفراغ
    /// (`hSpacing` المسافة بين الخانات — ٠ للألوان حتى تأخذ كل خانة أوسع مساحة ضغط)
    private func gridRows<Item: Hashable, Cell: View>(_ items: [Item], columns: Int, spacing: CGFloat,
                                                      hSpacing: CGFloat = DS.Spacing.sm,
                                                      @ViewBuilder cell: @escaping (Item) -> Cell) -> some View {
        VStack(spacing: spacing) {
            ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { start in
                let end = min(start + columns, items.count)
                HStack(spacing: hSpacing) {
                    ForEach(items[start..<end], id: \.self) { item in
                        cell(item).frame(maxWidth: .infinity)
                    }
                    ForEach(0..<(columns - (end - start)), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: DS.Border.width)
                    }
                }
            }
        }
    }

    /// حذف نهائي — متاح فقط إذا كان التصنيف فارغاً؛ غير ذلك يُقترح الإخفاء
    private func deleteCard(_ category: ContentCategory) -> some View {
        let count = store.itemCount(category)
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            // الزرّ الواحد بالأحمر — معطّل (نفس الشكل خافتاً) ما دام فيه عناصر
            DSButton(L10n.t("حذف التصنيف نهائياً", "Delete category permanently"), icon: "trash",
                     role: .destructive) {
                confirmDelete = true
            }
            .disabled(count > 0)
            if count > 0 {
                Text(L10n.t("فيه \(count) عنصر — ما ينحذف إلا وهو فاضي. تقدر تخفيه بدل الحذف.",
                            "It has \(count) items — only empty categories can be deleted. You can hide it instead."))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .dsAlert(L10n.t("حذف التصنيف", "Delete Category"), isPresented: $confirmDelete) {
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                Task {
                    if await store.delete(category) { dismiss() } else { errorText = store.errorMessage }
                }
            }
        } message: {
            Text(L10n.t("«\(category.nameAr)» ينحذف نهائياً من التصنيفات.",
                        "«\(category.nameAr)» will be permanently deleted."))
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        errorText = nil
        let ok: Bool
        if isNew {
            ok = await store.add(section: section, nameAr: nameAr, nameEn: nameEn,
                                 iconKey: iconKey, colorKey: colorKey)
        } else if var updated = category {
            updated.nameAr = nameAr
            updated.nameEn = nameEn.isEmpty ? nameAr : nameEn
            updated.iconKey = iconKey
            updated.colorKey = colorKey
            updated.isActive = isActive
            ok = await store.save(updated)
        } else {
            ok = false
        }
        if ok { dismiss() } else { errorText = store.errorMessage }
    }
}

// MARK: - أسماء الأيقونات والألوان للقارئ الصوتي (خاصة بهذا الملف)

/// أزرار الأيقونة واللون في مربّع التصنيف بلا نص — هذه أسماؤها لـ VoiceOver (توصية أبل)
private enum CategoryEditA11yNames {
    static func icon(_ key: String) -> String {
        switch key {
        case "newspaper.fill":     return L10n.t("جريدة", "Newspaper")
        case "megaphone.fill":     return L10n.t("مكبّر صوت", "Megaphone")
        case "heart.fill":         return L10n.t("قلب", "Heart")
        case "figure.child":       return L10n.t("طفل", "Child")
        case "heart.slash.fill":   return L10n.t("قبر", "Grave")
        case "hands.clap.fill":    return L10n.t("تصفيق", "Clapping hands")
        case "envelope.open.fill": return L10n.t("ظرف مفتوح", "Open envelope")
        case "bell.badge.fill":    return L10n.t("جرس", "Bell")
        case "chart.bar.fill":     return L10n.t("رسم بياني", "Bar chart")
        case "star.fill":          return L10n.t("نجمة", "Star")
        case "calendar":           return L10n.t("تقويم", "Calendar")
        case "gift.fill":          return L10n.t("هدية", "Gift")
        case "graduationcap.fill": return L10n.t("قبعة تخرّج", "Graduation cap")
        case "house.fill":         return L10n.t("منزل", "House")
        case "trophy.fill":        return L10n.t("كأس", "Trophy")
        case "doc.text.fill":      return L10n.t("مستند", "Document")
        case "book.closed.fill":   return L10n.t("كتاب", "Book")
        case "photo.stack.fill":   return L10n.t("صور", "Photos")
        case "folder.fill":        return L10n.t("مجلد", "Folder")
        case "sparkles":           return L10n.t("نجوم لامعة", "Sparkles")
        default:                   return L10n.t("أيقونة", "Icon")
        }
    }

    static func color(_ key: String) -> String {
        switch key {
        case "navy":         return L10n.t("كحلي", "Navy")
        case "green":        return L10n.t("أخضر غامق", "Dark green")
        case "gold":         return L10n.t("ذهبي", "Gold")
        case "wedding":      return L10n.t("وردي", "Pink")
        case "birth":        return L10n.t("أخضر", "Green")
        case "death":        return L10n.t("رمادي غامق", "Dark gray")
        case "vote":         return L10n.t("بنفسجي", "Purple")
        case "announcement": return L10n.t("برتقالي", "Orange")
        case "congrats":     return L10n.t("أصفر", "Yellow")
        case "reminder":     return L10n.t("أحمر", "Red")
        case "invitation":   return L10n.t("فيروزي", "Teal")
        case "info":         return L10n.t("أزرق", "Blue")
        case "rose":         return L10n.t("عنّابي", "Burgundy")
        case "gray":         return L10n.t("رمادي", "Gray")
        default:             return L10n.t("لون", "Colour")
        }
    }
}
