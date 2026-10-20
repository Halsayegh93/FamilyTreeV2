import SwiftUI

// MARK: - عُدّة لوحة الإدارة «مركز القيادة» (طلب المالك ٢٠٢٦-١٠-٢٠ — الاتجاه «أ»)
//
// قطع مشتركة لصفحة «اليوم» وصفحات الأقسام الستة و«الوارد»: الرأس الكحلي بحلقته الذهبية الساكنة، الأزرار
// الزجاجية، مربّعات الأرقام، البطاقة البيضاء بعنوانها، مربّع الأيقونة الملوّن، أزرار الكبسولة، صفّ القسم، شريط
// مراحل الطلب. كل المقاسات والألوان من `DS.Hub` (DesignSystem.swift) — لا أرقام هنا.

// MARK: الأقسام

/// أقسام اللوحة بعد «اليوم» — الاسم والرمز ولون مربّعه وظهوره حسب الدور (IA.md). ستة منذ ٢٠٢٦-١٠-٢٠ (اختيار
/// المالك «٦ أقسام»): «المناسبات والإعلانات» = المناسبات + الإعلانات، و«الفريق والأمان» = الفريق + الدخول والأمان.
/// ظهور القسم المدموج = اتحاد شرطي القسمين (كل صفّ داخله بصلاحيته كما كانت — لا يرى دورٌ أكثر مما رأى).
enum AdminArea: String, CaseIterable, Identifiable, Hashable {
    case inbox, family, occasions, metrics, team, app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox:     return L10n.t("الوارد", "Inbox")
        case .family:    return L10n.t("العائلة", "Family")
        case .occasions: return L10n.t("المناسبات والإعلانات", "Occasions & announcements")
        case .metrics:   return L10n.t("المؤشرات", "Insights")
        case .team:      return L10n.t("الفريق والأمان", "Team & security")
        case .app:       return L10n.t("التطبيق", "App")
        }
    }

    var subtitle: String {
        switch self {
        case .inbox:     return L10n.t("الطلبات ورسائل الأعضاء", "Requests and member messages")
        case .family:    return L10n.t("الأعضاء وبياناتهم وحساباتهم", "Members, their details and accounts")
        case .occasions: return L10n.t("الوفيات والذكرى والمنشورات، والإعلان للأعضاء",
                                       "Deaths, memorials and posts, and announcing to members")
        case .metrics:   return L10n.t("أرقام وتاريخ — للقراءة", "Numbers and history — read only")
        case .team:      return L10n.t("من يدير، ومن يدخل التطبيق وكيف", "Who manages, who signs in and how")
        case .app:       return L10n.t("إعدادات التطبيق والتشغيل", "App settings and operations")
        }
    }

    var icon: String {
        switch self {
        case .inbox:     return "tray.full.fill"
        case .family:    return "person.3.fill"
        case .occasions: return "calendar.badge.clock"
        case .metrics:   return "chart.xyaxis.line"
        case .team:      return "person.badge.shield.checkmark.fill"
        case .app:       return "gearshape.2.fill"
        }
    }

    /// لون مربّع القسم (تعبئة ثابتة بنص أبيض — عائلة الكحلي والذهبي)
    var fill: Color {
        switch self {
        case .inbox:     return DS.Color.primaryFill
        case .family:    return DS.Color.palmFill
        case .occasions: return DS.Color.saduFill
        case .metrics:   return DS.Color.goldFill
        case .team:      return DS.Color.navyFill
        case .app:       return DS.Color.slateFill
        }
    }

    /// يظهر هذا القسم لدور المشاهد — القسم الفارغ لدورك لا يُرسم (المبدأ ٥ في IA.md).
    /// المدموجان: المناسبات (`canModerate`) ∪ الإعلانات (`canSendNotifications` ⊂ الإدارة)، والفريق (`isAdmin`) ∪
    /// الدخول والأمان (`canViewSystemSettings`)
    @MainActor
    func isVisible(for authVM: AuthViewModel) -> Bool {
        let role = authVM.currentUser?.role
        switch self {
        case .inbox:     return authVM.canModerate
        case .family:    return authVM.canEditMembers
        case .occasions: return authVM.canModerate || authVM.canSendNotifications
        case .metrics:   return authVM.isAdmin || role == .monitor
        case .team:      return authVM.isAdmin || authVM.canViewSystemSettings
        case .app:       return authVM.canViewSystemSettings
        }
    }

    /// الأقسام الظاهرة لهذا الدور بترتيبها
    @MainActor
    static func visible(for authVM: AuthViewModel) -> [AdminArea] {
        allCases.filter { $0.isVisible(for: authVM) }
    }
}

