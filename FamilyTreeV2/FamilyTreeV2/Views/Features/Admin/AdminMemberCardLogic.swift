import Foundation

// MARK: - منطق كرت العضو v3 «ب» البحت (الوحدة V3، اختيار المالك ٢٠٢٦-١١-٢٦: «مجموعات تنطوي»)
//
// Foundation فقط — يُفحص بلا محاكي (tests/admin-redesign/V3، مع `AdminMemberSheetLogic.swift`):
//   xcrun swiftc -o /private/tmp/claude-501/v3-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMemberSheetLogic.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMemberCardLogic.swift tests/admin-redesign/V3/main.swift \
//     && /private/tmp/claude-501/v3-logic
// ما هنا:
//   ١) «العضو» ثلاث مجموعات (البيانات · العائلة · الحساب): كل مجموعة مفتوحة أول مرة، والاختيار يُحفظ لكل مشاهد،
//      وما فيه طلب أو صفّ «تحت التعديل» لا ينطوي.
//   ٢) الطلب ← الصفّ الذي سيغيّره (شارة «طلب» تقفز إلى الطلب في «إجراءات الإدارة»)، ومن الطلبات «عنه».
//   ٣) قاعدة «مرحلة الموافقة»: الطلب داخل مسار الموافقات (أو المسار شغّال) = «فتح في الوارد» وحده.
//   ٤) كلمة «غير مسجّل» لكل قيمة غائبة، وسطور ملخّص المجموعات.
//   ٥) أزرار الرأس، و«الصلة بالعائلة» (كانت «النسب» — تسمية المالك ٢٠٢٦-١١-٢٦) وما يحفظه مربّعها.

