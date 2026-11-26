import SwiftUI

// MARK: - صفوف «إشعارات الإدارة» (إعادة تصميم الإدارة ٢٠٢٦-١١-٢٦، الوحدة U18 — spec A.6/C.15، mock 11)
//
// كان خطّاً زمنياً بنقاط ملوّنة (اختيار ٢٠٢٦-١١-٠٦). صار قوائم اللوحة الواحدة: كل قسم («يحتاج إجراء الآن»، اليوم، أمس…)
// بطاقة بيضاء من صفوفها (`dsGroupedRow` — كل صفّ جزؤه، فيبقى السحب والتحديد لكل صفّ)، والصفّ:
//   [مربّع النوع ٣٠ ممتلئ] العنوان ١٥ (غير المقروء متوسط + نقطة ذهبية) ……… الوقت [›]
//                          النص ١٣ رمادي · ما تغيّر · مَن فعل [الحالة]
//                          [الملف] [تنبيه] · [شحن الرصيد]
// في «يحتاج إجراء الآن» زرّ البيت الواحد كحلي في طرف الصفّ («إعلان» · «مراجعة» · «راجع» · «شحن الرصيد») — تحت النص من
// أحجام إمكانية الوصول. الأزرار عناصر مستقلة للقارئ الصوتي، والنص عنصر واحد بإجراءاته («مقروء»، «حذف»).
// كل جزء نوع صغير مستقل (حارس المكدس).

/// نوع الإشعار بالكلام للقارئ الصوتي (طلب · إضافة · تعديل · نظام)
enum AdminNoticeTone: Equatable {
    case request, add, edit, system

    var spoken: String {
        switch self {
        case .request: return L10n.t("طلب", "Request")
        case .add:     return L10n.t("إضافة", "Addition")
        case .edit:    return L10n.t("تعديل", "Edit")
        case .system:  return L10n.t("نظام", "System")
        }
    }

    /// نوع الإشعار من فئته ونوعه
    static func of(_ n: AppNotification, _ category: AdminNotices.Category) -> AdminNoticeTone {
        switch category {
        case .system: return .system
        case .action: return AdminNotices.securityKinds.contains(n.kind) ? .system : .request
        case .changes, .team:
            if n.details?.selfChild == true || n.details?.action == "add" { return .add }
            let addKinds: Set<String> = [
                "member_add", NotificationKind.womenAdd.rawValue, NotificationKind.adminEditChildAdd.rawValue,
                NotificationKind.joinApproved.rawValue, NotificationKind.accountActivated.rawValue,
            ]
            return addKinds.contains(n.kind) ? .add : .edit
        }
    }
}

/// إجراءات الإشعار — السحب والضغط المطوّل والقارئ الصوتي نفسها (spec A.15)
enum AdminNoticeRowAction: String, Identifiable, Hashable {
    case read, delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .read:   return L10n.t("مقروء", "Read")
        case .delete: return L10n.t("حذف", "Delete")
        }
    }

    var icon: String {
        switch self {
        case .read:   return "envelope.open.fill"
        case .delete: return "trash.fill"
        }
    }
}

