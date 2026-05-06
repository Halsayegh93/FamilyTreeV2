import SwiftUI

/// Modifier يمنع الضغط المكرر على أي `Button` خلال فترة قصيرة
/// الاستخدام:
/// ```swift
/// Button { saveAction() } label: { ... }
///   .singleTap("save_member_\(id)")
/// ```
/// أو بدون مفتاح (يولّد افتراضي):
/// ```swift
/// Button { ... } label: { ... }.singleTap()
/// ```
struct SingleTapModifier: ViewModifier {
    let key: String
    let interval: TimeInterval
    @State private var isLocked = false

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!isLocked)
            .simultaneousGesture(
                TapGesture().onEnded {
                    guard !isLocked else { return }
                    isLocked = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                        isLocked = false
                    }
                }
            )
    }
}

extension View {
    /// يمنع الضغط المكرر على الزر خلال `interval` ثانية (افتراضياً 0.6)
    func singleTap(_ key: String = UUID().uuidString, interval: TimeInterval = 0.6) -> some View {
        self.modifier(SingleTapModifier(key: key, interval: interval))
    }
}

/// Drop-in بديل لـ `Button { action } label: { ... }` يضمن الضغط مرة وحدة
/// الاستخدام:
/// ```swift
/// SingleFireButton {
///   await saveAction()
/// } label: {
///   Text("حفظ")
/// }
/// ```
struct SingleFireButton<Label: View>: View {
    let action: () -> Void
    let label: () -> Label
    @State private var lastFire: Date = .distantPast
    let interval: TimeInterval

    init(interval: TimeInterval = 0.6, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.interval = interval
        self.action = action
        self.label = label
    }

    var body: some View {
        Button {
            let now = Date()
            if now.timeIntervalSince(lastFire) >= interval {
                lastFire = now
                action()
            }
        } label: {
            label()
        }
    }
}
