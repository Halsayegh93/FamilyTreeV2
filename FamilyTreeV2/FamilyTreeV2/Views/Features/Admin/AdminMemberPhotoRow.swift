import SwiftUI

// MARK: - صفّ «الصورة» في ورقة العضو «أ3» (الوحدة V2-3) — حالات P1 داخل الصفّ نفسه
//
// حالات P1 نفسها (`PhotoNudgeLogic.row` + `PhotoChangeRequestStore`، نفس النداءات والنصوص — كل كتابة تمرّ بـ`dryRun`
// داخل المخزن)، لكن مكانها صفّ «الصورة» بجانب سهمه (النموذج «أ3»: «زرّ إضافي، والسهم باقٍ لأن المدير يضيف الصورة
// أو يبدّلها بنفسه»):
//   لا شيء   → «الصورة · موجودة/بلا صورة ‹» (الصفّ كله يفتح مربّع الصورة لمن يعدّل)
//   نبّهه    → «الصورة / بلا صورة» + «🔔 نبّهه يضيف صورة» ذهبية بإطار + ‹ — بلا جهاز: «لا تصله الإشعارات — يظهر له عند
//              فتح التطبيق»
//   مفتوح    → «الصورة / نُبّه قبل 3 أيام · ذُكّر 1 من 3 · بانتظار صورته» + «ذكّره الحين» (كحلية) + «إلغاء التنبيه» + ‹
//   له صورة  → صفّ «الصورة … ‹» ثم صفّ «طلب تغيير الصورة / يصله إشعار بالسبب» + «طلب» (مربّع السبب `PhotoChangeRequestBox`)
// الصفّ نوع واحد (VStack) — يرسم فاصله الداخلي بنفسه فلا تعدّه البطاقة صفّين.

struct AdminMemberPhotoRow: View {
    let member: FamilyMember
    /// له حساب دخول (`AdminMemberSheetFacts.account`)
    let hasLogin: Bool
    let canEdit: Bool
    /// لا جهاز مسجّل له (لا تصله الإشعارات) — false حين لا نعرف
    let noDevices: Bool
    /// إضافة الصورة أو تبديلها (`EditMemberPhotoSheet`) — السهم
    let openPhoto: () -> Void
    /// «طلب» — مربّع السبب (`AdminMemberBox.photoRequest`)
    let askChange: () -> Void

    @EnvironmentObject private var authVM: AuthViewModel
    @ObservedObject private var store = PhotoChangeRequestStore.shared
    @ObservedObject private var config = AppConfigValues.shared
    @State private var busy = false
    @State private var confirmCancel = false
    @State private var failure: String?
    /// يعيد الحساب حين يعود «ذكّره الحين» (بعد دقيقة من آخر إشعار)
    @State private var now = Date()

    private var hasPhoto: Bool { !AdminMemberFacts.isBlank(member.avatarUrl) }

    private var state: PhotoNudgeLogic.Row {
        PhotoNudgeLogic.row(viewer: .init(authVM: authVM), member: .init(member, hasLogin: hasLogin),
                            open: store.open(for: member.id)?.nudgeOpen,
                            maxReminders: PhotoNudgeConfig.maxReminders, now: now)
    }

    private var valueText: String {
        if hasPhoto { return L10n.t("موجودة", "Added") }
        return member.avatarUnavailable == true ? L10n.t("لا توجد صورة لهذا العضو", "No photo exists") : L10n.t("بلا صورة", "No photo")
    }

