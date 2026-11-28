// فحص أدوات T0 (Core/DebugAdminProbe.swift) بلا محاكي: قارئ الأعلام ومقياس المكدس على الخيط الرئيسي للماك
//   xcrun swiftc -Onone -D DEBUG -D DEBUG_PROBE_TEST -o /private/tmp/claude-501/t0probe \
//     FamilyTreeV2/FamilyTreeV2/Core/DebugAdminProbe.swift tests/admin-redesign/T0/main.swift && /private/tmp/claude-501/t0probe
import Foundation

var failures = 0
func check(_ ok: Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
    if ok { print("PASS \(label)") } else { print("FAIL \(label) \(detail())"); failures += 1 }
}

// MARK: الأعلام

func args(_ a: String...) -> DebugArgs { DebugArgs(["app"] + a) }

var a = args("-tmpAdminRole", "monitor")
check(a.adminRole == "monitor" && a.errors.isEmpty && a.isDryRun && a.anyActive, "role monitor", "\(a)")
a = args("-tmpAdminRole", "monitr")
check(a.adminRole == nil && a.errors.count == 1 && a.isDryRun, "unknown role → error + still dry-run", "\(a.errors)")
a = args("-tmpAdminRole")
check(a.adminRole == nil && a.errors.count == 1, "role without value → error")
a = args("-tmpAdminRole", "-tmpStackDepth")
check(a.errors.count == 1 && a.stackDepth, "role followed by a flag → error, flag still read")
a = args("-tmpStackDepth", "-tmpStackCheck")
check(a.stackDepth && a.stackCheck && a.errors.isEmpty && !a.isDryRun, "stack flags")
a = args("-tmpStackDepth", "YES", "-tmpStackCheck", "0")
check(a.stackDepth && !a.stackCheck && a.errors.isEmpty, "bool values")
a = args("-tmpStackDepth", "maybe")
check(a.errors.count == 1, "bool unknown value → error")
a = args("-tmpFailStores", "sms,devices@20, usage")
check(a.failStores == [.sms: 0, .devices: 20, .usage: 0] && a.errors.isEmpty && !a.isDryRun, "fail stores list", "\(a.failStores)")
a = args("-tmpFailStores", "sms,foo,devices@x,census@2.5")
check(a.failStores == [.sms: 0, .census: 2.5] && a.errors.count == 2, "fail stores unknown name / bad seconds", "\(a.failStores) \(a.errors)")
a = args("-tmpFailStores")
check(a.failStores.isEmpty && a.errors.count == 1, "fail stores without value → error")
a = args("-tmpRoleMatrix", #"{"monitor":{"areas":{"team":"read"}}}"#)
check(a.roleMatrix?["monitor"] != nil && a.isDryRun && a.errors.isEmpty, "role matrix json")
a = args("-tmpRoleMatrix", "[1]")
check(a.roleMatrix == nil && a.errors.count == 1 && a.isDryRun, "role matrix not an object → error")
a = args("-tmpStackDeep")
check(a.errors.count == 1 && a.anyActive, "unknown flag in the family → error")
a = args("-tmpOfflineFrom", "5", "-tmpNewDots", "-uiPreviewJoinCard", "box")
check(!a.anyActive && a.errors.isEmpty, "other -tmp flags untouched")
a = args("-tmpAdminRole", "supervisor", "-tmpFailStores", "sms,devices@20", "-tmpStackDepth")
check(a.summary == "role=supervisor · fail=sms,devices@20 · stack=depth · DRY-RUN", "summary", a.summary)

// MARK: مقياس المكدس

@inline(never) func keep(_ p: UnsafeMutableRawBufferPointer) { if p.count == 0 { print("") } }

/// يستهلك المكدس: إطار فيه ٥١٢ بايت حيّة، ويسجّل أعمق عنوان
@inline(never) func burn(_ n: Int, _ deepest: inout UInt) {
    var pad: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
              UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64) = (UInt64(n), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    var pad2 = pad
    withUnsafeMutableBytes(of: &pad) { keep($0) }
    withUnsafeMutableBytes(of: &pad2) { keep($0) }
    let here = DebugStackMeter.here()
    if here < deepest { deepest = here }
    if n > 0 { burn(n - 1, &deepest) }
}

guard let meter = DebugStackMeter() else { print("FAIL meter init"); exit(1) }
print("meter spanKB=\(meter.spanKB)")
_ = meter.endTurn()   // الطلاء الأول
check(meter.endTurn() == nil, "quiet turn → nil")

for frames in [200, 800] {
    var deepest = UInt.max
    burn(frames, &deepest)
    let low = meter.endTurn()
    let truthKB = meter.depthKB(deepest)
    let gotKB = low.map(meter.depthKB) ?? -1
    check(low != nil && low! <= deepest && deepest - low! < 8 * 1024,
          "turn high-water \(frames) frames: truth \(truthKB) KB, measured \(gotKB) KB", "low=\(String(describing: low)) deepest=\(deepest)")
}
check(meter.endTurn() == nil, "after repaint the next quiet turn → nil")

// فحص داخل الدورة: الكلفة من نقطة الدخول
do {
    let entry = meter.checkBegin()
    var deepest = UInt.max
    burn(300, &deepest)
    let low = meter.checkEnd()
    let truthKB = Int((entry - deepest) / 1024)
    let stepKB = low < entry ? Int((entry - low) / 1024) : 0
    check(low <= deepest && abs(stepKB - truthKB) <= 8, "check step: truth \(truthKB) KB, measured \(stepKB) KB")
    let turn = meter.endTurn()
    check(turn != nil && turn! <= low, "turn after a check keeps the check's depth")
}

// فحص صغير جداً: لا ينزل تحت هامش الفحص → خطوة صغيرة (≤ الهامش + إطار)
do {
    let entry = meter.checkBegin()
    let low = meter.checkEnd()
    let stepKB = low < entry ? Int((entry - low) / 1024) : 0
    check(stepKB <= 6, "tiny check stays under the margin: \(stepKB) KB")
    _ = meter.endTurn()
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
