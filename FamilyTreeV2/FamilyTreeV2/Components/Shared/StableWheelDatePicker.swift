import SwiftUI

/// عجلة تاريخ مستقرة — لا تسبب ScrollView auto-scroll.
///
/// الحيلة: نحطها داخل ScrollView معطّل، فـ iOS يحسب إن العجلة موجودة في scroll container
/// خاص بها، وما يعمل auto-scroll للـ parent ScrollView أثناء اللف.
///
/// استخدام:
/// ```swift
/// StableWheelDatePicker(selection: $birthDate, in: ...Date())
/// ```
struct StableWheelDatePicker: View {
    @Binding var selection: Date
    let range: PartialRangeThrough<Date>?
    let height: CGFloat

    init(
        selection: Binding<Date>,
        in range: PartialRangeThrough<Date>? = nil,
        height: CGFloat = 180
    ) {
        self._selection = selection
        self.range = range
        self.height = height
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                if let range {
                    DatePicker("", selection: $selection, in: range, displayedComponents: .date)
                } else {
                    DatePicker("", selection: $selection, displayedComponents: .date)
                }
            }
            .datePickerStyle(.wheel)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: L10n.isArabic ? "ar" : "en_US"))
            .frame(maxWidth: .infinity)
        }
        .scrollDisabled(true)
        .frame(height: height)
    }
}
