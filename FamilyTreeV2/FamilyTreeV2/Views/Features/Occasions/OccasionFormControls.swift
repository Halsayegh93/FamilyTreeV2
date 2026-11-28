import SwiftUI

// MARK: - عناصر نموذج «منشورات المناسبات»: اختيارات (شرائح وقوائم منسدلة) بدل الكتابة

/// صفوف تلتف تلقائياً (للشرائح). الاتجاه يتبع لغة التطبيق تلقائياً.
struct OccasionFlowLayout: Layout {
    var spacing: CGFloat = 8

    /// لو العنصر أعرض من السطر، يلتف داخلياً بعرض السطر
    private func size(of subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let natural = subview.sizeThatFits(.unspecified)
        if natural.width > maxWidth && maxWidth.isFinite {
            return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
        }
        return natural
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let s = size(of: subview, maxWidth: maxWidth)
            if x + s.width > maxWidth && x > 0 {
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += s.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, s.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let s = size(of: subview, maxWidth: bounds.width)
            if x + s.width > bounds.maxX && x > bounds.minX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: s.width, height: s.height))
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
    }
}

/// مربعات الاختيار في «منشورات المناسبات» (القالب، النموذج، مكان النشر) — عائلة واحدة (طلب المالك ٢٠٢٦-١٠-١٧):
/// أرضية بيضاء بحدّ شعري وزوايا md، والمختار حدّ ذهبي وأرضية ذهبية خفيفة (OccasionTile في الهوية)
struct OccasionTileStyle: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(isOn ? DS.Color.accentLight.opacity(0.12) : DS.Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(isOn ? DS.Color.accentLight : DS.Color.cardBorder, lineWidth: isOn ? 2 : 1)
            )
    }
}

extension View {
    func occasionTile(isOn: Bool) -> some View { modifier(OccasionTileStyle(isOn: isOn)) }
}

/// مربع اختيار بقرص رمز فوق والعنوان تحته (وسطر صغير اختياري) — القالب والنموذج بنفس الشكل
struct OccasionOptionTile: View {
    let title: String
    var subtitle: String? = nil
    /// SF Symbol داخل القرص
    let icon: String
    /// القرص: أرضيته وحلقته ولون الرمز
    let disc: (fill: Color, ring: Color, symbol: Color)
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Spacing.xs) {
                ZStack {
                    Circle().fill(disc.fill)
                    Circle().strokeBorder(disc.ring, lineWidth: 1.5)
                    Image(systemName: icon)
                        .dsGlyph(DS.Glyph.lg, weight: .semibold)
                        .foregroundColor(disc.symbol)
                }
                .frame(width: DS.Icon.rowLarge, height: DS.Icon.rowLarge)
                .accessibilityHidden(true)
                Text(title)
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 88)
            .occasionTile(isOn: isOn)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// شريحة اختيار واحدة
struct OccasionChip: View {
    let title: String
    /// رمز SF Symbols قبل النص (مثل القلم في «نص آخر») — بدل الإيموجي
    var systemImage: String? = nil
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xsm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .dsGlyph(DS.Glyph.sm, weight: .semibold)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
                .dsFont(.rowTitle)
                .foregroundColor(isOn ? DS.Color.textOnPrimary : DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .fill(isOn ? AnyShapeStyle(DS.Color.primaryFill) : AnyShapeStyle(DS.Color.cardBackgroundSoft))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .stroke(isOn ? Color.clear : DS.Color.cardBorderStrong, lineWidth: 1)
                )
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// خيار «✏️ نص آخر» مع حقل الكتابة
struct OccasionCustomOption {
    var text: Binding<String>
    var placeholder: String = ""
    var label: String? = nil
    var multiline: Bool = false
}

/// صف اختيارات: كل شريحة قيمة جاهزة؛ «بدون» (اختياري) = رقم بعد آخر عنصر؛ «نص آخر» = ‎-1 ويظهر حقل كتابة.
struct OccasionChips: View {
    let options: [String]
    let selected: Int
    let onSelect: (Int) -> Void
    var noneLabel: String? = nil
    var custom: OccasionCustomOption? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            OccasionFlowLayout(spacing: DS.Spacing.sm) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                    OccasionChip(title: option, isOn: selected == i) { onSelect(i) }
                }
                if let noneLabel {
                    OccasionChip(title: noneLabel, isOn: selected == options.count) { onSelect(options.count) }
                }
                if let custom {
                    OccasionChip(title: custom.label ?? L10n.t("نص آخر", "Other"), systemImage: "pencil", isOn: selected == -1) { onSelect(-1) }
                }
            }
            if let custom, selected == -1 {
                OccasionTextInput(text: custom.text, placeholder: custom.placeholder, multiline: custom.multiline)
            }
        }
    }
}

