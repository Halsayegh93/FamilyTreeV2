import SwiftUI

// MARK: - صورة قابلة للتكبير والتحريك (طلب المالك)
//
// تُستخدم في تفاصيل عناصر المكتبة وفي معرض صور المشاريع:
// • قرصة بإصبعين للتكبير (حتى ٥ أضعاف)
// • سحب لتحريك الصورة وهي مكبّرة، مع إرجاعها داخل الإطار
// • ضغطتان: تكبير ×٢٫٥ عند نقطة الضغط، وضغطتان مرة ثانية للرجوع

struct ZoomableImage<Content: View>: View {
    /// الحد الأقصى للتكبير
    var maxScale: CGFloat = 5
    /// تكبير الضغطتين
    var doubleTapScale: CGFloat = 2.5
    /// يُستدعى عند تغيّر حالة التكبير — لتعطيل تمرير الصفحات مثلاً
    var onZoomChange: ((Bool) -> Void)? = nil
    @ViewBuilder let content: () -> Content

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            content()
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    SimultaneousGesture(magnification(in: geo.size), drag(in: geo.size))
                )
                .onTapGesture(count: 2) { toggleZoom(in: geo.size) }
                .clipped()
                // إحداثيات فيزيائية ثابتة: في الواجهة العربية كان محور الإزاحة
                // معكوساً فتتحرك الصورة ضد اتجاه الإصبع (طلب المالك)
                .environment(\.layoutDirection, .leftToRight)
                .animation(DS.Anim.quick, value: scale)
        }
    }

    // MARK: الإيماءات

    private func magnification(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(1, lastScale * value), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.01 { reset() } else { clampOffset(in: size) }
                notify()
            }
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                guard scale > 1 else { return }
                clampOffset(in: size)
            }
    }

    private func toggleZoom(in size: CGSize) {
        withAnimation(DS.Anim.snappy) {
            if scale > 1 {
                reset()
            } else {
                scale = doubleTapScale
                lastScale = scale
            }
        }
        notify()
    }

    // MARK: الحدود

    /// يمنع سحب الصورة خارج إطارها — يرجّعها للحافة عند تجاوزها
    private func clampOffset(in size: CGSize) {
        let maxX = max(0, (size.width * scale - size.width) / 2)
        let maxY = max(0, (size.height * scale - size.height) / 2)
        withAnimation(DS.Anim.quick) {
            offset = CGSize(width: min(max(offset.width, -maxX), maxX),
                            height: min(max(offset.height, -maxY), maxY))
        }
        lastOffset = offset
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    private func notify() {
        onZoomChange?(scale > 1.01)
    }
}
