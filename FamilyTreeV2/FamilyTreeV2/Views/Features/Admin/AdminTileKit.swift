import Foundation
#if !ADMIN_LOGIC_TEST
import SwiftUI
#endif

// MARK: - مربّعات اللوحة (إعادة التصميم ٢٠٢٦-١١-٢٦ — spec A.8 وA.12 وA.16، الوحدة U4)
//
// نوعان من المربّعات:
//  ١) مربّع القسم `AdminRowTile` («اليوم ← الأقسام»): بطاقة بيضاء بخطّ رفيع بلا ظلّ (زاوية ١٢، حشوة ١٢، أقل ارتفاع ٧٦)،
//     مربّع أيقونة ٣٠ ممتلئ بلون القسم في البداية فوق، الاسم ١٥ متوسط، وتحته **سطر الحالة** ١٣: جملة قصيرة تقول حال القسم
//     بكلمة بدل الشارات الحمراء (spec E.16) — «2 عاجل»، «4 مشكلات في الشجرة»، «الرصيد منخفض»، «يعمل للجميع».
//     أربع نغمات (`AdminTileTone`): محايد رمادي · انتباه (`warning` + ⓘ ممتلئة) · عاجل (`error` + الرمز نفسه بنبضة هادئة)
//     · سليم (رمادي + ✓ `success` في الطرف). والقسم «للاطلاع» يُختم سطره بـ«للاطلاع».
//     **حال المخزن** (`AdminStoreHealth`، AdminContracts.swift — spec T1): الكلمة الهادئة لا تظهر إلا بعد وصول بياناتها.
//     التحميل = سطر هيكل رمادي (المربّع يُضغط فوراً)، الفشل بلا بيانات = «تعذّر التحميل» ↻ رمادي والضغط عليه يعيد جلب
//     مخزنه وحده، الفشل بعد تحميل ناجح = الكلمة + «آخر تحديث 9:12»، المرفوض = لا سطر (أو «للاطلاع»).
//     الشبكة `AdminRowTileGrid`: عمودان بفراغ ١٠، والعدد الفردي يمدّ آخر مربّع بعرض الصفّ (لا يتيم)، وكل صفّ بطول أطول
//     مربّعيه؛ ثلاثة أعمدة أفقياً، وعمود واحد من أحجام إمكانية الوصول. الضغط: يصغر ٠٫٩٧ مع تظليل في ١٢٠ م.ث.
//  ٢) مربّع الأداة `AdminHubTile`/`AdminToolTile` (البحث والأدوات، ومربّع إجراءات شجرة النساء): الأيقونة ٤٤ في الوسط فوق
//     والاسم تحتها — بقي شكله وأخذ سطح البطاقة الجديد (زاوية ١٢ بلا ظلّ) وضغطة المربّع، وتحذيره سطر بنغمة «انتباه»
//     لا شارة حمراء. الشبكة `AdminTileGrid` كما هي (٣ أعمدة، ٢ للعددين ٢ و٤ ومع الخط الكبير جداً، صفوف من أحجام
//     إمكانية الوصول).
//
// الاستعمال (U7):
//   AdminRowTileGrid {
//       ForEach(areas) { area in
//           Button { openAreaFromToday(area) } label: {
//               AdminRowTile(area: area, state: .urgent("2 عاجل"), health: inboxHealth,
//                            retry: { Task { await reloadInbox() } }, readOnly: area.isReadOnly(for: authVM))
//           }
//           .buttonStyle(AdminTilePressStyle())
//       }
//   }
//   • حقيقتان في سطر واحد: `AdminTileState.joined([.urgent("2 عاجل"), .attention("5 بانتظارك")])` («2 عاجل · 5 بانتظارك»).
//   • نغمة حبّة الحالة نفسها (`AdminPillTone` في AdminHubKit): `AdminTileTone(pillTone)` و`tone.pill` — رأس بطاقة الحالة
//     ومربّع قسمها يقرآن من حساب واحد.
//
// الجزء الأول منطق خالص (Foundation) يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u4-logic FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTileKit.swift tests/admin-redesign/U4/main.swift && /tmp/u4-logic

// MARK: - المنطق الخالص

/// نغمة سطر الحالة في مربّع القسم — spec A.8 (الكلمة دائماً، لا لون وحده)
nonisolated enum AdminTileTone: Hashable {
    /// «170 في التطبيق»، «لا شيء قريب» — رمادي بلا رمز
    case neutral
    /// «4 مشكلات في الشجرة»، «الرصيد منخفض» — `warning` + ⓘ ممتلئة
    case attention
    /// «2 عاجل»، «الصيانة مفعّلة» — `error` + الرمز نفسه بنبضة هادئة
    case urgent
    /// «سليمة»، «يعمل للجميع»، «لا جديد» — رمادي + ✓ `success` (بعد وصول البيانات فقط)
    case good

    /// الأقوى يغلب حين تجتمع حقيقتان في سطر واحد
    var rank: Int {
        switch self {
        case .neutral:   return 0
        case .good:      return 1
        case .attention: return 2
        case .urgent:    return 3
        }
    }
}

