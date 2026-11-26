import SwiftUI

// MARK: - «الصورة» في ورقة العضو — معلومة في «البيانات»، وأوامرها في «إجراءات الإدارة» (F4، طلب المالك ٢٠٢٦-١١-٢٦:
// «اهم شي نفصل الأمور الادارية عن الاعضاء»)
//
// ١) `AdminMemberPhotoRow` — صفّ «البيانات»: «الصورة · موجودة/بلا صورة» بالمصغّرة (للذكور)، والصفّ كله يفتح مربّع الصورة
//    لمن يعدّل (إضافة الصورة أو تبديلها تعديلُ بيانات لا أمرُ إدارة). لا حبّة «نبّهه» هنا بعد اليوم.
//    «له صورة» = `avatar_url` أو `photo_url` (نفس `PhotoNudgeLogic.hasPhoto` والسيرفر — F4، V26).
// ٢) `AdminMemberPhotoActions` — صفّ بطاقة «إجراءات الإدارة» بحالات P1 نفسها (`PhotoNudgeLogic.row` +
//    `PhotoChangeRequestStore`، كل كتابة تمرّ بـ`dryRun` داخل المخزن):
//      نبّهه   → «تنبيه لإضافة صورة / يصله إشعار، ثم تذكير…» + «🔔 نبّهه يضيف صورة» (بلا جهاز: «لا تصله الإشعارات…»)
//      مفتوح   → «نُبّه قبل 3 أيام · ذُكّر 1 من 3 · بانتظار صورته» + «ذكّره الحين» + «إلغاء التنبيه» (بتأكيد)
//      له صورة → «طلب تغيير الصورة / يصله إشعار بالسبب» + «طلب» (مربّع السبب `PhotoChangeRequestBox`)
//    النتائج الصادقة (F4): «وصله التنبيه» حين تغيّر notified_at فعلاً، وإلا «أُرسل له قبل أقل من دقيقة» (V15)؛ رفض لأن له
//    صورة الآن ← يُحدَّث العضو و«أضاف صورته — حدّثنا البيانات» (V11). الورقة تضعه بـ`.id(member.id)` فتبدأ حالته من
//    جديد مع كل عضو (V29)، و`working` يعطّل «السابق/التالي» أثناء الإرسال (V27).

struct AdminMemberPhotoRow: View {
    let member: FamilyMember
    let canEdit: Bool
    /// إضافة الصورة أو تبديلها (`EditMemberPhotoSheet`)
    let openPhoto: () -> Void

    private var hasPhoto: Bool { PhotoNudgeLogic.hasPhoto(avatar: member.avatarUrl, photo: member.photoURL) }

    /// المصغّرة: الأفاتار وإلا الصورة — لا صور للإناث في التطبيق
    private var thumbnail: String? {
        guard hasPhoto, !member.isFemale else { return nil }
        return [member.avatarUrl, member.photoURL]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private var valueText: String {
        if hasPhoto { return L10n.t("موجودة", "Added") }
        return member.avatarUnavailable == true ? L10n.t("لا توجد صورة لهذا العضو", "No photo exists") : L10n.t("بلا صورة", "No photo")
    }

    var body: some View {
        let row = AdminMemberRow(icon: "photo.fill", tint: DS.Color.sadu, title: L10n.t("الصورة", "Photo"),
                                 value: valueText, thumbnail: thumbnail)
        if canEdit {
            AdminMemberTapRow(hint: hasPhoto ? L10n.t("تغيير", "Change") : L10n.t("إضافة", "Add"), action: openPhoto) {
                row.chevron(true)
            }
        } else {
            row
        }
    }
}

struct AdminMemberPhotoActions: View {
    let member: FamilyMember
    /// له حساب دخول (`AdminMemberSheetFacts.account`)
    let hasLogin: Bool
    /// لا جهاز مسجّل له (لا تصله الإشعارات) — false حين لا نعرف
    let noDevices: Bool
    /// «طلب» — مربّع السبب (`AdminMemberBox.photoRequest`)
    let askChange: () -> Void
    /// أمر جارٍ — الورقة تعطّل «السابق/التالي» حتى ينتهي (V27)
    @Binding var working: Bool

    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @ObservedObject private var store = PhotoChangeRequestStore.shared
    @ObservedObject private var config = AppConfigValues.shared
    @State private var busy = false
    @State private var confirmCancel = false
    @State private var failure: String?
    @State private var info: String?
    /// يعيد الحساب حين يعود «ذكّره الحين» (بعد دقيقة من آخر إشعار)
    @State private var now = Date()

    /// حالة الصفّ — الورقة تقرأها أيضاً لتقرّر هل في البطاقة صفّ صورة
    @MainActor static func state(member: FamilyMember, hasLogin: Bool, viewer: PhotoNudgeLogic.Viewer,
                                 now: Date = Date()) -> PhotoNudgeLogic.Row {
        PhotoNudgeLogic.row(viewer: viewer, member: .init(member, hasLogin: hasLogin),
                            open: PhotoChangeRequestStore.shared.open(for: member.id)?.nudgeOpen,
                            maxReminders: PhotoNudgeConfig.maxReminders, now: now)
    }

