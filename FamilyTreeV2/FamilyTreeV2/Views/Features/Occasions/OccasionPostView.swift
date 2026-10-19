import SwiftUI
import UIKit

// MARK: - رسم بوست المناسبة بمقاسه الحقيقي (نقطة = بكسل) — نموذج ٢، ونموذج ١ في OccasionModel1View.swift،
// ونموذج ٣ (المعتمد) في OccasionModel3View.swift
//
// نفس تخطيط الموقع (familytree-web/src/components/occasions/OccasionPost.tsx)، وكل قالب مع صورة وبدون صورة.
// الرسم بإحداثيات ثابتة من اليسار لليمين (LTR) حتى يطلع نفس الشكل مهما كانت لغة التطبيق؛
// النص العربي ينرسم صح تلقائياً، والصورة دائماً يسار والنص يمين مثل التصميم المعتمد.

struct OccasionPhoto: Equatable {
    var image: UIImage?
    var zoom: CGFloat = 1
    /// موضع الصورة داخل الإطار بالنسبة المئوية (مثل object-position)
    var x: CGFloat = 50
    var y: CGFloat = 40
    var gray: Bool = false
}

struct OccasionPostView: View {
    let template: OccasionTemplate
    let size: OccasionSize
    let values: [String: String]
    let photo: OccasionPhoto
    let kit: OccasionKit
    /// يتغيّر لما تتوفّر ملفات جديدة — يضمن تحديث الرسم
    let revision: Int
    /// نموذج ١ أو ٢ أو ٣ (القالب اللي ما له نموذج ١ يرجع لنموذج ٢)
    var model: OccasionModel = .m2
    /// التهاني و«إعلان عزاء»: «مع صورة» أو «بدون صورة» (الإعلان يوصل هنا بقالب نسخته — OccasionTemplate.layout)
    var withPhoto: Bool = true
    /// «إعلان عزاء» و«مشاركة عزاء»: «فحمي وفضي» أو «الأصلية» (باقي القوالب ما يأثّر فيها)
    var palette: OccasionPalette = .standard

    var canvas: CGSize { size.canvas }

    /// يرسم بـ«فحمي وفضي»؟
    var silver: Bool { palette == .silver && template.hasPalette }

