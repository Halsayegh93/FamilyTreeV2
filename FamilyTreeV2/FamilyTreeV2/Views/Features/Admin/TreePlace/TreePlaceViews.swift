import SwiftUI

// MARK: - «مكانه في الشجرة»: القسم داخل الطلب + المقطع الصغير (الاختيار «ج»، ٢٠٢٦-١١-١٣)

/// مقاسات المقطع — عقدة ٧٢ بزوايا ١٢ وصورة ٢٢ (المواصفة)، والنص بأدوار النص فيكبر مع «حجم النص»
enum TreePlaceMetrics {
    static let nodeWidth: CGFloat = 72
    static let avatar: CGFloat = 22
    static let photoAvatar: CGFloat = DS.Icon.row
    static let moreWidth: CGFloat = 36
    static let gap: CGFloat = DS.Spacing.sm
    static let line: CGFloat = 2
    static let parentLink: CGFloat = DS.Spacing.md + DS.Spacing.xxs
    static let busHeight: CGFloat = DS.Spacing.lg + DS.Spacing.xxs
    static let fatherBorder: CGFloat = 2
    static let markBorder: CGFloat = 2
    static let haloBorder: CGFloat = 2.5
    static let haloWidth: CGFloat = 4
    static let grandfatherOpacity: Double = 0.55
}

/// القسم «مكانه في الشجرة» — بعد قسم بيانات الطلب: المقطع ← الملاحظة ← «افتح بالشجرة الكاملة» (يفتح الشجرة الحقيقية)
struct TreePlaceSection: View {
    let place: TreePlace?
    var index: Int = 2
    /// أعضاء شجرة العائلة (`memberVM.allMembers`) — محمّلة مسبقاً
    let men: [FamilyMember]
    /// زرّ المربّع الرئيسي نفسه — يتكرّر في المعاينة؛ nil = «العودة إلى الطلب» وحده
    var primary: TreePlacePrimary? = nil
    /// بلا مكان يُرسم (طلب انضمام بلا مطابق): الملاحظة وحدها
    var emptyNote: String? = nil
    /// في بطاقات القوائم: زرّ «افتح بالشجرة الكاملة» وحده (الملاحظة في لوحة المعاينة)
    var buttonOnly: Bool = false
    /// زرّ الرجوع في المعاينة: «العودة إلى الطلب» (الافتراضي) أو «العودة إلى الإشعار»
    var backTitle: String = TreePlaceText.backToRequest

    @State private var women: [FamilyMember] = WomenStore.cache
    @State private var showPreview = false
    @State private var runPrimary = false

    var body: some View {
        let resolved = place?.resolve(TreePlaceData(men: men, women: women))
        Group {
            if buttonOnly {
                if resolved != nil { TreePlaceOpenButton { showPreview = true } }
            } else {
                section(resolved)
            }
        }
        // شجرة النساء لم تُفتح بعد في هذه الجلسة: قراءتها مرة (قراءة فقط) ليُرسم المكان
        .task(id: place?.tree == .women) {
            guard place?.tree == .women, women.isEmpty else { return }
            if let fetched = try? await WomenStore.fetch() { women = fetched }
        }
        .fullScreenCover(isPresented: $showPreview, onDismiss: {
            // الإجراء الرئيسي بعد إغلاق المعاينة — فيعمل المعالج نفسه (وتأكيده إن كان له) فوق المربّع
            guard runPrimary else { return }
            runPrimary = false
            primary?.action()
        }) {
            if let resolved {
                TreePlacePreviewScreen(resolved: resolved, men: men, women: women,
                                       primaryTitle: primary?.title, primaryIcon: primary?.icon, backTitle: backTitle,
                                       onBack: { showPreview = false },
                                       onPrimary: { runPrimary = true; showPreview = false })
            }
        }
    }

