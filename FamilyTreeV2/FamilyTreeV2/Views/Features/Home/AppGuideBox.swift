import SwiftUI

// MARK: - «دليل الاستخدام» (كان «التعليمات») — من علامة المعلومات في الرئيسية (طلب المالك ٢٠٢٦-٠٩-٢٧)
//
// فصول (طلب المالك: «أضيف دليل الاستخدام للواجهات الأخرى»): الشجرة، الرئيسية، الديوانيات،
// حسابي، الإشعارات، ثم (٢٠٢٦-١٠-٠٧، «حتى في التعليمات في دليل الاستخدام») إضافة خبر، المكتبة،
// المشاريع، التواصل — ترحيب بقائمة الفصول ← نقاط الفصل ← «أنهيت الفصل» ← الفصل التالي،
// وشريط تقدّم مقسّم أعلى كل فصل (يُضغط للانتقال)،
// وكل نقطة تدخل بحركة مرتّبة (الرقم ← العنوان ← اللقطة ← الشرح) — ومع «تقليل الحركة» بلا حركة.
//
// تعليمات الشجرة نقطةً نقطة، بصفحات واضحة (طلب المالك: «بالصورة… من الواجهة الحقيقية…
// واضحة ومفهومة كل نقطة»): كل صفحة = رقمها + عنوان عريض + لقطة حقيقية من الشجرة
// (بأسماء تجريبية، فاتح وداكن في Assets: Guide*) عليها إصبع أو دائرة في المكان نفسه
// + سطر شرح واحد. «التالي» ينقل للنقطة التالية، والسحب يرجع.
//   ١ اضغط على الصورة ← يظهر الأبناء   ٢ اضغط على الاسم ← تفاصيل العضو
//   ٣ الرقم فوق الصورة                   ٤ أنت هنا
//   ٥ المتوفّى                            ٦ أزرار الشجرة
// مع «تقليل الحركة»: قبل ← بعد جنباً إلى جنب، والدوائر ثابتة.
// العلامة فيها قسمان منفصلان بمبدّل كبير أعلى المربّع (طلب المالك): «عن التطبيق» أولاً
// (الاسم والإصدار ومصمّم التطبيق — محتوى العلامة الأصلي) ثم «التعليمات» وحدها.