// MARK: التنقّل بين الأقسام (طلب المالك ٢٠٢٦-١٠-٢٠ «مابي تويب علوي فكر بشي ابسط»)
//
// لا شريط أقسام: عنوان صفحة القسم في الرأس الكحلي قائمة أصلية «العائلة ⌄» بالأقسام الظاهرة لدورك (الحالي بعلامة).
// «اليوم» يسجّل في `AdminAreaRouter` ناقلاً يستبدل مسار مكدسه بصفحة القسم المختار (لا تراكم). وقسم الصفحة في البيئة
// (`adminArea`) يضعه من يفتحها — الصفحة المدفوعة في `NavigationStack` لا ترث بيئة موضع الرابط، فكل من يدفع صفحة
// يمرّر قسمه صراحةً (مثل `adminBackTitle`). الصفحات الداخلية: زرّ الرجوع واسم القسم فقط. بلا ناقل (قبل فتح تبويب
// الإدارة) أو بلا قسم: العنوان نصّ عادي.

/// ناقل مكدس «اليوم» إلى صفحة قسم — يضبطه `AdminDashboardView` عند ظهوره (nil قبله)
@MainActor
enum AdminAreaRouter {
    static var navigate: ((AdminArea) -> Void)?
}

private struct AdminAreaKey: EnvironmentKey { static let defaultValue: AdminArea? = nil }

extension EnvironmentValues {
    /// القسم الذي تنتمي له الصفحة الحالية — يضعه من يفتحها، ويمرّره لما تدفعه هي
    var adminArea: AdminArea? {
        get { self[AdminAreaKey.self] }
        set { self[AdminAreaKey.self] = newValue }
    }
}

extension View {
    /// الصفحة تتبع هذا القسم (قائمة العنوان، وما تدفعه من صفحات)
    func adminArea(_ area: AdminArea?) -> some View {
        environment(\.adminArea, area)
    }
}

