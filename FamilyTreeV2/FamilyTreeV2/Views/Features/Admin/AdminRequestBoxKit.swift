import SwiftUI

// MARK: - مربّع الطلب: القطع (إعادة تصميم الإدارة ٢٠٢٦-١١-٢٦، الوحدة U9 — spec C.3، mock 3)
//
// ورقة طويلة (`dsTallBox`) بمكدسها الخاص (`NavigationStack`)، من أعلى إلى أسفل:
//   صفّ التنقّل «إغلاق» · نوع الطلب (١٧ شبه عريض) · «⋯» (إدارة الطلب وحدها: عاجل · استلم/اترك · حذف الطلب)
//   ← سطر صاحب الطلب (صورة ٤٨ · الاسم ١٥ متوسط · «قبل ساعتين · من شجرة العائلة» ١٣ رمادي · «عاجل»)
//   ← بطاقة المراحل الأربع «وصل ← المختص ← الاعتماد ← التنفيذ» (Life360) وسطرها، أو «بانتظار قرارك» بلا مسار
//   ← «التفاصيل» صفوفاً (مربّع ٣٠ · العنوان ١٥ · القيمة ١٥ في الطرف · قلم/سهم) ← … ← «السجل» مطويّاً
//   ← الشريط السفلي: زرّان على الأكثر + «المزيد»، وسطر الخطأ/التنبيه فوقه.
// القطع هنا عرض فقط؛ القرار وصلاحياته ونداءاته في `AdminAllRequestsView` (منطقة U9)، والمنطق الخالص في
// `AdminRequestBoxLogic.swift`.

// MARK: المقاسات والنصوص

enum AdminRequestBoxMetrics {
    /// صورة صاحب الطلب ٤٨ (spec C.3 البند ٢)
    static let avatar: CGFloat = DS.Icon.tapTarget + DS.Spacing.xs
    /// نقطة المرحلة المنجزة/القادمة، وحلقة الحالية
    static let trackDot: CGFloat = DS.Spacing.md
    static let trackDotCurrent: CGFloat = DS.Spacing.lg
    static let trackLine: CGFloat = DS.Border.widthBold
    /// مكان الصورة المقترحة قبل تحميلها (كان ثابتاً خاصاً في `AdminAllRequestsView`)
    static let photoPlaceholder: CGFloat = 200
    /// ورقة واحدة في المرة: ما يُفتح فوق «الوارد» بعد نزول المربّع (حركة الورقة ~٠٫٣٥ ث)
    static let sheetHandoff: TimeInterval = 0.5
    /// المحتوى (أخبار، ديوانيات، مشاريع) يُخفى تفاؤلياً ثم يُكتب: أول إعادة جلب بعد هذه المهلة، والثانية بعد الأخرى
    static let contentSettle: TimeInterval = 1.2
    static let contentRecheck: TimeInterval = 1.5
}

enum AdminRequestBoxText {
    static let close = L10n.t("إغلاق", "Close")
    static let more = L10n.t("المزيد", "More")
    static let manage = L10n.t("إدارة الطلب", "Manage the request")
    static let details = L10n.t("التفاصيل", "Details")
    static let request = L10n.t("الطلب", "Request")
    static let waiting = L10n.t("بانتظار قرارك", "Awaiting your decision")
    static let log = L10n.t("السجل", "Log")
    static let backToInbox = L10n.t("العودة إلى الوارد", "Back to the inbox")
    static let slow = L10n.t("الرد يتأخر… ننتظر النتيجة قبل المتابعة.", "The answer is taking a while… waiting for the result.")
    static let urgent = L10n.t("عاجل", "Urgent")
    static let readOnly = L10n.t("للاطلاع فقط — لا يدخل هذا الطلب في صلاحياتك.", "View only — this request is outside your role.")
    static let deleteQuestion = L10n.t("حذف الطلب نهائياً؟", "Delete the request permanently?")
    static let deleteLine = L10n.t("يُحذف الطلب من قاعدة البيانات. لا يمكن التراجع.",
                                   "The request is removed from the database. This can't be undone.")
    static let deleteVerb = L10n.t("احذف الطلب", "Delete the request")
    static let cancel = L10n.t("إلغاء", "Cancel")

    /// «وصل» · «المختص» · «الاعتماد» · «التنفيذ» (spec A.11)
    static let stepTitles = [L10n.t("وصل", "Arrived"), L10n.t("المختص", "Specialist"),
                             L10n.t("الاعتماد", "Approval"), L10n.t("التنفيذ", "Carry out")]

    static func nextRequest(_ name: String) -> String {
        L10n.t("الطلب التالي: \(name)", "Next request: \(name)")
    }

    /// «عالجه بدر (المدير) من قبل: قُبل» — أو «عولج هذا الطلب من قبل»
    static func handledBy(_ name: String?, decision: String?) -> String {
        let who = name.map { L10n.t("عالجه \($0) من قبل", "Already handled by \($0)") }
            ?? L10n.t("عولج هذا الطلب من قبل", "This request was already handled")
        guard let decision, !decision.isEmpty else { return who + L10n.t("، ننتقل للتالي.", " — moving on.") }
        return who + ": " + decision
    }

    /// «4 خطوات» بالعدّ العربي
    static func steps(_ n: Int) -> String {
        switch n {
        case 0: return L10n.t("لا خطوات", "No steps")
        case 1: return L10n.t("خطوة واحدة", "1 step")
        case 2: return L10n.t("خطوتان", "2 steps")
        case 3...10: return L10n.t("\(n) خطوات", "\(n) steps")
        default: return L10n.t("\(n) خطوة", "\(n) steps")
        }
    }

