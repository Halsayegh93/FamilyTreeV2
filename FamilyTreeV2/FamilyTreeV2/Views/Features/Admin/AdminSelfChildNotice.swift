import SwiftUI

// MARK: - «تمت إضافة ابن» في «إشعارات الإدارة» (طلب المالك ٢٠٢٦-١١-٠٥)
//
// العضو يضيف ابنه بلا موافقة فيصل الإدارة علم وخبر، ومعه أدوات لو فيه خطأ: «الملف» (أو «راجع» عند الشك) يفتح «بيانات العضو»،
// «تنبيه» مربّع بأسباب جاهزة يرسل للأب `sendNotification`، و«حذف» مسار حذف العضو نفسه بتأكيده (`deleteMember`).
// كل زرّ بصلاحيته: `canSendNotifications` و`canDeleteMembers`؛ ولا يظهر ما لا يملكه الدور.

/// ما يحتاجه صفّ «تمت إضافة ابن» ومربّعاته
struct AdminNoticeSelfChild: Identifiable, Equatable {
    let childId: UUID
    let fatherId: UUID?
    let notificationId: UUID
    let childFirstName: String
    let childFullName: String
    let fatherName: String
    let review: Bool
    let canAlert: Bool
    let canDelete: Bool

    var id: UUID { childId }

    /// سنة الميلاد الميلادية إن عُرفت
    static func birthYear(_ raw: String?) -> Int? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count >= 4,
              let year = Int(raw.prefix(4)), year >= DeceasedMemorial.minGregorianYear else { return nil }
        return year
    }
}

enum AdminSelfChildAction {
    case openProfile, alert, delete
}