/// عنوان صفحة القسم: قائمة أصلية (`Menu`) — «العائلة ⌄» وتحتها الأقسام الظاهرة لدورك، والحالي بعلامة ✓.
/// الاختيار ينقل مباشرة (المسار يُستبدل). بلا ناقل أو بلا قسم يبقى العنوان نصّاً.
struct AdminAreaTitleMenu: View {
    let title: String
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.adminArea) private var current

    var body: some View {
        if let navigate = AdminAreaRouter.navigate, let current {
            Menu {
                Picker(selection: Binding(get: { current }, set: { area in
                    guard area != current else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    navigate(area)
                })) {
                    ForEach(AdminArea.visible(for: authVM)) { area in
                        Label(area.title, systemImage: area.icon).tag(area)
                    }
                } label: {
                    Text(L10n.t("الأقسام", "Sections"))
                }
                .pickerStyle(.inline)
            } label: {
                label(chevron: true)
            }
            .accessibilityLabel(L10n.t("\(title)، تبديل القسم", "\(title), switch section"))
            .accessibilityHint(L10n.t("يعرض أقسام اللوحة", "Shows the dashboard sections"))
        } else {
            label(chevron: false)
        }
    }

    private func label(chevron: Bool) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.xsm) {
            Text(title)
                .dsFont(.hubTitle)
                .foregroundColor(DS.Color.textOnPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            if chevron {
                Image(systemName: "chevron.down")
                    .dsGlyph(DS.Glyph.lg, weight: .bold)
                    .foregroundColor(DS.Color.accentLight)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: الرأس الكحلي

/// خلفية الرأس: تدرّج الكحلي + الحلقة الذهبية الساكنة في الطرف السفلي الأيمن (كما في النموذج «أ»)
struct AdminBandBackground: View {
    var body: some View {
        DS.Hub.band
            // الحلقة فوق التدرّج بلا أن تكبّر الرأس — ما يخرج منها يُقصّ بحدوده
            .overlay(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .stroke(DS.Hub.ringHalo, lineWidth: DS.Hub.ringHaloWidth)
                        .frame(width: DS.Hub.ringSide + DS.Hub.ringHaloWidth,
                               height: DS.Hub.ringSide + DS.Hub.ringHaloWidth)
                    Circle()
                        .strokeBorder(DS.Hub.ringStroke, lineWidth: DS.Border.width)
                        .frame(width: DS.Hub.ringSide, height: DS.Hub.ringSide)
                }
                .frame(width: 0, height: 0)
                .offset(x: DS.Hub.ringOffsetX - DS.Hub.ringSide / 2, y: DS.Hub.ringOffsetY - DS.Hub.ringSide / 2)
            }
            .clipped()
            // موضع فيزيائي ثابت (يمين أسفل) في الاتجاهين — زخرفة لا تتبع اتجاه اللغة
            .environment(\.layoutDirection, .leftToRight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// خلفية الرأس الكحلي: التدرّج تحت المحتوى (وأفقياً تحت النوتش وطرف الشاشة). منطقة شريط الحالة فوقه
    /// يغطّيها `adminStatusBarCover()` على جذر الصفحة بنفس الكحلي — فيلتقيان بلا خطّ
    func adminBandBackground(landscape: Bool) -> some View {
        background(AdminBandBackground().ignoresSafeArea(edges: landscape ? .horizontal : []))
    }
}

/// دائرة زجاجية فوق الرأس (بحث، جرس، إعدادات…) — اسم الرمز ونقطة «جديد» اختيارية، أو عدد (جرس «اليوم»)
struct AdminGlassCircle: View {
    let symbol: String
    var dot: Bool = false
    /// عدد أحمر على الركن بدل النقطة (٠ = لا شيء)
    var count: Int = 0

    var body: some View {
        Image(dsSymbol: symbol)
            .dsGlyph(DS.Glyph.lg, weight: .semibold)
            .foregroundColor(DS.Color.textOnPrimary)
            .frame(width: DS.Hub.glassButton, height: DS.Hub.glassButton)
            .background(Circle().fill(DS.Hub.glass))
            .overlay(Circle().strokeBorder(DS.Hub.glassLine, lineWidth: DS.Border.width))
            .overlay(alignment: .topLeading) {
                if count > 0 {
                    Text(verbatim: count > 99 ? "99+" : "\(count)")
                        .dsFont(.badge)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textOnPrimary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, DS.Spacing.xs)
                        .frame(minWidth: DS.Hub.bellBadge, minHeight: DS.Hub.bellBadge)
                        .background(Capsule().fill(DS.Hub.bellDot))
                        .overlay(Capsule().strokeBorder(DS.Hub.bandTop, lineWidth: DS.Border.widthBold))
                        .offset(x: -DS.Spacing.xs, y: -DS.Spacing.xs)
                        .accessibilityHidden(true)
                } else if dot {
                    Circle()
                        .fill(DS.Hub.bellDot)
                        .frame(width: DS.Hub.bellDotSize, height: DS.Hub.bellDotSize)
                        .overlay(Circle().strokeBorder(DS.Hub.bandTop, lineWidth: DS.Border.widthBold))
                        .offset(x: DS.Spacing.xsm, y: DS.Spacing.xsm)
                }
            }
            .dsTapArea(width: DS.Hub.glassButton, height: DS.Hub.glassButton)
    }
}

/// زرّ دائري زجاجي بإجراء
struct AdminGlassButton: View {
    let symbol: String
    let label: String
    var dot: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { AdminGlassCircle(symbol: symbol, dot: dot) }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityLabel(label)
    }
}

/// «‹ اليوم» بالذهبي — الرجوع لصفحة اللوحة الأولى
struct AdminBackLink: View {
    var title: String = L10n.t("اليوم", "Today")
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xxs) {
                Image(systemName: "chevron.backward")
                    .dsGlyph(DS.Glyph.lg, weight: .semibold)
                Text(title)
                    .dsFont(.chip)
                    .lineLimit(1)
            }
            .foregroundColor(DS.Color.accentLight)
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("رجوع إلى \(title)", "Back to \(title)"))
    }
}

