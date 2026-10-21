import SwiftUI

// MARK: - رأس الصفحة الفرعية الواحد (طلب المالك ٢٠٢٦-١٠-٠٧ «أسلوب واحد في جميع الأقسام»)
//
// كل صفحة فرعية في كل قسم (صفحات الرئيسية، كل صفحات الإدارة، الإعدادات، الإشعارات، التسجيل، الألبوم…)
// تأخذ نفس الرأس الملوّن: تدرّج القسم + مجسّم القسم (`TrialHeaderIcon`) + عنوان أبيض + وصف + زرّا
// الرجوع/الإغلاق الموحّدان (`DSBackButton`/`DSCloseButton` فوق اللون) + إجراءات اختيارية في الطرف
// (`DSHeaderButton`) + زخرفة «مجسّمات» تحته، واختيارياً المجسّم كبيراً مائلاً شفافاً في الطرف الآخر.
// كان مكرّراً باليد: `HomeNewsView.subPageHeader` (خاص)، `NotificationsCenterView.notificationsHeader`،
// `RegistrationView.topBar`، `SettingsView` — والإدارة بشريط النظام الأبيض + `DSPageHero`.
// الأبعاد والخطوط من `DSBox.pageHeader*` / `DS.TextRole.pageTitle/pageSubtitle` — مكان واحد.
//
// الاستعمال:
//  ١) صفحة داخل NavigationStack بشريط النظام (صفحات الإدارة) — سطر واحد على جذر الصفحة، ويُخفى شريط النظام:
//         AdminPushHealthView-body
//             .dsSubPageHeader(L10n.t("الأجهزة ووصول الإشعارات", "Devices & notification reach"), subtitle: L10n.t("…", "…"))
//     مع إجراءات (كانت ToolbarItem — تنتقل هنا لأن شريط النظام يختفي):
//             .dsSubPageHeader(title, subtitle: sub) {
//                 DSHeaderButton(symbol: "plus", label: L10n.t("إضافة", "Add")) { showAdd = true }
//             }
//     القسم من البيئة (`.dsSection` للتبويب أو `.dsSectionPage` للصفحة) — أو `section: .library` صراحة.
//     الرجوع افتراضياً `dismiss()` من البيئة (يرجع خطوة في NavigationStack أو يغلق الورقة).
//  ٢) صفحة ترسم رأسها بنفسها داخل VStack (صفحات الرئيسية):
//         VStack(spacing: 0) {
//             DSSubPageHeader(title: …, subtitle: …, section: .projects, onBack: { activeSubPage = nil }) {
//                 DSHeaderButton(symbol: "checkmark.circle", label: …) { … }
//             }
//             FamilyProjectsView()
//         }
//  ٣) صفحة تُفتح ورقة/غطاء (الإعدادات، الإشعارات من الرئيسية): `nav: .close` يضع × في الطرف الآخر
//     (يسار في العربية — قاعدة «الإغلاق يسار») بدل سهم الرجوع.
//  ٤) بلا مجسّم: `icon: ""`. مجسّم آخر غير مجسّم القسم: `icon: "bell.fill"` (يرسمه «مجسّمات»).
//     النسخة الكبيرة المائلة الشفافة في الطرف: `watermark: true`.

/// زرّ التنقّل في الرأس
enum DSSubPageNav {
    /// سهم الرجوع في بداية السطر (يمين العربية) — الصفحات المدفوعة
    case back
    /// × في نهاية السطر (يسار العربية) — الأوراق والأغطية
    case close
    /// بلا زرّ (صفحة جذر)
    case none
}

