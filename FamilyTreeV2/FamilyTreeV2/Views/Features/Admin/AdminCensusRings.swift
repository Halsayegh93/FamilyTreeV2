import Foundation
#if !ADMIN_LOGIC_TEST
import SwiftUI
#endif

// MARK: - بطاقة «العائلة»: الحلقات الثلاث + سطران (إعادة التصميم ٢٠٢٦-١١-٢٦ — spec A.10/A.11/C.1/C.12، الوحدة U6)
//
// بطاقة واحدة يضعها «اليوم» (U7) و«الإحصاءات» (U15) تحت عنوان «العائلة»، وتأخذ الأرقام وأفعال الضغط فقط — لا تفتح شيئاً
// بنفسها (الموضع يقرّر الوجهة بـ`AdminAreaRouter`)، ولا تجلب شيئاً:
//  • ثلاث حلقات `DSRingGauge` (`DS.Ring.censusCard` ٧٦/٧): الإجمالي (الحبر `DS.Chart.total`) · الرجال (`DS.Chart.men`) · النساء
//    (`DS.Chart.women`)، كلٌّ فوق مسار من درجة أفتح من لونه (`DS.Chart.*Track`). الحلقة = نسبة الأحياء من مجموعتها، ووسطها
//    النسبة «83٪» ١٥ شبه عريض؛ تحتها الاسم ١٣ رمادي ثم العدد ١٧ شبه عريض «2,991 ‹» — العمود كله زرّ ≥ ٤٤ بجملة للقارئ الصوتي
//    («الرجال: 2,729، 87 بالمئة أحياء. يفتح القائمة»). ألوان السلاسل اجتازت فاحص dataviz على الأبيض و#1C1F25 (spec A.11).
//  • «≈ نسبة الأحياء تقديرية: فيها كبار سن بلا تاريخ وفاة ‹» ١٣ بالذهبي الغامق تحت الحلقات ما دام في «تحقق من الأحياء»
//    (`AdminMemberCounts.oldLiving`) من لم يراجعه المستخدم «حي ✓» (`AdminLivingVerifiedStore`). الأعداد لا تحمل «≈» أبداً.
//  • سطران: «اليوم» = «في التطبيق» (من 2,489 حياً) 170 ‹ · «خارج العائلة» (أحياء) 50 ‹ بمربّع لون `DS.Chart.outside` —
//    خارج العائلة أحياؤه فقط، بلا متوفين (طلب المالك، F1)
//    (تظليل ٤٥° مع «التمييز بدون لون»)؛ «الإحصاءات» = «أحياء» (2,362 رجل و127 امرأة) 2,489 · «متوفون» 502 — بلا سهم.
//  • الحالات (`AdminStoreHealth`): قبل الوصول الحلقات على `DS.Ring.emptyTrack` و«—» (لا صفر)، والرقم «—» لا يُضغط؛ الفشل بلا
//    بيانات = بطاقة «تعذّر تحميل الأرقام» + «أعد المحاولة» مكانها؛ الفشل بعد تحميل = الأرقام + «آخر تحديث 9:12»؛ المرفوض = لا شيء.
//    الصفر يُعرض ولا يفتح شيئاً (spec A.3/A.10).
//  • من أحجام إمكانية الوصول كل حلقة صفّ (`DS.Ring.mediumStacked` بجانب الاسم والعدد والنسبة)، وأفقياً الحلقات بعرض عمود القراءة.
//  • حارس المكدس: جسم `AdminCensusRings` = `AnyView` (والأقسام داخله كذلك) — من يضعها لا يحمل نوعها الكبير.
//
// T2 «الرقم = القائمة» — ما يجب أن يفتحه كل رقم، وعدد أول ما يُرى هناك يساوي الرقم المضغوط (`AdminCensusRoutes.destination`
// يكتبه منطقاً، و`AdminCensusFigures.value(of:)` هو الرقم الذي تُقارَن به القائمة):
//  | الرقم                     | «اليوم» (U7)                                            | «الإحصاءات» (U15)                 | يساوي                |
//  |---------------------------|---------------------------------------------------------|-----------------------------------|----------------------|
//  | الإجمالي 2,991            | `.area(.metrics)` + `.stats(.family)` (الحلقات أول ما يُرى) | لا شيء — بيته الصفحة نفسها، بلا سهم | `total`              |
//  | الرجال 2,729              | `.area(.family)` + `.members(account .all, life .all)`  | نفسه                              | `men` (الفلاتر ممسوحة) |
//  | النساء 262                | المالك والمدير: «نساء العائلة» + `.women(status .all, branch .all)`؛ المراقب: `.openWomenTree` | نفسه | `women` (بلا خارج العائلة) |
//  | في التطبيق 170            | `.area(.metrics)` + `.stats(.inApp)` (عنوانه «170 لهم حساب») | لا يُعرض هناك                    | `inApp` (123 + 47)   |
//  | خارج العائلة 50           | `.area(.metrics)` + `.stats(.outside)` (عنوانه 50)       | لا يُعرض هناك                    | `outsideLiving`      |
//  | «≈ نسبة الأحياء تقديرية» | «العائلة» + `.members(review: .living)` («هل ما زالوا أحياء؟») | نفسه                     | من لم يُراجَع        |
//  | أحياء 2,489 · متوفون 502 | —                                                       | بلا سهم (رجال ونساء مختلطون)      | —                    |
//  170 و50 يخلطان الرجال والنساء فلا قائمة واحدة تحملهما — يفتحان قسم «الإحصاءات» الذي يقسمهما (Autoplan note 3).
//
// الاستعمال:
//   AdminSectionLabel(title: L10n.t("العائلة", "Family"), link: …«الإحصاءات ‹»…)
//   AdminCensusRings(figures: .make(census: census, members: memberVM.allMembers, women: WomenStore.cache),
//                    health: censusHealth,
//                    actions: .init(total: { open(.metrics, .stats(.family)) }, men: { … }, women: { … },
//                                   inApp: { … }, outside: { … }, estimate: { … }, retry: { Task { await reload() } }))
//   «الإحصاءات»: `rows: .livingAndDeceased` و`total: nil`.
//
// الجزء الأول منطق خالص (Foundation) يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u6-logic FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminCensusRings.swift tests/admin-redesign/U6/main.swift && /tmp/u6-logic

