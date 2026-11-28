import SwiftUI

/// مفتاحا ظهور زوج البنت من خارج العائلة وأبنائها منه (`spouse_shown` / `children_shown`، قرار المالك ٢٠٢٦-١١-٢٨) —
/// قسم واحد بمكانين:
/// - `.admin`: «الظهور للأعضاء» في تفاصيل البنت للإدارة (مالك، مدير، مراقب) — كتابة مباشرة (`WomenStore.setVisibilityAsAdmin`).
/// - `.child`: «الظهور في شجرة النساء» في مربّع «الأم» عند ابن البنت / بنت البنت وأمّه بلا حساب
///   (`set_mother_visibility` — «اجعله عند تعديل الأم»).
/// يُحفظ فوراً؛ النجاح لحظة «تم الحفظ»، والفشل يرجع المفتاح ويظهر السبب بالعربية.
/// - `.own`: الزوجة صاحبة الحساب وزوجها من خارج العائلة — داخل «الأسرة» بـ«الملف الشخصي» تحت خانة الزوج، بلا إطار قسم،
///   وسطر «عند الإخفاء…» تحته (`women_family_set_visibility` على عقدتها هي — العيّنة spouse2 القسم ٤).
struct WomanVisibilityAdminSection: View {
    enum Mode { case admin, child, own }

    let womanId: UUID
    var mode: Mode = .admin
    var onChanged: (() async -> Void)? = nil

    enum Item: CaseIterable { case spouse, children }

