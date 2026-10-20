import SwiftUI
import Supabase

// MARK: - Admin Tree Health View
/// واجهة صحة الشجرة — تكشف الأعضاء المشكلين (يتائم، بدون أسماء، روابط مكسورة)
///
/// بشكل «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠، `AdminPageKit`): رأس كحلي (رجوع، المشاكل بأنواعها أرقاماً، شرائح
/// الفلاتر بعددها) ← بطاقة «سلامة الشجرة» تصعد فوقه ← بحث ← صفوف الأعضاء بطاقات بيضاء داخل `List` (بقيت لأجل
/// أزرار السحب). الإجراءات والتأكيدات والمربّعات كما كانت تماماً.
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
        // الرأس (الأرقام والفلاتر) ← بطاقة السلامة ← البحث ← الأعضاء: قائمة واحدة تتمرّر معاً
        // (بقيت `List` لأجل أزرار السحب)
        AdminPage(header: header, lead: AnyView(leadCard), layout: .list, content: AnyView(listRows))
            .onChange(of: searchText) { _ in displayLimit = 20 }
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

    /// بطاقة أعلى الصفحة (تصعد فوق الرأس): الفحص، أو تعذّر التحميل، أو «الشجرة سليمة»، أو حلقة السلامة
    @ViewBuilder
    private var leadCard: some View {
        if isCheckingTree {
            AdminPageStateCard(.loading(L10n.t("جاري فحص الشجرة...", "Checking tree health...")))
        } else if membersFailed {
            AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                                      message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                      retry: { Task { await memberVM.fetchAllMembers(force: true) } }))
        } else if cachedIssueMembers.isEmpty {
            emptyState
        } else {
            healthScoreRow
                .adminCard()
        }
    }

    /// البحث ← عنوان الفلتر المختار ← صفوف الأعضاء بأزرار السحب ← «عرض المزيد»
    @ViewBuilder
    private var listRows: some View {
        if !isCheckingTree && !membersFailed && !cachedIssueMembers.isEmpty {
            let members = filteredMembers

            // Search
            DSSearchField(text: $searchText,
                          placeholder: L10n.t("بحث بالاسم أو الرقم...", "Search by name or phone..."),
                          tint: pageTint)
                .dsStaggerIn(2)
                .adminPageRow(top: DS.Hub.stackSpacing, bottom: DS.Spacing.xxs)

            // عنوان الفلتر المختار + تلميح السحب
            AdminSectionLabel(title: selectedFilter.label,
                              trailing: members.isEmpty ? nil
                                  : L10n.t("← سحب لإجراءات سريعة →", "← Swipe for quick actions →"))
                .dsStaggerIn(3)
                // العنوان يظهر مع الصفوف (بعد الفحص) — فتبدأ الصفوف بعده
                .onAppear(perform: startRowsCascade)
                .adminPageRow(top: DS.Spacing.xs, bottom: 0)

            if members.isEmpty {
                noResultsState
                    .adminPageRow(top: DS.Spacing.xs)
            } else {
                let visible = Array(members.prefix(displayLimit))
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, member in
                    let memberIssues = cachedMemberIssues[member.id] ?? []
                    memberRow(member: member)
                        // نمط الأخبار والديوانيات: أول ٧ تصعد تباعاً، وما يُبنى بالتمرير يظهر مباشرة
                        .dsCardCascade(index, appeared: appeared)
                        .adminPageRow()
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
                        .adminPageRow(top: DS.Spacing.sm, bottom: DS.Spacing.lg)
                }
            }
        }
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

    /// الرأس الكحلي: المشاكل بأنواعها أرقاماً (من الفحص المحلي نفسه، بلا طلبات جديدة) — «—» قبل اكتماله —
    /// والضغط على نوع يختار فلتره؛ وشرائح الفلاتر الخمسة بعددها
    private var header: AdminPageHeader {
        let ready = !isCheckingTree && !membersFailed
        func value(_ n: Int) -> String { AdminPageKPI.count(n, ready: ready) }
        func pick(_ f: TreeIssueFilter) -> AdminPageTap {
            .action { withAnimation(DS.Anim.snappy) { filterSelection.wrappedValue = f } }
        }
        return AdminPageHeader(
            title: L10n.t("صحة الشجرة", "Tree Health"),
            subtitle: L10n.t("أعضاء يحتاجون ربطاً أو تصحيحاً في الشجرة",
                             "Members who need a link or a fix in the tree"),
            glyph: "stethoscope",
            // الأنواع الثلاثة الأهم (السلامة الكلية في صفّ النسبة) — أربعة مربّعات تقصّ «رابط مكسور» بالخط الكبير
            kpis: [
                AdminPageKPI(value(cachedCounts[.orphan] ?? 0), TreeIssueFilter.orphan.label,
                             icon: TreeIssueFilter.orphan.icon, tint: DS.Hub.kpiHot, tap: pick(.orphan)),
                AdminPageKPI(value(cachedCounts[.brokenParent] ?? 0), TreeIssueFilter.brokenParent.label,
                             icon: TreeIssueFilter.brokenParent.icon, tint: DS.Hub.kpiLate, tap: pick(.brokenParent)),
                AdminPageKPI(value(cachedCounts[.duplicatePhone] ?? 0), TreeIssueFilter.duplicatePhone.label,
                             icon: TreeIssueFilter.duplicatePhone.icon, tint: DS.Hub.kpiMine, tap: pick(.duplicatePhone))
            ],
            chips: ready && !cachedIssueMembers.isEmpty ? filterChips : [])
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
        let shown = cachedIssueMembers.isEmpty ? 1 : min(0.99, score)
        return AdminScoreRow(progress: shown,
                             title: L10n.t("سلامة الشجرة", "Tree integrity"),
                             subtitle: L10n.t("بلا ملاحظات: \(cachedCleanCount) من \(cachedCheckedCount)",
                                              "No issues: \(cachedCleanCount) of \(cachedCheckedCount)"))
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

    /// شرائح الفلاتر فوق الرأس بعدد كل مشكلة
    private var filterChips: [AdminPageChip] {
        TreeIssueFilter.allCases.map { filter in
            let filterCount = cachedCounts[filter] ?? 0
            return AdminPageChip(id: filter.rawValue, title: filter.label,
                                 count: filterCount > 0 ? filterCount : nil, icon: filter.icon,
                                 selected: selectedFilter == filter) {
                withAnimation(DS.Anim.snappy) { filterSelection.wrappedValue = filter }
            }
        }
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

        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                // Avatar
                Text(displayName.isEmpty ? "?" : String(displayName.prefix(1)))
                    .dsFont(.rowTitle)
                    .foregroundColor(tint.dsReadableGlyph)
                    .frame(width: DS.Hub.iconSquare, height: DS.Hub.iconSquare)
                    .background(RoundedRectangle(cornerRadius: DS.Hub.iconSquareRadius, style: .continuous)
                        .fill(tint.dsReadableGlyph.opacity(DS.Opacity.tintFill)))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    // Name
                    Text(displayName.isEmpty ? L10n.t("بدون اسم", "No Name") : displayName)
                        .dsFont(.hubRow)
                        .foregroundColor(displayName.isEmpty ? DS.Color.textTertiary : DS.Color.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Phone
                    if hasPhone {
                        Text(phone)
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textTertiary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }

                Spacer(minLength: 0)

                // Role badge
                DSStatusChip(text: member.roleName, tint: member.roleColor)
                    .fixedSize()
            }

            // Issue tags — تبدأ تحت الاسم (بعد عمود الأيقونة ٣٦ + ٨)
            if !issues.isEmpty {
                issueTags(issues)
                    .padding(.leading, DS.Hub.iconSquare + DS.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Hub.cardPadding)
        .padding(.vertical, DS.Spacing.md)
        .adminCard(padding: nil)
        .accessibilityElement(children: .combine)
    }

    /// شارات المشاكل بلون كلٍّ منها — إن ضاق السطر تُحذف الأيقونات ثم تنزل تحت بعض
    private func issueTags(_ issues: [TreeIssueFilter]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.xs) {
                ForEach(issues, id: \.self) { tag in
                    DSStatusChip(text: tag.label, icon: tag.icon, tint: tag.color)
                }
            }
            HStack(spacing: DS.Spacing.xs) {
                ForEach(issues, id: \.self) { tag in
                    DSStatusChip(text: tag.label, tint: tag.color)
                }
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(issues, id: \.self) { tag in
                    DSStatusChip(text: tag.label, icon: tag.icon, tint: tag.color)
                }
            }
        }
    }

    // MARK: - Show More

    private func showMoreButton(remaining: Int) -> some View {
        // الشريحة الواحدة بلون الصفحة (مساحة ضغط ٤٤)
        AdminPillButton(title: L10n.t("عرض المزيد (\(remaining) متبقي)", "Show more (\(remaining) remaining)"),
                        icon: "chevron.down", style: .soft, height: DS.Hub.pillHeightCard) {
            displayLimit += 20
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        AdminPageStateCard(.empty(L10n.t("الشجرة سليمة!", "Tree is Healthy!"),
                                  message: L10n.t("ما في أعضاء مشكلين حالياً", "No problematic members found"),
                                  tint: DS.Color.success))
    }

    private var noResultsState: some View {
        AdminPageStateCard(.empty(
            L10n.t("لا توجد نتائج", "No Results"),
            message: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? L10n.t("لا أحد في «\(selectedFilter.label)» الآن", "Nobody in \(selectedFilter.label) right now")
                : L10n.t("جرّب اسماً آخر أو رقماً", "Try another name or number")))
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
                              icon: "person.text.rectangle.fill", tint: AppSection.admin.ink, index: 0) {
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
            DSFieldIcon(name: "phone.fill", tint: DS.Color.sea)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(L10n.t("رقم الهاتف", "Phone Number"))
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(phone)
                    .dsFieldFont(.body)
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