struct AppGuideBox: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// ارتفاع شريحة النقطة يكبر مع خط الجهاز (نص النقطة بمقاس Apple — ٢٠٢٦-١٠-٠٨) فلا يُقصّ سطرها الثالث
    @ScaledMetric(relativeTo: .body) private var slideHeight: CGFloat = GuideMetrics.slideHeight
    @State private var page = 0
    @State private var section: InfoSection = .about
    /// الفصل المفتوح — nil = صفحة الترحيب وقائمة الفصول
    @State private var chapterIndex: Int? = nil

    enum InfoSection: Hashable { case guide, about }

    /// القسم الذي يفتح عليه — علامة المعلومات في الرئيسية على «عن التطبيق»، ومربّع
    /// «دليل الاستخدام» في الإعدادات على الدليل (٢٠٢٦-١٠-٠٧)
    init(startOn: InfoSection = .about) {
        _section = State(initialValue: startOn)
    }

    /// شرائح الفصل: نقاطه ← «أنهيت الفصل»
    private enum Slide: Hashable { case step(Int), done }

    private var chapters: [GuideChapter] { GuideChapter.all }
    private var chapter: GuideChapter? { chapterIndex.map { chapters[$0] } }
    private var pages: [GuidePage] { chapter?.pages ?? [] }
    private var slides: [Slide] { pages.indices.map { Slide.step($0) } + [.done] }
    private var isGuide: Bool { section == .guide }
    private var onDoneSlide: Bool { chapter != nil && page == slides.count - 1 }
    private var hasNextChapter: Bool { (chapterIndex ?? 0) < chapters.count - 1 }

    private var guideActionTitle: String {
        guard chapter != nil else { return L10n.t("ابدأ الجولة", "Start the tour") }
        if onDoneSlide {
            return hasNextChapter ? L10n.t("الفصل التالي", "Next chapter") : L10n.t("تم", "Done")
        }
        return L10n.t("التالي", "Next")
    }

    private var guideActionIcon: String {
        guard chapter != nil else { return "play.fill" }
        if onDoneSlide && !hasNextChapter { return "checkmark" }
        return L10n.isArabic ? "chevron.left" : "chevron.right"
    }

    private func openChapter(_ index: Int) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) {
            chapterIndex = index
            page = 0
        }
    }

    private func advance() {
        guard let current = chapterIndex else { openChapter(0); return }
        if onDoneSlide {
            if hasNextChapter { openChapter(current + 1) } else { dismiss() }
        } else {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) { page += 1 }
        }
    }

    var body: some View {
        DSComposer(
            title: isGuide ? L10n.t("دليل الاستخدام", "User Guide") : L10n.t("عن التطبيق", "About the app"),
            subtitle: isGuide ? (chapter.map { L10n.t("فصل «\($0.title)»", "Chapter: \($0.title)") }
                                 ?? L10n.t("تعرّف على التطبيق خطوة بخطوة", "Learn the app step by step"))
                              : L10n.t("تطبيق عائلة المحمدعلي", "Al-Mohammad Ali family app"),
            icon: isGuide ? "book.pages.fill" : "info.circle.fill",
            tint: DS.Color.actionNavy,
            actionTitle: guideActionTitle,
            actionIcon: guideActionIcon,
            showsAction: isGuide,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: true,
            onSubmit: { advance() },
            onCancel: { dismiss() }
        ) {
            sectionSwitch

            if isGuide {
                guideContent
            } else {
                aboutContent
            }
        }
    }

    // MARK: - مبدّل القسمين — نفس المبدّل الكبير المرتّب في «الإشعارات | المستجدات»

    private var sectionSwitch: some View {
        // «عن التطبيق» أولاً ثم «دليل الاستخدام» (طلب المالك) — ويفتح على «عن التطبيق»
        DSSegmentedSwitch(
            options: [
                DSSegmentOption(id: InfoSection.about, title: L10n.t("عن التطبيق", "About"), icon: "info.circle.fill"),
                DSSegmentOption(id: InfoSection.guide, title: L10n.t("دليل الاستخدام", "User Guide"), icon: "book.pages.fill")
            ],
            selection: $section
        )
    }

    // MARK: - قسم «دليل الاستخدام»

    @ViewBuilder
    private var guideContent: some View {
        if let chapter {
            VStack(spacing: DS.Spacing.sm) {
                chapterBar(chapter)
                progressBar

                TabView(selection: $page) {
                    ForEach(slides.indices, id: \.self) { i in
                        slideView(slides[i], isCurrent: page == i)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: slideHeight)   // بطاقة النقطة كاملة مع ظلّها
                .id(chapter.id)          // فصل جديد = صفحات جديدة من أولها
            }
            .padding(.bottom, DS.Spacing.xs)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
        } else {
            GuideWelcomeView(chapters: chapters, reduceMotion: reduceMotion, onOpen: openChapter)
                .transition(.opacity)
        }
    }

    /// شريط الفصل: رجوع لكل الفصول + اسم الفصل بلونه
    private func chapterBar(_ chapter: GuideChapter) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            // رجوع لكل الفصول — الشريحة الواحدة
            DSChipButton(L10n.t("كل الفصول", "All chapters"),
                         icon: L10n.isArabic ? "chevron.right" : "chevron.left",
                         tint: DS.Color.actionNavy) {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) { chapterIndex = nil }
            }
            .padding(.vertical, DS.Spacing.xsm)

            Spacer(minLength: 0)

            // اسم الفصل بلونه — شارة بنفس مقاس الشريحة
            HStack(spacing: DS.Spacing.xsm) {
                Image(systemName: chapter.icon)
                    .dsGlyph(DS.Glyph.sm)
                    .accessibilityHidden(true)
                Text(chapter.title)
                    .dsFont(.chip)
            }
            .foregroundColor(chapter.tint.dsReadableGlyph)
            .padding(.horizontal, DSBox.chipPadding)
            .frame(minHeight: DSBox.chipHeight)
            .background(Capsule().fill(chapter.tint.dsReadableGlyph.opacity(DS.Opacity.tintFill)))
        }
    }

    @ViewBuilder
    private func slideView(_ slide: Slide, isCurrent: Bool) -> some View {
        switch slide {
        case .step(let i):
            GuidePageView(page: pages[i], number: i + 1, total: pages.count,
                          chapterIcon: chapter?.icon ?? "book.pages.fill",
                          chapterTint: chapter?.tint ?? DS.Color.actionNavy,
                          isCurrent: isCurrent, reduceMotion: reduceMotion)
        case .done:
            GuideDoneView(isCurrent: isCurrent, reduceMotion: reduceMotion,
                          chapterTitle: chapter?.title ?? "",
                          nextTitle: hasNextChapter ? chapters[(chapterIndex ?? 0) + 1].title : nil)
        }
    }

    /// شريط تقدّم مقسّم بعدد النقاط: ما مضى وما أنت فيه كحلي، والباقي رمادي — يُضغط للانتقال
    private var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(pages.indices, id: \.self) { i in
                let slideIndex = i
                let reached = page >= slideIndex
                let current = page == slideIndex
                Capsule()
                    .fill(reached ? DS.Color.actionNavy.dsReadableGlyph : DS.Color.textTertiary.opacity(0.25))
                    .frame(height: current ? 7 : 5)
                    .shadow(color: current ? DS.Color.actionNavy.dsReadableGlyph.opacity(0.45) : .clear, radius: 4)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) { page = slideIndex }
                    }
                    .accessibilityLabel(L10n.t("النقطة \(i + 1) من \(pages.count)", "Step \(i + 1) of \(pages.count)"))
                    .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: page)
    }

    // MARK: - قسم «عن التطبيق» (محتوى العلامة الأصلي: الأيقونة والاسم والإصدار ومصمّم التطبيق)

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return b.map { "\(v) (\($0))" } ?? v
    }

    /// بطاقتان بلغة أقسام المربّعات: التطبيق (أيقونته الحقيقية + الاسم + الإصدار) ثم «عمل هذا التطبيق»
    private var aboutContent: some View {
        VStack(spacing: DSBox.sectionSpacing) {
            HStack(spacing: DS.Spacing.md) {
                // أيقونة التطبيق (الشعار القديم) — طلب المالك ٢٠٢٦-١٠-١٧: يبقى حتى يتبدّل مع الأيقونة الجديدة
                Image("AppIconImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: DSBox.logoSide, height: DSBox.logoSide)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    .dsCardShadow()
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(L10n.t("تطبيق عائلة المحمدعلي", "Al-Mohammad Ali family app"))
                        .font(DSBox.titleFont)
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    HStack(spacing: DS.Spacing.xsm) {
                        // اللمسة الذهبية الواحدة
                        DSGoldDot(size: DS.Icon.legendDotCompact)
                        Text(L10n.t("الإصدار \(appVersion)", "Version \(appVersion)"))
                            .dsFieldFont(.calloutMedium)
                            .foregroundColor(DS.Color.fieldValue)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard(padding: nil)
            .accessibilityElement(children: .combine)
            .dsStaggerIn(1)

            DSComposerSection(title: "عمل هذا التطبيق", icon: "hammer.fill", index: 2) {
                HStack(spacing: DS.Spacing.sm) {
                    DSFieldIcon(name: "person.fill")
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs / 2) {
                        Text("حسن الصايغ")
                            .dsFieldFont(.headline)
                            .foregroundColor(DS.Color.fieldLabel)
                        Text("Made by Hasan Al-Sayegh")
                            .dsFieldFont(.calloutCompactMedium)
                            .foregroundColor(DS.Color.fieldValue)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: DSBox.fieldMinHeight)
                .dsRowBox()
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.bottom, DS.Spacing.xs)
    }
}

// MARK: - تعريف النقاط

private struct GuidePage {
    enum Visual {
        /// إصبع يضغط مكاناً في لقطة «قبل» ← تتحوّل للقطة «بعد»
        case tap(before: String, after: String, at: CGPoint, aspect: CGFloat)
        /// دائرة تنبض حول مكان في لقطة (نصف القطر نسبة من عرض اللقطة)
        case spot(image: String, at: CGPoint, radius: CGFloat, aspect: CGFloat)
        /// شريط أدوات الشجرة بأرقام على كل زر وشرح كل رقم
        case toolbar
        /// إطار مدوّر ينبض حول منطقة في لقطة (مستطيل بنِسَب العرض والارتفاع)
        case rect(image: String, rect: CGRect, aspect: CGFloat)
    }

    let title: String
    let text: String
    let visual: Visual

    static let treeAspect: CGFloat = 1206.0 / 1074.0
    static let nameAspect: CGFloat = 1206.0 / 1545.0

    /// لقطات بقية الواجهات مقصوصة بنفس نسبة لقطات الشجرة
    static let shotAspect: CGFloat = 1206.0 / 1074.0

    static var tree: [GuidePage] {
        [
            GuidePage(title: L10n.t("اضغط على الصورة", "Tap the photo"),
                      text: L10n.t("يظهر أبناء العضو تحته، واضغط عليها مرة ثانية لإخفائهم.",
                                   "The member's children appear below; tap it again to hide them."),
                      visual: .tap(before: "GuideTreeBefore", after: "GuideTreeAfter",
                                   at: CGPoint(x: 0.5, y: 0.71), aspect: treeAspect)),
            GuidePage(title: L10n.t("اضغط على الاسم", "Tap the name"),
                      text: L10n.t("تنفتح تفاصيل العضو: معلوماته وعائلته وصلة القرابة.",
                                   "The member's details open: info, family and kinship."),
                      visual: .tap(before: "GuideNameBefore", after: "GuideNameAfter",
                                   at: CGPoint(x: 0.5, y: 0.485), aspect: nameAspect)),
            GuidePage(title: L10n.t("الرقم فوق الصورة", "The number on the photo"),
                      text: L10n.t("عدد أبناء العضو — والسهم يعني إنك تقدر تفتحهم.",
                                   "How many children the member has — the arrow means you can open them."),
                      visual: .spot(image: "GuideTreeBefore", at: CGPoint(x: 0.435, y: 0.629),
                                    radius: 0.075, aspect: treeAspect)),
            GuidePage(title: L10n.t("أنت هنا", "You are here"),
                      text: L10n.t("الإطار الأخضر وعلامة «أنت هنا» تبيّن مكانك في الشجرة.",
                                   "The green ring and «You» mark show your place in the tree."),
                      visual: .spot(image: "GuideTreeAfter", at: CGPoint(x: 0.5, y: 0.757),
                                    radius: 0.14, aspect: treeAspect)),
            GuidePage(title: L10n.t("المتوفّى", "Deceased"),
                      text: L10n.t("صورته رمادية، وتحت اسمه شريط أحمر فيه سنة الوفاة ثم الميلاد.",
                                   "Their photo is grey, with a red strip under the name showing the death then birth year."),
                      visual: .spot(image: "GuideTreeBefore", at: CGPoint(x: 0.5, y: 0.35),
                                    radius: 0.15, aspect: treeAspect)),
            GuidePage(title: L10n.t("أزرار الشجرة", "Tree buttons"),
                      text: L10n.t("هذي الأزرار في أعلى الشجرة.",
                                   "These buttons are at the top of the tree."),
                      visual: .toolbar)
        ]
    }
}

// MARK: - فصول الدليل (كل واجهة فصل)

private struct GuideChapter: Identifiable {
    let id: String
    let title: String
    let icon: String
    let tint: Color
    let pages: [GuidePage]

    /// كل فصل بلون قسمه من `AppSection` (عائلة البحري الواحدة) — الإشعارات من الرئيسية
    static var all: [GuideChapter] {
        [
            GuideChapter(id: "tree", title: L10n.t("الشجرة", "Tree"), icon: "tree.fill",
                         tint: AppSection.tree.fill, pages: GuidePage.tree),
            GuideChapter(id: "home", title: L10n.t("الرئيسية", "Home"), icon: "house.fill",
                         tint: AppSection.home.fill, pages: GuidePage.home),
            // رمز الديوانيات الموحّد «مجلس» (sofa.fill) — قرار المالك ٢٠٢٦-١٠-٠٧ (كان map.fill)
            GuideChapter(id: "diwaniyas", title: L10n.t("الديوانيات", "Diwaniyas"), icon: "sofa.fill",
                         tint: AppSection.diwaniyas.fill, pages: GuidePage.diwaniyas),
            GuideChapter(id: "profile", title: L10n.t("حسابي", "My Account"), icon: "person.crop.circle.fill",
                         tint: AppSection.profile.fill, pages: GuidePage.profile),
            GuideChapter(id: "notifications", title: L10n.t("الإشعارات", "Notifications"), icon: "bell.badge.fill",
                         tint: AppSection.home.fill, pages: GuidePage.notifications),
            // فصول أقسام الرئيسية (٢٠٢٦-١٠-٠٧) — كل فصل بلون قسمه؛ «التواصل» = رسائل الإدارة → لون الإدارة
            GuideChapter(id: "addNews", title: L10n.t("إضافة خبر", "Add a post"), icon: "newspaper.fill",
                         tint: AppSection.news.fill, pages: GuidePage.addNews),
            GuideChapter(id: "library", title: L10n.t("المكتبة", "Library"), icon: "books.vertical.fill",
                         tint: AppSection.library.fill, pages: GuidePage.library),
            GuideChapter(id: "projects", title: L10n.t("المشاريع", "Projects"), icon: "briefcase.fill",
                         tint: AppSection.projects.fill, pages: GuidePage.projects),
            GuideChapter(id: "contact", title: L10n.t("التواصل", "Contact"), icon: "envelope.fill",
                         tint: AppSection.admin.fill, pages: GuidePage.contact)
        ]
    }
}

extension GuidePage {
    fileprivate static var home: [GuidePage] {
        [
            GuidePage(title: L10n.t("الجرس", "The bell"),
                      text: L10n.t("إشعاراتك هنا: الردود والموافقات وأخبار العائلة — والنقطة الحمراء تعني جديد.",
                                   "Your notifications: replies, approvals and family news — a red dot means new."),
                      visual: .spot(image: "GuideHomeTop", at: CGPoint(x: 0.174, y: 0.133),
                                    radius: 0.07, aspect: shotAspect)),
            GuidePage(title: L10n.t("علامة المعلومات", "The info mark"),
                      text: L10n.t("تفتح «عن التطبيق» و«دليل الاستخدام» — هذا الدليل.",
                                   "Opens «About» and the «User Guide» — this guide."),
                      visual: .spot(image: "GuideHomeTop", at: CGPoint(x: 0.08, y: 0.133),
                                    radius: 0.07, aspect: shotAspect)),
            GuidePage(title: L10n.t("أقسام التطبيق", "App sections"),
                      text: L10n.t("كل بلاطة تفتح قسماً: الشجرة، الديوانيات، المكتبة، المشاريع، والتواصل.",
                                   "Each tile opens a section: tree, diwaniyas, library, projects and contact."),
                      visual: .rect(image: "GuideHomeTiles", rect: CGRect(x: 0.03, y: 0.012, width: 0.94, height: 0.596),
                                    aspect: shotAspect)),
            GuidePage(title: L10n.t("الأخبار والمناسبات", "News & occasions"),
                      text: L10n.t("اضغط لتفتح كل الأخبار، وتفاعل بالإعجاب والتعليق، وأضف خبرك من زر + داخل صفحة الأخبار.",
                                   "Tap to open all news, like and comment, and add your own from the + button inside the news page."),
                      visual: .rect(image: "GuideHomeNews", rect: CGRect(x: 0.035, y: 0.049, width: 0.931, height: 0.902),
                                    aspect: shotAspect))
        ]
    }

    fileprivate static var diwaniyas: [GuidePage] {
        [
            GuidePage(title: L10n.t("الفلتر", "Filter"),
                      text: L10n.t("اختر: الكل أو الديوانيات أو الحسينيات — والرقم عددها.",
                                   "Choose all, diwaniyas or husseiniyas — the number is how many."),
                      visual: .rect(image: "GuideDiwTop", rect: CGRect(x: 0.128, y: 0.034, width: 0.844, height: 0.112),
                                    aspect: shotAspect)),
            GuidePage(title: L10n.t("اتصال", "Call"),
                      text: L10n.t("اتصل بصاحب الديوانية مباشرة — وفوقه موعدها وموقعها.",
                                   "Call the host directly — the time and place are right above."),
                      visual: .spot(image: "GuideDiwTop", at: CGPoint(x: 0.635, y: 0.558),
                                    radius: 0.1, aspect: shotAspect)),
            GuidePage(title: L10n.t("زر الخيارات", "Options"),
                      text: L10n.t("للإبلاغ عن ديوانية — ولصاحبها التعديل والحذف.",
                                   "Report a diwaniya — its host can also edit or delete it."),
                      visual: .spot(image: "GuideDiwTop", at: CGPoint(x: 0.126, y: 0.296),
                                    radius: 0.075, aspect: shotAspect)),
            GuidePage(title: L10n.t("أضف ديوانيتك", "Add yours"),
                      text: L10n.t("أضف ديوانيتك أو حسينيتك، وتظهر للجميع بعد موافقة الإدارة.",
                                   "Add your diwaniya or husseiniya; everyone sees it after admin approval."),
                      visual: .spot(image: "GuideDiwAdd", at: CGPoint(x: 0.119, y: 0.885),
                                    radius: 0.09, aspect: shotAspect))
        ]
    }

    fileprivate static var profile: [GuidePage] {
        [
            GuidePage(title: L10n.t("تعديل بياناتك", "Edit your info"),
                      text: L10n.t("اضغط القلم لتعديل صورتك وبياناتك — أول ٣ تعديلات لكل حقل مباشرة، وبعدها بموافقة الإدارة.",
                                   "Tap the pencil to edit your photo and info — the first 3 changes to each field apply directly, then admin approval."),
                      visual: .spot(image: "GuideProfileTop", at: CGPoint(x: 0.218, y: 0.744),
                                    radius: 0.07, aspect: shotAspect)),
            GuidePage(title: L10n.t("رمز QR", "QR code"),
                      text: L10n.t("يعرض رمزك لتشاركه مع قريبك.",
                                   "Shows your code to share with a relative."),
                      visual: .spot(image: "GuideProfileInfo", at: CGPoint(x: 0.131, y: 0.292),
                                    radius: 0.075, aspect: shotAspect)),
            GuidePage(title: L10n.t("مسح", "Scan"),
                      text: L10n.t("امسح رمز قريبك لتعرف صلة القرابة بينكم.",
                                   "Scan a relative's code to see how you're related."),
                      visual: .spot(image: "GuideProfileInfo", at: CGPoint(x: 0.292, y: 0.292),
                                    radius: 0.09, aspect: shotAspect)),
            // «طلباتي» بترتيب الصفحة: المعلومات ← طلباتي ← عائلتي
            GuidePage(title: L10n.t("طلباتي", "My requests"),
                      text: L10n.t("طلباتك المرسلة للإدارة تظهر هنا «تحت المراجعة» — واضغط «سحب» لإلغاء أي طلب.",
                                   "Requests you sent to the admins show here «Under review» — tap «Withdraw» to cancel one."),
                      visual: .rect(image: "GuideProfileRequests", rect: CGRect(x: 0.035, y: 0.21, width: 0.93, height: 0.613),
                                    aspect: shotAspect)),
            GuidePage(title: L10n.t("عائلتي", "My family"),
                      text: L10n.t("يظهر لما تكون حالتك «متزوج»: أضف زوجتك واختر أمك، و«إضافة ابن» لابن أو بنت بموافقة الإدارة.",
                                   "Shows when your status is «Married»: add your wife and pick your mother; «Add child» adds a son or daughter after admin approval."),
                      visual: .rect(image: "GuideProfileFamily", rect: CGRect(x: 0.035, y: 0.164, width: 0.93, height: 0.707),
                                    aspect: shotAspect)),
            GuidePage(title: L10n.t("الإعدادات", "Settings"),
                      text: L10n.t("المظهر واللغة والإشعارات والخصوصية والأجهزة.",
                                   "Appearance, language, notifications, privacy and devices."),
                      visual: .spot(image: "GuideProfileTop", at: CGPoint(x: 0.093, y: 0.133),
                                    radius: 0.07, aspect: shotAspect))
        ]
    }

    fileprivate static var notifications: [GuidePage] {
        [
            GuidePage(title: L10n.t("الإشعارات | المستجدات", "Notifications | Updates"),
                      text: L10n.t("«الإشعارات» ما يخصّك، و«المستجدات» أخبار التطبيق — والرقم الأحمر يعني جديد.",
                                   "«Notifications» are yours, «Updates» are app news — a red number means new."),
                      visual: .rect(image: "GuideNotifs", rect: CGRect(x: 0.035, y: 0.026, width: 0.93, height: 0.142),
                                    aspect: shotAspect)),
            GuidePage(title: L10n.t("قراءة الكل وتحديد", "Read all & select"),
                      text: L10n.t("علّم الكل مقروءاً، أو حدّد إشعارات بعينها.",
                                   "Mark everything as read, or select specific notifications."),
                      visual: .rect(image: "GuideNotifs", rect: CGRect(x: 0.035, y: 0.175, width: 0.93, height: 0.141),
                                    aspect: shotAspect)),
            GuidePage(title: L10n.t("اضغط الإشعار", "Tap a notification"),
                      text: L10n.t("يفتح تفاصيله — واسحبه لحذفه أو تعليمه مقروءاً.",
                                   "Opens its details — swipe it to delete or mark as read."),
                      visual: .rect(image: "GuideNotifs", rect: CGRect(x: 0.035, y: 0.47, width: 0.93, height: 0.276),
                                    aspect: shotAspect))
        ]
    }

    // MARK: فصول أقسام الرئيسية (٢٠٢٦-١٠-٠٧) — لقطاتها بالشكل الموحّد الجديد (Guide{News,Library,Project,Contact}*)

    /// مواضع بلاطات الأقسام في لقطة `GuideHomeTiles` (نِسَب من اليسار)
    private static let libraryTile = CGRect(x: 0.655, y: 0.32, width: 0.313, height: 0.288)
    private static let projectsTile = CGRect(x: 0.343, y: 0.32, width: 0.314, height: 0.288)
    private static let contactTile = CGRect(x: 0.031, y: 0.32, width: 0.314, height: 0.288)

    fileprivate static var addNews: [GuidePage] {
        [
            GuidePage(title: L10n.t("زر الإضافة", "The add button"),
                      text: L10n.t("افتح «الأخبار والمناسبات» من الرئيسية، واضغط زر + أسفل الصفحة.",
                                   "Open «News & occasions» from Home, then tap the + button at the bottom."),
                      visual: .spot(image: "GuideNewsPage", at: CGPoint(x: 0.119, y: 0.827),
                                    radius: 0.09, aspect: shotAspect)),
            GuidePage(title: L10n.t("التصنيف", "Category"),
                      text: L10n.t("اختر نوع خبرك: إعلان أو زواج أو مولود أو وفاة… ثم اكتبه.",
                                   "Pick the type: announcement, wedding, newborn, obituary… then write it."),
                      visual: .rect(image: "GuideNewsAddTop", rect: CGRect(x: 0.061, y: 0.259, width: 0.878, height: 0.343),
                                    aspect: shotAspect)),
            GuidePage(title: L10n.t("صور وتصويت", "Photos & polls"),
                      text: L10n.t("أضف حتى ٥ صور، أو حوّله تصويتاً بخيارين إلى أربعة.",
                                   "Add up to 5 photos, or turn it into a poll with two to four options."),
                      visual: .rect(image: "GuideNewsAddBottom", rect: CGRect(x: 0.442, y: 0.343, width: 0.483, height: 0.32),
                                    aspect: shotAspect)),
            GuidePage(title: L10n.t("إرسال للمراجعة", "Submit"),
                      text: L10n.t("اضغط «إرسال للمراجعة» — ويظهر خبرك للعائلة بعد موافقة الإدارة.",
                                   "Tap «Submit» — your post appears to the family after admin approval."),
                      visual: .rect(image: "GuideNewsAddBottom", rect: CGRect(x: 0.306, y: 0.744, width: 0.64, height: 0.218),
                                    aspect: shotAspect))
        ]
    }

    fileprivate static var library: [GuidePage] {
        [
            GuidePage(title: L10n.t("افتح المكتبة", "Open the library"),
                      text: L10n.t("من بلاطة «مكتبة العائلة» في الرئيسية: وثائق وصور من تاريخ العائلة.",
                                   "From the «Family Library» tile on Home: documents and photos from the family's history."),
                      visual: .rect(image: "GuideHomeTiles", rect: libraryTile, aspect: shotAspect)),
            // صفحة المكتبة ← الضغط على أول عنصر يفتح تفاصيله وزر «حفظ أو مشاركة» أعلاها
            GuidePage(title: L10n.t("اضغط العنصر", "Tap an item"),
                      text: L10n.t("يفتح تفاصيله وملفه — ومنه تحفظه أو تشاركه.",
                                   "Opens its details and file — save or share it from there."),
                      visual: .tap(before: "GuideLibraryList", after: "GuideLibraryItem",
                                   at: CGPoint(x: 0.735, y: 0.34), aspect: nameAspect)),
            // مربّع «إضافة إلى المكتبة» (يفتحه زر +) — قسم «الملف»: صورة أو PDF
            GuidePage(title: L10n.t("أضف للمكتبة", "Add to the library"),
                      text: L10n.t("اضغط + وأضف صورة أو ملف PDF بعنوانه وسنته — ويظهر للجميع بعد موافقة الإدارة.",
                                   "Tap + and add a photo or PDF with its title and year — everyone sees it after admin approval."),
                      visual: .rect(image: "GuideLibraryAdd", rect: CGRect(x: 0.061, y: 0.245, width: 0.878, height: 0.485),
                                    aspect: shotAspect))
        ]
    }

    fileprivate static var projects: [GuidePage] {
        [
            GuidePage(title: L10n.t("افتح المشاريع", "Open projects"),
                      text: L10n.t("من بلاطة «مشاريع العائلة»: مشاريع أفراد العائلة ومحلاتهم.",
                                   "From the «Family Projects» tile: family members' projects and businesses."),
                      visual: .rect(image: "GuideHomeTiles", rect: projectsTile, aspect: shotAspect)),
            GuidePage(title: L10n.t("حسابات التواصل", "Contact accounts"),
                      text: L10n.t("داخل المشروع: اضغط أي حساب للاتصال أو الواتساب أو فتحه — والضغط المطوّل ينسخه.",
                                   "Inside a project: tap any account to call, WhatsApp or open it — long-press to copy."),
                      visual: .rect(image: "GuideProjectAccounts", rect: CGRect(x: 0.035, y: 0.094, width: 0.93, height: 0.816),
                                    aspect: shotAspect)),
            // مربّع «مشروع جديد» (يفتحه زر +): الشعار والاسم والصور والحسابات
            GuidePage(title: L10n.t("أضف مشروعك", "Add yours"),
                      text: L10n.t("اضغط + وأضف الشعار والاسم والصور والحسابات — يظهر لك فوراً وللجميع بعد الموافقة.",
                                   "Tap + and add the logo, name, photos and accounts — you see it now, everyone after approval."),
                      visual: .rect(image: "GuideProjectsAdd", rect: CGRect(x: 0.05, y: 0.16, width: 0.9, height: 0.83),
                                    aspect: nameAspect)),
            // تفاصيل مشروع العضو نفسه — زر «تعديل» (القلم) أعلاها
            GuidePage(title: L10n.t("صاحب المشروع", "Project owner"),
                      text: L10n.t("أنت صاحب مشروعك: تعدّله أو تحذفه من داخله، والمعلّق منه في «طلباتي».",
                                   "You own your project: edit or delete it from inside it; pending ones are under «Mine»."),
                      visual: .spot(image: "GuideProjectOwner", at: CGPoint(x: 0.233, y: 0.142),
                                    radius: 0.07, aspect: shotAspect))
        ]
    }

    fileprivate static var contact: [GuidePage] {
        [
            GuidePage(title: L10n.t("افتح التواصل", "Open contact"),
                      text: L10n.t("من بلاطة «التواصل» في الرئيسية تراسل إدارة العائلة مباشرة.",
                                   "From the «Contact» tile on Home, message the family admins directly."),
                      visual: .rect(image: "GuideHomeTiles", rect: contactTile, aspect: shotAspect)),
            GuidePage(title: L10n.t("نوع الرسالة", "Message type"),
                      text: L10n.t("اختر: استفسار أو شكوى أو اقتراح أو أخرى، ثم اكتب رسالتك.",
                                   "Choose inquiry, complaint, suggestion or other, then write your message."),
                      visual: .rect(image: "GuideContactType", rect: CGRect(x: 0.061, y: 0.256, width: 0.878, height: 0.339),
                                    aspect: shotAspect)),
            // مربّع «تواصل مع الإدارة» — قسم «بريد الرد» وحقل «بريدك للرد (اختياري)»
            GuidePage(title: L10n.t("الرد", "The reply"),
                      text: L10n.t("الإدارة ترد عليك بالاتصال أو الواتساب — أو بالبريد إذا كتبته.",
                                   "The admins reply by call or WhatsApp — or by email if you add it."),
                      visual: .rect(image: "GuideContactReply", rect: CGRect(x: 0.061, y: 0.471, width: 0.878, height: 0.271),
                                    aspect: shotAspect))
        ]
    }
}

// MARK: - صفحة نقطة واحدة

private struct GuidePageView: View {
    let page: GuidePage
    let number: Int
    let total: Int
    /// أيقونة الفصل ولونه (لون قسمه) — قرص «مجسّمات» في عنوان البطاقة
    let chapterIcon: String
    let chapterTint: Color
    let isCurrent: Bool
    let reduceMotion: Bool
    @State private var start = Date()
    /// دخول مرتّب كلما وصلت للنقطة: القرص ← العنوان ← اللقطة ← الشرح
    @State private var shown = false

    var body: some View {
        // بطاقة بلغة أقسام المربّعات: السطح + إطار ١ نقطة + لمسة «مجسّمات»
        VStack(spacing: DSBox.sectionInnerSpacing) {
            // قرص الفصل + العنوان + رقم النقطة
            HStack(spacing: DS.Spacing.sm) {
                DSStateIcon(chapterIcon, tint: chapterTint.dsReadableGlyph, size: DSBox.alertIcon, mapsChrome: false)
                    .scaleEffect(shown ? 1 : 0.4)
                    .rotationEffect(.degrees(shown ? 0 : -25))
                    .accessibilityHidden(true)
                Text(page.title)
                    .font(DSBox.titleFont)
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .offset(x: shown ? 0 : (L10n.isArabic ? -14 : 14))
                    .opacity(shown ? 1 : 0)
                Spacer(minLength: 0)
                Text(L10n.t("\(number) من \(total)", "\(number) of \(total)"))
                    .dsFont(.chipCompact)
                    .foregroundColor(chapterTint.dsReadableGlyph)
                    .monospacedDigit()
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.xxs + 1)
                    .background(Capsule().fill(chapterTint.dsReadableGlyph.opacity(DS.Opacity.tintFill)))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            visual
                .frame(maxWidth: .infinity)
                .frame(height: GuideMetrics.visualHeight)
                .scaleEffect(shown ? 1 : 0.94)
                .opacity(shown ? 1 : 0)

            Text(page.text)
                .dsFieldFont(.bodySemibold)
                .foregroundColor(DS.Color.fieldValue)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .offset(y: shown ? 0 : 8)
                .opacity(shown ? 1 : 0)
        }
        .padding(DSBox.sectionPadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .guideCard()
        .onAppear { if isCurrent { enter() } }
        .onChange(of: isCurrent) { current in
            if current {
                start = Date()   // تبدأ الحركة من أولها كلما وصلت للنقطة
                enter()
            }
        }
    }

    private func enter() {
        if reduceMotion { shown = true; return }
        shown = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72).delay(0.05)) { shown = true }
    }

    @ViewBuilder
    private var visual: some View {
        switch page.visual {
        case let .tap(before, after, at, aspect):
            if reduceMotion {
                HStack(spacing: DS.Spacing.xs) {
                    GuideTapScene(before: before, after: after, at: at, aspect: aspect, t: 0.95)
                    Image(systemName: L10n.isArabic ? "arrow.left" : "arrow.right")
                        .dsGlyph(DS.Glyph.lgCompact)
                        .foregroundColor(DS.Color.textTertiary)
                        .accessibilityHidden(true)
                    GuideTapScene(before: before, after: after, at: at, aspect: aspect, t: 2.5)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(page.text)
            } else {
                TimelineView(.animation(paused: !isCurrent)) { ctx in
                    let t = max(0, ctx.date.timeIntervalSince(start)).truncatingRemainder(dividingBy: GuideTapScene.period)
                    GuideTapScene(before: before, after: after, at: at, aspect: aspect, t: t)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(page.text)
            }
        case let .spot(image, at, radius, aspect):
            TimelineView(.animation(paused: reduceMotion || !isCurrent)) { ctx in
                GuideSpotScene(image: image, at: at, radius: radius, aspect: aspect,
                               pulse: reduceMotion ? 0.5 : ctx.date.timeIntervalSince(start))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(page.text)
        case .toolbar:
            GuideToolbarScene()
        case let .rect(image, rect, aspect):
            TimelineView(.animation(paused: reduceMotion || !isCurrent)) { ctx in
                GuideRectScene(image: image, rect: rect, aspect: aspect,
                               pulse: reduceMotion ? 0.5 : ctx.date.timeIntervalSince(start))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(page.text)
        }
    }
}

// MARK: - صفحة الترحيب: الأيقونة تطفو وحولها شارات تدور + قائمة الفصول (كل واجهة فصل)

private struct GuideWelcomeView: View {
    let chapters: [GuideChapter]
    let reduceMotion: Bool
    let onOpen: (Int) -> Void
    @State private var shown = false

    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            TimelineView(.animation(paused: reduceMotion)) { ctx in
                emblem(t: reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate)
            }
            .frame(height: GuideMetrics.welcomeArtHeight)
            .scaleEffect(shown ? 1 : 0.85)
            .opacity(shown ? 1 : 0)
            .accessibilityHidden(true)

            VStack(spacing: DS.Spacing.xs) {
                Text(L10n.t("أهلاً بك في دليل الاستخدام", "Welcome to the User Guide"))
                    .dsFont(.pageTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(L10n.t("اختر الواجهة التي تريد التعرّف عليها", "Choose the screen you want to learn"))
                    .dsFieldFont(.bodyCompact)
                    .foregroundColor(DS.Color.fieldValue)
            }
            .multilineTextAlignment(.center)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .accessibilityElement(children: .combine)

            // الفصول بعمودين داخل بطاقة قسم (صفوف عادية لا شبكة كسولة — حتى يُقاس ارتفاع المربّع صح)
            DSComposerSection(title: L10n.t("كل الفصول", "All chapters"), icon: "book.pages.fill", index: 1) {
                VStack(spacing: DS.Spacing.xsm) {
                    ForEach(Array(stride(from: 0, to: chapters.count, by: 2)), id: \.self) { start in
                        HStack(spacing: DS.Spacing.xsm) {
                            ForEach(start..<min(start + 2, chapters.count), id: \.self) { index in
                                chapterRow(chapters[index], index: index)
                                    .opacity(shown ? 1 : 0)
                                    .offset(y: shown || reduceMotion ? 0 : 12)
                                    .animation(reduceMotion ? nil
                                               : .spring(response: 0.5, dampingFraction: 0.8).delay(0.12 + Double(index) * 0.05),
                                               value: shown)
                            }
                            if start + 1 >= chapters.count { Spacer(minLength: 0).frame(maxWidth: .infinity) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xs)
        .onAppear {
            if reduceMotion { shown = true; return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.05)) { shown = true }
        }
    }

    private func chapterRow(_ chapter: GuideChapter, index: Int) -> some View {
        Button { onOpen(index) } label: {
            HStack(spacing: DS.Spacing.sm) {
                // أيقونة «مجسّمات»
                DSStateIcon(chapter.icon, tint: chapter.tint.dsReadableGlyph, size: DS.Icon.rowCompact, mapsChrome: false)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs / 2) {
                    Text(chapter.title)
                        .dsFieldFont(.headlineCompact)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(L10n.t("\(chapter.pages.count) نقاط", "\(chapter.pages.count) points"))
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: DSFieldMetrics.toggleRowHeight)
            .dsCard(padding: nil, radius: DS.Radius.md, fill: DS.Color.background)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(L10n.t("فصل \(chapter.title)، \(chapter.pages.count) نقاط",
                                   "Chapter \(chapter.title), \(chapter.pages.count) points"))
    }

    /// الأيقونة تتنفّس وتطفو، وشارات الفصول تدور حولها ببطء (معتدلة الاتجاه)
    private func emblem(t: Double) -> some View {
        let breathe = (sin(t * 2 * .pi / 3.2) + 1) / 2
        let float = sin(t * 2 * .pi / 4.0) * 3
        let angle = t * 2 * .pi / 20
        let icons = chapters.prefix(5)
        return ZStack {
            Circle()
                .fill(DS.Color.primary.opacity(0.08))
                .frame(width: 112, height: 112)
                .scaleEffect(0.96 + 0.06 * breathe)
            Circle()
                .strokeBorder(DS.Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1.2, dash: [3, 5]))
                .frame(width: 100, height: 100)
            // أيقونة التطبيق (الشعار القديم) حتى يتبدّل مع الأيقونة الجديدة
            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 7, x: 0, y: 4)
                .offset(y: float)
            ForEach(Array(icons.enumerated()), id: \.element.id) { i, chapter in
                let a = angle + Double(i) * 2 * .pi / Double(icons.count)
                Image(systemName: chapter.icon)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(chapter.tint.dsReadableGlyph))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.8))
                    .shadow(color: chapter.tint.opacity(0.3), radius: 4, x: 0, y: 2)
                    .offset(x: cos(a) * 51, y: sin(a) * 51)
            }
        }
    }
}

// MARK: - نهاية الفصل: علامة صح تُرسم ودفعة نقاط ملوّنة + الفصل التالي

private struct GuideDoneView: View {
    let isCurrent: Bool
    let reduceMotion: Bool
    let chapterTitle: String
    let nextTitle: String?
    @State private var shown = false


    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                if !reduceMotion {
                    // دفعة نقاط ذهبية صغيرة — اللمسة الواحدة (بدل النقاط الملوّنة)
                    ForEach(0..<12, id: \.self) { i in
                        let a = Double(i) / 12 * 2 * .pi
                        DSGoldDot(size: i.isMultiple(of: 2) ? 9 : 6)
                            .offset(x: shown ? cos(a) * 92 : 0, y: shown ? sin(a) * 92 : 0)
                            .opacity(shown ? 0 : 1)
                    }
                }
                Circle()
                    .fill(DS.Color.success.opacity(0.12))
                    .frame(width: 140, height: 140)
                    .scaleEffect(shown ? 1 : 0.6)
                Circle()
                    .trim(from: 0, to: shown ? 1 : 0)
                    .stroke(DS.Color.success, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 98, height: 98)
                    .rotationEffect(.degrees(-90))
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundColor(DS.Color.success)
                    .scaleEffect(shown ? 1 : 0.3)
                    .opacity(shown ? 1 : 0)
            }
            .frame(height: GuideMetrics.doneArtHeight)
            .accessibilityHidden(true)

            VStack(spacing: DS.Spacing.xsm) {
                Text(nextTitle == nil ? L10n.t("جاهز!", "All set!")
                                      : L10n.t("أنهيت فصل «\(chapterTitle)»", "«\(chapterTitle)» done"))
                    .dsFont(.celebrationTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(nextTitle.map { L10n.t("التالي: «\($0)» — أو اختر من «كل الفصول»",
                                            "Next: «\($0)» — or pick from «All chapters»") }
                     ?? L10n.t("صرت تعرف أساسيات التطبيق — استمتع به",
                               "You know the app basics now — enjoy it"))
                    .dsFieldFont(.fieldValue)
                    .foregroundColor(DS.Color.fieldValue)
                    .multilineTextAlignment(.center)
            }
            .offset(y: shown ? 0 : 10)
            .opacity(shown ? 1 : 0)
            .accessibilityElement(children: .combine)
        }
        .padding(.top, DS.Spacing.md)
        .padding(DSBox.sectionPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .guideCard()
        .onAppear { if isCurrent { enter() } }
        .onChange(of: isCurrent) { if $0 { enter() } }
    }

    private func enter() {
        if reduceMotion { shown = true; return }
        shown = false
        withAnimation(.easeOut(duration: 0.9).delay(0.1)) { shown = true }
    }
}

// MARK: - مشهد الضغط: لقطة «قبل» + إصبع ← لقطة «بعد»

private struct GuideTapScene: View {
    let before: String
    let after: String
    let at: CGPoint
    let aspect: CGFloat
    let t: Double

    static let period = 4.4

    private static func seg(_ t: Double, _ a: Double, _ b: Double) -> Double {
        min(1, max(0, (t - a) / (b - a)))
    }
    private static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    var body: some View {
        let handIn = Self.ease(Self.seg(t, 0.2, 0.85))
        let handOut = Self.seg(t, 1.1, 1.3)
        let pressX = Self.seg(t, 0.85, 1.05)
        let press = pressX <= 0 || pressX >= 1 ? 0 : (pressX < 0.5 ? pressX * 2 : (1 - pressX) * 2)
        let ripple = Self.seg(t, 0.88, 1.3)
        // الموجة والإصبع يخلصون قبل ما تتحوّل اللقطة — حتى ما تقع الموجة على عنصر ثاني في «بعد»
        let shown = Self.ease(Self.seg(t, 1.3, 1.7)) * (1 - Self.ease(Self.seg(t, 3.7, 4.1)))

        return GuideShot(aspect: aspect) {
            ZStack {
                Image(before).resizable().scaledToFit().opacity(1 - shown)
                Image(after).resizable().scaledToFit().opacity(shown)
            }
        } overlay: { size in
            let target = CGPoint(x: at.x * size.width, y: at.y * size.height)
            let rest = CGPoint(x: size.width * 0.86, y: size.height * 0.96)
            let hand = CGPoint(x: rest.x + (target.x - rest.x) * handIn,
                               y: rest.y + (target.y - rest.y) * handIn)
            ZStack {
                Circle()
                    .stroke(DS.Color.warning, lineWidth: 3)
                    .frame(width: 34, height: 34)
                    .scaleEffect(0.5 + 1.6 * ripple)
                    .opacity(ripple > 0 && ripple < 1 ? (1 - ripple) : 0)
                    .position(target)
                GuideFinger(press: press)
                    .position(x: hand.x + 12, y: hand.y + 15)
                    .opacity(min(1, handIn * 3) * (1 - handOut))
            }
        }
    }
}

// MARK: - مشهد الدائرة: لقطة + دائرة تنبض حول المكان

private struct GuideSpotScene: View {
    let image: String
    let at: CGPoint
    let radius: CGFloat
    let aspect: CGFloat
    /// الوقت للنبض (ثابت مع «تقليل الحركة»)
    let pulse: Double

    var body: some View {
        let wave = (sin(pulse * 2 * .pi / 1.6) + 1) / 2   // ٠…١
        return GuideShot(aspect: aspect) {
            Image(image).resizable().scaledToFit()
        } overlay: { size in
            let center = CGPoint(x: at.x * size.width, y: at.y * size.height)
            let r = radius * size.width
            ZStack {
                // تعتيم خفيف خارج الدائرة حتى يبرز المكان
                Rectangle()
                    .fill(Color.black.opacity(0.28))
                    .mask(
                        Rectangle()
                            .overlay(Circle().frame(width: r * 2, height: r * 2)
                                .position(center)
                                .blendMode(.destinationOut))
                            .compositingGroup()
                    )
                Circle()
                    .stroke(DS.Color.warning, lineWidth: 3)
                    .frame(width: r * 2, height: r * 2)
                    .position(center)
                Circle()
                    .stroke(DS.Color.warning.opacity(0.5 * (1 - wave)), lineWidth: 2)
                    .frame(width: r * 2 * (1 + 0.25 * wave), height: r * 2 * (1 + 0.25 * wave))
                    .position(center)
            }
        }
    }
}

// MARK: - مشهد الإطار: لقطة + إطار مدوّر ينبض حول منطقة (للبطاقات والصفوف)

private struct GuideRectScene: View {
    let image: String
    let rect: CGRect
    let aspect: CGFloat
    let pulse: Double

    var body: some View {
        let wave = (sin(pulse * 2 * .pi / 1.6) + 1) / 2
        return GuideShot(aspect: aspect) {
            Image(image).resizable().scaledToFit()
        } overlay: { size in
            let r = CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
                           width: rect.width * size.width, height: rect.height * size.height)
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.28))
                    .mask(
                        Rectangle()
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .frame(width: r.width, height: r.height)
                                .position(x: r.midX, y: r.midY)
                                .blendMode(.destinationOut))
                            .compositingGroup()
                    )
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.Color.warning, lineWidth: 3)
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(DS.Color.warning.opacity(0.5 * (1 - wave)), lineWidth: 2)
                    .frame(width: r.width + 12 * wave, height: r.height + 12 * wave)
                    .position(x: r.midX, y: r.midY)
            }
        }
    }
}

