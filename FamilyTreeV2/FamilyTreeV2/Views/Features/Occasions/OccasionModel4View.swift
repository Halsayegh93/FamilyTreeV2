import SwiftUI
import UIKit

// MARK: - نموذج ٤ — تصميمه كله من السيرفر (`occasion_designer.models.m4` — OccasionDesignerConfig.swift)
//
// "layouts": المفتاح رقم الإعلان ("wedding") أو نوعه ("happy" · "death" · "deathText" · "solace") أو "default".
// كل تخطيط: { "background": "#FCF7EC", "layers": [ … ] } — ويقدر يكون لكل مقاس تخطيطه:
// { "post": {…}, "story": {…}, "square": {…} } (المقاس الغائب يأخذ تخطيط المنشور ويتمدّد طوله بالنسبة).
// الإحداثيات بنقاط المنشور ١٠٨٠×١٣٥٠ (x, y, w, h). الطبقات بالترتيب (الأولى تحت):
//   { "type": "image", "src": "m4/bg.jpg" أو رابط كامل https://…, "x": 0, "y": 0, "w": 1080, "h": 1350, "fit": "fill|fit" }
//   { "type": "photo", "x": 340, "y": 160, "w": 400, "h": 400, "shape": "circle|rounded|rect", "radius": 40,
//     "border": "#C9A24A", "borderWidth": 8 }                ← صورة المستخدم (تُتجاهل في «بدون صورة»)
//   { "type": "text", "text": "{intro}", "x": 90, "y": 620, "w": 900, "size": 44, "weight": "regular|semibold|extrabold",
//     "color": "#8A6A22", "align": "center|right|left", "lines": 2 }   ← {name} {occasion} {dua} … من حقول الإعلان
// نص كله فاضي بعد التعويض ما ينرسم. الصور تنزل وتنخزن مثل بقية الملفات (OccasionKit) — غيّر الرابط (?v=2) لتحديث صورة.

struct OccasionModel4Spec {
    struct Layer {
        enum Kind { case image, photo, text }
        let kind: Kind
        let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
        let src: String?
        let fill: Bool
        let shape: String
        let radius: CGFloat
        let border: Color?
        let borderWidth: CGFloat
        let text: String
        let size: CGFloat
        let weight: OccasionKit.FontWeight
        let color: Color
        let align: TextAlignment
        let lines: Int?

