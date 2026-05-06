import SwiftUI

/// شيت اختيار التاريخ — يرتفع من أسفل الشاشة، لا يُطبّق التاريخ إلا عند الضغط على "تأكيد"
struct DSDatePickerSheet: View {
    @Binding var selection: Date
    @Binding var isPresented: Bool
    let range: PartialRangeThrough<Date>?
    let title: String

    @State private var tempDate: Date

    init(
        selection: Binding<Date>,
        isPresented: Binding<Bool>,
        in range: PartialRangeThrough<Date>? = nil,
        title: String = ""
    ) {
        self._selection = selection
        self._isPresented = isPresented
        self.range = range
        self.title = title
        self._tempDate = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            DSSheetHeader(
                title: title,
                isLoading: false,
                showBackground: false,
                onCancel: { isPresented = false },
                onConfirm: {
                    selection = tempDate
                    isPresented = false
                }
            )

            Group {
                if let range {
                    DatePicker("", selection: $tempDate, in: range, displayedComponents: .date)
                } else {
                    DatePicker("", selection: $tempDate, displayedComponents: .date)
                }
            }
            .datePickerStyle(.wheel)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: L10n.isArabic ? "ar" : "en_US"))
            .frame(maxWidth: .infinity)
        }
        .presentationDetents([.height(320)])
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}
