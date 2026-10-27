import SwiftUI

// MARK: - قوائم الإشعارات والرسائل المرتّبة (طلب المالك ٢٠٢٦-١٠-٢٤ «والرسائل و الاشعارات في الادارة ابي ارتبها " حتى اشعارات العامة "»)
//
// شكل واحد لثلاث قوائم — «إشعارات الإدارة»، رسائل الأعضاء في «الوارد»، ومركز الإشعارات العام («الإشعارات | المستجدات»):
//   • أقسام بالأيام: اليوم · أمس · التاريخ (`DSDayBuckets`) بعنوان صغير وعدده (`DSDayHeader`)
//   • كل يوم بطاقة واحدة بصفوف مختصرة يفصلها خطّ رفيع يبدأ من النص (`dsGroupedRow`) — كل صفّ يرسم جزءه من البطاقة،
//     فتبقى أزرار السحب والتحديد لكل صفّ وحده
//   • الصفّ (`DSNoticeRow`): أيقونة النوع بلونه · العنوان وفي طرفه الوقت · سطر النص · سطر صغير اختياري · إجراء اختياري.
//     غير المقروء: العنوان أعرض، والنقطة الذهبية بجانب الوقت (طلب المالك ٢٠٢٦-١٠-١٠ «نقاط صفراء صغيرة إذا شي جديد»)
//     والوقت بلون القسم؛ المقروء أهدأ.
// المقاسات والأدوار هنا (لا أرقام عند الاستعمال).

enum DSNoticeMetrics {
    /// حشوة الصفّ داخل بطاقة اليوم، والفراغ بين الأيقونة والنص وبين الأسطر
    static let paddingH: CGFloat = DS.Hub.cardPadding
    static let paddingV: CGFloat = DS.Spacing.sm + DS.Spacing.xxs
    static let gap: CGFloat = DS.Spacing.md
    static let lineGap: CGFloat = DS.Spacing.xxs
    /// نقطة «جديد» الذهبية بجانب الوقت
    static let unreadDot: CGFloat = DS.Spacing.sm
    /// بين عنوان اليوم وبطاقته
    static let headerGap: CGFloat = DS.Spacing.xsm
    /// دائرة التحديد قبل الأيقونة (وضع التحديد) والفراغ بعدها
    static let selectCircle: CGFloat = DS.Icon.section
    static let selectGap: CGFloat = DS.Spacing.sm
    /// الخطّ الفاصل يبدأ من النص (بعد الأيقونة، وبعد دائرة التحديد إن ظهرت) كما في قوائم الآيفون
    static func dividerInset(icon: CGFloat, selecting: Bool = false) -> CGFloat {
        paddingH + icon + gap + (selecting ? selectCircle + selectGap : 0)
    }
    /// بين أيقونة السطر الصغير ونصّه (المرسل، النوع)
    static let metaGap: CGFloat = DS.Spacing.xxs + DS.Border.width
    /// شارة النوع على ركن صورة المرسل (رسائل الأعضاء)
    static let kindBadge: CGFloat = 18
    static let kindBadgeGlyph: CGFloat = DS.Glyph.micro
}

extension DS.TextRole {
    /// عنوان صفّ الإشعار: غير المقروء عريض، والمقروء أخفّ — Subheadline (١٥)
    static let noticeTitle = DS.TextRole(.subheadline, weight: .semibold)
    static let noticeTitleRead = DS.TextRole(.subheadline, weight: .medium)
}

// MARK: الأيام

