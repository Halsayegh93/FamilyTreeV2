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
//     (`updateChildrenOrder` للأبناء، `WomenStore.reorder` للبنات — كلٌّ بجدوله)، «فك الربط» للابن بلا أبناء بتأكيد صادق
//     (`updateMemberFather(…, nil)` — يخرج من شجرة العائلة ويصير اسمه الكامل اسمه الأول)، ومن له أبناء معطّل («الأب ←
//     تغيير» في ورقته)، و«إضافة ابن / بنت» (`AddSonByAdminSheet` ← `add_family_child`) و«ربط من الشجرة»
//     (`updateMemberFather`). فشل السيرفر يظهر برسالته (`errorMessage`). فكّ ربط البنت لا نداء له ← «فك ربط البنت غير متاح بعد.»
// (و) «الأم»: منتقي بنات العائلة (`DSWifeFlowBox(relation: .mother)`) ← `WomenStore.setMotherId` (ومعه زوجاً لأبيه إن
//     لم يكن لها زوج) — نفس مسار شجرة النساء للإدارة.
// (د) «صلته بالعائلة» (كانت «تصحيح النسب» — تسمية المالك): أربعة خيارات بشرح قصير؛ الحفظ بما له نداء فقط
//     (`AdminMemberCardLogic.lineageSave`): ربط الأب، `decide_lineage_request`، `approve_join_as_daughter_son` — وغيرها
//     معطّل «يحتاج تحديث السيرفر».
// (هـ) الإخفاء: تأكيد قبله (في الورقة) و«تراجع» بعده (`AdminMemberUndoBar`).
// تجربة الأدوار (`-tmpAdminRole`): كل كتابة تمرّ بـ`DebugAdminProbe.dryRun` (نجاح مصطنع).

/// مربّعات «العائلة» والجنس — بنوع مستقل (حارس المكدس)
enum AdminMemberFamilyBox: Identifiable {
    case spouses(FamilyMember), gender(FamilyMember), children(FamilyMember), lineage(FamilyMember)
    /// م٤: «الأم» — منتقي الأم
    case mother(FamilyMember)

    var id: String {
        switch self {
        case .spouses(let m): return "spouses-\(m.id)"
        case .gender(let m): return "genderMove-\(m.id)"
        case .children(let m): return "children-\(m.id)"
        case .lineage(let m): return "lineage-\(m.id)"
        case .mother(let m): return "mother-\(m.id)"
        }
    }

    var member: FamilyMember {
        switch self {
        case .spouses(let m), .gender(let m), .children(let m), .lineage(let m), .mother(let m): return m
        }
    }
}

