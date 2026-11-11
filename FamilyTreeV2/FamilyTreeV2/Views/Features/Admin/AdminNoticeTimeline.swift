import SwiftUI

// MARK: - «إشعارات الإدارة» خطّاً زمنياً (اختيار المالك ٢٠٢٦-١١-٠٦ — العيّنة «ب خطّ زمني»)
//
// كل إشعار بطاقة مستقلة (كان كل يوم بطاقة واحدة)، وعلى طرفها خطّ الوقت بنقطة ملوّنة بدل أيقونة النوع — لون النقطة = النوع
// (طلب · إضافة · تعديل · نظام). عنوان كل قسم («يحتاج إجراء الآن»، اليوم، أمس…) حلقة فارغة على الخطّ نفسه. الإجراء رابط صغير
// في طرف البطاقة. السحب والتحديد ونقطة «جديد» الذهبية والعنوان الأعرض لغير المقروء كما كانت.
// كل جزء نوع صغير مستقل (حارس المكدس).

/// نوع الإشعار على الخطّ الزمني — لون نقطته
enum AdminNoticeTone: Equatable {
    case request, add, edit, system

    var color: Color {
        switch self {
        case .request: return DS.Color.sea
        case .add:     return DS.Color.palm
        case .edit:    return DS.Color.accent
        case .system:  return DS.Color.slate
        }
    }

    /// اسم النوع للقارئ الصوتي (اللون وحده لا يُسمع)
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

/// مقاسات الخطّ الزمني (مكانها هنا — لا أرقام عند الاستعمال)
enum AdminTimelineMetrics {
    /// عمود الخطّ في طرف البطاقة، والفراغ بينه وبين البطاقة
    static let rail: CGFloat = DS.Spacing.md
    static let railGap: CGFloat = DS.Spacing.sm
    /// النقطة وحلقة عنوان القسم وسُمك الخطّ
    static let dot: CGFloat = DS.Spacing.smd
    static let ring: CGFloat = DS.Spacing.smd
    static let line: CGFloat = DS.Border.widthBold
    /// النقطة على مستوى عنوان البطاقة
    static let dotTop: CGFloat = DSNoticeMetrics.paddingV + DS.Spacing.xs
    /// بين البطاقات، وفوق عنوان القسم
    static let cardGap: CGFloat = DS.Spacing.sm
    static let headerTop: CGFloat = DS.Hub.stackSpacing
    /// الحلقة على مستوى نصّ عنوان القسم
    static var ringTop: CGFloat { headerTop + DS.Spacing.xxs }
}

/// عمود الخطّ: جزء فوق النقطة (إن لم يكن أول الخطّ) ثم النقطة ثم جزء حتى أسفل الصفّ (إن لم يكن آخره) — يملأ ارتفاع صفّه
struct AdminTimelineRail: View {
    enum Mark { case dot(Color), ring }
    let mark: Mark
    /// بُعد مركز العلامة من أعلى الصفّ
    let markTop: CGFloat
    var lineAbove = true
    var lineBelow = true

    private var size: CGFloat {
        if case .dot = mark { return AdminTimelineMetrics.dot }
        return AdminTimelineMetrics.ring
    }

    var body: some View {
        VStack(spacing: 0) {
            segment(visible: lineAbove).frame(height: max(0, markTop - size / 2))
            markView
            segment(visible: lineBelow).frame(maxHeight: .infinity)
        }
        .frame(width: AdminTimelineMetrics.rail)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }

    private func segment(visible: Bool) -> some View {
        Rectangle()
            .fill(visible ? DS.Color.cardBorder : Color.clear)
            .frame(width: AdminTimelineMetrics.line)
    }

    @ViewBuilder
    private var markView: some View {
        switch mark {
        case .dot(let color):
            Circle().fill(color).frame(width: size, height: size)
        case .ring:
            Circle().strokeBorder(DS.Color.cardBorderStrong, lineWidth: AdminTimelineMetrics.line)
                .background(Circle().fill(DS.Hub.background))
                .frame(width: size, height: size)
        }
    }
}

extension View {
    /// الصفّ على الخطّ الزمني: يحجز عمود الخطّ في الطرف ويرسمه بطول الصفّ كله (مع الفراغ تحته — الخطّ متّصل).
    /// الخطّ في طرف البداية (يمين الشاشة بالعربي) — طلب المالك ٢٠٢٦-١١-٠٧ «الخط الزمني ابيه في الجهة الثانية»
    func adminTimelineRail(_ mark: AdminTimelineRail.Mark, markTop: CGFloat,
                           lineAbove: Bool = true, lineBelow: Bool = true) -> some View {
        padding(.leading, AdminTimelineMetrics.rail + AdminTimelineMetrics.railGap)
            .overlay(alignment: .leading) {
                AdminTimelineRail(mark: mark, markTop: markTop, lineAbove: lineAbove, lineBelow: lineBelow)
            }
    }
}

/// عنوان القسم على الخطّ: الاسم وعدده، وحلقة فارغة على الخطّ
struct AdminTimelineHeader: View {
    let title: String
    let count: Int
    let isFirst: Bool

    var body: some View {
        DSDayHeader(title: title, count: count)
            .padding(.top, AdminTimelineMetrics.headerTop)
            .padding(.bottom, DSNoticeMetrics.headerGap)
            .adminTimelineRail(.ring, markTop: AdminTimelineMetrics.ringTop, lineAbove: !isFirst)
    }
}

/// بطاقة الإشعار على الخطّ:
///   العنوان (نوع الحدث) ……… • الوقت
///   الشخص/النص · «قبل ← بعد» · السطر الصغير
///   [الحالة]                     [رابط ›]
struct AdminNoticeTimelineRow: View {
    let item: AdminNoticeItem
    let selecting: Bool
    let picked: Bool
    /// آخر صفّ في الخطّ — لا يمتدّ الخطّ تحته
    var isLast = false
    let onTap: () -> Void
    var onSelfChild: ((AdminSelfChildAction, AdminNoticeSelfChild) -> Void)? = nil

