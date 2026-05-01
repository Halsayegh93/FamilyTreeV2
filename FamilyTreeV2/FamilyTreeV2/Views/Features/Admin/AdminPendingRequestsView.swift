import SwiftUI

struct AdminPendingRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    /// نتائج مطابقة الأسماء لكل عضو (يتم تفعيلها بالضغط على الزر)
    @State private var nameMatchResults: [UUID: [(member: FamilyMember, matchCount: Int, matchedParts: [String])]] = [:]
    @State private var loadingMatchFor: UUID? = nil
    /// Merge confirmation state
    @State private var mergeTarget: (pendingMember: FamilyMember, treeMember: FamilyMember)? = nil
    @State private var showMergeConfirm = false
    @State private var showMergeSuccess = false
    @State private var mergeSuccessMessage = ""
    @State private var expandedMatches: Set<UUID> = []
    /// الربط المباشر بعضو موجود (swipe right)
    @State private var memberToLink: FamilyMember? = nil

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

            if pendingMembers.isEmpty {
                DSEmptyState(
                    icon: "person.badge.shield.checkmark.fill",
                    title: L10n.t("لا توجد طلبات معلقة حالياً", "No pending requests"),
                    style: .halo,
                    tint: DS.Color.success
                )
            } else {
                List {
                    ForEach(pendingMembers) { member in
                        pendingMemberCard(member: member)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    memberToLink = member
                                } label: {
                                    Label(L10n.t("ربط", "Link"), systemImage: "link.badge.plus")
                                }
                                .tint(DS.Color.success)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if authVM.canRejectRequests {
                                    Button(role: .destructive) {
                                        Task { await adminRequestVM.rejectOrDeleteMember(memberId: member.id) }
                                    } label: {
                                        Label(L10n.t("رفض", "Reject"), systemImage: "xmark.circle.fill")
                                    }
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(L10n.t("طلبات الربط", "Link Requests"))
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .sheet(item: $memberToLink) { member in
            LinkToExistingMemberSheet(pendingMember: member)
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
        .alert(
            L10n.t("خطأ", "Error"),
            isPresented: Binding(
                get: { adminRequestVM.errorMessage != nil },
                set: { if !$0 { adminRequestVM.errorMessage = nil } }
            )
        ) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {
                adminRequestVM.errorMessage = nil
            }
        } message: {
            Text(adminRequestVM.errorMessage ?? "")
        }
    }

    func pendingMemberCard(member: FamilyMember) -> some View {
        let nameMatches = nameMatchResults[member.id] ?? []
        let hasMatches = !nameMatches.isEmpty
        let isLoading = loadingMatchFor == member.id
        let hasSearched = nameMatchResults.keys.contains(member.id)
        let platform = member.registrationPlatform ?? "ios"
        let registrationTime = member.createdAt.map { formatRegistrationDate($0) } ?? "—"
        let uname = member.username

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

                        // اسم المستخدم (من الموقع)
                        if let uname {
                            HStack(spacing: 4) {
                                Image(systemName: "at")
                                    .font(DS.Font.scaled(10, weight: .bold))
                                    .foregroundColor(DS.Color.primary)
                                Text(uname)
                                    .font(DS.Font.scaled(11, weight: .bold))
                                    .foregroundColor(DS.Color.primary)
                            }
                        }

                        // عرض الاسم الخماسي بشكل واضح
                        if member.fullName.split(whereSeparator: \.isWhitespace).count >= 5 {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(DS.Font.scaled(10))
                                    .foregroundColor(DS.Color.success)
                                Text(L10n.t("اسم خماسي مكتمل", "Full 5-part name"))
                                    .font(DS.Font.scaled(10))
                                    .foregroundColor(DS.Color.success)
                            }
                        }

                        // الوقت والتاريخ
                        HStack(spacing: 3) {
                            Image(systemName: "clock.fill")
                                .font(DS.Font.scaled(9))
                            Text(registrationTime)
                                .font(DS.Font.scaled(10, weight: .semibold))
                        }
                        .foregroundColor(DS.Color.textSecondary)

                        // المصدر
                        HStack(spacing: 3) {
                            Image(systemName: platform == "web" ? "globe" : "iphone")
                                .font(DS.Font.scaled(9))
                            Text(platform == "web" ? L10n.t("الموقع", "Web") : L10n.t("التطبيق", "App"))
                                .font(DS.Font.scaled(10, weight: .bold))
                        }
                        .foregroundColor(platform == "web" ? DS.Color.info : DS.Color.success)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((platform == "web" ? DS.Color.info : DS.Color.success).opacity(0.12))
                        .clipShape(Capsule())
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
                                .accessibilityLabel(L10n.t("إعادة البحث", "Search again"))
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
                            .accessibilityLabel(L10n.t("إعادة البحث", "Search again"))
                        }
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(DS.Color.success.opacity(0.08))
                        .cornerRadius(DS.Radius.md)
                    }
                }

                DSSecondaryButton(
                    L10n.t("رفض الطلب", "Reject Request"),
                    icon: "xmark.circle",
                    color: DS.Color.error
                ) {
                    Task { await adminRequestVM.rejectOrDeleteMember(memberId: member.id) }
                }
                .disabled(adminRequestVM.isLoading)
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
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, 3)
                .background(strengthColor.opacity(0.12))
                .clipShape(Capsule())

                // بادج قوة التطابق
                Text(matchStrengthLabel(ratio: matchRatio))
                    .font(DS.Font.scaled(10, weight: .bold))
                    .foregroundColor(DS.Color.textOnPrimary)
                    .padding(.horizontal, DS.Spacing.sm)
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

    // MARK: - تنسيق تاريخ التسجيل مع الوقت
    private func formatRegistrationDate(_ isoString: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        guard let date = iso.date(from: isoString) ?? iso2.date(from: isoString) else {
            return String(isoString.prefix(16)).replacingOccurrences(of: "T", with: " ")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateFormat = "d MMM · h:mm a"
        return formatter.string(from: date)
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

// MARK: - ربط مباشر بعضو موجود بالشجرة (swipe right)
struct LinkToExistingMemberSheet: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) var dismiss
    @FocusState private var searchFocused: Bool

    let pendingMember: FamilyMember

    @State private var searchText = ""
    @State private var selectedMember: FamilyMember? = nil
    @State private var showConfirm = false

    private var candidates: [FamilyMember] {
        let all = memberVM.allMembers.filter {
            $0.role != .pending &&
            $0.id != pendingMember.id &&
            $0.isDeceased == false
        }
        if searchText.isEmpty { return all }
        return all.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // بطاقة العضو المعلق
                    VStack(spacing: DS.Spacing.xs) {
                        HStack(spacing: DS.Spacing.md) {
                            ZStack {
                                Circle()
                                    .fill(DS.Color.warning.opacity(0.15))
                                    .frame(width: 46, height: 46)
                                Text(pendingMember.fullName.prefix(1))
                                    .font(DS.Font.scaled(20, weight: .bold))
                                    .foregroundColor(DS.Color.warning)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t("سيتم ربط حساب:", "Linking account:"))
                                    .font(DS.Font.caption2)
                                    .foregroundColor(DS.Color.textTertiary)
                                Text(pendingMember.fullName)
                                    .font(DS.Font.calloutBold)
                                    .foregroundColor(DS.Color.textPrimary)
                            }
                            Spacer()
                        }

                        if let selected = selectedMember {
                            HStack(spacing: DS.Spacing.sm) {
                                Image(systemName: "arrow.down")
                                    .font(DS.Font.scaled(12, weight: .bold))
                                    .foregroundColor(DS.Color.success)
                                Text(L10n.t("سيُربط بـ", "Will link to"))
                                    .font(DS.Font.caption1)
                                    .foregroundColor(DS.Color.textSecondary)
                                Text(selected.fullName)
                                    .font(DS.Font.calloutBold)
                                    .foregroundColor(DS.Color.success)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    withAnimation(DS.Anim.snappy) { selectedMember = nil }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(DS.Color.textTertiary)
                                }
                            }
                            .padding(DS.Spacing.sm)
                            .background(DS.Color.success.opacity(0.08))
                            .cornerRadius(DS.Radius.md)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(DS.Spacing.lg)
                    .background(DS.Color.surface)

                    // حقل البحث
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(searchFocused ? DS.Color.primary : DS.Color.textTertiary)
                        TextField(L10n.t("ابحث عن عضو...", "Search member..."), text: $searchText)
                            .focused($searchFocused)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                        }
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.lg)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .stroke(searchFocused ? DS.Color.primary : DS.Color.inactiveBorder, lineWidth: searchFocused ? 2 : 1))
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)

                    // القائمة
                    List {
                        ForEach(candidates) { member in
                            let isSelected = selectedMember?.id == member.id
                            Button {
                                withAnimation(DS.Anim.snappy) {
                                    selectedMember = isSelected ? nil : member
                                }
                            } label: {
                                HStack(spacing: DS.Spacing.md) {
                                    ZStack {
                                        Circle()
                                            .fill(isSelected ? DS.Color.success.opacity(0.15) : DS.Color.primary.opacity(0.08))
                                            .frame(width: 38, height: 38)
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(DS.Font.scaled(14, weight: .bold))
                                                .foregroundColor(DS.Color.success)
                                        } else {
                                            Text(member.fullName.prefix(1))
                                                .font(DS.Font.scaled(16, weight: .bold))
                                                .foregroundColor(DS.Color.primary)
                                        }
                                    }
                                    Text(member.fullName)
                                        .font(DS.Font.callout)
                                        .foregroundColor(DS.Color.textPrimary)
                                        .lineLimit(2)
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(DS.Color.gradientPrimary)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .padding(.vertical, DS.Spacing.xs)
                            }
                            .buttonStyle(DSScaleButtonStyle())
                            .listRowBackground(
                                isSelected ? DS.Color.success.opacity(0.05) : Color.clear
                            )
                            .listRowSeparator(isSelected ? .hidden : .visible)
                        }
                    }
                    .listStyle(.plain)

                    // زر الربط
                    DSPrimaryButton(
                        L10n.t("ربط بهذا العضو", "Link to This Member"),
                        icon: "link.badge.plus",
                        isLoading: adminRequestVM.isLoading
                    ) {
                        showConfirm = true
                    }
                    .disabled(selectedMember == nil || adminRequestVM.isLoading)
                    .opacity(selectedMember == nil ? 0.5 : 1.0)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Color.surface)
                }
            }
            .navigationTitle(L10n.t("ربط بعضو موجود", "Link to Existing Member"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.Font.scaled(20))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
            }
            .animation(DS.Anim.snappy, value: selectedMember?.id)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .alert(
            L10n.t("تأكيد الربط", "Confirm Link"),
            isPresented: $showConfirm
        ) {
            Button(L10n.t("ربط", "Link"), role: .none) {
                guard let target = selectedMember else { return }
                Task {
                    await adminRequestVM.mergeMemberIntoTreeMember(
                        newMemberId: pendingMember.id,
                        existingTreeMemberId: target.id
                    )
                    dismiss()
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            if let target = selectedMember {
                Text(L10n.t(
                    "سيُربط حساب \(pendingMember.firstName) بسجل \(target.fullName) الموجود بالشجرة.\nسيحتفظ بموقعه وأبنائه وبياناته.",
                    "Account \(pendingMember.firstName) will be linked to \(target.fullName)'s existing tree record. Position, children and data will be preserved."
                ))
            }
        }
    }
}