/// تجميع بالأيام: «اليوم» · «أمس» · «الأحد 18 أكتوبر» (وبالسنة إن لم تكن السنة الحالية) — بأرقام لاتينية كبقية اللوحة
enum DSDayBuckets {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar_KW@numbers=latn" : "en_US")
        f.setLocalizedDateFormatFromTemplate(format)
        return f
    }
    private static let thisYear = formatter("EEEEdMMMM")
    private static let otherYear = formatter("EEEEdMMMMyyyy")

    static func title(for date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return L10n.t("اليوم", "Today") }
        if cal.isDateInYesterday(date) { return L10n.t("أمس", "Yesterday") }
        let same = cal.component(.year, from: date) == cal.component(.year, from: now)
        return (same ? thisYear : otherYear).string(from: date)
    }

    /// عناصر مرتّبة (الأحدث أولاً) ← أيامها بترتيبها، ومعرّف كل يوم بدايته (ثابت بين التحديثات)
    static func group<T>(_ items: [T], date: (T) -> Date) -> [DSDayGroup<T>] {
        let cal = Calendar.current
        var order: [Date] = []
        var map: [Date: [T]] = [:]
        for item in items {
            let day = cal.startOfDay(for: date(item))
            if map[day] == nil { order.append(day) }
            map[day, default: []].append(item)
        }
        return order.map { DSDayGroup(day: $0, title: title(for: $0), items: map[$0] ?? []) }
    }
}

struct DSDayGroup<T>: Identifiable {
    let day: Date
    let title: String
    let items: [T]
    var id: Date { day }
}

/// عنوان اليوم فوق بطاقته: الاسم بالثانوي وعدده في الطرف — عنوان قسم للقارئ الصوتي
struct DSDayHeader: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(title)
                .dsFont(.sectionTitle)
                .foregroundColor(DS.Color.textSecondary)
            Spacer(minLength: 0)
            if let count {
                Text(verbatim: "\(count)")
                    .dsFont(.caption)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
        .padding(.horizontal, DS.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: بطاقة اليوم من صفوفها

/// موضع الصفّ في بطاقة يومه — الأول يدوّر الأعلى، والأخير الأسفل، والوحيد الاثنين
enum DSGroupPosition: Equatable {
    case single, first, middle, last

    init(index: Int, count: Int) {
        if count <= 1 { self = .single }
        else if index == 0 { self = .first }
        else if index == count - 1 { self = .last }
        else { self = .middle }
    }

    var roundsTop: Bool { self == .single || self == .first }
    var roundsBottom: Bool { self == .single || self == .last }
}

/// جزء الصفّ من البطاقة: السطح والإطار الرفيع بزوايا موضعه — الحافة غير المدوّرة تمتدّ خارج الصفّ وتُقصّ، فيلتقي الصفّ
/// بجاره بلا خطّ ولا زاوية. الصفّ المختار (التحديد) أو المضغوط بتعبئة خفيفة
private struct DSGroupSegment: View {
    let position: DSGroupPosition
    let radius: CGFloat
    let highlight: Color?

    var body: some View {
        Color.clear
            .overlay {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                ZStack {
                    shape.fill(DS.Color.surface)
                    if let highlight { shape.fill(highlight) }
                    shape.strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke), lineWidth: DS.Card.strokeWidth)
                }
                .padding(.top, position.roundsTop ? 0 : -radius)
                .padding(.bottom, position.roundsBottom ? 0 : -radius)
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct DSGroupedRowModifier: ViewModifier {
    let position: DSGroupPosition
    let radius: CGFloat
    let dividerInset: CGFloat
    let highlight: Color?
    /// مضغوط الآن (`DSNoticePressStyle`) — تعبئة خفيفة داخل شكل الصفّ (لا تخرج من زواياه)
    @Environment(\.dsNoticePressed) private var pressed

    func body(content: Content) -> some View {
        let fill = highlight ?? (pressed ? DS.Color.textTertiary.opacity(DS.Opacity.tintFillSoft) : nil)
        return content
            .background(DSGroupSegment(position: position, radius: radius, highlight: fill)
                .animation(DSMotion.press, value: pressed))
            .overlay(alignment: .bottom) {
                if !position.roundsBottom {
                    AdminRowDivider().padding(.leading, dividerInset)
                }
            }
    }
}

extension View {
    /// الصفّ جزء من بطاقة يومه: السطح والإطار بزوايا موضعه، وخطّ فاصل رفيع تحته يبدأ من النص (إلا الأخير)
    func dsGroupedRow(_ position: DSGroupPosition, radius: CGFloat = DS.Hub.cardRadius,
                      dividerInset: CGFloat, highlight: Color? = nil) -> some View {
        modifier(DSGroupedRowModifier(position: position, radius: radius, dividerInset: dividerInset, highlight: highlight))
    }
}

private struct DSNoticePressedKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// صفّ بطاقة اليوم مضغوط الآن (من `DSNoticePressStyle`) — يقرؤه `dsGroupedRow`
    var dsNoticePressed: Bool {
        get { self[DSNoticePressedKey.self] }
        set { self[DSNoticePressedKey.self] = newValue }
    }
}

/// ضغطة صفّ داخل بطاقة اليوم: تعبئة خفيفة بشكل الصفّ كصفوف قوائم الآيفون (لا تصغير — الصفّ جزء من بطاقة)
struct DSNoticePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.dsNoticePressed, configuration.isPressed)
    }
}

