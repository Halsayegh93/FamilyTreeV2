import SwiftUI

// MARK: - عُدّة لوحة الإدارة (إعادة التصميم ٢٠٢٦-١١-٢٦ — spec A.2–A.7، الوحدة U2)
//
// قطع مشتركة لصفحات الأقسام الستة وما تحتها: الرأس الكحلي المسطّح (رجوع ذهبي بالنص، العنوان، الوصف الذهبي، سطر الأرقام
// `AdminHeaderLine`)، الأزرار الزجاجية، البطاقة البيضاء بإطار رفيع بلا ظلّ، عنوان القسم، مربّع الأيقونة، الصفّ، حبّة الحالة
// (كلمة دائماً) وحبّة الإجراء، شريط المراحل. لا حلية ذهبية ولا تدرّج ولا صعود للبطاقة فوق الرأس.
// كل المقاسات والألوان من `DS.Hub` (DesignSystem.swift)؛ العقود (الهبوط، حال المخزن، عنصر سطر الرأس) في AdminContracts.swift.

// MARK: الأقسام

/// أقسام اللوحة بعد «اليوم» — الاسم والرمز ولون مربّعه وظهوره حسب الدور. ستة منذ ٢٠٢٦-١٠-٢٠ (اختيار المالك «٦ أقسام»).
/// `rawValue` ثابتة (مفاتيح جدول السيرفر): «الإحصاءات» اسم `metrics` منذ ٢٠٢٦-١١-٢٦ (كان «المؤشرات» — spec B.3).
enum AdminArea: String, CaseIterable, Identifiable, Hashable {
    case inbox, family, occasions, metrics, team, app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox:     return L10n.t("الوارد", "Inbox")
        case .family:    return L10n.t("العائلة", "Family")
        case .occasions: return L10n.t("المناسبات والإعلانات", "Occasions & announcements")
        case .metrics:   return L10n.t("الإحصاءات", "Statistics")
        case .team:      return L10n.t("الفريق والأمان", "Team & security")
        case .app:       return L10n.t("التطبيق", "App")
        }
    }

    /// الاسم على مربّعه في «اليوم» — سطر واحد فتتساوى المربّعات (طلب المالك ٢٠٢٦-١١-٢٦ «نصغر المربعات»)؛ الاسم الكامل للعنوان والقارئ الصوتي
    var tileTitle: String {
        switch self {
        case .occasions: return L10n.t("المناسبات", "Occasions")
        default:         return title
        }
    }

    var subtitle: String {
        switch self {
        case .inbox:     return L10n.t("الطلبات ورسائل الأعضاء", "Requests and member messages")
        case .family:    return L10n.t("الأعضاء وبياناتهم وحساباتهم", "Members, their details and accounts")
        case .occasions: return L10n.t("الوفيات والذكرى والمنشورات، والإعلان للأعضاء",
                                       "Deaths, memorials and posts, and announcing to members")
        case .metrics:   return L10n.t("أرقام العائلة والموافقات — للاطلاع", "Family and approval numbers — read only")
        case .team:      return L10n.t("من يدير، ومن يدخل التطبيق", "Who manages, and who signs in")
        case .app:       return L10n.t("إعدادات التطبيق والتشغيل", "App settings and operations")
        }
    }

    /// رمز القسم في مربّعه وقائمة العنوان (مثل النماذج: صندوق · شخصان · تقويم · أعمدة · درع · منزلقات)
    var icon: String {
        switch self {
        case .inbox:     return "tray.fill"
        case .family:    return "person.2.fill"
        case .occasions: return "calendar"
        case .metrics:   return "chart.bar.fill"
        case .team:      return "checkmark.shield.fill"
        case .app:       return "slider.horizontal.3"
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

    /// اسم «اليوم» كما يظهر في رأسه — زرّ الرجوع في صفحات الأقسام «‹ الإدارة» (spec C.2–C.14)
    static var homeTitle: String { L10n.t("الإدارة", "Admin") }

    /// يظهر هذا القسم لدور المشاهد — القسم الفارغ لدورك لا يُرسم. المصدر جدول «مين يشوف وش» من السيرفر
    /// (`AdminRoleMatrix` ← `app_config.admin_role_matrix`): المالكان كل شي، المدير كل شي عدا «التطبيق» و«الفريق والأمان»
    /// للاطلاع، المراقب الوارد والعائلة والمناسبات والإحصاءات للاطلاع، المشرف الوارد والمناسبات. كل مدخل لصفحات القسم يمرّ
    /// بهذا الشرط (`AdminAreaGate`)
    @MainActor
    func isVisible(for authVM: AuthViewModel) -> Bool {
        authVM.adminAccess(self).canSee
    }

    /// القسم للاطلاع فقط لهذا الدور («يشوف بس» في الجدول) — المربّع يحمل «للاطلاع» وأزرار التعديل تختفي
    /// (الأوامر: `authVM.adminCanEdit(area)` مضروبة مع صلاحية الدور — AdminContracts.swift)
    @MainActor
    func isReadOnly(for authVM: AuthViewModel) -> Bool {
        authVM.adminAccess(self) == .read
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
// يمرّر قسمه صراحةً (مثل `adminBackTitle`). بلا ناقل (قبل فتح تبويب الإدارة) أو بلا قسم: العنوان نصّ عادي.
// الهبوط (ما يفتح عليه القسم) في `AdminAreaRouter.landings` — AdminContracts.swift.

/// ناقل مكدس «اليوم» إلى صفحة قسم — يضبطه `AdminDashboardView` عند ظهوره (nil قبله). كل نقل عبره يمسح الهبوطات المنتظرة
/// أولاً (قائمة العنوان تفتح القسم على افتراضه)؛ «اليوم» يضع هبوط انتقاله بـ`land(_:hop:)` بعد ذلك.
@MainActor
enum AdminAreaRouter {
    static var navigate: ((AdminArea) -> Void)? {
        get { opener.map { open in { area in clearLandings(); open(area) } } }
        set { opener = newValue }
    }

    private static var opener: ((AdminArea) -> Void)?
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
    /// العدد بعد العنوان بالذهبي («العائلة ⌄ · 2719» في الرأس المطويّ) — nil = بلا عدد
    var count: String? = nil
    /// سطر الرأس المطويّ: العنوان بخط عنوان الصفحة لا عنوان الرأس الكبير
    var compact: Bool = false
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
            .accessibilityLabel(L10n.t("\(spokenTitle)، تبديل القسم", "\(spokenTitle), switch section"))
            .accessibilityHint(L10n.t("يعرض أقسام اللوحة", "Shows the dashboard sections"))
        } else {
            label(chevron: false)
        }
    }

    private var spokenTitle: String { count.map { "\(title) \($0)" } ?? title }

    private func label(chevron: Bool) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.xsm) {
            Text(title)
                .dsFont(compact ? .pageTitle : .hubTitle)
                .foregroundColor(DS.Color.headerTitle)
                .lineLimit(compact ? 1 : 2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: !compact)
            if chevron {
                Image(systemName: "chevron.down")
                    .dsGlyph(compact ? DS.Glyph.md : DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(DS.Color.accentLight)
                    .accessibilityHidden(true)
            }
            if let count {
                // النقطة والعدد نصّان منفصلان — نصّ واحد «· 2719» يقلب النقطة بعد العدد في العربية
                HStack(spacing: DS.Spacing.xs) {
                    Text(verbatim: "·")
                    Text(verbatim: count).monospacedDigit()
                }
                .dsFont(.hubRow)
                .foregroundColor(DS.Color.accentLight)
                .lineLimit(1)
                .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: الرأس الكحلي (spec A.3)

/// خلفية الرأس: كحلي مسطّح بلون رأس «اليوم» نفسه (`DSHeaderBackground(section: .admin)` — طلب المالك ٢٠٢٦-١١-٠٢ «ليش الهيدرات
/// أقسام الادارة مو نفس لوحة الادارة»). لا تدرّج ولا حلقة ذهبية (spec A.3/E.5)
struct AdminBandBackground: View {
    var body: some View {
        DSHeaderBackground(section: .admin)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// خلفية الرأس الكحلي تحت المحتوى (وأفقياً تحت النوتش وطرف الشاشة). منطقة شريط الحالة فوقه يغطّيها
    /// `adminStatusBarCover()` على جذر الصفحة بنفس الكحلي — فيلتقيان بلا خطّ
    func adminBandBackground(landscape: Bool) -> some View {
        background(AdminBandBackground().ignoresSafeArea(edges: landscape ? .horizontal : []))
    }
}

/// مقاسات هيكل صفحة القسم التي لا تخصّ غيرها
enum AdminHubMetrics {
    /// لون الرأس خلف أعلى التمرير — السحب للتحديث يكشف كحلياً لا أبيض (نفس «اليوم»)
    static let pullReveal: CGFloat = 260
}

/// دائرة زجاجية في الرأس (بحث، ⚙︎، ⋯…): ٣٦ مرسومة ولمسها ٤٤ — اسم الرمز، ونقطة «جديد» أو عدد اختياريان
struct AdminGlassCircle: View {
    let symbol: String
    var dot: Bool = false
    /// عدد أحمر على الركن بدل النقطة (٠ = لا شيء)
    var count: Int = 0

    var body: some View {
        Image(dsSymbol: symbol)
            .dsGlyph(DS.Glyph.xl, weight: .medium)
            .foregroundStyle(DS.Color.headerGlyph)
            .frame(width: DS.Hub.glassButton, height: DS.Hub.glassButton)
            .background(Circle().fill(DS.Hub.glass))
            .overlay(Circle().strokeBorder(DS.Hub.glassLine, lineWidth: DS.Border.width))
            .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text(verbatim: count > 99 ? "99+" : "\(count)")
                        .dsFont(.badge)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textOnPrimary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, DS.Spacing.xs)
                        .frame(minWidth: DS.Hub.bellBadge, minHeight: DS.Hub.bellBadge)
                        .background(Capsule().fill(DS.Color.errorFill))
                        .overlay(Capsule().strokeBorder(DS.Color.bandFill, lineWidth: DS.Border.widthBold))
                        .accessibilityHidden(true)
                } else if dot {
                    Circle()
                        .fill(DS.Color.errorFill)
                        .frame(width: DS.Hub.bellDotSize, height: DS.Hub.bellDotSize)
                        .overlay(Circle().strokeBorder(DS.Color.bandFill, lineWidth: DS.Border.width))
                        .padding(DS.Spacing.xsm)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
    }
}

/// زرّ دائري زجاجي بإجراء — في الرأس زرّان على الأكثر (spec A.3)
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

/// زرّ نصّي في طرف الرأس («تحديد») — أبيض ١٥، لمسه ٤٤ (spec A.3: بدل الدائرتين)
struct AdminHeaderTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .dsFont(.body)
                .foregroundColor(DS.Color.headerTitle)
                .lineLimit(1)
                .padding(.horizontal, DS.Spacing.xsm)
                .frame(minWidth: DS.Icon.tapTarget, minHeight: DS.Icon.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
    }
}

/// زرّ الرجوع: سهم + اسم ما فُتحت منه الصفحة بالذهبي، ١٥، لمسه ٤٤ («‹ الإدارة» — spec A.3)
struct AdminBackLink: View {
    var title: String = AdminArea.homeTitle
    /// false = السهم وحده (السطر المطويّ في «العائلة»)
    var showsTitle: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xsm) {
                Image(systemName: DSBackButton.symbol)
                    .dsGlyph(DS.Glyph.md, weight: .semibold)
                if showsTitle {
                    Text(title)
                        .dsFont(.body)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .foregroundColor(DS.Color.accentLight)
            .frame(minWidth: DS.Icon.tapTarget, minHeight: DS.Icon.tapTarget,
                   alignment: showsTitle ? .leading : .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(L10n.t("رجوع إلى \(title)", "Back to \(title)"))
    }
}

/// أعلى الرأس (spec A.3): رجوع ذهبي في سطره ← العنوان وفي طرفه زرّان على الأكثر ← سطر الوصف الذهبي (١٣).
/// ما يخصّ الصفحة (سطر الأرقام، الحقول) يأتي تحته
struct AdminHeaderLead<Title: View, Trailing: View>: View {
    var backTitle: String?
    var onBack: (() -> Void)?
    var subtitle: String?
    let title: () -> Title
    let trailing: () -> Trailing

    init(backTitle: String? = nil, onBack: (() -> Void)? = nil, subtitle: String? = nil,
         @ViewBuilder title: @escaping () -> Title, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.backTitle = backTitle
        self.onBack = onBack
        self.subtitle = subtitle
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onBack, let backTitle {
                AdminBackLink(title: backTitle, action: onBack)
            }
            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                title()
                Spacer(minLength: DS.Spacing.xs)
                HStack(spacing: 0) { trailing() }
            }
            .frame(minHeight: DS.Icon.tapTarget)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.accentLight)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// سطر ذهبي صغير فوق الرأس برمزه («للاطلاع فقط — التعديل للمالك» بقفل — spec A.3). كان شارة كبسولة
struct AdminBandChip: View {
    let text: String
    var icon: String? = nil
    var tint: Color = DS.Color.accentLight

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xsm) {
            if let icon {
                Image(dsSymbol: icon).dsGlyph(DS.Glyph.sm, weight: .medium)
            }
            Text(text)
                .dsFont(.subtitle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(tint)
        .padding(.vertical, DS.Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

/// رأس صفحة القسم (spec A.3): «‹ الإدارة» ← العنوان (قائمة الأقسام في جذر القسم) + زرّان ← الوصف ← سطر «للاطلاع» ←
/// سطر الأرقام (`items`) ← ملحق اختياري (حقل بحث، أزرار الصفحة). كحلي مسطّح، يلتفّ على محتواه
struct AdminBandHeader<Buttons: View, Accessory: View>: View {
    var backTitle: String? = AdminArea.homeTitle
    let title: String
    var subtitle: String? = nil
    /// سطر «للاطلاع» بقفل (`AdminPageHeader.readOnlyText`)
    var badge: String? = nil
    /// nil = حسب المحتوى: `DS.Hub.headerBottom`، أو `headerBottomLine` تحت سطر الأرقام
    var bottomPadding: CGFloat? = nil
    /// صفحة القسم نفسها (لا داخلية) — العنوان قائمة الأقسام
    var isAreaRoot: Bool = false
    /// سطر أرقام الرأس (`AdminHeaderLine`) — فارغ = بلا سطر
    var items: [AdminHeaderItem] = []
    @ViewBuilder var buttons: () -> Buttons
    @ViewBuilder var accessory: () -> Accessory
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dsLandscape) private var landscape
    /// اسم الصفحة التي فُتحت منها (إن مرّره من دفعها) — يغلب «الإدارة» الافتراضي
    @Environment(\.adminBackTitle) private var outerBack

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AdminHeaderLead(backTitle: backTitle.map { outerBack ?? $0 },
                            onBack: backTitle == nil ? nil : { dismiss() },
                            subtitle: subtitle) {
                // صفحة القسم: العنوان قائمة الأقسام (خلف `AnyView` — حارس المكدس)
                if isAreaRoot {
                    AnyView(AdminAreaTitleMenu(title: title))
                } else {
                    Text(title)
                        .dsFont(.hubTitle)
                        .foregroundColor(DS.Color.headerTitle)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
            } trailing: {
                buttons()
            }
            if let badge {
                AdminBandChip(text: badge, icon: "lock.fill")
            }
            if !items.isEmpty {
                AnyView(AdminHeaderLine(items: items))
            }
            accessory()
        }
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth - 2 * DS.Spacing.lg)
        .padding(.horizontal, landscape ? DS.Spacing.xxl : DS.Spacing.lg)
        .padding(.top, DS.Hub.headerTop)
        .padding(.bottom, bottomPadding ?? (items.isEmpty ? DS.Hub.headerBottom : DS.Hub.headerBottomLine))
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminBandBackground(landscape: landscape)
        .dsLightStatusBar()
    }
}

extension AdminBandHeader where Accessory == EmptyView {
    init(backTitle: String? = AdminArea.homeTitle, title: String, subtitle: String? = nil,
         badge: String? = nil, bottomPadding: CGFloat? = nil, isAreaRoot: Bool = false,
         items: [AdminHeaderItem] = [], @ViewBuilder buttons: @escaping () -> Buttons) {
        self.init(backTitle: backTitle, title: title, subtitle: subtitle, badge: badge,
                  bottomPadding: bottomPadding, isAreaRoot: isAreaRoot, items: items, buttons: buttons,
                  accessory: { EmptyView() })
    }
}

extension AdminBandHeader where Buttons == EmptyView, Accessory == EmptyView {
    init(backTitle: String? = AdminArea.homeTitle, title: String, subtitle: String? = nil,
         badge: String? = nil, bottomPadding: CGFloat? = nil, isAreaRoot: Bool = false,
         items: [AdminHeaderItem] = []) {
        self.init(backTitle: backTitle, title: title, subtitle: subtitle, badge: badge,
                  bottomPadding: bottomPadding, isAreaRoot: isAreaRoot, items: items, buttons: { EmptyView() },
                  accessory: { EmptyView() })
    }
}

// MARK: سطر أرقام الرأس (spec A.3 البند ٤ — NEW، بدل مربّعات الأرقام الزجاجية)

/// صفّ يلتفّ من عناصر `[رقم ١٥ أبيض][اسم ١٣ ذهبي][سهم ذهبي إن فتح شيئاً]`، ١٨ بين العناصر وكل عنصر ٤٤ طولاً.
/// الصفر والتحميل باهتان (`DS.Hub.lineZero`) ولا يفتحان شيئاً؛ الفشل «—» برمز إعادة المحاولة؛ القديم يبقى رقمه ويُضاف
/// «آخر تحديث 9:12» آخر السطر. المرفوض لدورك لا يُرسم (`AdminHeaderItemLook` — AdminContracts.swift)
struct AdminHeaderLine: View {
    let items: [AdminHeaderItem]

    private struct Row: Identifiable {
        let item: AdminHeaderItem
        let look: AdminHeaderItemLook
        var id: String { item.id }
    }

    var body: some View {
        let rows = items.map { Row(item: $0, look: $0.look) }.filter { !$0.look.hidden }
        let stale = rows.compactMap(\.look.staleSince).min()
        AdminHeaderLineLayout(spacing: DS.Hub.headerLineGap) {
            ForEach(rows) { row in
                AdminHeaderLineItem(item: row.item, look: row.look)
            }
            if let stale {
                Text(AdminStoreHealthText.updated(stale))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Hub.lineZero)
                    .frame(minHeight: DS.Icon.tapTarget)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// عنصر واحد في سطر الرأس
private struct AdminHeaderLineItem: View {
    let item: AdminHeaderItem
    let look: AdminHeaderItemLook

    var body: some View {
        if look.retry, let retry = item.retry {
            Button(action: retry) { face }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel(L10n.t("\(item.label): \(AdminStoreHealthText.failed)",
                                           "\(item.label): \(AdminStoreHealthText.failed)"))
                .accessibilityHint(AdminStoreHealthText.retry)
        } else if look.opens {
            AdminTapWrap(tap: item.tap, feel: .press, label: AnyView(face), accessibilityLabel: spoken)
                .accessibilityHint(L10n.t("يفتح القائمة", "Opens the list"))
        } else {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
        }
    }

    /// «5 بانتظار قرارك» — أو حال التحميل/الفشل بالكلمات (رقم بلا اسم لا يُقرأ وحده)
    private var spoken: String {
        if look.retry { return L10n.t("\(item.label): \(AdminStoreHealthText.failed)",
                                      "\(item.label): \(AdminStoreHealthText.failed)") }
        if look.text == AdminStoreHealthText.placeholder {
            return L10n.t("\(item.label): \(AdminStoreHealthText.loading)", "\(item.label): \(AdminStoreHealthText.loading)")
        }
        if let spoken = item.spoken { return spoken }
        let base = "\(look.text) \(item.label)"
        guard let since = look.staleSince else { return base }
        let stamp = AdminStoreHealthText.updated(since)
        return L10n.t("\(base)، \(stamp)", "\(base), \(stamp)")
    }

    private var face: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xsm) {
            Text(verbatim: look.text)
                .dsFont(.hubLineNumber)
                .monospacedDigit()
                .foregroundColor(item.emphasis ? DS.Hub.inboxReviewInk : (look.dim ? DS.Hub.lineZero : DS.Color.headerTitle))
                .lineLimit(1)
            Text(item.label)
                .dsFont(item.emphasis ? .chip : .subtitle)
                .foregroundColor(item.emphasis ? DS.Hub.inboxReviewInk : (look.dim ? DS.Hub.lineZero : DS.Color.accentLight))
                .fixedSize(horizontal: false, vertical: true)
            if look.retry {
                Image(systemName: "arrow.clockwise")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(DS.Color.accentLight)
            } else if look.opens {
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(DS.Color.accentLight)
            }
        }
        .frame(minHeight: DS.Icon.tapTarget)
        .contentShape(Rectangle())
    }
}

/// صفّ يلتفّ: فراغ ثابت بين العناصر في السطر، وبلا فراغ بين السطور (كل عنصر ٤٤ طولاً). العنصر الأعرض من السطر يلتفّ
/// نصّه داخله. يُقلب تلقائياً من اليمين لليسار
struct AdminHeaderLineLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(ProposedViewSize(width: maxW.isFinite ? maxW : nil, height: nil))
            if x > 0, x + s.width > maxW { y += line; x = 0; line = 0 }
            widest = max(widest, x + s.width)
            x += s.width + spacing
            line = max(line, s.height)
        }
        return CGSize(width: maxW.isFinite ? maxW : widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + s.width > bounds.maxX { y += line; x = bounds.minX; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: s.width, height: s.height))
            x += s.width + spacing
            line = max(line, s.height)
        }
    }
}

/// شريحة فلتر فوق الرأس الكحلي (spec A.9): تُرسم ٣٦ ولمسها ٤٤، ١٣. المختارة ذهبية بعلامة ✓ (الذهبي على الكحلي فقط)،
/// والباقية زجاجية وعددها ذهبي. فلتر فقط — لا تنقّل
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
                if selected {
                    Image(systemName: "checkmark").dsGlyph(DS.Glyph.sm, weight: .semibold)
                } else if let icon {
                    Image(dsSymbol: icon)
                        .dsGlyph(DS.Glyph.sm)
                        .foregroundColor(iconTint)
                }
                Text(title).dsFont(.chip)
                if let count {
                    Text(verbatim: AdminNumberText.grouped(count))
                        .dsFont(.chip)
                        .monospacedDigit()
                        .foregroundColor(selected ? DS.Hub.onGold : DS.Color.accentLight)
                }
            }
            .lineLimit(1)
            .foregroundColor(selected ? DS.Hub.onGold : DS.Color.textOnPrimary)
            .padding(.horizontal, DS.Spacing.md)
            .frame(minHeight: DS.Hub.filterChipHeight)
            .background(Capsule().fill(selected ? DS.Color.accentLight : DS.Hub.glass))
            .overlay(Capsule().strokeBorder(selected ? Color.clear : DS.Hub.glassLine, lineWidth: DS.Border.width))
            .dsTapArea(width: DS.Icon.tapTarget, height: DS.Hub.filterChipHeight)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(count.map { "\(title) \($0)" } ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: البطاقة (spec A.5)

extension View {
    /// بطاقة اللوحة: أبيض `cardBackground`، إطار ١ رفيع بارد (`DS.Hub.cardStroke`)، زاوية ١٢، **بلا ظلّ ولا جلد مجسّم**،
    /// حشوة ١٤. `framed` = بطاقة الحالة (إطار يُرى `DS.Hub.frameStroke`). لا بطاقة داخل بطاقة
    func adminCard(padding: CGFloat? = DS.Hub.cardPadding, framed: Bool = false) -> some View {
        modifier(AdminCardSurface(padding: padding, stroke: framed ? DS.Hub.frameStroke : DS.Hub.cardStroke))
    }
}

private struct AdminCardSurface: ViewModifier {
    let padding: CGFloat?
    let stroke: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous)
        return content
            .padding(padding ?? 0)
            .background(shape.fill(DS.Color.cardBackground))
            .overlay(shape.strokeBorder(stroke, lineWidth: DS.Card.strokeWidth))
    }
}