    /// قارئ الشاشة: «المرحلة: الاعتماد، الثالثة من أربع»
    static func stageSpoken(_ step: Int) -> String {
        let ordinals = [L10n.t("الأولى", "first"), L10n.t("الثانية", "second"), L10n.t("الثالثة", "third"),
                        L10n.t("الرابعة", "fourth")]
        let i = min(max(step, 0), stepTitles.count - 1)
        return L10n.t("المرحلة: \(stepTitles[i])، \(ordinals[i]) من أربع", "Stage: \(stepTitles[i]), \(ordinals[i]) of four")
    }
}

// MARK: - البيئة: شكل صفوف التفاصيل

private struct AdminRequestBoxRowsKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// داخل مربّع الطلب الجديد: صفوف التفاصيل بشكل spec A.6 داخل بطاقة واحدة. خارجه (المربّع المعالَج في «المنجز»)
    /// تبقى الصفوف بشكلها السابق (`dsRowBox`)
    var adminRequestBoxRows: Bool {
        get { self[AdminRequestBoxRowsKey.self] }
        set { self[AdminRequestBoxRowsKey.self] = newValue }
    }
}

// MARK: - أزرار نصّية (صفّ التنقّل)

/// زرّ نصّي كحلي بمساحة لمس ٤٤ (كأزرار ورقة الفلاتر)
struct AdminBoxTextButtonStyle: ButtonStyle {
    var role: DS.TextRole = .callout
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dsSection) private var section

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .dsFont(role)
            .foregroundColor(isEnabled ? (section?.ink ?? DS.Color.primary) : DS.Color.textTertiary)
            .opacity(configuration.isPressed ? DS.Opacity.disabled : 1)
            .frame(minWidth: DS.Icon.tapTarget, minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
            .animation(DS.Hub.rowPressAnimation, value: configuration.isPressed)
    }
}

// MARK: - صفّ التنقّل: «إغلاق» · النوع · «⋯»

/// بند في «⋯» — إدارة الطلب وحدها (spec C.3 البند ١)
struct AdminBoxMenuItem: Identifiable {
    let id: String
    let title: String
    let icon: String
    var destructive: Bool = false
    var isEnabled: Bool = true
    let run: () -> Void
}

