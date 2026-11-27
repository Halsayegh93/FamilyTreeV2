import SwiftUI

// MARK: - عُدّة بطاقة العضو «AB» (اختيار المالك ٢٠٢٦-١١-٢٧ «بين ا و ب»)
//
// شكل فقط — نفس المربّع بالمنتصف ونفس الترتيب والأزرار في الشجرتين. أساس A الهادئ (أرضية كريمية، خطوط ذهبية رفيعة،
// إطار ذهبي للصورة، زخرفة تحت الاسم، كل قسم لوح كريمي) ولون B في مكانين: مربّع لون العائلة بجانب عنوان القسم،
// وخانات «طلب تعديل» الملوّنة. الألوان والمقاسات من `DS.MemberCard` (DesignSystem.swift)، والقواعد من `MemberCardLogic`.

// MARK: الرأس والصورة والاسم

/// الخط الذهبي الرفيع تحت الرأس الكحلي (يتلاشى في الطرفين)
struct MemberCardBandHairline: View {
    var body: some View {
        LinearGradient(stops: [.init(color: .clear, location: 0),
                               .init(color: DS.MemberCard.gold, location: 0.18),
                               .init(color: DS.MemberCard.gold, location: 0.82),
                               .init(color: .clear, location: 1)],
                       startPoint: .leading, endPoint: .trailing)
            .frame(height: DS.MemberCard.bandHairline)
            .accessibilityHidden(true)
    }
}

/// إطار الصورة: فراغ بلون الأرضية ثم خط ذهبي رفيع وظلّ خفيف — الخط يرسم نفسه مرة عند الفتح من أعلى مع عقارب الساعة
/// (A1، `DSMotion.ringDraw` بعد قفزة الصورة). «تقليل الحركة»: مرسوم كاملاً من البداية
struct MemberCardAvatarFrame: ViewModifier {
    let side: CGFloat
    @State private var drawn: CGFloat? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let mat = DS.MemberCard.avatarMat
        let ring = DS.MemberCard.avatarRing
        content
            .padding(mat)
            .background(Circle().fill(DS.MemberCard.boxBackground))
            .overlay(
                Circle()
                    .inset(by: ring / 2)
                    .trim(from: 0, to: drawn ?? DSMotionRules.drawStart(reduceMotion: reduceMotion))
                    .stroke(DS.MemberCard.gold, style: StrokeStyle(lineWidth: ring, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .accessibilityHidden(true)
            )
            .dsSubtleShadow()
            .onAppear {
                guard drawn == nil else { return }
                guard !reduceMotion else { drawn = 1; return }
                drawn = 0
                withAnimation(DSMotion.ringDraw) { drawn = 1 }
            }
    }
}

extension View {
    func memberCardAvatarFrame(side: CGFloat) -> some View { modifier(MemberCardAvatarFrame(side: side)) }
}

/// الزخرفة تحت الاسم: خطّان ذهبيّان يتلاشيان وبينهما معيّن — تمتدّ مرة من المعيّن إلى الطرفين عند الفتح (A1،
/// قناع يتّسع من الوسط، فلا يتشوّه المعيّن ولا يهمّ اتجاه السطر). «تقليل الحركة»: كاملة من البداية
struct MemberCardOrnament: View {
    @State private var drawn: CGFloat? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let width = DS.MemberCard.ornamentWidth
        let seed = DS.MemberCard.ornamentDiamond * 2
        let p = drawn ?? DSMotionRules.drawStart(reduceMotion: reduceMotion)
        shape
            .mask(Rectangle().frame(width: seed + (width - seed) * p))
            .onAppear {
                guard drawn == nil else { return }
                guard !reduceMotion else { drawn = 1; return }
                drawn = 0
                withAnimation(DSMotion.ornamentDraw) { drawn = 1 }
            }
    }

    private var shape: some View {
        let half = (DS.MemberCard.ornamentWidth - DS.MemberCard.ornamentDiamond * 3) / 2
        return HStack(spacing: DS.MemberCard.ornamentDiamond) {
            line(fadingFrom: .leading).frame(width: half)
            Rectangle()
                .fill(DS.MemberCard.gold)
                .frame(width: DS.MemberCard.ornamentDiamond, height: DS.MemberCard.ornamentDiamond)
                .rotationEffect(.degrees(45))
            line(fadingFrom: .trailing).frame(width: half)
        }
        .frame(height: DS.MemberCard.ornamentDiamond * 1.5)
        .accessibilityHidden(true)
    }

