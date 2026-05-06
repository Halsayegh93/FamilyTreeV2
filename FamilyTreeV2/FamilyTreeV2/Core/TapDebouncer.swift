import Foundation

/// Global tap debouncer — يمنع تكرار الضغط على الأزرار خلال فترة قصيرة
/// الاستخدام: `TapDebouncer.shared.canFire(key: "approve_\(id)")` ثم نفّذ الإجراء
@MainActor
final class TapDebouncer {
    static let shared = TapDebouncer()

    /// آخر وقت تم فيه ضغط مفتاح معين
    private var lastFireTimes: [String: Date] = [:]

    /// الفترة الافتراضية لمنع الضغط المكرر (بالثواني)
    static let defaultInterval: TimeInterval = 0.6

    /// فحص ما إذا كان يمكن تنفيذ الإجراء، وإذا أمكن سجّل الوقت
    /// - Returns: `true` إذا مرّ وقت كافٍ منذ آخر ضغط لنفس المفتاح
    @discardableResult
    func canFire(_ key: String, interval: TimeInterval = TapDebouncer.defaultInterval) -> Bool {
        let now = Date()
        if let last = lastFireTimes[key], now.timeIntervalSince(last) < interval {
            return false
        }
        lastFireTimes[key] = now
        return true
    }

    /// إعادة تعيين مفتاح معين (لو الإجراء فشل وتبي تسمح بإعادة المحاولة فوراً)
    func reset(_ key: String) {
        lastFireTimes.removeValue(forKey: key)
    }

    /// تنظيف المفاتيح القديمة (أكثر من ساعة)
    func cleanup() {
        let cutoff = Date().addingTimeInterval(-3600)
        lastFireTimes = lastFireTimes.filter { $0.value > cutoff }
    }
}

/// Wrapper تلقائي لتنفيذ إجراء مرة واحدة بناءً على مفتاح
/// الاستخدام:
/// ```
/// Button { debouncedTap("save_\(id)") { saveAction() } } label: { ... }
/// ```
@MainActor
func debouncedTap(_ key: String, interval: TimeInterval = TapDebouncer.defaultInterval, action: () -> Void) {
    if TapDebouncer.shared.canFire(key, interval: interval) {
        action()
    }
}

/// نسخة async
@MainActor
func debouncedTapAsync(_ key: String, interval: TimeInterval = TapDebouncer.defaultInterval, action: () async -> Void) async {
    if TapDebouncer.shared.canFire(key, interval: interval) {
        await action()
    }
}