struct AdminRequestBoxNavRow: View {
    let title: String
    var menu: [AdminBoxMenuItem] = []
    /// «إغلاق» معطّل أثناء قرار يُرسل (لا يُغلق المربّع على طلب لم يُعرف مصيره)
    var closeEnabled: Bool = true
    /// «إغلاق» — أو «إخفاء التفاصيل» داخل مربّع الطلب بالمنتصف (`AdminRequestPanel`)
    var closeTitle: String = AdminRequestBoxText.close
    let onClose: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dsSection) private var section

    var body: some View {
        let close = Button(closeTitle, action: onClose)
            .buttonStyle(AdminBoxTextButtonStyle(role: .callout))
            .disabled(!closeEnabled)
        let heading = Text(title)
            .dsFont(.emptyTitle)
            .foregroundColor(DS.Color.textPrimary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    HStack { close; Spacer(minLength: DS.Spacing.sm); menuButton }
                    heading.frame(maxWidth: .infinity)
                }
            } else {
                ZStack {
                    heading.padding(.horizontal, DS.Icon.tapTarget * 2)
                    HStack { close; Spacer(minLength: DS.Spacing.sm); menuButton }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        // تحت مقبض الورقة
        .padding(.top, DS.Spacing.md)
    }

    @ViewBuilder
    private var menuButton: some View {
        if menu.isEmpty {
            Color.clear.frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget).accessibilityHidden(true)
        } else {
            let plain = menu.filter { !$0.destructive }
            let red = menu.filter(\.destructive)
            Menu {
                ForEach(plain) { item in
                    Button(action: item.run) { Label(item.title, systemImage: item.icon) }
                        .disabled(!item.isEnabled)
                }
                if !red.isEmpty {
                    Divider()
                    ForEach(red) { item in
                        Button(role: .destructive, action: item.run) { Label(item.title, systemImage: item.icon) }
                            .disabled(!item.isEnabled)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .dsGlyph(DS.Glyph.lg, weight: .semibold)
                    .foregroundColor(section?.ink ?? DS.Color.primary)
                    .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(AdminRequestBoxText.manage)
        }
    }
}

// MARK: - سطر صاحب الطلب

struct AdminRequestTitleBlock: View {
    let name: String
    /// «قبل ساعتين · من شجرة العائلة»
    var line: String? = nil
    var avatarURL: String? = nil
    var urgent: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            DSMemberAvatar(name: name, avatarUrl: avatarURL, size: AdminRequestBoxMetrics.avatar,
                           roleColor: AppSection.admin.ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(name)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let line, !line.isEmpty {
                    Text(line)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.Spacing.sm)
            if urgent {
                AdminStatePill(title: AdminRequestBoxText.urgent, tone: .error, icon: "flame.fill")
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - المراحل الأربع (spec A.11 — Life360)

/// «وصل ← المختص ← الاعتماد ← التنفيذ»: المنجز نقطة كحلية ممتلئة، الحالية حلقة كحلية وعنوانها متوسط، القادم رمادي.
/// يتبع اتجاه اللغة (الأولى على اليمين بالعربية)
struct AdminRequestStageTrack: View {
    /// ٠…٣ (`AdminRequestBoxLogic.trackStep`)
    let current: Int
    var titles: [String] = AdminRequestBoxText.stepTitles

    var body: some View {
        let now = min(max(current, 0), titles.count - 1)
        return HStack(alignment: .top, spacing: 0) {
            ForEach(titles.indices, id: \.self) { i in
                VStack(spacing: DS.Spacing.xsm) {
                    ZStack {
                        HStack(spacing: 0) {
                            line(visible: i > 0, done: i <= now)
                            line(visible: i < titles.count - 1, done: i < now)
                        }
                        dot(i, now: now)
                    }
                    .frame(height: AdminRequestBoxMetrics.trackDotCurrent)
                    Text(titles[i])
                        .dsFont(i == now ? .chip : .subtitle)
                        .foregroundColor(i == now ? DS.Color.textPrimary : (i < now ? DS.Color.textSecondary : DS.Color.textTertiary))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AdminRequestBoxText.stageSpoken(now))
    }

    private func line(visible: Bool, done: Bool) -> some View {
        Rectangle()
            .fill(visible ? (done ? DS.Color.primaryFill : DS.Chart.inkTrack) : Color.clear)
            .frame(height: AdminRequestBoxMetrics.trackLine)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func dot(_ i: Int, now: Int) -> some View {
        if i < now {
            Circle()
                .fill(DS.Color.primaryFill)
                .frame(width: AdminRequestBoxMetrics.trackDot, height: AdminRequestBoxMetrics.trackDot)
        } else if i == now {
            Circle()
                .fill(DS.Color.cardBackground)
                .overlay(Circle().strokeBorder(DS.Color.primaryFill, lineWidth: AdminRequestBoxMetrics.trackLine))
                .frame(width: AdminRequestBoxMetrics.trackDotCurrent, height: AdminRequestBoxMetrics.trackDotCurrent)
        } else {
            Circle()
                .fill(DS.Color.cardBackground)
                .overlay(Circle().strokeBorder(DS.Color.textTertiary, lineWidth: DS.Border.width))
                .frame(width: AdminRequestBoxMetrics.trackDot, height: AdminRequestBoxMetrics.trackDot)
        }
    }
}

/// بطاقة المراحل: الشريط وسطره («أوصى المراقب بالقبول · عندك منذ 3 ساعات · متبقٍّ 21 ساعة»). بلا مسار: «بانتظار قرارك»
struct AdminRequestStageCard: View {
    /// nil = «مسار الموافقات» مطفأ
    let step: Int?
    let note: String
    /// المهلة تجاوزت — السطر بلون التنبيه
    var late: Bool = false

    var body: some View {
        Group {
            if let step {
                VStack(spacing: DS.Spacing.md) {
                    AdminRequestStageTrack(current: step)
                    if !note.isEmpty {
                        Text(note)
                            .dsFont(.subtitle)
                            .foregroundColor(late ? DS.Color.warning : DS.Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                HStack(spacing: DS.Spacing.md) {
                    AdminIconSquare(symbol: "hourglass", tint: DS.Color.accent, filled: false)
                    Text(note.isEmpty ? AdminRequestBoxText.waiting : note)
                        .dsFont(.body)
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: DS.Hub.rowMinHeight)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
        .adminCard()
    }
}

// MARK: - قسم: عنوان ثم بطاقته (spec A.4/A.5)

struct AdminBoxSection<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: title, trailing: trailing)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - صفوف التفاصيل (تتبع `adminRequestBoxRows`)

/// صفّ معلومة: داخل المربّع الجديد `[مربّع ٣٠ ممتلئ][العنوان ١٥] … [القيمة ١٥ رمادية][واتساب/قلم/سهم]` (spec A.6)،
/// وخارجه الشكل السابق (أيقونة الحقل + العنوان فوق القيمة في صندوق)
struct AdminDetailInfoRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    /// رقم هاتف ← «واتساب» في الطرف
    var whatsapp: String? = nil
    /// قلم ← مربّع التعديل الموجود (الاسم/الرقم — spec C.3 البند ٤)
    var edit: (() -> Void)? = nil
    /// سهم ← يفتح الشخص داخل مكدس المربّع
    var open: (() -> Void)? = nil
    /// القيمة رابط اتصال (رقم الهاتف) — بلون التواصل
    var tel: URL? = nil
    @Environment(\.adminRequestBoxRows) private var boxRows
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if boxRows { newRow } else { oldRow }
    }

    // الشكل الجديد

    @ViewBuilder
    private var newRow: some View {
        if let open {
            Button(action: open) { newFace(chevron: true) }
                .buttonStyle(AdminRowPressStyle())
                .accessibilityHint(L10n.t("يفتح بياناته", "Opens their details"))
        } else {
            newFace(chevron: false)
        }
    }

    private func newFace(chevron: Bool) -> some View {
        let plain = Text(value)
            .dsFont(.body)
            .foregroundColor(tel == nil ? DS.Color.textSecondary : DS.Color.sea)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
        let valueText = AdminDetailTelValue(text: plain, tel: tel)
        return HStack(alignment: .center, spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: icon, tint: color, filled: true)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    labelText
                    valueText.multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            } else {
                labelText.layoutPriority(1)
                Spacer(minLength: DS.Spacing.sm)
                valueText
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
            }
            if let url = KuwaitPhone.whatsappURL(whatsapp) {
                AdminDetailWhatsAppButton(url: url)
            }
            if let edit {
                Button(action: edit) {
                    Image(systemName: "pencil")
                        .dsGlyph(DS.Glyph.md, weight: .semibold)
                        .foregroundColor(DS.Color.accent)
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel(L10n.t("تعديل \(label)", "Edit \(label)"))
            }
            if chevron { DSChevron() }
        }
        .padding(.vertical, DS.Spacing.xsm)
        .frame(maxWidth: .infinity, minHeight: DS.Hub.rowMinHeight, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: (edit != nil || whatsapp != nil || tel != nil) ? .contain : .combine)
    }

    private var labelText: some View {
        Text(label)
            .dsFont(.body)
            .foregroundColor(DS.Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // الشكل السابق (المربّع المعالَج)

    private var oldRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: icon, tint: color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(label)
                        .dsFieldFont(.label)
                        .foregroundColor(DS.Color.fieldLabel)
                    // القيمة أوضح من العنوان: بوزن أثقل ولون النص الأساسي («خلها واضحة اكثر» ٢٠٢٦-١١-٢٤)
                    Text(value)
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if let url = KuwaitPhone.whatsappURL(whatsapp) {
                AdminDetailWhatsAppButton(url: url)
            }
        }
        // يمتدّ لارتفاع جاره حين يكونان جنب بعض — المربّعان بطول واحد
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .dsRowBox()
    }
}

/// القيمة نفسها رابط اتصال حين يُمرَّر رقم (الهاتف) — لمس ٤٤
private struct AdminDetailTelValue<Label: View>: View {
    let text: Label
    let tel: URL?

    var body: some View {
        if let tel {
            Button { UIApplication.shared.open(tel) } label: {
                text.frame(minHeight: DS.Icon.tapTarget).contentShape(Rectangle())
            }
            .buttonStyle(DSPressStyle())
            .accessibilityHint(L10n.t("اتصال", "Call"))
        } else {
            text
        }
    }
}

/// زرّ «واتساب» — حبّة مدمجة خضراء بنصّها، يفتح المحادثة مع الرقم
struct AdminDetailWhatsAppButton: View {
    let url: URL

    var body: some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "message.fill").dsGlyph(DSButtonSize.compact.glyph)
                Text(L10n.t("واتساب", "WhatsApp"))
            }
            .modifier(DSButtonFace(size: .compact, tint: DS.Color.success, fullWidth: false))
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(L10n.t("مراسلة عبر واتساب", "Message on WhatsApp"))
    }
}

/// نصّ طويل: العنوان ثم المحتوى بعرض الصفّ
struct AdminDetailLongTextRow: View {
    let icon: String
    let label: String
    let text: String
    @Environment(\.adminRequestBoxRows) private var boxRows

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: boxRows ? DS.Spacing.md : DS.Spacing.sm) {
                if boxRows {
                    AdminIconSquare(symbol: icon, tint: AppSection.admin.ink, filled: true)
                } else {
                    DSFieldIcon(name: icon, tint: AppSection.admin.ink)
                        .accessibilityHidden(true)
                }
                Text(label)
                    .modifier(AdminDetailLabelFont(boxRows: boxRows))
                Spacer(minLength: 0)
            }
            Text(text)
                .modifier(AdminDetailValueFont(boxRows: boxRows))
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .modifier(AdminDetailRowFrame(boxRows: boxRows))
        .accessibilityElement(children: .combine)
    }
}

/// «قبل ← بعد»: القديم مشطوب ← الجديد (تغيير الاسم/الرقم)
struct AdminDetailComparisonRow: View {
    let oldLabel: String
    let oldValue: String
    let newLabel: String
    let newValue: String
    let icon: String
    var whatsapp: String? = nil
    @Environment(\.adminRequestBoxRows) private var boxRows

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: boxRows ? DS.Spacing.md : DS.Spacing.sm) {
                iconView(tint: boxRows ? DS.Color.textTertiary : DS.Color.error)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(oldLabel)
                        .modifier(AdminDetailLabelFont(boxRows: boxRows, muted: true))
                    Text(oldValue)
                        .modifier(AdminDetailValueFont(boxRows: boxRows))
                        .foregroundColor(boxRows ? DS.Color.textTertiary : DS.Color.fieldValue)
                        .strikethrough(true, color: DS.Color.error.opacity(DS.Opacity.disabled))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            // سهم تحت عمود الأيقونات: من القديم إلى الجديد
            Image(systemName: "arrow.down")
                .dsGlyph(DS.Glyph.smCompact)
                .foregroundColor(DS.Color.textTertiary)
                .frame(width: boxRows ? DS.Hub.iconSquare : DS.Icon.row)
                .accessibilityHidden(true)
            HStack(spacing: boxRows ? DS.Spacing.md : DS.Spacing.sm) {
                iconView(tint: DS.Color.success)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(newLabel)
                        .modifier(AdminDetailLabelFont(boxRows: boxRows))
                        .foregroundColor(DS.Color.success)
                    Text(newValue)
                        .modifier(AdminDetailValueFont(boxRows: boxRows, strong: true))
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                if let url = KuwaitPhone.whatsappURL(whatsapp) {
                    AdminDetailWhatsAppButton(url: url)
                }
            }
        }
        .modifier(AdminDetailRowFrame(boxRows: boxRows))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func iconView(tint: Color) -> some View {
        if boxRows {
            AdminIconSquare(symbol: icon, tint: tint, filled: true)
        } else {
            DSFieldIcon(name: icon, tint: tint).accessibilityHidden(true)
        }
    }
}

/// رابط يُفتح (واتساب، موقع، سوشال)
struct AdminDetailLinkRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    let url: URL
    @Environment(\.adminRequestBoxRows) private var boxRows

    var body: some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: boxRows ? DS.Spacing.md : DS.Spacing.sm) {
                if boxRows {
                    AdminIconSquare(symbol: icon, tint: color, filled: true)
                    Text(label).dsFont(.body).foregroundColor(DS.Color.textPrimary)
                    Spacer(minLength: DS.Spacing.sm)
                    Text(value)
                        .dsFont(.body)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                } else {
                    DSFieldIcon(name: icon, tint: color).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(label).dsFieldFont(.label).foregroundColor(DS.Color.fieldLabel)
                        Text(value).dsFieldFont(.fieldValue).foregroundColor(DS.Color.fieldValue).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                Image(systemName: "arrow.up.forward")
                    .dsGlyph(DS.Glyph.sm)
                    .foregroundColor(color.dsReadableGlyph)
                    .accessibilityHidden(true)
            }
            .modifier(AdminDetailRowFrame(boxRows: boxRows))
            .contentShape(Rectangle())
        }
        .buttonStyle(boxRows ? AnyButtonStyle(AdminRowPressStyle()) : AnyButtonStyle(DSScaleButtonStyle()))
    }
}

