import SwiftUI
import Supabase

// MARK: - ورقة العضو الواحدة «بيانات العضو» (طلب المالك ٢٠٢٦-١٠-٢٠ — PROPOSAL §١)
//
// صفحة واحدة تتمرّر بلا تبويبات («مابي تويب علوي»): الرأس (الصورة، الاسم، النسب والفرع، الحالة الرسمية، اتصال/واتساب)
// ← «بيانات ناقصة» و«مشكلات الشجرة» بأزرار إصلاح صريحة (عند وجودها) ← «البيانات» ← «النسب» ← «الحساب» ← السابق/التالي
// داخل القائمة التي فُتحت منها (= «استكمال البيانات»، عضو في كل مرة) و«حذف العضو نهائياً».
// كل أمر هو نفسه السابق بصلاحيته ونداء سيرفره — جُمع هنا فقط، والتعديل بالمربّعات الموجودة:
//   تاريخ الميلاد `EditBirthDateSheet` · الجنس `EditGenderSheet` · الصورة `EditMemberPhotoSheet` · الوفاة
//   `EditDeathDateSheet` (بلا تاريخ) / `DeceasedDateBox` (سنة فقط/هجري) · الأب `LinkFatherSheet` · الاسم `EditNameSheet` ·
//   الرقم `PendingMemberPhoneSheet(activateOnSave:)` · كل البيانات والسيرة والأبناء `AdminMemberDetailSheet(showsAccount: false)`
//   · «تسجيل في التطبيق» `activateAccount` · الإيقاف `setMemberStatus` (`canFreezeMembers`) · منع الرقم `banPhone`
//   (`canManageBannedPhones`) · الأجهزة `fetchDevicesForMember` (عرض `canViewSystemSettings`) وتسجيل خروجها
//   `removeDeviceByAdmin` (`canManageDevices`) · الإخفاء `is_hidden_from_tree` · مسح الرقم المكرر `clearPhoneNumber` ·
//   الحذف `deleteMember` (`canDeleteMembers`، لا المالك ولا النفس).

struct AdminMemberSheet: View {
    let ids: [UUID]
    @State private var position: Int
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    @Environment(\.dismiss) private var dismiss

    /// من السيرفر عند فتح كل عضو — العضو المحمّل قد يكون قديماً
    @State private var liveStatus: FamilyMember.MemberStatus?
    @State private var ban: BannedPhone?
    @State private var devices: [NotificationViewModel.LinkedDevice]?
    @State private var tree: AdminMemberFacts.TreeContext?

    @State private var box: AdminMemberBox?
    @State private var tall: AdminMemberTallBox?
    @State private var confirm: AdminMemberConfirm?
    @State private var busy: String?
    @State private var failure: String?

    init(ids: [UUID], start: Int) {
        self.ids = ids
        _position = State(initialValue: min(max(0, start), max(0, ids.count - 1)))
    }

    private var member: FamilyMember? {
        guard ids.indices.contains(position) else { return nil }
        return memberVM.member(byId: ids[position])
    }

