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

    /// الكحلي (الافتراضي) يتبع لون القسم — وألوان المعاني كما هي
    @Environment(\.dsSection) private var section

    // نفس شكل أقسام مربّعات الإضافة (DSComposerSection) — تصميم موحّد (طلب المالك)
    var body: some View {
        let c = color.dsChrome(in: section).dsReadableGlyph
        return VStack(alignment: .leading, spacing: DS.Spacing.sm + DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.xsm + 1) {
                DSStateIcon(icon, tint: c, size: DS.Icon.section, mapsChrome: false)
                Text(title)
                    .dsFont(.sectionTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                Spacer(minLength: 0)
                trailing()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // البطاقة الواحدة (زواياها من `DS.Card` — كانت ١٦) بحشوة الصفحات
        .dsCard(padding: DS.Spacing.md)
    }
}

// MARK: - خط الحقول داخل المربّعات بالمنتصف (طلب المالك ٢٠٢٦-١٠-٠١)
// «بكل المربعات بالمنتصف نبي نخلي بيانات الحقول شوي اقل و قيمة الحقول ايضا»:
// المربّع يعلن أنه مربّع (`dsInCenterBox`)، فعناوين الحقول وقيمها بداخله أصغر بنقطة.
// الصفحات لا تتأثر — نفس أحجامها السابقة.

private struct DSInCenterBoxKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// داخل مربّع بالمنتصف (الإضافة والتعديل والتفاصيل والتنبيهات)
    var dsInCenterBox: Bool {
        get { self[DSInCenterBoxKey.self] }
        set { self[DSInCenterBoxKey.self] = newValue }
    }
}

enum DSFieldFont {
    /// كم تصغر عناوين الحقول وقيمها داخل المربّعات — ٠: مقاسات Apple الافتراضية في كل مكان
    /// (طلب المالك ٢٠٢٦-١٠-٠٨ «حجم الخط الافتراضي في الآيفون»؛ كانت ٢ ثم ١)
    static let boxReduction: CGFloat = 0
}

/// صناديق الحقول داخل المربّعات أصغر قليلاً أيضاً (طلب المالك: «وحتى المربعات بعد شوي»)
/// الأرقام نفسها في `DSBox` (مكان واحد لهيكل المربّعات) — هذه أسماء قديمة تشير إليها
enum DSFieldMetrics {
    /// كم يقصر صندوق الحقل داخل المربّعات (٤٦ ← ٤٠)
    static let boxHeightReduction: CGFloat = fieldHeight - DSBox.fieldMinHeight
    /// الحشوة الرأسية لصندوق الحقل/الصف داخل المربّعات (بدل ٨)
    static let boxVerticalPadding: CGFloat = DSBox.fieldVerticalPadding
    /// أيقونة الحقل داخل المربّعات (بدل ٣٢)
    static let boxIconSize: CGFloat = DSBox.fieldIcon
    /// ارتفاع صندوق الحقل في الصفحات (داخل المربّعات أقصر بـ `boxHeightReduction`)
    static let fieldHeight: CGFloat = 46
    /// صفوف «الميلاد ← متوفّى ← الوفاة» وبطاقتا الجنس (في الصفحات؛ داخل المربّعات أقصر بـ `boxHeightReduction`)
    static let dateRowHeight: CGFloat = 58
    static let toggleRowHeight: CGFloat = 52
    static let optionRowHeight: CGFloat = 50
}

private struct DSFieldFontModifier: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    @Environment(\.dsInCenterBox) private var inBox

    func body(content: Content) -> some View {
        // الحجم هنا مقاس Apple لدور (`DSBox.fieldValueSize` ١٧ = Body، `fieldLabelSize` ١٣ = Footnote) — يُرسم
        // بمعامل خط الآيفون نفسه كباقي الأدوار ومقيّداً بنمطه (فحص ٢٠٢٦-١٠-٠٨: كان بلا المعامل فيظهر عنوان
        // الحقل وقيمته أكبر ١١٪ من بقية نص المربّع)
        let base = inBox ? size - DSFieldFont.boxReduction : size
        content.font(DS.Font.plex(base * DS.Font.opticalScale, weight: weight,
                                  relativeTo: DS.Font.textStyle(for: size)))
    }
}

