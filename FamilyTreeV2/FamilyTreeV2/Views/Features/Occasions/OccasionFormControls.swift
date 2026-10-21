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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(disc.symbol)
                }
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
                Text(title)
                    .font(DS.Font.plex(13, weight: .semibold))
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Font.plex(11))
                        .foregroundColor(DS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
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
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
            }
                .font(DS.Font.plex(14, weight: .semibold))
                .foregroundColor(isOn ? DS.Color.textOnPrimary : DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isOn ? AnyShapeStyle(DS.Color.primaryFill) : AnyShapeStyle(DS.Color.cardBackgroundSoft))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
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
            OccasionFlowLayout(spacing: 8) {
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
                        .font(DS.Font.plex(14, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(DS.Font.icon(12, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                        .accessibilityHidden(true)
                }
                .foregroundColor(DS.Color.textPrimary)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm + 2)
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
                        .font(DS.Font.plex(15))
                        .foregroundColor(DS.Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm + 2)
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
            OccasionFlowLayout(spacing: 8) {
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
            .padding(.vertical, DS.Spacing.sm + 2)
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
                OccasionFlowLayout(spacing: 8) {
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
                    .frame(width: 44, height: 44)
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(picked?.name ?? L10n.t("اختر حسينية من القائمة", "Choose a husseiniya from the list"))
                        .font(DS.Font.plex(14, weight: .semibold))
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
            .padding(.vertical, DS.Spacing.sm + 2)
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
        .font(DS.Font.caption1.weight(.semibold))
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
        if r.shrunk { return L10n.t("الخط أصغر شوي ليدخل بسطر واحد", "Slightly smaller to fit one line") }
        return ""
    }

    var body: some View {
        let r = resolution
        let shortest = r.options.last?.count
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            (Text("\(r.element.title): \(r.option.label)").fontWeight(.semibold).foregroundColor(DS.Color.textSecondary)
                + Text(note.isEmpty ? "" : "  · " + note).foregroundColor(DS.Color.textTertiary))
                .font(DS.Font.caption1)
            if r.options.count > 1 {
                OccasionFlowLayout(spacing: 8) {
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
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.plex(14, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !warning.isEmpty {
                    Text(warning)
                        .font(DS.Font.plex(11, weight: .semibold))
                        .foregroundColor(isOn ? DS.Color.textOnPrimary.opacity(0.85) : DS.Color.warning)
                }
            }
            .foregroundColor(isOn ? DS.Color.textOnPrimary : DS.Color.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    // النص أبيض فوق المختار ← primaryFill (قاعدة الهوية؛ primary يفتح في الداكن)
                    .fill(isOn ? AnyShapeStyle(DS.Color.primaryFill) : AnyShapeStyle(DS.Color.cardBackgroundSoft))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isOn ? Color.clear : DS.Color.cardBorderStrong, lineWidth: 1)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
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
        DSCard(padding: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                    Text(title)
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textPrimary)
                    if let hint {
                        Text(hint)
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textTertiary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if let toggle {
                        Toggle(L10n.t("إظهار", "Show"), isOn: toggle)
                            .labelsHidden()
                            .tint(DS.Color.primary)
                            .accessibilityLabel(L10n.t("إظهار \(title)", "Show \(title)"))
                    }
                }
                if toggle?.wrappedValue ?? true {
                    content()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// عنوان صغير داخل البطاقة
struct OccasionFieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(DS.Font.caption1)
            .fontWeight(.semibold)
            .foregroundColor(DS.Color.textSecondary)
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

struct OccasionMemberPickerSheet: View {
    let family: OccasionFamilyIndex
    let preferDeceased: Bool
    let onPick: (FamilyMember) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            let results = family.search(query, preferDeceased: preferDeceased)
            List {
                ForEach(results) { m in
                    Button {
                        onPick(m)
                        dismiss()
                    } label: {
                        HStack(spacing: DS.Spacing.md) {
                            OccasionMemberAvatar(member: m)
                            Text(m.nameWordsWithFamily.joined(separator: " "))
                                .font(DS.Font.callout)
                                .foregroundColor(DS.Color.textPrimary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if m.isDeceased == true {
                                Text(L10n.t("متوفى", "Deceased"))
                                    .font(DS.Font.caption2)
                                    .foregroundColor(DS.Color.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(DS.Color.cardBackgroundSoft))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .overlay {
                if results.isEmpty {
                    Text(query.trimmingCharacters(in: .whitespaces).isEmpty
                         ? L10n.t("اكتب الاسم للبحث في شجرة العائلة", "Type a name to search the family tree")
                         : L10n.t("ما لقينا أحد بهالاسم — تقدر تكتبه بنفسك.", "No match — you can type the name yourself."))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(DS.Spacing.xxl)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: L10n.t("ابحث بالاسم", "Search by name"))
            .navigationTitle(L10n.t("اختيار من الشجرة", "Pick from the tree"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: DSToolbar.cancelPlacement) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                }
            }
        }
    }
}