    var body: some View {
        page
            .modifier(AdminMemberSheetBoxes(box: $box, tall: $tall))
            .modifier(AdminMemberSheetAlerts(confirm: $confirm, failure: $failure, run: run))
            .onAppear { tree = AdminMemberFacts.TreeContext(memberVM.allMembers) }
            .onChange(of: memberVM.membersVersion) { _ in tree = AdminMemberFacts.TreeContext(memberVM.allMembers) }
            .task(id: ids.indices.contains(position) ? ids[position] : nil) { await refresh() }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private var page: AnyView {
        guard let m = member else {
            return AnyView(VStack(spacing: DS.Spacing.lg) {
                closeRow
                DSEmptyView(L10n.t("العضو غير موجود", "Member not found"),
                            message: L10n.t("ربما حُذف أو تغيّر — ارجع للقائمة", "It may have been deleted — go back to the list"),
                            style: .card)
                Spacer(minLength: 0)
            }
            .padding(DS.Spacing.lg)
            .background(DS.Hub.background.ignoresSafeArea()))
        }
        let facts = AdminMemberSheetFacts(member: m, all: memberVM.allMembers, byId: memberVM.member(byId:), tree: tree,
                                          account: accounts.info(m.id), accountsReady: accounts.loaded,
                                          liveStatus: liveStatus)
        return AnyView(ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Hub.stackSpacing) {
                AnyView(AdminMemberSheetHero(member: m, facts: facts, onClose: { dismiss() }))
                if authVM.canEditMembers && (!facts.gaps.isEmpty || !facts.problems.isEmpty) {
                    AnyView(fixesCard(m, facts))
                }
                AnyView(AdminMemberDataSection(member: m, facts: facts, canEdit: authVM.canEditMembers,
                                               open: { box = $0 }, openTall: { tall = $0 }))
                AnyView(AdminMemberLineageSection(member: m, facts: facts, canEdit: authVM.canEditMembers,
                                                  canManageChildren: authVM.canEditMembers && authVM.currentUser?.role != .monitor,
                                                  open: { tall = $0 }, ask: { confirm = $0 },
                                                  openWomen: openWomenTree))
                if m.isDeceased != true {
                    AnyView(accountSection(m, facts))
                }
                AnyView(footer(m))
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xxxl)
            .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Hub.background.ignoresSafeArea()))
    }

    private var closeRow: some View {
        HStack {
            Spacer(minLength: 0)
            DSCloseButton { dismiss() }
        }
    }

    // MARK: الإجراءات

    private func openWomenTree() {
        dismiss()
        TreeTabContainer.openWomenOnAppear = true
        NotificationCenter.default.post(name: .openWomenTree, object: nil)
    }

    private func refresh() async {
        liveStatus = nil
        ban = nil
        devices = nil
        if !accounts.loaded { await accounts.refresh() }
        guard let m = member, m.isDeceased != true else { return }
        if let status = await memberVM.fetchMemberStatus(memberId: m.id) { liveStatus = status }
        await refreshBan(m)
        if authVM.canViewSystemSettings {
            devices = await notificationVM.fetchDevicesForMember(m.id)
        }
    }

    private func refreshBan(_ m: FamilyMember) async {
        guard authVM.canManageBannedPhones, !AdminMemberFacts.isBlank(m.phoneNumber) else { return }
        ban = await authVM.activeBan(for: (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func run(_ action: AdminMemberConfirm) {
        guard let m = member else { return }
        confirm = nil
        busy = action.id
        Task {
            var ok = true
            switch action {
            case .register:
                adminRequestVM.errorMessage = nil
                await adminRequestVM.activateAccount(memberId: m.id)
                if let reason = adminRequestVM.errorMessage {
                    adminRequestVM.errorMessage = nil
                    failure = reason
                }
                if let status = await memberVM.fetchMemberStatus(memberId: m.id) { liveStatus = status }
            case .suspend, .unsuspend:
                let target: FamilyMember.MemberStatus = action == .suspend ? .frozen : .active
                ok = await memberVM.setMemberStatus(memberId: m.id, status: target)
                if ok { liveStatus = target }
            case .block:
                ok = await authVM.banPhone((m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                           reason: L10n.t("من «بيانات العضو»: \(m.displayFullName)", "From Member details: \(m.displayFullName)"))
                await refreshBan(m)
                if let status = await memberVM.fetchMemberStatus(memberId: m.id) { liveStatus = status }
            case .unblock:
                if let ban { ok = await authVM.unbanPhone(ban.id) }
                await refreshBan(m)
            case .hide, .show:
                ok = await AdminMemberSheet.setHidden(m.id, hidden: action == .hide, memberVM: memberVM)
            case .clearPhone:
                ok = await memberVM.clearPhoneNumber(for: m.id)
            case .signOut(let device):
                ok = await notificationVM.removeDeviceByAdmin(device)
                devices = await notificationVM.fetchDevicesForMember(m.id)
                if !ok { failure = notificationVM.lastDeviceError }
            case .delete:
                if await memberVM.deleteMember(memberId: m.id) {
                    NotificationCenter.default.post(name: .memberDeleted, object: m.id)
                    busy = nil
                    dismiss()
                    return
                }
                ok = false
                failure = memberVM.errorMessage
            }
            busy = nil
            if !ok && failure == nil {
                failure = L10n.t("تأكد من الاتصال ثم حاول مرة أخرى.", "Check your connection and try again.")
            }
        }
    }

    /// الإخفاء من الشجرة وإظهاره — نفس نداء «صحة الشجرة» السابق ثم إعادة التحميل
    static func setHidden(_ id: UUID, hidden: Bool, memberVM: MemberViewModel) async -> Bool {
        do {
            try await SupabaseConfig.client
                .from("profiles")
                .update(["is_hidden_from_tree": hidden])
                .eq("id", value: id.uuidString)
                .execute()
            await memberVM.fetchAllMembers(force: true)
            return true
        } catch {
            Log.error("Toggle hidden failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: «بيانات ناقصة» و«مشكلات الشجرة» — أزرار المحطة نفسها

    private func fixesCard(_ m: FamilyMember, _ facts: AdminMemberSheetFacts) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if !facts.gaps.isEmpty {
                fixGroup(title: L10n.t("بيانات ناقصة", "Missing data"), count: facts.gaps.count,
                         buttons: facts.gaps.map { gap in (gap.id, gap.fixTitle, gap.icon, { fixGap(gap, m) }) })
            }
            if !facts.problems.isEmpty {
                fixGroup(title: L10n.t("مشكلات الشجرة", "Tree problems"), count: facts.problems.count,
                         buttons: facts.problems.map { p in (p.id, p.fixTitle, p.icon, { fixProblem(p, m) }) })
            }
        }
        .padding(DS.Hub.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous)
            .fill(DS.Color.warning.opacity(DS.Opacity.tintFill)))
    }

    private func fixGroup(title: String, count: Int, buttons: [(String, String, String, () -> Void)]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xsm) {
                Text(title)
                    .dsFont(.headline)
                    .foregroundColor(DS.Color.warning.dsReadableGlyph)
                AdminCountBadge(count: count, tint: DS.Color.warning)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            OccasionFlowLayout(spacing: DS.Spacing.sm) {
                ForEach(buttons, id: \.0) { item in
                    AdminPillButton(title: item.1, icon: item.2, style: .navy, height: DS.Hub.pillHeightCard, action: item.3)
                }
            }
        }
    }

    private func fixGap(_ gap: AdminMemberGap, _ m: FamilyMember) {
        switch gap {
        case .noBirth: box = .birth(m)
        case .noGender: box = .gender(m)
        case .noPhoto: box = .photo(m)
        case .deathIncomplete: box = AdminMemberFacts.isBlank(m.deathDate) ? .death(m) : .deathDate(m)
        }
    }

    private func fixProblem(_ p: AdminMemberProblem, _ m: FamilyMember) {
        switch p {
        case .orphan, .brokenParent: tall = .father(m)
        case .noName: box = .name(m)
        case .hidden: confirm = .show
        case .dupPhone: confirm = .clearPhone
        }
    }

    // MARK: «الحساب»

    private func accountSection(_ m: FamilyMember, _ facts: AdminMemberSheetFacts) -> some View {
        let isOther = m.role != .owner && m.id != authVM.currentUser?.id
        let phone = (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let frozen = facts.status == .frozen
        let canRegister = authVM.canEditMembers && isOther && !frozen && !phone.isEmpty && m.role != .pending
            && (liveStatus ?? m.status) != .active && facts.status != .registered
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: L10n.t("الحساب", "Account"))
            AdminRowsCard {
                AdminSheetRow(icon: facts.status?.icon ?? "person.fill", tint: facts.status?.tint ?? DS.Color.slate,
                              title: L10n.t("الحالة", "Status"), value: facts.statusLine)
                AdminSheetRow(icon: "phone.fill", tint: DS.Color.sea, title: L10n.t("رقم الهاتف", "Phone number"),
                              value: phone.isEmpty ? L10n.t("بلا رقم هاتف", "No phone") : KuwaitPhone.display(phone),
                              valueIsNumber: !phone.isEmpty,
                              action: authVM.canEditMembers
                                ? (phone.isEmpty ? L10n.t("إضافة", "Add") : L10n.t("تعديل", "Edit"), { box = .phone(m) }) : nil)
                if canRegister {
                    AdminSheetRow(icon: "checkmark.seal.fill", tint: DS.Color.success,
                                  title: L10n.t("تسجيل في التطبيق", "Register in the app"),
                                  value: L10n.t("يتيح له الدخول برقمه فيصير «عضواً مسجّلاً»",
                                                "Lets them sign in with their number"),
                                  action: (L10n.t("تسجيل", "Register"), { confirm = .register }),
                                  busy: busy == AdminMemberConfirm.register.id)
                }
                AdminSheetRow(icon: "clock.fill", tint: DS.Color.slate, title: L10n.t("آخر دخول", "Last sign-in"),
                              value: facts.lastSeenText)
                // الأجهزة لمن له حساب دخول (المقيّد في الشجرة لا جهاز له)
                if authVM.canViewSystemSettings && facts.status != .treeOnly {
                    devicesRows(m)
                }
                if authVM.canFreezeMembers && isOther {
                    AdminSheetRow(icon: frozen ? "lock.open.fill" : "hand.raised.fill",
                                  tint: frozen ? DS.Color.success : DS.Color.warning,
                                  title: frozen ? L10n.t("رفع الإيقاف", "Lift the suspension") : L10n.t("إيقاف الحساب", "Suspend account"),
                                  value: frozen ? L10n.t("يعود للدخول إلى التطبيق", "They can sign in again")
                                                : L10n.t("يمنعه من الدخول مؤقتاً، وبياناته محفوظة", "Blocks sign-in for now; data is kept"),
                                  action: (frozen ? L10n.t("رفع", "Lift") : L10n.t("إيقاف", "Suspend"),
                                           { confirm = frozen ? .unsuspend : .suspend }),
                                  busy: busy == AdminMemberConfirm.suspend.id || busy == AdminMemberConfirm.unsuspend.id)
                }
                if authVM.canManageBannedPhones && isOther && !phone.isEmpty {
                    AdminSheetRow(icon: ban == nil ? "nosign" : "checkmark.circle.fill",
                                  tint: ban == nil ? DS.Color.error : DS.Color.success,
                                  title: ban == nil ? L10n.t("منع الرقم من التسجيل", "Block the number from signing up")
                                                    : L10n.t("رفع منع الرقم", "Unblock the number"),
                                  value: ban == nil ? L10n.t("المالك فقط — ويوقف حساب صاحبه", "Owner only — also suspends the account")
                                                    : L10n.t("الحساب يبقى موقوفاً حتى ترفع إيقافه", "The account stays suspended until lifted"),
                                  action: (ban == nil ? L10n.t("منع", "Block") : L10n.t("رفع", "Unblock"),
                                           { confirm = ban == nil ? .block : .unblock }),
                                  busy: busy == AdminMemberConfirm.block.id || busy == AdminMemberConfirm.unblock.id)
                }
            }
        }
    }

    @ViewBuilder
    private func devicesRows(_ m: FamilyMember) -> some View {
        if let devices {
            if devices.isEmpty {
                AdminSheetRow(icon: "iphone.slash", tint: DS.Color.slate, title: L10n.t("الأجهزة المرتبطة", "Linked devices"),
                              value: L10n.t("لا أجهزة مرتبطة — لا تصله الإشعارات", "No linked devices — no notifications"))
            } else {
                ForEach(devices) { device in
                    AdminSheetRow(icon: device.platform.lowercased() == "android" ? "candybarphone" : "iphone.gen3",
                                  tint: DS.Color.info, title: device.displayName,
                                  value: L10n.t("آخر استخدام: ", "Last used: ") + AdminMemberSheetFacts.dateText(iso: device.updatedAt),
                                  action: authVM.canManageDevices
                                    ? (L10n.t("تسجيل خروج", "Sign out"), { confirm = .signOut(device) }) : nil,
                                  busy: busy == AdminMemberConfirm.signOut(device).id)
                }
            }
        } else {
            AdminSheetRow(icon: "iphone.gen3", tint: DS.Color.info, title: L10n.t("الأجهزة المرتبطة", "Linked devices"),
                          value: L10n.t("جارٍ التحميل…", "Loading…"))
        }
    }

    // MARK: الأسفل: السابق · حذف العضو نهائياً · التالي

    private func footer(_ m: FamilyMember) -> some View {
        let canDelete = authVM.canDeleteMembers && m.role != .owner && m.id != authVM.currentUser?.id
        return VStack(spacing: DS.Spacing.sm) {
            if ids.count > 1 {
                Text(verbatim: L10n.t("\(position + 1) من \(ids.count)", "\(position + 1) of \(ids.count)"))
                    .dsFont(.caption)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: DS.Spacing.sm) {
                if ids.count > 1 {
                    stepButton(next: false)
                }
                Spacer(minLength: 0)
                if canDelete {
                    DSDangerTextButton(L10n.t("حذف العضو نهائياً", "Delete member permanently")) { confirm = .delete }
                }
                Spacer(minLength: 0)
                if ids.count > 1 {
                    stepButton(next: true)
                }
            }
        }
        .padding(.top, DS.Spacing.sm)
    }

    private func stepButton(next: Bool) -> some View {
        let enabled = next ? position < ids.count - 1 : position > 0
        return Button {
            withAnimation(DS.Anim.snappy) { position += next ? 1 : -1 }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                if !next { Image(systemName: "chevron.backward").dsGlyph(DS.Glyph.sm, weight: .bold) }
                Text(next ? L10n.t("التالي", "Next") : L10n.t("السابق", "Previous"))
                    .dsFont(.hubButton)
                    .lineLimit(1)
                if next { Image(systemName: "chevron.forward").dsGlyph(DS.Glyph.sm, weight: .bold) }
            }
            .foregroundColor(next ? DS.Color.textOnPrimary : DS.Color.textPrimary)
            .padding(.horizontal, DS.Hub.pillPadding)
            .frame(minHeight: DS.Hub.pillHeightCard)
            .background(Capsule().fill(next ? DS.Color.primaryFill : DS.Color.cardBackgroundSoft))
            .dsTapArea(width: DS.Icon.tapTarget, height: DS.Hub.pillHeightCard)
        }
        .buttonStyle(DSPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : DS.Opacity.disabled)
    }
}

