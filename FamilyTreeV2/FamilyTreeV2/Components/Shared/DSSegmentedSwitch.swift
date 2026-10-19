import SwiftUI

// MARK: - مبدّل أقسام كبير مرتّب (طلب المالك ٢٠٢٦-٠٩-٢٧)
//
// إطار واضح يضم الأزرار بعرض وارتفاع متساويين: المختار ممتلئ بتدرّج الإجراء (لون القسم) ونصّه أبيض،
// والباقي هادئ؛ والعدد شارة صغيرة (حمراء على غير المختار = فيه جديد هناك).
// يُستخدم في «الإشعارات | المستجدات» وفي علامة المعلومات «عن التطبيق | التعليمات».

struct DSSegmentOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let icon: String
    var count: Int? = nil
}

/// مقاس المبدّل — مكان واحد (طلب المالك ٢٠٢٦-١٠-٠٧ «أي شي حجمه صار كبير تردّه حجمه السابق»)
enum DSSegmentSize {
    /// ٤٤ + رمز، ويملأ العرض — «الإشعارات | المستجدات»، «عن التطبيق | التعليمات»
    case large
    /// ٣٢، نص ١٣ عريض ورمز صغير، ويملأ العرض — الفلاتر داخل الصفحات (كانت المبدّل المقسّم للنظام ~٣٢)
    case regular
    /// ٣٠، نص ١١ عريض بلا رمز، بعرض نصّه — تبويب الشجرة [شجرة العائلة / النساء] في شريط أدواتها
    case compact
}

struct DSSegmentedSwitch<ID: Hashable>: View {
    let options: [DSSegmentOption<ID>]
    @Binding var selection: ID
    var size: DSSegmentSize = .large
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// المختار بتدرّج القسم (DSActionFill) وظلّه بلونه
    @Environment(\.dsSection) private var section

    init(options: [DSSegmentOption<ID>], selection: Binding<ID>, size: DSSegmentSize = .large) {
        self.options = options
        self._selection = selection
        self.size = size
    }

    // المقاسات من `DSBox.segment*` و`DS.TextRole.segment*`
    private var height: CGFloat {
        switch size {
        case .large: return DSBox.segmentHeight
        case .regular: return DSBox.segmentHeightRegular
        case .compact: return DSBox.segmentHeightCompact
        }
    }
    private var inset: CGFloat { size == .large ? DSBox.segmentPadding : DSBox.segmentPaddingSmall }
    private var role: DS.TextRole {
        switch size {
        case .large: return .segment
        case .regular: return .segmentRegular
        case .compact: return .segmentCompact
        }
    }
    private var glyph: CGFloat { size == .large ? DS.Glyph.md : DS.Glyph.sm }

    var body: some View {
        let bar = HStack(spacing: size == .compact ? DS.Spacing.xxs : DS.Spacing.xs) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(inset)
        // دائري الأطراف (كبسولة — طلب المالك)
        .background(Capsule().fill(DS.Color.surface))
        .overlay(Capsule()
            .strokeBorder(DS.Color.textTertiary.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 1))
        .shadow(color: .black.opacity(colorScheme == .dark || size == .compact ? 0 : 0.05), radius: 8, x: 0, y: 3)
        if size == .compact {
            // بعرض نصّه، ويتبع «حجم النص» في الجهاز (طلب المالك ٢٠٢٦-١٠-٠٨) بسقف لا يدفع أزرار شريط الشجرة
            bar.fixedSize().dynamicTypeSize(...DynamicTypeSize.xLarge)
        } else {
            bar.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    private func segment(_ option: DSSegmentOption<ID>) -> some View {
        let selected = option.id == selection
        return Button {
            guard !selected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.8)) {
                selection = option.id
            }
        } label: {
            HStack(spacing: DS.Spacing.xsm) {
                if size != .compact {
                    // رمز النظام أو المخصّص من الأصول (ن-١ فحص ٢٠٢٦-١٠-٠٧)
                    Image(dsSymbol: option.icon)
                        .dsGlyph(glyph)
                        .accessibilityHidden(true)
                }
                Text(option.title)
                    .dsFont(role)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let count = option.count, count > 0 {
                    Text("\(count)")
                        .dsFont(.badge)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textOnPrimary)
                        .padding(.horizontal, DS.Spacing.xsm)
                        .frame(minWidth: DS.Icon.countBadge, minHeight: DSBox.chipHeightMini)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.25) : DS.Color.errorFill))
                }
            }
            .foregroundColor(selected ? .white : DS.Color.textSecondary)
            .padding(.horizontal, size == .compact ? DS.Spacing.sm : 0)
            .frame(maxWidth: size == .compact ? nil : .infinity)
            // حدّ أدنى — يطول مع «حجم النص» في الجهاز بدل أن يُقصّ النص (فحص ٢٠٢٦-١٠-٠٨)
            .frame(minHeight: height)
            .background {
                if selected {
                    Capsule()
                        .fill(DSActionFill.style())
                        .shadow(color: DS.Color.actionNavy.dsChromeFill(in: section)
                                    .opacity(colorScheme == .dark || size == .compact ? 0 : 0.28),
                                radius: 6, x: 0, y: 3)
                        .matchedGeometryEffect(id: "thumb", in: ns)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.count.map { $0 > 0 ? "\(option.title)، \($0)" : option.title } ?? option.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
