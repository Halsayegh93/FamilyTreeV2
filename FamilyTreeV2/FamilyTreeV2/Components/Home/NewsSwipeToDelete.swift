import SwiftUI

/// إجراء واحد يظهر عند سحب بطاقة
struct DSSwipeAction: Identifiable {
    var id: String { title }
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
}

/// سحب بطاقة لكشف إجراءاتها — موحّد للأخبار والرسائل (طلب المالك)، بموضع فيزيائي ثابت بلا انعكاس RTL:
/// السحب صوب اليمين (الإصبع من اليسار لليمين) يكشف الإجراءات متجاورة على اليسار
/// (الأول على الحافة الخارجية). السحب صوب اليسار لا يحرّك البطاقة، ولا ينفّذ السحب الكامل شيئاً تلقائياً.
/// بطاقة واحدة مفتوحة فقط: بدء سحب بطاقة أخرى يغلق السابقة.
///
/// بديل عن `.swipeActions` الذي لا يعمل خارج `List` ويعكس اتجاهه في الواجهة العربية.
struct DSSwipeActionsModifier: ViewModifier {
    /// معرّف البطاقة — لإغلاق إجراءات أي بطاقة أخرى عند فتح هذه
    let id: UUID
    let actions: [DSSwipeAction]

    @Environment(\.layoutDirection) private var layoutDirection
    @State private var offset: CGFloat = 0
    @State private var baseOffset: CGFloat = 0
    @State private var isHorizontal: Bool? = nil

    private let buttonWidth: CGFloat = 80
    /// عرض الكشف = عدد الأزرار
    private var reveal: CGFloat { buttonWidth * CGFloat(actions.count) }

    func body(content: Content) -> some View {
        if actions.isEmpty {
            content
        } else {
            content
                // المحتوى بلغته الأصلية؛ الحاوية وحدها بإحداثيات فيزيائية (يسار→يمين)
                .environment(\.layoutDirection, layoutDirection)
                .offset(x: offset)
                .background(alignment: .leading) {
                    if offset > 0 {
                        HStack(spacing: 6) {
                            ForEach(actions) { a in
                                actionButton(a)
                            }
                        }
                    }
                }
                .simultaneousGesture(drag)
                // فتح إجراءات بطاقة أخرى يغلق إجراءات هذه
                .onReceive(NotificationCenter.default.publisher(for: .newsSwipeOpened)) { note in
                    if (note.object as? UUID) != id, offset != 0 { close() }
                }
                .environment(\.layoutDirection, .leftToRight)
        }
    }

    private func actionButton(_ a: DSSwipeAction) -> some View {
        Button {
            close()
            a.action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: a.icon)
                    .font(DS.Font.scaled(18, weight: .bold))
                Text(a.title)
                    .font(DS.Font.scaled(12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(.white)
            .frame(width: buttonWidth - 6)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(a.color)
            )
        }
        .buttonStyle(.plain)
        .opacity(min(1, abs(offset) / reveal))
        .accessibilityLabel(a.title)
    }

    /// اتجاه واحد: لليمين فقط
    private func clamp(_ x: CGFloat) -> CGFloat { max(0, x) }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                // نحسم الاتجاه أول مرة: أفقي → سحب البطاقة، عمودي → نترك التمرير
                if isHorizontal == nil { isHorizontal = abs(dx) > abs(dy) * 1.3 }
                guard isHorizontal == true else { return }
                // أول حركة سحب على هذه البطاقة → أغلق المفتوح في غيرها
                if offset == 0 {
                    NotificationCenter.default.post(name: .newsSwipeOpened, object: id)
                }
                let raw = clamp(baseOffset + dx)
                // مقاومة خفيفة بعد مسافة الكشف
                offset = raw <= reveal ? raw : reveal + (raw - reveal) * 0.35
            }
            .onEnded { value in
                defer { isHorizontal = nil }
                guard isHorizontal == true else { return }
                let raw = clamp(baseOffset + value.translation.width)
                if raw > reveal * 0.4 {
                    withAnimation(DS.Anim.snappy) { offset = reveal }
                    baseOffset = offset
                } else {
                    close()
                }
            }
    }

    private func close() {
        withAnimation(DS.Anim.snappy) { offset = 0 }
        baseOffset = 0
    }
}

extension Notification.Name {
    /// فُتحت إجراءات بطاقة — object: معرّف البطاقة
    static let newsSwipeOpened = Notification.Name("newsSwipeOpened")
}

extension View {
    func dsSwipeActions(id: UUID, actions: [DSSwipeAction]) -> some View {
        modifier(DSSwipeActionsModifier(id: id, actions: actions))
    }

    /// أخبار: «حذف» (للإدارة وصاحب الخبر) ثم «إبلاغ» (لغير صاحبه)
    func newsSwipeActions(
        id: UUID,
        canDelete: Bool,
        canReport: Bool,
        onDelete: @escaping () -> Void,
        onReport: @escaping () -> Void
    ) -> some View {
        var actions: [DSSwipeAction] = []
        if canDelete {
            actions.append(DSSwipeAction(icon: "trash.fill", title: L10n.t("حذف", "Delete"),
                                         color: DS.Color.error, action: onDelete))
        }
        if canReport {
            actions.append(DSSwipeAction(icon: "flag.fill", title: L10n.t("إبلاغ", "Report"),
                                         color: DS.Color.warning, action: onReport))
        }
        return dsSwipeActions(id: id, actions: actions)
    }
}
