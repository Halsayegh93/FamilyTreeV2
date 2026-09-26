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
    /// تعديل/إضافة رقم فعلي لعضو معلّق
    @State private var phoneEditMember: FamilyMember? = nil

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
        .dsTallBox(item: $memberToLink) { member in   // قائمة أعضاء طويلة (توصية أبل)
            LinkToExistingMemberSheet(pendingMember: member)
                .environmentObject(memberVM)
                .environmentObject(adminRequestVM)
        }
        .dsCenterBox(item: $phoneEditMember) { member in
            PendingMemberPhoneSheet(member: member)
                .environmentObject(adminRequestVM)
        }
        .dsAlert(
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
        .dsAlert(
            {
                if case .failure = adminRequestVM.mergeResult {
                    return L10n.t("خطأ في الدمج", "Merge Error")
                }
                return L10n.t("تم الدمج", "Merge Complete")
            }(),
            isPresented: $showMergeSuccess
        ) {
            Button(L10n.t("حسناً", "OK")) {
                adminRequestVM.mergeResult = nil
            }
        } message: {
            Text(mergeSuccessMessage)
        }
        .task {
            if memberVM.allMembers.isEmpty {
                await memberVM.fetchAllMembers()
            }
        }
        .dsAlert(
            L10n.t("خطأ", "Error"),
            isPresented: Binding(
                get: { adminRequestVM.errorMessage != nil },
                set: { if !$0 { adminRequestVM.errorMessage = nil } }
            )
        ) {
            Button(L10n.t("حسناً", "OK")) {
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
                        Text(member.displayFullName)
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)

                        // اسم المستخدم (من الموقع)
                        if let uname {
                            HStack(spacing: 4) {
                                Image(systemName: "at")
                                    .font(DS.Font.scaled(11, weight: .bold))
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
                                    .font(DS.Font.scaled(11))
                                    .foregroundColor(DS.Color.success)
                                Text(L10n.t("اسم خماسي مكتمل", "Full 5-part name"))
                                    .font(DS.Font.scaled(11))
                                    .foregroundColor(DS.Color.success)
                            }
                        }

                        // الوقت والتاريخ
                        HStack(spacing: 3) {
                            Image(systemName: "clock.fill")
                                .font(DS.Font.scaled(11))
                            Text(registrationTime)
                                .font(DS.Font.scaled(11, weight: .semibold))
                        }
                        .foregroundColor(DS.Color.textSecondary)

                        // المصدر
                        HStack(spacing: 3) {
                            Image(systemName: platform == "web" ? "globe" : "iphone")
                                .font(DS.Font.scaled(11))
                            Text(platform == "web" ? L10n.t("الموقع", "Web") : L10n.t("التطبيق", "App"))
                                .font(DS.Font.scaled(11, weight: .bold))
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

                            // 1) RPC الذكي: مطابقة جزأين+ مع exact word + top-4 parts (v2)
                            let serverIds = await adminRequestVM.searchMembersByNameRPC(
                                member.fullName,
                                excluding: member.id
                            )
                            let serverMembers: [FamilyMember] = serverIds.compactMap { id in
                                memberVM.allMembers.first(where: { $0.id == id })
                            }

                            // 2) Fallback/تكميل: المطابقة المحلية (Arabic normalization + compound names)
                            let localMatches = findNameMatches(for: member)
                            let serverIdSet = Set(serverIds)
                            let extraLocalMatches = localMatches.filter { !serverIdSet.contains($0.member.id) }

                            // 3) دمج: السيرفر أولاً (أدق)، ثم باقي المحلي
                            var merged: [(member: FamilyMember, matchCount: Int, matchedParts: [String])] = []
                            for m in serverMembers {
                                merged.append((member: m, matchCount: 0, matchedParts: []))
                            }
                            merged.append(contentsOf: extraLocalMatches)

                            withAnimation(DS.Anim.smooth) {
                                nameMatchResults[member.id] = merged
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

                // تعديل / إضافة رقم فعلي للعضو المعلّق
                Button {
                    phoneEditMember = member
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "phone.badge.plus")
                            .font(DS.Font.scaled(14, weight: .semibold))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L10n.t("تعديل / إضافة رقم فعلي", "Edit / Add real number"))
                                .font(DS.Font.scaled(13, weight: .bold))
                            Text(phoneSubtitle(for: member))
                                .font(DS.Font.scaled(11, weight: .medium))
                                .foregroundColor(DS.Color.textSecondary)
                        }
                        Spacer()
                        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                            .font(DS.Font.scaled(11, weight: .bold))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    .foregroundColor(DS.Color.primary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(DS.Color.primary.opacity(0.08))
                    .cornerRadius(DS.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.primary.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(DSScaleButtonStyle())
                .disabled(adminRequestVM.isLoading)

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
                        .font(DS.Font.scaled(11, weight: .medium))
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
                                .font(DS.Font.scaled(11, weight: .semibold))
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
                .font(DS.Font.scaled(11, weight: .semibold))
                .foregroundColor(strengthColor)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, 3)
                .background(strengthColor.opacity(0.12))
                .clipShape(Capsule())

                // بادج قوة التطابق
                Text(matchStrengthLabel(ratio: matchRatio))
                    .font(DS.Font.scaled(11, weight: .bold))
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

    // MARK: - وصف رقم الجوال للعضو المعلّق
    private func phoneSubtitle(for member: FamilyMember) -> String {
        let phone = member.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if phone.isEmpty {
            return L10n.t("لا يوجد رقم — اضغط للإضافة", "No number — tap to add")
        }
        return L10n.t("الرقم الحالي: ", "Current: ") + KuwaitPhone.display(phone)
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
        formatter.dateFormat = "d MMM yyyy · h:mm a"
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

/// عدد الأعضاء الظاهرين في قائمة الربط قبل «عرض المزيد» — صفوف عادية لا قائمة كسولة
/// حتى يُقاس ارتفاع المربّع كاملاً (نفس ملاحظة مربّعات الاختيار)
private let linkCandidatesPageSize = 40

/// صورة الحرف الأول للعضو في صفوف المربّعات (بحجم أيقونة الحقل)
private func memberInitialBadge(_ name: String, tint: Color) -> some View {
    Text(name.prefix(1))
        .font(DS.Font.plex(14, weight: .bold))
        .foregroundColor(tint)
        .frame(width: 32, height: 32)
        .background(Circle().fill(tint.opacity(0.14)))
}

/// «ربط بعضو موجود» — نفس تصميم المربّعات الموحّد (طلب المالك): رأس كحلي، الحساب المعلّق
/// ثم البحث في أعضاء الشجرة، و«ربط» / «إلغاء» أسفل المربّع
struct LinkToExistingMemberSheet: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) var dismiss
    /// «تقليل الحركة» (توصية أبل): صف المختار يظهر بتلاشٍ فقط بلا انزلاق ولا تكبير
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let pendingMember: FamilyMember

    @State private var searchText = ""
    @State private var selectedMember: FamilyMember? = nil
    @State private var showConfirm = false
    @State private var displayLimit = linkCandidatesPageSize

    private var candidates: [FamilyMember] {
        let all = memberVM.allMembers.filter {
            $0.role != .pending &&
            $0.id != pendingMember.id &&
            $0.isDeceased != true
        }
        if searchText.isEmpty { return all }
        return all.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        DSComposer(
            title: L10n.t("ربط بعضو موجود", "Link to Existing Member"),
            subtitle: pendingMember.displayFullName,
            icon: "link.badge.plus",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("ربط", "Link"),
            actionIcon: "link",
            canSubmit: selectedMember != nil,
            isBusy: adminRequestVM.isLoading,
            // عضو مختار ولم يُربط بعد → «إلغاء» يسأل قبل التجاهل (توصية أبل)
            hasUnsavedChanges: selectedMember != nil,
            onSubmit: { showConfirm = true },
            onCancel: { dismiss() }
        ) {
            accountSection
            candidatesSection
        }
        .animation(DS.Anim.snappy, value: selectedMember?.id)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        // بحث جديد → نبدأ من أول النتائج
        .onChange(of: searchText) { _ in displayLimit = linkCandidatesPageSize }
        .dsAlert(
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

    // MARK: الحساب المعلّق + العضو المختار

    private var accountSection: some View {
        DSComposerSection(title: L10n.t("الحساب المعلّق", "Pending Account"),
                          icon: "person.fill",
                          tint: DS.Color.warning,
                          index: 0) {
            HStack(spacing: DS.Spacing.sm) {
                memberInitialBadge(pendingMember.fullName, tint: DS.Color.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("سيتم ربط حساب:", "Linking account:"))
                        .font(DS.Font.plex(12, weight: .heavy))
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(pendingMember.displayFullName)
                        .font(DS.Font.plex(14.5))
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .accessibilityElement(children: .combine)

            if let selected = selectedMember {
                HStack(spacing: DS.Spacing.sm) {
                    DSFieldIcon(name: "arrow.down", tint: DS.Color.success)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("سيُربط بـ", "Will link to"))
                            .font(DS.Font.plex(12, weight: .heavy))
                            .foregroundColor(DS.Color.fieldLabel)
                        Text(selected.displayFullName)
                            .font(DS.Font.plex(14.5, weight: .bold))
                            .foregroundColor(DS.Color.success)
                            .lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(DS.Anim.snappy) { selectedMember = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(DS.Color.textTertiary)
                            // مساحة ضغط ٤٤ (توصية أبل) — الرمز وحجم الصف كما هما
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .padding(-12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("إلغاء الاختيار", "Clear selection"))
                }
                .dsRowBox()
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: البحث + أعضاء الشجرة

    private var candidatesSection: some View {
        let list = candidates
        let visible = Array(list.prefix(displayLimit))
        return DSComposerSection(title: L10n.t("أعضاء الشجرة", "Tree Members"),
                                 icon: "person.3.fill",
                                 tint: DS.Color.primary,
                                 index: 1) {
            DSComposerField(icon: "magnifyingglass",
                            label: L10n.t("بحث", "Search"),
                            placeholder: L10n.t("ابحث عن عضو...", "Search member..."),
                            text: $searchText)
                .overlay(alignment: .trailing) { clearSearchButton }

            ForEach(visible) { member in
                candidateRow(member)
            }

            if list.count > visible.count {
                showMoreButton(remaining: list.count - visible.count)
            }
        }
    }

    @ViewBuilder
    private var clearSearchButton: some View {
        if !searchText.isEmpty {
            Button { searchText = "" } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(DS.Color.textTertiary)
                    // مساحة ضغط ٤٤ (توصية أبل) بلا هامش — الرمز في نفس موضعه (كان ٣٦ + هامش ٤)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("مسح البحث", "Clear search"))
        }
    }

    private func candidateRow(_ member: FamilyMember) -> some View {
        let isSelected = selectedMember?.id == member.id
        return Button {
            withAnimation(DS.Anim.snappy) {
                selectedMember = isSelected ? nil : member
            }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Group {
                    if isSelected {
                        DSFieldIcon(name: "checkmark", tint: DS.Color.success)
                    } else {
                        memberInitialBadge(member.fullName, tint: DS.Color.primary)
                    }
                }
                .accessibilityHidden(true)
                Text(member.displayFullName)
                    .font(DS.Font.plex(14.5, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? DS.Color.textPrimary : DS.Color.fieldValue)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(DS.Color.success)
                        // «تقليل الحركة»: تلاشٍ فقط بلا تكبير
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .dsRowBox()
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Color.success.opacity(isSelected ? 0.55 : 0), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func showMoreButton(remaining: Int) -> some View {
        Button {
            withAnimation(DS.Anim.snappy) { displayLimit += linkCandidatesPageSize }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
                Text(L10n.t(
                    "عرض المزيد (\(remaining) متبقي)",
                    "Show more (\(remaining) remaining)"
                ))
                .font(DS.Font.plex(12.5, weight: .bold))
            }
            .foregroundColor(DS.Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xs)
            .frame(minHeight: 44)   // مساحة ضغط ٤٤ (توصية أبل) — النص كما هو
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
    }
}

// MARK: - مربّع تعديل / إضافة رقم فعلي لعضو معلّق
/// نفس تصميم المربّعات الموحّد (طلب المالك): رأس كحلي، العضو ثم الرقم الجديد،
/// و«حفظ» / «إلغاء» أسفل المربّع
struct PendingMemberPhoneSheet: View {
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    let member: FamilyMember
    /// عند true يفعّل العضو بعد حفظ الرقم (يُستخدم في «صحة الشجرة»)
    var activateOnSave: Bool = false

    @State private var selectedCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var localDigits: String = ""
    @State private var errorBanner: String? = nil

    private var canSave: Bool {
        !localDigits.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !adminRequestVM.isLoading
    }

    /// الرقم الذي يُفتح عليه المربّع (نفس تعبئة onAppear) — للمقارنة بما أُدخل
    private var start: (country: KuwaitPhone.Country, localDigits: String) {
        KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
    }

    var body: some View {
        DSComposer(
            title: L10n.t("رقم العضو", "Member Number"),
            subtitle: member.displayFullName,
            icon: "phone.badge.plus",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            canSubmit: canSave,
            isBusy: adminRequestVM.isLoading,
            // رقم أو دولة مختلفة عمّا فُتح عليه → «إلغاء» يسأل قبل التجاهل (توصية أبل)
            hasUnsavedChanges: localDigits != start.localDigits || selectedCountry != start.country,
            onSubmit: { save() },
            onCancel: { dismiss() }
        ) {
            memberSection
            numberSection
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear {
            let detected = start
            selectedCountry = detected.country
            localDigits = detected.localDigits
            focused = true
        }
    }

    // MARK: العضو

    private var memberSection: some View {
        DSComposerSection(title: L10n.t("العضو", "Member"),
                          icon: "person.fill",
                          tint: DS.Color.warning,
                          index: 0) {
            HStack(spacing: DS.Spacing.sm) {
                memberInitialBadge(member.fullName, tint: DS.Color.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayFullName)
                        .font(DS.Font.plex(14.5, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                    // الرقم معزول باتجاه LTR — بدونه يظهر في السطر العربي «50011223 965+»
                    Text(L10n.t("الرقم الحالي: ", "Current: ")
                         + "\u{2066}" + KuwaitPhone.display(member.phoneNumber) + "\u{2069}")
                        .font(DS.Font.plex(12))
                        .foregroundColor(DS.Color.fieldValue)
                }
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: الرقم الجديد (الدولة + الرقم المحلي)

    private var numberSection: some View {
        DSComposerSection(title: L10n.t("الرقم الفعلي الجديد", "New real number"),
                          icon: "number",
                          tint: DS.Color.success,
                          index: 1) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "phone.fill", tint: DS.Color.success)
                    .accessibilityHidden(true)
                DSPhoneField(
                    country: $selectedCountry,
                    digits: $localDigits,
                    placeholder: String(repeating: "X", count: selectedCountry.maxDigits),
                    compact: true,
                    bordered: false
                )
            }
            .dsRowBox()

            Text(activateOnSave
                 ? L10n.t(
                    "سيُضاف الرقم ويُفعّل الحساب مباشرة بعد الحفظ.",
                    "The number will be added and the account activated right after saving.")
                 : L10n.t(
                    "يُحدَّث رقم العضو فقط — يبقى الطلب معلّقاً لتربطه بالشجرة أو ترفضه لاحقاً.",
                    "Only updates the member's number — the request stays pending so you can link or reject it later."))
                .font(DS.Font.plex(11.5))
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorBanner {
                Text(errorBanner)
                    .font(DS.Font.plex(12, weight: .semibold))
                    .foregroundColor(DS.Color.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func save() {
        errorBanner = nil
        Task {
            let ok = await adminRequestVM.updatePendingMemberPhone(
                memberId: member.id,
                country: selectedCountry,
                localDigits: localDigits,
                activate: activateOnSave
            )
            if ok {
                dismiss()
            } else {
                errorBanner = adminRequestVM.errorMessage
                adminRequestVM.errorMessage = nil
            }
        }
    }
}
