import SwiftUI
import Foundation

// MARK: - Notification Names
extension Notification.Name {
    static let memberDeleted = Notification.Name("memberDeleted")
    static let showKinshipPath = Notification.Name("showKinshipPath")
    /// Posted to navigate the tree to a specific member and open their details sheet.
    /// userInfo: ["memberId": UUID]
    static let openMemberInTree = Notification.Name("openMemberInTree")
}

// MARK: - ثوابت الشجرة
private enum TreeConst {
    // Zoom
    static let minScale: CGFloat = 0.2
    static let maxScale: CGFloat = 3.0
    static let defaultScale: CGFloat = 0.60
    static let openNodeScale: CGFloat = 0.75
    static let closeNodeScale: CGFloat = 0.80
    static let kinshipScale: CGFloat = 0.45

    // Durations (nanoseconds)
    static let shortDelay: UInt64 = 100_000_000     // 0.1s
    static let scrollDelay: UInt64 = 250_000_000     // 0.25s
    static let kinshipScrollDelay: UInt64 = 500_000_000 // 0.5s
    static let kinshipSecondScroll: UInt64 = 400_000_000 // 0.4s
    static let highlightDuration: UInt64 = 5_000_000_000 // 5s
    /// مدة وضع صلة القرابة ثم ينتهي وحده (طلب المالك ٢٠٢٦-١٠-٠٩: ٢٠ ثانية مع زرّ إلغاء أسفل الشجرة — كانت ١٨)
    static let kinshipSeconds: Double = 20

}

// MARK: - تخطيط الكانفس (إحداثيات مطلقة — نفس محرّك تبويب النساء)
/// نتيجة حساب مواضع كل العقد المرئية بإحداثيات مطلقة داخل كانفس ثابت.
private struct FamilyLayout {
    var positions: [UUID: CGPoint] = [:]     // الزاوية العليا-اليسرى لكل عقدة
    var depth: [UUID: Int] = [:]
    var heights: [UUID: CGFloat] = [:]       // ارتفاع صندوق كل عقدة
    var childRows: [UUID: [[UUID]]] = [:]     // صفوف أبناء كل أب (لرسم خطوط الربط)
    var connectors: [ConnectorGroup] = []     // خطوط كل أب مع أبنائه — تُبنى مرة مع التخطيط
    var size: CGSize = .zero
    /// مقاسات العقدة التي بُني بها التخطيط — العقد والخطوط والكاميرا تقرأها من هنا فتتطابق دائماً
    var m = FamilyTreeMetrics(k: 1)
}

/// أبعاد العقدة الدائرية + فجوات الكانفس × معامل «حجم النص» (`DS.TreeScale`، طلب المالك ٢٠٢٦-١٠-٠٨):
/// العقدة والفجوات والخطوط تكبر معاً فلا تتراكب. تُحسب مرة مع كل تخطيط (لا لكل عقدة في كل إطار).
/// الأرقام = مقاس «كبير» (الافتراضي) — نفس الشكل السابق تماماً عند المعامل ١.
private struct FamilyTreeMetrics: Equatable {
    let k: CGFloat
    let nodeW: CGFloat        // عرض صندوق العقدة (الدائرة 105 + الإطار)
    let circleFull: CGFloat   // ارتفاع الدائرة + حلقة الرتبة
    let nameH: CGFloat        // كبسولة الاسم
    let lifeH: CGFloat        // سطر سنوات المتوفّى
    let hGap: CGFloat         // بين الإخوة أفقيًا
    let vGap: CGFloat         // بين الأب وأبنائه عموديًا (عُوّضت مساحة شريحة التوسيع المحذوفة)
    let rowGap: CGFloat       // بين صفوف الأبناء الملتفّة — يتّسع لخط الصف فوقه
    let spineRoom: CGFloat    // مساحة العمود على جانبي الأبناء الملتفّين (يبقى التمركز)
    let spineOut: CGFloat     // بُعد العمود عن حافة أبعد ابن
    let lineCorner: CGFloat   // استدارة زوايا الخطوط
    let canvasPad: CGFloat    // هامش حول الشجرة

    init(k: CGFloat) {
        self.k = k
        nodeW = 124 * k; circleFull = 112 * k; nameH = 32 * k; lifeH = 20 * k
        hGap = 14 * k; vGap = 48 * k; rowGap = 34 * k
        spineRoom = 18 * k; spineOut = 12 * k; lineCorner = 10 * k; canvasPad = 60 * k
    }

    var nodeHDefault: CGFloat { circleFull + nameH }
    /// ارتفاع صندوق العقدة حسب الحالة (يطابق ترتيب TreeMemberNode: دائرة+اسم[+سنوات]).
    /// شريحة التوسيع أُزيلت — العدّاد صار شارة فوق الصورة (طلب المالك).
    func boxHeight(deceased: Bool) -> CGFloat { circleFull + nameH + (deceased ? lifeH : 0) }
}

/// خطوط أب واحد مع كل أبنائه (كل الصفوف) — تُبنى مرة مع التخطيط بعد المرآة لا كل إطار.
private struct ConnectorGroup: Equatable {
    var pid: UUID? = nil       // الأب — لرسم خطوط آخر أب فُتح بالتدريج
    var path = Path()          // الخطوط العادية
    var kinPath = Path()       // طريق القرابة — ذهبي وأسمك
    var dots: [CGPoint] = []   // نقاط تفرّع الأبناء عن الخط الأفقي
}

/// خطوط كل الآباء وأبنائهم في لوحة واحدة — طبقة مستقلة متساوية (`.equatable()`) فلا يُعاد رسمها مع كل إطار
/// سحب/تكبير (كانت تُرسم من جديد بكل إطار لأن جسم الشجرة يُعاد مع الإزاحة — فحص «اللاق» ٢٠٢٦-١٠-٠٧). نفس الرسم.
private struct TreeConnectorsLayer: View, Equatable {
    let connectors: [ConnectorGroup]
    let size: CGSize
    /// خطوط الأب المفتوح للتو تُرسم بالتدريج في طبقتها
    let skip: UUID?
    let dark: Bool
    /// معامل «حجم النص» — سماكة الخط ونقاط التفرّع تكبر مع العقد
    let k: CGFloat

