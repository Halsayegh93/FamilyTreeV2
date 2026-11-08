import SwiftUI

// MARK: - إطار مربّع «العائلة» في تفاصيل العضو بالشجرتين (اختيار المالك ٢٠٢٦-١١-٠٧ «ب»: «صور مصغّرة بالرأس»)
// بطاقة بالإطار الرفيع والظلّ الخفيف + حدّ أخضر العائلة على جهة البداية (يمين بالعربي)؛ الرأس = «العائلة» وتحته
// الملخّص صغيراً رمادياً، ومطويّاً: صور متراكبة لأقرب الأقارب (حتى ٥) ثم «+N» ثم السهم؛ مفتوحاً: السهم لأسفل.
// المحتوى داخله كما هو (يمرّره المستدعي).

enum DSFamilyKit {
    /// عرض الحدّ الأخضر على جهة البداية
    static let edgeWidth: CGFloat = 4
    /// قطر الصورة الصغيرة في الرأس (بلا الحلقة)
    static let stackAvatar: CGFloat = 24
    /// الحلقة البيضاء حول كل صورة
    static let stackRing: CGFloat = 2
    /// تراكب الصور
    static let stackOverlap: CGFloat = 7
    /// أقصى عدد صور قبل «+N»
    static let stackMax = 5
    /// حرف الاسم داخل الصورة الصغيرة (نسبة من قطرها)
    static let stackInitialScale: CGFloat = 0.42
    /// مسافة شارة العلم عن طرف رأس المربّع حين يكون فيه زرّ ×
    static var badgeInsetWithClose: CGFloat {
        DS.Spacing.lg + (DS.Icon.row - DS.Spacing.xs) + DS.Spacing.md
    }
}

/// مربّع «العائلة» القابل للطي — الضغط على الرأس يفتح المحتوى ويطويه بحركة `DSComposerSection` نفسها
struct DSFamilyBox<Content: View>: View {
    var title: String = L10n.t("العائلة", "Family")
    /// «الأب · الأم · الزوجة · 6 أبناء» — دالة الملخّص الموجودة في كل شجرة
    let summary: String
    /// الأقارب بالترتيب: الأب/الأم/الزوجة أو الزوج/الأبناء — أول ٥ صور ثم «+N»
    let people: [FamilyMember]
    @Binding var isOpen: Bool
    var index: Int = 0
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DSBox.sectionInnerSpacing) {
            Button {
                withAnimation(reduceMotion ? nil : DSMotion.expand) { isOpen.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary.isEmpty ? title : "\(title)، \(summary)")
            .accessibilityAddTraits([.isHeader, .isButton])
            .accessibilityHint(isOpen ? L10n.t("يخفي المحتوى", "Collapses")
                                      : L10n.t("يعرض المحتوى", "Expands"))
            if isOpen {
                content()
                    .transition(contentTransition)
            }
        }
        // المحتوى بعيد عن الحدّ الأخضر بعرضه
        .padding(.leading, DSFamilyKit.edgeWidth)
        .dsCard()
        .overlay {
            // الحدّ الأخضر على جهة البداية، مقصوص بزوايا البطاقة (مثل border-right في العيّنة)
            HStack(spacing: 0) {
                Rectangle().fill(DS.Color.palm).frame(width: DSFamilyKit.edgeWidth)
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .dsStaggerIn(index)
    }

    /// نفس انسياب `DSComposerSection`: الفتح ينساب من تحت العنوان، والطي يتلاشى سريعاً
    private var contentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: AnyTransition.opacity.combined(with: .offset(y: -8))
                .animation(DSMotion.expand.delay(0.04)),
            removal: AnyTransition.opacity.animation(.easeOut(duration: 0.12))
        )
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                if !summary.isEmpty {
                    Text(summary)
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            // الصور المتراكبة مطويّاً فقط (ومن أحجام إمكانية الوصول يكفي الملخّص)
            if !isOpen && !people.isEmpty && !dynamicTypeSize.isAccessibilitySize {
                DSFamilyAvatarStack(people: people)
                    .transition(.opacity)
            }
            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .dsGlyph(DS.Glyph.smCompact)
                .foregroundColor(DS.Color.textTertiary)
                // مفتوحاً يشير لأسفل
                .rotationEffect(.degrees(isOpen ? (L10n.isArabic ? -90 : 90) : 0))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// صور صغيرة متراكبة بحلقة بيضاء (حتى ٥) ثم فقاعة كريمية «+N» للباقي
struct DSFamilyAvatarStack: View {
    let people: [FamilyMember]

    var body: some View {
        let shown = Array(people.prefix(DSFamilyKit.stackMax))
        let rest = people.count - shown.count
        HStack(spacing: -DSFamilyKit.stackOverlap) {
            ForEach(shown) { m in
                ringed { avatar(m) }
            }
            if rest > 0 {
                ringed {
                    Circle()
                        .fill(DS.Color.cardBackgroundSoft)
                        .overlay(
                            Text(verbatim: "+\(rest)")
                                .font(DS.Font.plexFixed(DSFamilyKit.stackAvatar * DSFamilyKit.stackInitialScale,
                                                        weight: .semibold))
                                .foregroundColor(DS.Color.accent)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                        )
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func ringed<V: View>(@ViewBuilder _ v: () -> V) -> some View {
        v()
            .frame(width: DSFamilyKit.stackAvatar, height: DSFamilyKit.stackAvatar)
            .clipShape(Circle())
            .padding(DSFamilyKit.stackRing)
            .background(Circle().fill(DS.Color.surface))
    }

    /// الصورة، وإلا الحرف الأول على لون الجنس؛ المتوفى بالأبيض والأسود
    @ViewBuilder
    private func avatar(_ m: FamilyMember) -> some View {
        let fill = m.isFemale ? DS.Color.femaleFill : DS.Color.maleFill
        let initial = Circle()
            .fill(fill)
            .overlay(
                Text(String((m.firstName.isEmpty ? m.fullName : m.firstName).prefix(1)))
                    .font(DS.Font.plexFixed(DSFamilyKit.stackAvatar * DSFamilyKit.stackInitialScale,
                                            weight: .semibold))
                    .foregroundColor(DS.Color.textOnPrimary)
            )
        Group {
            if let s = m.avatarUrl, let url = URL(string: s) {
                CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { initial }
            } else {
                initial
            }
        }
        .grayscale(m.isDeceased == true ? 1 : 0)
    }
}

/// يقرأ إغلاق المربّع المتحرّك من داخل المربّع (`dsPanelClose`) — وإلا `dismiss()`؛ لزرّ × في رأس التفاصيل
/// (قراءته من عرض التفاصيل نفسه فارغة — نفس سبب «إغلاق» في الشريط السفلي)
struct DSPanelCloseReader<Content: View>: View {
    @Environment(\.dsPanelClose) private var panelClose
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder let content: (@escaping () -> Void) -> Content

    var body: some View {
        content { if let panelClose { panelClose() } else { dismiss() } }
    }
}
