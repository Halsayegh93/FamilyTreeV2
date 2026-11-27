// فحص منطق «صلاحيات الأعضاء حسب الفئة» (Core/MemberAccess.swift، الوحدة P2) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/p2-logic \
//     FamilyTreeV2/FamilyTreeV2/Core/MemberAccess.swift tests/admin-redesign/P2/main.swift \
//     && /private/tmp/claude-501/p2-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias A = MemberAccess
typealias S = MemberScreen
typealias C = MemberCategory
let empty = A.Matrix(json: nil)

// ── ١) الافتراضي = اليوم ──
for c in C.allCases where c != .limited {
    check(S.allCases.allSatisfy { A.sees($0, category: c, matrix: empty, legacyLimited: nil) }, true,
          "الافتراضي: \(c.rawValue) يرى كل شيء")
}
for s in A.legacyLimitedDefaults {
    check(A.sees(s, category: .limited, matrix: empty, legacyLimited: nil), false, "المحدود لا يرى \(s.rawValue) افتراضياً")
}
check(A.sees(.news, category: .limited, matrix: empty, legacyLimited: nil), true, "المحدود يرى الأخبار")
check(A.sees(.memberDetailsEditRequest, category: .limited, matrix: empty, legacyLimited: nil), false,
      "المحدود: داخل تفاصيل العضو مخفي مع أمّه")
// المفتاح القديم يبقى احتياطاً
check(A.sees(.diwaniyas, category: .limited, matrix: empty, legacyLimited: []), true, "outside_member_locked_sections = [] يفتح الكل")
check(A.sees(.library, category: .limited, matrix: empty, legacyLimited: ["library"]), false, "القديم: المكتبة مقفولة")
check(A.sees(.projects, category: .limited, matrix: empty, legacyLimited: ["library"]), true, "القديم: المشاريع مفتوحة")
// الإدارة وغير المفعّل خارج الجدول
let allOff = A.Matrix(json: ["family_man": Dictionary(uniqueKeysWithValues: S.allCases.map { ($0.rawValue, false) })])
check(A.sees(.tree, category: nil, matrix: allOff, legacyLimited: nil), true, "بلا فئة (الإدارة) = يرى")

// ── ٢) الأم المطفأة تخفي أبناءها، وترجع قيمهم حين تُشغَّل ──
var m = A.setting(.memberDetailsContact, to: false, category: .daughterSon, matrix: empty)
check(A.sees(.memberDetailsContact, category: .daughterSon, matrix: m, legacyLimited: nil), false, "خيار داخلي مطفأ")
check(A.sees(.memberDetails, category: .daughterSon, matrix: m, legacyLimited: nil), true, "أمّه ظاهرة")
m = A.setting(.memberDetails, to: false, category: .daughterSon, matrix: m)
check(S.memberDetails.children.allSatisfy { !A.sees($0, category: .daughterSon, matrix: m, legacyLimited: nil) }, true,
      "الأم المطفأة تخفي كل أبنائها")
check(A.ownValue(.memberDetailsKinship, category: .daughterSon, matrix: m, legacyLimited: nil), true,
      "قيمة الابن نفسها لا تتغيّر")
m = A.setting(.memberDetails, to: true, category: .daughterSon, matrix: m)
check(A.sees(.memberDetailsKinship, category: .daughterSon, matrix: m, legacyLimited: nil), true, "تشغيل الأم يرجع الأبناء")
check(A.sees(.memberDetailsContact, category: .daughterSon, matrix: m, legacyLimited: nil), false, "والمطفأ قبلها يبقى مطفأ")
check(A.sees(.memberDetailsContact, category: .daughterDaughter, matrix: m, legacyLimited: nil), true, "فئة أخرى لا تتأثر")

// ── ٣) الإبلاغ والحظر خارج الجدول دائماً ──
check(S.allCases.contains { A.isProtectedKey($0.rawValue) }, false, "لا مفتاح للإبلاغ أو الحظر في القائمة")
for k in ["member_details.report", "member_details.block", "news.report", "report", "block", "news.block_author"] {
    check(A.isProtectedKey(k), true, "محمي: \(k)")
}
let sneaky = A.Matrix(json: ["family_man": ["member_details.report": false, "member_details.block": false, "tree": false]])
check(sneaky.rows[.familyMan]?.count, 1, "مفاتيح الإبلاغ/الحظر تُرمى عند القراءة")
check(A.alwaysVisibleSafety(category: .limited, matrix: allOff), true, "الإبلاغ والحظر ظاهران ولو كل شيء مطفأ")
check(A.sees(.profile, category: .familyMan, matrix: allOff, legacyLimited: nil), true, "«حسابي» لا يُخفى (حذف الحساب والإعدادات)")
check(S.profile.isLocked, true, "«حسابي» بلا مفتاح")
check(A.sees(.profileMyFamily, category: .familyMan, matrix: allOff, legacyLimited: nil), false, "لكن داخل «حسابي» يُطفأ")

