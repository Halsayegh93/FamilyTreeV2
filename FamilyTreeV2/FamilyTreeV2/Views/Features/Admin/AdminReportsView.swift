import SwiftUI
import UIKit

struct AdminReportsView: View {
    @EnvironmentObject var memberVM: MemberViewModel

    enum ReportType: String, CaseIterable {
        case phone, age, family
        var label: String {
            switch self {
            case .phone: return L10n.t("الهاتف", "Phone")
            case .age: return L10n.t("العمر", "Age")
            case .family: return L10n.t("العائلة", "Family")
            }
        }
        var icon: String {
            switch self {
            case .phone: return "phone.fill"
            case .age: return "calendar"
            case .family: return "person.3.fill"
            }
        }
    }

    enum StatusFilter: CaseIterable {
        case all, alive, deceased
        var label: String {
            switch self {
            case .all: return L10n.t("الكل", "All")
            case .alive: return L10n.t("أحياء", "Alive")
            case .deceased: return L10n.t("متوفين", "Deceased")
            }
        }
    }

    // MARK: - State
    @State private var selectedReport: ReportType = .phone
    @State private var searchText = ""
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var isGenerating = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var displayLimit = 20

    // فلاتر
    @State private var showFilters = false
    @State private var minAgeText = ""
    @State private var maxAgeText = ""
    @State private var statusFilter: StatusFilter = .all
    @State private var selectedFatherId: UUID? = nil // nil = الكل

    // MARK: - Computed
    private var activeMembers: [FamilyMember] {
        memberVM.allMembers.filter { $0.role != .pending }
    }

    /// الآباء المتوفرين للفلتر
    private var availableFathers: [FamilyMember] {
        let fatherIds = Set(activeMembers.compactMap(\.fatherId))
        return activeMembers
            .filter { fatherIds.contains($0.id) }
            .sorted { $0.fullName < $1.fullName }
    }

    private var filteredMembers: [FamilyMember] {
        var members = activeMembers

        // 1. بحث نصي
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            members = members.filter {
                $0.fullName.localizedCaseInsensitiveContains(trimmed) ||
                $0.firstName.localizedCaseInsensitiveContains(trimmed) ||
                ($0.phoneNumber ?? "").contains(trimmed)
            }
        }

        // 2. فلتر الحالة (أحياء/متوفين)
        switch statusFilter {
        case .all: break
        case .alive: members = members.filter { $0.isDeceased != true }
        case .deceased: members = members.filter { $0.isDeceased == true }
        }

        // 3. فلتر العائلة
        if let fatherId = selectedFatherId {
            members = members.filter { $0.fatherId == fatherId || $0.id == fatherId }
        }

        // 4. فلتر نطاق العمر
        let minAgeVal = Int(minAgeText) ?? 0
        let maxAgeVal = Int(maxAgeText) ?? 0
        if minAgeVal > 0 || maxAgeVal > 0 {
            members = members.filter { m in
                guard let age = ageForMember(m) else { return false }
                if minAgeVal > 0 && maxAgeVal > 0 { return age >= minAgeVal && age <= maxAgeVal }
                if minAgeVal > 0 { return age >= minAgeVal }
                return age <= maxAgeVal
            }
        }

