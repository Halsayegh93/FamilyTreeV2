import SwiftUI
import Combine

/// شجرة النساء (women_members) — عرض فقط لكل الأعضاء.
/// تعرض WomenClassicTreeView (كانفس كلاسيكي بإحداثيات مطلقة).
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
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        Group {
            if isLoading {
                // التحميل الواحد: مجسّم قسم الشجرة يتنفّس (بدل الهالة النابضة والنقاط)
                ZStack {
                    DS.Color.background.ignoresSafeArea()
                    DSPageLoader(L10n.t("جارٍ تحميل شجرة النساء", "Loading the women tree"), section: .tree)
                        .dsStaggerIn(0)
                }
            } else if allMembers.isEmpty {
                // الرأس ومبدّل [شجرة العائلة / النساء] يبقيان — كانت الحالة الفارغة (أو فشل الجلب) بلا رأس ولا
                // مبدّل، فيعلق المستخدم في «النساء» ولا يرجع لشجرة العائلة (فحص ٢٠٢٦-١٠-٠٨)
                VStack(spacing: 0) {
                    if verticalSizeClass != .compact {
                        MainHeaderView(
                            selectedTab: $selectedTab,
                            showingNotifications: $showingNotifications,
                            title: L10n.t("النساء", "Women"),
                            subtitle: nil,
                            icon: AppSection.tree.symbol,
                            section: .tree,
                            subtitleChip: true
                        )
                    }
                    if let treeTab {
                        FamilyTreeTabBar(selection: treeTab)
                            .padding(.top, DS.Spacing.sm)
                    }
                    DSEmptyView(L10n.t("لا توجد بيانات للنساء بعد", "No women data yet"), section: .tree)
                        // الحالة الفارغة تدخل بتلاشٍ وصعود خفيف — «تقليل الحركة»: تلاشٍ فقط
                        .dsStaggerIn(0)
                        .frame(maxHeight: .infinity)
                }
                .background(DS.Color.background.ignoresSafeArea())
            } else {
                VStack(spacing: 0) {
                    // الوضع الأفقي: بلا هيدر — مساحة كاملة للشجرة (طلب المالك)
                    if verticalSizeClass != .compact {
                        MainHeaderView(
                            selectedTab: $selectedTab,
                            showingNotifications: $showingNotifications,
                            title: L10n.t("النساء", "Women"),
                            subtitle: "\(allMembers.count) " + L10n.t("فرد", "members"),
                            icon: AppSection.tree.symbol,
                            section: .tree,
                            subtitleChip: true
                        )
                    }
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
        // تغيير من جهاز آخر (realtime) → أعِد الجلب بلا تدخّل المستخدم
        .onReceive(womenChangePublisher) { _ in Task { await reloadWomen() } }
        // تفاصيل المرأة: مربّع بالمنتصف قابل للتوسّع بدل الشيت — نفس تفاصيل العضو (طلب المالك)
        .fullScreenCover(item: $selectedWoman) { w in
            WomanDetailSheet(
                woman: w,
                allWomen: allMembers,
                me: authVM.currentUser,
                canEdit: authVM.canEditMembers,
                // الحذف للمالك والمدير فقط (`canDeleteMembers`) — المراقب يعدّل ولا يحذف (م-٣ فحص ٢٠٢٦-١٠-٠٧)
                canDelete: authVM.canDeleteMembers,
                canAnnounceDeath: authVM.isAdmin,
                onChanged: { await reloadWomen() },
                onOpenMember: { id in
                    // أغلق المربّع الحالي ثم افتح بروفايل الزوجة بعد التحميل الجديد
                    selectedWoman = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        selectedWoman = allMembers.first { $0.id == id }
                    }
                }
            )
            .background(ClearPresentationBackground())
        }
        .transaction { t in
            // يظهر المربّع في مكانه بلا انزلاق — والإغلاق بلا انزلاق يتم داخل المربّع
            if selectedWoman != nil { t.disablesAnimations = true }
        }
    }

    /// المخفيّ يختفي عن العضو العادي، ويبقى ظاهرًا للإدارة **بعلامة إخفاء**
    /// (عين مشطوبة + تعتيم) — فالإدارة تحتاج رؤيته لتديره، والعلامة تمنع
    /// الالتباس الذي كان: إخفاء بلا أثر مرئيّ يوحي أن الإعداد لا يعمل.
    private func visible(_ rows: [FamilyMember]) -> [FamilyMember] {
        authVM.canEditMembers ? rows : rows.filter { !$0.isHiddenFromTree }
    }

    /// إعادة الجلب عند وصول تغيير حيّ من جهاز آخر.
    private var womenChangePublisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: .womenMembersChanged)
    }

    private func load() async {
        do {
            let rows = try await WomenStore.fetch()
            allMembers = visible(rows)
            isLoading = false
        } catch {
            isLoading = false
        }
    }

    /// إعادة تحميل بعد تعديل/إضافة/حذف من شيت التفاصيل.
    private func reloadWomen() async {
        if let rows = try? await WomenStore.fetch() { allMembers = visible(rows) }
    }

    /// عقدة المستخدم في شجرة النساء — تلقائيًا لكل مستخدم حسب هويّته:
    /// ١) عقدة بنفس معرّفه (mirror للذكور) · ٢) عقدة مرتبطة بحسابه · ٣) مطابقة بالاسم.
    private func resolveMyWomanId() -> UUID? {
        guard let me = authVM.currentUser else { return nil }
        // ١) الأدقّ: عقدة تحمل نفس معرّف المستخدم (الذكور مُمثّلون بنفس المعرّف)
        if allMembers.contains(where: { $0.id == me.id }) { return me.id }
        // ٢) عقدة مرتبطة بالحساب (للإناث المربوطات)
        if let linked = WomenStore.womanByLinkedUser[me.id] { return linked }
        // ٣) مطابقة بالاسم (احتياطي أخير)
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

/// تفاصيل امرأة — مربّع بمنتصف الشاشة قابل للتوسّع بنفس تصميم تفاصيل العضو
/// (MemberDetailsView، طلب المالك):
/// المصغّر: صورة + اسم + صلة القرابة + العمر.
/// «عرض التفاصيل» يوسّعه: العائلة (الأم/الزوج/الأبناء).
/// شريط أزرار ثابت أسفله: «الإدارة» كحلي يمين (يفتح مربّع الإدارة) و«إغلاق» يسار.
private struct WomanDetailSheet: View {
    let woman: FamilyMember
    let allWomen: [FamilyMember]
    /// المستخدم الحالي — لحساب صلة القرابة.
    let me: FamilyMember?
    /// صلاحية التعديل (إدارة).
    var canEdit: Bool = false
    /// صلاحية الحذف — المالك والمدير فقط حسب جدول الأدوار (م-٣ فحص ٢٠٢٦-١٠-٠٧)
    var canDelete: Bool = false
    /// عرض «إعلان وفاة» بعد تسجيلها — للمالك والمدير (السيرفر يفرضه منذ 20261007130000)
    var canAnnounceDeath: Bool = false
    /// يُستدعى بعد أي إضافة/تعديل/حذف لإعادة تحميل الشجرة.
    var onChanged: (() async -> Void)? = nil
    /// يفتح تفاصيل عضو آخر (مثلاً بروفايل الزوجة بعد ربطها من العائلة).
    var onOpenMember: ((UUID) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    /// حجم المربّع: مصغّر = صورة+اسم+قرابة+عمر فقط، موسّع = كل المعلومات.
    @State private var isExpanded = false
    /// نتيجة صلة القرابة داخل المربّع (بانر).
    @State private var kinshipText: String? = nil
    /// قسم «العائلة» (الأم/الزوج/الأبناء) مطويّ بالبداية — مثل تفاصيل العضو
    @State private var familyOpen = false
    @State private var heroIn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// ارتفاع شريط الأزرار السفلي — يدخل في ارتفاع المربّع المصغّر والموسّع
    @State private var panelFooterH: CGFloat = 0
    /// ارتفاع الرأس الملوّن الثابت أعلى المربّع (قرار المالك: الشكل «ب» مثل تفاصيل العضو)
    @State private var panelHeaderH: CGFloat = 0
    /// الرأس والشريط معاً — يدخلان في ارتفاع المربّع المصغّر والموسّع
    private var panelChromeH: CGFloat { panelHeaderH + panelFooterH }
    /// الرأس والشريط قيسا — قبلها لا نُبلِّغ ارتفاعاً ناقصاً (نفس تفاصيل العضو)
    private var chromeReady: Bool { panelFooterH > 0 && panelHeaderH > 0 }
    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — الرأس قد يتجاوز حدّ المربّع المصغّر، فيُسمح بتمريره
    /// (والتفاصيل لا تُبنى إلا عند التوسيع حتى لا يُمرَّر إلى فراغ)
    private var isLandscape: Bool { vSizeClass == .compact }

    /// لون القسم الذي فُتحت منه التفاصيل — كحلي «الإطار» يتبعه (نفس «إدارة السجل» في شجرة العائلة)
    @Environment(\.dsSection) private var section
    private var chromeInk: Color { DS.Color.primary.dsChrome(in: section) }

    // «الإدارة» = مربّع الإجراءات وحده (طلب المالك ٢٠٢٦-١٠-٠٧ «أبي الإجراءات تظهر بروحها»)، ومنه
    // تُفتح مربّعاتها: «إدارة السجل» (نفس مربّع شجرة العائلة)، الإضافة، الوفاة، الترتيب، الاختيار من العائلة
    @State private var showAdminBox = false
    /// مسودّة النماذج وما يُفتح فوق مربّع الإجراءات (كائن مرجعي — انظر `WomanAdminDraft`)
    @StateObject private var draft = WomanAdminDraft()

    // الاختيار من العائلة (من التفاصيل) — «المربّع المتطوّر» المشترك (`DSMemberPickerBox`)
    @State private var showWifeNav = false
    @State private var showHusbandPicker = false
    @State private var wifeSearch = ""

    enum AddKind: Int, Identifiable {
        /// ابن أو ابنة — إجراء واحد والجنس يُختار داخل المربّع (طلب المالك ٢٠٢٦-١٠-٠٧)
        case child, wife, mother
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .child: return L10n.t("إضافة ابن أو ابنة", "Add son or daughter")
            case .wife: return L10n.t("إضافة زوجة", "Add wife")
            case .mother: return L10n.t("إضافة أم", "Add mother")
            }
        }
        /// سطر «لمن» في بطاقة السياق أعلى المربّع
        var contextLabel: String {
            switch self {
            case .child: return L10n.t("إضافة ابن أو ابنة لـ", "Adding a child to")
            case .wife: return L10n.t("إضافة زوجة لـ", "Adding a wife to")
            case .mother: return L10n.t("إضافة أم لـ", "Adding a mother to")
            }
        }
        /// أيقونة رأس مربّع الإضافة
        var icon: String {
            switch self {
            case .child: return "person.crop.circle.badge.plus"
            case .wife: return "heart.fill"
            // "figure.dress" ليس رمزاً في SF Symbols — كانت الدائرة تظهر فارغة
            case .mother: return "figure.stand.dress"
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
            // البنت تبقى ابنة أبيها بعد زواجها — كان الشرط husbandId == nil
            // يُخفي المتزوجات من قائمة أبناء العضو رغم ظهورهنّ في الشجرة.
            .filter { $0.fatherId == woman.id || $0.motherId == woman.id }
            .sorted {
                if $0.isFemale != $1.isFemale { return !$0.isFemale }   // ذكور أولًا
                return $0.sortOrder < $1.sortOrder
            }
    }
    private var isViewingSelf: Bool { woman.id == me?.id }

    /// خصوصية الأنثى: زوجها لا يُعرض للعضو العادي — تراه الإدارة، وهي نفسها،
    /// وزوجها (فبطاقته تعرض «الزوجة» أصلاً).
    private var showHusband: Bool {
        guard husband != nil else { return false }
        return canEdit || isViewingSelf || husband?.id == me?.id
    }

    /// الأم أو الزوجة/الزوج (حسب الخصوصية) — صف العلاقات في «العائلة»
    private var hasRelations: Bool { mother != nil || !wives.isEmpty || showHusband }
    /// هل في التفاصيل ما يُعرض؟ — بلا شيء لا يظهر زر «عرض التفاصيل»
    private var hasDetails: Bool {
        hasRelations || !children.isEmpty
    }

    var body: some View {
        // مربّع بالمنتصف قابل للتوسّع بدل الشيت — يُغلق بـ«إغلاق» أو بالضغط خارجه
        DSExpandableCenterPanel(isExpanded: $isExpanded, onClose: { dismiss() }) {
            detailsStack
        }
    }

    // MARK: - المربّع وما يُفتح منه

    /// التفاصيل + مربّع «الإدارة» + ما يخصّ العرض وحده
    private var detailsStack: some View {
        detailsLayout
            // «الإدارة» — مربّع الإجراءات بمنتصف الشاشة، وكل إجراء يفتح مربّعه فوقه
            .dsCenterBox(isPresented: $showAdminBox) { WomanDraftScope(draft: draft) { actionsBox } }
            // خطأ كتابة (م-٢ فحص ٢٠٢٦-١٠-٠٧): رسالة السيرفر في مربّع تنبيه، والمربّع المفتوح يبقى كما هو
            .dsAlert(draft.writeError?.title ?? "",
                     isPresented: Binding(get: { draft.writeError != nil },
                                          set: { if !$0 { draft.writeError = nil } })) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) { draft.writeError = nil }
            } message: {
                Text(draft.writeError?.message ?? "")
            }
            // فتح بروفايل إحدى الزوجات (عند تعدّدهن)
            .confirmationDialog(L10n.t("الزوجات", "Wives"),
                                isPresented: $showWifeNav, titleVisibility: .visible) {
                ForEach(wives) { w in
                    Button(w.fullName.isEmpty ? w.firstName : w.fullName) { onOpenMember?(w.id) }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            }
            // اختيار زوج من العائلة (لعقدة أنثى) — «المربّع المتطوّر» المشترك
            .dsCenterBox(isPresented: $showHusbandPicker) {
                DSMemberPickerBox(
                    title: L10n.t("اختيار زوج من العائلة", "Choose husband"),
                    subtitle: displayName(woman),
                    candidates: husbandCandidates,
                    search: $wifeSearch,
                    emptyTitle: L10n.t("لا يوجد ذكور في الشجرة", "No family men"),
                    selectedId: woman.husbandId,
                    onPick: { linkHusband($0.id) },
                    onCancel: { showHusbandPicker = false; wifeSearch = "" })
            }
    }

    /// نوافذ الإدارة تُفتح فوق مربّع الإجراءات نفسه (لا من التفاصيل) — فـ«إلغاء» يرجع إليه
    private func withAdminPresentations<Box: View>(_ box: Box) -> some View {
        box
            // «إدارة السجل» — مربّع طويل من الأسفل مثل «إدارة السجل» في شجرة العائلة (توصية أبل للنماذج الطويلة)
            .dsTallBox(isPresented: $draft.showEdit) { WomanDraftScope(draft: draft) { editBox } }
            // «تسجيل وفاة» / «إلغاء الوفاة» — مربّعها الصغير
            .dsCenterBox(isPresented: $draft.showDeath) { WomanDraftScope(draft: draft) { deathBox } }
            // «ترتيب الأبناء» — مربّعه
            .dsCenterBox(isPresented: $draft.showReorder) { WomanDraftScope(draft: draft) { reorderBox } }
            // إضافة (ابن أو ابنة / زوجة / أم) — مربّع واحد بنفس «إضافة ابن» في شجرة العائلة
            .dsCenterBox(item: $draft.addKind) { kind in WomanDraftScope(draft: draft) { addBox(kind) } }
            // اختيار زوجة موجودة من العائلة (لعقدة ذكر) — «المربّع المتطوّر» المشترك
            .dsCenterBox(isPresented: $draft.showWifePicker) {
                DSMemberPickerBox(
                    title: L10n.t("اختيار زوجة من العائلة", "Choose wife"),
                    subtitle: displayName(woman),
                    candidates: wifeCandidates,
                    search: $wifeSearch,
                    emptyTitle: L10n.t("لا توجد إناث متاحات في الشجرة", "No available family women"),
                    onAddByName: { query in
                        draft.showWifePicker = false; wifeSearch = ""
                        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.boxHandoff) { startAdd(.wife, name: query) }
                    },
                    rowHint: L10n.t("ربطها زوجةً له", "Link as his wife"),
                    onPick: { linkWife($0.id) },
                    onCancel: { draft.showWifePicker = false; wifeSearch = "" })
            }
            // اختيار الأم من زوجات الأب — نفس المربّع، والمختارة حالياً بعلامة ✓
            .dsCenterBox(isPresented: $draft.showMother) {
                DSMemberPickerBox(
                    title: L10n.t("اختيار الأم", "Choose mother"),
                    subtitle: L10n.t("اختر أمّ العضو من زوجات الأب", "Pick the mother from the father's wives"),
                    icon: "figure.and.child.holdinghands",
                    candidates: fatherWives,
                    search: $wifeSearch,
                    emptyTitle: L10n.t("لا توجد زوجات للأب في الشجرة", "The father has no wives in the tree"),
                    selectedId: woman.motherId,
                    removeTitle: woman.motherId != nil ? L10n.t("إزالة الأم", "Remove mother") : nil,
                    onRemove: { setMother(nil) },
                    onPick: { setMother($0.id) },
                    onCancel: { draft.showMother = false; wifeSearch = "" })
            }
            // حذف
            .dsAlert(L10n.t("حذف العضو؟", "Delete member?"), isPresented: $draft.showDelete) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) { performDelete() }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            } message: {
                Text(L10n.t("سيُحذف نهائيًا من شجرة النساء.", "This removes them from the women tree."))
            }
            // مصدر إضافة الزوجة: عادية (بالاسم) أو من العائلة
            .confirmationDialog(L10n.t("إضافة زوجة", "Add wife"),
                                isPresented: $draft.showWifeSource, titleVisibility: .visible) {
                Button(L10n.t("إضافة بالاسم", "Add by name")) { startAdd(.wife) }
                Button(L10n.t("اختيار من العائلة", "Choose from family")) { draft.showWifePicker = true }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            }
    }

    // MARK: - هيكل المربّع (نفس تفاصيل العضو)

    /// الرأس الملوّن الثابت، ثم الرأس (يُقاس للمصغّر) والتفاصيل، وتحتها شريط الأزرار الثابت
    private var detailsLayout: some View {
        VStack(spacing: 0) {
            // رأس ملوّن ثابت (لا يتمرّر) مثل بقية المربّعات — قرار المالك (الشكل «ب»)
            womanHeaderBand.readHeight($panelHeaderH)

            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {
                        // الرأس: الصورة والاسم والقرابة وزر التفاصيل — ارتفاعه = المربّع المصغّر
                        headerPart
                            .id("detailsTop")
                            .background(
                                GeometryReader { geo in
                                    // بعد قياس الرأس الملوّن والشريط السفلي معاً (نفس سبب مربّعات الإضافة)
                                    Color.clear.preference(key: DSPanelCollapsedHeightKey.self,
                                                           value: chromeReady ? geo.size.height + DS.Spacing.lg + panelChromeH : 0)
                                }
                            )

                        // التفاصيل تبقى في مكانها ويُقصّ المربّع فوقها عند الإخفاء —
                        // فلا تختفي فجأة: يتحرّك الارتفاع وحده
                        if isExpanded || !isLandscape {
                            detailsBody
                                .opacity(isExpanded ? 1 : 0)
                                .allowsHitTesting(isExpanded)
                        }

                        Spacer(minLength: DS.Spacing.md)
                    }
                    // المربّع بحجم محتواه (+ الرأس الملوّن والشريط السفلي)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: SheetContentHeightKey.self,
                                                   value: chromeReady ? geo.size.height + panelChromeH : 0)
                        }
                    )
                }
                .scrollDisabled(!isExpanded && !isLandscape)
                .onChange(of: isExpanded) { expanded in
                    if !expanded {
                        withAnimation(DS.Anim.smooth) { scrollProxy.scrollTo("detailsTop", anchor: .top) }
                    }
                }
            }
            // شريط أزرار ثابت أسفل المربّع — مثل كل المربّعات: الإجراء كحلي يمين و«إغلاق» يسار
            panelFooter.readHeight($panelFooterH)
        }
        .background(DS.Color.background)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// رأس ملوّن مثل مربّعات الإضافة (فوق الصورة، بلا تداخل) — نفس رأس تفاصيل العضو
    private var womanHeaderBand: some View {
        DSComposerHeader(
            title: L10n.t("تفاصيل العضو", "Member Details"),
            subtitle: L10n.t("من شجرة النساء", "From the women's tree"),
            icon: "person.text.rectangle.fill",
            tint: woman.isDeceased == true ? DS.Color.textSecondary : DS.Color.actionNavy
        )
    }

    /// الجزء الظاهر في المربّع المصغّر
    private var headerPart: some View {
        VStack(spacing: DS.Spacing.md) {
            compactHeroSection
                .padding(.top, DS.Spacing.lg)

            quickActionsRow
                .padding(.horizontal, DS.Spacing.lg)
                .dsStaggerIn(1)

            if let kinshipText {
                kinshipBanner(kinshipText)
                    .padding(.horizontal, DS.Spacing.lg)
                    .transition(.opacity)
            }

            if hasDetails {
                detailsToggleButton
                    .dsStaggerIn(2)
            }
        }
    }

    /// «عرض التفاصيل» / «إخفاء التفاصيل» — يوسّع المربّع أو يصغّره
    private var detailsToggleButton: some View {
        let expanded = isExpanded
        // الزرّ الواحد (٤٤، تعبئة القسم) بعرض محتواه
        return DSButton(expanded ? L10n.t("إخفاء التفاصيل", "Hide details")
                                 : L10n.t("عرض التفاصيل", "Show details"),
                        icon: expanded ? "chevron.down" : "chevron.up",
                        fullWidth: false) {
            withAnimation(DS.Anim.snappy) { isExpanded.toggle() }
        }
    }

    /// جسم التفاصيل: العائلة (تدخل عند «عرض التفاصيل») — بلا تواريخ كما كان شيت النساء
    /// أصلاً (العمر في الحبّة فقط). الإدارة صارت مربّعاً مستقلاً من الشريط السفلي.
    private var detailsBody: some View {
        let open = isExpanded
        return VStack(spacing: DS.Spacing.md) {
            familySection
                .dsStaggerWhen(0, active: open)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Compact Hero

    private var compactHeroSection: some View {
        VStack(spacing: DS.Spacing.md) {
            // (بلا توهّج مموّه خلف الصورة — نفس تفاصيل العضو)
            ZStack {
                avatar(woman, size: 130)
                    // المتوفّى الذكر بالأبيض والأسود — والأنثى بلونها (نفس شجرة النساء)
                    .saturation(woman.isDeceased == true && !woman.isFemale ? 0 : 1)
                    .overlay(Circle().stroke(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
                    .scaleEffect(heroIn || reduceMotion ? 1 : 0.6)
                    .opacity(heroIn ? 1 : 0)
                    .accessibilityHidden(true)   // الصورة زخرفة — الاسم تحتها

                if woman.isDeceased == true {
                    Circle()
                        .fill(DS.Color.background)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "heart.slash.fill")
                                .dsGlyph(DS.Glyph.xlCompact)
                                .foregroundColor(DS.Color.textTertiary)
                        )
                        .overlay(Circle().stroke(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
                        .offset(x: 48, y: 48)
                        // القارئ الصوتي: علامة الوفاة تُقرأ كلمةً لا اسم رمز
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.t(woman.isFemale ? "متوفّاة" : "متوفّى", "Deceased"))
                }
            }

            Text(displayName(woman))
                .dsFont(.title)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, DS.Spacing.lg)
                .offset(y: heroIn || reduceMotion ? 0 : 10)
                .opacity(heroIn ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2)
                                       : .spring(response: 0.55, dampingFraction: 0.68).delay(0.05)) { heroIn = true }
        }
    }

    // MARK: - Quick Actions (قرابة + عمر)

    @ViewBuilder
    private var quickActionsRow: some View {
        let showKinship = !isViewingSelf && me != nil
        HStack(spacing: DS.Spacing.sm) {
            if showKinship {
                // شريحة العُدّة (٣٤، ومساحة ضغط ٤٤ داخلها)
                DSChipButton(L10n.t("صلة القرابة", "Kinship"),
                             icon: "point.3.connected.trianglepath.dotted",
                             tint: DS.Color.warning,
                             size: .small, action: computeKinship)
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
                // حبّة ساكنة بمقاس شريحة العُدّة وشكلها (جنب شريحة «صلة القرابة»)
                HStack(spacing: DS.Spacing.xsm) {
                    Image(systemName: isDeceased ? "heart.slash.fill" : "timelapse")
                        .dsGlyph(DS.Glyph.smCompact)
                        .accessibilityHidden(true)   // زخرفة
                    Text("\(age) " + L10n.t("سنة", "yrs"))
                        .dsFont(.chip)
                    if isDeceased {
                        Text("· " + L10n.t(woman.isFemale ? "متوفّاة" : "متوفّى", "deceased"))
                            .dsFont(.caption)
                    }
                }
                .lineLimit(1)
                .foregroundColor(color)
                .padding(.horizontal, DSBox.chipPadding)
                .frame(minHeight: DSBox.chipHeight)
                .background(Capsule().fill(color.opacity(DS.Opacity.tintFill)))
                .overlay(Capsule().strokeBorder(color.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
                .accessibilityElement(children: .combine)   // الحبّة تُقرأ جملةً واحدة
            }
        }
    }

    /// نتيجة صلة القرابة — ملاحظة العُدّة الملوّنة بلون القرابة
    private func kinshipBanner(_ text: String) -> some View {
        DSNoteCard(text,
                   title: L10n.t("صلة القرابة", "Kinship"),
                   icon: "point.3.connected.trianglepath.dotted",
                   tint: DS.Color.warning)
    }

    private func computeKinship() {
        guard let me else { return }
        let lookup = Dictionary(uniqueKeysWithValues: allWomen.map { ($0.id, $0) })
        // شجرة النساء وحدها تحسب صلة القرابة من جهة الأم
        let result = KinshipCalculator.calculate(from: me, to: woman, lookup: lookup, includeMaternal: true)
        withAnimation(DS.Anim.snappy) { kinshipText = result.relationship }
    }

    // MARK: - العائلة (الأم/الزوج/الأبناء) — قسم قابل للطي

    @ViewBuilder
    private var familySection: some View {
        let kids = children
        if hasRelations || !kids.isEmpty {
            // نفس أقسام المربّعات — العنوان يفتح/يخفي العائلة (مطويّة بالبداية)
            DSComposerSection(
                title: L10n.t("العائلة", "Family"),
                icon: "person.2.fill",
                tint: DS.Color.success,
                trailing: familySummary(children: kids.count),
                isOpen: $familyOpen
            ) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    if hasRelations {
                        relationsRow
                    }
                    if !kids.isEmpty {
                        childrenBox(kids)
                    }
                }
            }
        }
    }

    /// «الأم · الزوج · ٣ أبناء» — ملخّص بجانب العنوان والقسم مطويّ
    private func familySummary(children count: Int) -> String {
        var parts: [String] = []
        if mother != nil { parts.append(L10n.t("الأم", "Mother")) }
        let w = wives
        if !w.isEmpty {
            parts.append(w.count == 1 ? L10n.t("الزوجة", "Wife") : L10n.t("الزوجات", "Wives"))
        } else if showHusband {
            parts.append(L10n.t("الزوج", "Husband"))
        }
        if count > 0 { parts.append(L10n.t("\(count) أبناء", "\(count) children")) }
        return parts.joined(separator: " · ")
    }

    /// الأم + الزوجة (أو الزوج) جنب بعض — الضغط يفتح صاحبها
    private var relationsRow: some View {
        let w = wives
        return HStack(spacing: DS.Spacing.sm) {
            if let mother {
                relationTile(icon: "figure.stand.dress", label: L10n.t("الأم", "Mother"),
                             value: shortName(mother), color: DS.Color.accent,
                             onTap: { onOpenMember?(mother.id) })
            }
            if !w.isEmpty {
                relationTile(icon: "heart.fill",
                             label: w.count == 1 ? L10n.t("الزوجة", "Wife") : L10n.t("الزوجات", "Wives"),
                             value: w.map { shortName($0) }.joined(separator: "، "),
                             color: DS.Color.female,
                             onTap: {
                                 if w.count == 1 { onOpenMember?(w[0].id) }
                                 else { showWifeNav = true }
                             })
            } else if showHusband, let husband {
                relationTile(icon: "person.fill", label: L10n.t("الزوج", "Husband"),
                             value: shortName(husband), color: DS.Color.male,
                             onTap: { onOpenMember?(husband.id) })
            }
        }
    }

    private func shortName(_ m: FamilyMember) -> String {
        m.firstName.isEmpty ? m.fullName : m.firstName
    }

    private func displayName(_ m: FamilyMember) -> String {
        m.fullName.isEmpty ? m.firstName : m.displayFullName
    }

    /// صف علاقة بنفس صفوف المربّعات: أيقونة الحقل + العنوان + الاسم (+ سهم للفتح)
    private func relationTile(icon: String, label: String, value: String, color: Color,
                              onTap: (() -> Void)? = nil) -> some View {
        let inner = HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: color)
                .accessibilityHidden(true)   // زخرفة
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                // خط «العائلة» كما كان قبل التوحيد (طلب المالك ٢٠٢٦-١٠-٠٧): العنوان ١١ ثقيل والقيمة ١٣
                Text(label)
                    .dsFont(.familyLabel)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(value)
                    .dsFont(.familyValue)
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            if onTap != nil {
                DSChevron()   // سهم الصفّ الموحّد (زخرفة)
            }
        }
        .frame(maxWidth: .infinity)
        .dsRowBox()
        .contentShape(Rectangle())
        return Group {
            if let onTap {
                Button(action: onTap) { inner }.buttonStyle(DSPressStyle())
            } else {
                inner
            }
        }
    }

    /// الأبناء: الذكور ثم الإناث — كل ٣ في سطر متمركز (نفس شريط تفاصيل العضو — طلب المالك ٢٠٢٦-١٠-٠٧)
    /// عدد الأبناء في السطر الواحد (مثل تفاصيل العضو في شجرة العائلة)
    private static let childrenPerRow = 3

    private func childrenBox(_ kids: [FamilyMember]) -> some View {
        let sons = kids.filter { !$0.isFemale }
        let daughters = kids.filter { $0.isFemale }
        return VStack(spacing: DS.Spacing.sm) {
            Text(L10n.t("الأبناء", "Children") + " · \(kids.count)")
                .dsFont(.familyLabel)   // ١١ ثقيل كما كان قبل التوحيد
                .foregroundColor(DS.Color.fieldLabel)
                .frame(maxWidth: .infinity)
            if !sons.isEmpty {
                childrenGroup(L10n.t("الذكور", "Sons"), sons, DS.Color.male)
            }
            if !daughters.isEmpty {
                childrenGroup(L10n.t("الإناث", "Daughters"), daughters, DS.Color.female)
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity)
        .dsRowBox()
    }

    /// مجموعة أبناء (ذكور أو إناث) — عنوان بنقطة اللون ثم كل ٣ في سطر
    private func childrenGroup(_ title: String, _ list: [FamilyMember], _ color: Color) -> some View {
        VStack(spacing: DS.Spacing.xsm) {
            HStack(spacing: DS.Spacing.xs) {
                Circle().fill(color).frame(width: DS.Icon.legendDotSmall, height: DS.Icon.legendDotSmall)
                Text("\(title) (\(list.count))")
                    .dsFont(.boxSectionTitle)
                    .foregroundColor(DS.Color.textSecondary)
            }
            VStack(spacing: DS.Spacing.xs) {
                ForEach(Array(stride(from: 0, to: list.count, by: Self.childrenPerRow)), id: \.self) { start in
                    HStack(alignment: .top, spacing: DS.Spacing.md) {
                        ForEach(list[start..<min(start + Self.childrenPerRow, list.count)]) { c in
                            childBubble(c, ring: color.opacity(DS.Opacity.tintStroke))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// صورة دائرية بحلقة + الاسم الأول تحتها (علامة وفاة للمتوفّى)
    private func childBubble(_ c: FamilyMember, ring: Color) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            ZStack {
                avatar(c, size: 42)
                    .saturation(c.isDeceased == true && !c.isFemale ? 0 : 1)
                    .overlay(Circle().stroke(ring, lineWidth: DS.Border.widthBold).padding(-2))
                if c.isDeceased == true {
                    Circle().fill(DS.Color.background)
                        .frame(width: DS.Icon.avatarBadge, height: DS.Icon.avatarBadge)
                        .overlay(Image(systemName: "heart.slash.fill")
                            .dsGlyph(DS.Glyph.microCompact)
                            .foregroundColor(DS.Color.textTertiary))
                        .offset(x: 15, y: 15)
                }
            }
            Text(c.firstName.isEmpty ? c.fullName : c.firstName)
                .dsFont(.chipCompact)   // ١١٫٥ عريض كما كان قبل التوحيد
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 60)
        }
        // القارئ الصوتي: الاسم (+ «متوفّى») بلا حرف الصورة البديلة
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((c.firstName.isEmpty ? c.fullName : c.firstName)
                            + (c.isDeceased == true ? L10n.t("، متوفّى", ", deceased") : ""))
    }

    // MARK: - «الإدارة» = مربّع الإجراءات وحده (طلب المالك ٢٠٢٦-١٠-٠٧ «أبي الإجراءات تظهر بروحها»)
    //
    // مربّعات بنفس شكل «اختر نوع الطلب» ولوحة الإدارة: ثلاثة في كل سطر، أيقونة مجسّمة وتحتها اسم
    // الإجراء، والحذف اسمه أحمر. كل مربّع يفتح مربّعه فوقه (والمربّع يتقلّص خلفه قليلاً)، فـ«إلغاء» يرجع
    // إليه: «إدارة السجل» (نفس مربّع شجرة العائلة)، الإضافة، الوفاة، الترتيب، الأم، الزوجة، الحذف.
    // الكتابة تذهب لجداول شجرة النساء كما كانت (`WomenStore`).

    /// الأم تُختار من زوجات الأب فقط — بلا زوجات للأب ولا أمّ محدّدة لا يظهر مربّعها
    /// (كان يفتح قائمة فارغة)
    private var canPickMother: Bool { mother != nil || !fatherWives.isEmpty }

    /// يملأ مسودّة السجل من السجل نفسه — قبل فتح «إدارة السجل» أو الوفاة أو الترتيب
    private func loadRecordDraft() {
        draft.name = startName
        let birth = parseBirthDate(woman.birthDate)
        draft.hasBirth = birth != nil
        draft.birth = birth ?? Date()
        draft.deceased = woman.isDeceased == true
        let death = parseBirthDate(woman.deathDate)
        draft.hasDeath = draft.deceased && death != nil
        draft.death = death ?? Date()
        // المرتبطة بزوج متزوجة فعلاً — اعرضها كذلك ولو لم تُعلَّم بعد
        draft.married = startMarried
        draft.ordered = children
        draft.sorting = false
    }

    private func openEditBox() {
        loadRecordDraft()
        draft.showEdit = true
    }

    /// «تسجيل وفاة» / «إلغاء الوفاة» — المربّع يفتح والمفتاح مقلوب، يحدّد التاريخ ثم «حفظ»
    private func openDeathBox() {
        loadRecordDraft()
        draft.deceased.toggle()
        // نقطة البداية بعد القلب — «إلغاء» بلا تعديل لا يسأل «تجاهل التعديلات؟» (ن-٢ فحص ٢٠٢٦-١٠-٠٧)
        draft.datesStart = datesSignature
        draft.showDeath = true
    }

    private func openReorderBox() {
        loadRecordDraft()
        draft.sorting = true
        draft.showReorder = true
    }

    private struct AdminAction: Identifiable {
        let id: String
        let title: String
        let icon: String
        let color: Color
        let run: () -> Void
    }

    /// عنوان إجراء الوفاة حسب حالة السجل
    private var deathActionTitle: String {
        woman.isDeceased == true ? L10n.t("إلغاء الوفاة", "Mark living") : L10n.t("تسجيل وفاة", "Deceased")
    }

    /// الإجراءات بالترتيب: الإضافة، الأم والترتيب، الوفاة، تعديل البيانات، ثم الحذف
    private var adminActions: [AdminAction] {
        var list: [AdminAction] = [
            AdminAction(id: "child", title: L10n.t("إضافة ابن أو ابنة", "Add son or daughter"),
                        icon: "person.badge.plus", color: DS.Color.male) { startAdd(.child) }
        ]
        if !woman.isFemale {
            list.append(AdminAction(id: "wife", title: L10n.t("إضافة زوجة", "Add wife"),
                                    icon: "heart.fill", color: DS.Color.female) { draft.showWifeSource = true })
        }
        if canPickMother {
            list.append(AdminAction(id: "mother", title: L10n.t("الأم", "Mother"),
                                    icon: "figure.and.child.holdinghands", color: DS.Color.accent) {
                draft.showMother = true
            })
        }
        if !children.isEmpty {
            // neonBlue = كحلي primaryDark نفسه في الفاتح، وأزرق فاتح يُقرأ في الداكن
            list.append(AdminAction(id: "reorder", title: L10n.t("ترتيب الأبناء", "Reorder"),
                                    icon: "arrow.up.arrow.down", color: DS.Color.neonBlue) { openReorderBox() })
        }
        list.append(AdminAction(id: "deceased", title: deathActionTitle,
                                icon: "heart.slash", color: DS.Color.warning) { openDeathBox() })
        list.append(AdminAction(id: "edit", title: L10n.t("تعديل البيانات", "Edit details"),
                                icon: "pencil", color: DS.Color.primary) { openEditBox() })
        // الحذف للمالك والمدير فقط (م-٣)، ومن المدخل الواحد `requestDelete`
        if canDelete {
            list.append(AdminAction(id: "delete", title: L10n.t("حذف", "Delete"),
                                    icon: "trash", color: DS.Color.error) { requestDelete() })
        }
        return list
    }

    /// «الإدارة»: رأس ملوّن + «الإجراءات» + «إغلاق» — بلا زر إجراء
    private var actionsBox: some View {
        let actions = adminActions
        return withAdminPresentations(
            DSComposer(
                title: L10n.t("الإدارة", "Manage"),
                subtitle: displayName(woman),
                icon: "person.badge.shield.checkmark.fill",
                tint: woman.isDeceased == true ? DS.Color.textSecondary : DS.Color.actionNavy,
                actionTitle: "",
                showsAction: false,
                cancelTitle: L10n.t("إغلاق", "Close"),
                canSubmit: false,
                isBusy: draft.busy,
                isBehindExtra: draft.boxOnTop,
                onSubmit: {},
                onCancel: { showAdminBox = false }
            ) {
                DSComposerSection(title: L10n.t("الإجراءات", "Actions"),
                                  icon: "square.grid.2x2.fill",
                                  tint: DS.Color.primary,
                                  index: 0) {
                    // ثلاثة في كل سطر — صفوف عادية لا LazyVGrid (الشبكة الكسولة تُبلِّغ
                    // ارتفاعاً ناقصاً فيُقصّ آخر صف)
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(Array(stride(from: 0, to: actions.count, by: 3)), id: \.self) { start in
                            let end = min(start + 3, actions.count)
                            HStack(spacing: DS.Spacing.sm) {
                                ForEach(actions[start..<end]) { adminTile($0) }
                                ForEach(0..<(3 - (end - start)), id: \.self) { _ in
                                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                                }
                            }
                        }
                    }
                }
                .disabled(draft.busy)
            }
        )
    }

    /// مربّع إجراء — نفس مربّعات «اختر نوع الطلب»: أيقونة مجسّمة + اسم الإجراء
    /// (الحذف اسمه أحمر — إجراء لا رجعة فيه)
    private func adminTile(_ action: AdminAction) -> some View {
        Button(action: action.run) {
            VStack(spacing: DS.Spacing.xsm) {
                // قرص العُدّة المجسّم بمقاس مربّعات الأدوات (زخرفة — الاسم تحتها يكفي)
                DSStateIcon(action.icon, tint: action.color, size: DS.Icon.tile)
                Text(action.title)
                    .dsFieldFont(.chip)
                    .foregroundColor(action.color == DS.Color.error ? DS.Color.error : DS.Color.fieldLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xs)
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(action.title)
    }

    // MARK: - «إدارة السجل» — نفس مربّع «إدارة السجل» في شجرة العائلة (`AdminMemberDetailSheet`)
    // الصورة والاسم، ثم بطاقات `DSFormCard`: البيانات الأساسية، التواريخ والحالة (`DSLifeDatesBox`)،
    // الحالة الاجتماعية، النسب (الترتيب فيه)، ثم «حذف السجل نهائياً» بالأحمر، و«حفظ» / «إلغاء» أسفله.

    private var editBox: some View {
        DSComposer(
            title: L10n.t("إدارة السجل", "Member Admin"),
            subtitle: displayName(woman),
            icon: "person.badge.shield.checkmark.fill",
            tint: woman.isDeceased == true ? DS.Color.textSecondary : DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            actionIcon: "checkmark",
            canSubmit: !draft.name.trimmingCharacters(in: .whitespaces).isEmpty,
            isBusy: draft.busy,
            hasUnsavedChanges: adminFormHasChanges,
            onSubmit: performSave,
            onCancel: { draft.showEdit = false }
        ) {
            adminHero.dsStaggerIn(0)
            basicsCard.dsStaggerIn(1)
            datesCard.dsStaggerIn(2)
            if woman.isFemale { maritalCard.dsStaggerIn(3) }
            lineageCard.dsStaggerIn(4)
            // زرّ الحذف لمن يملك الحذف فقط (م-٣ فحص ٢٠٢٦-١٠-٠٧)
            if canDelete { deleteButton.dsStaggerIn(5) }
        }
    }

    // MARK: - مربّع الوفاة — «التواريخ والحالة» نفسها (مفتاح «متوفّاة» + تاريخ الوفاة) و«حفظ» / «إلغاء»
    private var deathBox: some View {
        DSComposer(
            title: deathActionTitle,
            subtitle: displayName(woman),
            icon: "heart.slash",
            tint: woman.isDeceased == true ? DS.Color.textSecondary : DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            actionIcon: "checkmark",
            canSubmit: true,
            isBusy: draft.busy,
            // يقارن بما فُتح عليه المربّع (المفتاح مقلوب أصلاً) لا بالسجل — ن-٢ فحص ٢٠٢٦-١٠-٠٧
            hasUnsavedChanges: datesSignature != draft.datesStart,
            onSubmit: performSave,
            onCancel: { draft.showDeath = false }
        ) {
            datesCard.dsStaggerIn(0)
        }
    }

    // MARK: - مربّع ترتيب الأبناء — أسهم للأعلى/الأسفل و«حفظ» / «إلغاء»
    private var reorderBox: some View {
        DSComposer(
            title: L10n.t("ترتيب الأبناء", "Reorder children"),
            subtitle: displayName(woman),
            icon: "arrow.up.arrow.down",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            actionIcon: "checkmark",
            canSubmit: true,
            isBusy: draft.busy,
            // ترتيب جديد لم يُحفظ → «إلغاء» يسأل قبل التجاهل
            hasUnsavedChanges: orderChanged,
            onSubmit: performSave,
            onCancel: { draft.showReorder = false }
        ) {
            DSFormCard(L10n.t("الأبناء (\(draft.ordered.count))", "Children (\(draft.ordered.count))"),
                       icon: "person.3.fill", color: chromeInk) {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(Array(draft.ordered.enumerated()), id: \.element.id) { index, child in
                        relationRow(child, sortIndex: index)
                    }
                }
            }
            .dsStaggerIn(0)
        }
    }

    /// الصورة والاسم — نفس رأس «إدارة السجل» (بلا تغيير صورة: سجلّات شجرة النساء بلا رفع صور)
    private var adminHero: some View {
        VStack(spacing: DS.Spacing.sm) {
            avatar(woman, size: DS.Icon.photoPicker)
                .saturation(woman.isDeceased == true && !woman.isFemale ? 0 : 1)
                .overlay(Circle().stroke(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
                .accessibilityHidden(true)   // الصورة زخرفة — الاسم تحتها
            Text(displayName(woman))
                .dsFont(.headline)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: البيانات الأساسية
    private var basicsCard: some View {
        DSFormCard(L10n.t("البيانات الأساسية", "Basic Info"),
                   icon: "person.text.rectangle.fill", color: chromeInk) {
            DSFieldBox(L10n.t("الاسم الكامل", "Full Name")) {
                TextField(L10n.t("الاسم الكامل", "Full Name"), text: $draft.name, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(.vertical, DS.Spacing.sm)
            }
        }
    }

    // MARK: التواريخ والحالة — تسجيل الوفاة بنفس صفوف شجرة العائلة (`DSLifeDatesBox`)
    private var datesCard: some View {
        DSFormCard(L10n.t("التواريخ والحالة", "Dates & Status"),
                   icon: "calendar", color: DS.Color.warning) {
            DSLifeDatesBox(hasBirthDate: $draft.hasBirth, birthDate: $draft.birth,
                           isDeceased: $draft.deceased,
                           hasDeathDate: $draft.hasDeath, deathDate: $draft.death,
                           deceasedTitle: woman.isFemale ? L10n.t("متوفّاة", "Deceased")
                                                         : L10n.t("متوفّى", "Deceased"))
        }
    }

    // MARK: الحالة الاجتماعية (للإناث)
    private var maritalCard: some View {
        // المرتبطة بزوج في الشجرة متزوجة بحكم الرابط — إطفاء المفتاح لها كان بلا أثر
        let linked = woman.husbandId != nil
        return DSFormCard(L10n.t("الحالة الاجتماعية", "Marital Status"),
                          icon: "heart.fill", color: chromeInk) {
            DSToggleBox(title: L10n.t("متزوجة", "Married"), isOn: $draft.married, tint: chromeInk)
                .disabled(linked)
            maritalNote(linked
                        ? L10n.t("مرتبطة بزوج في الشجرة — فُكّ الارتباط أولاً لتغيير الحالة.",
                                 "Linked to a husband in the tree — unlink first to change this.")
                        : L10n.t("المتزوجة لا تظهر في قائمة اختيار الزوجة.",
                                 "A married woman is hidden from wife candidates."))
        }
    }

    private func maritalNote(_ text: String) -> some View {
        Text(text)
            .dsFont(.footnote)
            .foregroundColor(DS.Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: النسب: الأم، الزوجات، الأبناء — نفس بطاقة «النسب» في شجرة العائلة
    private var lineageCard: some View {
        DSFormCard(L10n.t("النسب", "Lineage"), icon: "link", color: chromeInk) {
            // الأم والزوجات للعرض — تغييرها من مربّعات «الإدارة» («الأم»، «إضافة زوجة»)
            if canPickMother {
                lineageInfoRow(title: L10n.t("الأم", "Mother"),
                               value: mother.map(displayName),
                               placeholder: L10n.t("غير محدّدة", "Not set"))
            }

            let w = wives
            if !woman.isFemale && !w.isEmpty {
                lineageHeader(L10n.t("الزوجات (\(w.count))", "Wives (\(w.count))"))
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(w) { relationRow($0) }
                }
            }

            HStack {
                lineageHeader(L10n.t("الأبناء (\(draft.ordered.count))", "Children (\(draft.ordered.count))"))
                Spacer()
                if draft.ordered.count > 1 {
                    // «ترتيب» / «تم» — الشريحة الموحّدة (مساحة ضغط ٤٤ فيها)
                    DSChipButton(draft.sorting ? L10n.t("تم", "Done") : L10n.t("ترتيب", "Sort"),
                                 icon: draft.sorting ? "checkmark" : "arrow.up.arrow.down",
                                 tint: chromeInk,
                                 isSelected: draft.sorting, size: .small) {
                        withAnimation(DS.Anim.snappy) { draft.sorting.toggle() }
                    }
                }
            }
            .padding(.top, DS.Spacing.xs)

            VStack(spacing: DS.Spacing.sm) {
                ForEach(Array(draft.ordered.enumerated()), id: \.element.id) { index, child in
                    relationRow(child, sortIndex: index)
                }
            }
        }
    }

    private func lineageHeader(_ text: String) -> some View {
        Text(text)
            .dsFont(.sectionTitle)
            .foregroundColor(DS.Color.fieldValue)
    }

    /// صفّ للعرض بنفس صندوق صفوف المربّعات (مثل «الأب في الشجرة» بلا سهم): العنوان فوق والاسم
    private func lineageInfoRow(title: String, value: String?, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            lineageHeader(title)
            HStack(spacing: DS.Spacing.sm) {
                if let value {
                    Text(value)
                        .dsFieldFont(DSBox.fieldValueSize, weight: .semibold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                } else {
                    Text(placeholder)
                        .dsFieldFont(.body)
                        .foregroundColor(DS.Color.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: DS.Icon.tapTarget)
            // صندوق صفوف المربّعات الموحّد
            .dsRowBox()
        }
        .accessibilityElement(children: .combine)
    }

    /// صفّ زوجة أو ابن/ابنة — نفس صفّ الابن في «النسب» (قرص الحالة + الاسم + الميلاد).
    /// `sortIndex` = صفّ ابن: في وضع «ترتيب» تظهر أسهم للأعلى/الأسفل.
    private func relationRow(_ m: FamilyMember, sortIndex: Int? = nil) -> some View {
        let isDead = m.isDeceased == true
        // الوفاة بالأحمر بمعناها، والأنثى بلونها، والذكر بحبر القسم (نفس صفّ الابن في شجرة العائلة)
        let tint = isDead ? DS.Color.error : (m.isFemale ? DS.Color.female : chromeInk)
        let sorting = draft.sorting && sortIndex != nil
        return HStack(spacing: DS.Spacing.sm) {
            DSStateIcon(isDead ? "person.fill.xmark" : "person.fill",
                        tint: tint, size: DS.Icon.discSmall, mapsChrome: false)
                // القارئ الصوتي: الأيقونة زخرفة، إلا علامة الوفاة فتُقرأ كلمةً
                .accessibilityLabel(L10n.t("متوفى", "Deceased"))
                .accessibilityHidden(!isDead)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(m.firstName.isEmpty ? m.fullName : m.firstName)
                    .dsFieldFont(DSBox.fieldValueSize, weight: .semibold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                if let birth = m.birthDate, !birth.isEmpty {
                    Text(birth)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }

            Spacer(minLength: 0)

            if sorting, let index = sortIndex {
                // منطقة ضغط ٤٤×٤٤ لكل سهم (حد أبل) بلا تداخل والأقراص كما هي
                let hit = Self.sortHit
                HStack(spacing: hit / 2) {
                    sortArrow("chevron.up", enabled: index > 0,
                              label: L10n.t("نقل لأعلى", "Move up"),
                              hitLeading: hit, hitTrailing: 0) {
                        draft.ordered.swapAt(index, index - 1)
                    }
                    sortArrow("chevron.down", enabled: index < draft.ordered.count - 1,
                              label: L10n.t("نقل لأسفل", "Move down"),
                              hitLeading: 0, hitTrailing: hit) {
                        draft.ordered.swapAt(index, index + 1)
                    }
                }
            }
        }
        .frame(minHeight: DS.Icon.tapTarget)
        // صندوق صفوف المربّعات الموحّد
        .dsRowBox()
        .accessibilityElement(children: sorting ? .contain : .combine)
    }

    /// قرص أسهم الترتيب (قرص الصفّ)، وفرقه عن مساحة الضغط ٤٤ — نفس «النسب» في شجرة العائلة
    private static let sortDisc: CGFloat = DS.Icon.row
    private static let sortHit: CGFloat = DS.Icon.tapTarget - DS.Icon.row

    /// سهم ترتيب: القرص كما هو، ومنطقة ضغط ٤٤×٤٤ (حد أبل) حولها بلا تغيير مكانها —
    /// الحشو الموجب يوسّع منطقة الضغط، والسالب يعيد حجمها في التخطيط
    private func sortArrow(_ icon: String, enabled: Bool, label: String,
                           hitLeading: CGFloat, hitTrailing: CGFloat,
                           action: @escaping () -> Void) -> some View {
        Button { withAnimation(DS.Anim.snappy) { action() } } label: {
            Image(dsSymbol: icon)
                .dsGlyph(DS.Glyph.sm)
                .foregroundColor(enabled ? chromeInk : DS.Color.textTertiary.opacity(DS.Opacity.disabled))
                .frame(width: Self.sortDisc, height: Self.sortDisc)
                .background(chromeInk.opacity(enabled ? DS.Opacity.tintFill : DS.Opacity.tintFillSoft / 2), in: Circle())
                .padding(.leading, hitLeading)
                .padding(.trailing, hitTrailing)
                .padding(.vertical, Self.sortHit / 2)
                .contentShape(Rectangle())
                .padding(.leading, -hitLeading)
                .padding(.trailing, -hitTrailing)
                .padding(.vertical, -Self.sortHit / 2)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: حذف السجل — الزرّ الواحد بالأحمر، والتأكيد كما هو
    private var deleteButton: some View {
        DSButton(L10n.t("حذف السجل نهائياً", "Permanently Delete"), icon: "trash.fill", role: .destructive) {
            requestDelete()
        }
    }

    // MARK: تغييرات لم تُحفظ (توصية أبل) — «إلغاء» يسأل قبل التجاهل

    private var startName: String { woman.fullName.isEmpty ? woman.firstName : woman.fullName }
    private var startMarried: Bool { woman.isMarried == true || woman.husbandId != nil }
    private var startBirthKey: String? { parseBirthDate(woman.birthDate).map { Self.dayKey($0) } }
    private var startDeathKey: String? {
        woman.isDeceased == true ? parseBirthDate(woman.deathDate).map { Self.dayKey($0) } : nil
    }
    /// ما في النموذج الآن («yyyy-MM-dd» أو nil)
    private var draftBirthKey: String? { draft.hasBirth ? Self.dayKey(draft.birth) : nil }
    private var draftDeathKey: String? { draft.deceased && draft.hasDeath ? Self.dayKey(draft.death) : nil }
    private var orderChanged: Bool { draft.ordered.map(\.id) != children.map(\.id) }
    /// بطاقة «التواريخ والحالة» كما هي الآن (الميلاد · الوفاة · تاريخها) — لمقارنة مربّع الوفاة بنقطة بدايته
    private var datesSignature: String {
        [draftBirthKey ?? "", draft.deceased ? "1" : "0", draftDeathKey ?? ""].joined(separator: "|")
    }

    private var adminFormHasChanges: Bool {
        draft.name.trimmingCharacters(in: .whitespaces) != startName
            || draftBirthKey != startBirthKey
            || draft.deceased != (woman.isDeceased == true)
            || draftDeathKey != startDeathKey
            || (woman.isFemale && draft.married != startMarried)
            || orderChanged
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }

    // MARK: - الشريط السفلي (نفس شريط تفاصيل العضو)

    /// شريط ثابت أسفل المربّع: «الإدارة» كحلي يمين (يفتح مربّع الإجراءات)، «إغلاق» يسار
    private var panelFooter: some View {
        // صفّ الأزرار بمواصفة `DSBox` الواحدة
        HStack(spacing: DSBox.buttonSpacing) {
            if canEdit {
                // الزرّ الواحد (تعبئة القسم) — دوّارته أثناء العمل
                DSButton(L10n.t("الإدارة", "Manage"),
                         icon: "person.badge.shield.checkmark.fill",
                         isLoading: draft.busy) { showAdminBox = true }
                    // نفس تعطيل بطاقة الإدارة أثناء العمل
                    .disabled(draft.busy)
            }
            WomanPanelCloseButton()
        }
        // نفس شريط أزرار مربّعات العمل (`DSComposer`) وتفاصيل العضو: هوامشه من `DSBox`
        .padding(.horizontal, DSBox.footerHorizontal)
        .padding(.top, DSBox.footerTop)
        .padding(.bottom, DSBox.footerBottom)
        .background(
            DS.Color.background
                .overlay(alignment: .top) {
                    Rectangle().fill(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke))
                        .frame(height: DS.Card.strokeWidth)
                }
        )
    }

    // MARK: - مربّع الإضافة — نفس «إضافة ابن» في شجرة العائلة (`AddSonByAdminSheet`)

    private func startAdd(_ kind: AddKind, name: String = "") {
        draft.addName = name
        draft.addGender = "male"
        draft.addHasBirth = false
        draft.addBirth = Date()
        draft.addMarried = false
        draft.addKind = kind
    }

    /// للابن والابنة إجراء واحد بمبدّل الجنس؛ الزوجة والأم أنثى دائماً
    private func addIsFemale(_ kind: AddKind) -> Bool { kind == .child ? draft.addGender == "female" : true }

    private func addBox(_ kind: AddKind) -> some View {
        let isChild = kind == .child
        let female = addIsFemale(kind)
        return DSComposer(
            title: kind.title,
            subtitle: L10n.t("يُضاف للشجرة فوراً", "Added to the tree right away"),
            icon: kind.icon,
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("إضافة", "Add"),
            actionIcon: "plus",
            canSubmit: !draft.addName.trimmingCharacters(in: .whitespaces).isEmpty,
            isBusy: draft.busy,
            hasUnsavedChanges: addFormHasChanges(kind),
            onSubmit: { performAdd(kind) },
            onCancel: { draft.addKind = nil }
        ) {
            addContext(kind).dsStaggerIn(0)

            DSFormCard(L10n.t("البيانات الأساسية", "Basic Info"),
                       icon: "person.text.rectangle.fill", color: chromeInk) {
                DSFieldBox(isChild ? L10n.t("الاسم الأول", "First Name") : L10n.t("الاسم", "Name")) {
                    TextField(isChild ? L10n.t("الاسم الأول", "First name") : L10n.t("الاسم", "Name"),
                              text: $draft.addName)
                }
                if isChild {
                    DSGenderPicker(selection: $draft.addGender)
                }
            }
            .dsStaggerIn(1)

            DSFormCard(L10n.t("تاريخ الميلاد", "Birth Date"), icon: "calendar", color: DS.Color.warning) {
                // الإضافة لا تُسجّل وفاة (كما كانت) — الميلاد وحده
                DSLifeDatesBox(hasBirthDate: $draft.addHasBirth, birthDate: $draft.addBirth,
                               isDeceased: .constant(false),
                               hasDeathDate: .constant(false), deathDate: .constant(Date()),
                               showsDeceased: false)
            }
            .dsStaggerIn(2)

            if female {
                DSFormCard(L10n.t("الحالة الاجتماعية", "Marital Status"),
                           icon: "heart.fill", color: chromeInk) {
                    DSToggleBox(title: L10n.t("متزوجة", "Married"), isOn: $draft.addMarried, tint: chromeInk)
                    maritalNote(L10n.t("المتزوجة لا تظهر في قائمة اختيار الزوجة.",
                                       "A married woman is hidden from wife candidates."))
                }
                .dsStaggerIn(3)
            }
        }
    }

    /// لمن الإضافة — نفس بطاقة السياق أعلى «إضافة ابن»
    private func addContext(_ kind: AddKind) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            // قرص الحالة المجسّم (زخرفة — النص بجانبه يكفي)
            DSStateIcon("person.badge.plus", tint: chromeInk, size: DS.Icon.row, mapsChrome: false)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(kind.contextLabel)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                Text(displayName(woman))
                    .dsFont(.headlineCompact)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        // البطاقة الواحدة
        .dsCard(padding: DS.Spacing.md)
    }

    /// الإضافة تبدأ فارغة: أي اسم أو تاريخ أو «متزوجة» أو «أنثى» = إدخال لم يُحفظ
    private func addFormHasChanges(_ kind: AddKind) -> Bool {
        !draft.addName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draft.addHasBirth
            || (addIsFemale(kind) && draft.addMarried)
            || (kind == .child && draft.addGender != "male")
    }

    // MARK: - اختيار زوجة/زوج من العائلة — المرشّحون

    /// مرشّحات «زوجة من العائلة»: إناث الشجرة غير المرتبطات بزوج (عدا العضو نفسه).
    private var wifeCandidates: [FamilyMember] {
        allWomen
            // المتوفيات لا تُعرض ضمن مرشّحات الزوجة
            .filter { $0.isFemale && $0.isDeceased != true && $0.id != woman.id && $0.husbandId == nil }
            .sorted { $0.fullName.localizedCompare($1.fullName) == .orderedAscending }
    }
    /// مرشّحات «زوج من العائلة»: ذكور الشجرة (عدا العضو نفسه).
    private var husbandCandidates: [FamilyMember] {
        allWomen
            .filter { !$0.isFemale && $0.id != woman.id }
            .sorted { $0.fullName.localizedCompare($1.fullName) == .orderedAscending }
    }

    /// ربط أنثى موجودة كزوجة لهذه العقدة (لعقدة ذكر).
    private func linkWife(_ womanId: UUID) {
        runWrite(failTitle: L10n.t("تعذّر الربط", "Couldn't link"), {
            try await WomenStore.setHusbandId(womanId: womanId, husbandId: woman.id)
        }, onSuccess: {
            // افتح بروفايل الزوجة المختارة (وإلا أغلق المربّع)
            if let open = onOpenMember { open(womanId) } else { dismiss() }
        })
    }

    /// ربط هذه الأنثى بزوج من ذكور العائلة.
    private func linkHusband(_ maleId: UUID) {
        runWrite(failTitle: L10n.t("تعذّر الربط", "Couldn't link")) {
            try await WomenStore.setHusbandId(womanId: woman.id, husbandId: maleId)
        }
    }

    // MARK: - الكتابة — مسار واحد لكل كتابات شجرة النساء (م-٢ فحص ٢٠٢٦-١٠-٠٧)

    /// المربّع يبقى مفتوحاً بدوّارته أثناء الكتابة. النجاح: يُعاد التحميل وتُغلق المربّعات ثم التفاصيل
    /// (أو `onSuccess`). الفشل — ومنه رفض حارس روابط العائلة — يعرض رسالة السيرفر ويبقى المربّع كما هو؛
    /// كان `try?` / `catch {}` يغلقه كأن العملية نجحت.
    private func runWrite(failTitle: String,
                          _ write: @escaping () async throws -> Void,
                          onSuccess: (@MainActor () -> Void)? = nil) {
        guard !draft.busy else { return }
        draft.busy = true
        Task { @MainActor in
            do {
                try await write()
                await onChanged?()
                draft.busy = false
                draft.closeBoxes(); showAdminBox = false
                showHusbandPicker = false; wifeSearch = ""
                // بعد إغلاق المربّعات — لا يُغلق التفاصيل والمربّعات فوقها في اللحظة نفسها
                try? await Task.sleep(nanoseconds: UInt64(DSMotion.boxHandoff * 1_000_000_000))
                if let onSuccess { onSuccess() } else { dismiss() }
            } catch {
                // ما كُتب قبل الخطأ (حفظ من أكثر من خطوة) يظهر في الشجرة
                await onChanged?()
                draft.busy = false
                draft.writeError = WomanWriteError(title: failTitle, message: WomenStore.failureMessage(error))
            }
        }
    }

    // MARK: - Actions

    private var nextSort: Int { (children.map(\.sortOrder).max() ?? -1) + 1 }

    /// الإضافة — نفس كتابة «إضافة ابن» / «إضافة بنت» السابقتين حسب الجنس المختار
    private func performAdd(_ kind: AddKind) {
        guard !draft.addName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let name = draft.addName.trimmingCharacters(in: .whitespaces)
        let birth = draft.addHasBirth ? Self.dayKey(draft.addBirth) : nil
        let married = draft.addMarried
        let daughter = kind == .child && draft.addGender == "female"
        let sort = nextSort
        // الخطأ يُعرض والمربّع يبقى بما كُتب فيه (م-٢ فحص ٢٠٢٦-١٠-٠٧) — كان `catch { }` يغلقه بصمت
        runWrite(failTitle: L10n.t("تعذّرت الإضافة", "Couldn't add")) {
            switch kind {
            case .child where daughter:
                try await WomenStore.addChild(parentId: woman.id, name: name, sortOrder: sort, gender: "female", parentFullName: woman.fullName, birthDate: birth, isMarried: married)
            case .child:
                try await WomenStore.addChild(parentId: woman.id, name: name, sortOrder: sort, gender: "male", parentFullName: woman.fullName, birthDate: birth)
            case .wife:
                try await WomenStore.addWife(husbandId: woman.id, name: name, birthDate: birth, isMarried: married)
            case .mother:
                try await WomenStore.addMother(childId: woman.id, name: name, birthDate: birth, isMarried: married)
            }
        }
    }

    /// «حفظ» في «إدارة السجل» ومربّعي الوفاة والترتيب — نفس كتابة «تعديل البيانات» و«تسجيل وفاة»
    /// و«ترتيب الأبناء» السابقة (تقارن المسودّة بالسجل وتكتب ما تغيّر فقط).
    /// وفاة سُجّلت الآن لأنثى → مربّع «إعلان وفاة».
    private func performSave() {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let deceased = draft.deceased
        let wasDeceased = woman.isDeceased == true
        let birthKey = draftBirthKey
        let deathKey = draftDeathKey
        // ما لم يتغيّر يُكتب كما هو في السجل (لا يُفقد تاريخ بصيغة أخرى)
        let birthToWrite = birthKey != startBirthKey ? birthKey : woman.birthDate
        let deathToWrite = deathKey != startDeathKey ? deathKey : woman.deathDate
        let fieldsChanged = name != startName || birthKey != startBirthKey
            || deceased != wasDeceased || deathKey != startDeathKey
        let married = draft.married
        let marriedChanged = woman.isFemale && married != startMarried
        let reorder = orderChanged
        let orderIds = draft.ordered.map(\.id)
        guard fieldsChanged || marriedChanged || reorder else {
            // لا تغيير: يُغلق المربّع المفتوح ويبقى مربّع الإجراءات
            draft.closeBoxes()
            return
        }
        let woman = self.woman
        let canAnnounce = canAnnounceDeath
        runWrite(failTitle: L10n.t("تعذّر الحفظ", "Couldn't save"), {
            if fieldsChanged {
                try await WomenStore.update(id: woman.id, fullName: name,
                                            isDeceased: deceased,
                                            deathDate: deathToWrite, birthDate: birthToWrite,
                                            gender: woman.gender, isHidden: woman.isHiddenFromTree)
            }
            if woman.isFemale, married != (woman.isMarried == true) {
                try await WomenStore.setMarried(id: woman.id, married)
            }
            if reorder {
                try await WomenStore.reorder(orderedIds: orderIds)
            }
        }, onSuccess: {
            dismiss()
            // وفاة امرأة سُجّلت الآن → مربّع «إعلان وفاة» بصيغة المؤنث
            // (الرجال المنعكسون هنا تُسجَّل وفاتهم من شجرة الرجال)
            if deceased, !wasDeceased, woman.isFemale {
                Task {
                    await DeathAnnouncementPresenter.offer(
                        DeathAnnouncementTarget(id: woman.id, name: name, isFemale: true,
                                                deathDate: deathToWrite),
                        canAnnounce: canAnnounce)
                }
            }
        })
    }

    /// تحويل نص التاريخ لـDate (yyyy-MM-dd)
    private func parseBirthDate(_ raw: String?) -> Date? {
        guard let raw, raw.count >= 10 else { return nil }
        return Self.dayFormatter.date(from: String(raw.prefix(10)))
    }

    /// المدخل الواحد للحذف — مربّع «حذف» في الإدارة و«حذف السجل نهائياً» في «إدارة السجل» يمرّان من هنا،
    /// ثم التأكيد نفسه ثم `performDelete` (م-٢/م-٣ فحص ٢٠٢٦-١٠-٠٧)
    private func requestDelete() {
        guard canDelete else { return }
        draft.showDelete = true
    }

    /// الحذف — إن رفضه السيرفر (أبناء/بنات/زوجة مرتبطون) تظهر رسالته ويبقى المربّع مفتوحاً
    private func performDelete() {
        guard canDelete else { return }
        runWrite(failTitle: L10n.t("تعذّر الحذف", "Couldn't delete")) {
            try await WomenStore.delete(id: woman.id)
        }
    }

    /// تعيين أمّ العضو (من زوجات الأب) أو إزالتها.
    private func setMother(_ motherId: UUID?) {
        runWrite(failTitle: L10n.t("تعذّر الحفظ", "Couldn't save")) {
            try await WomenStore.setMotherId(childId: woman.id, motherId: motherId)
        }
    }

    // MARK: - الصور

    private func avatar(_ m: FamilyMember, size: CGFloat) -> some View {
        Group {
            if let url = m.avatarUrl ?? m.photoURL, let u = URL(string: url) {
                CachedAsyncImage(url: u) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    fallback(m, size: size)
                }
            } else {
                fallback(m, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func fallback(_ m: FamilyMember, size: CGFloat) -> some View {
        // بلا صورة — مجسّم الشخص بلون الجنس نفسه
        let artTint: Color = m.isFemale
            ? (m.isDeceased == true ? DS.Color.femaleDeceased : DS.Color.female)
            : (m.isDeceased == true ? DS.Color.textTertiary : DS.Color.male)
        // قرص العُدّة المجسّم بلون الجنس كما هو (بلا تحويل للقسم)
        return DSStateIcon("person.fill", tint: artTint, size: size, mapsChrome: false)
    }

    private func year(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if let r = s.range(of: "\\d{4}", options: .regularExpression) { return String(s[r]) }
        return nil
    }
}

/// مسودّة «إدارة السجل» ومربّع الإضافة — كائن مرجعي: محتوى المربّع المعروض يُبنى من إغلاق
/// لا يُعاد حسابه حين تتغيّر حالة التفاصيل وحدها (كان «حفظ»/«إضافة» يبقى معطّلاً بعد الكتابة)،
/// فيراقبه `WomanDraftScope` داخل المربّع ويعيد بناءه مع كل تغيّر.
private final class WomanAdminDraft: ObservableObject {
    @Published var name = ""
    @Published var hasBirth = false
    @Published var birth = Date()
    @Published var deceased = false
    @Published var hasDeath = false
    @Published var death = Date()
    @Published var married = false
    @Published var ordered: [FamilyMember] = []
    @Published var sorting = false
    @Published var addName = ""
    @Published var addGender = "male"
    @Published var addHasBirth = false
    @Published var addBirth = Date()
    @Published var addMarried = false
    // ما يُفتح فوق مربّع الإجراءات
    @Published var addKind: WomanDetailSheet.AddKind? = nil
    @Published var showEdit = false
    @Published var showDeath = false
    @Published var showReorder = false
    @Published var showMother = false
    @Published var showWifePicker = false
    @Published var showWifeSource = false
    @Published var showDelete = false
    /// كتابة جارية — في المسودّة حتى يراها المربّع المفتوح فوق التفاصيل (يبقى مفتوحاً بدوّارته)
    @Published var busy = false
    /// خطأ آخر كتابة — يظهر في `dsAlert` والمربّع يبقى مفتوحاً (م-٢ فحص ٢٠٢٦-١٠-٠٧)
    @Published var writeError: WomanWriteError? = nil
    /// بطاقة التواريخ لحظة فتح مربّع الوفاة (ن-٢)
    var datesStart = ""

    /// مربّع مفتوح فوق مربّع الإجراءات → يتقلّص خلفه قليلاً
    var boxOnTop: Bool {
        addKind != nil || showEdit || showDeath || showReorder || showMother || showWifePicker
    }

    func closeBoxes() {
        addKind = nil
        showEdit = false; showDeath = false; showReorder = false
        showMother = false; showWifePicker = false; showWifeSource = false
    }
}

/// خطأ كتابة في شجرة النساء: عنوان الرسالة + نص السيرفر (أو النص العام) — م-٢ فحص ٢٠٢٦-١٠-٠٧
private struct WomanWriteError {
    let title: String
    let message: String
}

/// يعيد بناء محتوى المربّع مع كل تغيّر في المسودّة
private struct WomanDraftScope<Content: View>: View {
    @ObservedObject var draft: WomanAdminDraft
    @ViewBuilder let content: () -> Content
    var body: some View { content() }
}

/// «إغلاق» في شريط المربّع السفلي (يسار، مثل «إلغاء» بقية المربّعات) — عرض مستقل
/// حتى يقرأ إغلاق المربّع المتحرّك من داخله (نسخة من PanelCloseButton في تفاصيل العضو)
private struct WomanPanelCloseButton: View {
    @Environment(\.dsPanelClose) private var panelClose
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // «إغلاق» = زرّ الإلغاء في مواصفة `DSBox` الواحدة
        Button(L10n.t("إغلاق", "Close")) {
            if let panelClose { panelClose() } else { dismiss() }
        }
        .buttonStyle(.ds(.cancel))
    }
}
