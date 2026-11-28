import SwiftUI

// MARK: - صفحات الإدارة بتصميم المربّعات الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧، «أسلوب واحد» ٢٠٢٦-١٠-٠٧)
//
// لغة واحدة لكل صفحات الإدارة (الطلبات، الأعضاء، الرسائل، السجل، النظام…):
//   • الرأس: الرأس الملوّن الموحّد `.dsSubPageHeader(…)` (DSSubPageHeader.swift) — كان شريط النظام الأبيض
//     + بطاقة رأس `DSPageHero` (حُذفت في دفعة 3-B بعد أن صار لا يستعملها أحد).
//   • `DSHeroStat` + `DSStatsRow` (DSStateKit) — صفّ الأرقام السريعة تحت الرأس.
//   • `DSStatTile` — بطاقة رقم حيّ (قابلة للضغط) لشبكة الأرقام.
//   • `DSSearchField` — حقل بحث بنفس إطار حقول المربّعات.
//   • `DSFilterChips` — شريط فلاتر أفقي مع العدد، والمختار ممتلئ بلون القسم (بارتفاع الشريحة الواحدة).
//   • إعادة تصميم الإدارة (U5، spec A.9/A.13): الشكل الجديد بمعامل صريح `style: .admin` في `DSSearchField` و`DSFilterChips`
//     (الافتراضي شكل اليوم — صفحات الأعضاء لا تتغيّر)، و`DSAdminChipLabel` + `DSChipFlow` + `DSNumber` يشاركها طقم
//     الفلاتر (`Views/Features/Admin/AdminFilterKit.swift`).
// والمحتوى تحتها بأقسام `DSComposerSection` وصفوف `.dsRowBox()` — مثل المربّعات تماماً.
// كل المقاسات والخطوط من DesignSystem.swift (`DS`، `DSBox`، `DS.TextRole`).

// MARK: - رقم في صفّ الأرقام

struct DSHeroStat: Identifiable {
    let id = UUID()
    let value: String
    let label: String
    var icon: String? = nil
}

// MARK: - بطاقة رقم حيّ

/// رقم كبير + عنوان + أيقونة بلون القسم — تُستخدم في شبكات الأرقام (٢ أو ٣ بالصف).
struct DSStatTile: View {
    let value: String
    let label: String
    let icon: String
    var tint: Color = DS.Color.primary
    /// شارة تنبيه صغيرة (مثل «جديد») — nil = بلا شارة
    var badge: String? = nil
    var action: (() -> Void)? = nil
    /// نسبة (٠…١) — حلقة مصغّرة موحّدة مكان الأيقونة (`DSRingValue`، الدفعة ١٠: كل نسبة بحلقة)
    var ring: Double? = nil
    @Environment(\.dsSection) private var section

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(DSScaleButtonStyle())
            } else {
                content
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                if let ring {
                    DSRingValue(progress: ring, tint: tint)
                        .frame(minWidth: DS.Icon.section, minHeight: DS.Icon.section, alignment: .leading)
                } else {
                    DSFieldIcon(name: icon, tint: tint)
                }
                Spacer(minLength: 0)
                if let badge {
                    let glyph = tint.dsChrome(in: section).dsReadableGlyph
                    Text(badge)
                        .dsFont(.badgeCompact)
                        .foregroundColor(glyph)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xxs)
                        .background(glyph.opacity(DS.Opacity.tintFill), in: Capsule())
                }
            }
            Text(value)
                .dsFont(.statValue)
                .foregroundColor(DS.Color.fieldLabel)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .dsFieldFont(.chip)
                .foregroundColor(DS.Color.fieldValue)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // البطاقة الواحدة (`.dsCard`) — كانت سطحاً وإطاراً وزوايا ١٦ يدوية
        .dsCard(padding: DS.Spacing.md)
        .contentShape(Rectangle())
    }
}

// MARK: - حقل بحث

/// شكل حقل البحث — يُمرَّر صراحةً (لا من البيئة: الصفحة المدفوعة لا ترث بيئة من دفعها)
enum DSSearchFieldStyle {
    /// شكل اليوم (٤٦، إطار رمادي خفيف) — صفحات الأعضاء (`DaughterSons`، …) وما لم يُرحَّل بعد
    case standard
    /// شريط فلاتر الإدارة (spec A.13): ٤٤، إطار `DS.Hub.frameStroke` على الأبيض، زاوية ١٢
    case admin
}