/// صورة كبيرة (الصورة المقترحة) — بعرض الصفّ
struct AdminDetailPhotoRow: View {
    let url: URL
    @Environment(\.adminRequestBoxRows) private var boxRows

    var body: some View {
        CachedAsyncImage(url: url) { img in
            img.resizable().scaledToFit()
        } placeholder: {
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background)
                .frame(height: AdminRequestBoxMetrics.photoPlaceholder)
                .overlay(DSPageLoader(size: DS.Icon.rowLarge, fillsSpace: false))
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke), lineWidth: DS.Border.width)
        )
        .padding(.vertical, boxRows ? DS.Spacing.sm : 0)
        // صورة محتوى (المقترحة/الجديدة) — اسم واضح بدل «صورة» بلا وصف
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("الصورة", "Photo"))
        .accessibilityAddTraits(.isImage)
    }
}

/// غلاف `ButtonStyle` بنوع واحد (لاختيار الضغطة بحسب الشكل)
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

private struct AdminDetailLabelFont: ViewModifier {
    let boxRows: Bool
    var muted: Bool = false

    func body(content: Content) -> some View {
        if boxRows {
            content.dsFont(.subtitle).foregroundColor(muted ? DS.Color.textTertiary : DS.Color.textSecondary)
        } else {
            content.dsFieldFont(.label).foregroundColor(DS.Color.fieldLabel)
        }
    }
}

