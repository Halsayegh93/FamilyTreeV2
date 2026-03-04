import SwiftUI
import UIKit

struct AdminReportsView: View {
    @EnvironmentObject var authVM: AuthViewModel

    // Age filter
    @State private var ageFilterMode: AgeFilterMode = .all
    @State private var minAge: Int = 0
    @State private var maxAge: Int = 100

    // Search & selection
    @State private var searchText: String = ""
    @State private var selectedMemberIds: Set<UUID> = []

    // PDF
    @State private var isGenerating = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    enum AgeFilterMode: String, CaseIterable {
        case all
        case children     // 0-17
        case youth        // 18-30
        case adults       // 31-50
        case seniors      // 51+
        case custom

        var label: (ar: String, en: String) {
            switch self {
            case .all:      return ("الكل", "All")
            case .children: return ("أطفال (٠-١٧)", "Children (0-17)")
            case .youth:    return ("شباب (١٨-٣٠)", "Youth (18-30)")
            case .adults:   return ("بالغين (٣١-٥٠)", "Adults (31-50)")
            case .seniors:  return ("كبار (٥١+)", "Seniors (51+)")
            case .custom:   return ("مخصص", "Custom")
            }
        }

        var range: (min: Int, max: Int)? {
            switch self {
            case .all:      return nil
            case .children: return (0, 17)
            case .youth:    return (18, 30)
            case .adults:   return (31, 50)
            case .seniors:  return (51, 120)
            case .custom:   return nil
            }
        }
    }

    private var activeMembers: [FamilyMember] {
        authVM.allMembers.filter { $0.role != .pending }
    }

    private var filteredMembers: [FamilyMember] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let byText: [FamilyMember]
        if trimmed.isEmpty {
            byText = activeMembers
        } else {
            byText = activeMembers.filter {
                $0.fullName.localizedCaseInsensitiveContains(trimmed) ||
                $0.firstName.localizedCaseInsensitiveContains(trimmed)
            }
        }

        // If "All" mode, return everyone (including those without birthdate)
        if ageFilterMode == .all {
            return byText.sorted { $0.fullName < $1.fullName }
        }

        let effectiveMin: Int
        let effectiveMax: Int
        if ageFilterMode == .custom {
            effectiveMin = minAge
            effectiveMax = maxAge
        } else if let range = ageFilterMode.range {
            effectiveMin = range.min
            effectiveMax = range.max
        } else {
            return byText.sorted { $0.fullName < $1.fullName }
        }

