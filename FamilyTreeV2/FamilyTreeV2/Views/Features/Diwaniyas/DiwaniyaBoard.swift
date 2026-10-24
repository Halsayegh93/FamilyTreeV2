import SwiftUI
import UIKit

// MARK: - «أسبوع المجالس» — واجهة الترتيب الجديد للديوانيات
// (طلب المالك ٢٠٢٦-١٠-٢٤ «ابي ترتيب جديد للديوانيات ورني التنظيم الجديد — ابدعلي بالتصميم»)
//
// من الأعلى: بطاقة الأسبوع (تاريخ اليوم + حال الليلة + شريط ٧ أيام يبدأ باليوم، تحت كل يوم نقاط ذهبية بعدد
// مجالسه، والضغط على يوم يعرض مجالسه كلها) ← المجموعات بالترتيب (`DiwaniyaOrganizer`) ← بطاقة المجلس: صاحبه،
// الوقت والمنطقة، حال الليلة (مفتوحة الآن بشريط تقدّم / تبدأ بعد…)، حروف الأسبوع بأيامه مضاءة، وأزرار سريعة:
// اتصال، الموقع، مشاركة. لا شريط «ديوانيات/حسينيات» (طلب المالك): النوع وسم صغير على بطاقة الحسينية.
// الحركة: انزلاق اختيار اليوم وتبدّل القائمة باتجاهه، دخول البطاقات تباعاً، نبضة «الآن» على الساعة المشتركة —
// وكلها تسكن مع «تقليل الحركة».

/// مقاسات «أسبوع المجالس» — مكان واحد لهذا القسم
enum DSDiwaniya {
    /// دائرة رقم اليوم في شريط الأسبوع
    static let dayDisc: CGFloat = 32
    /// أصغر ما يصغر إليه اسم اليوم في خانته قبل أن يتحوّل الشريط إلى حروف
    static let dayNameScale: CGFloat = 0.8
    /// نقطة مجلس تحت اليوم (حتى `maxDots`)
    static let dayDot: CGFloat = 5
    static let maxDots = 3
    /// حرف اليوم في أسبوع البطاقة
    static let weekLetter: CGFloat = 22
    /// قرص الإجراء السريع (اتصال، الموقع، مشاركة) — بارتفاع الشريحة
    static var actionDisc: CGFloat { DSBox.chipHeight }
    /// شريط تقدّم المجلس المفتوح أسفل البطاقة
    static let liveBar: CGFloat = 3
    /// إزاحة القائمة حين يتبدّل اليوم (نحو اتجاه اليوم المختار)
    static let switchShift: CGFloat = DS.Spacing.xxxl
    /// فراغ أسفل القائمة حتى لا يغطي زرّ الإضافة العائم آخر بطاقة
    static var bottomClearance: CGFloat { DS.Icon.floatingButton + DS.Spacing.xxxl }
}

// MARK: - إجراءات البطاقة (من الصفحة)

/// ما يقدر عليه المستخدم وما تفعله أزرار البطاقة — تمرّره صفحة الديوانيات
struct DiwaniyaCardActions {
    let currentUserId: UUID?
    /// حذف أي ديوانية (`canDeleteDiwaniyas` — المالك والمدير)
    let canDeleteAny: Bool
    /// اعتماد/رفض المعلّقة (`isAdmin`)
    let canApprove: Bool
    let edit: (Diwaniya) -> Void
    let delete: (Diwaniya) -> Void
    let report: (Diwaniya) -> Void
    let approve: (Diwaniya) -> Void
    let reject: (Diwaniya) -> Void

    func isOwn(_ d: Diwaniya) -> Bool { currentUserId == d.ownerId }
    /// التعديل للإدارة ولصاحبها (كما كان)
    func canEdit(_ d: Diwaniya) -> Bool { canDeleteAny || isOwn(d) }
    /// الإبلاغ للجميع عن غير ديوانياتهم (سياسة Apple)
    func canReport(_ d: Diwaniya) -> Bool { !isOwn(d) }
}

// MARK: - محتوى الصفحة

/// بطاقة الأسبوع ثم المجموعات — يُعاد حسابه كل دقيقة (حال الليلة: مفتوحة/تبدأ/انتهت)
struct DiwaniyaBoard: View {
    /// الظاهرة للمستخدم (المعتمدة + المعلّقة المسموح له برؤيتها)
    let items: [Diwaniya]
    let actions: DiwaniyaCardActions
    let onRefresh: () async -> Void

