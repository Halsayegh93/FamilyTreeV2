import SwiftUI
import Supabase
import PostgREST

/// «أسماء عن التطبيق» — صفحة المالك في «التطبيق ← القوائم» (طلب المالك ٢٠٢٦-١١-١٤ «صفحة في الإدارة»):
/// الأسماء التي تظهر في مربّع «عن التطبيق» (النموذج «ج») بالترتيب، الصفة اختيارية فوق الاسم.
/// المصدر `app_config.about_credits` (يقرؤه كل مسجّل عبر `AppConfigValues.aboutCredits`)، والحفظ القائمة كاملة عبر
/// `set_app_config` (المالك وحده؛ السيرفر يفحص الشكل: ١–٢٠ اسماً، الاسم ≤ ٦٠ والصفة ≤ ٤٠). بشكل «أسماء العوائل»:
/// رأس كحلي بالعدد ← «إضافة اسم» ← «الأسماء» صفوفاً بقائمة خيارات (تعديل، أعلى، أسفل، حذف).
struct AdminAboutCreditsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @ObservedObject private var config = AppConfigValues.shared

    /// سطر كما يُحفظ على السيرفر (الإنجليزي اختياري ويبقى كما هو ما لم يتغيّر العربي)
    struct Credit: Codable, Hashable {
        var role: String?
        var name: String
        var role_en: String?
        var name_en: String?
    }

    @State private var credits: [Credit] = []
    @State private var loaded = false
    @State private var saving = false
    @State private var error: String?

    @State private var newRole = ""
    @State private var newName = ""

    @State private var editingIndex: Int?
    @State private var editRole = ""
    @State private var editName = ""
    @State private var deletingIndex: Int?

    /// حدود السيرفر (`private.about_credits_problem`)
    private static let maxCount = 20
    private static let maxName = 60
    private static let maxRole = 40

    private var canEdit: Bool { authVM.canManageSettings }
    private let tint = DS.Color.accent

    var body: some View {
        AdminPage(header: header,
                  lead: AnyView(canEdit ? AnyView(addSection) : AnyView(EmptyView())),
                  content: AnyView(listSection))
        .task { await load(force: true) }
        .refreshable { await load(force: true) }
        .dsAlert(L10n.t("تعديل الاسم", "Edit name"), isPresented: Binding(
            get: { editingIndex != nil }, set: { if !$0 { editingIndex = nil } }
        )) {
            TextField(L10n.t("الصفة (اختيارية)", "Role (optional)"), text: $editRole)
                .dsAlertField()
            TextField(L10n.t("الاسم", "Name"), text: $editName)
                .dsAlertField()
            Button(L10n.t("حفظ", "Save")) {
                if let i = editingIndex { applyEdit(at: i) }
                editingIndex = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { editingIndex = nil }
        }
        .dsAlert(L10n.t("حذف الاسم", "Delete name"), isPresented: Binding(
            get: { deletingIndex != nil }, set: { if !$0 { deletingIndex = nil } }
        )) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                if let i = deletingIndex { mutate { $0.remove(at: i) } }
                deletingIndex = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { deletingIndex = nil }
        } message: {
            Text(L10n.t("يختفي من مربّع «عن التطبيق» عند الجميع.", "It disappears from the About box for everyone."))
        }
        .dsAlert(L10n.t("تعذّر الحفظ", "Couldn't save"), isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: - الرأس الكحلي

    private var header: AdminPageHeader {
        AdminPageHeader(
            title: L10n.t("أسماء عن التطبيق", "About box names"),
            subtitle: L10n.t("تظهر في مربّع «عن التطبيق» بهذا الترتيب، والصفة فوق الاسم.",
                             "Shown in the About box in this order, with the role above the name."),
            glyph: "info.circle.fill",
            kpis: [
                AdminPageKPI(AdminPageKPI.count(credits.count, ready: loaded), L10n.t("اسم", "Names"),
                             icon: "person.2.fill")
            ])
    }

    // MARK: - إضافة اسم

    private var canAdd: Bool {
        !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && credits.count < Self.maxCount && !saving
    }

    private var addSection: some View {
        AdminSectionCard(title: L10n.t("إضافة اسم", "Add a name")) {
            VStack(spacing: DS.Spacing.sm) {
                DSComposerField(icon: "tag.fill",
                                label: L10n.t("الصفة (اختيارية)", "Role (optional)"),
                                placeholder: L10n.t("مثل: التصميم", "e.g. Design"),
                                text: limited($newRole, Self.maxRole),
                                tint: tint)
                HStack(spacing: DS.Spacing.sm) {
                    DSComposerField(icon: "person.fill",
                                    label: L10n.t("الاسم", "Name"),
                                    placeholder: L10n.t("الاسم كما يظهر", "The name as shown"),
                                    text: limited($newName, Self.maxName),
                                    tint: tint)
                        .submitLabel(.done)
                        .onSubmit { if canAdd { submitAdd() } }
                    if canAdd {
                        DSChipButton(L10n.t("إضافة", "Add"), icon: "plus", isSelected: true) { submitAdd() }
                    }
                }
                if credits.count >= Self.maxCount {
                    DSNoteCard(L10n.t("الحد الأعلى 20 اسماً.", "The limit is 20 names."),
                               icon: "info.circle.fill", tint: DS.Color.info)
                }
            }
        }
    }

    // MARK: - الأسماء

    @ViewBuilder
    private var listSection: some View {
        if !loaded {
            AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الأسماء…", "Loading names…")))
        } else {
            AdminSectionCard(title: L10n.t("الأسماء", "Names"),
                             tag: saving ? L10n.t("حفظ…", "Saving…") : "\(credits.count)") {
                AdminRowsCardBody {
                    ForEach(Array(credits.enumerated()), id: \.offset) { i, credit in
                        row(credit, at: i)
                    }
                }
            }
        }
    }

    private func row(_ credit: Credit, at i: Int) -> some View {
        HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: "person.fill", tint: tint)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                if let role = credit.role?.trimmingCharacters(in: .whitespacesAndNewlines), !role.isEmpty {
                    Text(role)
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.accent)
                }
                Text(credit.name)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if canEdit {
                Menu {
                    Button {
                        editRole = credit.role ?? ""
                        editName = credit.name
                        editingIndex = i
                    } label: { Label(L10n.t("تعديل", "Edit"), systemImage: "pencil") }

                    if i > 0 {
                        Button { mutate { $0.swapAt(i, i - 1) } } label: {
                            Label(L10n.t("نقل لأعلى", "Move up"), systemImage: "arrow.up")
                        }
                    }
                    if i < credits.count - 1 {
                        Button { mutate { $0.swapAt(i, i + 1) } } label: {
                            Label(L10n.t("نقل لأسفل", "Move down"), systemImage: "arrow.down")
                        }
                    }
                    // السيرفر يطلب اسماً واحداً على الأقل
                    if credits.count > 1 {
                        Button(role: .destructive) { deletingIndex = i } label: {
                            Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .dsGlyph(DS.Glyph.md)
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .padding(.vertical, -DS.Spacing.xsm)
                .disabled(saving)
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(minHeight: DSBox.fieldMinHeight)
        // القارئ الصوتي: الصفّ عنصر واحد «الصفة، الاسم» وخيارات القائمة إجراءاته (يُسحب لأعلى/لأسفل) بلا فتح القائمة
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel(credit))
        .accessibilityActions {
            if canEdit && !saving {
                Button(L10n.t("تعديل", "Edit")) {
                    editRole = credit.role ?? ""
                    editName = credit.name
                    editingIndex = i
                }
                if i > 0 {
                    Button(L10n.t("نقل لأعلى", "Move up")) { mutate { $0.swapAt(i, i - 1) } }
                }
                if i < credits.count - 1 {
                    Button(L10n.t("نقل لأسفل", "Move down")) { mutate { $0.swapAt(i, i + 1) } }
                }
                if credits.count > 1 {
                    Button(L10n.t("حذف", "Delete")) { deletingIndex = i }
                }
            }
        }
    }

    private func rowLabel(_ credit: Credit) -> String {
        let role = credit.role?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return role.isEmpty ? credit.name : "\(role)، \(credit.name)"
    }

    // MARK: - التحميل والحفظ

    /// يقصّ النص عند حدّ السيرفر أثناء الكتابة
    private func limited(_ text: Binding<String>, _ max: Int) -> Binding<String> {
        Binding(get: { text.wrappedValue }, set: { text.wrappedValue = String($0.prefix(max)) })
    }

    private func load(force: Bool) async {
        await config.refresh(force: force)
        let raw = config.values["about_credits"] as? [Any] ?? []
        if let data = try? JSONSerialization.data(withJSONObject: raw),
           let decoded = try? JSONDecoder().decode([Credit].self, from: data), !decoded.isEmpty {
            credits = decoded
        } else {
            // المفتاح لم يُضف على السيرفر بعد → ما يعرضه المربّع اليوم
            credits = [Credit(role: "فكرة وتنفيذ", name: "حسن الصايغ",
                              role_en: "Idea and development", name_en: "Hasan Al-Sayegh")]
        }
        loaded = true
    }

    private func submitAdd() {
        let role = newRole.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newRole = ""
        newName = ""
        KeyboardDismisser.endEditing()
        mutate { $0.append(Credit(role: role.isEmpty ? nil : role, name: name)) }
    }

    private func applyEdit(at i: Int) {
        guard credits.indices.contains(i) else { return }
        let role = String(editRole.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxRole))
        let name = String(editName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxName))
        guard !name.isEmpty else { return }
        mutate { list in
            var c = list[i]
            // الإنجليزي يتبع العربي: يُحذف إن تغيّر العربي (يرجع التطبيق للعربي)
            if c.name != name { c.name_en = nil }
            if (c.role ?? "") != role { c.role_en = nil }
            c.name = name
            c.role = role.isEmpty ? nil : role
            list[i] = c
        }
    }

    /// يغيّر القائمة ويحفظها كاملة؛ إن فشل الحفظ ترجع كما كانت
    private func mutate(_ change: (inout [Credit]) -> Void) {
        let before = credits
        var after = credits
        change(&after)
        guard after != before, !after.isEmpty else { return }
        credits = after
        Task { await save(after, revertTo: before) }
    }

    private struct Params: Encodable {
        let p_key: String
        let p_value: [Credit]
    }

    private func save(_ list: [Credit], revertTo before: [Credit]) async {
        saving = true
        defer { saving = false }
        do {
            _ = try await SupabaseConfig.client.rpc("set_app_config",
                                                    params: Params(p_key: "about_credits", p_value: list)).execute()
            await config.refresh(force: true)
        } catch {
            if ErrorHelper.isCancellation(error) { return }
            Log.warning("[CONFIG] تعذّر حفظ about_credits: \(error.localizedDescription)")
            credits = before
            let text = error.localizedDescription
            self.error = text.contains("unknown_key") || text.contains("إعداد غير معروف")
                ? L10n.t("الأسماء لم تُفعَّل على السيرفر بعد.", "Names aren't enabled on the server yet.")
                : L10n.t("يرجى التحقق من الاتصال والمحاولة مرة أخرى.", "Check the connection and try again.")
        }
    }
}