    @State private var shown: [Item: Bool] = [:]
    @State private var busy: Set<Item> = []
    @State private var errorText: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dsSection) private var section

    var body: some View {
        if mode == .own {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(Item.allCases, id: \.self) { row($0) }
                Text(MotherVisibilityLogic.ownNote)
                    .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let errorText {
                    DSNoteCard(errorText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                }
            }
            .onAppear(perform: load)
        } else {
            MemberCardSection(title: sectionTitle, icon: "eye.fill", fill: DS.Color.seaFill) {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(Item.allCases, id: \.self) { row($0) }
                    if let errorText {
                        DSNoteCard(errorText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    /// السطر تحت العنوان: «ظاهر للأعضاء/مخفي عن الأعضاء»، وللزوجة نصّ العيّنة
    private func line(_ i: Item, on: Bool) -> String {
        guard mode == .own else {
            return on ? L10n.t("ظاهر للأعضاء", "Shown to members") : L10n.t("مخفي عن الأعضاء", "Hidden from members")
        }
        return i == .spouse ? MotherVisibilityLogic.ownSpouseLine : MotherVisibilityLogic.ownChildrenLine
    }

    private var sectionTitle: String {
        mode == .admin ? L10n.t("الظهور للأعضاء", "Shown to members")
                       : L10n.t("الظهور في شجرة النساء", "Shown in the women's tree")
    }

    private func title(_ i: Item) -> String {
        switch (mode, i) {
        case (.admin, .spouse): return MotherVisibilityLogic.adminSpouseTitle
        case (.admin, .children): return MotherVisibilityLogic.adminChildrenTitle
        case (.child, .spouse): return MotherVisibilityLogic.childSpouseTitle
        case (.child, .children): return MotherVisibilityLogic.childChildrenTitle
        case (.own, .spouse): return MotherVisibilityLogic.ownSpouseTitle
        case (.own, .children): return MotherVisibilityLogic.ownChildrenTitle
        }
    }

    private func row(_ i: Item) -> some View {
        let on = shown[i] ?? false
        let tint = on ? DS.Color.success : DS.Color.textTertiary
        return Toggle(isOn: Binding(get: { shown[i] ?? false }, set: { save(i, $0) })) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: i == .spouse ? (mode == .admin ? "heart.fill" : "person.fill") : "person.2.fill")
                    .dsGlyph(DS.Glyph.md)
                    .foregroundColor(tint)
                    .frame(width: DS.Icon.row, height: DS.Icon.row)
                    .background(Circle().fill(tint.opacity(DS.Opacity.tintFill)))
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title(i))
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(line(i, on: on))
                        .dsFont(.caption)
                        .foregroundColor(mode == .own ? DS.Color.textTertiary : tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(DS.Color.toggleOn)
        .disabled(busy.contains(i))
        .opacity(busy.contains(i) ? DS.Opacity.disabled : 1)
        .animation(reduceMotion ? nil : DS.Anim.snappy, value: on)
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .memberCardInset()
        .accessibilityValue(on ? L10n.t("ظاهر", "Shown") : L10n.t("مخفي", "Hidden"))
    }

    private func load() {
        shown[.spouse] = WomenStore.spouseShownIds.contains(womanId)
        shown[.children] = WomenStore.childrenShownIds.contains(womanId)
    }

    private func save(_ i: Item, _ on: Bool) {
        guard !busy.contains(i), NetworkMonitor.shared.requireOnline() else { return }
        let before = shown[i] ?? false
        guard before != on else { return }
        shown[i] = on
        busy.insert(i)
        errorText = nil
        let spouse: Bool? = i == .spouse ? on : nil
        let children: Bool? = i == .children ? on : nil
        Task {
            do {
                switch mode {
                case .admin: try await WomenStore.setVisibilityAsAdmin(id: womanId, spouse: spouse, children: children)
                case .child: try await DaughterFamilyAPI.setMotherVisibility(motherId: womanId, spouse: spouse, children: children)
                case .own:
                    // نفس مسار عين الزوج السابقة (`women_family_set_visibility`، عقدتها فقط) — مفتاح واحد للحقل الواحد
                    try await DaughterFamilyAPI.setVisibility(spouse: spouse, children: children)
                    WomenStore.rememberVisibility(id: womanId, spouse: spouse, children: children)
                }
                busy.remove(i)
                DSMomentToast.show(L10n.t("تم الحفظ", "Saved"), moment: .success, section: section)
                NotificationCenter.default.post(name: .womenMembersChanged, object: nil)
                await onChanged?()
            } catch {
                busy.remove(i)
                shown[i] = before
                errorText = mode != .child ? WomenStore.failureMessage(error)
                    : ((error as? LocalizedError)?.errorDescription ?? MotherVisibilityLogic.errorMessage(hint: nil))
            }
        }
    }
}

/// الأم التي تظهر مفاتيحها لصاحب الحساب (من آخر جلب لشجرة النساء): بلا حساب، وأبوه أو زوجها من خارج العائلة — nil = لا مفاتيح.
/// الأم يجب أن تكون في الجلب (وإلا لا نعرف إن كان لها حساب).
@MainActor
enum MotherVisibilityTarget {
    static func motherId(fatherId: UUID?, motherId: UUID?) -> UUID? {
        guard WomenStore.visibilitySupported, let mid = motherId,
              let mother = WomenStore.cache.first(where: { $0.id == mid }) else { return nil }
        let show = MotherVisibilityLogic.childShowsToggles(
            motherId: mid, motherHasAccount: WomenStore.linkedUserByWoman[mid] != nil,
            fatherId: fatherId, motherHusbandId: mother.husbandId, outsideIds: WomenStore.outsideFamilyIds)
        return show ? mid : nil
    }
}

/// مربّع «الأم» لابن البنت / بنت البنت وأمّه بلا حساب: اسمها، ثم «الظهور في شجرة النساء» بالمفتاحين
/// (طلب المالك ٢٠٢٦-١١-٢٨ «شيل زر الخصوصية وخله عند تعديل الام»)
struct MotherVisibilityBox: View {
    let motherId: UUID
    let motherName: String
    var onChanged: (() async -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DSComposer(
            title: L10n.t("الأم", "Mother"),
            subtitle: motherName,
            icon: "person.fill",
            tint: DS.Color.female,
            actionTitle: "",
            showsAction: false,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { dismiss() }
        ) {
            WomanVisibilityAdminSection(womanId: motherId, mode: .child, onChanged: onChanged)
        }
    }
}
