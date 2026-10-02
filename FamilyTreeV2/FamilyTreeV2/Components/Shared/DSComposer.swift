import SwiftUI
import PhotosUI

// MARK: - مربّعات الإضافة (طلب المالك ٢٠٢٦-٠٩-٢٦)
//
// لغة تصميم واحدة لمربّعات «إضافة» — خبر، مشروع، مكتبة، ديوانية/حسينية:
//   • رأس متدرّج بلون القسم: أيقونة في دائرة زجاجية + علامة مائية كبيرة + لمعة
//     تمرّ مرة عند الفتح. اللون يتبدّل بحركة ناعمة (مثلاً مع نوع الخبر).
//   • أقسام تدخل تباعاً (تلاشٍ + صعود خفيف) بدل ظهور الكل دفعة واحدة.
//   • شريط أزرار سفلي ثابت: الإجراء كحلي يمين، «إلغاء» رمادي يسار (قاعدة التطبيق).
//   • «مربّع إضافي» للأشياء الاختيارية (تصويت، حسابات، وقت…) يطلع فوق المربّع،
//     ويتقلّص المربّع الأساسي خلفه قليلاً، ثم يظهر ملخّص ما أُضيف بشارة.

// MARK: - ألوان الأقسام

extension DS.Color {
    // الداكن أفتح قليلاً حتى تُقرأ الأيقونات والنصوص الملوّنة على الخلفية الداكنة
    static let composerProject    = SwiftUI.Color.adaptive(light: "#2E6B5E", dark: "#3F8F7D")
    static let composerLibrary    = SwiftUI.Color.adaptive(light: "#8A6A2F", dark: "#B48D4A")
    static let composerDiwaniya   = SwiftUI.Color.adaptive(light: "#1F5C7A", dark: "#3E8DB5")
    static let composerHusseiniya = SwiftUI.Color.adaptive(light: "#1E4D3A", dark: "#3F8A66")
}

// MARK: - قياس الارتفاع

private struct DSHeightReader: ViewModifier {
    @Binding var height: CGFloat
    func body(content: Content) -> some View {
        content.background(GeometryReader { geo in
            Color.clear
                .onAppear { height = geo.size.height }
                .onChange(of: geo.size.height) { height = $0 }
        })
    }
}

extension View {
    func readHeight(_ h: Binding<CGFloat>) -> some View { modifier(DSHeightReader(height: h)) }
}

// MARK: - إيقاع الحركة — تسلسل واحد لكل المربّعات (طلب المالك ٢٠٢٦-٠٩-٢٧)
//
// «حركات مرتّبة وإبداع في كل مربّع» — إيقاع واحد هادئ في كل مكان:
//   ١) المربّع يكبر من ٠٫٩٤ مع تلاشٍ (بعد قياس ارتفاعه — فلا يتغيّر حجمه وهو يظهر).
//   ٢) الرأس: الدائرة الزجاجية تقفز بنابض لطيف ودوران صغير يستقر، ثم العنوان ثم الوصف
//      ينسابان من جهة الأيقونة، والعلامة المائية تظهر وتطفو، ولمعة تمرّ مرة واحدة.
//   ٣) الأقسام تتوالى بعد الرأس (٥٥ ملّي ثانية بينها): صعود ١٢ نقطة وتكبير طفيف،
//      وأيقونة كل قسم تتفتّح بعد بطاقتها بقليل.
//   ٤) الأزرار آخراً: صعود خفيف مع تلاشٍ؛ والكحلي يلمع مرة واحدة حين يصير ممكناً.
// «تقليل الحركة» (توصية أبل): لا تكبير ولا انزلاق ولا دوران — تلاشٍ قصير فقط أو ظهور مباشر.
// كل حركات الدخول إزاحة/شفافية/تكبير عند الرسم فقط — لا تغيّر مقاسات التخطيط،
// فيبقى قياس ارتفاع المربّع (SheetContentHeightKey) صحيحاً من أول فتح.

enum DSMotion {
    // ١) المربّع
    static let panelScale: CGFloat = 0.94
    /// نفس نابض الفتح المعتمد للمربّعات
    static let panel = DS.Anim.snappy

    // ٢) الرأس
    static let iconDelay = 0.06
    static let iconFromScale: CGFloat = 0.55
    static let iconFromAngle: Double = -14
    static let iconPop = Animation.spring(response: 0.5, dampingFraction: 0.6)
    static let titleDelay = 0.13
    static let subtitleDelay = 0.19
    /// إزاحة العنوان والوصف (نحو جهة الأيقونة — تنعكس تلقائياً مع العربية)
    static let textShift: CGFloat = 10
    static let text = Animation.spring(response: 0.42, dampingFraction: 0.88)
    static let watermarkDelay = 0.1
    static let shineDelay = 0.34

    // ٣) الأقسام
    /// أول قسم داخل المربّع يدخل بعد الرأس، وفي الصفحات (بلا رأس) مبكراً
    static let sectionsAfterHeader = 0.22
    static let sectionsOnPage = 0.08
    static let step = 0.055
    /// سقف للتأخير — عنصر رقمه كبير (صف في قائمة) لا ينتظر طويلاً
    static let maxSteps = 8
    static let rise: CGFloat = 12
    static let riseScale: CGFloat = 0.98
    static let section = Animation.spring(response: 0.46, dampingFraction: 0.84)

    // ٤) الأزرار
    static let footerRise: CGFloat = 7
    static let footer = Animation.spring(response: 0.42, dampingFraction: 0.86)

    // التفاعل
    static let press = Animation.spring(response: 0.26, dampingFraction: 0.72)
    static let expand = Animation.spring(response: 0.38, dampingFraction: 0.86)
    static let enable = Animation.easeInOut(duration: 0.25)
    /// «تقليل الحركة»: تلاشٍ قصير بدل أي حركة
    static let fade = Animation.easeOut(duration: 0.2)

    /// تأخير عنصر في التسلسل
    static func staggerDelay(_ index: Int, base: Double) -> Double {
        base + Double(min(max(index, 0), maxSteps)) * step
    }

    /// الأزرار بعد آخر قسم (حتى ثلاثة — لا تتأخّر أكثر في المربّعات الطويلة)
    static func footerDelay(lastSection: Int) -> Double {
        sectionsAfterHeader + Double(min(max(lastSection + 1, 1), 3)) * step + 0.03
    }
}

private struct DSStaggerBaseKey: EnvironmentKey {
    /// = DSMotion.sectionsOnPage (الصفحات بلا رأس)
    static let defaultValue: Double = 0.08
}

extension EnvironmentValues {
    /// متى يبدأ أول قسم بالدخول: بعد الرأس داخل المربّعات، ومبكراً في الصفحات
    var dsStaggerBase: Double {
        get { self[DSStaggerBaseKey.self] }
        set { self[DSStaggerBaseKey.self] = newValue }
    }
}