    private func section(_ resolved: TreePlaceResolved?) -> some View {
        DSComposerSection(title: TreePlaceText.sectionTitle, icon: AppSection.tree.symbol,
                          tint: AppSection.tree.ink, index: index) {
            if let resolved {
                VStack(spacing: DS.Spacing.md) {
                    TreePlaceSnippet(resolved: resolved, data: TreePlaceData(men: men, women: women))
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(resolved.note)
                    Text(resolved.note)
                        .dsFont(.footnote)
                        .foregroundColor(resolved.noteIsDanger ? DS.Color.error : DS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    TreePlaceOpenButton { showPreview = true }
                }
            } else if let emptyNote {
                DSNoteCard(emptyNote, icon: "person.badge.plus", tint: DS.Color.warning)
            } else if let place {
                // لا أب مسجّل، أو ما تمّ/رُفض وشخصه لم يعد في الشجرة
                DSNoteCard(place.unresolvedNote(TreePlaceData(men: men, women: women)),
                           icon: "exclamationmark.triangle.fill", tint: DS.Color.warning)
            }
        }
    }
}

/// «افتح بالشجرة الكاملة» — بعرض كامل ٤٤، إطار ذهبي ونص ذهبي ورمز الشجرة
struct TreePlaceOpenButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSBox.buttonSpacing) {
                Image(dsSymbol: AppSection.tree.symbol)
                    .dsGlyph(DS.Glyph.md)
                    .accessibilityHidden(true)
                Text(TreePlaceText.openFull)
            }
            .font(DSBox.buttonFont)
            .foregroundColor(DS.Color.accent)
            .dsButtonLabelFit()
            .frame(maxWidth: .infinity, minHeight: DSBox.buttonHeight)
            .background(DSBox.buttonShape.fill(DS.Color.accentLight.opacity(DS.Opacity.tintFillSoft)))
            .overlay(DSBox.buttonShape.strokeBorder(DS.Color.accentLight, lineWidth: DS.Border.widthBold))
            .contentShape(DSBox.buttonShape)
        }
        .buttonStyle(DSScaleButtonStyle())
    }
}

// MARK: - المقطع

/// المقطع بحسب التغيير: الجد ← الأب ← الإخوة · قبل ‹ بعد · نقل (قبل ثم بعد) · زوجة من خارج العائلة · الرأس
struct TreePlaceSnippet: View {
    let resolved: TreePlaceResolved
    let data: TreePlaceData

    var body: some View {
        switch resolved.shape {
        case .tree:
            family(grandfather: resolved.grandfather, father: resolved.father, siblings: resolved.siblings,
                   shown: resolved.after ?? resolved.person, mark: resolved.mark)
        case .beforeAfter:
            beforeAfter
        case .moveFather:
            let A = TreePlaceText.pair(resolved.oldFather, fatherOf: { data.man($0) ?? data.woman($0) })
            let B = TreePlaceText.pair(resolved.father, fatherOf: { data.man($0) ?? data.woman($0) })
            VStack(spacing: DS.Spacing.md) {
                stageCaption(L10n.t("قبل: تحت «\(A)»", "Before: under «\(A)»"))
                family(grandfather: resolved.oldGrandfather, father: resolved.oldFather, siblings: resolved.oldSiblings,
                       shown: resolved.person,
                       mark: TreePlaceMarkStyle(kind: .ring, pill: nil, female: resolved.female))
                Rectangle()
                    .fill(DS.Color.textTertiary.opacity(DS.Opacity.divider))
                    .frame(height: DS.Border.width)
                    .padding(.horizontal, DS.Spacing.xl)
                stageCaption(L10n.t("بعد: تحت «\(B)»", "After: under «\(B)»"))
                family(grandfather: resolved.grandfather, father: resolved.father, siblings: resolved.siblings,
                       shown: resolved.after ?? resolved.person, mark: resolved.mark)
            }
        case .outsideWife:
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                TreePlaceMiniNode(member: resolved.person, role: .father)
                TreePlaceWifeGhost(name: resolved.wifeName ?? "")
            }
        case .rootOnly:
            TreePlaceMiniNode(member: resolved.person, mark: resolved.mark)
        }
    }

    private func stageCaption(_ text: String) -> some View {
        Text(text)
            .dsFont(.caption)
            .foregroundColor(DS.Color.textTertiary)
            .frame(maxWidth: .infinity)
    }

    /// الجد (باهت) ← الأب (إطار كحلي) ← الإخوة بترتيب الشجرة — الخط من الجد إلى الأب ومن الأب إلى الشخص ذهبي
    @ViewBuilder
    private func family(grandfather: FamilyMember?, father: FamilyMember?, siblings: [FamilyMember],
                        shown: FamilyMember, mark: TreePlaceMarkStyle) -> some View {
        VStack(spacing: 0) {
            if let grandfather {
                TreePlaceMiniNode(member: grandfather, caption: TreePlaceText.grandfather, role: .grandfather)
                Rectangle()
                    .fill(TreePlaceSiblingRow.pathColor(mark))
                    .frame(width: TreePlaceMetrics.line, height: TreePlaceMetrics.parentLink)
                    .accessibilityHidden(true)
            }
            if let father {
                TreePlaceMiniNode(member: father,
                                  caption: resolved.place.tree == .women ? TreePlaceText.herFather : TreePlaceText.father,
                                  role: .father)
            }
            let list = siblings.map { $0.id == shown.id ? shown : $0 }
            let pi = list.firstIndex { $0.id == shown.id } ?? 0
            let w = TreePlaceSiblingRow.windows(count: list.count)
            // أوسع نافذة تتّسع في عرض المربّع (الكل أو ±٢ ← ±١ ← الشخص وحده)
            ViewThatFits(in: .horizontal) {
                TreePlaceSiblingRow(siblings: list, personIndex: pi, neighbours: w[0], mark: mark, hasFather: father != nil)
                TreePlaceSiblingRow(siblings: list, personIndex: pi, neighbours: w[1], mark: mark, hasFather: father != nil)
                TreePlaceSiblingRow(siblings: list, personIndex: pi, neighbours: w[2], mark: mark, hasFather: father != nil)
            }
        }
    }

    /// قبل ‹ بعد في نفس المكان: الاسم/الميلاد القديم مشطوب رمادي، والجديد بإطار ذهبي
    private var beforeAfter: some View {
        let before = resolved.person
        let after = resolved.after ?? resolved.person
        var strikeName = false, strikeCaption = false
        var beforeCaption: String? = nil, afterCaption: String? = nil
        var avatar = TreePlaceMetrics.avatar
        switch resolved.place.change {
        case .rename:
            // الاسم الأول نفسه (تغيّر الأب أو الجد…): الجزء المتغيّر من الاسم الكامل وصفاً مشطوباً ← جديداً
            if TreePlaceText.firstName(before) == TreePlaceText.firstName(after),
               let diff = TreePlaceText.nameDiff(before.fullName, after.fullName) {
                beforeCaption = diff.old
                afterCaption = diff.new
                strikeCaption = true
            } else {
                strikeName = true
            }
        case .birth:
            strikeCaption = true
            beforeCaption = TreePlaceText.birthCaption(before.birthDate) ?? L10n.t("بلا ميلاد", "No birth date")
            afterCaption = TreePlaceText.birthCaption(after.birthDate) ?? after.birthDate
        case .photo: avatar = TreePlaceMetrics.photoAvatar
        default: break
        }
        return HStack(alignment: .center, spacing: DS.Spacing.sm) {
            VStack(spacing: DS.Spacing.xs) {
                stageCaption(TreePlaceText.before)
                TreePlaceMiniNode(member: before, caption: beforeCaption, struck: strikeName,
                                  captionStruck: strikeCaption, avatarSize: avatar, dimmed: true)
            }
            .fixedSize()
            Image(systemName: "chevron.forward")
                .dsGlyph(DS.Glyph.sm, weight: .bold)
                .foregroundColor(DS.Color.accentLight)
                .accessibilityHidden(true)
            VStack(spacing: DS.Spacing.xs) {
                stageCaption(TreePlaceText.after)
                TreePlaceMiniNode(member: after, caption: afterCaption, mark: resolved.mark, avatarSize: avatar)
            }
            .fixedSize()
        }
    }
}