private struct AdminDetailValueFont: ViewModifier {
    let boxRows: Bool
    var strong: Bool = false

    func body(content: Content) -> some View {
        if boxRows {
            content.dsFont(strong ? .rowTitle : .body)
        } else {
            content.dsFieldFont(strong ? .fieldValueStrong : .fieldValue)
        }
    }
}

/// إطار الصفّ: داخل البطاقة حشوة عمودية فقط (الفاصل من البطاقة)، وخارجها صندوق الصفّ
private struct AdminDetailRowFrame: ViewModifier {
    let boxRows: Bool

    func body(content: Content) -> some View {
        if boxRows {
            content
                .padding(.vertical, DS.Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: DS.Hub.rowMinHeight, alignment: .leading)
        } else {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsRowBox()
        }
    }
}

// MARK: - الشريط السفلي (spec C.3 البند ٨): زرّان + «المزيد»، وسطر فوقه

/// قرار أو إجراء في الشريط — `style` يحدّد وجهه
struct AdminBoxAction: Identifiable {
    /// `approve` = «موافقة» الخضراء في المربّع المختصر (`AdminRequestPanelSummary`)
    enum Style { case primary, approve, reject, plain }
    let id: String
    let title: String
    var icon: String? = nil
    var style: Style = .plain
    var isEnabled: Bool = true
    let run: () -> Void
}

/// سطر فوق الشريط: خطأ (أحمر)، أو من عالجه (رمادي)، أو «الرد يتأخر» (تنبيه)
struct AdminBoxNotice: Equatable {
    enum Kind { case error, info, slow }
    let kind: Kind
    let text: String
}

struct AdminRequestDecisionBar: View {
    /// زرّان على الأكثر (`AdminRequestBoxLogic.barSplit`)
    let buttons: [AdminBoxAction]
    /// «المزيد» — قائمة أصلية
    var more: [AdminBoxAction] = []
    /// الإجراء الجاري (دوّارته الصغيرة داخل زرّه)
    var busyId: String? = nil
    /// معطّل: قرار يُرسل، أو الانتقال للتالي قبل ٠٫٨ ث وتحميله
    var locked: Bool = false
    var notice: AdminBoxNotice? = nil
    /// سطر بلا أزرار (للاطلاع، طلبك، عند غيرك)
    var quietLine: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if let notice { noticeLine(notice) }
            if let quietLine, buttons.isEmpty, more.isEmpty {
                HStack(alignment: .top, spacing: DS.Spacing.xsm) {
                    Image(systemName: "eye")
                        .dsGlyph(DS.Glyph.md)
                        .foregroundColor(DS.Color.textTertiary)
                        .accessibilityHidden(true)
                    Text(quietLine)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            if !buttons.isEmpty || !more.isEmpty {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: DS.Spacing.sm))
                    : AnyLayout(HStackLayout(spacing: DS.Spacing.sm))
                layout {
                    ForEach(buttons) { action in
                        Button(action: action.run) {
                            AdminBoxActionFace(title: action.title, icon: action.icon, style: action.style,
                                               busy: busyId == action.id, fills: true)
                        }
                        .buttonStyle(DSPressStyle())
                        .disabled(locked || !action.isEnabled)
                    }
                    if !more.isEmpty { moreMenu }
                }
                .opacity(locked ? DSActionFill.disabledOpacity : 1)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Hub.background.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { AdminRowDivider() }
        .animation(DS.Anim.snappy, value: notice)
    }

