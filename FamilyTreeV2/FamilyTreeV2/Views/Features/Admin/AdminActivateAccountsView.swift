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
        ZStack {
            if memberVM.isLoading && memberVM.allMembers.isEmpty {
                VStack(spacing: DS.Spacing.lg) {
                    ProgressView()
                        .tint(DS.Color.primary)
                        .scaleEffect(1.3)
                    Text(L10n.t("جاري فحص البيانات...", "Checking data..."))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allIssueMembers.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {

                    stationView
                    Spacer(minLength: 0)
                    if false {
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
            }
        }
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
        .alert(
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
        .alert(
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
        .alert(L10n.t("تم التحديث", "Updated"), isPresented: $showGenderResult) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(genderUpdateResult ?? "")
        }
        .sheet(item: $memberToEditPhone) { member in
            PendingMemberPhoneSheet(member: member, activateOnSave: true)
                .environmentObject(adminRequestVM)
        }
        .sheet(item: $memberToEditBirthDate) { member in
            EditBirthDateSheet(member: member, memberVM: memberVM)
        }
        .sheet(item: $memberToEdit) { member in
            LinkFatherSheet(member: member, memberVM: memberVM)
        }
        .sheet(item: $memberToEditGender) { member in
            EditGenderSheet(member: member, memberVM: memberVM)
        }
        .sheet(item: $memberToEditPhoto) { member in
            EditMemberPhotoSheet(member: member, memberVM: memberVM)
        }
        .sheet(item: $memberToEditDeathDate) { member in
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

    private var stationView: some View {
        VStack(spacing: DS.Spacing.md) {
            if stationPool.isEmpty {
                VStack(spacing: DS.Spacing.md) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 42, weight: .light))
                        .foregroundColor(DS.Color.success)
                    Text(L10n.t("ما فيه ملفات ناقصة", "No incomplete profiles"))
                        .font(DS.Font.plex(16, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                }
                .padding(.vertical, DS.Spacing.xxxl)
            } else {
                // ═══ شريحة التصنيف النشط ═══
                if focus != .all {
                    HStack(spacing: 5) {
                        Text(focus.label)
                            .font(DS.Font.scaled(11, weight: .semibold))
                        Button {
                            focus = .all
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(DS.Font.scaled(11, weight: .bold))
                        }
                    }
                    .foregroundColor(DS.Color.primary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(DS.Color.primary.opacity(0.10)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Spacing.lg)
                }

                // ═══ التقدّم ═══
                VStack(spacing: DS.Spacing.xs) {
                    HStack {
                        Text(L10n.t(
                            "\(min(stationCursor + 1, stationPool.count)) من \(stationPool.count)",
                            "\(min(stationCursor + 1, stationPool.count)) of \(stationPool.count)"
                        ))
                        .font(DS.Font.scaled(11, weight: .semibold))
                        .foregroundColor(DS.Color.textSecondary)
                        Spacer()
                        if resolvedCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(DS.Font.scaled(11, weight: .bold))
                                Text(L10n.t("أنجزت \(resolvedCount)", "\(resolvedCount) done"))
                                    .font(DS.Font.scaled(11, weight: .semibold))
                            }
                            .foregroundColor(DS.Color.success)
                        }
                    }

                    GeometryReader { geo in
                        let ratio = CGFloat(stationCursor + 1) / CGFloat(max(1, stationPool.count))
                        ZStack(alignment: .leading) {
                            Capsule().fill(DS.Color.textTertiary.opacity(0.12))
                            Capsule().fill(DS.Color.primary)
                                .frame(width: max(0, geo.size.width * ratio))
                        }
                    }
                    .frame(height: 5)
                }
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

                Text(L10n.t("اسحب يميناً أو يساراً للتنقّل", "Swipe to move between members"))
                    .font(DS.Font.scaled(11))
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
        .padding(.top, DS.Spacing.sm)
    }

    /// بطاقة عضو واحد داخل المحطة — الإجراءات أيقونات مضغوطة
    private func stationCard(_ member: FamilyMember, loadsImage: Bool = true) -> some View {
        VStack(spacing: DS.Spacing.md) {
            DSMemberAvatar(
                name: member.fullName,
                avatarUrl: loadsImage ? member.avatarUrl : nil,
                size: 66,
                roleColor: member.roleColor
            )

            VStack(spacing: 2) {
                Text(member.shortFullName)
                    .font(DS.Font.plex(18, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                Text(member.fullName)
                    .font(DS.Font.scaled(11))
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            // ═══ الإجراءات كأيقونات ═══
            HStack(spacing: DS.Spacing.md) {
                if hasNoPhone(member), member.isDeceased != true {
                    stationIcon(L10n.t("هاتف", "Phone"), "phone.badge.plus", DS.Color.primary) {
                        memberToEditPhone = member
                    }
                }
                if isMissingBirthDate(member) {
                    stationIcon(L10n.t("ميلاد", "Birth"), "calendar.badge.plus", DS.Color.accent) {
                        memberToEditBirthDate = member
                    }
                }
                if isMissingFather(member) {
                    stationIcon(L10n.t("الأب", "Father"), "person.line.dotted.person", DS.Color.info) {
                        memberToEdit = member
                    }
                }
                if isMissingGender(member) {
                    stationIcon(L10n.t("الجنس", "Gender"), "person.fill.questionmark", DS.Color.neonPurple) {
                        memberToEditGender = member
                    }
                }
                if (member.avatarUrl ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
                   member.avatarUnavailable != true {
                    stationIcon(L10n.t("صورة", "Photo"), "camera.fill", DS.Color.secondary) {
                        memberToEditPhoto = member
                    }
                }
                if member.isDeceased == true,
                   (member.deathDate ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
                   member.deathDateUnknown != true {
                    stationIcon(L10n.t("وفاة", "Death"), "calendar.badge.clock", DS.Color.textSecondary) {
                        memberToEditDeathDate = member
                    }
                }

                // التفعيل — لغير المتوفّين فقط، ومعطّل حتى يُضاف رقم
                if member.status != .active, member.isDeceased != true {
                    stationIcon(
                        L10n.t("تفعيل", "Activate"),
                        "checkmark.seal.fill",
                        DS.Color.success,
                        disabled: hasNoPhone(member)
                    ) {
                        memberToActivate = member
                        showActivateConfirm = true
                    }
                }
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
                .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1)
        )
    }

    /// زر إجراء أيقوني مع تسمية تحته
    private func stationIcon(
        _ title: String,
        _ icon: String,
        _ color: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill(color.opacity(disabled ? 0.06 : 0.14))
                    Image(systemName: icon)
                        .font(DS.Font.scaled(17, weight: .semibold))
                        .foregroundColor(disabled ? DS.Color.textTertiary : color)
                }
                .frame(width: 52, height: 52)
                Text(title)
                    .font(DS.Font.scaled(11, weight: .semibold))
                    .foregroundColor(disabled ? DS.Color.textTertiary : DS.Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(DSScaleButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
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
                Text(member.fullName)
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
        DSEmptyState(
            icon: "checkmark.shield.fill",
            title: L10n.t("جميع الحسابات مفعلة والبيانات مكتملة", "All accounts activated and data complete"),
            tint: DS.Color.success
        )
    }

    // MARK: - No Results
    private var noResultsState: some View {
        DSEmptyState(
            icon: "magnifyingglass",
            title: L10n.t("لا توجد نتائج", "No results found")
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
                    Text(member.fullName)
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
                ToolbarItem(placement: .topBarLeading) {
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

struct LinkFatherSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var isSaving = false
    @State private var selectedFather: FamilyMember?

    /// All potential fathers (non-pending, non-deceased, excluding self)
    private var potentialFathers: [FamilyMember] {
        memberVM.allMembers
            .filter { $0.id != member.id && $0.role != .pending }
            .sorted {
                let a = $0.firstName.trimmingCharacters(in: .whitespaces)
                let b = $1.firstName.trimmingCharacters(in: .whitespaces)
                if a != b { return a.localizedStandardCompare(b) == .orderedAscending }
                return $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
            }
    }

    private var filteredFathers: [FamilyMember] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return potentialFathers
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return potentialFathers.filter { $0.fullName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Icon + member name
                    VStack(spacing: DS.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(DS.Color.info.opacity(0.1))
                                .frame(width: 70, height: 70)
                            Image(systemName: "person.line.dotted.person")
                                .font(DS.Font.scaled(28, weight: .bold))
                                .foregroundColor(DS.Color.info)
                        }

                        Text(member.fullName)
                            .font(DS.Font.headline)
                            .foregroundColor(DS.Color.textPrimary)
                    }
                    .padding(.top, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.md)

                    // Search field
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(DS.Color.textTertiary)
                        TextField(L10n.t("ابحث عن الأب...", "Search for father..."), text: $searchText)
                            .font(DS.Font.body)
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.lg)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.lg)
                            .stroke(DS.Color.info.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.sm)

                    // Results count
                    HStack {
                        Text(L10n.t(
                            "\(filteredFathers.count) عضو",
                            "\(filteredFathers.count) members"
                        ))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xs)

                    // Members list
                    List {
                        ForEach(filteredFathers) { father in
                            Button {
                                withAnimation(DS.Anim.snappy) {
                                    selectedFather = (selectedFather?.id == father.id) ? nil : father
                                }
                            } label: {
                                HStack(spacing: DS.Spacing.md) {
                                    // Selection indicator
                                    Image(systemName: selectedFather?.id == father.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedFather?.id == father.id ? DS.Color.info : DS.Color.textTertiary)
                                        .font(DS.Font.scaled(20))

                                    // Avatar
                                    ZStack {
                                        Circle()
                                            .fill(DS.Color.info.opacity(0.1))
                                            .frame(width: 40, height: 40)
                                        Text(String(father.firstName.prefix(1)))
                                            .font(DS.Font.calloutBold)
                                            .foregroundColor(DS.Color.info)
                                    }

                                    // Name
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(father.fullName)
                                            .font(DS.Font.callout)
                                            .foregroundColor(DS.Color.textPrimary)
                                            .lineLimit(1)
                                        if father.isDeceased == true {
                                            Text(L10n.t("متوفى", "Deceased"))
                                                .font(DS.Font.caption2)
                                                .foregroundColor(DS.Color.textTertiary)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, DS.Spacing.xs)
                            }
                            .listRowBackground(
                                selectedFather?.id == father.id
                                    ? DS.Color.info.opacity(0.08)
                                    : Color.clear
                            )
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)

                    // Save button
                    Button {
                        guard let father = selectedFather else { return }
                        isSaving = true
                        Task {
                            await memberVM.updateMemberFather(memberId: member.id, fatherId: father.id)
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            if isSaving {
                                ProgressView()
                                    .tint(DS.Color.textOnPrimary)
                            } else {
                                Image(systemName: "link.circle.fill")
                            }
                            Text(L10n.t("ربط الأب", "Link Father"))
                                .fontWeight(.bold)
                        }
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(selectedFather != nil ? DS.Color.info : DS.Color.textTertiary)
                        .cornerRadius(DS.Radius.lg)
                    }
                    .disabled(selectedFather == nil || isSaving)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                }
            }
            .navigationTitle(L10n.t("ربط الأب", "Link Father"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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

// MARK: - Edit Birth Date Sheet
struct EditBirthDateSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedDate: Date
    @State private var isSaving = false

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
        if let existing = member.birthDate,
           let parsed = Self.formatter.date(from: existing) {
            _selectedDate = State(initialValue: parsed)
        } else {
            var comps = DateComponents()
            comps.year = 1990; comps.month = 1; comps.day = 1
            _selectedDate = State(initialValue: Calendar.current.date(from: comps) ?? Date())
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: DS.Spacing.xl) {
                    // رأس مضغوط — أيقونة والاسم بصف واحد
                    HStack(spacing: DS.Spacing.sm) {
                        ZStack {
                            Circle().fill(DS.Color.accent.opacity(0.12)).frame(width: 34, height: 34)
                            Image(systemName: "calendar.badge.plus")
                                .font(DS.Font.scaled(15, weight: .semibold))
                                .foregroundColor(DS.Color.accent)
                        }
                        Text(member.fullName)
                            .font(DS.Font.scaled(13, weight: .semibold))
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.md)

                    // Date picker
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text(L10n.t("تاريخ الميلاد", "Birth Date"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)

                        StableWheelDatePicker(selection: $selectedDate, in: ...Date())
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    // Save button
                    Button {
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
                        .background(DS.Color.primary)
                        .cornerRadius(DS.Radius.lg)
                    }
                    .disabled(isSaving)
                    .padding(.horizontal, DS.Spacing.lg)

                    Spacer()
                }
            }
            .navigationTitle(L10n.t("تعديل تاريخ الميلاد", "Edit Birth Date"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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

// MARK: - شيتات مخصّصة لكل تخصّص في المحطة

/// غلاف موحّد لشيتات المحطة — أيقونة، اسم العضو، محتوى، وزر حفظ
private struct StationSheetShell<Content: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let memberName: String
    let isSaving: Bool
    let canSave: Bool
    let onSave: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    /// ارتفاع المحتوى الفعلي — الشيت يأخذ حجمه بدل نصف الشاشة الثابت
    @State private var contentHeight: CGFloat = 260

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: DS.Spacing.md) {
                    HStack(spacing: DS.Spacing.sm) {
                        ZStack {
                            Circle().fill(tint.opacity(0.12)).frame(width: 34, height: 34)
                            Image(systemName: icon)
                                .font(DS.Font.scaled(15, weight: .semibold))
                                .foregroundColor(tint)
                        }
                        Text(memberName)
                            .font(DS.Font.scaled(13, weight: .semibold))
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.md)

                    content()
                        .padding(.horizontal, DS.Spacing.lg)

                    Spacer(minLength: 0)

                    Button(action: onSave) {
                        HStack(spacing: DS.Spacing.sm) {
                            if isSaving { ProgressView().tint(DS.Color.textOnPrimary) }
                            Text(L10n.t("حفظ", "Save"))
                                .font(DS.Font.scaled(13, weight: .bold))
                        }
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(canSave ? tint : DS.Color.textTertiary, in: Capsule())
                    }
                    .disabled(!canSave || isSaving)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.md)
                }
                .background(
                    GeometryReader { proxy in
                        SwiftUI.Color.clear
                            .preference(key: SheetHeightKey.self, value: proxy.size.height)
                    }
                )
                .onPreferenceChange(SheetHeightKey.self) { h in
                    // + ارتفاع شريط التنقّل تقريباً
                    if h > 0, abs(h - contentHeight) > 1 { contentHeight = h + 56 }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
    }
}

/// تحديد جنس العضو
struct EditGenderSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var gender: String = "male"
    @State private var isSaving = false

    var body: some View {
        StationSheetShell(
            icon: "person.fill.questionmark",
            tint: DS.Color.neonPurple,
            title: L10n.t("تحديد الجنس", "Set Gender"),
            memberName: member.fullName,
            isSaving: isSaving,
            canSave: true,
            onSave: save
        ) {
            VStack(spacing: DS.Spacing.sm) {
                genderOption("male", L10n.t("ذكر", "Male"), "person.fill")
                genderOption("female", L10n.t("أنثى", "Female"), "person.dress.line.vertical.figure")
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func genderOption(_ value: String, _ label: String, _ icon: String) -> some View {
        let isOn = gender == value
        return Button {
            gender = value
        } label: {
            HStack(spacing: DS.Spacing.md) {
                DSIcon(icon, color: isOn ? DS.Color.neonPurple : DS.Color.textTertiary,
                       size: 32, iconSize: 13)

                Text(label)
                    .font(DS.Font.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.textPrimary)

                Spacer(minLength: 0)

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(DS.Font.scaled(15, weight: .semibold))
                    .foregroundColor(isOn ? DS.Color.neonPurple : DS.Color.textTertiary.opacity(0.5))
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm + 2)
            .background(isOn ? DS.Color.neonPurple.opacity(0.07) : DS.Color.background)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(isOn ? DS.Color.neonPurple.opacity(0.35)
                                       : DS.Color.textTertiary.opacity(0.15),
                                  lineWidth: 1)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
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

/// تاريخ الوفاة
struct EditDeathDateSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()
    @State private var isSaving = false
    @State private var isUnknown = false

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
        if let existing = member.deathDate, let parsed = Self.formatter.date(from: existing) {
            _selectedDate = State(initialValue: parsed)
        }
    }

    var body: some View {
        StationSheetShell(
            icon: "calendar.badge.clock",
            tint: DS.Color.textSecondary,
            title: L10n.t("تاريخ الوفاة", "Death Date"),
            memberName: member.fullName,
            isSaving: isSaving,
            canSave: true,
            onSave: save
        ) {
            VStack(spacing: DS.Spacing.md) {
                StableWheelDatePicker(selection: $selectedDate, in: ...Date())
                    .opacity(isUnknown ? 0.35 : 1)
                    .disabled(isUnknown)

                Toggle(isOn: $isUnknown) {
                    Text(L10n.t("التاريخ غير معروف", "Date unknown"))
                        .font(DS.Font.scaled(13, weight: .semibold))
                        .foregroundColor(DS.Color.textPrimary)
                }
                .tint(DS.Color.primary)
            }
        }
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

/// صورة العضو
struct EditMemberPhotoSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickedItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var isSaving = false

    var body: some View {
        StationSheetShell(
            icon: "camera.fill",
            tint: DS.Color.secondary,
            title: L10n.t("صورة العضو", "Member Photo"),
            memberName: member.fullName,
            isSaving: isSaving,
            canSave: pickedImage != nil,
            onSave: save
        ) {
            VStack(spacing: DS.Spacing.lg) {
                if let img = pickedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                } else {
                    ZStack {
                        Circle().fill(DS.Color.surface).frame(width: 96, height: 96)
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(DS.Font.scaled(26, weight: .light))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }

                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Text(L10n.t("اختيار صورة", "Choose photo"))
                        .font(DS.Font.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.secondary)
                        .padding(.horizontal, DS.Spacing.xl)
                        .padding(.vertical, DS.Spacing.sm + 2)
                        .background(DS.Color.secondary.opacity(0.10), in: Capsule())
                }

                // لا توجد صورة لهذا العضو — يخرجه من تقارير النقص بلا رفع صورة
                Button {
                    markNoPhoto()
                } label: {
                    Text(L10n.t("لا توجد صورة لهذا العضو", "No photo exists for this member"))
                        .font(DS.Font.caption1)
                        .fontWeight(.semibold)
                        .foregroundColor(DS.Color.textSecondary)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(DS.Color.background, in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(DS.Color.textTertiary.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(DSScaleButtonStyle())
                .onChange(of: pickedItem) { item in
                    Task {
                        guard let data = try? await item?.loadTransferable(type: Data.self),
                              let img = UIImage(data: data) else { return }
                        pickedImage = img
                    }
                }
            }
        }
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

/// يقيس ارتفاع محتوى الشيت ليأخذ الشيت حجمه بدل ارتفاع ثابت
private struct SheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
