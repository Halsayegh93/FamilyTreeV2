import Foundation
#if !ADMIN_LOGIC_TEST
import SwiftUI
#endif

// MARK: - «يحتاج مراجعتك» مربّعات في أعلى «العائلة» (اختيار المالك «ب · ثلاثة في كل صف»، ٢٠٢٦-١١-٢٨)
//
// بدل بطاقة «يحتاج مراجعتك» وصفّ «المكرر والأخطاء» تحتها: شبكة مربّعات، ثلاثة في كل صف. كل مربّع = مربّع أيقونة ملوّن ·
// رقم كبير بلون المربّع (رمادي حين صفر أو قبل وصوله) · اسم قصير. الضغط يفتح الصفحة الموجودة نفسها (لا صفحة جديدة):
//   المكرر والأخطاء ← `AdminIssuesPage` · مشكلات الشجرة ← قائمتها · تواريخ وفاة ناقصة ← `DeathDatesCampaignPage` ·
//   مسجّلون بلا صورة ← `AdminPhotoNudgePage` · متزوجة بلا زوج مربوط ← `AdminIssuesPage` (قسمها هناك) ·
//   ثم بقية قوائم «يحتاج مراجعتك» الحقيقية (هل ما زالوا أحياء؟ · بيانات ناقصة · لم يفتحوا التطبيق · لم يدخلوا منذ 21 يوماً).
// الأعداد من المصادر نفسها (`AdminReviewHubCounts`، `AdminIssuesData`). الصفر لا يفتح شيئاً. فراغ آخر صفّ يُملأ بمربّع هادئ
// «✓ الباقي سليم». من أحجام إمكانية الوصول: صفوف بعرض الصفحة (الأيقونة · الاسم · الرقم)، ومع XXXL عمودان.
//
// المنطق الخالص (الترتيب، لون الرقم، المربّع الهادئ) يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/rt1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminReviewTiles.swift tests/admin-redesign/RT1/main.swift && /tmp/rt1-logic

/// مربّع في «يحتاج مراجعتك» — بالترتيب المعروض
nonisolated enum AdminReviewTileKind: String, CaseIterable, Hashable {
    case issues, problems, death, photos, married, living, gaps, notOpened, inactive

    /// الاسم القصير تحت الرقم
    var title: String {
        switch self {
        case .issues:    return L10n.t("المكرر والأخطاء", "Duplicates & errors")
        case .problems:  return L10n.t("مشكلات الشجرة", "Tree problems")
        case .death:     return L10n.t("تواريخ وفاة ناقصة", "Missing death dates")
        case .photos:    return L10n.t("مسجّلون بلا صورة", "Registered, no photo")
        case .married:   return L10n.t("متزوجة بلا زوج مربوط", "Married, no husband linked")
        case .living:    return L10n.t("هل ما زالوا أحياء؟", "Still alive?")
        case .gaps:      return L10n.t("بيانات ناقصة", "Missing data")
        case .notOpened: return L10n.t("لم يفتحوا التطبيق", "Never opened the app")
        case .inactive:  return L10n.t("غائبون 21 يوماً", "Away 21+ days")
        }
    }

    /// رمز SF في مربّع الأيقونة
    var icon: String {
        switch self {
        case .issues:    return "arrow.left.arrow.right"
        case .problems:  return "exclamationmark"
        case .death:     return "moon.fill"
        case .photos:    return "person.crop.circle.badge.exclamationmark"
        case .married:   return "figure.stand.dress"
        case .living:    return "heart.text.square.fill"
        case .gaps:      return "list.bullet.clipboard.fill"
        case .notOpened: return "iphone.slash"
        case .inactive:  return "clock.arrow.circlepath"
        }
    }
}