// MARK: - الحقائق المحسوبة للعضو المعروض

@MainActor
struct AdminMemberSheetFacts {
    let status: AdminMemberStatus?
    let account: AdminAccountInfo?
    let gaps: [AdminMemberGap]
    let problems: [AdminMemberProblem]
    let isFamilyRoot: Bool
    let father: FamilyMember?
    let children: [FamilyMember]
    /// رأس فرعه (ابن مباشر لرأس الشجرة) — للرأس: «فرع علي»
    let branchHead: FamilyMember?

    init(member m: FamilyMember, all: [FamilyMember], byId: (UUID) -> FamilyMember?, tree: AdminMemberFacts.TreeContext?,
         account: AdminAccountInfo?, accountsReady: Bool, liveStatus: FamilyMember.MemberStatus?) {
        var shown = m
        if let liveStatus { shown.status = liveStatus }
        status = AdminMemberFacts.status(shown, hasLogin: accountsReady ? account != nil : nil)
        self.account = account
        gaps = AdminMemberFacts.gaps(m, registered: account != nil)
        problems = tree.map { AdminMemberFacts.problems(m, in: $0) } ?? []
        children = all.filter { $0.fatherId == m.id }.sorted { $0.sortOrder < $1.sortOrder }
        isFamilyRoot = m.fatherId == nil && !children.isEmpty
        father = m.fatherId.flatMap(byId)
        // بالصعود في سلسلة الآباء حتى ابن رأس الشجرة (نفس تجميع «حسب الفرع» في صفحة الأعضاء)
        var head: FamilyMember? = nil
        if let root = BranchPickerSheet.familyRoot(in: all), m.id != root.id {
            var cur = m
            for _ in 0..<200 {
                guard let fid = cur.fatherId, let f = byId(fid) else { break }
                if f.id == root.id { head = cur; break }
                cur = f
            }
        }
        branchHead = head
    }

