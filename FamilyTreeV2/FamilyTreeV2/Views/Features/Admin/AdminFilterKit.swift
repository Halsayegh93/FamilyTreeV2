import Foundation
#if !ADMIN_LOGIC_TEST
import SwiftUI
import UIKit
#endif

// MARK: - طقم «تصفية» (إعادة تصميم الإدارة U5 — spec A.9/A.13، ثم F3 طلب المالك ٢٠٢٦-١١-٢٦)
//
// المالك: «غير اسم الفلاتر الى اسم رسمي او تقليدي» + «خل طريقة التصفية اختر من التصفية اي خيار و يتطبق على الاختيارات الى
// اخترتها و خل المسح التصفية حبة حبة من الى اخترتهم وتظهر تحت التصفية». فصار (F3):
//  - الاسم «تصفية» في كل مكان (كلمة الآيفون العربية): الزرّ «تصفية» بعدد الاختيارات، عنوان الورقة، «لا نتائج بهذه التصفية».
//  - اختيار متعدّد داخل المجموعة: أي عدد من الخيارات، والنتيجة ما يطابق أيّها (OR)، والمجموعات معاً (AND). بلا اختيار =
//    المجموعة مطفأة؛ «الكل» أول صفّ ويمسح مجموعته. مجموعات الترتيب («أبجدياً · الأحدث») اختيار واحد، وصفّ المنتقي (الفرع ←
//    `BranchPickerSheet`) اختيار واحد أيضاً (قائمة شجرية: الفرع يحوي فروعه، والمنتقي المشترك يختار ويُغلق).
//  - تطبيق فوري: كل لمسة في الورقة تكتب في حالة الصفحة مباشرة (لا نسخة معلّقة ولا «إلغاء») — «النتيجة الآن» والأعداد
//    والقائمة خلف الورقة تتغيّر معها. «تم» يُغلق، والسحب لأسفل يُغلق.
//  - تحت الشريط شريحة لكل خيار مختار: الاسم (`chipTitle ?? title`) + عدده + ✕ تزيله وحده. تلتفّ ولا تتمرّر جانبياً. لا
//    «مسح الكل» تحت الشريط ولا في الورقة. الاختيار الافتراضي (نساء العائلة «الحيّات»، الوارد «بانتظار قرارك» من رابط)
//    شريحة عادية تُزال.
//  - عدد كل خيار = النتيجة لو اختير وحده في مجموعته مع بقية الاختيارات (فالأعداد تتبع المجموعات الأخرى).
//
// السطر أعلى القائمة: حقل البحث + زرّ «تصفية» (`AdminFilterBar`) ← الشرائح (`AdminActiveFilterChips`) ← «123 رجل · أبجدياً»
// (`AdminFilterCaption`). الثلاثة معاً: `AdminFilterPanel`. الورقة: `AdminFilterSheet` (`.adminFilterSheet`).
//
// عامّ لكل صفحة (الوارد، رسائل الأعضاء، العائلة، نساء العائلة، تواريخ الوفاة): الصفحة تملك حالة اختياراتها بنوعها هي (`S`) —
// `Set` لكل مجموعة متعدّدة — وتطبّقها على قائمتها، وتعطي الطقم `AdminFilterSet<S>`: المجموعات وأعدادها لأي حالة، وعدد النتيجة
// لأي حالة. النموذج (هنا أولاً) Foundation وحده فيُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/f3-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminFilterKit.swift … tests/admin-redesign/F3/main.swift
//
// مراجع (spec §G): Sotheby's · Letterboxd · HotelTonight (عيّنة المالك)، وتطبيق «الصور»/«البريد» في الآيفون للاختيار المتعدّد
// (دائرة بعلامة ✓).

// MARK: - النموذج

#if ADMIN_LOGIC_TEST
/// وجهة المنتقي داخل الورقة — في فحص المنطق بلا SwiftUI أي قيمة
typealias AdminFilterDestination = Any
#else
/// وجهة المنتقي داخل الورقة (`BranchPickerSheet` خلف `AnyView`)
typealias AdminFilterDestination = AnyView
#endif

/// دور المجموعة في الورقة
enum AdminFilterRole {
    /// تصفية: كل خيار مختار شريحة تحت الشريط ويُعدّ في زرّ «تصفية»
    case filter
    /// ترتيب («أبجدياً · الأحدث»): اختيار واحد، لا يُعدّ ولا شريحة له — اسمه في سطر الملخّص («123 رجل · أبجدياً»)
    case order
}

/// خيار واحد في مجموعة: القيمة بنوع الصفحة، الاسم، والعدد (nil = لم يُحمَّل بعد ← «—»، والخيار يبقى قابلاً للاختيار)
struct AdminFilterOption<Value> {
    let value: Value
    let title: String
    var count: Int?
    /// اسم أقصر للشريحة تحت الشريط — nil = الاسم نفسه
    var chipTitle: String?

