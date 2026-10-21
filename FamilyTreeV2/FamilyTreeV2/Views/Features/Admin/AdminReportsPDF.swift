import UIKit

// MARK: - رسم تقارير العائلة الرسمية (PDF) — «رسمي بهوية العائلة» (طلب المالك ٢٠٢٦-١٠-٢٠)
//
// تصميم أبيض (طلب المالك «ابي تصميم ابيض اكثر» و«ابيض بدال الكريمي»): ورق أبيض خالص بلا كريمي ولا رملي.
// A4 عمودي. الغلاف اختياري لسجل الأعضاء، وهو أبيض: شعار العائلة الحديث (`FamilyLogoNavy` — خط «المحمدعلي» الكحلي، من أصله
// المتّجه بدقّة ×٤) في الوسط، ثم عنوان التقرير ونطاقه بالكحلي، وسدو ذهبي رفيع تحته، وبيانات صغيرة رمادية (التاريخ بتوقيت الكويت،
// من أعدّه، النطاق، العدد)، وفقرة ما يحويه، وشارة محدّدة صغيرة «سرّي — لعائلة المحمدعلي فقط». كل صفحة بعدها:
// رأس رفيع (عنوان التقرير بالكحلي + الشعار صغيراً + خطّ كحلي شعري)، وتذييل سطر واحد: الختم رمادياً صغيراً يميناً و«صفحة
// X من Y» يساراً — والغلاف يُعدّ الصفحة الأولى (بلا تذييل).
// ملاحظة: الشعار داخل التطبيق ما زال `AppIconImage` (مؤجّل عمداً) — الملف وحده يحمل الشعار الحديث.
// الخط خط التطبيق نفسه (IBM Plex Sans Arabic، مسجّل في `UIAppFonts` — نفس أسماء `DS.Font.Plex`) والنص عربي من
// اليمين، والتشكيل (وصل الحروف) من CoreText. الجداول بصفوف متناوبة وعنوان يتكرّر أعلى كل صفحة، والأسماء الطويلة
// تلتفّ (لا قصّ). الأعمدة ما اختاره المالك في «البيانات:»: كل عمود بعرض أطول محتواه والاسم يأخذ ما بقي (`plan`). الورقة فاتحة دائماً فلا تتبع الوضع الداكن — ألوانها هنا (ألوان طباعة، مثل رسم الـ Canvas).
// يعمل خارج الخيط الرئيسي: قياس ثم توزيع على الصفحات (فيُعرف العدد الكلي قبل الرسم)، ثم الرسم، مع فحص الإلغاء.

