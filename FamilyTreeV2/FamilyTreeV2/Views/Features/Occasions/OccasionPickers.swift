import SwiftUI

// MARK: - «بوستات المناسبات»: المبدّل والقائمة المنسدلة الملوّنة
// طلب المالك ٢٠٢٦-١٠-١٢: «تصميم الزر مو تفاعلي» ← «قائمة منسدلة للطويل» و«خل القوائم بتصميم تفاعلي و ملون».
// المجموعات القصيرة (≤ ٤) = مبدّل متصل واحد (OccasionSegmented)، والطويلة = حقل منسدل (OccasionDropdown)
// يفتح قائمة ملوّنة بلون تصميم البوست (OccasionPickerSheet). «نص آخر» آخر عنصر بالقائمة.

// MARK: ألوان النوع

/// ألوان واجهة شاشة النوع — من ألوان تصميم البوست نفسه (مثل `tileStyle`)، لذلك هنا وليست في DS.Color:
/// الزواج ذهبي، المولود سماوي، المولودة وردي، الشفاء أخضر، التخرج كحلي وذهبي، الوفاة داكن وذهبي، مشاركة العزاء رمادي.
/// كل نص فوق `fill` بلون `onFill` بتباين ≥ ٤٫٥.
struct OccasionAccent {
    /// تعبئة المختار (إبهام المبدّل، الصف المختار، الأزرار الممتلئة)
    let fill: Color
    let onFill: Color
    /// أيقونات وروابط على سطح الصفحة (يتكيّف مع الوضع الداكن)
    let ink: Color
    /// إطار الحقول
    let line: Color
    /// الحقل: قاعدة + صبغة خفيفة فوقها
    let fieldBase: Color
    let fieldTint: Color
    let fieldText: Color
    let fieldSecondary: Color
    let fieldGlyph: Color
    /// رأس القائمة المفتوحة
    let header: [Color]
    let headerText: Color
    let headerGlyph: Color
    /// القائمة المفتوحة: الخلفية والصفوف
    let sheetBase: Color
    let sheetTint: Color
    let row: Color
    let rowText: Color
    let rowSecondary: Color
    /// الوفاة: داكن وذهبي في الوضعين
    let isDark: Bool

    /// الأنواع الفاتحة: لون واحد للتعبئة + درجة أعمق للرأس + لون فاتح للوضع الداكن + لون الإطار
    private static func light(_ fill: String, deep: String, inkDark: String, line: String,
                              glyph: (String, String)? = nil) -> OccasionAccent {
        let ink = Color.adaptive(light: fill, dark: inkDark)
        let glyphColor = glyph.map { Color.adaptive(light: $0.0, dark: $0.1) } ?? ink
        return OccasionAccent(
            fill: Color(hex: fill), onFill: .white, ink: ink, line: Color(hex: line),
            fieldBase: DS.Color.background, fieldTint: ink.opacity(OccasionUI.fieldTintOpacity),
            fieldText: DS.Color.textPrimary, fieldSecondary: DS.Color.textSecondary, fieldGlyph: glyphColor,
            header: [Color(hex: fill), Color(hex: deep)], headerText: .white,
            headerGlyph: glyph.map { Color(hex: $0.1) } ?? .white,
            sheetBase: DS.Color.surface, sheetTint: ink.opacity(OccasionUI.sheetTintOpacity),
            row: DS.Color.background, rowText: DS.Color.textPrimary, rowSecondary: DS.Color.textSecondary,
            isDark: false
        )
    }

    static let gold = light("#8A6A22", deep: "#6E5418", inkDark: "#E0C27A", line: "#C9A24A")
    static let sky = light("#1F6FA3", deep: "#175288", inkDark: "#8CC3EA", line: "#5FA8DA")
    static let rose = light("#9A4E5B", deep: "#7D3F4A", inkDark: "#E8A9B4", line: "#D0909A")
    static let green = light("#216C4F", deep: "#164C38", inkDark: "#7FC9A8", line: "#4A9E7C")
    /// التخرج: كحلي للتعبئة وذهبي للأيقونات والإطار
    static let navy = light("#1B3558", deep: "#0F2340", inkDark: "#9DB6DA", line: "#C9A24A", glyph: ("#8A6A22", "#E0C27A"))
    static let slate = light("#4A5560", deep: "#353E47", inkDark: "#B8C2CC", line: "#8A96A2")