/// قائمة منسدلة بنفس منطق OccasionChips: الحقل يبين الاختيار الحالي (بشكل قائمة الحسينيات)، والقائمة فيها الاختيارات
/// و«بدون» (اختياري، رقم بعد آخر عنصر) و«نص آخر» (‎-1) اللي يظهر حقل كتابة تحت — للقوائم الطويلة (الصفة، أيام العزاء ووقته)
struct OccasionMenuField: View {
    let options: [String]
    let selected: Int
    let onSelect: (Int) -> Void
    /// رمز SF Symbols في بداية الحقل
    var icon: String? = nil
    var noneLabel: String? = nil
    var custom: OccasionCustomOption? = nil
    /// عنوان القائمة للقارئ الصوتي
    var accessibilityTitle: String = ""

    private var currentTitle: String {
        if selected == -1 { return custom?.label ?? L10n.t("نص آخر", "Other") }
        if options.indices.contains(selected) { return options[selected] }
        return noneLabel ?? options.first ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                    menuItem(option, isOn: selected == i) { onSelect(i) }
                }
                if let noneLabel {
                    menuItem(noneLabel, isOn: selected == options.count) { onSelect(options.count) }
                }
                if let custom {
                    Divider()
                    Button {
                        onSelect(-1)
                    } label: {
                        Label(custom.label ?? L10n.t("نص آخر", "Other"), systemImage: selected == -1 ? "checkmark" : "pencil")
                    }
                }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    if let icon {
                        Image(systemName: icon)
                            .font(DS.Font.icon(15, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    Text(currentTitle)
                        .dsFont(.rowTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(DS.Font.icon(12, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                        .accessibilityHidden(true)
                }
                .foregroundColor(DS.Color.textPrimary)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.smd)
                .frame(minHeight: DS.Icon.tapTarget)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Color.primary, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .accessibilityLabel(accessibilityTitle.isEmpty ? currentTitle : "\(accessibilityTitle): \(currentTitle)")
            if let custom, selected == -1 {
                OccasionTextInput(text: custom.text, placeholder: custom.placeholder, multiline: custom.multiline)
            }
        }
    }

    @ViewBuilder
    private func menuItem(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isOn {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

/// بطاقات نص طويل (الدعاء) — نفس منطق OccasionChips بعرض كامل
struct OccasionTextCards: View {
    let options: [String]
    let selected: Int
    let onSelect: (Int) -> Void
    var noneLabel: String? = nil
    var custom: OccasionCustomOption? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                let isOn = selected == i
                Button { onSelect(i) } label: {
                    Text(option)
                        .dsFont(.fieldValue)
                        .foregroundColor(DS.Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.smd)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .fill(isOn ? DS.Color.primary.opacity(0.10) : DS.Color.cardBackgroundSoft)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .stroke(isOn ? DS.Color.primary : DS.Color.cardBorderStrong, lineWidth: isOn ? 1.5 : 1)
                        )
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
            OccasionFlowLayout(spacing: DS.Spacing.sm) {
                if let noneLabel {
                    OccasionChip(title: noneLabel, isOn: selected == options.count) { onSelect(options.count) }
                }
                if custom != nil {
                    OccasionChip(title: L10n.t("نص آخر", "Other"), systemImage: "pencil", isOn: selected == -1) { onSelect(-1) }
                }
            }
            if let custom, selected == -1 {
                OccasionTextInput(text: custom.text, placeholder: custom.placeholder, multiline: true)
            }
        }
    }
}

/// حقل كتابة بشكل موحّد
struct OccasionTextInput: View {
    let text: Binding<String>
    var placeholder: String = ""
    var multiline: Bool = false

    var body: some View {
        TextField(placeholder, text: text, axis: .vertical)
            .lineLimit(multiline ? 2...5 : 1...3)
            .font(DS.Font.body)
            .foregroundColor(DS.Color.textPrimary)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.smd)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Color.cardBackgroundSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.cardBorderStrong, lineWidth: 1)
            )
    }
}

/// اقتراحات سريعة تعبّي الحقل + الحقل نفسه للتعديل
struct OccasionQuickText: View {
    let text: Binding<String>
    var suggestions: [String] = []
    var placeholder: String = ""

