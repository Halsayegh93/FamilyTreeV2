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
    /// فشل الجلب ولا كاش — حالة خطأ بزرّ «إعادة المحاولة» لا «لا توجد بيانات» (مراجعة ٢٠٢٦-١١-٢٧ #9)
    @State private var loadFailed = false
    @EnvironmentObject private var memberVM: MemberViewModel
    /// عدد الرأس = «الإجمالي» في «إحصائيات العائلة» بالدالة نفسها (`AdminFamilyCensus`) — طلب المالك ٢٠٢٦-١١-١١
    /// «عدد شجرة النساء مو نفس الإجمالي» (كان عدد صفوف الجدول كلها مع المرايا وخارج العائلة)
    @State private var headcount: Int?
    /// «ابن البنت» يُطرح من الرجال في «الإجمالي» — يتحدّث العدد حين تصل قائمته
    @ObservedObject private var sons = DaughterSonsIndex.shared
    @State private var selectedWoman: FamilyMember? = nil
    @State private var showingNotifications = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// الحساب المقيّد («أكمل حسابك») — شجرة النساء مقفولة (الرأس والمبدّل يبقيان)
    @ObservedObject private var lineage = LineageGateStore.shared

    var body: some View {
        Group {
            if lineage.isLocked(.womenTree) {
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
                    LineageLockedView(section: .tree)
                        .frame(maxHeight: .infinity)
                }
                .background(DS.Color.background.ignoresSafeArea())
            } else if isLoading {
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
                    Group {
                        if loadFailed {
                            DSEmptyView(L10n.t("تعذّر تحميل شجرة النساء", "Couldn't load the women's tree"),
                                        message: L10n.t("تحقّق من الاتصال ثم أعد المحاولة.", "Check your connection and try again."),
                                        section: .tree,
                                        actionTitle: L10n.t("إعادة المحاولة", "Retry"), actionIcon: "arrow.clockwise") {
                                Task {
                                    isLoading = true
                                    await load()
                                }
                            }
                        } else {
                            DSEmptyView(L10n.t("لا توجد بيانات للنساء بعد", "No women data yet"), section: .tree)
                        }
                    }
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
                            // صيغة شجرة العائلة «2,990 فرداً» (مراجعة ٢٠٢٦-١١-٢٧ #11) — الرقم كما هو (= «الإجمالي»، طلب المالك ٢٠٢٦-١١-١١)
                            subtitle: L10n.t(TreeHeaderCount.arabic(headcount ?? allMembers.count),
                                             TreeHeaderCount.english(headcount ?? allMembers.count)),
                            icon: AppSection.tree.symbol,
                            section: .tree,
                            subtitleChip: true
                        )
                    }
                    WomenClassicTreeView(
                        members: allMembers,
                        // «صلاحيات الأعضاء حسب الفئة»: «تفاصيل المرأة» مطفأة لفئته — الضغط لا يفتح شيئاً (عقدتها هي تفتح)
                        onSelect: { w in
                            if w.id == authVM.currentUser?.id || authVM.memberSees(.womenTreeDetails) { selectedWoman = w }
                        },
                        treeTab: treeTab,
                        meWomanId: resolveMyWomanId(),
                        // حساب امرأة: تفتح الشجرة على عقدتها
                        autoLocate: (authVM.currentUser?.isWomanAccount ?? false) || LineageGateStore.shared.status?.flagged == true,
                        onRefresh: { await reloadWomen() },
                        linkedAvatars: linkedAvatars,
                        // 🔍 مثل شجرة العائلة وبصلاحيتها نفسها (طلب المالك ٢٠٢٦-١١-٢٨)
                        canSearch: authVM.memberSees(.treeSearch)
                    )
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await load() }
        .onAppear { refreshHeadcount() }
        .onChange(of: allMembers.count) { _ in refreshHeadcount() }
        .onChange(of: memberVM.membersVersion) { _ in refreshHeadcount() }
        .onChange(of: sons.ids) { _ in refreshHeadcount() }
        .task { if authVM.canModerateTree { await DaughterSonsIndex.shared.refresh() } }
        // انفكّ القفل (وافقت الإدارة على «أكمل حسابك») ← الجلب الآن
        .onChange(of: lineage.isLocked(.womenTree)) { locked in
            if !locked { Task { await load() } }
        }
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
                canModerate: authVM.canModerate,
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
        if authVM.canEditMembers { return rows }
        var out = rows.filter { !$0.isHiddenFromTree }
        // «ما يظهر في الشجرة» — اختيار البنت (٢٠٢٦-١١-٠٩): زوجها من خارج العائلة وعيالها منه مخفيون إلا بإظهارها
        guard WomenStore.visibilitySupported else { return out }
        let outside = WomenStore.outsideFamilyIds
        guard !outside.isEmpty else { return out }
        let spouseOn = WomenStore.spouseShownIds, kidsOn = WomenStore.childrenShownIds, hiddenKids = WomenStore.hiddenChildIds
        var hiddenHusbands = Set<UUID>()
        for w in out where w.isFemale {
            if let h = w.husbandId, outside.contains(h), !spouseOn.contains(w.id) { hiddenHusbands.insert(h) }
        }
        out.removeAll { m in
            if hiddenHusbands.contains(m.id) { return true }
            if let f = m.fatherId, outside.contains(f), let mom = m.motherId {
                return !kidsOn.contains(mom) || hiddenKids.contains(m.id)
            }
            return false
        }
        return out
    }

    /// إعادة الجلب عند وصول تغيير حيّ من جهاز آخر.
    private var womenChangePublisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: .womenMembersChanged)
    }

    /// صورة حساب الذكر المرتبط بعقدته حين لا صورة على العقدة (ابن البنت صاحب الحساب — صورته في ملفه لا في
    /// شجرة النساء). الإناث لا صور لهن أبداً («العضو ابن البنت اذا حاط صورة خلها تظهر بالشجرة» ٢٠٢٦-١١-٢٤)
    private var linkedAvatars: [UUID: String] {
        var out: [UUID: String] = [:]
        for m in allMembers where !m.isFemale && (m.avatarUrl ?? "").isEmpty {
            guard let uid = WomenStore.linkedUserByWoman[m.id],
                  let profile = memberVM.member(byId: uid),
                  !profile.isFemale,
                  let a = profile.avatarUrl, !a.isEmpty else { continue }
            out[m.id] = a
        }
        return out
    }

    /// الرجال (شجرة العائلة) + نساء شجرة النساء — نفس «الإجمالي»؛ قبل وصول الشجرتين يبقى عدد الصفوف
    private func refreshHeadcount() {
        guard !allMembers.isEmpty, !memberVM.allMembers.isEmpty else { return }
        headcount = AdminFamilyCensus.make(members: memberVM.allMembers, women: allMembers).counts.total
    }

    private func load() async {
        // مقفولة على الحساب المقيّد — لا جلب (السيرفر يرجع فاضي) حتى ينفكّ القفل
        if lineage.isLocked(.womenTree) { return }
        do {
            let rows = try await WomenStore.fetch()
            allMembers = visible(rows)
            loadFailed = false
            isLoading = false
        } catch {
            // الكاش يبقى ظاهراً إن وُجد؛ بلا كاش ← حالة الخطأ بزرّ الإعادة
            Log.warning("[Women] الجلب فشل: \(error.localizedDescription)")
            loadFailed = allMembers.isEmpty
            isLoading = false
        }
    }

    /// إعادة تحميل بعد تعديل/إضافة/حذف من شيت التفاصيل.
    private func reloadWomen() async {
        do {
            allMembers = visible(try await WomenStore.fetch())
        } catch {
            // الشجرة تبقى كما هي — والتغيّر الحيّ (realtime) يعيد الجلب لاحقاً
            Log.warning("[Women] إعادة الجلب بعد الحفظ فشلت: \(error.localizedDescription)")
        }
    }

    /// عقدة المستخدم في شجرة النساء — بالمعرّفات وحدها (مراجعة ٢٠٢٦-١١-٢٧ #4؛ كانت مطابقة بأول ٣ كلمات من الاسم
    /// توصل لعقدة غيره): عقدته بمعرّف ملفه (الرجل: عقدته المرآة) ثم المربوطة بحسابه. `WomenMyNode` (مفحوص: W1)
    private func resolveMyWomanId() -> UUID? {
        let ids = Set(allMembers.map(\.id))
        return WomenMyNode.resolve(userId: authVM.currentUser?.id, hasNode: { ids.contains($0) },
                                   womanByLinkedUser: WomenStore.womanByLinkedUser)
    }
}

/// تفاصيل امرأة — مربّع بمنتصف الشاشة قابل للتوسّع بنفس تصميم تفاصيل العضو
/// (MemberDetailsView، طلب المالك):
/// المصغّر: صورة + اسم + صلة القرابة + العمر.
/// «عرض التفاصيل» يوسّعه: العائلة (الأم/الزوج/الأبناء).
/// شريط أزرار ثابت أسفله: زرّ الدور يمين («الإدارة» ذهبي، «عائلتي»/«طلب إضافة» أخضر — يفتح مربّع الإجراءات)
/// و«إغلاق» يسار، بمقاس واحد.
/// (داخلي لا خاص — تفتحه أداة التصوير أيضاً بعيّنة، فيُفحص المربّع نفسه بلا شجرة)
struct WomanDetailSheet: View {
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
    /// من مجال المراجعة (`canModerate`) — ابنه الذي يضيفه من «عائلتي» لا ينتظر اعتماداً
    var canModerate: Bool = false
    /// يُستدعى بعد أي إضافة/تعديل/حذف لإعادة تحميل الشجرة.
    var onChanged: (() async -> Void)? = nil
    /// يفتح تفاصيل عضو آخر (مثلاً بروفايل الزوجة بعد ربطها من العائلة).
    var onOpenMember: ((UUID) -> Void)? = nil
    /// يفتح «أبناء» على ابنة لكل اسم (الاسم مملوء) فور الظهور — من تنبيه «شجرة العائلة للرجال فقط» أو الانتقال التلقائي
    /// لاسم بنت (`FamilyTreeMenOnly`، طلب المالك ٢٠٢٦-١١-٢٧). nil = التفاصيل كما هي
    var startsDaughterAdd: [String]? = nil
    /// الانتقال التلقائي من مربّع ابن: سطر «انتقلنا لشجرة النساء…» أعلى «أبناء» و«هو ولد؟ ارجع»
    var autoMove: WomenTreeAutoMove? = nil
    @State private var startedDaughterAdd = false
    @Environment(\.dismiss) private var dismiss
    /// الشجرة العامة (لمعرفة من منها) ونقل الجنس وإضافة الابن من «عائلتي»
    @EnvironmentObject private var memberVM: MemberViewModel
    /// «طلب إضافة» يصل للإدارة (tree_edit)
    @EnvironmentObject private var adminRequestVM: AdminRequestViewModel

    /// حجم المربّع: مصغّر = صورة+اسم+قرابة+عمر فقط، موسّع = كل المعلومات.
    @State private var isExpanded = false
    /// نتيجة صلة القرابة داخل المربّع (بانر).
    @State private var kinshipText: String? = nil
    /// قسم «العائلة» مطويّ ومغلق بالبداية (طلب المالك ٢٠٢٦-١١-٠٦)
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
    @State private var wifeSearch = ""
    /// «زوج من خارج العائلة» (أبناء البنات، ٢٠٢٦-١١-٠٧) — مربّع الاسم والوفاة فوق مربّع الإجراءات
    @State private var showOutsideHusband = false
    /// «الزوج»: من العائلة أو من خارجها (طلب المالك ٢٠٢٦-١١-١٢ «يحدد الزوج من العائلة او خارجها»)
    @State private var showHusbandSource = false
    /// طلب «زوج من خارج العائلة» (لغير الإدارة) — مربّع الاسم
    @State private var showOutsideHusbandRequest = false
    @State private var outsideHusbandName = ""
    /// «طلب حذف» لبنته أو زوجته (§11) — تأكيد «عائلتي» ثم الدالة الذاتية (طلب للمالك والمدير)
    @State private var confirmSelfRemoval = false
    /// طلبات تعديل البيانات في «الطلبات» (الشكل «أ»، قرار المالك ٢٠٢٦-١١-١٧) — مربّع الطلب المفتوح
    @State private var editRequest: WomanEditRequest? = nil
    /// «إضافة صورة» لزوج البنت من خارج العائلة (بند ١٥): حسابه — يفتح مربّع اقتراح الصورة نفسه (`TreeEditRequestView`)
    @State private var photoRequestFor: OutsideHusbandPhoto? = nil
    /// «الطلبات المرسلة» من «تابِعه» أو خانة «طلبك قيد المراجعة» (بطاقة «AB»، البندان ٥ و٧)
    @State private var showSentRequests = false
    /// «اتصال / واتساب» من صفّ «الهاتف» (الإدارة وهي نفسها) — نفس بطاقة الرجل
    @State private var phoneActionsNumber: String? = nil
    @Environment(\.openURL) private var openURL

