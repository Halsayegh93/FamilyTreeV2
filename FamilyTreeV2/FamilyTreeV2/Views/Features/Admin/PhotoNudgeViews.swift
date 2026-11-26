import SwiftUI

// MARK: - «نبّهه يضيف صورة» + التذكير — الواجهات (الوحدة P1، طلب المالك ٢٠٢٦-١١-٢٦)
//
// ١) `PhotoNudgeSheetRow`: صفّ في بطاقة «البيانات» بورقة العضو تحت «الصورة» — نوع مستقل يُنقل كما هو حين تُعاد ورقة
//    العضو (الوحدة التالية). حالاته من `PhotoNudgeLogic.row`:
//      بلا صورة → «تنبيه لإضافة صورة» + «نبّهه يضيف صورة» (بلا مربّع، لحظة «وصله التنبيه»)؛
//      له صورة → «طلب تغيير الصورة» + «طلب» (مربّع السبب الموجود `PhotoChangeRequestBox`)؛
//      طلب مفتوح → «نُبّه قبل 5 أيام · ذُكّر 1 من 3 · بانتظار صورته» + «ذكّره الحين» (يختفي دقيقة بعد كل إشعار)
//      + «إلغاء التنبيه» (بتأكيد).
// ٢) `AdminPhotoNudgePage`: «مسجّلون بلا صورة» من «يحتاج مراجعتك» — نفس قاعدة السيرفر (`PhotoNudgeLogic.isListed`)،
//    وفي أعلاها «نبّههم كلهم (N)» للمالك والمدير بتأكيد «يوصل إشعار لـ N عضو» ← «نُبّه N عضو». المراقب يرى القائمة
//    و«نبّهه» لكل عضو. الصفّ يفتح ورقة العضو.
// كل كتابة عبر `PhotoChangeRequestStore` (تمرّ بـ`DebugAdminProbe.dryRun` أولاً). حارس المكدس: الصفحة والطبقات خلف `AnyView`.

// MARK: - الربط بالنماذج

extension PhotoNudgeLogic.Viewer {
    /// صلاحية الدور × «يعدّل» «العائلة» في جدول السيرفر
    @MainActor init(authVM: AuthViewModel) {
        let family = authVM.adminCanEdit(.family)
        self.init(id: authVM.currentUser?.id,
                  canEdit: authVM.canEditMembers && family,
                  isOwner: authVM.currentUser?.role == .owner,
                  canBulk: authVM.isAdmin && family)
    }
}

extension PhotoNudgeLogic.Member {
    init(_ m: FamilyMember, hasLogin: Bool) {
        self.init(id: m.id,
                  isDeceased: m.isDeceased == true,
                  hasLogin: hasLogin,
                  hasPhoto: PhotoNudgeLogic.hasPhoto(avatar: m.avatarUrl, photo: m.photoURL),
                  isFemale: m.isFemale,
                  isOwner: m.role == .owner,
                  isActive: m.status == .active && m.role != .pending)
    }
}

/// إعداد المالك للتذكير (`app_config`) — الافتراضي قبل الترحيل
@MainActor
enum PhotoNudgeConfig {
    static var remindDays: Int {
        AppConfigValues.shared.int(PhotoNudgeLogic.remindDaysKey, default: PhotoNudgeLogic.defaultRemindDays)
    }
    static var maxReminders: Int {
        AppConfigValues.shared.int(PhotoNudgeLogic.maxRemindersKey, default: PhotoNudgeLogic.defaultMaxReminders)
    }
    static var explanation: String {
        PhotoNudgeLogic.nudgeExplanation(remindDays: remindDays, maxReminders: maxReminders)
    }
}

// MARK: - ١) صفّ ورقة العضو

struct PhotoNudgeSheetRow: View {
    let member: FamilyMember
    /// له حساب دخول (`AdminMemberSheetFacts.account`)
    let hasLogin: Bool
    /// «طلب» على عضو له صورة — يفتح مربّع السبب (`AdminMemberBox.photoRequest`)
    let onAskChange: () -> Void

    @EnvironmentObject private var authVM: AuthViewModel
    @ObservedObject private var store = PhotoChangeRequestStore.shared
    @ObservedObject private var config = AppConfigValues.shared
    @State private var busy = false
    @State private var confirmCancel = false
    @State private var failure: String?
    /// يعيد الحساب حين يعود «ذكّره الحين» (بعد دقيقة من آخر إشعار)
    @State private var now = Date()