nonisolated enum AdminReportPDF {

    struct Output: Sendable {
        let data: Data
        let pages: Int
    }

    struct Cancelled: Error {}

    // MARK: الورقة

    static let pageSize = CGSize(width: 595.28, height: 841.89)
    private static let margin: CGFloat = 36
    /// رأس الصفحات الداخلية: سطر (العنوان + الشعار) ثم خطّ كحلي شعري
    private static let headerTop: CGFloat = 20
    /// نقطة PDF = 1/72 بوصة: 19 هنا ≈ 6.7 مم مطبوعة — أكبر فعلياً من حدّ الشعار في الشاشة (32pt ≈ 5 مم)، وحوله
    /// ربع ارتفاعه فراغاً على الأقل (قاعدة الشعار في CLAUDE.md)
    private static let headerLogoHeight: CGFloat = 19
    private static let headerRule: CGFloat = headerTop + headerLogoHeight + 7
    private static let contentTop: CGFloat = headerRule + 14
    private static let footerLine: CGFloat = pageSize.height - 34
    private static let contentBottom: CGFloat = footerLine - 12
    private static var contentWidth: CGFloat { pageSize.width - margin * 2 }
    private static var right: CGFloat { pageSize.width - margin }

    // MARK: ألوان الطباعة (ثابتة — الورقة بيضاء دائماً)

    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
    /// كحلي العائلة (لون الشعار نفسه)
    private static let navy = rgb(0x172536)
    private static let navyLight = rgb(0x2A3E5C)
    /// الكحلي الأساسي (الرجال، الأعمدة)
    private static let brand = rgb(0x1F4E79)
    private static let gold = rgb(0xB89A5A)
    /// صفوف متناوبة: رمادي يكاد يكون أبيض (لا كريمي)
    private static let zebra = rgb(0xF6F7F9)
    /// إطارات خفيفة (المربّعات، التذييل)
    private static let line = rgb(0xE4E7EC)
    /// فاصل الصفوف
    private static let rowLine = rgb(0xEDEFF2)
    private static let ink = rgb(0x172536)
    private static let muted = rgb(0x5F6B78)
    private static let faint = rgb(0x8A94A0)
    private static let track = rgb(0xE9ECF0)
    private static let deceased = rgb(0xB5BAC1)
    private static let warning = rgb(0x9A6A0A)
    private static let success = rgb(0x157F3C)
    private static let slate = rgb(0x7A8794)
    private static let female = rgb(0xC85A80)
    private static let secret = rgb(0x9A3B2E)

    private static func color(_ tone: AdminReportTone) -> UIColor {
        switch tone {
        case .normal: return ink
        case .muted: return muted
        case .warning: return warning
        case .men: return brand
        case .women: return female
        case .total: return navy
        case .registered: return success
        case .treeOnly: return slate
        }
    }

    // MARK: الخط — URW Geometric Arabic (خط النظام احتياطاً)

    private static func plex(_ weight: String, _ size: CGFloat) -> UIFont {
        AppTypeface.uiFont(size: size, weight: weight == "Bold" ? .bold : weight == "SemiBold" ? .semibold : weight == "Medium" ? .medium : .regular)
    }
    private static let fBody = plex("Regular", 9.5)
    private static let fBodyBold = plex("SemiBold", 9.5)
    private static let fHead = plex("SemiBold", 9)
    /// جدول بأعمدة كثيرة لا تتّسع بالخط العادي (`plan`)
    private static let fBodyCompact = plex("Regular", 8.5)
    private static let fBodyBoldCompact = plex("SemiBold", 8.5)
    private static let fHeadCompact = plex("SemiBold", 8)
    private static let fSmall = plex("Regular", 8.5)
    private static let fSmallBold = plex("Medium", 8.5)
    private static let fFooter = plex("Regular", 8)
    private static let fFooterBold = plex("Medium", 8)
    private static let fHeader = plex("SemiBold", 10.5)
    private static let fSection = plex("Bold", 13.5)
    private static let fPanel = plex("SemiBold", 11.5)
    private static let fTileValue = plex("Bold", 17)
    private static let fRingValue = plex("Bold", 15)
    private static let fCoverTitle = plex("Bold", 28)
    private static let fCoverScope = plex("Regular", 13)
    private static let fCoverLabel = plex("Regular", 9)
    private static let fCoverValue = plex("Medium", 9.5)
    private static let fCoverIntro = plex("Regular", 9)
    private static let fSecret = plex("SemiBold", 9)

    private static func lineH(_ font: UIFont) -> CGFloat { ceil(font.lineHeight) }

    // MARK: النص

    private static func attrs(_ font: UIFont, _ color: UIColor, align: NSTextAlignment, ltr: Bool,
                              wrap: Bool) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.alignment = align
        p.baseWritingDirection = ltr ? .leftToRight : .rightToLeft
        p.lineBreakMode = wrap ? .byWordWrapping : .byTruncatingTail
        return [.font: font, .foregroundColor: color, .paragraphStyle: p]
    }

    /// سطر واحد (يُختصر بنقاط إن ضاق — الأعمدة مقاسة بعرض يكفي محتواها) أو نص يلتفّ
    private static func draw(_ text: String, in rect: CGRect, font: UIFont, color: UIColor,
                             align: NSTextAlignment = .right, ltr: Bool = false, wrap: Bool = false) {
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                attributes: attrs(font, color, align: align, ltr: ltr, wrap: wrap), context: nil)
    }

    private static func textHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
        // تقدير سريع: النص القصير سطر واحد بلا قياس (آلاف الصفوف)
        if CGFloat(text.count) * font.pointSize * 0.62 < width { return lineH(font) }
        let r = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                options: [.usesLineFragmentOrigin],
                                                attributes: attrs(font, ink, align: .right, ltr: false, wrap: true),
                                                context: nil)
        return max(lineH(font), ceil(r.height))
    }

    // MARK: الرسم الكامل

    static func render(_ doc: AdminReportDoc, isCancelled: () -> Bool = { false }) throws -> Output {
        let laid = try layout(doc.blocks, compact: doc.kind == .register && doc.options.compactRows, isCancelled: isCancelled)
        let coverPages = doc.options.includeCover ? 1 : 0
        let total = laid.count + coverPages
        let vector = familyLogo()
        let logo = vector.flatMap { raster($0, height: coverLogoWidth * $0.size.height / max($0.size.width, 1)) }
        let smallLogo = vector.flatMap { raster($0, height: headerLogoHeight) }
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: doc.title,
            kCGPDFContextAuthor as String: AdminReportText.familyName,
            kCGPDFContextCreator as String: "FamilyTreeV2",
            kCGPDFContextSubject as String: doc.summaryLine
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        var cancelled = false
        let data = renderer.pdfData { ctx in
            if doc.options.includeCover {
                ctx.beginPage()
                drawCover(doc, total: total, logo: logo)
            }
            for (i, items) in laid.enumerated() {
                if isCancelled() { cancelled = true; return }
                ctx.beginPage()
                drawHeader(doc.title, logo: smallLogo)
                for item in items { drawItem(item) }
                drawFooter(page: i + 1 + coverPages, total: total)
            }
        }
        if cancelled { throw Cancelled() }
        return Output(data: data, pages: total)
    }

    // MARK: التوزيع على الصفحات

    /// خطوط الجدول ومسافته الأفقية — العادي، أو المضغوط إن كثرت الأعمدة (`plan`)
    private struct TableStyle {
        let body: UIFont
        let bold: UIFont
        let head: UIFont
        let padX: CGFloat
        let padY: CGFloat

        static let regular = TableStyle(body: fBody, bold: fBodyBold, head: fHead, padX: 6, padY: 4.5)
        static let dense = TableStyle(body: fBodyCompact, bold: fBodyBoldCompact, head: fHeadCompact, padX: 4, padY: 3.25)
        static let compact = TableStyle(body: fBodyCompact, bold: fBodyBoldCompact, head: fHeadCompact, padX: 4, padY: 4.5)
    }

    /// مقاسات أعمدة جدول (بترتيب الأعمدة) وخطّه
    private struct ColumnPlan {
        let widths: [CGFloat]
        let style: TableStyle
    }

    private final class TableLayout {
        let table: AdminReportTable
        /// موضع كل عمود (من اليمين: الأول في اليمين)
        let frames: [(x: CGFloat, w: CGFloat)]
        let style: TableStyle
        let headerH: CGFloat
        var rowH: [CGFloat] = []
        var footerH: CGFloat = 0


        /// `plan`: مقاسات من المحتوى (جدول بعمود `fill`) — nil = نِسَب `weight`
        init(_ table: AdminReportTable, plan: ColumnPlan?, compact: Bool) {
            self.table = table
            style = plan?.style ?? (compact ? .dense : .regular)
            let widths: [CGFloat]
            if let plan {
                widths = plan.widths
            } else {
                let sum = table.columns.reduce(0) { $0 + $1.weight }
                widths = table.columns.map {
                    (AdminReportPDF.contentWidth * CGFloat($0.weight / max(sum, 0.0001))).rounded(.down)
                }
            }
            var x = AdminReportPDF.right
            var frames: [(x: CGFloat, w: CGFloat)] = []
            for w in widths {
                x -= w
                frames.append((x: x, w: w))
            }
            self.frames = frames
            var h: CGFloat = 0
            for (i, c) in table.columns.enumerated() {
                h = max(h, AdminReportPDF.textHeight(c.title, width: frames[i].w - style.padX * 2, font: style.head))
            }
            headerH = h + style.padY * 2 + 2
        }

        func measure(_ row: AdminReportTable.Row, font: UIFont) -> CGFloat {
            var h = AdminReportPDF.lineH(font)
            for (i, c) in table.columns.enumerated() where c.wraps && i < row.cells.count {
                h = max(h, AdminReportPDF.textHeight(row.cells[i], width: frames[i].w - style.padX * 2, font: font))
            }
            return h + style.padY * 2
        }
    }

    // MARK: مقاسات الأعمدة من المحتوى (الأعمدة المختارة في «البيانات:»)

    /// أقلّ عرض للاسم (نسبة من عرض الصفحة) — بالخط العادي ثم المضغوط
    private static let fillMinRegular: CGFloat = 0.30
    private static let fillMinCompact: CGFloat = 0.22
    /// ما دام الاسم بهذا العرض أو أكثر تتّسع الأعمدة الأخرى (العنوان سطر واحد، النص بلا التفاف)
    private static let fillComfort: CGFloat = 0.42
    /// عمود يلتفّ (الفرع، الحالة، الملاحظة) لا يزيد مبدئياً عن هذا قبل أن يلتفّ
    private static let wrapCap: CGFloat = 0.22

    private static func signature(_ t: AdminReportTable) -> String { t.columns.map(\.title).joined(separator: "|") }

    /// جداول بعمود `fill` (الاسم): كل عمود بعرض أطول محتواه (والعنوان على سطرين إن لزم)، والاسم يأخذ ما بقي.
    /// إن ضاقت الصفحة: تلتفّ الأعمدة القابلة للالتفاف حتى أطول كلمة، ثم الخط المضغوط، ثم (آخر حلّ) تصغر الأعمدة بالنسبة.
    /// تُحسب مرة لكل مجموعة جداول بالأعمدة نفسها — جداول الفروع كلها بمقاس واحد.
    private static func plan(_ tables: [AdminReportTable], compact: Bool) -> ColumnPlan? {
        guard let columns = tables.first?.columns, let fill = columns.firstIndex(where: \.fill) else { return nil }
        return plan(tables, columns: columns, fill: fill, compact: compact, dense: compact)
            ?? plan(tables, columns: columns, fill: fill, compact: true, dense: compact)
    }

    private static func plan(_ tables: [AdminReportTable], columns: [AdminReportTable.Column], fill: Int,
                             compact: Bool, dense: Bool) -> ColumnPlan? {
        let style = compact ? (dense ? TableStyle.dense : .compact) : .regular
        var cache: [String: CGFloat] = [:]
        // مفتاح الذاكرة بالخط (نفس النص بخط آخر عرضه آخر)
        func width(_ s: String, _ font: UIFont) -> CGFloat {
            let key = "\(font.fontName)\(font.pointSize)|\(s)"
            if let w = cache[key] { return w }
            let w = ceil((s as NSString).size(withAttributes: [.font: font]).width)
            cache[key] = w
            return w
        }
        func longestWord(_ s: String, _ font: UIFont) -> CGFloat {
            s.split(separator: " ").map { width(String($0), font) }.max() ?? width(s, font)
        }
        /// العنوان على سطرين بأفضل قسمة
        func twoLines(_ s: String, _ font: UIFont) -> CGFloat {
            let words = s.split(separator: " ").map(String.init)
            guard words.count > 1 else { return width(s, font) }
            return (1..<words.count).map { k in
                max(width(words[..<k].joined(separator: " "), font), width(words[k...].joined(separator: " "), font))
            }.min() ?? width(s, font)
        }

        let pad = style.padX * 2 + 1
        let others = columns.indices.filter { $0 != fill }
        var nat = [CGFloat](repeating: 0, count: columns.count)
        var low = nat
        var full = nat
        for i in others {
            let c = columns[i]
            var cellNat: CGFloat = 0
            var cellWord: CGFloat = 0
            for t in tables {
                for row in t.rows where i < row.cells.count && !row.cells[i].isEmpty {
                    cellNat = max(cellNat, width(row.cells[i], style.body))
                    if c.wraps { cellWord = max(cellWord, longestWord(row.cells[i], style.body)) }
                }
                if let f = t.footer, i < f.cells.count, !f.cells[i].isEmpty {
                    cellNat = max(cellNat, width(f.cells[i], style.bold))
                    if c.wraps { cellWord = max(cellWord, longestWord(f.cells[i], style.bold)) }
                }
            }
            let cellLow = c.wraps ? cellWord : cellNat
            let headTwo = twoLines(c.title, style.head)
            nat[i] = max(c.wraps ? min(cellNat, contentWidth * wrapCap) : cellNat, cellLow, headTwo) + pad
            low[i] = max(cellLow, longestWord(c.title, style.head)) + pad
            full[i] = max(nat[i], cellNat + pad, width(c.title, style.head) + pad)
        }

        let minFill = contentWidth * (compact ? fillMinCompact : fillMinRegular)
        var w = nat
        var total = others.reduce(0) { $0 + w[$1] }
        if total + minFill > contentWidth {
            let deficit = total + minFill - contentWidth
            let slack = others.reduce(0) { $0 + (nat[$1] - low[$1]) }
            if slack >= deficit, slack > 0 {
                for i in others { w[i] -= (nat[i] - low[i]) * deficit / slack }
            } else if !compact {
                return nil
            } else {
                // آخر حلّ: الأعمدة كلها بالنسبة (قد يُختصر نص بنقاط)
                let lowSum = others.reduce(0) { $0 + low[$1] }
                let k = min(1, (contentWidth - minFill) / max(lowSum, 1))
                for i in others { w[i] = (low[i] * k).rounded(.down) }
            }
        } else {
            // سعة: يتّسع كل عمود لنصّه كاملاً (والعنوان سطراً واحداً) ما دام الاسم مرتاحاً
            for i in others where full[i] > w[i] {
                let room = contentWidth - total - contentWidth * fillComfort
                guard room > 0 else { break }
                let grow = min(full[i] - w[i], room)
                w[i] += grow
                total += grow
            }
        }
        for i in others { w[i] = ceil(w[i]) }
        total = others.reduce(0) { $0 + w[$1] }
        w[fill] = (contentWidth - total).rounded(.down)
        return ColumnPlan(widths: w, style: style)
    }

    private enum Item {
        case block(AdminReportBlock, y: CGFloat, h: CGFloat)
        case header(TableLayout, y: CGFloat)
        case row(TableLayout, Int, y: CGFloat)
        case footer(TableLayout, y: CGFloat)
    }

    private static let blockGap: CGFloat = 12

    private static func layout(_ blocks: [AdminReportBlock], compact: Bool, isCancelled: () -> Bool) throws -> [[Item]] {
        var pages: [[Item]] = [[]]
        var y = contentTop
        func newPage() {
            pages.append([])
            y = contentTop
        }
        func fits(_ h: CGFloat) -> Bool { y + h <= contentBottom }

        // مقاسات الأعمدة من المحتوى — مرة لكل مجموعة جداول بالأعمدة نفسها
        var groups: [String: [AdminReportTable]] = [:]
        for b in blocks {
            if case let .table(t) = b, t.columns.contains(where: \.fill) { groups[signature(t), default: []].append(t) }
        }
        var plans: [String: ColumnPlan] = [:]
        for (key, list) in groups {
            plans[key] = plan(list, compact: compact)
            if isCancelled() { throw Cancelled() }
        }

        // جداول مقاسة مسبقاً (للإبقاء على العنوان مع أول صفّين)
        var tables: [Int: TableLayout] = [:]
        for (i, b) in blocks.enumerated() {
            guard case let .table(t) = b else { continue }
            let l = TableLayout(t, plan: plans[signature(t)], compact: compact)
            l.rowH = t.rows.map { l.measure($0, font: l.style.body) }
            if let f = t.footer { l.footerH = l.measure(f, font: l.style.bold) }
            tables[i] = l
            if isCancelled() { throw Cancelled() }
        }

        for (i, b) in blocks.enumerated() {
            if let l = tables[i] {
                // العنوان يتكرّر أعلى كل صفحة
                if !fits(l.headerH + (l.rowH.first ?? 0)) { newPage() }
                pages[pages.count - 1].append(.header(l, y: y))
                y += l.headerH
                for (r, h) in l.rowH.enumerated() {
                    if !fits(h) {
                        newPage()
                        pages[pages.count - 1].append(.header(l, y: y))
                        y += l.headerH
                    }
                    pages[pages.count - 1].append(.row(l, r, y: y))
                    y += h
                }
                if l.footerH > 0 {
                    if !fits(l.footerH) { newPage() }
                    pages[pages.count - 1].append(.footer(l, y: y))
                    y += l.footerH
                }
                y += blockGap
                continue
            }
            let h = measure(b)
            var need = h
            if case .heading = b, i + 1 < blocks.count {
                // العنوان لا يبقى وحده أسفل الصفحة: معه عنوان الجدول وأول صفّين (أو الكتلة التالية)
                if let next = tables[i + 1] {
                    need += next.headerH + next.rowH.prefix(2).reduce(0, +)
                } else {
                    need += measure(blocks[i + 1])
                }
            }
            if !fits(need) && y > contentTop { newPage() }
            pages[pages.count - 1].append(.block(b, y: y, h: h))
            y += h
            if case .heading = b { y += 4 } else { y += blockGap }
        }
        if pages.last?.isEmpty == true && pages.count > 1 { pages.removeLast() }
        return pages
    }

    // MARK: مقاسات الكتل

    private static let tileHeight: CGFloat = 52
    private static let ringsHeight: CGFloat = 150
    private static let barRow: CGFloat = 20
    private static let barLabelWidth: CGFloat = 130
    private static let barValueWidth: CGFloat = 100
    private static let splitHeight: CGFloat = 62
    private static let miniTreeHeight: CGFloat = 148

    private static func measure(_ b: AdminReportBlock) -> CGFloat {
        switch b {
        case .tiles: return tileHeight
        case let .heading(title, subtitle, panel):
            let f = panel ? fPanel : fSection
            var h = (panel ? 2 : 8) + textHeight(title, width: contentWidth - 12, font: f)
            if let subtitle { h += 2 + textHeight(subtitle, width: contentWidth - 12, font: fSmall) }
            return h + 4
        case .table: return 0
        case let .note(text, _): return textHeight(text, width: contentWidth - 20, font: fBody) + 12
        case .rings: return ringsHeight
        case let .bars(rows, _, _, _): return 18 + CGFloat(rows.count) * barRow
        case .split: return splitHeight
        case .miniTree: return miniTreeHeight
        }
    }

    // MARK: رسم عنصر

    private static func drawItem(_ item: Item) {
        switch item {
        case let .block(b, y, h): drawBlock(b, y: y, h: h)
        case let .header(l, y): drawTableHeader(l, y: y)
        case let .row(l, r, y): drawRow(l, l.table.rows[r], index: r, y: y, h: l.rowH[r], font: l.style.body)
        case let .footer(l, y):
            if let f = l.table.footer { drawRow(l, f, index: -1, y: y, h: l.footerH, font: l.style.bold, total: true) }
        }
    }

    private static func drawBlock(_ b: AdminReportBlock, y: CGFloat, h: CGFloat) {
        switch b {
        case let .tiles(tiles): drawTiles(tiles, y: y)
        case let .heading(title, subtitle, panel): drawHeading(title, subtitle: subtitle, panel: panel, y: y)
        case let .note(text, tone): drawNote(text, tone: tone, y: y, h: h)
        case let .rings(rings): drawRings(rings, y: y)
        case let .bars(rows, firstLabel, secondLabel, tone):
            drawBars(rows, firstLabel: firstLabel, secondLabel: secondLabel, tone: tone, y: y)
        case let .split(split): drawSplit(split, y: y)
        case let .miniTree(tree): drawMiniTree(tree, y: y)
        case .table: break
        }
    }

    // MARK: الجدول

    private static func drawTableHeader(_ l: TableLayout, y: CGFloat) {
        // أبيض: نص كحلي وخطّ كحلي تحته
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: l.headerH)
        navy.setFill()
        UIRectFill(CGRect(x: margin, y: rect.maxY - 0.9, width: contentWidth, height: 0.9))
        for (i, c) in l.table.columns.enumerated() {
            let f = l.frames[i]
            let pad = l.style.padX
            let h = textHeight(c.title, width: f.w - pad * 2, font: l.style.head)
            draw(c.title, in: CGRect(x: f.x + pad, y: y + (l.headerH - h) / 2, width: f.w - pad * 2, height: h + 1),
                 font: l.style.head, color: navy, align: c.centered ? .center : .right, wrap: true)
        }
    }

    private static func drawRow(_ l: TableLayout, _ row: AdminReportTable.Row, index: Int, y: CGFloat, h: CGFloat,
                                font: UIFont, total: Bool = false) {
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: h)
        if total {
            navy.setFill()
            UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 0.8))
        } else if index % 2 == 1 {
            zebra.setFill()
            UIRectFill(rect)
        }
        if !total {
            rowLine.setFill()
            UIRectFill(CGRect(x: margin, y: rect.maxY - 0.4, width: contentWidth, height: 0.4))
        }
        let single = lineH(font)
        for (i, c) in l.table.columns.enumerated() where i < row.cells.count {
            let text = row.cells[i]
            guard !text.isEmpty else { continue }
            let f = l.frames[i]
            let pad = l.style.padX
            let w = f.w - pad * 2
            let tint = row.tones[i].map { AdminReportPDF.color($0) } ?? ink
            let align: NSTextAlignment = c.centered ? .center : .right
            if c.wraps {
                let th = h > single + l.style.padY * 2 + 1 ? textHeight(text, width: w, font: font) : single
                draw(text, in: CGRect(x: f.x + pad, y: y + (h - th) / 2, width: w, height: th + 1),
                     font: font, color: tint, align: align, wrap: true)
            } else {
                draw(text, in: CGRect(x: f.x + pad, y: y + (h - single) / 2, width: w, height: single + 1),
                     font: font, color: tint, align: align, ltr: c.ltr)
            }
        }
    }

    // MARK: الكتل

    private static func drawTiles(_ tiles: [AdminReportTile], y: CGFloat) {
        guard !tiles.isEmpty else { return }
        let gap: CGFloat = 8
        let w = (contentWidth - gap * CGFloat(tiles.count - 1)) / CGFloat(tiles.count)
        for (i, t) in tiles.enumerated() {
            let x = right - CGFloat(i + 1) * w - CGFloat(i) * gap
            let rect = CGRect(x: x, y: y, width: w, height: tileHeight)
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.4, dy: 0.4), cornerRadius: 8)
            line.setStroke()
            path.lineWidth = 0.8
            path.stroke()
            draw(t.value, in: CGRect(x: x + 4, y: y + 6, width: w - 8, height: lineH(fTileValue)),
                 font: fTileValue, color: navy, align: .center)
            draw(t.label, in: CGRect(x: x + 4, y: y + 8 + lineH(fTileValue) - 4, width: w - 8, height: lineH(fSmall)),
                 font: fSmall, color: muted, align: .center)
        }
    }

    private static func drawHeading(_ title: String, subtitle: String?, panel: Bool, y: CGFloat) {
        let font = panel ? fPanel : fSection
        let top = y + (panel ? 2 : 8)
        let th = textHeight(title, width: contentWidth - 12, font: font)
        if !panel {
            gold.setFill()
            UIBezierPath(roundedRect: CGRect(x: right - 3, y: top + 3, width: 3, height: th - 6), cornerRadius: 1.5).fill()
        }
        draw(title, in: CGRect(x: margin, y: top, width: contentWidth - (panel ? 0 : 10), height: th + 1),
             font: font, color: navy, wrap: true)
        if let subtitle {
            let sh = textHeight(subtitle, width: contentWidth - 12, font: fSmall)
            draw(subtitle, in: CGRect(x: margin, y: top + th + 2, width: contentWidth - (panel ? 0 : 10), height: sh + 1),
                 font: fSmall, color: muted, wrap: true)
        }
    }

    private static func drawNote(_ text: String, tone: AdminReportTone, y: CGFloat, h: CGFloat) {
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: h)
        let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.4, dy: 0.4), cornerRadius: 6)
        if tone == .warning {
            // تنبيه: إطار كهرماني على الأبيض
            warning.withAlphaComponent(0.55).setStroke()
            path.lineWidth = 0.8
            path.stroke()
        } else {
            zebra.setFill()
            path.fill()
        }
        draw(text, in: rect.insetBy(dx: 10, dy: 6), font: fBody, color: color(tone), wrap: true)
    }

    private static func drawRings(_ rings: [AdminReportRing], y: CGFloat) {
        guard !rings.isEmpty else { return }
        let w = contentWidth / CGFloat(rings.count)
        for (i, ring) in rings.enumerated() {
            let x = right - CGFloat(i + 1) * w
            draw(ring.title, in: CGRect(x: x, y: y, width: w, height: lineH(fBodyBold)),
                 font: fBodyBold, color: navy, align: .center)
            let center = CGPoint(x: x + w / 2, y: y + 22 + 44)
            let radius: CGFloat = 40
            let lw: CGFloat = 11
            let full = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            full.lineWidth = lw
            if !ring.available {
                track.setStroke()
                full.setLineDash([3, 3], count: 2, phase: 0)
                full.stroke()
                draw("غير متاح", in: CGRect(x: center.x - radius, y: center.y - lineH(fSmall) / 2,
                                            width: radius * 2, height: lineH(fSmall)),
                     font: fSmall, color: faint, align: .center)
                continue
            }
            let total = ring.living + ring.deceased
            track.setStroke()
            full.stroke()
            if total > 0 {
                let start = -CGFloat.pi / 2
                let liveEnd = start + .pi * 2 * CGFloat(ring.living) / CGFloat(total)
                if ring.living > 0 {
                    let p = UIBezierPath(arcCenter: center, radius: radius, startAngle: start, endAngle: liveEnd, clockwise: true)
                    p.lineWidth = lw
                    color(ring.tone).setStroke()
                    p.stroke()
                }
                if ring.deceased > 0 {
                    let p = UIBezierPath(arcCenter: center, radius: radius, startAngle: liveEnd,
                                         endAngle: start + .pi * 2, clockwise: true)
                    p.lineWidth = lw
                    deceased.setStroke()
                    p.stroke()
                }
            }
            let vh = lineH(fRingValue)
            draw(AdminReportText.num(total), in: CGRect(x: center.x - radius, y: center.y - vh / 2 - 5,
                                                         width: radius * 2, height: vh),
                 font: fRingValue, color: navy, align: .center)
            draw(AdminReportText.peopleNoun(total), in: CGRect(x: center.x - radius, y: center.y + vh / 2 - 7, width: radius * 2, height: lineH(fSmall)),
                 font: fSmall, color: muted, align: .center)
            let legendY = center.y + radius + lw / 2 + 8
            legend([("أحياء \(AdminReportText.num(ring.living)) · \(AdminReportText.percent(ring.living, of: total))", color(ring.tone)),
                    ("متوفون \(AdminReportText.num(ring.deceased))", deceased)],
                   centerX: center.x, y: legendY, maxWidth: w - 8)
        }
    }

    /// مفتاح ألوان في سطر واحد مركزي (من اليمين)
    private static func legend(_ items: [(String, UIColor)], centerX: CGFloat, y: CGFloat, maxWidth: CGFloat) {
        let a = attrs(fSmall, muted, align: .right, ltr: false, wrap: false)
        let widths = items.map { ceil(($0.0 as NSString).size(withAttributes: a).width) + 10 }
        let gap: CGFloat = 10
        let total = min(maxWidth, widths.reduce(0, +) + gap * CGFloat(items.count - 1))
        var x = centerX + total / 2
        let h = lineH(fSmall)
        for (i, item) in items.enumerated() {
            let w = widths[i]
            item.1.setFill()
            UIBezierPath(ovalIn: CGRect(x: x - 7, y: y + h / 2 - 3, width: 6, height: 6)).fill()
            draw(item.0, in: CGRect(x: x - w, y: y, width: w - 10, height: h), font: fSmall, color: muted)
            x -= w + gap
        }
    }

    private static func drawBars(_ rows: [AdminReportBar], firstLabel: String, secondLabel: String?,
                                 tone: AdminReportTone, y: CGFloat) {
        var keys: [(String, UIColor)] = [(firstLabel, color(tone))]
        if let secondLabel { keys.append((secondLabel, deceased)) }
        legend(keys, centerX: margin + contentWidth / 2, y: y, maxWidth: contentWidth)
        let maxV = max(1, rows.map { $0.first + $0.second }.max() ?? 1)
        let barX0 = margin + barValueWidth
        let barW = contentWidth - barLabelWidth - barValueWidth - 8
        let barEnd = barX0 + barW
        for (i, row) in rows.enumerated() {
            let ry = y + 18 + CGFloat(i) * barRow
            if i % 2 == 1 {
                zebra.setFill()
                UIRectFill(CGRect(x: margin, y: ry, width: contentWidth, height: barRow))
            }
            draw(row.label, in: CGRect(x: right - barLabelWidth, y: ry + (barRow - lineH(fBody)) / 2,
                                       width: barLabelWidth - 4, height: lineH(fBody)),
                 font: fBody, color: ink)
            let fw = barW * CGFloat(row.first) / CGFloat(maxV)
            let sw = barW * CGFloat(row.second) / CGFloat(maxV)
            let by = ry + barRow / 2 - 5
            track.setFill()
            UIBezierPath(roundedRect: CGRect(x: barX0, y: by, width: barW, height: 10), cornerRadius: 3).fill()
            // من اليمين: الجزء الأول ثم الثاني
            if fw > 0 {
                color(tone).setFill()
                UIBezierPath(roundedRect: CGRect(x: barEnd - fw, y: by, width: fw, height: 10), cornerRadius: 3).fill()
            }
            if sw > 0 {
                deceased.setFill()
                UIBezierPath(roundedRect: CGRect(x: barEnd - fw - sw, y: by, width: sw, height: 10), cornerRadius: 3).fill()
            }
            draw(row.caption, in: CGRect(x: margin, y: ry + (barRow - lineH(fSmall)) / 2, width: barValueWidth - 6,
                                         height: lineH(fSmall)),
                 font: fSmallBold, color: navy, align: .left)
        }
    }

    private static func drawSplit(_ s: AdminReportSplit, y: CGFloat) {
        let total = max(1, s.first + s.second)
        let barY = y + 6
        let barH: CGFloat = 16
        let rect = CGRect(x: margin, y: barY, width: contentWidth, height: barH)
        track.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 5).fill()
        let fw = contentWidth * CGFloat(s.first) / CGFloat(total)
        if fw > 0 {
            success.setFill()
            UIBezierPath(roundedRect: CGRect(x: right - fw, y: barY, width: fw, height: barH),
                         byRoundingCorners: fw >= contentWidth - 1 ? .allCorners : [.topRight, .bottomRight],
                         cornerRadii: CGSize(width: 5, height: 5)).fill()
        }
        if s.second > 0 {
            slate.setFill()
            UIBezierPath(roundedRect: CGRect(x: margin, y: barY, width: contentWidth - fw, height: barH),
                         byRoundingCorners: fw <= 1 ? .allCorners : [.topLeft, .bottomLeft],
                         cornerRadii: CGSize(width: 5, height: 5)).fill()
        }
        let ly = barY + barH + 8
        let h = lineH(fBodyBold)
        let half = contentWidth / 2
        success.setFill()
        UIBezierPath(ovalIn: CGRect(x: right - 8, y: ly + h / 2 - 4, width: 8, height: 8)).fill()
        draw("\(s.firstLabel): \(AdminReportText.num(s.first)) (\(AdminReportText.percent(s.first, of: total)))",
             in: CGRect(x: right - half, y: ly, width: half - 14, height: h), font: fBodyBold, color: ink)
        slate.setFill()
        UIBezierPath(ovalIn: CGRect(x: margin + half - 8, y: ly + h / 2 - 4, width: 8, height: 8)).fill()
        draw("\(s.secondLabel): \(AdminReportText.num(s.second)) (\(AdminReportText.percent(s.second, of: total)))",
             in: CGRect(x: margin, y: ly, width: half - 14, height: h), font: fBodyBold, color: ink)
    }

    /// المؤسس في الأعلى ← خطّ ← الفروع في سطر (الأول يميناً) وتحت كل فرع عدده وشريط بنسبته
    private static func drawMiniTree(_ tree: AdminReportMiniTree, y: CGFloat) {
        let n = max(1, tree.nodes.count)
        // المؤسس
        let fw: CGFloat = 250
        let fh: CGFloat = 44
        let founder = CGRect(x: (pageSize.width - fw) / 2, y: y + 4, width: fw, height: fh)
        let fp = UIBezierPath(roundedRect: founder.insetBy(dx: 0.6, dy: 0.6), cornerRadius: 10)
        navy.setStroke()
        fp.lineWidth = 1.2
        fp.stroke()
        let t1 = lineH(fBodyBold), t2 = lineH(fSmall)
        draw(tree.founder, in: CGRect(x: founder.minX + 8, y: founder.minY + (fh - t1 - t2) / 2, width: fw - 16, height: t1),
             font: fBodyBold, color: navy, align: .center)
        draw(tree.founderCaption, in: CGRect(x: founder.minX + 8, y: founder.minY + (fh - t1 - t2) / 2 + t1, width: fw - 16,
                                             height: t2),
             font: fSmall, color: muted, align: .center)

        // الخطوط
        let gap: CGFloat = 6
        let slot = contentWidth / CGFloat(n)
        let nodeW = slot - gap
        let busY = founder.maxY + 14
        let nodeY = busY + 14
        let centers = (0..<n).map { right - slot * (CGFloat($0) + 0.5) }
        gold.setFill()
        UIRectFill(CGRect(x: founder.midX - 0.5, y: founder.maxY, width: 1, height: busY - founder.maxY))
        if let first = centers.first, let last = centers.last {
            UIRectFill(CGRect(x: min(first, last, founder.midX), y: busY - 0.5,
                              width: max(first, last, founder.midX) - min(first, last, founder.midX), height: 1))
        }
        for cx in centers { UIRectFill(CGRect(x: cx - 0.5, y: busY, width: 1, height: nodeY - busY)) }

        // العقد
        let maxCount = max(1, tree.nodes.filter { !$0.isRest }.map(\.count).max() ?? 1)
        let nodeH = miniTreeHeight - (nodeY - y) - 4
        let titleFont = n > 6 ? fSmallBold : fBodyBold
        for (i, node) in tree.nodes.enumerated() {
            let rect = CGRect(x: centers[i] - nodeW / 2, y: nodeY, width: nodeW, height: nodeH)
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.4, dy: 0.4), cornerRadius: 8)
            path.lineWidth = 0.8
            if node.isRest { path.setLineDash([3, 2], count: 2, phase: 0) }
            (node.isRest ? faint : line).setStroke()
            path.stroke()
            let inner = rect.insetBy(dx: 5, dy: 6)
            // العدد والشريط أسفل العقدة — العنوان والسطر الصغير فوقهما بلا تداخل (اسم فرع طويل: يُترك السطر الصغير)
            let barY = inner.maxY - 5
            let countY = barY - 4 - lineH(fSmallBold)
            var ty = inner.minY
            let th = min(textHeight(node.title, width: inner.width, font: titleFont), lineH(titleFont) * 2, countY - ty)
            draw(node.title, in: CGRect(x: inner.minX, y: ty, width: inner.width, height: th + 1),
                 font: titleFont, color: navy, align: .center, wrap: true)
            ty += th
            if let caption = node.caption, ty + lineH(fFooter) <= countY {
                draw(caption, in: CGRect(x: inner.minX, y: ty, width: inner.width, height: lineH(fFooter)),
                     font: fFooter, color: muted, align: .center)
            }
            draw(AdminReportText.people(node.count), in: CGRect(x: inner.minX, y: countY, width: inner.width,
                                                                height: lineH(fSmallBold)),
                 font: fSmallBold, color: ink, align: .center)
            let barW = inner.width - 4
            track.setFill()
            UIBezierPath(roundedRect: CGRect(x: inner.minX + 2, y: barY, width: barW, height: 5), cornerRadius: 2.5).fill()
            if !node.isRest {
                let w = max(3, barW * CGFloat(node.count) / CGFloat(maxCount))
                brand.setFill()
                UIBezierPath(roundedRect: CGRect(x: inner.minX + 2 + barW - w, y: barY, width: w, height: 5),
                             cornerRadius: 2.5).fill()
            }
        }
    }

    // MARK: الرأس والتذييل

    /// عنوان التقرير بالكحلي يميناً، والشعار صغيراً يساراً، وخطّ كحلي شعري تحتهما
    private static func drawHeader(_ title: String, logo: UIImage?) {
        let h = lineH(fHeader)
        let midY = headerTop + headerLogoHeight / 2
        draw(title, in: CGRect(x: margin + contentWidth * 0.3, y: midY - h / 2, width: contentWidth * 0.7, height: h),
             font: fHeader, color: navy)
        if let logo {
            let w = headerLogoHeight * logo.size.width / max(logo.size.height, 1)
            logo.draw(in: CGRect(x: margin, y: headerTop, width: w, height: headerLogoHeight))
        }
        navy.setFill()
        UIRectFill(CGRect(x: margin, y: headerRule, width: contentWidth, height: 0.6))
    }

    /// سطر واحد: «سرّي — لعائلة المحمدعلي فقط» رمادياً صغيراً يميناً، و«صفحة X من Y» يساراً
    private static func drawFooter(page: Int, total: Int) {
        line.setFill()
        UIRectFill(CGRect(x: margin, y: footerLine, width: contentWidth, height: 0.5))
        let y = footerLine + 7
        let h = lineH(fFooterBold)
        let half = contentWidth / 2
        draw(AdminReportText.confidential, in: CGRect(x: right - half, y: y, width: half, height: h),
             font: fFooter, color: faint)
        draw("صفحة \(page) من \(total)", in: CGRect(x: margin, y: y, width: half, height: h),
             font: fFooterBold, color: muted, align: .left)
    }

    // MARK: الغلاف

    /// شعار العائلة الحديث (`FamilyLogoNavy` — رسم متّجه SVG في الأصول). النسخة الفاتحة دائماً (الكحلية) — الورقة
    /// بيضاء مهما كان وضع الجهاز.
    private static func familyLogo() -> UIImage? {
        UIImage(named: "FamilyLogoNavy", in: .main, compatibleWith: UITraitCollection(userInterfaceStyle: .light))
    }

    /// الشعار صورةً بمقاس رسمه ×٤ (~٣٠٠ نقطة/بوصة عند الطباعة) على أبيض معتم: رسم SVG في سياق PDF يصير صورة بدقّة
    /// الشاشة على أي حال — هنا الدقّة ثابتة، وبلا قناع شفافية، وصورة الرأس واحدة يعيد الملف استعمالها في كل صفحة
    private static func raster(_ logo: UIImage, height: CGFloat) -> UIImage? {
        guard logo.size.height > 0 else { return nil }
        let size = CGSize(width: (height * logo.size.width / logo.size.height).rounded(.up), height: height.rounded(.up))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 4
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            logo.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static let coverLogoWidth: CGFloat = 176

    /// السدو الكويتي (الشكل الثابت القديم: خطّان ومعيّنات خمسة، الأوسط أكبر) — ذهبي رفيع تحت عنوان الغلاف
    private static func drawSadu(centerX: CGFloat, y: CGFloat, lineLength: CGFloat, unit: CGFloat, alpha: CGFloat) {
        let small = unit, big = unit * 1.5, gap = unit * 1.25
        let diamonds: [CGFloat] = [small, small, big, small, small]
        let width = diamonds.reduce(0, +) + gap * 4
        var x = centerX - width / 2
        for (i, d) in diamonds.enumerated() {
            let c = CGPoint(x: x + d / 2, y: y)
            let r = d / 2 * 1.2
            let path = UIBezierPath()
            path.move(to: CGPoint(x: c.x, y: c.y - r))
            path.addLine(to: CGPoint(x: c.x + r, y: c.y))
            path.addLine(to: CGPoint(x: c.x, y: c.y + r))
            path.addLine(to: CGPoint(x: c.x - r, y: c.y))
            path.close()
            gold.withAlphaComponent(i == 2 ? alpha : alpha * 0.7).setFill()
            path.fill()
            x += d + gap
        }
        let lineGap = unit * 2.5
        gold.withAlphaComponent(alpha * 0.55).setFill()
        UIRectFill(CGRect(x: centerX - width / 2 - lineGap - lineLength, y: y - 0.4, width: lineLength, height: 0.8))
        UIRectFill(CGRect(x: centerX + width / 2 + lineGap, y: y - 0.4, width: lineLength, height: 0.8))
    }

    private static func drawCover(_ doc: AdminReportDoc, total: Int, logo: UIImage?) {
        let cx = pageSize.width / 2
        var y: CGFloat = 150

        // الشعار في الوسط
        if let logo {
            let w = coverLogoWidth
            let h = w * logo.size.height / max(logo.size.width, 1)
            logo.draw(in: CGRect(x: cx - w / 2, y: y, width: w, height: h))
            y += h + 44
        } else {
            draw(AdminReportText.familyName, in: CGRect(x: margin, y: y, width: contentWidth, height: lineH(fCoverTitle)),
                 font: fCoverTitle, color: navy, align: .center)
            y += lineH(fCoverTitle) + 40
        }

        // العنوان والنطاق بالكحلي
        let th = textHeight(doc.title, width: contentWidth, font: fCoverTitle)
        draw(doc.title, in: CGRect(x: margin, y: y, width: contentWidth, height: th + 1),
             font: fCoverTitle, color: navy, align: .center, wrap: true)
        y += th + 4
        if !doc.scope.isEmpty {
            let sh = textHeight(doc.scope, width: contentWidth - 60, font: fCoverScope)
            draw(doc.scope, in: CGRect(x: margin + 30, y: y, width: contentWidth - 60, height: sh + 1),
                 font: fCoverScope, color: navyLight, align: .center, wrap: true)
            y += sh
        }

        // سدو ذهبي رفيع
        y += 20
        drawSadu(centerX: cx, y: y, lineLength: 64, unit: 3.4, alpha: 1)
        y += 26

        // بيانات صغيرة رمادية
        let rows: [(String, String)] = [
            ("التاريخ", "\(AdminReportText.longDate(doc.date)) · \(AdminReportText.time(doc.date)) (توقيت الكويت)"),
            ("أعدّه", doc.generatedBy.isEmpty ? "—" : doc.generatedBy),
            ("النطاق", doc.scope.isEmpty ? "العائلة كاملة" : doc.scope),
            ("العدد", "\(AdminReportText.people(doc.count)) · \(AdminReportText.pages(total))")
        ]
        let blockW: CGFloat = 340
        let labelW: CGFloat = 64
        let bx = cx - blockW / 2
        let valueW = blockW - labelW - 8
        line.setFill()
        UIRectFill(CGRect(x: bx, y: y, width: blockW, height: 0.5))
        for r in rows {
            let vh = textHeight(r.1, width: valueW, font: fCoverValue)
            let rh = max(vh, lineH(fCoverLabel)) + 12
            draw(r.0, in: CGRect(x: bx + blockW - labelW, y: y + 6, width: labelW, height: lineH(fCoverLabel)),
                 font: fCoverLabel, color: faint)
            draw(r.1, in: CGRect(x: bx, y: y + 6, width: valueW, height: vh + 1),
                 font: fCoverValue, color: muted, wrap: true)
            y += rh
            line.setFill()
            UIRectFill(CGRect(x: bx, y: y, width: blockW, height: 0.5))
        }

        // ما يحويه التقرير
        y += 20
        let introW = blockW
        let ih = textHeight(doc.intro, width: introW, font: fCoverIntro) + 4
        draw(doc.intro, in: CGRect(x: cx - introW / 2, y: y, width: introW, height: ih),
             font: fCoverIntro, color: faint, align: .center, wrap: true)

        // «سرّي» — شارة محدّدة صغيرة أسفل الغلاف
        let a = attrs(fSecret, secret, align: .center, ltr: false, wrap: false)
        let tw = ceil((AdminReportText.confidential as NSString).size(withAttributes: a).width)
        let lh = lineH(fSecret)
        let pill = CGRect(x: cx - (tw + 28) / 2, y: pageSize.height - 88, width: tw + 28, height: lh + 10)
        let pp = UIBezierPath(roundedRect: pill.insetBy(dx: 0.4, dy: 0.4), cornerRadius: pill.height / 2)
        pp.lineWidth = 0.8
        secret.setStroke()
        pp.stroke()
        draw(AdminReportText.confidential, in: CGRect(x: pill.minX, y: pill.minY + 5, width: pill.width, height: lh),
             font: fSecret, color: secret, align: .center)
    }
}

