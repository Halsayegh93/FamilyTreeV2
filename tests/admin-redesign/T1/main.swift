// فحص شاشة الشجرة (الوحدة T1، مراجعة ٢٠٢٦-١١-٢٧) — «موقعك» واحد للوضعين · كاميرا الانتقال لعضو · عدد الرأس — بلا محاكي:
//   xcrun swiftc -swift-version 5 -default-isolation MainActor -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/t1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/TreeLocateLogic.swift tests/admin-redesign/T1/main.swift \
//     && /private/tmp/claude-501/t1-logic
import Foundation
import CoreGraphics

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

// MARK: - «موقعك»
let root = UUID(), father = UUID(), me = UUID(), orphan = UUID(), daughterSon = UUID()
let fathers: [UUID: UUID] = [father: root, me: father]
let inTree: Set<UUID> = [root, father, me, orphan]          // orphan: حساب بلا أب بين الأفراد (غير مربوط)
func place(_ id: UUID?, women: Bool = false, tab: Bool = true) -> TreeMyPlace? {
    TreeMyPlace.resolve(userId: id, rootId: root, isInTree: { inTree.contains($0) }, fatherOf: { fathers[$0] },
                        inWomenTree: women, hasWomenTab: tab)
}
check(place(nil), nil, "بلا حساب: لا شيء")
check(place(me), .family(me), "المربوط: ينتقل لعقدته")
check(place(root), .family(root), "الرأس نفسه")
check(place(orphan), .notLinked, "حساب بين الأفراد بلا أب: «غير مربوط» (كان العمودي صامتاً)")
check(place(daughterSon, women: true), .women, "ابن البنت: شجرة النساء")
check(place(daughterSon, women: true, tab: false), .notLinked, "ابن البنت بلا تبويب النساء: الرسالة")
check(place(daughterSon), .notLinked, "غير موجود: الرسالة")
check(place(me, women: true), .family(me), "في الشجرتين: شجرة العائلة أولاً (كالأفقي)")
// حلقة آباء خاطئة لا تعلّق
let a = UUID(), b = UUID()
check(TreeMyPlace.reachesRoot(a, rootId: root, fatherOf: { $0 == a ? b : a }), false, "حلقة آباء: تتوقف")
check(TreeMyPlace.reachesRoot(me, rootId: nil, fatherOf: { fathers[$0] }), false, "بلا رأس")

// MARK: - كاميرا الانتقال لعضو
let avail = CGRect(x: 20, y: 200, width: 353, height: 520)   // تحت بطاقة الأدوات وفوق الشريط
let s: CGFloat = 0.6
let fatherR = CGRect(x: 400, y: 100, width: 124, height: 190)
let meR = CGRect(x: 400, y: 400, width: 124, height: 190)
let kidsR = CGRect(x: 250, y: 700, width: 400, height: 190)
func screen(_ r: CGRect, _ o: CGSize) -> CGRect {
    CGRect(x: o.width + r.minX * s, y: o.height + r.minY * s, width: r.width * s, height: r.height * s)
}
// «موقعك»: الأب + العضو (بلا أبناء ظاهرين)
var o = TreeFocusCamera.offset(member: meR, father: fatherR, kids: nil, avail: avail, bandMidX: 196.5, scale: s, fallbackAnchorY: 0.42)
check(screen(fatherR, o).minY >= avail.minY, true, "«موقعك»: الأب كاملاً تحت بطاقة الأدوات")
check(screen(meR, o).maxY <= avail.maxY, true, "«موقعك»: العضو فوق الشريط السفلي")
check(abs(screen(meR, o).midX - 196.5) < 0.01, true, "العضو بمنتصف الشاشة أفقياً")
check(abs(screen(fatherR.union(meR), o).midY - avail.midY) < 0.01, true, "الأب والعضو معاً بمنتصف المساحة (لا نصف فارغ)")
// البحث: الأب + العضو + أبناؤه — كلهم داخل المساحة (لا أبناء تحت الشريط)
o = TreeFocusCamera.offset(member: meR, father: fatherR, kids: kidsR, avail: avail, bandMidX: 196.5, scale: s, fallbackAnchorY: 0.42)
check(screen(fatherR, o).minY >= avail.minY, true, "البحث: الأب ظاهر")
check(screen(kidsR, o).maxY <= avail.maxY, true, "البحث: الأبناء فوق الشريط السفلي")
// مساحة ضيقة: لا تتّسع الثلاثة → الأب + العضو
let small = CGRect(x: 20, y: 200, width: 353, height: 330)
o = TreeFocusCamera.offset(member: meR, father: fatherR, kids: kidsR, avail: small, bandMidX: 196.5, scale: s, fallbackAnchorY: 0.42)
check(screen(fatherR, o).minY >= small.minY && screen(meR, o).maxY <= small.maxY, true, "مساحة ضيقة: الأب والعضو")
// أب بعيد جداً (صفوف إخوة كثيرة): العضو وأبناؤه أو وحده — لا يضيع العضو
let farFather = CGRect(x: 400, y: -900, width: 124, height: 190)
o = TreeFocusCamera.offset(member: meR, father: farFather, kids: nil, avail: small, bandMidX: 196.5, scale: s, fallbackAnchorY: 0.42)
check(small.contains(screen(meR, o)), true, "أب بعيد: العضو ظاهر كاملاً")

// MARK: - عدد الرأس
check(TreeHeaderCount.arabic(2728), "2,728 فرداً", "2728 → «2,728 فرداً»")
check(TreeHeaderCount.arabic(5), "5 أفراد", "5 أفراد")
check(TreeHeaderCount.arabic(2), "فردان", "فردان")
check(TreeHeaderCount.arabic(1100), "1,100 فرد", "1,100 فرد")
check(TreeHeaderCount.english(2728), "2,728 members", "English")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
