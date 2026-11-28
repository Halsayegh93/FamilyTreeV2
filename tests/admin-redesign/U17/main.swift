// فحص منطق «التطبيق» (Views/Features/Admin/AdminAppAreaLogic.swift، الوحدة U17) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u17-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminAppAreaLogic.swift tests/admin-redesign/U17/main.swift && /tmp/u17-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias L = AdminAppLogic

// MARK: التأكيد — يسأل عند تشغيل الصيانة وإيقاف الإشعارات فقط (spec A.14)
check(L.confirm(for: .maintenance, to: .flag(true)), .maintenanceOn, "maintenance on asks")
check(L.confirm(for: .maintenance, to: .flag(false)), nil, "maintenance off does not ask")
check(L.confirm(for: .pushPaused, to: .flag(true)), .pushOff, "stopping notifications asks")
check(L.confirm(for: .pushPaused, to: .flag(false)), nil, "turning notifications back on does not ask")
check(L.confirm(for: .resetCounter, to: nil), .resetCounter, "reset counter asks")
check(L.confirm(for: .restoreDefaults, to: nil), .restoreDefaults, "restore defaults asks")
for s in [AdminAppSetting.language, .diwaniyas, .womenTree, .projects, .polls, .newsApproval, .selfEditLimit] {
    check(L.confirm(for: s, to: .flag(false)), nil, "\(s) off does not ask")
    check(L.confirm(for: s, to: .flag(true)), nil, "\(s) on does not ask")
}
check(L.confirm(for: .libraryShield, to: .text("off")), nil, "screenshot policy does not ask")
check(L.confirm(for: .language, to: .text("en")), nil, "language does not ask")
// «نعم» ينفّذ التغيير نفسه
check(L.Confirm.maintenanceOn.change.setting, .maintenance, "confirm maintenance → maintenance")
check(L.Confirm.maintenanceOn.change.value, .flag(true), "confirm maintenance → on")
check(L.Confirm.pushOff.change.setting, .pushPaused, "confirm push → notifications_paused")
check(L.Confirm.pushOff.change.value, .flag(true), "confirm push → paused")
check(L.Confirm.restoreDefaults.change.value, nil, "restore defaults has no value")
for c in L.Confirm.allCases {
    check(c.title.hasSuffix("؟"), true, "\(c) title is a question")
    check(c.verb.isEmpty, false, "\(c) has a verb")
}

// MARK: الكلمات — لا كلمة هادئة إلا بنغمتها
check(L.statusWord(maintenanceOn: false), L.Word(text: "يعمل للجميع", tone: .ok, icon: "checkmark"), "status: running")
check(L.statusWord(maintenanceOn: true).text, "متوقف للأعضاء", "status: stopped")
check(L.statusWord(maintenanceOn: true).tone, .error, "status: stopped is error")
check(L.maintenanceWord(on: false), L.Word(text: "مطفأ", tone: .off), "maintenance off")
check(L.maintenanceWord(on: true), L.Word(text: "مفعّل", tone: .error), "maintenance on")
check(L.pushWord(paused: false), L.Word(text: "تعمل", tone: .ok), "push running")
check(L.pushWord(paused: true), L.Word(text: "موقوفة", tone: .warn), "push paused")
check(L.pushLine(paused: false), "تصل لكل الأعضاء", "push line")
check(L.forceUpdateWord(required: false), L.Word(text: "اختياري", tone: .off), "force update optional")
check(L.forceUpdateWord(required: true), L.Word(text: "إجباري", tone: .warn), "force update required")
check(L.forceUpdateRequired(modes: ["optional", "optional"]), false, "both optional")
check(L.forceUpdateRequired(modes: ["optional", "scheduled"]), true, "android scheduled")
check(L.forceUpdateRequired(modes: ["forced", "optional"]), true, "iphone forced")
check(L.legacyForceRequired(iosMin: 0, androidMin: 0, legacyAndroid: false), false, "legacy: no minimum")
check(L.legacyForceRequired(iosMin: 49, androidMin: 0, legacyAndroid: false), true, "legacy: iphone minimum")
check(L.legacyForceRequired(iosMin: 0, androidMin: 0, legacyAndroid: true), true, "legacy: old android switch")

// تلميح «يسأل قبل التغيير» فقط حين يسأل فعلاً
check(L.maintenanceHint(on: false), "يسأل قبل التغيير", "hint: turning maintenance on asks")
check(L.maintenanceHint(on: true) == "يسأل قبل التغيير", false, "hint: turning maintenance off does not claim to ask")
check(L.pushHint(paused: false), "يسأل قبل التغيير", "hint: stopping push asks")
check(L.pushHint(paused: true) == "يسأل قبل التغيير", false, "hint: resuming push does not claim to ask")