    private func line(fadingFrom edge: UnitPoint) -> some View {
        LinearGradient(colors: [.clear, DS.MemberCard.gold],
                       startPoint: edge, endPoint: edge == .leading ? .trailing : .leading)
            .frame(height: DS.Border.width)
    }
}

/// شريحة ساكنة بإطار رفيع على أرضية الصفّ (العمر) — بمقاس شريحة «صلة القرابة»
struct MemberCardStaticChip: View {
    let text: String
    let icon: String
    let tint: Color
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.xsm) {
            Image(systemName: icon)
                .dsGlyph(DS.Glyph.sm)
                .accessibilityHidden(true)
            Text(text).dsFont(.chip)
            if let trailing { Text(trailing).dsFont(.caption) }
        }
        .lineLimit(1)
        .foregroundColor(tint)
        .padding(.horizontal, DSBox.chipPadding)
        .frame(minHeight: DSBox.chipHeight)
        .background(Capsule().fill(DS.MemberCard.inset))
        .overlay(Capsule().strokeBorder(tint.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
        .accessibilityElement(children: .combine)
    }
}

// MARK: الأقسام

/// عنوان القسم: مربّع صغير بلون العائلة ورمز أبيض + العنوان + خط ذهبي خافت حتى الطرف (+ رقم في دائرة ذهبية)
struct MemberCardSectionHeader: View {
    let title: String
    let icon: String
    let fill: Color
    var count: Int? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .dsGlyph(DS.Glyph.sm)
                .foregroundColor(DS.Color.textOnPrimary)
                .frame(width: DS.MemberCard.sectionSquare, height: DS.MemberCard.sectionSquare)
                .background(RoundedRectangle(cornerRadius: DS.MemberCard.sectionSquareRadius, style: .continuous).fill(fill))
                .accessibilityHidden(true)
            Text(title)
                .dsFont(.rowTitle)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
            MemberCardHairline()
            if let count {
                Text(verbatim: "\(count)")
                    .dsFont(.badge)
                    .foregroundColor(DS.MemberCard.goldText)
                    .frame(width: DS.MemberCard.countDisc, height: DS.MemberCard.countDisc)
                    .overlay(Circle().strokeBorder(DS.MemberCard.gold, lineWidth: DS.Border.width))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count.map { "\(title)، \($0)" } ?? title)
        .accessibilityAddTraits(.isHeader)
    }
}

/// الخط الذهبي الخافت بعد العنوان — يملأ ما بقي من السطر
struct MemberCardHairline: View {
    var body: some View {
        LinearGradient(colors: [DS.MemberCard.hair, .clear],
                       startPoint: .leading, endPoint: .trailing)
            .frame(height: DS.Border.width)
            .frame(maxWidth: .infinity)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .accessibilityHidden(true)
    }
}

/// لوح القسم الكريمي بإطار رفيع — العنوان ثم المحتوى
struct MemberCardSection<Content: View>: View {
    let title: String
    let icon: String
    let fill: Color
    var count: Int? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            MemberCardSectionHeader(title: title, icon: icon, fill: fill, count: count)
            content()
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .memberCardPanel()
    }
}

extension View {
    /// لوح كريمي بإطار رفيع (قسم)
    func memberCardPanel() -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.MemberCard.panelRadius, style: .continuous)
        return background(shape.fill(DS.MemberCard.panel))
            .overlay(shape.strokeBorder(DS.MemberCard.panelLine, lineWidth: DS.Border.width))
    }

    /// صفّ داخل اللوح (معلومة، طلب) — أبيض بإطار أخفّ
    func memberCardInset() -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.MemberCard.insetRadius, style: .continuous)
        return background(shape.fill(DS.MemberCard.inset))
            .overlay(shape.strokeBorder(DS.MemberCard.insetLine, lineWidth: DS.Border.width))
    }
}

/// صفّ معلومة: أيقونة في مربّع خفيف + العنوان الصغير + القيمة، وسطر صغير اختياري تحته (قفل «مخفي عن الأعضاء»)
struct MemberCardInfoRow: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = DS.Color.sea
    var ltr = false
    /// سطر صغير تحت القيمة بقفل (رقم المرأة للإدارة)
    var lockCaption: String? = nil
    /// سهم في الطرف حين يكون الصفّ زرّاً
    var tappable = false

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .dsGlyph(DS.Glyph.md)
                .foregroundColor(tint)
                .frame(width: DS.Icon.row, height: DS.Icon.row)
                .background(RoundedRectangle(cornerRadius: DS.MemberCard.sectionSquareRadius, style: .continuous)
                    .fill(tint.opacity(DS.Opacity.tintFill)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(label)
                    .dsFont(.caption)
                    .foregroundColor(DS.MemberCard.muted)
                Text(value)
                    .dsFieldFont(.fieldValue)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .environment(\.layoutDirection, ltr ? .leftToRight : LanguageManager.shared.layoutDirection)
                if let lockCaption {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "lock.fill")
                            .dsGlyph(DS.Glyph.micro)
                            .accessibilityHidden(true)
                        Text(lockCaption).dsFont(.micro)
                    }
                    .foregroundColor(DS.Color.textTertiary)
                }
            }
            Spacer(minLength: 0)
            if tappable {
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .dsGlyph(DS.Glyph.sm)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
        .memberCardInset()
        .accessibilityElement(children: .combine)
    }
}

