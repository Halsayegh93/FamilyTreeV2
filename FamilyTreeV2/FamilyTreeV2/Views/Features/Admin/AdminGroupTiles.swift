import Foundation
#if !ADMIN_LOGIC_TEST
import SwiftUI
#endif

// MARK: - مجموعات الأقسام مربّعات (طلب المالك ٢٠٢٦-١١-٢٨ «المجموعات بشكل مربعات» — `app-review/inbox/group-tiles.png`)
//
// في «التطبيق والنظام» و«الإحصاءات» و«الفريق والصلاحيات» كل مجموعة مربّع، ثلاثة في كل صف، بشكل «يحتاج مراجعتك» نفسه:
// مربّع أيقونة ملوّن · رقم حيّ اختياري بلون المربّع · الاسم · سطر حال قصير. الضغط يفتح صفحة المجموعة وفيها ما كانت تعرضه
// المجموعة نفسه (المفاتيح والصفوف والرسوم) — لا ينتقل إعداد إلى بيت آخر ولا يتغيّر منطق. المجموعة التي هي باب واحد إلى صفحة
// موجودة (رسائل رمز الدخول، الأجهزة، الأخطاء، فريق الإدارة، التسجيل والمنع) يفتح مربّعها تلك الصفحة نفسها (بلا صفحة وسيطة
// فيها صفّ واحد). فراغ آخر صفّ يبقى فارغاً.
// الفتح «يتوسّع» من المربّع (طلب المالك «تفتح بشكل يتوسع»): انتقال التكبير في iOS 18 (`matchedTransitionSource` على المربّع،
// `navigationTransition(.zoom)` على الوجهة) داخل المكدس نفسه وخلف `AdminLazyPage` (حارس المكدس)؛ قبل iOS 18 دفع عادي.
// «تقليل الحركة» يتولاه النظام، والرجوع بالسحب من الطرف يعمل كما هو.
//
// المنطق الخالص (أيّ المربّعات لكل دور وبأي ترتيب، وجملة القارئ الصوتي) يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/gt1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminGroupTiles.swift tests/admin-redesign/GT1/main.swift && /tmp/gt1-logic

/// مربّعات «التطبيق والنظام» بالترتيب المعتمد (الأقسام الظاهرة ← القوائم ← التشغيل ← النظام، و«قواعد الأعضاء» تحت
/// «الأقسام الظاهرة»، وبطاقة «النظام» مقسومة إلى أبوابها)
nonisolated enum AdminAppTile: String, CaseIterable, Hashable {
    case visible, rules, lists, operations, sms, devices, errors, system

    var title: String {
        switch self {
        case .visible:    return L10n.t("الأقسام الظاهرة", "Visible sections")
        case .rules:      return L10n.t("قواعد الأعضاء", "Member rules")
        case .lists:      return L10n.t("القوائم", "Lists")
        case .operations: return L10n.t("التشغيل", "Operations")
        case .sms:        return L10n.t("رسائل رمز الدخول", "Sign-in code messages")
        case .devices:    return L10n.t("الأجهزة والإشعارات", "Devices and notifications")
        case .errors:     return L10n.t("الأخطاء", "Errors")
        case .system:     return L10n.t("النظام", "System")
        }
    }

    var icon: String {
        switch self {
        case .visible:    return "rectangle.on.rectangle"
        case .rules:      return "checklist"
        case .lists:      return "list.bullet.rectangle.fill"
        case .operations: return "gearshape.fill"
        case .sms:        return "ellipsis.message.fill"
        case .devices:    return "iphone"
        case .errors:     return "exclamationmark.triangle.fill"
        case .system:     return "info.circle.fill"
        }
    }

    /// صفحة مجموعة (المفاتيح داخلها) — أو باب إلى صفحة موجودة (false)
    var isGroupPage: Bool {
        switch self {
        case .visible, .rules, .lists, .operations, .system: return true
        case .sms, .devices, .errors: return false
        }
    }
}

/// مربّعات «الإحصاءات» تحت أرقام «العائلة» الثلاثة: كل قسم من أقسام الصفحة مربّع، و«الاستخدام» بعد «في التطبيق» كما كان
nonisolated enum AdminStatsTile: Hashable {
    case section(AdminStatsAnchor)
    case usage

    /// مفتاح ثابت (مفتاح انتقال التكبير ومعرّف التمرير)
    var key: String {
        switch self {
        case .section(let anchor): return "stats." + anchor.rawValue
        case .usage:               return "stats.usage"
        }
    }
}