// MARK: - ١) الأرقام (منطق خالص)

/// الحلقات الثلاث بترتيبها (الأولى في البداية — يمين العربية)
nonisolated enum AdminCensusRing: String, CaseIterable, Hashable {
    case total, men, women
}

/// كل رقم يُضغط في البطاقة
nonisolated enum AdminCensusNumber: String, CaseIterable, Hashable {
    case total, men, women, inApp, outside, estimate
}

/// أرقام البطاقة — نفس تعريفات `AdminMemberCounts` و`AdminFamilyCensus` (لا تعريف جديد). nil = لم يصل («—»)
nonisolated struct AdminCensusFigures: Equatable {
    /// رجال الشجرة بلا طلبات الانضمام وبلا أبناء البنات (`setMen`)
    var men: Int? = nil
    var menAlive: Int? = nil
    /// نساء العائلة بلا «خارج العائلة» (`setWomen(excluding:)`)
    var women: Int? = nil
    var womenAlive: Int? = nil
    /// الأحياء المسجّلون بتعريف العائلة الواحد (`AdminMemberCounts.setFamilyAccounts`) — رجالاً ونساءً
    var menAccounts: Int? = nil
    var womenAccounts: Int? = nil
    /// «خارج العائلة» الأحياء (`AdminFamilyCensus.outsideTotal`) ومتوفوه (`outsideDeceased(members:women:)` — لا يُعرض منذ F1:
    /// أرقام خارج العائلة للأحياء وحدهم بطلب المالك؛ باقٍ لمن يقرؤه حتى U21)
    var outsideLiving: Int? = nil
    var outsideDeceased: Int? = nil
    /// مرشّحو «تحقق من الأحياء» قبل استبعاد ما راجعه المستخدم (`AdminMemberCounts.oldLiving`) — رجال فقط
    var oldLiving: Set<UUID>? = nil

    var total: Int? { men.flatMap { m in women.map { m + $0 } } }
    var totalAlive: Int? { menAlive.flatMap { m in womenAlive.map { m + $0 } } }
    var menDeceased: Int? { men.flatMap { m in menAlive.map { max(0, m - $0) } } }
    var womenDeceased: Int? { women.flatMap { w in womenAlive.map { max(0, w - $0) } } }
    var totalDeceased: Int? { menDeceased.flatMap { m in womenDeceased.map { m + $0 } } }
    /// «في التطبيق» = المسجّلون الأحياء (123 رجل + 47 امرأة) — nil قبل وصول قوائم الحسابات (لا رقم بتعريف آخر)
    var inApp: Int? { menAccounts.flatMap { m in womenAccounts.map { m + $0 } } }

    func count(_ ring: AdminCensusRing) -> Int? {
        switch ring {
        case .total: return total
        case .men:   return men
        case .women: return women
        }
    }

    func alive(_ ring: AdminCensusRing) -> Int? {
        switch ring {
        case .total: return totalAlive
        case .men:   return menAlive
        case .women: return womenAlive
        }
    }

    /// نسبة الأحياء «83٪» — nil قبل الوصول أو لمجموعة فارغة
    func livingShare(_ ring: AdminCensusRing) -> Int? {
        AdminCensusMath.livingShare(alive: alive(ring), of: count(ring))
    }

    /// امتلاء الحلقة ٠…١ — nil = مسار فارغ و«—»
    func progress(_ ring: AdminCensusRing) -> Double? {
        AdminCensusMath.progress(alive: alive(ring), of: count(ring))
    }

    /// كبار السن بلا وفاة مسجّلة لم يراجعهم المستخدم بعد — أكثر من صفر = النسبة تقديرية
    func unverified(verified: Set<UUID>) -> Int {
        oldLiving.map { $0.subtracting(verified).count } ?? 0
    }

    /// الحلقة نسبتها تقديرية: الرجال والإجمالي (المرشّحون رجال)، ما دام فيهم من لم يُراجَع
    func isEstimated(_ ring: AdminCensusRing, verified: Set<UUID>) -> Bool {
        ring != .women && unverified(verified: verified) > 0
    }

    /// الرقم الظاهر الذي يجب أن يساويه أول عدد في وجهته (T2) — nil لـ«≈» (لا رقم ظاهر)
    func value(of number: AdminCensusNumber) -> Int? {
        switch number {
        case .total:    return total
        case .men:      return men
        case .women:    return women
        case .inApp:    return inApp
        case .outside:  return outsideLiving
        case .estimate: return nil
        }
    }
}

