import SwiftUI

/// إدارة أسماء العوائل — الإدارة تضع القائمة، والأعضاء يختارون منها
/// عند التسجيل أو من تعديل الملف الشخصي.
/// بشكل «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠، `AdminPageKit`): رأس كحلي بالأرقام ← «إضافة عائلة» (لمن يدير) تصعد
/// فوقه ← «العوائل» صفوفاً في بطاقة بيضاء وقائمة خيارات لكل صف.
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
        AdminPage(header: header,
                  lead: AnyView(canManage ? AnyView(addSection) : AnyView(listSection)),
                  content: AnyView(canManage ? AnyView(listSection) : AnyView(EmptyView())))
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

    // MARK: - الرأس الكحلي بالأرقام

    private var header: AdminPageHeader {
        let ready = !isFirstLoad
        return AdminPageHeader(
            title: AdminMembersManagementView.Tab.families.title,
            subtitle: AdminMembersManagementView.Tab.families.subtitle,
            glyph: AdminMembersManagementView.Tab.families.icon,
            kpis: [
                AdminPageKPI(AdminPageKPI.count(vm.options.count, ready: ready), L10n.t("عائلة", "Families"),
                             icon: "list.bullet"),
                AdminPageKPI(AdminPageKPI.count(activeCount, ready: ready), L10n.t("متاحة للاختيار", "Selectable"),
                             icon: "checkmark.circle", tint: DS.Hub.kpiMine),
                AdminPageKPI(AdminPageKPI.count(vm.options.count - activeCount, ready: ready),
                             L10n.t("معطّلة", "Disabled"), icon: "eye.slash", tint: DS.Hub.kpiLate)
            ])
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
