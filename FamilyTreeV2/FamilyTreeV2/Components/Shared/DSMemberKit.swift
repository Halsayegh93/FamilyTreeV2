import SwiftUI
import UIKit

// MARK: - عُدّة تفاصيل العضو في الشجرتين (طلب المالك ٢٠٢٦-١٠-٢٤)
//
// «وين التلوين و الحركات» · «احجم الازرار نبي وحدها» · «ورني مربعات اكثر ترتيب» · «علم السعودية للرقم السعودي».
//
// كل أزرار التفاصيل بمواصفة الزرّ الواحد (`DSBoxButtonStyle`: ارتفاع ٤٤، زوايا ١٢، خط الزرّ، ضغطة النابض)
// وتختلف باللون والوزن فقط — لغة ألوان واحدة في شجرة العائلة وشجرة النساء:
//   • ذهبي الهوية = إجراء مباشر للإدارة («تعديل مباشر»، «الإدارة»)
//   • أخضر العائلة = إضافة أفراد («طلب إضافة»، «عائلتي»)
//   • كحلي القسم = «طلب تعديل» · رمادي = «إغلاق» · أحمر = الحذف
//   • «عرض التفاصيل» أخفّ وزناً: تعبئة خفيفة بلون المعلومة وسهم في قرص يدور مع التوسيع
// الحركة مرة واحدة عند الظهور (لا `repeatForever`)، و«تقليل الحركة»: ساكن تماماً.

enum DSMemberKit {
    // MARK: ألوان الأدوار (ألوان العائلة — لا ألوان حالة)
    /// إجراء مباشر للإدارة — ذهبي الهوية (تعبئته `goldFill` تحت النص الأبيض ≈ ٥٫٤:١)
    static var directTint: Color { DS.Color.accent }
    /// إضافة أفراد — أخضر العائلة (`palmFill`)
    static var addTint: Color { DS.Color.palm }
    /// ربط فرد موجود في الشجرة — بترولي الصلة
    static var linkTint: Color { DS.Color.sea }
    /// «عرض التفاصيل» — لون المعلومة
    static var detailsTint: Color { DS.Color.info }

    // MARK: حركة الرمز (بعد دخول صفّ الأزرار `dsStaggerIn`)
    static let iconDelay: Double = 0.42
    /// القلم يميل للخلف، ثم «يكتب» متجاوزاً قليلاً، ثم يستقر
    static let writeFrom: Double = -26
    static let writeOvershoot: Double = 10
    static let writeStep: Double = 0.17
    /// قفزة رمز الإضافة من أصغر
    static let popFrom: CGFloat = 0.5

    // MARK: لمعة تعبر الزرّ مرة
    static let shineDelay: Double = 0.62
    static let shineDuration: Double = 0.9
    static let shineWidth: CGFloat = 56
    static let shineOpacity: Double = 0.32
    static let shineAngle: Double = 18

    // MARK: «عرض التفاصيل»
    /// السهم يومئ للأسفل عند الظهور («في المزيد تحت»)
    static let nudge: CGFloat = 3
    static let nudgeDelay: Double = 0.75
    static let nudgeBack: Double = 0.42
    /// السحب لأعلى يوسّع المربّع، ولأسفل على رأسه يصغّره
    static let swipeDistance: CGFloat = 36
    static let swipeMinimum: CGFloat = 12

    // MARK: علم دولة الرقم
    /// تعبئة الشارة فوق الرأس الملوّن (أبيض خفيف) وإطارها
    static let flagFill: Double = 0.16
    static let flagStroke: Double = 0.3
}

// MARK: - الزرّ الواحد بحياة صغيرة

/// نفس الزرّ الواحد (`DSBoxButtonStyle`) بلون دوره، ورمزه يتحرّك مرة حين يظهر — القلم «يكتب» والإضافة
/// تقفز — ولمعة بيضاء تعبره مرة. اهتزازة خفيفة عند الضغط، ولا يُضغط مرتين متتاليتين (`TapDebouncer`).
struct DSLiveButton: View {
    enum Motion { case write, pop }