    var body: some View {
        let lineLayers = TreeArtLines.layers(width: 2, dark: dark, scale: k)
        let lineDark = dark, k = self.k
        let connectors = self.connectors, skip = self.skip
        Canvas { ctx, _ in
            for g in connectors where skip == nil || g.pid != skip {
                TreeArtLines.stroke(&ctx, g.path, lineLayers)
                for d in g.dots {
                    TreeArtLines.dot(&ctx, at: d, r: 3 * k, dark: lineDark)
                }
                if !g.kinPath.isEmpty {
                    ctx.stroke(g.kinPath, with: .color(DS.Color.warning),
                               style: StrokeStyle(lineWidth: 3.5 * k, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// مسار جاهز كشكل — لرسم خطوط الأب المفتوح للتو بالتدريج (`trim`) من الأب نحو الأبناء.
private struct ConnectorPathShape: Shape {
    let path: Path
    func path(in rect: CGRect) -> Path { path }
}

/// قرصة التكبير مع تثبيت النقطة تحت الأصابع (iOS 17+) — نسخة شجرة العائلة.
/// لمسة على عقدة (الصورة أو الاسم) أثناء القرص أو السحب أو بعدهما مباشرة لا تُحسب — كانت إصبع من القرصة
/// تنزل على صورة فتمسكها الصورة لنفسها (فلا تكبير) وتفتح/تطوي فرعاً أو تفتح تفاصيل شخص بالغلط
/// (طلب المالك ٢٠٢٦-١٠-٠٩). للشجرتين (العائلة والنساء). يعدّ الأصابع على النافذة كلها (`TreeTouchWatcher`)
/// لأن قرصة إصبعها على زرّ لا يراها `MagnifyGesture`.
@MainActor
enum TreeTapGuard {
    /// مهلة بعد آخر حركة قرص/سحب أو لمسة بإصبعين تُهمَل فيها اللمسات
    static let window: CFTimeInterval = 0.35
    static let multiTouchWindow: CFTimeInterval = 0.5
    private static var lastGesture: CFTimeInterval = 0
    private static var lastMultiTouch: CFTimeInterval = 0
    private static var pinching = false
    /// حركة سحب/قرص جارية
    static func moved() { lastGesture = CACurrentMediaTime() }
    static func pinch(_ active: Bool) { pinching = active; lastGesture = CACurrentMediaTime() }
    /// إصبعان أو أكثر على الشاشة الآن
    static func multiTouch() { lastMultiTouch = CACurrentMediaTime() }
    /// القرص الملغى لا يصله «انتهى» — فلا يبقى القفل أكثر من ثانية بعد آخر حركة
    static var allowsTap: Bool {
        let now = CACurrentMediaTime()
        return now - lastGesture > (pinching ? 1.0 : window) && now - lastMultiTouch > multiTouchWindow
    }

    /// يركّب عدّاد الأصابع على نوافذ التطبيق (مرة واحدة — من جذر التطبيق)
    static func install() { TreeTouchWatcher.installOnWindows() }
}

/// يراقب عدد الأصابع على النافذة بلا أن يمسك اللمسات أو يؤخّرها (الأزرار والسحب يعملان كالمعتاد)
private final class TreeTouchWatcher: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private static let gestureName = "ds.treeTouchWatcher"
    private static var observing = false

    @MainActor static func installOnWindows() {
        if !observing {
            observing = true
            NotificationCenter.default.addObserver(forName: UIWindow.didBecomeVisibleNotification,
                                                   object: nil, queue: .main) { note in
                MainActor.assumeIsolated { attach(note.object as? UIWindow) }
            }
        }
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach { attach($0) }
        }
    }

    @MainActor private static func attach(_ window: UIWindow?) {
        guard let window else { return }
        let cls = String(describing: type(of: window))
        if cls.contains("Keyboard") || cls.contains("TextEffects") { return }
        if window.gestureRecognizers?.contains(where: { $0.name == gestureName }) == true { return }
        let w = TreeTouchWatcher(target: nil, action: nil)
        w.name = gestureName
        w.cancelsTouchesInView = false
        w.delaysTouchesBegan = false
        w.delaysTouchesEnded = false
        w.delegate = w
        window.addGestureRecognizer(w)
    }

    private func count(_ event: UIEvent) {
        let active = event.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 0
        if active >= 2 { MainActor.assumeIsolated { TreeTapGuard.multiTouch() } }
        // آخر إصبع رُفع: انتهى التسلسل — «فشل» يعيد الضبط ولا يؤثّر على غيره
        if active == 0 { state = .failed }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { count(event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { count(event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { count(event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { count(event) }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

private struct TreePinchZoomModifier: ViewModifier {
    @Binding var scale: CGFloat
    @Binding var baseScale: CGFloat
    @Binding var offset: CGSize
    @Binding var baseOffset: CGSize
    @Binding var userInteracted: Bool
    let clamp: (CGSize) -> CGSize
    /// معامل «حجم النص»: حدود القرص على الشاشة كما كانت (الزوم بوحدات العقدة ÷ المعامل)
    var k: CGFloat = 1

    func body(content: Content) -> some View {
        let lo = TreeConst.minScale / k, hi = TreeConst.maxScale / k
        if #available(iOS 17.0, *) {
            content.simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in
                        userInteracted = true
                        TreeTapGuard.pinch(true)
                        let ns = min(hi, max(lo, baseScale * v.magnification))
                        let f = v.startLocation
                        let r = scale > 0 ? ns / scale : 1
                        offset = CGSize(width: f.x - (f.x - offset.width) * r,
                                        height: f.y - (f.y - offset.height) * r)
                        scale = ns
                    }
                    .onEnded { _ in
                        TreeTapGuard.pinch(false)
                        baseScale = scale
                        let t = clamp(offset)
                        withAnimation(.easeOut(duration: 0.25)) { offset = t }
                        baseOffset = t
                    }
            )
        } else {
            content.simultaneousGesture(
                MagnificationGesture()
                    .onChanged { v in userInteracted = true; TreeTapGuard.pinch(true); scale = min(hi, max(lo, baseScale * v)) }
                    .onEnded { _ in
                        TreeTapGuard.pinch(false)
                        baseScale = scale
                        let t = clamp(offset)
                        withAnimation(.easeOut(duration: 0.25)) { offset = t }
                        baseOffset = t
                    }
            )
        }
    }
}

// MARK: - 1. واجهة الشجرة الرئيسية — Liquid Glass
struct TreeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Binding var selectedTab: Int
    /// تبويب علوي [عائلة/نساء] — يظهر تحت الهيدر عند تمريره.
    var treeTab: Binding<Int>? = nil
    @State private var showingNotifications = false
    @State private var selectedMember: FamilyMember? = nil
    @State private var currentLocationMemberID: UUID? = nil
    /// «موقعي» والحساب غير مربوط بالشجرة (بلا أب أو مخفي أو غير موجود) — رسالة بدل لا شيء
    @State private var showNotInTree = false
    @State private var isRefreshing = false

    @State private var searchedMemberID: UUID? = nil
    @State private var highlightTask: Task<Void, Never>?

    // ── محرّك الكانفس (إحداثيات مطلقة، يطابق تبويب النساء — زوم حقيقي + سحب بزخم) ──
    @State private var scale: CGFloat = TreeConst.defaultScale
    @State private var baseScale: CGFloat = TreeConst.defaultScale
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var viewport: CGSize = .zero
    @State private var layout = FamilyLayout()
    @State private var userInteracted = false
    @State private var fittedScale: CGFloat = TreeConst.defaultScale
    /// إظهار حقل البحث (مخفي افتراضياً خلف زر — العرض الكلاسيكي).
    @State private var showSearch = false

    // أبعاد العقدة الدائرية + فجوات الكانفس: `FamilyTreeMetrics` × معامل «حجم النص» — يُقرأ مرة من البيئة،
    // ويُخزَّن مع التخطيط (`layout.m`) فالعقد والخطوط والكاميرا تقرأ نفس المقاسات
    @Environment(\.dsTreeScale) private var envTreeScale
    /// نسخة المعامل في الحالة — إغلاقات العقد (`.equatable()`) تحمل نسخة قديمة من الواجهة، فتقرأ البيئة القديمة؛
    /// الحالة تُقرأ دائماً بقيمتها الحالية. تُزامَن عند الظهور ومع كل تغيير في «حجم النص».
    @State private var treeScale: CGFloat = 1
    /// أبناء لكل صف قبل الالتفاف — عمودياً ٣، وأفقياً يُحسب تلقائياً من عرض
    /// الشاشة ليتوسّع الإخوة جنب بعض بدل التكديس (طلب المالك)
    private var PER_ROW: Int {
        guard viewport.width > viewport.height, viewport.width > 0 else { return 3 }
        // أفقياً: صف واحد ما دام العدد معقولاً، وإذا كثر فسطران متساويان
        // (طلب المالك) — دالة perRow(for:) تتكفّل بالتقسيم لكل أب على حدة.
        return 99
    }
    /// عدد الأبناء في الصف الواحد لهذا الأب:
    /// عمودي ٣ · أفقي: صف واحد حتى ١٠، وإذا كثروا فسطران متساويان (طلب المالك).
    private func perRow(for count: Int) -> Int {
        guard viewport.width > viewport.height else { return 3 }
        if count <= 10 { return max(1, count) }
        return Int(ceil(Double(count) / 2.0))
    }

    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.colorScheme) var colorScheme
    /// دخول الأدوات حول الشجرة (الشريط، زر التحديث، الحالة الفارغة) مرة مع أول ظهور
    /// للتبويب — من TreeTabContainer، فلا يتكرر عند التبديل «العائلة/النساء».
    /// الرسم والعُقد والإيماءات لا تُمسّ.
    @Environment(\.treeChromeAppeared) private var chromeAppeared
    /// «تقليل الحركة»: شريط المسار وبانر القرابة يظهران بتلاشٍ بلا انزلاق
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activePath: Set<UUID> = []
    @State private var kinshipBanner: String? = nil
    @State private var kinshipHighlightedIds: Set<UUID> = [] // الأعضاء المهايلايتين بصلة القرابة
    /// متى ينتهي وضع صلة القرابة وحده (شريط الإلغاء السفلي يعدّ تنازلياً إليه)
    @State private var kinshipEndsAt: Date? = nil
    @State private var kinshipTimer: Task<Void, Never>? = nil
    /// مكان الشجرة قبل صلة القرابة — «إلغاء» يرجعها له بالضبط (طلب المالك ٢٠٢٦-١٠-٠٩ «لا ترد لوضع البداية»)
    @State private var preKinship: TreeCameraSnapshot? = nil
    /// آخر أب فُتح — خطوطه تُرسم بالتدريج من الأب نحو أبنائه، وأبناؤه يدخلون تباعاً
    /// (طلب المالك ٢٠٢٦-١٠-٠٤: حركات بالشجرة). «تقليل الحركة»: بلا تدريج.
    @State private var drawOnId: UUID? = nil
    @State private var drawProgress: CGFloat = 1
    // MARK: - بيانات مُخزنة مؤقتاً لتجنب إعادة الحساب كل render
    @State private var cachedVisibleMembers: [FamilyMember] = []
    @State private var cachedMemberById: [UUID: FamilyMember] = [:]
    @State private var cachedRootMembers: [FamilyMember] = []
    @State private var cachedChildrenByFatherId: [UUID: [FamilyMember]] = [:]
    @State private var cachedMemberIds: Set<UUID> = []

    private var primaryRootMember: FamilyMember? {
        cachedRootMembers.first
    }

    /// نتيجة بناء الكاش — قابلة للتحويل بين threads (FamilyMember هو struct).
    private struct TreeCache {
        let visible: [FamilyMember]
        let byId: [UUID: FamilyMember]
        let roots: [FamilyMember]
        let childrenMap: [UUID: [FamilyMember]]
        let ids: Set<UUID>
    }

    /// حساب الكاش — pure function، تشتغل على أي thread.
    private nonisolated static func computeCache(from members: [FamilyMember]) -> TreeCache {
        // المعيار القانوني الموحّد لـ"عضو في العائلة" — نفسه في الويب وكل العدّادات
        let visible = members.filter(\.isCountable)
        let byId = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })

        // مجموعة الأعضاء اللي عندهم أبناء (آباء حقيقيين)
        let fatherIds = Set(visible.compactMap(\.fatherId))

        let roots = visible.filter { member in
            guard let fatherId = member.fatherId else {
                // عضو بدون أب: يظهر كجذر فقط إذا عنده أبناء (جد/أب أصلي)
                return fatherIds.contains(member.id)
            }
            return byId[fatherId] == nil
        }.sortedForDisplay()

        let childrenMap = Dictionary(
            grouping: visible.compactMap { m in m.fatherId.map { (m, $0) } },
            by: { $0.1 }
        ).mapValues { pairs in pairs.map(\.0).sortedForDisplay() }

        return TreeCache(
            visible: visible,
            byId: byId,
            roots: roots,
            childrenMap: childrenMap,
            ids: Set(visible.map(\.id))
        )
    }

    /// تطبيق الكاش على @State — يحب يكون على MainActor.
    private func applyCache(_ cache: TreeCache) {
        cachedVisibleMembers = cache.visible
        cachedMemberById = cache.byId
        cachedRootMembers = cache.roots
        cachedChildrenByFatherId = cache.childrenMap
        cachedMemberIds = cache.ids
    }

    /// إعادة بناء سريعة (synchronous) — للتحميل الأول.
    private func rebuildCache() {
        applyCache(Self.computeCache(from: memberVM.allMembers))
    }

    /// إعادة بناء في خلفية — يمنع تجميد الواجهة عند 10K+ عضو.
    private func rebuildCacheBackground() async {
        let snapshot = memberVM.allMembers
        let cache = await Task.detached(priority: .userInitiated) {
            Self.computeCache(from: snapshot)
        }.value
        applyCache(cache)
    }

    // MARK: - بحث (منقول إلى TreeSearchOverlay)
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    DS.Color.background.ignoresSafeArea()

                    if cachedVisibleMembers.isEmpty {
                        emptyStateView
                            // حالة المزامنة/الفراغ تدخل بتلاشٍ وصعود مع أول ظهور
                            .dsCardCascade(1, appeared: chromeAppeared)
                    } else {
                        // حاوية بحجم الشاشة بالضبط + الكانفس كـ overlay لا يؤثر على تخطيطها —
                        // يمنع انزياح الشجرة يساراً عندما يكون الكانفس أعرض من الشاشة
                        // (الحاوية السابقة كانت تتمدد لحجم الكانفس فينحرف التمركز).
                        // الرسم يكمل تحت الشريط السفلي العائم (كان يُقصّ عند حدّه فيظهر خلفه شريط أبيض — طلب
                        // المالك ٢٠٢٦-١٠-٠٩)؛ مقاس التخطيط والتمركز يبقى المساحة الظاهرة فوق الشريط
                        SwiftUI.Color.clear
                            .frame(width: geometry.size.width,
                                   height: geometry.size.height + geometry.safeAreaInsets.bottom)
                            .overlay(alignment: .topLeading) {
                                ZStack(alignment: .topLeading) {
                                    // خطوط الأب وأبنائه — كل الصفوف موصولة (طلب المالك ٢٠٢٦-١٠-٠٤:
                                    // كان الخط يصل الصف الأول فقط). المسارات مبنية مع التخطيط.
                                    // طبقات الخط ونقطة التفرّع بأسلوب «مجسّمات» (أنبوب طين بلمعة)
                                    let k = layout.m.k
                                    let lineLayers = TreeArtLines.layers(width: 2, dark: colorScheme == .dark, scale: k)
                                    let lineDark = colorScheme == .dark
                                    TreeConnectorsLayer(connectors: layout.connectors, size: layout.size,
                                                        skip: drawOnId, dark: lineDark, k: k)
                                        .equatable()
                                    // خطوط آخر أب فُتح: تمتدّ من الأب نحو الأبناء، ثم تظهر نقاط التفرّع
                                    if let id = drawOnId, let g = layout.connectors.first(where: { $0.pid == id }) {
                                        ZStack(alignment: .topLeading) {   // نفس طبقات الخط
                                            ForEach(Array(lineLayers.enumerated()), id: \.offset) { _, l in
                                                ConnectorPathShape(path: l.dy == 0 ? g.path : g.path.offsetBy(dx: 0, dy: l.dy))
                                                    .trim(from: 0, to: drawProgress)
                                                    .stroke(l.color, style: l.style)
                                            }
                                        }
                                            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                                            .allowsHitTesting(false)
                                            .accessibilityHidden(true)
                                        Canvas { ctx, _ in
                                            for d in g.dots {
                                                TreeArtLines.dot(&ctx, at: d, r: 3 * k, dark: lineDark)
                                            }
                                            if !g.kinPath.isEmpty {
                                                ctx.stroke(g.kinPath, with: .color(DS.Color.warning),
                                                           style: StrokeStyle(lineWidth: 3.5 * k, lineCap: .round, lineJoin: .round))
                                            }
                                        }
                                        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                                        .opacity(Double(max(0, (drawProgress - 0.8) / 0.2)))
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                    }
                                    // العُقد — نفس شكل TreeMemberNode الدائري (بلا تغيير)
                                    ForEach(cachedVisibleMembers.filter { layout.positions[$0.id] != nil }, id: \.id) { m in
                                        canvasNode(m)
                                            .transition(nodeEntrance(for: m))
                                    }
                                }
                                .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                                .scaleEffect(scale, anchor: .topLeading)
                                .offset(offset)
                            }
                        // الكانفس مثبّت LTR → اتجاه السحب صحيح في واجهة RTL
                        .environment(\.layoutDirection, .leftToRight)
                        .contentShape(Rectangle())
                        .clipped()
                        .frame(height: geometry.size.height, alignment: .top)
                        .gesture(dragGesture)
                        .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { handleDoubleTap(at: $0.location) })
                        .modifier(TreePinchZoomModifier(scale: $scale, baseScale: $baseScale,
                                                        offset: $offset, baseOffset: $baseOffset,
                                                        userInteracted: $userInteracted, clamp: clampOffset,
                                                        k: layout.m.k))
                        // «حجم النص» تغيّر والتطبيق مفتوح: أعد التخطيط بالمقاسات الجديدة وثبّت الكاميرا على موضعك
                        .onChange(of: envTreeScale) { newScale in
                            treeScale = newScale
                            let L = rebuildLayout()
                            if !userInteracted {
                                fitCanvas(in: viewport, layout: L)
                            } else if let focus = breadcrumbChain.last ?? primaryRootMember {
                                centerOn(focus.id, in: L, verticalAnchor: 0.42)
                            }
                        }
                        .onAppear {
                            viewport = geometry.size
                            treeScale = envTreeScale
                            if activePath.isEmpty, let root = primaryRootMember { activePath = [root.id] }
                            let L = rebuildLayout()
                            if !userInteracted { fitCanvas(in: geometry.size, layout: L) }
                        }
                        .onChange(of: geometry.size) { newSize in
                            // تدوير الشاشة: أعد ضبط موضع الشجرة للاتجاه الجديد (طلب المالك)
                            let orientationFlipped = (viewport.width > viewport.height) != (newSize.width > newSize.height)
                            viewport = newSize
                            if orientationFlipped {
                                // تدوير: أعد بناء التخطيط (عدد الأعمدة يتغيّر) ثم مركّز
                                // العقدة المفتوحة الحالية بمنتصف الشاشة تلقائياً (طلب المالك)
                                withAnimation(DS.Anim.smooth) {
                                    let L = rebuildLayout()
                                    fitCanvas(in: newSize, layout: L)
                                    if let focus = breadcrumbChain.last ?? primaryRootMember {
                                        centerOn(focus.id, in: L, verticalAnchor: 0.5)
                                    }
                                }
                            } else if !userInteracted {
                                fitCanvas(in: newSize, layout: layout)
                            }
                        }
                    }

                    if verticalSizeClass == .compact {
                        // ── الوضع الأفقي: بلا هيدر — شريط المسار بمكانه أعلى الشاشة فقط ──
                        VStack(spacing: DS.Spacing.sm) {
                            if showSearch {
                                TreeSearchOverlay(
                                    onSelect: { member in selectMemberFromSearch(member) },
                                    autoFocus: true,
                                    onClose: { withAnimation(DS.Anim.snappy) { showSearch = false } },
                                    showFiltersWhenEmpty: true
                                )
                            } else if breadcrumbChain.count > 1 {
                                breadcrumbStrip
                                    .padding(.horizontal, DS.Spacing.sm)
                                    .padding(.vertical, DS.Spacing.xxs)
                                    .treeToolbarCard()
                            }
                        }
                        .padding(.horizontal, DS.Spacing.sm)
                        .dsCardCascade(0, appeared: chromeAppeared)
                        .zIndex(101)

                        // البار الجانبي — نفس أدوات البار العلوي عمودياً (طلب المالك)
                        landscapeSideToolbar
                            // يدخل بعد شريط المسار (نفس تتالي البطاقات)
                            .dsCardCascade(1, appeared: chromeAppeared)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .padding(.leading, DS.Spacing.sm)
                            .zIndex(101)
                    } else {
                        VStack(spacing: DS.Spacing.sm) {
                        MainHeaderView(
                            selectedTab: $selectedTab,
                            showingNotifications: $showingNotifications,
                            title: L10n.t("شجرة العائلة", "Family Tree"),
                            subtitle: "\(cachedVisibleMembers.count) " + L10n.t("فرد", "members"),
                            icon: AppSection.tree.symbol,   // الشجرة (رمز التطبيق) لا ورقة
                            section: .tree,
                            subtitleChip: true
                        )

                        // تحت الهيدر: إمّا البحث (مع الفلاتر) أو الشريط الموحّد
                        // (أدوات + شريط المسار مدمجين في بطاقة واحدة مدمّجة).
                        Group {
                            if showSearch {
                                TreeSearchOverlay(
                                    onSelect: { member in selectMemberFromSearch(member) },
                                    autoFocus: true,
                                    onClose: { withAnimation(DS.Anim.snappy) { showSearch = false } },
                                    showFiltersWhenEmpty: true
                                )
                            } else {
                                VStack(spacing: DS.Spacing.xxs) {
                                    classicToolbarRow

                                    // شريط المسار مدمج داخل نفس البطاقة — يظهر عند التعمق فقط
                                    if breadcrumbChain.count > 1 {
                                        DS.Color.mutedBackground
                                            .frame(height: DS.Border.width)
                                            .padding(.horizontal, DS.Spacing.xs)
                                        breadcrumbStrip
                                    }
                                }
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, DSBox.treeToolbarPadV)
                                // بطاقة الأدوات الزجاجية الواحدة (نفسها في شجرة النساء)
                                .treeToolbarCard()
                            }
                        }
                        .padding(.horizontal, DS.Spacing.sm)
                        // الهيدر ثابت (مثل بقية التبويبات)، وبطاقة الأدوات تدخل تحته أولاً —
                        // مرة مع أول ظهور للتبويب. «تقليل الحركة»: تلاشٍ فقط
                        .dsCardCascade(0, appeared: chromeAppeared)
                        }
                        .zIndex(101)
                    }

                    if !cachedVisibleMembers.isEmpty {
                        overlayTools

                        // بانر صلة القرابة
                        if let banner = kinshipBanner {
                            VStack {
                                HStack(spacing: DS.Spacing.sm) {
                                    DSStateIcon("person.2.fill", tint: AppSection.tree.ink, size: DS.Icon.discSmall, mapsChrome: false)
                                    Text(banner)
                                        .dsFont(.headline)
                                    Spacer()
                                    // «×» الصغير بلا قرص (كما كان) — مساحة ضغطه ٤٤ لا تكبّر البانر
                                    DSCloseButton(context: .onColor, size: .mini) { endKinship(resetView: true) }
                                }
                                .foregroundColor(DS.Color.headerTitle)
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.md)
                                // تدرّج الشجرة — «الهادئ الفاتح»: لونها الخفيف بنص داكن (`DSHeaderBackground`)
                                .background(DSHeaderBackground(section: .tree, veil: false))
                                .clipShape(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous))
                                // لمسة الطين الواحدة بظلّها (كان ظلاً يدوياً بلون الشجرة)
                                .modifier(DSClaySkin(radius: DS.Card.radius, onFill: !DS.Theme.isCalm, shadow: true, section: .tree))
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.top, DS.Spacing.sm)
                                // «تقليل الحركة»: تلاشٍ بلا انزلاق
                                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))

                                Spacer()
                            }
                        }
                    }
                }
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .dsAlert(L10n.t("حسابك غير مربوط بالشجرة بعد", "Your account isn't linked to the tree yet"),
                     isPresented: $showNotInTree) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: {
                Text(L10n.t("طلب انضمامك عند الإدارة لربط حسابك بمكانك في الشجرة. بعد الربط يأخذك «موقعي» إلى اسمك مباشرة.",
                            "Your join request is with the admins to link your account to your place in the tree. After that, «Me» takes you straight to your name."))
            }
            // تفاصيل العضو: مربّع بالمنتصف قابل للتوسّع بدل الشيت (طلب المالك)
            .fullScreenCover(item: $selectedMember) { member in
                MemberDetailsView(member: member, centered: true)
                    .background(ClearPresentationBackground())
            }
            .transaction { t in
                // يظهر المربّع في مكانه بلا انزلاق من الأسفل
                // يظهر المربّع في مكانه بلا انزلاق — والإغلاق بلا انزلاق يتم داخل المربّع
                if selectedMember != nil { t.disablesAnimations = true }
            }
            // معامل «حجم النص» قبل أول تخطيط (الـ task بعده)
            .onAppear { treeScale = envTreeScale }
            .task {
                if cachedVisibleMembers.isEmpty {
                    rebuildCache()
                    currentLocationMemberID = authVM.currentUser?.id
                    // أول تحميل — نبدأ من الجذر بالمنتصف (نفس إعادة الوضع)
                    try? await Task.sleep(nanoseconds: TreeConst.shortDelay)
                    resetToTopRoot(animated: false)
                }
            }
            .onDisappear {
                // إلغاء أي highlight tasks عالقة لتفادي memory leaks عند التنقل السريع
                highlightTask?.cancel()
                highlightTask = nil
            }
            // «أنت هنا» دائم — يتبع حساب المستخدم الحالي
            .onChange(of: authVM.currentUser?.id) { newId in
                currentLocationMemberID = newId
            }
            .onChange(of: memberVM.membersVersion) { _ in
                Task {
                    let snapshot = memberVM.allMembers
                    let cache = await Task.detached(priority: .userInitiated) {
                        Self.computeCache(from: snapshot)
                    }.value
                    withAnimation(DS.Anim.snappy) {
                        applyCache(cache)
                        if activePath.isEmpty, let root = cache.roots.first { activePath = [root.id] }
                        let L = rebuildLayout()
                        if !userInteracted { fitCanvas(in: viewport, layout: L) }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .memberDeleted)) { _ in
                // إغلاق شاشة التفاصيل تلقائياً بعد حذف العضو
                withAnimation(DS.Anim.snappy) {
                    selectedMember = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMemberInTree)) { note in
                // مزامنة الشجرة مع الشيت — التحريك فقط دون لمس selectedMember
                // (الشيت يبقى مفتوح ومحتواه يتحدث داخلياً عبر currentMemberId)
                guard let info = note.userInfo,
                      let memberId = info["memberId"] as? UUID,
                      let target = cachedMemberById[memberId] ?? memberVM.member(byId: memberId) else { return }
                selectMemberFromSearch(target)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showKinshipPath)) { note in
                guard let info = note.userInfo,
                      let memberId = info["memberId"] as? UUID,
                      let relationship = info["relationship"] as? String else { return }

                // بناء مسار كامل من الجذر للعضو الممسوح
                var fullPath = Set<UUID>()

                // مسار العضو الممسوح من الجذر
                var memberAncestors: [UUID] = []
                var current = cachedMemberById[memberId]
                while let c = current {
                    fullPath.insert(c.id)
                    memberAncestors.append(c.id)
                    if let fid = c.fatherId { current = cachedMemberById[fid] } else { current = nil }
                }

                // مسار المستخدم الحالي من الجذر
                var myAncestors: [UUID] = []
                if let myId = authVM.currentUser?.id {
                    var myCurrent = cachedMemberById[myId]
                    while let c = myCurrent {
                        fullPath.insert(c.id)
                        myAncestors.append(c.id)
                        if let fid = c.fatherId { myCurrent = cachedMemberById[fid] } else { myCurrent = nil }
                    }
                }

                // حساب الجد المشترك — أقرب أب مشترك بين الاثنين
                let memberSet = Set(memberAncestors)
                let commonAncestor = myAncestors.first { memberSet.contains($0) }

                // إضافة IDs القرابة إذا موجودة
                if let pathIds = info["pathIds"] as? [UUID] {
                    fullPath.formUnion(pathIds)
                }

                // احفظ مكان الشجرة قبل أول صلة قرابة (طلب ثانٍ أثناء الوضع لا يغيّر المكان المحفوظ)
                if preKinship == nil {
                    preKinship = TreeCameraSnapshot(activePath: activePath, scale: scale, baseScale: baseScale,
                                                    offset: offset, baseOffset: baseOffset, fittedScale: fittedScale,
                                                    searchedMemberID: searchedMemberID, userInteracted: userInteracted)
                }

                // فتح كل الفروع بالمسار + هايلايت
                withAnimation(.easeInOut(duration: 0.3)) {
                    activePath = fullPath
                    kinshipHighlightedIds = fullPath
                    searchedMemberID = memberId
                    kinshipBanner = relationship
                }

                // تصغير الزوم لإظهار المسار كامل + التمركز على الجد المشترك (كانفس)
                let scrollToId = commonAncestor ?? memberId
                userInteracted = true
                withAnimation(.easeInOut(duration: 0.4)) {
                    scale = TreeConst.kinshipScale
                    baseScale = TreeConst.kinshipScale
                    fittedScale = TreeConst.kinshipScale
                    let L = rebuildLayout()
                    centerOn(scrollToId, in: L)
                }

                // ينتهي الوضع وحده بعد ٢٠ ثانية (شريط الإلغاء السفلي يعدّ تنازلياً) — طلب جديد يبدأ العدّ من جديد
                kinshipTimer?.cancel()
                kinshipEndsAt = Date().addingTimeInterval(TreeConst.kinshipSeconds)
                kinshipTimer = Task {
                    try? await Task.sleep(nanoseconds: UInt64(TreeConst.kinshipSeconds * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    endKinship(resetView: false)
                }
            }
            // البحث منقول إلى TreeSearchOverlay — لا يعيد رسم الشجرة عند الكتابة
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    func getFullLineage(for member: FamilyMember, lookup: [UUID: FamilyMember]) -> String {
        var name = member.firstName
        var current = member
        var depth = 0
        var visited: Set<UUID> = [member.id]
        while let fatherId = current.fatherId,
              let father = lookup[fatherId],
              !visited.contains(father.id),
              depth < 5 {
            name += " " + father.firstName
            current = father
            visited.insert(father.id)
            depth += 1
        }
        return name
    }

    private func selectMemberFromSearch(_ member: FamilyMember) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        searchedMemberID = member.id
        var ancestors = Set<UUID>()
        var currentParentId = member.fatherId
        var visited = Set<UUID>()
        while let pId = currentParentId {
            if visited.contains(pId) { break }
            visited.insert(pId)
            ancestors.insert(pId)
            currentParentId = cachedMemberById[pId]?.fatherId
        }
        ancestors.insert(member.id)
        activePath = ancestors
        userInteracted = true
        withAnimation(.easeInOut(duration: 0.35)) {
            let L = rebuildLayout()
            centerOn(member.id, in: L)
        }
    }

    private func centerOnMember(_ member: FamilyMember, highlight: Bool = true, includeFocusedMemberInPath: Bool = true) {
        var ancestors = Set<UUID>()
        var currentParentId = member.fatherId
        var visited = Set<UUID>()
        while let pId = currentParentId {
            if visited.contains(pId) { break }
            visited.insert(pId)
            ancestors.insert(pId)
            currentParentId = cachedMemberById[pId]?.fatherId
        }
        if includeFocusedMemberInPath { ancestors.insert(member.id) }
        activePath = ancestors
        searchedMemberID = highlight ? member.id : nil
        userInteracted = true
        withAnimation(.easeInOut(duration: 0.35)) {
            let L = rebuildLayout()
            centerOn(member.id, in: L)
        }

        // إزالة التظليل بعد ٥ ثوانٍ
        if highlight {
            highlightTask?.cancel()
            highlightTask = Task {
                try? await Task.sleep(nanoseconds: TreeConst.highlightDuration)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) { searchedMemberID = nil }
            }
        }
    }

    private func resetToTopRoot(animated: Bool = true) {
        guard let root = primaryRootMember else { return }
        // الجذر فقط مفتوح — الأبناء يظهرون، وأبناؤهم لما يضغط المستخدم
        userInteracted = false
        activePath = [root.id]
        searchedMemberID = nil
        let L = rebuildLayout()
        if animated {
            withAnimation(.easeInOut(duration: 0.4)) { fitCanvas(in: viewport, layout: L) }
        } else {
            fitCanvas(in: viewport, layout: L)
        }
    }

    // MARK: - صف الأدوات تحت الهيدر — مطابق للتفرّع (بحث / البداية / موقعي) أيقونات فقط
    // الأزرار = زرّ الرأس الموحّد على السطح بمقاس الشريط (`DSHeaderButton(.surface, size: .toolbar)` ٣٤،
    // والجانبي `.mini` ٢٧) برمز بحبر الشجرة، والتبويب = `FamilyTreeTabBar` (`DSSegmentedSwitch(.compact)`)،
    // والبطاقة = `.treeToolbarCard()` — نفسها في شجرة النساء (أسلوب واحد، ومقاسات ما قبل التوحيد ٢٠٢٦-١٠-٠٧)

    /// بار جانبي عمودي للوضع الأفقي — نفس أدوات البار العلوي (طلب المالك)
    private var landscapeSideToolbar: some View {
        VStack(spacing: DS.Spacing.xs) {
            searchToolButton(.mini)
            homeToolButton(.mini)
            if let treeTab {
                FamilyTreeSideTabs(selection: treeTab)
            }
            if authVM.currentUser != nil {
                DSHeaderButton(symbol: "location.fill", label: L10n.t("موقعي", "Me"), context: .surface,
                               size: .mini, tint: AppSection.tree.ink) {
                    if let currentUserID = authVM.currentUser?.id,
                       let userMember = cachedMemberById[currentUserID] ?? memberVM.member(byId: currentUserID),
                       cachedMemberById[currentUserID] != nil {
                        currentLocationMemberID = userMember.id
                        centerOnMember(userMember, highlight: true, includeFocusedMemberInPath: false)
                    } else {
                        showNotInTree = true
                    }
                }
            }
        }
        .padding(DS.Spacing.xs)
        .treeToolbarCard()
    }

    private var classicToolbarRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            // الترتيب: بحث → البداية → تبويب [عائلة/نساء] → موقعي
            searchToolButton(.toolbar)
            homeToolButton(.toolbar)

            Spacer(minLength: 0)

            // التبويب [شجرة العائلة / النساء] — بعرض نصّه في الوسط
            if let treeTab {
                FamilyTreeTabBar(selection: treeTab)
            }

            Spacer(minLength: 0)

            // زر موقعي — آخر شي
            if authVM.currentUser != nil {
                DSHeaderButton(symbol: "location.fill", label: L10n.t("موقعي", "Me"), context: .surface,
                               size: .toolbar, tint: AppSection.tree.ink) {
                    if let currentUserID = authVM.currentUser?.id,
                       let userMember = cachedMemberById[currentUserID] ?? memberVM.member(byId: currentUserID) {
                        // التمييز «أنت هنا» دائم — الزر يفتح المسار ويتمركز فقط
                        currentLocationMemberID = userMember.id
                        centerOnMember(userMember, highlight: true, includeFocusedMemberInPath: false)
                    }
                }
            }
        }
    }

    private func searchToolButton(_ size: DSNavButtonSize) -> some View {
        DSHeaderButton(symbol: "magnifyingglass", label: L10n.t("بحث", "Search"), context: .surface,
                       size: size, tint: AppSection.tree.ink) {
            withAnimation(DS.Anim.smooth) { showSearch = true }
        }
    }

    private func homeToolButton(_ size: DSNavButtonSize) -> some View {
        DSHeaderButton(symbol: "house.fill", label: L10n.t("البداية", "Start"), context: .surface,
                       size: size, tint: AppSection.tree.ink) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            resetToTopRoot()
        }
    }

    // MARK: - شريط المسار (فتات النسب) — يوضّح وين أنت وترجع لأي مستوى بضغطة
    /// سلسلة النسب المفتوحة حالياً: الجذر ← ... ← أعمق عقدة مفتوحة.
    private var breadcrumbChain: [FamilyMember] {
        guard let root = primaryRootMember, activePath.contains(root.id) else { return [] }
        var chain = [root]
        var cur = root
        var guardCounter = 0
        while guardCounter < 40 {
            guardCounter += 1
            let kids = cachedChildrenByFatherId[cur.id] ?? []
            guard let next = kids.first(where: { activePath.contains($0.id) && $0.id != cur.id }) else { break }
            chain.append(next)
            cur = next
        }
        return chain
    }

    /// الرجوع لمستوى معيّن: يطوي كل ما تحته ويتمركز عليه.
    private func jumpToBreadcrumb(_ member: FamilyMember) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var rm = Set<UUID>()
        collectDescendants(of: member.id, into: &rm)
        activePath.subtract(rm)
        activePath.insert(member.id)
        searchedMemberID = nil
        userInteracted = true
        withAnimation(.easeInOut(duration: 0.3)) {
            let L = rebuildLayout()
            centerOn(member.id, in: L)
        }
    }

    /// شريط المسار المدمّج — نسخة أصغر مدمجة داخل بطاقة الأدوات (يظهر عند التعمق فقط).
    private var breadcrumbStrip: some View {
        // يتحرّك مع المسار (طلب المالك): آخر اسم يبقى ظاهراً عند التعمّق وعند «موقعي»
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xxs) {
                    ForEach(Array(breadcrumbChain.enumerated()), id: \.element.id) { idx, m in
                        let isLast = idx == breadcrumbChain.count - 1
                        HStack(spacing: DS.Spacing.xxs) {
                            // شريحة العُدّة الواحدة (`DSChipButton`) — الأخيرة (موقعك الآن) ممتلئة؛ المصغّرة داخل
                            // بطاقة الأدوات (كما كانت)، والصغيرة في بطاقتها المستقلة أفقياً
                            DSChipButton(m.firstName.isEmpty ? "—" : m.firstName,
                                         icon: idx == 0 ? "house.fill" : nil,
                                         isSelected: isLast,
                                         size: verticalSizeClass == .compact ? .small : .mini) {
                                jumpToBreadcrumb(m)
                            }
                            .accessibilityLabel(L10n.t("الرجوع إلى \(m.firstName)", "Back to \(m.firstName)"))

                            if !isLast {
                                DSChevron(size: DS.Glyph.xs)
                            }
                        }
                        .id(m.id)
                    }
                }
                .padding(.horizontal, DS.Spacing.xxs)
                .padding(.vertical, DS.Border.width)
            }
            // يُعاد التمرير كلما تغيّر آخر اسم (وعند الظهور) بعد رسم العناصر —
            // مع مسار طويل (أكثر من ٧) كان التمرير يسبق الرسم فلا يصل للنهاية
            .task(id: breadcrumbChain.last?.id) {
                try? await Task.sleep(nanoseconds: 80_000_000)
                scrollBreadcrumbToEnd(proxy, animated: true)
                try? await Task.sleep(nanoseconds: 250_000_000)
                scrollBreadcrumbToEnd(proxy, animated: true)
            }
        }
        // «تقليل الحركة»: تلاشٍ بلا انزلاق
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }

    /// يمرّر شريط المسار حتى يظهر آخر اسم (الموقع الحالي)
    private func scrollBreadcrumbToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = breadcrumbChain.last?.id else { return }
        if animated {
            withAnimation(DS.Anim.snappy) { proxy.scrollTo(last, anchor: .trailing) }
        } else {
            proxy.scrollTo(last, anchor: .trailing)
        }
    }

    // MARK: - أداة التحديث — Glassy
    private var overlayTools: some View {
        VStack {
            Spacer()
            if let endsAt = kinshipEndsAt, kinshipBanner != nil {
                // وضع صلة القرابة: شريط سفلي بزرّ الإلغاء وعدّ تنازلي ٢٠ ثانية (طلب المالك ٢٠٢٦-١٠-٠٩)
                KinshipExitBar(endsAt: endsAt, duration: TreeConst.kinshipSeconds) { endKinship(resetView: true) }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xl)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            } else {
            HStack {
                Spacer()
                // زرّ الرأس الموحّد على السطح (دائرة زجاجية رمادية) — أثناء التحديث دوّارة صغيرة داخله
                Button(action: {
                    guard !isRefreshing else { return }
                    isRefreshing = true
                    Task {
                        await memberVM.fetchAllMembers(force: true)
                        guard !Task.isCancelled else { return }
                        await rebuildCacheBackground()
                        resetToTopRoot()
                        withAnimation { isRefreshing = false }
                    }
                }) {
                    DSNavButtonLabel(symbol: isRefreshing ? "" : "arrow.counterclockwise", context: .surface)
                        .overlay {
                            if isRefreshing {
                                ProgressView().tint(DS.Color.textPrimary)
                            }
                        }
                }
                // ضغطة ناعمة موحّدة (كان بلا إحساس بالضغط)
                .buttonStyle(DSPressStyle())
                .disabled(isRefreshing)
                .accessibilityLabel(L10n.t("تحديث الشجرة", "Refresh tree"))
                .dsSubtleShadow()
                // الزر العائم يقفز آخراً بعد بطاقة الأدوات (مثل أزرار «+» العائمة)
                .modifier(TreeToolPop(shown: chromeAppeared))
                .padding(.bottom, DS.Spacing.xl)
            }
            .padding(.horizontal, DS.Spacing.lg)
            }
        }
        .animation(DS.Anim.snappy, value: kinshipEndsAt)
    }

    /// إنهاء وضع صلة القرابة — الزرّ (والـ«×») يرجع الشجرة لمكانها قبل صلة القرابة بالضبط (الفروع المفتوحة
    /// والتكبير والموضع)؛ انتهاء المدة يطفئ التمييز ويترك المكان كما هو
    private func endKinship(resetView: Bool) {
        kinshipTimer?.cancel()
        kinshipTimer = nil
        let snap = preKinship
        preKinship = nil
        withAnimation(DS.Anim.snappy) {
            kinshipBanner = nil
            kinshipHighlightedIds = []
            kinshipEndsAt = nil
            if resetView, let snap {
                activePath = snap.activePath
                searchedMemberID = snap.searchedMemberID
                userInteracted = snap.userInteracted
                rebuildLayout()
                scale = snap.scale; baseScale = snap.baseScale; fittedScale = snap.fittedScale
                offset = snap.offset; baseOffset = snap.baseOffset
            } else if resetView {
                searchedMemberID = nil
                userInteracted = false
                if let root = primaryRootMember { activePath = [root.id] }
                let L = rebuildLayout()
                fitCanvas(in: viewport, layout: L)
            } else {
                rebuildLayout()
            }
        }
    }

    // MARK: - محرّك الكانفس (إحداثيات مطلقة) — يصلّح الزوم المعطوب ويضيف خطوط ربط حقيقية

    /// نقر مزدوج: تكبير نحو نقطة اللمس، أو رجوع لملاءمة الشاشة إذا كان مكبّراً.
    private func handleDoubleTap(at location: CGPoint) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        userInteracted = true
        let zoomedIn = scale > fittedScale + 0.05
        // سقف التكبير على الشاشة كما كان (الزوم بوحدات العقدة ÷ معامل «حجم النص»)
        let ns: CGFloat = zoomedIn ? fittedScale : min(TreeConst.maxScale / layout.m.k, max(fittedScale * 2, 0.95))
        let r = scale > 0 ? ns / scale : 1
        withAnimation(.easeInOut(duration: 0.3)) {
            if zoomedIn {
                scale = ns; baseScale = ns
                offset = centeredOffset(scale: ns, in: viewport, layout: layout)
                baseOffset = offset
            } else {
                offset = clampOffset(CGSize(width: location.x - (location.x - offset.width) * r,
                                            height: location.y - (location.y - offset.height) * r))
                scale = ns; baseScale = ns; baseOffset = offset
            }
        }
    }

    /// إعادة حساب التخطيط من activePath الحالي وتخزينه.
    @discardableResult
    private func rebuildLayout() -> FamilyLayout {
        let L = computeLayout()
        layout = L
        return L
    }

    /// يحسب مواضع كل العقد المرئية بإحداثيات مطلقة (أبوي، صفوف بحدّ PER_ROW، بلا فصل جنسين).
    private func computeLayout() -> FamilyLayout {
        // المقاسات بمعامل «حجم النص» — مرة لكل تخطيط
        let M = FamilyTreeMetrics(k: treeScale)
        var L = FamilyLayout()
        L.m = M
        guard let root = primaryRootMember else { return L }
        let NODE_W = M.nodeW, H_GAP = M.hGap, V_GAP = M.vGap, ROW_GAP = M.rowGap
        let SPINE_ROOM = M.spineRoom, CANVAS_PAD = M.canvasPad
        let cOf = cachedChildrenByFatherId
        let byId = cachedMemberById
        var sizeCache: [UUID: CGSize] = [:]
        var seen = Set<UUID>()

        func boxH(_ id: UUID) -> CGFloat {
            M.boxHeight(deceased: byId[id]?.isDeceased == true)
        }
        // الأبناء الظاهرون: العقدة يجب أن تكون في activePath، ثم نركّز على الفرع المفتوح (مثل السلوك السابق).
        func visKids(_ id: UUID) -> [FamilyMember] {
            guard activePath.contains(id) else { return [] }
            let all = (cOf[id] ?? []).filter { $0.id != id }
            if !kinshipHighlightedIds.isEmpty { return all.filter { kinshipHighlightedIds.contains($0.id) } }
            let focused = all.filter { activePath.contains($0.id) }
            return focused.isEmpty ? all : focused
        }
        func blockDims(_ boxes: [CGSize]) -> CGSize {
            var w: CGFloat = 0, h: CGFloat = 0, i = 0
            while i < boxes.count {
                let row = Array(boxes[i..<min(i + perRow(for: boxes.count), boxes.count)])
                let rowW = row.reduce(0) { $0 + $1.width } + H_GAP * CGFloat(row.count - 1)
                let rowH = row.map(\.height).max() ?? 0
                w = max(w, rowW); h += (i > 0 ? ROW_GAP : 0) + rowH
                i += perRow(for: boxes.count)
            }
            // صفوف ملتفّة: مساحة العمود على الجانبين (بالتساوي فيبقى التمركز كما هو)
            if boxes.count > perRow(for: boxes.count) { w += SPINE_ROOM * 2 }
            return CGSize(width: w, height: h)
        }
        func measure(_ id: UUID) -> CGSize {
            let bh = boxH(id); L.heights[id] = bh
            if seen.contains(id) { return CGSize(width: NODE_W, height: bh) }
            seen.insert(id)
            let kids = visKids(id)
            if kids.isEmpty { let b = CGSize(width: NODE_W, height: bh); sizeCache[id] = b; return b }
            let childBlock = blockDims(kids.map { measure($0.id) })
            let b = CGSize(width: max(NODE_W, childBlock.width), height: bh + V_GAP + childBlock.height)
            sizeCache[id] = b; return b
        }
        var placed = Set<UUID>()
        func place(_ id: UUID, _ cx: CGFloat, _ top: CGFloat, _ d: Int) {
            if placed.contains(id) { return }
            placed.insert(id)
            L.positions[id] = CGPoint(x: cx - NODE_W / 2, y: top)
            L.depth[id] = d
            L.heights[id] = boxH(id)
            let kids = visKids(id)
            if kids.isEmpty { return }
            var rows: [[UUID]] = []
            var rowTop = top + boxH(id) + V_GAP
            let per = perRow(for: kids.count)
            var i = 0
            while i < kids.count {
                let rowKids = Array(kids[i..<min(i + per, kids.count)])
                let rowBoxes = rowKids.map { sizeCache[$0.id] ?? CGSize(width: NODE_W, height: boxH($0.id)) }
                let rowW = rowBoxes.reduce(0) { $0 + $1.width } + H_GAP * CGFloat(rowBoxes.count - 1)
                let rowH = rowBoxes.map(\.height).max() ?? 0
                var x = cx - rowW / 2
                for (j, k) in rowKids.enumerated() {
                    place(k.id, x + rowBoxes[j].width / 2, rowTop, d + 1)
                    x += rowBoxes[j].width + H_GAP
                }
                rows.append(rowKids.map { $0.id })
                rowTop += rowH + ROW_GAP
                i += per
            }
            L.childRows[id] = rows
        }

        let rootBox = measure(root.id)
        place(root.id, CANVAS_PAD + rootBox.width / 2, CANVAS_PAD, 0)
        let width = rootBox.width + CANVAS_PAD * 2
        let height = rootBox.height + CANVAS_PAD * 2
        // مرآة أفقية → ترتيب الإخوة يمين‑لليسار (RTL) مثل تبويب النساء
        for (id, p) in L.positions { L.positions[id] = CGPoint(x: width - p.x - NODE_W, y: p.y) }
        L.size = CGSize(width: width, height: height)
        L.connectors = buildConnectors(L)
        return L
    }

    /// خطوط كل أب مع أبنائه — تُبنى مرة مع التخطيط بعد المرآة (الأكبر يميناً)، لا كل إطار.
    /// اختيار المالك ٢٠٢٦-١٠-٠٤ (كان الخط يصل الصف الأول وحده):
    ///  • صف واحد بثلاثة أبناء أو أقل: الأقواس القديمة من أسفل الأب إلى كل ابن.
    ///  • صف واحد أطول (أفقياً): خط أفقي في منتصف الفجوة ونزول لكل ابن.
    ///  • صفوف ملتفّة — «العمود»: خط أفقي فوق كل صف، وعمود على جهة الأكبر يصل الصفوف بخط الأب.
    private func buildConnectors(_ L: FamilyLayout) -> [ConnectorGroup] {
        typealias Kid = (id: UUID, x: CGFloat, top: CGFloat)
        // نفس مقاسات التخطيط (× معامل «حجم النص»)
        let M = L.m, k = M.k
        let NODE_W = M.nodeW, ROW_GAP = M.rowGap, SPINE_OUT = M.spineOut
        let r = M.lineCorner
        var groups: [ConnectorGroup] = []
        for (pid, ids) in L.childRows {
            guard let pp = L.positions[pid] else { continue }
            let fx = pp.x + NODE_W / 2
            let fy = pp.y + (L.heights[pid] ?? M.nodeHDefault) - 2 * k
            // كل صف: مركز كل ابن وأعلى دائرته، يساراً→يميناً
            let rows: [[Kid]] = ids.map { row in
                row.compactMap { id in L.positions[id].map { (id: id, x: $0.x + NODE_W / 2, top: $0.y + 4 * k) } }
                    .sorted { $0.x < $1.x }
            }.filter { !$0.isEmpty }
            guard let first = rows.first else { continue }
            let kinFather = kinshipHighlightedIds.contains(pid)
            func isKin(_ id: UUID) -> Bool { kinFather && kinshipHighlightedIds.contains(id) }
            // خط كل صف: الأول في منتصف الفجوة بين الأب والصف، والتالية في منتصف الفجوة فوق صفّها
            let bus: [CGFloat] = rows.enumerated().map { i, row in
                let rowTop = (row.map(\.top).min() ?? fy) - 4 * k
                return i == 0 ? (fy + rowTop) / 2 : rowTop - ROW_GAP / 2
            }
            let last = rows.count - 1
            var g = ConnectorGroup()
            g.pid = pid
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
            /// نزول ابن من خطّ صفّه + نقطة التفرّع
            func drop(_ k: Kid, _ y: CGFloat) {
                g.path.move(to: p(k.x, y)); g.path.addLine(to: p(k.x, k.top)); g.dots.append(p(k.x, y))
            }
            /// آخر الطريق: على خط الصف إلى الابن ثم نزول مدوّر إليه
            func land(_ path: inout Path, _ k: Kid, _ y: CGFloat) {
                path.addArc(tangent1End: p(k.x, y), tangent2End: p(k.x, k.top), radius: r)
                path.addLine(to: p(k.x, k.top))
            }

            // صف واحد بثلاثة أبناء أو أقل: الأقواس القديمة (نقاط تحكم بعيدة ٨٠٪ — قوس واضح)
            if rows.count == 1, first.count <= 3 {
                for k in first {
                    var c = Path()
                    let dy = k.top - fy
                    c.move(to: p(fx, fy))
                    c.addCurve(to: p(k.x, k.top), control1: p(fx, fy + dy * 0.8), control2: p(k.x, k.top - dy * 0.8))
                    g.path.addPath(c)
                    if isKin(k.id) { g.kinPath.addPath(c) }
                }
                groups.append(g); continue
            }
            // نزول الأب إلى خط الصف الأول
            g.path.move(to: p(fx, fy)); g.path.addLine(to: p(fx, bus[0]))

            if rows.count == 1 {
                // صف واحد أطول (أفقياً): خط أفقي بطرفين مدوّرين ينزلان لطرفي الصف، والوسط نزول مستقيم
                let a = first.first!, b = first.last!
                g.path.move(to: p(a.x, a.top))
                g.path.addArc(tangent1End: p(a.x, bus[0]), tangent2End: p(b.x, bus[0]), radius: r)
                land(&g.path, b, bus[0])
                for k in first.dropFirst().dropLast() { drop(k, bus[0]) }
                for k in first where isKin(k.id) {
                    g.kinPath.move(to: p(fx, fy))
                    if abs(k.x - fx) < 1 { g.kinPath.addLine(to: p(k.x, k.top)) }
                    else { g.kinPath.addLine(to: p(fx, bus[0] - r)); g.kinPath.addArc(tangent1End: p(fx, bus[0]), tangent2End: p(k.x, bus[0]), radius: r); land(&g.kinPath, k, bus[0]) }
                }
                groups.append(g); continue
            }

            // صفوف ملتفّة — «العمود» على جهة الأكبر (أول ابن في ترتيب التخطيط)
            let eldestX = ids.first?.first.flatMap { L.positions[$0] }.map { $0.x + NODE_W / 2 } ?? fx
            let eldestRight = eldestX >= fx
            let allX = rows.flatMap { $0.map(\.x) }
            let sx = eldestRight ? (allX.max() ?? fx) + NODE_W / 2 + SPINE_OUT
                                 : (allX.min() ?? fx) - NODE_W / 2 - SPINE_OUT
            // الابن الأبعد عن العمود في كل صف: إليه ينتهي خط الصف بانعطافة
            func far(_ row: [Kid]) -> Kid { eldestRight ? row.first! : row.last! }
            // الصف الأول ← العمود ← الصف الأخير
            let f0 = far(first), fl = far(rows[last])
            g.path.move(to: p(f0.x, f0.top))
            g.path.addArc(tangent1End: p(f0.x, bus[0]), tangent2End: p(sx, bus[0]), radius: r)
            g.path.addArc(tangent1End: p(sx, bus[0]), tangent2End: p(sx, bus[last]), radius: r)
            g.path.addArc(tangent1End: p(sx, bus[last]), tangent2End: p(fl.x, bus[last]), radius: r)
            land(&g.path, fl, bus[last])
            // الصفوف الوسطى: تفرّع من العمود
            if last > 1 {
                for i in 1..<last {
                    let fi = far(rows[i])
                    g.path.move(to: p(sx, bus[i]))
                    land(&g.path, fi, bus[i])
                }
            }
            for (i, row) in rows.enumerated() {
                let fi = far(row)
                for k in row where k.id != fi.id { drop(k, bus[i]) }
            }
            // طريق القرابة: الأب ← (العمود) ← خط الصف ← الابن
            for (i, row) in rows.enumerated() {
                for k in row where isKin(k.id) {
                    g.kinPath.move(to: p(fx, fy))
                    if i == 0 {
                        if abs(k.x - fx) < 1 { g.kinPath.addLine(to: p(k.x, k.top)); continue }
                        g.kinPath.addLine(to: p(fx, bus[0] - r))
                        g.kinPath.addArc(tangent1End: p(fx, bus[0]), tangent2End: p(k.x, bus[0]), radius: r)
                    } else {
                        g.kinPath.addLine(to: p(fx, bus[0] - r))
                        g.kinPath.addArc(tangent1End: p(fx, bus[0]), tangent2End: p(sx, bus[0]), radius: r)
                        g.kinPath.addArc(tangent1End: p(sx, bus[0]), tangent2End: p(sx, bus[i]), radius: r)
                        g.kinPath.addArc(tangent1End: p(sx, bus[i]), tangent2End: p(k.x, bus[i]), radius: r)
                    }
                    land(&g.kinPath, k, bus[i])
                }
            }

            groups.append(g)
        }
        return groups
    }

    /// دخول أبناء الأب المفتوح للتو: يكبرون من موضعهم تباعاً بعد امتداد الخط إليهم.
    private func nodeEntrance(for m: FamilyMember) -> AnyTransition {
        guard !reduceMotion, let fid = m.fatherId, fid == drawOnId,
              let idx = layout.childRows[fid]?.flatMap({ $0 }).firstIndex(of: m.id),
              let p = layout.positions[m.id], layout.size.width > 0, layout.size.height > 0
        else { return .opacity }
        let anchor = UnitPoint(x: (p.x + layout.m.nodeW / 2) / layout.size.width, y: p.y / layout.size.height)
        return .asymmetric(
            insertion: AnyTransition.scale(scale: 0.5, anchor: anchor)
                .combined(with: .opacity)
                .animation(.spring(response: 0.45, dampingFraction: 0.72).delay(0.3 + Double(idx) * 0.07)),
            removal: .opacity)
    }

    /// عقدة واحدة بشكل TreeMemberNode الدائري، موضوعة بإحداثيات مطلقة.
    @ViewBuilder
    private func canvasNode(_ m: FamilyMember) -> some View {
        let M = layout.m
        let p = layout.positions[m.id] ?? .zero
        let h = layout.heights[m.id] ?? M.nodeHDefault
        TreeMemberNode(
            member: m,
            isExpanded: activePath.contains(m.id),
            searchedMemberID: $searchedMemberID,
            hasChildren: !((cachedChildrenByFatherId[m.id] ?? []).isEmpty),
            childrenCount: (cachedChildrenByFatherId[m.id] ?? []).count,
            showName: true,
            level: layout.depth[m.id] ?? 0,
            currentLocationMemberID: currentLocationMemberID,
            isKinshipHighlighted: kinshipHighlightedIds.contains(m.id),
            searchedSnapshot: searchedMemberID,
            // العقدة كلها × معامل «حجم النص» (نفس معامل التخطيط) — نصوصها بحجم ثابت فلا تكبر مرتين
            k: M.k,
            onTap: { selectedMember = m },
            onToggle: { toggleNode(m) }
        )
        // العقدة لا يُعاد بناؤها مع كل إطار سحب/تكبير ما لم تتغيّر بياناتها (فحص «اللاق»)
        .equatable()
        .frame(width: M.nodeW, height: h, alignment: .top)
        .position(x: p.x + M.nodeW / 2, y: p.y + h / 2)
    }

    /// فتح/طيّ عقدة (نفس منطق التفرّع السابق) ثم تحريك الكاميرا.
    private func toggleNode(_ member: FamilyMember) {
        let kids = cachedChildrenByFatherId[member.id] ?? []
        guard !kids.isEmpty else { return }
        let wasExpanded = activePath.contains(member.id)
        let hasDeeper = kids.contains { activePath.contains($0.id) }
        if !wasExpanded {
            activePath.insert(member.id)
        } else if hasDeeper {
            var rm = Set<UUID>(); collectDescendants(of: member.id, into: &rm)
            activePath.subtract(rm); searchedMemberID = nil
        } else {
            var rm: Set<UUID> = [member.id]; collectDescendants(of: member.id, into: &rm)
            activePath.subtract(rm); searchedMemberID = nil
        }
        userInteracted = true
        let opening = !wasExpanded || hasDeeper
        let drawOn = !wasExpanded && !reduceMotion
        if drawOn { drawOnId = member.id; drawProgress = 0 }
        defer {
            if drawOn { withAnimation(.easeInOut(duration: 0.7).delay(0.15)) { drawProgress = 1 } }
        }
        withAnimation(DS.Anim.smooth) {
            let L = rebuildLayout()
            // التمركز على العقدة بعد كل توسيع/طي — الشجرة تبقى بالمنتصف دائماً.
            // عند الفتح يرتفع الأب حسب عدد صفوف أبنائه: صف واحد 42%،
            // صفّان 34%، ثلاثة صفوف وأكثر (٧+ أبناء) 26% — ليظهر الصف الأخير.
            if opening {
                let per = perRow(for: kids.count)
                let rowCount = (kids.count + per - 1) / per
                adaptiveCenter(on: member.id, rowCount: rowCount, in: L)
            } else {
                // عند الطي: تمركز على الأب بنفس المنطق التكيّفي حسب صفوف أبنائه —
                // الشجرة تنزل ويظهر جميع الإخوة (طلب المالك)
                let pid = member.fatherId ?? member.id
                let sibs = cachedChildrenByFatherId[pid] ?? []
                let per2 = perRow(for: sibs.count)
                let rowCount = max(1, (sibs.count + per2 - 1) / per2)
                adaptiveCenter(on: pid, rowCount: rowCount, in: L)
            }
        }
    }

    private func collectDescendants(of parentId: UUID, into set: inout Set<UUID>) {
        for child in cachedChildrenByFatherId[parentId] ?? [] where child.id != parentId {
            if set.insert(child.id).inserted {
                collectDescendants(of: child.id, into: &set)
            }
        }
    }

    /// تمركز تكيّفي بعد التوسيع/الطي — يراعي اتجاه الشاشة:
    /// عمودي: نفس النقاط المعتادة · أفقي: زوم أبعد + نقاط أعلى ليظهر الأب وكل صفوف
    /// الأبناء داخل الارتفاع القصير (طلب المالك)
    private func adaptiveCenter(on id: UUID, rowCount: Int, in L: FamilyLayout) {
        if viewport.width > viewport.height {
            let s: CGFloat = rowCount >= 3 ? 0.45 : (rowCount == 2 ? 0.55 : 0.7)
            scale = s; baseScale = s
            let anchor: CGFloat = rowCount >= 3 ? 0.18 : (rowCount == 2 ? 0.24 : 0.32)
            centerOn(id, in: L, verticalAnchor: anchor)
        } else {
            let anchor: CGFloat = rowCount >= 3 ? 0.26 : (rowCount == 2 ? 0.34 : 0.42)
            centerOn(id, in: L, verticalAnchor: anchor)
        }
    }

    // ─── الكاميرا (offset) ───

    /// يُمركز عقدة في الشاشة — أفقياً بالمنتصف دائماً، وعمودياً عند `verticalAnchor`
    /// (0.5 = منتصف تماماً، 0.42 = أعلى قليلاً لتظهر الأبناء تحتها بعد التوسيع).
    private func centerOn(_ id: UUID, in L: FamilyLayout, verticalAnchor: CGFloat = 0.5) {
        guard let p = L.positions[id], viewport.width > 0 else { return }
        userInteracted = true
        let s = scale
        let h = L.heights[id] ?? L.m.nodeHDefault
        let cx = (p.x + L.m.nodeW / 2) * s
        // أعلى العقدة حيث يكون بالمقاس الافتراضي، والزيادة مع «حجم النص» تمتدّ للأسفل — لا تختفي تحت شريط الأدوات
        let cy = (p.y + h / (2 * L.m.k)) * s
        offset = clampOffset(CGSize(width: viewport.width / 2 - cx, height: viewport.height * verticalAnchor - cy))
        baseOffset = offset
    }

    /// يلائم الشجرة للشاشة ويوسّطها أفقياً وعمودياً (بمنتصف المساحة تحت الهيدر).
    private func fitCanvas(in size: CGSize, layout L: FamilyLayout) {
        guard L.size.width > 0, size.width > 0 else { return }
        // الوضع الأفقي: سقف زوم أصغر — الارتفاع قصير فلازم يبان الجذر وأبناؤه
        // بأسمائهم كاملة فوق البار السفلي
        let maxS: CGFloat = size.width > size.height ? 0.65 : 1.1
        // الملاءمة بوحدات العقدة الافتراضية (العرض ÷ معامل «حجم النص»): مع الخط الأكبر تظهر الشجرة أكبر
        // وتمتدّ خارج الشاشة للسحب (اختيار المالك ٢٠٢٦-١٠-٠٨) — بدل أن تصغّرها الملاءمة فيضيع التكبير
        let s = max(0.28, min(maxS, (size.width - 48) / (L.size.width / L.m.k)))
        scale = s; baseScale = s; fittedScale = s
        offset = centeredOffset(scale: s, in: size, layout: L)
        baseOffset = offset
    }

    /// إزاحة التوسيط: الكانفس بالمنتصف أفقياً، والجذر بمنتصف الشاشة عمودياً
    /// (نفس سلوك المحرّك السابق — scrollTo(root, anchor: .center)).
    private func centeredOffset(scale s: CGFloat, in size: CGSize, layout L: FamilyLayout) -> CGSize {
        // أعلى الجذر حيث يكون بالمقاس الافتراضي — العقدة الأكبر مع «حجم النص» تمتدّ للأسفل لا تحت الشريط
        var rootCY: CGFloat = L.m.canvasPad + L.m.nodeHDefault / (2 * L.m.k)
        if let root = primaryRootMember, let p = L.positions[root.id] {
            rootCY = p.y + (L.heights[root.id] ?? L.m.nodeHDefault) / (2 * L.m.k)
        }
        // عمودي: 0.37 (رفع الجذر — طلب المالك) · أفقي: 0.30 ليتّسع الجيل الأول بأسمائه
        let rootAnchor: CGFloat = size.width > size.height ? 0.30 : 0.37
        let y = size.height * rootAnchor - rootCY * s
        return CGSize(width: (size.width - L.size.width * s) / 2, height: y)
    }

    /// يُبقي الشجرة داخل حدود معقولة مع هامش overscroll.
    private func clampOffset(_ o: CGSize) -> CGSize {
        guard viewport.width > 0, viewport.height > 0 else { return o }
        let overscroll: CGFloat = 120
        let contentW = layout.size.width * scale
        let contentH = layout.size.height * scale
        func clampAxis(_ v: CGFloat, content: CGFloat, view: CGFloat, topHi: CGFloat) -> CGFloat {
            if content <= view {
                let slack = view - content
                return min(max(v, -overscroll), slack + overscroll)
            }
            let lo = view - content - overscroll
            return min(max(v, lo), topHi)
        }
        return CGSize(
            width: clampAxis(o.width, content: contentW, view: viewport.width, topHi: overscroll),
            height: clampAxis(o.height, content: contentH, view: viewport.height, topHi: viewport.height * 0.5)
        )
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                userInteracted = true
                TreeTapGuard.moved()
                offset = clampOffset(CGSize(width: baseOffset.width + v.translation.width,
                                            height: baseOffset.height + v.translation.height))
            }
            .onEnded { v in
                TreeTapGuard.moved()
                // زخم مثل ScrollView: يكمل حسب السرعة ثم يستقر داخل الحدود.
                let projected = CGSize(width: baseOffset.width + v.predictedEndTranslation.width,
                                       height: baseOffset.height + v.predictedEndTranslation.height)
                let target = clampOffset(projected)
                withAnimation(.easeOut(duration: 0.4)) { offset = target }
                baseOffset = target
            }
    }

    // MARK: - حالة فارغة
    @ViewBuilder
    private var emptyStateView: some View {
        // الحالات الثلاث بالعُدّة الواحدة (أسلوب واحد ٢٠٢٦-١٠-٠٧): مجسّم قسم الشجرة (الغافة) + عنوان + سطر،
        // والتحميل نفس المجسّم يتنفّس — مثل باقي الأقسام وشجرة النساء
        if memberVM.membersLoadFailed {
            DSEmptyView(L10n.t("تعذّر تحميل البيانات", "Couldn't load data"),
                        message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                        section: .tree, icon: "exclamationmark.triangle.fill", tint: DS.Color.error,
                        actionTitle: L10n.t("إعادة المحاولة", "Retry"), actionIcon: "arrow.clockwise") {
                memberVM.membersLoadFailed = false
                Task {
                    await memberVM.fetchAllMembers(force: true)
                    guard !Task.isCancelled else { return }
                    await rebuildCacheBackground()
                    resetToTopRoot()
                }
            }
        } else if memberVM.membersVersion > 0 && !memberVM.isLoading {
            // التحميل تم فعلاً لكن لا يوجد أعضاء — رسالة مختلفة عن "جاري المزامنة"
            DSEmptyView(L10n.t("لا يوجد أفراد في الشجرة بعد", "No family members yet"),
                        message: L10n.t("اسحب للتحديث أو تواصل مع الإدارة", "Pull to refresh or contact the admin"),
                        section: .tree,
                        actionTitle: L10n.t("تحديث", "Refresh"), actionIcon: "arrow.clockwise") {
                Task {
                    await memberVM.fetchAllMembers(force: true)
                    guard !Task.isCancelled else { return }
                    await rebuildCacheBackground()
                    resetToTopRoot()
                }
            }
        } else {
            DSPageLoader(L10n.t("جاري مزامنة الشجرة...", "Syncing tree..."), section: .tree)
        }
    }

}

