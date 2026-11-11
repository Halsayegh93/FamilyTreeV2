import SwiftUI
import PDFKit
import UIKit

/// نطاق جاهز من صفحة «العائلة» (الشريحة والبحث الحاليان) — يُحدَّد أعضاؤه في التقرير
struct AdminReportScope {
    let ids: Set<UUID>
    let title: String
}

struct AdminReportsView: View {
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var authVM: AuthViewModel

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
            case .phone: return DS.Color.primary
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
    }

    /// الحقول الديناميكية المتاحة للتقرير
    enum ReportField: String, CaseIterable, Identifiable {
        case fullName, firstName, phone, age, birthDate, deathDate, gender, married, role, status

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
    @State private var highlightedReport: ReportType = .family
    @State private var searchText = ""
    @State private var minAgeText = ""
    @State private var maxAgeText = ""
    @State private var statusFilter: StatusFilter = .all
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var displayLimit = 20
    @State private var isGenerating = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    /// معاينة التقرير قبل مشاركته (طلب المالك ٢٠٢٦-١١-٠٩)
    @State private var previewURL: URL? = nil
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var branchRootId: UUID? = nil
    /// «شجرة العائلة | شجرة النساء» فوق الصفحة — نفس مفتاح صفحة «العائلة» (طلب المالك ٢٠٢٦-١١-٠٩)
    @State private var treeScope: AdminFamilyScope = .family
    @State private var womenRows: [FamilyMember] = WomenStore.cache
    @State private var branchPickerOpen = false
    @State private var customTitle: String = "تقرير عائلة المحمدعلي"
    @State private var selectedFields: Set<ReportField> = [.fullName, .phone, .age]

    init(scope: AdminReportScope? = nil) {
        if let scope {
            _selectedMemberIds = State(initialValue: scope.ids)
            if !scope.title.isEmpty { _customTitle = State(initialValue: "تقرير عائلة المحمدعلي — \(scope.title)") }
        }
    }

    private let reportColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var ageRangeInvalid: Bool {
        let minVal = Int(minAgeText) ?? 0
        let maxVal = Int(maxAgeText) ?? 0
        return minVal > 0 && maxVal > 0 && minVal > maxVal
    }

    /// أعضاء الشجرة المختارة في المفتاح
    private var sourceMembers: [FamilyMember] {
        // شجرة النساء: الإناث فقط — مثل لوحة النساء في صفحة «العائلة» (الآباء فيها عُقد ربط)
        treeScope == .women ? womenRows.filter(\.isFemale) : memberVM.allMembers
    }

    private var activeMembers: [FamilyMember] {
        sourceMembers.filter {
            $0.role != .pending &&
            !$0.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var childrenByFather: [UUID: [FamilyMember]] {
        var map: [UUID: [FamilyMember]] = [:]
        for m in sourceMembers {
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
        return sourceMembers.first { $0.id == id }
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

        if selectedReport == .age || selectedReport == .phone {
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

    private var visibleMembers: [FamilyMember] {
        Array(filteredMembers.prefix(displayLimit))
    }

    private var activeFilterCount: Int {
        var count = 0
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if statusFilter != .all { count += 1 }
        if (selectedReport == .age || selectedReport == .phone) &&
            ((Int(minAgeText) ?? 0) > 0 || (Int(maxAgeText) ?? 0) > 0) {
            count += 1
        }
        if branchRootId != nil { count += 1 }
        return count
    }

    private var selectedCount: Int {
        selectedMemberIds.isEmpty ? filteredMembers.count : filteredMembers.filter { selectedMemberIds.contains($0.id) }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
          VStack(spacing: DS.Spacing.md) {
            // «شجرة النساء» للمالك والمدير فقط — مثل صفحة «العائلة»
            if authVM.isAdmin {
                DSSegmentedSwitch(options: AdminFamilyScope.options, selection: Binding(
                    get: { treeScope },
                    set: { v in
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) { switchTree(to: v) }
                    }), size: .regular)
            }
            // الوضع الأفقي: الإعدادات/النتائج/التصدير على عمودين
            AdaptiveCardStack(spacing: DS.Spacing.md, landscapeMinimum: 340) {
                settingsCard
                resultsSection
                exportSection
            }
          }
            .dsPageMargin()
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xxxxl)
            // ⚠️ مهم: نعلّق sheet الفرع على VStack الداخلي عشان لا يتزاحم
            // مع sheet المشاركة المعلّق على الـScrollView. SwiftUI لا يدعم
            // sheet متعدد على نفس الـView — يتم تجاهل الـsheet الثاني.
            // المربّع الطويل الموحّد (`dsTallBox`) بدل ورقة النظام
            .dsTallBox(isPresented: $branchPickerOpen) {
                BranchPickerSheet(
                    allMembers: sourceMembers,
                    onSelect: { id in
                        branchRootId = id
                        branchPickerOpen = false
                        displayLimit = 20
                    }
                )
            }
        }
        .background(DS.Color.background.ignoresSafeArea())
        .navigationTitle("مركز التقارير")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
        .task {
            if memberVM.allMembers.isEmpty {
                await memberVM.fetchAllMembers()
            }
        }
        .fullScreenCover(isPresented: Binding(get: { previewURL != nil }, set: { if !$0 { previewURL = nil } })) {
            if let url = previewURL {
                AdminReportPreview(url: url, title: customTitle.isEmpty ? "تقرير عائلة المحمدعلي" : customTitle)
                    .dsSectionPage(.admin)
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: { cleanupShareState() }) {
            ActivityView(items: shareItems) {
                cleanupShareState()
            }
        }
        .dsAlert(L10n.t("خطأ", "Error"), isPresented: $showErrorAlert) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    /// تبديل الشجرة: يمسح التحديد والفرع، والعنوان الافتراضي يتبع الشجرة
    private func switchTree(to v: AdminFamilyScope) {
        guard v != treeScope else { return }
        let familyTitle = "تقرير عائلة المحمدعلي", womenTitle = "تقرير شجرة النساء"
        if customTitle == familyTitle || customTitle == womenTitle || customTitle.isEmpty {
            customTitle = v == .women ? womenTitle : familyTitle
        }
        treeScope = v
        if v == .women {
            selectedFields.subtract([.phone, .role, .status, .gender])
            if selectedFields.isEmpty { selectedFields = [.fullName] }
            if statusFilter == .withPhone || statusFilter == .withoutPhone { statusFilter = .all }
        }
        selectedMemberIds.removeAll()
        branchRootId = nil
        displayLimit = 20
        if v == .women && womenRows.isEmpty {
            Task {
                if let rows = try? await WomenStore.fetch() { womenRows = rows }
            }
        }
    }

    // MARK: - كرت الإعدادات (موحّد)

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // رأس
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "slider.horizontal.3")
                    .font(DS.Font.scaled(14, weight: .bold))
                    .foregroundColor(DS.Color.primary)
                Text("إعدادات التقرير")
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.primary)
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.sm)

            Divider().opacity(0.5)

            // (1) معلومات التقرير: عنوان + فرع
            innerSection(icon: "doc.text", title: "معلومات التقرير") {
                VStack(spacing: DS.Spacing.sm) {
                    // عنوان
                    TextField("عنوان التقرير", text: $customTitle)
                        .dsFont(.fieldValue)
                        .modifier(ReportFieldBox())

                    // فرع — لشجرة العائلة فقط
                    if treeScope == .family { branchFilterRow }
                }
            }

            Divider().opacity(0.4).padding(.horizontal, DS.Spacing.md)

            // (2) تصفية الأعضاء + بحث
            innerSection(icon: "person.crop.circle.badge.checkmark", title: "تصفية") {
                VStack(spacing: DS.Spacing.sm) {
                    // فلتر الحالة
                    DSFilterChips(options: statusOptions, selection: $statusFilter)
                        .onChange(of: statusFilter) { _ in displayLimit = 20 }

                    // نطاق العمر (إن لزم): «العمر» ثم خانتان متساويتان
                    if needsAgeFilter {
                        HStack(spacing: DS.Spacing.sm) {
                            Text("العمر")
                                .dsFont(.label)
                                .foregroundColor(DS.Color.textSecondary)
                            ageField("من", text: $minAgeText)
                            Text("–")
                                .dsFont(.label)
                                .foregroundColor(DS.Color.textTertiary)
                            ageField("إلى", text: $maxAgeText)
                        }
                        if ageRangeInvalid {
                            Text("«من» أكبر من «إلى»")
                                .dsFont(.caption)
                                .foregroundColor(DS.Color.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // البحث
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .dsGlyph(DS.Glyph.md)
                            .foregroundColor(DS.Color.textTertiary)
                        TextField(treeScope == .women ? "بحث بالاسم..." : "بحث بالاسم أو الرقم...", text: $searchText)
                            .dsFont(.fieldValue)
                            .onChange(of: searchText) { _ in displayLimit = 20 }
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                displayLimit = 20
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                            .accessibilityLabel(L10n.t("مسح البحث", "Clear search"))
                        }
                    }
                    .modifier(ReportFieldBox())
                }
            }

            Divider().opacity(0.4).padding(.horizontal, DS.Spacing.md)

            // (3) الحقول
            innerSection(
                icon: "list.bullet.rectangle",
                title: "الحقول",
                trailing: "\(selectedFields.filter(availableFields.contains).count) مختارة"
            ) {
                // عمودان متساويان (أزواج: الاسمان، الهاتف والعمر، الميلاد والوفاة، الجنس ومتزوج، الدور والحالة)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 2),
                          spacing: DS.Spacing.sm) {
                    ForEach(availableFields) { field in
                        fieldChip(field)
                    }
                }
            }
            .padding(.bottom, DS.Spacing.md)
        }
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(DS.Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    /// قسم فرعي داخل كرت الإعدادات
    @ViewBuilder
    private func innerSection<Content: View>(
        icon: String,
        title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(11, weight: .semibold))
                    .foregroundColor(DS.Color.textSecondary)
                Text(title)
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textSecondary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(DS.Font.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            content()
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
    }

    private func fieldChip(_ field: ReportField) -> some View {
        let active = selectedFields.contains(field)
        return Button {
            if active {
                // يبقى حقل واحد على الأقل
                if selectedFields.filter(availableFields.contains).count > 1 {
                    selectedFields.remove(field)
                }
            } else {
                selectedFields.insert(field)
            }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                if active {
                    Image(systemName: "checkmark")
                        .dsGlyph(DS.Glyph.xs)
                }
                Text(field.label)
                    .dsFont(.chip)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(active ? DS.Color.textOnPrimary : DS.Color.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 36)
            .padding(.horizontal, DS.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(active ? DS.Color.primaryFill : DS.Color.fieldFill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// خانة رقم العمر — بعرض متساوٍ
    private func ageField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .dsFont(.fieldValue)
            .frame(maxWidth: .infinity, minHeight: DSBox.fieldMinHeight)
            .dsRowBox()
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(ageRangeInvalid ? DS.Color.error.opacity(DS.Opacity.selectedStroke) : Color.clear,
                            lineWidth: DS.Border.width)
            )
            .onChange(of: text.wrappedValue) { _ in displayLimit = 20 }
    }

    /// الحقول المتاحة للشجرة المختارة — شجرة النساء بلا هاتف ولا دور ولا حالة حساب ولا جنس (كلهن إناث)
    private var availableFields: [ReportField] {
        treeScope == .women
            ? ReportField.allCases.filter { ![.phone, .role, .status, .gender].contains($0) }
            : ReportField.allCases
    }

    /// فلاتر الحالة — شجرة النساء بلا فلاتر الهاتف
    private var statusOptions: [DSFilterOption<StatusFilter>] {
        StatusFilter.allCases
            .filter { treeScope == .family || ($0 != .withPhone && $0 != .withoutPhone) }
            .map { DSFilterOption(id: $0, title: $0.label) }
    }

    // متى نظهر نطاق العمر
    private var needsAgeFilter: Bool {
        selectedReport == .age || selectedReport == .phone || selectedFields.contains(.age)
    }

    // MARK: - بطاقة قسم موحّدة (مستخدمة للنتائج/التصدير فقط)

    @ViewBuilder
    private func sectionCard<Content: View>(
        icon: String,
        title: String,
        color: Color,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(DS.Font.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.textSecondary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(DS.Color.surface))
                        .overlay(
                            Capsule().stroke(DS.Color.textTertiary.opacity(0.2), lineWidth: 0.8)
                        )
                }
            }
            content()
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
    }


    private var resultsSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: "نتائج التقرير",
                icon: selectedReport.icon,
                trailing: "\(filteredMembers.count) عضو",
                iconColor: selectedReport.tint
            )

            if filteredMembers.isEmpty {
                VStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "person.2.slash")
                        .font(DS.Font.scaled(34))
                        .foregroundColor(DS.Color.textTertiary)
                    Text("لا يوجد أعضاء")
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .padding(.vertical, DS.Spacing.xl)
            } else {
                VStack(spacing: DS.Spacing.sm) {
                    HStack(spacing: DS.Spacing.sm) {
                        miniActionButton(title: "تحديد الكل", icon: "checkmark.circle.fill", tint: selectedReport.tint) {
                            selectedMemberIds = Set(filteredMembers.map(\.id))
                        }

                        miniActionButton(title: "إلغاء التحديد", icon: "xmark.circle.fill", tint: .red) {
                            selectedMemberIds.removeAll()
                        }

                        if activeFilterCount > 0 {
                            miniActionButton(title: "إعادة ضبط", icon: "arrow.counterclockwise", tint: selectedReport.tint) {
                                resetFilters()
                            }
                        }

                        Spacer()
                    }
                    .dsPageMargin()

                    ForEach(Array(visibleMembers.enumerated()), id: \.element.id) { _, member in
                        Button {
                            toggleSelection(member.id)
                        } label: {
                            memberRow(member: member)
                        }
                        .buttonStyle(.plain)
                        .dsPageMargin()
                    }

                    if displayLimit < filteredMembers.count {
                        Button {
                            displayLimit += 20
                        } label: {
                            Text("عرض المزيد (\(filteredMembers.count - displayLimit) متبقي)")
                                .font(DS.Font.caption1)
                                .foregroundColor(selectedReport.tint)
                                .padding(.vertical, DS.Spacing.sm)
                        }
                    }
                }
                .padding(.bottom, DS.Spacing.md)
            }
        }
    }

    private var exportSection: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("التصدير")
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)

                Text("النطاق: \(selectedCount) عضو")
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)

                DSPrimaryButton(L10n.t("إنشاء تقرير PDF", "Generate PDF Report"), icon: "doc.richtext.fill", isLoading: isGenerating) {
                    Task { await generatePDF() }
                }
                .disabled(isGenerating || filteredMembers.isEmpty || ageRangeInvalid)
            }
        }
    }

    private var branchFilterRow: some View {
        Group {
            if let m = branchRootMember {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "tree.fill")
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(selectedReport.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("فرع: \(m.fullName)")
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(selectedReport.tint)
                            .lineLimit(1)
                        Text("\(descendantIds(of: m.id).count) عضو في الفرع")
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    Spacer()
                    Button { branchPickerOpen = true } label: {
                        Text("تغيير")
                            .font(DS.Font.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(selectedReport.tint)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(selectedReport.tint.opacity(0.12)))
                    }
                    Button {
                        branchRootId = nil
                        displayLimit = 20
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(DS.Color.error)
                    }
                    .accessibilityLabel(L10n.t("إلغاء تصفية الفرع", "Clear branch filter"))
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(selectedReport.tint.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(selectedReport.tint.opacity(0.2), lineWidth: 1)
                )
            } else {
                Button { branchPickerOpen = true } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "tree")
                            .font(DS.Font.scaled(12, weight: .semibold))
                        Text("حصر على فرع معيّن")
                            .font(DS.Font.caption1)
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(DS.Font.scaled(11, weight: .bold))
                            .opacity(0.5)
                    }
                    .foregroundColor(DS.Color.textSecondary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(DS.Color.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(DS.Color.textTertiary.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(DSScaleButtonStyle())
            }
        }
    }

    private func reportQuickChip(_ report: ReportType) -> some View {
        let selected = highlightedReport == report
        return Button {
            withAnimation(DS.Anim.snappy) {
                highlightedReport = report
                selectedReport = report
                selectedMemberIds.removeAll()
                displayLimit = 20
            }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: report.icon)
                    Text(report.label)
                    if selected {
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark.circle.fill")
                            .font(DS.Font.scaled(13, weight: .bold))
                    }
                }
                .font(DS.Font.scaled(12, weight: .bold))
                .frame(maxWidth: .infinity)
            }
            .foregroundColor(selected ? DS.Color.textOnPrimary : report.tint)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 4)
            .background(selected ? report.tint : report.tint.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(selected ? report.tint.opacity(0.95) : report.tint.opacity(0.35), lineWidth: selected ? 2 : 1.2)
            )
            .shadow(color: report.tint.opacity(selected ? 0.28 : 0.08), radius: selected ? 10 : 3, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func memberRow(member: FamilyMember) -> some View {
        let selected = selectedMemberIds.contains(member.id)
        let phone = normalizedPhone(for: member)

        return HStack(spacing: DS.Spacing.md) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(DS.Font.scaled(20))
                .foregroundStyle(
                    selected ? AnyShapeStyle(DS.Color.gradientPrimary) : AnyShapeStyle(DS.Color.textTertiary)
                )

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(member.fullName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)

                    if member.isDeceased == true {
                        Image(systemName: "leaf.fill")
                            .font(DS.Font.scaled(11))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }

                HStack(spacing: DS.Spacing.sm) {
                    if selectedReport == .age || selectedReport == .phone {
                        if let age = ageForMember(member), age > 0 {
                            detailBadge(icon: "calendar", text: "\(age) سنة")
                        }
                    }

                    if !phone.isEmpty {
                        detailBadge(icon: "phone.fill", text: KuwaitPhone.display(phone))
                    } else if selectedReport == .missingPhone {
                        detailBadge(icon: "exclamationmark.triangle.fill", text: "رقم ناقص", tint: DS.Color.warning)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.forward")
                .font(DS.Font.scaled(12, weight: .bold))
                .foregroundColor(selected ? selectedReport.tint : DS.Color.textTertiary)
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(selected ? selectedReport.tint.opacity(0.08) : DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(selected ? selectedReport.tint.opacity(0.35) : Color.gray.opacity(0.12), lineWidth: 1)
        )
    }

    private func detailBadge(icon: String, text: String, tint: Color = DS.Color.textSecondary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(DS.Font.scaled(11))
            Text(text)
                .font(DS.Font.caption2)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.08))
        .clipShape(Capsule())
    }

    private func miniActionButton(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(11))
                Text(title)
                    .font(DS.Font.scaled(11, weight: .bold))
            }
            .foregroundColor(tint)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
            .background(tint.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
            // عزل اتجاه الرقم (LTR) حتى لا تنقلب «+» داخل سطر عربي
            return phone.isEmpty ? "—" : "\u{2066}" + KuwaitPhone.display(phone) + "\u{2069}"
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
                errorMessage = "لا يوجد أعضاء لإنشاء التقرير."
                showErrorAlert = true
            }
            return
        }

        var filters: [String] = []
        let minAgeVal = Int(minAgeText) ?? 0
        let maxAgeVal = Int(maxAgeText) ?? 0
        if selectedReport == .age || selectedReport == .phone {
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
        let orderedFields = availableFields.filter { selectedFields.contains($0) }

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
                previewURL = fileURL
                isGenerating = false
            }
        } catch {
            await MainActor.run {
                isGenerating = false
                errorMessage = "فشل إنشاء التقرير."
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
    private static let border = UIColor(red: 0.89, green: 0.91, blue: 0.93, alpha: 1.0)
    private static let softGray = UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1.0)
    private static let headerGray = UIColor(red: 0.94, green: 0.96, blue: 0.97, alpha: 1.0)
    private static let textPrimary = UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)
    private static let textMuted = UIColor(red: 0.39, green: 0.45, blue: 0.52, alpha: 1.0)
    private static let textTertiary = UIColor(red: 0.58, green: 0.64, blue: 0.72, alpha: 1.0)

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
        var alignment: NSTextAlignment = .right
        let value: (FamilyMember, Int) -> String

        init(title: String, ratio: CGFloat, alignment: NSTextAlignment = .right,
             value: @escaping (FamilyMember, Int) -> String) {
            self.title = title
            self.ratio = ratio
            self.alignment = alignment
            self.value = value
        }
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

        // توزيع الأعمدة: الحقول القصيرة بعرضها الثابت وفي الوسط، والاسم يأخذ الباقي (طلب المالك ٢٠٢٦-١١-٠٩)
        var columns: [ReportColumn] = [
            ReportColumn(title: "م", ratio: 0.06, alignment: .center) { _, index in "\(index)" }
        ]
        let availableRatio: CGFloat = 0.94
        let nameFields = fields.filter { $0 == .fullName || $0 == .firstName }
        let shortTotal = fields.filter { !nameFields.contains($0) }.reduce(0.0) { $0 + $1.ratio }
        let shortScale: CGFloat = nameFields.isEmpty
            ? (shortTotal > 0 ? availableRatio / shortTotal : 1)
            : min(1, (availableRatio - 0.30 * CGFloat(nameFields.count)) / max(shortTotal, 0.01))
        let nameRatioTotal = nameFields.reduce(0.0) { $0 + $1.ratio }
        let nameRoom = availableRatio - shortTotal * shortScale
        for field in fields {
            let isName = nameFields.contains(field)
            let ratio = isName ? nameRoom * field.ratio / max(nameRatioTotal, 0.01) : field.ratio * shortScale
            columns.append(ReportColumn(title: field.label, ratio: ratio,
                                        alignment: isName ? .right : .center) { member, _ in
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

    static func makePhoneReport(members: [FamilyMember], filters: [String], ageResolver: @escaping (FamilyMember) -> Int?) throws -> Data {
        try makeMembersTableReport(
            members: members,
            filters: filters,
            theme: PDFTheme(
                accent: UIColor(red: 0.21, green: 0.46, blue: 0.78, alpha: 1),
                title: "تقرير الهواتف"
            ),
            columns: [
                ReportColumn(title: "م", ratio: 0.10) { _, index in "\(index)" },
                ReportColumn(title: "الاسم الكامل", ratio: 0.42) { member, _ in member.fullName },
                ReportColumn(title: "العمر", ratio: 0.12) { member, _ in ageResolver(member).map { "\($0) سنة" } ?? "—" },
                ReportColumn(title: "رقم الهاتف", ratio: 0.36) { member, _ in standardizedPhone(member.phoneNumber) }
            ]
        )
    }

    static func makeAgeReport(members: [FamilyMember], filters: [String], ageResolver: @escaping (FamilyMember) -> Int?) throws -> Data {
        try makeMembersTableReport(
            members: members,
            filters: filters,
            theme: PDFTheme(
                accent: UIColor(red: 0.18, green: 0.55, blue: 0.51, alpha: 1),
                title: "تقرير الأعمار"
            ),
            columns: [
                ReportColumn(title: "م", ratio: 0.08) { _, index in "\(index)" },
                ReportColumn(title: "الاسم الكامل", ratio: 0.56) { member, _ in member.fullName },
                ReportColumn(title: "العمر", ratio: 0.14) { member, _ in ageResolver(member).map { "\($0) سنة" } ?? "—" },
                ReportColumn(title: "الهاتف", ratio: 0.22) { member, _ in standardizedPhone(member.phoneNumber) }
            ]
        )
    }

    static func makeFamilyReport(members: [FamilyMember], filters: [String]) throws -> Data {
        try makeMembersTableReport(
            members: members,
            filters: filters,
            theme: PDFTheme(
                accent: UIColor(red: 0.33, green: 0.41, blue: 0.57, alpha: 1),
                title: "تقرير الأسماء"
            ),
            columns: [
                ReportColumn(title: "م", ratio: 0.10) { _, index in "\(index)" },
                ReportColumn(title: "الاسم الكامل", ratio: 0.90) { member, _ in member.fullName }
            ]
        )
    }

    static func makeMissingPhoneReport(members: [FamilyMember], filters: [String]) throws -> Data {
        try makeMembersTableReport(
            members: members,
            filters: filters,
            theme: PDFTheme(
                accent: UIColor(red: 0.63, green: 0.49, blue: 0.23, alpha: 1),
                title: "تقرير الأعضاء بدون هاتف"
            ),
            columns: [
                ReportColumn(title: "م", ratio: 0.10) { _, index in "\(index)" },
                ReportColumn(title: "الاسم الكامل", ratio: 0.90) { member, _ in member.fullName }
            ]
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

        // (0) شعار العائلة الجديد (الكحلي) — يمين أعلى الصفحة، والعنوان على يساره (طلب المالك ٢٠٢٦-١١-٠٩)
        var textWidth = contentWidth
        if let logo = UIImage(named: "FamilyLogoNavy", in: nil,
                              compatibleWith: UITraitCollection(userInterfaceStyle: .light)),
           logo.size.width > 0, logo.size.height > 0 {
            let h: CGFloat = 48
            let w = h * logo.size.width / logo.size.height
            logo.draw(in: CGRect(x: rightEdge - w, y: topY - 2, width: w, height: h))
            textWidth = contentWidth - w - 12
        }

        // (1) "ALMOHAMMADALI FAMILY" — يمين أعلى الصفحة بجانب الشعار (RTL = visual right)
        let brand = "ALMOHAMMADALI FAMILY"
        drawRTLText(
            brand,
            in: CGRect(x: leftEdge, y: topY, width: textWidth, height: 12),
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
        // يبقى العنوان بعيداً عن التاريخ ورقم التقرير على اليسار، ويصغر خطه لو طال
        let titleRoom = textWidth - 150
        var fittedTitleFont = titleFont
        let titleW = (context.title as NSString).size(withAttributes: [.font: titleFont]).width
        if titleW > titleRoom, titleW > 0 {
            fittedTitleFont = titleFont.withSize(max(14, titleFont.pointSize * titleRoom / titleW * 0.85))
        }
        drawRTLText(
            context.title,
            in: CGRect(x: leftEdge + 150, y: topY + 16 + (titleFont.pointSize - fittedTitleFont.pointSize) / 2,
                       width: titleRoom, height: 36),
            font: fittedTitleFont,
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
            drawRTFText(texts[index], in: rect, font: font, color: textColor, alignment: column.alignment)
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
        DateHelper.displayDateTime(Date())
    }

    private static func fillRoundedRect(_ rect: CGRect, color: UIColor) {
        color.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
    }

    private static func strokeRoundedRect(_ rect: CGRect, color: UIColor, lineWidth: CGFloat) {
        color.setStroke()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        path.lineWidth = lineWidth
        path.stroke()
    }

    private static func drawRTFText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor,
                                    alignment: NSTextAlignment = .right) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
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


/// خانة نص في إعدادات التقرير — تعبئة الحقول الموحّدة وارتفاع ٤٤
private struct ReportFieldBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            // صفّ الحقل الموحّد: نفس الارتفاع والحشوة والتعبئة
            .frame(minHeight: DSBox.fieldMinHeight)
            .dsRowBox()
    }
}


// MARK: - معاينة التقرير قبل المشاركة

/// الـPDF كما سيُرسل: صفحات تتمرّر عمودياً، ورأس فيه الإغلاق و«مشاركة» (حفظ في الملفات، واتساب، طباعة…)
struct AdminReportPreview: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var sharing = false

    private var pageCount: Int { PDFDocument(url: url)?.pageCount ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            DSSubPageHeader(title: L10n.t("معاينة التقرير", "Report preview"),
                            subtitle: pageCount > 0 ? L10n.t("\(title) · \(pageCount) صفحة", "\(title) · \(pageCount) pages") : title,
                            nav: .close, onBack: { dismiss() }) {
                DSHeaderButton(symbol: "square.and.arrow.up", label: L10n.t("مشاركة", "Share")) { sharing = true }
            }
            AdminReportPDFView(url: url)
                .background(DS.Color.cardBackgroundSoft)
            Button { sharing = true } label: {
                Label(L10n.t("مشاركة التقرير", "Share report"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.ds(size: .large))
            .dsPageMargin()
            .padding(.vertical, DS.Spacing.md)
            .background(DS.Color.background)
        }
        .background(DS.Color.background.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
        .sheet(isPresented: $sharing) {
            ActivityView(items: [url]) { sharing = false }
        }
    }
}

/// عارض PDF بسيط: الصفحات تحت بعض، تكبير بالقرص
private struct AdminReportPDFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = .clear
        v.document = PDFDocument(url: url)
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url { v.document = PDFDocument(url: url) }
    }
}
