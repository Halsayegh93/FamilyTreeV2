import SwiftUI

// MARK: - «اليوم» الملموم (طلب المالك ٢٠٢٦-١٠-٢٥)
//
// «ابى لوحة الادارة بعد تكون ملمومة قراب من بعض حتى الهيدر يكون نفس بقية الهيدرات و عادي يكون متمدد شوي مع المربع
// الى عليه» + «حالة النظام نبي صغرهم» + «وابى صفحة الثانية بالتنبيهات تكون احصائيات العائلة»:
// • الرأس رأس التبويبات نفسه (`MainHeaderView`: أيقونة القسم، «الإدارة» وتحتها التحية، وأزرار عارية مثل جرس الرئيسية —
//   `AdminHeaderIcon`)، ثابت فوق التمرير، ولونه يمتد قليلاً تحت أول مربّع (`AdminTodayMetrics.bandGap` + `bandOverlap`).
// • «يحتاج انتباهك» مربّع بصفحتين تُسحبان (`AdminTodayPager`، عائد من الدفعة ١٣): الأرقام الأربعة وسطر «حالة النظام»
//   الصغير، ثم «إحصائيات العائلة» (`AdminFamilyStatsPage`) لمن يرى «المؤشرات» — ونقطتا الصفحة داخل المربّع.
// كل المقاسات هنا (لا أرقام عند الاستعمال).

enum AdminTodayMetrics {
    /// لون الرأس فوق أول مربّع، وكم يمتد تحته (المربّع يصعد عليه)
    static let bandGap: CGFloat = DS.Spacing.sm
    static let bandOverlap: CGFloat = DS.Spacing.xxl
    /// لون الرأس خلف أعلى التمرير — السحب للتحديث يكشف كحلياً لا أبيض
    static let pullReveal: CGFloat = 260
    /// الفراغ بين بطاقات «اليوم» = فراغ شبكة المربّعات (إيقاع واحد «قراب من بعض»)
    static var stack: CGFloat { AdminGrid.spacing }
    /// السطر الصغير أسفل الصفحتين («حالة النظام» وسطر الأعداد): ارتفاعه وزواياه
    static let slimRow: CGFloat = 28
    static let slimRowRadius: CGFloat = DS.Radius.sm
    /// السحب: أقل مسافة يبدأ بها، المسافة التي تقلب الصفحة، المقاومة عند الطرفين، والرمية (السرعة × هذا = مسافة إضافية)
    static let swipeMinimum: CGFloat = 12
    static let swipeDistance: CGFloat = 60
    static let swipeResistance: CGFloat = 0.3
    static let swipeThrow: CGFloat = 0.2
    /// نقطتا الصفحة (العادية، والحالية كبسولة) وشريطهما داخل المربّع في أسفله
    static let pageDot: CGFloat = 6
    static let pageDotActive: CGFloat = 16
    static let pageDotsHeight: CGFloat = 20
}

// MARK: - أزرار الرأس

/// زرّ رأس «اليوم» العاري — كأزرار رؤوس التبويبات (جرس الرئيسية و«عن التطبيق»): رمز أبيض بلمس ٤٤، وعدد أحمر على
/// ركنه (جرس «إشعارات الإدارة») بنفس شارة مربّعات الأقسام
struct AdminHeaderIcon: View {
    let symbol: String
    var count: Int = 0

    var body: some View {
        Image(dsSymbol: symbol)
            .dsGlyph(DS.Glyph.xxl, weight: .semibold)
            .foregroundStyle(DS.Color.headerGlyph)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    AdminTileBadge(kind: .count(count), ring: DS.Color.bandFill)
                        .offset(x: L10n.isArabic ? -AdminTileMetrics.badgeOffset : AdminTileMetrics.badgeOffset,
                                y: -AdminTileMetrics.badgeOffset)
                }
            }
            .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
            .contentShape(Rectangle())
    }
}

// MARK: - المربّع بصفحتين