/// أسفل الصفّ: سطر الحالة («راجعه» أو «ما فيه تكرار») ثم الأزرار
struct AdminSelfChildFooter: View {
    let notice: AdminNoticeSelfChild
    let act: (AdminSelfChildAction, AdminNoticeSelfChild) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            statusLine
            HStack(spacing: DS.Spacing.xsm) {
                if notice.review {
                    pill(L10n.t("راجع", "Review"), style: .navy, action: .openProfile)
                } else {
                    pill(L10n.t("الملف", "Profile"), style: .soft, action: .openProfile)
                }
                if notice.canAlert {
                    pill(L10n.t("تنبيه", "Alert"), style: .soft, action: .alert)
                }
                if notice.canDelete {
                    pill(L10n.t("حذف", "Delete"), style: .reject, action: .delete)
                }
            }
        }
        .padding(.horizontal, DSNoticeMetrics.paddingH)
        .padding(.bottom, DSNoticeMetrics.paddingV)
    }

    private var statusLine: some View {
        let tint = notice.review ? DS.Color.warning : DS.Color.success
        return HStack(alignment: .top, spacing: DS.Spacing.xs) {
            Image(systemName: notice.review ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .dsGlyph(DS.Glyph.sm)
                .accessibilityHidden(true)
            Text(notice.review
                 ? L10n.t("راجعه: الاسم الكامل أو تاريخ الميلاد يطابق عضواً آخر، احتمال مكرر.",
                          "Review: the full name or birth date matches another member, possibly a duplicate.")
                 : L10n.t("ما فيه تكرار تحت نفس الأب", "No duplicate under the same father"))
                .dsFont(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(tint)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xsm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .fill(tint.opacity(DS.Opacity.tintFill)))
    }

    private func pill(_ title: String, style: AdminPillStyle, action: AdminSelfChildAction) -> some View {
        AdminTapWrap(tap: .action { act(action, notice) },
                     label: AnyView(AdminPillLabel(title: title, style: style, fullWidth: true)),
                     accessibilityLabel: "\(title): \(notice.childFullName)")
            .frame(maxWidth: .infinity)
    }
}

// MARK: - المربّعات

/// حالة مربّعات صفّ الابن في الصفحة
struct AdminSelfChildFlow {
    var sheet: AdminMemberSheetContext?
    var alert: AdminNoticeSelfChild?
    var deleting: AdminNoticeSelfChild?
    var failure: String?
    var alertSent = false
}

/// الورقة والمربّعات وتأكيد الحذف — نوع مستقل (حارس المكدس)
struct AdminSelfChildFlowModifier: ViewModifier {
    @Binding var flow: AdminSelfChildFlow
    /// أبناء لم يصلوا لقائمة الأعضاء بعد
    let missingChildren: [UUID]
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel

    private static let maxChildFetch = 20

    func body(content: Content) -> some View {
        content
            .task(id: missingChildren) {
                for id in missingChildren.prefix(Self.maxChildFetch) where !Task.isCancelled {
                    await memberVM.fetchSingleMember(id: id)
                }
            }
            .dsTallBox(item: $flow.sheet) { context in
                AnyView(AdminMemberSheet(ids: context.ids, start: context.start))
            }
            .dsCenterBox(item: $flow.alert) { notice in
                AnyView(AdminChildAlertBox(notice: notice,
                                           onClose: { flow.alert = nil },
                                           onSent: { alertSent(notice) }))
            }
            // نفس تأكيد «حذف العضو نهائياً» في «بيانات العضو»
            .dsAlert(AdminMemberConfirm.delete.title,
                     isPresented: Binding(get: { flow.deleting != nil }, set: { if !$0 { flow.deleting = nil } }),
                     presenting: flow.deleting) { notice in
                Button(AdminMemberConfirm.delete.button, role: .destructive) { delete(notice) }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { flow.deleting = nil }
            } message: { _ in
                Text(AdminMemberConfirm.delete.message)
            }
            .dsAlert(L10n.t("تعذّر التنفيذ", "Couldn't complete"),
                     isPresented: Binding(get: { flow.failure != nil }, set: { if !$0 { flow.failure = nil } })) {
                Button(L10n.t("حسناً", "OK")) { flow.failure = nil }
            } message: {
                Text(flow.failure ?? "")
            }
            .dsAlert(L10n.t("أُرسل التنبيه", "Alert sent"), isPresented: $flow.alertSent, moment: .success) {
                Button(L10n.t("حسناً", "OK")) {}
            }
    }

    private func alertSent(_ notice: AdminNoticeSelfChild) {
        flow.alert = nil
        Task {
            await notificationVM.markNotificationAsRead(id: notice.notificationId)
            // بعد إغلاق المربّع — لا تتداخل حركتاهما
            try? await Task.sleep(nanoseconds: UInt64(DSMotion.boxHandoff * 1_000_000_000))
            flow.alertSent = true
        }
    }

    /// مسار حذف العضو نفسه (`AdminMemberSheet`) — حماية الروابط ترفض برسالة السيرفر
    private func delete(_ notice: AdminNoticeSelfChild) {
        flow.deleting = nil
        Task {
            if await memberVM.deleteMember(memberId: notice.childId) {
                NotificationCenter.default.post(name: .memberDeleted, object: notice.childId)
                await notificationVM.fetchNotifications(force: true)
            } else {
                flow.failure = memberVM.errorMessage
                    ?? L10n.t("تأكد من الاتصال ثم حاول مرة أخرى.", "Check your connection and try again.")
            }
        }
    }
}

/// «تنبيه لـ…»: سبب يعبّي نصّاً جاهزاً يقدر يعدّله، ويوصل الأب في إشعاراته
struct AdminChildAlertBox: View {
    let notice: AdminNoticeSelfChild
    let onClose: () -> Void
    let onSent: () -> Void
    @EnvironmentObject private var notificationVM: NotificationViewModel

    enum Reason: String, CaseIterable, Identifiable {
        case duplicateName, wrongName, wrongBirth, notYourSon
        var id: String { rawValue }

        var title: String {
            switch self {
            case .duplicateName: return L10n.t("الاسم مكرر", "Duplicate name")
            case .wrongName:     return L10n.t("الاسم غلط", "Wrong name")
            case .wrongBirth:    return L10n.t("الميلاد غلط", "Wrong birth date")
            case .notYourSon:    return L10n.t("مو ابنك", "Not your son")
            }
        }

        /// نصّ يُحفظ في الإشعار ويقرؤه الأب
        func body(child: String) -> String {
            switch self {
            case .duplicateName:
                return L10n.stored("الاسم «\(child)» يمكن مكرر في الشجرة. تأكد منه، وإذا كان خطأ احذفه من «عائلتي».",
                                   "The name «\(child)» may be a duplicate in the tree. Please check it, and delete it from «My Family» if it's wrong.")
            case .wrongName:
                return L10n.stored("الاسم «\(child)» يمكن فيه خطأ. تأكد منه وعدّله من «عائلتي».",
                                   "The name «\(child)» may be misspelled. Please check it and correct it from «My Family».")
            case .wrongBirth:
                return L10n.stored("تاريخ ميلاد «\(child)» يمكن غلط. تأكد منه وعدّله من «عائلتي».",
                                   "The birth date of «\(child)» may be wrong. Please check it and correct it from «My Family».")
            case .notYourSon:
                return L10n.stored("«\(child)» مسجّل تحتك كابن. إذا مو ابنك احذفه من «عائلتي».",
                                   "«\(child)» is registered as your son. If he isn't, delete him from «My Family».")
            }
        }
    }

    private static let bodyLimit = 300

    @State private var text = ""
    @State private var picked: Reason?
    @State private var isSending = false
    @State private var failed = false

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var noticeTitle: String { L10n.stored("تنبيه من الإدارة", "Notice from the administration") }

    var body: some View {
        DSComposer(
            title: L10n.t("تنبيه لـ«\(notice.fatherName)»", "Alert to «\(notice.fatherName)»"),
            subtitle: L10n.t("عن: \(notice.childFullName)", "About: \(notice.childFullName)"),
            icon: "exclamationmark.bubble.fill",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("إرسال التنبيه", "Send alert"),
            actionIcon: "paperplane.fill",
            canSubmit: !trimmed.isEmpty && !isSending,
            isBusy: isSending,
            hasUnsavedChanges: !trimmed.isEmpty,
            onSubmit: send,
            onCancel: onClose
        ) {
            DSComposerSection(title: L10n.t("السبب", "Reason"), icon: "tag.fill", tint: DS.Color.primary, index: 0) {
                NotifFlow {
                    ForEach(Reason.allCases) { reason in
                        DSChipButton(reason.title, isSelected: picked == reason) {
                            picked = reason
                            text = reason.body(child: notice.childFirstName)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            DSComposerSection(title: L10n.t("نص التنبيه", "Alert text"), icon: "text.bubble.fill", tint: DS.Color.primary, index: 1) {
                DSComposerField(icon: "pencil", label: L10n.t("النص", "Text"),
                                placeholder: L10n.t("اختر سبباً أو اكتب نصّك", "Pick a reason or write your own"),
                                text: $text, tint: DS.Color.primary, multiline: true, lines: 3...6, limit: Self.bodyLimit)
            }
            if !trimmed.isEmpty {
                DSComposerSection(title: L10n.t("يوصله في إشعاراته", "What he'll see in his notifications"),
                                  icon: "bell.fill", tint: DS.Color.primary, index: 2) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(verbatim: noticeTitle)
                            .dsFont(.rowTitle)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(verbatim: trimmed)
                            .dsFont(.callout)
                            .foregroundColor(DS.Color.textSecondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if failed {
                DSNoteCard(L10n.t("تعذّر إرسال التنبيه. حاول مرة أخرى.", "Couldn't send the alert. Try again."),
                           icon: "exclamationmark.circle.fill", tint: DS.Color.error)
            }
        }
    }

    private func send() {
        guard !isSending, !trimmed.isEmpty, notice.canAlert, let father = notice.fatherId else { return }
        isSending = true
        failed = false
        let body = trimmed
        Task {
            let ok = await notificationVM.sendNotification(title: noticeTitle, body: body,
                                                           targetMemberIds: [father], kind: "admin")
            isSending = false
            if ok { onSent() } else { failed = true }
        }
    }
}
