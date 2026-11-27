import SwiftUI

// MARK: - مربّعات التعديل في كرت العضو v3 (الوحدة V3، `v3-boxes.png`) — نداءات السيرفر الموجودة فقط
//
// (أ) «الزوجات» / «الزوج»: القائمة بالسحب للترتيب (`WomenStore.reorderWives` ← `wife_order`)، «فك الربط» لكل صفّ بتأكيد
//     (`WomenStore.setHusbandId(…, nil)`)، و«ربط من العائلة» (`DSWifeFlowBox` ← `setHusbandId` / `WomenStore.addChild`
//     تحت أبيها؛ للمرأة منتقي الرجال ← `setHusbandId`) و«إضافة من خارج العائلة» (الرجل: `WomenStore.addWife`؛ المرأة:
//     `add_outside_husband` ← `DaughterSons.addOutsideHusband`).
// (ب) «تغيير الجنس»: ما يبقى وما يُحذف، والمانع (أبناء/زوجات مربوطون)، ثم `move_child_gender`
//     (`MemberViewModel.moveChildGender`) — رفض السيرفر يُعرض برسالته.
// (ج) «الأبناء والبنات»: قائمة واحدة (الأبناء `profiles.father_id`، البنات `women_members.parent_id`)، الترتيب بالسحب
//     (`updateChildrenOrder` للأبناء، `WomenStore.reorder` للبنات — كلٌّ بجدوله)، «فك الربط» للابن بتأكيد
//     (`updateMemberFather(…, nil)`)، و«إضافة ابن / بنت» (`AddSonByAdminSheet` ← `add_family_child`) و«ربط من الشجرة»
//     (`updateMemberFather`). فكّ ربط البنت لا نداء له ← معطّل «يحتاج تحديث السيرفر».
// (د) «صلته بالعائلة» (كانت «تصحيح النسب» — تسمية المالك): أربعة خيارات بشرح قصير؛ الحفظ بما له نداء فقط
//     (`AdminMemberCardLogic.lineageSave`): ربط الأب، `decide_lineage_request`، `approve_join_as_daughter_son` — وغيرها
//     معطّل «يحتاج تحديث السيرفر».
// (هـ) الإخفاء: تأكيد قبله (في الورقة) و«تراجع» بعده (`AdminMemberUndoBar`).
// تجربة الأدوار (`-tmpAdminRole`): كل كتابة تمرّ بـ`DebugAdminProbe.dryRun` (نجاح مصطنع).

/// مربّعات «العائلة» والجنس — بنوع مستقل (حارس المكدس)
enum AdminMemberFamilyBox: Identifiable {
    case spouses(FamilyMember), gender(FamilyMember), children(FamilyMember), lineage(FamilyMember)

    var id: String {
        switch self {
        case .spouses(let m): return "spouses-\(m.id)"
        case .gender(let m): return "genderMove-\(m.id)"
        case .children(let m): return "children-\(m.id)"
        case .lineage(let m): return "lineage-\(m.id)"
        }
    }

    var member: FamilyMember {
        switch self {
        case .spouses(let m), .gender(let m), .children(let m), .lineage(let m): return m
        }
    }
}

extension AdminMemberCardFamily {
    /// الحقائق من المخازن الحيّة — المربّع يعيد حسابها بعد كل حفظ
    @MainActor
    static func make(_ m: FamilyMember, isProfile: Bool, memberVM: MemberViewModel,
                     store: AdminMemberCardFamilyStore) -> AdminMemberCardFamily {
        AdminMemberCardFamily(member: m, isProfile: isProfile, all: memberVM.allMembers, byId: memberVM.member(byId:),
                              women: store.people, daughterSon: DaughterSonsIndex.shared.contains(m.id),
                              lineageRow: store.lineageRows[m.id])
    }
}

/// نصّ فشل الكتابة: رسالة السيرفر العربية إن وُجدت (حارس روابط العائلة…)، وإلا العامة
@MainActor
private func adminFamilyFailure(_ error: Error) -> String {
    if error is WomenWriteFailure { return WomenStore.failureMessage(error) }
    return AuthViewModel.serverMessage(error, fallback: WomenStore.failureMessage(error))
}

// MARK: - قائمة بالسحب (ترتيب)

/// قائمة أصلية في وضع الترتيب: مقبض السحب لكل صفّ (القارئ الصوتي: «نقل لأعلى/لأسفل» من القائمة نفسها). بلا تمرير خاص —
/// ارتفاعها بعدد صفوفها، والمربّع يتمرّر
struct AdminMemberReorderList<Row: View>: View {
    @Binding var items: [FamilyMember]
    var reorders: Bool = true
    @ViewBuilder let row: (FamilyMember) -> Row
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 60

