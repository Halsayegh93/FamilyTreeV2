import SwiftUI

// MARK: - عناصر نموذج «بوستات المناسبات»: مبدّلات وقوائم منسدلة بدل الكتابة (OccasionPickers.swift)

/// صفوف تلتف تلقائياً (لشرائح الاقتراحات). الاتجاه يتبع لغة التطبيق تلقائياً.
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

// MARK: - مقاسات النموذج المدمج وتفاعله (طلب المالك ٢٠٢٦-١٠-١٢: «نبي شوي تبسيط الأزرار، صايرة هيوج»،
// «نبي الأزرار شوي تفاعلية»، «تصميم الزر مو تفاعلي» ← «قائمة منسدلة للطويل»، «خل القوائم بتصميم تفاعلي و ملون»)
// — مكان واحد لكل أرقام عناصر هذي الشاشة

enum OccasionUI {
    /// ارتفاع الشريحة المرئي — ومساحة الضغط ٤٤ بلا تكبير التخطيط (dsTapArea)
    static let chipHeight: CGFloat = DSBox.chipHeight
    static let chipPadH: CGFloat = DSBox.chipPadding
    /// حشوة فوق وتحت (تبين لما تلتف الشريحة على سطرين)
    static let chipPadV: CGFloat = DS.Spacing.xsm
    static let chipSpacing: CGFloat = DS.Spacing.xsm
    static let chipFont = DS.TextRole.chipCompact
    /// المبدّل: ارتفاع الزر وحشوة الإطار وأصغر تصغير للنص
    static let segmentHeight: CGFloat = DSBox.segmentHeightRegular
    static let segmentInset: CGFloat = DSBox.segmentPaddingSmall
    static let segmentMinScale: CGFloat = 0.8
    /// الأزرار الصغيرة (اختر من الشجرة، اختيار صورة، إضافة سطر)
    static let buttonHeight: CGFloat = DS.Icon.rowLarge
    /// حقل الكتابة
    static let fieldHeight: CGFloat = DS.Icon.tapTarget
    /// الحقل المنسدل: قرص الأيقونة، خط القيمة، أقصى عدد سطور
    static let fieldIcon: CGFloat = DS.Icon.row
    static let fieldValue = DS.TextRole(.subheadline, weight: .semibold)
    static let fieldLines = 3
    /// بطاقة القسم
    static let cardTitle = DS.TextRole(.subheadline, weight: .bold)
    /// تلميح جانب العنوان
    static let hint = DS.TextRole(.caption2)
    static let cardPadding: CGFloat = DS.Spacing.sm + DS.Spacing.xxs
    static let cardSpacing: CGFloat = DS.Spacing.sm + DS.Spacing.xxs
    /// ألوان الحقل البارز: صبغة الخلفية، الإطار، الظل، وتغميق الضغط
    static let fieldTintOpacity: Double = DS.Opacity.tintFillSoft
    static let sheetTintOpacity: Double = 0.05
    static let lineOpacity: Double = DS.Opacity.selectedStroke
    static let lineOpacityDark: Double = DS.Opacity.tintStroke
    static let shadowOpacity: Double = 0.14
    static let shadowPressed: Double = 0.06
    static let thumbShadow: Double = 0.35
    static let shadowRadius: CGFloat = 4
    static let shadowRadiusPressed: CGFloat = 1
    static let shadowY: CGFloat = 2
    static let shadowYPressed: CGFloat = 0.5
    static let pressDarken: Double = 0.1
    static let iconDiscOpacity: Double = DS.Opacity.tintFill
    /// الضغط: تصغير خفيف بنابض سريع بلا ارتداد؛ البطاقات العريضة أقل
    static let pressScale: CGFloat = 0.96
    static let pressScaleWide: CGFloat = 0.985
    static let pressScaleRow: CGFloat = 0.98
    static let pressOpacity: Double = 0.88
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.9)
    /// انتقال المختار (المبدّل) وتلاشي الألوان
    static let slide = Animation.spring(response: 0.3, dampingFraction: 0.9)
    static let fade = Animation.easeInOut(duration: 0.18)
    /// القائمة المفتوحة: الرأس، الصفوف، الدخول المتتابع، ومهلة التمييز قبل الإغلاق
    static let headerIcon: CGFloat = DS.Icon.rowLarge + DS.Spacing.xs
    static let headerClose: CGFloat = DS.Icon.row
    static let headerDiscOpacity: Double = DS.Opacity.tintFillStrong
    static let rowIcon: CGFloat = DS.Glyph.xxl + DS.Spacing.xs
    static let rowTitle = DS.TextRole(.subheadline, weight: .semibold)
    static let rowHeight: CGFloat = DS.Icon.tapTarget + DS.Spacing.xs
    static let rowSpacing: CGFloat = DS.Spacing.sm
    static let dash: [CGFloat] = [5, 4]
    static let dashedOpacity: Double = 0.7
    static let rowEnterOffset: CGFloat = 10
    static let rowEnter = Animation.spring(response: 0.34, dampingFraction: 0.88)
    static let stagger: Double = 0.03
    static let staggerCap = 10
    static let pickDelay: Double = 0.16
    /// تقدير ارتفاع الورقة القصيرة (الرأس + الحشوات، والصف) — أكبر من هذا ← نصف الشاشة / كاملة
    static let sheetChromeEstimate: CGFloat = 120
    static let sheetRowEstimate: CGFloat = 54
    static let sheetRowEstimateLong: CGFloat = 92
    static let sheetMaxFitHeight: CGFloat = 520
}