/// زر الشجرة العائم يقفز آخراً — نفس قفزة DSIconPop (تكبير بنابض من ٠٫٥٥) وتأخير أزرار «+»
/// العائمة، لكن يقوده علم ظهور التبويب فلا يتكرر مع التبديل «العائلة/النساء».
/// «تقليل الحركة»: تلاشٍ فقط.
/// مكان الشجرة (الفروع المفتوحة + التكبير + الموضع) — يُحفظ قبل صلة القرابة ويُرجَع له عند «إلغاء»
private struct TreeCameraSnapshot {
    let activePath: Set<UUID>
    let scale: CGFloat
    let baseScale: CGFloat
    let offset: CGSize
    let baseOffset: CGSize
    let fittedScale: CGFloat
    let searchedMemberID: UUID?
    let userInteracted: Bool
}

/// شريط صلة القرابة السفلي — كبسولة صغيرة بلون صلة القرابة (`DS.Color.warning`، لون تمييز المسار وشريحة
/// «صلة القرابة»): حلقة تعدّ تنازلياً (تفرغ خلال المدة والثواني داخلها) + «إلغاء صلة القرابة» ×، والكبسولة كلها زرّ.
/// الحلقة حركة خطية واحدة (لا تكرار)، والرقم يتحدّث مرة كل ثانية فقط.
private struct KinshipExitBar: View {
    let endsAt: Date
    let duration: Double
    let onCancel: () -> Void
    @State private var remaining: CGFloat = 1

