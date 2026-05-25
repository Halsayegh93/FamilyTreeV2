import SwiftUI

/// شجرة بنمط drill-down متراكم — كل مستوى يضاف **أسفل** السابق.
/// كل عضو = مربع موحّد الحجم. السلف يظهر مرة واحدة (بدون شبكة)،
/// والعضو النشط (الأخير) يظهر مع شبكة أبنائه بترتيب ذكي حسب العدد.
///
/// **التحكّم:**
///   - نقرة على ابن في الشبكة → تفرّع داخله (يصير النشط).
///   - نقرة على سلف في السلسلة → قفز إليه (طي ما تحته).
///   - نقرة على النشط → طي مستوى واحد للأعلى (collapse).
///   - ضغطة مطوّلة على أي عضو → فتح شاشة التفاصيل.
///
/// **ملاحظة**: مربوط حالياً عبر TreeTabContainer مع تبويب الكلاسيكي.
struct DrillDownTreeView: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @Binding var selectedTab: Int

    /// السلسلة الكاملة: الجذر → الأقرب. آخر عضو = النشط.
    @State private var chain: [FamilyMember] = []
    @State private var selectedMemberForDetails: FamilyMember? = nil
    @State private var showingNotifications = false
    @State private var showSearchBar = false
    @State private var scrollTarget: UUID? = nil

    /// الحجم الموحّد لمربع العضو.
    private let squareSize: CGFloat = 120

    /// استخراج السنة (4 أرقام) من نص تاريخ قد يكون بأي صيغة (YYYY-MM-DD، YYYY/M/D، YYYY فقط).
    private func year(from dateString: String?) -> String? {
        guard let s = dateString?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if let range = s.range(of: "\\d{4}", options: .regularExpression) {
            return String(s[range])
        }
        return nil
    }

    // MARK: - Helpers

    private var roots: [FamilyMember] {
        let visible = memberVM.allMembers.filter(\.isCountable)
        let byId = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        let fatherIds = Set(visible.compactMap(\.fatherId))
        return visible.filter { m in
            guard let fid = m.fatherId else { return fatherIds.contains(m.id) }
            return byId[fid] == nil
        }.sortedForDisplay()
    }

    private func children(of memberId: UUID) -> [FamilyMember] {
        memberVM.allMembers
            .filter { $0.fatherId == memberId && $0.isCountable }
            .sortedForDisplay()
    }

    /// ترتيب صفوف الأبناء: دائماً 3 لكل صف، الصف الأخير حسب الباقي.
    /// 1→1، 2→2، 3→3، 4→3+1، 5→3+2، 6→3+3، 7→3+3+1، ...
    private func smartRows(_ kids: [FamilyMember]) -> [[FamilyMember]] {
        let n = kids.count
        guard n > 0 else { return [] }
        let perRow = 3
        if n <= perRow { return [kids] }
        let full = n / perRow
        let rem = n % perRow
        let counts = Array(repeating: perRow, count: full) + (rem > 0 ? [rem] : [])
        var rows: [[FamilyMember]] = []
        var idx = 0
        for c in counts {
            rows.append(Array(kids[idx..<idx + c]))
            idx += c
        }
        return rows
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    MainHeaderView(
                        selectedTab: $selectedTab,
                        showingNotifications: $showingNotifications,
                        title: L10n.t("الشجرة", "Family Tree"),
                        subtitle: L10n.t("تصفّح بالتفرّع", "Drill-down")
                    )

                    // أزرار البداية/موقعي/البحث — ثابتة، يفتح البحث في sheet كامل
                    stickyActionsBar
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.xs)

                    if memberVM.allMembers.isEmpty {
                        Spacer()
                        emptyState
                        Spacer()
                    } else if chain.isEmpty {
                        Spacer()
                        ProgressView().tint(DS.Color.primary)
                        Spacer()
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: false) {
                                VStack(spacing: DS.Spacing.md) {
                                    ForEach(Array(chain.enumerated()), id: \.element.id) { idx, member in
                                        let isLast = idx == chain.count - 1

                                        // مربع العضو (مركّز)
                                        ancestorOrActiveSquare(member, atIndex: idx, isActive: isLast)
                                            .id(member.id)

                                        if isLast {
                                            // شبكة أبناء النشط
                                            childrenGridSection(of: member, atSectionIndex: idx)
                                        } else {
                                            chainConnector
                                        }
                                    }
                                }
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.top, DS.Spacing.sm)
                                .padding(.bottom, DS.Spacing.xxxxl)
                            }
                            .onChange(of: scrollTarget) { newId in
                                guard let id = newId else { return }
                                // تأخير بسيط حتى يضمّ ScrollView ID الجديد
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    // تأكد إن الـ ID لا يزال موجود في السلسلة قبل الـ scroll
                                    guard chain.contains(where: { $0.id == id }) else {
                                        scrollTarget = nil
                                        return
                                    }
                                    withAnimation(.easeInOut(duration: 0.45)) {
                                        proxy.scrollTo(id, anchor: .center)
                                    }
                                    // إعادة التعيين على الـ runloop التالي لتفادي تعديل state أثناء view update
                                    DispatchQueue.main.async {
                                        scrollTarget = nil
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { initializeChainIfNeeded() }
            .onChange(of: memberVM.allMembers.count) { _ in initializeChainIfNeeded() }
            .sheet(isPresented: $showingNotifications) {
                NavigationStack { NotificationsCenterView() }
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedMemberForDetails) { m in
                NavigationStack { MemberDetailsView(member: m) }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSearchBar) {
                searchSheet
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Top Bar (Root + Me)

    /// أزرار "البداية" و"موقعي" و"بحث" — ثابتة خارج الـ ScrollView.
    private var stickyActionsBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            // زر البحث — يفتح sheet كامل
            Button {
                showSearchBar = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(DS.Color.accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(DS.Color.accent.opacity(0.12)))
            }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityLabel(L10n.t("بحث", "Search"))

            Button {
                if let first = roots.first {
                    withAnimation(DS.Anim.smooth) { chain = [first] }
                    scrollTarget = first.id
                }
            } label: {
                pillLabel(icon: "house.fill", text: L10n.t("البداية", "Start"), color: DS.Color.primary)
            }
            .buttonStyle(DSScaleButtonStyle())

            Spacer()

            if let me = authVM.currentUser {
                Button { jumpTo(me) } label: {
                    pillLabel(icon: "location.fill", text: L10n.t("موقعي", "Me"), color: DS.Color.success)
                }
                .buttonStyle(DSScaleButtonStyle())
            }
        }
    }

    private func pillLabel(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(DS.Font.scaled(11, weight: .bold))
            Text(text).font(DS.Font.caption1).fontWeight(.bold)
        }
        .foregroundColor(color)
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, 7)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Ancestor / Active Square

    /// المربع المركّز للسلف أو النشط — متطابق الحجم. لمسة بصرية مختلفة للنشط.
    /// **السلوك:** نقرة قصيرة = توسيع/طي (drill أو collapse). ضغطة مطوّلة = عرض التفاصيل.
    private func ancestorOrActiveSquare(_ member: FamilyMember, atIndex idx: Int, isActive: Bool) -> some View {
        let kidsCount = children(of: member.id).count
        return HStack {
            Spacer()
            Button {
                if isActive {
                    // النشط: نقرة = طيّ مستوى واحد (للأعلى). إذا هو الجذر الوحيد → افتح التفاصيل.
                    if chain.count > 1 {
                        collapseLastLevel()
                    } else {
                        selectedMemberForDetails = member
                    }
                } else {
                    // سلف: نقرة تخليه النشط (يقطع السلسلة عند هذا المستوى)
                    makeActive(at: idx)
                }
            } label: {
                memberSquareContent(member, isActive: isActive, kidsCount: kidsCount)
            }
            .buttonStyle(DSScaleButtonStyle())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                    selectedMemberForDetails = member
                }
            )
            .accessibilityHint(L10n.t(
                isActive ? "اضغط لطيّ مستوى — اضغط مطوّلاً للتفاصيل" : "اضغط لتفعيله — اضغط مطوّلاً للتفاصيل",
                isActive ? "Tap to collapse one level. Long-press for details." : "Tap to activate. Long-press for details."
            ))
            Spacer()
        }
    }

    // MARK: - Member Square Content (unified visual)

    private func memberSquareContent(_ member: FamilyMember, isActive: Bool, kidsCount: Int) -> some View {
        let isDeceased = member.isDeceased == true
        let birthY = year(from: member.birthDate)
        let deathY = year(from: member.deathDate)
        let hasDates = birthY != nil || deathY != nil

        return VStack(spacing: 4) {
            // الصورة + علامة المتوفى (نقطة داكنة بأعلى الزاوية)
            ZStack(alignment: .topTrailing) {
                DSMemberAvatar(
                    name: member.firstName,
                    avatarUrl: member.avatarUrl,
                    size: isActive ? 46 : 42,
                    roleColor: member.roleColor
                )
                .overlay(
                    Circle().strokeBorder(
                        deceasedAwareBorderColor(isActive: isActive, isDeceased: isDeceased),
                        lineWidth: isActive ? 2.5 : 1.5
                    )
                )
                .saturation(isDeceased ? 0.55 : 1.0)

                if isDeceased {
                    Image(systemName: "sparkle")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(DS.Color.error))
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.20), radius: 2, x: 0, y: 1)
                        .offset(x: 3, y: -3)
                        .accessibilityLabel(L10n.t("متوفى", "Deceased"))
                }
            }

            Text(member.firstName)
                .font(DS.Font.scaled(12, weight: isActive ? .black : .bold))
                .foregroundColor(isDeceased ? DS.Color.textSecondary : DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // التواريخ — بدون أيقونة
            if hasDates {
                Text(dateRangeText(birthY: birthY, deathY: deathY, isDeceased: isDeceased))
                    .font(DS.Font.scaled(9, weight: .semibold))
                    .foregroundColor(isDeceased ? DS.Color.deceased : DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            // عدّاد الأبناء (دائماً)
            HStack(spacing: 3) {
                Image(systemName: kidsCount > 0 ? "person.2.fill" : "person.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("\(kidsCount)")
                    .font(DS.Font.scaled(9, weight: .bold))
            }
            .foregroundColor(kidsCount > 0 ? DS.Color.primary : DS.Color.textTertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(width: squareSize, height: squareSize)
        .background(squareBackground(isActive: isActive, isDeceased: isDeceased))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(
                    squareBorderColor(isActive: isActive, isDeceased: isDeceased),
                    lineWidth: isActive ? 1.5 : 1
                )
        )
        .shadow(color: .black.opacity(isActive ? 0.07 : 0.03), radius: isActive ? 9 : 4, x: 0, y: 2)
    }

    private func deceasedAwareBorderColor(isActive: Bool, isDeceased: Bool) -> Color {
        if isDeceased {
            return DS.Color.deceased.opacity(isActive ? 0.55 : 0.40)
        }
        return isActive ? DS.Color.primary.opacity(0.45) : DS.Color.primary.opacity(0.18)
    }

    private func squareBackground(isActive: Bool, isDeceased: Bool) -> Color {
        if isActive { return DS.Color.primary.opacity(0.08) }
        if isDeceased { return DS.Color.deceased.opacity(0.06) }
        return DS.Color.surface
    }

    private func squareBorderColor(isActive: Bool, isDeceased: Bool) -> Color {
        if isActive { return DS.Color.primary.opacity(0.40) }
        if isDeceased { return DS.Color.deceased.opacity(0.30) }
        return DS.Color.textTertiary.opacity(0.12)
    }

    private func dateRangeText(birthY: String?, deathY: String?, isDeceased: Bool) -> String {
        // الترتيب: الوفاة (يسار) – الميلاد (يمين)
        switch (birthY, deathY) {
        case let (b?, d?): return "\(d) – \(b)"
        case let (b?, nil): return isDeceased ? "؟ – \(b)" : b
        case let (nil, d?): return "؟ – \(d)"   // وفاة فقط → بالجهة الثانية (يمين)
        case (nil, nil):   return ""
        }
    }

    // MARK: - Children Grid (smart row layout)

    private func childrenGridSection(of member: FamilyMember, atSectionIndex idx: Int) -> some View {
        let kids = children(of: member.id)
        return Group {
            if kids.isEmpty {
                emptyChildrenCard
                    .padding(.top, DS.Spacing.sm)
            } else {
                VStack(spacing: DS.Spacing.sm) {
                    // خط رابط من النشط للشبكة
                    Rectangle()
                        .fill(DS.Color.primary.opacity(0.25))
                        .frame(width: 2, height: 14)

                    ForEach(Array(smartRows(kids).enumerated()), id: \.offset) { _, row in
                        HStack(spacing: DS.Spacing.sm) {
                            ForEach(row) { child in
                                Button {
                                    drillFromSection(at: idx, to: child)
                                } label: {
                                    memberSquareContent(
                                        child,
                                        isActive: false,
                                        kidsCount: children(of: child.id).count
                                    )
                                }
                                .buttonStyle(DSScaleButtonStyle())
                                .simultaneousGesture(
                                    LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                                        selectedMemberForDetails = child
                                    }
                                )
                                .accessibilityHint(L10n.t(
                                    "اضغط للتفرّع — اضغط مطوّلاً للتفاصيل",
                                    "Tap to drill in. Long-press for details."
                                ))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Chain Connector (between ancestor squares)

    private var chainConnector: some View {
        Rectangle()
            .fill(DS.Color.primary.opacity(0.22))
            .frame(width: 2, height: 22)
    }

    // MARK: - Empty States

    private var emptyChildrenCard: some View {
        VStack(spacing: DS.Spacing.xs) {
            Image(systemName: "person.3.sequence")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(DS.Color.textTertiary)
            Text(L10n.t("لا أبناء مسجّلين", "No registered children"))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
        }
        .padding(DS.Spacing.lg)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "tree")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(DS.Color.textTertiary)
            Text(L10n.t("لا يوجد أعضاء", "No members"))
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.textSecondary)
        }
    }

    // MARK: - Navigation

    private func initializeChainIfNeeded() {
        // إعادة التهيئة لو السلسلة فاضية، أو لو جذرها صار غير موجود (data refresh)
        let rootStale = !chain.isEmpty && memberVM.member(byId: chain[0].id) == nil
        if chain.isEmpty || rootStale, let first = roots.first {
            chain = [first]
        }
    }

    /// قطع السلسلة عند سلف معين → يصير هو النشط (تظهر شبكة أبنائه).
    private func makeActive(at index: Int) {
        guard index >= 0, index < chain.count else { return }
        let newChain = Array(chain[0...index])
        guard newChain.count != chain.count else { return }
        let targetId = newChain[index].id   // حفظ قبل تعديل state عشان نتجنّب index بعد التغيير
        withAnimation(.easeInOut(duration: 0.35)) {
            chain = newChain
        }
        scrollTarget = targetId
    }

    /// طيّ مستوى واحد للأعلى — يحذف العضو النشط من نهاية السلسلة.
    private func collapseLastLevel() {
        guard chain.count > 1 else { return }
        let newChain = Array(chain.dropLast())
        let targetId = newChain.last?.id
        withAnimation(.easeInOut(duration: 0.35)) {
            chain = newChain
        }
        scrollTarget = targetId
    }

    /// الضغط على ابن في شبكة النشط → اقطع السلسلة عند هذا المستوى وأضف الابن أسفله.
    private func drillFromSection(at sectionIndex: Int, to child: FamilyMember) {
        guard sectionIndex >= 0, sectionIndex < chain.count else { return }
        let upToIncluding = Array(chain[0...sectionIndex])
        withAnimation(.easeInOut(duration: 0.35)) {
            chain = upToIncluding + [child]
        }
        scrollTarget = child.id
    }

    // MARK: - Search Sheet

    /// شيت البحث الكامل — يحلّ مشكلة قصّ الأسماء في الـ inline overlay.
    private var searchSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TreeSearchOverlay(
                    onSelect: { member in
                        showSearchBar = false
                        // تأخير صغير حتى تنغلق الـ sheet قبل تحريك الشجرة
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            jumpTo(member)
                        }
                    },
                    usesFullHeight: true,
                    autoFocus: true
                )
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.sm)
                Spacer(minLength: 0)
            }
            .background(DS.Color.background.ignoresSafeArea())
            .navigationTitle(L10n.t("بحث في الشجرة", "Search Tree"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("إغلاق", "Close")) {
                        showSearchBar = false
                    }
                    .foregroundColor(DS.Color.primary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// قفز مباشر لأي عضو — بناء السلسلة من الجذر إليه. آمن ضد المراجع الدائرية.
    private func jumpTo(_ member: FamilyMember) {
        var ancestors: [FamilyMember] = []
        var currentId = member.fatherId
        var visited: Set<UUID> = [member.id]
        while let fid = currentId, !visited.contains(fid), let father = memberVM.member(byId: fid) {
            ancestors.append(father)
            visited.insert(fid)
            currentId = father.fatherId
        }
        ancestors.reverse()
        withAnimation(.easeInOut(duration: 0.35)) {
            chain = ancestors + [member]
        }
        scrollTarget = member.id
    }
}