/// شارة صغيرة فوق الرأس («للقراءة — يعدّلها المالك»، «تشغيل فعلي»…)
struct AdminBandChip: View {
    let text: String
    var icon: String? = nil
    var tint: Color = DS.Hub.rolePillInk

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            if let icon {
                Image(dsSymbol: icon).dsGlyph(DS.Glyph.xs)
            }
            Text(text)
                .dsFont(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundColor(tint)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xxs + 1)
        .background(Capsule().fill(DS.Hub.rolePillFill))
        .overlay(Capsule().strokeBorder(DS.Hub.rolePillStroke, lineWidth: DS.Border.width / 2))
    }
}

/// رأس صفحة القسم: «‹ اليوم» + أزرار زجاجية، العنوان الكبير، الوصف، ثم ملحق اختياري (شرائح، أرقام)
struct AdminBandHeader<Buttons: View, Accessory: View>: View {
    var backTitle: String? = L10n.t("اليوم", "Today")
    let title: String
    var subtitle: String? = nil
    var badge: String? = nil
    var bottomPadding: CGFloat = DS.Hub.headerBottomCompact
    /// صفحة القسم نفسها (لا داخلية) — العنوان قائمة الأقسام
    var isAreaRoot: Bool = false
    @ViewBuilder var buttons: () -> Buttons
    @ViewBuilder var accessory: () -> Accessory
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dsLandscape) private var landscape
    /// اسم الصفحة التي فُتحت منها (إن مرّره من دفعها) — يغلب «اليوم» الافتراضي
    @Environment(\.adminBackTitle) private var outerBack

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                if let backTitle {
                    AdminBackLink(title: outerBack ?? backTitle) { dismiss() }
                }
                Spacer(minLength: DS.Spacing.sm)
                HStack(spacing: DS.Spacing.sm) { buttons() }
            }
            .frame(minHeight: DS.Hub.glassButton)

            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                // صفحة القسم: العنوان قائمة الأقسام (خلف `AnyView` — حارس المكدس)
                if isAreaRoot {
                    AnyView(AdminAreaTitleMenu(title: title))
                } else {
                    Text(title)
                        .dsFont(.hubTitle)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 0)
                if let badge {
                    AdminBandChip(text: badge, icon: "eye.fill")
                }
            }
            .padding(.top, DS.Spacing.xsm)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Hub.onBandMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Spacing.xxs)
            }

            accessory()
        }
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth - 2 * DS.Spacing.lg)
        .padding(.horizontal, landscape ? DS.Spacing.xxl : DS.Spacing.lg)
        .padding(.top, DS.Hub.headerTop)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminBandBackground(landscape: landscape)
        .dsLightStatusBar()
    }
}

extension AdminBandHeader where Accessory == EmptyView {
    init(backTitle: String? = L10n.t("اليوم", "Today"), title: String, subtitle: String? = nil,
         badge: String? = nil, bottomPadding: CGFloat = DS.Hub.headerBottomCompact, isAreaRoot: Bool = false,
         @ViewBuilder buttons: @escaping () -> Buttons) {
        self.init(backTitle: backTitle, title: title, subtitle: subtitle, badge: badge,
                  bottomPadding: bottomPadding, isAreaRoot: isAreaRoot, buttons: buttons, accessory: { EmptyView() })
    }
}

extension AdminBandHeader where Buttons == EmptyView, Accessory == EmptyView {
    init(backTitle: String? = L10n.t("اليوم", "Today"), title: String, subtitle: String? = nil,
         badge: String? = nil, bottomPadding: CGFloat = DS.Hub.headerBottomCompact, isAreaRoot: Bool = false) {
        self.init(backTitle: backTitle, title: title, subtitle: subtitle, badge: badge,
                  bottomPadding: bottomPadding, isAreaRoot: isAreaRoot, buttons: { EmptyView() },
                  accessory: { EmptyView() })
    }
}

