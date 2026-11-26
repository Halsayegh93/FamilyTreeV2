import Foundation
#if !ADMIN_LOGIC_TEST
import SwiftUI
#endif

// MARK: - «يحتاج مراجعتك» صفحةً (إعادة تصميم الإدارة U12 — spec C.8)
//
// صفّ واحد في جذر «العائلة» (U11) يفتح هذه الصفحة: كل قوائم المراجعة بعددها في بطاقتين — «الشجرة والبيانات» (مشكلات في
// الشجرة · هل ما زالوا أحياء؟ · تواريخ وفاة ناقصة · بيانات ناقصة) و«الحسابات» (لم يفتحوا التطبيق بعد · لم يدخلوا منذ 21
// يوماً · مسجّلون بلا صورة — F4/V13). كل صفّ يفتح قائمته (`AdminReviewListPage(review:)`)، و«تواريخ وفاة ناقصة» بيتها الواحد `DeathDatesCampaignPage`
// (spec E.19). الرقم في الصفّ = أول رقم في القائمة التي يفتحها (T2): نفس `AdminMemberReview.rows`، وتواريخ الوفاة من
// `DeathDatesCampaign` (رقم صفحتها نفسها). الصفر رمادي «0» بلا سهم وسطره «لا شيء»؛ قبل وصول الأرقام «—» والصفّ يُضغط.
//
// الجزء الأول منطق خالص (Foundation) يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u12-logic FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminReviewHubPage.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminWomenPanel.swift tests/admin-redesign/U12/main.swift && /tmp/u12-logic

// MARK: - المنطق الخالص