    init(_ value: Value, _ title: String, count: Int? = nil, chipTitle: String? = nil) {
        self.value = value
        self.title = title
        self.count = count
        self.chipTitle = chipTitle
    }
}

/// مجموعة في ورقة التصفية: صفوف اختيار بأعدادها — متعدّدة (`.choices`) أو واحدة (`.single`/`.order`) — أو صفّ يفتح منتقياً
/// (`.picker`). تُبنى لحالة بعينها (`AdminFilterSet.groups(s)`)، فالأعداد والأسماء لتلك الحالة.
struct AdminFilterGroup<S>: Identifiable {
    enum Selection {
        /// أي عدد من الخيارات (OR) — بلا اختيار = «الكل»
        case multiple
        /// خيار واحد — المحايد بين الخيارات («الكل»، أو الترتيب الافتراضي)
        case single
    }

    struct Row: Identifiable {
        let id: Int
        let title: String
        let count: Int?
        let isSelected: (S) -> Bool
        /// المتعدّدة: يضيف الخيار أو يزيله؛ الواحدة: يضعه
        let select: (inout S) -> Void
    }

    /// شريحة واحدة تحت الشريط — خيار مختار واحد، و✕ تزيله وحده
    struct Chip: Identifiable {
        let id: String
        let title: String
        let count: Int?
        let remove: (inout S) -> Void
    }

    /// صفّ واحد بسهم يدفع منتقياً داخل الورقة (الفرع: قائمة طويلة شجرية)
    struct PickerRow {
        /// اسم القيمة المختارة («فرع جاسم») — nil = لا اختيار (يُكتب `chooseTitle`)
        let valueTitle: String?
        /// «اختر فرعاً» حين لا اختيار
        let chooseTitle: String
        let count: Int?
        /// الوجهة ترسم رأسها و«إلغاءها» بنفسها (`BranchPickerSheet`) — وإلا يرسم الطقم سطر رجوع «‹ تصفية» فوقها
        let ownsHeader: Bool
        /// الوجهة للحالة الحالية، و`apply` يكتب الاختيار ويرجع للورقة
        let destination: (S, _ apply: @escaping ((inout S) -> Void) -> Void) -> AdminFilterDestination
    }

    let id: String
    let title: String
    let role: AdminFilterRole
    let selection: Selection
    let showsCounts: Bool
    /// «الكل» أول صفّ (المتعدّدة والمنتقي) — يمسح المجموعة، وعدده = النتيجة بلا هذه المجموعة (يحسبه الطقم).
    /// nil = المحايد أحد الخيارات نفسها (`.single`/`.order`)
    let allTitle: String?
    let rows: [Row]
    let pickerRow: PickerRow?
    /// مفعّلة = فيها اختيار (ليست على «الكل»/المحايد)
    let isActive: (S) -> Bool
    /// يرجع المجموعة لـ«الكل» (أو محايدها)
    let clear: (inout S) -> Void
    /// شريحة لكل خيار مختار — فارغة حين تكون المجموعة على «الكل»، ودائماً للترتيب
    let chips: (S) -> [Chip]
}

extension AdminFilterGroup {
    /// اختيار متعدّد (F3): أي عدد من `options`، والنتيجة ما يطابق أيّها. `values` مجموعة المختار في حالة الصفحة (فارغة =
    /// «الكل»). «الكل» يُرسم أول صفّ باسم `allTitle` ويمسح المجموعة. عدد كل خيار = النتيجة لو اختير وحده في مجموعته
    /// (الصفحة تحسبه)، وكل مختار شريحة بعدده. المختار غير الموجود في `options` لا شريحة له — الصفحة تُبقيه بين خياراتها.
    static func choices<Value: Hashable>(_ id: String, title: String, values: WritableKeyPath<S, Set<Value>>,
                                         allTitle: String = AdminFilterText.all,
                                         options: [AdminFilterOption<Value>],
                                         showsCounts: Bool = true) -> AdminFilterGroup<S> {
        let rows = options.enumerated().map { index, option in
            Row(id: index, title: option.title, count: option.count,
                isSelected: { $0[keyPath: values].contains(option.value) },
                select: { state in
                    if state[keyPath: values].contains(option.value) {
                        state[keyPath: values].remove(option.value)
                    } else {
                        state[keyPath: values].insert(option.value)
                    }
                })
        }
        return AdminFilterGroup(id: id, title: title, role: .filter, selection: .multiple, showsCounts: showsCounts,
                                allTitle: allTitle, rows: rows, pickerRow: nil,
                                isActive: { !$0[keyPath: values].isEmpty },
                                clear: { $0[keyPath: values] = [] },
                                chips: { state in
                                    let picked = state[keyPath: values]
                                    guard !picked.isEmpty else { return [] }
                                    return options.enumerated().compactMap { index, option in
                                        guard picked.contains(option.value) else { return nil }
                                        let value = option.value
                                        return Chip(id: "\(id).\(index)", title: option.chipTitle ?? option.title,
                                                    count: option.count,
                                                    remove: { $0[keyPath: values].remove(value) })
                                    }
                                })
    }

