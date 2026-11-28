// فحص «حدّ التعديلات الذاتية» من السيرفر (FamilyTreeV2/FamilyTreeV2/Core/ProfileEditLimitState.swift، الوحدة PE1) — بلا محاكي:
//   xcrun swiftc -o /private/tmp/claude-501/pe1-logic \
//     FamilyTreeV2/FamilyTreeV2/Core/ProfileEditLimitState.swift tests/admin-redesign/PE1/main.swift && /private/tmp/claude-501/pe1-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}
typealias S = ProfileEditLimitState

// الردّ كما يرجعه profile_edit_limits()
let json = #"{"member_id":"d6a40577-e15f-4699-acb9-7c88711c2d61","enabled":true,"free_edits":3,"exempt":false,"fields":{"bio":{"used":3,"remaining":0,"last_edit_at":"2026-11-28T11:49:52+00:00"},"avatar":{"used":1,"remaining":2,"last_edit_at":null},"birthDate":{"used":0,"remaining":3,"last_edit_at":null},"isMarried":{"used":0,"remaining":3,"last_edit_at":null},"phoneNumber":{"used":0,"remaining":3,"last_edit_at":null},"isPhoneHidden":{"used":2,"remaining":1,"last_edit_at":null}}}"#
var s = S.parse(Data(json.utf8))!
check(s.loaded, true, "parsed = loaded")
check(s.enabled, true, "enabled")
check(s.freeEdits, 3, "free edits from the server")
check(s.canEdit("bio"), false, "bio used 3/3 → goes to the admins")
check(s.canEdit("avatar"), true, "avatar 1/3 → direct")
check(s.remaining("avatar"), 2, "avatar: 2 left")
check(s.remaining("bio"), 0, "bio: none left")
check(s.canEdit("fullName"), true, "a field the server doesn't count (name = always a request elsewhere) → not limited here")
s.record("avatar"); s.record("avatar")
check(s.canEdit("avatar"), false, "after direct saves the local copy follows the server count")
check(s.remaining("avatar"), 0, "avatar: none left")
// «إظهار الرقم» خيار خصوصية — السيرفر لا يعدّه (20261128161000)، ولا التطبيق
check(s.canEdit("isPhoneHidden"), true, "phone visibility is never limited")
s.record("isPhoneHidden")
check(s.used["isPhoneHidden"], 2, "phone visibility: nothing recorded")

// مطفأ من المالك (القيمة الحية منذ ٢٠٢٦-١٠-٢٢)
var off = S.parse(Data(#"{"enabled":false,"free_edits":3,"exempt":false,"fields":{"bio":{"used":9}}}"#.utf8))!
check(off.canEdit("bio"), true, "limit off → every edit direct")
check(off.remaining("bio"), 3, "limit off → full allowance shown")
off.record("bio")
check(off.used["bio"], 9, "limit off → the server doesn't count, nor do we")

// معفى (المالك والمدير والمراقب)
let exempt = S.parse(Data(#"{"enabled":true,"free_edits":3,"exempt":true,"fields":{"bio":{"used":5}}}"#.utf8))!
check(exempt.canEdit("bio"), true, "exempt role → direct")

// الحدّ صفر
let zero = S.parse(Data(#"{"enabled":true,"free_edits":0,"exempt":false,"fields":{}}"#.utf8))!
check(zero.canEdit("birthDate"), false, "zero free edits → every edit to the admins")

// قبل الوصول / ردّ غير مفهوم
check(S().canEdit("bio"), true, "not loaded → direct (the server trigger stays the guard)")
check(S.parse(Data("null".utf8)), nil, "null → nil")
check(S.parse(Data("{}".utf8)), nil, "no «enabled» → nil")

// خطأ المشغّل
check(S.isLimitError(hint: "edit_limit_reached"), true, "server hint recognised")
check(S.isLimitError(hint: "not_allowed"), false, "other hints aren't the limit")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
