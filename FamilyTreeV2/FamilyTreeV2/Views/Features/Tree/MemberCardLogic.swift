import Foundation

// MARK: - بطاقة العضو القديمة بشكل «AB» (اختيار المالك ٢٠٢٦-١١-٢٧ «بين ا و ب») — قواعد المحتوى العشرة
//
// منطق خالص بلا SwiftUI، تقرؤه `MemberDetailsView` (شجرة العائلة) و`WomanDetailSheet` (شجرة النساء) والشكل في
// `MemberCardAB.swift`. البنية كما هي (المربّع بالمنتصف، ترتيب الأقسام، الأزرار) — هذا الملف يقول ماذا يظهر فقط:
//  ١) خانات «طلب تعديل»: لا «تعديل رقم» على بطاقة غيرك، ولا «إضافة صورة» لأنثى.
//  ٢) سطر صادق تحت كل خانة: «يُطبَّق عند الموافقة» أو «تنفّذه الإدارة بيدها».
//  ٣) الحذف بكلامه: في شجرة العائلة «حذف من الشجرة» و«يُخفى ويبقى في السجل»، وفي شجرة النساء «يُحذف بموافقة المالك أو المدير».
//  ٤) بنت عمرها المسجّل أقل من 13: بلا «الزوج» و«أبناء» (بلا تاريخ ميلاد يبقيان).
//  ٥) طلبك من نفس النوع قيد المراجعة: الخانة «طلبك قيد المراجعة» وتفتحه بدل طلب جديد.
//  ٦) رسالة الإرسال بلا وعد «قريباً».
//  ٧) «طلبك عنه»: العضو والمشرف يرون طلباتهم هم فقط؛ القائمة كاملة لمن يقرّر طلبات الشجرة.
//  ٨) رقم المرأة: العضو لا يرى صفّاً ولا كلمة «مخفي»؛ الإدارة الأربعة وهي نفسها يرونه وتحته «مخفي عن الأعضاء».
//  ٩) العمر بعربي صحيح: «5 سنوات».
// الفحص: tests/admin-redesign/L1/main.swift (الأمر في رأسه).

