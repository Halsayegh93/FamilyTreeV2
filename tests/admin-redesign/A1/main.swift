// فحص «الحركة في تحديثات اليوم» (Components/Shared/DSMotionRules.swift، الوحدة A1، طلب المالك ٢٠٢٦-١١-٢٧ «ابى انميشن
// بالتحديثات الجديدة») — بلا محاكي، يُشغَّل من جذر المستودع (يقرأ ملفات المصدر لفحص القواعد):
//   xcrun swiftc -o /private/tmp/claude-501/a1-logic \
//     FamilyTreeV2/FamilyTreeV2/Components/Shared/DSMotionRules.swift tests/admin-redesign/A1/main.swift \
//     && /private/tmp/claude-501/a1-logic
//
// ما يُفحص: الخروج أسرع من الدخول (≈ ٦٠٪) · اتجاه الانتقال بين مربّعات التسجيل في العربية والإنجليزية، والرجوع بالعكس ·
// «تقليل الحركة» = تلاشٍ بلا إزاحة ولا قفزة ولا رسم · نقاط الخطوات الثلاث · وفي المصدر: لا `repeatForever` ولا
// `Timer.publish` في ملفات الحركة الجديدة، وكل حركة جديدة من `DSMotion` (لا أزمنة حرفية في الشاشات).
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias M = DSMotionRules
typealias T = DSMotionRules.Timing

// ١) الخروج أسرع من الدخول
check(T.stepOut < T.stepIn, true, "step: exit faster than enter")
check(T.revealOut < T.revealIn, true, "reveal: exit faster than enter")
check(M.exitDuration(enter: 0.34), 0.204, "exit = 60% of enter (rounded to ms)")
check(T.stepIn <= 0.4 && T.revealIn <= 0.4, true, "transitions stay under 400 ms")
check(T.selectHold < T.stepIn, true, "selected pop holds shorter than the slide")

// ٢) اتجاه الخطوات
check(M.isForward(from: 0, to: 1), true, "choose → form is forward")
check(M.isForward(from: 1, to: 0), false, "form → choose («رجوع») is backward")
let rtlFwd = M.stepOffsets(forward: true, rtl: true, reduceMotion: false)
check(rtlFwd.insert < 0, true, "RTL forward: new box comes from the left (end of an Arabic line)")
check(rtlFwd.remove > 0, true, "RTL forward: old box leaves to the right (start of an Arabic line)")
let ltrFwd = M.stepOffsets(forward: true, rtl: false, reduceMotion: false)
check(ltrFwd.insert > 0 && ltrFwd.remove < 0, true, "LTR forward: in from the right, out to the left")
let rtlBack = M.stepOffsets(forward: false, rtl: true, reduceMotion: false)
check(rtlBack.insert, -rtlFwd.insert, "RTL back mirrors forward (insert)")
check(rtlBack.remove, -rtlFwd.remove, "RTL back mirrors forward (remove)")
check(abs(rtlFwd.insert), M.stepShift, "slide distance = stepShift")
check(M.stepShift <= 32, true, "slide is short (≤ 32 pt)")

// ٣) «تقليل الحركة»
check(M.style(reduceMotion: true), .fade, "reduce motion → fade only")
check(M.style(reduceMotion: false), .full, "motion on → full")
let rm = M.stepOffsets(forward: true, rtl: true, reduceMotion: true)
check(rm.insert == 0 && rm.remove == 0, true, "reduce motion: no slide offset")
check(M.selectHold(reduceMotion: true), 0, "reduce motion: no pop hold before moving on")
check(M.selectHold(reduceMotion: false), T.selectHold, "motion on: pop hold")
check(M.drawStart(reduceMotion: true), 1, "reduce motion: ring/ornament drawn at once")
check(M.drawStart(reduceMotion: false), 0, "motion on: ring/ornament draw from 0")

// ٤) المقاسات
check(M.selectPopScale > 1 && M.selectPopScale <= 1.1, true, "selected pop is gentle (≤ 1.1)")
check(M.tilePopScale >= 0.85 && M.tilePopScale < 1, true, "tiles pop from ≥ 0.85 (never from zero)")

// ٥) نقاط الخطوات
check(M.signupStepCount, 3, "three steps: relation · details · review")
check(M.SignupStep.review.rawValue, M.signupStepCount - 1, "review is the last dot")

// ٦) المصدر
let root = FileManager.default.currentDirectoryPath + "/FamilyTreeV2/FamilyTreeV2/"
func source(_ path: String) -> String { (try? String(contentsOfFile: root + path, encoding: .utf8)) ?? "" }
let touched = [
    "Components/Shared/DSMotionRules.swift",
    "Views/Features/Auth/SignupOriginViews.swift",
    "Views/Features/Auth/CompleteRegistrationViews.swift",
    "Views/Features/Auth/WaitingForApprovalView.swift",
    "Views/Features/Tree/MemberCardAB.swift",
    "Views/Features/Admin/AdminTodayBand.swift",
    "Views/Features/Admin/AdminTileKit.swift",
]
for path in touched {
    let s = source(path)
    check(s.isEmpty, false, "source readable: \(path)")
    check(s.contains("repeatForever") || s.contains("Timer.publish"), false, "no continuous loop in \(path)")
}
let composer = source("Components/Shared/DSComposer.swift")
for token in ["stepIn", "stepOut", "reveal", "revealOut", "ringDraw", "ornamentDraw", "selectPop", "pillIn", "banner"] {
    check(composer.contains("static let \(token)"), true, "DSMotion.\(token) defined once in DSComposer.swift")
}
check(composer.contains("DSMotionRules.Timing"), true, "DSMotion builds its new curves from DSMotionRules.Timing")
let signup = source("Views/Features/Auth/SignupOriginViews.swift")
check(signup.contains("DSMomentToast.show"), true, "send success = the app's success moment")
check(signup.contains(".dsStep(") && composer.contains("DSMotionRules.stepOffsets"), true,
      "box change uses the RTL-aware step transition (dsStep → stepOffsets)")
check(signup.contains("DSMotionRules.SignupStep") || signup.contains("SignupStep"), true, "step dots follow the flow")
check(signup.contains("withAnimation(.easeInOut(duration"), false, "no literal curves in sign-up")
let waiting = source("Views/Features/Auth/WaitingForApprovalView.swift")
check(waiting.contains("DS.Anim.elastic"), false, "waiting box: no elastic fade of the whole page (box entrance instead)")
let tree = source("Views/Features/Tree/TreeView.swift")
check(tree.contains("DSMotion.banner"), true, "kinship banner (both paths) uses DSMotion.banner")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
