import SwiftUI
import Supabase

// MARK: - كرت العضو v3 «ب» «مجموعات تنطوي» (الوحدة V3، اختيار المالك ٢٠٢٦-١١-٢٦؛ قبلها «أ3» V2-3 وF4 وU13)
//
// ورقة طويلة (`dsTallBox`) تتمرّر بلا تبويبات، من الأعلى:
//   «إغلاق» ذهبي ثابت (٤٤) ← الرأس الكحلي: الصورة، الاسم كاملاً يلتفّ، شارات الحال (عضو مسجّل ✓ · فرع · «ابن بنت»/«من خارج
//   العائلة» · الدور)، وأزرار بلا إطار — رمز ذهبي ٢٢ واسمه تحته ومساحة لمس ٤٤: «الملف الكامل» · «في الشجرة» (لمن يصل إليه
//   الرأس الأول، لا فوق مربّع) · «اتصال» · «واتساب» (للرقم الظاهر لك فقط)؛ ٢×٢ مع الخط الكبير
//   ← الرقاقات: الناقص بكلمة صفّه («تاريخ الميلاد غير مسجّل · أضف ‹») ورقاقة الطلبات («طلبان عنه ‹» — قفز فقط)
//   ← «العضو» ثلاث مجموعات تنطوي (`AdminMemberCardGroups.swift`): «البيانات» · «العائلة» (`AdminMemberCardFamily.swift`) ·
//   «الحساب» (حقائق) — مفتوحة أول مرة، تتذكّر اختيار كل مشاهد، وما فيه طلب أو «تحت التعديل» لا ينطوي
//   ← «إجراءات الإدارة» بطاقة منفصلة بشريط عنوان كحلي (لا تُرسم على ورقتك): «طلبات عنه · N» (`AdminMemberCardRequests.swift`
//   — موافقة/رفض بنداء «الوارد» نفسه، وما في مرحلة موافقة «فتح في الوارد» وحده) ثم رقم الهاتف، الصورة، التسجيل، الأجهزة،
//   الإيقاف، منع الرقم، و«حذف العضو نهائياً» آخرها بالأحمر ← سطر القفل ← «‹ السابق · N من M · التالي ›» داخل القائمة فقط.
// مربّعات «العائلة» والجنس (`AdminMemberCardBoxes.swift`): الزوجات/الزوج · تغيير الجنس (`move_child_gender`) · الأبناء والبنات ·
//   «صلته بالعائلة» · وتأكيد الإخفاء و«تراجع» بعده — كلها بنداءات السيرفر الموجودة، وما لا نداء له معطّل «يحتاج تحديث السيرفر».
// كل أمر هو نفسه السابق بصلاحيته ونداء سيرفره، والمربّعات الموجودة: الميلاد `EditBirthDateSheet` · الجنس بلا قيمة
//   `EditGenderSheet` · الصورة `EditMemberPhotoSheet` · الوفاة `EditDeathDateSheet`/`DeceasedDateBox` · الأب `LinkFatherSheet` ·
//   الرقم `PendingMemberPhoneSheet(activateOnSave:)` · كل البيانات والسيرة `AdminMemberDetailSheet(showsAccount: false)` ·
//   «تسجيل في التطبيق» `activateAccount` · الإيقاف `setMemberSuspension` (`canFreezeMembers`) · الأجهزة
//   `fetchDevicesForMember`/`removeDeviceByAdmin` (`canManageDevices`) · الإخفاء `is_hidden_from_tree` (وعقدة شجرة النساء
//   `WomenStore.update`) · مسح الرقم `clearPhoneNumber` · الحذف `deleteMember` (`canDeleteMembers`، لا المالك ولا النفس).
// «في الشجرة»: `.requestMemberInTree` ← `MainTabView`/`TreeFocusRequest` (V33/V36). «منع الرقم» بيته «التسجيل والمنع» (T4).
// الورقة تقبل عقدة شجرة النساء أيضاً (`ids` من `women_members`): البيانات للاطلاع، و«العائلة» بمربّعاتها. صفوف النساء في
//   «العائلة» (F5) تفتح مربّع المرأة نفسه (`WomanDetailSheet`) كما كانت، وابن البنت هذه الورقة.
// كل أمر = صلاحية الدور × «يعدّل» في جدول السيرفر لقسم «العائلة» (`adminCanEdit(.family)`). تجربة الأدوار (T0): كل كتابة تمرّ
//   بـ`DebugAdminProbe.dryRun`، والمربّعات التي تحفظ في ملفات أخرى لا تُفتح أثناءها.
// حارس المكدس: الرأس والرقاقات والمجموعات والبطاقة أنواع مستقلة في `AnyView`، والمربّعات والتأكيدات في مُعدِّلاتها المستقلة.
// `AdminMemberSheet(ids:start:)` ثابت.

