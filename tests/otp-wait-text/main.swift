// فحص محلّل «انتظر N ثانية/دقيقة» لشاشة طلب الرمز (Core/OTPWaitText.swift) — بلا محاكي:
//   xcrun swiftc -o /tmp/otpwait FamilyTreeV2/FamilyTreeV2/Core/OTPWaitText.swift tests/otp-wait-text/main.swift && /tmp/otpwait
import Foundation
// فحص محلّل «انتظر N» — يُبنى مع Core/OTPWaitText.swift
var failures = 0
func check(_ got: String?, _ want: String?, _ label: String) {
    if got == want { print("PASS \(label): \(got ?? "nil")") } else { print("FAIL \(label): got \(got ?? "nil") want \(want ?? "nil")"); failures += 1 }
}
for (n, want) in [(50, "انتظر 50 ثانية"), (120, "انتظر دقيقتين"), (180, "انتظر 3 دقائق"), (61, "انتظر دقيقتين"),
                  (60, "انتظر دقيقة"), (1, "انتظر ثانية واحدة"), (2, "انتظر ثانيتين"), (7, "انتظر 7 ثوانٍ"), (600, "انتظر 10 دقائق"), (601, "انتظر 11 دقيقة")] {
    let text = "api(message: \"Please wait \(n) seconds before requesting another code\", errorCode: over_sms_send_rate_limit)"
    let secs = OTPWaitText.seconds(in: text)
    check(secs.map { OTPWaitText.waitPhrase(seconds: $0, arabic: true) }, want, "wait \(n)")
}
check(OTPWaitText.message(from: "For security purposes, you can only request this after 42 seconds.", arabic: true),
      "انتظر 42 ثانية قبل طلب رمز جديد.", "supabase after 42")
check(OTPWaitText.message(from: "PLEASE WAIT 1 SECOND", arabic: false), "Wait 1 second before requesting a new code.", "english 1 s")
check(OTPWaitText.message(from: "please wait 125 seconds", arabic: false), "Wait 3 minutes before requesting a new code.", "english 125 s")
check(OTPWaitText.message(from: "429 too many requests", arabic: true), nil, "no number → fallback")
check(OTPWaitText.message(from: "wait 0 seconds", arabic: true), nil, "zero → fallback")
check(OTPWaitText.exactDuration(seconds: 90, arabic: true), "90 ثانية", "exact 90")
check(OTPWaitText.exactDuration(seconds: 120, arabic: true), "دقيقتين", "exact 120")
check(OTPWaitText.exactDuration(seconds: 300, arabic: true), "5 دقائق", "exact 300")
print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
