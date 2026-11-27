import Foundation

// MARK: - قواعد بطاقة العضو في الشجرة «أ» (اعتمدها المالك ٢٠٢٦-١١-٢٧ — reports/app-review/member-card-tree)
//
// منطق خالص بلا SwiftUI — الواجهة في `MemberDetailsView` و`TreeMemberCardParts`:
//  • زرّ الأسفل حسب الدور (نقد م١): «الإدارة» لمن يعدّل الأعضاء (`canEditMembers`: المالك والمدير والمراقب) ولو على بطاقته،
//    «تعديل بياناتي» على بطاقتك، و«طلب تعديل» للعضو والمشرف.
//  • مربّعات «طلب تعديل» حسب من هو الشخص (م٣): أنت · ابنك · غيرك — وسطر صادق تحت كل مربّع (ح٣). لا رقم لغيرك (ح١)، ولا صورة
//    للمرأة (ح٢)، و«حذف من الشجرة» طريق الإخفاء الموجود (م٢). ما يحتاج ترحيلاً لا يظهر (الزوجة/الزوج لغيرك، الأم، «طلب آخر»
//    عن غيرك، بنت لرجل).
//  • زرّ القرابة: الكلمات داخل الزرّ، والقرابة البعيدة سطر ثانٍ «يلتقي معك في جدّكما …» (ت٤)؛ بلا عقدة لك «تظهر القرابة بعد
//    ربط حسابك» (ت٥)؛ بطاقتك بلا زرّ.
//  • سطر الحقائق «41 سنة · 3 أبناء»، والمتوفى بلا تاريخ «متوفى» فقط (ت٩).
//  • الخصوصية (م١٠): «طلبك عنه» = طلباتك أنت فقط، وقائمة كل الطلبات عنه لمن يقرّر طلبات الشجرة (`canModerateTree`).
// الفحص: tests/admin-redesign/T1/main.swift (الأمر في رأسه).

enum TreeMemberCardLogic {

    // MARK: زرّ الأسفل

    enum BottomButton: Equatable {
        case admin, requestEdit, editMine, none

        var title: String {
            switch self {
            case .admin: return L10n.t("الإدارة", "Manage")
            case .requestEdit: return L10n.t("طلب تعديل", "Request edit")
            case .editMine: return L10n.t("تعديل بياناتي", "Edit my details")
            case .none: return ""
            }
        }
    }

    static func bottomButton(isSelf: Bool, canEditMembers: Bool, isDeleted: Bool) -> BottomButton {
        if isDeleted { return .none }
        if canEditMembers { return .admin }
        return isSelf ? .editMine : .requestEdit
    }

    // MARK: من هو الشخص

    enum Person: Equatable { case me, myChild, other }

    static func person(isSelf: Bool, viewerId: UUID?, fatherId: UUID?) -> Person {
        if isSelf { return .me }
        if let viewerId, fatherId == viewerId { return .myChild }
        return .other
    }

    // MARK: مربّعات «طلب تعديل»

    /// السطر الصادق تحت اسم المربّع — النصّ يختلف لا اللون وحده
    enum Honesty: Equatable {
        case afterApproval, adminDoes, savedNow, firstThreeNow, withCode

        var text: String {
            switch self {
            case .afterApproval: return L10n.t("بعد موافقة الإدارة", "After admin approval")
            case .adminDoes: return L10n.t("تنفّذه الإدارة", "Done by the admins")
            case .savedNow: return L10n.t("يُحفظ فوراً", "Saved right away")
            case .firstThreeNow: return L10n.t("أول 3 تعديلات فوراً", "First 3 edits right away")
            case .withCode: return L10n.t("برمز تحقق", "With a verification code")
            }
        }
    }

    enum TileKind: String, Equatable {
        // أنت
        case myData, myPhone, addMyChild
        // ابنك
        case childData
        // غيرك (وابنك)
        case name, birth, death, deathDate, photo, addSon, remove

        var title: String {
            switch self {
            case .myData: return L10n.t("اسمي وميلادي وصورتي", "My name, birth & photo")
            case .myPhone: return L10n.t("رقمي", "My number")
            case .addMyChild: return L10n.t("إضافة ابن", "Add a son")
            case .childData: return L10n.t("بياناته في «عائلتي»", "His details in «My family»")
            case .name: return L10n.t("الاسم", "Name")
            case .birth: return L10n.t("الميلاد", "Birth")
            case .death: return L10n.t("الوفاة", "Death")
            case .deathDate: return L10n.t("تاريخ الوفاة", "Death date")
            case .photo: return L10n.t("الصورة", "Photo")
            case .addSon: return L10n.t("إضافة ابن", "Add a son")
            case .remove: return L10n.t("حذف من الشجرة", "Remove from the tree")
            }
        }