/// اهتزاز خفيف عند الاختيار
enum OccasionHaptic {
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}

/// الضغط: يصغر شوي ويرجع بنابض سريع. «تقليل الحركة»: بدون تصغير، بس يخفت
struct OccasionPressStyle: ButtonStyle {
    var scale: CGFloat = OccasionUI.pressScale

    func makeBody(configuration: Configuration) -> some View {
        OccasionPressLabel(configuration: configuration, scale: scale)
    }
}

private struct OccasionPressLabel: View {
    let configuration: ButtonStyleConfiguration
    let scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? OccasionUI.pressOpacity : 1)
            .animation(reduceMotion ? nil : OccasionUI.press, value: configuration.isPressed)
    }
}

/// زر صغير (اختر من الشجرة، اختيار صورة، إضافة سطر): ممتلئ بلون النوع أو خفيف بإطار
struct OccasionButtonLabel: View {
    let title: String
    var icon: String? = nil
    var filled: Bool = true
    @Environment(\.occasionAccent) private var accent

    var body: some View {
        HStack(spacing: DS.Spacing.xsm) {
            if let icon {
                Image(systemName: icon)
                    .dsGlyph(DS.Glyph.sm)
                    .accessibilityHidden(true)
            }
            Text(title)
                .dsFont(.chip)
                .lineLimit(1)
        }
        .foregroundColor(filled ? accent.onFill : accent.ink)
        .padding(.horizontal, DS.Spacing.lg)
        .frame(minHeight: OccasionUI.buttonHeight)
        .background {
            if filled {
                Capsule().fill(accent.fill)
                    .shadow(color: accent.fill.opacity(OccasionUI.thumbShadow), radius: OccasionUI.shadowRadius, y: OccasionUI.shadowY)
            } else {
                Capsule().fill(accent.ink.opacity(DS.Opacity.tintFill))
                Capsule().strokeBorder(accent.ink.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width)
            }
        }
        .contentShape(Capsule())
        .dsTapArea(width: OccasionUI.buttonHeight, height: OccasionUI.buttonHeight)
    }
}