/// صفّ الإخوة مع خطوطه: أفقي رمادي فوقهم، ونزول ذهبي من الأب إلى الشخص. أكثر من ٥ ← الشخص وجاران من كل جهة و«+N»
struct TreePlaceSiblingRow: View {
    let siblings: [FamilyMember]
    let personIndex: Int
    /// nil = الكل
    let neighbours: Int?
    let mark: TreePlaceMarkStyle
    let hasFather: Bool
    @Environment(\.layoutDirection) private var direction

    /// لون الطريق من الجد والأب إلى الشخص: ذهبي، ورمادي للطلب المرفوض (بلا ذهبي)
    static func pathColor(_ mark: TreePlaceMarkStyle) -> Color {
        mark.kind == .rejected ? DS.Color.textTertiary.opacity(DS.Opacity.selectedStroke) : DS.Color.accentLight
    }

    /// النوافذ بالترتيب لـ `ViewThatFits`: الكل (≤ ٥) أو ±٢، ثم ±١، ثم الشخص وحده — nil = الكل
    static func windows(count: Int) -> [Int?] {
        count <= 5 ? [nil, 1, 0] : [2, 1, 0]
    }

    private enum Slot: Hashable {
        case node(Int)
        case more(Int, trailingEnd: Bool)
    }

    /// الخانات بترتيب الشجرة (الأكبر أولاً)
    private var slots: [Slot] {
        guard let n = neighbours, siblings.count > 1 else { return siblings.indices.map { .node($0) } }
        let lo = max(0, personIndex - n), hi = min(siblings.count - 1, personIndex + n)
        var out: [Slot] = []
        if lo > 0 { out.append(.more(lo, trailingEnd: false)) }
        out += (lo...hi).map { .node($0) }
        if hi < siblings.count - 1 { out.append(.more(siblings.count - 1 - hi, trailingEnd: true)) }
        return out
    }

