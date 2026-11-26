import SwiftUI
import Supabase

// MARK: - ورقة العضو الواحدة «بيانات العضو» — «أ3 ملف موجز وأفعال» (الوحدة V2-3، اختيار المالك ٢٠٢٦-١١-٢٦؛ قبلها U13)
//
// ورقة طويلة (`dsTallBox`) تتمرّر بلا تبويبات، من الأعلى:
//   «إغلاق» ذهبي ثابت على الكحلي ← الرأس الكحلي المختصر (الصورة ٥٦، الاسم كاملاً يلتفّ، «الحالة · الفرع» ذهبياً) وتحته
//   حتى أربعة أزرار: «الملف الكامل» · «في الشجرة» · «اتصال» · «واتساب» (الأخيران للرقم الظاهر لك فقط — `dsVisiblePhone`؛
//   شبكة ٢×٢ مع الخط الكبير) ← رقاقة كريمية لكل ناقص («⚠ تاريخ الوفاة غير مكتمل · أكمل ‹») ← «البيانات» (شريط كحلي) ←
//   «النسب» (أخضر) ← «الحساب» (بترولي، للأحياء) ← «حذف العضو نهائياً» زرّ أحمر بإطار ← سطر القفل على ورقتك/ورقة المالك
//   ← شريط «السابق · 3 من 123 · التالي» أسفل الورقة داخل القائمة التي فُتحت منها فقط.
// القيم في الصفوف بالاسم الأول وحده — الاسم الكامل مرة واحدة في الرأس. القطع في `AdminMemberSheetKit.swift`، صفّ الصورة
// بحالات P1 في `AdminMemberPhotoRow.swift`، و«الحساب» في `AdminMemberAccountSection.swift`؛ المنطق في
// `AdminMemberSheetLogic` (فحصه tests/admin-redesign/U13 وV2c).
// كل أمر هو نفسه السابق بصلاحيته ونداء سيرفره — تغيّر الشكل والترتيب فقط، والتعديل بالمربّعات الموجودة:
//   تاريخ الميلاد `EditBirthDateSheet` · الجنس `EditGenderSheet` · الصورة `EditMemberPhotoSheet` · الوفاة
//   `EditDeathDateSheet` (بلا تاريخ) / `DeceasedDateBox` (سنة فقط/هجري) · الأب `LinkFatherSheet` · الاسم `EditNameSheet` ·
//   الرقم `PendingMemberPhoneSheet(activateOnSave:)` · كل البيانات والسيرة والأبناء `AdminMemberDetailSheet(showsAccount: false)`
//   · «تسجيل في التطبيق» `activateAccount` · الإيقاف `setMemberSuspension` (`canFreezeMembers`) · الأجهزة
//   `fetchDevicesForMember` (عرض `canViewSystemSettings`) وتسجيل خروجها `removeDeviceByAdmin` (`canManageDevices`) · الإخفاء
//   `is_hidden_from_tree` · مسح الرقم المكرر `clearPhoneNumber` · الحذف `deleteMember` (`canDeleteMembers`، لا المالك ولا النفس).
// «في الشجرة»: `.requestMemberInTree` ← `MainTabView` (تبويب الشجرة) و`TreeTabContainer` (شجرة العائلة) ← `.openMemberInTree`
//   الذي تعالجه `TreeView` أصلاً (نفس اختيار عضو من بحث الشجرة: المسار مفتوح والعضو مظلّل والكاميرا عليه).
// «منع الرقم من التسجيل» بيته الوحيد صفحة «التسجيل والمنع» (spec B.7/T4): الصفّ هنا يفتحها برقم العضو مطبَّعاً
//   (`KuwaitPhone.normalizedForStorage`، لا رقم مخفي أبداً) ومربّع المنع هناك مملوء لا يُرسل وحده؛ رفع المنع من قائمتها.
// كل أمر = صلاحية الدور × «يعدّل» في جدول السيرفر لقسم «العائلة» (`adminCanEdit(.family)`، Autoplan note 7).
// تجربة الأدوار (`-tmpAdminRole`/`-tmpRoleMatrix`، T0): كل كتابة من هنا تمرّ بـ`DebugAdminProbe.dryRun` (نجاح مصطنع)، والمربّعات
// التي تكتب في ملفات أخرى (الرقم، تاريخ الوفاة، طلب الصورة، المحرّر الكامل) لا تُفتح أثناءها.
// حارس المكدس: الرأس والرقاقات والأقسام أنواع مستقلة في `AnyView`، والمربّعات والتأكيدات في مُعدِّلاتها المستقلة.
// `AdminMemberSheet(ids:start:)` ثابت.

struct AdminMemberSheet: View {
    let ids: [UUID]
    @State private var position: Int
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// من السيرفر عند فتح كل عضو — العضو المحمّل قد يكون قديماً
    @State private var liveStatus: FamilyMember.MemberStatus?
    /// منع رقمه الساري (للعرض فقط — المنع ورفعه في صفحة «التسجيل والمنع»)
    @State private var ban: BannedPhone?
    @State private var devices: [NotificationViewModel.LinkedDevice]?
    @State private var devicesFailed = false
    @State private var devicesOpen = false
    @State private var tree: AdminMemberFacts.TreeContext?

    @State private var box: AdminMemberBox?
    @State private var tall: AdminMemberTallBox?
    @State private var bans: AdminMemberBanPrefill?
    @State private var confirm: AdminMemberConfirm?
    /// سبب الإيقاف (اختياري) — يصل للعضو ويظهر في شاشة الحساب الموقوف
    @State private var suspendReason = ""
    @State private var busy: String?
    @State private var failure: String?

    init(ids: [UUID], start: Int) {
        self.ids = ids
        _position = State(initialValue: AdminMemberSheetLogic.clampedStart(start, count: ids.count))
    }

    private var member: FamilyMember? {
        guard ids.indices.contains(position) else { return nil }
        return memberVM.member(byId: ids[position])
    }

    // MARK: الصلاحيات — صلاحية الدور × «يعدّل» في جدول «العائلة»

    private var familyEdit: Bool { authVM.adminCanEdit(.family) }
    private var canEdit: Bool { authVM.canEditMembers && familyEdit }
    private var canManageChildren: Bool { canEdit && authVM.currentUser?.role != .monitor }
    private var canFreeze: Bool { authVM.canFreezeMembers && familyEdit }
    private var canBan: Bool { authVM.canManageBannedPhones && familyEdit }
    private var canSignOutDevices: Bool { authVM.canManageDevices && familyEdit }
    private var canDelete: Bool { authVM.canDeleteMembers && familyEdit }

