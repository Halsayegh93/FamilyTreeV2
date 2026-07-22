import SwiftUI

/// شاشة إدارة طلبات تعديل الشجرة — مفصولة عن AdminAllRequestsView.
/// تعرض 5 تابات حسب نوع الإجراء (إضافة / تعديل اسم / رقم / وفاة / حذف).
struct AdminTreeEditRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAction: TreeEditAction = .add
    @State private var rejectingRequest: AdminRequest? = nil
    @State private var rejectReasonText: String = ""
    @State private var showRejectAlert: Bool = false

    private let allActions: [TreeEditAction] = [.add, .editName, .editPhone, .editBirth, .deceased, .delete, .other]

    private func color(for action: TreeEditAction) -> Color {
        switch action {
        case .add: return DS.Color.success
        case .editName: return DS.Color.info
        case .editPhone: return DS.Color.primary
        case .editBirth: return DS.Color.warning
        case .deceased: return DS.Color.textTertiary
        case .addDeathDate: return DS.Color.textTertiary
        case .addPhoto: return DS.Color.primary
        case .delete: return DS.Color.error
        case .other: return DS.Color.accent
        }
    }

    private func count(for action: TreeEditAction) -> Int {
        adminRequestVM.treeEditRequests.filter { $0.treeEditPayload?.resolvedAction == action }.count
    }

    private var filteredRequests: [AdminRequest] {
        adminRequestVM.treeEditRequests.filter { $0.treeEditPayload?.resolvedAction == selectedAction }
    }

    private func canApprove(_ action: TreeEditAction) -> Bool {
        guard let role = authVM.currentUser?.role else { return false }
        switch role {
        case .owner, .admin:
            return true
        case .monitor:
            return action == .editName || action == .editPhone || action == .deceased || action == .delete
        case .supervisor:
            return action == .add
        default:
            return false
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    tabsBar
                        .padding(.vertical, DS.Spacing.md)

                    if filteredRequests.isEmpty {
                        emptyState
                    } else {
                        requestsList
                    }
                }
            }
            .navigationTitle(L10n.t("طلبات الشجرة", "Tree Requests"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
            .alert(
                L10n.t("سبب الرفض", "Rejection Reason"),
                isPresented: $showRejectAlert
            ) {
                TextField(L10n.t("اكتب سبب الرفض (اختياري)", "Reason (optional)"), text: $rejectReasonText)
                Button(L10n.t("رفض", "Reject"), role: .destructive) {
                    if let req = rejectingRequest {
                        let reason = rejectReasonText.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await adminRequestVM.rejectTreeEditRequest(request: req, reason: reason.isEmpty ? nil : reason) }
                    }
                    rejectingRequest = nil
                    rejectReasonText = ""
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {
                    rejectingRequest = nil
                    rejectReasonText = ""
                }
            } message: {
                Text(L10n.t("سيظهر السبب في إشعار للمستخدم.", "The reason will appear in a notification to the user."))
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .task { await adminRequestVM.fetchTreeEditRequests(force: true) }
            .refreshable { await adminRequestVM.fetchTreeEditRequests(force: true) }
        }
    }

    // MARK: - Tabs

    private var tabsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(allActions, id: \.rawValue) { action in
                    let isSelected = selectedAction == action
                    let tint = color(for: action)
                    let badge = count(for: action)

                    Button {
                        withAnimation(DS.Anim.snappy) { selectedAction = action }
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: action.iconName)
                                .font(DS.Font.scaled(13, weight: .semibold))
                            Text(L10n.t(action.arabicLabel, action.englishLabel))
                                .font(DS.Font.caption1)
                                .fontWeight(.semibold)
                            if badge > 0 {
                                Text("\(badge)")
                                    .font(DS.Font.scaled(11, weight: .bold))
                                    .foregroundColor(isSelected ? tint : DS.Color.textOnPrimary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(isSelected ? DS.Color.textOnPrimary.opacity(0.85) : tint)
                                    .clipShape(Capsule())
                            }
                        }
                        .foregroundColor(isSelected ? DS.Color.textOnPrimary : tint)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(isSelected ? tint : tint.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(isSelected ? Color.clear : tint.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Spacer()
            Image(systemName: "tray")
                .font(DS.Font.scaled(48))
                .foregroundColor(DS.Color.textTertiary.opacity(0.5))
            Text(L10n.t("لا توجد طلبات", "No requests"))
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textSecondary)
            Text(L10n.t("سوف تظهر طلبات هذا النوع هنا.", "Requests of this type will appear here."))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Requests List

    private var requestsList: some View {
        ScrollView(showsIndicators: false) {
            AdaptiveLazyStack(spacing: DS.Spacing.md, landscapeMinimum: 360) {
                ForEach(filteredRequests) { request in
                    requestCard(for: request)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xxxxl)
        }
    }

    @ViewBuilder
    private func requestCard(for request: AdminRequest) -> some View {
        let payload = request.treeEditPayload
        let action = payload?.resolvedAction ?? selectedAction
        let tint = color(for: action)
        let requesterName = memberVM.member(byId: request.requesterId)?.fullName ?? L10n.t("غير معروف", "Unknown")

        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: action.iconName)
                        .font(DS.Font.scaled(18, weight: .semibold))
                        .foregroundColor(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(action.arabicLabel, action.englishLabel))
                        .font(DS.Font.caption1)
                        .fontWeight(.semibold)
                        .foregroundColor(tint)
                    Text(payload?.targetMemberName ?? request.member?.fullName ?? "—")
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                }

                Spacer()
            }

            DSDivider()

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                detailLines(for: request, payload: payload, action: action)

                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "person.fill")
                        .font(DS.Font.scaled(11))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(L10n.t("مقدم الطلب: ", "Requester: ") + requesterName)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }

                if let createdAt = request.createdAt, !createdAt.isEmpty {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "clock")
                            .font(DS.Font.scaled(11))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(formatDate(createdAt))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }

                if let notes = payload?.notes, !notes.isEmpty {
                    HStack(alignment: .top, spacing: DS.Spacing.xs) {
                        Image(systemName: "text.bubble")
                            .font(DS.Font.scaled(11))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(notes)
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }

            HStack(spacing: DS.Spacing.sm) {
                if canApprove(action) {
                    Button {
                        Task { await adminRequestVM.approveTreeEditRequest(request: request) }
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(DS.Font.scaled(14, weight: .semibold))
                            Text(L10n.t("موافقة", "Approve"))
                                .font(DS.Font.calloutBold)
                        }
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(DS.Color.success)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }

                if authVM.canRejectRequests {
                    Button {
                        rejectingRequest = request
                        rejectReasonText = ""
                        showRejectAlert = true
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "xmark.circle.fill")
                                .font(DS.Font.scaled(14, weight: .semibold))
                            Text(L10n.t("رفض", "Reject"))
                                .font(DS.Font.calloutBold)
                        }
                        .foregroundColor(DS.Color.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(DS.Color.error.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .stroke(DS.Color.error.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
            }
        }
        .padding(DS.Spacing.lg)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func detailLines(for request: AdminRequest, payload: TreeEditPayload?, action: TreeEditAction) -> some View {
        switch action {
        case .add:
            if let newName = payload?.newMemberName {
                detailRow(icon: "person.badge.plus", label: L10n.t("اسم الابن", "Son's name"), value: newName)
            }
            if let parentName = payload?.parentMemberName {
                detailRow(icon: "person.fill", label: L10n.t("الأب", "Parent"), value: parentName)
            }

        case .editName:
            if let currentName = payload?.targetMemberName {
                detailRow(icon: "person.fill", label: L10n.t("الاسم الحالي", "Current name"), value: currentName)
            }
            if let newName = payload?.newName {
                detailRow(icon: "pencil", label: L10n.t("الاسم الجديد", "New name"), value: newName, valueColor: DS.Color.info)
            }

        case .editPhone:
            if let currentPhone = request.member?.phoneNumber {
                detailRow(icon: "phone.fill", label: L10n.t("الرقم الحالي", "Current phone"), value: KuwaitPhone.display(currentPhone))
            }
            if let newPhone = payload?.newPhone {
                detailRow(icon: "phone.arrow.up.right", label: L10n.t("الرقم الجديد", "New phone"), value: KuwaitPhone.display(newPhone), valueColor: DS.Color.primary)
            }

        case .deceased:
            if let deathDate = payload?.deathDate {
                detailRow(icon: "calendar", label: L10n.t("تاريخ الوفاة", "Date of death"), value: deathDate)
            }

        case .addDeathDate:
            if let deathDate = payload?.deathDate, !deathDate.isEmpty {
                detailRow(icon: "calendar.badge.exclamationmark", label: L10n.t("تاريخ الوفاة", "Date of death"), value: deathDate)
            }

        case .addPhoto:
            if let photoStr = payload?.newPhotoUrl, let url = URL(string: photoStr) {
                detailRow(icon: "photo.badge.plus", label: L10n.t("الصورة المقترحة", "Suggested photo"), value: "", valueColor: DS.Color.primary)
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView().tint(DS.Color.primary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            }

        case .delete:
            if let reason = payload?.reason, !reason.isEmpty {
                detailRow(icon: "exclamationmark.triangle", label: L10n.t("السبب", "Reason"), value: reason, valueColor: DS.Color.error)
            }

        case .editBirth:
            if let newDate = (payload?.newBirthDate ?? payload?.newName), !newDate.isEmpty {
                detailRow(icon: "birthday.cake", label: L10n.t("تاريخ الميلاد الجديد", "New birth date"), value: newDate, valueColor: DS.Color.warning)
            }

        case .other:
            if let note = payload?.notes, !note.isEmpty {
                detailRow(icon: "square.and.pencil", label: L10n.t("الطلب", "Request"), value: note, valueColor: DS.Color.accent)
            }
        }
    }

    private func detailRow(icon: String, label: String, value: String, valueColor: Color = DS.Color.textPrimary) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(DS.Font.scaled(11))
                .foregroundColor(DS.Color.textTertiary)
                .frame(width: 16)
            Text(label)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
            Text(value)
                .font(DS.Font.caption1)
                .fontWeight(.semibold)
                .foregroundColor(valueColor)
                .lineLimit(2)
            Spacer()
        }
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            display.locale = Locale(identifier: L10n.isArabic ? "ar" : "en_US")
            return display.string(from: date)
        }
        return iso
    }
}
