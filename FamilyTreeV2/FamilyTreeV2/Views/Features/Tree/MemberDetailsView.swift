import SwiftUI

/// بطاقة العضو في الشجرة «أ» (اعتمدها المالك ٢٠٢٦-١١-٢٧، كانت مربّعاً بالمنتصف منذ ٢٠٢٦-١١-١٠): ورقة طويلة (`dsTallBox`)
/// يراها كل عضو حين يضغط شخصاً. الشكل والقطع في `TreeMemberCardParts.swift`، والقواعد في `TreeMemberCardLogic.swift`.
/// كل ما كان قبلها باقٍ بصلاحيته: «إبلاغ» و«حظر» (في «المزيد»)، «إعلان وفاة» للمالك والمدير، حذف السيرة، معاينة الصورة،
/// «طلب حذف» لابنك بمسار «عائلتي»، القرابة في الشجرة، الأب والأبناء يفتحون بطاقاتهم، والقفل «أكمل حسابك».
/// تغيّر بطلب المالك ونقد «المنتقد»: «الإدارة» تفتح بطاقة الإدارة v3 (`AdminMemberSheet`) لمن يعدّل الأعضاء؛ لا «تعديل رقم»
/// لغيرك ولا صورة للمرأة؛ «طلبك عنه» = طلباتك أنت فقط، وقائمة كل الطلبات لمن يقرّر طلبات الشجرة؛ الرقم المخفي لا يُذكر.
struct MemberDetailsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.dsSection) private var section
    @Environment(\.openURL) private var openURL
    private var chromeInk: Color { DS.Color.primary.dsChrome(in: section) }

    private let initialMember: FamilyMember
    @State private var currentMemberId: UUID

    /// بيانات العضو الحية من memberVM — تتحدث تلقائياً عند أي تعديل
    private var member: FamilyMember { memberVM.member(byId: currentMemberId) ?? initialMember }

    init(member: FamilyMember) {
        self.initialMember = member
        _currentMemberId = State(initialValue: member.id)
    }

    @State private var path: [TreeCardRoute] = []

    // الإدارة والنماذج الموجودة
    @State private var showAdminCard = false
    @State private var pendingEditAction: TreeEditAction? = nil
    @State private var showSelfAddChild = false
    @State private var showEditProfile = false
    @State private var editField: ProfileEditField? = nil
    @State private var showEditChild = false

    // الصورة
    @State private var showAvatarPreview = false
    @State private var previewScale: CGFloat = 1
    @State private var lastPreviewScale: CGFloat = 1

    // الأفعال الثانوية (كما كانت)
    @State private var showDeleteBioAlert = false
    @State private var showReportConfirm = false
    @State private var reportReason = ""
    @State private var reportSent = false
    @State private var reportFailed = false
    @State private var blockTarget: BlockTarget? = nil
    @ObservedObject private var blockedStore = BlockedMembersStore.shared
    @State private var phoneActionsNumber: String? = nil
    /// «طلب حذف» لابنك (§11): تأكيد «عائلتي» ثم `remove_self_child`
    @State private var confirmSelfRemoval = false
    @State private var selfRemovalSent = false
    @State private var selfRemovalError: String? = nil
    /// أُعلن عن وفاته؟ nil = لم يُتحقق بعد
    @State private var deathAnnounced: Bool? = nil

    // «سحب الطلب»
    @State private var withdrawTarget: AdminRequest? = nil
    @State private var withdrawing = false
    @State private var withdrawError: String? = nil

    // محسوبة مرة عند تغيّر العضو
    @State private var cachedFather: FamilyMember? = nil
    @State private var cachedChildren: [FamilyMember] = []
    @State private var cachedAllRequests: [AdminRequest] = []
    @State private var kinship: TreeMemberCardLogic.Kinship = .none
    @State private var kinshipPathIds: [UUID] = []
    @State private var kinshipText = ""
    /// جواب `profile_has_login` لابنك (nil = لم يصل) — ابنك المسجّل لا يُعدَّل من «عائلتي» (نقد البناء م٢)
    @State private var childLoginAnswer: Bool? = nil

    @ObservedObject private var lineage = LineageGateStore.shared

    // MARK: من يشاهد

    private var viewer: FamilyMember? { authVM.currentUser }
    private var isViewingSelf: Bool { member.id == viewer?.id }
    private var lineageLocked: Bool { !isViewingSelf && lineage.isLocked(.memberDetails) }
    private var isDeceased: Bool { member.isDeceased == true }

    /// ابنك أنت (أبوه = المشاهد)، قبل النظر إلى حسابه
    private var isOwnChild: Bool {
        guard let me = viewer?.id else { return false }
        return !isViewingSelf && member.fatherId == me
    }

    private var childHasLogin: Bool {
        isOwnChild && TreeMemberCardLogic.childHasLogin(looksRegistered: member.looksRegistered, serverAnswer: childLoginAnswer)
    }

    private var person: TreeMemberCardLogic.Person {
        TreeMemberCardLogic.person(isSelf: isViewingSelf, viewerId: viewer?.id, fatherId: member.fatherId,
                                   childHasLogin: childHasLogin)
    }

    /// «حذف من الشجرة» بقاعدة `showsDeleteRequest` القديمة (م١): لا لمسجّل ولا للإدارة ولا لمنتظر
    private var canRequestRemoval: Bool {
        TreeMemberCardLogic.canRequestRemoval(hasLogin: member.looksRegistered || childHasLogin,
                                              isStaff: TreeMemberCardLogic.staffRoles.contains(member.role.rawValue),
                                              isPending: member.role == .pending)
    }

    private var bottomButton: TreeMemberCardLogic.BottomButton {
        TreeMemberCardLogic.bottomButton(isSelf: isViewingSelf, canEditMembers: authVM.canEditMembers,
                                         isDeleted: member.isDeleted)
    }

    /// الرقم الظاهر لك وحدك (قواعد الرقم المخفي) — للمتوفى أيضاً كما كانت البطاقة القديمة (صفّ الرقم والعلم)
    private var visiblePhone: String? {
        member.dsVisiblePhone(viewerId: viewer?.id, viewerCanModerate: authVM.canModerate)
    }

    private var myRequests: [AdminRequest] {
        let refs = adminRequestVM.myPendingRequests.map {
            TreeMemberCardLogic.RequestRef(id: $0.id, memberId: $0.memberId, requesterId: $0.requesterId,
                                           womenNode: $0.treeEditPayload?.womenNodeId)
        }
        let ids = Set(TreeMemberCardLogic.mine(refs, memberId: member.id, viewer: viewer?.id))
        return adminRequestVM.myPendingRequests.filter { ids.contains($0.id) }
    }

    private var myActions: [String] { myRequests.compactMap { $0.treeEditPayload?.resolvedAction?.rawValue } }

    private var tiles: [TreeCardTile] {
        TreeMemberCardLogic.tiles(person: person, isFemale: member.isFemale, isDeceased: isDeceased,
                                  canRemove: canRequestRemoval)
    }

    private var pendingKinds: Set<TreeMemberCardLogic.TileKind> {
        Set(tiles.map(\.kind).filter { TreeMemberCardLogic.hasPending($0, myActions: myActions) })
    }

    private var isMemberBlocked: Bool { blockedStore.isBlocked(id: member.id, name: member.fullName) }

    /// «حظر» لغير صاحب الملف ولغير المتوفى — و«إلغاء الحظر» متاح دائماً
    private var canShowBlock: Bool { !isViewingSelf && !member.isDeleted && (!isDeceased || isMemberBlocked) }

    /// إعلان الوفاة للمتوفى الذي لم يُعلن عنه، للمالك والمدير، ولوفاة حديثة (السيرفر يفرضه)
    private var showsDeathAnnounce: Bool {
        isDeceased && authVM.isAdmin && deathAnnounced == false && DeathRecency.isRecent(member.deathDate)
    }

    /// «طلب حذف» بمسار «عائلتي»: لغير الإدارة، لغير صاحب الملف، ولمن لا يبدو مسجّلاً
    private var showsDeleteRequest: Bool {
        guard !authVM.canModerate, !isViewingSelf, !member.isDeleted, viewer != nil else { return false }
        let staff: [FamilyMember.UserRole] = [.owner, .admin, .monitor, .supervisor]
        return !member.looksRegistered && member.role != .pending && !staff.contains(member.role)
    }

    private var deletionPending: Bool {
        showsDeleteRequest && SelfRemovalText.isPendingAny(member.id, in: adminRequestVM.myPendingRequests)
    }

    private var firstName: String { member.firstName.isEmpty ? member.fullName : member.firstName }

    // MARK: - الجسم

    var body: some View {
        Group {
            if lineageLocked {
                LineageLockedView(section: section, style: .card, onOpen: {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { LineageGateStore.shared.openPage() }
                })
                .padding(DS.Spacing.lg)
            } else {
                NavigationStack(path: $path) {
                    AnyView(cardPage)
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: TreeCardRoute.self) { route in
                            destination(route)
                        }
                }
                .appUsageScreen(.memberDetails)
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear { recomputeCache() }
        .onChange(of: currentMemberId) { _ in path = []; recomputeCache() }
        .onChange(of: memberVM.membersVersion) { _ in recomputeCache() }
        .onChange(of: adminRequestVM.treeEditRequests.count) { _ in recomputeCache() }
        .task(id: member.isDeceased) { await refreshDeathAnnounced() }
        .task { await adminRequestVM.fetchMyPendingRequests() }
        .task(id: member.id) {
            // ابنك: هل له حساب دخول؟ (`profile_has_login` — نداء موجود، قراءة فقط)
            childLoginAnswer = nil
            guard isOwnChild, !member.looksRegistered else { return }
            childLoginAnswer = await memberVM.profileHasLogin(member.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .deathAnnouncementPublished)) { note in
            if (note.object as? UUID) == member.id { deathAnnounced = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .memberDeleted)) { note in
            if let id = note.object as? UUID, id == member.id { dismiss() }
        }
        .modifier(TreeCardPresentations(view: self))
        .debugStackProbe("TreeMemberCard")
    }

    // MARK: البطاقة

    private var cardPage: some View {
        VStack(spacing: 0) {
            AdminMemberCloseBar { dismiss() }
                .overlay(alignment: .trailing) {
                    // علم دولة الرقم (غير الكويت) — بقاعدة الرقم نفسها
                    DSPhoneCountryBadge(phone: visiblePhone)
                        .padding(.trailing, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.xl)
                }
            if member.isDeleted {
                DSEmptyView(L10n.t("هذا العضو حذف حسابه", "This member deleted their account"),
                            message: L10n.t("البيانات غير متوفرة", "Data unavailable"),
                            icon: "person.slash.fill", tint: DS.Color.textTertiary)
                    .frame(maxHeight: .infinity)
                    .background(DS.Hub.background)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        AnyView(header)
                        AnyView(cardBody)
                    }
                }
                .background(AdminMemberSheetBackdrop())
                AnyView(footer)
            }
        }
        .background(DS.Hub.background.ignoresSafeArea())
    }

    private var header: some View {
        let age = (member.isBirthDateHidden == true && !isViewingSelf && !authVM.canModerate) ? nil
            : TreeMemberCardLogic.age(birth: member.birthDate, death: member.deathDate, deceased: isDeceased,
                                      nowYear: Calendar.current.component(.year, from: Date()))
        var actions: [AdminMemberHeaderAction] = []
        switch kinship {
        case .mine, .locked: actions.append(.tree)
        default: break
        }
        // أزرار الاتصال السريعة للحيّ؛ رقم المتوفى في مجموعة «التواصل» كما كان
        if !isDeceased, KuwaitPhone.telURL(visiblePhone) != nil { actions.append(.call) }
        if !isDeceased, KuwaitPhone.whatsappURL(visiblePhone) != nil { actions.append(.whatsapp) }
        return TreeCardHeader(
            member: member,
            facts: TreeMemberCardLogic.factsLine(age: age, deceased: isDeceased, female: member.isFemale,
                                                 sons: cachedChildren.count),
            kinship: kinship, actions: actions, deletionPending: deletionPending,
            onKinship: showKinshipPath, onAction: perform, onPhoto: { showAvatarPreview = true })
    }

    private var cardBody: some View {
        VStack(spacing: DS.Hub.cardGap) {
            if !myRequests.isEmpty {
                TreeCardMyRequests(requests: myRequests, female: member.isFemale, isSelf: isViewingSelf) { path.append(.request($0.id)) }
            }
            if TreeMemberCardLogic.showsAllRequests(canModerateTree: authVM.canModerateTree), !cachedAllRequests.isEmpty {
                MemberPendingRequestsCard(requests: cachedAllRequests,
                                          onOpen: { MemberPendingRequestsLink.open($0) { dismiss() } },
                                          ink: chromeInk)
            }
            if let summary = TreeMemberCardLogic.familySummary(fatherName: cachedFather?.firstName,
                                                              sons: cachedChildren.count) {
                AnyView(TreeCardFamilyGroup(summary: summary, father: cachedFather, children: cachedChildren,
                                            ink: chromeInk, open: { openMemberInTree($0.id) }))
            }
            AnyView(dataGroup)
            if let phone = visiblePhone {
                AnyView(TreeCardContactGroup(phone: phone, female: member.isFemale) { phoneActionsNumber = phone })
            }
            if let bio = member.bio, !bio.isEmpty {
                AnyView(TreeCardBioGroup(stations: bio, canDelete: authVM.isAdmin || isViewingSelf) {
                    showDeleteBioAlert = true
                })
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(DS.Hub.background)
    }

    private var dataGroup: some View {
        let hidden = member.isBirthDateHidden == true && !isViewingSelf && !authVM.canModerate
        let birth: String? = member.birthDate.flatMap { raw in
            raw.isEmpty ? nil : (isDeceased ? Self.yearOnly(raw) : (DateHelper.displayDate(raw) ?? raw))
        }
        let death: String? = isDeceased ? member.deathDate.flatMap { $0.isEmpty ? nil : Self.yearOnly($0) } : nil
        let summary = TreeMemberCardLogic.dataSummary(birth: hidden ? (birth.map { _ in L10n.t("مخفي", "hidden") }) : birth,
                                                      death: death, deceased: isDeceased, female: member.isFemale)
        return TreeCardDataGroup(summary: summary, birth: birth, birthHidden: hidden && birth != nil,
                                 deceased: isDeceased, death: death, female: member.isFemale)
    }

    private var footer: some View {
        let menu = TreeCardMoreMenu(canReport: !isViewingSelf, canBlock: canShowBlock, isBlocked: isMemberBlocked,
                                    canAnnounceDeath: showsDeathAnnounce,
                                    report: { showReportConfirm = true },
                                    toggleBlock: requestBlockToggle,
                                    announceDeath: openDeathAnnouncement)
        return TreeCardFooter(button: bottomButton, more: menu.isEmpty ? nil : AnyView(menu)) {
            switch bottomButton {
            case .admin: showAdminCard = true
            case .requestEdit, .editMine: path.append(.tiles)
            case .none: break
            }
        }
    }

    // MARK: الصفحات الداخلية

    @ViewBuilder
    private func destination(_ route: TreeCardRoute) -> some View {
        switch route {
        case .tiles:
            AnyView(TreeCardTilesPage(
                back: isViewingSelf ? L10n.t("بطاقتك", "Your card") : firstName,
                title: bottomButton == .editMine ? TreeMemberCardLogic.BottomButton.editMine.title
                                                 : TreeMemberCardLogic.BottomButton.requestEdit.title,
                subtitle: TreeMemberCardLogic.requestSubtitle(name: member.displayFullName, isSelf: isViewingSelf),
                female: member.isFemale,
                note: person == .myChild ? L10n.t("\(firstName) ابنك — بياناته تُحفظ فوراً من «عائلتي».",
                                                  "\(firstName) is your son — his details save right away from «My family».")
                                         : (isOwnChild && childHasLogin
                                            ? L10n.t("\(firstName) ابنك وله حساب — يعدّل بياناته بنفسه، أو اطلب من الإدارة.",
                                                     "\(firstName) is your son with an account — he edits his own details, or ask the admins.")
                                            : nil),
                tiles: tiles, pending: pendingKinds,
                onBack: { if !path.isEmpty { path.removeLast() } },
                pick: pick)
                .debugStackProbe("TreeCardTilesPage"))
        case .request(let id):
            AnyView(TreeCardRequestPage(
                back: isViewingSelf ? L10n.t("بطاقتك", "Your card") : firstName, female: member.isFemale,
                isSelf: isViewingSelf, memberName: member.displayFullName,
                request: adminRequestVM.myPendingRequests.first { $0.id == id },
                isWithdrawing: withdrawing,
                onBack: { if !path.isEmpty { path.removeLast() } },
                withdraw: { withdrawTarget = adminRequestVM.myPendingRequests.first { $0.id == id } }))
        }
    }

    /// كل مربّع يفتح النموذج الموجود — والمربّع الذي عليه طلبك يفتح طلبك نفسه
    private func pick(_ tile: TreeCardTile) {
        if pendingKinds.contains(tile.kind),
           let request = myRequests.first(where: { $0.treeEditPayload?.resolvedAction?.rawValue == tile.kind.editAction }) {
            path.append(.request(request.id))
            return
        }
        switch tile.kind {
        case .myData: showEditProfile = true
        case .myPhone: editField = .phone
        case .addMyChild: showSelfAddChild = true
        case .childData: showEditChild = true
        case .remove where person == .myChild && showsDeleteRequest: confirmSelfRemoval = true
        default:
            if let raw = tile.kind.editAction, let action = TreeEditAction(rawValue: raw) { pendingEditAction = action }
        }
    }

    // MARK: - الأفعال

    private func perform(_ action: AdminMemberHeaderAction) {
        switch action {
        case .call: if let url = KuwaitPhone.telURL(visiblePhone) { openURL(url) }
        case .whatsapp: if let url = KuwaitPhone.whatsappURL(visiblePhone) { openURL(url) }
        case .tree:
            let id = member.id
            dismiss()
            NotificationCenter.default.post(name: .requestMemberInTree, object: nil, userInfo: ["memberId": id])
        case .fullProfile: break
        }
    }

    fileprivate func recomputeCache() {
        let m = member
        cachedFather = m.fatherId.flatMap { memberVM.member(byId: $0) }
        cachedChildren = memberVM.allMembers
            .filter { $0.fatherId == m.id && $0.isCountable }
            .sorted { $0.sortOrder < $1.sortOrder }
        // طلبات شجرة النساء عن عقدة أخرى (بنته مثلاً) تظهر في بطاقتها هي
        // بلا طلباتك — تظهر فوقها في «طلبك عنه» (ت٢)
        let me = viewer?.id
        cachedAllRequests = adminRequestVM.treeEditRequests.filter { r in
            guard r.memberId == m.id, me == nil || r.requesterId != me else { return false }
            let node = r.treeEditPayload?.womenNodeId
            return node == nil || node == m.id
        }
        computeKinship(for: m)
    }

    private func computeKinship(for m: FamilyMember) {
        guard let me = viewer else { kinship = .none; return }
        let hasNode = memberVM.member(byId: me.id) != nil && !me.isWomanAccount
        let isSelf = m.id == me.id
        guard hasNode, !isSelf, !m.isDeleted else {
            kinship = TreeMemberCardLogic.kinship(isSelf: isSelf, viewerHasNode: hasNode, isDeleted: m.isDeleted,
                                                  relationship: "", isBlood: false, distA: 0, distB: 0, ancestorName: nil)
            kinshipPathIds = []
            return
        }
        let result = KinshipCalculator.calculate(from: me, to: m, lookup: memberVM._memberById)
        kinshipText = result.relationship
        kinshipPathIds = result.pathA.map(\.id) + result.pathB.map(\.id) + (result.commonAncestor.map { [$0.id] } ?? [])
        kinship = TreeMemberCardLogic.kinship(isSelf: false, viewerHasNode: true, isDeleted: false,
                                              relationship: result.relationship, isBlood: result.kind == .blood,
                                              distA: max(0, result.pathA.count - 1), distB: max(0, result.pathB.count - 1),
                                              ancestorName: result.commonAncestor?.firstName, female: m.isFemale,
                                              ancestorIsRoot: result.commonAncestor.map { $0.fatherId == nil } ?? false)
    }

    /// طريق القرابة في الشجرة (T5): تاب الشجرة ← شجرة العائلة ← المسار — يعمل من الرئيسية والإشعارات أيضاً
    private func showKinshipPath() {
        let id = member.id, relation = kinshipText, ids = kinshipPathIds
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(name: .requestKinshipPath, object: nil,
                                            userInfo: ["memberId": id, "relationship": relation, "pathIds": ids])
        }
    }

    /// الأب أو الابن: البطاقة تتحدث والشجرة تتبعه خلفها
    private func openMemberInTree(_ id: UUID) {
        currentMemberId = id
        NotificationCenter.default.post(name: .openMemberInTree, object: nil, userInfo: ["memberId": id])
    }

    private func requestBlockToggle() {
        blockTarget = BlockTarget(id: member.id, name: member.fullName, otherNames: [member.displayFullName])
    }

    private func refreshDeathAnnounced() async {
        guard isDeceased, authVM.isAdmin else { return }
        let ids = await DeathAnnouncementPresenter.announcedIDs()
        deathAnnounced = ids.contains(member.id)
    }

    private func openDeathAnnouncement() {
        DeathAnnouncementPresenter.open(DeathAnnouncementTarget(id: member.id, name: member.fullName,
                                                                isFemale: member.isFemale, deathDate: member.deathDate))
    }

    fileprivate func sendSelfRemoval() {
        let id = member.id
        Task {
            switch await memberVM.removeSelfChild(id: id) {
            case .requested:
                await adminRequestVM.fetchMyPendingRequests(force: true)
                selfRemovalSent = true
            case .deleted:
                await adminRequestVM.fetchMyPendingRequests(force: true)
                dismiss()
            case .failed, .serverMissing:
                selfRemovalError = memberVM.errorMessage ?? L10n.t("تعذّر إرسال الطلب.", "Couldn't send the request.")
            }
            memberVM.errorMessage = nil
        }
    }

    fileprivate func withdraw(_ request: AdminRequest) {
        withdrawing = true
        Task {
            await adminRequestVM.cancelMyRequest(request)
            withdrawing = false
            if let message = adminRequestVM.errorMessage, !message.isEmpty {
                withdrawError = message
            } else if !path.isEmpty {
                path.removeLast()
            }
        }
    }

    fileprivate func sendReport() {
        let target = member, reason = reportReason
        reportReason = ""
        Task {
            let ok = await notificationVM.reportContent(
                contentKind: L10n.t("ملف عضو", "member profile"), contentLabel: target.fullName, contentId: target.id,
                reason: reason,
                source: RequestSource(.tree, .member(target.fullName), RequestSourceStep("flag.fill", "بلاغ عن ملف عضو")))
            if ok { reportSent = true } else { reportFailed = true }
        }
    }

    private static func yearOnly(_ date: String) -> String {
        let trimmed = date.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 4 else { return trimmed }
        let prefix = String(trimmed.prefix(4))
        return prefix.allSatisfy(\.isNumber) ? prefix : trimmed
    }

    // MARK: معاينة الصورة

    fileprivate var avatarPreview: some View {
        ZStack(alignment: .topTrailing) {
            DS.Color.overlayDark.opacity(DS.Opacity.mediaDim).ignoresSafeArea()
            if let raw = member.avatarUrl, let url = URL(string: raw), !member.isFemale {
                CachedAsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    .frame(width: DS.Icon.avatarPreview, height: DS.Icon.avatarPreview)
                    .clipShape(Circle())
                    .scaleEffect(previewScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(MagnificationGesture()
                        .onChanged { previewScale = min(max(lastPreviewScale * $0, 1), 4) }
                        .onEnded { _ in lastPreviewScale = previewScale })
            }
            DSCloseButton(context: .onMedia) { closePreview() }
                .padding(DS.Spacing.lg)
        }
        .contentShape(Rectangle())
        .onTapGesture { closePreview() }
    }

    private func closePreview() {
        previewScale = 1
        lastPreviewScale = 1
        showAvatarPreview = false
    }

    // MARK: ما يُفتح فوق الورقة (نوع مستقل — حارس المكدس)

    private struct TreeCardPresentations: ViewModifier {
        let view: MemberDetailsView

        func body(content: Content) -> some View {
            let v = view
            content
                // «الإدارة» = بطاقة الإدارة v3 بأقفالها (على بطاقتك أيضاً)، فوق هذه الورقة
                .dsTallBox(isPresented: v.$showAdminCard) {
                    if v.authVM.canEditMembers {
                        AdminMemberSheet(ids: [v.member.id], start: 0, inBox: true)
                    }
                }
                .dsTallBox(isPresented: v.$showEditProfile) {
                    if let me = v.authVM.currentUser { EditProfileView(member: me) }
                }
                .dsCenterBox(item: v.$editField) { field in
                    if let me = v.authVM.currentUser { ProfileFieldEditBox(field: field, member: me) }
                }
                .dsCenterBox(item: v.$pendingEditAction) { action in
                    TreeEditRequestView(member: v.member, action: action)
                }
                // بعد إغلاق النموذج: «طلبك عنه» يظهر فوراً
                .onChange(of: v.pendingEditAction) { action in
                    if action == nil { Task { await v.adminRequestVM.fetchMyPendingRequests(force: true) } }
                }
                .dsCenterBox(isPresented: v.$showSelfAddChild) { AddChildSheet(member: v.member) }
                .dsCenterBox(isPresented: v.$showEditChild) { EditChildSheet(member: v.member) }
                .fullScreenCover(isPresented: v.$showAvatarPreview) { v.avatarPreview }
                .modifier(TreeCardAlerts(view: v))
        }
    }

    private struct TreeCardAlerts: ViewModifier {
        let view: MemberDetailsView

        func body(content: Content) -> some View {
            let v = view
            content
                .dsAlert(L10n.t("حذف السيرة", "Delete Biography"), isPresented: v.$showDeleteBioAlert) {
                    Button(L10n.t("حذف", "Delete"), role: .destructive) {
                        let id = v.member.id
                        Task { await v.memberVM.updateMemberBio(memberId: id, bio: []) }
                    }
                    Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
                } message: {
                    Text(L10n.t("حذف السيرة الذاتية؟", "Delete biography?"))
                }
                .dsAlert(SelfRemovalText.confirmTitle, isPresented: v.$confirmSelfRemoval) {
                    Button(SelfRemovalText.sendButton) { v.sendSelfRemoval() }
                    Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
                } message: {
                    Text(SelfRemovalText.confirmMessage(v.member.firstName))
                }
                .dsAlert(SelfRemovalText.sentTitle, isPresented: v.$selfRemovalSent, moment: .sentForApproval) {
                    Button(L10n.t("حسناً", "OK")) {}
                } message: {
                    Text(SelfRemovalText.sentMessage)
                }
                .dsAlert(L10n.t("تعذّر الإرسال", "Couldn't send"),
                         isPresented: Binding(get: { v.selfRemovalError != nil },
                                              set: { if !$0 { v.selfRemovalError = nil } })) {
                    Button(L10n.t("حسناً", "OK")) { v.selfRemovalError = nil }
                } message: {
                    Text(v.selfRemovalError ?? "")
                }
                .dsAlert(L10n.t("سحب الطلب", "Withdraw Request"),
                         isPresented: Binding(get: { v.withdrawTarget != nil },
                                              set: { if !$0 { v.withdrawTarget = nil } }),
                         presenting: v.withdrawTarget) { request in
                    Button(L10n.t("تراجع", "Keep"), role: .cancel) {}
                    Button(L10n.t("سحب الطلب", "Withdraw"), role: .destructive) { v.withdraw(request) }
                } message: { _ in
                    Text(L10n.t("سيتم إلغاء هذا الطلب ولن يصل للإدارة.",
                                "This request will be cancelled and won't be sent to the admins."))
                }
                .dsAlert(L10n.t("خطأ", "Error"),
                         isPresented: Binding(get: { v.withdrawError != nil },
                                              set: { if !$0 { v.withdrawError = nil } })) {
                    Button(L10n.t("حسناً", "OK")) { v.withdrawError = nil }
                } message: {
                    Text(v.withdrawError ?? "")
                }
                .dsAlert(L10n.t("إبلاغ عن عضو", "Report Member"), isPresented: v.$showReportConfirm) {
                    TextField(L10n.t("سبب الإبلاغ (اختياري)", "Reason (optional)"), text: v.$reportReason)
                        .dsAlertField()
                    Button(L10n.t("إبلاغ", "Report"), role: .destructive) { v.sendReport() }
                    Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { v.reportReason = "" }
                } message: {
                    Text(L10n.t("اكتب سبب الإبلاغ، وسيتم إرساله للإدارة لمراجعة ملف هذا العضو.",
                                "Enter a reason; it will be sent to the admins to review this member's profile."))
                }
                .dsAlert(L10n.t("تعذّر الإبلاغ", "Couldn't report"), isPresented: v.$reportFailed) {
                    Button(L10n.t("حسناً", "OK")) {}
                } message: {
                    Text(L10n.t("تعذّر الإبلاغ. حاول مرة أخرى.", "Couldn't send the report. Please try again."))
                }
                .dsAlert(L10n.t("تم الإبلاغ", "Reported"), isPresented: v.$reportSent) {
                    Button(L10n.t("حسناً", "OK")) {}
                } message: {
                    Text(L10n.t("وصل البلاغ إلى الإدارة، وتتم مراجعته خلال ٢٤ ساعة.",
                                "Thank you — your report reached the admins and will be reviewed within 24 hours."))
                }
                // صفّ الرقم: «اتصال / واتساب» — الرقم الظاهر فقط
                .dsAlert(L10n.t("التواصل", "Contact"),
                         isPresented: Binding(get: { v.phoneActionsNumber != nil },
                                              set: { if !$0 { v.phoneActionsNumber = nil } }),
                         icon: "phone.fill") {
                    if let url = KuwaitPhone.telURL(v.phoneActionsNumber) {
                        Button(L10n.t("اتصال", "Call")) { v.openURL(url) }
                    }
                    if let url = KuwaitPhone.whatsappURL(v.phoneActionsNumber) {
                        Button(L10n.t("واتساب", "WhatsApp")) { v.openURL(url) }
                    }
                    Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
                } message: {
                    Text(verbatim: "\u{2066}\(KuwaitPhone.display(v.phoneActionsNumber))\u{2069}")
                }
                .dsBlockMemberFlow(target: v.$blockTarget)
        }
    }
}