/// أعلى رقم قسم داخل المربّع — ليدخل شريط الأزرار بعد آخر قسم
struct DSStaggerIndexKey: PreferenceKey {
    static let defaultValue = -1
    static func reduce(value: inout Int, nextValue: () -> Int) { value = max(value, nextValue()) }
}

/// دخول عنصر في تسلسل المربّع: تلاشٍ + إزاحة صغيرة (+ تكبير طفيف) بعد تأخير.
/// `x` بإشارة اتجاه الواجهة (موجب = نحو النهاية)، فتنعكس الحركة تلقائياً مع العربية.
struct DSEntrance: ViewModifier {
    var delay: Double
    var x: CGFloat = 0
    var y: CGFloat = 0
    var scale: CGFloat = 1
    var animation: Animation = DSMotion.section
    /// false = بلا حركة خاصة (العنصر يظهر مع حاويته)
    var active: Bool = true
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let settled = shown || reduceMotion || !active
        return content
            .opacity(shown || !active ? 1 : 0)
            .offset(x: settled ? 0 : x, y: settled ? 0 : y)
            .scaleEffect(settled ? 1 : scale, anchor: .top)
            .onAppear {
                guard active, !shown else { return }
                // «تقليل الحركة»: تلاشٍ قصير فقط
                withAnimation(reduceMotion ? DSMotion.fade : animation.delay(delay)) { shown = true }
            }
    }
}

extension View {
    func dsEntrance(delay: Double, x: CGFloat = 0, y: CGFloat = 0, scale: CGFloat = 1,
                    animation: Animation = DSMotion.section, active: Bool = true) -> some View {
        modifier(DSEntrance(delay: delay, x: x, y: y, scale: scale, animation: animation, active: active))
    }
}

/// قفزة أيقونة: تكبير بنابض لطيف مع دوران صغير يستقر (أيقونة الرأس، المربّع الإضافي، الأقسام).
/// «تقليل الحركة»: تلاشٍ فقط.
struct DSIconPop: ViewModifier {
    var delay: Double = DSMotion.iconDelay
    var fromScale: CGFloat = DSMotion.iconFromScale
    var fromAngle: Double = DSMotion.iconFromAngle
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let settled = shown || reduceMotion
        return content
            .scaleEffect(settled ? 1 : fromScale)
            .rotationEffect(.degrees(settled ? 0 : fromAngle))
            .opacity(shown ? 1 : 0)
            .onAppear {
                guard !shown else { return }
                withAnimation(reduceMotion ? DSMotion.fade : DSMotion.iconPop.delay(delay)) { shown = true }
            }
    }
}

/// ضغطة ناعمة موحّدة لأزرار المربّعات (الإجراء الكحلي، «إلغاء»، الشارات):
/// تصغير ٠٫٩٧ مع خفوت بسيط — ومع «تقليل الحركة» خفوت فقط
struct DSPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DSPressLabel(configuration: configuration)
    }
}

private struct DSPressLabel: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(DSMotion.press, value: configuration.isPressed)
    }
}

/// «جاهز»: حين يصير زر الإجراء الكحلي ممكناً — نبضة واحدة ولمعة تعبره مرة (بلا تكرار).
/// «تقليل الحركة»: إضاءة خفيفة تتلاشى بدل النبضة واللمعة.
struct DSReadyGlow: ViewModifier {
    let isReady: Bool
    /// false أثناء دخول المربّع (مثل تعبئة الحقول عند الفتح) — لا وميض وقتها
    var armed: Bool = true
    var cornerRadius: CGFloat = DS.Radius.lg
    @State private var pop = false
    @State private var sweep: CGFloat = 0
    @State private var flash = false
    /// آخر وميض — الصلاحية قد تتبدّل مع كل حرف (حذف ثم كتابة)، فلا نكرّره خلال ثانيتين
    @State private var lastFired = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .overlay {
                // اللمعة تبدأ وتنتهي خارج الزر (مقصوصة) — لا تُرى إلا وهي تعبره
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, DS.Color.textOnPrimary.opacity(0.34), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 64)
                        .rotationEffect(.degrees(18))
                        .offset(x: -80 + sweep * (geo.size.width + 160))
                }
                .clipShape(shape)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .overlay {
                shape.fill(DS.Color.textOnPrimary.opacity(flash ? 0.18 : 0))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .scaleEffect(pop ? 1.03 : 1)
            .onChange(of: isReady) { ready in
                guard ready, armed else { return }
                fire()
            }
    }

    private func fire() {
        guard Date().timeIntervalSince(lastFired) > 2 else { return }
        lastFired = Date()
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.14)) { flash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeInOut(duration: 0.4)) { flash = false }
            }
            return
        }
        guard sweep == 0 else { return }   // لمعة جارية — لا نكرّر
        withAnimation(.spring(response: 0.24, dampingFraction: 0.5)) { pop = true }
        withAnimation(.easeInOut(duration: 0.7)) { sweep = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) { pop = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            // ترجع خارج الزر بلا حركة — جاهزة للمرة القادمة
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { sweep = 0 }
        }
    }
}

// MARK: - المربّع نفسه

