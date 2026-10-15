import SwiftUI
import UIKit

// MARK: - رسم بوست المناسبة — نموذج ١ (صورة دائرية فوق، اسم كبير، كبسولة متدرجة)
//
// نفس OccasionPost.tsx في الموقع (M1HappyPost، M1HappyNoPhotoPost، M1DeathPhotoPost، M1DeathTextPost، M1SolacePost).
// المنشور (1080×1350) هو التصميم بالضبط؛ الستوري والمربع: الخلفية تكبر لين تغطي، والتخطيط نفسه مضروب في k
// وبهوامش أمان (OccasionM1Layout). الملفات من occasion-kit/m1 — تنزل من الموقع مثل باقي ملفات التصميم.

extension OccasionPostView {
    private static let ink = Color(hex: "#172536")

    // MARK: التهاني مع صورة (Wedding/Main/BabyGirl/Recovery/Graduation)

    var m1HappyPost: some View {
        let L = OccasionM1Layout.happy(size)
        let k = L.k
        let th = template.m1 ?? .wed
        let contentW = canvas.width - 2 * L.pad.side
        let v = template.verse ?? .wed
        var items: [AnyView] = [
            AnyView(verse(v, scale: th.verseWidth * k / v.width, top: th.verseTop * L.verseTopMul * k, pull: 30 * k)),
            AnyView(OccasionCirclePhoto(box: 336 * k, frame: image("m1/frame/\(th.frame).png"),
                                        avatar: template.theme?.avatar ?? .light, photo: photo)),
            AnyView(m1HappyText(th, k: k, contentW: contentW, big: false)),
        ]
        if has("dua") {
            items.append(AnyView(
                text(value("dua"), .regular, 27 * k, color: Color(hex: "#3E4A5A"), lineHeight: 1.6)
                    .shadow(color: .white.opacity(0.9), radius: 0, x: 0, y: 1 * k)
                    .frame(maxWidth: min(860 * k, contentW))
            ))
        }
        items.append(AnyView(m1Logo("navy", height: 212 * k).padding(.top, -8 * k).padding(.bottom, -12 * k)))
        return m1Canvas(root: th.root, bg: th.bg, pad: L.pad, items: items)
    }

    // MARK: التهاني بدون صورة (Wedding-NP …): مكان الصورة يروح للآية (بسطرين لما تتوفر)، والاسم والكبسولة والدعاء أكبر

    var m1HappyNoPhotoPost: some View {
        let L = OccasionM1Layout.happyNoPhoto(size)
        let k = L.k
        let th = template.m1 ?? .wed
        let contentW = canvas.width - 2 * L.pad.side
        let np = template.noPhoto
        let v = np?.verse ?? template.verse ?? .wed
        let vWidth = np?.m1Width ?? th.verseWidth
        var items: [AnyView] = [
            AnyView(verse(v, scale: vWidth * k / v.width, top: (np?.m1Top ?? 0) * L.verseTopMul * k, pull: 30 * k)),
            AnyView(m1HappyText(th, k: k, contentW: contentW, big: true)),
        ]
        if has("dua") {
            let duaW = min(880 * k, contentW)
            items.append(AnyView(
                text(value("dua"), .regular, 30 * k, color: Color(hex: "#3E4A5A"), lineHeight: 1.65, balanceWidth: duaW)
                    .shadow(color: .white.opacity(0.9), radius: 0, x: 0, y: 1 * k)
                    .frame(maxWidth: duaW)
            ))
        }
        items.append(AnyView(m1Logo("navy", height: 212 * k).padding(.top, -8 * k).padding(.bottom, -12 * k)))
        return m1Canvas(root: th.root, bg: th.bg, pad: L.pad, items: items)
    }

