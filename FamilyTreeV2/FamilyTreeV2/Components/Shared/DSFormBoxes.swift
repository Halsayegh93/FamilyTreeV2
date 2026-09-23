import SwiftUI

// ════════════════════════════════════════════════════════════════════
// بطاقات النماذج وحقولها — تصميم «التعديل المباشر» (طلب المالك، 2026-09-23)
// بطاقة لكل قسم، وكل حقل داخل مربّع بإطار. تستخدمها «إدارة السجل»
// و«إضافة ابن / تعديل الابن».
// ════════════════════════════════════════════════════════════════════

/// بطاقة قسم: أيقونة ملوّنة + عنوان (+ عنصر اختياري في الطرف)، ثم المحتوى
struct DSFormCard<Content: View, Trailing: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    init(_ title: String, icon: String, color: Color,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.color = color
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(DS.Font.plex(12, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(DS.Font.plex(15, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Spacer(minLength: 0)
                trailing()
            }
            content()
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
    }
}

/// إطار المربّع الموحّد للحقول داخل البطاقات
struct DSFieldChrome: ViewModifier {
    var minHeight: CGFloat = 46
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DS.Spacing.md)
            .frame(minHeight: minHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.background, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.textTertiary.opacity(0.18), lineWidth: 1)
            )
    }
}

extension View {
    /// يضع المحتوى داخل مربّع الحقل الموحّد
    func dsFieldChrome(minHeight: CGFloat = 46) -> some View {
        modifier(DSFieldChrome(minHeight: minHeight))
    }
}

/// حقل داخل مربّع — عنوان صغير فوقه، والمُدخل داخل صندوق بإطار
struct DSFieldBox<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(DS.Font.plex(12.5, weight: .semibold))
                .foregroundColor(DS.Color.textPrimary.opacity(0.78))
            content()
                .font(DS.Font.plex(14.5))
                .foregroundColor(DS.Color.textPrimary)
                .dsFieldChrome()
        }
    }
}

/// مفتاح (تشغيل/إيقاف) داخل مربّع
struct DSToggleBox: View {
    let title: String
    @Binding var isOn: Bool
    var tint: Color = DS.Color.primary

    var body: some View {
        Toggle(isOn: $isOn.animation(DS.Anim.snappy)) {
            Text(title)
                .font(DS.Font.plex(14, weight: .medium))
                .foregroundColor(DS.Color.textPrimary)
        }
        .tint(tint)
        .dsFieldChrome()
    }
}

/// عنوان صغير فوق عنصر (مثل مبدّل الجنس) بنفس نمط عناوين الحقول
struct DSFieldLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(DS.Font.plex(12.5, weight: .semibold))
            .foregroundColor(DS.Color.textPrimary.opacity(0.78))
    }
}

// MARK: - التواريخ: صف للقراءة + مربّع اختيار بالمنتصف (طلب المالك)

enum DSDateText {
    /// «23 سبتمبر 2026» — نفس عرض تاريخ الميلاد في تعديل البيانات
    static func display(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar" : "en_US")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
    }
}