/// كلمة حال القسم: جملة قصيرة + نغمتها — يبنيها صاحب الصفحة من بيانات مخزنه
nonisolated struct AdminTileState: Hashable {
    var text: String
    var tone: AdminTileTone

    init(_ text: String, tone: AdminTileTone = .neutral) {
        self.text = text
        self.tone = tone
    }

    static func neutral(_ text: String) -> AdminTileState { AdminTileState(text, tone: .neutral) }
    static func attention(_ text: String) -> AdminTileState { AdminTileState(text, tone: .attention) }
    static func urgent(_ text: String) -> AdminTileState { AdminTileState(text, tone: .urgent) }
    static func good(_ text: String) -> AdminTileState { AdminTileState(text, tone: .good) }

    /// حقيقتان أو أكثر في سطر واحد («2 عاجل · 5 بانتظارك») — بترتيبها، ونغمة السطر أقواها. فارغة = nil
    static func joined(_ facts: [AdminTileState]) -> AdminTileState? {
        let live = facts.filter { !$0.text.isEmpty }
        guard let strongest = live.max(by: { $0.tone.rank < $1.tone.rank }) else { return nil }
        return AdminTileState(live.map(\.text).joined(separator: AdminTileText.separator), tone: strongest.tone)
    }
}

/// نصوص المربّعات (المكان الواحد)
nonisolated enum AdminTileText {
    /// فاصل حقيقتين في سطر واحد، وقبل «للاطلاع»
    static let separator = " · "
    /// ختم سطر القسم الذي يشوفه الدور بس — spec A.8
    static var readOnly: String { L10n.t("للاطلاع", "View only") }
    /// نصّ بطول كلمة عادية تحت هيكل التحميل (لا يُقرأ — `.redacted`)
    static var skeletonSample: String { L10n.t("لا جديد الآن", "Nothing new yet") }
    /// تحذير أداة بلا سطر رقم
    static var needsAttention: String { L10n.t("يحتاج انتباهك", "Needs attention") }
}

/// ما يرسمه سطر الحالة: كلمة المخزن بعد حاله (`AdminStoreHealth.look`) — الفشل لا يُظهر كلمة هادئة أبداً (spec T1)
nonisolated struct AdminTileLine: Hashable {
    nonisolated enum Kind: Hashable {
        /// لا سطر (الاسم وحده)
        case none
        /// هيكل رمادي بشكل الكلمة (`.redacted`)
        case skeleton
        /// الكلمة (+ «آخر تحديث» إن كانت قديمة)
        case word
        /// «تعذّر التحميل» ↻ — والضغط يعيد جلب المخزن وحده
        case unknown
    }

    var kind: Kind
    var text: String
    var tone: AdminTileTone
    /// بيانات قديمة بعد فشل التحديث — «آخر تحديث 9:12» تحت الكلمة
    var staleSince: Date?

    /// لا سطر
    static let empty = AdminTileLine(kind: .none, text: "", tone: .neutral, staleSince: nil)

    /// - state: كلمة القسم (nil = لا كلمة؛ الاسم وحده أو «للاطلاع»)
    /// - health: حال المخزن الذي تُقرأ منه الكلمة — nil = الكلمة جاهزة (مستدعٍ قديم بلا حال مخزن)
    /// - readOnly: القسم للاطلاع لهذا الدور — يُختم السطر بـ«للاطلاع»
    static func make(state: AdminTileState?, health: AdminStoreHealth?, readOnly: Bool) -> AdminTileLine {
        func word(_ since: Date?) -> AdminTileLine {
            let parts = [state?.text, readOnly ? AdminTileText.readOnly : nil].compactMap { $0 }.filter { !$0.isEmpty }
            guard !parts.isEmpty else { return .empty }
            let tone: AdminTileTone = (state?.text.isEmpty ?? true) ? .neutral : (state?.tone ?? .neutral)
            return AdminTileLine(kind: .word, text: parts.joined(separator: AdminTileText.separator), tone: tone,
                                 staleSince: since)
        }
        switch health?.look ?? .word {
        case .word:
            return word(nil)
        case .staleWord(let since):
            return word(since)
        case .skeleton:
            let sample = state.map(\.text).flatMap { $0.isEmpty ? nil : $0 } ?? AdminTileText.skeletonSample
            return AdminTileLine(kind: .skeleton, text: sample, tone: .neutral, staleSince: nil)
        case .unknown:
            return AdminTileLine(kind: .unknown, text: AdminStoreHealthText.failed, tone: .neutral, staleSince: nil)
        case .hidden:
            // المرفوض: لا كلمة ولا إعادة محاولة — «للاطلاع» وحدها إن كان القسم للاطلاع
            return readOnly
                ? AdminTileLine(kind: .word, text: AdminTileText.readOnly, tone: .neutral, staleSince: nil)
                : .empty
        }
    }

    /// ما يقوله القارئ الصوتي بعد اسم القسم
    var spoken: String {
        switch kind {
        case .none:     return ""
        case .skeleton: return AdminStoreHealthText.loading
        case .unknown:  return AdminStoreHealthText.failed
        case .word:
            guard let staleSince else { return text }
            return [text, AdminStoreHealthText.updated(staleSince)].joined(separator: L10n.t("، ", ", "))
        }
    }
}

