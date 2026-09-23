import SwiftUI
import UIKit

// MARK: - مربّع الرسائل الموحّد (طلب المالك)
//
// كل رسائل التطبيق التي تظهر في منتصف الشاشة بتصميم واحد — نفس مربّع
// «تم تجاوز حد التعديلات»: بطاقة بزوايا ٢٤، النص كله باتجاه اليمين في العربية،
// وأزرار ممتلئة بعرض البطاقة. بديل مباشر لـ `.alert(...)` بنفس توقيعه:
//     .dsAlert("العنوان", isPresented: $flag) { Button(...) } message: { Text(...) }
// يُعرض في نافذة مستقلّة فوق كل شيء (حتى فوق الأوراق المفتوحة).

// MARK: إغلاق المربّع من الأزرار

private struct DSAlertDismissKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var dsAlertDismiss: () -> Void {
        get { self[DSAlertDismissKey.self] }
        set { self[DSAlertDismissKey.self] = newValue }
    }
}

/// أزرار المربّع: الأساسي كحلي، الحذف أحمر، الإلغاء رمادي — وكل ضغطة تنفّذ
/// إجراء الزر ثم تغلق المربّع.
///
/// ملاحظة مهمة: كانت الإغلاقة إيماءة لمس داخل ButtonStyle، وإيماءة الابن تتقدّم
/// على إيماءة الزر نفسه — فيُغلق المربّع ولا يُنفَّذ الإجراء (مثل «إزالة الجهاز»).
/// الآن PrimitiveButtonStyle: نستدعي trigger() صراحة ثم نغلق.
private struct DSAlertButtonStyle: PrimitiveButtonStyle {
    @Environment(\.dsAlertDismiss) private var dismiss

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.trigger()
            dismiss()
        } label: {
            configuration.label
        }
        .buttonStyle(DSAlertPressStyle(role: configuration.role))
        // التخطيط يرتّب حسب الدور: الإلغاء في مكان ثابت في كل الرسائل
        .layoutValue(key: DSAlertIsCancelKey.self, value: configuration.role == .cancel)
    }
}

/// شكل زر المربّع — كل الأزرار بنفس الخلفية الهادئة (طلب المالك)، ويُميَّز
/// الدور بلون النص: الحذف أحمر، الإلغاء عادي، الأساسي كحلي
private struct DSAlertPressStyle: ButtonStyle {
    let role: ButtonRole?

    func makeBody(configuration: Configuration) -> some View {
        // الحذف: مربّع أحمر بنص أبيض (طلب المالك)؛ الباقي خلفية هادئة
        let destructive = role == .destructive
        let text: Color = destructive ? .white
            : role == .cancel ? DS.Color.textPrimary
            : DS.Color.primary
        return configuration.label
            .font(DS.Font.calloutBold)
            .foregroundColor(text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 46)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(destructive ? DS.Color.error : DS.Color.mutedBackground.opacity(0.8)))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// هل الزر «إلغاء»؟ — لترتيب موحّد في كل الرسائل
private struct DSAlertIsCancelKey: LayoutValueKey {
    static let defaultValue = false
}

/// زرّان جنب بعض بعرض متساوٍ، وثلاثة فأكثر فوق بعض.
/// الترتيب موحّد مهما كان ترتيب الكود (طلب المالك):
/// «إلغاء» أولاً = يمين في العربية، والإجراء بعده = يسار؛ وفي العمودي «إلغاء» آخراً.
private struct DSAlertButtonsLayout: Layout {
    var spacing: CGFloat = DS.Spacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 280
        if subviews.count == 2 {
            let each = (width - spacing) / 2
            let h = subviews.map { $0.sizeThatFits(ProposedViewSize(width: each, height: nil)).height }.max() ?? 0
            return CGSize(width: width, height: h)
        }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if subviews.count == 2 {
            let each = (bounds.width - spacing) / 2
            // الإلغاء أولاً (يمين في RTL)، ثم الإجراء
            let ordered = subviews.sorted { a, b in a[DSAlertIsCancelKey.self] && !b[DSAlertIsCancelKey.self] }
            for (i, view) in ordered.enumerated() {
                let x = bounds.minX + CGFloat(i) * (each + spacing)
                view.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                           proposal: ProposedViewSize(width: each, height: bounds.height))
            }
            return
        }
        var y = bounds.minY
        // عمودياً: الإجراءات أولاً ثم الإلغاء في الأسفل
        let ordered = subviews.sorted { a, b in !a[DSAlertIsCancelKey.self] && b[DSAlertIsCancelKey.self] }
        for view in ordered {
            let h = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            view.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                       proposal: ProposedViewSize(width: bounds.width, height: h))
            y += h + spacing
        }
    }
}

// MARK: البطاقة

/// بطاقة المربّع الوسطي — تُستخدم للرسائل ولمربّعات خاصة (مثل «عن التطبيق»)
struct DSCenterCard<Content: View>: View {
    let onBackgroundTap: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @State private var appeared = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture { onBackgroundTap?() }

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                content()
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: 340)
            .background(DS.Color.background)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
            // إطار للمربّع في الوضع الداكن (طلب المالك) — يفصله عن الخلفية
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.16 : 0),
                                  lineWidth: colorScheme == .dark ? 1 : 0)
            )
            .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 10)
            .padding(.horizontal, DS.Spacing.xl)
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear { withAnimation(DS.Anim.snappy) { appeared = true } }
    }
}

