import SwiftUI

// MARK: - فريق الإدارة (تصميم صفحات الإدارة الموحّد — طلب المالك ٢٠٢٦-٠٩-٢٧)
//
// من الأعلى: بطاقة رأس بعدد كل دور ← بطاقة لكل دور (أيقونة الدور بلونه + اسمه + العدد) فيها
// أعضاؤه صفوفاً `.dsRowBox()` (الصورة · الاسم · مجال الدور · الرقم · شارة الدور) ← بطاقة
// «الأدوار وما يقدر عليه كل دور». بقيت `List` لأجل السحب «إزالة» على صف المسؤول، فبطاقة الدور
// تُرسم مقطّعةً خلف صفوفها (`TeamCardSegment`). الضغط على العضو يفتح «تغيير الدور» للمالك فقط،
// والمالك ونفسك لا يُغيَّران — كل الحراسات والمربّعات والتأكيدات كما كانت تماماً.

struct AdminModeratorsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @State private var appeared = false
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

    /// لون بلاطة «فريق الإدارة» في إعدادات النظام — رأس الصفحة يطابق البلاطة التي ضُغطت
    private let pageTint = DS.Color.actionNavy
    /// بطاقة الدور خلف صفوف القائمة — نفس مقاسات `DSComposerSection`: حشوة ١٢ ومسافة ١٠ بين الصفوف
    private let cardGap: CGFloat = DS.Spacing.md
    private let cardInset: CGFloat = DS.Spacing.lg + DS.Spacing.md
    private let rowHalfGap: CGFloat = (DS.Spacing.sm + 2) / 2

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

        return ZStack {
            DS.Color.background.ignoresSafeArea()

            // بطاقة الرأس ← بطاقات الأدوار ← دليل الأدوار: قائمة واحدة تتمرّر معاً
            // (بقيت `List` لأجل السحب «إزالة» على صف المسؤول)
            List {
                hero(team)
                    .teamListRow(top: DS.Spacing.sm, bottom: DS.Spacing.xs)

                teamContent(team)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            // تفاصيل الدور — مربّع عرض بمنتصف الشاشة (يُغلق أيضاً بالضغط خارجه)
            .dsCenterBox(item: $selectedRoleGuide, onBackgroundTap: { selectedRoleGuide = nil }) { guide in
                roleDetailBox(guide)
            }
        }
        .navigationTitle(L10n.t("فريق الإدارة", "Admin Team"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(DS.Font.scaled(22, weight: .medium))
                            .foregroundStyle(DS.Color.primary)
                    }
                    .accessibilityLabel(L10n.t("إضافة", "Add"))
                }
            }
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
            // «تقليل الحركة»: تلاشٍ هادئ فقط
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : DS.Anim.smooth.delay(0.15)) {
                appeared = true
            }
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

    // MARK: - محتوى القائمة

    @ViewBuilder
    private func teamContent(_ team: [FamilyMember]) -> some View {
        if isInitialLoading(team) {
            SysStateCard(icon: "person.3.fill",
                         title: L10n.t("جارٍ تحميل فريق الإدارة…", "Loading the admin team…"),
                         tint: pageTint,
                         isLoading: true)
                .dsStaggerIn(1)
                .teamListRow(top: DS.Spacing.md, bottom: DS.Spacing.xxxl)
        } else if loadFailed(team) {
            SysStateCard(icon: "wifi.exclamationmark",
                         title: L10n.t("تعذّر تحميل فريق الإدارة", "Couldn't load the admin team"),
                         hint: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                         tint: DS.Color.error,
                         actionTitle: L10n.t("إعادة المحاولة", "Retry"),
                         action: { Task { await loadTeam() } })
                .dsStaggerIn(1)
                .teamListRow(top: DS.Spacing.md, bottom: DS.Spacing.xxxl)
        } else if team.isEmpty {
            emptyState
                .dsStaggerIn(1)
                .teamListRow(top: DS.Spacing.md, bottom: DS.Spacing.xxxl)
        } else {
            let groups = roleGroups(team)
            ForEach(Array(groups.enumerated()), id: \.element.id) { offset, group in
                // رقم أول صف في البطاقة — الصفوف تتوالى عبر البطاقات بالترتيب الظاهر
                groupRows(group, index: offset + 1,
                          firstRow: groups.prefix(offset).reduce(0) { $0 + $1.members.count })
            }

            // قسم الصلاحيات
            rolesGuideSection(index: groups.count + 1)
                .teamListRow(top: cardGap, bottom: DS.Spacing.xxxl)
        }
    }

    // MARK: - بطاقة الرأس

    /// ٣ أرقام حيّة من الأعضاء المحمّلين أصلاً (بلا طلبات جديدة للسيرفر): عدد كل دور —
    /// المالك ضمن «المدراء» كما في بطاقتهم. «—» قبل اكتمال أول تحميل.
    private func hero(_ team: [FamilyMember]) -> some View {
        let pending = isInitialLoading(team) || loadFailed(team)
        func value(_ roles: Set<FamilyMember.UserRole>) -> String {
            pending ? "—" : "\(team.filter { roles.contains($0.role) }.count)"
        }
        return DSPageHero(
            title: L10n.t("فريق الإدارة", "Admin Team"),
            subtitle: isOwner
                ? L10n.t("اضغط على أي عضو لتغيير دوره", "Tap a member to change their role")
                : L10n.t("تتصفّح للقراءة — تغيير الأدوار للمالك", "Read-only — the owner assigns roles"),
            icon: "person.3.fill",
            tint: pageTint,
            stats: [
                DSHeroStat(value: value([.owner, .admin]),
                           label: L10n.t("المدراء", "Admins"),
                           icon: RoleGuide.forRole(.admin)?.icon),
                DSHeroStat(value: value([.monitor]),
                           label: L10n.t("المراقبين", "Monitors"),
                           icon: RoleGuide.forRole(.monitor)?.icon),
                DSHeroStat(value: value([.supervisor]),
                           label: L10n.t("المشرفين", "Supervisors"),
                           icon: RoleGuide.forRole(.supervisor)?.icon)
            ]
        )
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

    /// بطاقة دور واحدة كصفوف في القائمة: رأس البطاقة ثم أعضاؤها — كل صف يرسم جزءه من البطاقة
    /// (أعلى / وسط / أسفل) حتى يبقى السحب على صف العضو نفسه كما كان
    @ViewBuilder
    private func groupRows(_ group: RoleGroup, index: Int, firstRow: Int) -> some View {
        SysSectionTitle(title: group.title,
                        icon: group.icon,
                        tint: group.tint,
                        trailing: membersCountText(group.members.count))
            .dsStaggerIn(index)
            // العنوان يظهر مع الصفوف (بعد التحميل) — فتبدأ الصفوف بعده
            .onAppear(perform: startRowsCascade)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: cardGap + DS.Spacing.md, leading: cardInset,
                                      bottom: rowHalfGap, trailing: cardInset))
            .listRowBackground(cardSegment(.top, index: index))

        ForEach(Array(group.members.enumerated()), id: \.element.id) { i, member in
            let isLast = member.id == group.members.last?.id
            moderatorRow(member: member)
                // نمط الأخبار والديوانيات: أول ٧ صفوف تصعد تباعاً (عبر البطاقات)، والباقي مع السابع
                .dsCardCascade(firstRow + i, appeared: rowsAppeared)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: rowHalfGap, leading: cardInset,
                                          bottom: isLast ? DS.Spacing.md : rowHalfGap, trailing: cardInset))
                .listRowBackground(cardSegment(isLast ? .bottom : .middle, index: index))
        }
    }

    /// جزء البطاقة خلف الصف — يظهر مع محتواه بتلاشٍ فقط (مناسب لـ«تقليل الحركة» أيضاً)
    private func cardSegment(_ part: TeamCardSegment.Part, index: Int) -> some View {
        TeamCardSegment(part: part)
            .padding(.top, part == .top ? cardGap : 0)
            .padding(.horizontal, DS.Spacing.lg)
            .opacity(appeared ? 1 : 0)
            .animation(reduceMotion ? .easeInOut(duration: 0.2)
                                    : .easeOut(duration: 0.35).delay(0.1 + Double(index) * 0.06),
                       value: appeared)
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

    /// صف المسؤول بإطار صفوف المربّعات: الصورة (بلون دوره) + الاسم (Plex 13.5 عريض) + مجال الدور
    /// (Plex 12) + الرقم من اليسار، وشارة الدور (و«أنت») في الطرف، وسهم لمن يقدر المالك تغيير دوره
    private func moderatorRow(member: FamilyMember) -> some View {
        // المالك يظهر بنفس اسم المدير ولونه ومجاله — لا يتميّز عنه بصرياً (كما كان)
        let shownRole: FamilyMember.UserRole = member.role == .owner ? .admin : member.role
        let roleColor = shownRole.color
        let isSelf = member.id == authVM.currentUser?.id
        let canChange = isOwner && !isSelf && member.role != .owner

        return HStack(spacing: DS.Spacing.sm) {
            DSMemberAvatar(name: member.firstName, avatarUrl: member.avatarUrl, size: 40, roleColor: roleColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayFullName)
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let scope = RoleGuide.forRole(shownRole)?.mandate {
                    Text(scope)
                        .font(DS.Font.plex(12))
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                if let phone = member.phoneNumber, !phone.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(Self.isolatedLTR(KuwaitPhone.display(phone)))
                            .font(DS.Font.plex(11.5, weight: .medium))
                            .monospacedDigit()
                    }
                    .foregroundColor(DS.Color.textTertiary)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                SysStatusChip(text: member.roleName, tint: roleColor)
                if isSelf {
                    SysStatusChip(text: L10n.t("أنت", "You"), tint: DS.Color.info)
                }
            }
            .fixedSize()

            if canChange {
                SysChevron()
            }
        }
        .dsRowBox()
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

    private func rolesGuideSection(index: Int) -> some View {
        DSComposerSection(title: L10n.t("الأدوار وما يقدر عليه كل دور", "Roles and what each can do"),
                          icon: "person.badge.key.fill",
                          tint: pageTint,
                          index: index) {
            // ١) خريطة المجالات
            HStack(spacing: DS.Spacing.xs) {
                ForEach(Array(RoleDomain.all.enumerated()), id: \.offset) { _, domain in
                    domainTile(domain)
                }
            }

            // ٢) صف لكل دور — الضغط يفتح تفاصيله
            VStack(spacing: 6) {
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
        VStack(spacing: 4) {
            Image(systemName: domain.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(domain.color)
                .frame(width: 26, height: 26)
                .background(Circle().fill(domain.color.opacity(0.13)))
                .accessibilityHidden(true)
            Text(domain.title)
                .font(DS.Font.plex(11, weight: .bold))
                .foregroundColor(DS.Color.fieldLabel)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.8)
            Text(domain.roles.joined(separator: " · "))
                .font(DS.Font.plex(10, weight: .medium))
                .foregroundColor(DS.Color.fieldValue)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.sm)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(domain.color.opacity(0.28), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// صف الدور بإطار صفوف المربّعات: رمزه بلونه + اسمه + مجاله + عدد من يحملونه + سهم
    private func roleCompactRow(_ guide: RoleGuide) -> some View {
        let count = holdersCount(for: guide.title)
        return HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: guide.icon, tint: guide.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(guide.title)
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                Text(guide.mandate)
                    .font(DS.Font.plex(12))
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                // العضو: عدد الأحياء في الشجرة لا يعني أنهم يستخدمون التطبيق
                if guide.title == L10n.t("العضو", "Member"), let usage = usageStats {
                    Text(L10n.t("فعّالون (رقم + جهاز): \(usage.active)",
                                "Active (phone + device): \(usage.active)"))
                        .font(DS.Font.plex(11, weight: .semibold))
                        .foregroundColor(DS.Color.success)
                }
            }

            Spacer(minLength: 0)

            if let count, count > 0 {
                SysStatusChip(text: "\(count)", tint: guide.color)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(membersCountText(count))
            }
            SysChevron()
        }
        .dsRowBox()
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
            VStack(alignment: .leading, spacing: 8) {
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
        SysStateCard(
            icon: "person.3.fill",
            title: L10n.t("لا يوجد أعضاء في فريق الإدارة", "No admin team members"),
            hint: isOwner ? L10n.t("أضف مديراً أو مراقباً أو مشرفاً", "Add an admin, monitor or supervisor") : nil,
            tint: pageTint,
            actionTitle: isOwner ? L10n.t("إضافة", "Add") : nil,
            actionIcon: "plus",
            action: isOwner ? { showAddSheet = true } : nil
        )
    }
}

// MARK: - بطاقة الدور مقطّعة على صفوف القائمة (خاصة بهذا الملف)

/// نفس بطاقة `DSComposerSection` (سطح + حافة خفيفة + زوايا ١٦) لكن مقسومة على صفوف `List`:
/// كل صف يرسم جزءه — الأعلى بزاويتيه، الأوسط بحافتيه، الأسفل بزاويتيه — وما ليس له يُقصّ.
/// بهذا يبقى السحب («إزالة») على صف العضو نفسه كما كان، والبطاقة تبدو قطعة واحدة.
private struct TeamCardSegment: View {
    enum Part { case top, middle, bottom }
    let part: Part

    var body: some View {
        GeometryReader { geo in
            let overflow = DS.Radius.lg * 2
            let above: CGFloat = part == .top ? 0 : overflow
            let below: CGFloat = part == .bottom ? 0 : overflow
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(DS.Color.surface)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1))
                .frame(width: geo.size.width, height: geo.size.height + above + below)
                .offset(y: -above)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: - صف القائمة الشفاف (نمط صفحات الإدارة)

private extension View {
    /// صف بلا خلفية ولا فاصل، بهوامش الصفحة — المحتوى نفسه يرسم صندوقه
    func teamListRow(top: CGFloat = 4, bottom: CGFloat = 4) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: DS.Spacing.lg, bottom: bottom, trailing: DS.Spacing.lg))
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
    @Namespace private var roleNS

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
                          tint: DS.Color.primary, index: 0) {
            // اختيار مستوى الحساب
            HStack(spacing: 4) {
                ForEach(roleOptions, id: \.self) { role in
                    roleOption(role)
                }
            }
            // الخيار ٤٤ ضغطاً و٤٠ شكلاً — الهامش العمودي ٢ + نقطتا الضغط = نفس الإطار السابق (٤)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(DS.Color.background))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(DS.Color.textTertiary.opacity(0.14), lineWidth: 1))

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

    private func roleOption(_ role: FamilyMember.UserRole) -> some View {
        let isSelected = selectedRole == role
        let guide = RoleGuide.forRole(role)
        return Button {
            guard selectedRole != role else { return }
            if reduceMotion {
                selectedRole = role   // «تقليل الحركة»: المؤشّر يظهر في مكانه مباشرة
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { selectedRole = role }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: guide?.icon ?? "person.fill")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(isSelected ? .white : (guide?.color ?? DS.Color.primary))
                    .accessibilityHidden(true)
                Text(roleLabel(role))
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(isSelected ? .white : DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DSActionFill.style())
                        .matchedGeometryEffect(id: "role-pill", in: roleNS)
                }
            }
            // مساحة ضغط ٤٤ (توصية أبل) — المؤشّر الظاهر ٤٠ كما هو
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                                 tint: DS.Color.primary, trailing: selectedMember?.firstName, index: 1) {
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
                DSFieldIcon(name: "person.fill", tint: DS.Color.primary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayFullName)
                        .font(DS.Font.plex(14, weight: .bold))
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(1)

                    if let phone = member.phoneNumber, !phone.isEmpty {
                        Text(KuwaitPhone.display(phone))
                            .font(DS.Font.plex(12))
                            .foregroundColor(DS.Color.fieldValue)
                            .monospacedDigit()
                    }
                }

                Spacer(minLength: 0)

                // للعين فقط — «محدّد» يُعلن من صفة isSelected
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? DS.Color.primary : DS.Color.textTertiary.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .dsRowBox()
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Color.primary.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var emptyMembers: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "person.slash")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)
            Text(L10n.t("لا يوجد أعضاء", "No members found"))
                .font(DS.Font.plex(13, weight: .semibold))
                .foregroundColor(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.md)
        .dsRowBox()
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
                          tint: DS.Color.primary, index: 0) {
            HStack(spacing: DS.Spacing.sm) {
                memberAvatar
                    .accessibilityHidden(true)   // الصورة زخرفة — الاسم يُقرأ بعدها

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayFullName)
                        .font(DS.Font.plex(14.5, weight: .bold))
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(2)
                    Text(L10n.t("دوره الحالي: ", "Current role: ") + roleTitle(member.role))
                        .font(DS.Font.plex(12))
                        .foregroundColor(DS.Color.fieldValue)
                }
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .accessibilityElement(children: .combine)
        }
    }

    private var memberAvatar: some View {
        Group {
            if let avatar = member.avatarUrl, let url = URL(string: avatar) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: { DS.Color.mutedBackground }
            } else {
                ZStack {
                    DS.Color.primary.opacity(0.14)
                    Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    // MARK: بطاقات الأدوار

    private var rolesSection: some View {
        DSComposerSection(title: L10n.t("اختر الدور", "Choose a role"), icon: "person.badge.key.fill",
                          tint: DS.Color.primary, index: 1) {
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(guide.title)
                        .font(DS.Font.plex(13.5, weight: .heavy))
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(guide.mandate)
                        .font(DS.Font.plex(12.5))
                        .foregroundColor(DS.Color.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                // للعين فقط — «محدّد» يُعلن من صفة isSelected على البطاقة
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? guide.color : DS.Color.textTertiary.opacity(0.5))
                    .accessibilityHidden(true)
            }

            if isSelected {
                VStack(alignment: .leading, spacing: 5) {
                    Rectangle()
                        .fill(DS.Color.textTertiary.opacity(0.12))
                        .frame(height: 1)
                        .padding(.bottom, 3)
                    scopeCaption(L10n.t("يقدر", "Can"), color: DS.Color.success)
                    ForEach(guide.can, id: \.self) { text in
                        RoleScopeLineRow(text: text, allowed: true)
                    }
                    if !guide.cannot.isEmpty {
                        scopeCaption(L10n.t("ما يقدر", "Cannot"), color: DS.Color.textTertiary)
                            .padding(.top, 2)
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
                .strokeBorder(guide.color.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .animation(DS.Anim.snappy, value: selected)
    }

    private func scopeCaption(_ text: String, color: Color) -> some View {
        Text(text)
            .font(DS.Font.plex(12, weight: .heavy))
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
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(allowed ? DS.Color.success : DS.Color.textTertiary.opacity(0.8))
                .padding(.top, 2)
            Text(text)
                .font(DS.Font.plex(12.5))
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(guide.title)
                        .font(DS.Font.plex(12, weight: .heavy))
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(guide.mandate)
                        .font(DS.Font.plex(13.5))
                        .foregroundColor(DS.Color.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 5) {
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