// MARK: «العائلة»

/// قريب في صفّ الصور مطويّاً: الصورة ودوره تحتها
struct MemberCardRelative: Identifiable {
    let member: FamilyMember
    let role: String
    var id: UUID { member.id }
}

/// قسم «العائلة» بشكل AB — مطويّ ومغلق بالبداية كما كان (طلب المالك ٢٠٢٦-١١-٠٦): مطويّاً صور الأقارب بأدوارهم
/// و«عرض ‹»، ومفتوحاً المحتوى نفسه (يمرّره المستدعي) و«إخفاء»
struct MemberCardFamilyBox<Content: View, Face: View>: View {
    let summary: String
    let relatives: [MemberCardRelative]
    @Binding var isOpen: Bool
    @ViewBuilder let face: (FamilyMember) -> Face
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            MemberCardSectionHeader(title: L10n.t("العائلة", "Family"), icon: "person.3.fill",
                                    fill: DS.Color.palmFill)
            if isOpen {
                // الأب والأبناء ينزلون قليلاً مع تلاشٍ، ويختفون أسرع (`dsReveal`) — «تقليل الحركة»: تلاشٍ فقط
                content()
                    .transition(.dsReveal(reduceMotion: reduceMotion))
                toggle
            } else {
                HStack(alignment: .center, spacing: DS.Spacing.md) {
                    HStack(alignment: .top, spacing: DS.Spacing.sm) {
                        ForEach(relatives.prefix(4)) { r in
                            VStack(spacing: DS.Spacing.xxs) {
                                face(r.member)
                                    .frame(width: DS.MemberCard.face, height: DS.MemberCard.face)
                                    .overlay(Circle().strokeBorder(DS.MemberCard.hair, lineWidth: DS.Border.width))
                                Text(r.role)
                                    .dsFont(.micro)
                                    .foregroundColor(DS.MemberCard.muted)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                        if relatives.count > 4 {
                            Text(verbatim: "+\(relatives.count - 4)")
                                .dsFont(.badge)
                                .foregroundColor(DS.MemberCard.goldText)
                                .frame(width: DS.MemberCard.face, height: DS.MemberCard.face)
                                .background(Circle().fill(DS.MemberCard.inset))
                                .overlay(Circle().strokeBorder(DS.MemberCard.hair, lineWidth: DS.Border.width))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(summary)
                    Spacer(minLength: 0)
                    toggle
                }
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .memberCardPanel()
    }

    private var toggle: some View {
        Button {
            withAnimation(reduceMotion ? DSMotion.fade : DSMotion.expand) { isOpen.toggle() }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Text(isOpen ? L10n.t("إخفاء", "Hide") : L10n.t("عرض", "Show"))
                    .dsFont(.chip)
                Image(systemName: isOpen ? "chevron.up" : (L10n.isArabic ? "chevron.left" : "chevron.right"))
                    .dsGlyph(DS.Glyph.xs)
                    .accessibilityHidden(true)
            }
            .foregroundColor(DS.MemberCard.goldText)
            .frame(minWidth: DS.Icon.tapTarget, minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .frame(maxWidth: isOpen ? .infinity : nil, alignment: .trailing)
        .accessibilityLabel(isOpen ? L10n.t("إخفاء العائلة", "Hide family") : L10n.t("عرض العائلة", "Show family"))
    }
}

// MARK: «طلبك عنه» / «طلبات معلّقة»

/// القسم بالبند ٧: `mine` = طلباتك أنت مع «تابِعه»، `all` = كل الطلبات لمن يقرّر طلبات الشجرة وكل صفّ يفتح «الوارد»
struct MemberCardRequestsSection: View {
    let requests: [AdminRequest]
    let mode: MemberCardLogic.RequestsSection
    let female: Bool
    /// «تابِعه» (طلبك) أو فتح الطلب في «الوارد» (الكل)
    let onOpen: (AdminRequest) -> Void

    var body: some View {
        if mode != .none && !requests.isEmpty {
            MemberCardSection(title: mode == .mine ? MemberCardLogic.myRequestTitle(female: female)
                                                   : L10n.t("طلبات معلّقة", "Pending requests"),
                              icon: "checklist", fill: DS.Color.goldFill, count: requests.count) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    ForEach(requests) { row($0) }
                    Text(mode == .mine ? MemberCardLogic.followHint
                                       : L10n.t("اضغط الطلب يفتح في «الوارد» على الطلب نفسه", "Tap a request to open it in the inbox"))
                        .dsFont(.caption)
                        .foregroundColor(DS.MemberCard.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func row(_ request: AdminRequest) -> some View {
        let action = request.treeEditPayload?.displayAction
        return Button { onOpen(request) } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: action?.iconName ?? "questionmark.circle")
                    .dsGlyph(DS.Glyph.md)
                    .foregroundColor(DS.MemberCard.goldText)
                    .frame(width: DS.Icon.row, height: DS.Icon.row)
                    .background(RoundedRectangle(cornerRadius: DS.MemberCard.sectionSquareRadius, style: .continuous)
                        .fill(DS.Color.goldFill.opacity(DS.Opacity.tintFill)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(L10n.t(action?.arabicLabel ?? "—", action?.englishLabel ?? "—"))
                        .dsFont(.caption)
                        .foregroundColor(DS.MemberCard.muted)
                    Text(L10n.t("قيد المراجعة", "Under review"))
                        .dsFieldFont(.fieldValue)
                        .foregroundColor(DS.Color.textPrimary)
                }
                Spacer(minLength: 0)
                HStack(spacing: DS.Spacing.xs) {
                    Text(mode == .mine ? L10n.t("تابِعه", "Follow") : L10n.t("في الوارد", "In inbox"))
                        .dsFont(.chip)
                    Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                        .dsGlyph(DS.Glyph.xs)
                        .accessibilityHidden(true)
                }
                .foregroundColor(DS.MemberCard.goldText)
                .padding(.horizontal, DS.Spacing.md)
                .frame(minHeight: DSBox.chipHeight)
                .background(Capsule().fill(DS.MemberCard.inset))
                .overlay(Capsule().strokeBorder(DS.MemberCard.gold, lineWidth: DS.Border.width))
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
            .memberCardInset()
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(mode == .mine ? L10n.t("يفتح الطلبات المرسلة", "Opens your sent requests")
                                         : L10n.t("يفتح الطلب في الوارد", "Opens the request in the inbox"))
    }
}

// MARK: «طلب تعديل» — الخانات الملوّنة

/// لون الخانة بنوعها: الإضافة أخضر، التعديل كحلي، الوفاة رمادي، «طلب آخر» بترولي، الحذف أحمر
enum MemberTilePalette {
    case add, edit, record, other, delete

    var colors: (Color, Color) {
        switch self {
        case .add: return DS.MemberCard.tileAdd
        case .edit: return DS.MemberCard.tileEdit
        case .record: return DS.MemberCard.tileRecord
        case .other: return DS.MemberCard.tileOther
        case .delete: return DS.MemberCard.tileDelete
        }
    }
}

/// خانة «طلب تعديل»: الأيقونة بيضاء في حلقة كريمية، والاسم، ولمن، والسطر الصادق — وخلفها رسمة كبيرة باهتة
struct MemberRequestTile: View {
    let title: String
    let subtitle: String?
    let icon: String
    let palette: MemberTilePalette
    /// السطر الصادق (`MemberCardLogic.Honesty`) أو «طلبك قيد المراجعة · افتحه»
    let line: String
    var lineStyle: LineStyle = .honest
    let action: () -> Void

    enum LineStyle { case honest, pending, warning }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.MemberCard.tileRadius, style: .continuous)
        let (fill, deep) = palette.colors
        Button {
            guard TapDebouncer.shared.canFire("MemberRequestTile_\(title)") else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: DS.Spacing.xsm) {
                Image(systemName: icon)
                    .dsGlyph(DS.Glyph.lg)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .frame(width: DS.MemberCard.tileIconRing, height: DS.MemberCard.tileIconRing)
                    .background(Circle().fill(DS.Color.textOnPrimary.opacity(DS.MemberCard.tileDiscOpacity)))
                    .overlay(Circle().strokeBorder(DS.MemberCard.tileRing.opacity(DS.MemberCard.tileRingOpacity),
                                                   lineWidth: DS.MemberCard.avatarRing))
                    .accessibilityHidden(true)
                Text(title)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(DSBox.buttonLabelMinScale)
                VStack(spacing: DS.Spacing.xxs) {
                    if let subtitle {
                        Text(subtitle)
                            .dsFont(.caption)
                            .foregroundColor(DS.Color.textOnPrimary.opacity(DS.MemberCard.tileSubtitleOpacity))
                            .lineLimit(1)
                            .minimumScaleFactor(DSBox.buttonLabelMinScale)
                    }
                    Text(line)
                        .dsFont(.micro)
                        .foregroundColor(lineColor)
                        .lineLimit(2)
                        .minimumScaleFactor(DSBox.buttonLabelMinScale)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: DS.MemberCard.tileMinHeight, maxHeight: .infinity)
            .background(
                ZStack(alignment: .bottomTrailing) {
                    shape.fill(LinearGradient(colors: [fill, deep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: icon)
                        .font(DS.Font.icon(DS.MemberCard.tileWatermark, weight: .light))
                        .foregroundColor(DS.Color.textOnPrimary.opacity(DS.MemberCard.tileWatermarkOpacity))
                        .offset(x: DS.Spacing.md, y: DS.Spacing.md)
                        .accessibilityHidden(true)
                }
                .clipShape(shape)
            )
            .overlay(MemberTilePressVeil(radius: DS.MemberCard.tileRadius))
            .dsSubtleShadow()
            .contentShape(shape)
        }
        // ضغطة المربّعات الموحّدة (A1): يصغر ٠٫٩٧ وتغمق طبقته قليلاً — «تقليل الحركة»: الطبقة وحدها
        .buttonStyle(AdminTilePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([subtitle, line].compactMap { $0 }.joined(separator: "، "))
        .accessibilityAddTraits(.isButton)
    }

    private var lineColor: Color {
        switch lineStyle {
        case .honest: return DS.MemberCard.tileHonestText
        case .pending: return DS.MemberCard.tilePendingText
        case .warning: return DS.MemberCard.tileWarningText
        }
    }
}

/// طبقة الضغط فوق الخانة الملوّنة — تقرأ الضغط من داخل الزرّ (`AdminTilePressStyle` يضعه على محتواه)
private struct MemberTilePressVeil: View {
    let radius: CGFloat
    @Environment(\.adminTilePressed) private var pressed

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(DS.Hub.tilePressVeil)
            .opacity(pressed ? 1 : 0)
            .animation(DS.Hub.tilePress, value: pressed)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// شبكة الخانات: اثنتان في السطر (واحدة من أحجام إمكانية الوصول)، والسطر الناقص في المنتصف
struct MemberRequestGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        DSTileGridLayout(columns: typeSize.isAccessibilitySize ? 1 : 2, spacing: DS.Spacing.sm, square: false) {
            content()
        }
    }
}

/// «اختر نوع الطلب» + خط ذهبي خافت
struct MemberCardGridTitle: View {
    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(L10n.t("اختر نوع الطلب", "Choose request type"))
                .dsFont(.boxSectionTitle)
                .foregroundColor(DS.Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            MemberCardHairline()
        }
    }
}

/// الملاحظة تحت الشبكة: لوح أبيض بحدّ ذهبي على جهة البداية
struct MemberCardStrip: View {
    let text: String
    var body: some View {
        Text(text)
            .dsFont(.caption)
            .foregroundColor(DS.Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .padding(.leading, DS.MemberCard.stripEdge)
            .background(DS.MemberCard.inset)
            .overlay(alignment: .leading) {
                Rectangle().fill(DS.MemberCard.gold).frame(width: DS.MemberCard.stripEdge)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.MemberCard.insetRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.MemberCard.insetRadius, style: .continuous)
                .strokeBorder(DS.MemberCard.panelLine, lineWidth: DS.Border.width))
    }
}

// MARK: «الطلبات المرسلة» من البطاقة («تابِعه» و«طلبك قيد المراجعة · افتحه»)

/// الصفحة نفسها من مركز الإشعارات (`MySentRequestsList`) برأس المربّعات — تُفتح فوق البطاقة
struct MemberCardSentRequestsBox: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DSComposerHeader(title: L10n.t("الطلبات المرسلة", "Sent requests"),
                             subtitle: L10n.t("تتابعها أو تسحبها من هنا", "Follow or withdraw them here"),
                             icon: "paperplane.fill",
                             tint: DS.Color.actionNavy,
                             onClose: onClose)
            MySentRequestsList(section: AppSection.current ?? .home)
        }
        .background(DS.Color.background)
    }
}