    var body: some View {
        content
            .frame(width: canvas.width, height: canvas.height)
            .clipped()
            .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder
    private var content: some View {
        if template.effectiveModel(model) == .m3 {
            m3Post
        } else if template.effectiveModel(model) == .m1 {
            switch template.kind {
            case .happy:
                if template.showsPhoto(withPhoto) { m1HappyPost } else { m1HappyNoPhotoPost }
            case .death: m1DeathPhotoPost
            case .deathText: m1DeathTextPost
            case .solace: m1SolacePost
            }
        } else {
            switch template.kind {
            case .happy:
                if template.showsPhoto(withPhoto) { happyPost } else { happyNoPhotoPost }
            case .death: deathPost
            case .deathText: deathTextPost
            case .solace: solacePost
            }
        }
    }

    // MARK: أدوات

    /// النص النهائي للبوست: بدون تشكيل (الخط ما يضبطه) و«المحمدعلي» متصلة — نفس postText في الموقع
    func value(_ key: String) -> String { OccasionText.postText(values[key] ?? "") }

    func has(_ key: String) -> Bool {
        !value(key).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func image(_ path: String) -> UIImage? { kit.image(path) }

    func canvasBackground(root: Color, bg: String) -> some View {
        postBackground(root: root, path: "bg/\(bg)-\(size.rawValue).jpg", fill: false)
    }

    /// خلفية البوست (path = الخلفية الأصلية؛ fill = نموذج ١: صورة وحدة تغطي أي مقاس مثل object-fit: cover).
    /// «فحمي وفضي»: الخلفية الفحمية/الفاتحة من الموقع (نفس المسار + «-silver») فوق لون الأرضية؛ وقبل ما تنزل: الإعلان
    /// على الغرافيت (silverGround)، ومشاركة العزاء الخلفية الأصلية رمادية بلون البطاقة الفاتحة
    @ViewBuilder
    func postBackground(root: Color, path: String, fill: Bool) -> some View {
        let dark = template.kind != .solace
        if silver, image(OccasionSilver.path(path)) == nil, dark {
            silverGround(path, fill: fill)
        } else {
            let silverFile = silver ? image(OccasionSilver.path(path)) : nil
            let tint: Color? = silver && silverFile == nil ? OccasionSilver.card : nil
            ZStack {
                silver ? (dark ? OccasionSilver.groundBottom : OccasionSilver.card) : root
                if let ui = silverFile ?? image(path) {
                    bgImage(ui, fill: fill)
                        .grayscale(tint == nil ? 0 : 1)
                        .colorMultiply(tint ?? .white)
                }
            }
            .frame(width: canvas.width, height: canvas.height)
        }
    }

    @ViewBuilder
    private func bgImage(_ ui: UIImage, fill: Bool) -> some View {
        if fill {
            Image(uiImage: ui).resizable().scaledToFill().frame(width: canvas.width, height: canvas.height).clipped()
        } else {
            Image(uiImage: ui).resizable().frame(width: canvas.width, height: canvas.height)
        }
    }

    /// بديل الأرضية الفحمية لين ينزل ملفها: غرافيت متدرّج من فوق لتحت، وملمس الخلفية الأصلية الداكنة فوقه (بعد ما ينشال
    /// سوادها: brightness ثم screen) — فيبقى الحرير والعلامة المائية بنفس مكانها وأساس الأرضية الغرافيت نفسه
    private func silverGround(_ path: String, fill: Bool) -> some View {
        ZStack {
            LinearGradient(colors: [OccasionSilver.groundTop, OccasionSilver.groundBottom], startPoint: .top, endPoint: .bottom)
            if let ui = image(path) {
                bgImage(ui, fill: fill)
                    .grayscale(1)
                    .brightness(-0.1)
                    .blendMode(.screen)
            }
        }
        .compositingGroup()
        .frame(width: canvas.width, height: canvas.height)
    }

    /// ملف له نسخة «-silver» في «فحمي وفضي»: النسخة إذا نزلت، وإلا الأصلي ويحتاج تلوين (tint = رمادي)
    func silverAsset(_ path: String) -> (image: UIImage?, tint: Bool) {
        guard silver else { return (image(path), false) }
        if let ui = image(OccasionSilver.path(path)) { return (ui, false) }
        return (image(path), image(path) != nil)
    }

    /// الشعار المسطّح في «فحمي وفضي»: الكريمي (white) → الفضي logo/flat-silver، والكحلي (navy) → الفحمي logo/flat-navy-silver —
    /// وقبل ما ينزلون: الأصلي رمادياً (مثل نموذج ٣)
    func flatLogo(_ name: String) -> (image: UIImage?, gray: Bool) {
        let original = image(OccasionFlatLogo.path(name))
        guard silver else { return (original, false) }
        if let ui = image(name == "white" ? OccasionSilver.logo : OccasionSilver.path(OccasionFlatLogo.path(name))) { return (ui, false) }
        return (original, original != nil)
    }

    func verse(_ v: OccasionVerse, scale: CGFloat, top: CGFloat = 0, pull: CGFloat = 30) -> some View {
        let w = (v.width * scale).rounded()
        let h = w * v.height / v.width
        // مشاركة العزاء بـ«فحمي وفضي»: الآية بالفحمي (verse/*-silver) أو الأصلية رمادية؛ آيات الإعلان بيضاء أصلاً
        let file: (image: UIImage?, tint: Bool) = template.kind == .solace
            ? silverAsset("verse/\(v.file).png") : (image("verse/\(v.file).png"), false)
        return Group {
            if let ui = file.image {
                Image(uiImage: ui).resizable().frame(width: w, height: h)
                    .grayscale(file.tint ? 1 : 0)
            } else {
                Color.clear.frame(width: w, height: h)
            }
        }
        .accessibilityLabel(v.label)
        .padding(.top, top)
        .padding(.bottom, -pull)
    }

    func footer(logo: String, color: Color, lh: CGFloat, lineW: CGFloat, mb: CGFloat) -> some View {
        HStack(spacing: 28) {
            LinearGradient(colors: [color.opacity(0), color], startPoint: .leading, endPoint: .trailing)
                .frame(width: lineW, height: 2)
            let h = lh * OccasionFlatLogo.scale
            let flat = flatLogo(logo)
            if let ui = flat.image {
                Image(uiImage: ui).resizable().frame(width: h * ui.size.width / max(ui.size.height, 1), height: h)
                    .grayscale(flat.gray ? 1 : 0)
                    .padding(.vertical, (lh - h) / 2)
                    .accessibilityLabel(L10n.t("شعار عائلة المحمدعلي", "Al-Mohammad Ali family logo"))
            } else {
                Color.clear.frame(width: h * OccasionFlatLogo.aspect, height: lh)
            }
            LinearGradient(colors: [color, color.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: lineW, height: 2)
        }
        .padding(.bottom, mb)
    }

    func text(_ string: String, _ weight: OccasionKit.FontWeight, _ size: CGFloat, color: Color,
              lineHeight: CGFloat, balanceWidth: CGFloat? = nil) -> some View {
        let shown = balanceWidth.map { OccasionText.balanced(string, weight: weight, size: size, maxWidth: $0) } ?? string
        return Text(shown)
            .font(.custom(weight.postScriptName, fixedSize: size))
            .foregroundColor(color)
            .multilineTextAlignment(.center)
            // التخطيط LTR، لكن النص نفسه عربي — اتجاهه RTL حتى تطلع النقاط والأقواس بمكانها
            .environment(\.layoutDirection, .rightToLeft)
            .occasionLineBox(weight, size: size, lineHeight: lineHeight)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// سطر واحد بحجم التصميم؛ إذا ما دخل يصغر بقدر ما يدخل بس ما ينزل عن minSize — مثل OneLine في الموقع.
    /// ارتفاع السطر يبقى بحجم التصميم (lineHeight × maxSize) — فما يتحرك شي ثاني في البوست، بس الحروف أصغر.
    func fitLine(_ string: String, _ weight: OccasionKit.FontWeight, maxSize: CGFloat, minSize: CGFloat,
                 width: CGFloat, color: Color, lineHeight: CGFloat) -> some View {
        let size = OccasionText.fitSize(string, weight: weight, maxSize: maxSize, minSize: minSize, width: width)
        return Text(string)
            .font(.custom(weight.postScriptName, fixedSize: size))
            .foregroundColor(color)
            .lineLimit(1)
            // احتياط لو اختلف القياس شوي عن الرسم
            .minimumScaleFactor(0.6)
            .multilineTextAlignment(.center)
            .environment(\.layoutDirection, .rightToLeft)
            .occasionLineBox(weight, size: size, lineHeight: lineHeight * maxSize / max(size, 1))
            .frame(maxWidth: width)
    }

    /// سطر اسم واحد (الاسم، العائلة، اسم في سطر القرابة). مواصفاته من nameSlots — نفس اللي تختار منه الشاشة الصيغة،
    /// فالصيغة المختارة تدخل بحجم التصميم (أو ٨٥٪ منه على الأقل)
    func nameLine(_ key: String, color: Color) -> some View {
        let slot = template.nameSlots(model: model, size: size, withPhoto: withPhoto)[key]
            ?? OccasionNameSlot(weight: .extrabold, size: 56, width: 540, lineHeight: 1.25)
        let string = value(key)
        let minSize = slot.size * OccasionNames.minScale
        // نادر: حتى أقصر صيغة ما دخلت بأصغر حجم — سطرين متوازنين بأصغر حجم (مثل الموقع) بدل ما يصغر أكثر
        let tooLong = (OccasionNames.measure(string, weight: slot.weight, size: minSize) ?? 0) > slot.width + 0.5
        return Group {
            if tooLong {
                text(string, slot.weight, minSize, color: color, lineHeight: slot.lineHeight, balanceWidth: slot.width)
                    .frame(maxWidth: slot.width)
            } else {
                fitLine(string, slot.weight, maxSize: slot.size, minSize: minSize,
                        width: slot.width, color: color, lineHeight: slot.lineHeight)
            }
        }
    }

    /// سطر القرابة فيه اسم شخص واحد؟ (سطر واحد بصيغة تدخل) — القوائم تلتف مثل التصميم
    func isNameLine(_ key: String) -> Bool { OccasionNames.relationName(value(key)) != nil }

    // MARK: التهاني (عقد قران، مولود، مولودة، أجر وعافية، تخرج)

    private var happyPost: some View {
        let L = HappyLayout.of(size)
        let th = template.theme ?? .gold
        let vScale = template.verseScale * L.verseMul
        let vTop: CGFloat = size == .story ? 0 : (size == .post ? template.verseTopPost : template.verseTopSquare)
        let rowW = canvas.width - 2 * L.pad.side
        let rowH = 600 * L.k

        let column = VStack(spacing: 0) {
            if has("intro") {
                text(value("intro"), .semibold, L.intro, color: th.intro, lineHeight: 1.4, balanceWidth: L.cw)
            }
            if has("name") {
                nameLine("name", color: Color(hex: "#172536"))
                    .shadow(color: .white.opacity(0.9), radius: 0, x: 0, y: 2)
                    .shadow(color: th.shadow.opacity(0.20), radius: 12, x: 0, y: 12)
                    .padding(.top, 4)
            }
            if has("occasion") {
                text(value("occasion"), .extrabold, L.occ, color: th.acc, lineHeight: 1.35)
                    .padding(.top, 14)
            }
            if has("sub") {
                text(value("sub"), .extrabold, L.sub, color: th.sub, lineHeight: 1.3, balanceWidth: L.cw)
            }
            if has("dua") {
                OccasionDivider(color: th.line)
                    .padding(.top, L.divTop)
                    .padding(.bottom, L.divBottom)
                text(value("dua"), .regular, L.dua, color: Color(hex: "#3E4A5A"), lineHeight: 1.7, balanceWidth: L.duaW)
                    .frame(maxWidth: L.duaW)
            }
        }
        .frame(width: L.cw, height: rowH)

        let items: [AnyView] = [
            AnyView(verse(template.verse ?? .wed, scale: vScale, top: vTop)),
            AnyView(
                ZStack(alignment: .topLeading) {
                    OccasionHexPhoto(k: L.k, frame: image("frame/\(th.frame).png"), avatar: th.avatar, photo: photo,
                                     shadow: th.shadow.opacity(0.32), forceGray: false)
                        .offset(x: L.pleft)
                    column.offset(x: rowW - L.cw)
                }
                .frame(width: rowW, height: rowH, alignment: .topLeading)
            ),
            AnyView(footer(logo: "navy", color: th.line, lh: L.lh, lineW: L.lineW, mb: -10)),
        ]

        return ZStack(alignment: .top) {
            canvasBackground(root: th.root, bg: th.bg)
            OccasionSpacedColumn(items: items)
                .padding(.top, L.pad.top)
                .padding(.horizontal, L.pad.side)
                .padding(.bottom, L.pad.bottom)
                .frame(width: canvas.width, height: canvas.height)
        }
    }

    // MARK: التهاني بدون صورة (M2-Wedding-NP/Main-NP/BabyGirl-NP/Recovery-NP/Graduation-NP)
    // مساحة الصورة تروح للآية (بسطرين لما تتوفر) والنص بعرض البوست، والشعار بين خطين مثل النسخة مع صورة.

    private var happyNoPhotoPost: some View {
        let L = HappyNoPhotoLayout.of(size)
        let th = template.theme ?? .gold
        let np = template.noPhoto
        let v = np?.verse ?? template.verse ?? .wed
        let vWidth = (np?.m2Width ?? v.width) * L.verseMul
        let vTop = (np?.m2Top ?? 0) * L.topMul

        let column = VStack(spacing: 0) {
            if has("intro") {
                text(value("intro"), .semibold, L.intro, color: th.intro, lineHeight: 1.4, balanceWidth: L.cw)
            }
            if has("name") {
                nameLine("name", color: Color(hex: "#172536"))
                    .shadow(color: .white.opacity(0.9), radius: 0, x: 0, y: 2)
                    .shadow(color: Color(red: 23 / 255, green: 37 / 255, blue: 54 / 255).opacity(0.20), radius: 12, x: 0, y: 12)
                    .padding(.top, 4)
            }
            if has("occasion") {
                text(value("occasion"), .extrabold, L.occ, color: th.acc, lineHeight: 1.35, balanceWidth: L.cw)
                    .padding(.top, 16)
            }
            if has("sub") {
                text(value("sub"), .extrabold, L.sub, color: th.sub, lineHeight: 1.3, balanceWidth: L.cw)
            }
            if has("dua") {
                OccasionDivider(color: th.line)
                    .padding(.top, L.divTop)
                    .padding(.bottom, L.divBottom)
                text(value("dua"), .regular, L.dua, color: Color(hex: "#3E4A5A"), lineHeight: 1.7, balanceWidth: L.duaW)
                    .frame(maxWidth: L.duaW)
            }
        }
        .frame(width: L.cw)

        let items: [AnyView] = [
            AnyView(verse(v, scale: vWidth / v.width, top: vTop)),
            AnyView(column),
            AnyView(footer(logo: "navy", color: th.line, lh: L.lh, lineW: L.lineW, mb: -10)),
        ]

        return ZStack(alignment: .top) {
            canvasBackground(root: th.root, bg: th.bg)
            OccasionSpacedColumn(items: items)
                .padding(.top, L.pad.top)
                .padding(.horizontal, L.pad.side)
                .padding(.bottom, L.pad.bottom)
                .frame(width: canvas.width, height: canvas.height)
        }
    }

    // MARK: إعلان عزاء — مع صورة

    private var deathPost: some View {
        let L = DeathLayout.of(size)
        let P = OccasionDeathPalette.self
        let S = OccasionSilver.self
        let rowW = canvas.width - 2 * L.pad.side
        let rowH = 600 * L.k
        // «فحمي وفضي»: الذهبي فضي، والاسم أبيض، والعنوان فضي
        let accent = silver ? S.silver : P.gold
        let frame = silverAsset("frame/goldnight.png")

        let column = VStack(spacing: 4) {
            if has("lead") { text(value("lead"), .semibold, L.l1, color: .white, lineHeight: 1.4) }
            if has("title") { text(value("title"), .extrabold, L.l2, color: silver ? S.silver : P.soft, lineHeight: 1.35) }
            if has("name") {
                nameLine("name", color: silver ? S.text : P.gold)
                    .shadow(color: .black.opacity(0.65), radius: 13, x: 0, y: 10)
            }
            if has("relation") {
                OccasionDivider(color: silver ? S.deep : P.goldLine)
                    .padding(.top, L.divTop)
                    .padding(.bottom, L.divBottom)
                Group {
                    if isNameLine("relation") {
                        // اسم شخص واحد: سطر واحد بصيغة تدخل (والكبسولة على قده)
                        nameLine("relation", color: .white).fixedSize()
                    } else {
                        text(value("relation"), .semibold, L.rel, color: .white, lineHeight: 1.4, balanceWidth: L.relW - 80)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(Capsule().fill(accent.opacity(0.07)))
                .overlay(Capsule().stroke(accent.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 15, x: 0, y: 16)
                .frame(maxWidth: L.relW)
            }
        }
        .frame(width: L.cw, height: rowH)

        var items: [AnyView] = [
            AnyView(deathVerses(lead: L.leadMul, main: L.verseMul, leadPull: 34, mainPull: 30)),
            AnyView(
                ZStack(alignment: .topLeading) {
                    OccasionHexPhoto(k: L.k, frame: frame.image, avatar: .dark, photo: photo,
                                     shadow: .black.opacity(0.55), forceGray: false, tintFrame: frame.tint)
                        .offset(x: L.pleft)
                    column.offset(x: rowW - L.cw)
                }
                .frame(width: rowW, height: rowH, alignment: .topLeading)
            ),
        ]
        if has("menPlace") || has("womenPlace") { items.append(AnyView(deathVenues(scale: L.cols))) }
        if has("dua1") || has("dua2") { items.append(AnyView(deathDua(size: L.dua))) }
        items.append(AnyView(footer(logo: "white", color: silver ? S.deep : P.goldLine, lh: L.lh, lineW: L.lineW, mb: -8)))

        return ZStack(alignment: .top) {
            canvasBackground(root: P.root, bg: "death")
            OccasionSpacedColumn(items: items)
                .padding(.top, L.pad.top)
                .padding(.horizontal, L.pad.side)
                .padding(.bottom, L.pad.bottom)
                .frame(width: canvas.width, height: canvas.height)
        }
    }

    /// العزاءان في نموذج ٢: الأصلي بالذهبي؛ «فحمي وفضي»: العنوان والدبوس فضي، والفاصل فضي أعمق، والمنطقة والأوقات فضي
    private func deathVenues(scale s: CGFloat) -> some View {
        Group {
            if silver {
                venues(scale: s, accent: OccasionSilver.silver, line: OccasionSilver.deep, secondary: OccasionSilver.silver)
            } else {
                venues(scale: s)
            }
        }
    }

    // MARK: إعلان عزاء — بدون صورة (التفاصيل كاملة)

    private var deathTextPost: some View {
        let L = DeathTextLayout.of(size)
        let P = OccasionDeathPalette.self
        let S = OccasionSilver.self
        let rels = ["rel1", "rel2", "rel3"].filter { has($0) }
        // «فحمي وفضي»: الاسم أبيض، والقرابة والعنوان والتشييع فضي، والفواصل فضي أعمق
        let relColor = silver ? S.silver : P.grey

        var items: [AnyView] = [
            AnyView(deathVerses(lead: L.leadMul, main: L.verseMul, leadPull: 30, mainPull: 28)),
            AnyView(
                VStack(spacing: 0) {
                    if has("lead") { text(value("lead"), .semibold, L.l1, color: .white, lineHeight: 1.4) }
                    if has("title") { text(value("title"), .extrabold, L.l2, color: silver ? S.silver : P.soft, lineHeight: 1.35) }
                    if has("name") {
                        nameLine("name", color: silver ? S.text : P.gold)
                            .shadow(color: .black.opacity(0.65), radius: 13, x: 0, y: 10)
                    }
                }
            ),
        ]
        if !rels.isEmpty {
            items.append(AnyView(
                VStack(spacing: 0) {
                    ForEach(rels, id: \.self) { key in
                        // اسم شخص واحد: سطر واحد بصيغة تدخل؛ القوائم تلتف
                        if isNameLine(key) {
                            nameLine(key, color: relColor)
                        } else {
                            text(value(key), .regular, L.relF, color: relColor, lineHeight: L.relLH)
                        }
                    }
                }
                .frame(maxWidth: 900)
            ))
        }
        if has("funeral") || has("condolence") {
            items.append(AnyView(
                VStack(spacing: 2) {
                    OccasionDivider(color: silver ? S.deep : P.goldLine).padding(.bottom, L.divBottom)
                    if has("funeral") { text(value("funeral"), .semibold, L.fun, color: silver ? S.silver : P.gold, lineHeight: 1.45) }
                    if has("condolence") { text(value("condolence"), .semibold, L.con, color: .white, lineHeight: 1.45) }
                }
            ))
        }
        if has("menPlace") || has("womenPlace") { items.append(AnyView(deathVenues(scale: L.cols))) }
        if has("dua1") || has("dua2") { items.append(AnyView(deathDua(size: L.dua))) }
        items.append(AnyView(footer(logo: "white", color: silver ? S.deep : P.goldLine, lh: L.lh, lineW: L.lineW, mb: -8)))

        return ZStack(alignment: .top) {
            canvasBackground(root: P.root, bg: "death")
            OccasionSpacedColumn(items: items)
                .padding(.top, L.pad.top)
                .padding(.horizontal, L.pad.side)
                .padding(.bottom, L.pad.bottom)
                .frame(width: canvas.width, height: canvas.height)
        }
    }

    // MARK: مشاركة عزاء

    private var solacePost: some View {
        let L = SolaceLayout.of(size)
        // «فحمي وفضي»: الأرضية الفاتحة بألوان البطاقة الفاتحة (فحمي، رمادي ثانوي، وزخارف فضية أعمق)
        let S = OccasionSilver.self
        let ink = silver ? S.cardText : Color(hex: "#20262D")
        let muted = silver ? S.cardText2 : Color(hex: "#4A5560")
        let line = silver ? S.cardAccent : Color(hex: "#8D97A3")
        let duaColor = silver ? S.cardText2 : Color(hex: "#55657A")

        var items: [AnyView] = [
            AnyView(verse(template.verse ?? .sabr, scale: L.verseMul)),
            AnyView(
                VStack(spacing: 10) {
                    // «تتقدم عائلة المحمدعلي» ملاصق للعنوان وبعرضه — «مشاركة عزاء» ممدودة بالكشيدة (مثل الموقع)
                    OccasionSolaceHeadingView(from: has("from") ? value("from") : "", fromSize: L.from, titleSize: L.title,
                                              fromLineHeight: 1.35, titleColor: ink, fromColor: ink)
                        .modifier(OccasionLightShadow())
                    OccasionDivider(color: line).padding(.top, 4)
                }
            ),
            AnyView(
                VStack(spacing: 8) {
                    text("بأحر التعازي وأصدق المواساة إلى", .regular, L.sub, color: muted, lineHeight: 1.4)
                    if has("to") {
                        nameLine("to", color: ink)
                            .modifier(OccasionLightShadow())
                            .padding(.top, 8)
                    }
                }
            ),
            AnyView(
                VStack(spacing: 6) {
                    if has("lead") { text(value("lead"), .regular, L.lead, color: muted, lineHeight: 1.4) }
                    if has("name") {
                        nameLine("name", color: ink)
                            .modifier(OccasionLightShadow())
                    }
                }
            ),
        ]
        if has("dua") {
            items.append(AnyView(
                text(value("dua"), .regular, L.dua, color: duaColor, lineHeight: 1.75, balanceWidth: 880)
                    .frame(maxWidth: 880)
            ))
        }
        items.append(AnyView(footer(logo: "navy", color: line, lh: L.lh, lineW: L.lineW, mb: -12)))

        return ZStack(alignment: .top) {
            canvasBackground(root: Color(hex: "#F7F8F9"), bg: "solace")
            OccasionSpacedColumn(items: items)
                .padding(.top, L.pad.top)
                .padding(.horizontal, L.pad.side)
                .padding(.bottom, L.pad.bottom)
                .frame(width: canvas.width, height: canvas.height)
        }
    }

    // MARK: قطع الوفاة

    func deathVerses(lead: CGFloat, main: CGFloat, leadPull: CGFloat, mainPull: CGFloat) -> some View {
        VStack(spacing: 0) {
            verse(.sabrLead, scale: lead, pull: leadPull)
            verse(.inna, scale: main, pull: mainPull)
        }
    }

    /// الدعاء تحت الإعلان (نموذج ١ و٢): رمادي فاتح، وفضي في «فحمي وفضي»
    func deathDua(size s: CGFloat) -> some View {
        let color = silver ? OccasionSilver.silver : OccasionDeathPalette.dua
        return VStack(spacing: 0) {
            if has("dua1") { text(value("dua1"), .regular, s, color: color, lineHeight: 1.6) }
            if has("dua2") { text(value("dua2"), .regular, s, color: color, lineHeight: 1.6) }
        }
    }

    /// عزاء الرجال والنساء. accent = لون «عــزاء …» والدبوس (نموذج ٢ ذهبي، نموذج ١ أبيض، «فحمي وفضي» فضي)،
    /// line = الخط الفاصل بينهم، secondary = المنطقة والأوقات. فتحة الدبوس بلون الأرضية (الأسود، أو الغرافيت الغامق)
    func venues(scale s: CGFloat, accent: Color = OccasionDeathPalette.gold, line: Color = OccasionDeathPalette.goldLine,
                secondary: Color = OccasionDeathPalette.grey) -> some View {
        let hole = silver ? OccasionSilver.groundBottom : OccasionDeathPalette.root
        let men = has("menPlace")
        let women = has("womenPlace")
        // الأوقات تنقسم هنا (مع كل رسم للمنشور) — داخل OccasionVenue ما تنعاد لما يتسجّل الخط فيبقى القياس الأول
        func times(_ side: String) -> String { OccasionText.venueTimes(value("\(side)Times"), size: 22 * s, maxWidth: 210 * s) }
        // من اليسار لليمين: النساء ثم الرجال (في التصميم RTL: الرجال يمين)
        return HStack(spacing: 22 * s) {
            if women {
                OccasionVenue(label: "النساء", place: value("womenPlace"), area: value("womenArea"), times: times("women"), scale: s, accent: accent,
                              secondary: secondary, pinHole: hole)
                    .frame(maxWidth: .infinity)
            }
            if men && women {
                LinearGradient(colors: [line.opacity(0), line, line.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(width: 2, height: 128 * s)
            }
            if men {
                OccasionVenue(label: "الرجال", place: value("menPlace"), area: value("menArea"), times: times("men"), scale: s, accent: accent,
                              secondary: secondary, pinHole: hole)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - قطع مشتركة

/// عمود يوزّع عناصره مثل justify-content: space-between
struct OccasionSpacedColumn: View {
    let items: [AnyView]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                if i > 0 { Spacer(minLength: 0) }
                items[i]
            }
        }
    }
}

/// السداسي العمودي (رأس فوق وتحت) — نفس clip-path في الموقع
struct OccasionHexagon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.25))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.75))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.75))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.25))
        p.closeSubpath()
        return p
    }
}