// MARK: - أزرار الشجرة: الشريط الحقيقي فوق، وتحته أربع بطاقات مرتّبة — لكل زر شكله وعمله

private struct GuideToolbarScene: View {
    private enum Look {
        case circle(String)   // زر دائري بأيقونة (مثل الشجرة)
        case switcher         // مبدّل «شجرة العائلة | النساء»
    }

    private struct Item: Identifiable {
        let id: Int
        let look: Look
        let title: String
        let detail: String
    }

    private var items: [Item] {
        [
            Item(id: 1, look: .circle("magnifyingglass"),
                 title: L10n.t("البحث", "Search"),
                 detail: L10n.t("ابحث عن أي عضو باسمه", "Find any member by name")),
            Item(id: 2, look: .circle("house.fill"),
                 title: L10n.t("البداية", "Start"),
                 detail: L10n.t("يرجعك لأعلى الشجرة", "Back to the top of the tree")),
            Item(id: 3, look: .switcher,
                 title: L10n.t("العائلة / النساء", "Family / Women"),
                 detail: L10n.t("تبدّل بين الشجرتين", "Switch between the two trees")),
            Item(id: 4, look: .circle("location.fill"),
                 title: L10n.t("موقعي", "Me"),
                 detail: L10n.t("يوصلك لمكانك «أنت هنا»", "Takes you to your place"))
        ]
    }

