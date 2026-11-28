import SwiftUI

// MARK: - «تمت إضافة ابن» في «إشعارات الإدارة» (طلب المالك ٢٠٢٦-١١-٠٥)
//
// العضو يضيف ابنه بلا موافقة فيصل الإدارة علم وخبر، ومعه أدوات لو فيه خطأ: «الملف» (كحلي عند الشك) يفتح ورقة العضو،
// و«تنبيه» مربّع بأسباب جاهزة يرسل للأب `sendNotification` (هذا الصفّ بيته). كل زرّ بصلاحيته (`canSendNotifications`)،
// ولا يظهر ما لا يملكه الدور.
// إعادة تصميم الإدارة (U18، T4 — spec E.21): «حذف» حُذف من الإشعار. حذف العضو له بيت واحد: آخر صفّ أحمر في ورقة العضو،
// يفتحها «الملف». الكتابة (التنبيه، «مقروء») تمرّ بـ`AdminNoticeWrites` (DRY-RUN في تجربة الأدوار — T0).

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
    /// باقي «تغييرات الأعضاء» (طلب المالك «زر للتنبيه إذا في شي خطأ»): زرّ «تنبيه» وحده لمن غيّر البيانات
    var isGeneral = false

    var id: UUID { childId }

    /// سنة الميلاد الميلادية إن عُرفت
    static func birthYear(_ raw: String?) -> Int? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count >= 4,
              let year = Int(raw.prefix(4)), year >= DeceasedMemorial.minGregorianYear else { return nil }
        return year
    }
}

enum AdminSelfChildAction {
    case openProfile, alert
}

// MARK: - المربّعات

/// حالة مربّعات صفّ الابن في الصفحة
struct AdminSelfChildFlow {
    var sheet: AdminMemberSheetContext?
    var alert: AdminNoticeSelfChild?
    var alertSent = false
}

