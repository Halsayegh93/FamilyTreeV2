import SwiftUI
import UIKit

// MARK: - رسم بوست المناسبة بمقاسه الحقيقي (نقطة = بكسل) — نموذج ١ ونموذج ٢
//
// المرجع ملفات التصميم (HTML بعرض 1080): المقاسات والأوزان والألوان وارتفاع السطور والهوامش
// كلها منها. نموذج ٢ هنا، ونموذج ١ في OccasionModel1View.swift.
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
    /// نموذج ١ أو ٢ (القالب اللي ما له نموذج ١ ينرسم نموذج ٢)
    var model: OccasionModel = .m2

    var canvas: CGSize { size.canvas }

    var body: some View {
        content
            .frame(width: canvas.width, height: canvas.height)
            .clipped()
            .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder
    private var content: some View {
        if template.effectiveModel(model) == .m1 {
            switch template.kind {
            case .happy: m1HappyPost
            case .death, .deathText: m1DeathPost
            case .solace: m1SolacePost
            }
        } else {
            switch template.kind {
            case .happy: happyPost
            case .death: deathPost
            case .deathText: deathTextPost
            case .solace: solacePost
            }
        }
    }

    // MARK: أدوات

    /// النص النهائي للبوست: بدون تشكيل (الخط ما يضبطه) و«المحمد علي» ما ينقسم — نفس postText في الموقع
    func value(_ key: String) -> String { OccasionText.postText(values[key] ?? "") }

    func has(_ key: String) -> Bool {
        !value(key).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func image(_ path: String) -> UIImage? { kit.image(path) }

    /// لون الحبر الأساسي في التهاني ولون ظل الاسم (rgba(23,37,54,…))
    static let ink = Color(hex: "#172536")
    static let inkShadow = Color(red: 23 / 255, green: 37 / 255, blue: 54 / 255)

    /// سطور نص بصناديق CSS (line-height) — انظر OccasionTextLayout
    func lines(_ string: String, _ weight: OccasionKit.FontWeight, _ size: CGFloat, lh: CGFloat, color: Color,
               width: CGFloat, wrap: OccasionWrap = .normal, maxLines: Int? = nil) -> OccasionLines {
        OccasionLines(string, weight, size, lineHeight: lh, color: color, maxWidth: width, wrap: wrap, maxLines: maxLines)
    }

    /// سطر اسم واحد (الاسم، العائلة، اسم في سطر القرابة). مواصفاته من nameSlots — نفس اللي تختار منه
    /// الشاشة الصيغة (سداسي … ثلاثي) — فالاسم يوصل هنا بصيغة تدخل، ويصغر بس إذا حتى الثلاثي ما دخل
    func nameLine(_ key: String, color: Color) -> OccasionLines {
        let slot = template.nameSlots(model: model, size: size)[key] ?? OccasionNameSlot(.extrabold, 56, 540, 1.25)
        return OccasionLines(oneLine: value(key), slot.weight, slot.size, lineHeight: slot.lineHeight, color: color,
                             maxWidth: slot.width)
    }

    /// عنوان قصير (الافتتاح، المناسبة، اللقب، اسم المولود…): سطر واحد يصغر بس إذا ما دخل
    func label(_ string: String, _ weight: OccasionKit.FontWeight, _ size: CGFloat, lh: CGFloat, color: Color,
               width: CGFloat) -> OccasionLines {
        OccasionLines(oneLine: string, weight, size, lineHeight: lh, color: color, maxWidth: width, overflow: .normal)
    }

    /// سطر القرابة فيه اسم شخص واحد؟ (سطر واحد بصيغة تدخل) — القوائم تلتف مثل التصميم
    func isNameLine(_ key: String) -> Bool { OccasionNames.relationName(values[key] ?? "") != nil }

    /// سطرا كبسولة «صلة القرابة» اللي فيهم نص (وفاة مع صورة: سطر أو سطرين)
    var relationKeys: [String] { ["relation", "relation2"].filter { has($0) } }

    /// سطر قرابة داخل الكبسولة: اسم شخص واحد = سطر واحد بصيغته، والقائمة تلتف مثل التصميم
    func relationLine(_ key: String, size: CGFloat, width: CGFloat, wrap: OccasionWrap = .normal) -> OccasionLines {
        isNameLine(key)
            ? nameLine(key, color: .white)
            : lines(value(key), .semibold, size, lh: 1.4, color: .white, width: width, wrap: wrap)
    }

    func canvasBackground(root: Color, bg: String) -> some View {
        ZStack {
            root
            if let ui = image("bg/\(bg)-\(size.rawValue).jpg") {
                Image(uiImage: ui).resizable().frame(width: canvas.width, height: canvas.height)
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    func verse(_ v: OccasionVerse, width: CGFloat, top: CGFloat = 0, pull: CGFloat = 30) -> some View {
        let w = width.rounded()
        let h = w * v.height / v.width
        return Group {
            if let ui = image("verse/\(v.file).png") {
                Image(uiImage: ui).resizable().frame(width: w, height: h)
            } else {
                Color.clear.frame(width: w, height: h)
            }
        }
        .accessibilityLabel(v.label)
        .padding(.top, top)
        .padding(.bottom, -pull)
    }

    func logo(_ name: String, height lh: CGFloat) -> some View {
        Group {
            if let ui = image("logo/\(name).png") {
                Image(uiImage: ui).resizable().frame(width: lh * ui.size.width / max(ui.size.height, 1), height: lh)
                    .accessibilityLabel(L10n.t("شعار عائلة المحمد علي", "Al-Mohammad Ali family logo"))
            } else {
                Color.clear.frame(width: lh * 900 / 831, height: lh)
            }
        }
    }

    private func footer(logo name: String, color: Color, lh: CGFloat, lineW: CGFloat, mb: CGFloat) -> some View {
        HStack(spacing: 28) {
            LinearGradient(colors: [color.opacity(0), color], startPoint: .leading, endPoint: .trailing)
                .frame(width: lineW, height: 2)
            logo(name, height: lh)
            LinearGradient(colors: [color, color.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: lineW, height: 2)
        }
        .padding(.bottom, mb)
    }

    func post(root: some View, items: [AnyView], pad: OccasionInsets) -> some View {
        ZStack(alignment: .top) {
            root
            OccasionSpacedColumn(items: items)
                .padding(.top, pad.top)
                .padding(.horizontal, pad.side)
                .padding(.bottom, pad.bottom)
                .frame(width: canvas.width, height: canvas.height)
        }
    }

    // MARK: التهاني (عقد قران، مولود، مولودة، أجر وعافية، تخرج) — M2-Wedding/Main/BabyGirl/Recovery/Graduation

    private var happyPost: some View {
        let L = HappyLayout.of(size)
        let th = template.theme ?? .gold
        let vScale = template.verseScale * L.verseMul
        let vTop: CGFloat = size == .story ? 0 : (size == .post ? template.verseTopPost : template.verseTopSquare)
        let rowW = canvas.width - 2 * L.pad.side
        let rowH = 600 * L.k
        let v = template.verse ?? .wed

        let column = VStack(spacing: 0) {
            if has("intro") {
                label(value("intro"), .semibold, L.intro, lh: 1.4, color: th.intro, width: L.cw)
            }
            // الاسم سطر واحد بحجم التصميم (الصيغة تختصر لين يدخل)
            if has("name") {
                nameLine("name", color: Self.ink)
                    .textShadow(.lift(0.9), OccasionTextShadow(y: 12, blur: 24, color: Self.inkShadow.opacity(0.20)))
                    .padding(.top, 4)
            }
            if has("occasion") {
                label(value("occasion"), .extrabold, L.occ, lh: 1.35, color: th.acc, width: L.cw)
                    .padding(.top, 14)
            }
            if has("sub") {
                if template.id == "graduation" {
                    // الجهة («من الهيئة العامة للتعليم التطبيقي…») تلتف متوازنة مثل التصميم
                    lines(value("sub"), .extrabold, L.sub, lh: 1.3, color: th.sub, width: L.cw, wrap: .balance, maxLines: 2)
                } else {
                    // اسم المولود: سطر واحد
                    label(value("sub"), .extrabold, L.sub, lh: 1.3, color: th.sub, width: L.cw)
                }
            }
            if has("dua") {
                OccasionDivider(color: th.line)
                    .padding(.top, L.divTop)
                    .padding(.bottom, L.divBottom)
                lines(value("dua"), .regular, L.dua, lh: 1.7, color: Color(hex: "#3E4A5A"), width: L.duaW, wrap: .balance)
            }
        }
        .frame(width: L.cw, height: rowH)

        let items: [AnyView] = [
            AnyView(verse(v, width: v.width * vScale, top: vTop)),
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

        return post(root: canvasBackground(root: th.root, bg: th.bg), items: items, pad: L.pad)
    }

    // MARK: إعلان وفاة — مع صورة (M2-Condolence)

    private var deathPost: some View {
        let L = DeathLayout.of(size)
        let P = OccasionDeathPalette.self
        let rowW = canvas.width - 2 * L.pad.side
        let rowH = 600 * L.k

        let column = VStack(spacing: 4) {
            if has("lead") { label(value("lead"), .semibold, L.l1, lh: 1.4, color: .white, width: L.cw) }
            if has("title") { label(value("title"), .extrabold, L.l2, lh: 1.35, color: P.soft, width: L.cw) }
            if has("name") {
                nameLine("name", color: P.gold)
                    .textShadow(OccasionTextShadow(y: 10, blur: 26, color: .black.opacity(0.65)))
            }
            if !relationKeys.isEmpty {
                OccasionDivider(color: P.goldLine)
                    .padding(.top, L.divTop)
                    .padding(.bottom, L.divBottom)
                // سطر أو سطرين بنفس الكبسولة — تطول بس
                VStack(spacing: 0) {
                    ForEach(relationKeys, id: \.self) { key in
                        relationLine(key, size: L.rel, width: L.relW, wrap: .balance)
                    }
                }
                .modifier(OccasionPillBox(padTop: 10, padSide: 40, padBottom: 12, fill: AnyView(Capsule().fill(P.gold.opacity(0.07))),
                                          border: P.gold.opacity(0.5), shadow: .black.opacity(0.45), shadowRadius: 15, shadowY: 16))
            }
        }
        .frame(width: L.cw, height: rowH)

        var items: [AnyView] = [
            AnyView(deathVerses(lead: L.leadMul, main: L.verseMul, leadPull: 34, mainPull: 30)),
            AnyView(
                ZStack(alignment: .topLeading) {
                    OccasionHexPhoto(k: L.k, frame: image("frame/goldnight.png"), avatar: .dark, photo: photo,
                                     shadow: .black.opacity(0.55), forceGray: false)
                        .offset(x: L.pleft)
                    column.offset(x: rowW - L.cw)
                }
                .frame(width: rowW, height: rowH, alignment: .topLeading)
            ),
        ]
        if has("menPlace") || has("womenPlace") { items.append(AnyView(venues(scale: L.cols, accent: P.gold, line: P.goldLine))) }
        if has("dua1") || has("dua2") { items.append(AnyView(deathDua(size: L.dua, lh: L.duaLH, width: rowW))) }
        items.append(AnyView(footer(logo: "white", color: P.goldLine, lh: L.lh, lineW: L.lineW, mb: -8)))

        return post(root: canvasBackground(root: P.root, bg: "death"), items: items, pad: L.pad)
    }

    // MARK: إعلان وفاة — بدون صورة، التفاصيل كاملة (M2-CondolenceText)

    private var deathTextPost: some View {
        let L = DeathTextLayout.of(size)
        let P = OccasionDeathPalette.self
        let rowW = canvas.width - 2 * L.pad.side
        let rels = ["rel1", "rel2", "rel3"].filter { has($0) }

        var items: [AnyView] = [
            AnyView(deathVerses(lead: L.leadMul, main: L.verseMul, leadPull: 30, mainPull: 28)),
            AnyView(
                VStack(spacing: 0) {
                    if has("lead") { label(value("lead"), .semibold, L.l1, lh: 1.4, color: .white, width: rowW) }
                    VStack(spacing: 0) {
                        if has("title") { label(value("title"), .extrabold, L.l2, lh: 1.35, color: P.soft, width: rowW) }
                        if has("name") {
                            nameLine("name", color: P.gold)
                                .textShadow(OccasionTextShadow(y: 10, blur: 26, color: .black.opacity(0.65)))
                        }
                    }
                    .padding(.top, 2)
                }
            ),
        ]
        if !rels.isEmpty {
            items.append(AnyView(
                VStack(spacing: 0) {
                    ForEach(rels, id: \.self) { key in
                        if isNameLine(key) {
                            nameLine(key, color: P.grey)
                        } else {
                            lines(value(key), .regular, L.relF, lh: L.relLH, color: P.grey, width: min(900, rowW))
                        }
                    }
                }
            ))
        }
        if has("funeral") || has("condolence") {
            items.append(AnyView(
                VStack(spacing: 2) {
                    OccasionDivider(color: P.goldLine).padding(.bottom, L.divBottom)
                    if has("funeral") { lines(value("funeral"), .semibold, L.fun, lh: 1.45, color: P.gold, width: rowW) }
                    if has("condolence") { lines(value("condolence"), .semibold, L.con, lh: 1.45, color: .white, width: rowW) }
                }
            ))
        }
        if has("menPlace") || has("womenPlace") { items.append(AnyView(venues(scale: L.cols, accent: P.gold, line: P.goldLine))) }
        if has("dua1") || has("dua2") { items.append(AnyView(deathDua(size: L.dua, lh: 1.6, width: rowW))) }
        items.append(AnyView(footer(logo: "white", color: P.goldLine, lh: L.lh, lineW: L.lineW, mb: -8)))

        return post(root: canvasBackground(root: P.root, bg: "death"), items: items, pad: L.pad)
    }

    // MARK: مشاركة عزاء (M2-Solace)

    private var solacePost: some View {
        let L = SolaceLayout.of(size)
        let ink = Color(hex: "#20262D")
        let muted = Color(hex: "#4A5560")
        let line = Color(hex: "#8D97A3")
        let rowW = canvas.width - 2 * L.pad.side
        let v = template.verse ?? .sabr

        var items: [AnyView] = [
            AnyView(verse(v, width: v.width * L.verseMul)),
            AnyView(
                VStack(spacing: 10) {
                    lines("مشـاركة عـزاء", .extrabold, L.title, lh: 1.25, color: ink, width: rowW).textShadow(OccasionText.lightShadow())
                    OccasionDivider(color: line).padding(.top, 4)
                }
            ),
            AnyView(
                VStack(spacing: 8) {
                    if has("from") { label(value("from"), .semibold, L.from, lh: 1.35, color: ink, width: rowW).textShadow(OccasionText.lightShadow()) }
                    lines("بأحر التعازي وأصدق المواساة إلى", .regular, L.sub, lh: 1.4, color: muted, width: rowW)
                    if has("to") {
                        nameLine("to", color: ink)
                            .textShadow(OccasionText.lightShadow())
                            .padding(.top, 8)
                    }
                }
            ),
            AnyView(
                VStack(spacing: 6) {
                    if has("lead") { label(value("lead"), .regular, L.lead, lh: 1.4, color: muted, width: rowW) }
                    if has("name") {
                        nameLine("name", color: ink)
                            .textShadow(OccasionText.lightShadow())
                    }
                }
            ),
        ]
        if has("dua") {
            items.append(AnyView(
                lines(value("dua"), .regular, L.dua, lh: 1.75, color: Color(hex: "#55657A"), width: min(880, rowW), wrap: .balance)
            ))
        }
        items.append(AnyView(footer(logo: "navy", color: line, lh: L.lh, lineW: L.lineW, mb: -12)))

        return post(root: canvasBackground(root: Color(hex: "#F7F8F9"), bg: "solace"), items: items, pad: L.pad)
    }

    // MARK: قطع الوفاة

    func deathVerses(lead: CGFloat, main: CGFloat, leadPull: CGFloat, mainPull: CGFloat) -> some View {
        VStack(spacing: 0) {
            verse(.sabrLead, width: OccasionVerse.sabrLead.width * lead, pull: leadPull)
            verse(.inna, width: OccasionVerse.inna.width * main, pull: mainPull)
        }
    }

    func deathDua(size s: CGFloat, lh: CGFloat, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            if has("dua1") { lines(value("dua1"), .regular, s, lh: lh, color: OccasionDeathPalette.dua, width: width) }
            if has("dua2") { lines(value("dua2"), .regular, s, lh: lh, color: OccasionDeathPalette.dua, width: width) }
        }
    }

    /// عزاء الرجال والنساء. accent = لون «عــزاء …» والدبوس، line = لون الخط الفاصل بينهم
    func venues(scale s: CGFloat, accent: Color, line: Color) -> some View {
        let men = has("menPlace")
        let women = has("womenPlace")
        // من اليسار لليمين: النساء ثم الرجال (في التصميم RTL: الرجال يمين)
        return HStack(spacing: 22 * s) {
            if women {
                OccasionVenue(label: "النساء", place: value("womenPlace"), area: value("womenArea"), times: value("womenTimes"),
                              scale: s, accent: accent)
                    .frame(maxWidth: .infinity)
            }
            if men && women {
                LinearGradient(colors: [line.opacity(0), line, line.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(width: 2, height: 128 * s)
            }
            if men {
                OccasionVenue(label: "الرجال", place: value("menPlace"), area: value("menArea"), times: value("menTimes"),
                              scale: s, accent: accent)
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

/// كبسولة حول نص (padding + خلفية + إطار + box-shadow). الظل مثل CSS: برا الكبسولة فقط،
/// حتى لو الخلفية شبه شفافة (ظل SwiftUI العادي ياخذ شفافية الشكل فيختفي).
struct OccasionPillBox: ViewModifier {
    let padTop: CGFloat
    let padSide: CGFloat
    let padBottom: CGFloat
    /// الخلفية (لون أو تدرّج مقصوص بكبسولة)
    let fill: AnyView
    var border: Color? = nil
    var shadow: Color = .clear
    var shadowRadius: CGFloat = 0
    var shadowY: CGFloat = 0
    /// ظل ثاني صغير (مثل 0 2px 5px)
    var shadow2: Color = .clear
    var shadow2Radius: CGFloat = 0
    var shadow2Y: CGFloat = 0

    func body(content: Content) -> some View {
        let bw: CGFloat = border == nil ? 0 : 1
        return content
            .padding(.top, padTop + bw)
            .padding(.bottom, padBottom + bw)
            .padding(.horizontal, padSide + bw)
            .background(
                ZStack {
                    Capsule()
                        .fill(Color.black)
                        .shadow(color: shadow, radius: shadowRadius, x: 0, y: shadowY)
                        .shadow(color: shadow2, radius: shadow2Radius, x: 0, y: shadow2Y)
                        .mask(
                            ZStack {
                                Rectangle().padding(-200)
                                Capsule().blendMode(.destinationOut)
                            }
                            .compositingGroup()
                        )
                    fill
                    if let border {
                        Capsule().strokeBorder(border, lineWidth: 1)
                    }
                }
            )
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

/// فاصل: خطين يتلاشون + سداسي صغير (svg 16×18، المضلع من 1 إلى 15 / 17)
struct OccasionDivider: View {
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            LinearGradient(colors: [color.opacity(0), color], startPoint: .leading, endPoint: .trailing)
                .frame(width: 72, height: 2)
            OccasionHexagon()
                .stroke(color, lineWidth: 1.8)
                .frame(width: 14, height: 16)
                .padding(1)
            LinearGradient(colors: [color, color.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 72, height: 2)
        }
    }
}

/// الصورة تغطي المساحة (object-fit: cover) مع التكبير والموضع، أو ظل شخص لو ما فيه صورة
struct OccasionPhotoFill: View {
    let photo: OccasionPhoto
    let avatar: OccasionAvatar
    let width: CGFloat
    let height: CGFloat
    var forceGray = false

    var body: some View {
        Group {
            if let ui = photo.image, ui.size.width > 0, ui.size.height > 0 {
                let s = max(width / ui.size.width, height / ui.size.height) * max(photo.zoom, 1)
                let dw = ui.size.width * s
                let dh = ui.size.height * s
                ZStack(alignment: .topLeading) {
                    Color.clear
                    Image(uiImage: ui)
                        .resizable()
                        .frame(width: dw, height: dh)
                        .offset(x: (width - dw) * photo.x / 100, y: (height - dh) * photo.y / 100)
                }
                .frame(width: width, height: height, alignment: .topLeading)
                .grayscale(photo.gray || forceGray ? 1 : 0)
            } else {
                OccasionAvatarView(style: avatar)
            }
        }
        .frame(width: width, height: height)
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

    var body: some View {
        let width = 560 * k
        let height = 600 * k
        let pw = 398.4 * k
        let ph = 460 * k
        return ZStack(alignment: .topLeading) {
            OccasionPhotoFill(photo: photo, avatar: avatar, width: pw, height: ph, forceGray: forceGray)
                .clipShape(OccasionHexagon())
                .compositingGroup()
                .shadow(color: shadow, radius: 14, x: 0, y: 18)
                .offset(x: 80.8 * k, y: 70 * k)
            if let frame {
                Image(uiImage: frame).resizable().frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
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

/// عمود مكان العزاء (الرجال / النساء) — من اليسار: المكان والمنطقة، الدبوس، «عــزاء الرجال» والأوقات
struct OccasionVenue: View {
    let label: String
    let place: String
    let area: String
    let times: String
    let scale: CGFloat
    /// لون «عــزاء …» والدبوس (نموذج ٢ ذهبي، نموذج ١ أبيض)
    var accent: Color = OccasionDeathPalette.gold

    var body: some View {
        let P = OccasionDeathPalette.self
        let s = scale
        let hasArea = !area.trimmingCharacters(in: .whitespaces).isEmpty
        // عرض كتلة المكان = عرض محتواها (بحد أقصى 250 مثل max-width)؛ المنطقة ما تنكسر وتطلع لليسار إذا طالت
        let placeLayout = OccasionTextLayout.make(place, weight: .extrabold, size: 29 * s, maxWidth: 250 * s, wrap: .normal)
        let areaLayout = OccasionTextLayout.make(hasArea ? area : "", weight: .regular, size: 23 * s,
                                                 maxWidth: .greatestFiniteMagnitude, wrap: .normal)
        let placeW = min(250 * s, max(placeLayout.width(.extrabold), areaLayout.width(.regular)).rounded(.up))
        return HStack(alignment: .center, spacing: 12 * s) {
            // align-items: flex-start في RTL = يمين
            VStack(alignment: .trailing, spacing: 4 * s) {
                OccasionLines(place, .extrabold, 29 * s, lineHeight: 1.28, color: .white, maxWidth: 250 * s, alignment: .trailing)
                if hasArea {
                    // white-space: nowrap
                    OccasionLines(area, .regular, 23 * s, lineHeight: 1.3, color: P.grey, maxWidth: .greatestFiniteMagnitude)
                }
            }
            .frame(width: placeW, alignment: .trailing)
            OccasionPin(color: accent)
                .frame(width: 54 * s, height: 54 * s)
            // line-height: 1.15 للكتلة كلها
            VStack(spacing: 0) {
                OccasionLines("عــزاء", .semibold, 29 * s, lineHeight: 1.15, color: accent, maxWidth: .greatestFiniteMagnitude)
                OccasionLines(label, .semibold, 29 * s, lineHeight: 1.15, color: accent, maxWidth: .greatestFiniteMagnitude)
                if !times.trimmingCharacters(in: .whitespaces).isEmpty {
                    OccasionLines(times, .regular, 22 * s, lineHeight: 1.15, color: P.grey, maxWidth: .greatestFiniteMagnitude)
                        .padding(.top, 8 * s)
                }
            }
            .fixedSize()
        }
    }
}

/// دبوس الموقع داخل دائرة (نفس رسمة الموقع، مقاس 64)
struct OccasionPin: View {
    let color: Color

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
                    .fill(OccasionDeathPalette.root)
                    .frame(width: 9.2 * s, height: 9.2 * s)
                    .position(x: 32 * s, y: 27.4 * s)
            }
            .frame(width: 64 * s, height: 64 * s)
        }
    }
}

enum OccasionText {
    /// ظل نصوص مشاركة العزاء: 0 2px 0 rgba(255,255,255,.95), 0 12px 24px rgba(27,32,38,.20)
    static func lightShadow(_ k: CGFloat = 1) -> [OccasionTextShadow] {
        [.lift(0.95, y: 2 * k),
         OccasionTextShadow(y: 12 * k, blur: 24 * k, color: Color(red: 27 / 255, green: 32 / 255, blue: 38 / 255).opacity(0.20))]
    }

    /// التنوين والحركات على آخر حرف تطلع مزاحة بخط URW (ما فيه مواضع لها) — نشيلها من نص البوست،
    /// و«المحمد علي» (وعبد/أبو + الاسم) ما ينقسمون على سطرين. نفس postText في الموقع.
    static func postText(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: s.unicodeScalars.filter { !((0x064B...0x0652).contains($0.value) || $0.value == 0x0670) })
        var out = String(scalars)
        out = out.replacingOccurrences(of: "المحمد\\s+علي", with: "المحمد\u{00A0}علي", options: .regularExpression)
        out = out.replacingOccurrences(of: "(^|[\\s،(])(عبد|أبو|ابو|بو)\\s+(?=\\S)", with: "$1$2\u{00A0}", options: .regularExpression)
        return out
    }
}
