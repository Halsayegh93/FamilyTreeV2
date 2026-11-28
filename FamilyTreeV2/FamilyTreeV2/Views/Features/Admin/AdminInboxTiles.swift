import SwiftUI

// MARK: - مربّعات رأس «الوارد» (العيّنة المعتمدة `reports/app-review/inbox/inbox-final.png`، ٢٠٢٦-١١-٢٨)
//
// داخل الرأس الكحلي تحت «بانتظار قرارك · عاجل · متأخر»: «الطلبات» · «المنجزة» · «الرسائل» (من اليمين) — كل مربّع رمز + رقم
// + اسم في صفّ واحد، ٥٤، زاوية ١٤، إطار أبيض ١٨٪، والمختار حلقة ذهبية (`accentLight`). اللون حسب المعنى
// (`DS.Color.inboxRequestsFill` · `inboxDoneFill` · `inboxMessagesFill`). المربّع يبدّل القائمة تحت الرأس:
// الطلبات = قائمة «الوارد»، المنجزة = `AdminInboxHandledPage` (اليوم · هذا الأسبوع)، الرسائل = `AdminInboxView` —
// والصفحتان الأخيرتان تُرسمان برأس «الوارد» نفسه (`AdminInboxBandMaker` في البيئة). «الرسائل» لمن يملك `inbox.messages`.
// تحت المربّعات سطر البحث + «تصفية» على الكحلي بشكل «العائلة» (`AdminMembersFilterBar`)، وتحت الرأس شرائح المفعّل وسطر الملخّص.

enum AdminInboxTile: String, CaseIterable, Identifiable {
    case requests, done, messages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .requests: return L10n.t("الطلبات", "Requests")
        // «المنجزة» وحدها (المالك ٢٠٢٦-١١-٢٨: سطر واحد مثل الآخرين) — الرقم ما أُنجز اليوم
        case .done:     return L10n.t("المنجزة", "Done")
        case .messages: return L10n.t("الرسائل", "Messages")
        }
    }

    var icon: String {
        switch self {
        case .requests: return "list.clipboard"
        case .done:     return "checkmark"
        case .messages: return "message"
        }
    }

    var fill: Color {
        switch self {
        case .requests: return DS.Color.inboxRequestsFill
        case .done:     return DS.Color.inboxDoneFill
        case .messages: return DS.Color.inboxMessagesFill
        }
    }

    /// ما يقوله القارئ الصوتي عن الرقم
    func spoken(_ value: Int?) -> String {
        guard let value else { return L10n.t("\(title)، يُحمَّل", "\(title), loading") }
        switch self {
        case .requests: return L10n.t("الطلبات، \(value) معلّق", "Requests, \(value) pending")
        case .done:     return L10n.t("المنجزة، \(value) اليوم", "Done, \(value) today")
        case .messages: return L10n.t("الرسائل، \(value) غير مقروءة", "Messages, \(value) unread")
        }
    }
}

/// مربّع واحد بقيمته — nil = لم يصل بعد («—»)
struct AdminInboxTileItem: Identifiable {
    let tile: AdminInboxTile
    let value: Int?
    var id: String { tile.id }
}

/// صفّ المربّعات (صفّ واحد؛ من أحجام إمكانية الوصول عمود)
struct AdminInboxTileRow: View {
    let items: [AdminInboxTileItem]
    let selected: AdminInboxTile
    let onSelect: (AdminInboxTile) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let tiles = ForEach(items) { item in
            AdminInboxTileButton(item: item, selected: item.tile == selected) { onSelect(item.tile) }
        }
        if typeSize.isAccessibilitySize {
            VStack(spacing: DS.Spacing.sm) { tiles }
        } else {
            HStack(spacing: DS.Spacing.sm) { tiles }
        }
    }
}