    let title: String
    let icon: String
    /// لون الدور (ذهبي/أخضر…) — nil = تعبئة القسم
    var tint: Color? = nil
    var motion: Motion = .pop
    var isLoading: Bool = false
    /// ما يفعله الزرّ للقارئ الصوتي
    var hint: String? = nil
    /// `.compact` = بعرض نصّه وشكل أصغر (رأس تفاصيل العضو)، و`.regular` = بعرض السطر (شريط الأزرار)
    var size: DSButtonSize = .regular
    let action: () -> Void

    init(_ title: String, icon: String, tint: Color? = nil, motion: Motion = .pop,
         isLoading: Bool = false, hint: String? = nil, size: DSButtonSize = .regular,
         action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.motion = motion
        self.isLoading = isLoading
        self.hint = hint
        self.size = size
        self.action = action
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// ٠ = قبل الحركة، ١ = تجاوز، ٢ = استقر
    @State private var phase = 0
    @State private var sweep: CGFloat = 0

    var body: some View {
        Button {
            guard TapDebouncer.shared.canFire("DSLiveButton_\(title)") else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: DSBox.buttonSpacing) {
                if isLoading {
                    ProgressView()
                        .tint(DS.Color.textOnPrimary)
                        .scaleEffect(DS.Spinner.buttonScale)
                } else {
                    Image(dsSymbol: icon)
                        .dsGlyph(size.glyph)
                        .rotationEffect(.degrees(iconAngle), anchor: .bottomLeading)
                        .scaleEffect(iconScale)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
        }
        .buttonStyle(DSBoxButtonStyle(size: size, tint: tint, fullWidth: size != .compact))
        .overlay { shine.padding(.vertical, size.hitInset) }
        .allowsHitTesting(!isLoading)
        .accessibilityHint(hint ?? "")
        .onAppear(perform: play)
    }

    private var iconAngle: Double {
        guard motion == .write, !reduceMotion else { return 0 }
        switch phase {
        case 0: return DSMemberKit.writeFrom
        case 1: return DSMemberKit.writeOvershoot
        default: return 0
        }
    }

    private var iconScale: CGFloat {
        guard motion == .pop, !reduceMotion else { return 1 }
        return phase == 0 ? DSMemberKit.popFrom : 1
    }

    /// لمعة تبدأ وتنتهي خارج الزرّ (مقصوصة بشكله) — لا تُرى إلا وهي تعبره
    private var shine: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, DS.Color.textOnPrimary.opacity(DSMemberKit.shineOpacity), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: DSMemberKit.shineWidth)
                .rotationEffect(.degrees(DSMemberKit.shineAngle))
                .offset(x: -DSMemberKit.shineWidth * 1.5 + sweep * (geo.size.width + DSMemberKit.shineWidth * 3))
        }
        .clipShape(DSBox.buttonShape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func play() {
        guard phase == 0 else { return }
        guard !reduceMotion else { phase = 2; return }
        switch motion {
        case .write:
            withAnimation(DS.Anim.snappy.delay(DSMemberKit.iconDelay)) { phase = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + DSMemberKit.iconDelay + DSMemberKit.writeStep) {
                withAnimation(DS.Anim.elastic) { phase = 2 }
            }
        case .pop:
            withAnimation(DS.Anim.elastic.delay(DSMemberKit.iconDelay)) { phase = 2 }
        }
        withAnimation(.easeInOut(duration: DSMemberKit.shineDuration).delay(DSMemberKit.shineDelay)) { sweep = 1 }
    }
}

// MARK: - «عرض التفاصيل» / «إخفاء التفاصيل»

/// زرّ مدمج ممتلئ بلون المعلومة ونصّ أبيض (طلب المالك ٢٠٢٦-١٠-٢٥ «مملوء وصغر حجمه»): شكله ٣٦ بعرض نصّه
/// ومساحة لمسه ٤٤، وسهم في قرص أبيض يدور نصف دورة مع التوسيع ويومئ للأسفل مرة عند الظهور. نفسه في
/// الشجرتين — والسحب لأعلى على المربّع (ولأسفل على رأسه) يفعل الشيء نفسه (`dsDetailsSwipe`).
struct DSDetailsToggle: View {
    let isExpanded: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nudge: CGFloat = 0
    @State private var played = false

