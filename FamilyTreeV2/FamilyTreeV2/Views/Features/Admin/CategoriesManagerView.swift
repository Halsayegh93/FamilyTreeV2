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
        .sheet(item: $editing) { category in
            CategoryEditSheet(category: category, isNew: false, section: section)
        }
        .sheet(isPresented: $showAdd) {
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

/// ورقة تعديل/إضافة تصنيف — الاسم بالعربي والإنجليزي، الأيقونة، اللون، الظهور
struct CategoryEditSheet: View {
    let category: ContentCategory?
    let isNew: Bool
    let section: CategorySection

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = CategoryStore.shared
    @State private var nameAr = ""
    @State private var nameEn = ""
    @State private var iconKey = "star.fill"
    @State private var colorKey = "navy"
    @State private var isActive = true
    @State private var saving = false
    @State private var errorText: String?
    @State private var confirmDelete = false

    private var accent: Color { CategoryPalette.color(colorKey) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.lg) {
                    // معاينة
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: iconKey).font(DS.Font.scaled(12, weight: .bold))
                        Text(nameAr.isEmpty ? L10n.t("اسم التصنيف", "Category name") : nameAr)
                            .font(DS.Font.plex(13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, DS.Spacing.md)
                    .frame(height: 32)
                    .background(Capsule().fill(accent))
                    .opacity(isActive ? 1 : 0.45)

                    DSCard(padding: DS.Spacing.md) {
                        VStack(spacing: DS.Spacing.sm) {
                            TextField(L10n.t("الاسم بالعربي", "Arabic name"), text: $nameAr)
                                .font(DS.Font.callout)
                            Divider()
                            TextField(L10n.t("الاسم بالإنجليزي", "English name"), text: $nameEn)
                                .font(DS.Font.callout)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                    }

                    pickerCard(title: L10n.t("الأيقونة", "Icon")) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                            ForEach(CategoryPalette.icons, id: \.self) { icon in
                                Button { iconKey = icon } label: {
                                    Image(systemName: icon)
                                        .font(DS.Font.scaled(16, weight: .bold))
                                        .foregroundColor(iconKey == icon ? .white : accent)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 42)
                                        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                            .fill(iconKey == icon ? accent : accent.opacity(0.10)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    pickerCard(title: L10n.t("اللون", "Colour")) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 10) {
                            ForEach(CategoryPalette.colorKeys, id: \.self) { key in
                                Button { colorKey = key } label: {
                                    Circle()
                                        .fill(CategoryPalette.color(key))
                                        .frame(width: 32, height: 32)
                                        .overlay(Circle().strokeBorder(Color.white, lineWidth: colorKey == key ? 3 : 0))
                                        .overlay(Circle().strokeBorder(CategoryPalette.color(key), lineWidth: colorKey == key ? 1.5 : 0).padding(-3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !isNew {
                        DSCard(padding: DS.Spacing.md) {
                            Toggle(isOn: $isActive) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.t("ظاهر للأعضاء", "Visible to members"))
                                        .font(DS.Font.calloutBold)
                                    Text(L10n.t("الإخفاء يشيله من الاختيارات، والمحتوى القديم يبقى بتصنيفه",
                                                "Hiding removes it from choices; existing content keeps it"))
                                        .font(DS.Font.plex(11, weight: .medium))
                                        .foregroundColor(DS.Color.textSecondary)
                                }
                            }
                            .tint(DS.Color.primary)
                        }
                    }

                    if let category, !isNew, !store.isProtected(category) {
                        deleteCard(category)
                    }

                    if let errorText {
                        Text(errorText)
                            .font(DS.Font.plex(12, weight: .semibold))
                            .foregroundColor(DS.Color.error)
                    }
                }
                .padding(DS.Spacing.lg)
            }
            .background(DS.Color.background.ignoresSafeArea())
            .navigationTitle(isNew ? L10n.t("تصنيف جديد", "New Category") : L10n.t("تعديل التصنيف", "Edit Category"))
            .navigationBarTitleDisplayMode(.inline)
            .dsSheetToolbar(
                confirm: isNew ? L10n.t("إضافة", "Add") : L10n.t("حفظ", "Save"),
                isLoading: saving,
                disabled: nameAr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onConfirm: { Task { await save() } },
                onCancel: { dismiss() }
            )
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear {
            if let category {
                nameAr = category.nameAr
                nameEn = category.nameEn
                iconKey = category.iconKey
                colorKey = category.colorKey
                isActive = category.isActive
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
                    .font(DS.Font.calloutBold)
                    .foregroundColor(count == 0 ? DS.Color.error : DS.Color.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill((count == 0 ? DS.Color.error : DS.Color.textTertiary).opacity(0.10)))
            }
            .buttonStyle(.plain)
            .disabled(count > 0)
            if count > 0 {
                Text(L10n.t("فيه \(count) عنصر — ما ينحذف إلا وهو فاضي. تقدر تخفيه بدل الحذف.",
                            "It has \(count) items — only empty categories can be deleted. You can hide it instead."))
                    .font(DS.Font.plex(11, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
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

    private func pickerCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        DSCard(padding: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text(title)
                    .font(DS.Font.plex(12, weight: .bold))
                    .foregroundColor(DS.Color.textSecondary)
                content()
            }
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