    var body: some View {
        Button(action: onCancel) {
            HStack(spacing: DS.Spacing.sm) {
                ZStack {
                    Circle().stroke(DS.Color.textOnPrimary.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width * 2)
                    Circle()
                        .trim(from: 0, to: remaining)
                        .stroke(DS.Color.textOnPrimary, style: StrokeStyle(lineWidth: DS.Border.width * 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text("\(max(0, Int(ceil(endsAt.timeIntervalSince(ctx.date)))))")
                            .dsFont(.badge)
                            .monospacedDigit()
                    }
                }
                .frame(width: DS.Icon.row, height: DS.Icon.row)
                .accessibilityHidden(true)

                Text(L10n.t("إلغاء صلة القرابة", "Exit kinship"))
                    .dsFont(.chip)
                Image(systemName: "xmark")
                    .dsGlyph(DS.Glyph.sm)
            }
            .foregroundColor(DS.Color.textOnPrimary)
            .padding(.leading, DS.Spacing.xs)
            .padding(.trailing, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
            .background(Capsule().fill(DS.Color.warning.dsSolidFill))
            .modifier(DSClaySkin(onFill: true, shadow: true, section: .tree))
            .contentShape(Capsule())
        }
        .buttonStyle(DSPressStyle())
        .onAppear {
            remaining = CGFloat(max(0, endsAt.timeIntervalSinceNow) / duration)
            withAnimation(.linear(duration: max(0, endsAt.timeIntervalSinceNow))) { remaining = 0 }
        }
    }
}

private struct TreeToolPop: ViewModifier {
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : DSMotion.iconFromScale)
            .opacity(shown ? 1 : 0)
            .animation(reduceMotion ? DSMotion.fade : DSMotion.iconPop.delay(0.4), value: shown)
    }
}