    /// يوم مختار من الشريط (٠=السبت) — nil = الأسبوع كله
    @State private var selectedDay: Int?
    /// اتجاه تبدّل اليوم (لاحق = نحو نهاية الشريط)
    @State private var forward = true
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// [initialDay] = يفتح على يوم من الشريط (٠=السبت)، nil = الأسبوع كله
    init(items: [Diwaniya], actions: DiwaniyaCardActions, onRefresh: @escaping () async -> Void,
         initialDay: Int? = nil) {
        self.items = items
        self.actions = actions
        self.onRefresh = onRefresh
        _selectedDay = State(initialValue: initialDay)
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            board(DiwaniyaOrganizer(items: items, now: DiwaniyaClock.override ?? context.date))
        }
    }

    private func board(_ organizer: DiwaniyaOrganizer) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                DiwaniyaWeekHero(organizer: organizer, selectedDay: selectedDay) { day in
                    select(day, organizer: organizer)
                }
                .dsEntrance(delay: DSMotion.sectionsOnPage, y: DSMotion.rise, scale: DSMotion.riseScale)

                // القائمة تتبدّل مع اليوم المختار — طبقة واحدة فوق الأخرى أثناء الانتقال (بلا قفزة)
                ZStack(alignment: .top) {
                    DiwaniyaGroupsColumn(organizer: organizer, day: selectedDay, actions: actions,
                                         appeared: appeared) { select(nil, organizer: organizer) }
                        .id(selectedDay ?? -1)
                        .transition(switchTransition)
                }
            }
            .padding(DS.Spacing.lg)
            .padding(.bottom, DSDiwaniya.bottomClearance)
            .dsTabBarClearance()   // أفقياً: آخر بطاقة لا تختفي تحت شريط التبويبات العائم
            .onAppear {
                guard !appeared else { return }
                appeared = true
            }
        }
        .refreshable { await onRefresh() }
    }

    /// اختيار يوم (أو إلغاؤه): الاتجاه بحسب ترتيب الأيام من اليوم، ثم تبدّل القائمة بنابض هادئ
    private func select(_ day: Int?, organizer: DiwaniyaOrganizer) {
        guard day != selectedDay else { return }
        let rank: (Int?) -> Int = { $0.map { organizer.offset(of: $0) } ?? -1 }
        forward = rank(day) > rank(selectedDay)
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? DSMotion.fade : DS.Anim.smooth) { selectedDay = day }
    }

    /// القائمة الجديدة تدخل من جهة اليوم المختار والقديمة تخرج من الجهة الأخرى — «تقليل الحركة»: تلاشٍ فقط
    private var switchTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let shift = forward ? DSDiwaniya.switchShift : -DSDiwaniya.switchShift
        return .asymmetric(insertion: .diwaniyaShift(shift), removal: .diwaniyaShift(-shift))
    }
}

private struct DiwaniyaShift: ViewModifier {
    let x: CGFloat
    let opacity: Double
    func body(content: Content) -> some View { content.offset(x: x).opacity(opacity) }
}

private extension AnyTransition {
    /// إزاحة أفقية + تلاشٍ (موجب = نحو نهاية السطر، فتنعكس مع العربية)
    static func diwaniyaShift(_ x: CGFloat) -> AnyTransition {
        .modifier(active: DiwaniyaShift(x: x, opacity: 0), identity: DiwaniyaShift(x: 0, opacity: 1))
    }
}

// MARK: - المجموعات

/// مجموعات اليوم المختار أو الأسبوع كله، أو صفحة هادئة ليوم بلا مجالس
private struct DiwaniyaGroupsColumn: View {
    let organizer: DiwaniyaOrganizer
    let day: Int?
    let actions: DiwaniyaCardActions
    let appeared: Bool
    let onShowWeek: () -> Void