    /// «فرع علي» (أو الاسم المخصّص من «أسماء الفروع»)
    func branchTitle(_ names: AppSettingsViewModel) -> String? {
        guard let head = branchHead else { return nil }
        return names.branchName(for: head.id) ?? L10n.t("فرع \(head.firstName)", "\(head.firstName) branch")
    }

    /// شارة الاستخدام للعضو المسجّل (يستخدم التطبيق · غير نشط · لا تصله الإشعارات)
    var usageSub: AdminMemberSub? {
        guard status == .registered, let usage = account?.usage else { return nil }
        switch usage {
        case .active: return .usingApp
        case .idle: return .inactive
        default: return .noPush
        }
    }

    /// «عضو مسجّل · يستخدم التطبيق» …
    var statusLine: String {
        guard let status else { return L10n.t("جارٍ التحقق…", "Checking…") }
        guard status == .registered || status == .frozen, let usage = account?.usage else { return status.title }
        let use: String
        switch usage {
        case .active: use = AdminMemberSub.usingApp.title
        case .idle: use = AdminMemberSub.inactive.title
        default: use = AdminMemberSub.noPush.title
        }
        return "\(status.title) · \(use)"
    }

    var lastSeenText: String {
        if let seen = account?.lastSeen { return Self.dateText(seen) }
        return account == nil ? L10n.t("لم يسجّل الدخول بعد", "Not signed in yet") : "—"
    }

