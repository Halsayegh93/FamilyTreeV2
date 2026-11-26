import SwiftUI
import Supabase

// MARK: - ورقة العضو الواحدة «بيانات العضو» (إعادة تصميم الإدارة ٢٠٢٦-١١-٢٦، الوحدة U13 — spec C.10، النموذج ٦)
//
// على نمط «تفاصيل المكان» في خرائط Google: ورقة طويلة (`dsTallBox`) تتمرّر بلا تبويبات، من الأعلى:
//   سطر «إغلاق» ← كتلة العنوان (الصورة، الاسم، الحالة، الفرع) ← صفّ أزرار دائرية «اتصال · واتساب · الملف الكامل»
//   ← «أكمل الناقص» (الناقص والمشكلات بزرّ إصلاح كلٍّ منها) ← «البيانات» ← «النسب» ← «الحساب» (آخره «حذف العضو
//   نهائياً» أحمر بتأكيد) ← شريط «السابق · 3 من 123 · التالي» أسفل الورقة داخل القائمة التي فُتحت منها فقط.
// كل أمر هو نفسه السابق بصلاحيته ونداء سيرفره — تغيّر الشكل والترتيب فقط، والتعديل بالمربّعات الموجودة:
//   تاريخ الميلاد `EditBirthDateSheet` · الجنس `EditGenderSheet` · الصورة `EditMemberPhotoSheet` · الوفاة
//   `EditDeathDateSheet` (بلا تاريخ) / `DeceasedDateBox` (سنة فقط/هجري) · الأب `LinkFatherSheet` · الاسم `EditNameSheet` ·
//   الرقم `PendingMemberPhoneSheet(activateOnSave:)` · كل البيانات والسيرة والأبناء `AdminMemberDetailSheet(showsAccount: false)`
//   · «تسجيل في التطبيق» `activateAccount` · الإيقاف `setMemberSuspension` (`canFreezeMembers`) · الأجهزة
//   `fetchDevicesForMember` (عرض `canViewSystemSettings`) وتسجيل خروجها `removeDeviceByAdmin` (`canManageDevices`) · الإخفاء
//   `is_hidden_from_tree` · مسح الرقم المكرر `clearPhoneNumber` · الحذف `deleteMember` (`canDeleteMembers`، لا المالك ولا النفس).
// «منع الرقم من التسجيل» بيته الوحيد صفحة «التسجيل والمنع» (spec B.7/T4): الصفّ هنا يفتحها برقم العضو مطبَّعاً
//   (`KuwaitPhone.normalizedForStorage`، لا رقم مخفي أبداً) ومربّع المنع هناك مملوء لا يُرسل وحده؛ رفع المنع من قائمتها.
// كل أمر = صلاحية الدور × «يعدّل» في جدول السيرفر لقسم «العائلة» (`adminCanEdit(.family)`، Autoplan note 7).
// تجربة الأدوار (`-tmpAdminRole`/`-tmpRoleMatrix`، T0): كل كتابة من هنا تمرّ بـ`DebugAdminProbe.dryRun` (نجاح مصطنع)، والمربّعات
// التي تكتب في ملفات أخرى (الرقم، تاريخ الوفاة، طلب الصورة، المحرّر الكامل) لا تُفتح أثناءها.
// حارس المكدس: الأقسام في `AnyView` منفصلة، والمربّعات والتأكيدات في مُعدِّلاتها المستقلة. `AdminMemberSheet(ids:start:)` ثابت.

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    private func isOther(_ m: FamilyMember) -> Bool {
        m.role != .owner && m.id != authVM.currentUser?.id
    }

    var body: some View {
        page
            .safeAreaInset(edge: .bottom, spacing: 0) { stepBar }
            .background(DS.Hub.background.ignoresSafeArea())
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

    /// سطر «إغلاق» ثابت فوق، والمحتوى يتمرّر تحته
    private var page: AnyView {
        AnyView(VStack(spacing: 0) {
            navRow
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

    /// «إغلاق» في الطرف (spec C.10: بلا عنوان — الاسم في كتلة العنوان). مكان «⋯» محجوز فارغاً: لا أمر له اليوم،
    /// وزرّ لا يفعل شيئاً أسوأ من فراغ. داخل مكدس (مربّع طلب) «إغلاق» يرجع خطوة
    private var navRow: some View {
        HStack {
            Button { dismiss() } label: {
                Text(L10n.t("إغلاق", "Close"))
                    .dsFont(.body)
                    .foregroundColor(DS.Color.primary)
                    .frame(minWidth: DS.Icon.tapTarget, minHeight: DS.Icon.tapTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DSPressStyle())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.sm)
    }

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
        return AnyView(VStack(alignment: .leading, spacing: DS.Hub.sectionGap) {
            AnyView(head(m, facts))
            if canEdit && (!facts.gaps.isEmpty || !facts.problems.isEmpty) {
                AnyView(fixesSection(m, facts))
            }
            AnyView(AdminMemberDataSection(member: m, facts: facts, canEdit: canEdit,
                                           open: openBox, openTall: openTall))
            AnyView(AdminMemberLineageSection(member: m, facts: facts, canEdit: canEdit,
                                              canManageChildren: canManageChildren, busy: busy,
                                              open: openTall, ask: { confirm = $0 },
                                              openWomen: openWomenTree))
            if m.isDeceased != true {
                AnyView(accountSection(m, facts))
            } else if canDelete && isOther(m) {
                // المتوفى بلا «الحساب»: الحذف وحده آخر الورقة، أحمر بتأكيد
                AnyView(AdminRowsCard(dividerInset: AdminRowDivider.iconInset) { deleteRow })
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.xs)
        .padding(.bottom, DS.Hub.pageBottom)
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth)
        .frame(maxWidth: .infinity))
    }

    // MARK: كتلة العنوان + الأزرار الدائرية

    private func head(_ m: FamilyMember, _ facts: AdminMemberSheetFacts) -> some View {
        let phone = m.dsVisiblePhone(viewerId: authVM.currentUser?.id, viewerCanModerate: authVM.canModerate)
        let canContact = AdminMemberSheetLogic.canContact(phone)
        return VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            AdminMemberTitleBlock(member: m, facts: facts, branch: facts.branchTitle(appSettingsVM))
            if canContact || canEdit {
                HStack(alignment: .top, spacing: DS.Spacing.lg) {
                    if canContact {
                        AdminMemberRoundAction(title: L10n.t("اتصال", "Call"), icon: "phone.fill") {
                            if let url = KuwaitPhone.telURL(phone) { openURL(url) }
                        }
                        AdminMemberRoundAction(title: L10n.t("واتساب", "WhatsApp"), icon: "message.fill") {
                            if let url = KuwaitPhone.whatsappURL(phone) { openURL(url) }
                        }
                    }
                    if canEdit {
                        AdminMemberRoundAction(title: L10n.t("الملف الكامل", "Full profile"), icon: "pencil") {
                            openTall(.editAll(m))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: «أكمل الناقص» — الناقص ومشكلات الشجرة بزرّ إصلاح كلٍّ منها (نفس المربّعات)

    private func fixesSection(_ m: FamilyMember, _ facts: AdminMemberSheetFacts) -> some View {
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: L10n.t("أكمل الناقص", "Fill in what's missing"))
            AdminRowsCard(dividerInset: AdminMemberFixRow.dividerInset, framed: true) {
                ForEach(facts.gaps) { gap in
                    AdminMemberFixRow(title: AdminMemberFix.title(gap), verb: AdminMemberFix.verb(gap)) { fixGap(gap, m) }
                }
                ForEach(facts.problems) { problem in
                    AdminMemberFixRow(title: AdminMemberFix.title(problem), verb: AdminMemberFix.verb(problem),
                                      busy: busy == AdminMemberFix.confirm(problem)?.id) { fixProblem(problem, m) }
                }
            }
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

    // MARK: «الحساب» — الرقم، التسجيل، آخر دخول، الأجهزة، الإيقاف، منع الرقم، وآخرها الحذف

    private func accountSection(_ m: FamilyMember, _ facts: AdminMemberSheetFacts) -> some View {
        let other = isOther(m)
        let phone = (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let frozen = facts.status == .frozen
        // الرقم المخفي يُرفض قبل استعمال المطبَّع (المنطق في `AdminMemberSheetLogic`)
        let normalized = Self.storagePhone(phone)
        let banPrefill = AdminMemberSheetLogic.banPrefill(phone, normalize: { _ in normalized })
        return VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: L10n.t("الحساب", "Account"))
            AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                phoneRow(m, phone: phone)
                registerRow(m, facts, phone: phone, other: other, frozen: frozen)
                AdminMemberRow(icon: "clock.fill", tint: DS.Color.sea, title: L10n.t("آخر دخول", "Last sign-in"),
                               value: facts.lastSeenText)
                // الأجهزة لمن له حساب دخول (من بلا حساب لا جهاز له)
                if authVM.canViewSystemSettings && facts.status != .treeOnly {
                    devicesRow(m)
                    if devicesOpen, let devices, !devicesFailed {
                        ForEach(devices) { device in deviceRow(device) }
                    }
                }
                if canFreeze && other {
                    AdminMemberTapRow(hint: frozen ? L10n.t("يسأل قبل رفع الإيقاف", "Asks before lifting")
                                                   : L10n.t("يسأل قبل الإيقاف", "Asks before suspending"),
                                      action: { suspendReason = ""; confirm = frozen ? .unsuspend : .suspend }) {
                        AdminMemberRow(icon: frozen ? "play.fill" : "pause.fill", tint: DS.Color.slate,
                                       title: frozen ? L10n.t("رفع الإيقاف", "Lift the suspension")
                                                     : L10n.t("إيقاف الحساب", "Suspend account"),
                                       subtitle: frozen ? L10n.t("الحساب موقوف الآن", "The account is suspended") : nil,
                                       showsChevron: true,
                                       busy: busy == AdminMemberConfirm.suspend.id || busy == AdminMemberConfirm.unsuspend.id)
                    }
                }
                if canBan && other, let banPrefill {
                    AdminMemberTapRow(hint: L10n.t("يفتح «التسجيل والمنع» برقمه", "Opens sign-up and blocking with this number"),
                                      action: { bans = AdminMemberBanPrefill(phone: banPrefill) }) {
                        AdminMemberRow(icon: "lock.fill", tint: DS.Color.slate,
                                       title: L10n.t("منع الرقم من التسجيل", "Block the number from signing up"),
                                       subtitle: ban == nil ? nil : L10n.t("الرقم ممنوع من التسجيل الآن", "The number is blocked now"),
                                       showsChevron: true)
                    }
                }
                if canDelete && other {
                    deleteRow
                }
            }
        }
    }

    private func phoneRow(_ m: FamilyMember, phone: String) -> some View {
        let row = AdminMemberRow(icon: "phone.fill", tint: DS.Color.sea, title: L10n.t("الهاتف", "Phone"),
                                 value: phone.isEmpty ? L10n.t("بلا رقم هاتف", "No phone") : KuwaitPhone.display(phone),
                                 valueIsNumber: !phone.isEmpty, showsChevron: canEdit)
        return Group {
            if canEdit {
                AdminMemberTapRow(hint: phone.isEmpty ? L10n.t("إضافة", "Add") : L10n.t("تعديل", "Edit"),
                                  action: { openBox(.phone(m)) }) { row }
            } else {
                row
            }
        }
    }

    /// «تسجيل في التطبيق»: حبّة الحالة، أو حبّة «سجّل» حين يمكن (بتأكيد) — نفس شرط الزرّ السابق
    private func registerRow(_ m: FamilyMember, _ facts: AdminMemberSheetFacts, phone: String, other: Bool, frozen: Bool) -> some View {
        let canRegister = canEdit && other && !frozen && !phone.isEmpty && m.role != .pending
            && (liveStatus ?? m.status) != .active && facts.status != .registered
        let note: String? = {
            guard !canRegister, facts.status == .treeOnly else { return nil }
            if phone.isEmpty { return L10n.t("يحتاج رقم هاتف أولاً", "Needs a phone number first") }
            return nil
        }()
        return AdminMemberRow(icon: "iphone", tint: DS.Color.sea, title: L10n.t("تسجيل في التطبيق", "Registered in the app"),
                              subtitle: note, busy: busy == AdminMemberConfirm.register.id) {
            if canRegister {
                AdminPillButton(title: L10n.t("سجّل", "Register"), style: .navy) { confirm = .register }
                    .accessibilityLabel(L10n.t("تسجيل في التطبيق", "Register in the app"))
                    .accessibilityHint(L10n.t("يسأل قبل التسجيل", "Asks first"))
            } else {
                AdminStatePill(title: Self.registerWord(facts.status), tone: Self.registerTone(facts.status),
                               icon: facts.status == .registered ? "checkmark" : nil)
            }
        }
    }

    private static func registerWord(_ status: AdminMemberStatus?) -> String {
        switch status {
        case .registered: return L10n.t("مسجّل", "Registered")
        case .frozen: return L10n.t("موقوف", "Suspended")
        case .pendingJoin: return L10n.t("قيد المراجعة", "Under review")
        case .treeOnly, .deceased: return L10n.t("غير مسجّل", "Not registered")
        case nil: return AdminStoreHealthText.placeholder
        }
    }

    private static func registerTone(_ status: AdminMemberStatus?) -> AdminPillTone {
        switch status {
        case .registered: return .ok
        case .frozen: return .error
        default: return .off
        }
    }

    /// «الأجهزة · 2 ⌄» يفتح أجهزته تحته (و«تسجيل خروج» للمالك) — التحميل «—»، والفشل «تعذّر التحميل» يعيد الجلب
    @ViewBuilder
    private func devicesRow(_ m: FamilyMember) -> some View {
        let title = L10n.t("الأجهزة", "Devices")
        if let devices {
            if devicesFailed {
                AdminMemberTapRow(hint: AdminStoreHealthText.retry, action: { Task { await loadDevices(m) } }) {
                    AdminMemberRow(icon: "iphone.gen3", tint: DS.Color.sea, title: title) {
                        AdminStatePill(title: AdminStoreHealthText.failed, tone: .unknown, icon: "arrow.clockwise")
                    }
                }
            } else if devices.isEmpty {
                AdminMemberRow(icon: "iphone.slash", tint: DS.Color.sea, title: title,
                               subtitle: L10n.t("لا تصله الإشعارات", "Gets no notifications"),
                               value: L10n.t("لا أجهزة", "None"))
            } else {
                AdminMemberTapRow(hint: devicesOpen ? L10n.t("يطوي الأجهزة", "Hides the devices")
                                                    : L10n.t("يعرض الأجهزة", "Shows the devices"),
                                  action: { withAnimation(reduceMotion ? nil : DS.Anim.snappy) { devicesOpen.toggle() } }) {
                    AdminMemberRow(icon: "iphone.gen3", tint: DS.Color.sea, title: title,
                                   value: "\(devices.count)", valueIsNumber: true) {
                        Image(systemName: "chevron.down")
                            .dsGlyph(DS.Glyph.sm)
                            .foregroundColor(DS.Color.textTertiary)
                            .rotationEffect(.degrees(devicesOpen ? 180 : 0))
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityValue(devicesOpen ? L10n.t("ظاهرة", "Shown") : L10n.t("مطويّة", "Collapsed"))
            }
        } else {
            AdminMemberRow(icon: "iphone.gen3", tint: DS.Color.sea, title: title, value: AdminStoreHealthText.placeholder)
                .accessibilityValue(AdminStoreHealthText.loading)
        }
    }

    private func deviceRow(_ device: NotificationViewModel.LinkedDevice) -> some View {
        AdminMemberRow(icon: device.platform.lowercased() == "android" ? "candybarphone" : "iphone.gen3",
                       tint: DS.Color.info, title: device.displayName,
                       subtitle: L10n.t("آخر استخدام: ", "Last used: ") + AdminMemberSheetFacts.dateText(iso: device.updatedAt),
                       busy: busy == AdminMemberConfirm.signOut(device).id) {
            if canSignOutDevices {
                AdminPillButton(title: L10n.t("تسجيل خروج", "Sign out"), style: .reject) { confirm = .signOut(device) }
                    .accessibilityLabel(L10n.t("تسجيل خروج \(device.displayName)", "Sign out \(device.displayName)"))
                    .accessibilityHint(L10n.t("يسأل قبل الخروج", "Asks first"))
            }
        }
    }

    /// آخر صفّ في الورقة: أحمر، بلا سهم، ويسأل قبل الحذف (spec A.6/A.14)
    private var deleteRow: some View {
        AdminMemberTapRow(hint: L10n.t("يسأل قبل الحذف", "Asks before deleting"), action: { confirm = .delete }) {
            AdminMemberRow(icon: "trash.fill", title: L10n.t("حذف العضو نهائياً", "Delete member permanently"),
                           destructive: true, busy: busy == AdminMemberConfirm.delete.id)
        }
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

// MARK: - كتلة العنوان

/// الصورة ٦٦، الاسم ١٧ شبه عريض (سطران)، سطر الحالة ١٣، والفرع (والدور الإداري) ١٣ — بلا شرائح. الحالة «جارٍ التحقق»
/// هيكلاً رمادياً حتى تصل (spec C.10: التحميل = هيكل كتلة العنوان)
struct AdminMemberTitleBlock: View {
    let member: FamilyMember
    let facts: AdminMemberSheetFacts
    let branch: String?

    private var name: String {
        member.displayFullName.isEmpty ? L10n.t("بلا اسم", "No name") : member.displayFullName
    }

    /// «فرع جاسم · مراقب» — الدور لأعضاء الإدارة فقط
    private var secondLine: String? {
        let role: String? = [.owner, .admin, .monitor, .supervisor].contains(member.role) ? member.roleName : nil
        let parts = [branch, role].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            // لا صور للإناث في التطبيق (طلب المالك ٢٠٢٦-١١-٢٤) — الحرف الأول بدلها
            DSMemberAvatar(name: member.fullName, avatarUrl: member.isFemale ? nil : member.avatarUrl,
                           size: DS.Icon.avatarLarge, roleColor: member.roleColor)
                .grayscale(member.isDeceased == true ? 1 : 0)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: name)
                    .dsFont(.statValue)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: facts.statusLine)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .redacted(reason: facts.status == nil ? .placeholder : [])
                if let secondLine {
                    Text(verbatim: secondLine)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// زرّ دائري بعنوان تحته (صفّ خرائط Google): دائرة ٤٨ كحلية خفيفة ورمز كحلي، العنوان ١٣، اللمس بعرض ٦٦
struct AdminMemberRoundAction: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Spacing.xsm) {
                Image(dsSymbol: icon)
                    .dsGlyph(DS.Glyph.lg, weight: .medium)
                    .foregroundColor(DS.Color.primary)
                    .frame(width: DSBox.buttonHeightLarge, height: DSBox.buttonHeightLarge)
                    .background(Circle().fill(DS.Color.primary.opacity(DS.Opacity.tintFill)))
                Text(title)
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: DS.Hub.quickWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - «أكمل الناقص»

/// عنوان كل نقص/مشكلة وفعل إصلاحه القصير («تاريخ الميلاد ناقص — أضف»)
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

/// صفّ نقص: رمز تنبيه + النص + حبّة الفعل — الصفّ كله لمسة واحدة (spec A.7)
struct AdminMemberFixRow: View {
    let title: String
    let verb: String
    var busy: Bool = false
    let action: () -> Void

    /// الفاصل يبدأ من النص (بعد الرمز)
    static let dividerInset: CGFloat = DS.Icon.section + DS.Spacing.md

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .dsGlyph(DS.Glyph.md, weight: .medium)
                    .foregroundColor(DS.Color.warning)
                    .frame(width: DS.Icon.section)
                    .accessibilityHidden(true)
                Text(title)
                    .dsFont(.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DS.Spacing.sm)
                if busy {
                    ProgressView().scaleEffect(DS.Spinner.chipScale)
                } else {
                    AdminPillLabel(title: verb, style: .soft)
                }
            }
            .padding(.vertical, DS.Spacing.xsm)
            .frame(minHeight: DS.Hub.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(AdminRowPressStyle())
        .disabled(busy)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(verb))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - «البيانات»

struct AdminMemberDataSection: View {
    let member: FamilyMember
    let facts: AdminMemberSheetFacts
    let canEdit: Bool
    let open: (AdminMemberBox) -> Void
    let openTall: (AdminMemberTallBox) -> Void
    @EnvironmentObject private var authVM: AuthViewModel
    /// الطلب المعلّق وإعداد التذكير — صفّ «تنبيه لإضافة صورة»/«طلب تغيير الصورة» يظهر ويختفي معهما
    @ObservedObject private var photoRequests = PhotoChangeRequestStore.shared
    @ObservedObject private var photoConfig = AppConfigValues.shared

    private var genderText: String {
        switch (member.gender ?? "").lowercased() {
        case "male": return L10n.t("ذكر", "Male")
        case "female": return L10n.t("أنثى", "Female")
        default: return L10n.t("غير محدّد", "Not set")
        }
    }

    private var photoText: String {
        if !AdminMemberFacts.isBlank(member.avatarUrl) { return L10n.t("موجودة", "Added") }
        return member.avatarUnavailable == true ? L10n.t("لا توجد صورة لهذا العضو", "No photo exists") : L10n.t("بلا صورة", "No photo")
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
        let hasPhoto = !AdminMemberFacts.isBlank(m.avatarUrl)
        let bio = m.bio?.count ?? 0
        // «نبّهه يضيف صورة» / «طلب تغيير الصورة» / الطلب المعلّق (P1، `PhotoNudgeSheetRow` — المنطق PhotoNudgeLogic.swift)
        let photoRequest = canEdit && PhotoNudgeSheetRow.isVisible(member: m, hasLogin: facts.account != nil, authVM: authVM)
        return VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: L10n.t("البيانات", "Details"))
            AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                row(AdminMemberRow(icon: "textformat", tint: DS.Color.primary, title: L10n.t("الاسم", "Name"),
                                   value: m.displayFullName.isEmpty ? L10n.t("بلا اسم", "No name") : m.displayFullName,
                                   wrapsValue: true),
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
                                       subtitle: incomplete ? AdminMemberGap.deathIncomplete.title : ageAtDeathLine, value: value),
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
                // لا صور للإناث في التطبيق (طلب المالك ٢٠٢٦-١١-٢٤) — المصغّرة للذكور فقط
                row(AdminMemberRow(icon: "photo.fill", tint: DS.Color.sadu, title: L10n.t("الصورة", "Photo"),
                                   value: photoText, thumbnail: hasPhoto && !m.isFemale ? m.avatarUrl : nil),
                    verb: hasPhoto ? L10n.t("تغيير", "Change") : L10n.t("إضافة", "Add")) { open(.photo(m)) }
                if photoRequest {
                    PhotoNudgeSheetRow(member: m, hasLogin: facts.account != nil, onAskChange: { open(.photoRequest(m)) })
                }
                row(AdminMemberRow(icon: "doc.text.fill", tint: DS.Color.accent, title: L10n.t("السيرة", "Biography"),
                                   subtitle: latestBioLine, value: bioCountText(bio)),
                    verb: bio == 0 ? L10n.t("إضافة", "Add") : L10n.t("تعديل", "Edit")) { openTall(.editAll(m)) }
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
    let busy: String?
    let open: (AdminMemberTallBox) -> Void
    let ask: (AdminMemberConfirm) -> Void
    let openWomen: () -> Void

    var body: some View {
        let kids = facts.children
        let names = kids.prefix(4).map(\.firstName).joined(separator: "، ") + (kids.count > 4 ? "…" : "")
        return VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: L10n.t("النسب", "Lineage"))
            AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                if !facts.isFamilyRoot {
                    let father = AdminMemberRow(icon: "arrow.triangle.branch", tint: DS.Color.palm, title: L10n.t("الأب", "Father"),
                                                value: facts.father?.displayFullName ?? AdminMemberProblem.orphan.title,
                                                wrapsValue: true)
                    if canEdit {
                        AdminMemberTapRow(hint: facts.father == nil ? L10n.t("ربط", "Link") : L10n.t("تغيير", "Change"),
                                          action: { open(.father(member)) }) { father.chevron(true) }
                    } else {
                        father
                    }
                }
                let children = AdminMemberRow(icon: "person.2.fill", tint: DS.Color.palm, title: L10n.t("الأبناء", "Children"),
                                              subtitle: kids.isEmpty ? L10n.t("لا أبناء مسجّلون", "No children recorded") : names,
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

/// صفّ معلومة: `[مربّع ٣٠ ممتلئ][العنوان ١٥ / سطر ١٣ رمادي]…[القيمة ١٥ رمادية | حبّة | مفتاح][سهم إن فتح شيئاً]`.
/// ٤٤ لسطر و٥٦ لسطرين. القيمة الطويلة (الاسم) تلتفّ بجانب عنوان قصير، والقصيرة لا تلتفّ؛ من أحجام إمكانية الوصول
/// القيمة تحت العنوان. الحذف (`destructive`): العنوان أحمر والمربّع رمز أحمر على ١٢٪
struct AdminMemberRow: View {
    let icon: String
    var tint: Color = DS.Color.primary
    let title: String
    var subtitle: String? = nil
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

    init(icon: String, tint: Color = DS.Color.primary, title: String, subtitle: String? = nil, value: String? = nil,
         valueIsNumber: Bool = false, wrapsValue: Bool = false, thumbnail: String? = nil, destructive: Bool = false,
         showsChevron: Bool = false, busy: Bool = false) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
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
                    .dsFont(.body)
                    .foregroundColor(destructive ? DS.Color.error : DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
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
            .foregroundColor(DS.Color.textSecondary)
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

/// صفّ في بطاقات الورقة بزرّ كبسولة (يستعمله `PhotoChangeRequestSheetRow` في «البيانات»): نفس هيئة `AdminMemberRow` —
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
                    AdminPillButton(title: action.0, style: .soft, action: action.1)
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