    var body: some View {
        let groups = organizer.groups(day: day)
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            if let day, groups.allSatisfy({ $0.entries.isEmpty }) {
                DiwaniyaDayEmpty(organizer: organizer, day: day, onShowWeek: onShowWeek)
            } else {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if !group.entries.isEmpty {
                        DiwaniyaGroupSection(group: group, actions: actions, appeared: appeared,
                                             cascadeBase: index)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// عنوان المجموعة (قرص + اسم اليوم + التاريخ/العدد) ثم بطاقاتها
private struct DiwaniyaGroupSection: View {
    let group: DiwaniyaGroup
    let actions: DiwaniyaCardActions
    let appeared: Bool
    let cascadeBase: Int

    private var tint: Color {
        switch group.role {
        case .pending: return DS.Color.warning
        case .closed, .unscheduled: return DS.Color.slate
        case .day: return AppSection.diwaniyas.ink
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSSectionTitle(title: group.title, icon: group.icon, tint: tint, trailing: group.trailing)
            AdaptiveLazyStack(spacing: DS.Spacing.md) {
                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                    DiwaniyaCard(entry: entry, actions: actions)
                        .dsCardCascade(cascadeBase + index, appeared: appeared)
                }
            }
        }
    }
}

/// يوم بلا مجالس: صفحة هادئة + أقرب يوم فيه مجلس + الرجوع للأسبوع
private struct DiwaniyaDayEmpty: View {
    let organizer: DiwaniyaOrganizer
    let day: Int
    let onShowWeek: () -> Void

    /// «أقرب مجلس بعده: الثلاثاء · 7:30 م»
    private var hint: String? {
        let off = organizer.offset(of: day)
        for step in 1..<DiwaniyaWeek.count {
            let next = organizer.weekday(atOffset: off + step)
            let entries = organizer.groups(day: next).flatMap(\.entries)
            guard !entries.isEmpty else { continue }
            let time = entries.compactMap(\.schedule.start).min().map { " · " + DiwaniyaSchedule.clockWithPeriod($0) } ?? ""
            return L10n.t("أقرب مجلس بعده: \(DiwaniyaWeek.name(next))\(time)",
                          "Next gathering: \(DiwaniyaWeek.name(next))\(time)")
        }
        return nil
    }

    var body: some View {
        DSEmptyView(L10n.t("لا مجالس يوم \(DiwaniyaWeek.name(day))", "No gatherings on \(DiwaniyaWeek.name(day))"),
                    message: hint, section: .diwaniyas,
                    actionTitle: L10n.t("كل الأسبوع", "Whole week"), actionIcon: "calendar",
                    style: .card, action: onShowWeek)
            .dsCard()
    }
}

// MARK: - بطاقة الأسبوع

/// تاريخ اليوم وحال الليلة، وشريط الأيام السبعة القادمة (يبدأ باليوم) — كريمي الهوية بخيط ذهبي
private struct DiwaniyaWeekHero: View {
    let organizer: DiwaniyaOrganizer
    let selectedDay: Int?
    let onSelect: (Int?) -> Void

    var body: some View {
        let summary = organizer.summary
        let shape = RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // الشارة بجانب التاريخ، وتنزل تحته حين يضيق السطر (خط أكبر)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Spacing.md) {
                    title(summary)
                    Spacer(minLength: 0)
                    badge(summary)
                }
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    title(summary)
                    badge(summary)
                }
            }
            // خيط ذهبي رفيع بين الحال والشريط
            Rectangle()
                .fill(DS.Color.accentLight.opacity(DS.Opacity.tintStroke))
                .frame(height: DS.Border.width)
            DiwaniyaWeekStrip(organizer: organizer, selectedDay: selectedDay, onSelect: onSelect)
        }
        .padding(DS.Spacing.md)
        .background(shape.fill(DS.Color.cardBackgroundSoft))
        .overlay(shape.strokeBorder(DS.Color.accentLight.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
        .accessibilityElement(children: .contain)
    }

    /// «الليلة» — قمر ونجوم على قرص القسم المجسّم، وتاريخ اليوم وحال الليلة
    private func title(_ summary: DiwaniyaTonightSummary) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSStateIcon("moon.stars.fill", tint: AppSection.diwaniyas.ink, size: DS.Icon.size)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(DiwaniyaWeek.longDate(organizer.now))
                    .dsFont(.headline)
                    .foregroundColor(DS.Color.textPrimary)
                Text(Self.summaryLine(summary, organizer: organizer))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// «كل الأسبوع» حين يُختار يوم، وإلا «مفتوحة الآن» إن وُجدت
    @ViewBuilder private func badge(_ summary: DiwaniyaTonightSummary) -> some View {
        if selectedDay != nil {
            DSChipButton(L10n.t("كل الأسبوع", "Week"), icon: "xmark", size: .small) { onSelect(nil) }
                .fixedSize()
                .transition(.opacity)
        } else if summary.live > 0 {
            DiwaniyaLivePill(count: summary.live)
                .fixedSize()
                .transition(.opacity)
        }
    }

    /// «مجالس الليلة: 3 · أولها 7:00 م» / «لا مجالس الليلة · أقربها غداً 7:00 م»
    static func summaryLine(_ s: DiwaniyaTonightSummary, organizer o: DiwaniyaOrganizer) -> String {
        let tonight = s.live + s.upcoming + s.ended
        if s.live + s.upcoming > 0 {
            if s.live == 0, let first = s.firstStart {
                let time = DiwaniyaSchedule.clockWithPeriod(first)
                return L10n.t("مجالس الليلة: \(tonight) · أولها \(time)", "Tonight: \(tonight) · first at \(time)")
            }
            return L10n.t("مجالس الليلة: \(tonight)", "Tonight: \(tonight)")
        }
        let head = tonight > 0 ? L10n.t("انتهت مجالس الليلة", "Tonight's gatherings are over")
                               : L10n.t("لا مجالس الليلة", "No gatherings tonight")
        guard let off = s.nextOffset else { return head }
        let name = DiwaniyaWeek.name(o.weekday(atOffset: off))
        let when: String
        switch off {
        case 1: when = L10n.t("غداً", "tomorrow")
        case DiwaniyaWeek.count: when = L10n.t("\(name) القادم", "next \(name)")
        default: when = name
        }
        let time = s.nextStart.map { " " + DiwaniyaSchedule.clockWithPeriod($0) } ?? ""
        return L10n.t("\(head) · أقربها \(when)\(time)", "\(head) · next \(when)\(time)")
    }
}

/// شريط الأيام السبعة: اسم اليوم، رقمه (اليوم بقرص القسم)، ونقاط ذهبية بعدد مجالسه. المختار مرفوع ببطاقة
/// تنزلق إليه. يضيق المكان (خط أكبر) ← حرف اليوم بدل اسمه.
private struct DiwaniyaWeekStrip: View {
    let organizer: DiwaniyaOrganizer
    let selectedDay: Int?
    let onSelect: (Int?) -> Void
    @Namespace private var ns

