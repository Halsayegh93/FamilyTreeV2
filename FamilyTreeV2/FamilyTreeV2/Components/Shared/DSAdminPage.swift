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

/// حقل بحث بسطر واحد بنفس إطار حقول المربّعات (يتلوّن عند الكتابة) + زر مسح ٤٤ نقطة
struct DSSearchField: View {
    @Binding var text: String
    var placeholder: String = L10n.t("بحث…", "Search…")
    var tint: Color = DS.Color.primary
    @FocusState private var focused: Bool
    @Environment(\.dsSection) private var section

    var body: some View {
        // الكحلي ← حبر القسم (الإطار والعدسة عند الكتابة)
        let tint = self.tint.dsChrome(in: section).dsReadableGlyph
        return HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .dsGlyph(DS.Glyph.md, weight: .semibold)
                .foregroundColor(focused ? tint : DS.Color.textTertiary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .dsFieldFont(.body)
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
        .frame(minHeight: DSBox.searchHeight)
        .dsFocusFieldBox(focused: focused, tint: tint, fill: DS.Color.surface)
    }
}

// MARK: - شريط فلاتر

struct DSFilterOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    var icon: String? = nil
    var count: Int? = nil
}

/// فلاتر أفقية: المختار ممتلئ بلون القسم، والباقي بإطار خفيف — بارتفاع الشريحة الواحدة ومساحة ضغط ٤٤
struct DSFilterChips<ID: Hashable>: View {
    let options: [DSFilterOption<ID>]
    @Binding var selection: ID
    var tint: Color = DS.Color.primary
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dsSection) private var section

    var body: some View {
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

// MARK: - صندوق حقل يتلوّن عند الكتابة (دفعة 3-B «أسلوب واحد»، ٢٠٢٦-١٠-٠٧)

/// إطار صندوق الحقل في الصفحات (حقل البحث، محرّر نص متعدد الأسطر، حقل الرد، نطاق العمر): سطح + إطار
/// خفيف، ويتلوّن بلون الصفحة عند الكتابة، ويحمرّ عند خطأ — كان منسوخاً باليد في ٥ صفحات بنفس الأرقام.
struct DSFocusFieldBox: ViewModifier {
    var focused: Bool
    var tint: Color = DS.Color.primary
    var invalid: Bool = false
    var fill: Color = DS.Color.background
    var radius: CGFloat = DS.Radius.md
    @Environment(\.dsSection) private var section

    func body(content: Content) -> some View {
        let ink = tint.dsChrome(in: section).dsReadableGlyph
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let stroke: Color = invalid ? DS.Color.error.opacity(DS.Opacity.selectedStroke)
            : focused ? ink.opacity(DS.Opacity.selectedStroke)
            : DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke)
        return content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(stroke, lineWidth: focused ? DS.Border.widthBold : DS.Border.width))
            .animation(.easeInOut(duration: 0.2), value: focused)
    }
}

extension View {
    /// صندوق الحقل الموحّد في الصفحات — `.dsFocusFieldBox(focused: isFocused, tint: pageTint)`
    func dsFocusFieldBox(focused: Bool, tint: Color = DS.Color.primary, invalid: Bool = false,
                         fill: Color = DS.Color.background, radius: CGFloat = DS.Radius.md) -> some View {
        modifier(DSFocusFieldBox(focused: focused, tint: tint, invalid: invalid, fill: fill, radius: radius))
    }
}