// ── ٤) القراءة من JSON: غير المعروف والخاطئ يُرمى ──
let messy = A.Matrix(json: ["family_man": ["tree": false, "nope": false, "news": "no"], "alien": ["tree": false], "limited": 5])
check(messy.rows[.familyMan], [S.tree: false], "يُبقى المعروف بقيمة منطقية فقط")
check(messy.rows[.limited] == nil && messy.rows.count == 1, true, "فئة غير معروفة أو صفّ غير كائن يُرمى")
check(A.Matrix(json: "garbage").rows.isEmpty, true, "قيمة ليست كائناً = الافتراضي")
let nsBool = A.Matrix(json: ["family_man": ["tree": NSNumber(value: false)]])
check(nsBool.rows[.familyMan]?[.tree], false, "NSNumber منطقي يُقرأ")
let round = A.Matrix(json: m.json)
check(round, m, "الحفظ ثم القراءة = نفسه")
check(A.resetting(.daughterSon, matrix: m).rows[.daughterSon] == nil, true, "«إعادة الافتراضي» تحذف صفّ الفئة")
check(A.resetting(.daughterSon, matrix: m).json["daughter_son"] == nil, true, "وفي JSON")

// ── ٥) الفئة (نفس قاعدة my_member_category على السيرفر) ──
func cat(staff: Bool = false, active: Bool = true, limited: Bool = false, lineage: Bool = false, completed: Bool = true,
         review: Bool = false, child: Bool = false, outside: Bool = false, female: Bool = false) -> C? {
    A.category(.init(isStaff: staff, isActive: active, isLimited: limited, hasLineageRow: lineage,
                     isCompleted: completed, isReviewAccount: review,
                     isDaughterChildNode: child, isOutsideNode: outside, isFemale: female))
}
check(cat(staff: true, limited: true), nil, "الإدارة خارج الجدول ولو لها صفّ نسب")
check(cat(active: false), nil, "غير المفعّل خارج الجدول")
check(cat(limited: true, lineage: true, female: true), .limited, "المحدود أولاً")
check(cat(lineage: true), .daughterSon, "ابن بنت")
// بند ١٣: «لم يستكمل التسجيل» — صفّ نسب بلا completed_at ولا limited_at (ومنه من أرسل اسم الوالدة وينتظر الإدارة)
check(cat(lineage: true, completed: false), .incomplete, "ابن بنت لم يستكمل التسجيل")
check(cat(lineage: true, completed: false, female: true), .incomplete, "بنت بنت لم تستكمل التسجيل")
check(cat(limited: true, lineage: true, completed: false), .limited, "المحدود قبل «لم يستكمل»")
check(cat(lineage: true, completed: false, review: true), .daughterSon, "حساب المراجعة يبقى في فئته اليوم")
check(cat(completed: false, child: true), .daughterSon, "بلا صفّ نسب: ليس «لم يستكمل»")
check(C.incomplete.rawValue, "incomplete", "مفتاح السيرفر")
check(C.incomplete.titleAr, "لم يستكمل التسجيل", "عنوان الفئة")
check(C.incomplete.whoAr, "أبناء وبنات البنات قبل استكمال التسجيل", "سطر الفئة")
check(C.allCases.count, 7, "سبع فئات")
check(S.allCases.allSatisfy { A.sees($0, category: .incomplete, matrix: empty, legacyLimited: nil)
                               == A.sees($0, category: .daughterSon, matrix: empty, legacyLimited: nil) }, true,
      "افتراض «لم يستكمل» = افتراض ابن البنت اليوم")
check(cat(lineage: true, female: true), .daughterDaughter, "بنت بنت")
check(cat(child: true, outside: true, female: true), .daughterDaughter, "بنت بنت من عقدتها قبل «من خارج العائلة»")
check(cat(outside: true, female: true), .outsideSpouse, "زوجة من خارج العائلة")
check(cat(outside: true), .outsideSpouse, "زوج بنت من خارج العائلة")
check(cat(female: true), .familyWoman, "نساء العائلة")
check(cat(), .familyMan, "رجل من العائلة")
check(C(rawValue: "outside_spouse"), .outsideSpouse, "مفاتيح الفئات كما على السيرفر")

// ── ٦) القائمة: مفاتيح ثابتة، والأمهات والأبناء ──
check(S.memberDetailsEditRequest.rawValue, "member_details.edit_request", "المفتاح الثابت")
check(S.allCases.filter { $0.parent == nil }.map(\.rawValue),
      ["news", "tree", "women_tree", "member_details", "diwaniyas", "projects", "library", "contact", "notifications", "profile"],
      "الشاشات بالترتيب")
check(S.allCases.allSatisfy { s in s.parent.map { s.rawValue.hasPrefix($0.rawValue + ".") } ?? !s.rawValue.contains(".") }, true,
      "كل ابن تحت أمّه بالاسم")
check(Set(S.allCases.map(\.rawValue)).count, S.allCases.count, "بلا تكرار")

// ── ٧) ملخّص البطاقة ──
check(A.hiddenCounts(category: .limited, matrix: empty, legacyLimited: nil).screens, 5, "المحدود: 5 شاشات مخفية")
check(A.hiddenCounts(category: .familyMan, matrix: empty, legacyLimited: nil).screens, 0, "العضو: لا شيء مخفي")
let one = A.setting(.newsComment, to: false, category: .familyWoman, matrix: empty)
check(A.hiddenCounts(category: .familyWoman, matrix: one, legacyLimited: nil).inner, 1, "خيار داخلي واحد")
check(A.isCustom(category: .familyWoman, matrix: one), true, "مخصّص")
check(A.isCustom(category: .familyMan, matrix: one), false, "غيره افتراضي")
check(A.summaryAr(category: .limited, matrix: empty, legacyLimited: nil), "5 شاشات مخفية", "النص بالعربي")
check(A.summaryAr(category: .familyMan, matrix: empty, legacyLimited: nil), "كل الشاشات", "كامل")
check(A.summaryAr(category: .familyWoman, matrix: one, legacyLimited: nil), "خيار مخفي واحد", "مفرد")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