/// عنوان داخل البطاقة: العنوان ١٥ شبه عريض + شارة عدد اختيارية + رابط في الطرف (spec A.4)
struct AdminCardHeader<Trailing: View>: View {
    let title: String
    var badge: Int? = nil
    var badgeTint: Color = DS.Color.warning
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xsm) {
                Text(title)
                    .dsFont(.hubSection)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
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

/// شارة العدد بجانب العنوان: كبسولة بلون المعنى ١٢٪ ونصّ ١٣ (لا أقل من ١٣ — spec A.17/T6)
struct AdminCountBadge: View {
    let count: Int
    var tint: Color = DS.Color.warning

    var body: some View {
        let ink = tint.dsReadableGlyph
        Text(verbatim: count > 99 ? "99+" : "\(count)")
            .dsFont(.chip)
            .monospacedDigit()
            .foregroundColor(ink)
            .padding(.horizontal, DS.Spacing.xsm)
            .frame(minWidth: DS.Icon.section, minHeight: DS.Icon.section)
            .background(Capsule().fill(ink.opacity(DS.Opacity.tintFill)))
    }
}

/// رابط نصّي في طرف العنوان («عرض الكل ‹»، «الإحصاءات ‹») — ١٥ كحلي بسهمه، لمسه ٤٤ (spec A.4)
struct AdminCardLinkLabel: View {
    let title: String
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: DS.Spacing.xsm) {
            Text(title)
                .dsFont(.body)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if showsChevron {
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
            }
        }
        .foregroundColor(DS.Color.primary)
        .frame(minHeight: DS.Icon.tapTarget)
        .contentShape(Rectangle())
    }
}