// MARK: - 3. عقدة الفرد — Liquid Glass
struct TreeMemberNode: View, Equatable {
    let member: FamilyMember
    let isExpanded: Bool
    @Binding var searchedMemberID: UUID?
    let hasChildren: Bool
    let childrenCount: Int
    let showName: Bool
    var level: Int = 0
    let currentLocationMemberID: UUID?
    var isKinshipHighlighted: Bool = false
    /// قيمة البحث وقت بناء العقدة — للمقارنة (الربط يقرأ القيمة الحالية دائماً فلا يصلح لها)
    var searchedSnapshot: UUID? = nil
    /// معامل «حجم النص» (`DS.TreeScale`، من تخطيط الشجرة): كل مقاس في العقدة × k — ١ = الشكل الافتراضي
    var k: CGFloat = 1
    let onTap: () -> Void
    let onToggle: () -> Void

    /// العقدة تُعاد فقط إن تغيّرت بياناتها (الإغلاقات تشير لنفس حالة الشجرة)
    static func == (a: TreeMemberNode, b: TreeMemberNode) -> Bool {
        a.member == b.member && a.isExpanded == b.isExpanded && a.hasChildren == b.hasChildren
            && a.childrenCount == b.childrenCount && a.showName == b.showName && a.level == b.level
            && a.currentLocationMemberID == b.currentLocationMemberID
            && a.isKinshipHighlighted == b.isKinshipHighlighted && a.searchedSnapshot == b.searchedSnapshot
            && a.k == b.k
    }
    @State private var shouldLoadImage = false
    @State private var isPulsing = false
    @State private var arrowGlow = false

