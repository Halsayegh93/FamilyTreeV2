import SwiftUI

// MARK: - قطع بطاقة العضو في الشجرة «أ» (اعتمدها المالك ٢٠٢٦-١١-٢٧)
//
// الورقة الطويلة (`dsTallBox`) من الأعلى: «إغلاق» ذهبي على الكحلي ← الرأس: الصورة (المرأة دائرة بحرفها بلا صورة) والاسم كاملاً
// عنواناً، وسطر الحقائق «41 سنة · 3 أبناء»، وزرّ القرابة بالكلمات («ابن خالك ‹»، والبعيدة سطر ثانٍ «يلتقي معك في جدّكما …»)
// يفتح طريق القرابة في الشجرة، ثم «اتصال/واتساب» للرقم الظاهر لك فقط ← «طلبك عنه» فوق المجموعات ← المجموعات مطويّة بسطر
// ملخّصها (`AdminSectionCard(isOpen:summary:)` نفسها في بطاقة الإدارة) ← شريط ثابت: زرّ واحد حسب الدور و«المزيد».
// «طلب تعديل» صفحة داخل الورقة: شبكة مربّعات `AdminHubTile` (الأيقونة بلون عائلتها والاسم وسطر صادق تحته)، وكل مربّع يفتح
// النموذج الموجود. «طلبك عنه» يفتح طلبك داخل الورقة مع «سحب الطلب».
// القواعد في `TreeMemberCardLogic` (tests/admin-redesign/T1). حارس المكدس: كل قطعة نوع مستقل والورقة تضعها خلف `AnyView`.

typealias TreeCardTile = TreeMemberCardLogic.Tile

/// مسارات الورقة الداخلية — المكدس داخل الورقة نفسها (الرجوع يعود للبطاقة)
enum TreeCardRoute: Hashable {
    case tiles
    case request(UUID)
}

// MARK: - الرأس

struct TreeCardHeader: View {
    let member: FamilyMember
    let facts: String
    let kinship: TreeMemberCardLogic.Kinship
    let actions: [AdminMemberHeaderAction]
    /// طلب حذف معلّق منك عليه (§11)
    let deletionPending: Bool
    let onKinship: () -> Void
    let onAction: (AdminMemberHeaderAction) -> Void
    let onPhoto: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            TreeCardAvatar(member: member, onTap: onPhoto)
            VStack(spacing: DS.Spacing.xs) {
                Text(verbatim: member.displayFullName.isEmpty ? L10n.t("بلا اسم", "No name") : member.displayFullName)
                    .dsFont(.hubTitle)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !facts.isEmpty {
                    Text(verbatim: facts)
                        .dsFont(.subtitle)
                        .monospacedDigit()
                        .foregroundColor(DS.Hub.onBandMuted)
                        .multilineTextAlignment(.center)
                }
                if deletionPending {
                    AdminMemberBandTag(text: SelfRemovalText.pendingChip, highlighted: true)
                }
            }
            TreeCardKinshipButton(kinship: kinship, action: onKinship)
            if !actions.isEmpty {
                Rectangle().fill(DS.Hub.bandHairline).frame(height: DS.Border.width)
                AdminMemberHeaderActions(actions: actions, perform: onAction)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(DS.Hub.band)
    }
}

/// الصورة الكبيرة: صورة الرجل، أو دائرة زجاجية بحرفه الأول (المرأة دائماً بلا صورة)؛ رمادية للمتوفى. الضغط يكبّرها
struct TreeCardAvatar: View {
    let member: FamilyMember
    let onTap: () -> Void

    private var url: URL? {
        guard TreeMemberCardLogic.showsPhoto(isFemale: member.isFemale),
              let raw = member.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    var body: some View {
        let face = ZStack {
            Circle().fill(member.isFemale ? DS.Color.female.opacity(DS.Opacity.tintStroke) : DS.Hub.glass)
            if let url {
                CachedAsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { initial }
            } else {
                initial
            }
        }
        .frame(width: DS.Hub.treeCardAvatar, height: DS.Hub.treeCardAvatar)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(DS.Hub.glassLine, lineWidth: DS.Border.widthBold))
        .grayscale(member.isDeceased == true ? 1 : 0)

        if url != nil {
            Button(action: onTap) { face }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(Text(L10n.t("معاينة الصورة", "Preview photo")))
        } else {
            face.accessibilityHidden(true)
        }
    }

    private var initial: some View {
        Image(systemName: "person.fill")
            .dsGlyph(DS.Glyph.xxl)
            .foregroundColor(DS.Color.textOnPrimary)
    }
}

