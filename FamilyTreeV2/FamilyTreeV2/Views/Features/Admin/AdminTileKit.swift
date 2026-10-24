import SwiftUI

// MARK: - مربّعات اللوحة بالمنتصف (طلب المالك ٢٠٢٦-١٠-٢٤ «ودي نخلي الايقونات بالمنتصف مع المسميات و ترتيب شكل المربعات»)
//
// مربّع واحد لكل مدخل تنقّل في «اليوم» وصفحات الأقسام: مربّع الأيقونة بلون القسم/الأداة في الوسط فوق، والاسم تحته في الوسط
// (سطران محجوزان — كل مربّعات الشبكة بطول واحد)، وسطر رقم حيّ اختياري تحته، وشارة عدد على ركن الأيقونة (مثل أيقونات
// الآيفون). شبكة واحدة بأعمدة متساوية وزوايا وحشوة واحدة، وعنوان صغير لكل مجموعة (`AdminSectionLabel`). الحركة: الأيقونات
// تقفز مرة عند الظهور تباعاً (`DSIconPop` بإيقاع `DSMotion`)، والمربّع ينضغط بنابض الضغط الموحّد وأيقونته تكبر قليلاً —
// «تقليل الحركة»: تلاشٍ وخفوت فقط. من أحجام إمكانية الوصول المربّع صفّ (الأيقونة بجانب الاسم) بعمود واحد فلا يُقصّ الاسم.
// القوائم الطويلة وصفوف الأعضاء والإعدادات بمفاتيحها تبقى صفوفاً — هذه للتنقّل فقط.

/// مقاسات المربّع الواحد (مكانها هنا — لا أرقام عند الاستعمال)
enum AdminTileMetrics {
    /// مربّع الأيقونة الممتلئ وزواياه ورمزه الأبيض
    static let icon: CGFloat = 44
    static let iconRadius: CGFloat = 13
    static let glyph: CGFloat = DS.Glyph.xxl
    /// حشوة المربّع: فوق الأيقونة أوسع قليلاً من تحت الاسم (توازن بصري)، والجانبان أضيق (الاسم يتّسع)
    static let paddingTop: CGFloat = DS.Spacing.lg
    static let paddingBottom: CGFloat = DS.Spacing.md
    static let paddingSide: CGFloat = DS.Spacing.sm
    /// أسطر الاسم: بالحجم الافتراضي، ومع خط الجهاز الأكبر
    static let titleLines = 2
    static let titleLinesLarge = 3
    /// بين الأيقونة والاسم، وبين الاسم وسطر الرقم
    static let gap: CGFloat = DS.Spacing.sm + DS.Spacing.xxs
    static let captionGap: CGFloat = DS.Spacing.xxs
    static var radius: CGFloat { DS.Hub.tileRadius }
    /// شارة العدد على ركن الأيقونة: ارتفاعها الأدنى وكم تخرج من الركن
    static let badge: CGFloat = 20
    static let badgeOffset: CGFloat = DS.Spacing.xsm
    /// الصفّ (أحجام إمكانية الوصول): حشوته
    static let rowPadding: CGFloat = DS.Spacing.md
    /// الضغط: المربّع يصغر قليلاً، والأيقونة تكبر، وخفوت بسيط
    static let pressScale: CGFloat = 0.96
    static let pressIconScale: CGFloat = 1.08
    static let pressDim: Double = 0.9
    /// أعمدة الشبكة أفقياً: كل المربّعات في صفّ واحد حتى ستة (الأقسام الستة صفّ واحد بعرض عمود اللوحة)
    static let landscapeMaxColumns = 6
}

// MARK: الشبكة

/// شبكة المربّعات: أعمدة متساوية بفراغ واحد (`AdminGrid.spacing`) — كل مربّع بعرض عموده وطوله واحد
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

// MARK: الشارة

/// شارة على ركن أيقونة المربّع: عدد (بانتظار القرار…) أو علامة تنبيه — بحلقة بلون السطح تفصلها عن الأيقونة
struct AdminTileBadge: View {
    enum Kind: Equatable {
        case count(Int)
        case alert
    }

    let kind: Kind
    /// تعبئة ثابتة تحت نص أبيض (`errorFill` للعدد، `warningFill` للتنبيه)
    var fill: Color = DS.Color.errorFill

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
        .overlay(Capsule().strokeBorder(DS.Color.surface, lineWidth: DS.Border.widthBold))
        .accessibilityHidden(true)
    }

    /// نصّ الشارة للقارئ الصوتي
    static func spoken(_ kind: Kind) -> String {
        switch kind {
        case .count(let n): return L10n.t("\(n) بانتظارك", "\(n) waiting")
        case .alert:        return L10n.t("يحتاج انتباهك", "Needs attention")
        }
    }
}

// MARK: الضغط

