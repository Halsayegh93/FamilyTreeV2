import SwiftUI

// MARK: - رأس «العائلة» (اختيار المالك ٢٠٢٦-١١-٠٢: النموذج «ب» + «ج»، `samples/family-header`)
//
// مفتوحاً (ب): تحت العنوان ثلاث حلقات (السطر الذهبي «5 فروع · 47 مسجّلاً» حُذف في التبسيط ٢٠٢٦-١١-٠٢) بشكل «إحصاء الأفراد» (`DSRingGauge`
// بمسار الكحلي `DS.Ring.bandTrack`): الإجمالي ذهبي · الرجال · النساء — الحلقة نسبة الأحياء، والعدد في وسطها، وتحتها الاسم
// بلونها و«2351 حياً · 368 متوفى». الإجمالي ← «المؤشرات ← العائلة»، الرجال ← شريحة «الكل» في الصفحة نفسها، النساء ← شجرة
// النساء (كما في «إحصاء الأفراد»). من أحجام إمكانية الوصول كل حلقة كتلة (حلقة صغيرة بجانب الاسم والأعداد).
// مطويّاً (ج): حين تصعد الشرائح تحت سطر الرأس يظهر فوق التمرير سطر واحد مثبّت (`AdminMembersCompactBar`): ‹ · «العائلة ⌄ · 2719»
// · بحث (يرجع لأعلى ويضع المؤشر في الحقل) · ＋ تسجيل — والشرائح مثبّتة تحته في موضعها نفسه، فالتبديل بلا قفزة. العودة لأعلى
// تعيد الرأس الكامل. «تقليل الحركة» = تبديل بلا حركة.

/// أرقام رأس «العائلة» — نفس تعريفات «إحصاء الأفراد» (`AdminMemberCounts`): الرجال = الشجرة بلا طلبات الانضمام، النساء =
/// إناث شجرة النساء
struct AdminFamilyCensus: Equatable {
    var counts = AdminMemberCounts()
    /// «خارج العائلة» (طلب المالك ٢٠٢٦-١١-٠٨): ذكور = أبناء البنات (`DaughterSonsIndex`) + أزواج البنات من خارج العائلة؛
    /// إناث = نساء شجرة النساء المعلَّمات `is_outside_family` — لا يدخلون الإجمالي ولا الرجال ولا النساء.
    /// الأحياء فقط (٢٠٢٦-١١-٢٦)
    var outsideMale: Int?
    var outsideFemale: Int?
    var outsideTotal: Int? { outsideMale.flatMap { m in outsideFemale.map { m + $0 } } }
    /// «N لهم حساب» تحت الرجال والنساء وخارج العائلة (طلب المالك ٢٠٢٦-١١-٠٩ — في «العائلة» لا في «اليوم»):
    /// الرجال من قوائم «استخدام التطبيق» (`AdminAccountsStore`)، النساء من ربط عقدتها بحساب (`WomenStore.linkedUserByWoman`)،
    /// وأبناء البنات من `get_members_last_signin` (`signedIn`) لأن السيرفر يستبعدهم من القوائم. nil قبل وصول البيانات
    var menAccounts: Int?
    var womenAccounts: Int?
    var outsideAccounts: Int?

    @MainActor
    static func make(members: [FamilyMember], women: [FamilyMember], signedIn: Set<UUID>? = nil) -> AdminFamilyCensus {
        var c = AdminFamilyCensus()
        let outside = WomenStore.outsideFamilyIds
        c.counts.setMen(from: members)
        c.counts.setWomen(women, excluding: outside)
        let sons = DaughterSonsIndex.shared.ids
        // حساب مراجعة أبل مسجّل كابن بنت — لا يُحسب
        let review = AppConfigValues.shared.reviewAccountIds
        // «خارج العائلة» الأحياء فقط (طلب المالك ٢٠٢٦-١١-٢٦ «المتوفاة شيل من الاحصائيات خارج العائلة ابى بس الاحياء») —
        // متوفوه في قسمهم داخل «فرع خارج العائلة» (`AdminWomenPanel`)
        let sonCount = members.filter { sons.contains($0.id) && $0.hasName && !review.contains($0.id) && $0.isDeceased != true }.count
        if !women.isEmpty {
            let outsideRows = women.filter { outside.contains($0.id) && $0.hasName && $0.isDeceased != true }
            c.outsideMale = sonCount + outsideRows.filter { !$0.isFemale }.count
            c.outsideFemale = outsideRows.filter(\.isFemale).count
            let linked = WomenStore.linkedUserByWoman
            c.womenAccounts = women.filter { $0.isFemale && $0.hasName && !outside.contains($0.id) && linked[$0.id] != nil }.count
            if let signedIn {
                c.outsideAccounts = members.filter { sons.contains($0.id) && $0.hasName && !review.contains($0.id) && signedIn.contains($0.id) }.count
                    + outsideRows.filter { linked[$0.id] != nil }.count
            }
        }
        let accounts = AdminAccountsStore.shared
        if accounts.loaded {
            c.menAccounts = members.filter { m in
                m.role != .pending && m.hasName && !m.isWomanAccount && !sons.contains(m.id) && accounts.info(m.id) != nil
            }.count
        }
        return c
    }
}