    var body: some View {
        let state = self.state
        let remindAt: Date? = { if case .pending(let p) = state { return p.remindAt } else { return nil } }()
        content(state)
            .task(id: remindAt) {
                guard let remindAt else { return }
                let wait = remindAt.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64((wait + 0.5) * 1_000_000_000)) }
                if !Task.isCancelled { now = Date() }
            }
            .dsAlert(L10n.t("إلغاء التنبيه؟", "Cancel the notice?"), isPresented: $confirmCancel) {
                Button(L10n.t("إلغاء التنبيه", "Cancel notice"), role: .destructive) { cancel() }
                Button(L10n.t("رجوع", "Back"), role: .cancel) {}
            } message: {
                Text(L10n.t("لن يصله تذكير بعد الآن، ولن يظهر له المربّع. وتظهر صورته إن كانت مخفية بسبب الطلب.",
                            "No more reminders and no more box for them. The photo shows again if the request hid it."))
            }
            .dsAlert(L10n.t("تعذّر التنفيذ", "Couldn't complete"),
                     isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button(L10n.t("حسناً", "OK")) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
    }

    @ViewBuilder
    private func content(_ state: PhotoNudgeLogic.Row) -> some View {
        switch state {
        case .hidden:
            plainRow
        case .askChange:
            VStack(spacing: 0) {
                plainRow
                AdminRowDivider(inset: AdminRowDivider.iconInset)
                AdminSheetRow(icon: "camera.badge.ellipsis", tint: DS.Color.sadu,
                              title: L10n.t("طلب تغيير الصورة", "Ask to change the photo"),
                              value: L10n.t("يصله إشعار بالسبب، ثم تذكير حتى يغيّرها",
                                            "They're notified with the reason, then reminded until it's changed"),
                              action: (L10n.t("طلب", "Ask"), askChange), actionStyle: .navy)
            }
        case .nudge:
            nudgeRow
        case .pending(let p):
            pendingRow(p)
        }
    }

    // MARK: الوجوه

    /// الصفّ العادي: يُضغط كله لمن يعدّل (بسهم)، وإلا قيمة للاطلاع
    @ViewBuilder
    private var plainRow: some View {
        let row = AdminMemberRow(icon: "photo.fill", tint: DS.Color.sadu, title: L10n.t("الصورة", "Photo"),
                                 value: valueText, thumbnail: hasPhoto && !member.isFemale ? member.avatarUrl : nil)
        if canEdit {
            AdminMemberTapRow(hint: hasPhoto ? L10n.t("تغيير", "Change") : L10n.t("إضافة", "Add"), action: openPhoto) {
                row.chevron(true)
            }
        } else {
            row
        }
    }

    /// «الصورة / بلا صورة» · «نبّهه يضيف صورة» · ‹ — الحبّة تحت النص إن ضاق السطر (الخط الكبير)
    private var nudgeRow: some View {
        let line = noDevices
            ? L10n.t("لا تصله الإشعارات — يظهر له عند فتح التطبيق", "Gets no notifications — sees it when opening the app")
            : valueText
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.sm) {
                openArea(subtitle: line)
                nudgePill
                chevronButton
            }
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    openArea(subtitle: line)
                    nudgePill.padding(.leading, AdminRowDivider.iconInset)
                }
                chevronButton
            }
        }
    }

    /// طلب مفتوح: السطر (وسطر السبب) والحبّتان تحته
    private func pendingRow(_ p: PhotoNudgeLogic.Pending) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                openArea(subtitle: p.line, extra: extraLine(p))
                if busy {
                    ProgressView()
                        .scaleEffect(DS.Spinner.chipScale)
                        .frame(minWidth: DS.Icon.tapTarget, minHeight: DS.Icon.tapTarget, alignment: .leading)
                        .padding(.leading, AdminRowDivider.iconInset)
                        .accessibilityLabel(L10n.t("جارٍ الإرسال", "Sending"))
                } else if p.canRemind || p.canCancel {
                    AdminPillRow {
                        if p.canRemind {
                            AdminPillButton(title: L10n.t("ذكّره الحين", "Remind now"), style: .navy,
                                            height: DS.Hub.pillHeightCard, action: remind)
                                .fixedSize()
                        }
                        if p.canCancel {
                            AdminPillButton(title: L10n.t("إلغاء التنبيه", "Cancel notice"), style: .soft,
                                            height: DS.Hub.pillHeightCard) { confirmCancel = true }
                                .fixedSize()
                        }
                    }
                    .padding(.leading, AdminRowDivider.iconInset)
                    .padding(.bottom, DS.Spacing.xs)
                }
            }
            chevronButton
        }
    }

    /// مربّع الأيقونة والعنوان والسطر — يفتح مربّع الصورة (لمسة الصفّ)
    private func openArea(subtitle: String, extra: String? = nil) -> some View {
        Button(action: openPhoto) {
            HStack(spacing: DS.Spacing.md) {
                AdminIconSquare(symbol: "photo.fill", tint: DS.Color.sadu, filled: true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(L10n.t("الصورة", "Photo"))
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: subtitle)
                        .dsFont(.subtitle)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let extra {
                        Text(verbatim: extra)
                            .dsFont(.subtitle)
                            .foregroundColor(DS.Color.textTertiary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if hasPhoto && !member.isFemale, let raw = member.avatarUrl, let url = URL(string: raw) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(DS.Color.sadu.opacity(DS.Opacity.tintFill))
                    }
                    .frame(width: DS.Icon.section, height: DS.Icon.section)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                }
            }
            .padding(.vertical, DS.Spacing.xsm)
            .frame(minHeight: DS.Hub.rowMinHeightTwoLines)
            .contentShape(Rectangle())
        }
        .buttonStyle(AdminRowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(hasPhoto ? L10n.t("تغيير", "Change") : L10n.t("إضافة", "Add")))
    }

    /// السهم: نفس فعل الصفّ (القارئ الصوتي يقرأ الصفّ مرة)
    private var chevronButton: some View {
        Button(action: openPhoto) {
            DSChevron()
                .frame(minWidth: DS.Spacing.xl, minHeight: DS.Hub.rowMinHeightTwoLines)
                .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .accessibilityHidden(true)
    }

    /// «🔔 نبّهه يضيف صورة» — ذهبية بإطار (النموذج «أ3»)، ودوّارة أثناء الإرسال
    @ViewBuilder
    private var nudgePill: some View {
        if busy {
            ProgressView()
                .scaleEffect(DS.Spinner.chipScale)
                .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                .accessibilityLabel(L10n.t("جارٍ الإرسال", "Sending"))
        } else {
            Button(action: nudge) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "bell")
                        .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    Text(L10n.t("نبّهه يضيف صورة", "Ask for a photo"))
                        .dsFont(.hubButton)
                        .lineLimit(1)
                }
                .foregroundColor(DS.Color.accent)
                .padding(.horizontal, DS.Hub.pillPadding)
                .frame(minHeight: DS.Hub.pillHeightCard)
                .overlay(Capsule().strokeBorder(DS.Color.accentLight, lineWidth: DS.Border.widthBold))
                .dsTapArea(width: DS.Icon.tapTarget, height: DS.Hub.pillHeightCard)
            }
            .buttonStyle(DSPressStyle())
            .fixedSize()
            .accessibilityHint(Text(PhotoNudgeConfig.explanation))
        }
    }

    /// السبب (طلب التغيير) وإخفاء الصورة
    private func extraLine(_ p: PhotoNudgeLogic.Pending) -> String? {
        var parts: [String] = []
        if let reason = p.reason { parts.append(L10n.t("السبب: \(reason)", "Reason: \(reason)")) }
        if !p.isAdd, store.open(for: member.id)?.hidePhoto == true {
            parts.append(L10n.t("الصورة مخفية حتى يغيّرها", "Photo hidden until changed"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: الإجراءات (نفس `PhotoNudgeSheetRow`)

    private func nudge() {
        send(success: L10n.t("وصله التنبيه", "Notice sent")) { await store.nudge(memberId: member.id) }
    }

    private func remind() {
        send(success: L10n.t("وصله التذكير", "Reminder sent")) { await store.remind(memberId: member.id) }
    }

    private func send(success: String, _ call: @escaping () async -> String?) {
        guard !busy else { return }
        busy = true
        Task {
            let error = await call()
            busy = false
            now = Date()
            if let error {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                failure = error
            } else {
                DSMomentToast.show(success, moment: .success)
            }
        }
    }

    private func cancel() {
        busy = true
        Task {
            let error = await store.cancel(memberId: member.id)
            busy = false
            if let error {
                failure = error
            } else {
                UIAccessibility.post(notification: .announcement, argument: L10n.t("أُلغي التنبيه", "Notice cancelled"))
            }
        }
    }
}
