import SwiftUI
import UIKit

// MARK: - طقم الفلاتر (إعادة تصميم الإدارة U5 — spec A.9/A.13، اختيار المالك «ب» ٢٠٢٦-١١-٢٦)
//
// سطر واحد أعلى القائمة: حقل البحث + زرّ «الفلاتر» بعدد الفلاتر المفعّلة (`AdminFilterBar`) ← تحته شرائح الفلاتر
// المفعّلة، كل شريحة ✓ + القيمة + عددها + ✕ تلغي فلترها (`AdminActiveFilterChips`) ← سطر «مسح الفلاتر» … «123 رجل ·
// أبجدياً» (`AdminFilterCaption`). الثلاثة معاً: `AdminFilterPanel`.
// الزرّ يفتح ورقة «الفلاتر» (`AdminFilterSheet`، `.adminFilterSheet`): نصف الشاشة تكبر للكاملة، «إلغاء · الفلاتر · تم»،
// سطر «النتيجة الآن: N» يتغيّر مع كل اختيار قبل «تم»، مجموعات بعناوين صغيرة وصفوف اختيار بأعدادها، صفّ يفتح منتقياً
// داخل الورقة (الفرع ← `BranchPickerSheet`)، و«مسح الفلاتر» (أو «إعادة ضبط الفلاتر» لصفحة لها فلتر افتراضي) أسفلها.
// «إلغاء» والسحب لأسفل يرجعان كما كان، و«تم» يطبّق.
//
// عامّ لكل صفحة (الوارد، العائلة، نساء العائلة، تواريخ الوفاة): الصفحة تملك حالة فلاترها بنوعها هي (`S`) وتطبّقها على
// قائمتها كما تشاء، وتعطي الطقم `AdminFilterSet<S>`: المجموعات وأعدادها لأي حالة (فالأعداد تتبع بقية الاختيارات)،
// وعدد النتيجة لأي حالة، والحالة التي يرجع إليها «مسح الفلاتر». الطقم يمسك «المعلّق» داخل الورقة ولا يكتب في حالة
// الصفحة إلا بـ«تم» أو بـ✕ الشريحة أو «مسح الفلاتر» تحت الشريط.
//
// مراجع (spec §G): Sotheby's · Letterboxd · HotelTonight (عيّنة المالك)، وGetYourGuide (المسح أسفل الورقة) — Uizze.

// MARK: - النموذج

/// دور المجموعة في الورقة
enum AdminFilterRole {
    /// فلتر: يُعدّ في زرّ «الفلاتر» وله شريحة مفعّلة تُلغى
    case filter
    /// ترتيب («أبجدياً · الأحدث»): لا يُعدّ ولا شريحة له — اسمه في سطر الملخّص («123 رجل · أبجدياً»)
    case order
}

/// خيار واحد في مجموعة: القيمة بنوع الصفحة، الاسم، والعدد (nil = لم يُحمَّل بعد ← «—»، والخيار يبقى قابلاً للاختيار)
struct AdminFilterOption<Value> {
    let value: Value
    let title: String
    var count: Int?
    /// اسم أقصر للشريحة المفعّلة — nil = الاسم نفسه
    var chipTitle: String?

    init(_ value: Value, _ title: String, count: Int? = nil, chipTitle: String? = nil) {
        self.value = value
        self.title = title
        self.count = count
        self.chipTitle = chipTitle
    }
}

/// مجموعة في ورقة الفلاتر: صفوف اختيار بأعدادها (`.choices`)، أو ترتيب (`.order`)، أو صفّ يفتح منتقياً (`.picker`).
/// تُبنى لحالة بعينها (`AdminFilterSet.groups(s)`)، فالأعداد والاسم المعروض لتلك الحالة.
struct AdminFilterGroup<S>: Identifiable {
    struct Row: Identifiable {
        let id: Int
        let title: String
        let count: Int?
        let isSelected: (S) -> Bool
        let select: (inout S) -> Void
    }

    /// صفّ واحد بسهم يدفع منتقياً داخل الورقة (مثل الفرع: قائمة طويلة)
    struct PickerRow {
        /// القيمة الحالية بالكلام («كل الفروع»، «فرع جاسم»)
        let valueTitle: String
        let count: Int?
        /// الوجهة ترسم رأسها و«إلغاءها» بنفسها (`BranchPickerSheet`) — وإلا يرسم الطقم سطر رجوع «‹ الفلاتر» فوقها
        let ownsHeader: Bool
        /// الوجهة لحالة المعلّق، و`apply` يكتب الاختيار في المعلّق ويرجع للورقة
        let destination: (S, _ apply: @escaping ((inout S) -> Void) -> Void) -> AnyView
    }

    let id: String
    let title: String
    let role: AdminFilterRole
    let showsCounts: Bool
    let rows: [Row]
    let pickerRow: PickerRow?
    /// مفعّل = ليس على قيمته المحايدة («الكل»)
    let isActive: (S) -> Bool
    /// يرجع المجموعة لقيمتها المحايدة
    let clear: (inout S) -> Void
    /// اسم القيمة المختارة وعددها للشريحة المفعّلة — nil حين تكون محايدة
    let chip: (S) -> (title: String, count: Int?)?
}