nonisolated enum AdminMemberCardLogic {

    // MARK: ١) المجموعات

    enum Group: String, CaseIterable, Equatable {
        case data, family, account
    }

    /// صفوف «العضو» — كل صفّ في مجموعة واحدة
    enum Row: String, CaseIterable, Hashable {
        case name, birth, death, gender, photo, bio
        case father, mother, spouses, children, visibility, lineage
        case phone, app, lastSeen

        var group: Group {
            switch self {
            case .name, .birth, .death, .gender, .photo, .bio: return .data
            case .father, .mother, .spouses, .children, .visibility, .lineage: return .family
            case .phone, .app, .lastSeen: return .account
            }
        }
    }

    /// مفتاح UserDefaults لاختيار المشاهد (مفتوحة/مطويّة) لكل مجموعة
    static func storageKey(_ group: Group, viewer: UUID?) -> String {
        "admin.memberCard.open.\(group.rawValue).\(viewer?.uuidString.lowercased() ?? "anon")"
    }

    /// المجموعة لا تنطوي: فيها صفّ عليه طلب، أو صفّ «تحت التعديل» (حفظ جارٍ)
    static func locked(_ group: Group, requestRows: Set<Row>, pendingRows: Set<Row>) -> Bool {
        requestRows.contains { $0.group == group } || pendingRows.contains { $0.group == group }
    }

    static func canFold(_ group: Group, requestRows: Set<Row>, pendingRows: Set<Row>) -> Bool {
        !locked(group, requestRows: requestRows, pendingRows: pendingRows)
    }

    /// مفتوحة؟ — أول مرة (لا اختيار محفوظ) مفتوحة، والمقفولة مفتوحة دائماً
    static func isOpen(stored: Bool?, locked: Bool) -> Bool {
        locked || (stored ?? true)
    }

    // MARK: ٢) الطلب ← الصفّ

    /// ما يحتاجه الربط من الطلب: نوعه، وإجراء تعديل الشجرة، ونوع طلب شجرة النساء الحقيقي (`women.kind`)
    struct RequestKey: Equatable {
        let type: String
        let action: String?
        let womenKind: String?

        init(type: String, action: String?, womenKind: String?) {
            self.type = type
            self.action = action
            self.womenKind = womenKind
        }
    }

    /// الصفّ الذي سيغيّره الطلب — nil = يظهر في شريط «طلبات عنه» وحده (حذف، «طلب آخر»…)
    static func row(type: String, action: String?, womenKind: String?) -> Row? {
        switch type {
        case "tree_edit":
            // طلب شجرة النساء يُرسل بـ«add» ونوعه الحقيقي في `women.kind`
            switch womenKind {
            case "edit_name": return .name
            case "edit_birth": return .birth
            case "deceased": return .death
            case "delete": return nil
            case "wife", "husband": return .spouses
            case "mother": return .mother
            case "child", "son", "daughter": return .children
            default: break
            }
            switch action {
            case "edit_name": return .name
            case "edit_birth": return .birth
            case "deceased", "add_death_date": return .death
            case "add_photo": return .photo
            case "edit_phone": return .phone
            case "add": return .children
            default: return nil
            }
        case "photo_suggestion": return .photo
        case "deceased_report": return .death
        case "name_change", "family_change": return .name
        case "phone_change": return .phone
        case "child_add": return .children
        case "lineage_request": return .lineage
        default: return nil
        }
    }

    static func badgeRows(_ keys: [RequestKey]) -> Set<Row> {
        Set(keys.compactMap { row(type: $0.type, action: $0.action, womenKind: $0.womenKind) })
    }

    /// الطلب «عنه»؟ — `member_id` هو (ما لم يكن طلب شجرة نساء عن عقدة أخرى: بنته مثلاً)، أو `details.targetMemberId` هو
    /// (يُقارن كـ uuid — الآيفون يرسل حروفاً كبيرة والسيرفر صغيرة)، أو طلب شجرة النساء عن عقدته
    static func isAbout(personId: UUID, nodeId: UUID?, requestMemberId: UUID, targetMemberId: String?,
                        womenNodeId: UUID?) -> Bool {
        if let womenNodeId {
            return womenNodeId == personId || womenNodeId == nodeId
        }
        if requestMemberId == personId { return true }
        if let raw = targetMemberId, let target = UUID(uuidString: raw.trimmingCharacters(in: .whitespaces)) {
            return target == personId
        }
        return false
    }

    // MARK: ٣) أزرار الطلب في الشريط

    enum RequestAction: String, Equatable {
        case approve, reject, openInbox
    }

    /// داخل مسار الموافقات (مرحلة أو المسار شغّال) = «فتح في الوارد» وحده. غير ذلك: «موافقة»/«رفض» لمن يملكها
    /// (نفس فحوص «الوارد» — `canApproveFromBox`/`canRejectFromBox`) ثم «فتح في الوارد» دائماً
    static func requestActions(stage: String?, workflowOn: Bool, canApprove: Bool, canReject: Bool) -> [RequestAction] {
        let inStage = !(stage ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        guard !inStage, !workflowOn else { return [.openInbox] }
        var out: [RequestAction] = []
        if canApprove { out.append(.approve) }
        if canReject { out.append(.reject) }
        out.append(.openInbox)
        return out
    }

    // MARK: ٤) «غير مسجّل» وسطور الملخّص

    static func notRecorded(arabic: Bool = true) -> String { arabic ? "غير مسجّل" : "Not recorded" }

    /// القيمة كما هي، أو «غير مسجّل» — لا فراغ أبداً
    static func value(_ raw: String?, arabic: Bool = true) -> String {
        let v = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return v.isEmpty ? notRecorded(arabic: arabic) : v
    }

    /// جزء من سطر الملخّص: القيمة، أو «السيرة غير مسجّل»
    static func part(_ value: String?, label: String, arabic: Bool = true) -> String {
        let v = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return v.isEmpty ? "\(label) \(notRecorded(arabic: arabic))" : v
    }

    static func summary(_ parts: [String]) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// العدد بالعربية: ١ مفرد، ٢ مثنّى، ٣–١٠ جمع، ١١+ تمييز مفرد منصوب
    static func arabicCount(_ n: Int, one: String, two: String, few: String, many: String) -> String {
        switch n {
        case 1: return one
        case 2: return two
        case 3...10: return "\(n) \(few)"
        default: return "\(n) \(many)"
        }
    }

    /// «ابن وبنتان» · «5 أبناء وبنتان» — nil بلا أبناء
    static func childrenSummary(sons: Int, daughters: Int, arabic: Bool = true) -> String? {
        guard sons > 0 || daughters > 0 else { return nil }
        if !arabic {
            return [sons > 0 ? "\(sons) son\(sons == 1 ? "" : "s")" : nil,
                    daughters > 0 ? "\(daughters) daughter\(daughters == 1 ? "" : "s")" : nil]
                .compactMap { $0 }.joined(separator: " and ")
        }
        let s = sons > 0 ? arabicCount(sons, one: "ابن", two: "ابنان", few: "أبناء", many: "ابناً") : nil
        let d = daughters > 0 ? arabicCount(daughters, one: "بنت", two: "بنتان", few: "بنات", many: "بنتاً") : nil
        switch (s, d) {
        case let (s?, d?): return "\(s) و\(d)"
        case let (s?, nil): return s
        case let (nil, d?): return d
        default: return nil
        }
    }

    /// «زوجة» · «زوجتان» · «3 زوجات» للرجل، «زوج» للمرأة — nil بلا زوج
    static func spousesSummary(count: Int, female: Bool, arabic: Bool = true) -> String? {
        guard count > 0 else { return nil }
        if female { return arabic ? "زوج" : "Husband" }
        if !arabic { return count == 1 ? "Wife" : "\(count) wives" }
        return arabicCount(count, one: "زوجة", two: "زوجتان", few: "زوجات", many: "زوجة")
    }

    /// رقاقة القفز تحت الرأس: «طلبان عنه» — nil بلا طلبات
    static func requestsChip(count: Int, arabic: Bool = true) -> String? {
        guard count > 0 else { return nil }
        if !arabic { return count == 1 ? "1 request about them" : "\(count) requests about them" }
        return arabicCount(count, one: "طلب عنه", two: "طلبان عنه", few: "طلبات عنه", many: "طلباً عنه")
    }

    // MARK: ٥) أزرار الرأس

    /// «الملف الكامل» لمن يعدّل وله ملف (عقدة شجرة النساء بلا ملف: لا محرّر كامل) · «في الشجرة» لمن يصل إليه الرأس الأول
    /// وليست الورقة فوق مربّع آخر · «اتصال»/«واتساب» للحيّ برقم ظاهر لهذا المشاهد
    static func headerActions(canEdit: Bool, isProfile: Bool, reachable: Bool, inBox: Bool, isDeceased: Bool,
                              visiblePhone: String?) -> [AdminMemberSheetLogic.HeaderAction] {
        AdminMemberSheetLogic.headerActions(canEdit: canEdit && isProfile, inTree: isProfile && reachable && !inBox,
                                            isDeceased: isDeceased, visiblePhone: isProfile ? visiblePhone : nil)
    }

    // MARK: «الصلة بالعائلة»

    enum Lineage: String, CaseIterable, Equatable {
        /// «من العائلة» — أبوه في الشجرة
        case family
        /// «ابن بنت» — أبوه من خارج العائلة وأمّه بنت من العائلة
        case daughterSon
        /// «زوج من خارج العائلة»
        case outsideHusband
        /// «زوجة من خارج العائلة»
        case outsideWife
    }

    /// الصلة كما يقولها السيرفر: ابن البنت (`daughter_son_lineage`) ثم علامة «من خارج العائلة» (`is_outside_family`) ثم
    /// أب في الشجرة — nil = لا شيء معروف (الصفّ «غير مسجّل»)
    static func lineage(isDaughterSon: Bool, outsideFlag: Bool, isFemale: Bool, hasFamilyFather: Bool) -> Lineage? {
        if isDaughterSon { return .daughterSon }
        if outsideFlag { return isFemale ? .outsideWife : .outsideHusband }
        if hasFamilyFather { return .family }
        return nil
    }

    /// ما يفعله «حفظ» في مربّع «صلته بالعائلة» — بنداءات السيرفر الموجودة فقط
    enum LineageSave: String, Equatable {
        /// الاختيار هو الحالي — لا شيء يُحفظ
        case current
        /// «من العائلة» لمن لا صلة له بعد: ربط الأب (`LinkFatherSheet` ← `updateMemberFather`)
        case linkFather
        /// طلب «الصلة بالعائلة» معلّق: قرار الإدارة (`decide_lineage_request`)
        case decideRequest
        /// طلب انضمام معلّق لرجل: «ابن بنت من خارج العائلة» (`approve_join_as_daughter_son`)
        case approveJoin
        /// لا نداء على السيرفر لهذا التغيير — الزرّ معطّل بملاحظة «يحتاج تحديث السيرفر»
        case needsServer
    }

    static func lineageSave(choice: Lineage, current: Lineage?, isProfile: Bool, hasPendingLineageRequest: Bool,
                            isPendingJoin: Bool, isMale: Bool) -> LineageSave {
        if choice == current { return .current }
        switch choice {
        case .family:
            return isProfile && current == nil ? .linkFather : .needsServer
        case .daughterSon:
            if hasPendingLineageRequest { return .decideRequest }
            if isPendingJoin && isMale && isProfile && current == nil { return .approveJoin }
            return .needsServer
        case .outsideHusband, .outsideWife:
            return .needsServer
        }
    }

    // MARK: «الأبناء والبنات» — قائمة واحدة، والحفظ لكل جدول بترتيبه

    /// الأبناء (`profiles.sort_order`) والبنات (`women_members.sort_order`) في جدولين: بعد السحب يبقى ترتيب كلٍّ منهما
    /// النسبي كما رتّبته الإدارة، ويُحفظ كلٌّ بنداء جدوله
    static func partitionChildren<T>(_ ordered: [T], isSon: (T) -> Bool) -> (sons: [T], daughters: [T]) {
        var sons: [T] = []
        var daughters: [T] = []
        for item in ordered {
            if isSon(item) { sons.append(item) } else { daughters.append(item) }
        }
        return (sons, daughters)
    }
}