    var body: some View {
        let ink = DSMemberKit.detailsTint
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            HStack(spacing: DSBox.buttonSpacing) {
                Text(isExpanded ? L10n.t("إخفاء التفاصيل", "Hide details") : L10n.t("عرض التفاصيل", "Show details"))
                    .font(DSBox.buttonFontCompact)
                    .dsButtonLabelFit()
                    .id(isExpanded)
                    .transition(.opacity)
                Image(systemName: "chevron.down")
                    .dsGlyph(DS.Glyph.xs)
                    .foregroundColor(ink.dsSolidFill)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .frame(width: DS.Icon.section, height: DS.Icon.section)
                    .background(Circle().fill(DS.Color.textOnPrimary))
                    .offset(y: nudge)
                    .accessibilityHidden(true)
            }
            .foregroundColor(DS.Color.textOnPrimary)
            .padding(.horizontal, DS.Spacing.md)
            .frame(minHeight: DSBox.buttonHeightCompact)
            .background(DSBox.buttonShape.fill(ink.dsSolidFill))
            // مساحة لمس ٤٤ رغم الشكل الأصغر (حدّ أبل)
            .padding(.vertical, DSButtonSize.compact.hitInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .animation(reduceMotion ? nil : DS.Anim.smooth, value: isExpanded)
        .accessibilityLabel(isExpanded ? L10n.t("إخفاء التفاصيل", "Hide details") : L10n.t("عرض التفاصيل", "Show details"))
        .accessibilityHint(isExpanded ? L10n.t("يصغّر المربّع", "Collapses the box")
                                      : L10n.t("يعرض المعلومات والعائلة", "Shows the info and family"))
        .onAppear(perform: playNudge)
    }

    /// إيماءة واحدة للأسفل ثم رجوع — مرة عند الظهور فقط
    private func playNudge() {
        guard !played, !reduceMotion, !isExpanded else { return }
        played = true
        withAnimation(DS.Anim.elastic.delay(DSMemberKit.nudgeDelay)) { nudge = DSMemberKit.nudge }
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMemberKit.nudgeDelay + DSMemberKit.nudgeBack) {
            withAnimation(DS.Anim.bouncy) { nudge = 0 }
        }
    }
}

extension View {
    /// السحب العمودي على مربّع التفاصيل: لأعلى يوسّعه (`expands`)، ولأسفل يصغّره (`collapses`) — مع زرّ
    /// «عرض التفاصيل» لا بدله. لا يأخذ اللمس من الأزرار (`simultaneousGesture` بمسافة دنيا).
    func dsDetailsSwipe(expands: Bool = false, collapses: Bool = false,
                        perform: @escaping (_ expand: Bool) -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: DSMemberKit.swipeMinimum)
                .onEnded { value in
                    let dy = value.translation.height
                    guard abs(dy) > abs(value.translation.width) else { return }
                    if expands && dy < -DSMemberKit.swipeDistance { perform(true) }
                    if collapses && dy > DSMemberKit.swipeDistance { perform(false) }
                },
            including: (expands || collapses) ? .all : .subviews
        )
    }
}

// MARK: - مربّعات الإجراءات بلا يتيم

/// شبكة المربّعات: عمود ثابت العرض لكل المربّعات (٣ في السطر، أو ٢ مع خطوط إمكانية الوصول)، والأسطر
/// متوازنة (٤ = ٢+٢، ٥ = ٣+٢، ٧ = ٣+٢+٢) وكل سطر ناقص يتوسّط — فلا مربّع وحيد بجانبه فراغ، ولا مربّع بمقاس
/// آخر. المربّع مربّع (العرض = الارتفاع)، أو بارتفاع أطولها نصّاً مع خطوط إمكانية الوصول.
/// (الاتجاه يتبع الواجهة تلقائياً — الأول يميناً في العربية)
struct DSTileGridLayout: Layout {
    var columns: Int = 3
    var spacing: CGFloat = DS.Spacing.sm
    var square: Bool = true

    /// عدد المربّعات في كل سطر — أقل عدد أسطر، والفرق بين الأسطر واحد على الأكثر (الأطول أولاً)
    static func rows(count n: Int, columns c: Int) -> [Int] {
        guard n > 0, c > 0 else { return [] }
        let r = (n + c - 1) / c
        let base = n / r, extra = n % r
        return (0..<r).map { $0 < extra ? base + 1 : base }
    }

    private var columnCount: Int { max(1, columns) }

    private func tileWidth(_ width: CGFloat) -> CGFloat {
        max(0, (width - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount))
    }