    var body: some View {
        let unique = suggestions.reduce(into: [String]()) { acc, s in
            if !s.isEmpty && !acc.contains(s) { acc.append(s) }
        }
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if !unique.isEmpty {
                OccasionFlowLayout(spacing: DS.Spacing.sm) {
                    ForEach(unique, id: \.self) { s in
                        OccasionChip(title: s, isOn: text.wrappedValue == s) {
                            text.wrappedValue = text.wrappedValue == s ? "" : s
                        }
                    }
                }
            }
            OccasionTextInput(text: text, placeholder: placeholder)
        }
    }
}

/// المنطقة: كتابة + اختيار من قائمة مناطق الكويت حسب المحافظة
struct OccasionAreaField: View {
    let text: Binding<String>

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            OccasionTextInput(text: text, placeholder: L10n.t("اختر أو اكتب المنطقة", "Choose or type the area"))
            Menu {
                ForEach(OccasionChoices.areaGroups) { group in
                    Menu(group.name) {
                        ForEach(group.areas, id: \.self) { area in
                            Button(area) { text.wrappedValue = area }
                        }
                    }
                }
            } label: {
                Image(systemName: "mappin.and.ellipse")
                    .font(DS.Font.icon(17, weight: .semibold))
                    .foregroundColor(DS.Color.textOnPrimary)
                    .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                    .background(Circle().fill(DS.Color.primary))
            }
            .accessibilityLabel(L10n.t("اختيار المنطقة", "Choose area"))
        }
    }
}

/// الحسينيات (قائمة ثابتة حسب المحافظة): اختيار وحدة يعبّي المكان والمنطقة، و«حسينية أخرى» يبدأ الكتابة — نفس الموقع
struct OccasionHusseiniyaMenu: View {
    let place: String
    let onPick: (OccasionHusseiniya) -> Void
    let onOther: () -> Void

    var body: some View {
        let picked = OccasionChoices.husseiniya(named: place)
        Menu {
            ForEach(OccasionChoices.husseiniyaGroups) { group in
                Menu(group.governorate) {
                    ForEach(group.items, id: \.name) { h in
                        Button {
                            onPick(h)
                        } label: {
                            if picked == h {
                                Label("\(h.name) — \(h.area)", systemImage: "checkmark")
                            } else {
                                Text("\(h.name) — \(h.area)")
                            }
                        }
                    }
                }
            }
            Divider()
            Button {
                onOther()
            } label: {
                Label(L10n.t("حسينية أخرى", "Another husseiniya"), systemImage: "pencil")
            }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "building.columns")
                    .font(DS.Font.icon(15, weight: .semibold))
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(picked?.name ?? L10n.t("اختر حسينية من القائمة", "Choose a husseiniya from the list"))
                        .dsFont(.rowTitle)
                        .lineLimit(1)
                    if let picked {
                        Text(picked.area)
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(DS.Font.icon(12, weight: .semibold))
                    .foregroundColor(DS.Color.textTertiary)
            }
            .foregroundColor(DS.Color.textPrimary)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.smd)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(picked == nil ? DS.Color.cardBackgroundSoft : DS.Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(picked == nil ? DS.Color.cardBorderStrong : DS.Color.primary, lineWidth: 1)
            )
        }
        .accessibilityLabel(L10n.t("الحسينيات", "Husseiniyas"))
    }
}

/// تنبيه أحمر تحت الحقل المطلوب الفاضي
struct OccasionRequiredHint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .dsFont(.caption)
        .foregroundColor(DS.Color.error)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// «اسم الفقيد: رباعي» + شرائح الصيغ. اللي ما تدخل بسطر واحد عليها «أطول من السطر» وما تنختار؛
/// أقصر صيغة تنختار بأي وقت («الخط يصغر ليدخل»). الأطول اللي يدخل ينختار تلقائياً — نفس الموقع.
struct OccasionNameFormatPicker: View {
    let resolution: OccasionNameResolution
    let onSelect: (Int) -> Void

    private var note: String {
        let r = resolution
        if r.autoShortened && r.shrunk { return L10n.t("اختُصر وصغُر الخط ليدخل بسطر واحد", "Shortened and slightly smaller to fit one line") }
        if r.autoShortened { return L10n.t("اختُصر تلقائياً ليدخل بسطر واحد", "Shortened to fit one line") }
        if r.shrunk { return L10n.t("الخط أصغر قليلاً ليتّسع في سطر واحد", "Slightly smaller to fit one line") }
        return ""
    }