/// هيكل مربّع الإضافة: رأس + محتوى يتمرّر عند الحاجة + شريط أزرار. يبلّغ
/// `DSCenterPanel(hugsContent:)` بارتفاعه فيبقى المربّع على قدر محتواه.
struct DSComposer<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    var actionTitle: String
    var actionIcon: String = "checkmark"
    /// false = مربّع اختيار بلا زر إجراء — «إلغاء» وحده بعرض الشريط
    var showsAction: Bool = true
    /// نص الزر الرمادي — «إغلاق» لمربّعات العرض فقط (تفاصيل، قوائم)
    var cancelTitle: String = L10n.t("إلغاء", "Cancel")
    var canSubmit: Bool
    var isBusy: Bool = false
    /// ملاحظة صغيرة فوق الأزرار (مثل «يحتاج موافقة الإدارة»)
    var note: String? = nil
    /// تقدّم الرفع (٠…١) — يظهر شريطاً فوق الأزرار
    var progress: Double? = nil
    /// مربّع إضافي مفتوح فوقه → يتقلّص خلفه قليلاً
    var isBehindExtra: Bool = false
    /// هامش المحتوى الجانبي — ٠ لبطاقات تحمل هامشها بنفسها (تعديل البيانات)
    var contentPadding: CGFloat = DS.Spacing.lg
    /// تغييرات لم تُحفظ — «إلغاء» يسأل قبل التجاهل، ولا يُسحب المربّع الطويل (توصية أبل)
    var hasUnsavedChanges: Bool = false
    let onSubmit: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var headerH: CGFloat = 0
    @State private var contentH: CGFloat = 0
    @State private var footerH: CGFloat = 0
    @State private var confirmDiscard = false
    /// دخول الأزرار (آخر التسلسل) ورقم آخر قسم — ليأتي الشريط بعده
    @State private var footerIn = false
    @State private var lastSection = -1
    /// لحظة الفتح — لمعة «جاهز» لا تظهر أثناء دخول المربّع (مثل تعبئة الحقول عند الفتح)
    @State private var openedAt = Date()
    /// «تقليل الحركة» من إعدادات الجهاز (توصية أبل): بلا تصغير ولا نبض
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            DSComposerHeader(title: title, subtitle: subtitle, icon: icon, tint: tint)
                .readHeight($headerH)

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) { content() }
                    .environment(\.dsBoxTint, tint)      // تنسيق الألوان: ما بداخل المربّع بلونه
                    .environment(\.dsInCenterBox, true) // حقول المربّعات أصغر قليلاً (طلب المالك)
                    .padding(.horizontal, contentPadding)
                    .padding(.top, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.sm)
                    .readHeight($contentH)
            }
            .scrollDismissesKeyboard(.interactively)
            // الأقسام تبدأ بعد الرأس: رأس ← قسم ١ ← قسم ٢ … تسلسل واحد
            .environment(\.dsStaggerBase, DSMotion.sectionsAfterHeader)
            .onPreferenceChange(DSStaggerIndexKey.self) { lastSection = $0 }

            footer.readHeight($footerH)
        }
        .background(DS.Color.background)
        // يُبلَّغ الارتفاع بعد قياس الرأس والشريط معاً — تحديثان في نفس الإطار كان
        // المربّع يلتقط أولهما (الناقص) فيُقصّ آخر المحتوى
        // المربّع الطويل من الأسفل لا يُسحب وفيه كلام غير محفوظ
        .interactiveDismissDisabled(hasUnsavedChanges)
        .dsAlert(L10n.t("تجاهل التغييرات؟", "Discard changes?"), isPresented: $confirmDiscard) {
            Button(L10n.t("متابعة التعديل", "Keep editing"), role: .cancel) {}
            Button(L10n.t("تجاهل", "Discard"), role: .destructive) { onCancel() }
        } message: {
            Text(L10n.t("ما كتبته لم يُحفظ بعد، وسيضيع إذا خرجت.",
                        "What you entered isn't saved yet and will be lost."))
        }
        .preference(key: SheetContentHeightKey.self,
                    value: headerH > 0 && footerH > 0 ? headerH + contentH + footerH : 0)
        .scaleEffect(isBehindExtra && !reduceMotion ? 0.94 : 1)
        .blur(radius: isBehindExtra ? 1.2 : 0)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: isBehindExtra)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private var actionEnabled: Bool { canSubmit && !isBusy }
    /// انتهى دخول المربّع — بعده فقط تلمع «جاهز»
    private var entranceSettled: Bool { Date().timeIntervalSince(openedAt) > 0.8 }

    private var footer: some View {
        VStack(spacing: DS.Spacing.sm) {
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .transition(.opacity)
            }
            if let note {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle.fill").font(.system(size: 10.5, weight: .semibold))
                    Text(note).font(DS.Font.plex(11))
                }
                .foregroundColor(DS.Color.textTertiary)
            }
            HStack(spacing: DS.Spacing.sm) {
                if showsAction { actionButton }
                cancelButton
            }
            .buttonStyle(DSPressStyle())
        }
        // الأزرار آخر التسلسل: تصعد قليلاً مع تلاشٍ (والشريط نفسه ثابت)
        .opacity(footerIn ? 1 : 0)
        .offset(y: footerIn || reduceMotion ? 0 : DSMotion.footerRise)
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.md)
        .background(
            DS.Color.background
                .overlay(alignment: .top) {
                    Rectangle().fill(DS.Color.textTertiary.opacity(0.12)).frame(height: 1)
                }
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: progress != nil)
        .onAppear(perform: enterFooter)
    }

    /// الإجراء الكحلي — المعطّل ↔ الممكن يتحرّك بهدوء، و«جاهز» تلمع مرة (DSReadyGlow)
    private var actionButton: some View {
        Button(action: onSubmit) {
            HStack(spacing: 7) {
                if isBusy {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Image(systemName: actionIcon).font(.system(size: 14, weight: .bold))
                        .opacity(actionEnabled ? 1 : DSActionFill.labelDisabledOpacity)
                }
                Text(actionTitle).font(DS.Font.plex(15, weight: .bold))
                    .opacity(actionEnabled ? 1 : DSActionFill.labelDisabledOpacity)
            }
            .foregroundColor(DSActionFill.label())
            .frame(maxWidth: .infinity).frame(height: 48)
            // نفس DSActionFill.style(enabled:) — لكن الشفافية على الطبقة فتتحرّك بسلاسة
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(DSActionFill.style())
                    .opacity(actionEnabled ? 1 : DSActionFill.disabledOpacity)
            )
            .animation(DSMotion.enable, value: actionEnabled)
            .modifier(DSReadyGlow(isReady: canSubmit, armed: entranceSettled, cornerRadius: DS.Radius.lg))
        }
        .disabled(!canSubmit || isBusy)
    }

    private var cancelButton: some View {
        Button {
            if hasUnsavedChanges { confirmDiscard = true } else { onCancel() }
        } label: {
            Text(cancelTitle)
                .font(DS.Font.plex(15, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(DS.Color.mutedBackground.opacity(0.8)))
        }
        .disabled(isBusy)
    }

    private func enterFooter() {
        guard !footerIn else { return }
        guard !reduceMotion else {
            withAnimation(DSMotion.fade) { footerIn = true }
            return
        }
        // بعد أول تخطيط يصل رقم آخر قسم (تفضيل) — فتدخل الأزرار بعده
        DispatchQueue.main.async {
            withAnimation(DSMotion.footer.delay(DSMotion.footerDelay(lastSection: lastSection))) {
                footerIn = true
            }
        }
    }
}

// MARK: - الرأس