/// الحلقات الثلاث فوق الرأس الكحلي
struct AdminFamilyCensusBand: View {
    let census: AdminFamilyCensus
    /// «الرجال» ← شريحة «الكل» في صفحة الأعضاء نفسها
    let openMen: () -> Void
    /// «النساء» ← «شجرة النساء» في الصفحة نفسها (nil = تبويب الشجرة كما كان، لمن لا يرى قائمة النساء)
    var openWomen: (() -> Void)? = nil
    /// «خارج العائلة» ← «شجرة النساء ← فرع خارج العائلة» في الصفحة نفسها
    var openOutside: (() -> Void)? = nil
    @EnvironmentObject private var authVM: AuthViewModel
    @ObservedObject private var verified = AdminLivingVerifiedStore.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dsLandscape) private var landscape

    private enum Target { case overview, men, women, outside }

    private struct Gauge: Identifiable {
        let id: String
        let title: String
        let tint: Color
        let total: Int?
        let alive: Int?
        let deceased: Int?
        let target: Target
        /// الأحياء تقديريون («تحقق من الأحياء» فيها من لم يُراجَع — الرجال والإجمالي)
        var estimated = false
        /// «خارج العائلة»: سطرا «N ذكور · M إناث» بدل الأحياء والمتوفين
        var lines: (String, String)? = nil
        /// «N لهم حساب» — الرجال والنساء وخارج العائلة
        var accounts: String? = nil
    }

    private var estimated: Bool {
        (census.counts.oldLiving.map { $0.subtracting(verified.ids).count } ?? 0) > 0
    }

    private var gauges: [Gauge] {
        let c = census.counts
        return [
            Gauge(id: "total", title: L10n.t("الإجمالي", "Total"), tint: DS.Color.accentLight,
                  total: c.total, alive: c.totalAlive, deceased: c.totalDeceased, target: .overview, estimated: estimated),
            Gauge(id: "men", title: L10n.t("الرجال", "Men"), tint: DS.Hub.censusMale,
                  total: c.men, alive: c.menAlive, deceased: c.menDeceased, target: .men, estimated: estimated,
                  accounts: Self.accountsText(census.menAccounts)),
            Gauge(id: "women", title: L10n.t("النساء", "Women"), tint: DS.Hub.censusFemale,
                  total: c.women, alive: c.womenAlive, deceased: c.womenDeceased, target: .women,
                  accounts: Self.accountsText(census.womenAccounts)),
            Gauge(id: "outside", title: L10n.t("خارج العائلة", "Outside"), tint: DS.Hub.censusOutside,
                  total: census.outsideTotal, alive: census.outsideMale, deceased: nil, target: .outside,
                  lines: (census.outsideMale.map { L10n.t("\($0) ذكور", "\($0) male") } ?? L10n.t("— ذكور", "— male"),
                          census.outsideFemale.map { L10n.t("\($0) إناث", "\($0) female") } ?? L10n.t("— إناث", "— female")),
                  accounts: Self.accountsText(census.outsideAccounts))
        ]
    }

    /// كتل عمودية من أحجام إمكانية الوصول (كـ«إحصاء الأفراد»)
    private var stacked: Bool { typeSize.isAccessibilitySize }
    /// أربع حلقات في صفّ (الدفعة ٢٠٢٦-١١-٠٨ «نضبط التصميم شوي»): المتوسطة لتتّسع الأربع في عرض ٣٩٣
    private var ringSize: DS.Ring.Size { DS.Ring.medium }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if stacked {
                AnyView(VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ForEach(gauges) { block($0) }
                })
            } else {
                // صفّ واحد — في الوضع الأفقي بعرض عمود القراءة في الوسط
                AnyView(HStack(alignment: .top, spacing: DS.Spacing.md) {
                    ForEach(gauges) { column($0) }
                }
                .frame(maxWidth: landscape ? DS.Landscape.maxContentWidth : .infinity)
                .frame(maxWidth: .infinity))
            }
        }
    }

    // MARK: الحلقة

    /// الأحياء بلون الحلقة فوق مسار الكحلي، والعدد الكلي في الوسط يعدّ من الصفر («—» ومسار فارغ قبل وصول الأعداد)
    private func ring(_ g: Gauge, size: DS.Ring.Size) -> DSRingGauge {
        let total = g.total ?? 0
        let known = g.alive != nil && total > 0
        return DSRingGauge(progress: known ? Double(g.alive ?? 0) / Double(total) : nil, tint: g.tint, size: size,
                           track: DS.Ring.bandTrack, center: .count(g.total), ink: DS.Color.textOnPrimary)
    }

    /// عمود: الحلقة، ثم الاسم بلونها، ثم «2351 حياً · 368 متوفى» (سطران إن ضاق) — رابط واحد
    private func column(_ g: Gauge) -> some View {
        let face = VStack(spacing: DS.Spacing.xs) {
            // الاسم أصغر وفوق الحلقة (طلب المالك ٢٠٢٦-١١-٠٨ «نصغرهم» + «خل عنوان الحلقة فوق الحلقة»)
            Text(g.title)
                .dsFont(.hubLabel)
                .foregroundColor(g.tint)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                // مسافة بين العنوان والحلقة (طلب المالك ٢٠٢٦-١١-٠٨)
                .padding(.bottom, DS.Spacing.xsm)
            ring(g, size: ringSize)
                // مسافة تحت الحلقة أيضاً (طلب المالك ٢٠٢٦-١١-٠٨)
                .padding(.bottom, DS.Spacing.xsm)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Spacing.xs) { aliveText(g); dot; deceasedText(g) }
                VStack(spacing: 0) { aliveText(g); deceasedText(g) }
            }
            // سطر محجوز في كل الأعمدة (الحلقات بطول واحد)
            accountsText(g)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(g))
        return link(g, face: AnyView(face))
    }

    /// كتلة (أحجام إمكانية الوصول): حلقة صغيرة بجانب الاسم والعدد، ثم الأحياء والمتوفون
    private func block(_ g: Gauge) -> some View {
        let face = HStack(spacing: DS.Spacing.md) {
            ring(g, size: DS.Ring.mediumStacked)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "\(g.title) \(Self.number(g.total))")
                    .dsFont(.hubRow)
                    .foregroundColor(g.tint)
                    .fixedSize(horizontal: false, vertical: true)
                aliveText(g)
                deceasedText(g)
                if g.accounts != nil { accountsText(g) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(g))
        return link(g, face: AnyView(face))
    }

    private func aliveText(_ g: Gauge) -> some View {
        Text(verbatim: g.lines?.0 ?? AdminFamilyStatsPage.aliveText(g.alive, estimated: g.estimated))
            .dsFont(.caption)
            .monospacedDigit()
            .foregroundColor(g.tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func deceasedText(_ g: Gauge) -> some View {
        Text(verbatim: g.lines?.1 ?? AdminFamilyStatsPage.deceasedText(g.deceased))
            .dsFont(.caption)
            .monospacedDigit()
            .foregroundColor(DS.Hub.onBandMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func accountsText(_ g: Gauge) -> some View {
        Text(verbatim: g.accounts ?? " ")
            .dsFont(.caption)
            .monospacedDigit()
            .foregroundColor(DS.Color.accentLight)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    static func accountsText(_ n: Int?) -> String {
        n.map { L10n.t("\($0) لهم حساب", "\($0) with accounts") } ?? L10n.t("— لهم حساب", "— with accounts")
    }

    private var dot: some View {
        Text(verbatim: "·")
            .dsFont(.caption)
            .foregroundColor(DS.Hub.onBandMuted)
    }

    // MARK: الروابط (كـ«إحصاء الأفراد»)

    @ViewBuilder
    private func link(_ g: Gauge, face: AnyView) -> some View {
        switch g.target {
        case .overview:
            // «المؤشرات ← العائلة» لمن يرى «المؤشرات» فقط — وإلا رقم بلا رابط
            if AdminArea.metrics.isVisible(for: authVM) {
                NavigationLink {
                    AdminLazyPage {
                        AnyView(AdminAreaGate(area: .metrics) { AnyView(AdminAnalyticsView()) }
                            .adminArea(.metrics).adminBackTitle(AdminArea.family.title))
                    }
                } label: { face }
                .buttonStyle(DSPressStyle())
                .accessibilityHint(L10n.t("يفتح المؤشرات ← العائلة", "Opens Insights → Family"))
            } else {
                face
            }
        case .men:
            Button(action: openMen) { face }
                .buttonStyle(DSPressStyle())
                .accessibilityHint(L10n.t("يعرض كل الأعضاء", "Shows all members"))
        case .women:
            if let openWomen {
                Button(action: openWomen) { face }
                    .buttonStyle(DSPressStyle())
                    .accessibilityHint(L10n.t("يعرض قائمة النساء", "Shows the women's list"))
            } else {
                womenTreeLink(face)
            }
        case .outside:
            if let openOutside {
                Button(action: openOutside) { face }
                    .buttonStyle(DSPressStyle())
                    .accessibilityHint(L10n.t("يعرض فرع خارج العائلة", "Shows the outside branch"))
            } else {
                face
            }
        }
    }

    /// شجرة النساء في تبويب الشجرة (كحلقة «النساء» في «إحصاء الأفراد») — لمن لا يرى قائمة النساء هنا
    private func womenTreeLink(_ face: AnyView) -> some View {
        Button {
            TreeTabContainer.openWomenOnAppear = true
            NotificationCenter.default.post(name: .openWomenTree, object: nil)
        } label: { face }
        .buttonStyle(DSPressStyle())
        .accessibilityHint(L10n.t("يفتح شجرة النساء", "Opens the women's tree"))
    }

    // MARK: النصوص

    private static func number(_ n: Int?) -> String { n.map { "\($0)" } ?? "—" }

    /// «الإجمالي 2719، 2351 حياً، 368 متوفى»
    private func spoken(_ g: Gauge) -> String {
        if let lines = g.lines {
            return "\(g.title) \(Self.number(g.total))" + L10n.t("، ", ", ") + lines.0 + L10n.t("، ", ", ") + lines.1
                + L10n.t("، لا يدخلون الإجمالي", ", not in the total")
        }
        return "\(g.title) \(Self.number(g.total))" + L10n.t("، ", ", ")
            + AdminFamilyStatsPage.aliveText(g.alive, estimated: false)
            + (g.estimated ? L10n.t(" (تقديري)", " (estimate)") : "")
            + L10n.t("، ", ", ") + AdminFamilyStatsPage.deceasedText(g.deceased)
    }
}

/// الرأس المطويّ (ج): سطر واحد مثبّت فوق التمرير — ‹ · «العائلة ⌄ · 2719» · بحث · ＋ — والشرائح تحته
struct AdminMembersCompactBar: View {
    let total: Int?
    let backTitle: String
    let back: () -> Void
    let search: () -> Void
    /// صفحة «تسجيل عضو جديد» (`canRegisterMembers`) — nil = بلا زرّ
    let register: (() -> AnyView)?
    let chips: AnyView
    /// ارتفاع سطر الرأس — الشرائح تُثبَّت تحته حين تصل إليه
    @Binding var lineHeight: CGFloat
    @Environment(\.dsLandscape) private var landscape

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                AdminBackLink(title: backTitle, showsTitle: false, action: back)
                AnyView(AdminAreaTitleMenu(title: AdminArea.family.title, count: total.map { "\($0)" }, compact: true))
                Spacer(minLength: DS.Spacing.xs)
                AdminGlassButton(symbol: "magnifyingglass", label: L10n.t("بحث بالاسم أو رقم الهاتف", "Search by name or phone"),
                                 action: search)
                if let register {
                    NavigationLink { AdminLazyPage { register() } } label: {
                        AdminGlassCircle(symbol: "plus")
                    }
                    .buttonStyle(DSPressStyle())
                    .accessibilityLabel(L10n.t("تسجيل عضو جديد", "Register a new member"))
                }
            }
            .frame(minHeight: DS.Hub.compactBar)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lineHeight = $0 }
            chips
        }
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth - 2 * DS.Spacing.lg)
        .padding(.horizontal, landscape ? DS.Spacing.xxl : DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Hub.band.ignoresSafeArea(edges: landscape ? .horizontal : []))
        .dsSubtleShadow()
    }
}