/// حساب شبكة مربّعات الأقسام: الصفوف بالأعمدة، والصفّ الأخير الناقص تتقاسم مربّعاته عرضه (العدد الفردي يمدّ آخر مربّع)
nonisolated enum AdminTileGridMath {
    /// عمود واحد من أحجام إمكانية الوصول، وإلا أعمدة الوضع (عمودياً/أفقياً)
    static func columns(accessibilitySize: Bool, landscape: Bool, portrait: Int, wide: Int) -> Int {
        accessibilitySize ? 1 : max(1, landscape ? wide : portrait)
    }

    /// مجالات الصفوف: ٥ في عمودين = [0..<2, 2..<4, 4..<5]
    static func rows(count: Int, columns: Int) -> [Range<Int>] {
        guard count > 0 else { return [] }
        let c = max(1, columns)
        return stride(from: 0, to: count, by: c).map { $0..<min($0 + c, count) }
    }

    /// عرض المربّع في صفّ فيه `items` مربّعات (يملؤون عرضه)
    static func itemWidth(rowWidth: CGFloat, items: Int, spacing: CGFloat) -> CGFloat {
        let n = CGFloat(max(1, items))
        return max(0, (rowWidth - spacing * (n - 1)) / n)
    }
}

#if !ADMIN_LOGIC_TEST

// MARK: - المقاسات

/// مقاسات المربّعات (مكانها هنا — لا أرقام عند الاستعمال؛ مربّع القسم من `DS.Hub.areaTile*`)
enum AdminTileMetrics {
    /// مربّع الأداة: الأيقونة الممتلئة ورمزها الأبيض وزاويتها (من سلّم الزوايا)
    static let icon: CGFloat = 44
    static let iconRadius: CGFloat = DS.Radius.md
    static let glyph: CGFloat = DS.Glyph.xxl
    /// حشوة مربّع الأداة: فوق الأيقونة أوسع قليلاً من تحت الاسم (توازن بصري)، والجانبان أضيق (الاسم يتّسع)
    static let paddingTop: CGFloat = DS.Spacing.md
    static let paddingBottom: CGFloat = DS.Spacing.smd
    static let paddingSide: CGFloat = DS.Spacing.sm
    /// أسطر اسم مربّع الأداة: بالحجم الافتراضي، ومع خط الجهاز الأكبر
    static let titleLines = 2
    static let titleLinesLarge = 3
    /// بين الأيقونة والاسم، وبين الاسم وسطر الحالة
    static let gap: CGFloat = DS.Spacing.sm
    static let captionGap: CGFloat = DS.Spacing.xxs
    /// زاوية كل المربّعات = زاوية بطاقة اللوحة ١٢ — spec A.5/A.8 (كانت ١٨ `DS.Hub.tileRadius`، باقية لغير المربّعات)
    static var radius: CGFloat { DS.Hub.cardRadius }
    /// شارة العدد على ركن أيقونة مربّع الأداة: ارتفاعها الأدنى وكم تخرج من الركن
    static let badge: CGFloat = 20
    static let badgeOffset: CGFloat = DS.Spacing.xsm
    /// الصفّ (أحجام إمكانية الوصول لمربّع الأداة): حشوته
    static let rowPadding: CGFloat = DS.Spacing.md
    /// أصغر تصغير لنصّ يُحجز له سطر (اسم مربّع الأداة وسطره)
    static let titleMinScale: CGFloat = 0.85
    static let captionMinScale: CGFloat = 0.8
    /// أعمدة شبكة مربّعات الأدوات أفقياً: كلها في صفّ واحد حتى ستة
    static let landscapeMaxColumns = 6
    /// مربّع القسم: بين مربّع الأيقونة والنص (spec A.8 / العيّنة ١٠)، وأعمدة الشبكة أفقياً
    static let areaIconGap: CGFloat = DS.Spacing.smd
    static let areaColumnsLandscape = 3
    /// لمس «تعذّر التحميل» ↻ يتّسع فوق السطر وتحته (حتى حافة المربّع) فيقارب ٤٤ دون أن يغطي الاسم
    static let retryHitBleed: CGFloat = DS.Spacing.md
}

// MARK: - النغمة ← الألوان والرموز

extension AdminTileTone {
    /// من نغمة حبّة الحالة (AdminHubKit) — `unknown` حال مخزن لا نغمة كلمة، فتصير محايدة (الفشل يرسمه `health:`)
    init(_ pill: AdminPillTone) {
        switch pill {
        case .ok:            self = .good
        case .off, .unknown: self = .neutral
        case .warn:          self = .attention
        case .error:         self = .urgent
        }
    }

