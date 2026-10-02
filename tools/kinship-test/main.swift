import Foundation

// MARK: - Test family
var all: [UUID: FamilyMember] = [:]
var nameOf: [UUID: String] = [:]

@discardableResult
func add(_ name: String, _ gender: String = "male", father: FamilyMember? = nil,
         mother: FamilyMember? = nil, husband: FamilyMember? = nil) -> FamilyMember {
    let m = FamilyMember(id: UUID(), firstName: name, fullName: name, fatherId: father?.id,
                         motherId: mother?.id, husbandId: husband?.id, gender: gender)
    all[m.id] = m
    nameOf[m.id] = name
    return m
}

// Paternal spine: Root → GG → G → F → Me → Son → GSon → GGSon → GGGSon
let root  = add("Root")
let gg    = add("GG", father: root)
let ggb   = add("GGb", father: root)                    // great-grandfather's brother
let g     = add("G", father: gg)
let gm    = add("GM", "female", husband: g)             // grandmother (G's wife)
let gb    = add("Gb", father: gg)                       // grandfather's brother
let gs    = add("Gs", "female", father: gg)             // grandfather's sister
let f     = add("F", father: g, mother: gm)
// mother's side (outsiders to the paternal line)
let mggf  = add("MGGF")
let mgf   = add("MGF", father: mggf)
let mgm   = add("MGM", "female", husband: mgf)
let m     = add("M", "female", father: mgf, mother: mgm, husband: f)
let mb    = add("MB", father: mgf, mother: mgm)
let ms    = add("MS", "female", father: mgf, mother: mgm)
let fw2   = add("FW2", "female", husband: f)            // father's second wife (not my mother)
let u     = add("U", father: g, mother: gm)
let ua    = add("Ua", "female", father: g, mother: gm)
let gbS   = add("GbS", father: gb)
let gbD   = add("GbD", "female", father: gb)
// sister's husband's family (outsiders)
let shf   = add("SHF")
let shm   = add("SHM", "female", husband: shf)
let sh    = add("SH", father: shf, mother: shm)
// my generation
let me      = add("Me", father: f, mother: m)
let bro     = add("Bro", father: f, mother: m)
let bro2    = add("Bro2", father: f, mother: m)
let sis     = add("Sis", "female", father: f, mother: m, husband: sh)
let halfBro = add("HalfBro", father: f, mother: fw2)
// wife's family (outsiders)
let wg    = add("WG")
let wf    = add("WF", father: wg)
let wm    = add("WM", "female", husband: wf)
let w     = add("W", "female", father: wf, mother: wm, husband: me)
let wb    = add("WB", father: wf, mother: wm)
let ws    = add("WS", "female", father: wf, mother: wm)
let wu    = add("WU", father: wg)
let wx    = add("WX")
let wson  = add("WSon", father: wx, mother: w)          // wife's son from another husband
let ws2   = add("WS2", "female", father: wf, mother: wm, husband: bro2)  // wife's sister married to my brother
// children
let dh    = add("DH")
let son   = add("Son", father: me, mother: w)
let dau   = add("Dau", "female", father: me, mother: w, husband: dh)
// cousins and the (3,3)/(4,x) branches
let cousin  = add("Cousin", father: u)
let cousinF = add("CousinF", "female", father: u)
let gbSS    = add("GbSS", father: gbS)
let gbSD    = add("GbSD", "female", father: gbS)
let x1      = add("X1", father: ggb)
let x2      = add("X2", father: x1)
let x3      = add("X3", father: x2)
let x3f     = add("X3f", "female", father: x2)
// descendants (3-generation-deep branch and beyond)
let gson   = add("GSon", father: son)
let gdau   = add("GDau", "female", father: son)
let ggson  = add("GGSon", father: gson)
let ggdau  = add("GGDau", "female", father: gson)
let gggson = add("GGGSon", father: ggson)
// siblings' and cousins' descendants
let broS     = add("BroS", father: bro)
let broD     = add("BroD", "female", father: bro)
let broSS    = add("BroSS", father: broS)
let broSD    = add("BroSD", "female", father: broS)
let cousinS  = add("CousinS", father: cousin)
let cousinD  = add("CousinD", "female", father: cousin)
let cousinSS = add("CousinSS", father: cousinS)
// wives of relatives
let sw   = add("SW", "female", husband: son)
let bw   = add("BW", "female", husband: bro)
let cw   = add("CW", "female", husband: cousin)
let ws3  = add("WS3", "female", father: wf, mother: wm, husband: cousinS)  // wife's sister married far away
let x3w  = add("X3W", "female", husband: x3)
let cssw = add("CSSW", "female", husband: cousinSS)
let g3w  = add("G3W", "female", husband: gggson)
let x3fh = add("X3fH")
all[x3f.id]!.husbandId = x3fh.id                         // husband of my 4th-degree cousin
// maternal-only relations (women tree)
let mbS  = add("MBS", father: mb)
let msD  = add("MSD", "female", mother: ms)
let sisS = add("SisS", father: sh, mother: sis)
let sisD = add("SisD", "female", father: sh, mother: sis)
let uaS  = add("UaS", mother: ua)
let dauS = add("DauS", father: dh, mother: dau)
let sisKid = add("SisKid", father: sis)                  // women tree: parent_id may point to the mother
// double cousins: tie between two common ancestors at the same distance
let pg  = add("PG")
let qg  = add("QG")
let p1  = add("P1", father: pg)
let q1  = add("Q1", "female", father: qg, husband: p1)
let q2  = add("Q2", "female", father: pg)                // P1's sister
let p2  = add("P2", father: qg)                          // Q1's brother
all[q2.id]!.husbandId = p2.id
let k1  = add("K1", father: p1, mother: q1)
let k2  = add("K2", father: p2, mother: q2)
// unrelated, cycles
let stranger = add("Stranger")
let c1 = add("C1")
let c2 = add("C2", father: c1)
all[c1.id]!.fatherId = c2.id                             // father cycle
let loop = add("Loop")
all[loop.id]!.fatherId = loop.id                         // self-loop
let loopKid = add("LoopKid", father: loop)
let h1 = add("H1", "female")
let h2 = add("H2", "female", husband: h1)
all[h1.id]!.husbandId = h2.id                            // husband cycle
let ww = add("WW", "female")
all[ww.id]!.husbandId = ww.id                            // married to herself