    /// اختيار واحد — `neutral` بين `options` («الكل»)، وما سواه شريحة. لمجموعة خياراتها قوائم منفصلة لا تجتمع
    /// (نساء العائلة «الفرع»: كل الفروع | فرع خارج العائلة)
    static func single<Value: Equatable>(_ id: String, title: String, value: WritableKeyPath<S, Value>, neutral: Value,
                                         options: [AdminFilterOption<Value>],
                                         showsCounts: Bool = true) -> AdminFilterGroup<S> {
        radio(id, title: title, role: .filter, value: value, neutral: neutral, options: options, showsCounts: showsCounts)
    }

    /// ترتيب القائمة — `standard` ترتيب الصفحة الافتراضي. اختيار واحد، بلا أعداد ولا شريحة
    static func order<Value: Equatable>(_ id: String, title: String, value: WritableKeyPath<S, Value>, standard: Value,
                                        options: [AdminFilterOption<Value>]) -> AdminFilterGroup<S> {
        radio(id, title: title, role: .order, value: value, neutral: standard, options: options, showsCounts: false)
    }

    /// اختيار واحد بالاسم القديم — صار `single` (F3: `choices` متعدّدة)
    @available(*, deprecated, message: "use .choices(values:) for multi-select or .single(neutral:); F3")
    static func choices<Value: Equatable>(_ id: String, title: String, value: WritableKeyPath<S, Value>, all: Value,
                                          options: [AdminFilterOption<Value>],
                                          showsCounts: Bool = true) -> AdminFilterGroup<S> {
        single(id, title: title, value: value, neutral: all, options: options, showsCounts: showsCounts)
    }

    /// صفّ يدفع منتقياً داخل الورقة (spec A.13: «الفرع» ← `BranchPickerSheet`) — اختيار واحد. البطاقة: «الكل» (`allTitle`،
    /// يمسح) ثم صفّ القيمة بسهم (`valueTitle`، أو `chooseTitle` حين لا اختيار). `destination` يرسم المنتقي ويستدعي `pick`
    /// بالقيمة المختارة (الطقم يكتبها ويرجع للورقة).
    static func picker<Value: Equatable>(_ id: String, title: String, value: WritableKeyPath<S, Value>, all: Value,
                                         allTitle: String, valueTitle: String?, chooseTitle: String,
                                         count: Int? = nil, ownsHeader: Bool = false,
                                         destination: @escaping (_ current: Value,
                                                                 _ pick: @escaping (Value) -> Void) -> AdminFilterDestination)
        -> AdminFilterGroup<S> {
        let row = PickerRow(valueTitle: valueTitle, chooseTitle: chooseTitle, count: count, ownsHeader: ownsHeader,
                            destination: { state, apply in
                                destination(state[keyPath: value]) { picked in
                                    apply { $0[keyPath: value] = picked }
                                }
                            })
        return AdminFilterGroup(id: id, title: title, role: .filter, selection: .single, showsCounts: count != nil,
                                allTitle: allTitle, rows: [], pickerRow: row,
                                isActive: { $0[keyPath: value] != all },
                                clear: { $0[keyPath: value] = all },
                                chips: { state in
                                    guard state[keyPath: value] != all, let valueTitle else { return [] }
                                    return [Chip(id: id, title: valueTitle, count: count,
                                                 remove: { $0[keyPath: value] = all })]
                                })
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
        return AdminFilterGroup(id: id, title: title, role: role, selection: .single, showsCounts: showsCounts,
                                allTitle: nil, rows: rows, pickerRow: nil,
                                isActive: { $0[keyPath: value] != neutral },
                                clear: { $0[keyPath: value] = neutral },
                                chips: { state in
                                    let current = state[keyPath: value]
                                    guard role == .filter, current != neutral,
                                          let option = options.first(where: { $0.value == current }) else { return [] }
                                    return [Chip(id: id, title: option.chipTitle ?? option.title, count: option.count,
                                                 remove: { $0[keyPath: value] = neutral })]
                                })
    }
}

/// كل ما تعطيه الصفحة للطقم. `S` حالة اختياراتها بنوعها هي (struct Equatable).
struct AdminFilterSet<S: Equatable> {
    /// المجموعات لحالة بعينها (الأعداد تتبع بقية اختيارات تلك الحالة؛ مجموعة تابعة مثل «النوع» تظهر بعد «المجموعة»)
    let groups: (S) -> [AdminFilterGroup<S>]
    /// عدد النتيجة لحالة بعينها — nil = لم يُحمَّل بعد («—»). الصفحة تقرّر إن كان يشمل نصّ البحث
    let resultCount: (S) -> Int?
    /// المعدود بعد الرقم بالعربية الصحيحة («رجل»، «طلباً»…) — `AdminFilterText.noun`
    let noun: (Int) -> String
    /// يُصلح الحالة بعد كل اختيار (مثل: نوع لم تعد مجموعته مختارة يُزال)
    let normalize: (inout S) -> Void

