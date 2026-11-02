import SwiftUI

// MARK: - مربّع تفاصيل الإشعار الغني (طلب المالك ٢٠٢٦-١١-٠١ — «الورقة ناشفة، ما فيها تفاصيل»)
//
// مربّع بمنتصف الشاشة لكل إشعار (مركز الإشعارات و«إشعارات الإدارة»): رأس كحلي متدرّج (شريحة النوع والحالة، مربّع
// المرسل، العنوان و«الإدارة · الوقت»، زرّ ×) ← النص كاملاً في بطاقة اقتباس كريمية بخط ذهبي ← حسب الإشعار:
//   • طلب (`request_id`): للعضو «رحلة الطلب» و«رد الإدارة» والنوع/الوصول وأزرار السياق؛ وللإدارة مقدّم الطلب
//     و«تفاصيل الطلب» والسياق والمسار والقرار (نفس دوال القبول/الرفض الموجودة) و«فتح الطلب كامل».
//   • تغييرات (`details.changes`): «قبل/بعد» للإدارة أو «كان/صار» للعضو.
//   • خبر: «فتح الخبر». والبسيط: النص والوقت والإغلاق.
// العضو لا يرى اسم أحد من الإدارة ولا صورته أبداً — المرسل «الإدارة».
// كل جزء نوع صغير مستقل (حارس المكدس).

// MARK: - الهيكل

/// درجة الشريحة/الخطوة: محايد · ينتظر · مقبول · مرفوض
enum NotifBoxTone {
    case neutral, gold, pending, success, danger

    /// لون النص/النقطة على السطح الأبيض
    var ink: Color {
        switch self {
        case .neutral: return DS.Color.primary
        case .gold:    return DS.Color.accent
        case .pending: return DS.Color.warning
        case .success: return DS.Color.success
        case .danger:  return DS.Color.error
        }
    }

    /// خلفية الشريحة على الرأس الكحلي
    var bandFill: Color {
        switch self {
        case .neutral: return DS.Color.textOnPrimary.opacity(DS.Opacity.tintFill)
        case .gold:    return DS.Color.accentLight.opacity(DS.Opacity.tintStroke)
        case .pending: return DS.Color.warningFill.opacity(DS.Opacity.selectedStroke)
        case .success: return DS.Color.successFill.opacity(DS.Opacity.selectedStroke)
        case .danger:  return DS.Color.errorFill.opacity(DS.Opacity.selectedStroke)
        }
    }
}

/// شريحة على الرأس الكحلي
struct NotifBandChip: View {
    let text: String
    let tone: NotifBoxTone

    var body: some View {
        Text(verbatim: text)
            .dsFont(.badge)
            .foregroundColor(tone == .gold ? DS.Color.headerSubtitleOnTile : DS.Color.textOnPrimary)
            .lineLimit(1)
            .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xxs)
            .padding(.vertical, DS.Spacing.xs)
            .background(RoundedRectangle(cornerRadius: DS.Radius.sm + DS.Spacing.xxs, style: .continuous)
                .fill(tone.bandFill))
    }
}

/// مربّع الرأس (٥٢): ذهبي برمز النوع، أو دائرة العضو (للإدارة فقط)
enum NotifBoxTile: Equatable {
    case glyph(String)
    case member(name: String, avatarUrl: String?)
}

struct NotifBoxTileView: View {
    let tile: NotifBoxTile
    /// مقاس المربّع — ٤٠ في الرأس (طلب المالك ٢٠٢٦-١١-٠١ «هيدر المربع شوي نقلله»)، ٣٠ في الرأس المضغوط
    var side: CGFloat = DSBox.composerIcon

    var body: some View {
        Group {
            switch tile {
            case .glyph(let symbol):
                RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
                    .fill(DS.Color.accentLight)
                    .frame(width: side, height: side)
                    // أيقونة خفيفة (طلب المالك ٢٠٢٦-١١-٠١ «ايقونات الخفيفة») — رمز رفيع بلا مجسّم
                    .overlay(Image(dsSymbol: symbol.dsLightSymbol).dsGlyph(side * 0.48, weight: .light)
                        .foregroundColor(DS.Color.navyDeep))
            case .member(let name, let url):
                DSMemberAvatar(name: name, avatarUrl: url, size: side)
            }
        }
        .accessibilityHidden(true)
    }
}

