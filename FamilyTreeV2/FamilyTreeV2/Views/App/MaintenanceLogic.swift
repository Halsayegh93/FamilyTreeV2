import Foundation

// MARK: - منطق شاشة الصيانة وسببها (طلب المالك ٢٠٢٦-١١-٢٨، الوحدة MT1)
//
// منطق خالص (Foundation فقط) يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/mt1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/App/MaintenanceLogic.swift tests/admin-redesign/MT1/main.swift && /tmp/mt1-logic
//
//  ١) سبب الصيانة (`app_settings.maintenance_message`، ≤ ٢٠٠ حرف): يكتبه المالك في «التطبيق ← حالة التطبيق ← وضع الصيانة»
//     ويظهر للأعضاء بدل السطر الافتراضي — الفارغ/المسافات = السطر الافتراضي. بلا وقت رجوع («ما نحط وقت للرجوع»).
//  ٢) الرجوع التلقائي: الشاشة تعيد جلب الإعدادات كل ٦٠ ث (حلقة `Task` تُلغى عند الاختفاء) وعند الرجوع للتطبيق،
//     وحين تُطفأ الصيانة يكمل التطبيق وحده.

nonisolated enum MaintenanceLogic {
    /// حدّ السبب (= قيد السيرفر `app_settings_maintenance_message_len`)
    static let maxMessageLength = 200

    /// كل كم ثانية تعيد الشاشة جلب الإعدادات
    static let refreshSeconds: UInt64 = 60

    /// السطر الافتراضي تحت العنوان
    static var defaultLine: String {
        L10n.t("نقوم حالياً بتحديث التطبيق. يرجى المحاولة لاحقاً.",
               "We're currently updating the app. Please try again later.")
    }

    /// السبب كما يُحفظ: بلا مسافات في الطرفين، بحدّ ٢٠٠ حرف، والفارغ = nil (يرجع السطر الافتراضي)
    static func sanitized(_ raw: String?) -> String? {
        let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return t.count > maxMessageLength ? String(t.prefix(maxMessageLength)) : t
    }

    /// يظهر سبب المالك (لا السطر الافتراضي)؟
    static func shouldShowMessage(_ raw: String?) -> Bool { sanitized(raw) != nil }

    /// السطر تحت «التطبيق تحت الصيانة»: سبب المالك إن كُتب، وإلا الافتراضي
    static func bodyLine(_ raw: String?) -> String { sanitized(raw) ?? defaultLine }

    /// تغيّر السبب في الحقل عمّا هو محفوظ؟ (المسافات وحدها لا تُحسب تغييراً)
    static func isDirty(draft: String, saved: String?) -> Bool { sanitized(draft) != sanitized(saved) }

    /// الحقل لا يقبل أكثر من الحد أثناء الكتابة
    static func clampedDraft(_ text: String) -> String {
        text.count > maxMessageLength ? String(text.prefix(maxMessageLength)) : text
    }

    /// «45/200» — عدّاد الحروف تحت الحقل
    static func counter(_ draft: String) -> String { "\(min(draft.count, maxMessageLength))/\(maxMessageLength)" }

    /// تبقى شاشة الصيانة؟ (الإدارة تدخل كالعادة) — false = يكمل التطبيق وحده بلا ضغطة
    static func showsScreen(maintenanceOn: Bool, canModerate: Bool) -> Bool { maintenanceOn && !canModerate }
}