    var body: some View {
        List {
            ForEach(items) { m in
                row(m)
                    .frame(minHeight: rowHeight)
                    .listRowInsets(EdgeInsets(top: 0, leading: DS.Spacing.xs, bottom: 0, trailing: DS.Spacing.xs))
                    .listRowBackground(Color.clear)
            }
            .onMove(perform: reorders ? { from, to in items.move(fromOffsets: from, toOffset: to) } : nil)
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(reorders ? .active : .inactive))
        .scrollDisabled(true)
        .frame(height: rowHeight * CGFloat(items.count) + DS.Spacing.xs)
    }
}

/// صفّ في قوائم المربّعات: الاسم وسطره، ثم «فك الربط» أحمر (أو معطّلاً بملاحظته)
private struct AdminMemberLinkRow: View {
    let name: String
    var note: String? = nil
    var tag: AdminMemberTag? = nil
    var unlinkEnabled: Bool = true
    var busy: Bool = false
    let unlink: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: name)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                if let tag { AdminMemberTagPill(tag: tag) }
                if let note {
                    Text(note)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            Spacer(minLength: DS.Spacing.sm)
            if busy {
                ProgressView().scaleEffect(DS.Spinner.chipScale)
            } else {
                Button(action: unlink) {
                    Text(L10n.t("فك الربط", "Unlink"))
                        .dsFont(.chip)
                        .foregroundColor(unlinkEnabled ? DS.Color.error : DS.Color.textTertiary)
                        .frame(minWidth: DS.Icon.tapTarget, minHeight: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!unlinkEnabled)
                .accessibilityLabel(Text(L10n.t("فك ربط \(name)", "Unlink \(name)")))
                .accessibilityHint(Text(unlinkEnabled ? L10n.t("يسأل أولاً", "Asks first")
                                                      : L10n.t("يحتاج تحديث السيرفر", "Needs a server update")))
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// ملاحظة «يحتاج تحديث السيرفر» لزرّ معطّل لا نداء له
struct AdminMemberNeedsServerNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
            Image(systemName: "server.rack")
                .dsGlyph(DS.Glyph.sm, weight: .medium)
                .accessibilityHidden(true)
            Text(L10n.t("يحتاج تحديث السيرفر: ", "Needs a server update: ") + text)
                .dsFont(.subtitle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(DS.Color.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - (أ) «الزوجات» / «الزوج»

struct AdminMemberSpousesBox: View {
    let member: FamilyMember
    let isProfile: Bool
    @EnvironmentObject private var memberVM: MemberViewModel
    @ObservedObject private var store = AdminMemberCardFamilyStore.shared
    @Environment(\.dismiss) private var dismiss

    private enum Step { case list, linkFamily, outside, pickHusband }
    @State private var step: Step = .list
    @State private var order: [FamilyMember] = []
    @State private var busy = false
    @State private var working: UUID?
    @State private var failure: String?
    @State private var unlinkTarget: FamilyMember?
    @State private var name = ""
    @State private var deceased = false
    @State private var search = ""

    private var family: AdminMemberCardFamily {
        AdminMemberCardFamily.make(member, isProfile: isProfile, memberVM: memberVM, store: store)
    }
    private var female: Bool { member.isFemale }
    private var displayName: String { member.shortFullName }
    private var orderChanged: Bool { order.map(\.id) != family.spouses.map(\.id) }

    var body: some View {
        Group {
            switch step {
            case .list: AnyView(listStep)
            case .linkFamily: AnyView(linkStep)
            case .outside: AnyView(outsideStep)
            case .pickHusband: AnyView(husbandPicker)
            }
        }
        .onAppear { order = family.spouses }
        .onChange(of: store.people.count) { _ in if !orderChanged || order.isEmpty { order = family.spouses } }
        .dsAlert(L10n.t("فك الربط؟", "Unlink?"), isPresented: Binding(get: { unlinkTarget != nil },
                                                                     set: { if !$0 { unlinkTarget = nil } })) {
            Button(L10n.t("فك الربط", "Unlink"), role: .destructive) {
                if let target = unlinkTarget { unlink(target) }
                unlinkTarget = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { unlinkTarget = nil }
        } message: {
            Text(L10n.t("«\(unlinkTarget?.shortFullName ?? "")» تبقى في الشجرة، ويُفكّ ربطها بـ«\(displayName)» فقط. يُسجَّل التغيير.",
                        "«\(unlinkTarget?.shortFullName ?? "")» stays in the tree; only the link to «\(displayName)» is removed. The change is logged."))
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: القائمة

    private var listStep: some View {
        let count = family.spouses.count
        let outsideReady = !female || (count == 0 && WomenStore.outsideFamilySupported && DaughterSons.isEnabled)
        return DSComposer(
            title: female ? L10n.t("الزوج", "Husband") : L10n.t("الزوجات", "Wives"),
            subtitle: [displayName, family.spousesSummary(female: female)].compactMap { $0 }.joined(separator: " · "),
            icon: "heart",
            tint: DS.Color.actionNavy,
            actionTitle: orderChanged ? L10n.t("حفظ الترتيب", "Save order") : L10n.t("تم", "Done"),
            showsCancel: false,
            canSubmit: !busy,
            isBusy: busy,
            hasUnsavedChanges: orderChanged,
            extraActions: [
                DSComposerAction(id: "link", title: L10n.t("ربط من العائلة", "Link from the family"), icon: "person.2",
                                 isEnabled: !busy && (!female || count == 0)) {
                    failure = nil; search = ""; step = female ? .pickHusband : .linkFamily
                },
                DSComposerAction(id: "outside", title: L10n.t("إضافة من خارج العائلة", "Add from outside"), icon: "plus",
                                 isEnabled: !busy && outsideReady) {
                    failure = nil; name = ""; deceased = false; step = .outside
                }
            ],
            onSubmit: { orderChanged ? saveOrder() : dismiss() },
            onCancel: { dismiss() }
        ) {
            if family.nodeId == nil {
                DSNoteCard(L10n.t("لا عقدة له في شجرة النساء بعد — الربط يبدأ من شجرة النساء.",
                                  "No node in the women's tree yet — start from the women's tree."), tint: DS.Color.warning)
            } else if order.isEmpty {
                DSNoteCard(female ? L10n.t("لا زوج مسجّل لها.", "No husband recorded.")
                                  : L10n.t("لا زوجات مسجّلات له.", "No wives recorded."),
                           icon: "heart", tint: DS.Color.textTertiary)
            } else {
                AdminMemberReorderList(items: $order, reorders: !female && order.count > 1) { spouse in
                    AdminMemberLinkRow(name: spouse.shortFullName, note: spouseNote(spouse),
                                       busy: working == spouse.id) { unlinkTarget = spouse }
                }
                if !female && order.count > 1 {
                    Text(L10n.t("اسحب للترتيب: الأولى تظهر أولاً في الشجرة. «فك الربط» يسأل قبل التنفيذ ويُسجَّل.",
                                "Drag to order: the first shows first in the tree. «Unlink» asks first and is logged."))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if female && count > 0 {
                Text(L10n.t("لربط زوج آخر فكّ ربط الحالي أولاً.", "Unlink the current husband before linking another."))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
            } else if female && !outsideReady {
                AdminMemberNeedsServerNote(text: L10n.t("«زوج من خارج العائلة» غير مفعّل على السيرفر.",
                                                        "«Husband from outside» isn't enabled on the server."))
            }
            if let failure {
                DSNoteCard(failure, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
    }

    private func spouseNote(_ s: FamilyMember) -> String? {
        if family.outsideIds.contains(s.id) { return L10n.t("من خارج العائلة", "From outside the family") }
        if let f = s.fatherId.flatMap(memberVM.member(byId:)) {
            return L10n.t("من العائلة · بنت \(f.firstName)", "From the family · daughter of \(f.firstName)")
        }
        return nil
    }

    // MARK: «ربط من العائلة» — الرجل: مسار الزوجة الواحد

    private var linkStep: some View {
        let node = family.nodeId ?? member.id
        return DSWifeFlowBox(
            mode: .direct, husbandId: node, husbandName: displayName, people: store.people,
            isLoading: !store.loaded, showsHidden: true, isBusy: busy, error: failure,
            onOutside: { failure = nil; name = ""; deceased = false; step = .outside },
            onLink: { daughter, _ in
                write("setHusbandId \(daughter.id) → \(node)") {
                    try await WomenStore.setHusbandId(womanId: daughter.id, husbandId: node)
                }
            },
            onAddUnderFather: { name, father in addUnderFather(name, father: father, node: node, deceased: false) },
            onCancel: { step = .list })
        .addsDeceased { name, father in addUnderFather(name, father: father, node: node, deceased: true) }
    }

    private func addUnderFather(_ name: String, father: FamilyMember, node: UUID, deceased: Bool) {
        let sort = (store.people.filter { $0.fatherId == father.id }.map(\.sortOrder).max() ?? -1) + 1
        let fatherFull = father.fullName
        write("women addChild wife under \(father.id) for \(node)") {
            try await WomenStore.addChild(parentId: father.id, name: name, sortOrder: sort, gender: "female",
                                          parentFullName: fatherFull, isDeceased: deceased, isMarried: true,
                                          husbandId: node)
        }
    }

    // MARK: «الزوج» من العائلة — منتقي الرجال

    private var husbandPicker: some View {
        let men = memberVM.allMembers.filter { !$0.isFemale && $0.role != .pending && $0.hasName && $0.id != member.id }
        return DSMemberPickerBox(
            title: L10n.t("ربط زوج من العائلة", "Link a husband from the family"),
            subtitle: displayName,
            icon: "person.2",
            candidates: men,
            search: $search,
            requiresSpecificQuery: true,
            listsAllWhenEmpty: false,
            onPick: { man in
                guard let node = family.nodeId else { return }
                write("setHusbandId \(node) → \(man.id)") {
                    try await WomenStore.setHusbandId(womanId: node, husbandId: man.id)
                }
            },
            onCancel: { step = .list })
    }

    // MARK: «إضافة من خارج العائلة»

    private var outsideStep: some View {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return DSComposer(
            title: female ? L10n.t("زوج من خارج العائلة", "Husband from outside") : L10n.t("زوجة من خارج العائلة", "Wife from outside"),
            subtitle: displayName,
            icon: "plus",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("إضافة", "Add"),
            canSubmit: !trimmed.isEmpty && !busy,
            isBusy: busy,
            hasUnsavedChanges: !trimmed.isEmpty,
            onSubmit: addOutside,
            onCancel: { step = .list }
        ) {
            DSComposerSection(title: L10n.t("الاسم كاملاً", "Full name"), icon: "textformat", tint: DS.Color.actionNavy) {
                TextField(L10n.t("الاسم", "Name"), text: $name)
                    .dsFieldFont(.fieldValue)
                    .textInputAutocapitalization(.words)
                    .padding(DS.Spacing.md)
                    .dsRowBox()
                Toggle(female ? L10n.t("متوفى", "Deceased") : L10n.t("متوفاة", "Deceased"), isOn: $deceased)
                    .dsFont(.body)
                    .tint(DS.Color.toggleOn)
            }
            if let failure {
                DSNoteCard(failure, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
    }

    private func addOutside() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let node = family.nodeId else { return }
        let dead = deceased
        if female {
            write("add_outside_husband \(node)") {
                try await DaughterSons.addOutsideHusband(womanId: node, name: trimmed, deceased: dead)
            }
        } else {
            write("women addWife \(node)") {
                try await WomenStore.addWife(husbandId: node, name: trimmed, isDeceased: dead, isMarried: true)
            }
        }
    }

    // MARK: الكتابة

    private func unlink(_ spouse: FamilyMember) {
        // الرجل: الزوجة تُفكّ عن زوجها · المرأة: يُفكّ زوجها عن عقدتها
        let womanId = female ? (family.nodeId ?? member.id) : spouse.id
        working = spouse.id
        write("setHusbandId \(womanId) → nil", stay: true) {
            try await WomenStore.setHusbandId(womanId: womanId, husbandId: nil)
        }
    }

    private func saveOrder() {
        let ids = order.map(\.id)
        write("reorderWives \(ids.count)", stay: true) { try await WomenStore.reorderWives(orderedIds: ids) }
    }

    /// كتابة واحدة: الدوّارة، ثم إعادة الجلب والرجوع للقائمة؛ الفشل برسالة السيرفر والمربّع كما هو
    private func write(_ label: String, stay: Bool = false, _ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        failure = nil
        if DebugAdminProbe.dryRun("member card spouses \(label)") {
            working = nil
            step = .list
            return
        }
        busy = true
        Task { @MainActor in
            do {
                try await work()
                await store.refresh(force: true)
                order = family.spouses
                busy = false
                working = nil
                step = .list
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                busy = false
                working = nil
                failure = adminFamilyFailure(error)
            }
        }
    }
}

// MARK: - (ب) «تغيير الجنس»

struct AdminMemberGenderMoveBox: View {
    let member: FamilyMember
    let isProfile: Bool
    @EnvironmentObject private var memberVM: MemberViewModel
    @ObservedObject private var store = AdminMemberCardFamilyStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var failure: String?

    private var toFemale: Bool { !member.isFemale }
    private var target: String { toFemale ? "female" : "male" }

    private var family: AdminMemberCardFamily {
        AdminMemberCardFamily.make(member, isProfile: isProfile, memberVM: memberVM, store: store)
    }

    /// ما يمنع النقل محلياً (السيرفر يرفضه أيضاً) — nil = لا مانع
    private var blocker: String? {
        let f = family
        if toFemale {
            guard member.fatherId != nil else {
                return L10n.t("لا أب له في الشجرة — اربطه بأبيه أولاً، فالبنت تُنقل تحت أبيها.",
                              "No father in the tree — link him first; a daughter moves under her father.")
            }
            let kids = f.sons.count + f.daughters.count
            if kids > 0 || !f.spouses.isEmpty {
                let what = [AdminMemberCardLogic.childrenSummary(sons: f.sons.count, daughters: f.daughters.count,
                                                                 arabic: L10n.isArabic),
                            f.spousesSummary(female: false)].compactMap { $0 }.joined(separator: L10n.t(" و", " and "))
                return L10n.t("له \(what) مربوطون: فكّ ربطهم أولاً، وإلا يرفض السيرفر النقل.",
                              "\(what) are linked: unlink them first, or the server refuses the move.")
            }
            return nil
        }
        if !f.spouses.isEmpty {
            return L10n.t("لها زوج مربوط: فكّ ربطه أولاً.", "She has a linked husband: unlink him first.")
        }
        let node = f.nodeId.flatMap(store.node)
        guard let pid = node?.fatherId ?? member.fatherId, memberVM.member(byId: pid) != nil else {
            return L10n.t("أبوها ليس في شجرة العائلة — الابن يُنقل تحت أبيه.",
                          "Her father isn't in the family tree — a son moves under his father.")
        }
        return nil
    }

    private var keeps: String {
        toFemale ? L10n.t("الاسم · الأب · تاريخا الميلاد والوفاة · الظهور · الترتيب",
                          "Name · father · birth and death dates · visibility · order")
                 : L10n.t("الاسم · الأب · تاريخا الميلاد والوفاة · الظهور · الأم",
                          "Name · father · birth and death dates · visibility · mother")
    }

    private var loses: String {
        toFemale ? L10n.t("الصورة · الحساب ورقم الهاتف · السيرة · الدور",
                          "Photo · account and phone · biography · role")
                 : L10n.t("لا شيء من بياناتها — تُنقل لشجرة العائلة ابناً تحت أبيه",
                          "Nothing — moves to the family tree as a son under his father")
    }

    var body: some View {
        DSComposer(
            title: toFemale ? L10n.t("تغيير الجنس إلى أنثى؟", "Change to female?") : L10n.t("تغيير الجنس إلى ذكر؟", "Change to male?"),
            subtitle: member.shortFullName,
            icon: "person",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("انقله", "Move"),
            actionIcon: "arrow.left.arrow.right",
            canSubmit: blocker == nil && !busy,
            isBusy: busy,
            onSubmit: move,
            onCancel: { dismiss() }
        ) {
            DSNoteCard(toFemale ? L10n.t("ينقله من شجرة الرجال إلى شجرة النساء، بنتاً تحت أبيه. لا رجوع تلقائي: الرجوع نقل جديد.",
                                         "Moves him from the men's tree to the women's tree as a daughter. No automatic undo: going back is a new move.")
                                : L10n.t("ينقلها من شجرة النساء إلى شجرة العائلة، ابناً تحت أبيه. لا رجوع تلقائي: الرجوع نقل جديد.",
                                         "Moves her to the family tree as a son under his father. No automatic undo: going back is a new move."),
                       icon: "exclamationmark.triangle.fill", tint: DS.Color.warning)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(L10n.t("يبقى", "Kept")).dsFont(.sectionTitle).foregroundColor(DS.Color.textPrimary)
                Text(keeps).dsFont(.subtitle).foregroundColor(DS.Color.success).fixedSize(horizontal: false, vertical: true)
                Text(L10n.t("يُحذف", "Removed")).dsFont(.sectionTitle).foregroundColor(DS.Color.textPrimary)
                    .padding(.top, DS.Spacing.xs)
                Text(loses).dsFont(.subtitle).foregroundColor(toFemale ? DS.Color.error : DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let blocker {
                DSNoteCard(blocker, icon: "link", tint: DS.Color.error)
            }
            if let failure {
                DSNoteCard(failure, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func move() {
        guard blocker == nil else { return }
        let childId = isProfile ? member.id : (family.nodeId ?? member.id)
        if DebugAdminProbe.dryRun("move_child_gender \(childId) → \(target)") { dismiss(); return }
        let motherId = family.mother?.id
        busy = true
        failure = nil
        Task { @MainActor in
            // السيرفر يحفظ الروابط ويرفض من له أبناء/زوجة (`family_links_protected`) — رسالته كما هي
            guard let newId = await memberVM.moveChildGender(childId: childId, toGender: target) else {
                busy = false
                failure = memberVM.errorMessage ?? L10n.t("تعذّر النقل. حاول مرة أخرى.", "Couldn't move. Try again.")
                memberVM.errorMessage = nil
                return
            }
            // النقل يُنشئ سجلاً جديداً بلا الأم — أعِدها (أفضل جهد، كما في شجرة النساء)
            if let motherId, newId != childId { try? await WomenStore.setMotherId(childId: newId, motherId: motherId) }
            await store.refresh(force: true)
            busy = false
            DSMomentToast.show(L10n.t("تم النقل", "Moved"), moment: .success)
            dismiss()
        }
    }
}

// MARK: - (ج) «الأبناء والبنات»

struct AdminMemberChildrenBox: View {
    let member: FamilyMember
    /// «إضافة ابن / بنت» — الورقة تغلق هذا المربّع وتفتح `AddSonByAdminSheet` (المسار الموجود)
    let addChild: () -> Void
    @EnvironmentObject private var memberVM: MemberViewModel
    @ObservedObject private var store = AdminMemberCardFamilyStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var order: [FamilyMember] = []
    @State private var busy = false
    @State private var working: UUID?
    @State private var failure: String?
    @State private var unlinkTarget: FamilyMember?
    @State private var picking = false
    @State private var search = ""

    private var family: AdminMemberCardFamily {
        AdminMemberCardFamily.make(member, isProfile: true, memberVM: memberVM, store: store)
    }
    private var current: [FamilyMember] { family.sons + family.daughters }
    private var sonIds: Set<UUID> { Set(family.sons.map(\.id)) }
    private var orderChanged: Bool { order.map(\.id) != current.map(\.id) }

    var body: some View {
        Group {
            if picking { AnyView(linkPicker) } else { AnyView(listStep) }
        }
        .onAppear { order = current }
        .dsAlert(L10n.t("فك الربط؟", "Unlink?"), isPresented: Binding(get: { unlinkTarget != nil },
                                                                     set: { if !$0 { unlinkTarget = nil } })) {
            Button(L10n.t("فك الربط", "Unlink"), role: .destructive) {
                if let son = unlinkTarget { unlink(son) }
                unlinkTarget = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { unlinkTarget = nil }
        } message: {
            Text(L10n.t("«\(unlinkTarget?.shortFullName ?? "")» يبقى في الشجرة بلا أب. يُسجَّل التغيير ويمكن ربطه من جديد.",
                        "«\(unlinkTarget?.shortFullName ?? "")» stays in the tree without a father. Logged; can be linked again."))
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private var listStep: some View {
        DSComposer(
            title: L10n.t("الأبناء والبنات", "Sons and daughters"),
            subtitle: [member.shortFullName, family.childrenSummary].compactMap { $0 }.joined(separator: " · "),
            icon: "person.2",
            tint: DS.Color.actionNavy,
            actionTitle: orderChanged ? L10n.t("حفظ الترتيب", "Save order") : L10n.t("تم", "Done"),
            showsCancel: false,
            canSubmit: !busy,
            isBusy: busy,
            hasUnsavedChanges: orderChanged,
            extraActions: [
                DSComposerAction(id: "add", title: L10n.t("إضافة ابن / بنت", "Add son / daughter"), icon: "plus",
                                 isEnabled: !busy) { addChild() },
                DSComposerAction(id: "link", title: L10n.t("ربط من الشجرة", "Link from the tree"), icon: "tree",
                                 isEnabled: !busy) { failure = nil; search = ""; picking = true }
            ],
            onSubmit: { orderChanged ? saveOrder() : dismiss() },
            onCancel: { dismiss() }
        ) {
            if order.isEmpty {
                DSNoteCard(L10n.t("لا أبناء ولا بنات مسجّلون له.", "No sons or daughters recorded."),
                           icon: "person.2", tint: DS.Color.textTertiary)
            } else {
                AdminMemberReorderList(items: $order, reorders: order.count > 1) { child in
                    let son = sonIds.contains(child.id)
                    AdminMemberLinkRow(name: child.firstName.isEmpty ? child.shortFullName : child.firstName,
                                       tag: AdminMemberTag(text: son ? L10n.t("ابن", "Son") : L10n.t("بنت", "Daughter"),
                                                           tone: son ? .neutral : .daughterSon),
                                       unlinkEnabled: son, busy: working == child.id) { unlinkTarget = child }
                }
                Text(L10n.t("اسحب للترتيب. الأبناء والبنات يُحفظ ترتيب كلٍّ منهم في شجرته.",
                            "Drag to order. Sons and daughters each keep their order in their own tree."))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if !family.daughters.isEmpty {
                    AdminMemberNeedsServerNote(text: L10n.t("«فك الربط» للبنت (لا نداء يفرّغ أبا البنت في شجرة النساء).",
                                                            "«Unlink» for a daughter (no call clears her father in the women's tree)."))
                }
            }
            if let failure {
                DSNoteCard(failure, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
    }

    /// «ربط من الشجرة»: رجل بلا أب في الشجرة (ليس هو ولا أحد آبائه) يصير ابناً له — `updateMemberFather`
    private var linkPicker: some View {
        var ancestors = Set<UUID>([member.id])
        var cur = member.fatherId
        for _ in 0..<300 { guard let c = cur, ancestors.insert(c).inserted else { break }; cur = memberVM.member(byId: c)?.fatherId }
        let candidates = memberVM.allMembers.filter {
            !$0.isFemale && $0.fatherId == nil && $0.role != .pending && $0.hasName && !ancestors.contains($0.id)
                && !DaughterSonsIndex.shared.contains($0.id)
        }
        return DSMemberPickerBox(
            title: L10n.t("ربط ابن من الشجرة", "Link a son from the tree"),
            subtitle: member.shortFullName,
            icon: "tree",
            candidates: candidates,
            search: $search,
            hintMessage: L10n.t("من لا أب له في الشجرة فقط.", "Only members without a father in the tree."),
            onPick: { son in
                write("updateMemberFather \(son.id) → \(member.id)") {
                    await memberVM.updateMemberFather(memberId: son.id, fatherId: member.id)
                }
            },
            onCancel: { picking = false })
    }

    private func unlink(_ son: FamilyMember) {
        working = son.id
        write("updateMemberFather \(son.id) → nil") {
            await memberVM.updateMemberFather(memberId: son.id, fatherId: nil)
        }
    }

    private func saveOrder() {
        let parts = AdminMemberCardLogic.partitionChildren(order) { sonIds.contains($0.id) }
        let sonsChanged = parts.sons.map(\.id) != family.sons.map(\.id)
        let daughtersChanged = parts.daughters.map(\.id) != family.daughters.map(\.id)
        let fatherId = member.id
        write("children order sons:\(sonsChanged) daughters:\(daughtersChanged)") {
            if sonsChanged { await memberVM.updateChildrenOrder(for: fatherId, newOrder: parts.sons) }
            if daughtersChanged { try await WomenStore.reorder(orderedIds: parts.daughters.map(\.id)) }
        }
    }

    private func write(_ label: String, _ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        failure = nil
        if DebugAdminProbe.dryRun("member card children \(label)") { working = nil; picking = false; return }
        busy = true
        memberVM.errorMessage = nil
        Task { @MainActor in
            do {
                try await work()
                if let message = memberVM.errorMessage {
                    memberVM.errorMessage = nil
                    throw WomenWriteFailure(message: message)
                }
                await store.refresh(force: true)
                await memberVM.fetchAllMembers(force: true)
                order = current
                busy = false
                working = nil
                picking = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                busy = false
                working = nil
                failure = adminFamilyFailure(error)
            }
        }
    }
}

// MARK: - (د) «صلته بالعائلة»

struct AdminMemberLineageBox: View {
    let member: FamilyMember
    let isProfile: Bool
    let branch: String?
    /// «من العائلة» لمن لا صلة له: الورقة تغلق المربّع وتفتح ربط الأب (`LinkFatherSheet`)
    let linkFather: () -> Void
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var adminRequestVM: AdminRequestViewModel
    @ObservedObject private var store = AdminMemberCardFamilyStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var choice: AdminMemberCardLogic.Lineage?
    @State private var busy = false
    @State private var failure: String?

    private typealias Lin = AdminMemberCardLogic.Lineage

    private var family: AdminMemberCardFamily {
        AdminMemberCardFamily.make(member, isProfile: isProfile, memberVM: memberVM, store: store)
    }

    private var pendingRequest: AdminRequest? {
        adminRequestVM.lineageRequests.first { $0.memberId == member.id && $0.status == ApprovalStatus.pending.rawValue }
    }

    private var save: AdminMemberCardLogic.LineageSave {
        guard let choice else { return .current }
        return AdminMemberCardLogic.lineageSave(choice: choice, current: family.lineage, isProfile: isProfile,
                                                hasPendingLineageRequest: pendingRequest != nil && authVM.canApproveTreeRequests,
                                                isPendingJoin: member.role == .pending, isMale: !member.isFemale)
    }

    private var actionTitle: String {
        switch save {
        case .linkFather: return L10n.t("اختر الأب", "Pick the father")
        case .decideRequest: return L10n.t("وافق على طلبه", "Approve the request")
        case .approveJoin: return L10n.t("اقبله ابن بنت", "Accept as daughter's son")
        case .current, .needsServer: return L10n.t("حفظ", "Save")
        }
    }

    var body: some View {
        DSComposer(
            title: L10n.t("صلته بالعائلة", "Relation to the family"),
            subtitle: member.shortFullName,
            icon: "tag",
            tint: DS.Color.actionNavy,
            actionTitle: actionTitle,
            canSubmit: !busy && (save == .linkFather || save == .decideRequest || save == .approveJoin),
            isBusy: busy,
            hasUnsavedChanges: choice != nil && choice != family.lineage,
            onSubmit: submit,
            onCancel: { dismiss() }
        ) {
            VStack(spacing: 0) {
                ForEach(Lin.allCases, id: \.self) { option in
                    optionRow(option)
                    if option != Lin.allCases.last { AdminRowDivider() }
                }
            }
            .dsCard()
            if save == .needsServer {
                AdminMemberNeedsServerNote(text: L10n.t("لا نداء على السيرفر يغيّر هذه الصلة مباشرة.",
                                                        "No server call changes this relation directly."))
            }
            Text(currentLine)
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let failure {
                DSNoteCard(failure, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
        .onAppear { choice = family.lineage }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// «الحالي: ابن بنت · اعتمده حسن · 20/11/2026»
    private var currentLine: String {
        let now = family.lineageTag(branch: branch) ?? AdminMemberCardLogic.notRecorded(arabic: L10n.isArabic)
        let by = family.lineageSetBy(byId: memberVM.member(byId:))
        return L10n.t("الحالي: ", "Now: ") + [now, by].compactMap { $0 }.joined(separator: " · ")
    }

    private func optionRow(_ option: Lin) -> some View {
        let selected = choice == option
        return Button { choice = option } label: {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .dsGlyph(DS.Glyph.xl, weight: .regular)
                    .foregroundColor(selected ? DS.Color.primary : DS.Color.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(AdminMemberCardFamily.title(option))
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(AdminMemberCardFamily.explanation(option))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if option == .daughterSon, selected { motherLine }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Spacing.sm)
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(AdminRowPressStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// «ابن بنت» يحتاج أمّاً: الحالية، أو أمّه كما في طلبه المعلّق
    @ViewBuilder
    private var motherLine: some View {
        let requested = pendingRequest.flatMap { LineageRequestDetails.parse($0.details) }
        let name = AdminMemberCardFamily.firstName(family.mother).map { $0 }
            ?? requested?.motherName ?? requested?.newMother?.name
        HStack(spacing: DS.Spacing.xs) {
            Text(L10n.t("الأم:", "Mother:")).dsFont(.chip)
            Text(verbatim: name ?? AdminMemberCardLogic.notRecorded(arabic: L10n.isArabic)).dsFont(.chip)
        }
        .foregroundColor(DS.Color.textSecondary)
        .padding(DS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).fill(DS.Color.cardBackgroundSoft))
        if pendingRequest != nil {
            Text(L10n.t("له طلب «الصلة بالعائلة» معلّق — الموافقة تُنشئ صلته بأمّه كما في الطلب.",
                        "A pending relation request — approving links him to his mother as requested."))
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func submit() {
        switch save {
        case .linkFather:
            linkFather()
        case .decideRequest:
            guard let request = pendingRequest else { return }
            run("decide_lineage_request \(request.id)") {
                try await DaughterSons.decide(requestId: request.id, approve: true, reason: nil)
                await adminRequestVM.fetchPolicyRequests()
            }
        case .approveJoin:
            let id = member.id
            run("approve_join_as_daughter_son \(id)") {
                try await DaughterSons.approveJoin(memberId: id)
                await DaughterSonsIndex.shared.refresh(force: true)
            }
        case .current, .needsServer:
            break
        }
    }

    private func run(_ label: String, _ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        if DebugAdminProbe.dryRun("member card lineage \(label)") { dismiss(); return }
        busy = true
        failure = nil
        Task { @MainActor in
            do {
                try await work()
                await store.refreshLineage(member.id)
                await store.refresh(force: true)
                await memberVM.fetchAllMembers(force: true)
                busy = false
                DSMomentToast.show(L10n.t("تم الحفظ", "Saved"), moment: .success)
                dismiss()
            } catch {
                busy = false
                failure = DaughterSons.message(error)
            }
        }
    }
}

// MARK: - (هـ) «تراجع» بعد الإخفاء

/// كبسولة كحلية أسفل الورقة: «أُخفي من الشجرة · تراجع» لثوانٍ — «تراجع» يُظهره بالنداء نفسه
struct AdminMemberUndoBar: View {
    let text: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Text(text)
                .dsFont(.body)
                .foregroundColor(DS.Color.textOnPrimary)
                .lineLimit(2)
            Spacer(minLength: DS.Spacing.sm)
            Button(action: undo) {
                Text(L10n.t("تراجع", "Undo"))
                    .dsFont(.button)
                    .foregroundColor(DS.Color.accentLight)
                    .frame(minWidth: DS.Icon.tapTarget, minHeight: DS.Icon.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DSPressStyle())
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
        .background(Capsule().fill(DS.Color.primaryFill))
        .padding(.horizontal, DS.Spacing.lg)
        .accessibilityElement(children: .contain)
    }
}