    var body: some View {
        let counts = organizer.dayCounts
        ViewThatFits(in: .horizontal) {
            row(counts, names: true)
            row(counts, names: false)
        }
    }

    private func row(_ counts: [Int], names: Bool) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(0..<DiwaniyaWeek.count, id: \.self) { off in
                let day = organizer.weekday(atOffset: off)
                cell(offset: off, day: day, count: counts[day], names: names)
            }
        }
    }

    private func cell(offset off: Int, day: Int, count: Int, names: Bool) -> some View {
        let selected = selectedDay == day
        let isToday = off == 0
        let tile = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        return Button {
            onSelect(selected ? nil : day)
        } label: {
            VStack(spacing: DS.Spacing.xs) {
                Text(names ? DiwaniyaWeek.shortName(day) : DiwaniyaWeek.letter(day))
                    .dsFont(.caption)
                    .foregroundColor(isToday ? AppSection.diwaniyas.ink
                                             : (count > 0 ? DS.Color.textSecondary : DS.Color.textTertiary))
                    .lineLimit(1)
                    // الخانات بعرض واحد: الاسم الأطول («أربعاء») يصغر قليلاً بدل «…»
                    .minimumScaleFactor(DSDiwaniya.dayNameScale)
                Text(DiwaniyaWeek.dayNumber(organizer.date(atOffset: off)))
                    .dsFont(.statValue)
                    .monospacedDigit()
                    .foregroundColor(isToday ? DS.Color.textOnPrimary
                                             : (count > 0 ? DS.Color.textPrimary : DS.Color.textTertiary))
                    .frame(minWidth: DSDiwaniya.dayDisc, minHeight: DSDiwaniya.dayDisc)
                    .background(Circle().fill(isToday ? AppSection.diwaniyas.fill : Color.clear))
                dots(count)
            }
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background {
                if selected {
                    tile.fill(DS.Color.surface)
                        .overlay(tile.strokeBorder(AppSection.diwaniyas.ink.opacity(DS.Opacity.tintStroke),
                                                   lineWidth: DS.Border.width))
                        .dsSubtleShadow()
                        // معرّف لكل شكل من شكلي الشريط (`ViewThatFits` يقيس الاثنين)
                        .matchedGeometryEffect(id: names ? "dayName" : "dayLetter", in: ns)
                }
            }
            .contentShape(tile)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(L10n.t("\(DiwaniyaWeek.name(day)) \(DiwaniyaWeek.shortDate(organizer.date(atOffset: off)))، المجالس: \(count)",
                                   "\(DiwaniyaWeek.name(day)) \(DiwaniyaWeek.shortDate(organizer.date(atOffset: off))), gatherings: \(count)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// حتى ثلاث نقاط ذهبية — اليوم الفارغ يحفظ مكانها فتبقى الخانات بارتفاع واحد
    private func dots(_ count: Int) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(0..<min(count, DSDiwaniya.maxDots), id: \.self) { _ in
                DSGoldDot(size: DSDiwaniya.dayDot)
            }
        }
        .frame(height: DSDiwaniya.dayDot)
    }
}

/// «مفتوحة الآن» بعددها — نقطة خضراء تنبض بهدوء (الساعة المشتركة، ساكنة مع «تقليل الحركة»)
private struct DiwaniyaLivePill: View {
    let count: Int

    var body: some View {
        HStack(spacing: DS.Spacing.xsm) {
            DiwaniyaLiveDot()
            Text(L10n.t("مفتوحة الآن", "Open now"))
                .dsFont(.caption)
            Text("\(count)")
                .dsFont(.micro)
                .monospacedDigit()
        }
        .foregroundColor(DS.Color.success)
        .padding(.horizontal, DSBox.chipPaddingSmall)
        .frame(minHeight: DSBox.chipHeightSmall)
        .background(Capsule().fill(DS.Color.success.opacity(DS.Opacity.tintFill)))
        .overlay(Capsule().strokeBorder(DS.Color.success.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
        .accessibilityElement(children: .combine)
    }
}

private struct DiwaniyaLiveDot: View {
    var body: some View {
        Circle()
            .fill(DS.Color.success)
            .frame(width: DS.Pulse.dot, height: DS.Pulse.dot)
            .dsUrgentPulse(DS.Color.success, active: true)
            .accessibilityHidden(true)
    }
}

// MARK: - بطاقة المجلس

/// بطاقة المجلس الواحدة: الرأس (الصورة/المجسّم، الاسم، الصاحب، القائمة)، سطر الموعد (حال الليلة)،
/// ثم أسبوعه والإجراءات السريعة — أو «اعتماد/رفض» للإدارة إن كانت معلّقة
struct DiwaniyaCard: View {
    let entry: DiwaniyaEntry
    let actions: DiwaniyaCardActions

    private var item: Diwaniya { entry.item }
    private var isPending: Bool { item.approvalStatus == ApprovalStatus.pending.rawValue }
    private var isClosed: Bool { item.isClosed == true }
    private var kind: DiwaniyaKind { item.isHusseiniya ? .husseiniya : .diwaniya }

    /// لون البطاقة: المعلّقة بلون الانتظار، والمتوقفة رمادية، والحسينية بأخضرها، والديوانية بحبر القسم
    private var tint: Color {
        if isPending { return DS.Color.warning }
        if isClosed { return DS.Color.slate }
        return item.isHusseiniya ? DS.Color.composerHusseiniya : AppSection.diwaniyas.ink
    }

    /// تعبئة الحروف المضاءة تحت نص أبيض (ثابتة في الوضعين)
    private var fill: Color {
        if isPending { return DS.Color.warningFill }
        if isClosed { return DS.Color.slateFill }
        return item.isHusseiniya ? DS.Color.palmFill : AppSection.diwaniyas.fill
    }

    /// إطار ملوّن: المعلّقة بلون الانتظار، والمفتوحة الآن بالأخضر
    private var accentStroke: Color {
        if isPending { return DS.Color.warning.opacity(DS.Opacity.tintStroke) }
        if entry.tonight?.isLive == true { return DS.Color.success.opacity(DS.Opacity.tintStroke) }
        return .clear
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DiwaniyaCardHeader(item: item, kind: kind, tint: tint, actions: actions)
            DiwaniyaWhenLine(entry: entry, tint: tint)
            footer
        }
        .padding(DS.Spacing.md)
        .overlay(alignment: .bottom) {
            if case .live(let progress, _)? = entry.tonight {
                DiwaniyaLiveBar(progress: progress)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(accentStroke, lineWidth: DS.Border.width))
        .dsCard(padding: nil)
        // المتوقفة والمنتهية الليلة خافتة قليلاً
        .opacity(isClosed || entry.tonight?.isEnded == true ? DS.Opacity.dimmed : 1)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var footer: some View {
        if isPending && actions.canApprove {
            // الاعتماد من القسم نفسه — للإدارة (طلب المالك: «يوافقون من القسم نفسه»)
            HStack(spacing: DS.Spacing.sm) {
                DSButton(L10n.t("اعتماد", "Approve"), icon: "checkmark", tint: DS.Color.success) { actions.approve(item) }
                DSButton(L10n.t("رفض", "Reject"), icon: "xmark", tint: DS.Color.reject) { actions.reject(item) }
            }
        } else if isPending {
            HStack(spacing: DS.Spacing.sm) {
                DiwaniyaMiniWeek(days: entry.schedule.days, fill: fill)
                Spacer(minLength: DS.Spacing.sm)
                Text(L10n.t("تظهر للجميع بعد موافقة الإدارة", "Appears after admin approval"))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.warning)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Spacing.sm) {
                    DiwaniyaMiniWeek(days: entry.schedule.days, fill: fill)
                    Spacer(minLength: DS.Spacing.sm)
                    DiwaniyaQuickActions(item: item, schedule: entry.schedule)
                }
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    DiwaniyaMiniWeek(days: entry.schedule.days, fill: fill)
                    DiwaniyaQuickActions(item: item, schedule: entry.schedule)
                }
            }
        }
    }
}

/// رأس البطاقة: صورة المجلس (أو مجسّم نوعه)، الاسم + وسم الحسينية، الصاحب، وزرّ النقاط
private struct DiwaniyaCardHeader: View {
    let item: Diwaniya
    let kind: DiwaniyaKind
    let tint: Color
    let actions: DiwaniyaCardActions

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            DiwaniyaThumb(item: item, kind: kind, tint: tint)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xsm) {
                    Text(item.title)
                        .dsFont(.headline)
                        .foregroundColor(item.isClosed == true ? DS.Color.textSecondary : DS.Color.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    // النوع وسم صغير (بدل شريط «ديوانيات/حسينيات» — طلب المالك)
                    if item.isHusseiniya {
                        DSStatusChip(text: DiwaniyaKind.husseiniya.title, icon: DiwaniyaKind.husseiniya.icon,
                                     tint: DS.Color.composerHusseiniya, size: .mini)
                    }
                }
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "person.fill")
                        .dsGlyph(DS.Glyph.xs)
                        .foregroundColor(DS.Color.textTertiary)
                        .accessibilityHidden(true)
                    Text(item.ownerName)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textSecondary)
                        .dsNameLines()
                }
            }
            Spacer(minLength: 0)
            DiwaniyaCardMenu(item: item, actions: actions)
        }
    }
}