    /// الوفاة: حقول داكنة بذهبي (مثل البوست ومربّعه)، والمختار ذهبي بنص داكن
    static let deathGold: OccasionAccent = {
        let gold = OccasionDeathPalette.gold
        let dark = OccasionDeathPalette.root
        return OccasionAccent(
            fill: gold, onFill: dark, ink: Color.adaptive(light: "#8A6A22", dark: "#E9D5A6"), line: gold,
            fieldBase: Color(hex: "#1D2229"), fieldTint: .clear,
            fieldText: Color(hex: "#F1F2F4"), fieldSecondary: OccasionDeathPalette.grey, fieldGlyph: gold,
            header: [Color(hex: "#2A3038"), dark], headerText: gold, headerGlyph: gold,
            sheetBase: dark, sheetTint: .clear,
            row: Color(hex: "#20252D"), rowText: Color(hex: "#F1F2F4"), rowSecondary: OccasionDeathPalette.grey,
            isDark: true
        )
    }()
}

extension OccasionTemplate {
    var accent: OccasionAccent {
        switch kind {
        case .death, .deathText: return .deathGold
        case .solace: return .slate
        case .happy:
            switch id {
            case "newborn": return .sky
            case "newbornGirl": return .rose
            case "recovery": return .green
            case "graduation": return .navy
            default: return .gold
            }
        }
    }
}

private struct OccasionAccentKey: EnvironmentKey {
    static let defaultValue = OccasionAccent.gold
}

extension EnvironmentValues {
    /// ألوان نوع البوست المفتوح — تضعها شاشة النوع (`OccasionPostEditorView`)
    var occasionAccent: OccasionAccent {
        get { self[OccasionAccentKey.self] }
        set { self[OccasionAccentKey.self] = newValue }
    }
}

// MARK: الحقل البارز (خلفية مصبوغة + إطار + ظل خفيف، والضغط يغمّقه)

struct OccasionFieldChrome: ViewModifier {
    var pressed = false
    var radius: CGFloat = DS.Radius.md
    var raised = true
    @Environment(\.occasionAccent) private var accent

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(accent.fieldBase)
                    shape.fill(accent.fieldTint)
                    shape.fill(accent.isDark ? Color.white.opacity(pressed ? OccasionUI.pressDarken : 0)
                                             : accent.ink.opacity(pressed ? OccasionUI.pressDarken : 0))
                }
            }
            .overlay(shape.strokeBorder(accent.line.opacity(accent.isDark ? OccasionUI.lineOpacityDark : OccasionUI.lineOpacity),
                                        lineWidth: DS.Border.width))
            .shadow(color: raised ? accent.fill.opacity(pressed ? OccasionUI.shadowPressed : OccasionUI.shadowOpacity) : .clear,
                    radius: pressed ? OccasionUI.shadowRadiusPressed : OccasionUI.shadowRadius,
                    y: pressed ? OccasionUI.shadowYPressed : OccasionUI.shadowY)
    }
}

/// ضغط الحقل البارز: يصغر شوي ويغمق. «تقليل الحركة»: يغمق بس
struct OccasionFieldButtonStyle: ButtonStyle {
    var radius: CGFloat = DS.Radius.md

    func makeBody(configuration: Configuration) -> some View {
        OccasionFieldPressLabel(configuration: configuration, radius: radius)
    }
}

private struct OccasionFieldPressLabel: View {
    let configuration: ButtonStyleConfiguration
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .modifier(OccasionFieldChrome(pressed: configuration.isPressed, radius: radius))
            .scaleEffect(configuration.isPressed && !reduceMotion ? OccasionUI.pressScaleWide : 1)
            .animation(reduceMotion ? nil : OccasionUI.press, value: configuration.isPressed)
    }
}

// MARK: المبدّل المتصل (المجموعات القصيرة ≤ ٤)

