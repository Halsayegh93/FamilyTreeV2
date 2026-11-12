import SwiftUI

// MARK: - «طلب تغيير الصورة» — مربّع الإدارة (طلب المالك ٢٠٢٦-١١-١١)
//
// يُفتح من بطاقة «الصورة الشخصية» في تفاصيل إشعار التعديل (`NotificationChangeCard`) ومن «بيانات العضو»
// (`AdminMemberSheet`) — للمالك والمدير والمراقب (`canEditMembers`، والسيرفر يرفض غيرهم). هيكل المربّعات الموحّد
// (`DSComposer`): العضو باسمه الرباعي ← السبب (خلية قائمة: ثلاثة جاهزة و«سبب آخر» يفتح حقل الكتابة) ← إخفاء الصورة
// الحالية حتى يغيّرها (مطفأ افتراضياً) ← سطر التأكيد ← «إرسال الطلب» / «إلغاء». الإرسال `request_photo_change`.

struct PhotoChangeRequestBox: View {
    let member: FamilyMember
    /// بعد الإرسال الناجح (للتحديث) — المربّع يُغلق نفسه
    var onSent: (() -> Void)? = nil
    /// nil = إغلاق العرض الحالي (`dismiss`)
    var onClose: (() -> Void)? = nil

    @ObservedObject private var store = PhotoChangeRequestStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dsSection) private var section

    @State private var reason: PhotoChangeReason?
    @State private var otherText = ""
    @State private var hidePhoto = false
    @State private var isSending = false
    @State private var errorText: String?

    private var pending: PhotoChangeRequest? { store.open(for: member.id) }

    /// النص الذي يُرسل: عنوان السبب الجاهز أو المكتوب
    private var reasonText: String {
        guard let reason else { return "" }
        if reason == .other {
            return otherText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return reason.title
    }

    private var canSend: Bool {
        !reasonText.isEmpty && reasonText.count <= PhotoChangeRequestStore.reasonLimit && !isSending
    }

    private var name: String {
        let n = member.fourPartName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? member.fullName : n
    }

    var body: some View {
        DSComposer(
            title: L10n.t("طلب تغيير الصورة", "Photo change request"),
            subtitle: member.shortFullName,
            icon: "camera.badge.ellipsis",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("إرسال الطلب", "Send request"),
            actionIcon: "paperplane.fill",
            cancelTitle: L10n.t("إلغاء", "Cancel"),
            canSubmit: canSend,
            isBusy: isSending,
            onSubmit: send,
            onCancel: close
        ) {
            memberSection
            reasonSection
            hideSection
            confirmation
        }
        .task(id: member.id) { await store.refresh(memberId: member.id) }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: الأقسام

    private var memberSection: some View {
        DSComposerSection(title: L10n.t("العضو", "Member"), icon: "person.fill", index: 0) {
            NotificationSubjectCard(name: name, avatarUrl: member.avatarUrl, isWomenTree: false)
            if let pending {
                DSNoteCard(L10n.t("يوجد طلب معلّق منذ \(pending.sinceText) — السبب: \(pending.reason). الإرسال يحدّث السبب ويذكّره.",
                                  "A request has been pending since \(pending.sinceText) — reason: \(pending.reason). Sending updates the reason and reminds them."),
                           icon: "clock.fill", tint: DS.Color.warning)
            }
        }
    }

    private var reasonSection: some View {
        DSComposerSection(title: L10n.t("السبب", "Reason"), icon: "text.bubble.fill", index: 1) {
            // خلية بقائمة (قرار المالك ٢٠٢٦-١١-١١) — الثلاثة الجاهزة و«سبب آخر»
            DSMenuTile(icon: "questionmark.bubble",
                       label: L10n.t("سبب الطلب", "Reason"),
                       options: PhotoChangeReason.allCases.map {
                           DSChoiceOption(id: Optional($0), title: $0.title, icon: $0.icon)
                       },
                       selection: $reason,
                       placeholder: L10n.t("اختر السبب", "Choose a reason"))
            if reason == .other {
                DSComposerField(icon: "text.alignright",
                                label: L10n.t("السبب", "Reason"),
                                placeholder: L10n.t("اكتب السبب", "Write the reason"),
                                text: $otherText, multiline: true, limit: PhotoChangeRequestStore.reasonLimit)
                    .transition(.opacity)
            }
        }
        .animation(DS.Anim.quick, value: reason)
    }

    private var hideSection: some View {
        DSComposerSection(title: L10n.t("الصورة الحالية", "Current photo"), icon: "eye.slash.fill",
                          trailing: L10n.t("اختياري", "Optional"), index: 2) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "eye.slash.fill")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(L10n.t("إخفاء الصورة الحالية حتى يغيّرها", "Hide the current photo until it's changed"))
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.t("لا يراها الأعضاء، ويراها هو والإدارة", "Members won't see it; they and the admins still can"))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityHidden(true)
                Spacer(minLength: DS.Spacing.sm)
                Toggle(L10n.t("إخفاء الصورة الحالية حتى يغيّرها", "Hide the current photo until it's changed"), isOn: $hidePhoto)
                    .labelsHidden()
                    .tint(DS.Color.toggleOn)
                    .accessibilityLabel(L10n.t("إخفاء الصورة الحالية حتى يغيّرها", "Hide the current photo until it's changed"))
                    .accessibilityHint(L10n.t("لا يراها الأعضاء، ويراها هو والإدارة", "Members won't see it; they and the admins still can"))
            }
            .dsRowBox()
        }
    }

    /// سطر التأكيد باسمه الرباعي، ثم الخطأ إن وُجد
    @ViewBuilder
    private var confirmation: some View {
        DSNoteCard(L10n.t("سيصل الطلب إلى \(name) بإشعار، ويظهر له عند فتح التطبيق حتى يغيّر صورته.",
                          "\(name) will be notified, and asked again each time they open the app until the photo is changed."),
                   icon: "paperplane.fill")
            .dsStaggerIn(3)
        if let errorText {
            DSNoteCard(errorText, icon: "exclamationmark.circle.fill", tint: DS.Color.error)
                .transition(.opacity)
        }
    }

    // MARK: الإجراءات

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func send() {
        guard canSend else { return }
        let text = reasonText
        isSending = true
        errorText = nil
        Task {
            let failure = await store.request(memberId: member.id, reason: text, hide: hidePhoto)
            isSending = false
            if let failure {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                withAnimation(DS.Anim.quick) { errorText = failure }
                return
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIAccessibility.post(notification: .announcement,
                                 argument: L10n.t("أُرسل طلب تغيير الصورة", "Photo change request sent"))
            onSent?()
            close()
        }
    }
}