/// مربّع رقم زجاجي في الرأس (بانتظارك، مستعجل، متأخر، رسائل)
struct AdminKPITile: View {
    let value: String
    let label: String
    let icon: String
    var tint: Color = DS.Color.textOnPrimary
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // خط الجهاز أكبر من الافتراضي: التسمية على سطرين بدل قصّها («نشطون هذا الأسبوع»، «تصلهم الإشعارات») —
        // كل مربّع يحجز السطرين فتبقى المربّعات بطول واحد (بلا `fixedSize` على الصفّ: يعمّق مكدس «اليوم» ~٣٥ ك.ب).
        // الحجم الافتراضي كما كان تماماً.
        let wraps = typeSize > .large
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(value)
                .dsFont(.hubKPI)
                .monospacedDigit()
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            HStack(alignment: wraps ? .firstTextBaseline : .center, spacing: DS.Spacing.xs) {
                Image(dsSymbol: icon).dsGlyph(DS.Glyph.sm, weight: .semibold)
                Text(label)
                    .dsFont(.caption)
                    .lineLimit(wraps ? 2 : 1, reservesSpace: wraps)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(DS.Hub.onBandMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Hub.kpiPadding)
        .background(RoundedRectangle(cornerRadius: DS.Hub.kpiRadius, style: .continuous).fill(DS.Hub.glass))
        .overlay(RoundedRectangle(cornerRadius: DS.Hub.kpiRadius, style: .continuous)
            .strokeBorder(DS.Hub.glassLine, lineWidth: DS.Border.width))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// شريحة فلتر فوق الرأس (بانتظارك ٩، مستعجل ٢…) — المختارة ذهبية
struct AdminBandFilterChip: View {
    let title: String
    let count: Int?
    var icon: String? = nil
    var iconTint: Color = DS.Color.textOnPrimary
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                if let icon {
                    Image(dsSymbol: icon)
                        .dsGlyph(DS.Glyph.sm)
                        .foregroundColor(selected ? DS.Hub.onGold : iconTint)
                }
                Text(title).dsFont(.caption)
                if let count {
                    Text("\(count)")
                        .dsFont(.chip)
                        .monospacedDigit()
                        .foregroundColor(selected ? DS.Hub.onGold : DS.Color.textOnPrimary)
                }
            }
            .lineLimit(1)
            .foregroundColor(selected ? DS.Hub.onGold : DS.Hub.onBandMuted)
            .padding(.horizontal, DS.Spacing.md)
            .frame(minHeight: DSBox.chipHeight)
            .background(Capsule().fill(selected ? DS.Color.accentLight : DS.Hub.glass))
            .overlay(Capsule().strokeBorder(selected ? Color.clear : DS.Hub.glassLine, lineWidth: DS.Border.width))
            .dsTapArea(width: DS.Icon.tapTarget, height: DSBox.chipHeight)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(count.map { "\(title) \($0)" } ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: البطاقة

/// بطاقة اللوحة البيضاء (زوايا ٢٠، حشوة ١٤) — `.dsCard` الواحدة بمقاسات «مركز القيادة»
extension View {
    func adminCard(padding: CGFloat? = DS.Hub.cardPadding) -> some View {
        dsCard(padding: padding, radius: DS.Hub.cardRadius)
    }
}

/// عنوان البطاقة: العنوان العريض + شارة عدد اختيارية + رابط ذهبي في الطرف
struct AdminCardHeader<Trailing: View>: View {
    let title: String
    var badge: Int? = nil
    var badgeTint: Color = DS.Color.warning
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xsm) {
                Text(title)
                    .dsFont(.headline)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let badge, badge > 0 {
                    AdminCountBadge(count: badge, tint: badgeTint)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Spacing.sm)
            trailing()
        }
        .padding(.bottom, DS.Spacing.xs)
    }
}

extension AdminCardHeader where Trailing == EmptyView {
    init(title: String, badge: Int? = nil, badgeTint: Color = DS.Color.warning) {
        self.init(title: title, badge: badge, badgeTint: badgeTint, trailing: { EmptyView() })
    }
}

/// شارة العدد الدائرية بجانب عنوان البطاقة (كهرماني خفيف)
struct AdminCountBadge: View {
    let count: Int
    var tint: Color = DS.Color.warning

    var body: some View {
        let ink = tint.dsReadableGlyph
        Text(count > 99 ? "99+" : "\(count)")
            .dsFont(.caption)
            .monospacedDigit()
            .foregroundColor(ink)
            .padding(.horizontal, DS.Spacing.xsm)
            .frame(minWidth: DS.Icon.section, minHeight: DS.Icon.section)
            .background(Capsule().fill(ink.opacity(DS.Opacity.tintFill)))
    }
}

/// رابط ذهبي في طرف عنوان البطاقة («الوارد ١٤ ‹»، «عرض المنجز»)
struct AdminCardLinkLabel: View {
    let title: String
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            Text(title)
                .dsFont(.chip)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if showsChevron {
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
            }
        }
        .foregroundColor(DS.Color.accent)
        .frame(minHeight: DS.Icon.tapTarget)
        .contentShape(Rectangle())
    }
}

