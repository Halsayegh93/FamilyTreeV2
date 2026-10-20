import SwiftUI

// MARK: - «إنشاء» — المنشئ الواحد في «المناسبات والإعلانات» (الدفعة ب من «نفّذ كل المقترح»، ٢٠٢٦-١٠-٢٠)
//
// مربّع واحد «ماذا تنشئ؟» بأربعة أنواع بدل أربعة منشئات متفرّقة (D7 · D8 · D9 · D10 في AUDIT.md):
//   • إعلان — المنشئ المختصر نفسه (`AdminAnnounceComposer`: ☑ نشر في الأخبار ☑ إشعار للأعضاء، «خيارات أكثر»:
//     المستلمون والجدولة، والعناوين الجاهزة) — كان أيضاً صفحة «إشعار للأعضاء» الكاملة.
//   • إعلان وفاة — اختيار المتوفى (وفيات آخر ٣٠ يوماً لم يُعلن عنها) ثم مربّع `DeathAnnouncementBox` نفسه (`announce_death`).
//   • بطاقة تهنئة أو تعزية — مصمّم البطاقات نفسه (`OccasionComposerView`) يُفتح فوق المربّع.
//   • إعلان تحديث التطبيق — ما الجديد في الإصدار (`sendNotification(kind: app_update)` كما كانت صفحته).
// البيت الوحيد: زرّ «إنشاء» في رأس «المناسبات والإعلانات»؛ ومكبّر الصوت في رأس «اليوم» (طلب المالك) يفتح المربّع نفسه
// على «إعلان». يُعرض في نافذة مستقلّة (حارس المكدس — «اليوم» على سقف مكدس الجوال، كما كان `AdminAnnounceWindow`).
// الصلاحيات كما كانت: الإعلان والتحديث `canSendNotifications`، إعلان الوفاة `isAdmin`، البطاقة `canModerate`.
// لا منطق إرسال جديد — كل نوع يستدعي مساره الموجود، وحارس السيرفر يبقى الحَكَم.

/// نوع ما يُنشأ
enum AdminCreateKind: String, CaseIterable, Identifiable {
    case announcement, death, card, appUpdate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .announcement: return L10n.t("إعلان", "Announcement")
        case .death:        return L10n.t("إعلان وفاة", "Obituary")
        case .card:         return L10n.t("بطاقة تهنئة أو تعزية", "Greeting or condolence card")
        case .appUpdate:    return L10n.t("إعلان تحديث التطبيق", "App update notice")
        }
    }

    var note: String {
        switch self {
        case .announcement: return L10n.t("في الأخبار و/أو إشعار للأعضاء", "In News and/or a push")
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
        var list: [AdminCreateKind] = []
        if authVM.canSendNotifications { list.append(.announcement) }
        if authVM.isAdmin { list.append(.death) }
        if authVM.canModerate { list.append(.card) }
        if authVM.canSendNotifications { list.append(.appUpdate) }
        return list
    }
}

// MARK: - النافذة المستقلّة

/// يعرض «ماذا تنشئ؟» في نافذة فوق كل شيء (مثل `DeathAnnouncementPresenter`) — لا مُعدِّل عرض على «اليوم» ولا على صفحة القسم
@MainActor
enum AdminCreateWindow {
    private static var window: UIWindow?
    private static weak var previousKey: UIWindow?

