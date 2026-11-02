import UIKit

// MARK: - رسم تقارير العائلة الرسمية (PDF) — «الورق الرسمي الكلاسيكي» (طلب المالك ٢٠٢٦-١١-٠٢، الاتجاه «أ»)
//
// A4 عمودي. الغلاف كريمي بإطار ذهبي مزدوج: شعار «المحمدعلي» المسطّح (`FamilyLogoNavy`) في الوسط و«عائلة المحمدعلي»
// تحته، سدو ذهبي، عنوان التقرير ونطاقه (الفرع بمساره والتصفية)، مربّع بيانات (التاريخ بتوقيت الكويت · أعدّه ·
// التجميع · العدد)، ثم الفهرس للملفات متعدّدة الأقسام (على الغلاف إن قصر، وإلا صفحات «الفهرس» بعده)، وختم «سرّي»
// متحفّظ أسفله. الصفحات الداخلية: رأس (العنوان + النطاق يميناً والشعار يساراً + خطّ كحلي شعري)، جداول بصفّ رأس
// كحلي ونص أبيض وصفوف كريمية خفيفة متناوبة، شريط كريمي بخطّ ذهبي لكل مجموعة (بيت، فرع، شهر)، وسطر المجموع في ذيل
// كل جدول، وتذييل: «سرّي — لعائلة المحمدعلي فقط · التاريخ» و«صفحة X من Y».
// «كتاب الفرع»: كل قسم يبدأ صفحة ويدخل الفهرس؛ صفحات الشجرة المرسومة بوصلات ذهبية ومفتاح صغير؛ استمارة بخانات
// منقّطة ومربّعات تُعلَّم باليد وخطوط توقيع؛ بطاقات الأفراد صفّاً من بطاقتين.
// الألوان من `DS.Print` (الورقة فاتحة دائماً)، والخط خط الهوية (IBM Plex Sans Arabic — `DS.Font.Plex`)، والنص عربي
// من اليمين. الجداول بعنوان يتكرّر أعلى كل صفحة، والأسماء الطويلة تلتفّ. الأعمدة ما اختير بترتيبه: كل عمود بعرض
// أطول محتواه والاسم يأخذ ما بقي (`plan`).
// يعمل خارج الخيط الرئيسي: قياس ثم توزيع على الصفحات (فيُعرف العدد الكلي وأرقام الفهرس قبل الرسم)، ثم الرسم.

