import SwiftUI
import UIKit

// MARK: - مركز التقارير (تصميم صفحات الإدارة الموحّد — طلب المالك ٢٠٢٦-٠٩-٢٧)
//
// من الأعلى: بطاقة رأس بلون بلاطة «تقارير PDF» في لوحة الإدارة وأرقامها الحيّة ← «تصفية»: بحث
// وفلاتر الحالة بعددها (+ نطاق العمر عند اختيار حقل «العمر») ← «معلومات التقرير» (العنوان والفرع)
// ← «الحقول» ← «نتائج التقرير» (تحديد الأعضاء) ← شريط سفلي ثابت: النطاق + «إنشاء تقرير PDF» بالكحلي.
// كل الحسابات والتصفية والتحديد وإنشاء الـ PDF ومشاركته (`ActivityView`) كما كانت تماماً.
// (اختيار «نوع التقرير» لم يكن معروضاً في الصفحة، فالتقرير يبقى «الأسماء» كما كان.)
struct AdminReportsView: View {
    @EnvironmentObject private var memberVM: MemberViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum ReportType: String, CaseIterable {
        case family
        case age
        case phone
        case missingPhone

        var label: String {
            switch self {
            case .family: return "الأسماء"
            case .age: return "الأعمار"
            case .phone: return "الهواتف"
            case .missingPhone: return "بدون هاتف"
            }
        }

        var icon: String {
            switch self {
            case .family: return "person.text.rectangle.fill"
            case .age: return "calendar"
            case .phone: return "phone.fill"
            case .missingPhone: return "phone.down.fill"
            }
        }

        var tint: Color {
            switch self {
            case .family: return DS.Color.accent
            case .age: return DS.Color.secondary
            case .phone: return AppSection.admin.ink
            case .missingPhone: return DS.Color.warning
            }
        }

        var exportBaseName: String {
            switch self {
            case .family: return "family_report"
            case .age: return "age_report"
            case .phone: return "phone_report"
            case .missingPhone: return "missing_phone_report"
            }
        }
    }

    enum StatusFilter: CaseIterable {
        case all
        case alive
        case deceased
        case withPhone
        case withoutPhone

        var label: String {
            switch self {
            case .all: return L10n.t("الكل", "All")
            case .alive: return L10n.t("أحياء", "Alive")
            case .deceased: return L10n.t("متوفون", "Deceased")
            case .withPhone: return L10n.t("بهاتف", "With phone")
            case .withoutPhone: return L10n.t("بدون هاتف", "No phone")
            }
        }

        /// أيقونة الخيار في شريط فلاتر الحالة
        var icon: String {
            switch self {
            case .all: return "person.3.fill"
            case .alive: return "heart.fill"
            case .deceased: return "leaf.fill"
            case .withPhone: return "phone.fill"
            case .withoutPhone: return "phone.down.fill"
            }
        }
    }

    /// الحقول الديناميكية المتاحة للتقرير
    enum ReportField: String, CaseIterable, Identifiable {
        case fullName, firstName, phone, age, birthDate, deathDate, role, status, gender, married

        var id: String { rawValue }

        var label: String {
            switch self {
            case .fullName: return "الاسم الكامل"
            case .firstName: return "الاسم الأول"
            case .phone: return "رقم الهاتف"
            case .age: return "العمر"
            case .birthDate: return "تاريخ الميلاد"
            case .deathDate: return "تاريخ الوفاة"
            case .role: return "الدور"
            case .status: return "الحالة"
            case .gender: return "الجنس"
            case .married: return "متزوج"
            }
        }

        /// عنوان الحقل في الواجهة — `label` يبقى للـ PDF (عناوين أعمدته عربية دائماً)
        var title: String {
            switch self {
            case .fullName: return L10n.t("الاسم الكامل", "Full name")
            case .firstName: return L10n.t("الاسم الأول", "First name")
            case .phone: return L10n.t("رقم الهاتف", "Phone")
            case .age: return L10n.t("العمر", "Age")
            case .birthDate: return L10n.t("تاريخ الميلاد", "Birth date")
            case .deathDate: return L10n.t("تاريخ الوفاة", "Death date")
            case .role: return L10n.t("الدور", "Role")
            case .status: return L10n.t("الحالة", "Status")
            case .gender: return L10n.t("الجنس", "Gender")
            case .married: return L10n.t("متزوج", "Married")
            }
        }

        var icon: String {
            switch self {
            case .fullName: return "person.fill"
            case .firstName: return "tag.fill"
            case .phone: return "phone.fill"
            case .age: return "calendar"
            case .birthDate: return "calendar.badge.plus"
            case .deathDate: return "leaf.fill"
            case .role: return "star.fill"
            case .status: return "circle.lefthalf.filled"
            case .gender: return "person.2.fill"
            case .married: return "heart.fill"
            }
        }

        /// نسبة العرض النسبية في PDF
        var ratio: CGFloat {
            switch self {
            case .fullName: return 0.40
            case .firstName: return 0.18
            case .phone: return 0.20
            case .age: return 0.10
            case .birthDate: return 0.16
            case .deathDate: return 0.16
            case .role: return 0.12
            case .status: return 0.14
            case .gender: return 0.10
            case .married: return 0.10
            }
        }
    }

    @State private var selectedReport: ReportType = .family
    @State private var searchText = ""
    @State private var minAgeText = ""
    @State private var maxAgeText = ""
    @State private var statusFilter: StatusFilter = .all
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var displayLimit = 20
    @State private var isGenerating = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var branchRootId: UUID? = nil
    @State private var branchPickerOpen = false
    @State private var customTitle: String = "تقرير عائلة المحمدعلي"
    @State private var selectedFields: Set<ReportField> = [.fullName, .phone, .age]

    /// لون بلاطة «تقارير PDF» في لوحة الإدارة — رأس الصفحة يطابق البلاطة التي ضُغطت
    private let pageTint = DS.Color.composerLibrary

    /// حقلا نطاق العمر — الضغط حول الحقل (مساحة ٤٤ نقطة) يفتح الكتابة فيه
    private enum AgeBound: Hashable { case min, max }
    @FocusState private var focusedAge: AgeBound?

    private var ageRangeInvalid: Bool {
        let minVal = Int(minAgeText) ?? 0
        let maxVal = Int(maxAgeText) ?? 0
        return minVal > 0 && maxVal > 0 && minVal > maxVal
    }