    /// لا المالك ولا أنت — وحده يقبل الإيقاف ومنع الرقم والحذف
    private func isOther(_ m: FamilyMember) -> Bool {
        AdminMemberSheetLogic.isOther(memberId: m.id, viewerId: authVM.currentUser?.id, memberIsOwner: m.role == .owner)
    }

    var body: some View {
        page
            .safeAreaInset(edge: .bottom, spacing: 0) { stepBar }
            .background(AdminMemberSheetBackdrop(band: member != nil))
            .modifier(AdminMemberSheetBoxes(box: $box, tall: $tall, bans: $bans, onBansClosed: bansClosed))
            .modifier(AdminMemberSheetAlerts(confirm: $confirm, failure: $failure, suspendReason: $suspendReason, run: run))
            .onAppear { tree = AdminMemberFacts.TreeContext(memberVM.allMembers) }
            .onChange(of: memberVM.membersVersion) { _ in tree = AdminMemberFacts.TreeContext(memberVM.allMembers) }
            .task(id: ids.indices.contains(position) ? ids[position] : nil) { await refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .debugStackProbe("AdminMemberSheet")
    }

    // MARK: الهيكل

    /// «إغلاق» ثابت فوق على الكحلي، والرأس والأقسام تتمرّر تحته
    private var page: AnyView {
        AnyView(VStack(spacing: 0) {
            AdminMemberCloseBar { dismiss() }
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    content
                        .id(Self.topAnchor)
                }
                .onChange(of: position) { _ in
                    devicesOpen = false
                    proxy.scrollTo(Self.topAnchor, anchor: .top)
                }
            }
        })
    }

    private static let topAnchor = "member-sheet-top"

    private var content: AnyView {
        guard let m = member else {
            return AnyView(DSEmptyView(L10n.t("العضو غير موجود", "Member not found"),
                                       message: L10n.t("ربما حُذف أو تغيّر، يرجى العودة إلى القائمة", "It may have been deleted — go back to the list"),
                                       style: .card)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.lg))
        }
        let facts = AdminMemberSheetFacts(member: m, all: memberVM.allMembers, byId: memberVM.member(byId:), tree: tree,
                                          account: accounts.info(m.id), accountsReady: accounts.loaded,
                                          liveStatus: liveStatus, daughterSon: DaughterSonsIndex.shared.contains(m.id))
        let phone = m.dsVisiblePhone(viewerId: authVM.currentUser?.id, viewerCanModerate: authVM.canModerate)
        let actions = AdminMemberSheetLogic.headerActions(canEdit: canEdit, inTree: m.isCountable,
                                                          isDeceased: m.isDeceased == true, visiblePhone: phone)
        return AnyView(VStack(spacing: 0) {
            AnyView(AdminMemberSheetHeader(member: m, facts: facts, branch: facts.branchTitle(appSettingsVM),
                                           actions: actions) { perform($0, m, phone: phone) })
            AnyView(sections(m, facts))
        })
    }

    /// تحت الرأس: الرقاقات ← «البيانات» ← «النسب» ← «الحساب» ← الحذف ← سطر القفل (أرضية بيضاء)
    private func sections(_ m: FamilyMember, _ facts: AdminMemberSheetFacts) -> some View {
        let chips = AdminMemberSheetLogic.missingChips(
            gaps: facts.gaps.compactMap { AdminMemberSheetLogic.Missing(rawValue: $0.rawValue) },
            problems: facts.problems.compactMap { AdminMemberSheetLogic.Missing(rawValue: $0.rawValue) },
            canEdit: canEdit)
        let living = m.isDeceased != true
        let other = isOther(m)
        let phone = (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // الرقم المخفي يُرفض قبل استعمال المطبَّع (المنطق في `AdminMemberSheetLogic`)
        let normalized = Self.storagePhone(phone)
        let banPrefill = AdminMemberSheetLogic.banPrefill(phone, normalize: { _ in normalized })
        let commands = AdminMemberSheetLogic.accountCommands(isOther: other, canFreeze: canFreeze, canBan: canBan,
                                                             banPrefill: banPrefill, canDelete: canDelete)
        let lock = AdminMemberSheetLogic.lockNote(memberId: m.id, viewerId: authVM.currentUser?.id,
                                                  memberIsOwner: m.role == .owner, isDeceased: !living,
                                                  viewerCanAct: canEdit || canFreeze || canBan || canDelete)
        return VStack(alignment: .leading, spacing: DS.Hub.memberSectionGap) {
            if !chips.isEmpty {
                AnyView(AdminMemberMissingChips(items: chips, busy: busy) { fix($0, m) })
            }
            AnyView(AdminMemberDataSection(member: m, facts: facts, canEdit: canEdit, noDevices: noDevices(facts),
                                           open: openBox, openTall: openTall))
            AnyView(AdminMemberLineageSection(member: m, facts: facts, canEdit: canEdit,
                                              canManageChildren: canManageChildren, busy: busy,
                                              open: openTall, ask: { confirm = $0 },
                                              openWomen: openWomenTree))
            if living {
                AnyView(AdminMemberAccountSection(
                    member: m, facts: facts, canEdit: canEdit, isOther: other, commands: commands, banPrefill: banPrefill,
                    liveStatus: liveStatus, ban: ban, devices: devices, devicesFailed: devicesFailed,
                    devicesOpen: $devicesOpen,
                    showsDevices: authVM.canViewSystemSettings && facts.status != .treeOnly,
                    canSignOutDevices: canSignOutDevices, busy: busy,
                    openBox: openBox, ask: ask, openBans: { bans = AdminMemberBanPrefill(phone: $0) },
                    retryDevices: { Task { await loadDevices(m) } }))
            }
            // آخر الورقة: أحمر بإطار، ويسأل قبل الحذف (spec A.6/A.14)
            if commands.delete {
                AnyView(AdminMemberDeleteButton(busy: busy == AdminMemberConfirm.delete.id) { confirm = .delete })
            }
            if let lock {
                AnyView(AdminMemberLockNote(note: lock))
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.md)
        .padding(.bottom, DS.Hub.pageBottom)
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth)
        .frame(maxWidth: .infinity)
        .background(DS.Hub.background)
    }

    /// لا جهاز مسجّل له: الأجهزة حين جُلبت (المالك)، وإلا فئة الاستخدام «دخل بلا جهاز» (`AdminAccountsStore`)
    private func noDevices(_ facts: AdminMemberSheetFacts) -> Bool {
        if let devices, !devicesFailed { return devices.isEmpty }
        return facts.account?.usage == .loginNoDevice
    }

    // MARK: أزرار الرأس

    private func perform(_ action: AdminMemberHeaderAction, _ m: FamilyMember, phone: String?) {
        switch action {
        case .fullProfile: openTall(.editAll(m))
        case .tree: openInTree(m)
        case .call: if let url = KuwaitPhone.telURL(phone) { openURL(url) }
        case .whatsapp: if let url = KuwaitPhone.whatsappURL(phone) { openURL(url) }
        }
    }

    /// «في الشجرة»: تغلق الورقة، وتبويب الشجرة يفتح على شجرة العائلة والعضو في وسطها بمساره مفتوحاً ومظلّلاً
    private func openInTree(_ m: FamilyMember) {
        dismiss()
        NotificationCenter.default.post(name: .requestMemberInTree, object: nil, userInfo: ["memberId": m.id])
    }

    // MARK: «أكمل الناقص» — كل رقاقة تفتح مربّع إصلاحها (نفس المربّعات) أو تأكيده

    private func fix(_ item: AdminMemberSheetLogic.Missing, _ m: FamilyMember) {
        if let gap = item.gap {
            fixGap(gap, m)
        } else if let problem = item.problem {
            fixProblem(problem, m)
        }
    }

    private func fixGap(_ gap: AdminMemberGap, _ m: FamilyMember) {
        switch gap {
        case .noBirth: openBox(.birth(m))
        case .noGender: openBox(.gender(m))
        case .noPhoto: openBox(.photo(m))
        case .deathIncomplete: openBox(AdminMemberFacts.isBlank(m.deathDate) ? .death(m) : .deathDate(m))
        }
    }

    private func fixProblem(_ p: AdminMemberProblem, _ m: FamilyMember) {
        switch p {
        case .orphan, .brokenParent: openTall(.father(m))
        case .noName: openBox(.name(m))
        case .hidden, .dupPhone: confirm = AdminMemberFix.confirm(p)
        }
    }

    /// تأكيد من «الحساب»: الإيقاف ورفعه يبدآن بسبب فارغ
    private func ask(_ action: AdminMemberConfirm) {
        if action == .suspend || action == .unsuspend { suspendReason = "" }
        confirm = action
    }

    // MARK: شريط «السابق · 3 من 123 · التالي» — داخل القائمة التي فُتحت منها فقط

    @ViewBuilder
    private var stepBar: some View {
        if AdminMemberSheetLogic.showsStepBar(count: ids.count) {
            let counter = AdminMemberSheetLogic.counter(position: position, count: ids.count)
            HStack(spacing: DS.Spacing.sm) {
                stepButton(next: false)
                Spacer(minLength: 0)
                Text(verbatim: L10n.t("\(counter.current) من \(counter.total)", "\(counter.current) of \(counter.total)"))
                    .dsFont(.subtitle)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityLabel(L10n.t("العضو \(counter.current) من \(counter.total)", "Member \(counter.current) of \(counter.total)"))
                Spacer(minLength: 0)
                stepButton(next: true)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Hub.background.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { AdminRowDivider() }
        }
    }

    private func stepButton(next: Bool) -> some View {
        let enabled = AdminMemberSheetLogic.canStep(next: next, position: position, count: ids.count)
        return Button {
            position = AdminMemberSheetLogic.stepped(next: next, position: position, count: ids.count)
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                if !next { Image(systemName: "chevron.backward").dsGlyph(DS.Glyph.sm, weight: .semibold) }
                Text(next ? L10n.t("التالي", "Next") : L10n.t("السابق", "Previous"))
                    .dsFont(.hubSection)
                    .lineLimit(1)
                if next { Image(systemName: "chevron.forward").dsGlyph(DS.Glyph.sm, weight: .semibold) }
            }
            .foregroundColor(DS.Color.primary)
            .frame(minWidth: DS.Icon.tapTarget, minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : DS.Opacity.disabled)
    }

    // MARK: الفتح والإجراءات

    /// المربّعات التي تكتب في ملفات أخرى لا تُفتح أثناء تجربة دور (الحفظ داخلها) — مربّعات هذا الملف تكتب تجريبياً بنفسها
    private func openBox(_ target: AdminMemberBox) {
        if target.savesElsewhere, DebugAdminProbe.dryRun("member sheet box \(target.id) (saves inside)") { return }
        box = target
    }

    private func openTall(_ target: AdminMemberTallBox) {
        if target.savesElsewhere, DebugAdminProbe.dryRun("member sheet editor \(target.id) (saves inside)") { return }
        tall = target
    }

    private func openWomenTree() {
        dismiss()
        TreeTabContainer.openWomenOnAppear = true
        NotificationCenter.default.post(name: .openWomenTree, object: nil)
    }

    /// صفحة «التسجيل والمنع» أُغلقت: المنع يوقف الحساب أيضاً — نعيد قراءة الحالة والمنع
    private func bansClosed() {
        guard let m = member else { return }
        Task {
            await refreshBan(m)
            if let status = await memberVM.fetchMemberStatus(memberId: m.id) { liveStatus = status }
        }
    }

    /// `KuwaitPhone.normalizedForStorage` للرقم كما هو محفوظ: ٨ أرقام كويتية أو «+رمز…»
    private static func storagePhone(_ raw: String) -> String? {
        let parts = KuwaitPhone.detectCountryAndLocal(raw)
        return KuwaitPhone.normalizedForStorage(country: parts.country, rawLocalDigits: parts.localDigits)
    }

    private func refresh() async {
        liveStatus = nil
        ban = nil
        devices = nil
        devicesFailed = false
        if !accounts.loaded { await accounts.refresh() }
        guard let m = member, m.isDeceased != true else { return }
        // «طلب تغيير الصورة» المعلّق (السيرفر القديم: لا شيء)
        if authVM.canEditMembers { await PhotoChangeRequestStore.shared.refresh(memberId: m.id) }
        if let status = await memberVM.fetchMemberStatus(memberId: m.id) { liveStatus = status }
        await refreshBan(m)
        if authVM.canViewSystemSettings {
            await loadDevices(m)
        }
    }

    /// تعذّر الجلب ≠ «لا أجهزة» — «تعذّر التحميل» بإعادة المحاولة بدل «لا تصله الإشعارات»
    private func loadDevices(_ m: FamilyMember) async {
        let list = await notificationVM.fetchDevicesForMember(m.id)
        devicesFailed = list == nil
        devices = list ?? []
    }

    private func refreshBan(_ m: FamilyMember) async {
        guard canBan, !AdminMemberFacts.isBlank(m.phoneNumber) else { return }
        ban = await authVM.activeBan(for: (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func run(_ action: AdminMemberConfirm) {
        guard let m = member else { return }
        confirm = nil
        // تجربة دور: لا كتابة على السيرفر — نجاح مصطنع
        if DebugAdminProbe.dryRun("member sheet \(action.writeLabel) \(m.id)") {
            if action == .delete {
                DSMomentToast.show(L10n.t("تم الحذف", "Deleted"), moment: .success)
                dismiss()
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            return
        }
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
                ok = await memberVM.setMemberSuspension(memberId: m.id, suspend: action == .suspend,
                                                        reason: action == .suspend ? suspendReason : nil)
                if ok { liveStatus = target } else { failure = memberVM.errorMessage }
            case .hide, .show:
                ok = await AdminMemberSheet.setHidden(m.id, hidden: action == .hide, memberVM: memberVM)
            case .clearPhone:
                ok = await memberVM.clearPhoneNumber(for: m.id)
            case .signOut(let device):
                ok = await notificationVM.removeDeviceByAdmin(device)
                await loadDevices(m)
                if !ok { failure = notificationVM.lastDeviceError }
            case .delete:
                // السيرفر يرفض حذف من له أبناء/زوجة مرتبطون برسالة عربية (`family_links_protected`) — تُعرض كما هي
                if await memberVM.deleteMember(memberId: m.id) {
                    NotificationCenter.default.post(name: .memberDeleted, object: m.id)
                    busy = nil
                    DSMomentToast.show(L10n.t("تم الحذف", "Deleted"), moment: .success)
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

    /// الإخفاء من الشجرة وإظهاره — نفس نداء «صحة الشجرة» السابق ثم إعادة التحميل (المستدعي يمرّ بـ`dryRun` قبله)
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
    /// رأس فرعه (ابن مباشر لرأس الشجرة) — لكتلة العنوان: «فرع علي»
    let branchHead: FamilyMember?

    init(member m: FamilyMember, all: [FamilyMember], byId: (UUID) -> FamilyMember?, tree: AdminMemberFacts.TreeContext?,
         account: AdminAccountInfo?, accountsReady: Bool, liveStatus: FamilyMember.MemberStatus?, daughterSon: Bool = false) {
        var shown = m
        if let liveStatus { shown.status = liveStatus }
        status = AdminMemberFacts.status(shown, hasLogin: accountsReady ? account != nil : nil)
        self.account = account
        gaps = AdminMemberFacts.gaps(m, registered: account != nil)
        // ابن البنت بلا أب ومخفي من شجرة الرجال عمداً — ليست مشكلة (بيته شجرة النساء)
        problems = daughterSon ? [] : (tree.map { AdminMemberFacts.problems(m, in: $0) } ?? [])
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

    /// استخدامه للتطبيق — سطر تحت «آخر دخول» (كان بعد الحالة في كتلة العنوان قبل «أ3»): يستخدم التطبيق · غير نشط ·
    /// لا تصله الإشعارات
    var usageLine: String? {
        guard status == .registered || status == .frozen, let usage = account?.usage else { return nil }
        switch usage {
        case .active: return AdminMemberSub.usingApp.title
        case .idle: return AdminMemberSub.inactive.title
        default: return AdminMemberSub.noPush.title
        }
    }

    var lastSeenText: String {
        if let seen = account?.lastSeen { return Self.dateText(seen) }
        return account == nil ? L10n.t("لم يسجّل الدخول بعد", "Not signed in yet") : "—"
    }

    static func dateText(_ date: Date) -> String { DateHelper.displayDate(date) }

    static func dateText(iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return dateText(d) }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso).map(dateText) ?? iso
    }

    /// «yyyy-MM-dd» ← «03/03/1990»
    static func dayText(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(raw.prefix(10))) else { return String(raw.prefix(10)) }
        return dateText(d)
    }
}

// MARK: - «أكمل الناقص»

/// عنوان كل نقص/مشكلة وفعل إصلاحه القصير — رقاقات «أكمل الناقص» تحت الرأس («تاريخ الوفاة غير مكتمل · أكمل»)
@MainActor
enum AdminMemberFix {
    static func title(_ gap: AdminMemberGap) -> String {
        switch gap {
        case .noBirth:         return L10n.t("تاريخ الميلاد ناقص", "Birth date missing")
        case .noGender:        return L10n.t("الجنس غير محدّد", "Gender not set")
        case .noPhoto:         return L10n.t("الصورة ناقصة", "Photo missing")
        case .deathIncomplete: return L10n.t("تاريخ الوفاة غير مكتمل", "Death date incomplete")
        }
    }

    static func verb(_ gap: AdminMemberGap) -> String {
        switch gap {
        case .noBirth, .noPhoto: return L10n.t("أضف", "Add")
        case .noGender:          return L10n.t("حدّد", "Set")
        case .deathIncomplete:   return L10n.t("أكمل", "Complete")
        }
    }

    static func title(_ problem: AdminMemberProblem) -> String {
        switch problem {
        case .orphan:       return L10n.t("لا أب في الشجرة", "No father in the tree")
        case .noName:       return L10n.t("الاسم ناقص", "Name missing")
        case .brokenParent: return L10n.t("ارتباط الأب غير صالح", "Invalid father link")
        case .hidden:       return L10n.t("مخفي من الشجرة", "Hidden from the tree")
        case .dupPhone:     return L10n.t("رقم الهاتف مكرر عند عضو آخر", "Phone used by another member")
        }
    }

    static func verb(_ problem: AdminMemberProblem) -> String {
        switch problem {
        case .orphan:       return L10n.t("اربط", "Link")
        case .noName:       return L10n.t("عدّل", "Edit")
        case .brokenParent: return L10n.t("صحّح", "Fix")
        case .hidden:       return L10n.t("أظهر", "Show")
        case .dupPhone:     return L10n.t("امسح", "Clear")
        }
    }

    /// المشكلة التي إصلاحها كتابة بتأكيد (لا مربّع)
    static func confirm(_ problem: AdminMemberProblem) -> AdminMemberConfirm? {
        switch problem {
        case .hidden: return .show
        case .dupPhone: return .clearPhone
        default: return nil
        }
    }
}

// MARK: - «البيانات»

/// «البيانات» (شريط كحلي): الاسم الأول · الميلاد (+ العمر) · الوفاة (+ «تاريخ الوفاة غير مكتمل» كهرمانياً) · الجنس ·
/// الصورة (بحالات P1 — `AdminMemberPhotoRow`) · السيرة
struct AdminMemberDataSection: View {
    let member: FamilyMember
    let facts: AdminMemberSheetFacts
    let canEdit: Bool
    /// لا جهاز مسجّل له — سطر صفّ الصورة مع «نبّهه يضيف صورة»
    var noDevices: Bool = false
    let open: (AdminMemberBox) -> Void
    let openTall: (AdminMemberTallBox) -> Void

    private var genderText: String {
        switch (member.gender ?? "").lowercased() {
        case "male": return L10n.t("ذكر", "Male")
        case "female": return L10n.t("أنثى", "Female")
        default: return L10n.t("غير محدّد", "Not set")
        }
    }

    /// «40 سنة» / «سنتان» — العمر بالكلمات
    private static func yearsText(_ n: Int) -> String {
        L10n.isArabic
            ? AdminTodayText.arabicCount(n, one: "سنة واحدة", two: "سنتان", few: "سنوات", many: "سنة", single: "سنة")
            : (n == 1 ? "1 year" : "\(n) years")
    }

    /// «40 سنة» للحيّ — من تاريخ الميلاد
    private var ageLine: String? {
        guard member.isDeceased != true, let years = WifeCandidateRules.age(member), years >= 0 else { return nil }
        return L10n.t(Self.yearsText(years), "Age \(years)")
    }

    /// «عن 72 سنة» للمتوفى — حين يُعرف اليومان كاملين
    private var ageAtDeathLine: String? {
        guard member.isDeceased == true, member.deathDateUnknown != true, !AdminMemberFacts.deathIncomplete(member),
              let raw = member.deathDate, raw.count >= 10 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let died = f.date(from: String(raw.prefix(10))),
              let years = WifeCandidateRules.age(member, now: died), years >= 0 else { return nil }
        return L10n.t("عن \(Self.yearsText(years))", "Aged \(years)")
    }

    /// «3 أحداث» / «حدث واحد»
    private func bioCountText(_ n: Int) -> String {
        if n == 0 { return L10n.t("لا سيرة بعد", "None yet") }
        return L10n.isArabic
            ? AdminTodayText.arabicCount(n, one: "حدث واحد", two: "حدثان", few: "أحداث", many: "حدثاً", single: "حدث")
            : (n == 1 ? "1 entry" : "\(n) entries")
    }

    /// «آخرها: زواج 2012» — الحدث بأكبر سنة، وإلا آخر المضاف
    private var latestBioLine: String? {
        guard let list = member.bio, !list.isEmpty else { return nil }
        func year(_ s: FamilyMember.BioStation) -> Int? {
            guard let y = s.year, let r = y.range(of: "\\d{4}", options: .regularExpression) else { return nil }
            return Int(y[r])
        }
        let latest = list.filter { year($0) != nil }.max { (year($0) ?? 0) < (year($1) ?? 0) } ?? list.last
        guard let latest else { return nil }
        let title = latest.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let text = [title, year(latest).map(String.init)].compactMap { $0 }.joined(separator: " ")
        return L10n.t("آخرها: \(text)", "Latest: \(text)")
    }

    /// صفّ يُضغط حين يُعدَّل (بسهم)، وإلا قيمة للاطلاع بلا سهم (spec A.12: للاطلاع = قيم لا أزرار)
    @ViewBuilder
    private func row(_ row: AdminMemberRow, verb: String, action: @escaping () -> Void) -> some View {
        if canEdit {
            AdminMemberTapRow(hint: verb, action: action) { row.chevron(true) }
        } else {
            row
        }
    }

    var body: some View {
        let m = member
        let birth = AdminMemberSheetFacts.dayText(m.birthDate)
        let bio = m.bio?.count ?? 0
        // الاسم الأول وحده — الكامل مرة واحدة في الرأس
        let first = AdminMemberSheetLogic.firstName(m.firstName, full: m.fullName) ?? L10n.t("بلا اسم", "No name")
        return AdminMemberSheetSection(title: L10n.t("البيانات", "Details"), bar: DS.Color.primary) {
            row(AdminMemberRow(icon: "textformat", tint: DS.Color.primary, title: L10n.t("الاسم", "Name"), value: first),
                verb: L10n.t("تعديل", "Edit")) { openTall(.editAll(m)) }
            row(AdminMemberRow(icon: "calendar", tint: DS.Color.primary, title: L10n.t("الميلاد", "Birth"),
                               subtitle: ageLine, value: birth ?? L10n.t("غير مسجّل", "Not recorded")),
                verb: birth == nil ? L10n.t("إضافة", "Add") : L10n.t("تعديل", "Edit")) { open(.birth(m)) }
            if m.isDeceased == true {
                let incomplete = AdminMemberFacts.deathIncomplete(m)
                let value: String = m.deathDateUnknown == true
                    ? L10n.t("غير معروف", "Unknown")
                    : (AdminMemberSheetFacts.dayText(m.deathDate) ?? L10n.t("غير مسجّل", "Not recorded"))
                row(AdminMemberRow(icon: "calendar.badge.clock", tint: DS.Color.deceased, title: L10n.t("الوفاة", "Death"),
                                   subtitle: incomplete ? AdminMemberGap.deathIncomplete.title : ageAtDeathLine,
                                   subtitleWarns: incomplete, value: value),
                    verb: incomplete ? L10n.t("استكمال", "Complete") : L10n.t("تعديل", "Edit")) {
                    open(AdminMemberFacts.isBlank(m.deathDate) || m.deathDateUnknown == true ? .death(m) : .deathDate(m))
                }
            }
            // جنس محدّد: تغييره نقل بين الشجرتين — في المحرّر الكامل (`move_child_gender` بتأكيد)؛ بلا جنس: المربّع الصغير
            row(AdminMemberRow(icon: m.isFemale ? "figure.stand.dress" : "person.fill", tint: DS.Color.slate,
                               title: L10n.t("الجنس", "Gender"), value: genderText),
                verb: AdminMemberFacts.isBlank(m.gender) ? L10n.t("تحديد", "Set") : L10n.t("تغيير", "Change")) {
                if AdminMemberFacts.isBlank(m.gender) { open(.gender(m)) } else { openTall(.editAll(m)) }
            }
            // صفّ واحد بحالات P1 («نبّهه يضيف صورة»، التذكير، «طلب تغيير الصورة») وسهمه للإضافة/التبديل —
            // لا صور للإناث في التطبيق (طلب المالك ٢٠٢٦-١١-٢٤): المصغّرة للذكور فقط
            AdminMemberPhotoRow(member: m, hasLogin: facts.account != nil, canEdit: canEdit, noDevices: noDevices,
                                openPhoto: { open(.photo(m)) }, askChange: { open(.photoRequest(m)) })
            row(AdminMemberRow(icon: "doc.text.fill", tint: DS.Color.accent, title: L10n.t("السيرة", "Biography"),
                               subtitle: latestBioLine, value: bioCountText(bio)),
                verb: bio == 0 ? L10n.t("إضافة", "Add") : L10n.t("تعديل", "Edit")) { openTall(.editAll(m)) }
        }
    }
}

// MARK: - «النسب»

/// «النسب» (شريط أخضر): الأب (اسمه الأول) · الأبناء (العدد + أسماؤهم الأولى) · الأم والزوجة («تُدار من شجرة النساء» ‹) ·
/// «الظهور في الشجرة»
struct AdminMemberLineageSection: View {
    let member: FamilyMember
    let facts: AdminMemberSheetFacts
    let canEdit: Bool
    let canManageChildren: Bool
    let busy: String?
    let open: (AdminMemberTallBox) -> Void
    let ask: (AdminMemberConfirm) -> Void
    let openWomen: () -> Void

    /// الأب بالاسم الأول؛ بلا أب «غير مرتبط بأب»
    private var fatherText: String {
        guard let father = facts.father else { return AdminMemberProblem.orphan.title }
        return AdminMemberSheetLogic.firstName(father.firstName, full: father.fullName) ?? L10n.t("بلا اسم", "No name")
    }

    var body: some View {
        let kids = facts.children
        return AdminMemberSheetSection(title: L10n.t("النسب", "Lineage"), bar: DS.Color.palm) {
            if !facts.isFamilyRoot {
                let father = AdminMemberRow(icon: "arrow.triangle.branch", tint: DS.Color.palm, title: L10n.t("الأب", "Father"),
                                            value: fatherText)
                if canEdit {
                    AdminMemberTapRow(hint: facts.father == nil ? L10n.t("ربط", "Link") : L10n.t("تغيير", "Change"),
                                      action: { open(.father(member)) }) { father.chevron(true) }
                } else {
                    father
                }
            }
            let children = AdminMemberRow(icon: "person.2.fill", tint: DS.Color.palm, title: L10n.t("الأبناء", "Children"),
                                          subtitle: AdminMemberSheetLogic.childrenLine(kids.map(\.firstName)),
                                          value: "\(kids.count)", valueIsNumber: true)
            if canManageChildren {
                AdminMemberTapRow(hint: L10n.t("إدارة", "Manage"), action: { open(.editAll(member)) }) { children.chevron(true) }
            } else {
                children
            }
            AdminMemberTapRow(hint: L10n.t("يفتح شجرة النساء", "Opens the women's tree"), action: openWomen) {
                AdminMemberRow(icon: "heart.fill", tint: DS.Color.palm, title: L10n.t("الأم والزوجة", "Mother and wife"),
                               subtitle: L10n.t("تُدار من شجرة النساء", "Managed in the women's tree"), showsChevron: true)
            }
            visibilityRow
        }
    }

    /// «الظهور في الشجرة»: مفتاح يسأل قبل التغيير لمن يعدّل، وكلمة لمن يطّلع، وابن البنت بلا مفتاح (بيته شجرة النساء)
    @ViewBuilder
    private var visibilityRow: some View {
        let title = L10n.t("الظهور في الشجرة", "Shown in the tree")
        if DaughterSonsIndex.shared.contains(member.id) {
            // ابن بنت: لا «إظهار» في شجرة الرجال (السيرفر يرفضه أيضاً)
            AdminMemberRow(icon: "tree.fill", tint: DS.Color.palm, title: title,
                           subtitle: L10n.t("فرع خارج العائلة — في شجرة النساء فقط", "Outside branch — women's tree only"))
        } else if canEdit {
            let working = busy == AdminMemberConfirm.hide.id || busy == AdminMemberConfirm.show.id
            AdminMemberRow(icon: "tree.fill", tint: DS.Color.palm, title: title,
                           subtitle: member.isHiddenFromTree ? AdminMemberProblem.hidden.title : nil, busy: working) {
                Toggle(title, isOn: Binding(get: { !member.isHiddenFromTree },
                                            set: { shown in ask(shown ? .show : .hide) }))
                    .labelsHidden()
                    .tint(DS.Color.toggleOn)
                    .accessibilityHint(L10n.t("يسأل قبل التغيير", "Asks before changing"))
            }
        } else {
            AdminMemberRow(icon: "tree.fill", tint: DS.Color.palm, title: title,
                           value: member.isHiddenFromTree ? L10n.t("مخفي", "Hidden") : L10n.t("ظاهر", "Shown"))
        }
    }
}

// MARK: - صفّ الورقة (spec A.6)

/// صفّ معلومة: `[مربّع ٣٠ ممتلئ][العنوان ١٥ متوسط / سطر ١٣ رمادي]…[القيمة ١٥ رمادية | حبّة | مفتاح][سهم إن فتح شيئاً]`.
/// ٤٤ لسطر و٥٦ لسطرين. القيمة الطويلة تلتفّ بجانب عنوان قصير، والقصيرة لا تلتفّ؛ من أحجام إمكانية الوصول القيمة تحت
/// العنوان. السطر الكهرماني (`subtitleWarns`): نقص في الصفّ نفسه («تاريخ الوفاة غير مكتمل»). الحذف (`destructive`):
/// العنوان أحمر والمربّع رمز أحمر على ١٢٪
struct AdminMemberRow: View {
    let icon: String
    var tint: Color = DS.Color.primary
    let title: String
    var subtitle: String? = nil
    /// السطر بلون التنبيه (نقص في الصفّ)
    var subtitleWarns: Bool = false
    var value: String? = nil
    /// الرقم يُقرأ من اليسار (+965 …)
    var valueIsNumber: Bool = false
    /// قيمة طويلة (اسم كامل): تلتفّ حتى ٣ أسطر والعنوان بعرضه
    var wrapsValue: Bool = false
    /// صورة مصغّرة قبل القيمة (صفّ «الصورة»)
    var thumbnail: String? = nil
    var destructive: Bool = false
    var showsChevron: Bool = false
    var busy: Bool = false
    var accessory: AnyView? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    init(icon: String, tint: Color = DS.Color.primary, title: String, subtitle: String? = nil, subtitleWarns: Bool = false,
         value: String? = nil, valueIsNumber: Bool = false, wrapsValue: Bool = false, thumbnail: String? = nil,
         destructive: Bool = false, showsChevron: Bool = false, busy: Bool = false) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.subtitleWarns = subtitleWarns
        self.value = value
        self.valueIsNumber = valueIsNumber
        self.wrapsValue = wrapsValue
        self.thumbnail = thumbnail
        self.destructive = destructive
        self.showsChevron = showsChevron
        self.busy = busy
    }

    /// بطرف (حبّة، مفتاح، رمز)
    init<Accessory: View>(icon: String, tint: Color = DS.Color.primary, title: String, subtitle: String? = nil,
                          value: String? = nil, valueIsNumber: Bool = false, busy: Bool = false,
                          @ViewBuilder accessory: () -> Accessory) {
        self.init(icon: icon, tint: tint, title: title, subtitle: subtitle, value: value, valueIsNumber: valueIsNumber, busy: busy)
        self.accessory = AnyView(accessory())
    }

    func chevron(_ on: Bool) -> AdminMemberRow {
        var copy = self
        copy.showsChevron = on
        return copy
    }

    private var stacked: Bool { typeSize.isAccessibilitySize }
    private var hasSubtitle: Bool { !(subtitle ?? "").isEmpty }

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: icon, tint: destructive ? DS.Color.error : tint, filled: !destructive)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.rowTitle)
                    .foregroundColor(destructive ? DS.Color.error : DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .dsFont(subtitleWarns ? .chip : .subtitle)
                        .foregroundColor(subtitleWarns ? DS.Color.warning : DS.Color.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if stacked, let value { valueText(value, alignment: .leading) }
            }
            .fixedSize(horizontal: wrapsValue && !stacked, vertical: false)
            Spacer(minLength: DS.Spacing.sm)
            if let thumbnail, let url = URL(string: thumbnail) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(tint.opacity(DS.Opacity.tintFill))
                }
                .frame(width: DS.Icon.section, height: DS.Icon.section)
                .clipShape(Circle())
                .accessibilityHidden(true)
            }
            if !stacked, let value { valueText(value, alignment: .trailing) }
            if busy {
                ProgressView()
                    .scaleEffect(DS.Spinner.chipScale)
                    .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
            } else if let accessory {
                accessory
            }
            if showsChevron { DSChevron() }
        }
        .padding(.vertical, DS.Spacing.xsm)
        .frame(minHeight: hasSubtitle || stacked ? DS.Hub.rowMinHeightTwoLines : DS.Hub.rowMinHeight)
        .contentShape(Rectangle())
        // بطرف يعمل (حبّة، مفتاح) يبقى الطرف عنصراً مستقلاً بفعله — وإلا الصفّ عنصر واحد
        .accessibilityElement(children: accessory == nil ? .combine : .contain)
    }

    @ViewBuilder
    private func valueText(_ value: String, alignment: TextAlignment) -> some View {
        let text = Text(verbatim: value)
            .dsFont(.body)
            .monospacedDigit()
            .foregroundColor(DS.Color.textTertiary)
            .multilineTextAlignment(alignment)
            .environment(\.layoutDirection, valueIsNumber ? .leftToRight : LanguageManager.shared.layoutDirection)
        if wrapsValue || stacked {
            text.lineLimit(3).fixedSize(horizontal: false, vertical: true)
        } else {
            text.lineLimit(1).fixedSize()
        }
    }
}