        // 5. فلتر حسب نوع التقرير
        switch selectedReport {
        case .phone:
            members = members.filter {
                let phone = ($0.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return !phone.isEmpty
            }
            members.sort { $0.fullName < $1.fullName }
        case .age:
            members = members.filter {
                let birth = ($0.birthDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return !birth.isEmpty
            }
            members.sort { (ageForMember($0) ?? 0) > (ageForMember($1) ?? 0) }
        case .family:
            members.sort { $0.fullName < $1.fullName }
        }

        return members
    }

    private var activeFilterCount: Int {
        var count = 0
        if statusFilter != .all { count += 1 }
        if selectedFatherId != nil { count += 1 }
        if (Int(minAgeText) ?? 0) > 0 || (Int(maxAgeText) ?? 0) > 0 { count += 1 }
        return count
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // نوع التقرير
                Picker("", selection: $selectedReport) {
                    ForEach(ReportType.allCases, id: \.self) { type in
                        Label(type.label, systemImage: type.icon).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
                .onChange(of: selectedReport) {
                    selectedMemberIds.removeAll()
                    displayLimit = 20
                }

                // بحث + فلاتر
                VStack(spacing: DS.Spacing.sm) {
                    // بحث
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(DS.Color.textTertiary)
                            .font(DS.Font.scaled(14, weight: .medium))
                        TextField(L10n.t("بحث بالاسم أو الرقم...", "Search by name or phone..."), text: $searchText)
                            .font(DS.Font.callout)
                            .onChange(of: searchText) { displayLimit = 20 }
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                        }
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.md)

                    // زر الفلاتر
                    DisclosureGroup(isExpanded: $showFilters) {
                        filtersSection
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .font(DS.Font.scaled(14))
                            Text(L10n.t("فلاتر", "Filters"))
                                .font(DS.Font.calloutBold)
                            if activeFilterCount > 0 {
                                Text("\(activeFilterCount)")
                                    .font(DS.Font.scaled(10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(DS.Color.primary)
                                    .clipShape(Capsule())
                            }
                        }
                        .foregroundColor(DS.Color.primary)
                    }
                    .tint(DS.Color.primary)

                    // أزرار التحديد + العدد
                    HStack(spacing: DS.Spacing.sm) {
                        Button {
                            selectedMemberIds = Set(filteredMembers.map(\.id))
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill").font(DS.Font.scaled(11))
                                Text(L10n.t("الكل", "All")).font(DS.Font.scaled(12, weight: .bold))
                            }
                            .foregroundColor(DS.Color.primary)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(DS.Color.primary.opacity(0.1))
                            .clipShape(Capsule())
                        }

                        Button {
                            selectedMemberIds.removeAll()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark.circle.fill").font(DS.Font.scaled(11))
                                Text(L10n.t("إلغاء", "Clear")).font(DS.Font.scaled(12, weight: .bold))
                            }
                            .foregroundColor(DS.Color.error)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(DS.Color.error.opacity(0.1))
                            .clipShape(Capsule())
                        }

                        if activeFilterCount > 0 {
                            Button {
                                resetFilters()
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.counterclockwise").font(DS.Font.scaled(11))
                                    Text(L10n.t("إعادة", "Reset")).font(DS.Font.scaled(12, weight: .bold))
                                }
                                .foregroundColor(DS.Color.warning)
                                .padding(.horizontal, DS.Spacing.md)
                                .padding(.vertical, DS.Spacing.xs)
                                .background(DS.Color.warning.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }

                        Spacer()

                        Text(L10n.t(
                            "\(selectedMemberIds.isEmpty ? filteredMembers.count : selectedMemberIds.count) عضو",
                            "\(selectedMemberIds.isEmpty ? filteredMembers.count : selectedMemberIds.count) members"
                        ))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)

                // القائمة
                if filteredMembers.isEmpty {
                    Spacer()
                    VStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 36))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا يوجد أعضاء", "No members found"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                        if activeFilterCount > 0 {
                            Button {
                                resetFilters()
                            } label: {
                                Text(L10n.t("إعادة ضبط الفلاتر", "Reset Filters"))
                                    .font(DS.Font.caption1)
                                    .foregroundColor(DS.Color.primary)
                            }
                        }
                    }
                    Spacer()
                } else {
                    List {
                        let visible = Array(filteredMembers.prefix(displayLimit))
                        ForEach(visible) { member in
                            Button { toggleSelection(member.id) } label: {
                                memberRow(member: member)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 4, leading: DS.Spacing.lg, bottom: 4, trailing: DS.Spacing.lg))
                        }

                        if displayLimit < filteredMembers.count {
                            Button { displayLimit += 20 } label: {
                                HStack {
                                    Spacer()
                                    Text(L10n.t(
                                        "عرض المزيد (\(filteredMembers.count - displayLimit) متبقي)",
                                        "Show more (\(filteredMembers.count - displayLimit) remaining)"
                                    ))
                                    .font(DS.Font.caption1)
                                    .foregroundColor(DS.Color.primary)
                                    Spacer()
                                }
                                .padding(.vertical, DS.Spacing.sm)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: DS.Spacing.lg, bottom: 0, trailing: DS.Spacing.lg))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }

                // زر PDF
                VStack(spacing: DS.Spacing.xs) {
                    DSPrimaryButton(
                        L10n.t("إنشاء تقرير PDF", "Generate PDF"),
                        icon: "doc.richtext.fill",
                        isLoading: isGenerating
                    ) {
                        Task { await generatePDF() }
                    }
                    .disabled(isGenerating || filteredMembers.isEmpty)

                    if !selectedMemberIds.isEmpty {
                        Text(L10n.t(
                            "سيشمل التقرير \(selectedMemberIds.count) عضو محدد",
                            "Report will include \(selectedMemberIds.count) selected members"
                        ))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
                .background(DS.Color.background)
            }
        }
        .navigationTitle(L10n.t("تقارير PDF", "PDF Reports"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await memberVM.fetchAllMembers() }
        .sheet(isPresented: $showShareSheet) { ActivityView(items: shareItems) }
        .alert(L10n.t("خطأ", "Error"), isPresented: $showErrorAlert) {
            Button(L10n.t("موافق", "OK"), role: .cancel) {}
        } message: { Text(errorMessage) }
    }

    // MARK: - Filters Section
    private var filtersSection: some View {
        VStack(spacing: DS.Spacing.md) {
            // نطاق العمر — حقول إدخال
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack {
                    Image(systemName: "calendar").font(DS.Font.scaled(12))
                    Text(L10n.t("نطاق العمر", "Age Range"))
                        .font(DS.Font.calloutBold)
                }

                HStack(spacing: DS.Spacing.md) {
                    VStack(spacing: 2) {
                        Text(L10n.t("من", "From"))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textTertiary)
                        TextField("0", text: $minAgeText)
                            .keyboardType(.numberPad)
                            .font(DS.Font.headline)
                            .multilineTextAlignment(.center)
                            .frame(width: 70, height: 44)
                            .background(DS.Color.surface)
                            .cornerRadius(DS.Radius.md)
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).stroke(DS.Color.primary.opacity(0.3), lineWidth: 1))
                            .onChange(of: minAgeText) { displayLimit = 20 }
                    }

                    Text("—")
                        .font(DS.Font.title3)
                        .foregroundColor(DS.Color.textTertiary)

                    VStack(spacing: 2) {
                        Text(L10n.t("إلى", "To"))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textTertiary)
                        TextField("100", text: $maxAgeText)
                            .keyboardType(.numberPad)
                            .font(DS.Font.headline)
                            .multilineTextAlignment(.center)
                            .frame(width: 70, height: 44)
                            .background(DS.Color.surface)
                            .cornerRadius(DS.Radius.md)
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).stroke(DS.Color.primary.opacity(0.3), lineWidth: 1))
                            .onChange(of: maxAgeText) { displayLimit = 20 }
                    }

                    Spacer()

                    // أزرار سريعة
                    VStack(spacing: DS.Spacing.xs) {
                        quickAgeButton("18-30") { minAgeText = "18"; maxAgeText = "30" }
                        quickAgeButton("30-50") { minAgeText = "30"; maxAgeText = "50" }
                        quickAgeButton("50+") { minAgeText = "50"; maxAgeText = "" }
                    }
                }
            }

            DSDivider()

            // فلتر العائلة
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack {
                    Image(systemName: "person.3.fill").font(DS.Font.scaled(12))
                    Text(L10n.t("العائلة", "Family"))
                        .font(DS.Font.calloutBold)
                }

                Picker("", selection: $selectedFatherId) {
                    Text(L10n.t("جميع العائلات", "All Families")).tag(UUID?.none)
                    ForEach(availableFathers) { father in
                        Text(father.fullName).tag(UUID?.some(father.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(DS.Color.primary)
                .onChange(of: selectedFatherId) { displayLimit = 20 }
            }

            DSDivider()

            // فلتر الحالة
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack {
                    Image(systemName: "heart.fill").font(DS.Font.scaled(12))
                    Text(L10n.t("الحالة", "Status"))
                        .font(DS.Font.calloutBold)
                }

                Picker("", selection: $statusFilter) {
                    ForEach(StatusFilter.allCases, id: \.self) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: statusFilter) { displayLimit = 20 }
            }
        }
        .padding(.vertical, DS.Spacing.sm)
    }

    // MARK: - Member Row
    private func memberRow(member: FamilyMember) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: selectedMemberIds.contains(member.id) ? "checkmark.circle.fill" : "circle")
                .font(DS.Font.scaled(20))
                .foregroundStyle(
                    selectedMemberIds.contains(member.id)
                        ? AnyShapeStyle(DS.Color.gradientPrimary)
                        : AnyShapeStyle(DS.Color.textTertiary)
                )

            VStack(alignment: .leading, spacing: 2) {
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

                // التفاصيل حسب نوع التقرير — مع عرض متقاطع
                HStack(spacing: DS.Spacing.sm) {
                    if let age = ageForMember(member) {
                        HStack(spacing: 2) {
                            Image(systemName: "calendar").font(DS.Font.scaled(10))
                            Text(L10n.t("\(age) سنة", "\(age) yrs"))
                        }
                    }

                    if let phone = member.phoneNumber, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "phone.fill").font(DS.Font.scaled(10))
                            Text(KuwaitPhone.display(phone))
                        }
                    }

                    if selectedReport == .family,
                       let fatherId = member.fatherId,
                       let father = memberVM.allMembers.first(where: { $0.id == fatherId }) {
                        HStack(spacing: 2) {
                            Image(systemName: "person.fill").font(DS.Font.scaled(10))
                            Text(L10n.t("ابن \(father.firstName)", "Son of \(father.firstName)"))
                        }
                    }
                }
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
            }

            Spacer()
        }
    }

    // MARK: - Helpers
    private func toggleSelection(_ id: UUID) {
        if selectedMemberIds.contains(id) {
            selectedMemberIds.remove(id)
        } else {
            selectedMemberIds.insert(id)
        }
    }

    private func resetFilters() {
        minAgeText = ""
        maxAgeText = ""
        statusFilter = .all
        selectedFatherId = nil
        displayLimit = 20
    }

    private func quickAgeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            displayLimit = 20
        } label: {
            Text(title)
                .font(DS.Font.scaled(10, weight: .bold))
                .foregroundColor(DS.Color.primary)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, 3)
                .background(DS.Color.primary.opacity(0.1))
                .clipShape(Capsule())
        }
    }

    private func generatePDF() async {
        await MainActor.run { isGenerating = true }

        let sourceMembers = selectedMemberIds.isEmpty ? filteredMembers : filteredMembers.filter { selectedMemberIds.contains($0.id) }
        guard !sourceMembers.isEmpty else {
            await MainActor.run {
                isGenerating = false
                errorMessage = L10n.t("لا يوجد أعضاء لإنشاء التقرير.", "No members to generate report.")
                showErrorAlert = true
            }
            return
        }

        // وصف الفلاتر المطبقة للتقرير
        var filterDesc: [String] = []
        let minAgeVal = Int(minAgeText) ?? 0
        let maxAgeVal = Int(maxAgeText) ?? 0
        if minAgeVal > 0 && maxAgeVal > 0 {
            filterDesc.append(L10n.t("العمر: \(minAgeVal)–\(maxAgeVal)", "Age: \(minAgeVal)–\(maxAgeVal)"))
        } else if minAgeVal > 0 {
            filterDesc.append(L10n.t("العمر: \(minAgeVal)+", "Age: \(minAgeVal)+"))
        } else if maxAgeVal > 0 {
            filterDesc.append(L10n.t("العمر: حتى \(maxAgeVal)", "Age: up to \(maxAgeVal)"))
        }
        if let fId = selectedFatherId, let father = memberVM.allMembers.first(where: { $0.id == fId }) {
            filterDesc.append(L10n.t("العائلة: \(father.firstName)", "Family: \(father.firstName)"))
        }
        if statusFilter == .alive { filterDesc.append(L10n.t("أحياء فقط", "Alive only")) }
        if statusFilter == .deceased { filterDesc.append(L10n.t("متوفين فقط", "Deceased only")) }

        do {
            let reportData: Data
            let reportName: String

            switch selectedReport {
            case .phone:
                reportData = try MembersPDFBuilder.makePhoneReport(members: sourceMembers, filters: filterDesc, ageResolver: { ageForMember($0) })
                reportName = "phone_report"
            case .age:
                reportData = try MembersPDFBuilder.makeAgeReport(members: sourceMembers, filters: filterDesc, ageResolver: { ageForMember($0) })
                reportName = "age_report"
            case .family:
                reportData = try MembersPDFBuilder.makeFamilyReport(members: sourceMembers, allMembers: memberVM.allMembers, filters: filterDesc, ageResolver: { ageForMember($0) })
                reportName = "family_report"
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let fileName = "\(reportName)_\(formatter.string(from: Date())).pdf"
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
                errorMessage = L10n.t("فشل إنشاء التقرير.", "Failed to generate report.")
                showErrorAlert = true
            }
        }
    }

    private func ageForMember(_ member: FamilyMember) -> Int? {
        guard let birthDate = parsedBirthDate(member.birthDate) else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }

    private func parsedBirthDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let f1 = DateFormatter()
        f1.locale = Locale(identifier: "en_US_POSIX")
        f1.dateFormat = "yyyy-MM-dd"
        if let date = f1.date(from: raw) { return date }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }
        return nil
    }
}

