// فحص منطق عُدّة المربّعات (Views/Features/Admin/AdminTileKit.swift، الوحدة U4) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u4-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTileKit.swift tests/admin-redesign/U4/main.swift && /tmp/u4-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Kuwait")!
let earlier = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 9, minute: 12))!

// MARK: سطر الحالة ← حال المخزن (spec A.12 / T1: لا كلمة هادئة قبل وصول بياناتها)
let calm = AdminTileState.good("يعمل للجميع")
let urgent = AdminTileState.urgent("2 عاجل")

let loaded = AdminTileLine.make(state: calm, health: .loaded(at: earlier), readOnly: false)
check(loaded.kind, .word, "loaded → the word")
check(loaded.text, "يعمل للجميع", "loaded text")
check(loaded.tone, .good, "loaded keeps the good tone")
check(loaded.staleSince, nil, "loaded is not stale")

let failedNoData = AdminTileLine.make(state: calm, health: .failed(lastGood: nil), readOnly: false)
check(failedNoData.kind, .unknown, "failed without data → unknown, never the calm word")
check(failedNoData.text, "تعذّر التحميل", "unknown says «تعذّر التحميل»")
check(failedNoData.spoken, "تعذّر التحميل", "unknown spoken")

let failedStale = AdminTileLine.make(state: urgent, health: .failed(lastGood: earlier), readOnly: false)
check(failedStale.kind, .word, "failed after a good load keeps the word")
check(failedStale.text, "2 عاجل", "stale word text")
check(failedStale.tone, .urgent, "stale keeps its tone")
check(failedStale.staleSince, earlier, "stale carries the last good time")

for h in [AdminStoreHealth.idle, .loading] {
    let line = AdminTileLine.make(state: calm, health: h, readOnly: false)
    check(line.kind, .skeleton, "\(h) → skeleton")
    check(line.spoken, "جارٍ التحميل", "\(h) spoken as loading")
}
check(AdminTileLine.make(state: nil, health: .loading, readOnly: false).text, AdminTileText.skeletonSample,
      "skeleton without a word uses the sample width")

check(AdminTileLine.make(state: calm, health: .denied, readOnly: false).kind, .none, "denied → no line, no retry")
let deniedRead = AdminTileLine.make(state: calm, health: .denied, readOnly: true)
check(deniedRead.kind, .word, "denied read-only → «للاطلاع»")
check(deniedRead.text, "للاطلاع", "denied read-only text")
check(deniedRead.tone, .neutral, "denied read-only is neutral")

// MARK: «للاطلاع» وبلا حال مخزن — F2: عين بعد الكلمة (السطر لا يلتفّ)، والكلمة وحدها حين لا كلمة حال
let readWord = AdminTileLine.make(state: .neutral("170 في التطبيق"), health: nil, readOnly: true)
check(readWord.text, "170 في التطبيق", "read-only keeps the state word alone (no « · للاطلاع» tail)")
check(readWord.readOnlyMark, true, "read-only with a word → the eye glyph")
check(readWord.spoken, "170 في التطبيق، للاطلاع", "VoiceOver still says «للاطلاع»")
let readAlone = AdminTileLine.make(state: nil, health: nil, readOnly: true)
check(readAlone.text, "للاطلاع", "read-only alone")
check(readAlone.readOnlyMark, false, "the word «للاطلاع» alone has no eye")
check(readAlone.spoken, "للاطلاع", "read-only alone spoken once")
check(AdminTileLine.make(state: .neutral("170 في التطبيق"), health: nil, readOnly: false).readOnlyMark, false,
      "editable area → no eye")