    static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
    }

    static func dateText(iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return dateText(d) }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso).map(dateText) ?? iso
    }

    /// «yyyy-MM-dd» ← «٣ مارس ١٩٩٠»
    static func dayText(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(raw.prefix(10))) else { return String(raw.prefix(10)) }
        return dateText(d)
    }
}

// MARK: - الرأس

struct AdminMemberSheetHero: View {
    let member: FamilyMember
    let facts: AdminMemberSheetFacts
    let onClose: () -> Void
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                DSMemberAvatar(name: member.fullName, avatarUrl: member.avatarUrl, size: DS.Icon.avatarLarge,
                               roleColor: facts.status == .registered ? DS.Color.palm : DS.Color.slate)
                    .grayscale(member.isDeceased == true ? 1 : 0)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(member.shortFullName.isEmpty ? L10n.t("بلا اسم", "No name") : member.shortFullName)
                        .dsFont(.pageTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: [member.displayFullName, facts.branchTitle(appSettingsVM)].compactMap { $0 }.joined(separator: " · "))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    OccasionFlowLayout(spacing: DS.Spacing.xs) {
                        if let status = facts.status {
                            DSStatusChip(text: status.title, icon: status.icon, tint: status.tint)
                        }
                        if let usage = facts.usageSub {
                            DSStatusChip(text: usage.title, tint: usage == .usingApp ? DS.Color.info : DS.Color.warning)
                        }
                        if [.owner, .admin, .monitor, .supervisor].contains(member.role) {
                            DSStatusChip(text: member.roleName, tint: member.roleColor)
                        }
                    }
                }
                Spacer(minLength: 0)
                DSCloseButton(action: onClose)
            }
            if member.isDeceased != true, let phone = member.phoneNumber, !AdminMemberFacts.isBlank(phone) {
                HStack(spacing: DS.Spacing.sm) {
                    AdminPillButton(title: L10n.t("اتصال", "Call"), icon: "phone.fill", style: .soft,
                                    height: DS.Hub.pillHeightCard, fullWidth: true) {
                        let digits = phone.filter { $0.isNumber || $0 == "+" }
                        if let url = URL(string: "tel:\(digits)") { openURL(url) }
                    }
                    AdminPillButton(title: L10n.t("واتساب", "WhatsApp"), icon: "message.fill", style: .soft,
                                    height: DS.Hub.pillHeightCard, fullWidth: true) {
                        let digits = phone.filter(\.isNumber)
                        if let url = URL(string: "https://wa.me/\(digits)") { openURL(url) }
                    }
                }
            }
        }
    }
}

// MARK: - «البيانات»

struct AdminMemberDataSection: View {
    let member: FamilyMember
    let facts: AdminMemberSheetFacts
    let canEdit: Bool
    let open: (AdminMemberBox) -> Void
    let openTall: (AdminMemberTallBox) -> Void

    private var genderText: String {
        switch (member.gender ?? "").lowercased() {
        case "male": return L10n.t("ذكر", "Male")
        case "female": return L10n.t("أنثى", "Female")
        default: return L10n.t("غير محدّد", "Not set")
        }
    }