/// الحساب الخالص للحلقة
nonisolated enum AdminCensusMath {
    /// نسبة صحيحة بالتقريب لأقرب عدد (2,362 من 2,729 = 87٪ كما في المواصفة)، لكن لا ١٠٠٪ قبل أن تكتمل ولا ٠٪ وفيها أحد —
    /// الجزئي بين ١ و٩٩
    static func livingShare(alive: Int?, of total: Int?) -> Int? {
        guard let alive, let total, total > 0 else { return nil }
        let part = min(max(alive, 0), total)
        let rounded = Int((Double(part) / Double(total) * 100).rounded())
        guard part > 0, part < total else { return rounded }
        return min(max(rounded, 1), 99)
    }

    static func progress(alive: Int?, of total: Int?) -> Double? {
        guard let alive, let total, total > 0 else { return nil }
        return min(max(Double(alive) / Double(total), 0), 1)
    }

    /// يُضغط الرقم حين يفتح شيئاً وقد وصل وليس صفراً (الصفر و«—» يُعرضان بلا سهم — spec A.3/A.10)
    static func opens(value: Int?, hasAction: Bool) -> Bool {
        hasAction && (value ?? 0) > 0
    }
}

// MARK: - ٢) الوجهات (عقد T2، منطق خالص)

/// أين تُعرض البطاقة
nonisolated enum AdminCensusScreen: Hashable {
    /// «اليوم» — سطرا «في التطبيق» و«خارج العائلة»
    case today
    /// «الإحصاءات» — بيت الإجمالي، وسطرا «أحياء» و«متوفون» بلا سهم
    case stats
}

/// ما يفتحه رقم — الموضع (U7/U15) يحوّله إلى `AdminAreaRouter` / `land` / `.openWomenTree`
nonisolated enum AdminCensusDestination: Hashable {
    /// لا شيء (بلا سهم)
    case none
    /// «الإحصاءات» على قسمها (`.area(.metrics)` + `AdminLanding.stats`)
    case stats(AdminStatsAnchor)
    /// «العائلة» بفلاترها (`.area(.family)` + `AdminLanding.members`)
    case members(AdminMembersLanding)
    /// صفحة «نساء العائلة» بفلاترها (المالك والمدير)
    case women(AdminWomenLanding)
    /// تبويب الشجرة على شجرة النساء (`.openWomenTree`) — لمن لا يرى صفحة «نساء العائلة» (المراقب)
    case womenTree
}

nonisolated enum AdminCensusRoutes {
    /// وجهة كل رقم (spec C.1/C.12 وAutoplan note 3): المجموع يفتح القائمة بفلاترها ممسوحة («الحالة» = الكل صراحةً)، والمختلط
    /// (170 · 50) يفتح قسم «الإحصاءات» الذي يقسمه. `seesWomenPage` = المالك والمدير
    static func destination(_ number: AdminCensusNumber, on screen: AdminCensusScreen,
                            seesWomenPage: Bool) -> AdminCensusDestination {
        switch number {
        case .total:
            return screen == .today ? .stats(.family) : .none
        case .men:
            return .members(AdminMembersLanding(account: .all, life: .all))
        case .women:
            return seesWomenPage ? .women(AdminWomenLanding(status: .all, branch: .all)) : .womenTree
        case .inApp:
            return .stats(.inApp)
        case .outside:
            return .stats(.outside)
        case .estimate:
            return .members(AdminMembersLanding(review: .living))
        }
    }
}

// MARK: - ٣) النصوص (منطق خالص)

