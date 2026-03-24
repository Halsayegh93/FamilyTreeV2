import SwiftUI

// MARK: - Admin Members Registry — سجل الأعضاء
struct AdminMembersDirectoryView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel

    @State private var searchText = ""
    @State private var displayLimit = 20

    private var filteredMembers: [FamilyMember] {
        let members = memberVM.allMembers.filter { $0.role != .pending }
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
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.md) {
                membersSection
            }
            .padding(.bottom, DS.Spacing.xxxl)
        }
    }

    // MARK: - Members List
    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("سجل الأعضاء", "Members Registry"),
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
                        .onChange(of: searchText) { displayLimit = 20 }

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(DS.Color.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.xs)

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
                        let visible = Array(filteredMembers.prefix(displayLimit))
                        ForEach(visible) { member in
                            NavigationLink(destination: AdminMemberDetailSheet(member: member)) {
                                registryMemberRow(member: member)
                            }
                            .buttonStyle(DSBoldButtonStyle())

                            if member.id != visible.last?.id {
                                DSDivider()
                            }
                        }

                        if displayLimit < filteredMembers.count {
                            Button {
                                displayLimit += 20
                            } label: {
                                HStack {
                                    Spacer()
                                    Text(L10n.t(
                                        "عرض المزيد (\(filteredMembers.count - displayLimit) متبقي)",
                                        "Show more (\(filteredMembers.count - displayLimit) remaining)"
                                    ))
                                    .font(DS.Font.caption1)
                                    .foregroundColor(DS.Color.primary)
                                    Spacer()
                                }
                                .padding(.vertical, DS.Spacing.md)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func registryMemberRow(member: FamilyMember) -> some View {
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
        .padding(.vertical, DS.Spacing.xs)
    }
}
