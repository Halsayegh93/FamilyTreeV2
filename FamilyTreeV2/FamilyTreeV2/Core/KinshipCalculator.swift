import Foundation

// MARK: - KinshipCalculator
// حاسبة صلة القرابة — تخاطب المستخدم مباشرة: A = أنت، B = الشخص الآخر
// («أبوك»، «بنتك»، «ابن عمك»، «ابن أختك»، «زوجة أخوك»، «أبو زوجتك»).
// الأولوية: الزوج/الزوجة ← قرابة الدم ← المصاهرة (الأقرب يفوز) ← «من العائلة».
// شجرة العائلة: جهة الأب فقط، مع أمّ كل واحد على خط الأب (أمك، جدتك، ابنك لأمّه).
// شجرة النساء: الجهتان (includeMaternal) — عند التساوي تُرجَّح جهة الأب.
// جنس الشخص الثاني من سجلّه دائماً؛ ومن بينكما من نوع الرابط (رابط الأم = أنثى) أو من سجلّه.

enum KinshipCalculator {

    struct KinshipResult {
        let relationship: String       // وصف العلاقة بالعربي والإنجليزي
        let commonAncestor: FamilyMember? // الجد المشترك (nil للزوجين ولمن لا صلة له)
        let pathA: [FamilyMember]      // مسارك للجد المشترك (المصاهرة: أنت ثم زوجتك/زوجك ثم أهلها)
        let pathB: [FamilyMember]      // مسار الثاني للجد المشترك (زوجة قريبك: هي ثم زوجها ثم أهله)
        /// نوع الصلة — إضافة اختيارية للواجهات؛ القيمة الافتراضية تحفظ التوافق
        var kind: Kind = .blood

        nonisolated enum Kind { case same, spouse, blood, inLaw, unknown }
    }

    /// خطوة صعود: عبر الأب أو عبر الأم
    private enum Edge { case father, mother }

    /// أقصر مسار من العضو إلى أحد أسلافه
    private struct Route {
        let path: [FamilyMember]   // [العضو، ...، السلف]
        let edges: [Edge]          // الخطوات بالترتيب من العضو صعوداً
        var distance: Int { edges.count }

        /// العقدة i أنثى؟ — 0 صاحب المسار (من سجلّه). ما فوقه: رابط الأم = أنثى،
        /// وإلا من السجلّ (parent_id في شجرة النساء قد يشير إلى الأم).
        func isFemale(_ i: Int) -> Bool {
            if i > 0, edges[i - 1] == .mother { return true }
            return KinshipCalculator.isFemale(path[i])
        }

        /// عدد النساء فوق صاحب المسار — للترجيح: جهة الأب أولاً
        var femaleSteps: Int { path.indices.dropFirst().filter { isFemale($0) }.count }
    }

    /// تسمية قبل اختيار اللغة، مع صيغتها بعد «زوجة/زوج» (زوجة ابن عمك، زوجة أحد أقاربك)
    private struct Label {
        let ar: String
        let en: String
        let arOwner: String     // تُكتب بعد «زوجة/زوج»
        let enOwner: String?    // "Your cousin's" — nil: تُبنى "Wife of …" من enOf
        let enOf: String        // "your cousin" / "one of your relatives"

        init(_ ar: String, _ en: String, arOwner: String? = nil, enPossessive: Bool = true) {
            self.ar = ar
            self.en = en
            self.arOwner = arOwner ?? ar
            self.enOwner = enPossessive ? en + "'s" : nil
            self.enOf = en.prefix(1).lowercased() + en.dropFirst()
        }

        var text: String { L10n.t(ar, en) }
    }

    /// قرابة دم بين شخصين: التسمية + الجد المشترك + المسارين
    private struct Blood {
        let label: Label
        let ancestor: FamilyMember
        let pathA: [FamilyMember]
        let pathB: [FamilyMember]
        let distA: Int          // خطوات الأول إلى الجد المشترك (0 = هو الجد)
        let distB: Int
        let bFemale: Bool       // جنس الثاني
        var span: Int { distA + distB }
    }

