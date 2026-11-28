// فحص «تغيير الرقم لصاحب الحساب فقط» (Core/ErrorHelper.swift، الوحدة Q1، المالك ٢٠٢٦-١١-٢٧ «رقمه فقط») — بلا محاكي:
//   xcrun swiftc -o /private/tmp/claude-501/q1-logic \
//     FamilyTreeV2/FamilyTreeV2/Core/ErrorHelper.swift tests/admin-redesign/Q1/main.swift \
//     && /private/tmp/claude-501/q1-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

struct FakeError: Error, CustomStringConvertible {
    let description: String
}

check(ErrorHelper.adminRequestMessage(FakeError(description: "PostgrestError(code: P0001, hint: admin_request_phone_not_self)")),
      "تغيير الرقم متاح لصاحب الحساب فقط.", "phone_not_self → formal Arabic")
check(ErrorHelper.adminRequestMessage(FakeError(description: "ADMIN_REQUEST_PHONE_NOT_SELF")),
      "تغيير الرقم متاح لصاحب الحساب فقط.", "case-insensitive")
check(ErrorHelper.adminRequestMessage(FakeError(description: "network timeout")), nil, "other errors → nil (generic message)")
check(ErrorHelper.phoneNotSelfMessage.contains("أبوك") || ErrorHelper.phoneNotSelfMessage.contains("أمك"), false, "formal wording")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
