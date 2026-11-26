import Foundation

// MARK: - منطق «اليوم» v2 الخالص (الاتجاه «أ» «بطاقات العائلة الملوّنة»، اختيار المالك ٢٠٢٦-١١-٢٦ — الوحدة V2-1)
//
// ما يقرّره الرأس الكحلي والمربّعات المسطّحة، بلا واجهة (Foundation فقط):
//  ١) **عدد الجرس** = ما يحتاج إجراء الآن وحده — الرقم نفسه على شريحة «يحتاج إجراء N» في «إشعارات الإدارة»: الحالات المشتقة
//     (`AdminNoticeStore.derive`) + الإشعارات التي تنتظر قراراً. قاعدة الإشعار هنا حرفياً قاعدة صفّه في الصفحة
//     (`AdminNotificationsPage.item` و`applySelfChild`): طلب معرّفه معروف = ما دام معلّقاً، وإلا ما دام غير مقروء؛ «محاولات
//     دخول مريبة» ما دامت غير مقروءة؛ «تمت إضافة ابن · راجعه» ما دام غير مقروء؛ وإشعار رسالة العضو لمن يرى الرسائل فقط.
//     غير المقروء وحده لم يعد يُعدّ على الجرس.
//  ٢) **كلمة مربّع «العائلة»**: «5 قوائم للمراجعة» = قوائم «يحتاج مراجعتك» التي فيها أحد (`AdminReviewHubCounts` — رقم
//     صفّها في «العائلة» نفسه)، أو «سليمة» حين تصل كلها صفراً. القوائم لا تحمل أعداد الأفراد (لا 2,991 ولا 170).
//  ٣) **كلمة مربّع «الإحصاءات»**: «الراحلون 502» ← قسم «الراحلون».
//  ٤) **سطر التحية حبّةً**: يُرسم حين يقول شيئاً فقط — لا أثناء التحميل ولا «ما في طلبات — يوم هادئ».
//
// يُفحص بلا محاكي (`tests/admin-redesign/V2/main.swift` — أمر `swiftc` في رأسه).

/// ما يحتاجه عدد الجرس من إشعار إدارة واحد
nonisolated struct AdminBellNotice: Hashable {
    /// `AdminNotices.category` — nil = ليس إشعار إدارة (لا يُعدّ)
    var category: AdminNoticeCategory?
    var read: Bool
    /// معرّف الطلب في الإشعار (`AdminNotices.requestId`) — nil = لا طلب معروف
    var requestId: UUID? = nil
    /// «محاولات دخول مريبة» (`sms_suspicious`)
    var suspicious = false
    /// «تمت إضافة ابن» بطلب مراجعة (`details.selfChild` + `details.review` وللابن ملف)
    var selfChildReview = false
    /// إشعار رسالة عضو (`contact_message`) — لمن يرى الرسائل (`inbox.messages`) فقط
    var contactMessage = false
}

nonisolated enum AdminTodayBandLogic {

    // MARK: الجرس

    /// الإشعار يحتاج إجراء الآن — قاعدة صفّه في «إشعارات الإدارة» نفسها
    static func needsAction(_ notice: AdminBellNotice, open: Set<UUID>) -> Bool {
        switch notice.category {
        case .action?:
            if notice.suspicious { return !notice.read }
            return notice.requestId.map(open.contains) ?? !notice.read
        case .changes?:
            return notice.selfChildReview && !notice.read
        case .team?, .system?, nil:
            return false
        }
    }

    /// عدد الجرس = الحالات المشتقة + الإشعارات التي تحتاج إجراء (= «يحتاج إجراء N» في الصفحة)
    /// - open: معرّفات الطلبات المعلّقة الآن (`AdminTodayFeed.openRequestIds`)
    static func bellCount(derived: Int, notices: [AdminBellNotice], open: Set<UUID>, seesMessages: Bool) -> Int {
        max(0, derived) + notices.filter { (seesMessages || !$0.contactMessage) && needsAction($0, open: open) }.count
    }

    /// نصّ الشارة الذهبية: «3» · «99+» — nil = لا شارة
    static func bellBadge(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }

    // MARK: كلمات المربّعات

    /// «العائلة»: عدد قوائم «يحتاج مراجعتك» التي فيها أحد. `counts` = عدد كل قائمة بترتيبها (nil = لم يصل بعد).
    /// لا شيء وصل = nil (هيكل)؛ فيها أحد = «5 قوائم للمراجعة» (محايدة — تُقال ولا تُلحّ)؛ كلها وصلت صفراً = «سليمة» ✓؛
    /// صفر فيما وصل وبعضها لم يصل = nil (لا «سليمة» قبل أن تُعرف كلها)
    static func reviewListsWord(counts: [Int?]) -> AdminTodayWord? {
        let known = counts.compactMap { $0 }
        guard !known.isEmpty else { return nil }
        let busy = known.filter { $0 > 0 }.count
        if busy > 0 { return AdminTodayWord(state: .neutral(listsText(busy))) }
        guard known.count == counts.count else { return nil }
        return AdminTodayWord(state: .good(L10n.t("سليمة", "All good")))
    }

    /// عدد القوائم التي فيها أحد — رقم «5 قوائم» نفسه (nil = لا شيء وصل)
    static func busyLists(_ counts: [Int?]) -> Int? {
        let known = counts.compactMap { $0 }
        return known.isEmpty ? nil : known.filter { $0 > 0 }.count
    }

    /// «قائمة واحدة للمراجعة» · «قائمتان للمراجعة» · «5 قوائم للمراجعة» · «11 قائمة للمراجعة»
    static func listsText(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "1 list to review" : "\(AdminNumberText.grouped(n)) lists to review" }
        let what = AdminTodayLogic.counted(n, one: "قائمة واحدة", two: "قائمتان", few: "قوائم", many: "قائمة",
                                           single: "قائمة")
        return "\(what) للمراجعة"
    }

    /// «الإحصاءات»: «الراحلون 502» ← قسم «الراحلون». nil قبل وصول الأعداد
    static func departedWord(_ deceased: Int?) -> AdminTodayWord? {
        guard let deceased else { return nil }
        let n = AdminNumberText.grouped(deceased)
        return AdminTodayWord(state: .neutral(L10n.t("الراحلون \(n)", "Departed \(n)")), landing: .stats(.departed))
    }

    // MARK: سطر التحية

    /// الحبّة تُرسم حين يقول السطر شيئاً: له بيت يفتحه، أو حقيقة غير «يوم هادئ». أثناء التحميل (nil) لا شيء
    static func showsSmartPill(_ line: AdminSmartLine?) -> Bool {
        guard let line, !line.text.isEmpty else { return false }
        return line.link != nil || line.text != AdminTodayLogic.calmText
    }
}
