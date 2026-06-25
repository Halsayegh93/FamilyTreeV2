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
    /// بيانات مُحقونة (تبويب التفرّع — جدول منفصل). عند nil نستخدم memberVM.
    var injectedMembers: [FamilyMember]? = nil
    /// عند الضغط على عضو: يُستدعى بدل فتح MemberDetailsView (لبيانات منفصلة).
    var onOpenDetails: ((FamilyMember) -> Void)? = nil
    /// مُضمّن داخل شاشة أخرى (تبويب التفرّع) — نخفي الهيدر وشريط الأدوات الخاص.
    var embedded: Bool = false
    /// تخصيص الهيدر (لمطابقة شجرة العائلة في تبويب التفرّع).
    var headerTitle: String? = nil
    var headerSubtitle: String? = nil
    var headerIcon: String? = nil
    /// تبويبات [شجرة العائلة | التفرّع] داخل شريط الأدوات.
    var treeTab: Binding<Int>? = nil

    // مصدر البيانات الموحّد — مُحقون أو memberVM.
    private var allData: [FamilyMember] { injectedMembers ?? memberVM.allMembers }
    private func lookupMember(_ id: UUID) -> FamilyMember? {
        if let injectedMembers { return injectedMembers.first { $0.id == id } }
        return memberVM.member(byId: id)
    }
    private func openDetails(_ m: FamilyMember) {
        if let onOpenDetails { onOpenDetails(m) } else { selectedMemberForDetails = m }
    }
    // الصورة مرتبطة حيّة بالأصل (نفس id في profiles) — تتغيّر بتغيّرها في الشجرة.
    private func displayAvatar(for m: FamilyMember) -> String? {
        if injectedMembers != nil, let fam = memberVM.member(byId: m.id) {
            return fam.displayAvatarUrl
        }
        return m.displayAvatarUrl
    }

    /// السلسلة الكاملة: الجذر → الأقرب. آخر عضو = النشط.
    @State private var chain: [FamilyMember] = []
    @State private var selectedMemberForDetails: FamilyMember? = nil
    @State private var showingNotifications = false
    @State private var showSearchBar = false
    @State private var scrollTarget: UUID? = nil
    /// الفرع المختار في البحث — يبقى ثابتاً طول ما شجرة التفرّع ظاهرة (يُصفَّر عند
    /// الخروج من الشاشة أو إغلاق التطبيق)، حتى لو أُعيد فتح لوحة البحث.
    @State private var searchBranchRootId: UUID? = nil

    // صلة القرابة — البانر + المعرّفات المهايلايتة + الطرفين
    @State private var kinshipBanner: String? = nil
    @State private var kinshipPathIds: Set<UUID> = []
    @State private var kinshipTargetId: UUID? = nil
    @State private var kinshipMeId: UUID? = nil
    @State private var kinshipCommonAncestorId: UUID? = nil
    @State private var kinshipDismissTask: Task<Void, Never>? = nil
    // لقطة سلسلة الشجرة قبل تفعيل القرابة — للرجوع لنفس المكان عند الانتهاء
    @State private var preKinshipChain: [FamilyMember]? = nil

    // نمط فروع الخطوط (قوس/زاوية) — يبقى عبر التشغيل
    @AppStorage("drillBranchStyle") private var drillBranchStyleRaw: String = BranchConnectorStyle.arc.rawValue
    private var drillBranchStyle: BranchConnectorStyle {
        BranchConnectorStyle(rawValue: drillBranchStyleRaw) ?? .arc
    }

    /// الحجم الموحّد لمربع العضو.
    private let squareSize: CGFloat = 110

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
        let visible = allData.filter(\.isCountable)
        let byId = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        let fatherIds = Set(visible.compactMap(\.fatherId))
        return visible.filter { m in
            guard let fid = m.fatherId else { return fatherIds.contains(m.id) }
            return byId[fid] == nil
        }.sortedForDisplay()
    }

    private func children(of memberId: UUID) -> [FamilyMember] {
        allData
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
                    if !embedded {
                        MainHeaderView(
                            selectedTab: $selectedTab,
                            showingNotifications: $showingNotifications,
                            title: headerTitle ?? L10n.t("الشجرة", "Family Tree"),
                            subtitle: headerSubtitle ?? L10n.t("تصفّح بالتفرّع", "Drill-down"),
                            icon: headerIcon
                        )
                    }

                    // المحتوى + البار العائم الشفاف فوقه (الشجرة تبين خلفه)
                    ZStack(alignment: .top) {
                        Group {
                            if showSearchBar {
                                searchInlinePanel
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .transition(.opacity)
                            } else if allData.isEmpty {
                                emptyState
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if chain.isEmpty {
                                ProgressView().tint(DS.Color.primary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if kinshipBanner != nil {
                                verticalKinshipChain
                            } else {
                                ScrollViewReader { proxy in
                                    ScrollView(showsIndicators: false) {
                                        VStack(spacing: DS.Spacing.xs) {
                                            ForEach(Array(chain.enumerated()), id: \.element.id) { idx, member in
                                                let isLast = idx == chain.count - 1
                                                ancestorOrActiveSquare(member, atIndex: idx, isActive: isLast)
                                                    .id(member.id)
                                                if isLast {
                                                    childrenGridSection(of: member, atSectionIndex: idx)
                                                } else {
                                                    chainConnector
                                                }
                                            }
                                        }
                                        .padding(.horizontal, DS.Spacing.lg)
                                        .padding(.top, 60)   // يكشف الشجرة تحت البار العائم
                                        .padding(.bottom, DS.Spacing.xxxxl)
                                    }
                                    .onChange(of: scrollTarget) { newId in
                                        guard let id = newId else { return }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                            guard chain.contains(where: { $0.id == id }) else {
                                                scrollTarget = nil
                                                return
                                            }
                                            withAnimation(.easeInOut(duration: 0.5)) {
                                                proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.15))
                                            }
                                            DispatchQueue.main.async { scrollTarget = nil }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // البار العائم — شفاف، الشجرة تبين خلفه
                        if !showSearchBar {
                            stickyActionsBar
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.top, DS.Spacing.sm)
                                .padding(.bottom, DS.Spacing.xs)
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if let banner = kinshipBanner {
                    kinshipBannerView(text: banner)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { initializeChainIfNeeded() }
            .onChange(of: allData.count) { _ in initializeChainIfNeeded() }
            .onReceive(NotificationCenter.default.publisher(for: .showKinshipPath)) { note in
                handleKinshipNotification(note)
            }
            .sheet(isPresented: $showingNotifications) {
                NavigationStack { NotificationsCenterView() }
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedMemberForDetails) { m in
                NavigationStack { MemberDetailsView(member: m) }
                    .presentationDetents([.fraction(0.42), .large])
                    .presentationDragIndicator(.visible)
            }
            .animation(DS.Anim.smooth, value: showSearchBar)
            .animation(DS.Anim.snappy, value: kinshipBanner)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Kinship Vertical Chain

    /// مربّع عضو في وضع القرابة — نفس مربّع الشجرة، النقر يفتح التفاصيل.
    private func kinshipSquareButton(_ member: FamilyMember) -> some View {
        Button {
            openDetails(member)
        } label: {
            memberSquareContent(
                member,
                isActive: kinshipTargetId == member.id,
                kidsCount: children(of: member.id).count
            )
        }
        .buttonStyle(DSScaleButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                openDetails(member)
            }
        )
        .id(member.id)
    }

    /// عمود عمودي لفرع واحد من فروع القرابة (من تحت الجد المشترك للطرف).
    private func kinshipBranchColumn(_ members: [FamilyMember]) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            ForEach(Array(members.enumerated()), id: \.element.id) { idx, m in
                kinshipSquareButton(m)
                if idx != members.count - 1 {
                    chainConnector
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// عرض سلسلة القرابة عموديًا — نفس مربعات ووصلات الشجرة العادية.
    /// عند وجود جدّ مشترك: يتفرّع عنده لفرعين (أنت / الهدف) تمامًا مثل تفرّع الشجرة.
    private var verticalKinshipChain: some View {
        let caIndex = kinshipCommonAncestorId.flatMap { caid in
            chain.firstIndex(where: { $0.id == caid })
        }
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                Group {
                    if let caIndex, caIndex > 0, caIndex < chain.count - 1 {
                        // تفرّع حقيقي عند الجد المشترك
                        let ca = chain[caIndex]
                        let meBranch = Array(chain[0..<caIndex].reversed())   // ابن الجد ← ... ← أنت
                        let targetBranch = Array(chain[(caIndex + 1)...])     // ابن الجد ← ... ← الهدف
                        VStack(spacing: DS.Spacing.xs) {
                            HStack { Spacer(); kinshipSquareButton(ca); Spacer() }

                            // فرع على شكل الشجرة (قوس/زاوية حسب الإعداد)
                            BranchConnector(branchCount: 2, style: drillBranchStyle)
                                .stroke(
                                    DS.Color.warning.opacity(0.85),
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                                )
                                .frame(height: 22)

                            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                                kinshipBranchColumn(meBranch)
                                kinshipBranchColumn(targetBranch)
                            }
                        }
                    } else {
                        // fallback: سلسلة عمودية بسيطة (لا يوجد جد مشترك أو طرف هو الجد)
                        VStack(spacing: DS.Spacing.xs) {
                            ForEach(Array(chain.enumerated()), id: \.element.id) { idx, member in
                                kinshipSquareButton(member)
                                if idx != chain.count - 1 {
                                    chainConnector
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.xxxxl)
            }
            .onChange(of: scrollTarget) { newId in
                guard let id = newId else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard chain.contains(where: { $0.id == id }) else {
                        scrollTarget = nil
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.5)) {
                        proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.3))
                    }
                    DispatchQueue.main.async { scrollTarget = nil }
                }
            }
        }
    }

    // MARK: - Kinship Banner + Handler

    private func kinshipBannerView(text: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "person.2.fill")
                .font(DS.Font.scaled(15, weight: .bold))
            Text(text)
                .font(DS.Font.calloutBold)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: DS.Spacing.sm)
            Button {
                clearKinship()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.Font.scaled(18))
                    .foregroundColor(DS.Color.textOnPrimary.opacity(0.7))
            }
        }
        .foregroundColor(DS.Color.textOnPrimary)
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(DS.Color.gradientPrimary)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .padding(.horizontal, DS.Spacing.lg)
        .shadow(color: DS.Color.primary.opacity(0.3), radius: 8, y: 4)
    }

    /// يستقبل إشعار `.showKinshipPath` ويبني سلسلة ثنائية الاتجاه:
    /// **أنت → ... → الجد المشترك → ... → الهدف**
    /// — كل أعضاء مسار القرابة يظهرون في سلسلة خطّية واحدة، الطرفان مميّزان.
    private func handleKinshipNotification(_ note: Notification) {
        guard let info = note.userInfo,
              let memberId = info["memberId"] as? UUID,
              let relationship = info["relationship"] as? String,
              let target = lookupMember(memberId),
              let meId = authVM.currentUser?.id,
              let me = lookupMember(meId) else { return }

        let lookup = injectedMembers != nil
            ? Dictionary(allData.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            : memberVM._memberById
        let result = KinshipCalculator.calculate(from: me, to: target, lookup: lookup)

        // pathA = [me, ..., common_ancestor]
        // pathB = [target, ..., common_ancestor]
        // نُركّب سلسلة خطّية: pathA + (pathB بدون الجد المشترك، معكوس)
        // → [me, ..., CA, ..., target]
        let newChain: [FamilyMember]
        if result.commonAncestor != nil, !result.pathB.isEmpty {
            newChain = result.pathA + Array(result.pathB.dropLast().reversed())
        } else {
            // لا يوجد جد مشترك — fallback لمسار الهدف فقط من الجذر
            var ancestors: [FamilyMember] = []
            var current: FamilyMember? = target
            while let c = current {
                ancestors.append(c)
                current = c.fatherId.flatMap { lookupMember($0) }
            }
            newChain = Array(ancestors.reversed())
        }

        guard !newChain.isEmpty else { return }

        // مجموعة معرّفات للهايلايت — كل أعضاء السلسلة + pathIds من الإشعار
        var pathSet: Set<UUID> = Set(newChain.map(\.id))
        if let ids = info["pathIds"] as? [UUID] {
            pathSet.formUnion(ids)
        }

        kinshipDismissTask?.cancel()

        // احفظ مكان الشجرة الحالي مرة واحدة فقط (لو القرابة مو مفعّلة أصلاً)
        if kinshipBanner == nil {
            preKinshipChain = chain
        }

        withAnimation(.easeInOut(duration: 0.4)) {
            chain = newChain
            kinshipBanner = relationship
            kinshipPathIds = pathSet
            kinshipTargetId = memberId
            kinshipMeId = meId
            kinshipCommonAncestorId = result.commonAncestor?.id
        }

        // التمرير للجد المشترك ليبيّن نقطة الوصل بين الطرفين
        scrollTarget = result.commonAncestor?.id ?? target.id

        // إخفاء البانر والهايلايت بعد 20 ثانية
        kinshipDismissTask = Task {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { clearKinship() }
        }
    }

    private func clearKinship() {
        kinshipDismissTask?.cancel()
        withAnimation(DS.Anim.snappy) {
            kinshipBanner = nil
            kinshipPathIds = []
            kinshipTargetId = nil
            kinshipMeId = nil
            kinshipCommonAncestorId = nil
            // الرجوع لنفس مكان الشجرة الذي ضُغطت منه القرابة (أو البداية كحل احتياطي)
            if let saved = preKinshipChain, !saved.isEmpty,
               lookupMember(saved[0].id) != nil {
                chain = saved
            } else if let first = roots.first {
                chain = [first]
            }
        }
        preKinshipChain = nil
    }

    // MARK: - Top Bar (Root + Me)

    /// أزرار "بحث" و"البداية" و"موقعي" — أيقونات فقط (بدون نص) بتصميم موحّد.
    /// تظهر فقط عند إغلاق البحث؛ زر إغلاق البحث صار داخل مربع البحث نفسه.
    private var stickyActionsBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button {
                withAnimation(DS.Anim.smooth) { showSearchBar = true }
            } label: {
                iconButton(icon: "magnifyingglass", color: DS.Color.primary)
            }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityLabel(L10n.t("بحث", "Search"))

            Button {
                if let first = roots.first {
                    withAnimation(DS.Anim.smooth) { chain = [first] }
                    scrollTarget = first.id
                }
            } label: {
                iconButton(icon: "house.fill", color: DS.Color.primary)
            }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityLabel(L10n.t("البداية", "Start"))

            Spacer()

            // التبويبات بالمنتصف (نفس توزيع شجرة العائلة)
            if let treeTab {
                FamilyTreeTabBar(selection: treeTab)
            }

            Spacer()

            if let me = authVM.currentUser {
                Button { jumpTo(me) } label: {
                    iconButton(icon: "location.fill", color: DS.Color.primary)
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("موقعي", "Me"))
            }
        }
    }

    /// زر دائري بأيقونة فقط (بدون نص) — أيقونة أكبر ضمن خلفية ملوّنة خفيفة.
    private func iconButton(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(DS.Font.scaled(16, weight: .bold))
            .foregroundColor(color)
            .frame(width: 40, height: 40)
            .background(Circle().fill(color.opacity(0.12)))
    }

    // MARK: - Ancestor / Active Square

    /// المربع المركّز للسلف أو النشط — متطابق الحجم. لمسة بصرية مختلفة للنشط.
    /// **السلوك:** نقرة قصيرة = توسيع/طي (drill أو collapse). ضغطة مطوّلة = عرض التفاصيل.
    private func ancestorOrActiveSquare(_ member: FamilyMember, atIndex idx: Int, isActive: Bool) -> some View {
        let kidsCount = children(of: member.id).count
        return HStack(spacing: DS.Spacing.xs) {
            Spacer()
            Button {
                if isActive {
                    // النشط: نقرة = طيّ مستوى واحد (للأعلى). إذا هو الجذر الوحيد → افتح التفاصيل.
                    if chain.count > 1 {
                        collapseLastLevel()
                    } else {
                        openDetails(member)
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
                    openDetails(member)
                }
            )
            .accessibilityHint(L10n.t(
                isActive ? "اضغط لطيّ مستوى — اضغط مطوّلاً للتفاصيل" : "اضغط لتفعيله — اضغط مطوّلاً للتفاصيل",
                isActive ? "Tap to collapse one level. Long-press for details." : "Tap to activate. Long-press for details."
            ))

            // زوجات الأب — جنبه على اليسار، مكدّسة عمودياً عند التعدّد.
            if isActive {
                let wives = allData.filter { $0.husbandId == member.id && $0.isFemale }
                if !wives.isEmpty {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(wives) { wife in
                            Button { openDetails(wife) } label: { wifeBesideCard(wife) }
                                .buttonStyle(DSScaleButtonStyle())
                        }
                    }
                }
            }
            Spacer()
        }
    }

    // شارة "متوفى" نصية موحّدة (بدل النجمة/الورقة) — بنفس حجم الشارة السابقة.
    private var deceasedBadge: some View {
        Text(L10n.t("متوفى", "Deceased"))
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(DS.Color.error))
            .overlay(Capsule().strokeBorder(Color.white, lineWidth: 1))
            .shadow(color: .black.opacity(0.20), radius: 2, x: 0, y: 1)
            .accessibilityLabel(L10n.t("متوفى", "Deceased"))
    }

    // بطاقة زوجة مُصغّرة بجانب الأب — بدون صورة، الاسم فقط.
    private func wifeBesideCard(_ wife: FamilyMember) -> some View {
        VStack(spacing: 3) {
            Text(L10n.t("زوجة", "Wife"))
                .font(DS.Font.caption2).fontWeight(.bold)
                .foregroundColor(FemaleAvatarView.wifeIcon)
            Text(wife.fullName.isEmpty ? wife.firstName : wife.fullName)
                .font(DS.Font.caption1).fontWeight(.semibold)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(3).multilineTextAlignment(.center).minimumScaleFactor(0.6)
            if wife.isDeceased ?? false {
                deceasedBadge
            }
        }
        .frame(width: 104)
        .padding(.vertical, DS.Spacing.sm)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(FemaleAvatarView.wifeIcon.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(FemaleAvatarView.wifeIcon.opacity(0.3), lineWidth: 1))
        )
    }

    // MARK: - Member Square Content (unified visual)

    private func memberSquareContent(_ member: FamilyMember, isActive: Bool, kidsCount: Int) -> some View {
        let isDeceased = member.isDeceased == true
        let birthY = year(from: member.birthDate)
        let deathY = year(from: member.deathDate)
        let hasDates = birthY != nil || deathY != nil
        // لون المربع حسب الجنس: ذكر أزرق، أنثى بنفسجي.
        let genderAccent: Color = member.isFemale ? FemaleAvatarView.wifeIcon : DS.Color.primary

        // الاسم + التواريخ + العدّاد (تُعرض جنب الصورة للذكور، وحدها للإناث).
        let infoBlock = VStack(alignment: member.isFemale ? .center : .leading, spacing: 2) {
            Text(member.firstName)
                .font(DS.Font.scaled(12, weight: isActive ? .black : .bold))
                .foregroundColor(isDeceased ? DS.Color.textSecondary : DS.Color.textPrimary)
                .lineLimit(member.isFemale ? 2 : 2)
                .multilineTextAlignment(member.isFemale ? .center : .leading)
                .minimumScaleFactor(0.7)

            // التواريخ + عدّاد الأبناء — للذكور فقط (الإناث مربّع مُصغّر بالاسم).
            if !member.isFemale {
                if hasDates {
                    Text(dateRangeText(birthY: birthY, deathY: deathY, isDeceased: isDeceased))
                        .font(DS.Font.scaled(9, weight: .semibold))
                        .foregroundColor(isDeceased ? DS.Color.deceased : DS.Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                HStack(spacing: 3) {
                    Image(systemName: kidsCount > 0 ? "person.2.fill" : "person.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(kidsCount)")
                        .font(DS.Font.scaled(9, weight: .bold))
                }
                .foregroundColor(kidsCount > 0 ? DS.Color.primary : DS.Color.textTertiary)
            }
        }

        // صورة الذكر + علامة المتوفى.
        let maleAvatar = ZStack(alignment: .topTrailing) {
            DSMemberAvatar(
                name: member.firstName,
                avatarUrl: displayAvatar(for: member),
                size: isActive ? 44 : 38,
                roleColor: genderAccent,
                isFemale: false
            )
            .overlay(
                Circle().strokeBorder(
                    deceasedAwareBorderColor(isActive: isActive, isDeceased: isDeceased),
                    lineWidth: isActive ? 2.5 : 1.5
                )
            )
            .saturation(isDeceased ? 0.55 : 1.0)

            if isDeceased {
                deceasedBadge
                    .offset(x: 10, y: -6)
            }
        }

        return Group {
            if member.isFemale {
                // الإناث: بدون صورة — الاسم فقط (مع علامة وفاة صغيرة عند اللزوم).
                VStack(spacing: 2) {
                    if isDeceased { deceasedBadge }
                    infoBlock
                }
            } else {
                // الذكور: الصورة جنب المعلومات (أفقي) بدل فوقها.
                HStack(spacing: 6) {
                    maleAvatar
                    infoBlock
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, member.isFemale ? 5 : 6)
        .padding(.horizontal, member.isFemale ? 6 : 8)
        .frame(width: squareSize,
               height: member.isFemale ? 52 : 64,
               alignment: member.isFemale ? .center : .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .fill(isDeceased ? DS.Color.surface : genderAccent.opacity(isActive ? 0.14 : 0.07))
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(
                    isDeceased ? DS.Color.deceased.opacity(0.4) : genderAccent.opacity(isActive ? 0.6 : 0.35),
                    lineWidth: isActive ? 1.5 : 1
                )
        )
        .shadow(color: .black.opacity(isActive ? 0.07 : 0.03), radius: isActive ? 9 : 4, x: 0, y: 2)
        // سهم خفيف جداً يوضح أن عند العضو أبناء — داخل المربع من الأسفل
        .overlay(alignment: .bottom) {
            if kidsCount > 0 {
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(DS.Color.primary.opacity(0.45))
                    .padding(.bottom, 3)
                    .allowsHitTesting(false)
            }
        }
        // تمييز ذهبي لأعضاء مسار القرابة + نجمة للمستهدف
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(
                    kinshipPathIds.contains(member.id) ? DS.Color.warning : Color.clear,
                    lineWidth: 2.5
                )
        )
        .shadow(
            color: kinshipPathIds.contains(member.id) ? DS.Color.warning.opacity(0.45) : .clear,
            radius: 10, x: 0, y: 0
        )
        .overlay(alignment: .topLeading) {
            if kinshipTargetId == member.id {
                // الهدف — نجمة ذهبية
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(5)
                    .background(Circle().fill(DS.Color.warning))
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                    .shadow(color: DS.Color.warning.opacity(0.5), radius: 3, x: 0, y: 1)
                    .offset(x: -3, y: -3)
                    .allowsHitTesting(false)
            } else if kinshipMeId == member.id {
                // أنا — شخص أخضر
                Image(systemName: "person.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(5)
                    .background(Circle().fill(DS.Color.success))
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                    .shadow(color: DS.Color.success.opacity(0.5), radius: 3, x: 0, y: 1)
                    .offset(x: -3, y: -3)
                    .allowsHitTesting(false)
            } else if kinshipCommonAncestorId == member.id {
                // الجد المشترك — تاج
                Image(systemName: "crown.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(5)
                    .background(Circle().fill(DS.Color.accent))
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                    .shadow(color: DS.Color.accent.opacity(0.5), radius: 3, x: 0, y: 1)
                    .offset(x: -3, y: -3)
                    .allowsHitTesting(false)
            }
        }
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
        // الذكور يمين، الإناث يسار — كل عمود عمودي (تحت بعض).
        let males = kids.filter { !$0.isFemale }
        let females = kids.filter { $0.isFemale }
        return Group {
            if kids.isEmpty {
                emptyChildrenCard
                    .padding(.top, DS.Spacing.sm)
            } else if females.isEmpty {
                // لا يوجد إناث — الأبناء جنب بعض (أفقي).
                horizontalChildren(kids, sectionIndex: idx)
                    .padding(.top, DS.Spacing.sm)
            } else {
                HStack(alignment: .top, spacing: DS.Spacing.xs) {
                    // في RTL: أول عمود = اليمين → الذكور.
                    genderColumn(color: DS.Color.primary,
                                 kids: males, sectionIndex: idx)
                    genderColumn(color: FemaleAvatarView.wifeIcon,
                                 kids: females, sectionIndex: idx)
                }
                .padding(.top, DS.Spacing.sm)
            }
        }
    }

    // الأبناء جنب بعض (3 لكل صف) — عند عدم وجود إناث.
    @ViewBuilder
    private func horizontalChildren(_ kids: [FamilyMember], sectionIndex idx: Int) -> some View {
        let rows = smartRows(kids)
        VStack(spacing: DS.Spacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(row) { child in
                        Button {
                            drillFromSection(at: idx, to: child)
                        } label: {
                            memberSquareContent(
                                child, isActive: false,
                                kidsCount: children(of: child.id).count
                            )
                        }
                        .buttonStyle(DSScaleButtonStyle())
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                                openDetails(child)
                            }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func genderColumn(color: Color, kids: [FamilyMember], sectionIndex idx: Int) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            if kids.isEmpty {
                Text("—").font(DS.Font.caption1).foregroundColor(DS.Color.textTertiary)
            } else {
                ForEach(kids) { child in
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
                            openDetails(child)
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Chain Connector (between ancestor squares)

    private var chainConnector: some View {
        Rectangle()
            .fill(
                kinshipPathIds.isEmpty
                    ? DS.Color.primary.opacity(0.22)
                    : DS.Color.warning.opacity(0.85)
            )
            .frame(width: kinshipPathIds.isEmpty ? 2 : 3, height: 14)
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
        let rootStale = !chain.isEmpty && lookupMember(chain[0].id) == nil
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

    // MARK: - Search Inline Panel

    /// لوحة البحث inline — تأخذ كامل المساحة بين stickyActionsBar وأسفل الشاشة.
    /// تظهر بدل ScrollView الشجرة عند `showSearchBar = true`.
    private var searchInlinePanel: some View {
        TreeSearchOverlay(
            onSelect: { member in
                withAnimation(DS.Anim.smooth) { showSearchBar = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    jumpTo(member)
                }
            },
            usesFullHeight: true,
            autoFocus: true,
            onClose: {
                withAnimation(DS.Anim.smooth) { showSearchBar = false }
            },
            externalBranchRootId: $searchBranchRootId
        )
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.xs)
        .padding(.bottom, DS.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// قفز مباشر لأي عضو — بناء السلسلة من الجذر إليه. آمن ضد المراجع الدائرية.
    private func jumpTo(_ member: FamilyMember) {
        var ancestors: [FamilyMember] = []
        var currentId = member.fatherId
        var visited: Set<UUID> = [member.id]
        while let fid = currentId, !visited.contains(fid), let father = lookupMember(fid) {
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