struct AdminMemberSheet: View {
    let ids: [UUID]
    /// F4 (V8): الورقة فوق مربّع آخر (مربّع الطلب، مسار المرسل) — «في الشجرة» ورابط شجرة النساء لا يظهران (الإغلاق
    /// يُرجع للمربّع لا للتبويبات، فكانت الشجرة تُفتح خلفه)
    let inBox: Bool
    @State private var position: Int
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    /// صفّ الصورة في «إجراءات الإدارة» يتبع الطلب المفتوح (يظهر ويختفي معه)
    @ObservedObject private var photoStore = PhotoChangeRequestStore.shared
    /// شجرة النساء وصفّ ابن البنت — «العائلة»
    @ObservedObject private var family = AdminMemberCardFamilyStore.shared
    @ObservedObject private var daughterSons = DaughterSonsIndex.shared
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
    /// رأس شجرة العائلة الأول (`FamilyTreeLayoutEngine.index`) — «في الشجرة» لمن يصل إليه فقط (V33)
    @State private var treeRoot: UUID?
    /// صفّ الصورة يرسل الآن — «السابق/التالي» معطّلان حتى ينتهي (V27)
    @State private var photoWorking = false

    @State private var box: AdminMemberBox?
    @State private var tall: AdminMemberTallBox?
    @State private var familyBox: AdminMemberFamilyBox?
    @State private var bans: AdminMemberBanPrefill?
    @State private var confirm: AdminMemberConfirm?
    /// عقدة شجرة النساء التي يخفيها/يظهرها التأكيد (ابن البنت، المرأة) — nil = ملفه في شجرة الرجال
    @State private var visibilityNode: FamilyMember?
    /// «أُخفي من الشجرة · تراجع» لثوانٍ بعد الإخفاء
    @State private var undoHidden: UUID?
    /// سبب الإيقاف (اختياري) — يصل للعضو ويظهر في شاشة الحساب الموقوف
    @State private var suspendReason = ""
    @State private var busy: String?
    @State private var failure: String?
    /// قفزة إلى «طلبات عنه» (الرقاقة وشارات «طلب»)
    @State private var scrollTarget: String?
    /// م٦: «تغيير الجنس» يُنشئ سجلاً جديداً في الشجرة الأخرى — الكرت يتبع المعرّف الجديد (القديم ← الجديد)
    @State private var movedIds: [UUID: UUID] = [:]
    /// ت-ج٧: آخر جلب لمخازن «الوارد» من هذا الكرت — «التالي» لا يعيده قبل `requestsRefreshInterval`
    @State private var requestsFetchedAt: Date?

    init(ids: [UUID], start: Int, inBox: Bool = false) {
        self.ids = ids
        self.inBox = inBox
        _position = State(initialValue: AdminMemberSheetLogic.clampedStart(start, count: ids.count))
    }

    /// معرّف العضو المعروض الآن — كل نتيجة غير متزامنة تُكتب فقط إن بقي هو نفسه (V27). بعد نقل الجنس: سجلّه الجديد (م٦)
    private var currentId: UUID? {
        ids.indices.contains(position) ? AdminMemberCardLogic.resolved(ids[position], moved: movedIds) : nil
    }

    /// ملفه في شجرة الرجال، وإلا عقدته في شجرة النساء (امرأة بلا حساب، زوج من خارج العائلة)
    private var member: FamilyMember? {
        guard let currentId else { return nil }
        return memberVM.member(byId: currentId) ?? family.node(currentId)
    }

    private var isProfile: Bool { currentId.flatMap { memberVM.member(byId: $0) } != nil }

    // MARK: الصلاحيات — صلاحية الدور × «يعدّل» في جدول «العائلة»

    private var familyEdit: Bool { authVM.adminCanEdit(.family) }
    private var canEdit: Bool { authVM.canEditMembers && familyEdit }
    private var canManageChildren: Bool { canEdit && authVM.currentUser?.role != .monitor }
    private var canFreeze: Bool { authVM.canFreezeMembers && familyEdit }
    private var canBan: Bool { authVM.canManageBannedPhones && familyEdit }
    private var canSignOutDevices: Bool { authVM.canManageDevices && familyEdit }
    private var canDelete: Bool { authVM.canDeleteMembers && familyEdit }
    /// «طلبات عنه» لمن يقرّر طلبات الشجرة (مخازن «الوارد» تُجلب له وحده)
    private var seesRequests: Bool { authVM.canModerateTree }

    /// ح٢: أوامر العائلة (الجنس، الزوجات/الزوج، الأبناء، الظهور، الصلة، الأب) لا تعمل على ورقتك — «البيانات» كما هي
    private func familyAdmin(_ m: FamilyMember) -> Bool {
        AdminMemberCardLogic.familyAdmin(canEdit: canEdit, memberId: m.id, linkedUserId: WomenStore.linkedUserByWoman[m.id],
                                         viewerId: authVM.currentUser?.id)
    }

    /// م-ج١: ورقتك = ملفك، أو عقدتك في شجرة النساء («نساء العائلة» تفتح الكرت بمعرّف العقدة المربوطة بحسابك)
    private func isSelf(_ m: FamilyMember) -> Bool {
        AdminMemberCardLogic.isSelf(memberId: m.id, linkedUserId: WomenStore.linkedUserByWoman[m.id],
                                    viewerId: authVM.currentUser?.id)
    }

    /// لا المالك ولا أنت — وحده يقبل الإيقاف ومنع الرقم والحذف
    private func isOther(_ m: FamilyMember) -> Bool {
        AdminMemberSheetLogic.isOther(isSelf: isSelf(m), memberIsOwner: m.role == .owner)
    }