    /// «تهنئة وتبريك للأخ العزيز» ← الاسم ← الكبسولة (المناسبة + اسم المولود أو الجهة).
    /// big = النسخة بدون صورة (المقدمة ٣٤، الاسم ٩٢، الكبسولة ٤٠)
    private func m1HappyText(_ th: OccasionM1Theme, k: CGFloat, contentW: CGFloat, big: Bool) -> some View {
        // الاسم: ٩٢ بدون صورة و٧٨ مع صورة (nameSlots)
        let introSize: CGFloat = big ? 34 : 30
        let pillSize: CGFloat = big ? 40 : 35
        let padH: CGFloat = (big ? 56 : 46) * k
        let padTop: CGFloat = (big ? 11 : 9) * k
        let padBottom: CGFloat = (big ? 13 : 11) * k
        let pillGap: CGFloat = (big ? 16 : 12) * k
        let pillText = [value("occasion"), value("sub")]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        return VStack(spacing: (big ? 4 : 2) * k) {
            if has("intro") {
                text(value("intro"), .semibold, introSize * k, color: th.intro, lineHeight: 1.4, balanceWidth: contentW)
            }
            if has("name") {
                nameLine("name", color: Self.ink)
                    .shadow(color: .white.opacity(0.9), radius: 0, x: 0, y: 2 * k)
                    .shadow(color: Color(red: 23 / 255, green: 37 / 255, blue: 54 / 255).opacity(0.22), radius: 12 * k, x: 0, y: 12 * k)
            }
            if !pillText.isEmpty {
                text(pillText, .extrabold, pillSize * k, color: th.pillText, lineHeight: 1.4, balanceWidth: contentW - 2 * padH)
                    .padding(.horizontal, padH)
                    .padding(.top, padTop)
                    .padding(.bottom, padBottom)
                    .background(
                        OccasionCSSGradient(angle: 100, stops: th.pill)
                            .clipShape(Capsule())
                            .shadow(color: th.pillShadow.opacity(th.pillA1), radius: 14 * k, x: 0, y: 14 * k)
                            .shadow(color: th.pillShadow.opacity(th.pillA2), radius: 2.5 * k, x: 0, y: 2 * k)
                    )
                    .frame(maxWidth: contentW)
                    .padding(.top, pillGap)
            }
        }
    }

    // MARK: إعلان وفاة — مع صورة (Condolence-Photo): الصورة بالحلقة البيضاء بين الآية والاسم

