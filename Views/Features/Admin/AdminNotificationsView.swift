import SwiftUI

struct AdminNotificationsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var sendToAll = true
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var searchText = ""

    private var candidates: [FamilyMember] {
        let base = authVM.allMembers.filter { $0.role != .pending }
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
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        DSSectionHeader(title: "محتوى الإشعار", icon: "bell.badge")

                        DSCard {
                            VStack(spacing: 0) {
                                HStack(spacing: DS.Spacing.md) {
                                    Image(systemName: "textformat")
                                        .foregroundColor(.white)
                                        .font(DS.Font.scaled(14))
                                        .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                                        .background(DS.Color.gradientPrimary)
                                        .cornerRadius(DS.Radius.sm)

                                    TextField("العنوان", text: $title)
                                        .font(DS.Font.body)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.md)

                                DSDivider()

                                HStack(alignment: .top, spacing: DS.Spacing.md) {
                                    Image(systemName: "text.alignright")
                                        .foregroundColor(.white)
                                        .font(DS.Font.scaled(14))
                                        .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                                        .background(DS.Color.gradientPrimary)
                                        .cornerRadius(DS.Radius.sm)

                                    TextEditor(text: $bodyText)
                                        .font(DS.Font.body)
                                        .frame(minHeight: 100)
                                        .scrollContentBackground(.hidden)
                                        .background(Color.clear)
                                }
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.md)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                    }

                    // Targeting section
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        DSSectionHeader(title: "الاستهداف", icon: "target")

                        DSCard {
                            VStack(spacing: 0) {
                                HStack(spacing: DS.Spacing.md) {
                                    Image(systemName: "person.3.fill")
                                        .foregroundColor(.white)
                                        .font(DS.Font.scaled(12))
                                        .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                                        .background(DS.Color.gradientPrimary)
                                        .cornerRadius(DS.Radius.sm)

                                    Toggle("إرسال للجميع", isOn: $sendToAll)
                                        .font(DS.Font.body)
                                        .tint(DS.Color.primary)
                                }
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.md)

                                if !sendToAll {
                                    DSDivider()

                                    // Search field
                                    HStack(spacing: DS.Spacing.md) {
                                        Image(systemName: "magnifyingglass")
                                            .foregroundColor(DS.Color.textTertiary)
                                        TextField("بحث عن عضو...", text: $searchText)
                                            .font(DS.Font.body)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .padding(.horizontal, DS.Spacing.lg)
                                    .padding(.vertical, DS.Spacing.sm)

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
                                            .padding(.vertical, DS.Spacing.sm)
                                        }

                                        if member.id != candidates.last?.id {
                                            DSDivider()
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                    }

                    // Send button
                    DSPrimaryButton(
                        "إرسال الإشعار",
                        icon: "paperplane.fill",
                        isLoading: authVM.isLoading
                    ) {
                        Task {
                            await authVM.sendNotification(
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
        .navigationTitle("إرسال إشعار")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear {
            Task { await authVM.fetchAllMembers() }
        }
    }
}
