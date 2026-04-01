import Foundation

// MARK: - KinshipCalculator
// حاسبة صلة القرابة — يلقى الجد المشترك ويحدد العلاقة بين عضوين

enum KinshipCalculator {

    struct KinshipResult {
        let relationship: String       // وصف العلاقة بالعربي والإنجليزي
        let commonAncestor: FamilyMember? // الجد المشترك
        let pathA: [FamilyMember]      // مسار العضو الأول للجد المشترك
        let pathB: [FamilyMember]      // مسار العضو الثاني للجد المشترك
    }

    /// حساب صلة القرابة بين عضوين
    static func calculate(
        from memberA: FamilyMember,
        to memberB: FamilyMember,
        lookup: [UUID: FamilyMember]
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

        // بناء مسار الأجداد لكل عضو
        let pathA = ancestorPath(for: memberA, lookup: lookup)
        let pathB = ancestorPath(for: memberB, lookup: lookup)

        // B هو أحد أجداد A (أب، جد، جد الجد...)
        if let indexInA = pathA.firstIndex(where: { $0.id == memberB.id }) {
            let dist = indexInA
            return KinshipResult(
                relationship: descendantLabel(distance: dist, gender: memberA.gender),
                commonAncestor: memberB,
                pathA: Array(pathA.prefix(through: indexInA)),
                pathB: [memberB]
            )
        }

        // A هو أحد أجداد B
        if let indexInB = pathB.firstIndex(where: { $0.id == memberA.id }) {
            let dist = indexInB
            return KinshipResult(
                relationship: ancestorLabel(distance: dist, gender: memberA.gender),
                commonAncestor: memberA,
                pathA: [memberA],
                pathB: Array(pathB.prefix(through: indexInB))
            )
        }

        // البحث عن الجد المشترك (LCA)
        for (indexA, ancestorA) in pathA.enumerated() {
            if let indexB = pathB.firstIndex(where: { $0.id == ancestorA.id }) {
                let distA = indexA  // المسافة من A للجد المشترك
                let distB = indexB  // المسافة من B للجد المشترك
                let ancestor = ancestorA

                let label = cousinLabel(distA: distA, distB: distB, gender: memberB.gender)
                return KinshipResult(
                    relationship: label,
                    commonAncestor: ancestor,
                    pathA: Array(pathA.prefix(through: indexA)),
                    pathB: Array(pathB.prefix(through: indexB))
                )
            }
        }

        // ما لقينا جد مشترك
        return KinshipResult(
            relationship: L10n.t("من العائلة", "Family member"),
            commonAncestor: nil,
            pathA: pathA,
            pathB: pathB
        )
    }

    /// بناء مسار الأجداد: [العضو، أبوه، جده، جد جده...]
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

    /// تسمية أبناء العمومة والأقارب الجانبيين
    private static func cousinLabel(distA: Int, distB: Int, gender: String?) -> String {
        let isMale = gender != "female"

        // إخوان (نفس الأب)
        if distA == 1 && distB == 1 {
            return isMale ? L10n.t("أخوه", "His brother") : L10n.t("أخته", "His sister")
        }

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

        // علاقة بعيدة
        let minDist = min(distA, distB)
        let maxDist = max(distA, distB)
        if minDist == maxDist {
            return L10n.t("قريب من الدرجة \(minDist)", "Relative (degree \(minDist))")
        }
        return L10n.t("قريب", "Relative")
    }
}
