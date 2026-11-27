import SwiftUI

// MARK: - قطع ورقة العضو «أ3 ملف موجز وأفعال» (الوحدة V2-3، اختيار المالك ٢٠٢٦-١١-٢٦)
//
// V3 «ب»: الشارات تحت الاسم (`AdminMemberBandTag`)، والأزرار بلا إطار (رمز ذهبي ٢٢ واسمه تحته، لمس ٤٤).
// الرأس الكحلي المختصر: «إغلاق» ذهبي ثابت فوق، ثم الصورة ٥٦ والاسم كاملاً (يلتفّ بلا قصّ) و«الحالة · الفرع» ذهبياً،
// ثم حتى أربعة أزرار زجاجية بأسمائها تحتها («الملف الكامل» · «في الشجرة» · «اتصال» · «واتساب» — الأخيران للرقم الظاهر
// فقط، يُحذفان لا يُعتّمان)، ومن أحجام إمكانية الوصول شبكة ٢×٢ بالرمز والاسم في سطر.
// تحت الرأس: رقاقة كريمية لكل ناقص («⚠ تاريخ الوفاة غير مكتمل · أكمل ‹») تفتح مربّع إصلاحه، ثم الأقسام بعناوين عريضة
// وشريط رفيع في بدايتها (نمط «فرع حسن» في «العائلة»)، وآخرها «حذف العضو نهائياً» زرّ أحمر بإطار، وسطر القفل على ورقتك.
// المنطق (أيّ الأزرار، أيّ الرقاقات، الاسم الأول، القفل) في `AdminMemberSheetLogic` — يُفحص في tests/admin-redesign/V2c.
// حارس المكدس: كل قطعة نوع مستقل، والورقة تضعها خلف `AnyView`.

typealias AdminMemberHeaderAction = AdminMemberSheetLogic.HeaderAction

extension AdminMemberSheetLogic.HeaderAction {
    var title: String {
        switch self {
        case .fullProfile: return L10n.t("الملف الكامل", "Full profile")
        case .tree:        return L10n.t("في الشجرة", "In the tree")
        case .call:        return L10n.t("اتصال", "Call")
        case .whatsapp:    return L10n.t("واتساب", "WhatsApp")
        }
    }

    var symbol: String {
        switch self {
        case .fullProfile: return "pencil"
        case .tree:        return "tree"
        case .call:        return "phone"
        case .whatsapp:    return "message"
        }
    }

    var hint: String {
        switch self {
        case .fullProfile: return L10n.t("يفتح كل بياناته للتعديل", "Opens all their details to edit")
        case .tree:        return L10n.t("يفتح الشجرة على هذا العضو", "Opens the tree on this member")
        case .call:        return L10n.t("يتصل برقمه", "Calls their number")
        case .whatsapp:    return L10n.t("يفتح واتساب برقمه", "Opens WhatsApp with their number")
        }
    }
}

extension AdminMemberSheetLogic.Missing {
    /// النقص نفسه في نموذج «العائلة» (نفس `rawValue`)
    var gap: AdminMemberGap? { AdminMemberGap(rawValue: rawValue) }
    var problem: AdminMemberProblem? { AdminMemberProblem(rawValue: rawValue) }

    var title: String {
        if let gap { return AdminMemberFix.title(gap) }
        if let problem { return AdminMemberFix.title(problem) }
        return ""
    }

    var verb: String {
        if let gap { return AdminMemberFix.verb(gap) }
        if let problem { return AdminMemberFix.verb(problem) }
        return ""
    }
}

// MARK: - «إغلاق» — ثابت فوق المحتوى على الكحلي

/// F4 (فحص المدير على المحاكي ٢٠٢٦-١١-٢٦: لمسة «إغلاق» لا تغلق، السحب وحده يغلق): كان الزرّ يبدأ ٨ نقاط تحت حافة
/// الورقة — داخل شريط مقبض السحب (`presentationDragIndicator`) الذي يأخذ اللمسات أعلى الورقة، فتضيع لمسة النصف
/// الأعلى. الآن الزرّ يبدأ تحت ذلك الشريط (`DS.Spacing.xl`)، ومنطقة لمسه ٤٤ على الأقل وتمتدّ حتى حافة الورقة، وفوق
/// المحتوى المتمرّر (`zIndex` في الورقة)
struct AdminMemberCloseBar: View {
    let close: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: close) {
                Text(L10n.t("إغلاق", "Close"))
                    .dsFont(.button)
                    .foregroundColor(DS.Color.accentLight)
                    .padding(.horizontal, DS.Spacing.lg)
                    .frame(minWidth: DS.Icon.tapTarget + DS.Spacing.lg, minHeight: DS.Icon.tapTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DSPressStyle())
            .accessibilityHint(Text(L10n.t("يغلق بيانات العضو", "Closes the member details")))
            Spacer(minLength: 0)
        }
        .padding(.top, DS.Spacing.xl)
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth)
        .frame(maxWidth: .infinity)
        .background(DS.Hub.band.ignoresSafeArea(edges: .top))
    }
}