    /// نغمة حبّة الحالة المقابلة — رأس بطاقة الحالة يقول ما يقوله مربّع قسمها
    var pill: AdminPillTone {
        switch self {
        case .neutral:   return .off
        case .attention: return .warn
        case .urgent:    return .error
        case .good:      return .ok
        }
    }

    /// لون نصّ السطر: الانتباه والعاجل بلون الحبّة، والمحايد والسليم رماديان (السليم تقوله العلامة)
    var textInk: Color {
        switch self {
        case .neutral, .good:     return DS.Color.textTertiary
        case .attention, .urgent: return pill.ink
        }
    }
}

// MARK: - السطح والضغط

private struct AdminTilePressedKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// المربّع مضغوط الآن (من `AdminTilePressStyle`) — سطحه يتظلّل (`DS.Hub.rowPress`)
    var adminTilePressed: Bool {
        get { self[AdminTilePressedKey.self] }
        set { self[AdminTilePressedKey.self] = newValue }
    }
}

/// ضغطة المربّع (spec A.8/A.16): يصغر ٠٫٩٧ ويتظلّل سطحه في ١٢٠ م.ث (`DS.Hub.tilePress`) — «تقليل الحركة»: التظليل فقط.
/// الإطار لا يتغيّر (التصغير بصري، لا يزيح ما حوله)
struct AdminTilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AdminTilePressLabel(configuration: configuration)
    }
}

private struct AdminTilePressLabel: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .environment(\.adminTilePressed, configuration.isPressed)
            .scaleEffect(configuration.isPressed && !reduceMotion ? DS.Hub.tilePressScale : 1)
            .animation(DS.Hub.tilePress, value: configuration.isPressed)
    }
}

/// سطح المربّع = بطاقة اللوحة (spec A.5): أبيض، خطّ ١ رفيع بارد، زاوية ١٢، بلا ظلّ ولا جلد مجسّم — ويتظلّل مضغوطاً
private struct AdminTileSurface: ViewModifier {
    let pressed: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AdminTileMetrics.radius, style: .continuous)
        return content
            .background(shape.fill(pressed ? DS.Hub.rowPress : DS.Color.cardBackground))
            .overlay(shape.strokeBorder(DS.Hub.cardStroke, lineWidth: DS.Card.strokeWidth))
            .contentShape(shape)
            .animation(DS.Hub.tilePress, value: pressed)
    }
}

// MARK: - سطر الحالة

/// سطر الحالة ١٣: [رمز النغمة] الكلمة [✓ للسليم] — والهيكل، و«تعذّر التحميل» ↻ (زرّ يعيد جلب مخزنه إن مُرّر `retry`)
private struct AdminTileLineView: View {
    let line: AdminTileLine
    var retry: (() -> Void)? = nil
    var centered: Bool = false
    /// nil = يلتفّ كاملاً (مربّع القسم)؛ ١ = سطر محجوز (مربّع الأداة)
    var lineLimit: Int? = nil
    /// خط السطر: ١٣ في مربّع القسم (spec A.8)، و١٢ تحت اسم مربّع الأداة (كرقمه)
    var role: DS.TextRole = .subtitle