/// ورقة العضو ومربّع «تنبيه» ولحظة «أُرسل» — نوع مستقل (حارس المكدس)
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
            .dsAlert(L10n.t("أُرسل التنبيه", "Alert sent"), isPresented: $flow.alertSent, moment: .success) {
                Button(L10n.t("حسناً", "OK")) {}
            }
    }

    private func alertSent(_ notice: AdminNoticeSelfChild) {
        flow.alert = nil
        Task {
            await AdminNoticeWrites.markRead([notice.notificationId], notificationVM)
            // بعد إغلاق المربّع — لا تتداخل حركتاهما
            try? await Task.sleep(nanoseconds: UInt64(DSMotion.boxHandoff * 1_000_000_000))
            flow.alertSent = true
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
        case duplicateName, wrongName, wrongBirth, notYourSon, badPhoto, wrongData
        var id: String { rawValue }

        static func options(general: Bool) -> [Reason] {
            general ? [.wrongName, .wrongBirth, .badPhoto, .wrongData] : [.duplicateName, .wrongName, .wrongBirth, .notYourSon]
        }

        /// نصوص رسمية (طلب المالك ٢٠٢٦-١١-٠٧ «نخليها رسمية»)، ويقدر السيرفر يبدّلها بلا بناء:
        /// `app_config.child_alert_texts` = {"<السبب>": {"title": "…", "body": "… {name} …"}, "<السبب>_general": {…}}
        @MainActor private func serverText(_ field: String, general: Bool) -> String? {
            guard let all = AppConfigValues.shared.values["child_alert_texts"] as? [String: Any] else { return nil }
            let entry = (general ? all["\(rawValue)_general"] as? [String: Any] : nil) ?? all[rawValue] as? [String: Any]
            guard let t = (entry?[field] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }

        @MainActor var title: String {
            if let t = serverText("title", general: false) { return t }
            switch self {
            case .duplicateName: return L10n.t("الاسم مكرّر", "Duplicate name")
            case .wrongName:     return L10n.t("خطأ في الاسم", "Incorrect name")
            case .wrongBirth:    return L10n.t("خطأ في تاريخ الميلاد", "Incorrect birth date")
            case .notYourSon:    return L10n.t("ليس من الأبناء", "Not your son")
            case .badPhoto:      return L10n.t("الصورة غير مناسبة", "Unsuitable photo")
            case .wrongData:     return L10n.t("خطأ في البيانات", "Incorrect details")
            }
        }

        /// نصّ يُحفظ في الإشعار ويقرؤه الأب
        @MainActor func body(child: String, general: Bool = false) -> String {
            if let t = serverText("body", general: general) { return t.replacingOccurrences(of: "{name}", with: child) }
            switch self {
            case .wrongName where general:
                return L10n.stored("نأمل مراجعة الاسم «\(child)» وتصحيحه، إذ يُرجَّح وجود خطأ فيه.",
                                   "Please review and correct the name «\(child)», as it may contain an error.")
            case .wrongBirth where general:
                return L10n.stored("نأمل مراجعة تاريخ ميلاد «\(child)» وتصحيحه، إذ يُرجَّح وجود خطأ فيه.",
                                   "Please review and correct the birth date of «\(child)», as it may contain an error.")
            case .badPhoto:
                return L10n.stored("نأمل استبدال صورة «\(child)»، إذ إنها غير مناسبة.",
                                   "Please replace the photo of «\(child)», as it is not suitable.")
            case .wrongData:
                return L10n.stored("نأمل مراجعة بيانات «\(child)» التي جرى تعديلها، إذ يُرجَّح وجود خطأ فيها.",
                                   "Please review the edited details of «\(child)», as they may contain an error.")
            case .duplicateName:
                return L10n.stored("يُرجَّح أن الاسم «\(child)» مكرّر في الشجرة. نأمل التحقق منه، وحذفه من «الأسرة» إن ثبت تكراره.",
                                   "The name «\(child)» may be a duplicate in the tree. Please verify it and delete it from «My Family» if so.")
            case .wrongName:
                return L10n.stored("نأمل مراجعة الاسم «\(child)» وتصحيحه من «الأسرة»، إذ يُرجَّح وجود خطأ فيه.",
                                   "Please review and correct the name «\(child)» from «My Family», as it may contain an error.")
            case .wrongBirth:
                return L10n.stored("نأمل مراجعة تاريخ ميلاد «\(child)» وتصحيحه من «الأسرة»، إذ يُرجَّح وجود خطأ فيه.",
                                   "Please review and correct the birth date of «\(child)» from «My Family», as it may contain an error.")
            case .notYourSon:
                return L10n.stored("«\(child)» مسجّل ضمن أبنائك. إن لم يكن من أبنائك، نأمل حذفه من «الأسرة».",
                                   "«\(child)» is registered as your son. If he is not, please delete him from «My Family».")
            }
        }
    }

    private static let bodyLimit = 300

    @State private var text = ""
    @State private var picked: Reason?
    @State private var isSending = false
    @State private var failed = false

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var noticeTitle: String { AdminAlertProfileCard.title }

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
                    ForEach(Reason.options(general: notice.isGeneral)) { reason in
                        DSChipButton(reason.title, isSelected: picked == reason) {
                            picked = reason
                            text = reason.body(child: notice.childFirstName, general: notice.isGeneral)
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
                            .dsFont(.adminRowTitle)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(verbatim: trimmed)
                            .dsFont(.adminRowSubtitle)
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
            let ok = await AdminNoticeWrites.sendAlert(title: noticeTitle, body: body, to: father, notificationVM)
            isSending = false
            if ok { onSent() } else { failed = true }
        }
    }
}

// MARK: - التنبيه عند العضو في «حسابي» (طلب المالك ٢٠٢٦-١١-٠٥ «بمركز الإشعارات والملف الشخصي وبشكل بسيط»)

/// آخر تنبيه من الإدارة لم يُقرأ — يختفي بـ«تم» أو حين يقرؤه من مركز الإشعارات
struct AdminAlertProfileCard: View {
    static let title = L10n.stored("تنبيه من الإدارة", "Notice from the administration")
    @EnvironmentObject private var notificationVM: NotificationViewModel

    var body: some View {
        if let alert = notificationVM.notifications.first(where: { $0.title == Self.title && !$0.read }) {
            AdminAlertCardBody(text: alert.body) {
                Task { await notificationVM.markNotificationAsRead(id: alert.id) }
            }
        }
    }
}

struct AdminAlertCardBody: View {
    let text: String
    let onDone: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: "exclamationmark.bubble.fill")
                .dsGlyph(DS.Glyph.lg)
                .foregroundColor(DS.Color.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: AdminAlertProfileCard.title)
                    .dsFont(.adminRowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                Text(verbatim: text)
                    .dsFont(.adminRowSubtitle)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DSChipButton(L10n.t("تم", "Done"), size: .small, action: onDone)
        }
        .dsCard()
    }
}