/// فاصل الصفوف داخل البطاقة — خطّ رفيع يبدأ من النص لا من حافة البطاقة (spec A.5)
struct AdminRowDivider: View {
    /// من أين يبدأ: ٠ لصفوف بلا أيقونة، `AdminRowDivider.iconInset` بعد مربّع الأيقونة (٣٠ + ١٢)
    var inset: CGFloat = 0

    static let iconInset: CGFloat = DS.Hub.iconSquare + DS.Spacing.md

    var body: some View {
        Rectangle()
            .fill(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke * 2))
            .frame(height: DS.Border.width / 2)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

/// شبكة المربّعات (الأقسام، «نبض العائلة»): عمودان عمودياً، وأعمدة متكيّفة أفقياً
enum AdminGrid {
    static let spacing: CGFloat = DS.Spacing.smd

    static func columns(landscape: Bool) -> [GridItem] {
        landscape
            ? [GridItem(.adaptive(minimum: DS.Landscape.tileMinWidth), spacing: spacing)]
            : [GridItem(.flexible(), spacing: spacing), GridItem(.flexible(), spacing: spacing)]
    }
}

/// عنوان قسم فوق بطاقته (spec A.4): ١٥ شبه عريض بالحبر، وفي الطرف ملاحظة ١٣ رمادية أو رابط نصّي واحد. لا أيقونة ولا
/// شريط تحته. ٨ بينه وبين بطاقته (`DS.Hub.sectionHeadingGap` — من يضعهما)
struct AdminSectionLabel: View {
    let title: String
    /// ملاحظة رمادية في الطرف («الحلقة = نسبة الأحياء»، «هذا الأسبوع»)
    var trailing: String? = nil
    /// رابط نصّي في الطرف (`AdminCardLinkLabel` داخل زرّ أو `NavigationLink`) — بدل الملاحظة
    var link: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
            Text(title)
                .dsFont(.hubSection)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let link {
                link
            } else if let trailing {
                Text(trailing)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, DS.Spacing.xxs)
    }
}

