import SwiftUI

/// شريط السدو أسفل رأس الأقسام — نفس الشكل الثابت القديم (خطّان ومعيّنات خمسة، الأوسط أكبر)،
/// وعليه حركة هادئة بطلب المالك ٢٠٢٦-١٠-٠٤ («لا تغيّر السدو، خلها القديمة بس حط حركات»):
///  • عند ظهور القسم: الخطّان يمتدّان من الوسط للأطراف، والمعيّنات تظهر من الوسط تباعاً.
///  • بعدها: موجة ضوء خفيفة تعبر المعيّنات (كل ٣ ثوانٍ)، ولمعة هادئة تجري على الخطّين (كل ٦ ثوانٍ).
/// «تقليل الحركة»: الشكل الثابت كما كان بلا أي حركة.
struct SaduOrnament: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var start = Date()

    private let ink = DS.Color.textOnPrimary

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 0 : max(0, tl.date.timeIntervalSince(start))
            HStack(spacing: 5) {
                line(t: t, anchor: .trailing)
                ForEach(0..<5, id: \.self) { i in diamond(i, t: t) }
                line(t: t, anchor: .leading)
            }
        }
        // متماثل — نثبّت الاتجاه حتى تمتدّ الخطوط من الوسط في العربي والإنجليزي
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
        .onAppear {
            start = Date()
            if reduceMotion { shown = true; return }
            shown = false
            withAnimation(.easeOut(duration: 0.7).delay(0.1)) { shown = true }
        }
    }

    /// خطّ يمتدّ من جهة المعيّنات للخارج، وعليه لمعة تجري كل ٦ ثوانٍ
    private func line(t: TimeInterval, anchor: UnitPoint) -> some View {
        Rectangle()
            .fill(ink.opacity(0.16))
            .frame(height: 1)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        let w = geo.size.width
                        // يمين الخطّ الأيسر ← يسار الخطّ الأيمن: اللمعة تخرج من الوسط للطرف
                        let p = CGFloat((t / 6).truncatingRemainder(dividingBy: 1))
                        let x = anchor == .trailing ? w - p * (w + 60) : -60 + p * (w + 60)
                        LinearGradient(colors: [.clear, ink.opacity(0.55), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: 60)
                            .offset(x: x)
                    }
                    .mask(Rectangle().frame(height: 1))
                }
            }
            .scaleEffect(x: shown ? 1 : 0, anchor: anchor)
    }

    /// معيّن — يظهر من الوسط تباعاً، وتعبره موجة ضوء خفيفة
    private func diamond(_ i: Int, t: TimeInterval) -> some View {
        let center = i == 2
        let base: Double = center ? 0.55 : 0.30
        let fromCenter = Double(abs(i - 2))
        // موجة: ٠…١ تمرّ من اليمين لليسار كل ٣ ثوانٍ
        let wave = reduceMotion ? 0 : max(0, sin((t / 3) * 2 * .pi - Double(4 - i) * 0.7))
        return Rectangle()
            .fill(ink.opacity(min(0.9, base + wave * 0.35)))
            .frame(width: center ? 6 : 4, height: center ? 6 : 4)
            .scaleEffect(1 + CGFloat(wave) * 0.25)
            .rotationEffect(.degrees(45))
            .scaleEffect(shown ? 1 : 0.01)
            .opacity(shown ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.6).delay(0.25 + fromCenter * 0.12),
                       value: shown)
    }
}