    /// `start` النوع المفتوح أولاً (إن كان متاحاً للدور)، و`death` متوفى جاهز لـ«إعلان وفاة» (من «القادم»)
    static func open(_ start: AdminCreateKind = .announcement, death: DeathAnnouncementTarget? = nil,
                     authVM: AuthViewModel, newsVM: NewsViewModel, notificationVM: NotificationViewModel,
                     memberVM: MemberViewModel) {
        let allowed = AdminCreateKind.allowed(for: authVM)
        guard window == nil, !allowed.isEmpty, let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        previousKey = scene.windows.first(where: \.isKeyWindow)
        let root = AdminCreateRoot(allowed: allowed, start: allowed.contains(start) ? start : allowed[0],
                                   death: death, onClose: { close() })
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

/// جذر النافذة: المربّع بنوعه المختار، ومصمّم البطاقات فوقه بملء الشاشة. من لا يملك إلا البطاقة (المراقب والمشرف)
/// يفتح المصمّم مباشرة بلا مربّع اختيار
struct AdminCreateRoot: View {
    let allowed: [AdminCreateKind]
    let death: DeathAnnouncementTarget?
    let onClose: () -> Void

    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @State private var kind: AdminCreateKind
    @State private var cardOpen = false

    init(allowed: [AdminCreateKind], start: AdminCreateKind, death: DeathAnnouncementTarget?, onClose: @escaping () -> Void) {
        self.allowed = allowed
        self.death = death
        self.onClose = onClose
        _kind = State(initialValue: start)
    }

    private var cardOnly: Bool { allowed == [.card] }

    var body: some View {
        Group {
            if cardOnly {
                Color.clear
            } else {
                DSCenterPanel(onBackgroundTap: nil, hugsContent: true) { box }
            }
        }
        .fullScreenCover(isPresented: $cardOpen, onDismiss: { if cardOnly { onClose() } }) {
            NavigationStack { OccasionComposerView() }
                .environmentObject(authVM)
                .environmentObject(memberVM)
                .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .onAppear { if cardOnly { cardOpen = true } }
    }

    /// كل نوع منشئه الموجود خلف `AnyView` (نوع صغير لكل فرع)
    private var box: AnyView {
        let chooser = AnyView(AdminCreateTypePicker(kinds: allowed, selection: $kind))
        switch kind {
        case .announcement:
            return AnyView(AdminAnnounceComposer(chooser: chooser, onClose: onClose))
        case .death:
            return AnyView(AdminCreateDeathForm(chooser: chooser, preset: death, onClose: onClose))
        case .card:
            return AnyView(AdminCreateCardForm(chooser: chooser, onOpen: { cardOpen = true }, onClose: onClose))
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
            VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
                AdminIconSquare(symbol: kind.icon, tint: kind.tint, side: DS.Hub.miniIcon,
                                radius: DS.Hub.miniIconRadius, filled: true, glyph: DS.Glyph.md)
                Text(kind.title)
                    .dsFont(.hubButton)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(kind.note)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

/// يشرح البطاقة ثم «فتح مصمّم البطاقة» — المصمّم نفسه (`OccasionComposerView`) بملء الشاشة فوق المربّع
struct AdminCreateCardForm: View {
    let chooser: AnyView
    let onOpen: () -> Void
    let onClose: () -> Void

    private var tint: Color { DS.Color.actionNavy }

    var body: some View {
        DSComposer(
            title: L10n.t("ماذا تنشئ؟", "What to create?"),
            subtitle: AdminCreateKind.card.title,
            icon: AdminCreateKind.card.icon,
            tint: tint,
            actionTitle: L10n.t("فتح مصمّم البطاقة", "Open the card designer"),
            actionIcon: "paintbrush.pointed.fill",
            canSubmit: true,
            note: L10n.t("صورة تُحفظ في الصور أو تُشارك — لا تُرسل للأعضاء من هنا",
                         "An image to save or share — nothing is sent to members from here"),
            onSubmit: onOpen,
            onCancel: onClose
        ) {
            chooser
            DSComposerSection(title: L10n.t("الأنواع", "Kinds"), icon: "photo.on.rectangle.angled", tint: tint, index: 1) {
                row(icon: "gift.fill", title: L10n.t("تهنئة", "Congratulations"),
                    note: L10n.t("زواج، مولود، تخرّج… بصورة أو بدونها", "Wedding, newborn, graduation… with or without a photo"))
                row(icon: NewsTypeHelper.icon(for: "وفاة"), title: L10n.t("إعلان عزاء", "Condolence notice"),
                    note: L10n.t("التشييع والعزاء والدعاء", "Funeral, condolences and prayer"))
                row(icon: "hands.and.sparkles.fill", title: L10n.t("مشاركة عزاء", "Shared condolence"),
                    note: L10n.t("بطاقة مواساة بلا صورة", "A sympathy card without a photo"))
            }
        }
    }

    private func row(icon: String, title: String, note: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: tint)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(note)
                    .dsFieldFont(.subtitle)
                    .foregroundColor(DS.Color.fieldValue)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .dsRowBox()
        .accessibilityElement(children: .combine)
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
