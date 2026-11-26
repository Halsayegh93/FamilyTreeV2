import SwiftUI

// MARK: - Admin Analytics — إحصائيات متقدمة
//
// بتصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧): بطاقة رأس بلون بلاطة «إحصائيات متقدمة»
// (مجال «الشجرة والأعضاء») وأرقامها الحيّة ← «ملخص عام» بحلقة الأحياء ← التوزيعات بأشرطة ونِسَب
// ← شبكات أرقام `DSStatTile` ← «نمو الأعضاء» بالأعمدة ← الأخبار.
// بشكل «اليوم» (٢٠٢٦-١٠-٢٠، `AdminPageKit`): الأرقام في الرأس الكحلي، الأقسام بطاقات بيضاء، والشبكات
// تحت عناوين أقسام مثل «نبض العائلة».
// كل رقم من البيانات المحمّلة أصلاً (الأعضاء، شجرة النساء) وبنفس الحسابات السابقة.
// الترتيب «أ» (اختيار المالك ٢٠٢٦-١١-٢٦ «ابى ارتب احصائيات العائلة»): أعداد «العائلة» نفسها (`AdminFamilyCensus`) ←
// «خارج العائلة» (الأحياء) ← «الأحياء والراحلون» (الرجال والنساء) ← التطبيق (المسجّلون، الأدوار) ← تركيبة العائلة
// (الأعمار، نظرة على الشجرة) ← النمو. حُذفت: «تفاصيل» المطوية، الجنس (مكرّر في الحلقات)، شجرة النساء (داخل الأعداد)،
// الحالة الاجتماعية (قلّة من سُجّل زواجه)، إحصائيات الوفيات (داخل «الأحياء والراحلون»)، والأخبار (ليست من العائلة).
struct AdminAnalyticsView: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var authVM: AuthViewModel
    /// المسجّلون مقابل المقيّدين في الشجرة (`app_usage_stats` — نفس أرقام «اليوم»)
    @State private var usage: AppUsageStats? = AppUsageStats.cached

    /// «المؤشرات ← العائلة» بيت «إحصاء الأفراد» (الدفعة ج): المراقب يرى الأعداد فقط (الملخص، المسجّلون، الجنس، النساء)
    private var countsOnly: Bool { !authVM.isAdmin }

    /// بيانات شجرة النساء (women_members) — كاش فوري ثم جلب عند الحاجة.
    @State private var womenData: [FamilyMember] = WomenStore.cache
    /// حالة جلب شجرة النساء — بطاقة تحميل/خطأ بدل «جاري التحميل» الدائمة إن فشل الجلب
    @State private var womenLoading = false
    @State private var womenFailed = false
    /// انتهت محاولة جلب (أو الكاش جاهز من البداية)
    @State private var womenAttempted = !WomenStore.cache.isEmpty

    /// لون بلاطة «إحصائيات متقدمة» في لوحة الإدارة — مجال «الشجرة والأعضاء»
    private let pageTint = DS.Color.composerProject

    // البيانات المحسوبة — مبنية على المعيار القانوني (FamilyMember.isCountable)
    // عشان تطابق "أعضاء العائلة" في الشجرة + الويب + التقارير
    private var countableMembers: [FamilyMember] {
        memberVM.allMembers.filter(\.isCountable)
    }
    private var activeMembers: [FamilyMember] {
        countableMembers.filter { $0.isDeceased != true }
    }
    private var deceasedMembers: [FamilyMember] {
        countableMembers.filter { $0.isDeceased == true }
    }
    private var totalMembers: Int { countableMembers.count }

    var body: some View {
        // نمو الأعضاء يُحسب مرة واحدة — لبطاقة الرأس («جديد هذا الشهر») ولقسم النمو
        let growth = monthlyGrowth()
        // أعداد «العائلة» نفسها (الرجال، نساء العائلة بلا «خارج العائلة»، وخارج العائلة الأحياء) — مرة واحدة
        let census = AdminFamilyCensus.make(members: memberVM.allMembers, women: womenData)

        // بشكل «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠، `AdminPageKit`): رأس كحلي بالأرقام ← «ملخص عام» يصعد فوقه ←
        // البطاقات والشبكات (عمودان أفقياً)
        return AdminPage(header: header(census, newThisMonth: growth.last?.count ?? 0),
                         lead: AnyView(totalMembers == 0 ? AnyView(membersStateCard) : AnyView(censusCard(census))),
                         content: AnyView(sections(growth, census: census)))
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            // جلب بيانات شجرة النساء إن لم تكن محمّلة (كاش التبويب يغني عن الجلب غالباً)
            async let accounts = AppUsageStats.fetch()
            if womenData.isEmpty { await loadWomen() }
            if let u = await accounts { usage = u }
        }
    }

    /// نفس جلب شجرة النساء السابق (`WomenStore.fetch()`) — ويحفظ حالته لبطاقة التحميل/الخطأ
    @MainActor
    private func loadWomen() async {
        womenLoading = true
        womenFailed = false
        if let fetched = try? await WomenStore.fetch() {
            womenData = fetched
        } else {
            womenFailed = true
        }
        womenLoading = false
        womenAttempted = true
    }

    // MARK: - الرأس الكحلي

    /// ٣ أرقام حيّة من البيانات المحمّلة أصلاً: أفراد العائلة (نفس «إجمالي» الملخص)، نسبة الأحياء،
    /// ومن أُضيف هذا الشهر (آخر عمود في «نمو الأعضاء») — «—» قبل تحميل الأعضاء.
    private func header(_ census: AdminFamilyCensus, newThisMonth: Int) -> AdminPageHeader {
        // «أفراد العائلة» = الرجال + نساء العائلة (كان الرجال وحدهم) — نفس «الإجمالي» في الحلقات وفي «العائلة»
        let total = census.counts.total ?? 0
        let alive = census.counts.totalAlive ?? 0
        let ready = total > 0
        let alivePct = AnalyticsPercent.value(alive, of: total)
        return AdminPageHeader(
            title: L10n.t("إحصاءات العائلة", "Family statistics"),
            subtitle: countsOnly ? L10n.t("الأعداد · الأحياء والراحلون · المسجّلون", "Counts · living and deceased · registered")
                                 : L10n.t("الأعداد · الأحياء والراحلون · التطبيق · التركيبة · النمو",
                                          "Counts · living and deceased · app · makeup · growth"),
            glyph: "chart.bar.xaxis",
            kpis: [
                AdminPageKPI(ready ? total.formatted() : "—", L10n.t("أفراد العائلة", "Members"),
                             icon: "person.3.fill"),
                AdminPageKPI(ready ? L10n.t("\(alivePct)٪", "\(alivePct)%") : "—", L10n.t("أحياء", "Alive"),
                             icon: "heart.fill", tint: DS.Hub.kpiMine,
                             ring: ready ? Double(alive) / Double(total) : nil),
                AdminPageKPI(ready ? signed(newThisMonth) : "—", L10n.t("جديد هذا الشهر", "New this month"),
                             icon: "chart.line.uptrend.xyaxis", tint: DS.Hub.kpiLate)
            ])
    }

    /// البطاقات بعد الحلقات — بالترتيب «أ» (عمودان أفقياً)
    private func sections(_ growth: [(label: String, count: Int)], census: AdminFamilyCensus) -> AnyView {
        guard totalMembers > 0 else { return AnyView(EmptyView()) }
        if countsOnly {
            return AnyView(AdaptiveCardStack(spacing: DS.Hub.stackSpacing) {
                AnyView(outsideCard(census))
                AnyView(aliveDeadSection(census))
                AnyView(registeredSection)
            })
        }
        return AnyView(AdaptiveCardStack(spacing: DS.Hub.stackSpacing) {
            // ١ الأعداد: الحلقات فوق، ثم «خارج العائلة»
            AnyView(outsideCard(census))
            // ٢ الأحياء والراحلون
            AnyView(aliveDeadSection(census))
            // ٣ التطبيق
            AnyView(registeredSection)
            AnyView(rolesSection)
            // ٤ تركيبة العائلة
            AnyView(ageGroupsSection)
            AnyView(treeInsightsSection)
            // ٥ النمو
            AnyView(monthlyGrowthSection(growth))
        })
    }

    /// «+١٢» — الإشارة قبل الرقم في السطر العربي أيضاً
    private func signed(_ n: Int) -> String {
        n > 0 ? "\u{2066}+\(n.formatted())\u{2069}" : "0"
    }

    // MARK: - «إحصاء الأفراد» (أول بطاقة — تصعد فوق الرأس)

    /// الحلقات الثلاث (الإجمالي · الرجال · النساء) + المسجّلون — انتقلت من مربّع «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٢) فبيتها
    /// هنا وحده. نفس الأعداد من البيانات المحمّلة في الصفحة (الأعضاء، شجرة النساء، «استخدام التطبيق») بلا جلب جديد
    private func censusCard(_ census: AdminFamilyCensus) -> some View {
        // نساء العائلة بلا «خارج العائلة» (كانت تعدّهن هنا وحدها — ٢٠٢٦-١١-٢٦)
        var counts = census.counts
        counts.setUsage(usage)
        return AdminMemberCountsCard(counts: counts)
    }

    // MARK: - «خارج العائلة» (الأحياء فقط — نفس حلقتها في «العائلة»)

    /// إناث من خارج العائلة (زوجات من عوائل ثانية، بنات البنات) · أزواج البنات · أبناء البنات — الأحياء فقط
    /// (طلب المالك ٢٠٢٦-١١-٢٦)، ولا يدخلون أي رقم فوق. المتوفون في «فرع خارج العائلة» بقسمهم
    @ViewBuilder
    private func outsideCard(_ census: AdminFamilyCensus) -> some View {
        if womenData.isEmpty {
            womenStateCard
        } else {
            let outside = WomenStore.outsideFamilyIds
            let rows = womenData.filter { outside.contains($0.id) && $0.hasName }
            let living = rows.filter { $0.isDeceased != true }
            let females = living.filter(\.isFemale).count
            let husbands = living.count - females
            let sons = max((census.outsideMale ?? husbands) - husbands, 0)
            let deceased = rows.count - living.count
            AdminSectionCard(title: L10n.t("خارج العائلة", "Outside the family"),
                             tag: L10n.t("\((females + husbands + sons).formatted()) حي", "\((females + husbands + sons).formatted()) living")) {
                valueLine(icon: "figure.stand.dress", tint: DS.Color.female,
                          label: L10n.t("إناث (زوجات وبنات بنات)", "Women (wives, daughters' daughters)"), value: females)
                valueLine(icon: "figure.stand", tint: DS.Color.slate,
                          label: L10n.t("أزواج البنات", "Daughters' husbands"), value: husbands)
                valueLine(icon: "figure.and.child.holdinghands", tint: DS.Color.slate,
                          label: L10n.t("أبناء البنات", "Daughters' sons"), value: sons)
                Text(L10n.t("لا يُعدّون في أرقام العائلة فوق · المتوفون (\(deceased.formatted())) في «فرع خارج العائلة»",
                            "Not counted in the family numbers above · deceased (\(deceased.formatted())) are in «Outside branch»"))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - «الأحياء والراحلون» (الرجال ونساء العائلة)

    /// أحياء · متوفون (من الحلقات نفسها)، ثم متوسط العمر عند الوفاة وأطول عمر ومن بلا تاريخ وفاة — كان «إحصائيات
    /// الوفيات» للرجال وحدهم
    private func aliveDeadSection(_ census: AdminFamilyCensus) -> some View {
        let c = census.counts
        let total = c.total ?? 0
        let alive = c.totalAlive ?? 0
        let dead = c.totalDeceased ?? 0
        let outside = WomenStore.outsideFamilyIds
        let deadWomen = womenData.filter { $0.isFemale && $0.hasName && !outside.contains($0.id) && $0.isDeceased == true }
        let deadPeople = deceasedMembers + deadWomen

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let calendar = Calendar.current
        let lifespans: [Int] = deadPeople.compactMap { m in
            guard let bStr = m.birthDate, let dStr = m.deathDate,
                  let b = formatter.date(from: String(bStr.prefix(10))),
                  let d = formatter.date(from: String(dStr.prefix(10))),
                  d >= b else { return nil }
            return calendar.dateComponents([.year], from: b, to: d).year
        }
        let avgLifespan = lifespans.isEmpty ? 0 : lifespans.reduce(0, +) / lifespans.count
        let oldest = lifespans.max() ?? 0
        let noDate = deadPeople.filter { ($0.deathDate ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.count

        return AdminSectionCard(title: L10n.t("الأحياء والراحلون", "Living and deceased"),
                                tag: total > 0 ? L10n.t("\(total.formatted()) فرد", "\(total.formatted()) members") : nil) {
            valueLine(icon: "heart.fill", tint: DS.Color.success, label: L10n.t("أحياء", "Living"), value: alive,
                      share: total > 0 ? AnalyticsPercent.text(alive, of: total) : nil)
            valueLine(icon: "leaf.fill", tint: DS.Color.deceased, label: L10n.t("متوفون", "Deceased"), value: dead,
                      share: total > 0 ? AnalyticsPercent.text(dead, of: total) : nil)
            LazyVGrid(columns: tileColumns(3), spacing: DS.Spacing.sm) {
                DSStatTile(value: avgLifespan > 0 ? "\(avgLifespan)" : "—",
                           label: L10n.t("متوسط العمر عند الوفاة", "Avg. age at death"),
                           icon: "hourglass.bottomhalf.filled", tint: DS.Color.warning)
                DSStatTile(value: oldest > 0 ? "\(oldest)" : "—",
                           label: L10n.t("أطول عمر", "Longest life"),
                           icon: "star.fill", tint: DS.Color.success)
                DSStatTile(value: noDate.formatted(),
                           label: L10n.t("بلا تاريخ وفاة", "No death date"),
                           icon: "calendar.badge.exclamationmark", tint: DS.Color.textSecondary)
            }
            if !lifespans.isEmpty && lifespans.count < deadPeople.count {
                Text(L10n.t("العمر محسوب من \(lifespans.count.formatted()) متوفى لديهم تاريخ ميلاد ووفاة",
                            "Ages from \(lifespans.count.formatted()) deceased with both birth & death dates"))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - حالة الأعضاء (قبل الأقسام)

    /// لا أعضاء محسوبين: فشل التحميل (مع إعادة المحاولة) · جارٍ التحميل · لا بيانات كافية
    @ViewBuilder
    private var membersStateCard: some View {
        if memberVM.membersLoadFailed {
            AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                                      message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                      retry: { Task { await memberVM.fetchAllMembers(force: true) } }))
        } else if memberVM.allMembers.isEmpty {
            AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الأعضاء…", "Loading members…")))
        } else {
            AdminPageStateCard(.empty(L10n.t("لا توجد بيانات كافية", "No data available"),
                                      message: L10n.t("أضف أعضاء للشجرة لعرض الإحصاءات",
                                                      "Add members to the tree to see analytics")))
        }
    }

    // MARK: - المسجّلون في التطبيق من الأحياء (الحالات الرسمية — «عضو مسجّل» · «بدون حساب»)

    /// كل رقم يفتح شريحته في «العائلة» (بيت القائمة)
    private var registeredSection: some View {
        let u = usage
        let registered = u.map { $0.active + $0.idle + $0.loginNoDevice }
        let treeOnly = u.map { $0.neverLogged + $0.noPhone }
        let living = (registered ?? 0) + (treeOnly ?? 0)
        let pct = AnalyticsPercent.value(registered ?? 0, of: living)
        let line = L10n.t("\(registered ?? 0) من \(living) من الأحياء", "\(registered ?? 0) of \(living) living members")
        return AdminSectionCard(title: L10n.t("المسجّلون في التطبيق من الأحياء", "Registered among the living"),
                                spacing: DS.Spacing.sm) {
            // الحلقة الموحّدة (الدفعة ١٠): المسجّلون أخضر فوق رمادي «بدون حساب»
            DSGaugeRow(gauge: DSRingGauge(progress: u == nil || living == 0 ? nil : Double(registered ?? 0) / Double(living),
                                          tint: DS.Color.success, size: DS.Ring.medium, track: DS.Ring.restTrack,
                                          center: .percent(u == nil || living == 0 ? nil : pct),
                                          caption: L10n.t("مسجّلون", "Registered")),
                       title: L10n.t("لهم حساب في التطبيق", "Have an app account"),
                       subtitle: u == nil ? L10n.t("جارٍ تحميل الحسابات…", "Loading accounts…") : line,
                       spoken: u == nil ? nil : L10n.t("المسجّلون \(pct)٪، \(line)", "Registered \(pct)%, \(line)"))
            AdminRowsCardBody {
                AdminTapRow(icon: "checkmark.seal.fill", tint: DS.Color.success,
                            title: L10n.t("الأعضاء المسجّلون", "Registered members"),
                            subtitle: L10n.t("لهم حساب في التطبيق", "Have an app account"),
                            value: registered.map { "\($0)" } ?? "—",
                            tap: .page { AnyView(AdminMembersPage(chip: .registered).adminArea(.family)) })
                AdminTapRow(icon: "person.fill", tint: DS.Color.slate,
                            title: L10n.t("بدون حساب", "In the tree only"),
                            subtitle: L10n.t("أسماء في الشجرة بلا حساب", "Names in the tree without an account"),
                            value: treeOnly.map { "\($0)" } ?? "—",
                            tap: .page { AnyView(AdminMembersPage(chip: .treeOnly).adminArea(.family)) })
            }
        }
    }

    // MARK: - Roles Distribution
    private var rolesSection: some View {
        // الأحياء فقط — كان «عضو» يشمل المتوفّين (٢٬٧١١ بدل ٢٬٣٤٤)
        let pool = activeMembers
        let admins = pool.filter { $0.role == .owner || $0.role == .admin }.count
        let monitors = pool.filter { $0.role == .monitor }.count
        let supervisors = pool.filter { $0.role == .supervisor }.count
        let members = pool.filter { $0.role == .member }.count
        let sum = admins + monitors + supervisors + members
        let total = max(sum, 1)

        return AdminSectionCard(title: L10n.t("توزيع الأدوار (الأحياء)", "Roles (alive)"),
                                tag: L10n.t("\(sum.formatted()) حي", "\(sum.formatted()) alive")) {
            VStack(spacing: DS.Spacing.sm) {
                AnalyticsBarRow(label: L10n.t("مدير", "Admin"), count: admins, total: total,
                                color: FamilyMember.UserRole.admin.color)
                AnalyticsBarRow(label: L10n.t("مراقب", "Monitor"), count: monitors, total: total,
                                color: FamilyMember.UserRole.monitor.color)
                AnalyticsBarRow(label: L10n.t("مشرف", "Supervisor"), count: supervisors, total: total,
                                color: FamilyMember.UserRole.supervisor.color)
                AnalyticsBarRow(label: L10n.t("عضو", "Member"), count: members, total: total,
                                color: FamilyMember.UserRole.member.color)
            }
        }
    }

    /// شجرة النساء بلا أرقام بعد: خطأ (مع إعادة نفس الجلب) · تحميل · لا بيانات
    @ViewBuilder
    private var womenStateCard: some View {
        if womenFailed {
            AdminPageStateCard(.error(L10n.t("تعذّر تحميل بيانات النساء", "Couldn't load women data"),
                                      message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                      retry: { Task { await loadWomen() } }))
        } else if womenLoading || !womenAttempted {
            AdminPageStateCard(.loading(L10n.t("جاري تحميل بيانات النساء…", "Loading women data…")))
        } else {
            AdminPageStateCard(.empty(L10n.t("لا توجد بيانات بعد", "No data yet"),
                                      message: L10n.t("تظهر هنا أرقام شجرة النساء بعد إضافتهن",
                                                      "Women tree numbers appear here once they're added")))
        }
    }

    // MARK: - Tree Insights — نظرة على الشجرة
    private var treeInsightsSection: some View {
        // بنية الشجرة محسوبة على كل الأعضاء للحفاظ على سلاسل النسب كاملة.
        let all = memberVM.allMembers

        // الأبناء حسب الأب.
        var childrenByFather: [UUID: Int] = [:]
        for m in all {
            if let f = m.fatherId { childrenByFather[f, default: 0] += 1 }
        }
        let parentsCount = childrenByFather.count
        let totalChildren = childrenByFather.values.reduce(0, +)
        let avgChildren = parentsCount > 0 ? Double(totalChildren) / Double(parentsCount) : 0
        let maxChildren = childrenByFather.values.max() ?? 0

        // أعضاء بلا أبناء (countable فقط — أوراق فعلية في العائلة).
        let leaves = countableMembers.filter { childrenByFather[$0.id] == nil }.count

        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: L10n.t("نظرة على الشجرة", "Tree Insights"))

            LazyVGrid(columns: tileColumns(3), spacing: DS.Spacing.sm) {
                DSStatTile(value: parentsCount.formatted(), label: L10n.t("لديهم أبناء", "Parents"),
                           icon: "person.2.fill", tint: DS.Color.info)
                DSStatTile(value: String(format: "%.1f", avgChildren), label: L10n.t("متوسط الأبناء", "Avg. children"),
                           icon: "chart.bar.fill", tint: DS.Color.warning)
                DSStatTile(value: maxChildren.formatted(), label: L10n.t("أكبر عائلة", "Largest family"),
                           icon: "crown.fill", tint: DS.Color.secondary)
                DSStatTile(value: leaves.formatted(), label: L10n.t("بدون أبناء", "No children"),
                           icon: "leaf.fill", tint: DS.Color.success)
                DSStatTile(value: totalChildren.formatted(), label: L10n.t("روابط نسب", "Parent links"),
                           icon: "arrow.triangle.branch", tint: AppSection.admin.ink)
            }
        }
    }

    // MARK: - Age Groups
    private var ageGroupsSection: some View {
        let calendar = Calendar.current
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let pool = activeMembers

        let ages: [Int] = pool.compactMap { member in
            guard let birthStr = member.birthDate,
                  let birthDate = dateFormatter.date(from: birthStr) else { return nil }
            return calendar.dateComponents([.year], from: birthDate, to: now).year
        }

        let under18 = ages.filter { $0 < 18 }.count
        let age18to30 = ages.filter { $0 >= 18 && $0 < 30 }.count
        let age30to50 = ages.filter { $0 >= 30 && $0 < 50 }.count
        let age50to70 = ages.filter { $0 >= 50 && $0 < 70 }.count
        let over70 = ages.filter { $0 >= 70 }.count
        let noAge = pool.count - ages.count
        let total = max(pool.count, 1)

        // فئات متتالية — لون القسم نفسه لكل الفئات، و«بدون تاريخ» رمادي
        return AdminSectionCard(title: L10n.t("الفئات العمرية", "Age Groups"),
                                tag: L10n.t("الأحياء", "Alive")) {
            VStack(spacing: DS.Spacing.sm) {
                AnalyticsBarRow(label: L10n.t("أقل من ١٨", "Under 18"), count: under18, total: total, color: pageTint)
                AnalyticsBarRow(label: "18–29", count: age18to30, total: total, color: pageTint)
                AnalyticsBarRow(label: "30–49", count: age30to50, total: total, color: pageTint)
                AnalyticsBarRow(label: "50–69", count: age50to70, total: total, color: pageTint)
                AnalyticsBarRow(label: L10n.t("٧٠+", "70+"), count: over70, total: total, color: pageTint)
                if noAge > 0 {
                    AnalyticsBarRow(label: L10n.t("بدون تاريخ", "No date"), count: noAge, total: total,
                                    color: DS.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Monthly Growth

    /// آخر ٦ أشهر: عدد من أُضيف كل شهر (نفس الحساب السابق — تاريخ الإنشاء من كل الأعضاء)،
    /// بمرور واحد على الأعضاء بدل مرور لكل شهر.
    private func monthlyGrowth() -> [(label: String, count: Int)] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let calendar = Calendar.current
        let now = Date()

        // عدد المضافين لكل (سنة، شهر)
        var perMonth: [Int: Int] = [:]
        // سجلّ بلا اسم (رقم دخول بلا اسم) ليس فرداً في العائلة — لا يُعدّ في النمو
        for member in memberVM.allMembers where member.hasName {
            guard let created = member.createdAt else { continue }
            // محاولة عدة أشكال
            let cleanDate = created.prefix(19)
            guard let date = dateFormatter.date(from: String(cleanDate)) else { continue }
            let c = calendar.dateComponents([.year, .month], from: date)
            guard let year = c.year, let month = c.month else { continue }
            perMonth[year * 100 + month, default: 0] += 1
        }

        // آخر 6 شهور
        return (0..<6).reversed().map { offset in
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: now) else {
                return ("", 0)
            }
            let components = calendar.dateComponents([.year, .month], from: monthStart)
            let year = components.year ?? 2026
            let month = components.month ?? 1
            let monthName = calendar.shortMonthSymbols[(month - 1) % 12]
            return (monthName, perMonth[year * 100 + month] ?? 0)
        }
    }

    private func monthlyGrowthSection(_ months: [(label: String, count: Int)]) -> some View {
        let sum = months.reduce(0) { $0 + $1.count }
        return AdminSectionCard(title: L10n.t("نمو الأعضاء", "Member Growth"),
                                tag: L10n.t("آخر ٦ أشهر", "Last 6 months")) {
            AnalyticsGrowthColumns(months: months, tint: pageTint)
    
            Text(L10n.t("أُضيف \(sum.formatted()) خلال آخر ٦ أشهر",
                        "\(sum.formatted()) added in the last 6 months"))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .monospacedDigit()
                .padding(.horizontal, DS.Spacing.xxs)
        }
    }

    // MARK: - Shared Components

    /// أعمدة متساوية لشبكات الأرقام
    private func tileColumns(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm, alignment: .top), count: count)
    }

    /// سطر رقم بجانب الحلقة: أيقونة صغيرة + العنوان + الرقم (+ النسبة) — مثل أسطر «حالة الإشعارات»
    private func valueLine(icon: String, tint: Color, label: String, value: Int, share: String? = nil) -> some View {
        HStack(spacing: DS.Spacing.xsm) {
            Image(dsSymbol: icon)
                .dsGlyph(DS.Glyph.xs)
                .foregroundColor(tint)
                .frame(width: DS.Icon.inline)
                .accessibilityHidden(true)
            Text(label)
                .dsFieldFont(.chip)
                .foregroundColor(DS.Color.fieldValue)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: DS.Spacing.xs)
            Text(value.formatted())
                .dsFont(.headline)
                .foregroundColor(DS.Color.fieldLabel)
                .monospacedDigit()
                .lineLimit(1)
            if let share {
                Text(share)
                    .dsFont(.micro)
                    .foregroundColor(DS.Color.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: DS.Icon.row, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - النِّسَب

private enum AnalyticsPercent {
    /// نسبة مقرّبة لأقرب عدد صحيح (٠…١٠٠)
    static func value(_ count: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(count) / Double(total) * 100).rounded())
    }

    /// «٤٨٪» — والنسبة الصغيرة غير الصفرية تظهر «أقل من ١٪» بدل «٠٪»
    static func text(_ count: Int, of total: Int) -> String {
        let fraction = total > 0 ? Double(count) / Double(total) : 0
        if count > 0 && fraction < 0.01 { return L10n.t("أقل من 1٪", "<1%") }
        let p = value(count, of: total)
        return L10n.t("\(p)٪", "\(p)%")
    }
}

// MARK: - صف توزيع

/// العنوان + الشريط الموحّد بنسبة العدد (`DSMeterBar` — يمتلئ مرة عند الظهور، ثابت مع «تقليل الحركة») + العدد والنسبة
private struct AnalyticsBarRow: View {
    let label: String
    let count: Int
    let total: Int
    let color: Color

    private var fraction: Double { total > 0 ? Double(count) / Double(total) : 0 }

    var body: some View {
        let share = AnalyticsPercent.text(count, of: total)

        HStack(spacing: DS.Spacing.sm) {
            Text(label)
                .dsFieldFont(.sectionTitle)
                .foregroundColor(DS.Color.fieldLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: DS.Chart.barLabelWidth, alignment: .leading)

            // الشريط الموحّد (الدفعة ١٠ — توزيع من ٤ أجزاء فأكثر: صفّ لكل جزء)
            DSMeterBar(progress: fraction, tint: color)

            // الرقم بخط واضح + النسبة تحته
            VStack(alignment: .trailing, spacing: 0) {
                Text(count.formatted())
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                    .monospacedDigit()
                Text(share)
                    .dsFont(.micro)
                    .foregroundColor(DS.Color.textTertiary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: DS.Chart.barValueWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("\(label): \(count.formatted())، \(share)",
                                   "\(label): \(count.formatted()), \(share)"))
    }
}

// MARK: - أعمدة نمو الأعضاء

/// عمود لكل شهر — الشهر الحالي بلون القسم كاملاً والأشهر السابقة أخفّ.
/// الأعمدة ترتفع بحركة ناعمة عند الظهور (ثابتة مع «تقليل الحركة»).
private struct AnalyticsGrowthColumns: View {
    let months: [(label: String, count: Int)]
    let tint: Color
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let maxCount = max(months.map(\.count).max() ?? 1, 1)

        HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
            ForEach(Array(months.enumerated()), id: \.offset) { index, month in
                let isCurrent = index == months.count - 1
                VStack(spacing: DS.Spacing.xs) {
                    Text(month.count.formatted())
                        .dsFieldFont(.badge)
                        .foregroundColor(isCurrent ? tint : DS.Color.fieldValue)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(LinearGradient(colors: [tint, tint.opacity(DS.Opacity.dimmed)],
                                             startPoint: .top, endPoint: .bottom))
                        .opacity(isCurrent ? 1 : DS.Opacity.disabled)
                        .frame(height: shown || reduceMotion
                               ? max(CGFloat(month.count) / CGFloat(maxCount) * DS.Chart.columnMaxHeight,
                                     DS.Chart.columnMinHeight)
                               : DS.Chart.columnMinHeight)

                    Text(month.label)
                        .dsFont(.micro)
                        .foregroundColor(isCurrent ? DS.Color.fieldLabel : DS.Color.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(month.label): \(month.count.formatted())")
            }
        }
        // ارتفاع ثابت — البطاقة لا تتمدّد أثناء ارتفاع الأعمدة
        .frame(maxWidth: .infinity, minHeight: DS.Chart.columnsAreaHeight, alignment: .bottom)
        .onAppear {
            guard !reduceMotion else { shown = true; return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.82).delay(0.25)) { shown = true }
        }
    }
}