    private var activeMembers: [FamilyMember] {
        memberVM.allMembers.filter {
            $0.role != .pending &&
            !$0.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var childrenByFather: [UUID: [FamilyMember]] {
        var map: [UUID: [FamilyMember]] = [:]
        for m in memberVM.allMembers {
            if let f = m.fatherId {
                map[f, default: []].append(m)
            }
        }
        return map
    }

    private func descendantIds(of rootId: UUID) -> Set<UUID> {
        var ids: Set<UUID> = [rootId]
        var stack = [rootId]
        let kidsMap = childrenByFather
        while let cur = stack.popLast() {
            for c in kidsMap[cur] ?? [] {
                if !ids.contains(c.id) {
                    ids.insert(c.id)
                    stack.append(c.id)
                }
            }
        }
        return ids
    }

    private var branchRootMember: FamilyMember? {
        guard let id = branchRootId else { return nil }
        return memberVM.allMembers.first { $0.id == id }
    }

    private var filteredMembers: [FamilyMember] {
        var members = activeMembers

        if let rootId = branchRootId {
            let ids = descendantIds(of: rootId)
            members = members.filter { ids.contains($0.id) }
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            members = members.filter {
                $0.fullName.localizedCaseInsensitiveContains(trimmedSearch) ||
                $0.firstName.localizedCaseInsensitiveContains(trimmedSearch) ||
                normalizedPhone(for: $0).contains(trimmedSearch)
            }
        }

        switch statusFilter {
        case .all:
            break
        case .alive:
            members = members.filter { $0.isDeceased != true }
        case .deceased:
            members = members.filter { $0.isDeceased == true }
        case .withPhone:
            members = members.filter { !normalizedPhone(for: $0).isEmpty && $0.isDeceased != true }
        case .withoutPhone:
            members = members.filter { normalizedPhone(for: $0).isEmpty && $0.isDeceased != true }
        }

        if needsAgeFilter {
            let minAgeVal = Int(minAgeText) ?? 0
            let maxAgeVal = Int(maxAgeText) ?? 0
            if minAgeVal > 0 || maxAgeVal > 0 {
                members = members.filter { member in
                    guard let age = ageForMember(member) else { return false }
                    if minAgeVal > 0 && age < minAgeVal { return false }
                    if maxAgeVal > 0 && age > maxAgeVal { return false }
                    return true
                }
            }
        }

        switch selectedReport {
        case .family:
            members.sort { $0.fullName < $1.fullName }

        case .age:
            members = members.filter { member in
                guard member.isDeceased != true else { return false }
                guard !normalizedBirth(for: member).isEmpty else { return false }
                guard let age = ageForMember(member) else { return false }
                return age > 0
            }
            members.sort { (ageForMember($0) ?? 0) > (ageForMember($1) ?? 0) }

        case .phone:
            members = members.filter { !normalizedPhone(for: $0).isEmpty }
            members.sort { $0.fullName < $1.fullName }

        case .missingPhone:
            members = members.filter { normalizedPhone(for: $0).isEmpty }
            members.sort { $0.fullName < $1.fullName }
        }

        return members
    }

    /// أول `displayLimit` من النتائج — `members` هي `filteredMembers` محسوبة مرة واحدة في `body`
    private func visibleMembers(of members: [FamilyMember]) -> [FamilyMember] {
        Array(members.prefix(displayLimit))
    }

    private var activeFilterCount: Int {
        var count = 0
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if statusFilter != .all { count += 1 }
        if needsAgeFilter &&
            ((Int(minAgeText) ?? 0) > 0 || (Int(maxAgeText) ?? 0) > 0) {
            count += 1
        }
        if branchRootId != nil { count += 1 }
        return count
    }

    /// النطاق: المحدّدون من النتائج، أو كل النتائج إن لم يُحدَّد أحد — `members` = `filteredMembers`
    private func selectedCount(in members: [FamilyMember]) -> Int {
        selectedMemberIds.isEmpty ? members.count : members.filter { selectedMemberIds.contains($0.id) }.count
    }

    /// عدد أعضاء التقرير لكل خيار حالة (لشريط الفلاتر) — نفس شروط `filteredMembers` تماماً
    /// (الفرع، البحث، نطاق العمر ونوع التقرير) بلا فرز، وبمرور واحد على الأعضاء.
    private func statusCounts() -> [StatusFilter: Int] {
        var pool = activeMembers

        if let rootId = branchRootId {
            let ids = descendantIds(of: rootId)
            pool = pool.filter { ids.contains($0.id) }
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            pool = pool.filter {
                $0.fullName.localizedCaseInsensitiveContains(trimmedSearch) ||
                $0.firstName.localizedCaseInsensitiveContains(trimmedSearch) ||
                normalizedPhone(for: $0).contains(trimmedSearch)
            }
        }

        let minAgeVal = Int(minAgeText) ?? 0
        let maxAgeVal = Int(maxAgeText) ?? 0
        let usesAgeRange = needsAgeFilter && (minAgeVal > 0 || maxAgeVal > 0)

        var counts: [StatusFilter: Int] = [:]
        for member in pool {
            let noPhone = normalizedPhone(for: member).isEmpty
            let deceased = member.isDeceased == true

            // نطاق العمر — يطبَّق متى ظهر حقلاه (حقل «العمر» مختار) لا لنوع تقرير مخفي
            if usesAgeRange {
                guard let age = ageForMember(member) else { continue }
                if minAgeVal > 0 && age < minAgeVal { continue }
                if maxAgeVal > 0 && age > maxAgeVal { continue }
            }

            // شروط نوع التقرير
            switch selectedReport {
            case .family:
                break
            case .age:
                guard !deceased, !normalizedBirth(for: member).isEmpty,
                      let age = ageForMember(member), age > 0 else { continue }
            case .phone:
                if noPhone { continue }
            case .missingPhone:
                if !noPhone { continue }
            }

            counts[.all, default: 0] += 1
            if deceased {
                counts[.deceased, default: 0] += 1
            } else {
                counts[.alive, default: 0] += 1
                counts[noPhone ? .withoutPhone : .withPhone, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - Body

    var body: some View {
        // نتائج التقرير تُحسب مرة واحدة لكل رسم (كانت تُعاد مع كل استخدام) — نفس `filteredMembers`
        let members = filteredMembers
        let loaded = !memberVM.allMembers.isEmpty

        return ScrollView(showsIndicators: false) {
            pageContent(members: members, loaded: loaded)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xxxl)
                // ⚠️ مهم: نعلّق مربّع الفرع على المحتوى الداخلي عشان لا يتزاحم
                // مع sheet المشاركة المعلّق على الـScrollView. SwiftUI لا يدعم
                // sheet متعدد على نفس الـView — يتم تجاهل الـsheet الثاني.
                .dsTallBox(isPresented: $branchPickerOpen) {   // شجرة فروع طويلة (توصية أبل)
                    BranchPickerSheet(
                        allMembers: memberVM.allMembers,
                        selectedId: branchRootId,
                        onSelect: { id in
                            branchRootId = id
                            branchPickerOpen = false
                            displayLimit = 20
                        }
                    )
                }
        }
        .scrollDismissesKeyboard(.interactively)
        // التصدير مثبّت أسفل الصفحة (مثل شريط أزرار المربّعات) — النطاق يتحدّث مع التصفية والتحديد
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if loaded {
                exportBar(members: members)
            }
        }
        // الرأس الملوّن الموحّد (كان شريط النظام + بطاقة رأس)
        .dsSubPageHeader(L10n.t("مركز التقارير", "Reports Center"),
                         subtitle: L10n.t("اختر الأعضاء والحقول، ثم صدّر ملف PDF للطباعة أو المشاركة",
                                          "Pick members and fields, then export a PDF to print or share"))
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            if memberVM.allMembers.isEmpty {
                await memberVM.fetchAllMembers()
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: { cleanupShareState() }) {
            ActivityView(items: shareItems) {
                cleanupShareState()
            }
        }
        .dsAlert(L10n.t("خطأ", "Error"), isPresented: $showErrorAlert) {
            Button(L10n.t("موافق", "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - هيكل الصفحة

    private func pageContent(members: [FamilyMember], loaded: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            hero(members: members, loaded: loaded)

            if loaded {
                filtersBlock

                // الوضع الأفقي: الأقسام على عمودين
                AdaptiveCardStack(spacing: DS.Spacing.md) {
                    infoSection
                    fieldsSection
                    if members.isEmpty {
                        noResultsCard
                    } else {
                        resultsSection(members: members)
                    }
                }
            } else {
                membersStateCard
                    .padding(.top, DS.Spacing.xs)
                    .dsStaggerIn(1)
            }
        }
    }

    // MARK: - بطاقة الرأس

    /// ٣ أرقام حيّة من بيانات الصفحة نفسها (بلا طلبات جديدة): الأعضاء المتاحون للتقارير، ومن سيدخل
    /// الملف الآن (النطاق)، وعدد الحقول المختارة — «—» قبل تحميل الأعضاء.
    private func hero(members: [FamilyMember], loaded: Bool) -> some View {
        // العنوان والوصف في الرأس الملوّن — الأرقام هنا
        DSStatsRow([
                DSHeroStat(value: loaded ? "\(activeMembers.count)" : "—",
                           label: L10n.t("الأعضاء", "Members"), icon: "person.3.fill"),
                DSHeroStat(value: loaded ? "\(selectedCount(in: members))" : "—",
                           label: L10n.t("في التقرير", "In report"), icon: "doc.richtext.fill"),
                DSHeroStat(value: "\(selectedFields.count)",
                           label: L10n.t("الحقول", "Fields"), icon: "list.bullet.rectangle.fill")
        ], tint: pageTint)
    }

    // MARK: - حالة الأعضاء (قبل التحميل)

    /// لا أعضاء محمّلين بعد: فشل التحميل (مع إعادة نفس الجلب) · جارٍ التحميل
    @ViewBuilder
    private var membersStateCard: some View {
        if memberVM.membersLoadFailed {
            DSStateCard(icon: "wifi.exclamationmark",
                         title: L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                         hint: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                         tint: DS.Color.error,
                         actionTitle: L10n.t("إعادة المحاولة", "Retry"),
                         action: { Task { await memberVM.fetchAllMembers(force: true) } })
        } else {
            DSPageLoader(L10n.t("جارٍ تحميل الأعضاء…", "Loading members…"), fillsSpace: false)
                .padding(.top, DS.Spacing.lg)
        }
    }

    // MARK: - التصفية

    /// بحث + فلاتر الحالة بعددها (+ نطاق العمر) — نفس خيارات «تصفية» السابقة
    @ViewBuilder
    private var filtersBlock: some View {
        DSSectionTitle(title: L10n.t("تصفية", "Filter"),
                        icon: "person.crop.circle.badge.checkmark",
                        tint: pageTint,
                        trailing: activeFilterCount > 0
                            ? L10n.t("\(activeFilterCount) مفعّلة", "\(activeFilterCount) active")
                            : nil)
            .dsStaggerIn(1)

        DSSearchField(text: $searchText,
                      placeholder: L10n.t("بحث بالاسم أو الرقم…", "Search by name or number…"),
                      tint: pageTint)
            .onChange(of: searchText) { _ in displayLimit = 20 }
            .dsStaggerIn(1)

        statusChips
            .dsStaggerIn(1)

        if needsAgeFilter {
            ageRangeRow
                .dsStaggerIn(1)
        }
    }

    /// فلتر الحالة (كان شريطاً مقسّماً) — العدد = من سيدخل التقرير بهذا الخيار، ويظهر إن كان أكبر من صفر
    private var statusChips: some View {
        let counts = statusCounts()
        return DSFilterChips(
            options: StatusFilter.allCases.map { status in
                let n = counts[status] ?? 0
                return DSFilterOption(id: status, title: status.label, icon: status.icon,
                                      count: n > 0 ? n : nil)
            },
            selection: $statusFilter,
            tint: pageTint
        )
        .onChange(of: statusFilter) { _ in displayLimit = 20 }
    }

    /// نطاق العمر (من → إلى) بإطار حقل البحث — يحمرّ مع «غلط» إن كان «من» أكبر من «إلى»
    private var ageRangeRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "calendar", tint: DS.Color.warning)
                .accessibilityHidden(true)
            Text(L10n.t("العمر", "Age"))
                .dsFieldFont(.rowTitle)
                .foregroundColor(DS.Color.fieldLabel)
                .lineLimit(1)
            Spacer(minLength: DS.Spacing.xs)
            ageField(.min)
                .onChange(of: minAgeText) { _ in displayLimit = 20 }
            Image(systemName: L10n.isArabic ? "arrow.left" : "arrow.right")
                .dsGlyph(DS.Glyph.xs)
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)
            ageField(.max)
                .onChange(of: maxAgeText) { _ in displayLimit = 20 }
            if ageRangeInvalid {
                DSStatusChip(text: L10n.t("غلط", "Invalid"),
                              icon: "exclamationmark.triangle.fill",
                              tint: DS.Color.error)
                    .fixedSize()
            }
        }
        .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xxs)
        .frame(minHeight: DS.Icon.tapTarget + DS.Spacing.sm)
        .dsFocusFieldBox(focused: false, invalid: ageRangeInvalid, fill: DS.Color.surface)
    }

    private func ageField(_ bound: AgeBound) -> some View {
        let isMin = bound == .min
        let focused = focusedAge == bound
        return TextField(isMin ? L10n.t("من", "From") : L10n.t("إلى", "To"),
                         text: isMin ? $minAgeText : $maxAgeText)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .dsFieldFont(.headlineCompact)
            .foregroundColor(DS.Color.textPrimary)
            .monospacedDigit()
            .focused($focusedAge, equals: bound)
            .frame(width: DS.Icon.sizeLg, height: DSBox.fieldMinHeight)
            .dsFocusFieldBox(focused: focused, tint: pageTint, invalid: ageRangeInvalid, radius: DS.Radius.sm)
            .padding(.vertical, DS.Spacing.xs)   // مساحة ضغط ٤٤ نقطة
            .contentShape(Rectangle())
            .onTapGesture { focusedAge = bound }
            .accessibilityLabel(isMin ? L10n.t("العمر من", "Minimum age") : L10n.t("العمر إلى", "Maximum age"))
    }

    // MARK: - معلومات التقرير

    private var infoSection: some View {
        DSComposerSection(title: L10n.t("معلومات التقرير", "Report info"),
                          icon: "doc.text",
                          tint: pageTint,
                          index: 2) {
            // الفارغ يُنشأ بالعنوان الافتراضي — فيظهر هو كنص إرشادي
            DSComposerField(icon: "textformat",
                            label: L10n.t("عنوان التقرير", "Report title"),
                            placeholder: "تقرير عائلة المحمدعلي",
                            text: $customTitle,
                            tint: pageTint)

            branchFilterRow
        }
    }

    /// حصر التقرير على فرع: صف يفتح مربّع الفروع، وبعد الاختيار اسم الفرع وعدده + «تغيير» و«إزالة»
    private var branchFilterRow: some View {
        Group {
            if let m = branchRootMember {
                let count = descendantIds(of: m.id).count
                DSRow(icon: "tree.fill", tint: pageTint,
                       title: L10n.t("فرع: \(m.displayFullName)", "Branch: \(m.displayFullName)"),
                       subtitle: L10n.t("\(count) عضو في الفرع", "\(count) members in branch")) {
                    HStack(spacing: DS.Spacing.xs) {
                        toolButton(title: L10n.t("تغيير", "Change"), icon: nil, tint: pageTint) {
                            branchPickerOpen = true
                        }
                        Button {
                            branchRootId = nil
                            displayLimit = 20
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .dsGlyph(DS.Glyph.xl, weight: .semibold)
                                .foregroundColor(DS.Color.error)
                                .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, -DS.Spacing.xsm)
                        .accessibilityLabel(L10n.t("إزالة الفرع", "Remove branch"))
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(pageTint.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
            } else {
                Button {
                    branchPickerOpen = true
                } label: {
                    DSRow(icon: "tree", tint: DS.Color.textSecondary,
                           title: L10n.t("حصر على فرع معيّن", "Filter by branch"),
                           subtitle: L10n.t("كل الفروع", "All branches")) {
                        DSChevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(DSScaleButtonStyle())
            }
        }
    }

    // MARK: - الحقول

    private var fieldsSection: some View {
        DSComposerSection(title: L10n.t("الحقول", "Fields"),
                          icon: "list.bullet.rectangle",
                          tint: pageTint,
                          trailing: L10n.t("\(selectedFields.count) مختارة", "\(selectedFields.count) selected"),
                          index: 3) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: DS.Spacing.sm)],
                      alignment: .leading,
                      spacing: DS.Spacing.xs) {
                ForEach(ReportField.allCases) { field in
                    fieldChip(field)
                }
            }
        }
    }

    /// حقل يُضاف للتقرير أو يُزال (يبقى حقل واحد على الأقل) — المختار بلون الصفحة وعلامة ✓
    private func fieldChip(_ field: ReportField) -> some View {
        let active = selectedFields.contains(field)
        return Button {
            withAnimation(reduceMotion ? nil : DS.Anim.quick) {
                if active {
                    if selectedFields.count > 1 {
                        selectedFields.remove(field)
                    }
                } else {
                    selectedFields.insert(field)
                }
            }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: active ? "checkmark.circle.fill" : field.icon)
                    .dsGlyph(DS.Glyph.smCompact)
                    .foregroundColor(active ? pageTint : DS.Color.textTertiary)
                    .accessibilityHidden(true)
                Text(field.title)
                    .dsFieldFont(.chip)
                    .foregroundColor(active ? DS.Color.fieldLabel : DS.Color.fieldValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: DS.Icon.avatar)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(active ? pageTint.opacity(DS.Opacity.tintFill) : DS.Color.background))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(active ? pageTint.opacity(DS.Opacity.selectedStroke) : DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke),
                              lineWidth: active ? DS.Border.widthBold : DS.Border.width))
            .padding(.vertical, DS.Spacing.xxs)   // مساحة ضغط ٤٤ نقطة
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(field.title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: - نتائج التقرير

    private func resultsSection(members: [FamilyMember]) -> some View {
        DSComposerSection(title: L10n.t("نتائج التقرير", "Report results"),
                          icon: selectedReport.icon,
                          tint: pageTint,
                          trailing: resultsTrailing(members: members),
                          index: 4) {
            resultsTools(members: members)

            LazyVStack(spacing: DS.Spacing.sm) {
                ForEach(visibleMembers(of: members)) { member in
                    memberRow(member)
                }
            }

            if displayLimit < members.count {
                loadMoreButton(remaining: members.count - displayLimit)
            }
        }
    }

    /// «٢٥ عضو» — ومع التحديد «٣ محدّد · ٢٥ عضو»
    private func resultsTrailing(members: [FamilyMember]) -> String {
        let total = members.count
        guard !selectedMemberIds.isEmpty else { return L10n.t("\(total) عضو", "\(total) members") }
        let picked = selectedCount(in: members)
        return L10n.t("\(picked) محدّد · \(total) عضو", "\(picked) selected · \(total) members")
    }

    /// تحديد الكل · إلغاء التحديد · إعادة ضبط (مع تصفية مفعّلة) — نفس الأزرار السابقة
    private func resultsTools(members: [FamilyMember]) -> some View {
        HStack(spacing: DS.Spacing.xsm) {
            toolButton(title: L10n.t("تحديد الكل", "Select all"), icon: "checkmark.circle.fill",
                       tint: AppSection.admin.ink) {
                selectedMemberIds = Set(members.map(\.id))
            }

            toolButton(title: L10n.t("إلغاء التحديد", "Clear selection"), icon: "xmark.circle.fill",
                       tint: DS.Color.error) {
                selectedMemberIds.removeAll()
            }

            if activeFilterCount > 0 {
                toolButton(title: L10n.t("إعادة ضبط", "Reset"), icon: "arrow.counterclockwise",
                           tint: pageTint) {
                    resetFilters()
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// الشريحة الواحدة (`DSChipButton`) — مساحة ضغط ٤٤ بلا تكبير الصف
    private func toolButton(title: String, icon: String?, tint: Color,
                            action: @escaping () -> Void) -> some View {
        DSChipButton(title, icon: icon, tint: tint, action: action)
    }

    /// صف عضو بإطار صفوف المربّعات: الصورة + الاسم (وورقة للمتوفى) + العمر/الهاتف كما كانت
    /// + دائرة التحديد. الضغط يحدّده للتقرير أو يلغيه — والمحدّد بإطار كحلي أوضح.
    private func memberRow(_ member: FamilyMember) -> some View {
        let selected = selectedMemberIds.contains(member.id)
        let phone = normalizedPhone(for: member)
        let deceased = member.isDeceased == true
        let age: Int? = needsAgeFilter
            ? ageForMember(member).flatMap { $0 > 0 ? $0 : nil }
            : nil
        let missingPhone = phone.isEmpty && selectedReport == .missingPhone

        return Button {
            toggleSelection(member.id)
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSMemberAvatar(name: member.fullName,
                               avatarUrl: member.avatarUrl,
                               size: DS.Icon.avatarRow,
                               roleColor: deceased ? DS.Color.textTertiary : member.roleColor)

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(member.displayFullName)
                            .dsFieldFont(.rowTitle)
                            .foregroundColor(DS.Color.fieldLabel)
                            .lineLimit(1)
                        if deceased {
                            Image(systemName: "leaf.fill")
                                .dsGlyph(DS.Glyph.micro, weight: .semibold)
                                .foregroundColor(DS.Color.textTertiary)
                        }
                    }

                    if age != nil || !phone.isEmpty || missingPhone {
                        HStack(spacing: DS.Spacing.sm) {
                            if let age {
                                detailText(icon: "calendar", text: L10n.t("\(age) سنة", "\(age) yrs"))
                            }
                            if !phone.isEmpty {
                                detailText(icon: "phone.fill", text: KuwaitPhone.display(phone))
                            } else if missingPhone {
                                DSStatusChip(text: L10n.t("رقم ناقص", "Missing number"),
                                              icon: "exclamationmark.triangle.fill",
                                              tint: DS.Color.warning)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .dsGlyph(DS.Glyph.xxlCompact, weight: .semibold)
                    .foregroundColor(selected ? AppSection.admin.ink : DS.Color.textTertiary)
            }
            .frame(minHeight: DSBox.fieldMinHeight)
            .dsRowBox()
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(AppSection.admin.ink.opacity(DS.Opacity.selectedStroke), lineWidth: DS.Border.widthBold)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rowAccessibilityLabel(member, phone: phone, age: age, missingPhone: missingPhone))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func detailText(icon: String, text: String) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            Image(dsSymbol: icon)
                .dsGlyph(DS.Glyph.micro, weight: .semibold)
            Text(text)
                .dsFont(.subtitle)
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundColor(DS.Color.fieldValue)
    }

    private func rowAccessibilityLabel(_ member: FamilyMember, phone: String, age: Int?,
                                       missingPhone: Bool) -> String {
        var parts = [member.displayFullName]
        if member.isDeceased == true { parts.append(L10n.t("متوفى", "Deceased")) }
        if let age { parts.append(L10n.t("\(age) سنة", "\(age) years")) }
        if !phone.isEmpty {
            parts.append(KuwaitPhone.display(phone))
        } else if missingPhone {
            parts.append(L10n.t("رقم ناقص", "Missing number"))
        }
        return parts.joined(separator: "، ")
    }

    /// الشريحة الواحدة بلون الصفحة (مساحة ضغط ٤٤)
    private func loadMoreButton(remaining: Int) -> some View {
        DSChipButton(L10n.t("عرض المزيد (\(remaining) متبقي)", "Show more (\(remaining) remaining)"),
                     icon: "arrow.down.circle.fill", tint: pageTint) {
            displayLimit += 20
        }
        .frame(maxWidth: .infinity)
    }

    /// لا أحد يطابق — ومع تصفية مفعّلة «إعادة ضبط» (نفس زر أدوات النتائج)
    private var noResultsCard: some View {
        let filtered = activeFilterCount > 0
        let reset: (() -> Void)? = filtered ? { resetFilters() } : nil
        return DSEmptyView(L10n.t("لا يوجد أعضاء", "No members"),
                           message: filtered
                               ? L10n.t("لا أحد يطابق التصفية الحالية", "No one matches the current filters")
                               : nil,
                           actionTitle: filtered ? L10n.t("إعادة ضبط", "Reset") : nil,
                           actionIcon: "arrow.counterclockwise",
                           style: .compact,
                           action: reset)
            .dsCard(padding: nil)
            .dsStaggerIn(4)
    }

    // MARK: - التصدير

    /// شريط سفلي ثابت: «إنشاء تقرير PDF» بالكحلي الموحّد (يمين) + النطاق (يسار) — نفس شرط التعطيل
    private func exportBar(members: [FamilyMember]) -> some View {
        let scope = selectedCount(in: members)
        return HStack(spacing: DS.Spacing.md) {
            DSActionButton(title: L10n.t("إنشاء تقرير PDF", "Generate PDF Report"),
                            icon: "doc.richtext.fill",
                            isBusy: isGenerating,
                            enabled: !(isGenerating || members.isEmpty || ageRangeInvalid)) {
                Task { await generatePDF() }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(selectedMemberIds.isEmpty
                     ? L10n.t("النطاق: الكل", "Scope: all")
                     : L10n.t("النطاق: المحدّدون", "Scope: selected"))
                    .dsFont(.micro)
                    .foregroundColor(DS.Color.fieldValue)
                Text(L10n.t("\(scope) عضو", "\(scope) members"))
                    .dsFont(.headline)
                    .foregroundColor(DS.Color.fieldLabel)
                    .monospacedDigit()
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .dsGlass(Rectangle())
        .overlay(Divider(), alignment: .top)
    }

    // متى نظهر نطاق العمر — ومتى نطبّقه (كان يظهر مع حقل «العمر» ولا يصفّي شيئاً: نوع التقرير ثابت «الأسماء»)
    private var needsAgeFilter: Bool {
        selectedReport == .age || selectedReport == .phone || selectedFields.contains(.age)
    }

    private func toggleSelection(_ id: UUID) {
        if selectedMemberIds.contains(id) {
            selectedMemberIds.remove(id)
        } else {
            selectedMemberIds.insert(id)
        }
    }

    private func resetFilters() {
        searchText = ""
        minAgeText = ""
        maxAgeText = ""
        statusFilter = .all
        displayLimit = 20
        selectedMemberIds.removeAll()
        branchRootId = nil
    }

    private func cleanupShareState() {
        showShareSheet = false
        shareItems.removeAll()
    }

    private func normalizedPhone(for member: FamilyMember) -> String {
        (member.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedBirth(for member: FamilyMember) -> String {
        (member.birthDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ageForMember(_ member: FamilyMember) -> Int? {
        guard let birthDate = parsedBirthDate(member.birthDate) else { return nil }
        // للمتوفّى مع تاريخ وفاة → عمر الوفاة (من الميلاد إلى الوفاة)
        // للحيّ أو متوفى بدون تاريخ وفاة → للحين
        let endDate: Date
        if member.isDeceased == true,
           let deathStr = member.deathDate,
           let parsedDeath = parsedBirthDate(deathStr) {
            endDate = parsedDeath
        } else if member.isDeceased == true {
            // متوفى بدون تاريخ وفاة → ما نقدر نحسب
            return nil
        } else {
            endDate = Date()
        }
        guard let years = Calendar.current.dateComponents([.year], from: birthDate, to: endDate).year else {
            return nil
        }
        return years >= 0 ? years : nil
    }

    /// استخراج قيمة حقل لعضو — يستخدم في الـ PDF
    static func formatField(
        _ field: ReportField,
        for member: FamilyMember,
        ageResolver: (FamilyMember) -> Int?
    ) -> String {
        switch field {
        case .fullName:
            return member.fullName
        case .firstName:
            return member.firstName
        case .phone:
            let phone = (member.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return phone.isEmpty ? "—" : KuwaitPhone.display(phone)
        case .age:
            return ageResolver(member).map { "\($0)" } ?? "—"
        case .birthDate:
            return (member.birthDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "—" : (member.birthDate ?? "—")
        case .deathDate:
            return (member.deathDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "—" : (member.deathDate ?? "—")
        case .role:
            return member.roleName
        case .status:
            if member.isDeceased == true { return "متوفى" }
            if member.status == .frozen { return "مجمّد" }
            let phone = (member.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if phone.isEmpty { return "بدون هاتف" }
            return "نشط"
        case .gender:
            switch member.gender {
            case "male": return "ذكر"
            case "female": return "أنثى"
            default: return "—"
            }
        case .married:
            switch member.isMarried {
            case true: return "نعم"
            case false: return "لا"
            default: return "—"
            }
        }
    }

    private func parsedBirthDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: raw) { return date }
        let iso = ISO8601DateFormatter()
        return iso.date(from: raw)
    }

    private func generatePDF() async {
        await MainActor.run { isGenerating = true }

        let sourceMembers = selectedMemberIds.isEmpty
            ? filteredMembers
            : filteredMembers.filter { selectedMemberIds.contains($0.id) }

        guard !sourceMembers.isEmpty else {
            await MainActor.run {
                isGenerating = false
                errorMessage = L10n.t("لا يوجد أعضاء لإنشاء التقرير.", "No members to include in the report.")
                showErrorAlert = true
            }
            return
        }

        var filters: [String] = []
        let minAgeVal = Int(minAgeText) ?? 0
        let maxAgeVal = Int(maxAgeText) ?? 0
        if needsAgeFilter {
            if minAgeVal > 0 && maxAgeVal > 0 {
                filters.append("العمر: \(minAgeVal) - \(maxAgeVal)")
            } else if minAgeVal > 0 {
                filters.append("العمر: من \(minAgeVal)")
            } else if maxAgeVal > 0 {
                filters.append("العمر: إلى \(maxAgeVal)")
            }
        }
        if statusFilter == .alive { filters.append("أحياء فقط") }
        if statusFilter == .deceased { filters.append("متوفين فقط") }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filters.append("بحث: \(searchText)")
        }
        if let m = branchRootMember {
            filters.append("فرع: \(m.fullName)")
        }

        // ابنِ أعمدة ديناميكية من الحقول المختارة (مرتبة حسب الـ enum)
        let orderedFields = ReportField.allCases.filter { selectedFields.contains($0) }

        do {
            let reportData = try MembersPDFBuilder.makeCustomReport(
                members: sourceMembers,
                filters: filters,
                title: customTitle.isEmpty ? "تقرير عائلة المحمدعلي" : customTitle,
                accent: selectedReport.tint,
                fields: orderedFields,
                ageResolver: { ageForMember($0) },
                branchName: branchRootMember?.fullName,
                filterLabel: statusFilter.label
            )

            // اسم الملف يشمل الفرع لو محدّد
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            var nameParts: [String] = [
                customTitle.isEmpty ? "report" : customTitle.replacingOccurrences(of: " ", with: "_")
            ]
            if let m = branchRootMember {
                let firstWord = m.fullName.split(separator: " ").first.map(String.init) ?? ""
                if !firstWord.isEmpty { nameParts.append("فرع-\(firstWord)") }
            }
            nameParts.append(formatter.string(from: Date()))
            let fileName = "\(nameParts.joined(separator: "-")).pdf"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try reportData.write(to: fileURL, options: .atomic)

            await MainActor.run {
                shareItems = [fileURL]
                showShareSheet = true
                isGenerating = false
            }
        } catch {
            await MainActor.run {
                isGenerating = false
                errorMessage = L10n.t("فشل إنشاء التقرير.", "Couldn't create the report.")
                showErrorAlert = true
            }
        }
    }
}

private enum MembersPDFBuilder {
    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 36
    private static let rowHeight: CGFloat = 24
    private static let pageBodyTop: CGFloat = 150     // الصفحة الأولى: تحت الهيدر مباشرة (مقرّب)
    private static let pageBodyTopOther: CGFloat = 50 // الصفحات الباقية: قريب من الأعلى
    // ألوان الملف من DS («مكان واحد») — مثبّتة على الفاتح لأن الملف يُطبع على ورق أبيض
    private static func paper(_ color: Color) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    }
    private static let border = paper(DS.Color.textTertiary).withAlphaComponent(DS.Opacity.tintFillStrong)
    private static let softGray = paper(DS.Color.surface).withAlphaComponent(DS.Opacity.disabled)
    private static let headerGray = paper(DS.Color.surface)
    private static let textPrimary = paper(DS.Color.textPrimary)
    private static let textMuted = paper(DS.Color.textSecondary)
    private static let textTertiary = paper(DS.Color.textTertiary)

    private static let titleFont = UIFont.systemFont(ofSize: 26, weight: .black)
    private static let brandFont = UIFont.systemFont(ofSize: 9, weight: .semibold)
    private static let bodyFont = UIFont.systemFont(ofSize: 10, weight: .regular)
    private static let bodyBoldFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
    private static let metaFont = UIFont.systemFont(ofSize: 9, weight: .regular)
    private static let metaBoldFont = UIFont.systemFont(ofSize: 9, weight: .bold)
    private static let smallFont = UIFont.systemFont(ofSize: 8.5, weight: .medium)
    private static let branchFont = UIFont.systemFont(ofSize: 11, weight: .bold)

    private struct ReportColumn {
        let title: String
        let ratio: CGFloat
        let value: (FamilyMember, Int) -> String
    }

    private struct PDFTheme {
        let accent: UIColor
        let title: String
    }

    /// تقرير ديناميكي بالحقول المختارة من قبل المستخدم
    static func makeCustomReport(
        members: [FamilyMember],
        filters: [String],
        title: String,
        accent: Color,
        fields: [AdminReportsView.ReportField],
        ageResolver: @escaping (FamilyMember) -> Int?,
        branchName: String? = nil,
        filterLabel: String? = nil
    ) throws -> Data {
        let uiAccent = UIColor(accent)

        var columns: [ReportColumn] = [
            ReportColumn(title: "م", ratio: 0.06) { _, index in "\(index)" }
        ]
        let fieldsTotalRatio = fields.reduce(0.0) { $0 + $1.ratio }
        let availableRatio: CGFloat = 0.94
        let normalizer: CGFloat = fieldsTotalRatio > 0 ? availableRatio / fieldsTotalRatio : 1.0
        for field in fields {
            let normalizedRatio = field.ratio * normalizer
            columns.append(ReportColumn(title: field.label, ratio: normalizedRatio) { member, _ in
                AdminReportsView.formatField(field, for: member, ageResolver: ageResolver)
            })
        }

        let fieldLabels = fields.map { $0.label }.joined(separator: " • ")

        return try makeMembersTableReport(
            members: members,
            filters: filters,
            theme: PDFTheme(accent: uiAccent, title: title),
            columns: columns,
            branchName: branchName,
            fieldLabels: fieldLabels,
            filterLabel: filterLabel
        )
    }

    private struct ReportContext {
        let title: String
        let count: Int
        let filters: [String]
        let accent: UIColor
        let branchName: String?      // اسم الفرع لو محدد
        let fieldLabels: String?     // أسماء الحقول مفصولة بـ •
        let filterLabel: String?     // فلتر الأعضاء (أحياء/متوفون...)
        let reportNumber: String     // رقم تقرير قصير
    }

    private static func makeMembersTableReport(
        members: [FamilyMember],
        filters: [String],
        theme: PDFTheme,
        columns: [ReportColumn],
        branchName: String? = nil,
        fieldLabels: String? = nil,
        filterLabel: String? = nil
    ) throws -> Data {
        let renderer = makeRenderer(title: theme.title)
        let reportNumber = String(Int.random(in: 100000...999999))
        let context = ReportContext(
            title: theme.title,
            count: members.count,
            filters: filters,
            accent: theme.accent,
            branchName: branchName,
            fieldLabels: fieldLabels,
            filterLabel: filterLabel,
            reportNumber: reportNumber
        )

        return renderer.pdfData { pdf in
            var pageNumber = 1
            var rowIndex = 1
            var y = beginPage(pdf, pageNumber: pageNumber, context: context)
            drawTableHeader(y: y, columns: columns, accent: theme.accent)
            y += rowHeight + 10

            for member in members {
                if y + rowHeight > pageHeight - 70 {
                    drawFooter(pageNumber: pageNumber)
                    pageNumber += 1
                    y = beginPage(pdf, pageNumber: pageNumber, context: context)
                    drawTableHeader(y: y, columns: columns, accent: theme.accent)
                    y += rowHeight + 10
                }

                drawTableRow(y: y, index: rowIndex, member: member, columns: columns, isEven: rowIndex.isMultiple(of: 2))
                y += rowHeight + 4
                rowIndex += 1
            }

            drawFooter(pageNumber: pageNumber)
        }
    }

    private static func makeRenderer(title: String) -> UIGraphicsPDFRenderer {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextAuthor as String: "AlmohamadAli"
        ]
        return UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), format: format)
    }

    private static func beginPage(_ pdf: UIGraphicsPDFRendererContext, pageNumber: Int, context: ReportContext) -> CGFloat {
        pdf.beginPage()
        UIColor.white.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)).fill()
        // الهيدر فقط في الصفحة الأولى
        if pageNumber == 1 {
            drawHeaderCard(context: context)
            return pageBodyTop
        } else {
            return pageBodyTopOther
        }
    }

    private static func drawHeaderCard(context: ReportContext) {
        let leftEdge = margin
        let rightEdge = pageWidth - margin
        let topY: CGFloat = 36
        let contentWidth = rightEdge - leftEdge

        // (1) شعار العائلة "ALMOHAMMADALI FAMILY" — يمين أعلى الصفحة (RTL = visual right)
        let brand = "ALMOHAMMADALI FAMILY"
        drawRTLText(
            brand,
            in: CGRect(x: leftEdge, y: topY, width: contentWidth, height: 12),
            font: brandFont,
            color: textTertiary,
            alignment: .right,
            kern: 2.5
        )

        // (2) التاريخ + رقم التقرير — يسار أعلى الصفحة
        let dateStr = formattedFullDate()
        drawRTLText(
            dateStr,
            in: CGRect(x: leftEdge, y: topY, width: 220, height: 12),
            font: metaBoldFont,
            color: textPrimary,
            alignment: .left
        )
        drawRTLText(
            "تقرير #\(context.reportNumber)",
            in: CGRect(x: leftEdge, y: topY + 14, width: 220, height: 12),
            font: metaFont,
            color: textMuted,
            alignment: .left
        )

        // (3) عنوان التقرير الرئيسي — كبير وعريض
        drawRTLText(
            context.title,
            in: CGRect(x: leftEdge, y: topY + 16, width: contentWidth, height: 36),
            font: titleFont,
            color: textPrimary,
            alignment: .right
        )

        // (4) اسم الفرع (لو موجود) — بلون الـ accent + أيقونة شجرة
        var branchY: CGFloat = topY + 16 + 36
        if let branch = context.branchName, !branch.isEmpty {
            drawRTLText(
                "🌳 فرع \(branch)",
                in: CGRect(x: leftEdge, y: branchY, width: contentWidth, height: 16),
                font: branchFont,
                color: context.accent,
                alignment: .right
            )
            branchY += 18
        }

        // (5) خط فاصل خفيف
        let separatorY = branchY + 6
        let separator = UIBezierPath()
        separator.move(to: CGPoint(x: leftEdge, y: separatorY))
        separator.addLine(to: CGPoint(x: rightEdge, y: separatorY))
        separator.lineWidth = 0.6
        border.setStroke()
        separator.stroke()

        // (6) سطر التفاصيل: العدد + الفلتر + الحقول
        let metaY = separatorY + 6
        var metaParts: [String] = []
        metaParts.append("👥 العدد: \(context.count) عضو")
        if let f = context.filterLabel, !f.isEmpty {
            metaParts.append("🏷️ الفلتر: \(f)")
        }
        if let fields = context.fieldLabels, !fields.isEmpty {
            metaParts.append("📋 الحقول: \(fields)")
        }
        drawRTLText(
            metaParts.joined(separator: "    "),
            in: CGRect(x: leftEdge, y: metaY, width: contentWidth, height: 14),
            font: metaFont,
            color: textMuted,
            alignment: .right
        )
    }

    private static func formattedFullDate() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar")
        f.dateFormat = "EEEE، d MMMM، yyyy"
        return f.string(from: Date())
    }

    private static func drawTableHeader(y: CGFloat, columns: [ReportColumn], accent: UIColor) {
        let rect = CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: rowHeight)
        fillRoundedRect(rect, color: accent.withAlphaComponent(0.12))
        strokeRoundedRect(rect, color: border, lineWidth: 0.8)
        drawColumns(columns.map(\.title), columns: columns, y: y, textColor: textPrimary, font: bodyBoldFont)
    }

    private static func drawTableRow(y: CGFloat, index: Int, member: FamilyMember, columns: [ReportColumn], isEven: Bool) {
        let rect = CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: rowHeight)
        fillRoundedRect(rect, color: isEven ? softGray : UIColor.white)
        strokeRoundedRect(rect, color: border.withAlphaComponent(0.7), lineWidth: 0.8)
        let texts = columns.map { $0.value(member, index) }
        drawColumns(texts, columns: columns, y: y, textColor: textPrimary, font: bodyFont)
    }

    private static func drawColumns(_ texts: [String], columns: [ReportColumn], y: CGFloat, textColor: UIColor, font: UIFont) {
        let totalWidth = pageWidth - margin * 2 - 16
        var cursor = pageWidth - margin - 8

        for (index, column) in columns.enumerated() {
            let width = totalWidth * column.ratio
            let rect = CGRect(x: cursor - width, y: y + 5, width: width - 8, height: rowHeight - 10)
            drawRTFText(texts[index], in: rect, font: font, color: textColor)
            cursor -= width
        }
    }

    private static func drawFooter(pageNumber: Int, drawNow: Bool = true) {
        guard drawNow || UIGraphicsGetCurrentContext() != nil else { return }
        let lineY = pageHeight - 38
        UIColor.systemGray5.setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: lineY))
        path.addLine(to: CGPoint(x: pageWidth - margin, y: lineY))
        path.lineWidth = 1
        path.stroke()

        drawRTFText("AlmohamadAli", in: CGRect(x: margin, y: lineY + 6, width: 160, height: 14), font: smallFont, color: textMuted)
        drawRTFText("صفحة \(pageNumber)", in: CGRect(x: pageWidth - margin - 100, y: lineY + 6, width: 100, height: 14), font: smallFont, color: textMuted)
    }

    private static func formattedNow() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar_KW")
        formatter.dateFormat = "yyyy/MM/dd - h:mm a"
        return formatter.string(from: Date())
    }

    private static func fillRoundedRect(_ rect: CGRect, color: UIColor) {
        color.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: DS.Radius.md).fill()
    }

    private static func strokeRoundedRect(_ rect: CGRect, color: UIColor, lineWidth: CGFloat) {
        color.setStroke()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: DS.Radius.md)
        path.lineWidth = lineWidth
        path.stroke()
    }

    private static func drawRTFText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.baseWritingDirection = .rightToLeft
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    /// رسم نص بمحاذاة يسار/يمين/وسط مع دعم RTL والتباعد الحرفي
    private static func drawRTLText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .right,
        kern: CGFloat = 0
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.baseWritingDirection = .rightToLeft
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        if kern > 0 { attrs[.kern] = kern }
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private static func standardizedPhone(_ phone: String?) -> String {
        let digits = (phone ?? "").filter(\.isNumber)
        guard !digits.isEmpty else { return "—" }
        if digits.hasPrefix("965"), digits.count >= 11 {
            return "+\(digits)"
        }
        if digits.count == 8 {
            return "+965\(digits)"
        }
        return "+\(digits)"
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