        return byText.filter { member in
            guard let age = ageForMember(member) else { return false }
            return age >= effectiveMin && age <= effectiveMax
        }
        .sorted { $0.fullName < $1.fullName }
    }

    private var selectedMembersInFilter: [FamilyMember] {
        filteredMembers.filter { selectedMemberIds.contains($0.id) }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) {

                    // MARK: - Stats Summary
                    statsSection
                        .padding(.top, DS.Spacing.md)

                    // MARK: - Age Filter
                    ageFilterSection

                    // MARK: - Members
                    membersSection

                    // MARK: - Generate PDF
                    generateReportSection
                }
                .padding(.bottom, DS.Spacing.xxxl)
            }
        }
        .navigationTitle(L10n.t("التقارير", "Reports"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await authVM.fetchAllMembers() }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(items: shareItems)
        }
        .alert(L10n.t("تعذر إنشاء التقرير", "Failed to generate report"), isPresented: $showErrorAlert) {
            Button(L10n.t("موافق", "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Stats Section
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("إحصائيات", "Statistics"),
                    icon: "chart.bar.fill",
                    iconColor: DS.Color.primary
                )

                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                    statCell(
                        icon: "person.2.fill",
                        color: DS.Color.primary,
                        title: L10n.t("إجمالي الأعضاء", "Total Members"),
                        value: "\(activeMembers.count)"
                    )
                    statCell(
                        icon: "line.3.horizontal.decrease.circle.fill",
                        color: DS.Color.info,
                        title: L10n.t("نتائج التصفية", "Filtered"),
                        value: "\(filteredMembers.count)"
                    )
                    statCell(
                        icon: "checkmark.circle.fill",
                        color: DS.Color.success,
                        title: L10n.t("محدد", "Selected"),
                        value: "\(selectedMemberIds.count)"
                    )
                    statCell(
                        icon: "calendar",
                        color: DS.Color.warning,
                        title: L10n.t("الفئة العمرية", "Age Group"),
                        value: L10n.t(ageFilterMode.label.ar, ageFilterMode.label.en)
                    )
                }
                .padding(DS.Spacing.md)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func statCell(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Font.scaled(16, weight: .bold))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)

                Text(value)
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.sm)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Age Filter Section
    private var ageFilterSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("تصفية حسب العمر", "Filter by Age"),
                    icon: "slider.horizontal.3",
                    iconColor: DS.Color.warning
                )

                // Quick filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(AgeFilterMode.allCases, id: \.self) { mode in
                            Button {
                                withAnimation(DS.Anim.snappy) { ageFilterMode = mode }
                                if let range = mode.range {
                                    minAge = range.min
                                    maxAge = range.max
                                }
                            } label: {
                                Text(L10n.t(mode.label.ar, mode.label.en))
                                    .font(DS.Font.caption1)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, DS.Spacing.md)
                                    .padding(.vertical, DS.Spacing.sm)
                                    .foregroundColor(ageFilterMode == mode ? .white : DS.Color.primary)
                                    .background(ageFilterMode == mode ? DS.Color.gradientPrimary : LinearGradient(colors: [DS.Color.primary.opacity(0.1)], startPoint: .leading, endPoint: .trailing))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                }

                // Custom range steppers
                if ageFilterMode == .custom {
                    DSDivider()
                    VStack(spacing: DS.Spacing.md) {
                        Stepper(L10n.t("العمر الأدنى: \(minAge)", "Min Age: \(minAge)"), value: $minAge, in: 0...120)
                            .font(DS.Font.callout)
                            .tint(DS.Color.primary)
                            .onChange(of: minAge) { _, newValue in
                                if newValue > maxAge { maxAge = newValue }
                            }

                        DSDivider()

                        Stepper(L10n.t("العمر الأعلى: \(maxAge)", "Max Age: \(maxAge)"), value: $maxAge, in: 0...120)
                            .font(DS.Font.callout)
                            .tint(DS.Color.primary)
                            .onChange(of: maxAge) { _, newValue in
                                if newValue < minAge { minAge = newValue }
                            }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.md)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Members Section
    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("الأعضاء", "Members"),
                    icon: "person.2.fill",
                    trailing: "\(filteredMembers.count)",
                    iconColor: DS.Color.success
                )

                // Search
                HStack(spacing: DS.Spacing.md) {
                    DSIcon("magnifyingglass", color: DS.Color.primary)

                    TextField(L10n.t("ابحث بالاسم...", "Search by name..."), text: $searchText)
                        .font(DS.Font.body)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)

                DSDivider()

                // Select/Deselect buttons
                HStack(spacing: DS.Spacing.sm) {
                    Button {
                        selectedMemberIds = Set(filteredMembers.map(\.id))
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(DS.Font.scaled(11))
                            Text(L10n.t("تحديد الكل", "Select All"))
                                .font(DS.Font.caption2)
                                .fontWeight(.bold)
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
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "xmark.circle.fill")
                                .font(DS.Font.scaled(11))
                            Text(L10n.t("إلغاء التحديد", "Deselect"))
                                .font(DS.Font.caption2)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(DS.Color.error)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(DS.Color.error.opacity(0.1))
                        .clipShape(Capsule())
                    }

                    Spacer()
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)

                DSDivider()

                // Members list
                if filteredMembers.isEmpty {
                    VStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "person.2.slash")
                            .font(DS.Font.scaled(32))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا يوجد أعضاء", "No members found"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.xl)
                } else {
                    membersListView
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Generate Report Section
    private var generateReportSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("إنشاء التقرير", "Generate Report"),
                    icon: "doc.richtext.fill",
                    iconColor: DS.Color.info
                )

                VStack(spacing: DS.Spacing.sm) {
                    DSPrimaryButton(
                        L10n.t("إنشاء تقرير PDF", "Generate PDF Report"),
                        icon: "doc.richtext.fill",
                        isLoading: isGenerating
                    ) {
                        Task { await generatePDF() }
                    }
                    .disabled(isGenerating || filteredMembers.isEmpty)
                    .opacity((isGenerating || filteredMembers.isEmpty) ? 0.6 : 1.0)

                    Text(L10n.t(
                        "إذا لم تحدد أعضاء، سيتم إنشاء التقرير لكل الأعضاء المعروضين.",
                        "If none selected, report includes all displayed members."
                    ))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.lg)
                }
                .padding(DS.Spacing.lg)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Members List
    private var membersListView: some View {
        LazyVStack(spacing: 0) {
            ForEach(filteredMembers) { member in
                Button {
                    toggleSelection(member.id)
                } label: {
                    memberRow(member: member)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

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
                Text(member.fullName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)

                HStack(spacing: DS.Spacing.sm) {
                    if let age = ageForMember(member) {
                        HStack(spacing: 2) {
                            Image(systemName: "calendar")
                                .font(DS.Font.scaled(10))
                            Text(L10n.t("\(age)", "\(age)"))
                        }
                    }

                    if let phone = member.phoneNumber, !phone.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "phone.fill")
                                .font(DS.Font.scaled(10))
                            Text(KuwaitPhone.display(phone))
                        }
                    }
                }
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }

    // MARK: - Helpers

    private func toggleSelection(_ id: UUID) {
        if selectedMemberIds.contains(id) {
            selectedMemberIds.remove(id)
        } else {
            selectedMemberIds.insert(id)
        }
    }

    private func generatePDF() async {
        await MainActor.run { isGenerating = true }

        let sourceMembers = selectedMembersInFilter.isEmpty ? filteredMembers : selectedMembersInFilter
        guard !sourceMembers.isEmpty else {
            await MainActor.run {
                isGenerating = false
                errorMessage = L10n.t("لا يوجد أعضاء لإنشاء التقرير.", "No members to generate report.")
                showErrorAlert = true
            }
            return
        }

        let effectiveMin = ageFilterMode == .custom ? minAge : (ageFilterMode.range?.min ?? 0)
        let effectiveMax = ageFilterMode == .custom ? maxAge : (ageFilterMode.range?.max ?? 120)

        do {
            let reportData = try MembersPDFBuilder.makePhoneAndAgeReport(
                members: sourceMembers,
                minAge: effectiveMin,
                maxAge: effectiveMax,
                generatedAt: Date(),
                ageResolver: { ageForMember($0) }
            )

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let fileName = "members_report_\(formatter.string(from: Date())).pdf"
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
                errorMessage = L10n.t("فشل إنشاء التقرير. حاول مرة أخرى.", "Failed to generate report. Please try again.")
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

    private func phoneDisplay(_ phone: String?) -> String {
        guard let phone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "—"
        }
        return KuwaitPhone.display(phone)
    }
}

