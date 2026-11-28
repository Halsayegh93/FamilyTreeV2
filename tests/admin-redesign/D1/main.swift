// فحص المحلّل المشترك للتواريخ (Core/DateParsing.swift، الوحدة D1 — تعليق Sentry FAMILYTREE-A/-7/-9) — بلا محاكي:
//   xcrun swiftc -o /private/tmp/claude-501/d1-logic \
//     FamilyTreeV2/FamilyTreeV2/Core/DateParsing.swift tests/admin-redesign/D1/main.swift \
//     && /private/tmp/claude-501/d1-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias P = DateParsing

// المرجع: 2026-11-27 10:00:00 UTC
let ref = Date(timeIntervalSince1970: 1_795_773_600)
check(P.isoPlain.string(from: ref), "2026-11-27T10:00:00Z", "reference date")

// ١) صيغ السيرفر (timestamptz)
check(P.iso("2026-11-27T10:00:00Z"), ref, "plain Z")
check(P.iso("2026-11-27T10:00:00+00:00"), ref, "plain +00:00")
check(P.iso("2026-11-27T13:00:00+03:00"), ref, "plain +03:00 (Kuwait)")
check(P.iso("2026-11-27T10:00:00.000Z"), ref, "fractional .000Z")
check(P.iso("2026-11-27T10:00:00.000+00:00"), ref, "fractional .000+00:00")
check(P.iso("2026-11-27T10:00:00.250Z").map { $0.timeIntervalSince(ref) }, 0.25, "fractional .250 kept")
check(P.iso("2026-11-27T10:00:00.123456+00:00").map { abs($0.timeIntervalSince(ref) - 0.123456) < 0.001 }, true,
      "postgres microseconds +00:00")

// ٢) ما ليس ISO بوقت — كما كان (nil)، واليوم وحده عبر `day`
check(P.iso("2026-11-27"), nil, "date-only is not ISO datetime (unchanged behaviour)")
check(P.iso(""), nil, "empty")
check(P.iso(nil), nil, "nil")
check(P.iso("not a date"), nil, "garbage")
var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
check(P.day("2026-11-27"), cal.date(from: DateComponents(year: 2026, month: 11, day: 27)), "date-only via day() (device tz)")
check(P.day("2026-11-27T10:00:00Z"), cal.date(from: DateComponents(year: 2026, month: 11, day: 27)), "day() uses first 10 chars")
check(P.day("2026"), nil, "day() too short")
check(P.dayLocal.string(from: cal.date(from: DateComponents(year: 1993, month: 3, day: 25))!), "1993-03-25", "dayLocal format")

// ٣) الكتابة — نفس ما كان يكتبه ISO8601DateFormatter() بلا خيارات
check(P.isoString(ref), ISO8601DateFormatter().string(from: ref), "isoString == default ISO8601DateFormatter")
check(P.isoString(ref), "2026-11-27T10:00:00Z", "isoString text")
check(P.isoFractionalString(ref.addingTimeInterval(0.5)), "2026-11-27T10:00:00.500Z", "isoFractionalString")
check(P.isoFullDate.string(from: ref), "2026-11-27", "isoFullDate (withFullDate, GMT)")
check(P.iso(P.isoFractionalString(ref)), ref, "round trip fractional")

// ٤) UTC: الميلاد للمطابقة (NameMatcher) وصيغة SQL
check(P.dayUTC.date(from: "2026-11-27"), Date(timeIntervalSince1970: 1_795_737_600), "dayUTC")
check(P.yearUTC.date(from: "1990"), Date(timeIntervalSince1970: 631_152_000), "yearUTC → Jan 1")
check(P.sqlDateTimeUTC.date(from: "2026-11-27 10:00:00"), ref, "sql datetime UTC")

// ٥) الإعداد لم يتغيّر (نفس الكائن، نفس الخيارات)
check(P.isoFractional.formatOptions, [.withInternetDateTime, .withFractionalSeconds], "isoFractional options")
check(P.isoPlain.formatOptions, ISO8601DateFormatter().formatOptions, "isoPlain options == default")
check(P.isoPlain.timeZone, ISO8601DateFormatter().timeZone, "isoPlain tz == default (GMT)")
check(P.isoFractional === P.isoFractional, true, "cached instance")