/// أرضية الورقة خلف التمرير: كحلي في النصف الأعلى (السحب فوق الرأس لا يكشف أبيض) وأبيض في الأسفل. بلا رأس (العضو
/// غير موجود) أبيض كلها
struct AdminMemberSheetBackdrop: View {
    var band: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            if band { DS.Hub.band }
            DS.Hub.background
        }
        .ignoresSafeArea()
    }
}

// MARK: - الرأس الكحلي

struct AdminMemberSheetHeader: View {
    let member: FamilyMember
    let facts: AdminMemberSheetFacts
    let branch: String?
    /// V3: شارة الصلة على الرأس — «ابن بنت» / «من خارج العائلة» (nil لمن من العائلة)
    var lineageTag: String? = nil
    let actions: [AdminMemberHeaderAction]
    let perform: (AdminMemberHeaderAction) -> Void

    private var name: String {
        member.displayFullName.isEmpty ? L10n.t("بلا اسم", "No name") : member.displayFullName
    }

    private var role: String? {
        switch member.role {
        case .owner: return L10n.t("المالك", "Owner")
        case .admin, .monitor, .supervisor: return member.roleName
        default: return nil
        }
    }

    /// للقارئ الصوتي: «عضو مسجّل · فرع حسن · ابن بنت · المالك»
    private var line: String {
        let status = facts.status?.title ?? L10n.t("جارٍ التحقق…", "Checking…")
        return [status, branch, lineageTag, role].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Hub.stackSpacing) {
            HStack(alignment: .center, spacing: DS.Spacing.md) {
                AdminMemberHeaderAvatar(member: member)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(verbatim: name)
                        .dsFont(.statValue)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    // V3: شارات الحال — الحالة الرسمية (✓ للمسجّل)، الفرع، الصلة، الدور
                    DSChipFlow(spacing: DS.Spacing.xs, lineSpacing: DS.Spacing.xs) {
                        AdminMemberBandTag(text: facts.status?.title ?? L10n.t("جارٍ التحقق…", "Checking…"),
                                           icon: facts.status == .registered ? "checkmark" : nil)
                            .redacted(reason: facts.status == nil ? .placeholder : [])
                        if let branch { AdminMemberBandTag(text: branch) }
                        if let lineageTag { AdminMemberBandTag(text: lineageTag, highlighted: true) }
                        if let role { AdminMemberBandTag(text: role) }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(name)، \(line)"))
                Spacer(minLength: 0)
            }
            if !actions.isEmpty {
                AdminMemberHeaderActions(actions: actions, perform: perform)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.xs)
        .padding(.bottom, DS.Spacing.lg)
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth)
        .frame(maxWidth: .infinity)
        .background(DS.Hub.band)
    }
}

/// الصورة ٥٦ على الكحلي: الصورة، أو الحرف الأول أبيض على دائرة زجاجية (لا صور للإناث — طلب المالك ٢٠٢٦-١١-٢٤).
/// رمادية للمتوفى
struct AdminMemberHeaderAvatar: View {
    let member: FamilyMember

    private var url: URL? {
        guard !member.isFemale, let raw = member.avatarUrl, !AdminMemberFacts.isBlank(raw) else { return nil }
        return URL(string: raw)
    }

    var body: some View {
        ZStack {
            Circle().fill(DS.Hub.glass)
            if let url {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initial
                }
            } else {
                initial
            }
        }
        .frame(width: DS.Hub.memberAvatar, height: DS.Hub.memberAvatar)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(DS.Hub.glassLine, lineWidth: DS.Border.width))
        .grayscale(member.isDeceased == true ? 1 : 0)
        .accessibilityHidden(true)
    }

    private var initial: some View {
        Text(verbatim: String(member.fullName.trimmingCharacters(in: .whitespaces).prefix(1)))
            .dsFont(.hubKPI)
            .foregroundColor(DS.Color.textOnPrimary)
    }
}