// MARK: - المهمة الكاملة خارج الخيط الرئيسي: بناء ← رسم ← حفظ الملف ← صور المعاينة

/// علامة إلغاء تُقرأ من خيط الرسم (تغيّر النوع أو التصفية أثناء الإنشاء)
nonisolated final class AdminReportCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

nonisolated struct AdminReportResult: @unchecked Sendable {
    let kind: AdminReportKind
    let url: URL
    let pages: Int
    let count: Int
    let summary: String
    /// صورة الغلاف للمعاينة (`AdminReportJob.thumbnailPages`)
    let thumbnails: [UIImage]
    /// مدة البناء والرسم (ث)
    let seconds: Double
}

nonisolated enum AdminReportJob {
    static let thumbnailWidth: CGFloat = 220
    /// المعاينة أول صفحة (الغلاف إن اختير) وعليها عدد الصفحات — الضغط يفتح الملف كاملاً
    static let thumbnailPages = 1

    /// `fields`: ما اختير في «البيانات:» — nil = الافتراضي
    static func run(_ kind: AdminReportKind, input: AdminReportInput, filter: AdminReportFilter,
                    fields: Set<AdminReportField>? = nil, options: AdminReportOptions = .init(), flag: AdminReportCancelFlag) throws -> AdminReportResult {
        let start = CFAbsoluteTimeGetCurrent()
        let doc = AdminReportBuilder.build(kind, input: input, filter: filter, fields: fields, options: options)
        if flag.isCancelled { throw AdminReportPDF.Cancelled() }
        let out = try AdminReportPDF.render(doc, isCancelled: { flag.isCancelled })
        let seconds = CFAbsoluteTimeGetCurrent() - start

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FamilyReports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AdminReportText.kuwait.timeZone
        f.dateFormat = "yyyyMMdd-HHmm"
        let url = dir.appendingPathComponent("\(kind.fileStem)-\(f.string(from: input.date)).pdf")
        try out.data.write(to: url, options: .atomic)

        return AdminReportResult(kind: kind, url: url, pages: out.pages, count: doc.count, summary: doc.summaryLine,
                                 thumbnails: thumbnails(out.data, count: thumbnailPages, width: thumbnailWidth),
                                 seconds: seconds)
    }

    /// صور أول الصفحات (CoreGraphics — آمنة خارج الخيط الرئيسي)
    static func thumbnails(_ data: Data, count: Int, width: CGFloat) -> [UIImage] {
        guard let provider = CGDataProvider(data: data as CFData), let pdf = CGPDFDocument(provider) else { return [] }
        let size = CGSize(width: width, height: (width * AdminReportPDF.pageSize.height / AdminReportPDF.pageSize.width).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return (0..<min(count, pdf.numberOfPages)).compactMap { i in
            guard let page = pdf.page(at: i + 1) else { return nil }
            return renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                let cg = ctx.cgContext
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: 1, y: -1)
                cg.concatenate(page.getDrawingTransform(.mediaBox, rect: CGRect(origin: .zero, size: size),
                                                        rotate: 0, preserveAspectRatio: true))
                cg.drawPDFPage(page)
            }
        }
    }
}
