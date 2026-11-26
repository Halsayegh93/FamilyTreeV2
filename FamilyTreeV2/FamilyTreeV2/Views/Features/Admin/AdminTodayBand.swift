import SwiftUI

// MARK: - رأس «اليوم» الكحلي — v2 الاتجاه «أ» «بطاقات العائلة الملوّنة» (اختيار المالك ٢٠٢٦-١١-٢٦، الوحدة V2-1)
//
// الرأس يحمل كل ما فوق «الأقسام»، بالترتيب (spec V2-1 البند ١، `directions.html#a`):
//  ١) «الإدارة» ٢٢، وتحته «مساء الخير، حسن» وكبسولة الدور «المالك» بإطار ذهبي؛ وفي الطرف أزرار الرأس دوائر ٤٤ (مكبّر
//     الصوت · البحث · الجرس) — يمرّرها «اليوم» كما هي (روابطها وصلاحياتها وعدد الجرس من عنده).
//  ٢) سطر التحية الذكي حبّةً ٤٤ بإطار ذهبي («● طلب خصوصية بانتظار ردّك ‹») — حين يقول شيئاً فقط
//     (`AdminTodayBandLogic.showsSmartPill`)؛ نصّه وبيته من منطق السطر نفسه (`AdminTodayLogic.smartLine`).
//  ٣) حلقات «العائلة» ورابطاها (`AdminCensusBand`، نوع مستقل) — لمن يرى `today.census` فقط (يمرّرها «اليوم» أو لا).
// الكحلي نفسه في الوضعين، ونصّه أبيض/ذهبي. يتمرّر مع الصفحة (منطقة شريط الحالة كحلية بـ`adminStatusBarCover` على الجذر).
// حارس المكدس: جسمه `AnyView`، والحلقات والأزرار `AnyView` من «اليوم».

struct AdminTodayBand: View {
    /// «مساء الخير، حسن»
    let greeting: String
    /// «المالك» / «المدير» … — nil = بلا كبسولة
    let role: String?
    /// أزرار الطرف (مكبّر الصوت · البحث · الجرس) — دوائر `AdminHeaderIcon`
    let buttons: AnyView
    /// سطر التحية الذكي — nil = يُحمَّل بعد
    let smartLine: AdminSmartLine?
    /// يفتح بيت السطر — nil = السطر بلا بيت لدورك (يُقرأ ولا يُضغط)
    let openSmartLine: (() -> Void)?
    /// اسم البيت للقارئ الصوتي («يفتح الوارد»)
    let smartHint: String?
    /// حلقات «العائلة» ورابطاها — nil لمن لا يرى `today.census`
    let census: AnyView?

    var body: some View {
        AnyView(AdminTodayBandBody(greeting: greeting, role: role, buttons: buttons, smartLine: smartLine,
                                   openSmartLine: openSmartLine, smartHint: smartHint, census: census))
    }
}

private struct AdminTodayBandBody: View {
    let greeting: String
    let role: String?
    let buttons: AnyView
    let smartLine: AdminSmartLine?
    let openSmartLine: (() -> Void)?
    let smartHint: String?
    let census: AnyView?

    @Environment(\.dsLandscape) private var landscape
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Hub.bandGap) {
            topRow
            if AdminTodayBandLogic.showsSmartPill(smartLine), let smartLine {
                smartPill(smartLine)
                    .transition(.opacity)
            }
            if let census {
                census
            }
        }
        .animation(DSMotion.fade, value: AdminTodayBandLogic.showsSmartPill(smartLine))
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth - 2 * DS.Spacing.lg)
        .padding(.horizontal, landscape ? DS.Spacing.xxl : DS.Spacing.lg)
        .padding(.top, DS.Hub.headerTop)
        .padding(.bottom, census == nil ? DS.Hub.headerBottom : DS.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminBandBackground(landscape: landscape)
        .dsLightStatusBar()
    }

    // MARK: العنوان والتحية والأزرار

    private var topRow: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(AdminArea.homeTitle)
                    .dsFont(.hubTitle)
                    .foregroundColor(DS.Color.headerTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(DS.Hub.bandMinScale)
                    .accessibilityAddTraits(.isHeader)
                // التحية والدور في سطر (في الوسط عمودياً)، وتحت بعض حين يضيق (الخط الكبير)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: DS.Spacing.sm) {
                        greetingText
                        if let role { roleCapsule(role) }
                    }
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        greetingText
                        if let role { roleCapsule(role) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DS.Spacing.xsm) { buttons }
        }
        .frame(minHeight: DS.Icon.tapTarget)
    }

    private var greetingText: some View {
        Text(verbatim: greeting)
            .dsFont(.subtitle)
            .foregroundColor(DS.Color.headerSubtitle)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// كبسولة الدور بإطار ذهبي بلا تعبئة (١٢)
    private func roleCapsule(_ role: String) -> some View {
        Text(role)
            .dsFont(.caption)
            .foregroundColor(DS.Hub.rolePillInk)
            .lineLimit(1)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs)
            .overlay(Capsule().strokeBorder(DS.Hub.rolePillStroke, lineWidth: DS.Border.width))
            .accessibilityLabel(L10n.t("دورك: \(role)", "Your role: \(role)"))
    }

    // MARK: سطر التحية حبّةً

    /// حبّة ٤٤ بإطار ذهبي: نقطة ذهبية · الجملة بيضاء ١٥ (سطر واحد يُقصّ، وأكثر من أحجام إمكانية الوصول) · سهم ذهبي إن فتح
    private func smartPill(_ line: AdminSmartLine) -> some View {
        let opens = openSmartLine != nil
        let shape = RoundedRectangle(cornerRadius: DS.Icon.tapTarget / 2, style: .continuous)
        let face = HStack(spacing: DS.Spacing.sm) {
            Circle()
                .fill(DS.Color.accentLight)
                .frame(width: DS.Hub.bandPillDot, height: DS.Hub.bandPillDot)
                .accessibilityHidden(true)
            Text(verbatim: line.text)
                .dsFont(.rowTitle)
                .foregroundColor(DS.Color.headerTitle)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            if opens {
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .dsGlyph(DS.Glyph.xs, weight: .semibold)
                    .foregroundColor(DS.Color.accentLight)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .frame(minHeight: DS.Icon.tapTarget)
        .background(shape.fill(DS.Hub.bandPillFill))
        .overlay(shape.strokeBorder(DS.Hub.bandPillStroke, lineWidth: DS.Border.width))
        .contentShape(shape)
        return Group {
            if let openSmartLine {
                Button(action: openSmartLine) { face }
                    .buttonStyle(DSPressStyle())
                    .accessibilityLabel(line.text)
                    .accessibilityHint(smartHint ?? "")
            } else {
                face
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(line.text)
            }
        }
    }
}
