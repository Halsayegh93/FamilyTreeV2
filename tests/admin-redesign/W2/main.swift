// فحص شجرة النساء ٢ (الوحدة W2، ٢٠٢٦-١١-٢٨) — هدف البحث/«موقعك» · زوج البنت وهي مطويّة · شكل الزوج والزوجة الواحد — بلا محاكي:
//   xcrun swiftc -swift-version 5 -default-isolation MainActor -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/w2-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/WomenTreeLogic.swift tests/admin-redesign/W2/main.swift \
//     && /private/tmp/claude-501/w2-logic
import Foundation
import CoreGraphics

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

// MARK: - هدف التمركز (البحث و«موقعك»)
let daughter = UUID(), husbandOut = UUID(), man = UUID(), wifeIn = UUID()
let wifeOf: [UUID: UUID] = [husbandOut: daughter]
func target(_ id: UUID, fatherInTree: Bool, husband: UUID? = nil, husbandInTree: Bool = false) -> UUID {
    WomenFocusTarget.resolve(id: id, fatherInTree: fatherInTree, husbandId: husband,
                             husbandInTree: husbandInTree, outsideWifeOf: wifeOf)
}
check(target(daughter, fatherInTree: true), daughter, "بنت تحت أبيها: عقدتها")
check(target(wifeIn, fatherInTree: false, husband: man, husbandInTree: true), man, "زوجة وافدة: عقدة زوجها (هي مربّع جنبه)")
check(target(husbandOut, fatherInTree: false), daughter, "الزوج من خارج العائلة: عقدة زوجته البنت")
check(target(wifeIn, fatherInTree: false, husband: man, husbandInTree: false), wifeIn, "زوجة وزوجها غير ظاهر: عقدتها")
check(target(wifeIn, fatherInTree: true, husband: man, husbandInTree: true), wifeIn, "بنت متزوجة من العائلة: عقدتها تحت أبيها")

// MARK: - زوج البنت ظاهر وهي مطويّة
check(WomenSpouseRule.showsHusband(hasHusband: true, collapsed: true, hasKids: true), true, "مطويّة ولها أبناء: الزوج جنبها")
check(WomenSpouseRule.showsHusband(hasHusband: true, collapsed: false, hasKids: true), true, "مفتوحة: الزوج جنبها")
check(WomenSpouseRule.showsHusband(hasHusband: true, collapsed: true, hasKids: false), true, "بلا أبناء: الزوج جنبها")
check(WomenSpouseRule.showsHusband(hasHusband: false, collapsed: false, hasKids: true), false, "بلا زوج ظاهر: لا شيء")

// MARK: - شكل واحد للزوج والزوجة
let g = WomenSpouseGeometry(k: 1, circle: 105, nodeW: 124)
check(g.wifeSquare, g.husbandSquare, "مربّع الزوجة بمقاس دائرة الزوج")
check(g.wifeCellW, g.husbandCellW, "خلية الزوجة بعرض خلية الزوج")
check(g.centerX(1), g.husbandCellX, "الزوجة الأولى مكان الزوج تماماً")
check(g.overhang(1), g.husbandOverhang, "بروز زوجة واحدة = بروز الزوج")
// الخط الذهبي: من حافة العقدة إلى أبعد زوجة في الجهة (يمرّ خلف القريبة) — خطّ واحد
check(g.lineFrom, 105 / 2, "الخط يبدأ من حافة شكل العضو")
check(g.lineTo(1), g.husbandCellX - g.husbandSquare / 2, "زوج/زوجة واحدة: الخط حتى حافة شكله")
check(g.lineTo(2), g.centerX(2) + (g.wifeCellW + g.spacing) / 2 - g.wifeSquare / 2, "زوجتان: الخط حتى حافة الأبعد")
let k2 = WomenSpouseGeometry(k: 1.2, circle: 126, nodeW: 148.8)
check(abs(k2.husbandSquare - g.husbandSquare * 1.2) < 0.001, true, "المقاسات × معامل «حجم النص»")

print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
