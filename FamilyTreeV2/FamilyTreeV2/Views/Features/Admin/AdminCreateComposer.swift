import SwiftUI

// MARK: - «إنشاء» — المنشئ الواحد في «المناسبات والإعلانات» (الدفعة ب من «نفّذ كل المقترح»، ٢٠٢٦-١٠-٢٠)
//
// مربّع واحد «ماذا تنشئ؟» بأربعة أنواع بدل أربعة منشئات متفرّقة (D7 · D8 · D9 · D10 في AUDIT.md):
//   • إعلان — المنشئ المختصر نفسه (`AdminAnnounceComposer`، تبسيط ٢٠٢٦-١٠-٢٢: شاشة واحدة — النص · لمن · أرسل الآن/جدولة،
//     إشعار فقط بعنوان ثابت، وزرّ واحد يقول ما سيحدث) — كان أيضاً صفحة «إشعار للأعضاء» الكاملة. ويفتحه «تعديل» في
//     «الإشعارات المجدولة» بمسودّة الإشعار المجدول (`AdminAnnounceDraft(editing:)`) بلا مربّع الأنواع.
//   • إعلان وفاة — اختيار المتوفى (وفيات آخر ٣٠ يوماً لم يُعلن عنها) ثم مربّع `DeathAnnouncementBox` نفسه (`announce_death`).
//   • بطاقة تهنئة أو تعزية — مصمّم البطاقات نفسه (`OccasionComposerView`) يُفتح فوق المربّع.
//   • إعلان تحديث التطبيق — ما الجديد في الإصدار (`sendNotification(kind: app_update)` كما كانت صفحته).
// البيت الوحيد: زرّ «إنشاء» في رأس «المناسبات والإعلانات»؛ ومكبّر الصوت في رأس «اليوم» (طلب المالك) يفتح المربّع نفسه
// على «إعلان». يُعرض في نافذة مستقلّة (حارس المكدس — «اليوم» على سقف مكدس الجوال، كما كان `AdminAnnounceWindow`).
// الصلاحيات كما كانت: الإعلان والتحديث `canSendNotifications`، إعلان الوفاة `isAdmin`، البطاقة `canModerate` + خانة `occasions.cards` في الجدول.
// لا منطق إرسال جديد — كل نوع يستدعي مساره الموجود، وحارس السيرفر يبقى الحَكَم.

/// نوع ما يُنشأ
enum AdminCreateKind: String, CaseIterable, Identifiable {
    case announcement, death, card, appUpdate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .announcement: return L10n.t("إرسال إشعار", "Send a push")
        case .death:        return L10n.t("إعلان وفاة", "Obituary")
        case .card:         return L10n.t("تصميم إعلان", "Design an announcement")
        case .appUpdate:    return L10n.t("إعلان تحديث التطبيق", "App update notice")
        }
    }

    var note: String {
        switch self {
        case .announcement: return L10n.t("إشعار للأعضاء — الآن أو بموعد", "A push — now or scheduled")
        case .death:        return L10n.t("نص معتمد + موعد الدفن", "Standard text + burial time")
        case .card:         return L10n.t("صورة للحفظ والمشاركة", "An image to save and share")
        case .appUpdate:    return L10n.t("ما الجديد في الإصدار", "What's new in the release")
        }
    }

    var icon: String {
        switch self {
        case .announcement: return "megaphone.fill"
        case .death:        return NewsTypeHelper.icon(for: "وفاة")
        case .card:         return "photo.on.rectangle.angled"
        case .appUpdate:    return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .announcement: return DS.Color.sea
        case .death:        return DS.Color.slate
        case .card:         return DS.Color.sadu
        case .appUpdate:    return DS.Color.accent
        }
    }

    /// الأنواع المتاحة لدور المشاهد — بالترتيب
    @MainActor
    static func allowed(for authVM: AuthViewModel) -> [AdminCreateKind] {
        // شريط «إنشاء»: الإعلان وبطاقات المناسبات فقط (طلب المالك ٢٠٢٦-١٠-٢٣) — «إعلان وفاة» يبقى من صفحة العضو ومن «القادم»،
        // و«تحديث التطبيق» أُزيل من الشريط
        var list: [AdminCreateKind] = []
        if authVM.canSendNotifications { list.append(.announcement) }
        // البطاقة: المالك والمدير والمشرف (محتوى — جدول «مين يشوف وش» من السيرفر؛ المراقب لا، ٢٠٢٦-١١-٠٧)
        if authVM.canModerate && authVM.adminAccess(.occasionsCards).canEdit { list.append(.card) }
        return list
    }
}