/// صورة المجلس إن وُجدت (مصغّرة بزوايا القرص)، وإلا مجسّم نوعه: «مجلس» للديوانية و«راية» للحسينية
private struct DiwaniyaThumb: View {
    let item: Diwaniya
    let kind: DiwaniyaKind
    let tint: Color

    var body: some View {
        if let raw = item.imageUrl, !raw.isEmpty, let url = URL(string: raw) {
            let shape = RoundedRectangle(cornerRadius: DS.Icon.discRadius, style: .continuous)
            CachedAsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                DSStateIcon(kind.icon, tint: tint, size: DS.Icon.size)
            }
            .frame(width: DS.Icon.size, height: DS.Icon.size)
            .clipShape(shape)
            .overlay(shape.strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke), lineWidth: DS.Border.width))
            .accessibilityHidden(true)
        } else {
            DSStateIcon(kind.icon, tint: tint, size: DS.Icon.size)
        }
    }
}

/// زرّ النقاط: نسخ الرقم، التعديل والحذف لمن يملكهما، والإبلاغ عن غير ديوانياته
private struct DiwaniyaCardMenu: View {
    let item: Diwaniya
    let actions: DiwaniyaCardActions

    private var phone: String? {
        guard let p = item.contactPhone, !p.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return p
    }