// MARK: مربّع الأيقونة (spec A.6)

/// مربّع أيقونة ٣٠ بزاوية ٨: ممتلئ (تعبئة العائلة ورمز أبيض — صفوف الإعدادات والمعلومات) أو خفيف (لون المعنى ١٢٪ ورمز
/// بلونه — صفّ الحذف `error`)
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
            .dsGlyph(glyph, weight: .medium)
            .foregroundColor(filled ? DS.Color.textOnPrimary : ink)
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(filled ? tint.dsSolidFill : ink.opacity(DS.Opacity.tintFill)))
            .accessibilityHidden(true)
    }
}

// MARK: الحبّات (spec A.7)

/// حبّة الإجراء (تنفّذ أمراً): كحلية ممتلئة («إعلان»)، بإطار («بطاقة»، «تعديل» — كانت رملية)، رفض بإطار أحمر («إلغاء
/// الموعد»، «إيقاف»)، ذهبية (على الكحلي فقط: «＋ إنشاء»)، زجاجية فوق الرأس
enum AdminPillStyle {
    case navy, soft, reject, gold, glass
}

/// وجه حبّة الإجراء: تُرسم ٣٤ (`DS.Hub.pillHeight`)، ١٣ متوسط
struct AdminPillLabel: View {
    let title: String
    var icon: String? = nil
    var style: AdminPillStyle = .soft
    var height: CGFloat = DS.Hub.pillHeight
    var fullWidth: Bool = false
    /// الرمز بعد النص («حي ✓») بدل قبله
    var iconTrailing: Bool = false

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            if let icon, !iconTrailing {
                Image(dsSymbol: icon).dsGlyph(DS.Glyph.sm, weight: .semibold)
            }
            Text(title)
                .dsFont(.hubButton)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let icon, iconTrailing {
                Image(dsSymbol: icon).dsGlyph(DS.Glyph.sm, weight: .semibold)
            }
        }
        .foregroundColor(ink)
        .padding(.horizontal, DS.Hub.pillPadding)
        .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(stroke, lineWidth: DS.Border.width))
    }

    private var ink: Color {
        switch style {
        case .navy:   return DS.Color.textOnPrimary
        case .soft:   return DS.Color.primary
        case .reject: return DS.Color.error
        case .gold:   return DS.Hub.onGold
        case .glass:  return DS.Color.textOnPrimary
        }
    }

    private var fill: Color {
        switch style {
        case .navy:   return DS.Color.primaryFill
        case .soft:   return DS.Color.cardBackground
        case .reject: return DS.Color.cardBackground
        case .gold:   return DS.Color.accentLight
        case .glass:  return DS.Hub.glass
        }
    }

    private var stroke: Color {
        switch style {
        case .soft:   return DS.Hub.frameStroke
        case .reject: return DS.Color.error.opacity(DS.Opacity.tintStroke)
        case .glass:  return DS.Hub.glassLine
        case .navy, .gold: return Color.clear
        }
    }
}