/// المربّع: الرأس ثم محتوى يتمرّر — يبلّغ `DSCenterPanel` بارتفاعه (يحتضن محتواه حتى ٨٦٪ من الشاشة)
struct NotificationRichBox: View {
    let chips: [(String, NotifBoxTone)]
    let tile: NotifBoxTile
    let title: String
    let subtitle: String
    let onClose: () -> Void
    let content: AnyView

    @State private var headerH: CGFloat = 0
    @State private var contentH: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header.readHeight($headerH)
            ScrollView(showsIndicators: false) {
                content
                    .padding(DS.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .readHeight($contentH)
            }
        }
        .background(DS.Color.surface)
        .preference(key: SheetContentHeightKey.self, value: headerH > 0 ? headerH + contentH : 0)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// الرأس الأصغر (٢٠٢٦-١١-٠١): الشرائح وزرّ × في صفّ، ثم المربّع ٤٠ والعنوان — حشوة ١٢ بدل ١٦
    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xsm) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    NotifBandChip(text: chip.0, tone: chip.1)
                }
                Spacer(minLength: DS.Spacing.xs)
                // بلا × — «إغلاق» في شريط المربّع السفلي (طلب المالك ٢٠٢٦-١١-٠١)
            }
            HStack(spacing: DS.Spacing.md) {
                NotifBoxTileView(tile: tile)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(verbatim: title)
                        .dsFont(.headline)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !subtitle.isEmpty {
                        Text(verbatim: subtitle)
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.headerSubtitleOnTile)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSRichBoxBand())
    }
}

/// أرضية رأس المربّع الموحّد — كحلي متدرّج (مربّع الإشعار وكل مربّعات `DSComposer`)
struct DSRichBoxBand: View {
    /// المشاريع والمكتبة: الشريط بلون رأس صفحتها (فيروزي/أزرق) بدل الكحلي — ما بداخل المربّع بلونها
    /// فيتّسق الرأس والمحتوى (طلب المالك ٢٠٢٦-١١-٠١ «صلح لون المشاريع»)
    @Environment(\.dsSection) private var section
    var body: some View {
        Group {
            if let section, AppSection.HomeTile.tile(for: section) != nil {
                section.headerGradient
            } else {
                LinearGradient(colors: [DS.Color.navyFill, DS.Color.navyDeep],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .ignoresSafeArea(edges: .horizontal)
    }
}

/// زرّ × الخفيف على الرأس الكحلي
struct DSRichBoxCloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .dsGlyph(DS.Glyph.sm, weight: .regular)
                .foregroundColor(DS.Color.textOnPrimary)
                .frame(width: DS.Icon.row - DS.Spacing.xs, height: DS.Icon.row - DS.Spacing.xs)
                .background(Circle().fill(DS.Color.textOnPrimary.opacity(DS.Opacity.tintFill)))
                .dsTapArea(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("إغلاق", "Close"))
    }
}

// MARK: - أجزاء المحتوى

/// عنوان صغير فوق جزء
struct NotifBoxLabel: View {
    let text: String
    var body: some View {
        Text(verbatim: text)
            .dsFont(.sectionTitle)
            .foregroundColor(DS.Color.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// النص كاملاً في بطاقة اقتباس كريمية بخط ذهبي على جهة البداية
struct NotifQuoteCard: View {
    let text: AnyView

    var body: some View {
        text
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.Spacing.md + DS.Spacing.xxs)
            .padding(.vertical, DS.Spacing.md)
            .background(DS.Color.cardBackgroundSoft)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(DS.Color.accentLight)
                    .frame(width: DS.Border.widthBold * 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }
}

/// خطوة في «رحلة الطلب»
struct NotifJourneyStep {
    let title: String
    let subtitle: String
    let tone: NotifBoxTone
}

/// «رحلة الطلب» — خطّ عمودي بنقاط
struct NotifJourneyView: View {
    let steps: [NotifJourneyStep]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            NotifBoxLabel(text: L10n.t("رحلة الطلب", "Request journey"))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    stepRow(step, last: index == steps.count - 1)
                }
            }
        }
    }