/// صفّ يُضغط: تظليل لا تصغير (`AdminRowPressStyle`)، وتلميح ما يحدث
struct AdminMemberTapRow<Label: View>: View {
    let hint: String
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) { label() }
            .buttonStyle(AdminRowPressStyle())
            .accessibilityHint(Text(hint))
    }
}

/// صفّ في بطاقات الورقة بزرّ كبسولة («طلب تغيير الصورة» في صفّ الصورة، ومربّع `PhotoChangeRequestBox`): نفس هيئة `AdminMemberRow` —
/// مربّع ممتلئ، عنوان ١٥، سطر ١٣ رمادي، والإجراء حبّة بإطار في الطرف (لا سهم — الإجراء ظاهر)
struct AdminSheetRow: View {
    let icon: String
    var tint: Color = DS.Color.primary
    let title: String
    let value: String
    var valueIsNumber: Bool = false
    var multiline: Bool = false
    var action: (String, () -> Void)? = nil
    var busy: Bool = false
    /// حبّة الإجراء: بإطار (افتراضي)، أو كحلية في ورقة العضو («طلب» — النموذج «أ3»)
    var actionStyle: AdminPillStyle = .soft

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: icon, tint: tint, filled: true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: value)
                    .dsFont(.subtitle)
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
                    AdminPillButton(title: action.0, style: actionStyle, action: action.1)
                        .fixedSize()
                        .accessibilityLabel("\(action.0) — \(title)")
                }
            }
        }
        .padding(.vertical, DS.Spacing.xsm)
        .frame(minHeight: DS.Hub.rowMinHeightTwoLines)
    }
}