/// خط دور النص للحقل — بنمط Apple للدور (Dynamic Type)، و`boxReduction` داخل المربّعات
struct DSFieldRoleFontModifier: ViewModifier {
    let role: DS.TextRole
    @Environment(\.dsInCenterBox) private var inBox

    func body(content: Content) -> some View {
        content.font(DS.Font.plex(inBox ? role.textSize - DSFieldFont.boxReduction : role.textSize,
                                  weight: role.weight, relativeTo: role.style))
    }
}

extension View {
    /// خط عنوان حقل أو قيمته: حجمه كما هو في الصفحات، وأصغر قليلاً داخل المربّعات بالمنتصف
    func dsFieldFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(DSFieldFontModifier(size: size, weight: weight))
    }
}

/// إطار المربّع الموحّد للحقول داخل البطاقات
struct DSFieldChrome: ViewModifier {
    var minHeight: CGFloat = DSFieldMetrics.fieldHeight
    @Environment(\.dsInCenterBox) private var inBox
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DS.Spacing.md)
            .frame(minHeight: inBox ? minHeight - DSFieldMetrics.boxHeightReduction : minHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.background, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke), lineWidth: DS.Border.width)
            )
    }
}

extension View {
    /// يضع المحتوى داخل مربّع الحقل الموحّد
    func dsFieldChrome(minHeight: CGFloat = DSFieldMetrics.fieldHeight) -> some View {
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
        VStack(alignment: .leading, spacing: DS.Spacing.xs + 1) {
            Text(label)
                .dsFieldFont(DSBox.fieldLabelSize, weight: .heavy)
                .foregroundColor(DS.Color.fieldLabel)
            content()
                .dsFieldFont(DSBox.fieldValueSize)
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
    @Environment(\.dsSection) private var section

    var body: some View {
        Toggle(isOn: $isOn.animation(DS.Anim.snappy)) {
            Text(title)
                .dsFieldFont(.bodyMedium)
                .foregroundColor(DS.Color.textPrimary)
        }
        .tint(tint.dsChrome(in: section))
        .dsFieldChrome()
    }
}

/// عنوان صغير فوق عنصر (مثل مبدّل الجنس) بنفس نمط عناوين الحقول
struct DSFieldLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .dsFieldFont(.label)
            .foregroundColor(DS.Color.fieldLabel)
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
        DSCenterCard(onBackgroundTap: onCancel, title: title, icon: "calendar") {

            DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .environment(\.locale, LanguageManager.shared.locale)

            if let onClear {
                // الزرّ الواحد بدور «ثانوي» الرمادي (كان إطاراً مرسوماً باليد)
                DSButton(L10n.t("بدون تاريخ", "No date"), icon: "calendar.badge.minus", role: .cancel, action: onClear)
            }

            // صفّ أزرار الهيكل الموحّد
            DSBoxButtons {
                Button(L10n.t("حفظ", "Save")) { onDone(date) }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel, action: onCancel)
            }
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
    /// false = الميلاد وحده (إضافة لا تُسجّل وفاة — مثل إضافة ابن/ابنة في شجرة النساء)
    var showsDeceased: Bool = true

    /// رمادي هادئ لحالة الوفاة (طلب المالك)
    private let deceasedTint = DS.Color.textSecondary
    @Environment(\.dsInCenterBox) private var inBox
    @Environment(\.dsSection) private var section

    var body: some View {
        // كل حقل في مربّع منفصل (طلب المالك)
        VStack(spacing: DS.Spacing.sm) {
            dateRow(icon: "gift.fill", tint: DS.Color.warning,
                    title: L10n.t("تاريخ الميلاد", "Birth Date"),
                    has: $hasBirthDate, date: $birthDate)
                .modifier(BoxChrome(fill: DS.Color.background, stroke: DS.Color.textTertiary.opacity(DS.Opacity.tintFillStrong)))

            // «متوفّى» — لون مميّز
            if showsDeceased {
                Toggle(isOn: $isDeceased.animation(DS.Anim.snappy)) {
                    HStack(spacing: DS.Spacing.sm) {
                        rowIcon("heart.text.square.fill", tint: deceasedTint)
                        Text(deceasedTitle)
                            .dsFieldFont(.headlineCompact)
                            .foregroundColor(deceasedTint)
                    }
                }
                .tint(deceasedTint)
                .padding(.horizontal, DS.Spacing.md)
                .frame(minHeight: inBox ? DSFieldMetrics.toggleRowHeight - DSFieldMetrics.boxHeightReduction
                                        : DSFieldMetrics.toggleRowHeight)
                .modifier(BoxChrome(fill: deceasedTint.opacity(isDeceased ? 0.14 : 0.07),
                                    stroke: deceasedTint.opacity(0.35), solid: false))
            }

            if showsDeceased && isDeceased {
                dateRow(icon: "calendar.badge.minus", tint: deceasedTint,
                        title: L10n.t("تاريخ الوفاة", "Death Date"),
                        has: $hasDeathDate, date: $deathDate)
                    .modifier(BoxChrome(fill: DS.Color.background, stroke: DS.Color.textTertiary.opacity(DS.Opacity.tintFillStrong)))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private struct BoxChrome: ViewModifier {
        let fill: Color
        let stroke: Color
        /// السطح معتم (انظر `DSClaySkin.solid`)
        var solid: Bool = true
        func body(content: Content) -> some View {
            content
                .background(fill, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(stroke, lineWidth: DS.Border.width)
                )
                .trialCardSkin(radius: DS.Radius.md, solid: solid)
        }
    }

    // لون الصف كما هو (الرمادي = متوفى، الكهرماني = الميلاد) — رسم الاتجاه بنفس الحجم
    private func rowIcon(_ name: String, tint: Color) -> some View {
        DSStateIcon(name, tint: tint, size: DSBox.alertIcon, mapsChrome: false)
    }

    /// صف تاريخ: العنوان والقيمة، ثم زر «بدون تاريخ» وقلم التعديل داخل الصف
    private func dateRow(icon: String, tint: Color, title: String,
                         has: Binding<Bool>, date: Binding<Date>) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            rowIcon(icon, tint: tint)

            Button { pick(title: title, has: has, date: date) } label: {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title)
                        .dsFieldFont(.sectionTitle)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(has.wrappedValue ? DSDateText.display(date.wrappedValue)
                                          : L10n.t("بدون تاريخ", "No date"))
                        .dsFieldFont(has.wrappedValue ? .bodySemibold : .body)
                        .foregroundColor(has.wrappedValue ? DS.Color.textPrimary : DS.Color.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // «بدون تاريخ» — الشريحة الواحدة داخل صف التاريخ (مختارة = كحلي القسم إذا لا تاريخ)
            DSChipButton(L10n.t("بدون تاريخ", "No date"), isSelected: !has.wrappedValue, size: .small) {
                withAnimation(DS.Anim.snappy) { has.wrappedValue = false }
            }

            Button { pick(title: title, has: has, date: date) } label: {
                Image(systemName: has.wrappedValue ? "pencil" : "plus")
                    .dsGlyph(DS.Glyph.mdCompact)
                    .foregroundColor(DS.Color.primary.dsChrome(in: section))
                    .frame(width: DS.Icon.discSmall, height: DS.Icon.discSmall)
                    .background(Circle().fill(DS.Color.primary.dsChrome(in: section).opacity(DS.Opacity.tintFill)))
            }
            .buttonStyle(DSScaleButtonStyle())
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(minHeight: inBox ? DSFieldMetrics.dateRowHeight - DSFieldMetrics.boxHeightReduction
                                : DSFieldMetrics.dateRowHeight)
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
    /// نجمة «مطلوب» الحمراء بجانب العنوان (مثل حقول التسجيل) — الاختيار الفارغ «» = لا شيء محدّد
    var required: Bool = false
    @Environment(\.dsInCenterBox) private var inBox

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            HStack(spacing: DS.Spacing.xxs) {
                DSFieldLabel(text: L10n.t("الجنس", "Gender"))
                if required {
                    Text(verbatim: "*")
                        .dsFieldFont(.label)
                        .foregroundColor(DS.Color.error)
                        .accessibilityLabel(L10n.t("مطلوب", "Required"))
                }
            }
            HStack(spacing: DS.Spacing.sm) {
                option("male", title: L10n.t("ذكر", "Male"),
                       icon: "figure.stand", tint: DS.Color.male)
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
                Image(dsSymbol: icon)
                    .dsGlyph(DS.Glyph.lg)
                Text(title)
                    .dsFieldFont(.headlineCompact)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .dsGlyph(DS.Glyph.lgCompact, weight: .semibold)
            }
            .foregroundColor(selected ? tint : DS.Color.textSecondary)
            .padding(.horizontal, DS.Spacing.md)
            // حدّ أدنى يطول مع «حجم النص» في الجهاز (كان ارتفاعاً ثابتاً يضيق على «ذكر/أنثى» بالخط الكبير)
            .frame(minHeight: inBox ? DSFieldMetrics.optionRowHeight - DSFieldMetrics.boxHeightReduction
                                    : DSFieldMetrics.optionRowHeight)
            .background(selected ? tint.opacity(DS.Opacity.tintFill) : DS.Color.background,
                        in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(selected ? tint.opacity(DS.Opacity.selectedStroke)
                                     : DS.Color.textTertiary.opacity(DS.Opacity.tintFillStrong),
                            lineWidth: selected ? DS.Border.widthBold : DS.Border.width)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// الجنس للقراءة فقط — حين يكون تغييره ليس لصاحب المربّع (تغيير جنس الابن ينقله بين
/// الشجرة العامة وشجرة النساء، فهو لمن يعدّل الشجرة فقط، مثل أندرويد)
struct DSGenderReadOnlyRow: View {
    let gender: String

    var body: some View {
        let female = gender.lowercased() == "female"
        DSRow(icon: female ? "figure.stand.dress" : "figure.stand",
              tint: female ? DS.Color.likeAction : DS.Color.male,
              title: L10n.t("الجنس", "Gender"),
              subtitle: female ? L10n.t("أنثى", "Female") : L10n.t("ذكر", "Male")) {
            Image(systemName: "lock.fill")
                .dsGlyph(DS.Glyph.sm)
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.t("تغيير الجنس للإدارة فقط", "Only the administration can change gender"))
    }
}

// MARK: - تعبئة أزرار الإجراء (طلب المالك)

/// نفس تدرّج زر «طلب تعديل» — كحلي عميق في الوضع الداكن بدل الأزرق الفاتح.
/// «كل قسم بلونه»: التدرّج بلون قسم التبويب الذي يُرسم فيه الزر (iOS 17+ يُقرأ من البيئة
/// عند الرسم — بلا أي تعديل في أماكن الاستخدام)، وكحلي العلامة خارج التبويبات.
/// `enabled: false` يخفّته للزر المعطّل.
enum DSActionFill {
    /// شفافية الزر المعطّل (التعبئة ثم النص) — المربّعات تطبّقها على الطبقة فيتحرّك
    /// الانتقال معطّل ↔ ممكن بسلاسة، بنفس الشكل تماماً
    static let disabledOpacity: Double = 0.45
    static let labelDisabledOpacity: Double = 0.5

    static func style(enabled: Bool = true) -> AnyShapeStyle {
        let opacity = enabled ? 1 : disabledOpacity
        // بلا بيئة قسم (نافذة مستقلّة مثلاً): القسم المختار، وإلا كحلي العلامة
        let fallback = AppSection.current?.gradient ?? DS.Color.gradientPrimary
        if #available(iOS 17.0, *) {
            return AnyShapeStyle(DSSectionActionStyle(fallback: fallback, opacity: opacity))
        }
        return AnyShapeStyle(fallback.opacity(opacity))
    }

    /// نص الزر الكحلي — يخفت مع التعطيل؛ بالوضع الداكن كان الأبيض الكامل يوحي أنه مفعّل
    static func label(enabled: Bool = true) -> Color {
        .white.opacity(enabled ? 1 : labelDisabledOpacity)
    }
}

/// تدرّج الإجراء يُحلّ عند الرسم من بيئة الزر (`dsActionGradient` يضعه `.dsSection`)
@available(iOS 17.0, *)
nonisolated private struct DSSectionActionStyle: ShapeStyle {
    let fallback: LinearGradient
    let opacity: Double

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        (environment.dsActionGradient ?? fallback).opacity(opacity)
    }
}
