import SwiftUI

struct AdminNotificationsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var sendToAll = true
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var searchText = ""

    private var candidates: [FamilyMember] {
        let base = memberVM.allMembers.filter { $0.role != .pending }
        if searchText.isEmpty { return base }
        return base.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.xl) {

                    // Notification content section
                    DSCard(padding: 0) {
                        DSSectionHeader(title: L10n.t("محتوى الإشعار", "Notification Content"), icon: "bell.badge")

                            VStack(spacing: 0) {
                                HStack(spacing: DS.Spacing.md) {
                                    Image(systemName: "textformat")
                                        .foregroundColor(DS.Color.textOnPrimary)
                                        .font(DS.Font.scaled(14))
                                        .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                                        .background(DS.Color.gradientPrimary)
                                        .cornerRadius(DS.Radius.sm)

                                    TextField(L10n.t("العنوان", "Title"), text: $title)
                                        .font(DS.Font.body)
                                        .multilineTextAlignment(.leading)
                                        .onChange(of: title) {
                                            if title.count > 100 {
                                                title = String(title.prefix(100))
                                            }
                                        }
                                }
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.xs)

                                DSDivider()

                                HStack(alignment: .top, spacing: DS.Spacing.md) {
                                    Image(systemName: "text.alignright")
                                        .foregroundColor(DS.Color.textOnPrimary)
                                        .font(DS.Font.scaled(14))
                                        .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                                        .background(DS.Color.gradientPrimary)
                                        .cornerRadius(DS.Radius.sm)

                                    TextEditor(text: $bodyText)
                                        .font(DS.Font.body)
                                        .frame(minHeight: 100)
                                        .scrollContentBackground(.hidden)
                                        .background(Color.clear)
                                        .onChange(of: bodyText) {
                                            if bodyText.count > 500 {
                                                bodyText = String(bodyText.prefix(500))
                                            }
                                        }
                                }
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.xs)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                    // Targeting section
                    DSCard(padding: 0) {
                        DSSectionHeader(title: L10n.t("الاستهداف", "Targeting"), icon: "target")

                            VStack(spacing: 0) {
                                HStack(spacing: DS.Spacing.md) {
                                    Image(systemName: "person.3.fill")
                                        .foregroundColor(DS.Color.textOnPrimary)
                                        .font(DS.Font.scaled(12))
                                        .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                                        .background(DS.Color.gradientPrimary)
                                        .cornerRadius(DS.Radius.sm)

                                    Toggle(L10n.t("إرسال للجميع", "Send to All"), isOn: $sendToAll)
                                        .font(DS.Font.body)
                                        .tint(DS.Color.primary)
                                }
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.xs)

                                if !sendToAll {
                                    DSDivider()

                                    // Search field
                                    HStack(spacing: DS.Spacing.md) {
                                        Image(systemName: "magnifyingglass")
                                            .foregroundColor(DS.Color.textTertiary)
                                        TextField(L10n.t("بحث عن عضو...", "Search for a member..."), text: $searchText)
                                            .font(DS.Font.body)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .padding(.horizontal, DS.Spacing.lg)
                                    .padding(.vertical, DS.Spacing.xs)

                                    DSDivider()

                                    // Members list
                                    ForEach(candidates) { member in
                                        Button {
                                            if selectedMemberIds.contains(member.id) {
                                                selectedMemberIds.remove(member.id)
                                            } else {
                                                selectedMemberIds.insert(member.id)
                                            }
                                        } label: {
                                            HStack {
                                                if selectedMemberIds.contains(member.id) {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(DS.Color.gradientPrimary)
                                                }
                                                Spacer()
                                                Text(member.fullName)
                                                    .font(DS.Font.callout)
                                                    .foregroundColor(DS.Color.textPrimary)
                                            }
                                            .padding(.horizontal, DS.Spacing.lg)
                                            .padding(.vertical, DS.Spacing.xs)
                                        }

                                        if member.id != candidates.last?.id {
                                            DSDivider()
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                    // Send button
                    DSPrimaryButton(
                        L10n.t("إرسال الإشعار", "Send Notification"),
                        icon: "paperplane.fill",
                        isLoading: notificationVM.isLoading
                    ) {
                        Task {
                            await notificationVM.sendNotification(
                                title: title,
                                body: bodyText,
                                targetMemberIds: sendToAll ? nil : Array(selectedMemberIds)
                            )
                            dismiss()
                        }
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        (!sendToAll && selectedMemberIds.isEmpty)
                    )
                    .padding(.horizontal, DS.Spacing.lg)

                    Spacer(minLength: DS.Spacing.xxxl)
                }
                .padding(.top, DS.Spacing.lg)
            }
        }
        .navigationTitle(L10n.t("إرسال إشعار", "Send Notification"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await memberVM.fetchAllMembers() }
    }
}
