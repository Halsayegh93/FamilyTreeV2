import SwiftUI

/// إدارة أسماء العوائل — الإدارة تضع القائمة، والأعضاء يختارون منها
/// عند التسجيل أو من تعديل الملف الشخصي.
/// تصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧، «أسلوب واحد» ٢٠٢٦-١٠-٠٧): صفّ أرقام حيّة ←
/// «إضافة عائلة» (لمن يدير) ← «العوائل» صفوفاً `.dsRowBox()` وقائمة خيارات لكل صف.
struct AdminFamilyNamesView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var vm = FamilyNamesViewModel()

    @State private var newName = ""
    @State private var renaming: FamilyNameOption?
    @State private var renameText = ""
    @State private var deleting: FamilyNameOption?

    private var canManage: Bool { authVM.canManageSettings || authVM.isAdmin }

    /// لون مجال «الشجرة والأعضاء»
    private let tint = DS.Color.composerProject

    private var activeCount: Int { vm.options.filter(\.isActive).count }
    /// أول تحميل لم يصل بعد
    private var isFirstLoad: Bool { vm.isLoading && vm.options.isEmpty }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    hero
                    if canManage { addSection }
                    listSection
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.xxxl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await vm.fetch(force: true) }
        .refreshable { await vm.fetch(force: true) }
        .dsAlert(L10n.t("تعديل الاسم", "Rename"), isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField(L10n.t("اسم العائلة", "Family name"), text: $renameText)
                .dsAlertField()
            Button(L10n.t("حفظ", "Save")) {
                if let r = renaming { Task { await vm.rename(id: r.id, to: renameText) } }
                renaming = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { renaming = nil }
        }
        .dsAlert(L10n.t("حذف العائلة", "Delete Family"), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        )) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                if let d = deleting { Task { await vm.delete(id: d.id) } }
                deleting = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { deleting = nil }
        } message: {
            Text(L10n.t("الأعضاء الذين اختاروها يحتفظون باسمهم — تختفي من قائمة الاختيار فقط.",
                        "Members who picked it keep their name — it only leaves the picker."))
        }
    }

    // MARK: - الأرقام السريعة (العنوان والوصف في رأس «إدارة الأعضاء» الملوّن)

    private var hero: some View {
        DSStatsRow([
            DSHeroStat(value: isFirstLoad ? "—" : "\(vm.options.count)",
                       label: L10n.t("عائلة", "Families"), icon: "list.bullet"),
            DSHeroStat(value: isFirstLoad ? "—" : "\(activeCount)",
                       label: L10n.t("متاحة للاختيار", "Selectable"), icon: "checkmark.circle.fill"),
            DSHeroStat(value: isFirstLoad ? "—" : "\(vm.options.count - activeCount)",
                       label: L10n.t("معطّلة", "Disabled"), icon: "eye.slash.fill")
        ], tint: tint)
    }

    // MARK: - إضافة عائلة

    private var canSubmit: Bool {
        !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var addSection: some View {
        DSComposerSection(title: L10n.t("إضافة عائلة", "Add a family"),
                          icon: "plus.circle.fill",
                          tint: tint,
                          index: 1) {
            // الحقل الموحّد (`DSComposerField`) + شريحة «إضافة» ممتلئة بلون القسم
            HStack(spacing: DS.Spacing.sm) {
                DSComposerField(icon: "person.2.fill",
                                label: L10n.t("اسم العائلة", "Family name"),
                                placeholder: L10n.t("أضف اسم عائلة", "Add a family name"),
                                text: $newName,
                                tint: tint)
                    .submitLabel(.done)
                    .onSubmit { submitAdd() }

                if canSubmit {
                    DSChipButton(L10n.t("إضافة", "Add"), icon: "plus", isSelected: true) { submitAdd() }
                }
            }
        }
    }

    // MARK: - العوائل

    @ViewBuilder
    private var listSection: some View {
        if isFirstLoad {
            DSPageLoader(L10n.t("جارٍ تحميل العوائل…", "Loading families…"), fillsSpace: false)
        } else if vm.options.isEmpty, let error = vm.errorMessage {
            // الجدول قد لا يكون مُهاجَراً بعد — السبب ظاهر بدل قائمة فارغة صامتة
            DSStateCard(icon: "exclamationmark.triangle.fill",
                         title: L10n.t("تعذّر تحميل العوائل", "Couldn't load families"),
                         hint: error,
                         tint: DS.Color.error,
                         actionTitle: L10n.t("إعادة المحاولة", "Retry")) {
                Task { await vm.fetch(force: true) }
            }
        } else if vm.options.isEmpty {
            DSEmptyView(L10n.t("لا توجد عوائل بعد — أضف أول اسم.",
                               "No families yet — add the first one."),
                        style: .compact)
        } else {
            DSComposerSection(title: L10n.t("العوائل", "Families"),
                              icon: "list.bullet",
                              tint: tint,
                              trailing: vm.isLoading ? L10n.t("تحديث…", "Updating…") : "\(vm.options.count)",
                              index: 2) {
                if let error = vm.errorMessage {
                    errorRow(error)
                }
                ForEach(vm.options) { option in
                    row(option)
                }
            }
        }
    }

    /// سبب آخر فشل (إضافة مكرّرة، تعديل…) — الملاحظة الموحّدة بالأحمر، وتُغلق بـ ×
    private func errorRow(_ message: String) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            DSNoteCard(message, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            Button { vm.errorMessage = nil } label: {
                Image(systemName: "xmark")
                    .dsGlyph(DS.Glyph.smCompact)
                    .foregroundColor(DS.Color.textSecondary)
                    .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("إغلاق", "Close"))
        }
    }

    private func row(_ option: FamilyNameOption) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: option.isActive ? "checkmark.circle.fill" : "circle.slash",
                        tint: option.isActive ? DS.Color.success : DS.Color.textTertiary)
                .accessibilityHidden(true)

            Text(option.name)
                .dsFieldFont(.rowTitle)
                .foregroundColor(option.isActive ? DS.Color.fieldLabel : DS.Color.textTertiary)
                .lineLimit(2)

            if !option.isActive {
                DSStatusChip(text: L10n.t("معطّلة", "Disabled"), tint: DS.Color.textTertiary)
            }

            Spacer(minLength: 0)

            if canManage {
                Menu {
                    Button {
                        renameText = option.name
                        renaming = option
                    } label: { Label(L10n.t("تعديل الاسم", "Rename"), systemImage: "pencil") }

                    Button {
                        Task { await vm.setActive(id: option.id, !option.isActive) }
                    } label: {
                        Label(option.isActive ? L10n.t("تعطيل", "Disable")
                                              : L10n.t("تفعيل", "Enable"),
                              systemImage: option.isActive ? "eye.slash" : "eye")
                    }

                    Button(role: .destructive) { deleting = option } label: {
                        Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .dsGlyph(DS.Glyph.md)
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .padding(.vertical, -DS.Spacing.xsm)
                .accessibilityLabel(L10n.t("خيارات \(option.name)", "Options for \(option.name)"))
            }
        }
        .frame(minHeight: DSBox.fieldMinHeight)
        .dsRowBox()
        .accessibilityElement(children: .contain)
    }

    private func submitAdd() {
        let name = newName
        newName = ""
        Task { await vm.add(name) }
    }
}