    private var showsCircle: Bool { selecting && item.notificationId != nil }

    var body: some View {
        card
            .padding(.bottom, AdminTimelineMetrics.cardGap)
            .adminTimelineRail(.dot(item.tone.color), markTop: AdminTimelineMetrics.dotTop, lineBelow: !isLast)
    }

    private var card: some View {
        HStack(alignment: .top, spacing: DSNoticeMetrics.selectGap) {
            if showsCircle {
                DSNoticeSelectCircle(picked: picked, tint: AppSection.admin.ink)
            }
            AnyView(content)
        }
        .padding(.horizontal, DSNoticeMetrics.paddingH)
        .padding(.vertical, DSNoticeMetrics.paddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGroupedRow(.single, radius: DS.Hub.cardRadius, dividerInset: 0,
                      highlight: selecting && picked ? AppSection.admin.ink.opacity(DS.Opacity.tintFill) : nil)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        // برابط: يبقى الرابط عنصراً مستقلاً للقارئ الصوتي؛ ولون النقطة يُسمع نوعاً
        .accessibilityElement(children: hasLink && !selecting ? .contain : .combine)
        .accessibilityHint(item.tone.spoken)
        .accessibilityValue(item.isUnread ? L10n.t("جديد", "New") : "")
        .accessibilityAddTraits(item.notificationId != nil ? .isButton : [])
        .accessibilityAddTraits(selecting && picked ? .isSelected : [])
    }

    private var hasLink: Bool { item.button != nil || item.selfChild?.review == true }

    private var content: some View {
        VStack(alignment: .leading, spacing: DSNoticeMetrics.lineGap) {
            titleLine
            if !item.subtitle.isEmpty {
                // الحالة المشتقة (الآن) نصّها كاملاً حتى ٣ أسطر، والإشعار سطران أقصى
                DSNoticeText(text: item.subtitle, unread: item.isUnread || item.pinned, lines: item.pinned ? 3 : 2)
            }
            if let rich = item.rich, !rich.changes.isEmpty {
                NotificationChangesInline(changes: rich.changes)
            }
            bottomLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
            Text(verbatim: item.title)
                .dsFont(item.isUnread ? .noticeTitle : .noticeTitleRead)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Spacing.xs)
            if item.isUnread || !item.pinned {
                HStack(spacing: DS.Spacing.xs) {
                    if item.isUnread { DSGoldDot(size: DSNoticeMetrics.unreadDot) }
                    if !item.pinned {
                        Text(verbatim: AdminNoticeRow.relative(item.date))
                            .dsFont(.caption)
                            .monospacedDigit()
                            .foregroundColor(item.isUnread ? AppSection.admin.ink.dsReadableGlyph : DS.Color.textTertiary)
                            .lineLimit(1)
                    }
                }
                .fixedSize()
            }
        }
    }

    /// السطر الأخير: السطر الصغير (مَن فعل) والحالة، والرابط في طرف البطاقة
    @ViewBuilder
    private var bottomLine: some View {
        let meta = item.meta
        let status = item.selfChild.flatMap { $0.isGeneral ? nil : $0 }
        let link = linkView
        if meta != nil || status != nil || link != nil {
            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                if let meta {
                    Text(verbatim: meta)
                        .dsFont(.micro)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)
                }
                if let status {
                    AdminSelfChildStatusChip(review: status.review)
                }
                Spacer(minLength: 0)
                if let link, !selecting { link }
            }
            .padding(.top, DS.Spacing.xxs)
        }
    }

    /// رابط البيت الواحد: «إعلان/مراجعة/راجع/شحن الرصيد» ← صفحته، و«راجع» على الابن المشكوك فيه ← ملفه
    private var linkView: AnyView? {
        if let button = item.button {
            return AnyView(AdminTapWrap(tap: .page { AdminNoticeRoutes.page(item.target) },
                                        label: AnyView(AdminTimelineLink(title: button)),
                                        accessibilityLabel: "\(button): \(item.title)")
                .fixedSize())
        }
        if let notice = item.selfChild, notice.review, !notice.isGeneral, let onSelfChild {
            let title = L10n.t("راجع", "Review")
            return AnyView(AdminTapWrap(tap: .action { onSelfChild(.openProfile, notice) },
                                        label: AnyView(AdminTimelineLink(title: title)),
                                        accessibilityLabel: "\(title): \(notice.childFullName)")
                .fixedSize())
        }
        return nil
    }
}

/// رابط صغير في طرف البطاقة: النص وسهم صغير على تعبئة خفيفة — لمس ٤٤
struct AdminTimelineLink: View {
    let title: String

    var body: some View {
        AdminPillLabel(title: title, icon: L10n.isArabic ? "chevron.left" : "chevron.right", style: .soft,
                       iconTrailing: true)
            .dsTapArea(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
    }
}

/// حالة الابن المضاف: «احتمال مكرر» (تنبيه) أو «بلا تكرار»
struct AdminSelfChildStatusChip: View {
    let review: Bool

    var body: some View {
        DSStatusChip(text: review ? L10n.t("احتمال مكرر", "Possible duplicate") : L10n.t("بلا تكرار", "No duplicate"),
                     tint: review ? DS.Color.warning : DS.Color.success, size: .mini)
    }
}
