import SwiftUI

struct AdminNotificationsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss

    @State private var title = "عائلة المحمدعلي 🌿"
    @State private var bodyText = ""
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var searchText = ""
    @State private var displayLimit = 20

    private var activeMembers: [FamilyMember] {
        memberVM.allMembers
            .filter { $0.role != .pending }
            .sorted { $0.fullName < $1.fullName }
    }

    private var filteredMembers: [FamilyMember] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return activeMembers }
        return activeMembers.filter {
            $0.fullName.localizedCaseInsensitiveContains(trimmed) ||
            $0.firstName.localizedCaseInsensitiveContains(trimmed) ||
            ($0.phoneNumber ?? "").contains(trimmed)
        }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Title + Body fields
                VStack(spacing: DS.Spacing.sm) {
                    // Title
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "bell.badge")
                            .foregroundColor(DS.Color.textTertiary)
                            .font(DS.Font.scaled(14, weight: .medium))
                        TextField(L10n.t("عنوان الإشعار", "Notification title"), text: $title)
                            .font(DS.Font.callout)
                            .onChange(of: title) {
                                if title.count > 100 { title = String(title.prefix(100)) }
                            }
                        if !title.isEmpty {
                            Button { title = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                        }
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.md)

                    // Body (optional)
                    HStack(alignment: .top, spacing: DS.Spacing.sm) {
                        Image(systemName: "text.alignright")
                            .foregroundColor(DS.Color.textTertiary)
                            .font(DS.Font.scaled(14, weight: .medium))
                            .padding(.top, DS.Spacing.sm)
                        ZStack(alignment: L10n.isArabic ? .topTrailing : .topLeading) {
                            if bodyText.isEmpty {
                                Text(L10n.t("تفاصيل (اختياري)", "Details (optional)"))
                                    .font(DS.Font.callout)
                                    .foregroundColor(DS.Color.textTertiary)
                                    .padding(.top, DS.Spacing.sm)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $bodyText)
                                .font(DS.Font.callout)
                                .frame(minHeight: 60, maxHeight: 100)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .onChange(of: bodyText) {
                                    if bodyText.count > 500 { bodyText = String(bodyText.prefix(500)) }
                                }
                        }
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.md)

                    // Search
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(DS.Color.textTertiary)
                            .font(DS.Font.scaled(14, weight: .medium))
                        TextField(L10n.t("بحث بالاسم أو الرقم...", "Search by name or phone..."), text: $searchText)
                            .font(DS.Font.callout)
                            .onChange(of: searchText) { displayLimit = 20 }
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                        }
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.md)

                    // Select/Deselect + count
                    HStack(spacing: DS.Spacing.sm) {
                        Button {
                            selectedMemberIds = Set(filteredMembers.map(\.id))
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(DS.Font.scaled(11))
                                Text(L10n.t("الكل", "All"))
                                    .font(DS.Font.scaled(12, weight: .bold))
                            }
                            .foregroundColor(DS.Color.primary)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(DS.Color.primary.opacity(0.1))
                            .clipShape(Capsule())
                        }

                        Button {
                            selectedMemberIds.removeAll()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(DS.Font.scaled(11))
                                Text(L10n.t("إلغاء", "Clear"))
                                    .font(DS.Font.scaled(12, weight: .bold))
                            }
                            .foregroundColor(DS.Color.error)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(DS.Color.error.opacity(0.1))
                            .clipShape(Capsule())
                        }

                        Spacer()

                        Text(L10n.t(
                            "\(selectedMemberIds.isEmpty ? filteredMembers.count : selectedMemberIds.count) عضو",
                            "\(selectedMemberIds.isEmpty ? filteredMembers.count : selectedMemberIds.count) members"
                        ))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)

                // Members list
                if filteredMembers.isEmpty {
                    Spacer()
                    VStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "person.2.slash")
                            .font(DS.Font.scaled(36, weight: .regular))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا يوجد أعضاء", "No members found"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    Spacer()
                } else {
                    List {
                        let visible = Array(filteredMembers.prefix(displayLimit))
                        ForEach(visible) { member in
                            Button {
                                toggleSelection(member.id)
                            } label: {
                                memberRow(member: member)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 4, leading: DS.Spacing.lg, bottom: 4, trailing: DS.Spacing.lg))
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
                                .padding(.vertical, DS.Spacing.sm)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: DS.Spacing.lg, bottom: 0, trailing: DS.Spacing.lg))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }

                // Send button
                VStack(spacing: DS.Spacing.xs) {
                    DSPrimaryButton(
                        L10n.t("إرسال الإشعار", "Send Notification"),
                        icon: "paperplane.fill",
                        isLoading: notificationVM.isLoading
                    ) {
                        Task { await sendNotification() }
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    if selectedMemberIds.isEmpty {
                        Text(L10n.t("سيُرسل للجميع", "Will be sent to all"))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textTertiary)
                    } else {
                        Text(L10n.t(
                            "سيُرسل لـ \(selectedMemberIds.count) عضو محدد",
                            "Will be sent to \(selectedMemberIds.count) selected members"
                        ))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
                .background(DS.Color.background)
            }
        }
        .navigationTitle(L10n.t("إرسال إشعار", "Send Notification"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await memberVM.fetchAllMembers() }
    }

    // MARK: - Member Row

    private func memberRow(member: FamilyMember) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: selectedMemberIds.contains(member.id) ? "checkmark.circle.fill" : "circle")
                .font(DS.Font.scaled(20))
                .foregroundStyle(
                    selectedMemberIds.contains(member.id)
                        ? AnyShapeStyle(DS.Color.gradientPrimary)
                        : AnyShapeStyle(DS.Color.textTertiary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(member.fullName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                if let phone = member.phoneNumber, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "phone.fill")
                            .font(DS.Font.scaled(10))
                        Text(KuwaitPhone.display(phone))
                    }
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func toggleSelection(_ id: UUID) {
        if selectedMemberIds.contains(id) {
            selectedMemberIds.remove(id)
        } else {
            selectedMemberIds.insert(id)
        }
    }

    private func sendNotification() async {
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)

        // إذا كل الأعضاء محددين، نرسل broadcast (nil) بدل إرسال كل الـ IDs
        let activeMemberIds = Set(activeMembers.map(\.id))
        let targetIds: [UUID]? = if selectedMemberIds.isEmpty || selectedMemberIds == activeMemberIds {
            nil
        } else {
            Array(selectedMemberIds)
        }

        await notificationVM.sendNotification(
            title: title,
            body: trimmedBody.isEmpty ? title : trimmedBody,
            targetMemberIds: targetIds
        )
        dismiss()
    }
}
