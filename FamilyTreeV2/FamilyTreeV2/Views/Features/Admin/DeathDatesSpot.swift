import SwiftUI

// MARK: - مكان «تواريخ الوفاة» في «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٤)
//
// تحت «الأقسام» بعنوان واضح «إدارة الوفيات» (طلب المالك ٢٠٢٦-١٠-٢٥ «نخليها تحت الاقسام الستة بشكل واضح و بسيط ومرتب
// وواضح ان ادارة الوفيات» — كانت بطاقة بارزة تحت «يحتاج انتباهك») — مكان واحد بحالين:
//   • أثناء الحملة ولمن يعدّل الأعضاء (المالك والمدير والمراقب — `canEditMembers`): بطاقة بسيطة — العنوان وعدد الناقص، سطر
//     تقدّم واحد، وزرّ واحد «أكمل التواريخ» ← صفحتها (`DeathDatesCampaignPage`).
//   • بعدها (موقوفة من السيرفر، انتهى آخر يوم، أو اكتملت التواريخ)، وللمشرف دائماً: «ذكرى الراحلين» — أقرب ذكريين
//     (`DeceasedMemorialBoard`) ← «المناسبات والإعلانات»، وسطر «N متوفى: لا يوجد تاريخ كامل للوفاة» لمن لم يُحصّل تاريخه.
// كل بطاقة نوع مستقل خلف `AnyView` (حارس مكدس «اليوم» — ٨٠٠ ك.ب).

struct AdminDeathDatesSpot: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @ObservedObject private var store = DeathDatesCampaignStore.shared

    var body: some View {
        let loaded = !memberVM.allMembers.isEmpty
        let stats = DeathDatesCampaign.stats(memberVM.allMembers)
        // قبل وصول الأعضاء: البطاقة نفسها بلا أرقام («—») — لا قفز بين الحالين
        let campaign = authVM.canEditMembers && (!loaded || store.isActive(stats))
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: authVM.canEditMembers ? L10n.t("إدارة الوفيات", "Deaths") : L10n.t("الوفيات", "Deaths"))
            if campaign {
                AnyView(DeathDatesCampaignCard(stats: loaded ? stats : nil, until: store.until))
            } else {
                AnyView(DeceasedMemorialSpotCard(incomplete: stats.incomplete))
            }
        }
        .task { await store.refresh() }
    }
}

// MARK: - «إدارة تواريخ الوفاة»

/// البطاقة البسيطة تحت الأقسام: الرمز والعنوان وعدد من بلا تاريخ كامل، سطر تقدّم واحد («اكتمل 5 من 18 · 27٪»)، وزرّ واحد
/// «أكمل التواريخ» — البطاقة كلها تفتح الصفحة. آخر يوم يظهر شريحةً فقط إن حُدّد في السيرفر
struct DeathDatesCampaignCard: View {
    /// nil = لم تصل الأعضاء
    let stats: DeathDatesStats?
    let until: Date?

    var body: some View {
        NavigationLink {
            AdminLazyPage {
                AnyView(AdminAreaGate(area: .family) { AnyView(DeathDatesCampaignPage()) }
                    .adminBackTitle(L10n.t("اليوم", "Today")).adminArea(.family))
            }
        } label: {
            AnyView(face)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityHint(L10n.t("يفتح قائمة المتوفين بلا تاريخ كامل", "Opens the deceased without a full date"))
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .center, spacing: DS.Spacing.md) {
                AdminIconSquare(symbol: "calendar.badge.clock", tint: DS.Color.saduFill, filled: true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(L10n.t("استكمال تواريخ الوفاة", "Complete the death dates"))
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: missingLine)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DS.Spacing.xs)
                if let until {
                    AdminValueChip(text: L10n.t("حتى \(DeathDatesCampaignStore.untilText(until))",
                                                "Until \(DeathDatesCampaignStore.untilText(until))"),
                                   icon: "clock", tint: DS.Color.sadu)
                }
            }
            // سطر التقدّم الواحد: المكتمل أخضر على مسار خافت، والعدد بجانبه
            HStack(spacing: DS.Spacing.sm) {
                DSMeterBar(progress: stats?.share, tint: DS.Color.success)
                Text(verbatim: progressText)
                    .dsFont(.hubLabel)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            AdminPillLabel(title: L10n.t("أكمل التواريخ", "Complete the dates"), icon: "calendar.badge.plus",
                           style: .gold, height: DS.Hub.pillHeightCard, fullWidth: true)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
        .accessibilityElement(children: .combine)
    }

    /// «13 متوفى بلا تاريخ كامل» (متوفى واحد، متوفيان، 3 متوفين)
    private var missingLine: String {
        guard let s = stats else { return L10n.t("جارٍ العدّ…", "Counting…") }
        guard L10n.isArabic else { return "\(s.incomplete) without a full date" }
        let n = AdminTodayText.arabicCount(s.incomplete, one: "متوفى واحد", two: "متوفيان", few: "متوفين",
                                           many: "متوفى", single: "متوفى")
        return "\(n) بلا تاريخ كامل"
    }

    /// «اكتمل 5 من 18 · 27٪»
    private var progressText: String {
        guard let s = stats else { return L10n.t("اكتمل — من —", "— of — complete") }
        let need = s.full + s.incomplete
        let percent = s.percent.map { L10n.t(" · \($0)٪", " · \($0)%") } ?? ""
        return L10n.t("اكتمل \(s.full) من \(need)", "\(s.full) of \(need) complete") + percent
    }
}