    var m1DeathPhotoPost: some View {
        let L = OccasionM1Layout.deathPhoto(size)
        let k = L.k
        let contentW = canvas.width - 2 * L.pad.side
        var items: [AnyView] = [
            AnyView(deathVerses(lead: 391 * k / OccasionVerse.sabrLead.width, main: 541 * k / OccasionVerse.inna.width,
                                leadPull: 30 * k, mainPull: 28 * k)),
            AnyView(OccasionCirclePhoto(box: 286 * k, frame: image("m1/frame/white.png"), avatar: .dark, photo: photo)),
            AnyView(m1DeathName(k: k)),
        ]
        if has("relation") {
            items.append(AnyView(
                Group {
                    if isNameLine("relation") {
                        // اسم شخص واحد: سطر واحد بصيغة تدخل (والكبسولة على قده)
                        nameLine("relation", color: .white).fixedSize()
                    } else {
                        text(value("relation"), .semibold, 26 * k, color: .white, lineHeight: 1.4, balanceWidth: contentW - 82 * k)
                    }
                }
                .padding(.horizontal, 40 * k)
                .padding(.top, 10 * k)
                .padding(.bottom, 12 * k)
                .background(Capsule().fill(Color.white.opacity(0.10)))
                .overlay(Capsule().stroke(Color.white.opacity(0.28), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 15 * k, x: 0, y: 16 * k)
                .frame(maxWidth: contentW)
            ))
        }
        if has("menPlace") || has("womenPlace") {
            items.append(AnyView(venues(scale: 0.9 * k, accent: .white, line: Color.white.opacity(0.75))))
        }
        if has("dua1") || has("dua2") { items.append(AnyView(deathDua(size: 24 * k))) }
        items.append(AnyView(m1Logo("white", height: 134 * k).padding(.top, -6 * k).padding(.bottom, -8 * k)))
        return m1Canvas(root: OccasionDeathPalette.root, bg: "death", pad: L.pad, items: items)
    }

    // MARK: إعلان وفاة — بدون صورة (Condolence) بالتفاصيل كاملة: القرابة داخل بطاقة، ثم التشييع والعزاء

    var m1DeathTextPost: some View {
        let L = OccasionM1Layout.deathText(size)
        let k = L.k
        let contentW = canvas.width - 2 * L.pad.side
        let rels = ["rel1", "rel2", "rel3"].filter { has($0) }
        let relColor = Color(hex: "#E6E9EC")
        var items: [AnyView] = [
            AnyView(deathVerses(lead: 430 * k / OccasionVerse.sabrLead.width, main: 580 * k / OccasionVerse.inna.width,
                                leadPull: 30 * k, mainPull: 28 * k)),
            AnyView(m1DeathName(k: k)),
        ]
        if !rels.isEmpty {
            // سطر واحد = كبسولة؛ أكثر = بطاقة بزوايا دائرية (نفس الكبسولة)
            let card = RoundedRectangle(cornerRadius: 36 * k)
            items.append(AnyView(
                VStack(spacing: 0) {
                    ForEach(rels, id: \.self) { key in
                        // اسم شخص واحد: سطر واحد بصيغة تدخل؛ القوائم تلتف
                        if isNameLine(key) {
                            nameLine(key, color: relColor).fixedSize()
                        } else {
                            text(value(key), .regular, 26 * k, color: relColor, lineHeight: 1.55, balanceWidth: contentW - 92 * k)
                        }
                    }
                }
                .padding(.horizontal, 44 * k)
                .padding(.top, 12 * k)
                .padding(.bottom, 14 * k)
                .background(card.fill(Color.white.opacity(0.10)))
                .overlay(card.stroke(Color.white.opacity(0.28), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 15 * k, x: 0, y: 16 * k)
                .frame(maxWidth: contentW)
            ))
        }
        if has("funeral") || has("condolence") {
            items.append(AnyView(
                VStack(spacing: 4 * k) {
                    if has("funeral") {
                        text(value("funeral"), .semibold, 29 * k, color: .white, lineHeight: 1.45, balanceWidth: contentW)
                    }
                    if has("condolence") {
                        text(value("condolence"), .semibold, 27 * k, color: OccasionDeathPalette.soft, lineHeight: 1.45, balanceWidth: contentW)
                    }
                }
            ))
        }
        if has("menPlace") || has("womenPlace") {
            items.append(AnyView(venues(scale: 0.9 * k, accent: .white, line: Color.white.opacity(0.75))))
        }
        if has("dua1") || has("dua2") { items.append(AnyView(deathDua(size: 25 * k))) }
        items.append(AnyView(m1Logo("white", height: 150 * k).padding(.top, -6 * k).padding(.bottom, -8 * k)))
        return m1Canvas(root: OccasionDeathPalette.root, bg: "death", pad: L.pad, items: items)
    }

    /// «انتقل إلى رحمة الله تعالى» ← «المرحوم الحاج» ← الاسم (أبيض على أسود؛ حجم الاسم من nameSlots)
    private func m1DeathName(k: CGFloat) -> some View {
        VStack(spacing: 2 * k) {
            if has("lead") {
                text(value("lead"), .semibold, 30 * k, color: .white, lineHeight: 1.4)
            }
            if has("title") {
                text(value("title"), .extrabold, 36 * k, color: OccasionDeathPalette.soft, lineHeight: 1.35)
            }
            if has("name") {
                nameLine("name", color: .white)
                    .shadow(color: .black.opacity(0.65), radius: 13 * k, x: 0, y: 10 * k)
            }
        }
    }

    // MARK: مشاركة عزاء (Solace — التصميم ستوري 1080×1920)

    var m1SolacePost: some View {
        let L = OccasionM1Layout.solace(size)
        let k = L.k
        let contentW = canvas.width - 2 * L.pad.side
        let ink = Color(hex: "#20262D")
        let muted = Color(hex: "#4A5560")
        let shadow = OccasionLightShadow(k: k)
        var items: [AnyView] = [
            AnyView(verse(template.verse ?? .sabr, scale: k, pull: 30 * k)),
            AnyView(text("مشـاركة عـزاء", .extrabold, 96 * k, color: ink, lineHeight: 1.25).modifier(shadow)),
            AnyView(
                VStack(spacing: 8 * k) {
                    if has("from") {
                        text(value("from"), .semibold, 48 * k, color: ink, lineHeight: 1.35).modifier(shadow)
                    }
                    text("بأحر التعازي وأصدق المواساة إلى", .regular, 34 * k, color: muted, lineHeight: 1.4)
                }
            ),
        ]
        if has("to") {
            items.append(AnyView(nameLine("to", color: ink).modifier(shadow)))
        }
        items.append(AnyView(
            VStack(spacing: 6 * k) {
                if has("lead") {
                    text(value("lead"), .regular, 34 * k, color: muted, lineHeight: 1.4)
                }
                if has("name") {
                    nameLine("name", color: ink).modifier(shadow)
                }
            }
        ))
        if has("dua") {
            let duaW = min(860 * k, contentW)
            items.append(AnyView(
                text(value("dua"), .regular, 31 * k, color: Color(hex: "#55657A"), lineHeight: 1.75)
                    .frame(maxWidth: duaW)
            ))
        }
        items.append(AnyView(m1Logo("navy", height: 260 * k).padding(.top, -10 * k).padding(.bottom, -14 * k)))
        return m1Canvas(root: Color(hex: "#F7F8F9"), bg: "solace", pad: L.pad, items: items)
    }

    // MARK: قطع نموذج ١

    /// الخلفية: صورة وحدة بمقاس المنشور (أو الستوري للعزاء) تغطي أي مقاس — مثل object-fit: cover
    private func m1Background(root: Color, bg: String) -> some View {
        ZStack {
            root
            if let ui = image("m1/bg/\(bg).jpg") {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: canvas.width, height: canvas.height)
                    .clipped()
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    /// العناصر موزّعة (space-between) داخل هوامش التخطيط فوق الخلفية
    private func m1Canvas(root: Color, bg: String, pad: OccasionInsets, items: [AnyView]) -> some View {
        ZStack(alignment: .top) {
            m1Background(root: root, bg: bg)
            OccasionSpacedColumn(items: items)
                .padding(.top, pad.top)
                .padding(.horizontal, pad.side)
                .padding(.bottom, pad.bottom)
                .frame(width: canvas.width, height: canvas.height)
        }
    }

    /// الشعار وحده (نموذج ١ — بدون الخطين)
    private func m1Logo(_ name: String, height lh: CGFloat) -> some View {
        Group {
            if let ui = image("logo/\(name).png") {
                Image(uiImage: ui)
                    .resizable()
                    .frame(width: lh * ui.size.width / max(ui.size.height, 1), height: lh)
                    .accessibilityLabel(L10n.t("شعار عائلة المحمدعلي", "Al-Mohammad Ali family logo"))
            } else {
                Color.clear.frame(width: lh * 900 / 831, height: lh)
            }
        }
    }
}

// MARK: - قطع نموذج ١

/// وحدة الصورة (نموذج ١): إطار دائري بعرض box والصورة داخله بنسبة 232 من 336 (عند 52) — نفس نسبة كل إطارات نموذج ١
/// (التهاني box = 336، إعلان الوفاة بالحلقة البيضاء box = 286).
/// الإطار قرص معتم (مو حلقة مفرّغة) — فالصورة تنرسم **فوقه** مثل الموقع.
struct OccasionCirclePhoto: View {
    let box: CGFloat
    let frame: UIImage?
    let avatar: OccasionAvatar
    let photo: OccasionPhoto

    var body: some View {
        let d = box * 232 / 336
        let off = box * 52 / 336
        return ZStack(alignment: .topLeading) {
            if let frame {
                Image(uiImage: frame).resizable().frame(width: box, height: box)
            }
            photoContent(d)
                .frame(width: d, height: d)
                .background(Color(hex: "#E9E4DA"))
                .clipShape(Circle())
                .offset(x: off, y: off)
        }
        .frame(width: box, height: box, alignment: .topLeading)
    }

    /// الصورة تغطي الدائرة مع التكبير والموضع (مثل object-fit: cover)، أو ظل شخص لو ما فيه صورة
    @ViewBuilder
    private func photoContent(_ d: CGFloat) -> some View {
        if let ui = photo.image, ui.size.width > 0, ui.size.height > 0 {
            let s = max(d / ui.size.width, d / ui.size.height) * max(photo.zoom, 1)
            let dw = ui.size.width * s
            let dh = ui.size.height * s
            ZStack(alignment: .topLeading) {
                Color.clear
                Image(uiImage: ui)
                    .resizable()
                    .frame(width: dw, height: dh)
                    .offset(x: (d - dw) * photo.x / 100, y: (d - dh) * photo.y / 100)
            }
            .frame(width: d, height: d, alignment: .topLeading)
            .grayscale(photo.gray ? 1 : 0)
        } else {
            OccasionAvatarView(style: avatar)
        }
    }
}

/// تدرّج مثل linear-gradient(<angle>deg, …) في CSS — نقطتا البداية والنهاية تنحسب من مقاس الشكل
/// (الزاوية من فوق مع عقارب الساعة: 90 = لليمين)
struct OccasionCSSGradient: View {
    let angle: Double
    let stops: [Gradient.Stop]

    var body: some View {
        GeometryReader { geo in
            let p = points(geo.size)
            LinearGradient(stops: stops, startPoint: p.start, endPoint: p.end)
        }
    }

    private func points(_ size: CGSize) -> (start: UnitPoint, end: UnitPoint) {
        let w = max(size.width, 1)
        let h = max(size.height, 1)
        let rad = angle * .pi / 180
        let dx = CGFloat(sin(rad))
        let dy = CGFloat(-cos(rad))
        // خط التدرّج يمر بالمركز وطوله مثل CSS (يلمس الزاويتين البعيدتين)
        let half = (abs(w * dx) + abs(h * dy)) / 2
        let start = UnitPoint(x: (w / 2 - dx * half) / w, y: (h / 2 - dy * half) / h)
        let end = UnitPoint(x: (w / 2 + dx * half) / w, y: (h / 2 + dy * half) / h)
        return (start, end)
    }
}