/// مربّع أبيض واحد يصعد على لون الرأس بصفحات تُسحب أفقياً، ونقاطها في شريط أسفله داخل المربّع (الدفعة ١٣ «خلهم داخل
/// المربع»). الاتجاه عربي صحيح: الأولى على اليمين والثانية على يسارها (السحب يميناً يأتي بها)، وبالإنجليزية بالعكس. يبدأ
/// دائماً بالأولى («يحتاج انتباهك» أولاً). الصفحات بارتفاع أطولها فلا يقفز ما تحته (من أحجام إمكانية الوصول بطول الظاهرة).
/// القارئ الصوتي: الصفحة الظاهرة فقط، والنقاط عنصر قابل للتعديل (أعلى/أسفل) بإجراءين «التالي/السابق». صفحة واحدة
/// (المراقب والمشرف) = المربّع بلا نقاط ولا سحب. كل صفحة تحشو جانبيها وأعلاها، والمربّع يضيف الأسفل.
/// مقسِّم خفيف بلا `TabView` (ارتفاع الصفحات يتبع المحتوى، والاتجاه العربي مضبوط): `AdminPagerLayout` + سحب أفقي — من iOS 18
/// إيماءة UIKit أفقية فقط (`AdminHorizontalPan`) تُلغي لمس ما تحتها حين تبدأ، وقبله `DragGesture` متزامن مع التمرير.
struct AdminTodayPager: View {
    let pages: [AnyView]
    /// اسم كل صفحة للقارئ الصوتي
    let titles: [String]
    @State private var page = 0
    @State private var dragX: CGFloat = 0
    @Environment(\.layoutDirection) private var direction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var count: Int { pages.count }
    private var current: Int { min(max(page, 0), max(count - 1, 0)) }
    private var rtl: Bool { direction == .rightToLeft }

    var body: some View {
        AdminPagerLayout(page: current, drag: dragX, rtl: rtl, matchesHeights: !typeSize.isAccessibilitySize) {
            ForEach(pages.indices, id: \.self) { index in
                pages[index]
                    .environment(\.layoutDirection, direction)
                    .accessibilityHidden(index != current)
                    // الصفحة الأخرى خارج المربّع — لا تلتقط لمساً من هامشه
                    .allowsHitTesting(index == current)
            }
        }
        // الإزاحة بإحداثيات ثابتة (يسار ← يمين) ويُحسب الاتجاه العربي يدوياً؛ كل صفحة ترجع لاتجاه التطبيق
        .environment(\.layoutDirection, .leftToRight)
        .padding(.bottom, count > 1 ? AdminTodayMetrics.pageDotsHeight : DS.Hub.swipePadding)
        .overlay(alignment: .bottom) {
            if count > 1 {
                dots
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous))
        .adminCard(padding: 0)
        .modifier(AdminSwipeGesture(enabled: count > 1, changed: dragged, ended: released))
    }

    // MARK: السحب

    /// يتبع الإصبع — مقاومة عند الطرفين
    private func dragged(_ x: CGFloat) {
        let forward = rtl ? x : -x
        let atEdge = (forward > 0 && current == count - 1) || (forward < 0 && current == 0)
        dragX = x * (atEdge ? AdminTodayMetrics.swipeResistance : 1)
    }

    /// يقلب الصفحة بعد `swipeDistance` أو برمية سريعة (`thrownX` = حيث كانت ستقف)
    private func released(_ x: CGFloat, _ thrownX: CGFloat) {
        let moved = rtl ? x : -x
        let thrown = rtl ? thrownX : -thrownX
        let distance = AdminTodayMetrics.swipeDistance
        var target = current
        if moved > distance || thrown > distance * 2 { target += 1 }
        if moved < -distance || thrown < -distance * 2 { target -= 1 }
        go(min(max(target, 0), count - 1))
    }

    private func go(_ target: Int) {
        if target != current { UISelectionFeedbackGenerator().selectionChanged() }
        withAnimation(reduceMotion ? DSMotion.fade : DS.Anim.smooth) {
            page = target
            dragX = 0
        }
    }

    // MARK: النقاط