/// مربّعات «الفريق والصلاحيات»: «الفريق» (فريق الإدارة) ثم «الأعضاء» (صلاحيات الأعضاء · التسجيل والمنع)
nonisolated enum AdminTeamTile: String, CaseIterable, Hashable {
    case team, memberAccess, registration

    var title: String {
        switch self {
        case .team:         return L10n.t("فريق الإدارة", "Admin team")
        case .memberAccess: return L10n.t("صلاحيات الأعضاء", "Member permissions")
        case .registration: return L10n.t("التسجيل والمنع", "Sign-up and blocking")
        }
    }

    var icon: String {
        switch self {
        case .team:         return "star.fill"
        case .memberAccess: return "person.2.badge.key.fill"
        case .registration: return "person.badge.plus"
        }
    }
}

nonisolated enum AdminGroupTilesLogic {
    /// ثلاثة في كل صف (كـ«يحتاج مراجعتك»)
    static let columns = 3

    /// «التطبيق والنظام» (للمالك — بوابة القسم): رسائل رمز الدخول والأجهزة بخانتيهما في جدول الأدوار كما كانتا في «النظام»
    static func appTiles(seesSms: Bool, seesDevices: Bool) -> [AdminAppTile] {
        AdminAppTile.allCases.filter { tile in
            switch tile {
            case .sms:     return seesSms
            case .devices: return seesDevices
            default:       return true
            }
        }
    }

    /// «الإحصاءات»: أقسام الصفحة الظاهرة لدورك (`AdminStatsLogic.sections`) بلا «العائلة» (أرقامها الثلاثة فوق المربّعات)،
    /// و«الاستخدام» (`team.usage`) بعد «في التطبيق» — وأولها حين لا يُرى «في التطبيق»
    static func statsTiles(shown: [AdminStatsAnchor], seesUsage: Bool) -> [AdminStatsTile] {
        var list: [AdminStatsTile] = []
        if seesUsage && !shown.contains(.inApp) { list.append(.usage) }
        for anchor in shown where anchor != .family {
            list.append(.section(anchor))
            if anchor == .inApp && seesUsage { list.append(.usage) }
        }
        return list
    }

    /// «الفريق والصلاحيات»: فريق الإدارة (`team.members`) · صلاحيات الأعضاء (المالك وحده) · التسجيل والمنع
    /// (`team.registration`)
    static func teamTiles(seesTeam: Bool, isOwner: Bool, seesRegistration: Bool) -> [AdminTeamTile] {
        AdminTeamTile.allCases.filter { tile in
            switch tile {
            case .team:         return seesTeam
            case .memberAccess: return isOwner
            case .registration: return seesRegistration
            }
        }
    }

    /// جملة القارئ الصوتي: «الاسم، الرقم، الحال» (و«زر» من سمة الزرّ)
    static func spoken(title: String, number: String?, status: String?) -> String {
        [title, number, status]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: L10n.t("، ", ", "))
    }
}

#if !ADMIN_LOGIC_TEST

// MARK: - المربّع

/// لون سطر الحال تحت الاسم
enum AdminGroupStatusTone: Hashable { case plain, ok, warn, error }

/// مربّع مجموعة: ما يرسمه وما يفتحه
struct AdminGroupTileItem: Identifiable {
    /// مفتاح ثابت (مفتاح انتقال التكبير والقائمة)
    let id: String
    let title: String
    let icon: String
    /// تعبئة مربّع الأيقونة (رمز أبيض)
    let fill: Color
    /// لون الرقم (مقروء على الأبيض والأسود)
    var ink: Color = DS.Color.primary
    /// الرقم الحيّ — nil = بلا سطر رقم
    var number: String? = nil
    /// سطر الحال القصير — nil = الاسم وحده
    var status: String? = nil
    var tone: AdminGroupStatusTone = .plain
    /// اسم القسم للرجوع، والقسم الذي تتبعه الصفحة
    let backTitle: String
    let area: AdminArea
    /// الصفحة — تُبنى عند الفتح فقط (`AdminLazyPage`)
    let page: () -> AnyView
}