    private func tileHeight(_ w: CGFloat, _ subviews: Subviews) -> CGFloat {
        guard !square else { return w }
        return subviews.map { $0.sizeThatFits(ProposedViewSize(width: w, height: nil)).height }.max() ?? w
    }

    /// العرض المقترح محدوداً: الحاويات تسأل بلا عرض أو بعرض لا نهائي (لمعرفة المرونة) — المربّع بعرضه
    /// يصير ارتفاعاً لا نهائياً («Invalid frame dimension» ثم تعليق التخطيط)، فنجيب بعرض مثالي ثابت
    private func finiteWidth(_ proposed: CGFloat?) -> CGFloat {
        guard let proposed, proposed.isFinite else { return DS.Landscape.columnMinWidth }
        return max(0, proposed)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = finiteWidth(proposal.width)
        let h = tileHeight(tileWidth(width), subviews)
        let count = Self.rows(count: subviews.count, columns: columnCount).count
        return CGSize(width: width, height: CGFloat(count) * h + CGFloat(max(0, count - 1)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = tileWidth(bounds.width)
        let h = tileHeight(w, subviews)
        var index = 0
        var y = bounds.minY
        for k in Self.rows(count: subviews.count, columns: columnCount) {
            let rowWidth = CGFloat(k) * w + CGFloat(max(0, k - 1)) * spacing
            var x = bounds.minX + (bounds.width - rowWidth) / 2
            for _ in 0..<k {
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: w, height: h))
                x += w + spacing
                index += 1
            }
            y += h + spacing
        }
    }
}

/// مربّع إجراء: قرص أيقونة بلون مجموعته وتحته اسم الإجراء، على تعبئة خفيفة من اللون وإطار رفيع منه —
/// لون واحد لكل مجموعة (إضافة · ربط · السجل)، والحذف زرّ أحمر وحده خارج الشبكة
struct DSActionTile: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void
    /// فوق سطر ملوّن (`dsActionTileBand`): المربّع أبيض ليبرز على خلفية سطره
    @Environment(\.dsTileOnBand) private var onBand

    init(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.action = action
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        Button {
            guard TapDebouncer.shared.canFire("DSActionTile_\(title)") else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            // ملمومة وأصغر (طلب المالك ٢٠٢٦-١٠-٢٥ «ملمومة يم بعض وحجمهم أصغر»): قرص ٣٢ وحشوة ٤
            VStack(spacing: DS.Spacing.xs) {
                // قرص ممتلئ بلون المجموعة ورمز أبيض (مثل أيقونات الإعدادات في الآيفون) — التعبئة الثابتة
                // (`dsSolidFill`) تبقي الأبيض مقروءاً في الوضعين؛ على السطر الملوّن أصغر (٤ في السطر)
                Image(dsSymbol: icon)
                    .dsGlyph(onBand ? DS.Glyph.sm : DS.Glyph.md)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .frame(width: onBand ? DS.Icon.discSmall : DS.Icon.row, height: onBand ? DS.Icon.discSmall : DS.Icon.row)
                    .background(Circle().fill(tint.dsSolidFill))
                    .accessibilityHidden(true)
                Text(title)
                    .dsFieldFont(onBand ? .caption : .chip)
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(DSBox.buttonLabelMinScale)
            }
            .padding(.vertical, DS.Spacing.sm)
            .padding(.horizontal, DS.Spacing.xs)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(onBand ? DS.Color.surface : tint.opacity(DS.Opacity.tintFillSoft)))
            .overlay(shape.strokeBorder(tint.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
            .contentShape(shape)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(title)
    }
}

/// شبكة مربّعات جاهزة: ٣ في السطر (و٢ مع خطوط إمكانية الوصول) — ملمومة: فاصل ٤ وارتفاع المربّع على قدر
/// محتواه (لا مربّع كامل) فتقصر الشبكة
struct DSActionTileGrid<Content: View>: View {
    /// عدد المربّعات في السطر (٣، أو ٤ للمربّعات الصغيرة) — ويقلّ واحداً مع خطوط إمكانية الوصول
    var columns: Int = 3
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let large = typeSize.isAccessibilitySize
        DSTileGridLayout(columns: large ? max(2, columns - 2) : columns, spacing: DS.Spacing.xs, square: false) {
            content()
        }
    }
}

