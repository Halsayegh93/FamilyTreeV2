import SwiftUI
import UIKit

// MARK: - نصوص البوست بنفس حساب المتصفح (CSS)
//
// التصميم المعتمد ملفات HTML: لكل سطر «صندوق» ارتفاعه line-height × حجم الخط، والخط نفسه
// في نص الصندوق (نصف الفراغ فوق ونصفه تحت حسب ascent/descent). Text في SwiftUI يحسب ارتفاع
// السطر من الخط نفسه (فيه leading كبير بخط URW) — فكنا نقص بالسالب ويركب السطر على اللي فوقه.
// هنا نقسّم النص على سطور بأنفسنا (عادي أو text-wrap: balance) ونرسم كل سطر بصندوقه وخط الأساس
// بمكانه بالضبط، فالمسافات بين السطور تطلع مثل التصميم بدون تداخل.

enum OccasionWrap {
    /// لف عادي (مثل المتصفح بدون text-wrap)
    case normal
    /// text-wrap: balance — نفس عدد السطور لكن بأطوال متقاربة
    case balance
}

struct OccasionTextLayout: Equatable {
    let lines: [String]
    let size: CGFloat

    /// عرض أطول سطر (مثل max-content للكتلة)
    func width(_ weight: OccasionKit.FontWeight) -> CGFloat {
        let f = Self.font(weight, size)
        return lines.map { Self.width($0, f) }.max() ?? 0
    }

    // MARK: القياس

    static func font(_ weight: OccasionKit.FontWeight, _ size: CGFloat) -> UIFont {
        UIFont(name: weight.postScriptName, size: size) ?? UIFont.systemFont(ofSize: size)
    }

    static func width(_ s: String, _ font: UIFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width
    }