nonisolated enum AdminReviewTilesLogic {
    /// ثلاثة في كل صف (اختيار المالك «ب»)
    static let columns = 3

    /// المربّعات الظاهرة بترتيبها — «متزوجة بلا زوج مربوط» لمن يرى شجرة النساء في «العائلة» (المالك والمدير)
    static func kinds(seesWomen: Bool) -> [AdminReviewTileKind] {
        AdminReviewTileKind.allCases.filter { $0 != .married || seesWomen }
    }

    /// لون الرقم: بلون المربّع حين فيه أحد، ورمادي حين صفر أو قبل وصول الرقم
    enum NumberTone: Equatable { case tinted, grey }

    static func tone(_ count: Int?) -> NumberTone {
        guard let count, count > 0 else { return .grey }
        return .tinted
    }

    /// «17» · «2,177» · «0» · «—» قبل وصوله
    static func text(_ count: Int?) -> String {
        guard let count else { return AdminStoreHealthText.placeholder }
        return AdminNumberText.grouped(max(0, count))
    }

    /// المربّع يفتح صفحته: فيه أحد، أو لم يصل رقمه بعد (الصفحة تعدّ بنفسها) — الصفر لا يفتح شيئاً
    static func opens(_ count: Int?) -> Bool {
        guard let count else { return true }
        return count > 0
    }

    /// مربّع «✓ الباقي سليم» يملأ فراغ آخر صفّ (واحد فقط، وحين يكون فراغ) — وبعد وصول كل الأرقام فقط (`allArrived`):
    /// لا «سليم» أثناء التحميل ولا ورقم ما زال «—»
    static func showsFiller(tileCount: Int, columns: Int = columns, allArrived: Bool = true) -> Bool {
        guard allArrived, columns > 1, tileCount > 0 else { return false }
        return tileCount % columns != 0
    }

    /// «المكرر والأخطاء» في مربّعه: الأسماء المكررة والأرقام بدون أسماء — مشكلات الشجرة والمتزوجات لهما مربّعاهما
    static func issuesCount(duplicates: Int, nameless: Int) -> Int { duplicates + nameless }
}

#if !ADMIN_LOGIC_TEST

extension AdminReviewTileKind {
    /// تعبئة مربّع الأيقونة (رمز أبيض) — عائلة الكحلي والذهبي حسب المعنى
    var fill: Color {
        switch self {
        case .issues:    return DS.Color.goldFill
        case .problems:  return DS.Color.errorFill
        case .death:     return DS.Color.saduFill
        case .photos:    return DS.Color.seaFill
        case .married:   return DS.Color.femaleFill
        case .living:    return DS.Color.palmFill
        case .gaps:      return DS.Color.navyFill
        case .notOpened: return DS.Color.slateFill
        case .inactive:  return DS.Color.slateFill
        }
    }

    /// لون الرقم (مقروء على الأبيض والأسود)
    var ink: Color {
        switch self {
        case .issues:    return DS.Color.accent
        case .problems:  return DS.Color.error
        case .death:     return DS.Color.sadu
        case .photos:    return DS.Color.sea
        case .married:   return DS.Color.female
        case .living:    return DS.Color.palm
        case .gaps:      return DS.Color.primary
        case .notOpened: return DS.Color.slate
        case .inactive:  return DS.Color.slate
        }
    }

    /// قائمة «يحتاج مراجعتك» وراء المربّع (nil = «المكرر والأخطاء» / «متزوجة» — صفحة المكرر)
    var hubList: AdminReviewHubLogic.List? {
        switch self {
        case .problems:  return .problems
        case .death:     return .death
        case .photos:    return .photos
        case .living:    return .living
        case .gaps:      return .gaps
        case .notOpened: return .notOpened
        case .inactive:  return .inactive
        case .issues, .married: return nil
        }
    }

    /// الصفحة الموجودة التي يفتحها
    func page() -> AnyView {
        switch self {
        case .issues, .married: return AnyView(AdminIssuesPage())
        case .death:            return AnyView(DeathDatesCampaignPage())
        case .photos:           return AnyView(AdminPhotoNudgePage())
        default:
            guard let review = hubList?.review else { return AnyView(EmptyView()) }
            return AnyView(AdminReviewListPage(review: review, branchSet: nil))
        }
    }
}

