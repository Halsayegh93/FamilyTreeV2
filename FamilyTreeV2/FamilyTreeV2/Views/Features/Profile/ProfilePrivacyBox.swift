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

    /// `motherSpouse`/`motherChildren`: ابن البنت / بنت البنت وأمّه بلا حساب (قرار المالك ٢٠٢٦-١١-٢٨) —
    /// «ظهور الوالد بجانب الوالدة» و«ظهور الأبناء تحت الوالدة» على عقدة أمّه (`set_mother_visibility`)
    enum Item: CaseIterable { case phone, photo, birth, tree, spouse, motherSpouse, motherChildren }

    @State private var shown: [Item: Bool] = [:]
    @State private var busy: Set<Item> = []
    @State private var failedText: String?
    /// أمّ صاحب الحساب في شجرة النساء حين تظهر مفاتيحها (بلا حساب، وأبوه من خارج العائلة) — nil = لا مفاتيح
    @State private var motherId: UUID?

    private var items: [Item] {
        var out: [Item] = [.phone, .photo, .birth]
        if let node = treeNode {
            out.append(.tree)
            if node.husbandId != nil { out.append(.spouse) }
        }
        if motherId != nil { out += [.motherSpouse, .motherChildren] }
        return out
    }

    /// الأصل لكل مفتاح قبل القراءة: الخصوصية الشخصية ظاهرة، والزوج والوالدة مخفيّان (null على السيرفر)
    private func fallback(_ i: Item) -> Bool { ![.spouse, .motherSpouse, .motherChildren].contains(i) }

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
                if let failedText {
                    DSNoteCard(failedText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                }
            }
        }
        .onAppear(perform: load)
        .task { await loadMother() }
    }

    private func title(_ i: Item) -> String {
        switch i {
        case .phone: return L10n.t("رقم الهاتف", "Phone number")
        case .photo: return L10n.t("الصورة الشخصية", "Profile photo")
        case .birth: return L10n.t("تاريخ الميلاد", "Birth date")
        case .tree: return L10n.t("الظهور في الشجرة", "Shown in the tree")
        case .spouse: return L10n.t("ظهور الزوج", "Husband shown")
        case .motherSpouse: return MotherVisibilityLogic.childSpouseTitle
        case .motherChildren: return MotherVisibilityLogic.childChildrenTitle
        }
    }

    private func icon(_ i: Item) -> String {
        switch i {
        case .phone: return "phone.fill"
        case .photo: return "person.crop.circle.fill"
        case .birth: return "calendar"
        case .tree: return "tree.fill"
        case .spouse: return "heart.fill"
        case .motherSpouse: return "person.fill"
        case .motherChildren: return "person.2.fill"
        }
    }

    /// مربّع بالمنتصف: أيقونة بلون الحالة، الاسم، ثم «ظاهر/مخفي» بعين — الضغط على المربّع كله يبدّل
    private func tile(_ i: Item) -> some View {
        let on = shown[i] ?? fallback(i)
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
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
        resolveMother()
    }

    /// عقدة صاحب الحساب وأمّه من آخر جلب لشجرة النساء — الأم بلا حساب وأبوه (أو زوجها) من خارج العائلة
    private func resolveMother() {
        guard WomenStore.visibilitySupported, let me = authVM.currentUser?.id else { motherId = nil; return }
        let rows = WomenStore.cache
        let mine = treeNode ?? rows.first { $0.id == me } ?? WomenStore.node(forAccount: me)
        guard let mine, let mid = mine.motherId, let mother = rows.first(where: { $0.id == mid }) else {
            motherId = nil; return
        }
        let show = MotherVisibilityLogic.childShowsToggles(
            motherId: mid, motherHasAccount: WomenStore.linkedUserByWoman[mid] != nil,
            fatherId: mine.fatherId, motherHusbandId: mother.husbandId, outsideIds: WomenStore.outsideFamilyIds)
        motherId = show ? mid : nil
        if show {
            shown[.motherSpouse] = WomenStore.spouseShownIds.contains(mid)
            shown[.motherChildren] = WomenStore.childrenShownIds.contains(mid)
        }
    }

    /// شجرة النساء لم تُجلب بعد (حساب الرجل لا يجلبها في «حسابي») — جلب واحد ثم إعادة الحساب
    private func loadMother() async {
        guard WomenStore.cache.isEmpty else { return }
        _ = try? await WomenStore.fetch()
        resolveMother()
    }

    private func save(_ i: Item, _ on: Bool) {
        guard !busy.contains(i), NetworkMonitor.shared.requireOnline() else { return }
        let before = shown[i] ?? fallback(i)
        shown[i] = on
        busy.insert(i)
        failedText = nil
        Task {
            var ok = true
            var message: String?
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
            case .motherSpouse, .motherChildren:
                guard let mid = motherId else { ok = false; break }
                do {
                    if i == .motherSpouse { try await DaughterFamilyAPI.setMotherVisibility(motherId: mid, spouse: on) }
                    else { try await DaughterFamilyAPI.setMotherVisibility(motherId: mid, children: on) }
                    NotificationCenter.default.post(name: .womenMembersChanged, object: nil)
                } catch {
                    ok = false
                    message = (error as? LocalizedError)?.errorDescription
                }
            }
            busy.remove(i)
            if !ok {
                shown[i] = before
                failedText = message ?? L10n.t("تعذّر الحفظ، يرجى المحاولة مرة أخرى.", "Couldn't save, please try again.")
            }
        }
    }
}