    var body: some View {
        switch line.kind {
        case .none:
            EmptyView()
        case .skeleton:
            Text(verbatim: line.text)
                .dsFont(role)
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1)
                .redacted(reason: .placeholder)
                .accessibilityHidden(true)
        case .word:
            VStack(alignment: centered ? .center : .leading, spacing: DS.Spacing.xxs) {
                face(ink: line.tone.textInk, glyph: Self.glyph(line.tone), urgent: line.tone == .urgent,
                     check: line.tone == .good)
                if let since = line.staleSince {
                    AdminStaleStamp(since: since)
                }
            }
        case .unknown:
            if let retry {
                // «تعذّر التحميل» ↻ زرّ داخل المربّع: يعيد جلب مخزنه وحده — وباقي المربّع يفتح القسم كالعادة. لمسه يتّسع
                // بعرض المربّع وفوق السطر وتحته
                Button(action: retry) {
                    unknownFace
                        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                        .padding(.vertical, AdminTileMetrics.retryHitBleed)
                        .padding(.horizontal, DS.Hub.areaTilePadding)
                        .contentShape(Rectangle())
                        .padding(.vertical, -AdminTileMetrics.retryHitBleed)
                        .padding(.horizontal, -DS.Hub.areaTilePadding)
                }
                .buttonStyle(DSPressStyle())
            } else {
                unknownFace
            }
        }
    }

    /// «تعذّر التحميل» ↻ بلون حبّة الحالة المجهولة (`AdminPillTone.unknown` — رمادي، لا كلمة هادئة)
    private var unknownFace: some View {
        face(ink: AdminPillTone.unknown.ink, glyph: "arrow.clockwise", urgent: false, check: false)
    }

    /// رمز قبل الكلمة: ⓘ ممتلئة للانتباه والعاجل (العلامة ✓ للسليم بعدها — كالعيّنة)
    private static func glyph(_ tone: AdminTileTone) -> String? {
        switch tone {
        case .attention, .urgent: return "exclamationmark.circle.fill"
        case .neutral, .good:     return nil
        }
    }

    private func face(ink: Color, glyph: String?, urgent: Bool, check: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
            if let glyph {
                Image(dsSymbol: glyph)
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(ink)
                    // نبضة العاجل على رمزه وحده (الساعة المشتركة — تقف خارج الشاشة ومع «تقليل الحركة») — spec A.16
                    .dsUrgentPulse(DS.Color.error, active: urgent, side: DS.Glyph.sm)
                    .accessibilityHidden(true)
            }
            Text(verbatim: line.text)
                .dsFont(role)
                .monospacedDigit()
                .foregroundColor(ink)
                .multilineTextAlignment(centered ? .center : .leading)
                .lineLimit(lineLimit)
                .minimumScaleFactor(lineLimit == nil ? 1 : AdminTileMetrics.captionMinScale)
                .fixedSize(horizontal: false, vertical: lineLimit == nil)
            if check {
                Image(dsSymbol: "checkmark")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(DS.Color.success)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - مربّع القسم

/// شبكة مربّعات الأقسام (spec A.8): عمودان بفراغ ١٠، والعدد الفردي يمدّ آخر مربّع بعرض الصفّ؛ ثلاثة أفقياً؛ عمود واحد من
/// أحجام إمكانية الوصول. مربّعات الصفّ الواحد بطول واحد (أطولها)
struct AdminRowTileGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dsLandscape) private var landscape

    var body: some View {
        AdminTileRowsLayout(columns: AdminTileGridMath.columns(accessibilitySize: typeSize.isAccessibilitySize,
                                                               landscape: landscape,
                                                               portrait: DS.Hub.areaTileColumns,
                                                               wide: AdminTileMetrics.areaColumnsLandscape),
                            spacing: DS.Hub.areaTileGap) {
            content()
        }
    }
}

/// تخطيط الصفوف: كل صفّ بأعمدته، والصفّ الأخير الناقص تتقاسم مربّعاته عرضه؛ ارتفاع الصفّ = أطول مربّعاته (كل مربّع
/// يمتدّ له). الترتيب من البداية (يُعكس تلقائياً في العربية)
struct AdminTileRowsLayout: Layout {
    var columns: Int
    var spacing: CGFloat

    private struct Row {
        let range: Range<Int>
        let itemWidth: CGFloat
        let height: CGFloat
    }

    /// العرض المقترح محدوداً: الحاويات قد تسأل بلا عرض أو بعرض لا نهائي — نجيب بعرض ثابت (كـ`DSTileGridLayout`)
    private func finiteWidth(_ proposed: CGFloat?) -> CGFloat {
        guard let proposed, proposed.isFinite else { return DS.Landscape.columnMinWidth }
        return max(0, proposed)
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        AdminTileGridMath.rows(count: subviews.count, columns: columns).map { range in
            let w = AdminTileGridMath.itemWidth(rowWidth: width, items: range.count, spacing: spacing)
            let h = range.map { subviews[$0].sizeThatFits(ProposedViewSize(width: w, height: nil)).height }.max() ?? 0
            return Row(range: range, itemWidth: w, height: h)
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = finiteWidth(proposal.width)
        let list = rows(width: width, subviews: subviews)
        let height = list.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, list.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.range {
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: row.itemWidth, height: row.height))
                x += row.itemWidth + spacing
            }
            y += row.height + spacing
        }
    }
}

/// مربّع القسم (spec A.8): [مربّع ٣٠ ممتلئ] الاسم ١٥ ثم سطر الحالة ١٣ — بلا شارة ولا سهم. يوضع داخل زرّ/`NavigationLink`
/// بـ`AdminTilePressStyle`، في `AdminRowTileGrid`
struct AdminRowTile: View {
    let icon: String
    /// تعبئة مربّع الأيقونة (ثابتة تحت رمز أبيض — `AdminArea.fill`)
    let fill: Color
    let title: String
    /// كلمة حال القسم — nil = الاسم وحده (أو «للاطلاع»)
    var state: AdminTileState?
    /// حال المخزن الذي تُقرأ منه الكلمة — nil = الكلمة جاهزة
    var health: AdminStoreHealth?
    /// إعادة جلب مخزن الكلمة وحده (حين فشل بلا بيانات) — nil = «تعذّر التحميل» بلا ضغطة
    var retry: (() -> Void)?
    /// القسم للاطلاع لهذا الدور — يُختم السطر بـ«للاطلاع»
    var readOnly: Bool
    /// تلميح القارئ الصوتي (وصف القسم)
    var hint: String?
    /// الاسم الكامل للقارئ الصوتي حين يختصره المربّع (`AdminArea.tileTitle`) — nil = `title`
    var spokenTitle: String? = nil
    @Environment(\.adminTilePressed) private var pressed