struct DSComposerHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    /// العلامة المائية تظهر بهدوء ثم تطفو، واللمعة تمرّ مرة
    @State private var markIn = false
    @State private var shine = false
    @State private var drift = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(colors: [tint, tint.opacity(0.72)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // الداكن: ألوان الأنواع فاتحة فيه — طبقة تعتيم تحفظ وضوح النص الأبيض
            if colorScheme == .dark { Color.black.opacity(0.3) }

            // هالة ناعمة + علامة مائية كبيرة في الطرف الآخر
            halo
            watermark
            shineBand

            // التسلسل: الأيقونة تقفز ← العنوان ← الوصف (DSMotion)
            HStack(spacing: DS.Spacing.md) {
                iconBadge
                titles
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
        .frame(height: 86)
        .clipped()
        // القارئ الصوتي: الرأس يُقرأ عنواناً واحداً (العنوان ثم الوصف)، والزخارف تُتجاهل
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle.isEmpty ? title : "\(title)، \(subtitle)")
        .accessibilityAddTraits(.isHeader)
        .animation(.easeInOut(duration: 0.35), value: tint)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: icon)
        .onAppear {
            // تقليل الحركة: العلامة ظاهرة مباشرة بلا طفو ولا لمعة
            guard !reduceMotion else { markIn = true; return }
            withAnimation(.easeOut(duration: 0.7).delay(DSMotion.watermarkDelay)) { markIn = true }
            withAnimation(.easeInOut(duration: 1.1).delay(DSMotion.shineDelay)) { shine = true }
            // الحركة المتكرّرة الوحيدة في المربّعات: طفو بطيء للعلامة المائية
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) { drift = true }
        }
    }

    private var halo: some View {
        Circle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 150, height: 150)
            .blur(radius: 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .offset(x: -30, y: -60)
    }

    /// العلامة المائية تطفو ببطء — لمسة حياة خفيفة
    private var watermark: some View {
        Image(systemName: icon)
            .font(.system(size: 96, weight: .bold))
            .foregroundColor(.white.opacity(0.09))
            .rotationEffect(.degrees(drift ? -10 : -16))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .offset(x: 18, y: drift ? 10 : 20)
            .opacity(markIn ? 1 : 0)
            .id("wm-\(icon)")
            .transition(.opacity)
    }

    /// لمعة تمرّ مرة واحدة عند الفتح
    private var shineBand: some View {
        LinearGradient(colors: [.clear, .white.opacity(0.28), .clear],
                       startPoint: .leading, endPoint: .trailing)
            .frame(width: 80)
            .rotationEffect(.degrees(18))
            .offset(x: shine ? 320 : -320)
            .allowsHitTesting(false)
    }

    /// الدائرة الزجاجية: قفزة بنابض لطيف مع دوران صغير يستقر
    private var iconBadge: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.18))
            Circle().strokeBorder(Color.white.opacity(0.38), lineWidth: 1)
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .id(icon)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
        }
        .frame(width: 48, height: 48)
        .modifier(DSIconPop())
    }

    /// العنوان ثم الوصف ينسابان من جهة الأيقونة (٦٠ ملّي ثانية بينهما)
    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.Font.plex(18, weight: .bold))
                .foregroundColor(.white)
                .id("t-\(title)")
                .transition(.opacity)
                .dsEntrance(delay: DSMotion.titleDelay, x: -DSMotion.textShift, animation: DSMotion.text)
            Text(subtitle)
                .font(DS.Font.plex(12))
                .foregroundColor(.white.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .dsEntrance(delay: DSMotion.subtitleDelay, x: -DSMotion.textShift, animation: DSMotion.text)
        }
    }
}

// MARK: - لمعة تمرّ مرة

/// لمعة بيضاء مائلة تعبر الخلفية مرة واحدة عند الظهور — ضعها overlay على رأس متدرّج
struct DSShineSweep: View {
    var delay: Double = 0.3
    @State private var go = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.26), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 90)
                .rotationEffect(.degrees(18))
                .offset(x: go ? geo.size.width + 90 : -180)
        }
        .allowsHitTesting(false)
        .clipped()
        .onAppear {
            guard !reduceMotion else { return }   // بلا لمعة مع «تقليل الحركة»
            withAnimation(.easeInOut(duration: 1.15).delay(delay)) { go = true }
        }
    }
}

// MARK: - دخول الأقسام تباعاً

/// صعود ١٢ نقطة + تكبير طفيف بنابض، بفاصل ٥٥ ملّي ثانية بين الأقسام — داخل المربّع يبدأ
/// بعد الرأس (`dsStaggerBase`). «تقليل الحركة»: تلاشٍ هادئ فقط بدل الصعود والتكبير.
struct DSStaggerIn: ViewModifier {
    let index: Int
    @Environment(\.dsStaggerBase) private var base
    func body(content: Content) -> some View {
        content
            .dsEntrance(delay: DSMotion.staggerDelay(index, base: base),
                        y: DSMotion.rise, scale: DSMotion.riseScale)
            // رقم القسم يصل للمربّع — فيدخل شريط الأزرار بعد آخر قسم
            .preference(key: DSStaggerIndexKey.self, value: index)
    }
}

extension View {
    func dsStaggerIn(_ index: Int) -> some View { modifier(DSStaggerIn(index: index)) }
}

// MARK: - دخول البطاقات في الصفحات — نمط الأخبار والديوانيات (طلب المالك ٢٠٢٦-٠٩-٢٧: «طبّقه على البقية»)
//
// كل بطاقة/صف تصعد ٣٠ نقطة وتظهر، واحدة بعد الأخرى (٠٫٠٦ ث، أول ٧ فقط والباقي مع السابع)،
// مرة واحدة عند ظهور الصفحة — والصفوف التي تُبنى لاحقاً بالتمرير تظهر مباشرة بلا حركة.
// الاستخدام: `@State private var appeared = false` في الصفحة + `.onAppear { appeared = true }`
// ثم `.dsCardCascade(index, appeared: appeared)` على كل بطاقة. «تقليل الحركة»: تلاشٍ فقط.

struct DSCardCascade: ViewModifier {
    let index: Int
    let appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 30)
            .animation(reduceMotion ? .easeOut(duration: 0.2)
                                    : DS.Anim.smooth.delay(Double(min(max(index, 0), 6)) * 0.06),
                       value: appeared)
    }
}

extension View {
    /// دخول البطاقة رقم [index] في قائمة الصفحة (نمط الأخبار والديوانيات)
    func dsCardCascade(_ index: Int, appeared: Bool) -> some View {
        modifier(DSCardCascade(index: index, appeared: appeared))
    }
}

/// دخول تباعاً عند تفعيل شرط (مثل توسيع «عرض التفاصيل») بدل الظهور مرة عند الفتح
struct DSStaggerWhen: ViewModifier {
    let index: Int
    let active: Bool
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        let settled = shown || reduceMotion
        return content
            .opacity(shown ? 1 : 0)
            .offset(y: settled ? 0 : DSMotion.rise)
            .scaleEffect(settled ? 1 : DSMotion.riseScale, anchor: .top)
            .onAppear { shown = active }
            .onChange(of: active) { on in
                if on {
                    // نفس صعود الأقسام — و«تقليل الحركة»: تلاشٍ فقط
                    withAnimation(reduceMotion ? DSMotion.fade
                                               : DSMotion.section.delay(DSMotion.staggerDelay(index, base: 0.06))) {
                        shown = true
                    }
                } else {
                    shown = false
                }
            }
    }
}