// MARK: - المربّعات والتأكيدات

/// مربّعات بمنتصف الشاشة (الموجودة نفسها)
enum AdminMemberBox: Identifiable {
    case birth(FamilyMember), gender(FamilyMember), photo(FamilyMember), death(FamilyMember), deathDate(FamilyMember)
    case phone(FamilyMember), name(FamilyMember), photoRequest(FamilyMember)

    var id: String {
        switch self {
        case .birth(let m): return "birth-\(m.id)"
        case .gender(let m): return "gender-\(m.id)"
        case .photo(let m): return "photo-\(m.id)"
        case .death(let m): return "death-\(m.id)"
        case .deathDate(let m): return "deathDate-\(m.id)"
        case .phone(let m): return "phone-\(m.id)"
        case .name(let m): return "name-\(m.id)"
        case .photoRequest(let m): return "photoRequest-\(m.id)"
        }
    }

    /// المربّع يحفظ في ملف آخر (بلا `dryRun` داخله) — لا يُفتح أثناء تجربة دور. مربّعات `AdminMemberEditBoxes` تكتب تجريبياً
    var savesElsewhere: Bool {
        switch self {
        case .deathDate, .phone, .photoRequest: return true
        default: return false
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

    /// المحرّر الكامل `AdminMemberDetailSheet` يحفظ في ملفه — لا يُفتح أثناء تجربة دور
    var savesElsewhere: Bool {
        if case .editAll = self { return true }
        return false
    }
}

/// صفحة «التسجيل والمنع» برقم العضو (مطبَّعاً) — مربّع طويل فوق الورقة، رجوعه يغلقه
struct AdminMemberBanPrefill: Identifiable {
    let phone: String
    var id: String { phone }
}

/// إجراء ينتظر التأكيد (spec A.14: العنوان سؤال بالفعل، سطر ما يحدث، والزرّ يكرّر الفعل)
enum AdminMemberConfirm: Identifiable, Equatable {
    case register, suspend, unsuspend, hide, show, clearPhone, delete
    case signOut(NotificationViewModel.LinkedDevice)

    var id: String {
        switch self {
        case .register: return "register"
        case .suspend: return "suspend"
        case .unsuspend: return "unsuspend"
        case .hide: return "hide"
        case .show: return "show"
        case .clearPhone: return "clearPhone"
        case .delete: return "delete"
        case .signOut(let d): return "signOut-\(d.id)"
        }
    }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }

    /// سطر «DRY-RUN» أثناء تجربة دور
    var writeLabel: String {
        switch self {
        case .register: return "activateAccount"
        case .suspend: return "setMemberSuspension suspend"
        case .unsuspend: return "setMemberSuspension lift"
        case .hide: return "profiles.is_hidden_from_tree=true"
        case .show: return "profiles.is_hidden_from_tree=false"
        case .clearPhone: return "clearPhoneNumber"
        case .delete: return "deleteMember"
        case .signOut(let d): return "removeDeviceByAdmin \(d.id)"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .suspend, .delete, .clearPhone, .signOut, .hide: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .register: return L10n.t("تسجيل في التطبيق؟", "Register in the app?")
        case .suspend: return L10n.t("إيقاف الحساب؟", "Suspend the account?")
        case .unsuspend: return L10n.t("رفع الإيقاف؟", "Lift the suspension?")
        case .hide: return L10n.t("إخفاء من الشجرة؟", "Hide from the tree?")
        case .show: return L10n.t("إظهار في الشجرة؟", "Show in the tree?")
        case .clearPhone: return L10n.t("مسح الرقم المكرر؟", "Clear the duplicate number?")
        case .delete: return L10n.t("حذف العضو نهائياً؟", "Delete the member permanently?")
        case .signOut: return L10n.t("تسجيل خروج الجهاز؟", "Sign out the device?")
        }
    }

    var button: String {
        switch self {
        case .register: return L10n.t("سجّله في التطبيق", "Register")
        case .suspend: return L10n.t("أوقف الحساب", "Suspend")
        case .unsuspend: return L10n.t("ارفع الإيقاف", "Lift")
        case .hide: return L10n.t("أخفِه", "Hide")
        case .show: return L10n.t("أظهِره", "Show")
        case .clearPhone: return L10n.t("امسح الرقم", "Clear")
        case .delete: return L10n.t("احذف العضو", "Delete")
        case .signOut: return L10n.t("سجّل خروجه", "Sign out")
        }
    }

    var message: String {
        switch self {
        case .register: return L10n.t("سيتمكن من الدخول للتطبيق برقمه.", "They'll be able to sign in with their number.")
        case .suspend: return L10n.t("لن يتمكن من الدخول للتطبيق حتى يُرفع الإيقاف، وبياناته محفوظة. يصله إشعار بالسبب إن كتبته.",
                                     "They can't use the app until the suspension is lifted; their data is kept. They're notified, with the reason if you add one.")
        case .unsuspend: return L10n.t("سيتمكن من الدخول للتطبيق مجدداً.", "They'll be able to use the app again.")
        case .hide: return L10n.t("لن يظهر في الشجرة ولا في العدّ.", "They won't show in the tree or the counts.")
        case .show: return L10n.t("سيظهر في الشجرة من جديد.", "They'll show in the tree again.")
        case .clearPhone: return L10n.t("يُمسح الرقم من هذا العضو فقط (الرقم مكرر عند عضو آخر).", "Clears the number from this member only.")
        case .delete: return L10n.t("يحذف العضو وكل بياناته من الشجرة. لا يمكن التراجع.", "Removes the member and all their data. This can't be undone.")
        case .signOut(let d): return L10n.t("سيُزال \(d.displayName) من حسابه ويُسجَّل خروجه تلقائياً.",
                                            "\(d.displayName) will be removed and signed out automatically.")
        }
    }
}

/// المربّعات وصفحة «التسجيل والمنع» — في نوعها المستقل (حارس المكدس)
private struct AdminMemberSheetBoxes: ViewModifier {
    @Binding var box: AdminMemberBox?
    @Binding var tall: AdminMemberTallBox?
    @Binding var bans: AdminMemberBanPrefill?
    let onBansClosed: () -> Void
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    func body(content: Content) -> some View {
        content
            .dsCenterBox(item: $box) { target in boxView(target) }
            .dsTallBox(item: $tall) { target in tallView(target) }
            .dsTallBox(item: $bans, onDismiss: onBansClosed) { prefill in bansPage(prefill) }
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
        case .photoRequest(let m): return AnyView(PhotoChangeRequestBox(member: m))
        }
    }

