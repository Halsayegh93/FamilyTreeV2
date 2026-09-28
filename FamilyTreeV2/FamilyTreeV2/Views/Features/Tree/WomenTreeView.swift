import SwiftUI

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
                    // الحالة الفارغة تدخل بتلاشٍ وصعود خفيف — «تقليل الحركة»: تلاشٍ فقط
                    .dsStaggerIn(0)
                }
            } else {
                VStack(spacing: 0) {
                    // الوضع الأفقي: بلا هيدر — مساحة كاملة للشجرة (طلب المالك)
                    if verticalSizeClass != .compact {
                        MainHeaderView(
                            selectedTab: $selectedTab,
                            showingNotifications: $showingNotifications,
                            title: L10n.t("النساء", "Women"),
                            subtitle: "\(allMembers.count) " + L10n.t("فرد", "members"),
                            icon: "leaf.fill",
                            backgroundGradient: DS.Color.gradientPrimary,
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

/// شاشة تحميل شجرة النساء — أيقونة نابضة + عُقد وهمية (skeleton) عند التحوّل.
private struct WomenLoadingView: View {
    @State private var pulse = false
    private let rose = DS.Color.female
    /// «تقليل الحركة»: بلا نبض ولا تكبير — الهالة والنقاط ثابتة ظاهرة
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            VStack(spacing: DS.Spacing.xl) {
                // أيقونة نابضة داخل هالة
                ZStack {
                    Circle().fill(rose.opacity(0.15))
                        .frame(width: 110, height: 110)
                        .scaleEffect(reduceMotion ? 1 : (pulse ? 1.15 : 0.85))
                        .opacity(reduceMotion ? 0.5 : (pulse ? 0.3 : 0.7))
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
                            .scaleEffect(pulse || reduceMotion ? 1.0 : 0.5)
                            .opacity(pulse || reduceMotion ? 1 : 0.4)
                            .animation(reduceMotion ? nil
                                                    : .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.18),
                                       value: pulse)
                    }
                }
            }
            // حالة التحميل تدخل بتلاشٍ وصعود خفيف (نفس دخول الأقسام) — الخلفية ثابتة
            .dsStaggerIn(0)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// تفاصيل امرأة — مربّع بمنتصف الشاشة قابل للتوسّع بنفس تصميم تفاصيل العضو
/// (MemberDetailsView، طلب المالك):
/// المصغّر: صورة + اسم + صلة القرابة + العمر.
/// «عرض التفاصيل» يوسّعه: العائلة (الأم/الزوج/الأبناء) + الإدارة.
/// شريط أزرار ثابت أسفله: «تعديل البيانات» كحلي يمين (للإدارة) و«إغلاق» يسار.
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

    // إدارة (إضافة/تعديل/حذف)
    @State private var addKind: AddKind? = nil
    @State private var addName = ""
    @State private var showEditName = false
    @State private var editName = ""
    @State private var showDelete = false
    @State private var busy = false
    @State private var birthDateDraft = Date()
    /// نموذج الإضافة/التعديل: تاريخ ميلاد اختياري + علامة متزوجة
    @State private var formHasBirthDate = false
    @State private var formIsMarried = false
    @State private var showReorder = false
    @State private var showMotherPicker = false
    @State private var showWifeSource = false
    @State private var showWifeNav = false
    @State private var showWifePicker = false
    @State private var showHusbandPicker = false
    @State private var showChildGender = false
    @State private var wifeSearch = ""
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
        /// أيقونة رأس مربّع الإضافة
        var icon: String {
            switch self {
            case .son, .daughter: return "person.crop.circle.badge.plus"
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
        hasRelations || !children.isEmpty || canEdit
    }

    var body: some View {
        // مربّع بالمنتصف قابل للتوسّع بدل الشيت — يُغلق بـ«إغلاق» أو بالضغط خارجه
        DSExpandableCenterPanel(isExpanded: $isExpanded, onClose: { dismiss() }) {
            detailsStack
        }
    }

    // MARK: - المربّع وما يُفتح منه

    /// المحتوى + كل ما يُفتح منه (نماذج وقوائم بمنتصف الشاشة، اختيارات، تأكيد الحذف)
    private var detailsStack: some View {
        withPickers
    }

    /// إضافة/تعديل/ترتيب — مربّعات بمنتصف الشاشة (بدل الأوراق السفلية) + تأكيد الحذف
    private var withForms: some View {
        detailsLayout
            // إضافة (ابن/بنت/زوجة/أم)
            .dsCenterBox(isPresented: Binding(
                get: { addKind != nil },
                set: { if !$0 { addKind = nil; addName = "" } })) {
                memberFormBox(
                    title: addKind?.title ?? "",
                    icon: addKind?.icon ?? "person.crop.circle.badge.plus",
                    isFemale: addKind == .daughter || addKind == .wife || addKind == .mother,
                    confirmTitle: L10n.t("إضافة", "Add"),
                    confirmIcon: "plus",
                    onConfirm: performAdd
                )
            }
            // تعديل البيانات (الإجراء الكحلي في الشريط السفلي)
            .dsCenterBox(isPresented: $showEditName) {
                memberFormBox(
                    title: L10n.t("تعديل البيانات", "Edit details"),
                    icon: "pencil",
                    isFemale: woman.isFemale,
                    confirmTitle: L10n.t("حفظ", "Save"),
                    confirmIcon: "checkmark",
                    isEdit: true,
                    onConfirm: performRename
                )
            }
            // ترتيب الأبناء
            .dsCenterBox(isPresented: $showReorder) { reorderBox }
            // حذف
            .dsAlert(L10n.t("حذف العضو؟", "Delete member?"), isPresented: $showDelete) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) { performDelete() }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            } message: {
                Text(L10n.t("سيُحذف نهائيًا من شجرة النساء.", "This removes them from the women tree."))
            }
    }

    /// الاختيارات السريعة كما كانت: الأم، جنس الابن، مصدر الزوجة، الزوجات
    private var withDialogs: some View {
        withForms
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
    }

    /// اختيار زوجة/زوج من العائلة — مربّع بمنتصف الشاشة مع بحث
    private var withPickers: some View {
        withDialogs
            // اختيار زوجة موجودة من العائلة (لعقدة ذكر)
            .dsCenterBox(isPresented: $showWifePicker) {
                familyPickerBox(title: L10n.t("اختيار زوجة من العائلة", "Choose wife"),
                                icon: "heart.fill",
                                emptyMsg: L10n.t("لا توجد إناث متاحات في الشجرة", "No available family women"),
                                candidates: wifeCandidates, selectedId: nil,
                                onPick: { linkWife($0) },
                                onCancel: { showWifePicker = false; wifeSearch = "" })
            }
            // اختيار زوج من العائلة (لعقدة أنثى)
            .dsCenterBox(isPresented: $showHusbandPicker) {
                familyPickerBox(title: L10n.t("اختيار زوج من العائلة", "Choose husband"),
                                icon: "person.fill",
                                emptyMsg: L10n.t("لا يوجد ذكور في الشجرة", "No family men"),
                                candidates: husbandCandidates, selectedId: woman.husbandId,
                                onPick: { linkHusband($0) },
                                onCancel: { showHusbandPicker = false; wifeSearch = "" })
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
        return Button {
            withAnimation(DS.Anim.snappy) { isExpanded.toggle() }
        } label: {
            Label(expanded ? L10n.t("إخفاء التفاصيل", "Hide details")
                           : L10n.t("عرض التفاصيل", "Show details"),
                  systemImage: expanded ? "chevron.down" : "chevron.up")
                .font(DS.Font.plex(13, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, DS.Spacing.lg)
                .frame(height: 38)
                .background(DSActionFill.style(), in: Capsule())
                // مساحة ضغط ٤٤ نقطة (حد أبل) بلا تغيير الحبّة ولا ارتفاع المربّع المصغّر
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .padding(.vertical, -3)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    /// جسم التفاصيل: العائلة ← الإدارة (تدخل تباعاً عند «عرض التفاصيل») — بلا تواريخ
    /// كما كان شيت النساء أصلاً (العمر في الحبّة فقط)
    private var detailsBody: some View {
        let open = isExpanded
        return VStack(spacing: DS.Spacing.md) {
            familySection
                .dsStaggerWhen(0, active: open)

            if canEdit {
                adminSection
                    .dsStaggerWhen(1, active: open)
            }
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
                    .overlay(Circle().stroke(DS.Color.textTertiary.opacity(0.25), lineWidth: 1))
                    .scaleEffect(heroIn || reduceMotion ? 1 : 0.6)
                    .opacity(heroIn ? 1 : 0)
                    .accessibilityHidden(true)   // الصورة زخرفة — الاسم تحتها

                if woman.isDeceased == true {
                    Circle()
                        .fill(DS.Color.background)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "heart.slash.fill")
                                .font(DS.Font.scaled(18, weight: .bold))
                                .foregroundColor(DS.Color.textTertiary)
                        )
                        .overlay(Circle().stroke(DS.Color.textTertiary.opacity(0.25), lineWidth: 1))
                        .offset(x: 48, y: 48)
                        // القارئ الصوتي: علامة الوفاة تُقرأ كلمةً لا اسم رمز
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.t(woman.isFemale ? "متوفّاة" : "متوفّى", "Deceased"))
                }
            }

            Text(displayName(woman))
                .font(DS.Font.plex(18, weight: .bold))
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
                Button(action: computeKinship) {
                    quickPillLabel(
                        icon: "point.3.connected.trianglepath.dotted",
                        label: L10n.t("صلة القرابة", "Kinship"),
                        color: DS.Color.warning
                    )
                    // مساحة ضغط ٤٤ نقطة (حد أبل): الحشو يوسّع منطقة الضغط والسالب يعيد
                    // الحجم كما كان — الحبّة وارتفاع المربّع المصغّر بلا تغيير
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .padding(.vertical, -8)
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
                        .accessibilityHidden(true)   // زخرفة
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
                .accessibilityElement(children: .combine)   // الحبّة تُقرأ جملةً واحدة
            }
        }
    }

    private func quickPillLabel(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(DS.Font.scaled(11, weight: .semibold))
                .accessibilityHidden(true)   // زخرفة — النص يكفي
            Text(label)
                .font(DS.Font.scaled(12, weight: .bold))
        }
        .foregroundColor(color)
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs + 2)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    /// نتيجة صلة القرابة — صف بنفس صفوف المربّعات بلون القرابة
    private func kinshipBanner(_ text: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "point.3.connected.trianglepath.dotted", tint: DS.Color.warning)
                .accessibilityHidden(true)   // زخرفة
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("صلة القرابة", "Kinship"))
                    .font(DS.Font.plex(12, weight: .heavy))
                    .foregroundColor(DS.Color.fieldLabel)
                Text(text)
                    .font(DS.Font.plex(14.5, weight: .semibold))
                    .foregroundColor(DS.Color.fieldValue)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.sm + 2)
        .padding(.vertical, DS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .fill(DS.Color.warning.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(DS.Color.warning.opacity(0.28), lineWidth: 1))
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
                             value: shortName(husband), color: DS.Color.primary,
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
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DS.Font.plex(12, weight: .heavy))
                    .foregroundColor(DS.Color.fieldLabel)
                Text(value)
                    .font(DS.Font.plex(14))
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            if onTap != nil {
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)   // زخرفة
            }
        }
        .frame(maxWidth: .infinity)
        .dsRowBox()
        .contentShape(Rectangle())
        return Group {
            if let onTap {
                Button(action: onTap) { inner }.buttonStyle(DSScaleButtonStyle())
            } else {
                inner
            }
        }
    }

    /// الأبناء: الذكور ثم الإناث — صفوف من أربعة متمركزة (نفس شريط تفاصيل العضو)
    private func childrenBox(_ kids: [FamilyMember]) -> some View {
        let sons = kids.filter { !$0.isFemale }
        let daughters = kids.filter { $0.isFemale }
        return VStack(spacing: DS.Spacing.sm) {
            Text(L10n.t("الأبناء", "Children") + " · \(kids.count)")
                .font(DS.Font.plex(12, weight: .heavy))
                .foregroundColor(DS.Color.fieldLabel)
                .frame(maxWidth: .infinity)
            if !sons.isEmpty {
                childrenGroup(L10n.t("الذكور", "Sons"), sons, DS.Color.primary)
            }
            if !daughters.isEmpty {
                childrenGroup(L10n.t("الإناث", "Daughters"), daughters, DS.Color.female)
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity)
        .dsRowBox()
    }

    /// مجموعة أبناء (ذكور أو إناث) — عنوان بنقطة اللون ثم صفوف من أربعة
    private func childrenGroup(_ title: String, _ list: [FamilyMember], _ color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: DS.Spacing.xs) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text("\(title) (\(list.count))")
                    .font(DS.Font.plex(11, weight: .bold))
                    .foregroundColor(DS.Color.textSecondary)
            }
            VStack(spacing: 4) {
                ForEach(Array(stride(from: 0, to: list.count, by: 4)), id: \.self) { start in
                    HStack(alignment: .top, spacing: DS.Spacing.md) {
                        ForEach(list[start..<min(start + 4, list.count)]) { c in
                            childBubble(c, ring: color.opacity(0.35))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// صورة دائرية بحلقة + الاسم الأول تحتها (علامة وفاة للمتوفّى)
    private func childBubble(_ c: FamilyMember, ring: Color) -> some View {
        VStack(spacing: 4) {
            ZStack {
                avatar(c, size: 42)
                    .saturation(c.isDeceased == true && !c.isFemale ? 0 : 1)
                    .overlay(Circle().stroke(ring, lineWidth: 1.5).padding(-2))
                if c.isDeceased == true {
                    Circle().fill(DS.Color.background).frame(width: 16, height: 16)
                        .overlay(Image(systemName: "heart.slash.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(DS.Color.textTertiary))
                        .offset(x: 15, y: 15)
                }
            }
            Text(c.firstName.isEmpty ? c.fullName : c.firstName)
                .font(DS.Font.plex(11.5, weight: .bold))
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

    // MARK: - الإدارة (إضافة/ترتيب/وفاة/حذف)

    private struct AdminAction: Identifiable {
        let id: String
        let title: String
        let icon: String
        let color: Color
        let run: () -> Void
    }

    /// أزرار الإدارة بنفس ترتيبها — «تعديل البيانات» صار الإجراء الكحلي في الشريط السفلي
    private var adminActions: [AdminAction] {
        var list: [AdminAction] = [
            AdminAction(id: "child", title: L10n.t("ابن", "Child"),
                        icon: "person.badge.plus", color: DS.Color.primary) { showChildGender = true }
        ]
        if !woman.isFemale {
            list.append(AdminAction(id: "wife", title: L10n.t("زوجة", "Wife"),
                                    icon: "heart", color: DS.Color.female) { showWifeSource = true })
        }
        list.append(AdminAction(id: "mother", title: L10n.t("أم", "Mother"),
                                icon: "figure.stand.dress", color: DS.Color.accent) { showMotherPicker = true })
        let kids = children
        if !kids.isEmpty {
            // neonBlue = كحلي primaryDark نفسه في الفاتح، وأزرق فاتح يُقرأ في الداكن
            // (primaryDark الداكن كان باهتاً على خلفية الزر السوداء)
            list.append(AdminAction(id: "reorder", title: L10n.t("ترتيب الأبناء", "Reorder"),
                                    icon: "arrow.up.arrow.down", color: DS.Color.neonBlue) {
                orderedChildren = kids
                showReorder = true
            })
        }
        list.append(AdminAction(id: "deceased",
                                title: woman.isDeceased == true ? L10n.t("إلغاء الوفاة", "Living")
                                                                : L10n.t("متوفّى", "Deceased"),
                                icon: "heart.slash", color: DS.Color.warning) { toggleDeceased() })
        list.append(AdminAction(id: "delete", title: L10n.t("حذف", "Delete"),
                                icon: "trash", color: DS.Color.error) { showDelete = true })
        return list
    }

    private var adminSection: some View {
        let actions = adminActions
        return DSComposerSection(title: L10n.t("الإدارة", "Manage"),
                                 icon: "square.grid.2x2.fill",
                                 tint: DS.Color.primary) {
            // صفوف عادية لا LazyVGrid — الشبكة الكسولة تُبلِّغ ارتفاعاً ناقصاً فيُقصّ آخر صف
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
            .overlay(busy ? ProgressView().tint(DS.Color.primary) : nil)
            .disabled(busy)
        }
    }

    /// زر إدارة — مثل مربّعات نوع الطلب في تفاصيل العضو: أيقونة بدائرة + تسمية
    private func adminTile(_ action: AdminAction) -> some View {
        Button(action: action.run) {
            VStack(spacing: 6) {
                Image(systemName: action.icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(action.color)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(action.color.opacity(0.14)))
                Text(action.title)
                    .font(DS.Font.plex(12, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xs)
            .dsRowBox()
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(action.title)
    }

    // MARK: - الشريط السفلي (نفس شريط تفاصيل العضو)

    /// شريط ثابت أسفل المربّع: «تعديل البيانات» كحلي يمين (للإدارة)، «إغلاق» يسار
    private var panelFooter: some View {
        HStack(spacing: DS.Spacing.sm) {
            if canEdit {
                Button(action: openEditForm) {
                    HStack(spacing: 7) {
                        if busy {
                            ProgressView().tint(.white).scaleEffect(0.85)
                        } else {
                            Image(systemName: "pencil").font(.system(size: 14, weight: .bold))
                        }
                        Text(L10n.t("تعديل البيانات", "Edit details"))
                            .font(DS.Font.plex(15, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(DSActionFill.label(enabled: !busy))
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(DSActionFill.style(enabled: !busy),
                                in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                }
                // نفس تعطيل بطاقة الإدارة أثناء العمل
                .disabled(busy)
            }
            WomanPanelCloseButton()
        }
        .buttonStyle(DSScaleButtonStyle())
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.md)
        .background(
            DS.Color.background
                .overlay(alignment: .top) {
                    Rectangle().fill(DS.Color.textTertiary.opacity(0.12)).frame(height: 1)
                }
        )
    }

    /// «تعديل البيانات» — يملأ الاسم الحالي ثم يفتح نموذج التعديل
    private func openEditForm() {
        editName = woman.fullName.isEmpty ? woman.firstName : woman.fullName
        showEditName = true
    }

    // MARK: - نموذج الإضافة/التعديل (مربّع بمنتصف الشاشة)

    /// نموذج موحّد للإضافة والتعديل — الاسم ثم تاريخ الميلاد ثم «متزوجة»
    /// (الأخيرة للإناث فقط). بنفس تصميم مربّعات الإضافة.
    private func memberFormBox(
        title: String,
        icon: String,
        isFemale: Bool,
        confirmTitle: String,
        confirmIcon: String,
        isEdit: Bool = false,
        onConfirm: @escaping () -> Void
    ) -> some View {
        let nameText = isEdit ? $editName : $addName
        // المرتبطة بزوج في الشجرة متزوجة بحكم الرابط — إطفاء المفتاح
        // لها كان بلا أثر (الرابط يبقى ويستبعدها من المرشّحات).
        let linked = isEdit && woman.husbandId != nil
        return DSComposer(
            title: title,
            subtitle: displayName(woman),
            icon: icon,
            tint: DS.Color.actionNavy,
            actionTitle: confirmTitle,
            actionIcon: confirmIcon,
            canSubmit: !nameText.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty,
            hasUnsavedChanges: isEdit ? editFormHasChanges : addFormHasChanges,
            onSubmit: {
                showEditName = false
                onConfirm()
            },
            onCancel: {
                addKind = nil; addName = ""; showEditName = false
            }
        ) {
            DSComposerSection(title: L10n.t("الاسم", "Name"),
                              icon: "person.text.rectangle.fill",
                              tint: DS.Color.primary,
                              index: 0) {
                DSComposerField(icon: "person.fill",
                                label: L10n.t("الاسم", "Name"),
                                placeholder: L10n.t("الاسم", "Name"),
                                text: nameText)
            }

            DSComposerSection(title: L10n.t("تاريخ الميلاد", "Birth date"),
                              icon: "calendar",
                              tint: DS.Color.warning,
                              index: 1) {
                formToggleRow(icon: "calendar.badge.checkmark", iconTint: DS.Color.warning,
                              title: L10n.t("التاريخ معروف", "Date is known"),
                              isOn: $formHasBirthDate)
                if formHasBirthDate {
                    formBirthDateRow
                        .transition(.opacity)
                }
            }

            if isFemale {
                DSComposerSection(title: L10n.t("الحالة الاجتماعية", "Marital Status"),
                                  icon: "heart.fill",
                                  tint: DS.Color.primary,
                                  index: 2) {
                    formToggleRow(icon: "heart.fill", iconTint: DS.Color.primary,
                                  title: L10n.t("متزوجة", "Married"),
                                  isOn: $formIsMarried)
                        .disabled(linked)
                    Text(linked
                         ? L10n.t("مرتبطة بزوج في الشجرة — فُكّ الارتباط أولاً لتغيير الحالة.",
                                  "Linked to a husband in the tree — unlink first to change this.")
                         : L10n.t("المتزوجة لا تظهر في قائمة اختيار الزوجة.",
                                  "A married woman is hidden from wife candidates."))
                        .font(DS.Font.plex(11.5))
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            if isEdit {
                // المرتبطة بزوج متزوجة فعلاً — اعرضها كذلك ولو لم تُعلَّم بعد
                formIsMarried = woman.isMarried == true || woman.husbandId != nil
                if let d = parseBirthDate(woman.birthDate) {
                    birthDateDraft = d; formHasBirthDate = true
                } else {
                    formHasBirthDate = false
                }
            } else {
                formIsMarried = false
                formHasBirthDate = false
                birthDateDraft = Date()
            }
        }
    }

    // MARK: تغييرات لم تُحفظ (توصية أبل) — «إلغاء» يسأل قبل التجاهل

    /// الإضافة تبدأ فارغة: أي اسم أو تاريخ أو «متزوجة» = إدخال لم يُحفظ
    private var addFormHasChanges: Bool {
        !addName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || formHasBirthDate || formIsMarried
    }

    /// التعديل: أي حقل يختلف عمّا يفتح عليه النموذج (نفس قيم openEditForm و onAppear)
    private var editFormHasChanges: Bool {
        let startName = woman.fullName.isEmpty ? woman.firstName : woman.fullName
        let startMarried = woman.isMarried == true || woman.husbandId != nil
        let startBirth = parseBirthDate(woman.birthDate).map { Self.formDayFormatter.string(from: $0) }
        return editName != startName || formIsMarried != startMarried || formBirthDateValue != startBirth
    }

    /// نفس صيغة formBirthDateValue — للمقارنة بتاريخ الميلاد المحفوظ
    private static let formDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// صف مفتاح داخل مربّع: أيقونة الحقل + العنوان + المفتاح
    private func formToggleRow(icon: String, iconTint: Color, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: iconTint)
                .accessibilityHidden(true)   // زخرفة
            Text(title)
                .font(DS.Font.plex(13.5, weight: .bold))
                .foregroundColor(DS.Color.fieldLabel)
                .accessibilityHidden(true)   // يُقرأ اسماً للمفتاح نفسه
            Spacer(minLength: 0)
            Toggle("", isOn: isOn.animation(DS.Anim.snappy))
                .labelsHidden()
                .tint(DS.Color.primary)
                .accessibilityLabel(title)
        }
        .dsRowBox()
    }

    /// صف تاريخ الميلاد: التاريخ المختار + قلم يفتح مربّع التاريخ بمنتصف الشاشة
    private var formBirthDateRow: some View {
        Button(action: pickFormBirthDate) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "calendar", tint: DS.Color.warning)
                    .accessibilityHidden(true)   // زخرفة
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("تاريخ الميلاد", "Birth date"))
                        .font(DS.Font.plex(12, weight: .heavy))
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(DSDateText.display(birthDateDraft))
                        .font(DS.Font.plex(14.5))
                        .foregroundColor(DS.Color.fieldValue)
                }
                Spacer(minLength: 0)
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(DS.Color.primary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Color.primary.opacity(0.10)))
                    .accessibilityHidden(true)   // الصف كله زر — القلم زخرفة
            }
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pickFormBirthDate() {
        dsPresentDatePicker(title: L10n.t("تاريخ الميلاد", "Birth date"),
                            initial: birthDateDraft,
                            allowClear: false) { picked in
            guard let picked else { return }
            birthDateDraft = picked
        }
    }

    // MARK: - ترتيب الأبناء (مربّع بمنتصف الشاشة)

    private var reorderBox: some View {
        DSComposer(
            title: L10n.t("ترتيب الأبناء", "Reorder children"),
            subtitle: displayName(woman),
            icon: "arrow.up.arrow.down",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            canSubmit: true,
            // ترتيب جديد لم يُحفظ → «إلغاء» يسأل قبل التجاهل
            hasUnsavedChanges: orderedChildren.map(\.id) != children.map(\.id),
            onSubmit: { performReorder() },
            onCancel: { showReorder = false }
        ) {
            DSComposerSection(title: L10n.t("الأبناء", "Children"),
                              icon: "person.3.fill",
                              tint: DS.Color.primary,
                              trailing: "\(orderedChildren.count)",
                              index: 0) {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(Array(orderedChildren.enumerated()), id: \.element.id) { index, c in
                        reorderRow(c, index: index)
                    }
                }
            }
        }
    }

    /// صف ابن بسهمين للأعلى/الأسفل — نفس ترتيب الأبناء في «التعديل المباشر»
    private func reorderRow(_ c: FamilyMember, index: Int) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            avatar(c, size: 34)
                .saturation(c.isDeceased == true && !c.isFemale ? 0 : 1)
                .accessibilityHidden(true)   // الصورة زخرفة — الاسم بجانبها
            Text(c.firstName.isEmpty ? c.fullName : c.firstName)
                .font(DS.Font.plex(14.5, weight: .semibold))
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            // منطقتا الضغط تتقاسمان الفراغ بينهما (٤+٤ = مسافة الصف ٨) وتمتدّان للخارج ١٠
            sortArrow("chevron.up", enabled: index > 0,
                      label: L10n.t("نقل لأعلى", "Move up"), hitLeading: 10, hitTrailing: 4) {
                orderedChildren.swapAt(index, index - 1)
            }
            sortArrow("chevron.down", enabled: index < orderedChildren.count - 1,
                      label: L10n.t("نقل لأسفل", "Move down"), hitLeading: 4, hitTrailing: 10) {
                orderedChildren.swapAt(index, index + 1)
            }
        }
        .dsRowBox()
    }

    /// سهم ترتيب: دائرة ٣٠ كما هي، ومنطقة ضغط ٤٤×٤٤ (حد أبل) حولها بلا تغيير مكانها —
    /// الحشو الموجب يوسّع منطقة الضغط، والسالب يعيد حجمها في التخطيط
    private func sortArrow(_ icon: String, enabled: Bool, label: String,
                           hitLeading: CGFloat, hitTrailing: CGFloat,
                           action: @escaping () -> Void) -> some View {
        Button { withAnimation(DS.Anim.snappy) { action() } } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(enabled ? DS.Color.primary : DS.Color.textTertiary.opacity(0.4))
                .frame(width: 30, height: 30)
                .background(DS.Color.primary.opacity(enabled ? 0.10 : 0.04), in: Circle())
                .padding(.leading, hitLeading)
                .padding(.trailing, hitTrailing)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .padding(.leading, -hitLeading)
                .padding(.trailing, -hitTrailing)
                .padding(.vertical, -7)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: - اختيار زوجة/زوج من العائلة

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

    /// قائمة اختيار عضو من العائلة (زوجة/زوج) مع بحث — مربّع بمنتصف الشاشة:
    /// حقل بحث ثم النتائج صفوفاً، والمختار حالياً بعلامة ✓
    private func familyPickerBox(title: String, icon: String, emptyMsg: String, candidates: [FamilyMember],
                                 selectedId: UUID?,
                                 onPick: @escaping (UUID) -> Void, onCancel: @escaping () -> Void) -> some View {
        let list = wifeSearch.trimmingCharacters(in: .whitespaces).isEmpty
            ? candidates
            : candidates.filter { $0.fullName.contains(wifeSearch) || $0.firstName.contains(wifeSearch) }
        return DSComposer(
            title: title,
            subtitle: displayName(woman),
            icon: icon,
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            canSubmit: false,
            onSubmit: {},
            onCancel: onCancel
        ) {
            if candidates.isEmpty {
                VStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                        .accessibilityHidden(true)   // زخرفة
                    Text(emptyMsg)
                        .font(DS.Font.plex(14))
                        .foregroundColor(DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.xl)
                .dsStaggerIn(0)
            } else {
                DSComposerField(icon: "magnifyingglass",
                                label: L10n.t("بحث بالاسم", "Search by name"),
                                placeholder: L10n.t("الاسم", "Name"),
                                text: $wifeSearch)
                    .dsStaggerIn(0)

                DSComposerSection(title: L10n.t("أفراد العائلة", "Family members"),
                                  icon: "person.2.fill",
                                  tint: DS.Color.primary,
                                  trailing: "\(list.count)",
                                  index: 1) {
                    if list.isEmpty {
                        Text(L10n.t("لا توجد نتائج", "No results"))
                            .font(DS.Font.plex(13))
                            .foregroundColor(DS.Color.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Spacing.sm)
                    } else {
                        LazyVStack(spacing: DS.Spacing.sm) {
                            ForEach(list) { m in
                                pickerRow(m, selected: m.id == selectedId, onPick: onPick)
                            }
                        }
                    }
                }
            }
        }
    }

    private func pickerRow(_ m: FamilyMember, selected: Bool, onPick: @escaping (UUID) -> Void) -> some View {
        let shownName = m.fullName.isEmpty ? m.firstName : m.displayFullName
        return Button { onPick(m.id) } label: {
            HStack(spacing: DS.Spacing.sm) {
                avatar(m, size: 36)
                    .saturation(m.isDeceased == true && !m.isFemale ? 0 : 1)
                Text(shownName)
                    .font(DS.Font.plex(14, weight: .semibold))
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(DS.Color.primary)
                }
            }
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        // القارئ الصوتي: الاسم وحده (بلا حرف الصورة البديلة)، والمختار حالياً «محدد»
        .accessibilityLabel(shownName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// ربط أنثى موجودة كزوجة لهذه العقدة (لعقدة ذكر).
    private func linkWife(_ womanId: UUID) {
        showWifePicker = false; wifeSearch = ""; busy = true
        Task {
            try? await WomenStore.setHusbandId(womanId: womanId, husbandId: woman.id)
            await onChanged?()
            await MainActor.run {
                busy = false
                // افتح بروفايل الزوجة المختارة (وإلا أغلق المربّع)
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

    // MARK: - Actions

    private var nextSort: Int { (children.map(\.sortOrder).max() ?? -1) + 1 }

    /// نص التاريخ المختار — أو nil إن كان غير معروف
    private var formBirthDateValue: String? {
        guard formHasBirthDate else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: birthDateDraft)
    }

    private func performAdd() {
        guard let kind = addKind, !addName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let name = addName.trimmingCharacters(in: .whitespaces)
        let birth = formBirthDateValue
        let married = formIsMarried
        addName = ""; addKind = nil; busy = true
        Task {
            do {
                switch kind {
                case .son:
                    try await WomenStore.addChild(parentId: woman.id, name: name, sortOrder: nextSort, gender: "male", parentFullName: woman.fullName, birthDate: birth)
                case .daughter:
                    try await WomenStore.addChild(parentId: woman.id, name: name, sortOrder: nextSort, gender: "female", parentFullName: woman.fullName, birthDate: birth, isMarried: married)
                case .wife:
                    try await WomenStore.addWife(husbandId: woman.id, name: name, birthDate: birth, isMarried: married)
                case .mother:
                    try await WomenStore.addMother(childId: woman.id, name: name, birthDate: birth, isMarried: married)
                }
                await onChanged?()
            } catch { }
            await MainActor.run { busy = false; dismiss() }
        }
    }

    private func performRename() {
        let name = editName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let birth = formBirthDateValue
        let married = formIsMarried
        busy = true
        Task {
            try? await WomenStore.update(id: woman.id, fullName: name,
                                         isDeceased: woman.isDeceased == true,
                                         deathDate: woman.deathDate, birthDate: birth,
                                         gender: woman.gender, isHidden: woman.isHiddenFromTree)
            if woman.isFemale, married != (woman.isMarried == true) {
                try? await WomenStore.setMarried(id: woman.id, married)
            }
            await onChanged?()
            await MainActor.run { busy = false; dismiss() }
        }
    }

    /// تحويل نص التاريخ لـDate (yyyy-MM-dd)
    private func parseBirthDate(_ raw: String?) -> Date? {
        guard let raw, raw.count >= 10 else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(raw.prefix(10)))
    }

    private func toggleDeceased() {
        busy = true
        let becomingDeceased = !(woman.isDeceased == true)
        let name = woman.fullName.isEmpty ? woman.firstName : woman.fullName
        Task {
            let saved = (try? await WomenStore.update(id: woman.id,
                                         fullName: name,
                                         isDeceased: becomingDeceased,
                                         deathDate: woman.deathDate, birthDate: woman.birthDate,
                                         gender: woman.gender, isHidden: woman.isHiddenFromTree)) != nil
            await onChanged?()
            await MainActor.run { busy = false; dismiss() }
            // وفاة امرأة سُجّلت الآن → مربّع «إعلان وفاة» بصيغة المؤنث
            // (الرجال المنعكسون هنا تُسجَّل وفاتهم من شجرة الرجال)
            if saved, becomingDeceased, woman.isFemale {
                await DeathAnnouncementPresenter.offer(
                    DeathAnnouncementTarget(id: woman.id, name: name, isFemale: true),
                    canAnnounce: canEdit)
            }
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

    // MARK: - الصور

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
                // الإناث بالوردي، والمتوفّاة بوردي أغمق (طلب المالك)؛ الذكور بالكحلي
                let tint: Color = m.isFemale
                    ? (m.isDeceased == true ? DS.Color.femaleDeceased : DS.Color.female)
                    : DS.Color.primary
                if m.isFemale {
                    tint
                } else {
                    LinearGradient(
                        colors: [DS.Color.primary.opacity(0.22), DS.Color.accent.opacity(0.14)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
                Text(String((m.firstName.isEmpty ? m.fullName : m.firstName).prefix(1)))
                    .font(.system(size: g.size.width * 0.42, weight: .bold, design: .rounded))
                    .foregroundColor(m.isFemale ? .white : tint.opacity(0.85))
            }
        }
    }

    private func year(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if let r = s.range(of: "\\d{4}", options: .regularExpression) { return String(s[r]) }
        return nil
    }
}

/// «إغلاق» في شريط المربّع السفلي (يسار، مثل «إلغاء» بقية المربّعات) — عرض مستقل
/// حتى يقرأ إغلاق المربّع المتحرّك من داخله (نسخة من PanelCloseButton في تفاصيل العضو)
private struct WomanPanelCloseButton: View {
    @Environment(\.dsPanelClose) private var panelClose
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            if let panelClose { panelClose() } else { dismiss() }
        } label: {
            Text(L10n.t("إغلاق", "Close"))
                .font(DS.Font.plex(15, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(DS.Color.mutedBackground.opacity(0.8)))
        }
        .buttonStyle(DSScaleButtonStyle())
    }
}