    /// «تحديد» لمن بلا جنس (المربّع الصغير)، و«تغيير» لمن له جنس ← «بيانات العضو» (النقل بين الشجرتين)
    private var genderAction: (String, () -> Void)? {
        guard canEdit else { return nil }
        let m = member
        if AdminMemberFacts.isBlank(m.gender) {
            return (L10n.t("تحديد", "Set"), { open(.gender(m)) })
        }
        return (L10n.t("تغيير", "Change"), { openTall(.editAll(m)) })
    }

    private var photoText: String {
        if !AdminMemberFacts.isBlank(member.avatarUrl) { return L10n.t("موجودة", "Added") }
        return member.avatarUnavailable == true ? L10n.t("لا توجد صورة لهذا العضو", "No photo exists") : L10n.t("لا توجد صورة", "No photo")
    }

    private var deathText: String {
        if member.deathDateUnknown == true { return L10n.t("غير معروف", "Unknown") }
        if AdminMemberFacts.deathIncomplete(member) {
            let raw = AdminMemberSheetFacts.dayText(member.deathDate)
            return [raw, AdminMemberGap.deathIncomplete.title].compactMap { $0 }.joined(separator: " · ")
        }
        return AdminMemberSheetFacts.dayText(member.deathDate) ?? "—"
    }

    var body: some View {
        let birth = AdminMemberSheetFacts.dayText(member.birthDate)
        let bio = member.bio?.count ?? 0
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: L10n.t("البيانات", "Details"))
            AdminRowsCard {
                AdminSheetRow(icon: "person.text.rectangle.fill", tint: DS.Color.primary, title: L10n.t("الاسم", "Name"),
                              value: member.displayFullName, multiline: true,
                              action: canEdit ? (L10n.t("تعديل", "Edit"), { openTall(.editAll(member)) }) : nil)
                AdminSheetRow(icon: "calendar", tint: DS.Color.palm, title: L10n.t("تاريخ الميلاد", "Birth date"),
                              value: birth ?? L10n.t("غير مسجّل", "Not recorded"),
                              action: canEdit ? (birth == nil ? L10n.t("إضافة", "Add") : L10n.t("تعديل", "Edit"), { open(.birth(member)) }) : nil)
                // جنس محدّد: تغييره نقل بين الشجرتين — في «بيانات العضو» (`move_child_gender` بتأكيد)؛
                // بلا جنس: «تحديد» كما كان
                AdminSheetRow(icon: "person.fill.questionmark", tint: DS.Color.male, title: L10n.t("الجنس", "Gender"),
                              value: genderText,
                              action: genderAction)
                AdminSheetRow(icon: "photo.fill", tint: DS.Color.sadu, title: L10n.t("الصورة", "Photo"), value: photoText,
                              action: canEdit ? (AdminMemberFacts.isBlank(member.avatarUrl) ? L10n.t("إضافة", "Add") : L10n.t("تغيير", "Change"),
                                                 { open(.photo(member)) }) : nil)
                if member.isDeceased == true {
                    AdminSheetRow(icon: "calendar.badge.clock", tint: DS.Color.deceased, title: L10n.t("تاريخ الوفاة", "Death date"),
                                  value: deathText,
                                  action: canEdit ? (AdminMemberFacts.deathIncomplete(member) ? L10n.t("استكمال", "Complete") : L10n.t("تعديل", "Edit"),
                                                     { open(AdminMemberFacts.isBlank(member.deathDate) || member.deathDateUnknown == true
                                                            ? .death(member) : .deathDate(member)) }) : nil)
                }
                AdminSheetRow(icon: "book.pages.fill", tint: DS.Color.accent, title: L10n.t("السيرة الذاتية", "Biography"),
                              value: bio == 0 ? L10n.t("لا أحداث", "No entries") : L10n.t("\(bio) أحداث", "\(bio) entries"),
                              action: canEdit ? (bio == 0 ? L10n.t("إضافة", "Add") : L10n.t("تعديل", "Edit"), { openTall(.editAll(member)) }) : nil)
            }
        }
    }
}

// MARK: - «النسب»

struct AdminMemberLineageSection: View {
    let member: FamilyMember
    let facts: AdminMemberSheetFacts
    let canEdit: Bool
    let canManageChildren: Bool
    let open: (AdminMemberTallBox) -> Void
    let ask: (AdminMemberConfirm) -> Void
    let openWomen: () -> Void