    /// حساب صلة القرابة — A هو المستخدم (المخاطَب)، B الشخص الآخر
    /// - includeMaternal: يمرّ بالأم (خال، جد لأم...) — لشجرة النساء فقط. شجرة العائلة تبقى أبوية.
    static func calculate(
        from memberA: FamilyMember,
        to memberB: FamilyMember,
        lookup: [UUID: FamilyMember],
        includeMaternal: Bool = false
    ) -> KinshipResult {
        // نفس الشخص
        if memberA.id == memberB.id {
            return KinshipResult(
                relationship: L10n.t("أنت", "You"),
                commonAncestor: memberA,
                pathA: [memberA],
                pathB: [memberB],
                kind: .same
            )
        }

        // في شجرة النساء: السجلّ الكامل من الجدول — العضو الممرَّر قد يفتقد رابط الأم
        let memberA = includeMaternal ? (lookup[memberA.id] ?? memberA) : memberA
        let memberB = includeMaternal ? (lookup[memberB.id] ?? memberB) : memberB

        // ١) الزوجان — أقرب صلة، حتى لو كانت الزوجة بنت عمك
        if memberB.husbandId == memberA.id {
            return KinshipResult(relationship: L10n.t("زوجتك", "Your wife"), commonAncestor: nil,
                                 pathA: [memberA], pathB: [memberB], kind: .spouse)
        }
        if memberA.husbandId == memberB.id {
            return KinshipResult(relationship: L10n.t("زوجك", "Your husband"), commonAncestor: nil,
                                 pathA: [memberA], pathB: [memberB], kind: .spouse)
        }

        // ٢) قرابة الدم — تسبق المصاهرة دائماً (الأم «أمك» لا «زوجة أبوك»)
        let routesA = ancestorRoutes(for: memberA, lookup: lookup, includeMaternal: includeMaternal)
        if let blood = bloodRelation(memberA, memberB, routesA: routesA,
                                     lookup: lookup, includeMaternal: includeMaternal) {
            return KinshipResult(relationship: blood.label.text, commonAncestor: blood.ancestor,
                                 pathA: blood.pathA, pathB: blood.pathB, kind: .blood)
        }

        // ٣) المصاهرة: زوجة قريبك، أهل زوجتك/زوجك، زوج قريبتك
        if let inLaw = inLawRelation(memberA, memberB, routesA: routesA,
                                     lookup: lookup, includeMaternal: includeMaternal) {
            return inLaw
        }

        // ما لقينا صلة
        return KinshipResult(
            relationship: L10n.t("من العائلة", "Family member"),
            commonAncestor: nil,
            pathA: ancestorPath(for: memberA, lookup: lookup),
            pathB: ancestorPath(for: memberB, lookup: lookup),
            kind: .unknown
        )
    }

    /// بناء مسار الأجداد: [العضو، أبوه، جده، جد جده...]
    /// النسب أبويّ بطبيعته — لا يمرّ بالأم (يستخدمه نص النسب ورمز QR).
    static func ancestorPath(for member: FamilyMember, lookup: [UUID: FamilyMember]) -> [FamilyMember] {
        var path: [FamilyMember] = [member]
        var current = member
        var visited: Set<UUID> = [member.id]

        while let fatherId = current.fatherId,
              let father = lookup[fatherId],
              !visited.contains(father.id) {
            path.append(father)
            visited.insert(father.id)
            current = father
        }

        return path
    }

    /// سلسلة النسب كنص: "حسن صلاح عبدالله..."
    static func lineageText(for member: FamilyMember, lookup: [UUID: FamilyMember], maxDepth: Int = 8) -> String {
        let path = ancestorPath(for: member, lookup: lookup)
        let names = path.prefix(maxDepth).map(\.firstName)
        return names.joined(separator: " ")
    }

    // MARK: - Private: الصعود