/// فاصل الصفوف داخل البطاقة
struct AdminRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke * 2))
            .frame(height: DS.Border.width / 2)
            .accessibilityHidden(true)
    }
}

/// شبكة المربّعات (الأقسام، «نبض العائلة»): عمودان عمودياً، وأعمدة متكيّفة أفقياً
enum AdminGrid {
    static let spacing: CGFloat = DS.Spacing.sm + 2

    static func columns(landscape: Bool) -> [GridItem] {
        landscape
            ? [GridItem(.adaptive(minimum: DS.Landscape.tileMinWidth), spacing: spacing)]
            : [GridItem(.flexible(), spacing: spacing), GridItem(.flexible(), spacing: spacing)]
    }
}

/// عنوان قسم خارج البطاقات («نبض العائلة»، «الأقسام»)
struct AdminSectionLabel: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .dsFont(.sectionTitle)
                .foregroundColor(DS.Color.textTertiary)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
        .padding(.horizontal, DS.Spacing.xs)
        .padding(.top, DS.Spacing.xs)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: مربّع الأيقونة

/// مربّع أيقونة مستدير: خفيف (لون المعنى ١٢٪ ورمز بلونه) أو ممتلئ (تعبئة ثابتة ورمز أبيض)
struct AdminIconSquare: View {
    let symbol: String
    var tint: Color = DS.Color.primary
    var side: CGFloat = DS.Hub.iconSquare
    var radius: CGFloat = DS.Hub.iconSquareRadius
    var filled: Bool = false
    var glyph: CGFloat = DS.Glyph.xl

    var body: some View {
        let ink = tint.dsReadableGlyph
        Image(dsSymbol: symbol)
            .dsGlyph(glyph, weight: .semibold)
            .foregroundColor(filled ? DS.Color.textOnPrimary : ink)
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(filled ? tint.dsSolidFill : ink.opacity(DS.Opacity.tintFill)))
            .accessibilityHidden(true)
    }
}

// MARK: أزرار الكبسولة

/// شكل زرّ الكبسولة في الصفوف والبطاقات (النموذج «أ»): كحلي ممتلئ، رملي هادئ، رفض خفيف، ذهبي، زجاجي فوق الرأس
enum AdminPillStyle {
    case navy, soft, reject, gold, glass
}

struct AdminPillLabel: View {
    let title: String
    var icon: String? = nil
    var style: AdminPillStyle = .soft
    var height: CGFloat = DS.Hub.pillHeight
    var fullWidth: Bool = false

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            if let icon {
                Image(dsSymbol: icon).dsGlyph(DS.Glyph.md, weight: .semibold)
            }
            Text(title)
                .dsFont(.hubButton)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(ink)
        .padding(.horizontal, DS.Hub.pillPadding)
        .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(style == .glass ? DS.Hub.glassLine : Color.clear, lineWidth: DS.Border.width))
    }

    private var ink: Color {
        switch style {
        case .navy:   return DS.Color.textOnPrimary
        case .soft:   return DS.Color.textPrimary
        case .reject: return DS.Color.error
        case .gold:   return DS.Hub.onGold
        case .glass:  return DS.Color.textOnPrimary
        }
    }

    private var fill: Color {
        switch style {
        case .navy:   return DS.Color.primaryFill
        case .soft:   return DS.Color.cardBackgroundSoft
        case .reject: return DS.Color.error.opacity(DS.Opacity.tintFill)
        case .gold:   return DS.Color.accentLight
        case .glass:  return DS.Hub.glass
        }
    }
}

struct AdminPillButton: View {
    let title: String
    var icon: String? = nil
    var style: AdminPillStyle = .soft
    var height: CGFloat = DS.Hub.pillHeight
    var fullWidth: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AdminPillLabel(title: title, icon: icon, style: style, height: height, fullWidth: fullWidth)
                .dsTapArea(width: DS.Icon.tapTarget, height: height)
        }
        .buttonStyle(DSPressStyle())
    }
}

// MARK: صفوف