        var icon: String {
            switch self {
            case .myData: return "person"
            case .myPhone: return "phone"
            case .addMyChild, .addSon: return "person.badge.plus"
            case .childData: return "person"
            case .name: return "text.alignright"
            case .birth: return "calendar"
            case .death: return "moon"
            case .deathDate: return "calendar.badge.minus"
            case .photo: return "photo"
            case .remove: return "eye.slash"
            }
        }

        /// إجراء `tree_edit` الموجود (`TreeEditAction.rawValue`) — nil = مسار آخر موجود (ملفّك، رقمك، «عائلتي»)
        var editAction: String? {
            switch self {
            case .name: return "edit_name"
            case .birth: return "edit_birth"
            case .death: return "deceased"
            case .deathDate: return "add_death_date"
            case .photo: return "add_photo"
            case .addSon: return "add"
            case .remove: return "delete"
            case .myData, .myPhone, .addMyChild, .childData: return nil
            }
        }
    }

    struct Tile: Equatable {
        let kind: TileKind
        let honesty: Honesty
    }

    static func tiles(person: Person, isFemale: Bool, isDeceased: Bool) -> [Tile] {
        let deathKind: TileKind = isDeceased ? .deathDate : .death
        switch person {
        case .me:
            var out = [Tile(kind: .myData, honesty: .firstThreeNow), Tile(kind: .myPhone, honesty: .withCode)]
            // أبناء المرأة في شجرة النساء — لا إضافة من هنا
            if !isFemale { out.append(Tile(kind: .addMyChild, honesty: .afterApproval)) }
            return out
        case .myChild:
            return [Tile(kind: .childData, honesty: .savedNow), Tile(kind: deathKind, honesty: .afterApproval),
                    Tile(kind: .addSon, honesty: .afterApproval), Tile(kind: .remove, honesty: .afterApproval)]
        case .other:
            var kinds: [TileKind] = [.name, .birth, deathKind]
            // المرأة: لا صورة (قاعدة المالك)، وأبناؤها وإخفاؤها في شجرة النساء بقواعدها
            if !isFemale { kinds += [.photo, .addSon, .remove] }
            return kinds.map { Tile(kind: $0, honesty: .afterApproval) }
        }
    }

    /// المربّع الذي عليه طلب لك ينتظر يفتح طلبك نفسه بدل نموذج جديد (السيرفر لا يمنع التكرار — ت٢)
    static func hasPending(_ kind: TileKind, myActions: [String]) -> Bool {
        guard let action = kind.editAction else { return false }
        return myActions.contains(action)
    }

    static var pendingTileText: String { L10n.t("طلبك ينتظر", "Your request is waiting") }

    // MARK: القرابة

    enum Kinship: Equatable {
        case button(title: String, line: String?)
        case locked, mine, none
    }

    static var lockedKinshipText: String { L10n.t("تظهر القرابة بعد ربط حسابك", "Kinship shows once your account is linked") }
    static var mineText: String { L10n.t("هذه بطاقتك كما يراها أقاربك", "This is your card as your relatives see it") }

    /// `distA`/`distB` خطوات كلٍّ منكما إلى الجد المشترك (حدّ «البعيدة» نفسه في `KinshipCalculator`)
    static func kinship(isSelf: Bool, viewerHasNode: Bool, isDeleted: Bool, relationship: String, isBlood: Bool,
                        distA: Int, distB: Int, ancestorName: String?) -> Kinship {
        if isDeleted { return .none }
        if isSelf { return .mine }
        guard viewerHasNode else { return .locked }
        let distant = isBlood && (distA > 4 || distB > 3)
        let name = ancestorName?.trimmingCharacters(in: .whitespaces) ?? ""
        let line = distant && !name.isEmpty ? L10n.t("يلتقي معك في جدّكما \(name)", "You meet at your grandfather \(name)") : nil
        return .button(title: relationship, line: line)
    }

    // MARK: سطر الحقائق

    static func year(_ s: String?) -> Int? {
        guard let s, let r = s.range(of: "\\d{4}", options: .regularExpression) else { return nil }
        return Int(s[r])
    }

