import SwiftUI
import UIKit
import PhotosUI

/// منشورات المناسبات — للإدارة والمشرفين (canModerate).
/// كل شي اختيار بدل الكتابة: القالب، النموذج (١ أو ٢ أو ٣)، مكان النشر (يحدد المقاس)، الاختيارات، الاسم من شجرة العائلة
/// (وتنزل معه صورته وسطور القرابة)، الصورة («مع صورة / بدون صورة» للتهاني و«إعلان عزاء»)، ثم حفظ في الصور أو مشاركة.
/// الشاشة (تجربة طلب المالك ٢٠٢٦-١٠-١٧): الرأس فيه العنوان وزرّا حفظ الصورة والمشاركة؛ تحته معاينة المنشور ثابتة
/// (~٤٠٪ من المساحة، وتصغر مع الكيبورد) وتحتها سطر القالب · مكان النشر · المقاس، والنموذج وحده يتمرّر تحتها.
/// المعاينة تكبر (~٩٠٪) بالسحب لتحت عليها أو بسحب النموذج لتحت من أوله، وترجع بالسحب لفوق أو تمرير النموذج أو بالضغط.
struct OccasionComposerView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @StateObject private var vm = OccasionComposerViewModel()
    @StateObject private var diwaniyasVM = DiwaniyasViewModel()
    @StateObject private var familyNamesVM = FamilyNamesViewModel()
    @ObservedObject private var kit = OccasionKit.shared
    @State private var pickerItem: PhotosPickerItem?
    @State private var showMemberPicker = false
    /// «إعلان عزاء»: قسم «بيانات العزاء» (التشييع، بداية العزاء، العزاءان، الدعاء) مطوي افتراضياً
    @State private var condolenceExpanded = false
    /// المعاينة مكبّرة لفحص التصميم (طلب المالك ٢٠٢٦-١٠-١٧ «لمن انزل تحت يكبر القالب»)
    @State private var previewExpanded = false
    /// حجم المعاينة اللي اختاره المستخدم بالسحب (٠ = الافتراضي) — يتذكّره الجهاز
    /// (طلب المالك ٢٠٢٦-١٠-١٧ «خل اتحكم في مكان القالب اصغره او اكبره»)
    @AppStorage("occasionPreviewHeight") private var chosenPreviewHeight: Double = 0
    /// السحب الجاري على المعاينة (تكبر/تصغر مع الإصبع) — يرجع صفر وحده لو انقطع السحب
    @GestureState private var previewDrag: CGFloat = 0
    /// آخر تكبير/تصغير — مهلة قصيرة حتى ما يرجع التمرير اللي سببه التغيير نفسه يعكسه
    @State private var previewToggledAt = Date.distantPast
    /// متابعة تمرير النموذج (صندوق مرجعي — يتغيّر مع كل إطار تمرير بدون ما يعيد رسم الشاشة)
    @State private var formScroll = OccasionFormScrollTracker()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// نصيب المعاينة الثابتة من المساحة تحت الرأس (الباقي للنموذج اللي يتمرّر) — مع الكيبورد المساحة تنقص فتصغر هي بعد.
    /// كان ٠٫٤٢ — المالك ٢٠٢٦-١٠-١٧ «اصغر الصورة زيادة»
    private static let previewShare: CGFloat = 0.32
    /// أقل ارتفاع للمعاينة (الشاشات الصغيرة والكيبورد ظاهر)
    private static let previewMinHeight: CGFloat = 120
    /// المعاينة المكبّرة: نصيبها من المساحة تحت الرأس (يبقى شريط من النموذج تحتها)
    private static let previewExpandedShare: CGFloat = 0.88
    /// سحب النموذج لتحت من أوله بهالمقدار يكبّر المعاينة، وتمريره لفوق بهالمقدار يصغّرها
    private static let previewPullToExpand: CGFloat = 70
    private static let previewScrollToCollapse: CGFloat = 24
    /// ترك السحب على المعاينة قريب من آخر حد (بهالمقدار) = مكبّرة
    private static let previewSnapToExpanded: CGFloat = 24
    /// خطوة تكبير/تصغير المعاينة لقارئ الشاشة
    private static let previewAccessibilityStep: CGFloat = 60
    /// حول المنشور في المعاينة: الحشوة فوق وتحت، سطر القالب · المكان · المقاس، والمقبض
    private static let previewPad = DS.Spacing.sm
    private static let previewInfoHeight: CGFloat = 18
    private static let previewGrabber = CGSize(width: 36, height: 5)
    private static var previewChrome: CGFloat { 2 * previewPad + previewInfoHeight + previewGrabber.height + 2 * DS.Spacing.xs }
    /// شفافية أرضية المعاينة الثابتة: regularMaterial ما بان شي تحتها، و٠٫٥٥ بلا ضباب «شفافة بزيادة» (المالك ٢٠٢٦-١٠-١٧)
    private static let previewBackdropOpacity: Double = 0.7

    var body: some View {
        Group {
            if authVM.canModerate {
                composer
            } else {
                DSEmptyView(L10n.t("هذي الصفحة للإدارة والمشرفين", "Admins and moderators only"),
                            icon: "lock.fill")
            }
        }
        // الرأس الموحّد: العنوان، وفي الطرف حفظ الصورة (الأساسي) والمشاركة
        .dsSubPageHeader(L10n.t("بطاقات التهنئة والتعزية", "Greeting & condolence cards"), icon: "") {
            if authVM.canModerate { headerActions }
        }
        .task(id: vm.assetKey) { await vm.prepareAssets() }
        .task { await loadData() }
        .onChange(of: memberVM.membersVersion) { _ in
            vm.updateFamily(memberVM.allMembers)
        }
        .onChange(of: pickerItem) { item in
            Task { await vm.loadPhoto(item) }
        }
        .sheet(item: $vm.shareItem) { item in
            OccasionShareSheet(items: [item.url])
        }
        .sheet(isPresented: $showMemberPicker) {
            OccasionMemberPickerSheet(family: vm.family, preferDeceased: vm.isDeath || vm.template.kind == .solace) { m in
                withAnimation(DS.Anim.quick) { vm.pickMember(m) }
            }
        }
        .alert(vm.message ?? "", isPresented: Binding(
            get: { vm.message != nil },
            set: { if !$0 { vm.message = nil } }
        )) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        }
    }

    /// أعضاء الشجرة + الديوانيات + أسماء العوائل (للاختيارات)
    private func loadData() async {
        vm.updateFamily(memberVM.allMembers)
        if memberVM.allMembers.isEmpty {
            await memberVM.fetchAllMembers()
            vm.updateFamily(memberVM.allMembers)
        }
        await diwaniyasVM.fetchDiwaniyas()
        vm.updateDiwaniyas(diwaniyasVM.diwaniyas)
        await familyNamesVM.fetch()
        vm.updateFamilyNames(familyNamesVM.activeNames)
    }

    private var composer: some View {
        GeometryReader { geo in
            // المعاينة ما تطول عن اللي يحتاجه المنشور بعرض الشاشة (المكبّرة للمنشور 4:5 يحدّها العرض) — والباقي للنموذج
            let canvas = vm.size.canvas
            let fitsWidth = ((geo.size.width - 2 * DS.Spacing.lg) * canvas.height / canvas.width + Self.previewChrome).rounded()
            let defaultCompact = min(fitsWidth, max(Self.previewMinHeight, (geo.size.height * Self.previewShare).rounded()))
            let expanded = min(fitsWidth, max(defaultCompact, (geo.size.height * Self.previewExpandedShare).rounded()))
            // المدى اللي يتحكّم فيه المستخدم: من أصغر حجم لين المكبّرة — وحجمه المختار داخله (يصغر وحده مع الكيبورد)
            let range = min(Self.previewMinHeight, expanded)...expanded
            let compact = chosenPreviewHeight > 0 ? min(range.upperBound, max(range.lowerBound, CGFloat(chosenPreviewHeight))) : defaultCompact
            let base = previewExpanded ? expanded : compact
            let height = min(range.upperBound, max(range.lowerBound, base + previewDrag))
            // أول النموذج وهو مستقر (من أعلى الشاشة): تحت المعاينة + الحشوة
            let restTop = geo.frame(in: .global).minY + height + DS.Spacing.lg
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                    // يقيس أول النموذج: السحب لتحت من أوله يكبّر المعاينة، والتمرير لفوق يصغّرها
                    Color.clear
                        .frame(height: 0)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
                            formTopChanged(top, restTop: restTop)
                        }
                    // «رابط الموقع» — روابط عامة لمولّد المنشورات على الموقع (المالك والمدير، نفس صلاحية
                    // جدول occasion_links). من النسخة المحلية (٢٠٢٦-١٠-١٢)؛ main ما فيه مقابل في التطبيق.
                    if authVM.isAdmin {
                        OccasionLinksSection()
                    }
                    templateSection
                    if vm.template.models.count > 1 { modelSection }
                    placementSection
                    detailsSection
                    // التهاني و«إعلان عزاء»: القسم دايماً (فيه «مع صورة / بدون صورة»)؛ مشاركة العزاء بدون صورة
                    if vm.template.photoOptional || vm.showsPhoto { photoSection }
                    actions
                }
                .padding(DS.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            // المعاينة ثابتة فوق والنموذج يتمرّر تحتها (يبان خافت من خلف أرضيتها الشفافة شوي)
            .safeAreaInset(edge: .top, spacing: 0) {
                pinnedPreview(height: height, width: geo.size.width, base: base, range: range)
            }
        }
        .background(DS.Color.background.ignoresSafeArea())
    }

    /// top = أول النموذج من أعلى الشاشة الآن، restTop = مكانه وهو مستقر تحت المعاينة.
    /// صغيرة: سحب النموذج لتحت من أوله (top فوق restTop بـ previewPullToExpand) يكبّرها.
    /// مكبّرة: تمرير النموذج لفوق (مسافة previewScrollToCollapse، والنموذج داخل في المعاينة — مو رجوع ارتداد السحب) يصغّرها.
    private func formTopChanged(_ top: CGFloat, restTop: CGFloat) {
        let tracker = formScroll
        defer { tracker.lastTop = top }
        guard previewDrag == 0, Date().timeIntervalSince(previewToggledAt) > 0.45, let last = tracker.lastTop else {
            tracker.upTravel = 0
            return
        }
        if previewExpanded {
            let delta = top - last
            tracker.upTravel = delta < 0 && top < restTop ? tracker.upTravel - delta : 0
            if tracker.upTravel > Self.previewScrollToCollapse {
                tracker.upTravel = 0
                setPreviewExpanded(false)
            }
        } else if top - restTop > Self.previewPullToExpand && top > last {
            // سحب فعلي لتحت (أول النموذج ينزل الحين) — مو فراغ فوق النموذج تركه تصغير المعاينة بالسحب عليها
            setPreviewExpanded(true)
        }
    }

    private func setPreviewExpanded(_ on: Bool) {
        guard on != previewExpanded else { return }
        previewToggledAt = Date()
        // سبرنق التطبيق؛ «تقليل الحركة»: تغيير حجم سريع بلا ارتداد
        withAnimation(reduceMotion ? DS.Anim.quick : DS.Anim.smooth) {
            previewExpanded = on
        }
    }

    private func postView() -> OccasionPostView {
        OccasionPostView(template: vm.layoutTemplate, size: vm.size, values: vm.values, photo: vm.photo,
                         kit: kit, revision: kit.revision, model: vm.model, withPhoto: vm.withPhoto, palette: vm.palette)
    }

    // MARK: الرأس (حفظ الصورة والمشاركة) وسطر المعاينة (القالب · مكان النشر · المقاس)

    /// «عقد قران · انستقرام — منشور · 1,080×1,350» — تحت المعاينة الثابتة
    private var previewInfo: String {
        let c = vm.size.canvas
        // المقاس معزول باتجاه LTR (U+2066…U+2069) حتى ما ينقلب «1,080×1,350» داخل السطر العربي
        return "\(vm.template.title) · \(vm.placement.title) · \u{2066}\(Self.pixels(c.width))×\(Self.pixels(c.height))\u{2069}"
    }

    /// أرقام لاتينية بفاصل الآلاف (1,080) مثل الموقع
    private static func pixels(_ v: CGFloat) -> String {
        Int(v).formatted(.number.locale(Locale(identifier: "en_US")))
    }

    /// المشاركة زر الرأس العادي (أهدأ)، وحفظ الصورة الإجراء الأساسي: دائرة بيضاء ممتلئة ورمز كحلي في طرف الرأس
    private var headerActions: some View {
        HStack(spacing: DS.Spacing.xs) {
            if vm.isWorking {
                ProgressView()
                    .tint(DS.Color.headerGlyph)
                    .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
            } else {
                DSHeaderButton(symbol: "square.and.arrow.up", label: L10n.t("مشاركة", "Share")) {
                    Task { await vm.share() }
                }
                Button {
                    Task { await vm.saveToPhotos() }
                } label: {
                    Image(systemName: "photo.badge.arrow.down")
                        .font(DS.Font.scaled(DSBox.navGlyph, weight: .bold))
                        .foregroundColor(DS.Color.primaryFill)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .frame(width: DSBox.navButtonOnColor, height: DSBox.navButtonOnColor)
                        .background(Circle().fill(DS.Color.textOnPrimary))
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("حفظ الصورة", "Save image"))
            }
        }
        // ناقص حقل مطلوب: الزرّان باهتان (والضغط يقول وش الناقص)
        .opacity(vm.missing.isEmpty ? 1 : 0.5)
    }

    // MARK: المعاينة الثابتة فوق النموذج

    private func pinnedPreview(height: CGFloat, width: CGFloat, base: CGFloat, range: ClosedRange<CGFloat>) -> some View {
        let canvas = vm.size.canvas
        let pad = Self.previewPad
        /// سطر القالب · مكان النشر · المقاس تحت المعاينة (ثابت معها)، والمقبض تحته يلمّح إن المعاينة تنسحب
        let infoHeight = Self.previewInfoHeight
        let grabber = Self.previewGrabber
        let scale = min((height - Self.previewChrome) / canvas.height, (width - 2 * DS.Spacing.lg) / canvas.width)
        return VStack(spacing: DS.Spacing.xs) {
            ZStack(alignment: .bottom) {
                postView()
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: canvas.width * scale, height: canvas.height * scale, alignment: .topLeading)
                    .environment(\.layoutDirection, .leftToRight)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(DS.Color.cardBorder, lineWidth: 1)
                    )
                    .overlay {
                        if kit.isLoading || !kit.fontsReady {
                            ProgressView()
                                .padding(DS.Spacing.md)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        }
                    }
                    .dsCardShadow()
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.t("معاينة المنشور", "Post preview"))
                    .accessibilityHint(L10n.t("اسحب لتحت أو لفوق لتكبير المعاينة أو تصغيرها — تبقى بالحجم اللي تختاره",
                                              "Drag down or up to resize the preview — it stays at the size you choose"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { setPreviewExpanded(!previewExpanded) }
                    // قارئ الشاشة: تمرير لفوق/لتحت يكبّر/يصغّر بخطوات
                    .accessibilityAdjustableAction { direction in
                        let step = direction == .increment ? Self.previewAccessibilityStep : -Self.previewAccessibilityStep
                        let target = min(range.upperBound, max(range.lowerBound, base + step))
                        withAnimation(DS.Anim.quick) {
                            chosenPreviewHeight = Double(target.rounded())
                            previewExpanded = false
                        }
                    }
                if kit.failed {
                    Button {
                        Task { await vm.prepareAssets() }
                    } label: {
                        Label(L10n.t("تعذّر تحميل ملفات التصميم — إعادة المحاولة", "Couldn't load design files — retry"),
                              systemImage: "arrow.clockwise")
                            .font(DS.Font.caption1)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.bottom, pad)
                }
            }
            Text(previewInfo)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: infoHeight)
                .padding(.horizontal, DS.Spacing.lg)
            Capsule()
                .fill(DS.Color.textTertiary.opacity(0.45))
                .frame(width: grabber.width, height: grabber.height)
                .accessibilityHidden(true)
        }
        .padding(.vertical, pad)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        // أرضية شوي شفافة (طلب المالك ٢٠٢٦-١٠-١٧): ضباب خفيف + لون الصفحة بشفافية — أشكال النموذج اللي يتمرّر تحت
        // المعاينة تبان خافتة من الجنبين وتحت سطر المعلومات بلا ما ينقرأ الكلام (فاتح وداكن)، والمنشور نفسه معتم
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                DS.Color.background.opacity(Self.previewBackdropOpacity)
            }
        }
        // حدّ المعاينة: النموذج يتمرّر تحت هذا الخط
        .overlay(alignment: .bottom) { Divider() }
        .contentShape(Rectangle())
        // الضغط يكبّر لآخر حد / يرجع لحجمك. السحب لتحت يكبّر ولفوق يصغّر، والحجم يوقف وين ما تترك إصبعك
        // (يتذكّره الجهاز)؛ الترك قريب من آخر حد = مكبّرة
        .onTapGesture { setPreviewExpanded(!previewExpanded) }
        .gesture(
            DragGesture(minimumDistance: 8)
                .updating($previewDrag) { g, drag, _ in drag = g.translation.height }
                .onEnded { g in
                    let target = min(range.upperBound, max(range.lowerBound, base + g.translation.height))
                    if target >= range.upperBound - Self.previewSnapToExpanded {
                        setPreviewExpanded(true)
                    } else {
                        previewToggledAt = Date()
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) {
                            chosenPreviewHeight = Double(target.rounded())
                            previewExpanded = false
                        }
                    }
                }
        )
        // الكتابة في حقل: المعاينة ترجع صغيرة حتى يبان الحقل فوق الكيبورد
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            setPreviewExpanded(false)
        }
    }

    // MARK: القالب

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSSectionHeader(title: L10n.t("القالب", "Template"), icon: "square.grid.2x2.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(vm.templates) { t in
                        // مربع المناسبة بلونها (occ-*) ورمز أبيض — إعلان العزاء كحلي ليلي بحلقة ورمز ذهبي — مثل الموقع (OccasionTile)
                        OccasionOptionTile(title: t.title, icon: t.icon, disc: t.tileStyle, isOn: t.id == vm.template.id) {
                            withAnimation(DS.Anim.quick) { vm.select(t) }
                        }
                        .frame(width: 104)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: النموذج

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSSectionHeader(title: L10n.t("النموذج", "Design"), icon: "rectangle.on.rectangle")
            HStack(spacing: DS.Spacing.sm) {
                ForEach(vm.template.models) { m in
                    modelCard(m)
                }
            }
        }
    }

    /// نفس مربع القالب (OccasionOptionTile): قرص الرسمة، الاسم، وشكل الصورة — والمختار بالذهبي مثله، ثلاثة في سطر
    private func modelCard(_ m: OccasionModel) -> some View {
        // القالب أو النسخة اللي ما فيها صورة (مشاركة العزاء، «بدون صورة») يقول «بدون صورة»
        OccasionOptionTile(title: m.title, subtitle: vm.showsPhoto ? m.subtitle : L10n.t("بدون صورة", "No photo"),
                           icon: m.symbol, disc: (DS.Color.primaryFill, .clear, DS.Color.textOnPrimary),
                           isOn: vm.effectiveModel == m) {
            withAnimation(DS.Anim.quick) { vm.model = m }
        }
    }

    // MARK: مكان النشر

    private var placementSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSSectionHeader(title: L10n.t("مكان النشر", "Where to post"), icon: "paperplane.fill")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: DS.Spacing.sm)], spacing: DS.Spacing.sm) {
                ForEach(vm.placements) { p in
                    let on = p.id == vm.placement.id
                    Button {
                        withAnimation(DS.Anim.quick) { vm.placement = p }
                    } label: {
                        // نفس عائلة مربعات القالب والنموذج: حدّ شعري، والمختار ذهبي
                        Text(p.title)
                            .font(DS.Font.plex(13, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundColor(DS.Color.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .padding(.horizontal, DS.Spacing.sm)
                            .occasionTile(isOn: on)
                    }
                    .buttonStyle(DSScaleButtonStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if vm.size == .story {
                Text(L10n.t("الستوري فيه هوامش أمان فوق وتحت حتى ما تغطيها أزرار التطبيقات.",
                            "Stories keep safe margins at the top and bottom so app buttons don't cover the content."))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
    }

    // MARK: التفاصيل (اختيارات)

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSSectionHeader(title: L10n.t("التفاصيل", "Details"), icon: "checklist")
            // «الألوان» أول شي في التفاصيل (مثل الموقع)
            if vm.template.hasPalette { paletteCard }
            HStack(spacing: DS.Spacing.sm) {
                Text(L10n.t("اختر من القوائم — والكتابة متاحة من «نص آخر»", "Pick from the lists — use “Other” to type"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)
                Spacer(minLength: 0)
                Button(L10n.t("بدء من جديد", "Start over")) {
                    withAnimation(DS.Anim.quick) { vm.resetForm() }
                }
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.primary)
            }
            switch vm.template.kind {
            case .happy: happyForm
            case .death, .deathText: deathForm
            case .solace: solaceForm
            }
        }
    }

    /// «الألوان» («إعلان عزاء» و«مشاركة عزاء»): «فحمي وفضي» (الافتراضي) أو «الأصلية» — للنماذج الثلاثة (طلب المالك ٢٠٢٦-١٠-١٧)
    private var paletteCard: some View {
        OccasionFormCard(title: L10n.t("الألوان", "Colours"), hint: L10n.t("لكل النماذج", "All designs")) {
            OccasionChips(options: OccasionPalette.allCases.map(\.title),
                          selected: OccasionPalette.allCases.firstIndex(of: vm.palette) ?? 0) { i in
                withAnimation(DS.Anim.quick) { vm.palette = OccasionPalette.allCases[i] }
            }
        }
    }

    private func genderChips(_ labels: [String]) -> some View {
        OccasionChips(options: labels, selected: vm.gender == .male ? 0 : 1) { i in
            withAnimation(DS.Anim.quick) { vm.setGender(i == 0 ? .male : .female) }
        }
    }

    private func toggle(_ key: String) -> Binding<Bool> {
        Binding(get: { vm.sel(key) == 1 },
                set: { on in withAnimation(DS.Anim.quick) { vm.setSel(key, on ? 1 : 0) } })
    }

    // MARK: الاسم (من الشجرة أو كتابة)

    private func nameSection(_ title: String) -> some View {
        OccasionFormCard(title: title, hint: L10n.t("سطر واحد — إذا طال ينختصر تلقائياً", "One line — shortened automatically if long")) {
            if let m = vm.member {
                selectedMember(m)
            } else {
                if vm.gender == .male && !vm.family.isEmpty {
                    Button {
                        showMemberPicker = true
                    } label: {
                        Label(L10n.t("اختر من شجرة العائلة", "Pick from the family tree"), systemImage: "magnifyingglass")
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textOnPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Capsule().fill(DS.Color.primary))
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
                OccasionTextInput(
                    text: vm.text("nameTyped"),
                    placeholder: vm.gender == .male && !vm.family.isEmpty
                        ? L10n.t("أو اكتب الاسم هنا", "Or type the name here")
                        : L10n.t("اكتب الاسم", "Type the name")
                )
            }
            if vm.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                OccasionRequiredHint(L10n.t("مطلوب — اختر الاسم من الشجرة أو اكتبه", "Required — pick the name from the tree or type it"))
            } else {
                formatPicker("name")
            }
        }
    }

    /// صيغة عنصر اسم (سداسي … ثلاثي) — تظهر لما يكون فيه أكثر من صيغة
    @ViewBuilder
    private func formatPicker(_ key: String) -> some View {
        if let r = vm.nameResolution(key) {
            OccasionNameFormatPicker(resolution: r) { n in
                withAnimation(DS.Anim.quick) { vm.setNameCount(key, n) }
            }
        }
    }

    private func selectedMember(_ m: FamilyMember) -> some View {
        HStack(spacing: DS.Spacing.md) {
            OccasionMemberAvatar(member: m, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.nameResolution("name")?.option.name ?? vm.name)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                HStack(spacing: DS.Spacing.xs) {
                    Text(m.isDeceased == true
                         ? L10n.t("من شجرة العائلة · متوفى", "From the family tree · deceased")
                         : L10n.t("من شجرة العائلة", "From the family tree"))
                    if vm.isLoadingMemberPhoto {
                        ProgressView().controlSize(.mini)
                    }
                }
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textTertiary)
            }
            Spacer(minLength: 0)
            Button(L10n.t("تغيير", "Change")) { showMemberPicker = true }
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.primary)
            Button {
                withAnimation(DS.Anim.quick) { vm.clearMember() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.Font.icon(18))
                    .foregroundColor(DS.Color.textTertiary)
            }
            .accessibilityLabel(L10n.t("إلغاء الاختيار", "Clear selection"))
        }
        .padding(DS.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(DS.Color.primary.opacity(0.08))
        )
    }

    // MARK: التهاني

    private var happyForm: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            happyRecipient
            happyGreeting
            nameSection(L10n.t("الاسم", "Name"))
            if vm.template.id == "graduation" {
                graduationCard
            } else {
                occasionCard
            }
            if vm.template.id == "newborn" || vm.template.id == "newbornGirl" {
                babyNameCard
            }
            duaCard(OccasionChoices.duas(vm.template.id, vm.gender))
        }
    }

    /// له/لها + الصفة في قائمة منسدلة (طلب المالك ٢٠٢٦-١٠-١٧) فيها «نص آخر» لصفة مكتوبة
    private var happyRecipient: some View {
        OccasionFormCard(title: L10n.t("لمن التهنئة", "Congratulating")) {
            genderChips([L10n.t("له", "Him"), L10n.t("لها", "Her")])
            OccasionMenuField(
                options: OccasionChoices.honorifics(vm.gender),
                selected: vm.sel("honor"),
                onSelect: { i in withAnimation(DS.Anim.quick) { vm.setSel("honor", i) } },
                icon: "person.fill",
                custom: OccasionCustomOption(text: vm.text("honorCustom"),
                                             placeholder: L10n.t("اكتب الصفة — مثال: الأخ الغالي", "Type the title")),
                accessibilityTitle: L10n.t("الصفة", "Title")
            )
        }
    }

    private var happyGreeting: some View {
        let honor = OccasionChoices.honor(vm.form)
        let openings = OccasionChoices.openings(vm.template.id).map { OccasionChoices.composeIntro($0, honor: honor) }
        return OccasionFormCard(title: L10n.t("صيغة التهنئة", "Greeting")) {
            OccasionChips(
                options: openings,
                selected: vm.sel("opening"),
                onSelect: { vm.setSel("opening", $0) },
                custom: OccasionCustomOption(text: vm.text("introCustom"), placeholder: L10n.t("اكتب سطر التهنئة", "Type the greeting line"))
            )
        }
    }

    private var graduationCard: some View {
        OccasionFormCard(title: L10n.t("التخرج", "Graduation")) {
            OccasionFieldLabel(L10n.t("المرحلة", "Degree"))
            OccasionChips(options: OccasionChoices.degrees, selected: vm.sel("degree")) { vm.setSel("degree", $0) }
            if vm.sel("degree") > 0 {
                OccasionFieldLabel(L10n.t("الجهة", "Institution"))
                OccasionChips(
                    options: OccasionChoices.institutions,
                    selected: vm.sel("inst"),
                    onSelect: { vm.setSel("inst", $0) },
                    custom: OccasionCustomOption(text: vm.text("instCustom"),
                                                 placeholder: L10n.t("اسم الجامعة أو الكلية", "University or college"),
                                                 label: L10n.t("جهة أخرى", "Other"))
                )
            }
        }
    }

    private var occasionCard: some View {
        OccasionFormCard(title: L10n.t("المناسبة", "Occasion")) {
            OccasionChips(
                options: OccasionChoices.occasions(vm.template.id, vm.gender),
                selected: vm.sel("occasion"),
                onSelect: { vm.setSel("occasion", $0) },
                custom: OccasionCustomOption(text: vm.text("occasionCustom"), placeholder: L10n.t("اكتب سطر المناسبة", "Type the occasion line"))
            )
        }
    }

    private var babyNameCard: some View {
        let isBoy = vm.template.id == "newborn"
        let kids = vm.babyNameSuggestions
        return OccasionFormCard(
            title: isBoy ? L10n.t("اسم المولود", "Baby's name") : L10n.t("اسم المولودة", "Baby's name"),
            hint: kids.isEmpty ? nil : L10n.t("أبناؤه من الشجرة — الأحدث أولاً", "His children from the tree — newest first")
        ) {
            OccasionQuickText(text: vm.text("sub"), suggestions: kids, placeholder: L10n.t("اكتب الاسم", "Type the name"))
            if vm.form.txt("sub").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                OccasionRequiredHint(isBoy ? L10n.t("مطلوب — اكتب اسم المولود", "Required — type the baby's name")
                                           : L10n.t("مطلوب — اكتب اسم المولودة", "Required — type the baby's name"))
            }
        }
    }

    private func duaCard(_ options: [String]) -> some View {
        OccasionFormCard(title: L10n.t("الدعاء", "Prayer")) {
            OccasionTextCards(
                options: options,
                selected: vm.sel("dua"),
                onSelect: { vm.setSel("dua", $0) },
                noneLabel: L10n.t("بدون دعاء", "No prayer"),
                custom: OccasionCustomOption(text: vm.text("duaCustom"), placeholder: L10n.t("اكتب الدعاء", "Type the prayer"))
            )
        }
    }

    // MARK: إعلان عزاء — نموذج واحد للنسختين (مع صورة / بدون صورة) — نفس الموقع (OccasionStudio)
    // كل الحقول للنسختين (اتحاد اللي كان في القالبين)، وكل نسخة ترسم اللي لها: «مع صورة» «صلة القرابة» سطر واحد،
    // و«بدون صورة» الزوج والأبناء والإخوان والتشييع وبداية العزاء — التلميح يقول وش ما يظهر في النسخة الحالية

    private var deathForm: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            deceasedCard
            nameSection(vm.gender == .male ? L10n.t("اسم الفقيد", "Name of the deceased") : L10n.t("اسم الفقيدة", "Name of the deceased"))
            OccasionFormCard(title: L10n.t("صلة القرابة", "Relation"),
                             hint: vm.showsPhoto ? L10n.t("اتركها فاضية لتختفي", "Leave empty to hide") : onlyWithPhotoHint) {
                OccasionQuickText(text: vm.text("relation"), suggestions: vm.relationSuggestions,
                                  placeholder: L10n.t("مثال: والد كل من: الأسماء", "e.g. والد كل من: الأسماء"))
                formatPicker("relation")
            }
            relationsCard
            // «بيانات العزاء» قسم واحد مطوي (طلب المالك ٢٠٢٦-١٠-١٧ «طويل») — ملخّصه سطر لكل عزاء، ويفتح بالضغط
            condolenceDetailsHeader
            if condolenceExpanded {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    funeralCard
                    condolenceCard
                    venueCard("men")
                    venueCard("women")
                    deathDuaCard
                }
                .padding(.leading, DS.Spacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// ملخّص «بيانات العزاء» وهو مطوي: «الرجال: ديوان العائلة · اليوم وغداً وبعد غد، عقب صلاة العصر» (سطر لكل عزاء)
    private var condolenceSummary: [String] {
        let v = vm.values
        var lines: [String] = []
        for (side, label) in [("men", L10n.t("الرجال", "Men")), ("women", L10n.t("النساء", "Women"))] {
            let place = v["\(side)Place"] ?? ""
            guard !place.isEmpty else { continue }
            lines.append("\(label): " + [place, v["\(side)Times"] ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
        }
        return lines.isEmpty ? [L10n.t("بدون أماكن عزاء", "No condolence venues")] : lines
    }

    private var condolenceDetailsHeader: some View {
        Button {
            withAnimation(DS.Anim.quick) { condolenceExpanded.toggle() }
        } label: {
            DSCard(padding: DS.Spacing.md) {
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(L10n.t("بيانات العزاء", "Condolence details"))
                            .font(DS.Font.headline)
                            .foregroundColor(DS.Color.textPrimary)
                        if condolenceExpanded {
                            Text(L10n.t("التشييع، بداية العزاء، أماكن العزاء وأوقاته، والدعاء",
                                        "Funeral, condolence start, venues and times, and the prayer"))
                                .font(DS.Font.caption2)
                                .foregroundColor(DS.Color.textTertiary)
                        } else {
                            ForEach(condolenceSummary, id: \.self) { line in
                                Text(line)
                                    .font(DS.Font.caption1)
                                    .foregroundColor(DS.Color.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(DS.Font.icon(14, weight: .semibold))
                        .foregroundColor(DS.Color.primary)
                        .rotationEffect(.degrees(condolenceExpanded ? 180 : 0))
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        .accessibilityHidden(true)
                }
                .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityHint(condolenceExpanded ? L10n.t("اضغط للطي", "Tap to collapse") : L10n.t("اضغط للفتح", "Tap to expand"))
    }

    private var deceasedCard: some View {
        let g = vm.gender
        return OccasionFormCard(title: L10n.t("الفقيد", "The deceased")) {
            genderChips([L10n.t("فقيد", "Male"), L10n.t("فقيدة", "Female")])
            OccasionFieldLabel(L10n.t("السطر الأول", "First line"))
            OccasionChips(
                options: OccasionChoices.deathLeads(g),
                selected: vm.sel("lead"),
                onSelect: { vm.setSel("lead", $0) },
                custom: OccasionCustomOption(text: vm.text("leadCustom"))
            )
            OccasionFieldLabel(L10n.t("اللقب", "Title"))
            OccasionChips(
                options: OccasionChoices.deathTitles(g),
                selected: vm.sel("title"),
                onSelect: { vm.setSel("title", $0) },
                custom: OccasionCustomOption(text: vm.text("titleCustom"))
            )
        }
    }

    private var relationsCard: some View {
        let male = vm.gender == .male
        return OccasionFormCard(title: L10n.t("القرابة", "Relatives"),
                                hint: noPhotoOnlyHint ?? L10n.t("أي سطر فاضي يختفي", "Empty lines are hidden")) {
            OccasionFieldLabel(L10n.t("الزوج / الزوجة", "Spouse"))
            OccasionTextInput(text: vm.text("rel1"), placeholder: male ? "زوج: الاسم" : "زوجة: الاسم")
            formatPicker("rel1")
            OccasionFieldLabel(L10n.t("الأبناء", "Children"))
            OccasionQuickText(text: vm.text("rel2"), suggestions: vm.sonsSuggestion,
                              placeholder: male ? "والد كل من: الأسماء" : "والدة كل من: الأسماء")
            formatPicker("rel2")
            OccasionFieldLabel(L10n.t("الإخوان", "Brothers"))
            OccasionQuickText(text: vm.text("rel3"), suggestions: vm.brothersSuggestion,
                              placeholder: male ? "شقيق كل من: الأسماء" : "شقيقة كل من: الأسماء")
            formatPicker("rel3")
        }
    }

    private var funeralCard: some View {
        OccasionFormCard(title: L10n.t("التشييع", "Funeral"), hint: noPhotoOnlyHint, toggle: toggle("funeral")) {
            OccasionFieldLabel(L10n.t("اليوم", "Day"))
            OccasionChips(options: OccasionChoices.funeralDays, selected: vm.sel("fDay")) { vm.setSel("fDay", $0) }
            OccasionFieldLabel(L10n.t("الوقت", "Time"))
            OccasionChips(options: OccasionChoices.funeralTimes, selected: vm.sel("fTime")) { vm.setSel("fTime", $0) }
            OccasionFieldLabel(L10n.t("المقبرة", "Cemetery"))
            OccasionChips(
                options: OccasionChoices.cemeteries,
                selected: vm.sel("cem"),
                onSelect: { vm.setSel("cem", $0) },
                custom: OccasionCustomOption(text: vm.text("cemCustom"), label: L10n.t("مقبرة أخرى", "Other"))
            )
        }
    }

    private var condolenceCard: some View {
        OccasionFormCard(title: L10n.t("بداية العزاء", "Condolences start"), hint: noPhotoOnlyHint, toggle: toggle("cond")) {
            DatePicker(L10n.t("التاريخ", "Date"), selection: $vm.form.condolenceDate, displayedComponents: .date)
                .environment(\.calendar, Calendar(identifier: .gregorian))
                .font(DS.Font.callout)
                .tint(DS.Color.primary)
            OccasionFieldLabel(L10n.t("المدة", "Duration"))
            OccasionChips(options: OccasionChoices.durationLabels, selected: vm.sel("dur")) { vm.setSel("dur", $0) }
        }
    }

    /// القرابة كاملة والتشييع وبداية العزاء ترسمهم نسخة «بدون صورة» بس، و«صلة القرابة» نسخة «مع صورة» بس
    private var noPhotoOnlyHint: String? {
        vm.showsPhoto ? L10n.t("يظهر في نسخة «بدون صورة» فقط", "No-photo version only") : nil
    }

    private var onlyWithPhotoHint: String { L10n.t("يظهر في نسخة «مع صورة» فقط", "Photo version only") }

    private func venueCard(_ side: String) -> some View {
        OccasionFormCard(
            title: side == "men" ? L10n.t("عزاء الرجال", "Men's condolences") : L10n.t("عزاء النساء", "Women's condolences"),
            toggle: toggle(side)
        ) {
            OccasionFieldLabel(L10n.t("المكان", "Place"))
            OccasionHusseiniyaMenu(
                place: vm.form.txt("\(side)Place"),
                onPick: { h in withAnimation(DS.Anim.quick) { vm.setVenuePlace(side, h.name) } },
                onOther: { withAnimation(DS.Anim.quick) { vm.pickOtherHusseiniya(side) } }
            )
            OccasionQuickText(
                text: vm.venuePlace(side),
                suggestions: vm.diwaniyas.map(\.title) + OccasionChoices.venuePresets(vm.gender),
                placeholder: L10n.t("ديوان العائلة (إذا تركته فاضي)", "Family diwaniya (if left empty)")
            )
            OccasionFieldLabel(L10n.t("المنطقة", "Area"))
            OccasionAreaField(text: vm.text("\(side)Area"))
            // الأيام والوقت بصيغة النعي الرسمية في الكويت — وفي المنشور «<الأيام>، <الوقت>»
            OccasionFieldLabel(L10n.t("الأيام", "Days"))
            OccasionMenuField(
                options: OccasionChoices.condolenceDays,
                selected: vm.sel("\(side)Days"),
                onSelect: { i in withAnimation(DS.Anim.quick) { vm.setSel("\(side)Days", i) } },
                icon: "calendar",
                noneLabel: L10n.t("بدون أيام", "No days"),
                custom: OccasionCustomOption(text: vm.text("\(side)DaysCustom"),
                                             placeholder: L10n.t("مثال: يومي السبت والأحد", "e.g. Saturday and Sunday")),
                accessibilityTitle: L10n.t("أيام العزاء", "Condolence days")
            )
            // الرجال: «العزاء في المقبرة فقط» آخر القائمة
            OccasionFieldLabel(L10n.t("الوقت", "Time"))
            OccasionMenuField(
                options: OccasionChoices.condolenceTimes(side),
                selected: vm.sel("\(side)Time"),
                onSelect: { i in withAnimation(DS.Anim.quick) { vm.setSel("\(side)Time", i) } },
                icon: "clock",
                noneLabel: L10n.t("بدون وقت", "No time"),
                custom: OccasionCustomOption(text: vm.text("\(side)TimeCustom"),
                                             placeholder: L10n.t("مثال: من الساعة ٨ مساءً", "e.g. from 8 pm")),
                accessibilityTitle: L10n.t("وقت العزاء", "Condolence time")
            )
        }
    }

    private var deathDuaCard: some View {
        let options = OccasionChoices.deathDuas(vm.gender).map { pair in
            [pair.0, pair.1].filter { !$0.isEmpty }.joined(separator: " — ")
        }
        return OccasionFormCard(title: L10n.t("الدعاء", "Prayer")) {
            OccasionTextCards(
                options: options,
                selected: vm.sel("deathDua"),
                onSelect: { vm.setSel("deathDua", $0) },
                noneLabel: L10n.t("بدون دعاء", "No prayer"),
                custom: OccasionCustomOption(text: vm.text("dua1Custom"), placeholder: L10n.t("اكتب الدعاء", "Type the prayer"))
            )
        }
    }

    // MARK: مشاركة العزاء

    private var solaceForm: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            OccasionFormCard(title: L10n.t("من", "From")) {
                OccasionChips(
                    options: OccasionChoices.solaceFrom,
                    selected: vm.sel("from"),
                    onSelect: { vm.setSel("from", $0) },
                    custom: OccasionCustomOption(text: vm.text("fromCustom"))
                )
            }
            OccasionFormCard(title: L10n.t("إلى", "To"), hint: L10n.t("اسم العائلة المعزّى فيها", "The bereaved family")) {
                OccasionQuickText(text: vm.text("toFamily"), suggestions: Array(vm.familyNames.prefix(16)),
                                  placeholder: L10n.t("اكتب اسم العائلة", "Type the family name"))
                if OccasionChoices.solaceFamily(vm.form.txt("toFamily")).isEmpty {
                    OccasionRequiredHint(L10n.t("مطلوب — اكتب اسم العائلة", "Required — type the family name"))
                } else {
                    formatPicker("to")
                }
                OccasionFieldLabel(L10n.t("الصيغة", "Wording"))
                OccasionChips(
                    options: OccasionChoices.solaceToFormats.map { $0.replacingOccurrences(of: "{x}", with: "…") },
                    selected: vm.sel("toFmt")
                ) { vm.setSel("toFmt", $0) }
            }
            OccasionFormCard(title: L10n.t("الفقيد", "The deceased")) {
                genderChips([L10n.t("فقيد", "Male"), L10n.t("فقيدة", "Female")])
                OccasionChips(
                    options: OccasionChoices.solaceLeads(vm.gender),
                    selected: vm.sel("slead"),
                    onSelect: { vm.setSel("slead", $0) },
                    custom: OccasionCustomOption(text: vm.text("sleadCustom"))
                )
            }
            nameSection(vm.gender == .male ? L10n.t("اسم الفقيد", "Name of the deceased") : L10n.t("اسم الفقيدة", "Name of the deceased"))
            duaCard(OccasionChoices.duas("solace", vm.gender))
        }
    }

    // MARK: الصورة

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSSectionHeader(title: L10n.t("الصورة", "Photo"), icon: "photo.fill")
            if vm.template.photoOptional {
                OccasionChips(options: [L10n.t("مع صورة", "With photo"), L10n.t("بدون صورة", "No photo")],
                              selected: vm.withPhoto ? 0 : 1) { i in
                    withAnimation(DS.Anim.quick) { vm.withPhoto = i == 0 }
                }
                if !vm.showsPhoto {
                    Text(vm.isDeath
                         ? L10n.t("مكان الصورة يروح للآية والقرابة والتشييع وبداية العزاء — بخط أكبر.",
                                  "The photo's space goes to the verse, relatives, funeral and condolence start, in larger type.")
                         : L10n.t("مكان الصورة يروح للآية والاسم — بخط أكبر.", "The photo's space goes to the verse and the name, in larger type."))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            if vm.showsPhoto {
                photoControls
            }
        }
    }

    /// اختيار الصورة وضبطها (تظهر لما يكون في البوست صورة)
    private var photoControls: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.md) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(vm.photo.image == nil ? L10n.t("اختيار صورة", "Choose photo") : L10n.t("تغيير الصورة", "Change photo"),
                          systemImage: "photo.on.rectangle")
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.sm + 2)
                        .background(Capsule().fill(DS.Color.primary))
                }
                if vm.photo.image != nil {
                    Button(L10n.t("إزالة", "Remove")) {
                        vm.removePhoto()
                        pickerItem = nil
                    }
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.error)
                }
                Spacer(minLength: 0)
            }
            if vm.photoFromMember {
                Label(L10n.t("صورة العضو من شجرة العائلة — تقدر تغيّرها", "The member's photo from the family tree — you can change it"),
                      systemImage: "checkmark.circle.fill")
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.success)
            }
            Toggle(L10n.t("أبيض وأسود", "Black & white"), isOn: $vm.photo.gray)
                .font(DS.Font.callout)
                .tint(DS.Color.primary)
            if vm.photo.image != nil {
                photoSlider(L10n.t("تكبير", "Zoom"), value: $vm.photo.zoom, range: 1...3)
                photoSlider(L10n.t("يمين / يسار", "Left / right"), value: $vm.photo.x, range: 0...100)
                photoSlider(L10n.t("فوق / تحت", "Up / down"), value: $vm.photo.y, range: 0...100)
            }
            Text(L10n.t("الصورة تبقى على جهازك — ما تنرفع لأي مكان.", "The photo stays on your device — it isn't uploaded anywhere."))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
        }
    }

    private func photoSlider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
            Slider(value: value, in: range)
                .tint(DS.Color.primary)
        }
    }

    // MARK: الحفظ والمشاركة

    private var actions: some View {
        VStack(spacing: DS.Spacing.md) {
            DSPrimaryButton(L10n.t("حفظ في الصور", "Save to Photos"), icon: "square.and.arrow.down", isLoading: vm.isWorking) {
                Task { await vm.saveToPhotos() }
            }
            .opacity(vm.missing.isEmpty ? 1 : 0.5)
            DSSecondaryButton(L10n.t("مشاركة", "Share"), icon: "square.and.arrow.up", color: DS.Color.primary) {
                Task { await vm.share() }
            }
            .disabled(vm.isWorking)
            .opacity(vm.missing.isEmpty ? 1 : 0.5)
            if !vm.missing.isEmpty {
                OccasionRequiredHint(L10n.t("قبل الحفظ أكمل: ", "Before saving, fill in: ") + vm.missing.joined(separator: "، "))
                    .frame(maxWidth: .infinity)
            }
            Text(L10n.t("الصورة تطلع ", "Exports at ") + "\(Int(vm.size.canvas.width))×\(Int(vm.size.canvas.height)) "
                 + L10n.t("بكسل — جاهزة لـ ", "px — ready for ") + vm.placement.title)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }
}

/// ورقة المشاركة (واتساب، انستقرام، حفظ الملف…)
private struct OccasionShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// متابعة تمرير النموذج تحت المعاينة — مرجعي حتى ما تنعاد الشاشة مع كل إطار تمرير
private final class OccasionFormScrollTracker {
    var lastTop: CGFloat?
    /// كم تمرّر النموذج لفوق متتالياً (يصفر لما يرجع لتحت)
    var upTravel: CGFloat = 0
}