struct DSSubPageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    /// قسم الرأس — nil = قسم البيئة (`dsSection`)، ثم الرئيسية
    var section: AppSection? = nil
    /// رمز المجسّم — nil = مجسّم القسم (`AppSection.artIcon`)، "" = بلا مجسّم
    var icon: String? = nil
    /// المجسّم كبيراً مائلاً شفافاً في الطرف الآخر
    var watermark: Bool = false
    var nav: DSSubPageNav = .back
    /// nil = `dismiss()` من البيئة
    var onBack: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.dsSection) private var envSection
    @Environment(\.dsLandscape) private var landscape
    @Environment(\.dismiss) private var dismiss

    init(title: String, subtitle: String? = nil, section: AppSection? = nil, icon: String? = nil,
         watermark: Bool = false, nav: DSSubPageNav = .back, onBack: (() -> Void)? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.section = section
        self.icon = icon
        self.watermark = watermark
        self.nav = nav
        self.onBack = onBack
        self.trailing = trailing
    }

    /// الوضع الأفقي — رأس مضغوط (٤٦) ومجسّم وأزرار أصغر
    private var compact: Bool { landscape }
    private var sec: AppSection { section ?? envSection ?? .home }
    private var artIcon: String { icon ?? sec.artIcon }
    /// في طرف الرأس أزرار (إجراءات أو ×)
    private var hasTrailingItems: Bool { Trailing.self != EmptyView.self || nav == .close }

    private func goBack() {
        if let onBack { onBack() } else { dismiss() }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.md) {
                if nav == .back {
                    DSBackButton(context: .onColor, compact: compact, action: goBack)
                }

                if !artIcon.isEmpty {
                    TrialHeaderIcon(icon: artIcon, tint: sec.fill,
                                    side: compact ? DSBox.pageHeaderIconCompact : DSBox.pageHeaderIcon)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title)
                        .font(DSBox.pageTitleFont)
                        .foregroundColor(DS.Color.headerTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(DSBox.pageSubtitleFont)
                            .foregroundColor(DS.Color.headerSubtitle)
                            // الوصف الطويل سطران (الرأس يطول — `minHeight`) بدل «…» مع مقاسات Apple
                            .lineLimit(compact ? 1 : DSBox.pageSubtitleLines)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                Spacer(minLength: DS.Spacing.xs)

                trailing()

                if nav == .close {
                    DSCloseButton(context: .onColor, compact: compact, action: goBack)
                }
            }
            .padding(.horizontal, compact ? DS.Spacing.xxl : DS.Spacing.lg)
            .padding(.bottom, compact ? DS.Spacing.xs : DS.Spacing.sm)
            .padding(.top, compact ? DS.Spacing.xs : 0)
            .frame(minHeight: compact ? DSBox.pageHeaderHeightCompact : DSBox.pageHeaderHeight, alignment: .bottom)

            // زخرفة «مجسّمات» تحت الرأس — تحلّ محل الخط الفاصل (مثل رؤوس التبويبات)
            if let ornament = FT5STrial.tabHeaderOrnament(section: "\(sec)", tint: sec.fill) {
                ornament
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.bottom, DS.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .background(background)
        // نص شريط الحالة أبيض فوق الرأس الملوّن
        .dsLightStatusBar()
    }

    private var background: some View {
        ZStack {
            // تدرّج القسم + نفس طبقة MainHeaderView (بدونها يطلع الرأس أفتح) — «الهادئ»: لون القسم الخفيف
            DSHeaderBackground(section: sec)
            if watermark, !artIcon.isEmpty {
                // المجسّم نفسه كبيراً مائلاً شفافاً في الطرف الآخر (مثل رأس مربّع العمل) — زخرفة تُقصّ بحدود الرأس
                // يخرج قليلاً من الطرف ويُقصّ — ويتنحّى عن أزرار الطرف إن وُجدت (الهوامش تتبع اتجاه اللغة)
                FT5STrial.headerIcon(icon: artIcon, tint: sec.fill)
                    .frame(width: DSBox.pageWatermark, height: DSBox.pageWatermark)
                    .rotationEffect(.degrees(DSBox.pageWatermarkAngle))
                    .opacity(DSBox.pageWatermarkOpacity)
                    .padding(.trailing, hasTrailingItems ? DS.Icon.tapTarget + DS.Spacing.lg : -DS.Spacing.lg)
                    .padding(.bottom, -DS.Spacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .clipped()
        // أفقياً: اللون يمتدّ تحت النوتش وطرف الشاشة الآخر (كان يقف عند المنطقة الآمنة بشريطين أبيضين)
        // — الأزرار والنص يبقون داخل المنطقة الآمنة
        .ignoresSafeArea(edges: compact ? [.top, .horizontal] : .top)
    }
}

extension DSSubPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, section: AppSection? = nil, icon: String? = nil,
         watermark: Bool = false, nav: DSSubPageNav = .back, onBack: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, section: section, icon: icon, watermark: watermark,
                  nav: nav, onBack: onBack, trailing: { EmptyView() })
    }
}

// MARK: - تبنّي الرأس بسطر واحد

private struct DSSubPageHeaderModifier<Trailing: View>: ViewModifier {
    let title: String
    let subtitle: String?
    let section: AppSection?
    let icon: String?
    let watermark: Bool
    let nav: DSSubPageNav
    let onBack: (() -> Void)?
    let trailing: () -> Trailing

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            DSSubPageHeader(title: title, subtitle: subtitle, section: section, icon: icon,
                            watermark: watermark, nav: nav, onBack: onBack, trailing: trailing)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DS.Color.background.ignoresSafeArea())
        // شريط النظام يختفي — الرأس الملوّن هو شريط الصفحة (سحب الرجوع من الحافة يبقى)
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension View {
    /// رأس الصفحة الفرعية الملوّن فوق هذه الصفحة، ويُخفي شريط النظام (للصفحات داخل NavigationStack)
    func dsSubPageHeader<T: View>(_ title: String, subtitle: String? = nil, section: AppSection? = nil,
                                  icon: String? = nil, watermark: Bool = false, nav: DSSubPageNav = .back,
                                  onBack: (() -> Void)? = nil,
                                  @ViewBuilder trailing: @escaping () -> T) -> some View {
        modifier(DSSubPageHeaderModifier(title: title, subtitle: subtitle, section: section, icon: icon,
                                         watermark: watermark, nav: nav, onBack: onBack, trailing: trailing))
    }

    /// رأس الصفحة الفرعية الملوّن بلا إجراءات
    func dsSubPageHeader(_ title: String, subtitle: String? = nil, section: AppSection? = nil,
                         icon: String? = nil, watermark: Bool = false, nav: DSSubPageNav = .back,
                         onBack: (() -> Void)? = nil) -> some View {
        dsSubPageHeader(title, subtitle: subtitle, section: section, icon: icon, watermark: watermark,
                        nav: nav, onBack: onBack) { EmptyView() }
    }
}