/// صيغة اسم: مبدّل متصل بسطر واحد («سداسي · خماسي · رباعي · ثلاثي»). كل صيغة تدخل بسطر واحد ولو بخط
/// أصغر (٦٠٪ فأكثر) تنختار وتنفّذ كما هي؛ اللي ما تدخل حتى بالأصغر باهتة، والأقصر تنختار بأي وقت. فوقه سطر صغير بالصيغة المختارة والاسم بها.
struct OccasionNameFormatPicker: View {
    let resolution: OccasionNameResolution
    let onSelect: (Int) -> Void
    @Environment(\.occasionAccent) private var accent

    var body: some View {
        let r = resolution
        let last = r.options.last?.count
        let faded = r.options.contains { !$0.usable && $0.count != last }
        let lastShrinks = r.options.contains { !$0.fits && ($0.usable || $0.count == last) }
        VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Image(systemName: "text.alignright")
                    .dsGlyph(DS.Glyph.xs)
                    .foregroundColor(accent.ink)
                    .accessibilityHidden(true)
                Text(verbatim: "\(r.element.title): \(r.option.label)")
                    .dsFont(.chipCompact)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize()
                    .layoutPriority(1)
                Text(verbatim: "— " + r.option.name)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if r.autoShortened || r.shrunk {
                    Text(r.autoShortened && r.shrunk ? L10n.t("· اختُصر وصغُر", "· shortened, smaller")
                         : r.autoShortened ? L10n.t("· اختُصر تلقائياً", "· shortened")
                         : L10n.t("· الخط أصغر شوي", "· slightly smaller"))
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .dsFont(.footnote)
            .lineLimit(1)
            if r.options.count > 1 {
                OccasionSegmented(
                    options: r.options.map {
                        .init(id: $0.count, title: $0.label, enabled: $0.usable || $0.count == last,
                              accessibilityText: "\($0.label): \($0.name)")
                    },
                    selection: Binding(get: { r.option.count }, set: { onSelect($0) })
                )
                if faded || lastShrinks {
                    Text([faded ? L10n.t("الباهتة أطول من السطر", "Faded ones are longer than the line") : nil,
                          lastShrinks ? L10n.t("الطويلة يصغر خطها لتدخل", "Longer ones use smaller text to fit") : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
    }
}

/// تلميح «مطلوب» تحت الحقل الفاضي
struct OccasionRequiredHint: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .dsFont(.caption)
            .foregroundColor(DS.Color.error)
    }
}

/// خيار «✏️ نص آخر» مع حقل الكتابة
struct OccasionCustomOption {
    var text: Binding<String>
    var placeholder: String = ""
    var label: String? = nil
    var multiline: Bool = false
}

/// حقل كتابة بشكل موحّد: نفس صبغة الحقول وإطارها (بدون ظل — للكتابة لا للضغط)
struct OccasionTextInput: View {
    let text: Binding<String>
    var placeholder: String = ""
    var multiline: Bool = false
    @Environment(\.occasionAccent) private var accent

    var body: some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(accent.fieldSecondary), axis: .vertical)
            .lineLimit(multiline ? 2...5 : 1...3)
            .dsFont(.callout)
            .foregroundColor(accent.fieldText)
            .tint(accent.fieldGlyph)
            .padding(.horizontal, OccasionUI.chipPadH)
            .padding(.vertical, DS.Spacing.sm)
            .frame(minHeight: OccasionUI.fieldHeight)
            .modifier(OccasionFieldChrome(raised: false))
    }
}

/// اقتراحات سريعة (شرائح بارزة بعلامة +) تعبّي الحقل + الحقل نفسه للتعديل.
/// accessory (اختياري) ينرسم بين الاقتراحات والحقل؛ تغيّر focusRequest يركّز على الحقل للكتابة.
struct OccasionQuickText: View {
    let text: Binding<String>
    var suggestions: [String] = []
    var placeholder: String = ""
    var accessory: AnyView? = nil
    var focusRequest: Int = 0

    @FocusState private var focused: Bool

