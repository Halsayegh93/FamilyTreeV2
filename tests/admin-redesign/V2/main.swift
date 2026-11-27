// فحص منطق «اليوم» v2 — الاتجاه «أ» (Views/Features/Admin/AdminTodayBandLogic.swift وحبّة المربّع في AdminTileKit.swift،
// الوحدة V2-1) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/v2-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTileKit.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminCensusRings.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTodayLogic.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminNoticeLogic.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTodayBandLogic.swift tests/admin-redesign/V2/main.swift && /tmp/v2-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias Band = AdminTodayBandLogic

// MARK: ١) عدد الجرس = «يحتاج إجراء N» (spec V2-1 البند ٢) — لا غير المقروء وحده

let pending = UUID()
let decided = UUID()
let open: Set<UUID> = [pending]

check(Band.needsAction(AdminBellNotice(category: .action, read: true, requestId: pending), open: open), true,
      "request still pending → needs action (even if read)")
check(Band.needsAction(AdminBellNotice(category: .action, read: false, requestId: decided), open: open), false,
      "request already decided → not counted (even if unread)")
check(Band.needsAction(AdminBellNotice(category: .action, read: false), open: open), true,
      "request with no known id → while unread")
check(Band.needsAction(AdminBellNotice(category: .action, read: true), open: open), false,
      "request with no known id, read → no")
check(Band.needsAction(AdminBellNotice(category: .action, read: false, suspicious: true), open: open), true,
      "suspicious sign-in unread → needs action")
check(Band.needsAction(AdminBellNotice(category: .action, read: true, suspicious: true), open: open), false,
      "suspicious sign-in read → no")
check(Band.needsAction(AdminBellNotice(category: .changes, read: false, selfChildReview: true), open: open), true,
      "added son «راجعه» unread → needs action")
check(Band.needsAction(AdminBellNotice(category: .changes, read: false), open: open), false,
      "member change unread → not counted")
check(Band.needsAction(AdminBellNotice(category: .team, read: false), open: open), false, "team activity unread → no")
check(Band.needsAction(AdminBellNotice(category: .system, read: false), open: open), false, "system unread → no")
check(Band.needsAction(AdminBellNotice(category: nil, read: false), open: open), false, "not an admin notice → no")

let notices: [AdminBellNotice] = [
    AdminBellNotice(category: .action, read: false, requestId: pending),                    // ١
    AdminBellNotice(category: .action, read: false, requestId: decided),                    // —
    AdminBellNotice(category: .action, read: false, suspicious: true),                      // ١
    AdminBellNotice(category: .changes, read: false),                                       // —
    AdminBellNotice(category: .team, read: false),                                          // —
    AdminBellNotice(category: .action, read: false, contactMessage: true),                  // ١ لمن يرى الرسائل
]
check(Band.bellCount(derived: 2, notices: notices, open: open, seesMessages: true), 5,
      "bell = 2 derived + 3 waiting (owner sees messages)")
check(Band.bellCount(derived: 2, notices: notices, open: open, seesMessages: false), 4,
      "bell drops the member-message notice for a role without messages")
check(Band.bellCount(derived: 0, notices: [AdminBellNotice(category: .team, read: false),
                                           AdminBellNotice(category: .changes, read: false)],
                     open: [], seesMessages: true), 0,
      "only unread (no action) → no badge number")
check(Band.bellBadge(0), nil, "0 → no badge")
check(Band.bellBadge(2), "2", "2 → «2»")
check(Band.bellBadge(120), "99+", "over 99 → «99+»")

// MARK: ٢) مربّع «العائلة»: «5 قوائم للمراجعة» (قوائم «يحتاج مراجعتك» التي فيها أحد) أو «سليمة»

// بترتيب `AdminReviewHubLogic.List`: مشكلات · أحياء؟ · وفاة · بيانات · لم يفتحوا · لم يدخلوا
check(Band.reviewListsWord(counts: [4, 41, 363, 12, 2_177, 0])?.state, AdminTileState.neutral("5 قوائم للمراجعة"),
      "five busy lists → «5 قوائم للمراجعة» (calm word, not a pill)")
check(Band.busyLists([4, 41, 363, 12, 2_177, 0]), 5, "the «5 قوائم» number")
check(Band.reviewListsWord(counts: [4, 41, 363, 12, 2_177, 0])?.landing, nil,
      "opens «العائلة» root (its «يحتاج مراجعتك» row) — no new landing")
check(Band.reviewListsWord(counts: [0, 0, 363, 0, 0, 0])?.state.text, "قائمة واحدة للمراجعة", "one list")
check(Band.reviewListsWord(counts: [3, 0, 363, 0, 0, 0])?.state.text, "قائمتان للمراجعة", "two lists")
check(Band.reviewListsWord(counts: [3, 1, 363, 2, 5, 9])?.state.text, "6 قوائم للمراجعة", "six lists")
check(Band.reviewListsWord(counts: [0, 0, 0, 0, 0, 0])?.state, AdminTileState.good("سليمة"),
      "every list arrived empty → «سليمة» ✓")