/// صفّ الأزرار: أربعة أعمدة متساوية (الأقل يبدأ من الطرف البادئ بعرض الربع) — مربّع زجاجي ٥٦×٥٢ واسمه تحته؛
/// من أحجام إمكانية الوصول شبكة ٢×٢ والرمز والاسم في سطر واحد. اللمس العمود كله (≥ ٤٤)
struct AdminMemberHeaderActions: View {
    let actions: [AdminMemberHeaderAction]
    let perform: (AdminMemberHeaderAction) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let large = typeSize.isAccessibilitySize
        let columns = AdminMemberSheetLogic.actionColumns(accessibilitySize: large)
        let rows = AdminMemberSheetLogic.actionRows(count: actions.count, accessibilitySize: large)
        VStack(spacing: DS.Spacing.sm) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(alignment: .top, spacing: large ? DS.Spacing.sm : DS.Hub.memberActionGap) {
                    ForEach(rows[r], id: \.self) { i in
                        button(actions[i], large: large)
                            .frame(maxWidth: .infinity)
                    }
                    // الخانات الفارغة تبقي عرض العمود ربعاً (أو نصفاً) فيبدأ الصفّ الناقص من الطرف البادئ
                    ForEach(rows[r].count..<columns, id: \.self) { _ in
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: 0)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func button(_ action: AdminMemberHeaderAction, large: Bool) -> some View {
        Button { perform(action) } label: {
            if large { tile(action) } else { column(action) }
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(action.title))
        .accessibilityHint(Text(action.hint))
        .accessibilityAddTraits(.isButton)
    }

    /// V3 (طلب المالك): بلا إطار — رمز ذهبي صغير (٢٢) واسمه تحته، ومساحة لمس ٤٤ غير مرئية
    private func column(_ action: AdminMemberHeaderAction) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            Image(dsSymbol: action.symbol)
                .dsGlyph(DS.Glyph.xxl, weight: .regular)
                .foregroundColor(DS.Color.accentLight)
            Text(action.title)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textOnPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
        .contentShape(Rectangle())
    }

    /// من أحجام إمكانية الوصول: الرمز واسمه في سطر، بلا إطار، ولمس ٤٤
    private func tile(_ action: AdminMemberHeaderAction) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(dsSymbol: action.symbol)
                .dsGlyph(DS.Glyph.lg, weight: .medium)
                .foregroundColor(DS.Color.accentLight)
            Text(action.title)
                .dsFont(.button)
                .foregroundColor(DS.Color.textOnPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
        .contentShape(Rectangle())
    }
}

/// شارة على الكحلي: كبسولة زجاجية بنصّ أبيض (والصلة «ابن بنت»/«من خارج العائلة» بذهبي خافت)
struct AdminMemberBandTag: View {
    let text: String
    var icon: String? = nil
    var highlighted: Bool = false

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            if let icon {
                Image(systemName: icon)
                    .dsGlyph(DS.Glyph.xs, weight: .bold)
                    .foregroundColor(DS.Color.accentLight)
            }
            Text(verbatim: text)
                .dsFont(.caption)
                .foregroundColor(highlighted ? DS.Color.accentLight : DS.Color.textOnPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xxs)
        .background(Capsule().fill(highlighted ? DS.Hub.rolePillFill : DS.Hub.glass))
        .overlay(Capsule().strokeBorder(DS.Hub.glassLine, lineWidth: DS.Border.width))
    }
}

// MARK: - «أكمل الناقص» — رقاقة لكل ناقص

/// رقاقات كريمية تلتفّ تحت الرأس: «⚠ تاريخ الوفاة غير مكتمل · أكمل ‹» — الرقاقة كلها لمسة تفتح مربّع إصلاحها
/// (نفس المربّعات: `DeceasedDateBox`، الميلاد، الجنس، ربط الأب…). ما إصلاحه تأكيد (الإظهار، مسح الرقم المكرر)
/// دوّارة صغيرة مكان الفعل أثناء التنفيذ
struct AdminMemberMissingChips: View {
    let items: [AdminMemberSheetLogic.Missing]
    /// الإصلاح الجاري (`AdminMemberConfirm.id`)
    let busy: String?
    let fix: (AdminMemberSheetLogic.Missing) -> Void

    var body: some View {
        DSChipFlow(spacing: DS.Spacing.sm, lineSpacing: DS.Spacing.sm) {
            ForEach(items, id: \.self) { item in chip(item) }
        }
    }

    private func isBusy(_ item: AdminMemberSheetLogic.Missing) -> Bool {
        guard let busy, let problem = item.problem, let confirm = AdminMemberFix.confirm(problem) else { return false }
        return busy == confirm.id
    }