/// حقل بحث بسطر واحد بنفس إطار حقول المربّعات (يتلوّن عند الكتابة) + زر مسح ٤٤ نقطة
struct DSSearchField: View {
    @Binding var text: String
    var placeholder: String = L10n.t("بحث…", "Search…")
    var tint: Color = DS.Color.primary
    /// `.admin` = حقل شريط الفلاتر في الإدارة؛ الافتراضي شكل اليوم
    var style: DSSearchFieldStyle = .standard
    @FocusState private var focused: Bool
    @Environment(\.dsSection) private var section

    var body: some View {
        // الكحلي ← حبر القسم (الإطار والعدسة عند الكتابة)
        let tint = self.tint.dsChrome(in: section).dsReadableGlyph
        let admin = style == .admin
        return HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .dsGlyph(DS.Glyph.md, weight: .semibold)
                .foregroundColor(focused ? tint : DS.Color.textTertiary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .dsFieldFont(.fieldValue)
                .foregroundColor(DS.Color.textPrimary)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dsGlyph(DS.Glyph.lgCompact, weight: .regular)
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -DS.Spacing.sm)
                .accessibilityLabel(L10n.t("مسح البحث", "Clear search"))
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        // الإدارة: ٤٤ (`DS.Icon.tapTarget`) بإطار يُرى — spec A.13؛ غيرها كما كان
        .frame(minHeight: admin ? DS.Icon.tapTarget : DSBox.searchHeight)
        .dsFocusFieldBox(focused: focused, tint: tint, fill: DS.Color.surface,
                         idleStroke: admin ? DS.Hub.frameStroke : nil)
    }
}

// MARK: - شريط فلاتر

struct DSFilterOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    var icon: String? = nil
    var count: Int? = nil
}

/// شكل شريط الفلاتر — يُمرَّر صراحةً (لا من البيئة: الصفحة المدفوعة لا ترث بيئة من دفعها)
enum DSFilterChipsStyle {
    /// شكل اليوم: صفّ أفقي يتمرّر، المختار ممتلئ بتدرّج القسم — كل الاستدعاءات الحالية وما لم يُرحَّل بعد
    case standard
    /// الإدارة (spec A.9 الاستعمال ١، صفّ فلتر بُعد واحد): تلتفّ لسطر ثانٍ ولا تتمرّر جانبياً، تُرسم ٣٦ ولمسها ٤٤،
    /// إطار `frameStroke` على الأبيض، والمختارة كحلية بـ✓ قبل الاسم والعدد ذهبي
    case admin
}

/// فلاتر أفقية: المختار ممتلئ بلون القسم، والباقي بإطار خفيف — بارتفاع الشريحة الواحدة ومساحة ضغط ٤٤
struct DSFilterChips<ID: Hashable>: View {
    let options: [DSFilterOption<ID>]
    @Binding var selection: ID
    var tint: Color = DS.Color.primary
    /// `.admin` = شرائح الإدارة الملتفّة؛ الافتراضي شكل اليوم
    var style: DSFilterChipsStyle = .standard
    /// `.admin` بشكل فلاتر «العائلة» (`DSAdminChipLabel(compact: true)`: ٣٠ وبلا ✓، لمسها ٤٤) — «الوارد» (٢٠٢٦-١١-٢٨)
    var compact: Bool = false
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dsSection) private var section

    var body: some View {
        switch style {
        case .standard: standardBody
        case .admin: adminBody
        }
    }

    /// شرائح الإدارة: تلتفّ (`DSChipFlow`)، كل شريحة زرّ بعلامة «مختار» للقارئ الصوتي
    private var adminBody: some View {
        DSChipFlow {
            ForEach(options) { option in
                let selected = option.id == selection
                Button {
                    guard !selected else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(reduceMotion ? nil : DS.Anim.snappy) {
                        selection = option.id
                    }
                } label: {
                    DSAdminChipLabel(title: option.title,
                                     count: option.count.map { DSNumber.grouped($0) },
                                     icon: option.icon,
                                     selected: selected,
                                     compact: compact)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var standardBody: some View {
        // المختار ممتلئ بتدرّج القسم (DSActionFill)، وعدد غير المختار بحبره
        let tint = self.tint.dsChrome(in: section).dsReadableGlyph
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(options) { option in
                    let selected = option.id == selection
                    Button {
                        guard !selected else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) {
                            selection = option.id
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            if let icon = option.icon {
                                Image(dsSymbol: icon).dsGlyph(DS.Glyph.smCompact)
                            }
                            Text(option.title).dsFont(.sectionTitle)
                            if let count = option.count {
                                Text("\(count)")
                                    .dsFont(.badge)
                                    .monospacedDigit()
                                    .padding(.horizontal, DS.Spacing.xsm)
                                    .padding(.vertical, DS.Border.width)
                                    .background((selected ? DS.Color.textOnPrimary : tint)
                                                    .opacity(selected ? DS.Opacity.tintFillStrong : DS.Opacity.tintFill),
                                                in: Capsule())
                            }
                        }
                        .foregroundColor(selected ? DS.Color.textOnPrimary : DS.Color.textSecondary)
                        .padding(.horizontal, DSBox.chipPadding)
                        // ارتفاع الشريحة الواحدة (`DSBox.chipHeight`) — كان ٣٦
                        .frame(minHeight: DSBox.chipHeight)
                        .background {
                            if selected {
                                Capsule().fill(DSActionFill.style())
                                    .matchedGeometryEffect(id: "chip", in: ns)
                            } else {
                                Capsule().strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke),
                                                       lineWidth: DS.Border.width)
                            }
                        }
                        .padding(.vertical, (DS.Icon.tapTarget - DSBox.chipHeight) / 2)   // مساحة ضغط ٤٤
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, DS.Border.width)
        }
    }
}