check(Band.reviewListsWord(counts: [0, 0, 0, 0, nil, nil]), nil,
      "no «سليمة» before the account lists arrive")
check(Band.reviewListsWord(counts: [0, 41, 0, 0, nil, nil])?.state.text, "قائمة واحدة للمراجعة",
      "busy lists said while account lists still loading")
check(Band.reviewListsWord(counts: [nil, nil, nil, nil, nil, nil]), nil, "nothing arrived → skeleton")
check(Band.busyLists([nil, nil]), nil, "nothing arrived → no number")
check(Band.listsText(11), "11 قائمة للمراجعة", "11 lists (single noun)")

// MARK: ٣) مربّع «الإحصاءات»: «الراحلون 502»

check(Band.departedWord(502)?.state, AdminTileState.neutral("الراحلون 502"), "departed word")
check(Band.departedWord(502)?.landing, .stats(.family), "opens «العائلة» where «متوفون 502» is (F4, V16)")
check(Band.departedWord(1_502)?.state.text, "الراحلون 1,502", "thousands separator")
check(Band.departedWord(nil), nil, "before the numbers → no word (skeleton)")

// MARK: ٤) المربّع المسطّح: الحبّة البيضاء لما ينتظرك وحده

let now = Date()
func line(_ state: AdminTileState?, _ health: AdminStoreHealth?, readOnly: Bool = false) -> AdminTileLine {
    AdminTileLine.make(state: state, health: health, readOnly: readOnly)
}
check(line(.attention("1 بانتظار ردّك"), .loaded(at: now)).pill, .attention, "inbox waiting → navy pill")
check(line(.urgent("محاولة مريبة"), .loaded(at: now)).pill, .urgent, "suspicious attempt → red pill")
check(line(.urgent("الصيانة مفعّلة"), .loaded(at: now)).pill, .urgent, "maintenance on → red pill")
check(line(.neutral("لا شيء قريب"), .loaded(at: now)).pill, nil, "calm word → plain line")
check(line(.good("يعمل للجميع"), .loaded(at: now)).pill, nil, "good word → plain line with ✓")
check(line(.neutral("5 قوائم للمراجعة"), .loaded(at: now)).pill, nil, "review lists → plain line")
check(line(.attention("1 بانتظار ردّك"), .loading).pill, nil, "loading → skeleton, no pill")
check(line(.attention("1 بانتظار ردّك"), .loading).kind, .skeleton, "loading never says «تعذّر التحميل»")
check(line(.attention("1 بانتظار ردّك"), .failed(lastGood: nil)).pill, nil, "failed → «تعذّر التحميل ↻», no pill")
let staleLine = line(.attention("1 بانتظار ردّك"), .failed(lastGood: now))
check(staleLine.pill, .attention, "stale data keeps its pill")
check(staleLine.staleSince != nil, true, "stale data adds «آخر تحديث»")
let readOnlyLine = line(.attention("الرصيد منخفض"), .loaded(at: now), readOnly: true)
check(readOnlyLine.pill, .attention, "read-only keeps the pill")
check(readOnlyLine.readOnlyMark, true, "read-only keeps the eye")
check(readOnlyLine.spoken, "الرصيد منخفض، للاطلاع", "VoiceOver: word + «للاطلاع»")
check(line(nil, .loaded(at: now), readOnly: true).pill, nil, "«للاطلاع» alone → plain")

// MARK: ٥) سطر التحية حبّةً: حين يقول شيئاً فقط

check(Band.showsSmartPill(nil), false, "loading → no pill")
check(Band.showsSmartPill(AdminSmartLine(text: AdminTodayLogic.calmText, link: nil)), false, "quiet day → no pill")
var smart = AdminTodayLogic.SmartInput()
smart.policy = 1
let policyLine = AdminTodayLogic.smartLine(smart)
check(Band.showsSmartPill(policyLine), true, "privacy request waiting → pill")
check(policyLine?.link?.home, .inbox, "pill opens «الوارد» (same destination as today)")
check(Band.showsSmartPill(AdminTodayLogic.smartLine(AdminTodayLogic.SmartInput())), false, "nothing → no pill")
check(Band.showsSmartPill(AdminSmartLine(text: "اليوم ذكرى وفاة فلان", link: nil)), true,
      "a fact whose home this role can't open is still said (no chevron)")

// MARK: ٦) رابطا الرأس: «46 حياً» (الأحياء وحدهم)

check(AdminCensusText.livingNoun(46), "حياً", "46 حياً")
check(AdminCensusText.livingNoun(3), "أحياء", "3 أحياء")
check(AdminCensusText.livingNoun(1), "حيّ", "1 حيّ")
check(AdminCensusText.livingNoun(2), "حيّان", "2 حيّان")
check(AdminCensusText.livingNoun(111), "حياً", "111 حياً")
check(AdminCensusText.livingNoun(100), "حيّ", "100 حيّ")
check(AdminCensusText.inAppSub(living: 2_489), "من 2,489 حياً", "stats card: «من 2,489 حياً»")
check(AdminCensusText.inAppOfTotal(2_991), "من 2,991", "band: «في التطبيق 170 من 2,991»")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
