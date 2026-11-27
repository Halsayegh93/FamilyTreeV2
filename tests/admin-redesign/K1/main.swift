// فحص «صلة القرابة عن طريق الأم في شجرة العائلة» + «تغيير الجنس لا يفشل بصمت» (الوحدة K1، ٢٠٢٦-١١-٢٧) — بلا محاكي:
//   xcrun swiftc -swift-version 5 -default-isolation MainActor -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/k1-logic \
//     tools/kinship-test/Stubs.swift FamilyTreeV2/FamilyTreeV2/Core/KinshipCalculator.swift \
//     FamilyTreeV2/FamilyTreeV2/Core/ArabicTextNormalizer.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/FamilyTreeMenOnly.swift tests/admin-redesign/K1/main.swift \
//     && /private/tmp/claude-501/k1-logic
//
// الشكل الحقيقي للبيانات (تحقّق ٢٠٢٦-١١-٢٧): `profiles` بلا `mother_id` أبداً (٠ من ٢٧٨٩)؛ الأمهات في `women_members`:
// عقدة الرجل المنعكسة بنفس معرّفه (`parent_id` = أبوه في `profiles`، و`mother_id` = أمه)، والأم بنت `parent_id` = أبوها
// في `profiles` و`husband_id` = زوجها. حساب المرأة ملفّ بلا أب، وعقدتها في شجرة النساء مربوطة (`linked_user_id`).
//
// ما يُفحص: نتائج جهة الأب كما كانت حرفاً بحرف · خالك/خالتك/ابن خالك/ابن خالتك/بنت خالتك/جدك أبو أمك عن طريق الأم ·
// امرأة تسأل · الأبعد من الجهتين يختار الأقرب (والتساوي لجهة الأب) · بلا شجرة النساء = كما كان ·
// تغيير الجنس: «أنثى» لمن له أب = نقل بين الشجرتين لا تحديث عادي · رسالة رفض السيرفر تظهر.
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

// MARK: - البيانات

var profiles: [UUID: FamilyMember] = [:]
var women: [FamilyMember] = []

@discardableResult
func profile(_ name: String, father: FamilyMember? = nil) -> FamilyMember {
    let m = FamilyMember(id: UUID(), firstName: name, fullName: name, fatherId: father?.id, motherId: nil,
                         husbandId: nil, gender: "male")
    profiles[m.id] = m
    return m
}
/// عقدة رجل منعكسة في شجرة النساء — نفس المعرّف، ومعها أمّه إن عُرفت
func mirror(_ p: FamilyMember, mother: FamilyMember? = nil) {
    women.append(FamilyMember(id: p.id, firstName: p.firstName, fullName: p.fullName, fatherId: p.fatherId,
                              motherId: mother?.id, husbandId: nil, gender: "male"))
}
@discardableResult
func daughter(_ name: String, father: FamilyMember?, husband: FamilyMember? = nil,
              mother: FamilyMember? = nil) -> FamilyMember {
    let w = FamilyMember(id: UUID(), firstName: name, fullName: name, fatherId: father?.id, motherId: mother?.id,
                         husbandId: husband?.id, gender: "female")
    women.append(w)
    return w
}

// جهة الأب: R ← G ← F ← أنا، وعمي U وابنه UC، وأخي Bro
let r    = profile("R")
let g    = profile("G", father: r)
let f    = profile("F", father: g)
let me   = profile("Me", father: f)
let bro  = profile("Bro", father: f)
let u    = profile("U", father: g)
let uc   = profile("UC", father: u)
// جهة الأم: R ← A1 ← MGF (جدي أبو أمي، في `profiles`)، وخالي MU وابنه KS
let a1   = profile("A1", father: r)
let mgf  = profile("MGF", father: a1)
let mu   = profile("MU", father: mgf)
let ks   = profile("KS", father: mu)
// زوج خالتي الثانية X من العائلة، وابنها KhS
let x    = profile("X", father: r)
let khs  = profile("KhS", father: x)
// حساب أختي: ملف بلا أب (حساب امرأة)
let sisAccount = FamilyMember(id: UUID(), firstName: "Sis", fullName: "Sis", fatherId: nil, motherId: nil,
                              husbandId: nil, gender: "female")
profiles[sisAccount.id] = sisAccount

// شجرة النساء
let mom    = daughter("Mom", father: mgf, husband: f)
let khala  = daughter("Khala", father: mgf, husband: u)        // خالتي متزوجة عمي — أمّ UC
let khala2 = daughter("Khala2", father: mgf, husband: x)       // أمّ KhS
let khD    = daughter("KhD", father: x, mother: khala2)        // بنت خالتي
let sisNode = daughter("SisNode", father: f, mother: mom)      // عقدة أختي
for p in [r, g, f, bro, u, a1, mgf, mu, ks, x] { mirror(p, mother: p.id == bro.id ? mom : nil) }
mirror(me, mother: mom)
mirror(uc, mother: khala)
mirror(khs, mother: khala2)

typealias K = KinshipCalculator

func family(_ a: FamilyMember, _ b: FamilyMember, viewerNode: UUID? = nil,
            women w: [FamilyMember] = women) -> K.KinshipResult {
    K.calculateInFamilyTree(from: a, to: b, lookup: profiles, women: w, viewerNodeId: viewerNode)
}
func old(_ a: FamilyMember, _ b: FamilyMember) -> K.KinshipResult {
    K.calculate(from: a, to: b, lookup: profiles)
}
func ids(_ r: K.KinshipResult) -> [UUID] { r.pathA.map(\.id) + r.pathB.map(\.id) }