// MARK: - Harness
var passed = 0
var failed = 0
var failures: [String] = []

func rec(_ m: FamilyMember) -> FamilyMember { all[m.id]! }

@discardableResult
func check(_ a: FamilyMember, _ b: FamilyMember, maternal: Bool = false, _ expected: String,
           _ file: StaticString = #file, _ line: UInt = #line) -> KinshipCalculator.KinshipResult {
    let r = KinshipCalculator.calculate(from: rec(a), to: rec(b), lookup: all, includeMaternal: maternal)
    if r.relationship == expected {
        passed += 1
    } else {
        failed += 1
        failures.append("line \(line): \(a.firstName) → \(b.firstName)\(maternal ? " [maternal]" : ""): expected «\(expected)» got «\(r.relationship)»")
    }
    return r
}

func expect(_ cond: Bool, _ what: String, _ line: UInt = #line) {
    if cond { passed += 1 } else { failed += 1; failures.append("line \(line): \(what)") }
}

func names(_ ms: [FamilyMember]) -> [String] { ms.map { nameOf[$0.id] ?? "?" } }
/// The chain MemberDetailsView builds: pathA + reversed(pathB without the ancestor)
func chain(_ r: KinshipCalculator.KinshipResult) -> [String] {
    names(r.pathA + Array(r.pathB.dropLast().reversed()))
}