nonisolated enum AdminCensusText {
    static func ringName(_ ring: AdminCensusRing) -> String {
        switch ring {
        case .total: return L10n.t("الإجمالي", "Total")
        case .men:   return L10n.t("الرجال", "Men")
        case .women: return L10n.t("النساء", "Women")
        }
    }

    static var inAppTitle: String { L10n.t("في التطبيق", "In the app") }
    static var outsideTitle: String { L10n.t("خارج العائلة", "Outside the family") }
    static var livingTitle: String { L10n.t("أحياء", "Living") }
    static var deceasedTitle: String { L10n.t("متوفون", "Deceased") }
    static var failed: String { L10n.t("تعذّر تحميل الأرقام", "Couldn't load the numbers") }
    static var opensList: String { L10n.t("يفتح القائمة", "Opens the list") }
    /// سطر «≈» تحت الحلقات (spec C.1)
    static var estimateNote: String {
        L10n.t("≈ نسبة الأحياء تقديرية: فيها كبار سن بلا تاريخ وفاة",
               "≈ The living share is an estimate: it includes elders with no death date")
    }

    /// «83٪» — نفس `DSGaugeText.percent` في وسط الحلقة
    static func percent(_ n: Int) -> String { L10n.t("\(n)٪", "\(n)%") }

    /// «2,991» أو «—» (لا صفر قبل الوصول)
    static func number(_ n: Int?) -> String {
        n.map { AdminNumberText.grouped($0) } ?? AdminStoreHealthText.placeholder
    }

    /// العدد والمعدود بالعربية (١ و٢ بلفظهما، ٣–١٠ جمع، ١١–٩٩ مفرد منصوب، والمئات مفرد) — الأرقام بفاصل الآلاف
    static func counted(_ n: Int, one: String, two: String, few: String, many: String, single: String) -> String {
        if n == 1 { return one }
        if n == 2 { return two }
        let digits = AdminNumberText.grouped(n)
        switch n % 100 {
        case 3...10:  return "\(digits) \(few)"
        case 11...99: return "\(digits) \(many)"
        default:      return "\(digits) \(single)"
        }
    }

    /// «2,489 حياً»
    static func living(_ n: Int) -> String {
        L10n.isArabic ? counted(n, one: "حيّ واحد", two: "حيّان", few: "أحياء", many: "حياً", single: "حيّ")
                      : "\(AdminNumberText.grouped(n)) living"
    }

    /// «87 متوفى»
    static func deceased(_ n: Int) -> String {
        L10n.isArabic ? counted(n, one: "متوفى واحد", two: "متوفيان", few: "متوفين", many: "متوفى", single: "متوفى")
                      : "\(AdminNumberText.grouped(n)) deceased"
    }

    /// «2,362 رجل» (نصّ المواصفة)
    static func men(_ n: Int) -> String {
        L10n.isArabic ? counted(n, one: "رجل واحد", two: "رجلان", few: "رجال", many: "رجل", single: "رجل")
                      : "\(AdminNumberText.grouped(n)) " + (n == 1 ? "man" : "men")
    }

    /// «127 امرأة»
    static func women(_ n: Int) -> String {
        L10n.isArabic ? counted(n, one: "امرأة واحدة", two: "امرأتان", few: "نساء", many: "امرأة", single: "امرأة")
                      : "\(AdminNumberText.grouped(n)) " + (n == 1 ? "woman" : "women")
    }

    /// تحت «في التطبيق»: «من 2,489 حياً»
    static func inAppSub(living: Int?) -> String? {
        living.map { L10n.t("من \(Self.living($0))", "of \(Self.living($0))") }
    }

    /// تحت «خارج العائلة»: «أحياء» — أرقام خارج العائلة للأحياء وحدهم (طلب المالك، F1: بلا «و87 متوفى»)
    static var outsideLivingSub: String { L10n.t("أحياء", "Living") }

    /// تحت «خارج العائلة»: «أحياء، و87 متوفى» — «أحياء» وحدها بلا متوفين أو قبل وصولهم
    @available(*, deprecated, message: "use outsideLivingSub (outside the family = living only, F1); U21 removes")
    static func outsideSub(deceased: Int?) -> String {
        guard let deceased, deceased > 0 else { return L10n.t("أحياء", "Living") }
        return L10n.t("أحياء، و\(Self.deceased(deceased))", "Living, and \(Self.deceased(deceased))")
    }

    /// تحت «أحياء»/«متوفون»: «2,362 رجل و127 امرأة»
    static func split(men: Int?, women: Int?) -> String? {
        guard let men, let women else { return nil }
        return L10n.t("\(Self.men(men)) و\(Self.women(women))", "\(Self.men(men)) and \(Self.women(women))")
    }

    /// جملة الحلقة للقارئ الصوتي (spec A.17): «الرجال: 2,729، 87 بالمئة أحياء. يفتح القائمة»
    static func ringSpoken(_ ring: AdminCensusRing, count: Int?, share: Int?, estimated: Bool, opens: Bool) -> String {
        let name = ringName(ring)
        guard let count else {
            return L10n.t("\(name): لم يصل العدد بعد", "\(name): not loaded yet")
        }
        var text = L10n.t("\(name): \(AdminNumberText.grouped(count))", "\(name): \(AdminNumberText.grouped(count))")
        if let share {
            text += estimated
                ? L10n.t("، نحو \(share) بالمئة أحياء (تقديري)", ", about \(share)% living (estimate)")
                : L10n.t("، \(share) بالمئة أحياء", ", \(share)% living")
        }
        return opens ? text + ". " + opensList : text
    }

    /// جملة السطر: «في التطبيق: 170، من 2,489 حياً. يفتح القائمة»
    static func rowSpoken(title: String, value: Int?, sub: String?, opens: Bool) -> String {
        guard let value else { return L10n.t("\(title): لم يصل العدد بعد", "\(title): not loaded yet") }
        var text = L10n.t("\(title): \(AdminNumberText.grouped(value))", "\(title): \(AdminNumberText.grouped(value))")
        if let sub { text += L10n.t("، \(sub)", ", \(sub)") }
        return opens ? text + ". " + opensList : text
    }

    /// سطر «≈» للقارئ الصوتي — بالعدد، وبلا الرمز «≈» (يُقرأ «يساوي تقريباً»)
    static func estimateSpoken(unverified: Int, opens: Bool) -> String {
        let text = L10n.t("نسبة الأحياء تقديرية: فيها \(AdminNumberText.grouped(unverified)) من كبار السن بلا تاريخ وفاة",
                          "The living share is an estimate: \(AdminNumberText.grouped(unverified)) elders have no death date")
        return opens
            ? text + L10n.t(". يفتح «هل ما زالوا أحياء؟»", ". Opens “Are they still alive?”")
            : text
    }
}