// MARK: ١) جهة الأب كما كانت حرفاً بحرف (الكلمة والمسار) وبلا «عن طريق الأم»

for (b, word) in [(f, "أبوك"), (g, "جدك"), (u, "عمك"), (uc, "ابن عمك"), (bro, "أخوك"), (r, "جد أبوك")] {
    let now = family(me, b), before = old(me, b)
    check(now.relationship, word, "paternal word: \(b.firstName)")
    check(now.relationship, before.relationship, "paternal unchanged: \(b.firstName)")
    check(ids(now), ids(before), "paternal path unchanged: \(b.firstName)")
    check(now.viaMother, false, "paternal not via mother: \(b.firstName)")
}
// قبل: خالي يظهر من جهة الأب البعيدة
check(old(me, mu).relationship != "خالك", true, "before: maternal uncle was not «خالك»")

// MARK: ٢) عن طريق الأم

check(family(me, mu).relationship, "خالك", "maternal uncle → خالك")
check(family(me, mu).viaMother, true, "maternal uncle via mother")
check(family(me, ks).relationship, "ابن خالك", "maternal uncle's son → ابن خالك")
check(family(me, mgf).relationship, "جدك أبو أمك", "maternal grandfather → جدك أبو أمك")
check(family(me, mgf).viaMother, true, "maternal grandfather via mother")
check(family(me, khala).relationship, "خالتك", "maternal aunt → خالتك")
check(family(me, khD).relationship, "بنت خالتك", "maternal aunt's daughter → بنت خالتك")
check(family(me, mom).relationship, "أمك", "mother → أمك")
// الأبعد من الجهتين: ابن خالتي من جهة الأب بعيد (X ابن R)، من جهة الأم ابن خالتي — يُختار الأقرب
check(old(me, khs).relationship != "ابن خالتك", true, "before: KhS was a distant paternal relative")
check(family(me, khs).relationship, "ابن خالتك", "both sides: closest wins → ابن خالتك")
check(family(me, khs).viaMother, true, "KhS via mother")
// التساوي: ابن عمي هو ابن خالتي أيضاً — جهة الأب تبقى
check(family(me, uc).relationship, "ابن عمك", "tie keeps paternal → ابن عمك")
check(family(me, uc).viaMother, false, "tie is not via mother")
// العكس: خالي يسأل عني — ابن أختك
check(family(mu, me).relationship, "ابن أختك", "uncle asks → ابن أختك")

// MARK: ٣) امرأة تسأل (حسابها بلا أب، وعقدتها مربوطة)

check(old(sisAccount, u).relationship, "من العائلة", "before: woman viewer saw «من العائلة»")
check(family(sisAccount, u, viewerNode: sisNode.id).relationship, "عمك", "woman viewer → عمك")
check(family(sisAccount, u, viewerNode: sisNode.id).viaMother, false, "woman viewer paternal not via mother")
check(family(sisAccount, mu, viewerNode: sisNode.id).relationship, "خالك", "woman viewer → خالك")
check(family(sisAccount, ks, viewerNode: sisNode.id).relationship, "ابن خالك", "woman viewer → ابن خالك")
check(family(sisAccount, me, viewerNode: sisNode.id).relationship, "أخوك", "woman viewer → أخوك")
check(family(me, sisNode).relationship, "أختك", "brother sees sister node → أختك")

// MARK: ٤) بلا شجرة النساء (لم تُجلب بعد) = كما كان تماماً

for b in [mu, ks, mgf, khs, u] {
    check(family(me, b, women: []).relationship, old(me, b).relationship, "no women nodes = old: \(b.firstName)")
    check(family(me, b, women: []).viaMother, false, "no women nodes not via mother: \(b.firstName)")
}
check(K.motherNote, "عن طريق الأم", "note text")

// MARK: ٥) تغيير الجنس — لا يفشل بصمت

typealias G = FamilyTreeMenOnly
check(G.genderChangeRoute(to: "female", current: "male", hasFather: true), .moveBetweenTrees,
      "female with a father → move between trees")
check(G.genderChangeRoute(to: "female", current: "male", hasFather: false), .plainUpdate,
      "female without a father → plain update")
check(G.genderChangeRoute(to: "male", current: "female", hasFather: true), .plainUpdate, "male → plain update")
check(G.genderChangeRoute(to: "male", current: "male", hasFather: true), .unchanged, "same gender → nothing")
check(G.genderChangeRoute(to: "male", current: nil, hasFather: true), .unchanged, "nil current = male")
check(G.menOnlyHint, "family_tree_men_only", "server hint")
let serverText = "شجرة العائلة للرجال فقط — أضف البنت في شجرة النساء"
check(G.genderFailureMessage(serverMessage: serverText), serverText, "server Arabic message shown as is")
check(G.genderFailureMessage(serverMessage: nil), "تعذّر حفظ الجنس. حاول مرة أخرى.", "fallback message")
check(G.genderFailureMessage(serverMessage: "new row violates"), "تعذّر حفظ الجنس. حاول مرة أخرى.",
      "English server text → fallback")

print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
exit(failures == 0 ? 0 : 1)