    /// أنثى؟ — من السجلّ، أو قرينة: لها زوج مسجَّل
    private static func isFemale(_ m: FamilyMember) -> Bool {
        m.isFemale || m.husbandId != nil
    }

    /// أقصر مسار لكل سلف (BFS، والزيارة المسجّلة تمنع الدوران). الأب يُستكشف قبل الأم فيفوز عند التساوي.
    /// شجرة العائلة: الصعود عبر الآباء فقط، وأمّ كل واحد على الطريق تُضاف بلا صعود منها
    /// (أمك، جدتك) — فلا خال ولا ابن خالة إلا في شجرة النساء.
    private static func ancestorRoutes(for member: FamilyMember, lookup: [UUID: FamilyMember],
                                       includeMaternal: Bool) -> [UUID: Route] {
        var routes: [UUID: Route] = [member.id: Route(path: [member], edges: [])]
        var queue: [Route] = [routes[member.id]!]
        var head = 0
        while head < queue.count {
            let route = queue[head]
            head += 1
            guard let node = route.path.last else { continue }
            for (edge, parentId) in [(Edge.father, node.fatherId), (Edge.mother, node.motherId)] {
                guard let parentId, routes[parentId] == nil, let parent = lookup[parentId] else { continue }
                let next = Route(path: route.path + [parent], edges: route.edges + [edge])
                routes[parentId] = next
                if includeMaternal || edge == .father { queue.append(next) }
            }
        }
        return routes
    }

    /// قرابة الدم بين a وb (التسمية من جهة a) — nil إن لم يجمعهما سلف
    private static func bloodRelation(_ a: FamilyMember, _ b: FamilyMember, routesA cached: [UUID: Route]? = nil,
                                      lookup: [UUID: FamilyMember], includeMaternal: Bool) -> Blood? {
        guard a.id != b.id else { return nil }
        let routesA = cached ?? ancestorRoutes(for: a, lookup: lookup, includeMaternal: includeMaternal)
        let routesB = ancestorRoutes(for: b, lookup: lookup, includeMaternal: includeMaternal)

        // B أحد أسلافك (أب، أم، جد...)
        if let route = routesA[b.id], route.distance > 0 {
            return Blood(label: ancestorLabel(route), ancestor: b, pathA: route.path, pathB: [b],
                         distA: route.distance, distB: 0, bFemale: route.isFemale(route.distance))
        }

        // أنت أحد أسلاف B
        if let route = routesB[a.id], route.distance > 0 {
            return Blood(label: descendantLabel(route), ancestor: a, pathA: [a], pathB: route.path,
                         distA: 0, distB: route.distance, bFemale: route.isFemale(0))
        }

        // الجد المشترك الأقرب: أقل مجموع مسافة، ثم أقل نساء على الطريقين (جهة الأب أولاً)،
        // ثم الأقرب لك، ثم جهة أبوك، ثم المعرّف — فالنتيجة ثابتة لا تتبع ترتيب القاموس
        var best: (key: (Int, Int, Int, Int, String), ancestor: FamilyMember, a: Route, b: Route)?
        for (id, routeA) in routesA where routeA.distance > 0 {
            guard let routeB = routesB[id], routeB.distance > 0, let ancestor = routeA.path.last else { continue }
            let key = (routeA.distance + routeB.distance, routeA.femaleSteps + routeB.femaleSteps,
                       routeA.distance, routeA.femaleSteps, id.uuidString)
            if let current = best, !(key < current.key) { continue }
            best = (key, ancestor, routeA, routeB)
        }
        guard let best else { return nil }
        return Blood(label: collateralLabel(routeA: best.a, routeB: best.b, a: a, b: b,
                                            includeMaternal: includeMaternal),
                     ancestor: best.ancestor, pathA: best.a.path, pathB: best.b.path,
                     distA: best.a.distance, distB: best.b.distance, bFemale: best.b.isFemale(0))
    }

    // MARK: - Private: تسمية قرابة الدم

