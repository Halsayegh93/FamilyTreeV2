import Supabase
import SwiftUI

// MARK: - مربّع «دمج» في «المكرر والأخطاء» (موافقة المالك ٢٠٢٦-١١-٢٧، «حط زر دمج لكل اسم واحد»)
//
// «دمجه في الآخر» بجانب اسم شخص = هذا الاسم يُحذف ويُدمج في الآخر (لا زرّ حيث يرفض السيرفر: متوفى وحيّ، ميلادان متباعدان). ثلاثة فأكثر: «يُدمج في أيّهم؟» أولاً (مربّعات بالاسم الكامل وسطر
// الفرق)، ثم التأكيد: يبقى · يُحذف · «ينتقل: …» من معاينة السيرفر (`merge_duplicate_members(p_dry_run: true)`) ·
// «يُحذف الاسم المكرر نهائياً.» · «دمج» أحمر و«رجوع». النجاح لحظة `DSMomentToast` ثم تحديث القوائم فتختفي المجموعة.
// المنطق الخالص (من يظهر عليه الزرّ، نصّ ما ينتقل، رسائل الأخطاء) في `AdminMergeRules`.

/// شخص في المربّع: الاسم الكامل + سطر الفرق (عدد الأبناء · الزوج · «أُضيف في …»)
struct AdminMergePerson: Equatable {
    let id: UUID
    let name: String
    let facts: String
}

struct AdminMergeContext: Identifiable {
    /// الاسم الذي يُحذف (صاحب زرّ «دمج»)
    let remove: AdminMergePerson
    /// من يمكن الدمج فيه (`AdminMergeRules.targets`) — واحد = بلا سؤال
    let targets: [AdminMergePerson]
    var id: UUID { remove.id }
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

    private enum Step { case pick, confirm }

    @State private var step: Step
    @State private var keepId: UUID?
    @State private var preview: AdminMergeRules.Preview?
    @State private var loading = false
    @State private var failure: String?
    @State private var busy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(context: AdminMergeContext, onMerged: @escaping () async -> Void, onClose: @escaping () -> Void) {
        self.context = context
        self.onMerged = onMerged
        self.onClose = onClose
        let single = context.targets.count == 1
        _step = State(initialValue: single ? .confirm : .pick)
        _keepId = State(initialValue: single ? context.targets.first?.id : nil)
    }

    // حارس المكدس: المربّع طبقة خلف `AnyView`
    var body: some View {
        AnyView(box)
            .task(id: step) { if step == .confirm { await loadPreview() } }
    }

    private var keep: AdminMergePerson? { context.targets.first { $0.id == keepId } }

    @ViewBuilder
    private var box: some View {
        switch step {
        case .pick:
            DSComposer(
                title: L10n.t("دمج اسم مكرر", "Merge a duplicate"),
                subtitle: context.remove.name,
                icon: "arrow.triangle.merge",
                tint: DS.Color.actionNavy,
                actionTitle: L10n.t("التالي", "Next"),
                actionIcon: L10n.isArabic ? "chevron.left" : "chevron.right",
                canSubmit: keepId != nil,
                onSubmit: { go(.confirm) },
                onCancel: onClose
            ) {
                DSComposerSection(title: L10n.t("يُدمج في أيّهم؟", "Merge into which one?"),
                                  icon: "person.2.fill", tint: DS.Color.primary, index: 0) {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(context.targets, id: \.id) { person in
                            choiceTile(person)
                        }
                    }
                }
                DSComposerSection(title: L10n.t("يُحذف", "Removed"), icon: "trash.fill", tint: DS.Color.error, index: 1) {
                    personCard(context.remove, tone: DS.Color.error)
                }
            }
        case .confirm:
            DSComposer(
                title: L10n.t("تأكيد الدمج", "Confirm merge"),
                subtitle: context.remove.name,
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
                if let keep {
                    DSComposerSection(title: L10n.t("يبقى", "Kept"), icon: "checkmark.circle.fill",
                                      tint: DS.Color.success, index: 0) {
                        personCard(keep, tone: DS.Color.success)
                    }
                }
                DSComposerSection(title: L10n.t("يُحذف", "Removed"), icon: "trash.fill", tint: DS.Color.error, index: 1) {
                    personCard(context.remove, tone: DS.Color.error)
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

    /// مربّع اختيار: الاسم الكامل وسطر الفرق — المختار بإطار وتعبئة خفيفة
    private func choiceTile(_ person: AdminMergePerson) -> some View {
        let selected = keepId == person.id
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        return Button {
            guard keepId != person.id else { return }
            withAnimation(reduceMotion ? nil : DS.Anim.snappy) { keepId = person.id }
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
        }
        .buttonStyle(DSPressStyle())
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
        guard keepId != nil else { return }
        withAnimation(reduceMotion ? nil : DS.Anim.snappy) { step = next }
    }

    private func back() {
        guard !busy else { return }
        if context.targets.count > 1 {
            preview = nil
            failure = nil
            withAnimation(reduceMotion ? nil : DS.Anim.snappy) { step = .pick }
        } else {
            onClose()
        }
    }

    private func loadPreview() async {
        guard let keepId else { return }
        loading = true
        failure = nil
        preview = nil
        let result = await AdminMergeWrites.run(keep: keepId, remove: context.remove.id, dryRun: true)
        guard keepId == self.keepId else { return }
        loading = false
        switch result {
        case .success(let p): preview = p
        case .failure(let f): failure = f.message
        }
    }

    private func merge() {
        guard let keepId, !busy, preview != nil else { return }
        // تجربة دور: لا كتابة على السيرفر — نجاح مصطنع
        if DebugAdminProbe.dryRun("merge duplicate \(context.remove.id) → \(keepId)") {
            DSMomentToast.show(L10n.t("تم الدمج", "Merged"), moment: .success)
            onClose()
            return
        }
        guard NetworkMonitor.shared.requireOnline() else { return }
        busy = true
        failure = nil
        Task {
            let result = await AdminMergeWrites.run(keep: keepId, remove: context.remove.id, dryRun: false)
            switch result {
            case .success:
                Log.info("[Merge] دُمج \(context.remove.id) في \(keepId)")
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