    private func stepRow(_ step: NotifJourneyStep, last: Bool) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm + DS.Spacing.xxs) {
            VStack(spacing: 0) {
                Circle()
                    .fill(step.tone.ink)
                    .frame(width: DS.Spacing.md, height: DS.Spacing.md)
                if !last {
                    Rectangle()
                        .fill(DS.Color.cardBorder)
                        .frame(width: DS.Spacing.xxs, height: DS.Spacing.xxxl - DS.Spacing.xxs)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: step.title)
                    .dsFont(.sectionTitle)
                    .foregroundColor(step.tone == .neutral ? DS.Color.textPrimary : step.tone.ink)
                if !step.subtitle.isEmpty {
                    Text(verbatim: step.subtitle)
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
            .offset(y: -DS.Spacing.xxs)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// «رد الإدارة»
struct NotifReplyCard: View {
    let text: String
    /// عنوان البطاقة ورمزها — «مسار الموافقات» يستعملها لتوصية المختص وملاحظة المدير
    var label: String = L10n.t("رد الإدارة", "Administration's reply")
    var icon: String = "bubble.left.fill"

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm + DS.Spacing.xxs) {
            RoundedRectangle(cornerRadius: DS.Radius.sm + DS.Spacing.xxs, style: .continuous)
                .fill(DS.Color.navyDeep)
                .frame(width: DS.Icon.row, height: DS.Icon.row)
                .overlay(Image(dsSymbol: icon.dsLightSymbol).dsGlyph(DS.Glyph.md, weight: .light)
                    .foregroundColor(DS.Color.headerSubtitleOnTile))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: label)
                    .dsFont(.badge)
                    .foregroundColor(DS.Color.accent)
                Text(verbatim: text)
                    .dsFont(.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .fill(DS.Color.accentLight.opacity(DS.Opacity.tintFillSoft)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(DS.Color.accentLight.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
        .accessibilityElement(children: .combine)
    }
}

/// خانة في شبكة المعلومات — المميّزة (القيمة المطلوبة/الجديدة) بالأخضر
struct NotifInfoCell {
    let label: String
    let value: String
    var highlighted = false
}

struct NotifInfoGrid: View {
    let cells: [NotifInfoCell]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Spacing.sm), GridItem(.flexible())],
                  alignment: .leading, spacing: DS.Spacing.sm) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(verbatim: cell.label)
                        .dsFont(.micro)
                        .foregroundColor(cell.highlighted ? DS.Color.success : DS.Color.textSecondary)
                    Text(verbatim: cell.value)
                        .dsFont(.rowTitle)
                        .foregroundColor(cell.highlighted ? DS.Color.success : DS.Color.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xxs)
                .padding(.vertical, DS.Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm + DS.Spacing.xxs, style: .continuous)
                    .fill(cell.highlighted ? DS.Color.success.opacity(DS.Opacity.tintFill) : DS.Color.cardBackgroundSoft))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// سطر سياق («بيصير الابن رقم ٣ …») بزرّ اختياري
struct NotifContextLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: DS.Spacing.sm + DS.Spacing.xxs) {
            Image(dsSymbol: icon.dsLightSymbol).dsGlyph(DS.Glyph.lg, weight: .light).foregroundColor(DS.Color.accent)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .dsFont(.callout)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm + DS.Spacing.xxs)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.cardBackgroundSoft))
    }
}

/// شريحة صغيرة على السطح الأبيض (المسار، المسند إليه، الأولوية)
struct NotifTagChip: View {
    let text: String
    let tone: NotifBoxTone