/// مبدّل متصل بسطر واحد: المختار يتزحلق لمكانه بلون النوع، مع اهتزاز خفيف وضغط.
/// «تقليل الحركة»: يتلاشى بدل ما يتزحلق. `compact` = بعرض محتواه (إظهار/إخفاء في رأس البطاقة).
struct OccasionSegmented<ID: Hashable>: View {
    struct Option: Identifiable {
        let id: ID
        let title: String
        var icon: String? = nil
        var enabled: Bool = true
        var accessibilityText: String? = nil
    }

    let options: [Option]
    @Binding var selection: ID
    var compact = false
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.occasionAccent) private var accent

    var body: some View {
        let track = Capsule()
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(OccasionUI.segmentInset)
        .background {
            ZStack {
                track.fill(accent.fieldBase)
                track.fill(accent.fieldTint)
            }
        }
        .overlay(track.strokeBorder(accent.line.opacity(accent.isDark ? OccasionUI.lineOpacityDark : OccasionUI.lineOpacity),
                                    lineWidth: DS.Border.width))
        .shadow(color: accent.fill.opacity(OccasionUI.shadowOpacity), radius: OccasionUI.shadowRadius, y: OccasionUI.shadowY)
    }

    private func segment(_ option: Option) -> some View {
        let on = option.id == selection
        return Button {
            guard !on else { return }
            OccasionHaptic.select()
            withAnimation(reduceMotion ? OccasionUI.fade : OccasionUI.slide) { selection = option.id }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                if let icon = option.icon {
                    Image(systemName: icon)
                        .dsGlyph(DS.Glyph.sm)
                        .accessibilityHidden(true)
                }
                Text(option.title)
                    .dsFont(.segmentCompact)
                    .lineLimit(1)
                    .minimumScaleFactor(OccasionUI.segmentMinScale)
            }
            .foregroundColor(on ? accent.onFill : accent.fieldSecondary)
            .padding(.horizontal, compact ? DS.Spacing.md : DS.Spacing.xs)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: OccasionUI.segmentHeight)
            .background {
                if on {
                    if reduceMotion {
                        Capsule().fill(accent.fill).transition(.opacity)
                    } else {
                        Capsule().fill(accent.fill)
                            .shadow(color: accent.fill.opacity(OccasionUI.thumbShadow), radius: OccasionUI.shadowRadius, y: OccasionUI.shadowY)
                            .matchedGeometryEffect(id: "thumb", in: ns)
                    }
                }
            }
            .contentShape(Capsule())
            .dsTapArea(width: OccasionUI.segmentHeight, height: OccasionUI.segmentHeight)
        }
        .buttonStyle(OccasionPressStyle())
        .disabled(!option.enabled)
        .opacity(option.enabled ? 1 : DSActionFill.disabledOpacity)
        .accessibilityLabel(option.accessibilityText ?? option.title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: الحقل المنسدل

/// الحقل نفسه: أيقونة ملوّنة + القيمة (وسطر صغير اختياري) + سهم — حقل بارز واضح أنه ينضغط
struct OccasionDropdownField: View {
    let icon: String
    let value: String?
    var detail: String? = nil
    var placeholder: String = L10n.t("اختر من القائمة", "Choose from the list")
    var isCustom = false
    var accessibilityLabel: String = ""
    let action: () -> Void

    @Environment(\.occasionAccent) private var accent

    var body: some View {
        Button {
            OccasionHaptic.select()
            action()
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: isCustom ? "pencil" : icon)
                    .dsGlyph(DS.Glyph.sm)
                    .foregroundColor(accent.fieldGlyph)
                    .frame(width: OccasionUI.fieldIcon, height: OccasionUI.fieldIcon)
                    .background(Circle().fill(accent.fieldGlyph.opacity(OccasionUI.iconDiscOpacity)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(value ?? placeholder)
                        .dsFont(value == nil ? .footnote : OccasionUI.fieldValue)
                        .foregroundColor(value == nil ? accent.fieldSecondary : accent.fieldText)
                        .lineLimit(OccasionUI.fieldLines)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .dsFont(.caption)
                            .foregroundColor(accent.fieldSecondary)
                            .lineLimit(1)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .dsGlyph(DS.Glyph.xs)
                    .foregroundColor(accent.fieldGlyph)
                    .accessibilityHidden(true)
            }
            .padding(.leading, DS.Spacing.xsm)
            .padding(.trailing, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xsm)
            .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .buttonStyle(OccasionFieldButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue([value ?? placeholder, detail].compactMap { $0 }.joined(separator: "، "))
        .accessibilityHint(L10n.t("يفتح القائمة", "Opens the list"))
    }
}

/// عنصر في القائمة المفتوحة
struct OccasionPickRow: Identifiable {
    enum Kind { case option, none, custom }
    let id: String
    let title: String
    var subtitle: String? = nil
    var kind: Kind = .option
    /// نص إضافي للبحث (المنطقة، المحافظة…)
    var keywords: String = ""
}

struct OccasionPickSection: Identifiable {
    let id: String
    var title: String? = nil
    let rows: [OccasionPickRow]
}

/// معرّف «نص آخر» في القوائم
enum OccasionPick {
    static let customID = "__custom"
}

/// حقل منسدل لقائمة اختيارات: «بدون» (اختياري) = رقم بعد آخر عنصر؛ «نص آخر» = ‎-1 (آخر عنصر) ويظهر حقل كتابة تحته
struct OccasionDropdown: View {
    var label: String? = nil
    /// عنوان القائمة المفتوحة (الافتراضي العنوان فوق الحقل)
    var title: String? = nil
    let icon: String
    let options: [String]
    let selected: Int
    let onSelect: (Int) -> Void
    var noneLabel: String? = nil
    var custom: OccasionCustomOption? = nil
    /// سطر صغير تحت كل اختيار (اختياري — مقاس مكان النشر مثلاً)
    var details: [String]? = nil
    /// نصوص طويلة (الدعاء): الصفوف تلتف
    var longText = false
    var searchable = false

    @State private var open = false
    @State private var focusAfterClose = false
    @FocusState private var customFocused: Bool
    @Environment(\.occasionAccent) private var accent

    private var customTitle: String { custom?.label ?? L10n.t("نص آخر", "Other") }

    private var current: String? {
        if selected == -1, custom != nil { return customTitle }
        if options.indices.contains(selected) { return options[selected] }
        if let noneLabel, selected == options.count { return noneLabel }
        return nil
    }

    private var rows: [OccasionPickRow] {
        var out = options.enumerated().map { i, title in
            OccasionPickRow(id: String(i), title: title, subtitle: details.flatMap { $0.indices.contains(i) ? $0[i] : nil })
        }
        if let noneLabel { out.append(OccasionPickRow(id: String(options.count), title: noneLabel, kind: .none)) }
        if custom != nil { out.append(OccasionPickRow(id: OccasionPick.customID, title: customTitle, kind: .custom)) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            if let label { OccasionFieldLabel(label) }
            OccasionDropdownField(icon: icon, value: current,
                                  detail: details.flatMap { $0.indices.contains(selected) ? $0[selected] : nil },
                                  isCustom: selected == -1 && custom != nil,
                                  accessibilityLabel: label ?? title ?? "") { open = true }
            if let custom, selected == -1 {
                OccasionTextInput(text: custom.text, placeholder: custom.placeholder, multiline: custom.multiline || longText)
                    .focused($customFocused)
            }
        }
        .sheet(isPresented: $open, onDismiss: {
            guard focusAfterClose else { return }
            focusAfterClose = false
            customFocused = true
        }) {
            OccasionPickerSheet(
                title: title ?? label ?? "",
                icon: icon,
                sections: [OccasionPickSection(id: "all", rows: rows)],
                selectedID: selected == -1 ? OccasionPick.customID : String(selected),
                longText: longText,
                searchable: searchable
            ) { id in
                if id == OccasionPick.customID {
                    focusAfterClose = true
                    onSelect(-1)
                } else if let i = Int(id) {
                    onSelect(i)
                }
            }
            .environment(\.occasionAccent, accent)
        }
    }
}

// MARK: القائمة المفتوحة (ورقة ملوّنة بلون النوع)

/// رأس ملوّن بعنوان الحقل وأيقونته، بحث مصبوغ (للقوائم الطويلة)، صفوف بطاقات بأيقونة صغيرة ملوّنة؛
/// المختار ممتلئ بلون النوع وعلامة ✓. الصفوف تدخل بتلاشي متتابع قصير («تقليل الحركة»: بدونه).
/// الضغط: تمييز سريع + اهتزاز ثم تتسكّر.
struct OccasionPickerSheet: View {
    let title: String
    let icon: String
    let sections: [OccasionPickSection]
    let selectedID: String?
    var longText = false
    var searchable = false
    var searchPrompt: String = L10n.t("ابحث…", "Search…")
    var emptyText: String = L10n.t("ما لقينا شي بهالاسم — اختر «نص آخر» واكتبه.", "No match — choose “Other” and type it.")
    let onPick: (String) -> Void

    @Environment(\.occasionAccent) private var accent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var flashID: String?
    @State private var appeared = false

    private var filtered: [OccasionPickSection] {
        let tokens = OccasionFamilyIndex.normalize(query).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return sections }
        return sections.compactMap { s in
            let rows = s.rows.filter { r in
                if r.kind == .custom { return true }
                if r.kind == .none { return false }
                let hay = OccasionFamilyIndex.normalize("\(r.title) \(r.subtitle ?? "") \(r.keywords) \(s.title ?? "")")
                return tokens.allSatisfy { hay.contains($0) }
            }
            return rows.isEmpty ? nil : OccasionPickSection(id: s.id, title: s.title, rows: rows)
        }
    }

    var body: some View {
        let groups = filtered
        let onlyCustom = !groups.flatMap(\.rows).contains { $0.kind != .custom }
        VStack(spacing: 0) {
            header
            if searchable { searchField }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OccasionUI.rowSpacing) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { gi, group in
                        if let t = group.title {
                            Text(t)
                                .dsFont(.label)
                                .foregroundColor(accent.isDark ? accent.fieldGlyph : accent.ink)
                                .padding(.top, gi == 0 ? 0 : DS.Spacing.sm)
                                .padding(.horizontal, DS.Spacing.xs)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(group.rows) { r in
                            row(r, order: order(of: r.id, in: groups))
                        }
                    }
                    if onlyCustom && !query.isEmpty {
                        Text(emptyText)
                            .dsFont(.footnote)
                            .foregroundColor(accent.rowSecondary)
                            .padding(.horizontal, DS.Spacing.xs)
                    }
                }
                .padding(DS.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background {
            ZStack {
                accent.sheetBase
                accent.sheetTint
            }
            .ignoresSafeArea()
        }
        // الورقة ما ترث اتجاه التطبيق (تنعرض من UIKit) — نفس ما يسوي DSAlert
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .modifier(OccasionSheetCorner())
        .onAppear {
            if reduceMotion { appeared = true } else { DispatchQueue.main.async { appeared = true } }
        }
    }

    // ارتفاع الورقة: القصيرة على قدّها، والطويلة (والبحث) كاملة
    private var detents: Set<PresentationDetent> {
        let count = sections.reduce(0) { $0 + $1.rows.count }
        if searchable { return [.large] }
        let rowH = longText ? OccasionUI.sheetRowEstimateLong : OccasionUI.sheetRowEstimate
        let est = OccasionUI.sheetChromeEstimate + CGFloat(count) * rowH
        return est < OccasionUI.sheetMaxFitHeight ? [.height(est), .large] : [.medium, .large]
    }

    private func order(of id: String, in groups: [OccasionPickSection]) -> Int {
        var n = 0
        for g in groups {
            for r in g.rows {
                if r.id == id { return n }
                n += 1
            }
        }
        return n
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .dsGlyph(DS.Glyph.lg)
                .foregroundColor(accent.headerGlyph)
                .frame(width: OccasionUI.headerIcon, height: OccasionUI.headerIcon)
                .background(Circle().fill(accent.headerGlyph.opacity(OccasionUI.headerDiscOpacity)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.headline)
                    .foregroundColor(accent.headerText)
                    .lineLimit(2)
                Text(L10n.t("اختر من القائمة", "Choose from the list"))
                    .dsFont(.caption)
                    .foregroundColor(accent.headerText)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .dsGlyph(DS.Glyph.sm)
                    .foregroundColor(accent.headerText)
                    .frame(width: OccasionUI.headerClose, height: OccasionUI.headerClose)
                    .background(Circle().fill(accent.headerText.opacity(OccasionUI.headerDiscOpacity)))
                    .dsTapArea(width: OccasionUI.headerClose, height: OccasionUI.headerClose)
            }
            .buttonStyle(OccasionPressStyle())
            .accessibilityLabel(L10n.t("إغلاق", "Close"))
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.xl + DS.Spacing.xs)
        .padding(.bottom, DS.Spacing.md)
        .background(
            LinearGradient(colors: accent.header, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea(edges: .top)
        )
    }

    private var searchField: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .dsGlyph(DS.Glyph.sm)
                .foregroundColor(accent.fieldGlyph)
                .accessibilityHidden(true)
            TextField("", text: $query, prompt: Text(searchPrompt).foregroundColor(accent.fieldSecondary))
                .dsFont(.callout)
                .foregroundColor(accent.fieldText)
                .tint(accent.fieldGlyph)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dsGlyph(DS.Glyph.md, weight: .regular)
                        .foregroundColor(accent.fieldSecondary)
                        .dsTapArea(width: DS.Glyph.md, height: DS.Glyph.md)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("مسح البحث", "Clear search"))
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(minHeight: DS.Icon.tapTarget)
        .modifier(OccasionFieldChrome(raised: false))
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.md)
    }

    private func row(_ r: OccasionPickRow, order: Int) -> some View {
        let on = flashID.map { $0 == r.id } ?? (r.id == selectedID)
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        let glyph: String = {
            switch r.kind {
            case .custom: return "pencil"
            case .none: return "minus"
            case .option: return icon
            }
        }()
        return Button {
            guard flashID == nil else { return }
            OccasionHaptic.select()
            withAnimation(OccasionUI.fade) { flashID = r.id }
            DispatchQueue.main.asyncAfter(deadline: .now() + OccasionUI.pickDelay) {
                onPick(r.id)
                dismiss()
            }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: glyph)
                    .dsGlyph(DS.Glyph.xs)
                    .foregroundColor(on ? accent.onFill : accent.fieldGlyph)
                    .frame(width: OccasionUI.rowIcon, height: OccasionUI.rowIcon)
                    .background(Circle().fill((on ? accent.onFill : accent.fieldGlyph).opacity(OccasionUI.iconDiscOpacity)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(r.title)
                        .dsFont(longText ? .footnote : OccasionUI.rowTitle)
                        .foregroundColor(on ? accent.onFill : (r.kind == .custom ? accent.fieldGlyph : accent.rowText))
                        .lineSpacing(longText ? DS.Spacing.xxs : 0)
                        .fixedSize(horizontal: false, vertical: true)
                    if let s = r.subtitle {
                        Text(s)
                            .dsFont(.caption)
                            .foregroundColor(on ? accent.onFill : accent.rowSecondary)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                if on && r.kind != .custom {
                    Image(systemName: "checkmark.circle.fill")
                        .dsGlyph(DS.Glyph.lg)
                        .foregroundColor(accent.onFill)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm + DS.Spacing.xxs)
            .frame(maxWidth: .infinity, minHeight: OccasionUI.rowHeight, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(accent.row)
                    shape.fill(accent.fill).opacity(on ? 1 : 0)
                }
            }
            .overlay {
                if r.kind == .custom && !on {
                    shape.strokeBorder(accent.fieldGlyph.opacity(OccasionUI.dashedOpacity),
                                       style: StrokeStyle(lineWidth: DS.Border.widthBold, dash: OccasionUI.dash))
                } else {
                    shape.strokeBorder(accent.line.opacity(on ? 0 : (accent.isDark ? OccasionUI.lineOpacityDark : OccasionUI.lineOpacity)),
                                       lineWidth: DS.Border.width)
                }
            }
            .shadow(color: accent.fill.opacity(on ? OccasionUI.thumbShadow : OccasionUI.shadowOpacity),
                    radius: OccasionUI.shadowRadius, y: OccasionUI.shadowY)
            .contentShape(shape)
        }
        .buttonStyle(OccasionRowPressStyle())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : OccasionUI.rowEnterOffset)
        .animation(reduceMotion ? nil : OccasionUI.rowEnter.delay(Double(min(order, OccasionUI.staggerCap)) * OccasionUI.stagger),
                   value: appeared)
        .accessibilityAddTraits(r.id == selectedID ? [.isButton, .isSelected] : .isButton)
    }
}