    /// نقطتا الصفحة (الحالية كبسولة ذهبية) — الضغط يقلب، والقارئ الصوتي: «الصفحة ١ من ٢: يحتاج انتباهك»
    private var dots: some View {
        HStack(spacing: DS.Spacing.xsm) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? DS.Color.accent : DS.Color.textTertiary.opacity(DS.Opacity.tintStroke))
                    .frame(width: index == current ? AdminTodayMetrics.pageDotActive : AdminTodayMetrics.pageDot,
                           height: AdminTodayMetrics.pageDot)
            }
        }
        .frame(minWidth: DS.Icon.tapTarget, minHeight: AdminTodayMetrics.pageDotsHeight)
        .contentShape(Rectangle())
        .onTapGesture { go(current == count - 1 ? 0 : current + 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("الصفحة \(current + 1) من \(count): \(title(current))",
                                   "Page \(current + 1) of \(count): \(title(current))"))
        .accessibilityHint(L10n.t("اسحب لأعلى أو لأسفل للتبديل", "Swipe up or down to switch"))
        .accessibilityAdjustableAction { step in
            switch step {
            case .increment: go(min(current + 1, count - 1))
            case .decrement: go(max(current - 1, 0))
            @unknown default: break
            }
        }
        .accessibilityAction(named: L10n.t("التالي", "Next")) { go(min(current + 1, count - 1)) }
        .accessibilityAction(named: L10n.t("السابق", "Previous")) { go(max(current - 1, 0)) }
    }

    private func title(_ index: Int) -> String {
        titles.indices.contains(index) ? titles[index] : ""
    }
}

/// الصفحات جنباً إلى جنب بعرض المربّع وارتفاع أطولها (أو الظاهرة: `matchesHeights = false`)؛ الظاهرة في مكانها والأخرى
/// بجانبها (يساراً في العربية) + إزاحة السحب. إحداثيات يسار ← يمين دائماً (الحاوية تفرضها) والاتجاه العربي من `rtl`
struct AdminPagerLayout: Layout {
    var page: Int
    var drag: CGFloat
    var rtl: Bool
    var matchesHeights = true

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let shown = heights.indices.contains(page) ? heights[page] : 0
        return CGSize(width: width, height: matchesHeights ? heights.max() ?? 0 : shown)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() {
            let step = CGFloat(index - page) * bounds.width
            subview.place(at: CGPoint(x: bounds.minX + (rtl ? -step : step) + drag, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: matchesHeights ? bounds.height : nil))
        }
    }
}

// MARK: إيماءة السحب الأفقي

/// السحب الأفقي على المربّع: من iOS 18 إيماءة UIKit (`AdminHorizontalPan`)، وقبله `DragGesture` متزامن مع التمرير
private struct AdminSwipeGesture: ViewModifier {
    let enabled: Bool
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            if enabled {
                content.gesture(AdminHorizontalPan(changed: changed, ended: ended))
            } else {
                content
            }
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: AdminTodayMetrics.swipeMinimum)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        changed(value.translation.width)
                    }
                    .onEnded { value in ended(value.translation.width, value.predictedEndTranslation.width) },
                including: enabled ? .all : .subviews)
        }
    }
}

/// إيماءة UIKit أفقية فقط: لا تبدأ إن كانت الحركة عمودية (تبقى للتمرير)، وحين تبدأ تُلغي لمس الأزرار تحتها
/// (`cancelsTouchesInView`) — السحب لا يفتح الرقم الذي بدأ عليه
@available(iOS 18.0, *)
private struct AdminHorizontalPan: UIGestureRecognizerRepresentable {
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = true
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let x = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            changed(x)
        case .ended:
            ended(x, x + recognizer.velocity(in: recognizer.view).x * AdminTodayMetrics.swipeThrow)
        case .cancelled, .failed:
            ended(0, 0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y)
        }
    }
}

// MARK: - السطر الصغير أسفل الصفحتين

/// شكل السطر الصغير أسفل صفحتي المربّع («حالة النظام»، وسطر أعداد العائلة): رمز صغير ونصّ صغير بلون واحد على تعبئة
/// خفيفة منه بزوايا صغيرة — بطول ٢٨ ولمس ٤٤ بلا إزاحة. `trailing`: «⌄» أو لا شيء
struct AdminSlimRow<Leading: View, Trailing: View>: View {
    let ink: Color
    let fill: Color
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Spacing.xsm) {
            leading()
            Spacer(minLength: DS.Spacing.xs)
            trailing()
        }
        .foregroundColor(ink)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xxs)
        .frame(maxWidth: .infinity, minHeight: AdminTodayMetrics.slimRow)
        .background(RoundedRectangle(cornerRadius: AdminTodayMetrics.slimRowRadius, style: .continuous).fill(fill))
        .dsTapArea(width: DS.Icon.tapTarget, height: AdminTodayMetrics.slimRow)
    }
}

