import SwiftUI
import UIKit

struct AdminReportsView: View {
    @EnvironmentObject private var memberVM: MemberViewModel

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

        var label: String {
            switch self {
            case .all: return L10n.t("الكل", "All")
            case .alive: return L10n.t("أحياء", "Alive")
            case .deceased: return L10n.t("متوفين", "Deceased")
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
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var branchRootId: UUID? = nil
    @State private var branchPickerOpen = false

    private let reportColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

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
            VStack(spacing: DS.Spacing.lg) {
                overviewSection
                resultsSection
                exportSection
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xxxxl)
        }
        .background(DS.Color.background.ignoresSafeArea())
        .navigationTitle("مركز التقارير")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
        .task { await memberVM.fetchAllMembers() }
        .sheet(isPresented: $showShareSheet, onDismiss: { cleanupShareState() }) {
            ActivityView(items: shareItems) {
                cleanupShareState()
            }
        }
        .sheet(isPresented: $branchPickerOpen) {
            BranchPickerSheet(
                allMembers: memberVM.allMembers,
                onSelect: { id in
                    branchRootId = id
                    branchPickerOpen = false
                    displayLimit = 20
                }
            )
        }
        .alert("خطأ", isPresented: $showErrorAlert) {
            Button("موافق", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var overviewSection: some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
                    .fill(DS.Color.surface)

                RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
                    .stroke(selectedReport.tint.opacity(0.2), lineWidth: 1.2)

                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    HStack(alignment: .top) {
                        Text("تقارير الإدارة")
                            .font(DS.Font.title3)
                            .fontWeight(.black)
                            .foregroundColor(DS.Color.textPrimary)

                        Spacer()

                        Image(systemName: selectedReport.icon)
                            .font(DS.Font.scaled(22, weight: .bold))
                            .foregroundColor(selectedReport.tint)
                            .frame(width: 48, height: 48)
                            .background(selectedReport.tint.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    }

                    HStack {
                        Text("اختيار التقرير")
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Spacer()
                    }

                    LazyVGrid(columns: reportColumns, spacing: DS.Spacing.sm) {
                        ForEach(ReportType.allCases, id: \.self) { report in
                            reportQuickChip(report)
                        }
                    }

                    filtersSection
                }
                .padding(DS.Spacing.lg)
            }
        }
    }

    private var filtersSection: some View {
        VStack(spacing: DS.Spacing.md) {
            // Branch filter
            branchFilterRow

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(DS.Font.scaled(12))
                    Text("تصفية")
                        .font(DS.Font.calloutBold)
                }

                if selectedReport == .age || selectedReport == .phone {
                    HStack(spacing: DS.Spacing.md) {
                        Spacer()

                        TextField(L10n.t("من", "Min"), text: $minAgeText)
                            .keyboardType(.numberPad)
                            .font(DS.Font.headline)
                            .multilineTextAlignment(.center)
                            .frame(width: 78, height: 44)
                            .background(DS.Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                    .stroke(ageRangeInvalid ? DS.Color.error.opacity(0.5) : selectedReport.tint.opacity(0.3), lineWidth: 1)
                            )
                            .onChange(of: minAgeText) { _ in displayLimit = 20 }

                        VStack(spacing: 2) {
                            Text(L10n.t("إلى", "to"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                            if ageRangeInvalid {
                                Text(L10n.t("خطأ!", "Invalid!"))
                                    .font(DS.Font.caption2)
                                    .foregroundColor(DS.Color.error)
                            }
                        }

                        TextField(L10n.t("إلى", "Max"), text: $maxAgeText)
                            .keyboardType(.numberPad)
                            .font(DS.Font.headline)
                            .multilineTextAlignment(.center)
                            .frame(width: 78, height: 44)
                            .background(DS.Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                    .stroke(ageRangeInvalid ? DS.Color.error.opacity(0.5) : selectedReport.tint.opacity(0.3), lineWidth: 1)
                            )
                            .onChange(of: maxAgeText) { _ in displayLimit = 20 }

                        Spacer()
                    }
                }

                Picker("", selection: $statusFilter) {
                    ForEach(StatusFilter.allCases, id: \.self) { status in
                        Text(status.label).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: statusFilter) { _ in displayLimit = 20 }
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(DS.Font.scaled(12))
                    Text("بحث")
                        .font(DS.Font.calloutBold)
                }

                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DS.Color.textTertiary)

                    TextField("بحث بالاسم أو الرقم...", text: $searchText)
                        .font(DS.Font.callout)
                        .onChange(of: searchText) { _ in displayLimit = 20 }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            displayLimit = 20
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(DS.Color.textTertiary)
                        }
                    }
                }
                .padding(DS.Spacing.md)
                .background(DS.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                )
            }
        }
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
                    .padding(.horizontal, DS.Spacing.lg)

                    ForEach(Array(visibleMembers.enumerated()), id: \.element.id) { _, member in
                        Button {
                            toggleSelection(member.id)
                        } label: {
                            memberRow(member: member)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, DS.Spacing.lg)
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
                        Image(systemName: "chevron.left")
                            .font(DS.Font.scaled(10, weight: .bold))
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
                            .font(DS.Font.scaled(10))
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

            Image(systemName: "chevron.left")
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
                .font(DS.Font.scaled(10))
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
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
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

        do {
            let reportData: Data

            switch selectedReport {
            case .family:
                reportData = try MembersPDFBuilder.makeFamilyReport(members: sourceMembers, filters: filters)
            case .age:
                reportData = try MembersPDFBuilder.makeAgeReport(members: sourceMembers, filters: filters, ageResolver: { ageForMember($0) })
            case .phone:
                reportData = try MembersPDFBuilder.makePhoneReport(members: sourceMembers, filters: filters, ageResolver: { ageForMember($0) })
            case .missingPhone:
                reportData = try MembersPDFBuilder.makeMissingPhoneReport(members: sourceMembers, filters: filters)
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let fileName = "\(selectedReport.exportBaseName)_\(formatter.string(from: Date())).pdf"
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
                errorMessage = "فشل إنشاء التقرير."
                showErrorAlert = true
            }
        }
    }
}

