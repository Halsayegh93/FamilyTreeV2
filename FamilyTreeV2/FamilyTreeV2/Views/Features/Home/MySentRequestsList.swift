import SwiftUI

// «الطلبات المرسلة» (طلب المالك ٢٠٢٦-١١-١٧): طلبات العضو المعلّقة وسحبها — كانت «طلباتي» في الملف الشخصي،
// صارت صفحة ثالثة في مركز الإشعارات. الصفوف والسحب والرد على سؤال الإدارة كما كانت حرفياً.
struct MySentRequestsList: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    var section: AppSection = .home

    @State private var requestToCancel: AdminRequest? = nil
    @State private var cancelRequestError: String? = nil
    @State private var showApprovalReplySent = false
    /// أول جلب لم ينتهِ — هيكل البطاقات بدل «لا توجد طلبات» الخاطئة
    @State private var loaded = false

    var body: some View {
        let requests = adminRequestVM.myPendingRequests
        Group {
            if requests.isEmpty && !loaded {
                ScrollView {
                    DSCardSkeleton(style: .request, count: 2, label: L10n.t("جارٍ تحميل الطلبات…", "Loading requests…"))
                        .dsPageMargin()
                        .padding(.vertical, DS.Spacing.sm)
                }
                .scrollDisabled(true)
            } else if requests.isEmpty {
                DSEmptyView(L10n.t("لا توجد طلبات مرسلة", "No sent requests"),
                            message: L10n.t("الطلبات التي ترسلها للإدارة تظهر هنا حتى تُعالج، ويمكنك سحبها",
                                            "Requests you send to the administration appear here until handled, and you can withdraw them"),
                            section: section, icon: "paperplane.fill")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(requests, id: \.id) { request in
                            myRequestRow(request)
                        }
                    }
                    .dsPageMargin()
                    .padding(.vertical, DS.Spacing.sm)
                }
                .refreshable { await adminRequestVM.fetchMyPendingRequests(force: true) }
                .dsRecordsTapOrigin()
            }
        }
        .task {
            await adminRequestVM.refreshApprovalsFlag()
            await adminRequestVM.fetchMyPendingRequests()
            loaded = true
        }
        .dsAlert(
            L10n.t("سحب الطلب؟", "Withdraw request?"),
            isPresented: Binding(
                get: { requestToCancel != nil },
                set: { if !$0 { requestToCancel = nil } }
            ),
            presenting: requestToCancel
        ) { request in
            Button(L10n.t("تراجع", "Keep"), role: .cancel) {}
            Button(L10n.t("سحب الطلب", "Withdraw"), role: .destructive) {
                Task {
                    await adminRequestVM.cancelMyRequest(request)
                    if let message = adminRequestVM.errorMessage, !message.isEmpty {
                        cancelRequestError = message
                    }
                }
            }
        } message: { _ in
            Text(L10n.t("سيتم إلغاء هذا الطلب ولن يصل للإدارة.",
                        "This request will be cancelled and won't be sent to the admins."))
        }
        .dsAlert(
            L10n.t("خطأ", "Error"),
            isPresented: Binding(
                get: { cancelRequestError != nil },
                set: { if !$0 { cancelRequestError = nil } }
            )
        ) {
            Button(L10n.t("حسناً", "OK")) { cancelRequestError = nil }
        } message: {
            Text(cancelRequestError ?? "")
        }
        .dsAlert(L10n.t("تم إرسال ردّك", "Reply sent"), isPresented: $showApprovalReplySent, moment: .sentForApproval) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(L10n.t("وصل الرد إلى الإدارة، ويُستكمل الطلب بعد المراجعة.",
                        "Your reply reached the administration, and your request continues its review."))
        }
    }

    /// المسار شغّال (أو الطلب نفسه يحمل مرحلة من السيرفر) → صفّ بمرحلة الطلب ومتتبّعه (وما تطلبه الإدارة)،
    /// وإلا الصفّ كما كان
    @ViewBuilder
    private func myRequestRow(_ request: AdminRequest) -> some View {
        if let flow = adminRequestVM.memberApprovalSnapshot(for: request) {
            myApprovalRequestRow(request, flow: flow)
        } else {
            myClassicRequestRow(request)
        }
    }

    /// «مسار الموافقات» (طلب المالك ٢٠٢٦-١٠-١٥): العنوان وشارة المرحلة ← متتبّع الخطوات ← وإن طلبت
    /// الإدارة معلومات: ما تطلبه وحقل لكل مطلوب و«إرسال للإدارة» — العضو يُخاطَب بـ«الإدارة» لا بالأدوار
    private func myApprovalRequestRow(_ request: AdminRequest, flow: ApprovalSnapshot) -> some View {
        let info = myRequestDisplay(for: request)
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.md) {
                DSStateIcon(info.icon, tint: info.color, size: DS.Icon.rowLarge)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(info.title)
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                    if let target = info.target, !target.isEmpty {
                        Text(target)
                            .dsFont(.subtitle)
                            .foregroundColor(DS.Color.textSecondary)
                            .lineLimit(1)
                    }
                    ApprovalStageChips(snapshot: flow, audience: .member)
                }

                Spacer(minLength: DS.Spacing.sm)

                DSChipButton(L10n.t("سحب", "Withdraw"), tint: DS.Color.error, size: .small) { requestToCancel = request }
                    .accessibilityLabel(L10n.t("سحب الطلب", "Withdraw request"))
            }

            ApprovalTracker(stage: flow.stage, audience: .member)

            if flow.stage == .info {
                ApprovalMemberReplyCard(adminRequestVM: adminRequestVM, snapshot: flow) {
                    showApprovalReplySent = true
                }
                // سؤال جديد = مسودة جديدة (لا تبقى قيم ردّ سابق)
                .id("\(flow.requestId)-\(flow.stageSince?.timeIntervalSince1970 ?? 0)")
            }
        }
        .profileCell()
    }

    private func myClassicRequestRow(_ request: AdminRequest) -> some View {
        let info = myRequestDisplay(for: request)
        return HStack(spacing: DS.Spacing.md) {
            DSStateIcon(info.icon, tint: info.color, size: DS.Icon.rowLarge)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(info.title)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                if let target = info.target, !target.isEmpty {
                    Text(target)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                }

                // شارة «تحت المراجعة» — كبسولة الحالة المشتركة
                DSStatusChip(text: L10n.t("قيد المراجعة", "Under Review"),
                             icon: "clock.badge.questionmark", tint: DS.Color.warning)
            }

            Spacer(minLength: DS.Spacing.sm)

            // سحب/إلغاء الطلب — الشريحة الواحدة بلون الحذف
            DSChipButton(L10n.t("سحب", "Withdraw"), tint: DS.Color.error, size: .small) { requestToCancel = request }
                .accessibilityLabel(L10n.t("سحب الطلب", "Withdraw request"))
        }
        .profileCell()
    }

    private struct MyRequestDisplay {
        let icon: String
        let color: Color
        let title: String
        let target: String?
    }

    /// يشتق أيقونة/لون/عنوان/هدف الطلب حسب نوعه للعرض في «طلباتي».
    private func myRequestDisplay(for request: AdminRequest) -> MyRequestDisplay {
        let selfId = authVM.currentUser?.id
        // اسم العضو المستهدف — نُخفيه إن كان العضو نفسه (زائد بلا فائدة)
        let targetName: String? = {
            guard let m = request.member, m.id != selfId else { return nil }
            return m.displayFullName
        }()

        switch request.requestType {
        case RequestType.treeEdit.rawValue:
            let action = request.treeEditPayload?.displayAction
            let name = AdminAllRequestsView.womenSubjectName(request.treeEditPayload)
                ?? memberVM.treeEditTargetName(request.treeEditPayload)
                ?? request.treeEditPayload?.newMemberName
                ?? targetName
            return MyRequestDisplay(
                icon: action?.iconName ?? "square.and.pencil",
                color: treeEditColor(for: action),
                title: L10n.t(action?.arabicLabel ?? "طلب تعديل", action?.englishLabel ?? "Edit request"),
                target: name
            )
        case RequestType.nameChange.rawValue:
            return .init(icon: "pencil.line", color: DS.Color.info,
                         title: L10n.t("تغيير الاسم", "Name change"),
                         target: request.newValue ?? targetName)
        case RequestType.phoneChange.rawValue:
            return .init(icon: "phone.arrow.up.right", color: AppSection.profile.ink,
                         title: L10n.t("تغيير رقم الهاتف", "Phone change"), target: targetName)
        case RequestType.deceasedReport.rawValue:
            return .init(icon: "leaf.fill", color: DS.Color.textTertiary,
                         title: L10n.t("تسجيل وفاة", "Deceased report"), target: targetName)
        case RequestType.childAdd.rawValue:
            return .init(icon: "person.badge.plus", color: DS.Color.palm,
                         title: L10n.t("إضافة ابن", "Add child"), target: targetName)
        case RequestType.relativeRemove.rawValue:
            // «طلب حذف من الشجرة — {الاسم}» (§9)
            let removed = RelativeRemoveDetails.parse(request.details)?.trimmedName
            return .init(icon: "person.badge.minus", color: DS.Color.error,
                         title: RelativeRemoveDetails.genericTitle + (removed.map { " — " + $0 } ?? ""), target: nil)
        // أنواع تظهر في «طلباتي» والمسار شغّال فقط (ليُرد على سؤال المختص)
        case RequestType.familyChange.rawValue:
            return .init(icon: "person.2.fill", color: DS.Color.info,
                         title: L10n.t("تغيير العائلة", "Family change"), target: request.newValue ?? targetName)
        case RequestType.photoSuggestion.rawValue:
            return .init(icon: "camera.badge.ellipsis", color: AppSection.profile.ink,
                         title: L10n.t("اقتراح صورة", "Photo suggestion"), target: targetName)
        case RequestType.newsReport.rawValue, RequestType.contentReport.rawValue:
            return .init(icon: "exclamationmark.bubble.fill", color: DS.Color.error,
                         title: L10n.t("بلاغ", "Report"), target: nil)
        default:
            return .init(icon: "clock", color: DS.Color.warning,
                         title: L10n.t("طلب", "Request"), target: targetName)
        }
    }

    private func treeEditColor(for action: TreeEditAction?) -> Color {
        switch action {
        case .add: return DS.Color.palm
        case .editName: return DS.Color.info
        case .editPhone: return AppSection.profile.ink
        case .editBirth: return DS.Color.palm
        case .deceased, .addDeathDate: return DS.Color.textTertiary
        case .addPhoto: return AppSection.profile.ink
        case .delete: return DS.Color.error
        case .other: return DS.Color.accent
        case .none: return DS.Color.warning
        }
    }

}
