import SwiftUI

// MARK: - مكان «تواريخ الوفاة» في «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٤؛ إعادة التصميم U7 ٢٠٢٦-١١-٢٦ — spec C.1 البند ٣)
//
// مكان واحد تحت «الأقسام» بحالين (سطر واحد في `AdminDashboardView`):
//   • أثناء الحملة ولمن يعدّل الأعضاء (`canEditMembers`): عنوان «تواريخ الوفاة» ثم بطاقة — «134 متوفى بلا تاريخ كامل»
//     (١٧ شبه عريض)، شريط رفيع بالحبر (نسبة من له تاريخ كامل)، «لهم تاريخ كامل 3 من 367 … 1٪» ١٣ رمادي، وزرّ «أكمل
//     التواريخ ‹» — البطاقة كلها تفتح بيت الاستكمال الوحيد `DeathDatesCampaignPage` (spec E.19). الأرقام أرقام الحملة نفسها
//     (`DeathDatesCampaign.stats`) — فأول رقم في الصفحة («بلا تاريخ كامل») يساوي رقم البطاقة (T2).
//   • بعدها (موقوفة من السيرفر، انتهى آخر يوم، أو اكتملت التواريخ)، ولمن لا يعدّل الأعضاء: «ذكرى الراحلين» و«عرض الكل»
//     (← «المناسبات» على «ذكرى الراحلين»)، أقرب ذكريين (الاسم · «بعد 3 أيام»)، ثم «134 متوفى بلا تاريخ كامل ‹» (يفتح
//     الصفحة لمن يعدّل الأعضاء، وبلا سهم لغيره).
// كل بطاقة نوع مستقل خلف `AnyView`، وكل رابط خلف `AdminLazyPage` (حارس مكدس «اليوم» — ٧٢٠ ك.ب).

struct AdminDeathDatesSpot: View {
    /// «عرض الكل» ← «المناسبات» على «ذكرى الراحلين» (يمرّره «اليوم» بهبوطه) — nil = بلا رابط (القسم ليس لدورك)
    var openOccasions: (() -> Void)? = nil
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @ObservedObject private var store = DeathDatesCampaignStore.shared

    var body: some View {
        let loaded = !memberVM.allMembers.isEmpty
        let stats = DeathDatesCampaign.stats(memberVM.allMembers)
        // قبل وصول الأعضاء: بطاقة الحملة نفسها بلا أرقام («—») — لا قفز بين الحالين
        let campaign = authVM.canEditMembers && authVM.adminCanEdit(.family) && (!loaded || store.isActive(stats))
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            if campaign {
                AdminSectionLabel(title: DeathDatesCampaignPage.title)
                AnyView(DeathDatesCampaignCard(stats: loaded ? stats : nil, until: store.until))
            } else {
                AdminSectionLabel(title: L10n.t("ذكرى الراحلين", "Memorials"), link: allLink)
                AnyView(DeceasedMemorialSpotCard(incomplete: loaded ? stats.incomplete : nil))
            }
        }
        .task { await store.refresh() }
    }

    /// «عرض الكل ‹» في طرف العنوان
    private var allLink: AnyView? {
        guard let openOccasions else { return nil }
        return AnyView(Button(action: openOccasions) {
            AdminCardLinkLabel(title: L10n.t("عرض الكل", "See all"))
        }
        .buttonStyle(DSPressStyle())
        .accessibilityHint(L10n.t("يفتح المناسبات على ذكرى الراحلين", "Opens Occasions on the memorials")))
    }
}

/// صفحة الاستكمال الوحيدة خلف بوابة «العائلة» — رجوعها «الإدارة» (عنوان رأس «اليوم»)
private func deathDatesPage() -> AnyView {
    AnyView(AdminAreaGate(area: .family) { AnyView(DeathDatesCampaignPage()) }
        .adminArea(.family)
        .adminBackTitle(AdminArea.homeTitle))
}

/// «134 متوفى بلا تاريخ كامل» (متوفى واحد، متوفيان، 3 متوفين) — «—» قبل وصول الأعضاء
private func incompleteText(_ n: Int?) -> String {
    guard let n else { return L10n.t("— بلا تاريخ كامل", "— without a full date") }
    guard n > 0 else { return L10n.t("اكتملت التواريخ كلها", "Every date is complete") }
    return L10n.isArabic ? AdminCensusText.deceased(n) + " بلا تاريخ كامل"
                         : "\(AdminNumberText.grouped(n)) deceased without a full date"
}

// MARK: - «تواريخ الوفاة» (أثناء الحملة)

/// البطاقة: العدد عنواناً، شريط رفيع بالحبر، سطر «لهم تاريخ كامل N من M … ٪»، و«أكمل التواريخ ‹» — كلها رابط واحد
struct DeathDatesCampaignCard: View {
    /// nil = لم تصل الأعضاء
    let stats: DeathDatesStats?
    let until: Date?