extension AdminFilterGroup {
    /// صفوف اختيار بأعدادها — `all` القيمة المحايدة («الكل»): لا شريحة لها ولا تُعدّ
    static func choices<Value: Equatable>(_ id: String, title: String, value: WritableKeyPath<S, Value>, all: Value,
                                          options: [AdminFilterOption<Value>],
                                          showsCounts: Bool = true) -> AdminFilterGroup<S> {
        radio(id, title: title, role: .filter, value: value, neutral: all, options: options, showsCounts: showsCounts)
    }

    /// ترتيب القائمة — `standard` ترتيب الصفحة الافتراضي. بلا أعداد ولا شريحة
    static func order<Value: Equatable>(_ id: String, title: String, value: WritableKeyPath<S, Value>, standard: Value,
                                        options: [AdminFilterOption<Value>]) -> AdminFilterGroup<S> {
        radio(id, title: title, role: .order, value: value, neutral: standard, options: options, showsCounts: false)
    }

    /// صفّ واحد بسهم يدفع منتقياً داخل الورقة (spec A.13: «الفرع» ← `BranchPickerSheet`).
    /// `valueTitle` اسم القيمة الحالية لهذه الحالة («كل الفروع» حين تكون `all`)، و`destination` يرسم المنتقي
    /// ويستدعي `pick` بالقيمة المختارة (الطقم يكتبها في المعلّق ويرجع للورقة).
    static func picker<Value: Equatable>(_ id: String, title: String, value: WritableKeyPath<S, Value>, all: Value,
                                         valueTitle: String, count: Int? = nil, ownsHeader: Bool = false,
                                         destination: @escaping (_ current: Value,
                                                                 _ pick: @escaping (Value) -> Void) -> AnyView)
        -> AdminFilterGroup<S> {
        let row = PickerRow(valueTitle: valueTitle, count: count, ownsHeader: ownsHeader,
                            destination: { state, apply in
                                destination(state[keyPath: value]) { picked in
                                    apply { $0[keyPath: value] = picked }
                                }
                            })
        return AdminFilterGroup(id: id, title: title, role: .filter, showsCounts: count != nil, rows: [],
                                pickerRow: row,
                                isActive: { $0[keyPath: value] != all },
                                clear: { $0[keyPath: value] = all },
                                chip: { $0[keyPath: value] == all ? nil : (valueTitle, count) })
    }

    private static func radio<Value: Equatable>(_ id: String, title: String, role: AdminFilterRole,
                                                value: WritableKeyPath<S, Value>, neutral: Value,
                                                options: [AdminFilterOption<Value>],
                                                showsCounts: Bool) -> AdminFilterGroup<S> {
        let rows = options.enumerated().map { index, option in
            Row(id: index, title: option.title, count: option.count,
                isSelected: { $0[keyPath: value] == option.value },
                select: { $0[keyPath: value] = option.value })
        }
        return AdminFilterGroup(id: id, title: title, role: role, showsCounts: showsCounts, rows: rows,
                                pickerRow: nil,
                                isActive: { $0[keyPath: value] != neutral },
                                clear: { $0[keyPath: value] = neutral },
                                chip: { state in
                                    let current = state[keyPath: value]
                                    guard current != neutral,
                                          let option = options.first(where: { $0.value == current }) else { return nil }
                                    return (option.chipTitle ?? option.title, option.count)
                                })
    }
}

/// كل ما تعطيه الصفحة للطقم. `S` حالة فلاترها بنوعها هي (struct Equatable).
struct AdminFilterSet<S: Equatable> {
    /// ما يرجع إليه «مسح الفلاتر» — بلا فلاتر عادةً؛ صفحة لها فلتر افتراضي (نساء العائلة: «الحيّات») تمرّره فيصير
    /// الزرّ «إعادة ضبط الفلاتر»
    let reset: S
    /// المجموعات لحالة بعينها (الأعداد تتبع بقية اختيارات تلك الحالة؛ مجموعة تابعة مثل «النوع» تظهر بعد «المجموعة»)
    let groups: (S) -> [AdminFilterGroup<S>]
    /// عدد النتيجة لحالة بعينها — nil = لم يُحمَّل بعد («—»). الصفحة تقرّر إن كان يشمل نصّ البحث
    let resultCount: (S) -> Int?
    /// المعدود بعد الرقم بالعربية الصحيحة («رجل»، «طلباً»…) — `AdminFilterText.noun`
    let noun: (Int) -> String
    /// يُصلح الحالة بعد كل اختيار (مثل: «النوع» لم يعد من «المجموعة» المختارة ← «الكل»)
    let normalize: (inout S) -> Void

    init(reset: S,
         noun: @escaping (Int) -> String = { AdminFilterText.resultsNoun($0) },
         normalize: @escaping (inout S) -> Void = { _ in },
         resultCount: @escaping (S) -> Int?,
         groups: @escaping (S) -> [AdminFilterGroup<S>]) {
        self.reset = reset
        self.noun = noun
        self.normalize = normalize
        self.resultCount = resultCount
        self.groups = groups
    }

    /// عدد الفلاتر المفعّلة (بلا الترتيب) — رقم زرّ «الفلاتر»
    func activeCount(_ state: S) -> Int {
        groups(state).filter { $0.role == .filter && $0.isActive(state) }.count
    }

    /// «مسح الفلاتر»، أو «إعادة ضبط الفلاتر» حين يكون للصفحة فلتر افتراضي
    var resetTitle: String {
        activeCount(reset) == 0 ? AdminFilterText.clear : AdminFilterText.resetDefaults
    }

    /// «123 رجل» — «—» ما دام العدد لم يُحمَّل
    func resultPhrase(_ count: Int?) -> String {
        guard let count else { return "—" }
        return "\(DSNumber.grouped(count)) \(noun(count))"
    }