nonisolated enum AdminReviewHubLogic {
    /// قوائم الصفحة بترتيبها (نفس قيم `AdminMemberReview`)
    /// F4 (V13): «مسجّلون بلا صورة» (P1) قائمة سابعة — تدخل «سليمة» و«N قوائم» وكلمة «اليوم» وإخفاء البطاقة مثل
    /// غيرها، بنفس قاعدة قائمتها (`AdminPhotoNudgeList.rows`)
    enum List: String, CaseIterable, Hashable {
        case problems, living, death, gaps, notOpened, inactive, photos

        /// قوائم «الحسابات» — أرقامها تنتظر قوائم الحسابات (`AdminAccountsStore`)
        var isUsage: Bool { self == .notOpened || self == .inactive || self == .photos }

        /// نصّ الصفّ (spec C.8)
        var title: String {
            switch self {
            case .problems:  return L10n.t("مشكلات في الشجرة", "Tree problems")
            case .living:    return L10n.t("هل ما زالوا أحياء؟", "Still alive?")
            case .death:     return L10n.t("تواريخ وفاة ناقصة", "Missing death dates")
            case .gaps:      return L10n.t("بيانات ناقصة", "Missing data")
            case .notOpened: return L10n.t("لم يفتحوا التطبيق بعد", "Haven't opened the app yet")
            case .inactive:  return L10n.t("لم يدخلوا منذ 21 يوماً", "Away for 21+ days")
            case .photos:    return L10n.t("مسجّلون بلا صورة", "Registered, no photo")
            }
        }

        /// صيغ العدد والمعدود لسطر بطاقة «العائلة» الأول (V22) — nil = العنوان كما هو بعد الرقم
        var forms: AdminCountForms? {
            switch self {
            case .problems:
                return AdminCountForms(one: "مشكلة واحدة في الشجرة", two: "مشكلتان في الشجرة", few: "مشكلات في الشجرة",
                                       many: "مشكلةً في الشجرة", single: "مشكلة في الشجرة")
            case .death:
                return AdminCountForms(one: "تاريخ وفاة واحد ناقص", two: "تاريخا وفاة ناقصان", few: "تواريخ وفاة ناقصة",
                                       many: "تاريخ وفاة ناقصاً", single: "تاريخ وفاة ناقص")
            case .photos:
                return AdminCountForms(one: "مسجّل واحد بلا صورة", two: "مسجّلان بلا صورة", few: "مسجّلين بلا صورة",
                                       many: "مسجّلاً بلا صورة", single: "مسجّل بلا صورة")
            case .living, .gaps, .notOpened, .inactive:
                return nil
            }
        }
    }

    /// F4 (V30): مفتاح ذاكرة أعداد القوائم في «اليوم» — فئة استخدام كل حساب (لا عددها وحده: عضو انتقل من «نشط» إلى
    /// «غير نشط» لا يغيّر العدد ويغيّر القوائم). `A` = فئة الحساب (`AppUsageCategory` في التطبيق)
    struct CacheKey<A: Equatable>: Equatable {
        let membersVersion: Int
        let members: Int
        let accountsLoaded: Bool
        let accounts: [UUID: A]
        let daughterSons: Set<UUID>
        let verified: Set<UUID>
    }

    /// بطاقتا الصفحة
    static let treeAndData: [List] = [.problems, .living, .death, .gaps]
    static let accounts: [List] = [.notOpened, .inactive, .photos]

    /// شكل الرقم في طرف الصفّ
    struct Look: Equatable {
        /// «41»، «2,177»، «0» أو «—»
        let text: String
        /// رمادي: الصفر، وقبل وصول الرقم
        let dim: Bool
        /// يفتح القائمة (سهم + ضغطة) — الصفر لا يفتح شيئاً
        let opens: Bool
        /// القائمة فارغة: سطر «لا شيء» بدل الشرح
        let isEmpty: Bool
    }

    /// nil = لم يصل الرقم: «—» رمادي والصفّ يبقى يُضغط (spec C.8)
    static func look(_ count: Int?) -> Look {
        guard let count else { return Look(text: AdminStoreHealthText.placeholder, dim: true, opens: true, isEmpty: false) }
        if count <= 0 { return Look(text: "0", dim: true, opens: false, isEmpty: true) }
        return Look(text: AdminNumberText.grouped(count), dim: false, opens: true, isEmpty: false)
    }

    /// صفّ «يحتاج مراجعتك» في جذر «العائلة» يختفي حين تصل كل القوائم صفراً (لا قبل وصولها) — المفتاح الغائب = لم يصل
    static func isAllClear(_ counts: [List: Int]) -> Bool {
        List.allCases.allSatisfy { counts[$0] == 0 }
    }

    /// سطر الصفّ في جذر «العائلة»: أول قائمتين فيهما أحد، ثم «و4 قوائم» للباقي («هل ما زالوا أحياء؟ · بيانات ناقصة · و4
    /// قوائم»). nil = لا قائمة فيها أحد بعد
    static func summary(_ counts: [List: Int], order: [List] = treeAndData + accounts) -> String? {
        let busy = order.filter { (counts[$0] ?? 0) > 0 }
        guard !busy.isEmpty else { return nil }
        var parts = busy.prefix(2).map(\.title)
        let rest = busy.count - 2
        if rest > 0 { parts.append(moreLists(rest)) }
        return parts.joined(separator: " · ")
    }

    /// «وقائمة أخرى» · «وقائمتان» · «و4 قوائم» · «و11 قائمةً»
    static func moreLists(_ n: Int) -> String {
        switch n {
        case 1:  return L10n.t("وقائمة أخرى", "and 1 more list")
        case 2:  return L10n.t("وقائمتان", "and 2 more lists")
        default:
            let few = (3...10).contains(n % 100)
            return L10n.t(few ? "و\(n) قوائم" : "و\(n) قائمةً", "and \(n) more lists")
        }
    }
}

#if !ADMIN_LOGIC_TEST

// MARK: - الأرقام (المصدر الواحد — الصفحة وصفّ «العائلة» يقرآن منه)