    private var isCurrentLocationMember: Bool {
        member.id == currentLocationMemberID
    }

    // لون دائرة الصورة — ذهبي إذا جزء من مسار القرابة
    private var nodeAccentColor: Color {
        if isKinshipHighlighted {
            return DS.Color.accent
        }
        if member.isDeceased == true {
            return DS.Color.deceased
        }
        switch member.role {
        case .owner: return DS.Color.ownerRole
        case .admin: return DS.Color.adminRole
        case .monitor: return DS.Color.monitorRole
        case .supervisor: return DS.Color.supervisorRole
        default: return DS.Color.male   // عقدة العضو: كحلي ثابت (معنى) — لا يتبع لون القسم
        }
    }

    // لون الإطار = نفس لون الدائرة
    private var borderColor: Color { nodeAccentColor }

    // تعبئة العقدة — لون صلب بلا تدرّج (الهوية). تحت أيقونة الشخص البيضاء يأخذ الكحلي والمتوفّى
    // تعبئتهما الثابتة (primaryFill / deceasedFill) حتى يبقى الأبيض مقروءاً في الداكن
    private var nodeFill: Color {
        if isKinshipHighlighted { return nodeAccentColor }
        if member.isDeceased == true { return DS.Color.deceasedFill }
        switch member.role {
        case .owner, .admin, .monitor, .supervisor: return nodeAccentColor
        default: return DS.Color.primaryFill
        }
    }