    /// ملخّص حالة واحدة لما تحت الشريط — يُحسب مرة لكل رسم (المجموعات قد تعدّ آلاف الأعضاء)
    func snapshot(_ state: S) -> AdminFilterSnapshot<S> {
        let all = groups(state)
        let items: [AdminFilterSnapshot<S>.Item] = all.compactMap { group in
            guard group.role == .filter, group.isActive(state), let chip = group.chip(state) else { return nil }
            return .init(id: group.id, groupTitle: group.title, title: chip.title,
                         count: group.showsCounts ? DSNumber.groupedOrDash(chip.count) : nil,
                         clear: group.clear)
        }
        let order = all.first { $0.role == .order }?.rows.first { $0.isSelected(state) }?.title
        return AdminFilterSnapshot(items: items, orderTitle: order, result: resultCount(state),
                                   atReset: state == reset)
    }
}

/// ملخّص حالة مطبّقة: الشرائح المفعّلة، اسم الترتيب، عدد النتيجة
struct AdminFilterSnapshot<S> {
    struct Item: Identifiable {
        let id: String
        let groupTitle: String
        let title: String
        let count: String?
        let clear: (inout S) -> Void
    }
    let items: [Item]
    let orderTitle: String?
    let result: Int?
    /// على حالة «مسح الفلاتر» نفسها — لا زرّ مسح
    let atReset: Bool
}

// MARK: - النصوص

enum AdminFilterText {
    static var filters: String { L10n.t("الفلاتر", "Filters") }
    static var clear: String { L10n.t("مسح الفلاتر", "Clear filters") }
    static var resetDefaults: String { L10n.t("إعادة ضبط الفلاتر", "Reset filters") }
    static var cancel: String { L10n.t("إلغاء", "Cancel") }
    static var done: String { L10n.t("تم", "Done") }
    static var resultNow: String { L10n.t("النتيجة الآن:", "Results now:") }
    static var searchPlaceholder: String { L10n.t("ابحث بالاسم أو الرقم", "Search by name or number") }
    static var noResults: String { L10n.t("لا نتائج بهذه الفلاتر", "No results with these filters") }
    static var removeHint: String { L10n.t("يلغي الفلتر", "Removes the filter") }

    /// المعدود بعد الرقم: ١ «نتيجة»، ٢ «نتيجتان»، ٣–١٠ «نتائج»، ١١–٩٩ «نتيجةً»، وغيرها مفرد
    static func noun(_ n: Int, one: String, two: String, few: String, many: String) -> String {
        if n == 1 { return one }
        if n == 2 { return two }
        switch n % 100 {
        case 3...10: return few
        case 11...99: return many
        default: return one
        }
    }

    /// المعدود الافتراضي: «نتيجة»
    static func resultsNoun(_ n: Int) -> String {
        L10n.t(noun(n, one: "نتيجة", two: "نتيجتان", few: "نتائج", many: "نتيجةً"), n == 1 ? "result" : "results")
    }

    /// سهم «يفتح» (يسار في العربية) وسهم الرجوع (يمين في العربية)
    static var forwardChevron: String { L10n.isArabic ? "chevron.left" : "chevron.right" }
    static var backChevron: String { L10n.isArabic ? "chevron.right" : "chevron.left" }
}

// MARK: - شريط الفلاتر

/// سطر واحد أعلى القائمة: حقل البحث (يأخذ الباقي) + زرّ «الفلاتر» بعدده. من أحجام إمكانية الوصول: الزرّ تحت الحقل.
struct AdminFilterBar: View {
    @Binding var search: String
    var placeholder: String = AdminFilterText.searchPlaceholder
    let activeCount: Int
    let openFilters: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let field = DSSearchField(text: $search, placeholder: placeholder, style: .admin)
        let button = AdminFilterButton(activeCount: activeCount, action: openFilters)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                field
                button
            }
        } else {
            HStack(spacing: DS.Spacing.sm) {
                field
                button.fixedSize()
            }
        }
    }
}

/// زرّ «الفلاتر»: ٤٤، إطار `frameStroke`، رمز ذهبي النص، وكبسولة كحلية بالعدد حين يكون فلتر مفعّل (spec A.13)
struct AdminFilterButton: View {
    let activeCount: Int
    let action: () -> Void
    @Environment(\.dsSection) private var section

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xsm) {
                Image(systemName: "line.3.horizontal.decrease")
                    .dsGlyph(DS.Glyph.xl, weight: .medium)
                    .foregroundColor(DS.Color.accent)
                    .accessibilityHidden(true)
                Text(AdminFilterText.filters)
                    .dsFont(.callout)
                    .foregroundColor(DS.Color.textPrimary)
                if activeCount > 0 {
                    Text(verbatim: "\(activeCount)")
                        .dsFont(.sectionTitle)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textOnPrimary)
                        .padding(.horizontal, DS.Spacing.xsm)
                        .frame(minWidth: DS.Icon.section, minHeight: DS.Icon.section)
                        .background(Capsule().fill(section?.fill ?? DS.Color.primaryFill))
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .frame(minHeight: DS.Icon.tapTarget)
        }
        .buttonStyle(AdminFilterFieldButtonStyle())
        .accessibilityLabel(activeCount > 0
                            ? L10n.t("الفلاتر، \(activeCount) مفعّلة", "Filters, \(activeCount) on")
                            : AdminFilterText.filters)
        .accessibilityHint(L10n.t("يفتح لوحة الفلاتر", "Opens the filters"))
    }
}