/// حبّة إجراء: تُرسم ٣٤ ولمسها ٤٤. حبّتان متجاورتان داخل `AdminPillRow` (١٢ بينهما فلا يتداخل لمسهما — spec A.7/T6)
struct AdminPillButton: View {
    let title: String
    var icon: String? = nil
    var style: AdminPillStyle = .soft
    var height: CGFloat = DS.Hub.pillHeight
    var fullWidth: Bool = false
    var iconTrailing: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AdminPillLabel(title: title, icon: icon, style: style, height: height, fullWidth: fullWidth, iconTrailing: iconTrailing)
                .dsTapArea(width: DS.Icon.tapTarget, height: height)
        }
        .buttonStyle(DSPressStyle())
    }
}

/// حبّات إجراء متجاورة: ١٢ بينها (`DS.Hub.actingPillGap`) فيبقى لمس كلٍّ منها ٤٤ بلا تداخل — spec A.7/T6
struct AdminPillRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: DS.Hub.actingPillGap) { content() }
    }
}

/// نغمة حبّة الحالة — كلمة دائماً، لا لون وحده (spec A.7/A.12)
enum AdminPillTone: Hashable {
    /// «يعمل» ✓، «مسموح»، «93٪»
    case ok
    /// «مطفأ»، «اختياري»
    case off
    /// «منخفض»، «شيئان يحتاجانك»
    case warn
    /// «مفعّل»، «متوقف للأعضاء»، «3 جديدة»
    case error
    /// المخزن لم يُحمَّل: «تعذّر التحميل» ↻ — لا كلمة هادئة
    case unknown