    enum AddKind: Int, Identifiable {
        /// «ابن» — إجراء واحد وكل اسم داخله ذكر أو أنثى (طلب المالك ٢٠٢٦-١٠-٢٥ «خلها مسمى ابن وداخل المربع
        /// في اختيار ذكر او انثى»)، وأكثر من اسم في المرّة. `sister` = «إضافة أخت» للعضو على عقدة أبيه
        case child, wife, mother, sister
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .child: return L10n.t("إضافة أبناء", "Add children")
            case .wife: return L10n.t("إضافة زوجة", "Add wife")
            case .mother: return L10n.t("إضافة أم", "Add mother")
            case .sister: return L10n.t("إضافة أخت", "Add sister")
            }
        }
        /// عنوان الطلب في مسار «من أين أُرسل» — بالعربية دائماً (بيانات تقرؤها الإدارة)
        var sourceTitle: String {
            switch self {
            case .child: return "طلب إضافة أبناء"
            case .wife: return "طلب إضافة زوجة"
            case .mother: return "طلب إضافة أم"
            case .sister: return "طلب إضافة أخت"
            }
        }
        /// عنوان مربّع «طلب إضافة» (لمن لا يضيف مباشرة)
        var requestTitle: String {
            switch self {
            case .child: return L10n.t("طلب إضافة أبناء", "Request children")
            case .wife: return L10n.t("طلب إضافة زوجة", "Request a wife")
            case .mother: return L10n.t("طلب إضافة أم", "Request a mother")
            case .sister: return L10n.t("إضافة أخت", "Add sister")
            }
        }
        /// سطر «لمن» في بطاقة السياق أعلى المربّع
        var contextLabel: String {
            switch self {
            case .child: return L10n.t("ابن أو ابنة لـ", "A son or daughter of")
            case .wife: return L10n.t("زوجة لـ", "A wife of")
            case .mother: return L10n.t("أم لـ", "The mother of")
            case .sister: return L10n.t("أختك — بنت أبيك", "Your sister — your father's daughter")
            }
        }
        /// عنوان قسم الأسماء
        var entriesTitle: String {
            switch self {
            case .child: return L10n.t("الأبناء", "Children")
            case .wife: return L10n.t("الزوجة", "Wife")
            case .mother: return L10n.t("الأم", "Mother")
            case .sister: return L10n.t("الأخوات", "Sisters")
            }
        }
        /// اسم الصفّ بجنسه («ابن ١»، «ابنة ٢»…)
        func rowLabel(_ entry: DSAddEntry) -> String {
            switch self {
            case .child: return entry.isFemale ? L10n.t("ابنة", "Daughter") : L10n.t("ابن", "Son")
            case .wife: return L10n.t("اسم الزوجة", "Wife's name")
            case .mother: return L10n.t("اسم الأم", "Mother's name")
            case .sister: return L10n.t("أخت", "Sister")
            }
        }
        /// الابن والأخت أكثر من اسم في المرّة (طلب المالك ٢٠٢٦-١٠-٢٥)
        var allowsMultiple: Bool { self == .child || self == .sister }
        /// أيقونة رأس مربّع الإضافة
        var icon: String {
            switch self {
            case .child: return "person.crop.circle.badge.plus"
            case .wife: return "heart.fill"
            // "figure.dress" ليس رمزاً في SF Symbols — كانت الدائرة تظهر فارغة
            case .mother, .sister: return "figure.stand.dress"
            }
        }
    }

    /// آلية الإضافة والربط حسب الدور (طلب المالك ٢٠٢٦-١٠-٢٤ «نظّم لي الآلية»)
    enum ActionMode {
        /// المالك/المدير/المراقب: إضافة وربط مباشر + إدارة السجل
        case direct
        /// العضو على عقدته هو: زوجته وأبناؤه وأمه مباشرة بدوال السيرفر الذاتية
        case selfFamily
        /// أي عضو مفعّل غيره: «طلب إضافة» يصل للإدارة (tree_edit) — وعلى عقدة أبيه «إضافة أخت» مباشرة
        case request
        /// غير مفعّل: عرض فقط
        case viewOnly
    }

    private var mode: ActionMode {
        if canEdit { return .direct }
        guard isActiveMember else { return .viewOnly }
        // حساب المرأة: دوال `*_self_*` للرجال (عقدة بمعرّف الحساب) — تعديل عائلتها بطلب للإدارة
        if me?.isWomanAccount == true { return .request }
        // ابن البنت: عقدته ليست بمعرّف حسابه — عائلته بطلب للإدارة مثل حساب المرأة
        if LineageGateStore.shared.status?.flagged == true { return .request }
        return isMyNode ? .selfFamily : .request
    }

    /// عضو مفعّل يرسل الطلبات (السيرفر يشترط is_approved_member — والرفض يُعرض إن حدث)
    private var isActiveMember: Bool {
        guard let me, me.role != .pending else { return false }
        if let s = me.status, s == .frozen || s == .deleted || s == .pending { return false }
        return true
    }

    /// عقدة المستخدم نفسه (نفس معرّفه، أو المرتبطة بحسابه) — مجال دوال `*_self_*`
    private var isMyNode: Bool {
        guard let me else { return false }
        return woman.id == me.id || WomenStore.womanByLinkedUser[me.id] == woman.id
    }

    /// حساب زوج البنت من خارج العائلة الذي تقترح له زوجته أو ابنه صورة (بند ١٥، المالك «خله عن طريق زوجته أو ابنه
    /// المضاف مع طلب أو هو بنفسه») — nil لغيرهما، وللنساء، ولمن لا حساب له (الصورة تُطبَّق على `profiles` عند القبول)
    private var outsideHusbandPhotoAccount: OutsideHusbandPhoto? {
        guard let me else { return nil }
        let myNode = WomenStore.womanByLinkedUser[me.id] ?? me.id
        let mine = allWomen.first { $0.id == myNode }
        let linked = WomenStore.linkedUserByWoman[woman.id] ?? (profileIds.contains(woman.id) ? woman.id : nil)
        guard let target = MemberCardLogic.outsideHusbandPhotoTarget(
            nodeId: woman.id, nodeIsMale: !woman.isFemale, nodeIsOutside: WomenStore.outsideFamilyIds.contains(woman.id),
            linkedProfile: linked, viewer: me.id,
            viewerIsWife: mine?.husbandId == woman.id,
            viewerIsSon: mine?.fatherId == woman.id) else { return nil }
        // بلا حساب: الطلب على عقدته في شجرة النساء نفسها
        if target.womenNode { return OutsideHusbandPhoto(member: woman, womenNode: true) }
        return memberVM.allMembers.first { $0.id == target.id }.map { OutsideHusbandPhoto(member: $0, womenNode: false) }
    }

    /// عقدة أبي المستخدم — منها «إضافة أخت» (لا من الملف الشخصي — طلب المالك ٢٠٢٦-١٠-٢٤)
    private var isMyFatherNode: Bool {
        guard let fid = me?.fatherId else { return false }
        return woman.id == fid && !woman.isFemale
    }

    /// معرّفات الشجرة العامة (profiles) — الذكر منها يُكتب هناك وينعكس هنا بنفس المعرّف
    private var profileIds: Set<UUID> { Set(memberVM.allMembers.map(\.id)) }

    private var husband: FamilyMember? {
        guard let hid = woman.husbandId else { return nil }
        return allWomen.first { $0.id == hid }
    }
    /// زوجات العضو الذكر (husband_id == العضو).
    private var wives: [FamilyMember] {
        let orders = WomenStore.wifeOrderByWoman   // «ترتيب الزوجات» (`wife_order`) ثم الترتيب القديم
        return allWomen.filter { $0.husbandId == woman.id }
            .sorted { WomenStore.wifeOrdered($0, $1, orders: orders) }
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
        let orders = WomenStore.wifeOrderByWoman
        return allWomen.filter { $0.husbandId == fid }
            .sorted { WomenStore.wifeOrdered($0, $1, orders: orders) }
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
    /// عقدتها هي — ومنها حساب المرأة المربوط (`isMyNode`): ترى زوجها ولا «صلة قرابة» بنفسها
    private var isViewingSelf: Bool { woman.id == me?.id || isMyNode }

    /// خصوصية الأنثى: زوجها لا يُعرض للعضو العادي — تراه الإدارة، وهي نفسها،
    /// وزوجها (فبطاقته تعرض «الزوجة» أصلاً).
    private var showHusband: Bool {
        guard husband != nil else { return false }
        return canEdit || isViewingSelf || husband?.id == me?.id
    }

    /// الأب أو الأم أو الزوجة/الزوج (حسب الخصوصية) — صفّ العلاقات في «العائلة» (البند ٨: الأب داخل «العائلة»)
    private var hasRelations: Bool { father != nil || mother != nil || !wives.isEmpty || showHusband }
    /// هل في التفاصيل ما يُعرض؟ — بلا شيء لا يظهر زر «عرض التفاصيل»
    private var hasDetails: Bool {
        hasRelations || !children.isEmpty || !infoRows.isEmpty || requestsMode != .none
    }

    var body: some View {
        // مربّع بالمنتصف قابل للتوسّع بدل الشيت — يُغلق بـ«إغلاق» أو بالضغط خارجه
        DSExpandableCenterPanel(isExpanded: $isExpanded, onClose: { dismiss() }) {
            detailsStack
        }
        .onAppear(perform: openDaughterAddIfAsked)
    }

    /// مربّع الإجراءات ثم «أبناء» بابنة واحدة — نفس مسار «إضافة بنت» بآلية الدور (مباشر · عائلتي · طلب)
    private func openDaughterAddIfAsked() {
        guard let names = startsDaughterAdd, !startedDaughterAdd, mode != .viewOnly else { return }
        startedDaughterAdd = true
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.boxHandoff) {
            showAdminBox = true
            DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.boxHandoff) {
                startAdd(.child)
                let daughters = (names.isEmpty ? [""] : names).map { name -> DSAddEntry in
                    var daughter = DSAddEntry(gender: "female")
                    daughter.name = name
                    return daughter
                }
                draft.addEntries = daughters
            }
        }
    }

    /// «هو ولد؟ ارجع»: يغلق المربّعات وشجرة النساء بلا كتابة — ومربّع الابن تحتها كما هو
    private func backToSon() {
        autoMove?.onBack()
        draft.closeBoxes()
        showAdminBox = false
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.panelOutDuration) { dismiss() }
    }

    /// سطر الانتقال التلقائي أعلى «أبناء» — لماذا نحن هنا، والرجوع
    private func autoMoveBanner(_ move: WomenTreeAutoMove) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSNoteCard(move.notice, icon: "figure.stand.dress", tint: DS.Color.female)
            DSChipButton(move.backTitle, icon: "arrow.uturn.backward", tint: chromeInk, size: .small) {
                backToSon()
            }
            .accessibilityHint(L10n.t("يرجع لمربّع الابن كما هو", "Returns to the son form as it was"))
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
            // مربّع أوامر موحّد (`DSComposer` + `DSCommandRow`) بدل قائمة النظام (طلب المالك ٢٠٢٦-١١-١٠)
            .dsCenterBox(isPresented: $showWifeNav, onBackgroundTap: { showWifeNav = false }) {
                DSComposer(title: L10n.t("الزوجات", "Wives"),
                           subtitle: L10n.t("اختر الزوجة لعرض بياناتها", "Pick a wife to open her details"),
                           icon: "heart.fill", tint: DS.Color.actionNavy,
                           actionTitle: "", showsAction: false, canSubmit: false,
                           onSubmit: {}, onCancel: { showWifeNav = false }) {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(wives) { w in
                            DSCommandRow(title: w.fullName.isEmpty ? w.firstName : w.fullName, icon: "person.fill") {
                                showWifeNav = false
                                // بعد خروج المربّع — نافذة واحدة في كل مرّة
                                DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.panelOutDuration + 0.15) {
                                    onOpenMember?(w.id)
                                }
                            }
                        }
                    }
                }
            }
            // نتيجة «طلب إضافة» / إضافة تنتظر الاعتماد — «حسناً» يغلق التفاصيل (الشجرة خلفها مُحدّثة)
            .dsAlert(draft.notice?.title ?? "",
                     isPresented: Binding(get: { draft.notice != nil },
                                          set: { if !$0 { draft.notice = nil } }),
                     moment: .sentForApproval) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) { draft.notice = nil; dismiss() }
            } message: {
                Text(draft.notice?.message ?? "")
            }
    }

    /// نوافذ الإدارة تُفتح فوق مربّع الإجراءات نفسه (لا من التفاصيل) — فـ«إلغاء» يرجع إليه
    private func withAdminPresentations<Box: View>(_ box: Box) -> some View {
        box
            // «إدارة السجل» — مربّع طويل من الأسفل مثل «إدارة السجل» في شجرة العائلة (توصية أبل للنماذج الطويلة)
            .dsTallBox(isPresented: $draft.showEdit) { WomanDraftScope(draft: draft) { editBox } }
            // «ترتيب الأبناء» — مربّعه
            .dsCenterBox(isPresented: $draft.showReorder) { WomanDraftScope(draft: draft) { reorderBox } }
            // «ترتيب الزوجات» — نفس مربّع ترتيب الأبناء
            .dsCenterBox(isPresented: $draft.showWifeReorder) { WomanDraftScope(draft: draft) { wifeReorderBox } }
            // إضافة (ابن أو ابنة / زوجة / أم) — مربّع واحد بنفس «إضافة ابن» في شجرة العائلة
            .dsCenterBox(item: $draft.addKind) { kind in WomanDraftScope(draft: draft) { addBox(kind) } }
            // «إضافة زوجة» الواحدة (لعقدة ذكر، طلب المالك ٢٠٢٦-١٠-٢٥ «ادمج ربط الزوجة مع اضافة زوجة»): من أين ←
            // من العائلة (أبوها ← بناته المتاحات، أو تُضاف تحته) أو من خارجها (مربّع الاسم)
            .dsCenterBox(isPresented: $draft.showWifeFlow) { WomanDraftScope(draft: draft) { wifeFlowBox } }
            // «زوج من خارج العائلة» (أبناء البنات) — الاسم والوفاة، ثم تُضاف عيالها من «الأبناء» تحته
            .dsCenterBox(isPresented: $showOutsideHusband) {
                OutsideHusbandBox(woman: woman,
                                  onDone: {
                                      showOutsideHusband = false
                                      showAdminBox = false
                                      await onChanged?()
                                  },
                                  onCancel: { showOutsideHusband = false })
            }
            // «الزوج»: من أين؟ — من العائلة (المنتقي) أو من خارجها (مربّع الاسم للإدارة، أو طلب بالاسم لغيرها)
            .dsCenterBox(isPresented: $showHusbandSource) {
                HusbandSourceBox(womanName: displayName(woman), isRequest: mode == .request,
                                 onFamily: { handOff(from: { showHusbandSource = false }) { openHusbandPicker() } },
                                 onOutside: {
                                     handOff(from: { showHusbandSource = false }) {
                                         if mode == .direct { showOutsideHusband = true }
                                         else { outsideHusbandName = ""; showOutsideHusbandRequest = true }
                                     }
                                 },
                                 onCancel: { showHusbandSource = false })
            }
            .dsCenterBox(isPresented: $showOutsideHusbandRequest) {
                OutsideHusbandRequestBox(womanName: displayName(woman), name: $outsideHusbandName,
                                         isBusy: draft.busy,
                                         onSend: { sendOutsideHusbandRequest() },
                                         onCancel: { showOutsideHusbandRequest = false })
            }
            // اختيار زوج من العائلة (لعقدة أنثى) — فوق مربّع الإجراءات نفسه: كان مربوطاً بالتفاصيل
            // ولا شيء يفتحه، وفتحه من التفاصيل والإجراءات مفتوحة لا يظهر أصلاً
            .dsCenterBox(isPresented: $draft.showHusbandPicker) {
                DSMemberPickerBox(
                    title: mode == .request ? L10n.t("طلب ربط زوج", "Request linking a husband")
                                            : L10n.t("اختيار زوج من العائلة", "Choose husband"),
                    subtitle: displayName(woman),
                    candidates: husbandCandidates,
                    search: $wifeSearch,
                    emptyTitle: L10n.t("لا يوجد ذكور في الشجرة", "No family men"),
                    selectedId: woman.husbandId,
                    onPick: { pickHusband($0) },
                    onCancel: { draft.showHusbandPicker = false; wifeSearch = "" })
            }
            // اختيار الأم من زوجات الأب — نفس المربّع، والمختارة حالياً بعلامة ✓
            .dsCenterBox(isPresented: $draft.showMother) {
                DSMemberPickerBox(
                    title: L10n.t("الأم", "Mother"),
                    subtitle: mother.map { L10n.t("الحالية: ", "Current: ") + displayName($0) }
                        ?? L10n.t("اختر أمّ العضو من زوجات الأب", "Pick the mother from the father's wives"),
                    icon: "figure.and.child.holdinghands",
                    candidates: fatherWives,
                    search: $wifeSearch,
                    emptyTitle: L10n.t("لا توجد زوجات للأب في الشجرة", "The father has no wives in the tree"),
                    selectedId: woman.motherId,
                    removeTitle: woman.motherId != nil ? L10n.t("إزالة الأم", "Remove mother") : nil,
                    onRemove: { setMother(nil) },
                    // «الأم» مدخل واحد: الأم غير موجودة بين زوجات الأب ← إضافتها من هنا
                    missingTitle: canAddMother && !fatherWives.isEmpty
                        ? L10n.t("ليست في القائمة؟ إضافة أم جديدة", "Not listed? Add a new mother") : nil,
                    onMissing: canAddMother ? { _ in motherPickerToAdd() } : nil,
                    // العضو: الاختيار طلب للإدارة (يُنفَّذ تلقائياً عند القبول)، والإدارة و«عائلتي» كتابة مباشرة
                    onPick: { m in
                        if mode == .request { sendMotherRequest(m) } else { setMother(m.id) }
                    },
                    onCancel: { draft.showMother = false; wifeSearch = "" })
            }
            // حذف
            .dsAlert(L10n.t("حذف العضو؟", "Delete member?"), isPresented: $draft.showDelete) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) { performDelete() }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            } message: {
                Text(L10n.t("سيُحذف نهائيًا من شجرة النساء.", "This removes them from the women tree."))
            }
            // تغيير الجنس = نقل بين الشجرتين (move_child_gender) — بتأكيد
            .dsAlert(genderChangeTitle + "؟", isPresented: $draft.showGender) {
                Button(L10n.t("تغيير", "Change")) { performGenderChange() }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            } message: {
                Text(genderChangeMessage)
            }
            // (مصدر الزوجة سؤال داخل مربّعها لا قائمة منبثقة — كان «اختيار من العائلة» يفتح مربّعه والقائمة
            // تُغلق في اللحظة نفسها فلا يظهر شيء)
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
        // أرضية «AB» الكريمية الخفيفة (كحلي الرأس في الداكن)
        .background(DS.MemberCard.boxBackground)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { if !isViewingSelf { await adminRequestVM.fetchMyPendingRequests() } }
        .dsTallBox(isPresented: $showSentRequests) {
            MemberCardSentRequestsBox(onClose: { showSentRequests = false })
        }
        .dsAlert(L10n.t("التواصل", "Contact"),
                 isPresented: Binding(get: { phoneActionsNumber != nil },
                                      set: { if !$0 { phoneActionsNumber = nil } }),
                 icon: "phone.fill") {
            if let url = KuwaitPhone.telURL(phoneActionsNumber) {
                Button(L10n.t("اتصال", "Call")) { openURL(url) }
            }
            if let url = KuwaitPhone.whatsappURL(phoneActionsNumber) {
                Button(L10n.t("واتساب", "WhatsApp")) { openURL(url) }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
        } message: {
            Text(verbatim: "\u{2066}\(KuwaitPhone.display(phoneActionsNumber))\u{2069}")
        }
    }

    /// رأس ملوّن مثل مربّعات الإضافة (فوق الصورة، بلا تداخل) — نفس رأس تفاصيل العضو
    private var womanHeaderBand: some View {
        // زرّ × في طرف الرأس يغلق المربّع (طلب المالك ٢٠٢٦-١١-٠٧) — مثل بقية المربّعات، و«إغلاق» السفلي باقٍ
        DSPanelCloseReader { close in
            DSComposerHeader(
                title: L10n.t("تفاصيل العضو", "Member Details"),
                subtitle: L10n.t("من شجرة النساء", "From the women's tree"),
                icon: "person.text.rectangle.fill",
                tint: woman.isDeceased == true ? DS.Color.textSecondary : DS.Color.actionNavy,
                onClose: close
            )
        }
        // «AB»: خط ذهبي رفيع تحت الرأس الكحلي
        .overlay(alignment: .bottom) { MemberCardBandHairline() }
        // علم دولة الرقم (غير الكويت) في زاوية الرأس — نفس تفاصيل العضو في شجرة العائلة، قبل زرّ × لا تحته
        .overlay(alignment: .trailing) {
            DSPhoneCountryBadge(phone: shownPhone)
                .padding(.leading, DS.Spacing.lg)
                .padding(.trailing, DS.Theme.isCalm ? DS.Spacing.lg : DSFamilyKit.badgeInsetWithClose)
        }
        // السحب لأسفل على الرأس يصغّر المربّع الموسّع
        .dsDetailsSwipe(collapses: isExpanded) { _ in setExpanded(false) }
    }

    /// رقم صاحب العقدة إن كان يحقّ للمشاهد رؤيته — من الشجرة العامة: الرجل بمعرّفه، والمرأة بحسابها المربوط
    /// (سجلّات شجرة النساء بلا أرقام)
    private var visiblePhone: String? {
        linkedProfile?.dsVisiblePhone(viewerId: me?.id, viewerCanModerate: canModerate)
    }

    /// ملف الشجرة العامة لصاحب العقدة: الرجل بمعرّفه، والمرأة بحسابها المربوط
    private var linkedProfile: FamilyMember? {
        memberVM.member(byId: woman.id)
            ?? WomenStore.linkedUserByWoman[woman.id].flatMap { memberVM.member(byId: $0) }
    }

    /// البند ٨: صفّ الرقم بقاعدة `MemberCardLogic.phoneRow` — رقم المرأة لا يراه العضو أبداً (لا صفّ ولا «مخفي»)
    private var phoneRow: MemberCardLogic.PhoneRow {
        MemberCardLogic.phoneRow(hasPhone: visiblePhone != nil, isFemale: woman.isFemale,
                                 isPhoneHidden: linkedProfile?.isPhoneHidden == true,
                                 isDeceased: woman.isDeceased == true,
                                 viewerIsSelf: isViewingSelf, viewerIsStaff: canModerate)
    }

    /// الرقم الظاهر للمشاهد فعلاً (للعلم في الرأس وصفّ «الهاتف»)
    private var shownPhone: String? {
        if case .shown = phoneRow { return visiblePhone }
        return nil
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

            // المخفيّة تراها الإدارة وحدها (السيرفر يخفيها عن الأعضاء): من أخفاها ومتى
            if woman.isHiddenFromTree, canModerate {
                hiddenBanner
                    .padding(.horizontal, DS.Spacing.lg)
            }

            if hasDetails {
                detailsToggleButton
                    .padding(.horizontal, DS.Spacing.lg)
                    .dsStaggerIn(2)
            }
        }
        // السحب لأعلى يوسّع المربّع (مع الزرّ لا بدله) — مثل تفاصيل العضو في شجرة العائلة
        .dsDetailsSwipe(expands: hasDetails && !isExpanded) { _ in setExpanded(true) }
    }

    /// «عرض التفاصيل» / «إخفاء التفاصيل» — الزرّ نفسه في الشجرتين (`DSDetailsToggle`، طلب المالك ٢٠٢٦-١٠-٢٤
    /// «شنو سويت عرض التفاصيل؟»): زرّ واضح بسهم يدور مع التوسيع
    private var detailsToggleButton: some View {
        DSDetailsToggle(isExpanded: isExpanded, tile: true, tint: DS.Color.actionNavy) { setExpanded(!isExpanded) }
    }

    /// التوسيع والتصغير بنابض ارتفاع المربّع نفسه — «تقليل الحركة»: مباشرة
    private func setExpanded(_ on: Bool) {
        guard on != isExpanded else { return }
        withAnimation(reduceMotion ? nil : DS.Anim.smooth) { isExpanded = on }
    }

    /// جسم التفاصيل: العائلة (تدخل عند «عرض التفاصيل») — بلا تواريخ كما كان شيت النساء
    /// أصلاً (العمر في الحبّة فقط). الإدارة صارت مربّعاً مستقلاً من الشريط السفلي.
    private var detailsBody: some View {
        let open = isExpanded
        // البند ٨: «المعلومات» (الميلاد، الوفاة، الهاتف بقاعدته) ثم «العائلة» بالأب — مثل بطاقة الرجل
        return VStack(spacing: DS.Spacing.md) {
            infoSection
                .dsStaggerWhen(0, active: open)

            familySection
                .dsStaggerWhen(1, active: open)

            // الإدارة: ظهور زوجها من خارج العائلة وأبنائها منه (قرار المالك ٢٠٢٦-١١-٢٨)
            if WomenStore.visibilitySupported,
               MotherVisibilityLogic.adminShowsToggles(canEdit: canEdit, isFemale: woman.isFemale,
                                                       husbandId: woman.husbandId,
                                                       outsideIds: WomenStore.outsideFamilyIds) {
                WomanVisibilityAdminSection(womanId: woman.id, onChanged: onChanged)
                    .dsStaggerWhen(2, active: open)
            }

            pendingRequestsCard
                .dsStaggerWhen(3, active: open)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - «طلبات معلّقة» (طلب المالك ٢٠٢٦-١١-٢٦ «ارتباط واضح بالوارد»)

    /// البند ٧: «طلبك عنها» = طلباتك أنت على عقدتها مع «تابِعه» (العضو والمشرف)؛ القائمة كاملة لمن يقرّر طلبات الشجرة
    /// (`canEdit` = `canModerateTree`) وكل طلب يفتح في «الوارد»
    @ViewBuilder
    private var pendingRequestsCard: some View {
        let mode = requestsMode
        MemberCardRequestsSection(
            requests: mode == .all ? allRequestsOnNode : myRequestsOnNode,
            mode: mode,
            female: woman.isFemale,
            onOpen: { request in
                if mode == .all { MemberPendingRequestsLink.open(request) { dismiss() } } else { showSentRequests = true }
            }
        )
    }

    private var allRequestsOnNode: [AdminRequest] {
        adminRequestVM.treeEditRequests.filter { $0.treeEditPayload?.womenNodeId == woman.id }
    }

    private var myRequestsOnNode: [AdminRequest] {
        let ids = Set(myRequestRefs.map(\.id))
        return adminRequestVM.myPendingRequests.filter { ids.contains($0.id) }
    }

    private var myRequestRefs: [MemberCardLogic.RequestRef] {
        MemberCardLogic.mineInWomen(adminRequestVM.myPendingRequests.map(MemberDetailsView.ref),
                                    nodeId: woman.id, viewer: me?.id)
    }

    private var requestsMode: MemberCardLogic.RequestsSection {
        MemberCardLogic.requestsSection(canModerateTree: canEdit, allCount: allRequestsOnNode.count,
                                        mineCount: myRequestsOnNode.count)
    }

    // MARK: «المعلومات» (البند ٨)

    private struct InfoRow: Identifiable {
        let id: String
        let icon: String
        let label: String
        let value: String
        var tint: Color = DS.Color.sea
        var phone: String? = nil
        var caption: String? = nil
    }

    /// الميلاد، الوفاة (السنة)، والهاتف بقاعدته — نفس صفوف بطاقة الرجل
    private var infoRows: [InfoRow] {
        var rows: [InfoRow] = []
        let deceased = woman.isDeceased == true
        if let birth = woman.birthDate, !birth.isEmpty {
            let hidden = woman.isBirthDateHidden == true && !isViewingSelf && !canModerate
            rows.append(InfoRow(id: "birth", icon: "calendar", label: L10n.t("الميلاد", "Birth"),
                                value: hidden ? L10n.t("مخفي", "Hidden")
                                    : (deceased ? (year(birth) ?? birth) : (DateHelper.displayDate(birth) ?? birth)),
                                tint: hidden ? DS.Color.textTertiary : DS.Color.primary))
        }
        if deceased, let death = woman.deathDate, !death.isEmpty {
            rows.append(InfoRow(id: "death", icon: "calendar.badge.minus", label: L10n.t("الوفاة", "Death"),
                                value: year(death) ?? death, tint: DS.Color.textTertiary))
        }
        switch phoneRow {
        case .shown(let hiddenCaption):
            if let phone = visiblePhone {
                rows.append(InfoRow(id: "phone", icon: "phone.fill", label: L10n.t("الهاتف", "Phone"),
                                    value: KuwaitPhone.display(phone), phone: phone,
                                    caption: hiddenCaption ? L10n.t("مخفي عن الأعضاء", "Hidden from members") : nil))
            }
        case .hiddenWord:
            rows.append(InfoRow(id: "phone", icon: "phone.fill", label: L10n.t("الهاتف", "Phone"),
                                value: L10n.t("مخفي", "Hidden"), tint: DS.Color.textTertiary))
        case .none:
            break
        }
        return rows
    }

    @ViewBuilder
    private var infoSection: some View {
        let rows = infoRows
        if !rows.isEmpty {
            MemberCardSection(title: L10n.t("المعلومات", "Info"), icon: "person.text.rectangle.fill",
                              fill: DS.Color.seaFill) {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(rows) { row in
                        let body = MemberCardInfoRow(icon: row.icon, label: row.label, value: row.value, tint: row.tint,
                                                     ltr: row.phone != nil, lockCaption: row.caption,
                                                     tappable: row.phone != nil)
                        if let phone = row.phone {
                            Button { phoneActionsNumber = phone } label: { body }
                                .buttonStyle(DSPressStyle())
                                .accessibilityHint(L10n.t("اضغط للاتصال أو المراسلة عبر واتساب",
                                                          "Tap to call or message on WhatsApp"))
                        } else {
                            body
                        }
                    }
                }
            }
        }
    }

    // MARK: - Compact Hero

    private var compactHeroSection: some View {
        VStack(spacing: DS.Spacing.md) {
            // (بلا توهّج مموّه خلف الصورة — نفس تفاصيل العضو)
            ZStack {
                avatar(woman, size: DS.Icon.memberHero)
                    // المتوفّى الذكر بالأبيض والأسود — والأنثى بلونها (نفس شجرة النساء)
                    .saturation(woman.isDeceased == true && !woman.isFemale ? 0 : 1)
                    // «AB»: فراغ بلون الأرضية ثم خط ذهبي رفيع وظلّ خفيف
                    .memberCardAvatarFrame(side: DS.Icon.memberHero)
                    .scaleEffect(heroIn || reduceMotion ? 1 : 0.6)
                    .opacity(heroIn ? 1 : 0)
                    .accessibilityHidden(true)   // الصورة زخرفة — الاسم تحتها

                if woman.isDeceased == true {
                    Circle()
                        .fill(DS.Color.background)
                        .frame(width: DS.Icon.rowLarge, height: DS.Icon.rowLarge)
                        .overlay(
                            Image(systemName: "leaf.fill")
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

            DSBalancedText(displayName(woman))
                .dsFont(.memberNameTitle)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, DS.Spacing.lg)
                .offset(y: heroIn || reduceMotion ? 0 : 10)
                .opacity(heroIn ? 1 : 0)
            // زخرفة «AB» تحت الاسم: خط ذهبي في وسطه معيّن
            MemberCardOrnament()
                .opacity(heroIn ? 1 : 0)
            // طلب حذف معلّق من المشاهد عليها (§11)
            if showsDeleteRequest && deletionPending {
                DSStatusChip(text: SelfRemovalText.pendingChip, tint: DS.Color.slate, size: .mini)
            }

            // «من خارج العائلة» / «ابن بنت» (أبناء البنات من خارج العائلة، ٢٠٢٦-١١-٠٧)
            if WomenStore.outsideFamilyIds.contains(woman.id) {
                DSStatusChip(text: DaughterSons.text("outside_tag", "من خارج العائلة", "Outside the family"),
                             icon: "person.badge.plus", tint: DS.Color.slate, size: .mini)
                    .opacity(heroIn ? 1 : 0)
            } else if !woman.isFemale, WomenStore.linkedUserByWoman[woman.id] != nil,
                      let f = woman.fatherId, WomenStore.outsideFamilyIds.contains(f) {
                DSStatusChip(text: DaughterSons.text("son_tag", "ابن بنت", "Daughter's son") + L10n.t(" · له حساب", " · has an account"),
                             icon: "checkmark.seal.fill", tint: DS.Color.female, size: .mini)
                    .opacity(heroIn ? 1 : 0)
            }
            // «لها حساب» — امرأة مربوطة بحساب في التطبيق (دخول النساء)
            if woman.isFemale && WomenStore.linkedUserByWoman[woman.id] != nil {
                DSStatusChip(text: L10n.t("لها حساب", "Has an account"), icon: "checkmark.seal.fill",
                             tint: DS.Color.success, size: .mini)
                    .opacity(heroIn ? 1 : 0)
            }
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
                             tint: DS.Color.palm,   // الهوية: القرابة أخضر العائلة (لا لون حالة) — مثل شجرة العائلة
                             size: .small, action: computeKinship)
            }
            agePill
        }
    }

    /// حبّة العمر — تظهر جنب زر القرابة. للمتوفّاة: رمادي + رمز يوضّح الوفاة. «5 سنوات» بعربي صحيح (البند ٩)
    @ViewBuilder
    private var agePill: some View {
        let isDeceased = woman.isDeceased == true
        if let age = womanAge {
            MemberCardStaticChip(text: MemberCardLogic.yearsText(age),
                                 icon: isDeceased ? "leaf.fill" : "timelapse",
                                 tint: isDeceased ? DS.Color.textSecondary : DS.Color.info,
                                 trailing: isDeceased ? "· " + L10n.t(woman.isFemale ? "متوفّاة" : "متوفّى", "deceased") : nil)
        }
    }

    /// العمر المسجّل (حبّة العمر، وقاعدة «بنت أقل من 13» في «طلب تعديل»)
    private var womanAge: Int? {
        MemberCardLogic.age(birth: woman.birthDate, death: woman.deathDate, deceased: woman.isDeceased == true,
                            nowYear: Calendar.current.component(.year, from: Date()))
    }

    /// «مخفية عن الأعضاء» — من أخفاها (أبوها/زوجها) ومتى، وما أخفاه أهلها يُظهرونه هم
    /// (اختيار المالك ٢٠٢٦-١١-١٢ «الإدارة تشوف بس»؛ السيرفر يرفض إظهار الإدارة له)
    private var hiddenBanner: some View {
        let info = WomenStore.hiddenInfo[woman.id]
        var lines: [String] = []
        let bySelf = info?.by != nil && (info?.by == WomenStore.linkedUserByWoman[woman.id] || info?.by == woman.id)
        if bySelf {
            lines.append(L10n.t("أخفت نفسها من حسابها", "She hid herself from her account"))
        } else if let by = info?.by {
            let who = memberVM.member(byId: by).map { PersonName.threeParts($0.fullName) } ?? L10n.t("عضو", "a member")
            let rel = by == woman.fatherId ? L10n.t(" (أبوها)", " (her father)")
                : by == woman.husbandId ? L10n.t(" (زوجها)", " (her husband)") : ""
            lines.append(L10n.t("أخفاها: \(who)\(rel)", "Hidden by: \(who)\(rel)"))
        }
        if let at = info?.at, let day = DateHelper.displayDate(String(at.prefix(10))) {
            lines.append(L10n.t("متى: \(day)", "When: \(day)"))
        }
        if info?.byFamily == true {
            lines.append(bySelf
                ? L10n.t("إظهارها منها هي من «تعديل الملف الشخصي».", "Only she can show herself again.")
                : L10n.t("أخفاها أهلها، وإظهارها منهم من «تعديل الملف الشخصي».",
                         "Hidden by her family; only they can show her again."))
        }
        if lines.isEmpty { lines.append(L10n.t("لا يراها الأعضاء في شجرة النساء.", "Members don't see her in the women's tree.")) }
        return DSNoteCard(lines.joined(separator: "\n"),
                          title: L10n.t("مخفية عن الأعضاء", "Hidden from members"),
                          icon: "eye.slash.fill",
                          tint: DS.Color.slate)
    }

    /// نتيجة صلة القرابة — ملاحظة العُدّة الملوّنة بلون القرابة
    private func kinshipBanner(_ text: String) -> some View {
        DSNoteCard(text,
                   title: L10n.t("صلة القرابة", "Kinship"),
                   icon: "point.3.connected.trianglepath.dotted",
                   tint: DS.Color.palm)
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
            // العائلة مطويّة ومغلقة بالبداية (طلب المالك ٢٠٢٦-١١-٠٦): الأم والزوجة بطاقتان أكبر، والأبناء
            // مرقّمون — الذكور ثم الإناث من الأكبر
            // «AB»: لوح كريمي بمربّع أخضر العائلة — مطويّاً صور الأقارب بأدوارهم و«عرض ‹»
            MemberCardFamilyBox(
                summary: familySummary(children: kids.count),
                relatives: stackPeople(children: kids),
                isOpen: $familyOpen,
                face: { m in
                    avatar(m, size: DS.MemberCard.face)
                        .saturation(m.isDeceased == true && !m.isFemale ? 0 : 1)
                        .accessibilityHidden(true)
                }
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

    /// صور «العائلة» مطويّاً بأدوارها: الأب، الأم، الزوجة/الزوجات أو الزوج (بقاعدة خصوصيته)، ثم الأبناء
    private func stackPeople(children kids: [FamilyMember]) -> [MemberCardRelative] {
        var people: [MemberCardRelative] = []
        if let father { people.append(.init(member: father, role: L10n.t("الأب", "Father"))) }
        if let mother { people.append(.init(member: mother, role: L10n.t("الأم", "Mother"))) }
        let w = wives
        if !w.isEmpty {
            people += w.map { .init(member: $0, role: L10n.t("الزوجة", "Wife")) }
        } else if showHusband, let husband {
            // اسمه تحت صورته لا كلمة «الزوج» (مراجعة ٢٠٢٦-١١-٢٧ «الزوج بجانب البنت» ٥)
            people.append(.init(member: husband, role: shortName(husband)))
        }
        return people + kids.map { .init(member: $0, role: shortName($0)) }
    }

    /// «الأم · الزوج · ٣ أبناء» — ملخّص بجانب العنوان والقسم مطويّ
    private func familySummary(children count: Int) -> String {
        var parts: [String] = []
        if father != nil { parts.append(L10n.t("الأب", "Father")) }
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

    /// الأب والأم ثم الزوجة (أو الزوج) — بطاقات بصورة واسم وعمر، الضغط يفتح صاحبها (البند ٨: الأب داخل «العائلة»)
    private var relationsRow: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if let father {
                DSFamilyPersonCard(role: L10n.t("الأب", "Father"), icon: "person.fill",
                                   tint: DS.Color.male, name: shortName(father),
                                   detail: DSMemberAge.detail(father),
                                   onTap: { onOpenMember?(father.id) }) {
                    relationAvatar(father)
                }
            }
            spouseAndMotherRow
        }
    }

    /// الأم + الزوجة (أو الزوج) بطاقتان جنب بعض
    private var spouseAndMotherRow: some View {
        let w = wives
        return HStack(alignment: .top, spacing: DS.Spacing.sm) {
            if let mother {
                DSFamilyPersonCard(role: L10n.t("الأم", "Mother"), icon: "figure.stand.dress",
                                   tint: DS.Color.accent, name: shortName(mother),
                                   detail: DSMemberAge.detail(mother),
                                   onTap: { onOpenMember?(mother.id) }) {
                    relationAvatar(mother)
                }
            }
            if w.count == 1 {
                DSFamilyPersonCard(role: L10n.t("الزوجة", "Wife"), icon: "heart.fill",
                                   tint: DS.Color.female, name: shortName(w[0]),
                                   detail: DSMemberAge.detail(w[0]),
                                   onTap: { onOpenMember?(w[0].id) }) {
                    relationAvatar(w[0])
                }
            } else if w.count > 1 {
                // الزوجات: اختيار عند التعدد كما كان
                DSFamilyPersonCard(role: L10n.t("الزوجات", "Wives") + " · \(w.count)", icon: "heart.fill",
                                   tint: DS.Color.female, name: w.map { shortName($0) }.joined(separator: "، "),
                                   onTap: { showWifeNav = true }) {
                    relationAvatar(w[0])
                }
            } else if showHusband, let husband {
                DSFamilyPersonCard(role: L10n.t("الزوج", "Husband"), icon: "person.fill",
                                   tint: DS.Color.male, name: shortName(husband),
                                   detail: DSMemberAge.detail(husband),
                                   onTap: { onOpenMember?(husband.id) }) {
                    relationAvatar(husband)
                }
            }
        }
    }

    private func relationAvatar(_ m: FamilyMember) -> some View {
        avatar(m, size: DSMemberKit.relationAvatar)
            .saturation(m.isDeceased == true && !m.isFemale ? 0 : 1)
            .accessibilityHidden(true)
    }

    private func shortName(_ m: FamilyMember) -> String {
        m.firstName.isEmpty ? m.fullName : m.firstName
    }

    private func displayName(_ m: FamilyMember) -> String {
        m.fullName.isEmpty ? m.firstName : m.displayFullName
    }

    /// الأبناء مرقّمون من الأكبر بشبكة ثابتة — الذكور ثم الإناث (اختيار المالك ٢٠٢٦-١١-٠٦ «أ»)؛ الضغط يفتح صاحبه
    private func childrenBox(_ kids: [FamilyMember]) -> some View {
        let sons = kids.filter { !$0.isFemale }
        let daughters = kids.filter { $0.isFemale }
        var groups: [DSFamilyChildrenBlock<AnyView>.ChildGroup] = []
        if !sons.isEmpty {
            groups.append(.init(id: "sons", title: L10n.t("الذكور", "Sons"), tint: DS.Color.male, members: sons))
        }
        if !daughters.isEmpty {
            groups.append(.init(id: "daughters", title: L10n.t("الإناث", "Daughters"), tint: DS.Color.female, members: daughters))
        }
        return DSFamilyChildrenBlock(
            groups: groups,
            avatar: { c in
                AnyView(avatar(c, size: DSMemberKit.childAvatar)
                    .saturation(c.isDeceased == true && !c.isFemale ? 0 : 1))
            },
            onTap: onOpenMember.map { open in { c in open(c.id) } })
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

    private func openWifeReorderBox() {
        draft.wivesOrdered = wives
        draft.showWifeReorder = true
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
        let run: () -> Void

        /// مجموعة الإجراء في المربّع (طلب المالك ٢٠٢٦-١٠-٢٤ «مو مرتبة») — من المعرّف فلا يتغيّر كل إجراء.
        /// اللون للمجموعة لا للإجراء («منسقة»): كل مربّعات المجموعة بلونها
        var group: ActionGroup {
            switch id {
            // «إضافة زوجة» الواحدة تضيف وتربط — مع الإضافة («ربط زوجة» اندمج فيها، طلب المالك ٢٠٢٦-١٠-٢٥)
            case "child", "wife", "addMother", "sister", "outsideHusband": return .add
            case "husband", "mother", "changeFather": return .link
            default: return .record
            }
        }
    }

    /// أقسام مربّع الإجراءات بالترتيب: الإضافة · الربط · السجل — والحذف في شريط المربّع مع «إغلاق»
    private enum ActionGroup: Int, CaseIterable {
        case add, link, record

        var title: String {
            switch self {
            case .add: return L10n.t("إضافة", "Add")
            case .link: return L10n.t("ربط", "Link")
            case .record: return L10n.t("السجل", "Record")
            }
        }
        /// سطر جانبي بجانب العنوان — ما الذي في المجموعة
        var hint: String? {
            switch self {
            case .add: return L10n.t("فرد جديد", "New person")
            case .link: return L10n.t("من الشجرة", "From the tree")
            case .record: return L10n.t("بيانات العضو", "Member record")
            }
        }
        var icon: String {
            switch self {
            case .add: return "plus.circle.fill"
            case .link: return "link"
            case .record: return "person.text.rectangle.fill"
            }
        }
    }

    /// لون المجموعة (ألوان العائلة — `DSMemberKit`): الإضافة أخضر، الربط بترولي، السجل كحلي القسم
    private func groupTint(_ group: ActionGroup) -> Color {
        switch group {
        case .add: return DSMemberKit.addTint
        case .link: return DSMemberKit.linkTint
        case .record: return chromeInk
        }
    }

    /// سطر «لمن» تحت كل بطاقة (طلب المالك ٢٠٢٦-١٠-٢٥ «حط توضيح مثلا اضافة اخت لعضو المختار او ابنة لعضو
    /// المختار») — من اسم صاحب العقدة
    private func tileSubtitle(_ id: String) -> String? {
        let who = "«" + shortName(woman) + "»"
        switch id {
        case "child": return L10n.t("أبناء لـ", "Children of ") + who
        case "sister": return L10n.t("أختك — بنت ", "Your sister — daughter of ") + who
        case "wife": return L10n.t("زوجة لـ", "Wife of ") + who
        case "husband": return L10n.t("زوج لـ", "Husband of ") + who
        case "outsideHusband": return L10n.t("زوج من خارج العائلة لـ", "Outside husband of ") + who
        // الأم: اسم أب العضو في السطر الثاني (طلب المالك ٢٠٢٦-١٠-٢٥) — الأم زوجة أبيه؛ بلا أب في الشجرة كما كان
        case "mother":
            // الأم الحالية باسمها (المدخل الواحد يعرضها) — وإلا من أين تُختار
            if let m = mother { return "«" + shortName(m) + "»" }
            if let f = father { return L10n.t("زوجات «", "Wives of «") + shortName(f) + "»" }   // «اختيار الأم» مختصر (طلب المالك)
            return L10n.t("من زوجات أبي ", "From the wives of the father of ") + who
        case "addMother":
            if let f = father { return L10n.t("زوجة «", "Wife of «") + shortName(f) + "»" }
            return L10n.t("أم لـ", "Mother of ") + who
        case "reorder": return L10n.t("أبناء ", "Children of ") + who
        case "wifeOrder": return L10n.t("زوجات ", "Wives of ") + who
        case "edit": return L10n.t("بيانات ", "Details of ") + who
        // الأب الحالي باسمه — وإلا «بلا أب في الشجرة»
        case "changeFather":
            if let f = father { return L10n.t("بنت «", "Daughter of «") + shortName(f) + "»" }
            return L10n.t("بلا أب في الشجرة", "No father in the tree")
        default: return nil
        }
    }

    /// الإجراءات حسب الآلية (`mode`): الإضافة ثم الربط، ثم (للإدارة) الترتيب والتعديل — والحذف في الشريط
    private var adminActions: [AdminAction] {
        switch mode {
        case .direct: return directActions
        case .selfFamily: return selfActions
        case .request: return requestActions
        case .viewOnly: return []
        }
    }

    /// المالك/المدير/المراقب — كتابة مباشرة
    private var directActions: [AdminAction] {
        // بطاقات الإضافة بأسماء قصيرة (ابن · أخت · زوجة · أم) وسطر «لمن» تحتها (طلب المالك ٢٠٢٦-١٠-٢٥ «خلها مسمى ابن»)
        var list: [AdminAction] = [
            AdminAction(id: "child", title: L10n.t("أبناء", "Children"),
                        icon: "person.badge.plus") { startAdd(.child) }
        ]
        // على عقدة أبيه هو: «إضافة أخت» للإدارة أيضاً (طلب المالك ٢٠٢٦-١٠-٢٤)
        if isMyFatherNode {
            list.append(AdminAction(id: "sister", title: L10n.t("أخت", "Sister"),
                                    icon: "figure.stand.dress") { startAdd(.sister) })
        }
        if !woman.isFemale {
            // «إضافة زوجة» الواحدة: من العائلة (ربط أو إضافة تحت أبيها) أو من خارجها
            list.append(AdminAction(id: "wife", title: L10n.t("زوجة", "Wife"),
                                    icon: "heart.fill") { openWifeFlow() })
        } else {
            // «الزوج» مدخل واحد يسأل: من العائلة أو من خارجها (كانا «ربط زوج» و«زوج من خارج العائلة»).
            // «من خارج العائلة» للبنت بلا زوج والترحيل مطبّق والمفتاح مفعّل (السيرفر يفرضهما أيضاً)
            let outsideOK = woman.husbandId == nil && WomenStore.outsideFamilySupported && DaughterSons.isEnabled
            list.append(AdminAction(id: "husband",
                                    title: woman.husbandId == nil ? L10n.t("الزوج", "Husband")
                                                                  : L10n.t("تغيير الزوج", "Change husband"),
                                    icon: "heart.fill") {
                if outsideOK { openHusbandSource() } else { openHusbandPicker() }
            })
        }
        // «الأم» مدخل واحد (طلب المالك ٢٠٢٦-١١-٠٧ — كانا «أم» و«اختيار الأم»): يعرض الأم الحالية،
        // ويفتح الاختيار من زوجات الأب وفيه «إضافة أم جديدة»، أو الإضافة مباشرة إن لم يكن للأب زوجات
        if canPickMother || canAddMother {
            list.append(motherAction)
        }
        // «ترتيب الزوجات» — للرجل بأكثر من زوجة (طلب المالك ٢٠٢٦-١١-٠٧)
        if !woman.isFemale && wives.count > 1 {
            list.append(AdminAction(id: "wifeOrder", title: L10n.t("ترتيب الزوجات", "Order wives"),
                                    icon: "arrow.up.arrow.down") { openWifeReorderBox() })
        }
        if !children.isEmpty {
            list.append(AdminAction(id: "reorder", title: L10n.t("ترتيب الأبناء", "Reorder"),
                                    icon: "arrow.up.arrow.down") { openReorderBox() })
        }
        // «تغيير الأب» (طلب المالك ٢٠٢٦-١١-١٣ «تغيير الاب للنساء المربوطة»): للأنثى وحدها — الذكر نسخة من الشجرة العامة
        // وأبوه من `profiles` — ولا لمن هي «من خارج العائلة»
        if canChangeFather {
            list.append(AdminAction(id: "changeFather", title: L10n.t("تغيير الأب", "Change father"),
                                    icon: "person.fill.turn.down") { openChangeFather() })
        }
        // الوفاة والجنس بيانات — مكانها «تعديل البيانات» لا مربّعات مستقلّة (طلب المالك ٢٠٢٦-١٠-٢٥)
        list.append(AdminAction(id: "edit", title: L10n.t("تعديل البيانات", "Edit details"),
                                icon: "pencil") { openEditBox() })
        // (الحذف ليس مربّعاً هنا — زرّ أحمر في شريط المربّع مع «إغلاق»: `deleteFooterAction`)
        return list
    }

    /// العضو على عقدته — دوال السيرفر الذاتية (زوجته، أبناؤه، أمّه)
    private var selfActions: [AdminAction] {
        var list: [AdminAction] = [
            AdminAction(id: "child", title: L10n.t("أبناء", "Children"),
                        icon: "person.badge.plus") { startAdd(.child) }
        ]
        if !woman.isFemale {
            list.append(AdminAction(id: "wife", title: L10n.t("زوجة", "Wife"),
                                    icon: "heart.fill") { openWifeFlow() })
        }
        // «الأم» مدخل واحد كما في الإدارة
        if !fatherWives.isEmpty || canAddMother {
            list.append(motherAction)
        }
        return list
    }

    /// الأم تُضاف (جديدة) حين لا أم بعد — والإدارة تحتاج أباً في الشجرة (وإلا ظهرت جذراً مستقلاً)
    private var canAddMother: Bool {
        mother == nil && (mode != .direct || woman.fatherId != nil)
    }
    /// يفتح الاختيار من زوجات الأب إن وُجدن (أو أمّ محدّدة تُغيَّر/تُزال)، وإلا «من أين الأم؟» مباشرة
    private var motherOpensPicker: Bool { mode == .direct ? canPickMother : !fatherWives.isEmpty }
    private var motherAction: AdminAction {
        AdminAction(id: "mother", title: L10n.t("الأم", "Mother"), icon: "figure.and.child.holdinghands") {
            if motherOpensPicker { openMotherPicker() } else { openMotherFlow() }
        }
    }
    /// من الاختيار إلى «إضافة أم جديدة» — يُغلق المنتقي ثم يفتح مربّع الأم بعد انتقال المربّع
    private func motherPickerToAdd() {
        draft.showMother = false; wifeSearch = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.boxHandoff) { openMotherFlow() }
    }

    /// غيره — «طلب إضافة» للإدارة (عنوان المربّع وملاحظته تقولان إنها طلبات)، و«أخت» مباشرة على عقدة أبيه
    /// الترتيب (قرار المالك ٢٠٢٦-١١-١٧): أبناء · الزوج · أم · أخت · تعديل اسم · تعديل ميلاد · تسجيل وفاة · طلب آخر · حذف —
    /// بلا «إضافة صورة». ما لا ينطبق على العقدة (زوج مسجّل، أم مسجّلة، الأخت لغير عقدة أبيه، وفاة مسجّلة) يُترك.
    /// الخانات من `MemberCardLogic.womenRequestIds` (البند ٤: بنت أقل من 13 بلا «أبناء» و«الزوج»)
    private var requestActions: [AdminAction] {
        var ids = MemberCardLogic.womenRequestIds(isFemale: woman.isFemale, hasHusband: woman.husbandId != nil,
                                                  hasMother: mother != nil, isFatherNode: isMyFatherNode,
                                                  isDeceased: woman.isDeceased == true, age: womanAge)
        // زوج البنت من خارج العائلة: «إضافة صورة» لزوجته أو ابنه وحدهما، قبل «طلب آخر»
        let photoAccount = outsideHusbandPhotoAccount
        if photoAccount != nil, let i = ids.firstIndex(of: "req.other") { ids.insert("req.addPhoto", at: i) }
        return ids.compactMap { id -> AdminAction? in
            switch id {
            case "child":
                return AdminAction(id: "child", title: L10n.t("أبناء", "Children"),
                                   icon: "figure.2.and.child.holdinghands") { startAdd(.child) }
            case "wife":
                return AdminAction(id: "wife", title: L10n.t("زوجة", "Wife"), icon: "heart.fill") { openWifeFlow() }
            case "husband":
                return AdminAction(id: "husband", title: L10n.t("الزوج", "Husband"), icon: "heart.fill") { openHusbandSource() }
            case "addMother":
                // اختيار الأم من زوجات الأب (طلب المالك ٢٠٢٦-١١-١٧ «ليش مافي اختيار الام») — وإلا «إضافة أم جديدة»
                return AdminAction(id: "addMother", title: L10n.t("أم", "Mother"), icon: "figure.2.arms.open") {
                    if fatherWives.isEmpty { openMotherFlow() } else { openMotherPicker() }
                }
            case "sister":
                return AdminAction(id: "sister", title: L10n.t("أخت", "Sister"),
                                   icon: "figure.stand.dress") { startAdd(.sister) }
            case "req.addPhoto":
                guard let account = photoAccount else { return nil }
                return AdminAction(id: id, title: L10n.t("إضافة صورة", "Add Photo"), icon: TreeEditAction.addPhoto.iconName) {
                    handOff(from: { showAdminBox = false }) { photoRequestFor = account }
                }
            default:
                guard id.hasPrefix("req."), let kind = WomanEditRequest(rawValue: String(id.dropFirst(4))) else { return nil }
                return AdminAction(id: id, title: kind.title, icon: kind.icon) {
                    // بنته أو زوجته: «طلب حذف» بمسار «عائلتي» (`remove_self_woman_child`) كما كان زرّ الشريط
                    if kind == .delete && showsDeleteRequest {
                        handOff(from: { showAdminBox = false }) { confirmSelfRemoval = true }
                    } else {
                        editRequest = kind
                    }
                }
            }
        }
    }

    /// السطر الصادق تحت الخانة (البندان ٢ و٣)
    private func requestHonesty(_ id: String) -> MemberCardLogic.Honesty {
        MemberCardLogic.womenHonesty(id, isFemale: woman.isFemale, hasHusband: woman.husbandId != nil,
                                     hasFatherWives: !fatherWives.isEmpty)
    }

    /// لون خانة «AB»: الإضافة أخضر، تعديل البيانات كحلي، الوفاة رمادي، «طلب آخر» بترولي، الحذف أحمر
    private func requestPalette(_ id: String) -> MemberTilePalette {
        switch id {
        case "req.deceased": return .record
        case "req.delete": return .delete
        case "req.other": return .other
        case "req.editName", "req.editBirth", "req.addPhoto": return .edit
        default: return .add
        }
    }

    /// السطر الفرعي تحت كل دائرة (طلب المالك ٢٠٢٦-١١-١٧): لمن الطلب
    private func requestSubtitle(_ id: String) -> String? {
        let who = "«" + shortName(woman) + "»"
        switch id {
        case "child": return L10n.t("لـ ", "For ") + who
        case "husband": return L10n.t("زوج ", "Husband of ") + who
        case "wife": return L10n.t("زوجة ", "Wife of ") + who
        case "addMother": return L10n.t("أم ", "Mother of ") + who
        case "sister": return L10n.t("بنت ", "Daughter of ") + who
        case "req.editName": return L10n.t("اسم ", "Name of ") + who
        case "req.editBirth": return L10n.t("ميلاد ", "Birth of ") + who
        case "req.deceased": return L10n.t("وفاة ", "Death of ") + who
        case "req.addPhoto": return L10n.t("صورة لـ", "Photo of ") + who
        case "req.other": return L10n.t("عن ", "About ") + who
        case "req.delete": return L10n.t("حذف ", "Delete ") + who
        default: return nil
        }
    }

    /// إرسال طلب تعديل للإدارة — بصيغة طلبات شجرة النساء اليدوية نفسها (`add` بلا اسم جديد، معلّق على العقدة أو
    /// أبيها/زوجها وإلا مقدّم الطلب): حارس السيرفر يرفض `other` من العضو، و`add` بلا اسم لا يكتب شيئاً عند القبول —
    /// الإدارة تنفّذه من شجرة النساء ثم تقبله، والسطر الأول من الملاحظات يقول نوع الطلب الحقيقي
    private func sendEditRequest(_ kind: WomanEditRequest, _ fields: [String], _ value: WomanEditValue) {
        guard let anchor = requestAnchor(preferHusband: false) else { return }
        var lines = ["شجرة النساء — " + kind.sourceTitle, "لـ: " + displayName(woman)]
        lines += fields
        // تنفيذ تلقائي عند القبول لكل ما عدا «طلب آخر» (`private.apply_women_request`)
        let women: WomenRequestData?
        switch kind {
        case .editName:
            women = value.name.map { WomenRequestData(kind: "edit_name", nodeId: woman.id.uuidString, name: $0) }
        case .editBirth:
            women = value.date.map { WomenRequestData(kind: "edit_birth", nodeId: woman.id.uuidString, birth: $0) }
        case .deceased:
            women = WomenRequestData(kind: "deceased", nodeId: woman.id.uuidString, death: value.date)
        case .delete:
            women = WomenRequestData(kind: "delete", nodeId: woman.id.uuidString)
        case .other:
            women = nil
        }
        lines.append(women != nil ? "يُنفَّذ تلقائياً عند القبول."
                                  : "التنفيذ يدوي: يُنفَّذ من شجرة النساء (تفاصيل العضو ← الإدارة) ثم يُقبل الطلب.")
        let payload = TreeEditPayload.make(action: .add,
                                           targetMemberId: anchor.uuidString,
                                           targetMemberName: displayName(woman),
                                           parentMemberId: anchor.uuidString,
                                           parentMemberName: displayName(woman),
                                           notes: lines.joined(separator: "\n"),
                                           women: women)
        editRequest = nil
        sendRequest(payload, sourceTitle: kind.sourceTitle, icon: kind.icon)
    }

    /// «إضافة زوجة» الواحدة — يبدأ بسؤال «من أين الزوجة؟» (كان «إضافة زوجة» و«ربط زوجة» مربّعين)
    private func openWifeFlow() {
        draft.addNotes = ""; draft.addFatherPicked = nil
        draft.flowRelation = .wife
        draft.showWifeFlow = true
    }
    /// «أم» — نفس طريقة الزوجة (طلب المالك ٢٠٢٦-١٠-٢٥): «من أين الأم؟» ← من العائلة / من خارجها
    private func openMotherFlow() {
        draft.addNotes = ""; draft.addFatherPicked = nil
        draft.flowRelation = .mother
        draft.showWifeFlow = true
    }
    /// «الزوج»: من العائلة أو من خارجها
    private func openHusbandSource() {
        draft.addNotes = ""
        showHusbandSource = true
    }

    /// من مربّع إلى مربّع: يُغلق الأول ثم يفتح الثاني بعد انتقال المربّع
    private func handOff(from close: () -> Void, _ open: @escaping () -> Void) {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.boxHandoff) { open() }
    }

    /// طلب «زوج من خارج العائلة» للإدارة — بالاسم الكامل، تنفيذ يدوي من «الإدارة» في تفاصيلها
    private func sendOutsideHusbandRequest() {
        let name = outsideHusbandName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let anchor = requestAnchor(preferHusband: false) else { return }
        showOutsideHusbandRequest = false
        sendRequest(requestPayload(title: L10n.t("طلب إضافة زوج من خارج العائلة", "Request a husband from outside the family"),
                                   name: name,
                                   details: [L10n.t("الزوج من خارج العائلة — تضيفه الإدارة من «الإدارة ← الزوج ← من خارج العائلة» في تفاصيلها.",
                                                    "Husband from outside the family — the admins add him from her details.")],
                                   createsSon: false, anchor: anchor),
                    sourceTitle: "طلب إضافة زوج من خارج العائلة", icon: "plus")
    }

    private func openHusbandPicker() {
        wifeSearch = ""; draft.addNotes = ""; draft.addFatherPicked = nil
        draft.showHusbandPicker = true
    }
    private func openMotherPicker() {
        wifeSearch = ""
        draft.showMother = true
    }

    // MARK: - «تغيير الأب» (الإدارة، طلب المالك ٢٠٢٦-١١-١٣ «ابى تغيير الاب للنساء المربوطة»)

    /// للأنثى وحدها (الذكر نسخة من الشجرة العامة وأبوه من `profiles`) — وللإدارة فقط. ومنهن «من خارج العائلة»
    /// (٢٠٢٦-١١-٢٦): إن تبيّن أنها من العائلة فربطها بأبيها يلغي العلامة على السيرفر (`trg_women_outside_flag`)
    private var canChangeFather: Bool {
        mode == .direct && woman.isFemale
    }

    /// رجال العائلة بشروط قائمة الآباء نفسها (أحياء ومتوفّون)، بلا أبيها الحالي — محسوبة مرة (`WifeCandidateRules`)
    private var changeFatherCandidates: [FamilyMember] {
        WifeCandidateRules.cachedDaughterFathers(for: woman, in: allWomen, showsHidden: canEdit)
    }

    private func openChangeFather() {
        wifeSearch = ""
        draft.changeFatherPicked = nil
        draft.showChangeFather = true
    }

    /// «نقل فاطمة تحت علي حسين …؟»
    private var changeFatherTitle: String {
        guard let f = draft.changeFatherPicked else { return "" }
        return L10n.t("نقل \(shortName(woman)) تحت \(displayName(f))؟", "Move \(shortName(woman)) under \(displayName(f))?")
    }

    /// المنتقي فوق مربّع الإجراءات ثم التأكيد — خلف `AnyView` (حارس المكدس: سلسلة مُعدِّلات مربّع الإجراءات
    /// طويلة أصلاً، فلا يعمّقها هذان)
    private func withChangeFather<Box: View>(_ box: Box) -> AnyView {
        AnyView(box
            .dsCenterBox(isPresented: $draft.showChangeFather) {
                DSMemberPickerBox(
                    title: L10n.t("اختيار الأب الجديد", "Choose the new father"),
                    subtitle: displayName(woman),
                    icon: "person.fill.turn.down",
                    candidates: changeFatherCandidates,
                    search: $wifeSearch,
                    emptyTitle: L10n.t("لا يوجد ذكور في الشجرة", "No family men"),
                    matchesFromFirstName: true,
                    onPick: { draft.changeFatherPicked = $0 },
                    onCancel: { draft.showChangeFather = false; draft.changeFatherPicked = nil; wifeSearch = "" })
            }
            // التأكيد فوق المنتقي (نافذة الرسائل المستقلّة) — «إلغاء» يرجع للمنتقي نفسه
            .dsAlert(changeFatherTitle,
                     isPresented: Binding(get: { draft.changeFatherPicked != nil },
                                          set: { if !$0 { draft.changeFatherPicked = nil } })) {
                if let picked = draft.changeFatherPicked {
                    Button(L10n.t("نقل", "Move")) { performChangeFather(picked) }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            } message: {
                Text(L10n.t("يتحدّث اسمها الكامل، وتُمسح الأم إذا لم تكن من زوجات الأب الجديد.",
                            "Her full name is updated, and the mother is cleared unless she is one of the new father's wives."))
            }
        )
    }

    /// الكتابة: `women_members` (الأب، الاسم الكامل = اسمها + نسب الأب الجديد، آخر بناته، والأم تُمسح إن لم تكن من زوجاته)،
    /// ولحسابها المربوط الاسم الكامل نفسه في `profiles` — ثم تحديث الشجرة ولحظة النجاح، والخطأ في مربّع الخطأ الموجود
    private func performChangeFather(_ newFather: FamilyMember) {
        guard canChangeFather, newFather.id != woman.fatherId else { return }
        let womanId = woman.id
        let given = woman.firstName.trimmingCharacters(in: .whitespaces)
        let first = given.isEmpty ? PersonName.firstUnit(woman.fullName) : given
        let lineage = newFather.fullName.trimmingCharacters(in: .whitespaces)
        let fullName = lineage.isEmpty ? first : "\(first) \(lineage)"
        let clearsMother = woman.motherId != nil && mother?.husbandId != newFather.id
        let sort = (allWomen.filter { $0.fatherId == newFather.id }.map(\.sortOrder).max() ?? -1) + 1
        let linkedUser = WomenStore.linkedUserByWoman[womanId]
        let members = memberVM
        runWrite(failTitle: L10n.t("تعذّر النقل", "Couldn't move"), {
            try await WomenStore.changeFather(womanId: womanId, newFatherId: newFather.id, fullName: fullName,
                                              sortOrder: sort, clearsMother: clearsMother, linkedUserId: linkedUser)
            // اسم حسابها في الشجرة العامة (الملف والبحث) — بعد كتابته
            if linkedUser != nil { await members.fetchAllMembers(force: true) }
        }, onSuccess: {
            DSMomentToast.show(L10n.t("تم النقل", "Moved"), moment: .success, section: AppSection.current)
            dismiss()
        })
    }

    /// عنوان مربّع الإجراءات وزرّه في الشريط حسب الآلية
    private var actionsBoxTitle: String {
        switch mode {
        case .direct: return L10n.t("الإدارة", "Manage")
        case .selfFamily: return L10n.t("الأسرة", "My family")
        case .request, .viewOnly: return L10n.t("طلب تعديل", "Request a change")
        }
    }
    private var actionsBoxIcon: String {
        switch mode {
        case .direct: return "person.badge.shield.checkmark.fill"
        case .selfFamily: return "person.2.fill"
        case .request, .viewOnly: return "paperplane.fill"
        }
    }
    /// ما يفعله زرّ الشريط — للقارئ الصوتي
    private var actionsBoxHint: String {
        switch mode {
        case .direct: return L10n.t("يفتح الإضافة والربط وإدارة السجل", "Opens add, link and record actions")
        case .selfFamily: return L10n.t("يضيف لعائلتك", "Adds to your family")
        case .request, .viewOnly: return L10n.t("يرسل طلب إضافة أو تعديل للإدارة", "Sends an addition or edit request to the admins")
        }
    }

    /// ملاحظة فوق الأزرار — ما الذي يحدث بعد الضغط
    private var actionsBoxNote: String? {
        switch mode {
        case .direct, .viewOnly: return nil
        case .selfFamily:
            return L10n.t("تُضاف لعائلتك فوراً — والابن ينتظر اعتماد الإدارة.",
                          "Added to your family right away — a son awaits approval.")
        case .request:
            return L10n.t("يُرسل الطلب إلى الإدارة للمراجعة", "The request goes to the admins for review")
        }
    }

    /// مربّع الإجراءات (طلب المالك ٢٠٢٦-١٠-٢٤ «ورني مربعات اكثر ترتيب و منسقة»): رأس ملوّن، ثم أقسام مرتّبة
    /// إضافة · ربط · السجل — كل قسم بلونه، ومربّعاته كلها بمقاس واحد في شبكة بلا يتيم (`DSActionTileGrid`)،
    /// و«حذف» الأحمر في شريط المربّع مع «إغلاق» (طلب المالك ٢٠٢٦-١٠-٢٥ «حطلي زر الحذف جنب الاغلاق») — بلا زر إجراء
    private var actionsBox: some View {
        let actions = adminActions
        return withEditRequests(withAdminPresentations(withChangeFather(
            DSComposer(
                title: actionsBoxTitle,
                subtitle: displayName(woman),
                icon: actionsBoxIcon,
                tint: woman.isDeceased == true ? DS.Color.textSecondary : DS.Color.actionNavy,
                actionTitle: "",
                showsAction: false,
                cancelTitle: L10n.t("إغلاق", "Close"),
                canSubmit: false,
                isBusy: draft.busy,
                note: actionsBoxNote,
                isBehindExtra: draft.boxOnTop,
                // «حذف» سطراً أحمر هادئاً تحت «إغلاق» (تذييل المربّعات الموحّد، طلب المالك ٢٠٢٦-١١-١١)
                extraActions: deleteFooterAction,
                extraInline: true,
                onSubmit: {},
                onCancel: { showAdminBox = false }
            ) {
                // رجعنا للمربّعات الصغيرة اثنين في السطر (المالك ٢٠٢٦-١١-٠٧: «المربعات كبيرة… الايقونات نطورها مو مربعات
                // نكبرها») — الأيقونات أوضح لكل إجراء (`refinedIcon`)، والترتيب: الأم وجنبها الزوجة، ثم الأبناء…
                let order = ["addMother", "mother", "wife", "wifeOrder", "husband", "outsideHusband", "child", "reorder", "sister",
                             "changeFather", "edit"]
                let tiles = actions.enumerated().sorted {
                    (order.firstIndex(of: $0.element.id) ?? order.count, $0.offset)
                        < (order.firstIndex(of: $1.element.id) ?? order.count, $1.offset)
                }.map(\.element)
                if mode == .request {
                    // «طلب تعديل» بنفس مربّع شجرة العائلة (طلب المالك ٢٠٢٦-١١-١٧ «نوحد التصميم بنفس شكل السابق»):
                    // بطاقات `DSActionTile` اثنتان في السطر بلون النوع وسطرها الفرعي، و«طلب حذف» بعرض كامل آخراً
                    let tilesReq = actions   // «طلب حذف» خانة مثل البقية آخر الشبكة (طلب المالك ٢٠٢٦-١١-١٧)
                    // «AB»: خانات ملوّنة بسطر صادق، وخانة عليها طلبك المعلّق «طلبك قيد المراجعة · افتحه» (البنود ٢–٥)
                    let mine = myRequestRefs
                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                        MemberCardGridTitle()
                        MemberRequestGrid {
                            ForEach(Array(tilesReq.enumerated()), id: \.element.id) { i, action in
                                let pending = MemberCardLogic.pending(kind: MemberCardLogic.womenPendingKind(action.id),
                                                                      in: mine) != nil
                                let honesty = requestHonesty(action.id)
                                MemberRequestTile(title: action.title, subtitle: requestSubtitle(action.id),
                                                  icon: action.icon, palette: requestPalette(action.id),
                                                  line: pending ? MemberCardLogic.pendingTileText : honesty.text,
                                                  lineStyle: pending ? .pending : (honesty.isWarning ? .warning : .honest)) {
                                    if pending {
                                        handOff(from: { showAdminBox = false }) { showSentRequests = true }
                                    } else {
                                        action.run()
                                    }
                                }
                                .dsEntrance(delay: DSMotion.staggerDelay(i, base: DSMotion.sectionsAfterHeader),
                                    scale: DSMotionRules.tilePopScale, animation: DSMotion.iconPop,
                                    anchor: .center)   // الخانات تقفز تباعاً (A1)
                            }
                        }
                        if let note = MemberCardLogic.womenGridNote(isFemale: woman.isFemale, age: womanAge) {
                            MemberCardStrip(text: note)
                        }
                    }
                    .disabled(draft.busy)
                } else if !tiles.isEmpty {
                    DSComposerSection(title: L10n.t("الإجراءات", "Actions"), icon: "square.grid.2x2.fill",
                                      tint: DS.Color.actionNavy, index: 0) {
                        DSActionTileGrid {
                            ForEach(Array(tiles.enumerated()), id: \.element.id) { i, action in
                                DSActionTile(action.title, subtitle: tileSubtitle(action.id) ?? tileValue(action.id),
                                             icon: refinedIcon(action), tint: groupTint(action.group), action: action.run)
                                    .dsEntrance(delay: DSMotion.staggerDelay(i, base: DSMotion.sectionsAfterHeader),
                                                y: DSMotion.rise, scale: DSMotion.riseScale)
                            }
                        }
                    }
                    .disabled(draft.busy)
                }
            }
            // «طلب تعديل» بأرضية «AB» الكريمية — الإدارة و«الأسرة» كما هما
            .environment(\.dsComposerBackground, mode == .request ? DS.MemberCard.boxBackground : nil)
        )))
    }

    /// مربّع طلب التعديل فوق مربّع «الطلبات» — خلف `AnyView` (حارس المكدس)
    private func withEditRequests<Box: View>(_ box: Box) -> AnyView {
        AnyView(box.dsCenterBox(item: $editRequest) { kind in
            WomanEditRequestBox(kind: kind,
                                womanName: displayName(woman),
                                currentFirstName: woman.firstName,
                                isBusy: draft.busy,
                                onSend: { sendEditRequest(kind, $0, $1) },
                                onCancel: { editRequest = nil })
        }
        // اقتراح صورة زوج البنت من خارج العائلة — مسار «إضافة صورة» نفسه وموافقة الإدارة
        .dsCenterBox(item: $photoRequestFor) { target in
            TreeEditRequestView(member: target.member, action: .addPhoto, targetIsWomenNode: target.womenNode)
        })
    }

    /// أيقونة أوضح لكل إجراء (طلب المالك ٢٠٢٦-١١-٠٧ «نطور الايقونات»)
    private func refinedIcon(_ action: AdminAction) -> String {
        switch action.id {
        case "mother", "addMother": return "figure.and.child.holdinghands"
        case "wife": return "heart.circle.fill"
        case "husband": return woman.husbandId == nil ? "person.crop.circle.badge.plus" : "arrow.triangle.2.circlepath"
        case "outsideHusband": return "person.crop.circle.badge.questionmark"
        case "child": return "figure.2.and.child.holdinghands"
        case "sister": return "figure.stand.dress"
        case "wifeOrder": return "list.number"
        case "reorder": return "arrow.up.arrow.down.circle.fill"
        case "edit": return "square.and.pencil"
        case "changeFather": return "person.fill.turn.down"
        default: return action.icon
        }
    }

    /// إجراءات المجموعة بترتيب العيّنة (ما ليس في القائمة يأتي آخر «الترتيب والبيانات» بترتيبه)
    private func orderedTiles(_ actions: [AdminAction], _ order: [String]) -> [AdminAction] {
        order.compactMap { id in actions.first { $0.id == id } }
            + (order.contains("edit") ? actions.filter { a in
                !(["addMother", "mother", "wife", "husband", "outsideHusband", "child", "sister", "wifeOrder", "reorder",
                   "changeFather", "edit"]).contains(a.id)
            } : [])
    }

    /// مجموعة مربّعات بعنوان صغير — ثلاثة في السطر (وأقل مع الخط الكبير، وصفوف من أحجام إمكانية الوصول، كـ`AdminTileGrid`)
    private func actionTileGroup(_ title: String, _ items: [AdminAction], startIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            AdminSectionLabel(title: title)
            AdminTileGrid(count: DS.Hub.areaColumns) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, action in
                    Button(action: action.run) {
                        AdminHubTile(icon: action.icon,
                                     fill: tileFill(action.group),
                                     title: tileTitle(action),
                                     caption: tileValue(action.id),
                                     reservesCaption: true,
                                     badge: action.id == "child" && !children.isEmpty ? .count(children.count) : nil,
                                     badgeFill: tileFill(action.group),
                                     badgeSpoken: L10n.t("\(children.count) أبناء", "\(children.count) children"),
                                     index: startIndex + i,
                                     hint: [action.title, tileSubtitle(action.id)].compactMap { $0 }
                                        .joined(separator: L10n.t("، ", ", ")))
                    }
                    .buttonStyle(AdminTilePressStyle())
                    .dsEntrance(delay: DSMotion.staggerDelay(startIndex + i, base: DSMotion.sectionsAfterHeader),
                                y: DSMotion.rise, scale: DSMotion.riseScale)
                }
            }
        }
    }

    /// تعبئة أيقونة المربّع (ثابتة تحت رمز أبيض) من لون المجموعة — السجل بتعبئة القسم
    private func tileFill(_ group: ActionGroup) -> Color {
        group == .record ? DS.Color.actionNavy : groupTint(group).dsSolidFill
    }

    /// اسم المربّع بالعيّنة «أ»: القرابة باسمها (الأم، الزوج…) والفعل في السطر الثاني/تلميح القارئ الصوتي
    private func tileTitle(_ action: AdminAction) -> String {
        switch action.id {
        case "child": return L10n.t("الأبناء", "Children")
        case "wife": return L10n.t("الزوجة", "Wife")
        case "husband": return L10n.t("الزوج", "Husband")
        case "outsideHusband": return L10n.t("زوج من خارجها", "Outside husband")
        case "mother", "addMother": return L10n.t("الأم", "Mother")
        case "sister": return L10n.t("الأخت", "Sister")
        default: return action.title
        }
    }

    /// السطر الثاني القصير: القيمة الحالية (اسم الأم/الزوج، العدد) أو «إضافة»/«ربط» إن لم توجد
    private func tileValue(_ id: String) -> String? {
        let add = L10n.t("إضافة", "Add")
        switch id {
        case "mother", "addMother": return mother.map(shortName) ?? add
        case "husband": return husband.map(shortName) ?? L10n.t("ربط", "Link")
        case "wife":
            if wives.count == 1 { return shortName(wives[0]) }
            return wives.isEmpty ? add : L10n.t("\(wives.count) زوجات", "\(wives.count) wives")
        case "child", "sister", "outsideHusband": return add
        case "wifeOrder": return L10n.t("\(wives.count) زوجات", "\(wives.count) wives")
        case "reorder": return L10n.t("\(children.count) أبناء", "\(children.count) children")
        default: return nil
        }
    }

    /// بطاقة الرأس الصغيرة في مربّع الإجراءات: الصورة + الاسم + «بنت فلان بن فلان · متزوجة»
    private var actionsHeaderCard: some View {
        HStack(spacing: DS.Spacing.md) {
            avatar(woman, size: DS.Icon.avatar)
                .saturation(woman.isDeceased == true && !woman.isFemale ? 0 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: displayName(woman))
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                if let line = actionsHeaderLine {
                    Text(verbatim: line)
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AdminTileMetrics.radius, style: .continuous)
            .fill(DS.Color.cardBackgroundSoft))
        .accessibilityElement(children: .combine)
    }

    /// «بنت عبدالله بن محمد · متزوجة» — النسب من الأب والجد، ثم الحالة
    private var actionsHeaderLine: String? {
        var parts: [String] = []
        if let f = father {
            var lineage = (woman.isFemale ? L10n.t("بنت ", "Daughter of ") : L10n.t("ابن ", "Son of ")) + shortName(f)
            if let gid = f.fatherId, let g = allWomen.first(where: { $0.id == gid }) {
                lineage += L10n.t(" بن ", " son of ") + shortName(g)
            }
            parts.append(lineage)
        }
        if woman.isFemale {
            if woman.isMarried == true || woman.husbandId != nil { parts.append(L10n.t("متزوجة", "Married")) }
            if woman.isDeceased == true { parts.append(L10n.t("متوفاة", "Deceased")) }
        } else {
            if !wives.isEmpty { parts.append(L10n.t("متزوج", "Married")) }
            if woman.isDeceased == true { parts.append(L10n.t("متوفى", "Deceased")) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// «حذف» في شريط مربّع الإجراءات — للإدارة حين يملك الحذف (المالك والمدير، م-٣)، ومن المدخل الواحد
    /// `requestDelete` ثم التأكيد نفسه (كان زرّاً أحمر بعرض المربّع تحت المربّعات)
    private var deleteFooterAction: [DSComposerAction] {
        guard mode == .direct, canDelete else { return [] }
        return [DSComposerAction(id: "delete", title: L10n.t("حذف", "Delete"), icon: "trash",
                                 role: .destructive, action: requestDelete)]
    }

    // MARK: - «إدارة السجل» — نفس مربّع «إدارة السجل» في شجرة العائلة (`AdminMemberDetailSheet`)
    // الصورة والاسم، ثم أقسام `DSComposerSection`: البيانات الأساسية، التواريخ والحالة (`DSLifeDatesBox`)،
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
            // «حذف السجل نهائياً» سطراً أحمر هادئاً تحت «حفظ/إلغاء» — لمن يملك الحذف فقط، والتأكيد كما هو
            extraActions: canDelete
                ? [DSComposerAction(id: "delete-record", title: L10n.t("حذف", "Delete"),
                                    icon: "trash", role: .destructive) { requestDelete() }]
                : [],
            extraInline: true,
            onSubmit: performSave,
            onCancel: { draft.showEdit = false }
        ) {
            adminHero.dsStaggerIn(0)
            basicsCard.dsStaggerIn(1)
            datesCard.dsStaggerIn(2)
            if woman.isFemale { maritalCard.dsStaggerIn(3) }
            lineageCard.dsStaggerIn(4)
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
            DSComposerSection(title: L10n.t("الأبناء", "Children"), icon: "person.3.fill", tint: chromeInk,
                              trailing: "\(draft.ordered.count)", index: 0) {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(Array(draft.ordered.enumerated()), id: \.element.id) { index, child in
                        relationRow(child, sortIndex: index)
                    }
                }
            }
            .dsStaggerIn(0)
        }
    }

    // MARK: - مربّع ترتيب الزوجات — نفس مربّع ترتيب الأبناء، يكتب `wife_order`
    private var wifeReorderBox: some View {
        let changed = draft.wivesOrdered.map(\.id) != wives.map(\.id)
        return DSComposer(
            title: L10n.t("ترتيب الزوجات", "Order wives"),
            subtitle: displayName(woman),
            icon: "arrow.up.arrow.down",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            actionIcon: "checkmark",
            canSubmit: changed,
            isBusy: draft.busy,
            hasUnsavedChanges: changed,
            onSubmit: performWifeReorder,
            onCancel: { draft.showWifeReorder = false }
        ) {
            DSComposerSection(title: L10n.t("الزوجات", "Wives"), icon: "heart.fill", tint: DS.Color.female,
                              trailing: "\(draft.wivesOrdered.count)", index: 0) {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(Array(draft.wivesOrdered.enumerated()), id: \.element.id) { index, wife in
                        relationRow(wife, sortIndex: index, wifeSort: true)
                    }
                }
            }
            .dsStaggerIn(0)
        }
    }

    private func performWifeReorder() {
        let ids = draft.wivesOrdered.map(\.id)
        // يبقى في التفاصيل بعد الحفظ (لا يغلقها) — الترتيب يظهر في «النسب» والشجرة
        runWrite(failTitle: L10n.t("تعذّر حفظ الترتيب", "Couldn't save the order"), {
            try await WomenStore.reorderWives(orderedIds: ids)
        }, onSuccess: {})
    }

    /// الصورة والاسم — نفس رأس «إدارة السجل» (بلا تغيير صورة: سجلّات شجرة النساء بلا رفع صور)
    private var adminHero: some View {
        VStack(spacing: DS.Spacing.sm) {
            avatar(woman, size: DS.Icon.photoPicker)
                .saturation(woman.isDeceased == true && !woman.isFemale ? 0 : 1)
                .overlay(Circle().stroke(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
                .accessibilityHidden(true)   // الصورة زخرفة — الاسم تحتها
            DSBalancedText(displayName(woman))
                .dsFont(.memberNameTitle)
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
        DSComposerSection(title: L10n.t("البيانات الأساسية", "Basic Info"), icon: "person.text.rectangle.fill", tint: chromeInk, index: 0) {
            DSComposerField(icon: "person.fill", label: L10n.t("الاسم الكامل", "Full Name"),
                            placeholder: L10n.t("الاسم الكامل", "Full Name"), text: $draft.name, multiline: true)
            // تغيير الجنس من البيانات (كان مربّعاً مستقلاً في الإجراءات) — بتأكيد قبل النقل بين الشجرتين
            if genderTarget != nil {
                Button { draft.showGender = true } label: {
                    DSRow(icon: "arrow.left.arrow.right", tint: chromeInk, title: genderChangeTitle,
                          subtitle: woman.isFemale ? L10n.t("الجنس: أنثى", "Gender: female")
                                                   : L10n.t("الجنس: ذكر", "Gender: male")) { DSChevron() }
                }
                .buttonStyle(DSScaleButtonStyle())
            }
        }
    }

    // MARK: التواريخ والحالة — تسجيل الوفاة بنفس صفوف شجرة العائلة (`DSLifeDatesBox`)
    private var datesCard: some View {
        DSComposerSection(title: L10n.t("التواريخ والحالة", "Dates & Status"), icon: "calendar", tint: DS.Color.palm, index: 0) {
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
        return DSComposerSection(title: L10n.t("الحالة الاجتماعية", "Marital Status"), icon: "heart.fill", tint: chromeInk, index: 0) {
            // اختيار من خيارين = الاختيار الموحّد (كان مفتاحاً)
            DSMenuTile(icon: "heart.fill", label: L10n.t("الحالة الاجتماعية", "Marital status"), options: [
                DSChoiceOption(id: false, title: L10n.t("عزباء", "Single"), icon: "person.fill"),
                DSChoiceOption(id: true, title: L10n.t("متزوجة", "Married"), icon: "heart.fill")
            ], selection: $draft.married)
                .disabled(linked)
                .opacity(linked ? DS.Opacity.disabled : 1)
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
        DSComposerSection(title: L10n.t("النسب", "Lineage"), icon: "link", tint: chromeInk, index: 0) {
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
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                } else {
                    Text(placeholder)
                        .dsFieldFont(.fieldValue)
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
    /// `wifeSort` = صفّ في «ترتيب الزوجات»: الأسهم ظاهرة دائماً وتحرّك `draft.wivesOrdered`.
    private func relationRow(_ m: FamilyMember, sortIndex: Int? = nil, wifeSort: Bool = false) -> some View {
        let isDead = m.isDeceased == true
        // الوفاة بالأحمر بمعناها، والأنثى بلونها، والذكر بحبر القسم (نفس صفّ الابن في شجرة العائلة)
        let tint = isDead ? DS.Color.error : (m.isFemale ? DS.Color.female : chromeInk)
        let sorting = (wifeSort || draft.sorting) && sortIndex != nil
        let sortCount = wifeSort ? draft.wivesOrdered.count : draft.ordered.count
        return HStack(spacing: DS.Spacing.sm) {
            DSStateIcon(isDead ? "person.fill.xmark" : "person.fill",
                        tint: tint, size: DS.Icon.discSmall, mapsChrome: false)
                // القارئ الصوتي: الأيقونة زخرفة، إلا علامة الوفاة فتُقرأ كلمةً
                .accessibilityLabel(L10n.t("متوفى", "Deceased"))
                .accessibilityHidden(!isDead)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(m.firstName.isEmpty ? m.fullName : m.firstName)
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                if let birth = m.birthDate, !birth.isEmpty {
                    Text(DateHelper.displayDate(birth) ?? birth)
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
                        if wifeSort { draft.wivesOrdered.swapAt(index, index - 1) }
                        else { draft.ordered.swapAt(index, index - 1) }
                    }
                    sortArrow("chevron.down", enabled: index < sortCount - 1,
                              label: L10n.t("نقل لأسفل", "Move down"),
                              hitLeading: 0, hitTrailing: hit) {
                        if wifeSort { draft.wivesOrdered.swapAt(index, index + 1) }
                        else { draft.ordered.swapAt(index, index + 1) }
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

    // MARK: «طلب حذف» (§11): بنته أو زوجته فقط، لغير الإدارة، بلا حساب دخول

    private var showsDeleteRequest: Bool {
        guard !canModerate, let me, mode != .viewOnly, me.isWomanAccount == false,
              WomenStore.linkedUserByWoman[woman.id] == nil else { return false }
        return (woman.fatherId == me.id && woman.isFemale) || woman.husbandId == me.id
    }

    private var deletionPending: Bool {
        SelfRemovalText.isPendingAny(woman.id, in: adminRequestVM.myPendingRequests)
    }

    private func sendSelfRemoval() {
        let isWife = woman.husbandId == me?.id
        let id = woman.id
        Task {
            draft.busy = true
            let result = isWife ? await memberVM.removeSelfWife(wifeId: id) : await memberVM.removeSelfWomanChild(id: id)
            draft.busy = false
            switch result {
            case .requested:
                await adminRequestVM.fetchMyPendingRequests(force: true)
                draft.notice = WomanWriteError(title: SelfRemovalText.sentTitle, message: SelfRemovalText.sentMessage)
            case .deleted:
                await onChanged?()
                dismiss()
            case .failed, .serverMissing:
                draft.notice = WomanWriteError(title: L10n.t("تعذّر الإرسال", "Couldn't send"),
                                               message: memberVM.errorMessage ?? L10n.t("تعذّر إرسال الطلب.", "Couldn't send the request."))
            }
            memberVM.errorMessage = nil
        }
    }

    /// شريط ثابت أسفل المربّع: زرّ الدور يمين (يفتح مربّع الإجراءات)، «إغلاق» يسار — بمقاس واحد
    private var panelFooter: some View {
        // «طلب حذف» داخل «طلب تعديل» فقط (طلب المالك ٢٠٢٦-١١-١٧) — لا زرّ منفصل في الشريط
        VStack(spacing: DSBox.buttonSpacing) {
            panelFooterRow
        }
        // نفس شريط أزرار مربّعات العمل (`DSComposer`) وتفاصيل العضو: هوامشه من `DSBox`
        .padding(.horizontal, DSBox.footerHorizontal)
        .padding(.top, DSBox.footerTop)
        .padding(.bottom, DSBox.footerBottom)
        .background(
            DS.MemberCard.boxBackground
                .overlay(alignment: .top) {
                    Rectangle().fill(DS.MemberCard.panelLine)
                        .frame(height: DS.Card.strokeWidth)
                }
        )
        .dsAlert(SelfRemovalText.confirmTitle, isPresented: $confirmSelfRemoval) {
            Button(SelfRemovalText.sendButton) { sendSelfRemoval() }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(SelfRemovalText.confirmMessage(woman.firstName))
        }
        .task(id: showsDeleteRequest) {
            if showsDeleteRequest { await adminRequestVM.fetchMyPendingRequests() }
        }
    }

    /// صفّ الأزرار: زرّ الدور + «إغلاق»
    private var panelFooterRow: some View {
        // صفّ الأزرار بمواصفة `DSBox` الواحدة
        HStack(spacing: DSBox.buttonSpacing) {
            // الإدارة «الإدارة»، والعضو على عقدته «عائلتي»، وغيره «طلب إضافة» — كلها تفتح مربّع الإجراءات
            // (كان الزرّ للإدارة وحدها، فالعضو لا يجد طريقاً للإضافة من شجرة النساء)
            // «طلب تعديل» مطفأ لفئته (`MemberAccess`) — «عائلتي» والإدارة كما هما
            if mode != .viewOnly && (mode != .request || MemberAccessStore.shared.sees(.womenTreeEditRequest)) {
                // الزرّ الواحد بلون دوره (`DSMemberKit`): «الإدارة» ذهبي، و«عائلتي»/«طلب إضافة» أخضر العائلة —
                // نفس مقاس «إغلاق» وخطّه، ورمزه يقفز مرة عند الظهور؛ دوّارته أثناء العمل
                DSLiveButton(actionsBoxTitle,
                             icon: actionsBoxIcon,
                             tint: mode == .direct ? DSMemberKit.directTint : DSMemberKit.addTint,
                             motion: .pop,
                             isLoading: draft.busy,
                             hint: actionsBoxHint) { showAdminBox = true }
                    // نفس تعطيل بطاقة الإدارة أثناء العمل
                    .disabled(draft.busy)
            }
            WomanPanelCloseButton()
        }
    }

    // MARK: - مربّع الإضافة — أكثر من اسم في المرّة (طلب المالك ٢٠٢٦-١٠-٢٥)

    private func startAdd(_ kind: AddKind) {
        draft.addNotes = ""; draft.addFatherPicked = nil
        // الابن يبدأ ذكراً (وكل اسم يُبدَّل داخل المربّع)، والأخت والزوجة والأم أنثى دائماً
        draft.addEntries = [DSAddEntry(gender: kind == .child ? "male" : "female")]
        draft.addKind = kind
    }

    /// الإضافة طلبٌ للإدارة (لا كتابة) — «إضافة أخت» مباشرة دائماً
    private func addIsRequest(_ kind: AddKind) -> Bool { mode == .request && kind != .sister }

    /// المتوفّاة طلبٌ لا كتابة: الزوجة والأم من «عائلتي»، والأخت لغير الإدارة (دوالها لا تحمل الوفاة)
    private func deceasedGoesToRequest(_ kind: AddKind) -> Bool {
        switch kind {
        case .wife, .mother: return mode == .selfFamily
        case .sister: return mode != .direct
        case .child: return false
        }
    }

    /// الأسماء المكتوبة (الصفّ الفارغ لا يُرسل)
    private var filledEntries: [DSAddEntry] { draft.addEntries.filter { !$0.trimmedName.isEmpty } }

    private func addBox(_ kind: AddKind) -> some View {
        let request = addIsRequest(kind)
        let count = filledEntries.count
        // دوال «عائلتي» للزوجة والأم والأخت تأخذ الاسم وحده — بلا ميلاد ولا «متزوجة» لا تُحفظ
        let showsBirth = mode == .direct || request || kind == .child
        let action: String = {
            if request {
                return count > 1 ? L10n.t("إرسال ", "Send ") + DSRequestCount.text(count) : L10n.t("إرسال الطلب", "Send request")
            }
            return count > 1 ? L10n.t("إضافة \(count)", "Add \(count)") : L10n.t("إضافة", "Add")
        }()
        return DSComposer(
            title: request ? kind.requestTitle : kind.title,
            subtitle: request ? L10n.t("كل اسم طلب يُراجَع وحده", "Each name is a request reviewed on its own")
                              : L10n.t("يُضاف للشجرة فوراً", "Added to the tree right away"),
            icon: request ? "paperplane.fill" : kind.icon,
            tint: DS.Color.actionNavy,
            actionTitle: action,
            actionIcon: request ? "paperplane.fill" : "plus",
            canSubmit: count > 0 && (!needsFatherName(kind) || !fatherNameText.isEmpty),
            isBusy: draft.busy,
            hasUnsavedChanges: addFormHasChanges,
            onSubmit: { performAdd(kind) },
            onCancel: { draft.addKind = nil }
        ) {
            // انتقال تلقائي من مربّع ابن باسم بنت — السطر أعلى المربّع و«هو ولد؟ ارجع»
            if kind == .child, let autoMove {
                autoMoveBanner(autoMove).dsStaggerIn(0)
            }
            addContext(kind).dsStaggerIn(0)

            // الأخوات الموجودات — حتى لا تُضاف أخت مكرّرة
            if kind == .sister {
                existingSistersCard.dsStaggerIn(1)
            }

            // الأسماء: لكل اسم حقله و«متوفّى/متوفّاة»، وللابن ذكر/أنثى، و«إضافة اسم آخر» للابن والأخت
            DSAddEntriesSection(entries: $draft.addEntries,
                                title: kind.entriesTitle,
                                icon: kind == .child ? "person.2.fill" : kind.icon,
                                tint: kind == .child ? chromeInk : DS.Color.female,
                                index: kind == .sister ? 2 : 1,
                                rowLabel: { kind.rowLabel($0) },
                                // الابن والأخت بالاسم الأول (يُكمَل باسم الأب)، والزوجة والأم باسمها كاملاً
                                placeholder: kind.allowsMultiple ? L10n.t("الاسم الأول", "First name")
                                                                 : L10n.t("اسمها كاملاً", "Her full name"),
                                showsGender: kind == .child,
                                allowsMultiple: kind.allowsMultiple,
                                showsBirth: showsBirth,
                                // «أبناء»: ثلاث بطاقات فقط (الجنس، الوفاة، الميلاد — طلب المالك ٢٠٢٦-١٠-٢٥)؛ «متزوجة» للأخت في
                                // الكتابة المباشرة، والزوجة والأم متزوجتان بالرابط
                                showsMarried: mode == .direct && kind == .sister,
                                newGender: kind == .child ? "male" : "female")

            // دوال «عائلتي» لا تحمل الوفاة للزوجة والأم والأخت — المتوفّاة تُرسل طلباً (يقال قبل الضغط)
            if deceasedGoesToRequest(kind), draft.addEntries.contains(where: \.deceased) {
                maritalNote(L10n.t("المتوفّاة تصل للإدارة طلباً، وتُضاف متوفّاة بعد مراجعته.",
                                   "A deceased entry goes to the administration as a request, added after review."))
            }

            // امرأة بلا زوج مسجّل: اسم الأب مطلوب حتى تضيف الإدارة الزوج أولاً ثم الأبناء (طلب المالك ٢٠٢٦-١١-١١)
            if request, needsFatherName(kind) {
                DSComposerSection(title: L10n.t("الأب", "Father"),
                                  icon: "person.fill", tint: DS.Color.primary, index: 2) {
                    // الأب من رجال الشجرة فقط (طلب المالك ٢٠٢٦-١١-١١: «شيل من خارج العائلة»)
                    Button { draft.showFatherPicker = true } label: {
                        DSFieldTileFace(icon: "person.fill", label: L10n.t("اسم الأب *", "Father's name *"),
                                        value: draft.addFatherPicked.map { displayName($0) } ?? L10n.t("اختر من الشجرة", "Pick from the tree"),
                                        isPlaceholder: draft.addFatherPicked == nil, glyph: .menu)
                    }
                    .buttonStyle(.plain)
                    maritalNote(L10n.t("لا يوجد زوج مسجّل لها في الشجرة؛ تضيفه الإدارة أولاً ثم الأبناء.",
                                       "She has no husband recorded in the tree; the administration adds him first, then the children."))
                }
                // منتقي الأب من ذكور الشجرة — فوق مربّع الإضافة
                .dsCenterBox(isPresented: $draft.showFatherPicker) {
                    DSMemberPickerBox(
                        title: L10n.t("اختيار الأب", "Choose the father"),
                        subtitle: displayName(woman),
                        candidates: husbandCandidates,
                        search: $wifeSearch,
                        emptyTitle: L10n.t("لا يوجد ذكور في الشجرة", "No family men"),
                        selectedId: draft.addFatherPicked?.id,
                        onPick: { picked in
                            draft.addFatherPicked = picked
                            draft.showFatherPicker = false
                            wifeSearch = ""
                        },
                        onCancel: { draft.showFatherPicker = false; wifeSearch = "" })
                }
            }

            // ملاحظة للإدارة مع الطلبات (اختيارية — تُرفق بكل طلب)
            if request {
                // قسم بعنوانه الموحّد وحقل المربّعات متعدّد الأسطر (نفس «ملاحظات» في «طلب تعديل»)
                DSComposerSection(title: L10n.t("ملاحظات للإدارة", "Notes for the administration"),
                                  icon: "note.text", tint: DS.Color.primary, index: 3) {
                    DSComposerField(icon: "note.text", label: L10n.t("ملاحظات (اختياري)", "Notes (optional)"),
                                    placeholder: L10n.t("مثلاً: ابنة فلان من زوجته الثانية", "e.g. daughter from his second wife"),
                                    text: $draft.addNotes, multiline: true)
                }
            }
        }
    }

    /// بنات الأب الموجودات في الشجرة (أخوات المستخدم) — تُعرض في «إضافة أخت»
    private var existingSisters: [FamilyMember] {
        allWomen.filter { $0.fatherId == woman.id && $0.isFemale }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var existingSistersCard: some View {
        let sisters = existingSisters
        return DSComposerSection(title: L10n.t("أخواتك في الشجرة", "Your sisters in the tree"), icon: "person.2.fill",
                                 tint: DS.Color.female, trailing: "\(sisters.count)", index: 1) {
            if sisters.isEmpty {
                maritalNote(L10n.t("لا توجد أخوات مسجّلات بعد.", "No sisters recorded yet."))
            } else {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(sisters) { relationRow($0) }
                }
                maritalNote(L10n.t("تأكّد أن أختك ليست في القائمة قبل الإضافة.",
                                   "Make sure your sister isn't listed before adding."))
            }
        }
    }

    /// لمن الإضافة — بطاقة السياق أعلى المربّع («ابن أو ابنة لـ» + الاسم)
    private func addContext(_ kind: AddKind) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            // قرص الحالة المجسّم (زخرفة — النص بجانبه يكفي)
            DSStateIcon("person.badge.plus", tint: chromeInk, size: DS.Icon.row, mapsChrome: false)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(kind.contextLabel)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                DSBalancedText(displayName(woman))
                    .dsFont(.memberNameTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        // البطاقة الواحدة
        .dsCard(padding: DS.Spacing.md)
    }

    /// الإضافة تبدأ فارغة: أي اسم أو تاريخ أو «متوفّى» أو «متزوجة» أو صفّ زائد أو ملاحظة = إدخال لم يُحفظ
    private var addFormHasChanges: Bool {
        draft.addEntries.contains { !$0.isBlank } || draft.addEntries.count > 1
            || !draft.addNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draft.addFatherPicked != nil
    }

    /// أبناء امرأة بلا زوج مسجّل — لا زوج يُعلَّق عليه الأبناء
    private func noHusband(_ kind: AddKind) -> Bool {
        kind == .child && woman.isFemale && woman.husbandId == nil
    }

    /// أهلها: هي نفسها، أو أبوها، أو إخوتها (نفس الأب) — وحدهم يحدّدون الأب (طلب المالك ٢٠٢٦-١١-١١
    /// «يتم فقط من عائلة فاطمة اختيار اسم الأب، ما يظهر لأحد ثاني»)
    private var isHerFamily: Bool {
        guard let me else { return false }
        if isMyNode { return true }
        if let f = woman.fatherId, me.id == f || me.fatherId == f { return true }
        return false
    }

    /// قسم «الأب» يظهر لأهلها فقط، والأب مطلوب منهم
    private func needsFatherName(_ kind: AddKind) -> Bool {
        noHusband(kind) && isHerFamily
    }

    /// اسم الأب كما يُرسل: المختار من رجال الشجرة
    private var fatherNameText: String {
        draft.addFatherPicked.map { displayName($0) } ?? ""
    }

    // MARK: - «إضافة زوجة» الواحدة — المربّع والكتابة حسب الآلية

    /// مرشّحات «زوج من العائلة»: ذكور الشجرة (عدا العضو نفسه).
    private var husbandCandidates: [FamilyMember] {
        let family = WifeCandidateRules.familyMemberIds
        return allWomen
            // رجال شجرة العائلة فقط — لا أزواج البنات من خارجها ولا أبناؤهم (طلب المالك ٢٠٢٦-١١-١٢)
            .filter { !$0.isFemale && $0.id != woman.id && (family.isEmpty || family.contains($0.id)) }
            // مقارنة نصّية بسيطة بدل localizedCompare على ~٢٥٠٠ اسم مع كل رسم — كانت تبطّئ فتح منتقي الزوج
            .sorted { $0.fullName < $1.fullName }
    }

    /// المربّع المشترك مع «حسابي» (`DSWifeFlowBox`): القوائم بقواعد `WifeCandidateRules` (لا متزوجة، ولا دون ١٨،
    /// ولا مولودة حديثاً)، و«من خارج العائلة» = مربّع «إضافة زوجة» بالاسم الموجود
    private var wifeFlowBox: some View {
        let mother = draft.flowRelation == .mother
        let box = DSWifeFlowBox(
            mode: mode == .direct ? .direct : (mode == .selfFamily ? .selfFamily : .request),
            relation: draft.flowRelation,
            husbandId: woman.id,
            personFatherId: woman.fatherId,
            husbandName: displayName(woman),
            people: allWomen,
            showsHidden: canEdit,
            isBusy: draft.busy,
            onOutside: {
                draft.showWifeFlow = false
                DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.boxHandoff) { startAdd(mother ? .mother : .wife) }
            },
            onLink: { daughter, father in
                if mother { linkFamilyMother(daughter, father: father) } else { linkFamilyWife(daughter, father: father) }
            },
            onAddUnderFather: { name, father in
                if mother { addMotherUnderFather(name, father: father) } else { addWifeUnderFather(name, father: father) }
            },
            // الإدارة تصلح بنفسها — غيرها يطلب
            onFatherMissing: mode == .direct ? nil : { typed in
                draft.showWifeFlow = false
                // member_id يشير لحساب (profiles) — عقدة امرأة ليست حساباً، فالمرساة نفسها كبقية طلبات الشجرة
                guard let anchor = requestAnchor(preferHusband: false) else { return }
                sendRequest(WifeCandidateRules.missingFatherPayload(typed: typed, memberId: anchor,
                                                                    memberName: displayName(woman),
                                                                    relation: draft.flowRelation),
                            sourceTitle: draft.flowRelation == .mother ? "طلب إضافة أم" : "طلب إضافة زوجة", icon: "plus")
            },
            onCancel: { draft.showWifeFlow = false }
        )
        // «متوفّاة» في «أضفها تحت أبيها» — للإدارة فقط (كتابة مباشرة تحمل الوفاة)؛ «من خارج العائلة» فيه الخيار أصلاً
        guard mode == .direct else { return box }
        return box.addsDeceased { name, father in
            if mother { addMotherUnderFather(name, father: father, deceased: true) }
            else { addWifeUnderFather(name, father: father, deceased: true) }
        }
    }

    /// «الأم من العائلة»: بنت موجودة تصير أمّه (وزوجةً لأبيه إن لم يكن لها زوج) — الإدارة بمسارات السجل الموجودة،
    /// والعضو على عقدته بدالته الذاتية (add_or_link_self_relative 'mother')، وغيره يطلب
    private func linkFamilyMother(_ daughter: FamilyMember, father: FamilyMember) {
        let childId = woman.id
        let personFather = woman.fatherId
        switch mode {
        case .direct:
            runWrite(failTitle: L10n.t("تعذّر الربط", "Couldn't link")) {
                if let personFather, daughter.husbandId == nil {
                    try await WomenStore.setHusbandId(womanId: daughter.id, husbandId: personFather)
                }
                try await WomenStore.setMotherId(childId: childId, motherId: daughter.id)
            }
        case .selfFamily:
            selfRelativeWrite(failTitle: L10n.t("تعذّر الربط", "Couldn't link")) {
                do { return try await WomenStore.addOrLinkSelfRelative(kind: "mother", fatherId: father.id, womanId: daughter.id, name: nil) }
                catch { throw WomenWriteFailure(message: WifeCandidateRules.failureMessage(error)) }
            }
        case .request:
            submitLinkRequest(title: L10n.t("طلب ربط أم", "Mother link request"), sourceTitle: "طلب ربط أم", picked: daughter,
                              name: lineageName(displayName(daughter), father: father),
                              details: [L10n.t("أبوها: ", "Her father: ") + displayName(father)])
        case .viewOnly:
            break
        }
    }

    /// «أضفها تحت أبيها» للأم: بنت جديدة لأبيها تصير أمّه (وزوجةً لأبيه)
    private func addMotherUnderFather(_ name: String, father: FamilyMember, deceased: Bool = false) {
        let childId = woman.id
        let personFather = woman.fatherId
        switch mode {
        case .direct:
            let sort = (allWomen.filter { $0.fatherId == father.id }.map(\.sortOrder).max() ?? -1) + 1
            let fatherFull = father.fullName
            runWrite(failTitle: L10n.t("تعذّرت الإضافة", "Couldn't add")) {
                let newId = try await WomenStore.addFamilyChild(parentId: father.id, name: name, gender: "female",
                                                                birthDate: nil, sortOrder: sort, parentFullName: fatherFull,
                                                                isDeceased: deceased)
                if let personFather { try await WomenStore.setHusbandId(womanId: newId, husbandId: personFather) }
                try await WomenStore.setMotherId(childId: childId, motherId: newId)
            }
        case .selfFamily:
            selfRelativeWrite(failTitle: L10n.t("تعذّرت الإضافة", "Couldn't add")) {
                do { return try await WomenStore.addOrLinkSelfRelative(kind: "mother", fatherId: father.id, womanId: nil, name: name) }
                catch { throw WomenWriteFailure(message: WifeCandidateRules.failureMessage(error)) }
            }
        case .request:
            guard let anchor = requestAnchor(preferHusband: false) else { return }
            sendRequest(requestPayload(title: L10n.t("طلب إضافة أم من العائلة", "Request a mother from the family"),
                                       name: lineageName(name, father: father),
                                       details: [L10n.t("أبوها في الشجرة: ", "Her father in the tree: ") + displayName(father),
                                                 L10n.t("تُضاف بنتاً لأبيها ثم تُربط أمّاً (وزوجةً للأب).",
                                                        "Add her as his daughter, then link her as the mother (and the father's wife).")],
                                       createsSon: false, anchor: anchor),
                        sourceTitle: "طلب إضافة أم من العائلة", icon: "plus")
        case .viewOnly:
            break
        }
    }

    /// «من العائلة»: بنت موجودة تُربط زوجةً — الإدارة مباشرة، والعضو على عقدته بدالته الذاتية، وغيره يطلب
    private func linkFamilyWife(_ daughter: FamilyMember, father: FamilyMember) {
        let husbandId = woman.id
        switch mode {
        case .direct:
            linkWife(daughter.id) { try await WomenStore.setHusbandId(womanId: daughter.id, husbandId: husbandId) }
        case .selfFamily:
            let womanId = daughter.id
            let open = onOpenMember
            selfRelativeWrite(failTitle: L10n.t("تعذّر الربط", "Couldn't link"), {
                do { return try await WomenStore.addOrLinkSelfWife(fatherId: father.id, womanId: womanId, name: nil) }
                catch { throw WomenWriteFailure(message: WifeCandidateRules.failureMessage(error)) }
            }, onLinked: {
                // افتح بروفايل الزوجة المختارة (وإلا أغلق المربّع) — كما في `linkWife`
                if let open { open(womanId) } else { dismiss() }
            })
        case .request:
            submitLinkRequest(title: L10n.t("طلب ربط زوجة", "Wife link request"), sourceTitle: "طلب ربط زوجة", picked: daughter,
                              name: lineageName(displayName(daughter), father: father),
                              details: [L10n.t("أبوها: ", "Her father: ") + displayName(father)])
        case .viewOnly:
            break
        }
    }

    /// «أضفها تحت أبيها»: بنت جديدة لأبيها تُربط زوجةً لهذه العقدة — الإدارة بإدراج واحد، والعضو على عقدته
    /// بدالته الذاتية، وغيره يطلب (تنفيذ يدوي)
    private func addWifeUnderFather(_ name: String, father: FamilyMember, deceased: Bool = false) {
        let husbandId = woman.id
        switch mode {
        case .direct:
            let sort = (allWomen.filter { $0.fatherId == father.id }.map(\.sortOrder).max() ?? -1) + 1
            let fatherFull = father.fullName
            runWrite(failTitle: L10n.t("تعذّرت الإضافة", "Couldn't add")) {
                try await WomenStore.addChild(parentId: father.id, name: name, sortOrder: sort, gender: "female",
                                              parentFullName: fatherFull, isDeceased: deceased,
                                              isMarried: true, husbandId: husbandId)
            }
        case .selfFamily:
            selfRelativeWrite(failTitle: L10n.t("تعذّرت الإضافة", "Couldn't add")) {
                do { return try await WomenStore.addOrLinkSelfWife(fatherId: father.id, womanId: nil, name: name) }
                catch { throw WomenWriteFailure(message: WifeCandidateRules.failureMessage(error)) }
            }
        case .request:
            guard let anchor = requestAnchor(preferHusband: false) else { return }
            sendRequest(requestPayload(title: L10n.t("طلب إضافة زوجة من العائلة", "Request a wife from the family"),
                                       name: lineageName(name, father: father),
                                       details: [L10n.t("أبوها في الشجرة: ", "Her father in the tree: ") + displayName(father),
                                                 L10n.t("تُضاف بنتاً لأبيها ثم تُربط زوجةً.",
                                                        "Add her as his daughter, then link her as the wife.")],
                                       createsSon: false, anchor: anchor),
                        sourceTitle: "طلب إضافة زوجة من العائلة", icon: "plus")
        case .viewOnly:
            break
        }
    }

    /// ربط أنثى موجودة زوجةً لهذه العقدة (لعقدة ذكر) ثم فتح بروفايلها.
    private func linkWife(_ womanId: UUID, _ write: @escaping () async throws -> Void) {
        runWrite(failTitle: L10n.t("تعذّر الربط", "Couldn't link"), write, onSuccess: {
            // افتح بروفايل الزوجة المختارة (وإلا أغلق المربّع)
            if let open = onOpenMember { open(womanId) } else { dismiss() }
        })
    }

    /// اختيار زوج من ذكور العائلة لهذه الأنثى — مباشر للإدارة، وطلب لغيرها
    private func pickHusband(_ picked: FamilyMember) {
        switch mode {
        case .direct:
            let womanId = woman.id
            runWrite(failTitle: L10n.t("تعذّر الربط", "Couldn't link")) {
                try await WomenStore.setHusbandId(womanId: womanId, husbandId: picked.id)
            }
        case .request:
            submitLinkRequest(title: L10n.t("طلب ربط زوج", "Husband link request"), sourceTitle: "طلب ربط زوج", picked: picked)
        case .selfFamily, .viewOnly:
            break
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
                wifeSearch = ""
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

    /// كتابة قريبة ذاتية (`add_or_link_self_relative`): معرّف = كُتبت (`onLinked` أو الإغلاق)، nil = أُرسلت للإدارة
    /// ← رسالة «أُرسل طلبك للإدارة، وستظهر بعد الموافقة» بدل الإغلاق
    private func selfRelativeWrite(failTitle: String,
                                   _ write: @escaping () async throws -> UUID?,
                                   onLinked: (@MainActor () -> Void)? = nil) {
        let tally = WomanAddTally()
        runWrite(failTitle: failTitle, {
            if try await write() == nil { tally.awaitingApproval += 1 }
        }, onSuccess: {
            if tally.awaitingApproval > 0 {
                draft.notice = WomanWriteError(title: WomenStore.sentForApprovalTitle,
                                               message: WomenStore.sentForApprovalMessage)
            } else if let onLinked {
                onLinked()
            } else {
                dismiss()
            }
        })
    }

    // MARK: - Actions

    private var nextSort: Int { (children.map(\.sortOrder).max() ?? -1) + 1 }

    /// الإضافة حسب الآلية، اسماً اسماً (طلب المالك ٢٠٢٦-١٠-٢٥ «اكثر من ابنة او ابن … اكثر من اخت»): كتابة مباشرة
    /// للإدارة، دوال «عائلتي» للعضو على عقدته، وطلب لكل اسم لغيره. ما يُكتب يخرج من المربّع — إن فشل اسم بقي هو
    /// وما بعده، ولا يتكرّر ما كُتب عند إعادة المحاولة
    private func performAdd(_ kind: AddKind) {
        let list = filledEntries
        guard !list.isEmpty else { return }
        if kind == .sister { performSisterAdds(list); return }
        switch mode {
        case .direct: performDirectAdds(kind, list)
        case .selfFamily: performSelfAdds(kind, list)
        case .request: submitAddRequests(kind, list)
        case .viewOnly: return
        }
    }

    /// اسم كُتب أو طُلب — يخرج من مربّع الأسماء
    private static func written(_ entry: DSAddEntry, in draft: WomanAdminDraft) async {
        await MainActor.run { draft.addEntries.removeAll { $0.id == entry.id } }
    }

    /// الإدارة — الخطأ يُعرض والمربّع يبقى بما لم يُكتب بعد (م-٢ فحص ٢٠٢٦-١٠-٠٧)
    private func performDirectAdds(_ kind: AddKind, _ list: [DSAddEntry]) {
        // ابن/ابنة امرأة زوجها في الشجرة: الأب زوجها والأم هي (كان الأب = المرأة فيتكرّر الفرع تحتها)
        let viaHusband: FamilyMember? = (kind == .child && woman.isFemale) ? husband : nil
        let parentId = viaHusband?.id ?? woman.id
        let parentFull = viaHusband?.fullName ?? woman.fullName
        let motherId: UUID? = viaHusband == nil ? nil : woman.id
        let firstSort = (allWomen.filter { $0.fatherId == parentId }.map(\.sortOrder).max() ?? -1) + 1
        // أبٌ من الشجرة العامة → الابن عبر السيرفر (الذكر يُكتب في profiles فيظهر في شجرة العائلة أيضاً —
        // كان يُكتب هنا وحدها، والمزامنة باتجاه واحد)
        let viaServer = kind == .child && profileIds.contains(parentId)
        let womanId = woman.id
        let fatherId = woman.fatherId
        let vm = memberVM
        let draft = self.draft
        runWrite(failTitle: L10n.t("تعذّرت الإضافة", "Couldn't add")) {
            var addedSon = false
            for (i, e) in list.enumerated() {
                let birth = e.hasBirth ? Self.dayKey(e.birth) : nil
                switch kind {
                case .child where viaServer:
                    let newId = try await WomenStore.addFamilyChild(parentId: parentId, name: e.trimmedName,
                                                                    gender: e.gender, birthDate: birth,
                                                                    sortOrder: firstSort + i, parentFullName: parentFull,
                                                                    isDeceased: e.deceased)
                    if let motherId { try await WomenStore.setMotherId(childId: newId, motherId: motherId) }
                    if e.isFemale, e.married { try await WomenStore.setMarried(id: newId, true) }
                    if !e.isFemale { addedSon = true }
                case .child:
                    try await WomenStore.addChild(parentId: parentId, name: e.trimmedName, sortOrder: firstSort + i,
                                                  gender: e.gender, parentFullName: parentFull, birthDate: birth,
                                                  isDeceased: e.deceased, isMarried: e.isFemale && e.married,
                                                  motherId: motherId)
                case .wife:
                    // الزوجة متزوجة بالرابط نفسه
                    try await WomenStore.addWife(husbandId: womanId, name: e.trimmedName, birthDate: birth,
                                                 isDeceased: e.deceased, isMarried: true)
                case .mother:
                    // الأم زوجةٌ للأب — وإلا ظهرت جذراً مستقلاً أعلى الشجرة
                    try await WomenStore.addMother(childId: womanId, name: e.trimmedName, husbandId: fatherId,
                                                   birthDate: birth, isDeceased: e.deceased)
                case .sister:
                    break
                }
                await Self.written(e, in: draft)
            }
            // الذكر دخل شجرة العائلة — حدّثها الآن
            if addedSon { await vm.fetchAllMembers(force: true) }
        }
    }

    /// العضو على عقدته — دوال السيرفر الذاتية (مقيّدة على عقدته هو). دالتا الزوجة والأم لا تحملان الوفاة —
    /// المتوفّاة تُرسل طلباً للإدارة بوصفها في الملاحظات (تضيفها الإدارة متوفّاة)
    private func performSelfAdds(_ kind: AddKind, _ list: [DSAddEntry]) {
        guard let meId = me?.id else { return }
        let parentFull = woman.fullName
        let firstSort = nextSort
        let vm = memberVM
        let requests = adminRequestVM
        // الابن من «عائلتي» ينتظر اعتماد الإدارة (طلب «إضافة ابن» نفسه) — إلا من مجال المراجعة
        let staff = canModerate
        let draft = self.draft
        let tally = WomanAddTally()
        // طلبات المتوفّيات تُبنى هنا (تقرأ العقدة) — والإرسال داخل الكتابة
        var deceasedRequests: [UUID: TreeEditPayload] = [:]
        let source = womenSource(kind.sourceTitle)
        if kind == .wife || kind == .mother {
            for e in list where e.deceased { deceasedRequests[e.id] = addRequestPayload(kind, e) }
        }
        runWrite(failTitle: L10n.t("تعذّرت الإضافة", "Couldn't add"), {
            for (i, e) in list.enumerated() {
                let birth = e.hasBirth ? Self.dayKey(e.birth) : nil
                switch kind {
                case .child where e.isFemale:
                    try await WomenStore.addFamilyChild(parentId: meId, name: e.trimmedName, gender: "female",
                                                        birthDate: birth, sortOrder: firstSort + i,
                                                        parentFullName: parentFull, isDeceased: e.deceased)
                    tally.added += 1
                case .child:
                    // نفس مسار «إضافة ابن» في «عائلتي»: مباشر للعضو (إشعار للإدارة)، والطلب عند حدّ اليوم فقط
                    let newId = await vm.addChild(firstNameOnly: e.trimmedName, phoneNumber: "", birthDate: birth,
                                                  fatherId: meId, isDeceased: e.deceased, deathDate: nil, gender: "male",
                                                  requestSource: source)
                    if newId == nil {
                        let msg = await MainActor.run { vm.errorMessage }
                        throw WomenWriteFailure(message: msg ?? L10n.t("تعذّرت إضافة الابن. حاول مرة أخرى.",
                                                                        "Couldn't add the son. Try again."))
                    }
                    let direct = await MainActor.run { vm.lastChildAddWasDirect }
                    if staff || direct { tally.added += 1 } else { tally.pending += 1 }
                case .wife, .mother:
                    if let payload = deceasedRequests[e.id] {
                        try await Self.submit(payload, via: requests, source: source)
                        tally.requested += 1
                    } else if kind == .wife {
                        // nil = أُرسلت طلباً للإدارة (`relative_add`)
                        if try await WomenStore.addSelfWife(name: e.trimmedName) != nil { tally.added += 1 }
                        else { tally.awaitingApproval += 1 }
                    } else {
                        if try await WomenStore.addSelfMother(name: e.trimmedName) != nil { tally.added += 1 }
                        else { tally.awaitingApproval += 1 }
                    }
                case .sister:
                    break
                }
                await Self.written(e, in: draft)
            }
        }, onSuccess: { finishAdds(tally) })
    }

    /// «إضافة أخت» على عقدة أبيه — بنات جديدات تحته. الإدارة بإدراج مباشر (يحمل الوفاة والميلاد و«متزوجة»)،
    /// والعضو بدالة «إضافة أخت» (add_or_link_self_relative) — والمتوفّاة طلباً للإدارة (الدالة لا تحمل الوفاة)
    private func performSisterAdds(_ list: [DSAddEntry]) {
        let fatherId = woman.id
        let fatherFull = woman.fullName
        let firstSort = nextSort
        let direct = mode == .direct
        let requests = adminRequestVM
        let draft = self.draft
        let tally = WomanAddTally()
        var deceasedRequests: [UUID: TreeEditPayload] = [:]
        let sisterSource = womenSource(AddKind.sister.sourceTitle)
        if !direct {
            for e in list where e.deceased { deceasedRequests[e.id] = addRequestPayload(.sister, e) }
        }
        runWrite(failTitle: L10n.t("تعذّرت إضافة الأخت", "Couldn't add the sister"), {
            for (i, e) in list.enumerated() {
                if direct {
                    try await WomenStore.addChild(parentId: fatherId, name: e.trimmedName, sortOrder: firstSort + i,
                                                  gender: "female", parentFullName: fatherFull,
                                                  birthDate: e.hasBirth ? Self.dayKey(e.birth) : nil,
                                                  isDeceased: e.deceased, isMarried: e.married)
                    tally.added += 1
                } else if let payload = deceasedRequests[e.id] {
                    try await Self.submit(payload, via: requests, source: sisterSource)
                    tally.requested += 1
                } else {
                    if try await WomenStore.addSelfSister(fatherId: fatherId, name: e.trimmedName) != nil { tally.added += 1 }
                    else { tally.awaitingApproval += 1 }
                }
                await Self.written(e, in: draft)
            }
        }, onSuccess: { finishAdds(tally) })
    }

    /// بعد دفعة الأسماء: كلها كُتبت → تُغلق التفاصيل؛ وما ينتظر الإدارة (ابن «عائلتي»، طلب) → رسالة بالأعداد
    private func finishAdds(_ t: WomanAddTally) {
        let waiting = t.pending + t.requested + t.awaitingApproval
        guard waiting > 0 else { dismiss(); return }
        let title: String
        let message: String
        if t.added == 0 && t.pending == 0 && t.requested == 0 {
            // إضافة قريبة لغير الإدارة — تنتظر موافقة الإدارة (`relative_add`)
            title = WomenStore.sentForApprovalTitle
            message = WomenStore.sentForApprovalMessage
        } else if t.added == 0 && t.pending == 0 && t.awaitingApproval == 0 {
            title = t.requested > 1 ? L10n.t("تم إرسال ", "Sent ") + DSRequestCount.text(t.requested)
                                    : L10n.t("تم إرسال الطلب", "Request sent")
            message = t.requested > 1
                ? L10n.t("وصلت طلباتك للإدارة — كلٌّ يُراجَع وحده. تتابعها أو تسحبها من الإشعارات ← الطلبات المرسلة.",
                         "The administration got your requests — each is reviewed on its own. Follow or withdraw them from Notifications → Sent requests.")
                // البند ٦: بلا وعد بإشعار (لا يصل إن قرّر المراقب) — ماذا يحدث وأين تتابعه
                : MemberCardLogic.sentMessage(manual: t.manual)
        } else if t.added == 0 && t.requested == 0 && t.awaitingApproval == 0 {
            title = t.pending > 1 ? L10n.t("أُضيف الأبناء", "Sons added") : L10n.t("أُضيف الابن", "Son added")
            message = t.pending > 1
                ? L10n.t("يظهرون في الشجرة، وينتظرون اعتماد الإدارة.", "They show in the tree and await the administration's approval.")
                : L10n.t("يظهر في الشجرة، وينتظر اعتماد الإدارة.", "He shows in the tree and awaits the administration's approval.")
        } else {
            title = L10n.t("تمت الإضافة", "Added")
            var parts: [String] = []
            if t.added > 0 { parts.append(L10n.t("أُضيف \(t.added) للشجرة", "\(t.added) added to the tree")) }
            if t.pending > 0 { parts.append(L10n.t("\(t.pending) يظهر وينتظر اعتماد الإدارة", "\(t.pending) shown, awaiting approval")) }
            if t.requested > 0 { parts.append(L10n.t("\(t.requested) أُرسل طلباً للإدارة", "\(t.requested) sent to the administration")) }
            if t.awaitingApproval > 0 {
                parts.append(L10n.t("\(t.awaitingApproval) تظهر بعد موافقة الإدارة", "\(t.awaitingApproval) appear once approved"))
            }
            message = parts.joined(separator: L10n.t("، و", ", ")) + "."
        }
        draft.notice = WomanWriteError(title: title, message: message)
    }

    // MARK: - «طلب إضافة» — طلب «تعديل الشجرة» (tree_edit) للإدارة
    //
    // السيرفر (trg_guard_admin_request_insert) يقبل لغير الإدارة «إضافة» parentMemberId = member_id، وmember_id
    // سجلّ في الشجرة العامة (profiles). سجلّات شجرة النساء ليست منها، فيُعلَّق الطلب على أقرب سجلّ منها
    // (العقدة نفسها، أو زوجها/أبوها، وإلا مقدّم الطلب)، والتفاصيل في الملاحظات. قبول «إضافة» باسم جديد يُنشئ
    // ابناً ذكراً تحت الأب في الشجرة العامة (حيّاً — القبول لا يكتب الوفاة) — فالاسم يُرسل للابن الذكر تحت أبيه
    // فقط، وغيره تنفّذه الإدارة يدوياً. لكل اسم طلب يُراجَع وحده.

    /// السجل الذي يُعلَّق عليه الطلب
    private func requestAnchor(preferHusband: Bool) -> UUID? {
        let ids = profileIds
        let order: [UUID?] = preferHusband ? [woman.husbandId, woman.id, woman.fatherId]
                                           : [woman.id, woman.fatherId, woman.husbandId]
        return order.compactMap { $0 }.first { ids.contains($0) } ?? me?.id
    }

    private func requestPayload(title: String, name: String, details: [String],
                                createsSon: Bool, anchor: UUID,
                                women: WomenRequestData? = nil) -> TreeEditPayload {
        var lines = [L10n.t("شجرة النساء — ", "Women's tree — ") + title,
                     L10n.t("الاسم: ", "Name: ") + name,
                     L10n.t("لـ: ", "For: ") + displayName(woman)]
        lines += details
        let note = draft.addNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { lines.append(L10n.t("ملاحظات: ", "Notes: ") + note) }
        if women != nil {
            lines.append(L10n.t("يُنفَّذ تلقائياً عند القبول.", "Applied automatically on approval."))
        } else if !createsSon {
            lines.append(L10n.t("التنفيذ يدوي: تُضاف من شجرة النساء (تفاصيل العضو ← الإدارة) ثم يُقبل الطلب.",
                                "Manual: add it from the women's tree (member details → Manage), then approve."))
        }
        return TreeEditPayload.make(action: .add,
                                    targetMemberId: anchor.uuidString,
                                    targetMemberName: displayName(woman),
                                    parentMemberId: anchor.uuidString,
                                    parentMemberName: displayName(woman),
                                    newMemberName: createsSon ? name : nil,
                                    notes: lines.joined(separator: "\n"),
                                    women: women)
    }

    /// بيانات التنفيذ التلقائي لإضافة ابنة/ابن أو أخت (السيرفر يضيفها عند القبول) — nil حين تبقى يدوية:
    /// ابن ذكر لرجل أو لزوج من العائلة مكانه الشجرة العامة، والمرأة بلا زوج مسجّل، والزوجة والأم والزوج
    private func autoAddData(_ kind: AddKind, _ e: DSAddEntry) -> WomenRequestData? {
        guard kind == .child || kind == .sister else { return nil }
        let fem = kind == .sister || e.isFemale
        if woman.isFemale {
            guard kind == .child, let h = woman.husbandId else { return nil }
            if !fem && profileIds.contains(h) { return nil }
        } else if !fem {
            return nil
        }
        return WomenRequestData(kind: kind == .sister ? "sister" : "child",
                                nodeId: woman.id.uuidString,
                                name: e.trimmedName,
                                gender: fem ? "female" : "male",
                                birth: e.hasBirth ? Self.dayKey(e.birth) : nil,
                                deceased: e.deceased ? true : nil)
    }

    /// طلب «إضافة» لاسم واحد: الجنس والميلاد و«متوفّى/متوفّاة» بوضوح في الملاحظات — القبول لا يكتب الوفاة، فالابن
    /// المتوفّى يُضاف تلقائياً ثم تُسجَّل وفاته من تفاصيله، والبقية تضيفها الإدارة كما وُصفت
    private func addRequestPayload(_ kind: AddKind, _ e: DSAddEntry) -> TreeEditPayload? {
        let childOfWoman = kind == .child && woman.isFemale
        guard let anchor = requestAnchor(preferHusband: childOfWoman) else { return nil }
        // أبو الابن: الرجل نفسه، أو زوج المرأة
        let father: UUID? = woman.isFemale ? woman.husbandId : woman.id
        let createsSon = kind == .child && !e.isFemale && anchor == father
        var details: [String] = []
        // تنبيه إداري بارز: لا زوج مسجّل — الإدارة تضيف الزوج باسم الأب المكتوب أولاً، ثم الأبناء
        if noHusband(kind) {
            details.append(L10n.t("⚠︎ تنبيه للإدارة: لا يوجد زوج مسجّل لها — أضف الزوج أولاً ثم الأبناء.",
                                  "⚠︎ Admin notice: no husband recorded — add the husband first, then the children."))
            if needsFatherName(kind) {
                details.append(L10n.t("الأب (الزوج): ", "Father (husband): ") + fatherNameText
                               + L10n.t(" — من العائلة", " — from the family"))
            } else {
                details.append(L10n.t("اسم الأب: يحدّده أهلها (مقدّم الطلب ليس من أهلها).",
                                      "Father: to be given by her family (the requester isn't her family)."))
            }
        }
        if kind == .child {
            details.append(L10n.t("الجنس: ", "Gender: ") + (e.isFemale ? L10n.t("أنثى", "Female") : L10n.t("ذكر", "Male")))
        }
        if e.hasBirth { details.append(L10n.t("تاريخ الميلاد: ", "Birth date: ") + Self.dayKey(e.birth)) }
        if e.deceased {
            details.append(createsSon
                ? L10n.t("الحالة: متوفّى — بعد القبول سجّل وفاته من تفاصيله.",
                         "Status: deceased — after approval, record his death from his details.")
                : (e.isFemale ? L10n.t("الحالة: متوفّاة — تُضاف متوفّاة.", "Status: deceased — add her as deceased.")
                              : L10n.t("الحالة: متوفّى — يُضاف متوفّى.", "Status: deceased — add him as deceased.")))
        }
        // الأخت: بنت لصاحب العقدة (أبي مقدّم الطلب)
        let title = kind == .sister ? L10n.t("بنت (أخت مقدّم الطلب)", "Daughter (the requester's sister)")
                                    : kind.requestTitle
        return requestPayload(title: title, name: e.trimmedName, details: details,
                              createsSon: createsSon, anchor: anchor,
                              women: createsSon ? nil : autoAddData(kind, e))
    }

    /// طلب لكل اسم (يُراجَع كلٌّ وحده)
    private func submitAddRequests(_ kind: AddKind, _ list: [DSAddEntry]) {
        let items = list.compactMap { e in addRequestPayload(kind, e).map { (e, $0) } }
        guard !items.isEmpty else { return }
        let requests = adminRequestVM
        let draft = self.draft
        let tally = WomanAddTally()
        let source = womenSource(kind.sourceTitle)
        runWrite(failTitle: L10n.t("تعذّر إرسال الطلب", "Couldn't send the request"), {
            for (e, payload) in items {
                try await Self.submit(payload, via: requests, source: source)
                tally.requested += 1
                await Self.written(e, in: draft)
            }
        }, onSuccess: { finishAdds(tally) })
    }

    private func submitLinkRequest(title: String, sourceTitle: String, picked: FamilyMember, name: String? = nil,
                                   details: [String] = []) {
        guard let anchor = requestAnchor(preferHusband: false) else { return }
        sendRequest(requestPayload(title: title, name: name ?? displayName(picked), details: details,
                                   createsSon: false, anchor: anchor), sourceTitle: sourceTitle)
    }

    /// الاسم المختار كاملاً بنسب أبيها (طلب المالك ٢٠٢٦-١١-١٢): «فاطمة» + «علي حسين … المحمدعلي» —
    /// الاسم الأطول من نسب أبيها يبقى كما هو (نفس قاعدة `WomenTreeRequestLines.fullName` في «الوارد»)
    private func lineageName(_ name: String, father: FamilyMember) -> String {
        let fatherFull = displayName(father)
        let words = name.split(separator: " ")
        guard let first = words.first, words.count <= fatherFull.split(separator: " ").count else { return name }
        return "\(first) \(fatherFull)"
    }

    /// مسار «من أين أُرسل» لطلبات هذه العقدة (طلب المالك ٢٠٢٦-١١-١١): شجرة النساء ← صاحبة العقدة ← الطلب
    private func womenSource(_ title: String, icon: String = "plus") -> RequestSource {
        RequestSource(.womenTree, .member(displayName(woman)), RequestSourceStep(icon, title))
    }

    /// طلب واحد (ربط زوج/زوجة، زوجة من العائلة) بنفس الكتابة والرسالة
    private func sendRequest(_ payload: TreeEditPayload, sourceTitle: String, icon: String = "link") {
        let vm = adminRequestVM
        let tally = WomanAddTally()
        let source = womenSource(sourceTitle, icon: icon)
        tally.manual = payload.women == nil
        runWrite(failTitle: L10n.t("تعذّر إرسال الطلب", "Couldn't send the request"), {
            try await Self.submit(payload, via: vm, source: source)
            tally.requested += 1
        }, onSuccess: { finishAdds(tally) })
    }

    /// إرسال طلب واحد بمسار الطلبات الموجود — عدم الوصول خطأ يُعرض
    private static func submit(_ payload: TreeEditPayload, via vm: AdminRequestViewModel,
                               source: RequestSource? = nil) async throws {
        let sent = await vm.submitTreeEditRequest(payload: payload, source: source)
        if !sent {
            throw WomenWriteFailure(message: L10n.t("لم يُرسل الطلب. تحقّق من الاتصال وحاول مرة أخرى.",
                                                    "The request wasn't sent. Check your connection and try again."))
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
        // ذكر من الشجرة العامة: الوفاة والتواريخ تُكتب هناك أيضاً (المزامنة باتجاه واحد) — وإلا بقي حيّاً في
        // شجرة العائلة ثم أعادته المزامنة حيّاً هنا
        let lifeChanged = birthKey != startBirthKey || deceased != wasDeceased || deathKey != startDeathKey
        let mirrorsProfile = !woman.isFemale && profileIds.contains(woman.id) && lifeChanged
        let vm = memberVM
        runWrite(failTitle: L10n.t("تعذّر الحفظ", "Couldn't save"), {
            if fieldsChanged {
                try await WomenStore.update(id: woman.id, fullName: name,
                                            isDeceased: deceased,
                                            deathDate: deathToWrite, birthDate: birthToWrite,
                                            gender: woman.gender, isHidden: woman.isHiddenFromTree)
            }
            if mirrorsProfile {
                try await WomenStore.updateMirroredProfileLife(id: woman.id, isDeceased: deceased,
                                                               deathDate: deathToWrite, birthDate: birthToWrite)
                await MainActor.run {
                    vm.updateMemberLocally(memberId: woman.id, isDeceased: deceased,
                                           birthDate: birthToWrite, deathDate: deceased ? deathToWrite : nil)
                }
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

    /// تعيين أمّ العضو (من زوجات الأب) أو إزالتها — العضو لنفسه بدالته الذاتية (set_self_mother)
    /// طلب «اختيار الأم» من زوجات الأب — `set_mother` في `private.apply_women_request`
    private func sendMotherRequest(_ m: FamilyMember) {
        guard let anchor = requestAnchor(preferHusband: false) else { return }
        draft.showMother = false; wifeSearch = ""
        let payload = requestPayload(title: L10n.t("طلب اختيار الأم", "Request setting the mother"),
                                     name: displayName(m),
                                     details: [L10n.t("الأم من زوجات الأب: ", "Mother from the father's wives: ") + displayName(m)],
                                     createsSon: false, anchor: anchor,
                                     women: WomenRequestData(kind: "set_mother", nodeId: woman.id.uuidString,
                                                             motherId: m.id.uuidString))
        sendRequest(payload, sourceTitle: "طلب اختيار الأم", icon: "figure.2.arms.open")
    }

    private func setMother(_ motherId: UUID?) {
        let selfService = mode == .selfFamily
        let childId = woman.id
        runWrite(failTitle: L10n.t("تعذّر الحفظ", "Couldn't save")) {
            if selfService {
                try await WomenStore.setSelfMother(motherId: motherId)
            } else {
                try await WomenStore.setMotherId(childId: childId, motherId: motherId)
            }
        }
    }

    // MARK: - تغيير الجنس = نقل بين الشجرتين (`MemberViewModel.moveChildGender` → move_child_gender)

    /// الجنس الجديد إن كان النقل ممكناً — nil = لا مربّع
    private var genderTarget: String? {
        guard mode == .direct else { return nil }
        if woman.isFemale {
            // أنثى → ذكر: تُنقل للشجرة العامة تحت أبيها، فلازم أبوها منها؛ والزوجة لا تُحوَّل
            guard woman.husbandId == nil, let f = woman.fatherId, profileIds.contains(f) else { return nil }
            return "male"
        }
        // ذكر → أنثى: ابنٌ تحت أب، بلا زوجات (لا يُفصلن)
        guard woman.fatherId != nil, wives.isEmpty else { return nil }
        return "female"
    }

    private var genderChangeTitle: String {
        genderTarget == "male" ? L10n.t("تغيير إلى ذكر", "Change to male")
                               : L10n.t("تغيير إلى أنثى", "Change to female")
    }

    private var genderChangeMessage: String {
        genderTarget == "male"
            ? L10n.t("يُنقل «\(displayName(woman))» إلى شجرة العائلة ابناً تحت أبيه، ويبقى ظاهراً هنا.",
                     "«\(displayName(woman))» moves to the family tree as a son under his father, and stays shown here.")
            : L10n.t("تُنقل «\(displayName(woman))» من شجرة العائلة إلى شجرة النساء ابنةً تحت أبيها.",
                     "«\(displayName(woman))» moves from the family tree to the women's tree as a daughter.")
    }

    private func performGenderChange() {
        guard let target = genderTarget else { return }
        let vm = memberVM
        let childId = woman.id
        let motherId = woman.motherId
        runWrite(failTitle: L10n.t("تعذّر تغيير الجنس", "Couldn't change gender")) {
            guard let newId = await vm.moveChildGender(childId: childId, toGender: target) else {
                let msg = await MainActor.run { vm.errorMessage }
                throw WomenWriteFailure(message: msg ?? L10n.t("تعذّر تغيير الجنس. حاول مرة أخرى.",
                                                                "Couldn't change gender. Try again."))
            }
            // النقل يُنشئ سجلاً جديداً بلا الأم — أعِدها (أفضل جهد)
            if let motherId, newId != childId {
                try? await WomenStore.setMotherId(childId: newId, motherId: motherId)
            }
        }
    }

    // MARK: - الصور

    /// قاعدة الشجرة نفسها (مراجعة ٢٠٢٦-١١-٢٧ #7): الأنثى بلا صورة أبداً، والذكر صورته أو صورة حسابه المربوط (ابن البنت)
    private func photoURL(_ m: FamilyMember) -> String? {
        let linked: String? = m.isFemale ? nil : WomenStore.linkedUserByWoman[m.id]
            .flatMap { memberVM.member(byId: $0) }
            .flatMap { $0.isFemale ? nil : $0.avatarUrl }
        return WomenTreePhoto.url(isFemale: m.isFemale, own: m.avatarUrl ?? m.photoURL, linked: linked)
    }

    private func avatar(_ m: FamilyMember, size: CGFloat) -> some View {
        Group {
            if let url = photoURL(m), let u = URL(string: url) {
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
    /// أسماء مربّع الإضافة — اسم أو أكثر (`DSAddEntriesSection`)
    @Published var addEntries: [DSAddEntry] = [DSAddEntry()]
    /// ملاحظة «طلب إضافة» للإدارة
    @Published var addNotes = ""
    /// الأب المختار من رجال الشجرة حين تُطلب إضافة أبناء لامرأة بلا زوج مسجّل (طلب المالك ٢٠٢٦-١١-١١)
    @Published var addFatherPicked: FamilyMember? = nil
    @Published var showFatherPicker = false
    // ما يُفتح فوق مربّع الإجراءات
    @Published var addKind: WomanDetailSheet.AddKind? = nil
    @Published var showEdit = false
    @Published var showReorder = false
    /// «ترتيب الزوجات» (طلب المالك ٢٠٢٦-١١-٠٧) — مربّعه ومسودّة ترتيبه
    @Published var showWifeReorder = false
    @Published var wivesOrdered: [FamilyMember] = []
    @Published var showMother = false
    /// «إضافة زوجة» الواحدة (`DSWifeFlowBox`)
    @Published var showWifeFlow = false
    /// زوجة أو أم — المربّع نفسه
    @Published var flowRelation: DSWifeFlowBox.Relation = .wife
    @Published var showHusbandPicker = false
    /// «تغيير الأب» (الإدارة، طلب المالك ٢٠٢٦-١١-١٣): المنتقي، ثم الأب المختار ينتظر التأكيد
    @Published var showChangeFather = false
    @Published var changeFatherPicked: FamilyMember? = nil
    @Published var showGender = false
    @Published var showDelete = false
    /// كتابة جارية — في المسودّة حتى يراها المربّع المفتوح فوق التفاصيل (يبقى مفتوحاً بدوّارته)
    @Published var busy = false
    /// خطأ آخر كتابة — يظهر في `dsAlert` والمربّع يبقى مفتوحاً (م-٢ فحص ٢٠٢٦-١٠-٠٧)
    @Published var writeError: WomanWriteError? = nil
    /// نتيجة تحتاج إعلاماً (طلب أُرسل، ابن ينتظر الاعتماد) — «حسناً» يغلق التفاصيل
    @Published var notice: WomanWriteError? = nil

    /// مربّع مفتوح فوق مربّع الإجراءات → يتقلّص خلفه قليلاً
    var boxOnTop: Bool {
        addKind != nil || showEdit || showReorder || showWifeReorder || showMother || showWifeFlow
            || showHusbandPicker || showFatherPicker || showChangeFather
    }

    func closeBoxes() {
        addKind = nil
        showEdit = false; showReorder = false; showWifeReorder = false
        showMother = false; showWifeFlow = false; showHusbandPicker = false; showFatherPicker = false
        showChangeFather = false; changeFatherPicked = nil
    }
}

/// خطأ كتابة في شجرة النساء: عنوان الرسالة + نص السيرفر (أو النص العام) — م-٢ فحص ٢٠٢٦-١٠-٠٧
/// أعداد دفعة الأسماء — تُعدّ داخل الكتابة وتُقرأ بعد نجاحها لرسالة واحدة بالنتيجة
private final class WomanAddTally {
    /// كُتب في الشجرة فوراً
    var added = 0
    /// ابن «عائلتي» — ظاهر وينتظر اعتماد الإدارة
    var pending = 0
    /// أُرسل طلباً للإدارة
    var requested = 0
    /// الطلب يدوي (بلا بيانات تنفيذ تلقائي) — رسالة الإرسال تقول «تنفّذه بيدها» (البند ٦)
    var manual = false
    /// قريبة («عائلتي») أُرسلت للإدارة من السيرفر نفسه — تظهر بعد الموافقة
    var awaitingApproval = 0
}

/// «إضافة صورة» لزوج البنت من خارج العائلة: ملف حسابه، أو عقدته في شجرة النساء بلا حساب (20261127260000)
struct OutsideHusbandPhoto: Identifiable {
    let member: FamilyMember
    let womenNode: Bool
    var id: UUID { member.id }
}

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



// MARK: - «الزوج»: من أين؟ (طلب المالك ٢٠٢٦-١١-١٢)

/// «من العائلة» (يختاره من رجال الشجرة) أو «من خارج العائلة» (يكتب اسمه) — نفس خيارات مربّع الزوجة
struct HusbandSourceBox: View {
    let womanName: String
    let isRequest: Bool
    let onFamily: () -> Void
    let onOutside: () -> Void
    let onCancel: () -> Void

    var body: some View {
        DSComposer(
            title: isRequest ? L10n.t("طلب إضافة زوج", "Request a husband") : L10n.t("الزوج", "Husband"),
            subtitle: womanName,
            icon: "heart.fill",
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            canSubmit: false,
            note: isRequest ? L10n.t("يُرسل للإدارة للمراجعة", "Sent to the administration for review") : nil,
            onSubmit: {},
            onCancel: onCancel
        ) {
            DSComposerSection(title: L10n.t("من أين الزوج؟", "Where is he from?"), icon: "person.fill.questionmark",
                              tint: DS.Color.male, index: 0) {
                VStack(spacing: DS.Spacing.sm) {
                    WifeFlowOption(title: L10n.t("من العائلة", "From the family"),
                                   hint: L10n.t("تختاره من رجال الشجرة", "Pick him from the family tree"),
                                   icon: "tree.fill", tint: DSMemberKit.addTint, action: onFamily)
                    WifeFlowOption(title: L10n.t("من خارج العائلة", "From outside the family"),
                                   hint: L10n.t("تكتب اسمه الكامل", "Type his full name"),
                                   icon: "person.crop.circle.badge.plus", tint: DS.Color.primary, action: onOutside)
                }
            }
        }
    }
}

/// طلب «زوج من خارج العائلة» لغير الإدارة: الاسم الكامل فقط، والإدارة تضيفه
struct OutsideHusbandRequestBox: View {
    let womanName: String
    @Binding var name: String
    let isBusy: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        DSComposer(
            title: L10n.t("زوج من خارج العائلة", "Husband from outside the family"),
            subtitle: womanName,
            icon: "person.crop.circle.badge.plus",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("إرسال الطلب", "Send request"),
            actionIcon: "paperplane.fill",
            canSubmit: !trimmed.isEmpty,
            isBusy: isBusy,
            note: L10n.t("يُرسل للإدارة للمراجعة", "Sent to the administration for review"),
            hasUnsavedChanges: !trimmed.isEmpty,
            onSubmit: { if !trimmed.isEmpty { onSend() } },
            onCancel: onCancel
        ) {
            DSComposerSection(title: L10n.t("الزوج", "Husband"), icon: "person.fill", tint: DS.Color.male, index: 0) {
                DSComposerField(icon: "person.fill", label: L10n.t("الاسم الكامل", "Full name"),
                                placeholder: L10n.t("اسمه الكامل مع العائلة", "His full name with the family name"),
                                text: $name)
            }
        }
    }
}