    private var moreMenu: some View {
        Menu {
            ForEach(more) { action in
                if let icon = action.icon {
                    Button(role: action.style == .reject ? .destructive : nil, action: action.run) {
                        Label(action.title, systemImage: icon)
                    }
                    .disabled(!action.isEnabled)
                } else {
                    Button(action.title, role: action.style == .reject ? .destructive : nil, action: action.run)
                        .disabled(!action.isEnabled)
                }
            }
        } label: {
            AdminBoxActionFace(title: AdminRequestBoxText.more, icon: nil, style: .plain, busy: false,
                               fills: typeSize.isAccessibilitySize)
        }
        .disabled(locked)
        .accessibilityLabel(AdminRequestBoxText.more)
    }

    private func noticeLine(_ notice: AdminBoxNotice) -> some View {
        let icon: String
        let tint: Color
        switch notice.kind {
        case .error: icon = "exclamationmark.circle.fill"; tint = DS.Color.error
        case .info: icon = "person.crop.circle.badge.checkmark"; tint = DS.Color.textSecondary
        case .slow: icon = "hourglass"; tint = DS.Color.warning
        }
        return HStack(alignment: .top, spacing: DS.Spacing.xsm) {
            Image(systemName: icon)
                .dsGlyph(DS.Glyph.md)
                .foregroundColor(tint)
                .accessibilityHidden(true)
            Text(notice.text)
                .dsFont(.subtitle)
                .foregroundColor(notice.kind == .info ? DS.Color.textSecondary : tint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }
}

/// وجه زرّ الشريط: كحلي ممتلئ (القرار) · إطار أحمر («رفض») · إطار رمادي («المزيد»، الثانوي) — ٤٤ بشكل الزرّ الواحد
struct AdminBoxActionFace: View {
    let title: String
    var icon: String? = nil
    var style: AdminBoxAction.Style = .plain
    var busy: Bool = false
    /// يتمدّد بعرض نصيبه من الشريط (القرار والرفض)؛ «المزيد» على قدر نصّه
    var fills: Bool = true

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            if busy {
                ProgressView()
                    .tint(ink)
                    .scaleEffect(DS.Spinner.buttonScale)
            } else if let icon {
                Image(dsSymbol: icon).dsGlyph(DSButtonSize.regular.glyph)
            }
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(DSBox.buttonLabelMinScale)
        }
        .dsFont(.button)
        .foregroundColor(ink)
        .padding(.horizontal, DS.Spacing.lg)
        .frame(maxWidth: fills ? .infinity : nil, minHeight: DSBox.buttonHeight)
        .background(DSBox.buttonShape.fill(fill))
        .overlay(DSBox.buttonShape.strokeBorder(stroke, lineWidth: DS.Border.width))
        .contentShape(DSBox.buttonShape)
    }

    private var ink: Color {
        switch style {
        case .primary, .approve: return DS.Color.textOnPrimary
        case .reject: return DS.Color.error
        case .plain: return DS.Color.textPrimary
        }
    }

    private var fill: Color {
        switch style {
        case .primary: return DS.Color.primaryFill
        case .approve: return DS.Color.successFill
        case .reject, .plain: return DS.Color.cardBackground
        }
    }

    private var stroke: Color {
        switch style {
        case .primary, .approve: return Color.clear
        case .reject: return DS.Color.error
        case .plain: return DS.Hub.frameStroke
        }
    }
}

// MARK: - النهاية: «كل الطلبات عولجت»

struct AdminRequestBoxEndState: View {
    let title: String

    var body: some View {
        DSEmptyView(title,
                    message: L10n.t("لا طلب آخر ينتظر هنا. ما عولج في مربّع «المنجزة» أعلى «الوارد».",
                                    "Nothing else is waiting here. «Done» is at the end of the inbox."),
                    icon: "checkmark.circle", tint: DS.Color.success, style: .card)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xxl)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - صفحة تُدفع داخل المربّع

/// إطار الصفحة المدفوعة داخل مكدس المربّع: «‹ الطلب» ثم العنوان ثم المحتوى يتمرّر
struct AdminBoxPage<Content: View>: View {
    let title: String
    var backTitle: String = AdminRequestBoxText.request
    let onBack: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "chevron.backward").dsGlyph(DS.Glyph.md, weight: .semibold)
                    Text(backTitle)
                }
            }
            .buttonStyle(AdminBoxTextButtonStyle(role: .callout))
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .accessibilityLabel(L10n.t("رجوع إلى \(backTitle)", "Back to \(backTitle)"))
            Text(title)
                .dsFont(.emptyTitle)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.sm)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Hub.stackSpacing) {
                    content()
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DS.Hub.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}

// MARK: - صفحة الملاحظة (التوصية، الرفض، الإرجاع، سؤال العضو)