/// صفّ في بطاقة قسمه
struct AdminNoticeListRow: View {
    let item: AdminNoticeItem
    let position: DSGroupPosition
    /// قسم «يحتاج إجراء الآن»: زرّ البيت كحلي في الطرف والوقت نسبي («قبل 3 ساعات»)؛ صفوف الأيام بساعتها («9:05 ص»)
    let now: Bool
    let selecting: Bool
    let picked: Bool
    var actions: [AdminNoticeRowAction] = []
    let onTap: () -> Void
    var perform: (AdminNoticeRowAction) -> Void = { _ in }
    var onSelfChild: ((AdminSelfChildAction, AdminNoticeSelfChild) -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    private var showsCircle: Bool { selecting && item.notificationId != nil }
    /// «تمت إضافة ابن» (لا باقي «تغييرات الأعضاء» — تنبيهها في التفاصيل)
    private var child: AdminNoticeSelfChild? { item.selfChild.flatMap { $0.isGeneral ? nil : $0 } }
    /// زرّ البيت في طرف الصفّ (لا تحته)
    private var sidePill: Bool { now && item.button != nil && !typeSize.isAccessibilitySize }
    private var hasPills: Bool { !selecting && ((child != nil && onSelfChild != nil) || (item.button != nil && !sidePill)) }
    /// سهم ‹ حين يكون الضغط هو الإجراء الوحيد (يفتح التفاصيل)
    private var showsChevron: Bool {
        !selecting && !now && item.notificationId != nil && item.button == nil && child == nil
    }

    var body: some View {
        HStack(alignment: now ? .center : .top, spacing: DSNoticeMetrics.gap) {
            leading
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                AnyView(textBlock)
                if hasPills { AnyView(pills) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if sidePill, !selecting, let homePill {
                homePill
            }
        }
        .padding(.horizontal, DSNoticeMetrics.paddingH)
        .padding(.vertical, DSNoticeMetrics.paddingV)
        .frame(maxWidth: .infinity, minHeight: DS.Hub.rowMinHeightTwoLines, alignment: .leading)
        .dsGroupedRow(position, radius: DS.Hub.cardRadius,
                      dividerInset: DSNoticeMetrics.dividerInset(icon: DS.Hub.iconSquare, selecting: showsCircle),
                      highlight: selecting && picked ? AppSection.admin.ink.opacity(DS.Opacity.tintFill) : nil)
    }

    private var leading: some View {
        HStack(spacing: DSNoticeMetrics.selectGap) {
            if showsCircle {
                DSNoticeSelectCircle(picked: picked, tint: AppSection.admin.ink)
            }
            AdminIconSquare(symbol: item.icon, tint: item.tint, filled: true)
        }
    }

    // MARK: النص

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: DSNoticeMetrics.lineGap) {
            titleLine
            if !item.subtitle.isEmpty {
                // الحالة المشتقة (الآن) نصّها كاملاً حتى ٣ أسطر، والإشعار سطران أقصى
                Text(verbatim: item.subtitle)
                    .dsFont(.subtitle)
                    .foregroundColor(item.isUnread || item.pinned ? DS.Color.textSecondary : DS.Color.textTertiary)
                    .lineLimit(item.pinned ? 3 : 2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let fields = changedFields {
                Text(verbatim: fields)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            metaLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // النص عنصر واحد: يفتح التفاصيل، ومعه «مقروء»/«حذف»؛ والنوع يُسمع (المربّع وحده لا يُسمع)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(item.notificationId != nil ? .isButton : [])
        .accessibilityAddTraits(selecting && picked ? .isSelected : [])
        .accessibilityValue(item.isUnread ? L10n.t("جديد", "New") : "")
        .accessibilityHint(item.tone.spoken)
        .accessibilityAction { onTap() }
        .accessibilityActions {
            ForEach(actions) { action in
                Button(action.title) { perform(action) }
            }
        }
    }

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
            Text(verbatim: item.title)
                .dsFont(item.isUnread ? .rowTitle : .body)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Spacing.xs)
            if item.isUnread || !item.pinned || showsChevron {
                HStack(spacing: DS.Spacing.xs) {
                    if item.isUnread { DSGoldDot(size: DSNoticeMetrics.unreadDot) }
                    if !item.pinned {
                        Text(verbatim: now ? AdminNoticeRow.relative(item.date) : AdminNoticeRow.clock(item.date))
                            .dsFont(.subtitle)
                            .monospacedDigit()
                            .foregroundColor(item.isUnread ? AppSection.admin.ink.dsReadableGlyph : DS.Color.textTertiary)
                            .lineLimit(1)
                    }
                    if showsChevron { DSChevron() }
                }
                .fixedSize()
            }
        }
    }

    /// «قبل ← بعد» مكانه مربّع التفاصيل (spec B.7)؛ في الصفّ أسماء ما تغيّر فقط: «تاريخ الميلاد · الصورة +2»
    private var changedFields: String? {
        guard let changes = item.rich?.changes, !changes.isEmpty else { return nil }
        let names = changes.prefix(2).map(\.displayLabel).joined(separator: " · ")
        return changes.count > 2 ? "\(names) +\(changes.count - 2)" : names
    }

    /// مَن فعل («أضافه أبوه فهد»، «بواسطة: فيصل») وحالة الابن المضاف
    @ViewBuilder
    private var metaLine: some View {
        if item.meta != nil || child != nil {
            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                if let meta = item.meta {
                    Text(verbatim: meta)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(2)
                }
                if let child {
                    AdminSelfChildStatusChip(review: child.review)
                }
            }
            .padding(.top, DS.Spacing.xxs)
        }
    }

