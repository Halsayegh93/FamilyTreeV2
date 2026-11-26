// فحص منطق مربّع الطلب (Views/Features/Admin/AdminRequestBoxLogic.swift، الوحدة U9) — بلا محاكي:
//   xcrun swiftc -o /tmp/u9-logic FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminRequestBoxLogic.swift \
//     tests/admin-redesign/U9/main.swift && /tmp/u9-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias B = AdminRequestBoxLogic

// MARK: الطلب التالي (T3: ثلاث موافقات متتالية تنتهي بـ«كل الطلبات عولجت»)
let order = ["a", "b", "c", "d"]
check(B.next(after: "b", order: order, pending: ["a", "c", "d"]), "c", "next = the one after, by id")
check(B.next(after: "d", order: order, pending: ["a", "b", "c"]), "a", "after the last it wraps to the first still pending")
check(B.next(after: "b", order: order, pending: ["a", "d"]), "d", "skips handled ones (c left the list)")
check(B.next(after: "b", order: order, pending: ["b"]), nil as String?, "the current one is never picked again")
check(B.next(after: "x", order: order, pending: ["c", "d"]), "c", "current not in the list (filters changed) → first pending")
check(B.next(after: "a", order: [], pending: []), nil as String?, "empty list → nil")
// ثلاثة طلبات تُعالج تباعاً
var pending: Set<String> = ["r1", "r2", "r3"]
var current: String? = "r1"
var steps: [String] = []
while let c = current {
    steps.append(c)
    pending.remove(c)
    current = B.next(after: c, order: ["r1", "r2", "r3"], pending: pending)
}
check(steps, ["r1", "r2", "r3"], "three decisions in a row walk r1 → r2 → r3")
check(B.endTitle(othersOutsideFilter: false, arabic: true), "كل الطلبات عولجت", "the third ends on «كل الطلبات عولجت»")
check(B.endTitle(othersOutsideFilter: true, arabic: true), "عولجت كل الطلبات بهذه التصفية", "filtered end says so (F3: «تصفية»)")

// MARK: شريط المراحل
check(B.trackStep(stage: "review"), 1, "review = المختص")
check(B.trackStep(stage: "info"), 1, "info stays on المختص")
check(B.trackStep(stage: "approve"), 2, "approve = الاعتماد")
check(B.trackStep(stage: "execute"), 3, "execute = التنفيذ")
check(B.trackStep(stage: "?"), 0, "unknown = وصل")

// MARK: بعد القرار
check(B.outcome(succeeded: true, stillPending: true, handlerIsMe: false), .success, "a confirmed answer = success")
check(B.outcome(succeeded: false, stillPending: true, handlerIsMe: false), .failed, "error and still pending = stay")
check(B.outcome(succeeded: false, stillPending: false, handlerIsMe: false), .handledElsewhere, "gone, by someone else = show who, then advance")
check(B.outcome(succeeded: false, stillPending: false, handlerIsMe: true), .success, "timeout but it was applied by me = success")

// MARK: الشريط السفلي: زرّان + «المزيد»
check(B.barSplit(decisions: 1, extras: 0).buttons, 1, "one decision = one button")
check(B.barSplit(decisions: 2, extras: 0).more, 0, "two decisions, nothing more")
check(B.barSplit(decisions: 3, extras: 1).buttons, 2, "never more than two buttons")
check(B.barSplit(decisions: 3, extras: 1).more, 2, "the third decision and the extras go to «المزيد»")

// MARK: سطر الخطأ
check(B.failureLine("الرقم مستخدم من عضو آخر — لم يُطبَّق شيء.", arabic: true),
      "تعذّر التنفيذ: الرقم مستخدم من عضو آخر — لم يُطبَّق شيء.", "hint message gets the «تعذّر التنفيذ:» lead")
check(B.failureLine("تعذّر تنفيذ القرار — لم يُطبَّق شيء. حاول مرة أخرى.", arabic: true),
      "تعذّر تنفيذ القرار — لم يُطبَّق شيء. حاول مرة أخرى.", "no double «تعذّر»")
check(B.failureLine("  ", arabic: true), "تعذّر التنفيذ — لم يُطبَّق شيء. حاول مرة أخرى.", "empty → generic line")
check(B.minimumLock >= 0.8, true, "the bar stays off at least 0.8 s")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