extension View {
    func dsStaggerWhen(_ index: Int, active: Bool) -> some View {
        modifier(DSStaggerWhen(index: index, active: active))
    }
}

// MARK: - قسم داخل المربّع

struct DSComposerSection<Content: View>: View {
    let title: String
    let icon: String
    var tint: Color = DS.Color.primary
    var trailing: String? = nil
    var index: Int = 0
    /// قسم قابل للطي: الضغط على العنوان يفتح المحتوى ويخفيه (مثل «العائلة»)
    var isOpen: Binding<Bool>? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dsStaggerBase) private var staggerBase
    @Environment(\.dsBoxTint) private var boxTint

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm + 2) {
            if let isOpen {
                Button {
                    // البطاقة تتمدّد بنابض هادئ والسهم يدور — «تقليل الحركة»: فتح/طي مباشر
                    withAnimation(reduceMotion ? nil : DSMotion.expand) { isOpen.wrappedValue.toggle() }
                } label: {
                    headerRow(chevronUp: isOpen.wrappedValue)
                        // مساحة ضغط ٤٤ نقطة (حد أبل) والعنوان بنفس ارتفاعه
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                        .padding(.vertical, -11)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint(isOpen.wrappedValue ? L10n.t("يخفي المحتوى", "Collapses")
                                                       : L10n.t("يعرض المحتوى", "Expands"))
            } else {
                headerRow(chevronUp: nil)
            }
            if isOpen?.wrappedValue ?? true {
                content()
                    .transition(contentTransition)
            }
        }
        .padding(DS.Spacing.md)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1))
        .dsStaggerIn(index)
    }

    /// الفتح: المحتوى ينساب من تحت العنوان مع تلاشٍ بعد بدء تمدّد البطاقة بلحظة؛
    /// الطي: يتلاشى سريعاً قبل أن تنكمش البطاقة فوقه
    private var contentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: AnyTransition.opacity.combined(with: .offset(y: -8))
                .animation(DSMotion.expand.delay(0.04)),
            removal: AnyTransition.opacity.animation(.easeOut(duration: 0.12))
        )
    }

    /// عنوان القسم: أيقونة بدائرة + العنوان + نص جانبي (+ سهم للقسم القابل للطي)
    private func headerRow(chevronUp: Bool?) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(tint.dsHarmonized(with: boxTint).dsReadableGlyph)
                .frame(width: 22, height: 22)
                .background(Circle().fill(tint.dsHarmonized(with: boxTint).dsReadableGlyph.opacity(0.13)))
                // أيقونة القسم تتفتّح بعد صعود بطاقتها بقليل — نفس لغة أيقونة الرأس
                .modifier(DSIconPop(delay: DSMotion.staggerDelay(index, base: staggerBase) + 0.08,
                                    fromScale: 0.6, fromAngle: 0))
            Text(title)
                .font(DS.Font.plex(12.5, weight: .bold))
                .foregroundColor(DS.Color.fieldLabel)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(DS.Font.plex(11, weight: .semibold))
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            if let chevronUp {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
                    .rotationEffect(.degrees(chevronUp ? 180 : 0))
            }
        }
    }
}

// MARK: - حقل

/// حقل بعنوان صغير فوق النص — إطاره يتلوّن بلون القسم عند الكتابة
struct DSComposerField: View {
    let icon: String
    let label: String
    let placeholder: String
    @Binding var text: String
    var tint: Color = DS.Color.primary
    var multiline: Bool = false
    var limit: Int? = nil
    var keyboard: UIKeyboardType = .default
    var ltr: Bool = false
    /// حقل إنجليزي يبقي التصحيح والحرف الكبير (مثل أسماء التصنيفات) — الافتراضي يطفئهما
    var ltrKeepsAutocorrect: Bool = false
    @FocusState private var focused: Bool
    /// نبضة صغيرة لأيقونة الحقل عند التركيز (مرة واحدة)
    @State private var iconPop = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dsBoxTint) private var boxTint
    @Environment(\.dsInCenterBox) private var inBox

    var body: some View {
        // داخل مربّع: لون الحقل = لون المربّع (تنسيق)
        let tint = self.tint.dsHarmonized(with: boxTint)
        return HStack(alignment: multiline ? .top : .center, spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: inBox ? 12 : 13, weight: .semibold))
                .foregroundColor(focused ? .white : tint)
                .frame(width: inBox ? DSFieldMetrics.boxIconSize : 32, height: inBox ? DSFieldMetrics.boxIconSize : 32)
                .background(RoundedRectangle(cornerRadius: inBox ? 8 : 9, style: .continuous)
                    .fill(focused ? tint : tint.opacity(0.12)))
                .scaleEffect(iconPop ? 1.08 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(label)
                        .dsFieldFont(12, weight: .heavy)
                        .foregroundColor(focused ? tint : DS.Color.fieldLabel)
                    Spacer(minLength: 0)
                    if let limit, focused || !text.isEmpty {
                        Text("\(text.count)/\(limit)")
                            .font(DS.Font.plex(10, weight: .semibold))
                            .foregroundColor(text.count >= limit ? DS.Color.error : DS.Color.textTertiary)
                            .monospacedDigit()
                    }
                }
                Group {
                    if multiline {
                        TextField(placeholder, text: $text, axis: .vertical).lineLimit(1...4)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .dsFieldFont(14.5)
                .foregroundColor(DS.Color.textPrimary)
                .keyboardType(keyboard)
                .autocorrectionDisabled(ltr && !ltrKeepsAutocorrect)
                .textInputAutocapitalization(ltr && !ltrKeepsAutocorrect ? .never : .sentences)
                .environment(\.layoutDirection, ltr ? .leftToRight : LanguageManager.shared.layoutDirection)
                .focused($focused)
            }
        }
        .padding(.horizontal, DS.Spacing.sm + 2)
        .padding(.vertical, inBox ? DSFieldMetrics.boxVerticalPadding : DS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(focused ? tint.opacity(0.65) : DS.Color.textTertiary.opacity(0.15),
                          lineWidth: focused ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .animation(.easeInOut(duration: 0.2), value: focused)
        .onChange(of: text) { v in
            if let limit, v.count > limit { text = String(v.prefix(limit)) }
        }
        // التركيز: الأيقونة تتلوّن وتنبض نبضة صغيرة — «تقليل الحركة»: اللون فقط
        .onChange(of: focused) { on in
            guard on, !reduceMotion else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { iconPop = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { iconPop = false }
            }
        }
    }
}

// MARK: - أيقونة حقل + صندوق صف