// MARK: - شريحة الإدارة (spec A.9، U5)

/// شكل شريحة الإدارة الواحد — لصفّ الفلتر (`DSFilterChips(style: .admin)`) ولشرائح الفلاتر المفعّلة
/// (`AdminActiveFilterChips`): تُرسم ٣٦ (`DS.Hub.filterChipHeight`) ولمسها ٤٤، كبسولة، ١٣ متوسط، إطار `frameStroke`
/// على الأبيض. المختارة: تعبئة القسم الكحلية بنص أبيض و✓ ١٢ قبل الاسم (اللون ليس الإشارة الوحيدة) والعدد ذهبي.
/// `removable`: ✕ في الطرف — الشريحة تلغي فلترها. الاسم الطويل مع الخط الكبير يلتفّ لسطرين ولا يُقصّ.
struct DSAdminChipLabel: View {
    let title: String
    /// العدد منسّقاً («2,362» أو «—») — nil = بلا عدد
    var count: String? = nil
    var icon: String? = nil
    var selected: Bool
    var removable: Bool = false
    /// شريحة الفلتر المفعّل: أصغر وبلا ✓ (طلب المالك ٢٠٢٦-١١-٢٧) — الكحلي و✕ تكفيان علامةً
    var compact: Bool = false
    @Environment(\.dsSection) private var section
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // تعبئة القسم الكحلية (`primaryFill` في الإدارة) — النص الأبيض ≥ ٦:١ في الوضعين
        let fill = section?.fill ?? DS.Color.primaryFill
        // العدد ذهبي على الكحلي (spec A.9)؛ في الداكن التعبئة أفتح (#2B5F90) فالذهبي ٢٫٥:١ — الذهبي الفاتح ٤٫٥:١
        let countOnFill = scheme == .dark ? DS.Hub.rolePillInk : DS.Color.accentLight
        let height = compact ? DS.Hub.activeFilterChipHeight : DS.Hub.filterChipHeight
        let shape = RoundedRectangle(cornerRadius: height / 2, style: .continuous)
        return HStack(spacing: compact ? DS.Spacing.xs : DS.Spacing.xsm) {
            if selected && !compact {
                Image(systemName: "checkmark")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .accessibilityHidden(true)
            } else if let icon {
                Image(dsSymbol: icon)
                    .dsGlyph(DS.Glyph.smCompact)
                    .accessibilityHidden(true)
            }
            Text(title)
                .dsFont(.chip)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let count {
                Text(verbatim: count)
                    .dsFont(.chip)
                    .monospacedDigit()
                    .foregroundColor(selected ? countOnFill : DS.Color.textTertiary)
            }
            if removable {
                Image(systemName: "xmark")
                    .dsGlyph(DS.Glyph.xs, weight: .semibold)
                    .foregroundColor(selected ? DS.Hub.onBandMuted : DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .foregroundColor(selected ? DS.Color.textOnPrimary : DS.Color.textPrimary)
        .padding(.horizontal, compact ? DS.Spacing.sm : DS.Spacing.md)
        .padding(.vertical, compact ? DS.Spacing.xxs : DS.Spacing.xs)
        .frame(minHeight: height)
        .background(shape.fill(selected ? fill : DS.Color.surface))
        .overlay(shape.strokeBorder(selected ? fill : DS.Hub.frameStroke, lineWidth: DS.Border.width))
        // مساحة ضغط ٤٤ تدخل في التخطيط: السطران الملتفّان يبعدان ٨ مرسومة و٠ بين مساحتي اللمس
        .padding(.vertical, (DS.Icon.tapTarget - height) / 2)
        .contentShape(Rectangle())
    }
}

// MARK: - التفاف الشرائح

/// صفّ شرائح يلتفّ لسطر جديد عند امتلاء العرض — لا تمرير جانبي ولا قصّ (ui-ux-pro-max «Chip Collection Reflow»).
/// الترتيب من الطرف البادئ (SwiftUI يعكس التخطيط المخصّص في العربية). شريحة أعرض من السطر تُعطى عرضه فيلتفّ نصّها.
struct DSChipFlow: Layout {
    var spacing: CGFloat = DS.Spacing.xsm
    /// بين السطرين — ٠ لأن كل شريحة تحمل مساحة لمسها (٤٤) فوق رسمها (٣٦)
    var lineSpacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(maxWidth: bounds.width, subviews: subviews).frames
        for (index, frame) in frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                  proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            var size = view.sizeThatFits(.unspecified)
            if maxWidth.isFinite, size.width > maxWidth {
                size = view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                size.width = min(size.width, maxWidth)
            }
            if x > 0, x + size.width > maxWidth {
                y += line + lineSpacing
                x = 0
                line = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: maxWidth.isFinite ? maxWidth : widest, height: y + line), frames)
    }
}

