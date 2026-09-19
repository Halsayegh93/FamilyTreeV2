import Foundation

// MARK: - KinshipCalculator
// حاسبة صلة القرابة — يلقى الجد المشترك ويحدد العلاقة بين عضوين
// شجرة العائلة: جهة الأب فقط. شجرة النساء: الجهتان (includeMaternal) — عند التساوي تُرجَّح جهة الأب.

enum KinshipCalculator {

    struct KinshipResult {
        let relationship: String       // وصف العلاقة بالعربي والإنجليزي
        let commonAncestor: FamilyMember? // الجد المشترك
        let pathA: [FamilyMember]      // مسار العضو الأول للجد المشترك
        let pathB: [FamilyMember]      // مسار العضو الثاني للجد المشترك
    }

    /// خطوة صعود: عبر الأب أو عبر الأم
    private enum Edge { case father, mother }

    /// أقصر مسار من العضو إلى أحد أسلافه
    private struct Route {
        let path: [FamilyMember]   // [العضو، ...، السلف]
        let edges: [Edge]          // الخطوات بالترتيب من العضو صعوداً
        var distance: Int { edges.count }
        var motherSteps: Int { edges.filter { $0 == .mother }.count }
        var isPaternal: Bool { motherSteps == 0 }
    }

    /// حساب صلة القرابة بين عضوين
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
                relationship: L10n.t("نفس الشخص", "Same person"),
                commonAncestor: memberA,
                pathA: [memberA],
                pathB: [memberB]
            )
        }

        // في شجرة النساء: السجلّ الكامل من الجدول — العضو الممرَّر قد يفتقد رابط الأم
        let memberA = includeMaternal ? (lookup[memberA.id] ?? memberA) : memberA
        let memberB = includeMaternal ? (lookup[memberB.id] ?? memberB) : memberB

        let routesA = ancestorRoutes(for: memberA, lookup: lookup, includeMaternal: includeMaternal)
        let routesB = ancestorRoutes(for: memberB, lookup: lookup, includeMaternal: includeMaternal)

        // B هو أحد أسلاف A (أب، أم، جد...)
        if let route = routesA[memberB.id], route.distance > 0 {
            let label = route.isPaternal
                ? descendantLabel(distance: route.distance, gender: memberA.gender)
                : maternalAncestorLabel(route: route, a: memberA, b: memberB)
            return KinshipResult(relationship: label, commonAncestor: memberB,
                                 pathA: route.path, pathB: [memberB])
        }

        // A هو أحد أسلاف B
        if let route = routesB[memberA.id], route.distance > 0 {
            let label = route.isPaternal
                ? ancestorLabel(distance: route.distance, gender: memberA.gender)
                : maternalDescendantLabel(route: route, a: memberA, b: memberB)
            return KinshipResult(relationship: label, commonAncestor: memberA,
                                 pathA: [memberA], pathB: route.path)
        }

        // الجد المشترك الأقرب: أقل مجموع مسافة، ثم أقل خطوات عبر الأم، ثم الأقرب لـA
        var best: (ancestor: FamilyMember, a: Route, b: Route)?
        for (id, routeA) in routesA where routeA.distance > 0 {
            guard let routeB = routesB[id], routeB.distance > 0,
                  let ancestor = routeA.path.last else { continue }
            if let current = best {
                let lhs = (routeA.distance + routeB.distance, routeA.motherSteps + routeB.motherSteps, routeA.distance)
                let rhs = (current.a.distance + current.b.distance, current.a.motherSteps + current.b.motherSteps, current.a.distance)
                if lhs < rhs { best = (ancestor, routeA, routeB) }
            } else {
                best = (ancestor, routeA, routeB)
            }
        }

        if let best {
            let label = collateralLabel(routeA: best.a, routeB: best.b, a: memberA, b: memberB,
                                        includeMaternal: includeMaternal)
            return KinshipResult(relationship: label, commonAncestor: best.ancestor,
                                 pathA: best.a.path, pathB: best.b.path)
        }

        // ما لقينا جد مشترك
        return KinshipResult(
            relationship: L10n.t("من العائلة", "Family member"),
            commonAncestor: nil,
            pathA: ancestorPath(for: memberA, lookup: lookup),
            pathB: ancestorPath(for: memberB, lookup: lookup)
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

    // MARK: - Private: الصعود على الجهتين

    /// أقصر مسار لكل سلف (BFS). الأب يُستكشف قبل الأم فيفوز عند التساوي.
    private static func ancestorRoutes(for member: FamilyMember, lookup: [UUID: FamilyMember],
                                       includeMaternal: Bool) -> [UUID: Route] {
        var routes: [UUID: Route] = [member.id: Route(path: [member], edges: [])]
        var queue: [Route] = [routes[member.id]!]
        var head = 0
        while head < queue.count {
            let route = queue[head]
            head += 1
            guard let node = route.path.last else { continue }
            let parents = includeMaternal
                ? [(Edge.father, node.fatherId), (Edge.mother, node.motherId)]
                : [(Edge.father, node.fatherId)]
            for (edge, parentId) in parents {
                guard let parentId, routes[parentId] == nil, let parent = lookup[parentId] else { continue }
                let next = Route(path: route.path + [parent], edges: route.edges + [edge])
                routes[parentId] = next
                queue.append(next)
            }
        }
        return routes
    }

    // MARK: - Private: تسمية العلاقات

    /// العضو هو حفيد/ابن الشخص الثاني
    private static func descendantLabel(distance: Int, gender: String?) -> String {
        let isMale = gender != "female"
        switch distance {
        case 1: return isMale ? L10n.t("أبوه", "His father") : L10n.t("أبوها", "Her father")
        case 2: return isMale ? L10n.t("جده", "His grandfather") : L10n.t("جدها", "Her grandfather")
        case 3: return L10n.t("جد الجد", "Great grandfather")
        default: return L10n.t("من الأجداد", "Ancestor")
        }
    }

    /// العضو هو أب/جد الشخص الثاني
    private static func ancestorLabel(distance: Int, gender: String?) -> String {
        let isMale = gender != "female"
        switch distance {
        case 1: return isMale ? L10n.t("ابنه", "His son") : L10n.t("بنته", "His daughter")
        case 2: return isMale ? L10n.t("حفيده", "His grandson") : L10n.t("حفيدته", "His granddaughter")
        default: return L10n.t("من الأحفاد", "Descendant")
        }
    }

    /// B سلف لـA عبر مسار يمرّ بالأم (أم، جد لأم، جدة لأب...)
    private static func maternalAncestorLabel(route: Route, a: FamilyMember, b: FamilyMember) -> String {
        let aMale = a.gender != "female"
        let bMale = b.gender != "female"
        switch route.distance {
        case 1:
            return aMale ? L10n.t("أمه", "His mother") : L10n.t("أمها", "Her mother")
        case 2:
            let viaMother = route.edges[0] == .mother
            switch (bMale, viaMother, aMale) {
            case (true, true, true):   return L10n.t("جده لأمه", "His maternal grandfather")
            case (true, true, false):  return L10n.t("جدها لأمها", "Her maternal grandfather")
            case (false, true, true):  return L10n.t("جدته لأمه", "His maternal grandmother")
            case (false, true, false): return L10n.t("جدتها لأمها", "Her maternal grandmother")
            case (_, false, true):     return L10n.t("جدته لأبيه", "His paternal grandmother")
            case (_, false, false):    return L10n.t("جدتها لأبيها", "Her paternal grandmother")
            }
        case 3:
            // جد/جدة أحد الوالدين: جد أبوه، جدة أمه...
            let parentMale = route.edges[0] == .father
            let parentAr = aMale ? (parentMale ? "أبوه" : "أمه") : (parentMale ? "أبوها" : "أمها")
            let parentEn = (aMale ? "His " : "Her ") + (parentMale ? "father's " : "mother's ")
            return L10n.t((bMale ? "جد " : "جدة ") + parentAr, parentEn + (bMale ? "grandfather" : "grandmother"))
        default:
            return L10n.t("من الأجداد", "Ancestor")
        }
    }

    /// A سلف لـB عبر مسار يمرّ بالأم (ابنها، حفيده من بنته...)
    private static func maternalDescendantLabel(route: Route, a: FamilyMember, b: FamilyMember) -> String {
        let aMale = a.gender != "female"
        let bMale = b.gender != "female"
        switch route.distance {
        case 1:
            return bMale ? L10n.t("ابنها", "Her son") : L10n.t("بنتها", "Her daughter")
        case 2:
            // المسار من B: الخطوة الأولى = والد B، فإن كانت أمّاً فـB من بنت A
            let throughDaughter = route.edges[0] == .mother
            let noun = bMale ? "حفيد" : "حفيدت"
            let enNoun = bMale ? "grandson" : "granddaughter"
            let pron = aMale ? "ه" : "ها"
            let enPron = aMale ? "His" : "Her"
            if throughDaughter {
                return L10n.t("\(noun)\(pron) من بنت\(pron)", "\(enPron) \(enNoun) (through daughter)")
            }
            return L10n.t("\(noun)\(pron)", "\(enPron) \(enNoun)")
        default:
            return L10n.t("من الأحفاد", "Descendant")
        }
    }

    /// الأقارب الجانبيون — الجهة (أب/أم) تحدد عم أو خال
    private static func collateralLabel(routeA: Route, routeB: Route, a: FamilyMember, b: FamilyMember,
                                        includeMaternal: Bool) -> String {
        let distA = routeA.distance
        let distB = routeB.distance
        let isMale = b.gender != "female"

        if distA == 1 && distB == 1 {
            // الإخوة — في شجرة النساء فقط يُميَّز: لأب، لأم
            if includeMaternal {
                let sameFather = a.fatherId != nil && a.fatherId == b.fatherId
                let sameMother = a.motherId != nil && a.motherId == b.motherId
                let mothersDiffer = a.motherId != nil && b.motherId != nil && a.motherId != b.motherId
                if sameMother && !sameFather {
                    return isMale ? L10n.t("أخوه لأمه", "His maternal half-brother") : L10n.t("أخته لأمه", "His maternal half-sister")
                }
                if sameFather && mothersDiffer {
                    return isMale ? L10n.t("أخوه لأبيه", "His paternal half-brother") : L10n.t("أخته لأبيه", "His paternal half-sister")
                }
            }
            return isMale ? L10n.t("أخوه", "His brother") : L10n.t("أخته", "His sister")
        }

        // جهة الأب خالصة: التسميات القديمة كما هي
        if routeA.isPaternal && routeB.isPaternal {
            return cousinLabel(distA: distA, distB: distB, gender: b.gender)
        }
        return composedLabel(routeA: routeA, routeB: routeB, a: a, b: b)
            ?? distantLabel(distA: distA, distB: distB)
    }

    /// جنس العقدة رقم i على المسار: الأولى من سجلّها، والباقي من نوع الخطوة (أب = ذكر، أم = أنثى)
    private static func isMaleNode(_ route: Route, _ i: Int, origin: FamilyMember) -> Bool {
        i == 0 ? origin.gender != "female" : route.edges[i - 1] == .father
    }

    /// تسمية مركّبة لمسار يمرّ بالأم: B ينحدر من أخ/أخت أحد أسلاف A.
    /// أمثلة: خاله، خال أبوه، عم أمه، خالة جدته، ابن خال أبوه، ابن بنت خالته.
    private static func composedLabel(routeA: Route, routeB: Route, a: FamilyMember, b: FamilyMember) -> String? {
        let distA = routeA.distance
        let distB = routeB.distance
        guard (1...4).contains(distA), (1...3).contains(distB) else { return nil }

        // Q: ابن الجد المشترك من جهة B (أخو/أخت العقدة P من جهة A)
        let qMale = isMaleNode(routeB, distB - 1, origin: b)

        var qAr: String
        var qEn: String
        if distA == 1 {
            // Q أخو/أخت A نفسه
            qAr = qMale ? "أخوه" : "أخته"
            qEn = qMale ? "his brother" : "his sister"
        } else {
            // P والد/جد A الملاصق للجد المشترك: ذكر → عم، أنثى → خال
            let pMale = isMaleNode(routeA, distA - 1, origin: a)
            let uncleAr = pMale ? (qMale ? "عم" : "عمة") : (qMale ? "خال" : "خالة")
            let uncleEn = (pMale ? "paternal " : "maternal ") + (qMale ? "uncle" : "aunt")
            if distA == 2 {
                // التاء المربوطة تُفتح قبل الضمير: خالة → خالته
                qAr = (uncleAr.hasSuffix("ة") ? String(uncleAr.dropLast()) + "ت" : uncleAr) + "ه"
                qEn = "his " + uncleEn
            } else {
                // R: سلف A الذي يُنسب إليه العم/الخال (أبوه، أمه، جده، جدته)
                let rMale = isMaleNode(routeA, distA - 2, origin: a)
                switch distA - 2 {
                case 1:
                    qAr = "\(uncleAr) " + (rMale ? "أبوه" : "أمه")
                    qEn = "his " + (rMale ? "father's " : "mother's ") + uncleEn
                case 2:
                    qAr = "\(uncleAr) " + (rMale ? "جده" : "جدته")
                    qEn = "his " + (rMale ? "grandfather's " : "grandmother's ") + uncleEn
                default:
                    return nil
                }
            }
        }

        // النزول من Q إلى B: ابن/بنت لكل جيل
        var downAr: [String] = []
        var downEn: [String] = []
        for i in 0..<(distB - 1) {
            let male = isMaleNode(routeB, i, origin: b)
            downAr.append(male ? "ابن" : "بنت")
            downEn.append(male ? "son of" : "daughter of")
        }
        let ar = (downAr + [qAr]).joined(separator: " ")
        let en = (downEn + [qEn]).joined(separator: " ")
        return L10n.t(ar, en.prefix(1).uppercased() + en.dropFirst())
    }

    /// تسمية أبناء العمومة والأقارب الجانبيين (الجهة الأبوية)
    private static func cousinLabel(distA: Int, distB: Int, gender: String?) -> String {
        let isMale = gender != "female"

        // عم (أخو أبوه)
        if distA == 2 && distB == 1 {
            return isMale ? L10n.t("عمه", "His uncle") : L10n.t("عمته", "His aunt")
        }

        // ابن الأخ
        if distA == 1 && distB == 2 {
            return isMale ? L10n.t("ابن أخوه", "His nephew") : L10n.t("بنت أخوه", "His niece")
        }

        // أبناء العمومة (ابن عم)
        if distA == 2 && distB == 2 {
            return isMale ? L10n.t("ابن عمه", "His cousin") : L10n.t("بنت عمه", "His cousin")
        }

        // عم الأب (أخو الجد)
        if distA == 3 && distB == 1 {
            return L10n.t("عم أبوه", "His father's uncle")
        }

        // ابن ابن الأخ
        if distA == 1 && distB == 3 {
            return L10n.t("ابن ابن أخوه", "Grand nephew")
        }

        // ابن عم الأب
        if distA == 3 && distB == 2 {
            return L10n.t("ابن عم أبوه", "Father's cousin")
        }

        if distA == 2 && distB == 3 {
            return L10n.t("ابن ابن عمه", "Cousin's son")
        }

        // أبناء عمومة بعيدين
        if distA == 3 && distB == 3 {
            return L10n.t("ابن عم أبوه", "Second cousin")
        }

        return distantLabel(distA: distA, distB: distB)
    }

    /// علاقة بعيدة
    private static func distantLabel(distA: Int, distB: Int) -> String {
        let minDist = min(distA, distB)
        let maxDist = max(distA, distB)
        if minDist == maxDist {
            return L10n.t("قريب من الدرجة \(minDist)", "Relative (degree \(minDist))")
        }
        return L10n.t("قريب", "Relative")
    }
}