    var body: some View {
        NavigationLink {
            AdminLazyPage { deathDatesPage() }
        } label: {
            AnyView(face)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint(L10n.t("يفتح صفحة تواريخ الوفاة", "Opens the death dates page"))
        .accessibilityAddTraits(.isButton)
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: incompleteText(stats?.incomplete))
                    .dsFont(.statValue)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let until {
                    Text(verbatim: L10n.t("الحملة حتى \(DeathDatesCampaignStore.untilText(until))",
                                          "Campaign until \(DeathDatesCampaignStore.untilText(until))"))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            // الشريط الرفيع (spec A.11 «Meter»): من له تاريخ كامل بالحبر فوق درجة أفتح منه
            DSMeterBar(progress: stats?.share, tint: DS.Chart.total, track: DS.Chart.inkTrack)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                Text(verbatim: progressText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DS.Spacing.sm)
                Text(verbatim: percentText)
            }
            .dsFont(.subtitle)
            .monospacedDigit()
            .foregroundColor(DS.Color.textTertiary)
            AdminPillLabel(title: L10n.t("أكمل التواريخ", "Complete the dates"),
                           icon: L10n.isArabic ? "chevron.left" : "chevron.right",
                           style: .soft, fullWidth: true, iconTrailing: true)
                .padding(.top, DS.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    /// «لهم تاريخ كامل 3 من 367 من الرجال» — العدد للرجال (شجرة العائلة) وحدهم، وبطاقة «الراحلون» تجمع الرجال ونساء
    /// العائلة، فيُذكر «من الرجال» صراحة حتى لا يُظنّ الرقمان متعارضين. العدد نفسه في رأس صفحة الحملة
    private var progressText: String {
        guard let s = stats else { return L10n.t("لهم تاريخ كامل — من —", "— of — have a full date") }
        let full = AdminNumberText.grouped(s.full)
        let need = AdminNumberText.grouped(s.full + s.incomplete)
        return L10n.t("لهم تاريخ كامل \(full) من \(need) من الرجال", "\(full) of \(need) men have a full date")
    }

    private var percentText: String {
        guard let percent = stats?.percent else { return AdminStoreHealthText.placeholder }
        return L10n.t("\(percent)٪", "\(percent)%")
    }

    private var spoken: String {
        [DeathDatesCampaignPage.title, incompleteText(stats?.incomplete), progressText]
            .joined(separator: L10n.t("، ", ", "))
    }
}

// MARK: - «ذكرى الراحلين» (بعد الحملة)

/// أقرب ذكريين خلال ٣٠ يوماً (الاسم · متى)، ثم من بقي بلا تاريخ كامل — يفتح صفحة الاستكمال لمن يعدّل الأعضاء
struct DeceasedMemorialSpotCard: View {
    /// nil = لم تصل الأعضاء
    let incomplete: Int?
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel

    private static let shown = 2

    var body: some View {
        let loaded = !memberVM.allMembers.isEmpty
        let board = loaded ? DeceasedMemorialBoard(memberVM.allMembers) : .empty
        VStack(alignment: .leading, spacing: 0) {
            if !loaded {
                // هيكل بشكل الصفّ النهائي (spec A.12) — لا «لا ذكرى» قبل وصول الأعضاء
                AdminListRow(icon: "leaf.fill", tint: DS.Color.sadu, title: L10n.t("المرحوم فلان الفلاني", "Late member"),
                             showsChevron: false)
                    .redacted(reason: .placeholder)
                    .accessibilityHidden(true)
            } else if board.upcoming.isEmpty {
                AdminListRow(icon: "leaf", tint: DS.Color.sadu,
                             title: L10n.t("لا ذكرى خلال 30 يوماً", "No memorial in the next 30 days"),
                             showsChevron: false)
            } else {
                ForEach(Array(board.upcoming.prefix(Self.shown).enumerated()), id: \.element.id) { index, u in
                    if index > 0 { AdminRowDivider(inset: AdminRowDivider.iconInset) }
                    AdminListRow(icon: "leaf.fill", tint: DS.Color.sadu,
                                 title: L10n.t("\(AdminOccasionsText.late(u.member)) \(u.member.shortFullName)",
                                               u.member.shortFullName),
                                 showsChevron: false) {
                        Text(verbatim: DeceasedMemorial.whenLabel(u.anniversary.daysUntil, arabic: L10n.isArabic))
                            .dsFont(.subtitle)
                            .foregroundColor(u.anniversary.daysUntil <= 1 ? DS.Color.accent : DS.Color.textTertiary)
                    }
                }
            }
            if let incomplete, incomplete > 0 {
                AdminRowDivider(inset: AdminRowDivider.iconInset)
                AnyView(incompleteRow(incomplete))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    /// «134 متوفى بلا تاريخ كامل ‹» — لمن يعدّل الأعضاء يفتح صفحة الاستكمال، ولغيره بلا سهم
    @ViewBuilder
    private func incompleteRow(_ n: Int) -> some View {
        let edits = authVM.canEditMembers && authVM.adminCanEdit(.family)
        let row = AdminListRow(icon: "calendar.badge.exclamationmark", tint: DS.Color.deceased,
                               title: incompleteText(n),
                               subtitle: edits ? L10n.t("أضف التاريخ متى عُرف", "Add the date once it's known") : nil,
                               showsChevron: edits)
        if edits {
            NavigationLink {
                AdminLazyPage { deathDatesPage() }
            } label: {
                row
            }
            .buttonStyle(AdminRowPressStyle())
        } else {
            row
        }
    }
}