    private func chip(_ item: AdminMemberSheetLogic.Missing) -> some View {
        let working = isBusy(item)
        return Button { fix(item) } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .dsGlyph(DS.Glyph.md, weight: .semibold)
                    .foregroundColor(DS.Color.warning)
                Text(item.title)
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if working {
                    ProgressView()
                        .scaleEffect(DS.Spinner.chipScale)
                        .tint(DS.Color.warning)
                } else {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(item.verb)
                            .dsFont(.sectionTitle)
                        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                            .dsGlyph(DS.Glyph.xs, weight: .semibold)
                    }
                    .foregroundColor(DS.Color.warning)
                }
            }
            .padding(.leading, DS.Spacing.md)
            .padding(.trailing, DS.Spacing.smd)
            .padding(.vertical, DS.Spacing.xsm)
            .frame(minHeight: DS.Icon.tapTarget)
            .background(RoundedRectangle(cornerRadius: DS.Hub.memberMissingRadius, style: .continuous)
                .fill(DS.Hub.memberMissingFill))
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .disabled(working)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.title))
        .accessibilityHint(Text(item.verb))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - عنوان القسم بشريطه (نمط «فرع حسن»)

/// «البيانات» (كحلي) · «النسب» (أخضر العائلة) · «الحساب» (بترولي): شريط ٤×٢٠ في البداية ثم العنوان ١٧ شبه عريض
struct AdminMemberSectionTitle: View {
    let title: String
    let bar: Color

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.smd) {
            RoundedRectangle(cornerRadius: DS.Hub.stripeWidth / 2, style: .continuous)
                .fill(bar)
                .frame(width: DS.Hub.stripeWidth, height: DS.Hub.familyBranchBar)
                .accessibilityHidden(true)
            Text(title)
                .dsFont(DS.Hub.familyBranchTitle)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.xxs)
    }
}

/// قسم الورقة: العنوان بشريطه ثم بطاقة صفوفه (الفاصل يبدأ بعد مربّع الأيقونة)
struct AdminMemberSheetSection<Rows: View>: View {
    let title: String
    let bar: Color
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminMemberSectionTitle(title: title, bar: bar)
            AdminRowsCard(dividerInset: AdminRowDivider.iconInset) { rows() }
        }
    }
}

// MARK: - «حذف العضو نهائياً» — آخر الورقة

/// زرّ أحمر بإطار بعرض الصفحة: يسأل قبل الحذف (spec A.14)، ودوّارة صغيرة أثناءه
struct AdminMemberDeleteButton: View {
    let busy: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Hub.memberDeleteRadius, style: .continuous)
        Button(action: action) {
            HStack(spacing: DS.Spacing.smd) {
                if busy {
                    ProgressView()
                        .scaleEffect(DS.Spinner.chipScale)
                        .tint(DS.Color.error)
                } else {
                    Image(systemName: "trash")
                        .dsGlyph(DS.Glyph.xl, weight: .medium)
                }
                Text(L10n.t("حذف العضو نهائياً", "Delete member permanently"))
                    .dsFont(.button)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundColor(DS.Color.error)
            .padding(.horizontal, DS.Hub.cardPadding)
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: DSBox.buttonHeightLarge)
            .background(shape.fill(DS.Color.cardBackground))
            .overlay(shape.strokeBorder(DS.Hub.memberDeleteStroke, lineWidth: DS.Border.width))
            .contentShape(shape)
        }
        .buttonStyle(DSPressStyle())
        .disabled(busy)
        .accessibilityHint(Text(L10n.t("يسأل قبل الحذف", "Asks before deleting")))
    }
}

// MARK: - سطر القفل

/// «هذا حسابك، وأنت المالك: لا إيقاف ولا منع رقم ولا حذف من هنا…» — ١٣ رمادي بقفل صغير، بلا بطاقة
struct AdminMemberLockNote: View {
    let note: AdminMemberSheetLogic.LockNote

    private var text: String {
        switch note {
        case .selfOwner:
            return L10n.t("هذا حسابك، وأنت المالك: لا إيقاف ولا منع رقم ولا حذف من هنا، ولا «طلب تغيير الصورة» لصورتك.",
                          "This is your account and you're the owner: no suspending, blocking or deleting here, and no photo-change request for your own photo.")
        case .selfAccount:
            return L10n.t("هذا حسابك: لا إيقاف ولا منع رقم ولا حذف من هنا، ولا «طلب تغيير الصورة» لصورتك.",
                          "This is your account: no suspending, blocking or deleting here, and no photo-change request for your own photo.")
        case .ownerAccount:
            return L10n.t("حساب المالك: لا إيقاف ولا منع رقم ولا حذف من هنا.",
                          "The owner's account: no suspending, blocking or deleting here.")
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
            Image(systemName: "lock")
                .dsGlyph(DS.Glyph.sm, weight: .medium)
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)
            Text(text)
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.xxs)
    }
}