// MARK: - صفّ «بيانات العضو»

/// صفّ في بطاقة «البيانات» تحت «الصورة»: طلب معلّق («منذ … — السبب …» و«إلغاء الطلب») أو «طلب تغيير الصورة»
struct PhotoChangeRequestSheetRow: View {
    let member: FamilyMember
    /// يُعرض «طلب» (العضو مسجّل حيّ له صورة وليس أنت) — الطلب المعلّق يُعرض دائماً
    let canRequest: Bool
    let onRequest: () -> Void

    @ObservedObject private var store = PhotoChangeRequestStore.shared
    @State private var isCancelling = false
    @State private var confirmCancel = false
    @State private var failure: String?

    /// يُرسم الصفّ أصلاً؟ (طلب معلّق أو يمكن الطلب) — `AdminRowsCard` يرسم فاصلاً لكل صفّ
    static func isVisible(member: FamilyMember, canRequest: Bool) -> Bool {
        canRequest || PhotoChangeRequestStore.shared.open(for: member.id) != nil
    }

    var body: some View {
        Group {
            if let pending = store.open(for: member.id) {
                AdminSheetRow(icon: "camera.badge.clock", tint: DS.Color.warning,
                              title: L10n.t("طلب تغيير صورة معلّق", "Photo change pending"),
                              value: pendingLine(pending), multiline: true,
                              action: (L10n.t("إلغاء الطلب", "Cancel request"), { confirmCancel = true }),
                              busy: isCancelling)
            } else {
                AdminSheetRow(icon: "camera.badge.ellipsis", tint: DS.Color.sadu,
                              title: L10n.t("طلب تغيير الصورة", "Ask to change the photo"),
                              value: L10n.t("يصله إشعار بالسبب، ويُطلب منه عند فتح التطبيق", "They're notified with the reason and asked when opening the app"),
                              multiline: true,
                              action: (L10n.t("طلب", "Ask"), onRequest))
            }
        }
        .dsAlert(L10n.t("إلغاء طلب تغيير الصورة؟", "Cancel the photo change request?"), isPresented: $confirmCancel) {
            Button(L10n.t("إلغاء الطلب", "Cancel request"), role: .destructive) { cancel() }
            Button(L10n.t("رجوع", "Back"), role: .cancel) {}
        } message: {
            Text(L10n.t("لن يظهر له المربّع بعد الآن، وتظهر صورته إن كانت مخفية بسبب الطلب.",
                        "They won't be asked anymore, and the photo shows again if the request hid it."))
        }
        .dsAlert(L10n.t("تعذّر التنفيذ", "Couldn't complete"),
                 isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(L10n.t("حسناً", "OK")) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    /// «منذ 11/11/2026 — السبب: الصورة غير واضحة» (+ «الصورة مخفية»)
    private func pendingLine(_ p: PhotoChangeRequest) -> String {
        var line = L10n.t("منذ \(p.sinceText) — السبب: \(p.reason)", "Since \(p.sinceText) — reason: \(p.reason)")
        if p.hidePhoto { line += L10n.t(" · الصورة مخفية حتى يغيّرها", " · photo hidden until changed") }
        return line
    }

    private func cancel() {
        isCancelling = true
        Task {
            let error = await store.cancel(memberId: member.id)
            isCancelling = false
            if let error { failure = error }
        }
    }
}

// MARK: - زرّ بطاقة «الصورة الشخصية» في تفاصيل الإشعار

/// صفّ أمر تحت «قبل ← بعد» للصورة — يفتح مربّع الطلب فوق مربّع الإشعار
struct PhotoChangeRequestCommand: View {
    let member: FamilyMember
    @ObservedObject private var store = PhotoChangeRequestStore.shared
    @State private var target: FamilyMember?

    var body: some View {
        let pending = store.open(for: member.id)
        DSCommandRow(title: L10n.t("طلب تغيير الصورة", "Ask to change the photo"),
                     icon: "camera.badge.ellipsis",
                     hint: pending.map { L10n.t("معلّق منذ \($0.sinceText) — السبب: \($0.reason)",
                                                "Pending since \($0.sinceText) — \($0.reason)") }
                        ?? L10n.t("يصله إشعار بالسبب، ويُطلب منه عند فتح التطبيق", "They're notified with the reason and asked when opening the app")) {
            target = member
        }
        .task(id: member.id) { await store.refresh(memberId: member.id) }
        .dsCenterBox(item: $target) { m in
            PhotoChangeRequestBox(member: m, onClose: { target = nil })
        }
    }
}
