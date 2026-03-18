import SwiftUI

struct AdminPendingRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @State private var selectedMemberForLinking: FamilyMember?
    @State private var matchedIdsForSelected: [UUID] = []
    /// نتائج مطابقة الأسماء لكل عضو (يتم تفعيلها بالضغط على الزر)
    @State private var nameMatchResults: [UUID: [(member: FamilyMember, matchCount: Int, matchedParts: [String])]] = [:]
    @State private var loadingMatchFor: UUID? = nil
    /// Merge confirmation state
    @State private var mergeTarget: (pendingMember: FamilyMember, treeMember: FamilyMember)? = nil
    @State private var showMergeConfirm = false
    @State private var showMergeSuccess = false
    @State private var mergeSuccessMessage = ""
    @State private var expandedMatches: Set<UUID> = []

    // تصفية الأعضاء الذين حالتهم "Pending"
    var pendingMembers: [FamilyMember] {
        memberVM.allMembers.filter { $0.role == .pending }
    }

    // MARK: - مطابقة الاسم المحلية
    /// تطبيع النص العربي: إزالة التشكيل + توحيد الألف والهمزة
    private func normalizeArabic(_ text: String) -> String {
        var s = text
        // إزالة التشكيل (الفتحة، الكسرة، الضمة، السكون، الشدة، التنوين)
        let diacritics: [Character] = [
            "\u{064B}", "\u{064C}", "\u{064D}", "\u{064E}", "\u{064F}",
            "\u{0650}", "\u{0651}", "\u{0652}", "\u{0670}"
        ]
        s.removeAll { diacritics.contains($0) }
        // توحيد الألف: أ إ آ → ا
        s = s.replacingOccurrences(of: "أ", with: "ا")
            .replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "آ", with: "ا")
        // توحيد: ة → ه
        s = s.replacingOccurrences(of: "ة", with: "ه")
        return s
    }

    /// تقسيم الاسم مع التعامل مع "عبد" المركبة + إزالة "ال"
    private func splitName(_ name: String) -> [String] {
        let raw = name
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var parts: [String] = []
        var i = 0
        while i < raw.count {
            let normalized = normalizeArabic(raw[i])
            // دمج "عبد" + الكلمة التالية (عبد الله → عبدالله)
            if normalized == "عبد" && i + 1 < raw.count {
                parts.append(normalizeArabic(raw[i] + raw[i + 1]))
                i += 2
            } else {
                // إزالة "ال" التعريف
                var clean = normalized
                if clean.hasPrefix("ال") && clean.count > 2 {
                    clean = String(clean.dropFirst(2))
                }
                parts.append(clean)
                i += 1
            }
        }
        return parts
    }

    /// مقارنة جزئين من الاسم (تطابق كامل أو يحتوي أحدهما الآخر)
    private func partsMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        // أحدهما يحتوي الآخر (عبدالله vs عبدالله، محمدعلي vs محمد)
        if a.count >= 3 && b.count >= 3 {
            if a.contains(b) || b.contains(a) { return true }
        }
        return false
    }

    /// يقارن أجزاء اسم العضو الجديد مع أعضاء الشجرة الموجودين
    /// يرجع التطابقات مع عدد الأجزاء المتطابقة (2 أو أكثر)
    private func findNameMatches(for member: FamilyMember) -> [(member: FamilyMember, matchCount: Int, matchedParts: [String])] {
        let newParts = splitName(member.fullName)
        guard newParts.count >= 2 else { return [] }

        let existingMembers = memberVM.allMembers.filter { $0.role != .pending && $0.id != member.id }

        var matches: [(member: FamilyMember, matchCount: Int, matchedParts: [String])] = []

        for existing in existingMembers {
            let existingParts = splitName(existing.fullName)

            var matchedParts: [String] = []
            var usedIndices: Set<Int> = []

            for newPart in newParts {
                for (idx, existingPart) in existingParts.enumerated() {
                    if !usedIndices.contains(idx) && partsMatch(newPart, existingPart) {
                        matchedParts.append(newPart)
                        usedIndices.insert(idx)
                        break
                    }
                }
            }

            if matchedParts.count >= 2 {
                matches.append((member: existing, matchCount: matchedParts.count, matchedParts: matchedParts))
            }
        }

        return matches.sorted { $0.matchCount > $1.matchCount }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            if pendingMembers.isEmpty {
                VStack(spacing: DS.Spacing.xl) {
                    ZStack {
                        Circle()
                            .fill(DS.Color.gridTree.opacity(0.08))
                            .frame(width: 140, height: 140)
                        Circle()
                            .fill(DS.Color.gridTree.opacity(0.12))
                            .frame(width: 100, height: 100)
                        Circle()
                            .fill(DS.Color.gradientPrimary)
                            .frame(width: 66, height: 66)
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .font(DS.Font.scaled(28, weight: .semibold))
                            .foregroundColor(DS.Color.textOnPrimary)
                    }
                    Text(L10n.t("لا توجد طلبات معلقة حالياً", "No pending requests"))
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textSecondary)
                }
            } else {
                List {
                    ForEach(pendingMembers) { member in
                        pendingMemberCard(member: member)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(L10n.t("طلبات الربط", "Link Requests"))
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .sheet(item: $selectedMemberForLinking) { member in
            FatherLinkApprovalSheet(member: member, suggestedMatchIds: matchedIdsForSelected)
                .environmentObject(authVM)
                .environmentObject(memberVM)
                .environmentObject(adminRequestVM)
        }
        .alert(
            L10n.t("تأكيد الدمج", "Confirm Merge"),
            isPresented: $showMergeConfirm
        ) {
            Button(L10n.t("دمج", "Merge"), role: .destructive) {
                if let target = mergeTarget {
                    Task {
                        await adminRequestVM.mergeMemberIntoTreeMember(
                            newMemberId: target.pendingMember.id,
                            existingTreeMemberId: target.treeMember.id
                        )
                        await MainActor.run {
                            if let result = adminRequestVM.mergeResult {
                                switch result {
                                case .success(let msg):
                                    mergeSuccessMessage = msg
                                case .failure(let msg):
                                    mergeSuccessMessage = msg
                                }
                                showMergeSuccess = true
                            }
                            mergeTarget = nil
                        }
                    }
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {
                mergeTarget = nil
            }
        } message: {
            if let target = mergeTarget {
                Text(L10n.t(
                    "سيتم ربط حساب \(target.pendingMember.fullName) بسجل \(target.treeMember.fullName) الموجود بالشجرة. سيحتفظ بموقعه بالشجرة وأبنائه وبياناته.",
                    "This will link \(target.pendingMember.fullName)'s account to the existing tree record \(target.treeMember.fullName). Tree position, children, and data will be preserved."
                ))
            }
        }
        .alert(
            {
                if case .failure = adminRequestVM.mergeResult {
                    return L10n.t("خطأ في الدمج", "Merge Error")
                }
                return L10n.t("تم الدمج", "Merge Complete")
            }(),
            isPresented: $showMergeSuccess
        ) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {
                adminRequestVM.mergeResult = nil
            }
        } message: {
            Text(mergeSuccessMessage)
        }
        .task { await memberVM.fetchAllMembers() }
    }

    func pendingMemberCard(member: FamilyMember) -> some View {
        let nameMatches = nameMatchResults[member.id] ?? []
        let hasMatches = !nameMatches.isEmpty
        let isLoading = loadingMatchFor == member.id
        let hasSearched = nameMatchResults.keys.contains(member.id)

        return DSCard {
            VStack(spacing: DS.Spacing.lg) {

                // Accent bar — لون مختلف إذا فيه تطابق
                LinearGradient(
                    colors: hasMatches
                        ? [DS.Color.info, DS.Color.success]
                        : [DS.Color.warning, DS.Color.warning.opacity(0.6)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 4)
                .cornerRadius(DS.Radius.full)

                HStack(spacing: DS.Spacing.lg) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [DS.Color.warning.opacity(0.3), DS.Color.warning.opacity(0.1)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 50, height: 50)

                        Text(member.fullName.prefix(1))
                            .font(DS.Font.headline)
                            .foregroundColor(DS.Color.warning)
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(member.fullName)
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)

                        // عرض الاسم الخماسي بشكل واضح
                        let parts = member.fullName.split(whereSeparator: \.isWhitespace)
                        if parts.count >= 5 {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(DS.Font.scaled(10))
                                    .foregroundColor(DS.Color.success)
                                Text(L10n.t("اسم خماسي مكتمل", "Full 5-part name"))
                                    .font(DS.Font.scaled(10))
                                    .foregroundColor(DS.Color.success)
                            }
                        }

                        Text(L10n.t("سجل في: \(member.createdAt?.prefix(10) ?? "—")", "Registered: \(member.createdAt?.prefix(10) ?? "—")"))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textSecondary)
                    }

                    Spacer()
                }

                // MARK: - زر البحث عن التطابق
                if !hasSearched {
                    Button {
                        withAnimation(DS.Anim.snappy) {
                            loadingMatchFor = member.id
                        }
                        // تأخير بسيط لإظهار اللودنج
                        Task {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            let results = findNameMatches(for: member)
                            withAnimation(DS.Anim.smooth) {
                                nameMatchResults[member.id] = results
                                loadingMatchFor = nil
                            }
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(DS.Color.info)
                            } else {
                                Image(systemName: "person.2.fill")
                                    .font(DS.Font.scaled(14, weight: .semibold))
                            }
                            Text(L10n.t("البحث عن تطابق بالشجرة", "Search for tree matches"))
                                .font(DS.Font.scaled(13, weight: .bold))
                        }
                        .foregroundColor(DS.Color.info)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(DS.Color.info.opacity(0.08))
                        .cornerRadius(DS.Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .stroke(DS.Color.info.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(DSScaleButtonStyle())
                    .disabled(isLoading)
                }

                // MARK: - نتائج التطابق
                if hasSearched {
                    if hasMatches {
                        VStack(spacing: DS.Spacing.sm) {
                            // عنوان التطابق
                            HStack(spacing: DS.Spacing.sm) {
                                Image(systemName: "person.2.fill")
                                    .font(DS.Font.scaled(13, weight: .semibold))
                                    .foregroundColor(DS.Color.info)
                                Text(L10n.t(
                                    "تطابق محتمل مع \(nameMatches.count) عضو بالشجرة",
                                    "Potential match with \(nameMatches.count) tree member(s)"
                                ))
                                .font(DS.Font.scaled(12, weight: .bold))
                                .foregroundColor(DS.Color.info)
                                Spacer()

                                // زر إعادة البحث
                                Button {
                                    withAnimation(DS.Anim.snappy) {
                                        _ = nameMatchResults.removeValue(forKey: member.id)
                                    }
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(DS.Font.scaled(12, weight: .semibold))
                                        .foregroundColor(DS.Color.textTertiary)
                                }
                            }
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(DS.Color.info.opacity(0.08))
                            .cornerRadius(DS.Radius.md)

                            // قائمة الأعضاء المتطابقين
                            ForEach(
                                expandedMatches.contains(member.id) ? nameMatches : Array(nameMatches.prefix(2)),
                                id: \.member.id
                            ) { match in
                                nameMatchRow(match: match, pendingMember: member)
                            }

                            if nameMatches.count > 2 && !expandedMatches.contains(member.id) {
                                Button {
                                    withAnimation(DS.Anim.snappy) {
                                        _ = expandedMatches.insert(member.id)
                                    }
                                } label: {
                                    HStack(spacing: DS.Spacing.xs) {
                                        Image(systemName: "chevron.down")
                                            .font(DS.Font.caption2)
                                        Text(L10n.t(
                                            "عرض الكل (\(nameMatches.count))",
                                            "Show All (\(nameMatches.count))"
                                        ))
                                        .font(DS.Font.caption1)
                                    }
                                    .foregroundColor(DS.Color.primary)
                                    .padding(.top, DS.Spacing.xs)
                                }
                            }
                        }
                    } else {
                        // لا يوجد تطابق
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(DS.Font.scaled(14, weight: .semibold))
                                .foregroundColor(DS.Color.success)
                            Text(L10n.t("لا يوجد تطابق بالشجرة — اسم جديد", "No tree matches — new name"))
                                .font(DS.Font.scaled(12, weight: .bold))
                                .foregroundColor(DS.Color.success)
                            Spacer()

                            // زر إعادة البحث
                            Button {
                                withAnimation(DS.Anim.snappy) {
                                    _ = nameMatchResults.removeValue(forKey: member.id)
                                }
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(DS.Font.scaled(12, weight: .semibold))
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(DS.Color.success.opacity(0.08))
                        .cornerRadius(DS.Radius.md)
                    }
                }

                DSApproveRejectButtons(
                    approveTitle: L10n.t("ربط بالشجرة", "Link to Tree"),
                    rejectTitle: L10n.t("رفض", "Reject"),
                    isLoading: adminRequestVM.isLoading
                ) {
                    Task {
                        let ids = await adminRequestVM.fetchMatchedMemberIds(for: member.id)
                        // ندمج المطابقات المحلية مع مطابقات السيرفر
                        let localMatchIds = nameMatches.map(\.member.id)
                        let combined = Array(Set(ids + localMatchIds))
                        await MainActor.run {
                            matchedIdsForSelected = combined
                            selectedMemberForLinking = member
                        }
                    }
                } onReject: {
                    Task {
                        await adminRequestVM.rejectOrDeleteMember(memberId: member.id)
                    }
                }
            }
            .padding(DS.Spacing.lg)
        }
    }

    // MARK: - صف التطابق
    private func nameMatchRow(match: (member: FamilyMember, matchCount: Int, matchedParts: [String]), pendingMember: FamilyMember) -> some View {
        let totalParts = max(
            pendingMember.fullName.split(whereSeparator: \.isWhitespace).count,
            match.member.fullName.split(whereSeparator: \.isWhitespace).count
        )
        let matchRatio = Double(match.matchCount) / Double(max(totalParts, 1))
        let strengthColor: Color = matchRatio >= 0.8 ? DS.Color.success : matchRatio >= 0.6 ? DS.Color.info : DS.Color.warning

        // اسم الأب لعضو الشجرة
        let fatherName: String? = match.member.fatherId.flatMap { fid in
            memberVM.allMembers.first(where: { $0.id == fid })?.fullName
        }

        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // الصف الأول: أيقونة + اسم العضو المتطابق
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                // أيقونة قوة التطابق
                ZStack {
                    Circle()
                        .fill(strengthColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: matchRatio >= 0.8 ? "checkmark.circle.fill" : "person.fill.questionmark")
                        .font(DS.Font.scaled(17, weight: .semibold))
                        .foregroundColor(strengthColor)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    // اسم العضو الكامل بالشجرة
                    Text(L10n.t("عضو الشجرة:", "Tree member:"))
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)

                    // الاسم مع تمييز الأجزاء المتطابقة
                    highlightedName(
                        fullName: match.member.fullName,
                        matchedParts: match.matchedParts,
                        highlightColor: strengthColor
                    )

                    // اسم الأب إذا موجود
                    if let fatherName {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right")
                                .font(DS.Font.scaled(9, weight: .semibold))
                            Text(L10n.t("ابن: \(fatherName)", "Son of: \(fatherName)"))
                                .font(DS.Font.scaled(11, weight: .medium))
                        }
                        .foregroundColor(DS.Color.textSecondary)
                    }
                }

                Spacer()
            }

            // الصف الثاني: badges + زر الدمج
            HStack(spacing: DS.Spacing.sm) {
                // بادج عدد التطابق
                Text(L10n.t(
                    "\(match.matchCount)/\(totalParts) متطابق",
                    "\(match.matchCount)/\(totalParts) match"
                ))
                .font(DS.Font.scaled(10, weight: .semibold))
                .foregroundColor(strengthColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(strengthColor.opacity(0.12))
                .clipShape(Capsule())

                // بادج قوة التطابق
                Text(matchStrengthLabel(ratio: matchRatio))
                    .font(DS.Font.scaled(10, weight: .bold))
                    .foregroundColor(DS.Color.textOnPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(strengthColor)
                    .clipShape(Capsule())

                Spacer()

                // زر الدمج
                Button {
                    mergeTarget = (pendingMember: pendingMember, treeMember: match.member)
                    showMergeConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(DS.Font.scaled(12, weight: .bold))
                        Text(L10n.t("دمج", "Merge"))
                            .font(DS.Font.scaled(12, weight: .bold))
                    }
                    .foregroundColor(DS.Color.textOnPrimary)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(DS.Color.gradientPrimary)
                    .clipShape(Capsule())
                }
                .buttonStyle(DSScaleButtonStyle())
            }
        }
        .padding(DS.Spacing.md)
        .background(strengthColor.opacity(0.04))
        .cornerRadius(DS.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(strengthColor.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - تمييز الأجزاء المتطابقة
    private func highlightedName(fullName: String, matchedParts: [String], highlightColor: Color) -> some View {
        let parts = fullName.split(whereSeparator: \.isWhitespace).map(String.init)
        // استخدام Text concatenation بدل HStack لتجنب القص
        return parts.enumerated().reduce(Text("")) { result, item in
            let (index, part) = item
            let isMatched = matchedParts.contains { $0.localizedCaseInsensitiveCompare(part) == .orderedSame }
            let separator = index > 0 ? Text(" ") : Text("")
            let styledPart = Text(part)
                .font(DS.Font.scaled(14, weight: isMatched ? .bold : .regular))
                .foregroundColor(isMatched ? highlightColor : DS.Color.textSecondary)
            return result + separator + styledPart
        }
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - وصف قوة التطابق
    private func matchStrengthLabel(ratio: Double) -> String {
        if ratio >= 0.8 {
            return L10n.t("تطابق قوي", "Strong")
        } else if ratio >= 0.6 {
            return L10n.t("تطابق متوسط", "Medium")
        } else {
            return L10n.t("تطابق ضعيف", "Weak")
        }
    }
}

struct FatherLinkApprovalSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) var dismiss
    @FocusState private var isSearchFocused: Bool

    let member: FamilyMember
    let suggestedMatchIds: [UUID]
    @State private var searchText = ""
    @State private var selectedFatherId: UUID?
    @State private var showAllResults = false
    @State private var confirmationShown = false

    /// المرشحون: المطابقات المقترحة أولاً ثم الباقي
    private var fatherCandidates: [FamilyMember] {
        let candidates = memberVM.allMembers.filter { $0.role != .pending && $0.id != member.id }

        if searchText.isEmpty {
            let suggested = candidates.filter { suggestedMatchIds.contains($0.id) }
            let others = candidates.filter { !suggestedMatchIds.contains($0.id) }
            return suggested + (showAllResults ? others : Array(others.prefix(20)))
        }
        return candidates.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }
    }

    private var selectedFather: FamilyMember? {
        guard let id = selectedFatherId else { return nil }
        return memberVM.allMembers.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DS.Spacing.lg) {

                        // MARK: - Member Profile Card
                        memberProfileCard
                            .padding(.top, DS.Spacing.sm)

                        // MARK: - Match Status Banner
                        matchStatusBanner

                        // MARK: - Selected Father Preview
                        if let father = selectedFather {
                            selectedFatherCard(father)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.95).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }

                        // MARK: - Search
                        searchField

                        // MARK: - Candidates List
                        candidatesList

                        // MARK: - Activate Button
                        activateButton
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xxl)
                }
            }
            .navigationTitle(L10n.t("ربط بالأب", "Link to Father"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.Font.scaled(20, weight: .medium))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
            }
            .animation(DS.Anim.snappy, value: selectedFatherId)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .alert(
            L10n.t("تأكيد التفعيل", "Confirm Activation"),
            isPresented: $confirmationShown
        ) {
            Button(L10n.t("تفعيل", "Activate"), role: .none) {
                Task {
                    await adminRequestVM.approveMember(memberId: member.id, fatherId: selectedFatherId)
                    dismiss()
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            if let father = selectedFather {
                Text(L10n.t(
                    "سيتم تفعيل \(member.firstName ?? member.fullName) وربطه كابن لـ \(father.fullName)",
                    "Activate \(member.firstName ?? member.fullName) and link as child of \(father.fullName)"
                ))
            } else {
                Text(L10n.t(
                    "سيتم تفعيل \(member.firstName ?? member.fullName) بدون ربط بأب",
                    "Activate \(member.firstName ?? member.fullName) without linking to a father"
                ))
            }
        }
    }

    // MARK: - Member Profile Card

    private var memberProfileCard: some View {
        DSCard {
            VStack(spacing: DS.Spacing.md) {
                // Avatar + Name
                HStack(spacing: DS.Spacing.md) {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(DS.Color.gradientPrimary)
                            .frame(width: 52, height: 52)
                        if let avatarUrl = member.avatarUrl, let url = URL(string: avatarUrl) {
                            AsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Text(String(member.fullName.prefix(1)))
                                    .font(DS.Font.scaled(22, weight: .bold))
                                    .foregroundColor(DS.Color.textOnPrimary)
                            }
                            .frame(width: 52, height: 52)
                            .clipShape(Circle())
                        } else {
                            Text(String(member.fullName.prefix(1)))
                                .font(DS.Font.scaled(22, weight: .bold))
                                .foregroundColor(DS.Color.textOnPrimary)
                        }
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(L10n.t("عضو جديد", "New Member"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textTertiary)
                        Text(member.fullName)
                            .font(DS.Font.title3)
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(2)
                    }

                    Spacer()

                    // Name parts count badge
                    let parts = member.fullName.split(whereSeparator: \.isWhitespace).count
                    VStack(spacing: 2) {
                        Text("\(parts)")
                            .font(DS.Font.scaled(18, weight: .black))
                            .foregroundColor(parts >= 5 ? DS.Color.success : DS.Color.warning)
                        Text(L10n.t("أجزاء", "parts"))
                            .font(DS.Font.scaled(9, weight: .bold))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    .padding(DS.Spacing.sm)
                    .background((parts >= 5 ? DS.Color.success : DS.Color.warning).opacity(0.08))
                    .cornerRadius(DS.Radius.md)
                }

                // Registration date
                if let createdAt = member.createdAt {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "calendar.badge.clock")
                            .font(DS.Font.scaled(11))
                        Text(L10n.t("تاريخ التسجيل: \(createdAt.prefix(10))", "Registered: \(createdAt.prefix(10))"))
                            .font(DS.Font.caption2)
                    }
                    .foregroundColor(DS.Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Phone if available
                if let phone = member.phoneNumber, !phone.isEmpty {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "phone.fill")
                            .font(DS.Font.scaled(11))
                        Text(phone)
                            .font(DS.Font.caption1)
                    }
                    .foregroundColor(DS.Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Match Status Banner

    private var matchStatusBanner: some View {
        Group {
            if !suggestedMatchIds.isEmpty {
                HStack(spacing: DS.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(DS.Color.success.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(DS.Font.scaled(14, weight: .semibold))
                            .foregroundColor(DS.Color.success)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("مطابقات محتملة", "Potential Matches"))
                            .font(DS.Font.subheadline)
                            .foregroundColor(DS.Color.success)
                        Text(L10n.t(
                            "وُجدت \(suggestedMatchIds.count) مطابقة بالاسم — يُنصح بالربط",
                            "\(suggestedMatchIds.count) name match(es) found — linking recommended"
                        ))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textSecondary)
                    }
                    Spacer()
                    Text("\(suggestedMatchIds.count)")
                        .font(DS.Font.scaled(20, weight: .black))
                        .foregroundColor(DS.Color.success)
                }
                .padding(DS.Spacing.md)
                .background(DS.Color.success.opacity(0.06))
                .cornerRadius(DS.Radius.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .stroke(DS.Color.success.opacity(0.15), lineWidth: 1)
                )
            } else {
                HStack(spacing: DS.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(DS.Color.warning.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "person.fill.questionmark")
                            .font(DS.Font.scaled(14, weight: .semibold))
                            .foregroundColor(DS.Color.warning)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("لا توجد مطابقات", "No Matches"))
                            .font(DS.Font.subheadline)
                            .foregroundColor(DS.Color.warning)
                        Text(L10n.t("ابحث واختر الأب يدوياً من القائمة", "Search and select father manually"))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    Spacer()
                }
                .padding(DS.Spacing.md)
                .background(DS.Color.warning.opacity(0.06))
                .cornerRadius(DS.Radius.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .stroke(DS.Color.warning.opacity(0.15), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Selected Father Card

    private func selectedFatherCard(_ father: FamilyMember) -> some View {
        DSGlowCard(borderColor: DS.Color.success) {
            HStack(spacing: DS.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(DS.Color.success.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "link.circle.fill")
                        .font(DS.Font.scaled(20, weight: .semibold))
                        .foregroundColor(DS.Color.success)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(L10n.t("سيُربط كابن لـ", "Will be linked as child of"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                    Text(father.fullName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.success)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    withAnimation(DS.Anim.snappy) {
                        selectedFatherId = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Font.scaled(20))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(DS.Font.scaled(15, weight: .medium))
                .foregroundColor(isSearchFocused ? DS.Color.primary : DS.Color.textTertiary)

            TextField(L10n.t("ابحث عن الأب بالاسم...", "Search for father by name..."), text: $searchText)
                .font(DS.Font.body)
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Font.scaled(16))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .cornerRadius(DS.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(isSearchFocused ? DS.Color.primary : DS.Color.inactiveBorder, lineWidth: isSearchFocused ? 2 : 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
    }

    // MARK: - Candidates List

    private var candidatesList: some View {
        LazyVStack(spacing: DS.Spacing.sm) {
            // Suggested matches section
            let suggested = fatherCandidates.filter { suggestedMatchIds.contains($0.id) }
            let others = fatherCandidates.filter { !suggestedMatchIds.contains($0.id) }

            if !suggested.isEmpty && searchText.isEmpty {
                DSSectionHeader(
                    L10n.t("مطابقات مقترحة", "Suggested Matches"),
                    icon: "star.fill"
                )

                ForEach(suggested) { father in
                    fatherCandidateRow(father, isSuggested: true)
                }
            }

            if !others.isEmpty {
                if !suggested.isEmpty && searchText.isEmpty {
                    DSSectionHeader(
                        L10n.t("أعضاء آخرون", "Other Members"),
                        icon: "person.3.fill"
                    )
                    .padding(.top, DS.Spacing.sm)
                }

                ForEach(others) { father in
                    fatherCandidateRow(father, isSuggested: false)
                }

                // Show more button
                if searchText.isEmpty && !showAllResults {
                    Button {
                        withAnimation(DS.Anim.snappy) {
                            showAllResults = true
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(DS.Font.scaled(14, weight: .semibold))
                            Text(L10n.t("عرض جميع الأعضاء", "Show all members"))
                                .font(DS.Font.scaled(13, weight: .bold))
                        }
                        .foregroundColor(DS.Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(DS.Color.primary.opacity(0.06))
                        .cornerRadius(DS.Radius.md)
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
            }

            if fatherCandidates.isEmpty {
                VStack(spacing: DS.Spacing.md) {
                    Image(systemName: "magnifyingglass")
                        .font(DS.Font.scaled(28))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(L10n.t("لا توجد نتائج", "No results"))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.xxxl)
            }
        }
    }

    // MARK: - Father Candidate Row

    private func fatherCandidateRow(_ father: FamilyMember, isSuggested: Bool) -> some View {
        let isSelected = selectedFatherId == father.id

        return Button {
            withAnimation(DS.Anim.snappy) {
                selectedFatherId = father.id
            }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? DS.Color.success : DS.Color.textTertiary.opacity(0.3), lineWidth: isSelected ? 0 : 1.5)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(DS.Color.gradientPrimary)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(DS.Font.scaled(12, weight: .bold))
                            .foregroundColor(DS.Color.textOnPrimary)
                    }
                }

                // Avatar
                ZStack {
                    Circle()
                        .fill(isSuggested ? DS.Color.success.opacity(0.12) : DS.Color.primary.opacity(0.1))
                        .frame(width: 38, height: 38)
                    if let avatarUrl = father.avatarUrl, let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Text(String(father.fullName.prefix(1)))
                                .font(DS.Font.scaled(16, weight: .bold))
                                .foregroundColor(isSuggested ? DS.Color.success : DS.Color.primary)
                        }
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                    } else {
                        Text(String(father.fullName.prefix(1)))
                            .font(DS.Font.scaled(16, weight: .bold))
                            .foregroundColor(isSuggested ? DS.Color.success : DS.Color.primary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(father.fullName)
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if isSuggested {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(DS.Font.scaled(8))
                            Text(L10n.t("مطابقة مقترحة", "Suggested match"))
                                .font(DS.Font.scaled(10, weight: .semibold))
                        }
                        .foregroundColor(DS.Color.success)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DS.Font.scaled(18))
                        .foregroundStyle(DS.Color.gradientPrimary)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(DS.Spacing.md)
            .background(
                isSelected
                    ? DS.Color.primary.opacity(0.06)
                    : (isSuggested ? DS.Color.success.opacity(0.03) : DS.Color.surface)
            )
            .cornerRadius(DS.Radius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(
                        isSelected ? DS.Color.primary.opacity(0.3) : (isSuggested ? DS.Color.success.opacity(0.12) : Color.clear),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Activate Button

    private var activateButton: some View {
        VStack(spacing: DS.Spacing.sm) {
            if selectedFatherId == nil {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "info.circle")
                        .font(DS.Font.scaled(12))
                    Text(L10n.t("اختر الأب أولاً لتفعيل العضوية", "Select a father first to activate membership"))
                        .font(DS.Font.caption1)
                }
                .foregroundColor(DS.Color.textTertiary)
            }

            DSPrimaryButton(
                L10n.t("تفعيل العضوية والربط", "Activate & Link"),
                icon: "checkmark.shield.fill",
                isLoading: adminRequestVM.isLoading
            ) {
                confirmationShown = true
            }
            .disabled(selectedFatherId == nil || adminRequestVM.isLoading)
            .opacity((selectedFatherId == nil || adminRequestVM.isLoading) ? 0.5 : 1.0)
        }
    }
}
