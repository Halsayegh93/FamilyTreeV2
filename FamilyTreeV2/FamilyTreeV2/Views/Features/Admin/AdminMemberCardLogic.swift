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
//   ٦) نقد «المنتقد» على v3: قفل أوامر العائلة على ورقتك (ح٢)، موانع نقل الجنس ومنها الحساب (ح١)، «فك الربط» للابن (ح٣)،
//      الأنواع التي يقرّرها الشريط (`boxDecidableTypes`)، التأنيث («غير مسجّلة»، «عنها»)، منتقي الزوج بلا محارمها (م٥)،
//      والمعرّف الجديد بعد النقل (م٦).

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

    /// الأنواع التي يقبلها/يرفضها الشريط ومربّع الإشعار بدوالها الموجودة (`approveFromPush` + دالة الرفض لكل نوع) —
    /// المصدر الواحد (`AdminRequestViewModel.boxAllowed` يقرأ منه). غيرها («تغيير الرقم»، «الصلة بالعائلة»، الانضمام…)
    /// «فتح في الوارد» وحده
    static let boxDecidableTypes: Set<String> = [
        "tree_edit", "deceased_report", "name_change", "photo_suggestion", "news_report",
    ]

    /// داخل مسار الموافقات (مرحلة أو المسار شغّال) أو نوع لا يقرّره الشريط = «فتح في الوارد» وحده. غير ذلك:
    /// «موافقة»/«رفض» لمن يملكها (نفس فحوص «الوارد» — `canApproveFromBox`/`canRejectFromBox`) ثم «فتح في الوارد» دائماً
    static func requestActions(type: String, stage: String?, workflowOn: Bool, canApprove: Bool,
                               canReject: Bool) -> [RequestAction] {
        let inStage = !(stage ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        guard !inStage, !workflowOn, boxDecidableTypes.contains(type) else { return [.openInbox] }
        var out: [RequestAction] = []
        if canApprove { out.append(.approve) }
        if canReject { out.append(.reject) }
        out.append(.openInbox)
        return out
    }

    /// م١: «طلبات عنه» (الشريط، الرقاقة، شارات «طلب») لمن يقرّر طلبات الشجرة، ولا على ورقتك — طلباتك يعالجها غيرك
    /// (`boxAllowed`)، وبطاقة «إجراءات الإدارة» لا تُرسم على ورقتك فلا مرساة تقفز إليها
    static func showsRequests(isSelf: Bool, seesRequests: Bool) -> Bool {
        seesRequests && !isSelf
    }

    // MARK: ٤) «غير مسجّل» وسطور الملخّص

    /// «غير مسجّل»، و«غير مسجّلة» بعد كلمة مؤنثة (الأم، الزوجة، الصورة، السيرة، الوفاة، الصلة بالعائلة)
    static func notRecorded(arabic: Bool = true, feminine: Bool = false) -> String {
        arabic ? (feminine ? "غير مسجّلة" : "غير مسجّل") : "Not recorded"
    }

    /// القيمة كما هي، أو «غير مسجّل/ة» — لا فراغ أبداً
    static func value(_ raw: String?, arabic: Bool = true, feminine: Bool = false) -> String {
        let v = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return v.isEmpty ? notRecorded(arabic: arabic, feminine: feminine) : v
    }

    /// جزء من سطر الملخّص: القيمة، أو «السيرة غير مسجّلة»
    static func part(_ value: String?, label: String, arabic: Bool = true, feminine: Bool = false) -> String {
        let v = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return v.isEmpty ? "\(label) \(notRecorded(arabic: arabic, feminine: feminine))" : v
    }

    /// «عنه» / «عنها» — الكرت يُفتح للنساء أيضاً
    static func aboutWord(female: Bool, arabic: Bool = true) -> String {
        arabic ? (female ? "عنها" : "عنه") : "about them"
    }

    /// عنوان الشريط: «طلبات عنها» · «طلبات عنه · 3»
    static func requestsTitle(count: Int, female: Bool, arabic: Bool = true) -> String {
        let base = arabic ? "طلبات \(aboutWord(female: female))" : "Requests about them"
        return count > 0 ? "\(base) · \(count)" : base
    }

    /// الشريط بلا طلبات: «لا طلبات عنها الآن.»
    static func noRequests(female: Bool, arabic: Bool = true) -> String {
        arabic ? "لا طلبات \(aboutWord(female: female)) الآن." : "No requests about them now."
    }

    /// عنوان مربّع الصلة وصفّها في مربّعه: «صلته بالعائلة» / «صلتها بالعائلة»
    static func lineageTitle(female: Bool, arabic: Bool = true) -> String {
        arabic ? (female ? "صلتها بالعائلة" : "صلته بالعائلة") : "Relation to the family"
    }

    /// صفّ «الأبناء والبنات» وملخّص «العائلة» بكلمة واحدة: العدد، أو «لا أبناء مسجّلون»
    static func childrenValue(sons: Int, daughters: Int, arabic: Bool = true) -> String {
        childrenSummary(sons: sons, daughters: daughters, arabic: arabic)
            ?? (arabic ? "لا أبناء مسجّلون" : "No children recorded")
    }

    /// صفّ «الصورة»: «موجودة» · «بلا صورة» · «لا توجد صورة لهذا العضو» (`avatar_unavailable` — لا تُطلب)
    static func photoValue(hasPhoto: Bool, unavailable: Bool, arabic: Bool = true) -> String {
        if hasPhoto { return arabic ? "موجودة" : "Added" }
        if unavailable { return arabic ? "لا توجد صورة لهذا العضو" : "No photo exists" }
        return arabic ? "بلا صورة" : "No photo"
    }

    /// كلمة «بلا حساب» الواحدة في الكرت — هي كلمة الرأس (`AdminMemberStatus.treeOnly`)
    static func noAccountWord(arabic: Bool = true) -> String { arabic ? "بدون حساب" : "No account" }

    /// «آخر دخول»: التاريخ، أو «لم يسجّل الدخول بعد» لمن لا حساب له (لا «غير مسجّل» — لم يدخل أبداً)
    static func lastSeen(_ date: String?, hasAccount: Bool, female: Bool, arabic: Bool = true) -> String {
        if let date = date?.trimmingCharacters(in: .whitespaces), !date.isEmpty { return date }
        guard hasAccount else {
            return arabic ? (female ? "لم تسجّل الدخول بعد" : "لم يسجّل الدخول بعد") : "Not signed in yet"
        }
        return arabic ? "غير معروف" : "Unknown"
    }

    /// ملخّص «الحساب»: كلمة الحال (كالرأس) ثم آخر دخول — «بدون حساب · لم يسجّل الدخول بعد» · «مسجّل · آخر دخول 2/11/2026»
    static func accountSummary(statusWord: String, lastSeen date: String?, hasAccount: Bool, female: Bool,
                               arabic: Bool = true) -> String {
        let seen: String
        if let date = date?.trimmingCharacters(in: .whitespaces), !date.isEmpty {
            seen = arabic ? "آخر دخول \(date)" : "Last seen \(date)"
        } else {
            seen = lastSeen(nil, hasAccount: hasAccount, female: female, arabic: arabic)
        }
        return summary([statusWord, seen])
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

    /// رقاقة القفز تحت الرأس: «طلبان عنه» / «طلبان عنها» — nil بلا طلبات
    static func requestsChip(count: Int, female: Bool = false, arabic: Bool = true) -> String? {
        guard count > 0 else { return nil }
        if !arabic { return count == 1 ? "1 request about them" : "\(count) requests about them" }
        let about = aboutWord(female: female)
        return arabicCount(count, one: "طلب \(about)", two: "طلبان \(about)", few: "طلبات \(about)", many: "طلباً \(about)")
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

    /// ت٥: خيارات المربّع لجنسه — «ابن بنت» و«زوج من خارج العائلة» للرجل، و«زوجة من خارج العائلة» للمرأة
    static func lineageOptions(female: Bool) -> [Lineage] {
        female ? [.family, .outsideWife] : [.family, .daughterSon, .outsideHusband]
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
        /// م٣: الطلب (أو الانضمام) داخل مسار الموافقات — القرار في «الوارد» بمراحله، والزرّ «فتح في الوارد»
        case openInbox
        /// ت٥: «من خارج العائلة» يحسبه السيرفر من الروابط (`trg_women_outside_flag`) — لا يُكتب باليد، والزرّ معطّل بشرحه
        case automatic
        /// لا نداء على السيرفر لهذا التغيير — الزرّ معطّل بملاحظة «يحتاج تحديث السيرفر»
        case needsServer
    }

    static func lineageSave(choice: Lineage, current: Lineage?, isProfile: Bool, hasPendingLineageRequest: Bool,
                            requestInWorkflow: Bool = false, isPendingJoin: Bool, joinInWorkflow: Bool = false,
                            isMale: Bool) -> LineageSave {
        if choice == current { return .current }
        switch choice {
        case .family:
            return isProfile && current == nil ? .linkFather : .needsServer
        case .daughterSon:
            if hasPendingLineageRequest { return requestInWorkflow ? .openInbox : .decideRequest }
            if isPendingJoin && isMale && isProfile && current == nil { return joinInWorkflow ? .openInbox : .approveJoin }
            return .needsServer
        case .outsideHusband, .outsideWife:
            return .automatic
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

    // MARK: ح٢ ورقتك — أوامر العائلة والإدارة مقفولة

    /// أوامر العائلة (الجنس، الزوجات/الزوج، الأبناء، الظهور، الصلة، الأب) لمن يعدّل، ولا على ورقتك أنت —
    /// «البيانات» (الميلاد، الصورة، السيرة) تبقى كما في التصميم
    static func familyAdmin(canEdit: Bool, memberId: UUID, viewerId: UUID?) -> Bool {
        canEdit && memberId != viewerId
    }

    // MARK: ح١ نقل الجنس — من له حساب لا يُنقل

    /// له حساب في التطبيق؟ true يقيناً · false لا · nil لا يُعرف بعد (مخزن الحسابات لم يُحمَّل). دور إداري أو «طلب انضمام»
    /// (سجّل بنفسه) أو أنت أو موقوف أو قبل الشروط أو عقدة شجرة نساء مربوطة بحساب أو في مخزن الحسابات = له حساب
    static func appAccount(role: String, isViewer: Bool, frozen: Bool, looksRegistered: Bool, linkedLogin: Bool,
                           inAccountsStore: Bool, storeLoaded: Bool) -> Bool? {
        let staff: Set<String> = ["owner", "admin", "monitor", "supervisor", "pending"]
        if staff.contains(role) || isViewer || frozen || looksRegistered || linkedLogin || inAccountsStore { return true }
        return storeLoaded ? false : nil
    }

    /// ما يمنع «انقله» (السيرفر لا يمنع حذف من له حساب — `move_child_gender` إلى أنثى يحذف ملفه)
    enum GenderMoveBlock: Equatable {
        /// «له حساب في التطبيق — لا يُنقل»
        case account
        /// مخزن الحسابات لم يُحمَّل — «تعذّر التحقق»
        case unverified
        /// إلى أنثى بلا أب في الشجرة — البنت تُنقل تحت أبيها
        case noFather
        /// إلى أنثى وله أبناء/بنات/زوجات مربوطون — يرفضه السيرفر (`family_links_protected`)
        case linked(sons: Int, daughters: Int, wives: Int)
        /// إلى ذكر ولها زوج مربوط
        case linkedHusband
        /// إلى ذكر وأبوها ليس رجلاً في شجرة العائلة
        case fatherOutside
    }

    static func genderMoveBlock(toFemale: Bool, account: Bool?, hasFather: Bool, sons: Int, daughters: Int, wives: Int,
                                hasHusband: Bool, fatherInFamily: Bool) -> GenderMoveBlock? {
        guard let account else { return .unverified }
        if account { return .account }
        if toFemale {
            guard hasFather else { return .noFather }
            if sons + daughters + wives > 0 { return .linked(sons: sons, daughters: daughters, wives: wives) }
            return nil
        }
        if hasHusband { return .linkedHusband }
        return fatherInFamily ? nil : .fatherOutside
    }

    /// سطر «يُحذف» في مربّع النقل — لا «الحساب» (من له حساب لا يُنقل أصلاً)
    static func genderMoveLoses(toFemale: Bool, arabic: Bool = true) -> String {
        if toFemale {
            return arabic ? "الصورة · رقم الهاتف · السيرة · الدور" : "Photo · phone number · biography · role"
        }
        return arabic ? "لا شيء من بياناتها — تُنقل لشجرة العائلة ابناً تحت أبيه"
                      : "Nothing — moves to the family tree as a son under his father"
    }

    // MARK: ح٣ «فك الربط» للابن

    /// الابن بلا أبناء فقط: فكّ أبيه يُخرجه من شجرة العائلة (`full_name` = اسمه الأول) — ومن له أبناء يخرج فرعه كله معه،
    /// فيُعطَّل ويُوجَّه إلى «الأب ← تغيير» في ورقته
    static func sonUnlinkAllowed(childCount: Int) -> Bool { childCount == 0 }

    // MARK: م٥ «ربط زوج من العائلة» — لا محارمها

    /// رجال لا يُعرضون زوجاً لها: أبوها وأجدادها، وأبناء كلٍّ منهم (أعمامها وإخوتها)، وذكور ذرّية أبيها (أبناء إخوتها…)،
    /// وأبناؤها وذكور ذرّيتهم. `fatherOf` = أب كل رجل في شجرة العائلة
    static func husbandBlocked(fatherId: UUID?, sonIds: [UUID], fatherOf: [UUID: UUID]) -> Set<UUID> {
        var sonsOf: [UUID: [UUID]] = [:]
        for (son, father) in fatherOf { sonsOf[father, default: []].append(son) }
        func descendants(_ roots: [UUID]) -> Set<UUID> {
            var out = Set<UUID>()
            var stack = roots
            while let next = stack.popLast() {
                guard out.insert(next).inserted else { continue }
                stack += sonsOf[next] ?? []
            }
            return out
        }
        var blocked = Set<UUID>()
        if let fatherId {
            var chain: [UUID] = []
            var up: UUID? = fatherId
            var seen = Set<UUID>()
            while let a = up, seen.insert(a).inserted { chain.append(a); up = fatherOf[a] }
            blocked.formUnion(chain)
            for ancestor in chain.dropFirst() { blocked.formUnion(sonsOf[ancestor] ?? []) }
            blocked.formUnion(descendants([fatherId]))
        }
        blocked.formUnion(descendants(sonIds))
        return blocked
    }

    /// يظهر مرشّحاً زوجاً؟ رجل حيّ بالغ (العمر المجهول لا يُحكم عليه) له اسم، وليس «طلب انضمام»
    static func husbandEligible(isMale: Bool, isPending: Bool, hasName: Bool, isDeceased: Bool, age: Int?,
                                minAge: Int) -> Bool {
        guard isMale, !isPending, hasName, !isDeceased else { return false }
        if let age, age < minAge { return false }
        return true
    }

    // MARK: م٦ بعد نقل الجنس

    /// المعرّف الذي يعرضه الكرت: النقل بين الشجرتين يُنشئ سجلاً جديداً (`move_child_gender` يرجع معرّفه)
    static func resolved(_ id: UUID, moved: [UUID: UUID]) -> UUID {
        var current = id
        var seen: Set<UUID> = [id]
        while let next = moved[current], seen.insert(next).inserted { current = next }
        return current
    }
}