// MARK: - «إحصائيات العائلة» (الصفحة الثانية)

/// أعداد العائلة من البيانات المحمّلة أصلاً — نفس تعريفات «إحصاء الأفراد» في «المؤشرات ← العائلة» (`AdminMemberCounts`):
/// الرجال = الشجرة بلا المعلّقين، النساء = إناث شجرة النساء، المسجّلون = لهم حساب دخول؛ والفروع = أبناء رأس الشجرة
/// المباشرون (كتقرير «سجل العائلة بالفروع»)، و«هذا الشهر» = من قُيّد في الشجرة هذا الشهر (كـ«جديد هذا الشهر» في «المؤشرات»).
/// nil = لم يُعرف بعد («—»)
struct AdminFamilyStats: Equatable {
    var counts = AdminMemberCounts()
    var branches: Int? = nil
    var joinedThisMonth: Int? = nil
    /// «خارج العائلة» — نفس تعريف حلقة صفحة «العائلة» (`AdminFamilyCensus`): أبناء البنات وأزواجهن من خارج العائلة + نساء خارجها
    var outsideMale: Int? = nil
    var outsideFemale: Int? = nil
    var outsideTotal: Int? { outsideMale.flatMap { m in outsideFemale.map { m + $0 } } }

    @MainActor
    static func make(members all: [FamilyMember]) -> AdminFamilyStats {
        var s = AdminFamilyStats()
        s.counts = AdminMemberCounts.seeded(members: all)
        guard !all.isEmpty else { return s }
        let census = AdminFamilyCensus.make(members: all, women: WomenStore.cache)
        s.outsideMale = census.outsideMale
        s.outsideFemale = census.outsideFemale

        let tree = all.filter { $0.role != .pending }
        if let root = BranchPickerSheet.familyRoot(in: tree) {
            s.branches = tree.filter { $0.fatherId == root.id && $0.hasName && !$0.isWomanAccount }.count
        }
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        s.joinedThisMonth = all.filter { m in
            guard m.hasName, let created = ApprovalWorkflow.date(m.createdAt) else { return false }
            return created >= monthStart
        }.count
        return s
    }
}

/// «إحصائيات العائلة»: العنوان ورابط «المؤشرات»، ثم أربعة أرقام بشكل أرقام «يحتاج انتباهك» (الأفراد · الرجال · النساء ·
/// المسجّلون — كل رقم يفتح بيته)، ثم سطر صغير: الأحياء · المتوفون · الفروع · هذا الشهر. «≈» للأحياء ما دام في كبار السن من
/// لم يُراجَع (نفس «أحياء (تقديري)»)
struct AdminFamilyStatsPage: View {
    let stats: AdminFamilyStats
    @ObservedObject private var verified = AdminLivingVerifiedStore.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Target { case overview, directory, women, accounts, outside }