    // حلقة العقدة وإطار الاسم — لون الرتبة صلباً
    private var borderStroke: Color { nodeAccentColor.opacity(0.9) }

    var body: some View {
            // الوضع التفاعلي — دائري
            VStack(spacing: 0) {
                // الصورة: توسيع/طي الأبناء — وبلا أبناء تفتح التفاصيل (طلب المالك)
                Button {
                    guard TreeTapGuard.allowsTap else { return }
                    if hasChildren {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onToggle()
                    } else {
                        onTap()
                    }
                } label: {
                    ZStack {
                        // الدائرة الرئيسية — أرضية فاتحة بلون الرتبة والمجسّم فوقها، وظلّ ملوّن ناعم (عمق أنظف)
                        Circle()
                            .fill(AnyShapeStyle(nodeAccentColor.opacity(DS.Opacity.tintFill)))
                            .background(Circle().fill(DS.Color.surface))
                            .frame(width: interactiveNodeSize, height: interactiveNodeSize)
                            .shadow(color: nodeAccentColor.opacity(member.isDeceased == true ? 0.12 : 0.26),
                                    radius: 10 * k, x: 0, y: 5 * k)

                        // الصورة أو الأيقونة
                        if shouldLoadImage, let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
                            CachedAsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                avatarArt
                            }
                            .frame(width: interactiveNodeSize, height: interactiveNodeSize)
                            .clipShape(Circle())
                            .saturation(member.isDeceased == true ? 0 : 1)   // المتوفّى: صورة غير ملوّنة
                        } else {
                            avatarArt
                        }

                        // فاصل داخلي بلون السطح — يفصل الصورة عن الحلقة (مظهر أنظف)
                        Circle()
                            .stroke(DS.Color.surface, lineWidth: 2.5 * k)
                            .frame(width: interactiveNodeSize, height: interactiveNodeSize)

                        // حلقة خارجية بلون الرتبة (رصاصية للمتوفّى — تمييز أوضح)
                        Circle()
                            .stroke(borderStroke, lineWidth: 3 * k)
                            .frame(width: interactiveNodeSize + 6 * k, height: interactiveNodeSize + 6 * k)
                    }
                }
                .overlay {
                    // «أنت هنا» — حلقة زرقاء ثابتة دائمة حول عقدتك
                    if isCurrentLocationMember {
                        Circle()
                            .stroke(DS.Color.currentLocation.opacity(0.9), lineWidth: 3 * k)
                            .frame(width: interactiveNodeSize + 16 * k, height: interactiveNodeSize + 16 * k)
                    }
                }
                .overlay {
                    // حلقة البحث المتوهجة
                    if searchedMemberID == member.id {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [AppSection.tree.ink, AppSection.tree.ink],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 5 * k
                            )
                            .frame(width: interactiveNodeSize + 14 * k, height: interactiveNodeSize + 14 * k)
                            .dsGlowShadow()
                    }
                }
                .overlay {
                    // وميض الموقع (الدائرة الزرقاء — يجب أن يكون تحت شريط المتوفى)
                    if isCurrentLocationMember {
                        Circle()
                            .stroke(DS.Color.currentLocation, lineWidth: 4.2 * k)
                            .frame(width: interactiveNodeSize + 10 * k, height: interactiveNodeSize + 10 * k)
                            .scaleEffect(isPulsing ? 1.35 : 1.0)
                            .opacity(isPulsing ? 0.0 : 0.9)
                            .shadow(color: DS.Color.currentLocation.opacity(0.5), radius: 12 * k)
                            .animation(Animation.easeOut(duration: 1.25).repeatCount(4, autoreverses: false), value: isPulsing)
                            .onAppear { isPulsing = true }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // شارة الوفاة — قلب مكسور رمادي في الزاوية (نفس نمط شجرة النساء والتفاصيل)
                    if member.isDeceased ?? false {
                        Circle()
                            .fill(DS.Color.background)
                            .frame(width: 30 * k, height: 30 * k)
                            .overlay(
                                Image(systemName: "heart.slash.fill")
                                    .dsTreeGlyph(DS.Glyph.md, k)
                                    .foregroundColor(DS.Color.textTertiary)
                            )
                            .overlay(Circle().stroke(DS.Color.deceased.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width * k))
                            .offset(x: -6 * k, y: -6 * k)
                    }
                }
                .overlay(alignment: .topLeading) {
                    // شارة عدد الأبناء + سهم — فوق يسار الصورة (رقم أكبر — طلب المالك)
                    if hasChildren {
                        HStack(spacing: DS.Spacing.xxs * k) {
                            Text("\(childrenCount)")
                                .dsTreeFont(.nodeCount, k)
                            Image(systemName: "chevron.down")
                                .dsTreeGlyph(DS.Glyph.xs, k, weight: .heavy)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                        .foregroundColor(DS.Color.textOnPrimary)
                        .padding(.horizontal, DS.Spacing.sm * k)
                        .frame(minWidth: 34 * k, minHeight: 32 * k)
                        // غامق قسم الشجرة (كان كحلياً ثابتاً) — أغمق من لون العضو بلا صورة
                        .background(Capsule().fill(isKinshipHighlighted ? DS.Color.warning
                                                   : AppSection.tree.deep))
                        // لمسة الطين الواحدة بظلّها (كان ظلاً يدوياً)
                        .modifier(DSClaySkin(onFill: true, compact: true, shadow: true, section: .tree))
                        .overlay(Capsule().stroke(DS.Color.textOnPrimary.opacity(DS.Opacity.selectedStroke),
                                                  lineWidth: DS.Border.widthBold * k))
                        .offset(x: -2 * k, y: 0)
                    }
                }
                .overlay(alignment: .top) {
                    // علامة "أنت هنا" — overlay لا يأثر على الـ layout
                    if isCurrentLocationMember {
                        Text(L10n.t("أنت هنا", "You"))
                            .dsTreeFont(.badge, k)
                            .foregroundColor(DS.Color.onTint)
                            .padding(.horizontal, DS.Spacing.sm * k)
                            .padding(.vertical, DS.Spacing.xxs * k)
                            .background(DS.Color.currentLocation)
                            .clipShape(Capsule())
                            .offset(y: -16 * k)
                    }
                }
                .task {
                    // تأخير تحميل الصور حسب المستوى لتحسين الأداء
                    if level <= 1 {
                        shouldLoadImage = true
                    } else {
                        try? await Task.sleep(nanoseconds: UInt64(level) * 200_000_000)
                        guard !Task.isCancelled else { return }
                        shouldLoadImage = true
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(nodeAccessibilityLabel)
                .accessibilityHint(hasChildren
                    ? L10n.t("توسيع أو طي الأبناء", "Expand or collapse children")
                    : L10n.t("افتح التفاصيل", "Open details"))

                // الاسم — كبسولة مستقلة، وتحتها مربع التاريخ المنفصل للمتوفى.
                // نموذج تفاعل موحّد: كل ما يخص الشخص (دائرة/اسم/تواريخ) يفتح تفاصيله،
                // والتوسيع له زر مستقل مدخل تحت آخر مربع (شريحة العدد + السهم).
                Button(action: { if TreeTapGuard.allowsTap { onTap() } }) {
                    Group {
                        if member.isDeceased ?? false {
                            // ── المتوفّى: بطاقة واحدة مدمجة — الاسم فوق وشريط السنوات الأحمر تحته ──
                            VStack(spacing: 0) {
                                if showName {
                                    Text(displayName)
                                        .dsTreeFont(.headline, k)
                                        .foregroundColor(DS.Color.textPrimary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                        .padding(.horizontal, DS.Spacing.lg * k)
                                        .padding(.vertical, DS.Spacing.xs * k)
                                        .frame(minWidth: interactiveLabelWidth, minHeight: interactiveLabelHeight + 2 * k)
                                        .background(DS.Color.surface)
                                }
                                Text(getLifeSpan())
                                    .dsTreeFont(.badge, k)
                                    .foregroundColor(DS.Color.textOnPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .padding(.horizontal, DS.Spacing.md * k)
                                    // سطر خط الهوية أطول من خط النظام (١٫٥×) — حشوة أصغر فيبقى الشريط ٢١ كما كان
                                    .padding(.vertical, DS.Spacing.xxs * k)
                                    // maxWidth يمدّد الشريط الأحمر ليطابق عرض الاسم مهما طال
                                    .frame(minWidth: interactiveLabelWidth, maxWidth: .infinity, minHeight: 21 * k)
                                    .background(DS.Color.deceasedStrip)   // عنّابي بدرجة خفيفة (طلب المالك)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg * k, style: .continuous))
                            .modifier(DSClaySkin(radius: DS.Radius.lg * k,
                                                 eyeRow: showName ? interactiveLabelHeight + 2 * k : nil, section: .tree))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg * k, style: .continuous)
                                .stroke(borderStroke, lineWidth: 2.5 * k))
                        } else if showName {
                            Text(displayName)
                                .dsTreeFont(.headline, k)
                                .foregroundColor(DS.Color.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .padding(.horizontal, DS.Spacing.lg * k)
                                .padding(.vertical, DS.Spacing.xs * k)
                                .frame(minWidth: interactiveLabelWidth, minHeight: interactiveLabelHeight + 2 * k)
                                .background(DS.Color.surface)
                                .clipShape(Capsule())
                                .modifier(DSClaySkin(section: .tree))
                                .overlay(Capsule().stroke(borderStroke, lineWidth: 2.5 * k))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(DSScaleButtonStyle())
                .zIndex(1)
                .accessibilityLabel(displayName)
                .accessibilityHint(L10n.t("افتح التفاصيل", "Open details"))
                // (شريحة التوسيع أُزيلت — العدّاد شارة فوق الصورة والصورة تتوسّع)
            }.fixedSize()
    }

    func getLifeSpan() -> String {
        let birth = member.birthDate?.prefix(4); let death = member.deathDate?.prefix(4)
        if (birth == nil || birth == "") && (death == nil || death == "") {
            return L10n.t(member.isFemale ? "متوفية" : "متوفى", "Deceased")
        }
        // سنة الوفاة أولاً ثم الميلاد (طلب المالك)
        // «م» تسبق الرقم (م1947)، والمجهولة «م0000» — طلب المالك
        // كل سنة داخل عزل LTR (U+2066…U+2069) فتبقى «م» ملتصقة بيمين رقمها
        // ولا تنتقل لجهة السنة الأخرى مهما كان اتجاه الواجهة (طلب المالك)
        func iso(_ y: String?) -> String {
            let v = (y == nil || y == "") ? "0000" : y!
            return "\u{2066}م\(v)\u{2069}"
        }
        // الوفاة أولاً ثم الميلاد (معكوس — طلب المالك)
        return "\(iso(death.map(String.init))) - \(iso(birth.map(String.init)))"
    }

    private var displayName: String {
        let first = member.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty { return first }
        let full = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty {
            // أول وحدة (PersonName القاعدة ٣) — «زين العابدين» ما ينقص لـ«زين»
            return PersonName.firstUnit(full)
        }
        return L10n.t("بدون اسم", "No name")
    }

    private var fullDisplayName: String {
        let full = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty { return full }
        let first = member.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty { return first }
        return L10n.t("بدون اسم", "No name")
    }

    /// رسم العضو بلا صورة بأسلوب «مجسّمات»، بلون الرتبة/الجنس نفسه (المعنى لا يتغيّر).
    /// غلاف Equatable فلا يُعاد رسم الكانفس مع كل سحب/تكبير للشجرة.
    private var avatarArt: some View {
        TreeAvatarArt(tint: nodeAccentColor, size: interactiveNodeSize - 4 * k)
            .equatable()
            .frame(width: interactiveNodeSize, height: interactiveNodeSize)
            .clipShape(Circle())
    }

    // مقاسات العقدة × معامل «حجم النص» (k = ١ في الإعداد الافتراضي)
    private var interactiveNodeSize: CGFloat { 105 * k }
    private var interactiveLabelWidth: CGFloat { 110 * k }
    private var interactiveLabelHeight: CGFloat { 28 * k }

    /// وصف صوتي موحّد للعقدة (VoiceOver): الاسم + الحالة + عدد الأبناء
    var nodeAccessibilityLabel: String {
        var parts: [String] = [fullDisplayName]
        if member.isDeceased == true {
            parts.append(L10n.t("متوفى", "deceased"))
        }
        if hasChildren {
            parts.append("\(childrenCount) " + L10n.t("أبناء", "children"))
        }
        if isCurrentLocationMember {
            parts.append(L10n.t("موقعك الحالي", "your location"))
        }
        return parts.joined(separator: "، ")
    }
}

// MARK: - رسوم الشجرة بأسلوب «مجسّمات» (الاتجاه النهائي — اعتماد المالك ٢٠٢٦-١٠-٠٦)
// كل ما هنا ساكن وخفيف — الشجرة فيها مئات العقد: لا ظلال إضافية، ولا كانفس متحرك لكل عقدة،
// ولا TimelineView. الألوان: حبر/غامق قسم الشجرة، وألوان المعنى (ذكر/أنثى/رتبة/متوفّى/القرابة) لا تتغيّر.

/// طبقة واحدة من خط الوصل
struct TreeLineLayer {
    let color: Color
    let style: StrokeStyle
    var dy: CGFloat = 0
}

enum TreeArtLines {
    /// طبقات خط الأب وأبنائه — أنبوب طين: ظلّ ناعم تحته + جسم أعرض + لمعة علوية رفيعة.
    /// `scale` = معامل «حجم النص» (`DS.TreeScale`): الخط بطبقاته يغلظ مع العقد
    static func layers(width: CGFloat, dark: Bool, scale k: CGFloat = 1) -> [TreeLineLayer] {
        let ink = AppSection.tree.ink
        let w = width * k
        func st(_ lw: CGFloat, dash: [CGFloat] = []) -> StrokeStyle {
            StrokeStyle(lineWidth: lw, lineCap: dash.isEmpty ? .round : .butt, lineJoin: .round, dash: dash)
        }
        return [TreeLineLayer(color: AppSection.tree.deep.opacity(dark ? 0.45 : 0.14), style: st(w + 1.6 * k), dy: 1.6 * k),
                TreeLineLayer(color: ink.opacity(dark ? 0.6 : 0.5), style: st(w + 0.8 * k)),
                TreeLineLayer(color: .white.opacity(dark ? 0.14 : 0.55), style: st(max(0.6 * k, w * 0.3)), dy: -0.5 * k)]
    }

    static func stroke(_ ctx: inout GraphicsContext, _ path: Path, _ layers: [TreeLineLayer]) {
        for l in layers {
            ctx.stroke(l.dy == 0 ? path : path.offsetBy(dx: 0, dy: l.dy), with: .color(l.color), style: l.style)
        }
    }

    /// نقطة التفرّع — قرص طين أكبر قليلاً مع لمعة علوية
    static func dot(_ ctx: inout GraphicsContext, at d: CGPoint, r: CGFloat, dark: Bool) {
        let ink = AppSection.tree.ink
        let rect = CGRect(x: d.x - r, y: d.y - r, width: r * 2, height: r * 2)
        let big = rect.insetBy(dx: -r * 0.25, dy: -r * 0.25)
        ctx.fill(Path(ellipseIn: big), with: .color(ink.opacity(0.75)))
        ctx.fill(Path(ellipseIn: CGRect(x: big.minX + big.width * 0.22, y: big.minY + big.height * 0.16,
                                        width: big.width * 0.36, height: big.height * 0.3)),
                 with: .color(.white.opacity(dark ? 0.3 : 0.6)))
    }
}

/// رسم العضو بلا صورة — Equatable: لا يُعاد رسمه إلا إن تغيّر اللون أو المقاس
struct TreeAvatarArt: View, Equatable {
    let tint: Color
    let size: CGFloat
    var icon: String = "person.fill"

    var body: some View {
        DSStateIcon(icon, tint: tint, size: size, mapsChrome: false)
            .allowsHitTesting(false)
    }
}

// لمسة الطين على عناصر الشجرة صارت الواحدة `DSClaySkin` (ArtTrial.swift) — كانت `TreeArtSkin` هنا (أسلوب واحد ٢٠٢٦-١٠-٠٧)
