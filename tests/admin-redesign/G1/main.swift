// فحص «شجرة العائلة للرجال فقط» (Views/Features/Tree/FamilyTreeMenOnly.swift، الوحدة G1، طلب المالك ٢٠٢٦-١١-٢٧) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/g1-logic \
//     FamilyTreeV2/FamilyTreeV2/Core/ArabicTextNormalizer.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/FamilyTreeMenOnly.swift tests/admin-redesign/G1/main.swift \
//     && /private/tmp/claude-501/g1-logic
//
// ما يُفحص: «أنثى» في مربّع إضافة لشجرة العائلة لا تُقبل (تنبيه + انتقال لشجرة النساء، أو «إلغاء» فقط بلا مسار) ·
// الجنس يبقى ذكراً بعد اختيار «أنثى» · الحارس الأخير قبل الكتابة · الاسم المنقول لمربّع البنت · النصوص ·
// اسم بنت في مربّع ابن (التطبيع، أنثى/ذكر/غير معروف من بيانات الشجرتين، أمان التداخل، حمزة/أسامة، ما ينتقل، «هو ولد؟ ارجع»).
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias M = FamilyTreeMenOnly

// ١) القرار
check(M.decision(gender: "male", hasWomenPath: true), .allow, "male → allowed")
check(M.decision(gender: "male", hasWomenPath: false), .allow, "male without women path → still allowed")
check(M.decision(gender: nil, hasWomenPath: true), .allow, "no gender (defaults male) → allowed")
check(M.decision(gender: "", hasWomenPath: true), .allow, "empty gender → allowed")
check(M.decision(gender: "female", hasWomenPath: true), .redirectToWomenTree, "female → alert + women tree")
check(M.decision(gender: " Female ", hasWomenPath: true), .redirectToWomenTree, "female any case/spaces → alert")
check(M.decision(gender: "FEMALE", hasWomenPath: false), .blockOnly, "female without women path → alert with cancel only")

// ٢) الاختيار في المربّع: «أنثى» لا تبقى
check(M.keptGender(picked: "female", current: "male"), "", "pick female while male → empty, must choose again")
check(M.keptGender(picked: "male", current: "male"), "male", "pick male → male")
check(M.keptGender(picked: "female", current: "female"), "", "stale female → empty, never silently male")
check(M.keptGender(picked: "female", current: ""), "", "pick female from empty → stays empty")
check(M.keptGender(picked: "male", current: "female"), "male", "pick male from stale female → male")

// ٣) الحارس الأخير قبل الكتابة
check(M.mayWriteToFamilyTree(gender: "male"), true, "male may be written")
check(M.genderChosen(""), false, "empty after the alert → the add button waits for a choice")
check(M.genderChosen("male"), true, "male chosen → may add")
check(M.mayWriteToFamilyTree(gender: nil), true, "nil may be written (server writes male)")
check(M.mayWriteToFamilyTree(gender: "female"), false, "female never written to the family tree")
check(M.isFemale("female"), true, "isFemale female")
check(M.isFemale("male"), false, "isFemale male")

// ٤) الاسم المنقول لمربّع «أبناء» في شجرة النساء
check(M.carriedName("  فاطمة \n"), "فاطمة", "typed name trimmed")
check(M.carriedName(""), "", "empty name stays empty")

// ٥) النصوص (العربية)
check(M.title, "شجرة العائلة للرجال فقط", "alert title")
check(M.message, "البنات يُضفن في شجرة النساء تحت أبيهن.", "alert line")
check(M.openTitle, "إلى شجرة النساء", "primary button")
check(M.cancelTitle, "إلغاء", "cancel button")

// ٦) اسم بنت في مربّع ابن — التطبيع
check(M.normalizedFirstName("  فاطمة  "), "فاطمه", "normalise: trim + final ة→ه")
check(M.normalizedFirstName("فاطمه"), "فاطمه", "normalise: final ه stays")
check(M.normalizedFirstName("أمل"), "امل", "normalise: أ→ا")
check(M.normalizedFirstName("إيمان"), "ايمان", "normalise: إ→ا")
check(M.normalizedFirstName("آمنة"), "امنه", "normalise: آ→ا and ة→ه")
check(M.normalizedFirstName("ليلى"), "ليلي", "normalise: ى→ي")
check(M.normalizedFirstName("فـــاطمة"), "فاطمه", "normalise: tatweel removed")
check(M.normalizedFirstName("فَاطِمَةُ"), "فاطمه", "normalise: diacritics removed")
check(M.normalizedFirstName("\u{200F}مريم\u{200F}"), "مريم", "normalise: invisible marks removed")
check(M.normalizedFirstName("نورة محمد"), "نوره", "normalise: first word only")
check(M.normalizedFirstName("ةحمد"), "ةحمد", "normalise: ة only at the end")
check(M.normalizedFirstName("   "), "", "normalise: blank → empty")
check(M.normalizedFirstName("Sara"), "sara", "normalise: latin lowercased")