    /// أحياء تقديريون: في «تحقق من الأحياء» من لم يراجعه المستخدم
    private var estimated: Bool {
        (stats.counts.oldLiving.map { $0.subtracting(verified.ids).count } ?? 0) > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Hub.swipeGap) {
            AdminCardHeader(title: L10n.t("إحصائيات العائلة", "Family statistics")) {
                link(.overview, face: AnyView(insightsLink))
            }
            numbers
        }
        .padding(.horizontal, DS.Hub.swipePadding)
        .padding(.top, DS.Hub.swipePadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("إحصائيات العائلة", "Family statistics"))
    }

    // MARK: الأرقام

    /// حلقات صفحة «العائلة» نفسها + «المستخدمين» (طلب المالك ٢٠٢٦-١١-٠٩): العنوان فوق الحلقة، العدد في وسطها،
    /// والحلقة نسبة الأحياء (والمستخدمين: نسبة المسجّلين من الأحياء)، وتحتها سطران صغيران
    private struct Ring: Identifiable {
        let id: String
        let title: String
        let tint: Color
        let total: Int?
        let progress: Double?
        let line1: String
        let line2: String
        let target: Target
    }

    private var rings: [Ring] {
        let c = stats.counts
        func share(_ part: Int?, _ whole: Int?) -> Double? {
            guard let part, let whole, whole > 0 else { return nil }
            return Double(part) / Double(whole)
        }
        // «المستخدمين» (طلب المالك ٢٠٢٦-١١-٠٩): العدد = من لهم رقم هاتف، والحلقة من دخل منهم؛ تحتها دخلوا · ما دخلوا أبداً
        // صياغة يفهمها المدير الجديد (طلب المالك ٢٠٢٦-١١-٠٩): من فتح التطبيق، ومن له رقم ولم يفتحه بعد
        let users = (c.accounts.map { L10n.t("\($0) فتحوا التطبيق", "\($0) opened the app") } ?? "—",
                     c.neverLogged.map { L10n.t("\($0) لم يفتحوه بعد", "\($0) not yet") } ?? "—")
        return [
            Ring(id: "total", title: L10n.t("الإجمالي", "Total"), tint: DS.Color.accent, total: c.total,
                 progress: share(c.totalAlive, c.total),
                 line1: Self.aliveText(c.totalAlive, estimated: estimated), line2: Self.deceasedText(c.totalDeceased),
                 target: .overview),
            Ring(id: "men", title: L10n.t("الرجال", "Men"), tint: DS.Color.male, total: c.men,
                 progress: share(c.menAlive, c.men),
                 line1: Self.aliveText(c.menAlive, estimated: estimated), line2: Self.deceasedText(c.menDeceased), target: .directory),
            Ring(id: "women", title: L10n.t("النساء", "Women"), tint: DS.Color.female, total: c.women,
                 progress: share(c.womenAlive, c.women),
                 line1: Self.aliveText(c.womenAlive, estimated: false), line2: Self.deceasedText(c.womenDeceased), target: .women),
            Ring(id: "outside", title: L10n.t("خارج العائلة", "Outside"), tint: DS.Color.slate, total: stats.outsideTotal,
                 progress: share(stats.outsideMale, stats.outsideTotal),
                 line1: stats.outsideMale.map { L10n.t("\($0) ذكور", "\($0) male") } ?? "—",
                 line2: stats.outsideFemale.map { L10n.t("\($0) إناث", "\($0) female") } ?? "—", target: .outside),
            Ring(id: "users", title: L10n.t("المستخدمين", "Users"), tint: DS.Color.success.dsReadableGlyph, total: c.withPhone,
                 progress: share(c.accounts, c.withPhone),
                 line1: users.0, line2: users.1, target: .accounts)
        ]
    }

    @ViewBuilder
    private var numbers: some View {
        if typeSize.isAccessibilitySize {
            // أحجام إمكانية الوصول: كل حلقة صفّ (حلقة صغيرة بجانب الاسم والعدد)
            VStack(spacing: DS.Spacing.xs) {
                ForEach(rings) { r in
                    link(r.target, face: AnyView(HStack(spacing: DS.Spacing.md) {
                        DSRingGauge(progress: r.progress, tint: r.tint, size: DS.Ring.mediumStacked,
                                    track: DS.Ring.restTrack, center: .count(r.total))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: "\(r.title) \(r.total.map { "\($0)" } ?? "—")")
                                .dsFont(.hubRow).foregroundColor(r.tint)
                            Text(verbatim: "\(r.line1) · \(r.line2)")
                                .dsFont(.caption).foregroundColor(DS.Color.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: DS.Icon.tapTarget)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoken(r))))
                }
            }
        } else {
            HStack(alignment: .top, spacing: DS.Spacing.xxs) {
                ForEach(rings) { r in
                    link(r.target, face: AnyView(column(r)))
                }
            }
        }
    }

    private func column(_ r: Ring) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            Text(r.title)
                .dsFont(.hubLabel)
                .foregroundColor(r.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            DSRingGauge(progress: r.progress, tint: r.tint, size: DS.Ring.todayCensus,
                        track: DS.Ring.restTrack, center: .count(r.total))
            VStack(spacing: 0) {
                Text(verbatim: r.line1).foregroundColor(r.tint)
                Text(verbatim: r.line2).foregroundColor(DS.Color.textTertiary)
            }
            .dsFont(.micro)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(r))
    }

    private func spoken(_ r: Ring) -> String {
        "\(r.title) \(r.total.map { "\($0)" } ?? "—")، \(r.line1)، \(r.line2)"
    }

    private func hairline(horizontal: Bool) -> some View {
        Rectangle()
            .fill(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke))
            .frame(width: horizontal ? nil : DS.Border.width, height: horizontal ? DS.Border.width : nil)
            .accessibilityHidden(true)
    }

    /// «المؤشرات ‹» في طرف العنوان — بلا تكبير سطر العنوان (لمس ٤٤ بلا إزاحة)
    private var insightsLink: some View {
        HStack(spacing: DS.Spacing.xxs) {
            Text(L10n.t("المؤشرات", "Insights"))
                .dsFont(.hubButton)
                .lineLimit(1)
            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .dsGlyph(DS.Glyph.sm, weight: .semibold)
        }
        .foregroundColor(DS.Color.accent)
        .frame(minHeight: DS.Icon.section)
        .dsTapArea(width: DS.Icon.tapTarget, height: DS.Icon.section)
        .accessibilityLabel(L10n.t("المؤشرات: إحصاء الأفراد كاملاً", "Insights: the full family census"))
    }

    // MARK: الروابط

    @ViewBuilder
    private func link(_ target: Target, face: AnyView) -> some View {
        switch target {
        case .women:
            // شجرة النساء تُدار من تبويب الشجرة (كحلقة «النساء» في «إحصاء الأفراد»)
            Button {
                TreeTabContainer.openWomenOnAppear = true
                NotificationCenter.default.post(name: .openWomenTree, object: nil)
            } label: { face }
            .buttonStyle(DSPressStyle())
        default:
            NavigationLink { AdminLazyPage { Self.page(target) } } label: { face }
                .buttonStyle(DSPressStyle())
        }
    }

    private static func page(_ target: Target) -> AnyView {
        let today = L10n.t("اليوم", "Today")
        switch target {
        case .overview:  return AnyView(AdminAreaGate(area: .metrics) { AnyView(AdminAnalyticsView()) }
                                            .adminArea(.metrics).adminBackTitle(today))
        case .directory: return AnyView(AdminMembersPage().adminArea(.family).adminBackTitle(today))
        case .accounts:  return AnyView(AdminMembersPage(chip: .registered).adminArea(.family).adminBackTitle(today))
        case .outside:   return AnyView(AdminMembersPage(womenOutside: true).adminArea(.family).adminBackTitle(today))
        case .women:     return AnyView(EmptyView())
        }
    }

    // MARK: النصوص (المعدود بالعربية الصحيحة)

    /// «2,582 حياً» (حيّ واحد، حيّان، 3 أحياء) — «≈» إن كانوا تقديريين
    static func aliveText(_ n: Int?, estimated: Bool) -> String {
        guard let n else { return L10n.t("— أحياء", "— living") }
        let text = L10n.isArabic
            ? AdminTodayText.arabicCount(n, one: "حيّ واحد", two: "حيّان", few: "أحياء", many: "حياً", single: "حيّ")
            : "\(n) living"
        return estimated ? "≈ " + text : text
    }

    /// «557 متوفى» (متوفى واحد، متوفيان، 3 متوفين)
    static func deceasedText(_ n: Int?) -> String {
        guard let n else { return L10n.t("— متوفون", "— deceased") }
        return L10n.isArabic
            ? AdminTodayText.arabicCount(n, one: "متوفى واحد", two: "متوفيان", few: "متوفين", many: "متوفى", single: "متوفى")
            : "\(n) deceased"
    }

    /// «5 فروع» (فرع واحد، فرعان، 11 فرعاً)
    static func branchesText(_ n: Int) -> String {
        L10n.isArabic
            ? AdminTodayText.arabicCount(n, one: "فرع واحد", two: "فرعان", few: "فروع", many: "فرعاً", single: "فرع")
            : (n == 1 ? "1 branch" : "\(n) branches")
    }
}
