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

/// صف اختيار تاريخ موحّد — يعرض التاريخ المختار، وعند الضغط يفتح شيت سفلي للاختيار.
/// استخدم هذا في كل التطبيق بدل عرض العجلة مضمّنة.
struct DSDateField: View {
    let label: String
    @Binding var date: Date
    var icon: String = "calendar"
    var iconColor: Color = DS.Color.accent
    var range: PartialRangeThrough<Date>? = nil
    /// نمط مدمج لصفوف الـ Form (أيقونة SF صغيرة بدل DSIcon الكبيرة)
    var compact: Bool = false

    @State private var showSheet = false

    private var formatted: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isArabic ? "ar" : "en_US")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        Button {
            showSheet = true
        } label: {
            if compact {
                HStack {
                    Label(label, systemImage: icon)
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textPrimary)
                    Spacer()
                    Text(formatted)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                }
                .contentShape(Rectangle())
            } else {
                HStack(spacing: DS.Spacing.md) {
                    DSIcon(icon, color: iconColor)
                    Text(label)
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textPrimary)
                    Spacer()
                    Text(formatted)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            DSDatePickerSheet(
                selection: $date,
                isPresented: $showSheet,
                in: range,
                title: label
            )
        }
    }
}