/// القرابة داخل الزرّ: «ابن خالك ‹» بإطار ذهبي على الكحلي — يفتح طريق القرابة في الشجرة. بلا عقدة لك: سطر مقفول يقول لماذا
struct TreeCardKinshipButton: View {
    let kinship: TreeMemberCardLogic.Kinship
    let action: () -> Void

    var body: some View {
        switch kinship {
        case .button(let title, let line):
            Button(action: action) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .dsGlyph(DS.Glyph.md)
                    VStack(spacing: DS.Spacing.xxs) {
                        Text(verbatim: title)
                            .dsFont(.button)
                            .multilineTextAlignment(.center)
                        if let line {
                            Text(verbatim: line)
                                .dsFont(.caption)
                                .foregroundColor(DS.Hub.onBandMuted)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                        .dsGlyph(DS.Glyph.sm, weight: .semibold)
                }
                .foregroundColor(DS.Color.accentLight)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
                .frame(minHeight: DS.Icon.tapTarget)
                .background(Capsule().fill(DS.Hub.rolePillFill))
                .overlay(Capsule().strokeBorder(DS.Hub.rolePillStroke, lineWidth: DS.Border.width))
                .contentShape(Capsule())
            }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityHint(Text(L10n.t("يعرض طريق القرابة في الشجرة", "Shows the kinship path in the tree")))
        case .locked:
            Label(TreeMemberCardLogic.lockedKinshipText, systemImage: "lock")
                .dsFont(.caption)
                .foregroundColor(DS.Hub.onBandMuted)
                .padding(.horizontal, DS.Spacing.md)
                .frame(minHeight: DS.Icon.tapTarget)
                .overlay(Capsule().strokeBorder(DS.Hub.glassLine, lineWidth: DS.Border.width))
        case .mine:
            Text(TreeMemberCardLogic.mineText)
                .dsFont(.caption)
                .foregroundColor(DS.Color.accentLight)
        case .none:
            EmptyView()
        }
    }
}

// MARK: - «طلبك عنه» — فوق المجموعات، طلباتك أنت فقط

struct TreeCardMyRequests: View {
    let requests: [AdminRequest]
    let female: Bool
    /// على بطاقتك «طلبك» (م٤)
    var isSelf = false
    let open: (AdminRequest) -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(requests) { request in
                Button { open(request) } label: { row(request) }
                    .buttonStyle(DSPressStyle())
                    .accessibilityHint(Text(L10n.t("يفتح طلبك، وتقدر تسحبه", "Opens your request; you can withdraw it")))
            }
        }
    }

    private func row(_ request: AdminRequest) -> some View {
        HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: "tray", tint: DS.Color.accent, filled: true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(TreeMemberCardLogic.myRequestTitle(female: female, isSelf: isSelf))
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                Text(verbatim: TreeCardRequestText.kind(request) + " · " + L10n.t("بانتظار الإدارة", "Waiting for the admins"))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Spacing.sm)
            DSChevron()
        }
        .padding(DS.Hub.cardPadding)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
        .background(RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous)
            .fill(DS.Color.cardBackgroundSoft))
        .overlay(RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous)
            .strokeBorder(DS.Color.accentLight.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// نصوص الطلب: نوعه بكلماته (طلب شجرة النساء بنوعه الحقيقي)، ومتى أُرسل، وما طُلب
enum TreeCardRequestText {
    static func kind(_ r: AdminRequest) -> String {
        guard let action = r.treeEditPayload?.displayAction else {
            return L10n.t("طلب", "Request")
        }
        return L10n.t(action.arabicLabel, action.englishLabel)
    }

    static func sent(_ r: AdminRequest) -> String? { DateHelper.displayDateTime(r.createdAt) }

    static func value(_ r: AdminRequest) -> String? {
        guard let p = r.treeEditPayload else { return r.newValue }
        let raw = p.newName ?? p.newMemberName ?? p.newBirthDate ?? p.deathDate ?? p.women?.name
        guard let raw, !raw.isEmpty else { return nil }
        return DateHelper.displayDate(raw) ?? raw
    }
}

// MARK: - المجموعات المطويّة (كلها مطويّة أول مرة)

/// «العائلة»: الأب ثم الأبناء — الضغط على أحدهم يفتح بطاقته والشجرة تتبعه
struct TreeCardFamilyGroup: View {
    let summary: String
    let father: FamilyMember?
    let children: [FamilyMember]
    let ink: Color
    let open: (FamilyMember) -> Void
    @State private var isOpen = false

    var body: some View {
        AdminSectionCard(title: L10n.t("العائلة", "Family"), isOpen: $isOpen, summary: summary) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                if let father {
                    DSFamilyPersonRow(role: L10n.t("الأب", "Father"), tint: ink, name: father.displayFullName,
                                      detail: DSMemberAge.detail(father), onTap: { open(father) }) {
                        TreeCardSmallAvatar(member: father, size: DSMemberKit.parentAvatar, ink: ink)
                    }
                }
                if !children.isEmpty {
                    DSFamilyChildrenBlock(groups: [.init(id: "children", title: nil, tint: ink, members: children)],
                                          avatar: { TreeCardSmallAvatar(member: $0, size: DSMemberKit.childAvatar, ink: ink) },
                                          onTap: open)
                }
            }
        }
    }
}