    var body: some View {
        Text(verbatim: text)
            .dsFont(.caption)
            .foregroundColor(tone.ink)
            .lineLimit(1)
            .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xxs)
            .padding(.vertical, DS.Spacing.xs + DS.Border.width)
            .background(RoundedRectangle(cornerRadius: DS.Radius.sm + DS.Spacing.xxs, style: .continuous)
                .fill(tone.ink.opacity(DS.Opacity.tintFill)))
    }
}

/// سطر صغير بساعة («أُرسل …»)
struct NotifMetaLine: View {
    let text: String

    var body: some View {
        Label {
            Text(verbatim: text).dsFont(.caption).lineLimit(2)
        } icon: {
            Image(dsSymbol: "clock").dsGlyph(DS.Glyph.sm, weight: .light)
        }
        .labelStyle(DSNoticeMetaLabelStyle())
        .foregroundColor(DS.Color.textSecondary)
    }
}

/// أزرار المربّع: أساسي كحلي · موافقة خضراء · رفض بإطار أحمر · ثانوي بإطار
enum NotifBoxButtonKind { case primary, approve, reject, secondary }

struct NotifBoxButtonStyle: ButtonStyle {
    let kind: NotifBoxButtonKind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DSBox.buttonRadius, style: .continuous)
        let fill: Color = {
            switch kind {
            case .primary:   return DS.Color.primaryFill
            case .approve:   return DS.Color.successFill
            case .reject, .secondary: return DS.Color.surface
            }
        }()
        let ink: Color = {
            switch kind {
            case .primary, .approve: return DS.Color.textOnPrimary
            case .reject:            return DS.Color.error
            case .secondary:         return DS.Color.primary
            }
        }()
        return configuration.label
            .dsFont(.button)
            .foregroundColor(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, minHeight: DSBox.buttonHeight)
            .padding(.horizontal, DS.Spacing.xs)
            .background(shape.fill(fill))
            .overlay {
                if kind == .reject || kind == .secondary {
                    shape.strokeBorder(kind == .reject ? DS.Color.error.opacity(DS.Opacity.tintStroke) : DS.Color.cardBorder,
                                       lineWidth: DS.Border.width)
                }
            }
            .opacity(configuration.isPressed ? 0.85 : (isEnabled ? 1 : DS.Opacity.disabled))
            .contentShape(shape)
    }
}

/// صفّ أزرار بعرض متساوٍ
struct NotifButtonRow: View {
    struct Item {
        let title: String
        let kind: NotifBoxButtonKind
        var disabled = false
        let action: () -> Void
    }
    let items: [Item]

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button(item.title, action: item.action)
                    .buttonStyle(NotifBoxButtonStyle(kind: item.kind))
                    .disabled(item.disabled)
            }
        }
    }
}

/// رابط نصّي بالوسط («فتح الطلب كامل»)
struct NotifTextLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .dsFont(.chip)
                .foregroundColor(DS.Color.primary)
                .underline()
                .frame(minHeight: DS.Icon.tapTarget)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

/// التفاف أفقي بسيط للشرائح
struct NotifFlow: Layout {
    var spacing: CGFloat = DS.Spacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW, x > 0 { y += line + spacing; x = 0; line = 0 }
            x += s.width + spacing
            line = max(line, s.height)
        }
        return CGSize(width: maxW.isFinite ? maxW : x, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { y += line + spacing; x = bounds.minX; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            line = max(line, s.height)
        }
    }
}

// MARK: - نصوص وتواريخ