    var body: some View {
        let r = resolution
        let shortest = r.options.last?.count
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            (Text("\(r.element.title): \(r.option.label)").fontWeight(.medium).foregroundColor(DS.Color.textSecondary)
                + Text(note.isEmpty ? "" : "  · " + note).foregroundColor(DS.Color.textTertiary))
                .font(DS.Font.caption1)
            if r.options.count > 1 {
                OccasionFlowLayout(spacing: DS.Spacing.sm) {
                    ForEach(r.options, id: \.count) { o in
                        OccasionFormatChip(
                            title: "\(o.label) — \(o.name)",
                            warning: o.fits ? "" : ((o.count == shortest || o.usable)
                                ? L10n.t("الخط يصغر ليدخل", "Smaller type to fit")
                                : L10n.t("أطول من السطر", "Too long for one line")),
                            isOn: o.count == r.option.count,
                            // اختيار المستخدم يُنفّذ إذا يدخل بسطر واحد ولو بخط أصغر (≥ ٦٠٪)
                            enabled: o.fits || o.usable || o.count == shortest
                        ) {
                            onSelect(o.count)
                        }
                    }
                }
            }
        }
    }
}

/// شريحة صيغة الاسم: الصيغة + الاسم، وتحتها تنبيه («أطول من السطر») — اللي ما تدخل ما تنختار
struct OccasionFormatChip: View {
    let title: String
    let warning: String
    let isOn: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.rowTitle)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !warning.isEmpty {
                    Text(warning)
                        .dsFont(.micro)
                        .foregroundColor(isOn ? DS.Color.textOnPrimary.opacity(0.85) : DS.Color.warning)
                }
            }
            .foregroundColor(isOn ? DS.Color.textOnPrimary : DS.Color.textPrimary)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    // النص أبيض فوق المختار ← primaryFill (قاعدة الهوية؛ primary يفتح في الداكن)
                    .fill(isOn ? AnyShapeStyle(DS.Color.primaryFill) : AnyShapeStyle(DS.Color.cardBackgroundSoft))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(isOn ? Color.clear : DS.Color.cardBorderStrong, lineWidth: DS.Border.width)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : DS.Opacity.disabled)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// بطاقة قسم في النموذج: عنوان + تلميح + مفتاح «إظهار» (اختياري)
struct OccasionFormCard<Content: View>: View {
    let title: String
    var hint: String? = nil
    var toggle: Binding<Bool>? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        // قسم المربّعات الموحّد (`DSComposerSection`، طلب المالك ٢٠٢٦-١١-١١): العنوان الموحّد، والتلميح سطراً تحته،
        // و«إظهار» = «ظاهر في البطاقة / مخفي» بالاختيار الموحّد بدل المفتاح — نفس القيمة المحفوظة
        DSComposerSection(title: title, icon: "square.text.square", index: 0) {
            if let hint {
                Text(hint)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let toggle {
                DSVisibilityPicker(hidden: Binding(get: { !toggle.wrappedValue }, set: { toggle.wrappedValue = !$0 }),
                                   shownLine: L10n.t("يظهر هذا القسم في البطاقة.", "This section is shown on the card."),
                                   hiddenLine: L10n.t("لا يظهر هذا القسم في البطاقة.", "This section is hidden from the card."),
                                   rowTitle: L10n.t("الظهور في البطاقة", "Shown on the card"),
                                   shownState: L10n.t("يظهر في البطاقة", "Shown on the card"),
                                   hiddenState: L10n.t("مخفي عن البطاقة", "Hidden from the card"))
            }
            if toggle?.wrappedValue ?? true {
                content()
            }
        }
    }
}

/// عنوان صغير داخل البطاقة
struct OccasionFieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        // عنوان الحقل الموحّد (`label` / `fieldLabel`)
        Text(text)
            .dsFieldFont(.label)
            .foregroundColor(DS.Color.fieldLabel)
    }
}

// MARK: - اختيار عضو من شجرة العائلة

struct OccasionMemberAvatar: View {
    let member: FamilyMember
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let raw = member.avatarUrl, !raw.isEmpty, let url = URL(string: raw) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(DS.Color.cardBorder, lineWidth: 1))
    }

    private var initials: some View {
        ZStack {
            DS.Color.cardBackgroundSoft
            Text(String(OccasionFamilyIndex.firstName(member).prefix(1)))
                .font(DS.Font.scaled(size * 0.4, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)
        }
    }
}