// MARK: - PDF Builder

private enum MembersPDFBuilder {
    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 36
    private static let rowHeight: CGFloat = 24
    private static let titleFont = UIFont.boldSystemFont(ofSize: 18)
    private static let headerFont = UIFont.boldSystemFont(ofSize: 12)
    private static let bodyFont = UIFont.systemFont(ofSize: 11)
    private static let smallFont = UIFont.systemFont(ofSize: 9)
    private static let filterFont = UIFont.italicSystemFont(ofSize: 10)

    // MARK: - تقرير الهاتف (مع العمر)
    static func makePhoneReport(members: [FamilyMember], filters: [String], ageResolver: (FamilyMember) -> Int?) throws -> Data {
        let renderer = makeRenderer()
        let dateStr = formattedNow()

        return renderer.pdfData { context in
            var y = margin
            var num = 1

            func header() {
                drawTitle(L10n.t("تقرير أرقام الهاتف", "Phone Numbers Report"), date: dateStr, count: members.count, filters: filters, y: &y)
                drawRow(cols: ["#", L10n.t("الاسم", "Name"), L10n.t("العمر", "Age"), L10n.t("الهاتف", "Phone")],
                        widths: [28, 230, 50, 210], y: y, font: headerFont, bg: true)
                y += rowHeight + 4
            }

            context.beginPage(); header()

            for m in members {
                if y + rowHeight > pageHeight - margin { context.beginPage(); y = margin; header() }
                let age = ageResolver(m).map { "\($0)" } ?? "—"
                drawRow(cols: ["\(num)", m.fullName, age, KuwaitPhone.display(m.phoneNumber)],
                        widths: [28, 230, 50, 210], y: y, font: bodyFont, bg: false)
                drawLine(y: y + rowHeight)
                y += rowHeight; num += 1
            }
        }
    }