enum NotifBoxText {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return iso.date(from: raw) ?? isoPlain.date(from: raw)
    }

    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    /// «السبت ٣١ أكتوبر · ٩:١٠ م»
    static func long(_ date: Date) -> String {
        "\(formatter("EEEEdMMMM").string(from: date)) · \(formatter("jmm").string(from: date))"
    }

    /// «١ نوفمبر · ١٢:٢٤ ص»
    static func short(_ date: Date) -> String {
        "\(formatter("dMMMM").string(from: date)) · \(formatter("jmm").string(from: date))"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    static func relative(_ date: Date) -> String {
        relativeFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// «خلال ساعتين» / «خلال ٣ أيام» — بالعدد العربي الصحيح (مفرد، مثنى، جمع)
    static func within(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int(seconds / 60))
        if minutes < 60 { return L10n.t("خلال \(arabicCount(minutes, one: "دقيقة", two: "دقيقتين", few: "دقائق", many: "دقيقة"))",
                                       "within \(minutes) min") }
        let hours = minutes / 60
        if hours < 24 { return L10n.t("خلال \(arabicCount(hours, one: "ساعة", two: "ساعتين", few: "ساعات", many: "ساعة"))",
                                     "within \(hours) h") }
        let days = hours / 24
        return L10n.t("خلال \(arabicCount(days, one: "يوم", two: "يومين", few: "أيام", many: "يوم"))", "within \(days) d")
    }

    private static func arabicCount(_ n: Int, one: String, two: String, few: String, many: String) -> String {
        switch n {
        case 1: return one
        case 2: return two
        case 3...10: return "\(n) \(few)"
        default: return "\(n) \(many)"
        }
    }

    /// اسم نوع الطلب
    static func requestType(_ type: String) -> String {
        switch type {
        case RequestType.treeEdit.rawValue:        return L10n.t("طلب تعديل", "Edit request")
        case RequestType.nameChange.rawValue:      return L10n.t("تغيير الاسم", "Name change")
        case RequestType.familyChange.rawValue:    return L10n.t("تغيير العائلة", "Family change")
        case RequestType.phoneChange.rawValue:     return L10n.t("تغيير الرقم", "Phone change")
        case RequestType.childAdd.rawValue:        return L10n.t("طلب إضافة ابن", "Add child")
        case RequestType.deceasedReport.rawValue:  return L10n.t("تسجيل وفاة", "Death report")
        case RequestType.photoSuggestion.rawValue: return L10n.t("اقتراح صورة", "Photo suggestion")
        case RequestType.newsReport.rawValue, RequestType.contentReport.rawValue:
            return L10n.t("بلاغ", "Report")
        case RequestType.joinRequest.rawValue:     return L10n.t("طلب انضمام", "Join request")
        case RequestType.linkRequest.rawValue:     return L10n.t("طلب ربط", "Link request")
        case RequestType.accountDelete.rawValue:   return L10n.t("حذف الحساب", "Account deletion")
        case RequestType.privacyRequest.rawValue:  return L10n.t("طلب خصوصية", "Privacy request")
        case RequestType.relativeAdd.rawValue:     return L10n.t("إضافة قريبة", "Add relative")
        case "contact_message":                    return L10n.t("رسالة", "Message")
        default:                                   return L10n.t("طلب", "Request")
        }
    }

    /// مرحلة «مسار الموافقات»
    static func stage(_ raw: String) -> String {
        switch raw {
        case "review":  return L10n.t("المسار: مراجعة المختص", "Stage: specialist review")
        case "info":    return L10n.t("المسار: بانتظار معلومات", "Stage: awaiting info")
        case "approve": return L10n.t("المسار: بانتظار اعتماد المدير", "Stage: awaiting manager")
        case "execute": return L10n.t("المسار: بانتظار التنفيذ", "Stage: awaiting execution")
        default:        return raw
        }
    }
}

extension Notification.Name {
    /// «فتح الخبر» من مربّع الإشعار — الرئيسية تفتح صفحة الأخبار على الخبر (`userInfo["id"]`: UUID)
    static let openNewsPost = Notification.Name("openNewsPost")
}

extension String {
    /// الرمز بخطّه الرفيع بلا تعبئة (طلب المالك ٢٠٢٦-١١-٠١ «ايقونات الخفيفة») — يبقى كما هو إن لم يوجد بديل
    var dsLightSymbol: String {
        guard contains(".fill") else { return self }
        let outline = replacingOccurrences(of: ".fill", with: "")
        return UIImage(systemName: outline) != nil ? outline : self
    }
}