/// الحلقة بجانب «اكتمل N من M» وسطر الناقص — نفسها في «اليوم» وأعلى الصفحة
struct DeathDatesGaugeRow: View {
    let stats: DeathDatesStats?

    var body: some View {
        DSGaugeRow(gauge: DSRingGauge(parts: stats.flatMap { Self.parts($0) }, size: DS.Ring.small, track: DS.Ring.emptyTrack,
                                      center: .percent(stats?.percent)),
                   title: title, subtitle: subtitle)
    }

    /// مكتمل أخضر، السنة فقط كهرماني، بلا تاريخ رمادي المتوفين («غير معروف» خارج الحلقة — قرار إداري)
    static func parts(_ s: DeathDatesStats) -> [DSGaugePart]? {
        DSGaugePart.counts([("full", s.full, DS.Color.success),
                            ("year", s.yearOnly, DS.Color.warning),
                            ("missing", s.missing, DS.Color.deceased)])
    }

    private var title: String {
        guard let s = stats else { return L10n.t("اكتمل — من —", "— of — complete") }
        let need = s.full + s.incomplete
        return L10n.t("اكتمل \(s.full) من \(need)", "\(s.full) of \(need) complete")
    }

    private var subtitle: String {
        guard let s = stats else { return L10n.t("جارٍ العدّ…", "Counting…") }
        var parts = [L10n.t("السنة فقط \(s.yearOnly)", "Year only \(s.yearOnly)"),
                     L10n.t("بلا تاريخ \(s.missing)", "No date \(s.missing)")]
        if s.unknown > 0 { parts.append(L10n.t("غير معروف \(s.unknown)", "Unknown \(s.unknown)")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - «ذكرى الراحلين» (بعد الحملة)

/// أقرب ذكريين خلال ٣٠ يوماً ← «المناسبات والإعلانات» (القائمة كاملة في «القادم»)، ثم من بقي بلا تاريخ كامل
/// («لا يوجد تاريخ كامل للوفاة») — مختصرة: العنوان يقول «ذكرى» فالصفّ «المرحوم فلان» فقط
struct DeceasedMemorialSpotCard: View {
    let incomplete: Int
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel

    private static let shown = 2

    var body: some View {
        let board = DeceasedMemorialBoard(memberVM.allMembers)
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                AdminLazyPage {
                    AnyView(AdminOccasionsPage().adminArea(.occasions).adminBackTitle(L10n.t("اليوم", "Today")))
                }
            } label: {
                AnyView(memorials(board))
            }
            .buttonStyle(.plain)
            if incomplete > 0 {
                AdminRowDivider()
                AnyView(incompleteRow)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private func memorials(_ board: DeceasedMemorialBoard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AdminCardHeader(title: L10n.t("ذكرى الراحلين", "Memorials"),
                            badge: board.withinWeek, badgeTint: DS.Color.sadu) {
                AdminCardLinkLabel(title: L10n.t("القادم", "Upcoming"))
            }
            if board.upcoming.isEmpty {
                AdminListRow(icon: "moon.stars", tint: DS.Color.sadu,
                             title: L10n.t("لا ذكرى خلال ٣٠ يوماً", "No memorial in the next 30 days"),
                             showsChevron: false)
            } else {
                ForEach(Array(board.upcoming.prefix(Self.shown).enumerated()), id: \.element.id) { index, u in
                    if index > 0 { AdminRowDivider() }
                    AdminListRow(icon: "moon.stars.fill", tint: DS.Color.sadu,
                                 title: L10n.t("\(AdminOccasionsText.late(u.member)) \(u.member.shortFullName)",
                                               u.member.shortFullName),
                                 subtitle: DeceasedMemorial.anniversaryLine(u.anniversary, arabic: L10n.isArabic),
                                 showsChevron: false) {
                        AdminValueChip(text: DeceasedMemorial.whenLabel(u.anniversary.daysUntil, arabic: L10n.isArabic),
                                       tint: u.anniversary.daysUntil <= 1 ? DS.Color.accent : DS.Color.primary)
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }

    /// «N متوفى: لا يوجد تاريخ كامل للوفاة» — لمن يعدّل الأعضاء يفتح صفحة الاستكمال
    @ViewBuilder
    private var incompleteRow: some View {
        let row = AdminListRow(icon: "calendar.badge.exclamationmark", tint: DS.Color.deceased,
                               title: L10n.t("\(incomplete) متوفى: \(DeathDatesCampaign.noFullDate)",
                                             "\(incomplete) deceased: \(DeathDatesCampaign.noFullDate)"),
                               subtitle: authVM.canEditMembers ? L10n.t("أضف التاريخ متى عُرف", "Add the date once it's known") : nil,
                               showsChevron: authVM.canEditMembers)
        if authVM.canEditMembers {
            NavigationLink {
                AdminLazyPage {
                    AnyView(AdminAreaGate(area: .family) { AnyView(DeathDatesCampaignPage()) }
                        .adminBackTitle(L10n.t("اليوم", "Today")).adminArea(.family))
                }
            } label: {
                row
            }
            .buttonStyle(.plain)
        } else {
            row
        }
    }
}
