import SwiftUI

// MARK: - عناصر نموذج «بوستات المناسبات»: اختيارات (شرائح) بدل الكتابة

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

/// شريحة اختيار واحدة
struct OccasionChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.plex(14, weight: .semibold))
                .foregroundColor(isOn ? DS.Color.textOnPrimary : DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isOn ? AnyShapeStyle(DS.Color.primary) : AnyShapeStyle(DS.Color.cardBackgroundSoft))
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
                    OccasionChip(title: "✏️ " + (custom.label ?? L10n.t("نص آخر", "Other")), isOn: selected == -1) { onSelect(-1) }
                }
            }
            if let custom, selected == -1 {
                OccasionTextInput(text: custom.text, placeholder: custom.placeholder, multiline: custom.multiline)
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
                    OccasionChip(title: "✏️ " + L10n.t("نص آخر", "Other"), isOn: selected == -1) { onSelect(-1) }
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
                    .font(DS.Font.scaled(17, weight: .semibold))
                    .foregroundColor(DS.Color.textOnPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(DS.Color.primary))
            }
            .accessibilityLabel(L10n.t("اختيار المنطقة", "Choose area"))
        }
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