/// ما تطلبه صفحة الملاحظة — كل قرار يحتاج سبباً أو ملاحظة يمرّ منها، والتأكيد زرّها (spec A.14)
struct AdminBoxNoteSpec: Hashable {
    enum Purpose: String, Hashable {
        case recommendApprove, recommendReject, ask, approveNote, returnBack, reject, rejectFlow
    }
    let purpose: Purpose

    var title: String {
        switch purpose {
        case .recommendApprove: return L10n.t("التوصية بالقبول", "Recommend approval")
        case .recommendReject: return L10n.t("التوصية بالرفض", "Recommend rejection")
        case .ask: return L10n.t("اطلب معلومات من العضو", "Ask the member for info")
        case .approveNote: return L10n.t("اعتماد بملاحظة للمختص", "Approve with a note")
        case .returnBack: return L10n.t("إرجاع للمختص", "Return to the specialist")
        case .reject, .rejectFlow: return L10n.t("رفض الطلب؟", "Reject the request?")
        }
    }

    var label: String {
        switch purpose {
        case .recommendApprove: return L10n.t("ملاحظتك للمدير (اختياري)", "Your note for the manager (optional)")
        case .recommendReject: return L10n.t("سبب التوصية بالرفض — مطلوب", "Why you recommend rejection — required")
        case .ask: return L10n.t("سؤالك للعضو", "Your question")
        case .approveNote: return L10n.t("ملاحظتك للمختص", "Your note for the specialist")
        case .returnBack: return L10n.t("المطلوب من المختص — مطلوب", "What you need from the specialist — required")
        case .reject: return L10n.t("سبب الرفض (اختياري)", "Reason (optional)")
        case .rejectFlow: return L10n.t("سبب الرفض — مطلوب", "Reason — required")
        }
    }

    var placeholder: String {
        switch purpose {
        case .recommendApprove, .recommendReject: return L10n.t("رأيك للمدير", "Your view for the manager")
        case .ask: return L10n.t("مثلاً: أرفق صورة البطاقة", "e.g. attach a photo of the ID")
        case .approveNote, .returnBack: return L10n.t("ملاحظة للمختص", "A note for the specialist")
        case .reject, .rejectFlow: return L10n.t("يصل إلى صاحب الطلب مع الرفض", "Sent to the requester with the rejection")
        }
    }

    /// سطر يشرح ما يحدث بعد التأكيد
    var footnote: String {
        switch purpose {
        case .recommendApprove, .recommendReject: return L10n.t("يُرفع الطلب للمدير بتوصيتك.", "The request goes up to the manager with your recommendation.")
        case .ask: return L10n.t("يصل العضو إشعار بما تطلبه، ويرجع الطلب لك بعد ردّه.", "The member is notified; the request comes back to you after the reply.")
        case .approveNote: return L10n.t("«اعتماد» يرجّعه للمختص لينفّذه.", "«Approve» sends it back to the specialist to carry out.")
        case .returnBack: return L10n.t("يرجع الطلب للمختص بملاحظتك.", "The request goes back to the specialist with your note.")
        case .reject, .rejectFlow: return L10n.t("يُرفض الطلب ويبقى في السجل. لا يمكن التراجع.", "The request is rejected and kept in the log. This can't be undone.")
        }
    }

    var confirm: String {
        switch purpose {
        case .recommendApprove, .recommendReject: return L10n.t("رفع للمدير", "Send to the manager")
        case .ask: return L10n.t("أرسل للعضو", "Send to the member")
        case .approveNote: return L10n.t("اعتماد", "Approve")
        case .returnBack: return L10n.t("أرجعه للمختص", "Return it")
        case .reject, .rejectFlow: return L10n.t("ارفض الطلب", "Reject the request")
        }
    }

    var requiresNote: Bool {
        switch purpose {
        case .recommendReject, .returnBack, .rejectFlow: return true
        case .recommendApprove, .approveNote, .reject, .ask: return false
        }
    }

    var templates: [ApprovalTemplateKind] {
        switch purpose {
        case .recommendApprove: return [.recommend]
        case .recommendReject, .reject, .rejectFlow: return [.reject]
        case .ask: return [.info]
        case .approveNote: return [.note]
        case .returnBack: return [.returnBack]
        }
    }

    var isReject: Bool { purpose == .reject || purpose == .rejectFlow }
}

struct AdminBoxNotePage: View {
    let spec: AdminBoxNoteSpec
    @ObservedObject var adminRequestVM: AdminRequestViewModel
    @Binding var text: String
    @Binding var fields: Set<ApprovalInfoField>
    let onBack: () -> Void
    let onConfirm: () -> Void
    @State private var error: String?

    var body: some View {
        AdminBoxPage(title: spec.title, onBack: onBack) {
            if spec.purpose == .ask { askFields }
            ApprovalTemplateChips(adminRequestVM: adminRequestVM, kinds: spec.templates) { insert($0) }
            DSComposerField(icon: spec.isReject ? "xmark.bubble" : "text.bubble",
                            label: label,
                            placeholder: spec.placeholder,
                            text: $text,
                            tint: DS.Color.actionNavy,
                            multiline: true,
                            limit: 500)
            if let error {
                Text(error)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(spec.footnote)
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: confirm) {
                AdminBoxActionFace(title: spec.confirm, style: spec.isReject ? .reject : .primary)
            }
            .buttonStyle(DSPressStyle())
            .padding(.top, DS.Spacing.sm)
        }
        .task { await adminRequestVM.fetchApprovalTemplates() }
    }