/// الإعلان اللي يفتح عليه المصمّم
struct AdminCreateDesignTarget: Identifiable {
    let id: String
}

// MARK: - النافذة المستقلّة

/// يعرض «ماذا تنشئ؟» في نافذة فوق كل شيء (مثل `DeathAnnouncementPresenter`) — لا مُعدِّل عرض على «اليوم» ولا على صفحة القسم
@MainActor
enum AdminCreateWindow {
    private static var window: UIWindow?
    private static weak var previousKey: UIWindow?

    /// `start` النوع المفتوح أولاً (إن كان متاحاً للدور)، و`death` متوفى جاهز لـ«إعلان وفاة» (من «القادم»)،
    /// و`announce` مسودّة «إعلان» (تعديل إشعار مجدول من «القادم» — المربّع وحده بلا «ماذا تنشئ؟»)
    /// `chooser: false` = المربّع وحده بلا «ماذا تنشئ؟» (أزرار قسم «المناسبات والإعلانات» — كل زر يفتح نوعه بس،
    /// المالك ٢٠٢٦-١١-٠٨)؛ و«تصميم إعلان» بإعلان جاهز (`cardTemplate`) بلا اختيار يفتح المصمّم مباشرة على إعلانه
    static func open(_ start: AdminCreateKind = .announcement, death: DeathAnnouncementTarget? = nil,
                     announce: AdminAnnounceDraft? = nil, cardTemplate: String? = nil, chooser: Bool = true,
                     authVM: AuthViewModel, newsVM: NewsViewModel, notificationVM: NotificationViewModel,
                     memberVM: MemberViewModel) {
        let allowed = AdminCreateKind.allowed(for: authVM)
        guard window == nil, !allowed.isEmpty, let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        previousKey = scene.windows.first(where: \.isKeyWindow)
        let first = allowed.contains(start) ? start : allowed[0]
        let root = AdminCreateRoot(allowed: chooser ? allowed : [first], start: first,
                                   death: death, announce: announce, cardTemplate: cardTemplate,
                                   directCard: !chooser && cardTemplate != nil, onClose: { close() })
            .environmentObject(authVM)
            .environmentObject(newsVM)
            .environmentObject(notificationVM)
            .environmentObject(memberVM)
            .environment(\.locale, LanguageManager.shared.locale)
            // نافذة مستقلّة لا تصلها بيئة التطبيق — لون القسم المختار (أزرار الإجراء)
            .dsSection(AppSection.current)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        let w = UIWindow(windowScene: scene)
        // تحت نافذة التنبيهات (.alert + 1) فيظهر التأكيد فوقه
        w.windowLevel = .alert
        w.backgroundColor = .clear
        w.overrideUserInterfaceStyle = DSPopupPresenter.appInterfaceStyle(in: scene)
        w.rootViewController = host
        w.makeKeyAndVisible()
        window = w
    }

    static func close() {
        guard let w = window else { return }
        window = nil
        UIView.animate(withDuration: 0.2, animations: { w.alpha = 0 }, completion: { _ in
            w.isHidden = true
            w.rootViewController = nil
            previousKey?.makeKey()
        })
    }
}

