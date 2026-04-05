import SwiftUI

/// شاشة طلب تعديل الشجرة — إضافة / تعديل اسم / حذف
struct TreeEditRequestView: View {
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isDetailsFocused: Bool
    @FocusState private var isNameFieldFocused: Bool
    @FocusState private var isNewNameFocused: Bool
    @FocusState private var isNewMemberNameFocused: Bool

    @State private var selectedAction = "تعديل اسم"
    @State private var memberName = ""
    @State private var details = ""
    @State private var newNameText = ""
    @State private var newMemberNameText = ""
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var nameSearchText = ""
    @State private var selectedMember: FamilyMember?
    @State private var showMemberPicker = false

    private let actionItems: [(key: String, icon: String, labelAr: String, labelEn: String, color: Color)] = [
        ("إضافة", "person.badge.plus", "إضافة", "Add", DS.Color.success),
        ("تعديل اسم", "pencil.line", "تعديل اسم", "Edit Name", DS.Color.info),
        ("حذف", "person.badge.minus", "حذف", "Remove", DS.Color.error)
    ]

    private var canSubmit: Bool {
        guard selectedMember != nil, !adminRequestVM.isLoading else { return false }
        switch selectedAction {
        case "تعديل اسم":
            return !newNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "حذف":
            return !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "إضافة":
            return !newMemberNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }

    /// Dynamic label for member picker based on action
    private var memberPickerLabel: String {
        switch selectedAction {
        case "إضافة":
            return L10n.t("الأب", "Father")
        default:
            return L10n.t("العضو المعني", "Target Member")
        }
    }

    /// Dynamic placeholder for member picker
    private var memberPickerPlaceholder: String {
        switch selectedAction {
        case "إضافة":
            return L10n.t("اختر الأب من القائمة...", "Select father from list...")
        default:
            return L10n.t("اختر العضو من القائمة...", "Select member from list...")
        }
    }

    /// Dynamic label & placeholder for details section
    private var detailsLabel: String {
        switch selectedAction {
        case "حذف":
            return L10n.t("سبب الحذف", "Removal Reason")
        default:
            return L10n.t("ملاحظات إضافية (اختياري)", "Additional Notes (optional)")
        }
    }

    private var detailsPlaceholder: String {
        switch selectedAction {
        case "تعديل اسم":
            return L10n.t("أي ملاحظات إضافية...", "Any additional notes...")
        case "حذف":
            return L10n.t("اكتب سبب الحذف...", "Write the removal reason...")
        case "إضافة":
            return L10n.t("أي ملاحظات إضافية...", "Any additional notes...")
        default:
            return ""
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xxl) {
                        actionSection
                        memberNameSection

                        // Action-specific fields
                        if selectedAction == "تعديل اسم" {
                            newNameSection
                        } else if selectedAction == "إضافة" {
                            newMemberNameSection
                        }

                        detailsSection
                        submitButton
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xxxxl)
                }
            }
            .navigationTitle(L10n.t("طلب تعديل الشجرة", "Tree Edit Request"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.error)
                }
            }
            .alert(L10n.t("تم الإرسال", "Request Sent"), isPresented: $showSuccessAlert) {
                Button(L10n.t("حسناً", "OK")) { dismiss() }
            } message: {
                Text(L10n.t(
                    "تم إرسال طلبك للإدارة وسيتم مراجعته قريباً.",
                    "Your request has been sent to admin for review."
                ))
            }
            .alert(L10n.t("تعذر الإرسال", "Failed to Send"), isPresented: $showErrorAlert) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: {
                Text(L10n.t(
                    "تعذر إرسال الطلب. حاول مرة أخرى.",
                    "Failed to send request. Please try again."
                ))
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }

    // MARK: - Action Type Section
    private var actionSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(L10n.t("نوع التعديل", "Edit Type"))
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)

            HStack(spacing: DS.Spacing.sm) {
                ForEach(actionItems, id: \.key) { item in
                    let isSelected = selectedAction == item.key
                    Button {
                        withAnimation(DS.Anim.snappy) {
                            selectedAction = item.key
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: item.icon)
                                .font(DS.Font.scaled(14, weight: .semibold))
                            Text(L10n.t(item.labelAr, item.labelEn))
                                .font(DS.Font.caption1)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(isSelected ? DS.Color.textOnPrimary : item.color)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? item.color : item.color.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? Color.clear : item.color.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
            }
        }
    }

    // MARK: - Member Name Section (dynamic label)
    private var memberNameSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(memberPickerLabel)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)

            // Tappable field to open member picker
            Button {
                showMemberPicker = true
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: selectedAction == "إضافة" ? "person.2.fill" : "person.fill")
                        .font(DS.Font.scaled(14, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(width: 24)

                    if let selected = selectedMember {
                        Text(selected.fullName)
                            .font(DS.Font.body)
                            .foregroundColor(DS.Color.textPrimary)
                    } else {
                        Text(memberPickerPlaceholder)
                            .font(DS.Font.body)
                            .foregroundColor(DS.Color.textTertiary)
                    }

                    Spacer()

                    Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                        .font(DS.Font.scaled(12, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.md)
                .background(DS.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .stroke(
                            selectedMember != nil ? DS.Color.primary.opacity(0.3) : DS.Color.textTertiary.opacity(0.15),
                            lineWidth: selectedMember != nil ? 1.5 : 1
                        )
                )
            }
            .buttonStyle(DSScaleButtonStyle())
        }
        .sheet(isPresented: $showMemberPicker) {
            memberPickerSheet
        }
        .onChange(of: selectedAction) {
            // Reset all fields when action type changes
            selectedMember = nil
            memberName = ""
            newNameText = ""
            newMemberNameText = ""
            details = ""
        }
    }

    // MARK: - New Name Section (for تعديل اسم)
    private var newNameSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(L10n.t("الاسم الجديد", "New Name"))
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)

            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "pencil")
                    .font(DS.Font.scaled(14, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                    .frame(width: 24)

                TextField(
                    L10n.t("اكتب الاسم الجديد...", "Enter the new name..."),
                    text: $newNameText
                )
                .font(DS.Font.body)
                .foregroundColor(DS.Color.textPrimary)
                .focused($isNewNameFocused)

                if !newNameText.isEmpty {
                    Button {
                        newNameText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.Font.scaled(14, weight: .medium))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.md)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(
                        isNewNameFocused ? DS.Color.primary.opacity(0.4) : DS.Color.textTertiary.opacity(0.15),
                        lineWidth: isNewNameFocused ? 1.5 : 1
                    )
            )
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - New Member Name Section (for إضافة)
    private var newMemberNameSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(L10n.t("اسم العضو الجديد", "New Member Name"))
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)

            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "person.badge.plus")
                    .font(DS.Font.scaled(14, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                    .frame(width: 24)

                TextField(
                    L10n.t("اكتب اسم العضو الجديد...", "Enter the new member's name..."),
                    text: $newMemberNameText
                )
                .font(DS.Font.body)
                .foregroundColor(DS.Color.textPrimary)
                .focused($isNewMemberNameFocused)

                if !newMemberNameText.isEmpty {
                    Button {
                        newMemberNameText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.Font.scaled(14, weight: .medium))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.md)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(
                        isNewMemberNameFocused ? DS.Color.primary.opacity(0.4) : DS.Color.textTertiary.opacity(0.15),
                        lineWidth: isNewMemberNameFocused ? 1.5 : 1
                    )
            )
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Member Picker Sheet
    private var memberPickerSheet: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .font(DS.Font.scaled(14, weight: .medium))
                            .foregroundColor(DS.Color.textTertiary)

                        TextField(
                            L10n.t("ابحث عن عضو...", "Search for a member..."),
                            text: $nameSearchText
                        )
                        .font(DS.Font.body)
                        .foregroundColor(DS.Color.textPrimary)
                        .focused($isNameFieldFocused)

                        if !nameSearchText.isEmpty {
                            Button {
                                nameSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(DS.Font.scaled(14, weight: .medium))
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)

                    // Members list
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: DS.Spacing.xs) {
                            ForEach(filteredMembers) { member in
                                Button {
                                    selectedMember = member
                                    memberName = member.fullName
                                    showMemberPicker = false
                                    nameSearchText = ""
                                } label: {
                                    HStack(spacing: DS.Spacing.sm) {
                                        // Avatar circle
                                        ZStack {
                                            Circle()
                                                .fill(DS.Color.primary.opacity(0.1))
                                                .frame(width: 32, height: 32)

                                            Text(String(member.firstName.prefix(1)))
                                                .font(DS.Font.caption1)
                                                .fontWeight(.semibold)
                                                .foregroundColor(DS.Color.primary)
                                        }

                                        Text(member.fullName)
                                            .font(DS.Font.callout)
                                            .foregroundColor(DS.Color.textPrimary)
                                            .lineLimit(1)

                                        Spacer()

                                        if selectedMember?.id == member.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(DS.Font.scaled(16, weight: .medium))
                                                .foregroundColor(DS.Color.primary)
                                        }
                                    }
                                    .padding(.horizontal, DS.Spacing.md)
                                    .padding(.vertical, DS.Spacing.sm)
                                }
                                .buttonStyle(DSScaleButtonStyle())

                                if member.id != filteredMembers.last?.id {
                                    Divider()
                                        .padding(.leading, 52)
                                }
                            }
                        }
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.xxxxl)
                    }
                }
            }
            .navigationTitle(L10n.t("اختر العضو", "Select Member"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) {
                        showMemberPicker = false
                        nameSearchText = ""
                    }
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.error)
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .onAppear { isNameFieldFocused = true }
        }
    }

    /// Filtered members based on search text — show first 15 by default, all when searching
    private var filteredMembers: [FamilyMember] {
        let members = memberVM.allMembers.filter { $0.status != .frozen }
        let sorted = members.sorted { $0.fullName < $1.fullName }
        if nameSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Array(sorted.prefix(15))
        }
        let query = nameSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sorted
            .filter { $0.fullName.lowercased().contains(query) || $0.firstName.lowercased().contains(query) }
    }

    // MARK: - Details Section (dynamic label based on action)
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(detailsLabel)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)

            ZStack(alignment: .topTrailing) {
                TextEditor(text: $details)
                    .frame(minHeight: selectedAction == "حذف" ? 100 : 80)
                    .focused($isDetailsFocused)
                    .scrollContentBackground(.hidden)
                    .font(DS.Font.body)

                if details.isEmpty {
                    Text(detailsPlaceholder)
                        .font(DS.Font.body)
                        .foregroundColor(DS.Color.textTertiary)
                        .padding(.top, DS.Spacing.sm)
                        .padding(.trailing, DS.Spacing.xs)
                        .allowsHitTesting(false)
                }
            }
            .padding(DS.Spacing.md)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(
                        isDetailsFocused ? DS.Color.primary.opacity(0.4) : DS.Color.textTertiary.opacity(0.15),
                        lineWidth: isDetailsFocused ? 1.5 : 1
                    )
            )
        }
    }

    // MARK: - Submit Button
    private var submitButton: some View {
        DSPrimaryButton(
            L10n.t("إرسال الطلب", "Submit Request"),
            icon: "paperplane.fill",
            isLoading: adminRequestVM.isLoading,
            useGradient: canSubmit,
            color: canSubmit ? DS.Color.primary : .gray
        ) {
            submit()
        }
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1.0 : DS.Opacity.disabled)
    }

    // MARK: - Submit Logic
    private func submit() {
        guard let member = selectedMember else { return }
        let cleanNotes = details.trimmingCharacters(in: .whitespacesAndNewlines)

        let payload: TreeEditPayload
        switch selectedAction {
        case "تعديل اسم":
            payload = TreeEditPayload(
                v: 2,
                action: selectedAction,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                newName: newNameText.trimmingCharacters(in: .whitespacesAndNewlines),
                parentMemberId: nil,
                parentMemberName: nil,
                newMemberName: nil,
                reason: nil,
                notes: cleanNotes.isEmpty ? nil : cleanNotes
            )
        case "حذف":
            payload = TreeEditPayload(
                v: 2,
                action: selectedAction,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                newName: nil,
                parentMemberId: nil,
                parentMemberName: nil,
                newMemberName: nil,
                reason: cleanNotes.isEmpty ? nil : cleanNotes,
                notes: nil
            )
        case "إضافة":
            payload = TreeEditPayload(
                v: 2,
                action: selectedAction,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                newName: nil,
                parentMemberId: member.id.uuidString,
                parentMemberName: member.fullName,
                newMemberName: newMemberNameText.trimmingCharacters(in: .whitespacesAndNewlines),
                reason: nil,
                notes: cleanNotes.isEmpty ? nil : cleanNotes
            )
        default:
            return
        }

        Task {
            let sent = await adminRequestVM.submitTreeEditRequest(payload: payload)
            if sent {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showSuccessAlert = true
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                showErrorAlert = true
            }
        }
    }
}