extension AdminMemberCardFamily {
    /// الحقائق من المخازن الحيّة — المربّع يعيد حسابها بعد كل حفظ
    @MainActor
    static func make(_ m: FamilyMember, isProfile: Bool, memberVM: MemberViewModel,
                     store: AdminMemberCardFamilyStore) -> AdminMemberCardFamily {
        let daughterSon = DaughterSonsIndex.shared.contains(m.id)
        return AdminMemberCardFamily(member: m, isProfile: isProfile, all: memberVM.allMembers, byId: memberVM.member(byId:),
                                     women: store.people, daughterSon: daughterSon,
                                     lineageRow: store.lineageRows[m.id],
                                     known: AdminMemberCardLogic.familyKnown(storeLoaded: store.loaded, daughterSon: daughterSon,
                                                                             lineageChecked: store.lineageChecked.contains(m.id)))
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
/// ارتفاعها مجموع صفوفها المقيسة (ت٣: مع الخط الكبير يطول الصفّ — الاسم والشارة — فكان آخر صفّ يُقصّ)، والمربّع يتمرّر
struct AdminMemberReorderList<Row: View>: View {
    @Binding var items: [FamilyMember]
    var reorders: Bool = true
    @ViewBuilder let row: (FamilyMember) -> Row
    /// تقدير الصفّ قبل قياسه — يكبر مع الخط
    @ScaledMetric(relativeTo: .subheadline) private var estimate: CGFloat = DS.Hub.memberReorderRow
    @State private var heights: [UUID: CGFloat] = [:]

    private var total: CGFloat {
        items.reduce(0) { sum, m in sum + max(heights[m.id] ?? estimate, estimate) } + DS.Spacing.xs
    }

    var body: some View {
        List {
            ForEach(items) { m in
                row(m)
                    .frame(minHeight: estimate)
                    .background(GeometryReader { g in
                        Color.clear
                            .onAppear { heights[m.id] = g.size.height }
                            .onChange(of: g.size.height) { heights[m.id] = $0 }
                    })
                    .listRowInsets(EdgeInsets(top: 0, leading: DS.Spacing.xs, bottom: 0, trailing: DS.Spacing.xs))
                    .listRowBackground(Color.clear)
            }
            .onMove(perform: reorders ? { from, to in items.move(fromOffsets: from, toOffset: to) } : nil)
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(reorders ? .active : .inactive))
        .scrollDisabled(true)
        .frame(height: total)
    }
}

/// صفّ في قوائم المربّعات: الاسم وسطره، ثم «فك الربط» أحمر (أو معطّلاً بملاحظته)
private struct AdminMemberLinkRow: View {
    let name: String
    var note: String? = nil
    var tag: AdminMemberTag? = nil
    var unlinkEnabled: Bool = true
    /// للقارئ الصوتي: لماذا «فك الربط» معطّل
    var disabledHint: String = L10n.t("يحتاج تحديث السيرفر", "Needs a server update")
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
                        .minimumScaleFactor(DSBox.buttonLabelMinScale)
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
                .accessibilityHint(Text(unlinkEnabled ? L10n.t("يسأل أولاً", "Asks first") : disabledHint))
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
    /// م٥: الزوج المختار ينتظر التأكيد قبل `setHusbandId`
    @State private var husbandTarget: FamilyMember?
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
            // م١٠: فكّ زوج المرأة — «يبقى… ربطه»
            Text(female
                 ? L10n.t("«\(unlinkTarget?.shortFullName ?? "")» يبقى في الشجرة، ويُفكّ ربطه بـ«\(displayName)» فقط. يُسجَّل التغيير.",
                          "«\(unlinkTarget?.shortFullName ?? "")» stays in the tree; only the link to «\(displayName)» is removed. The change is logged.")
                 : L10n.t("«\(unlinkTarget?.shortFullName ?? "")» تبقى في الشجرة، ويُفكّ ربطها بـ«\(displayName)» فقط. يُسجَّل التغيير.",
                          "«\(unlinkTarget?.shortFullName ?? "")» stays in the tree; only the link to «\(displayName)» is removed. The change is logged."))
        }
        .dsAlert(L10n.t("ربط زوج؟", "Link a husband?"), isPresented: Binding(get: { husbandTarget != nil },
                                                                          set: { if !$0 { husbandTarget = nil } })) {
            Button(L10n.t("اربطه", "Link")) {
                if let man = husbandTarget { linkHusband(man) }
                husbandTarget = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { husbandTarget = nil }
        } message: {
            // ت-ج١: يبدأ بفعل — نصّ من متغيّرين
            Text(verbatim: AdminMemberCardLogic.husbandLinkMessage(husband: husbandTarget?.shortFullName ?? "",
                                                                   wife: displayName, arabic: L10n.isArabic))
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: القائمة

    private var listStep: some View {
        let count = family.spouses.count
        let outsideReady = !female || (count == 0 && WomenStore.outsideFamilySupported && DaughterSons.isEnabled)
        return DSComposer(
            title: female ? L10n.t("الزوج", "Husband") : L10n.t("الزوجات", "Wives"),
            subtitle: AdminMemberCardLogic.boxSubtitle([displayName, family.spousesSummary(female: female)]),
            icon: "heart",
            tint: DS.Color.actionNavy,
            actionTitle: orderChanged ? L10n.t("حفظ الترتيب", "Save order") : L10n.t("تم", "Done"),
            showsCancel: false,
            canSubmit: !busy,
            isBusy: busy,
            hasUnsavedChanges: orderChanged,
            // م٧: الثانويان بإطار ذهبي و«تم» وحده ممتلئ — يتجاوران ما اتّسع النصّان كاملين، وإلا صفّ لكلٍّ
            extraActions: [
                DSComposerAction(id: "link", title: L10n.t("ربط من العائلة", "Link from the family"), icon: "person.2",
                                 isEnabled: !busy && (!female || count == 0), style: .outlined) {
                    failure = nil; search = ""; step = female ? .pickHusband : .linkFamily
                },
                DSComposerAction(id: "outside", title: L10n.t("إضافة من خارج العائلة", "Add from outside"), icon: "plus",
                                 isEnabled: !busy && outsideReady, style: .outlined) {
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

    // MARK: «الزوج» من العائلة — منتقي الرجال (م٥: بلا محارمها ولا القُصّر ولا المتوفين، وتأكيد قبل الربط)

    private var husbandPicker: some View {
        let f = family
        let node = f.nodeId ?? member.id
        // أب كل رجل في شجرة العائلة، وأبناؤها (عقدتها أمّهم في شجرة النساء أو في ملفاتهم)
        let fatherOf = Dictionary(memberVM.allMembers.compactMap { m in m.fatherId.map { (m.id, $0) } },
                                  uniquingKeysWith: { a, _ in a })
        let sons = Set(store.people.filter { !$0.isFemale && ($0.motherId == node || $0.motherId == member.id) }.map(\.id)
                       + memberVM.allMembers.filter { $0.motherId == node || $0.motherId == member.id }.map(\.id))
        // ت-ج٢: ومن جهة أمّها — أبو أمّها (أمّها من بنات العائلة) وآباؤه وأخوالها
        let blocked = AdminMemberCardLogic.husbandBlocked(fatherId: f.father?.id ?? member.fatherId,
                                                          motherFatherId: f.mother?.fatherId, sonIds: Array(sons),
                                                          fatherOf: fatherOf)
        let minAge = WifeCandidateRules.minimumAge
        let men = memberVM.allMembers.filter {
            $0.id != member.id && !blocked.contains($0.id)
                && AdminMemberCardLogic.husbandEligible(isMale: !$0.isFemale, isPending: $0.role == .pending,
                                                       hasName: $0.hasName, isDeceased: $0.isDeceased == true,
                                                       age: WifeCandidateRules.age($0), minAge: minAge)
        }
        return DSMemberPickerBox(
            title: L10n.t("ربط زوج من العائلة", "Link a husband from the family"),
            subtitle: displayName,
            icon: "person.2",
            candidates: men,
            search: $search,
            requiresSpecificQuery: true,
            listsAllWhenEmpty: false,
            hintMessage: L10n.t("لا يظهر محارمها ولا من دون \(minAge) سنة ولا المتوفون.",
                                "Her close relatives, men under \(minAge) and the deceased aren't listed."),
            onPick: { man in husbandTarget = man },
            onCancel: { step = .list })
    }

    private func linkHusband(_ man: FamilyMember) {
        guard let node = family.nodeId else { return }
        write("setHusbandId \(node) → \(man.id)") {
            try await WomenStore.setHusbandId(womanId: node, husbandId: man.id)
        }
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
    /// م٦: نُقل — القديم ← الجديد (الكرت يتبع السجل الجديد بدل «العضو غير موجود»)
    let onMoved: (UUID, UUID) -> Void
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var authVM: AuthViewModel
    @ObservedObject private var store = AdminMemberCardFamilyStore.shared
    @ObservedObject private var accounts = AdminAccountsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var failure: String?
    /// نُقل لكن لم تُربط الأم — المربّع يبقى بسطره و«تم»
    @State private var motherFailed = false
    /// م-ج٢: جواب السيرفر `profile_has_login` — nil حتى يصل (أو إن فشل)
    @State private var serverLogin: Bool?
    @State private var checkingLogin = true

    private var toFemale: Bool { !member.isFemale }
    private var target: String { toFemale ? "female" : "male" }

    private var family: AdminMemberCardFamily {
        AdminMemberCardFamily.make(member, isProfile: isProfile, memberVM: memberVM, store: store)
    }

    /// ح١: له حساب في التطبيق؟ (nil = لا يُعرف بعد) — السيرفر لا يمنع، والنقل إلى أنثى يحذف ملفه.
    /// م-ج٢: الحكم جواب `profile_has_login` للملف؛ عقدة شجرة النساء بلا ملف حسابها رابطها (`linked_user_id`) وحده
    private var account: Bool? {
        let node = family.nodeId
        return AdminMemberCardLogic.appAccount(
            serverLogin: isProfile ? serverLogin : false,
            role: member.role.rawValue, isViewer: member.id == authVM.currentUser?.id, frozen: member.status == .frozen,
            linkedLogin: node.flatMap { WomenStore.linkedUserByWoman[$0] } != nil,
            inAccountsStore: accounts.info(member.id) != nil)
    }

    /// ما يمنع النقل محلياً — nil = لا مانع
    private var block: AdminMemberCardLogic.GenderMoveBlock? {
        let f = family
        let node = f.nodeId.flatMap(store.node)
        let fatherId = node?.fatherId ?? member.fatherId
        return AdminMemberCardLogic.genderMoveBlock(
            toFemale: toFemale, account: account, checking: checkingLogin, hasFather: member.fatherId != nil,
            sons: f.sons.count, daughters: f.daughters.count, wives: toFemale ? f.spouses.count : 0,
            hasHusband: !toFemale && !f.spouses.isEmpty,
            fatherInFamily: fatherId.flatMap { memberVM.member(byId: $0) } != nil)
    }

    private var blocker: String? {
        guard let block else { return nil }
        switch block {
        case .account:
            return toFemale ? L10n.t("له حساب في التطبيق — لا يُنقل بين الشجرتين: النقل يحذف ملفه ويبقى حسابه بلا ملف.",
                                     "Has an app account — can't be moved: the move deletes the profile and orphans the account.")
                            : L10n.t("لها حساب في التطبيق — لا تُنقل بين الشجرتين.",
                                     "Has an app account — can't be moved between the trees.")
        case .unverified:
            return L10n.t("تعذّر التحقق من حساب العضو في التطبيق — أغلق المربّع وحاول بعد قليل.",
                          "Couldn't check the member's app account — close and try again shortly.")
        case .checking:
            return L10n.t("يتحقق من حساب العضو في التطبيق…", "Checking the member's app account…")
        case .noFather:
            return L10n.t("لا أب له في الشجرة — اربطه بأبيه أولاً، فالبنت تُنقل تحت أبيها.",
                          "No father in the tree — link him first; a daughter moves under her father.")
        case .linked(let sons, let daughters, let wives):
            let what = [AdminMemberCardLogic.childrenSummary(sons: sons, daughters: daughters, arabic: L10n.isArabic),
                        AdminMemberCardLogic.spousesSummary(count: wives, female: false, arabic: L10n.isArabic)]
                .compactMap { $0 }.joined(separator: L10n.t(" و", " and "))
            return L10n.t("له \(what) مربوطون: فكّ ربطهم أولاً، وإلا يرفض السيرفر النقل.",
                          "\(what) are linked: unlink them first, or the server refuses the move.")
        case .linkedHusband:
            return L10n.t("لها زوج مربوط: فكّ ربطه أولاً.", "She has a linked husband: unlink him first.")
        case .fatherOutside:
            return L10n.t("أبوها ليس في شجرة العائلة — الابن يُنقل تحت أبيه.",
                          "Her father isn't in the family tree — a son moves under his father.")
        }
    }

    private var keeps: String {
        toFemale ? L10n.t("الاسم · الأب · تاريخا الميلاد والوفاة · الظهور · الترتيب",
                          "Name · father · birth and death dates · visibility · order")
                 : L10n.t("الاسم · الأب · تاريخا الميلاد والوفاة · الظهور · الأم",
                          "Name · father · birth and death dates · visibility · mother")
    }

    /// ح١: بلا «الحساب» — من له حساب لا يُنقل أصلاً
    private var loses: String { AdminMemberCardLogic.genderMoveLoses(toFemale: toFemale, arabic: L10n.isArabic) }

    var body: some View {
        Group {
            if motherFailed { AnyView(movedWithoutMother) } else { AnyView(confirmStep) }
        }
        .task {
            guard isProfile else { checkingLogin = false; return }
            checkingLogin = true
            serverLogin = await memberVM.profileHasLogin(member.id)
            checkingLogin = false
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private var confirmStep: some View {
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
                // السؤال جارٍ: سطر محايد لا خطأ
                DSNoteCard(blocker, icon: block == .checking ? "hourglass"
                                    : block == .account || block == .unverified ? "person.crop.circle.badge.exclamationmark" : "link",
                           tint: block == .checking ? DS.Color.textTertiary : DS.Color.error)
            }
            if let failure {
                DSNoteCard(failure, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
    }

    /// م٦: نُقل لكن ربط الأم فشل — يُقال بوضوح، والكرت صار على السجل الجديد (صفّ «الأم» يربطها)
    private var movedWithoutMother: some View {
        DSComposer(
            title: L10n.t("تم النقل", "Moved"),
            subtitle: member.shortFullName,
            icon: "checkmark",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("تم", "Done"),
            showsCancel: false,
            canSubmit: true,
            onSubmit: { dismiss() },
            onCancel: { dismiss() }
        ) {
            DSNoteCard(L10n.t("نُقل، لكن لم تُربط الأم — اربطها من صفّ «الأم» في الكرت أو من شجرة النساء.",
                              "Moved, but the mother wasn't linked — link her from the «Mother» row or the women's tree."),
                       icon: "exclamationmark.triangle.fill", tint: DS.Color.warning)
        }
    }

    private func move() {
        guard blocker == nil else { return }
        let childId = isProfile ? member.id : (family.nodeId ?? member.id)
        if DebugAdminProbe.dryRun("move_child_gender \(childId) → \(target)") { dismiss(); return }
        let motherId = family.mother?.id
        let cardId = member.id
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
            // النقل يُنشئ سجلاً جديداً بلا الأم — أعِدها، وإن فشل فقُل ذلك (كان `try?` يضيّعه بصمت)
            var motherLinked = true
            if let motherId, newId != childId {
                do { try await WomenStore.setMotherId(childId: newId, motherId: motherId) } catch { motherLinked = false }
            }
            await store.refresh(force: true)
            busy = false
            if newId != cardId { onMoved(cardId, newId) }
            if motherLinked {
                DSMomentToast.show(L10n.t("تم النقل", "Moved"), moment: .success)
                dismiss()
            } else {
                motherFailed = true
            }
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
            // ح٣: نصّ صادق — بلا أب لا يُرسم في شجرة العائلة، و`full_name` يصير اسمه الأول
            let name = unlinkTarget?.shortFullName ?? ""
            let first = unlinkTarget.flatMap { AdminMemberSheetLogic.firstName($0.firstName, full: $0.fullName) } ?? name
            Text(L10n.t("«\(name)» يخرج من شجرة العائلة حتى يُربط من جديد، ويصير اسمه الكامل «\(first)» وحده. يُسجَّل التغيير.",
                        "«\(name)» leaves the family tree until relinked, and his full name becomes «\(first)». The change is logged."))
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private var listStep: some View {
        DSComposer(
            title: L10n.t("الأبناء والبنات", "Sons and daughters"),
            subtitle: AdminMemberCardLogic.boxSubtitle([member.shortFullName, family.childrenSummary]),
            icon: "person.2",
            tint: DS.Color.actionNavy,
            actionTitle: orderChanged ? L10n.t("حفظ الترتيب", "Save order") : L10n.t("تم", "Done"),
            showsCancel: false,
            canSubmit: !busy,
            isBusy: busy,
            hasUnsavedChanges: orderChanged,
            // م٧: الثانويان بإطار ذهبي و«تم» وحده ممتلئ
            extraActions: [
                DSComposerAction(id: "add", title: L10n.t("إضافة ابن / بنت", "Add son / daughter"), icon: "plus",
                                 isEnabled: !busy, style: .outlined) { addChild() },
                DSComposerAction(id: "link", title: L10n.t("ربط من الشجرة", "Link from the tree"), icon: "tree",
                                 isEnabled: !busy, style: .outlined) { failure = nil; search = ""; picking = true }
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
                    let kids = grandchildren(child)
                    // ح٣: من له أبناء لا يُفكّ (يخرج فرعه كله) — «الأب ← تغيير» في ورقته
                    AdminMemberLinkRow(name: child.firstName.isEmpty ? child.shortFullName : child.firstName,
                                       note: son && kids > 0 ? L10n.t("له أبناء", "Has children") : nil,
                                       tag: AdminMemberTag(text: son ? L10n.t("ابن", "Son") : L10n.t("بنت", "Daughter"),
                                                           tone: son ? .neutral : .daughterSon),
                                       // ت-ج٣: البنات تُعدّ من شجرة النساء — قبل تحميلها لا يُفتح الزرّ
                                       unlinkEnabled: son && AdminMemberCardLogic.sonUnlinkAllowed(childCount: kids,
                                                                                                    countsLoaded: store.loaded),
                                       disabledHint: son ? (store.loaded ? L10n.t("له أبناء — غيّر أباه من ورقته", "Has children — change his father from his card")
                                                                         : L10n.t("جارٍ التحميل…", "Loading…"))
                                                         : AdminMemberCardLogic.daughterUnlinkNote(arabic: L10n.isArabic),
                                       busy: working == child.id) { unlinkTarget = child }
                }
                Text(L10n.t("اسحب للترتيب. الأبناء والبنات يُحفظ ترتيب كلٍّ منهم في شجرته.",
                            "Drag to order. Sons and daughters each keep their order in their own tree."))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if family.sons.contains(where: { grandchildren($0) > 0 }) {
                    DSNoteCard(L10n.t("«فك الربط» معطّل لمن له أبناء: يخرج فرعه كله من شجرة العائلة. لتصحيح أبيه افتح ورقته ← «الأب» ← تغيير.",
                                      "«Unlink» is off for a son with children: his whole branch would leave the family tree. To fix his father open his card → «Father» → Change."),
                               icon: "info.circle", tint: DS.Color.info)
                }
                if !family.daughters.isEmpty {
                    // ت-ج٨: جملة بسيطة بلا مصطلحات
                    Text(AdminMemberCardLogic.daughterUnlinkNote(arabic: L10n.isArabic))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
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
                    try Self.saved(await memberVM.updateMemberFather(memberId: son.id, fatherId: member.id), memberVM)
                }
            },
            onCancel: { picking = false })
    }

    /// أبناء الابن وبناته (شجرة الرجال وشجرة النساء)
    private func grandchildren(_ son: FamilyMember) -> Int {
        memberVM.allMembers.filter { $0.fatherId == son.id }.count
            + store.people.filter { $0.isFemale && $0.fatherId == son.id }.count
    }

    private func unlink(_ son: FamilyMember) {
        // ح٣: لا يُفكّ من له أبناء (الزرّ معطّل — وهذا حارس ثانٍ)، ولا قبل تحميل شجرة النساء (ت-ج٣)
        guard AdminMemberCardLogic.sonUnlinkAllowed(childCount: grandchildren(son), countsLoaded: store.loaded) else { return }
        working = son.id
        write("updateMemberFather \(son.id) → nil") {
            try Self.saved(await memberVM.updateMemberFather(memberId: son.id, fatherId: nil), memberVM)
        }
    }

    /// ح٣: رفض السيرفر لا يظهر نجاحاً — رسالته (`errorMessage`) في المربّع
    private static func saved(_ ok: Bool, _ vm: MemberViewModel) throws {
        guard ok else {
            let message = vm.errorMessage ?? L10n.t("تعذّر الحفظ. حاول مرة أخرى.", "Couldn't save. Try again.")
            vm.errorMessage = nil
            throw WomenWriteFailure(message: message)
        }
    }

    private func saveOrder() {
        let parts = AdminMemberCardLogic.partitionChildren(order) { sonIds.contains($0.id) }
        let sonsChanged = parts.sons.map(\.id) != family.sons.map(\.id)
        let daughtersChanged = parts.daughters.map(\.id) != family.daughters.map(\.id)
        let fatherId = member.id
        write("children order sons:\(sonsChanged) daughters:\(daughtersChanged)") {
            if sonsChanged {
                try Self.saved(await memberVM.updateChildrenOrder(for: fatherId, newOrder: parts.sons), memberVM)
            }
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
    /// م٣: الطلب/الانضمام داخل مسار الموافقات — يُغلق الكرت ويفتح «الوارد» عليه
    let openInbox: (AdminRequest) -> Void
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var adminRequestVM: AdminRequestViewModel
    @ObservedObject private var store = AdminMemberCardFamilyStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var choice: AdminMemberCardLogic.Lineage?
    @State private var busy = false
    @State private var failure: String?
    /// م٣: تأكيد قبل القرار (نصّ المسار القديم `PendingMemberSheets`)
    @State private var confirmJoin = false
    @State private var confirmDecide = false
    /// م٤: منتقي الأم داخل المربّع نفسه
    @State private var pickingMother = false

    private typealias Lin = AdminMemberCardLogic.Lineage

    private var female: Bool { member.isFemale }

    private var family: AdminMemberCardFamily {
        AdminMemberCardFamily.make(member, isProfile: isProfile, memberVM: memberVM, store: store)
    }

    private var pendingRequest: AdminRequest? {
        adminRequestVM.lineageRequests.first { $0.memberId == member.id && $0.status == ApprovalStatus.pending.rawValue }
    }

    /// طلب انضمامه المعلّق (صفّه في مسار الموافقات إن وُجد) — لـ«فتح في الوارد»
    private var joinRequest: AdminRequest? {
        AdminMemberCardRequests.joinRequest(member, vm: adminRequestVM).first
    }

    private var workflowOn: Bool { adminRequestVM.approvalsWorkflowOn }

    /// طلبه «الزوج/الزوجة من العائلة» أو «اسم الوالدة مكتوباً» — يُقرَّر من بطاقته في «الوارد» لا من هنا
    private var needsInboxCard: Bool {
        AdminMemberCardLogic.lineageRequestNeedsInboxCard(pendingRequest?.details)
    }

    private var save: AdminMemberCardLogic.LineageSave {
        guard let choice else { return .current }
        let requestStage = !(pendingRequest?.stage ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        let joinStage = !(joinRequest?.stage ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        return AdminMemberCardLogic.lineageSave(choice: choice, current: family.lineage, isProfile: isProfile,
                                                hasPendingLineageRequest: pendingRequest != nil && authVM.canApproveTreeRequests,
                                                requestInWorkflow: workflowOn || requestStage,
                                                requestNeedsInboxCard: needsInboxCard,
                                                isPendingJoin: member.role == .pending, joinInWorkflow: workflowOn || joinStage,
                                                isMale: !female)
    }

    private var actionTitle: String {
        switch save {
        case .linkFather: return L10n.t("اختر الأب", "Pick the father")
        case .decideRequest: return female ? L10n.t("وافق على طلبها", "Approve the request") : L10n.t("وافق على طلبه", "Approve the request")
        case .approveJoin: return L10n.t("اقبله ابن بنت", "Accept as daughter's son")
        case .openInbox: return L10n.t("فتح في الوارد", "Open in inbox")
        case .current, .needsServer, .automatic: return L10n.t("حفظ", "Save")
        }
    }

    var body: some View {
        Group {
            if pickingMother {
                AnyView(AdminMemberMotherBox(member: member, isProfile: isProfile) { pickingMother = false })
            } else {
                AnyView(options)
            }
        }
        .onAppear { if choice == nil { choice = family.lineage } }
        .dsAlert(DaughterSons.text("option_title", "ابن بنت من خارج العائلة", "A daughter's son from outside the family"),
                 isPresented: $confirmJoin) {
            Button(L10n.t("موافقة", "Approve")) { approveJoin() }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("يُقبل حساب \(member.displayFullName) ويكمل نسبه من التطبيق.",
                        "\(member.displayFullName)'s account is approved; he completes his lineage in the app."))
        }
        .dsAlert(L10n.t("الموافقة على طلب «الصلة بالعائلة»؟", "Approve the relation request?"), isPresented: $confirmDecide) {
            Button(L10n.t("موافقة", "Approve")) { decide() }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("يُعتمد «ابن بنت» لـ\(member.displayFullName) وتُربط أمّه كما في طلبه.",
                        "«Daughter's son» is confirmed for \(member.displayFullName) and his mother linked as requested."))
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private var options: some View {
        // ت٥: الخيارات التي تنطبق على جنسه فقط
        let list = AdminMemberCardLogic.lineageOptions(female: female)
        return DSComposer(
            title: AdminMemberCardLogic.lineageTitle(female: female, arabic: L10n.isArabic),
            subtitle: member.shortFullName,
            icon: "tag",
            tint: DS.Color.actionNavy,
            actionTitle: actionTitle,
            canSubmit: !busy && [.linkFather, .decideRequest, .approveJoin, .openInbox].contains(save),
            isBusy: busy,
            hasUnsavedChanges: choice != nil && choice != family.lineage,
            onSubmit: submit,
            onCancel: { dismiss() }
        ) {
            VStack(spacing: 0) {
                ForEach(list, id: \.self) { option in
                    optionRow(option)
                    if option != list.last { AdminRowDivider() }
                }
            }
            .dsCard()
            switch save {
            case .needsServer:
                AdminMemberNeedsServerNote(text: L10n.t("لا نداء على السيرفر يغيّر هذه الصلة مباشرة.",
                                                        "No server call changes this relation directly."))
            case .automatic:
                DSNoteCard(automaticNote, icon: "arrow.triangle.branch", tint: DS.Color.info)
            case .openInbox:
                DSNoteCard(needsInboxCard
                           ? L10n.t("له طلب «استكمال التسجيل» معلّق — الربط من بطاقته في «الوارد».",
                                    "A pending registration-completion request — link it from its inbox card.")
                           : L10n.t("الطلب في مسار الموافقات — القرار من «الوارد» بمراحله.",
                                    "The request is in the approvals path — decide it in the inbox."),
                           icon: "tray", tint: DS.Color.info)
            default:
                EmptyView()
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
    }

    /// ت٥: «من خارج العائلة» يحسبه السيرفر من الروابط (`trg_women_outside_flag`) — لا يُكتب باليد
    private var automaticNote: String {
        choice == .outsideWife
            ? L10n.t("تُحسب تلقائياً من الروابط: بلا أب في الشجرة ومتزوّجة من رجل في العائلة.",
                     "Computed automatically from the links: no father in the tree and married to a family man.")
            : L10n.t("تُحسب تلقائياً من الروابط: رجل بلا أب ولا أمّ في الشجرة، زوج لبنت من العائلة.",
                     "Computed automatically from the links: a man with no father or mother in the tree, married to a family daughter.")
    }

    /// «الحالي: ابن بنت · اعتمده حسن · 20/11/2026»
    private var currentLine: String {
        let now = family.lineageTag(branch: branch)
            ?? AdminMemberCardLogic.notRecorded(arabic: L10n.isArabic, feminine: true)
        let by = family.lineageSetBy(byId: memberVM.member(byId:))
        return L10n.t("الحالي: ", "Now: ") + [now, by].compactMap { $0 }.joined(separator: " · ")
    }

    private func optionRow(_ option: Lin) -> some View {
        let selected = choice == option
        return VStack(alignment: .leading, spacing: 0) {
            Button { choice = option } label: {
                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .dsGlyph(DS.Glyph.xl, weight: .regular)
                        .foregroundColor(selected ? DS.Color.primary : DS.Color.textTertiary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(AdminMemberCardFamily.title(option))
                            .dsFont(.rowTitle)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(AdminMemberCardFamily.explanation(option, female: female))
                            .dsFont(.subtitle)
                            .foregroundColor(DS.Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DS.Spacing.sm)
                .frame(minHeight: DS.Icon.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(AdminRowPressStyle())
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            if option == .daughterSon, selected { motherLine }
        }
    }

    /// «ابن بنت» يحتاج أمّاً: الحالية بسهم ‹ يفتح منتقي الأم (م٤)، أو أمّه كما في طلبه المعلّق (للاطلاع)
    @ViewBuilder
    private var motherLine: some View {
        let requested = pendingRequest.flatMap { LineageRequestDetails.parse($0.details) }
        let current = AdminMemberCardFamily.firstName(family.mother)
        let name = current ?? requested?.motherName ?? requested?.newMother?.name
        let canPick = pendingRequest == nil && family.nodeId != nil
        let face = HStack(spacing: DS.Spacing.xs) {
            Text(L10n.t("الأم:", "Mother:")).dsFont(.chip)
            Text(verbatim: name ?? AdminMemberCardLogic.notRecorded(arabic: L10n.isArabic, feminine: true)).dsFont(.chip)
            Spacer(minLength: DS.Spacing.sm)
            if canPick { DSChevron() }
        }
        .foregroundColor(DS.Color.textSecondary)
        .padding(.horizontal, DS.Spacing.md)
        .frame(minHeight: DS.Icon.tapTarget)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).fill(DS.Color.cardBackgroundSoft))
        .padding(.leading, AdminRowDivider.iconInset)
        .padding(.bottom, DS.Spacing.sm)
        if canPick {
            Button { pickingMother = true } label: { face.contentShape(Rectangle()) }
                .buttonStyle(AdminRowPressStyle())
                .accessibilityHint(Text(name == nil ? L10n.t("يختار أمّه من بنات العائلة", "Picks his mother from the family daughters")
                                                    : L10n.t("يغيّر أمّه", "Changes his mother")))
        } else {
            face
        }
        if pendingRequest != nil && !needsInboxCard {
            Text(L10n.t("له طلب «الصلة بالعائلة» معلّق — الموافقة تُنشئ صلته بأمّه كما في الطلب.",
                        "A pending relation request — approving links him to his mother as requested."))
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, AdminRowDivider.iconInset)
                .padding(.bottom, DS.Spacing.sm)
        }
    }

    private func submit() {
        switch save {
        case .linkFather:
            linkFather()
        case .decideRequest:
            confirmDecide = true
        case .approveJoin:
            confirmJoin = true
        case .openInbox:
            if let request = pendingRequest ?? joinRequest { openInbox(request) }
        case .current, .needsServer, .automatic:
            break
        }
    }

    private func decide() {
        guard let request = pendingRequest else { return }
        run("decide_lineage_request \(request.id)") {
            try await DaughterSons.decide(requestId: request.id, approve: true, reason: nil)
            await adminRequestVM.fetchPolicyRequests()
        }
    }

    private func approveJoin() {
        let id = member.id
        run("approve_join_as_daughter_son \(id)") {
            try await DaughterSons.approveJoin(memberId: id)
            await DaughterSonsIndex.shared.refresh(force: true)
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

// MARK: - (و) «الأم» — منتقي الأم (م٤)

/// بنت من بنات العائلة تصير أمّه — مسار الإدارة نفسه في شجرة النساء (`linkFamilyMother`/`addMotherUnderFather`):
/// `WomenStore.setMotherId` على عقدته، وتصير زوجةً لأبيه إن لم يكن لها زوج. بلا عقدة في شجرة النساء: لا ربط من هنا
struct AdminMemberMotherBox: View {
    let member: FamilyMember
    let isProfile: Bool
    /// داخل مربّع «الصلة»: يرجع إليه — nil = يُغلق المربّع
    var onDone: (() -> Void)? = nil
    @EnvironmentObject private var memberVM: MemberViewModel
    @ObservedObject private var store = AdminMemberCardFamilyStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var failure: String?

    private var family: AdminMemberCardFamily {
        AdminMemberCardFamily.make(member, isProfile: isProfile, memberVM: memberVM, store: store)
    }

    var body: some View {
        let f = family
        Group {
            if let node = f.nodeId {
                AnyView(DSWifeFlowBox(
                    mode: .direct, relation: .mother, husbandId: node, personFatherId: f.father?.id,
                    husbandName: member.shortFullName, people: store.people, isLoading: !store.loaded, showsHidden: true,
                    isBusy: busy, error: failure,
                    onLink: { daughter, _ in link(daughter, node: node, personFather: f.father?.id) },
                    onAddUnderFather: { name, father in
                        add(name, father: father, node: node, personFather: f.father?.id, deceased: false)
                    },
                    onCancel: close)
                    .addsDeceased { name, father in
                        add(name, father: father, node: node, personFather: f.father?.id, deceased: true)
                    })
            } else {
                AnyView(DSComposer(title: L10n.t("الأم", "Mother"), subtitle: member.shortFullName, icon: "heart",
                                   tint: DS.Color.actionNavy, actionTitle: "", showsAction: false,
                                   cancelTitle: L10n.t("إغلاق", "Close"), canSubmit: false,
                                   onSubmit: {}, onCancel: close) {
                    DSNoteCard(L10n.t("لا عقدة له في شجرة النساء بعد — الأم تُربط من شجرة النساء.",
                                      "No node in the women's tree yet — link the mother from the women's tree."),
                               tint: DS.Color.warning)
                })
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func close() {
        if let onDone { onDone() } else { dismiss() }
    }

    private func link(_ daughter: FamilyMember, node: UUID, personFather: UUID?) {
        write("mother link \(daughter.id) → \(node)") {
            if let personFather, daughter.husbandId == nil {
                try await WomenStore.setHusbandId(womanId: daughter.id, husbandId: personFather)
            }
            try await WomenStore.setMotherId(childId: node, motherId: daughter.id)
        }
    }

    private func add(_ name: String, father: FamilyMember, node: UUID, personFather: UUID?, deceased: Bool) {
        let sort = (store.people.filter { $0.fatherId == father.id }.map(\.sortOrder).max() ?? -1) + 1
        let fatherFull = father.fullName
        write("mother add under \(father.id) for \(node)") {
            let newId = try await WomenStore.addFamilyChild(parentId: father.id, name: name, gender: "female",
                                                            birthDate: nil, sortOrder: sort, parentFullName: fatherFull,
                                                            isDeceased: deceased)
            if let personFather { try await WomenStore.setHusbandId(womanId: newId, husbandId: personFather) }
            try await WomenStore.setMotherId(childId: node, motherId: newId)
        }
    }

    /// كتابة واحدة: الدوّارة، ثم إعادة الجلب والرجوع؛ الفشل برسالة السيرفر والمربّع كما هو
    private func write(_ label: String, _ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        failure = nil
        if DebugAdminProbe.dryRun("member card \(label)") { close(); return }
        busy = true
        Task { @MainActor in
            do {
                try await work()
                await store.refresh(force: true)
                busy = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                close()
            } catch {
                busy = false
                failure = adminFamilyFailure(error)
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