// ٥ب) نفس قيمة المحلّلين القديمين حرفياً (كسور حتى ٦ خانات، مناطق زمنية مختلفة) — الترتيب والمقارنات لا تتغيّر
let oldFrac = ISO8601DateFormatter(); oldFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
let oldPlain = ISO8601DateFormatter()
var g = SystemRandomNumberGenerator()
var mismatches: [String] = []
var samples = ["2026-11-27T10:00:00.717999-05:30", "2026-11-27T10:00:00.999999Z", "2026-11-27T10:00:00.000001Z",
               "2026-11-27T10:00:00.123Z", "2026-11-27T10:00:00.1+00:00", "1999-12-31T23:59:59.999+03:00",
               " 2026-11-27T10:00:00Z", "2026-11-27T10:00:00", "2026-11-27 10:00:00+00", "2026-11-27"]
for _ in 0..<20_000 {
    let digits = [0, 1, 2, 3, 6].randomElement(using: &g)!
    let frac = digits == 0 ? "" : "." + String(String(format: "%06d", Int.random(in: 0...999_999, using: &g)).prefix(digits))
    samples.append(String(format: "20%02d-%02d-%02dT%02d:%02d:%02d", Int.random(in: 0...40, using: &g), Int.random(in: 1...12, using: &g),
                          Int.random(in: 1...28, using: &g), Int.random(in: 0...23, using: &g), Int.random(in: 0...59, using: &g),
                          Int.random(in: 0...59, using: &g)) + frac + ["Z", "+00:00", "+03:00", "-05:30"].randomElement(using: &g)!)
}
for s in samples where P.iso(s) != (oldFrac.date(from: s) ?? oldPlain.date(from: s)) { mismatches.append(s) }
check(mismatches.prefix(3).map { $0 }, [], "iso == old fractional ?? plain (\(samples.count) strings)")
var fracMismatch: [String] = []
for s in samples where P.isoRequiringFraction(s) != oldFrac.date(from: s) { fracMismatch.append(s) }
check(fracMismatch.prefix(3).map { $0 }, [], "isoRequiringFraction == old fractional-only")
check(P.isoRequiringFraction("2026-11-27T10:00:00Z"), nil, "requiring fraction rejects plain")

// ٦) السرعة: ٢٬٩٠٠ عضو × صيغتان (ما علّق «الإدارة») — المشترك يجب أن يكون أسرع بوضوح من إنشاء محلّل لكل صف
let rows = (0..<2_900).map { i in i % 2 == 0 ? "2026-11-\(10 + i % 18)T10:00:00.123456+00:00" : "2026-11-\(10 + i % 18)T10:00:00Z" }
var t0 = Date()
var parsed = 0
for r in rows where P.iso(r) != nil { parsed += 1 }
let shared = Date().timeIntervalSince(t0)
t0 = Date()
for r in rows {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if f.date(from: r) == nil { f.formatOptions = [.withInternetDateTime]; _ = f.date(from: r) }
}
let perCall = Date().timeIntervalSince(t0)
print(String(format: "INFO 2900 rows: shared %.1f ms · per-call %.1f ms", shared * 1000, perCall * 1000))
check(parsed, 2_900, "all rows parsed")
check(shared * 10 < perCall, true, "shared at least 10x faster than per-call")

// ٧) من عدة خيوط (فك الصفوف قد يجري خارج الخيط الرئيسي)
let lock = NSLock()
var concurrentOK = 0
DispatchQueue.concurrentPerform(iterations: 2_000) { i in
    let ok = P.iso(rows[i % rows.count]) != nil && P.isoString(ref) == "2026-11-27T10:00:00Z"
    if ok { lock.lock(); concurrentOK += 1; lock.unlock() }
}
check(concurrentOK, 2_000, "concurrent parse/format")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
