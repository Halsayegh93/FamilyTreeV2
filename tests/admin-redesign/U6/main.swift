// فحص منطق بطاقة «العائلة» (Views/Features/Admin/AdminCensusRings.swift، الوحدة U6) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u6-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminCensusRings.swift tests/admin-redesign/U6/main.swift && /tmp/u6-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

L10n.isArabic = true

// MARK: أرقام اليوم (٢٠٢٦-١١-٢٦)
let elders = Set((0..<41).map { _ in UUID() })
let today = AdminCensusFigures(men: 2_729, menAlive: 2_362, women: 262, womenAlive: 127,
                               menAccounts: 123, womenAccounts: 47,
                               outsideLiving: 50, oldLiving: elders)

check(today.total, 2_991, "total = men + women")
check(today.totalAlive, 2_489, "living = 2,362 + 127")
check(today.menDeceased, 367, "men deceased")
check(today.womenDeceased, 135, "women deceased")
check(today.totalDeceased, 502, "deceased")
check(today.inApp, 170, "in the app = 123 + 47 (setFamilyAccounts)")

// MARK: نسبة الأحياء في وسط الحلقة (spec C.1: 83٪ / 87٪ / 48٪)
check(today.livingShare(.total), 83, "total share 83")
check(today.livingShare(.men), 87, "men share 87 (rounded, not floored)")
check(today.livingShare(.women), 48, "women share 48")
check(AdminCensusMath.livingShare(alive: 996, of: 1_000), 99, "never 100 before it is complete")
check(AdminCensusMath.livingShare(alive: 1, of: 1_000), 1, "never 0 with someone living")
check(AdminCensusMath.livingShare(alive: 10, of: 10), 100, "complete = 100")
check(AdminCensusMath.livingShare(alive: 0, of: 10), 0, "none = 0")
check(AdminCensusMath.livingShare(alive: 5, of: 0), nil, "empty group → no share")
check(AdminCensusMath.livingShare(alive: nil, of: 10), nil, "not loaded → no share")
check(AdminCensusFigures().progress(.men), nil, "not loaded → empty track")
check(today.progress(.women).map { ($0 * 1000).rounded() }, 485, "women progress 0.485")

// MARK: «—» والصفر لا يُضغطان
check(AdminCensusMath.opens(value: 170, hasAction: true), true, "number with action opens")
check(AdminCensusMath.opens(value: 0, hasAction: true), false, "zero opens nothing")
check(AdminCensusMath.opens(value: nil, hasAction: true), false, "«—» opens nothing")
check(AdminCensusMath.opens(value: 170, hasAction: false), false, "no action, no chevron")
check(AdminCensusText.number(nil), "—", "not loaded = «—», never 0")
check(AdminCensusText.number(2_991), "2,991", "thousands separator")
var noAccounts = today
noAccounts.womenAccounts = nil
check(noAccounts.inApp, nil, "in the app waits for both account lists")

// MARK: «≈» تقديري
check(today.unverified(verified: []), 41, "41 elders unchecked")
check(today.unverified(verified: Set(elders.prefix(40))), 1, "one left")
check(today.isEstimated(.men, verified: []), true, "men share estimated")
check(today.isEstimated(.total, verified: []), true, "total share estimated")
check(today.isEstimated(.women, verified: []), false, "women never estimated (elders are men)")
check(today.isEstimated(.men, verified: elders), false, "all checked → exact")
var noElders = today
noElders.oldLiving = nil
check(noElders.unverified(verified: []), 0, "no candidates yet → no note")

// MARK: النصوص (spec C.1 / C.12)
check(AdminCensusText.inAppSub(living: 2_489), "من 2,489 حياً", "in-app sub")
check(AdminCensusText.outsideLivingSub, "أحياء", "outside sub = living only (F1)")
check(AdminCensusText.split(men: 2_362, women: 127), "2,362 رجل و127 امرأة", "living split")
check(AdminCensusText.split(men: 367, women: 135), "367 رجل و135 امرأة", "deceased split")
check(AdminCensusText.split(men: 5, women: 2), "5 رجال وامرأتان", "small counts")
check(AdminCensusText.living(103), "103 أحياء", "103 → few")
check(AdminCensusText.living(100), "100 حيّ", "100 → single")
check(AdminCensusText.percent(83), "83٪", "percent")

// MARK: القارئ الصوتي (spec A.17)
check(AdminCensusText.ringSpoken(.men, count: 2_729, share: 87, estimated: false, opens: true),
      "الرجال: 2,729، 87 بالمئة أحياء. يفتح القائمة", "ring sentence")
check(AdminCensusText.ringSpoken(.total, count: 2_991, share: 83, estimated: true, opens: false),
      "الإجمالي: 2,991، نحو 83 بالمئة أحياء (تقديري)", "estimated ring, no action")
check(AdminCensusText.ringSpoken(.women, count: nil, share: nil, estimated: false, opens: true),
      "النساء: لم يصل العدد بعد", "ring not loaded")
check(AdminCensusText.rowSpoken(title: "في التطبيق", value: 170, sub: "من 2,489 حياً", opens: true),
      "في التطبيق: 170، من 2,489 حياً. يفتح القائمة", "row sentence")
check(AdminCensusText.estimateSpoken(unverified: 41, opens: true).contains("41 من كبار السن"), true,
      "estimate sentence names the count")
check(AdminCensusText.estimateSpoken(unverified: 41, opens: true).contains("≈"), false, "no «≈» glyph read aloud")

// MARK: T2 — الوجهات والرقم الذي تساويه القائمة
check(AdminCensusRoutes.destination(.total, on: .today, seesWomenPage: true), .stats(.family), "today total → stats family")
check(AdminCensusRoutes.destination(.total, on: .stats, seesWomenPage: true), .none, "stats total → its own home")
check(AdminCensusRoutes.destination(.men, on: .today, seesWomenPage: true),
      .members(AdminMembersLanding(account: .all, life: .all)), "men → family root, filters cleared")
check(AdminCensusRoutes.destination(.women, on: .today, seesWomenPage: true),
      .women(AdminWomenLanding(status: .all, branch: .all)), "women → family women, status all")
check(AdminCensusRoutes.destination(.women, on: .today, seesWomenPage: false), .womenTree, "monitor → women tree")
check(AdminCensusRoutes.destination(.inApp, on: .today, seesWomenPage: true), .stats(.inApp), "170 → stats in-app")
check(AdminCensusRoutes.destination(.outside, on: .today, seesWomenPage: true), .stats(.outside), "50 → stats outside")
check(AdminCensusRoutes.destination(.estimate, on: .today, seesWomenPage: true),
      .members(AdminMembersLanding(review: .living)), "≈ → «هل ما زالوا أحياء؟»")
check(today.value(of: .men), 2_729, "men list must hold 2,729")
check(today.value(of: .women), 262, "women list must hold 262")
check(today.value(of: .inApp), 170, "in-app headline 170")
check(today.value(of: .outside), 50, "outside headline 50")
check(today.value(of: .total), 2_991, "family rings total 2,991")

L10n.isArabic = false
check(AdminCensusText.ringSpoken(.men, count: 2_729, share: 87, estimated: false, opens: true),
      "Men: 2,729, 87% living. Opens the list", "english ring sentence")
check(AdminCensusText.split(men: 2_362, women: 127), "2,362 men and 127 women", "english split")
L10n.isArabic = true

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