// MARK: - Main tree (paternal only), viewer = Me (male)
check(me, f, "أبوك")
check(me, m, "أمك")                    // mother is blood, never «زوجة أبوك»
check(me, fw2, "زوجة أبوك")            // father's other wife
check(me, g, "جدك")
check(me, gm, "جدتك")
check(me, gg, "جد أبوك")
check(me, root, "من أجدادك")
check(me, son, "ابنك")
check(me, dau, "بنتك")                 // father viewing his daughter (was «ابنه»)
check(me, gson, "حفيدك")
check(me, gdau, "حفيدتك")
check(me, ggson, "ابن حفيدك")
check(me, ggdau, "بنت حفيدك")
check(me, gggson, "من أحفادك")
check(me, bro, "أخوك")
check(me, sis, "أختك")
check(me, halfBro, "أخوك")             // main tree does not split half-brothers
check(me, u, "عمك")
check(me, ua, "عمتك")
check(me, cousin, "ابن عمك")
check(me, cousinF, "بنت عمك")
check(me, broS, "ابن أخوك")
check(me, broD, "بنت أخوك")
check(me, gb, "عم أبوك")
check(me, gs, "عمة أبوك")
check(me, gbS, "ابن عم أبوك")
check(me, gbD, "بنت عم أبوك")
check(me, broSS, "ابن ابن أخوك")
check(me, broSD, "بنت ابن أخوك")
check(me, cousinS, "ابن ابن عمك")
check(me, cousinD, "بنت ابن عمك")
check(me, gbSS, "ابن ابن عم أبوك")     // (3,3) — was the duplicate «ابن عم أبوه»
check(me, gbSD, "بنت ابن عم أبوك")
check(me, ggb, "عم جدك")
check(me, x1, "ابن عم جدك")
check(me, x2, "ابن ابن عم جدك")
check(me, x3, "قريبك من الدرجة 4")
check(me, x3f, "قريبتك من الدرجة 4")
check(me, cousinSS, "من أقاربك")
check(me, mb, "من العائلة")            // main tree stays paternal: no «خالك»
check(me, stranger, "من العائلة")
check(me, me, "أنت")

// Spouses and in-laws
check(me, w, "زوجتك")
check(w, me, "زوجك")
check(me, sw, "زوجة ابنك")
check(me, bw, "زوجة أخوك")
check(me, cw, "زوجة ابن عمك")
check(me, wf, "أبو زوجتك")
check(me, wm, "أم زوجتك")
check(me, wb, "أخو زوجتك")
check(me, ws, "أخت زوجتك")
check(me, wu, "من أهل زوجتك")
check(me, wson, "ابن زوجتك")
check(me, ws2, "زوجة أخوك")            // tie with «أخت زوجتك» → wife-of-relative first
check(me, ws3, "أخت زوجتك")            // closer link wins over «زوجة ابن ابن عمك»
check(me, x3w, "زوجة قريبك من الدرجة 4")
check(me, cssw, "زوجة أحد أقاربك")
check(me, g3w, "زوجة أحد أحفادك")
check(me, sh, "زوج أختك")
check(me, dh, "زوج بنتك")
check(me, x3fh, "زوج قريبتك من الدرجة 4")
check(w, f, "أبو زوجك")
check(w, m, "أم زوجك")
check(w, bro, "أخو زوجك")
check(w, sis, "أخت زوجك")
check(w, u, "من أهل زوجك")
check(w, son, "ابنك")                  // her own son via mother link — blood wins
check(w, wson, "ابنك")
check(sis, sh, "زوجك")
check(sis, shf, "أبو زوجك")
check(sis, shm, "أم زوجك")
check(sw, son, "زوجك")
check(sw, me, "أبو زوجك")
check(wf, me, "زوج بنتك")
check(wb, me, "زوج أختك")

// Other viewpoints (target gender always from B)
check(dau, me, "أبوك")
check(dau, son, "أخوك")
check(son, dau, "أختك")
check(f, sis, "بنتك")
check(gm, f, "ابنك")                   // mother viewing son (mother link, main tree)
check(gm, me, "حفيدك")
check(cousin, me, "ابن عمك")
check(cousinF, me, "ابن عمك")
check(gbSS, me, "ابن ابن عم أبوك")
check(u, me, "ابن أخوك")
check(ua, me, "ابن أخوك")
check(u, sis, "بنت أخوك")
check(broS, me, "عمك")
check(broS, sis, "عمتك")

