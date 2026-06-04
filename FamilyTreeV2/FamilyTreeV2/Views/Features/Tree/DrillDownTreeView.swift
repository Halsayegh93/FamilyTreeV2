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

                    // أزرار الإجراءات — تختفي عند فتح البحث (الإغلاق صار داخل مربع البحث)
                    if !showSearchBar {
                        stickyActionsBar
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.top, DS.Spacing.sm)
                            .padding(.bottom, DS.Spacing.xs)
                            .transition(.opacity)
                    }

                    // لوحة البحث تأخذ كل المساحة لما تفتح — الشجرة تختفي
                    if showSearchBar {
                        searchInlinePanel
                            .frame(maxHeight: .infinity)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if memberVM.allMembers.isEmpty {
                        Spacer()
                        emptyState
                        Spacer()
                    } else if chain.isEmpty {
                        Spacer()
                        ProgressView().tint(DS.Color.primary)
                        Spacer()
                    } else if kinshipBanner != nil {
                        // وضع القرابة: السلسلة عموديًا — نفس ستايل الشجرة
                        verticalKinshipChain
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: false) {
                                VStack(spacing: DS.Spacing.xs) {
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
                                // تأخير أكبر شوية حتى يُرسَم محتوى الأبناء قبل التمرير
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    // تأكد إن الـ ID لا يزال موجود في السلسلة قبل الـ scroll
                                    guard chain.contains(where: { $0.id == id }) else {
                                        scrollTarget = nil
                                        return
                                    }
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        // anchor قريب من الأعلى عشان شبكة الأبناء تبيّن تحته
                                        proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.15))
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
            .overlay(alignment: .top) {
                if let banner = kinshipBanner {
                    kinshipBannerView(text: banner)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { initializeChainIfNeeded() }
            .onChange(of: memberVM.allMembers.count) { _ in initializeChainIfNeeded() }
            .onReceive(NotificationCenter.default.publisher(for: .showKinshipPath)) { note in
                handleKinshipNotification(note)
            }
            .sheet(isPresented: $showingNotifications) {
                NavigationStack { NotificationsCenterView() }
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedMemberForDetails) { m in
                NavigationStack { MemberDetailsView(member: m) }
                    .presentationDetents([.medium, .large])
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
            selectedMemberForDetails = member
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
                selectedMemberForDetails = member
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
              let target = memberVM.member(byId: memberId),
              let meId = authVM.currentUser?.id,
              let me = memberVM.member(byId: meId) else { return }

        let lookup = memberVM._memberById
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
                current = c.fatherId.flatMap { memberVM.member(byId: $0) }
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
               memberVM.member(byId: saved[0].id) != nil {
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
                iconButton(icon: "arrow.up.to.line", color: DS.Color.primary)
            }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityLabel(L10n.t("البداية", "Start"))

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
            .font(DS.Font.scaled(19, weight: .bold))
            .foregroundColor(color)
            .frame(width: 44, height: 44)
            .background(Circle().fill(color.opacity(0.12)))
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

        return VStack(spacing: 2) {
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
        .padding(.vertical, 5)
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
        let rows = smartRows(kids)
        return Group {
            if kids.isEmpty {
                emptyChildrenCard
                    .padding(.top, DS.Spacing.sm)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        // فروع فقط للصف الأول (أول 3 أبناء كحد أقصى) — البقية بلا فروع
                        if rowIndex == 0 {
                            BranchConnector(
                                branchCount: min(3, row.count),
                                style: drillBranchStyle
                            )
                            .stroke(
                                DS.Color.primary.opacity(0.55),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                            )
                            .frame(height: 22)
                        }

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