    private let columns = [GridItem(.flexible(), spacing: DS.Spacing.sm),
                           GridItem(.flexible(), spacing: DS.Spacing.sm)]

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            // الشريط الحقيقي كما يظهر أعلى الشجرة
            GuideShot(aspect: 1158.0 / 160.0) {
                Image("GuideTreeToolbar").resizable().scaledToFit()
            } overlay: { _ in EmptyView() }
            .accessibilityHidden(true)

            LazyVGrid(columns: columns, spacing: DS.Spacing.sm) {
                ForEach(items) { item in
                    VStack(spacing: DS.Spacing.xs + 1) {
                        look(item.look)
                            .frame(height: GuideMetrics.toolbarLook)
                        Text(item.title)
                            .dsFieldFont(.rowTitleCompact)
                            .foregroundColor(DS.Color.fieldLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(item.detail)
                            .dsFieldFont(.footnote)
                            .foregroundColor(DS.Color.fieldValue)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, DS.Spacing.sm)
                    .padding(.horizontal, DS.Spacing.xsm)
                    .frame(maxWidth: .infinity, minHeight: GuideMetrics.toolbarCardMinHeight, alignment: .top)
                    .dsCard(padding: nil, radius: DS.Radius.md, fill: DS.Color.background)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// شكل الزر كما في شريط الشجرة
    @ViewBuilder
    private func look(_ look: Look) -> some View {
        switch look {
        case .circle(let icon):
            Image(dsSymbol: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppSection.tree.ink)   // بلون شريط الشجرة الحقيقي (أخضر الشجرة)
                .frame(width: 40, height: 40)
                .background(Circle().fill(DS.Color.surface))
                .overlay(Circle().strokeBorder(DS.Color.textTertiary.opacity(0.25), lineWidth: 1))
                .accessibilityHidden(true)
        case .switcher:
            HStack(spacing: 2) {
                Text(L10n.t("شجرة العائلة", "Family"))
                    .font(DS.Font.plex(10.5, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(DSActionFill.style()))
                Text(L10n.t("النساء", "Women"))
                    .font(DS.Font.plex(10.5, weight: .bold))
                    .foregroundColor(DS.Color.textSecondary)
                    .padding(.horizontal, 6)
            }
            .padding(3)
            .background(Capsule().fill(DS.Color.surface))
            .overlay(Capsule().strokeBorder(DS.Color.textTertiary.opacity(0.25), lineWidth: 1))
            .fixedSize()
            .accessibilityHidden(true)
        }
    }
}

// MARK: - أدوات مشتركة

/// مقاسات رسوم الدليل (لوحات متحرّكة — ليست أجزاء واجهة): مكانها الواحد هنا
private enum GuideMetrics {
    /// شريحة النقطة كاملة مع ظلّها (في الحجم الافتراضي — يكبر مع خط الجهاز)، ولقطتها داخلها؛
    /// ٣٧٦ ← ٤٠٤: ثلاثة أسطر من نص النقطة بمقاس Apple (Body ١٧) تحت اللقطة
    static let slideHeight: CGFloat = 404
    static let visualHeight: CGFloat = 252
    /// شعار صفحة الترحيب، ورسم «أنهيت الفصل»
    static let welcomeArtHeight: CGFloat = 118
    static let doneArtHeight: CGFloat = 190
    /// بطاقات أزرار الشجرة: مكان شكل الزرّ وأقل ارتفاع للبطاقة
    static let toolbarLook: CGFloat = 40
    static let toolbarCardMinHeight: CGFloat = 96
    /// هامش جانبي يحفظ ظلّ البطاقة داخل صفحات الـ TabView
    static let cardInset: CGFloat = 3
}

/// لقطة بإطار موحّد (كل لقطات الدليل): زوايا الصفوف، إطار ١ نقطة، وظلّ خفيف — وطبقة رسم فوقها
/// بنفس مقاسها (الإحداثيات من اليسار دائماً)
private struct GuideShot<Content: View, Overlay: View>: View {
    let aspect: CGFloat
    @ViewBuilder let content: () -> Content
    @ViewBuilder let overlay: (CGSize) -> Overlay

    var body: some View {
        let frame = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        content()
            .aspectRatio(aspect, contentMode: .fit)
            .overlay { GeometryReader { g in overlay(g.size) } }
            .clipShape(frame)
            .overlay(frame.strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.tintFillStrong), lineWidth: DS.Border.width))
            .dsCardShadow()
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// بطاقة شريحة الدليل بلغة أقسام المربّعات (السطح + إطار ١ نقطة + لمسة «مجسّمات») — بهامش يحفظ ظلّها
/// داخل صفحات الـ TabView
private struct GuideCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .dsCard(padding: nil)
            .padding(.horizontal, GuideMetrics.cardInset)
            .padding(.bottom, DS.Spacing.sm)
    }
}

private extension View {
    func guideCard() -> some View { modifier(GuideCard()) }
}

/// الإصبع: أبيض بحدّ أسود — واضح على اللقطات الفاتحة والداكنة
private struct GuideFinger: View {
    let press: Double
    var body: some View {
        ZStack {
            Image(systemName: "hand.point.up.left.fill")
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.45), radius: 4, x: 0, y: 2)
            Image(systemName: "hand.point.up.left")
                .foregroundStyle(Color.black.opacity(0.75))
        }
        .font(.system(size: 34, weight: .regular))
        .scaleEffect(1 - 0.14 * press, anchor: .topLeading)
        .accessibilityHidden(true)
    }
}
