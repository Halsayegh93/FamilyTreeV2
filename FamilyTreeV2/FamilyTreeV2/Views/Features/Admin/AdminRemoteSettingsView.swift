import SwiftUI
import Supabase

struct AdminRemoteSettingsView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @StateObject private var model = RemoteSettingsModel.shared
    @State private var selection: ConfigSelection?
    @State private var search = ""
    var body: some View {
        List {
            Section {
                Text(L10n.t("تغييرات هذه الصفحة تظهر عند تحديث الإعدادات بدون بناء جديد. التعديل للمالك، والمدير يطّلع فقط.",
                            "Changes apply when settings refresh without a new build. Only the owner can edit; admins can view."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let payload = model.payload, let meta = payload.meta {
                ForEach((payload.categories ?? []).sorted { $0.sort < $1.sort }) { category in
                    let keys = meta.keys.filter {
                        meta[$0]?.category == category.key && (search.isEmpty || meta[$0]!.label_ar.localizedCaseInsensitiveContains(search))
                    }.sorted { (meta[$0]!.sort, $0) < (meta[$1]!.sort, $1) }
                    if !keys.isEmpty {
                        Section(category.label_ar) {
                            ForEach(keys, id: \.self) { key in
                                Button {
                                    selection = ConfigSelection(key: key, meta: meta[key]!, value: payload.values[key] ?? .null)
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(meta[key]!.label_ar).foregroundStyle(.primary)
                                        Text(payload.values[key]?.strings?.joined(separator: "، ") ?? payload.values[key]?.editorText ?? "—")
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        if let name = meta[key]?.updated_by_name {
                                            Text(L10n.t("آخر تعديل: \(name)", "Last changed by \(name)"))
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                    NavigationLink(L10n.t("سجل تغييرات الإعدادات", "Settings change history")) { AdminRemoteSettingsHistory() }
                }
            } else if model.loading { ProgressView() }
            if let error = model.error {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button(L10n.t("إعادة المحاولة", "Retry")) { Task { await model.refresh() } }
                }
            }
        }
        .navigationTitle(L10n.t("إعدادات السيرفر", "Server settings"))
        .searchable(text: $search, prompt: L10n.t("ابحث عن إعداد", "Find a setting"))
        .task { await model.refresh() }
        .refreshable { await model.refresh() }
        .sheet(item: $selection) { item in
            ConfigEditor(item: item, canEdit: authVM.canManageSettings && model.payload?.can_edit == true)
        }
    }
}
private struct ConfigSelection: Identifiable {
    let key: String
    let meta: RemoteConfigMeta
    let value: ConfigValue
    var id: String { key }
}
private struct ConfigEditor: View {
    let item: ConfigSelection
    let canEdit: Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = RemoteSettingsModel.shared
    @State private var draft = ""
    @State private var validation: String?
    @State private var confirmReset = false
    var body: some View {
        NavigationStack {
            Form {
                Section(item.meta.label_ar) {
                    if let help = item.meta.help_ar { Text(help).font(.footnote).foregroundStyle(.secondary) }
                    if item.meta.kind == "int" {
                        TextField(L10n.t("القيمة", "Value"), text: $draft).keyboardType(.numberPad)
                    } else {
                        TextEditor(text: $draft).frame(minHeight: 150)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                    if let min = item.meta.min, let max = item.meta.max {
                        Text(L10n.t("المدى: \(Int(min)) إلى \(Int(max))", "Range: \(Int(min)) to \(Int(max))")).font(.caption)
                    }
                    if let max = item.meta.max_length {
                        Text(L10n.t("الحد الأقصى: \(max) حرف", "Maximum: \(max) characters")).font(.caption)
                    }
                    if item.meta.kind == "json" {
                        Text(L10n.t("اكتب كل عنوان في سطر مستقل.", "Write each title on a separate line."))
                            .font(.caption)
                    }
                }.disabled(!canEdit || model.saving)
                if let error = validation ?? model.error { Text(error).foregroundStyle(.red) }
                if canEdit {
                    Button(L10n.t("حفظ", "Save")) { save() }.disabled(model.saving)
                    Button(L10n.t("إعادة للقيمة الافتراضية", "Restore default"), role: .destructive) { confirmReset = true }
                        .disabled(model.saving || item.meta.is_default)
                }
            }
            .navigationTitle(item.meta.label_ar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(L10n.t("إغلاق", "Close")) { dismiss() }.disabled(model.saving)
            } }
            .confirmationDialog(L10n.t("إعادة هذا الإعداد للافتراضي؟", "Restore this setting's default?"), isPresented: $confirmReset) {
                Button(L10n.t("إعادة للافتراضي", "Restore default"), role: .destructive) {
                    Task { if await model.save(key: item.key, value: .null) { dismiss() } }
                }
            }
            .onAppear { draft = item.meta.kind == "json" ? (item.value.strings?.joined(separator: "\n") ?? "") : item.value.editorText; model.error = nil }
            .interactiveDismissDisabled(model.saving)
        }
    }
    private func save() {
        let value: ConfigValue
        if item.meta.kind == "int" {
            let normalized = draft.map { char -> String in
                if let digit = char.wholeNumberValue { return String(digit) }
                return String(char)
            }.joined()
            guard let n = Double(normalized), n.isFinite, n.rounded() == n,
                  n >= (item.meta.min ?? -2147483647), n <= (item.meta.max ?? 2147483647) else {
                validation = L10n.t("أدخل عددًا صحيحًا ضمن المدى.", "Enter a whole number within the range."); return
            }
            value = .number(n)
        } else if item.meta.kind == "json" {
            value = .array(draft.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.map(ConfigValue.string))
        } else { value = .string(draft) }
        validation = nil
        Task { if await model.save(key: item.key, value: value) { dismiss() } }
    }
}
private struct AdminRemoteSettingsHistory: View {
    private struct Entry: Decodable, Identifiable {
        let id: Int
        let key: String
        let old_value: ConfigValue?
        let new_value: ConfigValue
        let changed_at: String
        let changed_by_name: String?
    }
    @State private var entries: [Entry] = []
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    Text(RemoteSettingsModel.shared.payload?.meta?[entry.key]?.label_ar ?? entry.key)
                    Text("\(entry.old_value?.editorText ?? "—") → \(entry.new_value.editorText)")
                        .font(.caption).foregroundStyle(.secondary)
                    if let name = entry.changed_by_name { Text(name).font(.caption2).foregroundStyle(.secondary) }
                    Text(stamp(entry.changed_at)).font(.caption2)
                }
            }
            if entries.isEmpty && error == nil { Text(L10n.t("لا توجد تغييرات مسجّلة", "No changes recorded")) }
        }
        .navigationTitle(L10n.t("سجل الإعدادات", "Settings history"))
        .task { await load() }
        .refreshable { await load() }
    }
    private func stamp(_ raw: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date else { return raw }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    private func load() async {
        do {
            entries = try await SupabaseConfig.client.from("app_config_history")
                .select("id,key,old_value,new_value,changed_at,changed_by_name").order("id", ascending: false).limit(100).execute().value
            error = nil
        } catch { self.error = L10n.t("تعذّر تحميل السجل.", "Couldn't load history.") }
    }
}