struct TreeCardSmallAvatar: View {
    let member: FamilyMember
    let size: CGFloat
    let ink: Color

    var body: some View {
        ZStack {
            Circle().fill(ink.opacity(DS.Opacity.tintFill))
            if !member.isFemale, let raw = member.avatarUrl, let url = URL(string: raw) {
                CachedAsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
            } else {
                Text(verbatim: String(member.firstName.prefix(1)))
                    .dsFont(.rowTitle)
                    .foregroundColor(ink)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .grayscale(member.isDeceased == true ? 1 : 0)
        .accessibilityHidden(true)
    }
}

/// «البيانات»: الميلاد والوفاة (المتوفى بلا تاريخ: «متوفى» فقط)
struct TreeCardDataGroup: View {
    let summary: String
    /// nil = غير مسجّل؛ «مخفي» حين أخفاه صاحبه عنك
    let birth: String?
    let birthHidden: Bool
    let deceased: Bool
    let death: String?
    let female: Bool
    @State private var isOpen = false

    var body: some View {
        AdminSectionCard(title: L10n.t("البيانات", "Details"), isOpen: $isOpen, summary: summary) {
            AdminRowsCardBody {
                AdminMemberFactRow(icon: "calendar", tint: DS.Color.primary, title: L10n.t("الميلاد", "Birth"),
                                   value: birthHidden ? L10n.t("مخفي", "Hidden") : birth,
                                   valueIsNumber: birth != nil && !birthHidden)
                if deceased {
                    AdminMemberFactRow(icon: "moon", tint: DS.Color.deceased, title: L10n.t("الوفاة", "Death"),
                                       value: death ?? (female ? L10n.t("متوفاة", "Deceased") : L10n.t("متوفى", "Deceased")),
                                       valueIsNumber: death != nil)
                }
            }
        }
    }
}

/// «التواصل»: صفّ الرقم وحده (الاتصال والواتساب في الرأس — ت١)، ويظهر فقط حين يحقّ لك رؤية الرقم
struct TreeCardContactGroup: View {
    let phone: String
    let female: Bool
    let tap: () -> Void
    @State private var isOpen = false

    var body: some View {
        let display = KuwaitPhone.display(phone)
        AdminSectionCard(title: L10n.t("التواصل", "Contact"), isOpen: $isOpen,
                         summary: TreeMemberCardLogic.contactSummary(female: female,
                                                                     masked: TreeMemberCardLogic.maskedPhone(display))) {
            AdminRowsCardBody {
                AdminMemberFactRow(icon: "phone", tint: DS.Color.sea,
                                   title: female ? L10n.t("رقمها", "Her number") : L10n.t("رقمه", "His number"),
                                   value: display, valueIsNumber: true, action: tap,
                                   actionHint: L10n.t("اتصال أو واتساب", "Call or WhatsApp"))
            }
        }
    }
}

/// «السيرة»: أحداثها بالسنة، و«حذف السيرة» للإدارة ولصاحبها
struct TreeCardBioGroup: View {
    let stations: [FamilyMember.BioStation]
    let canDelete: Bool
    let delete: () -> Void
    @State private var isOpen = false

    private var summary: String {
        let n = stations.count
        guard L10n.isArabic else { return "\(n) entries" }
        switch n {
        case 1: return "حدث واحد"
        case 2: return "حدثان"
        case 3...10: return "\(n) أحداث"
        default: return "\(n) حدثاً"
        }
    }

    var body: some View {
        AdminSectionCard(title: L10n.t("السيرة", "Biography"), isOpen: $isOpen, summary: summary) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                ForEach(stations) { station in
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        if let year = station.year, !year.isEmpty {
                            Text(verbatim: year)
                                .dsFont(.caption)
                                .monospacedDigit()
                                .foregroundColor(DS.Color.accent)
                        }
                        Text(station.title)
                            .dsFont(.rowTitle)
                            .foregroundColor(DS.Color.textPrimary)
                        if !station.details.isEmpty {
                            Text(station.details)
                                .dsFont(.body)
                                .foregroundColor(DS.Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if canDelete {
                    DSButton(L10n.t("حذف السيرة", "Delete Biography"), icon: "trash", role: .destructive, action: delete)
                }
            }
        }
    }
}

// MARK: - رأس الصفحات الداخلية («طلب تعديل»، «طلبك عنه»)

struct TreeCardPageHeader: View {
    let back: String
    let title: String
    let subtitle: String
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Button(action: onBack) {
                HStack(spacing: DS.Spacing.xxs) {
                    Image(systemName: L10n.isArabic ? "chevron.right" : "chevron.left")
                        .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    Text(verbatim: back).dsFont(.button)
                }
                .foregroundColor(DS.Color.accentLight)
                .frame(minHeight: DS.Icon.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressStyle())
            .accessibilityLabel(Text(L10n.t("رجوع", "Back")))
            Text(title)
                .dsFont(.hubTitle)
                .foregroundColor(DS.Color.textOnPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: subtitle)
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.accentLight)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.xl)
        .padding(.bottom, DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Hub.band.ignoresSafeArea(edges: .top))
    }
}

// MARK: - «طلب تعديل» — شبكة المربّعات

struct TreeCardTilesPage: View {
    let back: String
    let title: String
    let subtitle: String
    /// المرأة: «اسمي وميلادي» بلا «صورتي» (م٣)
    var female = false
    let note: String?
    let tiles: [TreeCardTile]
    let pending: Set<TreeMemberCardLogic.TileKind>
    let onBack: () -> Void
    let pick: (TreeCardTile) -> Void