/// شبكة «يحتاج مراجعتك»: عنوانها الصغير ثم المربّعات
struct AdminReviewTilesSection: View {
    /// عدد كل مربّع — nil = لم يصل بعد («—» رمادي)
    let counts: [AdminReviewTileKind: Int]
    let kinds: [AdminReviewTileKind]
    @Environment(\.dynamicTypeSize) private var typeSize
    /// الفتح «يتوسّع» من المربّع (طلب المالك ٢٠٢٦-١١-٢٨ — `adminZoomSource`/`adminZoomDestination`، iOS 18)
    @Namespace private var zoom

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: AdminAreaGroup.review.title)
            if typeSize.isAccessibilitySize {
                // صفوف بعرض الصفحة — لا قصّ للاسم الطويل
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(kinds, id: \.self) { kind in tile(kind, row: true) }
                }
            } else {
                let columns = typeSize >= .xxxLarge ? 2 : AdminReviewTilesLogic.columns
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm, alignment: .top),
                                         count: columns),
                          spacing: DS.Spacing.sm) {
                    ForEach(kinds, id: \.self) { kind in tile(kind, row: false) }
                    if AdminReviewTilesLogic.showsFiller(tileCount: kinds.count, columns: columns,
                                                         allArrived: kinds.allSatisfy { counts[$0] != nil }) {
                        AdminReviewFillerTile()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func tile(_ kind: AdminReviewTileKind, row: Bool) -> some View {
        let count = counts[kind]
        let face = AdminReviewTileFace(kind: kind, count: count, row: row)
        let spoken = "\(kind.title): \(count == nil ? AdminStoreHealthText.loading : AdminReviewTilesLogic.text(count))"
        if AdminReviewTilesLogic.opens(count) {
            NavigationLink {
                AdminLazyPage { AnyView(kind.page().adminBackTitle(AdminArea.family.title).adminArea(.family)) }
                    .adminZoomDestination(kind, in: zoom)
            } label: { face.adminZoomSource(kind, in: zoom) }
            .buttonStyle(AdminTilePressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: spoken))
            .accessibilityHint(L10n.t("يفتح القائمة", "Opens the list"))
            .accessibilityAddTraits(.isButton)
        } else {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: spoken))
        }
    }
}

/// وجه المربّع: مربّع الأيقونة · الرقم الكبير بلون المربّع (رمادي للصفر) · الاسم القصير — كل مربّعات الصف بطول واحد
private struct AdminReviewTileFace: View {
    let kind: AdminReviewTileKind
    let count: Int?
    /// من أحجام إمكانية الوصول: صفّ (الأيقونة · الاسم · الرقم)
    let row: Bool

    var body: some View {
        let tinted = AdminReviewTilesLogic.tone(count) == .tinted
        let number = Text(verbatim: AdminReviewTilesLogic.text(count))
            .dsFont(.hubKPI)
            .monospacedDigit()
            .foregroundColor(tinted ? kind.ink : DS.Color.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        let title = Text(kind.title)
            .dsFont(.hubLabel)
            .foregroundColor(DS.Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        Group {
            if row {
                HStack(spacing: DS.Spacing.md) {
                    icon
                    title.frame(maxWidth: .infinity, alignment: .leading)
                    number
                }
                .padding(DS.Hub.cardPadding)
            } else {
                VStack(spacing: DS.Spacing.xs) {
                    icon
                    number
                    title.multilineTextAlignment(.center)
                }
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous).fill(DS.Color.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous)
            .strokeBorder(DS.Color.textPrimary.opacity(DS.Opacity.cardStroke), lineWidth: DS.Border.width))
        .contentShape(RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous))
    }

    private var icon: some View {
        Image(systemName: kind.icon)
            .dsGlyph(DS.Glyph.md, weight: .semibold)
            .foregroundColor(DS.Color.textOnPrimary)
            .frame(width: DS.Icon.row, height: DS.Icon.row)
            .background(RoundedRectangle(cornerRadius: DS.Hub.tileIconRadius, style: .continuous).fill(kind.fill))
            .accessibilityHidden(true)
    }
}

/// «✓ الباقي سليم» — مربّع هادئ يملأ فراغ آخر صفّ (بلا إطار ممتلئ ولا ضغطة)
private struct AdminReviewFillerTile: View {
    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            Image(systemName: "checkmark")
                .dsGlyph(DS.Glyph.sm, weight: .semibold)
            Text(L10n.t("الباقي سليم", "The rest is fine"))
                .dsFont(.hubLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(DS.Color.textTertiary)
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous)
            .strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke),
                          style: StrokeStyle(lineWidth: DS.Border.width, dash: [DS.Spacing.xs])))
        .accessibilityElement(children: .combine)
    }
}

#endif