/// جذر النافذة: المربّع بنوعه المختار، ومصمّم الإعلانات فوقه بملء الشاشة. نوع واحد (المشرف، أو زرّ في «المناسبات
/// والإعلانات») = المربّع بلا «ماذا تنشئ؟». المصمّم يفتح على الإعلان المختار وحده (المالك ٢٠٢٦-١١-٠٨)
struct AdminCreateRoot: View {
    let allowed: [AdminCreateKind]
    let death: DeathAnnouncementTarget?
    /// مسودّة «إعلان» (تعديل إشعار مجدول) — nil = جديد
    let announce: AdminAnnounceDraft?
    /// يفتح المصمّم مباشرة على الإعلان الجاهز («بطاقة» على فرح في «المناسبات»)
    let directCard: Bool
    let onClose: () -> Void

    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @State private var kind: AdminCreateKind
    /// الإعلان المفتوح في المصمّم — `item` (لا Bool) حتى يوصل المصمّم الاختيار الحالي لا قيمة قديمة
    @State private var designing: AdminCreateDesignTarget?
    /// الإعلان المختار في «تصميم إعلان» — يفتح المصمّم عليه وحده (بلا اختيار مسبق: المستخدم يختار)
    @State private var cardTemplate: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(allowed: [AdminCreateKind], start: AdminCreateKind, death: DeathAnnouncementTarget?,
         announce: AdminAnnounceDraft? = nil, cardTemplate: String? = nil, directCard: Bool = false,
         onClose: @escaping () -> Void) {
        self.allowed = allowed
        self.directCard = directCard
        // «بطاقة» على فرح في «المناسبات» — المصمّم على قالبه (زواج ← عقد قران، مولود ← قدوم مولود)
        if let cardTemplate { _cardTemplate = State(initialValue: cardTemplate) }
        self.death = death
        self.announce = announce
        self.onClose = onClose
        _kind = State(initialValue: start)
    }

    var body: some View {
        Group {
            if directCard {
                Color.clear
            } else {
                // التبديل بين الأنواع بحركة: المربّع الجديد ينزلق ويظهر، والقديم يتلاشى (المالك ٢٠٢٦-١٠-٢٣ «نبي انميشن و حركات»)
                DSCenterPanel(onBackgroundTap: nil, hugsContent: true) {
                    box
                        .id(kind)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                            removal: .opacity))
                }
                .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82), value: kind)
            }
        }
        .fullScreenCover(item: $designing, onDismiss: { if directCard { onClose() } }) { target in
            NavigationStack { OccasionComposerView(startTemplateId: target.id, lockedTemplate: true) }
                .environmentObject(authVM)
                .environmentObject(memberVM)
                .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .onAppear { if directCard, let cardTemplate { designing = AdminCreateDesignTarget(id: cardTemplate) } }
        // الإعلانات والنماذج والنصوص من السيرفر (`occasion_designer`)
        .task { await AppConfigValues.shared.refresh() }
    }

    /// كل نوع منشئه الموجود خلف `AnyView` (نوع صغير لكل فرع)
    private var box: AnyView {
        // نوع واحد = بلا «ماذا تنشئ؟»
        let chooser = allowed.count > 1 ? AnyView(AdminCreateTypePicker(kinds: allowed, selection: $kind)) : AnyView(EmptyView())
        switch kind {
        case .announcement:
            // تعديل إشعار مجدول: المربّع وحده (لا تبديل نوع أثناء التعديل)
            if let announce, announce.editingId != nil {
                return AnyView(AdminAnnounceComposer(draft: announce, onClose: onClose))
            }
            return AnyView(AdminAnnounceComposer(chooser: allowed.count > 1 ? chooser : nil,
                                                 draft: announce ?? AdminAnnounceDraft(), onClose: onClose))
        case .death:
            return AnyView(AdminCreateDeathForm(chooser: chooser, preset: death, onClose: onClose))
        case .card:
            return AnyView(AdminCreateCardForm(chooser: chooser, single: allowed.count == 1, selection: $cardTemplate,
                                        onOpen: { if let id = cardTemplate { designing = AdminCreateDesignTarget(id: id) } }, onClose: onClose))
        case .appUpdate:
            return AnyView(AdminAppUpdateComposer(chooser: chooser, onClose: onClose))
        }
    }
}

