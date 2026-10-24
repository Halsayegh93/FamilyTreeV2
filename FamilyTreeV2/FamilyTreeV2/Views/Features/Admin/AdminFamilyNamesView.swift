import SwiftUI

/// «أسماء العوائل والفروع» — صفحة واحدة في «التطبيق ← القوائم» (الدفعة ج، ٢٠٢٦-١٠-٢٠؛ كانتا صفحتين):
/// أسماء العوائل (الإدارة تضع القائمة، والأعضاء يختارون منها عند التسجيل أو تعديل الملف) وأسماء الفروع (تظهر في قائمة
/// اختيار الفرع فقط). بشكل «اليوم» (`AdminPageKit`): رأس كحلي بالأرقام ← «إضافة عائلة» (لمن يدير) تصعد فوقه ←
/// «أسماء الفروع» (صفّ يفتح شجرة الفروع بوضع التسمية) ← «العوائل» صفوفاً بقائمة خيارات لكل صف. بلا تبويبات.
/// العوائل: المالك والمدير يضيفان ويعدّلان · الفروع: المالك يسمّي والمدير يقرأ (كما كانتا).
struct AdminFamilyNamesView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @StateObject private var vm = FamilyNamesViewModel()
    /// مربّع «أسماء الفروع» (شجرة الفروع بوضع التسمية)
    @State private var branchNamesOpen = false

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
        AdminPage(header: header,
                  lead: AnyView(canManage ? AnyView(addSection) : AnyView(branchesSection)),
                  content: AnyView(VStack(spacing: DS.Hub.stackSpacing) {
                      if canManage { AnyView(branchesSection) }
                      AnyView(listSection)
                  }))
        .task { await vm.fetch(force: true) }
        .task { await appSettingsVM.fetchSettings() }
        // أسماء الفروع — شجرة الفروع نفسها بوضع التسمية (كما كانت في «إعدادات التطبيق»)
        .dsTallBox(isPresented: $branchNamesOpen) {
            BranchPickerSheet(
                allMembers: memberVM.allMembers,
                renamesBranches: true,
                canRename: authVM.canManageSettings,
                onRename: { id, name in
                    Task { await appSettingsVM.updateBranchName(name, for: id, updatedBy: authVM.currentUser?.id) }
                }
            )
            .environmentObject(appSettingsVM)
        }
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

    // MARK: - الرأس الكحلي بالأرقام

    private var header: AdminPageHeader {
        let ready = !isFirstLoad
        return AdminPageHeader(
            title: L10n.t("أسماء العوائل والفروع", "Family and branch names"),
            subtitle: L10n.t("يختار العضو عائلته منها، وأسماء الفروع تظهر في قائمة اختيار الفرع.",
                             "Members pick their family from this list; branch names show in the branch picker."),
            glyph: "person.2.crop.square.stack.fill",
            kpis: [
                AdminPageKPI(AdminPageKPI.count(vm.options.count, ready: ready), L10n.t("عائلة", "Families"),
                             icon: "list.bullet"),
                AdminPageKPI(AdminPageKPI.count(activeCount, ready: ready), L10n.t("متاحة للاختيار", "Selectable"),
                             icon: "checkmark.circle", tint: DS.Hub.kpiMine),
                AdminPageKPI("\(customBranchNamesCount)", L10n.t("فروع بأسماء", "Named branches"),
                             icon: "arrow.triangle.branch")
            ])
    }

    // MARK: - أسماء الفروع (طلب المالك ٢٠٢٦-١٠-٠٩)

    /// عدد الفروع التي لها اسم مخصّص
    private var customBranchNamesCount: Int {
        (appSettingsVM.settings.branchNames ?? [:]).values
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var branchesSection: some View {
        AdminSectionCard(title: L10n.t("أسماء الفروع", "Branch names"),
                         tag: customBranchNamesCount > 0
                            ? L10n.t("\(customBranchNamesCount) اسم مخصّص", "\(customBranchNamesCount) custom") : nil) {
            AdminTapRow(icon: "arrow.triangle.branch", tint: DS.Color.palm,
                        title: L10n.t("تسمية الفروع", "Name the branches"),
                        subtitle: authVM.canManageSettings
                            ? L10n.t("اسم يظهر في قائمة اختيار الفرع فقط", "A name shown in the branch picker list only")
                            : AdminPageHeader.readOnlyText,
                        tap: .action { branchNamesOpen = true })
        }
    }

    // MARK: - إضافة عائلة

    private var canSubmit: Bool {
        !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var addSection: some View {
        AdminSectionCard(title: L10n.t("إضافة عائلة", "Add a family")) {
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
            AdminPageStateCard(.loading(L10n.t("جارٍ تحميل العوائل…", "Loading families…")))
        } else if vm.options.isEmpty, let error = vm.errorMessage {
            // الجدول قد لا يكون مُهاجَراً بعد — السبب ظاهر بدل قائمة فارغة صامتة
            AdminPageStateCard(.error(L10n.t("تعذّر تحميل العوائل", "Couldn't load families"),
                                      message: error,
                                      retry: { Task { await vm.fetch(force: true) } }))
        } else if vm.options.isEmpty {
            AdminPageStateCard(.empty(L10n.t("لا توجد عوائل بعد — أضف أول اسم.",
                                             "No families yet — add the first one.")))
        } else {
            AdminSectionCard(title: L10n.t("العوائل", "Families"),
                             tag: vm.isLoading ? L10n.t("تحديث…", "Updating…") : "\(vm.options.count)") {
                if let error = vm.errorMessage {
                    errorRow(error)
                }
                AdminRowsCardBody {
                    ForEach(vm.options) { option in
                        row(option)
                    }
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
        HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: option.isActive ? "checkmark.circle.fill" : "circle.slash",
                            tint: option.isActive ? DS.Color.success : DS.Color.textTertiary)

            Text(option.name)
                .dsFont(.hubRow)
                .foregroundColor(option.isActive ? DS.Color.textPrimary : DS.Color.textTertiary)
                .lineLimit(2)

            if !option.isActive {
                DSStatusChip(text: L10n.t("مخفية من الاختيار", "Hidden from the picker"), tint: DS.Color.textTertiary)
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
                        Label(option.isActive ? L10n.t("إخفاء من الاختيار", "Hide from the picker")
                                              : L10n.t("إظهار في الاختيار", "Show in the picker"),
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
        .padding(.vertical, DS.Spacing.sm)
        .frame(minHeight: DSBox.fieldMinHeight)
        .accessibilityElement(children: .contain)
    }

    private func submitAdd() {
        let name = newName
        newName = ""
        // لوحة المفاتيح تُغلق بعد الإضافة كما كانت (ضاع `addFocused = false` في التوحيد — ن-١١ فحص ٢٠٢٦-١٠-٠٧)
        KeyboardDismisser.endEditing()
        Task { await vm.add(name) }
    }
}