    private func width(_ s: Slot) -> CGFloat {
        if case .more = s { return TreePlaceMetrics.moreWidth }
        return TreePlaceMetrics.nodeWidth
    }

    var body: some View {
        // الأكبر يميناً في العربية (مثل الشجرة) — الرسم بإحداثيات من اليسار
        let visual = direction == .rightToLeft ? Array(slots.reversed()) : slots
        var centers: [CGFloat] = []
        var x: CGFloat = 0
        for s in visual {
            centers.append(x + width(s) / 2)
            x += width(s) + TreePlaceMetrics.gap
        }
        let total = max(0, x - TreePlaceMetrics.gap)
        let personSlot = visual.firstIndex(of: .node(personIndex))
        let outerDirection = direction
        return VStack(spacing: 0) {
            if hasFather {
                connectors(visual: visual, centers: centers, total: total, personSlot: personSlot)
                    .frame(width: total, height: TreePlaceMetrics.busHeight)
            }
            HStack(alignment: .top, spacing: TreePlaceMetrics.gap) {
                ForEach(Array(visual.enumerated()), id: \.offset) { _, s in
                    switch s {
                    case .node(let i):
                        TreePlaceMiniNode(member: siblings[i], mark: i == personIndex ? mark : nil)
                            .environment(\.layoutDirection, outerDirection)
                    case .more(let n, _):
                        Text("+\(n)")
                            .dsFont(.badge)
                            .foregroundColor(DS.Color.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.vertical, DS.Spacing.xxs)
                            .frame(width: TreePlaceMetrics.moreWidth)
                            .background(Capsule().fill(DS.Color.fieldFill))
                            .padding(.top, DS.Spacing.lg)
                    }
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .fixedSize()
    }

    private func connectors(visual: [Slot], centers: [CGFloat], total: CGFloat, personSlot: Int?) -> some View {
        let fx = total / 2
        let busY = TreePlaceMetrics.busHeight / 2
        let bottom = TreePlaceMetrics.busHeight
        let xs = centers + [fx]
        let lo = xs.min() ?? fx, hi = xs.max() ?? fx
        let grey = DS.Color.textTertiary.opacity(DS.Opacity.tintStroke)
        let gold = Self.pathColor(mark)
        let w = TreePlaceMetrics.line
        return Canvas { ctx, _ in
            var bus = Path()
            bus.move(to: CGPoint(x: lo, y: busY)); bus.addLine(to: CGPoint(x: hi, y: busY))
            for (i, s) in visual.enumerated() where i != personSlot {
                if case .node = s {
                    bus.move(to: CGPoint(x: centers[i], y: busY)); bus.addLine(to: CGPoint(x: centers[i], y: bottom))
                }
            }
            ctx.stroke(bus, with: .color(grey), style: StrokeStyle(lineWidth: w, lineCap: .round))
            var path = Path()
            path.move(to: CGPoint(x: fx, y: 0)); path.addLine(to: CGPoint(x: fx, y: busY))
            if let p = personSlot {
                path.addLine(to: CGPoint(x: centers[p], y: busY))
                path.addLine(to: CGPoint(x: centers[p], y: bottom))
            }
            ctx.stroke(path, with: .color(gold), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// عقدة المقطع: صورة ٢٢ (أو الحرف الأول بلون الجنس) + الاسم الأول + وصف اختياري + شريحة التغيير
struct TreePlaceMiniNode: View {
    enum Role { case plain, grandfather, father }

    let member: FamilyMember
    var caption: String? = nil
    var role: Role = .plain
    var mark: TreePlaceMarkStyle? = nil
    /// «قبل»: الاسم مشطوب رمادي
    var struck: Bool = false
    var captionStruck: Bool = false
    var avatarSize: CGFloat = TreePlaceMetrics.avatar
    /// «قبل» كاملة رمادية
    var dimmed: Bool = false

    private var female: Bool { member.isFemale }
    private var tint: Color { female ? DS.Color.female : DS.Color.male }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous) }

    var body: some View {
        VStack(spacing: DS.Spacing.xxs) {
            avatar
            Text(TreePlaceText.firstName(member))
                .dsFont(.chip)
                .foregroundColor(nameColor)
                .strikethrough(struck, color: DS.Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let caption {
                Text(caption)
                    .dsFont(.micro)
                    .foregroundColor(DS.Color.textTertiary)
                    .strikethrough(captionStruck, color: DS.Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let pill = mark?.pill {
                Text(pill)
                    .dsFont(.badge)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, DS.Spacing.xsm)
                    .padding(.vertical, DS.Spacing.xxs)
                    .background(Capsule().fill(mark?.pillFill ?? DS.Color.goldFill))
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .padding(.horizontal, DS.Spacing.xs)
        .frame(width: TreePlaceMetrics.nodeWidth)
        .background(shape.fill(DS.Color.cardBackground))
        .overlay(fillOverlay)
        .overlay(border)
        .background(halo)
        .opacity(role == .grandfather || mark?.fadesPerson == true ? TreePlaceMetrics.grandfatherOpacity : 1)
    }

    private var nameColor: Color {
        if struck || dimmed { return DS.Color.textTertiary }
        guard let mark else { return DS.Color.textPrimary }
        switch mark.kind {
        case .ghost, .danger, .grey, .rejected: return mark.ink
        default: return DS.Color.textPrimary
        }
    }

    @ViewBuilder private var fillOverlay: some View {
        if let mark, mark.fillOpacity > 0 {
            shape.fill(mark.tint.opacity(mark.fillOpacity)).allowsHitTesting(false)
        }
    }

    @ViewBuilder private var border: some View {
        if let mark {
            switch mark.kind {
            case .ghost, .danger, .rejected:
                shape.strokeBorder(mark.tint, style: StrokeStyle(lineWidth: TreePlaceMetrics.markBorder,
                                                                 dash: [DS.Spacing.xs, DS.Spacing.xs - 1]))
            case .halo:
                shape.strokeBorder(mark.tint, lineWidth: TreePlaceMetrics.haloBorder)
            case .ring:
                shape.strokeBorder(mark.tint, lineWidth: TreePlaceMetrics.markBorder)
            case .grey:
                shape.strokeBorder(DS.Color.deceased.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.widthBold)
            }
        } else if role == .father {
            shape.strokeBorder(DS.Color.male, lineWidth: TreePlaceMetrics.fatherBorder)
        } else {
            shape.strokeBorder(DS.Color.cardBorder, lineWidth: DS.Border.widthBold)
        }
    }

    @ViewBuilder private var halo: some View {
        if let mark, mark.kind == .halo {
            RoundedRectangle(cornerRadius: DS.Radius.md + TreePlaceMetrics.haloWidth, style: .continuous)
                .fill(mark.tint.opacity(DS.Opacity.tintFillStrong))
                .padding(-TreePlaceMetrics.haloWidth)
        }
    }

    @ViewBuilder private var avatar: some View {
        let url = (member.avatarUrl ?? member.photoURL).flatMap { URL(string: $0) }
        let solid = mark.map { [.ghost, .grey, .danger, .rejected].contains($0.kind) } ?? false
        ZStack {
            Circle().fill(solid ? (mark?.pillFill ?? tint) : tint.opacity(DS.Opacity.tintFill))
            Text(String(TreePlaceText.firstName(member).prefix(1)))
                .dsFont(.micro)
                .foregroundColor(solid ? DS.Color.textOnPrimary : tint.dsReadableGlyph)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let url {
                CachedAsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
                .saturation(member.isDeceased == true || dimmed ? 0 : 1)
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .accessibilityHidden(true)
    }
}

/// زوجة من خارج العائلة: مربّع شبح وردي متقطّع باسمها وشريحة «زوجة من خارج العائلة» — بلا خط
struct TreePlaceWifeGhost: View {
    let name: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        VStack(spacing: DS.Spacing.xxs) {
            Text(PersonName.firstUnit(name.trimmingCharacters(in: .whitespacesAndNewlines)))
                .dsFont(.chip)
                .foregroundColor(DS.Color.female)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(TreePlaceText.outsideWifePill)
                .dsFont(.badge)
                .foregroundColor(DS.Color.textOnPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, DS.Spacing.xsm)
                .padding(.vertical, DS.Spacing.xxs)
                .background(Capsule().fill(DS.Color.femaleFill))
        }
        .padding(.vertical, DS.Spacing.md)
        .padding(.horizontal, DS.Spacing.sm)
        .frame(minWidth: TreePlaceMetrics.nodeWidth * 1.6)
        .background(shape.fill(DS.Color.female.opacity(DS.Opacity.tintFillSoft)))
        .overlay(shape.strokeBorder(DS.Color.female, style: StrokeStyle(lineWidth: TreePlaceMetrics.markBorder,
                                                                         dash: [DS.Spacing.xs, DS.Spacing.xs - 1])))
    }
}