#if !ADMIN_LOGIC_TEST

// MARK: - ٤) من مخازن التطبيق (الواجهات المجمّدة تُقرأ فقط)

extension AdminCensusFigures {
    /// من أعداد «اليوم»/«الإحصاءات» بعد `setFamilyAccounts` (`AdminMemberCounts.seeded` يستدعيها)
    init(counts: AdminMemberCounts, outsideLiving: Int?, outsideDeceased: Int? = nil) {
        self.init(men: counts.men, menAlive: counts.menAlive, women: counts.women, womenAlive: counts.womenAlive,
                  menAccounts: counts.menAccounts, womenAccounts: counts.womenAccounts,
                  outsideLiving: outsideLiving, outsideDeceased: outsideDeceased, oldLiving: counts.oldLiving)
    }

    /// من `AdminFamilyCensus.make` (+ «المسجّلون» بتعريف العائلة `setFamilyAccounts` على نسخة من أعداده، ومتوفو «خارج العائلة»).
    /// `women` = صفوف شجرة النساء نفسها التي بُني منها `census` (عادةً `WomenStore.cache`)
    @MainActor
    static func make(census: AdminFamilyCensus, members: [FamilyMember], women: [FamilyMember]) -> AdminCensusFigures {
        var counts = census.counts
        counts.setFamilyAccounts(members: members)
        return AdminCensusFigures(counts: counts, outsideLiving: census.outsideTotal,
                                  outsideDeceased: outsideDeceased(members: members, women: women))
    }

    /// متوفو «خارج العائلة» بقاعدة `AdminFamilyCensus.make` نفسها للأحياء (أبناء البنات المسمَّون بلا حساب المراجعة + صفوف
    /// شجرة النساء المعلَّمة `is_outside_family` المسمّاة) — فـ«أحياء، و87 متوفى» و«متوفون من خارج العائلة» في «الإحصاءات» رقم
    /// واحد. nil قبل وصول شجرة النساء
    @MainActor
    static func outsideDeceased(members: [FamilyMember], women: [FamilyMember]) -> Int? {
        guard !women.isEmpty else { return nil }
        let outside = WomenStore.outsideFamilyIds
        let sons = DaughterSonsIndex.shared.ids
        let review = AppConfigValues.shared.reviewAccountIds
        let sonsDead = members.filter {
            sons.contains($0.id) && $0.hasName && !review.contains($0.id) && $0.isDeceased == true
        }.count
        let rowsDead = women.filter { outside.contains($0.id) && $0.hasName && $0.isDeceased == true }.count
        return sonsDead + rowsDead
    }
}

// MARK: - ٥) البطاقة

/// أفعال الضغط — nil = الرقم بلا سهم ولا ضغطة. الوجهة التي يجب أن يفتحها كلٌّ: `AdminCensusRoutes.destination` (جدول T2 أعلى الملف)
struct AdminCensusRingsActions {
    /// الإجمالي ← «الإحصاءات» على «العائلة» («اليوم»)؛ nil في «الإحصاءات» نفسها (بيته)
    var total: (() -> Void)? = nil
    /// الرجال ← «العائلة» بفلاتر ممسوحة
    var men: (() -> Void)? = nil
    /// النساء ← «نساء العائلة» (الحالة = الكل) للمالك والمدير، وشجرة النساء للمراقب
    var women: (() -> Void)? = nil
    /// «في التطبيق» ← «الإحصاءات» على «في التطبيق»
    var inApp: (() -> Void)? = nil
    /// «خارج العائلة» ← «الإحصاءات» على «خارج العائلة»
    var outside: (() -> Void)? = nil
    /// «≈ نسبة الأحياء تقديرية» ← «هل ما زالوا أحياء؟»
    var estimate: (() -> Void)? = nil
    /// «أعد المحاولة» حين فشل الجلب بلا بيانات
    var retry: (() -> Void)? = nil

    init(total: (() -> Void)? = nil, men: (() -> Void)? = nil, women: (() -> Void)? = nil,
         inApp: (() -> Void)? = nil, outside: (() -> Void)? = nil, estimate: (() -> Void)? = nil,
         retry: (() -> Void)? = nil) {
        self.total = total
        self.men = men
        self.women = women
        self.inApp = inApp
        self.outside = outside
        self.estimate = estimate
        self.retry = retry
    }

