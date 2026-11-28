import SwiftUI

/// «الظهور للأعضاء» في تفاصيل البنت التي زوجها من خارج العائلة — للإدارة (مالك، مدير، مراقب؛ قرار المالك ٢٠٢٦-١١-٢٨).
/// مفتاحا «ظهور الزوج» (`spouse_shown`) و«ظهور الأبناء» (`children_shown`) — أغلب الأمهات بلا حساب، فالإدارة تقرّر عنهن.
/// يُحفظ فوراً (`WomenStore.setVisibilityAsAdmin`)؛ النجاح لحظة «تم الحفظ»، والفشل يرجع المفتاح ويظهر السبب.
struct WomanVisibilityAdminSection: View {
    let womanId: UUID
    var onChanged: (() async -> Void)? = nil

    enum Item: CaseIterable { case spouse, children }

    @State private var shown: [Item: Bool] = [:]
    @State private var busy: Set<Item> = []
    @State private var errorText: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dsSection) private var section

    var body: some View {
        MemberCardSection(title: L10n.t("الظهور للأعضاء", "Shown to members"), icon: "eye.fill", fill: DS.Color.seaFill) {
            VStack(spacing: DS.Spacing.sm) {
                ForEach(Item.allCases, id: \.self) { row($0) }
                if let errorText {
                    DSNoteCard(errorText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func title(_ i: Item) -> String {
        i == .spouse ? MotherVisibilityLogic.adminSpouseTitle : MotherVisibilityLogic.adminChildrenTitle
    }

    private func row(_ i: Item) -> some View {
        let on = shown[i] ?? false
        let tint = on ? DS.Color.success : DS.Color.textTertiary
        return Toggle(isOn: Binding(get: { shown[i] ?? false }, set: { save(i, $0) })) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: i == .spouse ? "heart.fill" : "person.2.fill")
                    .dsGlyph(DS.Glyph.md)
                    .foregroundColor(tint)
                    .frame(width: DS.Icon.row, height: DS.Icon.row)
                    .background(Circle().fill(tint.opacity(DS.Opacity.tintFill)))
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title(i))
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(on ? L10n.t("ظاهر للأعضاء", "Shown to members") : L10n.t("مخفي عن الأعضاء", "Hidden from members"))
                        .dsFont(.caption)
                        .foregroundColor(tint)
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
        Task {
            do {
                if i == .spouse { try await WomenStore.setVisibilityAsAdmin(id: womanId, spouse: on) }
                else { try await WomenStore.setVisibilityAsAdmin(id: womanId, children: on) }
                busy.remove(i)
                DSMomentToast.show(L10n.t("تم الحفظ", "Saved"), moment: .success, section: section)
                await onChanged?()
            } catch {
                busy.remove(i)
                shown[i] = before
                errorText = WomenStore.failureMessage(error)
            }
        }
    }
}
