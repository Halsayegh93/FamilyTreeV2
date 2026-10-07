import SwiftUI

// MARK: - قطع الحالة والاختيار المشتركة (طلب المالك ٢٠٢٦-١٠-٠٧ «أسلوب واحد، والتعديل من مكان واحد»)
//
// • `DSEmptyView`   — الصفحة الفاضية الواحدة: مجسّم القسم + عنوان + سطر واحد (مثل «لا توجد ديوانيات»).
// • `DSPageLoader`  — التحميل الواحد: نفس مجسّم القسم يتنفّس (+ نص قصير إن وُجد). بلا دوّارة.
// • `DSStateCard`   — بطاقة حالة صغيرة داخل صفحة (فارغ/تحميل/خطأ) — نفس `SysStateCard` بتوقيعه.
// • `DSNoteCard`    — ملاحظة ملوّنة خفيفة (كانت ١٥ نسخة يدوية).
// • `DSOptionTiles` — مربّعات اختيار واحد بأيقونة (نوع الخبر، نوع الديوانية، التصنيف، المظهر…).
// • `DSChipButton`  — شريحة/زرّ صغير بارتفاع واحد (`DSBox.chipHeight`).
// • نسخ مشتركة من عُدّة `Sys*` (كانت داخل ملف صفحة إدارة ويستعملها ~٢٧ ملفاً):
//   `DSStatusChip`، `DSRow`، `DSSectionTitle`، `DSChevron`، `DSActionButton`، `DSRing`، `DSDistributionBar`؛
//   و`SysGradientIcon` ← `DSStateIcon` (ArtTrial.swift). دفعة الإدارة تحذف `Sys*` من
//   `AdminSystemHealthView.swift` وتضع مكانها أسماء بديلة (`typealias SysRow = DSRow` …) أو تعيد التسمية.
// كل الأبعاد والخطوط والشفافيات من DesignSystem.swift (`DS`، `DSBox`، `DS.TextRole`).

// MARK: - التنفّس (التحميل)

/// تنفّس التحميل: تكبير وخفوت هادئان متكرّران — ثابت مع «تقليل الحركة»
private struct DSLoadingBreath: ViewModifier {
    var active: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inhale = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(inhale ? 1.04 : 0.96)
            .opacity(inhale ? 1 : 0.72)
            .onAppear {
                guard active, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { inhale = true }
            }
    }
}

// MARK: - الصفحة الفاضية

/// شكل الصفحة الفاضية — مكان واحد (طلب المالك ٢٠٢٦-١٠-٠٧ «أي شي حجمه صار كبير تردّه حجمه السابق»)
enum DSEmptyStyle {
    /// صفحة كاملة: مجسّم ١٣٠ + عنوان ٢٠ (يتوسّط المساحة)
    case page
    /// داخل قائمة/بطاقة كبيرة: مجسّم ٩٦ + عنوان ١٥ (`compact: true`)
    case card
    /// صفحة فاضية بمساحتها القديمة (صفحات الإدارة — كانت بطاقة حالة بقرص ٥٢): مجسّم ٦٤ + عنوان ١٥ + سطر
    case compact
    /// صفّ داخل قائمة/نتائج: قرص ٣٢ + سطر واحد (~٤٤–٥٠ ارتفاعاً)
    case inline
}

/// الصفحة الفاضية الواحدة: مجسّم القسم + عنوان + سطر واحد (+ زرّ اختياري بالمواصفة الواحدة).
/// `style:` (`DSEmptyStyle`) يحدّد المقاس؛ `compact: true` القديمة = `.card`.
struct DSEmptyView: View {
    let title: String
    var message: String? = nil
    /// nil = قسم البيئة ثم الرئيسية
    var section: AppSection? = nil
    /// رمز المجسّم — nil = مجسّم القسم (`AppSection.artIcon`)
    var icon: String? = nil
    /// لون معنى (نجاح «كل شيء تمام»، خطأ) — nil = حبر القسم
    var tint: Color? = nil
    var actionTitle: String? = nil
    var actionIcon: String? = nil
    var action: (() -> Void)? = nil
    var style: DSEmptyStyle = .page
    @Environment(\.dsSection) private var envSection
    /// وضع العرض: المجسّم أصغر وبجانب النص (الارتفاع ~٤٠٠ نقطة — كان العنوان يُقصّ تحت الإحصائيات)
    @Environment(\.dsLandscape) private var landscape