    var body: some View {
        let canEdit = actions.canEdit(item)
        let canReport = actions.canReport(item)
        if canEdit || canReport || phone != nil {
            Menu {
                if let phone {
                    Button {
                        UIPasteboard.general.string = KuwaitPhone.display(phone)
                        DSMomentToast.show(L10n.t("تم نسخ الرقم", "Number copied"), moment: .success, section: .diwaniyas)
                    } label: {
                        Label(L10n.t("نسخ الرقم", "Copy number"), systemImage: "doc.on.doc")
                    }
                }
                if canEdit {
                    if phone != nil { Divider() }
                    Button(action: { actions.edit(item) }) {
                        Label(L10n.t("تعديل", "Edit"), systemImage: "pencil")
                    }
                    // الحذف للمالك والمدير (`canDeleteDiwaniyas`) — نفس شرط الحذف في السيرفر
                    if actions.canDeleteAny {
                        Button(role: .destructive, action: { actions.delete(item) }) {
                            Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                        }
                    }
                }
                // إبلاغ متاح للجميع (أعضاء وإدارة) لغير ديوانياتهم — سياسة Apple
                if canReport {
                    if canEdit || phone != nil { Divider() }
                    Button(action: { actions.report(item) }) {
                        Label(L10n.t("إبلاغ", "Report"), systemImage: "exclamationmark.bubble")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .dsGlyph(DS.Glyph.lg)
                    .foregroundColor(DS.Color.textSecondary)
                    .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                    .background(Circle().fill(DS.Color.textTertiary.opacity(DS.Opacity.tintFillSoft)))
                    // القرص ٣٨ ← مساحة ضغط ٤٤ بلا تغيير في التخطيط
                    .dsTapArea(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
            }
            .accessibilityLabel(L10n.t("خيارات", "Options"))
        }
    }
}

/// سطر الموعد: حال الليلة (مفتوحة الآن / تبدأ بعد… / انتهت) أو الوقت، ثم المنطقة
private struct DiwaniyaWhenLine: View {
    let entry: DiwaniyaEntry
    let tint: Color

    var body: some View {
        let area = entry.item.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.sm) {
                status
                if !area.isEmpty { separator; place(area) }
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                status
                if !area.isEmpty { place(area) }
            }
        }
    }

    private var separator: some View {
        Circle()
            .fill(DS.Color.textTertiary.opacity(DS.Opacity.divider))
            .frame(width: DS.Spacing.xs, height: DS.Spacing.xs)
            .accessibilityHidden(true)
    }

    private func place(_ area: String) -> some View {
        label(area, icon: "mappin.and.ellipse", color: DS.Color.textSecondary, glyph: DS.Color.accent)
    }

    @ViewBuilder private var status: some View {
        let s = entry.schedule
        switch entry.tonight {
        case .live(_, let end)?:
            HStack(spacing: DS.Spacing.xsm) {
                DiwaniyaLiveDot()
                Text(L10n.t("مفتوحة الآن · حتى \(DiwaniyaSchedule.clockWithPeriod(end))",
                            "Open now · until \(DiwaniyaSchedule.clockWithPeriod(end))"))
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.success)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        case .upcoming(let start, let minutes)?:
            let time = DiwaniyaSchedule.clockWithPeriod(start)
            label(minutes <= Self.soonWindow
                    ? L10n.t("تبدأ \(time) · \(Self.inText(minutes))", "Starts \(time) · \(Self.inText(minutes))")
                    : L10n.t("الليلة \(time)", "Tonight \(time)"),
                  icon: "clock.fill", color: AppSection.diwaniyas.ink, glyph: AppSection.diwaniyas.ink, role: .chip)
        case .ended?:
            label(L10n.t("انتهت الليلة", "Over for tonight") + (s.timeText.map { " · \($0)" } ?? ""),
                  icon: "checkmark.circle", color: DS.Color.textTertiary, glyph: DS.Color.textTertiary)
        case .today?:
            label(L10n.t("الليلة", "Tonight"), icon: "clock.fill",
                  color: AppSection.diwaniyas.ink, glyph: AppSection.diwaniyas.ink, role: .chip)
        case nil:
            if let time = s.timeText {
                label(time, icon: "clock.fill", color: DS.Color.textSecondary, glyph: tint)
            } else if let free = s.freeText {
                label(free, icon: "text.bubble.fill", color: DS.Color.textSecondary, glyph: tint)
            } else {
                label(L10n.t("الموعد غير محدد", "No time set"), icon: "clock",
                      color: DS.Color.textTertiary, glyph: DS.Color.textTertiary)
            }
        }
    }

    private func label(_ text: String, icon: String, color: Color, glyph: Color,
                       role: DS.TextRole = .subtitle) -> some View {
        HStack(spacing: DS.Spacing.xsm) {
            Image(systemName: icon)
                .dsGlyph(DS.Glyph.sm)
                .foregroundColor(glyph)
                .accessibilityHidden(true)
            Text(text)
                .dsFont(role)
                .foregroundColor(color)
                .lineLimit(1)
        }
    }

    /// «تبدأ بعد …» خلال ثلاث ساعات — وما بعدها وقتها فقط
    private static let soonWindow = 180

    /// «بعد 45 د» / «بعد ساعة» / «بعد ساعتين» / «بعد 3 ساعات»
    private static func inText(_ minutes: Int) -> String {
        if minutes < 60 { return L10n.t("بعد \(max(minutes, 1)) د", "in \(max(minutes, 1)) min") }
        let h = Int((Double(minutes) / 60).rounded())
        switch h {
        case 1: return L10n.t("بعد ساعة", "in 1 hr")
        case 2: return L10n.t("بعد ساعتين", "in 2 hr")
        default: return L10n.t("بعد \(h) ساعات", "in \(h) hr")
        }
    }
}

/// شريط تقدّم المجلس المفتوح على حافة البطاقة السفلية — من بدايته حتى نهايته (يبدأ من جهة القراءة)
private struct DiwaniyaLiveBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(DS.Color.success.opacity(DS.Opacity.tintFill))
                Rectangle().fill(DS.Color.success)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: DSDiwaniya.liveBar)
        .accessibilityHidden(true)
    }
}