    private var label: String {
        guard spec.purpose == .ask else { return spec.label }
        return fields.isEmpty ? L10n.t("سؤالك للعضو — مطلوب بلا اختيار", "Your question — required without a choice")
                              : L10n.t("سؤالك للعضو (اختياري)", "Your question (optional)")
    }

    /// الناقص: شرائح متعددة الاختيار (رقم الهاتف، الميلاد، الوفاة، الاسم الكامل)
    private var askFields: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(L10n.t("اختر الناقص", "Choose what's missing"))
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textSecondary)
            DSChipFlow(spacing: DS.Spacing.sm, lineSpacing: DS.Spacing.sm) {
                ForEach(ApprovalInfoField.askable) { field in
                    let on = fields.contains(field)
                    DSChipButton(field.title, icon: on ? "checkmark" : field.icon, tint: field.tint, isSelected: on, size: .small) {
                        withAnimation(DS.Anim.snappy) {
                            if on { fields.remove(field) } else { fields.insert(field) }
                        }
                        error = nil
                    }
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private func insert(_ body: String) {
        let current = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = current.isEmpty ? body : current + "\n" + body
        error = nil
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func confirm() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if spec.purpose == .ask, fields.isEmpty, trimmed.isEmpty {
            error = L10n.t("اختر الناقص أو اكتب سؤالك للعضو.", "Choose what's missing or write your question.")
            return
        }
        if spec.requiresNote, trimmed.isEmpty {
            error = spec.isReject ? L10n.t("اكتب سبب الرفض، وسيصل إلى العضو.", "Write the reason — it goes to the member.")
                                  : L10n.t("اكتب الملاحظة أولاً.", "Write the note first.")
            return
        }
        onConfirm()
    }
}

// MARK: - «السجل» مطويّاً (spec C.3 البند ٧)

struct AdminRequestLogCard: View {
    let steps: [DSPathStep]
    /// السجلّ لم يصل بعد
    var loading: Bool = false
    @State private var open = false

    var body: some View {
        AdminSectionCard(title: AdminRequestBoxText.log, isOpen: $open,
                         summary: loading ? AdminStoreHealthText.placeholder : AdminRequestBoxText.steps(steps.count)) {
            if loading {
                Text(AdminStoreHealthText.placeholder)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .redacted(reason: .placeholder)
            } else {
                DSPathSteps(steps: steps)
            }
        }
    }
}

// MARK: - معاينة (DEBUG): القطع وحدها بأسماء وهمية

#if DEBUG
/// مربّع طلب بأسماء وهمية — للتصوير والمعاينة فقط (يمكن ربطه بـ`-uiPreviewRequestTrail` في `AdminTrailPreview`)
struct AdminRequestBoxShowcase: View {
    var step: Int? = 2
    var notice: AdminBoxNotice? = nil
    var ended = false

    var body: some View {
        VStack(spacing: 0) {
            AdminRequestBoxNavRow(title: "طلب إضافة ابن", menu: [
                AdminBoxMenuItem(id: "urgent", title: "اجعله عاجلاً", icon: "flame") {},
                AdminBoxMenuItem(id: "claim", title: "استلم الطلب", icon: "hand.raised") {},
                AdminBoxMenuItem(id: "delete", title: "حذف الطلب", icon: "trash", destructive: true) {},
            ]) {}
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Hub.stackSpacing) {
                    if ended {
                        AdminRequestBoxEndState(title: AdminRequestBoxLogic.endTitle(othersOutsideFilter: false,
                                                                                     arabic: L10n.isArabic))
                    } else {
                        AdminRequestTitleBlock(name: "سالم أحمد يوسف", line: "قبل ساعتين · من شجرة العائلة", urgent: true)
                        AdminRequestStageCard(step: step, note: step == nil ? "" : "أوصى المراقب بالقبول · عندك منذ 3 ساعات")
                        AdminBoxSection(title: AdminRequestBoxText.details) {
                            AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                                AdminDetailInfoRow(icon: "person.fill", label: "الابن", value: "محمد سالم أحمد",
                                                   color: DS.Color.palm, edit: {})
                                AdminDetailInfoRow(icon: "arrow.triangle.branch", label: "الأب", value: "سالم أحمد يوسف",
                                                   color: DS.Color.palm, open: {})
                                AdminDetailInfoRow(icon: "calendar", label: "الميلاد", value: "02/11/2026", color: DS.Color.primary)
                            }
                        }
                        AdminRequestLogCard(steps: [DSPathStep(icon: "paperplane.fill", title: "أُرسل", lines: ["بواسطة: سالم"])])
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
            }
            AdminRequestDecisionBar(
                buttons: ended ? [AdminBoxAction(id: "back", title: AdminRequestBoxText.backToInbox, style: .primary) {}]
                    : [AdminBoxAction(id: "approve", title: "اعتماد", style: .primary) {},
                       AdminBoxAction(id: "reject", title: "رفض", style: .reject) {}],
                more: ended ? [] : [AdminBoxAction(id: "now", title: "اعتماد وتنفيذ الحين", icon: "bolt") {}],
                notice: notice)
        }
        .environment(\.adminRequestBoxRows, true)
        .background(DS.Hub.background.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
    }
}

struct AdminRequestBoxShowcase_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AdminRequestBoxShowcase()
            AdminRequestBoxShowcase(step: nil, notice: AdminBoxNotice(kind: .error,
                                    text: "تعذّر التنفيذ: الرقم مستخدم من عضو آخر — لم يُطبَّق شيء."))
            AdminRequestBoxShowcase(ended: true)
        }
    }
}
#endif