    init(noun: @escaping (Int) -> String = { AdminFilterText.resultsNoun($0) },
         normalize: @escaping (inout S) -> Void = { _ in },
         resultCount: @escaping (S) -> Int?,
         groups: @escaping (S) -> [AdminFilterGroup<S>]) {
        self.noun = noun
        self.normalize = normalize
        self.resultCount = resultCount
        self.groups = groups
    }

    /// كان «مسح الفلاتر» يرجع إلى `reset` — لا مسح للكل بعد F3، فلا يُستعمل
    @available(*, deprecated, message: "no clear-all after F3; drop reset:")
    init(reset: S,
         noun: @escaping (Int) -> String = { AdminFilterText.resultsNoun($0) },
         normalize: @escaping (inout S) -> Void = { _ in },
         resultCount: @escaping (S) -> Int?,
         groups: @escaping (S) -> [AdminFilterGroup<S>]) {
        self.init(noun: noun, normalize: normalize, resultCount: resultCount, groups: groups)
    }

    /// لمسة واحدة (صفّ في الورقة، ✕ شريحة، «الكل»): التغيير ثم الإصلاح
    func applying(_ mutate: (inout S) -> Void, to state: S) -> S {
        var next = state
        mutate(&next)
        normalize(&next)
        return next
    }

    /// عدد صفّ «الكل» في مجموعة = النتيجة لو مُسحت هذه المجموعة وحدها
    func allCount(_ group: AdminFilterGroup<S>, in state: S) -> Int? {
        resultCount(applying(group.clear, to: state))
    }

    /// عدد الاختيارات (شريحة لكل خيار مختار) — رقم زرّ «تصفية»
    func activeCount(_ state: S) -> Int {
        snapshot(state).items.count
    }

    /// «123 رجل» — «—» ما دام العدد لم يُحمَّل
    func resultPhrase(_ count: Int?) -> String {
        guard let count else { return "—" }
        return "\(AdminNumberText.grouped(count)) \(noun(count))"
    }

    /// ملخّص حالة واحدة لما تحت الشريط — يُحسب مرة لكل رسم (المجموعات قد تعدّ آلاف الأعضاء)
    func snapshot(_ state: S) -> AdminFilterSnapshot<S> {
        let all = groups(state)
        let items: [AdminFilterSnapshot<S>.Item] = all.flatMap { group -> [AdminFilterSnapshot<S>.Item] in
            guard group.role == .filter else { return [] }
            return group.chips(state).map { chip in
                .init(id: chip.id, groupTitle: group.title, title: chip.title,
                      count: group.showsCounts ? (chip.count.map { AdminNumberText.grouped($0) } ?? "—") : nil,
                      remove: chip.remove)
            }
        }
        let order = all.first { $0.role == .order }?.rows.first { $0.isSelected(state) }?.title
        return AdminFilterSnapshot(items: items, orderTitle: order, result: resultCount(state))
    }
}

/// ملخّص حالة: الشرائح (خيار مختار لكل واحدة)، اسم الترتيب، عدد النتيجة
struct AdminFilterSnapshot<S> {
    struct Item: Identifiable {
        let id: String
        let groupTitle: String
        let title: String
        let count: String?
        /// ✕ الشريحة — يزيل هذا الخيار وحده
        let remove: (inout S) -> Void
    }
    let items: [Item]
    let orderTitle: String?
    let result: Int?
}

// MARK: - النصوص (المكان الواحد)

enum AdminFilterText {
    /// الاسم الرسمي (طلب المالك ٢٠٢٦-١١-٢٦ «اسم رسمي او تقليدي» — كلمة الآيفون العربية): الزرّ وعنوان الورقة
    static var filters: String { L10n.t("تصفية", "Filter") }
    static var all: String { L10n.t("الكل", "All") }
    static var done: String { L10n.t("تم", "Done") }
    static var resultNow: String { L10n.t("النتيجة الآن:", "Results now:") }
    static var searchPlaceholder: String { L10n.t("ابحث بالاسم أو الرقم", "Search by name or number") }
    static var noResults: String { L10n.t("لا نتائج بهذه التصفية", "No results with this filter") }
    /// تحت «لا نتائج بهذه التصفية» — لا مسح للكل: الشرائح فوق تُزال واحدة واحدة
    static var noResultsHint: String {
        L10n.t("أزل اختياراً من الشرائح أعلاه، أو عدّل التصفية.", "Remove a choice from the chips above, or edit the filter.")
    }
    static var edit: String { L10n.t("تعديل التصفية", "Edit filter") }
    static var showAll: String { L10n.t("عرض الكل", "Show all") }
    static var removeHint: String { L10n.t("يزيل هذا الاختيار وحده", "Removes only this choice") }
    static var openHint: String { L10n.t("يفتح التصفية", "Opens the filter") }
    static var selected: String { L10n.t("محدّد", "Selected") }
    static var notSelected: String { L10n.t("غير محدّد", "Not selected") }
    static var addHint: String { L10n.t("يضيفه إلى التصفية", "Adds it to the filter") }
    static var dropHint: String { L10n.t("يزيله من التصفية", "Removes it from the filter") }