    init(_ title: String, message: String? = nil, section: AppSection? = nil, icon: String? = nil,
         tint: Color? = nil, actionTitle: String? = nil, actionIcon: String? = nil,
         compact: Bool = false, style: DSEmptyStyle? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.section = section
        self.icon = icon
        self.tint = tint
        self.actionTitle = actionTitle
        self.actionIcon = actionIcon
        self.style = style ?? (compact ? .card : .page)
        self.action = action
    }

    /// داخل قائمة/بطاقة (لا يملأ المساحة)
    private var compact: Bool { style != .page }

    var body: some View {
        if style == .inline {
            inlineBody
        } else if landscape {
            landscapeBody
        } else {
            portraitBody
        }
    }

    /// المجسّم (مشهد القسم إن كان له، وإلا رمزه على القرص) بالمقاس المطلوب
    private func art(side: CGFloat) -> some View {
        let sec = section ?? envSection ?? .home
        return EmptyStateArt(icon: icon ?? sec.artIcon, tint: (tint ?? sec.ink).dsReadableGlyph,
                             kind: icon == nil ? sec.artPlace : nil)
            .scaleEffect(side / DS.Icon.emptyArt)
            .frame(width: side, height: side)
    }

    /// مقاس المجسّم حسب الشكل
    private var artSide: CGFloat {
        switch style {
        case .page: return DS.Icon.emptyArt
        case .card: return DS.Icon.loaderArt
        case .compact, .inline: return DS.Icon.emptyArtCompact
        }
    }

