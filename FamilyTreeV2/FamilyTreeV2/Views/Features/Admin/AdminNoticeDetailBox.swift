import SwiftUI

// MARK: - تفاصيل إشعار الإدارة «بلا تكرار» (اختيار المالك ٢٠٢٦-١١-٠٦ — العيّنة ٢ «أ» و٣ «أ»)
//
// لتغييرات الأعضاء ونشاط الفريق (الطلبات والنظام يبقون في `NotificationDetailBox` بقرارهم):
//   • العنوان = نوع الحدث («إضافة ابن»، «تعديل بيانات»)، وتحته الشجرة والوقت
//   • الشخص مرة واحدة في بطاقته (يفتح ملفه)، والنص يختفي إن كرّر العنوان أو البطاقة، ثم «قبل ← بعد»
//   • «تم» و«فيه خطأ؟» (و«حذف» بتأكيد للابن المضاف لمن يملكه)
//   • «فيه خطأ؟» يفتح الأسباب في المربّع نفسه: سبب جاهز ← الجملة التي ستصله ← «أرسل لـفلان»؛ الكتابة اختيارية («أضف
//     ملاحظة»)، وبعد الإرسال سطر «أُرسل» في المربّع بدل نافذة النجاح. الإرسال نفسه القديم: إشعار «تنبيه من الإدارة»
//     (`sendNotification`، `kind: admin`) يصل العضو في إشعاراته وبطاقة «حسابي» — بلا شيء جديد على السيرفر.
// كل جزء نوع صغير مستقل (حارس المكدس).