// MARK: الأسطر
check(L.versionLine(short: "1.0.1", build: "51"), "الإصدار \u{2066}1.0.1 (51)\u{2069}", "version + build, isolated")
check(L.versionLine(short: "1.0.1", build: nil), "الإصدار \u{2066}1.0.1\u{2069}", "version without build")
check(L.versionLine(short: "2", build: "2"), "الإصدار \u{2066}2\u{2069}", "build equal to version not repeated")
check(L.storeLine(ios: 49, android: 0), "آخر إصدار في المتجر: آيفون 49", "store line iphone only")
check(L.storeLine(ios: 49, android: 31), "آخر إصدار في المتجر: آيفون 49 · أندرويد 31", "store line both")
check(L.storeLine(ios: 0, android: 0), "آخر إصدار في المتجر لم يُحدَّد بعد", "store line none")
check(L.legacyLine(iosMin: 0, androidMin: 31), "أقل إصدار مسموح: آيفون بلا · أندرويد 31", "legacy line as before")
check(L.languageTitle(nil), "العربية", "language default")
check(L.languageTitle("en"), "English", "language en")
check(L.shieldTitle(nil), "على الأعضاء فقط", "screenshot default members")
check(L.shieldTitle("all"), "على الجميع", "screenshot all")
check(L.shieldTitle("off"), "مطفأ", "screenshot off")
check(L.branchesValue(0), nil, "no named branch → no value")
check(L.branchesValue(1), "فرع واحد", "1 branch")
check(L.branchesValue(2), "فرعان", "2 branches")
check(L.branchesValue(3), "3 فروع", "3 branches")
check(L.branchesValue(14), "14 فرعاً", "14 branches")
check(L.branchesValue(100), "100 فرع", "100 branches")
check(L.errorsValue(totals: [2, 1, 0, 0]), "3", "errors sum")
check(L.errorsValue(totals: [1000, 204]), "1,204", "errors thousands")

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Kuwait")!
let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 10))!
let nov17 = cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 9))!
let lastYear = cal.date(from: DateComponents(year: 2025, month: 1, day: 3, hour: 9))!
check(L.dayMonth(nov17, now: now, calendar: cal), "17 نوفمبر", "last change this year")
check(L.dayMonth(lastYear, now: now, calendar: cal), "3 يناير 2025", "last change another year")

// MARK: الحالات (T1/T5) — لا قيمة ولا أداة قبل وصول الإعدادات
let t0 = Date(timeIntervalSince1970: 1_000)
check(L.controlEnabled(health: .loaded(at: t0), canEdit: true, busy: false), true, "loaded owner: enabled")
check(L.controlEnabled(health: .loading, canEdit: true, busy: false), false, "loading: disabled")
check(L.controlEnabled(health: .failed(lastGood: nil), canEdit: true, busy: false), false, "failed with no data: disabled")
check(L.controlEnabled(health: .failed(lastGood: t0), canEdit: true, busy: false), true, "failed after a good load: enabled")
check(L.controlEnabled(health: .loaded(at: t0), canEdit: false, busy: false), false, "read-only: disabled")
check(L.controlEnabled(health: .loaded(at: t0), canEdit: true, busy: true), false, "while saving: disabled")
check(L.showsValue(.idle), false, "idle: skeleton")
check(L.showsValue(.failed(lastGood: nil)), false, "failed: no fake value")
check(L.showsValue(.failed(lastGood: t0)), true, "stale: keeps value")
check(L.seeded(.idle, hasData: true, now: t0), .loaded(at: t0), "seeded from memory")
check(L.seeded(.idle, hasData: false, now: t0), .idle, "not seeded without data")
check(L.seeded(.failed(lastGood: nil), hasData: true, now: t0), .failed(lastGood: nil), "seed only from idle")
// حبّة الرأس: الفشل بلا بيانات «تعذّر التحميل» (لا «يعمل للجميع»)
check(AdminStoreHealth.failed(lastGood: nil).look, .unknown, "failed settings → unknown pill")
check(AdminStoreHealth.loading.look, .skeleton, "loading settings → skeleton pill")

// MARK: نجاح الحفظ
check(L.saveSucceeded(desired: .flag(true), after: .flag(true), errored: false), true, "saved")
check(L.saveSucceeded(desired: .flag(true), after: .flag(true), errored: true), false, "error → not saved")
check(L.saveSucceeded(desired: .flag(true), after: .flag(false), errored: false), false, "zero rows (value unchanged) → not saved")
check(L.saveSucceeded(desired: .text("en"), after: .text("en"), errored: false), true, "language saved")

// MARK: حال الحفظ — واحد في كل مرة، والفشل يبقى حتى ينجح
var st = AdminAppSaveState()
check(st.isBusy, false, "idle")
check(st.begin(.maintenance), true, "begin maintenance")
check(st.isSaving(.maintenance), true, "maintenance saving")
check(st.isBusy, true, "busy")
check(st.begin(.polls), false, "second save refused while busy")
st.finish(.polls, success: true)
check(st.isSaving(.maintenance), true, "finishing another key changes nothing")
st.finish(.maintenance, success: false)
check(st.isBusy, false, "done")
check(st.hasFailed(.maintenance), true, "failure line shown")
check(st.begin(.polls), true, "next save")
st.finish(.polls, success: true)
check(st.hasFailed(.maintenance), true, "another key's success keeps the failure line")
check(st.begin(.maintenance), true, "retry")
check(st.hasFailed(.maintenance), false, "retry clears the line while saving")
st.finish(.maintenance, success: true)
check(st.hasFailed(.maintenance), false, "success clears the line")

// MARK: المفاتيح والمخازن
check(AdminAppSetting.maintenance.serverKey, "maintenance_mode", "maintenance key")
check(AdminAppSetting.pushPaused.serverKey, "notifications_paused", "push key = notifications_paused")
check(AdminAppSetting.libraryShield.store, .config, "screenshot policy in app_config")
check(AdminAppSetting.selfEditLimit.store, .editLimit, "self-edit limit on the server (not this device)")
check(AdminAppSetting.selfEditLimit.serverKey, "profile_edit_limit_enabled", "self-edit limit = app_config key")
check(L.Confirm.resetCounter.message.contains("كل الأعضاء"), true, "reset text says it resets every member")
check(L.Confirm.resetCounter.message.contains("الانتظار"), false, "reset text: no «waiting periods» (there are none)")
check(AdminAppSetting.restoreDefaults.store, .command, "restore is a command")
check(AdminAppSetting.allCases.filter { $0.store == .settings }.allSatisfy { $0.serverKey != nil }, true,
      "every app_settings item has a key")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