    var body: some View {
        let unique = suggestions.reduce(into: [String]()) { acc, s in
            if !s.isEmpty && !acc.contains(s) { acc.append(s) }
        }
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if !unique.isEmpty {
                OccasionFlowLayout(spacing: OccasionUI.chipSpacing) {
                    ForEach(unique, id: \.self) { s in
                        OccasionSuggestionChip(title: s, isOn: text.wrappedValue == s) {
                            text.wrappedValue = text.wrappedValue == s ? "" : s
                        }
                    }
                }
            }
            if let accessory { accessory }
            OccasionTextInput(text: text, placeholder: placeholder)
                .focused($focused)
        }
        .onChange(of: focusRequest) { _ in
            DispatchQueue.main.async { focused = true }
        }
    }
}

/// «الحسينيات» في مكان العزاء: حقل منسدل يفتح القائمة الثابتة (بحث + حسب المحافظة).
/// الاختيار يعبّي المكان (والمنطقة تتعبّى من الـ VM)؛ «حسينية أخرى» (آخر القائمة) يعبّي «حسينية » للكتابة.
struct OccasionHusseiniyaPicker: View {
    let place: Binding<String>
    let onOther: () -> Void

    @State private var showSheet = false
    /// «حسينية أخرى» ينفّذ بعد ما تتسكّر الورقة — حتى يقدر الحقل ياخذ التركيز
    @State private var otherPending = false
    @Environment(\.occasionAccent) private var accent

    var body: some View {
        let picked = OccasionChoices.husseiniya(named: place.wrappedValue)
        VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            OccasionFieldLabel(L10n.t("الحسينيات", "Husseiniyas"))
            OccasionDropdownField(icon: "building.columns.fill", value: picked?.name, detail: picked?.area,
                                  placeholder: L10n.t("اختر حسينية من القائمة", "Pick a Husseiniya from the list"),
                                  accessibilityLabel: L10n.t("اختيار حسينية", "Choose a Husseiniya")) {
                showSheet = true
            }
        }
        .sheet(isPresented: $showSheet, onDismiss: {
            if otherPending {
                otherPending = false
                onOther()
            }
        }) {
            OccasionPickerSheet(
                title: L10n.t("الحسينيات", "Husseiniyas"),
                icon: "building.columns.fill",
                sections: OccasionChoices.husseiniyaGroups.map { g in
                    OccasionPickSection(id: g.name, title: g.name,
                                        rows: g.items.map { OccasionPickRow(id: $0.name, title: $0.name, subtitle: $0.area) })
                } + [OccasionPickSection(id: OccasionPick.customID, rows: [
                    OccasionPickRow(id: OccasionPick.customID, title: L10n.t("حسينية أخرى", "Another Husseiniya"), kind: .custom),
                ])],
                selectedID: picked?.name,
                searchable: true,
                searchPrompt: L10n.t("ابحث باسم الحسينية أو المنطقة", "Search by name or area"),
                emptyText: L10n.t("ما لقينا حسينية بهالاسم — اختر «حسينية أخرى» واكتبها.",
                                  "No match — choose “Another Husseiniya” and type it.")
            ) { id in
                if id == OccasionPick.customID {
                    otherPending = true
                } else {
                    place.wrappedValue = id
                }
            }
            .environment(\.occasionAccent, accent)
        }
    }
}

/// المنطقة: حقل منسدل بقائمة مناطق الكويت حسب المحافظة (بحث)؛ «منطقة أخرى» (آخر القائمة) يبيّن حقل كتابة.
/// المنطقة اللي تعبّت تلقائياً (من حسينية أو ديوانية) وما هي بالقائمة تبين مكتوبة في الحقل.
struct OccasionAreaField: View {
    let text: Binding<String>

    @State private var open = false
    @State private var typing = false
    @State private var focusAfterClose = false
    @FocusState private var focused: Bool
    @Environment(\.occasionAccent) private var accent