/// أيقونة الحقل (مربّع مستدير صغير) — نفس أيقونة DSComposerField
// MARK: - تنسيق ألوان المربّع (طلب المالك ٢٠٢٦-٠٩-٢٧: «الألوان بشكل منسق أكثر»)
//
// كل مربّع يمرّر لونه لما بداخله: أيقونات الأقسام والحقول والإضافات تأخذ لون رأس المربّع
// نفسه — فالمربّع الواحد بلون واحد متناسق. يبقى الأحمر (حذف/خطر) والكهرماني (تنبيه/انتظار)
// كما هما لأنهما دلالة. خارج المربّعات (الصفحات) لا يتغيّر شيء.

private struct DSBoxTintKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    /// لون المربّع الحالي — nil خارج المربّعات
    var dsBoxTint: Color? {
        get { self[DSBoxTintKey.self] }
        set { self[DSBoxTintKey.self] = newValue }
    }
}

extension Color {
    /// داخل مربّع: لون المربّع نفسه، إلا الأحمر والكهرماني (دلالة) — وخارجه اللون كما هو
    func dsHarmonized(with box: Color?) -> Color {
        guard let box, self != DS.Color.error, self != DS.Color.warning else { return self }
        return box
    }
}

extension Color {
    /// لون أيقونة/شارة مقروء في الوضعين: الكحلي الغامق (`actionNavy`) يختفي كرمز على بطاقة داكنة،
    /// فنستعمل `primary` — نفس الكحلي تماماً في الفاتح، وأزرق فاتح مقروء في الداكن. باقي الألوان كما هي.
    var dsReadableGlyph: Color { self == DS.Color.actionNavy ? DS.Color.primary : self }
}

struct DSFieldIcon: View {
    let name: String
    var tint: Color = DS.Color.primary
    @Environment(\.dsBoxTint) private var boxTint
    @Environment(\.dsInCenterBox) private var inBox
    var body: some View {
        let glyph = tint.dsHarmonized(with: boxTint).dsReadableGlyph
        let side = inBox ? DSFieldMetrics.boxIconSize : 32
        Image(systemName: name)
            .font(.system(size: inBox ? 12 : 13, weight: .semibold))
            .foregroundColor(glyph)
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: inBox ? 8 : 9, style: .continuous).fill(glyph.opacity(0.12)))
    }
}

extension View {
    /// صف داخل قسم في صندوق بنفس إطار حقول المربّعات
    func dsRowBox() -> some View {
        modifier(DSRowBoxModifier())
    }
}

// MARK: - شارة إضافة اختيارية

/// «+ صور» / «+ تصويت»… — فارغة بإطار متقطّع، ومملوءة بلونها مع ملخّص ما أُضيف
struct DSExtraChip: View {
    let icon: String
    let title: String
    var tint: Color = DS.Color.primary
    /// ملخّص ما أُضيف — nil = لم يُضف شيء بعد
    var summary: String? = nil
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.dsBoxTint) private var boxTint

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: summary == nil ? "plus" : icon)
                    .font(.system(size: 11.5, weight: .bold))
                if summary == nil {
                    Image(systemName: icon).font(.system(size: 11.5, weight: .semibold))
                }
                Text(summary ?? title)
                    .font(DS.Font.plex(12, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundColor(summary == nil ? DS.Color.textSecondary : tint.dsHarmonized(with: boxTint))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(summary == nil ? Color.clear : tint.dsHarmonized(with: boxTint).opacity(0.12)))
            .overlay(
                Capsule().strokeBorder(summary == nil ? DS.Color.textTertiary.opacity(0.4) : tint.dsHarmonized(with: boxTint).opacity(0.45),
                                       style: StrokeStyle(lineWidth: 1.2, dash: summary == nil ? [4, 3] : []))
            )
            // مساحة ضغط ٤٤ نقطة (الحد الأدنى عند أبل) والشكل كما هو
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(summary.map { "\(title): \($0)" } ?? title)
        // تمتلئ الشارة بنابض حين يُضاف شيء — «تقليل الحركة»: تتبدّل مباشرة
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: summary)
    }
}

// MARK: - المربّع الإضافي

/// مربّع صغير يطلع فوق مربّع الإضافة للأشياء الاختيارية. يُعرض عبر
/// `.dsExtraBox(item:)` ويُغلق بحركة قبل أن يختفي.
struct DSExtraBox<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    var tint: Color = DS.Color.primary
    var doneTitle: String = L10n.t("تم", "Done")
    var doneEnabled: Bool = true
    /// بلا زر إجراء (خطوة اختيار فقط) — يبقى «إلغاء» بعرض كامل
    var showsDone: Bool = true
    /// خطوة رجوع داخل المربّع (مثل: من إدخال الحساب لقائمة المنصّات)
    var onBack: (() -> Void)? = nil
    let onDone: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var appeared = false
    /// لحظة الفتح — لمعة «جاهز» لا تظهر أثناء الدخول
    @State private var openedAt = Date()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.3 : 0)
                .ignoresSafeArea()
                .onTapGesture { close(onCancel) }

            // نفس تسلسل المربّعات: الأيقونة تقفز ← العنوان ← المحتوى يصعد ← الأزرار آخراً
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                headerRow

                VStack(alignment: .leading, spacing: DS.Spacing.md) { content() }
                    .dsEntrance(delay: 0.2, y: DSMotion.rise, scale: DSMotion.riseScale)

                buttonsRow
                    .dsEntrance(delay: 0.28, y: DSMotion.footerRise, animation: DSMotion.footer)
            }
            .padding(DS.Spacing.lg + 2)
            .frame(maxWidth: 380)
            .background(DS.Color.background)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.06),
                                  lineWidth: colorScheme == .dark ? 1.25 : 1)
            )
            .overlay(alignment: .top) {
                // خط لون القسم أعلى المربّع
                Capsule().fill(tint).frame(width: 44, height: 4).padding(.top, 7)
            }
            .shadow(color: .black.opacity(0.3), radius: 26, x: 0, y: 12)
            .padding(.horizontal, DS.Spacing.xl)
            // يطلع فوق المربّع: يكبر من ٠٫٩٤ ويصعد قليلاً مع تلاشٍ
            .scaleEffect(appeared || reduceMotion ? 1 : DSMotion.panelScale)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .opacity(appeared ? 1 : 0)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear {
            withAnimation(reduceMotion ? DSMotion.fade : DSMotion.panel) { appeared = true }
        }
    }

    private var headerRow: some View {
        HStack(spacing: DS.Spacing.sm + 2) {
            ZStack {
                Circle().fill(LinearGradient(colors: [tint, tint.opacity(0.75)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .id(icon)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
            }
            .frame(width: 40, height: 40)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: icon)
            .shadow(color: tint.opacity(0.35), radius: 8, y: 3)
            .modifier(DSIconPop())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(DS.Font.plex(16, weight: .bold)).foregroundColor(DS.Color.textPrimary)
                    .dsEntrance(delay: 0.12, x: -8, animation: DSMotion.text)
                if let subtitle {
                    Text(subtitle).font(DS.Font.plex(11.5)).foregroundColor(DS.Color.textSecondary)
                        .dsEntrance(delay: 0.17, x: -8, animation: DSMotion.text)
                }
            }
            Spacer(minLength: 0)
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(DS.Color.mutedBackground.opacity(0.8)))
                        .frame(width: 44, height: 44)   // مساحة ضغط ٤٤ (توصية أبل)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel(L10n.t("رجوع", "Back"))
            }
        }
    }

    private var buttonsRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            if showsDone {
                Button { close(onDone) } label: {
                    Text(doneTitle)
                        .font(DS.Font.plex(14.5, weight: .bold))
                        .foregroundColor(DSActionFill.label())
                        .opacity(doneEnabled ? 1 : DSActionFill.labelDisabledOpacity)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        // نفس DSActionFill.style(enabled:) — الشفافية على الطبقة فتتحرّك بسلاسة
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .fill(DSActionFill.style())
                                .opacity(doneEnabled ? 1 : DSActionFill.disabledOpacity)
                        )
                        .animation(DSMotion.enable, value: doneEnabled)
                        .modifier(DSReadyGlow(isReady: doneEnabled,
                                              armed: Date().timeIntervalSince(openedAt) > 0.6,
                                              cornerRadius: DS.Radius.md))
                }
                .disabled(!doneEnabled)
            }
            Button { close(onCancel) } label: {
                Text(L10n.t("إلغاء", "Cancel"))
                    .font(DS.Font.plex(14.5, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.mutedBackground.opacity(0.8)))
            }
        }
        .buttonStyle(DSPressStyle())
    }

    private func close(_ then: @escaping () -> Void) {
        withAnimation(.easeIn(duration: 0.18)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { then() }
    }
}