/// صفّ في بطاقة قسم: مربّع أيقونة + عنوان + وصف + طرف (عدد/شارة) + سهم — داخل `NavigationLink`
struct AdminListRow<Trailing: View>: View {
    let icon: String
    var tint: Color = DS.Color.primary
    let title: String
    var subtitle: String? = nil
    var showsChevron: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: icon, tint: tint)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.Spacing.xs)
            trailing()
            if showsChevron { DSChevron() }
        }
        .padding(.vertical, DS.Spacing.sm + 2)
        .frame(minHeight: DS.Icon.tapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension AdminListRow where Trailing == EmptyView {
    init(icon: String, tint: Color = DS.Color.primary, title: String, subtitle: String? = nil,
         showsChevron: Bool = true) {
        self.init(icon: icon, tint: tint, title: title, subtitle: subtitle, showsChevron: showsChevron,
                  trailing: { EmptyView() })
    }
}

/// شريط تقدّم رفيع (رصيد، نسبة الحسابات)
struct AdminMeter: View {
    /// ٠…١
    let progress: Double
    var tint: Color = DS.Color.warning

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Color.cardBackgroundSoft)
                Capsule().fill(tint)
                    .frame(width: max(DS.Hub.meterHeight, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: DS.Hub.meterHeight)
        .accessibilityHidden(true)
    }
}

/// شريط مراحل الطلب الخمس (تقديم ← مراجعة ← اعتماد ← تنفيذ ← مكتمل): المنجز ذهبي
struct AdminStageTrack: View {
    /// عدد المراحل المنجزة (١…٥)
    let done: Int
    var total: Int = 5

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < done ? DS.Color.accentLight : DS.Color.cardBackgroundSoft)
                    .frame(height: DS.Hub.trackHeight)
            }
        }
        .accessibilityHidden(true)
    }
}

/// منطقة شريط الحالة كحلية دائماً على جذر صفحات اللوحة — الرأس يتمرّر أو يثبت تحتها، ونص الوقت الأبيض يُقرأ
/// فوقها في كل حال. الارتفاع من المنطقة الآمنة للجذر (صفر أفقياً: لا شريط حالة)
private struct AdminStatusBarCover: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geo in
            content
                .frame(width: geo.size.width, height: geo.size.height)
                .overlay {
                    DS.Hub.bandTop
                        .frame(height: geo.safeAreaInsets.top)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
    }
}

/// تأثير حافة التمرير (iOS 26) يُخفى أعلى صفحات اللوحة — كان ضباباً فاتحاً تحت الوقت الأبيض
private struct AdminHideTopEdgeEffect: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}

extension View {
    /// على جذر صفحة اللوحة: منطقة شريط الحالة كحلية ثابتة
    func adminStatusBarCover() -> some View { modifier(AdminStatusBarCover()) }
    /// على تمرير صفحة اللوحة: بلا ضباب الحافة العليا
    func adminHideTopEdgeEffect() -> some View { modifier(AdminHideTopEdgeEffect()) }
}

// MARK: صفحة القسم

/// هيكل صفحة القسم: الرأس الكحلي ثم المحتوى المتمرّر على الأرضية الرملية — يُخفي شريط النظام
struct AdminHubPage<Header: View, Content: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    @Environment(\.dsLandscape) private var landscape

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header()
                VStack(spacing: DS.Hub.stackSpacing) {
                    content()
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Hub.stackSpacing)
                .padding(.bottom, DS.Spacing.xxxl)
                .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth)
                .dsTabBarClearance()
                .frame(maxWidth: .infinity)
                .background(DS.Hub.background)
            }
        }
        .adminHideTopEdgeEffect()
        .background(alignment: .top) {
            // السحب للأسفل فوق الرأس يكشف كحلياً لا رملياً
            DS.Hub.bandTop.frame(height: DS.Hub.ringSide).ignoresSafeArea(edges: .top)
        }
        .background(DS.Hub.background.ignoresSafeArea())
        .adminStatusBarCover()
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}

/// بطاقة صفوف قسم بعنوان — الصفوف مفصولة بخط رفيع
struct AdminRowsCard<Content: View>: View {
    var title: String? = nil
    var footnote: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                AdminCardHeader(title: title)
            }
            _VariadicView.Tree(AdminDividedLayout()) { content() }
            if let footnote {
                Text(footnote)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }
}

/// يضع فاصلاً رفيعاً بين أبناء البطاقة الظاهرين فقط
struct AdminDividedLayout: _VariadicView_UnaryViewRoot {
    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(alignment: .leading, spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != last { AdminRowDivider() }
            }
        }
    }
}