    func ring(_ ring: AdminCensusRing) -> (() -> Void)? {
        switch ring {
        case .total: return total
        case .men:   return men
        case .women: return women
        }
    }
}

/// السطران تحت الحلقات
enum AdminCensusRows: Hashable {
    /// «اليوم»: «في التطبيق» · «خارج العائلة»
    case appAndOutside
    /// «الإحصاءات»: «أحياء» · «متوفون» (بلا سهم — رجال ونساء مختلطون)
    case livingAndDeceased
    /// الحلقات وحدها
    case none
}

/// بطاقة «العائلة» — حلقات الإجمالي والرجال والنساء + سطران. جسمها `AnyView` (حارس المكدس)
struct AdminCensusRings: View {
    let figures: AdminCensusFigures
    var rows: AdminCensusRows = .appAndOutside
    /// حال مخزن الأرقام — nil = من القيم نفسها (nil = لم تصل)
    var health: AdminStoreHealth? = nil
    var actions = AdminCensusRingsActions()

    init(figures: AdminCensusFigures, rows: AdminCensusRows = .appAndOutside, health: AdminStoreHealth? = nil,
         actions: AdminCensusRingsActions = AdminCensusRingsActions()) {
        self.figures = figures
        self.rows = rows
        self.health = health
        self.actions = actions
    }

    var body: some View {
        AnyView(AdminCensusRingsCard(figures: figures, rows: rows, health: health, actions: actions))
    }
}

private struct AdminCensusRingsCard: View {
    let figures: AdminCensusFigures
    let rows: AdminCensusRows
    let health: AdminStoreHealth?
    let actions: AdminCensusRingsActions