    private static func inList(_ v: String) -> Bool {
        OccasionChoices.kuwaitAreas.contains(v.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        let value = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let listed = Self.inList(value)
        let showInput = typing || (!value.isEmpty && !listed)
        let group = OccasionChoices.areaGroups.first { $0.areas.contains(value) }?.name
        VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            OccasionDropdownField(
                icon: "map.fill",
                value: value.isEmpty ? (showInput ? L10n.t("منطقة أخرى", "Other area") : nil) : value,
                detail: listed ? group : nil,
                placeholder: L10n.t("اختر المنطقة", "Choose the area"),
                isCustom: showInput,
                accessibilityLabel: L10n.t("المنطقة", "Area")
            ) { open = true }
            if showInput {
                OccasionTextInput(text: text, placeholder: L10n.t("اكتب المنطقة", "Type the area"))
                    .focused($focused)
            }
        }
        .onChange(of: text.wrappedValue) { v in
            // تعبئة تلقائية (حسينية/ديوانية) أو «بدء من جديد» وهو مو يكتب ← يرجع للقائمة
            if !focused && (v.isEmpty || Self.inList(v)) { typing = false }
        }
        .sheet(isPresented: $open, onDismiss: {
            guard focusAfterClose else { return }
            focusAfterClose = false
            focused = true
        }) {
            OccasionPickerSheet(
                title: L10n.t("المنطقة", "Area"),
                icon: "map.fill",
                sections: OccasionChoices.areaGroups.map { g in
                    OccasionPickSection(id: g.name, title: g.name, rows: g.areas.map { OccasionPickRow(id: $0, title: $0) })
                } + [OccasionPickSection(id: OccasionPick.customID, rows: [
                    OccasionPickRow(id: OccasionPick.customID, title: L10n.t("منطقة أخرى", "Other area"), kind: .custom),
                ])],
                selectedID: showInput ? OccasionPick.customID : (value.isEmpty ? nil : value),
                searchable: true,
                searchPrompt: L10n.t("ابحث باسم المنطقة", "Search by area"),
                emptyText: L10n.t("ما لقينا منطقة بهالاسم — اختر «منطقة أخرى» واكتبها.", "No match — choose “Other area” and type it.")
            ) { id in
                if id == OccasionPick.customID {
                    if Self.inList(text.wrappedValue) { text.wrappedValue = "" }
                    typing = true
                    focusAfterClose = true
                } else {
                    typing = false
                    text.wrappedValue = id
                }
            }
            .environment(\.occasionAccent, accent)
        }
    }
}

/// بطاقة قسم في النموذج (خفيفة): عنوان صغير + تلميح + مبدّل «إظهار / إخفاء» (اختياري)
struct OccasionFormCard<Content: View>: View {
    let title: String
    var hint: String? = nil
    var toggle: Binding<Bool>? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: OccasionUI.cardSpacing) {
            // مع المبدّل: بالوسط
            HStack(alignment: toggle == nil ? .firstTextBaseline : .center, spacing: DS.Spacing.xsm) {
                Text(title)
                    .dsFont(OccasionUI.cardTitle)
                    .foregroundColor(DS.Color.textPrimary)
                if let hint {
                    Text(hint)
                        .dsFont(OccasionUI.hint)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if let toggle {
                    OccasionSegmented(
                        options: [.init(id: true, title: L10n.t("إظهار", "Show"), accessibilityText: L10n.t("إظهار \(title)", "Show \(title)")),
                                  .init(id: false, title: L10n.t("إخفاء", "Hide"), accessibilityText: L10n.t("إخفاء \(title)", "Hide \(title)"))],
                        selection: toggle,
                        compact: true
                    )
                    .fixedSize()
                }
            }
            if toggle?.wrappedValue ?? true {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(padding: OccasionUI.cardPadding)
    }
}

/// عنوان صغير داخل البطاقة
struct OccasionFieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .dsFont(.caption)
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