    var body: some View {
        let kids = facts.children
        let names = kids.prefix(4).map(\.firstName).joined(separator: "، ") + (kids.count > 4 ? "…" : "")
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: L10n.t("النسب", "Lineage"))
            AdminRowsCard {
                if !facts.isFamilyRoot {
                    AdminSheetRow(icon: "person.line.dotted.person", tint: DS.Color.info, title: L10n.t("الأب", "Father"),
                                  value: facts.father?.displayFullName ?? AdminMemberProblem.orphan.title, multiline: true,
                                  action: canEdit ? (facts.father == nil ? L10n.t("ربط", "Link") : L10n.t("تغيير", "Change"),
                                                     { open(.father(member)) }) : nil)
                }
                AdminSheetRow(icon: "person.2.fill", tint: DS.Color.palm,
                              title: L10n.t("الأبناء (\(kids.count))", "Children (\(kids.count))"),
                              value: kids.isEmpty ? L10n.t("لا أبناء مسجّلون", "No children recorded") : names,
                              action: canManageChildren ? (L10n.t("إدارة", "Manage"), { open(.editAll(member)) }) : nil)
                AdminSheetRow(icon: "figure.2", tint: DS.Color.female, title: L10n.t("الأم والزوجة", "Mother and wife"),
                              value: L10n.t("تُدار من شجرة النساء", "Managed in the women's tree"),
                              action: (L10n.t("فتح", "Open"), openWomen))
                if canEdit {
                    AdminSheetRow(icon: member.isHiddenFromTree ? "eye.slash" : "eye", tint: DS.Color.slate,
                                  title: L10n.t("الظهور في الشجرة", "Shown in the tree"),
                                  value: member.isHiddenFromTree ? AdminMemberProblem.hidden.title : L10n.t("ظاهر", "Shown"),
                                  action: (member.isHiddenFromTree ? L10n.t("إظهار", "Show") : L10n.t("إخفاء", "Hide"),
                                           { ask(member.isHiddenFromTree ? .show : .hide) }))
                }
            }
        }
    }
}

// MARK: - صفّ الورقة

/// صفّ في بطاقات الورقة: مربّع أيقونة + عنوان + قيمة + زرّ كبسولة اختياري (لا سهم — الإجراء ظاهر)
struct AdminSheetRow: View {
    let icon: String
    var tint: Color = DS.Color.primary
    let title: String
    let value: String
    var valueIsNumber: Bool = false
    var multiline: Bool = false
    var action: (String, () -> Void)? = nil
    var busy: Bool = false

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: icon, tint: tint)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: value)
                    .dsFont(.footnote)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(multiline ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.layoutDirection, valueIsNumber ? .leftToRight : LanguageManager.shared.layoutDirection)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: DS.Spacing.xs)
            if let action {
                if busy {
                    ProgressView().scaleEffect(DS.Spinner.chipScale)
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                } else {
                    AdminPillButton(title: action.0, style: .soft, action: action.1)
                        .fixedSize()
                        .accessibilityLabel("\(action.0) — \(title)")
                }
            }
        }
        .padding(.vertical, DS.Spacing.sm + 2)
        .frame(minHeight: DS.Icon.tapTarget)
    }
}

// MARK: - المربّعات والتأكيدات

/// مربّعات بمنتصف الشاشة (الموجودة نفسها)
enum AdminMemberBox: Identifiable {
    case birth(FamilyMember), gender(FamilyMember), photo(FamilyMember), death(FamilyMember), deathDate(FamilyMember)
    case phone(FamilyMember), name(FamilyMember)

    var id: String {
        switch self {
        case .birth(let m): return "birth-\(m.id)"
        case .gender(let m): return "gender-\(m.id)"
        case .photo(let m): return "photo-\(m.id)"
        case .death(let m): return "death-\(m.id)"
        case .deathDate(let m): return "deathDate-\(m.id)"
        case .phone(let m): return "phone-\(m.id)"
        case .name(let m): return "name-\(m.id)"
        }
    }
}

/// مربّعات طويلة من الأسفل (قوائم الأعضاء، المحرّر الكامل)
enum AdminMemberTallBox: Identifiable {
    case father(FamilyMember), editAll(FamilyMember)

    var id: String {
        switch self {
        case .father(let m): return "father-\(m.id)"
        case .editAll(let m): return "edit-\(m.id)"
        }
    }
}

/// إجراء ينتظر التأكيد
enum AdminMemberConfirm: Identifiable, Equatable {
    case register, suspend, unsuspend, block, unblock, hide, show, clearPhone, delete
    case signOut(NotificationViewModel.LinkedDevice)

