import Foundation

// MARK: - منطق «المناسبات والإعلانات» (إعادة التصميم ٢٠٢٦-١١-٢٦ — spec C.11، الوحدة U14)
//
// منطق خالص (Foundation فقط) يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u14-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminOccasionsLogic.swift tests/admin-redesign/U14/main.swift && /tmp/u14-logic
//
//  ١) الأقسام بترتيب المالك ٢٠٢٦-١١-٢٨ (`admin-sections`): «القادم» (المجدول) ← «عزاء وذكرى» ← «أفراح العائلة» ←
//     «الإعلانات عند الفتح» ← «المنشور» (المنشور ووصول الإشعارات). كان «أفراح» ← «عزاء» ← «عند الفتح» ← «الإعلانات».
//  ٢) ما يراه الدور وما يعدّله: كل أمر = صلاحية الدور (`isAdmin`، `canSendNotifications`، خانات `occasions.*`) × «يعدّل»
//     القسم في جدول السيرفر (`adminCanEdit(.occasions)`) — فالمراقب (المناسبات «للاطلاع») يرى الذكرى بلا أزرار.
//  ٣) الهبوط (`AdminOccasionsAnchor` من «اليوم» أو سطر الرأس) ← القسم الذي يُمرَّر إليه.

/// أقسام الصفحة بترتيبها
nonisolated enum AdminOccasionsSection: String, CaseIterable, Hashable {
    /// «القادم»: الإشعارات المجدولة «تعديل»/«إلغاء الموعد» (كانت أول «الإعلانات»)
    case upcoming
    /// «عزاء وذكرى» (وفاة لم تُعلن «إعلان»، ذكرى الراحلين، المتوفون بلا تاريخ كامل)
    case grief
    /// «أفراح العائلة» (زواج · مولود · تهنئة من الأخبار، و«بطاقة» على كل فرح)
    case joys
    /// «الإعلانات عند الفتح» («إيقاف»)
    case launch
    /// «المنشور»: المنشور N ‹ ووصول الإشعارات (كانا آخر «الإعلانات»)
    case published
}

nonisolated enum AdminOccasionsLogic {
    /// ما يراه الدور ويعدّله في الصفحة
    struct Access: Equatable {
        /// قسم «أفراح العائلة» — لمن يصمّم البطاقات (كما كان)
        var joys = false
        /// «بطاقة» على صفّ فرح
        var card = false
        /// «＋ إنشاء» في الرأس
        var create = false
        /// «إعلان» على وفاة لم تُعلن (والوفيات نفسها تظهر للمالك والمدير فقط)
        var deaths = false
        var announceDeath = false
        /// «الإعلانات عند الفتح» و«إيقاف»
        var launch = false
        var stopLaunch = false
        /// «الإعلانات» و«تعديل»/«إلغاء الموعد»
        var announcements = false
        var editScheduled = false
        /// سطر أرقام الرأس (المالك والمدير)
        var headerLine = false
        /// صفّ «متوفون بلا تاريخ وفاة كامل» وهل يفتح «تواريخ الوفاة»
        var datesRow = false
        var datesOpens = false
        /// «تصل الإشعارات إلى N جهازاً» (المالك — بيته «الفريق والأمان»)
        var reach = false
        /// سطر «للاطلاع فقط» في الرأس
        var readOnly = false

        /// - cardKind: «تصميم إعلان» من أنواع المنشئ لدورك (`AdminCreateKind.allowed` — `canModerate` + `occasions.cards`)
        /// - announceKind: «إرسال إشعار» من أنواعه + خانة `occasions.announce` «يعدّل»
        /// - seesPublished: خانة `occasions.published` ظاهرة
        /// - areaEdit: `adminCanEdit(.occasions)`
        /// - familyEdit: `adminCanEdit(.family)` — «تواريخ الوفاة» صفحة تحت «العائلة»
        /// - ownerSystem: `canViewSystemSettings`
        static func make(isAdmin: Bool, canSendNotifications: Bool, cardKind: Bool, announceKind: Bool,
                         seesPublished: Bool, areaEdit: Bool, canEditMembers: Bool, familyEdit: Bool,
                         ownerSystem: Bool) -> Access {
            var a = Access()
            a.readOnly = !areaEdit
            a.joys = cardKind
            a.card = cardKind && areaEdit
            a.create = areaEdit && (cardKind || announceKind)
            a.deaths = isAdmin
            a.announceDeath = isAdmin && areaEdit
            a.launch = isAdmin
            a.stopLaunch = isAdmin && areaEdit
            a.announcements = isAdmin && seesPublished
            a.editScheduled = a.announcements && canSendNotifications && areaEdit
            a.headerLine = isAdmin
            a.datesRow = canEditMembers
            a.datesOpens = canEditMembers && familyEdit
            a.reach = a.announcements && ownerSystem
            return a
        }
    }

    /// الأقسام الظاهرة بترتيبها — «عزاء وذكرى» للجميع (المراقب والمشرف: الذكرى)
    static func sections(_ access: Access) -> [AdminOccasionsSection] {
        var list: [AdminOccasionsSection] = []
        if access.announcements { list.append(.upcoming) }
        list.append(.grief)
        if access.joys { list.append(.joys) }
        if access.launch { list.append(.launch) }
        if access.announcements { list.append(.published) }
        return list
    }

    /// القسم الذي يملك هذا الهبوط
    static func section(for anchor: AdminOccasionsAnchor) -> AdminOccasionsSection {
        switch anchor {
        case .awaiting, .memorials: return .grief
        case .launch:               return .launch
        case .scheduled:            return .upcoming
        case .doors:                return .published
        }
    }

    /// إلى أين تُمرَّر الصفحة عند الفتح: الصريح (`init`) يغلب المخزَّن (`AdminAreaRouter.take`)؛ القسم المخفي لدورك يُتجاهل،
    /// وأول قسم ظاهر = أعلى الصفحة بلا تمرير (يبقى الرأس ظاهراً)
    static func scrollTarget(explicit: AdminOccasionsAnchor?, stored: AdminOccasionsAnchor?,
                             shown: [AdminOccasionsSection]) -> AdminOccasionsSection? {
        guard let anchor = explicit ?? stored else { return nil }
        let target = section(for: anchor)
        guard shown.contains(target), shown.first != target else { return nil }
        return target
    }

    /// أول `limit` ثم «عرض الكل (N)» — المطويّ يعرض `limit`، والمفتوح الكل
    static func visibleCount(total: Int, limit: Int, expanded: Bool) -> Int {
        expanded ? total : min(total, limit)
    }

    /// يحتاج رابط «عرض الكل»؟
    static func needsToggle(total: Int, limit: Int) -> Bool { total > limit }

    /// كم يُعرض قبل «عرض الكل»: الأفراح والذكرى ٣ (spec C.11)
    static let collapsedRows = 3
}