/// «ماذا تنشئ؟» — مربّعات الأنواع (عمودان، وعمود واحد مع الخط الكبير جداً): رمز + الاسم + سطر يشرحه
struct AdminCreateTypePicker: View {
    let kinds: [AdminCreateKind]
    @Binding var selection: AdminCreateKind
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dsSection) private var section

    var body: some View {
        let cols = typeSize >= .accessibility1 ? 1 : 2
        VStack(spacing: DS.Spacing.sm) {
            ForEach(Array(stride(from: 0, to: kinds.count, by: cols)), id: \.self) { start in
                let end = min(start + cols, kinds.count)
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(kinds[start..<end]) { tile($0) }
                    ForEach(0..<(cols - (end - start)), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: DS.Border.width)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("ماذا تنشئ؟", "What to create?"))
    }

    private func tile(_ kind: AdminCreateKind) -> some View {
        let selected = kind == selection
        let ink = kind.tint.dsChrome(in: section).dsReadableGlyph
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        return Button {
            guard !selected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(DS.Anim.snappy) { selection = kind }
        } label: {
            // صفّ مضغوط: رمز صغير + الاسم، بلا السطر الوصفي (المالك ٢٠٢٦-١٠-٢٣ «قلل حجم مربعات ماذا ننشئ»)
            HStack(spacing: DS.Spacing.sm) {
                AdminIconSquare(symbol: kind.icon, tint: kind.tint, side: DS.Icon.row,
                                radius: DS.Hub.miniIconRadius, filled: true, glyph: DS.Glyph.sm)
                Text(kind.title)
                    .dsFont(.hubButton)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(shape.fill(selected ? ink.opacity(DS.Opacity.tintFillSoft) : DS.Color.surface))
            .overlay(shape.strokeBorder(selected ? ink.opacity(DS.Opacity.selectedStroke)
                                                 : DS.Color.textTertiary.opacity(DS.Opacity.border),
                                        lineWidth: selected ? DS.Border.widthBold : DS.Border.width))
            .contentShape(shape)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - إعلان وفاة: اختيار المتوفى ثم المربّع نفسه

/// وفيات آخر ٣٠ يوماً لم يُعلن عنها — الضغط يختار، ثم مربّع `DeathAnnouncementBox` بنصّه المعتمد وموعد الدفن.
/// من «القادم» يصل المتوفى جاهزاً
struct AdminCreateDeathForm: View {
    let chooser: AnyView
    let onClose: () -> Void

    @EnvironmentObject private var memberVM: MemberViewModel
    @State private var target: DeathAnnouncementTarget?
    /// المعلن عنهم — nil أثناء الجلب
    @State private var announced: Set<UUID>? = nil

    init(chooser: AnyView, preset: DeathAnnouncementTarget?, onClose: @escaping () -> Void) {
        self.chooser = chooser
        self.onClose = onClose
        _target = State(initialValue: preset)
    }

    private var tint: Color { DS.Color.actionNavy }

    /// نفس قائمة «الوفيات والإعلان» السابقة: وفيات آخر ٣٠ يوماً (الأحدث أولاً) بلا من أُعلن عنه
    private var candidates: [FamilyMember] {
        let done = announced ?? []
        return memberVM.allMembers
            .filter { $0.isDeceased == true && $0.role != .pending && DeathRecency.isRecent($0.deathDate) && !done.contains($0.id) }
            .sorted { ($0.deathDate ?? "") > ($1.deathDate ?? "") }
    }

    var body: some View {
        if let target {
            DeathAnnouncementBox(target: target, chooser: AnyView(VStack(spacing: DSBox.sectionSpacing) {
                chooser
                selectedSection(target)
            }), onClose: onClose)
            .id(target.id)
        } else {
            DSComposer(
                title: L10n.t("ماذا تنشئ؟", "What to create?"),
                subtitle: AdminCreateKind.death.title,
                icon: AdminCreateKind.death.icon,
                tint: tint,
                actionTitle: L10n.t("نشر الإعلان", "Publish"),
                actionIcon: "paperplane.fill",
                canSubmit: false,
                note: L10n.t("اختر المتوفى أولاً", "Pick the deceased first"),
                onSubmit: {},
                onCancel: onClose
            ) {
                chooser
                DSComposerSection(title: L10n.t("المتوفى", "Deceased"), icon: "person.fill", tint: tint,
                                  trailing: L10n.t("وفيات آخر ٣٠ يوماً", "Last 30 days"), index: 1) {
                    pickList
                }
            }
            .task {
                if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
                // تعذّر الجلب = تُعرض كل الوفيات الحديثة (السيرفر يرفض المكرّر برسالته)
                announced = await AdminTodayFetch.announcedDeathIds() ?? []
            }
        }
    }

    @ViewBuilder private var pickList: some View {
        if announced == nil {
            DSPageLoader(L10n.t("جارٍ التحميل…", "Loading…"), fillsSpace: false)
                .frame(maxWidth: .infinity)
        } else if candidates.isEmpty {
            DSEmptyView(L10n.t("لا توجد وفاة حديثة لم يُعلن عنها", "No recent death awaits an announcement"),
                        message: L10n.t("يظهر هنا من سُجّلت وفاته خلال ٣٠ يوماً", "Deaths recorded in the last 30 days appear here"),
                        icon: "checkmark.seal", style: .compact)
        } else {
            VStack(spacing: DS.Spacing.sm) {
                ForEach(candidates) { m in
                    Button {
                        withAnimation(DS.Anim.snappy) {
                            target = DeathAnnouncementTarget(id: m.id, name: m.fullName, isFemale: m.isFemale,
                                                             deathDate: m.deathDate)
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            DSFieldIcon(name: AdminCreateKind.death.icon, tint: tint)
                            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                                Text(m.fullName)
                                    .dsFieldFont(.rowTitle)
                                    .foregroundColor(DS.Color.fieldLabel)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(AdminOccasionsText.deathLine(m))
                                    .dsFieldFont(.subtitle)
                                    .foregroundColor(DS.Color.fieldValue)
                            }
                            Spacer(minLength: 0)
                            DSChevron()
                        }
                        .dsRowBox()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("إعلان وفاة \(m.fullName)", "Announce \(m.fullName)'s death"))
                }
            }
        }
    }

    /// المتوفى المختار + «تغيير»
    private func selectedSection(_ t: DeathAnnouncementTarget) -> some View {
        DSComposerSection(title: L10n.t("المتوفى", "Deceased"), icon: "person.fill", tint: tint, index: 1) {
            HStack(spacing: DS.Spacing.sm) {
                Text(t.name)
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DS.Spacing.xs)
                DSChipButton(L10n.t("تغيير", "Change"), icon: "arrow.left.arrow.right", size: .small) {
                    withAnimation(DS.Anim.snappy) { target = nil }
                }
            }
            .dsRowBox()
        }
    }
}

// MARK: - بطاقة تهنئة أو تعزية

/// اختيار الإعلان (عقد قران، قدوم مولود، …) ثم «صمّم الإعلان» — المصمّم (`OccasionComposerView`) بملء الشاشة فوق
/// المربّع على الإعلان المختار وحده
struct AdminCreateCardForm: View {
    let chooser: AnyView
    /// بلا «ماذا تنشئ؟» (زرّ «تصميم إعلان» في «المناسبات والإعلانات») — العنوان اسم النوع
    var single = false
    /// القالب المختار (المالك ٢٠٢٦-١٠-٢٣ «في تصميم اعلان خل اختيار نوع البطاقات»)
    @Binding var selection: String?
    let onOpen: () -> Void
    let onClose: () -> Void

    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    private var tint: Color { DS.Color.actionNavy }
    /// الإعلانات الظاهرة (إعداد السيرفر)
    private var templates: [OccasionTemplate] { OccasionTemplate.available }

    /// مربّع «رابط الموقع» مفتوح بدل اختيار الإعلان
    @State private var linksOpen = false

    var body: some View {
        Group {
            if linksOpen {
                AdminSiteLinksBox(onBack: { linksOpen = false }, onClose: onClose)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                form
                    .transition(.opacity)
            }
        }
        .animation(DS.Anim.smooth, value: linksOpen)
    }

    /// زرّ «رابط الموقع» — أيقونة صغيرة تفتح مربّعه
    private var siteLinksButton: some View {
        DSIconButton(icon: "link", size: 28, iconSize: 13, iconColor: DS.Color.accent,
                     fillColor: DS.Color.accent.opacity(DS.Opacity.tintFillSoft),
                     borderColor: DS.Color.accent.opacity(DS.Opacity.border), borderWidth: DS.Border.width) {
            UISelectionFeedbackGenerator().selectionChanged()
            linksOpen = true
        }
        .accessibilityLabel(L10n.t("رابط الموقع", "Website link"))
        .accessibilityHint(L10n.t("المولّد على الموقع لمن عنده الرابط", "The website generator, for whoever has the link"))
    }

    private var form: some View {
        DSComposer(
            title: single ? AdminCreateKind.card.title : L10n.t("ماذا تنشئ؟", "What to create?"),
            subtitle: single ? L10n.t("اختر الإعلان ثم صمّمه", "Pick one, then design it") : AdminCreateKind.card.title,
            icon: AdminCreateKind.card.icon,
            tint: tint,
            actionTitle: L10n.t("صمّم الإعلان", "Design it"),
            actionIcon: "paintbrush.pointed.fill",
            canSubmit: selection != nil,
            note: L10n.t("صورة تُحفظ في الصور أو تُشارك — لا تُرسل للأعضاء من هنا",
                         "An image to save or share — nothing is sent to members from here"),
            onSubmit: onOpen,
            onCancel: onClose
        ) {
            chooser
            // «رابط الموقع» — زرّ أيقونة في سطر عنوان القسم يفتح مربّعه: في «تصميم إعلان» من «المناسبات والإعلانات» فقط،
            // للمالك والمدير (صلاحية جدول occasion_links) — كان داخل المصمّم (المالك ٢٠٢٦-١١-٠٨)
            DSComposerSection(title: L10n.t("اختر الإعلان", "Pick the announcement"), icon: "photo.on.rectangle.angled", tint: tint, index: 1,
                              accessory: single && authVM.isAdmin ? AnyView(siteLinksButton) : nil) {
                let cols = typeSize >= .accessibility1 ? 1 : 2
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(Array(stride(from: 0, to: templates.count, by: cols)), id: \.self) { start in
                        let end = min(start + cols, templates.count)
                        HStack(spacing: DS.Spacing.sm) {
                            ForEach(templates[start..<end]) { tile($0) }
                            ForEach(0..<(cols - (end - start)), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity, maxHeight: DS.Border.width)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// التهاني ذهبية، والعزاء رمادي (لون معنى «وفاة»)
    private func tile(_ t: OccasionTemplate) -> some View {
        let selected = selection == t.id
        let color = t.kind == .happy ? DS.Color.accent : DS.Color.newsDeath
        let ink = color.dsReadableGlyph
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        return Button {
            guard !selected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(DS.Anim.snappy) { selection = t.id }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                AdminIconSquare(symbol: t.icon, tint: color, side: DS.Icon.row,
                                radius: DS.Hub.miniIconRadius, filled: true, glyph: DS.Glyph.sm)
                Text(t.title)
                    .dsFont(.hubButton)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(shape.fill(selected ? ink.opacity(DS.Opacity.tintFillSoft) : DS.Color.surface))
            .overlay(shape.strokeBorder(selected ? ink.opacity(DS.Opacity.selectedStroke)
                                                 : DS.Color.textTertiary.opacity(DS.Opacity.border),
                                        lineWidth: selected ? DS.Border.widthBold : DS.Border.width))
            .contentShape(shape)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - رابط الموقع

/// مربّع «رابط الموقع» (زرّ في «تصميم إعلان» من «المناسبات والإعلانات»): إنشاء رابط لمولّد الإعلانات على الموقع
/// ونسخه وإيقافه — نفس `OccasionLinksSection` بلا رأس. «رجوع» يرجع لاختيار الإعلان
struct AdminSiteLinksBox: View {
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        DSComposer(
            title: L10n.t("رابط الموقع", "Website link"),
            subtitle: L10n.t("نفس المولّد على الموقع بدون تسجيل دخول — لمن عنده الرابط بس",
                             "The same generator on the website without signing in — only for whoever has the link"),
            icon: "link",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("رجوع", "Back"),
            actionIcon: "chevron.backward",
            canSubmit: true,
            note: nil,
            onSubmit: onBack,
            onCancel: onClose
        ) {
            OccasionLinksSection(embedded: true)
        }
    }
}

// MARK: - إعلان تحديث التطبيق

/// نوع رسالة التحديث (كان في صفحة «رسالة تحديث التطبيق»)
enum AdminAppUpdateKind: String, CaseIterable, Identifiable {
    case feature, fix, maintenance, notice
    var id: String { rawValue }

    var title: String {
        switch self {
        case .feature:     return L10n.t("ميزة جديدة", "New feature")
        case .fix:         return L10n.t("إصلاح", "Fix")
        case .maintenance: return L10n.t("صيانة", "Maintenance")
        case .notice:      return L10n.t("تنويه", "Notice")
        }
    }

    var icon: String {
        switch self {
        case .feature:     return "sparkles"
        case .fix:         return "wrench.and.screwdriver.fill"
        case .maintenance: return "gearshape.2.fill"
        case .notice:      return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .feature:     return DS.Color.accent
        case .fix:         return DS.Color.info
        case .maintenance: return DS.Color.warning
        case .notice:      return DS.Color.primary
        }
    }

    /// عنوان الإشعار كما يصل العضو
    var headline: String {
        switch self {
        case .feature:     return L10n.t("ميزة جديدة في التطبيق", "New in the app")
        case .fix:         return L10n.t("تحسينات وإصلاحات", "Improvements & fixes")
        case .maintenance: return L10n.t("صيانة مجدولة", "Scheduled maintenance")
        case .notice:      return L10n.t("تنويه من الإدارة", "Notice from admin")
        }
    }
}

/// رسالة نظام لكل الأعضاء — تظهر في «المستجدات» بمركز الإشعارات ويصل معها إشعار. النشر كما كان تماماً:
/// صفّ واحد بلا هدف بنوع `app_update` (القاعدة تُفرّخ نسخة لكل عضو ويخرج الدفع مرة واحدة)
struct AdminAppUpdateComposer: View {
    let chooser: AnyView
    let onClose: () -> Void

    @EnvironmentObject private var notificationVM: NotificationViewModel
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var kind: AdminAppUpdateKind = .feature
    @State private var version = ""
    @State private var summary = ""
    @State private var isSending = false
    @State private var confirm = false
    @State private var failure: String? = nil
    @State private var sent = false

    private static let maxLength = 1000
    private let tint = DS.Color.brandFill

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// «ميزة جديدة في التطبيق · 2.1»
    private var finalTitle: String {
        let v = trimmed(version)
        return v.isEmpty ? kind.headline : "\(kind.headline) · \(v)"
    }

    var body: some View {
        DSComposer(
            title: L10n.t("ماذا تنشئ؟", "What to create?"),
            subtitle: AdminCreateKind.appUpdate.title,
            icon: AdminCreateKind.appUpdate.icon,
            tint: tint,
            actionTitle: L10n.t("نشر للجميع", "Publish to everyone"),
            actionIcon: "megaphone.fill",
            canSubmit: !trimmed(summary).isEmpty && !isSending,
            isBusy: isSending,
            note: trimmed(summary).isEmpty ? L10n.t("اكتب ما الجديد", "Write what's new")
                                           : L10n.t("يظهر في «المستجدات» لكل الأعضاء ويصل معه إشعار",
                                                    "Shows in Updates for everyone with a push"),
            hasUnsavedChanges: !trimmed(summary).isEmpty || !trimmed(version).isEmpty,
            onSubmit: { confirm = true },
            onCancel: onClose
        ) {
            chooser
            if AppReleaseNotes.current != nil {
                fillReleaseNotesRow
            }
            DSComposerSection(title: L10n.t("النوع", "Type"), icon: "square.grid.2x2.fill", tint: tint,
                              trailing: kind.title, index: 1) {
                DSOptionTiles(AdminAppUpdateKind.allCases.map { DSOptionTile($0, title: $0.title, icon: $0.icon, tint: $0.color) },
                              selection: $kind, columns: typeSize >= .xxxLarge ? 2 : 4)
            }
            DSComposerSection(title: L10n.t("الرسالة", "Message"), icon: "text.bubble.fill", tint: tint, index: 2) {
                DSComposerField(icon: "number", label: L10n.t("رقم الإصدار (اختياري)", "Version (optional)"),
                                placeholder: L10n.t("مثال: 2.1", "e.g. 2.1"), text: $version, tint: tint,
                                keyboard: .numbersAndPunctuation, ltr: true)
                DSComposerField(icon: "text.alignright", label: L10n.t("ما الجديد", "What's new"),
                                placeholder: L10n.t("اكتب ما تغيّر في التطبيق…", "Describe what changed…"),
                                text: $summary, tint: tint, multiline: true, limit: Self.maxLength)
            }
            DSComposerSection(title: L10n.t("المعاينة", "Preview"), icon: "eye.fill", tint: tint,
                              trailing: L10n.t("كما يصل العضو", "As members see it"), index: 3) {
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    DSStateIcon(kind.icon, tint: kind.color, size: DS.Icon.row)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(finalTitle)
                            .dsFieldFont(.rowTitle)
                            .foregroundColor(DS.Color.fieldLabel)
                        Text(summary.isEmpty ? L10n.t("نص التحديث…", "Update text…") : summary)
                            .dsFieldFont(.subtitle)
                            .foregroundColor(DS.Color.fieldValue)
                            .lineLimit(6)
                    }
                    Spacer(minLength: 0)
                }
                .dsRowBox()
                .accessibilityElement(children: .combine)
            }
        }
        .dsAlert(L10n.t("نشر للجميع؟", "Publish to everyone?"), isPresented: $confirm, icon: "megaphone.fill") {
            Button(L10n.t("نشر", "Publish")) { Task { await publish() } }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("«\(finalTitle)» يظهر في «المستجدات» ويصل إشعار لكل الأعضاء.",
                        "“\(finalTitle)” shows in Updates and every member gets a push."))
        }
        .dsAlert(L10n.t("تعذّر النشر", "Couldn't publish"), isPresented: Binding(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
        )) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
        .dsAlert(L10n.t("تم النشر", "Published"), isPresented: $sent, moment: .success, icon: "megaphone.fill") {
            Button(L10n.t("حسناً", "OK"), role: .cancel) { onClose() }
        } message: {
            Text(L10n.t("وصل إعلان التحديث لكل الأعضاء.", "The update notice reached every member."))
        }
    }

    /// «تعبئة ملاحظات هذا الإصدار» — النوع والرقم وما الجديد، ثم مراجعتها
    private var fillReleaseNotesRow: some View {
        Button {
            withAnimation(DS.Anim.quick) {
                kind = .feature
                version = AppReleaseNotes.currentVersionLabel
                summary = AppReleaseNotes.current ?? summary
            }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "wand.and.stars", tint: tint)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(L10n.t("تعبئة ملاحظات هذا الإصدار \(AppReleaseNotes.currentVersionLabel)",
                                "Fill this release's notes \(AppReleaseNotes.currentVersionLabel)"))
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.t("النوع والرقم وما الجديد — راجعها ثم انشر", "Type, version and what's new — review, then publish"))
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func publish() async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        let ok = await notificationVM.sendNotification(title: finalTitle, body: trimmed(summary),
                                                       targetMemberIds: nil, kind: "app_update")
        if ok {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            sent = true
        } else {
            failure = L10n.t("تعذّر النشر. حاول مرة أخرى.", "Could not publish. Try again.")
        }
    }
}