    /// B سلف لك — المسار منك صعوداً إليه
    private static func ancestorLabel(_ route: Route) -> Label {
        let d = route.distance
        let female = route.isFemale(d)
        switch d {
        case 1:
            return female ? Label("أمك", "Your mother") : Label("أبوك", "Your father")
        case 2:
            // جهة الأب هي الأصل (جدك، جدتك) — جهة الأم تُذكر
            if route.isFemale(1) {
                return female ? Label("جدتك أم أمك", "Your maternal grandmother")
                              : Label("جدك أبو أمك", "Your maternal grandfather")
            }
            return female ? Label("جدتك", "Your grandmother") : Label("جدك", "Your grandfather")
        case 3:
            // جد/جدة أحد والديك: جد أبوك، جدة أمك
            let viaMother = route.isFemale(1)
            let parentAr = viaMother ? "أمك" : "أبوك"
            let parentEn = viaMother ? "mother's" : "father's"
            return female ? Label("جدة \(parentAr)", "Your \(parentEn) grandmother")
                          : Label("جد \(parentAr)", "Your \(parentEn) grandfather")
        default:
            return female
                ? Label("من جداتك", "One of your ancestors", arOwner: "إحدى جداتك", enPossessive: false)
                : Label("من أجدادك", "One of your ancestors", arOwner: "أحد أجدادك", enPossessive: false)
        }
    }

    /// أنت سلف لـB — المسار منه صعوداً إليك
    private static func descendantLabel(_ route: Route) -> Label {
        let d = route.distance
        let female = route.isFemale(0)
        switch d {
        case 1:
            return female ? Label("بنتك", "Your daughter") : Label("ابنك", "Your son")
        case 2:
            // من ابنك هو الأصل — من بنتك يُذكر
            if route.isFemale(1) {
                return female
                    ? Label("حفيدتك من بنتك", "Your granddaughter (through your daughter)", enPossessive: false)
                    : Label("حفيدك من بنتك", "Your grandson (through your daughter)", enPossessive: false)
            }
            return female ? Label("حفيدتك", "Your granddaughter") : Label("حفيدك", "Your grandson")
        case 3:
            // ابن/بنت حفيدك أو حفيدتك
            let viaGranddaughter = route.isFemale(1)
            let gcAr = viaGranddaughter ? "حفيدتك" : "حفيدك"
            let gcEn = viaGranddaughter ? "granddaughter's" : "grandson's"
            return female ? Label("بنت \(gcAr)", "Your \(gcEn) daughter")
                          : Label("ابن \(gcAr)", "Your \(gcEn) son")
        default:
            return female
                ? Label("من حفيداتك", "One of your descendants", arOwner: "إحدى حفيداتك", enPossessive: false)
                : Label("من أحفادك", "One of your descendants", arOwner: "أحد أحفادك", enPossessive: false)
        }
    }