    var ink: Color {
        switch self {
        case .ok:            return DS.Color.success
        case .off, .unknown: return DS.Color.textSecondary
        case .warn:          return DS.Color.warning
        case .error:         return DS.Color.error
        }
    }

    var fill: Color {
        switch self {
        case .ok:            return DS.Color.success.opacity(DS.Opacity.tintFill)
        case .off, .unknown: return DS.Color.textTertiary.opacity(DS.Opacity.tintFill)
        case .warn:          return DS.Color.warning.opacity(DS.Opacity.tintFill)
        case .error:         return DS.Color.error.opacity(DS.Opacity.tintFill)
        }
    }
}

/// حبّة الحالة (spec A.7): كبسولة ١٣ متوسط، حشوة ٦ × ١١، كلمة بلونها على ١٢٪ منه. داخل صفّ يُضغط هي جزء منه (لمسة واحدة).
/// بحال مخزنها (`health:`): التحميل حبّة رمادية «—»، الفشل بلا بيانات «تعذّر التحميل» ↻ (والضغط يعيد جلب مخزنها وحده إن
/// مُرّر `retry`)، القديم كلمته + «آخر تحديث» للقارئ الصوتي، المرفوض لا شيء
struct AdminStatePill: View {
    let title: String
    var tone: AdminPillTone = .off
    var icon: String? = nil
    /// يعمل؟ (حبّة تغيّر شيئاً — `AdminStatePillButton`): دوّارة صغيرة داخل الحبّة
    var isBusy: Bool = false
    private var health: AdminStoreHealth? = nil
    private var retry: (() -> Void)? = nil

    init(title: String, tone: AdminPillTone = .off, icon: String? = nil, isBusy: Bool = false) {
        self.title = title
        self.tone = tone
        self.icon = icon
        self.isBusy = isBusy
    }

    /// الكلمة بعد وصول بياناتها فقط
    init(health: AdminStoreHealth, title: String, tone: AdminPillTone, icon: String? = nil,
         retry: (() -> Void)? = nil) {
        self.title = title
        self.tone = tone
        self.icon = icon
        self.health = health
        self.retry = retry
    }