nonisolated enum AdminReportPDF {

    struct Output: Sendable {
        let data: Data
        let pages: Int
    }

    struct Cancelled: Error {}

    // MARK: الورقة

    static let pageSize = CGSize(width: 595.28, height: 841.89)
    private static let margin: CGFloat = 36
    private static let headerTop: CGFloat = 20
    /// نقطة PDF = 1/72 بوصة: 19 ≈ 6.7 مم مطبوعة — فوق حدّ الشعار، وحوله ربع ارتفاعه فراغاً على الأقل
    private static let headerLogoHeight: CGFloat = 19
    private static let headerRule: CGFloat = headerTop + headerLogoHeight + 7
    private static let contentTop: CGFloat = headerRule + 14
    private static let footerLine: CGFloat = pageSize.height - 34
    private static let contentBottom: CGFloat = footerLine - 12
    private static var contentWidth: CGFloat { pageSize.width - margin * 2 }
    private static var right: CGFloat { pageSize.width - margin }

    /// الفهرس على الغلاف حتى هذا العدد، وإلا صفحات «الفهرس»
    static let coverTocMax = 8
    /// أكثر مداخل الفهرس (المجموعات الأولى)
    static let tocMaxEntries = 60
    private static let tocPerPage = 30
    /// بطاقات الأفراد في الصفّ
    static let cardsPerRow = 2

    // MARK: ألوان الورق (`DS.Print`)

    private static let navy = DS.Print.navy
    private static let navyLight = DS.Print.navySoft
    private static let brand = DS.Print.navy
    private static let gold = DS.Print.gold
    private static let goldText = DS.Print.goldText
    private static let cream = DS.Print.cream
    private static let zebra = DS.Print.creamSoft
    private static let line = DS.Print.line
    private static let rowLine = DS.Print.rowLine
    private static let ink = DS.Print.ink
    private static let muted = DS.Print.muted
    private static let faint = DS.Print.faint
    private static let track = DS.Print.track
    private static let deceased = DS.Print.deceased
    private static let warning = DS.Print.warning
    private static let success = DS.Print.success
    private static let slate = DS.Print.slate
    private static let female = DS.Print.female
    private static let secret = DS.Print.secret
    private static let paper = DS.Print.paper

    private static func color(_ tone: AdminReportTone) -> UIColor {
        switch tone {
        case .normal, .checkbox: return ink
        case .muted, .blank: return muted
        case .warning: return warning
        case .men: return brand
        case .women: return female
        case .total: return gold
        case .registered: return success
        case .treeOnly: return slate
        }
    }

    // MARK: الخط — IBM Plex Sans Arabic (خط النظام احتياطاً)

    private static func plex(_ weight: String, _ size: CGFloat) -> UIFont {
        UIFont(name: weight == "Bold" ? DS.Font.Plex.bold : weight == "SemiBold" ? DS.Font.Plex.semibold : weight == "Medium" ? DS.Font.Plex.medium : DS.Font.Plex.regular, size: size)
            ?? UIFont.systemFont(ofSize: size, weight: weight == "Bold" ? .bold : weight == "SemiBold" ? .semibold : .regular)
    }
    private static let fBody = plex("Regular", 9.5)
    private static let fBodyBold = plex("SemiBold", 9.5)
    private static let fHead = plex("SemiBold", 9)
    private static let fBodyCompact = plex("Regular", 8.5)
    private static let fBodyBoldCompact = plex("SemiBold", 8.5)
    private static let fHeadCompact = plex("SemiBold", 8)
    private static let fSmall = plex("Regular", 8.5)
    private static let fSmallBold = plex("Medium", 8.5)
    private static let fFooter = plex("Regular", 8)
    private static let fFooterBold = plex("Medium", 8)
    private static let fHeader = plex("SemiBold", 10.5)
    private static let fBand = plex("SemiBold", 10.5)
    private static let fSection = plex("Bold", 18)
    private static let fPanel = plex("SemiBold", 11.5)
    private static let fTileValue = plex("Bold", 17)
    private static let fRingValue = plex("Bold", 15)
    private static let fCoverFamily = plex("Medium", 10)
    private static let fCoverTitle = plex("Bold", 28)
    private static let fCoverScope = plex("Regular", 12)
    private static let fCoverLabel = plex("Regular", 9)
    private static let fCoverValue = plex("Medium", 9.5)
    private static let fCoverIntro = plex("Regular", 9)
    private static let fTocTitle = plex("Bold", 11)
    private static let fToc = plex("Regular", 9.5)
    private static let fSecret = plex("SemiBold", 8.5)
    private static let fChartTitle = plex("Bold", 14)
    private static let fNode = plex("SemiBold", 8.5)
    private static let fNodeSmall = plex("SemiBold", 6.5)
    private static let fNodeCaption = plex("Regular", 6.5)
    private static let fNodeCaptionSmall = plex("Regular", 5.5)
    private static let fCardName = plex("SemiBold", 10)

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

    private static func draw(_ text: String, in rect: CGRect, font: UIFont, color: UIColor,
                             align: NSTextAlignment = .right, ltr: Bool = false, wrap: Bool = false) {
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                attributes: attrs(font, color, align: align, ltr: ltr, wrap: wrap), context: nil)
    }

    private static func textWidth(_ text: String, _ font: UIFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func textHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
        if CGFloat(text.count) * font.pointSize * 0.62 < width { return lineH(font) }
        let r = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                options: [.usesLineFragmentOrigin],
                                                attributes: attrs(font, ink, align: .right, ltr: false, wrap: true),
                                                context: nil)
        return max(lineH(font), ceil(r.height))
    }

    /// خطّ منقّط أفقي (خانة تُعبّأ باليد)
    private static func dotted(from x0: CGFloat, to x1: CGFloat, y: CGFloat, color: UIColor = faint) {
        guard x1 - x0 > 4 else { return }
        let p = UIBezierPath()
        p.move(to: CGPoint(x: x0, y: y))
        p.addLine(to: CGPoint(x: x1, y: y))
        p.lineWidth = 0.7
        p.setLineDash([1, 2.2], count: 2, phase: 0)
        color.setStroke()
        p.stroke()
    }

    // MARK: الرسم الكامل

    static func render(_ doc: AdminReportDoc, isCancelled: () -> Bool = { false }) throws -> Output {
        let laid = try layout(doc.blocks, isCancelled: isCancelled)
        // الفهرس: على الغلاف إن قصر، وإلا صفحاته بعد الغلاف (مدخل واحد بلا فهرس)
        let entries = laid.toc.count > 1 ? laid.toc : []
        let tocOnCover = doc.cover && entries.count <= coverTocMax
        let tocPages = entries.isEmpty || tocOnCover ? 0 : Int(ceil(Double(entries.count) / Double(tocPerPage)))
        let firstContent = (doc.cover ? 1 : 0) + tocPages + 1
        let total = firstContent - 1 + laid.pages.count
        let toc = entries.map { (title: $0.title, page: firstContent + $0.page) }

        let vector = familyLogo()
        let logo = vector.flatMap { raster($0, height: coverLogoWidth * $0.size.height / max($0.size.width, 1), background: cream) }
        let smallLogo = vector.flatMap { raster($0, height: headerLogoHeight, background: paper) }
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: doc.title,
            kCGPDFContextAuthor as String: AdminReportText.familyName,
            kCGPDFContextCreator as String: "FamilyTreeV2",
            kCGPDFContextSubject as String: doc.summaryLine
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        var cancelled = false
        let stamp = "\(AdminReportText.confidential) · \(AdminReportText.date(doc.date, calendar: AdminReportText.kuwait))"
        let data = renderer.pdfData { ctx in
            var page = 0
            if doc.cover {
                ctx.beginPage()
                page += 1
                drawCover(doc, total: total, logo: logo, toc: tocOnCover ? toc : [])
            }
            if tocPages > 0 {
                for chunk in stride(from: 0, to: toc.count, by: tocPerPage) {
                    ctx.beginPage()
                    page += 1
                    drawHeader(doc.title, scope: doc.scope, logo: smallLogo)
                    drawTocPage(Array(toc[chunk..<min(chunk + tocPerPage, toc.count)]), first: chunk == 0)
                    drawFooter(page: page, total: total, stamp: stamp)
                }
            }
            for items in laid.pages {
                if isCancelled() { cancelled = true; return }
                ctx.beginPage()
                page += 1
                drawHeader(doc.title, scope: doc.scope, logo: smallLogo)
                for item in items { drawItem(item) }
                drawFooter(page: page, total: total, stamp: stamp)
            }
        }
        if cancelled { throw Cancelled() }
        return Output(data: data, pages: total)
    }

    // MARK: التوزيع على الصفحات

    private struct TableStyle {
        let body: UIFont
        let bold: UIFont
        let head: UIFont
        let padX: CGFloat

        static let regular = TableStyle(body: fBody, bold: fBodyBold, head: fHead, padX: 6)
        static let compact = TableStyle(body: fBodyCompact, bold: fBodyBoldCompact, head: fHeadCompact, padX: 4)
    }

    private struct ColumnPlan {
        let widths: [CGFloat]
        let style: TableStyle
    }

    private final class TableLayout {
        let table: AdminReportTable
        let frames: [(x: CGFloat, w: CGFloat)]
        let style: TableStyle
        let headerH: CGFloat
        let padY: CGFloat
        var rowH: [CGFloat] = []
        var footerH: CGFloat = 0
        var summaryH: CGFloat = 0

        init(_ table: AdminReportTable, plan: ColumnPlan?) {
            self.table = table
            style = plan?.style ?? .regular
            padY = table.roomy ? 9 : 4.5
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
            headerH = h + 4.5 * 2 + 3
            if let s = table.summary {
                summaryH = AdminReportPDF.textHeight(s, width: AdminReportPDF.contentWidth - 8, font: AdminReportPDF.fSmallBold) + 8
            }
        }

        func measure(_ row: AdminReportTable.Row, font: UIFont) -> CGFloat {
            var h = AdminReportPDF.lineH(font)
            for (i, c) in table.columns.enumerated() where c.wraps && i < row.cells.count {
                h = max(h, AdminReportPDF.textHeight(row.cells[i], width: frames[i].w - style.padX * 2, font: font))
            }
            return h + padY * 2
        }
    }

    // MARK: مقاسات الأعمدة من المحتوى

    private static let fillMinRegular: CGFloat = 0.30
    private static let fillMinCompact: CGFloat = 0.22
    private static let fillComfort: CGFloat = 0.42
    private static let wrapCap: CGFloat = 0.22

    private static func signature(_ t: AdminReportTable) -> String { t.columns.map(\.title).joined(separator: "|") }

    /// جداول بعمود `fill` (الاسم): كل عمود بعرض أطول محتواه (والعنوان على سطرين إن لزم)، والاسم يأخذ ما بقي.
    /// إن ضاقت الصفحة: تلتفّ الأعمدة القابلة للالتفاف حتى أطول كلمة، ثم الخط المضغوط، ثم تصغر الأعمدة بالنسبة.
    private static func plan(_ tables: [AdminReportTable]) -> ColumnPlan? {
        guard let columns = tables.first?.columns, let fill = columns.firstIndex(where: \.fill) else { return nil }
        return plan(tables, columns: columns, fill: fill, compact: false)
            ?? plan(tables, columns: columns, fill: fill, compact: true)
    }

    private static func plan(_ tables: [AdminReportTable], columns: [AdminReportTable.Column], fill: Int,
                             compact: Bool) -> ColumnPlan? {
        let style = compact ? TableStyle.compact : .regular
        var cache: [String: CGFloat] = [:]
        func width(_ s: String, _ font: UIFont) -> CGFloat {
            let key = "\(font.fontName)\(font.pointSize)|\(s)"
            if let w = cache[key] { return w }
            let w = textWidth(s, font)
            cache[key] = w
            return w
        }
        func longestWord(_ s: String, _ font: UIFont) -> CGFloat {
            s.split(separator: " ").map { width(String($0), font) }.max() ?? width(s, font)
        }
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
            let minW = CGFloat(c.minWidth)
            nat[i] = max(c.wraps ? min(cellNat, contentWidth * wrapCap) : cellNat, cellLow, headTwo, minW - pad) + pad
            low[i] = max(cellLow, longestWord(c.title, style.head), minW - pad) + pad
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
                let lowSum = others.reduce(0) { $0 + low[$1] }
                let k = min(1, (contentWidth - minFill) / max(lowSum, 1))
                for i in others { w[i] = (low[i] * k).rounded(.down) }
            }
        } else {
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
        case summary(TableLayout, y: CGFloat)
    }

    private struct Laid {
        let pages: [[Item]]
        /// مداخل الفهرس: العنوان ورقم صفحة المحتوى (من ٠)
        let toc: [(title: String, page: Int)]
    }

    private static let blockGap: CGFloat = 12

    private static func layout(_ blocks: [AdminReportBlock], isCancelled: () -> Bool) throws -> Laid {
        var pages: [[Item]] = [[]]
        var toc: [(title: String, page: Int)] = []
        var y = contentTop
        func newPage() {
            pages.append([])
            y = contentTop
        }
        func fits(_ h: CGFloat) -> Bool { y + h <= contentBottom }

        var groups: [String: [AdminReportTable]] = [:]
        for b in blocks {
            if case let .table(t) = b, t.columns.contains(where: \.fill) { groups[signature(t), default: []].append(t) }
        }
        var plans: [String: ColumnPlan] = [:]
        for (key, list) in groups {
            plans[key] = plan(list)
            if isCancelled() { throw Cancelled() }
        }

        var tables: [Int: TableLayout] = [:]
        for (i, b) in blocks.enumerated() {
            guard case let .table(t) = b else { continue }
            let l = TableLayout(t, plan: plans[signature(t)])
            l.rowH = t.rows.map { l.measure($0, font: l.style.body) }
            if let f = t.footer { l.footerH = l.measure(f, font: l.style.bold) }
            tables[i] = l
            if isCancelled() { throw Cancelled() }
        }

        for (i, b) in blocks.enumerated() {
            if let l = tables[i] {
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
                if l.summaryH > 0 {
                    if !fits(l.summaryH) { newPage() }
                    pages[pages.count - 1].append(.summary(l, y: y))
                    y += l.summaryH
                }
                y += blockGap
                continue
            }
            switch b {
            case .pageBreak:
                if !(pages.last?.isEmpty ?? true) { newPage() }
                continue
            case let .section(title, _):
                if !(pages.last?.isEmpty ?? true) { newPage() }
                toc.append((title, pages.count - 1))
            case .treeChart:
                // صفحة الشجرة كاملة — إلا بعد عنوان قسم في أعلى الصفحة نفسها (لا يبقى العنوان وحده)
                var afterSection = false
                if case .block(.section(_, _), _, _)? = pages.last?.last { afterSection = true }
                if !(pages.last?.isEmpty ?? true) && !afterSection { newPage() }
            default: break
            }
            var h = measure(b)
            if case .treeChart = b { h = contentBottom - y }
            var need = h
            switch b {
            case .heading, .band:
                // العنوان لا يبقى وحده أسفل الصفحة: معه عنوان الجدول وأول صفّين (أو الكتلة التالية)
                if i + 1 < blocks.count {
                    if let next = tables[i + 1] {
                        need += next.headerH + next.rowH.prefix(2).reduce(0, +)
                    } else {
                        need += measure(blocks[i + 1])
                    }
                }
            default: break
            }
            if !fits(need) && y > contentTop { newPage() }
            if case let .band(title, _, true) = b { toc.append((title, pages.count - 1)) }
            pages[pages.count - 1].append(.block(b, y: y, h: h))
            y += h
            switch b {
            case .heading, .band: y += 4
            case .section: y += 8
            default: y += blockGap
            }
        }
        if pages.last?.isEmpty == true && pages.count > 1 { pages.removeLast() }
        return Laid(pages: pages, toc: toc)
    }

    // MARK: مقاسات الكتل

    private static let tileHeight: CGFloat = 52
    private static let ringsHeight: CGFloat = 150
    private static let barRow: CGFloat = 20
    private static let barLabelWidth: CGFloat = 130
    private static let barValueWidth: CGFloat = 100
    private static let splitHeight: CGFloat = 62
    private static let miniTreeHeight: CGFloat = 148
    private static let bandHeight: CGFloat = 24
    private static let cardHeight: CGFloat = 92
    private static let cardGap: CGFloat = 10
    private static let signaturesHeight: CGFloat = 46
    private static let chartKeyHeight: CGFloat = 40

    private static func measure(_ b: AdminReportBlock) -> CGFloat {
        switch b {
        case .tiles: return tileHeight
        case let .heading(title, subtitle, _):
            var h = 2 + textHeight(title, width: contentWidth - 12, font: fPanel)
            if let subtitle { h += 2 + textHeight(subtitle, width: contentWidth - 12, font: fSmall) }
            return h + 4
        case .band: return bandHeight
        case let .section(title, subtitle):
            var h = textHeight(title, width: contentWidth, font: fSection) + 10
            if let subtitle { h += textHeight(subtitle, width: contentWidth, font: fSmall) + 2 }
            return h + 6
        case .pageBreak, .table: return 0
        case let .note(text, _): return textHeight(text, width: contentWidth - 20, font: fBody) + 12
        case .rings: return ringsHeight
        case let .bars(rows, _, _, _): return 18 + CGFloat(rows.count) * barRow
        case .split: return splitHeight
        case .miniTree: return miniTreeHeight
        case .treeChart: return contentBottom - contentTop
        case .cardRow: return cardHeight
        case .signatures: return signaturesHeight
        case let .caption(text): return textHeight(text, width: contentWidth, font: fFooter) + 2
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
        case let .summary(l, y):
            if let s = l.table.summary {
                navy.setFill()
                UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 0.6))
                draw(s, in: CGRect(x: margin + 4, y: y + 4, width: contentWidth - 8, height: l.summaryH - 6),
                     font: fSmallBold, color: navy, wrap: true)
            }
        }
    }

    private static func drawBlock(_ b: AdminReportBlock, y: CGFloat, h: CGFloat) {
        switch b {
        case let .tiles(tiles): drawTiles(tiles, y: y)
        case let .heading(title, subtitle, _): drawHeading(title, subtitle: subtitle, y: y)
        case let .band(title, subtitle, _): drawBand(title, subtitle: subtitle, y: y)
        case let .section(title, subtitle): drawSection(title, subtitle: subtitle, y: y)
        case let .note(text, tone): drawNote(text, tone: tone, y: y, h: h)
        case let .rings(rings): drawRings(rings, y: y)
        case let .bars(rows, firstLabel, secondLabel, tone):
            drawBars(rows, firstLabel: firstLabel, secondLabel: secondLabel, tone: tone, y: y)
        case let .split(split): drawSplit(split, y: y)
        case let .miniTree(tree): drawMiniTree(tree, y: y)
        case let .treeChart(chart): drawTreeChart(chart, y: y, h: h)
        case let .cardRow(cards): drawCards(cards, y: y)
        case let .signatures(labels): drawSignatures(labels, y: y)
        case let .caption(text):
            draw(text, in: CGRect(x: margin, y: y, width: contentWidth, height: h), font: fFooter, color: faint, wrap: true)
        case .table, .pageBreak: break
        }
    }

    // MARK: الجدول — صفّ رأس كحلي بنص أبيض، وصفوف كريمية خفيفة متناوبة

    private static func drawTableHeader(_ l: TableLayout, y: CGFloat) {
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: l.headerH - 1)
        navy.setFill()
        UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 3, height: 3)).fill()
        for (i, c) in l.table.columns.enumerated() {
            let f = l.frames[i]
            let pad = l.style.padX
            let h = textHeight(c.title, width: f.w - pad * 2, font: l.style.head)
            draw(c.title, in: CGRect(x: f.x + pad, y: y + (rect.height - h) / 2, width: f.w - pad * 2, height: h + 1),
                 font: l.style.head, color: paper, align: c.centered ? .center : .right, wrap: true)
        }
    }

    private static func drawRow(_ l: TableLayout, _ row: AdminReportTable.Row, index: Int, y: CGFloat, h: CGFloat,
                                font: UIFont, total: Bool = false) {
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: h)
        if total {
            cream.setFill()
            UIRectFill(rect)
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
            let f = l.frames[i]
            let pad = l.style.padX
            let w = f.w - pad * 2
            let tone = row.tones[i]
            let tint = tone.map { AdminReportPDF.color($0) } ?? ink
            let align: NSTextAlignment = c.centered ? .center : .right
            if tone == .checkbox {
                let s: CGFloat = 9
                let box = CGRect(x: f.x + (f.w - s) / 2, y: y + (h - s) / 2, width: s, height: s)
                let p = UIBezierPath(roundedRect: box, cornerRadius: 1.5)
                p.lineWidth = 0.8
                navy.setStroke()
                p.stroke()
                continue
            }
            if tone == .blank {
                // النص (إن وُجد) ثم خطّ منقّط في الباقي حتى طرف الخانة
                var end = f.x + f.w - pad
                if !text.isEmpty {
                    let tw = min(textWidth(text, font), w)
                    draw(text, in: CGRect(x: f.x + pad, y: y + (h - single) / 2, width: w, height: single + 1),
                         font: font, color: muted)
                    end -= tw + 4
                }
                dotted(from: f.x + pad, to: end, y: y + h - l.padY - 1)
                continue
            }
            guard !text.isEmpty else { continue }
            if c.wraps {
                let th = h > single + l.padY * 2 + 1 ? textHeight(text, width: w, font: font) : single
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
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.4, dy: 0.4), cornerRadius: 6)
            zebra.setFill()
            path.fill()
            line.setStroke()
            path.lineWidth = 0.8
            path.stroke()
            draw(t.value, in: CGRect(x: x + 4, y: y + 6, width: w - 8, height: lineH(fTileValue)),
                 font: fTileValue, color: navy, align: .center)
            draw(t.label, in: CGRect(x: x + 4, y: y + 8 + lineH(fTileValue) - 4, width: w - 8, height: lineH(fSmall)),
                 font: fSmall, color: muted, align: .center)
        }
    }

    /// عنوان لوحة (إحصاء، قسم صغير)
    private static func drawHeading(_ title: String, subtitle: String?, y: CGFloat) {
        let top = y + 2
        let th = textHeight(title, width: contentWidth - 12, font: fPanel)
        draw(title, in: CGRect(x: margin, y: top, width: contentWidth, height: th + 1), font: fPanel, color: navy, wrap: true)
        if let subtitle {
            let sh = textHeight(subtitle, width: contentWidth - 12, font: fSmall)
            draw(subtitle, in: CGRect(x: margin, y: top + th + 2, width: contentWidth, height: sh + 1),
                 font: fSmall, color: muted, wrap: true)
        }
    }

    /// شريط كريمي بخطّ ذهبي يميناً: العنوان يميناً، والعدد/المسار يساراً
    private static func drawBand(_ title: String, subtitle: String?, y: CGFloat) {
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: bandHeight)
        cream.setFill()
        UIRectFill(rect)
        gold.setFill()
        UIRectFill(CGRect(x: right - 3, y: y, width: 3, height: bandHeight))
        let th = lineH(fBand)
        let titleW = min(textWidth(title, fBand), contentWidth * 0.62)
        draw(title, in: CGRect(x: right - 12 - titleW, y: y + (bandHeight - th) / 2, width: titleW, height: th),
             font: fBand, color: navy)
        if let subtitle {
            let sh = lineH(fSmall)
            draw(subtitle, in: CGRect(x: margin + 8, y: y + (bandHeight - sh) / 2, width: contentWidth - titleW - 32, height: sh),
                 font: fSmall, color: goldText, align: .left)
        }
    }

    /// قسم يبدأ صفحة: عنوان كبير كحلي، خطّ ذهبي قصير، وسطر تحته
    private static func drawSection(_ title: String, subtitle: String?, y: CGFloat) {
        let th = textHeight(title, width: contentWidth, font: fSection)
        draw(title, in: CGRect(x: margin, y: y, width: contentWidth, height: th + 1), font: fSection, color: navy, wrap: true)
        gold.setFill()
        UIRectFill(CGRect(x: right - 48, y: y + th + 4, width: 48, height: 1.6))
        if let subtitle {
            let sh = textHeight(subtitle, width: contentWidth, font: fSmall)
            draw(subtitle, in: CGRect(x: margin, y: y + th + 10, width: contentWidth, height: sh + 1),
                 font: fSmall, color: muted, wrap: true)
        }
    }

    private static func drawNote(_ text: String, tone: AdminReportTone, y: CGFloat, h: CGFloat) {
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: h)
        if tone == .warning {
            // تنبيه: شريط كريمي بخطّ ذهبي (الطريقة، ملاحظة مهمة)
            cream.setFill()
            UIRectFill(rect)
            gold.setFill()
            UIRectFill(CGRect(x: right - 3, y: y, width: 3, height: h))
            draw(text, in: rect.insetBy(dx: 12, dy: 6), font: fBody, color: ink, wrap: true)
        } else {
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.4, dy: 0.4), cornerRadius: 5)
            zebra.setFill()
            path.fill()
            draw(text, in: rect.insetBy(dx: 10, dy: 6), font: fBody, color: color(tone), wrap: true)
        }
    }

    /// خطوط تعبئة بأسمائها تحتها، بعرض الصفحة
    private static func drawSignatures(_ labels: [String], y: CGFloat) {
        guard !labels.isEmpty else { return }
        let gap: CGFloat = 18
        let w = (contentWidth - gap * CGFloat(labels.count - 1)) / CGFloat(labels.count)
        for (i, label) in labels.enumerated() {
            let x = right - CGFloat(i + 1) * w - CGFloat(i) * gap
            dotted(from: x, to: x + w, y: y + 24, color: muted)
            draw(label, in: CGRect(x: x, y: y + 28, width: w, height: lineH(fSmall)), font: fSmall, color: muted, align: .center)
        }
    }

    /// بطاقتان في الصفّ: حرف الاسم في دائرة، الاسم، النسب، ثم الأسطر
    private static func drawCards(_ cards: [AdminReportCard], y: CGFloat) {
        let w = (contentWidth - cardGap * CGFloat(cardsPerRow - 1)) / CGFloat(cardsPerRow)
        for (i, c) in cards.enumerated() {
            let x = right - CGFloat(i + 1) * w - CGFloat(i) * cardGap
            let rect = CGRect(x: x, y: y, width: w, height: cardHeight - 8)
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.4, dy: 0.4), cornerRadius: 6)
            (c.deceased ? zebra : paper).setFill()
            path.fill()
            line.setStroke()
            path.lineWidth = 0.8
            path.stroke()
            gold.setFill()
            UIRectFill(CGRect(x: rect.maxX - 3, y: rect.minY + 8, width: 3, height: rect.height - 16))
            let d: CGFloat = 30
            let circle = CGRect(x: rect.maxX - 12 - d, y: rect.minY + 10, width: d, height: d)
            (c.deceased ? slate : navy).setFill()
            UIBezierPath(ovalIn: circle).fill()
            let initial = c.name.first.map(String.init) ?? ""
            draw(initial, in: CGRect(x: circle.minX, y: circle.midY - lineH(fBand) / 2, width: d, height: lineH(fBand)),
                 font: fBand, color: paper, align: .center)
            let textRight = circle.minX - 8
            let tw = textRight - rect.minX - 10
            var ty = rect.minY + 8
            let nh = min(textHeight(c.name, width: tw, font: fCardName), lineH(fCardName) * 2)
            draw(c.name, in: CGRect(x: rect.minX + 10, y: ty, width: tw, height: nh + 1), font: fCardName, color: navy, wrap: true)
            ty += nh
            if !c.lineage.isEmpty {
                draw(c.lineage, in: CGRect(x: rect.minX + 10, y: ty, width: tw, height: lineH(fSmall)), font: fSmall, color: goldText)
                ty += lineH(fSmall) + 2
            }
            for l in c.lines where ty + lineH(fFooter) <= rect.maxY - 4 {
                draw(l, in: CGRect(x: rect.minX + 10, y: ty, width: rect.width - 22, height: lineH(fFooter)),
                     font: fFooter, color: muted)
                ty += lineH(fFooter)
            }
        }
    }

    // MARK: الشجرة المطبوعة

    /// العقد على مستويات: الأوراق بخانات متساوية (الأول يميناً) والأب في منتصف أبنائه؛ وصلات ذهبية؛ ومفتاح أسفل الصفحة.
    /// خانات كثيرة (فوق المريح) = عقد أصغر بخط أصغر (`AdminReportBuilder.treeSlotsScaled`)
    private static func drawTreeChart(_ chart: AdminReportTreeChart, y: CGFloat, h: CGFloat) {
        guard !chart.nodes.isEmpty else { return }
        // العنوان
        let th = lineH(fChartTitle)
        draw(chart.title, in: CGRect(x: margin, y: y, width: contentWidth, height: th), font: fChartTitle, color: navy, align: .center)
        var top = y + th + 2
        if let sub = chart.subtitle {
            draw(sub, in: CGRect(x: margin, y: top, width: contentWidth, height: lineH(fSmall)), font: fSmall, color: muted,
                 align: .center)
            top += lineH(fSmall)
        }
        drawSadu(centerX: pageSize.width / 2, y: top + 8, lineLength: 30, unit: 2.4, alpha: 1)
        top += 22

        // المستويات والخانات
        var depth = [Int](repeating: 0, count: chart.nodes.count)
        var slotX = [CGFloat](repeating: 0, count: chart.nodes.count)
        var next: CGFloat = 0
        var maxDepth = 0
        func place(_ i: Int, _ d: Int) {
            depth[i] = d
            maxDepth = max(maxDepth, d)
            let kids = chart.nodes[i].children
            if kids.isEmpty {
                slotX[i] = next
                next += 1
            } else {
                for k in kids { place(k, d + 1) }
                slotX[i] = (slotX[kids.first!] + slotX[kids.last!]) / 2
            }
        }
        place(0, 0)
        let slots = max(next, 1)
        let slotW = contentWidth / slots
        let compact = Int(slots) > AdminReportBuilder.treeSlotsComfort
        let titleFont = compact ? fNodeSmall : fNode
        let capFont = compact ? fNodeCaptionSmall : fNodeCaption
        let nodeW = min(slotW - (compact ? 3 : 6), 120)
        let nodeH = lineH(titleFont) + lineH(capFont) + 8
        let bottom = y + h - chartKeyHeight
        let levelGap = min(110, (bottom - top - nodeH) / CGFloat(max(maxDepth, 1)))
        func center(_ i: Int) -> CGPoint {
            CGPoint(x: right - (slotX[i] + 0.5) * slotW, y: top + CGFloat(depth[i]) * levelGap)
        }

        // الوصلات أولاً (تحت العقد)
        gold.setFill()
        for (i, n) in chart.nodes.enumerated() where !n.children.isEmpty {
            let p = center(i)
            let busY = p.y + nodeH + (levelGap - nodeH) / 2
            UIRectFill(CGRect(x: p.x - 0.5, y: p.y + nodeH, width: 1, height: busY - p.y - nodeH))
            let xs = n.children.map { center($0).x }
            if let a = xs.min(), let b = xs.max(), b > a { UIRectFill(CGRect(x: a, y: busY - 0.5, width: b - a, height: 1)) }
            for k in n.children {
                let c = center(k)
                UIRectFill(CGRect(x: c.x - 0.5, y: busY, width: 1, height: c.y - busY))
            }
        }

        // العقد
        for (i, n) in chart.nodes.enumerated() {
            let c = center(i)
            let isRoot = i == 0
            let w = isRoot ? min(max(nodeW, 120), contentWidth * 0.5) : nodeW
            let rect = CGRect(x: c.x - w / 2, y: c.y, width: w, height: nodeH)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 3)
            path.lineWidth = 0.8
            if isRoot {
                navy.setFill()
                path.fill()
            } else {
                (n.deceased ? DS.Print.deceasedFill : paper).setFill()
                path.fill()
                if n.continued { path.setLineDash([2.5, 1.8], count: 2, phase: 0) }
                (n.continued ? goldText : navy).setStroke()
                path.stroke()
            }
            let tColor = isRoot ? paper : (n.deceased ? muted : navy)
            draw(n.title, in: CGRect(x: rect.minX + 1, y: rect.minY + 3, width: rect.width - 2, height: lineH(titleFont)),
                 font: titleFont, color: tColor, align: .center)
            if let cap = n.caption {
                draw(cap, in: CGRect(x: rect.minX + 1, y: rect.minY + 3 + lineH(titleFont), width: rect.width - 2,
                                     height: lineH(capFont)),
                     font: capFont, color: isRoot ? gold : muted, align: .center)
            }
        }

        // المفتاح
        drawTreeKey(y: y + h - chartKeyHeight + 8)
    }

    private static func drawTreeKey(y: CGFloat) {
        let box = CGRect(x: margin, y: y, width: contentWidth, height: chartKeyHeight - 10)
        let p = UIBezierPath(roundedRect: box, cornerRadius: 4)
        p.lineWidth = 0.6
        line.setStroke()
        p.stroke()
        let items: [(String, UIColor, Bool)] = [
            ("على قيد الحياة", paper, false),
            ("متوفى — وتحته سنتا الميلاد والوفاة", DS.Print.deceasedFill, false),
            ("مختصر — فرعه في صفحته", paper, true)
        ]
        let slot = (contentWidth - 8) / CGFloat(items.count + 1)
        let h = lineH(fFooter)
        let midY = box.midY
        for (i, item) in items.enumerated() {
            let x = right - 6 - CGFloat(i) * slot
            let sw = CGRect(x: x - 16, y: midY - 5, width: 16, height: 10)
            let sp = UIBezierPath(roundedRect: sw, cornerRadius: 2)
            item.1.setFill()
            sp.fill()
            sp.lineWidth = 0.7
            if item.2 { sp.setLineDash([2, 1.5], count: 2, phase: 0) }
            (item.2 ? goldText : navy).setStroke()
            sp.stroke()
            draw(item.0, in: CGRect(x: x - slot + 4, y: midY - h / 2, width: slot - 26, height: h), font: fFooter, color: muted)
        }
        draw("الرقم تحت الاسم = عدد أفراد فرعه", in: CGRect(x: margin + 6, y: midY - h / 2, width: slot - 8, height: h),
             font: fFooter, color: muted, align: .left)
    }

    // MARK: الحلقات والأشرطة والشجرة المصغّرة (الملخّص)

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

    /// العنوان بالكحلي يميناً وبجانبه النطاق صغيراً، والشعار يساراً، وخطّ كحلي شعري تحتهما
    private static func drawHeader(_ title: String, scope: String, logo: UIImage?) {
        let h = lineH(fHeader)
        let midY = headerTop + headerLogoHeight / 2
        let logoW = logo.map { headerLogoHeight * $0.size.width / max($0.size.height, 1) } ?? 0
        let room = contentWidth - logoW - 16
        let tw = min(textWidth(title, fHeader), room)
        draw(title, in: CGRect(x: right - tw, y: midY - h / 2, width: tw, height: h), font: fHeader, color: navy)
        if !scope.isEmpty, room - tw > 40 {
            let sh = lineH(fFooter)
            draw(scope, in: CGRect(x: right - room, y: midY - sh / 2 + 1, width: room - tw - 10, height: sh),
                 font: fFooter, color: faint)
        }
        if let logo {
            logo.draw(in: CGRect(x: margin, y: headerTop, width: logoW, height: headerLogoHeight))
        }
        navy.setFill()
        UIRectFill(CGRect(x: margin, y: headerRule, width: contentWidth, height: 0.6))
    }

    /// «سرّي — لعائلة المحمدعلي فقط · التاريخ» يميناً، و«صفحة X من Y» يساراً
    private static func drawFooter(page: Int, total: Int, stamp: String) {
        line.setFill()
        UIRectFill(CGRect(x: margin, y: footerLine, width: contentWidth, height: 0.5))
        let y = footerLine + 7
        let h = lineH(fFooterBold)
        let half = contentWidth / 2
        draw(stamp, in: CGRect(x: right - half - 40, y: y, width: half + 40, height: h), font: fFooter, color: faint)
        draw("صفحة \(page) من \(total)", in: CGRect(x: margin, y: y, width: half - 50, height: h),
             font: fFooterBold, color: muted, align: .left)
    }

    // MARK: الفهرس

    /// مدخل: العنوان يميناً، ونقاط، ورقم الصفحة يساراً
    private static func drawTocRow(_ title: String, page: Int, x: CGFloat, width: CGFloat, y: CGFloat) {
        let h = lineH(fToc)
        let num = "\(page)"
        let nw = textWidth(num, fToc) + 2
        let tw = min(textWidth(title, fToc), width - nw - 30)
        draw(title, in: CGRect(x: x + width - tw, y: y, width: tw, height: h), font: fToc, color: ink)
        draw(num, in: CGRect(x: x, y: y, width: nw, height: h), font: fToc, color: navy, align: .left)
        dotted(from: x + nw + 4, to: x + width - tw - 4, y: y + h - 3, color: line)
    }

    private static func drawTocPage(_ entries: [(title: String, page: Int)], first: Bool) {
        var y = contentTop
        if first {
            draw("الفهرس", in: CGRect(x: margin, y: y, width: contentWidth, height: lineH(fSection)), font: fSection, color: navy)
            gold.setFill()
            UIRectFill(CGRect(x: right - 48, y: y + lineH(fSection) + 4, width: 48, height: 1.6))
            y += lineH(fSection) + 18
        }
        for e in entries {
            drawTocRow(e.title, page: e.page, x: margin, width: contentWidth, y: y)
            y += lineH(fToc) + 8
        }
    }

    // MARK: الغلاف

    /// شعار العائلة (`FamilyLogoNavy` — متّجه في الأصول) بالنسخة الفاتحة دائماً
    private static func familyLogo() -> UIImage? {
        UIImage(named: "FamilyLogoNavy", in: .main, compatibleWith: UITraitCollection(userInterfaceStyle: .light))
    }

    /// الشعار صورةً بمقاس رسمه ×٤ (~٣٠٠ نقطة/بوصة) على أرضية معتمة بلون الورقة تحته (كريمي الغلاف، أبيض الصفحات)
    private static func raster(_ logo: UIImage, height: CGFloat, background: UIColor) -> UIImage? {
        guard logo.size.height > 0 else { return nil }
        let size = CGSize(width: (height * logo.size.width / logo.size.height).rounded(.up), height: height.rounded(.up))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 4
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            background.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            logo.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static let coverLogoWidth: CGFloat = 170

    /// السدو (خطّان ومعيّنات خمسة، الأوسط أكبر) — ذهبي رفيع
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

    /// كريمي بإطار ذهبي مزدوج: الشعار، «عائلة المحمدعلي»، سدو، العنوان والنطاق، مربّع البيانات، الفهرس (أو فقرة ما
    /// يحويه)، وختم «سرّي» متحفّظ أسفله
    private static func drawCover(_ doc: AdminReportDoc, total: Int, logo: UIImage?, toc: [(title: String, page: Int)]) {
        let page = CGRect(origin: .zero, size: pageSize)
        cream.setFill()
        UIRectFill(page)
        let outer = UIBezierPath(rect: page.insetBy(dx: 22, dy: 22))
        outer.lineWidth = 1.4
        gold.setStroke()
        outer.stroke()
        let inner = UIBezierPath(rect: page.insetBy(dx: 28, dy: 28))
        inner.lineWidth = 0.5
        inner.stroke()

        let cx = pageSize.width / 2
        var y: CGFloat = toc.isEmpty ? 120 : 84
        if let logo {
            let w = coverLogoWidth
            let h = w * logo.size.height / max(logo.size.width, 1)
            logo.draw(in: CGRect(x: cx - w / 2, y: y, width: w, height: h))
            y += h + 8
        }
        draw(AdminReportText.familyName, in: CGRect(x: margin, y: y, width: contentWidth, height: lineH(fCoverFamily)),
             font: fCoverFamily, color: goldText, align: .center)
        y += lineH(fCoverFamily) + 14
        drawSadu(centerX: cx, y: y, lineLength: 56, unit: 3.2, alpha: 1)
        y += 26

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
        y += 22

        // مربّع البيانات: أبيض بإطار رفيع
        var rows: [(String, String)] = [
            ("التاريخ", "\(AdminReportText.longDate(doc.date)) · \(AdminReportText.time(doc.date)) (توقيت الكويت)"),
            ("أعدّه", doc.generatedBy.isEmpty ? "—" : doc.generatedBy)
        ]
        if let g = doc.grouping { rows.append(("التجميع", g)) }
        rows.append(("العدد", "\(AdminReportText.people(doc.count)) · \(AdminReportText.pages(total))"))
        let blockW: CGFloat = 340
        let labelW: CGFloat = 64
        let bx = cx - blockW / 2
        let valueW = blockW - labelW - 24
        let heights = rows.map { max(textHeight($0.1, width: valueW, font: fCoverValue), lineH(fCoverLabel)) + 10 }
        let boxH = heights.reduce(0, +) + 10
        let box = UIBezierPath(rect: CGRect(x: bx, y: y, width: blockW, height: boxH))
        paper.setFill()
        box.fill()
        box.lineWidth = 0.6
        line.setStroke()
        box.stroke()
        var ry = y + 5
        for (i, r) in rows.enumerated() {
            draw(r.0, in: CGRect(x: bx + blockW - labelW - 10, y: ry + 5, width: labelW, height: lineH(fCoverLabel)),
                 font: fCoverLabel, color: faint)
            draw(r.1, in: CGRect(x: bx + 10, y: ry + 5, width: valueW, height: heights[i]),
                 font: fCoverValue, color: ink, wrap: true)
            ry += heights[i]
        }
        y += boxH + 22

        if !toc.isEmpty {
            draw("الفهرس", in: CGRect(x: bx, y: y, width: blockW, height: lineH(fTocTitle)), font: fTocTitle, color: navy)
            y += lineH(fTocTitle) + 6
            for e in toc {
                drawTocRow(e.title, page: e.page, x: bx, width: blockW, y: y)
                y += lineH(fToc) + 5
            }
        } else if !doc.intro.isEmpty {
            let ih = textHeight(doc.intro, width: blockW, font: fCoverIntro) + 4
            draw(doc.intro, in: CGRect(x: cx - blockW / 2, y: y, width: blockW, height: ih),
                 font: fCoverIntro, color: muted, align: .center, wrap: true)
        }

        // «سرّي» — مستطيل صغير محدّد أسفل الغلاف
        let tw = textWidth(AdminReportText.confidential, fSecret)
        let lh = lineH(fSecret)
        let stampRect = CGRect(x: cx - (tw + 24) / 2, y: pageSize.height - 84, width: tw + 24, height: lh + 10)
        let sp = UIBezierPath(rect: stampRect)
        sp.lineWidth = 0.7
        secret.setStroke()
        sp.stroke()
        draw(AdminReportText.confidential, in: CGRect(x: stampRect.minX, y: stampRect.minY + 5, width: stampRect.width, height: lh),
             font: fSecret, color: secret, align: .center)
    }
}