/// محتوى رسالة: عنوان + نص + أزرار (أو «حسناً» إن لم تُمرَّر أزرار)
private struct DSAlertBody<A: View, M: View>: View {
    let title: String
    let actions: A
    let message: M?
    let onDismiss: () -> Void

    var body: some View {
        DSCenterCard(onBackgroundTap: nil) {
            Text(title)
                .font(DS.Font.plex(17, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let message {
                message
                    .font(DS.Font.plex(14, weight: .regular))
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DSAlertButtonsLayout {
                if A.self == EmptyView.self {
                    Button(L10n.t("حسناً", "OK")) {}
                } else {
                    actions
                }
            }
            .textFieldStyle(.roundedBorder)
            .buttonStyle(DSAlertButtonStyle())
            .environment(\.dsAlertDismiss, onDismiss)
            .padding(.top, DS.Spacing.xs)
        }
    }
}

// MARK: نافذة العرض — فوق كل شيء

@MainActor
final class DSPopupPresenter {
    static let shared = DSPopupPresenter()
    private var window: UIWindow?
    private var token = UUID()
    /// النافذة الرئيسية قبل العرض — تعود «مفتاحاً» بعد الإغلاق (للوحة المفاتيح والتركيز)
    private weak var previousKey: UIWindow?

    func show<V: View>(_ view: V) -> UUID {
        let id = UUID()
        token = id
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return id }
        if window == nil { previousKey = scene.windows.first(where: \.isKeyWindow) }
        let host = UIHostingController(rootView: AnyView(view))
        host.view.backgroundColor = .clear
        let w = window ?? UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear
        w.rootViewController = host
        w.overrideUserInterfaceStyle = scene.windows.first(where: \.isKeyWindow)?.overrideUserInterfaceStyle ?? .unspecified
        w.makeKeyAndVisible()
        window = w
        return id
    }

    /// يُخفي النافذة إن كانت ما زالت تعرض المربّع صاحب هذا المعرّف
    func hide(_ id: UUID) {
        guard id == token, let w = window else { return }
        w.isHidden = true
        w.rootViewController = nil
        window = nil
        previousKey?.makeKey()
    }
}

private final class DSAlertLatest<A: View, M: View> {
    var actions: (() -> A)?
    var message: (() -> M)??
}

private struct DSAlertModifier<A: View, M: View>: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let actions: () -> A
    let message: (() -> M)?
    @State private var shownID: UUID?
    /// أحدث نسخة من الأزرار والنص — onChange يلتقط قيم الرسم السابق، فالرسالة
    /// المبنية من بيانات (presenting) كانت تظهر بالعنوان فقط لأن البيانات nil وقتها
    @State private var latest = DSAlertLatest<A, M>()

    func body(content: Content) -> some View {
        latest.actions = actions
        latest.message = message
        return content
            .onChange(of: isPresented) { presented in
                presented ? present() : dismissWindow()
            }
            .onAppear { if isPresented { present() } }
            .onDisappear { dismissWindow() }
    }

    private func present() {
        let binding = $isPresented
        let view = DSAlertBody(
            title: title,
            actions: (latest.actions ?? actions)(),
            message: (latest.message ?? message)?(),
            onDismiss: {
                // بعد ظهور أثر الضغط — ثم تُغلق النافذة عبر onChange
                DispatchQueue.main.async { binding.wrappedValue = false }
            }
        )
        shownID = DSPopupPresenter.shared.show(view)
    }

    private func dismissWindow() {
        guard let id = shownID else { return }
        DSPopupPresenter.shared.hide(id)
        shownID = nil
    }
}

extension View {
    /// بديل `.alert` بتصميم التطبيق الموحّد (عنوان + أزرار)
    func dsAlert<A: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> A
    ) -> some View {
        modifier(DSAlertModifier<A, EmptyView>(title: title, isPresented: isPresented,
                                                actions: actions, message: nil))
    }

    /// بديل `.alert` بتصميم التطبيق الموحّد (عنوان + أزرار + نص)
    func dsAlert<A: View, M: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> A,
        @ViewBuilder message: @escaping () -> M
    ) -> some View {
        modifier(DSAlertModifier(title: title, isPresented: isPresented,
                                 actions: actions, message: message))
    }

    /// بديل `.alert(presenting:)` — الأزرار والنص يُبنيان من البيانات المعروضة
    func dsAlert<T, A: View, M: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> A,
        @ViewBuilder message: @escaping (T) -> M
    ) -> some View {
        modifier(DSAlertModifier(title: title, isPresented: isPresented,
                                 actions: { data.map(actions) },
                                 message: { data.map(message) }))
    }

    /// بديل `.alert(presenting:)` بلا نص
    func dsAlert<T, A: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> A
    ) -> some View {
        modifier(DSAlertModifier<A?, EmptyView>(title: title, isPresented: isPresented,
                                                 actions: { data.map(actions) }, message: nil))
    }
}