// MARK: - الأرقام

/// أرقام اللوحة: لاتينية بفاصل الآلاف («2,362») — spec A.10
enum DSNumber {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()

    static func grouped(_ n: Int) -> String {
        formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// لم يُحمَّل بعد = «—» (لا صفر أبداً) — spec A.10
    static func groupedOrDash(_ n: Int?) -> String {
        n.map { grouped($0) } ?? "—"
    }
}

// MARK: - صندوق حقل يتلوّن عند الكتابة (دفعة 3-B «أسلوب واحد»، ٢٠٢٦-١٠-٠٧)

/// إطار صندوق الحقل في الصفحات (حقل البحث، محرّر نص متعدد الأسطر، حقل الرد، نطاق العمر): سطح + إطار
/// خفيف، ويتلوّن بلون الصفحة عند الكتابة، ويحمرّ عند خطأ — كان منسوخاً باليد في ٥ صفحات بنفس الأرقام.
struct DSFocusFieldBox: ViewModifier {
    var focused: Bool
    var tint: Color = DS.Color.primary
    var invalid: Bool = false
    var fill: Color = DS.Color.background
    var radius: CGFloat = DS.Radius.md
    /// إطار الحقل وهو ساكن — nil = الرمادي الخفيف كما كان؛ حقل بحث الإدارة يمرّر `DS.Hub.frameStroke` (spec A.13)
    var idleStroke: Color? = nil
    @Environment(\.dsSection) private var section

    func body(content: Content) -> some View {
        let ink = tint.dsChrome(in: section).dsReadableGlyph
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let stroke: Color = invalid ? DS.Color.error.opacity(DS.Opacity.selectedStroke)
            : focused ? ink.opacity(DS.Opacity.selectedStroke)
            : idleStroke ?? DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke)
        return content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(stroke, lineWidth: focused ? DS.Border.widthBold : DS.Border.width))
            .animation(.easeInOut(duration: 0.2), value: focused)
    }
}

extension View {
    /// صندوق الحقل الموحّد في الصفحات — `.dsFocusFieldBox(focused: isFocused, tint: pageTint)`
    func dsFocusFieldBox(focused: Bool, tint: Color = DS.Color.primary, invalid: Bool = false,
                         fill: Color = DS.Color.background, radius: CGFloat = DS.Radius.md,
                         idleStroke: Color? = nil) -> some View {
        modifier(DSFocusFieldBox(focused: focused, tint: tint, invalid: invalid, fill: fill, radius: radius,
                                 idleStroke: idleStroke))
    }
}