nonisolated enum MemberCardLogic {

    // MARK: العمر (البند ٩)

    static func year(_ s: String?) -> Int? {
        guard let s, let r = s.range(of: "\\d{4}", options: .regularExpression) else { return nil }
        return Int(s[r])
    }

    /// الحيّ حتى هذه السنة، والمتوفى حتى سنة وفاته (بلا سنة وفاة = لا عمر) — نفس حبّة العمر القديمة
    static func age(birth: String?, death: String?, deceased: Bool, nowYear: Int) -> Int? {
        guard let by = year(birth) else { return nil }
        guard let end = deceased ? year(death) : nowYear, end >= by, end - by < 130 else { return nil }
        return end - by
    }

    /// «سنة واحدة» · «سنتان» · «5 سنوات» (3–10) · «11 سنة» — الأرقام لاتينية كبقية التطبيق
    static func yearsText(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "1 yr" : "\(n) yrs" }
        switch n {
        case 0: return "أقل من سنة"
        case 1: return "سنة واحدة"
        case 2: return "سنتان"
        case 3...10: return "\(n) سنوات"
        default: return "\(n) سنة"
        }
    }

    /// بنت عمرها المسجّل أقل من 13 (البند ٤) — بلا تاريخ ميلاد = لا
    static func isYoungGirl(isFemale: Bool, age: Int?) -> Bool {
        guard isFemale, let age else { return false }
        return age < 13
    }

    // MARK: السطر الصادق (البندان ٢ و٣)

    enum Honesty: Equatable {
        /// يُطبَّق وحده عند القبول
        case afterApproval
        /// تنفّذه الإدارة بيدها ثم تقبله
        case adminDoes
        /// حذف شجرة العائلة = إخفاء
        case hidesKeepsRecord
        /// حذف شجرة النساء = حذف فعلي للمالك والمدير
        case deletesOwnerAdmin

        var text: String {
            switch self {
            case .afterApproval: return L10n.t("يُطبَّق عند الموافقة", "Applied once approved")
            case .adminDoes: return L10n.t("تنفّذه الإدارة بيدها", "The admins do it by hand")
            case .hidesKeepsRecord: return L10n.t("يُخفى ويبقى في السجل", "Hidden, kept in the record")
            case .deletesOwnerAdmin: return L10n.t("يُحذف بموافقة المالك أو المدير", "Deleted once the owner or an admin approves")
            }
        }

        /// الحذف بلون التحذير على الخانة
        var isWarning: Bool { self == .hidesKeepsRecord || self == .deletesOwnerAdmin }
    }

    // MARK: خانات «طلب تعديل» في شجرة العائلة (البنود ١ و٢ و٣)

    /// إجراءات `tree_edit` نفسها (`TreeEditAction.rawValue`) — بالترتيب القديم: «ابن» أولاً
    static func familyKinds(isFemale: Bool, isDeceased: Bool) -> [String] {
        var kinds = ["add", "edit_name", "edit_birth"]
        if isDeceased {
            kinds.append("add_death_date")
            if !isFemale { kinds.append("add_photo") }
        } else {
            if !isFemale { kinds.append("add_photo") }
            kinds.append("deceased")
        }
        kinds.append("delete")
        // لا «edit_phone» أبداً هنا: الخانات على بطاقة غيرك، ورقمك أنت من «حسابي ← تغيير الرقم»
        return kinds
    }

    /// كل طلبات شجرة العائلة تُطبَّق عند القبول (`decide_admin_request`)، والحذف إخفاء
    static func familyHonesty(_ kind: String) -> Honesty {
        kind == "delete" ? .hidesKeepsRecord : .afterApproval
    }

    /// السطر الذهبي تحت شبكة شجرة العائلة: لماذا لا «تعديل رقم» ولا «إضافة صورة»
    static func familyGridNote(isFemale: Bool) -> String {
        let phone = L10n.t("لا «تعديل رقم» لغيرك. رقمك أنت من «حسابي ← تغيير الرقم».",
                           "No «Edit phone» for others. Change your own number from «Profile → Change number».")
        let photo = isFemale
            ? L10n.t(" لا صور للنساء في التطبيق.", " Women have no photos in the app.")
            : L10n.t(" و«إضافة صورة» للرجال فقط.", " «Add photo» is for men only.")
        return phone + photo
    }

    // MARK: خانات «طلب تعديل» في شجرة النساء (البنود ٢ و٣ و٤)

    /// معرّفات خانات `WomanDetailSheet.requestActions` بترتيبها — «أبناء» و«الزوج» لا يظهران لبنت أقل من 13
    static func womenRequestIds(isFemale: Bool, hasHusband: Bool, hasMother: Bool, isFatherNode: Bool,
                                isDeceased: Bool, age: Int?) -> [String] {
        let young = isYoungGirl(isFemale: isFemale, age: age)
        var ids: [String] = []
        if !young { ids.append("child") }
        if !isFemale { ids.append("wife") } else if !hasHusband && !young { ids.append("husband") }
        if !hasMother { ids.append("addMother") }
        if isFatherNode { ids.append("sister") }
        ids += ["req.editName", "req.editBirth"]
        if !isDeceased { ids.append("req.deceased") }
        ids += ["req.other", "req.delete"]
        return ids
    }

    /// أين تُطبَّق صورة زوج البنت من خارج العائلة: ملف حسابه، أو عقدته في شجرة النساء حين لا حساب له
    struct PhotoTarget: Equatable {
        let id: UUID
        /// true = عقدة في `women_members` بلا ملف (`tree_edit add_photo` بـ member_id = مقدّم الطلب، 20261127260000)
        let womenNode: Bool
    }

    /// «إضافة صورة» لزوج البنت من خارج العائلة (بند ١٥، المالك ٢٠٢٦-١١-٢٧ «خله عن طريق زوجته أو ابنه المضاف مع طلب أو
    /// هو بنفسه» — بلا زرّ للإدارة): للذكر من خارج العائلة، لزوجته أو ابنه وحدهما. له حساب → الصورة على ملفه
    /// (`profiles.avatar_url`، وهو نفسه يضيفها من «حسابي»)؛ بلا حساب → على عقدته في شجرة النساء (موافقة المالك
    /// ٢٠٢٦-١١-٢٧، `women_members.avatar_url`). النساء بلا صور.
    static func outsideHusbandPhotoTarget(nodeId: UUID, nodeIsMale: Bool, nodeIsOutside: Bool, linkedProfile: UUID?,
                                          viewer: UUID?, viewerIsWife: Bool, viewerIsSon: Bool) -> PhotoTarget? {
        guard nodeIsMale, nodeIsOutside, let viewer, viewer != linkedProfile, viewer != nodeId,
              viewerIsWife || viewerIsSon else { return nil }
        if let linkedProfile { return PhotoTarget(id: linkedProfile, womenNode: false) }
        return PhotoTarget(id: nodeId, womenNode: true)
    }

    /// ما يُنفَّذ وحده عند القبول (`private.apply_women_request`) وما تنفّذه الإدارة بيدها:
    /// الابنة والأخت تلقائياً (ابن امرأة بلا زوج مسجّل يدوي)، الأم من زوجات الأب تلقائياً وأم جديدة يدوي،
    /// الزوج والزوجة و«طلب آخر» يدوي (البنود «لاحقاً» في المقترح)
    static func womenHonesty(_ id: String, isFemale: Bool, hasHusband: Bool, hasFatherWives: Bool) -> Honesty {
        switch id {
        case "child": return isFemale && !hasHusband ? .adminDoes : .afterApproval
        case "sister", "req.editName", "req.editBirth", "req.deceased", "req.addPhoto": return .afterApproval
        case "addMother": return hasFatherWives ? .afterApproval : .adminDoes
        case "req.delete": return .deletesOwnerAdmin
        default: return .adminDoes
        }
    }

    /// السطر الذهبي تحت شبكة شجرة النساء — لبنت أقل من 13 فقط
    static func womenGridNote(isFemale: Bool, age: Int?) -> String? {
        guard isYoungGirl(isFemale: isFemale, age: age), let age else { return nil }
        return L10n.t("«أبناء» و«الزوج» لا يظهران: عمرها المسجّل \(yearsText(age))، أقل من 13.",
                      "«Children» and «Husband» are hidden: her recorded age is \(yearsText(age)), under 13.")
    }

    // MARK: الطلبات (البندان ٥ و٧)

    struct RequestRef: Equatable {
        let id: UUID
        let memberId: UUID?
        let requesterId: UUID?
        /// عقدة شجرة النساء في الطلب — nil لطلبات شجرة العائلة
        let womenNode: UUID?
        /// الإجراء (`tree_edit.action`) أو نوع شجرة النساء (`women.kind`)
        let kind: String
    }

    /// «طلبك عنه» في شجرة العائلة: طلباتك أنت عنه وحده (طلب شجرة النساء عن بنته يظهر في بطاقتها)
    static func mineInFamily(_ refs: [RequestRef], memberId: UUID, viewer: UUID?) -> [RequestRef] {
        guard let viewer else { return [] }
        return refs.filter {
            $0.requesterId == viewer && $0.memberId == memberId && ($0.womenNode == nil || $0.womenNode == memberId)
        }
    }

    /// «طلبك عنها» في شجرة النساء: طلباتك أنت المعلّقة على عقدتها
    static func mineInWomen(_ refs: [RequestRef], nodeId: UUID, viewer: UUID?) -> [RequestRef] {
        guard let viewer else { return [] }
        return refs.filter { $0.requesterId == viewer && $0.womenNode == nodeId }
    }

    /// نوع الطلب الذي تفتحه خانة شجرة النساء (`women.kind`) — nil = لا يُعرف (يدوي بلا بيانات)
    static func womenPendingKind(_ id: String) -> String? {
        switch id {
        case "child": return "child"
        case "sister": return "sister"
        case "addMother": return "set_mother"
        case "req.editName": return "edit_name"
        case "req.editBirth": return "edit_birth"
        case "req.deceased": return "deceased"
        case "req.delete": return "delete"
        default: return nil
        }
    }

    /// طلبك المعلّق من نوع الخانة — الخانة تفتحه بدل نموذج جديد (السيرفر يقبل التكرار)
    static func pending(kind: String?, in mine: [RequestRef]) -> RequestRef? {
        guard let kind else { return nil }
        return mine.first { $0.kind == kind }
    }

    static var pendingTileText: String { L10n.t("طلبك قيد المراجعة · افتحه", "Your request is under review · open") }

    enum RequestsSection: Equatable {
        /// القائمة كاملة (المالك والمدير والمراقب) — كل صفّ يفتح «الوارد»
        case all
        /// «طلبك عنه» — طلباتك أنت فقط مع «تابِعه»
        case mine
        case none
    }

    /// البند ٧: من يقرّر طلبات الشجرة يرى الكل؛ العضو والمشرف طلباتهم فقط
    static func requestsSection(canModerateTree: Bool, allCount: Int, mineCount: Int) -> RequestsSection {
        if canModerateTree { return allCount > 0 ? .all : .none }
        return mineCount > 0 ? .mine : .none
    }

    static func myRequestTitle(female: Bool) -> String {
        female ? L10n.t("طلبك عنها", "Your request about her") : L10n.t("طلبك عنه", "Your request about him")
    }

    static var followHint: String {
        L10n.t("تتابعه أو تسحبه من الإشعارات ← الطلبات المرسلة.",
               "Follow or withdraw it from Notifications → Sent requests.")
    }

    // MARK: رسالة الإرسال (البند ٦)

    static func sentMessage(manual: Bool = false) -> String {
        manual
            ? L10n.t("وصل طلبك للإدارة، وتنفّذه بيدها عند موافقتهم. تتابعه أو تسحبه من الإشعارات ← الطلبات المرسلة.",
                     "Your request reached the admins; they carry it out by hand once approved. Follow or withdraw it from Notifications → Sent requests.")
            : L10n.t("وصل طلبك للإدارة، ويُطبَّق عند موافقتهم. تتابعه أو تسحبه من الإشعارات ← الطلبات المرسلة.",
                     "Your request reached the admins and is applied once they approve. Follow or withdraw it from Notifications → Sent requests.")
    }

    // MARK: الرقم (البند ٨)

    enum PhoneRow: Equatable {
        /// لا صفّ أبداً
        case none
        /// الرقم ظاهر؛ `hiddenCaption` = قفل صغير و«مخفي عن الأعضاء» تحته
        case shown(hiddenCaption: Bool)
        /// كلمة «مخفي» (رجل أخفى رقمه، كما كان)
        case hiddenWord
    }

    /// `viewerIsStaff` = الإدارة الأربعة (`canModerate`: المالك والمدير والمراقب والمشرف)
    static func phoneRow(hasPhone: Bool, isFemale: Bool, isPhoneHidden: Bool, isDeceased: Bool,
                         viewerIsSelf: Bool, viewerIsStaff: Bool) -> PhoneRow {
        if isDeceased { return .none }
        let hidden = isFemale || isPhoneHidden
        let maySee = !hidden || viewerIsSelf || viewerIsStaff
        if hasPhone && maySee {
            return .shown(hiddenCaption: isFemale)
        }
        // المرأة: لا صفّ ولا «مخفي» للعضو؛ الرجل المخفي: «مخفي» كما كان
        return !isFemale && isPhoneHidden && !viewerIsSelf && !viewerIsStaff ? .hiddenWord : .none
    }
}
