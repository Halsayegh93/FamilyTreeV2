import SwiftUI

/// شجرة النساء (women_members) — عرض فقط لكل الأعضاء.
/// تعيد استخدام محرّك DrillDownTreeView ببيانات محقونة (النساء كعُقد).
struct WomenTreeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Binding var selectedTab: Int
    /// تبويب الشجرة [0=عائلة، 1=نساء] — لعرض شريط التبويب العلوي.
    var treeTab: Binding<Int>? = nil

    // تبدأ من الكاش (إن وُجد) — انتقال فوري بلا شاشة تحميل في المرات التالية.
    @State private var allMembers: [FamilyMember] = WomenStore.cache
    @State private var isLoading = WomenStore.cache.isEmpty
    @State private var selectedWoman: FamilyMember? = nil
    @State private var showingNotifications = false

    var body: some View {
        Group {
            if isLoading {
                WomenLoadingView()
            } else if allMembers.isEmpty {
                ZStack {
                    DS.Color.background.ignoresSafeArea()
                    VStack(spacing: DS.Spacing.md) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 44))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا توجد بيانات للنساء بعد", "No women data yet"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    MainHeaderView(
                        selectedTab: $selectedTab,
                        showingNotifications: $showingNotifications,
                        title: L10n.t("النساء", "Women"),
                        subtitle: "\(allMembers.count) " + L10n.t("فرد", "members"),
                        icon: "leaf.fill",
                        backgroundGradient: DS.Color.gradientPrimary
                    )
                    WomenClassicTreeView(
                        members: allMembers,
                        onSelect: { selectedWoman = $0 },
                        treeTab: treeTab,
                        meWomanId: resolveMyWomanId()
                    )
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await load() }
        .sheet(item: $selectedWoman) { w in
            WomanDetailSheet(
                woman: w,
                allWomen: allMembers,
                me: authVM.currentUser,
                canEdit: authVM.canEditMembers,
                onChanged: { await reloadWomen() },
                onOpenMember: { id in
                    // أغلق الشيت الحالي ثم افتح بروفايل الزوجة بعد التحميل الجديد
                    selectedWoman = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        selectedWoman = allMembers.first { $0.id == id }
                    }
                }
            )
        }
    }

    private func load() async {
        do {
            let rows = try await WomenStore.fetch()
            allMembers = rows
            isLoading = false
        } catch {
            isLoading = false
        }
    }

    /// إعادة تحميل بعد تعديل/إضافة/حذف من شيت التفاصيل.
    private func reloadWomen() async {
        if let rows = try? await WomenStore.fetch() { allMembers = rows }
    }

    /// عقدة المستخدم في شجرة النساء — تلقائيًا: أولًا بالربط، وإلا بمطابقة الاسم الكامل.
    private func resolveMyWomanId() -> UUID? {
        guard let me = authVM.currentUser else { return nil }
        if let linked = WomenStore.womanByLinkedUser[me.id] { return linked }
        let target = normalizeName(me.fullName)
        guard !target.isEmpty else { return nil }
        // مطابقة تامّة، وإلا تطابق أول ٣ كلمات (الاسم + الأب + الجد).
        if let exact = allMembers.first(where: { normalizeName($0.fullName) == target }) { return exact.id }
        let key = firstWords(target, 3)
        guard !key.isEmpty else { return nil }
        return allMembers.first(where: { firstWords(normalizeName($0.fullName), 3) == key })?.id
    }
    private func normalizeName(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }
    private func firstWords(_ s: String, _ n: Int) -> String {
        s.split(separator: " ").prefix(n).joined(separator: " ")
    }
}