    var body: some View {
        let state = Self.state(member: member, hasLogin: hasLogin, viewer: .init(authVM: authVM), now: now)
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
            .dsAlert(L10n.t("لم يُرسل الآن", "Not sent now"),
                     isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
                Button(L10n.t("حسناً", "OK")) { info = nil }
            } message: {
                Text(info ?? "")
            }
    }

    @ViewBuilder
    private func content(_ state: PhotoNudgeLogic.Row) -> some View {
        switch state {
        case .hidden:
            EmptyView()
        case .askChange:
            AdminSheetRow(icon: "camera.badge.ellipsis", tint: DS.Color.sadu,
                          title: L10n.t("طلب تغيير الصورة", "Ask to change the photo"),
                          value: L10n.t("يصله إشعار بالسبب، ثم تذكير حتى يغيّرها",
                                        "They're notified with the reason, then reminded until it's changed"),
                          action: (L10n.t("طلب", "Ask"), askChange), actionStyle: .navy)
        case .nudge:
            face(icon: "bell.fill", title: L10n.t("تنبيه لإضافة صورة", "Ask for a photo"),
                 line: noDevices ? L10n.t("لا تصله الإشعارات — يظهر له عند فتح التطبيق",
                                          "Gets no notifications — sees it when opening the app")
                                 : PhotoNudgeConfig.explanation) {
                nudgePill
            }
        case .pending(let p):
            face(icon: p.isAdd ? "bell.badge.fill" : "camera.badge.clock",
                 title: p.isAdd ? L10n.t("تنبيه لإضافة صورة", "Ask for a photo")
                                : L10n.t("طلب تغيير الصورة", "Photo change request"),
                 line: p.line, extra: extraLine(p), tint: DS.Color.warning) {
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
        }
    }

    // MARK: الوجه

    /// مربّع الأيقونة · العنوان ١٥ والسطر ١٣ رمادي (وسطر ثانٍ اختياري) · الحبّات تحت النص (تلتفّ بلا ضغط)
    private func face<Actions: View>(icon: String, title: String, line: String, extra: String? = nil,
                                     tint: Color = DS.Color.sadu,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        let pills = actions()
        return HStack(alignment: .top, spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: icon, tint: tint, filled: true)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title)
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: line)
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
                .accessibilityElement(children: .combine)
                if busy {
                    ProgressView()
                        .scaleEffect(DS.Spinner.chipScale)
                        .frame(minWidth: DS.Icon.tapTarget, minHeight: DS.Hub.pillHeightCard, alignment: .leading)
                        .accessibilityLabel(L10n.t("جارٍ الإرسال", "Sending"))
                } else {
                    AdminPillRow { pills }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(minHeight: DS.Hub.rowMinHeightTwoLines)
    }

    /// «🔔 نبّهه يضيف صورة» — ذهبية بإطار (النموذج «أ3»)
    private var nudgePill: some View {
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

    /// السبب (طلب التغيير) وإخفاء الصورة
    private func extraLine(_ p: PhotoNudgeLogic.Pending) -> String? {
        var parts: [String] = []
        if let reason = p.reason { parts.append(L10n.t("السبب: \(reason)", "Reason: \(reason)")) }
        if !p.isAdd, store.open(for: member.id)?.hidePhoto == true {
            parts.append(L10n.t("الصورة مخفية حتى يغيّرها", "Photo hidden until changed"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: الإجراءات

    private func nudge() {
        send(success: L10n.t("وصله التنبيه", "Notice sent")) { await store.nudgeOutcome(memberId: $0) }
    }

    private func remind() {
        send(success: L10n.t("وصله التذكير", "Reminder sent")) { await store.remindOutcome(memberId: $0) }
    }

    private func send(success: String, _ call: @escaping (UUID) async -> PhotoNudgeOutcome) {
        guard !busy else { return }
        let id = member.id
        busy = true
        working = true
        Task {
            let outcome = await call(id)
            if outcome == .stale {
                // له صورة الآن — نحدّث العضو وطلبه (المشغّل أغلقه)
                await memberVM.fetchSingleMember(id: id)
                await store.refresh(memberId: id)
            }
            busy = false
            working = false
            now = Date()
            switch outcome {
            case .sent:
                DSMomentToast.show(success, moment: .success)
            case .tooSoon:
                info = PhotoNudgeLogic.tooSoonText
            case .stale:
                DSMomentToast.show(PhotoNudgeLogic.staleText, moment: .success)
            case .failed(let message):
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                failure = message
            }
        }
    }

    private func cancel() {
        let id = member.id
        busy = true
        working = true
        Task {
            let error = await store.cancel(memberId: id)
            busy = false
            working = false
            if let error {
                failure = error
            } else {
                UIAccessibility.post(notification: .announcement, argument: L10n.t("أُلغي التنبيه", "Notice cancelled"))
            }
        }
    }
}