// ٧) القاعدة من البيانات: أنثى في شجرة النساء وليس اسماً لذكر
let women: [(firstName: String, isFemale: Bool)] = [
    ("فاطمة", true), ("مريم", true), ("نورة", true), ("ليلى", true), ("نور", true), ("آمنة", true),
    ("محمد", false),            // عقدة رجل منعكسة في شجرة النساء
    ("", true),                 // اسم فارغ لا يدخل
]
let men = ["محمد", "حمزة", "أسامة", "نور", "علي"]
let book = M.nameBook(women: women, men: men)
check(book.female.contains("نور"), false, "overlap safety: نور is male and female → not female")
check(book.female.intersection(book.male).isEmpty, true, "overlap safety: female ∩ male = ∅")
check(book.female.contains(""), false, "empty name never in the book")
check(M.guess("فاطمة", book: book), .female, "فاطمة → female")
check(M.guess("فاطمه", book: book), .female, "فاطمه (ه) → female")
check(M.guess("  فَاطِمَة  ", book: book), .female, "فاطمة with marks/spaces → female")
check(M.guess("ليلي", book: book), .female, "ليلي (ي) → female")
check(M.guess("امنه", book: book), .female, "امنه → female (آمنة)")
check(M.guess("محمد", book: book), .male, "محمد → male")
check(M.guess("حمزة", book: book), .male, "حمزة stays male (ends in ة, in men's list)")
check(M.guess("أسامة", book: book), .male, "أسامة stays male (ends in ة, in men's list)")
check(M.guess("اسامه", book: book), .male, "اسامه normalised → male")
check(M.guess("نور", book: book), .male, "نور (both trees) → male, no move")
check(M.guess("طلحة", book: book), .unknown, "unknown name ending in ة → no guess")
check(M.guess("زيد", book: book), .unknown, "unknown name → no guess")
check(M.guess("", book: book), .unknown, "empty → unknown")
check(M.guess("فاطمة", book: .empty), .unknown, "no data → no guess")
// ذكر في شجرة النساء وحدها (عقدة منعكسة) يحمي اسمه
let book2 = M.nameBook(women: [("سلمى", true), ("سلمى", false)], men: [])
check(M.guess("سلمى", book: book2), .male, "name on a male node in the women tree → male")

// ٨) ما ينتقل عند الإرسال
check(M.namesToMove(["فاطمة"], book: book, confirmedSons: []), ["فاطمة"], "one girl's name → moves")
check(M.namesToMove(["  فاطمة "], book: book, confirmedSons: []), ["فاطمة"], "moved name is trimmed")
check(M.namesToMove(["حمزة"], book: book, confirmedSons: []), [], "حمزة → stays a son")
check(M.namesToMove(["زيد"], book: book, confirmedSons: []), [], "unknown → stays a son")
check(M.namesToMove(["علي", "مريم", "حمزة", "نورة"], book: book, confirmedSons: []), ["مريم", "نورة"],
      "mixed list → only the girls move, in order")
check(M.namesToMove(["مريم", "مريم"], book: book, confirmedSons: []), ["مريم"], "duplicates move once")
check(M.namesToMove(["فاطمة"], book: book, confirmedSons: M.sonKeys(["فاطمه"])), [],
      "«هو ولد؟ ارجع» → the same name is sent as a son next time")
check(M.namesToMove(["فاطمة", "مريم"], book: book, confirmedSons: M.sonKeys(["فاطمة"])), ["مريم"],
      "confirmed son only covers its own name")
check(M.namesToMove(["", "  "], book: book, confirmedSons: []), [], "blank rows never move")

// ٩) نصوص الانتقال
check(M.autoMoveNotice(["فاطمة"]), "انتقلنا لشجرة النساء لأن «فاطمة» اسم بنت", "notice line (one)")
check(M.autoMoveNotice(["فاطمة", "مريم"]), "انتقلنا لشجرة النساء لأن «فاطمة» و«مريم» أسماء بنات", "notice line (two)")
check(M.quotedList(["أ", "ب", "ج"]), "«أ»، «ب» و«ج»", "three names joined")
check(M.backTitle(count: 1), "هو ولد؟ ارجع", "back button (one)")
check(M.backTitle(count: 2), "هم أولاد؟ ارجع", "back button (many)")
check(M.noPathTitle(["فاطمة"]), "«فاطمة» اسم بنت", "no-path alert title")
check(M.sendAsSonTitle(count: 1), "هو ولد — أرسل", "no-path send-as-son button")

if failures == 0 { print("ALL PASS") } else { print("\(failures) FAILED"); exit(1) }
