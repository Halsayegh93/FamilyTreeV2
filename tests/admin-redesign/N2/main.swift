// فحص «متزوجة بلا زوج مربوط» في «المكرر والأخطاء» (Views/Features/Admin/AdminDuplicateNames.swift، الوحدة N2) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/n2-logic \
//     FamilyTreeV2/FamilyTreeV2/Core/ArabicTextNormalizer.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminDuplicateNames.swift tests/admin-redesign/N2/main.swift && /private/tmp/claude-501/n2-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias M = AdminMarriedNoHusband
func uid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
func w(_ id: Int, parent: Int?, mother: Int? = nil, married: Bool = true, husband: Int? = nil,
       female: Bool = true, first: String = "شهد", full: String = "") -> M.Woman {
    M.Woman(id: uid(id), parent: parent.map(uid), mother: mother.map(uid), isFemale: female, isMarried: married,
            husband: husband.map(uid), firstName: first, fullName: full)
}

// MARK: من يدخل القائمة
let rows = [
    w(1, parent: 100),                         // بنت عائلة متزوجة بلا زوج ← نعم
    w(2, parent: 100, husband: 200),           // لها زوج مربوط ← لا
    w(3, parent: 100, married: false),         // غير متزوجة ← لا
    w(4, parent: nil),                         // زوجة وافدة بلا أب في الشجرة ← لا (ليست بنت عائلة)
    w(5, parent: 100, female: false),          // عقدة رجل ← لا
    w(6, parent: 101, first: "دلال"),           // نعم
    w(7, parent: 1, mother: 1, married: false),// ابنة شهد (طفلة) ← لا، لكن تُعدّ ابناً لشهد
    w(8, parent: 300, mother: 1, married: false, female: false),  // ابن شهد بأمّه
]
check(M.ids(rows), [uid(1), uid(6)], "بنات العائلة المتزوجات بلا زوج فقط، بترتيب الدخل")
check(M.ids(rows, excluding: [uid(6)]), [uid(1)], "المستبعدون (عقد الرجال المنسوخة) لا يدخلون")

// MARK: لها أبناء
check(M.childCount(uid(1), in: rows), 2, "أبناؤها بالأصل أو بالأم — مرة لكل ابن")
check(M.childCount(uid(6), in: rows), 0, "بلا أبناء")

// MARK: الاسم «شهد بنت صلاح عبدالحميد»
check(M.displayName(first: "شهد", father: "صلاح", grandfather: "عبدالحميد", fullName: ""), "شهد بنت صلاح عبدالحميد", "الاسم بالنسب")
check(M.displayName(first: "شهد", father: "صلاح", grandfather: nil, fullName: ""), "شهد بنت صلاح", "بلا جد")
check(M.displayName(first: "شهد", father: nil, grandfather: nil, fullName: "شهد صلاح عبدالحميد حسن المحمدعلي"),
      "شهد بنت صلاح عبدالحميد", "بلا أب ظاهر: من الاسم الكامل")
check(M.displayName(first: "", father: nil, grandfather: nil, fullName: "شهد"), "شهد", "اسم واحد")

// MARK: المدخل
check(AdminDuplicateNames.entryCount(duplicates: 1, problems: 2, nameless: 3, marriedNoHusband: 7), 13,
      "رقم المدخل يشمل «متزوجة بلا زوج مربوط»")
check(AdminDuplicateNames.entryCount(duplicates: 1, problems: 2, nameless: 3), 6, "بلا القائمة الجديدة: كما كان")

print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
