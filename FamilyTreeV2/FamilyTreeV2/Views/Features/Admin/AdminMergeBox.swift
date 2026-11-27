import Supabase
import SwiftUI

// MARK: - مربّع «دمج» في «المكرر والأخطاء» (موافقة المالك ٢٠٢٦-١١-٢٧؛ «خله دمج واحد» نفس اليوم)
//
// زرّ «دمج» واحد على بطاقة المجموعة. المربّع: «أيّهما يبقى؟» (مربّعات بالاسم الكامل وسطر الفرق؛ من لا يصلح للبقاء باهت،
// وصاحب الحساب مختار مسبقاً) ← لثلاثة فأكثر «أيّهم يُحذف؟» ← التأكيد: يبقى · يُحذف · «ينتقل: …» من معاينة السيرفر
// (`merge_duplicate_members(p_dry_run: true)`) · «يُحذف الاسم المكرر نهائياً.» · «دمج» أحمر و«رجوع». النجاح لحظة
// `DSMomentToast` ثم تحديث القوائم فتختفي المجموعة. المنطق الخالص (الخطة، نصّ ما ينتقل، رسائل الأخطاء) في `AdminMergeRules`.

/// شخص في المربّع: الاسم الكامل + سطر الفرق (عدد الأبناء · الزوج · «أُضيف في …»)
struct AdminMergePerson: Equatable {
    let id: UUID
    let name: String
    let facts: String
}

struct AdminMergeContext: Identifiable {
    /// كل من في المجموعة بترتيبها
    let people: [AdminMergePerson]
    /// من يبقى ومن يُحذف (`AdminMergeRules.plan`)
    let plan: AdminMergeRules.Plan
    let signature: String
    var id: String { signature }
}

/// النداء الواحد: المعاينة والدمج الفعلي
enum AdminMergeWrites {
    private struct Params: Encodable {
        let p_keep: String
        let p_remove: String
        let p_dry_run: Bool
    }

    static func run(keep: UUID, remove: UUID, dryRun: Bool) async -> Result<AdminMergeRules.Preview, AdminMergeFailure> {
        do {
            let data = try await SupabaseConfig.client
                .rpc("merge_duplicate_members",
                     params: Params(p_keep: keep.uuidString, p_remove: remove.uuidString, p_dry_run: dryRun))
                .execute().data
            guard let preview = AdminMergeRules.preview(from: data) else {
                return .failure(AdminMergeFailure(message: AdminMergeRules.message(hint: nil)))
            }
            return .success(preview)
        } catch {
            let pg = error as? PostgrestError
            let raw = ErrorHelper.description(error)
            Log.error("[Merge] merge_duplicate_members (dry=\(dryRun)): \(raw)")
            if pg?.code == "PGRST202" || raw.localizedCaseInsensitiveContains("could not find the function") {
                return .failure(AdminMergeFailure(message: "هذه الميزة تحتاج تحديث السيرفر."))
            }
            return .failure(AdminMergeFailure(message: AdminMergeRules.message(hint: pg?.hint)))
        }
    }
}

struct AdminMergeFailure: Error, Equatable {
    let message: String
}

struct AdminMergeBox: View {
    let context: AdminMergeContext
    /// بعد نجاح الدمج: تحديث الأعضاء وشجرة النساء
    let onMerged: () async -> Void
    let onClose: () -> Void

    private enum Step { case keep, remove, confirm }

    @State private var step: Step = .keep
    @State private var keepId: UUID?
    @State private var removeId: UUID?
    @State private var preview: AdminMergeRules.Preview?
    @State private var loading = false
    @State private var failure: String?
    @State private var busy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(context: AdminMergeContext, onMerged: @escaping () async -> Void, onClose: @escaping () -> Void) {
        self.context = context
        self.onMerged = onMerged
        self.onClose = onClose
        _keepId = State(initialValue: context.plan.preselected)
    }

    // حارس المكدس: المربّع طبقة خلف `AnyView`
    var body: some View {
        AnyView(box)
            .task(id: step) { if step == .confirm { await loadPreview() } }
    }

    private func person(_ id: UUID?) -> AdminMergePerson? { context.people.first { $0.id == id } }
    private var removeOptions: [UUID] { keepId.map { context.plan.removeOptions(keep: $0) } ?? [] }