/// نصوص الإشعار بلا تكرار — العنوان والشخص ومَن فعل
enum AdminNoticeText {
    /// نوع الحدث: من `details.action` (v2) أو «تمت إضافة ابن»، وإلا عنوان السيرفر قبل «:»
    static func eventTitle(_ n: AppNotification) -> String {
        let women = n.details?.tree == "women"
        if n.details?.selfChild == true { return L10n.t("إضافة ابن", "Son added") }
        switch n.details?.action {
        case "edit":   return L10n.t("تعديل بيانات", "Details changed")
        case "add":    return women ? L10n.t("إضافة في شجرة النساء", "Added to women's tree")
                                    : L10n.t("إضافة عضو", "Member added")
        case "delete": return women ? L10n.t("حذف من شجرة النساء", "Removed from women's tree")
                                    : L10n.t("حذف عضو", "Member removed")
        default:
            let head = n.title.split(separator: ":", maxSplits: 1).first.map(String.init) ?? n.title
            return head.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// اسم الشخص المعني (مرة واحدة) — ثلاثة أسماء متتالية «علي محمدحسين عبدالله» (طلب المالك ٢٠٢٦-١١-٠٧)
    static func subjectName(_ n: AppNotification, member: (UUID) -> FamilyMember?) -> String {
        let m = NotificationDetailParts.subjectMember(n, member: member)
        return (m?.chainThreeName ?? PersonName.firstThree(n.details?.subject?.name ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// مكان التغيير من `details.tree` (السيرفر يسجّله لكل تغيير v2): «شجرة النساء» أو «شجرة العائلة»
    static func treeLabel(_ n: AppNotification) -> String? {
        switch n.details?.tree {
        case "women": return L10n.t("شجرة النساء", "Women's tree")
        case "main":  return L10n.t("شجرة العائلة", "Family tree")
        default:      return nil
        }
    }

    /// غيّرها أحد الطاقم (لا العضو نفسه): `details.actor.is_admin`، وإلا `details.sender.type`.
    /// المشرف الذي عدّل بياناته هو تعديل «بنفسه»
    static func isStaffChange(_ n: AppNotification) -> Bool {
        let actorId = n.createdBy?.uuidString.lowercased() ?? n.details?.actor?.id?.lowercased()
        let subjectId = n.subjectMemberId?.uuidString.lowercased() ?? n.details?.subject?.id?.lowercased()
        if let actorId, actorId == subjectId { return false }
        if let isAdmin = n.details?.actor?.isAdmin { return isAdmin }
        return n.details?.sender?.type == "admin"
    }

    /// عنوان قسم «قبل ← بعد»: «تغييرات الإدارة» لما يغيّرها الطاقم، وإلا «تغييرات العضو»
    static func changesTitle(_ n: AppNotification) -> String {
        isStaffChange(n) ? L10n.t("تغييرات الإدارة", "Admin changes") : L10n.t("تغييرات العضو", "Member's changes")
    }

    /// الأسماء الطويلة بين «» في نصوص السيرفر القديمة ← ثلاثة أسماء
    static func shortenQuotedNames(_ text: String) -> String {
        guard text.contains("«") else { return text }
        var out = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "«"), let close = rest[open...].firstIndex(of: "»") {
            out += String(rest[..<open]) + "«" + PersonName.firstThree(String(rest[rest.index(after: open)..<close])) + "»"
            rest = rest[rest.index(after: close)...]
        }
        return out + String(rest)
    }

    static func birthYear(_ n: AppNotification, member: (UUID) -> FamilyMember?) -> Int? {
        AdminNoticeSelfChild.birthYear(NotificationDetailParts.subjectMember(n, member: member)?.birthDate)
    }

    /// مَن فعل: «أضافه أبوه فهد» للابن، «بنفسه» لمن عدّل بياناته، وإلا «بواسطة: فلان»
    static func actorLine(_ n: AppNotification, member: (UUID) -> FamilyMember?) -> String? {
        let actorId = n.createdBy ?? n.details?.actor?.id.flatMap(UUID.init(uuidString:))
        let actor = actorId.flatMap(member)
        let name = actor?.chainThreeName ?? (n.details?.actor?.name ?? n.details?.sender?.name).map(PersonName.firstThree)
        guard let name, !name.isEmpty else { return nil }
        if n.details?.selfChild == true { return L10n.t("أضافه أبوه \(name)", "Added by his father \(name)") }
        if let actorId, let subject = NotificationDetailParts.subjectMember(n, member: member)?.id, subject == actorId {
            return L10n.t("بنفسه", "By themselves")
        }
        return L10n.t("بواسطة: \(name)", "By \(name)")
    }

    /// النص يكرّر العنوان أو الشخص أو التغييرات — لا يُعرض
    static func bodyRepeats(_ n: AppNotification, title: String, person: String) -> Bool {
        let body = n.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty || n.details?.selfChild == true || !(n.details?.changes ?? []).isEmpty { return true }
        if n.details?.action != nil { return true }
        if body == title || body == n.title || title.contains(body) || n.title.contains(body) { return true }
        return !person.isEmpty && body == person
    }
}

/// مربّع التفاصيل
struct AdminNoticeDetailBox: View {
    let notification: AppNotification
    let categoryTitle: String
    let icon: String
    /// أدوات الابن المضاف أو «فيه خطأ؟» لمن غيّر البيانات — nil = بلا تنبيه
    let notice: AdminNoticeSelfChild?
    let onClose: () -> Void
    /// ملف العضو (`AdminMemberSheet`) — الصفحة تغلق المربّع أولاً
    let onOpenProfile: (UUID) -> Void
    let onDelete: (AdminNoticeSelfChild) -> Void

    @EnvironmentObject private var memberVM: MemberViewModel

    @State private var reporting = false

    private var subject: FamilyMember? {
        NotificationDetailParts.subjectMember(notification, member: { memberVM.member(byId: $0) })
    }
    private var title: String { AdminNoticeText.eventTitle(notification) }
    private var person: String { AdminNoticeText.subjectName(notification, member: { memberVM.member(byId: $0) }) }

    private var subtitle: String {
        var parts: [String] = []
        if let tree = AdminNoticeText.treeLabel(notification) { parts.append(tree) }
        parts.append(AdminNoticeRow.relative(notification.createdDate))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NotificationRichBox(chips: [(categoryTitle, .gold)], tile: .glyph(icon), title: title, subtitle: subtitle,
                            onClose: onClose, content: content)
    }

    private var content: AnyView {
        let changes = notification.details?.changes ?? []
        let body = notification.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return AnyView(VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if !person.isEmpty {
                AnyView(personCard)
            }
            if !AdminNoticeText.bodyRepeats(notification, title: title, person: person) {
                NotifQuoteCard(text: AnyView(Text(verbatim: body).dsFont(.body).foregroundColor(DS.Color.textPrimary)))
            }
            if !changes.isEmpty {
                NotifBoxLabel(text: AdminNoticeText.changesTitle(notification))
                NotificationChangeCards(changes: changes, isStaff: true, subjectName: person)
            }
            if reporting, let notice {
                AdminNoticeReportPanel(notice: notice, onBack: { withAnimation(DS.Anim.quick) { reporting = false } })
            } else {
                footer
            }
        })
    }

    /// الشخص مرة واحدة: الصورة · الاسم · مواليد ومَن فعل · الحالة — يفتح ملفه
    private var personCard: some View {
        let year = AdminNoticeText.birthYear(notification, member: { memberVM.member(byId: $0) })
        let line = [year.map { L10n.t("مواليد \($0)", "Born \($0)") },
                    AdminNoticeText.actorLine(notification, member: { memberVM.member(byId: $0) })]
            .compactMap { $0 }.joined(separator: " · ")
        let status = notice.flatMap { $0.isGeneral ? nil : $0 }
        return Button {
            if let id = subject?.id { onOpenProfile(id) }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSMemberAvatar(name: subject?.firstName ?? person, avatarUrl: subject?.avatarUrl, size: DS.Icon.rowLarge)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(verbatim: person)
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !line.isEmpty {
                        Text(verbatim: line)
                            .dsFont(.caption)
                            .foregroundColor(DS.Color.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if let status { AdminSelfChildStatusChip(review: status.review) }
                if subject != nil { DSChevron() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsRowBox()
        }
        .buttonStyle(DSScaleButtonStyle())
        .disabled(subject == nil)
        .accessibilityHint(subject != nil ? L10n.t("يفتح ملف العضو", "Opens the member's profile") : "")
    }

    private var footer: NotifButtonRow {
        let canAlert = notice?.canAlert == true && notice?.fatherId != nil
        var items: [NotifButtonRow.Item] = [.init(title: L10n.t("تم", "Done"), kind: .primary, action: onClose)]
        if canAlert {
            items.append(.init(title: L10n.t("إرسال تنبيه", "Send a notice"), kind: .secondary) {
                withAnimation(DS.Anim.quick) { reporting = true }
            })
        }
        if let notice, notice.canDelete, !notice.isGeneral {
            items.append(.init(title: L10n.t("حذف", "Delete"), kind: .reject) { onDelete(notice) })
        }
        return NotifButtonRow(items: items)
    }
}

// MARK: - «فيه خطأ؟» داخل المربّع

/// الأسباب الجاهزة في المربّع نفسه: سبب ← الجملة التي تصله ← «أرسل لـفلان»؛ الملاحظة اختيارية
struct AdminNoticeReportPanel: View {
    let notice: AdminNoticeSelfChild
    let onBack: () -> Void

    @EnvironmentObject private var notificationVM: NotificationViewModel
    @EnvironmentObject private var memberVM: MemberViewModel

    private typealias Reason = AdminChildAlertBox.Reason
    private static let noteLimit = 300

    @State private var picked: Reason?
    @State private var addsNote = false
    @State private var note = ""
    @State private var isSending = false
    @State private var failed = false
    @State private var sent = false

    private var recipient: String {
        notice.fatherId.flatMap { memberVM.member(byId: $0)?.firstName }
            ?? notice.fatherName.split(separator: " ").first.map(String.init) ?? notice.fatherName
    }

    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// النص الذي يصله: جملة السبب ثم الملاحظة
    private var message: String {
        let reason = picked?.body(child: notice.childFirstName, general: notice.isGeneral)
        return [reason, trimmedNote.isEmpty ? nil : trimmedNote].compactMap { $0 }.joined(separator: "\n")
    }

    var body: some View {
        if sent {
            sentLine
        } else {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                NotifBoxLabel(text: L10n.t("اختر سبب التنبيه", "Choose the reason"))
                reasons
                noteArea
                if failed {
                    DSNoteCard(L10n.t("تعذّر الإرسال. حاول مرة أخرى.", "Couldn't send. Try again."),
                               icon: "exclamationmark.circle.fill", tint: DS.Color.error)
                }
                NotifButtonRow(items: [
                    .init(title: isSending ? L10n.t("جارٍ الإرسال…", "Sending…") : L10n.t("أرسل لـ\(recipient)", "Send to \(recipient)"),
                          kind: .primary, disabled: message.isEmpty || isSending, action: send),
                    .init(title: L10n.t("رجوع", "Back"), kind: .secondary, disabled: isSending, action: onBack),
                ])
            }
        }
    }

    private var reasons: some View {
        let options = Reason.options(general: notice.isGeneral)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, reason in
                VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
                    Button {
                        withAnimation(DS.Anim.quick) { picked = picked == reason ? nil : reason }
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: picked == reason ? "largecircle.fill.circle" : "circle")
                                .dsGlyph(DS.Glyph.lg, weight: .regular)
                                .foregroundColor(picked == reason ? DS.Color.primary : DS.Color.textTertiary)
                                .accessibilityHidden(true)
                            Text(verbatim: reason.title)
                                .dsFont(.rowTitle)
                                .foregroundColor(DS.Color.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(picked == reason ? .isSelected : [])
                    if picked == reason {
                        // الجملة التي تصله بالضبط
                        Text(verbatim: reason.body(child: notice.childFirstName, general: notice.isGeneral))
                            .dsFont(.caption)
                            .foregroundColor(DS.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(DS.Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .dsWhiteTile(radius: DS.Radius.sm)
                            .padding(.bottom, DS.Spacing.sm)
                            .accessibilityLabel(L10n.t("يصله: ", "He'll see: ") + reason.body(child: notice.childFirstName,
                                                                                               general: notice.isGeneral))
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                if index < options.count - 1 { AdminRowDivider() }
            }
        }
        .dsRowBox()
    }

    @ViewBuilder
    private var noteArea: some View {
        if addsNote {
            TextField(L10n.t("ملاحظة (اختيارية)", "Note (optional)"), text: $note, axis: .vertical)
                .dsFieldFont(.fieldValue)
                .lineLimit(2...5)
                .padding(DS.Spacing.sm)
                .dsWhiteTile(radius: DS.Radius.sm)
                .onChange(of: note) { value in
                    if value.count > Self.noteLimit { note = String(value.prefix(Self.noteLimit)) }
                }
        } else {
            Button {
                withAnimation(DS.Anim.quick) { addsNote = true }
            } label: {
                Label(L10n.t("أضف ملاحظة", "Add a note"), systemImage: "plus")
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.primary)
                    .frame(minHeight: DS.Icon.tapTarget)
            }
            .buttonStyle(.plain)
        }
    }

    private var sentLine: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .dsGlyph(DS.Glyph.md)
                .accessibilityHidden(true)
            Text(verbatim: L10n.t("أُرسل لـ\(recipient)", "Sent to \(recipient)"))
                .dsFont(.rowTitle)
            Spacer(minLength: 0)
        }
        .foregroundColor(DS.Color.success)
        .padding(.horizontal, DS.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: DSBox.buttonHeight, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .fill(DS.Color.success.opacity(DS.Opacity.tintFill)))
        .accessibilityElement(children: .combine)
    }

    private func send() {
        let body = message
        guard !isSending, !body.isEmpty, notice.canAlert, let father = notice.fatherId else { return }
        isSending = true
        failed = false
        Task {
            let ok = await notificationVM.sendNotification(title: AdminAlertProfileCard.title, body: body,
                                                           targetMemberIds: [father], kind: "admin")
            isSending = false
            if ok {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(DS.Anim.quick) { sent = true }
                UIAccessibility.post(notification: .announcement,
                                     argument: L10n.t("أُرسل لـ\(recipient)", "Sent to \(recipient)"))
                await notificationVM.markNotificationAsRead(id: notice.notificationId)
            } else {
                failed = true
            }
        }
    }
}