    /// يُرسم الصفّ أصلاً؟ — `AdminRowsCard` يرسم فاصلاً لكل ابن
    @MainActor static func isVisible(member: FamilyMember, hasLogin: Bool, authVM: AuthViewModel) -> Bool {
        state(member: member, hasLogin: hasLogin, viewer: .init(authVM: authVM), now: Date()) != .hidden
    }

    @MainActor private static func state(member: FamilyMember, hasLogin: Bool, viewer: PhotoNudgeLogic.Viewer,
                                         now: Date) -> PhotoNudgeLogic.Row {
        PhotoNudgeLogic.row(viewer: viewer, member: .init(member, hasLogin: hasLogin),
                            open: PhotoChangeRequestStore.shared.open(for: member.id)?.nudgeOpen,
                            maxReminders: PhotoNudgeConfig.maxReminders, now: now)
    }

    private var row: PhotoNudgeLogic.Row {
        Self.state(member: member, hasLogin: hasLogin, viewer: .init(authVM: authVM), now: now)
    }

    var body: some View {
        let state = row
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
            EmptyView()
        case .nudge:
            PhotoNudgeRowFace(icon: "bell.fill", tint: DS.Color.sadu,
                              title: L10n.t("تنبيه لإضافة صورة", "Ask for a photo"),
                              line: PhotoNudgeConfig.explanation, busy: busy) {
                AdminPillButton(title: L10n.t("نبّهه يضيف صورة", "Ask for a photo"), icon: "bell", style: .soft,
                                height: DS.Hub.pillHeightCard, action: nudge)
                    .fixedSize()
            }
        case .askChange:
            PhotoNudgeRowFace(icon: "camera.badge.ellipsis", tint: DS.Color.sadu,
                              title: L10n.t("طلب تغيير الصورة", "Ask to change the photo"),
                              line: L10n.t("يصله إشعار بالسبب، ثم تذكير حتى يغيّرها", "They're notified with the reason, then reminded until it's changed"),
                              busy: false) {
                AdminPillButton(title: L10n.t("طلب", "Ask"), style: .soft, height: DS.Hub.pillHeightCard, action: onAskChange)
                    .fixedSize()
                    .accessibilityLabel(L10n.t("طلب تغيير الصورة", "Ask to change the photo"))
            }
        case .pending(let p):
            PhotoNudgeRowFace(icon: p.isAdd ? "bell.badge.fill" : "camera.badge.clock", tint: DS.Color.warning,
                              title: p.isAdd ? L10n.t("تنبيه لإضافة صورة", "Ask for a photo")
                                             : L10n.t("طلب تغيير الصورة", "Photo change request"),
                              line: p.line, extra: extraLine(p), busy: busy) {
                if p.canRemind {
                    AdminPillButton(title: L10n.t("ذكّره الحين", "Remind now"), icon: "bell", style: .soft,
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

/// وجه الصفّ: مربّع الأيقونة · العنوان ١٥ والسطر ١٣ رمادي (وسطر ثانٍ اختياري) · الحبّات تحت النص (تلتفّ بلا ضغط)
private struct PhotoNudgeRowFace<Actions: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let line: String
    var extra: String? = nil
    let busy: Bool
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: icon, tint: tint, filled: true)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title)
                        .dsFont(.body)
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
                    AdminPillRow { actions() }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(minHeight: DS.Hub.rowMinHeightTwoLines)
    }
}

// MARK: - ٢) «مسجّلون بلا صورة»

@MainActor
enum AdminPhotoNudgeList {
    /// أعضاء القائمة من فهرس «العائلة» (نفس قاعدة السيرفر) — nil قبل وصول الحسابات (لا صفر مضلِّل)
    static func rows(in index: AdminMembersIndex, viewer: PhotoNudgeLogic.Viewer) -> [Int]? {
        guard index.built, index.accountsReady else { return nil }
        return index.entries.indices.filter { i in
            let e = index.entries[i]
            return PhotoNudgeLogic.isListed(.init(e.member, hasLogin: e.hasLogin),
                                            viewerId: viewer.id, viewerIsOwner: viewer.isOwner)
        }
    }

    static var title: String { L10n.t("مسجّلون بلا صورة", "Registered, no photo") }
    static var subtitle: String { L10n.t("لهم حساب وليس في ملفهم صورة", "They have an account but no profile photo") }
    static let icon = "person.crop.circle.badge.exclamationmark"
}

struct AdminPhotoNudgePage: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    @ObservedObject private var sons = DaughterSonsIndex.shared
    @ObservedObject private var store = PhotoChangeRequestStore.shared
    @ObservedObject private var config = AppConfigValues.shared