    var body: some View {
        page
            .safeAreaInset(edge: .bottom, spacing: 0) { stepBar }
            .overlay(alignment: .bottom) { undoBar }
            .background(AdminMemberSheetBackdrop(band: member != nil))
            .modifier(AdminMemberSheetBoxes(box: $box, tall: $tall, familyBox: $familyBox, bans: $bans,
                                            onBansClosed: bansClosed, branch: branchTitle,
                                            isProfile: isProfile, openAfter: openAfter,
                                            onMoved: { old, new in movedIds[old] = new },
                                            openInbox: { request in
                                                familyBox = nil
                                                MemberPendingRequestsLink.open(request) { dismiss() }
                                            }))
            .modifier(AdminMemberSheetAlerts(confirm: $confirm, failure: $failure, suspendReason: $suspendReason,
                                             female: member?.isFemale == true, run: run))
            .onAppear { rebuildTree() }
            .onChange(of: memberVM.membersVersion) { _ in rebuildTree() }
            .task(id: currentId) { await refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .debugStackProbe("AdminMemberSheet")
    }

    // MARK: الهيكل

    /// «إغلاق» ثابت فوق على الكحلي، والرأس والأقسام تتمرّر تحته
    private var page: AnyView {
        AnyView(VStack(spacing: 0) {
            AdminMemberCloseBar { dismiss() }
                .zIndex(1)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    content
                        .id(Self.topAnchor)
                }
                .onChange(of: position) { _ in
                    devicesOpen = false
                    undoHidden = nil
                    proxy.scrollTo(Self.topAnchor, anchor: .top)
                }
                .onChange(of: scrollTarget) { target in
                    guard let target else { return }
                    withAnimation(DS.Anim.snappy) { proxy.scrollTo(target, anchor: .top) }
                    scrollTarget = nil
                }
            }
        })
    }

    private static let topAnchor = "member-sheet-top"

    private var branchTitle: String? {
        guard let m = member else { return nil }
        return facts(m).branchTitle(appSettingsVM)
    }

    private func facts(_ m: FamilyMember) -> AdminMemberSheetFacts {
        AdminMemberSheetFacts(member: m, all: memberVM.allMembers, byId: memberVM.member(byId:), tree: tree,
                              account: isProfile ? accounts.info(m.id) : nil, accountsReady: accounts.loaded,
                              liveStatus: liveStatus, daughterSon: daughterSons.contains(m.id))
    }

    private func familyFacts(_ m: FamilyMember) -> AdminMemberCardFamily {
        AdminMemberCardFamily.make(m, isProfile: isProfile, memberVM: memberVM, store: family)
    }

    private var content: AnyView {
        guard let m = member else {
            return AnyView(DSEmptyView(L10n.t("العضو غير موجود", "Member not found"),
                                       message: L10n.t("ربما حُذف أو تغيّر، يرجى العودة إلى القائمة", "It may have been deleted — go back to the list"),
                                       style: .card)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.lg))
        }
        let facts = facts(m)
        let fam = familyFacts(m)
        let phone = m.dsVisiblePhone(viewerId: authVM.currentUser?.id, viewerCanModerate: authVM.canModerate)
        let actions = AdminMemberCardLogic.headerActions(canEdit: canEdit, isProfile: isProfile, reachable: drawnInTree(m),
                                                         inBox: inBox, isDeceased: m.isDeceased == true, visiblePhone: phone)
        return AnyView(VStack(spacing: 0) {
            AnyView(AdminMemberSheetHeader(member: m, facts: facts, branch: facts.branchTitle(appSettingsVM),
                                           lineageTag: fam.headerTag, actions: actions) { perform($0, m, phone: phone) })
            AnyView(sections(m, facts, fam))
        })
    }

    /// الطلبات المعلّقة عنه (لمن يقرّر طلبات الشجرة) — لا على ورقتك (م١: بطاقة «إجراءات الإدارة» لا تُرسم عليها، فالرقاقة
    /// والشارات لا تقفز إلى شيء)
    private func requests(_ m: FamilyMember, _ fam: AdminMemberCardFamily) -> [AdminRequest] {
        guard AdminMemberCardLogic.showsRequests(isSelf: isSelf(m), seesRequests: seesRequests) else { return [] }
        return AdminMemberCardRequests.about(m, nodeId: fam.nodeId, vm: adminRequestVM)
    }

    /// الصفوف «تحت التعديل» الآن (حفظ جارٍ من الورقة)
    private var pendingRows: Set<AdminCardRow> {
        switch busy {
        case AdminMemberConfirm.hide.id, AdminMemberConfirm.show.id: return [.visibility]
        case AdminMemberConfirm.clearPhone.id, AdminMemberConfirm.unlinkPhone.id: return [.phone]
        default: return []
        }
    }

    /// تحت الرأس: الرقاقات ← «العضو» (ثلاث مجموعات) ← «إجراءات الإدارة» (بطاقة منفصلة) ← سطر القفل
    private func sections(_ m: FamilyMember, _ facts: AdminMemberSheetFacts, _ fam: AdminMemberCardFamily) -> some View {
        let chips = AdminMemberSheetLogic.missingChips(
            gaps: facts.gaps.compactMap { AdminMemberSheetLogic.Missing(rawValue: $0.rawValue) },
            problems: facts.problems.compactMap { AdminMemberSheetLogic.Missing(rawValue: $0.rawValue) },
            canEdit: canEdit && isProfile, ownCard: isSelf(m))
        let living = m.isDeceased != true
        let other = isOther(m)
        let about = requests(m, fam)
        let requestRows = AdminMemberCardLogic.badgeRows(about.map(AdminMemberCardRequests.key))
        let phone = (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // الرقم المخفي يُرفض قبل استعمال المطبَّع (المنطق في `AdminMemberSheetLogic`)
        let normalized = Self.storagePhone(phone)
        let banPrefill = AdminMemberSheetLogic.banPrefill(phone, normalize: { _ in normalized })
        let commands = AdminMemberSheetLogic.accountCommands(isOther: other, canFreeze: canFreeze, canBan: canBan,
                                                             banPrefill: banPrefill, canDelete: canDelete)
        let lock = AdminMemberSheetLogic.lockNote(isSelf: isSelf(m), memberIsOwner: m.role == .owner, isDeceased: !living,
                                                  viewerCanAct: canEdit || canFreeze || canBan || canDelete)
        let showsDevices = authVM.canViewSystemSettings && facts.status != .treeOnly && isProfile
        let hasLogin = facts.account != nil
        let card = AdminMemberSheetLogic.adminCard(
            isSelf: isSelf(m), living: living,
            photo: isProfile && AdminMemberPhotoActions.state(member: m, hasLogin: hasLogin, viewer: .init(authVM: authVM)) != .hidden,
            register: isProfile && AdminMemberAccountSection.canRegister(member: m, facts: facts, canEdit: canEdit,
                                                                         isOther: other, liveStatus: liveStatus),
            devices: canSignOutDevices && showsDevices && !devicesFailed && (devices?.isEmpty == false),
            commands: isProfile ? commands : .init(suspend: false, ban: false, delete: false),
            phone: canEdit && isProfile, requests: seesRequests)
        let handlers = AdminMemberCardHandlers(
            openBox: { openBox($0) }, openTall: { openTall($0) }, openFamily: { familyBox = $0 },
            jumpToRequest: { row in
                scrollTarget = about.first { AdminMemberCardRequests.row($0) == row }
                    .map { AdminMemberCardRequests.anchor($0.id) } ?? AdminMemberCardRequests.stripAnchor
            },
            setHidden: { hidden in askVisibility(hidden: hidden, node: fam.visibilityNode) })
        let viewer = authVM.currentUser?.id
        let familyAdmin = familyAdmin(m)
        let data = AnyView(AdminMemberDataGroup(member: m, isProfile: isProfile, canEdit: canEdit,
                                                familyAdmin: familyAdmin, requestRows: requestRows,
                                                pendingRows: pendingRows, viewer: viewer, handlers: handlers))
        let familyGroup = AnyView(AdminMemberFamilyGroup(member: m, family: fam, canEdit: familyAdmin,
                                                         canManageChildren: canManageChildren && familyAdmin,
                                                         branch: facts.branchTitle(appSettingsVM), requestRows: requestRows,
                                                         pendingRows: pendingRows, viewer: viewer,
                                                         byId: memberVM.member(byId:), handlers: handlers))
        let account: AnyView? = living && isProfile ? accountGroup(m, facts, requestRows: requestRows,
                                                                    showsDevices: showsDevices, handlers: handlers) : nil
        let admin: AnyView? = card.map { adminSection(m, facts, card: $0, banPrefill: banPrefill, requests: about) }
        return VStack(alignment: .leading, spacing: DS.Hub.memberSectionGap) {
            if !chips.isEmpty || !about.isEmpty {
                AnyView(VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    if !about.isEmpty {
                        AdminMemberRequestsChip(count: about.count, female: m.isFemale) {
                            scrollTarget = AdminMemberCardRequests.stripAnchor
                        }
                    }
                    if !chips.isEmpty {
                        AdminMemberMissingChips(items: chips, busy: busy) { fix($0, m) }
                    }
                })
            }
            VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
                AdminMemberSectionTitle(title: L10n.t("العضو", "Member"), bar: DS.Color.primary)
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    data
                    familyGroup
                    if let account { account }
                }
            }
            if let admin { admin }
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

    /// «الحساب» حقائق — الأجهزة للاطلاع لمن يراها ولا يسجّل خروجها (كما كانت)
    private func accountGroup(_ m: FamilyMember, _ facts: AdminMemberSheetFacts, requestRows: Set<AdminCardRow>,
                              showsDevices: Bool, handlers: AdminMemberCardHandlers) -> AnyView {
        let devicesView: AnyView? = showsDevices && !canSignOutDevices
            ? AnyView(AdminMemberDevicesFacts(devices: devices, failed: devicesFailed, open: $devicesOpen,
                                              retry: { Task { await loadDevices(m) } }))
            : nil
        return AnyView(AdminMemberAccountGroup(member: m, facts: facts, requestRows: requestRows, pendingRows: pendingRows,
                                               viewer: authVM.currentUser?.id, jumpToRequest: handlers.jumpToRequest,
                                               devices: devicesView)
            .id(m.id))
    }

    /// «إجراءات الإدارة» — `.id` يبدأ حالة صفّ الصورة من جديد مع كل عضو (V29)
    private func adminSection(_ m: FamilyMember, _ facts: AdminMemberSheetFacts, card: AdminMemberSheetLogic.AdminCard,
                              banPrefill: String?, requests: [AdminRequest]) -> AnyView {
        let strip: AnyView? = AdminMemberCardLogic.showsRequests(isSelf: isSelf(m), seesRequests: seesRequests)
            ? AnyView(AdminMemberRequestsStrip(member: m, requests: requests, byId: memberVM.member(byId:)) { request in
                MemberPendingRequestsLink.open(request) { dismiss() }
            })
            : nil
        return AnyView(AdminMemberAdminSection(
            member: m, facts: facts, card: card, banPrefill: banPrefill, ban: ban, devices: devices,
            noDevices: noDevices(facts), busy: busy, ask: { ask($0) }, openBox: { openBox($0) },
            openBans: { bans = AdminMemberBanPrefill(phone: $0) }, photoWorking: $photoWorking, requests: strip)
            .id(m.id))
    }

    /// يُرسم في شجرة العائلة: سلسلة آبائه حتى الرأس الأول وكلهم مرسومون (V33)
    private func drawnInTree(_ m: FamilyMember) -> Bool {
        AdminMemberSheetLogic.reachable(m.id, root: treeRoot,
                                        father: { memberVM.member(byId: $0)?.fatherId },
                                        drawable: { memberVM.member(byId: $0)?.isCountable == true })
    }

    private func rebuildTree() {
        tree = AdminMemberFacts.TreeContext(memberVM.allMembers)
        treeRoot = FamilyTreeLayoutEngine.index(memberVM.allMembers).roots.first?.id
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

    /// «في الشجرة»: تغلق الورقة، وتبويب الشجرة يفتح على شجرة العائلة والعضو في وسطها بمساره مفتوحاً ومظلّلاً. الطلب
    /// ينتظر في `TreeFocusRequest` حتى تجهز شجرة العائلة (V36) — لا مهلة ثابتة
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
        case .hidden, .dupPhone:
            visibilityNode = nil
            confirm = AdminMemberFix.confirm(p)
        }
    }

    /// تأكيد من «الحساب»: الإيقاف ورفعه يبدآن بسبب فارغ
    private func ask(_ action: AdminMemberConfirm) {
        if action == .suspend || action == .unsuspend { suspendReason = "" }
        if action == .hide || action == .show { visibilityNode = nil }
        confirm = action
    }

    /// مفتاح «الظهور»: الإخفاء يسأل أولاً (وبعده «تراجع»)، والإظهار مباشرة — بالنداء نفسه
    private func askVisibility(hidden: Bool, node: FamilyMember?) {
        visibilityNode = node
        if hidden { confirm = .hide } else { run(.show) }
    }

    // MARK: «تراجع» بعد الإخفاء (لثوانٍ — `DSMotion.undoWindow`)

    @ViewBuilder
    private var undoBar: some View {
        if let id = undoHidden, id == currentId {
            AdminMemberUndoBar(text: member?.isFemale == true ? L10n.t("أُخفيت من الشجرة", "Hidden from the tree")
                                                              : L10n.t("أُخفي من الشجرة", "Hidden from the tree")) {
                undoHidden = nil
                run(.show)
            }
            .padding(.bottom, AdminMemberSheetLogic.showsStepBar(count: ids.count) ? DS.Icon.tapTarget + DS.Spacing.md : DS.Spacing.md)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: id) {
                try? await Task.sleep(nanoseconds: UInt64(DSMotion.undoWindow * 1_000_000_000))
                if !Task.isCancelled, undoHidden == id { withAnimation(DS.Anim.snappy) { undoHidden = nil } }
            }
        }
    }

    /// مربّع يفتح آخر بعد إغلاقه (الأبناء ← «إضافة ابن / بنت»، الصلة ← ربط الأب) — مهلة التسليم بين المربّعات
    private func openAfter(_ next: AdminMemberAfterBox) {
        familyBox = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.boxHandoff) {
            switch next {
            case .addChild(let m): openBox(.addChild(m))
            case .father(let m): openTall(.father(m))
            }
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
        // أثناء أمر جارٍ لا تنقّل — نتيجته تخصّ هذا العضو (V27)
        let enabled = AdminMemberSheetLogic.canStep(next: next, position: position, count: ids.count,
                                                    busy: busy != nil || photoWorking)
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

    /// صفحة «التسجيل والمنع» أُغلقت: المنع يوقف الحساب أيضاً — نعيد قراءة الحالة والمنع
    private func bansClosed() {
        guard let m = member else { return }
        Task {
            await refreshBan(m)
            let status = await memberVM.fetchMemberStatus(memberId: m.id)
            if let status, currentId == m.id { liveStatus = status }
        }
    }

    /// `KuwaitPhone.normalizedForStorage` للرقم كما هو محفوظ: ٨ أرقام كويتية أو «+رمز…»
    private static func storagePhone(_ raw: String) -> String? {
        let parts = KuwaitPhone.detectCountryAndLocal(raw)
        return KuwaitPhone.normalizedForStorage(country: parts.country, rawLocalDigits: parts.localDigits)
    }

    /// كل نتيجة تُكتب فقط إن بقي العضو نفسه ولم يُلغَ الجلب (V27: «التالي» أثناءه كان يكتب حال العضو السابق وأجهزته
    /// على التالي — و«تسجيل خروج» يعمل على جهاز غيره)
    private func refresh() async {
        liveStatus = nil
        ban = nil
        devices = nil
        devicesFailed = false
        if !accounts.loaded { await accounts.refresh() }
        // «العائلة»: شجرة النساء وصفّ ابن البنت · «طلبات عنه»: مخازن «الوارد» نفسها (لمن يقرّر طلبات الشجرة)
        await family.refresh()
        if let id = currentId { await family.refreshLineage(id) }
        await daughterSons.refresh()
        // ت-ج٧: مرة كل ٢٠ ثانية من هذا الكرت — المخازن الفارغة (المعتاد) تتجاوز مهلتها، فكان «التالي» يجلبها كلها كل مرة
        if seesRequests, AdminMemberCardLogic.requestsRefreshDue(last: requestsFetchedAt, now: Date()) {
            requestsFetchedAt = Date()
            await refreshRequests()
        }
        guard let m = member else { return }
        // «طلب تغيير الصورة» المعلّق (السيرفر القديم: لا شيء) — وللمتوفى أيضاً: طلبه المفتوح يُلغى من هنا (V24)
        if authVM.canEditMembers { await PhotoChangeRequestStore.shared.refresh(memberId: m.id) }
        guard m.isDeceased != true, isCurrent(m) else { return }
        let status = await memberVM.fetchMemberStatus(memberId: m.id)
        guard isCurrent(m) else { return }
        if let status { liveStatus = status }
        await refreshBan(m)
        if authVM.canViewSystemSettings, isCurrent(m) {
            await loadDevices(m)
        }
    }

    private func isCurrent(_ m: FamilyMember) -> Bool { !Task.isCancelled && currentId == m.id }

    /// مخازن «الوارد» (بمهلها — لا جلب مكرّر)
    private func refreshRequests() async {
        async let tree: Void = adminRequestVM.fetchTreeEditRequests()
        async let deceased: Void = adminRequestVM.fetchDeceasedRequests()
        async let names: Void = adminRequestVM.fetchNameChangeRequests()
        async let photos: Void = adminRequestVM.fetchPhotoSuggestionRequests()
        async let kids: Void = adminRequestVM.fetchChildAddRequests()
        async let policy: Void = adminRequestVM.fetchPolicyRequests()
        // م٢: طلبات تغيير الرقم وصفوف الانضمام في مسار الموافقات — «فتح في الوارد» وحده
        async let phones: Void = adminRequestVM.fetchPhoneChangeRequests()
        async let joins: Void = adminRequestVM.fetchJoinApprovalRequests()
        _ = await (tree, deceased, names, photos, kids, policy, phones, joins)
    }

    /// تعذّر الجلب ≠ «لا أجهزة» — «تعذّر التحميل» بإعادة المحاولة بدل «لا تصله الإشعارات»
    private func loadDevices(_ m: FamilyMember) async {
        let list = await notificationVM.fetchDevicesForMember(m.id)
        guard currentId == m.id else { return }
        devicesFailed = list == nil
        devices = list ?? []
    }

    private func refreshBan(_ m: FamilyMember) async {
        guard canBan, !AdminMemberFacts.isBlank(m.phoneNumber) else { return }
        let found = await authVM.activeBan(for: (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        guard currentId == m.id else { return }
        ban = found
    }

    private func run(_ action: AdminMemberConfirm) {
        guard let m = member else { return }
        confirm = nil
        // تجربة دور: لا كتابة على السيرفر — نجاح مصطنع
        if DebugAdminProbe.dryRun("member sheet \(action.writeLabel) \(m.id)") {
            if action == .delete {
                DSMomentToast.show(L10n.t("تم الحذف", "Deleted"), moment: .success)
                dismiss()
            } else if action == .hide {
                withAnimation(DS.Anim.snappy) { undoHidden = m.id }
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
                let status = await memberVM.fetchMemberStatus(memberId: m.id)
                if let status, currentId == m.id { liveStatus = status }
            case .suspend, .unsuspend:
                let target: FamilyMember.MemberStatus = action == .suspend ? .frozen : .active
                ok = await memberVM.setMemberSuspension(memberId: m.id, suspend: action == .suspend,
                                                        reason: action == .suspend ? suspendReason : nil)
                if ok { if currentId == m.id { liveStatus = target } } else { failure = memberVM.errorMessage }
            case .hide, .show:
                let hidden = action == .hide
                if let node = visibilityNode {
                    // ابن البنت والمرأة: عقدتهما في شجرة النساء (نداء «إدارة السجل» نفسه)
                    ok = await AdminMemberSheet.setWomenHidden(node, hidden: hidden)
                    await family.refresh(force: true)
                } else {
                    ok = await AdminMemberSheet.setHidden(m.id, hidden: hidden, memberVM: memberVM)
                }
                if ok, hidden, currentId == m.id { withAnimation(DS.Anim.snappy) { undoHidden = m.id } }
                if ok, !hidden { undoHidden = nil }
            case .clearPhone, .unlinkPhone:
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

    /// عقدة شجرة النساء: إخفاؤها وإظهارها بنداء «إدارة السجل» في شجرة النساء (`WomenStore.update` بقيمها كما هي)
    static func setWomenHidden(_ node: FamilyMember, hidden: Bool) async -> Bool {
        do {
            try await WomenStore.update(id: node.id, fullName: node.fullName, isDeceased: node.isDeceased == true,
                                        deathDate: node.deathDate, birthDate: node.birthDate, gender: node.gender,
                                        isHidden: hidden)
            return true
        } catch {
            Log.error("Toggle women node hidden failed: \(error.localizedDescription)")
            return false
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

    /// «آخر دخول»: التاريخ، أو «لم يسجّل/تسجّل الدخول بعد» لمن لا حساب له (م١٠ — كان «غير مسجّل»)
    func lastSeenText(female: Bool) -> String {
        AdminMemberCardLogic.lastSeen(account?.lastSeen.map(Self.dateText), hasAccount: account != nil, female: female,
                                      arabic: L10n.isArabic)
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

/// ما إصلاحه تأكيد لا مربّع. عنوان الرقاقة وفعلها في `AdminMemberCardLogic.chipTitle/chipVerb` (م-ج٣: كلمة الصفّ نفسها)
@MainActor
enum AdminMemberFix {
    /// المشكلة التي إصلاحها كتابة بتأكيد (لا مربّع)
    static func confirm(_ problem: AdminMemberProblem) -> AdminMemberConfirm? {
        switch problem {
        case .hidden: return .show
        case .dupPhone: return .clearPhone
        default: return nil
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
    /// V3: «إضافة ابن / بنت» من مربّع «الأبناء والبنات» — المسار الموجود `AddSonByAdminSheet`
    case addChild(FamilyMember)

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
        case .addChild(let m): return "addChild-\(m.id)"
        }
    }

    /// المربّع يحفظ في ملف آخر (بلا `dryRun` داخله) — لا يُفتح أثناء تجربة دور. مربّعات `AdminMemberEditBoxes` تكتب تجريبياً
    var savesElsewhere: Bool {
        switch self {
        case .deathDate, .phone, .photoRequest, .addChild: return true
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

/// ما يُفتح بعد إغلاق مربّع «العائلة» (المربّع لا يفتح فوق نفسه)
enum AdminMemberAfterBox {
    case addChild(FamilyMember), father(FamilyMember)
}

/// صفحة «التسجيل والمنع» برقم العضو (مطبَّعاً) — مربّع طويل فوق الورقة، رجوعه يغلقه
struct AdminMemberBanPrefill: Identifiable {
    let phone: String
    var id: String { phone }
}

/// إجراء ينتظر التأكيد (spec A.14: العنوان سؤال بالفعل، سطر ما يحدث، والزرّ يكرّر الفعل)
enum AdminMemberConfirm: Identifiable, Equatable {
    case register, suspend, unsuspend, hide, show, clearPhone, delete
    /// V3: «مسح الرقم» من صفّ «رقم الهاتف» في «إجراءات الإدارة» (لمن لا حساب دخول له) — `clearPhoneNumber` نفسه
    case unlinkPhone
    case signOut(NotificationViewModel.LinkedDevice)

    var id: String {
        switch self {
        case .register: return "register"
        case .suspend: return "suspend"
        case .unsuspend: return "unsuspend"
        case .hide: return "hide"
        case .show: return "show"
        case .clearPhone: return "clearPhone"
        case .unlinkPhone: return "unlinkPhone"
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
        case .clearPhone, .unlinkPhone: return "clearPhoneNumber"
        case .delete: return "deleteMember"
        case .signOut(let d): return "removeDeviceByAdmin \(d.id)"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .suspend, .delete, .clearPhone, .unlinkPhone, .signOut, .hide: return true
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
        case .unlinkPhone: return L10n.t("مسح رقم الهاتف؟", "Clear the phone number?")
        case .delete: return L10n.t("حذف العضو نهائياً؟", "Delete the member permanently?")
        case .signOut: return L10n.t("تسجيل خروج الجهاز؟", "Sign out the device?")
        }
    }

    var button: String { button(female: false) }

    /// م١٠: «أخفِها» / «أظهِرها» على ورقة المرأة
    func button(female: Bool) -> String {
        switch self {
        case .register: return L10n.t("سجّله في التطبيق", "Register")
        case .suspend: return L10n.t("أوقف الحساب", "Suspend")
        case .unsuspend: return L10n.t("ارفع الإيقاف", "Lift")
        case .hide: return female ? L10n.t("أخفِها", "Hide") : L10n.t("أخفِه", "Hide")
        case .show: return female ? L10n.t("أظهِرها", "Show") : L10n.t("أظهِره", "Show")
        case .clearPhone, .unlinkPhone: return L10n.t("امسح الرقم", "Clear")
        case .delete: return L10n.t("احذف العضو", "Delete")
        case .signOut: return L10n.t("سجّل خروجه", "Sign out")
        }
    }

    var message: String { message(female: false) }

    func message(female: Bool) -> String {
        switch self {
        case .hide where female:
            return L10n.t("تُخفى عن كل الأعضاء في الشجرة والعدّ، وتبقى ظاهرة في الإدارة. تقدر تتراجع.",
                          "Hidden from every member in the tree and the counts; still shown in admin. You can undo.")
        case .show where female:
            return L10n.t("ستظهر في الشجرة من جديد.", "She'll show in the tree again.")
        case .register: return L10n.t("سيتمكن من الدخول للتطبيق برقمه.", "They'll be able to sign in with their number.")
        case .suspend: return L10n.t("لن يتمكن من الدخول للتطبيق حتى يُرفع الإيقاف، وبياناته محفوظة. يصله إشعار بالسبب إن كتبته.",
                                     "They can't use the app until the suspension is lifted; their data is kept. They're notified, with the reason if you add one.")
        case .unsuspend: return L10n.t("سيتمكن من الدخول للتطبيق مجدداً.", "They'll be able to use the app again.")
        case .hide: return L10n.t("يُخفى عن كل الأعضاء في الشجرة والعدّ، ويبقى ظاهراً في الإدارة. تقدر تتراجع.",
                                  "Hidden from every member in the tree and the counts; still shown in admin. You can undo.")
        case .show: return L10n.t("سيظهر في الشجرة من جديد.", "They'll show in the tree again.")
        case .clearPhone: return L10n.t("يُمسح الرقم من هذا العضو فقط (الرقم مكرر عند عضو آخر).", "Clears the number from this member only.")
        case .unlinkPhone: return L10n.t("يُمسح الرقم من بياناته (لا حساب دخول له). تقدر تضيفه من جديد.",
                                         "Clears the number from their record (no sign-in account). You can add it again.")
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
    @Binding var familyBox: AdminMemberFamilyBox?
    @Binding var bans: AdminMemberBanPrefill?
    let onBansClosed: () -> Void
    /// «فرع حسن» — لسطر «الحالي» في مربّع «صلته بالعائلة»
    let branch: String?
    let isProfile: Bool
    let openAfter: (AdminMemberAfterBox) -> Void
    /// م٦: نُقل بين الشجرتين — القديم ← الجديد (الكرت يتبعه)
    let onMoved: (UUID, UUID) -> Void
    /// م٣: قرار «الصلة بالعائلة» داخل مسار الموافقات — يُغلق الكرت ويفتح «الوارد» على الطلب
    let openInbox: (AdminRequest) -> Void
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var authVM: AuthViewModel

    func body(content: Content) -> some View {
        content
            .dsCenterBox(item: $box) { target in boxView(target) }
            .dsCenterBox(item: $familyBox) { target in familyView(target) }
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
        case .addChild(let m): return AnyView(AddSonByAdminSheet(parent: m).environmentObject(memberVM).environmentObject(authVM))
        }
    }

    /// مربّعات «العائلة» والجنس (V3) — كلٌّ نوع مستقل خلف `AnyView`
    private func familyView(_ target: AdminMemberFamilyBox) -> AnyView {
        let view: AnyView
        switch target {
        case .spouses(let m): view = AnyView(AdminMemberSpousesBox(member: m, isProfile: isProfile))
        case .gender(let m): view = AnyView(AdminMemberGenderMoveBox(member: m, isProfile: isProfile, onMoved: onMoved))
        case .children(let m): view = AnyView(AdminMemberChildrenBox(member: m) { openAfter(.addChild(m)) })
        case .lineage(let m): view = AnyView(AdminMemberLineageBox(member: m, isProfile: isProfile, branch: branch,
                                                                   linkFather: { openAfter(.father(m)) },
                                                                   openInbox: openInbox))
        case .mother(let m): view = AnyView(AdminMemberMotherBox(member: m, isProfile: isProfile))
        }
        return AnyView(view.environmentObject(memberVM).environmentObject(authVM).environmentObject(adminRequestVM))
    }

    private func tallView(_ target: AdminMemberTallBox) -> AnyView {
        switch target {
        case .father(let m): return AnyView(LinkFatherSheet(member: m, memberVM: memberVM))
        // م-ج١: على ورقتك الأب والأبناء للاطلاع في المحرّر الكامل أيضاً (الأوامر نفسها مقفولة في الكرت)
        case .editAll(let m):
            let own = AdminMemberCardLogic.isSelf(memberId: m.id, linkedUserId: WomenStore.linkedUserByWoman[m.id],
                                                  viewerId: authVM.currentUser?.id)
            return AnyView(AdminMemberDetailSheet(member: m, showsAccount: false, lineageLocked: own))
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
    /// م١٠: «أخفِها» على ورقة المرأة
    let female: Bool
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
                Button(action.button(female: female), role: action.isDestructive ? .destructive : nil) { run(action) }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { confirm = nil }
            } message: { action in
                Text(action.message(female: female))
            }
            .dsAlert(L10n.t("تعذّر التنفيذ", "Couldn't complete"),
                     isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button(L10n.t("حسناً", "OK")) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
    }
}