    // MARK: - تقرير العمر (مع الهاتف)
    static func makeAgeReport(members: [FamilyMember], filters: [String], ageResolver: (FamilyMember) -> Int?) throws -> Data {
        let renderer = makeRenderer()
        let dateStr = formattedNow()

        return renderer.pdfData { context in
            var y = margin
            var num = 1

            func header() {
                drawTitle(L10n.t("تقرير الأعمار", "Ages Report"), date: dateStr, count: members.count, filters: filters, y: &y)
                drawRow(cols: ["#", L10n.t("الاسم", "Name"), L10n.t("العمر", "Age"), L10n.t("الميلاد", "Birth"), L10n.t("الهاتف", "Phone")],
                        widths: [28, 180, 40, 90, 170], y: y, font: headerFont, bg: true)
                y += rowHeight + 4
            }

            context.beginPage(); header()

            for m in members {
                if y + rowHeight > pageHeight - margin { context.beginPage(); y = margin; header() }
                let age = ageResolver(m).map { "\($0)" } ?? "—"
                let birth = String((m.birthDate ?? "—").prefix(10))
                let phone = KuwaitPhone.display(m.phoneNumber)
                drawRow(cols: ["\(num)", m.fullName, age, birth, phone],
                        widths: [28, 180, 40, 90, 170], y: y, font: bodyFont, bg: false)
                drawLine(y: y + rowHeight)
                y += rowHeight; num += 1
            }
        }
    }