    @State private var index = AdminMembersIndex.empty
    @State private var limit = AdminMembersPage.pageSize
    @State private var sheet: AdminMemberSheetContext?
    @State private var confirmAll = false
    @State private var sendingAll = false
    @State private var busy: Set<UUID> = []
    @State private var failure: String?
    @State private var now = Date()

    init() {}

    // حارس المكدس: الصفحة نوع واحد والمحتوى خلف `AnyView`
    var body: some View {
        AdminPage(header: header, content: AnyView(content), updatedAt: store.allOpenHealth.lastGood)
            .adminArea(.family)
            .dsTallBox(item: $sheet) { context in
                AdminMemberSheet(ids: context.ids, start: context.start)
            }
            .refreshable { await reload(force: true) }
            .task { await reload(force: false) }
            .onChange(of: memberVM.membersVersion) { _ in rebuild() }
            .onChange(of: accounts.accounts) { _ in rebuild() }
            .onChange(of: accounts.loaded) { _ in rebuild() }
            .onChange(of: sons.ids) { _ in rebuild() }
            .dsAlert(L10n.t("نبّههم كلهم؟", "Notify them all?"), isPresented: $confirmAll) {
                Button(L10n.t("نبّههم", "Notify")) { sendAll() }
                Button(L10n.t("رجوع", "Back"), role: .cancel) {}
            } message: {
                Text(PhotoNudgeLogic.bulkConfirmMessage(bulkCount))
            }
            .dsAlert(L10n.t("تعذّر التنفيذ", "Couldn't complete"),
                     isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button(L10n.t("حسناً", "OK")) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
            .debugStackProbe("AdminPhotoNudgePage")
    }

    private var viewer: PhotoNudgeLogic.Viewer { .init(authVM: authVM) }

    private var header: AdminPageHeader {
        AdminPageHeader(title: AdminPhotoNudgeList.title, subtitle: AdminPhotoNudgeList.subtitle,
                        readOnly: !authVM.adminCanEdit(.family))
    }

    private func reload(force: Bool) async {
        now = Date()
        if memberVM.allMembers.isEmpty || force { await memberVM.fetchAllMembers(force: force) }
        rebuild()
        async let opens: Void = store.refreshAllOpen()
        async let accountsDone: Void = accounts.refresh(force: force)
        _ = await (opens, accountsDone)
        await AppConfigValues.shared.refresh()
        now = Date()
        rebuild()
    }

    private func rebuild() {
        let names = appSettingsVM
        index = AdminMembersIndex.build(members: memberVM.allMembers, accounts: accounts.accounts,
                                        accountsReady: accounts.loaded, daughterSons: sons.ids,
                                        branchName: { names.branchName(for: $0) })
    }

    /// القائمة بترتيبها: من لم يُنبَّه أولاً (بترتيب الفهرس)، ثم الأقدم إشعاراً
    private var rows: [Int]? {
        guard let list = AdminPhotoNudgeList.rows(in: index, viewer: viewer) else { return nil }
        let last = { (i: Int) in store.open(for: index.entries[i].id)?.nudgeOpen.lastNotice }
        return list.enumerated().sorted { a, b in
            switch (last(a.element), last(b.element)) {
            case (nil, nil): return a.offset < b.offset
            case (nil, _): return true
            case (_, nil): return false
            case (let x?, let y?): return x < y
            }
        }.map(\.element)
    }

    private var openMap: [UUID: PhotoNudgeLogic.Open] {
        store.openByMember.mapValues(\.nudgeOpen)
    }

    private var bulkCount: Int {
        guard let rows else { return 0 }
        return PhotoNudgeLogic.bulkCount(listed: rows.map { index.entries[$0].id }, open: openMap, now: now)
    }

    // MARK: المحتوى

    @ViewBuilder
    private var content: some View {
        if memberVM.membersLoadFailed && memberVM.allMembers.isEmpty {
            AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                                      message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                      retry: { Task { await reload(force: true) } }))
        } else if accounts.health == .failed(lastGood: nil) {
            AdminPageStateCard(.error(L10n.t("تعذّر تحميل الحسابات", "Couldn't load accounts"),
                                      message: L10n.t("القائمة تحتاج معرفة من له حساب", "The list needs to know who has an account"),
                                      retry: { Task { await reload(force: true) } }))
        } else if let rows {
            if rows.isEmpty {
                AdminPageStateCard(.empty(L10n.t("كل المسجّلين عندهم صورة", "Every registered member has a photo"),
                                          message: L10n.t("لا أحد ينتظر تنبيهاً الآن", "Nobody needs a notice right now"),
                                          tint: DS.Color.success))
            } else {
                AnyView(loaded(rows))
            }
        } else {
            AdminPageStateCard(.loading(L10n.t("جارٍ تحميل القائمة", "Loading the list"), rows: 4))
        }
    }

    private func loaded(_ rows: [Int]) -> some View {
        VStack(alignment: .leading, spacing: DS.Hub.sectionGap) {
            if viewer.canBulk { bulkCard }
            if store.allOpenHealth == .failed(lastGood: nil) {
                openFailedNote
            }
            VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
                AdminSectionLabel(title: AdminPhotoNudgeList.title, trailing: DSNumber.grouped(rows.count))
                list(rows)
                if rows.count > limit {
                    AdminPillButton(title: L10n.t("عرض المزيد (\(rows.count - limit))", "Show more (\(rows.count - limit))"),
                                    icon: "chevron.down", style: .soft, height: DS.Hub.pillHeightCard) {
                        limit += AdminMembersPage.pageSize
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            hint
        }
    }

    /// «نبّههم كلهم (N)» — المالك والمدير. N = من لم يُنبَّه خلال ٧ أيام (نفس السيرفر)
    private var bulkCard: some View {
        let n = bulkCount
        let ready = store.allOpenHealth.hasData
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(verbatim: PhotoNudgeConfig.explanation)
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if sendingAll {
                HStack(spacing: DS.Spacing.sm) {
                    ProgressView().scaleEffect(DS.Spinner.chipScale)
                    Text(L10n.t("جارٍ الإرسال…", "Sending…"))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
            } else {
                AdminPillButton(title: PhotoNudgeLogic.bulkButtonTitle(n), icon: "bell.fill", style: .navy,
                                height: DS.Icon.tapTarget, fullWidth: true) { confirmAll = true }
                    .disabled(n == 0 || !ready)
                    .opacity(n == 0 || !ready ? DS.Opacity.disabled : 1)
                if ready && n == 0 {
                    Text(L10n.t("كلهم نُبّهوا خلال ٧ أيام — التذكير التلقائي يكمل عنك.",
                                "All were notified in the last 7 days — automatic reminders carry on."))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    /// حال التنبيهات لم تصل — القائمة تُعرض بلا سطر الحال، و«أعد المحاولة»
    private var openFailedNote: some View {
        Button { Task { await store.refreshAllOpen() } } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "exclamationmark.circle.fill")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .accessibilityHidden(true)
                Text(L10n.t("تعذّر تحميل حال التنبيهات — أعد المحاولة", "Couldn't load notice status — try again"))
                    .dsFont(.subtitle)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundColor(DS.Color.error)
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
    }

    private func list(_ rows: [Int]) -> some View {
        let visible = Array(rows.prefix(limit))
        let ids = rows.map { index.entries[$0].id }
        return LazyVStack(spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.element) { n, i in
                if n > 0 { AdminRowDivider(inset: DS.Icon.avatar + DS.Spacing.md) }
                AnyView(row(i, ids: ids, position: n))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    /// الصفّ: الصورة والاسم وسطر الحال («لم يُنبَّه بعد» / «نُبّه قبل 5 أيام · ذُكّر 1 من 3») + «نبّهه»/«ذكّره»
    private func row(_ i: Int, ids: [UUID], position: Int) -> some View {
        let entry = index.entries[i]
        let open = store.open(for: entry.id)?.nudgeOpen
        let known = store.allOpenHealth.hasData
        let line = known ? PhotoNudgeLogic.shortLine(open, maxReminders: PhotoNudgeConfig.maxReminders, now: now)
                         : AdminStoreHealthText.placeholder
        let state = PhotoNudgeLogic.row(viewer: viewer, member: .init(entry.member, hasLogin: entry.hasLogin),
                                        open: open, maxReminders: PhotoNudgeConfig.maxReminders, now: now)
        return HStack(spacing: DS.Spacing.sm) {
            Button { sheet = AdminMemberSheetContext(ids: ids, start: position) } label: {
                AdminMemberListRow(entry: entry, subline: line, warns: false, showsStatus: false)
            }
            .buttonStyle(AdminRowPressStyle())
            if known { trailing(entry, state: state) }
        }
    }

    @ViewBuilder
    private func trailing(_ entry: AdminMembersIndex.Entry, state: PhotoNudgeLogic.Row) -> some View {
        if busy.contains(entry.id) {
            ProgressView()
                .scaleEffect(DS.Spinner.chipScale)
                .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                .accessibilityLabel(L10n.t("جارٍ الإرسال", "Sending"))
        } else {
            switch state {
            case .nudge:
                AdminPillButton(title: L10n.t("نبّهه", "Notify"), icon: "bell", style: .soft, height: DS.Hub.pillHeightCard) {
                    send(entry.id, success: L10n.t("وصله التنبيه", "Notice sent")) { await store.nudge(memberId: entry.id) }
                }
                .fixedSize()
                .accessibilityLabel(Text(verbatim: "\(L10n.t("نبّهه يضيف صورة", "Ask for a photo")): \(entry.member.fourPartName)"))
            case .pending(let p) where p.canRemind:
                AdminPillButton(title: L10n.t("ذكّره", "Remind"), icon: "bell", style: .soft, height: DS.Hub.pillHeightCard) {
                    send(entry.id, success: L10n.t("وصله التذكير", "Reminder sent")) { await store.remind(memberId: entry.id) }
                }
                .fixedSize()
                .accessibilityLabel(Text(verbatim: "\(L10n.t("ذكّره الحين", "Remind now")): \(entry.member.fourPartName)"))
            default:
                EmptyView()
            }
        }
    }

    /// سطر الإرشاد آخر الصفحة — ١٣ رمادي بلا بطاقة
    private var hint: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xsm) {
            Image(systemName: "info.circle")
                .dsGlyph(DS.Glyph.sm, weight: .medium)
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)
            Text(L10n.t("الإشعار يفتح عنده «أضف صورتك الشخصية»، ويظهر له مرة لكل إشعار — لا كل ما فتح التطبيق. الضغط على الاسم يفتح ورقته.",
                        "The notice opens «Add your photo» for them, once per notice — not every time they open the app. Tap a name to open their sheet."))
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Spacing.xxs)
        .padding(.top, DS.Spacing.xs)
    }

    // MARK: الإجراءات

    private func send(_ id: UUID, success: String, _ call: @escaping () async -> String?) {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        Task {
            let error = await call()
            busy.remove(id)
            now = Date()
            if let error {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                failure = error
            } else {
                DSMomentToast.show(success, moment: .success)
            }
        }
    }

    private func sendAll() {
        let expected = bulkCount
        guard expected > 0, !sendingAll else { return }
        sendingAll = true
        Task {
            let result = await store.requestAll(expected: expected)
            sendingAll = false
            now = Date()
            switch result {
            case .success(let sent):
                DSMomentToast.show(PhotoNudgeLogic.bulkResult(sent), moment: .success)
            case .failure(let error):
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                failure = error.message
            }
        }
    }
}

/// صفّ «مسجّلون بلا صورة · N» في «يحتاج مراجعتك» (بطاقة «الحسابات») — يفتح القائمة؛ الصفر رمادي بلا سهم
struct AdminPhotoNudgeHubRow: View {
    /// nil = لم تصل الحسابات («—»)
    let count: Int?

    var body: some View {
        let look = AdminReviewHubLogic.look(count)
        let title = AdminPhotoNudgeList.title
        let face = AdminListRow(icon: AdminPhotoNudgeList.icon, tint: DS.Color.sea, title: title,
                                subtitle: look.isEmpty ? L10n.t("لا شيء", "Nothing") : AdminPhotoNudgeList.subtitle,
                                showsChevron: look.opens) {
            AdminRowValue(text: look.text, tint: look.dim ? DS.Color.textTertiary : DS.Color.textPrimary)
        }
        let spoken: String = {
            if look.isEmpty { return L10n.t("\(title): لا شيء", "\(title): nothing") }
            if look.text == AdminStoreHealthText.placeholder {
                return L10n.t("\(title): \(AdminStoreHealthText.loading)", "\(title): \(AdminStoreHealthText.loading)")
            }
            return L10n.t("\(title): \(look.text)", "\(title): \(look.text)")
        }()
        AdminTapWrap(tap: look.opens ? .page { AnyView(AdminPhotoNudgePage()) } : .none, feel: .row,
                     label: AnyView(face), accessibilityLabel: spoken)
            .accessibilityHint(look.opens ? L10n.t("يفتح القائمة", "Opens the list") : "")
    }
}