    /// صفّ: قرص القسم الصغير + السطر (+ الوصف تحته إن وُجد، + شريحة الإجراء)
    private var inlineBody: some View {
        let sec = section ?? envSection ?? .home
        return HStack(spacing: DS.Spacing.sm) {
            DSStateIcon(icon ?? sec.artIcon, tint: tint ?? sec.ink, size: DS.Icon.row)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.callout)
                    .foregroundColor(DS.Color.textSecondary)
                if let message, !message.isEmpty {
                    Text(message)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                DSChipButton(actionTitle, icon: actionIcon, size: .small, action: action)
            }
        }
        // صفّ ~٤٨ (قرص ٣٢ + ٨×٢) — بارتفاع صفّ «لا توجد نتائج» القديم
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// أفقياً: المجسّم بجانب العنوان والسطر والزرّ — صفّ واحد قصير يتوسّط المساحة
    private var landscapeBody: some View {
        HStack(spacing: DS.Spacing.xl) {
            art(side: style == .compact ? DS.Icon.emptyArtCompact
                    : compact ? DS.Landscape.loaderArt : DS.Landscape.emptyArt)
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text(title)
                    .dsFont(compact ? .headline : .emptyTitle)
                    .foregroundColor(DS.Color.textPrimary)
                if let message, !message.isEmpty {
                    Text(message)
                        .dsFont(compact ? .callout : .body)
                        .foregroundColor(DS.Color.textSecondary)
                }
                if let actionTitle, let action {
                    DSButton(actionTitle, icon: actionIcon, tint: tint.flatMap(Self.meaning), fullWidth: false, action: action)
                        .padding(.top, DS.Spacing.xs)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: DS.Landscape.maxContentWidth)
        .padding(.horizontal, DS.Spacing.xxl)
        .padding(.vertical, style == .compact ? DS.Spacing.md : DS.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity)
    }

    private var portraitBody: some View {
        let sec = section ?? envSection ?? .home
        let side = artSide
        let small = style == .compact
        return VStack(spacing: small ? DS.Spacing.sm : compact ? DS.Spacing.md : DS.Spacing.xl) {
            if !compact { Spacer(minLength: 0) }
            // مجسّم القسم: مشهد مربّعه (الغافة، المجلس، الكتاب، الدكان) إن كان له، وإلا رمزه على القرص
            EmptyStateArt(icon: icon ?? sec.artIcon, tint: (tint ?? sec.ink).dsReadableGlyph,
                          kind: icon == nil ? sec.artPlace : nil)
                .scaleEffect(side / DS.Icon.emptyArt)
                .frame(width: side, height: side)
            VStack(spacing: small ? DS.Spacing.xxs : DS.Spacing.sm) {
                Text(title)
                    .dsFont(compact ? .headline : .emptyTitle)
                    .foregroundColor(DS.Color.textPrimary)
                if let message, !message.isEmpty {
                    Text(message)
                        .dsFont(compact ? .callout : .body)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.Spacing.xxl)
            .accessibilityElement(children: .combine)
            if let actionTitle, let action {
                DSButton(actionTitle, icon: actionIcon, tint: tint.flatMap(Self.meaning), fullWidth: false, action: action)
            }
            if !compact { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, small ? DS.Spacing.md : compact ? DS.Spacing.lg : 0)
    }

    /// زرّ الحالة: لون المعنى صلباً (الخطأ مثلاً)، والكحلي/لون قسم = تعبئة القسم
    private static func meaning(_ c: Color) -> Color? {
        (c == DS.Color.primary || c == DS.Color.actionNavy || c.dsSectionOfFill != nil) ? nil : c
    }
}

// MARK: - التحميل

/// التحميل الواحد: مجسّم القسم نفسه يتنفّس (+ نص قصير اختياري) — بدل الدوّارات و«جاري التحميل...»
struct DSPageLoader: View {
    var text: String? = nil
    /// nil = قسم البيئة ثم الرئيسية
    var section: AppSection? = nil
    /// رمز المجسّم — nil = مجسّم القسم
    var icon: String? = nil
    /// مقاس المجسّم — الافتراضي `DS.Icon.loaderArt` (٩٦) لملء الصفحة، و`DS.Icon.loaderArtInline` (٥٢) داخل بطاقة/قائمة
    var size: CGFloat = DS.Icon.loaderArt
    /// false = على قدر محتواه (داخل بطاقة/قائمة) بدل ملء المساحة
    var fillsSpace: Bool = true
    @Environment(\.dsSection) private var envSection
    /// وضع العرض: المجسّم لا يتجاوز `DS.Landscape.loaderArt`
    @Environment(\.dsLandscape) private var landscape

    init(_ text: String? = nil, section: AppSection? = nil, icon: String? = nil,
         size: CGFloat? = nil, fillsSpace: Bool = true) {
        self.text = text
        self.section = section
        self.icon = icon
        self.size = size ?? (fillsSpace ? DS.Icon.loaderArt : DS.Icon.loaderArtInline)
        self.fillsSpace = fillsSpace
    }

    var body: some View {
        let sec = section ?? envSection ?? .home
        let size = landscape ? min(self.size, DS.Landscape.loaderArt) : self.size
        VStack(spacing: DS.Spacing.md) {
            // نفس مجسّم الصفحة الفاضية (مشهد القسم أو رمزه) يتنفّس
            EmptyStateArt(icon: icon ?? sec.artIcon, tint: sec.ink, kind: icon == nil ? sec.artPlace : nil)
                .scaleEffect(size / DS.Icon.emptyArt)
                .frame(width: size, height: size)
                .modifier(DSLoadingBreath())
            if let text, !text.isEmpty {
                Text(text)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: fillsSpace ? .infinity : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text ?? L10n.t("جاري التحميل", "Loading"))
    }
}

// MARK: - بطاقة الحالة (فارغ / تحميل / خطأ) داخل صفحة

/// بطاقة صغيرة في المنتصف: قرص الحالة المجسّم، عنوان، سطر توضيح، وزرّ — نفس `SysStateCard` بتوقيعه
/// (التحميل: القرص يتنفّس بدل الدوّارة؛ الزرّ بالمواصفة الواحدة؛ البطاقة `.dsCard`)
struct DSStateCard: View {
    let icon: String
    let title: String
    var hint: String? = nil
    var tint: Color = DS.Color.primary
    var isLoading: Bool = false
    var actionTitle: String? = nil
    var actionIcon: String = "arrow.clockwise"
    var action: (() -> Void)? = nil
    /// رسمة كبيرة بدل القرص الصغير (مثل جرس الإشعارات الفاضية)
    var art: AnyView? = nil

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            if let art, !isLoading {
                art.accessibilityHidden(true)
            } else {
                DSStateIcon(icon, tint: tint, size: DS.Icon.state)
                    .modifier(DSLoadingBreath(active: isLoading))
            }

            Text(title)
                .dsFieldFont(.headline)
                .foregroundColor(DS.Color.fieldLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let hint {
                Text(hint)
                    .dsFieldFont(.subtitle)
                    .foregroundColor(DS.Color.fieldValue)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action, !isLoading {
                DSButton(actionTitle, icon: actionIcon, fullWidth: false, action: action)
                    .padding(.top, DS.Spacing.xxs)
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: 360)
        .dsCard(padding: nil)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isLoading ? L10n.t("جاري التحميل", "Loading") : title)
    }
}

// MARK: - ملاحظة ملوّنة

/// ملاحظة خفيفة بلون (معلومة، تنبيه، موافقة الإدارة…): قرص مجسّم صغير + عنوان اختياري + نص.
/// الكحلي ← لون القسم؛ ألوان المعاني (`warning`، `error`، `success`) كما هي.
struct DSNoteCard: View {
    let text: String
    var title: String? = nil
    var icon: String = "info.circle.fill"
    var tint: Color = DS.Color.primary
    @Environment(\.dsSection) private var section

    init(_ text: String, title: String? = nil, icon: String = "info.circle.fill", tint: Color = DS.Color.primary) {
        self.text = text
        self.title = title
        self.icon = icon
        self.tint = tint
    }

    var body: some View {
        let ink = tint.dsChrome(in: section).dsReadableGlyph
        let shape = RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
        return HStack(alignment: .top, spacing: DS.Spacing.sm) {
            DSStateIcon(icon, tint: ink, size: DS.Icon.section, mapsChrome: false)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                if let title {
                    Text(title)
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(ink)
                }
                Text(text)
                    .dsFieldFont(.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, title == nil ? DS.Spacing.xxs : 0)
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.sm + DS.Spacing.xxs)
        .background(shape.fill(ink.opacity(DS.Opacity.tintFillSoft)))
        .overlay(shape.strokeBorder(ink.opacity(DS.Opacity.tintStroke), lineWidth: DS.Card.strokeWidth))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - مربّعات اختيار واحد

/// خيار في `DSOptionTiles`
struct DSOptionTile<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let icon: String
    /// لون الخيار (معنى) — nil = لون القسم
    var tint: Color? = nil

    init(_ id: ID, title: String, icon: String, tint: Color? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.tint = tint
    }
}

/// شبكة مربّعات اختيار واحد: قرص أيقونة + اسم. المختار: سطح بلونه الخفيف وإطاره، وقرصه مجسّم ممتلئ.
/// `icon:` لرسم خاص لكل خيار (مثل شارات أنواع الأخبار المتحرّكة) — يستلم الخيار وهل هو مختار.
struct DSOptionTiles<ID: Hashable, Icon: View>: View {
    let options: [DSOptionTile<ID>]
    @Binding var selection: ID
    var columns: Int = 4
    @ViewBuilder var icon: (DSOptionTile<ID>, Bool) -> Icon
    @Environment(\.dsSection) private var section
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ options: [DSOptionTile<ID>], selection: Binding<ID>, columns: Int = 4,
         @ViewBuilder icon: @escaping (DSOptionTile<ID>, Bool) -> Icon) {
        self.options = options
        self._selection = selection
        self.columns = columns
        self.icon = icon
    }

    var body: some View {
        // صفوف عادية لا `LazyVGrid` (دفعة 2-A): الشبكة الكسولة تُبلِّغ ارتفاعاً ناقصاً داخل المربّعات
        // فيُقصّ آخر صف (كان يُرى في «تعديل الخبر») — نفس الشكل تماماً
        let cols = max(1, columns)
        VStack(spacing: DS.Spacing.sm) {
            ForEach(Array(stride(from: 0, to: options.count, by: cols)), id: \.self) { start in
                let end = min(start + cols, options.count)
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(options[start..<end]) { option in tile(option) }
                    ForEach(0..<(cols - (end - start)), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: DS.Border.width)
                    }
                }
            }
        }
    }

    private func tile(_ option: DSOptionTile<ID>) -> some View {
        let selected = selection == option.id
        let ink = (option.tint ?? DS.Color.primary).dsChrome(in: section).dsReadableGlyph
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        return Button {
            guard selection != option.id else { return }
            withAnimation(DS.Anim.snappy) { selection = option.id }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: DS.Spacing.xsm) {
                icon(option, selected)
                    .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                    .scaleEffect(selected && !reduceMotion ? 1.08 : 1)
                    .accessibilityHidden(true)
                Text(option.title)
                    .dsFont(.chip)
                    .foregroundColor(selected ? ink : DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.sm)
            .background(shape.fill(selected ? ink.opacity(DS.Opacity.tintFillSoft) : DS.Color.background))
            .overlay(shape.strokeBorder(selected ? ink.opacity(DS.Opacity.selectedStroke)
                                                 : DS.Color.textTertiary.opacity(DS.Opacity.border),
                                        lineWidth: selected ? DS.Border.widthBold : DS.Border.width))
            .trialCardSkin(radius: DS.Radius.md)
            .contentShape(shape)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension DSOptionTiles where Icon == DSOptionTileIcon {
    /// القرص الافتراضي: المختار مجسّم ممتلئ بلونه، وغيره قرص خفيف برمزه
    init(_ options: [DSOptionTile<ID>], selection: Binding<ID>, columns: Int = 4) {
        self.init(options, selection: selection, columns: columns) { option, selected in
            DSOptionTileIcon(icon: option.icon, tint: option.tint, selected: selected)
        }
    }
}

/// قرص خيار `DSOptionTiles` الافتراضي
struct DSOptionTileIcon: View {
    let icon: String
    var tint: Color? = nil
    let selected: Bool
    @Environment(\.dsSection) private var section

    var body: some View {
        let ink = (tint ?? DS.Color.primary).dsChrome(in: section).dsReadableGlyph
        if selected {
            DSStateIcon(icon, tint: ink, size: DS.Icon.sizeSm, mapsChrome: false)
        } else {
            Image(dsSymbol: icon)
                .dsGlyph(DS.Glyph.lg)
                .foregroundColor(ink)
                .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                .background(Circle().fill(ink.opacity(DS.Opacity.tintFill)))
        }
    }
}

// MARK: - الشريحة (زرّ صغير)

/// مقاس الشريحة — مكان واحد (طلب المالك ٢٠٢٦-١٠-٠٧ «أي شي حجمه صار كبير تردّه حجمه السابق»)
enum DSChipSize {
    /// ٣٤، نص ١٢ عريض — الفلاتر وأزرار الصفّ الصغيرة
    case regular
    /// ٢٨، نص ١٢ وحشوة ١٠ — شرائح داخل صفّ/بطاقة (فروع البحث، «صلة القرابة»، «الموقع/اتصال»)
    case small
    /// ~١٨، نص ١١ وحشوة ٦ — شريط المسار في الشجرة وتبويب شريطها الجانبي
    case mini
}

/// شريحة/زرّ صغير بارتفاع من `DSChipSize` (`DSBox.chipHeight*`) — فلتر، «تحديد»، «بدون تاريخ»، إجراء صغير في صفّ.
/// غير المختار: لون خفيف ورمز ونص بلونه؛ المختار: ممتلئ (تعبئة القسم، أو لون المعنى) بنص أبيض.
/// مساحة الضغط ٤٤ (حدّ أبل) لا تدخل التخطيط — الشريحة تأخذ ارتفاعها المرئي فقط.
struct DSChipButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = DS.Color.primary
    var isSelected: Bool = false
    /// عدد صغير بعد النص (فلاتر)
    var count: Int? = nil
    var size: DSChipSize = .regular
    /// أثناء العمل: دوّارة صغيرة مكان الرمز ولا تُضغط مرة ثانية (تحميل الصورة قبل تعديلها)
    var isLoading: Bool = false
    let action: () -> Void
    @Environment(\.dsSection) private var section
    /// المعطّل (للقراءة فقط مثلاً) يخفت بشفافية الزرّ الواحد — كان «حفظ» الممتلئ يبدو فعّالاً
    /// وهو لا يعمل (ن-١١ فحص ٢٠٢٦-١٠-٠٧)
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, icon: String? = nil, tint: Color = DS.Color.primary, isSelected: Bool = false,
         count: Int? = nil, size: DSChipSize = .regular, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.isSelected = isSelected
        self.count = count
        self.size = size
        self.isLoading = isLoading
        self.action = action
    }

    private var height: CGFloat {
        switch size {
        case .regular: return DSBox.chipHeight
        case .small: return DSBox.chipHeightSmall
        case .mini: return DSBox.chipHeightMini
        }
    }
    private var padding: CGFloat {
        switch size {
        case .regular: return DSBox.chipPadding
        case .small: return DSBox.chipPaddingSmall
        case .mini: return DSBox.chipPaddingMini
        }
    }

    var body: some View {
        let ink = tint.dsChrome(in: section).dsReadableGlyph
        let chrome = tint == DS.Color.primary || tint == DS.Color.actionNavy
        return Button(action: action) {
            HStack(spacing: size == .mini ? DS.Spacing.xxs : DS.Spacing.xsm) {
                if isLoading {
                    ProgressView()
                        .tint(isSelected ? .white : ink)
                        .scaleEffect(DS.Spinner.chipScale)
                } else if let icon {
                    Image(dsSymbol: icon).dsGlyph(size == .regular ? DS.Glyph.sm
                                                  : size == .small ? DS.Glyph.smCompact : DS.Glyph.xs)
                }
                Text(title)
                    .dsFont(size == .mini ? .badge : .chip)
                    .lineLimit(1)
                if let count {
                    Text("\(count)")
                        .dsFont(.micro)
                        .monospacedDigit()
                        .opacity(0.85)
                }
            }
            .foregroundColor(isSelected ? .white : ink)
            .padding(.horizontal, padding)
            .frame(height: height)
            .background {
                if isSelected {
                    Capsule().fill(chrome ? DSActionFill.style() : AnyShapeStyle(tint.dsChromeFill(in: section)))
                } else {
                    Capsule().fill(ink.opacity(DS.Opacity.tintFill))
                }
            }
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : ink.opacity(DS.Opacity.tintStroke),
                                            lineWidth: DS.Border.width))
            // المعطّل بنفس شفافية الزرّ الواحد المعطّل (ن-١١)
            .opacity(isEnabled ? 1 : DSActionFill.disabledOpacity)
            // مساحة ضغط ٤٤ (حدّ أبل) بلا أن تكبّر الصفّ
            .dsTapArea(width: DS.Icon.tapTarget, height: height)
        }
        .buttonStyle(DSPressStyle())
        .allowsHitTesting(!isLoading)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - عُدّة صفحات النظام المشتركة (كانت `Sys*` في AdminSystemHealthView.swift)

/// كبسولة حالة صغيرة: منتظر = warning، مفعّل = success، مرفوض/مجمّد = error، معلومة = primary
struct DSStatusChip: View {
    /// مقاس شارة الحالة: العادية (صفحات الإدارة) والمصغّرة (داخل صفّ/بطاقة — كانت الشارات هناك أنحف)
    enum Size { case regular, mini }

    let text: String
    var icon: String? = nil
    var tint: Color = DS.Color.primary
    var size: Size = .regular
    @Environment(\.dsSection) private var section

    var body: some View {
        let ink = tint.dsChrome(in: section).dsReadableGlyph
        return HStack(spacing: DS.Spacing.xxs + 1) {
            if let icon {
                Image(dsSymbol: icon)
                    .dsGlyph(DS.Glyph.micro)
                    .accessibilityHidden(true)
            }
            Text(text)
                .dsFont(.badge)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundColor(ink)
        .padding(.horizontal, size == .mini ? DS.Spacing.xsm : DS.Spacing.sm)
        .padding(.vertical, size == .mini ? DS.Spacing.xxs : DS.Spacing.xxs + 1)
        .background(ink.opacity(DS.Opacity.tintFill), in: Capsule())
    }
}

/// صفّ بإطار حقول المربّعات: قرص مجسّم + عنوان + وصف + طرف اختياري
struct DSRow<Trailing: View>: View {
    let icon: String
    var tint: Color = DS.Color.primary
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .frame(minHeight: DSBox.fieldMinHeight)
        .dsRowBox()
    }
}

extension DSRow where Trailing == EmptyView {
    init(icon: String, tint: Color = DS.Color.primary, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
    }
}

/// سهم صغير يتبع اتجاه اللغة (للصفوف القابلة للضغط)
struct DSChevron: View {
    /// مقاس الرمز — الأصغر بين شرائح شريط المسار
    var size: CGFloat = DS.Glyph.sm

    var body: some View {
        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
            .dsGlyph(size)
            .foregroundColor(DS.Color.textTertiary)
            .accessibilityHidden(true)
    }
}

/// عنوان قسم خارج البطاقة — نفس رأس `DSComposerSection` (قرص مجسّم + عنوان + نص جانبي)
struct DSSectionTitle: View {
    let title: String
    let icon: String
    var tint: Color = DS.Color.primary
    var trailing: String? = nil
    /// قرص العنوان — الأصغر (`DS.Icon.inline` ١٦) لعناوين التاريخ داخل القوائم
    var iconSize: CGFloat = DS.Icon.section

    var body: some View {
        HStack(spacing: DS.Spacing.xsm + 1) {
            DSStateIcon(icon, tint: tint, size: iconSize)
            Text(title)
                .dsFieldFont(.sectionTitle)
                .foregroundColor(DS.Color.fieldLabel)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, DS.Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// زرّ إجراء بعرض كامل — الزرّ الواحد (٤٠): تعبئة القسم، أو لون صلب للتحذير/الخطر (`tint`)
struct DSActionButton: View {
    let title: String
    let icon: String
    /// nil = تعبئة القسم، وغيره لون صلب (تحذير/خطر)
    var tint: Color? = nil
    var isBusy: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        DSButton(title, icon: icon, role: tint == DS.Color.error ? .destructive : nil,
                 tint: tint == DS.Color.error ? nil : tint, isLoading: isBusy, action: action)
            .disabled(!enabled)
    }
}

/// حلقة نسبة (٠…١) بلون الحالة — تمتلئ بحركة ناعمة (ثابتة مع «تقليل الحركة»)
struct DSRing<Center: View>: View {
    let progress: Double
    var tint: Color = DS.Color.success
    var lineWidth: CGFloat = DS.Spacing.sm
    var size: CGFloat = 84
    @ViewBuilder var center: () -> Center
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(DS.Opacity.tintFill), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown || reduceMotion ? max(0, min(1, progress)) : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { shown = true; return }
            withAnimation(.easeOut(duration: 0.9).delay(0.2)) { shown = true }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: progress)
    }
}

/// شريط أفقي مقسّم بنسب ملوّنة (توزيع فئات) — لمحة بدل جدول أرقام
struct DSDistributionBar: View {
    struct Segment: Identifiable {
        let id: String
        let value: Int
        let tint: Color
    }
    let segments: [Segment]
    var height: CGFloat = 10

    var body: some View {
        let visible = segments.filter { $0.value > 0 }
        let total = max(1, visible.reduce(0) { $0 + $1.value })
        let gap = DS.Spacing.xxs
        let gaps = CGFloat(max(0, visible.count - 1)) * gap
        GeometryReader { geo in
            HStack(spacing: gap) {
                ForEach(visible) { seg in
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(seg.tint)
                        .frame(width: max(height, (geo.size.width - gaps) * CGFloat(seg.value) / CGFloat(total)))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(Capsule().fill(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke)))
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

// MARK: - صفّ الأرقام السريعة (دفعة 2-B «أسلوب واحد»، ٢٠٢٦-١٠-٠٧)

/// أرقام الصفحة السريعة في البطاقة الواحدة `.dsCard()` — كانت داخل بطاقة الرأس `DSPageHero`؛ صار العنوان
/// والوصف في رأس الصفحة الملوّن (`dsSubPageHeader`) والأرقام هنا تحته. القيمة بحبر القسم (أو لون معنى
/// `tint`) واسمها تحتها، وكل رقم في خانة بلون خفيف. يأخذ نفس `DSHeroStat`.
struct DSStatsRow: View {
    let stats: [DSHeroStat]
    var tint: Color = DS.Color.primary
    @Environment(\.dsSection) private var section

    init(_ stats: [DSHeroStat], tint: Color = DS.Color.primary) {
        self.stats = stats
        self.tint = tint
    }

    var body: some View {
        let ink = tint.dsChrome(in: section).dsReadableGlyph
        let shape = RoundedRectangle(cornerRadius: DS.Icon.discRadius, style: .continuous)
        return HStack(spacing: DS.Spacing.sm) {
            ForEach(stats) { stat in
                VStack(spacing: DS.Spacing.xxs) {
                    HStack(spacing: DS.Spacing.xs) {
                        if let icon = stat.icon {
                            Image(dsSymbol: icon)
                                .dsGlyph(DS.Glyph.xs)
                                .accessibilityHidden(true)
                        }
                        Text(stat.value)
                            .dsFont(.headline)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundColor(ink)
                    Text(stat.label)
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.sm)
                .background(shape.fill(ink.opacity(DS.Opacity.tintFillSoft)))
                .accessibilityElement(children: .combine)
            }
        }
        .dsCard()
    }
}

// MARK: - وجه شريحة «إضافة» المتقطّعة (دفعة 2-A «أسلوب واحد»، ٢٠٢٦-١٠-٠٧)

/// وجه شريحة/خانة «إضافة» بإطار متقطّع — نفس وجه `DSExtraChip` الفارغ («+ صور»، «+ تصويت»)، لمن يحتاج
/// الوجه وحده داخل غير `Button` (مثل `PhotosPicker`) أو بعرض السطر («خيار آخر»). الشريحة بارتفاع
/// `DSBox.chipHeight` ومساحة ضغط ٤٤، وبعرض السطر بارتفاع الزرّ الواحد.
struct DSAddChipLabel: View {
    let icon: String
    let title: String
    /// nil = رمادي هادئ (مثل الشريحة الفارغة)، وإلا لون الخانة
    var tint: Color? = nil
    /// بعرض السطر وبارتفاع `DSBox.buttonHeight` (خانة إضافة) بدل الشريحة
    var fullWidth: Bool = false
    /// دوّارة صغيرة مكان الرمز أثناء التحميل
    var isLoading: Bool = false

    static let dash = StrokeStyle(lineWidth: 1.2, dash: [4, 3])
    static let strokeOpacity: Double = 0.4

    var body: some View {
        let ink = tint ?? DS.Color.textSecondary
        let line = (tint ?? DS.Color.textTertiary).opacity(Self.strokeOpacity)
        HStack(spacing: DS.Spacing.xsm) {
            if isLoading {
                ProgressView().scaleEffect(0.7).tint(ink)
            } else {
                Image(systemName: "plus").dsGlyph(DS.Glyph.sm)
                if icon != "plus" { Image(dsSymbol: icon).dsGlyph(DS.Glyph.sm, weight: .semibold) }
            }
            Text(title)
                .dsFont(.chip)
                .lineLimit(1)
        }
        .foregroundColor(ink)
        .padding(.horizontal, DSBox.chipPadding)
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .frame(height: fullWidth ? DSBox.buttonHeight : DSBox.chipHeight)
        .overlay {
            if fullWidth {
                RoundedRectangle(cornerRadius: DSBox.buttonRadius, style: .continuous).strokeBorder(line, style: Self.dash)
            } else {
                Capsule().strokeBorder(line, style: Self.dash)
            }
        }
        // مساحة ضغط ٤٤ (حدّ أبل) والشكل كما هو
        .padding(.vertical, fullWidth ? 0 : (DS.Icon.tapTarget - DSBox.chipHeight) / 2)
        .contentShape(Rectangle())
    }
}

// MARK: - مشهد القسم للصفحة الفاضية والتحميل (دفعة 2-A «أسلوب واحد»، ٢٠٢٦-١٠-٠٧)

extension AppSection {
    /// مشهد «مجسّمات» القسم (نفس مجسّم مربّعه في الرئيسية) — `DSEmptyView`/`DSPageLoader` يرسمانه
    /// حين لا يُمرَّر رمز آخر؛ nil = رمز القسم (`artIcon`) على القرص
    var artPlace: FTTileScenes.Kind? {
        switch self {
        case .tree:      return .tree
        case .diwaniyas: return .diwaniya
        case .library:   return .library
        case .projects:  return .projects
        default:         return nil
        }
    }
}