    /// الأقارب الجانبيون: B من نسل أخ/أخت أحد أسلافك (أو أخوك نفسه).
    /// Q ابن الجد المشترك من جهة B، وP ابنه من جهتك: P رجل → عم، امرأة → خال.
    /// أمثلة: عمك، خالتك، عم أبوك، خال أمك، عم جدك، ابن أختك، بنت ابن عمك، ابن ابن عم أبوك.
    private static func collateralLabel(routeA: Route, routeB: Route, a: FamilyMember, b: FamilyMember,
                                        includeMaternal: Bool) -> Label {
        let distA = routeA.distance
        let distB = routeB.distance
        let female = routeB.isFemale(0)

        if distA == 1 && distB == 1 {
            // الإخوة — في شجرة النساء فقط يُميَّز: من أبوك، من أمك
            if includeMaternal {
                let sameFather = a.fatherId != nil && a.fatherId == b.fatherId
                let sameMother = a.motherId != nil && a.motherId == b.motherId
                let mothersDiffer = a.motherId != nil && b.motherId != nil && a.motherId != b.motherId
                if sameMother && !sameFather {
                    return female ? Label("أختك من أمك", "Your maternal half-sister")
                                  : Label("أخوك من أمك", "Your maternal half-brother")
                }
                if sameFather && mothersDiffer {
                    return female ? Label("أختك من أبوك", "Your paternal half-sister")
                                  : Label("أخوك من أبوك", "Your paternal half-brother")
                }
            }
            return female ? Label("أختك", "Your sister") : Label("أخوك", "Your brother")
        }

        // أبعد من عم جدك أو من حفيد ابن عمه
        guard distA <= 4, distB <= 3 else { return distantLabel(distA: distA, distB: distB, female: female) }

        let qFemale = routeB.isFemale(distB - 1)
        let qAr: String
        if distA == 1 {
            qAr = qFemale ? "أختك" : "أخوك"
        } else {
            let uncle = routeA.isFemale(distA - 1) ? (qFemale ? "خالة" : "خال") : (qFemale ? "عمة" : "عم")
            switch distA {
            case 2:  qAr = (qFemale ? String(uncle.dropLast()) + "ت" : uncle) + "ك"   // عمة → عمتك
            case 3:  qAr = uncle + (routeA.isFemale(1) ? " أمك" : " أبوك")
            default: qAr = uncle + (routeA.isFemale(2) ? " جدتك" : " جدك")
            }
        }
        // النزول من Q إلى B: ابن/بنت لكل جيل، وجنس كل واحد من رابطه
        let chain = (0..<(distB - 1)).map { routeB.isFemale($0) ? "بنت" : "ابن" }
        let ar = (chain + [qAr]).joined(separator: " ")

        let en: String
        if distA == 1 {
            let sibling = "Your " + (qFemale ? "sister's " : "brother's ")
            en = sibling + (distB == 2 ? (female ? "daughter" : "son") : (female ? "granddaughter" : "grandson"))
        } else {
            let owner: String
            switch distA {
            case 2:  owner = "Your "
            case 3:  owner = "Your " + (routeA.isFemale(1) ? "mother's " : "father's ")
            default: owner = "Your " + (routeA.isFemale(2) ? "grandmother's " : "grandfather's ")
            }
            switch distB {
            case 1:
                let side = distA == 2 ? (routeA.isFemale(1) ? "maternal " : "paternal ") : ""
                en = owner + side + (qFemale ? "aunt" : "uncle")
            case 2:
                en = owner + "cousin"
            default:
                en = owner + "cousin's " + (female ? "daughter" : "son")
            }
        }
        return Label(ar, en)
    }

    /// علاقة بعيدة
    private static func distantLabel(distA: Int, distB: Int, female: Bool) -> Label {
        if distA == distB {
            return Label((female ? "قريبتك" : "قريبك") + " من الدرجة \(distA)",
                         "Your relative (degree \(distA))", enPossessive: false)
        }
        return female
            ? Label("من قريباتك", "One of your relatives", arOwner: "إحدى قريباتك", enPossessive: false)
            : Label("من أقاربك", "One of your relatives", arOwner: "أحد أقاربك", enPossessive: false)
    }

    // MARK: - Private: المصاهرة