    // MARK: الأزرار

    /// «الملف» و«تنبيه» للابن المضاف وحدهما (T4 — حذف العضو بيته ورقة العضو التي يفتحها «الملف»؛ كحلي عند احتمال
    /// التكرار)، وزرّ البيت تحت النص في صفوف الأيام — تلتفّ لسطر ثانٍ ولا تُقصّ، و١٢ بينها فلا يتداخل لمسها (spec A.7/T6)
    private var pills: some View {
        DSChipFlow(spacing: DS.Hub.actingPillGap, lineSpacing: DS.Spacing.md) {
            if let child, let onSelfChild {
                let open = L10n.t("الملف", "Profile")
                AdminPillButton(title: open, style: child.review ? .navy : .soft) { onSelfChild(.openProfile, child) }
                    .accessibilityLabel(Text(verbatim: "\(open): \(child.childFullName)"))
                if child.canAlert {
                    let alert = L10n.t("تنبيه", "Alert")
                    AdminPillButton(title: alert, style: .soft) { onSelfChild(.alert, child) }
                        .accessibilityLabel(Text(verbatim: "\(alert): \(child.fatherName)"))
                }
            }
            if !sidePill, let homePill {
                homePill
            }
        }
    }

    /// زرّ البيت الواحد: «إعلان» ← المناسبات · «مراجعة» ← الوارد على الطلب · «راجع» ← طلبات رمز الدخول · «شحن الرصيد» ←
    /// رسائل رمز الدخول. كحلي في «يحتاج إجراء الآن»، وبإطار في صفوف الأيام
    private var homePill: AnyView? {
        guard let title = item.button, item.target != .none else { return nil }
        let target = item.target
        return AnyView(AdminTapWrap(tap: .page { AdminNoticeRoutes.page(target) },
                                    label: AnyView(AdminPillLabel(title: title, style: now ? .navy : .soft)
                                        .dsTapArea(width: DS.Icon.tapTarget, height: DS.Hub.pillHeight)),
                                    accessibilityLabel: "\(title): \(item.title)")
            .fixedSize())
    }
}

/// «12 غير مقروء» في البداية و«قراءة الكل» بجانبه في الطرف (spec C.15 السطر ٣، mock 11) — تحته إن ضاق. «قراءة الكل» زرّ
/// نصّي كحلي بوزن عادي (كرابط البطاقة `AdminCardLinkLabel`، لمس ٤٤) — لا وزن عنوان (F2)
struct AdminNoticeCaption: View {
    let unread: Int
    let onReadAll: () -> Void

    var body: some View {
        let button = Button(action: onReadAll) {
            Text(L10n.t("قراءة الكل", "Mark all read"))
                .dsFont(.body)
                .foregroundColor(AppSection.admin.ink)
                .padding(.horizontal, DS.Spacing.xsm)
                .frame(minWidth: DS.Icon.tapTarget, minHeight: DS.Icon.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        let count = (Text(verbatim: AdminNumberText.grouped(unread))
            .font(DS.Font.role(.sectionTitle))
            .foregroundColor(DS.Color.textPrimary)
            + Text(verbatim: " " + AdminNoticeLogic.unreadTail()))
            .dsFont(.subtitle)
            .foregroundColor(DS.Color.textSecondary)
            .monospacedDigit()
            .accessibilityElement(children: .combine)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.sm) {
                count
                Spacer(minLength: DS.Spacing.sm)
                button.fixedSize()
            }
            VStack(alignment: .leading, spacing: 0) {
                count.frame(minHeight: DS.Icon.tapTarget)
                button
            }
        }
        .frame(minHeight: DS.Icon.tapTarget)
    }
}

/// حالة الابن المضاف: «احتمال مكرر» (تنبيه) أو «بلا تكرار» — حبّة حالة بكلمة (spec A.7)
struct AdminSelfChildStatusChip: View {
    let review: Bool

    var body: some View {
        AdminStatePill(title: review ? L10n.t("احتمال مكرر", "Possible duplicate") : L10n.t("بلا تكرار", "No duplicate"),
                       tone: review ? .warn : .ok,
                       icon: review ? "exclamationmark.triangle.fill" : "checkmark")
    }
}