    private func tallView(_ target: AdminMemberTallBox) -> AnyView {
        switch target {
        case .father(let m): return AnyView(LinkFatherSheet(member: m, memberVM: memberVM))
        case .editAll(let m): return AnyView(AdminMemberDetailSheet(member: m, showsAccount: false))
        }
    }

    /// بيت «منع رقم من التسجيل» الوحيد: الصفحة نفسها بمربّع المنع مملوءاً (لا يُرسل وحده)، و«رجوع» يعود للورقة
    private func bansPage(_ prefill: AdminMemberBanPrefill) -> some View {
        AdminLazyPage { AnyView(AdminRegistrationBansView(prefillPhone: prefill.phone)) }
            .adminArea(.team)
            .adminBackTitle(L10n.t("بيانات العضو", "Member details"))
    }
}

/// التأكيدات والخطأ — في نوعها المستقل (حارس المكدس)
private struct AdminMemberSheetAlerts: ViewModifier {
    @Binding var confirm: AdminMemberConfirm?
    @Binding var failure: String?
    @Binding var suspendReason: String
    let run: (AdminMemberConfirm) -> Void

    func body(content: Content) -> some View {
        content
            .dsAlert(confirm?.title ?? "",
                     isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                     presenting: confirm) { action in
                if case .suspend = action {
                    TextField(L10n.t("سبب الإيقاف (اختياري)", "Reason (optional)"), text: $suspendReason)
                        .dsAlertField()
                }
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