    /// «تصفية، 3 مفعّلة» — القارئ الصوتي على الزرّ
    static func on(_ n: Int) -> String { L10n.t("تصفية، \(n) مفعّلة", "Filter, \(n) on") }

    /// «الكل» في مجموعة متعدّدة: يلغي اختياراتها
    static func clearsGroup(_ group: String) -> String {
        L10n.t("يلغي اختيارات \(group)", "Clears the \(group) choices")
    }

    /// القارئ الصوتي بعد ✕ شريحة: «أُزيل بانتظار قرارك. النتيجة الآن: 12 طلباً»
    static func removed(_ title: String, result: String) -> String {
        L10n.t("أُزيل \(title). \(resultNow) \(result)", "Removed \(title). \(resultNow) \(result)")
    }

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

#if !ADMIN_LOGIC_TEST

// MARK: - شريط التصفية

/// سطر واحد أعلى القائمة: حقل البحث (يأخذ الباقي) + زرّ «تصفية» بعدده. من أحجام إمكانية الوصول: الزرّ تحت الحقل.
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

/// زرّ «تصفية»: ٤٤، إطار `frameStroke`، رمز ذهبي النص، وكبسولة كحلية بعدد الاختيارات (spec A.13)
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
        .accessibilityLabel(activeCount > 0 ? AdminFilterText.on(activeCount) : AdminFilterText.filters)
        .accessibilityHint(AdminFilterText.openHint)
    }
}

// MARK: - الشرائح تحت الشريط

/// شريحة لكل خيار مختار (spec A.9 الاستعمال ٢، F3): ✓ + الاسم + عدده + ✕، تلتفّ ولا تتمرّر جانبياً. لمس الشريحة يزيل
/// خيارها وحده فوراً (الباقي يبقى). لا شيء يُرسم بلا اختيار، ولا «مسح الكل».
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
                    Button { remove(item) } label: {
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

    private func remove(_ item: AdminFilterSnapshot<S>.Item) {
        let next = set.applying(item.remove, to: selection)
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? nil : DS.Anim.snappy) { selection = next }
        // الشريحة تختفي من تحت إصبع القارئ — يُقال ما حدث والنتيجة الجديدة
        guard UIAccessibility.isVoiceOverRunning else { return }
        let phrase = AdminFilterText.removed(item.title, result: set.resultPhrase(set.resultCount(next)))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            UIAccessibility.post(notification: .announcement, argument: phrase)
        }
    }
}

// MARK: - سطر الملخّص

/// سطر ٤٤ تحت الشرائح: «123 رجل · أبجدياً» (١٣ رمادي والرقم شبه عريض بحبر النص) في البداية تحت الشرائح. `note` كلمة
/// ثابتة بعد الترتيب («الأحدث أولاً» حين لا مجموعة ترتيب).
struct AdminFilterCaption<S: Equatable>: View {
    let set: AdminFilterSet<S>
    var note: String? = nil
    private let snapshot: AdminFilterSnapshot<S>

    init(set: AdminFilterSet<S>, state: S, note: String? = nil) {
        self.init(set: set, note: note, snapshot: set.snapshot(state))
    }

    init(set: AdminFilterSet<S>, note: String?, snapshot: AdminFilterSnapshot<S>) {
        self.set = set
        self.note = note
        self.snapshot = snapshot
    }

    var body: some View {
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
            .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

// MARK: - اللوحة كاملة

/// الشريط + الشرائح + سطر الملخّص، وورقة التصفية. الحالات تُحسب مرة لكل رسم.
/// `openFilters`: nil = اللوحة تفتح ورقتها بنفسها؛ صفحة تضع اللوحة داخل `List` (أو تفتح الورقة من بطاقة «لا نتائج») تمرّره
/// وتضع `.adminFilterSheet` على جذرها (صفّ القائمة الكسولة قد يُزال وورقته مفتوحة).
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
                AdminFilterCaption(set: set, note: note, snapshot: snapshot)
            }
        }
        .adminFilterSheet(isPresented: $showsSheet, set: set, selection: $selection)
    }
}

// MARK: - الحالة الفارغة بالتصفية

/// «لا نتائج بهذه التصفية» (spec A.12، F3) — بطاقة واحدة مكان القائمة. لا «مسح الكل»: الورقة تُفتح للتعديل، والشرائح فوق
/// تُزال واحدة واحدة. صفّ شرائح ببُعد واحد (`DSFilterChips`) يعطي «عرض الكل» = شريحة «الكل» نفسها.
struct AdminFilterEmptyCard: View {
    private let title: String
    private let message: String?
    private let actionTitle: String
    private let action: () -> Void