    init(icon: String, fill: Color, title: String, state: AdminTileState? = nil, health: AdminStoreHealth? = nil,
         retry: (() -> Void)? = nil, readOnly: Bool = false, hint: String? = nil) {
        self.icon = icon
        self.fill = fill
        self.title = title
        self.state = state
        self.health = health
        self.retry = retry
        self.readOnly = readOnly
        self.hint = hint
    }

    /// مربّع قسم من `AdminArea`: رمزه ولونه واسمه ووصفه للقارئ الصوتي
    init(area: AdminArea, state: AdminTileState? = nil, health: AdminStoreHealth? = nil,
         retry: (() -> Void)? = nil, readOnly: Bool = false) {
        self.init(icon: area.icon, fill: area.fill, title: area.tileTitle, state: state, health: health, retry: retry,
                  readOnly: readOnly, hint: area.subtitle)
        spokenTitle = area.title
    }

    /// القديم: سطر صغير + شارة حمراء — الشارة تصير سطر حالة بنغمة «انتباه» والسطر يلحقها (spec E.16)
    @available(*, deprecated, message: "use AdminRowTile(area:state:health:retry:readOnly:) — a state line, no badge; U21 removes")
    init(icon: String, ink: Color, title: String, caption: String? = nil, badge: AdminTileBadge.Kind? = nil,
         badgeSpoken: String? = nil, index: Int = 0, hint: String? = nil) {
        let badgeText = badge.map { badgeSpoken ?? AdminTileBadge.spoken($0) }
        let state = AdminTileState.joined([badgeText.map { AdminTileState.attention($0) },
                                           caption.map { AdminTileState.neutral($0) }].compactMap { $0 })
        self.init(icon: icon, fill: ink.dsSolidFill, title: title, state: state, hint: hint)
    }

    var body: some View {
        let line = AdminTileLine.make(state: state, health: health, readOnly: readOnly)
        HStack(alignment: .top, spacing: AdminTileMetrics.areaIconGap) {
            AdminIconSquare(symbol: icon, tint: fill, filled: true)
            VStack(alignment: .leading, spacing: AdminTileMetrics.captionGap) {
                Text(title)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                AdminTileLineView(line: line, retry: retry)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.Hub.areaTilePadding)
        .padding(.vertical, DS.Hub.areaTilePaddingV)
        .frame(maxWidth: .infinity, minHeight: DS.Hub.areaTileMinHeight, maxHeight: .infinity, alignment: .topLeading)
        .modifier(AdminTileSurface(pressed: pressed))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([spokenTitle ?? title, line.spoken].filter { !$0.isEmpty }.joined(separator: L10n.t("، ", ", ")))
        .accessibilityHint(hint ?? "")
        .accessibilityActions {
            if line.kind == .unknown, let retry {
                Button(AdminStoreHealthText.retry, action: retry)
            }
        }
    }
}

extension AdminArea {
    /// حبر القسم (نصّ/رمز على السطح — يتكيّف مع الداكن) — قرين `fill`
    var ink: Color {
        switch self {
        case .inbox:     return DS.Color.primary
        case .family:    return DS.Color.palm
        case .occasions: return DS.Color.sadu
        case .metrics:   return DS.Color.accent
        case .team:      return DS.Color.primary
        case .app:       return DS.Color.slate
        }
    }
}

// MARK: - مربّع الأداة (البحث والأدوات)

/// شبكة مربّعات الأدوات: أعمدة متساوية بفراغ واحد (`AdminGrid.spacing`) — كل مربّع بعرض عموده وطوله واحد
struct AdminTileGrid<Content: View>: View {
    let count: Int
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dsLandscape) private var landscape

    var body: some View {
        LazyVGrid(columns: Self.columns(count: count, typeSize: typeSize, landscape: landscape),
                  alignment: .center, spacing: AdminGrid.spacing) {
            content()
        }
    }

    /// ٣ أعمدة (الستة صفّان)، و٢ حين يكون العدد ٢ أو ٤ (صفوف كاملة بلا خانة فارغة) أو مع الخط الكبير جداً، وعمود واحد من
    /// أحجام إمكانية الوصول (المربّع صفّ). أفقياً: كلها في صفّ واحد حتى ستة
    static func columns(count: Int, typeSize: DynamicTypeSize, landscape: Bool) -> [GridItem] {
        if typeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: AdminGrid.spacing)]
        }
        let n: Int
        if landscape { n = max(1, min(count, AdminTileMetrics.landscapeMaxColumns)) }
        else if count <= 1 { n = 1 }
        else if count == 2 || count == 4 || typeSize >= .xxxLarge { n = DS.Hub.areaColumnsLargeText }
        else { n = DS.Hub.areaColumns }
        return Array(repeating: GridItem(.flexible(), spacing: AdminGrid.spacing, alignment: .top), count: n)
    }
}