    @ViewBuilder
    private var box: some View {
        switch step {
        case .keep:
            DSComposer(
                title: L10n.t("دمج اسم مكرر", "Merge a duplicate"),
                subtitle: L10n.t("أيّهما يبقى؟", "Which one stays?"),
                icon: "arrow.triangle.merge",
                tint: DS.Color.actionNavy,
                actionTitle: L10n.t("التالي", "Next"),
                actionIcon: L10n.isArabic ? "chevron.left" : "chevron.right",
                canSubmit: keepId != nil,
                onSubmit: afterKeep,
                onCancel: onClose
            ) {
                DSComposerSection(title: L10n.t(context.people.count > 2 ? "أيّهم يبقى؟" : "أيّهما يبقى؟", "Which one stays?"),
                                  icon: "checkmark.circle.fill", tint: DS.Color.success, index: 0) {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(context.people, id: \.id) { p in
                            choiceTile(p, selected: keepId == p.id,
                                       enabled: context.plan.keepOptions.contains(p.id)) { keepId = p.id }
                        }
                    }
                }
            }
        case .remove:
            DSComposer(
                title: L10n.t("دمج اسم مكرر", "Merge a duplicate"),
                subtitle: person(keepId)?.name ?? "",
                icon: "arrow.triangle.merge",
                tint: DS.Color.actionNavy,
                actionTitle: L10n.t("التالي", "Next"),
                actionIcon: L10n.isArabic ? "chevron.left" : "chevron.right",
                canSubmit: removeId != nil,
                onSubmit: { go(.confirm) },
                onCancel: back
            ) {
                DSComposerSection(title: L10n.t("أيّهم يُحذف ويُدمج فيه؟", "Which one is removed into it?"),
                                  icon: "trash.fill", tint: DS.Color.error, index: 0) {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(removeOptions, id: \.self) { id in
                            if let p = person(id) {
                                choiceTile(p, selected: removeId == id, enabled: true) { removeId = id }
                            }
                        }
                    }
                }
            }
        case .confirm:
            DSComposer(
                title: L10n.t("تأكيد الدمج", "Confirm merge"),
                subtitle: person(removeId)?.name ?? "",
                icon: "arrow.triangle.merge",
                tint: DS.Color.actionNavy,
                actionTitle: "",
                showsAction: false,
                showsCancel: false,
                canSubmit: false,
                isBusy: busy,
                extraActions: [
                    DSComposerAction(id: "merge", title: L10n.t("دمج", "Merge"), icon: "arrow.triangle.merge",
                                     role: .destructive, isEnabled: preview != nil && failure == nil && !loading,
                                     action: merge),
                    DSComposerAction(id: "back", title: L10n.t("رجوع", "Back"), role: .cancel, action: back)
                ],
                onSubmit: {},
                onCancel: back
            ) {
                if let keep = person(keepId) {
                    DSComposerSection(title: L10n.t("يبقى", "Kept"), icon: "checkmark.circle.fill",
                                      tint: DS.Color.success, index: 0) {
                        personCard(keep, tone: DS.Color.success)
                    }
                }
                if let removed = person(removeId) {
                    DSComposerSection(title: L10n.t("يُحذف", "Removed"), icon: "trash.fill", tint: DS.Color.error, index: 1) {
                        personCard(removed, tone: DS.Color.error)
                    }
                }
                DSComposerSection(title: L10n.t("ما ينتقل", "What moves"), icon: "arrow.right.arrow.left",
                                  tint: DS.Color.primary, index: 2) {
                    summary
                }
                if let failure {
                    DSNoteCard(failure, icon: "exclamationmark.circle.fill", tint: DS.Color.error)
                } else {
                    DSNoteCard(AdminMergeRules.deleteNote, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                }
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        if loading {
            HStack(spacing: DS.Spacing.sm) {
                ProgressView().scaleEffect(DS.Spinner.chipScale)
                Text(L10n.t("جارٍ حساب ما ينتقل…", "Working out what moves…"))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: DS.Hub.rowMinHeight, alignment: .leading)
        } else if let preview {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(verbatim: AdminMergeRules.movesLine(preview))
                    .dsFont(.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let line = AdminMergeRules.conflictsLine(preview) {
                    Text(verbatim: line)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let line = AdminMergeRules.notMovedLine(preview) {
                    Text(verbatim: line)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(L10n.t("تعذّر حساب ما ينتقل.", "Couldn't work out what moves."))
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: قطع

    /// مربّع اختيار: الاسم الكامل وسطر الفرق — المختار بإطار وتعبئة خفيفة، ومن لا يصلح باهت لا يُضغط
    private func choiceTile(_ person: AdminMergePerson, selected: Bool, enabled: Bool,
                            choose: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        return Button {
            guard enabled, !selected else { return }
            withAnimation(reduceMotion ? nil : DS.Anim.snappy) { choose() }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .dsGlyph(DS.Glyph.lg, weight: .medium)
                    .foregroundColor(selected ? DS.Color.primary : DS.Color.textTertiary)
                    .accessibilityHidden(true)
                personLines(person)
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
            .background(shape.fill(selected ? DS.Color.choicePill : DS.Color.fieldFill))
            .overlay(shape.strokeBorder(selected ? DS.Color.selectionStroke : DS.Color.cardBorder,
                                        lineWidth: DS.Border.width))
            .contentShape(shape)
            .opacity(enabled ? 1 : DS.Opacity.disabled)
        }
        .buttonStyle(DSPressStyle())
        .disabled(!enabled)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func personCard(_ person: AdminMergePerson, tone: Color) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            RoundedRectangle(cornerRadius: DS.Border.width * 2, style: .continuous)
                .fill(tone)
                .frame(width: DS.Spacing.xs)
                .accessibilityHidden(true)
            personLines(person)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func personLines(_ person: AdminMergePerson) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(verbatim: person.name)
                .dsFont(.hubRow)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !person.facts.isEmpty {
                Text(verbatim: person.facts)
                    .dsFont(.subtitle)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: الإجراءات

    private func go(_ next: Step) {
        withAnimation(reduceMotion ? nil : DS.Anim.snappy) { step = next }
    }

    /// بعد «أيّهما يبقى؟»: واحد يُحذف = التأكيد مباشرة، وأكثر = «أيّهم يُحذف؟»
    private func afterKeep() {
        guard keepId != nil else { return }
        let options = removeOptions
        if !options.contains(where: { $0 == removeId }) { removeId = options.count == 1 ? options.first : nil }
        go(options.count > 1 ? .remove : .confirm)
    }

    private func back() {
        guard !busy else { return }
        preview = nil
        failure = nil
        switch step {
        case .keep: onClose()
        case .remove: go(.keep)
        case .confirm: go(removeOptions.count > 1 ? .remove : .keep)
        }
    }

    private func loadPreview() async {
        guard let keepId, let removeId else { return }
        loading = true
        failure = nil
        preview = nil
        let result = await AdminMergeWrites.run(keep: keepId, remove: removeId, dryRun: true)
        guard keepId == self.keepId, removeId == self.removeId else { return }
        loading = false
        switch result {
        case .success(let p): preview = p
        case .failure(let f): failure = f.message
        }
    }

    private func merge() {
        guard let keepId, let removeId, !busy, preview != nil else { return }
        // تجربة دور: لا كتابة على السيرفر — نجاح مصطنع
        if DebugAdminProbe.dryRun("merge duplicate \(removeId) → \(keepId)") {
            DSMomentToast.show(L10n.t("تم الدمج", "Merged"), moment: .success)
            onClose()
            return
        }
        guard NetworkMonitor.shared.requireOnline() else { return }
        busy = true
        failure = nil
        Task {
            let result = await AdminMergeWrites.run(keep: keepId, remove: removeId, dryRun: false)
            switch result {
            case .success:
                Log.info("[Merge] دُمج \(removeId) في \(keepId)")
                DSMomentToast.show(L10n.t("تم الدمج", "Merged"), moment: .success)
                busy = false
                onClose()
                await onMerged()
            case .failure(let f):
                busy = false
                failure = f.message
            }
        }
    }
}

// MARK: - مربّع «حذف» الاسم الفارغ («حط حذف بعد اذا في مكرر وبيانات ناقصة و نفس المكان بالشجرة»، المالك ٢٠٢٦-١١-٢٧)
//
// «حذف» بجانب «دمج» على البطاقة حين يكون فيها اسم لا يُفقد بحذفه شيء (`AdminMergeRules.deleteCandidates`). أكثر من مرشّح:
// «أيّهم يُحذف؟» (الأفرغ ثم الأقدم إضافة مختار مسبقاً) ← التأكيد: الاسم الكامل · «لا توجد بيانات تُفقد.» · «يُحذف نهائياً.» ·
// «حذف» أحمر و«رجوع». الحذف نفسه طريق الإدارة الموجود (الصفحة تمرّره: `deleteMember` للرجال، `WomenStore.delete` للنساء)،
// وحماية روابط العائلة على السيرفر ترفض إن بقي أحد مربوطاً (الرسالة رسمية من `AdminMergeRules.deleteMessage`).

struct AdminDeleteDuplicateContext: Identifiable {
    /// المرشّحون بترتيب الاختيار — الأول مختار مسبقاً
    let candidates: [AdminMergePerson]
    let signature: String
    var id: String { "delete-" + signature }
}

struct AdminDeleteDuplicateBox: View {
    let context: AdminDeleteDuplicateContext
    /// الحذف: nil = نجح، وإلا رسالة رسمية
    let perform: (UUID) async -> String?
    let onClose: () -> Void

    private enum Step { case pick, confirm }

    @State private var step: Step
    @State private var chosen: UUID?
    @State private var failure: String?
    @State private var busy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(context: AdminDeleteDuplicateContext, perform: @escaping (UUID) async -> String?, onClose: @escaping () -> Void) {
        self.context = context
        self.perform = perform
        self.onClose = onClose
        _step = State(initialValue: context.candidates.count > 1 ? .pick : .confirm)
        _chosen = State(initialValue: context.candidates.first?.id)
    }

    var body: some View { AnyView(box) }

    private var person: AdminMergePerson? { context.candidates.first { $0.id == chosen } }

    @ViewBuilder
    private var box: some View {
        switch step {
        case .pick:
            DSComposer(
                title: L10n.t("حذف اسم مكرر", "Delete a duplicate"),
                subtitle: L10n.t("أيّهم يُحذف؟", "Which one is deleted?"),
                icon: "trash",
                tint: DS.Color.actionNavy,
                actionTitle: L10n.t("التالي", "Next"),
                actionIcon: L10n.isArabic ? "chevron.left" : "chevron.right",
                canSubmit: chosen != nil,
                onSubmit: { go(.confirm) },
                onCancel: onClose
            ) {
                DSComposerSection(title: L10n.t("أيّهم يُحذف؟", "Which one is deleted?"),
                                  icon: "trash.fill", tint: DS.Color.error, index: 0) {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(context.candidates, id: \.id) { p in tile(p) }
                    }
                }
            }
        case .confirm:
            DSComposer(
                title: L10n.t("تأكيد الحذف", "Confirm delete"),
                subtitle: person?.name ?? "",
                icon: "trash",
                tint: DS.Color.actionNavy,
                actionTitle: "",
                showsAction: false,
                showsCancel: false,
                canSubmit: false,
                isBusy: busy,
                extraActions: [
                    DSComposerAction(id: "delete", title: L10n.t("حذف", "Delete"), icon: "trash",
                                     role: .destructive, isEnabled: chosen != nil && !busy, action: delete),
                    DSComposerAction(id: "back", title: L10n.t("رجوع", "Back"), role: .cancel, action: back)
                ],
                onSubmit: {},
                onCancel: back
            ) {
                if let person {
                    DSComposerSection(title: L10n.t("يُحذف", "Deleted"), icon: "trash.fill", tint: DS.Color.error, index: 0) {
                        lines(person)
                    }
                }
                DSNoteCard(AdminMergeRules.nothingLostNote, icon: "checkmark.circle.fill", tint: DS.Color.success)
                if let failure {
                    DSNoteCard(failure, icon: "exclamationmark.circle.fill", tint: DS.Color.error)
                } else {
                    DSNoteCard(AdminMergeRules.deleteForeverNote, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                }
            }
        }
    }

    private func tile(_ p: AdminMergePerson) -> some View {
        let selected = chosen == p.id
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        return Button {
            guard !selected else { return }
            withAnimation(reduceMotion ? nil : DS.Anim.snappy) { chosen = p.id }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .dsGlyph(DS.Glyph.lg, weight: .medium)
                    .foregroundColor(selected ? DS.Color.primary : DS.Color.textTertiary)
                    .accessibilityHidden(true)
                lines(p)
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
            .background(shape.fill(selected ? DS.Color.choicePill : DS.Color.fieldFill))
            .overlay(shape.strokeBorder(selected ? DS.Color.selectionStroke : DS.Color.cardBorder, lineWidth: DS.Border.width))
            .contentShape(shape)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func lines(_ p: AdminMergePerson) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(verbatim: p.name)
                .dsFont(.hubRow)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !p.facts.isEmpty {
                Text(verbatim: p.facts)
                    .dsFont(.subtitle)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func go(_ next: Step) {
        withAnimation(reduceMotion ? nil : DS.Anim.snappy) { step = next }
    }

    private func back() {
        guard !busy else { return }
        failure = nil
        if step == .confirm, context.candidates.count > 1 { go(.pick) } else { onClose() }
    }

    private func delete() {
        guard let chosen, !busy else { return }
        // تجربة دور: لا كتابة على السيرفر — نجاح مصطنع
        if DebugAdminProbe.dryRun("delete duplicate \(chosen)") {
            DSMomentToast.show(L10n.t("تم الحذف", "Deleted"), moment: .success)
            onClose()
            return
        }
        guard NetworkMonitor.shared.requireOnline() else { return }
        busy = true
        failure = nil
        Task {
            let message = await perform(chosen)
            busy = false
            if let message {
                failure = message
            } else {
                Log.info("[Duplicates] حُذف الاسم المكرر الفارغ \(chosen)")
                DSMomentToast.show(L10n.t("تم الحذف", "Deleted"), moment: .success)
                onClose()
            }
        }
    }
}