// MARK: - الشرائح المفعّلة

/// شرائح الفلاتر المفعّلة تحت الشريط (spec A.9 الاستعمال ٢): ✓ + القيمة + عددها + ✕، تلتفّ ولا تتمرّر جانبياً.
/// لمس الشريحة يلغي فلترها فوراً (لا ورقة). لا شيء يُرسم بلا فلاتر.
struct AdminActiveFilterChips<S: Equatable>: View {
    let set: AdminFilterSet<S>
    @Binding var selection: S
    private let snapshot: AdminFilterSnapshot<S>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(set: AdminFilterSet<S>, selection: Binding<S>) {
        self.init(set: set, selection: selection, snapshot: set.snapshot(selection.wrappedValue))
    }

    init(set: AdminFilterSet<S>, selection: Binding<S>, snapshot: AdminFilterSnapshot<S>) {
        self.set = set
        self._selection = selection
        self.snapshot = snapshot
    }

    var body: some View {
        if !snapshot.items.isEmpty {
            DSChipFlow {
                ForEach(snapshot.items) { item in
                    Button {
                        var next = selection
                        item.clear(&next)
                        set.normalize(&next)
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(reduceMotion ? nil : DS.Anim.snappy) { selection = next }
                    } label: {
                        DSAdminChipLabel(title: item.title, count: item.count, selected: true, removable: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.count.map {
                        L10n.t("\(item.groupTitle): \(item.title)، \($0)", "\(item.groupTitle): \(item.title), \($0)")
                    } ?? L10n.t("\(item.groupTitle): \(item.title)", "\(item.groupTitle): \(item.title)"))
                    .accessibilityHint(AdminFilterText.removeHint)
                }
            }
            .transition(.opacity)
        }
    }
}

// MARK: - سطر الملخّص

/// سطر ٤٤ تحت الشرائح: «مسح الفلاتر» (كحلي، حين تختلف الحالة عن حالة المسح) في البداية، وفي الطرف «123 رجل · أبجدياً»
/// (١٣ رمادي والرقم شبه عريض بحبر النص). `note` كلمة ثابتة بعد الترتيب («الأقدم أولاً» حين لا مجموعة ترتيب).
struct AdminFilterCaption<S: Equatable>: View {
    let set: AdminFilterSet<S>
    @Binding var selection: S
    var note: String? = nil
    private let snapshot: AdminFilterSnapshot<S>
    @Environment(\.dsSection) private var section
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(set: AdminFilterSet<S>, selection: Binding<S>, note: String? = nil) {
        self.init(set: set, selection: selection, note: note, snapshot: set.snapshot(selection.wrappedValue))
    }

    init(set: AdminFilterSet<S>, selection: Binding<S>, note: String?, snapshot: AdminFilterSnapshot<S>) {
        self.set = set
        self._selection = selection
        self.note = note
        self.snapshot = snapshot
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    summary
                    resetButton
                }
            } else {
                HStack(spacing: DS.Spacing.sm) {
                    resetButton
                    Spacer(minLength: DS.Spacing.sm)
                    summary
                }
            }
        }
        .frame(minHeight: DS.Icon.tapTarget)
    }

    @ViewBuilder
    private var resetButton: some View {
        if !snapshot.atReset {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(reduceMotion ? nil : DS.Anim.snappy) { selection = set.reset }
            } label: {
                Text(set.resetTitle)
                    .dsFont(.button)
                    .foregroundColor(section?.ink ?? DS.Color.primary)
                    .frame(minHeight: DS.Icon.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var summary: some View {
        let number = Text(verbatim: snapshot.result.map { DSNumber.grouped($0) } ?? "—")
            .font(DS.Font.role(.sectionTitle))
            .foregroundColor(DS.Color.textPrimary)
        let tail = [snapshot.result.map { set.noun($0) }, snapshot.orderTitle.map { "· \($0)" }, note.map { "· \($0)" }]
            .compactMap { $0 }
            .joined(separator: " ")
        return (number + Text(verbatim: tail.isEmpty ? "" : " \(tail)"))
            .dsFont(.subtitle)
            .foregroundColor(DS.Color.textSecondary)
            .multilineTextAlignment(.leading)
            .accessibilityElement(children: .combine)
    }
}

// MARK: - اللوحة كاملة

/// الشريط + الشرائح + سطر الملخّص، وورقة الفلاتر. الحالات تُحسب مرة لكل رسم.
/// `openFilters`: nil = اللوحة تفتح ورقتها بنفسها؛ صفحة تضع اللوحة داخل `List` تمرّره وتضع `.adminFilterSheet` على
/// جذرها (صفّ القائمة الكسولة قد يُزال وورقته مفتوحة).
struct AdminFilterPanel<S: Equatable>: View {
    let set: AdminFilterSet<S>
    @Binding var selection: S
    @Binding var search: String
    var placeholder: String = AdminFilterText.searchPlaceholder
    var note: String? = nil
    var showsCaption: Bool = true
    var openFilters: (() -> Void)? = nil
    @State private var showsSheet = false

    var body: some View {
        let snapshot = set.snapshot(selection)
        VStack(alignment: .leading, spacing: 0) {
            AdminFilterBar(search: $search, placeholder: placeholder, activeCount: snapshot.items.count) {
                if let openFilters { openFilters() } else { showsSheet = true }
            }
            .padding(.bottom, snapshot.items.isEmpty ? 0 : DS.Spacing.xs)
            AdminActiveFilterChips(set: set, selection: $selection, snapshot: snapshot)
            if showsCaption {
                AdminFilterCaption(set: set, selection: $selection, note: note, snapshot: snapshot)
            }
        }
        .adminFilterSheet(isPresented: $showsSheet, set: set, selection: $selection)
    }
}

// MARK: - الحالة الفارغة بالفلاتر

/// «لا نتائج بهذه الفلاتر» + «مسح الفلاتر» (spec A.12) — بطاقة واحدة مكان القائمة
struct AdminFilterEmptyCard: View {
    var title: String = AdminFilterText.noResults
    var clearTitle: String = AdminFilterText.clear
    let onClear: () -> Void

    var body: some View {
        DSEmptyView(title, actionTitle: clearTitle, style: .card, action: onClear)
    }
}

// MARK: - الورقة

extension View {
    /// ورقة «الفلاتر» فوق هذه الصفحة: تنسخ `selection` معلّقاً، ولا تكتب فيه إلا بـ«تم»
    func adminFilterSheet<S: Equatable>(isPresented: Binding<Bool>, set: AdminFilterSet<S>,
                                        selection: Binding<S>) -> some View {
        modifier(AdminFilterSheetModifier(isPresented: isPresented, set: set, selection: selection))
    }
}

private struct AdminFilterSheetModifier<S: Equatable>: ViewModifier {
    @Binding var isPresented: Bool
    let set: AdminFilterSet<S>
    @Binding var selection: S
    @Environment(\.dsSection) private var section
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            // حارس المكدس (spec B.6): محتوى الورقة نوع مستقل خلف `AnyView`
            AnyView(AdminFilterSheet(set: set, selection: $selection, startsLarge: typeSize.isAccessibilitySize))
                .dsSection(section ?? AppSection.current)
        }
    }
}