/// شارة على ركن أيقونة مربّع الأداة: عدد أو علامة تنبيه — بحلقة بلون السطح تفصلها عن الأيقونة. **ليست لمربّعات الأقسام**
/// (spec E.16: سطر الحالة بدلها). الشارة نفسها على جرس رأس «اليوم» (حلقتها بلون الرأس)
struct AdminTileBadge: View {
    enum Kind: Equatable {
        case count(Int)
        case alert
    }

    let kind: Kind
    /// تعبئة ثابتة تحت نص أبيض — أحمر للعدد و«!»، أو لون مجموعة الأداة
    var fill: Color = DS.Color.errorFill
    /// الحلقة حولها: لون ما تحتها (سطح المربّع، أو الرأس الكحلي)
    var ring: Color = DS.Color.cardBackground

    var body: some View {
        Group {
            switch kind {
            case .count(let n):
                Text(verbatim: n > 99 ? "99+" : "\(n)")
                    .dsFont(.badge)
                    .monospacedDigit()
            case .alert:
                Image(systemName: "exclamationmark")
                    .dsGlyph(DS.Glyph.xs, weight: .heavy)
            }
        }
        .foregroundColor(DS.Color.textOnPrimary)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, DS.Spacing.xsm)
        .frame(minWidth: AdminTileMetrics.badge, minHeight: AdminTileMetrics.badge)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(ring, lineWidth: DS.Border.widthBold))
        .accessibilityHidden(true)
    }

    /// نصّ الشارة للقارئ الصوتي
    static func spoken(_ kind: Kind) -> String {
        switch kind {
        case .count(let n): return L10n.t("\(n) بانتظارك", "\(n) waiting")
        case .alert:        return AdminTileText.needsAttention
        }
    }
}

/// وجه مربّع الأداة: الأيقونة الممتلئة في الوسط فوق ← الاسم في الوسط (سطران محجوزان) ← سطر الرقم/الحالة (اختياري، محجوز
/// إن طُلب) — والشارة على ركن الأيقونة. سطح بطاقة اللوحة (زاوية ١٢ بلا ظلّ). يوضع داخل زرّ بـ`AdminTilePressStyle`
struct AdminHubTile: View {
    let icon: String
    /// تعبئة مربّع الأيقونة (ثابتة تحت رمز أبيض — `AdminArea.fill` أو `tint.dsSolidFill`)
    let fill: Color
    let title: String
    /// رقم حيّ صغير تحت الاسم («53 فرد»، «3 الآن»)
    var caption: String? = nil
    var captionTint: Color = DS.Color.textTertiary
    /// نغمة السطر (تحذير الأداة = `.attention`: لون التحذير ورمزه بدل الشارة الحمراء) — nil = `captionTint` بلا رمز
    var captionTone: AdminTileTone? = nil
    /// يحجز سطر الرقم وإن لم يصل بعد — مربّعات الشبكة الواحدة بطول واحد
    var reservesCaption: Bool = false
    var badge: AdminTileBadge.Kind? = nil
    var badgeFill: Color = DS.Color.errorFill
    /// ما تقوله الشارة للقارئ الصوتي («6 طلبات بانتظار القرار») — nil = النص العام
    var badgeSpoken: String? = nil
    /// ترتيبه في الشبكة — قفزة الأيقونات تباعاً
    var index: Int = 0
    /// تلميح القارئ الصوتي (وصف الأداة)
    var hint: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.adminTilePressed) private var pressed

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                rowFace
            } else {
                tileFace
            }
        }
        .modifier(AdminTileSurface(pressed: pressed))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint(hint ?? "")
    }

    /// أسطر الاسم المحجوزة: سطران بالحجم الافتراضي وما دونه، وثلاثة فوقه
    private var titleLines: Int { typeSize > .large ? AdminTileMetrics.titleLinesLarge : AdminTileMetrics.titleLines }

    private var spoken: String {
        [title, caption, badge.map { badgeSpoken ?? AdminTileBadge.spoken($0) }]
            .compactMap { $0 }.joined(separator: L10n.t("، ", ", "))
    }

    /// السطر تحت الاسم: بنغمته إن كانت له (رمز ولون)، وإلا الرقم بلونه الممرّر
    @ViewBuilder
    private func captionView(centered: Bool, lineLimit: Int?) -> some View {
        if let caption {
            if let captionTone {
                AdminTileLineView(line: AdminTileLine(kind: .word, text: caption, tone: captionTone, staleSince: nil),
                                  centered: centered, lineLimit: lineLimit, role: .caption)
            } else {
                Text(verbatim: caption)
                    .dsFont(.caption)
                    .monospacedDigit()
                    .foregroundColor(captionTint)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .lineLimit(lineLimit)
                    .minimumScaleFactor(lineLimit == nil ? 1 : AdminTileMetrics.captionMinScale)
                    .fixedSize(horizontal: false, vertical: lineLimit == nil)
            }
        }
    }

    private var tileFace: some View {
        VStack(spacing: AdminTileMetrics.gap) {
            AdminTileIcon(icon: icon, fill: fill, badge: badge, badgeFill: badgeFill, index: index)
            // المحجوز (مخفي) يعطي كل المربّعات طولاً واحداً: سطرا الاسم (ثلاثة مع خط أكبر من الافتراضي — الأسماء الطويلة
            // لا تُقصّ) + سطر الرقم؛ والظاهر يلتصق بأعلاه — الرقم تحت الاسم مباشرة مهما كان الاسم سطراً أو أكثر
            ZStack(alignment: .top) {
                VStack(spacing: AdminTileMetrics.captionGap) {
                    Text(verbatim: " ").dsFont(.hubRow).lineLimit(titleLines, reservesSpace: true)
                    if reservesCaption || caption != nil {
                        Text(verbatim: " ").dsFont(.caption).lineLimit(1)
                    }
                }
                .hidden()
                .accessibilityHidden(true)
                VStack(spacing: AdminTileMetrics.captionGap) {
                    Text(title)
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(titleLines)
                        .minimumScaleFactor(AdminTileMetrics.titleMinScale)
                    captionView(centered: true, lineLimit: 1)
                }
            }
        }
        .padding(.top, AdminTileMetrics.paddingTop)
        .padding(.bottom, AdminTileMetrics.paddingBottom)
        .padding(.horizontal, AdminTileMetrics.paddingSide)
        .frame(maxWidth: .infinity)
    }

    /// أحجام إمكانية الوصول: صفّ — الأيقونة بجانب الاسم والرقم، والشارة ثم السهم في الطرف (كصفوف الإعدادات)
    private var rowFace: some View {
        HStack(spacing: DS.Spacing.md) {
            AdminTileIcon(icon: icon, fill: fill, badge: nil, badgeFill: badgeFill, index: index)
            VStack(alignment: .leading, spacing: AdminTileMetrics.captionGap) {
                Text(title)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                captionView(centered: false, lineLimit: nil)
            }
            Spacer(minLength: DS.Spacing.xs)
            if let badge {
                AdminTileBadge(kind: badge, fill: badgeFill)
            }
            DSChevron()
        }
        .padding(AdminTileMetrics.rowPadding)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
    }
}