/// حروف الأسبوع السبعة (س ح ن ث ر خ ج) — أيام المجلس مضاءة بلونه، والقارئ الصوتي يقرأ الأيام كاملة
private struct DiwaniyaMiniWeek: View {
    let days: [Int]
    let fill: Color

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(0..<DiwaniyaWeek.count, id: \.self) { day in
                let on = days.contains(day)
                Text(DiwaniyaWeek.letter(day))
                    .dsFont(.badge)
                    .foregroundColor(on ? DS.Color.textOnPrimary : DS.Color.textTertiary)
                    .frame(minWidth: DSDiwaniya.weekLetter, minHeight: DSDiwaniya.weekLetter)
                    .background(Circle().fill(on ? fill : DS.Color.textTertiary.opacity(DS.Opacity.tintFillSoft)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DiwaniyaSchedule.daysLabel(days))
    }
}

/// اتصال · الموقع · مشاركة — أقراص صغيرة بلون معناها (التواصل بترولي، المكان ذهبي، المشاركة بحبر القسم)
private struct DiwaniyaQuickActions: View {
    let item: Diwaniya
    let schedule: DiwaniyaSchedule

    private var callURL: URL? { KuwaitPhone.telURL(item.contactPhone) }

    /// رابط الخريطة المحفوظ، وإلا بحث الخرائط باسم المنطقة
    private var mapURL: URL? {
        if let raw = item.mapsUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, let url = URL(string: raw) {
            return url
        }
        guard let area = item.address?.trimmingCharacters(in: .whitespacesAndNewlines), !area.isEmpty else { return nil }
        var c = URLComponents(string: "https://maps.apple.com/")
        c?.queryItems = [URLQueryItem(name: "q", value: area)]
        return c?.url
    }