    /// صفحة بورقة التصفية: «تعديل التصفية» يفتح الورقة
    init(title: String = AdminFilterText.noResults, editFilters: @escaping () -> Void) {
        self.title = title
        message = AdminFilterText.noResultsHint
        actionTitle = AdminFilterText.edit
        action = editFilters
    }

    /// صفّ شرائح ببُعد واحد: «عرض الكل» يختار شريحة «الكل»
    init(title: String = AdminFilterText.noResults, showAll: @escaping () -> Void) {
        self.title = title
        message = nil
        actionTitle = AdminFilterText.showAll
        action = showAll
    }

    var body: some View {
        DSEmptyView(title, message: message, actionTitle: actionTitle, style: .card, action: action)
    }
}

// MARK: - الورقة

extension View {
    /// ورقة «تصفية» فوق هذه الصفحة — كل لمسة فيها تكتب في `selection` مباشرة (F3)
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

/// ورقة «تصفية» (spec A.13 بعد F3): نصف الشاشة تكبر للكاملة، مقبض، «تصفية» في الوسط و«تم» في الطرف، «النتيجة الآن: N»
/// ثابت تحت الرأس، والمجموعات تتمرّر. كل لمسة تُطبَّق فوراً على الصفحة (لا نسخة معلّقة ولا «إلغاء»)، و«تم» والسحب لأسفل
/// يغلقان. المنتقي (الفرع) يُدفع داخل مكدس الورقة.
struct AdminFilterSheet<S: Equatable>: View {
    let set: AdminFilterSet<S>
    @Binding var selection: S
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
        let state = selection
        let groups = set.groups(state)
        return VStack(spacing: 0) {
            navRow
            resultLine(state)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        groupSection(group, state: state)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.lg)
            }
        }
        .background(DS.Hub.background.ignoresSafeArea())
    }

    /// «تصفية» (الوسط، ١٧ شبه عريض) · «تم» (الطرف، شبه عريض، كحلي لا أزرق). لا «إلغاء» — كل لمسة طُبّقت
    private var navRow: some View {
        let done = Button(AdminFilterText.done) { dismiss() }
            .buttonStyle(AdminFilterTextButtonStyle(role: .hubSection, color: ink))
        let title = Text(AdminFilterText.filters)
            .dsFont(.emptyTitle)
            .foregroundColor(DS.Color.textPrimary)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    HStack { Spacer(minLength: DS.Spacing.sm); done }
                    title.frame(maxWidth: .infinity)
                }
            } else {
                ZStack {
                    title.padding(.horizontal, DS.Icon.tapTarget * 2)
                    HStack { Spacer(minLength: DS.Spacing.sm); done }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        // تحت مقبض الورقة
        .padding(.top, DS.Spacing.md)
    }

    /// «النتيجة الآن: 123 رجل» — يتغيّر مع كل لمسة (والقائمة خلف الورقة معه)
    private func resultLine(_ state: S) -> some View {
        let count = set.resultCount(state)
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

    private func groupSection(_ group: AdminFilterGroup<S>, state: S) -> some View {
        let multi = group.selection == .multiple
        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            Text(group.title)
                .dsFont(.label)
                .foregroundColor(DS.Color.textTertiary)
                .padding(.horizontal, DS.Spacing.xxs)
                .accessibilityAddTraits(.isHeader)
            AdminFilterCard {
                // «الكل» أول صفّ: يمسح المجموعة، وعدده النتيجة بلاها
                if let allTitle = group.allTitle {
                    AdminFilterRadioRow(title: allTitle,
                                        count: set.allCount(group, in: state),
                                        showsCount: group.showsCounts || group.pickerRow != nil,
                                        isSelected: !group.isActive(state),
                                        indicator: multi ? .check : .radio,
                                        hint: AdminFilterText.clearsGroup(group.title)) {
                        pick(group.clear)
                    }
                }
                if let picker = group.pickerRow {
                    pickerRow(group, picker, divider: group.allTitle != nil)
                } else {
                    ForEach(group.rows) { row in
                        AdminFilterRadioRow(title: row.title,
                                            count: row.count,
                                            showsCount: group.showsCounts,
                                            isSelected: row.isSelected(state),
                                            divider: row.id > 0 || group.allTitle != nil,
                                            indicator: multi ? .check : .radio) {
                            pick(row.select)
                        }
                    }
                }
            }
        }
        .padding(.top, DS.Hub.stackSpacing)
    }

    private func pickerRow(_ group: AdminFilterGroup<S>, _ picker: AdminFilterGroup<S>.PickerRow,
                           divider: Bool) -> some View {
        let chosen = picker.valueTitle
        return Button {
            path.append(group.id)
        } label: {
            HStack(spacing: DS.Spacing.smd) {
                Text(chosen ?? picker.chooseTitle)
                    .dsFont(.body)
                    .foregroundColor(chosen == nil ? DS.Color.textSecondary : DS.Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if chosen != nil, let count = picker.count {
                    Text(verbatim: DSNumber.grouped(count))
                        .dsFont(.subtitle)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textTertiary)
                }
                if chosen != nil {
                    AdminFilterRadio(isOn: true)
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
        .overlay(alignment: .top) {
            if divider { AdminFilterRowDivider() }
        }
        .accessibilityLabel(L10n.t("\(group.title): \(chosen ?? picker.chooseTitle)",
                                   "\(group.title): \(chosen ?? picker.chooseTitle)"))
        .accessibilityValue(chosen == nil ? AdminFilterText.notSelected : AdminFilterText.selected)
        .accessibilityHint(L10n.t("يفتح القائمة", "Opens the list"))
    }

    // MARK: المنتقي داخل الورقة

    @ViewBuilder
    private func pickerPage(_ id: String) -> some View {
        if let group = set.groups(selection).first(where: { $0.id == id }), let picker = group.pickerRow {
            let content = picker.destination(selection) { mutate in
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

    /// سطر الرجوع فوق منتقٍ بلا رأس: «‹ تصفية» في البداية واسم المجموعة في الوسط
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
        .accessibilityLabel(L10n.t("رجوع إلى التصفية", "Back to the filter"))
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

    /// لمسة في الورقة: تُطبَّق على الصفحة فوراً (بعد الإصلاح)، اهتزاز اختيار، ويقرأ القارئ الصوتي النتيجة الجديدة جملةً
    private func pick(_ mutate: (inout S) -> Void) {
        let next = set.applying(mutate, to: selection)
        guard next != selection else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? nil : DS.Anim.quick) { selection = next }
        guard UIAccessibility.isVoiceOverRunning else { return }
        let phrase = "\(AdminFilterText.resultNow) \(set.resultPhrase(set.resultCount(next)))"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            UIAccessibility.post(notification: .announcement, argument: phrase)
        }
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

/// صفّ اختيار: `[الاسم ١٥][العدد رمادي][علامة ٢٢]` (spec A.13). العلامة دائرة اختيار واحد (`.radio`) أو دائرة ✓ للاختيار
/// المتعدّد (`.check` — كتحديد «الصور» و«البريد»). الصفر رمادي ويبقى قابلاً للاختيار، والعدد الذي لم يُحمَّل «—».
/// `divider`: خطّ رفيع فوقه يبدأ من النص. القارئ الصوتي: المتعدّد «محدّد/غير محدّد» + «يضيفه/يزيله»، والواحد سمة «مختار».
struct AdminFilterRadioRow: View {
    enum Indicator { case radio, check }

    let title: String
    var count: Int? = nil
    var showsCount: Bool = true
    let isSelected: Bool
    var divider: Bool = false
    var indicator: Indicator = .radio
    /// تلميح القارئ الصوتي — nil = حسب العلامة
    var hint: String? = nil
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
                switch indicator {
                case .radio: AdminFilterRadio(isOn: isSelected)
                case .check: AdminFilterCheck(isOn: isSelected)
                }
            }
            .padding(.horizontal, DS.Hub.cardPadding)
            .padding(.vertical, DS.Spacing.sm)
            .frame(minHeight: DS.Hub.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(AdminFilterRowPressStyle())
        .overlay(alignment: .top) {
            if divider { AdminFilterRowDivider() }
        }
        .accessibilityLabel(showsCount && count != nil
                            ? L10n.t("\(title)، \(DSNumber.grouped(count ?? 0))",
                                     "\(title), \(DSNumber.grouped(count ?? 0))")
                            : title)
        .modifier(AdminFilterRowAccessibility(indicator: indicator, isSelected: isSelected, hint: hint))
    }
}

/// المتعدّد: قيمة «محدّد/غير محدّد» نصّاً (لا سمة «مختار» فيتكرّر)، وتلميح الإضافة أو الإزالة؛ الواحد: سمة «مختار»
private struct AdminFilterRowAccessibility: ViewModifier {
    let indicator: AdminFilterRadioRow.Indicator
    let isSelected: Bool
    let hint: String?

    func body(content: Content) -> some View {
        switch indicator {
        case .check:
            content
                .accessibilityValue(isSelected ? AdminFilterText.selected : AdminFilterText.notSelected)
                .accessibilityHint(hint ?? (isSelected ? AdminFilterText.dropHint : AdminFilterText.addHint))
        case .radio:
            content
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(hint ?? "")
        }
    }
}

/// خطّ رفيع فوق الصفّ يبدأ من النص
private struct AdminFilterRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.Hub.cardStroke)
            .frame(height: DS.Border.width)
            .padding(.leading, DS.Hub.cardPadding)
            .accessibilityHidden(true)
    }
}

/// دائرة الاختيار الواحد ٢٢: إطار رمادي، والمختارة حلقة سميكة بتعبئة القسم الكحلية
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

/// دائرة الاختيار المتعدّد ٢٢ (F3): إطار رمادي فارغة، والمختارة ممتلئة بتعبئة القسم وعلامة ✓ بيضاء — الشكل لا اللون وحده
struct AdminFilterCheck: View {
    let isOn: Bool
    @Environment(\.dsSection) private var section

    var body: some View {
        let fill = section?.fill ?? DS.Color.primaryFill
        ZStack {
            if isOn {
                Circle().fill(fill)
                Image(systemName: "checkmark")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(DS.Color.textOnPrimary)
            } else {
                Circle().strokeBorder(DS.Color.textTertiary, lineWidth: DS.Border.widthBold)
            }
        }
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

/// زرّ بشكل الحقل (زرّ «تصفية»): أبيض بإطار `frameStroke`، وتظليل عند الضغط
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

/// زرّ نصّ كحلي بلمس ٤٤ («تم») — يخفت عند الضغط ويبهت معطّلاً
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

// MARK: - المعاينة (٣ مجموعات: الحساب · الحالة متعدّدتان · الفرع منتقٍ — أرقام «العائلة» في mock 5)

#if DEBUG
private struct AdminFilterPreviewState: Equatable {
    enum Account: Hashable { case hasLogin, noLogin }
    enum Life: Hashable { case living, deceased }
    var accounts: Set<Account> = []
    var lives: Set<Life> = []
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
            (s.accounts.isEmpty || s.accounts.contains(cell.hasLogin ? .hasLogin : .noLogin))
                && (s.lives.isEmpty || s.lives.contains(cell.living ? .living : .deceased))
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
        noun: { n in
            L10n.t(AdminFilterText.noun(n, one: "رجل", two: "رجلان", few: "رجال", many: "رجلاً"), n == 1 ? "man" : "men")
        },
        resultCount: { count($0) },
        groups: { s in
            [
                .choices("account", title: L10n.t("الحساب", "Account"), values: \.accounts, options: [
                    AdminFilterOption(.hasLogin, L10n.t("لهم حساب", "Has an account"),
                                      count: count(with(s, \.accounts, [.hasLogin]))),
                    AdminFilterOption(.noLogin, L10n.t("بلا حساب", "No account"),
                                      count: count(with(s, \.accounts, [.noLogin]))),
                ]),
                .choices("life", title: L10n.t("الحالة", "Status"), values: \.lives, options: [
                    AdminFilterOption(.living, L10n.t("الأحياء", "Living"), count: count(with(s, \.lives, [.living]))),
                    AdminFilterOption(.deceased, L10n.t("المتوفون", "Deceased"),
                                      count: count(with(s, \.lives, [.deceased]))),
                ]),
                .picker("branch", title: L10n.t("الفرع", "Branch"), value: \.branch, all: nil,
                        allTitle: L10n.t("كل الفروع", "All branches"), valueTitle: s.branch,
                        chooseTitle: L10n.t("اختر فرعاً", "Pick a branch"),
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

/// صفحة تجريبية: الشريط بثلاثة اختيارات (شريحة لكل واحد)، والشرائح الملتفّة لصفّ تصفية ببُعد واحد
private struct AdminFilterKitPreview: View {
    @State var selection = AdminFilterPreviewState(accounts: [.hasLogin], lives: [.living, .deceased])
    @State var search = ""
    @State var inline = 0
    @State var opensSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                AdminFilterPanel(set: AdminFilterPreviewData.set, selection: $selection, search: $search,
                                 note: L10n.t("أبجدياً", "A–Z"), openFilters: { opensSheet = true })
                DSFilterChips(options: [
                    DSFilterOption(id: 0, title: L10n.t("الكل", "All"), count: 48),
                    DSFilterOption(id: 1, title: L10n.t("يحتاج إجراء", "Needs action"), count: 6),
                    DSFilterOption(id: 2, title: L10n.t("نشاط الفريق", "Team activity"), count: 1_204),
                    DSFilterOption(id: 3, title: L10n.t("النظام", "System"), count: 3),
                ], selection: $inline, style: .admin)
                if AdminFilterPreviewData.count(selection) == 0 {
                    AdminFilterEmptyCard(editFilters: { opensSheet = true })
                }
            }
            .padding(DS.Spacing.lg)
        }
        .background(DS.Hub.background)
        .adminFilterSheet(isPresented: $opensSheet, set: AdminFilterPreviewData.set, selection: $selection)
    }
}

#Preview("تصفية — RTL") {
    AdminFilterKitPreview()
        .dsSection(.admin)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
}

#Preview("ورقة تصفية — RTL") {
    AdminFilterKitPreview(opensSheet: true)
        .dsSection(.admin)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
}

#Preview("تصفية — AX3 داكن") {
    AdminFilterKitPreview()
        .dsSection(.admin)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.dynamicTypeSize, .accessibility3)
        .preferredColorScheme(.dark)
}
#endif

#endif