/// شاشة تحميل شجرة النساء — أيقونة نابضة + عُقد وهمية (skeleton) عند التحوّل.
private struct WomenLoadingView: View {
    @State private var pulse = false
    private let rose = Color(hex: "#C07A8C")

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            VStack(spacing: DS.Spacing.xl) {
                // أيقونة نابضة داخل هالة
                ZStack {
                    Circle().fill(rose.opacity(0.15))
                        .frame(width: 110, height: 110)
                        .scaleEffect(pulse ? 1.15 : 0.85)
                        .opacity(pulse ? 0.3 : 0.7)
                    Circle().fill(DS.Color.gradientPrimary)
                        .frame(width: 76, height: 76)
                        .overlay(Image(systemName: "person.2.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(.white))
                        .dsGlowShadow()
                }

                VStack(spacing: DS.Spacing.xs) {
                    Text(L10n.t("جارٍ تحميل شجرة النساء", "Loading the women tree"))
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(L10n.t("لحظات من فضلك…", "Just a moment…"))
                        .font(DS.Font.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                }

                // نقاط متحرّكة
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(DS.Color.primary)
                            .frame(width: 9, height: 9)
                            .scaleEffect(pulse ? 1.0 : 0.5)
                            .opacity(pulse ? 1 : 0.4)
                            .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.18), value: pulse)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// شيت تفاصيل امرأة — مطابق لشيت تفاصيل العائلة:
/// عند الفتح (متوسط): صورة + اسم + صلة القرابة + العمر فقط.
/// عند التوسيع (كبير): المعلومات الأساسية + العائلة (الزوج/الأم/الأبناء).
private struct WomanDetailSheet: View {
    let woman: FamilyMember
    let allWomen: [FamilyMember]
    /// المستخدم الحالي — لحساب صلة القرابة.
    let me: FamilyMember?
    /// صلاحية التعديل (إدارة).
    var canEdit: Bool = false
    /// يُستدعى بعد أي إضافة/تعديل/حذف لإعادة تحميل الشجرة.
    var onChanged: (() async -> Void)? = nil
    /// يفتح تفاصيل عضو آخر (مثلاً بروفايل الزوجة بعد ربطها من العائلة).
    var onOpenMember: ((UUID) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    /// حجم الشيت: متوسط = صورة+اسم+قرابة+عمر فقط، كبير = كل المعلومات.
    @State private var detent: PresentationDetent = .fraction(0.46)
    /// نتيجة صلة القرابة داخل الشيت (بانر).
    @State private var kinshipText: String? = nil

    // إدارة (إضافة/تعديل/حذف)
    @State private var addKind: AddKind? = nil
    @State private var addName = ""
    @State private var showEditName = false
    @State private var editName = ""
    @State private var showDelete = false
    @State private var busy = false
    @State private var showReorder = false
    @State private var showMotherPicker = false
    @State private var showWifeSource = false
    @State private var showWifeNav = false
    @State private var showWifePicker = false
    @State private var showHusbandPicker = false
    @State private var showChildGender = false
    @State private var wifeSearch = ""
    @State private var childrenExpanded = false
    @State private var orderedChildren: [FamilyMember] = []

    enum AddKind: Int, Identifiable {
        case son, daughter, wife, mother
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .son: return L10n.t("إضافة ابن", "Add son")
            case .daughter: return L10n.t("إضافة بنت", "Add daughter")
            case .wife: return L10n.t("إضافة زوجة", "Add wife")
            case .mother: return L10n.t("إضافة أم", "Add mother")
            }
        }
    }

    private var husband: FamilyMember? {
        guard let hid = woman.husbandId else { return nil }
        return allWomen.first { $0.id == hid }
    }
    /// زوجات العضو الذكر (husband_id == العضو).
    private var wives: [FamilyMember] {
        allWomen.filter { $0.husbandId == woman.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    private var mother: FamilyMember? {
        guard let mid = woman.motherId else { return nil }
        return allWomen.first { $0.id == mid }
    }
    private var father: FamilyMember? {
        guard let fid = woman.fatherId else { return nil }
        return allWomen.first { $0.id == fid }
    }
    /// زوجات والد العضو — الأمهات المحتملات لاختيار أمّ العضو منهنّ.
    private var fatherWives: [FamilyMember] {
        guard let fid = woman.fatherId else { return [] }
        return allWomen.filter { $0.husbandId == fid }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    /// الأبناء (بلا الزوجات) — مرتّبون: الذكور ثم الإناث حسب الترتيب.
    private var children: [FamilyMember] {
        allWomen
            .filter { ($0.fatherId == woman.id || $0.motherId == woman.id) && $0.husbandId == nil }
            .sorted {
                if $0.isFemale != $1.isFemale { return !$0.isFemale }   // ذكور أولًا
                return $0.sortOrder < $1.sortOrder
            }
    }
    private var isViewingSelf: Bool { woman.id == me?.id }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {
                        compactHeroSection
                            .padding(.top, DS.Spacing.lg)

                        quickActionsRow
                            .padding(.horizontal, DS.Spacing.lg)

                        if let kinshipText {
                            kinshipBanner(kinshipText)
                                .padding(.horizontal, DS.Spacing.lg)
                        }

                        // المعلومات تظهر فقط عند توسيع الشيت (الحجم الكبير)
                        if detent == .large {
                            detailsCard
                                .padding(.horizontal, DS.Spacing.lg)
                            if canEdit {
                                adminCard
                                    .padding(.horizontal, DS.Spacing.lg)
                            }
                        } else {
                            Text(L10n.t("اسحب لأعلى لعرض التفاصيل", "Swipe up for details"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textTertiary)
                                .padding(.top, DS.Spacing.md)
                        }

                        Spacer(minLength: 40)
                    }
                }

                floatingCloseButton
            }
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .presentationDetents([.fraction(0.46), .large], selection: $detent)
            .presentationDragIndicator(.visible)
            // إضافة (ابن/بنت/زوجة/أم)
            .alert(addKind?.title ?? "", isPresented: Binding(
                get: { addKind != nil }, set: { if !$0 { addKind = nil; addName = "" } })) {
                TextField(L10n.t("الاسم", "Name"), text: $addName)
                Button(L10n.t("إضافة", "Add")) { performAdd() }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { addName = "" }
            }
            // تعديل الاسم
            .alert(L10n.t("تعديل الاسم", "Edit name"), isPresented: $showEditName) {
                TextField(L10n.t("الاسم الكامل", "Full name"), text: $editName)
                Button(L10n.t("حفظ", "Save")) { performRename() }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            }
            // حذف
            .alert(L10n.t("حذف العضو؟", "Delete member?"), isPresented: $showDelete) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) { performDelete() }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            } message: {
                Text(L10n.t("سيُحذف نهائيًا من شجرة النساء.", "This removes them from the women tree."))
            }
            // ترتيب الأبناء (سحب لإعادة الترتيب)
            .sheet(isPresented: $showReorder) { reorderSheet }
            // اختيار الأم من زوجات الأب
            .confirmationDialog(L10n.t("اختيار الأم", "Choose mother"),
                                isPresented: $showMotherPicker, titleVisibility: .visible) {
                ForEach(fatherWives) { w in
                    Button((w.fullName.isEmpty ? w.firstName : w.fullName)
                           + (w.id == woman.motherId ? "  ✓" : "")) { setMother(w.id) }
                }
                if woman.motherId != nil {
                    Button(L10n.t("إزالة الأم", "Remove mother"), role: .destructive) { setMother(nil) }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            } message: {
                Text(L10n.t("اختر أمّ العضو من زوجات الأب", "Pick the mother from the father's wives"))
            }
            // اختيار جنس الابن المُضاف: ذكر أو أنثى (زر واحد مدمج)
            .confirmationDialog(L10n.t("إضافة ابن", "Add child"),
                                isPresented: $showChildGender, titleVisibility: .visible) {
                Button(L10n.t("ذكر", "Male")) { addName = ""; addKind = .son }
                Button(L10n.t("أنثى", "Female")) { addName = ""; addKind = .daughter }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            }
            // مصدر إضافة الزوجة: عادية (بالاسم) أو من العائلة
            .confirmationDialog(L10n.t("إضافة زوجة", "Add wife"),
                                isPresented: $showWifeSource, titleVisibility: .visible) {
                Button(L10n.t("إضافة بالاسم", "Add by name")) { addName = ""; addKind = .wife }
                Button(L10n.t("اختيار من العائلة", "Choose from family")) { showWifePicker = true }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            }
            // فتح بروفايل إحدى الزوجات (عند تعدّدهن)
            .confirmationDialog(L10n.t("الزوجات", "Wives"),
                                isPresented: $showWifeNav, titleVisibility: .visible) {
                ForEach(wives) { w in
                    Button(w.fullName.isEmpty ? w.firstName : w.fullName) { onOpenMember?(w.id) }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            }
            // اختيار زوجة موجودة من العائلة (لعقدة ذكر)
            .sheet(isPresented: $showWifePicker) {
                familyPickerSheet(title: L10n.t("اختيار زوجة من العائلة", "Choose wife"),
                                  emptyMsg: L10n.t("لا توجد إناث متاحات في الشجرة", "No available family women"),
                                  candidates: wifeCandidates, onPick: { linkWife($0) },
                                  onCancel: { showWifePicker = false; wifeSearch = "" })
            }
            // اختيار زوج من العائلة (لعقدة أنثى)
            .sheet(isPresented: $showHusbandPicker) {
                familyPickerSheet(title: L10n.t("اختيار زوج من العائلة", "Choose husband"),
                                  emptyMsg: L10n.t("لا يوجد ذكور في الشجرة", "No family men"),
                                  candidates: husbandCandidates, onPick: { linkHusband($0) },
                                  onCancel: { showHusbandPicker = false; wifeSearch = "" })
            }
        }
    }

    /// مرشّحات «زوجة من العائلة»: إناث الشجرة غير المرتبطات بزوج (عدا العضو نفسه).
    /// مرشّحات «زوجة من العائلة»: إناث الشجرة غير المرتبطات بزوج (عدا العضو نفسه).
    private var wifeCandidates: [FamilyMember] {
        allWomen
            .filter { $0.isFemale && $0.id != woman.id && $0.husbandId == nil }
            .sorted { $0.fullName.localizedCompare($1.fullName) == .orderedAscending }
    }
    /// مرشّحات «زوج من العائلة»: ذكور الشجرة (عدا العضو نفسه).
    private var husbandCandidates: [FamilyMember] {
        allWomen
            .filter { !$0.isFemale && $0.id != woman.id }
            .sorted { $0.fullName.localizedCompare($1.fullName) == .orderedAscending }
    }

    /// قائمة اختيار عضو من العائلة (زوجة/زوج) مع بحث.
    private func familyPickerSheet(title: String, emptyMsg: String, candidates: [FamilyMember],
                                   onPick: @escaping (UUID) -> Void, onCancel: @escaping () -> Void) -> some View {
        let list = wifeSearch.trimmingCharacters(in: .whitespaces).isEmpty
            ? candidates
            : candidates.filter { $0.fullName.contains(wifeSearch) || $0.firstName.contains(wifeSearch) }
        return NavigationStack {
            Group {
                if candidates.isEmpty {
                    Text(emptyMsg)
                        .font(DS.Font.callout).foregroundColor(DS.Color.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(list) { m in
                        Button { onPick(m.id) } label: {
                            HStack(spacing: DS.Spacing.md) {
                                avatar(m, size: 36).saturation(m.isDeceased == true ? 0 : 1)
                                Text(m.fullName.isEmpty ? m.firstName : m.fullName)
                                    .font(DS.Font.callout).foregroundColor(DS.Color.textPrimary)
                                Spacer()
                            }
                        }
                    }
                    .searchable(text: $wifeSearch, prompt: L10n.t("بحث بالاسم", "Search by name"))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("إلغاء", "Cancel")) { onCancel() }
                }
            }
        }
        .presentationDetents([.large])
    }

    /// ربط أنثى موجودة كزوجة لهذه العقدة (لعقدة ذكر).
    private func linkWife(_ womanId: UUID) {
        showWifePicker = false; wifeSearch = ""; busy = true
        Task {
            try? await WomenStore.setHusbandId(womanId: womanId, husbandId: woman.id)
            await onChanged?()
            await MainActor.run {
                busy = false
                // افتح بروفايل الزوجة المختارة (وإلا أغلق الشيت)
                if let open = onOpenMember { open(womanId) } else { dismiss() }
            }
        }
    }

    /// ربط هذه الأنثى بزوج من ذكور العائلة.
    private func linkHusband(_ maleId: UUID) {
        showHusbandPicker = false; wifeSearch = ""; busy = true
        Task {
            try? await WomenStore.setHusbandId(womanId: woman.id, husbandId: maleId)
            await onChanged?()
            await MainActor.run { busy = false; dismiss() }
        }
    }

    private var reorderSheet: some View {
        NavigationStack {
            List {
                ForEach(orderedChildren) { c in
                    HStack(spacing: DS.Spacing.md) {
                        avatar(c, size: 34).saturation(c.isDeceased == true ? 0 : 1)
                        Text(c.firstName.isEmpty ? c.fullName : c.firstName)
                            .font(DS.Font.callout).foregroundColor(DS.Color.textPrimary)
                        Spacer()
                        Image(systemName: "line.3.horizontal").foregroundColor(DS.Color.textTertiary)
                    }
                }
                .onMove { from, to in orderedChildren.move(fromOffsets: from, toOffset: to) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(L10n.t("ترتيب الأبناء", "Reorder children"))
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("إلغاء", "Cancel")) { showReorder = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("حفظ", "Save")) { performReorder() }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Compact Hero

    private var compactHeroSection: some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 170, height: 170)
                    .blur(radius: 28)
                    .opacity(0.35)

                ZStack {
                    avatar(woman, size: 130)
                        .overlay(
                            Circle().stroke(
                                LinearGradient(
                                    colors: [DS.Color.primary, DS.Color.accent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                        )
                        .dsGlowShadow()

                    if woman.isDeceased == true {
                        Circle()
                            .fill(DS.Color.background)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "heart.slash.fill")
                                    .font(DS.Font.scaled(18, weight: .bold))
                                    .foregroundColor(DS.Color.textTertiary)
                            )
                            .offset(x: 48, y: 48)
                    }
                }
            }

            Text(woman.fullName.isEmpty ? woman.firstName : woman.fullName)
                .font(DS.Font.title2)
                .fontWeight(.bold)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, DS.Spacing.lg)
        }
    }

    // MARK: - Quick Actions (قرابة + عمر)

    @ViewBuilder
    private var quickActionsRow: some View {
        let showKinship = !isViewingSelf && me != nil
        HStack(spacing: DS.Spacing.sm) {
            if showKinship {
                Button(action: computeKinship) {
                    quickPillLabel(
                        icon: "point.3.connected.trianglepath.dotted",
                        label: L10n.t("صلة القرابة", "Kinship"),
                        color: DS.Color.warning
                    )
                }
                .buttonStyle(DSScaleButtonStyle())
            }
            agePill
        }
    }

    /// حبّة العمر — تظهر جنب زر القرابة. للمتوفّاة: رمادي + رمز يوضّح الوفاة.
    @ViewBuilder
    private var agePill: some View {
        let isDeceased = woman.isDeceased == true
        if let byStr = year(woman.birthDate), let byInt = Int(byStr) {
            let end: Int? = isDeceased ? Int(year(woman.deathDate) ?? "") : Calendar.current.component(.year, from: Date())
            if let end, end >= byInt, end - byInt < 130 {
                let age = end - byInt
                let color = isDeceased ? DS.Color.textSecondary : DS.Color.info
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: isDeceased ? "heart.slash.fill" : "timelapse")
                        .font(DS.Font.scaled(11, weight: .semibold))
                    Text("\(age) " + L10n.t("سنة", "yrs"))
                        .font(DS.Font.scaled(12, weight: .bold))
                    if isDeceased {
                        Text("· " + L10n.t(woman.isFemale ? "متوفّاة" : "متوفّى", "deceased"))
                            .font(DS.Font.scaled(11, weight: .semibold))
                    }
                }
                .foregroundColor(color)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs + 2)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }

    private func quickPillLabel(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(DS.Font.scaled(11, weight: .semibold))
            Text(label)
                .font(DS.Font.scaled(12, weight: .bold))
        }
        .foregroundColor(color)
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs + 2)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func kinshipBanner(_ text: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundColor(DS.Color.warning)
            Text(text)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)
            Spacer()
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.warning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private func computeKinship() {
        guard let me else { return }
        let lookup = Dictionary(uniqueKeysWithValues: allWomen.map { ($0.id, $0) })
        let result = KinshipCalculator.calculate(from: me, to: woman, lookup: lookup)
        withAnimation(DS.Anim.snappy) { kinshipText = result.relationship }
    }

    // MARK: - Details Card (العلاقات بالاسم + الأبناء المطويّون)

    private var detailsCard: some View {
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // ── الأم + الزوجة جنب بعض (بلا الأب) ──
            if mother != nil || !wives.isEmpty || husband != nil {
                HStack(spacing: DS.Spacing.sm) {
                    if let mother {
                        relationCell(icon: "figure.dress", label: L10n.t("الأم", "Mother"),
                                     value: shortName(mother), color: DS.Color.accent,
                                     onTap: { onOpenMember?(mother.id) })
                    }
                    if !wives.isEmpty {
                        relationCell(icon: "heart.fill",
                                     label: wives.count == 1 ? L10n.t("الزوجة", "Wife") : L10n.t("الزوجات", "Wives"),
                                     value: wives.map { shortName($0) }.joined(separator: "، "),
                                     color: Color(hex: "#C07A8C"),
                                     onTap: {
                                         if wives.count == 1 { onOpenMember?(wives[0].id) }
                                         else { showWifeNav = true }
                                     })
                    } else if let husband {
                        relationCell(icon: "person.fill", label: L10n.t("الزوج", "Husband"),
                                     value: shortName(husband), color: DS.Color.primary,
                                     onTap: { onOpenMember?(husband.id) })
                    }
                }
            }

            // ── الأبناء: مطويّون افتراضياً (مثل شجرة العائلة) ──
            if !children.isEmpty {
                Divider()
                childrenToggle
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .dsCardShadow()
    }

    private func shortName(_ m: FamilyMember) -> String {
        m.firstName.isEmpty ? m.fullName : m.firstName
    }

    /// خلية علاقة مدمجة (أيقونة + تسمية + اسم) — لعرض الأم والزوجة جنب بعض.
    private func relationCell(icon: String, label: String, value: String, color: Color,
                              onTap: (() -> Void)? = nil) -> some View {
        let inner = HStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 34, height: 34)
                Image(systemName: icon).font(DS.Font.scaled(14, weight: .semibold)).foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(DS.Font.caption2).foregroundColor(DS.Color.textSecondary)
                Text(value).font(DS.Font.calloutBold).foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            if onTap != nil {
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .font(DS.Font.scaled(11, weight: .bold)).foregroundColor(DS.Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.sm)
        .background(DS.Color.background)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        return Group {
            if let onTap {
                Button(action: onTap) { inner }.buttonStyle(DSScaleButtonStyle())
            } else {
                inner
            }
        }
    }

    /// الأبناء مطويّون مثل شجرة العائلة — يظهرون عند الضغط على العنوان.
    private var childrenToggle: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(DS.Anim.snappy) { childrenExpanded.toggle() }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "person.3.fill")
                        .font(DS.Font.scaled(13, weight: .semibold))
                        .foregroundColor(DS.Color.primary)
                    Text(L10n.t("الأبناء", "Children") + " (\(children.count))")
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(DS.Font.scaled(11, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                        .rotationEffect(.degrees(childrenExpanded ? 180 : 0))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if childrenExpanded {
                childrenTiles.padding(.top, DS.Spacing.sm)
            }
        }
    }

    private func detailRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 34, height: 34)
                Image(systemName: icon).font(DS.Font.scaled(14, weight: .semibold)).foregroundColor(color)
            }
            Text(label).font(DS.Font.callout).foregroundColor(DS.Color.textSecondary)
            Spacer()
            Text(value).font(DS.Font.calloutBold).foregroundColor(DS.Color.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .environment(\.layoutDirection, .leftToRight)
        }
        .padding(.vertical, DS.Spacing.sm)
    }

    // MARK: - Admin Card (إضافة/تعديل/حذف)

    private var adminCard: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 4)
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(L10n.t("الإدارة", "Manage"))
                .font(DS.Font.calloutBold).foregroundColor(DS.Color.textPrimary)
            LazyVGrid(columns: cols, spacing: DS.Spacing.lg) {
                adminCircle("ابن", "Child", "person.badge.plus", DS.Color.primary) { showChildGender = true }
                if !woman.isFemale {
                    adminCircle("زوجة", "Wife", "heart", Color(hex: "#C07A8C")) { showWifeSource = true }
                }
                adminCircle("أم", "Mother", "figure.dress", DS.Color.accent) { showMotherPicker = true }
                adminCircle("تعديل الاسم", "Rename", "pencil", DS.Color.info) {
                    editName = woman.fullName.isEmpty ? woman.firstName : woman.fullName
                    showEditName = true
                }
                if !children.isEmpty {
                    adminCircle("ترتيب الأبناء", "Reorder", "arrow.up.arrow.down", DS.Color.primaryDark) {
                        orderedChildren = children
                        showReorder = true
                    }
                }
                adminCircle(woman.isDeceased == true ? "إلغاء الوفاة" : "متوفّى",
                            woman.isDeceased == true ? "Living" : "Deceased",
                            "heart.slash", DS.Color.warning) { toggleDeceased() }
                adminCircle("حذف", "Delete", "trash", DS.Color.error) { showDelete = true }
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(busy ? ProgressView().tint(DS.Color.primary) : nil)
        .disabled(busy)
    }

    /// زر إدارة دائري: أيقونة داخل دائرة ملوّنة + تسمية تحتها.
    private func adminCircle(_ ar: String, _ en: String, _ icon: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill(color.opacity(0.12)).frame(width: 50, height: 50)
                    Circle().strokeBorder(color.opacity(0.25), lineWidth: 1).frame(width: 50, height: 50)
                    Image(systemName: icon).font(DS.Font.scaled(18, weight: .semibold)).foregroundColor(color)
                }
                Text(L10n.t(ar, en))
                    .font(DS.Font.caption2).foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Actions

    private var nextSort: Int { (children.map(\.sortOrder).max() ?? -1) + 1 }

    private func performAdd() {
        guard let kind = addKind, !addName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let name = addName.trimmingCharacters(in: .whitespaces)
        addName = ""; addKind = nil; busy = true
        Task {
            do {
                switch kind {
                case .son:
                    try await WomenStore.addChild(parentId: woman.id, name: name, sortOrder: nextSort, gender: "male", parentFullName: woman.fullName)
                case .daughter:
                    try await WomenStore.addChild(parentId: woman.id, name: name, sortOrder: nextSort, gender: "female", parentFullName: woman.fullName)
                case .wife:
                    try await WomenStore.addWife(husbandId: woman.id, name: name)
                case .mother:
                    try await WomenStore.addMother(childId: woman.id, name: name)
                }
                await onChanged?()
            } catch { }
            await MainActor.run { busy = false; dismiss() }
        }
    }

    private func performRename() {
        let name = editName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        busy = true
        Task {
            try? await WomenStore.update(id: woman.id, fullName: name,
                                         isDeceased: woman.isDeceased == true,
                                         deathDate: woman.deathDate, birthDate: woman.birthDate,
                                         gender: woman.gender, isHidden: woman.isHiddenFromTree)
            await onChanged?()
            await MainActor.run { busy = false; dismiss() }
        }
    }

    private func toggleDeceased() {
        busy = true
        Task {
            try? await WomenStore.update(id: woman.id,
                                         fullName: woman.fullName.isEmpty ? woman.firstName : woman.fullName,
                                         isDeceased: !(woman.isDeceased == true),
                                         deathDate: woman.deathDate, birthDate: woman.birthDate,
                                         gender: woman.gender, isHidden: woman.isHiddenFromTree)
            await onChanged?()
            await MainActor.run { busy = false; dismiss() }
        }
    }

    private func performDelete() {
        busy = true
        Task {
            try? await WomenStore.delete(id: woman.id)
            await onChanged?()
            await MainActor.run { busy = false; dismiss() }
        }
    }

    /// تعيين أمّ العضو (من زوجات الأب) أو إزالتها.
    private func setMother(_ motherId: UUID?) {
        busy = true
        Task {
            try? await WomenStore.setMotherId(childId: woman.id, motherId: motherId)
            await onChanged?()
            await MainActor.run { busy = false; dismiss() }
        }
    }

    private func performReorder() {
        let ids = orderedChildren.map(\.id)
        showReorder = false; busy = true
        Task {
            try? await WomenStore.reorder(orderedIds: ids)
            await onChanged?()
            await MainActor.run { busy = false; dismiss() }
        }
    }

    // (أُزيل familySection — العلاقات صارت ضمن detailsCard بالاسم، والأبناء عبر childrenToggle)

    /// الأبناء كبلاطات (صورة + اسم) — صف واحد حتى ٥، وسطران إذا أكثر. تُبرز الإناث بالوردي.
    @ViewBuilder
    private var childrenTiles: some View {
        if children.count > 5 {
            let mid = (children.count + 1) / 2
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack(alignment: .top, spacing: DS.Spacing.sm) {
                        ForEach(Array(children.prefix(mid))) { childTile($0) }
                    }
                    HStack(alignment: .top, spacing: DS.Spacing.sm) {
                        ForEach(Array(children.dropFirst(mid))) { childTile($0) }
                    }
                }
                .padding(.vertical, 2)
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    ForEach(children) { childTile($0) }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func childTile(_ c: FamilyMember) -> some View {
        VStack(spacing: 4) {
            ZStack {
                avatar(c, size: 46)
                    .saturation(c.isDeceased == true ? 0 : 1)
                    .overlay(Circle().strokeBorder(DS.Color.primary.opacity(0.18), lineWidth: 1))
                if c.isDeceased == true {
                    Circle().fill(DS.Color.background).frame(width: 16, height: 16)
                        .overlay(Image(systemName: "heart.slash.fill").font(.system(size: 9, weight: .bold)).foregroundColor(DS.Color.textTertiary))
                        .offset(x: 16, y: 16)
                }
            }
            Text(c.firstName.isEmpty ? c.fullName : c.firstName)
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: 56)
        }
    }

    private var floatingCloseButton: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(DS.Font.scaled(15, weight: .bold))
                    .foregroundColor(DS.Color.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(DS.Color.surface)
                    .clipShape(Circle())
                    .dsSubtleShadow()
            }
            .padding(.trailing, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
        }
    }

    private func relationRow(_ label: String?, _ m: FamilyMember, fullName: Bool = false) -> some View {
        let name = fullName ? (m.fullName.isEmpty ? m.firstName : m.fullName)
                            : (m.firstName.isEmpty ? m.fullName : m.firstName)
        return HStack(spacing: DS.Spacing.md) {
            avatar(m, size: 40).saturation(m.isDeceased == true ? 0 : 1)
            VStack(alignment: .leading, spacing: 2) {
                if let label {
                    Text(label)
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }
                Text(name)
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
            }
            Spacer()
            if m.isDeceased == true {
                if let ls = lifeSpanNeat(m) {
                    Text(ls)
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textSecondary)
                        .environment(\.layoutDirection, .leftToRight)
                } else {
                    Image(systemName: "heart.slash.fill")
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.background)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private func lifeSpanNeat(_ m: FamilyMember) -> String? {
        guard m.isDeceased == true else { return nil }
        let by = year(m.birthDate), dy = year(m.deathDate)
        guard by != nil || dy != nil else { return nil }   // كلاهما مفقود → لا تعرض
        return "\(dy ?? "؟") – \(by ?? "؟")"   // وفاة – ميلاد
    }

    private func avatar(_ m: FamilyMember, size: CGFloat) -> some View {
        Group {
            if let url = m.avatarUrl ?? m.photoURL, let u = URL(string: url) {
                CachedAsyncImage(url: u) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    fallback(m)
                }
            } else {
                fallback(m)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func fallback(_ m: FamilyMember) -> some View {
        GeometryReader { g in
            ZStack {
                LinearGradient(
                    colors: [DS.Color.primary.opacity(0.22), DS.Color.accent.opacity(0.14)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Text(String((m.firstName.isEmpty ? m.fullName : m.firstName).prefix(1)))
                    .font(.system(size: g.size.width * 0.42, weight: .bold, design: .rounded))
                    .foregroundColor(DS.Color.primary.opacity(0.85))
            }
        }
    }

    private func year(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if let r = s.range(of: "\\d{4}", options: .regularExpression) { return String(s[r]) }
        return nil
    }
}