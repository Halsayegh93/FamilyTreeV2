import Foundation
import CoreGraphics

// منطق خالص لشاشة الشجرة (مراجعة ٢٠٢٦-١١-٢٧) — بلا SwiftUI، يُفحص بلا محاكي: tests/admin-redesign/T1/main.swift

/// إلى أين يأخذ زرّ «موقعك» — مكان واحد للوضعين العمودي والأفقي (كان الأفقي وحده يعرف شجرة النساء والحساب غير المربوط)
nonisolated enum TreeMyPlace: Equatable {
    /// عقدته في شجرة العائلة ومتصلة بالجذر — يُنقل إليها
    case family(UUID)
    /// مكانه في شجرة النساء (ابن بنت، أو حساب امرأة) — يُنقل لتبويب النساء
    case women
    /// لا مكان له بعد — رسالة «حسابك غير مربوط بالشجرة بعد»
    case notLinked

    /// - userId: حساب المستخدم (nil = لا شيء يحدث)
    /// - rootId: رأس شجرة العائلة الظاهر
    /// - fatherOf: أبو العضو داخل الشجرة الظاهرة (nil = ليس فيها أو بلا أب)
    /// - isInTree: العضو ضمن أفراد شجرة العائلة الظاهرين
    /// - inWomenTree: مكانه في شجرة النساء (`TreeView.placeIsInWomenTree`)
    /// - hasWomenTab: تبويب النساء متاح هنا
    static func resolve(userId: UUID?, rootId: UUID?,
                        isInTree: (UUID) -> Bool, fatherOf: (UUID) -> UUID?,
                        inWomenTree: Bool, hasWomenTab: Bool) -> TreeMyPlace? {
        guard let userId else { return nil }
        if isInTree(userId), reachesRoot(userId, rootId: rootId, fatherOf: fatherOf) {
            return .family(userId)
        }
        if hasWomenTab && inWomenTree { return .women }
        return .notLinked
    }

    /// سلسلة الآباء تصل للرأس — حساب بلا أب (غير مربوط) موجود بين الأفراد لكنه بلا مكان في الرسم
    static func reachesRoot(_ id: UUID, rootId: UUID?, fatherOf: (UUID) -> UUID?) -> Bool {
        guard let rootId else { return false }
        var cur: UUID? = id
        var seen = Set<UUID>()
        while let c = cur, seen.insert(c).inserted {
            if c == rootId { return true }
            cur = fatherOf(c)
        }
        return false
    }
}

/// الكاميرا عند الانتقال لعضو («موقعك»، نتيجة البحث، مسار الأسماء، صلة القرابة): التكبير الافتراضي، والعضو بمنتصف
/// الشاشة أفقياً؛ عمودياً تتوسّط المساحة الظاهرة أكبر مجموعة تتّسع من: الأب + العضو + أول صف من أبنائه الظاهرين ←
/// الأب + العضو ← العضو + أبناؤه ← العضو وحده. فيظهر الأب تحت بطاقة الأدوات لا تحتها، ولا يبقى نصف الشاشة فارغاً
nonisolated enum TreeFocusCamera {
    /// - member/father/kids: إطارات بإحداثيات الكانفس (kids = إطار أول صف من الأبناء الظاهرين)
    /// - avail: المساحة الظاهرة على الشاشة (تحت الأدوات وفوق الشريط السفلي)
    /// - bandMidX: منتصف الشاشة الأفقي
    /// - fallbackAnchorY: موضع العضو من المساحة إن لم يتّسع حتى وحده
    static func offset(member: CGRect, father: CGRect?, kids: CGRect?, avail: CGRect, bandMidX: CGFloat,
                       scale s: CGFloat, fallbackAnchorY: CGFloat) -> CGSize {
        let x = bandMidX - member.midX * s
        var candidates: [CGRect] = []
        if let father, let kids { candidates.append(member.union(father).union(kids)) }
        if let father { candidates.append(member.union(father)) }
        if let kids { candidates.append(member.union(kids)) }
        candidates.append(member)
        for r in candidates where r.height * s <= avail.height {
            return CGSize(width: x, height: avail.midY - r.midY * s)
        }
        return CGSize(width: x, height: avail.minY + avail.height * fallbackAnchorY - member.midY * s)
    }
}

/// عدد الأفراد في رأس الشجرة بصيغة الإدارة: «2,728 فرداً» · «فردان» · «5 أفراد» (فاصل الآلاف والتمييز الصحيح)
nonisolated enum TreeHeaderCount {
    static func arabic(_ n: Int) -> String {
        AdminCountForms(one: "فرد واحد", two: "فردان", few: "أفراد", many: "فرداً", single: "فرد").text(n)
    }

    static func english(_ n: Int) -> String {
        "\(AdminNumberText.grouped(n)) " + (n == 1 ? "member" : "members")
    }
}