extension View {
    /// يعرض مربّعاً إضافياً فوق مربّع الإضافة (بلا انزلاق من الأسفل)
    func dsExtraBox<Item: Identifiable, C: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> C
    ) -> some View {
        fullScreenCover(item: item) { it in
            content(it).background(ClearPresentationBackground())
        }
        .transaction { t in if item.wrappedValue != nil { t.disablesAnimations = true } }
    }
}

/// إغلاق المربّع الإضافي بلا انزلاق — نفس فكرة إغلاق مربّعات المنتصف
func dsCloseExtra(_ body: () -> Void) {
    var t = Transaction()
    t.disablesAnimations = true
    withTransaction(t, body)
}

// MARK: - شريط صور

/// صور مصغّرة أفقية مع مربّع «إضافة» — تدخل الصورة الجديدة بقفزة ناعمة
struct DSComposerPhotoStrip: View {
    @Binding var images: [UIImage]
    let limit: Int
    var tint: Color = DS.Color.primary
    var size: CGFloat = 76
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var loading = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                if images.count < limit {
                    PhotosPicker(selection: $pickerItems,
                                 maxSelectionCount: max(1, limit - images.count),
                                 matching: .images) {
                        VStack(spacing: 4) {
                            if loading {
                                ProgressView().tint(tint)
                            } else {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 19, weight: .semibold))
                                Text(L10n.t("إضافة", "Add")).font(DS.Font.plex(11, weight: .bold))
                            }
                        }
                        .foregroundColor(tint)
                        .frame(width: size, height: size)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(tint.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .strokeBorder(tint.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
                    }
                    .disabled(loading)
                }
                ForEach(Array(images.enumerated()), id: \.offset) { idx, img in
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                // «تقليل الحركة»: تُحذف مباشرة بلا انزلاق الصور المجاورة
                                _ = withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) {
                                    images.remove(at: idx)
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9.5, weight: .heavy))
                                    .foregroundColor(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(Color.black.opacity(0.55)))
                                    .padding(5)
                                    // مساحة ضغط ٤٤ نقطة حول الشارة الصغيرة (حد أبل)
                                    .frame(width: 44, height: 44, alignment: .topLeading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.t("حذف الصورة", "Remove photo"))
                        }
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .padding(.vertical, 2)
        }
        .onChange(of: pickerItems) { items in
            guard !items.isEmpty else { return }
            loading = true
            Task {
                var loaded: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) { loaded.append(img) }
                }
                await MainActor.run {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.7)) {
                        images.append(contentsOf: loaded.prefix(max(0, limit - images.count)))
                    }
                    pickerItems = []
                    loading = false
                }
            }
        }
    }
}

// MARK: - شعار دائري

/// شعار دائري كبير: فارغ → حلقة متقطّعة تدور ببطء وكاميرا، ومختار → الصورة
/// مع شارة تغيير. يقصّ الصورة دائرياً بعد الاختيار.
struct DSComposerLogoPicker: View {
    @Binding var image: UIImage?
    /// الشعار الحالي (في التعديل) — يُعرض حتى يُختار غيره
    var existingURL: String? = nil
    var tint: Color = DS.Color.primary
    var size: CGFloat = 92
    @State private var pickerItem: PhotosPickerItem?
    @State private var rawImage: UIImage?
    @State private var showCropper = false
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 6) {
            Button { showPicker = true } label: {
                ZStack {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(tint.opacity(0.5), lineWidth: 2))
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                    } else if let existingURL, let url = URL(string: existingURL) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: { Circle().fill(tint.opacity(0.08)) }
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(tint.opacity(0.5), lineWidth: 2))
                    } else {
                        Circle()
                            .fill(tint.opacity(0.08))
                            .frame(width: size, height: size)
                        Circle()
                            .strokeBorder(tint.opacity(0.55), style: StrokeStyle(lineWidth: 1.6, dash: [6, 5]))
                            .frame(width: size, height: size)
                            .rotationEffect(.degrees(spin ? 360 : 0))
                        VStack(spacing: 3) {
                            Image(systemName: "camera.fill").font(.system(size: 22, weight: .semibold))
                            Text(L10n.t("شعار", "Logo")).font(DS.Font.plex(11, weight: .bold))
                        }
                        .foregroundColor(tint)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: (image == nil && existingURL == nil) ? "plus" : "pencil")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(tint))
                        .overlay(Circle().strokeBorder(DS.Color.background, lineWidth: 2.5))
                        .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(DSPressStyle())
            .contextMenu {
                if image != nil {
                    Button(role: .destructive) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { image = nil }
                    } label: { Label(L10n.t("حذف الشعار", "Remove logo"), systemImage: "trash") }
                }
            }

            Text((image == nil && existingURL == nil) ? L10n.t("اضغط لإضافة الشعار (اختياري)", "Tap to add a logo (optional)")
                              : L10n.t("اضغط للتغيير · اضغط مطوّلاً للحذف", "Tap to change · long-press to remove"))
                .font(DS.Font.plex(11))
                .foregroundColor(DS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    await MainActor.run { rawImage = img; showCropper = true }
                }
                await MainActor.run { pickerItem = nil }
            }
        }
        .fullScreenCover(isPresented: $showCropper) {
            if let rawImage {
                ImageCropperView(image: rawImage, cropShape: .circle, onCrop: { cropped in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.68)) { image = cropped }
                    showCropper = false
                    self.rawImage = nil
                }, onCancel: {
                    showCropper = false
                    self.rawImage = nil
                })
            }
        }
        .onAppear {
            guard !reduceMotion else { return }   // الإطار ثابت مع «تقليل الحركة»
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}