    /// الكلمات تنفصل بالمسافة العادية فقط (المسافة الثابتة U+00A0 في «المحمد علي» ما تنقسم)
    private static func words(_ paragraph: String) -> [String] {
        paragraph.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    /// لف عادي: أكبر عدد كلمات بكل سطر
    static func greedy(_ words: [String], _ font: UIFont, _ maxWidth: CGFloat) -> [String] {
        var lines: [String] = []
        var current = ""
        for w in words {
            if current.isEmpty {
                current = w
                continue
            }
            let candidate = current + " " + w
            if width(candidate, font) <= maxWidth + 0.01 {
                current = candidate
            } else {
                lines.append(current)
                current = w
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    /// text-wrap: balance — أصغر عرض يحافظ على نفس عدد السطور (مثل المتصفح)
    static func balanced(_ words: [String], _ font: UIFont, _ maxWidth: CGFloat) -> [String] {
        let base = greedy(words, font, maxWidth)
        guard base.count > 1 else { return base }
        var lo: CGFloat = 0
        var hi = maxWidth
        var best = base
        for _ in 0..<18 {
            let mid = (lo + hi) / 2
            let attempt = greedy(words, font, mid)
            if attempt.count <= base.count {
                best = attempt
                hi = mid
            } else {
                lo = mid
            }
            if hi - lo < 0.5 { break }
        }
        return best
    }

    /// أفضل تقسيم على عدد سطور محدد (أقل عرض لأطول سطر) — للاحتياط إذا الاسم طويل جداً
    private static func bestSplit(_ words: [String], _ font: UIFont, lines count: Int) -> [String] {
        guard words.count > count, count > 1 else { return words.isEmpty ? [] : [words.joined(separator: " ")] }
        // ثنائي البحث على العرض: أصغر عرض يعطي «count» سطور أو أقل
        let total = width(words.joined(separator: " "), font)
        var lo: CGFloat = 0
        var hi = total
        var best = greedy(words, font, hi)
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            let attempt = greedy(words, font, mid)
            if attempt.count <= count {
                best = attempt
                hi = mid
            } else {
                lo = mid
            }
        }
        return best
    }

    private static func wrap(_ text: String, _ font: UIFont, _ maxWidth: CGFloat, _ mode: OccasionWrap) -> [String] {
        text.components(separatedBy: "\n").flatMap { paragraph -> [String] in
            let ws = words(paragraph)
            guard !ws.isEmpty else { return [] }
            switch mode {
            case .normal: return greedy(ws, font, maxWidth)
            case .balance: return balanced(ws, font, maxWidth)
            }
        }
    }

    /// يقسّم النص على سطور. maxLines (للأسماء): إذا زاد عدد السطور يصغر الخط شوي شوي،
    /// بس ما ينزل عن minScale من الحجم الأصلي؛ وإذا ما كفى حتى عنده يتقسم على maxLines ويصغر لين يدخل بالعرض.
    static func make(_ text: String, weight: OccasionKit.FontWeight, size: CGFloat, maxWidth: CGFloat,
                     wrap mode: OccasionWrap, maxLines: Int? = nil, minScale: CGFloat = 0.7) -> OccasionTextLayout {
        guard !text.isEmpty else { return OccasionTextLayout(lines: [], size: size) }
        var s = size
        var lines = wrap(text, font(weight, s), maxWidth, mode)
        guard let maxLines, lines.count > maxLines else { return OccasionTextLayout(lines: lines, size: s) }

        let minSize = (size * minScale).rounded(.down)
        let step = max(1, (size * 0.02).rounded())
        // عدد السطور يحدده اللف العادي (التوازن ما يغيّر العدد) — نوازن مرة وحدة بالنهاية
        var count = lines.count
        while count > maxLines && s > minSize {
            s = max(minSize, s - step)
            count = wrap(text, font(weight, s), maxWidth, .normal).count
        }
        if count <= maxLines {
            return OccasionTextLayout(lines: wrap(text, font(weight, s), maxWidth, mode), size: s)
        }

        // احتياط نادر (كلمات طويلة جداً): سطرين بأقل عرض، والحجم يصغر بقدر ما يدخل
        let ws = words(text.replacingOccurrences(of: "\n", with: " "))
        lines = bestSplit(ws, font(weight, s), lines: maxLines)
        let widest = lines.map { width($0, font(weight, s)) }.max() ?? 0
        if widest > maxWidth { s = (s * maxWidth / widest).rounded(.down) }
        return OccasionTextLayout(lines: lines, size: s)
    }

    // MARK: سطر واحد (الأسماء والعناوين القصيرة)

    /// نسبة الحجم اللي يحتاجها النص حتى يدخل بسطر واحد (1 = يدخل بحجم التصميم)
    static func fitScale(_ text: String, weight: OccasionKit.FontWeight, size: CGFloat, maxWidth: CGFloat) -> CGFloat {
        let t = text.replacingOccurrences(of: "\n", with: " ")
        guard !t.isEmpty, maxWidth > 0 else { return 1 }
        let w = width(t, font(weight, size))
        return w <= maxWidth + 0.01 ? 1 : maxWidth / w
    }

    /// سطر واحد بحجم التصميم؛ إذا ما دخل يصغر بقدر ما يدخل بس ما ينزل عن minScale.
    /// إذا ما دخل حتى عنده (نادر): overflow = .balance يقسمه على سطرين (الأسماء)، و .normal يلتف عادي بحجم التصميم (العناوين).
    static func oneLine(_ text: String, weight: OccasionKit.FontWeight, size: CGFloat, maxWidth: CGFloat,
                        minScale: CGFloat, overflow: OccasionWrap) -> OccasionTextLayout {
        let t = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return OccasionTextLayout(lines: [], size: size) }
        let scale = fitScale(t, weight: weight, size: size, maxWidth: maxWidth)
        if scale >= 1 { return OccasionTextLayout(lines: [t], size: size) }
        let minSize = size * minScale
        // أعشار البكسل مثل المتصفح؛ نتأكد بالقياس إن التقريب ما طلّعه أعرض من العمود
        var s = max(minSize, (size * scale * 10).rounded(.down) / 10)
        while s > minSize && width(t, font(weight, s)) > maxWidth + 0.01 { s = max(minSize, s - 0.5) }
        if width(t, font(weight, s)) <= maxWidth + 0.01 { return OccasionTextLayout(lines: [t], size: s) }
        switch overflow {
        case .balance: return make(t, weight: weight, size: minSize, maxWidth: maxWidth, wrap: .balance, maxLines: 2, minScale: 1)
        case .normal: return make(t, weight: weight, size: size, maxWidth: maxWidth, wrap: .normal)
        }
    }
}

/// ظل نص مثل text-shadow في CSS (x، y، blur، لون)
struct OccasionTextShadow {
    var x: CGFloat = 0
    let y: CGFloat
    let blur: CGFloat
    let color: Color

    /// 0 2px 0 rgba(255,255,255,a) — الظل الأبيض تحت الحروف
    static func lift(_ alpha: Double, y: CGFloat = 2) -> OccasionTextShadow {
        OccasionTextShadow(y: y, blur: 0, color: .white.opacity(alpha))
    }
}

/// سطور النص بصناديق CSS: كل سطر ارتفاعه lineHeight × الحجم، وخط الأساس بمكانه في المتصفح
struct OccasionLines: View {
    let layout: OccasionTextLayout
    let weight: OccasionKit.FontWeight
    let lineHeight: CGFloat
    let color: Color
    /// محاذاة السطور (text-align) — الأساس وسط
    let alignment: HorizontalAlignment
    /// text-shadow: كل ظل طبقة لحاله تحت النص (الأول فوق) — مثل المتصفح، بدل shadow() المتسلسلة
    /// اللي تحسب الظل الثاني من النص + الظل الأول فيطلع أغمق
    var shadows: [OccasionTextShadow] = []
    /// حجم الخط اللي ينحسب منه ارتفاع صندوق السطر. السطر الواحد اللي صغر يبقى صندوقه بحجم التصميم،
    /// فما يتحرك شي ثاني في البوست — بس حروف الاسم أصغر
    private let boxSize: CGFloat?

    init(_ text: String, _ weight: OccasionKit.FontWeight, _ size: CGFloat, lineHeight: CGFloat, color: Color,
         maxWidth: CGFloat, wrap: OccasionWrap = .normal, maxLines: Int? = nil, minScale: CGFloat = 0.7,
         alignment: HorizontalAlignment = .center) {
        self.layout = OccasionTextLayout.make(text, weight: weight, size: size, maxWidth: maxWidth,
                                              wrap: wrap, maxLines: maxLines, minScale: minScale)
        self.weight = weight
        self.lineHeight = lineHeight
        self.color = color
        self.alignment = alignment
        self.boxSize = nil
    }

    /// سطر واحد (اسم أو عنوان قصير) يصغر بس إذا ما دخل — انظر OccasionTextLayout.oneLine
    init(oneLine text: String, _ weight: OccasionKit.FontWeight, _ size: CGFloat, lineHeight: CGFloat, color: Color,
         maxWidth: CGFloat, minScale: CGFloat = OccasionNames.minScale, overflow: OccasionWrap = .balance) {
        self.layout = OccasionTextLayout.oneLine(text, weight: weight, size: size, maxWidth: maxWidth,
                                                 minScale: minScale, overflow: overflow)
        self.weight = weight
        self.lineHeight = lineHeight
        self.color = color
        self.alignment = .center
        self.boxSize = size
    }

    /// يضيف ظلال text-shadow بالترتيب المكتوب في CSS
    func textShadow(_ list: OccasionTextShadow...) -> OccasionLines { textShadow(list) }

    func textShadow(_ list: [OccasionTextShadow]) -> OccasionLines {
        var copy = self
        copy.shadows += list
        return copy
    }

    var body: some View {
        ZStack {
            // CSS: الظل الأول يترسم فوق البقية → نرسم من الأخير للأول
            ForEach(Array(shadows.enumerated().reversed()), id: \.offset) { _, sh in
                stack(sh.color)
                    // blur في CSS = ضعف الانحراف المعياري؛ blur(radius:) هنا ≈ 0.9 × الانحراف
                    .blur(radius: sh.blur > 0 ? sh.blur / 2 * 1.1 : 0)
                    .offset(x: sh.x, y: sh.y)
                    .accessibilityHidden(true)
            }
            stack(color)
        }
    }

    private func stack(_ color: Color) -> some View {
        let size = layout.size
        let font = OccasionTextLayout.font(weight, size)
        // المتصفح (Blink) يقرّب ascent و descent لأقرب بكسل، ونصف الفراغ اللي فوق السطر يتقرّب لتحت (floor)
        let ascent = font.ascender.rounded()
        let descent = (-font.descender).rounded()
        let box = lineHeight * (boxSize ?? size)
        let baseline = ((box - (ascent + descent)) / 2).rounded(.down) + ascent
        return VStack(alignment: alignment, spacing: 0) {
            ForEach(Array(layout.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.custom(weight.postScriptName, fixedSize: size))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .fixedSize()
                    // التخطيط LTR، لكن النص عربي — اتجاهه RTL حتى تطلع النقاط والأقواس بمكانها
                    .environment(\.layoutDirection, .rightToLeft)
                    .alignmentGuide(VerticalAlignment.top) { d in d[.firstTextBaseline] - baseline }
                    .frame(height: box, alignment: .top)
            }
        }
    }
}

/// تدرّج مثل linear-gradient(<angle>deg, …) في CSS — يحتاج مقاس الصندوق
struct OccasionCSSGradient: View {
    let angle: Double
    let stops: [Gradient.Stop]

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let h = max(geo.size.height, 1)
            let rad = angle * .pi / 180
            let dx = sin(rad)
            let dy = -cos(rad)
            let len = abs(w * sin(rad)) + abs(h * cos(rad))
            let start = UnitPoint(x: (w / 2 - dx * len / 2) / w, y: (h / 2 - dy * len / 2) / h)
            let end = UnitPoint(x: (w / 2 + dx * len / 2) / w, y: (h / 2 + dy * len / 2) / h)
            LinearGradient(stops: stops, startPoint: start, endPoint: end)
        }
    }
}