private struct AdminTilePressedKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// المربّع مضغوط الآن (من `AdminTilePressStyle`) — أيقونته تكبر قليلاً
    var adminTilePressed: Bool {
        get { self[AdminTilePressedKey.self] }
        set { self[AdminTilePressedKey.self] = newValue }
    }
}

/// ضغطة المربّع: يصغر قليلاً بنابض الضغط الموحّد (`DSMotion.press`) وأيقونته تكبر — «تقليل الحركة»: خفوت فقط
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
            .environment(\.adminTilePressed, configuration.isPressed && !reduceMotion)
            .scaleEffect(configuration.isPressed && !reduceMotion ? AdminTileMetrics.pressScale : 1)
            .opacity(configuration.isPressed ? AdminTileMetrics.pressDim : 1)
            .animation(DSMotion.press, value: configuration.isPressed)
    }
}

// MARK: المربّع

/// وجه المربّع: الأيقونة الممتلئة في الوسط فوق ← الاسم في الوسط (سطران محجوزان) ← سطر الرقم (اختياري، محجوز إن طُلب) —
/// والشارة على ركن الأيقونة. يوضع داخل `NavigationLink`/زرّ بـ`AdminTilePressStyle`
struct AdminHubTile: View {
    let icon: String
    /// تعبئة مربّع الأيقونة (ثابتة تحت رمز أبيض — `AdminArea.fill` أو `tint.dsSolidFill`)
    let fill: Color
    let title: String
    /// رقم حيّ صغير تحت الاسم («53 فرد»، «3 الآن»)
    var caption: String? = nil
    var captionTint: Color = DS.Color.textTertiary
    /// يحجز سطر الرقم وإن لم يصل بعد — مربّعات الشبكة الواحدة بطول واحد
    var reservesCaption: Bool = false
    var badge: AdminTileBadge.Kind? = nil
    var badgeFill: Color = DS.Color.errorFill
    /// ما تقوله الشارة للقارئ الصوتي («6 طلبات بانتظار القرار») — nil = النص العام
    var badgeSpoken: String? = nil
    /// ترتيبه في الشبكة — قفزة الأيقونات تباعاً
    var index: Int = 0
    /// تلميح القارئ الصوتي (وصف القسم)
    var hint: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                rowFace
            } else {
                tileFace
            }
        }
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
                        .minimumScaleFactor(0.85)
                    if let caption {
                        Text(verbatim: caption)
                            .dsFont(.caption)
                            .monospacedDigit()
                            .foregroundColor(captionTint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .padding(.top, AdminTileMetrics.paddingTop)
        .padding(.bottom, AdminTileMetrics.paddingBottom)
        .padding(.horizontal, AdminTileMetrics.paddingSide)
        .frame(maxWidth: .infinity)
        .dsCard(padding: nil, radius: AdminTileMetrics.radius)
        .contentShape(RoundedRectangle(cornerRadius: AdminTileMetrics.radius, style: .continuous))
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
                if let caption {
                    Text(verbatim: caption)
                        .dsFont(.caption)
                        .foregroundColor(captionTint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.Spacing.xs)
            if let badge {
                AdminTileBadge(kind: badge, fill: badgeFill)
            }
            DSChevron()
        }
        .padding(AdminTileMetrics.rowPadding)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
        .dsCard(padding: nil, radius: AdminTileMetrics.radius)
        .contentShape(RoundedRectangle(cornerRadius: AdminTileMetrics.radius, style: .continuous))
    }
}

/// أيقونة المربّع الممتلئة (رمز أبيض) — تقفز مرة عند الظهور بترتيبها، وتكبر قليلاً مع الضغط، والشارة على ركنها
private struct AdminTileIcon: View {
    let icon: String
    let fill: Color
    let badge: AdminTileBadge.Kind?
    let badgeFill: Color
    let index: Int
    @Environment(\.adminTilePressed) private var pressed

    var body: some View {
        Image(dsSymbol: icon)
            .dsGlyph(AdminTileMetrics.glyph, weight: .semibold)
            .foregroundColor(DS.Color.textOnPrimary)
            .frame(width: AdminTileMetrics.icon, height: AdminTileMetrics.icon)
            .background(RoundedRectangle(cornerRadius: AdminTileMetrics.iconRadius, style: .continuous).fill(fill))
            .scaleEffect(pressed ? AdminTileMetrics.pressIconScale : 1)
            .animation(DSMotion.press, value: pressed)
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

// MARK: مربّع أداة (صفحات الأقسام)

/// مربّع أداة من فهرس الأدوات — يفتح صفحتها كما يفتحها صفّها (`AdminToolRow`)، أو ينفّذ إجراءها
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
        AdminHubTile(icon: tool.icon, fill: tool.tint.dsSolidFill, title: tool.title, caption: caption,
                     captionTint: warn ? DS.Color.warning : DS.Color.textTertiary,
                     reservesCaption: reservesCaption, badge: warn ? .alert : nil, badgeFill: DS.Color.warningFill,
                     index: index, hint: tool.subtitle)
    }
}