// MARK: - علم دولة الرقم (غير الكويت)

/// دولة رقم الهاتف لعرض علمها — الكويت (الافتراضي) بلا علم، ودولة من قائمة `KuwaitPhone` بعلمها، وأي رمز
/// دولي آخر بكرة أرضية
struct DSPhoneOrigin {
    /// العلم، أو nil = دولة خارج القائمة (كرة أرضية)
    let flag: String?
    let name: String

    init?(_ raw: String?) {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let country = KuwaitPhone.detectCountryAndLocal(raw).country
        let home = KuwaitPhone.defaultCountry
        if country.isoCode != home.isoCode {
            flag = country.flag
            name = L10n.t(country.nameArabic,
                          Locale(identifier: "en").localizedString(forRegionCode: country.isoCode) ?? country.isoCode)
            return
        }
        // رمز دولي لا تعرفه القائمة (ليس +965) — كرة أرضية
        let normalized = KuwaitPhone.normalizeDigits(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = normalized.filter(\.isNumber)
        let international = normalized.hasPrefix("+") || normalized.hasPrefix("00")
        let afterPlus = normalized.hasPrefix("00") ? String(digits.dropFirst(2)) : digits
        let homeCode = home.dialingCode.filter(\.isNumber)
        guard international, !afterPlus.hasPrefix(homeCode) else { return nil }
        flag = nil
        name = L10n.t("خارج الكويت", "outside Kuwait")
    }
}

extension FamilyMember {
    /// الرقم إن كان يحقّ للمشاهد رؤيته — نفس قاعدة صفّ «الهاتف»: المخفي يراه صاحبه والإدارة فقط،
    /// ولا رقم للمتوفى (والسيرفر يحجب المخفي أصلاً عن غيرهم)
    func dsVisiblePhone(viewerId: UUID?, viewerCanModerate: Bool) -> String? {
        guard isDeceased != true, let phone = phoneNumber,
              !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if isPhoneHidden == true && id != viewerId && !viewerCanModerate { return nil }
        return phone
    }
}

/// شارة صغيرة بعلم دولة الرقم في زاوية الرأس الملوّن لتفاصيل العضو (طلب المالك ٢٠٢٦-١٠-٢٤
/// «علم السعودية للرقم السعودي … بالزاوية فوق») — لا شيء للرقم الكويتي أو بلا رقم مسموح
struct DSPhoneCountryBadge: View {
    /// الرقم بعد فحص الخصوصية (`dsVisiblePhone`)
    let phone: String?

    var body: some View {
        if let origin = DSPhoneOrigin(phone) {
            Group {
                if let flag = origin.flag {
                    Text(flag).dsFont(.tabTitle)
                } else {
                    Image(systemName: "globe")
                        .dsGlyph(DS.Glyph.lg)
                        .foregroundColor(DS.Color.textOnPrimary)
                }
            }
            .frame(minWidth: DS.Icon.rowLarge, minHeight: DS.Icon.row)
            .padding(.horizontal, DS.Spacing.xs)
            .background(Capsule().fill(DS.Color.textOnPrimary.opacity(DSMemberKit.flagFill)))
            .overlay(Capsule().strokeBorder(DS.Color.textOnPrimary.opacity(DSMemberKit.flagStroke),
                                            lineWidth: DS.Border.width))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.t("رقم من \(origin.name)", "Phone from \(origin.name)"))
        }
    }
}

// MARK: - سطر مربّعات بخلفية لونه

private struct DSTileOnBandKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// مربّعات الإجراءات فوق سطر ملوّن — تُرسم بيضاء
    var dsTileOnBand: Bool {
        get { self[DSTileOnBandKey.self] }
        set { self[DSTileOnBandKey.self] = newValue }
    }
}

extension View {
    /// كل سطر مربّعات بخلفية لون مجموعته الخفيف (طلب المالك ٢٠٢٦-١٠-٢٥ «خلفية عند كل سطر») —
    /// والمربّعات فوقه بيضاء بإطار لونها
    func dsActionTileBand(_ tint: Color) -> some View {
        environment(\.dsTileOnBand, true)
            .padding(DS.Spacing.xs)
            .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(tint.opacity(DS.Opacity.tintFill)))
    }
}