/// أيقونة مربّع الأداة الممتلئة (رمز أبيض) — تقفز مرة عند الظهور بترتيبها، والشارة على ركنها
private struct AdminTileIcon: View {
    let icon: String
    let fill: Color
    let badge: AdminTileBadge.Kind?
    let badgeFill: Color
    let index: Int

    var body: some View {
        Image(dsSymbol: icon)
            .dsGlyph(AdminTileMetrics.glyph, weight: .semibold)
            .foregroundColor(DS.Color.textOnPrimary)
            .frame(width: AdminTileMetrics.icon, height: AdminTileMetrics.icon)
            .background(RoundedRectangle(cornerRadius: AdminTileMetrics.iconRadius, style: .continuous).fill(fill))
            .overlay(alignment: .topTrailing) {
                if let badge {
                    AdminTileBadge(kind: badge, fill: badgeFill)
                        .offset(x: L10n.isArabic ? -AdminTileMetrics.badgeOffset : AdminTileMetrics.badgeOffset,
                                y: -AdminTileMetrics.badgeOffset)
                }
            }
            // قفزة الظهور تباعاً — بعد أيقونة الرأس بإيقاع الأقسام (تلاشٍ فقط مع «تقليل الحركة»)
            .modifier(DSIconPop(delay: DSMotion.staggerDelay(index, base: DSMotion.iconDelay)))
            .accessibilityHidden(true)
    }
}

/// مربّع أداة من فهرس الأدوات — يفتح صفحتها كما يفتحها صفّها (`AdminToolRow`)، أو ينفّذ إجراءها. التحذير سطر بنغمة
/// «انتباه» (لون التحذير ورمزه) لا شارة حمراء — spec E.16
struct AdminToolTile: View {
    let tool: AdminTool
    var caption: String? = nil
    var warn: Bool = false
    var reservesCaption: Bool = false
    var index: Int = 0

    var body: some View {
        switch tool.kind {
        case .page(let make):
            // اسم القسم على زرّ «رجوع» الصفحة الداخلية، وقسمها في قائمة العنوان (مثل الصفّ)
            NavigationLink { AdminLazyPage(make: make).adminBackTitle(tool.area.title).adminArea(tool.area) } label: { face }
                .buttonStyle(AdminTilePressStyle())
        case .action(let run):
            Button(action: run) { face }
                .buttonStyle(AdminTilePressStyle())
        }
    }

    private var face: AdminHubTile {
        AdminHubTile(icon: tool.icon, fill: tool.tint.dsSolidFill, title: tool.title,
                     caption: caption ?? (warn ? AdminTileText.needsAttention : nil),
                     captionTone: warn ? .attention : nil,
                     reservesCaption: reservesCaption, index: index, hint: tool.subtitle)
    }
}

#endif
