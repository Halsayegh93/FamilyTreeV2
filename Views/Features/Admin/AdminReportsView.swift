import SwiftUI
import UIKit

struct AdminReportsView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var minAge: Int = 0
    @State private var maxAge: Int = 100
    @State private var searchText: String = ""
    @State private var selectedMemberIds: Set<UUID> = []

    @State private var isGenerating = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

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

        return byText.filter { member in
            guard let age = ageForMember(member) else { return false }
            return age >= minAge && age <= maxAge
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

        ScrollView {
            VStack(spacing: DS.Spacing.lg) {

                // MARK: - Age Filter Section
                DSSectionHeader(title: "تصفية حسب العمر", icon: "slider.horizontal.3")

                DSCard {
                    VStack(spacing: DS.Spacing.md) {
                        Stepper("العمر الأدنى: \(minAge)", value: $minAge, in: 0...120)
                            .font(DS.Font.callout)
                            .tint(DS.Color.primary)
                            .onChange(of: minAge) { _, newValue in
                                if newValue > maxAge { maxAge = newValue }
                            }

                        DSDivider()

                        Stepper("العمر الأعلى: \(maxAge)", value: $maxAge, in: 0...120)
                            .font(DS.Font.callout)
                            .tint(DS.Color.primary)
                            .onChange(of: maxAge) { _, newValue in
                                if newValue < minAge { minAge = newValue }
                            }
                    }
                    .padding(DS.Spacing.lg)
                }
                .padding(.horizontal, DS.Spacing.lg)

                // MARK: - Search & Select Section
                DSSectionHeader(title: "بحث واختيار الأعضاء", icon: "person.2.fill")

                DSCard {
                    VStack(spacing: DS.Spacing.md) {
                        // Search field
                        HStack(spacing: DS.Spacing.md) {
                            ZStack {
                                Circle()
                                    .fill(DS.Color.gradientPrimary)
                                    .frame(width: 32, height: 32)
                                Image(systemName: "magnifyingglass")
                                    .font(DS.Font.scaled(12, weight: .semibold))
                                    .foregroundColor(.white)
                            }

                            TextField("ابحث بالاسم...", text: $searchText)
                                .font(DS.Font.body)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(DS.Spacing.md)
                        .background(DS.Color.surfaceElevated)
                        .cornerRadius(DS.Radius.md)

                        if filteredMembers.isEmpty {
                            Text("لا يوجد أعضاء ضمن العمر المحدد.")
                                .foregroundColor(DS.Color.textSecondary)
                                .font(DS.Font.callout)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, DS.Spacing.md)
                        } else {
                            // Select all / Deselect buttons
                            HStack(spacing: DS.Spacing.md) {
                                Button {
                                    selectedMemberIds = Set(filteredMembers.map(\.id))
                                } label: {
                                    HStack(spacing: DS.Spacing.xs) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(DS.Font.scaled(12))
                                        Text("تحديد الكل (\(filteredMembers.count))")
                                            .font(DS.Font.caption1)
                                    }
                                    .foregroundColor(DS.Color.primary)
                                    .padding(.horizontal, DS.Spacing.md)
                                    .padding(.vertical, DS.Spacing.sm)
                                    .background(DS.Color.primary.opacity(0.1))
                                    .cornerRadius(DS.Radius.full)
                                }

                                Button {
                                    selectedMemberIds.removeAll()
                                } label: {
                                    HStack(spacing: DS.Spacing.xs) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(DS.Font.scaled(12))
                                        Text("إلغاء التحديد")
                                            .font(DS.Font.caption1)
                                    }
                                    .foregroundColor(DS.Color.error)
                                    .padding(.horizontal, DS.Spacing.md)
                                    .padding(.vertical, DS.Spacing.sm)
                                    .background(DS.Color.error.opacity(0.1))
                                    .cornerRadius(DS.Radius.full)
                                }

                                Spacer()
                            }

                            DSDivider()

                            // Members list
                            ForEach(filteredMembers) { member in
                                Button {
                                    if selectedMemberIds.contains(member.id) {
                                        selectedMemberIds.remove(member.id)
                                    } else {
                                        selectedMemberIds.insert(member.id)
                                    }
                                } label: {
                                    HStack(spacing: DS.Spacing.md) {
                                        Image(systemName: selectedMemberIds.contains(member.id) ? "checkmark.circle.fill" : "circle")
                                            .font(DS.Font.scaled(20))
                                            .foregroundStyle(
                                                selectedMemberIds.contains(member.id)
                                                    ? AnyShapeStyle(DS.Color.gradientPrimary)
                                                    : AnyShapeStyle(DS.Color.textTertiary)
                                            )

                                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                            Text(member.fullName)
                                                .font(DS.Font.calloutBold)
                                                .foregroundColor(DS.Color.textPrimary)
                                            Text("العمر: \(ageForMember(member) ?? 0) • الهاتف: \(phoneDisplay(member.phoneNumber))")
                                                .font(DS.Font.caption1)
                                                .foregroundColor(DS.Color.textSecondary)
                                        }

                                        Spacer()
                                    }
                                    .padding(.vertical, DS.Spacing.sm)
                                }
                            }
                        }
                    }
                    .padding(DS.Spacing.lg)
                }
                .padding(.horizontal, DS.Spacing.lg)

                // MARK: - Generate PDF Section
                DSSectionHeader(title: "إنشاء التقرير", icon: "doc.richtext.fill")

                VStack(spacing: DS.Spacing.sm) {
                    DSPrimaryButton(
                        "إنشاء تقرير PDF",
                        icon: "doc.richtext.fill",
                        isLoading: isGenerating
                    ) {
                        Task { await generatePDF() }
                    }
                    .disabled(isGenerating || filteredMembers.isEmpty)
                    .opacity((isGenerating || filteredMembers.isEmpty) ? 0.6 : 1.0)

                    Text("إذا لم تحدد أعضاء، سيتم إنشاء التقرير لكل الأعضاء ضمن العمر المحدد.")
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Spacing.lg)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxxl)
            }
            .padding(.top, DS.Spacing.md)
        }
        } // ZStack
        .navigationTitle("تقارير PDF")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear {
            Task { await authVM.fetchAllMembers() }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(items: shareItems)
        }
        .alert("تعذر إنشاء التقرير", isPresented: $showErrorAlert) {
            Button("موافق", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func generatePDF() async {
        await MainActor.run { isGenerating = true }

        let sourceMembers = selectedMembersInFilter.isEmpty ? filteredMembers : selectedMembersInFilter
        guard !sourceMembers.isEmpty else {
            await MainActor.run {
                isGenerating = false
                errorMessage = "لا يوجد أعضاء لإنشاء التقرير."
                showErrorAlert = true
            }
            return
        }

        do {
            let reportData = try MembersPDFBuilder.makePhoneAndAgeReport(
                members: sourceMembers,
                minAge: minAge,
                maxAge: maxAge,
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
                errorMessage = error.localizedDescription
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
        return phone
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
