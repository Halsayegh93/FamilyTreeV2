import SwiftUI

// MARK: - مبدّل أقسام كبير مرتّب (طلب المالك ٢٠٢٦-٠٩-٢٧)
//
// إطار واضح يضم الأزرار بعرض وارتفاع متساويين: المختار ممتلئ بكحلي الإجراء ونصّه أبيض،
// والباقي هادئ؛ والعدد شارة صغيرة (حمراء على غير المختار = فيه جديد هناك).
// يُستخدم في «الإشعارات | المستجدات» وفي علامة المعلومات «عن التطبيق | التعليمات».

struct DSSegmentOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let icon: String
    var count: Int? = nil
}

struct DSSegmentedSwitch<ID: Hashable>: View {
    let options: [DSSegmentOption<ID>]
    @Binding var selection: ID
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(4)
        // دائري الأطراف (كبسولة — طلب المالك)
        .background(Capsule().fill(DS.Color.surface))
        .overlay(Capsule()
            .strokeBorder(DS.Color.textTertiary.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 1))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 8, x: 0, y: 3)
        .dynamicTypeSize(...DynamicTypeSize.large)
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
            HStack(spacing: 6) {
                Image(systemName: option.icon)
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityHidden(true)
                Text(option.title)
                    .font(DS.Font.plex(14.5, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let count = option.count, count > 0 {
                    Text("\(count)")
                        .font(DS.Font.plex(11, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 18)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.25) : DS.Color.error))
                }
            }
            .foregroundColor(selected ? .white : DS.Color.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                if selected {
                    Capsule()
                        .fill(DSActionFill.style())
                        .shadow(color: DS.Color.actionNavy.opacity(colorScheme == .dark ? 0 : 0.28), radius: 6, x: 0, y: 3)
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
