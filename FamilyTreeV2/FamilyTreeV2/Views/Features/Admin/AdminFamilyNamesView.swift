import SwiftUI

/// إدارة أسماء العوائل — الإدارة تضع القائمة، والأعضاء يختارون منها
/// عند التسجيل أو من تعديل الملف الشخصي.
/// تصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧): بطاقة رأس بأرقام حيّة ←
/// «إضافة عائلة» (لمن يدير) ← «العوائل» صفوفاً `.dsRowBox()` وقائمة خيارات لكل صف.
struct AdminFamilyNamesView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var vm = FamilyNamesViewModel()

    @State private var newName = ""
    @State private var renaming: FamilyNameOption?
    @State private var renameText = ""
    @State private var deleting: FamilyNameOption?
    @FocusState private var addFocused: Bool

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

    // MARK: - بطاقة الرأس

    private var hero: some View {
        DSPageHero(
            title: L10n.t("قائمة عوائل العضوية", "Membership families"),
            subtitle: L10n.t("يختار العضو عائلته منها، وتظهر بآخر اسمه في التطبيق.",
                             "Members pick from this list; it appears at the end of their name."),
            icon: "person.2.crop.square.stack.fill",
            tint: tint,
            stats: [
                DSHeroStat(value: isFirstLoad ? "—" : "\(vm.options.count)",
                           label: L10n.t("عائلة", "Families"), icon: "list.bullet"),
                DSHeroStat(value: isFirstLoad ? "—" : "\(activeCount)",
                           label: L10n.t("متاحة للاختيار", "Selectable"), icon: "checkmark.circle.fill"),
                DSHeroStat(value: isFirstLoad ? "—" : "\(vm.options.count - activeCount)",
                           label: L10n.t("معطّلة", "Disabled"), icon: "eye.slash.fill")
            ]
        )
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
            // حقل بنفس إطار حقول المربّعات (يتلوّن عند الكتابة) + زر «إضافة» كحلي
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(addFocused ? .white : tint)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(addFocused ? tint : tint.opacity(0.12)))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("اسم العائلة", "Family name"))
                        .dsFieldFont(12, weight: .heavy)
                        .foregroundColor(addFocused ? tint : DS.Color.fieldLabel)
                    TextField(L10n.t("أضف اسم عائلة", "Add a family name"), text: $newName)
                        .dsFieldFont(14.5)
                        .foregroundColor(DS.Color.textPrimary)
                        .focused($addFocused)
                        .submitLabel(.done)
                        .onSubmit { submitAdd() }
                }

                if canSubmit {
                    Button { submitAdd() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11.5, weight: .bold))
                            Text(L10n.t("إضافة", "Add"))
                                .font(DS.Font.plex(13, weight: .bold))
                        }
                        .foregroundColor(DSActionFill.label())
                        .padding(.horizontal, DS.Spacing.md)
                        .frame(height: 34)
                        .background(DSActionFill.style(), in: Capsule())
                        // مساحة ضغط ٤٤ نقطة والشكل كما هو
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DSScaleButtonStyle())
                    .padding(.vertical, -5)
                }
            }
            .padding(.horizontal, DS.Spacing.sm + 2)
            .padding(.vertical, DS.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(addFocused ? tint.opacity(0.65) : DS.Color.textTertiary.opacity(0.15),
                                  lineWidth: addFocused ? 1.5 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { addFocused = true }
            .animation(.easeInOut(duration: 0.2), value: addFocused)
        }
    }

    // MARK: - العوائل

    @ViewBuilder
    private var listSection: some View {
        if isFirstLoad {
            SysStateCard(icon: "person.2.crop.square.stack.fill",
                         title: L10n.t("جارٍ تحميل العوائل…", "Loading families…"),
                         tint: tint,
                         isLoading: true)
        } else if vm.options.isEmpty, let error = vm.errorMessage {
            // الجدول قد لا يكون مُهاجَراً بعد — السبب ظاهر بدل قائمة فارغة صامتة
            SysStateCard(icon: "exclamationmark.triangle.fill",
                         title: L10n.t("تعذّر تحميل العوائل", "Couldn't load families"),
                         hint: error,
                         tint: DS.Color.error,
                         actionTitle: L10n.t("إعادة المحاولة", "Retry")) {
                Task { await vm.fetch(force: true) }
            }
        } else if vm.options.isEmpty {
            SysStateCard(icon: "person.2.crop.square.stack",
                         title: L10n.t("لا توجد عوائل بعد — أضف أول اسم.",
                                       "No families yet — add the first one."),
                         tint: tint)
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

    /// سبب آخر فشل (إضافة مكرّرة، تعديل…) — يُغلق بـ ×
    private func errorRow(_ message: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "exclamationmark.triangle.fill", tint: DS.Color.error)
                .accessibilityHidden(true)
            Text(message)
                .font(DS.Font.plex(12.5, weight: .semibold))
                .foregroundColor(DS.Color.error)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { vm.errorMessage = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(DS.Color.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -6)
            .accessibilityLabel(L10n.t("إغلاق", "Close"))
        }
        .padding(.horizontal, DS.Spacing.sm + 2)
        .padding(.vertical, DS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .fill(DS.Color.error.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(DS.Color.error.opacity(0.22), lineWidth: 1))
    }

    private func row(_ option: FamilyNameOption) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: option.isActive ? "checkmark.circle.fill" : "circle.slash",
                        tint: option.isActive ? DS.Color.success : DS.Color.textTertiary)
                .accessibilityHidden(true)

            Text(option.name)
                .dsFieldFont(13.5, weight: .bold)
                .foregroundColor(option.isActive ? DS.Color.fieldLabel : DS.Color.textTertiary)
                .lineLimit(2)

            if !option.isActive {
                SysStatusChip(text: L10n.t("معطّلة", "Disabled"), tint: DS.Color.textTertiary)
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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .padding(.vertical, -6)
                .accessibilityLabel(L10n.t("خيارات \(option.name)", "Options for \(option.name)"))
            }
        }
        .frame(minHeight: 36)
        .dsRowBox()
        .accessibilityElement(children: .contain)
    }

    private func submitAdd() {
        let name = newName
        newName = ""
        addFocused = false
        Task { await vm.add(name) }
    }
}