extension AdminReviewHubLogic.List {
    /// القائمة التي يفتحها الصفّ — «تواريخ وفاة ناقصة» بيتها `DeathDatesCampaignPage` (`AdminReviewListPage(.death)`
    /// يحوّل إليها أيضاً)
    /// nil = «مسجّلون بلا صورة» (بيتها `AdminPhotoNudgePage`، لا قائمة مراجعة)
    var review: AdminMemberReview? {
        switch self {
        case .problems:  return .problems
        case .living:    return .living
        case .death:     return .death
        case .gaps:      return .gaps
        case .notOpened: return .notOpened
        case .inactive:  return .inactive
        case .photos:    return nil
        }
    }

    /// الشرح تحت العنوان (سطر ١٣ رمادي)
    var subtitle: String { review?.subtitle ?? AdminPhotoNudgeList.subtitle }

    var icon: String { review?.icon ?? AdminPhotoNudgeList.icon }

    /// لون مربّع الأيقونة: «الشجرة والبيانات» بلون قسم «العائلة»، و«الحسابات» بلون التواصل — لا أحمر ولا كهرماني لقائمة
    /// (الكلمات الهادئة، spec A.0)
    var tint: Color { isUsage ? DS.Color.sea : DS.Color.palm }
}

@MainActor
enum AdminReviewHubCounts {
    /// عدد كل قائمة — المفتاح الغائب = لم يصل بعد («—»). نفس ما تعدّه صفحة كل قائمة (T2)
    /// - photos: من ينظر (قاعدة «مسجّلون بلا صورة» تستثنيه والمالك لغير المالك) — nil = لا يُحسب (القائمة غائبة فلا «سليمة»)
    static func make(index: AdminMembersIndex, verified: Set<UUID>,
                     members: [FamilyMember], photos: PhotoNudgeLogic.Viewer? = nil) -> [AdminReviewHubLogic.List: Int] {
        guard index.built else { return [:] }
        var out: [AdminReviewHubLogic.List: Int] = [:]
        for list in AdminReviewHubLogic.List.allCases {
            switch list {
            case .death:
                // رقم صفحة «تواريخ الوفاة» نفسه (نطاق «ذكرى الراحلين»، بلا «غير معروف»)
                out[list] = DeathDatesCampaign.stats(members).incomplete
            case .photos:
                // نفس قاعدة القائمة وعددها (`AdminPhotoNudgeList.rows`) — nil قبل وصول الحسابات
                if let photos, let rows = AdminPhotoNudgeList.rows(in: index, viewer: photos) { out[list] = rows.count }
            case .notOpened, .inactive:
                if index.accountsReady, let review = list.review { out[list] = review.rows(in: index, verified: verified).count }
            default:
                if let review = list.review { out[list] = review.rows(in: index, verified: verified).count }
            }
        }
        return out
    }
}

// MARK: - الصفحة

