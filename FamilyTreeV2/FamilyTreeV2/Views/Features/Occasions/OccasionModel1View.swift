import SwiftUI
import UIKit

// MARK: - نموذج ١ (صورة دائرية فوق، اسم كبير، كبسولة متدرجة لسطر المناسبة)
//
// من ملفات التصميم (صفحة m1): Wedding, Main, BabyGirl, Recovery, Graduation, Condolence, Solace.
// المنشور (1080×1350) هو التصميم بالضبط؛ الستوري والمربع: الخلفية تكبر لين تغطي (aspect-fill)
// والتخطيط نفسه مضروب في k وبهوامش أمان (M1Layout).

extension OccasionPostView {

    /// خلفية نموذج ١: ملف واحد بمقاس المنشور (أو الستوري للعزاء) — يغطي أي مقاس
    func m1Background(root: Color, file: String) -> some View {
        ZStack {
            root
            if let ui = image("m1/bg/\(file).jpg") {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: canvas.width, height: canvas.height)
                    .clipped()
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    // MARK: التهاني

    var m1HappyPost: some View {
        let L = M1Layout.happy(size)
        let k = L.k
        let th = template.m1Theme ?? .wed
        let contentW = canvas.width - 2 * L.pad.side
        let v = template.verse ?? .wed
        // سطر المناسبة داخل الكبسولة: «لقدوم مولوده [الاسم]» / «لتخرجه من [الجهة]»
        let pillText = ["occasion", "sub"].filter { has($0) }.map { value($0) }.joined(separator: " ")

        let block = VStack(spacing: 2 * k) {
            if has("intro") {
                label(value("intro"), .semibold, 30 * k, lh: 1.4, color: th.intro, width: contentW)
            }
            if has("name") {
                nameLine("name", color: Self.ink)
                    .textShadow(.lift(0.9, y: 2 * k), OccasionTextShadow(y: 12 * k, blur: 24 * k, color: Self.inkShadow.opacity(0.22)))
            }
            if !pillText.isEmpty {
                lines(pillText, .extrabold, 35 * k, lh: 1.4, color: th.pillText, width: contentW - 92 * k, wrap: .balance)
                    .modifier(OccasionPillBox(
                        padTop: 9 * k, padSide: 46 * k, padBottom: 11 * k,
                        fill: AnyView(OccasionCSSGradient(angle: 100, stops: th.pill).clipShape(Capsule())),
                        shadow: th.pillShadow.opacity(th.pillShadowA1), shadowRadius: 14 * k, shadowY: 14 * k,
                        shadow2: th.pillShadow.opacity(th.pillShadowA2), shadow2Radius: 2.5 * k, shadow2Y: 2 * k))
                    .padding(.top, 12 * k)
            }
        }

        var items: [AnyView] = [
            AnyView(verse(v, width: th.verseWidth * k, top: th.verseTop * L.verseTopMul * k, pull: 30 * k)),
            AnyView(OccasionCirclePhoto(k: k, frame: image("m1/frame/\(th.frame).png"),
                                        avatar: template.theme?.avatar ?? .light, photo: photo)),
            AnyView(block),
        ]
        if has("dua") {
            items.append(AnyView(
                lines(value("dua"), .regular, 27 * k, lh: 1.6, color: Color(hex: "#3E4A5A"), width: min(860 * k, contentW))
                    .textShadow(.lift(0.9, y: 1 * k))
            ))
        }
        items.append(AnyView(logo("navy", height: 212 * k).padding(.top, -8 * k).padding(.bottom, -12 * k)))

        return post(root: m1Background(root: th.root, file: th.bg), items: items, pad: L.pad)
    }

    // MARK: إعلان وفاة (Condolence — أبيض على أسود)؛ «مع صورة» = نفسه بصورة دائرية بإطار نموذج ١ فوق الاسم

    var m1DeathPost: some View {
        let L = M1Layout.death(size)
        let k = L.k
        let P = OccasionDeathPalette.self
        let contentW = canvas.width - 2 * L.pad.side
        // سطور القرابة داخل الكبسولة الوحدة — تطول بس (مع صورة: سطر أو سطرين، بدون: الزوج والأبناء والإخوان)
        let rels = template.kind == .death ? relationKeys : ["rel1", "rel2", "rel3"].filter { has($0) }
        // الصورة أصغر شوي من التهاني حتى تدخل مع القرابة والأماكن والدعاء (الستوري فيه مكان)
        let photoK = k * (size == .story ? 1 : 0.8)

        let block = VStack(spacing: 4 * k) {
            if has("lead") { label(value("lead"), .semibold, 34 * k, lh: 1.4, color: .white, width: contentW) }
            if has("title") { label(value("title"), .extrabold, 42 * k, lh: 1.35, color: P.soft, width: contentW) }
            if has("name") {
                nameLine("name", color: .white)
                    .textShadow(OccasionTextShadow(y: 10 * k, blur: 26 * k, color: .black.opacity(0.65)))
            }
        }

        var items: [AnyView] = [
            AnyView(deathVerses(lead: 469 / OccasionVerse.sabrLead.width * k, main: 637 / OccasionVerse.inna.width * k,
                                leadPull: 34 * k, mainPull: 30 * k)),
        ]
        if template.hasPhoto(model) {
            items.append(AnyView(OccasionCirclePhoto(k: photoK, frame: image("m1/frame/\(OccasionM1Theme.deathFrame).png"),
                                                     avatar: .dark, photo: photo)))
        }
        items.append(AnyView(block))
        if !rels.isEmpty {
            items.append(AnyView(
                VStack(spacing: 0) {
                    ForEach(rels, id: \.self) { key in
                        relationLine(key, size: 30 * k, width: contentW - 94 * k)
                    }
                }
                    .modifier(OccasionPillBox(
                        padTop: 12 * k, padSide: 46 * k, padBottom: 14 * k,
                        fill: AnyView(Capsule().fill(Color.white.opacity(0.10))),
                        border: Color.white.opacity(0.28),
                        shadow: .black.opacity(0.45), shadowRadius: 15 * k, shadowY: 16 * k))
            ))
        }
        if has("menPlace") || has("womenPlace") {
            items.append(AnyView(venues(scale: k, accent: .white, line: Color.white.opacity(0.75))))
        }
        if has("dua1") || has("dua2") { items.append(AnyView(deathDua(size: 27 * k, lh: 1.65, width: contentW))) }
        items.append(AnyView(logo("white", height: 172 * k).padding(.top, -8 * k).padding(.bottom, -12 * k)))

        return post(root: m1Background(root: P.root, file: "death"), items: items, pad: L.pad)
    }

    // MARK: مشاركة عزاء (Solace — التصميم ستوري 1080×1920)

    var m1SolacePost: some View {
        let L = M1Layout.solace(size)
        let k = L.k
        let ink = Color(hex: "#20262D")
        let muted = Color(hex: "#4A5560")
        let contentW = canvas.width - 2 * L.pad.side

        var items: [AnyView] = [
            AnyView(verse(.sabr, width: 952 * k, pull: 30 * k)),
            AnyView(lines("مشـاركة عـزاء", .extrabold, 96 * k, lh: 1.25, color: ink, width: contentW)
                .textShadow(OccasionText.lightShadow(k))),
            AnyView(
                VStack(spacing: 8 * k) {
                    if has("from") {
                        label(value("from"), .semibold, 48 * k, lh: 1.35, color: ink, width: contentW).textShadow(OccasionText.lightShadow(k))
                    }
                    lines("بأحر التعازي وأصدق المواساة إلى", .regular, 34 * k, lh: 1.4, color: muted, width: contentW)
                }
            ),
        ]
        if has("to") {
            items.append(AnyView(nameLine("to", color: ink).textShadow(OccasionText.lightShadow(k))))
        }
        items.append(AnyView(
            VStack(spacing: 6 * k) {
                if has("lead") { label(value("lead"), .regular, 34 * k, lh: 1.4, color: muted, width: contentW) }
                if has("name") {
                    nameLine("name", color: ink)
                        .textShadow(OccasionText.lightShadow(k))
                }
            }
        ))
        if has("dua") {
            items.append(AnyView(
                lines(value("dua"), .regular, 31 * k, lh: 1.75, color: Color(hex: "#55657A"), width: min(860 * k, contentW))
            ))
        }
        items.append(AnyView(logo("navy", height: 260 * k).padding(.top, -10 * k).padding(.bottom, -14 * k)))

        return post(root: m1Background(root: Color(hex: "#F7F8F9"), file: "solace"), items: items, pad: L.pad)
    }
}

/// إطار دائري 336×336 والصورة 232×232 داخله عند (52، 52) — مضروب في k
struct OccasionCirclePhoto: View {
    let k: CGFloat
    let frame: UIImage?
    let avatar: OccasionAvatar
    let photo: OccasionPhoto

    var body: some View {
        let box = 336 * k
        let d = 232 * k
        return ZStack(alignment: .topLeading) {
            if let frame {
                Image(uiImage: frame).resizable().frame(width: box, height: box)
            }
            OccasionPhotoFill(photo: photo, avatar: avatar, width: d, height: d)
                .clipShape(Circle())
                .offset(x: 52 * k, y: 52 * k)
        }
        .frame(width: box, height: box, alignment: .topLeading)
    }
}