private enum MembersPDFBuilder {
    static func makePhoneAndAgeReport(
        members: [FamilyMember],
        minAge: Int,
        maxAge: Int,
        generatedAt: Date,
        ageResolver: (FamilyMember) -> Int?
    ) throws -> Data {
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 36
        let rowHeight: CGFloat = 24
        let titleFont = UIFont.boldSystemFont(ofSize: 18)
        let headerFont = UIFont.boldSystemFont(ofSize: 12)
        let bodyFont = UIFont.systemFont(ofSize: 11)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Members Report",
            kCGPDFContextAuthor as String: "FamilyTreeV2"
        ]

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            format: format
        )

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        let rows: [(name: String, age: String, phone: String)] = members.map { member in
            let ageText = ageResolver(member).map(String.init) ?? "—"
            let phoneText = (member.phoneNumber?.isEmpty == false) ? (member.phoneNumber ?? "—") : "—"
            return (member.fullName, ageText, phoneText)
        }

        return renderer.pdfData { context in
            var currentY = margin
            var rowNumber = 1

            func drawHeader() {
                let title = "Family Members Report (Phones + Age)"
                title.draw(
                    in: CGRect(x: margin, y: currentY, width: pageWidth - margin * 2, height: 26),
                    withAttributes: [
                        .font: titleFont,
                        .foregroundColor: UIColor.black
                    ]
                )
                currentY += 26

                let subtitle = "Age Filter: \(minAge)-\(maxAge)    Generated: \(dateFormatter.string(from: generatedAt))    Count: \(rows.count)"
                subtitle.draw(
                    in: CGRect(x: margin, y: currentY, width: pageWidth - margin * 2, height: 20),
                    withAttributes: [
                        .font: bodyFont,
                        .foregroundColor: UIColor.darkGray
                    ]
                )
                currentY += 26

                UIColor(white: 0.92, alpha: 1).setFill()
                UIBezierPath(rect: CGRect(x: margin, y: currentY, width: pageWidth - margin * 2, height: rowHeight)).fill()

                let numberRect = CGRect(x: margin + 6, y: currentY + 5, width: 28, height: rowHeight)
                let nameRect = CGRect(x: margin + 38, y: currentY + 5, width: 250, height: rowHeight)
                let ageRect = CGRect(x: margin + 292, y: currentY + 5, width: 70, height: rowHeight)
                let phoneRect = CGRect(x: margin + 366, y: currentY + 5, width: 190, height: rowHeight)

                "#".draw(in: numberRect, withAttributes: [.font: headerFont])
                "Full Name".draw(in: nameRect, withAttributes: [.font: headerFont])
                "Age".draw(in: ageRect, withAttributes: [.font: headerFont])
                "Phone".draw(in: phoneRect, withAttributes: [.font: headerFont])

                currentY += rowHeight + 4
            }

            context.beginPage()
            drawHeader()

            for row in rows {
                if currentY + rowHeight > pageHeight - margin {
                    context.beginPage()
                    currentY = margin
                    drawHeader()
                }

                let numberRect = CGRect(x: margin + 6, y: currentY + 5, width: 28, height: rowHeight)
                let nameRect = CGRect(x: margin + 38, y: currentY + 5, width: 250, height: rowHeight)
                let ageRect = CGRect(x: margin + 292, y: currentY + 5, width: 70, height: rowHeight)
                let phoneRect = CGRect(x: margin + 366, y: currentY + 5, width: 190, height: rowHeight)

                String(rowNumber).draw(in: numberRect, withAttributes: [.font: bodyFont, .foregroundColor: UIColor.darkGray])
                row.name.draw(in: nameRect, withAttributes: [.font: bodyFont])
                row.age.draw(in: ageRect, withAttributes: [.font: bodyFont])
                row.phone.draw(in: phoneRect, withAttributes: [.font: bodyFont])

                UIColor(white: 0.92, alpha: 1).setStroke()
                let line = UIBezierPath()
                line.move(to: CGPoint(x: margin, y: currentY + rowHeight))
                line.addLine(to: CGPoint(x: pageWidth - margin, y: currentY + rowHeight))
                line.lineWidth = 0.5
                line.stroke()

                currentY += rowHeight
                rowNumber += 1
            }
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
