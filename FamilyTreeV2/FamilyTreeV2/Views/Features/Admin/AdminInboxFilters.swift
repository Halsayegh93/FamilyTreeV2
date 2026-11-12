import SwiftUI

// MARK: - أقسام «الوارد» وفلاترها (التصميم المعتمد ٢٠٢٦-١١-١١، العيّنة inbox-tabs/sample.png «المقترح»)
//
// ١) في الرأس الكحلي مسار اختيار واحد بثلاثة أقسام (شكل `DSChoiceTiles` على الرأس): «الطلبات» بعددها ·
//    «تمت معالجتها» · «الرسائل» بعدد غير المقروء (أحمر) — «الرسائل» لمن يراها في جدول السيرفر فقط.
// ٢) تحت البحث صفّ شرائح واحد يلتفّ: «كل الطلبات N» أولاً، ثم فلاتر المسار («بانتظار قرارك» كهرماني، «عاجل»،
//    «متأخر» أحمر) حين تنطبق، ثم المجموعات بأعدادها. المسار والمجموعة يجتمعان (كما كانا)، والضغط على المختارة
//    يلغيها. المالك قد يراجع هذه الفلاتر لاحقاً — كلها هنا (العناصر تُبنى في `AdminAllRequestsView.inboxFilterItems`).

/// قسم في مسار الرأس
struct AdminInboxSegmentOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    /// العدد في الشارة — nil = بلا شارة
    var count: Int? = nil
    /// شارة حمراء (غير المقروء)
    var alert: Bool = false
}

/// مسار اختيار خفيف على الرأس الكحلي: مسار شفاف، والمختار حبّة بيضاء بنصّ كحلي (بأحجام الوصول فوق بعض)
struct AdminInboxSegmentTrack<ID: Hashable>: View {
    let options: [AdminInboxSegmentOption<ID>]
    @Binding var selection: ID
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        let stack = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 0))
            : AnyLayout(HStackLayout(spacing: 0))
        stack { ForEach(options) { segment($0) } }
            .padding(DSBox.choiceTrackInset)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Hub.glass))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Hub.glassLine, lineWidth: DS.Border.width))
    }

    private func segment(_ option: AdminInboxSegmentOption<ID>) -> some View {
        let selected = option.id == selection
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md - DSBox.choiceTrackInset, style: .continuous)
        return Button {
            guard !selected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) { selection = option.id }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Text(option.title)
                    .dsFieldFont(.fieldValue)
                    .fontWeight(selected ? .semibold : .regular)
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.8)
                if let count = option.count, count > 0 {
                    Text(verbatim: "\(count)")
                        .dsFont(.badge)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textOnPrimary)
                        .padding(.horizontal, DS.Spacing.xsm)
                        .frame(minWidth: DS.Icon.inline + DS.Spacing.xs, minHeight: DS.Icon.inline + DS.Spacing.xs)
                        .background(Capsule().fill(option.alert ? DS.Color.errorFill
                                                   : (selected ? DS.Color.brandFill : DS.Hub.glassLine)))
                }
            }
            .foregroundColor(selected ? DS.Color.brand : DS.Hub.onBandMuted)
            .padding(.horizontal, DS.Spacing.sm)
            .frame(maxWidth: .infinity)
            .frame(minHeight: DSBox.choiceTrackHeight)
            .background {
                if selected {
                    shape.fill(Color.white)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsTapArea(width: DS.Icon.tapTarget, height: DSBox.choiceTrackHeight)
        .accessibilityLabel(option.count.map { "\(option.title) \($0)" } ?? option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// شريحة في صفّ الفلاتر الواحد
struct AdminInboxFilterItem: Identifiable {
    enum Tone { case neutral, amber, red }
    let id: String
    let title: String
    var count: Int? = nil
    var icon: String? = nil
    var tone: Tone = .neutral
    let selected: Bool
    let action: () -> Void
}

/// صفّ فلاتر واحد يلتفّ (بدل صفّين بـ«الكل» مرتين): المختارة كحلية ممتلئة، والباقية رمادية فاتحة —
/// «بانتظار قرارك» كهرمانية و«متأخر» حمراء حين لا تُختار
struct AdminInboxFilterRow: View {
    let items: [AdminInboxFilterItem]
    @Environment(\.dsSection) private var section

    var body: some View {
        NotifFlow(spacing: DS.Spacing.sm) {
            ForEach(items) { chip($0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("فلاتر الطلبات", "Request filters"))
    }

    private func chip(_ item: AdminInboxFilterItem) -> some View {
        let toneInk: Color = {
            switch item.tone {
            case .neutral: return DS.Color.textSecondary
            case .amber: return DS.Color.warning.dsReadableGlyph
            case .red: return DS.Color.error.dsReadableGlyph
            }
        }()
        let toneFill: Color = {
            switch item.tone {
            case .neutral: return DS.Color.fieldFill
            case .amber: return DS.Color.warning.opacity(DS.Opacity.tintFill)
            case .red: return DS.Color.error.opacity(DS.Opacity.tintFill)
            }
        }()
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            item.action()
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                if let icon = item.icon {
                    Image(dsSymbol: icon).dsGlyph(DS.Glyph.smCompact)
                }
                Text(item.title).dsFont(.chip)
                if let count = item.count {
                    Text(verbatim: "\(count)")
                        .dsFont(.badge)
                        .monospacedDigit()
                }
            }
            .lineLimit(1)
            .foregroundColor(item.selected ? DS.Color.textOnPrimary : toneInk)
            .padding(.horizontal, DSBox.chipPadding)
            .frame(minHeight: DSBox.chipHeight)
            .background(Capsule().fill(item.selected ? AnyShapeStyle(DSActionFill.style()) : AnyShapeStyle(toneFill)))
            .padding(.vertical, (DS.Icon.tapTarget - DSBox.chipHeight) / 2)   // مساحة ضغط ٤٤
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.count.map { "\(item.title) \($0)" } ?? item.title)
        .accessibilityAddTraits(item.selected ? .isSelected : [])
    }
}
