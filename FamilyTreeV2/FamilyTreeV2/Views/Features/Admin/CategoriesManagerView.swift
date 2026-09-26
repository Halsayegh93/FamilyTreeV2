import SwiftUI

// MARK: - إدارة التصنيفات — في «إعدادات التطبيق» (طلب المالك)
//
// لكل قسم فيه تصنيفات (الأخبار، مكتبة العائلة): تعديل الاسم والأيقونة واللون،
// إخفاء/إظهار (بدون حذف — المحتوى القديم يبقى بتصنيفه)، ترتيب، وإضافة للأخبار.

struct CategoriesManagerView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var store = CategoryStore.shared
    @State private var section: CategorySection = .news
    @State private var editing: ContentCategory?
    @State private var showAdd = false
    /// التصنيف المطلوب حذفه من القائمة — ينتظر التأكيد
    @State private var pendingDelete: ContentCategory?
    @State private var deleteError: String?

    private var canEdit: Bool { authVM.canManageSettings }

    var body: some View {
        List {
            pickerSection
            categoriesSection
            addSection
        }
        .environment(\.editMode, editModeBinding)
        .scrollContentBackground(.hidden)
        .background(DS.Color.background.ignoresSafeArea())
        .navigationTitle(L10n.t("التصنيفات", "Categories"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.fetch(); await store.fetchCounts() }
        .refreshable { await store.fetch(); await store.fetchCounts() }
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

    private var editModeBinding: Binding<EditMode> {
        Binding.constant(canEdit ? EditMode.active : EditMode.inactive)
    }

    private var pickerSection: some View {
        Section {
            Picker("", selection: $section) {
                ForEach(CategorySection.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } footer: {
            Text(footerText)
                .font(DS.Font.plex(11, weight: .medium))
                .foregroundColor(DS.Color.textSecondary)
        }
    }

    private var categoriesSection: some View {
        Section {
            ForEach(store.list(section, activeOnly: false)) { category in
                Button {
                    if canEdit { editing = category }
                } label: {
                    row(category)
                }
                .buttonStyle(.plain)
                .moveDisabled(!canEdit)
            }
            .onMove { source, destination in
                if canEdit { move(from: source, to: destination) }
            }
        } header: {
            Text(L10n.t("اسحب لإعادة الترتيب", "Drag to reorder"))
                .font(DS.Font.plex(11, weight: .medium))
                .textCase(nil)
        }
    }

    @ViewBuilder
    private var addSection: some View {
        if canEdit && section.allowsAdding {
            Section {
                Button { showAdd = true } label: {
                    Label(L10n.t("إضافة تصنيف", "Add category"), systemImage: "plus.circle.fill")
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                }
            }
        }
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

    private func row(_ category: ContentCategory) -> some View {
        let count = store.itemCount(category)
        return HStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle().fill(category.color.opacity(category.isActive ? 0.18 : 0.08))
                    .frame(width: 34, height: 34)
                Image(systemName: category.iconKey)
                    .font(DS.Font.scaled(14, weight: .bold))
                    .foregroundColor(category.isActive ? category.color : DS.Color.textTertiary)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(category.nameAr)
                        .font(DS.Font.plex(14, weight: .bold))
                        .foregroundColor(category.isActive ? DS.Color.textPrimary : DS.Color.textTertiary)
                    // عدد العناصر — رقم فقط جنب الاسم (طلب المالك)
                    Text("\(count)")
                        .font(DS.Font.plex(11, weight: .bold))
                        .foregroundColor(count > 0 ? category.color : DS.Color.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill((count > 0 ? category.color : DS.Color.textTertiary).opacity(0.12)))
                }
                Text(category.nameEn)
                    .font(DS.Font.plex(11, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
            }
            Spacer(minLength: 0)
            if !category.isActive {
                Text(L10n.t("مخفي", "Hidden"))
                    .font(DS.Font.plex(10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(DS.Color.textTertiary))
            }
            // حذف من برّا — للتصنيف الفارغ غير الأساسي فقط
            if canEdit && count == 0 && !store.isProtected(category) {
                Button {
                    pendingDelete = category
                } label: {
                    Image(systemName: "trash")
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(DS.Color.error)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(DS.Color.error.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("حذف التصنيف", "Delete category"))
            }
        }
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
                Text(errorText)
                    .font(DS.Font.plex(12, weight: .semibold))
                    .foregroundColor(DS.Color.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: الأقسام

    /// معاينة شارة التصنيف كما ستظهر
    private var preview: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: iconKey).font(DS.Font.scaled(12, weight: .bold))
                .accessibilityHidden(true)
            Text(nameAr.isEmpty ? L10n.t("اسم التصنيف", "Category name") : nameAr)
                .font(DS.Font.plex(13, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, DS.Spacing.md)
        .frame(height: 32)
        .background(Capsule().fill(accent))
        .opacity(isActive ? 1 : 0.45)
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xs)
    }

    private var namesSection: some View {
        DSComposerSection(title: L10n.t("الاسم", "Name"), icon: "tag.fill",
                          tint: DS.Color.primary, index: 1) {
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
            gridRows(CategoryPalette.icons, columns: 5, spacing: 6) { icon in
                Button { iconKey = icon } label: {
                    Image(systemName: icon)
                        .font(DS.Font.scaled(16, weight: .bold))
                        .foregroundColor(iconKey == icon ? .white : accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(iconKey == icon ? accent : accent.opacity(0.10)))
                        // مساحة ضغط ٤٤ (توصية أبل) — الزر الظاهر ٤٢ كما هو
                        .frame(height: 44)
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
                        .frame(width: 32, height: 32)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: colorKey == key ? 3 : 0))
                        .overlay(Circle().strokeBorder(CategoryPalette.color(key), lineWidth: colorKey == key ? 1.5 : 0).padding(-3))
                        // مساحة ضغط ٤٤ (توصية أبل)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // زر لون بلا نص — اسم اللون للقارئ الصوتي، والمختار «محدّد»
                .accessibilityLabel(CategoryEditA11yNames.color(key))
                .accessibilityAddTraits(colorKey == key ? .isSelected : [])
            }
            .padding(.vertical, -6)
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("ظاهر للأعضاء", "Visible to members"))
                            .font(DS.Font.plex(13.5, weight: .bold))
                            .foregroundColor(DS.Color.fieldLabel)
                        Text(L10n.t("الإخفاء يشيله من الاختيارات، والمحتوى القديم يبقى بتصنيفه",
                                    "Hiding removes it from choices; existing content keeps it"))
                            .font(DS.Font.plex(11))
                            .foregroundColor(DS.Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(DS.Color.primary)
            }
            .dsRowBox()
        }
    }

    /// شبكة غير كسولة: صفوف من `columns` عناصر، والصف الناقص يُكمَّل بفراغ
    /// (`hSpacing` المسافة بين الخانات — ٠ للألوان حتى تأخذ كل خانة أوسع مساحة ضغط)
    private func gridRows<Item: Hashable, Cell: View>(_ items: [Item], columns: Int, spacing: CGFloat,
                                                      hSpacing: CGFloat = 8,
                                                      @ViewBuilder cell: @escaping (Item) -> Cell) -> some View {
        VStack(spacing: spacing) {
            ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { start in
                let end = min(start + columns, items.count)
                HStack(spacing: hSpacing) {
                    ForEach(items[start..<end], id: \.self) { item in
                        cell(item).frame(maxWidth: .infinity)
                    }
                    ForEach(0..<(columns - (end - start)), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
    }

    /// حذف نهائي — متاح فقط إذا كان التصنيف فارغاً؛ غير ذلك يُقترح الإخفاء
    private func deleteCard(_ category: ContentCategory) -> some View {
        let count = store.itemCount(category)
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Button {
                confirmDelete = true
            } label: {
                Label(L10n.t("حذف التصنيف نهائياً", "Delete category permanently"), systemImage: "trash")
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(count == 0 ? DS.Color.error : DS.Color.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill((count == 0 ? DS.Color.error : DS.Color.textTertiary).opacity(0.10)))
            }
            .buttonStyle(DSScaleButtonStyle())
            .disabled(count > 0)
            if count > 0 {
                Text(L10n.t("فيه \(count) عنصر — ما ينحذف إلا وهو فاضي. تقدر تخفيه بدل الحذف.",
                            "It has \(count) items — only empty categories can be deleted. You can hide it instead."))
                    .font(DS.Font.plex(11, weight: .medium))
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
        case "heart.slash.fill":   return L10n.t("قلب مشطوب", "Crossed-out heart")
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
