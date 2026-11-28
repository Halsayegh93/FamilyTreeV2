import SwiftUI

/// «خصوصيتي» من «حسابي» — مربّع مختصر بالمنتصف (طلب المالك ٢٠٢٦-١١-٠٩: «مختصر و واضح و بسيط ومافي كلام وايد»).
/// صفّ لكل شي: أيقونة · الاسم · «ظاهر/مخفي» · مفتاح (شغّال = ظاهر). يُحفظ فوراً بنفس نداءات «الإعدادات ← الخصوصية»،
/// والتفاصيل الكاملة (المحظورون، طلبات بياناتي…) تبقى هناك.
struct ProfilePrivacyBox: View {
    /// عقدة البنت في شجرة النساء — تضيف «اسمي في الشجرة» (nil للرجال)
    var treeNode: FamilyMember?
    var onTreeChanged: () -> Void = {}

    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss

    enum Item: CaseIterable { case phone, photo, birth, tree, spouse }

    @State private var shown: [Item: Bool] = [:]
    @State private var busy: Set<Item> = []
    @State private var failed = false

    private var items: [Item] {
        guard let node = treeNode else { return [.phone, .photo, .birth] }
        return node.husbandId == nil ? [.phone, .photo, .birth, .tree] : Item.allCases
    }

    var body: some View {
        DSComposer(
            title: L10n.t("الخصوصية", "Privacy"),
            subtitle: L10n.t("ما يظهر للأعضاء", "What members see"),
            icon: "lock.fill",
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { dismiss() }
        ) {
            VStack(spacing: DS.Spacing.sm) {
                // مربّعات جنب بعض بنفس المقاس — صفّان صفّان، والأخير الفرد بعرض الصف (طلب المالك «منظمة اكثر»)
                let rows = stride(from: 0, to: items.count, by: 2).map { Array(items[$0 ..< min($0 + 2, items.count)]) }
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(rows[r], id: \.self) { tile($0) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                if failed {
                    DSNoteCard(L10n.t("تعذّر الحفظ، يرجى المحاولة مرة أخرى.", "Couldn't save, please try again."),
                               icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func title(_ i: Item) -> String {
        switch i {
        case .phone: return L10n.t("رقم الهاتف", "Phone number")
        case .photo: return L10n.t("الصورة الشخصية", "Profile photo")
        case .birth: return L10n.t("تاريخ الميلاد", "Birth date")
        case .tree: return L10n.t("الظهور في الشجرة", "Shown in the tree")
        case .spouse: return L10n.t("ظهور الزوج", "Husband shown")
        }
    }

    private func icon(_ i: Item) -> String {
        switch i {
        case .phone: return "phone.fill"
        case .photo: return "person.crop.circle.fill"
        case .birth: return "calendar"
        case .tree: return "tree.fill"
        case .spouse: return "heart.fill"
        }
    }

    /// مربّع بالمنتصف: أيقونة بلون الحالة، الاسم، ثم «ظاهر/مخفي» بعين — الضغط على المربّع كله يبدّل
    private func tile(_ i: Item) -> some View {
        let on = shown[i] ?? (i != .spouse)
        let tint = on ? DS.Color.success : DS.Color.textTertiary
        let status = on ? L10n.t("ظاهر", "Shown") : L10n.t("مخفي", "Hidden")
        return Button { save(i, !on) } label: {
            VStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon(i))
                    .dsGlyph(DS.Glyph.md)
                    .foregroundColor(tint)
                    .frame(width: DS.Icon.row, height: DS.Icon.row)
                    .background(Circle().fill(tint.opacity(DS.Opacity.tintFill)))
                Text(title(i))
                    .dsFont(.callout)
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: DS.Spacing.xxs) {
                    Image(systemName: on ? "eye.fill" : "eye.slash.fill").dsGlyph(DS.Glyph.xs)
                    Text(status).dsFont(.micro)
                }
                .foregroundColor(tint)
                .padding(.horizontal, DS.Spacing.sm).padding(.vertical, DS.Spacing.xxs)
                .background(Capsule().fill(tint.opacity(DS.Opacity.tintFill)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, DS.Spacing.sm)
            .padding(.horizontal, DS.Spacing.xs)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(on ? tint.opacity(DS.Opacity.tintStroke) : .clear, lineWidth: DS.Border.width))
            .opacity(busy.contains(i) ? DS.Opacity.disabled : 1)
        }
        .buttonStyle(DSPressStyle())
        .disabled(busy.contains(i))
        .accessibilityLabel(title(i))
        .accessibilityValue(status)
        .accessibilityHint(on ? L10n.t("اضغط للإخفاء", "Tap to hide") : L10n.t("اضغط للإظهار", "Tap to show"))
    }


    private func load() {
        let u = authVM.currentUser
        shown[.phone] = !(u?.isPhoneHidden ?? false)
        shown[.photo] = !(u?.isPhotoHidden ?? false)
        shown[.birth] = !(u?.isBirthDateHidden ?? false)
        shown[.tree] = !(treeNode?.isHiddenFromTree ?? false)
        shown[.spouse] = treeNode.map { WomenStore.spouseShownIds.contains($0.id) } ?? false
    }

    private func save(_ i: Item, _ on: Bool) {
        guard !busy.contains(i), NetworkMonitor.shared.requireOnline() else { return }
        let before = shown[i] ?? (i != .spouse)
        shown[i] = on
        busy.insert(i)
        failed = false
        Task {
            var ok = true
            switch i {
            case .phone: ok = await memberVM.updatePhoneHidden(!on)
            case .photo: ok = await memberVM.updatePhotoHidden(!on)
            case .birth: ok = await memberVM.updateBirthDateHidden(!on)
            case .tree, .spouse:
                if WomenStore.visibilitySupported {
                    do {
                        if i == .tree { try await DaughterFamilyAPI.setVisibility(me: on) }
                        else { try await DaughterFamilyAPI.setVisibility(spouse: on) }
                        onTreeChanged()
                    } catch { ok = false }
                }
            }
            busy.remove(i)
            if !ok { shown[i] = before; failed = true }
        }
    }
}