// MARK: - المهمة خارج الخيط الرئيسي: بناء ← رسم ← حفظ الملف ← صور المعاينة

/// علامة إلغاء تُقرأ من خيط الرسم (تغيّر التصفية أثناء الإنشاء)
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
    let title: String
    let url: URL
    let pages: Int
    let count: Int
    let summary: String
    /// صور أول الصفحات للمعاينة
    let thumbnails: [UIImage]
}

nonisolated enum AdminReportJob {
    static let thumbnailWidth: CGFloat = 220

    static func build(_ request: AdminReportRequest, input: AdminReportInput) -> AdminReportDoc {
        AdminReportBuilder.build(request, input: input)
    }

    /// رسم ← حفظ في مجلد مؤقت ← صور أول `thumbnails` صفحات
    static func render(_ doc: AdminReportDoc, thumbnails count: Int, flag: AdminReportCancelFlag) throws -> AdminReportResult {
        let out = try AdminReportPDF.render(doc, isCancelled: { flag.isCancelled })
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FamilyReports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AdminReportText.kuwait.timeZone
        f.dateFormat = "yyyyMMdd-HHmmss"
        let url = dir.appendingPathComponent("\(doc.kind.fileStem)-\(f.string(from: Date())).pdf")
        try out.data.write(to: url, options: .atomic)
        return AdminReportResult(kind: doc.kind, title: doc.title, url: url, pages: out.pages, count: doc.count,
                                 summary: doc.summaryLine,
                                 thumbnails: thumbnails(out.data, count: count, width: thumbnailWidth))
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