/// ورقة «الفلاتر» (spec A.13، mock 5): نصف الشاشة تكبر للكاملة، مقبض، «إلغاء · الفلاتر · تم»، «النتيجة الآن: N» ثابت
/// تحت الرأس، المجموعات تتمرّر، و«مسح الفلاتر» آخرها. المنتقي (الفرع) يُدفع داخل مكدس الورقة.
struct AdminFilterSheet<S: Equatable>: View {
    let set: AdminFilterSet<S>
    @Binding var selection: S
    @State private var pending: S
    @State private var path: [String] = []
    @State private var detent: PresentationDetent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dsSection) private var section
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `startsLarge`: من أحجام إمكانية الوصول تفتح بالكامل (النصف لا يتّسع لمجموعة واحدة)
    init(set: AdminFilterSet<S>, selection: Binding<S>, startsLarge: Bool = false) {
        self.set = set
        self._selection = selection
        self._pending = State(initialValue: selection.wrappedValue)
        self._detent = State(initialValue: startsLarge ? .large : .medium)
    }

    private var ink: Color { section?.ink ?? DS.Color.primary }

    var body: some View {
        let styled = NavigationStack(path: $path) {
            root
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: String.self) { id in
                    pickerPage(id)
                }
        }
        .tint(ink)
        .background(DS.Hub.background.ignoresSafeArea())
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        if #available(iOS 16.4, *) {
            styled
                .presentationCornerRadius(DS.Radius.xxl)
                .presentationContentInteraction(.scrolls)
        } else {
            styled
        }
    }

    // MARK: الجذر

    private var root: some View {
        let groups = set.groups(pending)
        return VStack(spacing: 0) {
            navRow
            resultLine
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        groupSection(group)
                    }
                    resetButton
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.lg)
            }
        }
        .background(DS.Hub.background.ignoresSafeArea())
    }

    /// «إلغاء» (البداية) · «الفلاتر» (الوسط، ١٧ شبه عريض) · «تم» (الطرف، شبه عريض) — نصوص كحلية لا زرقاء
    private var navRow: some View {
        let cancel = Button(AdminFilterText.cancel) { dismiss() }
            .buttonStyle(AdminFilterTextButtonStyle(role: .callout, color: ink))
        let done = Button(AdminFilterText.done) { apply() }
            .buttonStyle(AdminFilterTextButtonStyle(role: .hubSection, color: ink))
        let title = Text(AdminFilterText.filters)
            .dsFont(.emptyTitle)
            .foregroundColor(DS.Color.textPrimary)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    HStack { cancel; Spacer(minLength: DS.Spacing.sm); done }
                    title.frame(maxWidth: .infinity)
                }
            } else {
                ZStack {
                    title.padding(.horizontal, DS.Icon.tapTarget * 2)
                    HStack { cancel; Spacer(minLength: DS.Spacing.sm); done }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        // تحت مقبض الورقة
        .padding(.top, DS.Spacing.md)
    }

    /// «النتيجة الآن: 123 رجل» — يتغيّر مع كل اختيار قبل «تم»
    private var resultLine: some View {
        let count = set.resultCount(pending)
        let number = Text(verbatim: count.map { DSNumber.grouped($0) } ?? "—")
            .font(DS.Font.role(.sectionTitle))
            .foregroundColor(DS.Color.textPrimary)
        let noun = count.map { Text(verbatim: " \(set.noun($0))") } ?? Text(verbatim: "")
        return (Text(verbatim: "\(AdminFilterText.resultNow) ") + number + noun)
            .dsFont(.subtitle)
            .foregroundColor(DS.Color.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xs)
            .accessibilityElement(children: .combine)
    }

    private func groupSection(_ group: AdminFilterGroup<S>) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            HStack(spacing: DS.Spacing.sm) {
                Text(group.title)
                    .dsFont(.label)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: DS.Spacing.sm)
                // صفّ المنتقي بلا «الكل» داخله (قائمة الفروع) — «مسح» في طرف عنوانه حين يكون مفعّلاً
                if group.pickerRow != nil, group.isActive(pending) {
                    Button(L10n.t("مسح", "Clear")) { pick(group.clear) }
                        .buttonStyle(AdminFilterTextButtonStyle(role: .chip, color: ink))
                        .accessibilityLabel(L10n.t("مسح فلتر \(group.title)", "Clear \(group.title) filter"))
                }
            }
            .padding(.horizontal, DS.Spacing.xxs)
            AdminFilterCard {
                if let picker = group.pickerRow {
                    pickerRow(group, picker)
                } else {
                    ForEach(group.rows) { row in
                        AdminFilterRadioRow(title: row.title,
                                            count: row.count,
                                            showsCount: group.showsCounts,
                                            isSelected: row.isSelected(pending),
                                            divider: row.id > 0) {
                            pick(row.select)
                        }
                    }
                }
            }
        }
        .padding(.top, DS.Hub.stackSpacing)
    }

    private func pickerRow(_ group: AdminFilterGroup<S>, _ picker: AdminFilterGroup<S>.PickerRow) -> some View {
        Button {
            path.append(group.id)
        } label: {
            HStack(spacing: DS.Spacing.smd) {
                Text(picker.valueTitle)
                    .dsFont(.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let count = picker.count {
                    Text(verbatim: DSNumber.grouped(count))
                        .dsFont(.subtitle)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textTertiary)
                }
                Image(systemName: AdminFilterText.forwardChevron)
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Hub.cardPadding)
            .padding(.vertical, DS.Spacing.sm)
            .frame(minHeight: DS.Hub.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(AdminFilterRowPressStyle())
        .accessibilityLabel(L10n.t("\(group.title): \(picker.valueTitle)", "\(group.title): \(picker.valueTitle)"))
        .accessibilityHint(L10n.t("يفتح القائمة", "Opens the list"))
    }

    /// «مسح الفلاتر» في الوسط أسفل المجموعات (GetYourGuide) — معطّل وهو على حالة المسح نفسها
    private var resetButton: some View {
        Button(set.resetTitle) { pick { $0 = set.reset } }
            .buttonStyle(AdminFilterTextButtonStyle(role: .callout, color: ink))
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Spacing.md)
            .disabled(pending == set.reset)
    }

    // MARK: المنتقي داخل الورقة

    @ViewBuilder
    private func pickerPage(_ id: String) -> some View {
        if let group = set.groups(pending).first(where: { $0.id == id }), let picker = group.pickerRow {
            let content = picker.destination(pending) { mutate in
                pick(mutate)
                path.removeAll()
            }
            if picker.ownsHeader {
                content
                    .toolbar(.hidden, for: .navigationBar)
            } else {
                VStack(spacing: 0) {
                    pushedHeader(group.title)
                    content
                }
                .background(DS.Hub.background.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    /// سطر الرجوع فوق منتقٍ بلا رأس: «‹ الفلاتر» في البداية واسم المجموعة في الوسط
    private func pushedHeader(_ title: String) -> some View {
        let back = Button {
            path.removeLast()
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: AdminFilterText.backChevron)
                    .dsGlyph(DS.Glyph.lg, weight: .semibold)
                    .accessibilityHidden(true)
                Text(AdminFilterText.filters)
                    .dsFont(.callout)
            }
            .foregroundColor(ink)
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("رجوع إلى الفلاتر", "Back to filters"))
        let heading = Text(title)
            .dsFont(.emptyTitle)
            .foregroundColor(DS.Color.textPrimary)
            .accessibilityAddTraits(.isHeader)
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) { back; heading }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ZStack {
                    heading.padding(.horizontal, DS.Icon.tapTarget * 2)
                    HStack { back; Spacer(minLength: 0) }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        // تحت مقبض الورقة
        .padding(.top, DS.Spacing.md)
    }

    // MARK: الأفعال

    /// اختيار في المعلّق: يُصلح الحالة، اهتزاز اختيار، ويقرأ القارئ الصوتي النتيجة الجديدة جملةً لا رقماً
    private func pick(_ mutate: (inout S) -> Void) {
        var next = pending
        mutate(&next)
        set.normalize(&next)
        guard next != pending else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? nil : DS.Anim.quick) { pending = next }
        guard UIAccessibility.isVoiceOverRunning else { return }
        let phrase = "\(AdminFilterText.resultNow) \(set.resultPhrase(set.resultCount(next)))"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            UIAccessibility.post(notification: .announcement, argument: phrase)
        }
    }

    /// «تم»: يكتب المعلّق في حالة الصفحة ثم يغلق
    private func apply() {
        if selection != pending { selection = pending }
        dismiss()
    }
}

