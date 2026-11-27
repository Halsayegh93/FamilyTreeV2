// فحص شجرة النساء (الوحدة W1، مراجعة ٢٠٢٦-١١-٢٧) — كبسولة «ابن بنت/بنت بنت» · «موقعك» بالمعرّفات · قاعدة الصور · القارئ الصوتي — بلا محاكي:
//   xcrun swiftc -swift-version 5 -default-isolation MainActor -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/w1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/WomenTreeLogic.swift tests/admin-redesign/W1/main.swift \
//     && /private/tmp/claude-501/w1-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

// MARK: - الكبسولة
let husband = UUID(), daughter = UUID(), kid = UUID()
let outside: Set<UUID> = [husband]
func tag(_ id: UUID, female: Bool, father: UUID?, mother: UUID?, out: Set<UUID> = outside) -> WomenNodeTag? {
    WomenNodeTag.resolve(id: id, isFemale: female, fatherId: father, motherId: mother, outside: out)
}
check(tag(husband, female: false, father: nil, mother: nil), .outsideFamily, "الزوج نفسه: «من خارج العائلة»")
check(tag(kid, female: true, father: husband, mother: daughter), .daughterDaughter, "بنت البنت: «بنت بنت» لا «من خارج العائلة»")
check(tag(kid, female: false, father: husband, mother: daughter), .daughterSon, "ابن البنت بلا حساب: «ابن بنت»")
// ابن البنت بمعرّف داخل قائمة «خارج العائلة» (سجل قديم) — الصلة أولاً
check(tag(kid, female: false, father: husband, mother: daughter, out: [husband, kid]), .daughterSon, "ابن البنت المعلَّم خارجاً: «ابن بنت»")
check(tag(kid, female: true, father: husband, mother: nil), nil, "بلا أم: لا كبسولة (لا «خارج العائلة» خطأً)")
check(tag(kid, female: true, father: UUID(), mother: daughter), nil, "أبوه من العائلة: لا كبسولة")
check(tag(daughter, female: true, father: UUID(), mother: nil), nil, "بنت العائلة: لا كبسولة")
check(tag(kid, female: true, father: husband, mother: daughter, out: []), nil, "قبل دعم «خارج العائلة»: لا شيء")

// MARK: - «موقعك»
let me = UUID(), womanNode = UUID()
let nodes: Set<UUID> = [me, womanNode]
func mine(_ u: UUID?, linked: [UUID: UUID] = [:], has: Set<UUID> = nodes) -> UUID? {
    WomenMyNode.resolve(userId: u, hasNode: { has.contains($0) }, womanByLinkedUser: linked)
}
let acct = UUID()
check(mine(nil), nil, "بلا حساب")
check(mine(me), me, "الرجل: عقدته المرآة بمعرّفه")
check(mine(acct, linked: [acct: womanNode]), womanNode, "حساب المرأة: عقدتها المربوطة")
check(mine(acct), nil, "غير موجود: لا تخمين")
check(mine(acct, linked: [acct: UUID()]), nil, "ربط لعقدة غير ظاهرة: لا شيء")
check(mine(me, linked: [me: womanNode]), me, "المعرّف نفسه أولاً")

// MARK: - الصور
check(WomenTreePhoto.url(isFemale: true, own: "a", linked: "b"), nil, "الأنثى: بلا صورة أبداً")
check(WomenTreePhoto.url(isFemale: false, own: "a", linked: "b"), "a", "الذكر: صورته")
check(WomenTreePhoto.url(isFemale: false, own: "", linked: "b"), "b", "ابن البنت: صورة حسابه")
check(WomenTreePhoto.url(isFemale: false, own: nil, linked: nil), nil, "ذكر بلا صورة")

// MARK: - القارئ الصوتي
check(WomenNodeSpeech.label(name: "منال", isFemale: true, deceased: true, relation: nil), "منال، ابنة، متوفاة", "بنت متوفاة")
check(WomenNodeSpeech.label(name: "أسماء", isFemale: true, deceased: false, relation: "بنت بنت"), "أسماء، بنت بنت", "بنت بنت")
check(WomenNodeSpeech.label(name: "حمد", isFemale: false, deceased: true, relation: nil), "حمد، ابن، متوفى", "ابن متوفى")
check(WomenNodeSpeech.hint(children: 3, collapsed: true), "تُفتح فيظهر الأبناء (3)", "مطويّة")
check(WomenNodeSpeech.hint(children: 3, collapsed: false), "تُطوى فيختفي الأبناء", "مفتوحة")
check(WomenNodeSpeech.hint(children: 0, collapsed: true), "تُفتح التفاصيل", "بلا أبناء")

print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
