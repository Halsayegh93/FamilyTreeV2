import SwiftUI

/// إدارة أسماء العوائل — الإدارة تضع القائمة، والأعضاء يختارون منها
/// عند التسجيل أو من تعديل الملف الشخصي.
struct AdminFamilyNamesView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var vm = FamilyNamesViewModel()

    @State private var newName = ""
    @State private var renaming: FamilyNameOption?
    @State private var renameText = ""
    @State private var deleting: FamilyNameOption?
    @FocusState private var addFocused: Bool

    private var canManage: Bool { authVM.canManageSettings || authVM.isAdmin }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    introCard
                    if canManage { addRow }
                    listCard
                }
                .padding(DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxxl)
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await vm.fetch(force: true) }
        .refreshable { await vm.fetch(force: true) }
        .alert(L10n.t("تعديل الاسم", "Rename"), isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField(L10n.t("اسم العائلة", "Family name"), text: $renameText)
            Button(L10n.t("حفظ", "Save")) {
                if let r = renaming { Task { await vm.rename(id: r.id, to: renameText) } }
                renaming = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { renaming = nil }
        }
        .alert(L10n.t("حذف العائلة", "Delete Family"), isPresented: Binding(
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

    // MARK: - الأقسام

    private var introCard: some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            Image(systemName: "person.2.crop.square.stack.fill")
                .font(DS.Font.scaled(15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(SwiftUI.Color.white.opacity(0.20))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("قائمة عوائل العضوية", "Membership families"))
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(.white)
                Text(L10n.t("يختار العضو عائلته منها، وتظهر بآخر اسمه في التطبيق.",
                            "Members pick from this list; it appears at the end of their name."))
                    .font(DS.Font.scaled(11))
                    .foregroundColor(SwiftUI.Color.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.md - 2)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(DS.Color.gradientPrimary)
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(DS.Color.headerVeil)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(DS.Color.headerBorder, lineWidth: 1)
        )
    }

    private var addRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "plus.circle.fill")
                .font(DS.Font.scaled(14, weight: .bold))
                .foregroundColor(DS.Color.primary)
            TextField(L10n.t("أضف اسم عائلة", "Add a family name"), text: $newName)
                .font(DS.Font.scaled(13))
                .focused($addFocused)
                .submitLabel(.done)
                .onSubmit { submitAdd() }
            if !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(L10n.t("إضافة", "Add")) { submitAdd() }
                    .font(DS.Font.scaled(12, weight: .bold))
                    .foregroundColor(DS.Color.primary)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm + 2)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.primary.opacity(0.20), lineWidth: 1)
        )
    }

    private var listCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: 5) {
                Image(systemName: "list.bullet")
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(DS.Color.primary.opacity(0.75))
                Text(L10n.t("العوائل (\(vm.options.count))", "Families (\(vm.options.count))"))
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textSecondary)
                Spacer(minLength: 0)
                if vm.isLoading { ProgressView().scaleEffect(0.7) }
            }

            VStack(spacing: 0) {
                if vm.options.isEmpty && !vm.isLoading {
                    Text(L10n.t("لا توجد عوائل بعد — أضف أول اسم.",
                                "No families yet — add the first one."))
                        .font(DS.Font.scaled(11))
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, DS.Spacing.xl)
                } else {
                    ForEach(Array(vm.options.enumerated()), id: \.element.id) { index, option in
                        row(option)
                        if index < vm.options.count - 1 { DSDivider() }
                    }
                }
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
            )
        }
    }

    private func row(_ option: FamilyNameOption) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: option.isActive ? "checkmark.circle.fill" : "circle.slash")
                .font(DS.Font.scaled(12, weight: .bold))
                .foregroundColor(option.isActive ? DS.Color.success : DS.Color.textTertiary)

            Text(option.name)
                .font(DS.Font.scaled(13, weight: .semibold))
                .foregroundColor(option.isActive ? DS.Color.textPrimary : DS.Color.textTertiary)

            if !option.isActive {
                Text(L10n.t("معطّلة", "Disabled"))
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(DS.Color.textTertiary.opacity(0.12)))
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
                        .font(DS.Font.scaled(13, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(width: 40, height: 32)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.vertical, 7)
    }

    private func submitAdd() {
        let name = newName
        newName = ""
        addFocused = false
        Task { await vm.add(name) }
    }
}