/// شبكة مربّعات المجموعات (ثلاثة في الصف، عمودان مع XXXL، وصفوف بعرض الصفحة من أحجام إمكانية الوصول). كل مربّع يفتح
/// صفحته بانتقال التكبير من المربّع نفسه
struct AdminGroupTilesSection: View {
    /// عنوان صغير فوق الشبكة — nil = بلا عنوان
    var title: String? = nil
    let items: [AdminGroupTileItem]
    @Namespace private var zoom
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            if let title { AdminSectionLabel(title: title) }
            if typeSize.isAccessibilitySize {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(items) { item in tile(item, row: true) }
                }
            } else {
                let columns = typeSize >= .xxxLarge ? 2 : AdminGroupTilesLogic.columns
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm, alignment: .top),
                                         count: columns),
                          spacing: DS.Spacing.sm) {
                    ForEach(items) { item in tile(item, row: false) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(_ item: AdminGroupTileItem, row: Bool) -> some View {
        NavigationLink {
            AdminLazyPage { AnyView(item.page().adminBackTitle(item.backTitle).adminArea(item.area)) }
                .adminZoomDestination(item.id, in: zoom)
        } label: {
            AdminGroupTileFace(item: item, row: row)
                .adminZoomSource(item.id, in: zoom)
        }
        .buttonStyle(AdminTilePressStyle())
        .id(item.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: AdminGroupTilesLogic.spoken(title: item.title, number: item.number,
                                                                      status: item.status)))
        .accessibilityAddTraits(.isButton)
    }
}

/// وجه المربّع — شكل «يحتاج مراجعتك» (`AdminReviewTileFace`): مربّع الأيقونة · الرقم بلون المربّع · الاسم (سطران على
/// الأكثر) · سطر الحال. كل مربّعات الصف بطول واحد
private struct AdminGroupTileFace: View {
    let item: AdminGroupTileItem
    /// من أحجام إمكانية الوصول: صفّ (الأيقونة · الاسم والحال · الرقم)
    let row: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous)
        Group {
            if row {
                HStack(spacing: DS.Spacing.md) {
                    icon
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        title
                        status
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    number
                }
                .padding(DS.Hub.cardPadding)
            } else {
                VStack(spacing: DS.Spacing.xs) {
                    icon
                    number
                    title
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    status
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity)
        .background(shape.fill(DS.Color.cardBackground))
        .overlay(shape.strokeBorder(DS.Color.textPrimary.opacity(DS.Opacity.cardStroke), lineWidth: DS.Border.width))
        .contentShape(shape)
    }

    private var icon: some View {
        Image(systemName: item.icon)
            .dsGlyph(DS.Glyph.md, weight: .semibold)
            .foregroundColor(DS.Color.textOnPrimary)
            .frame(width: DS.Icon.row, height: DS.Icon.row)
            .background(RoundedRectangle(cornerRadius: DS.Hub.tileIconRadius, style: .continuous).fill(item.fill))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var number: some View {
        if let value = item.number {
            Text(verbatim: value)
                .dsFont(.hubKPI)
                .monospacedDigit()
                .foregroundColor(value == AdminStoreHealthText.placeholder ? DS.Color.textTertiary : item.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var title: some View {
        Text(item.title)
            .dsFont(.hubLabel)
            .foregroundColor(DS.Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var status: some View {
        if let text = item.status, !text.isEmpty {
            Text(verbatim: text)
                .dsFont(.subtitle)
                .monospacedDigit()
                .foregroundColor(statusInk)
        }
    }

    private var statusInk: Color {
        switch item.tone {
        case .plain: return DS.Color.textSecondary
        case .ok:    return DS.Color.success
        case .warn:  return DS.Color.warning
        case .error: return DS.Color.error
        }
    }
}

// MARK: - صفحة المجموعة

private struct AdminGroupTitleKey: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    /// عنوان صفحة المجموعة المفتوحة من مربّعها — العنوان الصغير بالاسم نفسه داخلها لا يتكرّر (`AdminSectionLabel`)
    var adminGroupTitle: String? {
        get { self[AdminGroupTitleKey.self] }
        set { self[AdminGroupTitleKey.self] = newValue }
    }
}

/// صفحة مجموعة: الرأس الكحلي باسم المجموعة («‹ اسم القسم») ثم ما كانت المجموعة تعرضه
struct AdminGroupPage<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    /// سطر «للاطلاع» بقفل
    var badge: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        AdminHubPage {
            AdminBandHeader(title: title, subtitle: subtitle, badge: badge)
        } content: {
            content()
        }
        // ما يُدفع من الصفوف يرجع باسم المجموعة
        .environment(\.adminPageTitle, title)
        .environment(\.adminGroupTitle, title)
    }
}

// MARK: - الفتح «يتوسّع» من المربّع (iOS 18 — وإلا دفع عادي)

extension View {
    /// مصدر انتقال التكبير: المربّع نفسه بزاويته وخلفيته
    @ViewBuilder
    func adminZoomSource<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace) { source in
                source
                    .clipShape(RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous))
            }
        } else {
            self
        }
    }

    /// الوجهة تتوسّع من مصدرها وتنكمش إليه عند الرجوع
    @ViewBuilder
    func adminZoomDestination<ID: Hashable>(_ id: ID, in namespace: Namespace.ID, enabled: Bool = true) -> some View {
        if #available(iOS 18.0, *), enabled {
            self.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

#endif
