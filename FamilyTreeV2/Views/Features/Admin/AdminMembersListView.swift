import SwiftUI

struct AdminMembersListView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var searchText = ""

    var filteredMembers: [FamilyMember] {
        let members = authVM.allMembers.filter { $0.role != .pending }
        if searchText.isEmpty {
            return members.sorted { $0.fullName < $1.fullName }
        } else {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return members.filter {
                $0.fullName.localizedCaseInsensitiveContains(query)
                || ($0.phoneNumber ?? "").contains(query)
            }
        }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) {

                    // MARK: - Stats
                    statsSection
                        .padding(.top, DS.Spacing.md)

                    // MARK: - Members
                    membersSection
                }
                .padding(.bottom, DS.Spacing.xxxl)
            }
        }
        .navigationTitle(L10n.t("سجل الأعضاء", "Member Registry"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Stats Section
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("إحصائيات", "Statistics"),
                    icon: "chart.bar.fill",
                    iconColor: DS.Color.primary
                )

                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                    statCell(
                        icon: "person.2.fill",
                        color: DS.Color.primary,
                        title: L10n.t("إجمالي الأعضاء", "Total Members"),
                        value: "\(authVM.allMembers.filter { $0.role != .pending }.count)"
                    )
                    statCell(
                        icon: "line.3.horizontal.decrease.circle.fill",
                        color: DS.Color.info,
                        title: L10n.t("نتائج البحث", "Search Results"),
                        value: "\(filteredMembers.count)"
                    )
                    statCell(
                        icon: "shield.fill",
                        color: DS.Color.warning,
                        title: L10n.t("مدراء ومشرفين", "Admins & Supervisors"),
                        value: "\(authVM.allMembers.filter { $0.role == .admin || $0.role == .supervisor }.count)"
                    )
                    statCell(
                        icon: "person.fill.checkmark",
                        color: DS.Color.success,
                        title: L10n.t("أعضاء فعالين", "Active Members"),
                        value: "\(authVM.allMembers.filter { $0.status == .active }.count)"
                    )
                }
                .padding(DS.Spacing.md)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func statCell(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Font.scaled(16, weight: .bold))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)

                Text(value)
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.sm)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Members Section
    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("الأعضاء", "Members"),
                    icon: "person.3.sequence.fill",
                    trailing: "\(filteredMembers.count)",
                    iconColor: DS.Color.success
                )

                // Search bar
                HStack(spacing: DS.Spacing.md) {
                    DSIcon("magnifyingglass", color: DS.Color.primary)

                    TextField(L10n.t("ابحث بالاسم أو رقم الهاتف...", "Search by name or phone..."), text: $searchText)
                        .font(DS.Font.body)
                        .multilineTextAlignment(.leading)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(DS.Color.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)

                DSDivider()

                // Members list
                if filteredMembers.isEmpty {
                    VStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "person.fill.questionmark")
                            .font(DS.Font.scaled(32))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا يوجد أعضاء بهذا البحث", "No members found"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.xl)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredMembers) { member in
                            NavigationLink(destination: AdminMemberDetailSheet(member: member)) {
                                memberRow(member: member)
                            }
                            .buttonStyle(DSBoldButtonStyle())

                            if member.id != filteredMembers.last?.id {
                                DSDivider()
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func memberRow(member: FamilyMember) -> some View {
        HStack(spacing: DS.Spacing.md) {
            // Avatar
            ZStack {
                Circle()
                    .fill(member.roleColor.opacity(0.12))
                    .frame(width: 42, height: 42)

                Text(String(member.fullName.prefix(1)))
                    .font(DS.Font.scaled(18, weight: .bold))
                    .foregroundColor(member.roleColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(member.fullName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)

                HStack(spacing: DS.Spacing.sm) {
                    DSRoleBadge(title: member.roleName, color: member.roleColor)

                    if let phone = member.phoneNumber, !phone.isEmpty {
                        Text(KuwaitPhone.display(phone))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)
                .frame(width: 26, height: 26)
                .background(DS.Color.textTertiary.opacity(0.1))
                .clipShape(Circle())
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }
}