        init?(_ d: [String: Any]) {
            func num(_ k: String, _ def: CGFloat = 0) -> CGFloat { (d[k] as? NSNumber).map { CGFloat($0.doubleValue) } ?? def }
            switch d["type"] as? String {
            case "image": kind = .image
            case "photo": kind = .photo
            case "text": kind = .text
            default: return nil
            }
            x = num("x"); y = num("y"); w = num("w", 1080); h = num("h")
            src = (d["src"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            if kind == .image && src == nil { return nil }
            fill = (d["fit"] as? String) != "fit"
            shape = d["shape"] as? String ?? "rect"
            radius = num("radius")
            border = (d["border"] as? String).map { Color(hex: $0) }
            borderWidth = num("borderWidth")
            text = d["text"] as? String ?? ""
            size = num("size", 40)
            switch d["weight"] as? String {
            case "semibold": weight = .semibold
            case "extrabold", "bold": weight = .extrabold
            default: weight = .regular
            }
            color = Color(hex: d["color"] as? String ?? "#172536")
            switch d["align"] as? String {
            case "right": align = .trailing
            case "left": align = .leading
            default: align = .center
            }
            lines = (d["lines"] as? NSNumber)?.intValue
        }
    }

    struct Layout {
        let background: Color
        let layers: [Layer]
        /// تمديد الطول (المقاس اللي ما له تخطيط خاص)
        let yScale: CGFloat

        var imagePaths: [String] { layers.compactMap { $0.kind == .image ? $0.src : nil } }
    }

    let title: String?
    let subtitle: String?
    private let layouts: [String: Any]

    init?(_ entry: [String: Any]) {
        guard let layouts = entry["layouts"] as? [String: Any], !layouts.isEmpty else { return nil }
        self.layouts = layouts
        title = entry["title"] as? String
        subtitle = entry["subtitle"] as? String
    }

    /// تخطيط الإعلان بالمقاس — nil = ما له تصميم في نموذج ٤
    func layout(for t: OccasionTemplate, size: OccasionSize) -> Layout? {
        let raw = (layouts[t.id] ?? layouts[t.kind.configKey] ?? layouts["default"]) as? [String: Any]
        guard let raw else { return nil }
        if let own = raw[size.rawValue] as? [String: Any] { return Self.parse(own, yScale: 1) }
        if let post = raw["post"] as? [String: Any] {
            return Self.parse(post, yScale: size.canvas.height / OccasionSize.post.canvas.height)
        }
        return Self.parse(raw, yScale: size.canvas.height / OccasionSize.post.canvas.height)
    }

    func supports(_ t: OccasionTemplate) -> Bool { layout(for: t, size: .post) != nil }

    private static func parse(_ d: [String: Any], yScale: CGFloat) -> Layout? {
        guard let layers = d["layers"] as? [[String: Any]] else { return nil }
        let parsed = layers.compactMap(Layer.init)
        guard !parsed.isEmpty else { return nil }
        return Layout(background: Color(hex: d["background"] as? String ?? "#FFFFFF"), layers: parsed, yScale: yScale)
    }
}

extension OccasionKind {
    /// اسم النوع في إعداد السيرفر
    var configKey: String {
        switch self {
        case .happy: return "happy"
        case .death: return "death"
        case .deathText: return "deathText"
        case .solace: return "solace"
        }
    }
}

/// رسم نموذج ٤ بمقاسه الحقيقي (نقطة = بكسل) من تخطيط السيرفر
struct OccasionModel4View: View {
    let layout: OccasionModel4Spec.Layout
    let values: [String: String]
    let photo: OccasionPhoto
    let showsPhoto: Bool
    let kit: OccasionKit
    let canvas: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            layout.background
            ForEach(Array(layout.layers.enumerated()), id: \.offset) { _, layer in
                layerView(layer)
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func layerView(_ l: OccasionModel4Spec.Layer) -> some View {
        let y = l.y * layout.yScale
        switch l.kind {
        case .image:
            if let src = l.src, let ui = kit.image(src) {
                let h = l.h > 0 ? l.h * layout.yScale : l.w * ui.size.height / max(ui.size.width, 1)
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: l.fill ? .fill : .fit)
                    .frame(width: l.w, height: h)
                    .clipped()
                    .offset(x: l.x, y: y)
            }
        case .photo:
            if showsPhoto {
                let h = l.h > 0 ? l.h : l.w
                photoFill(w: l.w, h: h)
                    .clipShape(shape(l))
                    .overlay(shape(l).stroke(l.border ?? .clear, lineWidth: l.borderWidth))
                    .offset(x: l.x, y: y)
            }
        case .text:
            let s = Self.fill(l.text, values)
            if !s.isEmpty {
                Text(s)
                    .font(.custom(l.weight.postScriptName, size: l.size))
                    .foregroundColor(l.color)
                    .multilineTextAlignment(l.align)
                    .lineLimit(l.lines)
                    .minimumScaleFactor(0.5)
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(width: l.w, height: l.h > 0 ? l.h * layout.yScale : nil, alignment: frameAlignment(l.align))
                    .offset(x: l.x, y: y)
            }
        }
    }

    private func frameAlignment(_ a: TextAlignment) -> Alignment {
        switch a {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }

    private func shape(_ l: OccasionModel4Spec.Layer) -> AnyShape {
        switch l.shape {
        case "circle": return AnyShape(Circle())
        case "rounded": return AnyShape(RoundedRectangle(cornerRadius: l.radius, style: .continuous))
        default: return AnyShape(Rectangle())
        }
    }

    @ViewBuilder
    private func photoFill(w: CGFloat, h: CGFloat) -> some View {
        if let ui = photo.image, ui.size.width > 0, ui.size.height > 0 {
            let s = max(w / ui.size.width, h / ui.size.height) * max(photo.zoom, 1)
            let dw = ui.size.width * s
            let dh = ui.size.height * s
            ZStack(alignment: .topLeading) {
                Color.clear
                Image(uiImage: ui)
                    .resizable()
                    .frame(width: dw, height: dh)
                    .offset(x: (w - dw) * photo.x / 100, y: (h - dh) * photo.y / 100)
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .grayscale(photo.gray ? 1 : 0)
        } else {
            OccasionAvatarView(style: .light)
                .frame(width: w, height: h)
        }
    }

    /// «{name} {occasion}» ← قيم حقول الإعلان (المفتاح الغائب = فاضي)
    static func fill(_ template: String, _ values: [String: String]) -> String {
        var out = template
        while let open = out.range(of: "{"), let close = out.range(of: "}", range: open.upperBound..<out.endIndex) {
            let key = String(out[open.upperBound..<close.lowerBound])
            out.replaceSubrange(open.lowerBound..<close.upperBound, with: values[key] ?? "")
        }
        return out.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(whereSeparator: { $0 == " " }).joined(separator: " ") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