    var body: some View {
        switch health?.look ?? .word {
        case .hidden:
            EmptyView()
        case .skeleton:
            face(title: AdminStoreHealthText.placeholder, tone: .off, icon: nil)
                .accessibilityLabel(AdminStoreHealthText.loading)
        case .unknown:
            if let retry {
                Button(action: retry) { unknownFace }
                    .buttonStyle(DSPressStyle())
                    .dsTapArea(width: DS.Icon.tapTarget, height: DS.Hub.filterChipHeight)
                    .accessibilityHint(AdminStoreHealthText.retry)
            } else {
                unknownFace
            }
        case .staleWord(let since):
            face(title: title, tone: tone, icon: icon)
                .accessibilityLabel(L10n.t("\(title)، \(AdminStoreHealthText.updated(since))",
                                           "\(title), \(AdminStoreHealthText.updated(since))"))
        case .word:
            face(title: title, tone: tone, icon: icon)
        }
    }

    private var unknownFace: some View {
        face(title: AdminStoreHealthText.failed, tone: .unknown, icon: "arrow.clockwise")
    }

    private func face(title: String, tone: AdminPillTone, icon: String?) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            if isBusy {
                ProgressView()
                    .scaleEffect(DS.Spinner.chipScale)
                    .tint(tone.ink)
            } else if let icon {
                Image(dsSymbol: icon).dsGlyph(DS.Glyph.sm, weight: .semibold)
            }
            Text(title)
                .dsFont(.chip)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundColor(tone.ink)
        .padding(.vertical, DS.Hub.statePillPaddingV)
        .padding(.horizontal, DS.Hub.statePillPaddingH)
        .background(Capsule().fill(tone.fill))
        .accessibilityElement(children: .combine)
    }
}

/// حبّة حالة تغيّر شيئاً حين تُضغط (الصيانة، إشعارات الجوال في «التطبيق» — «ب» المالك): لمسها ٤٤، سمة الزرّ، وتلميح
/// «يسأل قبل التغيير» (التأكيد عند من يستعملها — spec A.14). أثناء الحفظ دوّارة صغيرة داخلها ومعطّلة
struct AdminStatePillButton: View {
    let title: String
    var tone: AdminPillTone = .off
    var icon: String? = nil
    var isBusy: Bool = false
    /// «يسأل قبل التغيير» — false لما لا يسأل (إطفاء الصيانة، إعادة الإشعارات)
    var asksFirst: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AdminStatePill(title: title, tone: tone, icon: icon, isBusy: isBusy)
                .dsTapArea(width: DS.Icon.tapTarget, height: DS.Hub.filterChipHeight)
        }
        .buttonStyle(DSPressStyle())
        .disabled(isBusy)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(asksFirst ? L10n.t("يسأل قبل التغيير", "Asks before changing") : "")
    }
}

/// «آخر تحديث 9:12» — ١٣ رمادي، تحت ما يعرض أرقاماً قديمة بعد فشل التحديث (spec A.2/A.12)
struct AdminStaleStamp: View {
    let since: Date

    var body: some View {
        Text(AdminStoreHealthText.updated(since))
            .dsFont(.subtitle)
            .foregroundColor(DS.Color.textTertiary)
    }
}

// MARK: الصفوف (spec A.6)

/// ضغطة الصفّ: تظليل لا تصغير (`DS.Hub.rowPress`، ١٠٠ م.ث). `bleed` = يمتدّ التظليل حتى حافة البطاقة (حشوتها)
struct AdminRowPressStyle: ButtonStyle {
    var bleed: CGFloat = DS.Hub.cardPadding

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Rectangle()
                    .fill(DS.Hub.rowPress.opacity(configuration.isPressed ? 1 : 0))
                    .padding(.horizontal, -bleed)
            )
            .animation(DS.Hub.rowPressAnimation, value: configuration.isPressed)
    }
}

