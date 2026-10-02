import SwiftUI
import Supabase

// MARK: - Admin Tree Health View
/// واجهة صحة الشجرة — تكشف الأعضاء المشكلين (يتائم، بدون أسماء، روابط مكسورة)
///
/// بتصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧): بطاقة رأس بلون مجال «الشجرة
/// والأعضاء» وأرقامها الحيّة ← حلقة «سلامة الشجرة» ← بحث + فلاتر المشاكل بعددها ←
/// صفوف `.dsRowBox()` داخل `List` (بقيت لأجل أزرار السحب). الإجراءات والتأكيدات
/// والمربّعات كما كانت تماماً.
struct AdminTreeHealthView: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @State private var appeared = false
    @State private var searchText = ""
    @State private var selectedFilter: TreeIssueFilter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(initialFilter: TreeIssueFilter = .orphan) {
        self._selectedFilter = State(initialValue: initialFilter)
    }
    @State private var memberToLinkFather: FamilyMember?
    @State private var memberToEditName: FamilyMember?
    @State private var memberToToggleHidden: FamilyMember?
    @State private var showToggleHiddenConfirm = false
    @State private var memberToDelete: FamilyMember?
    @State private var showDeleteConfirm = false
    @State private var deleteFailureText: String?
    @State private var showDeleteFailure = false
    @State private var displayLimit = 20

    // MARK: - Cached data (computed once per allMembers change)
    @State private var cachedIssueMembers: [FamilyMember] = []
    @State private var cachedMemberIssues: [UUID: Set<TreeIssueFilter>] = [:]
    @State private var cachedCounts: [TreeIssueFilter: Int] = [:]
    /// مقام «سلامة الشجرة»: غير المجمّدين، ومن لا ملاحظة عليه منهم
    @State private var cachedCheckedCount = 0
    @State private var cachedCleanCount = 0

    /// لون مجال «الشجرة والأعضاء»
    private let pageTint = DS.Color.composerProject

    // MARK: - Filter Enum

    enum TreeIssueFilter: String, CaseIterable, Identifiable {
        case orphan, noName, brokenParent, hiddenFromTree, duplicatePhone

        var id: String { rawValue }

        var label: String {
            switch self {
            case .orphan:         return L10n.t("معلّق", "Unlinked")
            case .noName:         return L10n.t("بدون اسم", "No Name")
            case .brokenParent:   return L10n.t("رابط مكسور", "Broken Link")
            case .hiddenFromTree: return L10n.t("مخفي", "Hidden")
            case .duplicatePhone: return L10n.t("رقم مكرر", "Dup Phone")
            }
        }

        var icon: String {
            switch self {
            case .orphan:         return "person.fill.xmark"
            case .noName:         return "textformat.abc.dottedunderline"
            case .brokenParent:   return "link.badge.plus"
            case .hiddenFromTree: return "eye.slash"
            case .duplicatePhone: return "phone.badge.waveform"
            }
        }

        var color: Color {
            switch self {
            case .orphan:         return DS.Color.error
            case .noName:         return DS.Color.warning
            case .brokenParent:   return DS.Color.info
            case .hiddenFromTree: return DS.Color.textTertiary
            case .duplicatePhone: return DS.Color.neonPink
            }
        }
    }

    @State private var memberToClearPhone: FamilyMember?
    @State private var showClearPhoneConfirm = false

    // MARK: - Rebuild Cache (called once when data changes)

    private func rebuildCache() {
        let allActive = memberVM.allMembers.filter { $0.role != .pending && $0.status != .frozen }
        let fatherIds = Set(allActive.compactMap(\.fatherId))
        let activeIds = Set(allActive.map(\.id))

        var issues: [UUID: Set<TreeIssueFilter>] = [:]
        var result: [FamilyMember] = []
        var checked = 0

        for member in memberVM.allMembers where member.status != .frozen {
            checked += 1
            var memberIssues = Set<TreeIssueFilter>()

            // Orphan: بدون أب + بدون أبناء
            if member.fatherId == nil && !fatherIds.contains(member.id) && member.role != .pending {
                memberIssues.insert(.orphan)
            }

            // No name
            let name = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty || name == "بدون اسم" {
                memberIssues.insert(.noName)
            }

            // Broken parent
            if let fid = member.fatherId, !activeIds.contains(fid) {
                memberIssues.insert(.brokenParent)
            }

            // Hidden from tree
            if member.isHiddenFromTree {
                memberIssues.insert(.hiddenFromTree)
            }

            if !memberIssues.isEmpty {
                issues[member.id] = memberIssues
                result.append(member)
            }
        }

        // Duplicate phones
        let dupGroups = memberVM.duplicatePhoneGroups
        for group in dupGroups {
            for member in group {
                issues[member.id, default: []].insert(.duplicatePhone)
                if !result.contains(where: { $0.id == member.id }) {
                    result.append(member)
                }
            }
        }

        result.sort { $0.fullName < $1.fullName }

        // Compute counts
        var counts: [TreeIssueFilter: Int] = [:]
        for filter in TreeIssueFilter.allCases {
            counts[filter] = issues.values.filter { $0.contains(filter) }.count
        }

        cachedIssueMembers = result
        cachedMemberIssues = issues
        cachedCounts = counts
        // «سلامة الشجرة» — من فُحص (غير المجمّدين) ولا ملاحظة عليه
        cachedCheckedCount = checked
        cachedCleanCount = max(0, checked - result.filter { $0.status != .frozen }.count)
    }

    // MARK: - Filtered Data (lightweight — uses cache)

    private var filteredMembers: [FamilyMember] {
        var members = cachedIssueMembers.filter { cachedMemberIssues[$0.id]?.contains(selectedFilter) == true }
        if !searchText.isEmpty {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            members = members.filter {
                $0.fullName.localizedCaseInsensitiveContains(query)
                || ($0.phoneNumber ?? "").contains(query)
            }
        }
        return members
    }

    private func issueLabels(for member: FamilyMember) -> [TreeIssueFilter] {
        guard let issues = cachedMemberIssues[member.id] else { return [] }
        return TreeIssueFilter.allCases.filter { issues.contains($0) }
    }

    // MARK: - States

    /// أول فحص والأعضاء لم يُحمّلوا بعد (نفس شرط التحميل السابق)
    private var isCheckingTree: Bool { memberVM.isLoading && cachedIssueMembers.isEmpty }

    /// فشل تحميل الأعضاء ولا بيانات محلية — القائمة الفارغة هنا ليست «الشجرة سليمة»
    private var membersFailed: Bool { memberVM.membersLoadFailed && memberVM.allMembers.isEmpty }

    // MARK: - Body

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            // بطاقة الرأس ← الحلقة ← البحث والفلاتر ← الأعضاء: قائمة واحدة تتمرّر معاً
            // (بقيت `List` لأجل أزرار السحب)
            List {
                heroSection
                    .healthListRow(top: DS.Spacing.sm, bottom: DS.Spacing.sm)

                if isCheckingTree {
                    SysStateCard(icon: "heart.text.square.fill",
                                 title: L10n.t("جاري فحص الشجرة...", "Checking tree health..."),
                                 tint: pageTint,
                                 isLoading: true)
                        .padding(.top, DS.Spacing.xs)
                        .dsStaggerIn(1)
                        .healthListRow()
                } else if membersFailed {
                    SysStateCard(icon: "wifi.exclamationmark",
                                 title: L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                                 hint: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                 tint: DS.Color.error,
                                 actionTitle: L10n.t("إعادة المحاولة", "Retry"),
                                 action: { Task { await memberVM.fetchAllMembers(force: true) } })
                        .padding(.top, DS.Spacing.xs)
                        .dsStaggerIn(1)
                        .healthListRow()
                } else if cachedIssueMembers.isEmpty {
                    emptyState
                        .padding(.top, DS.Spacing.xs)
                        .dsStaggerIn(1)
                        .healthListRow()
                } else {
                    let members = filteredMembers

                    healthScoreRow
                        .dsStaggerIn(1)
                        .healthListRow()

                    // Search
                    DSSearchField(text: $searchText,
                                  placeholder: L10n.t("بحث بالاسم أو الرقم...", "Search by name or phone..."),
                                  tint: pageTint)
                        .dsStaggerIn(2)
                        .healthListRow(top: DS.Spacing.xs, bottom: 2)

                    filterChips
                        .dsStaggerIn(2)
                        .healthListRow(top: 0, bottom: 0)

                    // عنوان الفلتر المختار + تلميح السحب
                    SysSectionTitle(title: selectedFilter.label,
                                    icon: selectedFilter.icon,
                                    tint: selectedFilter.color,
                                    trailing: members.isEmpty ? nil
                                        : L10n.t("← سحب لإجراءات سريعة →", "← Swipe for quick actions →"))
                        .dsStaggerIn(3)
                        // العنوان يظهر مع الصفوف (بعد الفحص) — فتبدأ الصفوف بعده
                        .onAppear(perform: startRowsCascade)
                        .healthListRow(top: DS.Spacing.xs, bottom: 2)

                    if members.isEmpty {
                        noResultsState
                            .padding(.top, DS.Spacing.xs)
                            .healthListRow()
                    } else {
                        let visible = Array(members.prefix(displayLimit))
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, member in
                            let memberIssues = cachedMemberIssues[member.id] ?? []
                            memberRow(member: member)
                                // نمط الأخبار والديوانيات: أول ٧ تصعد تباعاً، وما يُبنى بالتمرير يظهر مباشرة
                                .dsCardCascade(index, appeared: appeared)
                                .healthListRow()
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        memberToDelete = member
                                        showDeleteConfirm = true
                                    } label: {
                                        Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                                    }
                                    if memberIssues.contains(.orphan) || memberIssues.contains(.brokenParent) {
                                        Button {
                                            memberToLinkFather = member
                                        } label: {
                                            Label(L10n.t("ربط أب", "Link Father"), systemImage: "person.line.dotted.person")
                                        }
                                        .tint(DS.Color.info)
                                    }
                                    if memberIssues.contains(.noName) {
                                        Button {
                                            memberToEditName = member
                                        } label: {
                                            Label(L10n.t("تعديل اسم", "Edit Name"), systemImage: "pencil")
                                        }
                                        .tint(DS.Color.warning)
                                    }
                                    if memberIssues.contains(.duplicatePhone) {
                                        Button {
                                            memberToClearPhone = member
                                            showClearPhoneConfirm = true
                                        } label: {
                                            Label(L10n.t("مسح الرقم", "Clear Phone"), systemImage: "phone.badge.minus")
                                        }
                                        .tint(DS.Color.neonPink)
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        memberToToggleHidden = member
                                        showToggleHiddenConfirm = true
                                    } label: {
                                        Label(
                                            member.isHiddenFromTree
                                                ? L10n.t("إظهار", "Show")
                                                : L10n.t("إخفاء", "Hide"),
                                            systemImage: member.isHiddenFromTree ? "eye" : "eye.slash"
                                        )
                                    }
                                    .tint(member.isHiddenFromTree ? DS.Color.success : DS.Color.textTertiary)
                                }
                        }

                        if displayLimit < members.count {
                            showMoreButton(remaining: members.count - displayLimit)
                                .healthListRow(top: DS.Spacing.xs, bottom: DS.Spacing.lg)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .environment(\.defaultMinListRowHeight, 0)
            .onChange(of: searchText) { _ in displayLimit = 20 }
        }
        .navigationTitle(L10n.t("صحة الشجرة", "Tree Health"))
        .navigationBarTitleDisplayMode(.inline)
        .dsAlert(
            L10n.t("تأكيد", "Confirm"),
            isPresented: $showToggleHiddenConfirm,
            presenting: memberToToggleHidden
        ) { member in
            Button(member.isHiddenFromTree
                   ? L10n.t("إظهار بالشجرة", "Show in Tree")
                   : L10n.t("إخفاء من الشجرة", "Hide from Tree")
            ) {
                Task { await toggleHidden(member) }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: { member in
            Text(member.isHiddenFromTree
                 ? L10n.t("إظهار \(member.fullName) بالشجرة؟", "Show \(member.fullName) in tree?")
                 : L10n.t("إخفاء \(member.fullName) من الشجرة؟", "Hide \(member.fullName) from tree?")
            )
        }
        .dsAlert(
            L10n.t("حذف العضو نهائياً", "Delete Member Permanently"),
            isPresented: $showDeleteConfirm,
            presenting: memberToDelete
        ) { member in
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                Task {
                    if await !memberVM.deleteMember(memberId: member.id) {
                        deleteFailureText = memberVM.errorMessage
                        showDeleteFailure = true
                    }
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: { member in
            Text(L10n.t(
                "هل أنت متأكد من حذف \(member.fullName)؟ هذا الإجراء لا يمكن التراجع عنه.",
                "Are you sure you want to delete \(member.fullName)? This action cannot be undone."
            ))
        }
        .dsAlert(L10n.t("لم يُحذف العضو", "Member Not Deleted"), isPresented: $showDeleteFailure) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(deleteFailureText ?? "")
        }
        .dsAlert(
            L10n.t("مسح رقم الهاتف", "Clear Phone Number"),
            isPresented: $showClearPhoneConfirm,
            presenting: memberToClearPhone
        ) { member in
            Button(L10n.t("مسح", "Clear"), role: .destructive) {
                Task {
                    _ = await memberVM.clearPhoneNumber(for: member.id)
                    rebuildCache()
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: { member in
            let phone = member.phoneNumber ?? ""
            Text(L10n.t(
                "مسح رقم \(KuwaitPhone.display(phone)) من \(member.fullName)؟",
                "Clear \(KuwaitPhone.display(phone)) from \(member.fullName)?"
            ))
        }
        // مربّعات بمنتصف الشاشة بدل الأوراق السفلية (طلب المالك)
        .dsTallBox(item: $memberToLinkFather) { member in   // قائمة أعضاء طويلة — مربّع طويل (توصية أبل)
            LinkFatherSheet(member: member, memberVM: memberVM)
        }
        .dsCenterBox(item: $memberToEditName) { member in
            EditNameSheet(member: member, memberVM: memberVM)
        }
        .onAppear {
            rebuildCache()
            if (cachedCounts[selectedFilter] ?? 0) == 0 {
                if let first = TreeIssueFilter.allCases.first(where: { (cachedCounts[$0] ?? 0) > 0 }) {
                    selectedFilter = first
                }
            }
        }
        .onChange(of: memberVM.membersVersion) { _ in
            rebuildCache()
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// الصفوف تدخل بعد أقسام الصفحة فوقها (الحلقة ← البحث والفلاتر ← العنوان = ٣)، فيبقى التسلسل:
    /// الرأس ← الأقسام ← الصفوف. مرة واحدة؛ «تقليل الحركة»: تلاشٍ فوري بلا انتظار.
    private func startRowsCascade() {
        guard !appeared else { return }
        guard !reduceMotion else { appeared = true; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.staggerDelay(4, base: DSMotion.sectionsOnPage)) {
            appeared = true
        }
    }

    // MARK: - Toggle Hidden

    private func toggleHidden(_ member: FamilyMember) async {
        let newValue = !member.isHiddenFromTree
        do {
            try await SupabaseConfig.client
                .from("profiles")
                .update(["is_hidden_from_tree": newValue])
                .eq("id", value: member.id.uuidString)
                .execute()
            await memberVM.fetchAllMembers(force: true)
        } catch {
            Log.error("Toggle hidden failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Hero

    /// ٣ أرقام حيّة من الفحص المحلي نفسه (بلا طلبات جديدة للسيرفر) — «—» قبل اكتماله
    private var heroSection: some View {
        let ready = !isCheckingTree && !membersFailed
        func value(_ n: Int) -> String { ready ? "\(n)" : "—" }
        return DSPageHero(
            title: L10n.t("صحة الشجرة", "Tree Health"),
            subtitle: L10n.t("أعضاء يحتاجون ربطاً أو تصحيحاً في الشجرة",
                             "Members who need a link or a fix in the tree"),
            icon: "heart.text.square.fill",
            tint: pageTint,
            stats: [
                DSHeroStat(value: value(cachedIssueMembers.count),
                           label: L10n.t("يحتاجون مراجعة", "Need review"),
                           icon: "exclamationmark.triangle.fill"),
                DSHeroStat(value: value(cachedCounts[.orphan] ?? 0),
                           label: TreeIssueFilter.orphan.label,
                           icon: TreeIssueFilter.orphan.icon),
                DSHeroStat(value: value(cachedCounts[.brokenParent] ?? 0),
                           label: TreeIssueFilter.brokenParent.label,
                           icon: TreeIssueFilter.brokenParent.icon)
            ]
        )
    }

    // MARK: - Health Score

    /// نسبة من فُحصوا بلا أي ملاحظة
    private var healthScore: Double {
        guard cachedCheckedCount > 0 else { return 1 }
        return max(0, min(1, Double(cachedCleanCount) / Double(cachedCheckedCount)))
    }

    /// حلقة «سلامة الشجرة» — لا تعرض ١٠٠٪ ما دامت هناك ملاحظة واحدة
    private var healthScoreRow: some View {
        let score = healthScore
        let pct = cachedIssueMembers.isEmpty ? 100 : min(99, Int((score * 100).rounded(.down)))
        let ringTint = score >= 0.9 ? DS.Color.success
            : (score >= 0.6 ? DS.Color.warning : DS.Color.error)
        return HStack(spacing: DS.Spacing.md) {
            SysRing(progress: score, tint: ringTint, lineWidth: 6, size: 56) {
                Text(L10n.t("\(pct)٪", "\(pct)%"))
                    .dsFieldFont(13, weight: .bold)
                    .foregroundColor(DS.Color.fieldLabel)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("سلامة الشجرة", "Tree integrity"))
                    .dsFieldFont(13.5, weight: .bold)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(L10n.t("بلا ملاحظات: \(cachedCleanCount) من \(cachedCheckedCount)",
                            "No issues: \(cachedCleanCount) of \(cachedCheckedCount)"))
                    .dsFieldFont(12)
                    .foregroundColor(DS.Color.fieldValue)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .dsRowBox()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.t(
            "سلامة الشجرة \(pct)٪، بلا ملاحظات: \(cachedCleanCount) من \(cachedCheckedCount)",
            "Tree integrity \(pct)%, no issues: \(cachedCleanCount) of \(cachedCheckedCount)"
        ))
    }

    // MARK: - Filter Chips

    /// اختيار الفلتر يرجع «عرض المزيد» للبداية — كما كان
    private var filterSelection: Binding<TreeIssueFilter> {
        Binding(
            get: { selectedFilter },
            set: { newValue in
                selectedFilter = newValue
                displayLimit = 20
            }
        )
    }

    private var filterChips: some View {
        DSFilterChips(
            options: TreeIssueFilter.allCases.map { filter in
                let filterCount = cachedCounts[filter] ?? 0
                return DSFilterOption(id: filter,
                                      title: filter.label,
                                      icon: filter.icon,
                                      count: filterCount > 0 ? filterCount : nil)
            },
            selection: filterSelection,
            tint: pageTint
        )
    }

    // MARK: - Member Row

    /// صف بإطار صفوف المربّعات: الحرف الأول بإطار أيقونة الحقل (بلون المشكلة المختارة) +
    /// الاسم (Plex 13.5 عريض) + الرقم (Plex 12) + شارة الدور، وتحتها شارات المشاكل.
    private func memberRow(member: FamilyMember) -> some View {
        let tint = selectedFilter.color
        let displayName = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = member.phoneNumber ?? ""
        let hasPhone = !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let issues = issueLabels(for: member)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                // Avatar
                Text(displayName.isEmpty ? "?" : String(displayName.prefix(1)))
                    .font(DS.Font.plex(14, weight: .bold))
                    .foregroundColor(tint)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.12)))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    // Name
                    Text(displayName.isEmpty ? L10n.t("بدون اسم", "No Name") : displayName)
                        .dsFieldFont(13.5, weight: .bold)
                        .foregroundColor(displayName.isEmpty ? DS.Color.textTertiary : DS.Color.fieldLabel)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Phone
                    if hasPhone {
                        Text(phone)
                            .dsFieldFont(12)
                            .foregroundColor(DS.Color.fieldValue)
                            .monospacedDigit()
                            .lineLimit(1)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }

                Spacer(minLength: 0)

                // Role badge
                SysStatusChip(text: member.roleName, tint: member.roleColor)
                    .fixedSize()
            }

            // Issue tags — تبدأ تحت الاسم (بعد عمود الأيقونة ٣٢ + ٨)
            if !issues.isEmpty {
                issueTags(issues)
                    .padding(.leading, 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
        .accessibilityElement(children: .combine)
    }

    /// شارات المشاكل بلون كلٍّ منها — إن ضاق السطر تُحذف الأيقونات ثم تنزل تحت بعض
    private func issueTags(_ issues: [TreeIssueFilter]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.xs) {
                ForEach(issues, id: \.self) { tag in
                    SysStatusChip(text: tag.label, icon: tag.icon, tint: tag.color)
                }
            }
            HStack(spacing: DS.Spacing.xs) {
                ForEach(issues, id: \.self) { tag in
                    SysStatusChip(text: tag.label, tint: tag.color)
                }
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(issues, id: \.self) { tag in
                    SysStatusChip(text: tag.label, icon: tag.icon, tint: tag.color)
                }
            }
        }
    }

    // MARK: - Show More

    private func showMoreButton(remaining: Int) -> some View {
        Button {
            displayLimit += 20
        } label: {
            HStack(spacing: 6) {
                Text(L10n.t(
                    "عرض المزيد (\(remaining) متبقي)",
                    "Show more (\(remaining) remaining)"
                ))
                .font(DS.Font.plex(12.5, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10.5, weight: .bold))
                    .accessibilityHidden(true)
            }
            .foregroundColor(pageTint)
            .padding(.horizontal, DS.Spacing.lg)
            .frame(minHeight: 44)
            .background(Capsule().fill(pageTint.opacity(0.10)))
            .overlay(Capsule().strokeBorder(pageTint.opacity(0.25), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(DSScaleButtonStyle())
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        SysStateCard(
            icon: "checkmark.shield.fill",
            title: L10n.t("الشجرة سليمة!", "Tree is Healthy!"),
            hint: L10n.t("ما في أعضاء مشكلين حالياً", "No problematic members found"),
            tint: DS.Color.success
        )
    }

    private var noResultsState: some View {
        SysStateCard(
            icon: "magnifyingglass",
            title: L10n.t("لا توجد نتائج", "No Results"),
            hint: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? L10n.t("لا أحد في «\(selectedFilter.label)» الآن", "Nobody in \(selectedFilter.label) right now")
                : L10n.t("جرّب اسماً آخر أو رقماً", "Try another name or number"),
            tint: DS.Color.textTertiary
        )
    }
}

// MARK: - صف القائمة الشفاف (نمط صفحات الإدارة)

private extension View {
    /// صف بلا خلفية ولا فاصل، بهوامش الصفحة — المحتوى نفسه يرسم صندوقه
    func healthListRow(top: CGFloat = 4, bottom: CGFloat = 4) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: DS.Spacing.lg, bottom: bottom, trailing: DS.Spacing.lg))
    }
}

// MARK: - Edit Name Sheet

/// تعديل الاسم — مربّع بمنتصف الشاشة بنفس تصميم مربّعات الإضافة (طلب المالك):
/// حقل الاسم الكامل + رقم العضو للتعرّف عليه، و«حفظ» / «إلغاء» أسفله.
struct EditNameSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @State private var fullName: String = ""
    @State private var isSaving = false

    /// الاسم الذي يُفتح عليه المربّع (نفس تعبئة onAppear) — للمقارنة بما كُتب
    private var startName: String {
        let name = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name == "بدون اسم") ? "" : name
    }

    var body: some View {
        DSComposer(
            title: L10n.t("تعديل الاسم", "Edit Name"),
            subtitle: L10n.t("عدّل بياناته في الشجرة", "Update the details in the tree"),
            icon: "pencil",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            // الحفظ لا يعمل باسم فارغ (نفس شرط saveName)
            canSubmit: !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            isBusy: isSaving,
            // اسم معدّل لم يُحفظ → «إلغاء» يسأل قبل التجاهل (توصية أبل)
            hasUnsavedChanges: fullName.trimmingCharacters(in: .whitespacesAndNewlines) != startName,
            onSubmit: { Task { await saveName() } },
            onCancel: { dismiss() }
        ) {
            DSComposerSection(title: L10n.t("البيانات الأساسية", "Basic Info"),
                              icon: "person.text.rectangle.fill", tint: DS.Color.primary, index: 0) {
                DSComposerField(icon: "person.fill",
                                label: L10n.t("الاسم الكامل", "Full Name"),
                                placeholder: L10n.t("أدخل الاسم الكامل...", "Enter full name..."),
                                text: $fullName)

                if let phone = member.phoneNumber, !phone.isEmpty {
                    phoneRow(phone)
                }
            }
        }
        .onAppear {
            fullName = startName
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// رقم العضو للقراءة فقط — يساعد على معرفة صاحب السجل بلا اسم
    private func phoneRow(_ phone: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "phone.fill", tint: DS.Color.success)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("رقم الهاتف", "Phone Number"))
                    .dsFieldFont(12, weight: .heavy)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(phone)
                    .dsFieldFont(14.5)
                    .foregroundColor(DS.Color.fieldValue)
                    .monospacedDigit()
                    .environment(\.layoutDirection, .leftToRight)
            }
            Spacer(minLength: 0)
        }
        .dsRowBox()
        .accessibilityElement(children: .combine)   // «رقم الهاتف، …» عنصراً واحداً
    }

    private func saveName() async {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        await memberVM.updateMemberName(memberId: member.id, fullName: trimmed)
        isSaving = false
        dismiss()
    }
}
