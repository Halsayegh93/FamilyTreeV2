import SwiftUI

// MARK: - Admin Analytics — إحصائيات متقدمة
//
// بتصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧): بطاقة رأس بلون بلاطة «إحصائيات متقدمة»
// (مجال «الشجرة والأعضاء») وأرقامها الحيّة ← «ملخص عام» بحلقة الأحياء ← التوزيعات بأشرطة ونِسَب
// ← شبكات أرقام `DSStatTile` ← «نمو الأعضاء» بالأعمدة ← الأخبار.
// كل رقم من البيانات المحمّلة أصلاً (الأعضاء، شجرة النساء، الأخبار) وبنفس الحسابات السابقة.
struct AdminAnalyticsView: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var newsVM: NewsViewModel

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

    /// أرقام شجرة النساء معروفة: محمّلة، أو انتهى جلبها بلا خطأ
    private var womenKnown: Bool {
        !womenData.isEmpty || (womenAttempted && !womenFailed && !womenLoading)
    }

    var body: some View {
        // نمو الأعضاء يُحسب مرة واحدة — لبطاقة الرأس («جديد هذا الشهر») ولقسم النمو
        let growth = monthlyGrowth()

        return ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) {
                    heroSection(newThisMonth: growth.last?.count ?? 0)

                    if totalMembers == 0 {
                        membersStateCard
                            .padding(.top, DS.Spacing.xs)
                            .dsStaggerIn(1)
                    } else {
                        // الوضع الأفقي: الأقسام على عمودين
                        AdaptiveCardStack(spacing: DS.Spacing.md, landscapeMinimum: 340) {
                            // ملخص عام
                            overviewSection

                            // توزيع الأدوار
                            rolesSection

                            // توزيع الجنس
                            genderSection

                            // شجرة النساء
                            womenSection

                            // الحالة الاجتماعية
                            maritalSection

                            // الفئات العمرية
                            ageGroupsSection

                            // نظرة على الشجرة (أجيال، متوسط الأبناء، أكبر عائلة)
                            treeInsightsSection

                            // إحصائيات الوفيات (متوسط العمر عند الوفاة)
                            if deceasedMembers.count > 0 {
                                deceasedInsightsSection
                            }

                            // نمو الأعضاء الشهري
                            monthlyGrowthSection(growth)

                            // الأخبار
                            newsSection
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.xxxl)
            }
        }
        .navigationTitle(L10n.t("إحصائيات متقدمة", "Analytics"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            // جلب بيانات شجرة النساء إن لم تكن محمّلة (كاش التبويب يغني عن الجلب غالباً)
            if womenData.isEmpty { await loadWomen() }
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

    // MARK: - بطاقة الرأس

    /// ٣ أرقام حيّة من البيانات المحمّلة أصلاً: أفراد العائلة (نفس «إجمالي» الملخص)، نسبة الأحياء،
    /// ومن أُضيف هذا الشهر (آخر عمود في «نمو الأعضاء») — «—» قبل تحميل الأعضاء.
    private func heroSection(newThisMonth: Int) -> some View {
        let ready = totalMembers > 0
        let alivePct = AnalyticsPercent.value(activeMembers.count, of: totalMembers)
        return DSPageHero(
            title: L10n.t("إحصائيات متقدمة", "Analytics"),
            subtitle: L10n.t("العائلة بالأرقام — الأدوار والأعمار والنمو",
                             "The family in numbers — roles, ages and growth"),
            icon: "chart.bar.xaxis",
            tint: pageTint,
            stats: [
                DSHeroStat(value: ready ? totalMembers.formatted() : "—",
                           label: L10n.t("أفراد العائلة", "Members"), icon: "person.3.fill"),
                DSHeroStat(value: ready ? L10n.t("\(alivePct)٪", "\(alivePct)%") : "—",
                           label: L10n.t("أحياء", "Alive"), icon: "heart.fill"),
                DSHeroStat(value: ready ? signed(newThisMonth) : "—",
                           label: L10n.t("جديد هذا الشهر", "New this month"),
                           icon: "chart.line.uptrend.xyaxis")
            ]
        )
    }

    /// «+١٢» — الإشارة قبل الرقم في السطر العربي أيضاً
    private func signed(_ n: Int) -> String {
        n > 0 ? "\u{2066}+\(n.formatted())\u{2069}" : "0"
    }

    // MARK: - حالة الأعضاء (قبل الأقسام)

    /// لا أعضاء محسوبين: فشل التحميل (مع إعادة المحاولة) · جارٍ التحميل · لا بيانات كافية
    @ViewBuilder
    private var membersStateCard: some View {
        if memberVM.membersLoadFailed {
            SysStateCard(icon: "wifi.exclamationmark",
                         title: L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                         hint: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                         tint: DS.Color.error,
                         actionTitle: L10n.t("إعادة المحاولة", "Retry"),
                         action: { Task { await memberVM.fetchAllMembers(force: true) } })
        } else if memberVM.allMembers.isEmpty {
            SysStateCard(icon: "chart.bar.xaxis",
                         title: L10n.t("جارٍ تحميل الأعضاء…", "Loading members…"),
                         tint: pageTint,
                         isLoading: true)
        } else {
            SysStateCard(icon: "chart.bar.xaxis",
                         title: L10n.t("لا توجد بيانات كافية", "No data available"),
                         hint: L10n.t("أضف أعضاء للشجرة لعرض الإحصائيات", "Add members to the tree to see analytics"),
                         tint: pageTint)
        }
    }

    // MARK: - Overview — ملخص عام

    /// حلقة نسبة الأحياء + الإجمالي والأحياء والمتوفين (نفس أرقام الملخص السابق)
    private var overviewSection: some View {
        let total = totalMembers
        let alive = activeMembers.count
        let deceased = deceasedMembers.count
        let pct = AnalyticsPercent.value(alive, of: total)

        return DSComposerSection(title: L10n.t("ملخص عام", "Overview"),
                                 icon: "chart.bar.fill",
                                 tint: pageTint,
                                 trailing: L10n.t("\(total.formatted()) فرد", "\(total.formatted()) members"),
                                 index: 1) {
            HStack(spacing: DS.Spacing.md) {
                SysRing(progress: total > 0 ? Double(alive) / Double(total) : 0,
                        tint: DS.Color.success, lineWidth: 8, size: 92) {
                    ringCenter(value: L10n.t("\(pct)٪", "\(pct)%"), caption: L10n.t("أحياء", "Alive"))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.t("الأحياء \(pct)٪", "Alive \(pct)%"))

                VStack(spacing: 6) {
                    valueLine(icon: "person.2.fill", tint: pageTint,
                              label: L10n.t("إجمالي", "Total"), value: total)
                    valueLine(icon: "heart.fill", tint: DS.Color.success,
                              label: L10n.t("أحياء", "Alive"), value: alive)
                    valueLine(icon: "heart.slash.fill", tint: DS.Color.textSecondary,
                              label: L10n.t("متوفين", "Deceased"), value: deceased)
                }
            }
            .dsRowBox()
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

        return DSComposerSection(title: L10n.t("توزيع الأدوار (الأحياء)", "Roles (alive)"),
                                 icon: "shield.fill",
                                 tint: pageTint,
                                 trailing: L10n.t("\(sum.formatted()) حي", "\(sum.formatted()) alive"),
                                 index: 2) {
            VStack(spacing: 10) {
                AnalyticsBarRow(label: L10n.t("مدير", "Admin"), count: admins, total: total,
                                color: FamilyMember.UserRole.admin.color)
                AnalyticsBarRow(label: L10n.t("مراقب", "Monitor"), count: monitors, total: total,
                                color: FamilyMember.UserRole.monitor.color)
                AnalyticsBarRow(label: L10n.t("مشرف", "Supervisor"), count: supervisors, total: total,
                                color: FamilyMember.UserRole.supervisor.color)
                AnalyticsBarRow(label: L10n.t("عضو", "Member"), count: members, total: total,
                                color: FamilyMember.UserRole.member.color)
            }
            .dsRowBox()
        }
    }

    // MARK: - Gender Distribution
    private var genderSection: some View {
        // الرجال: أحياء شجرة الرجال؛ النساء: أحياء شجرة النساء (منفصلة في جدول آخر)
        let males = activeMembers.count
        let females = womenData.filter { $0.isFemale && $0.isDeceased != true }.count
        let total = max(males + females, 1)
        let known = womenKnown

        return DSComposerSection(title: L10n.t("توزيع الجنس (الأحياء)", "Gender (alive)"),
                                 icon: "person.2.circle.fill",
                                 tint: pageTint,
                                 trailing: known ? L10n.t("\((males + females).formatted()) حي",
                                                          "\((males + females).formatted()) alive") : nil,
                                 index: 3) {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    // عدد الذكور معروف دائماً (من الأعضاء) — النسبة فقط تنتظر شجرة النساء
                    genderBlock(title: L10n.t("ذكور", "Males"), count: males, total: total,
                                color: DS.Color.primary, alignment: .leading,
                                countKnown: true, shareKnown: known)
                    Spacer(minLength: 0)
                    genderBlock(title: L10n.t("إناث", "Females"), count: females, total: total,
                                color: DS.Color.female, alignment: .trailing,
                                countKnown: known, shareKnown: known)
                }
                // لمحة النسبة — بعد معرفة أرقام شجرة النساء (قبلها تبدو ١٠٠٪ ذكوراً)
                if known {
                    SysDistributionBar(segments: [
                        .init(id: "male", value: males, tint: DS.Color.primary),
                        .init(id: "female", value: females, tint: DS.Color.female)
                    ], height: 12)
                }
            }
            .dsRowBox()
        }
    }

    /// عدد جنس واحد: نقطة اللون + العنوان، الرقم كبيراً، والنسبة تحته
    private func genderBlock(title: String, count: Int, total: Int, color: Color,
                             alignment: HorizontalAlignment, countKnown: Bool, shareKnown: Bool) -> some View {
        let value = countKnown ? count.formatted() : "—"
        let share = shareKnown ? AnalyticsPercent.text(count, of: total) : "—"
        return VStack(alignment: alignment, spacing: 1) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                    .dsFieldFont(12, weight: .bold)
                    .foregroundColor(DS.Color.fieldLabel)
            }
            Text(value)
                .font(DS.Font.plex(20, weight: .bold))
                .foregroundColor(DS.Color.fieldLabel)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(share)
                .dsFieldFont(11, weight: .semibold)
                .foregroundColor(DS.Color.fieldValue)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("\(title): \(value)، \(share)", "\(title): \(value), \(share)"))
    }

    // MARK: - Women Tree — شجرة النساء
    private var womenSection: some View {
        let women = womenData.filter { $0.isFemale }
        let wives = women.filter { $0.husbandId != nil }.count
        let daughters = women.filter { $0.husbandId == nil }.count
        let deceasedW = women.filter { $0.isDeceased == true }.count
        let aliveW = women.count - deceasedW
        let linked = women.filter { WomenStore.linkedUserByWoman[$0.id] != nil }.count

        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SysSectionTitle(title: L10n.t("شجرة النساء", "Women Tree"),
                            icon: "figure.dress.line.vertical.figure",
                            tint: pageTint)

            if women.isEmpty {
                womenStateCard
            } else {
                LazyVGrid(columns: tileColumns(3), spacing: DS.Spacing.sm) {
                    DSStatTile(value: women.count.formatted(), label: L10n.t("إجمالي النساء", "Total women"),
                               icon: "person.fill", tint: DS.Color.female)
                    DSStatTile(value: daughters.formatted(), label: L10n.t("بنات العائلة", "Daughters"),
                               icon: "figure.and.child.holdinghands", tint: DS.Color.info)
                    DSStatTile(value: wives.formatted(), label: L10n.t("زوجات", "Wives"),
                               icon: "heart.fill", tint: DS.Color.accent)
                    DSStatTile(value: aliveW.formatted(), label: L10n.t("على قيد الحياة", "Alive"),
                               icon: "heart.circle.fill", tint: DS.Color.success)
                    DSStatTile(value: deceasedW.formatted(), label: L10n.t("متوفيات", "Deceased"),
                               icon: "heart.slash.fill", tint: DS.Color.femaleDeceased)
                    DSStatTile(value: linked.formatted(), label: L10n.t("مرتبطة بحساب", "Linked accounts"),
                               icon: "link.circle.fill", tint: DS.Color.warning)
                }
            }
        }
        .dsStaggerIn(4)
    }

    /// شجرة النساء بلا أرقام بعد: خطأ (مع إعادة نفس الجلب) · تحميل · لا بيانات
    @ViewBuilder
    private var womenStateCard: some View {
        if womenFailed {
            SysStateCard(icon: "wifi.exclamationmark",
                         title: L10n.t("تعذّر تحميل بيانات النساء", "Couldn't load women data"),
                         hint: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                         tint: DS.Color.error,
                         actionTitle: L10n.t("إعادة المحاولة", "Retry"),
                         action: { Task { await loadWomen() } })
        } else if womenLoading || !womenAttempted {
            SysStateCard(icon: "figure.dress.line.vertical.figure",
                         title: L10n.t("جاري تحميل بيانات النساء…", "Loading women data…"),
                         tint: pageTint,
                         isLoading: true)
        } else {
            SysStateCard(icon: "figure.dress.line.vertical.figure",
                         title: L10n.t("لا توجد بيانات بعد", "No data yet"),
                         hint: L10n.t("تظهر هنا أرقام شجرة النساء بعد إضافتهن",
                                      "Women tree numbers appear here once they're added"),
                         tint: DS.Color.textTertiary)
        }
    }

    // MARK: - Marital Status — الحالة الاجتماعية
    private var maritalSection: some View {
        let pool = activeMembers
        let married = pool.filter { $0.isMarried == true }.count
        let single = pool.filter { $0.isMarried == false }.count
        let unknown = pool.count - married - single
        let total = max(pool.count, 1)
        let pct = AnalyticsPercent.value(married, of: total)

        return DSComposerSection(title: L10n.t("الحالة الاجتماعية", "Marital Status"),
                                 icon: "heart.circle.fill",
                                 tint: pageTint,
                                 trailing: L10n.t("الأحياء", "Alive"),
                                 index: 5) {
            HStack(spacing: DS.Spacing.md) {
                SysRing(progress: Double(married) / Double(total),
                        tint: DS.Color.success, lineWidth: 8, size: 84) {
                    ringCenter(value: L10n.t("\(pct)٪", "\(pct)%"), caption: L10n.t("متزوج", "Married"), size: 18)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.t("متزوج \(pct)٪", "Married \(pct)%"))

                VStack(spacing: 6) {
                    valueLine(icon: "heart.fill", tint: DS.Color.success,
                              label: L10n.t("متزوج", "Married"), value: married,
                              share: AnalyticsPercent.text(married, of: total))
                    // is_married افتراضياً false — فأغلبهم لم يحدّدوا حالتهم
                    valueLine(icon: "person.fill", tint: DS.Color.info,
                              label: L10n.t("أعزب / غير محدد", "Single / not set"), value: single,
                              share: AnalyticsPercent.text(single, of: total))
                    if unknown > 0 {
                        valueLine(icon: "questionmark.circle.fill", tint: DS.Color.textTertiary,
                                  label: L10n.t("غير محدد", "Unspecified"), value: unknown,
                                  share: AnalyticsPercent.text(unknown, of: total))
                    }
                }
            }
            .dsRowBox()
        }
    }

    // MARK: - Tree Insights — نظرة على الشجرة
    private var treeInsightsSection: some View {
        // بنية الشجرة محسوبة على كل الأعضاء للحفاظ على سلاسل النسب كاملة.
        let all = memberVM.allMembers
        let ids = Set(all.map(\.id))

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

        // عدد الأجيال = أقصى عمق من الجذور للأسفل (memoized).
        let generations = treeDepth(all: all, ids: ids, childIndex: buildChildIndex(all))

        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SysSectionTitle(title: L10n.t("نظرة على الشجرة", "Tree Insights"),
                            icon: "tree.fill",
                            tint: pageTint)

            LazyVGrid(columns: tileColumns(3), spacing: DS.Spacing.sm) {
                DSStatTile(value: generations.formatted(), label: L10n.t("عدد الأجيال", "Generations"),
                           icon: "square.stack.3d.up.fill", tint: DS.Color.accent)
                DSStatTile(value: parentsCount.formatted(), label: L10n.t("لديهم أبناء", "Parents"),
                           icon: "person.2.fill", tint: DS.Color.info)
                DSStatTile(value: String(format: "%.1f", avgChildren), label: L10n.t("متوسط الأبناء", "Avg. children"),
                           icon: "chart.bar.fill", tint: DS.Color.warning)
                DSStatTile(value: maxChildren.formatted(), label: L10n.t("أكبر عائلة", "Largest family"),
                           icon: "crown.fill", tint: DS.Color.secondary)
                DSStatTile(value: leaves.formatted(), label: L10n.t("بدون أبناء", "No children"),
                           icon: "leaf.fill", tint: DS.Color.success)
                DSStatTile(value: totalChildren.formatted(), label: L10n.t("روابط نسب", "Parent links"),
                           icon: "arrow.triangle.branch", tint: DS.Color.primary)
            }
        }
        .dsStaggerIn(6)
    }

    /// فهرس الأبناء (أب → معرّفات أبنائه) لحساب العمق.
    private func buildChildIndex(_ all: [FamilyMember]) -> [UUID: [UUID]] {
        var index: [UUID: [UUID]] = [:]
        for m in all {
            if let f = m.fatherId { index[f, default: []].append(m.id) }
        }
        return index
    }

    /// أقصى عمق للشجرة بدءاً من الجذور (عضو بلا أب أو أبوه خارج المجموعة).
    private func treeDepth(all: [FamilyMember], ids: Set<UUID>, childIndex: [UUID: [UUID]]) -> Int {
        var memo: [UUID: Int] = [:]
        var visiting: Set<UUID> = []

        func depth(_ id: UUID) -> Int {
            if let d = memo[id] { return d }
            if visiting.contains(id) { return 1 } // حماية ضد الدوائر
            visiting.insert(id)
            let kids = childIndex[id] ?? []
            let d = kids.isEmpty ? 1 : 1 + (kids.map(depth).max() ?? 0)
            visiting.remove(id)
            memo[id] = d
            return d
        }

        let roots = all.filter { m in
            guard let f = m.fatherId else { return true }
            return !ids.contains(f)
        }
        return roots.map { depth($0.id) }.max() ?? 0
    }

    // MARK: - Deceased Insights — إحصائيات الوفيات
    private var deceasedInsightsSection: some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        let deceased = deceasedMembers

        // الأعمار عند الوفاة (لمن عنده تاريخ ميلاد ووفاة).
        let lifespans: [Int] = deceased.compactMap { m in
            guard let bStr = m.birthDate, let dStr = m.deathDate,
                  let b = formatter.date(from: String(bStr.prefix(10))),
                  let d = formatter.date(from: String(dStr.prefix(10))),
                  d >= b else { return nil }
            return calendar.dateComponents([.year], from: b, to: d).year
        }
        let avgLifespan = lifespans.isEmpty ? 0 : lifespans.reduce(0, +) / lifespans.count
        let oldest = lifespans.max() ?? 0
        let ratio = totalMembers > 0
            ? Int((Double(deceased.count) / Double(totalMembers) * 100).rounded())
            : 0

        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SysSectionTitle(title: L10n.t("إحصائيات الوفيات", "Deceased Insights"),
                            icon: "hourglass",
                            tint: pageTint,
                            trailing: L10n.t("\(deceased.count.formatted()) متوفى",
                                             "\(deceased.count.formatted()) deceased"))

            LazyVGrid(columns: tileColumns(3), spacing: DS.Spacing.sm) {
                DSStatTile(value: avgLifespan > 0 ? "\(avgLifespan)" : "—",
                           label: L10n.t("متوسط العمر", "Avg. lifespan"),
                           icon: "hourglass.bottomhalf.filled", tint: DS.Color.warning)
                DSStatTile(value: oldest > 0 ? "\(oldest)" : "—",
                           label: L10n.t("أطول عمر", "Longest life"),
                           icon: "star.fill", tint: DS.Color.success)
                DSStatTile(value: L10n.t("\(ratio)٪", "\(ratio)%"),
                           label: L10n.t("نسبة المتوفين", "Deceased %"),
                           icon: "heart.slash.fill", tint: DS.Color.textSecondary)
            }

            if lifespans.count < deceased.count {
                Text(L10n.t(
                    "محسوبة من \(lifespans.count) متوفّى لديهم تاريخ ميلاد ووفاة",
                    "Based on \(lifespans.count) deceased with both birth & death dates"
                ))
                .font(DS.Font.plex(11, weight: .medium))
                .foregroundColor(DS.Color.textTertiary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
            }
        }
        .dsStaggerIn(6)
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
        return DSComposerSection(title: L10n.t("الفئات العمرية", "Age Groups"),
                                 icon: "calendar.circle.fill",
                                 tint: pageTint,
                                 trailing: L10n.t("الأحياء", "Alive"),
                                 index: 6) {
            VStack(spacing: 10) {
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
            .dsRowBox()
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
        for member in memberVM.allMembers {
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
        return DSComposerSection(title: L10n.t("نمو الأعضاء", "Member Growth"),
                                 icon: "chart.line.uptrend.xyaxis",
                                 tint: pageTint,
                                 trailing: L10n.t("آخر ٦ أشهر", "Last 6 months"),
                                 index: 6) {
            AnalyticsGrowthColumns(months: months, tint: pageTint)
                .dsRowBox()

            Text(L10n.t("أُضيف \(sum.formatted()) خلال آخر ٦ أشهر",
                        "\(sum.formatted()) added in the last 6 months"))
                .font(DS.Font.plex(11, weight: .medium))
                .foregroundColor(DS.Color.textTertiary)
                .monospacedDigit()
                .padding(.horizontal, 2)
        }
    }

    // MARK: - News Stats
    private var newsSection: some View {
        // الإجمالي من السيرفر — المحمَّل وحده ٢٥ منشوراً فقط
        let totalNews = max(newsVM.totalNewsCount, newsVM.allNews.count)
        let approvedNews = newsVM.allNews.filter { $0.approval_status == "approved" }.count
        let pendingNews = newsVM.pendingNewsRequests.count
        let withImages = newsVM.allNews.filter { !($0.image_urls ?? []).isEmpty }.count
        let withPolls = newsVM.allNews.filter { $0.hasPoll }.count

        // الأخبار من مجال «المحتوى والبلاغات» — عنوانها بلونه
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SysSectionTitle(title: L10n.t("إحصائيات الأخبار", "News Statistics"),
                            icon: "newspaper.fill",
                            tint: DS.Color.composerLibrary)

            LazyVGrid(columns: tileColumns(3), spacing: DS.Spacing.sm) {
                DSStatTile(value: totalNews.formatted(), label: L10n.t("إجمالي", "Total"),
                           icon: "newspaper.fill", tint: DS.Color.primary)
                DSStatTile(value: approvedNews.formatted(), label: L10n.t("منشور", "Published"),
                           icon: "checkmark.seal.fill", tint: DS.Color.success)
                DSStatTile(value: pendingNews.formatted(), label: L10n.t("معلق", "Pending"),
                           icon: "clock.fill", tint: DS.Color.warning)
            }

            LazyVGrid(columns: tileColumns(2), spacing: DS.Spacing.sm) {
                DSStatTile(value: withImages.formatted(), label: L10n.t("بصور", "With Images"),
                           icon: "photo.fill.on.rectangle.fill", tint: DS.Color.info)
                DSStatTile(value: withPolls.formatted(), label: L10n.t("باستطلاع", "With Polls"),
                           icon: "checklist", tint: DS.Color.accent)
            }
        }
        .dsStaggerIn(6)
    }

    // MARK: - Shared Components

    /// أعمدة متساوية لشبكات الأرقام
    private func tileColumns(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm, alignment: .top), count: count)
    }

    /// النسبة داخل الحلقة: الرقم كبيراً وتحته ما يعنيه
    private func ringCenter(value: String, caption: String, size: CGFloat = 20) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(DS.Font.plex(size, weight: .bold))
                .foregroundColor(DS.Color.fieldLabel)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(DS.Font.plex(9.5, weight: .semibold))
                .foregroundColor(DS.Color.fieldValue)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
    }

    /// سطر رقم بجانب الحلقة: أيقونة صغيرة + العنوان + الرقم (+ النسبة) — مثل أسطر «حالة الإشعارات»
    private func valueLine(icon: String, tint: Color, label: String, value: Int, share: String? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(label)
                .dsFieldFont(12, weight: .semibold)
                .foregroundColor(DS.Color.fieldValue)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(value.formatted())
                .font(DS.Font.plex(15, weight: .bold))
                .foregroundColor(DS.Color.fieldLabel)
                .monospacedDigit()
                .lineLimit(1)
            if let share {
                Text(share)
                    .font(DS.Font.plex(10.5, weight: .semibold))
                    .foregroundColor(DS.Color.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: 32, alignment: .trailing)
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

/// العنوان + شريط يمتلئ بنسبة العدد + العدد والنسبة. الشريط يمتلئ بحركة ناعمة عند الظهور
/// (ثابت مع «تقليل الحركة»).
private struct AnalyticsBarRow: View {
    let label: String
    let count: Int
    let total: Int
    let color: Color
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { total > 0 ? Double(count) / Double(total) : 0 }

    var body: some View {
        let share = AnalyticsPercent.text(count, of: total)

        HStack(spacing: DS.Spacing.sm) {
            Text(label)
                .dsFieldFont(12.5, weight: .bold)
                .foregroundColor(DS.Color.fieldLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 92, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.14))
                    Capsule()
                        .fill(color)
                        .frame(width: shown || reduceMotion
                               ? max(geo.size.width * fraction, count > 0 ? 6 : 0)
                               : 0)
                }
            }
            .frame(height: 10)

            // الرقم بخط واضح + النسبة تحته
            VStack(alignment: .trailing, spacing: 0) {
                Text(count.formatted())
                    .dsFieldFont(14, weight: .bold)
                    .foregroundColor(DS.Color.fieldLabel)
                    .monospacedDigit()
                Text(share)
                    .font(DS.Font.plex(10, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 58, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("\(label): \(count.formatted())، \(share)",
                                   "\(label): \(count.formatted()), \(share)"))
        .onAppear {
            guard !reduceMotion else { shown = true; return }
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) { shown = true }
        }
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
                        .dsFieldFont(11, weight: .bold)
                        .foregroundColor(isCurrent ? tint : DS.Color.fieldValue)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(LinearGradient(colors: [tint, tint.opacity(0.7)],
                                             startPoint: .top, endPoint: .bottom))
                        .opacity(isCurrent ? 1 : 0.5)
                        .frame(height: shown || reduceMotion
                               ? max(CGFloat(month.count) / CGFloat(maxCount) * 100, 4)
                               : 4)

                    Text(month.label)
                        .font(DS.Font.plex(10.5, weight: .semibold))
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
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .bottom)
        .onAppear {
            guard !reduceMotion else { shown = true; return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.82).delay(0.25)) { shown = true }
        }
    }
}
