import SwiftUI

// MARK: - قطع مربّعي «خبر جديد» و«تعديل الخبر» المشتركة
//
// طلب المالك ٢٠٢٦-١٠-٠٧ «أسلوب واحد، والتعديل من مكان واحد»: كانت مربّعات نوع الخبر وصندوق الكتابة
// ومعاينة التصويت وأزرار خياراته منسوخة باليد في `AddNewsView` و`EditNewsView`. صارت هنا مرّة واحدة
// وعلى القطع الموحّدة (`DSOptionTiles`، `DSChipButton`، `DSAddChipLabel`، `DS.TextRole`، `DSBox`).

/// مربّعات نوع الخبر — `DSOptionTiles` الموحّدة، وفي كل خيار شارة النوع المتحرّكة
/// (اختيار النوع يشغّل حكايته فوراً — طلب المالك ٢٠٢٦-١٠-٠٥)
struct NewsTypeTiles: View {
    let types: [String]
    @Binding var selection: String
    /// التصويت مختار: لا نوع مختار، والمربّعات خافتة ولا تُضغط
    var disabled: Bool = false

    /// لون الخيار: الإعلان كحلي العلامة (معنى)، و«خبر» العادي بلون قسم الأخبار، والباقي بلون نوعه
    static func tint(for type: String) -> Color {
        let typeColor = NewsTypeHelper.color(for: type)
        if type == "إعلان" { return DS.Color.brand }
        return typeColor == DS.Color.brand ? AppSection.news.ink : typeColor
    }

    var body: some View {
        DSOptionTiles(
            types.map { DSOptionTile($0, title: NewsTypeHelper.displayName(for: $0),
                                     icon: NewsTypeHelper.icon(for: $0), tint: Self.tint(for: $0)) },
            selection: Binding(get: { disabled ? "" : selection }, set: { selection = $0 })
        ) { option, selected in
            NewsTypeTileIcon(type: option.id, tint: Self.tint(for: option.id), selected: selected)
        }
        .opacity(disabled ? DS.Opacity.disabled : 1)
        .allowsHitTesting(!disabled)
    }
}

/// قرص خيار نوع الخبر: شارة النوع (أو رمزه) على قرص بلونه — ممتلئ للمختار، خفيف لغيره
private struct NewsTypeTileIcon: View {
    let type: String
    let tint: Color
    let selected: Bool

    var body: some View {
        ZStack {
            Circle().fill(selected ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(DS.Opacity.tintFill)))
            if FTNewsBadges.hasArt(for: type, currentIcon: NewsTypeHelper.icon(for: type)) {
                FTNewsBadge(type: type, tint: tint, seed: abs(type.hashValue % 89),
                            style: selected ? .onColor : .soft, beatOnAppear: selected)
                    .id(selected)
            } else {
                Image(dsSymbol: NewsTypeHelper.icon(for: type))
                    .dsGlyph(DS.Glyph.lg)
                    // فوق لون النوع المتكيّف: أبيض أو حبر داكن حسب التباين (الهوية)
                    .foregroundColor(selected ? DS.Color.readableText(on: tint) : tint)
            }
        }
    }
}

/// صندوق كتابة نص الخبر (نفس صندوق الحقول: سطح هادئ، إطار يتلوّن عند الكتابة)
struct NewsContentEditor: View {
    @Binding var text: String
    let placeholder: String
    let tint: Color
    var focused: FocusState<Bool>.Binding

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .focused(focused)
                .frame(minHeight: DS.Icon.loaderArt, maxHeight: DS.Icon.loaderArt * 2)
                .scrollContentBackground(.hidden)
                .dsFieldFont(.body)
                .foregroundColor(DS.Color.textPrimary)
                .padding(.horizontal, DS.Spacing.xsm)
                .padding(.vertical, DS.Spacing.xs)
            if text.isEmpty {
                Text(placeholder)
                    .dsFieldFont(.body)
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, DS.Spacing.md)
                    .allowsHitTesting(false)
            }
        }
        .background(shape.fill(DS.Color.background))
        .overlay(shape.strokeBorder(focused.wrappedValue ? tint.opacity(DS.Opacity.selectedStroke)
                                                         : DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke),
                                    lineWidth: focused.wrappedValue ? DS.Border.widthBold : DS.Border.width))
        .trialCardSkin(radius: DS.Card.radius)
        .animation(DSMotion.fade, value: focused.wrappedValue)
    }
}

/// رقم الخيار في دائرة بلون التصويت
struct NewsPollNumber: View {
    let number: Int
    var size: CGFloat = DS.Icon.section

    var body: some View {
        Text("\(number)")
            .dsFont(.badge)
            .foregroundColor(DS.Color.textOnPrimary)
            .frame(width: size, height: size)
            .background(Circle().fill(DS.Color.newsVote))
    }
}

/// معاينة التصويت داخل محتوى الخبر — «تعديل» يفتح مربّعه و«إزالة التصويت» تحذفه
struct NewsPollPreview: View {
    let question: String
    let options: [String]
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let shape = RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
        let row = RoundedRectangle(cornerRadius: DS.Icon.discRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(q.isEmpty ? L10n.t("تصويت بدون سؤال", "Poll without a question") : q)
                .dsFont(.rowTitle)
                .foregroundColor(q.isEmpty ? DS.Color.textTertiary : DS.Color.textPrimary)
            ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
                HStack(spacing: DS.Spacing.sm) {
                    NewsPollNumber(number: idx + 1)
                    Text(option)
                        .dsFont(.callout)
                        .foregroundColor(DS.Color.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.Spacing.sm)
                .frame(minHeight: DSBox.chipHeight)   // يطول مع «حجم النص» بدل قصّ الخيار
                .background(
                    // شريط نسبة تجميلي (معاينة شكل التصويت)
                    GeometryReader { g in
                        row.fill(DS.Color.newsVote.opacity(DS.Opacity.tintFill))
                            .frame(width: g.size.width * CGFloat(0.35 + 0.15 * Double((idx * 7) % 4)))
                    }
                )
                .background(row.fill(DS.Color.background))
            }
            HStack {
                DSChipButton(L10n.t("تعديل", "Edit"), icon: "pencil", tint: DS.Color.newsVote, action: onEdit)
                Spacer()
                DSChipButton(L10n.t("إزالة التصويت", "Remove poll"), icon: "trash", tint: DS.Color.error, action: onRemove)
            }
        }
        .padding(DS.Card.padding)
        .background(shape.fill(DS.Color.newsVote.opacity(DS.Opacity.tintFillSoft)))
        .overlay(shape.strokeBorder(DS.Color.newsVote.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
    }
}

/// «خيار آخر» في مربّع التصويت — خانة إضافة بإطار متقطّع بارتفاع الزرّ الواحد
struct NewsPollAddOptionButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DSAddChipLabel(icon: "plus", title: L10n.t("خيار آخر", "Another option"),
                           tint: DS.Color.newsVote, fullWidth: true)
        }
        .buttonStyle(DSPressStyle())
    }
}

/// حذف خيار من مربّع التصويت — دائرة حمراء بمساحة ضغط ٤٤
struct NewsPollRemoveOptionButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .dsGlyph(DS.Glyph.xl, weight: .regular)
                .foregroundColor(DS.Color.error)
                .frame(width: DS.Icon.row, height: DS.Icon.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