private struct AdminInboxTileButton: View {
    let item: AdminInboxTileItem
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Hub.inboxTileRadius, style: .continuous)
        let ringGap = DS.Hub.inboxTileRingGap + DS.Hub.inboxTileRing
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: item.tile.icon)
                    .dsGlyph(DS.Glyph.md, weight: .semibold)
                    .accessibilityHidden(true)
                Text(verbatim: item.value.map { DSNumber.grouped($0) } ?? "—")
                    .dsFont(.hubKPI)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                Text(item.tile.title)
                    .dsFont(.inboxTileLabel)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundColor(DS.Color.textOnPrimary)
            .padding(.horizontal, DS.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: DS.Hub.inboxTileHeight)
            .background(shape.fill(item.tile.fill))
            .overlay(shape.strokeBorder(Color.white.opacity(DS.Hub.inboxTileStrokeOpacity), lineWidth: DS.Border.width))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: DS.Hub.inboxTileRadius + ringGap, style: .continuous)
                        .strokeBorder(DS.Color.accentLight, lineWidth: DS.Hub.inboxTileRing)
                        .padding(-ringGap)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.tile.spoken(item.value))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - رأس «الوارد» فوق صفحة مضمّنة

/// يرسم رأس «الوارد» (الأرقام والمربّعات) فوق «المنجزة» و«الرسائل»: الصفحة تمرّر أزرار رأسها («تحديد») وسطر البحث والتصفية
struct AdminInboxBandMaker {
    let make: (_ actions: [AdminPageAction], _ accessory: AnyView?) -> AnyView
}

private struct AdminInboxBandMakerKey: EnvironmentKey { static let defaultValue: AdminInboxBandMaker? = nil }

extension EnvironmentValues {
    /// غير nil = الصفحة مضمّنة تحت مربّعات «الوارد» (لا تُورَّث للصفحات المدفوعة منها — `AdminPage.pushedPage`)
    var adminInboxBand: AdminInboxBandMaker? {
        get { self[AdminInboxBandMakerKey.self] }
        set { self[AdminInboxBandMakerKey.self] = newValue }
    }
}

/// أزرار رأس الصفحة المضمّنة بشكل `AdminPageBand` نفسه (نصّ أو دائرة زجاجية)
struct AdminInboxBandActions: View {
    let actions: [AdminPageAction]

    var body: some View {
        ForEach(actions) { action in
            if action.textOnly, case .action(let run) = action.tap {
                AdminHeaderTextButton(title: action.label, action: run)
            } else {
                AdminTapWrap(tap: action.tap, feel: .scale,
                             label: AnyView(AdminGlassCircle(symbol: action.symbol, dot: action.dot)),
                             accessibilityLabel: action.label)
            }
        }
    }
}

// MARK: - «المنجزة»: الفترة (منطق خالص)

enum AdminInboxDoneLogic {
    /// «اليوم» (المحايد، بلا شريحة) · «هذا الأسبوع» — من مخزن «المنجز» نفسه (آخر ٣٠ يوماً بصفحات ٤٠)
    enum Range: String, CaseIterable, Hashable {
        case today, week

        var title: String {
            switch self {
            case .today: return L10n.t("اليوم", "Today")
            case .week:  return L10n.t("هذا الأسبوع", "This week")
            }
        }
    }

    struct Filters: Equatable {
        var range: Range = .today
    }

    static func contains(_ date: Date, _ range: Range, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch range {
        case .today: return calendar.isDate(date, inSameDayAs: now)
        case .week:  return calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) && date <= now.addingTimeInterval(60)
        }
    }

    /// أول الأسبوع — «عرض المزيد» يبقى ما دام آخر المحمَّل داخل الأسبوع
    static func weekStart(now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
    }
}

// MARK: - تحت الرأس: المفعّل وسطر العدد (شكل «العائلة»)

/// شريحة لكل اختيار بـ✕ (`AdminActiveFilterChips`) ثم «12 طلباً · الأحدث أولاً» (`AdminFilterCaption`) — الطقم الواحد، والبحث
/// و«تصفية» في الكحلي فوقها (`AdminMembersFilterBar`)
struct AdminInboxFilterStatus<S: Equatable>: View {
    let set: AdminFilterSet<S>
    @Binding var selection: S
    var note: String? = nil

    var body: some View {
        let snapshot = set.snapshot(selection)
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            if !snapshot.items.isEmpty {
                AdminActiveFilterChips(set: set, selection: $selection, snapshot: snapshot)
            }
            AdminFilterCaption(set: set, note: note, snapshot: snapshot)
        }
    }
}