    /// صلة عبر زواج واحد — الأقرب يفوز، وعند التساوي: زوجة قريبك ← أهل زوجتك/زوجك ← زوج قريبتك.
    /// الزوجات قد يكنّ مخفيّات من الشجرة لكنهنّ في lookup — يُبحث في الاتجاهين.
    private static func inLawRelation(_ a: FamilyMember, _ b: FamilyMember, routesA: [UUID: Route],
                                      lookup: [UUID: FamilyMember], includeMaternal: Bool) -> KinshipResult? {
        var best: (key: (Int, Int, String), result: KinshipResult)?
        func offer(_ key: (Int, Int, String), _ result: KinshipResult) {
            if let current = best, !(key < current.key) { return }
            best = (key, result)
        }

        // أ) B زوجة قريبك: زوجة ابنك، زوجة أخوك، زوجة ابن عمك، زوجة أبوك (حين لا تكون أمك)
        if let rid = b.husbandId, rid != a.id, let r = lookup[rid],
           let blood = bloodRelation(a, r, routesA: routesA, lookup: lookup, includeMaternal: includeMaternal) {
            offer((blood.span + 1, 0, r.id.uuidString),
                  KinshipResult(relationship: spouseLabel(of: blood.label, wife: true).text,
                                commonAncestor: blood.ancestor, pathA: blood.pathA,
                                pathB: [b] + blood.pathB, kind: .inLaw))
        }

        // ب) أهل زوجتك: أبو/أم/أخو/أخت/ابن/بنت زوجتك، والبقية «من أهل زوجتك»
        // د) B زوج قريبتك: زوج بنتك، زوج أختك، زوج عمتك
        for m in lookup.values {
            if m.husbandId == a.id, m.id != b.id,
               let blood = bloodRelation(m, b, lookup: lookup, includeMaternal: includeMaternal) {
                offer((blood.span + 1, 1, m.id.uuidString),
                      KinshipResult(relationship: spouseFamilyLabel(blood, ofWife: true).text,
                                    commonAncestor: blood.ancestor, pathA: [a] + blood.pathA,
                                    pathB: blood.pathB, kind: .inLaw))
            }
            if m.husbandId == b.id, m.id != a.id,
               let blood = bloodRelation(a, m, routesA: routesA, lookup: lookup, includeMaternal: includeMaternal) {
                offer((blood.span + 1, 2, m.id.uuidString),
                      KinshipResult(relationship: spouseLabel(of: blood.label, wife: false).text,
                                    commonAncestor: blood.ancestor, pathA: blood.pathA,
                                    pathB: [b] + blood.pathB, kind: .inLaw))
            }
        }

        // ج) أهل زوجك: أبو/أم/أخو/أخت/ابن/بنت زوجك، والبقية «من أهل زوجك»
        if let hid = a.husbandId, hid != b.id, let h = lookup[hid],
           let blood = bloodRelation(h, b, lookup: lookup, includeMaternal: includeMaternal) {
            offer((blood.span + 1, 1, h.id.uuidString),
                  KinshipResult(relationship: spouseFamilyLabel(blood, ofWife: false).text,
                                commonAncestor: blood.ancestor, pathA: [a] + blood.pathA,
                                pathB: blood.pathB, kind: .inLaw))
        }

        return best?.result
    }

    /// «زوجة/زوج» + صلتك بقريبك: زوجة ابنك، زوجة أحد أقاربك، زوج بنتك
    private static func spouseLabel(of r: Label, wife: Bool) -> Label {
        let ar = (wife ? "زوجة " : "زوج ") + r.arOwner
        let en = r.enOwner.map { $0 + (wife ? " wife" : " husband") }
            ?? (wife ? "Wife of " : "Husband of ") + r.enOf
        return Label(ar, en)
    }

    /// B من أهل زوجتك/زوجك — الأقربون بالاسم، والبقية «من أهل …»
    private static func spouseFamilyLabel(_ blood: Blood, ofWife: Bool) -> Label {
        let sAr = ofWife ? "زوجتك" : "زوجك"
        let sEn = ofWife ? "wife's" : "husband's"
        let female = blood.bFemale
        switch (blood.distA, blood.distB) {
        case (1, 0): return female ? Label("أم \(sAr)", "Your \(sEn) mother") : Label("أبو \(sAr)", "Your \(sEn) father")
        case (1, 1): return female ? Label("أخت \(sAr)", "Your \(sEn) sister") : Label("أخو \(sAr)", "Your \(sEn) brother")
        case (0, 1): return female ? Label("بنت \(sAr)", "Your \(sEn) daughter") : Label("ابن \(sAr)", "Your \(sEn) son")
        default:     return Label("من أهل \(sAr)", "From your \(sEn) family")
        }
    }
}
