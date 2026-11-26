// فحص منطق ورقة العضو (Views/Features/Admin/AdminMemberSheetLogic.swift، الوحدة U13) — بلا محاكي:
//   xcrun swiftc -o /private/tmp/claude-501/u13-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMemberSheetLogic.swift tests/admin-redesign/U13/main.swift \
//     && /private/tmp/claude-501/u13-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias L = AdminMemberSheetLogic

// MARK: شريط «السابق · 3 من 123 · التالي» — يختفي بلا قائمة (spec C.10 / plan rule 2: معرّف واحد = بلا شريط)
check(L.showsStepBar(count: 1), false, "one id (search, notice, request box) → no prev/next bar")
check(L.showsStepBar(count: 0), false, "no ids → no bar")
check(L.showsStepBar(count: 2), true, "a list of two → bar")
check(L.canStep(next: true, position: 0, count: 1), false, "single id → «التالي» off")
check(L.canStep(next: false, position: 0, count: 5), false, "first → «السابق» off")
check(L.canStep(next: true, position: 0, count: 5), true, "first → «التالي» on")
check(L.canStep(next: true, position: 4, count: 5), false, "last → «التالي» off")
check(L.canStep(next: false, position: 4, count: 5), true, "last → «السابق» on")
check(L.stepped(next: true, position: 4, count: 5), 4, "«التالي» on the last stays")
check(L.stepped(next: true, position: 2, count: 5), 3, "«التالي» moves one")
check(L.stepped(next: false, position: 2, count: 5), 1, "«السابق» moves one back")
check(L.counter(position: 2, count: 123).current, 3, "«3 من 123»: current = position + 1")
check(L.counter(position: 2, count: 123).total, 123, "«3 من 123»: total = list count")

// MARK: بداية الورقة
check(L.clampedStart(7, count: 3), 2, "start past the end clamps to the last")
check(L.clampedStart(-4, count: 3), 0, "negative start clamps to 0")
check(L.clampedStart(5, count: 0), 0, "empty list → 0")

// MARK: صفّ «منع الرقم من التسجيل» — الرقم المملوء (T4): مطبَّع، لا رقم مخفي، ولا شيء يُرسل من هنا
/// بديل `KuwaitPhone` في الفحص: ٨ أرقام كويتية (بعد حذف 965/00965) أو «+رمز…» للأجنبي، وإلا nil
func fakeNormalize(_ raw: String) -> String? {
    var digits = raw.filter(\.isNumber)
    let international = raw.hasPrefix("+") || raw.hasPrefix("00")
    if digits.hasPrefix("00") { digits = String(digits.dropFirst(2)) }
    if digits.hasPrefix("965"), digits.count == 11 { return String(digits.dropFirst(3)) }
    if digits.count == 8, !international { return digits }
    return international && digits.count >= 9 ? "+" + digits : nil
}

check(L.banPrefill("99991234", normalize: fakeNormalize), "99991234", "local Kuwaiti number → 8 digits")
check(L.banPrefill("+965 9999 1234", normalize: fakeNormalize), "99991234", "+965 spaced → 8 digits")
check(L.banPrefill("  +966512345678 ", normalize: fakeNormalize), "+966512345678", "foreign number keeps its code")
check(L.banPrefill("+965 •••• 4417", normalize: fakeNormalize), nil, "masked «••••» never passes")
check(L.banPrefill("*****1234", normalize: fakeNormalize), nil, "masked «*» never passes")
check(L.banPrefill("9999xx34", normalize: fakeNormalize), nil, "letters = masked, never passes")
check(L.banPrefill("", normalize: fakeNormalize), nil, "empty → nil")
check(L.banPrefill(nil, normalize: fakeNormalize), nil, "no phone → nil")
check(L.banPrefill("   ", normalize: fakeNormalize), nil, "blank → nil")
check(L.banPrefill("123", normalize: fakeNormalize), nil, "not a number the server stores → nil")
check(L.banPrefill("99991234", normalize: { _ in "+965 ••••" }), nil, "a normaliser that returns a masked value is refused too")

// MARK: «اتصال»/«واتساب» — رقم ظاهر وغير مخفي فقط
check(L.canContact("+965 9999 1234"), true, "visible number → call/WhatsApp")
check(L.canContact("٩٩٩٩١٢٣٤"), true, "Arabic digits count as a number")
check(L.canContact(nil), false, "hidden from this viewer → no call/WhatsApp")
check(L.canContact("+965 •••• 4417"), false, "masked → no call/WhatsApp")
check(L.isMasked("(+965) 9999-1234"), false, "brackets and dashes are not a mask")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
