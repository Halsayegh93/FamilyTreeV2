import Foundation

// MARK: - مربّع الطلب: المنطق الخالص (إعادة تصميم الإدارة ٢٠٢٦-١١-٢٦، الوحدة U9 — spec C.3 + T3)
//
// ما يقرّره المربّع بلا واجهة: أيّ طلب يأتي بعد القرار (بالمعرّف، بين المعلّق فقط، ويلتفّ للبداية)، موضع المرحلة في
// شريط الخطوات الأربع، معنى ما حدث بعد القرار (نجح · فشل والطلب باقٍ · عالجه غيرك · وصل متأخراً ونجح)، وكم زرّاً يظهر
// في الشريط السفلي والباقي في «المزيد». Foundation فقط — يُفحص بلا محاكي:
//   xcrun swiftc -o /tmp/u9-logic FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminRequestBoxLogic.swift \
//     tests/admin-redesign/U9/main.swift && /tmp/u9-logic

nonisolated enum AdminRequestBoxLogic {
    /// أقلّ مدة يبقى فيها الشريط معطّلاً بعد الانتقال للطلب التالي (spec C.3 / Autoplan note 6) — لا ضغطة على طلب لم يُقرأ
    static let minimumLock: TimeInterval = 0.8
    /// كم يبقى سطر «عالجه فلان» قبل الانتقال
    static let handledNotice: TimeInterval = 1.6
    /// بعد هذه المدة بلا جواب يظهر سطر «الرد يتأخر…» (الشريط يبقى معطّلاً حتى يصل الجواب ويُعاد جلب الطلب)
    static let slowAfter: TimeInterval = 8

    // MARK: الطلب التالي

    /// الطلب التالي بالمعرّف: أول معلّق بعد الحالي في ترتيب القائمة كما ظهرت (الفلاتر والبحث)، ثم يلتفّ للبداية.
    /// الحالي لا يُختار أبداً (قد يبقى معلّقاً بعد توصية أو في تجربة الدور). nil = لا شيء باقٍ
    static func next(after current: String, order: [String], pending: Set<String>) -> String? {
        let candidates = order.filter { $0 != current && pending.contains($0) }
        guard !candidates.isEmpty else { return nil }
        guard let at = order.firstIndex(of: current) else { return candidates.first }
        let after = order[order.index(after: at)...].first { $0 != current && pending.contains($0) }
        return after ?? candidates.first
    }

    // MARK: شريط المراحل

    /// الخطوات الأربع: «وصل» ٠ · «المختص» ١ · «الاعتماد» ٢ · «التنفيذ» ٣ — من قيمة المرحلة الخام (`ApprovalStage`)
    static let trackSteps = 4

    static func trackStep(stage raw: String) -> Int {
        switch raw {
        case "review", "info": return 1
        case "approve": return 2
        case "execute": return 3
        default: return 0
        }
    }

    // MARK: بعد القرار

    enum Outcome: Equatable {
        /// نجح على السيرفر — ينتقل (من القائمة) أو يُغلق (من الإشعار)
        case success
        /// فشل والطلب ما زال معلّقاً — يبقى برسالة الخطأ والأزرار تعود
        case failed
        /// فشل لكن الطلب لم يعد معلّقاً وعالجه غيرك — «عالجه فلان» ثم ينتقل
        case handledElsewhere
    }

    /// `succeeded` جواب القرار · `stillPending` بعد إعادة جلب الطلب · `handlerIsMe` من عالجه أنت (وصل الجواب متأخراً
    /// أو انقطع والطلب نُفّذ فعلاً)
    static func outcome(succeeded: Bool, stillPending: Bool, handlerIsMe: Bool) -> Outcome {
        if succeeded { return .success }
        if stillPending { return .failed }
        return handlerIsMe ? .success : .handledElsewhere
    }

    // MARK: الشريط السفلي

    /// زرّان على الأكثر، والباقي في «المزيد» (spec C.3 البند ٨). `decisions` بترتيب أهميتها، و`extras` لا تظهر
    /// أزراراً أبداً (تحويل، سؤال العضو…)
    static func barSplit(decisions: Int, extras: Int) -> (buttons: Int, more: Int) {
        let buttons = min(decisions, 2)
        return (buttons, max(0, decisions - buttons) + extras)
    }

    // MARK: النصوص

    /// سطر الخطأ فوق الشريط: «تعذّر التنفيذ: …» — إلا إن بدأت الرسالة بالمعنى نفسه
    static func failureLine(_ message: String, arabic: Bool) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = arabic ? "تعذّر" : "Couldn"
        if trimmed.isEmpty { return arabic ? "تعذّر التنفيذ — لم يُطبَّق شيء. حاول مرة أخرى." : "Couldn't complete it — nothing was applied. Try again." }
        if trimmed.hasPrefix(lead) { return trimmed }
        return (arabic ? "تعذّر التنفيذ: " : "Couldn't complete it: ") + trimmed
    }

    /// النهاية: «كل الطلبات عولجت» — أو «… بهذه الفلاتر» حين يبقى معلّق خارجها
    static func endTitle(othersOutsideFilter: Bool, arabic: Bool) -> String {
        if othersOutsideFilter {
            return arabic ? "عولجت كل الطلبات بهذه الفلاتر" : "Every request in these filters is handled"
        }
        return arabic ? "كل الطلبات عولجت" : "Every request is handled"
    }
}