    // MARK: - تقرير العائلة (مع العمر والهاتف)
    static func makeFamilyReport(members: [FamilyMember], allMembers: [FamilyMember], filters: [String], ageResolver: (FamilyMember) -> Int?) throws -> Data {
        let renderer = makeRenderer()
        let dateStr = formattedNow()

        let byFatherId = Dictionary(grouping: members) { $0.fatherId }
        let fatherIds = Set(members.compactMap(\.fatherId))

        struct FamilyGroup {
            let fatherName: String
            let children: [FamilyMember]
        }

        var groups: [FamilyGroup] = []
        for fatherId in fatherIds.sorted(by: { $0.uuidString < $1.uuidString }) {
            let father = allMembers.first { $0.id == fatherId }
            let children = (byFatherId[fatherId] ?? []).sorted { $0.fullName < $1.fullName }
            groups.append(FamilyGroup(fatherName: father?.fullName ?? L10n.t("أب غير معروف", "Unknown Father"), children: children))
        }
        let orphans = (byFatherId[nil] ?? []).filter { !fatherIds.contains($0.id) }
        if !orphans.isEmpty {
            groups.append(FamilyGroup(fatherName: L10n.t("بدون أب محدد", "No Father Assigned"), children: orphans.sorted { $0.fullName < $1.fullName }))
        }

        return renderer.pdfData { context in
            var y = margin
            let groupFont = UIFont.boldSystemFont(ofSize: 13)

            func pageHeader() {
                drawTitle(L10n.t("تقرير العائلات", "Family Report"), date: dateStr, count: members.count, filters: filters, y: &y)
            }

            context.beginPage(); pageHeader()

            for group in groups {
                if y + rowHeight * 2 > pageHeight - margin { context.beginPage(); y = margin; pageHeader() }

                UIColor.systemBlue.withAlphaComponent(0.1).setFill()
                UIBezierPath(rect: CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: rowHeight + 2)).fill()

                let title = group.fatherName + " (\(group.children.count))"
                title.draw(
                    in: CGRect(x: margin + 8, y: y + 4, width: pageWidth - margin * 2 - 16, height: rowHeight),
                    withAttributes: [.font: groupFont, .foregroundColor: UIColor.systemBlue]
                )
                y += rowHeight + 6

                for child in group.children {
                    if y + rowHeight > pageHeight - margin { context.beginPage(); y = margin; pageHeader() }

                    let text = "   • " + child.fullName
                    text.draw(in: CGRect(x: margin + 16, y: y + 4, width: 220, height: rowHeight), withAttributes: [.font: bodyFont])

                    let age = ageResolver(child).map { "\($0)" } ?? "—"
                    age.draw(in: CGRect(x: margin + 240, y: y + 4, width: 40, height: rowHeight), withAttributes: [.font: smallFont, .foregroundColor: UIColor.darkGray])

                    let phone = KuwaitPhone.display(child.phoneNumber)
                    if phone != "—" {
                        phone.draw(in: CGRect(x: margin + 290, y: y + 4, width: 180, height: rowHeight), withAttributes: [.font: smallFont, .foregroundColor: UIColor.darkGray])
                    }

                    drawLine(y: y + rowHeight)
                    y += rowHeight
                }
                y += 8
            }
        }
    }

    // MARK: - Helpers
    private static func makeRenderer() -> UIGraphicsPDFRenderer {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "Members Report", kCGPDFContextAuthor as String: "FamilyTreeV2"]
        return UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), format: format)
    }

    private static func formattedNow() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f.string(from: Date())
    }

    private static func drawTitle(_ title: String, date: String, count: Int, filters: [String], y: inout CGFloat) {
        title.draw(in: CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: 26),
                   withAttributes: [.font: titleFont, .foregroundColor: UIColor.black])
        y += 26

        let sub = L10n.t("التاريخ: \(date)    العدد: \(count)", "Generated: \(date)    Count: \(count)")
        sub.draw(in: CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: 20),
                 withAttributes: [.font: bodyFont, .foregroundColor: UIColor.darkGray])
        y += 20

        if !filters.isEmpty {
            let filterText = L10n.t("الفلاتر: ", "Filters: ") + filters.joined(separator: " | ")
            filterText.draw(in: CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: 16),
                            withAttributes: [.font: filterFont, .foregroundColor: UIColor.systemBlue])
            y += 18
        }

        y += 8
    }

    private static func drawRow(cols: [String], widths: [CGFloat], y: CGFloat, font: UIFont, bg: Bool) {
        if bg {
            UIColor.systemGray5.setFill()
            UIBezierPath(rect: CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: rowHeight)).fill()
        }
        var x = margin + 6
        for (i, col) in cols.enumerated() {
            col.draw(in: CGRect(x: x, y: y + 5, width: widths[i], height: rowHeight),
                     withAttributes: [.font: font, .foregroundColor: i == 0 && !bg ? UIColor.darkGray : UIColor.black])
            x += widths[i] + 4
        }
    }

    private static func drawLine(y: CGFloat) {
        UIColor.systemGray5.setStroke()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: margin, y: y))
        line.addLine(to: CGPoint(x: pageWidth - margin, y: y))
        line.lineWidth = 0.5
        line.stroke()
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