    var body: some View {
        VStack(spacing: 0) {
            TreeCardPageHeader(back: back, title: title, subtitle: subtitle, onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Hub.cardGap) {
                    if let note {
                        DSNoteCard(note, icon: "person.2")
                    }
                    AdminTileGrid(count: tiles.count) {
                        ForEach(Array(tiles.enumerated()), id: \.element.kind) { i, tile in
                            let waiting = pending.contains(tile.kind)
                            Button { pick(tile) } label: {
                                AdminHubTile(icon: tile.kind.icon, fill: Self.fill(tile.kind), title: tile.kind.title(female: female),
                                             caption: waiting ? TreeMemberCardLogic.pendingTileText : tile.honesty.text,
                                             captionTint: Self.captionTint(tile.honesty, waiting: waiting),
                                             reservesCaption: true, index: i,
                                             hint: waiting ? L10n.t("يفتح طلبك نفسه", "Opens your request") : nil)
                            }
                            .buttonStyle(AdminTilePressStyle())
                        }
                    }
                }
                .padding(DS.Spacing.lg)
            }
        }
        .background(DS.Hub.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    /// الأيقونة بلون عائلتها: البيانات كحلي · الوفاة والحذف رمادي · الصورة عنابي · الإضافة أخضر · الرقم بترولي
    static func fill(_ kind: TreeMemberCardLogic.TileKind) -> Color {
        switch kind {
        case .name, .birth, .myData, .childData: return DS.Color.navyFill
        case .death, .deathDate, .remove: return DS.Color.slateFill
        case .photo: return DS.Color.saduFill
        case .addSon, .addMyChild: return DS.Color.palmFill
        case .myPhone: return DS.Color.seaFill
        }
    }

    static func captionTint(_ honesty: TreeMemberCardLogic.Honesty, waiting: Bool) -> Color {
        if waiting { return DS.Color.accent }
        switch honesty {
        case .savedNow, .firstThreeNow: return DS.Color.success
        case .adminDoes: return DS.Color.warning
        case .afterApproval, .withCode: return DS.Color.textTertiary
        }
    }
}

// MARK: - «طلبك عنه» — الطلب داخل الورقة مع «سحب الطلب»

struct TreeCardRequestPage: View {
    let back: String
    let female: Bool
    var isSelf = false
    let memberName: String
    let request: AdminRequest?
    let isWithdrawing: Bool
    let onBack: () -> Void
    let withdraw: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TreeCardPageHeader(back: back, title: TreeMemberCardLogic.myRequestTitle(female: female, isSelf: isSelf),
                               subtitle: TreeMemberCardLogic.requestSubtitle(name: memberName, isSelf: isSelf), onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Hub.cardGap) {
                    if let request {
                        AdminSectionCard {
                            AdminRowsCardBody {
                                AdminMemberFactRow(icon: "tray", tint: DS.Color.accent, title: TreeCardRequestText.kind(request),
                                                   subtitle: TreeCardRequestText.sent(request).map { L10n.t("أرسلته ", "Sent ") + $0 },
                                                   hidesValue: true)
                                if let value = TreeCardRequestText.value(request) {
                                    AdminMemberFactRow(icon: "pencil", tint: DS.Color.primary,
                                                       title: L10n.t("ما طلبته", "What you asked"), value: value)
                                }
                                AdminMemberFactRow(icon: "clock", tint: DS.Color.warning, title: L10n.t("الحالة", "Status"),
                                                   value: L10n.t("بانتظار الإدارة", "Waiting for the admins"))
                            }
                        }
                        DSNoteCard(L10n.t("ما دام ينتظر، تقدر تسحبه من هنا.", "While it waits, you can withdraw it here."),
                                   title: L10n.t("يُنفَّذ بعد موافقة الإدارة", "Applied after admin approval"),
                                   icon: "checkmark.shield")
                        DSButton(L10n.t("سحب الطلب", "Withdraw request"), icon: "trash", role: .destructive,
                                 isLoading: isWithdrawing, action: withdraw)
                        Text(L10n.t("يُحذف الطلب ولا يصل للإدارة.", "The request is deleted and won't reach the admins."))
                            .dsFont(.caption)
                            .foregroundColor(DS.Color.textTertiary)
                            .frame(maxWidth: .infinity)
                    } else {
                        // سُحب أو عولج بينما الصفحة مفتوحة
                        DSEmptyView(L10n.t("لم يعد الطلب ينتظر", "The request is no longer waiting"),
                                    message: L10n.t("سُحب أو عالجته الإدارة.", "It was withdrawn or handled."),
                                    icon: "tray", style: .card)
                    }
                }
                .padding(DS.Spacing.lg)
            }
        }
        .background(DS.Hub.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - الشريط الثابت أسفل الورقة

struct TreeCardFooter: View {
    let button: TreeMemberCardLogic.BottomButton
    /// «المزيد»: إبلاغ، حظر، إعلان وفاة — nil = لا شيء فيه (بطاقتك)
    let more: AnyView?
    let primary: () -> Void

    var body: some View {
        HStack(spacing: DSBox.buttonSpacing) {
            switch button {
            case .admin:
                DSLiveButton(button.title, icon: "checkmark.shield", tint: DSMemberKit.directTint, motion: .pop,
                             hint: L10n.t("يفتح بطاقة الإدارة لهذا العضو", "Opens the admin card for this member"),
                             action: primary)
            case .requestEdit, .editMine:
                DSButton(button.title, icon: "pencil", action: primary)
            case .none:
                EmptyView()
            }
            if let more { more }
        }
        .padding(.horizontal, DSBox.footerHorizontal)
        .padding(.top, DSBox.footerTop)
        .padding(.bottom, DSBox.footerBottom)
        .background(
            DS.Color.background
                .overlay(alignment: .top) {
                    Rectangle().fill(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke)).frame(height: DS.Border.width)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// «المزيد ⋯» — قائمة أصلية بالأفعال الثانوية
struct TreeCardMoreMenu: View {
    let canReport: Bool
    let canBlock: Bool
    let isBlocked: Bool
    let canAnnounceDeath: Bool
    let report: () -> Void
    let toggleBlock: () -> Void
    let announceDeath: () -> Void

    var isEmpty: Bool { !canReport && !canBlock && !canAnnounceDeath }

    var body: some View {
        Menu {
            if canAnnounceDeath {
                Button(action: announceDeath) {
                    Label(L10n.t("إعلان وفاة", "Death announcement"), systemImage: NewsTypeHelper.icon(for: "وفاة"))
                }
            }
            if canReport {
                Button(action: report) {
                    Label(L10n.t("إبلاغ", "Report"), systemImage: "exclamationmark.bubble")
                }
            }
            if canBlock {
                Button(role: isBlocked ? nil : .destructive, action: toggleBlock) {
                    Label(isBlocked ? L10n.t("إلغاء الحظر", "Unblock") : L10n.t("حظر", "Block"),
                          systemImage: isBlocked ? "hand.raised.slash" : "hand.raised")
                }
            }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "ellipsis").dsGlyph(DS.Glyph.md)
                Text(L10n.t("المزيد", "More")).dsFont(.button)
            }
            .foregroundColor(DS.Color.textPrimary)
            .padding(.horizontal, DS.Spacing.lg)
            .frame(minHeight: DSBox.buttonHeight)
            .background(DSBox.buttonShape.fill(DS.Color.cardBackgroundSoft))
            .overlay(DSBox.buttonShape.strokeBorder(DS.Color.cardBorder, lineWidth: DS.Border.width))
        }
        .fixedSize()
        .accessibilityLabel(Text(L10n.t("المزيد", "More")))
    }
}
