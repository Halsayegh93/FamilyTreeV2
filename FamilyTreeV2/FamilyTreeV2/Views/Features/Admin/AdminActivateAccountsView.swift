import SwiftUI
import PhotosUI

struct AdminActivateAccountsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @State private var appeared = false
    @State private var searchText = ""
    @State private var selectedFilter: MemberFilter = .notActivated
    @State private var memberToActivate: FamilyMember?
    @State private var showActivateConfirm = false
    @State private var memberToEditPhone: FamilyMember?
    @State private var memberToEditBirthDate: FamilyMember?

    // Selection mode for bulk gender update
    @State private var isSelectionMode = false
    @State private var selectedMembers: Set<UUID> = []
    @State private var memberToEdit: FamilyMember?
    @State private var showGenderConfirm = false
    @State private var pendingGender: String = "male"
    @State private var genderUpdateResult: String?
    @State private var showGenderResult = false
    @State private var displayLimit = 20
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// لون مجال «الشجرة والأعضاء»
    private let stationTint = DS.Color.composerProject

    /// نوع النقص المطلوب التركيز عليه — يُمرَّر من بطاقات «جودة البيانات»
    enum IssueFocus: String, CaseIterable {
        case all, noPhone, noBirthDate, noFather, noGender, noPhoto, deceasedNoDeathDate

        var label: String {
            switch self {
            case .all:                 return L10n.t("كل النواقص", "All issues")
            case .noPhone:             return L10n.t("بلا رقم هاتف", "No phone")
            case .noBirthDate:         return L10n.t("بلا تاريخ ميلاد", "No birth date")
            case .noFather:            return L10n.t("بلا أب مرتبط", "No linked father")
            case .noGender:            return L10n.t("بلا جنس محدّد", "No gender")
            case .noPhoto:             return L10n.t("بلا صورة", "No photo")
            case .deceasedNoDeathDate: return L10n.t("متوفّى بلا تاريخ وفاة", "Deceased, no death date")
            }
        }
    }

    @Binding var focus: IssueFocus

    init(focus: Binding<IssueFocus> = .constant(.all)) {
        self._focus = focus
    }

    /// وضع العمل — «محطة» تعرض عضواً واحداً بكل نواقصه كأزرار صريحة،
    /// و«قائمة» هو التصفّح القديم بالسحب. المحطة هي الافتراضي لأن الإجراءات ظاهرة.
    enum WorkMode { case station, list }
    @State private var workMode: WorkMode = .station
    @State private var stationCursor = 0
    @State private var resolvedCount = 0
    @State private var memberToEditGender: FamilyMember?
    @State private var memberToEditPhoto: FamilyMember?
    @State private var memberToEditDeathDate: FamilyMember?

    // MARK: - Combined Filter

    enum MemberFilter: String, CaseIterable {
        case notActivated, noBirthDate, noFather, noGender

        /// الفلاتر الظاهرة حالياً — لتفعيل noGender أضفها هنا
        static let visible: [MemberFilter] = [.notActivated, .noBirthDate, .noFather]

        var label: String {
            switch self {
            case .notActivated: return L10n.t("بدون هاتف", "No Phone")
            case .noBirthDate:  return L10n.t("بدون ميلاد", "No Birth Date")
            case .noFather:     return L10n.t("بدون أب", "No Father")
            case .noGender:     return L10n.t("بدون جنس", "No Gender")
            }
        }

        var icon: String {
            switch self {
            case .notActivated: return "phone.badge.waveform"
            case .noBirthDate:  return "calendar.badge.exclamationmark"
            case .noFather:     return "person.line.dotted.person"
            case .noGender:     return "person.fill.questionmark"
            }
        }

        var color: Color {
            switch self {
            case .notActivated: return DS.Color.error
            case .noBirthDate:  return DS.Color.warning
            case .noFather:     return DS.Color.info
            case .noGender:     return DS.Color.accent
            }
        }
    }

    // MARK: - Data

    /// All living non-pending members that have at least one issue
    private var allIssueMembers: [FamilyMember] {
        memberVM.allMembers
            .filter { $0.role != .pending && $0.isDeceased != true }
            .filter { memberHasAnyIssue($0) }
            .sorted {
                let a = $0.firstName.trimmingCharacters(in: .whitespaces)
                let b = $1.firstName.trimmingCharacters(in: .whitespaces)
                if a != b { return a.localizedStandardCompare(b) == .orderedAscending }
                return $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
            }
    }

    /// الأعضاء المطابقون للتركيز الحالي
    private var membersMatchingFocus: [FamilyMember] {
        func sortAlpha(_ list: [FamilyMember]) -> [FamilyMember] {
            list.sorted {
                let a = $0.firstName.trimmingCharacters(in: .whitespaces)
                let b = $1.firstName.trimmingCharacters(in: .whitespaces)
                if a != b { return a.localizedStandardCompare(b) == .orderedAscending }
                return $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
            }
        }
        func isBlank(_ v: String?) -> Bool {
            (v ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }

        switch focus {
        case .all:
            return allIssueMembers
        case .deceasedNoDeathDate:
            return sortAlpha(memberVM.allMembers.filter {
                $0.isDeceased == true && isBlank($0.deathDate) && $0.deathDateUnknown != true
            })
        case .noPhone:
            return sortAlpha(memberVM.allMembers.filter { $0.isDeceased != true && hasNoPhone($0) })
        case .noBirthDate:
            return sortAlpha(memberVM.allMembers.filter { $0.isDeceased != true && isMissingBirthDate($0) })
        case .noFather:
            return sortAlpha(memberVM.allMembers.filter { $0.isDeceased != true && isMissingFather($0) })
        case .noGender:
            return sortAlpha(memberVM.allMembers.filter { $0.isDeceased != true && isMissingGender($0) })
        case .noPhoto:
            // أصحاب الحسابات فقط — بقية أفراد الشجرة ليسوا مستخدمين وصورهم غير متوقّعة
            return sortAlpha(memberVM.allMembers.filter {
                $0.isDeceased != true && !isBlank($0.phoneNumber)
                && isBlank($0.avatarUrl) && $0.avatarUnavailable != true
            })
        }
    }

    private func memberHasAnyIssue(_ m: FamilyMember) -> Bool {
        isNotActivated(m) || isMissingBirthDate(m) || isMissingFather(m) || isMissingGender(m)
    }

    // Individual checks
    private func isNotActivated(_ m: FamilyMember) -> Bool {
        // غير مفعّل = حالة pending، أو بدون رقم هاتف (ما يقدر يسجل دخول)
        m.status == nil || m.status == .pending || hasNoPhone(m)
    }

    private func hasNoPhone(_ m: FamilyMember) -> Bool {
        m.phoneNumber == nil || (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isMissingBirthDate(_ m: FamilyMember) -> Bool {
        m.birthDate == nil || (m.birthDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isMissingFather(_ m: FamilyMember) -> Bool {
        m.fatherId == nil
    }

    private func isMissingGender(_ m: FamilyMember) -> Bool {
        m.gender == nil || (m.gender ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Counts per filter
    private func count(for filter: MemberFilter) -> Int {
        allIssueMembers.filter { matches(member: $0, filter: filter) }.count
    }

    private func matches(member: FamilyMember, filter: MemberFilter) -> Bool {
        switch filter {
        case .notActivated: return isNotActivated(member)
        case .noBirthDate:  return isMissingBirthDate(member)
        case .noFather:     return isMissingFather(member)
        case .noGender:     return isMissingGender(member)
        }
    }

    private var filteredMembers: [FamilyMember] {
        var members = allIssueMembers.filter { matches(member: $0, filter: selectedFilter) }
        if !searchText.isEmpty {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            members = members.filter { $0.fullName.localizedCaseInsensitiveContains(query) }
        }
        return members
    }

    /// نوع المشكلة التفصيلية (لعرض التاقات على كل عضو)
    enum IssueTag: Hashable {
        case notActivated
        case noPhone
        case noBirthDate
        case noFather

        var label: String {
            switch self {
            case .notActivated: return L10n.t("بدون هاتف", "No Phone")
            case .noPhone:      return L10n.t("بدون هاتف", "No Phone")
            case .noBirthDate:  return L10n.t("بدون ميلاد", "No Birth Date")
            case .noFather:     return L10n.t("بدون أب", "No Father")
            }
        }

        var icon: String {
            switch self {
            case .notActivated: return "person.badge.minus"
            case .noPhone:      return "phone.badge.plus"
            case .noBirthDate:  return "calendar.badge.exclamationmark"
            case .noFather:     return "person.line.dotted.person"
            }
        }

        var color: Color {
            switch self {
            case .notActivated: return DS.Color.error
            case .noPhone:      return DS.Color.error
            case .noBirthDate:  return DS.Color.warning
            case .noFather:     return DS.Color.info
            }
        }
    }

    /// Returns all issue tags for a given member
    private func issueLabels(for m: FamilyMember) -> [IssueTag] {
        var issues: [IssueTag] = []
        // إذا pending وعنده هاتف → tag "غير مفعل" فقط
        // إذا بدون هاتف → tag "بدون هاتف" (يغني عن "غير مفعل")
        if hasNoPhone(m) {
            issues.append(.noPhone)
        } else if isNotActivated(m) {
            issues.append(.notActivated)
        }
        if isMissingBirthDate(m) { issues.append(.noBirthDate) }
        if isMissingFather(m)    { issues.append(.noFather) }
        return issues
    }

    // MARK: - Body

    var body: some View {
        // صفحة واحدة تتمرّر: بطاقة الرأس ← المحطة (بطاقة عضو + إجراءاته) — طلب المالك ٢٠٢٦-٠٩-٢٧
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.md) {
                stationHero
                    .padding(.horizontal, DS.Spacing.lg)

                if memberVM.isLoading && memberVM.allMembers.isEmpty {
                    SysStateCard(icon: "person.crop.circle.badge.exclamationmark",
                                 title: L10n.t("جاري فحص البيانات...", "Checking data..."),
                                 tint: stationTint,
                                 isLoading: true)
                        .padding(.horizontal, DS.Spacing.lg)
                } else if allIssueMembers.isEmpty {
                    emptyState
                        .padding(.horizontal, DS.Spacing.lg)
                } else {
                    stationView
                }
            }
            .padding(.top, DS.Spacing.sm)
            .padding(.bottom, DS.Spacing.xxxl)
        }
        .background(DS.Color.background.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if selectedFilter == .noGender && !filteredMembers.isEmpty {
                    Button {
                        withAnimation(DS.Anim.snappy) {
                            isSelectionMode.toggle()
                            if !isSelectionMode {
                                selectedMembers.removeAll()
                            }
                        }
                    } label: {
                        Text(isSelectionMode
                             ? L10n.t("إلغاء", "Cancel")
                             : L10n.t("تحديد", "Select"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.primary)
                    }
                }
            }
        }
        .dsAlert(
            L10n.t("تفعيل الحساب", "Activate Account"),
            isPresented: $showActivateConfirm,
            presenting: memberToActivate
        ) { member in
            Button(L10n.t("تفعيل", "Activate")) {
                Task { await activateMember(member) }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: { member in
            Text(L10n.t(
                "تفعيل حساب \(member.fullName)؟",
                "Activate \(member.fullName)'s account?"
            ))
        }
        .dsAlert(
            L10n.t("تأكيد تحديث الجنس", "Confirm Gender Update"),
            isPresented: $showGenderConfirm
        ) {
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            Button(
                pendingGender == "male"
                    ? L10n.t("تعيين ذكر", "Set Male")
                    : L10n.t("تعيين أنثى", "Set Female")
            ) {
                let ids = selectedMembers
                let gender = pendingGender
                withAnimation(DS.Anim.snappy) {
                    selectedMembers.removeAll()
                    isSelectionMode = false
                }
                Task {
                    let count = await memberVM.bulkUpdateGender(memberIds: ids, gender: gender)
                    let genderText = gender == "male" ? L10n.t("ذكر", "male") : L10n.t("أنثى", "female")
                    genderUpdateResult = L10n.t(
                        "تم تحديث \(count) عضو إلى \(genderText)",
                        "Updated \(count) members to \(genderText)"
                    )
                    showGenderResult = true
                }
            }
        } message: {
            let genderText = pendingGender == "male" ? L10n.t("ذكر", "male") : L10n.t("أنثى", "female")
            Text(L10n.t(
                "هل تريد تعيين \(selectedMembers.count) عضو كـ \(genderText)؟",
                "Set \(selectedMembers.count) members as \(genderText)?"
            ))
        }
        .dsAlert(L10n.t("تم التحديث", "Updated"), isPresented: $showGenderResult) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(genderUpdateResult ?? "")
        }
        // مربّعات المحطة بمنتصف الشاشة بدل الأوراق السفلية (طلب المالك)
        .dsCenterBox(item: $memberToEditPhone) { member in
            PendingMemberPhoneSheet(member: member, activateOnSave: true)
                .environmentObject(adminRequestVM)
        }
        .dsCenterBox(item: $memberToEditBirthDate) { member in
            EditBirthDateSheet(member: member, memberVM: memberVM)
        }
        .dsTallBox(item: $memberToEdit) { member in   // قائمة أعضاء طويلة — مربّع طويل (توصية أبل)
            LinkFatherSheet(member: member, memberVM: memberVM)
        }
        .dsCenterBox(item: $memberToEditGender) { member in
            EditGenderSheet(member: member, memberVM: memberVM)
        }
        .dsCenterBox(item: $memberToEditPhoto) { member in
            EditMemberPhotoSheet(member: member, memberVM: memberVM)
        }
        .dsCenterBox(item: $memberToEditDeathDate) { member in
            EditDeathDateSheet(member: member, memberVM: memberVM)
        }
        .onChange(of: memberVM.allMembers.count) { _ in rebuildStationPool() }
        .onChange(of: focus) { _ in
            stationCursor = 0
            rebuildStationPool()
        }
        .onChange(of: selectedFilter) { _ in
            displayLimit = 20
            // Exit selection mode when switching filters
            if isSelectionMode {
                isSelectionMode = false
                selectedMembers.removeAll()
            }
        }
        .onAppear {
            withAnimation(DS.Anim.smooth.delay(0.15)) {
                appeared = true
            }
            if stationPool.isEmpty { rebuildStationPool() }
            // اختر أول فلتر متاح إذا الفلتر الافتراضي فارغ
            if count(for: selectedFilter) == 0, let first = availableFilters.first {
                selectedFilter = first
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// وضع «القائمة» القديم (تصفّح بالسحب + تحديد جماعي للجنس) — مخفي منذ صارت «المحطة»
    /// هي الوضع الوحيد (كان خلف `if false`)؛ بقي كما هو لو أُعيد.
    private var legacyListMode: some View {
        VStack(spacing: 0) {
            // Swipe hint
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "hand.draw")
                    .font(DS.Font.scaled(11, weight: .medium))
                Text(L10n.t(
                    "← سحب يمين: هاتف / ميلاد  •  سحب يسار: ربط أب / تفعيل →",
                    "← Swipe right: Phone / Birth  •  Swipe left: Father / Activate →"
                ))
                .font(DS.Font.caption2)
            }
            .foregroundColor(DS.Color.textTertiary)
            .padding(.horizontal, DS.Spacing.lg)

            // Search
            searchBar
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.xs)

            if filteredMembers.isEmpty {
                noResultsState
            } else {
                List {
                    let visible = Array(filteredMembers.prefix(displayLimit))
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, member in
                        if isSelectionMode {
                            Button {
                                withAnimation(DS.Anim.snappy) {
                                    toggleSelection(member)
                                }
                            } label: {
                                HStack(spacing: DS.Spacing.md) {
                                    selectionCheckbox(for: member)
                                    memberRow(member: member, index: index)
                                }
                            }
                            .buttonStyle(DSScaleButtonStyle())
                        } else {
                            memberRow(member: member, index: index)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if hasNoPhone(member) {
                                        Button {
                                            memberToEditPhone = member
                                        } label: {
                                            Label(L10n.t("هاتف", "Phone"), systemImage: "phone.badge.plus")
                                        }
                                        .tint(DS.Color.primary)
                                    }
                                    if isMissingBirthDate(member) {
                                        Button {
                                            memberToEditBirthDate = member
                                        } label: {
                                            Label(L10n.t("ميلاد", "Birth"), systemImage: "calendar.badge.plus")
                                        }
                                        .tint(DS.Color.warning)
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if isMissingFather(member) {
                                        Button {
                                            memberToEdit = member
                                        } label: {
                                            Label(L10n.t("ربط أب", "Link Father"), systemImage: "person.line.dotted.person")
                                        }
                                        .tint(DS.Color.info)
                                    }
                                    if isNotActivated(member) {
                                        Button {
                                            memberToActivate = member
                                            showActivateConfirm = true
                                        } label: {
                                            Label(L10n.t("تفعيل", "Activate"), systemImage: "checkmark.circle.fill")
                                        }
                                        .tint(DS.Color.success)
                                    }
                                }
                        }
                    }

                    if displayLimit < stationPool.count {
                        Button {
                            displayLimit += 20
                        } label: {
                            HStack {
                                Spacer()
                                Text(L10n.t(
                                    "عرض المزيد (\(stationPool.count - displayLimit) متبقي)",
                                    "Show more (\(stationPool.count - displayLimit) remaining)"
                                ))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.primary)
                                Spacer()
                            }
                            .padding(.vertical, DS.Spacing.sm)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            // Selection action bar
            if isSelectionMode {
                selectionActionBar
            }
        }
    }

    // MARK: - محطة الاستكمال

    /// مبدّل الوضع — محطة (إجراءات ظاهرة) أو قائمة (تصفّح وسحب)
    private var modeSwitcher: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach([WorkMode.station, WorkMode.list], id: \.self) { mode in
                let isOn = workMode == mode
                Button {
                    withAnimation(DS.Anim.snappy) { workMode = mode }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode == .station ? "bolt.badge.checkmark" : "list.bullet")
                            .font(DS.Font.scaled(11, weight: .semibold))
                        Text(mode == .station ? L10n.t("محطة", "Station") : L10n.t("قائمة", "List"))
                            .font(DS.Font.scaled(12, weight: .semibold))
                    }
                    .foregroundColor(isOn ? DS.Color.textOnPrimary : DS.Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(isOn ? DS.Color.primary : DS.Color.surface))
                    .overlay(
                        Capsule().strokeBorder(
                            isOn ? Color.clear : DS.Color.textTertiary.opacity(0.15),
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(DSScaleButtonStyle())
            }
        }
    }

    /// مجموعة المحطة — تُبنى مرة واحدة بدل إعادة فلترة آلاف الأعضاء عند كل رسم
    @State private var stationPool: [FamilyMember] = []

    private func rebuildStationPool() {
        let pool = membersMatchingFocus
        stationPool = pool
        if stationCursor >= pool.count { stationCursor = max(0, pool.count - 1) }
    }

    /// العضو المعروض حالياً في المحطة
    private var stationMember: FamilyMember? {
        let pool = stationPool
        guard !pool.isEmpty else { return nil }
        return pool[min(stationCursor, pool.count - 1)]
    }

    // MARK: - بطاقة الرأس

    /// أرقام حيّة بمرور واحد (بلا فرز) على نفس مجموعة النواقص: بلا رقم، بلا ميلاد
    private var heroCounts: (noPhone: Int, noBirth: Int) {
        var noPhone = 0, noBirth = 0
        for m in memberVM.allMembers where m.role != .pending && m.isDeceased != true && memberHasAnyIssue(m) {
            if hasNoPhone(m) { noPhone += 1 }
            if isMissingBirthDate(m) { noBirth += 1 }
        }
        return (noPhone, noBirth)
    }

    private var stationHero: some View {
        let loading = memberVM.isLoading && memberVM.allMembers.isEmpty
        let counts = heroCounts
        return DSPageHero(
            title: L10n.t("استكمال الحسابات", "Complete Accounts"),
            subtitle: L10n.t("عضو واحد في كل مرة — أكمل نواقصه ثم اسحب للتالي",
                             "One member at a time — fill the gaps, then swipe to the next"),
            icon: "person.crop.circle.badge.exclamationmark",
            tint: stationTint,
            stats: [
                DSHeroStat(value: loading ? "—" : "\(stationPool.count)",
                           label: L10n.t("في القائمة", "In queue"), icon: "list.bullet.rectangle.fill"),
                DSHeroStat(value: loading ? "—" : "\(counts.noPhone)",
                           label: L10n.t("بلا رقم", "No phone"), icon: "phone.down.fill"),
                DSHeroStat(value: loading ? "—" : "\(counts.noBirth)",
                           label: L10n.t("بلا ميلاد", "No birth date"), icon: "calendar.badge.exclamationmark")
            ]
        )
    }

    // MARK: - المحطة

    private var stationView: some View {
        VStack(spacing: DS.Spacing.md) {
            // ═══ شريحة التصنيف النشط — تبقى ظاهرة حتى لو فرغ التصنيف (لإلغائه) ═══
            if focus != .all {
                focusChip
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Spacing.lg)
            }

            if stationPool.isEmpty {
                SysStateCard(icon: "checkmark.seal.fill",
                             title: L10n.t("ما فيه ملفات ناقصة", "No incomplete profiles"),
                             hint: focus != .all
                                ? L10n.t("لا أحد في هذا التصنيف — ألغِه لعرض كل النواقص",
                                         "Nobody in this category — clear it to see all gaps")
                                : nil,
                             tint: DS.Color.success)
                    .padding(.horizontal, DS.Spacing.lg)
            } else {
                // ═══ التقدّم ═══
                stationProgress
                    .padding(.horizontal, DS.Spacing.lg)

                // ═══ تمرير أفقي سلس بين الأعضاء ═══
                TabView(selection: $stationCursor) {
                    // الفهارس ثابتة — إعادة بناء القائمة أثناء السحب كانت تقطّع الحركة.
                    // التوفير يتم داخل البطاقة: الصورة تُحمَّل للقريبة فقط.
                    ForEach(stationPool.indices, id: \.self) { index in
                        stationCard(stationPool[index], loadsImage: abs(index - stationCursor) <= 1)
                            .padding(.horizontal, DS.Spacing.lg)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 340)

                HStack(spacing: 5) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(L10n.t("اسحب يميناً أو يساراً للتنقّل", "Swipe to move between members"))
                        .font(DS.Font.plex(11.5, weight: .medium))
                }
                .foregroundColor(DS.Color.textTertiary)
            }
        }
    }

    /// التصنيف النشط (من «جودة البيانات») — × يرجّع لكل النواقص
    private var focusChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .accessibilityHidden(true)
            Text(focus.label)
                .font(DS.Font.plex(12, weight: .bold))
                .lineLimit(1)
            Button {
                focus = .all
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -6)
            .accessibilityLabel(L10n.t("إلغاء التصنيف", "Clear filter"))
        }
        .foregroundColor(stationTint)
        .padding(.leading, DS.Spacing.md)
        .frame(height: 34)
        .background(Capsule().fill(stationTint.opacity(0.10)))
        .overlay(Capsule().strokeBorder(stationTint.opacity(0.22), lineWidth: 1))
    }

    /// «٣ من ٤٥» + شريط التقدّم بلون القسم
    private var stationProgress: some View {
        VStack(spacing: 6) {
            HStack {
                Text(L10n.t(
                    "\(min(stationCursor + 1, stationPool.count)) من \(stationPool.count)",
                    "\(min(stationCursor + 1, stationPool.count)) of \(stationPool.count)"
                ))
                .font(DS.Font.plex(12, weight: .bold))
                .foregroundColor(DS.Color.fieldLabel)
                .monospacedDigit()
                Spacer()
                if resolvedCount > 0 {
                    SysStatusChip(text: L10n.t("أنجزت \(resolvedCount)", "\(resolvedCount) done"),
                                  icon: "checkmark.circle.fill",
                                  tint: DS.Color.success)
                }
            }

            GeometryReader { geo in
                let ratio = CGFloat(stationCursor + 1) / CGFloat(max(1, stationPool.count))
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Color.textTertiary.opacity(0.12))
                    Capsule().fill(stationTint)
                        .frame(width: max(6, geo.size.width * min(1, ratio)))
                }
            }
            .frame(height: 6)
            .animation(reduceMotion ? nil : DS.Anim.snappy, value: stationCursor)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    /// إجراء في بطاقة المحطة
    private struct StationAction: Identifiable {
        let id: String
        let title: String
        let icon: String
        let color: Color
        var disabled: Bool = false
        let action: () -> Void
    }

    /// إجراءات العضو — نفس الشروط والوجهات والترتيب كما كانت
    private func stationActions(for member: FamilyMember) -> [StationAction] {
        var items: [StationAction] = []
        if hasNoPhone(member), member.isDeceased != true {
            items.append(StationAction(id: "phone", title: L10n.t("هاتف", "Phone"),
                                       icon: "phone.badge.plus", color: DS.Color.primary) {
                memberToEditPhone = member
            })
        }
        if isMissingBirthDate(member) {
            items.append(StationAction(id: "birth", title: L10n.t("ميلاد", "Birth"),
                                       icon: "calendar.badge.plus", color: DS.Color.accent) {
                memberToEditBirthDate = member
            })
        }
        if isMissingFather(member) {
            items.append(StationAction(id: "father", title: L10n.t("الأب", "Father"),
                                       icon: "person.line.dotted.person", color: DS.Color.info) {
                memberToEdit = member
            })
        }
        if isMissingGender(member) {
            items.append(StationAction(id: "gender", title: L10n.t("الجنس", "Gender"),
                                       icon: "person.fill.questionmark", color: DS.Color.neonPurple) {
                memberToEditGender = member
            })
        }
        if (member.avatarUrl ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
           member.avatarUnavailable != true {
            items.append(StationAction(id: "photo", title: L10n.t("صورة", "Photo"),
                                       icon: "camera.fill", color: DS.Color.secondary) {
                memberToEditPhoto = member
            })
        }
        if member.isDeceased == true,
           (member.deathDate ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
           member.deathDateUnknown != true {
            items.append(StationAction(id: "death", title: L10n.t("وفاة", "Death"),
                                       icon: "calendar.badge.clock", color: DS.Color.textSecondary) {
                memberToEditDeathDate = member
            })
        }
        // التفعيل — لغير المتوفّين فقط، ومعطّل حتى يُضاف رقم
        if member.status != .active, member.isDeceased != true {
            items.append(StationAction(id: "activate", title: L10n.t("تفعيل", "Activate"),
                                       icon: "checkmark.seal.fill", color: DS.Color.success,
                                       disabled: hasNoPhone(member)) {
                memberToActivate = member
                showActivateConfirm = true
            })
        }
        return items
    }

    /// بطاقة عضو واحد داخل المحطة — الإجراءات أيقونات مضغوطة، أربعة بالسطر والباقي يلتفّ
    /// (كانت سطراً واحداً يُقصّ إذا كثرت النواقص)
    private func stationCard(_ member: FamilyMember, loadsImage: Bool = true) -> some View {
        let actions = stationActions(for: member)
        let rows = stride(from: 0, to: actions.count, by: 4).map { start in
            Array(actions[start..<min(start + 4, actions.count)])
        }
        return VStack(spacing: DS.Spacing.md) {
            DSMemberAvatar(
                name: member.fullName,
                avatarUrl: loadsImage ? member.avatarUrl : nil,
                size: 66,
                roleColor: member.roleColor
            )
            .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text(member.shortFullName)
                    .font(DS.Font.plex(18, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(member.displayFullName)
                    .font(DS.Font.plex(11.5))
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)

            // ═══ الإجراءات كأيقونات ═══
            VStack(spacing: DS.Spacing.sm) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(rows[r]) { item in
                            stationIcon(item.title, item.icon, item.color,
                                        disabled: item.disabled, action: item.action)
                        }
                    }
                }
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous).fill(DS.Color.surface))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1)
        )
    }

    /// زر إجراء أيقوني مع تسمية تحته (دائرة ٥٢ نقطة — فوق حد الضغط)
    private func stationIcon(
        _ title: String,
        _ icon: String,
        _ color: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(disabled ? DS.Color.textTertiary : color)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(color.opacity(disabled ? 0.06 : 0.13)))
                    .overlay(Circle().strokeBorder(color.opacity(disabled ? 0.08 : 0.22), lineWidth: 1))
                Text(title)
                    .font(DS.Font.plex(11.5, weight: .semibold))
                    .foregroundColor(disabled ? DS.Color.textTertiary : DS.Color.fieldValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
        .accessibilityLabel(title)
        .accessibilityHint(disabled ? L10n.t("أضف رقماً أولاً", "Add a phone number first") : "")
    }

    /// صف إجراء داخل بطاقة المحطة
    private func stationAction(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.md) {
                ZStack {
                    Circle().fill(color.opacity(0.14))
                    Image(systemName: icon)
                        .font(DS.Font.scaled(13, weight: .semibold))
                        .foregroundColor(color)
                }
                .frame(width: 34, height: 34)

                Text(title)
                    .font(DS.Font.scaled(13, weight: .semibold))
                    .foregroundColor(DS.Color.textPrimary)

                Spacer(minLength: 0)

                Image(systemName: "chevron.forward")
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(color.opacity(0.6))
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm + 2)
            .background(color.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(color.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    /// ينتقل للعضو التالي — ويعود للبداية عند النهاية
    private func advanceStation() {
        let count = stationPool.count
        guard count > 0 else { return }
        stationCursor = (stationCursor + 1) % count
    }

    // MARK: - Member Row
    private func memberRow(member: FamilyMember, index: Int) -> some View {
        HStack(spacing: DS.Spacing.md) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [selectedFilter.color.opacity(0.3), selectedFilter.color.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                Text(String(member.fullName.prefix(1)))
                    .font(DS.Font.headline)
                    .foregroundColor(selectedFilter.color)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(member.displayFullName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)

                // Role badge
                DSRoleBadge(title: roleLabel(member.role), color: member.roleColor)

                // Issue tags
                let issues = issueLabels(for: member)
                if !issues.isEmpty {
                    FlowLayout(spacing: DS.Spacing.xs) {
                        ForEach(issues, id: \.self) { issue in
                            HStack(spacing: 2) {
                                Image(systemName: issue.icon)
                                    .font(DS.Font.scaled(11, weight: .bold))
                                Text(issue.label)
                                    .font(DS.Font.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(issue.color)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(issue.color.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                }

                // Phone info
                if let phone = member.phoneNumber, !phone.isEmpty {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "phone.fill")
                            .font(DS.Font.scaled(11))
                        Text(KuwaitPhone.display(phone))
                            .font(DS.Font.caption1)
                            .monospacedDigit()
                    }
                    .foregroundColor(DS.Color.textTertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, DS.Spacing.xs)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 15)
        .animation(DS.Anim.smooth.delay(Double(index) * 0.04), value: appeared)
    }

    // MARK: - Filter Chips
    /// الفلاتر التي تحتوي على أعضاء فقط
    private var availableFilters: [MemberFilter] {
        MemberFilter.visible.filter { count(for: $0) > 0 }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(availableFilters, id: \.self) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
        .onChange(of: availableFilters) { newFilters in
            // إذا الفلتر المحدد صار فارغ، انقل تلقائياً لأول فلتر متاح
            if !newFilters.contains(selectedFilter), let first = newFilters.first {
                withAnimation(DS.Anim.snappy) { selectedFilter = first }
            }
        }
    }

    private func filterChip(_ filter: MemberFilter) -> some View {
        let isSelected = selectedFilter == filter
        let chipCount = count(for: filter)
        return Button {
            withAnimation(DS.Anim.snappy) {
                selectedFilter = filter
            }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: filter.icon)
                    .font(DS.Font.scaled(11, weight: .semibold))
                Text(filter.label)
                    .font(DS.Font.caption1)
                    .fontWeight(.semibold)
                if chipCount > 0 {
                    Text("\(chipCount)")
                        .font(DS.Font.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(isSelected ? filter.color : DS.Color.textOnPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.28) : filter.color)
                        )
                }
            }
            .foregroundColor(isSelected ? DS.Color.textOnPrimary : filter.color)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                Capsule()
                    .fill(isSelected ? filter.color : filter.color.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : filter.color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DS.Color.textTertiary)
            TextField(L10n.t("بحث عن عضو...", "Search member..."), text: $searchText)
                .font(DS.Font.callout)
                .onChange(of: searchText) { _ in displayLimit = 20 }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DS.Color.textTertiary)
                }
                .accessibilityLabel(L10n.t("مسح البحث", "Clear search"))
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .cornerRadius(DS.Radius.lg)
    }

    // MARK: - Selection Helpers

    private func toggleSelection(_ member: FamilyMember) {
        if selectedMembers.contains(member.id) {
            selectedMembers.remove(member.id)
        } else {
            selectedMembers.insert(member.id)
        }
    }

    private func selectionCheckbox(for member: FamilyMember) -> some View {
        let isSelected = selectedMembers.contains(member.id)
        return ZStack {
            Circle()
                .stroke(isSelected ? DS.Color.primary : DS.Color.textTertiary, lineWidth: 2)
                .frame(width: 24, height: 24)

            if isSelected {
                Circle()
                    .fill(DS.Color.primary)
                    .frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(DS.Font.scaled(12, weight: .bold))
                    .foregroundColor(DS.Color.textOnPrimary)
            }
        }
    }

    // MARK: - Selection Action Bar
    private var selectionActionBar: some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.md) {
                Button {
                    withAnimation(DS.Anim.snappy) {
                        if selectedMembers.count == stationPool.count {
                            selectedMembers.removeAll()
                        } else {
                            selectedMembers = Set(filteredMembers.map(\.id))
                        }
                    }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: selectedMembers.count == stationPool.count
                              ? "checklist.unchecked" : "checklist.checked")
                            .font(DS.Font.callout)
                        Text(selectedMembers.count == stationPool.count
                             ? L10n.t("إلغاء الكل", "Deselect All")
                             : L10n.t("تحديد الكل", "Select All"))
                            .font(DS.Font.calloutBold)
                    }
                    .foregroundColor(DS.Color.primary)
                }
                .buttonStyle(DSScaleButtonStyle())

                Spacer()

                if !selectedMembers.isEmpty {
                    Text(L10n.t(
                        "محدد: \(selectedMembers.count)",
                        "Selected: \(selectedMembers.count)"
                    ))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                }
            }

            if !selectedMembers.isEmpty {
                HStack(spacing: DS.Spacing.sm) {
                    Button {
                        pendingGender = "male"
                        showGenderConfirm = true
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "person.fill")
                                .font(DS.Font.scaled(13, weight: .bold))
                            Text(L10n.t("ذكر", "Male"))
                                .font(DS.Font.calloutBold)
                        }
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(DS.Color.primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(DSBoldButtonStyle())

                    Button {
                        pendingGender = "female"
                        showGenderConfirm = true
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "figure.stand.dress")
                                .font(DS.Font.scaled(13, weight: .bold))
                            Text(L10n.t("أنثى", "Female"))
                                .font(DS.Font.calloutBold)
                        }
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(DS.Color.neonPink)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(DSBoldButtonStyle())
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(
            DS.Color.surface
                .dsSubtleShadow()
        )
    }

    // MARK: - Empty State
    private var emptyState: some View {
        SysStateCard(
            icon: "checkmark.shield.fill",
            title: L10n.t("جميع الحسابات مفعلة والبيانات مكتملة", "All accounts activated and data complete"),
            hint: L10n.t("تظهر هنا الملفات الناقصة أولاً بأول", "Incomplete profiles show up here as they appear"),
            tint: DS.Color.success
        )
    }

    // MARK: - No Results
    private var noResultsState: some View {
        SysStateCard(
            icon: "magnifyingglass",
            title: L10n.t("لا توجد نتائج", "No results found"),
            tint: DS.Color.textTertiary
        )
    }

    // MARK: - Helpers
    private func roleLabel(_ role: FamilyMember.UserRole) -> String {
        switch role {
        case .owner: return L10n.t("مدير", "Admin")
        case .admin: return L10n.t("مدير", "Admin")
        case .monitor: return L10n.t("مراقب", "Monitor")
        case .supervisor: return L10n.t("مشرف", "Supervisor")
        case .member: return L10n.t("عضو", "Member")
        case .pending: return L10n.t("معلق", "Pending")
        }
    }

    private func activateMember(_ member: FamilyMember) async {
        await adminRequestVM.activateAccount(memberId: member.id)
    }
}

