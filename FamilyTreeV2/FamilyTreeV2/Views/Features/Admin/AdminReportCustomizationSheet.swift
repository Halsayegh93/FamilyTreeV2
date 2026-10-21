import SwiftUI

struct AdminReportCustomizationSheet: View {
    let kind: AdminReportKind
    let apply: (Set<AdminReportField>, AdminReportOptions) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<AdminReportField>
    @State private var options: AdminReportOptions

    init(kind: AdminReportKind, fields: Set<AdminReportField>, options: AdminReportOptions,
         apply: @escaping (Set<AdminReportField>, AdminReportOptions) -> Void) {
        self.kind = kind
        self.apply = apply
        _chosen = State(initialValue: kind.resolvedFields(fields))
        _options = State(initialValue: options)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.t("اختر البيانات التي تريد طباعتها. تتحدث المعاينة بعد الضغط على «تطبيق».",
                                "Choose the data to print. The preview updates when you tap Apply."))
                        .font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        preset(L10n.t("مختصر", "Minimal"), fields: kind == .stats ? [.people] : kind.lockedFields)
                        preset(L10n.t("أساسي", "Standard"), fields: kind.defaultFields)
                        preset(L10n.t("كل البيانات", "All data"), fields: Set(kind.fields))
                    }
                }
                fieldSection(L10n.t("البيانات الأساسية", "Basic data"), [.name, .branch, .status, .people, .branches])
                fieldSection(L10n.t("التواريخ والأعمار", "Dates and ages"), [.birth, .age, .death, .anniversary, .ageAtDeath, .ages])
                fieldSection(L10n.t("التواصل والتسجيل", "Contact and registration"), [.phone, .registration, .registered])
                if kind == .register {
                    Section(L10n.t("حجم القائمة", "List size")) {
                        Picker(L10n.t("الخط والمسافات", "Text and spacing"), selection: $options.compactRows) {
                            Text(L10n.t("أصغر", "Compact")).tag(true)
                            Text(L10n.t("عادي", "Regular")).tag(false)
                        }.pickerStyle(.segmented)
                        Text(L10n.t("«أصغر» يقلل الخط والمسافات قليلًا لعرض أسماء أكثر في الصفحة.",
                                    "Compact uses slightly smaller text and spacing to fit more names per page."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section(L10n.t("ترتيب القائمة", "List grouping")) {
                        Toggle(L10n.t("تقسيم الأسماء حسب الفروع", "Group names by branch"), isOn: $options.groupByBranch)
                        Text(L10n.t("عند إطفائه تظهر الأسماء في قائمة واحدة بترتيب الشجرة.",
                                    "When off, names appear in one list in tree order."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section(L10n.t("أجزاء الملف", "Document sections")) {
                        Toggle(L10n.t("صفحة الغلاف", "Cover page"), isOn: $options.includeCover)
                        Toggle(L10n.t("ملخّص الأعداد", "Count summary"), isOn: $options.includeSummary)
                        if options.groupByBranch {
                            Toggle(L10n.t("جدول ملخّص الفروع", "Branch summary table"), isOn: $options.includeBranchSummary)
                        }
                        Text(L10n.t("أطفئها إذا تبي الملف يبدأ بقائمة الأسماء مباشرة.",
                                    "Turn these off to start the document directly with the member list."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text(L10n.t("الأسماء المطلوبة تبقى ظاهرة، والبيانات المخفية من أصحابها تبقى مخفية في الملف.",
                                "Required names stay included. Data hidden by members stays hidden in the export."))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(L10n.t("استعادة الخيارات الافتراضية", "Restore default options")) {
                        chosen = kind.defaultFields
                        options = .init()
                    }
                }
            }
            .navigationTitle(L10n.t("تخصيص التقرير", "Customize report"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("تطبيق", "Apply")) {
                        apply(kind.resolvedFields(chosen), options)
                        dismiss()
                    }.disabled(chosen.isEmpty)
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func preset(_ title: String, fields: Set<AdminReportField>) -> some View {
        Button(title) { chosen = kind.resolvedFields(fields) }
            .font(.caption).buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func fieldSection(_ title: String, _ candidates: Set<AdminReportField>) -> some View {
        let available = kind.fields.filter(candidates.contains)
        if !available.isEmpty {
            Section(title) {
                ForEach(available) { field in
                    Toggle(isOn: Binding(get: { chosen.contains(field) }, set: { enabled in
                        if enabled { chosen.insert(field) } else { chosen.remove(field) }
                    })) {
                        HStack {
                            Text(AdminReportsView.fieldTitle(field, kind: kind))
                            if kind.lockedFields.contains(field) {
                                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                                    .accessibilityLabel(L10n.t("مطلوب", "Required"))
                            }
                        }
                    }.disabled(kind.lockedFields.contains(field))
                }
            }
        }
    }
}