// MARK: - فتح أي مربّع بمنتصف الشاشة بسطر واحد (بدل .sheet)

/// `.dsCenterBox(isPresented:) { MyBox() }` بدل `.sheet(isPresented:)` — نفس نمط مربّعات
/// الإضافة: غطاء كامل شفاف + `DSCenterPanel(hugsContent:)` + بلا انزلاق النظام من الأسفل.
private struct DSCenterBoxModifier<Box: View>: ViewModifier {
    @Binding var isPresented: Bool
    var onDismiss: (() -> Void)?
    var onBackgroundTap: (() -> Void)?
    let box: () -> Box

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented, onDismiss: onDismiss) {
                DSCenterPanel(onBackgroundTap: onBackgroundTap, hugsContent: true) { box() }
                    .background(ClearPresentationBackground())
            }
            .transaction { t in if isPresented { t.disablesAnimations = true } }
    }
}

private struct DSCenterBoxItemModifier<Item: Identifiable, Box: View>: ViewModifier {
    @Binding var item: Item?
    var onDismiss: (() -> Void)?
    var onBackgroundTap: (() -> Void)?
    let box: (Item) -> Box

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $item, onDismiss: onDismiss) { value in
                DSCenterPanel(onBackgroundTap: onBackgroundTap, hugsContent: true) { box(value) }
                    .background(ClearPresentationBackground())
            }
            .transaction { t in if item != nil { t.disablesAnimations = true } }
    }
}

extension View {
    /// مربّع بمنتصف الشاشة (بدل الورقة السفلية) — المحتوى عادةً `DSComposer`
    func dsCenterBox<Box: View>(isPresented: Binding<Bool>,
                                onDismiss: (() -> Void)? = nil,
                                onBackgroundTap: (() -> Void)? = nil,
                                @ViewBuilder content: @escaping () -> Box) -> some View {
        modifier(DSCenterBoxModifier(isPresented: isPresented, onDismiss: onDismiss,
                                     onBackgroundTap: onBackgroundTap, box: content))
    }

    /// نفس `dsCenterBox(isPresented:)` لكن بعنصر (بدل `.sheet(item:)`)
    func dsCenterBox<Item: Identifiable, Box: View>(item: Binding<Item?>,
                                                    onDismiss: (() -> Void)? = nil,
                                                    onBackgroundTap: (() -> Void)? = nil,
                                                    @ViewBuilder content: @escaping (Item) -> Box) -> some View {
        modifier(DSCenterBoxItemModifier(item: item, onDismiss: onDismiss,
                                         onBackgroundTap: onBackgroundTap, box: content))
    }
}


// MARK: - مربّع طويل من الأسفل للمحتوى الطويل (توصية أبل)

/// للمحتوى الطويل فقط (محادثة، قراءة طويلة، قوائم آلاف الأعضاء): نفس تصميم المربّعات
/// (رأس ملوّن، أقسام، أزرار أسفل) داخل ورقة طويلة من الأسفل تُغلق بالسحب — وما عداها
/// يبقى مربّعاً بالمنتصف (`dsCenterBox`).
private struct DSTallBoxStyle: ViewModifier {
    func body(content: Content) -> some View {
        let styled = content
            .background(DS.Color.background.ignoresSafeArea())
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        if #available(iOS 16.4, *) {
            styled.presentationCornerRadius(DS.Radius.xxl)
        } else {
            styled
        }
    }
}

/// نصف الشاشة من الأسفل (طلب المالك ٢٠٢٦-١٠-٠١: التعليقات «نص شاشة» بزر إغلاق) — يفتح
/// بالنصف ويُسحب للأعلى عند الحاجة، والتمرير يحرّك المحتوى لا الورقة.
private struct DSHalfBoxStyle: ViewModifier {
    func body(content: Content) -> some View {
        let styled = content
            .background(DS.Color.background.ignoresSafeArea())
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        if #available(iOS 16.4, *) {
            styled
                .presentationCornerRadius(DS.Radius.xxl)
                .presentationContentInteraction(.scrolls)
        } else {
            styled
        }
    }
}

extension View {
    /// نصف الشاشة من الأسفل — يفتح بالنصف ويُسحب للأعلى
    func dsHalfBox<Item: Identifiable, Box: View>(item: Binding<Item?>,
                                                  onDismiss: (() -> Void)? = nil,
                                                  @ViewBuilder content: @escaping (Item) -> Box) -> some View {
        sheet(item: item, onDismiss: onDismiss) { value in
            content(value).modifier(DSHalfBoxStyle())
        }
    }

    /// مربّع طويل من الأسفل (بدل `dsCenterBox`) للمحتوى الطويل — يُغلق بالسحب أو بزره
    func dsTallBox<Box: View>(isPresented: Binding<Bool>,
                              onDismiss: (() -> Void)? = nil,
                              @ViewBuilder content: @escaping () -> Box) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content().modifier(DSTallBoxStyle())
        }
    }

    /// نفس `dsTallBox(isPresented:)` لكن بعنصر
    func dsTallBox<Item: Identifiable, Box: View>(item: Binding<Item?>,
                                                  onDismiss: (() -> Void)? = nil,
                                                  @ViewBuilder content: @escaping (Item) -> Box) -> some View {
        sheet(item: item, onDismiss: onDismiss) { value in
            content(value).modifier(DSTallBoxStyle())
        }
    }
}

/// صندوق صف داخل قسم — أقصر قليلاً داخل المربّعات بالمنتصف (طلب المالك)
private struct DSRowBoxModifier: ViewModifier {
    @Environment(\.dsInCenterBox) private var inBox
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DS.Spacing.sm + 2)
            .padding(.vertical, inBox ? DSFieldMetrics.boxVerticalPadding : DS.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.textTertiary.opacity(0.15), lineWidth: 1))
    }
}