// MARK: الصفّ

/// الصفّ المختصر الواحد:
///   [الأيقونة]  العنوان (سطران أقصى) ……… • الوقت
///               النص والسطر الصغير (`detail`)        [إجراء]
struct DSNoticeRow<Leading: View, Detail: View, Accessory: View>: View {
    let title: String
    /// «قبل 5 دقائق» — فارغ = بلا وقت (حالة الآن)
    var time: String = ""
    let unread: Bool
    /// لون الوقت لغير المقروء (حبر القسم)
    var tint: Color = DS.Color.primary
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var detail: () -> Detail
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .top, spacing: DSNoticeMetrics.gap) {
            leading()
            VStack(alignment: .leading, spacing: DSNoticeMetrics.lineGap) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                    Text(verbatim: title)
                        .dsFont(unread ? .noticeTitle : .noticeTitleRead)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.Spacing.xs)
                    if unread || !time.isEmpty {
                        HStack(spacing: DS.Spacing.xs) {
                            if unread { DSGoldDot(size: DSNoticeMetrics.unreadDot) }
                            if !time.isEmpty {
                                Text(verbatim: time)
                                    .dsFont(.caption)
                                    .monospacedDigit()
                                    .foregroundColor(unread ? tint.dsReadableGlyph : DS.Color.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        .fixedSize()
                    }
                }
                HStack(alignment: .center, spacing: DS.Spacing.sm) {
                    VStack(alignment: .leading, spacing: DSNoticeMetrics.lineGap) {
                        detail()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    accessory()
                }
            }
        }
        .padding(.horizontal, DSNoticeMetrics.paddingH)
        .padding(.vertical, DSNoticeMetrics.paddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension DSNoticeRow where Accessory == EmptyView {
    init(title: String, time: String = "", unread: Bool, tint: Color = DS.Color.primary,
         @ViewBuilder leading: @escaping () -> Leading, @ViewBuilder detail: @escaping () -> Detail) {
        self.init(title: title, time: time, unread: unread, tint: tint, leading: leading, detail: detail,
                  accessory: { EmptyView() })
    }
}

/// سطر نصّ الصفّ: غير المقروء بالثانوي، والمقروء أهدأ
struct DSNoticeText: View {
    let text: String
    let unread: Bool
    var lines: Int = 1
    var role: DS.TextRole = .footnote

    var body: some View {
        Text(verbatim: text)
            .dsFont(role)
            .foregroundColor(unread ? DS.Color.textSecondary : DS.Color.textTertiary)
            .lineLimit(lines)
            .multilineTextAlignment(.leading)
    }
}

/// دائرة التحديد قبل أيقونة الصفّ (وضع التحديد)
struct DSNoticeSelectCircle: View {
    let picked: Bool
    var tint: Color = DS.Color.primary

    var body: some View {
        Image(systemName: picked ? "checkmark.circle.fill" : "circle")
            .dsGlyph(DS.Glyph.xl, weight: .regular)
            .foregroundColor(picked ? tint.dsReadableGlyph : DS.Color.textTertiary)
            .frame(width: DSNoticeMetrics.selectCircle, height: DS.Icon.rowLarge)
            .accessibilityHidden(true)
    }
}

/// سطر صغير بأيقونة تحت النص (المرسل، النوع): الأيقونة بجانب النص بفراغ صغير
struct DSNoticeMetaLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DSNoticeMetrics.metaGap) {
            configuration.icon
            configuration.title
        }
    }
}