    /// نص المشاركة: الاسم والصاحب، الأيام والوقت، المنطقة، ورابط الخريطة
    private var shareText: String {
        var lines = ["\(item.title) — \(item.ownerName)"]
        let when = [schedule.daysText, schedule.timeText].compactMap { $0 }.joined(separator: " · ")
        if !when.isEmpty { lines.append(when) } else if let free = schedule.freeText { lines.append(free) }
        if let area = item.address?.trimmingCharacters(in: .whitespacesAndNewlines), !area.isEmpty { lines.append(area) }
        if let raw = item.mapsUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty { lines.append(raw) }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let callURL {
                Button { UIApplication.shared.open(callURL) } label: {
                    DiwaniyaActionDisc(icon: "phone.fill", tint: DS.Color.sea)
                }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel(L10n.t("اتصال", "Call"))
            }
            if let mapURL {
                Button { UIApplication.shared.open(mapURL) } label: {
                    DiwaniyaActionDisc(icon: "location.fill", tint: DS.Color.accent)
                }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel(L10n.t("الموقع", "Location"))
            }
            ShareLink(item: shareText) {
                DiwaniyaActionDisc(icon: "square.and.arrow.up", tint: AppSection.diwaniyas.ink)
            }
            .buttonStyle(DSPressStyle())
            .accessibilityLabel(L10n.t("مشاركة", "Share"))
        }
    }
}

/// قرص إجراء سريع: الرمز بلون معناه على تعبئته الخفيفة — مساحة ضغط ٤٤ بلا تغيير في التخطيط
private struct DiwaniyaActionDisc: View {
    let icon: String
    let tint: Color

    var body: some View {
        Image(systemName: icon)
            .dsGlyph(DS.Glyph.md)
            .foregroundColor(tint)
            .frame(width: DSDiwaniya.actionDisc, height: DSDiwaniya.actionDisc)
            .background(Circle().fill(tint.opacity(DS.Opacity.tintFill)))
            .overlay(Circle().strokeBorder(tint.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
            .dsTapArea(width: DSDiwaniya.actionDisc, height: DSDiwaniya.actionDisc)
    }
}

extension DiwaniyaSchedule {
    /// أيام المجلس للقارئ الصوتي: «السبت والخميس» أو «لا أيام محددة»
    static func daysLabel(_ days: [Int]) -> String {
        guard !days.isEmpty else { return L10n.t("لا أيام محددة", "No days set") }
        if days.count == DiwaniyaWeek.count { return L10n.t("كل يوم", "Every day") }
        let names = days.map { DiwaniyaWeek.name($0) }
        return names.joined(separator: L10n.t("، ", ", "))
    }
}
