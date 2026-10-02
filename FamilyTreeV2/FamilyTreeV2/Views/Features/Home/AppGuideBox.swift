import SwiftUI

// MARK: - «دليل الاستخدام» (كان «التعليمات») — من علامة المعلومات في الرئيسية (طلب المالك ٢٠٢٦-٠٩-٢٧)
//
// فصول (طلب المالك: «أضيف دليل الاستخدام للواجهات الأخرى»): الشجرة، الرئيسية، الديوانيات،
// حسابي، الإشعارات — ترحيب بقائمة الفصول ← نقاط الفصل ← «أنهيت الفصل» ← الفصل التالي،
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
    @State private var page = 0
    @State private var section: InfoSection = .about
    /// الفصل المفتوح — nil = صفحة الترحيب وقائمة الفصول
    @State private var chapterIndex: Int? = nil

    enum InfoSection: Hashable { case guide, about }

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
                              : L10n.t("تطبيق عائلة المحمدعلي", "Al-Mohammad Ali Family App"),
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
                .frame(height: 346)
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
            Button {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) { chapterIndex = nil }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: L10n.isArabic ? "chevron.right" : "chevron.left")
                        .font(.system(size: 11.5, weight: .bold))
                    Text(L10n.t("كل الفصول", "All chapters"))
                        .font(DS.Font.plex(12.5, weight: .bold))
                }
                .foregroundColor(DS.Color.actionNavy.dsReadableGlyph)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(DS.Color.actionNavy.dsReadableGlyph.opacity(0.10)))
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSScaleButtonStyle())

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Image(systemName: chapter.icon)
                    .font(.system(size: 12, weight: .bold))
                    .accessibilityHidden(true)
                Text(chapter.title)
                    .font(DS.Font.plex(12.5, weight: .bold))
            }
            .foregroundColor(chapter.tint.dsReadableGlyph)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(chapter.tint.dsReadableGlyph.opacity(0.12)))
        }
    }

    @ViewBuilder
    private func slideView(_ slide: Slide, isCurrent: Bool) -> some View {
        switch slide {
        case .step(let i):
            GuidePageView(page: pages[i], number: i + 1, total: pages.count,
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

    private var aboutContent: some View {
        VStack(spacing: DS.Spacing.md) {
            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(L10n.t("تطبيق عائلة المحمدعلي", "Al-Mohammad Ali Family App"))
                    .font(DS.Font.plex(17, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("الإصدار \(appVersion)", "Version \(appVersion)"))
                    .font(DS.Font.plex(13, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
            }

            VStack(spacing: 3) {
                Text("عمل هذا التطبيق")
                    .font(DS.Font.plex(11, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
                Text("حسن الصايغ")
                    .font(DS.Font.plex(16, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text("Made by Hasan Al-Sayegh")
                    .font(DS.Font.plex(13, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .padding(.vertical, DS.Spacing.sm)
            .padding(.horizontal, DS.Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.background))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.textTertiary.opacity(0.15), lineWidth: 1))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.sm)
        .accessibilityElement(children: .combine)
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
                                   at: CGPoint(x: 0.5, y: 0.7095), aspect: treeAspect)),
            GuidePage(title: L10n.t("اضغط على الاسم", "Tap the name"),
                      text: L10n.t("تنفتح تفاصيل العضو: معلوماته وعائلته وصلة القرابة.",
                                   "The member's details open: info, family and kinship."),
                      visual: .tap(before: "GuideNameBefore", after: "GuideNameAfter",
                                   at: CGPoint(x: 0.5, y: 0.4854), aspect: nameAspect)),
            GuidePage(title: L10n.t("الرقم فوق الصورة", "The number on the photo"),
                      text: L10n.t("عدد أبناء العضو — والسهم يعني إنك تقدر تفتحهم.",
                                   "How many children the member has — the arrow means you can open them."),
                      visual: .spot(image: "GuideTreeBefore", at: CGPoint(x: 0.4378, y: 0.634),
                                    radius: 0.075, aspect: treeAspect)),
            GuidePage(title: L10n.t("أنت هنا", "You are here"),
                      text: L10n.t("الإطار الأخضر وعلامة «أنت هنا» تبيّن مكانك في الشجرة.",
                                   "The green ring and «You» mark show your place in the tree."),
                      visual: .spot(image: "GuideTreeAfter", at: CGPoint(x: 0.5, y: 0.755),
                                    radius: 0.14, aspect: treeAspect)),
            GuidePage(title: L10n.t("المتوفّى", "Deceased"),
                      text: L10n.t("صورته رمادية، وتحت اسمه شريط أحمر فيه سنة الوفاة ثم الميلاد.",
                                   "Their photo is grey, with a red strip under the name showing the death then birth year."),
                      visual: .spot(image: "GuideTreeBefore", at: CGPoint(x: 0.5, y: 0.355),
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

    static var all: [GuideChapter] {
        [
            GuideChapter(id: "tree", title: L10n.t("الشجرة", "Tree"), icon: "tree.fill",
                         tint: DS.Color.composerProject, pages: GuidePage.tree),
            GuideChapter(id: "home", title: L10n.t("الرئيسية", "Home"), icon: "house.fill",
                         tint: DS.Color.actionNavy, pages: GuidePage.home),
            GuideChapter(id: "diwaniyas", title: L10n.t("الديوانيات", "Diwaniyas"), icon: "map.fill",
                         tint: DS.Color.composerDiwaniya, pages: GuidePage.diwaniyas),
            GuideChapter(id: "profile", title: L10n.t("حسابي", "My Account"), icon: "person.crop.circle.fill",
                         tint: DS.Color.actionNavy, pages: GuidePage.profile),
            GuideChapter(id: "notifications", title: L10n.t("الإشعارات", "Notifications"), icon: "bell.badge.fill",
                         tint: DS.Color.composerDiwaniya, pages: GuidePage.notifications)
        ]
    }
}

extension GuidePage {
    fileprivate static var home: [GuidePage] {
        [
            GuidePage(title: L10n.t("الجرس", "The bell"),
                      text: L10n.t("إشعاراتك هنا: الردود والموافقات وأخبار العائلة — والنقطة الحمراء تعني جديد.",
                                   "Your notifications: replies, approvals and family news — a red dot means new."),
                      visual: .spot(image: "GuideHomeTop", at: CGPoint(x: 0.172, y: 0.148),
                                    radius: 0.07, aspect: shotAspect)),
            GuidePage(title: L10n.t("علامة المعلومات", "The info mark"),
                      text: L10n.t("تفتح «عن التطبيق» و«دليل الاستخدام» — هذا الدليل.",
                                   "Opens «About» and the «User Guide» — this guide."),
                      visual: .spot(image: "GuideHomeTop", at: CGPoint(x: 0.082, y: 0.148),
                                    radius: 0.07, aspect: shotAspect)),
            GuidePage(title: L10n.t("أقسام التطبيق", "App sections"),
                      text: L10n.t("كل بلاطة تفتح قسماً: الشجرة، الديوانيات، المكتبة، المشاريع، والتواصل.",
                                   "Each tile opens a section: tree, diwaniyas, library, projects and contact."),
                      visual: .rect(image: "GuideHomeTiles", rect: CGRect(x: 0.03, y: 0.02, width: 0.94, height: 0.595),
                                    aspect: shotAspect)),
            GuidePage(title: L10n.t("الأخبار والمناسبات", "News & occasions"),
                      text: L10n.t("اضغط لتفتح كل الأخبار، وتفاعل بالإعجاب والتعليق، وأضف خبرك من زر الإضافة.",
                                   "Tap to open all news, like and comment, and add your own from the add button."),
                      visual: .rect(image: "GuideHomeNews", rect: CGRect(x: 0.04, y: 0.028, width: 0.92, height: 0.816),
                                    aspect: shotAspect))
        ]
    }

    fileprivate static var diwaniyas: [GuidePage] {
        [
            GuidePage(title: L10n.t("الفلتر", "Filter"),
                      text: L10n.t("اختر: الكل أو الديوانيات أو الحسينيات — والرقم عددها.",
                                   "Choose all, diwaniyas or husseiniyas — the number is how many."),
                      visual: .rect(image: "GuideDiwTop", rect: CGRect(x: 0.045, y: 0.05, width: 0.915, height: 0.098),
                                    aspect: shotAspect)),
            GuidePage(title: L10n.t("اتصال", "Call"),
                      text: L10n.t("اتصل بصاحب الديوانية مباشرة — وفوقه موعدها وموقعها.",
                                   "Call the host directly — the time and place are right above."),
                      visual: .spot(image: "GuideDiwTop", at: CGPoint(x: 0.828, y: 0.581),
                                    radius: 0.1, aspect: shotAspect)),
            GuidePage(title: L10n.t("زر الخيارات", "Options"),
                      text: L10n.t("للإبلاغ عن ديوانية — ولصاحبها التعديل والحذف.",
                                   "Report a diwaniya — its host can also edit or delete it."),
                      visual: .spot(image: "GuideDiwTop", at: CGPoint(x: 0.127, y: 0.307),
                                    radius: 0.075, aspect: shotAspect)),
            GuidePage(title: L10n.t("أضف ديوانيتك", "Add yours"),
                      text: L10n.t("أضف ديوانيتك أو حسينيتك، وتظهر للجميع بعد موافقة الإدارة.",
                                   "Add your diwaniya or husseiniya; everyone sees it after admin approval."),
                      visual: .spot(image: "GuideDiwAdd", at: CGPoint(x: 0.119, y: 0.785),
                                    radius: 0.09, aspect: shotAspect))
        ]
    }

    fileprivate static var profile: [GuidePage] {
        [
            GuidePage(title: L10n.t("تعديل بياناتك", "Edit your info"),
                      text: L10n.t("اضغط القلم لتعديل صورتك وبياناتك — أول ٣ تعديلات مباشرة، وبعدها بموافقة الإدارة.",
                                   "Tap the pencil to edit your photo and info — the first 3 changes apply directly, then admin approval."),
                      visual: .spot(image: "GuideProfileTop", at: CGPoint(x: 0.169, y: 0.707),
                                    radius: 0.07, aspect: shotAspect)),
            GuidePage(title: L10n.t("رمز QR", "QR code"),
                      text: L10n.t("يعرض رمزك لتشاركه مع قريبك.",
                                   "Shows your code to share with a relative."),
                      visual: .spot(image: "GuideProfileInfo", at: CGPoint(x: 0.159, y: 0.299),
                                    radius: 0.09, aspect: shotAspect)),
            GuidePage(title: L10n.t("مسح", "Scan"),
                      text: L10n.t("امسح رمز قريبك لتعرف صلة القرابة بينكم.",
                                   "Scan a relative's code to see how you're related."),
                      visual: .spot(image: "GuideProfileInfo", at: CGPoint(x: 0.336, y: 0.299),
                                    radius: 0.08, aspect: shotAspect)),
            GuidePage(title: L10n.t("عائلتي", "My family"),
                      text: L10n.t("أضف أبناءك وزوجتك واختر الأم من هنا.",
                                   "Add your children and wife, and choose the mother here."),
                      visual: .rect(image: "GuideProfileFamily", rect: CGRect(x: 0.045, y: 0.321, width: 0.915, height: 0.503),
                                    aspect: shotAspect)),
            GuidePage(title: L10n.t("الإعدادات", "Settings"),
                      text: L10n.t("المظهر واللغة والإشعارات والخصوصية والأجهزة.",
                                   "Appearance, language, notifications, privacy and devices."),
                      visual: .spot(image: "GuideProfileTop", at: CGPoint(x: 0.092, y: 0.103),
                                    radius: 0.07, aspect: shotAspect))
        ]
    }

    fileprivate static var notifications: [GuidePage] {
        [
            GuidePage(title: L10n.t("الإشعارات | المستجدات", "Notifications | Updates"),
                      text: L10n.t("«الإشعارات» ما يخصّك، و«المستجدات» أخبار التطبيق — والرقم الأحمر يعني جديد.",
                                   "«Notifications» are yours, «Updates» are app news — a red number means new."),
                      visual: .rect(image: "GuideNotifs", rect: CGRect(x: 0.04, y: 0.034, width: 0.92, height: 0.134),
                                    aspect: shotAspect)),
            GuidePage(title: L10n.t("قراءة الكل وتحديد", "Read all & select"),
                      text: L10n.t("علّم الكل مقروءاً، أو حدّد إشعارات بعينها.",
                                   "Mark everything as read, or select specific notifications."),
                      visual: .rect(image: "GuideNotifs", rect: CGRect(x: 0.04, y: 0.201, width: 0.92, height: 0.112),
                                    aspect: shotAspect)),
            GuidePage(title: L10n.t("اضغط الإشعار", "Tap a notification"),
                      text: L10n.t("يفتح تفاصيله — واسحبه لحذفه أو تعليمه مقروءاً.",
                                   "Opens its details — swipe it to delete or mark as read."),
                      visual: .rect(image: "GuideNotifs", rect: CGRect(x: 0.04, y: 0.492, width: 0.92, height: 0.251),
                                    aspect: shotAspect))
        ]
    }
}

// MARK: - صفحة نقطة واحدة

private struct GuidePageView: View {
    let page: GuidePage
    let number: Int
    let total: Int
    let isCurrent: Bool
    let reduceMotion: Bool
    @State private var start = Date()
    /// دخول مرتّب كلما وصلت للنقطة: الرقم ← العنوان ← اللقطة ← الشرح
    @State private var shown = false

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            // الرقم + العنوان
            HStack(spacing: DS.Spacing.sm) {
                Text("\(number)")
                    .font(DS.Font.plex(15, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DSActionFill.style()))
                    .scaleEffect(shown ? 1 : 0.4)
                    .rotationEffect(.degrees(shown ? 0 : -25))
                    .accessibilityHidden(true)
                Text(page.title)
                    .font(DS.Font.plex(18, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .offset(x: shown ? 0 : (L10n.isArabic ? -14 : 14))
                    .opacity(shown ? 1 : 0)
                Spacer(minLength: 0)
                Text(L10n.t("\(number) من \(total)", "\(number) of \(total)"))
                    .font(DS.Font.plex(11.5, weight: .semibold))
                    .foregroundColor(DS.Color.textTertiary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            visual
                .frame(maxWidth: .infinity)
                .frame(height: 258)
                .scaleEffect(shown ? 1 : 0.94)
                .opacity(shown ? 1 : 0)

            Text(page.text)
                .dsFieldFont(14, weight: .semibold)
                .foregroundColor(DS.Color.fieldValue)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .offset(y: shown ? 0 : 8)
                .opacity(shown ? 1 : 0)
        }
        .padding(.horizontal, 2)
        .frame(maxHeight: .infinity, alignment: .top)
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
                        .font(.system(size: 15, weight: .bold))
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
            .frame(height: 118)
            .scaleEffect(shown ? 1 : 0.85)
            .opacity(shown ? 1 : 0)
            .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(L10n.t("أهلاً بك في دليل الاستخدام", "Welcome to the User Guide"))
                    .font(DS.Font.plex(19, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                Text(L10n.t("اختر الواجهة التي تريد التعرّف عليها", "Choose the screen you want to learn"))
                    .dsFieldFont(13.5)
                    .foregroundColor(DS.Color.fieldValue)
            }
            .multilineTextAlignment(.center)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .accessibilityElement(children: .combine)

            // الفصول بعمودين (صفوف عادية لا شبكة كسولة — حتى يُقاس ارتفاع المربّع صح)
            VStack(spacing: 6) {
                ForEach(Array(stride(from: 0, to: chapters.count, by: 2)), id: \.self) { start in
                    HStack(spacing: 6) {
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
                Image(systemName: chapter.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(chapter.tint.dsReadableGlyph)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(chapter.tint.dsReadableGlyph.opacity(0.13)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(chapter.title)
                        .dsFieldFont(14.5, weight: .bold)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(L10n.t("\(chapter.pages.count) نقاط", "\(chapter.pages.count) points"))
                        .dsFieldFont(12)
                        .foregroundColor(DS.Color.fieldValue)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.textTertiary.opacity(0.15), lineWidth: 1))
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

    private let confetti: [Color] = [DS.Color.primary, DS.Color.success, DS.Color.accent,
                                     DS.Color.composerLibrary, DS.Color.female, DS.Color.composerDiwaniya]

    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                if !reduceMotion {
                    ForEach(0..<12, id: \.self) { i in
                        let a = Double(i) / 12 * 2 * .pi
                        Circle()
                            .fill(confetti[i % confetti.count])
                            .frame(width: i.isMultiple(of: 2) ? 9 : 6, height: i.isMultiple(of: 2) ? 9 : 6)
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
            .frame(height: 190)
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(nextTitle == nil ? L10n.t("جاهز!", "All set!")
                                      : L10n.t("أنهيت فصل «\(chapterTitle)»", "«\(chapterTitle)» done"))
                    .font(DS.Font.plex(22, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                Text(nextTitle.map { L10n.t("التالي: «\($0)» — أو اختر من «كل الفصول»",
                                            "Next: «\($0)» — or pick from «All chapters»") }
                     ?? L10n.t("صرت تعرف أساسيات التطبيق — استمتع به",
                               "You know the app basics now — enjoy it"))
                    .dsFieldFont(14)
                    .foregroundColor(DS.Color.fieldValue)
                    .multilineTextAlignment(.center)
            }
            .offset(y: shown ? 0 : 10)
            .opacity(shown ? 1 : 0)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, DS.Spacing.md)
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
                    VStack(spacing: 5) {
                        look(item.look)
                            .frame(height: 40)
                        Text(item.title)
                            .dsFieldFont(13, weight: .bold)
                            .foregroundColor(DS.Color.fieldLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(item.detail)
                            .dsFieldFont(11.5)
                            .foregroundColor(DS.Color.fieldValue)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, DS.Spacing.sm)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .top)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.background))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(DS.Color.textTertiary.opacity(0.15), lineWidth: 1))
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
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(DS.Color.primary)
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

/// لقطة بإطار مدوّر وطبقة رسم فوقها بنفس مقاسها (الإحداثيات من اليسار دائماً)
private struct GuideShot<Content: View, Overlay: View>: View {
    let aspect: CGFloat
    @ViewBuilder let content: () -> Content
    @ViewBuilder let overlay: (CGSize) -> Overlay

    var body: some View {
        content()
            .aspectRatio(aspect, contentMode: .fit)
            .overlay { GeometryReader { g in overlay(g.size) } }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.textTertiary.opacity(0.22), lineWidth: 1))
            .environment(\.layoutDirection, .leftToRight)
    }
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