// MARK: - البطاقة والصفّ (يستعملهما منتقٍ بسيط في صفحته أيضاً)

/// بطاقة صفوف الورقة: أبيض، خطّ ١ `DS.Hub.cardStroke`، زاوية ١٢، بلا ظلّ (spec A.5)
struct AdminFilterCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous)
        VStack(spacing: 0) {
            content
        }
        .background(DS.Color.cardBackground)
        .clipShape(shape)
        .overlay(shape.strokeBorder(DS.Hub.cardStroke, lineWidth: DS.Border.width))
    }
}

/// صفّ اختيار: `[الاسم ١٥][العدد رمادي][دائرة ٢٢]` (spec A.13). الصفر رمادي ويبقى قابلاً للاختيار، والعدد الذي لم
/// يُحمَّل «—». `divider`: خطّ رفيع فوقه يبدأ من النص.
struct AdminFilterRadioRow: View {
    let title: String
    var count: Int? = nil
    var showsCount: Bool = true
    let isSelected: Bool
    var divider: Bool = false
    let action: () -> Void

    var body: some View {
        let zero = showsCount && count == 0
        Button(action: action) {
            HStack(spacing: DS.Spacing.smd) {
                Text(title)
                    .dsFont(.body)
                    .foregroundColor(zero ? DS.Color.textTertiary : DS.Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsCount {
                    Text(verbatim: DSNumber.groupedOrDash(count))
                        .dsFont(.subtitle)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textTertiary)
                }
                AdminFilterRadio(isOn: isSelected)
            }
            .padding(.horizontal, DS.Hub.cardPadding)
            .padding(.vertical, DS.Spacing.sm)
            .frame(minHeight: DS.Hub.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(AdminFilterRowPressStyle())
        .overlay(alignment: .top) {
            if divider {
                Rectangle()
                    .fill(DS.Hub.cardStroke)
                    .frame(height: DS.Border.width)
                    .padding(.leading, DS.Hub.cardPadding)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(showsCount && count != nil
                            ? L10n.t("\(title)، \(DSNumber.grouped(count ?? 0))",
                                     "\(title), \(DSNumber.grouped(count ?? 0))")
                            : title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// دائرة الاختيار ٢٢: إطار رمادي، والمختارة حلقة سميكة بتعبئة القسم الكحلية
struct AdminFilterRadio: View {
    let isOn: Bool
    @Environment(\.dsSection) private var section

    var body: some View {
        let fill = section?.fill ?? DS.Color.primaryFill
        Circle()
            .strokeBorder(isOn ? fill : DS.Color.textTertiary,
                          lineWidth: isOn ? (DS.Hub.filterRadio - DS.Spacing.sm) / 2 : DS.Border.widthBold)
            .frame(width: DS.Hub.filterRadio, height: DS.Hub.filterRadio)
            .accessibilityHidden(true)
    }
}

// MARK: - أساليب الضغط

/// الصفّ: تظليل `DS.Hub.rowPress` في ١٠٠ م.ث، بلا تصغير (spec A.6/A.16)
private struct AdminFilterRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? DS.Hub.rowPress : Color.clear)
            .animation(DS.Hub.rowPressAnimation, value: configuration.isPressed)
    }
}

/// زرّ بشكل الحقل (زرّ «الفلاتر»): أبيض بإطار `frameStroke`، وتظليل عند الضغط
private struct AdminFilterFieldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        return configuration.label
            .background(shape.fill(configuration.isPressed ? DS.Hub.rowPress : DS.Color.surface))
            .overlay(shape.strokeBorder(DS.Hub.frameStroke, lineWidth: DS.Border.width))
            .contentShape(shape)
            .animation(DS.Hub.rowPressAnimation, value: configuration.isPressed)
    }
}

/// زرّ نصّ كحلي بلمس ٤٤ (إلغاء، تم، مسح الفلاتر) — يخفت عند الضغط ويبهت معطّلاً
private struct AdminFilterTextButtonStyle: ButtonStyle {
    let role: DS.TextRole
    let color: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .dsFont(role)
            .foregroundColor(isEnabled ? color : DS.Color.textTertiary)
            .opacity(configuration.isPressed ? DS.Opacity.disabled : 1)
            .frame(minWidth: DS.Icon.tapTarget, minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
            .animation(DS.Hub.rowPressAnimation, value: configuration.isPressed)
    }
}

// MARK: - المعاينة (٣ مجموعات: الحساب · الحالة · الفرع — أرقام «العائلة» في mock 5)

#if DEBUG
private struct AdminFilterPreviewState: Equatable {
    enum Account { case all, hasLogin, noLogin }
    enum Life { case all, living, deceased }
    var account: Account = .all
    var life: Life = .all
    var branch: String? = nil
}

private enum AdminFilterPreviewData {
    struct Cell {
        let branch: String
        let hasLogin: Bool
        let living: Bool
        let count: Int
    }

    /// ٢,٣٦٢ رجلاً: ١٢٣ لهم حساب (كلهم أحياء)، ٢,٢٣٩ بلا حساب — كما في mock 5
    static let cells: [Cell] = [
        Cell(branch: "فرع جاسم", hasLogin: true, living: true, count: 41),
        Cell(branch: "فرع جاسم", hasLogin: false, living: true, count: 612),
        Cell(branch: "فرع جاسم", hasLogin: false, living: false, count: 101),
        Cell(branch: "فرع محمد", hasLogin: true, living: true, count: 37),
        Cell(branch: "فرع محمد", hasLogin: false, living: true, count: 480),
        Cell(branch: "فرع محمد", hasLogin: false, living: false, count: 88),
        Cell(branch: "فرع عبدالله", hasLogin: true, living: true, count: 29),
        Cell(branch: "فرع عبدالله", hasLogin: false, living: true, count: 455),
        Cell(branch: "فرع عبدالله", hasLogin: false, living: false, count: 120),
        Cell(branch: "فرع عبدالعزيز يوسف عبدالرحمن", hasLogin: true, living: true, count: 16),
        Cell(branch: "فرع عبدالعزيز يوسف عبدالرحمن", hasLogin: false, living: true, count: 310),
        Cell(branch: "فرع عبدالعزيز يوسف عبدالرحمن", hasLogin: false, living: false, count: 73),
    ]

    static var branches: [String] {
        cells.reduce(into: [String]()) { if !$0.contains($1.branch) { $0.append($1.branch) } }
    }

    static func count(_ s: AdminFilterPreviewState) -> Int {
        cells.filter { cell in
            (s.account == .all || cell.hasLogin == (s.account == .hasLogin))
                && (s.life == .all || cell.living == (s.life == .living))
                && (s.branch == nil || cell.branch == s.branch)
        }
        .reduce(0) { $0 + $1.count }
    }

    static func with<V>(_ s: AdminFilterPreviewState, _ key: WritableKeyPath<AdminFilterPreviewState, V>,
                        _ value: V) -> AdminFilterPreviewState {
        var copy = s
        copy[keyPath: key] = value
        return copy
    }

    static let set = AdminFilterSet<AdminFilterPreviewState>(
        reset: AdminFilterPreviewState(),
        noun: { n in
            L10n.t(AdminFilterText.noun(n, one: "رجل", two: "رجلان", few: "رجال", many: "رجلاً"), n == 1 ? "man" : "men")
        },
        resultCount: { count($0) },
        groups: { s in
            let all = L10n.t("الكل", "All")
            return [
                .choices("account", title: L10n.t("الحساب", "Account"), value: \.account, all: .all, options: [
                    AdminFilterOption(.all, all, count: count(with(s, \.account, .all))),
                    AdminFilterOption(.hasLogin, L10n.t("لهم حساب", "Has an account"),
                                      count: count(with(s, \.account, .hasLogin))),
                    AdminFilterOption(.noLogin, L10n.t("بلا حساب", "No account"),
                                      count: count(with(s, \.account, .noLogin))),
                ]),
                .choices("life", title: L10n.t("الحالة", "Status"), value: \.life, all: .all, options: [
                    AdminFilterOption(.all, all, count: count(with(s, \.life, .all))),
                    AdminFilterOption(.living, L10n.t("الأحياء", "Living"), count: count(with(s, \.life, .living))),
                    AdminFilterOption(.deceased, L10n.t("المتوفون", "Deceased"),
                                      count: count(with(s, \.life, .deceased))),
                ]),
                .picker("branch", title: L10n.t("الفرع", "Branch"), value: \.branch, all: nil,
                        valueTitle: s.branch ?? L10n.t("كل الفروع", "All branches"),
                        count: s.branch == nil ? nil : count(s)) { current, pick in
                    AnyView(ScrollView {
                        AdminFilterCard {
                            ForEach(Array(branches.enumerated()), id: \.offset) { index, branch in
                                AdminFilterRadioRow(title: branch, count: count(with(s, \.branch, branch)),
                                                    isSelected: current == branch, divider: index > 0) {
                                    pick(branch)
                                }
                            }
                        }
                        .padding(DS.Spacing.lg)
                    })
                },
            ]
        })
}

/// صفحة تجريبية: «يحتاج مراجعتك» غائب، الشريط بفلترين مفعّلين كما في mock 4، والشرائح الملتفّة لصفّ فلتر بُعد واحد
private struct AdminFilterKitPreview: View {
    @State var selection = AdminFilterPreviewState(account: .hasLogin, life: .living)
    @State var search = ""
    @State var inline = 0
    var opensSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                AdminFilterPanel(set: AdminFilterPreviewData.set, selection: $selection, search: $search,
                                 note: L10n.t("أبجدياً", "A–Z"))
                DSFilterChips(options: [
                    DSFilterOption(id: 0, title: L10n.t("الكل", "All"), count: 48),
                    DSFilterOption(id: 1, title: L10n.t("يحتاج إجراء", "Needs action"), count: 6),
                    DSFilterOption(id: 2, title: L10n.t("نشاط الفريق", "Team activity"), count: 1_204),
                    DSFilterOption(id: 3, title: L10n.t("النظام", "System"), count: 3),
                ], selection: $inline, style: .admin)
                if AdminFilterPreviewData.count(selection) == 0 {
                    AdminFilterEmptyCard { selection = AdminFilterPreviewData.set.reset }
                }
            }
            .padding(DS.Spacing.lg)
        }
        .background(DS.Hub.background)
        .sheet(isPresented: .constant(opensSheet)) {
            AdminFilterSheet(set: AdminFilterPreviewData.set, selection: $selection)
        }
    }
}

#Preview("الفلاتر — RTL") {
    AdminFilterKitPreview()
        .dsSection(.admin)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
}

#Preview("ورقة الفلاتر — RTL") {
    AdminFilterKitPreview(opensSheet: true)
        .dsSection(.admin)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
}

#Preview("الفلاتر — AX3 داكن") {
    AdminFilterKitPreview()
        .dsSection(.admin)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.dynamicTypeSize, .accessibility3)
        .preferredColorScheme(.dark)
}

#Preview("ورقة الفلاتر — AX3") {
    AdminFilterSheet(set: AdminFilterPreviewData.set,
                     selection: .constant(AdminFilterPreviewState(life: .living)),
                     startsLarge: true)
        .dsSection(.admin)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
