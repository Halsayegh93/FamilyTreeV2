import SwiftUI

// MARK: - Admin Analytics — إحصائيات متقدمة
struct AdminAnalyticsView: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var newsVM: NewsViewModel

    /// بيانات شجرة النساء (women_members) — كاش فوري ثم جلب عند الحاجة.
    @State private var womenData: [FamilyMember] = WomenStore.cache

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
        ZStack {
            DS.Color.background.ignoresSafeArea()

            if totalMembers == 0 {
                VStack(spacing: DS.Spacing.lg) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(DS.Font.scaled(48, weight: .light))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(L10n.t("لا توجد بيانات كافية", "No data available"))
                        .font(DS.Font.title3)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(L10n.t("أضف أعضاء للشجرة لعرض الإحصائيات", "Add members to the tree to see analytics"))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(DS.Spacing.xl)
            } else {

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.xxl) {
                    // الوضع الأفقي: الأقسام على عمودين
                    AdaptiveCardStack(spacing: DS.Spacing.xxl, landscapeMinimum: 340) {
                    // ملخص عام
                    overviewSection
                        .padding(.top, DS.Spacing.md)

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
                    monthlyGrowthSection

                    // الأخبار
                    newsSection
                    }

                    Spacer(minLength: DS.Spacing.xxxl)
                }
            }

            } // end else totalMembers > 0
        }
        .navigationTitle(L10n.t("إحصائيات متقدمة", "Analytics"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            // جلب بيانات شجرة النساء إن لم تكن محمّلة (كاش التبويب يغني عن الجلب غالباً)
            if womenData.isEmpty, let fetched = try? await WomenStore.fetch() {
                womenData = fetched
            }
        }
    }

    // MARK: - Women Tree — شجرة النساء
    private var womenSection: some View {
        let women = womenData.filter { $0.isFemale }
        let wives = women.filter { $0.husbandId != nil }.count
        let daughters = women.filter { $0.husbandId == nil }.count
        let deceasedW = women.filter { $0.isDeceased == true }.count
        let aliveW = women.count - deceasedW
        let linked = women.filter { WomenStore.linkedUserByWoman[$0.id] != nil }.count

        return DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("شجرة النساء", "Women Tree"),
                icon: "figure.dress.line.vertical.figure",
                iconColor: DS.Color.neonPink
            )

            if women.isEmpty {
                Text(L10n.t("جاري تحميل بيانات النساء…", "Loading women data…"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(DS.Spacing.lg)
            } else {
                let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                    overviewCell(
                        value: "\(women.count)",
                        label: L10n.t("إجمالي النساء", "Total women"),
                        icon: "person.fill",
                        color: DS.Color.neonPink
                    )
                    overviewCell(
                        value: "\(daughters)",
                        label: L10n.t("بنات العائلة", "Daughters"),
                        icon: "figure.child",
                        color: DS.Color.info
                    )
                    overviewCell(
                        value: "\(wives)",
                        label: L10n.t("زوجات", "Wives"),
                        icon: "heart.fill",
                        color: DS.Color.accent
                    )
                    overviewCell(
                        value: "\(aliveW)",
                        label: L10n.t("على قيد الحياة", "Alive"),
                        icon: "heart.circle.fill",
                        color: DS.Color.success
                    )
                    overviewCell(
                        value: "\(deceasedW)",
                        label: L10n.t("متوفيات", "Deceased"),
                        icon: "heart.slash.fill",
                        color: DS.Color.error
                    )
                    overviewCell(
                        value: "\(linked)",
                        label: L10n.t("مرتبطة بحساب", "Linked accounts"),
                        icon: "link.circle.fill",
                        color: DS.Color.warning
                    )
                }
                .padding(DS.Spacing.md)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Overview
    private var overviewSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("ملخص عام", "Overview"),
                icon: "chart.bar.fill",
                iconColor: DS.Color.secondary
            )

            let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                overviewCell(
                    value: "\(totalMembers)",
                    label: L10n.t("إجمالي", "Total"),
                    icon: "person.2.fill",
                    color: DS.Color.secondary
                )
                overviewCell(
                    value: "\(activeMembers.count)",
                    label: L10n.t("أحياء", "Alive"),
                    icon: "heart.fill",
                    color: DS.Color.success
                )
                overviewCell(
                    value: "\(deceasedMembers.count)",
                    label: L10n.t("متوفين", "Deceased"),
                    icon: "heart.slash.fill",
                    color: DS.Color.error
                )
            }
            .padding(DS.Spacing.md)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func overviewCell(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(DS.Font.scaled(15, weight: .bold))
                    .foregroundColor(color)
            }
            Text(value)
                .font(DS.Font.title2)
                .fontWeight(.black)
                .foregroundColor(DS.Color.textPrimary)
            Text(label)
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - Roles Distribution
    private var rolesSection: some View {
        let pool = countableMembers
        let admins = pool.filter { $0.role == .owner || $0.role == .admin }.count
        let monitors = pool.filter { $0.role == .monitor }.count
        let supervisors = pool.filter { $0.role == .supervisor }.count
        let members = pool.filter { $0.role == .member }.count
        let total = max(admins + monitors + supervisors + members, 1)

        return DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("توزيع الأدوار", "Roles Distribution"),
                icon: "shield.fill",
                iconColor: DS.Color.warning
            )

            VStack(spacing: DS.Spacing.md) {
                barRow(
                    label: L10n.t("مدير", "Admin"),
                    count: admins,
                    total: total,
                    color: FamilyMember.UserRole.admin.color
                )
                barRow(
                    label: L10n.t("مراقب", "Monitor"),
                    count: monitors,
                    total: total,
                    color: FamilyMember.UserRole.monitor.color
                )
                barRow(
                    label: L10n.t("مشرف", "Supervisor"),
                    count: supervisors,
                    total: total,
                    color: FamilyMember.UserRole.supervisor.color
                )
                barRow(
                    label: L10n.t("عضو", "Member"),
                    count: members,
                    total: total,
                    color: FamilyMember.UserRole.member.color
                )
            }
            .padding(DS.Spacing.lg)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Gender Distribution
    private var genderSection: some View {
        let males = activeMembers.filter { ($0.gender ?? "").lowercased() == "male" }.count
        let females = activeMembers.filter { ($0.gender ?? "").lowercased() == "female" }.count
        let unknown = activeMembers.count - males - females
        let total = max(activeMembers.count, 1)

        return DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("توزيع الجنس", "Gender Distribution"),
                icon: "person.2.circle.fill",
                iconColor: DS.Color.info
            )

            VStack(spacing: DS.Spacing.md) {
                barRow(
                    label: L10n.t("ذكور", "Males"),
                    count: males,
                    total: total,
                    color: DS.Color.info
                )
                barRow(
                    label: L10n.t("إناث", "Females"),
                    count: females,
                    total: total,
                    color: DS.Color.neonPink
                )
                if unknown > 0 {
                    barRow(
                        label: L10n.t("غير محدد", "Unspecified"),
                        count: unknown,
                        total: total,
                        color: DS.Color.textTertiary
                    )
                }
            }
            .padding(DS.Spacing.lg)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Marital Status — الحالة الاجتماعية
    private var maritalSection: some View {
        let pool = activeMembers
        let married = pool.filter { $0.isMarried == true }.count
        let single = pool.filter { $0.isMarried == false }.count
        let unknown = pool.count - married - single
        let total = max(pool.count, 1)

        return DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("الحالة الاجتماعية", "Marital Status"),
                icon: "heart.circle.fill",
                iconColor: DS.Color.neonPink
            )
            VStack(spacing: DS.Spacing.md) {
                barRow(label: L10n.t("متزوج", "Married"), count: married, total: total, color: DS.Color.success)
                barRow(label: L10n.t("أعزب", "Single"), count: single, total: total, color: DS.Color.info)
                if unknown > 0 {
                    barRow(label: L10n.t("غير محدد", "Unspecified"), count: unknown, total: total, color: DS.Color.textTertiary)
                }
            }
            .padding(DS.Spacing.lg)
        }
        .padding(.horizontal, DS.Spacing.lg)
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

        return DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("نظرة على الشجرة", "Tree Insights"),
                icon: "tree.fill",
                iconColor: DS.Color.success
            )
            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                overviewCell(value: "\(generations)", label: L10n.t("عدد الأجيال", "Generations"), icon: "square.stack.3d.up.fill", color: DS.Color.accent)
                overviewCell(value: "\(parentsCount)", label: L10n.t("لديهم أبناء", "Parents"), icon: "person.2.fill", color: DS.Color.info)
                overviewCell(value: String(format: "%.1f", avgChildren), label: L10n.t("متوسط الأبناء", "Avg. children"), icon: "chart.bar.fill", color: DS.Color.warning)
                overviewCell(value: "\(maxChildren)", label: L10n.t("أكبر عائلة", "Largest family"), icon: "crown.fill", color: DS.Color.secondary)
                overviewCell(value: "\(leaves)", label: L10n.t("بدون أبناء", "No children"), icon: "leaf.fill", color: DS.Color.success)
                overviewCell(value: "\(totalChildren)", label: L10n.t("روابط نسب", "Parent links"), icon: "arrow.triangle.branch", color: DS.Color.primary)
            }
            .padding(DS.Spacing.md)
        }
        .padding(.horizontal, DS.Spacing.lg)
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

        // الأعمار عند الوفاة (لمن عنده تاريخ ميلاد ووفاة).
        let lifespans: [Int] = deceasedMembers.compactMap { m in
            guard let bStr = m.birthDate, let dStr = m.deathDate,
                  let b = formatter.date(from: String(bStr.prefix(10))),
                  let d = formatter.date(from: String(dStr.prefix(10))),
                  d >= b else { return nil }
            return calendar.dateComponents([.year], from: b, to: d).year
        }
        let avgLifespan = lifespans.isEmpty ? 0 : lifespans.reduce(0, +) / lifespans.count
        let oldest = lifespans.max() ?? 0
        let ratio = totalMembers > 0
            ? Int((Double(deceasedMembers.count) / Double(totalMembers) * 100).rounded())
            : 0

        return DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("إحصائيات الوفيات", "Deceased Insights"),
                icon: "hourglass",
                iconColor: DS.Color.error
            )
            let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                miniStat(value: avgLifespan > 0 ? "\(avgLifespan)" : "—", label: L10n.t("متوسط العمر", "Avg. lifespan"), color: DS.Color.warning)
                miniStat(value: oldest > 0 ? "\(oldest)" : "—", label: L10n.t("أطول عمر", "Longest life"), color: DS.Color.success)
                miniStat(value: "\(ratio)%", label: L10n.t("نسبة المتوفين", "Deceased %"), color: DS.Color.error)
            }
            .padding(DS.Spacing.lg)

            if lifespans.count < deceasedMembers.count {
                Text(L10n.t(
                    "محسوبة من \(lifespans.count) متوفّى لديهم تاريخ ميلاد ووفاة",
                    "Based on \(lifespans.count) deceased with both birth & death dates"
                ))
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textTertiary)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.md)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Age Groups
    private var ageGroupsSection: some View {
        let calendar = Calendar.current
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let ages: [Int] = activeMembers.compactMap { member in
            guard let birthStr = member.birthDate,
                  let birthDate = dateFormatter.date(from: birthStr) else { return nil }
            return calendar.dateComponents([.year], from: birthDate, to: now).year
        }

        let under18 = ages.filter { $0 < 18 }.count
        let age18to30 = ages.filter { $0 >= 18 && $0 < 30 }.count
        let age30to50 = ages.filter { $0 >= 30 && $0 < 50 }.count
        let age50to70 = ages.filter { $0 >= 50 && $0 < 70 }.count
        let over70 = ages.filter { $0 >= 70 }.count
        let noAge = activeMembers.count - ages.count
        let total = max(activeMembers.count, 1)

        return DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("الفئات العمرية", "Age Groups"),
                icon: "calendar.circle.fill",
                iconColor: DS.Color.success
            )

            VStack(spacing: DS.Spacing.md) {
                barRow(label: L10n.t("أقل من ١٨", "Under 18"), count: under18, total: total, color: DS.Color.neonCyan)
                barRow(label: "18–29", count: age18to30, total: total, color: DS.Color.info)
                barRow(label: "30–49", count: age30to50, total: total, color: DS.Color.success)
                barRow(label: "50–69", count: age50to70, total: total, color: DS.Color.warning)
                barRow(label: L10n.t("٧٠+", "70+"), count: over70, total: total, color: DS.Color.error)
                if noAge > 0 {
                    barRow(label: L10n.t("بدون تاريخ", "No date"), count: noAge, total: total, color: DS.Color.textTertiary)
                }
            }
            .padding(DS.Spacing.lg)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Monthly Growth
    private var monthlyGrowthSection: some View {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let calendar = Calendar.current
        let now = Date()

        // آخر 6 شهور
        let months: [(label: String, count: Int)] = (0..<6).reversed().map { offset in
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: now) else {
                return ("", 0)
            }
            let components = calendar.dateComponents([.year, .month], from: monthStart)
            let year = components.year ?? 2026
            let month = components.month ?? 1

            let count = memberVM.allMembers.filter { member in
                guard let created = member.createdAt else { return false }
                // محاولة عدة أشكال
                let cleanDate = created.prefix(19)
                guard let date = dateFormatter.date(from: String(cleanDate)) else { return false }
                let memberComponents = calendar.dateComponents([.year, .month], from: date)
                return memberComponents.year == year && memberComponents.month == month
            }.count

            let monthName = calendar.shortMonthSymbols[(month - 1) % 12]
            return (monthName, count)
        }

        let maxCount = max(months.map(\.count).max() ?? 1, 1)

        return DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("نمو الأعضاء", "Member Growth"),
                icon: "chart.line.uptrend.xyaxis",
                trailing: L10n.t("آخر ٦ أشهر", "Last 6 months"),
                iconColor: DS.Color.accent
            )

            HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
                ForEach(months, id: \.label) { month in
                    VStack(spacing: DS.Spacing.xs) {
                        Text("\(month.count)")
                            .font(DS.Font.scaled(10, weight: .bold))
                            .foregroundColor(DS.Color.textSecondary)

                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .fill(
                                LinearGradient(
                                    colors: [DS.Color.accent, DS.Color.accentLight],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(
                                height: max(CGFloat(month.count) / CGFloat(maxCount) * 100, 4)
                            )

                        Text(month.label)
                            .font(DS.Font.scaled(9, weight: .semibold))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(DS.Spacing.lg)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - News Stats
    private var newsSection: some View {
        let totalNews = newsVM.allNews.count
        let approvedNews = newsVM.allNews.filter { $0.approval_status == "approved" }.count
        let pendingNews = newsVM.pendingNewsRequests.count
        let withImages = newsVM.allNews.filter { !($0.image_urls ?? []).isEmpty }.count
        let withPolls = newsVM.allNews.filter { $0.hasPoll }.count

        return DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("إحصائيات الأخبار", "News Statistics"),
                icon: "newspaper.fill",
                iconColor: DS.Color.primary
            )

            let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                miniStat(value: "\(totalNews)", label: L10n.t("إجمالي", "Total"), color: DS.Color.primary)
                miniStat(value: "\(approvedNews)", label: L10n.t("منشور", "Published"), color: DS.Color.success)
                miniStat(value: "\(pendingNews)", label: L10n.t("معلق", "Pending"), color: DS.Color.warning)
                miniStat(value: "\(withImages)", label: L10n.t("بصور", "With Images"), color: DS.Color.info)
                miniStat(value: "\(withPolls)", label: L10n.t("باستطلاع", "With Polls"), color: DS.Color.neonPurple)
            }
            .padding(DS.Spacing.lg)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Shared Components

    private func barRow(label: String, count: Int, total: Int, color: Color) -> some View {
        let percentage = total > 0 ? Double(count) / Double(total) : 0

        return HStack(spacing: DS.Spacing.md) {
            Text(label)
                .font(DS.Font.scaled(12, weight: .semibold))
                .foregroundColor(DS.Color.textSecondary)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.1))
                        .frame(height: 20)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * percentage, 2), height: 20)
                }
            }
            .frame(height: 20)

            Text("\(count)")
                .font(DS.Font.scaled(12, weight: .black))
                .foregroundColor(DS.Color.textPrimary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private func miniStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(DS.Font.headline)
                .fontWeight(.black)
                .foregroundColor(color)
            Text(label)
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xs)
    }
}