/// ضغط صف القائمة: يصغر شوي ويصبغ. «تقليل الحركة»: يصبغ بس
private struct OccasionRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OccasionRowPressLabel(configuration: configuration)
    }
}

private struct OccasionRowPressLabel: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.occasionAccent) private var accent

    var body: some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill((accent.isDark ? Color.white : accent.ink).opacity(configuration.isPressed ? OccasionUI.pressDarken : 0))
                    .allowsHitTesting(false)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? OccasionUI.pressScaleRow : 1)
            .animation(reduceMotion ? nil : OccasionUI.press, value: configuration.isPressed)
    }
}

/// زوايا الورقة وخلفيتها (iOS 16.4+)
private struct OccasionSheetCorner: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationCornerRadius(DS.Radius.xxl)
        } else {
            content
        }
    }
}

// MARK: اقتراحات سريعة (من الشجرة: الأسماء، الأبناء، الإخوان، الديوانيات) — شرائح بارزة بعلامة +

struct OccasionSuggestionChip: View {
    let title: String
    let isOn: Bool
    var enabled = true
    let action: () -> Void

    @Environment(\.occasionAccent) private var accent

    var body: some View {
        let shape = Capsule()
        Button {
            OccasionHaptic.select()
            action()
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "plus.circle.fill")
                    .dsGlyph(DS.Glyph.sm)
                    .foregroundColor(isOn ? accent.onFill : accent.fieldGlyph)
                    .accessibilityHidden(true)
                Text(title)
                    .dsFont(OccasionUI.chipFont)
                    .foregroundColor(isOn ? accent.onFill : accent.fieldText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, DS.Spacing.sm)
            .padding(.trailing, OccasionUI.chipPadH)
            .padding(.vertical, OccasionUI.chipPadV)
            .frame(minHeight: OccasionUI.chipHeight)
            .background {
                ZStack {
                    shape.fill(accent.fieldBase)
                    shape.fill(accent.fieldTint)
                    shape.fill(accent.fill).opacity(isOn ? 1 : 0)
                }
            }
            .overlay(shape.strokeBorder(accent.line.opacity(isOn ? 0 : (accent.isDark ? OccasionUI.lineOpacityDark : OccasionUI.lineOpacity)),
                                        lineWidth: DS.Border.width))
            .shadow(color: accent.fill.opacity(isOn ? OccasionUI.thumbShadow : OccasionUI.shadowOpacity),
                    radius: OccasionUI.shadowRadius, y: OccasionUI.shadowY)
            .animation(OccasionUI.fade, value: isOn)
            .contentShape(shape)
            .dsTapArea(width: OccasionUI.chipHeight, height: OccasionUI.chipHeight)
        }
        .buttonStyle(OccasionPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : DSActionFill.disabledOpacity)
        .accessibilityLabel(title)
        .accessibilityHint(isOn ? L10n.t("اضغط للإزالة", "Tap to remove") : L10n.t("اضغط للإضافة", "Tap to add"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// حقلان بسطر واحد إذا وسعهم السطر، وإلا فوق بعض (اليوم + الوقت في التشييع)
struct OccasionFieldPair<A: View, B: View>: View {
    @ViewBuilder var first: () -> A
    @ViewBuilder var second: () -> B

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                first()
                second()
            }
            VStack(alignment: .leading, spacing: OccasionUI.cardSpacing) {
                first()
                second()
            }
        }
    }
}
