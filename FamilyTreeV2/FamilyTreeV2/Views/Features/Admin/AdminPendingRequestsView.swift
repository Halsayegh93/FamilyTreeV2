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

    /// المرشحون: المطابقات المقترحة أولاً ثم الباقي
    private var fatherCandidates: [FamilyMember] {
        let candidates = memberVM.allMembers.filter { $0.role != .pending && $0.id != member.id }

        if searchText.isEmpty {
            // المطابقات المقترحة أولاً
            let suggested = candidates.filter { suggestedMatchIds.contains($0.id) }
            let others = candidates.filter { !suggestedMatchIds.contains($0.id) }
            return suggested + others.prefix(20)
        }
        return candidates.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.md) {

                // Header icon
                ZStack {
                    Circle()
                        .fill(DS.Color.gradientPrimary)
                        .frame(width: 56, height: 56)
                    Image(systemName: "link.badge.plus")
                        .font(DS.Font.scaled(22, weight: .semibold))
                        .foregroundColor(DS.Color.textOnPrimary)
                }
                .dsGlowShadow()
                .padding(.top, DS.Spacing.sm)

                // عرض اسم العضو الجديد بوضوح
                VStack(spacing: DS.Spacing.xs) {
                    Text(L10n.t("ربط العضو بالأب قبل التفعيل", "Link member to father before activation"))
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textPrimary)

                    Text(member.fullName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(DS.Color.primary.opacity(0.08))
                        .cornerRadius(DS.Radius.md)
                }

                // شريط معلومات المطابقات
                if !suggestedMatchIds.isEmpty {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(DS.Font.scaled(14))
                            .foregroundColor(DS.Color.success)
                        Text(L10n.t(
                            "وُجدت \(suggestedMatchIds.count) مطابقة محتملة بالاسم",
                            "\(suggestedMatchIds.count) potential name match(es) found"
                        ))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.success)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(DS.Color.success.opacity(0.08))
                    .cornerRadius(DS.Radius.md)
                } else {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "info.circle.fill")
                            .font(DS.Font.scaled(14))
                            .foregroundColor(DS.Color.warning)
                        Text(L10n.t("لا توجد مطابقات — اختر الأب يدوياً", "No matches — select father manually"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.warning)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(DS.Color.warning.opacity(0.08))
                    .cornerRadius(DS.Radius.md)
                }

                // حقل البحث
                HStack(spacing: DS.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(DS.Color.gradientPrimary)
                            .frame(width: 32, height: 32)
                        Image(systemName: "magnifyingglass")
                            .font(DS.Font.scaled(12, weight: .semibold))
                            .foregroundColor(DS.Color.textOnPrimary)
                    }

                    TextField(L10n.t("ابحث عن الأب...", "Search for father..."), text: $searchText)
                        .multilineTextAlignment(.leading)
                        .font(DS.Font.body)
                        .focused($isSearchFocused)
                }
                .padding(DS.Spacing.md)
                .background(DS.Color.surface)
                .cornerRadius(DS.Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(isSearchFocused ? DS.Color.primary : DS.Color.inactiveBorder, lineWidth: isSearchFocused ? 2 : 1)
                )
                .animation(.easeInOut(duration: 0.2), value: isSearchFocused)

                List(fatherCandidates) { father in
                    Button {
                        selectedFatherId = father.id
                    } label: {
                        HStack(spacing: DS.Spacing.md) {
                            if selectedFatherId == father.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(DS.Font.scaled(20))
                                    .foregroundStyle(DS.Color.gradientPrimary)
                            } else {
                                Image(systemName: "circle")
                                    .font(DS.Font.scaled(20))
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(father.fullName)
                                    .font(DS.Font.callout)
                                    .foregroundColor(DS.Color.textPrimary)
                                // علامة المطابقة المقترحة
                                if suggestedMatchIds.contains(father.id) {
                                    Text(L10n.t("مطابقة محتملة", "Potential match"))
                                        .font(DS.Font.scaled(10, weight: .semibold))
                                        .foregroundColor(DS.Color.success)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(DS.Color.success.opacity(0.12))
                                        .cornerRadius(DS.Radius.sm)
                                }
                            }
                        }
                    }
                    .listRowBackground(
                        suggestedMatchIds.contains(father.id)
                            ? DS.Color.success.opacity(0.04)
                            : Color.clear
                    )
                }
                .listStyle(.plain)

                if selectedFatherId == nil {
                    Text(L10n.t("اختر الأب أولاً قبل تفعيل العضوية.", "Select father first before activating membership."))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                DSPrimaryButton(
                    L10n.t("تفعيل العضوية والربط", "Activate & Link"),
                    icon: "checkmark.circle.fill",
                    isLoading: adminRequestVM.isLoading
                ) {
                    Task {
                        await adminRequestVM.approveMember(memberId: member.id, fatherId: selectedFatherId)
                        dismiss()
                    }
                }
                .disabled(selectedFatherId == nil || adminRequestVM.isLoading)
                .opacity((selectedFatherId == nil || adminRequestVM.isLoading) ? 0.6 : 1.0)
            }
            .padding(DS.Spacing.lg)
            .navigationTitle(L10n.t("اعتماد طلب الربط", "Approve Link Request"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.error)
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}