    /// العمر بالسنوات: الحيّ حتى هذه السنة، والمتوفى حتى سنة وفاته (بلا تاريخ وفاة = لا عمر)
    static func age(birth: String?, death: String?, deceased: Bool, nowYear: Int) -> Int? {
        guard let by = year(birth) else { return nil }
        guard let end = deceased ? year(death) : nowYear, end >= by, end - by < 130 else { return nil }
        return end - by
    }

    static func yearsText(_ n: Int) -> String {
        guard L10n.isArabic else { return "\(n) yrs" }
        switch n {
        case 1: return "سنة واحدة"
        case 2: return "سنتان"
        case 3...10: return "\(n) سنوات"
        default: return "\(n) سنة"
        }
    }

    static func sonsText(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "1 son" : "\(n) sons" }
        switch n {
        case 1: return "ابن واحد"
        case 2: return "ابنان"
        case 3...10: return "\(n) أبناء"
        default: return "\(n) ابناً"
        }
    }

    static func factsLine(age: Int?, deceased: Bool, female: Bool, sons: Int) -> String {
        var parts: [String] = []
        if deceased {
            let word = female ? L10n.t("متوفاة", "Deceased") : L10n.t("متوفى", "Deceased")
            parts.append(age.map { word + L10n.t(" عن ", " at ") + yearsText($0) } ?? word)
        } else if let age {
            parts.append(yearsText(age))
        }
        if sons > 0 { parts.append(sonsText(sons)) }
        return parts.joined(separator: " · ")
    }

    // MARK: ملخّصات المجموعات المطويّة

    static func familySummary(fatherName: String?, sons: Int) -> String? {
        var parts: [String] = []
        if let fatherName, !fatherName.isEmpty { parts.append(L10n.t("الأب ", "Father ") + fatherName) }
        if sons > 0 { parts.append(sonsText(sons)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func dataSummary(birth: String?, death: String?, deceased: Bool, female: Bool) -> String {
        var parts: [String] = []
        if let birth, !birth.isEmpty { parts.append(L10n.t("ميلاد ", "Born ") + birth) }
        if deceased {
            if let death, !death.isEmpty { parts.append(L10n.t("وفاة ", "Died ") + death) }
            else { parts.append(female ? L10n.t("متوفاة", "Deceased") : L10n.t("متوفى", "Deceased")) }
        }
        return parts.isEmpty ? L10n.t("الميلاد غير مسجّل", "Birth not recorded") : parts.joined(separator: " · ")
    }

    /// الرقم في الملخّص المطويّ: رمز الدولة فقط والباقي نقاط
    static func maskedPhone(_ display: String) -> String {
        let dots = "•••• ••••"
        let trimmed = display.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("+"), let space = trimmed.firstIndex(of: " ") else { return dots }
        return String(trimmed[..<space]) + " " + dots
    }

    static func contactSummary(female: Bool, masked: String) -> String {
        (female ? L10n.t("رقمها ", "Her number ") : L10n.t("رقمه ", "His number ")) + masked
    }

    // MARK: الخصوصية

    struct RequestRef: Equatable {
        let id: UUID
        let memberId: UUID
        let requesterId: UUID
        /// عقدة شجرة النساء في الطلب (بنته مثلاً) — تظهر في بطاقتها هي
        let womenNode: UUID?
    }

    /// «طلبك عنه»: طلباتك أنت عن هذا الشخص فقط (م١٠ — كان طلب واحد لك يُظهر كل الطلبات)
    static func mine(_ requests: [RequestRef], memberId: UUID, viewer: UUID?) -> [UUID] {
        guard let viewer else { return [] }
        return requests.filter {
            $0.requesterId == viewer && $0.memberId == memberId && ($0.womenNode == nil || $0.womenNode == memberId)
        }.map(\.id)
    }

    /// كل الطلبات عنه لمن يقرّر طلبات الشجرة فقط — لا المشرف ولا العضو
    static func showsAllRequests(canModerateTree: Bool) -> Bool { canModerateTree }

    static func myRequestTitle(female: Bool) -> String {
        female ? L10n.t("طلبك عنها", "Your request about her") : L10n.t("طلبك عنه", "Your request about him")
    }

    /// لا صور للإناث في التطبيق (قاعدة المالك ٢٠٢٦-١١-٢٤)
    static func showsPhoto(isFemale: Bool) -> Bool { !isFemale }
}