    var id: String {
        switch self {
        case .register: return "register"
        case .suspend: return "suspend"
        case .unsuspend: return "unsuspend"
        case .block: return "block"
        case .unblock: return "unblock"
        case .hide: return "hide"
        case .show: return "show"
        case .clearPhone: return "clearPhone"
        case .delete: return "delete"
        case .signOut(let d): return "signOut-\(d.id)"
        }
    }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }

    var isDestructive: Bool {
        switch self {
        case .suspend, .block, .delete, .clearPhone, .signOut, .hide: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .register: return L10n.t("تسجيل في التطبيق؟", "Register in the app?")
        case .suspend: return L10n.t("إيقاف الحساب؟", "Suspend the account?")
        case .unsuspend: return L10n.t("رفع الإيقاف؟", "Lift the suspension?")
        case .block: return L10n.t("منع الرقم من التسجيل؟", "Block the number from signing up?")
        case .unblock: return L10n.t("رفع منع الرقم؟", "Unblock the number?")
        case .hide: return L10n.t("إخفاء من الشجرة؟", "Hide from the tree?")
        case .show: return L10n.t("إظهار في الشجرة؟", "Show in the tree?")
        case .clearPhone: return L10n.t("مسح رقم الهاتف؟", "Clear the phone number?")
        case .delete: return L10n.t("حذف العضو نهائياً؟", "Delete the member permanently?")
        case .signOut: return L10n.t("تسجيل خروج الجهاز؟", "Sign out the device?")
        }
    }

    var button: String {
        switch self {
        case .register: return L10n.t("تسجيل في التطبيق", "Register")
        case .suspend: return L10n.t("إيقاف الحساب", "Suspend")
        case .unsuspend: return L10n.t("رفع الإيقاف", "Lift")
        case .block: return L10n.t("منع الرقم", "Block")
        case .unblock: return L10n.t("رفع المنع", "Unblock")
        case .hide: return L10n.t("إخفاء", "Hide")
        case .show: return L10n.t("إظهار", "Show")
        case .clearPhone: return L10n.t("مسح", "Clear")
        case .delete: return L10n.t("حذف", "Delete")
        case .signOut: return L10n.t("تسجيل خروج", "Sign out")
        }
    }

    var message: String {
        switch self {
        case .register: return L10n.t("سيتمكن من الدخول للتطبيق برقمه.", "They'll be able to sign in with their number.")
        case .suspend: return L10n.t("لن يتمكن من الدخول للتطبيق حتى يُرفع الإيقاف.", "They can't use the app until the suspension is lifted.")
        case .unsuspend: return L10n.t("سيتمكن من الدخول للتطبيق مجدداً.", "They'll be able to use the app again.")
        case .block: return L10n.t("لن يتمكن هذا الرقم من التسجيل، ويُوقف حساب صاحبه.", "This number can't sign up, and its account is suspended.")
        case .unblock: return L10n.t("سيتمكن الرقم من التسجيل مجدداً. الحساب يبقى موقوفاً حتى ترفع إيقافه.",
                                     "The number can sign up again. The account stays suspended until you lift it.")
        case .hide: return L10n.t("لن يظهر في الشجرة ولا في العدّ.", "They won't show in the tree or the counts.")
        case .show: return L10n.t("سيظهر في الشجرة من جديد.", "They'll show in the tree again.")
        case .clearPhone: return L10n.t("يُمسح الرقم من هذا العضو فقط (الرقم مكرر عند عضو آخر).", "Clears the number from this member only.")
        case .delete: return L10n.t("يحذف العضو وكل بياناته من الشجرة، ولا يمكن التراجع.", "Removes the member and all their data. This can't be undone.")
        case .signOut(let d): return L10n.t("سيُزال \(d.displayName) من حسابه ويُسجَّل خروجه تلقائياً.",
                                            "\(d.displayName) will be removed and signed out automatically.")
        }
    }
}

/// المربّعات — في نوعها المستقل (حارس المكدس)
private struct AdminMemberSheetBoxes: ViewModifier {
    @Binding var box: AdminMemberBox?
    @Binding var tall: AdminMemberTallBox?
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    func body(content: Content) -> some View {
        content
            .dsCenterBox(item: $box) { target in boxView(target) }
            .dsTallBox(item: $tall) { target in tallView(target) }
    }

    private func boxView(_ target: AdminMemberBox) -> AnyView {
        switch target {
        case .birth(let m): return AnyView(EditBirthDateSheet(member: m, memberVM: memberVM))
        case .gender(let m): return AnyView(EditGenderSheet(member: m, memberVM: memberVM))
        case .photo(let m): return AnyView(EditMemberPhotoSheet(member: m, memberVM: memberVM))
        case .death(let m): return AnyView(EditDeathDateSheet(member: m, memberVM: memberVM))
        case .deathDate(let m): return AnyView(DeceasedDateBox(member: m))
        case .phone(let m): return AnyView(PendingMemberPhoneSheet(member: m, activateOnSave: true).environmentObject(adminRequestVM))
        case .name(let m): return AnyView(EditNameSheet(member: m, memberVM: memberVM))
        }
    }

    private func tallView(_ target: AdminMemberTallBox) -> AnyView {
        switch target {
        case .father(let m): return AnyView(LinkFatherSheet(member: m, memberVM: memberVM))
        case .editAll(let m): return AnyView(AdminMemberDetailSheet(member: m, showsAccount: false))
        }
    }
}

/// التأكيدات والخطأ — في نوعها المستقل (حارس المكدس)
private struct AdminMemberSheetAlerts: ViewModifier {
    @Binding var confirm: AdminMemberConfirm?
    @Binding var failure: String?
    let run: (AdminMemberConfirm) -> Void

    func body(content: Content) -> some View {
        content
            .dsAlert(confirm?.title ?? "",
                     isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                     presenting: confirm) { action in
                Button(action.button, role: action.isDestructive ? .destructive : nil) { run(action) }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { confirm = nil }
            } message: { action in
                Text(action.message)
            }
            .dsAlert(L10n.t("تعذّر التنفيذ", "Couldn't complete"),
                     isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button(L10n.t("حسناً", "OK")) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
    }
}