private enum MembersPDFBuilder {
    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 28
    private static let rowHeight: CGFloat = 28
    private static let pageBodyTop: CGFloat = 120
    private static let border = UIColor(red: 0.86, green: 0.88, blue: 0.90, alpha: 1.0)
    private static let softGray = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0)
    private static let textPrimary = UIColor(red: 0.11, green: 0.15, blue: 0.20, alpha: 1.0)
    private static let textMuted = UIColor(red: 0.39, green: 0.45, blue: 0.52, alpha: 1.0)

    private static let titleFont = UIFont.boldSystemFont(ofSize: 20)
    private static let bodyFont = UIFont.systemFont(ofSize: 10.5, weight: .regular)
    private static let bodyBoldFont = UIFont.systemFont(ofSize: 10.5, weight: .semibold)
    private static let smallFont = UIFont.systemFont(ofSize: 9, weight: .medium)

    private struct ReportColumn {
        let title: String
        let ratio: CGFloat
        let value: (FamilyMember, Int) -> String
    }

    private struct PDFTheme {
        let accent: UIColor
        let title: String
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
    }

    private static func makeMembersTableReport(
        members: [FamilyMember],
        filters: [String],
        theme: PDFTheme,
        columns: [ReportColumn]
    ) throws -> Data {
        let renderer = makeRenderer(title: theme.title)
        let context = ReportContext(title: theme.title, count: members.count, filters: filters, accent: theme.accent)

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
        drawHeaderCard(context: context)
        drawFooter(pageNumber: pageNumber, drawNow: false)
        return pageBodyTop
    }

    private static func drawHeaderCard(context: ReportContext) {
        let cardRect = CGRect(x: margin, y: 18, width: pageWidth - margin * 2, height: 84)
        fillRoundedRect(cardRect, color: UIColor.white)
        strokeRoundedRect(cardRect, color: border, lineWidth: 1)

        if let logo = UIImage(named: "AppIconImage") {
            let logoRect = CGRect(x: cardRect.maxX - 54, y: cardRect.minY + 16, width: 28, height: 28)
            let currentContext = UIGraphicsGetCurrentContext()
            currentContext?.saveGState()
            UIBezierPath(roundedRect: logoRect.insetBy(dx: -3, dy: -3), cornerRadius: 10).addClip()
            logo.draw(in: logoRect)
            currentContext?.restoreGState()
        }

        drawRTFText(context.title, in: CGRect(x: cardRect.minX + 18, y: cardRect.minY + 14, width: cardRect.width - 76, height: 24), font: titleFont, color: textPrimary)
        let filterText = context.filters.isEmpty ? "بدون تصفية" : context.filters.joined(separator: " • ")
        let meta = "عدد السجلات: \(context.count)    |    التاريخ: \(formattedNow())    |    التصفية: \(filterText)"
        drawRTFText(meta, in: CGRect(x: cardRect.minX + 18, y: cardRect.minY + 46, width: cardRect.width - 36, height: 18), font: bodyFont, color: textMuted)
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
        UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
    }

    private static func strokeRoundedRect(_ rect: CGRect, color: UIColor, lineWidth: CGFloat) {
        color.setStroke()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
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