/// صف تاريخ داخل مربّع: العنوان فوق، والتاريخ (أو «لم يُحدَّد») مع قلم التعديل
struct DSDateRow: View {
    let title: String
    let date: Date?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DSFieldLabel(text: title)
            Button(action: action) {
                HStack(spacing: DS.Spacing.sm) {
                    Text(date.map(DSDateText.display) ?? L10n.t("بدون تاريخ", "No date"))
                        .font(DS.Font.plex(14.5, weight: date == nil ? .regular : .semibold))
                        .foregroundColor(date == nil ? DS.Color.textTertiary : DS.Color.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "pencil")
                        .font(DS.Font.plex(13, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(DS.Color.primary.opacity(0.10)))
                }
                .dsFieldChrome(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// مربّع اختيار تاريخ بمنتصف الشاشة — «حفظ» يمين و«إلغاء» يسار (قاعدة التطبيق).
/// `onClear` اختياري: يُظهر «بدون تاريخ» لمسح التاريخ.
struct DSDateCard: View {
    let title: String
    let initial: Date
    let onCancel: () -> Void
    let onDone: (Date) -> Void
    var onClear: (() -> Void)? = nil

    @State private var date: Date = Date()

    var body: some View {
        DSCenterCard(onBackgroundTap: onCancel) {
            Text(title)
                .font(DS.Font.plex(17, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
                .frame(maxWidth: .infinity)

            DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .environment(\.locale, LanguageManager.shared.locale)

            if let onClear {
                Button(action: onClear) {
                    Label(L10n.t("بدون تاريخ", "No date"), systemImage: "calendar.badge.minus")
                        .font(DS.Font.plex(13.5, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md)
                            .strokeBorder(DS.Color.textTertiary.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(DSScaleButtonStyle())
            }

            HStack(spacing: DS.Spacing.sm) {
                Button { onDone(date) } label: {
                    Text(L10n.t("حفظ", "Save"))
                        .font(DS.Font.plex(14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.primary))
                }
                Button(action: onCancel) {
                    Text(L10n.t("إلغاء", "Cancel"))
                        .font(DS.Font.plex(14, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.mutedBackground.opacity(0.8)))
                }
            }
            .buttonStyle(DSScaleButtonStyle())
        }
        .onAppear { date = initial }
    }
}

/// يعرض مربّع التاريخ في نافذة المربّعات (فوق كل شيء)
@MainActor
func dsPresentDatePicker(title: String, initial: Date?, allowClear: Bool,
                         onPick: @escaping (Date?) -> Void) {
    var id: UUID?
    let close: () -> Void = { if let i = id { DSPopupPresenter.shared.hide(i) } }
    id = DSPopupPresenter.shared.show(
        DSDateCard(
            title: title,
            initial: initial ?? Date(),
            onCancel: close,
            onDone: { picked in close(); onPick(picked) },
            onClear: allowClear ? { close(); onPick(nil) } : nil
        )
    )
}

// MARK: - حقول الميلاد ← متوفّى ← الوفاة (طلب المالك)

/// الميلاد وحالة الوفاة وتاريخ الوفاة — كل حقل في مربّعه.
/// «متوفّى» بلون مميّز، و«بدون تاريخ» زر داخل صف التاريخ نفسه.
struct DSLifeDatesBox: View {
    @Binding var hasBirthDate: Bool
    @Binding var birthDate: Date
    @Binding var isDeceased: Bool
    @Binding var hasDeathDate: Bool
    @Binding var deathDate: Date
    var deceasedTitle: String = L10n.t("متوفّى", "Deceased")

    /// رمادي هادئ لحالة الوفاة (طلب المالك)
    private let deceasedTint = DS.Color.textSecondary

    var body: some View {
        // كل حقل في مربّع منفصل (طلب المالك)
        VStack(spacing: DS.Spacing.sm) {
            dateRow(icon: "gift.fill", tint: DS.Color.warning,
                    title: L10n.t("تاريخ الميلاد", "Birth Date"),
                    has: $hasBirthDate, date: $birthDate)
                .modifier(BoxChrome(fill: DS.Color.background, stroke: DS.Color.textTertiary.opacity(0.18)))

            // «متوفّى» — لون مميّز
            Toggle(isOn: $isDeceased.animation(DS.Anim.snappy)) {
                HStack(spacing: DS.Spacing.sm) {
                    rowIcon("heart.text.square.fill", tint: deceasedTint)
                    Text(deceasedTitle)
                        .font(DS.Font.plex(14.5, weight: .bold))
                        .foregroundColor(deceasedTint)
                }
            }
            .tint(deceasedTint)
            .padding(.horizontal, DS.Spacing.md)
            .frame(minHeight: 52)
            .modifier(BoxChrome(fill: deceasedTint.opacity(isDeceased ? 0.14 : 0.07),
                                stroke: deceasedTint.opacity(0.35)))

            if isDeceased {
                dateRow(icon: "calendar.badge.minus", tint: deceasedTint,
                        title: L10n.t("تاريخ الوفاة", "Death Date"),
                        has: $hasDeathDate, date: $deathDate)
                    .modifier(BoxChrome(fill: DS.Color.background, stroke: DS.Color.textTertiary.opacity(0.18)))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private struct BoxChrome: ViewModifier {
        let fill: Color
        let stroke: Color
        func body(content: Content) -> some View {
            content
                .background(fill, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                )
        }
    }

    private func rowIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(DS.Font.plex(12, weight: .bold))
            .foregroundColor(tint)
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// صف تاريخ: العنوان والقيمة، ثم زر «بدون تاريخ» وقلم التعديل داخل الصف
    private func dateRow(icon: String, tint: Color, title: String,
                         has: Binding<Bool>, date: Binding<Date>) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            rowIcon(icon, tint: tint)

            Button { pick(title: title, has: has, date: date) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.Font.plex(12.5, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                    Text(has.wrappedValue ? DSDateText.display(date.wrappedValue)
                                          : L10n.t("بدون تاريخ", "No date"))
                        .font(DS.Font.plex(14, weight: has.wrappedValue ? .semibold : .regular))
                        .foregroundColor(has.wrappedValue ? DS.Color.textPrimary : DS.Color.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // «بدون تاريخ» — زر داخل صف التاريخ (يُبرَز إذا لا تاريخ)
            Button {
                withAnimation(DS.Anim.snappy) { has.wrappedValue = false }
            } label: {
                Text(L10n.t("بدون تاريخ", "No date"))
                    .font(DS.Font.plex(11.5, weight: .bold))
                    .foregroundColor(has.wrappedValue ? DS.Color.textSecondary : .white)
                    .padding(.horizontal, DS.Spacing.sm + 2)
                    .frame(height: 30)
                    .background(
                        Capsule().fill(has.wrappedValue ? DS.Color.mutedBackground.opacity(0.7)
                                                        : DS.Color.textSecondary)
                    )
            }
            .buttonStyle(DSScaleButtonStyle())

            Button { pick(title: title, has: has, date: date) } label: {
                Image(systemName: has.wrappedValue ? "pencil" : "plus")
                    .font(DS.Font.plex(13, weight: .bold))
                    .foregroundColor(DS.Color.primary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Color.primary.opacity(0.10)))
            }
            .buttonStyle(DSScaleButtonStyle())
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(minHeight: 58)
    }

    private func pick(title: String, has: Binding<Bool>, date: Binding<Date>) {
        dsPresentDatePicker(title: title,
                            initial: has.wrappedValue ? date.wrappedValue : nil,
                            allowClear: false) { picked in
            guard let picked else { return }
            date.wrappedValue = picked
            has.wrappedValue = true
        }
    }
}

// MARK: - الجنس: بطاقتان بأيقونة بدل المبدّل (طلب المالك)

struct DSGenderPicker: View {
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DSFieldLabel(text: L10n.t("الجنس", "Gender"))
            HStack(spacing: DS.Spacing.sm) {
                option("male", title: L10n.t("ذكر", "Male"),
                       icon: "figure.stand", tint: DS.Color.primary)
                option("female", title: L10n.t("أنثى", "Female"),
                       icon: "figure.stand.dress", tint: DS.Color.likeAction)
            }
        }
    }

    private func option(_ value: String, title: String, icon: String, tint: Color) -> some View {
        let selected = selection == value
        return Button {
            withAnimation(DS.Anim.snappy) { selection = value }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(DS.Font.plex(16, weight: .bold))
                Text(title)
                    .font(DS.Font.plex(14.5, weight: .bold))
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(DS.Font.plex(15, weight: .semibold))
            }
            .foregroundColor(selected ? tint : DS.Color.textSecondary)
            .padding(.horizontal, DS.Spacing.md)
            .frame(height: 50)
            .background(selected ? tint.opacity(0.12) : DS.Color.background,
                        in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(selected ? tint.opacity(0.55) : DS.Color.textTertiary.opacity(0.18),
                            lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