let readStale = AdminTileLine.make(state: urgent, health: .failed(lastGood: earlier), readOnly: true)
check(readStale.readOnlyMark, true, "stale read-only word keeps the eye")
check(readStale.spoken.hasPrefix("2 عاجل، للاطلاع، "), true, "stale read-only spoken: word, «للاطلاع», then the time")
check(AdminTileLine.make(state: nil, health: nil, readOnly: false).kind, .none, "no word → name only")
check(AdminTileLine.make(state: .attention(""), health: nil, readOnly: false).kind, .none, "empty word → name only")
check(AdminTileLine.make(state: .attention(""), health: nil, readOnly: true).tone, .neutral,
      "empty word + read-only is neutral")
check(AdminTileLine.make(state: .attention(""), health: nil, readOnly: true).text, "للاطلاع",
      "empty word + read-only → «للاطلاع» alone")
let urgentRead = AdminTileLine.make(state: urgent, health: .loaded(at: earlier), readOnly: true)
check(urgentRead.text, "2 عاجل", "word + read-only: the word alone")
check(urgentRead.tone, .urgent, "word + read-only keeps the word's tone")
check(urgentRead.readOnlyMark, true, "word + read-only: the eye")

// MARK: حقيقتان في سطر واحد
let two = AdminTileState.joined([.attention("5 بانتظارك"), .urgent("2 عاجل")])
check(two?.text, "5 بانتظارك · 2 عاجل", "joined keeps the order")
check(two?.tone, .urgent, "joined takes the strongest tone")
check(AdminTileState.joined([]), nil, "joined of nothing = nil")
check(AdminTileState.joined([.neutral(""), .good("سليمة")])?.text, "سليمة", "joined drops empty facts")

// MARK: الشبكة: العدد الفردي يمدّ آخر مربّع، وعمود واحد من أحجام إمكانية الوصول
check(AdminTileGridMath.columns(accessibilitySize: true, landscape: false, portrait: 2, wide: 3), 1, "AX → 1 column")
check(AdminTileGridMath.columns(accessibilitySize: true, landscape: true, portrait: 2, wide: 3), 1, "AX landscape → 1")
check(AdminTileGridMath.columns(accessibilitySize: false, landscape: false, portrait: 2, wide: 3), 2, "portrait → 2")
check(AdminTileGridMath.columns(accessibilitySize: false, landscape: true, portrait: 2, wide: 3), 3, "landscape → 3")
check(AdminTileGridMath.rows(count: 6, columns: 2), [0..<2, 2..<4, 4..<6], "6 tiles → 3 full rows")
check(AdminTileGridMath.rows(count: 5, columns: 2), [0..<2, 2..<4, 4..<5], "5 tiles → last row alone")
check(AdminTileGridMath.rows(count: 3, columns: 2), [0..<2, 2..<3], "3 tiles (monitor) → last spans")
check(AdminTileGridMath.rows(count: 1, columns: 2), [0..<1], "1 tile")
check(AdminTileGridMath.rows(count: 0, columns: 2), [], "no tiles")
check(AdminTileGridMath.rows(count: 5, columns: 3), [0..<3, 3..<5], "landscape 5 → 3 + 2")
check(AdminTileGridMath.rows(count: 4, columns: 1), [0..<1, 1..<2, 2..<3, 3..<4], "AX → one per row")
check(AdminTileGridMath.itemWidth(rowWidth: 361, items: 2, spacing: 10), 175.5, "two in a row share the width")
check(AdminTileGridMath.itemWidth(rowWidth: 361, items: 1, spacing: 10), 361, "a lone last tile spans the row")
check(AdminTileGridMath.itemWidth(rowWidth: 5, items: 2, spacing: 10), 0, "never negative")

// MARK: الإنجليزية
L10n.isArabic = false
check(AdminTileLine.make(state: nil, health: .failed(lastGood: nil), readOnly: false).text, "Couldn't load",
      "English unknown")
check(AdminTileLine.make(state: .neutral("170 in the app"), health: nil, readOnly: true).spoken,
      "170 in the app, View only", "English read-only (spoken)")
check(AdminTileLine.make(state: nil, health: nil, readOnly: true).text, "View only", "English read-only alone")
L10n.isArabic = true

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