/// صفّ في بطاقة (spec A.6): `[مربّع ٣٠ ممتلئ بلون العائلة][عنوان ١٥ / وصف ١٣ رمادي سطران]…[الطرف][سهم إن فتح شيئاً]`.
/// ٤٤ لسطر و٥٦ لسطرين. صفّ الحذف (`destructive`): العنوان أحمر والمربّع رمز أحمر على ١٢٪، آخر بطاقته ويسأل أولاً.
/// داخل `NavigationLink`/زرّ بـ`AdminRowPressStyle`
struct AdminListRow<Trailing: View>: View {
    let icon: String
    var tint: Color = DS.Color.primary
    let title: String
    var subtitle: String? = nil
    var showsChevron: Bool = true
    var destructive: Bool = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        let twoLines = subtitle.map { !$0.isEmpty } ?? false
        HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: icon, tint: destructive ? DS.Color.error : tint, filled: !destructive)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.body)
                    .foregroundColor(destructive ? DS.Color.error : DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.Spacing.xs)
            trailing()
            if showsChevron { DSChevron() }
        }
        .padding(.vertical, DS.Spacing.xsm)
        .frame(minHeight: twoLines ? DS.Hub.rowMinHeightTwoLines : DS.Hub.rowMinHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension AdminListRow where Trailing == EmptyView {
    init(icon: String, tint: Color = DS.Color.primary, title: String, subtitle: String? = nil,
         showsChevron: Bool = true, destructive: Bool = false) {
        self.init(icon: icon, tint: tint, title: title, subtitle: subtitle, showsChevron: showsChevron,
                  destructive: destructive, trailing: { EmptyView() })
    }
}

/// شريط تقدّم (٠…١) — غلاف للشريط الموحّد `DSMeterBar` (الصفحات الجديدة تستعمل `DSMeterBar` مباشرة)
struct AdminMeter: View {
    /// ٠…١
    let progress: Double
    var tint: Color = DS.Color.warning

    var body: some View {
        DSMeterBar(progress: progress, tint: tint)
    }
}

/// شريط مراحل الطلب: المنجز كحلي ممتلئ، والباقي مسار الحبر الفاتح (spec A.11)
struct AdminStageTrack: View {
    /// عدد المراحل المنجزة (١…`total`)
    let done: Int
    var total: Int = 5

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < done ? DS.Color.primaryFill : DS.Chart.inkTrack)
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
                    AdminBandBackground()
                        .frame(height: geo.safeAreaInsets.top)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea()
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

// MARK: صفحة القسم (spec A.2)

/// هيكل صفحة القسم: الرأس الكحلي ثم الأقسام على الأبيض — ١٦ تحت الرأس، ٢٤ بين الأقسام، ٢٤ آخرها فوق شريط التبويبات.
/// يُخفي شريط النظام
struct AdminHubPage<Header: View, Content: View>: View {
    /// طبقة مثبّتة أعلى الصفحة فوق التمرير (الرأس المطويّ في «العائلة») — nil = بلا شيء
    var pinned: AnyView? = nil
    /// كل تغيّر فيه يرجع التمرير لأعلى الصفحة (بحركة، وبلا حركة مع «تقليل الحركة»)
    var topToken: Int = 0
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    @Environment(\.dsLandscape) private var landscape
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// «ظهور موحّد»: كل قسم يصعد تباعاً مرة عند الظهور الأول فقط — لا عند التحديث (`dsCardCascade`)
    @State private var appeared = false

    var body: some View {
        ScrollViewReader { proxy in
            scroll
                .onChange(of: topToken) { _ in
                    if reduceMotion {
                        proxy.scrollTo(AdminHubScroll.top, anchor: .top)
                    } else {
                        withAnimation(DS.Anim.smooth) { proxy.scrollTo(AdminHubScroll.top, anchor: .top) }
                    }
                }
        }
        .adminHideTopEdgeEffect()
        .overlay(alignment: .top) { pinned }
        .background(alignment: .top) {
            // السحب للأسفل فوق الرأس يكشف كحلياً لا أبيض
            AdminBandBackground().frame(height: AdminHubMetrics.pullReveal).ignoresSafeArea(edges: .top)
        }
        .background(DS.Hub.background.ignoresSafeArea())
        .adminStatusBarCover()
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear { appeared = true }
    }

    private var scroll: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header()
                    .id(AdminHubScroll.top)
                _VariadicView.Tree(AdminCascadeLayout(appeared: appeared)) {
                    content()
                }
                .dsPageMargin()
                .padding(.top, DS.Spacing.lg)
                .padding(.bottom, DS.Hub.pageBottom)
                .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth)
                .dsTabBarClearance()
                .frame(maxWidth: .infinity)
                .background(DS.Hub.background)
            }
        }
        // ما يقيس موضعه داخل التمرير (الرأس المطويّ) يقيس بهذه المساحة: ٠ = أعلى المنطقة الظاهرة
        .coordinateSpace(name: AdminHubScroll.space)
    }
}

/// مفاتيح تمرير صفحة القسم: أعلى الصفحة، ومساحة الإحداثيات التي يقيس بها الرأس موضعه (بديل iOS 16 لـ`onScrollGeometryChange`)
enum AdminHubScroll {
    static let top = "adminHubTop"
    static let space = "adminHubScroll"
}

/// عمود أقسام الصفحة: ٢٤ بين قسم وقسم (`DS.Hub.sectionGap`)، وكل ابن يصعد ويظهر تباعاً (`dsCardCascade` بترتيبه —
/// أول ٧ والباقي مع السابع). العنوان وبطاقته ابن واحد (٨ بينهما)
struct AdminCascadeLayout: _VariadicView_UnaryViewRoot {
    let appeared: Bool

    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        VStack(spacing: DS.Hub.sectionGap) {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                child.dsCardCascade(index, appeared: appeared)
            }
        }
    }
}

/// بطاقة صفوف بعنوان — الصفوف مفصولة بخط رفيع يبدأ من النص (`dividerInset`)
struct AdminRowsCard<Content: View>: View {
    var title: String? = nil
    var footnote: String? = nil
    /// بداية الفاصل: ٠، أو `AdminRowDivider.iconInset` لصفوف بأيقونة
    var dividerInset: CGFloat = 0
    /// بطاقة الحالة (إطار يُرى)
    var framed: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                AdminCardHeader(title: title)
            }
            _VariadicView.Tree(AdminDividedLayout(inset: dividerInset)) { content() }
            if let footnote {
                Text(footnote)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard(framed: framed)
    }
}

/// يضع فاصلاً رفيعاً بين أبناء البطاقة الظاهرين فقط
struct AdminDividedLayout: _VariadicView_UnaryViewRoot {
    /// بداية الفاصل من الطرف (يبدأ من النص)
    var inset: CGFloat = 0

    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(alignment: .leading, spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != last { AdminRowDivider(inset: inset) }
            }
        }
    }
}

// MARK: - لحظة الموافقة (الدفعة ١٠)

/// بعد الموافقة على طلب في «الوارد»: لحظة «تمت الموافقة» — إن لم يظهر خطأ من الموافقة نفسها (رقم مستخدم، صلاحية…)
@MainActor
enum AdminApprovalMoment {
    static func after(_ adminRequestVM: AdminRequestViewModel, title: String = L10n.t("تمت الموافقة", "Approved")) {
        // الموافقة متفائلة (يختفي الصفّ فوراً) — مهلة قصيرة لتظهر أخطاء الفحص المحلي أولاً وتُغلق نافذة التفاصيل
        DispatchQueue.main.asyncAfter(deadline: .now() + DS.MomentToast.settle) {
            guard adminRequestVM.errorMessage == nil else { return }
            DSMomentToast.show(title, moment: .approved)
        }
    }
}