// MARK: - Flow Layout for Tags
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
            totalHeight = y + rowHeight
        }

        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}

// MARK: - Edit Phone Sheet
struct EditPhoneSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @State private var phoneInput: String
    @State private var selectedPhoneCountry: KuwaitPhone.Country
    @State private var isSaving = false

    init(member: FamilyMember, memberVM: MemberViewModel) {
        self.member = member
        self.memberVM = memberVM
        let detected = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
        _selectedPhoneCountry = State(initialValue: detected.country)
        _phoneInput = State(initialValue: detected.localDigits)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: DS.Spacing.xl) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(DS.Color.info.opacity(0.1))
                            .frame(width: 80, height: 80)
                        Image(systemName: "phone.badge.plus")
                            .font(DS.Font.scaled(30, weight: .bold))
                            .foregroundColor(DS.Color.info)
                    }
                    .padding(.top, DS.Spacing.xl)

                    // Member name
                    Text(member.displayFullName)
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textPrimary)

                    // Phone field — حقل موحّد مع كود الدولة على الجهة المقابلة
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text(L10n.t("رقم الجوال", "Phone Number"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)

                        DSPhoneField(
                            country: $selectedPhoneCountry,
                            digits: $phoneInput,
                            placeholder: L10n.t("أدخل رقم الجوال", "Enter phone number")
                        )
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    // Save button
                    Button {
                        isSaving = true
                        Task {
                            await memberVM.updateMemberPhone(memberId: member.id, country: selectedPhoneCountry, localPhone: phoneInput.trimmingCharacters(in: .whitespacesAndNewlines))
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            if isSaving {
                                ProgressView()
                                    .tint(DS.Color.textOnPrimary)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(L10n.t("حفظ", "Save"))
                                .fontWeight(.bold)
                        }
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(phoneInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? DS.Color.textTertiary : DS.Color.primary)
                        .cornerRadius(DS.Radius.lg)
                    }
                    .disabled(phoneInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    .padding(.horizontal, DS.Spacing.lg)

                    Spacer()
                }
            }
            .navigationTitle(L10n.t("تعديل رقم الجوال", "Edit Phone Number"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: DSToolbar.cancelPlacement) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.Font.scaled(22, weight: .medium))
                            .foregroundStyle(DS.Color.textTertiary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(L10n.t("إغلاق", "Close"))
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}

// MARK: - Link Father Sheet

/// ربط الأب — مربّع بمنتصف الشاشة بنفس تصميم مربّعات الإضافة (طلب المالك):
/// بطاقة العضو، ثم البحث وقائمة الأعضاء بعلامة اختيار، و«ربط الأب» / «إلغاء» أسفله.
struct LinkFatherSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var isSaving = false
    @State private var selectedFather: FamilyMember?
    @State private var cache = ResultsCache()

    /// نتائج البحث محفوظة لكل (نص بحث + نسخة الأعضاء): المربّع يعيد بناء محتواه كلما
    /// تغيّر ارتفاعه، وفرز آلاف الأعضاء مع كل مرة يثقّل الفتح والتمرير
    private final class ResultsCache {
        var key: String?
        var results: [FamilyMember] = []
    }

    private var results: [FamilyMember] {
        let key = "\(memberVM.membersVersion)|\(memberVM.allMembers.count)|\(searchText)"
        if cache.key != key {
            cache.results = Self.fathers(of: member, in: memberVM.allMembers, matching: searchText)
            cache.key = key
        }
        return cache.results
    }

    /// All potential fathers (non-pending, excluding self), filtered by the search text
    private static func fathers(of member: FamilyMember, in all: [FamilyMember],
                                matching search: String) -> [FamilyMember] {
        let potentialFathers = all
            .filter { $0.id != member.id && $0.role != .pending }
            .sorted {
                let a = $0.firstName.trimmingCharacters(in: .whitespaces)
                let b = $1.firstName.trimmingCharacters(in: .whitespaces)
                if a != b { return a.localizedStandardCompare(b) == .orderedAscending }
                return $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
            }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return potentialFathers }
        return potentialFathers.filter { $0.fullName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        DSComposer(
            title: L10n.t("ربط الأب", "Link Father"),
            subtitle: member.shortFullName,
            icon: "person.line.dotted.person",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("ربط الأب", "Link Father"),
            actionIcon: "link",
            canSubmit: selectedFather != nil,
            isBusy: isSaving,
            // أب مختار ولم يُربط بعد → «إلغاء» يسأل قبل التجاهل (توصية أبل)
            hasUnsavedChanges: selectedFather != nil,
            onSubmit: save,
            onCancel: { dismiss() }
        ) {
            StationMemberCard(member: member).dsStaggerIn(0)
            fatherSection
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// البحث + قائمة الأعضاء — المختار بعلامة ✓ (الضغط عليه مرة ثانية يلغي الاختيار)
    private var fatherSection: some View {
        DSComposerSection(
            title: L10n.t("اختر الأب", "Choose Father"),
            icon: "person.2.fill",
            tint: DS.Color.info,
            trailing: L10n.t("\(results.count) عضو", "\(results.count) members"),
            index: 1
        ) {
            DSComposerField(icon: "magnifyingglass",
                            label: L10n.t("بحث", "Search"),
                            placeholder: L10n.t("ابحث عن الأب...", "Search for father..."),
                            text: $searchText,
                            tint: DS.Color.info)

            if results.isEmpty {
                Text(L10n.t("لا توجد نتائج", "No results found"))
                    .font(DS.Font.plex(13, weight: .semibold))
                    .foregroundColor(DS.Color.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.md)
            } else {
                // كسولة — القائمة فيها آلاف الأعضاء: تُبنى الصفوف الظاهرة فقط
                LazyVStack(spacing: DS.Spacing.sm) {
                    ForEach(results) { father in
                        fatherRow(father)
                    }
                }
            }
        }
    }

    private func fatherRow(_ father: FamilyMember) -> some View {
        let isSelected = selectedFather?.id == father.id
        return Button {
            withAnimation(DS.Anim.snappy) {
                selectedFather = (selectedFather?.id == father.id) ? nil : father
            }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                // الحرف الأول بمربّع أيقونة الحقل (بلا تحميل صور لآلاف الصفوف)
                Text(String(father.firstName.prefix(1)))
                    .font(DS.Font.plex(14, weight: .bold))
                    .foregroundColor(DS.Color.info)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(DS.Color.info.opacity(0.12)))
                    .accessibilityHidden(true)   // زخرفة — الاسم يُقرأ كاملاً بعدها

                VStack(alignment: .leading, spacing: 2) {
                    Text(father.displayFullName)
                        .font(DS.Font.plex(14, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? DS.Color.textPrimary : DS.Color.fieldValue)
                        .lineLimit(1)
                    if father.isDeceased == true {
                        Text(L10n.t("متوفى", "Deceased"))
                            .font(DS.Font.plex(11))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }

                Spacer(minLength: 0)

                // علامة الاختيار للعين فقط — القارئ الصوتي يعلن «محدّد» من صفة isSelected
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? DS.Color.info : DS.Color.textTertiary.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .stationPickRow(selected: isSelected, tint: DS.Color.info)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func save() {
        guard let father = selectedFather else { return }
        isSaving = true
        Task {
            await memberVM.updateMemberFather(memberId: member.id, fatherId: father.id)
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - Edit Birth Date Sheet

/// تاريخ الميلاد — مربّع بمنتصف الشاشة بنفس تصميم مربّعات الإضافة (طلب المالك)
struct EditBirthDateSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedDate: Date
    @State private var isSaving = false
    /// اليوم الذي فُتح عليه المربّع — «إلغاء» يسأل فقط إذا تغيّر (توصية أبل)
    private let startDay: String

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init(member: FamilyMember, memberVM: MemberViewModel) {
        self.member = member
        self.memberVM = memberVM
        // Parse existing date or default to 1990-01-01
        let start: Date
        if let existing = member.birthDate,
           let parsed = Self.formatter.date(from: existing) {
            start = parsed
        } else {
            var comps = DateComponents()
            comps.year = 1990; comps.month = 1; comps.day = 1
            start = Calendar.current.date(from: comps) ?? Date()
        }
        _selectedDate = State(initialValue: start)
        startDay = Self.formatter.string(from: start)
    }

    var body: some View {
        DSComposer(
            title: L10n.t("تعديل تاريخ الميلاد", "Edit Birth Date"),
            subtitle: member.shortFullName,
            icon: "calendar.badge.plus",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            canSubmit: true,
            isBusy: isSaving,
            // مقارنة باليوم فقط — العجلة لا تغيّر إلا التاريخ
            hasUnsavedChanges: Self.formatter.string(from: selectedDate) != startDay,
            onSubmit: save,
            onCancel: { dismiss() }
        ) {
            StationMemberCard(member: member).dsStaggerIn(0)

            DSComposerSection(title: L10n.t("تاريخ الميلاد", "Birth Date"),
                              icon: "calendar", tint: DS.Color.warning, index: 1) {
                StableWheelDatePicker(selection: $selectedDate, in: ...Date())
                    .dsRowBox()
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func save() {
        isSaving = true
        Task {
            let dateString = Self.formatter.string(from: selectedDate)
            await memberVM.updateMemberBirthDate(
                memberId: member.id,
                birthDate: dateString
            )
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - مربّعات المحطة: أجزاء مشتركة

/// بطاقة «العضو» أعلى مربّعات المحطة — صورته واسمه الكامل (من نكمل بياناته)
private struct StationMemberCard: View {
    let member: FamilyMember

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSMemberAvatar(name: member.fullName, avatarUrl: member.avatarUrl,
                           size: 40, roleColor: member.roleColor)
                // المتوفّى بالأبيض والأسود (نفس تفاصيل العضو)
                .grayscale(member.isDeceased == true ? 1 : 0)
                .accessibilityHidden(true)   // الصورة زخرفة — الاسم يُقرأ بعدها

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("العضو", "Member"))
                    .font(DS.Font.plex(11.5, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                Text(member.displayFullName)
                    .font(DS.Font.plex(14.5, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1))
        // القارئ الصوتي: «العضو، الاسم» عنصراً واحداً
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// صف اختيار: نفس صندوق صفوف المربّعات + إطار بلون الاختيار للصف المختار
    func stationPickRow(selected: Bool, tint: Color) -> some View {
        dsRowBox()
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(tint.opacity(0.55), lineWidth: 1.5)
                    .opacity(selected ? 1 : 0)
            )
    }
}

/// دائرة صورة العضو — مثل شعار مربّعات الإضافة: فارغة بحلقة متقطّعة تدور ببطء
/// وكاميرا، ومختارة بالصورة مع شارة تغيير. نفس اختيار الصورة السابق (بلا قصّ).
private struct StationPhotoCircle: View {
    @Binding var item: PhotosPickerItem?
    let image: UIImage?
    var tint: Color = DS.Color.primary
    var size: CGFloat = 96
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            PhotosPicker(selection: $item, matching: .images) {
                circle
                    .overlay(alignment: .bottomTrailing) { badge }
            }
            .buttonStyle(DSScaleButtonStyle())
            // زر صورة بلا نص (بعد الاختيار) — اسمه للقارئ الصوتي هو نفس التسمية تحته
            .accessibilityLabel(caption)

            Text(caption)
                .font(DS.Font.plex(11))
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)   // مقروءة من اسم الزر أعلاه
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !reduceMotion else { return }   // الإطار ثابت مع «تقليل الحركة»
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { spin = true }
        }
    }

    private var caption: String {
        image == nil ? L10n.t("اختيار صورة", "Choose photo") : L10n.t("تغيير الصورة", "Change Photo")
    }

    @ViewBuilder
    private var circle: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(tint.opacity(0.5), lineWidth: 2))
                // «تقليل الحركة»: تظهر الصورة بتلاشٍ فقط بلا تكبير
                .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
        } else {
            ZStack {
                Circle().fill(tint.opacity(0.08))
                Circle()
                    .strokeBorder(tint.opacity(0.55), style: StrokeStyle(lineWidth: 1.6, dash: [6, 5]))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                VStack(spacing: 3) {
                    Image(systemName: "camera.fill").font(.system(size: 22, weight: .semibold))
                    Text(L10n.t("صورة", "Photo")).font(DS.Font.plex(11, weight: .bold))
                }
                .foregroundColor(tint)
            }
            .frame(width: size, height: size)
        }
    }

    private var badge: some View {
        Image(systemName: image == nil ? "plus" : "pencil")
            .font(.system(size: 11, weight: .heavy))
            .foregroundColor(.white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(tint))
            .overlay(Circle().strokeBorder(DS.Color.background, lineWidth: 2.5))
            .offset(x: 2, y: 2)
    }
}

// MARK: - مربّعات مخصّصة لكل تخصّص في المحطة

/// تحديد جنس العضو — بطاقة العضو ثم خياران بعلامة اختيار
struct EditGenderSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss
    /// الخيار الذي يُفتح عليه المربّع — اختيار غيره تغيير لم يُحفظ
    private static let startGender = "male"
    @State private var gender: String = EditGenderSheet.startGender
    @State private var isSaving = false

    var body: some View {
        DSComposer(
            title: L10n.t("تحديد الجنس", "Set Gender"),
            subtitle: member.shortFullName,
            icon: "person.fill.questionmark",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            canSubmit: true,
            isBusy: isSaving,
            hasUnsavedChanges: gender != Self.startGender,
            onSubmit: save,
            onCancel: { dismiss() }
        ) {
            StationMemberCard(member: member).dsStaggerIn(0)

            DSComposerSection(title: L10n.t("الجنس", "Gender"),
                              icon: "person.2.fill", tint: DS.Color.primary, index: 1) {
                genderOption("male", L10n.t("ذكر", "Male"), "figure.stand", DS.Color.primary)
                genderOption("female", L10n.t("أنثى", "Female"), "figure.stand.dress", DS.Color.likeAction)
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func genderOption(_ value: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        let isOn = gender == value
        return Button {
            withAnimation(DS.Anim.snappy) { gender = value }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: icon, tint: tint)
                    .accessibilityHidden(true)

                Text(label)
                    .font(DS.Font.plex(14.5, weight: isOn ? .bold : .medium))
                    .foregroundColor(isOn ? DS.Color.textPrimary : DS.Color.fieldValue)

                Spacer(minLength: 0)

                // للعين فقط — «محدّد» يُعلن من صفة isSelected
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isOn ? tint : DS.Color.textTertiary.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .stationPickRow(selected: isOn, tint: tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func save() {
        isSaving = true
        Task {
            await memberVM.updateMemberGender(memberId: member.id, gender: gender)
            isSaving = false
            dismiss()
        }
    }
}

/// تاريخ الوفاة — رأس رمادي هادئ للمتوفّى (مثل «طلب إضافة تاريخ وفاة»)
struct EditDeathDateSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()
    @State private var isSaving = false
    @State private var isUnknown = false
    /// ما فُتح عليه المربّع (اليوم + «غير معروف») — «إلغاء» يسأل فقط إذا تغيّر (توصية أبل)
    private let startDay: String
    private let startUnknown: Bool

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init(member: FamilyMember, memberVM: MemberViewModel) {
        self.member = member
        self.memberVM = memberVM
        _isUnknown = State(initialValue: member.deathDateUnknown == true)
        var start = Date()
        if let existing = member.deathDate, let parsed = Self.formatter.date(from: existing) {
            start = parsed
        }
        _selectedDate = State(initialValue: start)
        startDay = Self.formatter.string(from: start)
        startUnknown = member.deathDateUnknown == true
    }

    /// تغيير «غير معروف»، أو يوم مختلف والتاريخ معروف (العجلة معطّلة مع «غير معروف»)
    private var hasChanges: Bool {
        isUnknown != startUnknown
            || (!isUnknown && Self.formatter.string(from: selectedDate) != startDay)
    }

    var body: some View {
        DSComposer(
            title: L10n.t("تاريخ الوفاة", "Death Date"),
            subtitle: member.shortFullName,
            icon: "calendar.badge.clock",
            tint: DS.Color.textSecondary,
            actionTitle: L10n.t("حفظ", "Save"),
            canSubmit: true,
            isBusy: isSaving,
            hasUnsavedChanges: hasChanges,
            onSubmit: save,
            onCancel: { dismiss() }
        ) {
            StationMemberCard(member: member).dsStaggerIn(0)

            DSComposerSection(title: L10n.t("تاريخ الوفاة", "Death Date"),
                              icon: "calendar.badge.clock", tint: DS.Color.textSecondary, index: 1) {
                StableWheelDatePicker(selection: $selectedDate, in: ...Date())
                    .opacity(isUnknown ? 0.35 : 1)
                    .disabled(isUnknown)
                    .dsRowBox()

                Toggle(isOn: $isUnknown.animation(DS.Anim.snappy)) {
                    HStack(spacing: DS.Spacing.sm) {
                        DSFieldIcon(name: "questionmark.circle.fill", tint: DS.Color.textSecondary)
                            .accessibilityHidden(true)
                        Text(L10n.t("التاريخ غير معروف", "Date unknown"))
                            .font(DS.Font.plex(14, weight: .semibold))
                            .foregroundColor(DS.Color.textPrimary)
                    }
                }
                .tint(DS.Color.primary)
                .dsRowBox()
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func save() {
        isSaving = true
        Task {
            if isUnknown {
                await memberVM.setDeathDateUnknown(memberId: member.id)
                isSaving = false
                dismiss()
                return
            }
            let birth = member.birthDate.flatMap { Self.formatter.date(from: $0) }
            _ = await memberVM.updateMemberData(
                memberId: member.id,
                fullName: member.fullName,
                phoneNumber: member.phoneNumber ?? "",
                birthDate: birth,
                isMarried: member.isMarried ?? false,
                isDeceased: true,
                deathDate: selectedDate,
                isPhoneHidden: member.isPhoneHidden ?? false
            )
            isSaving = false
            dismiss()
        }
    }
}

/// صورة العضو — دائرة الصورة (مثل شعار مربّعات الإضافة) و«لا توجد صورة لهذا العضو»
struct EditMemberPhotoSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickedItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var isSaving = false

    var body: some View {
        DSComposer(
            title: L10n.t("صورة العضو", "Member Photo"),
            subtitle: member.shortFullName,
            icon: "camera.fill",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            canSubmit: pickedImage != nil,
            isBusy: isSaving,
            // صورة مختارة ولم تُرفع بعد → «إلغاء» يسأل قبل التجاهل
            hasUnsavedChanges: pickedImage != nil,
            onSubmit: save,
            onCancel: { dismiss() }
        ) {
            StationMemberCard(member: member).dsStaggerIn(0)

            DSComposerSection(title: L10n.t("الصورة", "Photo"),
                              icon: "photo.fill", tint: DS.Color.primary, index: 1) {
                StationPhotoCircle(item: $pickedItem, image: pickedImage)
                noPhotoButton
            }
        }
        .onChange(of: pickedItem) { item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self),
                      let img = UIImage(data: data) else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.68)) { pickedImage = img }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// لا توجد صورة لهذا العضو — يخرجه من تقارير النقص بلا رفع صورة
    private var noPhotoButton: some View {
        Button {
            markNoPhoto()
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "person.crop.circle.badge.xmark", tint: DS.Color.textSecondary)
                    .accessibilityHidden(true)
                Text(L10n.t("لا توجد صورة لهذا العضو", "No photo exists for this member"))
                    .font(DS.Font.plex(13.5, weight: .semibold))
                    .foregroundColor(DS.Color.textSecondary)
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    private func markNoPhoto() {
        isSaving = true
        Task {
            await memberVM.setAvatarUnavailable(memberId: member.id)
            isSaving = false
            dismiss()
        }
    }

    private func save() {
        guard let img = pickedImage else { return }
        isSaving = true
        Task {
            _ = await memberVM.uploadAvatar(image: img, for: member.id)
            isSaving = false
            dismiss()
        }
    }
}