// MARK: - Women tree (includeMaternal: true)
check(me, mb, maternal: true, "خالك")
check(me, ms, maternal: true, "خالتك")
check(me, mbS, maternal: true, "ابن خالك")
check(me, msD, maternal: true, "بنت خالتك")
check(me, sisS, maternal: true, "ابن أختك")
check(me, sisD, maternal: true, "بنت أختك")
check(me, uaS, maternal: true, "ابن عمتك")
check(me, mgf, maternal: true, "جدك أبو أمك")
check(me, mgm, maternal: true, "جدتك أم أمك")
check(me, mggf, maternal: true, "جد أمك")
check(me, dauS, maternal: true, "حفيدك من بنتك")
check(me, halfBro, maternal: true, "أخوك من أبوك")
check(me, bro, maternal: true, "أخوك")
check(me, cousin, maternal: true, "ابن عمك")   // father's side wins the tie
check(me, f, maternal: true, "أبوك")
check(me, m, maternal: true, "أمك")
check(me, gm, maternal: true, "جدتك")
check(me, w, maternal: true, "زوجتك")
check(me, sisKid, maternal: true, "ابن أختك")  // parent_id → sister: gender from her record
check(mb, me, maternal: true, "ابن أختك")
check(ms, sis, maternal: true, "بنت أختك")
check(mgf, me, maternal: true, "حفيدك من بنتك")
check(k1, k2, maternal: true, "ابن عمتك")      // double cousins: deterministic, father's side

// MARK: - English (second person)
L10n.arabic = false
check(me, f, "Your father")
check(me, dau, "Your daughter")
check(me, cousin, "Your cousin")
check(me, gb, "Your father's uncle")
check(me, gbSS, "Your father's cousin's son")
check(me, ua, "Your paternal aunt")
check(me, mb, maternal: true, "Your maternal uncle")
check(me, sisD, maternal: true, "Your sister's daughter")
check(me, sw, "Your son's wife")
check(me, wf, "Your wife's father")
check(me, wu, "From your wife's family")
check(me, root, "One of your ancestors")
check(me, x3, "Your relative (degree 4)")
check(me, cssw, "Wife of one of your relatives")
check(me, dauS, maternal: true, "Your grandson (through your daughter)")
check(w, me, "Your husband")
check(me, stranger, "Family member")
L10n.arabic = true

// MARK: - Paths, ancestors and kinds
do {
    let r = check(me, cousin, "ابن عمك")
    expect(r.kind == .blood, "cousin kind")
    expect(r.commonAncestor?.id == g.id, "cousin common ancestor = G")
    expect(names(r.pathA) == ["Me", "F", "G"], "cousin pathA \(names(r.pathA))")
    expect(names(r.pathB) == ["Cousin", "U", "G"], "cousin pathB \(names(r.pathB))")
}
do {
    let r = check(me, w, "زوجتك")
    expect(r.kind == .spouse && r.commonAncestor == nil, "wife: spouse kind, no ancestor")
}
do {
    let r = check(me, sw, "زوجة ابنك")
    expect(r.kind == .inLaw, "son's wife kind")
    expect(chain(r) == ["Me", "Son", "SW"], "son's wife chain \(chain(r))")
}
do {
    let r = check(me, fw2, "زوجة أبوك")
    expect(chain(r) == ["Me", "F", "FW2"], "father's wife chain \(chain(r))")
}
do {
    let r = check(me, wf, "أبو زوجتك")
    expect(chain(r) == ["Me", "W", "WF"], "wife's father chain \(chain(r))")
}
do {
    let r = check(me, cw, "زوجة ابن عمك")
    expect(chain(r) == ["Me", "F", "G", "U", "Cousin", "CW"], "cousin's wife chain \(chain(r))")
    expect(r.commonAncestor?.id == g.id, "cousin's wife ancestor = G")
}
do {
    let r = check(me, stranger, "من العائلة")
    expect(r.kind == .unknown && r.commonAncestor == nil, "stranger unknown")
}

// MARK: - Cycle guards (must terminate)
check(me, c1, "من العائلة")
check(c1, c2, "أبوك")
check(loopKid, loop, "أبوك")
check(me, loop, "من العائلة")
check(me, h1, "من العائلة")
check(h1, h2, "زوجتك")              // garbage data: must just terminate
check(me, ww, "من العائلة")

// MARK: - Summary
print("PASSED \(passed) / FAILED \(failed) (total \(passed + failed))")
for f in failures { print("  FAIL " + f) }
exit(failed == 0 ? 0 : 1)