    @ObservedObject private var verified = AdminLivingVerifiedStore.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dsLandscape) private var landscape

    var body: some View {
        switch health?.look {
        case .hidden?:
            EmptyView()
        case .unknown?:
            AdminPageStateCard(.error(AdminCensusText.failed,
                                      retry: health?.canRetry == true ? actions.retry : nil))
        case .staleWord(let since)?:
            card(staleSince: since)
        default:
            card(staleSince: nil)
        }
    }

    private func card(staleSince: Date?) -> some View {
        let unverified = figures.unverified(verified: verified.ids)
        return VStack(spacing: 0) {
            rings
            if unverified > 0 {
                estimateNote(unverified)
            }
            rowsSection
            if let staleSince {
                AdminStaleStamp(since: staleSince)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm)
            }
        }
        .padding(.horizontal, DS.Hub.cardPadding)
        .padding(.top, DS.Hub.cardPadding)
        // السطور تحمل حشوتها العمودية؛ الحلقات وحدها تحتاج حشوة البطاقة تحتها
        .padding(.bottom, rows == .none && staleSince == nil ? DS.Hub.cardPadding : 0)
        .frame(maxWidth: .infinity)
        // تظليل ضغط السطر الأخير يتبع زاويتي البطاقة
        .clipShape(RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous))
        .adminCard(padding: 0)
    }

    // MARK: الحلقات

    /// من أحجام إمكانية الوصول كل حلقة صفّ (spec A.17)
    private var stacked: Bool { typeSize.isAccessibilitySize }

    private var rings: AnyView {
        if stacked {
            return AnyView(VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(AdminCensusRing.allCases, id: \.self) { stackedRing($0) }
            })
        }
        // صفّ واحد؛ أفقياً بعرض عمود القراءة في الوسط (لا تتباعد الحلقات على عرض البطاقة كله)
        return AnyView(HStack(alignment: .top, spacing: DS.Spacing.sm) {
            ForEach(AdminCensusRing.allCases, id: \.self) { column($0) }
        }
        .frame(maxWidth: landscape ? DS.Landscape.maxContentWidth : .infinity)
        .frame(maxWidth: .infinity))
    }

    private func tint(_ ring: AdminCensusRing) -> Color {
        switch ring {
        case .total: return DS.Chart.total
        case .men:   return DS.Chart.men
        case .women: return DS.Chart.women
        }
    }

    private func track(_ ring: AdminCensusRing) -> Color {
        switch ring {
        case .total: return DS.Chart.inkTrack
        case .men:   return DS.Chart.menTrack
        case .women: return DS.Chart.womenTrack
        }
    }

    /// الحلقة: الأحياء بلون السلسلة فوق درجة أفتح منه، ونسبة الأحياء في الوسط تعدّ من الصفر («—» قبل الوصول)
    private func gauge(_ ring: AdminCensusRing, size: DS.Ring.Size) -> DSRingGauge {
        DSRingGauge(progress: figures.progress(ring), tint: tint(ring), size: size, track: track(ring),
                    center: size.value == nil ? .none : .percent(figures.livingShare(ring)))
    }

    private func spoken(_ ring: AdminCensusRing, opens: Bool) -> String {
        AdminCensusText.ringSpoken(ring, count: figures.count(ring), share: figures.livingShare(ring),
                                   estimated: figures.isEstimated(ring, verified: verified.ids), opens: opens)
    }

    /// عمود: الحلقة، ثم الاسم ١٣ رمادي، ثم العدد ١٧ شبه عريض وسهمه — العمود كله زرّ واحد (≥ ٤٤)
    private func column(_ ring: AdminCensusRing) -> some View {
        let action = actions.ring(ring)
        let opens = AdminCensusMath.opens(value: figures.count(ring), hasAction: action != nil)
        let face = VStack(spacing: DS.Spacing.xs) {
            gauge(ring, size: DS.Ring.censusCard)
            Text(AdminCensusText.ringName(ring))
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Spacing.xs) {
                Text(verbatim: AdminCensusText.number(figures.count(ring)))
                    .dsFont(.statValue)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if opens { DSChevron() }
            }
            .frame(minHeight: DS.Icon.tapTarget)
        }
        .padding(.top, DS.Spacing.xs)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        return tappable(face, action: opens ? action : nil, label: spoken(ring, opens: opens), style: .tile)
    }

    /// صفّ (أحجام إمكانية الوصول): حلقة صغيرة بلا رقم داخلها، بجانبها الاسم والعدد ونسبة الأحياء، والسهم في الطرف
    private func stackedRing(_ ring: AdminCensusRing) -> some View {
        let action = actions.ring(ring)
        let opens = AdminCensusMath.opens(value: figures.count(ring), hasAction: action != nil)
        let share = figures.livingShare(ring).map {
            L10n.t("\(AdminCensusText.percent($0)) أحياء", "\(AdminCensusText.percent($0)) living")
        }
        let face = HStack(spacing: DS.Spacing.md) {
            gauge(ring, size: DS.Ring.mediumStacked)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(AdminCensusText.ringName(ring))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textSecondary)
                Text(verbatim: AdminCensusText.number(figures.count(ring)))
                    .dsFont(.statValue)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textPrimary)
                if let share {
                    Text(verbatim: share)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Spacing.xs)
            if opens { DSChevron() }
        }
        .padding(.vertical, DS.Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
        return tappable(face, action: opens ? action : nil, label: spoken(ring, opens: opens), style: .row)
    }

    // MARK: «≈ نسبة الأحياء تقديرية»

    private func estimateNote(_ unverified: Int) -> AnyView {
        let opens = actions.estimate != nil
        let face = HStack(spacing: DS.Spacing.xs) {
            Text(AdminCensusText.estimateNote)
                .dsFont(.subtitle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if opens {
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .accessibilityHidden(true)
            }
        }
        // الذهبي الغامق على الأبيض (#725D31، ٦٫٣:١) — spec A.17
        .foregroundColor(DS.Color.accent)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
        .contentShape(Rectangle())
        return AnyView(tappable(face, action: actions.estimate,
                                label: AdminCensusText.estimateSpoken(unverified: unverified, opens: opens), style: .tile))
    }

    // MARK: السطران

    private var rowsSection: AnyView {
        switch rows {
        case .none:
            return AnyView(EmptyView())
        case .appAndOutside:
            return AnyView(VStack(spacing: 0) {
                AdminRowDivider()
                row(title: AdminCensusText.inAppTitle, sub: AdminCensusText.inAppSub(living: figures.totalAlive),
                    value: figures.inApp, action: actions.inApp)
                AdminRowDivider()
                row(title: AdminCensusText.outsideTitle, sub: AdminCensusText.outsideLivingSub,
                    value: figures.outsideLiving, action: actions.outside, swatch: true)
            })
        case .livingAndDeceased:
            return AnyView(VStack(spacing: 0) {
                AdminRowDivider()
                row(title: AdminCensusText.livingTitle,
                    sub: AdminCensusText.split(men: figures.menAlive, women: figures.womenAlive),
                    value: figures.totalAlive, action: nil)
                AdminRowDivider()
                row(title: AdminCensusText.deceasedTitle,
                    sub: AdminCensusText.split(men: figures.menDeceased, women: figures.womenDeceased),
                    value: figures.totalDeceased, action: nil)
            })
        }
    }

    /// سطر (spec A.6): [مربّع اللون][العنوان ١٥ / الوصف ١٣ رمادي] … [القيمة ١٥ شبه عريض][سهم إن فتح]
    private func row(title: String, sub: String?, value: Int?, action: (() -> Void)?, swatch: Bool = false) -> some View {
        let opens = AdminCensusMath.opens(value: value, hasAction: action != nil)
        let face = HStack(spacing: DS.Spacing.md) {
            if swatch { AdminCensusSwatch() }
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub {
                    Text(verbatim: sub)
                        .dsFont(.subtitle)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.Spacing.xs)
            Text(verbatim: AdminCensusText.number(value))
                .dsFont(.hubValue)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
            if opens { DSChevron() }
        }
        .padding(.vertical, DS.Spacing.xsm)
        .frame(minHeight: sub == nil ? DS.Hub.rowMinHeight : DS.Hub.rowMinHeightTwoLines)
        .contentShape(Rectangle())
        return tappable(face, action: opens ? action : nil,
                        label: AdminCensusText.rowSpoken(title: title, value: value, sub: sub, opens: opens), style: .row)
    }

    // MARK: الضغط

    private enum Press { case tile, row }

    /// زرّ بجملة واحدة للقارئ الصوتي، أو نصّ واحد بلا ضغطة. العمود يصغر ٠٫٩٧ (`DSPressStyle`) والسطر تظليل فقط
    /// (`AdminRowPressStyle`) — spec A.16
    @ViewBuilder
    private func tappable<Face: View>(_ face: Face, action: (() -> Void)?, label: String, style: Press) -> some View {
        if let action {
            switch style {
            case .tile:
                Button(action: action) { face }
                    .buttonStyle(DSPressStyle())
                    .accessibilityLabel(label)
            case .row:
                Button(action: action) { face }
                    .buttonStyle(AdminRowPressStyle())
                    .accessibilityLabel(label)
            }
        } else {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
        }
    }
}