struct AdminReviewHubPage: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    @ObservedObject private var sons = DaughterSonsIndex.shared
    @ObservedObject private var verified = AdminLivingVerifiedStore.shared

    @State private var index = AdminMembersIndex.empty
    @State private var counts: [AdminReviewHubLogic.List: Int] = [:]

    init() {}

    static var title: String { L10n.t("يحتاج مراجعتك", "Needs your review") }

    // حارس المكدس: الصفحة نوع واحد والمحتوى خلف `AnyView`
    var body: some View {
        AdminPage(header: header, content: AnyView(content))
            .adminArea(.family)
            .refreshable { await reload(force: true) }
            .task { await reload(force: false) }
            .onChange(of: memberVM.membersVersion) { _ in rebuild() }
            .onChange(of: accounts.accounts) { _ in rebuild() }
            .onChange(of: accounts.loaded) { _ in rebuild() }
            .onChange(of: sons.ids) { _ in rebuild() }
            .onChange(of: verified.ids) { _ in rebuild() }
            .debugStackProbe("AdminReviewHubPage")
    }

    private var canEdit: Bool { authVM.canEditMembers && authVM.adminCanEdit(.family) }

    private var header: AdminPageHeader {
        AdminPageHeader(title: Self.title,
                        subtitle: L10n.t("قوائم تحتاج قراراً منك", "Lists that need a decision from you"),
                        readOnly: !authVM.adminCanEdit(.family))
    }

    private func reload(force: Bool) async {
        verified.activate(user: authVM.currentUser?.id)
        if memberVM.allMembers.isEmpty || force { await memberVM.fetchAllMembers(force: force) }
        rebuild()
        await sons.refresh()
        await accounts.refresh(force: force)
        rebuild()
    }

    private func rebuild() {
        let names = appSettingsVM
        let built = AdminMembersIndex.build(members: memberVM.allMembers, accounts: accounts.accounts,
                                            accountsReady: accounts.loaded, daughterSons: sons.ids,
                                            branchName: { names.branchName(for: $0) })
        index = built
        counts = AdminReviewHubCounts.make(index: built, verified: verified.ids, members: memberVM.allMembers,
                                           photos: .init(authVM: authVM))
    }

    // MARK: المحتوى

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Hub.sectionGap) {
            if memberVM.membersLoadFailed && memberVM.allMembers.isEmpty {
                AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                                          message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                          retry: { Task { await reload(force: true) } }))
            } else {
                AnyView(section(L10n.t("الشجرة والبيانات", "Tree and data"), AdminReviewHubLogic.treeAndData))
                // «مسجّلون بلا صورة» قائمة سابعة في «الحسابات» (F4، V13) ← `AdminPhotoNudgePage`
                AnyView(section(L10n.t("الحسابات", "Accounts"), AdminReviewHubLogic.accounts))
                if counts.count == AdminReviewHubLogic.List.allCases.count,
                   AdminReviewHubLogic.isAllClear(counts) {
                    Text(L10n.t("كل القوائم فارغة الآن — لا شيء ينتظرك.", "Every list is empty right now — nothing is waiting for you."))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// عنوان ١٥ ثم بطاقة صفوفها مفصولة بخط يبدأ من النص (spec A.4/A.5)
    private func section(_ title: String, _ lists: [AdminReviewHubLogic.List]) -> some View {
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: title)
            AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                ForEach(lists, id: \.self) { list in
                    row(list)
                }
            }
        }
    }

    /// صفّ قائمة: مربّع الأيقونة · العنوان والشرح (أو «لا شيء») · الرقم ١٥ شبه عريض · السهم إن فتح شيئاً
    private func row(_ list: AdminReviewHubLogic.List) -> some View {
        let look = AdminReviewHubLogic.look(counts[list])
        let subtitle = look.isEmpty ? L10n.t("لا شيء", "Nothing") : list.subtitle
        let face = AdminListRow(icon: list.icon, tint: list.tint, title: list.title, subtitle: subtitle,
                                showsChevron: look.opens) {
            AdminRowValue(text: look.text, tint: look.dim ? DS.Color.textTertiary : DS.Color.textPrimary)
        }
        let spoken: String = {
            if look.isEmpty { return L10n.t("\(list.title): لا شيء", "\(list.title): nothing") }
            if look.text == AdminStoreHealthText.placeholder {
                return L10n.t("\(list.title): \(AdminStoreHealthText.loading)", "\(list.title): \(AdminStoreHealthText.loading)")
            }
            return L10n.t("\(list.title): \(look.text)", "\(list.title): \(look.text)")
        }()
        return AdminTapWrap(tap: look.opens ? destination(list) : .none, feel: .row, label: AnyView(face),
                            accessibilityLabel: spoken)
            .accessibilityHint(look.opens ? L10n.t("يفتح القائمة", "Opens the list") : "")
    }

    /// الوجهة خلف `AdminLazyPage` (`AdminTapWrap` يغلّفها ويمرّر «رجوع» = «يحتاج مراجعتك» والقسم)
    private func destination(_ list: AdminReviewHubLogic.List) -> AdminPageTap {
        if list == .death {
            return .page { AnyView(DeathDatesCampaignPage()) }
        }
        guard let review = list.review else { return .page { AnyView(AdminPhotoNudgePage()) } }
        return .page { AnyView(AdminReviewListPage(review: review, branchSet: nil)) }
    }
}

#endif
