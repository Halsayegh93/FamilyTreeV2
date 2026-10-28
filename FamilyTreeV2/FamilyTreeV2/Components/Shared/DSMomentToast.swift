import SwiftUI
import UIKit

// MARK: - لحظة النجاح الخفيفة (الدفعة ١٠ «لحظة نجاح» — طلب المالك ٢٠٢٦-١٠-٢٠)
//
// حيث لا يوجد تأكيد أصلاً (الموافقة على طلب، الاعتماد، التنفيذ — يُغلق المربّع ويختفي الصفّ بلا كلمة): كبسولة صغيرة أعلى
// الشاشة بمجسّم اللحظة نفسه من `FTMoments` (`.approved`) مصغّراً + سطر («تمت الموافقة»)، مع اهتزاز نجاح خفيف، ثم تختفي
// وحدها. لا أزرار ولا تنبيه جديد: ما كان له تأكيد (`dsAlert(…, moment:)`) يبقى كما هو.
// نافذة مستقلّة فوق التطبيق وتحت المربّعات (`DSPopupPresenter` = `.alert + 1`) لا تلتقط اللمس، فتبقى بعد إغلاق المربّع الذي
// فيه زرّ الموافقة. القارئ الصوتي يسمع السطر. «تقليل الحركة»: تلاشٍ فقط.

@MainActor
enum DSMomentToast {
    private static var window: UIWindow?
    private static var token = UUID()

    /// يعرض اللحظة (ويستبدل أي لحظة ظاهرة) — `section` لون الوسام
    static func show(_ title: String, moment: FTMoments.Moment = .approved, section: AppSection? = .admin) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: title)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }
        let id = UUID()
        token = id
        let view = DSMomentToastView(title: title, moment: moment, tint: section?.fill ?? DS.Color.actionNavy) {
            hide(id)
        }
        let host = UIHostingController(rootView: AnyView(view.dsSection(section)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)))
        host.view.backgroundColor = .clear
        let w = window ?? UIWindow(windowScene: scene)
        w.windowLevel = .alert
        w.backgroundColor = .clear
        // لا تلتقط اللمس — التطبيق تحتها يعمل كما هو
        w.isUserInteractionEnabled = false
        w.overrideUserInterfaceStyle = DSPopupPresenter.appInterfaceStyle(in: scene)
        w.rootViewController = host
        w.isHidden = false
        window = w
    }

    private static func hide(_ id: UUID) {
        guard id == token, let w = window else { return }
        w.isHidden = true
        w.rootViewController = nil
        window = nil
    }
}

/// الكبسولة: تنزل من أعلى وتبقى `DS.MomentToast.hold` ث ثم تصعد وتختفي
private struct DSMomentToastView: View {
    let title: String
    let moment: FTMoments.Moment
    let tint: Color
    let done: () -> Void
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            HStack(spacing: DS.Spacing.sm) {
                FTMomentView(moment: moment, tint: tint)
                    .scaleEffect(DS.MomentToast.artScale)
                    .frame(width: DS.MomentToast.artWidth, height: DS.MomentToast.art)
                Text(title)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, DS.Spacing.xs)
            .padding(.trailing, DS.MomentToast.padding + DS.Spacing.xs)
            .padding(.vertical, DS.Spacing.xs)
            .frame(minHeight: DS.MomentToast.minHeight)
            .background(Capsule().fill(DS.Color.surface))
            .overlay(Capsule().strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke), lineWidth: DS.Border.width))
            .dsCardShadow()
            .padding(.top, DS.MomentToast.topInset)
            .padding(.horizontal, DS.Spacing.lg)
            .offset(y: shown || reduceMotion ? 0 : -DS.MomentToast.rise)
            .opacity(shown ? 1 : 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(reduceMotion ? DSMotion.fade : DS.Anim.bouncy) { shown = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + DS.MomentToast.hold) {
                withAnimation(reduceMotion ? DSMotion.fade : DS.Anim.smooth) { shown = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + DS.MomentToast.fadeOut) { done() }
            }
        }
    }
}
