import SwiftUI

// MARK: - Admin Analytics — إحصائيات متقدمة
struct AdminAnalyticsView: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var newsVM: NewsViewModel

    // البيانات المحسوبة
    private var activeMembers: [FamilyMember] {
        memberVM.allMembers.filter { $0.role != .pending && $0.isDeceased != true }
    }
    private var deceasedMembers: [FamilyMember] {
        memberVM.allMembers.filter { $0.isDeceased == true }
    }
    private var totalMembers: Int { memberVM.allMembers.filter { $0.role != .pending }.count }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.xxl) {
                    // ملخص عام
                    overviewSection
                        .padding(.top, DS.Spacing.md)

                    // توزيع الأدوار
                    rolesSection

                    // توزيع الجنس
                    genderSection

                    // الفئات العمرية
                    ageGroupsSection

                    // نمو الأعضاء الشهري
                    monthlyGrowthSection

                    // الأخبار
                    newsSection

                    Spacer(minLength: DS.Spacing.xxxl)
                }
            }
        }
        .navigationTitle(L10n.t("إحصائيات متقدمة", "Analytics"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
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
        let admins = memberVM.allMembers.filter { $0.role == .owner || $0.role == .admin }.count
        let monitors = memberVM.allMembers.filter { $0.role == .monitor }.count
        let supervisors = memberVM.allMembers.filter { $0.role == .supervisor }.count
        let members = memberVM.allMembers.filter { $0.role == .member }.count
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
