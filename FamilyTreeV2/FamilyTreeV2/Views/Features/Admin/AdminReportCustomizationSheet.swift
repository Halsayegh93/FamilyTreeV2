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

    private let tint = DS.Color.actionNavy

    var body: some View {
        DSComposer(
            title: L10n.t("تخصيص التقرير", "Customize report"),
            subtitle: L10n.t("اختر البيانات وشكل القائمة", "Choose the data and list layout"),
            icon: "doc.text.fill",
            tint: tint,
            actionTitle: L10n.t("تطبيق", "Apply"),
            canSubmit: !chosen.isEmpty,
            onSubmit: {
                apply(kind.resolvedFields(chosen), options)
                dismiss()
            },
            onCancel: { dismiss() }
        ) {
            DSComposerSection(title: L10n.t("اختيار سريع", "Quick selection"), icon: "square.grid.2x2.fill", tint: tint, index: 0) {
                ChangedWordsFlow(spacing: DS.Spacing.xs) {
                    preset("minimal", L10n.t("مختصر", "Minimal"), fields: kind == .stats ? [.people] : kind.lockedFields)
                    preset("standard", L10n.t("أساسي", "Standard"), fields: kind.defaultFields)
                    preset("all", L10n.t("كل البيانات", "All data"), fields: Set(kind.fields))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                hint(L10n.t("تتحدث المعاينة بعد الضغط على «تطبيق».", "The preview updates when you tap Apply."))
            }
            fieldSection(L10n.t("البيانات الأساسية", "Basic data"), icon: "person.text.rectangle", index: 1,
                         [.name, .branch, .status, .people, .branches])
            fieldSection(L10n.t("التواريخ والأعمار", "Dates and ages"), icon: "calendar", index: 2,
                         [.birth, .age, .death, .anniversary, .ageAtDeath, .ages])
            fieldSection(L10n.t("التواصل والتسجيل", "Contact and registration"), icon: "phone.fill", index: 3,
                         [.phone, .registration, .registered])
            if kind == .register {
                DSComposerSection(title: L10n.t("حجم القائمة", "List size"), icon: "textformat.size", tint: tint, index: 4) {
                    DSSegmentedSwitch(options: [
                        .init(id: true, title: L10n.t("أصغر", "Compact"), icon: "textformat.size.smaller"),
                        .init(id: false, title: L10n.t("عادي", "Regular"), icon: "textformat.size")
                    ], selection: $options.compactRows, size: .regular)
                    hint(L10n.t("«أصغر» يقلل الخط والمسافات قليلًا لعرض أسماء أكثر في الصفحة.",
                                "Compact uses slightly smaller text and spacing to fit more names per page."))
                }
                DSComposerSection(title: L10n.t("ترتيب القائمة", "List grouping"), icon: "arrow.triangle.branch", tint: tint, index: 5) {
                    DSToggleBox(title: L10n.t("تقسيم الأسماء حسب الفروع", "Group names by branch"), isOn: $options.groupByBranch, tint: tint)
                    hint(L10n.t("عند إطفائه تظهر الأسماء في قائمة واحدة بترتيب الشجرة.",
                                "When off, names appear in one list in tree order."))
                }
                DSComposerSection(title: L10n.t("أجزاء الملف", "Document sections"), icon: "doc.on.doc.fill", tint: tint, index: 6) {
                    DSToggleBox(title: L10n.t("صفحة الغلاف", "Cover page"), isOn: $options.includeCover, tint: tint)
                    DSToggleBox(title: L10n.t("ملخّص الأعداد", "Count summary"), isOn: $options.includeSummary, tint: tint)
                    if options.groupByBranch {
                        DSToggleBox(title: L10n.t("جدول ملخّص الفروع", "Branch summary table"), isOn: $options.includeBranchSummary, tint: tint)
                    }
                    hint(L10n.t("أطفئها إذا تبي الملف يبدأ بقائمة الأسماء مباشرة.",
                                "Turn these off to start the document directly with the member list."))
                }
            }
            DSNoteCard(L10n.t("البيانات المطلوبة تبقى ظاهرة، والبيانات المخفية من أصحابها تبقى مخفية في الملف.",
                              "Required data stays included. Data hidden by members stays hidden in the export."),
                       icon: "lock.shield.fill", tint: tint)
            DSSecondaryButton(L10n.t("استعادة الخيارات الافتراضية", "Restore default options"),
                              icon: "arrow.counterclockwise", color: tint, size: .regular) {
                chosen = kind.defaultFields
                options = .init()
            }
        }
        .environment(\.dsSection, .admin)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private var presetID: String? {
        if chosen == kind.resolvedFields(kind.defaultFields) { return "standard" }
        if chosen == kind.resolvedFields(kind == .stats ? [.people] : kind.lockedFields) { return "minimal" }
        if chosen == Set(kind.fields) { return "all" }
        return nil
    }

    private func preset(_ id: String, _ title: String, fields: Set<AdminReportField>) -> some View {
        DSChipButton(title, icon: presetID == id ? "checkmark" : "plus", tint: tint,
                     isSelected: presetID == id, size: .small) {
            chosen = kind.resolvedFields(fields)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .dsFont(.footnote)
            .foregroundColor(DS.Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func fieldSection(_ title: String, icon: String, index: Int, _ candidates: Set<AdminReportField>) -> some View {
        let available = kind.fields.filter(candidates.contains)
        if !available.isEmpty {
            DSComposerSection(title: title, icon: icon, tint: tint, index: index) {
                ForEach(available) { field in
                    let locked = kind.lockedFields.contains(field)
                    DSToggleBox(title: AdminReportsView.fieldTitle(field, kind: kind)
                                + (locked ? L10n.t(" · مطلوب", " · Required") : ""),
                                isOn: Binding(get: { chosen.contains(field) }, set: { enabled in
                        if enabled { chosen.insert(field) } else { chosen.remove(field) }
                    }), tint: tint)
                    .disabled(locked)
                }
            }
        }
    }
}