/// فاصل: خطين يتلاشون + سداسي صغير
struct OccasionDivider: View {
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            LinearGradient(colors: [color.opacity(0), color], startPoint: .leading, endPoint: .trailing)
                .frame(width: 72, height: 2)
            OccasionHexagon()
                .stroke(color, lineWidth: 1.8)
                .frame(width: 14, height: 16)
            LinearGradient(colors: [color, color.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 72, height: 2)
        }
    }
}

/// وحدة الصورة: إطار 560×600 (مضروب في k)، والصورة مقصوصة داخل السداسي (نصف قطر 230 عند 280،300)
struct OccasionHexPhoto: View {
    let k: CGFloat
    let frame: UIImage?
    let avatar: OccasionAvatar
    let photo: OccasionPhoto
    let shadow: Color
    let forceGray: Bool
    /// «فحمي وفضي» قبل ما ينزل الإطار الفضي: الإطار الذهبي رمادي بلمسة باردة
    var tintFrame: Bool = false

    var body: some View {
        let width = 560 * k
        let height = 600 * k
        let pw = 398.4 * k
        let ph = 460 * k
        return ZStack(alignment: .topLeading) {
            photoContent(pw: pw, ph: ph)
                .frame(width: pw, height: ph)
                .clipShape(OccasionHexagon())
                .compositingGroup()
                .shadow(color: shadow, radius: 14, x: 0, y: 18)
                .offset(x: 80.8 * k, y: 70 * k)
            if let frame {
                Image(uiImage: frame).resizable().frame(width: width, height: height)
                    .grayscale(tintFrame ? 1 : 0)
                    .colorMultiply(tintFrame ? OccasionSilver.fallbackTint : .white)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    @ViewBuilder
    private func photoContent(pw: CGFloat, ph: CGFloat) -> some View {
        if let ui = photo.image, ui.size.width > 0, ui.size.height > 0 {
            let s = max(pw / ui.size.width, ph / ui.size.height) * max(photo.zoom, 1)
            let dw = ui.size.width * s
            let dh = ui.size.height * s
            ZStack(alignment: .topLeading) {
                Color.clear
                Image(uiImage: ui)
                    .resizable()
                    .frame(width: dw, height: dh)
                    .offset(x: (pw - dw) * photo.x / 100, y: (ph - dh) * photo.y / 100)
            }
            .frame(width: pw, height: ph, alignment: .topLeading)
            .grayscale(photo.gray || forceGray ? 1 : 0)
        } else {
            OccasionAvatarView(style: avatar)
        }
    }
}

/// صورة مؤقتة (ظل شخص) لين ما تنختار صورة
struct OccasionAvatarView: View {
    let style: OccasionAvatar

    var body: some View {
        GeometryReader { geo in
            let s = max(geo.size.width, geo.size.height) / 400
            let dx = (geo.size.width - 400 * s) / 2
            let dy = (geo.size.height - 400 * s) / 2
            ZStack {
                style.colors.bg
                Path { p in
                    p.addEllipse(in: CGRect(x: dx + 134 * s, y: dy + 92 * s, width: 132 * s, height: 132 * s))
                    p.move(to: CGPoint(x: dx + 70 * s, y: dy + 400 * s))
                    p.addCurve(to: CGPoint(x: dx + 200 * s, y: dy + 250 * s),
                               control1: CGPoint(x: dx + 70 * s, y: dy + 300 * s),
                               control2: CGPoint(x: dx + 130 * s, y: dy + 250 * s))
                    p.addCurve(to: CGPoint(x: dx + 330 * s, y: dy + 400 * s),
                               control1: CGPoint(x: dx + 270 * s, y: dy + 250 * s),
                               control2: CGPoint(x: dx + 330 * s, y: dy + 300 * s))
                    p.closeSubpath()
                }
                .fill(style.colors.fg)
            }
        }
    }
}

/// عمود مكان العزاء (الرجال / النساء) — من اليسار: المكان، الدبوس، العنوان
struct OccasionVenue: View {
    let label: String
    let place: String
    let area: String
    let times: String
    let scale: CGFloat
    /// لون «عــزاء …» والدبوس (نموذج ٢ ذهبي، نموذج ١ أبيض، «فحمي وفضي» فضي)
    var accent: Color = OccasionDeathPalette.gold
    /// المنطقة والأوقات
    var secondary: Color = OccasionDeathPalette.grey
    /// فتحة الدبوس: بلون الأرضية
    var pinHole: Color = OccasionDeathPalette.root

    var body: some View {
        let s = scale
        return HStack(alignment: .center, spacing: 12 * s) {
            VStack(alignment: .trailing, spacing: 4 * s) {
                Text(place)
                    .font(.custom(OccasionKit.FontWeight.extrabold.postScriptName, fixedSize: 29 * s))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .environment(\.layoutDirection, .rightToLeft)
                    .fixedSize(horizontal: false, vertical: true)
                if !area.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(area)
                        .font(.custom(OccasionKit.FontWeight.regular.postScriptName, fixedSize: 23 * s))
                        .foregroundColor(secondary)
                        .environment(\.layoutDirection, .rightToLeft)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(maxWidth: 250 * s, alignment: .trailing)
            OccasionPin(color: accent, hole: pinHole)
                .frame(width: 54 * s, height: 54 * s)
            VStack(spacing: 0) {
                Text("عــزاء")
                    .font(.custom(OccasionKit.FontWeight.semibold.postScriptName, fixedSize: 29 * s))
                    .foregroundColor(accent)
                Text(label)
                    .font(.custom(OccasionKit.FontWeight.semibold.postScriptName, fixedSize: 29 * s))
                    .foregroundColor(accent)
                if !times.trimmingCharacters(in: .whitespaces).isEmpty {
                    // «اليوم وغداً وبعد غد، عقب صلاة العصر» أطول من العنوان — يوصل مقسوماً سطرين عند الفاصلة
                    // (OccasionText.venueTimes في venues) بدل ما يوسّع العمود
                    Text(times)
                        .font(.custom(OccasionKit.FontWeight.regular.postScriptName, fixedSize: 22 * s))
                        .foregroundColor(secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2 * s)
                        .padding(.top, 8 * s)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .fixedSize()
        }
    }
}

/// دبوس الموقع داخل دائرة (نفس رسمة الموقع، مقاس 64)
struct OccasionPin: View {
    let color: Color
    /// لون الفتحة (لون الأرضية)
    var hole: Color = OccasionDeathPalette.root

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 64
            ZStack {
                Circle()
                    .stroke(color, lineWidth: 2.4 * s)
                    .frame(width: 59 * s, height: 59 * s)
                Path { p in
                    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
                    p.move(to: pt(32, 15.5))
                    p.addCurve(to: pt(20, 27.3), control1: pt(25.3, 15.5), control2: pt(20, 20.7))
                    p.addCurve(to: pt(32, 48), control1: pt(20, 36), control2: pt(32, 48))
                    p.addCurve(to: pt(44, 27.3), control1: pt(32, 48), control2: pt(44, 36))
                    p.addCurve(to: pt(32, 15.5), control1: pt(44, 20.7), control2: pt(38.7, 15.5))
                    p.closeSubpath()
                }
                .fill(color)
                Circle()
                    .fill(hole)
                    .frame(width: 9.2 * s, height: 9.2 * s)
                    .position(x: 32 * s, y: 27.4 * s)
            }
            .frame(width: 64 * s, height: 64 * s)
        }
    }
}

/// «مشاركة عزاء» وتحتها «تتقدم…» ملاصقاً لها وبعرضها — نفس SolaceHeading في الموقع (كل النماذج).
/// الكلمتان في HStack (التخطيط LTR: «عزاء» يسار و«مشاركة» يمين) والمسافة بينهما = المسافة العادية + الباقي.
struct OccasionSolaceHeadingView: View {
    let from: String
    let fromSize: CGFloat
    let titleSize: CGFloat
    let fromLineHeight: CGFloat
    let titleColor: Color
    let fromColor: Color

    var body: some View {
        let fit = OccasionSolaceHeading.fit(from: from, fromSize: fromSize, titleSize: titleSize)
        let t = from.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let fs = t.isEmpty ? fromSize : OccasionSolaceHeading.oneLineSize(t, fromSize, fit.cap)
        return VStack(spacing: 0) {
            Group {
                if let gap = fit.gap {
                    HStack(spacing: gap) {
                        word(fit.words[1])
                        word(fit.words[0])
                    }
                    .environment(\.layoutDirection, .leftToRight)
                } else {
                    word(fit.title)
                }
            }
            if !t.isEmpty {
                Text(t)
                    .font(.custom(OccasionKit.FontWeight.extrabold.postScriptName, fixedSize: fs))
                    .foregroundColor(fromColor)
                    .lineLimit(1)
                    // احتياط لو اختلف القياس شوي عن الرسم
                    .minimumScaleFactor(0.6)
                    .environment(\.layoutDirection, .rightToLeft)
                    .occasionLineBox(.extrabold, size: fs, lineHeight: fromLineHeight * fromSize / max(fs, 1))
                    .frame(maxWidth: fit.cap)
            }
        }
    }

    private func word(_ w: String) -> some View {
        Text(w)
            .font(.custom(OccasionKit.FontWeight.extrabold.postScriptName, fixedSize: titleSize))
            .foregroundColor(titleColor)
            .lineLimit(1)
            .fixedSize()
            .environment(\.layoutDirection, .rightToLeft)
            .occasionLineBox(.extrabold, size: titleSize, lineHeight: 1.25)
    }
}

/// ظل النص الفاتح (مثل text-shadow في التصميم) — k لنموذج ١ في المقاسات المصغّرة
struct OccasionLightShadow: ViewModifier {
    var k: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .shadow(color: .white.opacity(0.95), radius: 0, x: 0, y: 2 * k)
            .shadow(color: Color(red: 27 / 255, green: 32 / 255, blue: 38 / 255).opacity(0.20), radius: 12 * k, x: 0, y: 12 * k)
    }
}

extension View {
    /// يقرّب ارتفاع السطر من line-height في التصميم (CSS) بدل ارتفاع الخط الطبيعي.
    /// Text بسطر واحد في SwiftUI ارتفاعه منطقة الحروف (contentEm) بلا lineGap، فنصف الفراغ كما في CSS:
    /// (line-height − content) ÷ ٢ فوق وتحت. كان يُطرح من ارتفاع يشمل lineGap فينكمش صندوق الاسم لنصفه
    /// ويركب على السطر فوقه وتحته (طلب المالك ٢٠٢٦-١٠-١٧ «الاسم مو مكانه… كلهم»).
    func occasionLineBox(_ weight: OccasionKit.FontWeight, size: CGFloat, lineHeight: CGFloat) -> some View {
        let spacing = (lineHeight - weight.lineHeightEm) * size
        let halfLeading = (lineHeight - weight.contentEm) * size / 2
        return self
            .lineSpacing(max(0, spacing))
            .padding(.vertical, halfLeading)
    }
}

/// توزيع النص على سطرين متقاربين إذا ما وسعه سطر واحد (مثل text-wrap: balance)
enum OccasionText {
    /// التنوين والحركات على آخر حرف تطلع مزاحة بخط URW (ما فيه مواضع لها) — نشيلها من نص البوست،
    /// و«المحمد علي» المكتوبة بمسافة تصير «المحمدعلي» متصلة مثل الشجرة (كلمة كاملة فقط)،
    /// و«عبد/أبو + الاسم» ما ينقسمون على سطرين. نفس postText في الموقع.
    static func postText(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: s.unicodeScalars.filter { !((0x064B...0x0652).contains($0.value) || $0.value == 0x0670) })
        var out = String(scalars)
        out = out.replacingOccurrences(of: "(?<!\\p{L})المحمد\\s+علي(?!\\p{L})", with: "المحمدعلي", options: .regularExpression)
        out = out.replacingOccurrences(of: "(^|[\\s،(])(عبد|أبو|ابو|بو)\\s+(?=\\S)", with: "$1$2\u{00A0}", options: .regularExpression)
        return out
    }

    /// أكبر حجم خط (بين الأصغر والأكبر) يخلي النص بسطر واحد داخل العرض — نفس fitFontSize في الموقع
    static func fitSize(_ text: String, weight: OccasionKit.FontWeight, maxSize: CGFloat, minSize: CGFloat, width: CGFloat) -> CGFloat {
        guard !text.isEmpty, let font = UIFont(name: weight.postScriptName, size: maxSize) else { return maxSize }
        let w = (text as NSString).size(withAttributes: [.font: font]).width
        guard w > width else { return maxSize }
        return max(minSize, floor(maxSize * width * 0.97 / w))
    }

    /// أوقات العزاء تحت «عــزاء الرجال/النساء»: إذا ما دخلت بسطر، تنقسم عند «، » (الأيام فوق والوقت تحت)، وإلا سطرين متوازنين
    static func venueTimes(_ text: String, size: CGFloat, maxWidth: CGFloat) -> String {
        let weight = OccasionKit.FontWeight.regular
        guard let font = UIFont(name: weight.postScriptName, size: size),
              (text as NSString).size(withAttributes: [.font: font]).width > maxWidth else { return text }
        if let r = text.range(of: "، ") {
            return String(text[..<r.lowerBound]) + "،\n" + String(text[r.upperBound...])
        }
        return balanced(text, weight: weight, size: size, maxWidth: maxWidth)
    }

    static func balanced(_ text: String, weight: OccasionKit.FontWeight, size: CGFloat, maxWidth: CGFloat) -> String {
        guard !text.contains("\n"), let font = UIFont(name: weight.postScriptName, size: size) else { return text }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        func width(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: attrs).width }
        guard width(text) > maxWidth else { return text }
        let words = text.split(separator: " ").map(String.init)
        guard words.count > 1 else { return text }
        var best = text
        var bestWidth = CGFloat.greatestFiniteMagnitude
        for i in 1..<words.count {
            let first = words[..<i].joined(separator: " ")
            let second = words[i...].joined(separator: " ")
            let w = max(width(first), width(second))
            if w < bestWidth {
                bestWidth = w
                best = first + "\n" + second
            }
        }
        // إذا حتى السطرين ما يكفون، نخلي SwiftUI يلف النص بنفسه
        return bestWidth <= maxWidth ? best : text
    }
}
