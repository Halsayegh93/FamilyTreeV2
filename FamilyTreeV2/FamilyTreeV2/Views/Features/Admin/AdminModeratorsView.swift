import SwiftUI

// MARK: - فريق الإدارة — بشكل «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠ «كل الصفحات بنفس شكل «اليوم»»، `AdminPageKit`)
//
// رأس كحلي بعدد كل دور وزرّ «إضافة» للمالك (وشارة «للقراءة» لغيره) ← لكل دور عنوان بعدده ثم أعضاؤه، كل عضو بطاقة
// بيضاء (الصورة · الاسم · مجال الدور · الرقم · شارة الدور) ← بطاقة «الأدوار وما يقدر عليه كل دور». بقيت `List`
// (`AdminPage(layout: .list)`) لأجل السحب «إزالة» على صفّ المسؤول. الضغط على العضو يفتح «تغيير الدور» للمالك فقط،
// والمالك ونفسك لا يُغيَّران — كل الحراسات والمربّعات والتأكيدات كما كانت تماماً.

struct AdminModeratorsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @State private var showAddSheet = false
    @State private var memberToChange: FamilyMember?
    @State private var showRoleConfirm = false
    @State private var pendingRole: FamilyMember.UserRole = .member
    @State private var showRemoveConfirm = false
    /// الدور المعروضة تفاصيله في ورقة «يقدر / ما يقدر»
    @State private var selectedRoleGuide: RoleGuide? = nil
    /// المسؤول المطلوب تغيير دوره — يفتح ورقة اختيار المجال
    @State private var roleChangeTarget: FamilyMember? = nil
    /// من يستخدم التطبيق فعلاً — يظهر تحت صف «العضو»
    @State private var usageStats: AppUsageStats? = AppUsageStats.cached
    /// اكتمل أول جلب للأعضاء عند الفتح — قبله «—» في الأرقام وبطاقة تحميل (إن لم يكن الفريق محمّلاً أصلاً)
    @State private var hasLoaded = false
    /// جلب جارٍ (الفتح أو «إعادة المحاولة»)
    @State private var isFetching = false
    /// دخول صفوف الأعضاء (نمط الأخبار والديوانيات) — مرة واحدة، بعد عنوان بطاقتها وخلفيتها
    @State private var rowsAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOwner: Bool {
        authVM.isOwner
    }

    private var moderators: [FamilyMember] {
        let roleOrder: [FamilyMember.UserRole] = [.owner, .admin, .monitor, .supervisor]
        return memberVM.allMembers
            .filter { $0.role == .owner || $0.role == .admin || $0.role == .monitor || $0.role == .supervisor }
            .filter { $0.isDeceased != true } // المتوفون لا يظهرون في الفريق (طلب المالك)
            .sorted { a, b in
                let aIdx = roleOrder.firstIndex(of: a.role) ?? 99
                let bIdx = roleOrder.firstIndex(of: b.role) ?? 99
                if aIdx != bIdx { return aIdx < bIdx }
                return a.fullName < b.fullName
            }
    }

    var body: some View {
        let team = moderators

        // الرأس ← بطاقات الأعضاء بأدوارهم ← دليل الأدوار: قائمة واحدة تتمرّر معاً
        // (بقيت `List` لأجل السحب «إزالة» على صفّ المسؤول)
        return AdminPage(header: header(team), lead: leadCard(team), layout: .list,
                         content: AnyView(teamContent(team)))
        // تفاصيل الدور — مربّع عرض بمنتصف الشاشة (يُغلق أيضاً بالضغط خارجه)
        .dsCenterBox(item: $selectedRoleGuide, onBackgroundTap: { selectedRoleGuide = nil }) { guide in
            roleDetailBox(guide)
        }
        .dsTallBox(isPresented: $showAddSheet, onDismiss: {   // قائمة أعضاء طويلة (توصية أبل)
            Task { await memberVM.fetchAllMembers(force: true) }
        }) {
            AddModeratorSheet()
                .environmentObject(authVM)
                .environmentObject(memberVM)
        }
        .dsAlert(
            L10n.t("تغيير مستوى الحساب", "Change Account Level"),
            isPresented: $showRoleConfirm,
            presenting: memberToChange
        ) { member in
            Button(L10n.t("تأكيد", "Confirm"), role: .destructive) {
                Task {
                    await memberVM.updateMemberRole(memberId: member.id, newRole: pendingRole)
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: { member in
            let roleName: String = {
                switch pendingRole {
                case .admin: return L10n.t("مدير", "Admin")
                case .monitor: return L10n.t("مراقب", "Monitor")
                case .supervisor: return L10n.t("مشرف", "Supervisor")
                default: return L10n.t("عضو", "Member")
                }
            }()
            Text(L10n.t(
                "تغيير مستوى حساب \(member.firstName) إلى \(roleName)؟",
                "Change \(member.firstName)'s account level to \(roleName)?"
            ))
        }
        .dsAlert(
            L10n.t("إزالة الصلاحية", "Remove Permission"),
            isPresented: $showRemoveConfirm,
            presenting: memberToChange
        ) { member in
            Button(L10n.t("إزالة", "Remove"), role: .destructive) {
                Task {
                    await memberVM.updateMemberRole(memberId: member.id, newRole: .member)
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: { member in
            Text(L10n.t(
                "إزالة صلاحية \(member.firstName) وتحويله لعضو عادي؟",
                "Remove \(member.firstName)'s permission and set as regular member?"
            ))
        }
        .dsCenterBox(item: $roleChangeTarget) { member in
            ChangeRoleSheet(member: member) { newRole in
                Task { await memberVM.updateMemberRole(memberId: member.id, newRole: newRole) }
            }
            .environmentObject(authVM)
            .environmentObject(memberVM)
        }
        .task { usageStats = await AppUsageStats.fetch() }
        .onAppear {
            Task { await loadTeam() }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - التحميل

    /// نفس جلب الفتح السابق تماماً (`fetchAllMembers(force: true)`) — ويحفظ اكتماله لبطاقتي التحميل والخطأ
    private func loadTeam() async {
        isFetching = true
        await memberVM.fetchAllMembers(force: true)
        isFetching = false
        hasLoaded = true
    }

    /// أول تحميل (أو «إعادة المحاولة») ولا فريق محمّل بعد
    private func isInitialLoading(_ team: [FamilyMember]) -> Bool {
        team.isEmpty && (isFetching || !hasLoaded)
    }

    /// الجلب انتهى بلا أعضاء وفشل (بلا اتصال مثلاً) — القائمة الفارغة هنا ليست «لا يوجد فريق»
    private func loadFailed(_ team: [FamilyMember]) -> Bool {
        team.isEmpty && hasLoaded && !isFetching && memberVM.membersLoadFailed
    }

    // MARK: - الرأس الكحلي

    /// ٣ أرقام حيّة من الأعضاء المحمّلين أصلاً (بلا طلبات جديدة للسيرفر): عدد كل دور —
    /// المالك ضمن «المدراء» كما في بطاقتهم. «—» قبل اكتمال أول تحميل. «إضافة» للمالك فقط كما كانت.
    private func header(_ team: [FamilyMember]) -> AdminPageHeader {
        let pending = isInitialLoading(team) || loadFailed(team)
        func value(_ roles: Set<FamilyMember.UserRole>) -> String {
            pending ? "—" : "\(team.filter { roles.contains($0.role) }.count)"
        }
        return AdminPageHeader(
            title: L10n.t("فريق الإدارة", "Admin Team"),
            subtitle: isOwner
                ? L10n.t("اضغط على أي عضو لتغيير دوره", "Tap a member to change their role")
                : L10n.t("تغيير الأدوار للمالك", "The owner assigns roles"),
            glyph: "person.3.fill",
            readOnly: !isOwner,
            kpis: [
                AdminPageKPI(value([.owner, .admin]), L10n.t("المدراء", "Admins"),
                             icon: RoleGuide.forRole(.admin)?.icon ?? "person.fill"),
                AdminPageKPI(value([.monitor]), L10n.t("المراقبين", "Monitors"),
                             icon: RoleGuide.forRole(.monitor)?.icon ?? "person.fill", tint: DS.Hub.kpiMine),
                AdminPageKPI(value([.supervisor]), L10n.t("المشرفين", "Supervisors"),
                             icon: RoleGuide.forRole(.supervisor)?.icon ?? "person.fill", tint: DS.Hub.kpiMine)
            ],
            actions: isOwner ? [AdminPageAction(symbol: "plus", label: L10n.t("إضافة", "Add"),
                                                tap: .action { showAddSheet = true })] : [])
    }

    // MARK: - محتوى القائمة

    /// أول بطاقة (تصعد فوق الرأس): التحميل، أو تعذّره، أو «لا يوجد أعضاء» — والفريق المحمّل بلا بطاقة فوق الرأس
    private func leadCard(_ team: [FamilyMember]) -> AnyView? {
        if isInitialLoading(team) {
            return AnyView(AdminPageStateCard(.loading(L10n.t("جارٍ تحميل فريق الإدارة…", "Loading the admin team…"))))
        }
        if loadFailed(team) {
            return AnyView(AdminPageStateCard(.error(L10n.t("تعذّر تحميل فريق الإدارة", "Couldn't load the admin team"),
                                                     message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى",
                                                                     "Check your connection and try again"),
                                                     retry: { Task { await loadTeam() } })))
        }
        if team.isEmpty {
            return AnyView(emptyState
                .padding(.vertical, DS.Spacing.sm)
                .frame(maxWidth: .infinity)
                .adminCard())
        }
        return nil
    }

    @ViewBuilder
    private func teamContent(_ team: [FamilyMember]) -> some View {
        if !team.isEmpty {
            let groups = roleGroups(team)
            ForEach(Array(groups.enumerated()), id: \.element.id) { offset, group in
                // رقم أول صف في البطاقة — الصفوف تتوالى عبر البطاقات بالترتيب الظاهر
                groupRows(group, firstRow: groups.prefix(offset).reduce(0) { $0 + $1.members.count })
            }

            // قسم الصلاحيات
            rolesGuideSection
                .adminPageRow(top: DS.Hub.stackSpacing, bottom: DS.Spacing.xs)
        }
    }

    // MARK: - بطاقات الأدوار

    /// مجموعة دور في بطاقة — أيقونة الدور ولونه من `RoleGuide` (نفس «تغيير الدور»)
    private struct RoleGroup: Identifiable {
        let id: String
        let title: String
        let icon: String
        let tint: Color
        let members: [FamilyMember]
    }

    private func roleGroups(_ team: [FamilyMember]) -> [RoleGroup] {
        func group(_ id: String, _ title: String, _ role: FamilyMember.UserRole,
                   _ members: [FamilyMember]) -> RoleGroup {
            let guide = RoleGuide.forRole(role)
            return RoleGroup(id: id, title: title,
                             icon: guide?.icon ?? "person.fill",
                             tint: guide?.color ?? role.color,
                             members: members)
        }
        return [
            // المالك يظهر ضمن المدراء — بدون قسم خاص
            group("admins", L10n.t("المدراء", "Admins"), .admin,
                  team.filter { $0.role == .admin || $0.role == .owner }),
            group("monitors", L10n.t("المراقبين", "Monitors"), .monitor,
                  team.filter { $0.role == .monitor }),
            group("supervisors", L10n.t("المشرفين", "Supervisors"), .supervisor,
                  team.filter { $0.role == .supervisor })
        ]
        .filter { !$0.members.isEmpty }
    }

    /// دور واحد: عنوانه بعدده ثم أعضاؤه — كل عضو بطاقة بيضاء (السحب على صفّه نفسه كما كان)
    @ViewBuilder
    private func groupRows(_ group: RoleGroup, firstRow: Int) -> some View {
        AdminSectionLabel(title: group.title, trailing: membersCountText(group.members.count))
            // العنوان يظهر مع الصفوف (بعد التحميل) — فتبدأ الصفوف بعده
            .onAppear(perform: startRowsCascade)
            .adminPageRow(top: DS.Hub.stackSpacing, bottom: 0)

        ForEach(Array(group.members.enumerated()), id: \.element.id) { i, member in
            moderatorRow(member: member)
                // نمط الأخبار والديوانيات: أول ٧ صفوف تصعد تباعاً (عبر الأدوار)، والباقي مع السابع
                .dsCardCascade(firstRow + i, appeared: rowsAppeared)
                .adminPageRow()
        }
    }

    private func membersCountText(_ n: Int) -> String {
        L10n.t("\(n) عضو", n == 1 ? "1 member" : "\(n) members")
    }

    /// الصفوف تبدأ بعد عنوان أول بطاقة وخلفيتها (٢)، فيبقى كل صف بعد عنوان بطاقته وخلفيتها:
    /// الرأس ← عنوان البطاقة ← صفوفها. مرة واحدة؛ «تقليل الحركة»: تلاشٍ فوري بلا انتظار.
    private func startRowsCascade() {
        guard !rowsAppeared else { return }
        guard !reduceMotion else { rowsAppeared = true; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.staggerDelay(2, base: DSMotion.sectionsOnPage)) {
            rowsAppeared = true
        }
    }

    // MARK: - Moderator Row

    /// بطاقة المسؤول: الصورة (بلون دوره) + الاسم + مجال الدور + الرقم من اليسار، وشارة الدور (و«أنت») في الطرف،
    /// وسهم لمن يقدر المالك تغيير دوره
    private func moderatorRow(member: FamilyMember) -> some View {
        // المالك يظهر بنفس اسم المدير ولونه ومجاله — لا يتميّز عنه بصرياً (كما كان)
        let shownRole: FamilyMember.UserRole = member.role == .owner ? .admin : member.role
        let roleColor = shownRole.color
        let isSelf = member.id == authVM.currentUser?.id
        let canChange = isOwner && !isSelf && member.role != .owner

        return HStack(spacing: DS.Spacing.md) {
            DSMemberAvatar(name: member.firstName, avatarUrl: member.avatarUrl, size: DS.Icon.avatar, roleColor: roleColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                // الاسم والمجال يلتفّان والصفّ يطول مع «حجم النص» في الجهاز (كانا يُقصّان «…» بالخط الكبير)
                Text(member.displayFullName)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let scope = RoleGuide.forRole(shownRole)?.mandate {
                    Text(scope)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let phone = member.phoneNumber, !phone.isEmpty {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "phone.fill")
                            .dsGlyph(DS.Glyph.micro, weight: .semibold)
                            .accessibilityHidden(true)
                        Text(Self.isolatedLTR(KuwaitPhone.display(phone)))
                            .dsFont(.footnote)
                            .monospacedDigit()
                    }
                    .foregroundColor(DS.Color.textTertiary)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: DS.Spacing.xs) {
                DSStatusChip(text: member.roleName, tint: roleColor)
                if isSelf {
                    DSStatusChip(text: L10n.t("أنت", "You"), tint: DS.Color.info)
                }
            }
            .fixedSize()

            if canChange {
                DSChevron()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Hub.cardPadding)
        .padding(.vertical, DS.Spacing.md)
        .adminCard(padding: nil)
        .contentShape(Rectangle())
        .onTapGesture {
            // تغيير الدور: اختيار مجال من ورقة واحدة — بدل ترقية/تنزيل بالسحب
            guard isOwner, member.id != authVM.currentUser?.id, member.role != .owner else { return }
            roleChangeTarget = member
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(canChange ? .isButton : [])
        .accessibilityHint(canChange ? L10n.t("يفتح «تغيير الدور»", "Opens Change Role") : "")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // لا يمكن تعديل نفسك + فقط المدير يقدر يتحكم
            if isOwner && member.id != authVM.currentUser?.id && member.role != .owner {
                // إزالة الصلاحية
                Button(role: .destructive) {
                    memberToChange = member
                    showRemoveConfirm = true
                } label: {
                    Label(L10n.t("إزالة", "Remove"), systemImage: "minus.circle.fill")
                }

                // تغيير الدور صار من ورقة «تغيير الدور» بالضغط على الصف
            }
        }
        .contextMenu {
            if isOwner && member.id != authVM.currentUser?.id && member.role != .owner {
                Button {
                    roleChangeTarget = member
                } label: {
                    Label(L10n.t("تغيير الدور", "Change role"), systemImage: "person.badge.key.fill")
                }
                Button(role: .destructive) {
                    memberToChange = member
                    showRemoveConfirm = true
                } label: {
                    Label(L10n.t("إزالة الصلاحية", "Remove role"), systemImage: "minus.circle.fill")
                }
            }
        }
    }

    /// الأرقام تبقى بترتيبها من اليسار داخل سطر عربي
    private static func isolatedLTR(_ text: String) -> String {
        "\u{2066}\(text)\u{2069}"
    }

    // MARK: - دليل الأدوار — صف لكل دور (تحديث الأدوار 2026-09-21)
    //
    // بدل جدول ✓/✕ طويل: لكل دور صف فيه رمزه ولونه ومجاله وعدد من يحملونه، والضغط يفتح
    // «يقدر» و«ما يقدر» بكلام واضح — ليعرف المالك ما الذي يمنحه بالضبط.

    private var rolesGuideSection: some View {
        AdminSectionCard(title: L10n.t("الأدوار وما يقدر عليه كل دور", "Roles and what each can do")) {
            // ١) خريطة المجالات
            HStack(spacing: DS.Spacing.xs) {
                ForEach(Array(RoleDomain.all.enumerated()), id: \.offset) { _, domain in
                    domainTile(domain)
                }
            }

            // ٢) صف لكل دور — الضغط يفتح تفاصيله
            AdminRowsCardBody {
                ForEach(Array(RoleGuide.all.enumerated()), id: \.offset) { _, guide in
                    Button { selectedRoleGuide = guide } label: {
                        roleCompactRow(guide)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(L10n.t("يعرض ما يقدر عليه وما لا يقدر", "Shows what it can and can't do"))
                }
            }
        }
    }

    /// مجال عمل: أيقونته بدائرة بلونه + اسمه + أدواره
    private func domainTile(_ domain: RoleDomain) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            DSStateIcon(domain.icon, tint: domain.color, size: DS.Icon.section, mapsChrome: false)
            Text(domain.title)
                .dsFieldFont(.badge)
                .foregroundColor(DS.Color.fieldLabel)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.8)
            Text(domain.roles.joined(separator: " · "))
                .dsFont(.micro)
                .foregroundColor(DS.Color.fieldValue)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.sm)
        .padding(.horizontal, DS.Spacing.xs)
        // البطاقة الواحدة (صندوق فوق بطاقة القسم)
        .dsCard(padding: nil, fill: DS.Color.background)
        .accessibilityElement(children: .combine)
    }

    /// صف الدور بإطار صفوف المربّعات: رمزه بلونه + اسمه + مجاله + عدد من يحملونه + سهم
    private func roleCompactRow(_ guide: RoleGuide) -> some View {
        let count = holdersCount(for: guide.title)
        return HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: guide.icon, tint: guide.color)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(guide.title)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                Text(guide.mandate)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                // العضو: عدد الأحياء في الشجرة لا يعني أنهم يستخدمون التطبيق
                if guide.title == L10n.t("العضو", "Member"), let usage = usageStats {
                    Text(L10n.t("فعّالون (رقم + جهاز): \(usage.active)",
                                "Active (phone + device): \(usage.active)"))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.success)
                }
            }

            Spacer(minLength: 0)

            if let count, count > 0 {
                AdminValueChip(text: "\(count)", tint: guide.color)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(membersCountText(count))
            }
            DSChevron()
        }
        .padding(.vertical, DS.Spacing.sm + 2)
        .frame(minHeight: DS.Icon.tapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// عدد من يحملون هذا الدور
    private func holdersCount(for title: String) -> Int? {
        let all = memberVM.allMembers.filter { $0.isDeceased != true }
        switch title {
        case L10n.t("المالك", "Owner"):      return all.filter { $0.role == .owner }.count
        case L10n.t("المدير", "Admin"):      return all.filter { $0.role == .admin }.count
        case L10n.t("المراقب", "Monitor"):   return all.filter { $0.role == .monitor }.count
        case L10n.t("المشرف", "Supervisor"): return all.filter { $0.role == .supervisor }.count
        // الأعضاء العاديون الأحياء فقط (طلب المالك) — كل من في الشجرة،
        // سواء فعّل حسابه أو لا. الأحياء كلهم = هذا العدد + فريق الإدارة.
        case L10n.t("العضو", "Member"):      return all.filter { $0.role == .member && $0.isDeceased != true }.count
        default: return nil
        }
    }

    /// تفاصيل الدور — مربّع عرض بمنتصف الشاشة بتصميم المربّعات الموحّد:
    /// الرأس يحمل رمز الدور واسمه ومجاله، ثم قسما «يقدر» و«ما يقدر»، و«إغلاق» أسفله
    private func roleDetailBox(_ guide: RoleGuide) -> some View {
        DSComposer(
            title: guide.title,
            subtitle: guide.mandate,
            icon: guide.icon,
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { selectedRoleGuide = nil }
        ) {
            guideSection(title: L10n.t("يقدر", "Can"), lines: guide.can, allowed: true, index: 0)

            if !guide.cannot.isEmpty {
                guideSection(title: L10n.t("ما يقدر", "Cannot"), lines: guide.cannot, allowed: false, index: 1)
            }
        }
    }

    /// قسم «يقدر» أو «ما يقدر» — الأسطر داخل صندوق صف المربّعات
    private func guideSection(title: String, lines: [String], allowed: Bool, index: Int) -> some View {
        DSComposerSection(title: title,
                          icon: allowed ? "checkmark.circle.fill" : "xmark.circle.fill",
                          tint: allowed ? DS.Color.success : DS.Color.textTertiary,
                          index: index) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(lines, id: \.self) { line in
                    RoleScopeLineRow(text: line, allowed: allowed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsRowBox()
        }
    }

    // MARK: - Empty State

    /// لا أحد في الفريق — «إضافة» للمالك كما كانت
    private var emptyState: some View {
        DSEmptyView(L10n.t("لا يوجد أعضاء في فريق الإدارة", "No admin team members"),
                    message: isOwner ? L10n.t("أضف مديراً أو مراقباً أو مشرفاً", "Add an admin, monitor or supervisor") : nil,
                    actionTitle: isOwner ? L10n.t("إضافة", "Add") : nil,
                    actionIcon: "plus",
                    style: .compact, action: isOwner ? { showAddSheet = true } : nil)
    }
}

// MARK: - Add Moderator Sheet
//
// مربّع بمنتصف الشاشة بتصميم مربّعات الإضافة (طلب المالك): قسم «الدور» (مبدّل
// مشرف/مراقب/مدير + مجال الدور المختار) ثم قسم «العضو» (بحث + صفوف بعلامة اختيار)،
// و«إضافة» كحلي يمين / «إلغاء» رمادي يسار.
struct AddModeratorSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    /// «تقليل الحركة» (توصية أبل): مؤشّر الدور ينتقل مباشرة بلا انزلاق
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var selectedRole: FamilyMember.UserRole = .supervisor
    /// العضو المختار — يُعيَّن بالدور عند الضغط على «إضافة»
    @State private var selectedMember: FamilyMember?
    @State private var isSaving = false
    @State private var filterCache = RegularMembersCache()

    /// نفس ترتيب المبدّل السابق: مشرف، مراقب، مدير
    private let roleOptions: [FamilyMember.UserRole] = [.supervisor, .monitor, .admin]

    /// نفس التصفية والترتيب — مع حفظ النتيجة حتى يتغيّر الأعضاء أو نص البحث:
    /// القائمة ~٢٤٠٠ عضو، والمربّع يُعاد رسمه كلما تغيّر ارتفاع القائمة الكسولة أثناء التمرير
    private var regularMembers: [FamilyMember] {
        let all = memberVM.allMembers
        if let cached = filterCache.result(for: all, query: searchText) { return cached }
        let result = all
            .filter { $0.role == .member && $0.isDeceased != true && $0.status != .frozen }
            .filter { member in
                searchText.isEmpty || member.fullName.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.fullName < $1.fullName }
        filterCache.store(result, for: all, query: searchText)
        return result
    }

    var body: some View {
        DSComposer(
            title: L10n.t("إضافة مدير/مشرف", "Add Admin/Supervisor"),
            subtitle: L10n.t("اختر الدور ثم العضو", "Choose a role, then a member"),
            icon: "person.badge.plus",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("إضافة", "Add"),
            actionIcon: "plus",
            canSubmit: selectedMember != nil,
            isBusy: isSaving,
            // من سيُمنح الدور — ظاهر دائماً فوق الزر حتى لو خرج العضو من نتائج البحث
            note: selectedMember.map { "\($0.displayFullName) ← \(roleLabel(selectedRole))" },
            // عضو مختار ولم يُعيَّن بعد → «إلغاء» يسأل قبل التجاهل، ولا يُسحب المربّع الطويل
            hasUnsavedChanges: selectedMember != nil,
            onSubmit: assignRole,
            onCancel: { dismiss() }
        ) {
            roleSection
            memberSection
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: الدور

    private var roleSection: some View {
        DSComposerSection(title: L10n.t("الدور", "Role"), icon: "person.badge.key.fill",
                          tint: AppSection.admin.ink, index: 0) {
            // اختيار مستوى الحساب — المبدّل الموحّد (`DSSegmentedSwitch`)
            DSSegmentedSwitch(options: roleOptions.map {
                                  DSSegmentOption(id: $0, title: roleLabel($0),
                                                  icon: RoleGuide.forRole($0)?.icon ?? "person.fill")
                              },
                              selection: $selectedRole, size: .regular)

            // مجال الدور المختار — ليعرف من يمنح الدور ما الذي يمنحه بالضبط
            // (ZStack: القديم والجديد يتداخلان أثناء التلاشي بدل أن يتكدّسا)
            if let guide = RoleGuide.forRole(selectedRole) {
                ZStack(alignment: .top) {
                    RoleScopeRowBox(guide: guide)
                        .id(selectedRole)
                        .transition(.opacity)
                }
            }
        }
    }

    /// نفس أسماء المبدّل السابق
    private func roleLabel(_ role: FamilyMember.UserRole) -> String {
        switch role {
        case .admin: return L10n.t("مدير", "Admin")
        case .monitor: return L10n.t("مراقب", "Monitor")
        default: return L10n.t("مشرف", "Supervisor")
        }
    }

    // MARK: العضو

    private var memberSection: some View {
        let members = regularMembers
        return DSComposerSection(title: L10n.t("العضو", "Member"), icon: "person.fill",
                                 tint: AppSection.admin.ink, trailing: selectedMember?.firstName, index: 1) {
            // البحث
            DSComposerField(icon: "magnifyingglass",
                            label: L10n.t("بحث", "Search"),
                            placeholder: L10n.t("بحث عن عضو...", "Search member..."),
                            text: $searchText)

            if members.isEmpty {
                emptyMembers
            } else {
                // كسولة — قائمة الأعضاء قد تكون طويلة
                LazyVStack(spacing: DS.Spacing.sm) {
                    ForEach(members) { member in
                        memberRow(member)
                    }
                }
            }
        }
    }

    private func memberRow(_ member: FamilyMember) -> some View {
        let isSelected = selectedMember?.id == member.id
        return Button {
            selectedMember = member
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "person.fill", tint: AppSection.admin.ink)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(member.displayFullName)
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                        .dsNameLines()

                    if let phone = member.phoneNumber, !phone.isEmpty {
                        Text(KuwaitPhone.display(phone))
                            .dsFieldFont(.subtitle)
                            .foregroundColor(DS.Color.fieldValue)
                            .monospacedDigit()
                    }
                }

                Spacer(minLength: 0)

                // للعين فقط — «محدّد» يُعلن من صفة isSelected
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .dsGlyph(DS.Glyph.xl, weight: .semibold)
                    .foregroundColor(isSelected ? AppSection.admin.ink : DS.Color.textTertiary.opacity(DS.Opacity.disabled))
                    .accessibilityHidden(true)
            }
            .dsRowBox()
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(AppSection.admin.ink.opacity(isSelected ? DS.Opacity.selectedStroke : 0),
                                  lineWidth: DS.Border.widthBold)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var emptyMembers: some View {
        DSEmptyView(L10n.t("لا يوجد أعضاء", "No members found"), style: .inline)
    }

    // MARK: التعيين — نفس الاستدعاء ثم الإغلاق

    private func assignRole() {
        guard let member = selectedMember, !isSaving else { return }
        isSaving = true
        Task {
            await memberVM.updateMemberRole(memberId: member.id, newRole: selectedRole)
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - ورقة تغيير الدور (طلب المالك)
//
// الدور صار مجال عمل لا درجة، فالتغيير صار اختيار مجال من بطاقات واضحة
// بدل أسهم «ترقية/تنزيل». كل خيار يعرض مجاله وأهم ما يقدر عليه.

struct ChangeRoleSheet: View {
    let member: FamilyMember
    /// يُستدعى عند التأكيد بالدور الجديد
    let onSelect: (FamilyMember.UserRole) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: FamilyMember.UserRole
    @State private var showConfirm = false

    private let options: [FamilyMember.UserRole] = [.admin, .monitor, .supervisor, .member]

    init(member: FamilyMember, onSelect: @escaping (FamilyMember.UserRole) -> Void) {
        self.member = member
        self.onSelect = onSelect
        _selected = State(initialValue: member.role)
    }

    var body: some View {
        // نفس هيكل المربّعات الموحّد (طلب المالك): العضو، ثم بطاقات الأدوار كصفوف
        // بعلامة اختيار — المختارة تعرض كل «يقدر» و«ما يقدر» — ثم «حفظ» يطلب التأكيد
        DSComposer(
            title: L10n.t("تغيير الدور", "Change Role"),
            subtitle: member.displayFullName,
            icon: "person.badge.key.fill",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            canSubmit: selected != member.role,
            // دور مختار غير دوره الحالي ولم يُحفظ → «إلغاء» يسأل قبل التجاهل (توصية أبل)
            hasUnsavedChanges: selected != member.role,
            onSubmit: { showConfirm = true },
            onCancel: { dismiss() }
        ) {
            memberSection
            rolesSection
        }
        .dsAlert(L10n.t("تأكيد تغيير الدور", "Confirm Role Change"), isPresented: $showConfirm) {
            Button(L10n.t("تأكيد", "Confirm")) {
                onSelect(selected)
                dismiss()
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t(
                "\(member.firstName) يصير «\(roleTitle(selected))» — \(RoleGuide.forRole(selected)?.mandate ?? "")",
                "\(member.firstName) becomes «\(roleTitle(selected))» — \(RoleGuide.forRole(selected)?.mandate ?? "")"
            ))
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: العضو ودوره الحالي

    private var memberSection: some View {
        DSComposerSection(title: L10n.t("العضو", "Member"), icon: "person.fill",
                          tint: AppSection.admin.ink, index: 0) {
            HStack(spacing: DS.Spacing.sm) {
                memberAvatar
                    .accessibilityHidden(true)   // الصورة زخرفة — الاسم يُقرأ بعدها

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(member.displayFullName)
                        .dsFieldFont(.headlineCompact)
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(2)
                    Text(L10n.t("دوره الحالي: ", "Current role: ") + roleTitle(member.role))
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                }
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .accessibilityElement(children: .combine)
        }
    }

    /// صورة العضو الموحّدة
    private var memberAvatar: some View {
        DSMemberAvatar(name: member.firstName, avatarUrl: member.avatarUrl,
                       size: DS.Icon.avatar, roleColor: AppSection.admin.ink)
    }

    // MARK: بطاقات الأدوار

    private var rolesSection: some View {
        DSComposerSection(title: L10n.t("اختر الدور", "Choose a role"), icon: "person.badge.key.fill",
                          tint: AppSection.admin.ink, index: 1) {
            VStack(spacing: DS.Spacing.sm) {
                ForEach(options, id: \.self) { role in
                    if let guide = RoleGuide.forRole(role) {
                        Button { selected = role } label: {
                            roleOption(role: role, guide: guide)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected == role ? .isSelected : [])
                    }
                }
            }
        }
    }

    /// بطاقة دور بشكل صفوف المربّعات: رمز الدور + اسمه + مجاله + علامة اختيار،
    /// والمختارة تتوسّع بكل ما يقدر عليه وما لا يقدر
    private func roleOption(role: FamilyMember.UserRole, guide: RoleGuide) -> some View {
        let isSelected = selected == role
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: guide.icon, tint: guide.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(guide.title)
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(guide.mandate)
                        .dsFieldFont(.calloutCompact)
                        .foregroundColor(DS.Color.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                // للعين فقط — «محدّد» يُعلن من صفة isSelected على البطاقة
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .dsGlyph(DS.Glyph.xl, weight: .semibold)
                    .foregroundColor(isSelected ? guide.color : DS.Color.textTertiary.opacity(DS.Opacity.disabled))
                    .accessibilityHidden(true)
            }

            if isSelected {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Rectangle()
                        .fill(DS.Color.textTertiary.opacity(DS.Opacity.border))
                        .frame(height: DS.Border.width)
                        .padding(.bottom, DS.Spacing.xxs)
                    scopeCaption(L10n.t("يقدر", "Can"), color: DS.Color.success)
                    ForEach(guide.can, id: \.self) { text in
                        RoleScopeLineRow(text: text, allowed: true)
                    }
                    if !guide.cannot.isEmpty {
                        scopeCaption(L10n.t("ما يقدر", "Cannot"), color: DS.Color.textTertiary)
                            .padding(.top, DS.Spacing.xxs)
                        ForEach(guide.cannot, id: \.self) { text in
                            RoleScopeLineRow(text: text, allowed: false)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(guide.color.opacity(isSelected ? DS.Opacity.selectedStroke : 0), lineWidth: DS.Border.widthBold)
        )
        .contentShape(Rectangle())
        .animation(DS.Anim.snappy, value: selected)
    }

    private func scopeCaption(_ text: String, color: Color) -> some View {
        Text(text)
            .dsFont(.label)
            .foregroundColor(color)
    }

    private func roleTitle(_ role: FamilyMember.UserRole) -> String {
        RoleGuide.forRole(role)?.title ?? L10n.t("عضو", "Member")
    }
}

// MARK: - ذاكرة تصفية الأعضاء (خاصة بهذا الملف)

/// آخر نتيجة لتصفية «الأعضاء العاديين» — تُعاد فقط إذا تغيّرت مصفوفة الأعضاء أو نص البحث.
/// مقارنة المصفوفة فورية ما دامت لم تتغيّر (نفس التخزين)، وعنصراً بعنصر عند أي تعديل.
private final class RegularMembersCache {
    private var source: [FamilyMember] = []
    private var query: String?
    private var cached: [FamilyMember] = []

    func result(for members: [FamilyMember], query: String) -> [FamilyMember]? {
        guard self.query == query, source == members else { return nil }
        return cached
    }

    func store(_ result: [FamilyMember], for members: [FamilyMember], query: String) {
        source = members
        self.query = query
        cached = result
    }
}

// MARK: - أسطر مجال الدور بخط المربّعات (خاصة بهذا الملف)

/// سطر «يقدر» / «ما يقدر» — نصوص `RoleGuide` نفسها
private struct RoleScopeLineRow: View {
    let text: String
    let allowed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.xsm) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .dsGlyph(DS.Glyph.sm)
                .foregroundColor(allowed ? DS.Color.success : DS.Color.textTertiary)
                .padding(.top, DS.Spacing.xxs)
            Text(text)
                .dsFieldFont(.calloutCompact)
                .foregroundColor(DS.Color.fieldValue)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        // القارئ الصوتي: العلامة (✓/✗) تحمل المعنى — تُقرأ «يقدر: …» أو «ما يقدر: …» سطراً واحداً
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((allowed ? L10n.t("يقدر", "Can") : L10n.t("ما يقدر", "Cannot")) + ": " + text)
    }
}

/// مجال الدور المختار في صندوق صف — المختصر نفسه الذي كان في `RoleScopeCard(compact:)`:
/// المجال، وأول سطرين «يقدر»، وأول «ما يقدر»
private struct RoleScopeRowBox: View {
    let guide: RoleGuide

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: guide.icon, tint: guide.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(guide.title)
                        .dsFieldFont(.label)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(guide.mandate)
                        .dsFieldFont(.bodyCompact)
                        .foregroundColor(DS.Color.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(Array(guide.can.prefix(2)), id: \.self) { text in
                    RoleScopeLineRow(text: text, allowed: true)
                }
                ForEach(Array(guide.cannot.prefix(1)), id: \.self) { text in
                    RoleScopeLineRow(text: text, allowed: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
    }
}