/// مربّع لون «خارج العائلة» بجانب اسمه — مع «التمييز بدون لون» تظليل ٤٥° (spec A.11)
private struct AdminCensusSwatch: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var noColor

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Hub.chartBarRadius, style: .continuous)
        shape
            .fill(DS.Chart.outside)
            .overlay {
                if noColor {
                    Canvas { context, size in
                        // خطوط مائلة ٤٥° بلون سطح البطاقة — ثلاث في عرض المربّع
                        let step = size.width / 3
                        var path = Path()
                        var x = -size.height
                        while x < size.width {
                            path.move(to: CGPoint(x: x, y: size.height))
                            path.addLine(to: CGPoint(x: x + size.height, y: 0))
                            x += step
                        }
                        context.stroke(path, with: .color(DS.Color.cardBackground), lineWidth: DS.Border.width)
                    }
                    .clipShape(shape)
                }
            }
            .frame(width: DS.Hub.chartSwatch, height: DS.Hub.chartSwatch)
            .accessibilityHidden(true)
    }
}

// MARK: - المعاينة (أرقام اليوم ٢٠٢٦-١١-٢٦)

#if DEBUG
private enum AdminCensusPreviewData {
    /// الإجمالي 2,991 (رجال 2,729 · نساء 262)، الأحياء 2,489 (2,362 · 127)، في التطبيق 170 (123 · 47)، خارج العائلة 50 حياً و87
    /// متوفى، و41 من كبار السن لم يُراجَعوا («≈»)
    static let today = AdminCensusFigures(men: 2_729, menAlive: 2_362, women: 262, womenAlive: 127,
                                          menAccounts: 123, womenAccounts: 47,
                                          outsideLiving: 50, outsideDeceased: 87,
                                          oldLiving: Set((0..<41).map { _ in UUID() }))
    static let checked: AdminCensusFigures = {
        var f = today
        f.oldLiving = []
        return f
    }()
}

private struct AdminCensusRingsPreview: View {
    var figures = AdminCensusPreviewData.today
    var rows: AdminCensusRows = .appAndOutside
    var health: AdminStoreHealth? = nil
    var screen: AdminCensusScreen = .today

    var body: some View {
        let total: (() -> Void)? = screen == .today ? {} : nil
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            if screen == .today {
                AdminSectionLabel(title: L10n.t("العائلة", "Family"),
                                  link: AnyView(AdminCardLinkLabel(title: L10n.t("الإحصاءات", "Statistics"))))
            } else {
                AdminSectionLabel(title: L10n.t("العائلة", "Family"),
                                  trailing: L10n.t("الحلقة = نسبة الأحياء", "Ring = living share"))
            }
            AdminCensusRings(figures: figures, rows: rows, health: health,
                             actions: AdminCensusRingsActions(total: total, men: {}, women: {}, inApp: {},
                                                              outside: {}, estimate: {}, retry: {}))
        }
    }
}

/// صفحة المعاينة: أرضية اللوحة وهامشها، بالعربية من اليمين
private struct AdminCensusPreviewPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Hub.sectionGap) { content() }
                .padding(DS.Spacing.lg)
        }
        .background(DS.Hub.background)
        .dsSection(.admin)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
    }
}

#Preview("العائلة — اليوم والإحصاءات") {
    AdminCensusPreviewPage {
        AdminCensusRingsPreview()
        AdminCensusRingsPreview(figures: AdminCensusPreviewData.checked, rows: .livingAndDeceased, screen: .stats)
    }
}

#Preview("التحميل · الفشل · أرقام قديمة") {
    AdminCensusPreviewPage {
        AdminCensusRingsPreview(figures: AdminCensusFigures(), health: .loading)
        AdminCensusRingsPreview(figures: AdminCensusFigures(), health: .failed(lastGood: nil))
        AdminCensusRingsPreview(health: .failed(lastGood: Date().addingTimeInterval(-3_600)))
    }
}

#Preview("AX3 داكن") {
    AdminCensusPreviewPage {
        AdminCensusRingsPreview()
    }
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}
#endif

#endif
